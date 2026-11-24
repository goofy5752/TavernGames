local Wow = require("wow")

local ME, B = "Иван Петров", "Мария Стоянова"
local NAMESAKE = "Иван Димов"

-- In a guild, booted, own name resolved from the roster.
local function guildWow(w)
  w = w or Wow.new()
  w.inGuild = true
  w.roster = {
    { name = B .. "-Forever", online = true, guid = "Player-1-00000002" },
    { name = ME .. "-Forever", online = true, guid = Wow.GUID },
  }
  w:boot()
  w:fire("GUILD_ROSTER_UPDATE")
  return w
end

local function setup()
  local w = guildWow()
  return w, w.ns.RollChat
end

-- `host` (a guild member, HI delivered) announces a Death Roll table with
-- `seats` (names, padded with free seats) and sends me the snapshot that seats me.
local function seatAt(w, host, seats)
  w:member(host)
  w:deliver("GUILD", host, { v = 1, t = "HI", ver = "0.1.0", cls = "PRIEST", id = "Player-" .. host })
  local tid = host .. "#1"
  local s = { false, false, false, false, false }
  for i, name in ipairs(seats) do s[i] = name end
  local tbl = { tid = tid, g = "deathroll", h = host, e = 1, ac = "guild", tn = 45, st = "open", s = s, w = 0 }
  local announce = { v = 1, t = "TBL" }
  for k, v in pairs(tbl) do announce[k] = v end
  w:deliver("GUILD", host, announce)
  w:deliver("WHISPER", host, { v = 1, t = "SNP", tid = tid, e = 1, q = 1, tbl = tbl })
  w:advance(0)
  return tid
end

