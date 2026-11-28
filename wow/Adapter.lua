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
-- fairKeep: core/DealKeep.lua; lastAt: the table I am at (core/Presence.lua);
-- bookKeep, bookSpent: the Hold'em table key and spend (core/Book.lua);
-- stakeSeen, stakeLeft, stakeSat, stakeLog, stakeChess: my own outcome notes, the stake I
-- sat down for and what I sent at that table (core/StakesWatch.lua, core/StakesChess.lua), never
-- sent; ledger: the guild's gold ledger, account-wide; sound: false mutes ns.Art.play;
-- theme, deck: the character's skin key and deck (ui/Theme.lua), unset until chosen;
-- probeArt: the last /tavern probe art report, kept to be read from SavedVariables.
local CHAR_KEYS = { snoozeUntil = true, busy = true, debug = true, fairKeep = true, lastAt = true,
  bookKeep = true, bookSpent = true, stakeSeen = true, stakeLeft = true, stakeSat = true, stakeLog = true, stakeChess = true, paySent = true,
  theme = true, deck = true }
local GLOBAL_KEYS = { lang = true, introDone = true, minimap = true, ledger = true, scale = true, sound = true, probeArt = true }
Adapter.CHAR_KEYS, Adapter.GLOBAL_KEYS = CHAR_KEYS, GLOBAL_KEYS
Adapter.DEFAULTS = {
  char = { snoozeUntil = 0, busy = false, debug = false },
  global = { introDone = false, minimap = { hide = false }, sound = true },
}

local ALERT = { EV = true, ACT = true, SNP = true }
local BULK = { LVC = true, LID = true } -- the ledger's sync (and a whispered LEV) yields to the tables
local CHANNELS = { GUILD = true, WHISPER = true }
local WHO_WAIT = 5 -- seconds of roster lookup before asking the guild channel
local NOT_FOUND_WINDOW = 5 -- seconds a whisper target's "player not found" line stays hidden
local ROSTER_ASK_GAP = 10 -- seconds between roster refreshes asked for by unknown senders
local INK = { 242 / 255, 230 / 255, 200 / 255 } -- the ink token (ui/Theme.lua), for a class unknown

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

-- ChatThrottleLib's priority of a message on `channel`: a live GUILD LEV stays NORMAL.
function Adapter.priority(msg, channel)
  if type(msg) ~= "table" then return "NORMAL" end
  if ALERT[msg.t] then return "ALERT" end
  if BULK[msg.t] or (msg.t == "LEV" and channel == "WHISPER") then return "BULK" end
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

