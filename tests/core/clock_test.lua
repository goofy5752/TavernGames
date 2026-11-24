-- core/Clock.lua on a hand-made session with a fake env.now.
local Sim = require("sim")
local ns = Sim.ns
local E = ns.Engines.chess

-- A live chess session of `minutes` (0: no limit), white = seat 2 on turn, at now = t.
local function session(minutes, t)
  local clock = { t = t or 0 }
  local env = { now = function() return clock.t end }
  local s = setmetatable({ client = { env = env }, game = "chess", status = "live",
    state = E.new({ first = 2, opt = { clock = minutes } }) }, ns.Session)
  return s, clock
end

describe("the clock", function()
  it("left counts down only for the seat on turn", function()
    local Clock = ns.Clock
    local s, clock = session(5)
    eq(s.state.clock, { 3000, 3000 })
    s.clockAt, clock.t = 100, 112.5
    eq(Clock.left(s, 2), 2875)
    eq(Clock.left(s, 1), 3000)
    clock.t = 500
    eq(Clock.left(s, 2), 0)
    local free = session(0)
    free.clockAt = 0
    eq(Clock.left(free, 2), nil)
    eq(Clock.left(setmetatable({ client = s.client, game = "chess", status = "live" }, ns.Session), 2), nil)
  end)

  it("stamp rounds to tenths", function()
    local Clock = ns.Clock
    local s, clock = session(5)
    s.clockAt, s.clockKey, clock.t = 10, 0, 13.26
    eq(Clock.stamp(s, 2, { k = "move", f = 13, t = 29 }), 33)
    eq(Clock.stamp(s, 2, { k = "resign" }), nil)
    local free, c2 = session(0)
    free.clockAt, c2.t = 10, 13.26
    eq(Clock.stamp(free, 2, { k = "move", f = 13, t = 29 }), nil)
    s.status = "aborted"
    eq(Clock.stamp(s, 2, { k = "move", f = 13, t = 29 }), nil)
  end)

  it("the tolerance grows with the moves", function()
    local Clock = ns.Clock
    eq(Clock.tolerance(1), Clock.TOL_BASE + Clock.TOL_PER)
    eq(Clock.tolerance(1), 105)
    -- One move of the other seat: my clock saw it take (tolerance(1) -/+ 1) tenths more than its dt.
    local function oneMove(over)
      local s, clock = session(5)
      local forged = false
      s.hook = function(_, name) if name == "forged" then forged = true end end
      s.stake, s.mySeat = 50000, 1
      Clock.mark(s)
      clock.t = (Clock.tolerance(1) + over) / 10
      Clock.before(s, { seat = 2, a = { k = "move", f = 13, t = 29 }, dt = 0 })
      eq(s.clockOpp.n, 1)
      return forged
    end
    eq(oneMove(-1), false)
    eq(oneMove(1), true)
  end)

  it("mark starts a turn once, clears when not timed, and a snapshot's turn is unseen", function()
    local Clock = ns.Clock
    local s, clock = session(5, 7)
    Clock.mark(s)
    eq({ s.clockAt, s.clockKey, s.clockSeen }, { 7, 0, true })
    clock.t = 9
    Clock.mark(s) -- the same turn (an offer, a claim): the measurement goes on
    eq(s.clockAt, 7)
    Clock.mark(s, true)
    eq({ s.clockAt, s.clockSeen }, { 9, false })
    s.state.phase = "over"
    Clock.mark(s)
    eq({ s.clockAt, s.clockKey, s.clockSeen }, { nil, nil, nil })
  end)

  it("my own move is credited with my round trip, and only one sent on this turn counts", function()
    local Clock = ns.Clock
    local mv = { k = "move", f = 13, t = 29 }
    -- I am white (seat 2) on turn since 100 s; my ACT went at 103 s, its EV is back at 104 s.
    local function mine(sent, dt)
      local s, clock = session(30)
      local forged = false
      s.hook = function(_, name) if name == "forged" then forged = true end end
      s.stake, s.mySeat, s.sent = 50000, 2, sent
      clock.t = 100; Clock.mark(s)
      clock.t = 104
      Clock.before(s, { seat = 2, a = mv, dt = dt })
      return s, forged
    end
    local s = mine({ { a = mv, at = 50 }, { a = mv, at = 103 } }, 40) -- the one at 50 s was an earlier turn's
    eq(s.clockOwn.n, 1)
    ok(math.abs(s.clockOwn.sum) < 1e-9, "thought 3 s, a round trip of 1 s: " .. s.clockOwn.sum)
    local earlier = mine({ { a = mv, at = 50 } }, 40)
    eq(earlier.clockOwn, nil) -- nothing of this turn to measure against
    local s2, forged = mine({ { a = mv, at = 103 } }, 30 + 10 + Clock.tolerance(1) + 1)
    eq(forged, true)
    eq(s2.clockOwn.n, 1)
    -- The credit is at most RTT_MAX: a move that came back 5 s after it went.
    local t = session(30)
    t.client.env.now = function() return 108 end
    eq(Clock.countOwn(t, 80, 103, 100), false)
    eq(t.clockOwn.sum, 80 - 30 - Clock.RTT_MAX)
    eq(Clock.countOwn(t, 70, 103, 100, 103.2), false) -- arrivedAt given: a round trip of 2 tenths
    ok(math.abs(t.clockOwn.sum - (40 + 70 - 30 - 2)) < 1e-9)
    eq(t.clockOwn.n, 2)
  end)

  it("a flag on a turn a snapshot brought is unseen when my clock cannot confirm it", function()
    local Clock = ns.Clock
    -- I (seat 2) am on turn, measured from a snapshot at 50 s (clockSeen false); 3000 tenths left.
    local function due(t, seen)
      local s, clock = session(5)
      s.stake, s.mySeat = 50000, 2
      clock.t = 50; Clock.mark(s, not seen)
      clock.t = t
      return Clock.flagDue(s, { seat = 2, a = { k = "flag" }, auto = true }), s.stakePend
    end
    eq({ due(350, false) }, { true })            -- gone by my clock even from the snapshot: honest
    eq({ due(200, false) }, { true, "unseen" })  -- not gone: a question, never forged
    eq({ due(200, true) }, { false })            -- a turn I saw begin: forged (Member.onEvent)
    eq({ due(350, true) }, { true })
  end)

  it("a claim still waiting when I become host is dropped", function()
    local Clock = ns.Clock
    local s = session(5)
    s.mySeat, s.client.after = 1, function() return { cancel = function() end } end
    local stopped = false
    s.claimTimer = { cancel = function() stopped = true end }
    Clock.arm(s, E, s.state.turn)
    eq(s.claimTimer, nil); ok(stopped)
    ok(s.turnTimer ~= nil)
  end)

  it("only a move of the claimed seat fails my claim", function()
    local Clock = ns.Clock
    -- I (seat 2, white) moved; seat 1 is on turn and I claimed its flag.
    local function claimed(sk)
      local s = session(5)
      s.client.events = { emit = function() end }
      s.stake, s.mySeat = sk, 2
      ok(E.apply(s.state, 2, { k = "move", f = 13, t = 29 }, 0))
      Clock.mark(s)
      local stopped = false
      s.claimTimer = { cancel = function() stopped = true end }
      return s, function() return stopped end
    end
    local s, stopped = claimed(50000)
    ok(E.apply(s.state, 1, { k = "move", f = 53, t = 37 }, 0))
    Clock.after(s, { seat = 1, a = { k = "move", f = 53, t = 37 }, dt = 0 })
    eq(s.stakeFoul, "forged")
    eq(s.claimTimer, nil); ok(stopped())
    local fun, funStopped = claimed(nil)
    ok(E.apply(fun.state, 1, { k = "move", f = 53, t = 37 }, 0))
    Clock.after(fun, { seat = 1, a = { k = "move", f = 53, t = 37 }, dt = 0 })
    eq(fun.stakeFoul, nil); ok(funStopped())
    local quit, quitStopped = claimed(50000)
    ok(E.apply(quit.state, 1, { k = "resign" }))
    Clock.after(quit, { seat = 1, a = { k = "resign" } })
    eq(quit.stakeFoul, nil); ok(quitStopped())
    local offer, offerStopped = claimed(50000)
    ok(E.apply(offer.state, 1, { k = "offer" }))
    Clock.after(offer, { seat = 1, a = { k = "offer" } })
    eq(offer.stakeFoul, nil); eq(offerStopped(), false) -- still waiting for the flag
  end)

  it("a flag of my seat is honest only by my clock", function()
    local Clock = ns.Clock
    local s, clock = session(5)
    s.mySeat = 2
    local c = { at = 0, seen = true, seat = 2, left = 3000 }
    local unseen = { at = 0, seen = false, seat = 2, left = 3000 } -- measured from a snapshot
    local function verdict(seat, t) return { Clock.flagHonest(s, seat, t) } end
    clock.t = 298
    eq(verdict(2, c), { false, "forged" })
    eq(verdict(2, unseen), { false, "unseen" }) -- never forged on a turn I did not see begin
    clock.t = 299
    eq(verdict(2, c), { true }) -- FLAG_TOL left
    eq(verdict(2, unseen), { true }) -- gone by my clock even from the snapshot on
    eq(verdict(1, c), { false, "forged" })
    eq(verdict(2, nil), { false, "unseen" }) -- my clock measured nothing
    s.sent = { { a = { k = "move", f = 13, t = 29 }, at = 295 } } -- the last seconds: my own lag
    eq(verdict(2, c), { true })
    s.sent[1].at = 285 -- in time, and the host has not shown it: dropped
    eq(verdict(2, c), { false, "forged" })
    eq(verdict(2, unseen), { false, "unseen" })
  end)
end)
