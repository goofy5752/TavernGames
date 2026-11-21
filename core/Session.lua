local _, ns = ...

-- The table this client is at, as host or as member (player or watcher), and the
-- protocol around it. Seating: SIT/WAT/STD requests checked by the host, SNO
-- refusals, an SNP snapshot for each newcomer, the host's coalesced TBL announce.
-- Play: the host orders every table and game event (EV, q = seq + 1), checks each
-- ACT through the engine, runs the turn timer (an automatic move on expiry) and
-- the engine's system actions; members apply events strictly in order and heal a
-- gap with SYN -> SNP. Heartbeats: TCK from the host, PNG from members.
-- Offline seats, host handoff, host silence and convergence between competing
-- hosts live in core/Succession.lua; the member side (SNP, EV, TCK, SNO, END,
-- PNG/SYN) in core/Member.lua.
--
-- client.session is nil or a Session with the public fields
--   tid, role ("host"|"player"|"watcher"), mySeat, host, epoch, seq, seats,
--   state (engine state, nil until the first start),
--   status ("open"|"live"|"aborted"; "aborted" is kept until the next start),
--   deadline (env.now()-based end of the current turn, or nil),
--   hostSilent (true while a member has not heard its host for SILENT_AFTER s),
--   opt (the table options resolved by ns.Games.resolve; {} for a game without)
-- and session:record() -> TBL fields. Every change emits "session"(session|nil);
-- an EV from the host that the engine rejects emits "desync"(tid). Extensions
-- (ns.Ext), the "result" event, startGame and playAuto: core/Lifecycle.lua.
local Session = {}
Session.__index = Session
ns.Session = Session
ns.Ext = {} -- extensions by name (see Session:hook)

local C = ns.Const
local Succession = ns.Succession
local copy, byteLess, seatOf, contains = ns.Util.copy, ns.Util.byteLess, ns.Util.seatOf, ns.Util.contains
Session.seatOf = seatOf

local ACCESS = { guild = true, invite = true, group = true }

-- Point-to-point messages: honoured only when they arrive by WHISPER.
local WHISPERED = {
  SIT = true, WAT = true, STD = true, SNO = true, SNP = true, EV = true,
  ACT = true, SYN = true, PNG = true, TCK = true, HND = true, SED = true, PRV = true, PRQ = true,
}

local TIMERS = {
  "announceTimer", "heartbeatTimer", "tickTimer", "pingTimer", "turnTimer", "systemTimer",
  "sweepTimer", "silenceTimer", "fairTimer", "askTimer", "autoTimer", "stepTimer", "keysTimer", "bookTimer",
}

-- message, emit and refuse are shared with core/Member.lua and core/Succession.lua.
local function message(t, fields)
  fields.v, fields.t = C.PROTOCOL, t
  return fields
end
Session.message = message

local function emit(client)
  client.events:emit("session", client.session)
end
Session.emit = emit

local function refuse(client, tid, why)
  client.events:emit("refused", tid, why)
end
Session.refuse = refuse

function Session:cancelTimers()
  for i = 1, #TIMERS do
    local key = TIMERS[i]
    if self[key] then self[key].cancel(); self[key] = nil end
  end
end

-- The client's session ended or was left: no table, `at` cleared.
local function leave(client)
  if client.session then client.session:cancelTimers(); ns.DealKeep.clear(client.session) end
  client.session = nil
  client.presence:setAt(nil)
  emit(client)
end
Session.leave = leave

function Session:engine()
  return ns.Engines[self.game]
end

function Session:record()
  return {
    tid = self.tid, g = self.game, h = self.host, e = self.epoch, ac = self.access,
    tn = self.turn, st = self.status == "live" and "live" or "open", s = copy(self.seats),
    w = self.watchers, o = self.opt and next(self.opt) ~= nil and copy(self.opt) or nil,
  }
end

function Session:seatedCount()
  local n = 0
  for i = 1, #self.seats do
    if self.seats[i] then n = n + 1 end
  end
  return n
end

-- Seconds left on the current turn, or nil.
function Session:left()
  if not self.deadline then return nil end
  return math.max(0, self.deadline - self.client.env.now())
end

