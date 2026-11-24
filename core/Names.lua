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
-- values are skipped) reads the same, the initial of its next word ("Ivan P.").
-- "?" for no name.
function Names.short(name, others)
  local short, full = bare(name)
  if not short then return "?" end
  for _, o in pairs(others or {}) do
    local os, ofull = bare(o)
    if os == short and ofull ~= full then
      local initial = full:match("^%S+%s+([%z\1-\127\194-\244][\128-\191]*)")
      if initial and not Names.isBot(full) then return short .. " " .. initial .. "." end
      return short
    end
  end
  return short
end

-- `shown` (a name as seen in chat) stands for the full name `full`: the same
-- bytes, or a single word equal to its first word.
function Names.matches(full, shown)
  if type(full) ~= "string" or type(shown) ~= "string" then return false end
  return shown == full or (not shown:find("%s") and shown == Names.first(full))
end
