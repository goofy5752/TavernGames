local _, ns = ...

-- Who is online with the addon and where they sit (`at` = table id or nil).
-- Owned by a Client: timers go through client:after so client:stop cancels them.
local Presence = {}
Presence.__index = Presence
ns.Presence = Presence

local C = ns.Const

local byteLess = ns.Util.byteLess

local function public(p)
  return { name = p.name, cls = p.cls, guid = p.guid, at = p.at, incompatible = p.incompatible }
end

function Presence.new(client)
  return setmetatable({
    client = client,
    peers = {},      -- name -> { name, cls, guid, at, incompatible }
    heardAt = {},    -- name -> env.now() of the last message
    expiry = {},     -- name -> timer handle
    at = nil,        -- own table id
    sentAt = nil,    -- `at` carried by the last GUILD HI
    lastHi = nil,    -- env.now() of the last GUILD HI
    pendingHi = nil, -- coalesced GUILD HI timer
  }, Presence)
end

function Presence:hi(re)
  local env = self.client.env
  return { v = C.PROTOCOL, t = "HI", ver = C.VERSION, cls = env.cls, id = env.guid, at = self.at, re = re }
end

function Presence:sendGuildHi(re)
  if self.pendingHi then self.pendingHi.cancel(); self.pendingHi = nil end
  self.lastHi = self.client.env.now()
  self.sentAt = self.at
  self.client:send("GUILD", nil, self:hi(re))
end

function Presence:heartbeat()
  self.client:after(C.HI_HEARTBEAT, function()
    self:sendGuildHi(false)
    self:heartbeat()
  end)
end

function Presence:start()
  self:sendGuildHi(true)
  self:heartbeat()
end

-- Own seat changed: GUILD HI, at most one per HI_MIN_GAP seconds, latest `at` wins.
-- A stopped client only records it; its BYE already tells everyone.
function Presence:setAt(tid)
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
    if new or p.cls ~= cls or p.guid ~= guid or p.at ~= at or p.incompatible then
      p.cls, p.guid, p.at, p.incompatible = cls, guid, at, false
      self:changed()
    end
    if msg.re == true then self.client:send("WHISPER", sender, self:hi(false)) end
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
