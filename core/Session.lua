local _, ns = ...

-- The table this client is at, as host or as member (player or watcher), and the
-- protocol around it. Seating: SIT/WAT/STD requests checked by the host, SNO
-- refusals, an SNP snapshot for each newcomer, the host's coalesced TBL announce.
-- Play: the host orders every table and game event (EV, q = seq + 1), checks each
-- ACT through the engine, runs the turn timer (an automatic move on expiry) and
-- the engine's system actions; members apply events strictly in order and heal a
-- gap with SYN -> SNP. Heartbeats: TCK from the host, PNG from members.
--
-- client.session is nil or a Session with the public fields
--   tid, role ("host"|"player"|"watcher"), mySeat, host, epoch, seq, seats,
--   state (engine state, nil until the first start),
--   status ("open"|"live"|"aborted"; "aborted" is kept until the next start),
--   deadline (env.now()-based end of the current turn, or nil)
-- and session:record() -> TBL fields. Every change emits "session"(session|nil);
-- an EV from the host that the engine rejects emits "desync"(tid).
local Session = {}
Session.__index = Session
ns.Session = Session

local C = ns.Const
local copy, byteLess = ns.Util.copy, ns.Util.byteLess

local ACCESS = { guild = true, invite = true, group = true }

-- Point-to-point messages: honoured only when they arrive by WHISPER.
local WHISPERED = {
  SIT = true, WAT = true, STD = true, SNO = true, SNP = true, EV = true,
  ACT = true, SYN = true, PNG = true, TCK = true,
}

local TIMERS = { "announceTimer", "heartbeatTimer", "tickTimer", "pingTimer", "turnTimer", "systemTimer" }

local function message(t, fields)
  fields.v, fields.t = C.PROTOCOL, t
  return fields
end

local function contains(list, value)
  for i = 1, #list do
    if list[i] == value then return true end
  end
  return false
end

local function seatOf(seats, name)
  for i = 1, #seats do
    if seats[i] == name then return i end
  end
  return nil
end

local function emit(client)
  client.events:emit("session", client.session)
end

local function refuse(client, tid, why)
  client.events:emit("refused", tid, why)
end

function Session:cancelTimers()
  for i = 1, #TIMERS do
    local key = TIMERS[i]
    if self[key] then self[key].cancel(); self[key] = nil end
  end
end

-- The client's session ended or was left: no table, `at` cleared.
local function leave(client)
  if client.session then client.session:cancelTimers() end
  client.session = nil
  client.presence:setAt(nil)
  emit(client)
end

function Session:engine()
  return ns.Engines[self.game]
end

function Session:record()
  return {
    tid = self.tid, g = self.game, h = self.host, e = self.epoch, ac = self.access,
    tn = self.turn, st = self.status == "live" and "live" or "open", s = copy(self.seats),
    w = self.watchers,
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
-- carries the table events sit/stand/start/abort or an engine system action.
-- Returns true, or nil when the event does not fit (nothing is changed).
function Session:apply(seat, a)
  if type(a) ~= "table" then return nil end
  local k = seat == 0 and a.k
  if k == "sit" or k == "stand" then
    if type(a.seat) ~= "number" or self.seats[a.seat] == nil then return nil end
    if k == "sit" then
      if type(a.name) ~= "string" then return nil end
      self.seats[a.seat] = a.name
    else
      self.seats[a.seat] = false
    end
    return true
  elseif k == "start" then
    self.state, self.status = self:engine().new({ first = 1 }), "live"
    return true
  elseif k == "abort" then
    self.status, self.deadline = "aborted", nil
    return true
  end
  if self.status ~= "live" or type(seat) ~= "number" then return nil end
  local trial = copy(self.state)
  if not self:engine().apply(trial, seat, a) then return nil end
  self.state = trial
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

-- After a game event: the engine's pending system action and the turn timer,
-- whose expiry plays Engine.auto for the seat on turn. Not live: no timers.
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
      self:play(0, action)
    end)
  end
  local seat = self.state.turn
  if seat then
    self.deadline = client.env.now() + self.turn
    self.turnTimer = client:after(self.turn, function()
      self.turnTimer = nil
      local auto = engine.auto(self.state, seat)
      if auto then self:play(seat, auto, true) end
    end)
  end
end

-- The next ordered event: applied here, then whispered to every member except
-- `skip`. Sit/stand leave the running turn alone; every other event re-arms the
-- timers (abort stops them). Returns false when the event does not apply.
function Session:event(seat, a, skip, auto)
  if not self:apply(seat, a) then return false end
  self.seq = self.seq + 1
  local k = seat == 0 and a.k
  if k ~= "sit" and k ~= "stand" then self:armTimers() end
  local m = message("EV", {
    tid = self.tid, e = self.epoch, q = self.seq, seat = seat, a = a,
    auto = auto or nil, left = self:left(),
  })
  local members = self:members()
  for i = 1, #members do
    if members[i] ~= skip then self.client:send("WHISPER", members[i], m) end
  end
  return true
