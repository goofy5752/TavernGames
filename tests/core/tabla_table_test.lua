local Sim = require("sim")
local ns = Sim.ns
local E = ns.Engines.tabla

local A, B, W = "Иван Петров", "Мария Стоянова", "Гледач Гледачев"
local SEED = ("ff"):rep(16)
local ZERO, SA = ("00"):rep(16), ("01"):rep(16)
local COMMIT = "352302489bc2fcf025cf00cda8308033f97ac87712ce90b4d7cd72c58e4c3af9"
local FIRST = { { 24, 20 }, { 24, 20 }, { 13, 9 }, { 13, 9 } } -- a legal first move of seat 1 with 4:4
local sim, a, b, w
local REAL = ns.Ext.dice

-- A table of Табла hosted by a, watched by w; B is not seated yet. The dice
-- extension is the real one again (a `rigged` test that failed left it off).
local function table2(turn)
  ns.Ext.dice = REAL
  sim = Sim.new()
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  w = sim:add(W, { cls = "DRUID" })
  sim:run(1)
  local tid = a:openTable{ game = "tabla", access = "guild", turn = turn or 45 }; sim:run(3)
  w:watch(tid); sim:run(1)
  return sim, tid
end

local function seat(tid) b:sit(tid or a.session.tid, 2); sim:run(1) end

