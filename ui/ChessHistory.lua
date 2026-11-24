local _, ns = ...

-- The table history of chess (ui/HandHistory.lua's recorder, ui/HandHistoryPanel.lua's panel):
-- a hand of the chess book is one game,
--   { key, no, names = {seat -> name}, white = seat, moves = { san, … }, res = { winner, reason, left } | nil }.
-- A game still running grows with each move. It is the same game while white stays the same
-- and the move list does not shrink and the entry is not over while the state is running again;
-- otherwise (a rematch: white changes, a fresh list, or a game that ended without a move)
-- a new one begins. Never s.gameNo, which every adopted snapshot moves on. A snapshot
-- (b.jump) rereads the whole list from the state, which is what every update does here.
local L = ns.L
local H = ns.HandHistory

local END = { stalemate = "chess.end.stalemate", repetition = "chess.end.repetition", fifty = "chess.end.fifty",
  material = "chess.end.material", agreed = "chess.end.agreed", flagdraw = "chess.end.flagdraw" }

local function record(s, st, b)
  local top = b.hands[#b.hands]
  local moves = st.moves or {}
  if not top or top.white ~= st.white or #moves < #top.moves or (top.res and st.phase ~= "over") then
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
  top.moves = {}
  for i, m in ipairs(moves) do top.moves[i] = m.san end
  local r = st.phase == "over" and st.result
  top.res = r and { winner = r.winner, reason = r.reason, left = r.left } or nil
end

local function name(hand, seat)
  local who = seat and hand.names[seat]
  return type(who) == "string" and who or "?"
end

local function endText(hand, r)
  if r.reason == "mate" then return L("chess.end.mate", name(hand, r.winner)) end
  if r.reason == "resign" then return L("chess.end.resign", name(hand, 3 - r.winner)) end
  if r.reason == "flag" then return L("chess.end.flag", name(hand, r.winner)) end
  if r.reason == "left" then return L("chess.end.left", name(hand, r.left)) end
  return L(END[r.reason] or "chess.end.agreed")
end

-- The panel's lines of one game: add(style, text).
local function draw(add, hand)
  local M = ns.ChessModel
  add("head", L("chess.history.game", hand.no))
  add("sub", L("chess.history.sides", name(hand, hand.white), name(hand, 3 - hand.white)))
  for i = 1, #hand.moves, 2 do
    local line = (math.floor((i + 1) / 2)) .. ". " .. M.san(hand.moves[i])
    if hand.moves[i + 1] then line = line .. " " .. M.san(hand.moves[i + 1]) end
    add("line", line)
  end
  if hand.res then add("sub", endText(hand, hand.res)) end
end

H.GAMES.chess = true
H.RECORD.chess = record
H.DRAW.chess = draw
