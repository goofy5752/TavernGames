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

-- `shown` (a name as seen in chat) stands for the full name `full`: the same
-- bytes, or a single word equal to its first word.
function Names.matches(full, shown)
  if type(full) ~= "string" or type(shown) ~= "string" then return false end
  return shown == full or (not shown:find("%s") and shown == Names.first(full))
end
