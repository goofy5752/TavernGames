local Sim = require("sim")

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"

-- Three-seat test engine (minSeats 2): "inc" by the seat on turn, turns 1 -> 2 -> 3.
local copy = Sim.ns.Util.copy
local Rota = { id = "rota3", minSeats = 2, maxSeats = 3 }
function Rota.new() return { n = 0, turn = 1 } end
function Rota.apply(s, seat, a)
  if type(a) ~= "table" or a.k ~= "inc" then return nil, "action" end
  if seat ~= s.turn then return nil, "turn" end
  s.n, s.turn = s.n + 1, s.turn % 3 + 1
  return true
end
function Rota.legal(s, seat) return seat == s.turn and { { k = "inc" } } or {} end
function Rota.auto(s, seat) if seat == s.turn then return { k = "inc" } end end
function Rota.system() return nil end
Rota.snapshot, Rota.restore = copy, copy
Sim.ns.Engines.rota3 = Rota

-- a hosts a ttt table, c watches, b sits in seat 2: the match starts (at t=6).
local function setup()
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  local c = sim:add(C, { cls = "ROGUE" })
  sim:run(1)
  local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
  c:watch(tid); sim:run(1)
  b:sit(tid, 2); sim:run(1)
  return sim, a, b, c, tid
end

local function sentBy(sim, from, mark, pred)
  local out = {}
  for i, s in ipairs(sim.sent) do
    if i > mark and s.from == from and (not pred or pred(s)) then out[#out + 1] = s end
  end
  return out
end

local function ofType(t) return function(s) return s.msg.t == t end end

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

-- X wins rounds 1 (X first), 2 (O first) and 3 (X first): phase "match".
local function winMatch(sim, a, b)
  play(sim, a, b, X_FIRST); sim:run(4)
  play(sim, a, b, O_FIRST); sim:run(4)
  play(sim, a, b, X_FIRST); sim:run(4)
end

local function ev(tid, q, seat, a)
  return { v = 1, t = "EV", tid = tid, e = 1, q = q, seat = seat, a = a }
end

describe("table session", function()
  it("plays a full round on three clients (host, guest, watcher) with identical boards", function()
    local sim, a, b, c, tid = setup()
    eq(a.session.status, "live"); eq(b.session.status, "live"); eq(c.session.status, "live")
    eq(b.session.state.turn, 1); sim:run(2); eq(c.lobby:get(tid).state, "live")
    play(sim, a, b, X_FIRST)
    eq(a.session.state.line, {1,2,3}); eq(b.session.state.board, a.session.state.board)
    eq(c.session.state.board, a.session.state.board); eq(c.session.state.line, {1,2,3})
    eq(c.session.state.score, {1,0}); eq(b.session.state.phase, "round")
    sim:run(3); eq(b.session.state.round, 2); eq(c.session.state.round, 2); eq(a.session.state.round, 2)
    eq(b.session.state.turn, 2); eq(b.session.seq, a.session.seq); eq(c.session.seq, a.session.seq)
  end)

  it("applies each event once when every whisper is duplicated", function()
    local sim, a, b, c = setup()
    sim.bus.filter = function(_, _, _, m) return {m, m} end
    ok(a:act{k="mark", c=1}); sim:run(1)
    eq(b.session.seq, a.session.seq); eq(b.session.state.board[1], 1); eq(b.session.state.turn, 2)
    ok(b:act{k="mark", c=5}); sim:run(1)
    eq(a.session.state.board, {1,0,0,0,2,0,0,0,0}); eq(b.session.state.board, a.session.state.board)
    eq(c.session.state.board, a.session.state.board); eq(c.session.seq, a.session.seq)
    eq(a.session.state.turn, 1)
  end)

  it("gap triggers SYN and snapshot heals", function()
    local sim, a, b, _, tid = setup()
    local dropped = false
    sim.bus.filter = function(_, to, _, m)
      if not dropped and to == B and m.t == "EV" then dropped = true; return {} end
      return { m }
    end
    local m0 = #sim.sent
    ok(a:act{k="mark", c=1}); sim:run(0)
    ok(dropped); eq(b.session.seq, a.session.seq - 1); eq(b.session.state.board[1], 0)
    -- b's move reaches the host anyway; the EV for it arrives at b one event too far
    a:receive("WHISPER", B, { v = 1, t = "ACT", tid = tid, a = { k = "mark", c = 4 } })
    sim:run(1)
    eq(#sentBy(sim, B, m0, ofType("SYN")), 1)
    eq(sentBy(sim, B, m0, ofType("SYN"))[1].target, A)
    eq(b.session.state.board, a.session.state.board); eq(b.session.seq, a.session.seq)
    eq(b.session.state.board[4], 2); eq(b.session.status, "live")
  end)

  it("a desynced EV from the host emits desync and asks once for a snapshot", function()
    local sim, a, b, _, tid = setup()
    local seen = {}; b:on("desync", function(t) seen[#seen + 1] = t end)
    local m0, q = #sim.sent, b.session.seq
    b:receive("WHISPER", A, ev(tid, q + 1, 2, { k = "mark", c = 1 })) -- not seat 2's turn
    eq(seen, { tid }); eq(b.session.seq, q); eq(b.session.state.board[1], 0)
    b:receive("WHISPER", A, ev(tid, q + 1, 2, { k = "mark", c = 2 }))
    eq(#seen, 2)
    sim:run(1)
    eq(#sentBy(sim, B, m0, ofType("SYN")), 1); eq(sentBy(sim, B, m0, ofType("SYN"))[1].msg.have, q)
    eq(b.session.seq, a.session.seq); eq(b.session.state.board, a.session.state.board)
  end)

  it("TCK every 30 s lets a member behind it resync; members PNG every 30 s", function()
    local sim, a, b = setup()
    local dropped = false
    sim.bus.filter = function(_, to, _, m)
      if not dropped and to == B and m.t == "EV" then dropped = true; return {} end
      return { m }
    end
    local m0 = #sim.sent
    ok(a:act{k="mark", c=1}); sim:run(1)
    eq(b.session.seq, a.session.seq - 1)
    sim:run(29)
    local tck = sentBy(sim, A, m0, function(s) return s.msg.t == "TCK" and s.target == B end)
    eq(#tck, 1); eq(tck[1].msg.q, a.session.seq); eq(tck[1].msg.e, 1)
    eq(#sentBy(sim, B, m0, ofType("SYN")), 1)
    eq(b.session.seq, a.session.seq); eq(b.session.state.board[1], 1)
    local png = sentBy(sim, B, 0, ofType("PNG"))
    eq(#png, 1); eq(png[1].target, A); eq(png[1].channel, "WHISPER")
    sim:run(30); eq(#sentBy(sim, B, 0, ofType("PNG")), 2)
    eq(#sentBy(sim, C, 0, ofType("PNG")), 2)
    eq(#sentBy(sim, B, m0, ofType("SYN")), 1) -- in step again: no further SYN
  end)

  it("out-of-turn and taken-cell actions never become events", function()
    local sim, a, b, c, tid = setup()
    eq({ b:act{k="mark", c=4} }, { nil, "turn" })
    local q, m0 = a.session.seq, #sim.sent
    a:receive("WHISPER", B, { v = 1, t = "ACT", tid = tid, a = { k = "mark", c = 4 } }); sim:run(1)
    eq(a.session.seq, q); eq(a.session.state.board[4], 0); eq(#sentBy(sim, A, m0, ofType("EV")), 0)
    ok(a:act{k="mark", c=1}); sim:run(1)
    q, m0 = a.session.seq, #sim.sent
    eq({ b:act{k="mark", c=1} }, { nil, "cell" })
    eq({ a:act{k="mark", c=2} }, { nil, "turn" })
    eq({ c:act{k="mark", c=2} }, { nil, "seat" })
    a:receive("WHISPER", B, { v = 1, t = "ACT", tid = tid, a = { k = "mark", c = 1 } }); sim:run(1)
    eq(a.session.seq, q); eq(a.session.state.turn, 2); eq(#sentBy(sim, A, m0, ofType("EV")), 0)
    eq(#sentBy(sim, B, m0, ofType("ACT")), 0)
  end)

  it("ACT from a watcher or a stranger is ignored", function()
    local sim, a, _, _, tid = setup()
    local q, m0 = a.session.seq, #sim.sent
    a:receive("WHISPER", C, { v = 1, t = "ACT", tid = tid, a = { k = "mark", c = 1 } })
    a:receive("WHISPER", D, { v = 1, t = "ACT", tid = tid, a = { k = "mark", c = 1 } })
    sim:run(1)
    eq(a.session.seq, q); eq(a.session.state.board[1], 0); eq(a.session.state.turn, 1)
    eq(#sentBy(sim, A, m0, ofType("EV")), 0)
  end)

  it("EV from a non-host is ignored", function()
    local sim, a, b, c, tid = setup()
    ok(a:act{k="mark", c=1}); sim:run(1)
    local q = b.session.seq
    b:receive("WHISPER", C, ev(tid, q + 1, 2, { k = "mark", c = 5 }))
    b:receive("WHISPER", D, ev(tid, q + 1, 2, { k = "mark", c = 5 }))
    c:receive("WHISPER", B, ev(tid, q + 1, 2, { k = "mark", c = 5 }))
    sim:run(1)
    eq(b.session.state.board, {1,0,0,0,0,0,0,0,0}); eq(b.session.seq, q); eq(b.session.state.turn, 2)
    eq(c.session.state.board, {1,0,0,0,0,0,0,0,0}); eq(c.session.seq, q)
  end)

  it("point-to-point messages received on GUILD are ignored and never answered", function()
    local sim, a, b, c, tid = setup()
    ok(a:act{k="mark", c=1}); sim:run(1)
    local qa, qb, m0 = a.session.seq, b.session.seq, #sim.sent
    a:receive("GUILD", B, { v = 1, t = "ACT", tid = tid, a = { k = "mark", c = 5 } })
    a:receive("GUILD", D, { v = 1, t = "SIT", tid = tid, seat = 2 })
    a:receive("GUILD", D, { v = 1, t = "WAT", tid = tid })
    a:receive("GUILD", D, { v = 2, t = "SIT", tid = tid, seat = 2 })
    a:receive("GUILD", C, { v = 1, t = "SYN", tid = tid, have = 0 })
    a:receive("GUILD", B, { v = 1, t = "STD", tid = tid })
    b:receive("GUILD", A, ev(tid, qb + 1, 2, { k = "mark", c = 5 }))
    b:receive("GUILD", A, { v = 1, t = "TCK", tid = tid, e = 1, q = 99 })
    c:receive("GUILD", A, { v = 1, t = "SNO", tid = tid, why = "full" })
    sim:run(1)
    eq(#sentBy(sim, A, m0, function(s) return s.msg.t == "SNO" or s.msg.t == "SNP" or s.msg.t == "EV" end), 0)
    eq(#sentBy(sim, B, m0, ofType("SYN")), 0)
    eq(a.session.seq, qa); eq(b.session.seq, qb); eq(b.session.state.board[5], 0)
    eq(a.session.seats, { A, B }); eq(a.session.watchers, 1); eq(b.session.status, "live")
  end)

  it("turn timeout plays the first empty cell, flagged auto, no loss", function()
    local sim, a, b = setup()
    local m0 = #sim.sent
    sim:run(46); eq(a.session.state.board[1], 1); eq(a.session.status, "live"); eq(b.session.state.turn, 2)
    eq(b.session.state.board[1], 1); eq(a.session.state.score, {0,0}); eq(a.session.state.phase, "play")
    local evs = sentBy(sim, A, m0, function(s) return s.msg.t == "EV" and s.target == B end)
    eq(#evs, 1); eq(evs[1].msg.seat, 1); eq(evs[1].msg.auto, true); eq(evs[1].msg.a, { k = "mark", c = 1 })
    eq(evs[1].msg.left, 45); eq(evs[1].at, 51)
    eq(a.session.deadline, 96); eq(b.session.deadline, 96)
  end)

  it("no auto action while waiting for rematch", function()
    local sim, a, b, c = setup()
    winMatch(sim, a, b)
    eq(a.session.state.phase, "match"); eq(a.session.state.winner, 1); eq(a.session.deadline, nil)
    local q = a.session.seq
    sim:run(120)
    eq(a.session.state.phase, "match"); eq(b.session.state.phase, "match"); eq(c.session.state.phase, "match")
    eq(a.session.seq, q); eq(c.session.seq, q)
  end)

  it("rematch by both restarts 0:0 with the other seat first", function()
    local sim, a, b, c = setup()
    winMatch(sim, a, b)
    eq(c.session.state.score, {3,0})
    ok(a:act{k="rematch"}); sim:run(1)
    for _, cl in ipairs({ a, b, c }) do eq(cl.session.state.phase, "match") end
    ok(b:act{k="rematch"}); sim:run(1)
    for _, cl in ipairs({ a, b, c }) do
      local st = cl.session.state
      eq(st.phase, "play"); eq(st.score, {0,0}); eq(st.round, 1); eq(st.turn, 2)
    end
    eq(b.session.deadline, a.session.deadline); ok(a.session.deadline)
  end)

  it("standing mid-match aborts without a winner and reopens the chair", function()
    local sim, a, b, c, tid = setup()
    ok(a:act{k="mark", c=1}); sim:run(1)
    local m0 = #sim.sent
    b:stand(); sim:run(3)
    eq(a.session.status, "aborted"); eq(c.session.status, "aborted"); eq(a.session.deadline, nil)
    eq(c.lobby:get(tid).state, "open"); eq(c.lobby:get(tid).seats, { A, false })
    eq(a.session.seats, { A, false }); eq(c.session.seats, { A, false })
    eq(a.session.state.winner, nil); eq(c.session.state.board[1], 1)
    local kinds = {}
    for _, s in ipairs(sentBy(sim, A, m0, function(s) return s.msg.t == "EV" end)) do kinds[#kinds + 1] = s.msg.a.k end
    eq(kinds, { "stand", "abort" })
    local q = a.session.seq; sim:run(60); eq(a.session.seq, q)
    b:sit(tid, 2); sim:run(1)
    eq(b.session.status, "live"); eq(c.session.status, "live"); eq(c.session.state.board, {0,0,0,0,0,0,0,0,0})
    eq(b.session.state.turn, 1)
  end)

  it("with enough players left the match goes on and the empty seat is auto-played", function()
    local sim = Sim.new()
    local a = sim:add(A, { cls = "MAGE" }); local b = sim:add(B, { cls = "PRIEST" }); local c = sim:add(C, { cls = "ROGUE" })
    sim:run(1)
    local tid = a:openTable{game="rota3", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); c:sit(tid, 3); sim:run(1)
    eq(a.session.status, "live"); eq(c.session.state, { n = 0, turn = 1 })
    ok(a:act{k="inc"}); sim:run(1); ok(b:act{k="inc"}); sim:run(1)
    c:stand(); sim:run(1)
    eq(a.session.status, "live"); eq(b.session.status, "live"); eq(a.session.seats, { A, B, false })
    eq(b.session.state, { n = 2, turn = 3 })
    local m0 = #sim.sent
    sim:run(45)
    eq(b.session.state, { n = 3, turn = 1 })
    local evs = sentBy(sim, A, m0, function(s) return s.msg.t == "EV" and s.target == B end)
    eq(#evs, 1); eq(evs[1].msg.seat, 3); eq(evs[1].msg.auto, true)
  end)
end)
