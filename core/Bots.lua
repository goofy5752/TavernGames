local _, ns = ...

-- Bot mode: local fake players, each a full Client on a private Bus shared with
-- the human client, so one person can try every feature alone. Bots never reach
-- real players: enable() wraps env.send so that
--   * a WHISPER to a bot goes only to the bus;
--   * a GUILD message goes to the real send and to the bus;
--   * on the real side (GUILD and WHISPER to real players) a message whose tid
--     is a bot table (a bot as host, in its seats or in its invited set) is
--     dropped, and a HI whose `at` is a bot table goes out as a copy with `at`
--     cleared (the bus gets it unchanged);
--   * a table that was announced for real and then becomes a bot table gets one
--     real END, so real players do not keep a ghost of it.
-- A bot's WHISPER reaches the human or another bot through the bus (anything
-- else is dropped); a bot's GUILD reaches the human and the other bots only.
-- Deliveries are flushed through env.after(0, ...).
-- enable() also wraps env.inGroup so that a bot's GUID counts as in my group
-- (no group invite and no "not in your group" hint for a bot, and bots may sit
-- at my "group" table), and forwards my "rollSeen" events to every bot, so a
-- bot that hosts Death Roll sees my server rolls. A bot has no env.roll and no
-- env.groupInvite: its rolls are table rolls (src "ask").
--
-- Behaviour: a bot accepts an invitation after ACCEPT_AFTER s (two bots that
-- accept at once both get a seat: see Invites.seatFor), on its turn makes its
-- automatic move (client:playAuto) after MOVE_AFTER s, in phase "match" asks
-- for a rematch after REMATCH_AFTER s, and as host starts the next game
-- START_AFTER s after any change that leaves Session.startable true (a game
-- the host starts, or the next match of an engine with `again`, once at least
-- minSeats are seated and no game runs).
local Bots = {}
Bots.__index = Bots
ns.Bots = Bots

local C = ns.Const
local copy = ns.Util.copy

local MAX_BOTS = 12
local STARTERS = { { "Бот Иванов", "PRIEST" }, { "Bot Barleybrew", "WARRIOR" }, { "Бот Петрова", "MAGE" } }
local SPARE_CLASSES = { "ROGUE", "HUNTER", "WARLOCK", "DRUID", "PALADIN", "SHAMAN", "PRIEST", "WARRIOR", "MAGE" }
local ACCEPT_AFTER, MOVE_AFTER, REMATCH_AFTER, START_AFTER = 1, 1.5, 2, 2

local function hasBot(self, seats)
  for i = 1, #(seats or {}) do
    if seats[i] and self.isBot[seats[i]] then return true end
  end
  return false
end

-- Is `tid` a bot table? -> involved (bot host, seat or invitee), hosted (bot host).
function Bots:tableKind(tid)
  local involved, hosted = false, false
  for i = 1, #self.list do
    local s = self.list[i].session
    if s and s.tid == tid then
      involved = true
      if s.role == "host" then hosted = true end
    end
  end
  local rec = self.client.lobby:get(tid)
  if rec then
    if self.isBot[rec.host] then involved, hosted = true, true end
    if hasBot(self, rec.seats) then involved = true end
  end
  local s = self.client.session
  if s and s.tid == tid then
    if hasBot(self, s.seats) then involved = true end
    for name in pairs(s.invited or {}) do
      if self.isBot[name] then involved = true end
    end
  end
  return involved, hosted
end

function Bots:schedule()
  if self.flushQueued then return end
  self.flushQueued = true
  self.env.after(0, function()
    self.flushQueued = false
    self.bus:flush()
  end)
end

function Bots:busSend(from, channel, target, msg)
  self.bus:send(from, channel, target, msg)
  self:schedule()
end

