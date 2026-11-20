local _, ns = ...

-- Composes the core modules; the only API ui/ and wow/ call.
local Client = {}
Client.__index = Client
ns.Client = Client

local C = ns.Const

function Client.new(env)
  local self = setmetatable({ env = env, events = ns.Emitter.new(), timers = {}, running = false }, Client)
  self.presence = ns.Presence.new(self)
  self.lobby = ns.Lobby.new(self)
  self.session = nil -- see core/Session.lua
  self.pending = nil -- { tid, host } of an unanswered SIT/WAT
  return self
end

function Client:on(event, fn) self.events:on(event, fn) end

-- One-shot timer through env.after, tracked so stop() can cancel it.
function Client:after(seconds, fn)
  local timer, handle = {}, nil
  timer.cancel = function()
    self.timers[timer] = nil
    if handle then handle.cancel() end
  end
  self.timers[timer] = true
  handle = self.env.after(seconds, function()
    if not self.timers[timer] then return end
    self.timers[timer] = nil
    fn()
  end)
  return timer
end

function Client:send(channel, target, msg)
  self.env.send(channel, target, msg)
  if self.env.log then self.env.log("out", channel, target, msg) end
end

function Client:start()
  if self.running then return end
  self.running = true
  self.presence:start()
end

function Client:stop()
  if not self.running then return end
  self.running = false
  ns.Session.stand(self) -- STD or END; the seat change sends no HI (BYE follows)
  self:send("GUILD", nil, { v = C.PROTOCOL, t = "BYE" })
  for timer in pairs(self.timers) do timer.cancel() end
  self.timers = {}
end

function Client:peerOffline(name)
  self.presence:remove(name)
end

-- opts {game, access, turn} -> tid | nil, code ("busy" "game" "access" "turn").
function Client:openTable(opts) return ns.Session.open(self, opts) end

-- Refusals arrive as the event "refused"(tid, why).
function Client:sit(tid, seat) ns.Session.request(self, "SIT", tid, seat) end
function Client:watch(tid) ns.Session.request(self, "WAT", tid) end

-- Stands up or stops watching.
function Client:stand() ns.Session.stand(self) end

function Client:receive(channel, sender, msg)
  if not self.running then return end
  if self.env.log then self.env.log("in", channel, sender, msg) end
  if type(msg) ~= "table" or msg.v == nil or msg.t == nil then return end
  if type(sender) ~= "string" or sender == self.env.me then return end
  if msg.v ~= C.PROTOCOL then
    self.presence:incompatible(sender)
    if type(msg.v) == "number" and msg.v > C.PROTOCOL and not self.updateSeen then
      self.updateSeen = true
      self.events:emit("update")
    end
    -- A SIT/WAT with a string tid also gets the "version" refusal; every other
    -- v ~= 1 message stops here.
    if (msg.t == "SIT" or msg.t == "WAT") and type(msg.tid) == "string" then
      ns.Session.refuseVersion(self, sender, msg.tid)
    end
    return
  end
  self.presence:receive(channel, sender, msg)
  self.lobby:receive(channel, sender, msg)
  ns.Session.receive(self, channel, sender, msg)
end
