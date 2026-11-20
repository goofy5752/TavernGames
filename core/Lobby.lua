local _, ns = ...

-- Directory of announced tables, by tid. Records come from TBL announces and
-- are dropped on END or after TBL_EXPIRE seconds without a TBL. The table this
-- client hosts is written by its session instead (Lobby:set) and never expires.
-- Owned by a Client: timers go through client:after so client:stop cancels them.
local Lobby = {}
Lobby.__index = Lobby
ns.Lobby = Lobby

local C = ns.Const
local copy, same, byteLess = ns.Util.copy, ns.Util.same, ns.Util.byteLess

-- TBL wire fields -> record {tid, game, host, epoch, access, turn, state, seats, watchers, stake, opt}.
function Lobby.fromTBL(m)
  return {
    tid = m.tid, game = m.g, host = m.h, epoch = m.e, access = m.ac, turn = m.tn,
    state = m.st, seats = copy(m.s), watchers = m.w or 0, stake = nil, opt = copy(m.o),
  }
end

-- Shape check of a TBL record (the fields only; `v`/`t` are the client's job).
-- A game whose engine I have must fit it: its seat count and its options. A
-- game I do not have stays valid (it is listed, not joinable).
function Lobby.valid(m)
  if type(m) ~= "table" then return false end
  if type(m.tid) ~= "string" or type(m.h) ~= "string" or type(m.e) ~= "number" then return false end
  if type(m.g) ~= "string" or type(m.ac) ~= "string" or type(m.tn) ~= "number" or type(m.st) ~= "string" then
    return false
  end
  if m.w ~= nil and type(m.w) ~= "number" then return false end
  if type(m.s) ~= "table" or #m.s == 0 or #m.s > C.MAX_SEATS then return false end
  for i = 1, #m.s do
    if type(m.s[i]) ~= "string" and m.s[i] ~= false then return false end
  end
  if m.o ~= nil and type(m.o) ~= "table" then return false end
  local engine = ns.Games.engine(m.g)
  if engine and (#m.s ~= engine.maxSeats or ns.Games.resolve(m.g, m.o) == nil) then return false end
  return true
end

local function seatIndex(seats, name)
  for i = 1, #seats do
    if seats[i] == name then return i end
  end
  return math.huge
end

function Lobby.new(client)
  return setmetatable({
    client = client,
    records = {}, -- tid -> record
    heardAt = {}, -- tid -> env.now() of the last accepted TBL
    expiry = {},  -- tid -> timer handle
    own = {},     -- tid -> true for the table this client hosts
  }, Lobby)
end

function Lobby:changed()
  self.client.events:emit("tables")
end

-- Spec rule: the sender must be the record's host, and the epoch must be newer,
-- or equal with the same host. A newer epoch (a claim or a handoff) counts only
-- from a sender seated in the known record, as on the session side
-- (Succession.authority). Equal epoch from another host: the claimant wins only
-- if it sits lower than the known host in the known record. Its own claimed
-- seats are never consulted, so reordering them or claiming unseated gets nothing.
function Lobby:accepts(sender, m)
  if sender ~= m.h then return false end
  local known = self.records[m.tid]
  if not known then return true end
  if m.e > known.epoch then return seatIndex(known.seats, sender) ~= math.huge end
  if m.e < known.epoch then return false end
  if m.h == known.host then return true end
  return seatIndex(known.seats, m.h) < seatIndex(known.seats, known.host)
end

-- Same pattern as Presence: one timer per table, re-armed for the remainder.
function Lobby:armExpiry(tid, wait)
  self.expiry[tid] = self.client:after(wait, function()
    self.expiry[tid] = nil
    if not self.records[tid] or self.own[tid] then return end
    local quiet = self.client.env.now() - self.heardAt[tid]
    if quiet >= C.TBL_EXPIRE then
      self:remove(tid)
    else
      self:armExpiry(tid, C.TBL_EXPIRE - quiet)
    end
  end)
end

-- A v=1 message (already validated by the client); only TBL and END matter here.
function Lobby:receive(channel, sender, msg)
  if msg.t == "TBL" then
    -- Competing claims on a table I host are the session's business (Task 6).
    if not Lobby.valid(msg) or self.own[msg.tid] or not self:accepts(sender, msg) then return end
    local tid = msg.tid
    local rec = Lobby.fromTBL(msg)
    local changed = not same(rec, self.records[tid])
    self.records[tid] = rec
    self.heardAt[tid] = self.client.env.now()
    if not self.expiry[tid] then self:armExpiry(tid, C.TBL_EXPIRE) end
    if changed then self:changed() end
  elseif msg.t == "END" then
    local known = type(msg.tid) == "string" and self.records[msg.tid]
    if known and not self.own[msg.tid] and sender == known.host
        and type(msg.e) == "number" and msg.e >= known.epoch then
      self:remove(msg.tid)
    end
  end
end

-- The host's own record.
function Lobby:set(record)
  local tid = record.tid
  self.own[tid] = true
  if self.expiry[tid] then self.expiry[tid].cancel(); self.expiry[tid] = nil end
  if same(record, self.records[tid]) then return end
  self.records[tid] = copy(record)
  self:changed()
end

function Lobby:remove(tid)
  if not self.records[tid] then return end
  self.records[tid] = nil
  self.heardAt[tid] = nil
  self.own[tid] = nil
  if self.expiry[tid] then self.expiry[tid].cancel(); self.expiry[tid] = nil end
  self:changed()
end

function Lobby:get(tid)
  return copy(self.records[tid])
end

-- Copies of every record, sorted by tid bytes.
function Lobby:tables()
  local out = {}
  for _, r in pairs(self.records) do out[#out + 1] = copy(r) end
  table.sort(out, function(a, b) return byteLess(a.tid, b.tid) end)
  return out
end
