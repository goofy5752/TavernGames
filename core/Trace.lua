local _, ns = ...

-- Ring buffer of protocol lines for /tavern debug.
local Trace = {}
Trace.__index = Trace
ns.Trace = Trace

local function keyLess(a, b)
  local ta, tb = type(a), type(b)
  if ta == tb and (ta == "number" or ta == "string") then return a < b end
  if ta == tb then return tostring(a) < tostring(b) end
  return ta < tb
end

local function show(v, depth)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  if depth > 3 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, keyLess)
  local parts = {}
  for _, k in ipairs(keys) do
    local key = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
    parts[#parts + 1] = key .. "=" .. show(v[k], depth + 1)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function Trace.new(limit)
  return setmetatable({ limit = limit or ns.Const.TRACE_LINES, buf = {}, first = 1, count = 0, print = nil }, Trace)
end

-- dir "in"/"out"; peer = sender or whisper target (nil for a GUILD send).
function Trace:add(dir, channel, peer, msg)
  local line = table.concat({ tostring(dir), tostring(channel), tostring(peer or "-"), show(msg, 1) }, " ")
  if self.count < self.limit then
    self.buf[(self.first + self.count - 1) % self.limit + 1] = line
    self.count = self.count + 1
  else
    self.buf[self.first] = line
    self.first = self.first % self.limit + 1
  end
  if self.print then self.print(line) end
end

-- Oldest first.
function Trace:lines()
  local out = {}
  for i = 0, self.count - 1 do out[#out + 1] = self.buf[(self.first + i - 1) % self.limit + 1] end
  return out
end
