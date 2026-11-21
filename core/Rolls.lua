local _, ns = ...

-- Server rolls for the games whose engine lists the extension "rolls" (Death
-- Roll). The trust model: a roll counts as "seen" only when the host itself saw
-- it in chat; a member's own sighting reaches the host as a claim (ACT{k="roll",
-- n, max}), which the host takes after ROLL_CLAIM_WAIT unless it sees the roll
-- first; a client without RandomRoll, or its automatic move (playAuto), asks the
-- table (src "ask", the host rolls with env.random), and the turn timer rolls
-- for a player who does not (src "timeout"). Every client logs its sightings
-- and cross-checks each "seen" or "claim" entry of the game against them.
--
-- A staked game (state.staked) takes only what the host saw: no claim, no
-- ask and no timeout roll (engines/deathroll.lua); a member's own roll the
-- host has not played within ROLL_CLAIM_WAIT + ROLL_VERIFY_WAIT is unheard
-- (the UI says: stay in the group and roll again). Rolls.audit sums up what my
-- client saw of the game's rolls, for its note (core/Stakes.lua).
--
-- Session fields (local, never sent):
--   rollLog     sightings {seat, n, max, at, own}, newest last, at most ROLL_LOG
--               (own: the line was my own roll, shown as env.me)
--   rollCheck   index in state.rolls -> "ok" | "unseen" | "mismatch"
--   rollNotMine index -> true: a roll of my seat at a staked table that my
--               client did not make (no own sighting ROLL_VERIFY_WAIT after it)
--   rollPending index -> true: the verdict of that roll is still to come
--   rollFolded  the records of the games a snapshot replaced while they ran
--               here (staked): their findings stay with the running game
--   rolling     {seen = bool} while my roll is under way (seen: it showed up in chat)
--   rollStuck   true when my server roll never showed up (the UI says: type /roll)
--   rollUnheard true when the host of a staked game never played my seen roll
--   myRoll      {n, max}: my own roll seen on my current turn at its max,
--               while my own client saw me in my host's group (Rolls.withHost)
--   rollHost    the host whose table this is to Rolls (staked: only another
--               name is a host change, never the same host at a new epoch)
--   claim       {seat, n, max}: the member's claim the host holds (host only)
-- All of them start empty with every new game (the start event, or a snapshot of
-- another game than the one I had); a host change drops `rolling` and `claim`.
-- rollCheck, rollNotMine, rollPending and rollFolded are the game's audit
-- record: a verdict that comes after my session ended or the game was
-- replaced is still written into it, and at a staked table the record of a
-- game an event ended is kept as client.rollAudits[tid .. "/" .. q] (the q of
-- that event; Rolls.auditOf, the last AUDITS_KEPT), whatever comes next.
local Rolls = {}
ns.Rolls = Rolls

local C = ns.Const
local Session = ns.Session
local Names = ns.Names

local AUDITS_KEPT = 20

local function integer(n)
  return type(n) == "number" and n % 1 == 0
end

local function usesRolls(s)
  local ext = s:engine().ext or {}
  for i = 1, #ext do
    if ext[i] == "rolls" then return true end
  end
  return false
end

-- The only seat whose name `matches` the shown name; nil when none or several.
function Rolls.seatFor(seats, shown)
  local found = nil
  for i = 1, #seats do
    if seats[i] and Names.matches(seats[i], shown) then
      if found then return nil end
      found = i
    end
  end
  return found
end

-- What this client saw of state.rolls[index]: "ok", "unseen", "mismatch" or nil
-- (no verdict: an "ask" or "timeout" entry, or not checked yet).
function Rolls.check(session, index)
  return session.rollCheck and session.rollCheck[index]
end

-- The verdict on a recorded roll from my log of its game: "ok" when I saw the
-- same seat, max and n. Otherwise nil, or with `final` "mismatch" (I saw that
-- seat roll that max with another n) or "unseen".
local function verdict(log, entry, final)
  local other = false
  log = log or {}
  for i = 1, #log do
    local g = log[i]
    if g.seat == entry.seat and g.max == entry.max then
      if g.n == entry.n then return "ok" end
      other = true
    end
  end
  if not final then return nil end
  return other and "mismatch" or "unseen"
