local _, ns = ...

-- Composes the core modules; the only API ui/ and wow/ call.
local Client = {}
Client.__index = Client
ns.Client = Client

local C = ns.Const

function Client.new(env)
  local self = setmetatable({ env = env, events = ns.Emitter.new(), timers = {}, running = false }, Client)
  self.presence = ns.Presence.new(self)
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
  -- Task 4: stand up first when seated or watching.
  self:send("GUILD", nil, { v = C.PROTOCOL, t = "BYE" })
  for timer in pairs(self.timers) do timer.cancel() end
  self.timers = {}
  self.running = false
end

function Client:peerOffline(name)
  self.presence:remove(name)
end

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
    -- Task 4: a SIT/WAT with a string tid is also handed to the session for the
    -- "version" refusal; every other v ~= 1 message stops here.
    return
  end
  self.presence:receive(channel, sender, msg)
end
