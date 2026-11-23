local _, ns = ...

-- Who is online with the addon and where they sit (`at` = table id or nil).
-- Owned by a Client: timers go through client:after so client:stop cancels them.
local Presence = {}
Presence.__index = Presence
ns.Presence = Presence

local C = ns.Const

local byteLess = ns.Util.byteLess

local function public(p)
  return { name = p.name, cls = p.cls, guid = p.guid, at = p.at, incompatible = p.incompatible, race = p.race, sex = p.sex }
end

-- A peer's race (UnitRace's file name, "Scourge") and sex (UnitSex: 2 male, 3
-- female), for the portraits. Anything else is nil (the class icon): the race
-- becomes part of an atlas name (wow/Art.lua), so only plain letters pass.
local function race(v)
  return type(v) == "string" and #v >= 1 and #v <= 16 and v:find("^%a+$") and v or nil
end

local function sex(v)
  return (v == 2 or v == 3) and v or nil
end

function Presence.new(client)
  local db = client.env.db
  return setmetatable({
    client = client,
    peers = {},      -- name -> { name, cls, guid, at, incompatible, race, sex }
    heardAt = {},    -- name -> env.now() of the last message
    expiry = {},     -- name -> timer handle
    at = nil,        -- own table id
    been = {},       -- tid -> true: every table I was at since this client started
    home = db and type(db.lastAt) == "string" and db.lastAt or nil, -- the table the last client left me at
    -- ... and until when a seat there can still be mine: after that an absent player was stood up.
    homeUntil = (client.env.now and client.env.now() or 0) + C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER + C.CLAIM_STAGGER,
    sentAt = nil,    -- `at` carried by the last GUILD HI
    lastHi = nil,    -- env.now() of the last GUILD HI
    pendingHi = nil, -- coalesced GUILD HI timer
  }, Presence)
end

-- May a snapshot I did not ask for bring me (back) to table `tid`: one I was
-- at, the one I was at when the client before this one stopped (env.db.lastAt,
-- kept across a /reload: looking at other tables meanwhile costs me no seat;
-- only while that seat can still be held, self.homeUntil), or, having been at
-- none since this client started, the table a login finds me still seated at
-- (after a crash nothing is saved).
function Presence:mayReturn(tid)
  local now = self.client.env.now
  local home = tid == self.home and (now and now() or 0) <= self.homeUntil
  return self.been[tid] == true or home or next(self.been) == nil
end

-- My HI; `ld` is the digest of my ledger (none without a guild: a bot), the last
-- settled one while its x values are being hashed (core/LedgerHash.lua); `race`
-- and `sex` are env.race and env.sex (a bot has neither).
function Presence:hi(re)
  local env, L = self.client.env, self.client.ledger
  return { v = C.PROTOCOL, t = "HI", ver = C.VERSION, cls = env.cls, id = env.guid, at = self.at, re = re,
    ld = L and L:digest(true) or nil, race = env.race, sex = env.sex }
end

-- My GUILD HI. While my ledger's digest is being hashed it waits for it (a few
-- frames; the first HI after a login above all), the latest `re` kept.
function Presence:sendGuildHi(re)
  local net = self.client.ledgerNet
  if net and net.running and net.L:hashing() then
    self.hiRe = self.hiRe or re
    if self.hiWait then return end
    self.hiWait = true
    return net:fresh(function()
      local r = self.hiRe
      self.hiWait, self.hiRe = nil, nil
      if self.client.running then self:sendGuildHi(r) end
    end)
  end
  if self.pendingHi then self.pendingHi.cancel(); self.pendingHi = nil end
  self.lastHi = self.client.env.now()
  self.sentAt = self.at
  local hi = self:hi(re)
  self.sentLd = hi.ld -- the digest the guild last heard from me (core/LedgerSync.lua)
  self.client:send("GUILD", nil, hi)
end

function Presence:heartbeat()
  self.client:after(C.HI_HEARTBEAT, function()
    self:sendGuildHi(false)
    self:heartbeat()
  end)