end

local function setVerdict(s, index, v)
  if v and s.rollCheck[index] ~= v then
    s.rollCheck[index] = v
    Session.emit(s.client)
  end
end

local function checked(entry)
  return entry.src == "seen" or entry.src == "claim"
end

-- A new sighting turns every recorded roll it confirms into "ok".
local function recheck(s)
  local rolls = s.rollCheck and s.state and s.state.rolls or {}
  for i = 1, #rolls do
    if checked(rolls[i]) and s.rollCheck[i] ~= "ok" and verdict(s.rollLog, rolls[i], false) then
      setVerdict(s, i, "ok")
    end
  end
end

-- Did my client see itself roll `entry` (an own sighting of that n and max)?
local function ownSeen(log, entry)
  log = log or {}
  for i = 1, #log do
    local g = log[i]
    if g.own and g.n == entry.n and g.max == entry.max then return true end
  end
  return false
end

-- The roll state.rolls[index] was just applied: "ok" at once when my log
-- confirms it, else the final verdict ROLL_VERIFY_WAIT later, pending until
-- then. At a staked table a roll of my seat with no own sighting by then is not
-- mine (rollNotMine: a namesake's line, or one I never made). The verdict goes
-- into the record of the roll's game even when my session ended or the game
-- was replaced meanwhile (no sighting reaches that record any more).
local function verify(s, index)
  local entry = s.state.rolls[index]
  if not entry or not checked(entry) then return end
  local v = verdict(s.rollLog, entry, false)
  if v then setVerdict(s, index, v) end
  local mine = s.stake ~= nil and entry.seat == s.mySeat
  if v and not (mine and not ownSeen(s.rollLog, entry)) then return end
  local client, check, log = s.client, s.rollCheck, s.rollLog
  s.rollNotMine, s.rollPending = s.rollNotMine or {}, s.rollPending or {}
  local notMine, pending = s.rollNotMine, s.rollPending
  pending[index] = true
  client:after(C.ROLL_VERIFY_WAIT, function()
    pending[index] = nil
    local here, was, wasMine = client.session == s and s.rollCheck == check, check[index], notMine[index]
    if not check[index] then check[index] = verdict(log, entry, true) end
    if mine and not ownSeen(log, entry) then notMine[index] = true end
    if here and (check[index] ~= was or notMine[index] ~= wasMine) then Session.emit(client) end
  end)
end

-- What my client saw of the rolls of a game -> nil | "roll" | "unseen", from
-- its audit record (a session: the game it holds; or Rolls.auditOf's):
-- "roll" when a recorded roll is one I saw with another number or a roll of
-- my seat I did not make, "unseen" when one I never saw or whose verdict is
-- still pending (pending is never clean, until its verdict replaces it); the
-- worst of it and of its folded records. From rollCheck, rollNotMine,
-- rollPending and rollFolded only, never from rollLog (which keeps the last
-- ROLL_LOG sightings), so a long game keeps its early rolls. Final
-- ROLL_FINAL_WAIT after the game's result: every verdict of it is given by then.
function Rolls.audit(s)
  if next(s.rollNotMine or {}) ~= nil then return "roll" end
  local out = next(s.rollPending or {}) ~= nil and "unseen" or nil
  for _, v in pairs(s.rollCheck or {}) do
    if v == "mismatch" then return "roll" end
    if v == "unseen" then out = "unseen" end
  end
  for _, r in ipairs(s.rollFolded or {}) do
    local got = Rolls.audit(r)
    if got == "roll" then return "roll" end
    out = out or got
  end
  return out
end

local function record(s)
  return { rollCheck = s.rollCheck, rollNotMine = s.rollNotMine, rollPending = s.rollPending, rollFolded = s.rollFolded }
end

-- Did my client see itself roll `entry` (state.rolls of my game)? -> bool
function Rolls.ownSeen(s, entry)
  return ownSeen(s.rollLog, entry)
end

-- The audit record of the staked game of my client that ended with q, at
-- table tid (gid "<tid>/<q>") -> record for Rolls.audit | nil.
function Rolls.auditOf(client, gid)
  return client.rollAudits and client.rollAudits[gid]
end

-- Does my own client see me in my host's group (or am I the host) -> bool:
-- only then can the host see my roll. By my own group roster
-- (env.groupedWith), never by a GUID the host announced.
function Rolls.withHost(s)
  if s.role == "host" then return true end
  local env = s.client.env
  return env.groupedWith ~= nil and env.groupedWith(s.host) == true
end

-- A server roll seen in chat by `client` (`shown` normalized; my own as env.me).
function Rolls.seen(client, shown, n, lo, hi)
  client.events:emit("rollSeen", shown, n, lo, hi)
  local s = client.session
  if not s or not usesRolls(s) or lo ~= 1 or not integer(n) or not integer(hi) then return end
  local seat = Rolls.seatFor(s.seats, shown)
  if not seat then return end
  s.rollLog = s.rollLog or {}
  local log, own = s.rollLog, shown == client.env.me
  log[#log + 1] = { seat = seat, n = n, max = hi, at = client.env.now(), own = own or nil }
  if #log > C.ROLL_LOG then table.remove(log, 1) end
  recheck(s)
  local st = s.state
  if s.status ~= "live" or not st or st.turn ~= seat or hi ~= st.max then return end
  if own and seat == s.mySeat and Rolls.withHost(s) then s.myRoll = { n = n, max = hi } end
  if s.role == "host" then
    s:play(seat, { k = "roll", n = n, max = hi, src = "seen" })
  elseif st.staked then
    -- Only what the host sees counts: no claim. My own roll it never plays is unheard.
    if not (own and seat == s.mySeat) then return end
    local mine = { seen = true }
    s.rolling, s.rollStuck, s.rollUnheard = mine, false, nil
    client:after(C.ROLL_CLAIM_WAIT + C.ROLL_VERIFY_WAIT, function()
      if client.session ~= s or s.rolling ~= mine then return end
      s.rolling, s.rollUnheard = nil, true
      Session.emit(client)
    end)
    Session.emit(client)
  elseif seat == s.mySeat then
    -- Also when `rolling` is nil: after the stuck hint the player types /roll by hand.
    client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = { k = "roll", n = n, max = hi } }))
    s.rolling = { seen = true }
    Session.emit(client)
  end
