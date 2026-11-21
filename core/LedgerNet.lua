local _, ns = ...

-- The live side of the gold ledger (core/LedgerStore.lua).
-- * net:make: my entry, added at once; it leaves with the ones I make within
--   LEDGER_COALESCE s as GUILD LEVs of at most 4 (and LIVE_BYTES canonical
--   bytes), never while I am in an instance. For LEDGER_ADOPT_WAIT s after a
--   login (or until net:settle) my entries are queued, so my next id is above
--   whatever the guild holds. My X entries leave at most LEDGER_DENY_RATE a minute.
-- * net:take: a valid entry whose author and names in f/t/n are guild members
--   (env.member; absent = all) or authors in my store. A live GUILD LEV is 1..4
--   entries of its sender, else dropped whole. "ledger" is emitted once a moment.
-- * An entry under my name that I did not hold moves my counter above it, and:
--   in the adoption window (a store without my record at load, closed with the
--   login queue) it is kept as mine, unless it is too far above my counter
--   (then denied once the window closes); else when its number is at most my
--   saved seq (the store's at login), I held its id or it is too far, it is
--   forged and I deny it (an X that points at the stored body); else a crash
--   lost it: kept uncounted (`un`, a local field the view and the denials skip)
--   and put to me (net:asks, "mineAsk"), net:answer keeps or denies it.
local Ledger, C, Util = ns.Ledger, ns.Const, ns.Util

local Net = {}; Net.__index = Net
ns.LedgerNet = Net

local LIVE_MAX, LIVE_BYTES, MINUTE = 4, 760, 60

function Net.new(client, ledger)
  return setmetatable({ client = client, L = ledger, running = false, out = {}, denials = {}, deniedAt = {},
    queue = {}, far = {} }, Net)
end

local function inInstance(env)
  local s = env.status and env.status()
  return s and s.instance
end

-- fn(self) in `seconds`, unless the timer named `field` is armed already.
function Net:arm(field, seconds, fn)
  if self[field] then return end
  self[field] = self.client:after(seconds, function()
    self[field] = nil
    fn(self)
  end)
end

-- "ledger" (and "mineAsk" when the question changed) once, at the end of this moment.
function Net:changed()
  self:arm("emitTimer", 0, function()
    self.client.events:emit("ledger")
    if self.asked then self.asked = nil; self.client.events:emit("mineAsk") end
  end)
end

-- After a login: my record (seq 0 when missing), the saved seq, the window of a
-- new store and the queue of my own entries, both closed by net:settle.
function Net:start()
  if self.running then return end
  local L = self.L
  self.running = true
  L.adopting = L.fresh and not self.began -- a new store: once per client
  self.began = true
  self.saved = L:record().seq
  self.waiting = true
  self:arm("settleTimer", C.LEDGER_ADOPT_WAIT, Net.settle)
  if #self:asks() > 0 then self.asked = true; self:changed() end -- still unanswered from before
end

-- My entries of the last seconds still go out; queued ones are not made.
function Net:stop()
  if not self.running then return end
  self:flush()
  self.running = false
  self.out, self.denials, self.queue, self.far = {}, {}, {}, {}
  self.outTimer, self.denyTimer, self.emitTimer, self.settleTimer = nil, nil, nil, nil
end

-- Closes the adoption window and the login queue: queued entries are made, the
-- ids refused in the window denied. Again later: nothing more happens.
function Net:settle()
  if not self.running then return end
  self.L.adopting = false
  local queue, far = self.queue, self.far
  self.waiting, self.queue, self.far = false, {}, {}
  for _, q in ipairs(queue) do self:make(q[1], q[2]) end
  for _, b in ipairs(far) do self:deny(b) end
end

-- Is the adoption window of a new store open?
function Net:adopting() return self.L.adopting == true end

-- My new entry -> entry | "queued" | nil, reason ("stopped", or a reason of L:make).
function Net:make(kind, fields)
  if not self.running then return nil, "stopped" end
  if self.waiting then self.queue[#self.queue + 1] = { kind, Util.copy(fields) }; return "queued" end
  local e, why = self.L:make(kind, fields)
  if not e then return nil, why end
  local deny = kind == "X"
  local list = deny and self.denials or self.out
  list[#list + 1] = Ledger.wire(e)
  self:arm(deny and "denyTimer" or "outTimer", C.LEDGER_COALESCE, deny and Net.pump or Net.flush)
  self:changed()
  return e
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

-- My X of body b.
function Net:deny(b) return self:make("X", { r = b.i, h = b.h }) end

-- May my store take an entry naming these people? A member or a known author.
function Net:allowed(e, author)
  local member, L = self.client.env.member, self.L
  if not member then return true end
  local function known(name) return name == false or name == L.me or L:seen(name) > 0 or member(name) end
  if not known(author) or (e.f ~= nil and not known(e.f)) or (e.t ~= nil and not known(e.t)) then return false end
  for _, name in ipairs(type(e.n) == "table" and e.n or {}) do if not known(name) then return false end end
  return true
end

-- The own-name check of body b, number n, new in my store (held: I held its id before).
function Net:own(b, n, held)
  local L = self.L
  local near = L:bump(n) -- my counter is above it already (L:add), unless n is too far
  if L.adopting then
    if not near then self.far[#self.far + 1] = b end
  elseif not near or held or n <= self.saved then
    self:deny(b)
  else
    b.un, L.rev, self.asked = true, L.rev + 1, true
  end
end

-- An entry from the net, got from `from`; `live`: in a live LEV, where every
-- entry is its sender's own -> "new" | "dup" | "twin" | nil.
function Net:take(e, from, live)
  if not self.running or type(e) ~= "table" or type(from) ~= "string" then return nil end
  local L = self.L
  if not Ledger.valid(e, L.epoch()) then return nil end
  local author, n = Ledger.author(e.i)
  if (live and author ~= from) or not self:allowed(e, author) then return nil end
  local rev, held = L.rev, author == L.me and L:has(e.i)
  local status, b = L:add(e, from)
  if not status then return nil end
  if status ~= "dup" and author == L.me then self:own(b, n, held) end
  if L.rev ~= rev then self:changed() end
  return status
end

-- A message the client got: a live GUILD LEV (a whispered one is the sync's).
function Net:receive(channel, sender, msg)
  if channel ~= "GUILD" or msg.t ~= "LEV" or type(msg.ev) ~= "table" then return end
  local count = 0
  for _ in pairs(msg.ev) do count = count + 1 end
  if count < 1 or count > LIVE_MAX or #msg.ev ~= count then return end
  for _, e in ipairs(msg.ev) do if type(e) ~= "table" or Ledger.author(e.i) ~= sender then return end end
  for _, e in ipairs(msg.ev) do self:take(e, sender, true) end
end

-- My entries the guild holds that my store had lost (a crash): {body, ...}.
function Net:asks()
  local out = {}
  for _, b in ipairs(self.L:above(self.L.me, 0)) do if b.un then out[#out + 1] = b end end
  return out
end

-- The answer to the question of net:asks: true, they are mine and count; false,
-- one X each -> true | nil (nothing was asked).
function Net:answer(keep)
  local list = self.running and self:asks() or {}
  if #list == 0 then return nil end
  for _, b in ipairs(list) do b.un = nil end
  self.L.rev, self.asked = self.L.rev + 1, true
  if not keep then for _, b in ipairs(list) do self:deny(b) end end
  self:changed()
  return true
end

return Net
