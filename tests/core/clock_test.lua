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
    clock.t = 298
    eq(Clock.flagHonest(s, 2, c), false)
    clock.t = 299
    eq(Clock.flagHonest(s, 2, c), true) -- FLAG_TOL left
    eq(Clock.flagHonest(s, 1, c), false)
    eq(Clock.flagHonest(s, 2, { at = 0, seen = false, seat = 2, left = 3000 }), false)
    s.sent = { { a = { k = "move", f = 13, t = 29 }, at = 295 } } -- the last seconds: my own lag
    eq(Clock.flagHonest(s, 2, c), true)
    s.sent[1].at = 285 -- in time, and the host has not shown it: dropped
    eq(Clock.flagHonest(s, 2, c), false)
  end)
end)
