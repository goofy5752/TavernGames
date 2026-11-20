-- Fake WoW client for testing wow/ and ui/: a sandbox global table holding the
-- game API the addon uses, the real LibStub, CallbackHandler, AceSerializer,
-- LibDeflate and AceDB loaded into it, and a fake AceAddon/AceComm that records
-- every SendCommMessage. The wow/ files from the TOC run with the sandbox as
-- their globals, so whatever global they create is visible in `self.G`. With
-- `opts.ui` the ui/ files run too, over the fake widgets of frames.lua, the real
-- LibDataBroker and a fake LibDBIcon that records Register calls.
local Frames = require("frames")

local Wow = {}
Wow.__index = Wow

Wow.GUID = "Player-1-00000001"
Wow.FIRST = "Иван" -- what UnitName("player") gives on Forever
Wow.EPOCH0 = 1700000000

local BUILTINS = {
  "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset",
  "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
  "loadstring", "string", "table", "math", "coroutine",
}
local LIBS = {
  "Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
  "Libs/AceSerializer-3.0/AceSerializer-3.0.lua", "Libs/LibDeflate/LibDeflate.lua",
  "Libs/AceDB-3.0/AceDB-3.0.lua",
}

-- Called by the probe test: any call to these fails the test.
local function forbidden(name) return function() error("called " .. name, 2) end end

local function run(path, G, ...)
  local chunk, err = loadfile(path)
  if not chunk then error(err, 0) end
  setfenv(chunk, G)
  return chunk(...)
end

