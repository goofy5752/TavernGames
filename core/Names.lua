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
