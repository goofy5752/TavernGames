local Wow = require("wow")

local ME, B = "Иван Петров", "Мария Стоянова"
local B_GUID = "Player-1-00000002"

local function rosterWith(me)
  local r = { { name = B .. "-Forever", online = true, guid = B_GUID } }
  if me then r[#r + 1] = { name = ME .. "-Forever", online = true, guid = Wow.GUID } end
  return r
end

-- In a guild, booted, own name resolved from the roster.
local function guildWow()
  local w = Wow.new()
  w.inGuild, w.roster = true, rosterWith(true)
  w:boot()
  w:fire("GUILD_ROSTER_UPDATE")
  return w
end

describe("wow adapter: db", function()
  it("routes snoozeUntil, busy, debug to AceDB char and lang, introDone, minimap to global", function()
    local w = Wow.new(); w:init()
    local db, sv = w.ns.db, w.G.TavernGamesDB
    eq(db.snoozeUntil, 0); eq(db.busy, false); eq(db.debug, false)
    eq(db.lang, nil); eq(db.introDone, false); eq(db.minimap, { hide = false })
    db.busy, db.snoozeUntil, db.debug = true, 1700001800, true
    db.lang, db.introDone = "en", true
    local char = sv.char[Wow.FIRST .. " - Forever"]
    eq(char.busy, true); eq(char.snoozeUntil, 1700001800); eq(char.debug, true); eq(char.lang, nil)
    eq(sv.global.lang, "en"); eq(sv.global.introDone, true); eq(sv.global.busy, nil)
    raises(function() db.wager = 5 end, "unknown db key")
  end)

  it("keeps the dealer's saved round with the character: it survives a reload and can be dropped", function()
    local w = Wow.new(); w:init()
    local db, sv = w.ns.db, w.G.TavernGamesDB
    eq(db.fairKeep, nil)
    db.fairKeep = { tid = "t#1", h = 7 }
    eq(sv.char[Wow.FIRST .. " - Forever"].fairKeep, { tid = "t#1", h = 7 }); eq(sv.global.fairKeep, nil)
    db.fairKeep = nil; eq(sv.char[Wow.FIRST .. " - Forever"].fairKeep, nil)
  end)

  it("values survive a reload and the saved language is applied", function()
    local w = Wow.new(); w:init()
    local db = w.ns.db
    db.busy, db.snoozeUntil, db.debug, db.lang, db.introDone = true, 1700001800, true, "en", true
    db.minimap.hide = true
    w:fire("PLAYER_LOGOUT")
    local w2 = Wow.new{ saved = w.G.TavernGamesDB }; w2:init()
    local db2 = w2.ns.db
    eq(db2.busy, true); eq(db2.snoozeUntil, 1700001800); eq(db2.debug, true)
    eq(db2.lang, "en"); eq(db2.introDone, true); eq(db2.minimap.hide, true)
    eq(w2.ns.Locale.lang(), "en")
  end)
end)

describe("wow adapter: own name", function()
  it("comes from the roster entry with my GUID; ready callbacks run before start", function()
    local w = Wow.new(); w.inGuild, w.roster = true, rosterWith(true)
    local seen = {}
    w:init()
    w.ns.ready(function(c) seen[#seen + 1] = c.running end)
    w:enable()
    eq(w.rosterRequests, 1); eq(w.ns.client, nil); eq(#w.sent, 0)
    w:fire("GUILD_ROSTER_UPDATE")
    local c = w.ns.client
    ok(c, "no client"); eq(c.env.me, ME); eq(c.env.guid, Wow.GUID); eq(c.env.cls, "MAGE")
    eq(seen, { false }); eq(c.running, true); ok(c.env.db == w.ns.db, "env.db is not ns.db")
    local hi = w:sentOf("HI")[1]
    ok(hi, "no HI"); eq(hi.prefix, "TAVG"); eq(hi.dist, "GUILD"); eq(hi.prio, "NORMAL")
    w.ns.ready(function(c2) seen[#seen + 1] = (c2 == c) end)
    eq(seen, { false, true })
    w:advance(10); eq(#w:sentOf("WHO"), 0)
  end)

  it("without a roster match a WHO goes out after 5 s and the echo with my GUID names me", function()
    local w = Wow.new(); w.inGuild, w.roster = true, rosterWith(false)
    w:boot(); w:fire("GUILD_ROSTER_UPDATE")
    w:advance(4.9); eq(#w:sentOf("WHO"), 0)
    w:advance(0.2)
    local who = w:sentOf("WHO")
    eq(#who, 1); eq(who[1].dist, "GUILD"); eq(who[1].msg, { v = 1, t = "WHO", id = Wow.GUID })
    w:deliver("GUILD", B, { v = 1, t = "WHO", id = B_GUID }); eq(w.ns.client, nil)
    w:deliver("GUILD", ME .. "-Forever", { v = 1, t = "WHO", id = Wow.GUID })
    ok(w.ns.client, "no client"); eq(w.ns.client.env.me, ME); eq(w.ns.client.running, true)
  end)

  it("not in a guild: no client and no sends, but bots run under UnitName", function()
    local w = Wow.new(); w:boot()
    eq(w.ns.client, nil); eq(w.ns.noGuild, true); eq(w.rosterRequests, 0); eq(#w.sent, 0)
    w:advance(10); eq(#w.sent, 0)
    w:slash("bots")
    local c = w.ns.client
    ok(c, "no client"); eq(c.env.me, Wow.FIRST); ok(w.ns.bots, "no bots")
    w:advance(1)
    ok(c.presence:get("Бот Иванов"), "bot not seen"); eq(#w.sent, 0)
  end)

  it("joining a guild later starts the name lookup", function()
    local w = Wow.new(); w:boot()
    eq(w.ns.noGuild, true)
    w.inGuild, w.roster = true, rosterWith(true)
    w:fire("PLAYER_GUILD_UPDATE"); eq(w.ns.noGuild, false); eq(w.rosterRequests, 1)
    w:fire("GUILD_ROSTER_UPDATE"); eq(w.ns.client.env.me, ME)
  end)
end)

describe("wow adapter: comm", function()
  it("accepts only TAVG on GUILD and WHISPER, normalizes the sender and drops garbage", function()
    local w = guildWow()
    local got = {}
    w.ns.client.receive = function(_, ch, s, m) got[#got + 1] = { ch, s, m.t } end
    w:deliver("GUILD", B .. "-Forever", { v = 1, t = "HI" })
    w:deliver("WHISPER", B, { v = 1, t = "TBL" })
    w:deliver("PARTY", B, { v = 1, t = "HI" })
    w:deliver("RAID", B, { v = 1, t = "HI" })
    w:deliverRaw("OTHER", w.wire:pack({ v = 1, t = "HI" }), "GUILD", B)
    w:deliverRaw("TAVG", "garbage", "GUILD", B)
    w:deliverRaw("TAVG", w.wire:pack({ v = 1, t = "HI" }), "GUILD", "")
    eq(got, { { "GUILD", B, "HI" }, { "WHISPER", B, "TBL" } })
  end)

  it("drops GUILD and WHISPER messages from a sender missing from the latest roster scan", function()
    local w = guildWow()
    local X = "Гошо Тестов"
    local got = {}
    w.ns.client.receive = function(_, ch, s, m) got[#got + 1] = { ch, s, m.t } end
    local asked = w.rosterRequests
    w:deliver("WHISPER", X, { v = 1, t = "HI" })
    w:deliver("GUILD", X .. "-Forever", { v = 1, t = "TBL" })
    w:deliver("WHISPER", X, { v = 1, t = "INV" })
    eq(got, {}); eq(w.rosterRequests, asked + 1) -- one refresh, not one per message
    w:advance(10); w:deliver("WHISPER", X, { v = 1, t = "HI" })
    eq(got, {}); eq(w.rosterRequests, asked + 2)
    -- the fresh roster lists him (he just joined): his later messages pass
    w.roster[#w.roster + 1] = { name = X .. "-Forever", online = true, guid = "Player-1-00000009" }
    w:fire("GUILD_ROSTER_UPDATE")
    w:deliver("WHISPER", X, { v = 1, t = "HI" })
    eq(got, { { "WHISPER", X, "HI" } })
    -- he left the guild: dropped again
    table.remove(w.roster)
    w:fire("GUILD_ROSTER_UPDATE")
    w:deliver("GUILD", X, { v = 1, t = "HI" })
    eq(#got, 1)
  end)

  it("my own echo passes even when the roster has no entry for me", function()
    local w = Wow.new(); w.inGuild, w.roster = true, rosterWith(false)
    w:boot(); w:fire("GUILD_ROSTER_UPDATE"); w:advance(5.1)
    w:deliver("GUILD", ME .. "-Forever", { v = 1, t = "WHO", id = Wow.GUID })
    local c = w.ns.client; ok(c, "no client")
    local got = {}
    c.receive = function(_, ch, s, m) got[#got + 1] = { ch, s, m.t } end
    w:deliver("GUILD", ME .. "-Forever", { v = 1, t = "HI" })
    w:deliver("GUILD", "Гошо Тестов", { v = 1, t = "HI" })
    eq(got, { { "GUILD", ME, "HI" } })
  end)

  it("sends through SendCommMessage, ALERT for EV, ACT, SNP and NORMAL otherwise", function()
    local w = guildWow()
    local env = w.ns.client.env
    local n = #w.sent
    local types = { "EV", "ACT", "SNP", "HI", "TBL", "SIT", "END", "INV" }
    for _, t in ipairs(types) do env.send("WHISPER", B, { v = 1, t = t, tid = "x" }) end
    local prios = {}
    for i = n + 1, #w.sent do
      prios[#prios + 1] = w.sent[i].prio
      eq(w.sent[i].dist, "WHISPER"); eq(w.sent[i].target, B); eq(w.sent[i].prefix, "TAVG")
    end
    eq(prios, { "ALERT", "ALERT", "ALERT", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL" })
  end)

  it("a message that cannot be packed is dropped without an error", function()
    local w = guildWow()
    local n = #w.sent
    w.ns.client.env.send("GUILD", nil, { v = 1, t = "HI", f = function() end })
    eq(#w.sent, n)
  end)
end)

describe("wow adapter: game events", function()
  it("a guild member going offline in the roster or the system line leaves presence", function()
    local w = guildWow()
    local off = {}
    w.ns.client.peerOffline = function(_, name) off[#off + 1] = name end
    w.roster[1].online = false
    w:fire("GUILD_ROSTER_UPDATE"); eq(off, { B })
    w:fire("GUILD_ROSTER_UPDATE"); eq(off, { B })
    w:fire("CHAT_MSG_SYSTEM", "Тодор Ангелов has gone offline.")
    w:fire("CHAT_MSG_SYSTEM", "|Hplayer:Яна Жекова-Forever|h[Яна Жекова]|h has gone offline.")
    w:fire("CHAT_MSG_SYSTEM", "Тодор Ангелов has come online.")
    eq(off, { B, "Тодор Ангелов", "Яна Жекова" })
  end)

  it("a 'player not found' line is hidden only for a name whispered in the last 5 s", function()
    local w = guildWow()
    local line = "No player named '" .. B .. "' is currently playing."
    ok(not w:filtered("CHAT_MSG_SYSTEM", line), "hidden before any whisper")
    w.ns.client.env.send("WHISPER", B, { v = 1, t = "HI" })
    ok(w:filtered("CHAT_MSG_SYSTEM", line), "not hidden")
    ok(not w:filtered("CHAT_MSG_SYSTEM", "No player named 'Тодор Ангелов' is currently playing."), "other name hidden")
    ok(not w:filtered("CHAT_MSG_SYSTEM", B .. " has gone offline."), "other line hidden")
    w:advance(5); ok(w:filtered("CHAT_MSG_SYSTEM", line), "not hidden at 5 s")
    w:advance(1); ok(not w:filtered("CHAT_MSG_SYSTEM", line), "still hidden after 6 s")
  end)

  it("status, inGroup, now, epoch and after follow the game", function()
    local w = guildWow()
    local env = w.ns.client.env
    eq(env.status(), { combat = false, instance = false, busy = false })
    w.combat, w.instance = true, true
    eq(env.status(), { combat = true, instance = true, busy = false })
    w.combat, w.instance, w.dnd = false, false, true
    eq(env.status().busy, true)
    w.dnd = false; w.ns.db.busy = true
    eq(env.status().busy, true)
    w.group[B_GUID] = true
    eq(env.inGroup(B_GUID), true); eq(env.inGroup("Player-1-00000003"), false)
    local fired = 0
    env.after(2, function() fired = fired + 1 end)
    local t2 = env.after(2, function() fired = fired + 10 end)
    t2.cancel()
    w:advance(2)
    eq(fired, 1); eq(env.now(), w.clock); eq(env.epoch(), Wow.EPOCH0 + 2)
  end)

  it("PLAYER_LOGOUT stops the client with a BYE and nothing else, even when seated", function()
    local w = guildWow()
    local c = w.ns.client
    c:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:deliver("GUILD", B, { v = 1, t = "HI", cls = "PRIEST", id = B_GUID })
    w:deliver("WHISPER", B, { v = 1, t = "SIT", tid = c.session.tid, seat = 2 })
    w:advance(3); eq(c.session.seats[2], B)
    local n = #w.sent
    w:fire("PLAYER_LOGOUT")
    eq(c.running, false)
    eq(#w.sent, n + 1); eq(w.sent[#w.sent].msg.t, "BYE")
  end)

  it("classColor uses the class table and falls back to ink", function()
    local w = guildWow()
    eq({ w.ns.classColor("MAGE") }, { 0.25, 0.78, 0.92 })
    eq({ w.ns.classColor("NOPE") }, { 243 / 255, 226 / 255, 192 / 255 })
  end)

  it("creates no globals but TavernGamesDB, SLASH_TAVERNGAMES1 and SlashCmdList.TAVERNGAMES", function()
    local w = guildWow()
    w:slash("debug"); w:slash("bots"); w:slash("bots host"); w:slash("probe"); w:advance(6); w:slash("bots")
    eq(w:newGlobals(), { "SLASH_TAVERNGAMES1", "TavernGamesDB" })
    local keys = {}
    for k in pairs(w.G.SlashCmdList) do keys[#keys + 1] = k end
    eq(keys, { "TAVERNGAMES" }); eq(w.G.SLASH_TAVERNGAMES1, "/tavern")
  end)
end)