end

-- My roll -> true | nil, code: "none", "seat", "live", "turn" (not my turn),
-- "wait" (my roll is already under way), "roll" (a staked game and no server
-- roll: no env.roll, or the automatic path). With env.roll a server roll, which
-- comes back through Rolls.seen; without, or with `byTable` (the automatic
-- path: a server roll comes only from a click), the table rolls for me (src "ask").
function Rolls.roll(client, byTable)
  local s = client.session
  if not s then return nil, "none" end
  if not s.mySeat then return nil, "seat" end
  if s.status ~= "live" or not s.state then return nil, "live" end
  if s.state.turn ~= s.mySeat then return nil, "turn" end
  if s.rolling then return nil, "wait" end
  local env, max = client.env, s.state.max
  if s.state.staked and (byTable or not env.roll) then return nil, "roll" end
  s.rollUnheard = nil
  if env.roll and not byTable then
    local mine = { seen = false }
    s.rolling = mine
    env.roll(1, max)
    client:after(C.ROLL_ECHO_WAIT, function()
      if client.session ~= s or s.rolling ~= mine or mine.seen then return end
      s.rolling, s.rollStuck = nil, true
      Session.emit(client)
    end)
    Session.emit(client)
  elseif s.role == "host" then
    s:play(s.mySeat, { k = "roll", n = env.random(1, max), max = max, src = "ask" })
  else
    client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = { k = "roll", max = max, src = "ask" } }))
    s.rolling = { seen = true }
    Session.emit(client)
  end
  return true
end

