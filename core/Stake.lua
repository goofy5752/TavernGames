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

-- Does game `id` take a stake `c` -> bool. A cash game (engine.stakeOf:
-- Холдем) at the table options `opt`, when given, only its own stake of them.
function Stake.allowed(id, c, opt)
  local engine = ns.Games.engine(id)
  if not (Stake.valid(c) and engine ~= nil and engine.stakes == true) then return false end
  return opt == nil or not engine.stakeOf or c == engine.stakeOf(opt)
end

-- Gold and silver -> copper, or nil when it is not a stake.
function Stake.fromParts(gold, silver)
  if not (whole(gold) and whole(silver)) or gold < 0 or silver < 0 or silver >= 100 then return nil end
  local c = gold * 10000 + silver * 100
  return Stake.valid(c) and c or nil
end

-- The most a player of game `id` can lose at a table of stake `copper`:
-- Death Roll pays everyone else, a team game (engine.teams) two stakes (a
-- leaver pays both opponents), a cash game (engine.cashGame, whose stake is
-- its big blind) one full buy-in of 100 big blinds (more only by buying
-- again: the question says so), every other game one stake.
function Stake.worst(id, copper)
  if id == "deathroll" then return copper * (ns.Engines.deathroll.maxSeats - 1) end
  local engine = ns.Games.engine(id)
  if engine and engine.cashGame then return copper * 100 end
  if engine and engine.teams then return copper * 2 end
  return copper
end

---------------------------------------------------------------------------
-- The stake I accepted (Member.adopt checks every snapshot that seats me)
---------------------------------------------------------------------------

-- A staked seat is mine only through my own note {tid, sk, tn, o} in db.stakeSat
-- (sk nil: for fun; tn: the turn length of the table I accepted, kept by
-- Member.adopt; o: at a game with options the table options I accepted,
-- resolved for a staked table (Stake.options), kept by Member.adopt the same
-- way). It is written when I send a SIT with that sk to that table
-- (Session.request) or open it (Session.open), and by Stake.accept;
-- Stake.ask writes {tid} with no stake ("asked here, nothing accepted": a
-- /reload while asked finds it and gives the seat up);
-- it is cleared when I stand (Client:stand), when a SIT of mine is refused
-- and when I leave the table (Stake.watch). A logout keeps it (Session.stop
-- leaves nobody), so it outlives a /reload only while I am seated.
-- client.stakeNoted: the note was written or cleared in this run of the
-- client, so no note for a table means I accepted no stake there (only the
-- note loaded at login can be missing or stale, after a crash).
function Stake.note(client, tid, sk, tn, o)
  client.env.db.stakeSat = { tid = tid, sk = sk, tn = tn, o = ns.Util.copy(o) }
  client.stakeNoted = true
end

-- The options `o` of a staked table of game `id` as my note keeps them -> a
-- new table with every default filled in (never a lobby record's raw `o`,
-- which may lack one), or nil: a game without options (Морски шах; Сантасе,
-- Белот and Табла have `options = {}`) keeps none.
function Stake.options(id, o)
  local engine = ns.Games.engine(id)
  return engine and engine.options and #engine.options > 0 and ns.Games.resolve(id, o, true) or nil
end

function Stake.clear(client)
  client.env.db.stakeSat, client.env.db.stakeLog = nil, nil -- and what I sent there (core/StakesWatch.lua)
  client.stakeNoted = true
end

-- Do I hold a seat at my table s -> bool (a seat the host stood up is lost).
local function seated(client, s)
  return s.mySeat ~= nil and s.seats[s.mySeat] == client.env.me
end

-- No game runs at my table (open, aborted, or the game is over).
local function over(s)
  return s.status ~= "live" or s:gameOver()
end
Stake.over = over

-- The asked seat goes: I stand up, "refused"(tid, "stake").
function Stake.standUp(client, s)
  local tid = s.tid
  s.stakeAsk = nil
  client:stand(true) -- at once, never a cash-out (core/CashOut.lua)
  client.events:emit("refused", tid, "stake")
end

-- Member.adopt seated me at a staked table without a note of mine for it (a
-- crash, or a login with a stale note): the seat is kept for the running game
-- only (s.stakeGame, its s.gameNo: Session:noteResult), "stakeAsk"(tid, sk)
-- asks me, and unless I accept (Stake.accept) the game's end, the next game's
-- start (Member's onEvent), a snapshot of anything but that game
-- (Member.adopt) or a call to host the table (core/Succession.lua) stands me
-- up ("refused" "stake"). No game running: at once. Meanwhile my note says
-- "no stake accepted here": after a /reload the seat is refused, not asked
-- about again in what may be the next game.
function Stake.ask(client)
  local s = client.session
  s.stakeAsk, s.stakeGame = true, s.gameNo
  Stake.note(client, s.tid, nil)
  if over(s) then return Stake.standUp(client, s) end
  client.events:emit("stakeAsk", s.tid, s.stake)
end

-- I accept the stake I was asked about -> true | nil (nothing asked).
function Stake.accept(client)
  local s = client.session
  if not (s and s.stakeAsk and seated(client, s)) then return nil end
  s.stakeAsk = nil
  Stake.note(client, s.tid, s.stake, s.turn, Stake.options(s.game, s.opt))
  return true
end

-- Client.new. "session"(nil), I left: the note goes. An asked seat I lost
-- ends the question at once; one still unaccepted when the game is over, or
-- when the game I hold is not the one I was asked in any more, stands me up,
-- after the "session" handlers of that change have run.
-- "refused"(tid) of a SIT of mine, I hold no seat there: the note goes.
function Stake.watch(client)
  client:on("session", function(s)
    if not s then return Stake.clear(client) end
    if not s.stakeAsk then return end
    if not seated(client, s) then s.stakeAsk = nil; return end
    client:after(0, function()
      if client.session == s and s.stakeAsk and (over(s) or s.gameNo ~= s.stakeGame) then Stake.standUp(client, s) end
    end)
  end)
  client:on("refused", function(tid)
    local note, s = client.env.db.stakeSat, client.session
    if type(note) ~= "table" or note.tid ~= tid then return end
    if s and s.tid == tid and seated(client, s) then return end
    Stake.clear(client)
  end)
end
