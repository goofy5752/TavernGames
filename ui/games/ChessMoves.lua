local _, ns = ...

-- A chess move as the move lists show it (mockup 10: icons and squares instead of SAN), for the
-- table's list on parchment (ui/games/ChessPanels.lua) and the „История“ window (ui/ChessHistory.lua).
local Moves = {}
ns.ChessMoves = Moves

local FILES = "abcdefgh"
local PROMO = { q = 5, r = 4, b = 3, n = 2 }
local LETTER = { N = 2, B = 3, R = 4, Q = 5, K = 6 }

-- "e4" for square 29 (a1 = 1, h8 = 64).
function Moves.square(sq)
  local f = (sq - 1) % 8 + 1
  return FILES:sub(f, f) .. (math.floor((sq - 1) / 8) + 1)
end

-- One move from the SAN alone (a move the replay cannot place): the piece by its letter, a capture
-- without the piece it took.
local function fromSan(m, colour)
  local san = m.san or ""
  local d = { piece = colour * (LETTER[san:sub(1, 1)] or (san:find("^O%-O") and 6) or 1), from = Moves.square(m.f),
    to = Moves.square(m.t), castle = san:find("^O%-O") and (san:find("^O%-O%-O") and "Q" or "K") or nil,
    promo = m.p and PROMO[m.p] and colour * PROMO[m.p] or nil, capture = san:find("x", 1, true) ~= nil }
  return d
end

-- The moves `list` ({ f, t, p, san }, from the start position) described for the list: each
-- { piece (signed: white > 0), from, to ("e2"), take (the piece it took, signed, or nil; en passant
-- a pawn), capture, castle ("K" | "Q": the king's move), promo (the new piece, signed), check, mate,
-- san }. Replayed with the rules' own R.make; check and mate from the SAN's + and #.
-- A move whose piece is not on its square (a list that does not start at the start position) and the
-- rest after it are read from the SAN alone. Cached by the list and its length (a move only adds).
local cache = setmetatable({}, { __mode = "k" })
function Moves.describe(list)
  local R = ns.ChessRules
  local c = cache[list]
  local top = c and c.n > 0 and list[c.n]
  if not c or c.n > #list or (top and c.out[c.n].san ~= (top.san or "")) then
    c = { n = 0, out = {}, pos = R.start() }
    cache[list] = c
  end
  for i = c.n + 1, #list do
    local m, pos = list[i], c.pos
    local colour = i % 2 == 1 and 1 or -1
    local pc = pos and pos.board[m.f] or 0
    local d
    if pos and pc * colour > 0 and pos.side == colour then
      local before = pos.board[m.t]
      local cap = R.make(pos, m)
      d = { piece = pc, from = Moves.square(m.f), to = Moves.square(m.t), take = cap ~= 0 and cap or nil,
        capture = cap ~= 0, ep = cap ~= 0 and before == 0 or nil,
        castle = math.abs(pc) == 6 and math.abs(m.t - m.f) == 2 and (m.t > m.f and "K" or "Q") or nil,
        promo = m.p and PROMO[m.p] and colour * PROMO[m.p] or nil }
    else
      c.pos = nil
      d = fromSan(m, colour)
    end
    local san = m.san or ""
    d.check, d.mate, d.san = san:find("+", 1, true) ~= nil, san:find("#", 1, true) ~= nil, san
    c.out[i] = d
  end
  c.n = #list
  local out = {}
  for i = 1, #list do out[i] = c.out[i] end
  return out
end