-- Ordered event (seat, a) on seats/state/status, host and members alike. Seat 0
-- carries the table events sit/stand/start/abort, an event an extension's
-- `table` hook applies, or an engine system action.
-- Returns true, or nil when the event does not fit (nothing is changed).
function Session:apply(seat, a)
  if type(a) ~= "table" then return nil end
  local engine, k = self:engine(), seat == 0 and a.k
  if k == "sit" or k == "stand" then
    if type(a.seat) ~= "number" or self.seats[a.seat] == nil then return nil end
    if k == "sit" then
      if type(a.name) ~= "string" or self.seats[a.seat] then return nil end -- never onto a taken seat
      self.seats[a.seat] = a.name
    else
      self.seats[a.seat] = false
      if self.status == "live" and self.state and engine.leave then engine.leave(self.state, a.seat) end
    end
  elseif k == "start" then
    self.state, self.status = self:newGame(a.first), "live"
  elseif k == "abort" then
    self.status, self.deadline = "aborted", nil
  else
    if self.status ~= "live" or type(seat) ~= "number" then return nil end
    if seat ~= 0 or not self:hook("table", a) then
      local trial = copy(self.state)
      if not engine.apply(trial, seat, a) then return nil end
      self.state = trial
    end
  end
  self:noteResult()
  return true
end

---------------------------------------------------------------------------
-- Host side
---------------------------------------------------------------------------

