local _, ns = ...

-- Floor-plan geometry of the hall: floor or list mode, the spot of each table,
-- the chairs around a table, and the order the tables are shown in.
local HallLayout = {}
ns.HallLayout = HallLayout

local C = ns.Const
local byteLess = ns.Util.byteLess

-- "floor" up to LIST_MODE_ABOVE tables, "list" above that.
function HallLayout.mode(n)
  return n > C.LIST_MODE_ABOVE and "list" or "floor"
end

local function columns(n)
  if n <= 3 then return n end
  if n == 4 then return 2 end
  if n <= 6 then return 3 end
  return 4
end

-- Cell centres of a grid over a w x h floor, row by row (x from the left, y from the top).
function HallLayout.slots(n, w, h)
  local out = {}
  if n <= 0 then return out end
  local cols = columns(n)
  local rows = math.ceil(n / cols)
  local cw, ch = w / cols, h / rows
  for i = 1, n do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    out[i] = { (col + 0.5) * cw, (row + 0.5) * ch }
  end
  return out
end

-- Chair offsets from the table centre on a circle of radius r (y up): seat 1 at
-- the top, the others clockwise.
function HallLayout.chairs(seats, r)
  local out = {}
  for i = 1, seats do
    local a = math.rad(90 - (i - 1) * 360 / seats)
    out[i] = { r * math.cos(a), r * math.sin(a) }
  end
  return out
end

local function mine(rec, me)
  if rec.host == me then return true end
  for i = 1, #(rec.seats or {}) do
    if rec.seats[i] == me then return true end
  end
  return false
end

-- A new list: the table I am at first, then "open" before "live", then tid bytes.
function HallLayout.order(records, me)
  local out = {}
  for i = 1, #records do out[i] = records[i] end
  table.sort(out, function(a, b)
    local ma, mb = mine(a, me), mine(b, me)
    if ma ~= mb then return ma end
    local oa, ob = a.state == "open", b.state == "open"
    if oa ~= ob then return oa end
    return byteLess(a.tid, b.tid)
  end)
  return out
end