end

-- A game action by `seat` (0 = system); dropped silently if the engine refuses it.
function Session:play(seat, a, auto)
  if self:event(seat, a, nil, auto) then emit(self.client) end
end

function Session:startIfFull()
  if self.status == "live" then return end
  for i = 1, #self.seats do
    if not self.seats[i] then return end
  end
  self:event(0, { k = "start" })
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

function Session:snapshotTo(name)
  self.client:send("WHISPER", name, message("SNP", {
    tid = self.tid, e = self.epoch, q = self.seq, tbl = self:record(),
    st = self.state and self:engine().snapshot(self.state), left = self:left(),
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
  if kind == "SIT" then
    if type(seat) ~= "number" or self.seats[seat] ~= false then return "taken" end
  elseif self.watchers >= C.MAX_WATCHERS then
    return "full"
  end
  return nil
end

function Session:onRequest(sender, kind, seat)
  -- Already here (a repeated click): just the snapshot again.
  if seatOf(self.seats, sender) or (kind == "WAT" and self.watcherSet[sender]) then
    return self:snapshotTo(sender)
  end
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
  self:snapshotTo(sender)
  if kind == "SIT" then self:startIfFull() end
  self:recordChanged()
end

-- A seated player leaving a live match below minSeats aborts it (no winner).
function Session:onStand(sender)
  local seat = seatOf(self.seats, sender)
  if seat then
    self:event(0, { k = "stand", seat = seat, why = "left" }, sender)
    if self:seatedCount() == 0 then return self:finish() end
    if self.status == "live" and self:seatedCount() < self:engine().minSeats then
      self:event(0, { k = "abort" })
    end
    self:recordChanged()
  elseif self.watcherSet[sender] then
    self.watcherSet[sender] = nil
    self.watchers = self.watchers - 1
    self:recordChanged()
  end
end

function Session:onAct(sender, a)
  local seat = seatOf(self.seats, sender)
  if seat and self.status == "live" then self:play(seat, a) end
end

function Session:onSync(sender)
  if seatOf(self.seats, sender) or self.watcherSet[sender] then self:snapshotTo(sender) end
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
-- Member side
---------------------------------------------------------------------------

-- PNG to the host every PING_EVERY seconds.
function Session:schedulePing()
  self.pingTimer = self.client:after(C.PING_EVERY, function()
    self.pingTimer = nil
    self.client:send("WHISPER", self.host, message("PNG", { tid = self.tid }))
    self:schedulePing()
  end)
end

-- SYN{have} to the host, at most one per SYN_MIN_GAP seconds.
function Session:requestSync()
  local now = self.client.env.now()
  if self.lastSyn and now - self.lastSyn < C.SYN_MIN_GAP then return end
  self.lastSyn = now
  self.client:send("WHISPER", self.host, message("SYN", { tid = self.tid, have = self.seq }))
end

---------------------------------------------------------------------------
-- Client entry points
---------------------------------------------------------------------------

-- opts {game, access, turn} -> tid | nil, code ("busy" "game" "access" "turn").
function Session.open(client, opts)
  opts = opts or {}
  if client.session then return nil, "busy" end
  local engine = type(opts.game) == "string" and ns.Engines and ns.Engines[opts.game]
  if not engine then return nil, "game" end
  if not ACCESS[opts.access] then return nil, "access" end
  local turn = opts.turn == nil and C.TURN_DEFAULT or opts.turn
  if not contains(C.TURN_CHOICES, turn) then return nil, "turn" end

  local env = client.env
  local tid = env.me .. "#" .. env.epoch()
  local seats = {}
  for i = 1, engine.maxSeats do seats[i] = false end
  seats[1] = env.me
  client.pending = nil
  client.session = setmetatable({
    client = client,
    tid = tid, role = "host", mySeat = 1, host = env.me, epoch = 1, seq = 0,
    seats = seats, state = nil, status = "open", deadline = nil,
    game = opts.game, access = opts.access, turn = turn, watchers = 0,
    watcherSet = {}, -- name -> true
    invited = {},    -- name -> true, for access "invite" (filled by Task 7)
  }, Session)
  client.presence:setAt(tid)
  client.session:scheduleTick()
  client.session:recordChanged()
  return tid
end

-- kind "SIT" (with seat) or "WAT"; the answer is an SNP or the event "refused".
function Session.request(client, kind, tid, seat)
  local s = client.session
  if s and (s.tid ~= tid or s.role == "host") then return refuse(client, tid, "busy") end
  local host = s and s.host
  if not host then
    local rec = client.lobby:get(tid)
    if not rec then return refuse(client, tid, "gone") end
    host = rec.host
    client.pending = { tid = tid, host = host }
  end
  local m = kind == "SIT" and { tid = tid, seat = seat } or { tid = tid }
  client:send("WHISPER", host, message(kind, m))
end

-- Stand up or stop watching; a pending request is forgotten.
function Session.stand(client)
  client.pending = nil
  local s = client.session
  if not s then return end
  if s.role == "host" then
    -- Task 6: with other players seated the host hands the table over instead.
    return s:finish()
  end
  client:send("WHISPER", s.host, message("STD", { tid = s.tid }))
  leave(client)
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
    client:send("WHISPER", s.host, message("ACT", { tid = s.tid, a = a }))
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

-- Member: session from a snapshot (new, or replacing the current one).
local function adopt(client, sender, m)
  local t, me = m.tbl, client.env.me
  local seat = seatOf(t.s, me)
  local s = client.session or setmetatable({ client = client }, Session)
  s.tid, s.role, s.mySeat, s.host = m.tid, seat and "player" or "watcher", seat, sender
  s.epoch, s.seq, s.seats = m.e, m.q, copy(t.s)
  s.game, s.access, s.turn, s.watchers = t.g, t.ac, t.tn, t.w or 0
  s.state = type(m.st) == "table" and ns.Engines[t.g].restore(m.st) or nil
  s.status = t.st == "live" and "live" or (s.state and "aborted" or "open")
  s.deadline = type(m.left) == "number" and client.env.now() + m.left or nil
  client.pending = nil
  client.session = s
  if not s.pingTimer then s:schedulePing() end
  client.presence:setAt(s.tid)
  emit(client)
end

local function onSnapshot(client, sender, m)
  local t = m.tbl
  if type(m.e) ~= "number" or type(m.q) ~= "number" or not ns.Lobby.valid(t)
      or t.tid ~= m.tid or t.h ~= sender or not ns.Engines[t.g]
      or (t.st == "live" and type(m.st) ~= "table") then return end
  local s, p = client.session, client.pending
  if s and s.role ~= "host" and s.tid == m.tid and s.host == sender then
    if m.e >= s.epoch then adopt(client, sender, m) end
  elseif not s and p and p.tid == m.tid and p.host == sender then
    adopt(client, sender, m)
  elseif not s or s.tid ~= m.tid then
    -- Seated or listed after I gave up waiting or went elsewhere: free the place again.
    client:send("WHISPER", sender, message("STD", { tid = m.tid }))
  end
end

-- My session when `m` (EV/TCK) comes from its host at my epoch or later, else nil.
local function fromHost(client, sender, m)
  local s = client.session
  if not s or s.role == "host" or s.tid ~= m.tid or s.host ~= sender then return nil end
  if type(m.e) ~= "number" or m.e < s.epoch or type(m.q) ~= "number" then return nil end
  return s
end

local function onEvent(client, sender, m)
  local s = fromHost(client, sender, m)
  if not s or m.q <= s.seq then return end
  if m.q > s.seq + 1 then return s:requestSync() end
  if not s:apply(m.seat, m.a) then
    client.events:emit("desync", s.tid)
    return s:requestSync()
  end
  s.seq = m.q
  s.deadline = type(m.left) == "number" and client.env.now() + m.left or nil
  emit(client)
end

local function onTick(client, sender, m)
  local s = fromHost(client, sender, m)
  if s and m.q > s.seq then s:requestSync() end
end

local function onRefusal(client, sender, m)
  if type(m.why) ~= "string" then return end
  local s, p = client.session, client.pending
  if p and p.tid == m.tid and p.host == sender then
    client.pending = nil
    refuse(client, m.tid, m.why)
  elseif s and s.role ~= "host" and s.tid == m.tid and s.host == sender then
    refuse(client, m.tid, m.why) -- e.g. a watcher asking for a taken chair
  end
end

local function onEnd(client, sender, m)
  local s, p = client.session, client.pending
  if s and s.role ~= "host" and s.tid == m.tid and s.host == sender
      and type(m.e) == "number" and m.e >= s.epoch then
    leave(client)
  elseif p and p.tid == m.tid and p.host == sender then
    client.pending = nil
    refuse(client, m.tid, "gone")
  end
end

-- A v=1 message (already validated by the client). PNG needs nothing here:
-- Presence already noted that the sender was heard.
function Session.receive(client, channel, sender, m)
  local t = m.t
  if t == "HI" then
    local s = client.session
    if m.re == true and s and s.role == "host" then
      client:send("WHISPER", sender, message("TBL", s:record()))
    end
    return
  end
  if type(m.tid) ~= "string" then return end
  if WHISPERED[t] and channel ~= "WHISPER" then return end
  local s = client.session
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
  elseif t == "SYN" then
    if hosting then s:onSync(sender) end
  elseif t == "SNP" then
    onSnapshot(client, sender, m)
  elseif t == "EV" then
    onEvent(client, sender, m)
  elseif t == "TCK" then
    onTick(client, sender, m)
  elseif t == "SNO" then
    onRefusal(client, sender, m)
  elseif t == "END" then
    onEnd(client, sender, m)
  end
end
