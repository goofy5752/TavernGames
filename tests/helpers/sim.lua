-- Multi-client simulator: several Clients on one Bus and one fake clock.
local Sim = {}
Sim.__index = Sim

-- Shared namespace for every Sim (tests can register extra engines here).
Sim.ns = Loader.ns()

local EPOCH0 = 1700000000
-- The saved variables a crash loses: their copy at the last client:stop() comes back (sim:crash).
local CRASH_KEYS = { "ledger", "stakeSeen", "stakeLeft", "stakeSat" }

-- Seeds. A sim client makes its seeds the plain way, SEED_BYTES values of its
-- env.random as hex, so that a test can say what a seed will be (sim.nextRandom,
-- or env.random replaced). A client whose env has realSeeds = true makes them
-- as the game does, out of its secret pool (core/Fair.lua): Sim.realSeed.
Sim.realSeed = Sim.ns.Fair.seed
Sim.ns.Fair.seed = function(env, purpose)
  if env.realSeeds then return Sim.realSeed(env, purpose) end
  local out = {}
  for i = 1, Sim.ns.Const.SEED_BYTES do out[i] = string.format("%02x", env.random(0, 255)) end
  return table.concat(out)
end

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
    options = {},     -- name -> the opts of sim:add (reused by sim:relog)
    nextRolls = {},   -- results for env.roll, first to last; when empty: hi
    rolled = {},      -- every env.roll: { from, lo, hi, n }
    groupInvites = {}, -- every env.groupInvite: { from, name }
    stopped = {},     -- name -> the CRASH_KEYS of its db at sim:add or its last client:stop()
  }, Sim)
  -- Whose server rolls `to` sees in chat, and the name it sees for `from`.
  self.canSee = function() return true end
  self.rollName = function(from) return self.ns.Names.first(from) end
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
  -- `done` (optional), the done-callback of AceComm's SendCommMessage: here at once.
  env.send = function(channel, target, msg, done)
    if env.dead then return end
    sim.sent[#sim.sent + 1] = { at = sim.clock, from = name, channel = channel, target = target, msg = sim.ns.Util.copy(msg) }
    sim.bus:send(name, channel, target, msg)
    if done then done() end
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
  env.strictHooks = true -- an extension hook error fails the test (see Session:hook)
  return env
end

-- Remembers a copy of the CRASH_KEYS of name's db: what sim:crash comes back to.
function Sim:keep(name, db)
  local copy = {}
  for _, k in ipairs(CRASH_KEYS) do copy[k] = self.ns.Util.copy(db[k]) end
  self.stopped[name] = copy
end

function Sim:join(name, env)
  local client = self.ns.Client.new(env)
  local sim, stop = self, client.stop
  -- A clean logout writes the saved variables (what sim:crash comes back to).
  client.stop = function(c)
    stop(c)
    if sim.stopped[name] then sim:keep(name, env.db) end
  end
  self.clients[name], self.envs[name] = client, env
  self.bus:join(name, function(channel, sender, msg)
    if self.offlineSet[name] or self.offlineSet[sender] then return end
    client:receive(channel, sender, msg)
  end)
  client:start()
  return client
end

-- The fakes of a human player's client (sim:add, never sim.makeEnv):
-- env.roll unless opts.roll == false. The roll shows up in chat (rollSeen) on
-- the next drain for every client sim.canSee lets see it: as the full name for
-- the roller, as sim.rollName for the others.
-- env.group() reports opts.party (default: not in a group); env.groupInvite
-- records into sim.groupInvites.
function Sim:addFakes(env, opts)
  local sim, name = self, env.me
  local party = opts.party or { grouped = false, leader = false, raid = false, size = 0 }
  env.group = function()
    return { grouped = party.grouped, leader = party.leader, raid = party.raid, size = party.size }
  end
  env.groupInvite = function(who)
    sim.groupInvites[#sim.groupInvites + 1] = { from = name, name = who }
  end
  if opts.roll ~= false then
    env.roll = function(lo, hi)
      local n = table.remove(sim.nextRolls, 1) or hi
      sim.rolled[#sim.rolled + 1] = { from = name, lo = lo, hi = hi, n = n }
      env.after(0, function()
        local names = {}
        for to in pairs(sim.clients) do names[#names + 1] = to end
        table.sort(names, sim.ns.Util.byteLess)
        for _, to in ipairs(names) do
          if sim.canSee(name, to) then
            sim.clients[to]:rollSeen(to == name and name or sim.rollName(name), n, lo, hi)
          end
        end
      end)
    end
  end
end

-- A human player's client: in the guild opts.guild (default "МЕХАНАТА") with a
-- ledger store db.ledger, both kept across sim:relog (sim.makeEnv, a bot's env, has neither).
function Sim:add(name, opts)
  opts = opts or {}
  self.options[name] = opts
  local env = self:newEnv(name, opts)
  env.guild = opts.guild or "МЕХАНАТА"
  env.db.ledger = env.db.ledger or {}
  self:addFakes(env, opts)
  self:keep(name, env.db)
  return self:join(name, env), env
end

-- A fresh Client under the same name and options; the old one vanishes silently.
function Sim:relog(name)
  local old = self.envs[name]
  self.offlineSet[name] = nil -- a relog is online again
  old.dead = true
  self.bus:leave(name)
  local opts = {}
  for k, v in pairs(self.options[name] or {}) do opts[k] = v end
  opts.cls, opts.db = old.cls, old.db
  local env = self:newEnv(name, opts)
  env.status, env.inGroup, env.guild = old.status, old.inGroup, old.guild
  if self.options[name] then self:addFakes(env, opts) end
  return self:join(name, env)
end

-- A relog after a crash, or on another computer: nothing of the saved
-- variables that a /reload keeps of a running deal (db.fairKeep) is there,
-- and the ledger and the stake notes are as at the last client:stop() (or sim:add).
function Sim:crash(name)
  local db, kept = self.envs[name].db, self.stopped[name]
  db.fairKeep = nil
  for _, k in ipairs(kept and CRASH_KEYS or {}) do db[k] = self.ns.Util.copy(kept[k]) end
  return self:relog(name)
end

-- Closes the adoption window and the login queue of every client's ledger
-- (net:settle), so a test need not wait LEDGER_ADOPT_WAIT.
function Sim:settle()
  local names = {}
  for name in pairs(self.clients) do names[#names + 1] = name end
  table.sort(names, self.ns.Util.byteLess)
  for _, name in ipairs(names) do
    local net = self.clients[name].ledgerNet
    if net then net:settle() end
  end
end

-- The client shows a loading screen (on) or it just ended: the env flags of
-- the contract, env.loading and env.loadedAt. What becomes of the messages
-- meanwhile is the test's business (sim:offline: lost).
function Sim:loading(name, on)
  local env = self.envs[name]
  env.loading = on and true or nil
  if not on then env.loadedAt = self.clock end
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
