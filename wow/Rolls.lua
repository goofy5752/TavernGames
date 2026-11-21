local _, ns = ...

-- The WoW side of server rolls and of the group a table needs: the roll line in
-- chat (RANDOM_ROLL_RESULT), the env calls env.random, env.roll, env.group and
-- env.groupInvite, the automatic accept of my host's group invite, and the group
-- changes. Produces ns.RollChat. RandomRoll is called only through env.roll (a
-- click on „Хвърли“) and from /tavern probe roll (wow/Slash.lua); every call of
-- it, the player's typed /roll too, is caught by a hook (RollChat.made).
local Names, Adapter = ns.Names, ns.Adapter
local C = ns.Const

local RollChat = {}
ns.RollChat = RollChat

-- string.format argument of RANDOM_ROLL_RESULT -> what it is, and its specifier.
local ROLE = { "name", "n", "lo", "hi" }
local KIND = { "s", "d", "d", "d" }
local CAPTURE = { s = "(.+)", d = "(%d+)" }

-- A Lua pattern for the text string.format(fmt, name, n, lo, hi) gives ->
-- pattern, order (order[i] = "name" | "n" | "lo" | "hi" for the i-th capture),
-- or nil. `fmt` holds exactly four specifiers, all plain (%s %d, counted in
-- order of appearance) or all positional (%1$s %2$d ...), the name a string and
-- the three numbers numbers; any other % sequence makes it unusable.
function RollChat.pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local parts, order, used = {}, {}, {}
  local plain, positional = 0, 0
  local pos = 1
  while true do
    local at = fmt:find("%", pos, true)
    parts[#parts + 1] = Adapter.escape(fmt:sub(pos, (at or 0) - 1))
    if not at then break end
    local index, kind, after = fmt:match("^(%d+)%$([sd])()", at + 1)
    if index then
      index, positional = tonumber(index), positional + 1
    else
      kind, after = fmt:match("^([sd])()", at + 1)
      if not kind then return nil end
      plain = plain + 1
      index = plain
    end
    if not ROLE[index] or used[index] or KIND[index] ~= kind or (plain > 0 and positional > 0) then return nil end
    used[index] = true
    order[#order + 1] = ROLE[index]
    parts[#parts + 1] = CAPTURE[kind]
    pos = after
  end
  if #order ~= #ROLE then return nil end
  return "^" .. table.concat(parts) .. "$", order
end

-- The pattern of RANDOM_ROLL_RESULT, built once, on the first roll line looked at.
local rollPattern, rollOrder, built

-- A roll line -> name (normalized, a player link stripped), n, lo, hi | nil
-- (also for a secret value, and always while RANDOM_ROLL_RESULT is unusable).
function RollChat.parse(text)
  if issecretvalue and issecretvalue(text) then return nil end
  if not built then
    built = true
    rollPattern, rollOrder = RollChat.pattern(RANDOM_ROLL_RESULT)
  end
  if type(text) ~= "string" or not rollPattern then return nil end
  local captures = { text:match(rollPattern) }
  if #captures == 0 then return nil end
  local got = {}
  for i = 1, #rollOrder do got[rollOrder[i]] = captures[i] end
  local name, n, lo, hi = Adapter.nameIn(got.name), tonumber(got.n), tonumber(got.lo), tonumber(got.hi)
  if not (name and n and lo and hi) then return nil end
  return name, n, lo, hi
end

-- The roll and group calls of an env. A bot's env (`bot`) gets env.random only:
-- a bot never makes a server roll and never invites into my group.
function RollChat.env(env, bot)
  env.random = function(lo, hi) return math.random(lo, hi) end
  if bot then return end
  if type(RandomRoll) == "function" then
    env.roll = function(lo, hi) RandomRoll(lo, hi) end
  end
  -- Without all four group functions: no env.group, so core handles no group.
  if type(IsInGroup) == "function" and type(UnitIsGroupLeader) == "function"
      and type(IsInRaid) == "function" and type(GetNumGroupMembers) == "function" then
    env.group = function()
      return {
        grouped = IsInGroup() and true or false,
        leader = UnitIsGroupLeader("player") and true or false,
        raid = IsInRaid() and true or false,
        size = GetNumGroupMembers() or 0,
      }
    end
  end
  local invite = C_PartyInfo and C_PartyInfo.InviteUnit
  if type(invite) ~= "function" then invite = InviteUnit end
  if type(invite) == "function" then
    env.groupInvite = function(name) invite(name) end
  end
end

-- My RandomRoll calls of the last ROLL_ECHO_WAIT s: {lo, hi, at = GetTime()}.
-- The /roll slash command passes its numbers as text, and one number alone
-- is the top of 1..n.
local made = {}

local function range(lo, hi)
  lo, hi = tonumber(lo), tonumber(hi)
  if not hi then return 1, lo or 100 end
  return lo or 1, hi
end

-- A RandomRoll of lo..hi ran in the last ROLL_ECHO_WAIT s -> bool; the call
-- is used up (one call, one roll line).
function RollChat.made(lo, hi)
  local now, found = GetTime(), false
  for i = #made, 1, -1 do
    local r = made[i]
    if now - r.at > C.ROLL_ECHO_WAIT then
      table.remove(made, i)
    elseif not found and r.lo == lo and r.hi == hi then
      table.remove(made, i)
      found = true
    end
  end
  return found
end

if type(hooksecurefunc) == "function" and type(RandomRoll) == "function" then
  hooksecurefunc("RandomRoll", function(lo, hi)
    lo, hi = range(lo, hi)
    made[#made + 1] = { lo = lo, hi = hi, at = GetTime() }
  end)
end

-- The name a roll line shows, as `client` takes it: my own first name (what
-- UnitName gives) stands for env.me only when a RandomRoll of that range ran
-- in the last ROLL_ECHO_WAIT s (RollChat.made) and no other seat at my table
-- has a name it matches too. Otherwise it is passed as shown: a namesake's
-- roll reaches no seat rather than a wrong one, and is never taken for mine.
local function rollerName(client, shown, lo, hi)
  local me = client.env.me
  if shown ~= Names.normalize(UnitName("player")) then return shown end
  local s = client.session
  local seats = s and s.seats or {}
  for i = 1, #seats do
    if seats[i] and seats[i] ~= me and Names.matches(seats[i], shown) then return shown end
  end
  return RollChat.made(lo, hi) and me or shown
end

-- The last roll line seen, for /tavern probe roll: {raw, name, n, lo, hi, at};
-- `name` as it was passed to client:rollSeen (as shown when there is no client),
-- `at` = GetTime().
RollChat.last = nil

local EVENTS = {
  CHAT_MSG_SYSTEM = function(text)
    local shown, n, lo, hi = RollChat.parse(text)
    if not shown then return end
    local client = ns.client
    local name = client and rollerName(client, shown, lo, hi) or shown
    RollChat.last = { raw = text, name = name, n = n, lo = lo, hi = hi, at = GetTime() }
    if client then client:rollSeen(name, n, lo, hi) end
  end,
  PARTY_INVITE_REQUEST = function(inviter)
    local client = ns.client
    if not client or not client:groupInviteFrom(Names.normalize(inviter)) then return end
    if type(AcceptGroup) ~= "function" then return end
    AcceptGroup()
    -- The invite popup is shown after this event: hide it on the next frame.
    C_Timer.After(0, function()
      if type(StaticPopup_Hide) == "function" then StaticPopup_Hide("PARTY_INVITE") end
    end)
  end,
  GROUP_ROSTER_UPDATE = function()
    if ns.client then ns.client:groupChanged() end
  end,
}

local frame = CreateFrame("Frame")
for event in pairs(EVENTS) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...) EVENTS[event](...) end)
