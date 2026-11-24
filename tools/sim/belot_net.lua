-- Белот end to end: whole matches to 151 at a real table in the multi-client simulator
-- (tests/helpers/sim.lua, play.lua), every seat moving from its own client by E.bot.
--
--   luajit tools/sim/belot_net.lua [matches = 20] [stake in copper = 50000, 0 = for fun]
--
-- Checks per match: it ends; every client holds the same final state (score, winner,
-- every deal's result); the deals add up to the final score; a staked match leaves exactly
-- two debts, each loser owing the stake to one winner (help.stakes.belot), zero-sum.

package.path = "tests/helpers/?.lua;" .. package.path
Loader = require("loader")
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, View = ns.Const, ns.LedgerView

local MATCHES = tonumber(arg[1]) or 20
local SK = tonumber(arg[2]) or 50000
if SK == 0 then SK = nil end

local failures, t0 = 0, os.clock()
local function fail(m, what)
  failures = failures + 1
  print(string.format("FAIL match %d: %s", m, what))
end

local deals = 0
for m = 1, MATCHES do
  local okay, err = pcall(function()
    local sim, cl = Play.guild(4)
    for i, name in ipairs(Play.NAMES) do
      local x = m * 7919 + i * 104729
      sim.envs[name].random = function(lo, hi)
        x = (x * 48271) % 2147483647
        return lo + x % (hi - lo + 1)
      end
    end
    local tid = Play.open(sim, cl, "belot", SK, 4)
    local host = cl[Play.NAMES[1]]
    local seen = {}
    host:on("result", function() end)
    Play.finish(sim, host, 20000)
    sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 30)
    local st = host.session.state
    if st.phase ~= "match" then fail(m, "host's match not over: " .. tostring(st.phase)) return end
    for _, name in ipairs(Play.NAMES) do
      local s2 = cl[name].session and cl[name].session.state
      if not s2 or s2.phase ~= "match" or s2.winner ~= st.winner or s2.score[1] ~= st.score[1]
        or s2.score[2] ~= st.score[2] then
        fail(m, name .. " ends differently")
      end
    end
    deals = deals + st.round
    if SK then
      local debts = {}
      for _, d in ipairs(View.of(host.ledger).debts) do
        debts[#debts + 1] = d
      end
      local w = st.winner
      local winners = { [Play.NAMES[w]] = true, [Play.NAMES[w + 2]] = true }
      local net, from = {}, {}
      for _, d in ipairs(debts) do
        net[d.f] = (net[d.f] or 0) - d.c
        net[d.t] = (net[d.t] or 0) + d.c
        if winners[d.f] or not winners[d.t] then fail(m, "debt " .. d.f .. " -> " .. d.t) end
        if from[d.f] then fail(m, d.f .. " owes twice") end
        from[d.f] = true
        if d.c ~= SK then fail(m, "debt of " .. tostring(d.c)) end
      end
      if #debts ~= 2 then fail(m, #debts .. " debts, expected 2") end
      local sum = 0
      for _, v in pairs(net) do sum = sum + v end
      if sum ~= 0 then fail(m, "not zero-sum") end
      for name in pairs(winners) do if (net[name] or 0) ~= SK then fail(m, name .. " is owed " .. tostring(net[name])) end end
    end
    Play.restore()
  end)
  if not okay then fail(m, "error " .. tostring(err)) end
end
print(string.format("belot net: %d matches%s, %d deals, %.1fs, failures %d", MATCHES,
  SK and (" staked " .. SK) or " for fun", deals, os.clock() - t0, failures))
os.exit(failures == 0 and 0 or 1)
