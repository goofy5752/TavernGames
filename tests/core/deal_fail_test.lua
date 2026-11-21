local Sim = require("sim")
require("hicard_engine")
local ns = Sim.ns

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"
local SEED = ("ff"):rep(16)
local sim, tid, a, b, c, d
local got -- client -> the "fair" payloads it received

local function listen(cl)
  local list = {}
  got[cl] = list
  cl:on("fair", function(e) list[#list + 1] = e end)
end

-- a hosts hicard, b on seat 2 (and c on seat 3 when `three`), d online but not
-- at the table; not started. Every client yields SEED.
local function setup(three)
  sim, got = Sim.new(), {}
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  c = three and sim:add(C, { cls = "ROGUE" }) or nil
  d = sim:add(D, { cls = "DRUID" })
  listen(a); listen(b); listen(d)
  if c then listen(c) end
  sim:run(1)
  tid = a:openTable{ game = "hicard", access = "guild", turn = 45 }; sim:run(3)
  b:sit(tid, 2); sim:run(1)
  if three then c:sit(tid, 3); sim:run(1) end
  return sim, tid
end
local function table2() return setup(false) end
local function table3() return setup(true) end

local function start() a:startGame(); sim:run(1) end

-- A fresh Client under `name`, its "fair" events recorded too.
local function relog(name)
  local cl = sim:relog(name)
  listen(cl)
  return cl
end

-- `cl` ignores every message of type t (only those for which pred(sender, msg)
-- holds, when given) until the returned function is called.
local function drop(cl, t, pred)
  cl.receive = function(self, channel, sender, msg)
    if msg.t == t and (not pred or pred(sender, msg)) then return end
    return ns.Client.receive(self, channel, sender, msg)
  end
  return function() cl.receive = nil end
end

local function events(cl) return got[cl] end

-- n times: the client whose seat is on turn (at the table `via` hosts, default
-- a) plays its automatic move.
local function auto(n, via)
  for _ = 1, n do
    local s = (via or a).session
    local cl = sim.clients[s.seats[s.state.turn]]
    ok(cl:playAuto())
    sim:run(1)
  end
end

-- Automatic moves until the running hand at the table `via` hosts is over.
-- (No turn left, or the next hand already dealt.)
local function finish(via)
  local hand = (via or a).session.state.hand
  for _ = 1, 12 do
    local st = (via or a).session.state
    if not st.turn or st.hand ~= hand then return end
    auto(1, via)
  end
  error("the hand does not end")
end

-- Plays the match to its end -> hands dealt, h of the last round. With
-- `withhold`: the dealer of hand number `withhold` keeps its seeds to itself
-- (it forgets them, so no later attempt can reveal them).
local function playMatch(withhold)
  for _ = 1, 120 do
    local s = a.session
    if s:gameOver() then return s.fairN, s.fair.h end
    if withhold and s.fairN == withhold and s.fair.stage == "dealt" then
      sim.clients[s.fair.dealer].session.fair.seeds = {}
    end
    if s.state.turn then auto(1) else sim:run(1) end
  end
  error("the match does not end")
end

local function sentOf(t)
  local out = {}
  for _, m in ipairs(sim.sent) do
    if m.msg.t == t then out[#out + 1] = m end
  end
  return out
end

local function opensFromA()
  local n = 0
  for _, m in ipairs(sentOf("EV")) do
    if m.from == A and type(m.msg.a) == "table" and m.msg.a.op == "open" then n = n + 1 end
  end
  return n
end

local function act(x) return { v = 1, t = "ACT", tid = tid, a = x } end

-- An ACT asking for the fair op `op` (for drop).
local function asks(op) return function(_, msg) return type(msg.a) == "table" and msg.a.op == op end end

describe("deal failures", function()
  it("a player who never commits: the round is reopened every 20 s until he is back", function()
    local sim = table2(); sim:offline(B); a:startGame(); sim:run(1)
    local h1 = a.session.fair.h; eq(a.session.fair.stage, "commit"); eq({ ns.Deal.status(a.session) }, { "fair.waiting", B })
    sim:run(20); ok(a.session.fair.h ~= h1); eq(a.session.fair.stage, "commit")
    eq(opensFromA(), 2)
    sim:online(B); sim:run(20); eq(a.session.fair.stage, "dealt"); eq(b.session.fair.stage, "dealt"); eq(ns.Deal.missing(a.session), false)
  end)

  it("a seed that never arrives: the round is reopened", function()
    local sim = table2(); local restore = drop(b, "SED"); start()
    local h1 = a.session.fair.h; eq(a.session.fair.stage, "seed"); eq({ ns.Deal.status(a.session) }, { "fair.dealing", B })
    restore(); sim:run(20); ok(a.session.fair.h ~= h1); eq(a.session.fair.stage, "dealt")
  end)

  it("a relogged player gets its hand again from the dealer", function()
    local sim = table3(); start(); local deck, h = b.session.fair.deck, a.session.fair.h
    local n = #sentOf("PRV"); local c2 = relog(C); sim:run(2)
    eq(c2.session.state.deck, { [3] = deck[3], [6] = deck[6], [7] = deck[7] })
    local prq = sentOf("PRQ"); eq(#prq, 1)
    eq({ prq[1].from, prq[1].channel, prq[1].target, prq[1].msg.tid, prq[1].msg.h }, { C, "WHISPER", B, tid, h })
    local prv = sentOf("PRV"); eq(#prv, n + 1)
    eq({ prv[n + 1].from, prv[n + 1].target, prv[n + 1].msg.cards }, { B, C, { [3] = deck[3], [6] = deck[6] } })
    auto(9); sim:run(1)
    eq(#events(c2), 1); eq(events(c2)[1].verdict, "unseen")
    eq(#events(a), 1); eq(events(a)[1].verdict, "ok")
  end)

  it("the dealer relogs mid-hand: void, the same dealer deals again", function()
    local sim = table3(); start(); local h1 = a.session.fair.h; auto(1)
    local b2 = relog(B); sim:run(3)
    eq(events(a)[1].verdict, "void"); ok(a.session.fair.h ~= h1); eq({ a.session.fair.d, a.session.fair.stage }, { 2, "dealt" })
    eq(a.session.state.hand, 1); eq(a.session.state.pts, { 0, 0, 0 }); ok(b2.session.fair.deck ~= nil); eq(a.session.fairN, 1)
  end)

  it("the dealer stands mid-hand: void, the next player deals", function()
    local sim = table3(); start(); b:stand(); sim:run(3)
    eq(a.session.state.players, { 1, 3 }); eq(events(a)[1].verdict, "void")
    eq({ a.session.fair.d, a.session.fair.p, a.session.fair.stage }, { 3, { 1, 3 }, "dealt" }); ok(c.session.fair.deck ~= nil)
  end)

  it("a player stands during the shuffle: the round restarts without him", function()
    local sim = table3(); local restore = drop(b, "SED"); start(); eq(a.session.fair.stage, "seed")
    restore(); c:stand(); sim:run(1); eq({ a.session.fair.p, a.session.fair.stage }, { { 1, 2 }, "dealt" })
  end)

  it("the host leaves mid-hand: the next host carries the same hand on", function()
    local sim = table3(); start(); local h1 = a.session.fair.h
    a:stand(); sim:run(2); eq(b.session.role, "host"); eq({ b.session.fair.h, b.session.fair.stage }, { h1, "dealt" })
    finish(b); sim:run(1)
    eq(events(b)[1].verdict, "ok"); eq(events(c)[1].verdict, "ok")
  end)

  it("a resync after the same hand keeps what it saw; a missed event drops it", function()
    local sim = table3(); start(); auto(1)
    local r = c.session.fair; local lied = r.lied
    eq(c.session.seq, a.session.seq); eq(r.q, a.session.seq)
    a.session:snapshotTo(C); sim:run(1)
    r = c.session.fair; ok(r.base ~= nil); ok(r.log ~= nil); eq(r.lied, lied)
    local restore = drop(c, "EV"); auto(1); restore()
    ok(c.session.seq < a.session.seq)
    a.session:snapshotTo(C); sim:run(1)
    r = c.session.fair; eq(c.session.seq, a.session.seq); eq(r.base, nil); eq(r.log, nil)
    finish(); sim:run(1)
    eq(events(c)[1].verdict, "unseen"); eq(events(a)[1].verdict, "ok")
  end)

  it("a reveal before the hand is over, and a void or reveal from another seat, are refused", function()
    local sim = table3(); start(); local q, h = a.session.seq, a.session.fair.h
    a:receive("WHISPER", B, act{ k = "fair", op = "reveal", h = h, s = { SEED, SEED, SEED } })
    a:receive("WHISPER", C, act{ k = "fair", op = "void", h = h })
    a:receive("WHISPER", C, act{ k = "fair", op = "reveal", h = h, s = { SEED, SEED, SEED } })
    sim:run(1); eq(a.session.seq, q)
  end)

  it("the status line follows the round", function()
    sim = Sim.new(); a = sim:add(A, { cls = "MAGE" }); sim:run(1)
    a:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(1)
    eq({ ns.Deal.status(a.session) }, {})
    table2(); start(); eq({ ns.Deal.status(a.session) }, {})
    finish(); sim:run(1); eq({ ns.Deal.status(a.session) }, { "fair.last", "ok" })
    sim:run(2); eq(a.session.fair.stage, "dealt"); eq({ ns.Deal.status(a.session) }, { "fair.last", "ok" })
    a.session:play(0, { k = "void" }); eq({ ns.Deal.status(a.session) }, { "fair.void" })
    sim:run(1); eq(a.session.fair.stage, "dealt"); eq({ ns.Deal.status(a.session) }, { "fair.void" })
    local T = ns.Locale.tables
    eq(T.bg["fair.v.ok"], "проверена"); eq(T.bg["fair.v.bad"], "нередовна"); eq(T.en["fair.v.ok"], "verified")
    eq(T.bg["fair.v.unseen"], "не съм я гледал цялата"); eq(T.bg["fair.waiting"], "Чакаме %s за разбъркването…")
  end)

  -- Carried items (b), (c), (d).
  it("a member who relogs while no round is open still takes the host's next open", function()
    local sim = table2(); start(); auto(6); sim:run(2)                         -- hand 2 dealt by the host
    eq({ a.session.fairN, a.session.fair.d, a.session.fair.stage }, { 2, 1, "dealt" })
    local restore = drop(a, "HI"); local b2 = relog(B); sim:run(0); restore()  -- b2 holds no session yet
    eq(b2.session, nil)
    a.session:play(0, { k = "void" })                                         -- no round open, one hand counted
    eq(a.session.fair, nil); eq(ns.Ext.fair.snap(a.session), { n = 1 })
    local syn = #sentOf("SYN")
    a.session:snapshotTo(B); sim:run(1)
    eq(#sentOf("SYN"), syn)                                                   -- the open was not refused
    eq({ b2.session.fairN, b2.session.fair.h, b2.session.fair.d, b2.session.fair.stage }, { 2, a.session.fair.h, 1, "dealt" })
  end)

  it("a new host after the last hand of a match waits for its reveal", function()
    table3(); start(); local n = playMatch()                                   -- how many hands the match takes
    local sim = table3(); start()
    local _, last = playMatch(n)
    a:stand(); sim:run(1); eq(b.session.role, "host"); ok(b.session.fairTimer)
    sim:run(18)
    for _, cl in ipairs{ b, c } do eq(#events(cl), n - 1) end
    sim:run(3)
    for _, cl in ipairs{ b, c } do
      eq(#events(cl), n); eq({ events(cl)[n].verdict, events(cl)[n].why, events(cl)[n].h }, { "bad", "noreveal", last })
    end
  end)

  it("a member that missed the reveal learns from its resync that it did not see the hand", function()
    local sim = table2(); d:watch(tid); sim:run(1); start(); auto(5); local h1 = a.session.fair.h
    local restore = drop(d, "EV"); auto(1); sim:run(2); restore()
    eq(#events(d), 0); eq(events(a)[1].verdict, "ok")
    a.session:snapshotTo(D); sim:run(1)
    eq(#events(d), 1); eq({ events(d)[1].verdict, events(d)[1].h }, { "unseen", h1 })
    eq(d.session.fair.h, a.session.fair.h)
  end)

  -- Review M1-M3.
  it("the host hands off while the dealer's reveal is in flight, and the dealer takes over: проверена", function()
    local sim = table3(); start(); local h = a.session.fair.h; eq(a.session.fair.d, 2)
    drop(a, "ACT", asks("reveal")); finish()
    eq(b.session.fair.revealed, true); eq(a.session.fair.stage, "dealt")      -- the reveal went to A and was lost
    a:stand(); sim:run(2); eq(b.session.role, "host")
    for _, cl in ipairs{ b, c } do
      eq(#events(cl), 1); eq({ events(cl)[1].verdict, events(cl)[1].h }, { "ok", h })
    end
    sim:run(25)
    for _, cl in ipairs{ b, c } do eq(#events(cl), 1) end
  end)

  it("the host hands off while a member dealer's reveal is in flight: the dealer reveals to the new host", function()
    local sim = table3(); start(); finish(); sim:run(2)
    local h = a.session.fair.h; eq({ a.session.fair.d, a.session.fair.stage }, { 3, "dealt" })
    drop(a, "ACT", asks("reveal")); finish()
    eq(c.session.fair.revealed, true); eq(a.session.fair.stage, "dealt")
    a:stand(); sim:run(2); eq(b.session.role, "host")
    for _, cl in ipairs{ b, c } do
      eq(#events(cl), 2); eq({ events(cl)[2].verdict, events(cl)[2].h }, { "ok", h })
    end
  end)

  it("a host-dealer's stand and void both lost on the way: the new host voids the hand", function()
    local sim = table3(); start(); finish(); sim:run(2); finish(); sim:run(2)
    local h = a.session.fair.h; eq({ a.session.fair.d, a.session.fair.stage, a.session.fairN }, { 1, "dealt", 3 })
    local fromA = function(sender) return sender == A end
    drop(b, "EV", fromA); drop(c, "EV", fromA)                                -- A's stand and void never arrive
    a:stand(); sim:run(3); eq(b.session.role, "host")
    for _, cl in ipairs{ b, c } do
      eq(#events(cl), 3); eq({ events(cl)[3].verdict, events(cl)[3].h }, { "void", h })
    end
    local r = b.session.fair
    eq({ r.p, r.d, r.stage, b.session.fairN }, { { 2, 3 }, 3, "dealt", 3 }); ok(c.session.fair.deck ~= nil)
  end)

  it("a dealer whose void request was lost asks again after its next snapshot", function()
    local sim = table3(); start(); local h1 = a.session.fair.h; auto(1)
    local restore = drop(a, "ACT", asks("void"))
    local b2 = relog(B); sim:run(3)
    eq(#events(a), 0); eq({ b2.session.fair.h, b2.session.fair.voidAsked }, { h1, true })
    restore(); a.session:snapshotTo(B); sim:run(3)
    eq(#events(a), 1); eq(events(a)[1].verdict, "void")
    ok(a.session.fair.h ~= h1); eq({ a.session.fair.d, a.session.fair.stage }, { 2, "dealt" }); ok(b2.session.fair.deck ~= nil)
  end)
end)
