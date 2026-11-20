local _, ns = ...

-- Invitations to a table. Host side: client:invite(name) whispers INV, adds the
-- name to the session's invited set (the access list of an "invite" table) and
-- waits for INR; on an "invite" table the seated players hear the name (INA)
-- so that whoever claims the table next lets the same people in. Invitee side: an INV is either declined at once (INR "auto"
-- with a reason, no "invite" event) or shown until it is answered, runs out
-- after INVITE_SECONDS (INR "auto" "timeout") or goes stale because its table
-- filled or closed ("inviteGone"). A "yes" sits down through the lobby record.
--
-- Events: "invite"({tid, game, host, seats, expires}) and "inviteGone"(tid) on
-- the invitee, "inviteAnswer"(name, a, why) on the host.
-- Owned by a Client: timers go through client:after so client:stop cancels them.
local Invites = {}
Invites.__index = Invites
ns.Invites = Invites

local C = ns.Const
local copy = ns.Util.copy

local ANSWERS = { yes = true, no = true, auto = true }

local function message(t, fields)
  fields.v, fields.t = C.PROTOCOL, t
  return fields
end

local function freeSeat(seats)
  for i = 1, #seats do
    if seats[i] == false then return i end
  end
  return nil
end

local function seated(seats, name)
  for i = 1, #seats do
    if seats[i] == name then return true end
  end
  return false
end

-- Why an invitation is declined without asking, or nil. `atTable`: already at
-- another table; `snoozeUntil` and `epochNow` are on the env.epoch() clock.
function Invites.autoReason(status, snoozeUntil, epochNow, atTable)
  if status.combat then return "combat" end
  if status.instance then return "instance" end
  if status.busy or atTable then return "busy" end
  if epochNow < (snoozeUntil or 0) then return "snooze" end
  return nil
end

function Invites.new(client)
  local self = setmetatable({
    client = client,
    sent = {},       -- host side: invitee name -> { tid, timer }
    received = nil,  -- invitee side: { tid, game, host, seats, expires, timer }
  }, Invites)
  client:on("session", function(s) self:sessionChanged(s) end)
  client:on("tables", function() self:tablesChanged() end)
  return self
end

---------------------------------------------------------------------------
-- Host side
---------------------------------------------------------------------------

-- Host: the seat an invited player's SIT gets. Invitees who say yes at the same
-- moment all ask for the first free seat of their lobby record; whoever comes
-- second gets the lowest free seat instead of "taken". SIT cannot say that it
-- answers an invitation, so the rule covers any SIT from a name in my invited
-- set for an occupied seat; a SIT from anyone else, or for a seat that does
-- not exist, is left as it is (refused "taken" by Session:check).
function Invites.seatFor(s, sender, seat)
  if s.invited and s.invited[sender] and type(seat) == "number" and type(s.seats[seat]) == "string" then
    return freeSeat(s.seats) or seat
  end
  return seat
end

-- -> true | nil, code ("nothost" "unknown" "seated" "pending").
function Invites:send(name)
  local client = self.client
  local s = client.session
  if not s or s.role ~= "host" or not freeSeat(s.seats) then return nil, "nothost" end
  local peer = type(name) == "string" and client.presence:get(name)
  if not peer or peer.incompatible then return nil, "unknown" end
  if seated(s.seats, name) then return nil, "seated" end
  local pending = self.sent[name]
  if pending and pending.tid == s.tid then return nil, "pending" end
  if pending then pending.timer.cancel() end
  s.invited[name] = true
  local entry = { tid = s.tid }
  -- An invitee that never answers (offline, no addon any more) is given up a
  -- little after its own toast would have run out.
  entry.timer = client:after(C.INVITE_SECONDS + C.INVITE_GRACE, function()
    if self.sent[name] ~= entry then return end
    self.sent[name] = nil
    client.events:emit("inviteAnswer", name, "auto", "timeout")
  end)
  self.sent[name] = entry
  client:send("WHISPER", name, message("INV", { tid = s.tid, g = s.game, h = client.env.me, s = copy(s.seats) }))
  -- Seated players may become host: they learn the new name at once (INA), so
  -- an invited watcher is still let in after a claim. Newcomers get it in SNP.
  if s.access == "invite" then
    local note = message("INA", { tid = s.tid, e = s.epoch, n = name })
    for i = 1, #s.seats do
      local p = s.seats[i]
      if p and p ~= client.env.me then client:send("WHISPER", p, note) end
    end
  end
  return true
end

