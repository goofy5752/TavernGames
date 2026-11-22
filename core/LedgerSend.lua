local _, ns = ...

-- The sending side of core/LedgerNet.lua: my entries leave as GUILD LEVs of at
-- most LIVE_MAX entries and LIVE_BYTES packed bytes, never while I am in an
-- instance; my X entries at most LEDGER_DENY_RATE in any minute. The GUILD
-- budget (Net:afford) counts my LEVs and the sync's HI in parts of PART bytes,
-- as the server's throttle does: at most PARTS within any WINDOW s; the rest waits.
-- Net:hash hashes the stale x values of my store LEDGER_HASH_ITEMS items a frame
-- (core/LedgerHash.lua); Net:fresh(fn) runs fn once they are all fresh.
local C = ns.Const
local Net = ns.LedgerNet

local LIVE_MAX, LIVE_BYTES, MINUTE = Net.LIVE_MAX, 760, 60
local PART, PARTS, WINDOW = 255, 10, 10

local function inInstance(env)
  local s = env.status and env.status()
  return s and s.instance
end
Net.inInstance = inInstance

-- The packed size of a message. Here a stand-in, the bytes of its keys and
-- leaves; wow/Adapter.lua installs the real one (AceSerializer + LibDeflate).
function Net.size(msg)
  local n = 0
  for k, v in pairs(msg) do n = n + #tostring(k) + (type(v) == "table" and Net.size(v) or #tostring(v)) end
  return n
end

-- How many of `max` items (at least 1) go in one message of at most `limit`
-- packed bytes; build(k) is the message of the first k (a binary search).
-- AceSerializer writes a table's keys in `pairs` order, so a copy of a message
-- may pack up to about 20 bytes longer: the cut keeps SLACK bytes in hand.
Net.SLACK = 24
function Net.fit(max, limit, build)
  limit = limit - Net.SLACK
  if max <= 1 or Net.size(build(max)) <= limit then return max end

  local lo, hi = 1, max - 1
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if Net.size(build(mid)) <= limit then lo = mid else hi = mid - 1 end
  end
  return lo
end

-- One frame's share of the x hashing; then again next frame, or whoever waited is called.
function Net:hash()
  if not self.L:work(C.LEDGER_HASH_ITEMS) then return self:arm("hashTimer", 0, Net.hash) end
  local list = self.freshly or {}
  self.freshly = nil
  for _, fn in ipairs(list) do fn() end
end

-- fn() once no x of my store is stale: at once, or after the frames the hashing takes.
function Net:fresh(fn)
  if not (self.running and self.L:hashing()) then return fn() end
  self.freshly = self.freshly or {}
  self.freshly[#self.freshly + 1] = fn
  self.L.kick()
end

-- May msg go on GUILD now (within the budget)? -> true, and it is counted | false.
function Net:afford(msg)
  local now, recent, used = self.client.env.now(), {}, 0
  for _, s in ipairs(self.spent or {}) do
    if now - s.at < WINDOW then recent[#recent + 1], used = s, used + s.parts end
  end
  self.spent = recent
  local parts = math.ceil(Net.size(msg) / PART)
  if used + parts > PARTS then return false end
  recent[#recent + 1] = { at = now, parts = parts }
  return true
end

-- Sends at most the first `count` entries of `list` (removed from it) as GUILD
-- LEVs, as far as the budget allows -> how many left.
function Net:ship(list, count)
  local sent = 0
  while sent < count do
    local function lev(k) return { v = C.PROTOCOL, t = "LEV", ev = { unpack(list, 1, k) } } end
    local msg = lev(Net.fit(math.min(LIVE_MAX, count - sent), LIVE_BYTES, lev))
    if not self:afford(msg) then break end
    for _ = 1, #msg.ev do table.remove(list, 1) end
    self.client:send("GUILD", nil, msg)
    sent = sent + #msg.ev
  end
  return sent
end

-- My entries waiting to go out, unless I am in an instance (then again later).
function Net:flush()
  if #self.out == 0 then return end
  if not inInstance(self.client.env) then self:ship(self.out, #self.out) end
  if #self.out > 0 then self:arm("outTimer", C.LEDGER_COALESCE, Net.flush) end
end

-- My X entries: at most LEDGER_DENY_RATE in any minute, the rest when there is room.
function Net:pump()
  if #self.denials == 0 then return end
  local now, recent = self.client.env.now(), {}
  for _, t in ipairs(self.deniedAt) do if now - t < MINUTE then recent[#recent + 1] = t end end
  self.deniedAt = recent
  local room = C.LEDGER_DENY_RATE - #recent
  if room > 0 and not inInstance(self.client.env) then
    local sent = self:ship(self.denials, math.min(room, #self.denials))
    for _ = 1, sent do recent[#recent + 1] = now end
  end
  if #self.denials == 0 then return end
  local wait = #recent >= C.LEDGER_DENY_RATE and recent[1] + MINUTE - now or C.LEDGER_COALESCE
  self:arm("denyTimer", math.max(wait, 1), Net.pump)
end
