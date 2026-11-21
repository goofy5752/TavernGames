local _, ns = ...

-- The WoW binding of the core: saved variables (AceDB), the addon channel
-- (AceComm), game events, the own full name, and the env table that
-- Client.new receives. Produces for ui/: ns.addon, ns.client, ns.db,
-- ns.ready(fn), ns.classColor(cls), ns.bots, ns.noGuild.
local C, Names, L = ns.Const, ns.Names, ns.L

local Adapter = {
  -- Adapter-level message types (never passed to the Client):
  -- type -> fn(distribution, rawSender, msg).
  handlers = {},
  whispered = {}, -- whisper target -> GetTime() of the last whisper
}
ns.Adapter = Adapter

-- Which AceDB section holds each db key.
-- fairKeep: core/DealKeep.lua; lastAt: the table I am at (core/Presence.lua).
local CHAR_KEYS = { snoozeUntil = true, busy = true, debug = true, fairKeep = true, lastAt = true }
local GLOBAL_KEYS = { lang = true, introDone = true, minimap = true }
Adapter.DEFAULTS = {
  char = { snoozeUntil = 0, busy = false, debug = false },
  global = { introDone = false, minimap = { hide = false } },
}

local ALERT = { EV = true, ACT = true, SNP = true }
local CHANNELS = { GUILD = true, WHISPER = true }
local WHO_WAIT = 5 -- seconds of roster lookup before asking the guild channel
local NOT_FOUND_WINDOW = 5 -- seconds a whisper target's "player not found" line stays hidden
local ROSTER_ASK_GAP = 10 -- seconds between roster refreshes asked for by unknown senders
local INK = { 243 / 255, 226 / 255, 192 / 255 }

-- The db table of the env contract over an AceDB object: char keys and global
-- keys go to their own section; any other key is a programming error.
function Adapter.dbProxy(aceDB)
  local function section(key)
    if CHAR_KEYS[key] then return aceDB.char end
    if GLOBAL_KEYS[key] then return aceDB.global end
    return nil
  end
  return setmetatable({}, {
    __index = function(_, key)
      local s = section(key)
      if s then return s[key] end
      return nil
    end,
    __newindex = function(_, key, value)
      local s = section(key)
      if not s then error("TavernGames: unknown db key " .. tostring(key), 2) end
      s[key] = value
    end,
  })
end

function Adapter.priority(msg)
  if type(msg) == "table" and ALERT[msg.t] then return "ALERT" end
  return "NORMAL"
end

