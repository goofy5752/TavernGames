local _, ns = ...
ns.Engines = ns.Engines or {}

--[[ Табла — rules (numbers are binding; tests check them)
 1. Match: games cycle Обикновена ("std") -> Тапа ("tapa") -> Гюлбара ("gul") -> Обикновена ...;
    the first seat to reach 5 points (E.TARGET) wins the match.
 2. Game score: a win is 1 point; марс (the winner bears off all 15 before the loser has borne off
    any) is 2 points; pinning the mother in Тапа (rule 10) is 2 points. No doubling cube, no
    triple (backgammon) win.
 3. Board: points are numbered 1..24 from each seat's OWN perspective. A seat moves from 24 toward
    1, its home board is 1..6 and it bears off past 1. In a step {from, to}, from = 25 is the bar
    and to = 0 is off. E.abs(var, seat, q) gives the absolute point (seat 1's numbering).
    Std/Тапа: the seats move in opposite directions, seat 2's q is seat 1's 25-q.
    Гюлбара: both move the same way round, seat 2's q is seat 1's (q+11)%24+1 (seat 2's 24 = seat 1's 12).
 4. Dice: system action {k="dice", d={a,b}} at seat 0, values 1..6. E.system answers
    {k="need", r="open"} / {k="need", r="roll", s=seat} when the table needs dice (a hint for the
    host's dice source; "need" itself is never applied).
 5. Opening (game 1 only): one dice action is the opening roll, d[1] = seat 1's die, d[2] = seat
    2's die; a tie rolls again; the higher die starts and then rolls both dice anew (the opening
    dice are not played). opts.first is ignored (the opening roll decides).
 6. Every later game is started (first roll) by the winner of the previous game.
 7. A turn: each die is one step of one checker; a double gives 4 steps of that number. The seat
    must use as many dice as possible; if only one of two different dice can be used, the larger
    one must be used when it can. No playable step -> the only legal move is {k="move", steps={}}.
    A full turn is one action {k="move", steps={{from,to},...}}; apply accepts any order of
    single-die steps that ends in the same position as a legal move.
 8. Bearing off: only when all of the seat's checkers are in its home board (1..6) and none on the
    bar. A die equal to the point bears that checker off; a higher die bears off from the highest
    occupied point only when no checker of the seat stands on a higher point (a pinned checker
    counts); otherwise the die must be played inside the board. A move ends the game as soon as
    the 15th checker is off.
 9. Обикновена: start 2 on 24, 5 on 13, 3 on 8, 5 on 6. A point with 2+ opposing checkers is
    blocked; landing on a single opposing checker hits it to the bar. A seat with checkers on the
    bar must enter them all first (bar -> point 25-die, i.e. the opponent's home board) before any
    other step; if no entry is possible the rest of the roll is lost.
10. Тапа: start 15 on 24. No hitting and no bar. Landing on a single opposing checker pins it
    (тапа): the pinned checker cannot move until every pinning checker has left the point; the
    pinner's own checkers may join it, the pinned side may not land there. 2+ opposing checkers
    block. Pinning the opponent's lone checker on its own 24 (its last checker on the start
    point, "майката") wins the game at once for 2 points; the move ends there and counts as using
    every die. Both mothers can never be pinned together: the first such pin ends the game.
11. Гюлбара: start 15 on 24. No hitting: one opposing checker already blocks a point. No other
    blocking/prime or opening restrictions. Doubles in a seat's first 3 rolls of the game are
    plain doubles (4 steps). From a seat's 4th roll on (E.CASCADE_ROLL) a double d:d cascades:
    4 steps of d, then 4 steps of every higher number up to 6:6, each number one move action of
    the same seat. If a number cannot be fully played, the opponent plays the remainder (the
    unplayed steps of that number, then the higher numbers) with its own checkers, then rolls
    for its own turn; whatever the opponent cannot play of the remainder is lost.
12. A seat that leaves while the match is live loses the match (E.leave).
]]

local E = {
  id = "tabla", minSeats = 2, maxSeats = 2, TARGET = 5, CASCADE_ROLL = 4,
  VARIANTS = { "std", "tapa", "gul" }, options = {},
}
ns.Engines.tabla = E

local START = {
  std = { [24] = 2, [13] = 5, [8] = 3, [6] = 5 },
  tapa = { [24] = 15 },
  gul = { [24] = 15 },
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function zeros() local t = {} for i = 1, 24 do t[i] = 0 end return t end
local function rep(v, n) local t = {} for i = 1, n do t[i] = v end return t end

-- The other seat's own number for the same point (an involution).
local function oppOpposite(q) return 25 - q end
local function oppParallel(q) return (q + 11) % 24 + 1 end
local function oppOf(var) return var == "gul" and oppParallel or oppOpposite end

function E.abs(var, seat, q)
  if seat == 1 then return q end
  return oppOf(var)(q)
end

local function setBoard(s)
  s.var = E.VARIANTS[(s.game - 1) % 3 + 1]
  s.pts, s.pin = { zeros(), zeros() }, { zeros(), zeros() }
  for seat = 1, 2 do
    for q, n in pairs(START[s.var]) do s.pts[seat][q] = n end
  end
  s.bar, s.off, s.rolls = { 0, 0 }, { 0, 0 }, { 0, 0 }
  s.dice, s.left, s.cv, s.xfer = nil, nil, nil, nil
end

function E.new(opts)
  local s = { phase = "open", game = 1, score = { 0, 0 } }
  setBoard(s)
  return s
end

-- Positions (pts/pin/bar/off [+won]) -------------------------------------------------------------

local function copyPos(p)
  local a1, a2, b1, b2 = {}, {}, {}, {}
  local p1, p2, q1, q2 = p.pts[1], p.pts[2], p.pin[1], p.pin[2]
  for i = 1, 24 do a1[i], a2[i], b1[i], b2[i] = p1[i], p2[i], q1[i], q2[i] end
  return { pts = { a1, a2 }, pin = { b1, b2 }, bar = { p.bar[1], p.bar[2] },
           off = { p.off[1], p.off[2] }, won = p.won }
end

local function key(p)
  local t = {}
  for seat = 1, 2 do
    local a, b = p.pts[seat], p.pin[seat]
    for i = 1, 24 do t[#t + 1] = a[i]; t[#t + 1] = b[i] end
    t[#t + 1] = p.bar[seat]; t[#t + 1] = p.off[seat]
  end
  t[#t + 1] = p.won or 0
  return table.concat(t, ",")
end

local function allHome(p, me)
  if p.bar[me] > 0 then return false end
  local mine = p.pts[me]
  for q = 7, 24 do if mine[q] > 0 then return false end end
  return true
end

-- One checker of `me` from own point `from` (25 = bar) by die `d` -> new position, to | nil.
local function step(var, p, me, from, d)
  local op, mine = 3 - me, p.pts[me]
  if from == 25 then
    if p.bar[me] == 0 then return nil end
  else
    if type(from) ~= "number" or from < 1 or from > 24 or from % 1 ~= 0 then return nil end
    if p.bar[me] > 0 or mine[from] == 0 or p.pin[me][from] == 1 then return nil end
  end
  local opp, to, n = oppOf(var), from - d, nil
  if to >= 1 then
    local x = opp(to)
    local on, hit, pin = p.pts[op][x], false, false
    if on > 0 then
      if var == "std" then
        if on > 1 then return nil end
        hit = true
      elseif var == "tapa" then
        if p.pin[op][x] == 1 then -- already pinned by us: join the stack
        elseif on == 1 and mine[to] == 0 then pin = true
        else return nil end
      else
        return nil
      end
    end
    n = copyPos(p)
    n.pts[me][to] = n.pts[me][to] + 1
    if hit then n.pts[op][x] = 0; n.bar[op] = n.bar[op] + 1 end
    if pin then
      n.pin[op][x] = 1
      if x == 24 then n.won = 2 end
    end
  else
    if not allHome(p, me) then return nil end
    if to < 0 then
      for q = from + 1, 6 do if mine[q] > 0 then return nil end end
    end
    n = copyPos(p)
    n.off[me] = n.off[me] + 1
    to = 0
  end
  if from == 25 then
    n.bar[me] = n.bar[me] - 1
  else
    n.pts[me][from] = n.pts[me][from] - 1
    if n.pts[me][from] == 0 then
      local x = opp(from)
      if n.pin[op][x] == 1 then n.pin[op][x] = 0 end
    end
  end
  if not n.won and n.off[me] == 15 then n.won = n.off[op] == 0 and 2 or 1 end
  return n, to
end

local function distinct(rem)
  local seen, out = {}, {}
  for _, d in ipairs(rem) do
    if not seen[d] then seen[d] = true; out[#out + 1] = d end
  end
  table.sort(out, function(a, b) return a > b end)
  return out
end

local function without(rem, d)
  local out, gone = {}, false
  for _, x in ipairs(rem) do
    if x == d and not gone then gone = true else out[#out + 1] = x end
  end
  return out
end

-- Every legal full move for s.turn with dice s.left: list of {p, steps, dice, n}, deduped by the
-- resulting position. n = dice used (a winning move counts as using all of them).
-- Doubles are generated with non-increasing from-points (any order of equal dice reaches the same
-- positions); only a game-winning step (a mother pin) may break that order, since it ends the move.
local function gen(s)
  local me, var, dice = s.turn, s.var, s.left
  local double = true
  for i = 2, #dice do if dice[i] ~= dice[1] then double = false end end
  local leaves, steps, used = {}, {}, {}
  local function rec(p, rem, maxFrom)
    local any = false
    if not p.won and #rem > 0 then
      local lo = p.bar[me] > 0 and 25 or 1
      for _, d in ipairs(distinct(rem)) do
        for from = 25, lo, -1 do
          local n, to = step(var, p, me, from, d)
          if n and double and from > maxFrom and not n.won then n = nil end
          if n then
            any = true
            steps[#steps + 1] = { from, to }; used[#used + 1] = d
            rec(n, without(rem, d), from)
            steps[#steps] = nil; used[#used] = nil
          end
        end
      end
    end
    if not any then
      leaves[#leaves + 1] = { p = p, steps = copy(steps), dice = copy(used),
                              n = p.won and #dice or #steps }
    end
  end
  rec(copyPos(s), dice, 25)

  local maxN = 0
  for _, l in ipairs(leaves) do if l.n > maxN then maxN = l.n end end
  local big
  if not double and maxN == 1 then
    local hi = math.max(dice[1], dice[2])
    for _, l in ipairs(leaves) do
      if l.n == 1 and l.dice[1] == hi then big = hi break end
    end
  end
  local out, seen = {}, {}
  for _, l in ipairs(leaves) do
    if l.n == maxN and (not big or l.dice[1] == big) then
      local k = key(l.p)
      if not seen[k] then seen[k] = l; out[#out + 1] = l end
    end
  end
  return out, seen
end

-- Plays the submitted steps in any die assignment; returns the final position and its legal move.
local function sim(var, p, me, steps, i, rem, legalByKey)
  if i > #steps then
    local l = legalByKey[key(p)]
    if l then return p, l end
    return nil
  end
  if p.won then return nil end
  local st = steps[i]
  if type(st) ~= "table" then return nil end
  local from, to = st[1], st[2]
  if type(from) ~= "number" or type(to) ~= "number" then return nil end
  for _, d in ipairs(distinct(rem)) do
    if from - d == to or (to == 0 and from - d < 0) then
      local n, t = step(var, p, me, from, d)
      if n and t == to then
        local r, l = sim(var, n, me, steps, i + 1, without(rem, d), legalByKey)
        if r then return r, l end
      end
    end
  end
  return nil
end

-- Turn flow -----------------------------------------------------------------------------------

local function endGame(s, w, points)
  s.score[w] = s.score[w] + points
  s.gw, s.gp = w, points
  s.turn, s.left, s.cv, s.xfer = nil, nil, nil, nil
  if s.score[w] >= E.TARGET then
    s.phase, s.winner = "match", w
  else
    s.phase = "game"
  end
end

local function afterMove(s, used)
  local me = s.turn
  if s.cv then
    local full = used >= #s.left
    if full and s.cv < 6 then
      s.cv = s.cv + 1
      s.left = rep(s.cv, 4)
      return
    end
    if not full and not s.xfer then
      s.left = rep(s.cv, #s.left - used)
      s.turn, s.xfer = 3 - me, true
      return
    end
    -- cascade over: the receiver of a remainder now rolls its own turn
    local nextSeat = s.xfer and me or 3 - me
    s.cv, s.xfer, s.left = nil, nil, nil
    s.turn, s.phase = nextSeat, "roll"
    return
  end
  s.left = nil
  s.turn, s.phase = 3 - me, "roll"
end

local function die(x) return type(x) == "number" and x >= 1 and x <= 6 and x % 1 == 0 end

function E.apply(s, seat, a)
  if type(a) ~= "table" then return nil, "action" end
  local k = a.k
  if k == "move" then
    if seat ~= 1 and seat ~= 2 then return nil, "seat" end
    if s.phase ~= "move" then return nil, "phase" end
    if s.turn ~= seat then return nil, "turn" end
    if type(a.steps) ~= "table" then return nil, "move" end
    local _, byKey = gen(s)
    local p, l = sim(s.var, copyPos(s), seat, a.steps, 1, s.left, byKey)
    if not p then return nil, "move" end
    s.pts, s.pin, s.bar, s.off = p.pts, p.pin, p.bar, p.off
    if p.won then
      endGame(s, seat, p.won)
    else
      afterMove(s, l.n)
    end
    return true
  elseif k == "dice" then
    if seat ~= 0 then return nil, "seat" end
    if s.phase ~= "open" and s.phase ~= "roll" then return nil, "phase" end
    local d = a.d
    if type(d) ~= "table" or not die(d[1]) or not die(d[2]) then return nil, "dice" end
    local x, y = d[1], d[2]
    s.dice = { x, y }
    if s.phase == "open" then
      if x ~= y then s.turn, s.phase = x > y and 1 or 2, "roll" end
      return true
    end
    local me = s.turn
    s.rolls[me] = s.rolls[me] + 1
    if x == y then
      s.left = rep(x, 4)
      if s.var == "gul" and s.rolls[me] >= E.CASCADE_ROLL then s.cv, s.xfer = x, false end
    else
      s.left = { x, y }
    end
    s.phase = "move"
    return true
  elseif k == "next" then
    if seat ~= 0 then return nil, "seat" end
    if s.phase ~= "game" then return nil, "phase" end
    local w = s.gw
    s.game = s.game + 1
    setBoard(s)
    s.gw, s.gp = nil, nil
    s.turn, s.phase = w, "roll"
    return true
  end
  return nil, "action"
end

function E.legal(s, seat)
  local out = {}
  if s.phase == "move" and s.turn == seat then
    for _, l in ipairs((gen(s))) do out[#out + 1] = { k = "move", steps = copy(l.steps) } end
  end
  return out
end

function E.auto(s, seat)
  if s.phase ~= "move" or s.turn ~= seat then return nil end
  return { k = "move", steps = copy(gen(s)[1].steps) }
end

function E.system(s)
  if s.phase == "open" then return { k = "need", r = "open" }, 0 end
  if s.phase == "roll" then return { k = "need", r = "roll", s = s.turn }, 0 end
  if s.phase == "game" then return { k = "next" }, 3 end
end

function E.over(s) return s.phase == "match" end

function E.result(s)
  if s.phase ~= "match" then return nil end
  return { winners = { s.winner }, losers = { 3 - s.winner } }
end

function E.leave(s, seat)
  if s.phase == "match" or (seat ~= 1 and seat ~= 2) then return end
  s.phase, s.winner, s.quit = "match", 3 - seat, seat
  s.turn, s.left, s.cv, s.xfer = nil, nil, nil, nil
end

function E.view(s) return copy(s) end
function E.snapshot(s) return copy(s) end
function E.restore(t) return copy(t) end

return E
