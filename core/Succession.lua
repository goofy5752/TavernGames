local _, ns = ...

-- Who hosts a table when its host leaves or goes silent, and how every client
-- ends up agreeing on it. Works on Session objects (core/Session.lua).
--
-- Host side: `lastHeard` per member; a seated player silent for
-- OFFLINE_STAND_SECONDS is stood up ("offline"), a watcher silent for
-- SILENT_AFTER is dropped. A host that stands hands the table over with HND.
-- Member side: `hostHeard`; after SILENT_AFTER the session is `hostSilent`, and
-- the seated candidate of rank k claims the table CLAIM_STAGGER * k seconds later.
-- Convergence: Succession.authority decides whose TBL/SNP/TCK is followed.
--
-- A member that changed host without a snapshot is `stale`: it applies no EV and
-- keeps asking the new host (SYN when seated, WAT when watching) until an SNP
-- arrives, because a sequence number means nothing across epochs.
local Succession = {}
ns.Succession = Succession

local C = ns.Const
local byteLess, seatOf = ns.Util.byteLess, ns.Util.seatOf

local function cancel(s, key)
  if s[key] then s[key].cancel(); s[key] = nil end
end

-- Seated players in ascending seat order, without the old host.
function Succession.candidates(seats, oldHost)
  local out = {}
  for i = 1, #seats do
    local name = seats[i]
    if name and name ~= oldHost then out[#out + 1] = name end
  end
  return out
end

-- Host: whom my stand hands the table to -> the first candidate heard within
-- PING_EVERY + SYN_MIN_GAP (a member pings every PING_EVERY), else the first
-- candidate. A seat whose client is cut off would miss the HND while the others
-- follow it, and once it claims by silence they take up the state it holds:
-- every event since it was cut off, lost (e2e soak).
function Succession.heir(s, me)
  local list, now = Succession.candidates(s.seats, me), s.client.env.now()
  for _, name in ipairs(list) do
    local at = s.lastHeard and s.lastHeard[name]
    if at and now - at <= C.PING_EVERY + C.SYN_MIN_GAP then return name end
  end
  return list[1]
end

-- Of two hosts at the same epoch: the one in the lower seat. An unseated name
-- loses to a seated one; two unseated names fall back to byte order.
function Succession.wins(seats, hostA, hostB)
  local a, b = seatOf(seats, hostA), seatOf(seats, hostB)
  if a and b then return a <= b and hostA or hostB end
  if a or b then return a and hostA or hostB end
  return byteLess(hostB, hostA) and hostB or hostA
end

-- A cut-off seat (e2e soak): a seat whose client hears nothing for SILENT_AFTER
-- claims the table from the state it holds, while the host it lost may be alive
-- and the others still at it. Its higher epoch used to win, and every client
-- took up its stale state: the events since it was cut off (moves, settled
-- hands, their ledger entries) undone. So a host tells whether a seated member
-- spoke to it lately, f (Succession.followed), and a host that took the table
-- over also where its epoch began, b = {e, q} (the epoch my seq counted in and
-- that seq, s.base). A seat that holds a later event of that line than b
-- (Succession.behind) follows no such host while nobody follows it, when it
-- still hears its own table (a member: its host is not silent; a host: a member
-- spoke to it lately); and such a host, hearing the host it took over from,
-- followed by others, play past b (TCK) or announce the table at b's epoch
-- without my seat (TBL: it stood me up), gives the table back
-- (Succession.yields). Two hosts nobody follows (two players cut from each
-- other) end as before: the claimant keeps the table. A host that is really
-- gone leaves its members silent: they follow the claimant as before, behind
-- or not. Without b and f (an older client) the epochs decide as before.

-- The epoch my seq counts in: a member that follows a new host without its
-- snapshot yet (stale) still holds the old epoch's events.
local function heldEpoch(s) return s.stale and s.staleE or s.epoch end

-- Does a host whose epoch began at b miss events I hold -> bool. A host that
-- took the table over itself holds, of that line, what it held then (s.base).
function Succession.behind(s, b)
  if type(b) ~= "table" or type(b.e) ~= "number" or type(b.q) ~= "number" then return false end
  local mine = s.role == "host" and s.base
  local e, q = mine and mine.e or heldEpoch(s), mine and mine.q or s.seq
  return b.e < e or (b.e == e and b.q < q)
end

-- Host: has a seated member spoken to me (PNG, SYN, ACT: s.memberHeard, since
-- I took the table over) within SILENT_AFTER -> bool.
function Succession.followed(s)
  local now = s.client.env.now()
  for name, at in pairs(s.memberHeard or {}) do
    if seatOf(s.seats, name) and now - at < C.SILENT_AFTER then return true end
  end
  return false
end

-- The fields f and b of my TBL, SNP and TCK as host: both once I took the table
-- over (s.base), f alone once I heard another host of my table (s.rival); none
-- otherwise (a table that never forked sends what it always sent).
function Succession.mark(s, m)
  if s.base or s.rival then m.f = Succession.followed(s) end
  if s.base then m.b = { e = s.base.e, q = s.base.q } end
  return m
end

-- Host: another host of my table spoke (a TBL or TCK I do not follow): mine say f from now on.
function Succession.rival(s, kind)
  if s.role == "host" and kind == nil then s.rival = true end
end

-- Was the host of message m cut off from a table I still hear (see above) -> bool.
local function cutOff(s, m)
  if not s.mySeat or type(m) ~= "table" or m.f ~= false or not Succession.behind(s, m.b) then return false end
  if s.role == "host" then return Succession.followed(s) end
  return s.client.env.now() - (s.hostHeard or 0) <= C.PING_EVERY + C.SYN_MIN_GAP -- my host spoke lately
end

-- What `sender`, speaking as a host at `epoch` (TBL, SNP or TCK `m`), is to session s:
--   "current"  my host at my epoch;
--   "new"      a seated sender with a higher epoch, or at my epoch winning the
--              seat-order tie against my host: to be followed (not when it was
--              cut off from a table I still hear: see above);
--   nil        anything else (lower epoch, not seated, tie lost): ignored.
function Succession.authority(s, sender, epoch, m)
  if type(epoch) ~= "number" or epoch < s.epoch then return nil end
  if epoch == s.epoch and sender == s.host then return "current" end
  if not seatOf(s.seats, sender) then return nil end
  if epoch == s.epoch and Succession.wins(s.seats, s.host, sender) ~= sender then return nil end
  if cutOff(s, m) then return nil end
  return "new"
end

-- Host that took the table over and that nobody follows: `sender`, the host of
-- the epoch my claim came from, still plays it past my base (its TCK m at that
-- epoch, followed by others, m.f, m.q past it; or its TBL m at that epoch, its
-- seats without me: it stood me up)
-- -> true: I was the one cut off; I follow it again.
function Succession.yields(s, sender, m)
  local b = s.base
  if s.role ~= "host" or not b or Succession.followed(s) or sender ~= s.claimedFrom or m.e ~= b.e then return false end
  local seats = m.t == "TBL" and type(m.s) == "table" and m.s or nil
  if seats then
    if seatOf(seats, s.client.env.me) then return false end
  elseif m.f ~= true or type(m.q) ~= "number" or m.q <= b.q then
    return false
  end
  Succession.follow(s, sender, m.e, seats)
  s.yielded = true -- its snapshot may show my seat stood up offline: no foul of that host's (core/StakesWatch.lua)
  s:requestSync()
  return true
end

---------------------------------------------------------------------------
-- Host side: silent members
---------------------------------------------------------------------------

-- A host that claimed the table by silence and that no member (seat or watcher)
-- has spoken to since: it may well be the one cut off (e2e soak: such a host stood
-- every other seat up "offline" and wrote their settlements as debts to it, for
-- a game the table never had). It stands no seat up until somebody speaks to it,
-- and plays no other seat's timeout (Session:armTimers).
local function alone(s) return s.claimedFrom ~= nil and next(s.memberHeard or {}) == nil end
Succession.alone = alone

-- One timer for the member whose limit runs out first (alone: a seat's, looked at again every PING_EVERY).
function Succession.armSweep(s)
  cancel(s, "sweepTimer")
  local now, wait, lone = s.client.env.now(), nil, alone(s)
  for name, at in pairs(s.lastHeard) do
    local seated = seatOf(s.seats, name)
    local limit = seated and C.OFFLINE_STAND_SECONDS or C.SILENT_AFTER
    local w = at + limit - now
    if seated and lone then w = math.max(w, C.PING_EVERY) end
    if not wait or w < wait then wait = w end
  end
  if not wait then return end
  s.sweepTimer = s.client:after(math.max(wait, 0), function()
    s.sweepTimer = nil
    Succession.sweep(s)
  end)
end

function Succession.sweep(s)
  local now, changed, stood, lone = s.client.env.now(), false, false, alone(s)
  for i = 1, #s.seats do
    local name = s.seats[i]
    local at = name and s.lastHeard[name]
    if at and not lone and now - at >= C.OFFLINE_STAND_SECONDS then
      s.lastHeard[name] = nil
      s:event(0, { k = "stand", seat = i, why = "offline" })
      changed, stood = true, true
    end
  end
  if stood then s:abortIfShort() end
  for name in pairs(s.lastHeard) do if not seatOf(s.seats, name) and not s.watcherSet[name] then s.lastHeard[name] = nil end end
  local silent = {}
  for name in pairs(s.watcherSet) do
    if now - (s.lastHeard[name] or now) >= C.SILENT_AFTER then silent[#silent + 1] = name end
  end
  for i = 1, #silent do
    s.watcherSet[silent[i]], s.lastHeard[silent[i]] = nil, nil
    s.watchers = s.watchers - 1
    changed = true
  end
  if changed then s:recordChanged() end
  Succession.armSweep(s)
end

-- `name` sat down or started watching: heard just now.
function Succession.track(s, name)
  s.lastHeard[name] = s.client.env.now()
  Succession.armSweep(s)
end

-- `name` is no longer at the table.
function Succession.untrack(s, name)
  s.lastHeard[name] = nil
end

---------------------------------------------------------------------------
-- Member side: silent host
---------------------------------------------------------------------------

local function armSilence(s, wait)
  cancel(s, "silenceTimer")
  s.silenceTimer = s.client:after(wait, function()
    s.silenceTimer = nil
    local client = s.client
    local quiet = client.env.now() - s.hostHeard
    if quiet >= C.SILENT_AFTER and not s.hostSilent then
      s.hostSilent = true
      ns.Session.emit(client)
    end
    local rank = seatOf(Succession.candidates(s.seats, s.host), client.env.me)
    -- Seated: my turn to claim. Watching: the table is given up with its lobby record.
    local due = rank and (C.SILENT_AFTER + C.CLAIM_STAGGER * (rank - 1)) or C.TBL_EXPIRE
    if quiet >= due then
      if rank then return Succession.claim(s) end
      return ns.Session.leave(client)
    end
    armSilence(s, (quiet < C.SILENT_AFTER and C.SILENT_AFTER or due) - quiet)
  end)
end

-- (Re)starts the silence clock: the host counts as heard now.
function Succession.watchHost(s)
  s.hostHeard, s.hostSilent = s.client.env.now(), false
  armSilence(s, C.SILENT_AFTER)
end

-- Any v=1 message `m` from `sender`, before it is handled. A HI from my host
-- that names another table (or none) comes from a client that no longer runs
-- mine, e.g. after a reload: the silence clock keeps running.
function Succession.heard(s, sender, m)
  local now = s.client.env.now()
  if s.role == "host" then
    if s.lastHeard[sender] then s.lastHeard[sender] = now end
    if m.tid == s.tid and (m.t == "PNG" or m.t == "SYN" or m.t == "ACT") then
      s.memberHeard = s.memberHeard or {}
      s.memberHeard[sender] = now
    end
  elseif sender == s.host and not (m.t == "HI" and m.at ~= s.tid) then
    s.hostHeard = now
    if s.hostSilent then
      s.hostSilent = false
      ns.Session.emit(s.client)
    end
  end
end

---------------------------------------------------------------------------
-- Changing host
---------------------------------------------------------------------------

-- Member -> host at s.epoch (already raised by the caller), from my own state.
-- Every seated player gets an SNP; watchers are unknown to a member, so they
-- come back with WAT when they see the TBL. `oldHost` keeps its seat and, when
-- `oldHeard` is given, its offline clock runs from that moment. `base`: where my
-- epoch begins, {e, q} (s.base; see Succession.behind).
local function becomeHost(s, oldHost, oldHeard, base)
  local client = s.client
  local me, now = client.env.me, client.env.now()
  s.base, s.memberHeard = base, {}
  cancel(s, "pingTimer")
  cancel(s, "silenceTimer")
  s.role, s.host = "host", me
  s.hostSilent, s.stale, s.lastSyn = false, nil, nil
  s.watcherSet, s.watchers = {}, 0
  -- The invited set came with the snapshot (and the HND); whoever already sits
  -- here, and the old host, may come back too.
  s.invited = s.invited or {}
  if oldHost then s.invited[oldHost] = true end
  s.lastHeard = {}
  for i = 1, #s.seats do
    local name = s.seats[i]
    if name and name ~= me then
      s.invited[name] = true
      s.lastHeard[name] = (name == oldHost and oldHeard) or now
    end
  end
  if s.status == "live" and s:seatedCount() < s:engine().minSeats then s:applyUnsent(0, { k = "abort" }) end
  s:hook("hostChanged")
  s:armTimers() -- a fresh full turn
  local members = s:members()
  for i = 1, #members do s:snapshotTo(members[i]) end
  s:scheduleTick()
  Succession.armSweep(s)
  s:recordChanged()
end

-- The host went silent and it is my turn among the candidates. A seat whose
-- stake I was asked about and did not accept (s.stakeAsk, ns.Stake.ask) never
-- hosts, here or by a handoff: a host starts the next game itself. It stands
-- up instead, and the next candidate claims in its turn.
function Succession.claim(s)
  if s.stakeAsk then return ns.Stake.standUp(s.client, s) end
  local oldHost, oldHeard = s.host, s.hostHeard
  local base = { e = heldEpoch(s), q = s.seq }
  s.epoch = s.epoch + 1
  becomeHost(s, oldHost, oldHeard, base)
  s.claimedFrom = oldHost
end

-- Host -> member of somebody else's epoch.
function Succession.demote(s)
  local client = s.client
  cancel(s, "announceTimer"); cancel(s, "heartbeatTimer"); cancel(s, "tickTimer")
  cancel(s, "turnTimer"); cancel(s, "systemTimer"); cancel(s, "sweepTimer")
  s.role = s.mySeat and "player" or "watcher"
  s.watcherSet, s.lastHeard, s.lastAnnounce, s.deadline = nil, nil, nil, nil
  s.base, s.memberHeard, s.claimedFrom, s.rival = nil, nil, nil, nil
  client.lobby:remove(s.tid) -- no longer my own record; the new host's TBL lists it again
  s:schedulePing()
end

-- `host` is my host from now on, at `epoch`; my state waits for its snapshot.
-- `seats` (the new host's record, when known) tells whether I still hold my seat.
function Succession.follow(s, host, epoch, seats)
  if seats and s.mySeat and seats[s.mySeat] ~= s.client.env.me then s.mySeat = nil end
  if not s.stale then s.staleE = s.epoch end -- the epoch my seq counts in until the snapshot
  if s.role == "host" then Succession.demote(s) end
  s.role = s.mySeat and "player" or "watcher"
  s.host, s.epoch, s.stale, s.lastSyn = host, epoch, true, nil
  s:hook("hostChanged")
  Succession.watchHost(s)
  ns.Session.emit(s.client)
end

-- The host stands with `to` (the first candidate) still seated: its own stand
-- as the last event of the epoch, HND to every member, then it is gone.
function Succession.handoff(s, to)
  local client = s.client
  s:event(0, { k = "stand", seat = s.mySeat, why = "left" })
  s:abortIfShort()
  local m = { v = C.PROTOCOL, t = "HND", tid = s.tid, e = s.epoch + 1, to = to, inv = s:invitedList() }
  local members = s:members()
  for i = 1, #members do client:send("WHISPER", members[i], m) end
  client.lobby:remove(s.tid)
  ns.Session.leave(client)
end

-- HND, honoured only from my current host (it has just stood up, so the seat
-- rule cannot apply to it). Named: I take over. Otherwise I follow `to`, whose
-- SNP (seated) or TBL (watching) brings the state.
function Succession.onHandoff(client, sender, m)
  local s = client.session
  if not s or s.tid ~= m.tid or s.role == "host" or s.host ~= sender then return end
  if type(m.e) ~= "number" or m.e <= s.epoch or type(m.to) ~= "string" or m.to == sender then return end
  if m.to ~= client.env.me then
    s.handed = true -- its first snapshot is a new host's (Member.adopt)
    return Succession.follow(s, m.to, m.e)
  end
  if not s.mySeat then return end -- watchers never become host
  if s.stakeAsk then return ns.Stake.standUp(client, s) end -- nor an asked seat (Succession.claim)
  local seat = seatOf(s.seats, sender)
  if seat then s:applyUnsent(0, { k = "stand", seat = seat, why = "left" }) end -- its stand never reached me
  local base = { e = heldEpoch(s), q = s.seq }
  s.epoch = m.e
  s.invited = s.invited or {}
  s:addInvited(m.inv) -- invitations sent after my snapshot
  becomeHost(s, sender, nil, base)
end

-- TBL about my table from somebody claiming to host it.
function Succession.onTable(client, channel, sender, m)
  local s = client.session
  if not s or s.tid ~= m.tid or not ns.Lobby.valid(m) or m.h ~= sender then return end
  local kind = Succession.authority(s, sender, m.e, m)
  if kind == nil and Succession.yields(s, sender, m) then return client.lobby:receive(channel, sender, m) end
  Succession.rival(s, kind)
  if kind == "new" then
    local wasHost = s.role == "host"
    Succession.follow(s, sender, m.e, m.s)
    if wasHost then client.lobby:receive(channel, sender, m) end
    s:requestSync()
  elseif kind == "current" and s.stale then
    s:requestSync()
  end
end
