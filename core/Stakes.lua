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
--           host-started game (engine.start "host", the one Session:canStart
--           gates) that began earlier than STAKE_BREAK after the last ended
--           by my clock (a member's check);
--   roll    an idle stand of my seat after my client saw its own roll on that
--           turn (the host ignored it);
--   stand   my seat stood up while my client ran and I did not ask, unless an
--           idle stand my own clock agrees with;
--   unseen  a snapshot I asked for or logged in with brought me into the game,
--           or one from a changed host is a prefix of my game (or mine of it).
-- Fouls are reset when a new game begins; a foul raised by the event that
-- begins a game is set after the reset, so it counts against that game.
-- Death Roll's rolls are judged by Rolls.audit, not here.
--
-- Session fields (local, never sent):
--   stakeLive    a game runs (live, a state, not over); recomputed at the end of every hook
--   stakeRoster  seat -> name of who plays the running game, taken when it begins
--                (the seats engine.playing accepts); nil while none runs
--   stakeFoul    nil | "forged" | "roll" | "stand" | "unseen"
--   stakePend    the foul of the event being handled, set at the end of the hook
--   stakeTurn    {seat, at}: the seat on turn and my env.now() when it came on turn
--   stakeEndedAt my env.now() when the last game ended (Session:canStart's "break")
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

-- Is every other seated player in my group -> bool (a GUID Presence does not
-- know counts as outside). Session:canStart's "group".
function Stakes.grouped(s)
  local client = s.client
  local env = client.env
  for i = 1, #s.seats do
    local name = s.seats[i]
    if name and name ~= env.me then
      local peer = client.presence:get(name)
      if not (peer and peer.guid and env.inGroup(peer.guid) == true) then return false end
    end
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
-- snapshot of another game) the roster is taken and the foul cleared; then
-- the foul of the event; the turn (`moved`: a game action restarts it) and
-- the idle timer.
local function refresh(s, fresh, moved)
  local now, on = s.client.env.now(), running(s)
  if on and (fresh or not s.stakeLive) then
    s.stakeRoster, s.stakeFoul, s.stakeTurn = roster(s), nil, nil
  elseif not on then
    if s.stakeLive then s.stakeEndedAt = now end
    s.stakeRoster, s.stakeTurn = nil, nil
  end
  s.stakeLive = on
  if s.stakePend then Stakes.foul(s, s.stakePend); s.stakePend = nil end
  local turn, t = on and s.state.turn or nil, s.stakeTurn
  if not turn then
    s.stakeTurn = nil
  elseif moved or not t or t.seat ~= turn then
    s.stakeTurn = { seat = turn, at = now }
  end
  if s.stakeTurn ~= t then armIdle(s) end
end

-- My seat went while a game runs and I did not ask (`why`: the stand's, nil
-- when only my host's SNO "gone" told me): "stand", unless an idle stand
-- (engine.idle) my own clock agrees with: my seat on turn for
-- OFFLINE_STAND_SECONDS, AUTO_GRACE left for the transport. After my own roll
-- on that turn at its max (Rolls: s.myRoll) an idle stand is "roll".
local function stood(s, why)
  if not s.stakeLive or s.role == "host" then return end
  local t, now = s.stakeTurn, s.client.env.now()
  local idle = s:engine().idle and why ~= "offline" and why ~= "left"
  local mine = idle and t and t.seat == s.mySeat
  if mine and s.myRoll and s.myRoll.max == s.state.max then return pend(s, "roll") end
  if not (mine and now >= t.at + C.OFFLINE_STAND_SECONDS - C.AUTO_GRACE) then pend(s, "stand") end
end

-- Does game state a lead to b in one game (b is a, or a later point of it)?
-- Death Roll: the same start, a's rolls are b's first rolls. Морски шах: the
-- same round with a's marks on b's board, or the next round after a's ended.
local function leadsTo(a, b)
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

-- A snapshot replaced my state (how: see Member.adopt). The very game I hold:
-- nothing. My game carried on (or, from a changed host, one behind mine): the
-- same game, "unseen". Anything else is another game. A snapshot nobody asked
-- for that changes my game is "forged", from my own host always, from a
-- changed host unless it is a prefix (F21); one I asked for or logged in with
-- is "unseen". Its Death Roll state must say staked (Member.adopt set mine).
local function adopted(s, prev, m, how)
  local st, was, on = s.state, s.stakeLive, running(s)
  if s:engine().idle and type(m.st) == "table" and m.st.staked ~= true then pend(s, "forged") end
  local identical = prev ~= nil and st ~= nil and same(prev, st) and was == on
  local cont = identical or leadsTo(prev, st) or (how.changed and leadsTo(st, prev))
  if not identical and (was or on) then
    local pushed = not (how.changed or how.asked or how.fresh)
    pend(s, (pushed or (how.changed and not how.asked and not cont)) and "forged" or "unseen")
  end
  refresh(s, not cont)
end

ns.Ext.stakes = {
  applied = function(s, seat, a)
    if seat == 0 and a.k == "start" and s.role ~= "host" and s:engine().start == "host" and s.stakeEndedAt
        and s.client.env.now() < s.stakeEndedAt + C.STAKE_BREAK then
      pend(s, "forged") -- the host gave no break: whoever wanted to leave could not
    elseif seat == 0 and a.k == "stand" and a.seat == s.mySeat then
      stood(s, a.why)
    end
    refresh(s, false, seat ~= 0)
  end,
  forged = function(s) pend(s, "forged") end, -- the event is applied (or refused) next
  refused = function(s)
    pend(s, "forged")
    refresh(s)
  end,
  adopted = adopted,
  hostChanged = armIdle, -- the idle stand is the host's: armed, or cancelled
  leaving = function(s) refresh(s) end,
  -- Member: my host says I am not at its table any more (SNO "gone"), before my session ends.
  gone = function(s)
    stood(s, nil)
    refresh(s)
  end,
}
