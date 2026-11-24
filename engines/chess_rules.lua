local _, ns = ...
-- The rules of chess: move generation, legality, game end. Pure functions over
-- a position (see R.start); squares 1-64 with a1 = 1, h1 = 8, a8 = 57, pieces
-- 1..6 = P N B R Q K for white, -1..-6 for black, 0 = empty.
local R = {}
ns.ChessRules = R

local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
local FILES = "abcdefgh"
local PIECE = { P = 1, N = 2, B = 3, R = 4, Q = 5, K = 6, p = -1, n = -2, b = -3, r = -4, q = -5, k = -6 }
local PROMO = { "q", "r", "b", "n" }
local PROMO_PIECE = { q = 5, r = 4, b = 3, n = 2 }

-- The key's letter of every piece number.
local SYMBOL = {}
do
  local chars = ".PNBRQKpnbrqk"
  SYMBOL[0] = "."
  for x = 1, 6 do SYMBOL[x] = chars:sub(x + 1, x + 1); SYMBOL[-x] = chars:sub(x + 7, x + 7) end
end

-- The castling rights a move from or to a square ends: its king or its rook
-- leaves, or the rook is taken at home.
local STRIP = { [5] = "[KQ]", [8] = "K", [1] = "Q", [61] = "[kq]", [64] = "k", [57] = "q" }

-- { right, king from, king to, rook home, squares that must be empty, squares
-- the king stands on or passes (not attacked; the target square is checked
-- as for every king move) }
local CASTLES = {
  [1] = { { "K", 5, 7, 8, { 6, 7 }, { 5, 6 } }, { "Q", 5, 3, 1, { 2, 3, 4 }, { 5, 4 } } },
  [-1] = { { "k", 61, 63, 64, { 62, 63 }, { 61, 62 } }, { "q", 61, 59, 57, { 58, 59, 60 }, { 61, 60 } } },
}

