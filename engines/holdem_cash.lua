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
]==]
local _, ns = ...

local HC = { CHIP = 100, MIN_BB = 40, MAX_BB = 100 }
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