-- TOC lines starting with `prefix`, in TOC order.
local function tocFiles(prefix)
  local out = {}
  for line in io.lines("TavernGames.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line:sub(1, #prefix) == prefix then out[#out + 1] = line end
  end
  return out
end

-- opts.saved: a TavernGamesDB table from an earlier session (a /reload).
-- opts.ui: also run the ui/ files.
function Wow.new(opts)
  opts = opts or {}
  local self = setmetatable({
    clock = 0, timers = {}, seq = 0, frames = {}, sent = {}, chat = {}, filters = {},
    roster = {}, rosterRequests = 0, inGuild = false, combat = false, instance = false,
    dnd = false, group = {}, money = 0, icons = {}, sounds = {}, reloads = 0,
  }, Wow)
  local G = {}
  for _, name in ipairs(BUILTINS) do G[name] = _G[name] end
  G._G = G
  self.G = G

  G.securecallfunction = function(fn, ...) return fn(...) end
  G.geterrorhandler = function() return error end
  G.GetTime = function() return self.clock end
  G.GetServerTime = function() return Wow.EPOCH0 + math.floor(self.clock) end
  G.C_Timer = {
    NewTimer = function(seconds, fn)
      self.seq = self.seq + 1
      local t = { due = self.clock + seconds, seq = self.seq, fn = fn }
      self.timers[#self.timers + 1] = t
      return { Cancel = function() t.cancelled = true end }
    end,
  }
  G.C_Timer.After = function(seconds, fn) G.C_Timer.NewTimer(seconds, fn) end
  G.CreateFrame = Frames.factory(G, function(f) self.frames[#self.frames + 1] = f end)
  G.UIParent = G.CreateFrame("Frame")
  G.GameTooltip = Frames.tooltip(G.CreateFrame)
  G.GameTooltip:Hide()
  G.GetMoney = function() return self.money end
  G.UnitName = function(unit) if unit == "player" then return Wow.FIRST end end
  G.UnitGUID = function(unit) if unit == "player" then return Wow.GUID end end
  G.UnitClass = function() return "Маг", "MAGE", 8 end
  G.UnitRace = function() return "Човек", "Human", 1 end
  G.UnitFactionGroup = function() return "Alliance", "Alliance" end
  G.GetRealmName = function() return "Forever" end
  G.GetLocale = function() return "enUS" end
  G.GetCurrentRegion = function() return 3 end
  G.GetCurrentRegionName = function() return "EU" end
  G.IsInGuild = function() return self.inGuild end
  G.C_GuildInfo = { GuildRoster = function() self.rosterRequests = self.rosterRequests + 1 end }
  G.GetNumGuildMembers = function() return #self.roster, #self.roster end
  G.GetGuildRosterInfo = function(i)
    local m = self.roster[i]
    return m.name, "Член", 1, 60, "Маг", "Град", "", "", m.online, 0, "MAGE", 0, 0, false, false, 0, m.guid
  end
  G.InCombatLockdown = function() return self.combat end
  G.IsInInstance = function()
    if self.instance then return true, "party" end
    return false, "none"
  end
  G.UnitIsDND = function() return self.dnd end
  G.IsGUIDInGroup = function(guid) return self.group[guid] == true end
  G.ChatFrame_AddMessageEventFilter = function(event, fn)
    self.filters[event] = self.filters[event] or {}
    table.insert(self.filters[event], fn)
  end
  G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) self.chat[#self.chat + 1] = text end }
  G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  G.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
  G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
  G.SOUNDKIT = { TELL_MESSAGE = 3081 }
  G.PlaySound = function(id, channel) self.sounds[#self.sounds + 1] = { id, channel } end
  G.SlashCmdList = {}
  G.ReloadUI = function() self.reloads = self.reloads + 1 end
  G.InitiateTrade = forbidden("InitiateTrade")
  G.C_TradeInfo = { SetTradeMoney = forbidden("C_TradeInfo.SetTradeMoney") }
  G.SetSendMailMoney = forbidden("SetSendMailMoney")
  G.SendMail = forbidden("SendMail")
  if opts.saved then G.TavernGamesDB = opts.saved end

  for _, path in ipairs(LIBS) do run(path, G, "TavernGames") end
  local LibStub = G.LibStub
  local AceAddon = LibStub:NewLibrary("AceAddon-3.0", 1)
  function AceAddon.NewAddon(_, name)
    local addon = { name = name }
    function addon.RegisterComm(obj, prefix, method)
      self.comm = { obj = obj, prefix = prefix, method = method or "OnCommReceived" }
    end
    function addon.SendCommMessage(_, prefix, text, dist, target, prio)
      assert(type(prefix) == "string" and type(text) == "string" and type(dist) == "string")
      assert(prio == "BULK" or prio == "NORMAL" or prio == "ALERT", "bad prio " .. tostring(prio))
      self.sent[#self.sent + 1] = { prefix = prefix, text = text, dist = dist, target = target, prio = prio,
                                    msg = self.wire:unpack(text) }
    end
    self.addon = addon
    return addon
  end
  LibStub:NewLibrary("AceComm-3.0", 1)
  if opts.ui then
    run("Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua", G, "TavernGames")
    local Icon = LibStub:NewLibrary("LibDBIcon-1.0", 1)
    function Icon.Register(_, name, obj, db) self.icons[name] = { obj = obj, db = db, shown = not db.hide } end
    function Icon.Show(_, name) self.icons[name].shown = true end
    function Icon.Hide(_, name) self.icons[name].shown = false end
  end

  self.ns = Loader.ns()
  self.wire = self.ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
  self.baseline = {}
  for k in pairs(G) do self.baseline[k] = true end
  for _, path in ipairs(tocFiles("wow/")) do run(path, G, "TavernGames", self.ns) end
  if opts.ui then
    for _, path in ipairs(tocFiles("ui/")) do run(path, G, "TavernGames", self.ns) end
    -- From here on, reading a global the fake does not define is an error: it
    -- catches a WoW API the fake lacks and a misspelt or out-of-scope local.
    -- Globals that may be absent in the game too (saved variables, optional APIs).
    local optional = { TavernGamesDB = true, CUSTOM_CLASS_COLORS = true }
    setmetatable(G, { __index = function(_, k)
      if optional[k] then return nil end
      error("undefined global " .. tostring(k), 2)
    end })
  end
  return self
end

-- AceAddon's OnInitialize (ADDON_LOADED) and OnEnable (PLAYER_LOGIN).
function Wow:init() if self.addon.OnInitialize then self.addon:OnInitialize() end end
function Wow:enable() if self.addon.OnEnable then self.addon:OnEnable() end end
function Wow:boot() self:init(); self:enable() end

-- The first run is over (language chosen, intro seen): the main window opens
-- directly instead of the language dialog.
function Wow:firstRunDone() self.ns.db.lang, self.ns.db.introDone = "bg", true end

function Wow:fire(event, ...)
  for _, f in ipairs(self.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- true when a chat filter hides `text` for `event`.
function Wow:filtered(event, text)
  for _, fn in ipairs(self.filters[event] or {}) do
    if fn({}, event, text) then return true end
  end
  return false
end

-- A mouse click on a visible, enabled button.
function Wow:click(button, mouseButton)
  assert(button:IsVisible(), "click on a hidden frame")
  assert(button:IsEnabled(), "click on a disabled button")
  local fn = button.scripts.OnClick
  assert(fn, "the frame has no OnClick")
  fn(button, mouseButton or "LeftButton", false)
end

-- The pointer enters a visible frame (tooltips).
function Wow:hover(frame)
  assert(frame:IsVisible(), "hover over a hidden frame")
  local fn = frame.scripts.OnEnter
  if fn then fn(frame) end
end

-- A key press while `frame` has the keyboard.
function Wow:key(frame, key)
  local fn = frame.scripts.OnKeyDown
  assert(fn, "the frame has no OnKeyDown")
  fn(frame, key)
end

-- One rendered frame: OnUpdate of every visible frame.
function Wow:render(elapsed)
  for _, f in ipairs(self.frames) do
    if f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, elapsed or 0.02) end
  end
end

-- Visible font strings whose text contains the plain text `needle`.
function Wow:texts(needle) return Frames.visibleTexts(self.frames, needle) end

function Wow:advance(dt)
  local target = self.clock + dt
  while true do
    local best, bestIndex
    for i, t in ipairs(self.timers) do
      if not t.cancelled and t.due <= target and (not best or t.due < best.due or (t.due == best.due and t.seq < best.seq)) then
        best, bestIndex = t, i
      end
    end
    if not best then break end
    table.remove(self.timers, bestIndex)
    if best.due > self.clock then self.clock = best.due end
    best.fn(best)
  end
  self.clock = target
end

function Wow:deliverRaw(prefix, text, dist, sender)
  local c = self.comm
  c.obj[c.method](c.obj, prefix, text, dist, sender)
end

function Wow:deliver(dist, sender, msg) self:deliverRaw("TAVG", self.wire:pack(msg), dist, sender) end

function Wow:slash(text) self.G.SlashCmdList.TAVERNGAMES(text) end

-- Sent records whose message type is t.
function Wow:sentOf(t)
  local out = {}
  for _, s in ipairs(self.sent) do
    if s.msg and s.msg.t == t then out[#out + 1] = s end
  end
  return out
end

-- Chat lines (from index `from`) containing the plain text `needle`.
function Wow:chatWith(needle, from)
  local out = {}
  for i = from or 1, #self.chat do
    if self.chat[i]:find(needle, 1, true) then out[#out + 1] = self.chat[i] end
  end
  return out
end

-- Globals the wow/ files created, sorted.
function Wow:newGlobals()
  local out = {}
  for k in pairs(self.G) do
    if not self.baseline[k] then out[#out + 1] = k end
  end
  table.sort(out)
  return out
end

return Wow