-- My message as it may reach real players: nil when its tid is a bot table, a
-- copy without `at` for a HI sent while I am at a bot table, else msg itself.
function Bots:realCopy(msg)
  if type(msg) ~= "table" then return msg end
  if type(msg.tid) == "string" and (self:tableKind(msg.tid)) then return nil end
  if msg.t == "HI" and type(msg.at) == "string" and (self:tableKind(msg.at)) then
    local real = copy(msg)
    real.at = nil
    return real
  end
  return msg
end

-- Tables that real players know of (a real TBL went out): tid -> epoch.
function Bots:noteReal(msg)
  if type(msg) ~= "table" or type(msg.tid) ~= "string" then return end
  if msg.t == "TBL" and type(msg.e) == "number" then
    self.announced[msg.tid] = msg.e
  elseif msg.t == "END" then
    self.announced[msg.tid] = nil
  end
end

-- A table real players know of became a bot table: one real END takes it off their hall.
function Bots:retire()
  for tid, epoch in pairs(self.announced) do
    if (self:tableKind(tid)) then
      self.announced[tid] = nil
      self.orig("GUILD", nil, { v = C.PROTOCOL, t = "END", tid = tid, e = epoch })
      -- My last real HI may still place me there.
      local presence = self.client.presence
      if presence.at == tid then self.orig("GUILD", nil, self:realCopy(presence:hi(false))) end
    end
  end
end

-- The human client's env.send while bot mode is on. No bot table and no bot
-- name ever goes out for real, by GUILD or by WHISPER.
local function humanSend(self)
  local orig, me = self.orig, self.env.me
  return function(channel, target, msg)
    self:retire()
    if channel == "WHISPER" and self.isBot[target] then return self:busSend(me, channel, target, msg) end
    local real = self:realCopy(msg)
    if real ~= nil then
      self:noteReal(real)
      orig(channel, target, real)
    end
    if channel == "GUILD" then self:busSend(me, channel, target, msg) end
  end
end

-- The next thing `bot` wants to do at its table -> do(), delay | nil. As host:
-- start the next game whenever client:startGame would.
local function nextAction(bot)
  local s = bot.session
  if not s or not s.mySeat then return nil end
  if ns.Session.startable(bot) then return function() bot:startGame() end, START_AFTER end
  if s.status ~= "live" or not s.state then return nil end
  local st = s.state
  if st.phase == "match" then
    if st.rematch and not st.rematch[s.mySeat] then
      return function() bot:act({ k = "rematch" }) end, REMATCH_AFTER
    end
    return nil
  end
  if st.turn ~= s.mySeat then return nil end
  return function() bot:playAuto() end, MOVE_AFTER
end

local function behave(bot)
  bot:on("invite", function(inv)
    bot:after(ACCEPT_AFTER, function()
      local r = bot.invites.received
      if r and r.tid == inv.tid then bot:answerInvite(inv.tid, "yes") end
    end)
  end)
  -- One pending step at a time; what to do is decided again when it fires.
  local step
  bot:on("session", function()
    if step then return end
    local act, delay = nextAction(bot)
    if not act then return end
    step = bot:after(delay, function()
      step = nil
      local now = nextAction(bot)
      if now then now() end
    end)
  end)
  -- Nobody came to my invite-only table: close it.
  bot:on("inviteAnswer", function(_, answer)
    local s = bot.session
    if answer ~= "yes" and s and s.role == "host" and s.access == "invite" and s:seatedCount() == 1 then
      bot:stand()
    end
  end)
end

