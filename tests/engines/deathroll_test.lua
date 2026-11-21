local Sim = require("sim")
local E = Loader.ns().Engines.deathroll

local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"

local function new(seats, first, start) return E.new{seats=seats, first=first, opt={start=start or 100}} end
local function roll(s, seat, n, src) return E.apply(s, seat, {k="roll", n=n, max=s.max, src=src or "seen"}) end

describe("deathroll", function()
  it("declares its contract", function()
    eq({E.id, E.minSeats, E.maxSeats, E.start, E.needsGroup}, {"deathroll", 2, 5, "host", true}); eq(E.maxSeats, Loader.ns().Const.PARTY_SIZE); eq(E.ext, {"rolls","party"})
    eq(E.options, {{id="start", choices={100,1000,10000,100000}, default=1000}}); eq(E.new{seats={true,true}}.max, 1000)
  end)

  it("two players roll down to 1 and the roller of 1 loses", function()
    local s = new({true,true}, 1); eq(s.players, {1,2}); eq(s.turn, 1); eq(s.max, 100)
    ok(roll(s,1,57)); eq(s.max, 57); eq(s.turn, 2); ok(roll(s,2,12)); ok(roll(s,1,3)); ok(roll(s,2,1))
    eq(s.phase, "over"); eq(s.loser, 2); eq(s.turn, nil); eq(#s.rolls, 4)
    eq(s.rolls[1], {seat=1, n=57, max=100, src="seen"}); eq(E.result(s), {losers={2}, winners={1}}); eq(E.over(s), true)
  end)

  it("rejects in order: action, phase, turn, max, n, src; the state is untouched", function()
    local s = new({true,true}, 1); local before = E.snapshot(s)
    eq({E.apply(s, 1, {k="mark"})}, {nil,"action"}); eq({roll(s,2,5)}, {nil,"turn"})
    eq({E.apply(s, 1, {k="roll", n=5, max=99, src="seen"})}, {nil,"max"})
    for _, n in ipairs{0, 101, 1.5} do eq({roll(s,1,n)}, {nil,"n"}) end
    eq({roll(s,1,5,"magic")}, {nil,"src"}); eq(E.snapshot(s), before)
    ok(roll(s,1,1)); eq({roll(s,2,1)}, {nil,"phase"})
  end)

  it("rolling the cap keeps the cap and passes the turn", function()
    local s = new({true,true}, 1); ok(roll(s,1,100)); eq(s.max, 100); eq(s.turn, 2)
  end)

  it("skips empty seats, honours first, falls back to the lowest seat", function()
    local s = new({true,false,true,true}, 3, 1000); eq(s.players, {1,3,4}); eq(s.turn, 3)
    ok(roll(s,3,500)); eq(s.turn, 4); ok(roll(s,4,400)); eq(s.turn, 1); eq(new({true,false,true}, 2).turn, 1)
  end)

  it("leave: the turn moves on; one player left ends the game without a loser", function()
    local s = new({true,true,true}, 2); E.leave(s, 2); eq(s.players, {1,3}); eq(s.turn, 3); eq(s.phase, "play")
    E.leave(s, 3); eq(s.phase, "over"); eq(s.loser, nil); eq(s.turn, nil); eq(E.result(s), nil); eq(E.over(s), true)
  end)

  it("auto uses the injected random and is tagged timeout", function()
    local s = new({true,true}, 1)
    eq(E.auto(s, 1, function(lo, hi) eq({lo, hi}, {1, 100}); return 42 end), {k="roll", n=42, max=100, src="timeout"})
    eq(E.auto(s, 2, function() return 1 end), nil); eq(E.legal(s, 1), {{k="roll", max=100}}); eq(E.legal(s, 2), {})
  end)

  it("the loser starts the next game while still seated", function()
    local s = new({true,true}, 1); ok(roll(s,1,1)); eq(E.nextFirst(s, {true,true}), 1); eq(E.nextFirst(s, {false,true}), nil)
    eq(E.nextFirst(nil, {true,true}), nil)
  end)

  it("a loser who left is out of the game: no result, and his chair does not roll first", function()
    local s = new({true,true,true}, 1); ok(roll(s,1,1)); eq(E.playing(s, 1), true)
    eq(E.result(s), {losers={1}, winners={2,3}})
    E.leave(s, 1); eq(E.playing(s, 1), false); eq(E.playing(s, 2), true); eq(E.over(s), true)
    eq(E.result(s), nil); eq(E.nextFirst(s, {true,true,true}), nil)
    -- A seat that sat down after the start is not in the game either.
    s = new({true,false,true}, 1); eq(E.playing(s, 2), false); eq(E.playing(s, 3), true)
  end)

  it("snapshot round-trips and is a copy", function()
    local s = new({true,true}, 1); ok(roll(s,1,57)); local t = E.snapshot(s); t.rolls[1].n = 99; t.rolls[2] = {}
    eq(s.rolls[1].n, 57); eq(#s.rolls, 1); eq(E.snapshot(E.restore(E.snapshot(s))), E.snapshot(s))
  end)

  it("a game that ended without a loser can be started again", function()
    local sim = Sim.new()
    local a = sim:add(A, { cls = "MAGE" })
    local b = sim:add(B, { cls = "PRIEST" })
    local c = sim:add(C, { cls = "ROGUE" })
    sim:run(1)
    local tid = a:openTable{game="deathroll", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); sim:run(1); ok(a:startGame()); sim:run(1)
    local results = {}
    a:on("result", function(r) results[#results + 1] = r end)
    c:sit(tid, 3); sim:run(1); b:stand(); sim:run(1)
    eq(a.session.status, "live"); eq(a.session.state.phase, "over"); eq(a.session.state.loser, nil); eq(#results, 0)
    ok(a:startGame()); sim:run(1)
    eq(c.session.state.players, {1,3}); eq(c.session.state.phase, "play")
  end)
end)
