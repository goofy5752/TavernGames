local Wow = require("wow")

local ME, B = "Иван Петров", "Мария Стоянова"
local BOTS = { "Бот Иванов", "Bot Barleybrew", "Бот Петрова" }

local function guildWow(saved)
  local w = Wow.new{ saved = saved }
  w.inGuild = true
  w.roster = {
    { name = B .. "-Forever", online = true, guid = "Player-1-00000002" },
    { name = ME .. "-Forever", online = true, guid = Wow.GUID },
  }
  w:boot()
  w:fire("GUILD_ROSTER_UPDATE")
  return w
end

-- Does any string anywhere in `msg` equal one of `words`?
local function mentions(msg, words)
  if type(msg) == "string" then
    for i = 1, #words do
      if msg == words[i] then return true end
    end
    return false
  end
  if type(msg) ~= "table" then return false end
  for k, v in pairs(msg) do
    if mentions(k, words) or mentions(v, words) then return true end
  end
  return false
end

describe("/tavern", function()
  it("opens the main window and the intro when they exist, else prints the help", function()
    local w = guildWow()
    local L = w.ns.L
    w:slash(""); eq(#w:chatWith(L("slash.help")), 1)
    w:slash("nonsense"); eq(#w:chatWith(L("slash.help")), 2)
    local calls = {}
    w.ns.MainWindow = { toggle = function() calls[#calls + 1] = "toggle" end }
    w.ns.Intro = { start = function(force) calls[#calls + 1] = force end }
    w:slash(""); w:slash("intro"); w:slash("  INTRO  ")
    eq(calls, { "toggle", true, true })
  end)

  it("reset clears lang and introDone only", function()
    local w = guildWow()
    local db = w.ns.db
    db.lang, db.introDone, db.busy = "en", true, true
    w:slash("reset")
    eq(db.lang, nil); eq(db.introDone, nil); eq(db.busy, true)
    eq(#w:chatWith(w.ns.L("reset.done")), 1)
  end)

  it("debug toggles db.debug and prints trace lines to the chat frame only while on", function()
    local w = guildWow()
    local c = w.ns.client
    w:slash("debug"); eq(w.ns.db.debug, true)
    local n = #w.chat
    c:send("WHISPER", B, { v = 1, t = "EV", tid = "x", q = 7 })
    local out = w:chatWith("TAVG > WHISPER " .. B .. " ", n + 1)
    eq(#out, 1); ok(out[1]:find('t="EV"', 1, true), out[1]); ok(out[1]:find("q=7", 1, true), out[1])
    w:deliver("GUILD", B .. "-Forever", { v = 1, t = "HI", ver = "0.1.0", cls = "MAGE", id = "Player-1-00000002" })
    eq(#w:chatWith("TAVG < GUILD " .. B .. " ", n + 1), 1)
    w:slash("debug"); eq(w.ns.db.debug, false)
    n = #w.chat
    c:send("WHISPER", B, { v = 1, t = "EV", tid = "x", q = 8 })
    eq(#w:chatWith("TAVG", n + 1), 0)
  end)

  it("debug stays on after a reload", function()
    local w = guildWow()
    w:slash("debug"); w:fire("PLAYER_LOGOUT")
    local w2 = guildWow(w.G.TavernGamesDB)
    local n = #w2.chat
    w2.ns.client:send("WHISPER", B, { v = 1, t = "EV", tid = "x", q = 1 })
    eq(#w2:chatWith("TAVG > WHISPER", n + 1), 1)
  end)

  it("bots toggles three bots that never reach the guild channel; host and invite turn them on", function()
    local w = guildWow()
    local c = w.ns.client
    w:slash("bots"); ok(w.ns.bots, "no bots"); w:advance(1)
    for _, name in ipairs(BOTS) do ok(c.presence:get(name), "missing bot " .. name) end
    w:slash("bots host"); w:advance(1)
    eq(#c.lobby:tables(), 1)
    for _, s in ipairs(w.sent) do ok(not mentions(s.msg, BOTS), "a bot name went out for real") end
    w:slash("bots"); eq(w.ns.bots, nil)
    ok(not c.presence:get("Бот Иванов"), "bot still present"); eq(#c.lobby:tables(), 0)
    w:slash("bots invite"); ok(w.ns.bots, "invite did not start bots"); w:advance(1)
    ok(c.invites.received, "no invitation")
    for _, s in ipairs(w.sent) do ok(not mentions(s.msg, BOTS), "a bot name went out for real") end
  end)

  it("bots host <game> opens that game; an unknown game says so", function()
    local w = guildWow()
    local c = w.ns.client
    w:slash("bots host dr"); w:advance(1); eq(c.lobby:tables()[1].game, "deathroll")
    w:slash("bots host santase"); w:advance(1); eq(#c.lobby:tables(), 2)
    local games = {}
    for _, rec in ipairs(c.lobby:tables()) do games[rec.game] = true end
    eq(games, { deathroll = true, santase = true })
    w:slash("bots host chess"); eq(#w:chatWith(w.ns.L("bots.nogame")), 1); w:advance(1)
    eq(#c.lobby:tables(), 2)
    w:slash("bots invite nonsense"); eq(#w:chatWith(w.ns.L("bots.nogame")), 2)
    w:slash("bots invite deathroll"); w:advance(1)
    ok(c.invites.received, "no invitation"); eq(c.invites.received.game, "deathroll")
    w:slash("bots host belot"); w:advance(1)
    local belot = 0
    for _, rec in ipairs(c.lobby:tables()) do if rec.game == "belot" then belot = belot + 1 end end
    eq(belot, 1)
    w:slash("bots host tabla"); w:advance(1)
    local tabla = 0
    for _, rec in ipairs(c.lobby:tables()) do if rec.game == "tabla" then tabla = tabla + 1 end end
    eq(tabla, 1)
    w:slash("bots host holdem"); w:advance(1)
    local holdem = 0
    for _, rec in ipairs(c.lobby:tables()) do if rec.game == "holdem" then holdem = holdem + 1 end end
    eq(holdem, 1)
  end)

  it("bots fill asks for a table first, then fills mine with bots", function()
    local w = guildWow()
    w:slash("bots fill"); eq(#w:chatWith(w.ns.L("bots.nofill")), 1); ok(w.ns.bots, "fill did not start bots"); w:advance(1)
    ok(w.ns.client:openTable{ game = "holdem", access = "invite", turn = 45 })
    w:slash("bots fill 2"); w:advance(6)
    eq(w.ns.client.session:seatedCount(), 3); eq(#w:chatWith(w.ns.L("bots.nofill")), 1)
  end)

  it("bots host with an unknown game does not start the bots", function()
    local w = guildWow()
    w:slash("bots host chess"); eq(#w:chatWith(w.ns.L("bots.nogame")), 1); eq(w.ns.bots, nil)
  end)

  it("bots waits while the own name is still unknown", function()
    local w = Wow.new(); w.inGuild = true; w:boot()
    w:slash("bots")
    eq(w.ns.bots, nil); eq(w.ns.client, nil); eq(#w:chatWith(w.ns.L("bots.wait")), 1)
  end)
end)

describe("/tavern probe", function()
  local function probeLine(w, key, from)
    return w:chatWith(key, from)[1]
  end

  it("prints name, instance, API presence and random samples locally; never calls trade or mail", function()
    local w = guildWow()
    w:deliver("GUILD", B .. "-Forever", { v = 1, t = "HI" })
    local n, sent = #w.chat, #w.sent
    w:slash("probe")
    ok(probeLine(w, ME, n + 1), "no own name")
    ok(probeLine(w, B .. "-Forever", n + 1), "no raw sender")
    ok(probeLine(w, "IsInInstance: false", n + 1), "no instance line")
    ok(probeLine(w, "InitiateTrade: function", n + 1), "InitiateTrade")
    ok(probeLine(w, "C_TradeInfo.SetTradeMoney: function", n + 1), "SetTradeMoney")
    ok(probeLine(w, "SetSendMailMoney: function", n + 1), "SetSendMailMoney")
    ok(probeLine(w, "SendMail: function", n + 1), "SendMail")
    ok(probeLine(w, "issecretvalue: nil", n + 1), "issecretvalue")
    ok(probeLine(w, "math.randomseed: function", n + 1), "randomseed")
    local samples = probeLine(w, "math.random(1, 1000000):", n + 1)
    ok(samples, "no samples")
    local count = 0
    for v in samples:match("1000000%):%s*(.*)$"):gmatch("%d+") do
      count = count + 1
      ok(tonumber(v) >= 1 and tonumber(v) <= 1000000, v)
    end
    eq(count, 5)
    eq(#w.sent, sent + 1)
    local p = w.sent[#w.sent]
    eq(p.dist, "WHISPER"); eq(p.target, ME); eq(p.msg.t, "PRB"); ok(#p.text >= 600, "packed only " .. #p.text)
  end)

  it("probe lists the roll and party API and the roll format; probe roll reports what the chat showed", function()
    local w = guildWow()
    local L = w.ns.L
    w:slash("probe"); eq(#w:chatWith("RandomRoll: function"), 1); eq(#w:chatWith("AcceptGroup: function"), 1)
    eq(#w:chatWith("C_PartyInfo.InviteUnit: function"), 1); eq(#w:chatWith("InviteUnit: nil"), 1)
    eq(#w:chatWith("UnitIsGroupLeader: function"), 1); eq(#w:chatWith("StaticPopup_Hide: function"), 1)
    eq(#w:chatWith("IsInGroup: function"), 1); eq(#w:chatWith("IsInRaid: function"), 1)
    eq(#w:chatWith("GetNumGroupMembers: function"), 1)
    eq(#w:chatWith(L("probe.rollfmt", "%s rolls %d (%d-%d)", "OK")), 1); eq(#w.rolls, 0)
    w:slash("probe roll"); eq(w.rolls, { { 1, 100 } }); w:fire("CHAT_MSG_SYSTEM", "Иван rolls 64 (1-100)"); w:advance(3)
    eq(#w:chatWith("Иван rolls 64 (1-100)"), 1)
    eq(#w:chatWith(L("probe.roll.ok", "Иван rolls 64 (1-100)", ME, "yes")), 1)
    w:slash("probe roll"); w:advance(3); eq(#w:chatWith(L("probe.roll.lost")), 1)
    eq(#w.rolls, 2)
  end)

  it("probe shows '-' for a roll format it cannot use", function()
    local w = Wow.new()
    w.G.RANDOM_ROLL_RESULT = "%s rolls"
    w.inGuild = true
    w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
    w:boot(); w:fire("GUILD_ROSTER_UPDATE")
    w:slash("probe"); eq(#w:chatWith(w.ns.L("probe.rollfmt", "%s rolls", "-")), 1)
    eq(w.ns.RollChat.parse("Иван rolls 64 (1-100)"), nil)
  end)

  it("reports echo OK with the instance flag at send time when the whisper comes back", function()
    local w = guildWow()
    w.instance = true
    w:slash("probe")
    local p = w.sent[#w.sent]
    w.instance = false
    local n = #w.chat
    w:deliverRaw("TAVG", p.text, "WHISPER", ME)
    w:advance(4.9); eq(#w:chatWith("echo", n + 1), 0)
    w:advance(0.2)
    local line = w:chatWith("echo OK", n + 1)[1]
    ok(line, "no echo OK"); ok(line:find("true", 1, true), line); ok(line:find(tostring(#p.text), 1, true), line)
    eq(#w:chatWith("echo LOST", n + 1), 0)
  end)

  it("reports echo LOST when nothing comes back, and a late echo prints nothing", function()
    local w = guildWow()
    w:slash("probe")
    local p = w.sent[#w.sent]
    local n = #w.chat
    w:advance(5)
    local line = w:chatWith("echo LOST", n + 1)[1]
    ok(line, "no echo LOST"); ok(line:find("false", 1, true), line)
    w:deliverRaw("TAVG", p.text, "WHISPER", ME); w:advance(5)
    eq(#w:chatWith("echo", n + 1), 1)
  end)

  it("probe lists the trade and mail API by presence only", function()
    local w = guildWow()
    local paths = w.ns.Slash.PROBE_APIS
    eq(paths, {
      "InitiateTrade", "C_TradeInfo.SetTradeMoney", "SetSendMailMoney", "SendMail", "issecretvalue", "IsGUIDInGroup",
      "RandomRoll", "C_PartyInfo.InviteUnit", "InviteUnit", "AcceptGroup", "UnitIsGroupLeader", "StaticPopup_Hide",
      "IsInGroup", "IsInRaid", "GetNumGroupMembers",
      "SetTradeMoney", "GetPlayerTradeMoney", "GetTargetTradeMoney", "C_TradeInfo.GetTradeMoney",
      "MoneyInputFrame_SetCopper", "TradePlayerInputMoneyFrame", "CheckInteractDistance", "GetSendMailPrice",
      "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailBodyEditBox", "MailEditBox", "SendMailMoney",
      "MailFrameTab_OnClick", "GetInboxNumItems", "GetInboxHeaderInfo", "C_Mail.GetInboxHeaderInfo", "TakeInboxMoney",
      "AutoLootMailItem", "hooksecurefunc", "GetGuildInfo",
    })
    local n = #w.chat
    w:slash("probe")
    local said = "|cffb0813f" .. w.ns.L("addon.title") .. "|r: "
    for _, path in ipairs(paths) do
      local lines = 0
      for i = n + 1, #w.chat do
        local line = w.chat[i]:sub(#said + 1)
        if line:sub(1, #path + 2) == path .. ": " and line:sub(#path + 3):match("^%a+$") then lines = lines + 1 end
      end
      eq(lines, 1, path)
    end
    eq(#w:chatWith("GetPlayerTradeMoney: function", n + 1), 1); eq(#w:chatWith("hooksecurefunc: function", n + 1), 1)
    eq(#w:chatWith("TakeInboxMoney: function", n + 1), 1); eq(#w:chatWith("C_Mail.GetInboxHeaderInfo: nil", n + 1), 1)
    for _, name in ipairs({ "AcceptTrade", "SendMail", "TakeInboxMoney", "AutoLootMailItem", "InitiateTrade",
                            "SetTradeMoney", "SetSendMailMoney" }) do
      eq(w:called(name), 0, name)
    end
    for _, name in ipairs({ "AcceptTrade", "SendMail", "TakeInboxMoney", "AutoLootMailItem", "SetSendMailCOD" }) do
      ok(w.forbidden[name], name .. " is not forbidden")
    end
    for _, name in ipairs({ "InitiateTrade", "SetTradeMoney", "SetSendMailMoney" }) do
      ok(not w.forbidden[name], name .. " is forbidden")
    end
    raises(function() w.G.AcceptTrade() end, "called AcceptTrade"); eq(w:called("AcceptTrade"), 1)
  end)

  it("probe trade prints every trade event of the next trade", function()
    local w = guildWow()
    w.tradeMoney = { player = 0, target = 50000 }
    w.npc = { name = "Мария", guid = "Player-1-00000002" }
    w:slash("probe trade")
    eq(#w:chatWith(w.ns.L("probe.trade.armed")), 1)
    local n = #w.chat
    w:fire("TRADE_SHOW"); w:fire("TRADE_MONEY_CHANGED"); w:fire("TRADE_ACCEPT_UPDATE", 1, 1)
    w:fire("UI_INFO_MESSAGE", 0, w.G.ERR_TRADE_COMPLETE); w:fire("TRADE_CLOSED")
    local events = { "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "TRADE_CLOSED" }
    eq(#w.chat, n + 5)
    for i, event in ipairs(events) do ok(w.chat[n + i]:find(event, 1, true), w.chat[n + i]) end
    local accept = w.chat[n + 3]
    for _, needle in ipairs({ "50000", "Мария", "Player-1-00000002" }) do ok(accept:find(needle, 1, true), accept) end
    ok(w.chat[n + 4]:find(w.G.ERR_TRADE_COMPLETE, 1, true), w.chat[n + 4])
    w:fire("TRADE_SHOW"); eq(#w.chat, n + 5)
    eq(w:called("AcceptTrade"), 0)
  end)

  it("probe mail prints the inbox rows and the price", function()
    local w = guildWow()
    local L = w.ns.L
    w.mailOpen, w.mailPrice = true, 30
    w.inbox = {
      { sender = "Мария", subject = "Tavern Games: 5g", money = 50000 },
      { sender = "Auction House", subject = "x", money = 0 },
    }
    local n = #w.chat
    w:slash("probe mail")
    eq(#w.chat, n + 3)
    for _, needle in ipairs({ "Мария", "Tavern Games: 5g", "50000" }) do ok(w.chat[n + 1]:find(needle, 1, true), w.chat[n + 1]) end
    local said = "|cffb0813f" .. L("addon.title") .. "|r: "
    eq(w.chat[n + 1], said .. L("probe.mail.row", "1", "Мария", "Tavern Games: 5g", "50000", "number"))
    eq(w.chat[n + 2], said .. L("probe.mail.row", "2", "Auction House", "x", "0", "number"))
    eq(w.chat[n + 3], said .. L("probe.mail.price", "30")); ok(w.chat[n + 3]:find("30", 1, true), w.chat[n + 3])
    eq(w:called("TakeInboxMoney"), 0); eq(w:called("AutoLootMailItem"), 0)
    w.mailOpen = false
    n = #w.chat
    w:slash("probe mail")
    eq(#w.chat, n + 1); eq(w.chat[n + 1], said .. L("probe.mail.closed"))
  end)

  it("probe art prints every candidate, sound and API with what the client has, locally only", function()
    local w = guildWow()
    local L = w.ns.L
    local said = "|cffb0813f" .. L("addon.title") .. "|r: "
    local logo = "Interface\\Timer\\Alliance-Logo"
    local n, sent = #w.chat, #w.sent
    w:slash("probe art")
    eq(w.chat[n + 1], said .. L("probe.art.head"))
    ok(probeLine(w, said .. logo .. ": -", n + 1), "logo missing")
    ok(probeLine(w, said .. "GetFileIDFromPath: function", n + 1), "GetFileIDFromPath")
    local total = select(3, w.ns.Art.report())
    eq(total, 4 + 17 + 60 + 2 + 3) -- crests, leaders, races, the one class (MAGE), coins
    eq(w.chat[#w.chat - 1], said .. L("probe.art.sum", 0, total))
    eq(w.chat[#w.chat], said .. L("probe.art.saved"))
    local kept = w.ns.db.probeArt -- the report, line for line, without the chat prefix
    eq(#kept, #w.chat - 1 - n); eq(kept[1], L("probe.art.head")); eq(kept[#kept], L("probe.art.sum", 0, total))
    n = #w.chat
    w:hasFile(logo); w.ns.Art.reset()
    w:slash("probe art")
    ok(probeLine(w, said .. logo .. ": file", n + 1), "logo present")
    local player = w.chat[#w.chat - 2]
    eq(player, said .. L("probe.art.player", "Alliance", "Human", "2"))
    for _, needle in ipairs({ "Alliance", "Human", "2" }) do ok(player:find(needle, 1, true), player) end
    ok(w.chat[#w.chat - 1]:find("Намерени 1 от " .. total, 1, true), w.chat[#w.chat - 1])
    eq(w.ns.db.probeArt[#w.ns.db.probeArt], L("probe.art.sum", 1, total))
    eq(#w.sent, sent)
  end)
end)

describe("/tavern ledger", function()
  it("prints authors, entries, stubs and the digest on one local line", function()
    local w = guildWow()
    w:fire("PLAYER_LOGIN")
    w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
    local L = w.ns.L
    w.ns.client.ledgerNet:make("R", { gid = ME .. "#1/1", g = "ttt", n = { ME, B }, w = { 1 }, l = { 2 } })
    w:advance(1)
    local said = "|cffb0813f" .. L("addon.title") .. "|r: "
    local n = #w.chat
    w:slash("ledger")
    eq(#w.chat, n + 1)
    eq(w.chat[n + 1], said .. L("ledger.stats", 1, 1, 0, w.ns.client.ledger:digest()))
    eq(L("ledger.stats", 2, 30, 4, "abcd1234"), "Тефтер: 2 автори, 30 записа, 4 стари (само следа), отпечатък abcd1234")
    ok(w.ns.client.ledger:digest():match("^%x%x%x%x%x%x%x%x$"), "no digest")
  end)

  it("counts by a plain walk: no hash is finished and no author sorted in that frame (final review M2)", function()
    local w = guildWow()
    w:fire("PLAYER_LOGIN")
    w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
    local L, ledger, Ledger = w.ns.L, w.ns.client.ledger, w.ns.Ledger
    local settled = ledger:digest()
    for k = 1, 3 do ledger:add({ i = Ledger.id(B, k), k = "R", at = 1700000000 + k, gid = B .. "#1/" .. k, g = "ttt", n = { B, ME }, w = { 1 }, l = { 2 } }, B) end
    ledger:add({ i = Ledger.id(B, 3), k = "R", at = 1700000009, gid = B .. "#1/9", g = "ttt", n = { B, ME }, w = { 1 }, l = { 2 } }, B) -- a twin
    local old = "Стара Сянка"
    local _, body = ledger:add({ i = Ledger.id(old, 1), k = "R", at = 1600000000, gid = old .. "#1/1", g = "ttt", n = { old, B }, w = { 1 }, l = { 2 } }, B)
    eq(ledger:stub(body), true) -- an author held only as a stub
    ok(ledger:hashing(), "an x is stale")
    local calls = 0
    for _, name in ipairs({ "vector", "each", "above", "work" }) do
      local real = ledger[name]
      ledger[name] = function(...) calls = calls + 1; return real(...) end
    end
    local n = #w.chat
    w:slash("ledger")
    eq(calls, 0)
    ok(ledger:hashing(), "still stale")
    eq(w.chat[n + 1], "|cffb0813f" .. L("addon.title") .. "|r: " .. L("ledger.stats", 2, 4, ledger:stubCount(), settled))
  end)

  it("without a guild it says nothing is kept yet", function()
    local w = Wow.new(); w:boot()
    local n = #w.chat
    w:slash("ledger")
    eq(#w.chat, n + 1)
  end)
end)
