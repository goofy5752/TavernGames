local Sim = require("sim")
local ns = Sim.ns
local E = ns.Engines.tabla

local A, B, W = "Иван Петров", "Мария Стоянова", "Гледач Гледачев"
local SEED = ("ff"):rep(16)
local ZERO, SA = ("00"):rep(16), ("01"):rep(16)
local COMMIT = "352302489bc2fcf025cf00cda8308033f97ac87712ce90b4d7cd72c58e4c3af9"
local FIRST = { { 24, 20 }, { 24, 20 }, { 13, 9 }, { 13, 9 } } -- a legal first move of seat 1 with 4:4
local sim, a, b, w

-- A table of Табла hosted by a, watched by w; B is not seated yet.
local function table2(turn)
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
    eq(ns.Ext.dice.snap(a.session), nil); eq(ns.Dice.status({ engine = function() return ns.Engines.ttt end }), nil)   -- not a dice game
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
    eq(ns.Ext.dice.snap(a.session), { h = 10, d = 1, c = { COMMIT } })
    local b2 = sim:relog(B); sim:run(2)
    eq({ a.session.state.phase, a.session.state.dice, a.session.seq }, { "move", { 4, 3 }, 12 }); eq(a.session.diceLast, { h = 10, verdict = "ok", by = A })
    eq(b2.session.diceLast.verdict, "ok"); eq(b2.session.state, a.session.state)
  end)
  it("a guest that relogs after its commit cannot open it: the host throws alone and nobody is blamed", function()
    local sim, tid = table2(); mute(B, "seed"); seat(); local atA = fairs(a)
    local b2 = sim:relog(B); local atB = fairs(b2); sim:run(3)
    eq({ b2.session.throw.h, b2.session.throw.reload, b2.session.throw.seed, b2.session.throw.foul }, { 3, true, nil, nil })
    sim:run(8); eq({ atA[1].verdict, atA[2].verdict, atB[1].verdict, atB[2].verdict }, { "alone", "ok", "alone", "ok" })
    eq({ b2.session.diceUnheard, ns.Dice.alarm(b2.session), ns.Dice.alarm(a.session) }, { nil, false, false }); eq(b2.session.state, a.session.state)
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
end)
