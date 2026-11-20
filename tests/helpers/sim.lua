-- Multi-client simulator: several Clients on one Bus and one fake clock.
local Sim = {}
Sim.__index = Sim

-- Shared namespace for every Sim (tests can register extra engines here).
Sim.ns = Loader.ns()

local EPOCH0 = 1700000000

function Sim.new(ns)
  local self = setmetatable({
    ns = ns or Sim.ns,
    clock = 0,
    timers = {},      -- { due, seq, fn, env, cancelled }
    seq = 0,
    sent = {},        -- { at, from, channel, target, msg }
    clients = {},     -- name -> current Client
    envs = {},        -- name -> current env
    offlineSet = {},
    guids = {},       -- name -> guid (stable across relogs)
    guidCount = 0,
    nextRandom = {},  -- results for env.random, first to last; when empty: hi
  }, Sim)
  self.bus = self.ns.Bus.new()
  self.makeEnv = function(name, cls) return self:newEnv(name, { cls = cls }) end
  return self
end

function Sim:now() return self.clock end

function Sim:guidOf(name)
  if not self.guids[name] then
    self.guidCount = self.guidCount + 1
    self.guids[name] = string.format("Player-0000-%08d", self.guidCount)
  end
  return self.guids[name]
end

-- env per the shared contract; send records into sim.sent and goes on the bus.
function Sim:newEnv(name, opts)
  opts = opts or {}
  local sim = self
  local status = { combat = false, instance = false, busy = false }
  for k, v in pairs(opts.status or {}) do status[k] = v end
  local group = {}
  for _, n in ipairs(opts.group or {}) do group[sim:guidOf(n)] = true end

  local env = {
    me = name,
    guid = sim:guidOf(name),
    cls = opts.cls or "WARRIOR",
    db = opts.db or { lang = "bg", introDone = false, busy = false, snoozeUntil = 0, debug = false, minimap = {} },
  }
  env.send = function(channel, target, msg)
    if env.dead then return end
    sim.sent[#sim.sent + 1] = { at = sim.clock, from = name, channel = channel, target = target, msg = sim.ns.Util.copy(msg) }
    sim.bus:send(name, channel, target, msg)
  end
  env.now = function() return sim.clock end
  env.epoch = function() return EPOCH0 + sim.clock end
  env.after = function(seconds, fn)
    sim.seq = sim.seq + 1
    local t = { due = sim.clock + (seconds or 0), seq = sim.seq, fn = fn, env = env }
    sim.timers[#sim.timers + 1] = t
    return { cancel = function() t.cancelled = true end }
  end
  env.status = function() return { combat = status.combat, instance = status.instance, busy = status.busy } end
  env.inGroup = function(guid) return group[guid] == true end
  env.random = function(lo, hi) return table.remove(sim.nextRandom, 1) or hi end
  env.log = function() end
  return env
end

function Sim:join(name, env)
  local client = self.ns.Client.new(env)
  self.clients[name], self.envs[name] = client, env
  self.bus:join(name, function(channel, sender, msg)
    if self.offlineSet[name] or self.offlineSet[sender] then return end
    client:receive(channel, sender, msg)
  end)
  client:start()
  return client
end

function Sim:add(name, opts)
  local env = self:newEnv(name, opts)
  return self:join(name, env), env
end

-- A fresh Client under the same name and options; the old one vanishes silently.
function Sim:relog(name)
  local old = self.envs[name]
  self.offlineSet[name] = nil -- a relog is online again
  old.dead = true
  self.bus:leave(name)
  local env = self:newEnv(name, { cls = old.cls, db = old.db })
  env.status, env.inGroup = old.status, old.inGroup
  return self:join(name, env)
end

function Sim:offline(name) self.offlineSet[name] = true end
function Sim:online(name) self.offlineSet[name] = nil end

-- Index of the earliest due timer (by due time, then creation order), or nil.
local function dueIndex(self)
  local best
  for i, t in ipairs(self.timers) do
    local b = best and self.timers[best]
    if t.due <= self.clock and (not b or t.due < b.due or (t.due == b.due and t.seq < b.seq)) then best = i end
  end
  return best
end

-- Fires every due timer and flushes the bus until nothing is left at this instant.
function Sim:drain()
  for _ = 1, 100000 do
    local i = dueIndex(self)
    if i then
      local t = table.remove(self.timers, i)
      if not t.cancelled and not t.env.dead then t.fn() end
    else
      self.bus:flush()
      if not dueIndex(self) then return end
    end
  end
  error("sim: timers keep firing at t=" .. self.clock)
end

function Sim:run(seconds)
  if seconds <= 0 then self:drain(); return end
  for _ = 1, seconds do
    self.clock = self.clock + 1
    self:drain()
  end
end

function Sim:count(pred)
  local n = 0
  for _, s in ipairs(self.sent) do
    if pred(s) then n = n + 1 end
  end
  return n
end

return Sim
