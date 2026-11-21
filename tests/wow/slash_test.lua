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
end)
