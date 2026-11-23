-- Death Roll end to end: luajit tools/sim/deathroll_e2e.lua [games] [seed]
-- Whole tables of 2..5 clients on the network simulator (tests/helpers/sim.lua), staked and for fun:
-- real /roll plumbing (core/Rolls.lua), timeout auto-rolls (fun tables), players who stand up
-- mid-game, idle stands (staked), the host's end of the game. After every game the ledger of
-- EVERY client is compared with a reference of who owes whom how much (a leaver pays every player
-- still in the game, the loser pays every player still in the game, a fun table owes nothing).
package.path = "tests/helpers/?.lua;" .. package.path
Loader = require("loader")
local Sim = require("sim")
local ns = Sim.ns
local C = ns.Const
local games = tonumber(arg and arg[1]) or 300
local seed = tonumber(arg and arg[2]) or 1
math.randomseed(seed)

local NAMES = { "Иван Петров", "Петър Колев", "Мария Стоянова", "Гошо Тодоров", "Kiro Barley" }
local SK = 20000 -- 2 gold
local fails, checks, trace = {}, 0, {}
local function fail(msg)
  fails[#fails + 1] = ("seed %d: %s | %s"):format(seed, msg, table.concat(trace, " "))
  if #fails > 10 then print(table.concat(fails, "\n")); os.exit(1) end
end
local function check(c, msg) checks = checks + 1; if not c then fail(msg) end end

local stats = { games = 0, staked = 0, finished = 0, void = 0, leaves = 0, idle = 0, timeouts = 0, debts = 0, aborted = 0 }

for g = 1, games do
  trace = { "g" .. g }
  local n = math.random(2, 5)
  local staked = math.random() < 0.75
  local sk = staked and SK or nil
  local sim = Sim.new()
  local cl = {}
  for i = 1, n do cl[i] = sim:add(NAMES[i], { cls = "MAGE" }) end
  for _, env in pairs(sim.envs) do env.inGroup = function() return true end end
  sim:run(1)
  local host = cl[1]
  local start = ({ 100, 1000, 10000 })[math.random(3)]
  local tid = assert(host:openTable { game = "deathroll", access = "guild", turn = 45, opt = { start = start }, stake = sk })
  sim:run(3)
  for i = 2, n do cl[i]:sit(tid, i, sk); sim:run(1) end
  local okStart = host:startGame(); sim:run(1)
  if not okStart then
    fail("host could not start")
  else
    stats.games = stats.games + 1; if staked then stats.staked = stats.staked + 1 end
    trace[#trace + 1] = ("n=%d staked=%s start=%d"):format(n, tostring(staked), start)
    local present = {} -- seats still in the game (reference)
    for i = 1, n do present[i] = true end
    local function cur() -- the client that is host now (the first seat still in the game once the host left)
      for i = 1, n do if present[i] and cl[i].session and cl[i].session.role == "host" then return cl[i] end end
      for i = 1, n do if present[i] and cl[i].session then return cl[i] end end
      return host
    end
    local expect = {} -- "f|t" -> copper
    local function owe(f, t, c) expect[NAMES[f] .. "|" .. NAMES[t]] = (expect[NAMES[f] .. "|" .. NAMES[t]] or 0) + c end
    local function count() local k = 0 for _, v in pairs(present) do if v then k = k + 1 end end return k end
    local function forfeit(seat) -- a leaver (or idle stand) pays everyone still in the game
      for t = 1, n do if t ~= seat and present[t] then owe(seat, t, SK) end end
      present[seat] = false
    end
    local loser, finished = nil, false
    for step = 1, 300 do
      local s = cur().session
      if not s or s.status ~= "live" or s:gameOver() then break end
      local st = s.state
      local turn = st.turn
      if not turn then break end
      local who = cl[turn]
      local r = math.random()
      -- the live reference must agree with the engine on who is in the game
      for i = 1, n do check((ns.Engines.deathroll.playing(st, i)) == (present[i] == true), "playing() vs reference seat " .. i) end
      if r < 0.07 and count() > 1 then
        -- a player other than the host stands up
        local cands = {}
        for i = 1, n do if present[i] then cands[#cands + 1] = i end end
        local who2 = cands[math.random(#cands)]
        if who2 then
          trace[#trace + 1] = "stand" .. who2
          stats.leaves = stats.leaves + 1
          cl[who2]:stand(); sim:run(1)
          if staked then forfeit(who2) else present[who2] = false end
        end
      elseif r < 0.10 and staked and cl[turn] ~= cur() then
        trace[#trace + 1] = "idle" .. turn
        stats.idle = stats.idle + 1
        sim:run(C.OFFLINE_STAND_SECONDS + 2)
        forfeit(turn)
      elseif r < 0.18 and not staked then
        trace[#trace + 1] = "timeout" .. turn
        stats.timeouts = stats.timeouts + 1
        local k0 = #st.rolls
        sim:run(C.TURN_DEFAULT + C.AUTO_GRACE + 2)
        local s2 = cur().session
        if s2 and s2.state and #s2.state.rolls > k0 then
          local last = s2.state.rolls[#s2.state.rolls]
          check(last.src == "timeout" and last.seat == turn and last.n >= 1 and last.n <= last.max, "timeout roll")
        end
      else
        local max = st.max
        local q = math.random()
        local nn = q < 0.12 and 1 or (q < 0.25 and math.min(2, max) or math.random(1, max))
        trace[#trace + 1] = ("%d:%d/%d"):format(turn, nn, max)
        sim.nextRolls = { nn }
        local ok1 = who:roll()
        sim:run(1)
        check(ok1 ~= nil, "roll refused")
      end
    end
    local s = cur().session
    -- at the end of the game: who lost, per the host's engine
    local st = s and s.state
    if st and st.phase == "over" and st.loser and ns.Engines.deathroll.playing(st, st.loser) then
      stats.finished = stats.finished + 1
      loser = st.loser
      check(st.rolls[#st.rolls].n == 1 and st.rolls[#st.rolls].seat == loser, "loser rolled 1")
      check(count() >= 2, "a loser and nobody left to be paid")
      if staked then
        for t = 1, n do if t ~= loser and present[t] then owe(loser, t, SK) end end
      end
      -- every roll of the game is in range and chained
      for i = 2, #st.rolls do check(st.rolls[i].max == st.rolls[i - 1].n, "chain") end
    elseif st and st.phase == "over" then
      stats.void = stats.void + 1
    elseif not s or s.status ~= "live" then
      stats.aborted = stats.aborted + 1
    else
      fail("game did not end; phase " .. tostring(st and st.phase))
    end
    sim:run(C.STAKE_OWE_WAIT + C.ROLL_FINAL_WAIT + C.STAKE_FAIR_WAIT + 90)
    -- the ledger of every client
    for i = 1, n do
      local v = ns.LedgerView.of(cl[i].ledger)
      local got = {}
      for _, d in ipairs(v.debts) do
        if d.status == "confirmed" or d.status == "pending" then
          got[d.f .. "|" .. d.t] = (got[d.f .. "|" .. d.t] or 0) + (d.c or 0)
        else
          fail(("debt %s in status %s at %s"):format(d.key, tostring(d.status), NAMES[i]))
        end
      end
      for k, c in pairs(expect) do
        check(got[k] == c, ("client %s: debt %s expected %d got %s"):format(NAMES[i], k, c, tostring(got[k])))
        stats.debts = stats.debts + 1
      end
      for k, c in pairs(got) do check(expect[k] == c, ("client %s: unexpected debt %s %d"):format(NAMES[i], k, c)) end
    end
  end
end
print(("games %d (staked %d): finished with loser %d, no loser %d, aborted %d; leaves %d idle stands %d timeouts %d; debts checked %d"):format(
  stats.games, stats.staked, stats.finished, stats.void, stats.aborted, stats.leaves, stats.idle, stats.timeouts, stats.debts))
print(("checks %d, failures %d"):format(checks, #fails))
for _, f in ipairs(fails) do print(f) end
os.exit(#fails == 0 and 0 or 1)