-- The "rollSeen" calls of my client, in order.
local function rollsSeen(w)
  local seen = {}
  w.ns.client:on("rollSeen", function(...) seen[#seen + 1] = { ... } end)
  return seen
end

describe("wow: roll line", function()
  it("builds the pattern from positional and plain formats", function()
    local _, R = setup()
    local p, o = R.pattern("%s rolls %d (%d-%d)"); eq(o, { "name", "n", "lo", "hi" })
    eq({ ("Иван Петров rolls 57 (1-1000)"):match(p) }, { "Иван Петров", "57", "1", "1000" })
    p, o = R.pattern("%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)"); eq(o, { "name", "n", "lo", "hi" })
    eq({ ("Hans würfelt. Ergebnis: 7 (1-100)"):match(p) }, { "Hans", "7", "1", "100" })
    p, o = R.pattern("(%3$d-%4$d): %2$d от %1$s"); eq(o, { "lo", "hi", "n", "name" })
    eq({ ("(1-100): 7 от Hans"):match(p) }, { "1", "100", "7", "Hans" })
    eq(R.pattern("%s rolls %d"), nil); eq(R.pattern(nil), nil); eq(R.pattern("%s %s %d (%d-%d)"), nil)
    eq(R.pattern("%d rolls %s (%d-%d)"), nil); eq(R.pattern("%1$s rolls %d (%3$d-%4$d)"), nil)
    eq(R.pattern("%1$s rolls %2$d (%2$d-%4$d)"), nil); eq(R.pattern("%s rolls %d (%d-%d) 100%"), nil)
  end)

  it("parses a roll line, a player link, and nothing else", function()
    local w, R = setup()
    eq({ R.parse("Мария rolls 12 (1-57)") }, { "Мария", 12, 1, 57 })
    eq({ R.parse("|Hplayer:Мария Стоянова:1|h[Мария Стоянова]|h rolls 12 (1-57)") }, { "Мария Стоянова", 12, 1, 57 })
    eq(R.parse("Мария has gone offline."), nil); eq(R.parse(nil), nil)
    w.G.issecretvalue = function() return true end; eq(R.parse("Мария rolls 12 (1-57)"), nil)
  end)

  it("my own roll is passed under my full name; another player's as shown", function()
    local w = setup()
    local seen = rollsSeen(w)
    w.ns.client.env.roll(1, 1000)
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-1000)"); w:fire("CHAT_MSG_SYSTEM", "Мария rolls 3 (1-57)")
    w:fire("CHAT_MSG_SYSTEM", "Мария has gone offline.")
    eq(seen, { { ME, 57, 1, 1000 }, { "Мария", 3, 1, 57 } }); eq(w.ns.RollChat.last.raw, "Мария rolls 3 (1-57)")
  end)

  it("a namesake seated at my table keeps the shown name", function()
    local w = setup()
    seatAt(w, NAMESAKE, { ME, NAMESAKE }); eq(w.ns.client.session.mySeat, 1)
    local seen = rollsSeen(w)
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-1000)"); eq(seen, { { "Иван", 57, 1, 1000 } })
    w = setup()
    seatAt(w, B, { ME, B }); eq(w.ns.client.session.mySeat, 1)
    seen = rollsSeen(w)
    w.ns.client.env.roll(1, 1000)
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-1000)"); eq(seen, { { ME, 57, 1, 1000 } })
  end)

  it("a namesake's roll line is shown as shown: only a roll I made in the last 3 s is mine", function()
    local w = setup()
    local seen = rollsSeen(w)
    -- No RandomRoll of that range: a namesake's line, passed as shown.
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-1000)"); eq(seen[1], { "Иван", 57, 1, 1000 })
    -- The addon's own roll (env.roll) of that range just before: mine, once.
    w.ns.client.env.roll(1, 1000); w:advance(2)
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 58 (1-1000)"); eq(seen[2], { ME, 58, 1, 1000 })
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 59 (1-1000)"); eq(seen[3], { "Иван", 59, 1, 1000 })
    -- The player's own /roll, caught by the hook on RandomRoll (the slash command passes strings).
    w.G.RandomRoll("1", "500")
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 60 (1-500)"); eq(seen[4], { ME, 60, 1, 500 })
    w.G.RandomRoll(1, 500)
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 61 (1-100)"); eq(seen[5], { "Иван", 61, 1, 100 }) -- another range
    -- Older than ROLL_ECHO_WAIT: not mine any more.
    w.G.RandomRoll(1, 500); w:advance(3.5)
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 62 (1-500)"); eq(seen[6], { "Иван", 62, 1, 500 })
    eq(w.rolls, { { 1, 1000 }, { "1", "500" }, { 1, 500 }, { 1, 500 } })
  end)

  it("env.groupedWith asks my own roster: the guild roster's GUID in my group, or the name in my group", function()
    local w = setup()
    local env = w.ns.client.env
    eq(env.groupedWith(B), false)
    w.group["Player-1-00000002"] = true; eq(env.groupedWith(B), true) -- B's GUID from my guild roster
    w.group = {}; eq(env.groupedWith(B), false)
    w:member(B); w:deliver("GUILD", B, { v = 1, t = "HI", ver = "0.1.0", cls = "PRIEST", id = "Player-1-00000099" })
    w.group["Player-1-00000099"] = true; eq(env.groupedWith(B), false) -- the GUID B announced does not count
    w.partyNames[B] = true; eq(env.groupedWith(B), true); w.partyNames = {}
    w.raidNames[B] = true; eq(env.groupedWith(B), true); w.raidNames = {}
    w.party.size, w.groupRoster = 2, { ME .. "-Forever", B .. "-Forever" }; eq(env.groupedWith(B), true)
    eq(w.ns.Adapter.botEnv("Bot Ivanov", "PRIEST").groupedWith, nil)
  end)

  it("env.roll, env.group and env.groupInvite reach the game API; a bot env has only random", function()
    local w = setup()
    local env = w.ns.client.env
    env.roll(1, 87); eq(w.rolls, { { 1, 87 } })
    eq(env.group(), { grouped = false, leader = false, raid = false, size = 0 })
    w.party = { grouped = true, leader = true, raid = false, size = 3 }
    eq(env.group(), { grouped = true, leader = true, raid = false, size = 3 })
    env.groupInvite("Мария Стоянова"); eq(w.groupInvites, { "Мария Стоянова" })
    local r = env.random(1, 6); ok(r >= 1 and r <= 6 and r % 1 == 0, tostring(r))
    local bot = w.ns.Adapter.botEnv("Bot Ivanov", "PRIEST")
    eq(bot.roll, nil); eq(bot.groupInvite, nil); eq(bot.group, nil); eq(type(bot.random(1, 6)), "number")
  end)

  it("env.entropy feeds the seed pool with the client's clocks, with or without the optional calls", function()
    local w = setup()
    local env = w.ns.client.env
    local e1 = env.entropy(); eq(type(e1), "string"); ok(#e1 > 8)
    w.G.debugprofilestop, w.G.GetFramerate = function() return 123456.789 end, function() return 59.94 end
    local e2 = env.entropy(); ok(e2:find("123456.789", 1, true) and e2:find("59.94", 1, true), e2)
    eq(type(w.ns.Adapter.botEnv("Bot Ivanov", "PRIEST").entropy()), "string")
    local seed = w.ns.Fair.seed(env, "dice|t#1/3"); ok(#seed == 32 and not seed:find("[^0-9a-f]"), seed)
    ok(w.ns.Fair.seed(env, "dice|t#1/3") ~= seed)
  end)

  it("env.group is absent unless all four group functions exist", function()
    for _, fn in ipairs({ "IsInGroup", "UnitIsGroupLeader", "IsInRaid", "GetNumGroupMembers" }) do
      local w = Wow.new()
      w.G[fn] = nil
      guildWow(w)
      ok(w.ns.client, "no client"); eq(w.ns.client.env.group, nil)
      ok(w.ns.client.env.groupInvite, "groupInvite lost with " .. fn)
    end
  end)

  it("env.roll is absent when the client has no RandomRoll", function()
    local w = Wow.new()
    w.G.RandomRoll = nil
    guildWow(w)
    ok(w.ns.client, "no client"); eq(w.ns.client.env.roll, nil)
  end)

  it("a group invite from my Death Roll host is accepted and the popup hidden; any other is left alone", function()
    local w = setup()
    seatAt(w, B, { B, ME }); eq(w.ns.client.session.mySeat, 2)
    w:fire("PARTY_INVITE_REQUEST", "Мария")
    eq(w.accepted, 1); eq(w.popupsHidden, {})
    w:advance(0); eq(w.popupsHidden, { "PARTY_INVITE" })
    w:fire("PARTY_INVITE_REQUEST", "Гошо"); w:advance(0)
    eq(w.accepted, 1); eq(w.popupsHidden, { "PARTY_INVITE" })
  end)

  it("a group invite while not seated is left alone", function()
    local w = setup()
    w:fire("PARTY_INVITE_REQUEST", "Мария"); w:advance(0)
    eq(w.accepted, 0); eq(w.popupsHidden, {})
  end)

  it("a group change redraws the table", function()
    local w = setup()
    seatAt(w, B, { B, ME })
    local n = 0
    w.ns.client:on("session", function() n = n + 1 end)
    w:fire("GROUP_ROSTER_UPDATE"); eq(n, 1)
  end)
end)
