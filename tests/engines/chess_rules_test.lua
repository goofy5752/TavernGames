local ns = require("sim").ns
local R = ns.ChessRules

local KIWI = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
local function play(pos, seq)
  for i = 1, #seq, 2 do
    local m = R.find(pos, seq[i], seq[i + 1]); ok(m, "move " .. seq[i] .. "-" .. seq[i + 1]); R.make(pos, m)
  end
  return pos
end

describe("chess rules", function()
  it("perft from the start", function()
    eq(R.perft(R.start(), 1), 20); eq(R.perft(R.start(), 2), 400); eq(R.perft(R.start(), 3), 8902)
  end)
  it("perft of Kiwipete", function()
    eq(R.perft(R.fromFen(KIWI), 1), 48); eq(R.perft(R.fromFen(KIWI), 2), 2039)
  end)
  it("perft of the en passant pins, the promotions and the castling traps", function()
    local P3 = R.fromFen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
    eq(R.perft(P3, 1), 14); eq(R.perft(P3, 2), 191); eq(R.perft(P3, 3), 2812)
    local P4 = R.fromFen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
    eq(R.perft(P4, 1), 6); eq(R.perft(P4, 2), 264)
    local P5 = R.fromFen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
    eq(R.perft(P5, 1), 44); eq(R.perft(P5, 2), 1486)
  end)

  it("castling needs every condition", function()
    local pos = R.fromFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    ok(R.find(pos, 5, 7)); ok(R.find(pos, 5, 3))
    pos = R.fromFen("5rk1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    eq(R.find(pos, 5, 7), nil); ok(R.find(pos, 5, 3))
    pos = R.fromFen("4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    eq(R.find(pos, 5, 7), nil); eq(R.find(pos, 5, 3), nil)
    pos = R.fromFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    R.make(pos, R.find(pos, 8, 16)); eq(pos.castle, "Qkq")
    pos = R.fromFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    eq(R.make(pos, R.find(pos, 8, 64)), -4); eq(pos.castle, "Qq")
  end)
  it("castling moves the rook and a king move ends both rights", function()
    local pos = R.fromFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    eq(R.make(pos, R.find(pos, 5, 7)), 0)
    eq({pos.board[5], pos.board[6], pos.board[7], pos.board[8]}, {0, 4, 6, 0}); eq(pos.castle, "kq")
    R.make(pos, R.find(pos, 61, 59))
    eq({pos.board[57], pos.board[58], pos.board[59], pos.board[60], pos.board[61]}, {0, 0, -6, -4, 0}); eq(pos.castle, "")
  end)
  it("en passant only at once", function()
    local pos = play(R.start(), {13, 29, 49, 41, 29, 37, 52, 36})
    eq(pos.ep, 44); ok(R.find(pos, 37, 44))
    eq(R.make(pos, R.find(pos, 37, 44)), -1); eq(pos.board[36], 0); eq(pos.board[44], 1); eq(pos.board[37], 0)
    pos = play(R.start(), {13, 29, 49, 41, 29, 37, 52, 36, 16, 24, 56, 48})
    eq(pos.ep, nil); eq(R.find(pos, 37, 44), nil)
  end)
  it("a promotion needs its piece", function()
    local pos = R.fromFen("8/P6k/8/8/8/8/8/K7 w - - 0 1")
    eq(R.find(pos, 49, 57), nil); ok(R.find(pos, 49, 57, "q")); eq(R.find(pos, 49, 57, "k"), nil)
    eq(R.find(R.start(), 13, 29, "q"), nil)
    local list = {}
    for _, m in ipairs(R.moves(pos)) do if m.f == 49 then list[#list + 1] = m.p end end
    eq(list, {"q", "r", "b", "n"})
    R.make(pos, R.find(pos, 49, 57, "n")); eq(pos.board[57], 2); eq(pos.board[49], 0)
  end)
  it("the key counts en passant only when it can be taken", function()
    eq(R.key(R.fromFen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")),
      R.key(R.fromFen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")))
    local a = R.key(R.fromFen("rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 2"))
    local b = R.key(R.fromFen("rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2"))
    ok(a ~= b, a); eq(a:sub(65), "bKQkqe")
    eq(R.key(R.fromFen("8/8/8/8/k2Pp2Q/8/8/3K4 b - d3 0 1")), R.key(R.fromFen("8/8/8/8/k2Pp2Q/8/8/3K4 b - - 0 1")))
    eq(R.key(R.start()), "RNBQKBNRPPPPPPPP" .. ("."):rep(32) .. "pppppppprnbqkbnrwKQkq")
  end)
  it("mate and stalemate", function()
    eq(R.status(R.fromFen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")), "mate")
    eq(R.status(R.fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")), "stalemate")
    eq(R.status(R.start()), nil)
  end)
  it("insufficient material", function()
    for _, fen in ipairs({ "8/8/8/8/8/2k5/8/K7 w - - 0 1", "8/8/8/8/8/2k5/8/K1B5 w - - 0 1",
      "8/8/8/8/8/2k5/8/KN6 w - - 0 1", "8/8/8/8/8/2k1b3/8/K1B5 w - - 0 1" }) do
      eq(R.insufficient(R.fromFen(fen)), true)
    end
    for _, fen in ipairs({ "8/8/8/8/8/2k2b2/8/K1B5 w - - 0 1", "8/8/8/8/8/2k5/8/KNN5 w - - 0 1",
      "8/8/8/8/8/2k5/8/KR6 w - - 0 1", "8/8/8/8/8/2k5/P7/K7 w - - 0 1" }) do
      eq(R.insufficient(R.fromFen(fen)), false)
    end
  end)
  it("R.moves is ordered and repeatable", function()
    local pos = R.fromFen(KIWI)
    local a, b = R.moves(pos), R.moves(pos)
    eq(a, b); eq(#a, 48)
    for i = 2, #a do ok(a[i - 1].f < a[i].f or (a[i - 1].f == a[i].f and a[i - 1].t < a[i].t), "order at " .. i) end
  end)

  it("make keeps the counters, copy is independent", function()
    local pos = R.start()
    eq({pos.side, pos.castle, pos.ep, pos.half, pos.full}, {1, "KQkq", nil, 0, 1})
    local c = R.copy(pos)
    play(pos, {7, 22}); eq({pos.side, pos.half, pos.full, pos.ep}, {-1, 1, 1, nil})
    play(pos, {58, 43}); eq({pos.side, pos.half, pos.full}, {1, 2, 2})
    play(pos, {13, 29}); eq({pos.half, pos.ep}, {0, 21})
    eq(c.board[7], 2); eq(c.board[22], 0); eq(c.side, 1)
    local n = 0; for _ in pairs(c) do n = n + 1 end; eq(n, 5) -- ep is nil: five fields set
  end)
  it("check, attack and a bare king", function()
    local pos = R.fromFen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")
    eq(R.inCheck(pos, 1), true); eq(R.inCheck(pos, -1), false)
    eq(R.attacked(pos, 5, -1), true); eq(R.attacked(pos, 22, 1), true); eq(R.attacked(pos, 30, -1), true)
    eq(R.attacked(R.start(), 29, 1), false); eq(R.attacked(R.start(), 20, 1), true)
    pos = R.fromFen("8/8/8/8/8/2k5/8/KR6 w - - 0 1")
    eq(R.bare(pos, -1), true); eq(R.bare(pos, 1), false)
  end)
end)
