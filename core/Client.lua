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
  self.invites = ns.Invites.new(self)
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
  ns.Session.stop(self) -- keeps the seat; END only for a host alone (no HI: BYE follows)
  self:send("GUILD", nil, { v = C.PROTOCOL, t = "BYE" })
  for timer in pairs(self.timers) do timer.cancel() end
  self.timers = {}
  self.invites:drop(false) -- a shown invitation does not outlive the client
end

function Client:peerOffline(name)
  self.presence:remove(name)
end

-- opts {game, access, turn, opt} -> tid | nil, code ("busy" "game" "access" "turn" "opt").
function Client:openTable(opts) return ns.Session.open(self, opts) end

-- Refusals arrive as the event "refused"(tid, why).
function Client:sit(tid, seat) ns.Session.request(self, "SIT", tid, seat) end
function Client:watch(tid) ns.Session.request(self, "WAT", tid) end

-- Stands up or stops watching (the extensions hear of it first: hook `leaving`).
function Client:stand()
  if self.session then self.session:hook("leaving") end
  ns.Session.stand(self)
end

-- A move by my seat -> true | nil, code (see Session.act).
function Client:act(action) return ns.Session.act(self, action) end

-- Host: start the next game of a host-started game -> true | nil, code (see Session.startGame).
function Client:startGame() return ns.Session.startGame(self) end

-- My automatic move -> true | nil, code (see Session.playAuto).
function Client:playAuto() return ns.Session.playAuto(self) end

-- My roll in a game with server rolls -> true | nil, code (see Rolls.roll).
function Client:roll() return ns.Rolls.roll(self) end

-- A server roll seen in chat (`shown` normalized, my own as env.me); emits
-- "rollSeen"(shown, n, lo, hi) first, always (see Rolls.seen).
function Client:rollSeen(shown, n, lo, hi) ns.Rolls.seen(self, shown, n, lo, hi) end

-- A group invite from `shown` (normalized): accept it automatically? Only from
-- the host of the table where I hold a seat, when its game needs a group.
function Client:groupInviteFrom(shown) return ns.Party.inviteFrom(self, shown) end

-- My group changed (who is in it, its leader or size): "session" again.
function Client:groupChanged()
  if self.session then ns.Session.emit(self) end
end

-- Host of a table with a free seat: invite `name` -> true | nil, code
-- ("nothost" "unknown" "seated" "pending"). The answer arrives as "inviteAnswer".
function Client:invite(name) return self.invites:send(name) end

-- An "invite" event's table: answer "yes", "no" or "snooze" (see core/Invites.lua).
function Client:answerInvite(tid, answer) self.invites:answer(tid, answer) end

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
    -- A whispered SIT/WAT with a string tid also gets the "version" refusal;
    -- every other v ~= 1 message stops here.
    if channel == "WHISPER" and (msg.t == "SIT" or msg.t == "WAT") and type(msg.tid) == "string" then
      ns.Session.refuseVersion(self, sender, msg.tid)
    end
    return
  end
  self.presence:receive(channel, sender, msg)
  self.lobby:receive(channel, sender, msg)
  ns.Session.receive(self, channel, sender, msg)
  self.invites:receive(channel, sender, msg)
end
