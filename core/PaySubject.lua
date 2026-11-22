local _, ns = ...

-- The date and the subject of my payment letter (core/Pay.lua): Pay.utc, Pay.subject.
local View = ns.LedgerView
local floor = math.floor
local Pay = ns.Pay

local SUBJECT_MAX = 64 -- bytes of a letter's subject

-- {d, m, day} of epoch t in UTC (the fallback of env.date; core never calls os.date).
function Pay.utc(t)
  local day = floor(t / 86400)
  local z = day + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  return { d = doy - floor((153 * mp + 2) / 5) + 1, m = mp < 10 and mp + 3 or mp - 9, day = day }
end

local function label(g)
  local key = "game." .. tostring(g)
  local s = ns.L(key)
  return s ~= key and s or ns.L("game.unknown")
end

-- The first n bytes of s, or fewer: never inside a character.
local function cut(s, n)
  if #s <= n then return s end
  while n > 0 and s:byte(n + 1) >= 0x80 and s:byte(n + 1) < 0xC0 do n = n - 1 end
  return s:sub(1, n)
end

-- The subject of my letter to `name`: Pay.TAG and the games and days of my open
-- debts to it, newest first ("<game> <dd.mm>" by date(at), default Pay.utc,
-- joined by " + "), at most SUBJECT_MAX bytes.
function Pay.subject(view, me, name, date)
  date = date or Pay.utc
  local parts, rows = {}, View.rows(view)
  for j = #rows, 1, -1 do -- the rows go oldest first
    local d = rows[j].debt
    if d.f == me and d.t == name and d.status == "confirmed" and rows[j].open > 0 then
      local t = date(d.at)
      parts[#parts + 1] = string.format("%s %02d.%02d", label(d.g), t.d, t.m)
    end
  end
  return cut(#parts > 0 and Pay.TAG .. " " .. table.concat(parts, " + ") or Pay.TAG, SUBJECT_MAX)
end
