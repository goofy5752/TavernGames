local _, ns = ...

-- The play of a staked table (s.stake, core/Stake.lua): the extension
-- ns.Ext.stakes, which Session:hook and Session:filterAct call at a staked
-- table after the engine's own (core/Lifecycle.lua), the host's idle stand of
-- Death Roll (engine.idle), and the fouls my client notes against the running
-- game. A foul is the worst my client saw of that game, by Stakes.RANK:
--   forged  an event for my seat I did not send and that is no due timeout
--           (Member.onEvent, Member.timedOut), an event of my host my engine
--           refused, a pushed snapshot that changes the game I hold, a staked
--           flag in a snapshot that is not my accepted stake (Member.adopt), a
--           start no honest host plays (a member's checks): one while a game
--           runs, one of Морски шах (whose matches begin when sits fill the
--           table, or by both players' „Реванш“) while the table is live or,
--           after a game, before my client saw a seat empty and filled again
--           by a sit, one of a host-started game (engine.start "host", the
--           one Session:canStart gates) earlier than STAKE_BREAK after the
--           last ended by my clock, AUTO_GRACE left for the transport; a
--           snapshot that does for my seat what I did not (a mark or a roll in
--           my name, a new match without my „Реванш“, my seat gone without my
--           stand or an idle stand my clock agrees with);
--   roll    an idle stand of my seat after my client saw its own roll on that
--           turn while it saw me in the host's group (the host ignored it;
--           outside the group the host could not see it: no foul);
--   stand   my seat stood up while my client ran and I did not ask, unless an
--           idle stand my own clock agrees with;
--   unseen  a snapshot I asked for or logged in with brought me into the game,
--           or one from a changed host is a prefix of my game (or mine of it).
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
--   stakeFoul    nil | "forged" | "roll" | "stand" | "unseen"
--   stakePend    the foul of the event being handled, set at the end of the hook
--   stakeTurn    {seat, at, seen}: the seat on turn and my env.now() when it came on
--                turn (seen false: a snapshot brought the turn, my clock did not see it begin)
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

local function pend(s, why)
  local p = s.stakePend
  if not p or Stakes.RANK[why] > Stakes.RANK[p] then s.stakePend = why end
end

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
-- cleared; then the foul of the event; the turn (`moved`: a game action
-- restarts it) and the idle timer. `snap`: a snapshot, which dates no end.
local function refresh(s, fresh, moved, snap)
  local now, on = s.client.env.now(), running(s)
  if on and (fresh or not s.stakeLive) then
    s.stakeRoster, s.stakeFoul, s.stakeTurn, s.stakeStood, s.stakeRefill = roster(s), nil, nil, nil, nil
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
    s.stakeTurn = { seat = turn, at = now, seen = not snap }
  end
  if s.stakeTurn ~= t then armIdle(s) end
end

-- My seat `seat` went while a game runs and I did not ask (`why`: the stand's,
-- nil when only my host's SNO "gone" or a snapshot told me; `max`: the game's
-- max before it): "stand" ("forged" when a snapshot shows it), unless an idle
-- stand (engine.idle) my own clock agrees with: my seat on turn for
-- OFFLINE_STAND_SECONDS, AUTO_GRACE left for the transport ("unseen" when my
-- clock did not see that turn begin). After my own roll on that turn at its
-- max (Rolls: s.myRoll) an idle stand is "roll". Judged once a game.
local function stood(s, seat, why, snap, max)
  if not s.stakeLive or s.role == "host" or s.stakeStood then return end
  s.stakeStood = true
  local t, now = s.stakeTurn, s.client.env.now()
  local idle = s:engine().idle and why ~= "offline" and why ~= "left"
  local mine = idle and t and t.seat == seat
  if mine and s.myRoll and s.myRoll.max == max then return pend(s, "roll") end
  if mine and now >= t.at + C.OFFLINE_STAND_SECONDS - C.AUTO_GRACE then return end
  pend(s, (mine and not t.seen) and "unseen" or snap and "forged" or "stand")
end

-- My Морски шах timeout is due by my own clock (Member.timedOut's rule for a
-- turn my client saw begin, before this event): one mark of mine may be it.
local function timeoutDue(s, seat)
  local t = s.stakeTurn
  if not (t and t.seat == seat and t.seen and type(s.turn) == "number") then return false end
  if s.client.env.now() < t.at + s.turn then return false end
  for _, e in ipairs(s.sent or {}) do
    if e.at >= t.at and e.at < t.at + s.turn then return false end
  end
  return true
end

-- What a snapshot carrying my game on (or replacing it) did for my seat that
-- I did not -> true: forged. Морски шах: a mark of mine I never sent beyond
-- one due timeout, a new match while my match was live without my
-- „Реванш“; Death Roll: a roll of mine my client did not see itself make.
local function doneForMe(s, prev, st, seat, forward)
  if not (prev and st and seat) then return false end
  if prev.rolls and st.rolls then
    for i = forward and #prev.rolls + 1 or #st.rolls + 1, #st.rolls do
      if st.rolls[i].seat == seat and not ns.Rolls.ownSeen(s, st.rolls[i]) then return true end
    end
    return false
  end
  if not (prev.board and st.board) then return false end
  if not forward then
    return s.stakeStatus == "live" and not (prev.rematch and prev.rematch[seat]) and not ns.Member.mine(s, { k = "rematch" })
  end
  local timeout = timeoutDue(s, seat)
  for c = 1, 9 do
    if st.board[c] == seat and (prev.round ~= st.round or prev.board[c] ~= seat) and not ns.Member.mine(s, { k = "mark", c = c }) then
      if not timeout then return true end
      timeout = false
    end
  end
  return false
end

-- Does game state a lead to b in one game (b is a, or a later point of it)?
-- Death Roll: the same start, a's rolls are b's first rolls. Морски шах: the
-- same round with a's marks on b's board, or the next round after a's ended.
function Stakes.leadsTo(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if a.rolls and b.rolls then
    if a.start ~= b.start or #a.rolls > #b.rolls then return false end
    for i = 1, #a.rolls do
      if not same(a.rolls[i], b.rolls[i]) then return false end
    end
    return true
  end
  if not (a.board and b.board) then return false end
  if a.round ~= b.round then
    return a.round + 1 == b.round and a.phase == "round" and a.score[1] <= b.score[1] and a.score[2] <= b.score[2]
  end
  for c = 1, 9 do
    if a.board[c] ~= 0 and a.board[c] ~= b.board[c] then return false end
  end
  return true
end

local leadsTo = Stakes.leadsTo

-- A snapshot replaced my state (how: see Member.adopt). The very game I hold:
-- nothing. My game carried on (or, from a changed host, one behind mine): the
-- same game, "unseen". Anything else is another game. A snapshot nobody asked
-- for that changes my game is "forged", from my own host always, from a
-- changed host unless it is a prefix (F21); one I asked for or logged in with
-- is "unseen". Its Death Roll state must say staked (Member.adopt set mine).
-- The foul of a game that was running here stays, whatever the snapshot (the
-- host can make me ask for one at will: a TCK or a gap); Rolls' adopted
-- added what that game's roll audit found.
local function adopted(s, prev, m, how)
  local st, was, on, me = s.state, s.stakeLive, running(s), s.client.env.me
  local kept = was and s.stakeFoul or nil
  if s:engine().idle and type(m.st) == "table" and m.st.staked ~= true then pend(s, "forged") end
  local identical = prev ~= nil and st ~= nil and same(prev, st) and was == on
  local forward = leadsTo(prev, st)
  local cont = identical or forward or (how.changed and leadsTo(st, prev))
  if not identical and (was or on) then
    local pushed = not (how.changed or how.asked or how.fresh)
    pend(s, (pushed or (how.changed and not how.asked and not cont)) and "forged" or "unseen")
  end
  local held = s.stakeSeat -- my seat before this snapshot
  if held and not identical and doneForMe(s, prev, st, held, forward) then pend(s, "forged") end
  if held and s.seats[held] ~= me then stood(s, held, nil, true, prev and prev.max) end
  if how.sat then s.stakeRefill = "filled" end -- my own sit filled the seat
  refresh(s, not cont, nil, true)
  if kept then Stakes.foul(s, kept) end
  s.stakeHost = s.host
end

-- A start no honest host plays now (a member's check, before the event's
-- refresh): a game ran; Морски шах (no host start) at a live table; a
-- host-started game inside the break.
local function badStart(s)
  local engine = s:engine()
  if s.stakeLive or (engine.start ~= "host" and (s.stakeStatus == "live" or (s.stakeHad and s.stakeRefill ~= "filled"))) then
    return true
  end
  return engine.start == "host" and s.stakeEndedAt ~= nil
    and s.client.env.now() < s.stakeEndedAt + C.STAKE_BREAK - C.AUTO_GRACE
end

-- Host: the stand of another seat of the running game, but a leave (its
-- player asked for it), goes to that player too: its client judges it.
local function tellStood(s, a)
  local name = s.stakeRoster and s.stakeRoster[a.seat]
  if a.why == "left" or not name or name == s.client.env.me then return end
  s.client:send("WHISPER", name, ns.Session.message("EV", {
    tid = s.tid, e = s.epoch, q = s.seq, seat = 0, a = a, left = s:left(),
  }))
end

ns.Ext.stakes = {
  applied = function(s, seat, a)
    local start = seat == 0 and a.k == "start"
    if start and s.role ~= "host" and badStart(s) then
      pend(s, "forged")
    elseif seat == 0 and a.k == "stand" and s.role == "host" then
      tellStood(s, a)
    elseif seat == 0 and a.k == "stand" and a.seat == s.mySeat then
      stood(s, a.seat, a.why, false, s.state.max)
    end
    if seat == 0 and a.k == "stand" then s.stakeRefill = "empty" end
    if seat == 0 and a.k == "sit" and s.stakeRefill == "empty" then s.stakeRefill = "filled" end
    refresh(s, start, seat ~= 0)
  end,
  forged = function(s) pend(s, "forged") end, -- the event is applied (or refused) next
  refused = function(s)
    pend(s, "forged")
    refresh(s)
  end,
  adopted = adopted,
  -- The idle stand is the host's: armed, or cancelled. Another host gives the
  -- seat on turn a fresh OFFLINE_STAND_SECONDS from the takeover (a roll the
  -- old host never answered is not held against it: Rolls drops myRoll). The
  -- same host at a new epoch changes nothing.
  hostChanged = function(s)
    if s.stakeHost == s.host then return end
    s.stakeHost = s.host
    local t = s.stakeTurn
    if t then s.stakeTurn = { seat = t.seat, at = s.client.env.now(), seen = true } end
    armIdle(s)
  end,
  leaving = function(s) refresh(s) end,
  -- Member: my host says I am not at its table any more (SNO "gone"), before my session ends.
  gone = function(s)
    if s.seats[s.mySeat] == s.client.env.me then stood(s, s.mySeat, nil, false, s.state and s.state.max) end
    refresh(s)
  end,
}
