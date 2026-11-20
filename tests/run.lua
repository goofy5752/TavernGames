-- Minimal test runner. Usage: lua tests/run.lua file1.lua file2.lua ...
package.path = "tests/helpers/?.lua;" .. package.path

local passed, failed = 0, 0
local curDescribe, assertions = "", 0

local function fail(describeName, itName, msg)
  failed = failed + 1
  print("FAIL " .. describeName .. " / " .. itName .. ": " .. tostring(msg))
end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. show(k) .. "]=" .. show(v[k]) end
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
