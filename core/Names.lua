local _, ns = ...

local Names = {}
ns.Names = Names

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Trims and strips one trailing "-Realm" (a realm has no space and no hyphen).
-- Returns nil for a non-string or an empty result. Never changes letter case.
function Names.normalize(raw)
  if type(raw) ~= "string" then return nil end
  local s = trim(raw)
  local base = s:match("^(.+)%-[^%s%-]+$")
  if base then s = trim(base) end
  if s == "" then return nil end
  return s
end

-- The first word of a name ("Иван Петров" -> "Иван"): the form the server shows
-- in a roll line. The one copy of that rule.
function Names.first(name)
  return (name:match("^%S*"))
end

-- Is `name` one of the addon's bots ("Bot Petrova", core/Bots.lua)? The
-- screen marks a bot by this rule, the one Names.short drops "Bot " by.
function Names.isBot(name)
  local full = Names.normalize(name)
  return full ~= nil and full:match("^Bot%s+%S") ~= nil
end

-- The bare name a list shows: no realm; a bot ("Bot Petrova") its own name
-- ("Petrova"), a person the first word. -> short, the full name (nil: none).
local function bare(name)
  local full = Names.normalize(name)
  if not full then return nil end
  return full:match("^Bot%s+(.+)$") or Names.first(full), full
end

-- The short name of a seat for a list that names several (seats, plates, lists, the hand history):
-- bare(name), and when another name of `others` (any table of names; other
-- values are skipped) reads the same, the initial of its next word ("Ivan P."); when one
-- of those has that initial too, the whole next word ("Ivan Petrov" by "Ivan Pavlov"); when
-- that is the same too, the whole name. A bot keeps its own name. "?" for no name.
local function second(full) return full:match("^%S+%s+(%S+)") end
local function initialOf(full) return full:match("^%S+%s+([%z\1-\127\194-\244][\128-\191]*)") end

local SHORTS = {} -- the metatable of a Names.shorts map

function Names.short(name, others)
  local short, full = bare(name)
  if not short then return "?" end
  if getmetatable(others) == SHORTS then -- worked out once (Names.shorts): only those who read alike
    return others.map[full] or Names.short(name, others.groups[short])
  end
  local initial = initialOf(full)
  local level = 0 -- 0 the bare name, 1 the initial, 2 the next word, 3 the whole name
  for _, o in pairs(others or {}) do
    local os, ofull = bare(o)
    if os == short and ofull ~= full then
      if not initial or Names.isBot(full) then return short end
      local need = 1
      if initialOf(ofull) == initial then need = second(ofull) == second(full) and 3 or 2 end
      if need > level then level = need end
    end
  end
  if level == 1 then return short .. " " .. initial .. "." end
  if level == 2 then return short .. " " .. second(full) end
  if level == 3 then return full end
  return short
end

-- The short names of the list `names` (as `others`) worked out once: a map that Names.short
-- (so W.short, W.shortColored) takes in place of the list, with the same answers, each name
-- weighed only against those that read like it. A screen that names everyone of a long list
-- (the hall) builds it once per redraw, not Names.short against the whole list per name.
function Names.shorts(names)
  local groups, map = {}, {}
  for _, n in pairs(names or {}) do
    local short = bare(n)
    if short then
      local g = groups[short] or {}
      groups[short] = g
      g[#g + 1] = n
    end
  end
  for _, g in pairs(groups) do
    for _, n in ipairs(g) do
      local _, full = bare(n)
      map[full] = Names.short(n, g)
    end
  end
  return setmetatable({ map = map, groups = groups }, SHORTS)
end

-- `shown` (a name as seen in chat) stands for the full name `full`: the same
-- bytes, or a single word equal to its first word.
function Names.matches(full, shown)
  if type(full) ~= "string" or type(shown) ~= "string" then return false end
  return shown == full or (not shown:find("%s") and shown == Names.first(full))
end
