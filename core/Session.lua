local _, ns = ...

-- The table this client is at, as host or as member (player or watcher), and the
-- seating protocol around it: SIT/WAT/STD requests checked by the host, SNO
-- refusals, ordered seat events (EV seat 0) with an SNP snapshot for each
-- newcomer, and the host's coalesced TBL announce. Game play: Task 5.
--
-- client.session is nil or a Session with the public fields
--   tid, role ("host"|"player"|"watcher"), mySeat, host, epoch, seq, seats,
--   state, status, deadline
-- and session:record() -> TBL fields. Every change emits "session"(session|nil).
local Session = {}
Session.__index = Session
ns.Session = Session

local C = ns.Const
local copy, byteLess = ns.Util.copy, ns.Util.byteLess

local ACCESS = { guild = true, invite = true, group = true }

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

-- The client's session ended or was left: no table, `at` cleared.
local function leave(client)
  client.session = nil
  client.presence:setAt(nil)
  emit(client)
end

function Session:record()
  return {
    tid = self.tid, g = self.game, h = self.host, e = self.epoch, ac = self.access,
    tn = self.turn, st = self.state, s = copy(self.seats), w = self.watchers,
  }
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

-- Ordered table event `a` (seat 0) to every member except `skip`.
function Session:event(a, skip)
  self.seq = self.seq + 1
  local m = message("EV", { tid = self.tid, e = self.epoch, q = self.seq, seat = 0, a = a })
  local members = self:members()
  for i = 1, #members do
    if members[i] ~= skip then self.client:send("WHISPER", members[i], m) end
  end
end

function Session:snapshotTo(name)
  self.client:send("WHISPER", name, message("SNP", {
    tid = self.tid, e = self.epoch, q = self.seq, tbl = self:record(), st = nil, left = nil,
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
    self.seats[seat] = sender
    self:event({ k = "sit", seat = seat, name = sender }, sender)
  else
    self.watcherSet[sender] = true
    self.watchers = self.watchers + 1
  end
  self:snapshotTo(sender)
  self:recordChanged()
end

function Session:onStand(sender)
  local seat = seatOf(self.seats, sender)
  if seat then
    self.seats[seat] = false
    self:event({ k = "stand", seat = seat, why = "left" }, sender)
    if not self:anySeated() then return self:finish() end
    self:recordChanged()
  elseif self.watcherSet[sender] then
    self.watcherSet[sender] = nil
    self.watchers = self.watchers - 1
    self:recordChanged()
  end
end

function Session:anySeated()
  for i = 1, #self.seats do
    if self.seats[i] then return true end
  end
  return false
end

-- The last seated player is gone: END on GUILD, the session ends for everyone.
function Session:finish()
  local client = self.client
  if self.announceTimer then self.announceTimer.cancel(); self.announceTimer = nil end
  if self.heartbeatTimer then self.heartbeatTimer.cancel(); self.heartbeatTimer = nil end
  client:send("GUILD", nil, message("END", { tid = self.tid, e = self.epoch }))
  client.lobby:remove(self.tid)
  leave(client)
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
    seats = seats, state = "open", status = "ok", deadline = nil,
    game = opts.game, access = opts.access, turn = turn, watchers = 0,
    watcherSet = {}, -- name -> true
    invited = {},    -- name -> true, for access "invite" (filled by Task 7)
  }, Session)
  client.presence:setAt(tid)
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
  s.epoch, s.seq, s.seats, s.state = m.e, m.q, copy(t.s), t.st
  s.status, s.deadline = "ok", nil
  s.game, s.access, s.turn, s.watchers = t.g, t.ac, t.tn, t.w or 0
  client.pending = nil
  client.session = s
  client.presence:setAt(s.tid)
  emit(client)
end

local function onSnapshot(client, sender, m)
  if type(m.e) ~= "number" or type(m.q) ~= "number" or not ns.Lobby.valid(m.tbl)
      or m.tbl.tid ~= m.tid or m.tbl.h ~= sender then return end
  local s, p = client.session, client.pending
  if s and s.role ~= "host" and s.tid == m.tid and s.host == sender then
    adopt(client, sender, m)
  elseif not s and p and p.tid == m.tid and p.host == sender then
    adopt(client, sender, m)
  elseif not s or s.tid ~= m.tid then
    -- Seated or listed after I gave up waiting or went elsewhere: free the place again.
    client:send("WHISPER", sender, message("STD", { tid = m.tid }))
  end
end

local function onEvent(client, sender, m)
  local s = client.session
  if not s or s.role == "host" or s.tid ~= m.tid or s.host ~= sender or m.e ~= s.epoch then return end
  -- Task 5: a gap (q > seq + 1) asks the host for a snapshot (SYN).
  if m.q ~= s.seq + 1 then return end
  s.seq = m.q
  local a = m.a
  if m.seat == 0 and type(a) == "table" and type(a.seat) == "number" and s.seats[a.seat] ~= nil then
    if a.k == "sit" and type(a.name) == "string" then
      s.seats[a.seat] = a.name
    elseif a.k == "stand" then
      s.seats[a.seat] = false
    end
  end
  emit(client)
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

-- A v=1 message (already validated by the client).
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
  if t == "SIT" or t == "WAT" or t == "STD" then
    local s = client.session
    local hosting = s and s.role == "host" and s.tid == m.tid
    if t == "STD" then
      if hosting then s:onStand(sender) end
    elseif hosting then
      s:onRequest(sender, t, m.seat)
    else
      client:send("WHISPER", sender, message("SNO", { tid = m.tid, why = "gone" }))
    end
  elseif t == "SNP" then
    onSnapshot(client, sender, m)
  elseif t == "EV" then
    onEvent(client, sender, m)
  elseif t == "SNO" then
    onRefusal(client, sender, m)
  elseif t == "END" then
    onEnd(client, sender, m)
  end
end
