-- Minimal test runner. Usage: lua tests/run.lua file1.lua file2.lua ...
package.path = "tests/helpers/?.lua;" .. package.path

-- string.format as WoW's Lua 5.1 has it. LuaJIT is laxer: its %s prints
-- nil, booleans and tables through tostring, where 5.1 raises "bad argument
-- #n to 'format' (string expected, got nil)". Every test runs the 5.1 rule:
-- %s and %q take a string or a number, the numeric conversions a number (or
-- a numeric string), and every conversion needs its argument; extra
-- arguments are ignored. The original format then does the formatting.
do
  local format, select, type, tonumber = string.format, select, type, tonumber
  local NUMERIC = { c = true, d = true, i = true, o = true, u = true, x = true, X = true,
    e = true, E = true, f = true, g = true, G = true }
  local function check(n, conv, v, given)
    local t = given and type(v) or "no value"
    if conv == "s" or conv == "q" then
      if t ~= "string" and t ~= "number" then
        error("bad argument #" .. n .. " to 'format' (string expected, got " .. t .. ")", 3)
      end
    elseif NUMERIC[conv] and (not given or (t ~= "number" and t ~= "string") or tonumber(v) == nil) then
      error("bad argument #" .. n .. " to 'format' (number expected, got " .. t .. ")", 3)
    end
  end
  string.format = function(fmt, ...)
    if type(fmt) == "string" then
      local count, arg, i = select("#", ...), 0, 1
      while true do
        local s, e, conv = fmt:find("%%[-+ #0]*%d*%.?%d*(.)", i)
        if not s then break end
        if not (conv == "%" and e == s + 1) then
          arg = arg + 1
          check(arg + 1, conv, (select(arg, ...)), arg <= count)
        end
        i = e + 1
      end
    end
    return format(fmt, ...)
  end
end

local passed, failed = 0, 0
local curDescribe, assertions = "", 0

local function fail(describeName, itName, msg)
  failed = failed + 1
  print("FAIL " .. describeName .. " / " .. itName .. ": " .. tostring(msg))
end

-- A value for a failure message. A table already open on the way down prints
-- as <cycle> (frames point at their parents and back), one nested deeper than
-- SHOW_DEPTH as {…}.
local SHOW_DEPTH = 8
local function show(v, open, depth)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  open, depth = open or {}, depth or 0
  if open[v] then return "<cycle>" end
  if depth >= SHOW_DEPTH then return "{…}" end
  open[v] = true
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = "[" .. show(k, open, depth + 1) .. "]=" .. show(v[k], open, depth + 1)
  end
  open[v] = nil
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEq(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do
    if not deepEq(v, b[k], seen) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function describe(name, fn)
  local prev = curDescribe
  curDescribe = name
  local ok_, err = pcall(fn)
  if not ok_ then fail(name, "(describe body)", err) end
  curDescribe = prev
end

function it(name, fn)
  assertions = 0
  local ok_, err = pcall(fn)
  if not ok_ then
    fail(curDescribe, name, err)
  elseif assertions == 0 then
    fail(curDescribe, name, "no assertions")
  else
    passed = passed + 1
  end
end

function eq(actual, expected, msg)
  assertions = assertions + 1
  if not deepEq(actual, expected) then
    error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function ok(value, msg)
  assertions = assertions + 1
  if not value then error(msg or "expected truthy value, got " .. tostring(value), 2) end
end

function raises(fn, pattern)
  assertions = assertions + 1
  local s, err = pcall(fn)
  if s then error("expected an error, none raised", 2) end
  if pattern and not tostring(err):find(pattern) then
    error("error " .. show(tostring(err)) .. " does not match " .. show(pattern), 2)
  end
end

Loader = require("loader")

for _, path in ipairs({ ... }) do
  local chunk, err = loadfile(path)
  if not chunk then
    fail(path, "(load)", err)
  else
    local s, e = pcall(chunk)
    if not s then fail(path, "(load)", e) end
  end
end

print(passed .. " passed, " .. failed .. " failed")
os.exit(failed > 0 and 1 or 0)
