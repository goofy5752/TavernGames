local _, ns = ...

-- The chess clock of a table session (an engine with `clock`, spec 5.3). The
-- time left is in the engine state (tenths of a second); here is what the
-- state cannot hold: when the running turn began on my client, and what my
-- client makes of the host's word about it.
-- - Host: every move event carries `dt`, the tenths the mover thought, from
--   when my client began the turn (the event that gave it) to the move
--   (Clock.stamp, Session:event); the flag timer is the time left of the seat
--   on turn, plus AUTO_GRACE for another seat (Clock.arm, Session:armTimers).
-- - Member at a staked table: the host's `dt` is checked against my own clock
--   over the whole game, two sums (Clock.before): my moves (`dt` less my time
--   from my turn to my ACT) and the other seat's (my time between the two
--   events less `dt`). Either above its tolerance, TOL_BASE + TOL_PER per
--   move counted, is forged. A move without `dt` is forged; a flag of my seat
--   is honest only by my clock (Clock.flagHonest, Member.timedOut).
-- - The host's own flag: the other seat may claim it once my clock says its
--   time is gone (Clock.canClaim, Clock.claim); a move of that seat, or no
--   flag within AUTO_GRACE, is forged at a staked table.
-- A turn whose beginning my clock did not see (a login's snapshot, another
-- turn in a snapshot) is a gift to the seat on turn: measured from the
-- snapshot, never counted in the sums.
--
-- Session fields (local, never sent):
--   clockAt    my env.now() when the running turn began for me
--   clockKey   #state.moves of that turn
--   clockSeen  false when a snapshot brought the turn (my clock did not see it begin)
--   clockOwn, clockOpp  {sum, n}: the sums of my moves and of the other seat's, n moves each
--   clockPrev  {at, key, seen, seat, left}: the turn my clock measured before a snapshot replaced
--              the state (seat: on turn, left: its time in that state), or nil (Clock.adopted)
--   claimTimer my claim of the other seat's flag waits for the host's answer
-- The Session fields are reached at call time: this file loads before core/Session.lua.
local Clock = {}
ns.Clock = Clock

local C = ns.Const

-- Measured (tests/core/chess_table_test.lua, 0.4 s each way): an honest host
-- adds the round trip, 8 tenths, to the sum of my moves each move, and nothing
-- to the other's; 20 moves of mine make 160 of tolerance(20) = 200. A round
-- trip over about 1 s is charged in a long staked game (an in-game follow-up),
-- while a host that takes 3 s a move is caught by the fifth.
Clock.TOL_BASE = 100 -- tenths: what a sum may reach before its first move
Clock.TOL_PER = 5    -- tenths per move counted in it (a round trip of 0.5 s)
Clock.FLAG_TOL = 10  -- tenths my clock may still show when a flag of my seat comes

-- The tolerance of a sum of n moves, in tenths.
function Clock.tolerance(n)
  return Clock.TOL_BASE + Clock.TOL_PER * n
end

local function now(s) return s.client.env.now() end

-- A clock runs at this table -> bool: an engine with `clock`, live, a game
-- that is not over, with a time limit.
function Clock.timed(s)
  local engine, st = s:engine(), s.state
  return engine ~= nil and engine.clock == true and s.status == "live" and st ~= nil and st.clock ~= nil and not s:gameOver()
end

-- A new turn (another #moves than the marked one) or `fresh` (a snapshot
-- brought it) begins now on my clock. Not timed: every mark is cleared. A
-- new game (no move yet) starts both sums again.
function Clock.mark(s, fresh)
  if not Clock.timed(s) then
    s.clockAt, s.clockKey, s.clockSeen = nil, nil, nil
    return
  end
  local key = #s.state.moves
  if key == s.clockKey and not fresh then return end
  s.clockAt, s.clockKey, s.clockSeen = now(s), key, not fresh
  if key == 0 then s.clockOwn, s.clockOpp = nil, nil end
end

-- The seat's time in tenths, less what passed since the turn began when that
-- seat is on turn, never below 0; nil without a limit or a state.
function Clock.left(s, seat)
  local st = s.state
  local t = st and st.clock and st.clock[seat]
  if type(t) ~= "number" then return nil end
  if s.clockAt and st.turn == seat and Clock.timed(s) then t = t - (now(s) - s.clockAt) * 10 end
  return math.max(0, t)
end

