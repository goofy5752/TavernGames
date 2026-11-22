local Wow = require("wow")

local ME, M, S = "Иван Петров", "Мария Колева", "Мария Стоянова"
local M_GUID, S_GUID = "Player-1-00000002", "Player-1-00000003"

-- In a guild of me and Мария Колева (and `more` roster rows), booted, my name resolved.
local function guildWow(more)
  local w = Wow.new()
  w.inGuild = true
  w.roster = {
    { name = ME .. "-Forever", online = true, guid = Wow.GUID },
    { name = M .. "-Forever", online = true, guid = M_GUID },
  }
  for _, m in ipairs(more or {}) do w.roster[#w.roster + 1] = m end
  w:boot()
  w:fire("GUILD_ROSTER_UPDATE")
  return w
end

-- What client.pay:traded was given.
local function tradedLog(w)
  local got = {}
  w.ns.client.pay.traded = function(_, t) got[#got + 1] = t end
  return got
end

-- The trade window opens with the player of `guid` (UnitName("NPC") shows `shown`).
local function shows(w, guid, shown)
  w.npc = { name = shown or "Мария", guid = guid or M_GUID }
  w:fireTrade("TRADE_SHOW")
end

-- Мария is my target, in range, and I press „Трейд“ for `c`.
local function opened(w, c)
  w.units.target, w.near.target = M_GUID, true
  eq(w.ns.Trade.open(M, c), true)
end

-- Both sides put in money and accept, `first` ("target", the default, or "me")
-- first. The game shows both accepts together, (1, 1), only when I accepted
-- after the target: when I accept first, (1, 0) is the last update before the
-- server completes the trade.
local function bothAccept(w, gave, got, first)
  w.tradeMoney = { player = gave, target = got }
  w:fireTrade("TRADE_MONEY_CHANGED")
  if first == "me" then
    w:fireTrade("TRADE_ACCEPT_UPDATE", 1, 0)
  else
    w:fireTrade("TRADE_ACCEPT_UPDATE", 0, 1)
    w:fireTrade("TRADE_ACCEPT_UPDATE", 1, 1)
  end
end

describe("wow trade: state and open", function()
  it("state: no unit, far, ok", function()
    local w = guildWow()
    local T = w.ns.Trade
    eq(T.state(M), "none"); eq(T.state("Петър Никой"), "none")
    w.units.target = M_GUID
    eq(T.state(M), "far")
    w.near.target = true
    eq(T.state(M), "ok")
    w.G.CheckInteractDistance = function() error("combat lockdown") end
    eq(T.state(M), "ok")
    -- In combat the range check is restricted (blocked, not raising): it is not asked.
    local asked = 0
    w.G.CheckInteractDistance = function() asked = asked + 1 end
    w.combat = true
    eq(T.state(M), "ok"); eq(asked, 0)
    w.combat = false
    eq(T.state(M), "far"); eq(asked, 1)
    w.G.CheckInteractDistance = nil
    eq(T.state(M), "ok")
    w.G.InitiateTrade = nil
    eq(T.state(M), "off")
    eq(T.open(M, 50000), nil)
  end)

  it("the unit is the target, then party1..4, then raid1..40, by roster GUID", function()
    local w = guildWow()
    local T = w.ns.Trade
    w.units.target = "Player-1-00000099" -- someone else is targeted
    w.units.party3, w.near.party3 = M_GUID, true
    eq(T.state(M), "ok")
    eq(T.open(M, 100), true); eq(w:argsOf("InitiateTrade"), { "party3" })
    w.units.party3 = nil
    w.units.raid17 = M_GUID
    eq(T.state(M), "far")
    w.near.raid17 = true
    eq(T.open(M, 100), true); eq(w:argsOf("InitiateTrade"), { "raid17" })
  end)

  it("open starts the trade with the unit and fills the amount when it shows", function()
    local w = guildWow()
    opened(w, 50000)
    eq(w:called("InitiateTrade"), 1); eq(w:argsOf("InitiateTrade"), { "target" })
    eq(w:called("C_TradeInfo.SetTradeMoney"), 0)
    shows(w)
    eq(w:called("C_TradeInfo.SetTradeMoney"), 1); eq(w:argsOf("C_TradeInfo.SetTradeMoney"), { 50000 })
    eq(w:called("SetTradeMoney"), 0)
    eq(w.G.TradePlayerInputMoneyFrame.copper, 50000)
    w:fireTrade("TRADE_CLOSED")
    shows(w)
    eq(w:called("C_TradeInfo.SetTradeMoney"), 1); eq(w:called("MoneyInputFrame_SetCopper"), 1)
  end)

  it("a trade the addon did not open is never filled", function()
    local w = guildWow({ { name = S .. "-Forever", online = true, guid = S_GUID } })
    shows(w)
    w:fireTrade("TRADE_CLOSED")
    opened(w, 50000)
    shows(w, S_GUID) -- another player opens a trade with me meanwhile
    w:fireTrade("TRADE_CLOSED")
    eq(w:called("C_TradeInfo.SetTradeMoney"), 0)
    shows(w) -- the trade I opened, within 30 s, is still filled
    eq(w:called("C_TradeInfo.SetTradeMoney"), 1)
    w:fireTrade("TRADE_CLOSED")
    opened(w, 70000)
    w:advance(31)
    shows(w)
    eq(w:called("C_TradeInfo.SetTradeMoney"), 1); eq(w:called("MoneyInputFrame_SetCopper"), 1)
  end)

  it("a blocked set-money call is not an error", function()
    local w = guildWow()
    w.G.C_TradeInfo.SetTradeMoney = function() error("ADDON_ACTION_BLOCKED") end
    opened(w, 50000)
    eq(w:called("InitiateTrade"), 1)
    shows(w)
    eq(w:called("SetTradeMoney"), 0); eq(w:called("MoneyInputFrame_SetCopper"), 0)
    eq(w.G.TradePlayerInputMoneyFrame.copper, 0)
    eq(w.ns.Trade.state(M), "ok")
    eq(w.ns.client.pay:options(M).trade, "ok")
    -- No way to set the money at all: the trade still opens.
    local w2 = guildWow()
    w2.G.C_TradeInfo, w2.G.SetTradeMoney = nil, nil
    opened(w2, 50000)
    shows(w2)
    eq(w2:called("InitiateTrade"), 1); eq(w2:called("MoneyInputFrame_SetCopper"), 0)
  end)

  it("the classic and the modern spelling both work", function()
    local w = guildWow()
    w.G.C_TradeInfo.SetTradeMoney = nil
    opened(w, 50000)
    shows(w)
    eq(w:argsOf("SetTradeMoney"), { 50000 }); eq(w.G.TradePlayerInputMoneyFrame.copper, 50000)
    local w2 = guildWow()
    w2.G.SetTradeMoney = nil
    opened(w2, 60000)
    shows(w2)
    eq(w2:argsOf("C_TradeInfo.SetTradeMoney"), { 60000 }); eq(w2.G.TradePlayerInputMoneyFrame.copper, 60000)
    local w3 = guildWow()
    w3.G.C_TradeInfo = nil
    opened(w3, 70000)
    shows(w3)
    eq(w3:argsOf("SetTradeMoney"), { 70000 })
  end)
end)

describe("wow trade: what arrived", function()
  it("a completed trade is reported with both amounts", function()
    local w = guildWow()
    local got = tradedLog(w)
    shows(w)
    bothAccept(w, 0, 50000)
    eq(#got, 0)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    w:fireTrade("TRADE_CLOSED")
    w:fireTrade("TRADE_CLOSED")
    eq(got, { { name = M, gave = 0, got = 50000, items = false } })
  end)

  it("a completed trade is reported in either accept order", function()
    local w = guildWow()
    local got = tradedLog(w)
    -- I accept first: the last update is (1, 0); the window closes before the completion line.
    shows(w)
    bothAccept(w, 0, 50000, "me")
    w:fireTrade("TRADE_CLOSED")
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    -- I accept first, and the completion line comes before the close.
    shows(w)
    bothAccept(w, 0, 40000, "me")
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    w:fireTrade("TRADE_CLOSED")
    -- The target accepts first: (0, 1), then (1, 1).
    shows(w)
    bothAccept(w, 0, 30000, "target")
    w:fireTrade("TRADE_CLOSED")
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    eq(got, { { name = M, gave = 0, got = 50000, items = false }, { name = M, gave = 0, got = 40000, items = false },
              { name = M, gave = 0, got = 30000, items = false } })
  end)

  it("an error that is not the trade's own does not lose a completed trade", function()
    local w = guildWow()
    local got = tradedLog(w)
    shows(w)
    bothAccept(w, 0, 50000, "me")
    w:fireTrade("TRADE_CLOSED")
    w:fireTrade("UI_ERROR_MESSAGE", 0, "Ability is not ready yet.")
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    eq(got, { { name = M, gave = 0, got = 50000, items = false } })
  end)

  it("the completion may come after the window closed, and with the message as its only argument", function()
    local w = guildWow()
    local got = tradedLog(w)
    shows(w)
    w.tradeMoney = { player = 0, target = 30000 }
    w:fireTrade("TRADE_MONEY_CHANGED")
    w:fireTrade("TRADE_ACCEPT_UPDATE", 0, 1)
    w.tradeMoney = { player = 0, target = 50000 } -- she changes the amount: both accepts are reset
    w:fireTrade("TRADE_MONEY_CHANGED")
    w:fireTrade("TRADE_ACCEPT_UPDATE", 0, 0)
    w:fireTrade("TRADE_ACCEPT_UPDATE", 1, 1)
    w:fireTrade("TRADE_CLOSED") -- the money reads 0 from here on
    w:fireTrade("UI_INFO_MESSAGE", w.G.ERR_TRADE_COMPLETE)
    eq(got, { { name = M, gave = 0, got = 50000, items = false } })
    w:fireTrade("UI_INFO_MESSAGE", w.G.ERR_TRADE_COMPLETE)
    eq(#got, 1)
  end)

  it("the trade partner is resolved by GUID, not by the shown name", function()
    local w = guildWow({ { name = S .. "-Forever", online = true, guid = S_GUID } })
    local got = tradedLog(w)
    shows(w, S_GUID, "Мария")
    bothAccept(w, 0, 20000)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    eq(got, { { name = S, gave = 0, got = 20000, items = false } })
    eq(w.ns.Adapter.nameOfGUID(S_GUID), S); eq(w.ns.Adapter.nameOfGUID(M_GUID), M)
    eq(w.ns.Adapter.nameOfGUID("Player-1-00000099"), nil); eq(w.ns.Adapter.nameOfGUID(nil), nil)
  end)

  it("a cancelled trade reports nothing", function()
    local w = guildWow()
    local got = tradedLog(w)
    shows(w)
    w.tradeMoney = { player = 0, target = 50000 }
    w:fireTrade("TRADE_MONEY_CHANGED")
    w:fireTrade("TRADE_ACCEPT_UPDATE", 0, 1)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE) -- I have not accepted
    w:fireTrade("TRADE_CLOSED")
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE) -- a stray line: no trade is open
    shows(w)
    w.tradeMoney = { player = 0, target = 50000 }
    w:fireTrade("TRADE_MONEY_CHANGED")
    w:fireTrade("UI_ERROR_MESSAGE", 0, w.G.ERR_TRADE_CANCELLED)
    w:fireTrade("TRADE_CLOSED")
    shows(w)
    w:fireTrade("TRADE_MONEY_CHANGED")
    w:fireTrade("TRADE_REQUEST_CANCEL")
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    -- I accepted, the window closed, and the completion never came in time.
    for _, first in ipairs({ "me", "target" }) do
      shows(w)
      bothAccept(w, 0, 50000, first)
      w:fireTrade("TRADE_CLOSED")
      w:advance(5)
      w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    end
    -- I accepted, then the trade failed with the trade's own error.
    for _, first in ipairs({ "me", "target" }) do
      shows(w)
      bothAccept(w, 0, 50000, first)
      w:fireTrade("UI_ERROR_MESSAGE", 0, w.G.ERR_TRADE_BAG_FULL)
      w:fireTrade("TRADE_CLOSED")
      w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    end
    eq(got, {})
  end)

  it("an item on either side sets items = true", function()
    local w = guildWow()
    local got = tradedLog(w)
    shows(w)
    w:fireTrade("TRADE_PLAYER_ITEM_CHANGED", 1)
    bothAccept(w, 0, 50000)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    w:fireTrade("TRADE_CLOSED")
    shows(w)
    w:fireTrade("TRADE_TARGET_ITEM_CHANGED", 7) -- the "will not be traded" slot counts too
    bothAccept(w, 0, 50000)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    w:fireTrade("TRADE_CLOSED")
    eq(got, { { name = M, gave = 0, got = 50000, items = true }, { name = M, gave = 0, got = 50000, items = true } })
  end)

  it("a trade with a stranger reports nothing", function()
    local w = guildWow()
    local got = tradedLog(w)
    shows(w, "Player-1-00000099", "Странник")
    bothAccept(w, 0, 50000)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    w:fireTrade("TRADE_CLOSED")
    w.npc = { name = "Мария" } -- no GUID at all
    w:fireTrade("TRADE_SHOW")
    bothAccept(w, 0, 50000)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    eq(got, {})
  end)

  it("unreadable money reports nothing", function()
    local w = guildWow()
    local got = tradedLog(w)
    w.G.GetPlayerTradeMoney, w.G.GetTargetTradeMoney = nil, nil
    shows(w)
    bothAccept(w, 0, 50000)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    w.G.GetPlayerTradeMoney, w.G.GetTargetTradeMoney = function() return "?" end, function() error("no trade") end
    shows(w)
    bothAccept(w, 0, 50000)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    eq(got, {})
  end)

  it("the amounts read once I accepted stay when the money reads 0 at the end", function()
    local w = guildWow()
    local got = tradedLog(w)
    for _, first in ipairs({ "me", "target" }) do
      shows(w)
      bothAccept(w, 0, 50000, first)
      w.tradeMoney = { player = 0, target = 0 }
      w:fireTrade("TRADE_MONEY_CHANGED")
      w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    end
    eq(got, { { name = M, gave = 0, got = 50000, items = false }, { name = M, gave = 0, got = 50000, items = false } })
  end)

  it("the forbidden functions are never called", function()
    local w = guildWow()
    local got = tradedLog(w)
    opened(w, 50000)
    shows(w)
    bothAccept(w, 50000, 0)
    w:fireTrade("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE)
    w:fireTrade("TRADE_CLOSED")
    eq(got, { { name = M, gave = 50000, got = 0, items = false } })
    for name in pairs(w.forbidden) do eq(w:called(name), 0, name) end
    eq(w:called("AcceptTrade"), 0)
  end)
end)

describe("wow trade: the client's env", function()
  it("env.money, env.trade, env.mail and env.date come from the game", function()
    local w = guildWow()
    local env = w.ns.client.env
    w.money = 123456
    eq(env.money(), 123456)
    ok(env.trade == w.ns.Trade, "env.trade"); ok(env.mail == w.ns.Mail, "env.mail")
    eq(env.date(1700000000), { d = 14, m = 11, day = 19675 })
    eq(env.date(1700000000).day, math.floor(1700000000 / 86400))
    eq(env.date(951782400), { d = 29, m = 2, day = 11016 }) -- 2000-02-29
    w.G.date = nil
    eq(env.date(1700000000), w.ns.Pay.utc(1700000000))
    eq(w.ns.client.pay:options(M), { trade = "none", mail = "closed", fee = 30, short = 0 })
  end)
end)