-- `text` with every Lua pattern magic character escaped: it matches itself.
-- The one copy of that rule (wow/Rolls.lua uses it too).
function Adapter.escape(text)
  return (text:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1"))
end

-- A Lua pattern for the text string.format(fmt, name) gives; captures the name.
function Adapter.pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = Adapter.escape(fmt):gsub("%%%%s", "(.+)")
  return "^" .. p .. "$"
end

-- The player name in a system line's capture, which may be a player link
-- (normalized). The one copy of the link strip (wow/Rolls.lua uses it too).
local function nameIn(captured)
  return Names.normalize(captured:match("|Hplayer:([^:|]+)") or captured)
end
Adapter.nameIn = nameIn

local function match(pattern, text)
  if not pattern or type(text) ~= "string" then return nil end
  local captured = text:match(pattern)
  return captured and nameIn(captured)
end

function Adapter.say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffb0813f" .. L("addon.title") .. "|r: " .. text)
end

-- Protocol trace (/tavern debug): printed to the chat frame while db.debug is on.
local trace = ns.Trace.new()
Adapter.trace = trace

local function printTrace(line)
  line = line:gsub("^out ", "> "):gsub("^in ", "< ")
  DEFAULT_CHAT_FRAME:AddMessage("TAVG " .. line)
end

function Adapter.setDebug(on)
  ns.db.debug = on and true or false
  trace.print = on and printTrace or nil
end

function Adapter.log(dir, channel, peer, msg) trace:add(dir, channel, peer, msg) end

local addon = LibStub("AceAddon-3.0"):NewAddon("TavernGames", "AceComm-3.0")
ns.addon = addon
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
Adapter.wire = wire

-- To the addon channel; AceComm splits text above 255 bytes.
local function rawSend(channel, target, msg)
  local okPack, text = pcall(wire.pack, wire, msg)
  if not okPack then
    Adapter.log("drop", channel, target, msg)
    return
  end
  if channel == "WHISPER" then Adapter.whispered[target] = GetTime() end
  addon:SendCommMessage(C.PREFIX, text, channel, target, Adapter.priority(msg))
end

-- An adapter-level message (not from the Client), traced like the Client's own.
function Adapter.send(channel, target, msg)
  rawSend(channel, target, msg)
  Adapter.log("out", channel, target, msg)
end

local function timer(seconds, fn)
  local t = C_Timer.NewTimer(seconds or 0, fn)
  return { cancel = function() t:Cancel() end }
end

-- Cheap entropy for the seed pool (core/Fair.lua): the client's clocks, the
-- frame rate and the address of a fresh table. The two finer ones are used
-- only where the client has them.
local function entropy()
  return table.concat({
    tostring(GetTime()), tostring(GetServerTime()),
    type(debugprofilestop) == "function" and tostring(debugprofilestop()) or "",
    type(GetFramerate) == "function" and tostring(GetFramerate()) or "",
    tostring({}),
  }, "|")
end

local function baseEnv(me, guid, cls)
  return {
    me = me, guid = guid, cls = cls,
    now = function() return GetTime() end,
    epoch = function() return GetServerTime() end,
    after = timer, entropy = entropy,
  }
end

local function status()
  local inInstance = IsInInstance()
  return {
    combat = InCombatLockdown() and true or false,
    instance = inInstance and true or false,
    busy = (ns.db.busy or UnitIsDND("player")) and true or false,
  }
end

local function inGroup(guid)
  return IsGUIDInGroup ~= nil and IsGUIDInGroup(guid) and true or false
end

-- A bot's env (Bots.spawn replaces send); bots keep their settings in memory.
-- Of the roll and group calls a bot has only env.random (see ns.RollChat.env).
function Adapter.botEnv(name, cls)
  local env = baseEnv(name, "Bot-" .. name, cls)
  env.send = function() end
  env.status = function() return { combat = false, instance = false, busy = false } end
  env.inGroup = function() return false end
  env.db = { introDone = true, busy = false, snoozeUntil = 0, debug = false, minimap = { hide = true } }
  ns.RollChat.env(env, true)
  return env
end

local readyQueue = {}

function ns.ready(fn)
  if ns.client then return fn(ns.client) end
  readyQueue[#readyQueue + 1] = fn
end

-- The human Client under `name`; ready callbacks run before it starts.
function Adapter.createClient(name, send)
  local _, cls = UnitClass("player")
  local env = baseEnv(name, UnitGUID("player"), cls)
  env.send, env.status, env.inGroup, env.db, env.log = send, status, inGroup, ns.db, Adapter.log
  ns.RollChat.env(env, false)
  local client = ns.Client.new(env)
  ns.client, Adapter.env = client, env
  local queue = readyQueue
  readyQueue = {}
  for i = 1, #queue do queue[i](client) end
  client:start()
  return client
end

function ns.classColor(cls)
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local c = colors and colors[cls]
  if c then return c.r, c.g, c.b end
  return INK[1], INK[2], INK[3]
end

-- Own full name: UnitName gives only the first name, so the roster entry with
-- my GUID gives it, or else the echo of a WHO on the guild channel.
local lookingUp = false

local function found(name)
  if ns.client or not name then return end
  lookingUp = false
  Adapter.createClient(name, rawSend)
end

local function requestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then
    C_GuildInfo.GuildRoster()
  elseif GuildRoster then
    GuildRoster()
  end
end

function Adapter.lookUpName()
  if ns.client or lookingUp then return end
  if not IsInGuild() then
    ns.noGuild = true
    return
  end
  ns.noGuild = false
  lookingUp = true
  requestRoster()
  C_Timer.NewTimer(WHO_WAIT, function()
    if ns.client then return end
    Adapter.send("GUILD", nil, { v = C.PROTOCOL, t = "WHO", id = UnitGUID("player") })
  end)
end

Adapter.handlers.WHO = function(distribution, rawSender, msg)
  if distribution == "GUILD" and msg.id == UnitGUID("player") then found(Names.normalize(rawSender)) end
end

-- Roster: my own entry, the guild's names, and guild members who went from
-- online to offline.
local lastOnline

-- Guild gate: only a sender listed in the latest roster scan (or myself) reaches
-- the Client, on GUILD and WHISPER alike. Nothing is accepted before the first
-- scan. A sender the scan does not list (a stranger, or a member who joined
-- after it) is dropped and a fresh roster is asked for, at most once per
-- ROSTER_ASK_GAP; his later messages pass once a scan lists him. Losing a
-- newcomer's first messages is harmless: HI and TBL repeat, and a guild member's
-- client answers my own HI.
Adapter.members = {} -- normalized name -> true, from the latest roster scan
local lastRosterAsk

function Adapter.isMember(name)
  if Adapter.members[name] then return true end
  return ns.client ~= nil and name == ns.client.env.me
end

local function askRoster()
  local now = GetTime()
  if lastRosterAsk and now - lastRosterAsk < ROSTER_ASK_GAP then return end
  lastRosterAsk = now
  requestRoster()
end

local function scanRoster()
  local myGuid = UnitGUID("player")
  local online, members = {}, {}
  for i = 1, (GetNumGuildMembers()) do
    local raw, _, _, _, _, _, _, _, isOnline, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    local name = Names.normalize(raw)
    if name then
      if guid == myGuid then found(name) end
      online[name] = isOnline and true or false
      members[name] = true
    end
  end
  Adapter.members = members
  local client = ns.client
  if client and lastOnline then
    for name, was in pairs(lastOnline) do
      if was and online[name] == false then client:peerOffline(name) end
    end
  end
  lastOnline = online
end

local notFoundPattern, offlinePattern

local function hideNotFound(_, _, text)
  local name = match(notFoundPattern, text)
  local at = name and Adapter.whispered[name]
  if not at then return false end
  return GetTime() - at <= NOT_FOUND_WINDOW
end

local function addFilter(event, fn)
  if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter(event, fn)
  elseif ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
    ChatFrameUtil.AddMessageEventFilter(event, fn)
  end
end

local EVENTS = {
  PLAYER_GUILD_UPDATE = function() Adapter.lookUpName() end,
  GUILD_ROSTER_UPDATE = scanRoster,
  CHAT_MSG_SYSTEM = function(text)
    local name = match(offlinePattern, text)
    if name and ns.client then ns.client:peerOffline(name) end
  end,
  PLAYER_LOGOUT = function()
    if ns.client then ns.client:stop() end
  end,
}

function addon:OnInitialize()
  local aceDB = LibStub("AceDB-3.0"):New("TavernGamesDB", Adapter.DEFAULTS, true)
  ns.db = Adapter.dbProxy(aceDB)
  if ns.db.lang then ns.Locale.set(ns.db.lang) end
  Adapter.setDebug(ns.db.debug)
  self:RegisterComm(C.PREFIX, "OnCommReceived")
end

function addon:OnEnable()
  notFoundPattern = Adapter.pattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
  offlinePattern = Adapter.pattern(ERR_FRIEND_OFFLINE_S)
  addFilter("CHAT_MSG_SYSTEM", hideNotFound)
  local frame = CreateFrame("Frame")
  for event in pairs(EVENTS) do frame:RegisterEvent(event) end
  frame:SetScript("OnEvent", function(_, event, ...) EVENTS[event](...) end)
  Adapter.lookUpName()
end

function addon:OnCommReceived(prefix, text, distribution, sender)
  if prefix ~= C.PREFIX or not CHANNELS[distribution] then return end
  local name = Names.normalize(sender)
  if not name then return end
  local msg = wire:unpack(text)
  if not msg then return end
  Adapter.lastRawSender = sender -- the raw form, for /tavern probe
  -- WHO and PRB check for themselves that they are my own echo (GUID, probe id).
  local handler = type(msg.t) == "string" and Adapter.handlers[msg.t]
  if handler then
    Adapter.log("in", distribution, name, msg)
    return handler(distribution, sender, msg)
  end
  if not Adapter.isMember(name) then
    Adapter.log("drop", distribution, name, msg)
    return askRoster()
  end
  if ns.client then ns.client:receive(distribution, name, msg) end
end

-- /tavern bots: "on", "off", or "wait" while the own name is still unknown.
-- Outside a guild the bots get a local-only client named after UnitName.
function Adapter.toggleBots()
  if ns.bots then
    ns.bots:disable()
    ns.bots = nil
    return "off"
  end
  if not ns.client then
    if not ns.noGuild then return "wait" end
    Adapter.createClient(Names.normalize(UnitName("player")), function() end)
  end
  ns.bots = ns.Bots.enable(ns.client, Adapter.env, Adapter.botEnv)
  return "on"
end