end

function Presence:start()
  self.hiWait, self.hiRe = nil, nil
  self:sendGuildHi(true)
  self:heartbeat()
end

-- Own seat changed: GUILD HI, at most one per HI_MIN_GAP seconds, latest `at` wins.
-- A stopped client only records it; its BYE already tells everyone.
function Presence:setAt(tid)
  local db = self.client.env.db
  if db then db.lastAt = tid end
  if tid then self.been[tid] = true end
  if tid == self.at then return end
  self.at = tid
  if not self.client.running then return end
  if self.pendingHi then return end
  local wait = self.lastHi and (self.lastHi + C.HI_MIN_GAP - self.client.env.now()) or 0
  if wait <= 0 then
    self:sendGuildHi(false)
  else
    self.pendingHi = self.client:after(wait, function()
      self.pendingHi = nil
      if self.at ~= self.sentAt then self:sendGuildHi(false) end
    end)
  end
end

function Presence:changed()
  self.client.events:emit("peers")
end

-- One timer per peer: it fires when the peer could first be PEER_EXPIRE quiet
-- and re-arms itself for the remainder if the peer was heard meanwhile.
function Presence:armExpiry(name, wait)
  self.expiry[name] = self.client:after(wait, function()
    self.expiry[name] = nil
    if not self.peers[name] then return end
    local quiet = self.client.env.now() - self.heardAt[name]
    if quiet >= C.PEER_EXPIRE then
      self:remove(name)
    else
      self:armExpiry(name, C.PEER_EXPIRE - quiet)
    end
  end)
end

-- Creates or refreshes a record; returns it and whether it is new.
function Presence:touch(name)
  self.heardAt[name] = self.client.env.now()
  local p = self.peers[name]
  if p then return p, false end
  p = { name = name, incompatible = false }
  self.peers[name] = p
  self:armExpiry(name, C.PEER_EXPIRE)
  return p, true
end

-- A message with a protocol other than ours: the peer is listed, flagged incompatible.
function Presence:incompatible(name)
  local p, new = self:touch(name)
  if new or not p.incompatible then
    p.incompatible = true
    self:changed()
  end
end

-- A v=1 message from `sender` (already validated by the client).
function Presence:receive(channel, sender, msg)
  if msg.t == "HI" then
    local p, new = self:touch(sender)
    local cls = type(msg.cls) == "string" and msg.cls or nil
    local guid = type(msg.id) == "string" and msg.id or nil
    local at = type(msg.at) == "string" and msg.at or nil
    local r, s = race(msg.race), sex(msg.sex)
    if new or p.cls ~= cls or p.guid ~= guid or p.at ~= at or p.race ~= r or p.sex ~= s or p.incompatible then
      p.cls, p.guid, p.at, p.race, p.sex, p.incompatible = cls, guid, at, r, s, false
      self:changed()
    end
    if msg.re == true then self.client:send("WHISPER", sender, self:hi(false)) end
    -- The digest of the peer's ledger (8 hex): the sync compares it with mine.
    p.ld = type(msg.ld) == "string" and #msg.ld == 8 and msg.ld:find("^[0-9a-f]+$") and msg.ld or nil
    if p.ld and self.client.ledgerSync then self.client.ledgerSync:peer(sender, p.ld) end
  elseif msg.t == "BYE" then
    self:remove(sender)
  elseif self.peers[sender] then
    self.heardAt[sender] = self.client.env.now()
  end
end

function Presence:remove(name)
  if not self.peers[name] then return end
  self.peers[name] = nil
  self.heardAt[name] = nil
  if self.expiry[name] then self.expiry[name].cancel(); self.expiry[name] = nil end
  self:changed()
end

function Presence:get(name)
  local p = self.peers[name]
  return p and public(p) or nil
end

function Presence:list()
  local out = {}
  for _, p in pairs(self.peers) do out[#out + 1] = public(p) end
  table.sort(out, function(a, b) return byteLess(a.name, b.name) end)
  return out
end
