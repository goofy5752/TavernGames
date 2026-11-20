local Sim = require("sim")
local ns = Sim.ns

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"
local CLS = { [A] = "MAGE", [B] = "PRIEST", [C] = "ROGUE" }

-- The first n of a, b, c (opts[name] merged into their sim:add options); a hosts
-- deathroll from 100, everyone seated, the game started: seat 1 on turn.
local function setup(n, opts)
  opts = opts or {}
  local sim = Sim.new()
  local names, clients = { A, B, C }, {}
  for i = 1, n do
    local o = { cls = CLS[names[i]] }
    for k, v in pairs(opts[names[i]] or {}) do o[k] = v end
    clients[i] = sim:add(names[i], o)
  end
  sim:run(1)
  local a = clients[1]
  local tid = a:openTable{game="deathroll", access="guild", turn=45, opt={start=100}}; sim:run(3)
  for i = 2, n do clients[i]:sit(tid, i) end
  sim:run(1)
  ok(a:startGame()); sim:run(1)
  return sim, clients[1], clients[2], clients[3]
end

describe("rolls", function()
  it("finds the seat from a first name, a full name, and refuses two candidates", function()
    local R, N = ns.Rolls, ns.Names
    eq(N.first("Иван Петров"), "Иван"); eq(N.first("Kiro"), "Kiro")
    eq(N.matches("Иван Петров", "Иван"), true); eq(N.matches("Иван Петров", "Иван Петров"), true)
    eq(N.matches("Иван Петров", "Петров"), false); eq(N.matches("Иван Петров", "Иван Иванов"), false)
    eq(R.seatFor({A, B}, "Иван"), 1); eq(R.seatFor({A, false, C}, "Kiro Barley"), 3); eq(R.seatFor({A, B}, "Гошо"), nil)
    eq(R.seatFor({A, "Иван Димов"}, "Иван"), nil); eq(R.seatFor({A, "Иван Димов"}, "Иван Димов"), 2)
  end)

  it("the host sees a roll and everybody records it as seen and checked", function()
    local sim, a, b = setup(2)
    sim.nextRolls = {57}; ok(a:roll()); sim:run(1)
    eq(b.session.state.rolls, {{seat=1, n=57, max=100, src="seen"}}); eq(b.session.state.max, 57); eq(b.session.state.turn, 2)
    eq(ns.Rolls.check(a.session, 1), "ok"); eq(ns.Rolls.check(b.session, 1), "ok"); eq(sim.rolled, {{from=A, lo=1, hi=100, n=57}})
  end)

  it("a guest's roll seen by the host needs no claim wait", function()
    local sim, a, b = setup(2)
    sim.nextRolls = {57, 12}; a:roll(); sim:run(1); ok(b:roll()); sim:run(1)
    eq(a.session.state.rolls[2], {seat=2, n=12, max=57, src="seen"})
  end)

  it("a roll the host cannot see is taken as a claim after 3 s and marked", function()
    local sim, a, b = setup(2)
    sim.canSee = function(from, to) return from == to end
    sim.nextRolls = {57, 12}; a:roll(); sim:run(1); ok(b:roll()); sim:run(2); eq(#a.session.state.rolls, 1)
    sim:run(2); eq(a.session.state.rolls[2], {seat=2, n=12, max=57, src="claim"}); sim:run(6)
    eq(ns.Rolls.check(a.session, 2), "unseen"); eq(ns.Rolls.check(b.session, 2), "ok")
  end)

  it("chatter never becomes an event", function()
    local sim, a = setup(2)
    local q = a.session.seq
    a:rollSeen("Мария", 5, 1, 100)    -- not on turn
    a:rollSeen("Иван", 5, 1, 50)      -- wrong range
    a:rollSeen("Иван", 5, 2, 100)     -- lo ~= 1
    a:rollSeen("Гошо", 5, 1, 100)     -- not seated
    a:rollSeen("Иван", 5.5, 1, 100); sim:run(1); eq(a.session.seq, q); eq(#a.session.state.rolls, 0)
  end)

  it("a double click rolls once", function()
    local sim, a = setup(2)
    ok(a:roll()); eq({a:roll()}, {nil, "wait"}); sim:run(1); eq(#sim.rolled, 1); eq({a:roll()}, {nil, "turn"})
  end)

  it("a member cannot forge a seen roll", function()
    local sim, a = setup(2)
    sim.nextRolls = {57}; a:roll(); sim:run(1)
    a:receive("WHISPER", B, {v=1, t="ACT", tid=a.session.tid, a={k="roll", n=30, max=57, src="seen"}}); sim:run(1)
    eq(#a.session.state.rolls, 1); sim:run(3); eq(a.session.state.rolls[2], {seat=2, n=30, max=57, src="claim"})
    a:receive("WHISPER", B, {v=1, t="ACT", tid=a.session.tid, a={k="roll", n=1, max=57}}); sim:run(4); eq(#a.session.state.rolls, 2)   -- stale range, not on turn
  end)

  it("a client without /roll asks the table", function()
    local sim, a, b = setup(2, {[B] = {roll=false}})
    sim.nextRolls = {57}; ok(a:roll()); sim:run(1); sim.nextRandom = {42}
    ok(b:roll()); sim:run(1); eq(a.session.state.rolls[2], {seat=2, n=42, max=57, src="ask"})
    eq(ns.Rolls.check(a.session, 2), nil); eq(#sim.rolled, 1)
  end)

  it("timeout: the table rolls, tagged, nobody loses by the clock", function()
    local sim, a, b = setup(2)
    sim.nextRandom = {33}; sim:run(46); eq(b.session.state.rolls[1], {seat=1, n=33, max=100, src="timeout"})
    eq(b.session.state.phase, "play"); eq(b.session.state.turn, 2)
  end)

  it("a roll that never shows up is reported stuck, then the timeout covers it", function()
    local sim, a = setup(2)
    sim.canSee = function() return false end
    ok(a:roll()); sim:run(4); eq(a.session.rollStuck, true); eq(a.session.rolling, nil)
    sim.nextRandom = {9}; sim:run(45); eq(a.session.state.rolls[1].src, "timeout"); eq(a.session.rollStuck, false)
  end)

  it("a recorded number that differs from what I saw is a mismatch", function()
    local sim, a, b = setup(2)
    b:rollSeen("Иван", 57, 1, 100); a.session:play(1, {k="roll", n=5, max=100, src="seen"}); sim:run(6)
    eq(ns.Rolls.check(b.session, 1), "mismatch")
  end)

  it("host leaves mid-turn: the next host takes the roll", function()
    local sim, a, b, c = setup(3)
    a:stand(); sim:run(2); eq(b.session.role, "host"); eq(b.session.state.players, {2,3}); eq(b.session.state.turn, 2)
    sim.nextRolls = {40}; ok(b:roll()); sim:run(1); eq(c.session.state.rolls, {{seat=2, n=40, max=100, src="seen"}})
  end)

  it("a sighting from an earlier game does not confirm a claim in the next", function()
    local sim, a, b = setup(2)
    sim.nextRolls = {100, 57, 1}; ok(a:roll()); sim:run(1)
    ok(b:roll()); sim:run(1); ok(a:roll()); sim:run(1); eq(a.session.state.loser, 1)
    ok(a:startGame()); sim:run(1); sim.nextRolls = {100}; ok(a:roll()); sim:run(1)
    -- game 2, seat 2 on turn at 100: the same seat, max and n as its seen roll of game 1
    a:receive("WHISPER", B, {v=1, t="ACT", tid=a.session.tid, a={k="roll", n=57, max=100}}); sim:run(3)
    eq(a.session.state.rolls[2], {seat=2, n=57, max=100, src="claim"}); sim:run(6)
    eq(ns.Rolls.check(a.session, 2), "unseen")
  end)

  it("a resync into a newer game shows no verdict of the previous one", function()
    local sim, a, b = setup(2)
    b:rollSeen("Иван", 57, 1, 100); a.session:play(1, {k="roll", n=5, max=100, src="seen"}); sim:run(6)
    eq(ns.Rolls.check(b.session, 1), "mismatch")
    a.session:play(2, {k="roll", n=1, max=5, src="seen"}); sim:run(1)
    sim:offline(B); ok(a:startGame()); sim:run(1)                    -- b misses the start
    a.session:play(2, {k="roll", n=50, max=100, src="ask"}); sim:run(1)
    sim:online(B); a.session:play(1, {k="roll", n=20, max=50, src="ask"}); sim:run(2)
    eq(b.session.state.rolls[1], {seat=2, n=50, max=100, src="ask"}); eq(ns.Rolls.check(b.session, 1), nil)
  end)

  it("host leaves while my roll is in flight: as the next host I roll again at once", function()
    local sim, a, b, c = setup(3)
    sim.nextRolls = {57, 30, 20}; a:roll(); sim:run(1)
    sim.canSee = function(from, to) return from == to end
    ok(b:roll()); sim:run(1)                      -- the claim is held by a
    a:stand(); sim:run(1); eq(b.session.role, "host")
    ok(b:roll()); sim:run(1); eq(c.session.state.rolls[2], {seat=2, n=20, max=57, src="seen"})
  end)

  it("host leaves while my roll is in flight: with the next host I roll again at once", function()
    local sim, a, b, c = setup(3)
    sim.nextRolls = {57, 40, 30, 20}; a:roll(); sim:run(1); b:roll(); sim:run(1)
    sim.canSee = function(from, to) return from == to end
    ok(c:roll()); sim:run(1)                      -- the claim is held by a
    a:stand(); sim:run(1); eq(c.session.host, B)
    ok(c:roll()); sim:run(4); eq(b.session.state.rolls[3], {seat=3, n=20, max=40, src="claim"})
  end)

  it("rollSeen is announced as an event even with no table", function()
    local sim = Sim.new()
    local d = sim:add(D, { cls = "DRUID" }); sim:run(1)
    local got = {}
    d:on("rollSeen", function(...) got[#got + 1] = {...} end)
    d:rollSeen("Иван", 5, 1, 100)
    eq(got, {{"Иван", 5, 1, 100}})
  end)
end)