-- Square tables, built once. RAYS[sq][d]: the squares from sq outwards in
-- direction d, nearest first (1-4 along ranks and files, 5-8 diagonals).
-- PAWN_FROM[s][sq]: where a pawn of side s stands to attack sq.
-- PAWN_HITS[s][sq]: the squares a pawn of side s on sq attacks.
-- COLOUR[sq]: 0 for a dark square (a1), 1 for a light one.
local KNIGHT, KING, RAYS, COLOUR = {}, {}, {}, {}
local PAWN_FROM, PAWN_HITS = { [1] = {}, [-1] = {} }, { [1] = {}, [-1] = {} }
do
  local DIRS = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
  local JUMPS = { { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }
  local function at(file, rank)
    if file >= 1 and file <= 8 and rank >= 1 and rank <= 8 then return (rank - 1) * 8 + file end
  end
  for sq = 1, 64 do
    local file, rank = (sq - 1) % 8 + 1, math.floor((sq - 1) / 8) + 1
    COLOUR[sq] = (file + rank) % 2
    KNIGHT[sq], KING[sq], RAYS[sq] = {}, {}, {}
    for _, j in ipairs(JUMPS) do
      local t = at(file + j[1], rank + j[2]); if t then KNIGHT[sq][#KNIGHT[sq] + 1] = t end
    end
    for d, v in ipairs(DIRS) do
      local t = at(file + v[1], rank + v[2]); if t then KING[sq][#KING[sq] + 1] = t end
      local ray, k = {}, 1
      while true do
        t = at(file + v[1] * k, rank + v[2] * k)
        if not t then break end
        ray[#ray + 1] = t; k = k + 1
      end
      RAYS[sq][d] = ray
    end
    for _, s in ipairs({ 1, -1 }) do
      local from, hits = {}, {}
      for _, df in ipairs({ -1, 1 }) do
        local f = at(file + df, rank - s); if f then from[#from + 1] = f end
        local t = at(file + df, rank + s); if t then hits[#hits + 1] = t end
      end
      PAWN_FROM[s][sq], PAWN_HITS[s][sq] = from, hits
    end
  end
end

local function kingSq(b, side)
  local k = 6 * side
  for sq = 1, 64 do if b[sq] == k then return sq end end
end

-- The en passant target when it is a real one: empty, with the pawn that
-- just moved two in front of it.
local function epTarget(pos)
  local ep, s = pos.ep, pos.side
  if ep and pos.board[ep] == 0 and pos.board[ep - 8 * s] == -s then return ep end
end

-- What a move does besides the piece going from f to t: the square of a pawn
-- taken en passant, the castling rook's from and to.
local function extras(pc, cap, s, f, t)
  if pc == s then
    if cap == 0 and (t - f) % 8 ~= 0 then return t - 8 * s end
  elseif pc == 6 * s then
    if t - f == 2 then return nil, f + 3, f + 1 end
    if f - t == 2 then return nil, f - 4, f - 1 end
  end
end

function R.attacked(pos, sq, by)
  local b = pos.board
  local list = PAWN_FROM[by][sq]
  for i = 1, #list do if b[list[i]] == by then return true end end
  local n, k = 2 * by, 6 * by
  list = KNIGHT[sq]
  for i = 1, #list do if b[list[i]] == n then return true end end
  list = KING[sq]
  for i = 1, #list do if b[list[i]] == k then return true end end
  local q, rays = 5 * by, RAYS[sq]
  for d = 1, 8 do
    local slider = d <= 4 and 4 * by or 3 * by
    local ray = rays[d]
    for i = 1, #ray do
      local x = b[ray[i]]
      if x ~= 0 then
        if x == slider or x == q then return true end
        break
      end
    end
  end
  return false
end

function R.inCheck(pos, side)
  local k = kingSq(pos.board, side)
  return k ~= nil and R.attacked(pos, k, -side)
end

-- Whether the move leaves the mover's king unattacked. ksq: that king's
-- square before the move (nil: no king, every move is safe).
local function safe(pos, m, ksq)
  local b, s, f, t = pos.board, pos.side, m.f, m.t
  local pc, cap = b[f], b[t]
  local epsq, rf, rt = extras(pc, cap, s, f, t)
  if pc == 6 * s then ksq = t end
  if not ksq then return true end
  b[t], b[f] = pc, 0
  local epcap
  if epsq then epcap = b[epsq]; b[epsq] = 0 end
  if rf then b[rt], b[rf] = b[rf], 0 end
  local fine = not R.attacked(pos, ksq, -s)
  if rf then b[rf], b[rt] = b[rt], 0 end
  if epsq then b[epsq] = epcap end
  b[f], b[t] = pc, cap
  return fine
end

local function add(out, f, t, promo)
  if promo then
    for i = 1, 4 do out[#out + 1] = { f = f, t = t, p = PROMO[i] } end
  else
    out[#out + 1] = { f = f, t = t }
  end
end

local function castles(pos, f, out)
  local b, s = pos.board, pos.side
  for _, c in ipairs(CASTLES[s]) do
    if f == c[2] and b[c[4]] == 4 * s and pos.castle:find(c[1], 1, true) then
      local fine = true
      for _, sq in ipairs(c[5]) do if b[sq] ~= 0 then fine = false end end
      for _, sq in ipairs(c[6]) do if fine and R.attacked(pos, sq, -s) then fine = false end end
      if fine then add(out, f, c[3]) end
    end
  end
end

-- Stable insertion sort of out[first..] by the target square: one piece's
-- moves, so the four promotions keep their order.
local function sortFrom(out, first)
  for i = first + 1, #out do
    local m, j = out[i], i - 1
    while j >= first and out[j].t > m.t do out[j + 1] = out[j]; j = j - 1 end
    out[j + 1] = m
  end
end

-- Every move of the side to move by the pieces' rules, ignoring its own king.
local function pseudo(pos)
  local b, s, out = pos.board, pos.side, {}
  local ep = epTarget(pos)
  for f = 1, 64 do
    local pc = b[f] * s
    if pc > 0 then
      local first = #out + 1
      if pc == 1 then
        local rank = math.floor((f - 1) / 8) + 1
        local last, home = rank == (s == 1 and 7 or 2), rank == (s == 1 and 2 or 7)
        local t = f + 8 * s
        if b[t] == 0 then
          add(out, f, t, last)
          if home and b[t + 8 * s] == 0 then add(out, f, t + 8 * s) end
        end
        local hits = PAWN_HITS[s][f]
        for i = 1, #hits do
          local c = hits[i]
          if b[c] * s < 0 or c == ep then add(out, f, c, last) end
        end
      elseif pc == 2 or pc == 6 then
        local list = pc == 2 and KNIGHT[f] or KING[f]
        for i = 1, #list do if b[list[i]] * s <= 0 then add(out, f, list[i]) end end
        if pc == 6 then castles(pos, f, out) end
      else
        local rays = RAYS[f]
        for d = pc == 3 and 5 or 1, pc == 4 and 4 or 8 do
          local ray = rays[d]
          for i = 1, #ray do
            local x = b[ray[i]] * s
            if x <= 0 then add(out, f, ray[i]) end
            if x ~= 0 then break end
          end
        end
      end
      sortFrom(out, first)
    end
  end
  return out
end

function R.moves(pos)
  local ksq, out = kingSq(pos.board, pos.side), {}
  local list = pseudo(pos)
  for i = 1, #list do if safe(pos, list[i], ksq) then out[#out + 1] = list[i] end end
  return out
end

function R.find(pos, f, t, p)
  local list = R.moves(pos)
  for i = 1, #list do
    local m = list[i]
    if m.f == f and m.t == t and m.p == p then return m end
  end
end

function R.make(pos, m)
  local b, s, f, t = pos.board, pos.side, m.f, m.t
  local pc, cap = b[f], b[t]
  local epsq, rf, rt = extras(pc, cap, s, f, t)
  b[t], b[f] = m.p and PROMO_PIECE[m.p] * s or pc, 0
  if epsq then cap = b[epsq]; b[epsq] = 0 end
  if rf then b[rt], b[rf] = b[rf], 0 end
  if pos.castle ~= "" then
    if STRIP[f] then pos.castle = (pos.castle:gsub(STRIP[f], "")) end
    if STRIP[t] then pos.castle = (pos.castle:gsub(STRIP[t], "")) end
  end
  pos.ep = (pc == s and (t - f == 16 or f - t == 16)) and (f + t) / 2 or nil
  pos.half = (pc == s or cap ~= 0) and 0 or pos.half + 1
  if s == -1 then pos.full = pos.full + 1 end
  pos.side = -s
  return cap
end

function R.fromFen(fen)
  local place, side, castle, ep, half, full =
    tostring(fen):match("^(%S+)%s+([wb])%s+(%S+)%s+(%S+)%s*(%d*)%s*(%d*)")
  if not place then return nil end
  local board = {}
  for i = 1, 64 do board[i] = 0 end
  local rank, file = 8, 1
  for ch in place:gmatch(".") do
    if ch == "/" then
      rank, file = rank - 1, 1
    elseif ch:match("%d") then
      file = file + tonumber(ch)
    else
      if PIECE[ch] and rank >= 1 and file <= 8 then board[(rank - 1) * 8 + file] = PIECE[ch] end
      file = file + 1
    end
  end
  local rights = ""
  for c in ("KQkq"):gmatch(".") do if castle:find(c, 1, true) then rights = rights .. c end end
  local epsq
  local ef, er = ep:match("^([a-h])([36])$")
  if ef then epsq = (tonumber(er) - 1) * 8 + FILES:find(ef, 1, true) end
  return { board = board, side = side == "w" and 1 or -1, castle = rights, ep = epsq,
    half = tonumber(half) or 0, full = tonumber(full) or 1 }
end

function R.start() return R.fromFen(START) end

function R.copy(pos)
  local board = {}
  for i = 1, 64 do board[i] = pos.board[i] end
  return { board = board, side = pos.side, castle = pos.castle, ep = pos.ep, half = pos.half, full = pos.full }
end

-- Whether the side to move can take en passant now (a legal move).
local function epLegal(pos)
  local ep = epTarget(pos)
  if not ep then return false end
  local b, s = pos.board, pos.side
  local ksq, from = kingSq(b, s), PAWN_FROM[s][ep]
  for i = 1, #from do
    if b[from[i]] == s and safe(pos, { f = from[i], t = ep }, ksq) then return true end
  end
  return false
end

function R.key(pos)
  local b, parts = pos.board, {}
  for i = 1, 64 do parts[i] = SYMBOL[b[i]] end
  parts[65] = pos.side == 1 and "w" or "b"
  parts[66] = pos.castle
  if epLegal(pos) then
    local file = (pos.ep - 1) % 8 + 1
    parts[67] = FILES:sub(file, file)
  end
  return table.concat(parts)
end

function R.status(pos)
  if #R.moves(pos) > 0 then return nil end
  return R.inCheck(pos, pos.side) and "mate" or "stalemate"
end

function R.insufficient(pos)
  local b, minors, knights, colours = pos.board, 0, 0, {}
  for sq = 1, 64 do
    local a = math.abs(b[sq])
    if a == 1 or a == 4 or a == 5 then return false end
    if a == 2 then
      minors, knights = minors + 1, knights + 1
    elseif a == 3 then
      minors = minors + 1; colours[COLOUR[sq]] = true
    end
  end
  return minors <= 1 or (knights == 0 and not (colours[0] and colours[1]))
end

function R.bare(pos, side)
  local b = pos.board
  for sq = 1, 64 do
    local x = b[sq] * side
    if x > 0 and x ~= 6 then return false end
  end
  return true
end

function R.perft(pos, depth)
  if depth == 0 then return 1 end
  local list = R.moves(pos)
  if depth == 1 then return #list end
  local n = 0
  for i = 1, #list do
    local c = R.copy(pos)
    R.make(c, list[i])
    n = n + R.perft(c, depth - 1)
  end
  return n
end
