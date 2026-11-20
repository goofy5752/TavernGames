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

-- Of two hosts at the same epoch: the one in the lower seat. An unseated name
-- loses to a seated one; two unseated names fall back to byte order.
function Succession.wins(seats, hostA, hostB)
  local a, b = seatOf(seats, hostA), seatOf(seats, hostB)
  if a and b then return a <= b and hostA or hostB end
  if a or b then return a and hostA or hostB end
  return byteLess(hostB, hostA) and hostB or hostA
end

-- What `sender`, speaking as a host at `epoch` (TBL, SNP or TCK), is to session s:
--   "current"  my host at my epoch;
--   "new"      a seated sender with a higher epoch, or at my epoch winning the
--              seat-order tie against my host: to be followed;
--   nil        anything else (lower epoch, not seated, tie lost): ignored.
function Succession.authority(s, sender, epoch)
  if type(epoch) ~= "number" or epoch < s.epoch then return nil end
  if epoch == s.epoch and sender == s.host then return "current" end
  if not seatOf(s.seats, sender) then return nil end
  if epoch == s.epoch and Succession.wins(s.seats, s.host, sender) ~= sender then return nil end
  return "new"
end

---------------------------------------------------------------------------
-- Host side: silent members
---------------------------------------------------------------------------

-- One timer for the member whose limit runs out first.
function Succession.armSweep(s)
  cancel(s, "sweepTimer")
  local now, wait = s.client.env.now(), nil
  for name, at in pairs(s.lastHeard) do
    local limit = seatOf(s.seats, name) and C.OFFLINE_STAND_SECONDS or C.SILENT_AFTER
    local w = at + limit - now
    if not wait or w < wait then wait = w end
  end
  if not wait then return end
  s.sweepTimer = s.client:after(math.max(wait, 0), function()
    s.sweepTimer = nil
    Succession.sweep(s)
  end)
end

function Succession.sweep(s)
  local now, changed, stood = s.client.env.now(), false, false
  for i = 1, #s.seats do
    local name = s.seats[i]
    local at = name and s.lastHeard[name]
    if at and now - at >= C.OFFLINE_STAND_SECONDS then
      s.lastHeard[name] = nil
      s:event(0, { k = "stand", seat = i, why = "offline" })
      changed, stood = true, true
    end
  end
  if stood then s:abortIfShort() end
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
-- `oldHeard` is given, its offline clock runs from that moment.
local function becomeHost(s, oldHost, oldHeard)
  local client = s.client
  local me, now = client.env.me, client.env.now()
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
  if s.status == "live" and s:seatedCount() < s:engine().minSeats and s:apply(0, { k = "abort" }) then
    s.seq = s.seq + 1
  end
  s:armTimers() -- a fresh full turn
  local members = s:members()
  for i = 1, #members do s:snapshotTo(members[i]) end
  s:scheduleTick()
  Succession.armSweep(s)
  s:recordChanged()
end

-- The host went silent and it is my turn among the candidates.
function Succession.claim(s)
  local oldHost, oldHeard = s.host, s.hostHeard
  s.epoch = s.epoch + 1
  becomeHost(s, oldHost, oldHeard)
end

-- Host -> member of somebody else's epoch.
function Succession.demote(s)
  local client = s.client
  cancel(s, "announceTimer"); cancel(s, "heartbeatTimer"); cancel(s, "tickTimer")
  cancel(s, "turnTimer"); cancel(s, "systemTimer"); cancel(s, "sweepTimer")
  s.role = s.mySeat and "player" or "watcher"
  s.watcherSet, s.lastHeard, s.lastAnnounce, s.deadline = nil, nil, nil, nil
  client.lobby:remove(s.tid) -- no longer my own record; the new host's TBL lists it again
  s:schedulePing()
end

-- `host` is my host from now on, at `epoch`; my state waits for its snapshot.
-- `seats` (the new host's record, when known) tells whether I still hold my seat.
function Succession.follow(s, host, epoch, seats)
  if seats and s.mySeat and seats[s.mySeat] ~= s.client.env.me then s.mySeat = nil end
  if s.role == "host" then Succession.demote(s) end
  s.role = s.mySeat and "player" or "watcher"
  s.host, s.epoch, s.stale, s.lastSyn = host, epoch, true, nil
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
  if m.to ~= client.env.me then return Succession.follow(s, m.to, m.e) end
  if not s.mySeat then return end -- watchers never become host
  local seat = seatOf(s.seats, sender)
  if seat and s:apply(0, { k = "stand", seat = seat, why = "left" }) then
    s.seq = s.seq + 1 -- its stand never reached me
  end
  s.epoch = m.e
  s.invited = s.invited or {}
  s:addInvited(m.inv) -- invitations sent after my snapshot
  becomeHost(s, sender)
end

-- TBL about my table from somebody claiming to host it.
function Succession.onTable(client, channel, sender, m)
  local s = client.session
  if not s or s.tid ~= m.tid or not ns.Lobby.valid(m) or m.h ~= sender then return end
  local kind = Succession.authority(s, sender, m.e)
  if kind == "new" then
    local wasHost = s.role == "host"
    Succession.follow(s, sender, m.e, m.s)
    if wasHost then client.lobby:receive(channel, sender, m) end
    s:requestSync()
  elseif kind == "current" and s.stale then
    s:requestSync()
  end
end
