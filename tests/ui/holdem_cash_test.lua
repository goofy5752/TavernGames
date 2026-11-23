local Wow = require("wow")

-- Stage F3, Task 11: the UI of a cash Холдем: the model's `cash`, the panel „Сметка на масата“
-- (ui/games/HoldemCashView.lua), „Вход“ / „Докупи“, „Стани“ at a cash table, the bill, the headers.
local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"

local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = A .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

local E = guildWow().ns.Engines.holdem
local H = require("holdem")(E)

-- A staked table of three seats (blinds 10, rebuy "top"); buys[seat] chips bought at once.
local function table3(buys)
  local st = E.new{ seats = { true, true, true }, opt = { rebuy = "top", blinds = 10 }, staked = true, names = { A, B, C } }
  for seat, n in pairs(buys or {}) do ok(E.apply(st, seat, { k = "buy", n = n })) end
  return st
end
-- ... and one hand played out by checking (seat 1 takes 10 from each of seats 2 and 3).
local function played()
  local st = table3({ 1000, 1000, 1000 })
  ok(E.apply(st, 0, { k = "hand" })); ok(E.apply(st, 0, { k = "deal", deck = E.DECK }))
  H.checkdown(st)
  return st
end
local function sess(st, seat, extra)
  local s = { game = "holdem", status = "live", mySeat = seat, role = seat == 1 and "host" or "player",
    seats = { A, B, C, false, false, false }, state = st and E.view(st, seat or 0), tid = "t#1", epoch = 1, seq = 1, stake = 1000 }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

