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

---------------------------------------------------------------------------
-- The stake I accepted (Member.adopt checks every snapshot that seats me)
---------------------------------------------------------------------------

-- Notes that I accept stake `sk` (nil: for fun) at table `tid`: db.stakeSat,
-- written by my SIT (Session.request), my own table (Session.open) and
-- Stake.accept. client.stakeNoted: a note was written in this run of the
-- client, so a note of another table means I accepted nothing here (only a
-- note loaded at login can be stale, after a crash).
function Stake.note(client, tid, sk)
  client.env.db.stakeSat = { tid = tid, sk = sk }
  client.stakeNoted = true
end

-- No game runs at my table (open, aborted, or the game is over).
local function over(s)
  return s.status ~= "live" or s:gameOver()
end

local function standUp(client, s)
  local tid = s.tid
  s.stakeAsk = nil
  client:stand()
  client.events:emit("refused", tid, "stake")
end

-- Member.adopt seated me at a staked table without a note of mine for it (a
-- crash, or a login with a stale note): the seat is kept for the running game
-- only, "stakeAsk"(tid, sk) asks me, and unless I accept (Stake.accept) the
-- game's end stands me up ("refused" "stake"). No game running: at once.
function Stake.ask(client)
  local s = client.session
  s.stakeAsk = true
  if over(s) then return standUp(client, s) end
  client.events:emit("stakeAsk", s.tid, s.stake)
end

-- I accept the stake I was asked about -> true | nil (nothing asked).
function Stake.accept(client)
  local s = client.session
  if not (s and s.stakeAsk and s.mySeat) then return nil end
  s.stakeAsk = nil
  Stake.note(client, s.tid, s.stake)
  return true
end

-- Client.new: an asked stake still unaccepted when the game is over stands me
-- up, after the "session" handlers of that change have run.
function Stake.watch(client)
  client:on("session", function(s)
    if not (s and s.stakeAsk) then return end
    client:after(0, function()
      if client.session ~= s or not s.stakeAsk then return end
      if not s.mySeat then s.stakeAsk = nil elseif over(s) then standUp(client, s) end
    end)
  end)
end
