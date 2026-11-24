local Chess = require("chess")
local E, R, sq = Chess.E, Chess.R, Chess.sq

local function first() return 1 end
local function last(_, n) return n end

describe("chess bot", function()
  it("takes a hanging queen", function()
    local s = Chess.at("4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")
    eq(E.bot(s, s.turn, first), { k = "move", f = 29, t = 36 })
  end)

  it("mates in one", function()
    local s = Chess.at("7k/8/6K1/8/8/8/8/R7 w - - 0 1")
    eq(E.bot(s, s.turn, first), { k = "move", f = 1, t = 57 })
  end)

  it("does not hang its queen to a pawn", function()
    -- Qd4 may take d5 (guarded by the e6 pawn) or a7 (free): it never plays Qxd5.
    local s = Chess.at("4k3/p7/4p3/3p4/3Q4/8/8/4K3 w - - 0 1")
    local a = E.bot(s, s.turn, first)
    ok(a.t ~= sq("d5"), "the queen took the guarded pawn")
    -- The same with a black rook on a8.
    s = Chess.at("r3k3/p7/4p3/3p4/3Q4/8/8/4K3 w - - 0 1")
    ok(E.bot(s, s.turn, first).t ~= sq("d5"), "the queen took the guarded pawn")
  end)

  it("equal moves are chosen by the random it is given", function()
    local s = E.new{ first = 2, opt = { clock = 0 } }
    local a, b = E.bot(s, 2, first), E.bot(s, 2, last)
    ok(a.f ~= b.f or a.t ~= b.t, "the same move")
    eq(E.bot(s, 2, first), a); eq(E.bot(s, 2, last), b)
    ok(R.find(s, a.f, a.t, a.p) and R.find(s, b.f, b.t, b.p), "illegal move")
  end)

  it("accepts a draw when it is losing and plays on when it is not", function()
    local s = Chess.at("4k3/8/8/8/8/8/8/3QK3 b - - 0 1") -- black on turn, white offered
    s.offer = s.white
    local black = 3 - s.white
    eq(E.bot(s, black, first), { k = "accept" })
    local level = Chess.at("4k3/8/8/8/8/8/8/4K3 b - - 0 1")
    level.offer = level.white
    local a = E.bot(level, 3 - level.white, first)
    eq(a.k, "move")
    -- a standing offer while it is not its turn and not losing: nothing to do
    local calm = Chess.at("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    calm.offer = 3 - calm.turn
    eq(E.bot(calm, 3 - calm.white, first), nil)
  end)

  it("answers nothing off turn or when the game is over", function()
    local s = E.new{ first = 2, opt = { clock = 0 } }
    eq(E.bot(s, 1, first), nil)
    s.phase = "over"
    eq(E.bot(s, 2, first), nil)
  end)

  it("plays a whole game against itself", function()
    local s = E.new{ first = 2, opt = { clock = 0 } }
    local seed = 12345
    local function rnd(lo, hi)
      seed = (seed * 1103515245 + 12345) % 2147483648
      return lo + math.floor(seed / 65536) % (hi - lo + 1)
    end
    local plies = 0
    while s.phase == "play" and plies < 600 do
      local a = E.bot(s, s.turn, rnd)
      ok(a, "no action at ply " .. plies)
      ok(E.apply(s, s.turn, a), "refused at ply " .. plies)
      plies = plies + 1
    end
    if s.phase == "over" then ok(s.result.reason, "no reason") else ok(#E.legal(s, s.turn) > 0) end
  end)

  it("a move stays within the node cap and is quick", function()
    for _, fen in ipairs({
      "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
      "r1bq1rk1/pp2ppbp/2np1np1/8/3NP3/2N1BP2/PPPQ2PP/R3KB1R w KQ - 0 9",
    }) do
      local s = Chess.at(fen)
      local t = os.clock()
      ok(E.bot(s, s.turn, first))
      local took = os.clock() - t
      ok(E.botCount <= E.BOT_NODES, "count " .. E.botCount)
      ok(took < 0.25, "took " .. took)
    end
  end)
end)
