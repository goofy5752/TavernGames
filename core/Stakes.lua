local _, ns = ...

-- The play of a staked table (s.stake, core/Stake.lua): the extension
-- ns.Ext.stakes, which Session:hook and Session:filterAct call at a staked
-- table after the engine's own (core/Lifecycle.lua), the host's idle stand of
-- Death Roll (engine.idle), and the fouls my client notes against the running
-- game; what my client checks for them is in core/StakesWatch.lua. A foul is
-- the worst my client saw of that game, by Stakes.RANK:
--   forged  an event for my seat I did not send and that is no timeout due by
--           my own clock (Member.onEvent, Member.timedOut), an event of my
--           host my engine refused, a pushed snapshot that changes the game I
--           hold, a staked flag in a snapshot that is not my accepted stake
--           (Member.adopt), a start no honest host plays (a member's checks):
--           one while a game runs, one of Морски шах (whose matches begin
--           when sits fill the table, or by both players' „Реванш“) while the
--           table is live, before my client saw a seat empty and filled again
--           by a sit, or seating me without my own sit or „Реванш“; one of a
--           host-started game (engine.start "host", the one Session:canStart
--           gates) earlier than STAKE_BREAK after the last ended by my clock,
--           AUTO_GRACE left for the transport; a snapshot, of my game or
--           another, that does for my seat what I did not (a mark or a roll in
--           my name, my seat gone without my stand or a stand for idleness my
--           clock agrees with);
--   roll    a stand for idleness of my seat after my client saw its own roll
--           on that turn while it saw me in the host's group (the host ignored
--           it; outside the group the host could not see it: no foul);
--   stand   my seat stood up while my client ran and I did not ask, unless for
--           idleness and my own clock agrees;
--   unseen  a snapshot I asked for or logged in with brought me into the game,
--           or one from a changed host is a prefix of my game (or mine of it);
--           what my clock cannot tell after a login or another host.
-- Fouls are reset when an event begins a new game; a foul raised by that
-- event is set after the reset, so it counts against that game. A snapshot
-- never clears nor lowers the foul of a game that was running on my client.
-- The host also whispers the stand of a seat (not "left") to the player stood
-- up, so that client judges its own stand with its why. The same host at a new
-- epoch is no host change here (s.stakeHost).
-- Death Roll's rolls are judged by Rolls.audit, not here.
--
-- Session fields (local, never sent):
--   stakeLive    a game runs (live, a state, not over); recomputed at the end of every hook
--   stakeRoster  seat -> name of who plays the running game, taken when it begins
--                (the seats engine.playing accepts); nil while none runs
--   stakeNo      how many games began on my client at this table
--   stakeFoul    nil | "forged" | "roll" | "stand" | "unseen"
--   stakePend    the foul of the event being handled, set at the end of the hook
--   stakeTurn    {seat, at, seen, was}: the seat on turn and my env.now() when my client
--                first saw it on turn, or when another host took over (was: the first
--                clock then); seen false: a login brought the turn, no clock of mine saw it begin
--   stakeStood   my seat's stand was judged in this game
--   stakeRefill  "empty" | "filled": since the last game my client saw a seat
--                empty, then filled by a sit (Морски шах's next start)
--   stakeHad     a game state existed before the event being handled
--   stakeSeat    my seat after the last hook (nil: not seated)
--   stakeHost    the host of my table to Stakes
--   stakeStatus  s.status after the last hook (the status before the event being handled)
--   stakeEndedAt my env.now() when an event ended the last game (Session:canStart's
--                "break"); nil when a snapshot ended it
--   stakeIdle    my client stands up as host after its own idle turn (the note's why "idle")
--   idleTimer    the host's idle stand: OFFLINE_STAND_SECONDS after the seat came on turn
local Stakes = {}
ns.Stakes = Stakes

local C = ns.Const
local same = ns.Util.same

Stakes.RANK = { forged = 4, roll = 3, stand = 2, unseen = 1 }

-- Notes `why` against the running game; the higher rank stays.
function Stakes.foul(s, why)
  local now = s.stakeFoul
  if not now or Stakes.RANK[why] > Stakes.RANK[now] then s.stakeFoul = why end
end

-- Notes `why` for the event (or snapshot) being handled: set at the end of its hook.
local function pend(s, why)
  local p = s.stakePend
  if not p or Stakes.RANK[why] > Stakes.RANK[p] then s.stakePend = why end
end
Stakes.pend = pend

-- Is every other seated player in my group -> bool, by my own group roster
-- (env.groupedWith; without it nobody is). Session:canStart's "group".
function Stakes.grouped(s)
  local env = s.client.env
  for i = 1, #s.seats do
    local name = s.seats[i]
    if name and name ~= env.me and not (env.groupedWith and env.groupedWith(name) == true) then return false end
  end
  return true
end

local function running(s)
  return s.status == "live" and s.state ~= nil and not s:gameOver()
end
Stakes.running = running

local function roster(s)
  local engine, out = s:engine(), {}
  for i = 1, #s.seats do
    local name = s.seats[i]
    if name and (not engine.playing or engine.playing(s.state, i)) then out[i] = name end
  end
  return out
end

-- Host of a game with engine.idle: the seat on turn (s.stakeTurn) is stood up
-- ("idle") OFFLINE_STAND_SECONDS after it came on turn, by whoever hosts then;
-- my own seat stands up instead (Client:stand: a handoff, "left"). Fires only
-- while I host and the turn is still that one.
local function armIdle(s)
  if s.idleTimer then s.idleTimer.cancel(); s.idleTimer = nil end
  local t, client = s.stakeTurn, s.client
  if not (t and s.role == "host" and s:engine().idle) then return end
  s.idleTimer = client:after(math.max(0, t.at + C.OFFLINE_STAND_SECONDS - client.env.now()), function()
    s.idleTimer = nil
    if client.session ~= s or s.role ~= "host" or s.stakeTurn ~= t then return end
    if t.seat == s.mySeat then
      s.stakeIdle = true
      return client:stand()
    end
    ns.Succession.untrack(s, s.seats[t.seat])
    s:event(0, { k = "stand", seat = t.seat, why = "idle" })
    s:abortIfShort()
    s:recordChanged()
  end)
end

-- At the end of every hook: is a game running; when one begins (or `fresh`: a
-- start, or a snapshot of another game) the roster is taken and the foul
-- cleared (Stakes.began judges it first); then the foul of the event; the
-- turn (`moved`: a game action, or a snapshot at another turn, restarts it)
-- and the idle timer. `snap`: a snapshot (it dates no end; snap.fresh: a login
-- brought it, so no clock of mine saw its turn begin).
local function refresh(s, fresh, moved, snap)
  local now, on = s.client.env.now(), running(s)
  if on and (fresh or not s.stakeLive) then
    Stakes.began(s, snap)
    s.stakeRoster, s.stakeFoul, s.stakeTurn, s.stakeStood, s.stakeRefill = roster(s), nil, nil, nil, nil
    s.stakeNo = (s.stakeNo or 0) + 1
  elseif not on then
    if s.stakeLive then s.stakeEndedAt = not snap and now or nil end
    s.stakeRoster, s.stakeTurn = nil, nil
  end
  s.stakeLive, s.stakeStatus, s.stakeHad = on, s.status, s.state ~= nil
  s.stakeSeat = s.mySeat and s.seats[s.mySeat] == s.client.env.me and s.mySeat or nil
  if s.stakePend then Stakes.foul(s, s.stakePend); s.stakePend = nil end
  local turn, t = on and s.state.turn or nil, s.stakeTurn
  if not turn then
    s.stakeTurn = nil
  elseif moved or not t or t.seat ~= turn then
    s.stakeTurn = { seat = turn, at = now, seen = not (snap and snap.fresh) }
  end
  if s.stakeTurn ~= t then armIdle(s) end
end
Stakes.refresh = refresh

-- Host: the stand of another seat of the running game, but a leave (its
-- player asked for it), goes to that player too: its client judges it.
local function tellStood(s, a)
  local name = s.stakeRoster and s.stakeRoster[a.seat]
  if a.why == "left" or not name or name == s.client.env.me then return end
  s.client:send("WHISPER", name, ns.Session.message("EV", {
    tid = s.tid, e = s.epoch, q = s.seq, seat = 0, a = a, left = s:left(),
  }))
end

-- The member's checks (stood, badStart, began, sent, the hook `adopted`): core/StakesWatch.lua.
ns.Ext.stakes = {
  applied = function(s, seat, a)
    local start = seat == 0 and a.k == "start"
    if s.role == "host" and seat ~= 0 and seat == s.mySeat then Stakes.sent(s, a) end -- my own move
    if start and s.role ~= "host" and Stakes.badStart(s) then
      pend(s, "forged")
    elseif seat == 0 and a.k == "stand" and s.role == "host" then
      tellStood(s, a)
    elseif seat == 0 and a.k == "stand" and a.seat == s.mySeat then
      Stakes.stood(s, a.seat, a.why, false, s.state.max)
    end
    if seat == 0 and a.k == "stand" then s.stakeRefill = "empty" end
    if seat == 0 and a.k == "sit" and s.stakeRefill == "empty" then s.stakeRefill = "filled" end
    refresh(s, start, seat ~= 0)
  end,
  -- The event is applied (or refused) next. The timeout of a turn a login
  -- brought me (no clock of mine saw it begin) is a question, not forged.
  forged = function(s, seat, a, auto)
    local t = s.stakeTurn
    local blind = auto == true and t and t.seat == seat and not t.seen and same(a, s:engine().auto(s.state, seat))
    pend(s, blind and "unseen" or "forged")
  end,
  refused = function(s)
    pend(s, "forged")
    refresh(s)
  end,
  -- The idle stand is the host's: armed, or cancelled. Another host gives the
  -- seat on turn a fresh OFFLINE_STAND_SECONDS from the takeover (`was`: the
  -- turn's first clock); my own seat after a roll of mine only the first time
  -- (Rolls' hostChanged ran before: myRoll.pass). The same host at a new
  -- epoch changes nothing.
  hostChanged = function(s)
    if s.stakeHost == s.host then return end
    s.stakeHost = s.host
    local t, r = s.stakeTurn, s.myRoll
    if t and not (t.seat == s.stakeSeat and r and r.pass == false) then
      s.stakeTurn = { seat = t.seat, at = s.client.env.now(), seen = true, was = t.seen and (t.was or t.at) or nil }
    end
    armIdle(s)
  end,
  leaving = function(s)
    Stakes.sent(s, { k = "stand" })
    refresh(s)
  end,
  -- Member: my host says I am not at its table any more (SNO "gone"), before my session ends.
  gone = function(s)
    if s.seats[s.mySeat] == s.client.env.me then Stakes.stood(s, s.mySeat, nil, false, s.state and s.state.max) end
    refresh(s)
  end,
}
