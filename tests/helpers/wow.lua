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

-- The Global "never" set: the addon must never call these (it never moves gold).
local FORBIDDEN = { "AcceptTrade", "SendMail", "TakeInboxMoney", "AutoLootMailItem", "SetSendMailCOD" }

-- A logged payment API: every call goes to self.calls as {name = ..., args = {...}};
-- a name in self.forbidden fails the test. `fn(...)` gives the result, if any.
-- A call the player makes (Wow:playerCalls) is logged with player = true and
-- may be a forbidden one: the player presses the game's own buttons.
local function api(self, name, fn)
  return function(...)
    local player = self.byPlayer or nil
    self.calls[#self.calls + 1] = { name = name, args = { ... }, player = player }
    if self.forbidden[name] and not player then error("called " .. name, 2) end
    if fn then return fn(...) end
  end
end

-- An edit box of the send-mail frame, and a check button.
function Wow.editBox()
  return { text = "", SetText = function(b, t) b.text = t end, GetText = function(b) return b.text end }
end

local function checkButton(on)
  return { on = on, SetChecked = function(b, v) b.on = v and true or false end, GetChecked = function(b) return b.on end }
end

-- The game's „Send“ of the send-mail frame (SendMailMailButton). Its own
-- OnClick sets the letter's money, or its COD when COD is checked, from the
-- money box and calls SendMail with the boxes; a script added by
-- HookScript("OnClick") runs after all of it, or, with self.clickOrder ==
-- "hooks first" (a client that asks to confirm the money before it sends),
-- before the SendMail. `hooks` is the list of those scripts, in order. Click()
-- is the player's click: the game's own calls are the player's, a hooked
-- script's are the addon's.
function Wow:sendButton()
  local b = { hooks = {} }
  function b.HookScript(_, script, fn)
    if script == "OnClick" then b.hooks[#b.hooks + 1] = fn end
  end
  function b.Click()
    local G, player = self.G, self.byPlayer
    local function hooked()
      self.byPlayer = false
      for _, fn in ipairs(b.hooks) do fn(b, "LeftButton", false) end
      self.byPlayer = true
    end
    self.byPlayer = true
    -- Hooks first: the scripts run before the game sets the letter's money from the box.
    if self.clickOrder == "hooks first" then hooked() end
    local c, check = G.SendMailMoney.copper, G.SendMailSendMoneyButton
    if not check or check:GetChecked() then G.SetSendMailMoney(c) else G.SetSendMailCOD(c) end
    local body = G.SendMailBodyEditBox or G.MailEditBox
    G.SendMail(G.SendMailNameEditBox:GetText(), G.SendMailSubjectEditBox:GetText(), body and body:GetText() or "")
    if self.clickOrder ~= "hooks first" then hooked() end
    self.byPlayer = player
  end
  return b
end

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
-- opts.noHooks: a client without hooksecurefunc.
-- opts.late: names of game functions the client defines only later (nil while the
-- addon loads; the test puts self.late[name] back into self.G when it wants them).
-- opts.ui: also run the ui/ files.
function Wow.new(opts)
  opts = opts or {}
  local self = setmetatable({
    clock = 0, timers = {}, seq = 0, frames = {}, sent = {}, chat = {}, filters = {},
    roster = {}, rosterRequests = 0, inGuild = false, combat = false, instance = false,
    dnd = false, group = {}, money = 0, icons = {}, sounds = {}, reloads = 0,
    rolls = {}, groupInvites = {}, accepted = 0, popupsHidden = {},
    -- My group roster by name: unit names UnitInParty / UnitInRaid know, and GetRaidRosterInfo's rows.
    partyNames = {}, raidNames = {}, groupRoster = {},
    party = { grouped = false, leader = false, raid = false, size = 0 },
    -- Trade and mail: the open trade's money, the "NPC" unit (the trade partner),
    -- the inbox rows {sender, subject, money}, whether the mailbox is open.
    tradeMoney = { player = 0, target = 0 }, npc = {}, inbox = {}, mailOpen = false, mailPrice = 30,
    calls = {}, forbidden = {},
    -- Units: unit id ("target", "party1", "raid7") -> GUID; near[unit]: CheckInteractDistance says in range.
    units = {}, near = {},
  }, Wow)
  for _, name in ipairs(FORBIDDEN) do self.forbidden[name] = true end
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
  G.UnitName = function(unit)
    if unit == "player" then return Wow.FIRST end
    if unit == "NPC" then return self.npc.name, self.npc.realm end
  end
  G.UnitGUID = function(unit)
    if unit == "player" then return Wow.GUID end
    if unit == "NPC" then return self.npc.guid end
    return self.units[unit]
  end
  G.CheckInteractDistance = function(unit) return self.near[unit] == true end
  -- date("*t", t), in UTC so that a test never depends on the machine's zone.
  G.date = function(fmt, t)
    assert(fmt == "*t", "the fake date knows *t only")
    return os.date("!*t", t)
  end
  G.UnitClass = function() return "Маг", "MAGE", 8 end
  G.UnitRace = function() return "Човек", "Human", 1 end
  G.UnitFactionGroup = function() return "Alliance", "Alliance" end
  G.GetRealmName = function() return "Forever" end
  G.GetLocale = function() return "enUS" end
  G.GetCurrentRegion = function() return 3 end
  G.GetCurrentRegionName = function() return "EU" end
  G.IsInGuild = function() return self.inGuild end
  -- The guild's name while w.inGuild, unless w.guildName == false (the client has no guild data yet).
  G.GetGuildInfo = function(unit)
    if unit == "player" and self.inGuild and self.guildName ~= false then return self.guildName or "Механата", "Член", 1 end
  end
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
  G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
  G.RandomRoll = function(lo, hi) self.rolls[#self.rolls + 1] = { lo, hi } end
  G.C_PartyInfo = { InviteUnit = function(name) self.groupInvites[#self.groupInvites + 1] = name end }
  G.AcceptGroup = function() self.accepted = self.accepted + 1 end
  G.StaticPopup_Hide = function(which) self.popupsHidden[#self.popupsHidden + 1] = which end
  -- My own group, from w.party = {grouped, leader, raid, size}.
  G.IsInGroup = function() return self.party.grouped end
  G.IsInRaid = function() return self.party.raid end
  G.UnitIsGroupLeader = function(unit) return unit == "player" and self.party.leader end
  G.GetNumGroupMembers = function() return self.party.size end
  G.UnitInParty = function(name) return self.partyNames[name] == true end
  G.UnitInRaid = function(name) if self.raidNames[name] then return 1 end end
  G.GetRaidRosterInfo = function(i) return self.groupRoster[i] end
  G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
  G.SOUNDKIT = { TELL_MESSAGE = 3081 }
  G.PlaySound = function(id, channel) self.sounds[#self.sounds + 1] = { id, channel } end
  G.SlashCmdList = {}
  G.ReloadUI = function() self.reloads = self.reloads + 1 end
  G.InitiateTrade = api(self, "InitiateTrade")
  G.AcceptTrade = api(self, "AcceptTrade")
  G.SetTradeMoney = api(self, "SetTradeMoney")
  G.C_TradeInfo = { SetTradeMoney = api(self, "C_TradeInfo.SetTradeMoney") }
  G.GetPlayerTradeMoney = function() return self.tradeMoney.player end
  G.GetTargetTradeMoney = function() return self.tradeMoney.target end
  G.ERR_TRADE_COMPLETE = "Trade complete."
  G.ERR_TRADE_CANCELLED = "Trade cancelled."
  G.ERR_TRADE_BAG_FULL = "Trade failed, you don't have enough bag space."
  -- The money box of the trade frame and of the send-mail frame: {copper}.
  G.TradePlayerInputMoneyFrame, G.SendMailMoney = { copper = 0 }, { copper = 0 }
  G.MoneyInputFrame_SetCopper = api(self, "MoneyInputFrame_SetCopper", function(frame, c) frame.copper = c end)
  G.MoneyInputFrame_GetCopper = function(frame) return frame.copper end
  -- The money of the letter being written (the game's „Send“ sets it from the money box); a COD letter sends none.
  G.SetSendMailMoney = api(self, "SetSendMailMoney", function(c) self.sendMoney = c end)
  G.GetSendMailMoney = function() return self.sendMoney or 0 end
  G.SetSendMailCOD = api(self, "SetSendMailCOD", function() self.sendMoney = 0 end)
  G.SendMail = api(self, "SendMail")
  G.GetSendMailPrice = function() return self.mailPrice end
  G.MailFrame = { IsShown = function() return self.mailOpen end }
  G.MailFrameTab_OnClick = api(self, "MailFrameTab_OnClick")
  -- The classic send-mail frame: SendMailBodyEditBox (a test may swap it for MailEditBox).
  G.SendMailNameEditBox, G.SendMailSubjectEditBox, G.SendMailBodyEditBox = Wow.editBox(), Wow.editBox(), Wow.editBox()
  G.SendMailSendMoneyButton, G.SendMailCODButton = checkButton(true), checkButton(false)
  G.SendMailMailButton = self:sendButton()
  G.GetInboxNumItems = function() return #self.inbox, #self.inbox end
  -- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned
  G.GetInboxHeaderInfo = function(i)
    local m = self.inbox[i]
    if m then return nil, nil, m.sender, m.subject, m.money, m.cod or 0, 30, nil, false, m.returned or false end
  end
  G.TakeInboxMoney = api(self, "TakeInboxMoney")
  G.AutoLootMailItem = api(self, "AutoLootMailItem")
  -- hooksecurefunc([tbl,] name, fn): fn runs after the original, with its arguments.
  G.hooksecurefunc = function(a, b, c)
    local tbl, name, fn = a, b, c
    if type(a) == "string" then tbl, name, fn = G, a, b end
    local orig = tbl[name]
    tbl[name] = function(...)
      local r = { orig(...) }
      -- The hook is addon code: a call it makes is the addon's, even inside the player's click.
      local player = self.byPlayer
      self.byPlayer = false
      fn(...)
      self.byPlayer = player
      return unpack(r)
    end
  end
  if opts.noHooks then G.hooksecurefunc = nil end
  self.late = {}
  for _, name in ipairs(opts.late or {}) do self.late[name], G[name] = G[name], nil end
  if opts.saved then G.TavernGamesDB = opts.saved end

  for _, path in ipairs(LIBS) do run(path, G, "TavernGames") end
  local LibStub = G.LibStub
  local AceAddon = LibStub:NewLibrary("AceAddon-3.0", 1)
  function AceAddon.NewAddon(_, name)
    local addon = { name = name }
    function addon.RegisterComm(obj, prefix, method)
      self.comm = { obj = obj, prefix = prefix, method = method or "OnCommReceived" }
    end
    -- callback: AceComm's, called per part sent (arg, bytes sent so far, bytes in all); a test calls it.
    function addon.SendCommMessage(_, prefix, text, dist, target, prio, callback, arg)
      assert(type(prefix) == "string" and type(text) == "string" and type(dist) == "string")
      assert(prio == "BULK" or prio == "NORMAL" or prio == "ALERT", "bad prio " .. tostring(prio))
      self.sent[#self.sent + 1] = { prefix = prefix, text = text, dist = dist, target = target, prio = prio,
                                    msg = self.wire:unpack(text), callback = callback, arg = arg }
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
    local optional = {
      TavernGamesDB = true, CUSTOM_CLASS_COLORS = true, SOUNDKIT = true, issecretvalue = true, InviteUnit = true,
      debugprofilestop = true, GetFramerate = true,
    }
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

-- `name` joins the guild: listed in the roster, and the roster scan has run.
function Wow:member(name)
  for _, m in ipairs(self.roster) do
    if m.name == name then return end
  end
  self.roster[#self.roster + 1] = { name = name, online = true, guid = "Player-1-" .. name }
  self:fire("GUILD_ROSTER_UPDATE")
end

function Wow:slash(text) self.G.SlashCmdList.TAVERNGAMES(text) end

-- How many times the addon called the logged payment API `name` (the player's own calls do not count).
function Wow:called(name)
  local n = 0
  for _, c in ipairs(self.calls) do
    if c.name == name and not c.player then n = n + 1 end
  end
  return n
end

-- The arguments of the addon's last call of the logged API `name`, or nil.
function Wow:argsOf(name)
  for i = #self.calls, 1, -1 do
    local c = self.calls[i]
    if c.name == name and not c.player then return c.args end
  end
end

-- The player calls the game function `name` (a click on the game's own button):
-- the hooks of hooksecurefunc run, and a forbidden function is allowed.
function Wow:playerCalls(name, ...)
  self.byPlayer = true
  local okCall, err = pcall(self.G[name], ...)
  self.byPlayer = false
  if not okCall then error(err, 0) end
end

-- A trade event. TRADE_CLOSED and TRADE_REQUEST_CANCEL end the trade, as in the
-- game: afterwards there is no partner and both money values read 0.
function Wow:fireTrade(event, ...)
  self:fire(event, ...)
  if event == "TRADE_CLOSED" or event == "TRADE_REQUEST_CANCEL" then
    self.npc, self.tradeMoney = {}, { player = 0, target = 0 }
  end
end

-- A mail event; MAIL_SHOW and MAIL_CLOSED open and close the mailbox (MailFrame).
function Wow:fireMail(event, ...)
  if event == "MAIL_SHOW" then self.mailOpen = true end
  if event == "MAIL_CLOSED" then self.mailOpen = false end
  self:fire(event, ...)
end

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