-- Host: a member's roll ACT. "ask" is rolled at once; a claim is held for
-- ROLL_CLAIM_WAIT and then played as "claim" while that seat is still on turn
-- at that max (a sighting of my own plays it as "seen" before). Whatever src
-- the member sent is ignored.
local function act(s, seat, a)
  if a.k ~= "roll" then return a end
  local st = s.state
  if a.max ~= st.max or st.turn ~= seat or st.staked then return nil end -- staked: my own sighting only
  local max = st.max
  if a.src == "ask" then
    return { k = "roll", n = s.client.env.random(1, max), max = max, src = "ask" }
  end
  local n = a.n
  if not integer(n) or n < 1 or n > max then return nil end
  local claim = { seat = seat, n = n, max = max }
  s.claim = claim
  local client = s.client
  client:after(C.ROLL_CLAIM_WAIT, function()
    if client.session ~= s or s.claim ~= claim or s.role ~= "host" or s.status ~= "live" then return end
    if s.state.turn ~= seat or s.state.max ~= max then return end
    s:play(seat, { k = "roll", n = n, max = max, src = "claim" })
  end)
  return nil
end

-- A new game: no verdict, sighting, roll under way or claim of the last one
-- carries over (a sighting of game 1 must never confirm a claim in game 2).
local function resetGame(s)
  s.rollCheck, s.rollLog, s.rollNotMine, s.rollPending, s.rollFolded = {}, {}, {}, {}, {}
  s.rolling, s.rollStuck, s.claim, s.rollUnheard, s.myRoll, s.rollKept = nil, false, nil, nil, nil, nil
end

-- Staked: an event ended the game that ran here (s.stakeLive, before core/Stakes.lua's
-- refresh of it); its record goes under its gid.
local function keep(s)
  if s.stake == nil or s.rollKept or not s.rollCheck or not s.stakeLive or (s.status == "live" and not s:gameOver()) then return end
  local client = s.client
  local audits, order = client.rollAudits or {}, client.rollAuditOrder or {}
  client.rollAudits, client.rollAuditOrder, s.rollKept = audits, order, true
  local gid = s.tid .. "/" .. s.seq
  audits[gid], order[#order + 1] = record(s), gid
  if #order > AUDITS_KEPT then audits[table.remove(order, 1)] = nil end
end

local function sameRoll(x, y)
  return x.seat == y.seat and x.n == y.n and x.max == y.max and x.src == y.src
end

-- The snapshot state `now` continues the game of `prev`: same start number and
-- prev's rolls are the first rolls of `now`.
local function sameGame(prev, now)
  if not prev or not now or prev.start ~= now.start or #now.rolls < #prev.rolls then return false end
  for i = 1, #prev.rolls do
    if not sameRoll(prev.rolls[i], now.rolls[i]) then return false end
  end
  return true
end

local function applied(s, seat, a)
  if seat == 0 then
    if a.k == "start" then resetGame(s) end
    return keep(s)
  end
  if a.k ~= "roll" then return end
  s.rolling, s.rollStuck, s.claim, s.rollUnheard, s.myRoll = nil, false, nil, nil, nil
  s.rollCheck = s.rollCheck or {} -- joined mid-game: checks from here on
  verify(s, #s.state.rolls)
  keep(s)
end

ns.Ext.rolls = {
  act = act,
  applied = applied,
  -- A snapshot replaced my state. It carries my game on: at a staked table
  -- the rolls it adds are verified like applied ones. Another game's roll
  -- state is dropped; at a staked table, when my game was still running here
  -- (s.stakeLive), its record stays folded into the new one (Rolls.audit), so
  -- its pending verdicts still count when they come.
  adopted = function(s, prev)
    s.rollHost = s.host
    if sameGame(prev, s.state) then
      if s.stake ~= nil then
        for i = #prev.rolls + 1, #s.state.rolls do verify(s, i) end
      end
      return
    end
    local old = s.stake ~= nil and s.stakeLive and s.rollCheck and record(s)
    resetGame(s)
    if old then s.rollFolded = { old } end
  end,
  -- My host changed (I took over, or I follow another): a claim held by the old
  -- host is gone with it, so the roll under way is dropped and the player may
  -- press „Хвърли“ again at once (a second server roll; the new host plays the
  -- first one it sees). A host that steps down drops the claim it held. My own
  -- roll stays (myRoll). At a staked table the same host at a new epoch is no
  -- host change.
  hostChanged = function(s)
    if s.stake ~= nil and s.rollHost == s.host then return end
    s.rollHost = s.host
    s.rolling, s.claim = nil, nil
  end,
  auto = function(s)
    Rolls.roll(s.client, true)
    return true
  end,
}
