local _, ns = ...
-- Chess: the engine contract over ns.ChessRules (the moves) and ns.ChessSan
-- (the notation). The position fields (board side castle ep half full) sit
-- in the state itself, so the state is a position for the rules. Time is in
-- tenths of a second; `dt`, the time the mover thought, comes with the event
-- (core/Clock.lua measures it on the host), never inside the action.
ns.Engines = ns.Engines or {}

local E = { id = "chess", minSeats = 2, maxSeats = 2, stakes = true, again = true, clock = true,
  firstSeat = 2, INC = 50 }
ns.Engines.chess = E

E.options = {
  { id = "clock", at = "fun",   choices = { 5, 10, 15, 30, 0 }, default = 10 }, -- 0: no limit
  { id = "clock", at = "stake", choices = { 5, 10, 15, 30 },    default = 10 },
}

local MINUTES = 10  -- the clock when the table names none
local WAIT = 3      -- own moves after a declined offer before that seat may offer again
local PROMO = { q = true, r = true, b = true, n = true }

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function whole(v, lo, hi)
  return type(v) == "number" and v >= lo and v <= hi and v % 1 == 0
end

-- The colour a seat plays: 1 white, -1 black.
local function colour(s, seat) return seat == s.white and 1 or -1 end

-- opts.first: the seat that plays white (E.firstSeat when missing);
-- opts.opt.clock: minutes a player, 0 for no limit (missing: MINUTES).
function E.new(opts)
  opts = opts or {}
  local white = (opts.first == 1 or opts.first == 2) and opts.first or E.firstSeat
  local minutes = opts.opt and opts.opt.clock
  if not whole(minutes, 0, math.huge) then minutes = MINUTES end
  local base = minutes > 0 and minutes * 600 or nil
  local R = ns.ChessRules
  local s = R.start()
  s.white, s.turn, s.phase = white, white, "play"
  s.seen = { [R.key(s)] = 1 } -- the start counts for the threefold repetition
  s.moves, s.taken, s.wait = {}, { {}, {} }, { 0, 0 }
  s.base, s.clock = base, base and { base, base } or nil
  return s
end

-- The game ends: winner a seat or nil (a draw), reason one of the codes.
local function finish(s, winner, reason, left)
  s.phase, s.turn, s.offer = "over", nil, nil
  s.result = { winner = winner, reason = reason, left = left }
end

-- The legal move of the action, or nil and the code.
local function lookup(s, a)
  local R = ns.ChessRules
  if not whole(a.f, 1, 64) or not whole(a.t, 1, 64) then return nil, "move" end
  local promotion = false
  for _, m in ipairs(R.moves(s)) do
    if m.f == a.f and m.t == a.t then
      if m.p == nil then
        if a.p ~= nil then return nil, "move" end
        return m
      end
      promotion = true
      if m.p == a.p then return m end
    end
  end
  if promotion then return nil, "promo" end
  return nil, "move"
end

