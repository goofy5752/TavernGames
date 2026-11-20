local _, ns = ...

local Util = {}
ns.Util = Util

-- Deep copy; non-table values are returned as they are.
function Util.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Util.copy(v) end
  return out
end

-- Deep equality of plain data.
function Util.same(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not Util.same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

-- Plain byte order of two strings (string `<` goes through strcoll).
function Util.byteLess(a, b)
  local n = math.min(#a, #b)
  for i = 1, n do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then return x < y end
  end
  return #a < #b
end

-- Index of `name` in a seat list (names or false), or nil.
function Util.seatOf(seats, name)
  for i = 1, #seats do
    if seats[i] == name then return i end
  end
  return nil
end

-- Is `value` one of the elements of the array `list`?
function Util.contains(list, value)
  for i = 1, #list do
    if list[i] == value then return true end
  end
  return false
end

-- 123456 -> "12g 34s 56c"; zero parts are omitted; 0 -> "0c".
function Util.money(copper)
  copper = math.floor(copper or 0)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  if #parts == 0 then return "0c" end
  return table.concat(parts, " ")
end