-- The game value at a dotted `path` ("C_TradeInfo.SetTradeMoney"), looked up at
-- call time with rawget: an absent API reads as nil, never through a metatable of _G.
function Adapter.lookup(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = rawget(v, part)
  end
  return v
end

-- The first of the paths that holds a function, or nil.
function Adapter.fn(...)
  for i = 1, select("#", ...) do
    local f = Adapter.lookup((select(i, ...)))
    if type(f) == "function" then return f end
  end
  return nil
end

-- A value the game gave that may be compared and tested: not a secret value.
local function usable(v)
  local secret = Adapter.fn("issecretvalue")
  return not (secret and secret(v))
end

-- A copper value the game gave that can be used: a number from 0, not a secret value.
function Adapter.plain(v)
  return type(v) == "number" and v >= 0 and usable(v)
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
-- The ledger cuts its batches and counts its budget by the real packed size.
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end

-- To the addon channel; AceComm splits text above 255 bytes. done (optional)
-- runs once the last part has left (AceComm's callback per part), or at once when the message is dropped.
local function rawSend(channel, target, msg, done)
  local okPack, text = pcall(wire.pack, wire, msg)
  if not okPack then
    Adapter.log("drop", channel, target, msg)
    if done then done() end
    return
  end
  if channel == "WHISPER" then Adapter.whispered[target] = GetTime() end
  local callback = done and function(_, sent, total) if sent >= total then done() end end
  addon:SendCommMessage(C.PREFIX, text, channel, target, Adapter.priority(msg, channel), callback)
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

-- fn(...)'s first answer, or nil when it raises, is absent or is secret.
local function asks(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, got = pcall(fn, ...)
  if not ok or not usable(got) then return nil end
  return got or nil
end

-- The name of my guild, or nil: no guild, not known yet, or a secret value.
function Adapter.guildName()
  local name = asks(Adapter.fn("GetGuildInfo"), "player")
  return type(name) == "string" and name ~= "" and name or nil
end

-- The key of my guild's ledger (the guild's name, "-", my realm's), or nil
-- while the game client does not know my guild's name (right after login).
function Adapter.guildKey()
  local name = Adapter.guildName()
  local realm = asks(Adapter.fn("GetRealmName"))
  return name and name .. "-" .. (type(realm) == "string" and realm or "") or nil
end

-- A client started before my guild's name was known gets its ledger once it is
-- (ns.client:joinGuild): asked again on the guild's events.
function Adapter.joinGuild()
  local client = ns.client
  if not client or client.ledger then return end
  local key = Adapter.guildKey()
  if key then client:joinGuild(key) end
end

-- env.groupedWith(name): is `name` (normalized full name) in my party or raid?
-- From my own client's data only: its GUID from my guild roster scan in my
-- group, or the name in UnitInRaid / UnitInParty / the group roster; never a
-- GUID a player announced about itself (a host could name one outside my group).
local function groupedWith(name)
  local guid = Adapter.guids[name]
  if guid and inGroup(guid) then return true end
  if asks(UnitInRaid, name) or asks(UnitInParty, name) then return true end
  for i = 1, (asks(GetNumGroupMembers) or 0) do
    if Names.normalize(asks(GetRaidRosterInfo, i)) == name then return true end
  end
  return false
end

-- My race (UnitRace's file name, "Scourge") and sex (UnitSex: 2 male, 3 female)
-- for the portraits in my HI (core/Presence.lua); nil what the client does not say.
local function raceSex()
  local unitRace, unitSex = Adapter.fn("UnitRace"), Adapter.fn("UnitSex")
  local race, sex
  if unitRace then
    local ok, _, file = pcall(unitRace, "player")
    race = ok and type(file) == "string" and file or nil
  end
  if unitSex then
    local ok, got = pcall(unitSex, "player")
    sex = ok and (got == 2 or got == 3) and got or nil
  end
  return race, sex
end

-- The unit my client shows `name` (normalized full name) as: "player" for me;
-- for anyone else the unit of my own party or raid whose GUID is the one my guild
-- roster scan lists for that name (never a GUID a player announced about itself),
-- and only while UnitIsVisible says the client can draw it (far away or offline
-- a portrait would be a question mark). nil otherwise, or without UnitIsVisible.
function Adapter.unitOf(name)
  local env = Adapter.env
  if name == nil then return nil end
  if env and name == env.me then return "player" end
  local guid, visible = Adapter.guids[name], Adapter.fn("UnitIsVisible")
  if not (guid and visible) then return nil end
  -- One pcall over the walk: a unit whose answer is secret or raises is no unit.
  local ok, unit = pcall(function()
    local raid = asks(IsInRaid) and true or false
    for i = 1, raid and 40 or 4 do
      local u = (raid and "raid" or "party") .. i
      if asks(UnitGUID, u) == guid then return asks(visible, u) and u or nil end
    end
  end)
  return ok and unit or nil
end

-- My character's faction ("Alliance", "Horde", ...), or nil when the client
-- does not say (no UnitFactionGroup, a raise or a secret value).
function Adapter.faction()
  local got = asks(Adapter.fn("UnitFactionGroup"), "player")
  return type(got) == "string" and got or nil
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

-- The day number of the civil date y-m-d (1970-01-01 is day 0).
local function civilDay(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m > 2 and m - 3 or m + 9) + 2) / 5) + d - 1
  return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end

-- env.date(t): {d, m, day} of epoch t in my own zone, from WoW's date("*t", t)
-- (day: the local day number); core/Pay.lua's UTC arithmetic without it.
local function localDate(t)
  local date = Adapter.fn("date")
  local okDate, tm = false, nil
  if date then okDate, tm = pcall(date, "*t", t) end
  if not (okDate and type(tm) == "table" and tm.year and tm.month and tm.day) then return ns.Pay.utc(t) end
  return { d = tm.day, m = tm.month, day = civilDay(tm.year, tm.month, tm.day) }
end

-- env.money(): the copper in my bags, nil when the client cannot say.
local function money()
  local f = Adapter.fn("GetMoney")
  local okMoney, c = false, nil
  if f then okMoney, c = pcall(f) end
  if okMoney and Adapter.plain(c) then return c end
  return nil
end
Adapter.money = money

-- The human Client under `name`; ready callbacks run before it starts. Its
-- ledger store is ns.db.ledger[guild .. "-" .. realm]; without a guild name
-- now there is none (core/Client.lua logs it). Payment goes through env.money,
-- env.trade (wow/Trade.lua), env.mail (wow/Mail.lua) and env.date.
function Adapter.createClient(name, send)
  local _, cls = UnitClass("player")
  local env = baseEnv(name, UnitGUID("player"), cls)
  env.send, env.status, env.inGroup, env.db, env.log = send, status, inGroup, ns.db, Adapter.log
  env.groupedWith = groupedWith
  env.race, env.sex = raceSex()
  env.money, env.trade, env.mail, env.date = money, ns.Trade, ns.Mail, localDate
  env.guild = Adapter.guildKey() -- nil right after login, maybe: Adapter.joinGuild opens the ledger later
  env.member = Adapter.isMember
  env.loading, env.loadedAt = Adapter.loading, Adapter.loadedAt
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
Adapter.guids = {}   -- normalized name -> GUID, from the same scan (env.groupedWith)
Adapter.byGUID = {}  -- GUID -> normalized name, from the same scan (Adapter.nameOfGUID)
local lastRosterAsk

-- The guild member's full name (normalized) of a GUID, from the latest roster scan, or nil.
function Adapter.nameOfGUID(guid)
  if guid == nil then return nil end
  return Adapter.byGUID[guid]
end

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
  local online, members, guids, byGUID = {}, {}, {}, {}
  for i = 1, (GetNumGuildMembers()) do
    local raw, _, _, _, _, _, _, _, isOnline, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    local name = Names.normalize(raw)
    if name then
      if guid == myGuid then found(name) end
      online[name] = isOnline and true or false
      members[name], guids[name] = true, guid
      if guid then byGUID[guid] = name end
    end
  end
  Adapter.members, Adapter.guids, Adapter.byGUID = members, guids, byGUID
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

-- My client shows a loading screen (timers stand still, messages wait or are
-- lost) or it just ended: env.loading and env.loadedAt (GetTime()) of the env
-- contract, kept here too for a client created later. core/Dice.lua blames
-- nobody for a throw I missed that way.
local function loadingScreen(on)
  Adapter.loading = on and true or nil
  if not on then Adapter.loadedAt = GetTime() end
  local env = Adapter.env
  if env then env.loading, env.loadedAt = Adapter.loading, Adapter.loadedAt end
end

local EVENTS = {
  LOADING_SCREEN_ENABLED = function() loadingScreen(true) end,
  LOADING_SCREEN_DISABLED = function() loadingScreen(false) end,
  PLAYER_LEAVING_WORLD = function() loadingScreen(true) end,
  PLAYER_ENTERING_WORLD = function() loadingScreen(false) end,
  PLAYER_GUILD_UPDATE = function()
    Adapter.lookUpName()
    Adapter.joinGuild()
    if ns.Hall then ns.Hall.refresh() end
  end,
  GUILD_ROSTER_UPDATE = function(...)
    scanRoster(...)
    Adapter.joinGuild()
    if ns.Hall then ns.Hall.refresh() end
  end,
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
  if ns.Theme then ns.Theme.apply(ns.Theme.resolve(ns.db.theme, Adapter.faction())) end
  notFoundPattern = Adapter.pattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
  offlinePattern = Adapter.pattern(ERR_FRIEND_OFFLINE_S)
  addFilter("CHAT_MSG_SYSTEM", hideNotFound)
  local frame = CreateFrame("Frame")
  -- A client that does not know an event refuses to register it: left out.
  for event in pairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
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

-- Bots fill my table (/tavern bots fill, „Добави ботове“): bot mode is turned on
-- first when it is off -> "wait" (my name is not known yet), "nofill" (the
-- table takes no bots: Bots.canFill), or how many were asked; then true when
-- this call turned bot mode on.
function Adapter.fillBots(n)
  local started = false
  if not ns.bots then
    if Adapter.toggleBots() == "wait" then return "wait", false end
    started = true
  end
  return ns.bots:fill(n) or "nofill", started
end

-- My bots stand up from my table (/tavern bots clear, „Махни ботовете“) -> how
-- many left, or nil (bot mode off, or Bots.canClear says no).
function Adapter.clearBots() return ns.bots and ns.bots:clear() or nil end

-- Every bot-only table of mine closes (/tavern bots close, „Закрий“) -> how many.
function Adapter.closeBots() return ns.bots and ns.bots:closeAll() or 0 end

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
