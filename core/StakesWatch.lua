local _, ns = ...

-- What my client checks of a staked table's host (core/Stakes.lua notes the
-- fouls): the log of what I sent, the stand of my seat, a snapshot against my
-- game, a start no honest host plays. The rules:
--   (a) My clock is mine. s.stakeTurn.at is my env.now() when my client first
--       saw that seat on turn, by an event or on receipt of a snapshot; at a
--       staked table a snapshot sets s.turnAt (Member.timedOut) from it, never
--       from the host's `left`. A snapshot keeps the clock only of the very
--       turn I hold (turnKey). Only a fresh adopt (a login: no clock of mine
--       ran) brings a turn "unseen": what my clock cannot tell is a question.
--   (b) My roll is tied to its turn (Rolls: s.myRoll) through every host
--       change. The first other host is not charged with it and the turn gets
--       a fresh clock, once; without a roll of mine every other host does.
--   (c) An idle or offline stand of my seat needs OFFLINE_STAND_SECONDS -
--       AUTO_GRACE on that clock, however the turn reached me.
--   (d) s.stakeLog, what I sent at this table: my moves, „Реванш“, sit and
--       stand (my rolls: Rolls' own sightings, judged in its `adopted` before
--       they go). A snapshot of any game is checked against it: a mark in my
--       name that I did not send, a new match of Морски шах that seats me
--       without my own sit or „Реванш“ since the last began (Stakes.began,
--       events too).
-- Session fields (local, never sent):
--   stakeLog  {k, c, g, r}: the action's kind and cell, s.stakeNo and the round when sent
local Stakes = ns.Stakes

local C = ns.Const
local same = ns.Util.same
local pend, refresh, running = Stakes.pend, Stakes.refresh, Stakes.running

local LOG_KEPT = 32

-- I sent `a` (a member's ACT, a host's own move, my sit, my stand).
function Stakes.sent(s, a)
  local log = s.stakeLog or {}
  s.stakeLog = log
  log[#log + 1] = { k = a.k, c = a.c, g = s.stakeNo or 0, r = s.state and s.state.round }
  if #log > LOG_KEPT then table.remove(log, 1) end
end

-- Did I send a `k` (cell c, in round r) since the last game began here -> bool
local function sentIn(s, k, c, r)
  local log, g = s.stakeLog or {}, s.stakeNo or 0
  for i = 1, #log do
    local e = log[i]
    if e.k == k and e.g == g and e.c == c and (r == nil or e.r == r) then return true end
  end
  return false
end

-- A game begins on my client (Stakes' refresh, before the reset; `snap`: by a
-- snapshot). Морски шах (no host start) seats a member in a new match only
-- by its own sit or its own „Реванш“ since the last one began.
function Stakes.began(s, snap)
  local seat = s.mySeat
  if s.role == "host" or s:engine().start == "host" or (snap and snap.fresh) then return end
  if not seat or s.seats[seat] ~= s.client.env.me then return end
  if not (sentIn(s, "rematch") or sentIn(s, "sit")) then pend(s, "forged") end
end

-- My seat `seat` went while a game runs and I did not ask (`why`: the stand's,
-- nil when only my host's SNO "gone" or a snapshot told me; `max`: the game's
-- max before it): "stand" ("forged" when a snapshot shows it), unless a stand
-- for idleness (engine.idle; any why but "left") my own clock agrees with: my
-- seat on turn for OFFLINE_STAND_SECONDS, AUTO_GRACE left for the transport.
-- "unseen" when my clock did not see that turn begin (a fresh adopt), or when
-- another host restarted it and the turn's first clock agrees. After my own
-- roll on that turn at its max (Rolls: s.myRoll) such a stand is "roll", but
-- from the first other host since that roll (myRoll.pass). Judged once a game.
function Stakes.stood(s, seat, why, snap, max)
  if not s.stakeLive or s.role == "host" or s.stakeStood or sentIn(s, "stand") then return end
  s.stakeStood = true
  local t, now, r = s.stakeTurn, s.client.env.now(), s.myRoll
  local due = C.OFFLINE_STAND_SECONDS - C.AUTO_GRACE
  local mine = s:engine().idle and why ~= "left" and t and t.seat == seat
  if mine and r and r.max == max and r.pass ~= s.host then return pend(s, "roll") end
  if mine and now >= t.at + due then return end
  pend(s, (mine and (not t.seen or (t.was and now >= t.was + due))) and "unseen" or snap and "forged" or "stand")
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

-- What a snapshot of Морски шах did for my seat that I did not -> true:
-- forged. A mark of mine that my game did not have and my log does not: in my
-- game carried on (`forward`) beyond one due timeout, in another game any.
local function doneForMe(s, prev, st, seat, forward)
  if not (st and st.board and seat) then return false end
  local timeout = forward and timeoutDue(s, seat)
  for c = 1, 9 do
    local had = forward and prev.round == st.round and prev.board[c] == seat
    if st.board[c] == seat and not had then
      local mine = forward and sentIn(s, "mark", c, st.round)
      if mine then
        ns.Member.mine(s, { k = "mark", c = c }) -- shown: no later event may pass for it
      elseif not timeout then
        return true
      end
      timeout = timeout and mine
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

-- Which turn of its game a state stands at (two states of one game at the
-- same key and seat: the same turn) -> number | nil
local function turnKey(st)
  if type(st) ~= "table" then return nil end
  if st.rolls then return #st.rolls end
  if not st.board then return nil end
  local n = 0
  for c = 1, 9 do
    if st.board[c] ~= 0 then n = n + 1 end
  end
  return st.round * 10 + n
end

-- A snapshot replaced my state (how: see Member.adopt). The very game I hold:
-- nothing. My game carried on (or, from a changed host, one behind mine): the
-- same game, "unseen". Anything else is another game. A snapshot nobody asked
-- for that changes my game is "forged", from my own host always, from a
-- changed host unless it is a prefix (F21); one I asked for or logged in with
-- is "unseen". Its Death Roll state must say staked (Member.adopt set mine).
-- The foul of a game that was running here stays, whatever the snapshot (the
-- host can make me ask for one at will: a TCK or a gap); Rolls' adopted
-- judged the rolls it brought in my name. The clock of my turn is my own (a).
ns.Ext.stakes.adopted = function(s, prev, m, how)
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
  if held and s.seats[held] ~= me then Stakes.stood(s, held, nil, true, prev and prev.max) end
  if how.sat then s.stakeRefill = "filled" end -- my own sit filled the seat
  if s.mySeat and (how.req or (how.sat and not how.fresh)) then Stakes.sent(s, { k = "sit" }) end -- my own SIT took me in
  local t = s.stakeTurn
  local sameTurn = cont and on and t ~= nil and t.seat == st.turn and turnKey(prev) == turnKey(st)
  refresh(s, not cont, not sameTurn, how)
  if kept then Stakes.foul(s, kept) end
  s.stakeHost, t = s.host, s.stakeTurn
  s.turnAt = t and t.seat == s.mySeat and t.at or nil
end

-- A start no honest host plays now (a member's check, before the event's
-- refresh): a game ran; Морски шах (no host start) at a live table; a
-- host-started game inside the break.
function Stakes.badStart(s)
  local engine = s:engine()
  if s.stakeLive or (engine.start ~= "host" and (s.stakeStatus == "live" or (s.stakeHad and s.stakeRefill ~= "filled"))) then
    return true
  end
  return engine.start == "host" and s.stakeEndedAt ~= nil
    and s.client.env.now() < s.stakeEndedAt + C.STAKE_BREAK - C.AUTO_GRACE
end
