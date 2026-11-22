local _, ns = ...

-- The trade side of payment: env.trade of core/Pay.lua (Trade.state, Trade.open)
-- and the report of every completed trade with a guild member to
-- client.pay:traded. Trade.open starts a trade from a click on „Трейд“; the
-- amount is set once, at the first TRADE_SHOW with that player within FILL_WAIT
-- s, never in a trade the addon did not open. The addon never presses Trade
-- (AcceptTrade). Every game function is looked up at call time, in both
-- spellings where the client may have either, and skipped when absent.
local Adapter = ns.Adapter
local fn, lookup, plain = Adapter.fn, Adapter.lookup, Adapter.plain

local Trade = {}
ns.Trade = Trade

local FILL_WAIT = 30    -- s: the trade I open is filled when its window shows within this long
local COMPLETE_WAIT = 2 -- s: once the window closed with both sides accepted, the completion line may still come
local RANGE = 2         -- CheckInteractDistance's index of the trade range

-- The unit of guild member `name`: target, party1..4, raid1..40, the first
-- whose GUID is the roster GUID of that name; nil when none is.
local function unitOf(name)
  local guid, unitGUID = Adapter.guids[name], fn("UnitGUID")
  if not (guid and unitGUID) then return nil end
  local function is(unit)
    local okGUID, g = pcall(unitGUID, unit)
    return okGUID and g == guid
  end
  if is("target") then return "target" end
  for i = 1, 4 do if is("party" .. i) then return "party" .. i end end
  for i = 1, 40 do if is("raid" .. i) then return "raid" .. i end end
  return nil
end

-- "ok" | "far" | "none" (no unit of that player) | "off" (no InitiateTrade).
-- Without a range answer (no CheckInteractDistance, or it raises in combat) the
-- state is "ok": the game itself refuses a far trade.
function Trade.state(name)
  if not fn("InitiateTrade") then return "off" end
  local unit = unitOf(name)
  if not unit then return "none" end
  local near = fn("CheckInteractDistance")
  if not near then return "ok" end
  local okNear, inRange = pcall(near, unit, RANGE)
  if okNear and not inRange then return "far" end
  return "ok"
end

local wanted -- {name, c, at}: the amount to set in my trade with `name`, asked at GetTime() `at`

-- Starts a trade with `name` (from a click) for `c` copper -> true | nil.
function Trade.open(name, c)
  local initiate, unit = fn("InitiateTrade"), unitOf(name)
  if not (initiate and unit) or not pcall(initiate, unit) then return nil end
  wanted = { name = name, c = c, at = GetTime() }
  return true
end

-- Sets my side of the open trade to `c`. Called from TRADE_SHOW, the set-money
-- call may be blocked: then nothing is filled and the player types the amount
-- the payment dialog shows.
local function fill(c)
  local set = fn("C_TradeInfo.SetTradeMoney", "SetTradeMoney")
  if not (set and pcall(set, c)) then return end
  local show, box = fn("MoneyInputFrame_SetCopper"), lookup("TradePlayerInputMoneyFrame")
  if show and box then pcall(show, box, c) end
end

-- My side's and the partner's copper in the open trade, or nil.
local function amounts()
  local player, target = fn("GetPlayerTradeMoney"), fn("GetTargetTradeMoney")
  local okGave, gave, okGot, got
  if player and target then
    okGave, gave = pcall(player)
    okGot, got = pcall(target)
  else
    local both = fn("C_TradeInfo.GetTradeMoney")
    if not both then return nil end
    okGave, gave, got = pcall(both)
    okGot = okGave
  end
  if not (okGave and okGot and plain(gave) and plain(got)) then return nil end
  return gave, got
end

-- The trade in progress: {name (the partner's full name by GUID, nil for a
-- stranger), gave, got, items, both (both sides accepted), closedAt}.
local current

local function read()
  if current and not current.closedAt then current.gave, current.got = amounts() end
end

-- The partner of the open trade: its GUID through the roster scan, never the shown name.
local function partner()
  local unitGUID = fn("UnitGUID")
  if not unitGUID then return nil end
  local okGUID, guid = pcall(unitGUID, "NPC")
  return okGUID and Adapter.nameOfGUID(guid) or nil
end

-- The completion line: the trade is reported once, with the amounts read last
-- (the window may have closed and its money read 0 by now).
local function completed()
  local t = current
  current = nil
  if not (t and t.both and t.name and t.gave) then return end
  if t.closedAt and GetTime() - t.closedAt > COMPLETE_WAIT then return end
  local client = ns.client
  if not (client and client.pay) or t.name == client.env.me then return end
  client.pay:traded({ name = t.name, gave = t.gave, got = t.got, items = t.items })
end

local function accepted(v) return v == 1 or v == true end

-- True when one of the event's arguments is the line `global` names.
local function says(global, ...)
  local line = lookup(global)
  if line == nil then return false end
  for i = 1, select("#", ...) do
    if select(i, ...) == line then return true end
  end
  return false
end

local function item()
  if current and not current.closedAt then current.items = true end
end

local EVENTS = {
  TRADE_SHOW = function()
    local name = partner()
    current = { name = name, items = false, both = false }
    read()
    local w = wanted
    if w and GetTime() - w.at > FILL_WAIT then wanted, w = nil, nil end
    if w and name == w.name then
      wanted = nil
      fill(w.c)
    end
  end,
  -- After both accepted the amounts stay as read: a change resets the accepts first.
  TRADE_MONEY_CHANGED = function() if current and not current.both then read() end end,
  TRADE_ACCEPT_UPDATE = function(player, target)
    if not current or current.closedAt then return end
    read()
    current.both = accepted(player) and accepted(target)
  end,
  TRADE_PLAYER_ITEM_CHANGED = item,
  TRADE_TARGET_ITEM_CHANGED = item,
  TRADE_REQUEST_CANCEL = function() current = nil end,
  -- Closed before both accepted: cancelled. After: the completion line decides.
  TRADE_CLOSED = function()
    if current and current.both then current.closedAt = current.closedAt or GetTime() else current = nil end
  end,
  UI_INFO_MESSAGE = function(...) if says("ERR_TRADE_COMPLETE", ...) then completed() end end,
  -- A cancel, or any error once both accepted (bags full, too far): no trade.
  UI_ERROR_MESSAGE = function(...)
    if current and (current.both or says("ERR_TRADE_CANCELLED", ...)) then current = nil end
  end,
}

local frame = CreateFrame("Frame")
-- A client that does not know an event refuses to register it: left out.
for event in pairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) EVENTS[event](...) end)
