local _, ns = ...

-- When a staked game may begin: the break after the last one (Stakes.gap,
-- Session:canStart's "break"), a member's checks of a start (Stakes.began,
-- Stakes.badStart; core/Stakes.lua calls them through ns.Stakes) and the host's
-- held start of an `again` table that filled up again (the hook `hold`, which
-- Session:startIfFull asks at a staked table). The next match of Сантасе,
-- Белот and Табла waits STAKE_BREAK_MATCH: staying seated through it is the
-- acceptance of that match; a start earlier than that by my clock (AUTO_GRACE
-- left for the transport) is forged against it. An end that a snapshot brought
-- me is dated by its arrival: the host's own break may be over by then, so a
-- start earlier than mine is a question ("unseen"), never clean.
-- Session fields (local, never sent):
--   holdTimer      host: the held start, tried again when it fires
--   stakeHoldFrom  env.now() when my client took up (by a snapshot, or by
--                  becoming its host) a table whose game was over and whose end
--                  my client never held live (stakeEndedAt nil): the break runs from then
local Stakes = ns.Stakes

local C = ns.Const
local pend, sentIn = Stakes.pend, Stakes.sentIn

local HOLD_RECHECK = 5 -- s: a held start waits this long for a silent seat, again and again

-- The break after a game of s's engine -> seconds.
function Stakes.gap(s)
  return s:engine().again and C.STAKE_BREAK_MATCH or C.STAKE_BREAK
end

-- A game begins on my client (Stakes' refresh, before the reset; `snap`: by a
-- snapshot). Морски шах (no host start) seats a member in a new match only
-- by its own sit or its own „Реванш“ since the last one began. Only one of
-- this session makes the start clean: one a login took up (a host can replay
-- the state it was saved at), or none while my log is in doubt, makes it a
-- question ("unseen"), neither forged nor clean. A later match of an `again`
-- table rests on the break (badStart), not on my log.
function Stakes.began(s, snap)
  local seat, engine = s.mySeat, s:engine()
  if s.role == "host" or engine.start == "host" or (snap and snap.fresh) then return end
  if engine.again and s.stakeHad then return end
  if not seat or s.seats[seat] ~= s.client.env.me then return end
  if sentIn(s, "rematch", nil, nil, true) or sentIn(s, "sit", nil, nil, true) then return end
  pend(s, (s.stakeDoubt or sentIn(s, "rematch") or sentIn(s, "sit")) and "unseen" or "forged")
end

-- A start no honest host plays now (a member's check, before the event's
-- refresh): a game ran; at a live table one the host does not start (Морски
-- шах; an `again` table's start after a leave, before my client saw the seat
-- filled again by a sit); a host-started game, or any match of an `again`
-- table, inside the break by my clock -> "forged" | "unseen" (that break is
-- dated by a snapshot's arrival, s.stakeEndSnap) | nil.
function Stakes.badStart(s)
  local engine = s:engine()
  if s.stakeLive then return "forged" end
  local hosted = engine.start == "host" or (engine.again and s.stakeStatus == "live") -- the host's start
  if not hosted and (s.stakeStatus == "live" or (s.stakeHad and s.stakeRefill ~= "filled")) then return "forged" end
  if not (hosted or engine.again) then return nil end
  local early = s.stakeEndedAt ~= nil and s.client.env.now() < s.stakeEndedAt + Stakes.gap(s) - C.AUTO_GRACE
  return early and (s.stakeEndSnap and "unseen" or "forged") or nil
end

-- Host: the held start is tried again in `wait` s (replacing the one armed),
-- while this is still my session and I host it; a start is announced.
local function arm(s, wait)
  if s.holdTimer then s.holdTimer.cancel(); s.holdTimer = nil end
  local client = s.client
  s.holdTimer = client:after(math.max(0, wait), function()
    s.holdTimer = nil
    if client.session ~= s or s.role ~= "host" then return end
    local was = s.status
    s:startIfFull()
    if s.status ~= was then s:recordChanged() end
  end)
end

-- The hold of s's next start -> seconds left, and the name of a silent seated player
-- the start waits for (seconds > 0: no start of any kind, the
-- host's „Нова игра“ (Session:canStart's "break") nor the held one): the rest
-- of the break (from my end of the last game, or from s.stakeHoldFrom); at an
-- `again` table at least HOLD_RECHECK while a seated player other than me has
-- been silent for SILENT_AFTER (Succession's sweep stands it up in time: the
-- table is then short, and the old host of a takeover is never seated in a
-- match it does not hear begin).
function Stakes.held(s)
  local env = s.client.env
  local now, wait = env.now(), 0
  local from = s.stakeEndedAt or s.stakeHoldFrom
  if from then wait = from + Stakes.gap(s) - now end
  if not s:engine().again then return wait end
  local silent
  for name, at in pairs(s.lastHeard or {}) do
    if name ~= env.me and ns.Util.contains(s.seats, name) and now - at >= C.SILENT_AFTER and (not silent or name < silent) then wait, silent = math.max(wait, HOLD_RECHECK), name end
  end
  return wait, silent
end

-- Host (Session:startIfFull at a staked table) -> true: the start of an
-- `again` table waits while Stakes.held, and is tried again then.
function ns.Ext.stakes.hold(s)
  if not s:engine().again then return end
  local wait = Stakes.held(s)
  if wait <= 0 then return end
  arm(s, wait)
  return true
end

-- A snapshot showed me a game over that my client never held live: the break runs from now.
-- Before that: a snapshot of the very game I hold (the same state, still running) that puts
-- another name in a seat of its roster. No honest table does that (a seat changes hands only
-- through a stand, which changes the game): from my own host it is forged, from a host new to
-- me a question. Whatever names the table shows, my debts go by my roster (Book:settle).
local adopted = ns.Ext.stakes.adopted
ns.Ext.stakes.adopted = function(s, prev, m, how)
  if s.stakeLive and prev ~= nil and Stakes.running(s) and ns.Util.same(prev, s.state) then
    for seat, name in pairs(s.stakeRoster or {}) do
      if type(s.seats[seat]) == "string" and s.seats[seat] ~= name then pend(s, how.moved and "unseen" or "forged") end
    end
  end
  adopted(s, prev, m, how)
  if s:engine().again and s.stakeEndedAt == nil and s:gameOver() then s.stakeHoldFrom = s.client.env.now() end
end

-- I became the host of an `again` table: a game over whose end my clock did
-- not date holds a full break from now; a table that is not live tries its
-- start when the rest of the break is over (the start an old host held is not lost).
local hostChanged = ns.Ext.stakes.hostChanged
ns.Ext.stakes.hostChanged = function(s)
  local changed = s.stakeHost ~= s.host
  hostChanged(s)
  if not (changed and s.role == "host" and s:engine().again) then return end
  local now = s.client.env.now()
  if s.stakeEndedAt == nil and s:gameOver() then s.stakeHoldFrom = now end
  local from = s.stakeEndedAt or s.stakeHoldFrom
  if s.status ~= "live" then arm(s, from and from + Stakes.gap(s) - now or 0) end
end