function Bots:spawn(name, cls)
  local env = self.makeEnv(name, cls)
  env.send = function(channel, target, msg)
    if channel == "WHISPER" then
      if target == self.env.me or self.isBot[target] then self:busSend(name, channel, target, msg) end
    elseif channel == "GUILD" then
      self:busSend(name, channel, nil, msg)
    end
  end
  local bot = ns.Client.new(env)
  self.list[#self.list + 1] = bot
  self.isBot[name] = true
  if env.guid then self.botGuid[env.guid] = true end
  self.bus:join(name, function(channel, sender, msg) bot:receive(channel, sender, msg) end)
  behave(bot)
  bot:start()
  return bot
end

-- An idle bot (no table, nothing pending), spawning one while fewer than MAX_BOTS exist.
function Bots:idle()
  for i = 1, #self.list do
    local bot = self.list[i]
    if not bot.session and not bot.pending and not bot.invites.received then return bot end
  end
  if #self.list >= MAX_BOTS then return nil end
  local n = #self.list + 1
  return self:spawn("Бот Номер" .. n, SPARE_CLASSES[(n - 1) % #SPARE_CLASSES + 1])
end

-- An idle bot for a table of `game` (default "ttt") -> bot, game | nil (not a
-- playable game, bot mode off, or all MAX_BOTS busy).
local function idleFor(self, game)
  game = game or "ttt"
  if self.disabled or not ns.Games.engine(game) then return nil end
  local bot = self:idle()
  if not bot then return nil end
  return bot, game
end

-- An idle bot opens a guild table of `game` (default "ttt", the engine's default
-- options) and waits -> tid | nil.
function Bots:hostTable(game)
  local bot
  bot, game = idleFor(self, game)
  if not bot then return nil end
  return (bot:openTable{ game = game, access = "guild", turn = C.TURN_DEFAULT })
end

-- An idle bot opens an invite-only table of `game` (default "ttt", the engine's
-- default options) and invites me -> tid | nil.
function Bots:inviteMe(game)
  local bot
  bot, game = idleFor(self, game)
  if not bot then return nil end
  local tid = bot:openTable{ game = game, access = "invite", turn = C.TURN_DEFAULT }
  if not tid then return nil end
  -- After the pending deliveries, so the bot has heard my HI.
  bot:after(0, function()
    if not bot:invite(self.env.me) and bot.session and bot.session:seatedCount() == 1 then bot:stand() end
  end)
  return tid
end

-- My env.inGroup while bot mode is on: a bot's GUID is in my group.
local function humanInGroup(self)
  local orig = self.origInGroup
  return function(guid)
    if self.botGuid[guid] then return true end
    if orig then return orig(guid) end
    return false
  end
end

-- client: the human Client; env: its env (send and inGroup are wrapped);
-- makeEnv(name, cls) -> env.
function Bots.enable(client, env, makeEnv)
  local self = setmetatable({
    client = client, env = env, makeEnv = makeEnv, orig = env.send, origInGroup = env.inGroup,
    bus = ns.Bus.new(), list = {}, isBot = {}, botGuid = {}, announced = {}, flushQueued = false, disabled = false,
  }, Bots)
  self.bus:join(env.me, function(channel, sender, msg) client:receive(channel, sender, msg) end)
  env.send = humanSend(self)
  env.inGroup = humanInGroup(self)
  -- My sightings of server rolls reach every bot (only until disable).
  client:on("rollSeen", function(shown, n, lo, hi)
    if self.disabled then return end
    for i = 1, #self.list do self.list[i]:rollSeen(shown, n, lo, hi) end
  end)
  for i = 1, #STARTERS do self:spawn(STARTERS[i][1], STARTERS[i][2]) end
  return self
end

-- Leaves any bot table, stops every bot (their BYE reaches only me), forgets
-- the bot tables, stops forwarding my roll sightings and restores env.send and
-- env.inGroup.
function Bots.disable(self)
  if self.disabled then return end
  local client = self.client
  local s = client.session
  if s and (self:tableKind(s.tid)) then client:stand() end
  self.bus:flush()
  for i = 1, #self.list do self.list[i]:stop() end
  self.bus:flush()
  for _, rec in ipairs(client.lobby:tables()) do
    if self.isBot[rec.host] or hasBot(self, rec.seats) then client.lobby:remove(rec.tid) end
  end
  for name in pairs(self.isBot) do client:peerOffline(name) end
  self.disabled = true
  self.env.send = self.orig
  self.env.inGroup = self.origInGroup
  for name in pairs(self.isBot) do self.bus:leave(name) end
  self.bus:leave(self.env.me)
end
