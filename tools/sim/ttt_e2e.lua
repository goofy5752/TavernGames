-- Морски шах end to end: luajit tools/sim/ttt_e2e.lua [matches] [seed]
-- Staked and fun matches of two clients on the network simulator: random legal marks, turn-timer
-- auto marks, and the guest (or the host) logging out and back in mid-match. After each match:
-- both clients agree on the match, nobody carries a foul against an honest game, and the ledger
-- (a client that logged back in judges the match "unseen": its debts wait for its word, by design)
-- of both holds exactly one debt, loser -> winner, of the stake (nothing at a fun table).
package.path = "tests/helpers/?.lua;" .. package.path
Loader = require("loader")
local Sim = require("sim")
local ns = Sim.ns
local C = ns.Const
local matches = tonumber(arg and arg[1]) or 200
local seed = tonumber(arg and arg[2]) or 1
math.randomseed(seed)

local A, B = "Иван Петров", "Мария Стоянова"
local SK = 10000
local fails, checks, trace = {}, 0, {}
local function fail(msg)
  fails[#fails + 1] = ("seed %d: %s | %s"):format(seed, msg, table.concat(trace, " "))
  if #fails > 10 then print(table.concat(fails, "\n")); os.exit(1) end
end
local function check(c, msg) checks = checks + 1; if not c then fail(msg) end end

local st = { matches = 0, staked = 0, relogs = 0, autos = 0, debts = 0, fouls = 0 }
for m = 1, matches do
  trace = { "m" .. m }
  local staked = math.random() < 0.7
  local sk = staked and SK or nil
  local sim = Sim.new()
  local cl = { [A] = sim:add(A, { cls = "MAGE" }), [B] = sim:add(B, { cls = "PRIEST" }) }
  sim:run(1)
  local tid = assert(cl[A]:openTable { game = "ttt", access = "guild", turn = 45, stake = sk })
  sim:run(3)
  cl[B]:sit(tid, 2, sk); sim:run(1)
  local seatName = { A, B }
  local relogged = 0
  for step = 1, 400 do
    local host = cl[A]
    local s = host.session
    if not s or s:gameOver() then break end
    local state = s.state
    local seat = state.turn
    if state.phase == "round" then
      sim:run(4) -- the host's "next" after 3 s
    elseif seat then
      local r = math.random()
      local who = seatName[seat]
      if r < 0.04 and relogged < 2 then
        local victim = math.random() < 0.7 and B or A
        trace[#trace + 1] = "relog" .. victim
        relogged = relogged + 1; st.relogs = st.relogs + 1
        cl[victim]:stop(); sim:relog(victim); cl[victim] = sim.clients[victim]
        sim:run(math.random(1, 30)); sim:settle()
        if victim == A then break end -- a host that left: succession is tested elsewhere; stop this match
      elseif r < 0.12 then
        trace[#trace + 1] = "auto" .. seat
        st.autos = st.autos + 1
        sim:run(C.TURN_DEFAULT + C.AUTO_GRACE + 2)
      else
        local c = cl[who].session.state
        local l = ns.Engines.ttt.legal(c, seat)
        local a = l[math.random(#l)]
        trace[#trace + 1] = seat .. ":" .. a.c
        check(cl[who]:act(a), "move refused for " .. who)
        sim:run(1)
      end
    else
      sim:run(1)
    end
  end
  sim:run(C.STAKE_OWE_WAIT + C.STAKE_FAIR_WAIT + 90)
  st.matches = st.matches + 1; if staked then st.staked = st.staked + 1 end
  local hs = cl[A].session
  if hs and hs.state and hs.state.phase == "match" then
    local win = seatName[hs.state.winner]
    local lose = seatName[3 - hs.state.winner]
    for _, name in ipairs { A, B } do
      local s = cl[name].session
      if s then
        check(s.state.phase == "match" and s.state.winner == hs.state.winner and s.state.score[1] == hs.state.score[1] and s.state.score[2] == hs.state.score[2], name .. " disagrees on the match")
        if s.stakeFoul and not (s.stakeFoul == "unseen" and relogged > 0) then st.fouls = st.fouls + 1; fail(name .. " carries foul " .. tostring(s.stakeFoul) .. " at an honest match") end
      end
      local v = ns.LedgerView.of(cl[name].ledger)
      local n = 0
      for _, d in ipairs(v.debts) do
        n = n + 1
        check(d.f == lose and d.t == win and d.c == SK and staked, ("%s sees debt %s %d"):format(name, d.key, d.c or -1))
        check(d.status == "confirmed" or (d.status == "pending" and relogged > 0), name .. " debt status " .. tostring(d.status))
      end
      check(n == (staked and 1 or 0), ("%s sees %d debts"):format(name, n))
      st.debts = st.debts + n
    end
  else
    trace[#trace + 1] = "(match not finished)"
  end
end
print(("matches %d (staked %d), relogs %d, timer autos %d, debts checked %d, fouls %d"):format(st.matches, st.staked, st.relogs, st.autos, st.debts, st.fouls))
print(("checks %d, failures %d"):format(checks, #fails))
for _, f in ipairs(fails) do print(f) end
os.exit(#fails == 0 and 0 or 1)