-- Host, before every event: the `dt` of a move at a timed table (whole
-- tenths since the turn began), else nil. A start forgets the last game's
-- turn (one that ended at the same #moves would look like this one).
function Clock.stamp(s, seat, a)
  if type(a) ~= "table" or not s:engine().clock then return nil end
  if seat == 0 and a.k == "start" then s.clockKey = nil end
  if a.k ~= "move" or seat == 0 or not Clock.timed(s) then return nil end
  if not s.clockAt then Clock.mark(s) end
  return math.max(0, math.floor((now(s) - s.clockAt) * 10 + 0.5))
end

-- Host, from Session:armTimers after every game event (seat: on turn, or
-- nil): the turn is marked; with a limit, the deadline is the time left of
-- the seat on turn, and its flag goes then (another seat: AUTO_GRACE later).
function Clock.arm(s, engine, seat)
  Clock.mark(s)
  if not (seat and s.clockAt) then return end
  local client = s.client
  s.deadline = s.clockAt + s.state.clock[seat] / 10
  local wait = s.deadline + (seat ~= s.mySeat and C.AUTO_GRACE or 0) - now(s)
  s.turnTimer = client:after(math.max(0, wait), function()
    s.turnTimer = nil
    s:play(seat, { k = "flag" }, true)
  end)
end

-- The running turn as my clock saw it -> {at, key, seen, seat, left} | nil.
local function turn(s, st)
  if not (s.clockAt and st and st.turn and st.clock) then return nil end
  return { at = s.clockAt, key = s.clockKey, seen = s.clockSeen, seat = st.turn, left = st.clock[st.turn] }
end

-- Is a flag of `seat` honest by my own clock, for the turn `c` my clock
-- measured ({at, seen, seat, left}: Clock.adopted's clockPrev, or the running
-- turn) -> bool: my clock saw that turn of that seat begin, its time is gone
-- by my clock (FLAG_TOL left), and no action I sent on it, at least TOL_BASE
-- before my own deadline, is still unmatched in s.sent (the host dropped it;
-- a move sent later is the player's lag, spec 5.3). Shared with core/StakesChess.lua.
function Clock.flagHonest(s, seat, c)
  if not (c and c.seen and c.at and c.seat == seat and type(c.left) == "number") then return false end
  if (now(s) - c.at) * 10 < c.left - Clock.FLAG_TOL then return false end
  local last = c.at + (c.left - Clock.TOL_BASE) / 10
  local sent = s.sent or {}
  for i = 1, #sent do
    if sent[i].at >= c.at and sent[i].at <= last then return false end
  end
  return true
end

-- Member.timedOut for a clock engine: the event m is a flag due by my clock.
function Clock.flagDue(s, m)
  local st = s.state
  return type(m.a) == "table" and m.a.k == "flag" and st ~= nil and type(st.moves) == "table"
    and s.clockKey == #st.moves and Clock.flagHonest(s, m.seat, turn(s, st))
end

-- Adds d to the sum `key` (one move more); above its tolerance: forged.
local function count(s, key, d, m)
  local t = s[key] or { sum = 0, n = 0 }
  s[key] = t
  t.sum, t.n = t.sum + d, t.n + 1
  if t.sum > Clock.tolerance(t.n) then s:hook("forged", m.seat, m.a) end
end

-- The `at` of the first action in s.sent that is `a`, or nil.
local function sentAt(s, a)
  local sent = s.sent or {}
  for i = 1, #sent do
    if ns.Util.same(sent[i].a, a) then return sent[i].at end
  end
  return nil
end

-- Member, before the event m is applied (and before Member.mine takes my own
-- move off s.sent): at a staked, timed table, the host's `dt` of a move
-- against my clock. A turn my clock did not see begin is not counted.
function Clock.before(s, m)
  if not s:engine().clock or s.stake == nil or not Clock.timed(s) then return end
  local a = m.a
  if type(a) ~= "table" or a.k ~= "move" or m.seat == 0 then return end
  if m.dt == nil then return s:hook("forged", m.seat, a) end
  if type(m.dt) ~= "number" or not s.mySeat or not s.clockSeen or s.clockKey ~= #s.state.moves then return end
  if m.seat == s.mySeat then
    local at = sentAt(s, a)
    if at then count(s, "clockOwn", m.dt - (at - s.clockAt) * 10, m) end
  else
    count(s, "clockOpp", (now(s) - s.clockAt) * 10 - m.dt, m)
  end
end

local function stopClaim(s)
  if s.claimTimer then s.claimTimer.cancel(); s.claimTimer = nil end
end

-- My claim failed (another move of the claimed seat, or no flag in
-- AUTO_GRACE): forged at a staked table, nothing at a table for fun.
local function claimFailed(s)
  stopClaim(s)
  if s.stake == nil then return end
  ns.Stakes.foul(s, "forged")
  ns.Session.emit(s.client)
end

-- Member, after the event m was applied: the turn is marked (a start forgets
-- the last game's). While my claim waits, a move of the claimed seat fails
-- it; the end of the game (its flag among them) ends it.
function Clock.after(s, m)
  if not s:engine().clock then return end
  local a = type(m.a) == "table" and m.a or {}
  if m.seat == 0 and a.k == "start" then s.clockKey = nil end
  Clock.mark(s)
  if not s.claimTimer then return end
  if s.mySeat and m.seat == 3 - s.mySeat and a.k == "move" then return claimFailed(s) end
  if not Clock.timed(s) then stopClaim(s) end
end

-- Member.adopt, after a snapshot replaced my state (prevState: the one it
-- replaced): the turn my clock measured is kept in s.clockPrev; a login, or
-- a snapshot at another turn, begins the running turn now, unseen (a gift to
-- the seat on turn, out of the sums); the same turn keeps my measurement.
function Clock.adopted(s, prevState)
  if not s:engine().clock then return end
  s.clockPrev = turn(s, prevState)
  local st = s.state
  Clock.mark(s, not (s.clockAt and st and type(st.moves) == "table" and s.clockKey == #st.moves))
end

-- May I claim the other seat's flag -> bool: seated at a timed table, the
-- other seat on turn with no time left by my clock, not claimed at this ply.
function Clock.canClaim(s)
  local st, me = s.state, s.mySeat
  if not (me and Clock.timed(s) and st.turn == 3 - me) then return false end
  return Clock.left(s, st.turn) == 0 and st.claimed ~= #st.moves
end

-- I claim the other seat's flag -> true | nil, code (Session.act). A member
-- then waits AUTO_GRACE for the host's flag (Clock.after).
function Clock.claim(client)
  local ok, code = ns.Session.act(client, { k = "claim" })
  if not ok then return nil, code end
  local s = client.session
  if s.role == "host" then return true end
  stopClaim(s)
  s.claimTimer = client:after(C.AUTO_GRACE, function()
    s.claimTimer = nil
    if client.session == s then claimFailed(s) end
  end)
  return true
end

return Clock
