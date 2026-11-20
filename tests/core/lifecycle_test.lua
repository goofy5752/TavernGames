local Sim = require("sim")
require("pick_engine")

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"

local function clients()
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  local c = sim:add(C, { cls = "ROGUE" })
  local d = sim:add(D, { cls = "DRUID" })
  sim:run(1)
  return sim, a, b, c, d
end

-- a hosts a pick table, b and c sit in seats 2 and 3 (not started yet).
local function seated()
  local sim, a, b, c, d = clients()
  local tid = a:openTable{game="pick", access="guild", turn=45}; sim:run(3)
  b:sit(tid, 2); c:sit(tid, 3); sim:run(1)
  return sim, a, b, c, d, tid
end

-- seated(), then the host starts the game: seat 1 on turn.
local function running()
  local sim, a, b, c, d, tid = seated()
  ok(a:startGame()); sim:run(1)
  return sim, a, b, c, d, tid
end

local function results(client)
  local list = {}
  client:on("result", function(r) list[#list + 1] = r end)
  return list
end

-- moves {{seat, cell}, ...}; seat 1 is a, seat 2 is b; sim:run(1) after each.
local function play(sim, a, b, moves)
  for _, mv in ipairs(moves) do
    local who = mv[1] == 1 and a or b
    ok(who:act{k="mark", c=mv[2]}, "move " .. mv[1] .. ":" .. mv[2])
    sim:run(1)
  end
end

local X_FIRST = { {1,1}, {2,4}, {1,2}, {2,5}, {1,3} }
local O_FIRST = { {2,4}, {1,1}, {2,5}, {1,2}, {2,9}, {1,3} }

describe("game lifecycle", function()
  it("a host-started game waits for the host", function()
    local sim, a, b, c = clients()
    local tid = a:openTable{game="pick", access="guild", turn=45}; sim:run(3); b:sit(tid, 2); c:sit(tid, 3); sim:run(1)
    eq(a.session.status, "open"); eq({b:startGame()}, {nil, "nothost"}); ok(a:startGame()); sim:run(1)
    eq(c.session.status, "live"); eq(c.session.state.players, {1,2,3}); eq(c.session.state.turn, 1); eq(c.session.state.goal, 2)
  end)

  it("startGame refusals", function()
    local sim, a, b = clients()
    eq({a:startGame()}, {nil, "none"})
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    eq({a:startGame()}, {nil, "mode"})
    a:stand(); sim:run(1)
    tid = a:openTable{game="pick", access="guild", turn=45}; sim:run(3)
    eq({a:startGame()}, {nil, "short"})
    b:sit(tid, 2); sim:run(1); ok(a:startGame()); sim:run(1)
    eq({a:startGame()}, {nil, "live"})
  end)

  it("a newcomer waits for the next game; the result is announced once; the winner starts", function()
    local sim, a, b, c, d, tid = running()
    d:sit(tid, 4); sim:run(1)
    local ra, rb, rc, rd = results(a), results(b), results(c), results(d)
    eq(d.session.state.players, {1,2,3})
    ok(a:act{k="inc", by=1}); sim:run(1); ok(b:act{k="inc", by=1}); sim:run(1); ok(c:act{k="inc", by=1}); sim:run(1)
    ok(a:act{k="inc", by=1}); sim:run(1)
    for _, got in ipairs{ra, rb, rc, rd} do
      eq(#got, 1); eq(got[1].winners, {1}); eq(got[1].losers, {2,3})
      eq(got[1].seats, {A,B,C,D}); eq(got[1].game, "pick"); eq(got[1].tid, tid); eq(got[1].opt, {goal=2})
    end
    ok(a:startGame()); sim:run(1); eq(d.session.state.players, {1,2,3,4}); eq(d.session.state.turn, 1); eq(#ra, 1)
  end)

  it("a player leaves a three-player game: play goes on without his turns, and aborts below two", function()
    local sim, a, b, c = running()
    ok(a:act{k="inc", by=1}); sim:run(1); ok(b:act{k="inc", by=1}); sim:run(1)
    eq(a.session.state.turn, 3)
    c:stand(); sim:run(1); eq(a.session.status, "live"); eq(b.session.state.players, {1,2}); eq(b.session.state.turn, 1)
    b:stand(); sim:run(1); eq(a.session.status, "aborted")
  end)

  it("a player on turn who leaves does not stall the next player's timer", function()
    local sim, a, b, c, d, tid = running()
    ok(a:act{k="inc", by=1}); sim:run(1); ok(b:act{k="inc", by=1}); sim:run(1)
    sim.nextRandom = {1}
    c:stand(); sim:run(1); eq(a.session.state.turn, 1)
    local due = a.session.deadline
    eq(due, sim.clock + 45)
    -- a plain sit while seat 1's turn runs does not re-arm it: the timeout fires at its original time
    sim:run(10); d:sit(tid, 3); sim:run(1)
    eq(a.session.seats[3], D); eq(a.session.deadline, due)
    sim:run(due - 1 - sim.clock); eq(a.session.state.n[1], 1); eq(#sim.nextRandom, 1)
    sim:run(1)
    eq(#sim.nextRandom, 0); eq(a.session.state.n[1], 2)   -- auto played for seat 1 after a fresh full turn
  end)

  it("the act hook rewrites and drops a member's ACT", function()
    local sim, a, b, c, d, tid = running()
    ok(a:act{k="inc", by=1}); sim:run(1)
    a:receive("WHISPER", B, {v=1, t="ACT", tid=tid, a={k="inc", by=99}}); sim:run(1)
    eq(a.session.state.n[2], 1); eq(a.session.state.turn, 3)
    local seq = a.session.seq
    a:receive("WHISPER", C, {v=1, t="ACT", tid=tid, a={k="drop"}}); sim:run(1)
    eq(a.session.seq, seq)
  end)

  it("applied sees table and game events on host and members", function()
    local sim, a, b = running()
    ok(a:act{k="inc", by=1}); sim:run(1)
    local la, lb = a.session.appliedLog, b.session.appliedLog
    eq({la[#la - 1], la[#la]}, {"start", "inc"}); eq({lb[#lb - 1], lb[#lb]}, {"start", "inc"})
  end)

  it("the turn timeout plays auto with env.random", function()
    local sim, a = running()
    local mark = #sim.sent
    sim.nextRandom = {1}; sim:run(46)
    eq(#sim.nextRandom, 0); eq(a.session.state.n[1], 1)
    local autos = 0
    for i, s in ipairs(sim.sent) do
      if i > mark and s.from == A and s.target == B and s.msg.t == "EV" and s.msg.seat == 1 then
        eq(s.msg.auto, true); autos = autos + 1
      end
    end
    eq(autos, 1)
  end)

  it("playAuto makes my move", function()
    local sim, a = running()
    ok(a:playAuto()); eq(a.session.state.n[1], 1); eq({a:playAuto()}, {nil, "turn"})
  end)

  it("a reconnect snapshot does not repeat the result", function()
    local sim, a, b, c, d, tid = running()
    ok(a:act{k="inc", by=1}); sim:run(1); ok(b:act{k="inc", by=1}); sim:run(1); ok(c:act{k="inc", by=1}); sim:run(1)
    ok(a:act{k="inc", by=1}); sim:run(1)
    eq(a.session.state.winner, 1)
    local b2 = sim:relog(B)
    local count = 0
    b2:on("result", function() count = count + 1 end)
    sim:run(2); eq(count, 0); eq(b2.session.state.winner, 1)
    -- a later event on the finished game does not announce it either
    d:sit(tid, 4); sim:run(1); eq(b2.session.seats[4], D); eq(count, 0)
  end)

  it("Морски шах announces its match result once on every client", function()
    local sim, a, b, c = clients()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    c:watch(tid); sim:run(1); b:sit(tid, 2); sim:run(1)
    local ra, rb, rc = results(a), results(b), results(c)
    play(sim, a, b, X_FIRST); sim:run(4)
    play(sim, a, b, O_FIRST); sim:run(4)
    play(sim, a, b, X_FIRST); sim:run(4)
    eq(a.session.state.phase, "match")
    for _, got in ipairs{ra, rb, rc} do
      eq(#got, 1); eq(got[1].winners, {1}); eq(got[1].losers, {2}); eq(got[1].game, "ttt")
    end
  end)
end)
