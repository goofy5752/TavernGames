local _, ns = ...

-- The sending side of core/LedgerNet.lua: my entries leave as GUILD LEVs of at
-- most LIVE_MAX entries and LIVE_BYTES canonical bytes (a stand-in for the
-- packed size), never while I am in an instance; my X entries at most
-- LEDGER_DENY_RATE in any minute.
local Ledger, C = ns.Ledger, ns.Const
local Net = ns.LedgerNet

local LIVE_MAX, LIVE_BYTES, MINUTE = Net.LIVE_MAX, 760, 60

local function inInstance(env)
  local s = env.status and env.status()
  return s and s.instance
end

-- Sends the first `count` entries of `list` (removed from it) as GUILD LEVs.
function Net:ship(list, count)
  local ev, bytes = {}, 0
  local function send()
    self.client:send("GUILD", nil, { v = C.PROTOCOL, t = "LEV", ev = ev })
    ev, bytes = {}, 0
  end
  for _ = 1, count do
    local e = table.remove(list, 1)
    local size = #Ledger.canon(e)
    if #ev > 0 and (#ev == LIVE_MAX or bytes + size > LIVE_BYTES) then send() end
    ev[#ev + 1], bytes = e, bytes + size
  end
  if #ev > 0 then send() end
end

-- My entries waiting to go out, unless I am in an instance (then again later).
function Net:flush()
  if #self.out == 0 then return end
  if inInstance(self.client.env) then return self:arm("outTimer", C.LEDGER_COALESCE, Net.flush) end
  self:ship(self.out, #self.out)
end

-- My X entries: at most LEDGER_DENY_RATE in any minute, the rest when there is room.
function Net:pump()
  if #self.denials == 0 then return end
  local now, recent = self.client.env.now(), {}
  for _, t in ipairs(self.deniedAt) do if now - t < MINUTE then recent[#recent + 1] = t end end
  self.deniedAt = recent
  local room = C.LEDGER_DENY_RATE - #recent
  if room > 0 and not inInstance(self.client.env) then
    local count = math.min(room, #self.denials)
    self:ship(self.denials, count)
    for _ = 1, count do recent[#recent + 1] = now end
  end
  if #self.denials == 0 then return end
  local wait = #recent >= C.LEDGER_DENY_RATE and recent[1] + MINUTE - now or C.LEDGER_COALESCE
  self:arm("denyTimer", math.max(wait, 1), Net.pump)
end