-- Everyone at the table except me: seated players, then watchers by name bytes.
function Session:members()
  local me, out = self.client.env.me, {}
  for i = 1, #self.seats do
    local name = self.seats[i]
    if name and name ~= me then out[#out + 1] = name end
  end
  local watchers = {}
  for name in pairs(self.watcherSet) do watchers[#watchers + 1] = name end
  table.sort(watchers, byteLess)
  for i = 1, #watchers do out[#out + 1] = watchers[i] end
  return out
end

function Session:sendTBL()
  local client = self.client
  if self.announceTimer then self.announceTimer.cancel(); self.announceTimer = nil end
  if self.heartbeatTimer then self.heartbeatTimer.cancel() end
  self.lastAnnounce = client.env.now()
  client:send("GUILD", nil, message("TBL", self:record()))
  self.heartbeatTimer = client:after(C.TBL_HEARTBEAT, function()
    self.heartbeatTimer = nil
    self:sendTBL()
  end)
end

-- GUILD TBL at most once per TBL_MIN_GAP; a coalesced send carries the latest record.
function Session:announce()
  if self.announceTimer then return end
  local wait = self.lastAnnounce and (self.lastAnnounce + C.TBL_MIN_GAP - self.client.env.now()) or 0
  if wait <= 0 then
    self:sendTBL()
  else
    self.announceTimer = self.client:after(wait, function()
      self.announceTimer = nil
      self:sendTBL()
    end)
  end
end

-- The host's record changed: own lobby entry, announce, "session".
function Session:recordChanged()
  self.client.lobby:set(ns.Lobby.fromTBL(self:record()))
  self:announce()
  emit(self.client)
end

-- After a game event: the engine's pending system action (one that needs
-- randomness goes to the extensions' `need`, never to play) and the turn timer,
-- whose expiry plays Engine.auto for the seat on turn; with engine.view only
-- for my own seat (another hand is played by its owner, Session:armAuto).
-- Not live: no timers.
function Session:armTimers()
  if self.turnTimer then self.turnTimer.cancel(); self.turnTimer = nil end
  if self.systemTimer then self.systemTimer.cancel(); self.systemTimer = nil end
  self.deadline = nil
  if self.status ~= "live" then return end
  local client, engine = self.client, self:engine()
  local action, delay = engine.system(self.state)
  if action then
    self.systemTimer = client:after(delay or 0, function()
      self.systemTimer = nil
      if action.need then self:hook("need", action) else self:play(0, action) end
    end)
  end
  local seat = self.state.turn
  if seat then
    self.deadline = client.env.now() + self.turn
    if engine.view and seat ~= self.mySeat and not engine.publicAuto then return end
    self.turnTimer = client:after(self.turn + (seat ~= self.mySeat and engine.view and C.AUTO_GRACE or 0), function()
      self.turnTimer = nil
      local auto = engine.auto(self.state, seat, client.env.random)
      if auto then self:play(seat, auto, true) end
    end)
  end
end

-- The next ordered event: applied, whispered to every member except `skip`, then
-- the extensions' `applied`; false when it does not apply. A sit, a stand that keeps
-- the turn, or an event an extension calls `still` leaves the running turn alone.
function Session:event(seat, a, skip, auto)
  local turn = self.state and self.state.turn
  if not self:apply(seat, a) then return false end
  self.seq = self.seq + 1
  local k = seat == 0 and a.k
  if k ~= "sit" and (k ~= "stand" or self.state and self.state.turn ~= turn) and not self:hook("still", seat, a) then self:armTimers() end
  local m = message("EV", {
    tid = self.tid, e = self.epoch, q = self.seq, seat = seat, a = a,
    auto = auto or nil, left = self:left(),
  })
  local members = self:members()
  for i = 1, #members do
    if members[i] ~= skip then self.client:send("WHISPER", members[i], m) end
  end
  self:hook("applied", seat, a)
  return true
end

-- A game action by `seat` (0 = system); dropped silently if the engine refuses it.
function Session:play(seat, a, auto)
  if self:event(seat, a, nil, auto) then emit(self.client) end
end

function Session:startIfFull()
  if self.status == "live" or self:engine().start == "host" then return end
  for i = 1, #self.seats do
    if not self.seats[i] then return end
  end
  self:event(0, { k = "start" })
end

-- Host: a live match with fewer than minSeats seated players is aborted (no
-- winner). Returns true when it emitted the abort event.
function Session:abortIfShort()
  if self.status ~= "live" or self:seatedCount() >= self:engine().minSeats then return false end
  self:event(0, { k = "abort" })
  return true
end

-- TCK{q} to every member every PING_EVERY seconds.
function Session:scheduleTick()
  self.tickTimer = self.client:after(C.PING_EVERY, function()
    self.tickTimer = nil
    local m = message("TCK", { tid = self.tid, e = self.epoch, q = self.seq })
    local members = self:members()
    for i = 1, #members do self.client:send("WHISPER", members[i], m) end
    self:scheduleTick()
  end)
end

-- The invited set of an "invite" table as a list in byte order (nil when empty),
-- so a member that becomes host keeps letting the same people in.
function Session:invitedList()
  if self.access ~= "invite" then return nil end
  local out = {}
  for name in pairs(self.invited) do out[#out + 1] = name end
  if #out == 0 then return nil end
  table.sort(out, byteLess)
  return out
end

-- Adds every string in `list` (from an SNP or HND) to the invited set.
function Session:addInvited(list)
  if type(list) ~= "table" then return end
  for i = 1, #list do
    if type(list[i]) == "string" then self.invited[list[i]] = true end
  end
end

function Session:snapshotTo(name)
  self.client:send("WHISPER", name, message("SNP", {
    tid = self.tid, e = self.epoch, q = self.seq, tbl = self:record(),
    st = self:snapshotFor(name), left = self:left(),
    inv = self:invitedList(), fr = self:hook("snap"),
  }))
end

function Session:allows(peer)
  if self.access == "guild" then return true end
  if self.access == "invite" then return self.invited[peer.name] == true end
  if self.access == "group" then return peer.guid ~= nil and self.client.env.inGroup(peer.guid) == true end
  return false
end

-- Refusal reason for a SIT/WAT from `sender`, in the spec's order, or nil.
function Session:check(sender, kind, seat)
  local peer = self.client.presence:get(sender)
  if not peer or peer.incompatible then return "version" end
  if peer.at ~= nil and peer.at ~= self.tid then return "busy" end
  if not self:allows(peer) then return "access" end
  if kind ~= "SIT" then return self.watchers >= C.MAX_WATCHERS and "full" or nil end
  if type(seat) ~= "number" or self.seats[seat] ~= false then return "taken" end
  return nil
end

function Session:onRequest(sender, kind, seat)
  -- Already here (a repeated click): just the snapshot again.
  if seatOf(self.seats, sender) or (kind == "WAT" and self.watcherSet[sender]) then
    return self:snapshotTo(sender)
  end
  -- An invitee whose seat was taken a moment ago gets another free one.
  if kind == "SIT" then seat = ns.Invites.seatFor(self, sender, seat) end
  local why = self:check(sender, kind, seat)
  if why then
    return self.client:send("WHISPER", sender, message("SNO", { tid = self.tid, why = why }))
  end
  if kind == "SIT" then
    if self.watcherSet[sender] then
      self.watcherSet[sender] = nil
      self.watchers = self.watchers - 1
    end
    self:event(0, { k = "sit", seat = seat, name = sender }, sender)
  else
    self.watcherSet[sender] = true
    self.watchers = self.watchers + 1
  end
  Succession.track(self, sender)
  self:snapshotTo(sender)
  if kind == "SIT" then self:startIfFull() end
  self:recordChanged()
end

-- A seated player leaving a live match below minSeats aborts it (no winner).
function Session:onStand(sender)
  local seat = seatOf(self.seats, sender)
  Succession.untrack(self, sender)
  if seat then
    self:event(0, { k = "stand", seat = seat, why = "left" }, sender)
    if self:seatedCount() == 0 then return self:finish() end
    self:abortIfShort()
    self:recordChanged()
  elseif self.watcherSet[sender] then
    self.watcherSet[sender] = nil
    self.watchers = self.watchers - 1
    self:recordChanged()
  end
end

function Session:onAct(sender, a)
  local seat = seatOf(self.seats, sender)
  if not seat or self.status ~= "live" or type(a) ~= "table" then return end
  a = self:filterAct(seat, a)
  if a ~= nil then self:play(seat, a) end
end

-- SYN or PNG. From somebody who is not (or no longer) at my table it is answered
-- "gone", so a player stood up as offline or a dropped watcher lets go.
function Session:onSync(sender, wantsSnapshot)
  if not seatOf(self.seats, sender) and not self.watcherSet[sender] then
    self.client:send("WHISPER", sender, message("SNO", { tid = self.tid, why = "gone" }))
  elseif wantsSnapshot then
    self:snapshotTo(sender)
  end
end

-- The last seated player is gone: END on GUILD, the session ends for everyone.
function Session:finish()
  local client = self.client
  self:cancelTimers()
  client:send("GUILD", nil, message("END", { tid = self.tid, e = self.epoch }))
  client.lobby:remove(self.tid)
  leave(client)
end

---------------------------------------------------------------------------
-- Client entry points
---------------------------------------------------------------------------

-- opts {game, access, turn, opt} -> tid | nil, code ("busy" "game" "access" "turn" "opt").
function Session.open(client, opts)
  opts = opts or {}
  if client.session then return nil, "busy" end
  local engine = ns.Games.engine(opts.game)
  if not engine then return nil, "game" end
  if not ACCESS[opts.access] then return nil, "access" end
  local turn = opts.turn == nil and C.TURN_DEFAULT or opts.turn
  if not contains(C.TURN_CHOICES, turn) then return nil, "turn" end
  local opt = ns.Games.resolve(opts.game, opts.opt)
  if not opt then return nil, "opt" end

  local env = client.env
  local tid = env.me .. "#" .. env.epoch()
  local seats = {}
  for i = 1, engine.maxSeats do seats[i] = false end
  seats[1] = env.me
  client.pending = nil
  client.session = setmetatable({
    client = client,
    tid = tid, role = "host", mySeat = 1, host = env.me, epoch = 1, seq = 0,
    seats = seats, state = nil, status = "open", deadline = nil, hostSilent = false,
    game = opts.game, access = opts.access, turn = turn, opt = opt, watchers = 0,
    watcherSet = {}, -- name -> true
    lastHeard = {},  -- member name -> env.now() of its last message
    invited = {},    -- name -> true, for access "invite" (client:invite; travels in SNP/HND)
  }, Session)
  client.presence:setAt(tid)
  client.session:scheduleTick()
  client.session:recordChanged()
  return tid
end

-- kind "SIT" (with seat) or "WAT"; the answer is an SNP or the event "refused".
-- Unanswered for PENDING_SECONDS: given up ("gone"), so a late SNP is refused.
function Session.request(client, kind, tid, seat)
  local s = client.session
  if s and (s.tid ~= tid or s.role == "host") then return refuse(client, tid, "busy") end
  local host = s and s.host
  client.gaveUp = nil
  if s then s.sitAsked, s.asked = kind == "SIT" and client.env.now() or nil, true end -- see Party.inviteFrom, Member.adopt
  if not host then
    local rec = client.lobby:get(tid)
    if not rec then return refuse(client, tid, "gone") end
    -- A game I do not have: nothing to ask for.
    if not ns.Games.engine(rec.game) then return refuse(client, tid, "version") end
    host = rec.host
    local p = { tid = tid, host = host, kind = kind }
    client.pending = p
    client:after(C.PENDING_SECONDS, function()
      if client.pending ~= p then return end
      client.pending, client.gaveUp = nil, tid
      refuse(client, tid, "gone")
    end)
  end
  local m = kind == "SIT" and { tid = tid, seat = seat } or { tid = tid }
  client:send("WHISPER", host, message(kind, m))
end

-- Stand up or stop watching; a pending request is forgotten. A host with
-- another player seated hands the table over; alone, it closes the table.
-- client.gaveUp remembers the table, so a late SNP for it is not adopted.
function Session.stand(client)
  local s, p = client.session, client.pending
  client.gaveUp = (s and s.tid) or (p and p.tid) or client.gaveUp
  client.pending = nil
  if not s then return end
  if s.role == "host" then
    local successor = Succession.candidates(s.seats, client.env.me)[1]
    if successor then return Succession.handoff(s, successor) end
    return s:finish()
  end
  client:send("WHISPER", s.host, message("STD", { tid = s.tid }))
  leave(client)
end

-- The client stops (logout or /reload): nobody stands up. A seated player keeps
-- the seat for the offline window and gets the table back from the host's
-- snapshot when he returns; a host's players claim the table after the silence.
-- Only a host with nobody else seated closes its table, since nobody could hand
-- it back. A pending request is forgotten.
function Session.stop(client)
  local s = client.session
  client.pending = nil
  if s and s.role == "host" and not Succession.candidates(s.seats, client.env.me)[1] then s:finish() end
end

-- A move by my seat -> true | nil, code: "none" (no table), "seat" (not seated),
-- "live" (no match running) or the engine's refusal ("turn", "cell", ...).
-- Checked on a copy first; the host applies it at once, a guest sends ACT.
function Session.act(client, a)
  local s = client.session
  if not s then return nil, "none" end
  if not s.mySeat then return nil, "seat" end
  if s.status ~= "live" then return nil, "live" end
  local ok, code = s:engine().apply(copy(s.state), s.mySeat, a)
  if not ok then return nil, code end
  if s.role == "host" then
    s:play(s.mySeat, a)
  else
    ns.Member.sendAct(s, a)
  end
  return true
end

-- Spec 6.2: a SIT/WAT of another protocol version for a table I host.
function Session.refuseVersion(client, sender, tid)
  local s = client.session
  if s and s.role == "host" and s.tid == tid then
    client:send("WHISPER", sender, message("SNO", { tid = tid, why = "version" }))
  end
end

-- A v=1 message (already validated by the client).
function Session.receive(client, channel, sender, m)
  local t = m.t
  local s = client.session
  if s then Succession.heard(s, sender, m) end
  if t == "HI" then
    if s and s.role == "host" then
      if m.re == true then client:send("WHISPER", sender, message("TBL", s:record())) end
      -- Seated here but not aware of it (a relog): the snapshot brings it back.
      if m.at ~= s.tid and seatOf(s.seats, sender) then s:snapshotTo(sender) end
    end
    return
  end
  if type(m.tid) ~= "string" then return end
  if WHISPERED[t] and channel ~= "WHISPER" then return end
  local hosting = s and s.role == "host" and s.tid == m.tid
  if t == "SIT" or t == "WAT" then
    if hosting then
      s:onRequest(sender, t, m.seat)
    else
      client:send("WHISPER", sender, message("SNO", { tid = m.tid, why = "gone" }))
    end
  elseif t == "STD" then
    if hosting then s:onStand(sender) end
  elseif t == "ACT" then
    if hosting then s:onAct(sender, m.a) end
  elseif t == "SYN" or t == "PNG" then
    if hosting then s:onSync(sender, t == "SYN") end
  elseif t == "TBL" then
    Succession.onTable(client, channel, sender, m)
  elseif t == "HND" then
    Succession.onHandoff(client, sender, m)
  else
    local handle = ns.Member.handlers[t] -- SNP EV TCK SNO END (core/Member.lua)
    if handle then handle(client, sender, m) end
  end
end
