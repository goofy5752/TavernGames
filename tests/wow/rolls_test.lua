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
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-1000)"); eq(seen, { { ME, 57, 1, 1000 } })
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
    local bot = w.ns.Adapter.botEnv("Бот Иванов", "PRIEST")
    eq(bot.roll, nil); eq(bot.groupInvite, nil); eq(bot.group, nil); eq(type(bot.random(1, 6)), "number")
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
