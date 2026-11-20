local _, ns = ...

-- String tables per language (filled by locale/bg.lua and locale/en.lua) and
-- ns.L(key, ...), the only way user-visible text is looked up.
local Locale = { tables = { bg = {}, en = {} }, current = "bg" }
ns.Locale = Locale

-- "bg" or "en"; anything else is ignored.
function Locale.set(lang)
  if Locale.tables[lang] then Locale.current = lang end
end

function Locale.lang() return Locale.current end

-- The text for `key` in the current language, through string.format when extra
-- arguments are given; a missing key comes back as the key itself.
function ns.L(key, ...)
  local s = Locale.tables[Locale.current][key]
  if s == nil then return key end
  if select("#", ...) > 0 then return string.format(s, ...) end
  return s
end
