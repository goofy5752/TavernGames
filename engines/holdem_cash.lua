--[==[ Hold'em for real gold: who took how many chips from whom (pure Lua 5.1).

Used by engines/holdem.lua only at a staked table (opts.staked): the state then carries `cash`, the
pairwise matrix took[w][j] = chips seat w took from seat j over the game. Nothing here exists at a fun
table.

 - One chip is one silver (CHIP copper); a buy-in is MIN_BB to MAX_BB big blinds.
 - A pot of a finished hand carries `from` = {[seat] = chips of that seat in the pot}; an uncalled layer is
   in no pot. attribute(pots) splits each pot among its winners, in the pot's `winners` order:
   a winner's own chips come back to it; every other contributor j, ascending by seat, gives
   q = floor(from[j] / #winners) to each winner, and its remaining from[j] - q * #winners chips go one each
   to the winners round-robin, the pointer starting at the pot's first winner and running on through all
   of the pot's contributors. So each winner takes exactly what finish pays it less its own chips, the odd
   chips to the same winners, and for every seat the sum of its pair nets is won - contributed.
 - A voided hand is never attributed (it moves no chip).
 - A seat sits with 0 chips and sits out (seat(who, back)) until it buys; range(s, seat) is what buy takes and
   names what it refuses ("seat", "phase", "hand", "rebuy", "full"); see engines/holdem.lua rule 20.
 - settle(s, seat) writes the seat's out record: every pair of it with another occupied seat, its row and
   column taken out of took, the other seat's `cleared` moved by that pair, so that for every occupied seat
   sum over occupied j of net(i, j) == chips - bought - cleared. The names are the engine's own `who`.
]==]
local _, ns = ...

local HC = { CHIP = 100, MIN_BB = 40, MAX_BB = 100 }
local CHAIRS = 9
ns.HoldemCash = HC

function HC.new(rebuy)
  return { rebuy = rebuy, took = {}, outN = 0, outs = {}, left = {} }
end

local function credit(took, w, j, x)
  if x <= 0 then return end
  local row = took[w]
  if not row then row = {}; took[w] = row end
  row[j] = (row[j] or 0) + x
end

-- took[w][j] = chips winner w took from seat j in this hand (j ~= w; zero entries absent)
function HC.attribute(pots)
  local took = {}
  for _, pot in ipairs(pots) do
    local W, from, isW = pot.winners, pot.from or {}, {}
    for _, w in ipairs(W) do isW[w] = true end
    local js = {}
    for j in pairs(from) do if not isW[j] then js[#js + 1] = j end end
    table.sort(js)
    local n, ptr = #W, 1
    for _, j in ipairs(js) do
      local q = math.floor(from[j] / n)
      for _, w in ipairs(W) do credit(took, w, j, q) end
      for _ = 1, from[j] - q * n do
        credit(took, W[ptr], j, 1)
        ptr = ptr % n + 1
      end
    end
  end
  return took
end

-- adds a hand's took into the game's matrix
function HC.add(cash, took)
  for w, row in pairs(took) do
    for j, x in pairs(row) do credit(cash.took, w, j, x) end
  end
end

-- chips a took from b less chips b took from a (positive: b owes a)
function HC.net(cash, a, b)
  local t = cash.took
  return (t[a] and t[a][b] or 0) - (t[b] and t[b][a] or 0)
end

-- ------------------------------------------------------------------ the seats of a staked table

-- a staked seat: no chips, sitting out until its own buy; back = the chips `who` left this game with
function HC.seat(who, back)
  return { chips = 0, out = true, leaving = false, who = who, bought = 0, cleared = 0, back = back }
end

local function running(s)
  local ph = s.phase
  return ph == "deal" or ph == "bet" or ph == "street" or ph == "showdown"
end

-- the seat is dealt into the running hand (a leaving chair is the leaver's until the hand ends)
local function dealtIn(s, seat)
  local p = s.p[seat]
  return running(s) and (s.seats[seat].leaving or (p ~= nil and not p.gone))
end

-- the chips the seat may buy now: lo, hi | nil, code
function HC.range(s, seat)
  local st = s.seats[seat]
  if not st then return nil, "seat" end
  if s.closing then return nil, "phase" end
  if dealtIn(s, seat) then return nil, "hand" end
  local mode, c = s.cash.rebuy, st.chips
  local min, max = HC.MIN_BB * s.bb, HC.MAX_BB * s.bb
  if st.bought == 0 then
    if st.back == 0 and mode == "none" then return nil, "rebuy" end
    return math.max(min, math.min(st.back or 0, max)), max
  end
  if mode == "none" or (mode == "bust" and c > 0) then return nil, "rebuy" end
  if c == 0 then return min, max end
  if c < max then return 1, max - c end
  return nil, "full"
end

function HC.buy(s, seat, n)
  local lo, hi = HC.range(s, seat)
  if not lo then return nil, hi end
  if type(n) ~= "number" or n % 1 ~= 0 or n < lo or n > hi then return nil, "amount" end
  local st = s.seats[seat]
  st.chips, st.bought, st.out = st.chips + n, st.bought + n, false
  return true
end

-- the out record of a seat with bought > 0, before its chair empties or changes hands
function HC.settle(s, seat)
  local cash, st = s.cash, s.seats[seat]
  local net, names = {}, {}
  for j = 1, CHAIRS do
    local o = s.seats[j]
    local n = j ~= seat and o and HC.net(cash, seat, j) or 0
    if n ~= 0 then net[j], names[j], o.cleared = n, o.who, o.cleared - n end
  end
  cash.took[seat] = nil
  for w, row in pairs(cash.took) do
    row[seat] = nil
    if next(row) == nil then cash.took[w] = nil end
  end
  if st.who then cash.left[st.who] = st.chips end
  cash.outN = cash.outN + 1
  local rec = { n = cash.outN, seat = seat, who = st.who, chips = st.chips, bought = st.bought, net = net, names = names }
  cash.outs[#cash.outs + 1] = rec
  return rec
end

-- settled, and seated on: its chips go back to its name
local function out(s, seat)
  local st = s.seats[seat]
  HC.settle(s, seat)
  st.back, st.chips, st.out, st.bought, st.cleared = st.chips, 0, true, 0, 0
end

function HC.cashout(s, seat)
  local st = s.seats[seat]
  if not st then return nil, "seat" end
  if dealtIn(s, seat) then return nil, "hand" end
  if st.bought == 0 then return nil, "seat" end
  out(s, seat)
  return true
end

-- the game is closed: every seat that bought, ascending, as a cashout
function HC.close(s)
  for i = 1, CHAIRS do
    local st = s.seats[i]
    if st and st.bought > 0 then out(s, i) end
  end
end
