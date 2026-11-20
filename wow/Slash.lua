local _, ns = ...

-- /tavern and its subcommands; /tavern probe checks the early risks of spec
-- section 10 and prints only to the local chat frame.
local C, L, Adapter = ns.Const, ns.L, ns.Adapter

local Slash = {}
ns.Slash = Slash

local say = Adapter.say

local PROBE_BYTES = 600 -- packed size of the self-whisper (above 255: AceComm splits it)
local PROBE_WAIT = 5
-- Reported by presence only; the probe never calls them.
local PROBE_APIS = {
  "InitiateTrade", "C_TradeInfo.SetTradeMoney", "SetSendMailMoney", "SendMail", "issecretvalue", "IsGUIDInGroup",
}
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

  local p = { id = tostring(GetTime()) .. "-" .. math.random(1, 1000000), instance = inInstance and true or false }
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

local function bots(arg)
  local action
  if arg == "host" or arg == "invite" then
    if not ns.bots then
      local state = Adapter.toggleBots()
      if state == "wait" then return say(L("bots.wait")) end
      say(L("bots.on"))
    end
    if arg == "host" then action = ns.bots:hostTable() else action = ns.bots:inviteMe() end
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
  probe = Slash.probe,
}

function Slash.run(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  local fn = COMMANDS[cmd:lower()]
  if not fn then return say(L("slash.help")) end
  fn(rest:lower())
end

SLASH_TAVERNGAMES1 = "/tavern"
SlashCmdList.TAVERNGAMES = Slash.run
