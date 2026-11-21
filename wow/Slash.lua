local _, ns = ...

-- /tavern and its subcommands; /tavern probe checks the early risks of spec
-- section 10 and prints only to the local chat frame.
local C, L, Adapter = ns.Const, ns.L, ns.Adapter

local Slash = {}
ns.Slash = Slash

local say = Adapter.say

local PROBE_BYTES = 600 -- packed size of the self-whisper (above 255: AceComm splits it)
local PROBE_WAIT = 5
local ROLL_PROBE_WAIT = 3 -- seconds /tavern probe roll waits for its roll line
-- Reported by presence only; the probe never calls them (probe roll calls RandomRoll).
local PROBE_APIS = {
  "InitiateTrade", "C_TradeInfo.SetTradeMoney", "SetSendMailMoney", "SendMail", "issecretvalue", "IsGUIDInGroup",
  "RandomRoll", "C_PartyInfo.InviteUnit", "InviteUnit", "AcceptGroup", "UnitIsGroupLeader", "StaticPopup_Hide",
  "IsInGroup", "IsInRaid", "GetNumGroupMembers",
}
-- /tavern bots host|invite <game>: short names for engine ids.
local GAME_ALIAS = { dr = "deathroll" }
local ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function lookup(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end

-- Random letters, so deflate cannot shrink the probe below PROBE_BYTES.
local function noise(n)
  local out = {}
  for i = 1, n do
    local k = math.random(1, #ALPHABET)
    out[i] = ALPHABET:sub(k, k)
  end
  return table.concat(out)
end

local pending -- the probe whose echo is awaited

Adapter.handlers.PRB = function(distribution, rawSender, msg)
  local p = pending
  if p and distribution == "WHISPER" and msg.id == p.id and msg.pad == p.pad then p.sender = rawSender end
end

function Slash.probe()
  local client = ns.client
  local me = client and client.env.me
  say(L("probe.name", me or L("probe.unresolved"), tostring(UnitName("player"))))
  say(L("probe.sender", tostring(Adapter.lastRawSender or "-")))
  local inInstance, kind = IsInInstance()
  say(L("probe.instance", tostring(inInstance), tostring(kind)))
  for _, path in ipairs(PROBE_APIS) do say(L("probe.api", path, type(lookup(path)))) end
  local samples = {}
  for i = 1, 5 do samples[i] = tostring(math.random(1, 1000000)) end
  say(L("probe.random", table.concat(samples, " ")))
  say(L("probe.randomseed", type(math.randomseed)))
  -- "OK"/"-" are diagnostic tokens: was a roll line pattern built from the format?
  say(L("probe.rollfmt", tostring(RANDOM_ROLL_RESULT), ns.RollChat.pattern(RANDOM_ROLL_RESULT) and "OK" or "-"))

  local p ={ id = tostring(GetTime()) .. "-" .. math.random(1, 1000000), instance = inInstance and true or false }
  local msg, bytes = { v = C.PROTOCOL, t = "PRB", id = p.id }, 0
  local n = PROBE_BYTES
  repeat
    p.pad = noise(n)
    msg.pad = p.pad
    bytes = #Adapter.wire:pack(msg)
    n = n + 100
  until bytes >= PROBE_BYTES
  p.bytes = bytes
  pending = p
  Adapter.send("WHISPER", me or ns.Names.normalize(UnitName("player")), msg)
  say(L("probe.echo.sent", bytes, PROBE_WAIT))
  C_Timer.NewTimer(PROBE_WAIT, function()
    if pending ~= p then return end
    pending = nil
    if p.sender then
      say(L("probe.echo.ok", p.bytes, tostring(p.instance), p.sender))
    else
      say(L("probe.echo.lost", p.bytes, tostring(p.instance)))
    end
  end)
end

-- /tavern probe roll: one server roll 1-100 (the only RandomRoll call besides
-- „Хвърли“), then what the chat showed of it within ROLL_PROBE_WAIT s.
function Slash.probeRoll()
  if type(RandomRoll) ~= "function" then return say(L("probe.api", "RandomRoll", type(RandomRoll))) end
  local started = GetTime()
  RandomRoll(1, 100)
  C_Timer.NewTimer(ROLL_PROBE_WAIT, function()
    local last = ns.RollChat.last
    if not last or last.at < started then return say(L("probe.roll.lost")) end
    local me = ns.client and last.name == ns.client.env.me
    -- "yes"/"no" are diagnostic tokens: did the roll line's name resolve to me?
    say(L("probe.roll.ok", last.raw, last.name, me and "yes" or "no"))
  end)
end

local function probe(arg)
  if arg == "roll" then return Slash.probeRoll() end
  if arg ~= "" then return say(L("slash.help")) end
  Slash.probe()
end

-- Bot mode on (it may still wait for my name) -> true | nil.
local function botsOn()
  if ns.bots then return true end
  local state = Adapter.toggleBots()
  if state == "wait" then
    say(L("bots.wait"))
    return nil
  end
  say(L("bots.on"))
  return true
end

local function bots(arg)
  local verb, game = arg:match("^(%S*)%s*(.-)$")
  if verb == "fill" then
    if not botsOn() then return end
    if not ns.bots:fill(tonumber(game)) then say(L("bots.nofill")) end
    return
  end
  if verb == "host" or verb == "invite" then
    if game == "" then game = "ttt" end
    game = GAME_ALIAS[game] or game
    if not ns.Games.engine(game) then return say(L("bots.nogame")) end
    if not botsOn() then return end
    local action
    if verb == "host" then action = ns.bots:hostTable(game) else action = ns.bots:inviteMe(game) end
    if not action then say(L("bots.none")) end
    return
  end
  if arg ~= "" then return say(L("slash.help")) end
  local state = Adapter.toggleBots()
  say(L("bots." .. state))
end

local COMMANDS = {
  [""] = function()
    if ns.MainWindow then return ns.MainWindow.toggle() end
    say(L("slash.help"))
  end,
  bots = bots,
  debug = function()
    Adapter.setDebug(not ns.db.debug)
    say(L(ns.db.debug and "debug.on" or "debug.off"))
  end,
  intro = function()
    if ns.Intro then return ns.Intro.start(true) end
    say(L("slash.help"))
  end,
  reset = function()
    ns.db.lang, ns.db.introDone = nil, nil
    say(L("reset.done"))
  end,
  probe = probe,
}

function Slash.run(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  local fn = COMMANDS[cmd:lower()]
  if not fn then return say(L("slash.help")) end
  fn(rest:lower())
end

SLASH_TAVERNGAMES1 = "/tavern"
SlashCmdList.TAVERNGAMES = Slash.run
