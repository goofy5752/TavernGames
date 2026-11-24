local _, ns = ...
-- The chess training bot (never at a table for gold): material and small
-- square bonuses, negamax with alpha-beta over 2 plies plus a capture-only
-- ply, a hard cap on the positions searched, and `random` as the only tie
-- break. E.bot(s, seat, random) -> action | nil.
local E = ns.Engines.chess
local R = ns.ChessRules

E.BOT_NODES = 3000 -- positions searched for one move; the search ends by itself near 600 (3000 nodes = about 41 ms, JIT off)
E.botCount = 0     -- positions searched by the last call

local VALUE = { 100, 300, 300, 500, 900, 0 }
local MATE, INF = 100000, 1000000
local LOSING = -150 -- below this a standing draw offer is accepted

-- Closeness to the centre, 0 to 20, by square.
local CENTRE = {}
for sq = 1, 64 do
  local file, rank = (sq - 1) % 8 + 1, math.floor((sq - 1) / 8) + 1
  local ring = math.min(file, 9 - file, rank, 9 - rank)
  CENTRE[sq] = math.floor((ring - 1) * 20 / 3)
end

-- The position for white in centipawns.
local function evaluate(b)
  local score, queens = 0, false
  local kings = { 0, 0 } -- king bonus by colour index, 1 white 2 black
  for sq = 1, 64 do
    local pc = b[sq]
    if pc ~= 0 then
      local c = pc > 0 and 1 or -1
      local kind = pc * c
      local v = VALUE[kind]
      if kind == 1 or kind == 2 then v = v + CENTRE[sq] end
      if kind == 2 or kind == 3 then
        local home = c == 1 and 1 or 8
        if math.floor((sq - 1) / 8) + 1 ~= home then v = v + 10 end
      elseif kind == 5 then
        queens = true
      elseif kind == 6 then
        local home = c == 1 and 1 or 8
        if math.floor((sq - 1) / 8) + 1 == home then kings[c == 1 and 1 or 2] = 10 end
      end
      score = score + c * v
    end
  end
  if queens then score = score + kings[1] - kings[2] end
  return score
end

-- Captures (and promotions) first, the dearest victim by the cheapest taker.
local function order(pos, list, capturesOnly)
  local b, keyed = pos.board, {}
  for i = 1, #list do
    local m = list[i]
    local victim = b[m.t] ~= 0 and math.abs(b[m.t]) or 0
    if victim == 0 and math.abs(b[m.f]) == 1 and m.t == pos.ep then victim = 1 end
    local key = victim * 10 - math.abs(b[m.f])
    if m.p then key = key + 8 end
    if victim > 0 or m.p or not capturesOnly then
      keyed[#keyed + 1] = { m = m, key = key * 1000 - i }
    end
  end
  table.sort(keyed, function(x, y) return x.key > y.key end)
  for i = 1, #keyed do keyed[i] = keyed[i].m end
  return keyed
end

local count, cap, stopped

-- Negamax value of pos for the side to move. depth > 0: every move;
-- depth 0: captures only, each followed by the static value (depth -1), so the
-- capture ply is one ply. Stands pat even in check (no evasions are searched).
local function search(pos, depth, alpha, beta, ply)
  if count >= cap then stopped = true; return 0 end
  count = count + 1
  local stand = evaluate(pos.board) * pos.side
  if depth < 0 then return stand end
  local best = -INF
  if depth == 0 then
    if stand >= beta then return stand end -- no need to generate the captures
    if stand > alpha then alpha = stand end
    best = stand
  end
  local list = R.moves(pos)
  if depth > 0 and #list == 0 then
    return R.inCheck(pos, pos.side) and -MATE + ply or 0
  end
  list = order(pos, list, depth == 0)
  for i = 1, #list do
    local child = R.copy(pos)
    R.make(child, list[i])
    local v = -search(child, depth - 1, -beta, -alpha, ply + 1)
    if stopped then return 0 end
    if v > best then best = v end
    if v > alpha then alpha = v end
    if alpha >= beta then break end
  end
  return best
end

-- The best moves of the position for its side to move: list, score. Stops
-- at the node cap, keeping the moves of the root moves searched whole.
local function root(pos)
  local best, tied = -INF, {}
  local list = order(pos, R.moves(pos), false)
  for i = 1, #list do
    local child = R.copy(pos)
    R.make(child, list[i])
    -- the window opens one below the best so that equal moves stay exact
    local v = -search(child, 1, -INF, -(best - 1), 1)
    if stopped then break end
    if v > best then best, tied = v, { list[i] }
    elseif v == best then tied[#tied + 1] = list[i] end
  end
  if #tied == 0 then
    -- The cap came inside the first root move: no move has a searched score.
    -- Last resort, the static value of the position after each move.
    best = -INF
    for i = 1, #list do
      local child = R.copy(pos)
      R.make(child, list[i])
      local v = -evaluate(child.board) * child.side
      if v > best then best, tied = v, { list[i] }
      elseif v == best then tied[#tied + 1] = list[i] end
    end
  end
  return tied
end

function E.bot(s, seat, random)
  if s.phase ~= "play" or (seat ~= 1 and seat ~= 2) then return nil end
  local mine = seat == s.white and 1 or -1
  if s.offer == 3 - seat then
    if evaluate(s.board) * mine < LOSING then return { k = "accept" } end
  end
  if s.turn ~= seat then return nil end
  count, cap, stopped = 0, E.BOT_NODES, false
  local pos = R.copy(s)
  local tied = root(pos)
  E.botCount = count
  if not tied[1] then return nil end
  local m = tied[#tied == 1 and 1 or random(1, #tied)]
  return { k = "move", f = m.f, t = m.t, p = m.p }
end