-- INA from my current host at my epoch: one more name for the invited set.
function Invites:onAdded(sender, m)
  local s = self.client.session
  if not s or s.role == "host" or s.tid ~= m.tid or s.host ~= sender or s.epoch ~= m.e then return end
  if type(m.n) ~= "string" then return end
  s.invited = s.invited or {}
  s.invited[m.n] = true
end

function Invites:onAnswer(sender, m)
  local entry = self.sent[sender]
  if not entry or entry.tid ~= m.tid or not ANSWERS[m.a] then return end
  if m.why ~= nil and type(m.why) ~= "string" then return end
  entry.timer.cancel()
  self.sent[sender] = nil
  self.client.events:emit("inviteAnswer", sender, m.a, m.why)
end

-- Invitations for a table I no longer host, or that has no free seat left, are dropped.
function Invites:sessionChanged(s)
  for name, entry in pairs(self.sent) do
    if not s or s.role ~= "host" or s.tid ~= entry.tid or not freeSeat(s.seats) then
      entry.timer.cancel()
      self.sent[name] = nil
    end
  end
end

---------------------------------------------------------------------------
-- Invitee side
---------------------------------------------------------------------------

local function reply(client, host, tid, a, why)
  client:send("WHISPER", host, message("INR", { tid = tid, a = a, why = why }))
end

-- The shown invitation ends without an answer from me.
function Invites:drop(notify)
  local r = self.received
  if not r then return end
  self.received = nil
  r.timer.cancel()
  if notify then self.client.events:emit("inviteGone", r.tid) end
end

function Invites:onInvite(sender, m)
  local client, env = self.client, self.client.env
  if m.h ~= sender or type(m.g) ~= "string" or type(m.s) ~= "table" then return end
  local r = self.received
  if r and r.tid == m.tid and r.host == sender then return end -- a repeated whisper
  if r then return reply(client, sender, m.tid, "auto", "busy") end
  local s = client.session
  local why = Invites.autoReason(env.status(), env.db.snoozeUntil, env.epoch(), s ~= nil and s.tid ~= m.tid)
  if why then return reply(client, sender, m.tid, "auto", why) end
  r = { tid = m.tid, game = m.g, host = sender, seats = copy(m.s), expires = env.now() + C.INVITE_SECONDS }
  r.timer = client:after(C.INVITE_SECONDS, function()
    if self.received ~= r then return end
    reply(client, r.host, r.tid, "auto", "timeout")
    self:drop(true)
  end)
  -- Known to the lobby already: from now on its record going away means the table closed.
  r.listed = client.lobby:get(r.tid) ~= nil
  self.received = r
  client.events:emit("invite", { tid = r.tid, game = r.game, host = r.host, seats = copy(r.seats), expires = r.expires })
  self:tablesChanged()
end

-- The invitation's table filled up or was closed: the invitation is stale.
function Invites:tablesChanged()
  local r = self.received
  if not r then return end
  local rec = self.client.lobby:get(r.tid)
  if rec then
    r.listed = true
    if not freeSeat(rec.seats) then self:drop(true) end
  elseif r.listed then
    self:drop(true)
  end
end

-- answer "yes" | "no" | "snooze". "snooze" says "no" and keeps further
-- invitations away for SNOOZE_SECONDS. "yes" asks for the lowest free seat of
-- the lobby record; without one it is refused locally ("gone" or "taken").
function Invites:answer(tid, answer)
  if answer ~= "yes" and answer ~= "no" and answer ~= "snooze" then return end
  local client, env = self.client, self.client.env
  local r = self.received
  if r and r.tid == tid then
    reply(client, r.host, tid, answer == "yes" and "yes" or "no")
    self:drop(false)
  end
  if answer == "snooze" then env.db.snoozeUntil = env.epoch() + C.SNOOZE_SECONDS end
  if answer ~= "yes" then return end
  local rec = client.lobby:get(tid)
  if not rec then return client.events:emit("refused", tid, "gone") end
  local seat = freeSeat(rec.seats)
  if not seat then return client.events:emit("refused", tid, "taken") end
  ns.Session.request(client, "SIT", tid, seat)
end

local HANDLERS = { INV = Invites.onInvite, INR = Invites.onAnswer, INA = Invites.onAdded }

-- A v=1 message (already validated by the client); INV, INR and INA count only by WHISPER.
function Invites:receive(channel, sender, m)
  local handler = HANDLERS[m.t]
  if not handler or channel ~= "WHISPER" or type(m.tid) ~= "string" then return end
  handler(self, sender, m)
end
