local _, ns = ...

-- The chess table as plain data (no frames; spec 5.6): what ui/games/ChessView.lua
-- and ChessPanels.lua draw. Model.build(s, sel) gives
--   bottom   the colour at the bottom (1 white, -1 black): mine when I am seated, else white
--   cells    64 in screen order (row 1 on top, left to right): { sq, piece, last, sel, dot, ring, check }
--   myTurn, targets (the legal targets of `sel`, ascending), taken { [seat] = pieces, Q R B N P },
--   lead { [seat] = n } (material ahead, only the positive side), rows { { no, white, black, lastWhite,
--   lastBlack } } (SAN in the UI language), offerFor (the seat that may answer a standing offer),
--   status (the line of text), banner (the end text or nil), canOffer, canResign, canClaim.
local L = ns.L

local Model = {}
ns.ChessModel = Model

local VALUE = { 1, 3, 3, 5, 9 } -- P N B R Q (the king is never taken)
local BANNER = { stalemate = "chess.end.stalemate", repetition = "chess.end.repetition", fifty = "chess.end.fifty",
  material = "chess.end.material", agreed = "chess.end.agreed", flagdraw = "chess.end.flagdraw" }

-- The SAN with its piece letters in the UI language: a leading K Q R B N and the piece after "=".
function Model.san(san)
  local function letter(c) return L("chess.letter." .. c) end
  san = san:gsub("^([KQRBN])", letter)
  return (san:gsub("=([QRBN])", function(c) return "=" .. letter(c) end))
end

-- "5:00" for 2995 tenths (the seconds rounded up); "∞" for nil.
function Model.clockText(tenths)
  if tenths == nil then return L("chess.clock.none") end
  local secs = math.ceil(tenths / 10)
  return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- Does the move f -> t promote a pawn of the side to move?
function Model.promotes(s, f, t)
  local st = s.state
  for _, m in ipairs(ns.ChessRules.moves(st)) do
    if m.f == f and m.t == t and m.p then return true end
  end
  return false
end

local function seatName(s, seat)
  return s.seats and s.seats[seat] or L(seat == s.state.white and "chess.white" or "chess.black")
end

-- Pieces taken, sorted Q R B N P (the sign tells the colour).
local function sorted(list)
  local out = {}
  for i, p in ipairs(list or {}) do out[i] = p end
  table.sort(out, function(a, b) return math.abs(a) > math.abs(b) end)
  return out
end

local function material(list)
  local n = 0
  for _, p in ipairs(list) do n = n + VALUE[math.abs(p)] end
  return n
end

-- The end text of a finished game.
local function bannerOf(s, st)
  local r = st.result
  if st.phase ~= "over" or not r then return nil end
  if r.reason == "mate" then return L("chess.end.mate", seatName(s, r.winner)) end
  if r.reason == "resign" then return L("chess.end.resign", seatName(s, 3 - r.winner)) end
  if r.reason == "flag" then return L("chess.end.flag", seatName(s, r.winner)) end
  if r.reason == "left" then return L("chess.end.left", seatName(s, r.left)) end
  return L(BANNER[r.reason] or "chess.end.agreed")
end

local function statusOf(s, st, me, myTurn, inCheck)
  if st.phase ~= "play" then return "" end
  if st.offer == me then return L("chess.offer.sent") end
  local text = myTurn and L("chess.turn.mine") or L("chess.turn.other", seatName(s, st.turn))
  return inCheck and (text .. " " .. L("chess.check")) or text
end

-- The seat whose side is at the bottom: mine when I am seated, else white's (before a game: seat 1).
function Model.bottomSeat(s)
  if s.mySeat == 1 or s.mySeat == 2 then return s.mySeat end
  return s.state and s.state.white or 1
end

function Model.build(s, sel)
  local R, st, me = ns.ChessRules, s.state, s.mySeat
  local seated = me == 1 or me == 2
  local bottom = Model.bottomSeat(s) == st.white and 1 or -1
  local playing = s.status == "live" and st.phase == "play"
  local myTurn = playing and seated and st.turn == me
  local m = { bottom = bottom, myTurn = myTurn, targets = {}, cells = {}, taken = {}, lead = {} }

  local targetSet, capture = {}, {}
  if myTurn and sel and st.board[sel] ~= 0 and (st.board[sel] > 0) == (st.side == 1) then
    for _, mv in ipairs(R.moves(st)) do
      if mv.f == sel and not targetSet[mv.t] then
        targetSet[mv.t] = true
        m.targets[#m.targets + 1] = mv.t
        capture[mv.t] = st.board[mv.t] ~= 0 or (math.abs(st.board[sel]) == 1 and mv.t == st.ep)
      end
    end
    table.sort(m.targets)
  end
  local last = st.moves[#st.moves]
  local kingSq
  local inCheck = st.side and R.inCheck(st, st.side)
  if inCheck then
    for sq = 1, 64 do if st.board[sq] == 6 * st.side then kingSq = sq end end
  end
  for i = 1, 64 do
    local row, col = math.floor((i - 1) / 8) + 1, (i - 1) % 8 + 1
    local sq = bottom == 1 and (8 - row) * 8 + col or (row - 1) * 8 + 9 - col
    m.cells[i] = { sq = sq, piece = st.board[sq], last = last ~= nil and (sq == last.f or sq == last.t),
      sel = sq == sel and myTurn, dot = targetSet[sq] and not capture[sq] or false, ring = capture[sq] or false,
      check = sq == kingSq }
  end

  for seat = 1, 2 do m.taken[seat] = sorted(st.taken and st.taken[seat]) end
  local a, b = material(m.taken[1]), material(m.taken[2])
  if a > b then m.lead[1] = a - b elseif b > a then m.lead[2] = b - a end

  m.rows = {}
  for i = 1, #st.moves, 2 do
    local w, bl = st.moves[i], st.moves[i + 1]
    m.rows[#m.rows + 1] = { no = (i + 1) / 2, white = Model.san(w.san), black = bl and Model.san(bl.san),
      lastWhite = i == #st.moves, lastBlack = bl ~= nil and i + 1 == #st.moves }
  end

  m.offerFor = st.phase == "play" and st.offer and 3 - st.offer or nil
  m.canOffer = myTurn and st.wait[me] == 0 and not st.offer or false
  m.canResign = playing and seated or false
  m.canClaim = playing and seated and ns.Clock.canClaim(s) or false
  m.banner = bannerOf(s, st)
  m.status = statusOf(s, st, me, myTurn, inCheck)
  return m
end
