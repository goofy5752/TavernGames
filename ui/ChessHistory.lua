local _, ns = ...

-- The table history of chess (ui/HandHistory.lua's recorder, ui/HandHistoryPanel.lua's panel):
-- a hand of the chess book is one game,
--   { key, no, names = {seat -> name}, white = seat, moves = { move, … }, res = { winner, reason, left } | nil },
-- a move as the lists draw it (ns.ChessMoves.describe: its piece, squares, the piece it took, castling,
-- promotion, check, mate, san). The window shows each game's sides, its moves two a row (number,
-- white, black: ns.HistoryKit), the last one marked, and how it ended; an older game closed to that.
-- A game still running grows with each move. It is the same game while white stays the same
-- and the move list does not shrink and the entry is not over while the state is running again;
-- otherwise (a rematch: white changes, a fresh list, or a game that ended without a move)
-- a new one begins, but only once that game has a move or is over, and never for the
-- finished game seen again as running (no empty entries). Never s.gameNo, which every
-- adopted snapshot moves on. A snapshot
-- (b.jump) rereads the whole list from the state, which is what every update does here.
local L = ns.L
local H = ns.HandHistory

local END = { stalemate = "chess.end.stalemate", repetition = "chess.end.repetition", fifty = "chess.end.fifty",
  material = "chess.end.material", agreed = "chess.end.agreed", flagdraw = "chess.end.flagdraw" }

-- Is the move list the finished game top's own (the same white, the same moves)?
local function echoes(top, st, moves)
  if not (top and top.res and top.white == st.white and #moves == #top.moves) then return false end
  for i, m in ipairs(moves) do if m.san ~= top.moves[i].san then return false end end
  return true
end

local function record(s, st, b)
  local top = b.hands[#b.hands]
  local moves = st.moves or {}
  if not top or top.white ~= st.white or #moves < #top.moves or (top.res and st.phase ~= "over") then
    if st.phase ~= "over" and (#moves == 0 or echoes(top, st, moves)) then return end
    local no = (top and top.no or 0) + 1
    top = { key = "chess:" .. no, no = no, names = {}, white = st.white, moves = {} }
    b.hands[#b.hands + 1] = top
    while #b.hands > H.MAX do table.remove(b.hands, 1) end
  end
  for seat = 1, 2 do
    local who = s.handNames and s.handNames[seat]
    if type(who) ~= "string" then who = s.seats and s.seats[seat] end
    if top.names[seat] == nil and type(who) == "string" then top.names[seat] = who end
  end
  top.moves = ns.ChessMoves.describe(moves)
  local r = st.phase == "over" and st.result
  top.res = r and { winner = r.winner, reason = r.reason, left = r.left } or nil
end

local function endText(hand, r)
  local who = function(seat) return H.whoText(hand, seat) end
  if r.reason == "mate" then return L("chess.end.mate", who(r.winner)) end
  if r.reason == "resign" then return L("chess.end.resign", who(3 - r.winner)) end
  if r.reason == "flag" then return L("chess.end.flag", who(r.winner)) end
  if r.reason == "left" then return L("chess.end.left", who(r.left)) end
  return L(END[r.reason] or "chess.end.agreed")
end

-- The window's block of one game (ui/HandHistoryRows.lua): the sides, the moves, the end.
local function block(hand)
  local side = {}
  local white = hand.white == 2 and 2 or 1 -- none known (a record before it was seen): seat 1
  for k, seat in ipairs({ white, 3 - white }) do
    local name, color, full = H.who(hand, seat)
    side[k] = { piece = k == 1 and 6 or -6, name = name, color = color, full = full }
  end
  local rows, n = {}, #hand.moves
  for i = 1, n, 2 do
    rows[#rows + 1] = { no = (i + 1) / 2, white = hand.moves[i], black = hand.moves[i + 1], lastWhite = i == n, lastBlack = i + 1 == n }
  end
  local out = { rows = { { k = "side", list = side }, { k = "moves", rows = rows } } }
  out.sum = n == 1 and L("chess.history.moves1") or L("chess.history.moves", n)
  if hand.res then
    local text = endText(hand, hand.res)
    out.rows[3] = { k = "result", text = text }
    out.sum = text .. " · " .. out.sum
  end
  return out
end

H.GAMES.chess = true
H.RECORD.chess = record
H.BLOCK.chess = block