local function move(s, seat, a, dt)
  if s.turn ~= seat then return nil, "turn" end
  if dt ~= nil and not whole(dt, 0, math.huge) then return nil, "dt" end
  local m, code = lookup(s, a)
  if not m then return nil, code end
  local left = s.clock and s.clock[seat] - (dt or 0)
  if left and left <= 0 then return nil, "time" end
  -- Accepted: nothing below refuses.
  local R = ns.ChessRules
  if left then s.clock[seat] = left + E.INC end
  local before = R.copy(s)
  local cap = R.make(s, m)
  s.moves[#s.moves + 1] = { f = m.f, t = m.t, p = m.p, san = ns.ChessSan.of(before, m, s), dt = dt }
  if cap ~= 0 then s.taken[seat][#s.taken[seat] + 1] = cap end
  if s.half == 0 then s.seen = {} end
  local key = R.key(s)
  s.seen[key] = (s.seen[key] or 0) + 1
  local other = 3 - seat
  if s.offer == other then s.offer, s.wait[other] = nil, WAIT end -- a move declines
  if s.wait[seat] > 0 then s.wait[seat] = s.wait[seat] - 1 end
  s.turn = other
  local status = R.status(s)
  if status == "mate" then finish(s, seat, "mate")
  elseif status == "stalemate" then finish(s, nil, "stalemate")
  elseif R.insufficient(s) then finish(s, nil, "material")
  elseif s.seen[key] >= 3 then finish(s, nil, "repetition")
  elseif s.half >= 100 then finish(s, nil, "fifty")
  end
  return true
end

local ACTIONS = {
  move = move,
  resign = function(s, seat)
    finish(s, 3 - seat, "resign")
    return true
  end,
  offer = function(s, seat)
    if s.turn ~= seat then return nil, "turn" end
    if s.offer or s.wait[seat] ~= 0 then return nil, "offer" end
    s.offer = seat
    return true
  end,
  accept = function(s, seat)
    if not s.offer or s.offer == seat then return nil, "offer" end
    finish(s, nil, "agreed")
    return true
  end,
  decline = function(s, seat)
    if not s.offer or s.offer == seat then return nil, "offer" end
    s.wait[s.offer], s.offer = WAIT, nil
    return true
  end,
  -- seat: the flagged seat; its clock shows 0. Only a bare king on the other side makes it a draw.
  flag = function(s, seat)
    if s.turn ~= seat then return nil, "turn" end
    if not s.clock then return nil, "clock" end
    s.clock[seat] = 0
    local other = 3 - seat
    if ns.ChessRules.bare(s, colour(s, other)) then finish(s, nil, "flagdraw")
    else finish(s, other, "flag") end
    return true
  end,
  -- By the seat waiting for the other's flag; once per ply. Changes nothing
  -- else: the host answers with the flag (core/Clock.lua).
  claim = function(s, seat)
    if s.turn == seat then return nil, "turn" end
    if not s.clock then return nil, "clock" end
    if s.claimed == #s.moves then return nil, "claim" end
    s.claimed = #s.moves
    return true
  end,
}

-- seat 1 or 2; dt: whole tenths the mover thought (moves only; nil when the
-- event carried none). A refusal changes nothing.
function E.apply(s, seat, a, dt)
  if type(a) ~= "table" or type(a.k) ~= "string" or not ACTIONS[a.k] then return nil, "action" end
  if seat ~= 1 and seat ~= 2 then return nil, "seat" end
  if s.phase ~= "play" then return nil, "phase" end
  return ACTIONS[a.k](s, seat, a, dt)
end

function E.legal(s, seat)
  local out = {}
  if s.phase == "play" and s.turn == seat then
    for _, m in ipairs(ns.ChessRules.moves(s)) do out[#out + 1] = { k = "move", f = m.f, t = m.t, p = m.p } end
  end
  return out
end

-- The action the table timer plays when the seat on turn has no time left.
function E.auto(s, seat)
  if s.phase == "play" and s.clock and s.turn == seat then return { k = "flag" } end
  return nil
end

function E.system() end

function E.over(s) return s.phase == "over" end

function E.result(s)
  local r = s.phase == "over" and s.result
  if not r then return nil end
  if r.winner then return { winners = { r.winner }, losers = { 3 - r.winner }, left = r.left } end
  return { winners = {}, losers = {} }
end

function E.leave(s, seat)
  if s.phase == "play" and (seat == 1 or seat == 2) then finish(s, 3 - seat, "left", seat) end
end

-- White goes to the seat that played black (the colours follow the seats).
function E.nextFirst(prev, occupied)
  if prev and (prev.white == 1 or prev.white == 2) then return 3 - prev.white end
  return nil
end

function E.snapshot(s) return copy(s) end

-- A deep copy. An en passant square the side to move cannot have (white to
-- move: rank 6, black: rank 3) only comes from a forged snapshot: dropped.
function E.restore(t)
  local s = copy(t)
  local lo = s.side == 1 and 41 or 17
  if s.ep ~= nil and not whole(s.ep, lo, lo + 7) then s.ep = nil end
  return s
end

return E