-- The `a` of every EV sent to `name` after index `from` of sim.sent, in order.
local function evs(name, from)
  local out = {}
  for i = from + 1, #sim.sent do
    local m = sim.sent[i]
    if m.target == name and m.msg.t == "EV" then out[#out + 1] = m.msg.a end
  end
  return out
end

-- The "fair" payloads that client emits from now on.
local function fairs(cl)
  local list = {}
  cl:on("fair", function(e) list[#list + 1] = e end)
  return list
end

-- Drops every throw ACT of `name` with that op while its client believes it
-- sent it -> a function that lifts it, {n = how many were dropped}.
local function mute(name, op)
  local env, dropped, on = sim.envs[name], { n = 0 }, true
  local send = env.send
  env.send = function(channel, target, msg)
    local act = msg.t == "ACT" and msg.a
    if on and type(act) == "table" and act.k == "throw" and act.op == op then dropped.n = dropped.n + 1; return end
    return send(channel, target, msg)
  end
  return function() on = false end, dropped
end

-- Does `msg` hold any of `words` as a key or a value, at any depth?
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

-- A seed with which the opener, throwing alone, gets `want` for throw h (what a modified host does).
local function grind(tid, h, want, other)
  for i = 1, 100000 do
    local x = string.format("%032x", i)
    local d1, d2 = ns.Fair.dice(other and { x, other } or { x }, tid .. "/" .. h)
    if d1 == want[1] and d2 == want[2] then return x end
  end
end

-- B hosts after A's silence; A then takes the table back under a higher epoch with B's state,
-- 6:6 on the board for itself and `proof(h)` as the last throw; -> A's session.
local function retake(tid, proof)
  sim:offline(A)
  for _ = 1, 200 do if b.session.role == "host" then break end; sim:run(1) end
  local sa = a.session
  sa.state = ns.Util.copy(b.session.state)
  sa.epoch, sa.seq, sa.throw = b.session.epoch + 1, b.session.seq + 3, nil
  local st = sa.state
  st.dice, st.left, st.cv, st.xfer, st.phase, st.turn = { 6, 6 }, { 6, 6, 6, 6 }, nil, nil, "move", 1
  sa.diceProof = proof(sa.seq - 1)
  sim:online(A); sa:snapshotTo(B); sim:run(1)
  return sa
end

-- B hosts after A's silence; A then takes the table back under a higher epoch with B's state and
-- B's last proof, changed by set(state, A's session), by its snapshot or (tbl) by its TBL, which
-- makes B ask for one; -> A's session.
local function takeBack(set, tbl)
  sim:offline(A)
  for _ = 1, 200 do if b.session.role == "host" then break end; sim:run(1) end
  local sa = a.session
  sa.state, sa.diceProof = ns.Util.copy(b.session.state), ns.Util.copy(b.session.diceProof)
  sa.epoch, sa.seq, sa.throw = b.session.epoch + 1, b.session.seq + 50, nil
  set(sa.state, sa)
  sim:online(A)
  if tbl then sa.lastAnnounce = nil; sa:sendTBL() else sa:snapshotTo(B) end
  sim:run(2)
  return sa
end

-- Copied verbatim from tests/engines/tabla_test.lua.
local function arr(m) local t = {} for i = 1, 24 do t[i] = (m and m[i]) or 0 end return t end
local function sum(t) local n = 0 for i = 1, 24 do n = n + t[i] end return n end
local GAME = { std = 1, tapa = 2, gul = 3 }

-- A position with `turn` about to roll. m1/m2: own point -> count; off defaults to the rest of 15.
local function pos(var, turn, m1, m2, o)
  o = o or {}
  local s = E.new{}
  s.game, s.var = GAME[var], var
  s.pts, s.pin = { arr(m1), arr(m2) }, { arr(o.pin1), arr(o.pin2) }
  s.bar = o.bar or { 0, 0 }
  s.off = {}
  for seat = 1, 2 do
    s.off[seat] = (o.off and o.off[seat]) or (15 - sum(s.pts[seat]) - s.bar[seat])
  end
  s.rolls = o.rolls or { 0, 0 }
  s.turn, s.phase = turn, "roll"
  return s
end

-- A seated table where nothing throws by itself, every client at a copy of `state`
-- (nothing is thrown before B sits, so the extension goes off after table2).
local function rigged(state)
  table2(); ns.Ext.dice = {}; seat()
  a.session.state, b.session.state, w.session.state = ns.Util.copy(state), ns.Util.copy(state), ns.Util.copy(state)
  return sim
end

-- The host sets the dice by hand (the extension is off in `rigged`).
local function dice(x, y) a.session:play(0, { k = "dice", d = { x, y } }); sim:run(1) end

-- The "result" payloads that client emits from now on.
local function results(cl)
  local list = {}
  cl:on("result", function(r) list[#list + 1] = r end)
  return list
end

-- Every client at the same Гюлбара turn (game 3): A's 4:4 of throw 6 is its roll number `rolls`,
-- a cascade from the fourth on -> B's "fair" events from now on, A's state, A's session.
local function gul(rolls)
  local sim, tid = table2(); seat()
  for _, cl in ipairs{ a, b, w } do
    local st = cl.session.state; st.game, st.var, st.rolls[1] = 3, "gul", rolls
    if rolls >= E.CASCADE_ROLL then st.cv, st.xfer = 4, false end
    cl.session.diceProof.t = rolls
  end
  eq(E.thrown(b.session.state), 0); return fairs(b), a.session.state, a.session
end

describe("tabla at the table", function()
  it("two players throw together: three events a throw, the dice on no wire, the same board for everyone", function()
    local sim, tid = table2(); local mark = #sim.sent; seat(); eq(tid, "Иван Петров#1700000001")
    eq({ ns.Fair.dice({ SEED, SEED }, tid .. "/3") }, { 6, 1 }); eq({ ns.Fair.dice({ SEED, SEED }, tid .. "/6") }, { 4, 4 })
    local st = a.session.state                                                        -- sit, start, the opening throw (seat 1 starts), its own throw
    eq({ st.phase, st.turn, st.dice, st.left, a.session.seq }, { "move", 1, { 4, 4 }, { 4, 4, 4, 4 }, 8 })
    local ev = evs(B, mark); eq(#ev, 7); eq(ev[1], { k = "start" })
    eq(ev[2], { k = "throw", op = "open", h = 3, c = COMMIT }); eq(ev[3], { k = "throw", op = "commit", h = 3, seat = 2, c = COMMIT })
    eq(ev[4], { k = "throw", op = "seeds", h = 3, s = { SEED, SEED } }); eq({ ev[5].op, ev[5].h, ev[7].op, ev[7].h }, { "open", 6, "seeds", 6 })
    eq(b.session.state, st); eq(w.session.state, st)
    for _, cl in ipairs{ a, b, w } do
      eq(cl.session.diceLast, { h = 6, verdict = "ok", by = A }); eq(cl.session.diceSeen, { ok = 2, alone = 0, bad = 0 }); eq(cl.session.throw.done, true)
      eq({ ns.Dice.status(cl.session) }, { "dice.ok", "good" })
    end
    eq(sim:count(function(m) return m.msg.t == "EV" and m.msg.a.k == "dice" end), 0)
    eq(sim:count(function(m) return m.from == B and m.msg.t == "ACT" end), 4)             -- a commit and a seed per throw
    eq(sim:count(function(m) return m.channel == "GUILD" and (m.msg.t == "EV" or m.msg.t == "ACT") end), 0)
  end)

  it("a turn is one move event, then the next throw", function()
    local sim, tid = table2(); seat(); local seen = fairs(w)
    eq({ a:act{ k = "move", steps = { { 24, 20 } } } }, { nil, "move" }); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)
    local st = b.session.state; eq({ st.turn, st.phase, st.dice, b.session.seq }, { 2, "move", { 4, 3 }, 12 }); eq(b.session.diceLast.h, 10)
    eq({ #seen, seen[1].h, seen[1].verdict, seen[1].game }, { 1, 10, "ok", "tabla" }); eq(w.session.state, a.session.state)
    ok(b:act(E.auto(b.session.state, 2))); sim:run(1); eq({ a.session.state.turn, a.session.state.dice, a.session.seq }, { 1, { 1, 4 }, 16 })
  end)

  it("the table hook takes only what fits the throw", function()
    local sim, tid = table2(); seat(); local s, T = b.session, ns.Ext.dice.table
    eq(T(s, { k = "throw", op = "open", h = s.seq + 1, c = COMMIT }), nil)               -- the engine wants no dice now
    eq(T(s, { k = "throw", op = "seeds", h = 6, s = { SEED, SEED } }), nil)             -- that throw is closed
    eq(T(s, { k = "move", steps = {} }), nil); eq(ns.Ext.dice.act(a.session, 2, { k = "move", steps = {} }), { k = "move", steps = {} })
    eq(ns.Ext.dice.act(a.session, 2, { k = "throw", op = "seed", h = 6, s = SEED }), nil); eq(a.session.seq, 8)
    eq(ns.Ext.dice.snap(a.session), { p = { h = 6, c = { COMMIT, COMMIT }, s = { SEED, SEED }, r = 1, t = 1 } }); eq(ns.Dice.status({ engine = function() return ns.Engines.ttt end }), nil)   -- not a dice game
  end)
  it("a guest that never reveals gets no second throw: after DICE_WAIT the host throws alone", function()
    local sim, tid = table2(); for i = 1, 16 do sim.nextRandom[i] = 1 end; local mark = #sim.sent      -- A's first seed is SA, B's is SEED
    mute(B, "seed"); seat()
    eq({ a.session.state.phase, a.session.seq, a.session.throw.h, a.session.throw.commits[2] }, { "open", 4, 3, COMMIT })
    eq({ ns.Dice.status(a.session) }, { "dice.rolling", "inkDim" }); eq(sim:count(function(m) return mentions(m.msg, { SA }) end), 0)
    sim:run(9); eq({ a.session.state.phase, a.session.seq }, { "open", 4 })
    sim:run(1); local st = a.session.state
    eq({ ns.Fair.dice({ SA }, tid .. "/3") }, { 4, 1 }); eq({ st.phase, st.turn, st.dice }, { "roll", 1, { 4, 1 } }); eq(b.session.state.dice, { 4, 1 })
    local ev = evs(W, mark)                                                                -- sit, start, then the throw
    eq({ ev[3].op, ev[4].op, ev[5] }, { "open", "commit", { k = "throw", op = "seeds", h = 3, s = { SA } } })
    eq(ev[6], { k = "throw", op = "open", h = 6, c = COMMIT })                             -- the next throw, not this one again
    eq(a.session.diceLast, { h = 3, verdict = "alone", by = A, silent = B, n = 1 }); eq({ ns.Dice.status(w.session) }, { "dice.rolling", "inkDim" })
    eq({ b.session.diceUnheard, ns.Dice.alarm(b.session), a.session.diceUnheard }, { 1, false, nil })
    sim:run(10); eq({ a.session.diceLast.h, a.session.diceLast.n, a.session.state.phase }, { 6, 2, "move" }); eq({ ns.Dice.status(a.session) }, { "dice.aloneMany", "gold", A, 2 })
    eq({ b.session.diceUnheard, ns.Dice.alarm(b.session), ns.Dice.alarm(a.session), ns.Dice.alarm(w.session) }, { 2, true, false, false })
    eq(ns.Dice.tip(b.session), { { "ink", "dice.tip" }, { "red", "dice.unheard", 2 } })
    sim, tid = table2(); mute(B, "commit"); seat(); sim:run(10)                              -- the host never sees the guest's commit and throws alone
    eq({ b.session.diceUnheard, a.session.diceLast.verdict }, { 1, "alone" })
  end)
  it("the opener's seed leaves its client only in the event that fixes the dice", function()
    local sim, tid = table2(); for i = 1, 16 do sim.nextRandom[i] = 1 end; seat()
    local first, guest
    for i, m in ipairs(sim.sent) do
      if not first and mentions(m.msg, { SA }) then first = i end
      if not guest and m.from == B and m.msg.t == "ACT" and m.msg.a.op == "seed" then guest = i end
    end
    ok(guest < first); eq({ sim.sent[first].msg.t, sim.sent[first].msg.a.op, sim.sent[first].msg.a.s }, { "EV", "seeds", { SA, SEED } })
    eq(a.session.state.dice ~= nil, true); eq({ ns.Fair.dice({ SA, SEED }, tid .. "/3") }, { 3, 5 })
  end)
  it("a guest that was away when the throw opened commits from the snapshot", function()
    local sim, tid = table2(); seat(); sim:offline(B); ok(a:act{ k = "move", steps = FIRST }); sim:run(2)
    eq({ a.session.state.phase, a.session.throw.h, a.session.throw.commits[2], a.session.seq }, { "roll", 10, nil, 10 })
    eq(ns.Ext.dice.snap(a.session), { h = 10, d = 1, c = { COMMIT }, p = { h = 6, c = { COMMIT, COMMIT }, s = { SEED, SEED }, r = 1, t = 1 } })
    local b2 = sim:relog(B); sim:run(2)
    eq({ a.session.state.phase, a.session.state.dice, a.session.seq }, { "move", { 4, 3 }, 12 }); eq(a.session.diceLast, { h = 10, verdict = "ok", by = A })
    eq(b2.session.diceLast.verdict, "ok"); eq(b2.session.state, a.session.state)
  end)
  it("a guest that crashes after its commit cannot open it: the host throws alone and nobody is blamed", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local atA = fairs(a)
    local b2 = sim:crash(B); local atB = fairs(b2); sim:run(3)
    eq({ b2.session.throw.h, b2.session.throw.reload, b2.session.throw.seed, b2.session.throw.foul }, { 3, true, nil, nil })
    sim:run(8); eq({ atA[1].verdict, atA[2].verdict, atB[1].verdict, atB[2].verdict }, { "alone", "ok", "alone", "ok" })
    eq({ b2.session.diceUnheard, ns.Dice.alarm(b2.session), ns.Dice.alarm(a.session) }, { 1, false, false }); eq(b2.session.state, a.session.state)   -- counted, not red
  end)
  it("the host vanishes mid-throw: the new host throws under a new number", function()
    local sim, tid = table2(); local lift = mute(B, "seed"); seat(); sim:offline(A); lift()
    for _ = 1, 100 do if b.session.role == "host" then break end; sim:run(1) end                 -- 75 s of silence
    eq({ b.session.role, b.session.throw.h, b.session.throw.d, b.session.state.phase }, { "host", 5, 2, "open" })
    sim:run(10); eq({ ns.Fair.dice({ SEED }, tid .. "/5") }, { 2, 2 })
    eq(b.session.diceLast, { h = 5, verdict = "alone", by = B, silent = A, n = 1 }); eq({ b.session.state.dice, b.session.state.phase }, { { 2, 2 }, "open" })
  end)
  it("a host that throws again over a seed it was sent is caught by that guest; dice that no throw gave are flagged", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local atB, atW = fairs(b), fairs(w)
    ns.Dice.open(a.session); sim:run(1)                                                       -- a second open over throw 3
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 3, "bad", "dodge" }); eq(#atW, 0); eq(ns.Dice.alarm(b.session), true)
    a.session:play(0, { k = "dice", d = { 6, 2 } }); sim:run(1)
    eq({ atW[1].verdict, atW[1].why, w.session.state.dice }, { "bad", "forged", { 6, 2 } }); eq({ ns.Dice.status(w.session) }, { "dice.rolling", "red" })
    eq(ns.Dice.tip(w.session)[2], { "red", "dice.tip.bad", "forged" })
  end)
  it("a snapshot from my own host that drops or rewrites a throw I revealed to is caught", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local atB = fairs(b)                 -- B holds throw 3 and has sent its seed
    a.session.throw = nil; a.session:snapshotTo(B); sim:run(1)
    eq({ atB[1].h, atB[1].verdict, atB[1].why }, { 3, "bad", "dodge" })
    sim:run(10); local s = b.session                                                          -- throw 6 opens; B commits and reveals again
    a.session.throw.commits[2] = ns.Fair.commit(ZERO); a.session:snapshotTo(B); sim:run(1)    -- the host's own commit under B's seat, not B's own
    a.session:play(0, { k = "throw", op = "seeds", h = s.throw.h, s = { SEED, ZERO } }); sim:run(1)
    eq({ atB[#atB].verdict, atB[#atB].why }, { "bad", "mine" })
    local old = s.throw.h; ns.Ext.dice.adopted(s, nil, { q = s.seq, fr = { h = 3, d = 1, c = { COMMIT } } }, {}); eq(s.throw.h, old)   -- an fr at or below h 6 is not taken
  end)
  it("seeds that do not open the commits are refused", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local s, T = b.session, ns.Ext.dice.table
    eq(T(s, { k = "throw", op = "seeds", h = 3, s = { SEED, ZERO } }), nil); eq(T(s, { k = "throw", op = "seeds", h = 3, s = { [2] = SEED } }), nil)
    eq(T(s, { k = "throw", op = "seeds", h = 3, s = { SEED, SEED, SEED } }), nil); eq(T(s, { k = "throw", op = "seeds", h = 4, s = { SEED, SEED } }), nil)
    eq(T(s, { k = "throw", op = "commit", h = 3, seat = 2, c = COMMIT }), nil); eq(T(s, { k = "throw", op = "commit", h = 3, seat = 1, c = COMMIT }), nil)
    eq({ s.state.phase, s.throw.done }, { "open", nil }); eq(T(s, { k = "throw", op = "seeds", h = 3, s = { SEED, SEED } }), true); eq(s.state.dice, { 6, 1 })
  end)

  it("a host that commits in the guest's name and picks both seeds is caught by that guest", function()
    local sim, tid = table2(); local lift = mute(B, "commit"); seat(); lift(); local atB, atW = fairs(b), fairs(w)
    a.session:play(0, { k = "throw", op = "commit", h = 3, seat = 2, c = ns.Fair.commit(ZERO) }); sim:run(1)
    eq({ b.session.throw.foul, b.session.throw.sent, b.session.throw.done }, { "mine", nil, nil })
    a.session:play(0, { k = "throw", op = "seeds", h = 3, s = { SEED, ZERO } }); sim:run(1)   -- both seeds are the host's
    eq({ atB[1].h, atB[1].verdict, atB[1].why, atW[1].h, atW[1].verdict }, { 3, "bad", "mine", 3, "ok" })
    eq(sim:count(function(m) return m.from == B and m.msg.t == "ACT" and m.msg.a.op == "seed" and m.msg.a.h == 3 end), 0)
    eq(b.session.state, a.session.state); eq({ b.session.throw.done, b.session.diceLast.verdict }, { true, "ok" })   -- the game goes on
    eq({ ns.Dice.status(b.session) }, { "dice.ok", "red" }); eq(ns.Dice.tip(b.session), { { "ink", "dice.tip" }, { "red", "dice.tip.bad", "mine" } })
    eq({ ns.Dice.alarm(w.session), ns.Dice.alarm(a.session), b.session.diceSeen.bad }, { false, false, 1 })
  end)
  it("the guest says its commit and then its seed again every 3 s, twice at most", function()
    local sim, tid = table2(); local lift, dropped = mute(B, "commit"); seat(); local atA = fairs(a)
    sim:run(2); eq({ dropped.n, a.session.throw.commits[2] }, { 1, nil })
    lift(); sim:run(1); eq({ atA[1].h, atA[1].verdict, b.session.diceUnheard }, { 3, "ok", nil })   -- the repeat got through
    eq(sim:count(function(m) return m.from == B and m.msg.t == "ACT" and m.msg.a.h == 3 end), 2)     -- one commit, one seed
    sim:run(20); eq(sim:count(function(m) return m.from == B and m.msg.t == "ACT" end), 4)           -- nothing is said again after a close
    sim, tid = table2(); lift, dropped = mute(B, "seed"); seat(); sim:run(2); eq(dropped.n, 1)
    sim:run(7); eq({ dropped.n, b.session.throw.h, b.session.throw.sent }, { 3, 3, true })           -- at 3 s and 6 s, then silence
  end)
  it("the act hook takes a commit and a seed only from the other seat, for the running throw, when they fit", function()
    local sim, tid = table2(); mute(B, "commit"); seat(); local s, act, need = a.session, ns.Ext.dice.act, ns.Ext.dice.need
    eq(act(s, 2, { k = "throw", op = "seed", h = 3, s = SEED }), nil)                    -- a seed before its commit
    eq(act(s, 2, { k = "throw", op = "commit", h = 4, c = COMMIT }), nil)                -- another throw
    eq(act(s, 1, { k = "throw", op = "commit", h = 3, c = COMMIT }), nil)                -- the opener's own seat
    eq(act(s, 2, { k = "throw", op = "commit", h = 3, c = SEED }), nil)                  -- not a commit
    eq(act(s, 2, { k = "throw", op = "seeds", h = 3, s = { SEED, SEED } }), nil)         -- a member publishes nothing
    eq(act(s, 2, { k = "throw", op = "open", h = 4, c = COMMIT }), nil); eq({ s.seq, s.throw.commits[2] }, { 3, nil })
    eq(act(s, 2, { k = "throw", op = "commit", h = 3, c = COMMIT }), nil); eq({ s.seq, s.throw.commits[2] }, { 4, COMMIT })
    eq(act(s, 2, { k = "throw", op = "commit", h = 3, c = ns.Fair.commit(ZERO) }), nil)  -- a second commit
    eq(act(s, 2, { k = "throw", op = "seed", h = 3, s = ZERO }), nil)                    -- not the seed of that commit
    eq(act(s, 2, { k = "throw", op = "seed", h = 4, s = SEED }), nil); eq(act(s, 2, { k = "throw", op = "seed", h = 3, s = "ff" }), nil)
    eq({ s.seq, s.throw.commits[2], s.throw.done }, { 4, COMMIT, nil })
    need(s, { k = "dice", need = "dice" }); eq({ s.seq, s.throw.h }, { 4, 3 })           -- a running throw is not opened again
    s.fairTimer.cancel(); s.fairTimer = nil; need(s, { k = "dice", need = "dice" }); ok(s.fairTimer ~= nil); eq(s.seq, 4)
    eq(act(s, 2, { k = "throw", op = "seed", h = 3, s = SEED }), nil); eq({ s.seq, s.throw.done }, { 5, true }); eq(s.diceLast, { h = 3, verdict = "ok", by = A })
  end)
  it("a snapshot I asked for that lacks my throw counts as unheard; one that changes the opener's commit is a foul; a malformed throw is not taken", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local atB = fairs(b)
    a.session.throw = nil; b.session:requestSync(); sim:run(1)
    eq({ #atB, b.session.diceUnheard, b.session.throw == nil, ns.Dice.alarm(b.session) }, { 0, 1, true, false })
    local s, adopted = b.session, ns.Ext.dice.adopted
    local function take(fr) adopted(s, nil, { q = 4, fr = fr }, {}); return s.throw and s.throw.h end
    eq({ s.seq, take({ h = 5, d = 1, c = { COMMIT } }) }, { 4, nil })                     -- a number above the snapshot's
    eq(take({ h = 4, d = 2, c = { [2] = COMMIT } }), nil); eq(take({ h = 4, d = 3, c = { COMMIT } }), nil)   -- the opener is the host's seat
    eq(take({ h = 4, d = 1, c = { SEED } }), nil); eq(take({ h = 4, d = 1, c = { COMMIT, "zz" } }), nil)
    eq(take({ h = 4.5, d = 1, c = { COMMIT } }), nil); eq(take({ h = 4, d = 1 }), nil); eq(take("x"), nil)
    eq({ take({ h = 4, d = 1, c = { COMMIT } }), s.throw.asked, s.throw.own }, { 4, true, COMMIT })   -- well formed: taken, and I commit
    s.role = "host"; s.throw = nil; eq(take({ h = 4, d = 1, c = { COMMIT } }), nil); s.role = "player"   -- a host takes none
    sim, tid = table2(); mute(B, "seed"); seat(); atB = fairs(b)
    local t = a.session.throw; t.seed, t.commits[1] = ZERO, ns.Fair.commit(ZERO); a.session:snapshotTo(B); sim:run(1)
    eq({ b.session.throw.foul, b.session.throw.h, #atB }, { "commit", 3, 0 })
    sim:run(9); eq({ atB[1].h, atB[1].verdict, atB[1].why }, { 3, "bad", "commit" }); eq(b.session.state, a.session.state)
  end)
  it("a host that raises its own epoch over a throw I revealed to is caught; a host that really changed leaves it unheard", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local atB = fairs(b)                 -- B holds throw 3 and has sent its seed
    a.session.throw = nil; a.session.epoch = a.session.epoch + 1; a.session:sendTBL(); sim:run(1)   -- learnt from its TBL
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 3, "bad", "dodge" })
    eq({ b.session.diceUnheard, ns.Dice.alarm(b.session), b.session.host, b.session.epoch }, { nil, true, A, 2 })
    sim, tid = table2(); mute(B, "seed"); seat(); atB = fairs(b)
    a.session.throw = nil; a.session.epoch = a.session.epoch + 1; a.session:snapshotTo(B); sim:run(1)   -- learnt from its snapshot
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, b.session.diceUnheard }, { 1, 3, "bad", "dodge", nil })
    sim, tid = table2(); local lift = mute(B, "seed"); seat(); atB = fairs(b); sim:offline(A); lift()
    for _ = 1, 100 do if b.session.role == "host" then break end; sim:run(1) end                 -- the host is gone: B hosts
    eq({ b.session.role, #atB, b.session.diceUnheard, ns.Dice.alarm(b.session), b.session.throw.h }, { "host", 0, 1, false, 5 })
    eq({ ns.Dice.status(b.session) }, { "dice.rolling", "inkDim" }); eq(ns.Dice.tip(b.session), { { "ink", "dice.tip" }, { "red", "dice.unheard", 1 } })
  end)
  it("a snapshot that rewrites the dice of a throw I closed is caught, asked for or not, and I say so", function()
    local sim, tid = table2(); seat(); local atB, atW = fairs(b), fairs(w)                    -- throws 3 and 6 closed ok, dice 4:4
    eq({ ns.Dice.status(b.session) }, { "dice.ok", "good" })
    local st = a.session.state; st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }; a.session:snapshotTo(B); sim:run(1)
    eq({ b.session.state.dice, #atB, atB[1].h, atB[1].verdict, atB[1].why }, { { 6, 6 }, 1, 6, "bad", "forged" })
    eq({ ns.Dice.status(b.session) }, { "dice.bad", "red" }); eq(b.session.diceSeen, { ok = 1, alone = 0, bad = 1 })
    eq(w.session.diceCry, { h = 6, seat = 2, name = B, why = "forged" }); eq({ #atW, ns.Dice.alarm(w.session), ns.Dice.alarm(a.session) }, { 0, false, false })
    eq(ns.Dice.tip(w.session), { { "ink", "dice.tip" }, { "gold", "dice.cry", B, "forged" } })
    st.dice, st.left = { 4, 4 }, { 4, 4, 4, 4 }; a.session:snapshotTo(B); sim:run(1)          -- no snapshot turns it back to ok
    eq({ ns.Dice.status(b.session) }, { "dice.bad", "red" }); eq({ b.session.diceSeen.bad, b.session.diceSeen.ok, b.session.state }, { 1, 1, a.session.state })
    sim, tid = table2(); seat(); atB = fairs(b)                                               -- the same in a snapshot I asked for
    st = a.session.state; st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }; b.session:requestSync(); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, ns.Dice.alarm(b.session) }, { 1, 6, "bad", "forged", true })
    sim, tid = table2(); seat(); atB = fairs(b)                                               -- a host that keeps dice of its own and moves by them
    st = a.session.state; st.dice, st.left = { 6, 5 }, { 6, 5 }; ok(a:act(E.auto(st, 1))); sim:run(1)
    eq({ atB[1].h, atB[1].verdict, atB[1].why }, { 6, "bad", "forged" }); eq(ns.Dice.tip(b.session)[2], { "red", "dice.tip.bad", "forged" })
    eq({ ns.Dice.status(b.session) }, { "dice.ok", "red" })                                   -- the next throw was whole; the line stays red
    eq(b.session.state, a.session.state)                                                      -- the table is the host's; my line says what it is
  end)
  it("dice of a throw whose events never reached me: unheard when I asked for the snapshot, a dodge when it is pushed on me", function()
    local sim, tid = table2(); seat(); local atB = fairs(b); sim:offline(B); ok(a:act{ k = "move", steps = FIRST }); sim:run(11)
    eq({ a.session.diceLast.h, a.session.diceLast.verdict, a.session.state.dice ~= nil, ns.Util.same(a.session.state.dice, b.session.state.dice) }, { 10, "alone", true, false })
    sim:online(B); b.session:requestSync(); sim:run(1)
    eq({ #atB, b.session.diceUnheard, ns.Dice.alarm(b.session), b.session.seq }, { 0, 1, false, a.session.seq }); eq(b.session.state, a.session.state)
    sim, tid = table2(); seat(); atB = fairs(b); sim:offline(B); ok(a:act{ k = "move", steps = FIRST }); sim:run(11)
    sim:online(B); a.session:snapshotTo(B); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, b.session.diceUnheard }, { 1, 10, "bad", "dodge", nil })
  end)
  it("my seed outlives a /reload: a commit forged under my seat is still mine; after a crash such a throw is never ok", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local db = sim.envs[B].db
    eq(db.fairKeep, { dice = true, tid = tid, h = 3, me = B, seat = 2, c = COMMIT, seed = SEED })
    local b2 = sim:relog(B); local atB = fairs(b2); sim:run(1)                                -- the seed is said again, the throw is whole
    eq({ atB[1].h, atB[1].verdict, b2.session.diceUnheard, a.session.diceLast.verdict }, { 3, "ok", nil, "ok" }); eq(b2.session.state, a.session.state)
    eq(db.fairKeep, nil)                                                                      -- gone with its throw
    sim, tid = table2(); mute(B, "seed"); seat(); a.session.throw.commits[2] = ns.Fair.commit(ZERO)   -- the host puts a commit of its own under B's seat
    b2 = sim:relog(B); atB = fairs(b2); sim:run(1); eq({ b2.session.throw.foul, b2.session.throw.reload, b2.session.throw.seed }, { "mine", nil, SEED })
    a.session:play(0, { k = "throw", op = "seeds", h = 3, s = { SEED, ZERO } }); sim:run(1)
    eq({ atB[1].h, atB[1].verdict, atB[1].why, ns.Dice.alarm(b2.session) }, { 3, "bad", "mine", true })
    sim, tid = table2(); mute(B, "seed"); seat(); a.session.throw.commits[2] = ns.Fair.commit(ZERO)   -- the same after a crash: B cannot tell
    b2 = sim:crash(B); atB = fairs(b2); sim:run(1); eq({ b2.session.throw.foul, b2.session.throw.reload, b2.session.throw.seed }, { nil, true, nil })
    a.session:play(0, { k = "throw", op = "seeds", h = 3, s = { SEED, ZERO } }); sim:run(1)
    eq({ atB[1].h, atB[1].verdict, atB[1].why, atB[2].verdict }, { 3, "unseen", nil, "ok" }); eq(b2.session.diceSeen, { ok = 1, alone = 0, bad = 0, unseen = 1 })
    b2.session.throw = { h = 3, d = 1, done = true }; b2.session.diceLast = atB[1]; eq({ ns.Dice.status(b2.session) }, { "dice.unseen", "gold" })
    sim, tid = table2(); mute(B, "seed"); seat(); db = sim.envs[B].db; ok(db.fairKeep ~= nil); b:stand(); sim:run(1); eq(db.fairKeep, nil)   -- gone when I leave
    sim, tid = table2(); mute(B, "seed"); seat(); db = sim.envs[B].db; db.fairKeep.c = ns.Fair.commit(ZERO)   -- a record of another open is not taken
    b2 = sim:relog(B); sim:run(1); eq({ b2.session.throw.reload, b2.session.throw.seed, db.fairKeep }, { true, nil, nil })
  end)
  it("a snapshot's dice are proved by the last throw's commits and seeds: no rewritten die or open step gets through (P1-P3)", function()
    local sim, tid = table2(); seat(); local atB = fairs(b); local st, sa = a.session.state, a.session   -- throw 6 closed ok, 4:4, A to move
    eq({ ns.Fair.dice(sa.diceProof.s, tid .. "/6") }, { 4, 4 }); eq(b.session.diceProof, sa.diceProof)
    st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }; sa.seq = sa.seq + 1; b.session:requestSync(); sim:run(1)   -- P1: the host skips a number, I ask
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, b.session.diceUnheard }, { 1, 6, "bad", "forged", nil })
    eq({ ns.Dice.status(b.session) }, { "dice.bad", "red" }); eq(a.session.diceCry, { h = 6, seat = 2, name = B, why = "forged" })
    sim, tid = table2(); seat(); atB = fairs(b); st, sa = a.session.state, a.session            -- P2: the dice as thrown, the open steps rewritten, pushed
    st.left = { 6, 6, 6, 6 }; sa.seq = sa.seq + 1; sa:snapshotTo(B); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 6, "bad", "forged" })
    ok(a:act(E.auto(st, 1))); sim:run(1); eq(b.session.state, a.session.state); eq(ns.Dice.alarm(b.session), true)   -- the host moves by them: still red
    sim, tid = table2(); seat(); atB = fairs(b); st, sa = a.session.state, a.session            -- P3: the same at my own number under a raised epoch
    st.left = { 6, 6, 6, 6 }; sa.epoch = sa.epoch + 1; sa:snapshotTo(B); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 6, "bad", "forged" })
    sim, tid = table2(); seat(); atB = fairs(b); st, sa = a.session.state, a.session            -- dice with a proof of the host's own making
    st.dice, st.left = { 6, 1 }, { 6, 1 }; eq({ ns.Fair.dice({ SEED, SEED }, tid .. "/3") }, { 6, 1 })
    sa.diceProof = { h = 3, c = { COMMIT, COMMIT }, s = { SEED, SEED }, r = 1, t = 1 }; sa.seq = sa.seq + 1; sa:snapshotTo(B); sim:run(1)   -- the opening throw, told to be a roll
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 3, "bad", "forged" })
    sim, tid = table2(); seat(); ok(a:act{ k = "move", steps = FIRST }); sim:run(1); atB = fairs(b); st, sa = a.session.state, a.session   -- throw 10 is closed
    st.dice, st.left, st.turn = { 4, 4 }, { 4, 4, 4, 4 }, 1; eq(b.session.diceProof.h, 10)      -- an older throw than my last, whole and of its own turn
    sa.diceProof = { h = 6, c = { COMMIT, COMMIT }, s = { SEED, SEED }, r = 1, t = 1 }; sa.seq = sa.seq + 2; sa:snapshotTo(B); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 10, "bad", "forged" })
    sim, tid = table2(); seat(); atB = fairs(b); st, sa = a.session.state, a.session            -- a later throw with a seed in my name
    local x, y = ns.Fair.dice({ SEED, ZERO }, tid .. "/9"); st.dice, st.left = { x, y }, x == y and { x, x, x, x } or { x, y }
    sa.diceProof = { h = 9, c = { COMMIT, ns.Fair.commit(ZERO) }, s = { SEED, ZERO }, r = 1, t = 1 }; sa.seq = sa.seq + 1; sa:snapshotTo(B); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 9, "bad", "forged" })
    sim, tid = table2(); seat(); atB = fairs(b); st, sa = a.session.state, a.session            -- dice and no proof at all
    sa.diceProof = nil; sa.seq = sa.seq + 1; sa:snapshotTo(B); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 6, "bad", "forged" })
  end)
  it("a throw of mine that closed in events I lost is taken from its proof: whole, and nothing is counted", function()
    local sim, tid = table2(); local lift = mute(B, "seed"); seat(); local atB = fairs(b); sim:offline(B)   -- B committed to throw 3
    a.session:play(0, { k = "throw", op = "seeds", h = 3, s = { SEED, SEED } }); sim:run(1)       -- its seed got through; the seeds event did not
    eq({ a.session.diceLast.h, b.session.throw.h, b.session.throw.done, #atB }, { 3, 3, nil, 0 })
    lift(); sim:online(B); b.session:requestSync(); sim:run(1)
    eq({ atB[1].h, atB[1].verdict, atB[2].h, atB[2].verdict, b.session.diceUnheard, ns.Dice.alarm(b.session) }, { 3, "ok", 6, "ok", nil, false })
    eq(b.session.state, a.session.state); eq(b.session.diceProof, a.session.diceProof)
    sim, tid = table2(); mute(B, "seed"); seat(); atB = fairs(b); sim:offline(B); sim:run(10)      -- the same throw made alone meanwhile
    sim:online(B); b.session:requestSync(); sim:run(1)
    eq({ atB[1].h, atB[1].verdict, b.session.diceUnheard, ns.Dice.alarm(b.session) }, { 3, "alone", 1, false })
  end)
  it("a host that takes the table back from me with dice of its own making is caught (round 3)", function()
    local sim, tid = table2(); seat(); local atB = fairs(b)
    local sa = retake(tid, function(h) local x = grind(tid, h, { 6, 6 }); return { h = h, c = { ns.Fair.commit(x) }, s = { x }, r = 1, t = 1 } end)
    eq({ b.session.role, b.session.host, b.session.state.dice }, { "player", A, { 6, 6 } })   -- a throw made alone that I never saw, pushed on me
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, ns.Dice.alarm(b.session) }, { 1, sa.seq - 1, "bad", "dodge", true })
    ok(a:act(E.auto(sa.state, 1))); sim:run(1); eq({ ns.Dice.alarm(b.session), ns.Dice.tip(b.session)[2] }, { true, { "red", "dice.tip.bad", "dodge" } })
    sim, tid = table2(); seat(); atB = fairs(b)                                                -- two seeds of its own, one under my seat
    sa = retake(tid, function(h) local x = grind(tid, h, { 6, 6 }, ZERO); return { h = h, c = { ns.Fair.commit(x), ns.Fair.commit(ZERO) }, s = { x, ZERO }, r = 1, t = 1 } end)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, ns.Dice.alarm(b.session) }, { 1, sa.diceProof.h, "bad", "forged", true })
  end)
  it("my seed of an earlier throw proves no later one (round 3)", function()
    local sim, tid = table2(); seat(); local atB = fairs(b); local st, sa = a.session.state, a.session
    local x = grind(tid, 9, { 6, 6 }, SEED); st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }       -- B's real seed and commit of throws 3 and 6, under number 9
    sa.diceProof = { h = 9, c = { ns.Fair.commit(x), COMMIT }, s = { x, SEED }, r = 1, t = 1 }; sa.seq = 10; b.session:requestSync(); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, b.session.diceUnheard }, { 1, 9, "bad", "forged", nil })
  end)
  it("a host that was away and comes back under the new host blames nobody", function()
    local sim, tid = table2(); seat(); local atA, atB = fairs(a), fairs(b); sim:offline(A)
    for _ = 1, 200 do if b.session.role == "host" then break end; sim:run(1) end
    sim:online(A); sim:run(40)                                                                 -- A hears B's table and follows it
    eq({ a.session.role, a.session.host, b.session.role, ns.Dice.alarm(a.session), ns.Dice.alarm(b.session) }, { "player", B, "host", false, false })
    for _, e in ipairs(atA) do ok(e.verdict ~= "bad", "A: " .. tostring(e.why)) end
    for _, e in ipairs(atB) do ok(e.verdict ~= "bad", "B: " .. tostring(e.why)) end
    eq(a.session.state, b.session.state); eq(a.session.diceProof, b.session.diceProof)
  end)
  it("a cascade is what the events give: no number beyond the moves I missed, none outside its rules (round 3)", function()
    local atB, st, sa = gul(4); sim:offline(B); ok(a:act(E.auto(st, 1))); sim:run(1)           -- an honest move while B hears nothing
    st = sa.state; eq({ sa.seq, st.cv ~= nil, (E.thrown(st)) }, { 9, true, 1 })
    sim:online(B); b.session:requestSync(); sim:run(1)
    eq({ #atB, b.session.diceUnheard, ns.Dice.alarm(b.session), b.session.seq }, { 0, 1, false, 9 }); eq(b.session.state, st)   -- a number I did not see played: counted, not blamed
    atB, st, sa = gul(4); st.cv, st.left = 6, { 6, 6, 6, 6 }; sa.seq = sa.seq + 1; sa:snapshotTo(B); sim:run(1)   -- two numbers on in one event
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 6, "bad", "forged" })
    atB, st, sa = gul(4); sim:offline(B); ok(a:act(E.auto(st, 1))); sim:run(1); sim:online(B)   -- one honest move, then one number too many
    st = sa.state; st.cv, st.left, st.xfer, st.turn = 6, { 6, 6, 6, 6 }, false, 1; b.session:requestSync(); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 6, "bad", "forged" })
    atB, st, sa = gul(4); for _, cl in ipairs{ a, b } do cl.session.state.cv = nil end          -- a plain double turned into a cascade
    st.rolls[1], st.cv, st.left = 3, 5, { 5, 5, 5, 5 }; sa.seq = sa.seq + 1; sa:snapshotTo(B); sim:run(1)   -- before the fourth roll
    eq({ E.thrown(st), #atB, atB[1].verdict, atB[1].why }, { false, 1, "bad", "forged" })
    local sim, tid = table2(); seat(); atB = fairs(b); st, sa = a.session.state, a.session      -- the reviewer's probe: not even Гюлбара's roll count
    st.var = "gul"; st.cv, st.xfer, st.left = 6, false, { 6, 6, 6, 6 }; sa.seq = sa.seq + 1; sa:snapshotTo(B); sim:run(1)
    eq({ E.thrown(st), #atB, atB[1].h, atB[1].verdict, atB[1].why }, { false, 1, 6, "bad", "forged" })
  end)
  it("a cascade number I did not see played is never silent, whoever hosts and whatever number of events it names (round 4)", function()
    for _, by in ipairs{ "snp", "tbl" } do                                                     -- the reviewer's probe: a standard table called Гюлбара
      local sim, tid = table2(); seat(); local atB = fairs(b)
      takeBack(function(st)
        st.var, st.rolls[1], st.cv, st.xfer, st.left = "gul", E.CASCADE_ROLL, 6, false, { 6, 6, 6, 6 }
      end, by == "tbl")
      eq({ b.session.host, b.session.state.cv, atB[#atB].h, atB[#atB].verdict, atB[#atB].why, ns.Dice.alarm(b.session) }, { A, 6, 6, "bad", "forged", true })
    end
    local atB, st, sa = gul(4); st.cv, st.left = 6, { 6, 6, 6, 6 }; sa.seq = sa.seq + 2; sa:snapshotTo(B); sim:run(1)   -- a real Гюлбара cascade; my host says I missed two events
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, b.session.diceUnheard }, { 1, 6, "bad", "dodge", nil })
    atB, st, sa = gul(4); st.cv, st.left = 6, { 6, 6, 6, 6 }; sa.seq = sa.seq + 2; b.session:requestSync(); sim:run(1)   -- the same in a snapshot I asked for
    eq({ #atB, b.session.diceUnheard, ns.Dice.alarm(b.session), b.session.state.cv }, { 0, 1, false, 6 })
    atB = gul(4); takeBack(function(st) st.cv, st.left = 6, { 6, 6, 6, 6 } end)              -- by a host that takes the table back, pushed
    eq({ b.session.host, #atB, atB[1].h, atB[1].verdict, atB[1].why }, { A, 1, 6, "bad", "dodge" })
    atB = gul(4); takeBack(function(st) st.cv, st.left = 6, { 6, 6, 6, 6 } end, true)        -- and when I ask it
    eq({ b.session.host, #atB, b.session.diceUnheard, b.session.state.cv }, { A, 0, 1, 6 })
    atB, st, sa = gul(4); for _, cl in ipairs{ a, b, w } do local t = cl.session.state; t.cv, t.left = 5, { 5, 5, 5, 5 } end   -- as many moves as mine, but other steps
    st.cv, st.xfer, st.turn, st.left = 4, true, 2, { 4, 4 }; sa.seq = sa.seq + 2; sa:snapshotTo(B); sim:run(1)
    eq({ (E.thrown(st)), (E.thrown(b.session.state)), #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 1, 1, 6, "bad", "dodge" })
    atB = gul(4); takeBack(function(st, sa) sa.diceProof.c[3] = "x" end)                        -- the throw I hold, told otherwise by a retaking host
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 6, "bad", "forged" })
    atB, st, sa = gul(2)                                                                       -- a plain double: the roll counts are mine, not the snapshot's
    st.rolls[1], st.cv = E.CASCADE_ROLL, 4; sa.seq = sa.seq + 2; sa:snapshotTo(B); sim:run(1)
    eq({ E.thrown(st), #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 0, 1, 6, "bad", "forged" })
    atB = gul(2)
    takeBack(function(st) st.rolls[2] = E.CASCADE_ROLL - 1 end)                                -- nor a retaking host's, for the throws to come
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 6, "bad", "forged" })
  end)
  it("a proof names the seat it was thrown for and that seat's roll: my throw is not the host's turn, and no turn is played twice (round 4)", function()
    local function mine()                                                                      -- throw 10 is B's own: 4:3, B to move
      local sim, tid = table2(); seat(); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)
      local p = b.session.diceProof; eq({ p.h, p.r, p.t, b.session.state.turn, b.session.state.dice }, { 10, 2, 1, 2, { 4, 3 } })
      eq(a.session.diceProof, p); return fairs(b), a.session.state, a.session
    end
    local atB, st, sa = mine(); st.turn = 1; sa.seq = sa.seq + 2; sa:snapshotTo(B); sim:run(1)   -- my host gives my dice to its own seat
    eq({ b.session.state.turn, #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 1, 10, "bad", "forged" })
    atB, st, sa = mine(); st.turn, sa.diceProof.r = 1, 1; sa.seq = sa.seq + 2; b.session:requestSync(); sim:run(1)   -- and says the throw was its own
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, b.session.diceUnheard }, { 1, 10, "bad", "forged", nil })
    atB, st, sa = mine(); st.rolls[2], sa.diceProof.t = 3, 3; sa.seq = sa.seq + 2; sa:snapshotTo(B); sim:run(1)   -- or another roll of mine
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 10, "bad", "forged" })
    for _, r in ipairs{ 2, 1 } do                                                              -- the same from a host that takes the table back (the reviewer's probe)
      atB = mine(); takeBack(function(st, sa) st.turn, sa.diceProof.r = 1, r end)
      eq({ b.session.host, b.session.state.turn, atB[#atB].h, atB[#atB].verdict, atB[#atB].why }, { A, 1, 10, "bad", "forged" })
    end
    local sim, tid = table2(); seat(); ok(a:act{ k = "move", steps = FIRST }); sim:run(1); atB = fairs(b)   -- a two-seed proof of its own making for my turn:
    local x = grind(tid, 13, { 6, 6 }, SEED); sa, st = a.session, a.session.state; st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }   -- my seed of throw 10, told to be of 13
    sa.diceProof = { h = 13, c = { ns.Fair.commit(x), COMMIT }, s = { x, SEED }, r = 2, t = 1 }; sa.seq = 14; sa:snapshotTo(B); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 13, "bad", "forged" })
  end)
  it("a throw of mine that closed in events I lost gets its seat and roll from my own state; a throw I did not see is counted beside an old number too (round 4)", function()
    local sim, tid = table2(); seat(); local lift = mute(B, "seed"); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)
    local atB, sa = fairs(b), a.session; eq({ b.session.throw.h, b.session.throw.r, b.session.throw.sent }, { 10, 2, true }); sim:offline(B)
    sa:play(0, { k = "throw", op = "seeds", h = 10, s = { SEED, SEED } }); sim:run(1)           -- my seed got through; the seeds event did not
    sa.state.rolls[2], sa.diceProof.t = 3, 3; lift(); sim:online(B); b.session:requestSync(); sim:run(1)   -- and it was "my third roll"
    eq({ b.session.state.rolls[2], atB[#atB].h, atB[#atB].verdict, atB[#atB].why, b.session.diceProof.t }, { 3, 10, "bad", "forged", 1 })
    sim, tid = table2(); seat(); lift = mute(B, "seed"); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)   -- the same lost close, told as it was
    atB, sa = fairs(b), a.session; sim:offline(B); sa:play(0, { k = "throw", op = "seeds", h = 10, s = { SEED, SEED } }); sim:run(1)
    lift(); sim:online(B); b.session:requestSync(); sim:run(1)
    eq({ #atB, atB[1].h, atB[1].verdict, b.session.diceUnheard, ns.Dice.alarm(b.session) }, { 1, 10, "ok", nil, false }); eq(b.session.state, a.session.state)
    sim, tid = table2(); seat(); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)             -- I log in again: the roll in the board is the proof's
    sa = a.session; sa.state.rolls[2] = 3; local b2 = sim:crash(B); atB = fairs(b2); sim:run(1)
    eq({ b2.session.state.rolls[2], #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 3, 1, 10, "bad", "forged" })
    sim, tid = table2(); seat(); atB, sa = fairs(b), a.session; local st = sa.state           -- "A threw alone and moved": B to roll, with a running throw of an old number
    local x = grind(tid, 9, { 6, 6 }); st.dice, st.left, st.phase, st.turn, st.rolls[1] = { 6, 6 }, nil, "roll", 2, 2
    sa.diceProof = { h = 9, c = { ns.Fair.commit(x) }, s = { x }, r = 1, t = 2 }; sa.throw = { h = 6, d = 1, commits = { COMMIT } }
    sa.seq = 11; sa:snapshotTo(B); sim:run(1)
    eq({ b.session.state.dice, #atB, atB[1].h, atB[1].verdict, atB[1].why }, { { 6, 6 }, 1, 9, "bad", "dodge" })
  end)
  it("a turn is not played twice with the dice of the throw I hold (round 4)", function()
    local sim, tid = table2(); seat(); local lift = mute(B, "commit"); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)
    local atW, sa = fairs(w), a.session; local st = sa.state                                    -- A has moved its 4:4 (throw 6); throw 10 runs
    eq({ w.session.diceProof.h, w.session.state.phase, w.session.state.left, st.dice }, { 6, "roll", nil, { 4, 4 } })
    st.phase, st.turn, st.left = "move", 1, { 4, 4, 4, 4 }; sa.seq = sa.seq + 2; sa:snapshotTo(W); sim:run(1)   -- the 4:4 open again for A
    eq({ w.session.state.left, #atW, atW[1].h, atW[1].verdict, atW[1].why }, { { 4, 4, 4, 4 }, 1, 6, "bad", "forged" })
  end)
  it("my dice records outlive a table the host ends under me: a red line stays red, and what comes back is held against what I knew (round 4)", function()
    local function endIt(tid) a:send("GUILD", nil, ns.Session.message("END", { tid = tid, e = a.session.epoch })); sim:run(2) end
    local sim, tid = table2(); seat(); local atB, sa = fairs(b), a.session; local st = sa.state
    mute(B, "protest"); st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }; sa:snapshotTo(B); sim:run(1)   -- red already (no event follows the snapshot)
    eq({ #atB, ns.Dice.alarm(b.session), b.session.diceSeen.bad }, { 1, true, 1 }); local old = b.session
    local h = sa.seq + 1; local x = grind(tid, h, { 6, 6 }, ZERO); sa.seq = h + 1              -- the table ends and comes back with two seeds of the host's
    sa.diceProof = { h = h, c = { ns.Fair.commit(x), ns.Fair.commit(ZERO) }, s = { x, ZERO }, r = 1, t = 1 }; endIt(tid)
    local s = b.session; ok(s ~= nil and s ~= old); eq({ s.mySeat, s.state.dice, ns.Dice.alarm(s), s.diceSeen.bad >= 1 }, { 2, { 6, 6 }, true, true })
    eq({ atB[#atB].h, atB[#atB].verdict, atB[#atB].why, ns.Dice.status(s) }, { h, "bad", "forged", "dice.bad", "red" })
    sim, tid = table2(); seat(); atB, sa = fairs(b), a.session; st = sa.state                  -- a green line: the table comes back with a throw made alone
    h = sa.seq + 1; x = grind(tid, h, { 6, 6 }); st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }; sa.seq = h + 1
    sa.diceProof = { h = h, c = { ns.Fair.commit(x) }, s = { x }, r = 1, t = 1 }; endIt(tid)
    eq({ b.session.state.dice, #atB, atB[1].h, atB[1].verdict, atB[1].why, ns.Dice.alarm(b.session) }, { { 6, 6 }, 1, h, "bad", "dodge", true })
    sim, tid = table2(); seat(); atB, sa = fairs(b), a.session; st = sa.state                  -- or with other dice under the throw I saw
    st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }; endIt(tid)
    eq({ b.session.state.dice, #atB, atB[1].h, atB[1].verdict, atB[1].why }, { { 6, 6 }, 1, 6, "bad", "forged" })
    sim, tid = table2(); seat(); atB = fairs(b); endIt(tid)                                    -- the table as it was: nothing to say
    eq({ b.session ~= nil, #atB, b.session.diceUnheard, ns.Dice.status(b.session) }, { true, 0, nil, "dice.ok", "good" }); eq(b.session.state, a.session.state)
    eq(b.session.diceSeen, { ok = 2, alone = 0, bad = 0 }); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)   -- and the game goes on
    eq({ atB[1].h, atB[1].verdict, b.session.diceSeen.ok }, { 10, "ok", 3 }); eq(b.session.state, a.session.state)
  end)
  it("an abort or a start over a throw I gave my seed to is a second try; a host that stands up is not; a bad throw stays counted (round 4)", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local atB = fairs(b)
    a.session:play(0, { k = "abort" }); sim:run(1); eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why, ns.Dice.alarm(b.session) }, { 1, 3, "bad", "dodge", true })
    sim, tid = table2(); mute(B, "seed"); seat(); atB = fairs(b)
    a.session:play(0, { k = "start" }); sim:run(1); eq({ atB[1].h, atB[1].verdict, atB[1].why, ns.Dice.alarm(b.session), b.session.diceBad }, { 3, "bad", "dodge", true, "dodge" })
    sim, tid = table2(); mute(B, "seed"); seat(); atB = fairs(b); a:stand(); sim:run(3)          -- the host leaves mid-throw: the table is mine
    eq({ b.session.role, ns.Dice.alarm(b.session) }, { "host", false }); for _, e in ipairs(atB) do ok(e.verdict ~= "bad") end
    sim, tid = table2(); seat(); atB = fairs(b); local s = b.session
    ns.Dice.int.close(s, 6, "bad", "forged"); eq({ s.diceSeen.ok, s.diceSeen.bad }, { 1, 1 })     -- throw 6 found bad afterwards: counted once
    ns.Dice.int.close(s, 6, "ok", nil, { d = 1 }); eq({ s.diceSeen.ok, s.diceSeen.bad, ns.Dice.alarm(s) }, { 2, 1, true })   -- its number used again
  end)
  it("a table that ends under me cannot come back under another id with dice of the host's making (round 5)", function()
    local function other(tid, send)                                                            -- the reviewer's probes rr8 and rr9
      local sa, nt = a.session, A .. "#1700000099"; local st = sa.state
      send(sa); sa.tid = nt; sa.seq = sa.seq + 3
      local x = grind(nt, sa.seq - 1, { 6, 6 }); st.dice, st.left, st.phase, st.turn = { 6, 6 }, { 6, 6, 6, 6 }, "move", 1
      sa.diceProof = { h = sa.seq - 1, c = { ns.Fair.commit(x) }, s = { x }, r = 1, t = st.rolls[1] }
      sa:snapshotTo(B); sim:run(2); return nt
    end
    local sim, tid = table2(); seat(); local atB = fairs(b)
    local nt = other(tid, function(sa) a:send("GUILD", nil, ns.Session.message("END", { tid = tid, e = sa.epoch })) end)
    eq({ b.session, b.dice[nt] }, {}); eq(#atB, 0); ok(sim:count(function(m) return m.from == B and m.msg.t == "STD" and m.msg.tid == nt end) >= 1)
    sim, tid = table2(); seat(); atB = fairs(b)
    nt = other(tid, function() a:send("WHISPER", B, ns.Session.message("SNO", { tid = tid, why = "gone" })); sim:run(1); eq(b.session, nil) end)
    eq({ b.session, b.dice[nt] }, {}); eq(#atB, 0); ok(sim:count(function(m) return m.from == B and m.msg.t == "STD" and m.msg.tid == nt end) >= 1)
  end)
  it("a start in the middle of a match wipes no count of mine; a real new match does (round 4)", function()
    local sim, tid = table2(); seat(); local atB, sa = fairs(b), a.session; local st = sa.state
    st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }; sa:snapshotTo(B); sim:run(1); eq(ns.Dice.alarm(b.session), true)
    sa:play(0, { k = "start" }); sim:run(1)                                                    -- the match "starts" again under me
    eq({ b.session.seq, a.session.seq, ns.Dice.alarm(b.session), b.session.diceSeen.bad >= 1, b.session.diceBad }, { a.session.seq, b.session.seq, true, true, "forged" })
    sim, tid = table2(); seat(); atB, sa = fairs(b), a.session; st = sa.state
    st.dice, st.left = { 6, 6 }, { 6, 6, 6, 6 }; sa:snapshotTo(B); sim:run(1); eq(ns.Dice.alarm(b.session), true)
    for _, cl in ipairs{ a, b, w } do E.leave(cl.session.state, 1) end; eq(E.over(b.session.state), true)   -- the match is over on every client
    sa:play(0, { k = "start" }); sim:run(1); eq({ ns.Dice.alarm(b.session), b.session.diceSeen.bad, b.session.diceBad }, { false, 0, nil })
  end)
  it("I stand up and sit down again at the same table: nobody is blamed for the throws I chose not to see (round 4)", function()
    local sim, tid = table2(); seat(); local atB = fairs(b); b:stand(); sim:run(1); eq(b.session, nil)
    b:sit(tid, 2); sim:run(2); local s = b.session
    eq({ s.mySeat, #atB > 0, ns.Dice.alarm(s), s.diceUnheard, s.diceLast.verdict }, { 2, true, false, nil, "ok" }); eq(s.state, a.session.state)
    for _, e in ipairs(atB) do eq(e.verdict, "ok") end
    sim, tid = table2(); seat(); atB = fairs(b); b:stand(); sim:run(1); w:sit(tid, 2); sim:run(12)   -- somebody else plays in my chair meanwhile
    ok(a.session.diceProof.h > 6); w:stand(); sim:run(1); b:sit(tid, 2); sim:run(2); s = b.session
    eq({ s.mySeat, ns.Dice.alarm(s), s.diceUnheard }, { 2, false, nil }); eq(s.state, a.session.state)
    for _, e in ipairs(atB) do ok(e.verdict ~= "bad", tostring(e.why)) end
    sim, tid = table2(); seat(); ok(a:act{ k = "move", steps = FIRST }); sim:run(1); atB = fairs(b)   -- records of another host: its numbers judge nothing
    b.dice[tid].diceHost = W; local sa = a.session; local st = sa.state; st.dice, st.left, st.turn = { 4, 4 }, { 4, 4, 4, 4 }, 1
    sa.diceProof = { h = 6, c = { COMMIT, COMMIT }, s = { SEED, SEED }, r = 1, t = 1 }; sa.seq = sa.seq + 2
    a:send("GUILD", nil, ns.Session.message("END", { tid = tid, e = sa.epoch })); sim:run(2)
    eq({ b.session.diceProof.h, #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 6, 1, 6, "bad", "dodge" })
  end)
  it("nobody moves: the host's clock plays the first legal move for either seat", function()
    local sim, tid = table2(30); seat()
    eq({ a.session.state.turn, a.session:left(), E.auto(a.session.state, 1).steps }, { 1, 30, { { 24, 20 }, { 24, 20 }, { 20, 16 }, { 20, 16 } } })
    sim:run(29); eq(a.session.seq, 8); sim:run(1)
    eq({ a.session.state.turn, a.session.state.phase, a.session.state.dice, a.session.seq, a.session:left() }, { 2, "move", { 4, 3 }, 12, 30 })
    sim:run(30); eq({ a.session.state.turn, a.session.seq }, { 1, 16 }); eq(b.session.state, a.session.state)
    eq(sim:count(function(m) return m.target == B and m.msg.t == "EV" and m.msg.auto == true end), 2)
    eq(sim:count(function(m) return m.msg.t == "ACT" and m.msg.a.k == "move" end), 0)
  end)
  it("a player offline for three minutes is stood up and loses; meanwhile the host throws alone", function()
    local sim, tid = table2(30); seat(); local res = results(a); sim:offline(B); local t0 = sim.clock
    for _ = 1, 200 do if #res > 0 then break end; sim:run(1) end
    eq(#res, 1); ok(sim.clock - t0 >= 180 and sim.clock - t0 <= 185); eq({ res[1].game, res[1].winners, res[1].losers, res[1].left, res[1].names }, { "tabla", { 1 }, { 2 }, 2, { A, B } })
    eq(a.session.status, "aborted"); ok(a.session.diceSeen.alone >= 3); eq(a.session.diceSeen.bad, 0)
  end)
  it("a player who stands up loses the match and the result names it", function()
    local sim, tid = table2(); seat(); local res = results(w); b:stand(); sim:run(2)
    eq({ #res, res[1].winners, res[1].losers, res[1].left }, { 1, { 1 }, { 2 }, 2 }); eq({ w.session.state.phase, w.session.state.winner }, { "match", 1 })
  end)
  it("the cascade's remainder passes to the opponent with a full clock; idle, the host's clock plays it and then the opponent throws", function()
    local sim = rigged(pos("gul", 1, { [24] = 1, [12] = 1 }, { [7] = 1, [20] = 14 }, { rolls = { 3, 0 } }))
    dice(5, 5); eq({ b.session.state.left, b.session.state.cv }, { { 5, 5, 5, 5 }, 5 })
    ok(a:act{ k = "move", steps = { { 12, 7 }, { 7, 2 } } }); sim:run(1); local st = b.session.state
    eq({ st.turn, st.phase, st.left, st.cv, st.xfer, b.session:left() }, { 2, "move", { 5, 5 }, 5, true, 45 })
    eq({ b:act{ k = "move", steps = { { 20, 15 } } } }, { nil, "move" })                 -- half of the remainder is not a move
    sim:run(43); eq(a.session.state.left, { 5, 5 }); sim:run(1); st = a.session.state
    eq({ st.turn, st.phase, st.left, st.cv, st.pts[2][15], st.pts[2][20] }, { 2, "move", { 6, 6, 6, 6 }, 6, 2, 12 })
    sim:run(45); st = a.session.state; eq({ st.turn, st.phase, st.left, st.cv, st.xfer, st.rolls }, { 2, "roll", nil, nil, nil, { 4, 0 } })
    eq(b.session.state, st); eq(w.session.state, st); ns.Ext.dice = REAL
  end)
  it("a mother pin ends the game at the table for 2 points and Гюлбара follows", function()
    local sim = rigged(pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 })); local res = results(a)
    dice(3, 5); ok(a:act{ k = "move", steps = { { 4, 1 } } }); sim:run(1); local st = b.session.state
    eq({ st.phase, st.gw, st.gp, st.score, st.pin[2][24], st.turn, #res }, { "game", 1, 2, { 2, 0 }, 1, nil, 0 })
    sim:run(3); st = w.session.state; eq({ st.phase, st.var, st.game, st.turn, st.score }, { "roll", "gul", 3, 1, { 2, 0 } }); ns.Ext.dice = REAL
  end)
end)