local function setup()
  local w = guildWow()
  local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent)
  parent:SetSize(732, 440)
  local View = w.ns.TableFrame.views.holdem
  local f = View.build(parent)
  local bought = {}
  w.ns.client.buy = function(_, n) bought[#bought + 1] = n; return true end
  return w, View, f, bought
end

local function plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

describe("ui: the model of a cash Холдем", function()
  it("the model of a staked table has the three views and a fun one none", function()
    local w = setup()
    local M = w.ns.HoldemModel
    local st = played()
    local m = M.build(sess(st, 1))
    eq(m.cash.mode, "top")
    eq(m.cash.mine, { { seat = 2, name = B, took = 10, gave = 0, net = 10 }, { seat = 3, name = C, took = 10, gave = 0, net = 10 } })
    eq(m.cash.all, { { seat = 1, name = A, bought = 1000, chips = 1020, net = 20 }, { seat = 2, name = B, bought = 1000, chips = 990, net = -10 },
                     { seat = 3, name = C, bought = 1000, chips = 990, net = -10 } })
    -- from the other side: seat 2 gave to seat 1
    eq(M.build(sess(st, 2)).cash.mine[1], { seat = 1, name = A, took = 0, gave = 10, net = -10 })
    -- a full seat may not buy: no range
    eq({ m.cash.lo, m.cash.hi }, { nil, nil })
    local fun = E.new{ seats = { true, true, true } }
    eq(M.build(sess(fun, 1, { stake = nil })).cash, nil)
  end)

  it("the range is the engine's, nil inside my hand and while my stake is still asked (H15b, H15c)", function()
    local w = setup()
    local M = w.ns.HoldemModel
    local st = table3({ [1] = 400 })
    eq({ M.build(sess(st, 1)).cash.lo, M.build(sess(st, 1)).cash.hi }, { 1, 600 })
    eq(M.build(sess(table3(), 1)).cash.lo, 400)
    eq(M.build(sess(st, 1, { stakeAsk = true })).cash.lo, nil)
    local hand = table3({ 1000, 1000, 1000 })
    ok(E.apply(hand, 0, { k = "hand" })); ok(E.apply(hand, 0, { k = "deal", deck = E.DECK }))
    eq(M.build(sess(hand, 1)).cash.lo, nil)
    eq(M.build(sess(hand, 1)).cash.all[1].bought, 1000)
    -- a watcher has no pairs and no range
    local m = M.build(sess(st, nil))
    eq({ #m.cash.mine, m.cash.lo }, { 0, nil })
  end)
end)

-- F3-F Minor 12: a chair that changed hands shows its record's own name, not the last hand's.
describe("ui: the names of „Сметка“", function()
  it("a newcomer's zeros are under the newcomer's name before the next hand", function()
    local w = setup()
    local M = w.ns.HoldemModel
    local st = played()
    ok(E.apply(st, 0, { k = "leave", seat = 3 })); ok(E.apply(st, 0, { k = "join", seat = 3, who = "Нов Играч" }))
    local s = sess(st, 1, { seats = { A, B, "Нов Играч", false, false, false }, handNames = { A, B, C } })
    local m = M.build(s)
    eq(m.cash.all[3], { seat = 3, name = "Нов Играч", bought = 0, chips = 0, net = 0 })
    eq(m.cash.mine[2], { seat = 3, name = "Нов Играч", took = 0, gave = 0, net = 0 })
    eq(m.cash.all[2].name, B)
  end)

  it("a watcher's panel opens on „Всички“: „Ти срещу всеки“ is empty for it", function()
    local w, View, f = setup()
    View.update(f, sess(played(), nil))
    w:click(f.cash.button)
    ok(f.cash.panel:IsShown()); eq(f.cash.tab, 2)
    View.update(f, sess(played(), 1)) -- a seated player's stays where it is
    eq(f.cash.tab, 2)
  end)
end)

describe("ui: the line of a hand", function()
  local function ev(last, names)
    return { tid = "t#1", game = "holdem", opt = { rebuy = "top" }, n = last.hand, last = last, chips = {},
             names = names or { A, "Nadya", "Kiro" }, at = 1 }
  end

  it("the line of a hand names the winner, the hand and where each silver came from", function()
    local w = setup()
    local V = w.ns.HoldemCashView
    local e = ev({ hand = 36, took = { [3] = { [1] = 40, [2] = 80 } }, cat = { [3] = 3 }, shown = { 3, 1 }, won = { [3] = 150 } })
    eq(V.line(w.ns.client, e), "#36 Kiro взе 1g 20s с две двойки (40s от теб, 80s от Nadya)")
    -- everybody else folded: no hand to name
    e = ev({ hand = 37, took = { [2] = { [1] = 10, [3] = 5 } }, cat = {}, shown = {}, won = { [2] = 30 } })
    eq(V.line(w.ns.client, e), "#37 Nadya взе 15s (10s от теб, 5s от Kiro)")
  end)

  it("a split pot gives one line per winner", function()
    local w = setup()
    local V = w.ns.HoldemCashView
    local e = ev({ hand = 8, took = { [1] = { [3] = 25 }, [2] = { [3] = 25 } }, cat = { [1] = 5, [2] = 5 }, shown = { 1, 2 } })
    eq(V.line(w.ns.client, e), "#8 Иван взе 25s с кента (25s от Kiro)\n#8 Nadya взе 25s с кента (25s от Kiro)")
  end)

  it("a voided hand says so", function()
    local w = setup()
    eq(w.ns.HoldemCashView.line(w.ns.client, ev({ hand = 5, void = true })), "#5 анулирана, чиповете са върнати")
  end)

  it("the lines of a table are the newest 30, kept for this run, only for a staked table", function()
    local w = setup()
    local V, client = w.ns.HoldemCashView, w.ns.client
    eq(V.lines("t#1"), {})
    for n = 1, 33 do
      client.events:emit("hand", ev({ hand = n, took = { [3] = { [1] = 10 } }, cat = { [3] = 2 }, shown = { 3, 1 } }))
    end
    local lines = V.lines("t#1")
    eq(#lines, 30); eq(lines[1], "#33 Kiro взе 10s с двойка (10s от теб)"); eq(lines[30]:sub(1, 3), "#4 ")
    eq(V.lines("other#1"), {})
    -- a fun table's hand (no matrix, no rebuy mode) leaves no line
    local fun = ev({ hand = 1, cat = { [1] = 2 }, shown = { 1 } })
    fun.tid, fun.opt = "fun#1", { betting = "nl" }
    client.events:emit("hand", fun)
    eq(V.lines("fun#1"), {})
    -- the panel's third tab shows them
    local _, View, f = setup()
    View.update(f, sess(played(), 1))
    eq(f.cash.panel:IsShown(), false)
  end)
end)

describe("ui: „Сметка“ and the buy-in on the felt", function()
  it("„Вход“ before my first buy, „Докупи“ when the mode allows, neither inside my hand nor while my stake is still asked", function()
    local w, View, f = setup()
    View.update(f, sess(table3(), 1))
    ok(f.cash.buy:IsShown()); eq(f.cash.buy.text:GetText(), "Вход")
    View.update(f, sess(table3({ [1] = 400 }), 1))
    ok(f.cash.buy:IsShown()); eq(f.cash.buy.text:GetText(), "Докупи")
    View.update(f, sess(table3({ [1] = 1000 }), 1))
    eq(f.cash.buy:IsShown(), false)
    local hand = table3({ 1000, 400, 1000 })
    ok(E.apply(hand, 0, { k = "hand" })); ok(E.apply(hand, 0, { k = "deal", deck = E.DECK }))
    View.update(f, sess(hand, 2))
    eq(f.cash.buy:IsShown(), false)
    View.update(f, sess(table3(), 1, { stakeAsk = true }))
    eq(f.cash.buy:IsShown(), false)
    -- a fun table has neither button
    local fun = E.new{ seats = { true, true, true } }
    View.update(f, sess(fun, 1, { stake = nil }))
    eq({ f.cash.button:IsShown(), f.cash.buy:IsShown() }, { false, false })
  end)

  it("the stepper stays inside the range and „Потвърди“ buys", function()
    local w, View, f, bought = setup()
    View.update(f, sess(table3({ [1] = 400 }), 1)) -- may buy 1..600; a step is 10 big blinds = 100 chips
    w:click(f.cash.buy)
    ok(f.cash.buyBox:IsShown(), "no stepper"); eq(f.cash.amount:GetText(), "6g")
    w:click(f.cash.minus); eq(f.cash.amount:GetText(), "5g")
    for _ = 1, 9 do w:click(f.cash.minus) end
    eq(f.cash.amount:GetText(), "1s") -- the low end is reached
    for _ = 1, 3 do w:click(f.cash.plus) end
    eq(f.cash.amount:GetText(), "3g 1s")
    for _ = 1, 9 do w:click(f.cash.plus) end
    eq(f.cash.amount:GetText(), "6g") -- and the high end
    w:click(f.cash.minus); w:click(f.cash.minus)
    w:click(f.cash.confirm)
    eq(bought, { 400 })
    eq(f.cash.buyBox:IsShown(), false)
    -- the first buy: 40 big blinds up to 100
    View.update(f, sess(table3(), 1))
    w:click(f.cash.buy)
    eq(f.cash.amount:GetText(), "10g")
    for _ = 1, 9 do w:click(f.cash.minus) end
    eq(f.cash.amount:GetText(), "4g")
    w:click(f.cash.confirm)
    eq(bought, { 400, 400 })
  end)

  it("a range that moves under the open stepper clamps it; losing the range closes it", function()
    local w, View, f = setup()
    View.update(f, sess(table3({ [1] = 400 }), 1))
    w:click(f.cash.buy)
    eq(f.cash.amount:GetText(), "6g")
    View.update(f, sess(table3({ [1] = 800 }), 1))
    eq(f.cash.amount:GetText(), "2g")
    View.update(f, sess(table3({ [1] = 1000 }), 1))
    eq(f.cash.buyBox:IsShown(), false)
  end)

  it("the panel has three tabs: against each, all, the hands", function()
    local w, View, f = setup()
    local st = played()
    View.update(f, sess(st, 1))
    w:click(f.cash.button)
    ok(f.cash.panel:IsShown()); eq({ f.cash.panel:GetSize() }, { 268, 300 })
    eq(plain(f.cash.title:GetText()), "Сметка на масата")
    eq({ f.cash.tabs[1].text:GetText(), f.cash.tabs[2].text:GetText(), f.cash.tabs[3].text:GetText() }, { "Ти срещу всеки", "Всички", "Ръце" })
    local function rows()
      local out = {}
      for _, r in ipairs(f.cash.rows) do
        if r.frame:IsShown() then
          local cells = {}
          for _, c in ipairs(r.cells) do if c:IsShown() then cells[#cells + 1] = plain(c:GetText()) end end
          out[#out + 1] = cells
        end
      end
      return out
    end
    eq(rows()[1], { "", "взел от теб", "взел си", "нето" })
    eq(rows()[2], { "Мария", "0c", "10s", "10s" })
    eq(rows()[3], { "Kiro", "0c", "10s", "10s" })
    w:click(f.cash.tabs[2])
    eq(rows()[1], { "", "вход", "чипове", "нето" })
    eq(rows()[2], { "Иван", "10g", "10g 20s", "20s" })
    eq(rows()[3], { "Мария", "10g", "9g 90s", "-10s" })
    w:click(f.cash.tabs[3])
    eq(rows(), { { "" } }) -- no hand heard yet
    w.ns.client.events:emit("hand", { tid = "t#1", game = "holdem", opt = { rebuy = "top" }, n = 1, at = 1, chips = {}, names = { A, B, C },
      last = { hand = 1, took = { [1] = { [2] = 10, [3] = 10 } }, cat = { [1] = 6 }, shown = { 1, 2, 3 } } })
    View.update(f, sess(st, 1))
    eq(rows()[1], { "#1 Иван взе 20s с флош (10s от Мария, 10s от Kiro)" })
    w:click(f.cash.button)
    eq(f.cash.panel:IsShown(), false)
  end)
end)

describe("ui: „Стани“ at a cash table", function()
  -- My own staked table (an open session), my cash-out pending: the real client's flow is Task 8's.
  local function world()
    local w = guildWow()
    w.ns.MainWindow.show()
    local client = w.ns.client
    assert(client:openTable{ game = "holdem", access = "guild", turn = 45, stake = 1000, opt = { blinds = 10 } })
    w:advance(0)
    local shown, realShow = {}, w.ns.MainWindow.show
    w.ns.MainWindow.show = function(tab) shown[#shown + 1] = tab or false; return realShow(tab) end
    w.ns.CashOut.owes = function() return true end
    return w, client, shown
  end

  it("„Стани“ at a cash table keeps the table open until the cashout, then goes to the hall", function()
    local w, client, shown = world()
    local TF, s = w.ns.TableFrame, client.session
    local real, calls = client.stand, {}
    client.stand = function(_, now) -- the real client waits for the cash-out: it says cashGoing and keeps my table
      calls[#calls + 1] = now == true
      client.cashGoing = { tid = s.tid, at = 0 }
      client.events:emit("cashGoing", s.tid)
    end
    TF.stand(); w:advance(0)
    eq(calls, { false }); ok(client.session == s, "the table stays"); eq(shown, {})
    ok(TF.frame:IsShown(), "the frame stays")
    eq(plain(TF.view.line:GetText()), "Ставаш след края на ръката. Сметката ти се записва.")
    eq(TF.view.standButton.text:GetText(), "Стани веднага")
    -- the cash-out is applied: my session ends and the hall shows
    client.cashGoing = nil
    real(client, true); client.events:emit("cashGoing", nil); w:advance(0)
    eq(client.session, nil); eq(shown[#shown], "hall")
  end)

  it("when the host never applies my cash-out „Стани веднага“ stands at once", function()
    local w, client, shown = world()
    local TF, s = w.ns.TableFrame, client.session
    local real, calls = client.stand, {}
    client.stand = function(self, now) calls[#calls + 1] = now == true; return real(self, now) end
    client.cashGoing = { tid = s.tid, at = 0 }; client.events:emit("cashGoing", s.tid); w:advance(0)
    eq(TF.view.standButton.text:GetText(), "Стани веднага")
    TF.stand(); w:advance(0)
    eq(calls, { true }); eq(client.session, nil); eq(shown[#shown], "hall")
  end)

  it("standing up at a cash table asks no forfeit question", function()
    local w, client = world()
    local s = client.session
    s.status = "live"
    ok(w.ns.Engines.holdem.cashGame, "the engine says cash")
    eq(w.ns.TableFrame.standCosts(s), false)
  end)
end)

describe("ui: the stake of a cash table in the headers", function()
  it("the table frame writes the blinds, the invitation too; the rebuy line of an unlisted table is not empty", function()
    local w = guildWow()
    local client = w.ns.client
    assert(client:openTable{ game = "holdem", access = "guild", turn = 45, stake = 2000, opt = { blinds = 20 } })
    w:advance(0)
    local v = w.ns.TableFrame.view
    eq(v.stake:GetText(), "Блайндове: 10s/20s")
    ok(not v.meta:GetText():find("Блайндове", 1, true), "the blinds twice: " .. v.meta:GetText()) -- F3-F Minor 13
    client.stand(client, true); w:advance(0)
    w:member(B)
    w:deliver("WHISPER", B, { v = 1, t = "INV", tid = B .. "#1", g = "holdem", h = B, s = { B, false, false, false, false, false }, sk = 1000 })
    w:advance(0)
    local T = w.ns.InviteToast
    ok(T.frame:IsShown(), "no toast"); eq(T.stake:GetText(), "Блайндове: 5s/10s")
    w:click(T.accept)
    local P = w.ns.StakePanels
    ok(P.askFrame:IsShown(), "no question")
    ok(P.askLeave:GetText() ~= "", "the rebuy line is empty")
    eq(P.askLeave:GetText(), w.ns.L("stake.ask.rebuy.unknown"))
  end)
end)

describe("ui: the tab „Тефтер“ of a cash debt", function()
  it("a debt of the debtor's own word for Холдем reads „Холдем“, another reads its game", function()
    local w = guildWow()
    w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
    local net = w.ns.client.ledgerNet
    net:make("D", { gid = "t#1/1", g = "holdem", f = A, t = B, c = 1500, why = "cash" })
    net:make("D", { gid = "t#1/2", g = "holdem", f = A, t = C, c = 1500, why = "lost" })
    w:advance(1); w:advance(0)
    local what = {}
    for _, l in ipairs(w.ns.LedgerTab.lines(w.ns.client)) do what[l.debt.gid] = l.what end
    eq(what, { ["t#1/1"] = "Холдем", ["t#1/2"] = "Тексас Холдем" })
  end)
end)

describe("ui: the bill of a cash table", function()
  -- The table is over (closed): my client's note of a settlement, the cashout event heard.
  local function bill(note, why)
    local w = guildWow()
    local client, P = w.ns.client, w.ns.StakePanels
    local tid = "t#1"
    local s = sess(played(), 1, { tid = tid, status = "live" })
    s.state.phase = "closed"
    s.engine = function() return w.ns.Engines.holdem end
    s.gameOver = function() return true end
    s.seatedCount = function() return 3 end
    client.session = s
    local gid = tid .. "/7"
    local base = { at = 1, g = "holdem", sk = 1000, why = "cash", tid = tid, q = 7,
      pairs = { { f = A, t = B, c = 1500 } } }
    for k, v in pairs(note) do base[k] = v end
    client.stakes:seen(true)[gid] = base
    client.events:emit("cashout", { tid = tid, gid = gid, seat = 2, name = B, chips = 0, bought = 0, pairs = base.pairs, why = why, at = 1 })
    local v = { area = w.G.CreateFrame("Frame", nil, w.G.UIParent) }
    P.bill(v, s)
    return w, v.bill, base
  end

  it("the bill of a cash-out lists the pairs and says it waits for the keys", function()
    local w, b = bill({ wait = true }, "left")
    ok(b:IsShown(), "no bill")
    eq(plain(b.lines[1].text:GetText()), "Мария стана от масата. Сметката по двойки:")
    eq(plain(b.lines[2].text:GetText()), "Ръцете се проверяват с ключовете. Остани на масата, за да се потвърди сметката ти сама.")
    eq(plain(b.lines[3].text:GetText()), "Иван дължи на Мария 15s")
    eq(b:GetHeight(), 32 + 18 * 4) -- the keys' line is long: it takes two rows
  end)

  it("a close says the game is over; a note that no longer waits has no keys line", function()
    local w, b = bill({}, "close")
    eq(plain(b.lines[1].text:GetText()), "Играта приключи. Сметката по двойки:")
    eq(plain(b.lines[2].text:GetText()), "Иван дължи на Мария 15s")
    eq(b.lines[3] == nil or not b.lines[3].text:IsVisible(), true)
  end)

  it("a note with no pair of mine is no bill and is not the last note (Task 7)", function()
    local w, b = bill({ pairs = {} }, "left")
    eq(b == nil or not b:IsShown(), true)
    local client = w.ns.client
    client.stakes:seen(true)["t#1/6"] = { at = 0, g = "holdem", sk = 1000, why = "cash", tid = "t#1", q = 6, pairs = { { f = A, t = B, c = 1500 } } }
    eq(client.stakes:last("t#1").q, 6)
  end)
end)

describe("ui: the buy-in asks again, and says why it did not go", function()
  it("a floor above my pick (buyLow) opens the stepper at the floor and says so", function()
    local w, View, f = setup()
    local TF = w.ns.TableFrame
    local said = {}
    TF.say = function(text) said[#said + 1] = text; return true end
    View.update(f, sess(table3({ [1] = 400 }), 1)) -- the range is 1..600
    w.ns.client.events:emit("buyLow", 200, 100)
    ok(f.cash.buyBox:IsShown(), "no stepper")
    eq(f.cash.amount:GetText(), "2g")
    eq(plain(said[1]), "Минимумът е вече над избраното: 2g. Избери отново.")
  end)

  it("„Потвърди“ says the refusal of client:buy", function()
    local w, View, f = setup()
    local said = {}
    w.ns.TableFrame.say = function(text) said[#said + 1] = text; return true end
    View.update(f, sess(table3({ [1] = 400 }), 1))
    w.ns.client.buy = function() return nil, "stake" end
    w:click(f.cash.buy); w:click(f.cash.confirm)
    eq(plain(said[1]), "Първо приеми залога на масата.")
    w.ns.client.buy = function() return nil, "zzz" end
    w:click(f.cash.buy); w:click(f.cash.confirm)
    eq(plain(said[2]), "Покупката не мина („zzz“).")
  end)

  -- F3-F Minor 13 / I1: no engine code of a buy or a cash-out is shown raw.
  it("every refusal code of the engine's buy and cashout has its own words", function()
    local w, View, f = setup()
    local said = {}
    w.ns.TableFrame.say = function(text) said[#said + 1] = text; return true end
    View.update(f, sess(table3({ [1] = 400 }), 1))
    local seen = {}
    for i, code in ipairs({ "hand", "phase", "rebuy", "full", "amount", "early", "seat", "live", "none", "stake" }) do
      w.ns.client.buy = function() return nil, code end
      w:click(f.cash.buy); w:click(f.cash.confirm)
      local text = plain(said[i])
      ok(not text:find(code, 1, true) and not text:find("Покупката не мина", 1, true), code .. ": " .. text)
      ok(not seen[text], code .. " repeats another code's words"); seen[text] = true
    end
  end)
end)

describe("ui: the end of my own cash-out", function()
  it("a window I closed stays closed; my own bill is said once from my own note", function()
    local w, client
    do
      w = guildWow()
      w.ns.MainWindow.show()
      client = w.ns.client
      assert(client:openTable{ game = "holdem", access = "guild", turn = 45, stake = 1000, opt = { blinds = 10 } })
      w:advance(0)
    end
    local said, tid = {}, client.session.tid
    w.ns.Hall.say = function(text) said[#said + 1] = plain(text) end
    local calls = {}
    local real = w.ns.MainWindow.show
    w.ns.MainWindow.show = function(tab) calls[#calls + 1] = tab or false; return real(tab) end
    local gid = tid .. "/7"
    client.stakes:seen(true)[gid] = { at = 1, g = "holdem", sk = 1000, why = "cash", tid = tid, q = 7,
      pairs = { { f = client.env.me, t = B, c = 1500 } } }
    client.events:emit("cashout", { tid = tid, gid = gid, seat = 1, name = client.env.me, chips = 0, bought = 0,
      pairs = {}, why = nil, at = 1 })
    w.ns.TableFrame.frame:Hide() -- I closed the window
    client.session = nil
    client.events:emit("cashGoing", nil)
    eq(calls, {})
    eq(#said, 1)
    ok(said[1]:find("Сметката ти: ", 1, true) == 1 and said[1]:find("15s", 1, true), said[1])
    client.events:emit("cashGoing", nil)
    eq(#said, 1) -- once
  end)

  it("the hands of a table that ended are freed", function()
    local w, View, f = setup()
    local client = w.ns.client
    client.events:emit("hand", { tid = "t#9", n = 1, last = { void = true, hand = 1 }, opt = { rebuy = "top" }, names = {} })
    eq(#w.ns.HoldemCashView.lines("t#9"), 1)
    client.events:emit("session", nil)
    eq(#w.ns.HoldemCashView.lines("t#9"), 0)
  end)
end)
