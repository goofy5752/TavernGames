local _, ns = ...

-- The stake of a table: integer copper, whole silver, from STAKE_MIN to
-- STAKE_MAX. Only a game whose engine has `stakes = true` takes one. Engines
-- load after core/, so they are looked up at call time only.
local Stake = {}
ns.Stake = Stake

local C = ns.Const
Stake.MIN, Stake.MAX = C.STAKE_MIN, C.STAKE_MAX

local function whole(n)
  return type(n) == "number" and n == math.floor(n)
end

-- Is `c` a stake -> bool.
function Stake.valid(c)
  return whole(c) and c % 100 == 0 and c >= Stake.MIN and c <= Stake.MAX
end

-- Does game `id` take a stake `c` -> bool.
function Stake.allowed(id, c)
  local engine = ns.Games.engine(id)
  return Stake.valid(c) and engine ~= nil and engine.stakes == true
end

-- Gold and silver -> copper, or nil when it is not a stake.
function Stake.fromParts(gold, silver)
  if not (whole(gold) and whole(silver)) or gold < 0 or silver < 0 or silver >= 100 then return nil end
  local c = gold * 10000 + silver * 100
  return Stake.valid(c) and c or nil
end

-- The most a player of game `id` can lose at a table of stake `copper`:
-- Death Roll pays everyone else, every other game one stake.
function Stake.worst(id, copper)
  if id == "deathroll" then return copper * (ns.Engines.deathroll.maxSeats - 1) end
  return copper
end
