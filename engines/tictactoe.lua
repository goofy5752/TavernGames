local _, ns = ...
ns.Engines = ns.Engines or {}

local E = { id = "ttt", minSeats = 2, maxSeats = 2, WINS = 3 }
ns.Engines.ttt = E

local LINES = {
  {1,2,3}, {4,5,6}, {7,8,9}, {1,4,7}, {2,5,8}, {3,6,9}, {1,5,9}, {3,5,7},
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function emptyBoard() return {0,0,0,0,0,0,0,0,0} end

function E.new(opts)
  local first = (opts and opts.first) == 2 and 2 or 1
  return {
    board = emptyBoard(), turn = first, score = {0, 0}, round = 1, first = first,
    phase = "play", line = nil, winner = nil, draw = false, rematch = {false, false},
  }
end

local function findLine(board)
  for _, l in ipairs(LINES) do
    local v = board[l[1]]
    if v ~= 0 and v == board[l[2]] and v == board[l[3]] then return l, v end
  end
end

function E.apply(s, seat, a)
  if type(a) ~= "table" then return nil, "action" end
  local k = a.k
  if k == "mark" then
    if seat ~= 1 and seat ~= 2 then return nil, "seat" end
    if s.phase ~= "play" then return nil, "phase" end
    if s.turn ~= seat then return nil, "turn" end
    local c = a.c
    if type(c) ~= "number" or c < 1 or c > 9 or c % 1 ~= 0 or s.board[c] ~= 0 then
      return nil, "cell"
    end
    s.board[c] = seat
    local line, who = findLine(s.board)
    if line then
      s.line = { line[1], line[2], line[3] }
      s.score[who] = s.score[who] + 1
      s.turn = nil
      if s.score[who] >= E.WINS then
        s.phase, s.winner = "match", who
      else
        s.phase = "round"
      end
    else
      local full = true
      for i = 1, 9 do if s.board[i] == 0 then full = false break end end
      if full then
        s.draw, s.turn, s.phase = true, nil, "round"
      else
        s.turn = 3 - seat
      end
    end
    return true
  elseif k == "next" then
    if seat ~= 0 then return nil, "seat" end
    if s.phase ~= "round" then return nil, "phase" end
    s.board = emptyBoard()
    s.line, s.draw = nil, false
    s.first = 3 - s.first
    s.turn = s.first
    s.round = s.round + 1
    s.phase = "play"
    return true
  elseif k == "rematch" then
    if seat ~= 1 and seat ~= 2 then return nil, "seat" end
    if s.phase ~= "match" then return nil, "phase" end
    s.rematch[seat] = true
    if s.rematch[1] and s.rematch[2] then
      -- first flips every round, so the match starter is first flipped (round-1) times
      local starter = s.first
      if (s.round - 1) % 2 == 1 then starter = 3 - starter end
      s.board = emptyBoard()
      s.score = {0, 0}
      s.round = 1
      s.first = 3 - starter
      s.turn = s.first
      s.line, s.winner, s.draw = nil, nil, false
      s.rematch = {false, false}
      s.phase = "play"
    end
    return true
  end
  return nil, "action"
end

function E.legal(s, seat)
  local out = {}
  if s.phase == "play" and s.turn == seat then
    for c = 1, 9 do
      if s.board[c] == 0 then out[#out + 1] = { k = "mark", c = c } end
    end
  end
  return out
end

function E.auto(s, seat)
  if s.phase ~= "play" or s.turn ~= seat then return nil end
  for c = 1, 9 do
    if s.board[c] == 0 then return { k = "mark", c = c } end
  end
end

function E.system(s)
  if s.phase == "round" then return { k = "next" }, 3 end
end

-- The match outcome: {winners, losers} once a player has won the match.
function E.result(s)
  if s.phase == "match" then return { winners = { s.winner }, losers = { 3 - s.winner } } end
  return nil
end

function E.snapshot(s) return copy(s) end
function E.restore(t) return copy(t) end

return E
