local Chess = require("chess")
local E = Chess.E

local function fresh() return E.new{ first = 2, opt = { clock = 0 } } end
local function sans(s)
  local out = {}
  for i, m in ipairs(s.moves) do out[i] = m.san end
  return out
end
local function last(s) return s.moves[#s.moves].san end

describe("chess san", function()
  it("a piece move and a mate", function()
    eq(Chess.play(fresh(), "g1f3").moves[1].san, "Nf3")
    local s = Chess.play(fresh(), "f2f3 e7e5 g2g4 d8h4")
    eq(sans(s), { "f3", "e5", "g4", "Qh4#" })
    eq(s.phase, "over"); eq(s.result.winner, 1); eq(s.result.reason, "mate")
  end)
  it("a pawn capture en passant starts with its file", function()
    eq(last(Chess.play(fresh(), "e2e4 a7a6 e4e5 d7d5 e5d6")), "exd6")
  end)
  it("castling both ways", function()
    local FEN = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
    eq(last(Chess.play(Chess.at(FEN), "e1g1")), "O-O")
    eq(last(Chess.play(Chess.at(FEN), "e1c1")), "O-O-O")
  end)
  it("a promotion with check", function()
    eq(last(Chess.play(Chess.at("4k3/P7/8/8/8/8/8/4K3 w - - 0 1"), "a7a8q")), "a8=Q+")
  end)
  it("disambiguation by file, by rank, by both", function()
    eq(last(Chess.play(Chess.at("8/8/1k6/8/8/8/8/KN3N2 w - - 0 1"), "b1d2")), "Nbd2")
    eq(last(Chess.play(Chess.at("8/8/1k6/R7/8/8/8/R3K3 w - - 0 1"), "a1a3")), "R1a3")
    eq(last(Chess.play(Chess.at("8/8/1k6/8/4Q2Q/8/8/K6Q w - - 0 1"), "h4e1")), "Qh4e1")
  end)
  it("a plain capture by a piece and by a pawn, and a rival that is pinned", function()
    eq(last(Chess.play(fresh(), "e2e4 d7d5 e4d5 d8d5 b1c3 d5a5 f1b5 c7c6 b5c6")), "Bxc6+")
    eq(last(Chess.play(fresh(), "e2e4 d7d5 e4d5")), "exd5")
    -- the knight on e2 is pinned by the rook on e8: Nc3, not Nbc3
    eq(last(Chess.play(Chess.at("4r1k1/8/8/8/8/8/4N3/1N2K3 w - - 0 1"), "b1c3")), "Nc3")
  end)
end)
