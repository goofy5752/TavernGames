-- Табла end to end: luajit tools/sim/tabla_e2e.lua [matches] [seed]   (from the repo root)
-- Whole staked matches (to 5 points, Обикновена -> Тапа -> Гюлбара ...) between two clients in
-- the network simulator (tests/helpers/sim.lua, play.lua), every move the engine's automatic
-- move from the mover's own client, the dice from the fair two-seed throws. Checks per match:
-- it ends, both clients hold the same final state, nobody's stake is fouled, the engine's
-- result has the higher score as winner with 5+ points, and the loser's debt of the stake to
-- the winner is confirmed in both ledgers (and no other debt of the match exists).
package.path = "tests/helpers/?.lua;" .. package.path
Loader = require("loader") -- the helpers expect the test runner's global
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local E = ns.Engines.tabla

local N = tonumber(arg[1]) or 10
local SEED = tonumber(arg[2]) or 1
local SK = 50000

local function lcg(seed)
  local x = seed
  return function(lo, hi)
    x = (x * 1103515245 + 12345) % 2147483648
    return lo + math.floor(x / 65536) % (hi - lo + 1)
  end
end
local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local I, P = Play.NAMES[1], Play.NAMES[2]
local fails, checks, games, t0 = 0, 0, 0, os.clock()
local function check(c, msg) checks = checks + 1; if not c then fails = fails + 1; print("FAIL " .. msg) end end

for m = 1, N do
  local seed = SEED * 1000 + m
  local sim, cl = Play.guild(2)
  local rnd = lcg(seed)
  for _, c in pairs(cl) do c.env.random = rnd end
  local tid = Play.open(sim, cl, "tabla", SK, 2)
  local host = cl[I]
  local last
  host:on("result", function(r) last = r end)
  local steps = 0
  while not (host.session and host.session:gameOver()) and steps < 20000 do
    Play.step(sim, host); steps = steps + 1
  end
  sim:run(5)

  local ctx = " (seed " .. seed .. ")"
  check(last ~= nil, "match did not end" .. ctx)
  if last then
    local hs, gs = host.session.state, cl[P].session.state
    check(deepEq(hs, gs), "host and guest states differ" .. ctx)
    for _, name in ipairs({ I, P }) do check(cl[name].session.stakeFoul == nil, "stake foul at " .. name .. ctx) end
    local r = E.result(hs)
    local w = r and r.winners[1]
    check(w and hs.score[w] >= E.TARGET and hs.score[3 - w] < E.TARGET, "winner/score " .. ctx)
    games = games + hs.game
    local names = last.names or host.session.seats
    local gid = host.session.tid .. "/" .. last.q
    local L, W = names[last.losers[1]], names[last.winners[1]]
    check(W == names[w], "result names the engine's winner" .. ctx)
    for _, name in ipairs({ I, P }) do
      local d = Play.debt(cl[name], gid, L, W)
      check(d and d.c == SK and d.status == "confirmed", "debt not confirmed at " .. name .. ctx)
      check(Play.debt(cl[name], gid, W, L) == nil, "reverse debt exists" .. ctx)
    end
  end
  Play.restore()
end
print(string.format("Табла e2e: %d staked matches, %d games, %d checks, %d failures, %.1fs", N, games, checks, fails, os.clock() - t0))
os.exit(fails == 0 and 0 or 1)
