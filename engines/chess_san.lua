local _, ns = ...
-- Standard algebraic notation of a move, with English letters (K Q R B N);
-- the view translates the letters. Pure, over the positions of ns.ChessRules.
local S = {}
ns.ChessSan = S

local FILES = "abcdefgh"
local LETTER = { [2] = "N", [3] = "B", [4] = "R", [5] = "Q", [6] = "K" }

local function file(sq) return (sq - 1) % 8 + 1 end
local function rank(sq) return math.floor((sq - 1) / 8) + 1 end
local function name(sq) return FILES:sub(file(sq), file(sq)) .. rank(sq) end

-- What tells the move apart from the legal moves of the same kind of piece
-- to the same square: nothing, the file of its square, the rank, or both.
local function disambiguation(pos, m, pc)
  local sameFile, sameRank, rival = false, false, false
  for _, o in ipairs(ns.ChessRules.moves(pos)) do
    if o.t == m.t and o.f ~= m.f and pos.board[o.f] == pc then
      rival = true
      if file(o.f) == file(m.f) then sameFile = true end
      if rank(o.f) == rank(m.f) then sameRank = true end
    end
  end
  if not rival then return "" end
  if not sameFile then return FILES:sub(file(m.f), file(m.f)) end
  if not sameRank then return tostring(rank(m.f)) end
  return name(m.f)
end

-- pos: the position before the legal move m, after: the position after it.
function S.of(pos, m, after)
  local R = ns.ChessRules
  local pc = pos.board[m.f]
  local kind, out = math.abs(pc), nil
  if kind == 6 and math.abs(m.t - m.f) == 2 then
    out = m.t > m.f and "O-O" or "O-O-O"
  elseif kind == 1 then
    local capture = file(m.t) ~= file(m.f) -- en passant takes on an empty square
    out = (capture and FILES:sub(file(m.f), file(m.f)) .. "x" or "") .. name(m.t)
    if m.p then out = out .. "=" .. m.p:upper() end
  else
    out = LETTER[kind] .. disambiguation(pos, m, pc) .. (pos.board[m.t] ~= 0 and "x" or "") .. name(m.t)
  end
  if R.status(after) == "mate" then return out .. "#" end
  if R.inCheck(after, after.side) then return out .. "+" end
  return out
end
