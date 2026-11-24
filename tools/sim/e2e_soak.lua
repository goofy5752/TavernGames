-- End-to-end soak of whole tables over the multi-client simulator
-- (tests/helpers/sim.lua, play.lua): every game, for fun and staked, played by
-- the engines' own bots/automatic moves, with random disruptions (a /reload, a
-- crash, a disconnect and back, a loading screen, the host or a player leaving
-- mid-match, a long silence on turn, a newcomer mid-game), then the checks:
--   * no Lua error anywhere (every timer and delivery runs under one xpcall per
--     table; a hook error is logged and, with env.strictHooks, raised too);
--   * every client that saw a result saw the same one (winners, losers, names);
--   * every client ends with the same ledger (same ids and hashes, same digest)
--     and so the same debts and balances; the balances sum to zero;
--   * money: every R's pairs have exactly their D entries (amount = stake), no D
--     outside them, no gid of a table with debts and no R; a cash table's
--     debts are exactly its settlements' pairs, and each name's settled
--     chips (chips - bought over its records) equal its debts' net;
--   * no client still sits at a table the others closed, no ghost in a lobby;
--   * no honest client is accused (forged/deal/dice/roll fouls, "bad" hands
--     other than a lapse a disruption explains), no "desync";
--   * fairness of the deal: every dealt deck is the one all revealed seeds give
--     (each client's own audit, verdict "ok"), and no seed reached the dealer
--     before every commit of its round was public;
--   * the timers drain: an idle guild does not grow its timer list.
-- Usage (from the repo root): luajit tools/sim/e2e_soak.lua [tables] [seed] [game|all] [wire]
--   game: ttt deathroll santase belot tabla holdem cash bots (default all, mixed)
--   wire: every message goes through the real wire format (AceSerializer + LibDeflate).
-- Deterministic per seed. Prints a summary and every failure with its seed.
package.path = "tests/helpers/?.lua;" .. package.path

-- string.format as WoW's Lua 5.1 has it (as tests/run.lua installs it).
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

Loader = require("loader")
Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, Ledger, View, Util = ns.Const, ns.Ledger, ns.LedgerView, ns.Util

local TABLES = tonumber(arg[1]) or 1000
local SEED = tonumber(arg[2]) or 1
local ONLY = arg[3] and arg[3] ~= "all" and arg[3] or nil
local FLAGS = {}
for i = 4, #arg do FLAGS[arg[i]] = true end
local WIRE = FLAGS.wire
-- one: exactly the table of seed SEED (a failure's repro), staked or fun as flagged.
local ONE = FLAGS.one
local VERBOSE = os.getenv("SOAK_VERBOSE") == "1"

local NAMES = { "Иван Петров", "Петър Колев", "Мария Стоянова", "Гошо Тодоров", "Kiro Barley", "Нади Колева" }
local BYSTANDER = "Дара Маринова"
local SK = 25000

local function lcg(seed)
  local x = (seed * 7919 + 17) % 2147483648
  return function(lo, hi)
    x = (x * 1103515245 + 12345) % 2147483648
    if lo == nil then return x / 2147483648 end
    if hi == nil then lo, hi = 1, lo end
    return lo + math.floor(x / 65536) % (hi - lo + 1)
  end
end

-- ---------------------------------------------------------------- the patched sim
-- T: the table being run (its log of everything the checks read); set per table.
local T

local function note(kind, msg)
  T.fail[#T.fail + 1] = kind .. ": " .. tostring(msg)
end

local newEnv, addFakes, join = Sim.newEnv, Sim.addFakes, Sim.join
function Sim:newEnv(name, opts)
  local env = newEnv(self, name, opts)
  local sim = self
  env.random = function(lo, hi) return sim.rng(lo, hi) end
  env.realSeeds = true -- seeds out of the secret pool (core/Fair.lua), as the game makes them
  env.log = function(kind, a, b, c)
    if kind == "error" then note("hook error", tostring(name) .. " " .. tostring(b) .. ": " .. tostring(c)) end
    if kind == "ledger" and type(c) == "string" and c:find("^not made") then T.notMade[#T.notMade + 1] = name .. " " .. c end
  end
  return env
end

-- A server roll of 1..hi from the table's stream (sim.nextRolls is the plain queue).
function Sim:addFakes(env, opts)
  addFakes(self, env, opts)
  local roll, sim = env.roll, self
  if roll then
    env.roll = function(lo, hi)
      table.insert(sim.nextRolls, 1, sim.rng(lo, hi))
      return roll(lo, hi)
    end
  end
end

local function listen(name, client)
  client:on("result", function(r)
    T.results[#T.results + 1] = { who = name, r = Util.copy(r), at = T.sim.clock }
    T.saw[name .. "|" .. tostring(r.tid) .. "/" .. tostring(r.q)] = true
  end)
  client:on("fair", function(v) T.fairs[#T.fairs + 1] = { who = name, v = Util.copy(v), at = T.sim.clock } end)
  client:on("forfeit", function(v)
    T.forfeits[#T.forfeits + 1] = { who = name, v = Util.copy(v), host = client.session ~= nil and client.session.role == "host" }
    T.saw[name .. "|" .. tostring(v.tid) .. "/" .. tostring(v.q)] = true
  end)
  client:on("cashout", function(v)
    local s = client.session
    -- seen on a fork: my client cut off, or a host that took the table over and nobody follows
    local fork = T.sim.offlineSet[name] or (s and s.role == "host" and s.claimedFrom ~= nil and not ns.Succession.followed(s))
    T.cashouts[#T.cashouts + 1] = { who = name, v = Util.copy(v), fork = fork and true or false }
    T.saw[name .. "|" .. tostring(v.gid)] = true
  end)
  client:on("desync", function(tid) T.desyncs[#T.desyncs + 1] = name .. " " .. tostring(tid) end)
  client:on("hand", function(v)
    local s = client.session
    T.hands[#T.hands + 1] = { who = name, v = Util.copy(v), host = s and s.role == "host", named = s and s.handNames ~= nil }
  end)
end

function Sim:join(name, env)
  local client = join(self, name, env)
  if T and T.sim == self then listen(name, client) end
  return client
end

-- Fouls my client notes against a game (every one, with who and when).
local foul = ns.Stakes.foul
ns.Stakes.foul = function(s, why)
  if T then T.fouls[#T.fouls + 1] = { who = s.client.env.me, why = why, at = T.sim.clock, tid = s.tid } end
  return foul(s, why)
end

-- Host changes, for the trace (SOAK_DUMP) and the fork count.
local Succ = ns.Succession
local claim, follow = Succ.claim, Succ.follow
Succ.claim = function(s)
  if T then
    T.claims[#T.claims + 1] = { who = s.client.env.me, at = T.sim.clock, e = s.epoch + 1, q = s.seq, old = s.host }
    if os.getenv("SOAK_DUMP") then print(string.format("@%d %s claims epoch %d at seq %d (old host %s)", T.sim.clock, s.client.env.me, s.epoch + 1, s.seq, tostring(s.host))) end
  end
  return claim(s)
end
Succ.follow = function(s, host, epoch, seats)
  if T and os.getenv("SOAK_DUMP") then
    print(string.format("@%d %s (%s e%d q%d) follows %s at epoch %d", T.sim.clock, s.client.env.me, s.role, s.epoch, s.seq, host, epoch))
  end
  return follow(s, host, epoch, seats)
end

local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
if WIRE then
  local size = ns.LedgerNet.size
  ns.LedgerNet.size = function(msg) return #wire:pack(msg) end
  _ = size
end

-- ---------------------------------------------------------------- the guild
local function guild(n, rng)
  local sim = Sim.new()
  sim.rng = rng
  T.sim = sim
  if WIRE then
    sim.bus.filter = function(_, _, _, msg)
      local back = wire:unpack(wire:pack(msg))
      if back == nil then note("wire", "a message did not survive the wire: " .. tostring(msg.t)) end
      return { back }
    end
  end
  local names = {}
  for i = 1, n do names[i] = NAMES[i] end
  names[#names + 1] = BYSTANDER
  local cl = {}
  for _, name in ipairs(names) do
    cl[name] = sim:add(name, { group = names, near = names })
  end
  sim:run(1)
  sim:settle()
  return sim, names
end

local function live(sim, name)
  local c = sim.clients[name]
  return c and not c.env.dead and c or nil
end

-- The client that hosts tid live now (the newest epoch if two think so).
local function hostOf(sim, tid)
  local best
  for _, name in ipairs(T.names) do
    local c = live(sim, name)
    local s = c and c.session
    if s and s.tid == tid and s.role == "host" and s.status == "live" and not sim.offlineSet[name] then
      if not best or (s.epoch or 0) > (best.session.epoch or 0) then best = c end
    end
  end
  return best
end

local function anyAt(sim, tid)
  for _, name in ipairs(T.names) do
    local c = live(sim, name)
    if c and c.session and c.session.tid == tid then return c end
  end
  return nil
end

-- ---------------------------------------------------------------- driving
local E = function(id) return ns.Engines[id] end

-- One move: the seat on turn at the host's table plays from its own client
-- (engine.bot, else the automatic move; Death Roll: a server roll); a busted
-- cash seat buys again or stands. Then one second.
local function step(sim, tid)
  local h = hostOf(sim, tid)
  local s = h and h.session
  if s and s.state then
    local seat = s.state.turn
    local name = seat and s.seats[seat]
    local c = name and live(sim, name)
    if c and c.session and c.session.tid == tid and c.session.state and c.session.mySeat == seat
        and not T.muted[name] then
      local cs = c.session
      local Eg = cs:engine()
      if cs.game == "deathroll" then
        if not cs.rolling then c:roll() end
      else
        local a
        if Eg.bot then a = Eg.bot(cs.state, seat, c.env.random) end
        if a then c:act(a) else c:playAuto() end
      end
    end
    if s.game == "holdem" and s.stake ~= nil and not E("holdem").inHand(s.state) then
      for i, nm in ipairs(T.names) do
        local seatRec = s.state.seats and s.state.seats[i]
        local cc = live(sim, nm)
        if cc and cc.session and cc.session.tid == tid and cc.session.mySeat and not T.muted[nm] then
          local st = cc.session.state
          local my = st and st.seats and st.seats[cc.session.mySeat]
          if my and my.chips == 0 and not my.leaving then
            local lo, hi = E("holdem").buyRange(st, cc.session.mySeat)
            if type(lo) == "number" and type(hi) == "number" and lo <= hi and sim.rng() < 0.7 then
              cc:act{ k = "buy", n = sim.rng(lo, hi) }
            elseif sim.rng() < 0.3 then
              cc:stand(); T.events[#T.events + 1] = "busted stand " .. nm
            end
          end
        end
        _ = seatRec
      end
    end
  end
  sim:run(1)
end

-- ---------------------------------------------------------------- disruptions
local KINDS = { "reload", "crash", "offline", "loading", "hostleave", "leave", "silence", "hostgone", "newcomer" }

local function disrupt(sim, tid, kind)
  local rng = sim.rng
  local h = hostOf(sim, tid)
  local seated = {}
  for _, name in ipairs(T.names) do
    local c = live(sim, name)
    if c and c.session and c.session.tid == tid and c.session.mySeat then seated[#seated + 1] = name end
  end
  if #seated == 0 then return end
  local who = seated[rng(1, #seated)]
  local line = kind .. " " .. who .. " @" .. sim.clock
  if kind == "reload" then
    sim:relog(who); sim:settle()
  elseif kind == "crash" then
    sim:crash(who); sim:settle()
  elseif kind == "offline" then
    local secs = ({ 3, 20, 60, 100, 200 })[rng(1, 5)]
    line = line .. " for " .. secs
    sim:offline(who)
    T.back[#T.back + 1] = { at = sim.clock + secs, fn = function() sim:online(who) end }
  elseif kind == "loading" then
    local secs = rng(2, 25)
    line = line .. " for " .. secs
    sim:loading(who, true); sim:offline(who)
    T.back[#T.back + 1] = { at = sim.clock + secs, fn = function() sim:online(who); sim:loading(who, false) end }
  elseif kind == "hostleave" then
    if not h then return end
    who = h.env.me; line = kind .. " " .. who .. " @" .. sim.clock
    h:stand(); T.left[who] = true
  elseif kind == "leave" then
    sim.clients[who]:stand(); T.left[who] = true
  elseif kind == "silence" then
    local secs = ({ 35, 50, 95, 200 })[rng(1, 4)]
    line = line .. " for " .. secs
    T.muted[who] = true
    T.back[#T.back + 1] = { at = sim.clock + secs, fn = function() T.muted[who] = nil end }
  elseif kind == "hostgone" then
    if not h then return end
    who = h.env.me; line = kind .. " " .. who .. " @" .. sim.clock
    h.env.dead = true; sim:offline(who); T.gone[who] = true
    T.back[#T.back + 1] = { at = sim.clock + rng(200, 900), fn = function()
      T.gone[who] = nil; sim:online(who); sim:crash(who); sim:settle()
    end }
  elseif kind == "newcomer" then
    local s = h and h.session
    if not (s and s.game == "holdem") then return end
    for i, name in ipairs(T.names) do
      local c = live(sim, name)
      if i <= #NAMES and name ~= BYSTANDER and c and not c.session and not s.seats[i] and i <= E("holdem").maxSeats and not T.left[name] then
        line = kind .. " " .. name .. " @" .. sim.clock
        c:sit(tid, i, s.stake)
        T.joinLater[name] = sim.clock
        break
      end
    end
  end
  T.events[#T.events + 1] = line
end

local function backs(sim)
  for i = #T.back, 1, -1 do
    local b = T.back[i]
    if sim.clock >= b.at then table.remove(T.back, i); b.fn() end
  end
end

-- ---------------------------------------------------------------- one table
local SEATS = { ttt = { 2, 2 }, deathroll = { 2, 5 }, santase = { 2, 2 }, belot = { 4, 4 }, tabla = { 2, 2 }, holdem = { 2, 6 } }

local function stakeOf(game, opt)
  if game == "holdem" then return E("holdem").stakeOf(opt) end
  return SK
end

-- Is the game played at tid over (every running client that holds it says so), or the table gone?
local function finished(sim, tid, game)
  local c = hostOf(sim, tid)
  if not c then
    -- no live host: over unless a member still holds the table live (a takeover under way)
    for _, name in ipairs(T.names) do
      local m = live(sim, name)
      local s = m and m.session
      if s and s.tid == tid and s.status == "live" and not (s.state and s:gameOver()) then return false end
    end
    return true
  end
  local s = c.session
  if game == "holdem" then return s.state ~= nil and E("holdem").over(s.state) end
  return s:gameOver() and s.state ~= nil and T.played
end

local function openTable(sim, game, staked, n, rng)
  local host = sim.clients[T.names[1]]
  local opt
  if game == "deathroll" then opt = { start = ({ 100, 1000, 10000 })[rng(1, 3)] } end
  if game == "holdem" then
    opt = { blinds = ({ 10, 20, 50 })[rng(1, 3)], betting = rng() < 0.5 and "nl" or "pl" }
    if staked then opt.rebuy = ({ "none", "bust", "top" })[rng(1, 3)] else opt.stack = ({ 50, 100 })[rng(1, 2)] end
  end
  local sk = staked and stakeOf(game, opt) or nil
  local tid = assert(host:openTable{ game = game, access = "guild", turn = 30, opt = opt, stake = sk })
  sim:run(3)
  for seat = 2, n do
    sim.clients[T.names[seat]]:sit(tid, seat, sk)
    sim:run(1)
  end
  if game == "deathroll" or game == "holdem" then
    for _ = 1, 40 do
      local ok = host:startGame()
      if ok then break end
      sim:run(1)
    end
    sim:run(1)
  end
  if game == "holdem" and staked then
    for seat = 1, n do
      local c = sim.clients[T.names[seat]]
      local lo, hi = E("holdem").buyRange(c.session.state, seat)
      if type(lo) == "number" and type(hi) == "number" then c:act{ k = "buy", n = rng(lo, hi) } end
      sim:run(1)
    end
  end
  return tid, sk, opt
end

local SHORT = { santase = "GOAL", belot = "TARGET", tabla = "TARGET" }

local function runTable(idx, seed, game, staked)
  local rng = lcg(seed)
  T = { idx = idx, seed = seed, game = game, staked = staked, fail = {}, results = {}, fairs = {}, forfeits = {},
    cashouts = {}, hands = {}, claims = {}, saw = {}, desyncs = {}, fouls = {}, events = {}, back = {}, muted = {}, left = {}, gone = {},
    joinLater = {}, notMade = {}, checks = 0 }
  local lo, hi = SEATS[game][1], SEATS[game][2]
  local n = rng(lo, hi)
  local sim, names = guild(game == "holdem" and math.min(6, n + 1) or n, rng)
  T.names, T.n = names, n
  local short = SHORT[game] and rng() < 0.85
  local was
  if short then was = E(game)[SHORT[game]]; E(game)[SHORT[game]] = 1 end
  local okRun, err = xpcall(function()
    local tid, sk = openTable(sim, game, staked, n, rng)
    T.tid, T.sk = tid, sk
    local h0 = sim.clients[names[1]]
    if not (h0.session and h0.session.status == "live") then note("setup", "the table is not live") end
    T.played = false
    local hands = game == "holdem" and rng(3, 14) or nil
    local closed = false
    local disruptions = rng() < 0.15 and 0 or rng(1, 3)
    local plan = {}
    for _ = 1, disruptions do plan[#plan + 1] = { at = rng(2, game == "ttt" and 8 or 60), kind = KINDS[rng(1, #KINDS)] } end
    local steps = 0
    for _ = 1, 9000 do
      backs(sim)
      steps = steps + 1
      for _, p in ipairs(plan) do
        if not p.done and steps >= p.at then p.done = true; disrupt(sim, tid, p.kind) end
      end
      local h = hostOf(sim, tid)
      if h and h.session.state then
        local st = h.session.state
        if game == "holdem" then
          T.played = true
          -- the hands asked for were played, or no hand can start any more (the others busted at a fun table)
          local idle = (st.phase == "done" or st.phase == "idle") and E("holdem").system(st) == nil and not T.back[1]
          if not closed and ((st.hand or 0) >= hands or idle) then
            if ns.Cash.close(h) then closed = true; T.closed = true; T.events[#T.events + 1] = "close @" .. sim.clock end
          end
        elseif not h.session:gameOver() then
          T.played = true
        end
      end
      if T.played and finished(sim, tid, game) and #T.back == 0 then break end
      step(sim, tid)
    end
    if not finished(sim, tid, game) then
      note("stuck", "the game did not end in 9000 steps")
      if os.getenv("SOAK_DUMP") then
        for _, nm in ipairs(names) do
          local c = sim.clients[nm]; local s = c.session; local st = s and s.state; local f = s and s.fair
          print(nm, s and s.role, s and s.epoch, s and s.seq, st and st.phase, st and st.turn, st and st.hand, f and f.stage, f and f.h, f and f.d, s and s.stale, s and s.mySeat, st and st.seats and s.mySeat and st.seats[s.mySeat] and tostring(st.seats[s.mySeat].away), s and tostring(s.backAsked), s and st and tostring((ns.Engines.holdem.system(st) or {}).k), s and tostring(s.systemTimer ~= nil), s and tostring(s.fairTimer ~= nil), s and s.fair and tostring(s.fair.wantOpen), s and s.fair and tostring(s.fair.revealed))
        end
      end
    end
    T.steps = steps
    -- Wind down: everyone back, a little while at the table, then everyone stands.
    for _, b in ipairs(T.back) do b.fn() end
    T.back = {}
    for name in pairs(T.muted) do T.muted[name] = nil end
    sim:run(rng(0, 60))
    for _, name in ipairs(names) do
      local c = live(sim, name)
      if c and c.session and c.session.tid == tid then c:stand(); sim:run(rng(0, 3)) end
    end
    sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 30)
  end, debug.traceback)
  if short then E(game)[SHORT[game]] = was end
  if not okRun then note("lua error", err) end
  return sim
end

-- ---------------------------------------------------------------- the checks
local function sortedKeys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

local function canonList(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for _, k in ipairs(sortedKeys(v)) do parts[#parts + 1] = tostring(k) .. "=" .. canonList(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function ledgerOf(c)
  local set, n = {}, 0
  c.ledger:each(function(e) set[e.i .. "#" .. e.h] = true; n = n + 1 end)
  return set, n
end

local function same(a, b)
  for k in pairs(a) do if not b[k] then return false, k end end
  for k in pairs(b) do if not a[k] then return false, k end end
  return true
end

-- Runs until every client holds the same ledger (at most `limit` s) -> converged, seconds.
local function converge(sim, limit)
  local t0 = sim.clock
  while true do
    local first, ok = nil, true
    for _, name in ipairs(T.names) do
      local c = sim.clients[name]
      local set = ledgerOf(c)
      if not first then first = set elseif not same(first, set) then ok = false; break end
    end
    if ok then return true, sim.clock - t0 end
    if sim.clock - t0 >= limit then return false, sim.clock - t0 end
    sim:run(10)
  end
end

local function checkResults()
  local byQ = {}
  for _, x in ipairs(T.results) do
    local r = x.r
    if r.tid == T.tid then
      local key = canonList({ w = r.winners, l = r.losers, n = r.names, left = r.left or false })
      byQ[r.q] = byQ[r.q] or {}
      byQ[r.q][key] = (byQ[r.q][key] or "") .. x.who .. ";"
    end
  end
  for q, keys in pairs(byQ) do
    T.checks = T.checks + 1
    if #sortedKeys(keys) > 1 then
      local parts = {}
      for k, who in pairs(keys) do parts[#parts + 1] = who .. " => " .. k end
      note("result disagree", "q=" .. q .. ": " .. table.concat(parts, " | "))
    end
  end
  return byQ
end

-- The names of a list of seats by the R's n.
local function namesOf(n, seats)
  local out = {}
  for _, s in ipairs(seats or {}) do if type(n[s]) == "string" then out[#out + 1] = n[s] end end
  return out
end

local function checkMoney(sim)
  local ref = sim.clients[BYSTANDER]
  local v = View.of(ref.ledger)
  local prefix = T.tid .. "/"
  local Rs, Ds, Ss = {}, {}, {}
  ref.ledger:each(function(e)
    if type(e.gid) == "string" and e.gid:sub(1, #prefix) == prefix then
      if e.k == "R" then Rs[e.gid] = Rs[e.gid] or {}; table.insert(Rs[e.gid], e) end
      if e.k == "D" then Ds[e.gid] = Ds[e.gid] or {}; table.insert(Ds[e.gid], e) end
      if e.k == "S" then Ss[#Ss + 1] = e end
    end
  end)
  local cash = T.game == "holdem" and T.staked
  if os.getenv("SOAK_DUMP") and not cash then
    ref.ledger:each(function(e) print("ledger " .. canonList(Ledger.wire(e))) end)
    for _, x in ipairs(T.results) do print("result seen by " .. x.who .. " @" .. x.at .. ": " .. canonList({ q = x.r.q, w = x.r.winners, l = x.r.losers, left = x.r.left, n = x.r.names })) end
    for _, x in ipairs(T.forfeits) do print("forfeit seen by " .. x.who .. ": " .. canonList(x.v)) end
  end
  if not T.staked then
    for gid in pairs(Ds) do note("money", "a D at a fun table: " .. gid) end
    for _ in pairs(Ss) do note("money", "an S at a fun table") end
    return
  end
  -- every pair key gid|f|t of the D entries, with its amounts
  local have = {}
  for gid, list in pairs(Ds) do
    for _, d in ipairs(list) do
      local key = gid .. "|" .. d.f .. "|" .. d.t
      have[key] = have[key] or {}
      have[key][d.c] = true
    end
  end
  local want = {}
  if not cash then
    local results = checkResults()
    -- The outcome of each gid: the host's R; without one (the host's client died
    -- before its entry went out, or the successor that was to write the R of its
    -- host's forfeit reloaded), the result or forfeit every client saw.
    local outcome = {}
    for gid, list in pairs(Rs) do
      local r1 = list[1]
      for i = 2, #list do
        if canonList({ list[i].w, list[i].l, list[i].n, list[i].sk }) ~= canonList({ r1.w, r1.l, r1.n, r1.sk }) then
          note("money", "two different R for " .. gid)
        end
      end
      T.checks = T.checks + 1
      if r1.sk ~= T.sk then note("money", "R stake " .. tostring(r1.sk) .. " ~= " .. tostring(T.sk)) end
      outcome[gid] = { l = namesOf(r1.n, r1.l), w = namesOf(r1.n, r1.w), why = r1.why, ls = r1.l, ws = r1.w }
    end
    for q, keys in pairs(results) do
      local gid = T.tid .. "/" .. q
      if not outcome[gid] then
        T.noR = (T.noR or 0) + 1
        for _, x in ipairs(T.results) do
          if x.r.tid == T.tid and x.r.q == q then
            local r = x.r
            outcome[gid] = { l = namesOf(r.names, r.losers), w = namesOf(r.names, r.winners), why = r.left and "left" or nil, ls = r.losers, ws = r.winners }
            break
          end
        end
      end
      _ = keys
    end
    for _, x in ipairs(T.forfeits) do
      local gid = x.v.tid .. "/" .. x.v.q
      -- the leaver's own client only predicts the number of its stand: not the gid the host gives it
      if x.v.tid == T.tid and not outcome[gid] and (x.who ~= x.v.name or x.host) then
        T.noR = (T.noR or 0) + 1
        outcome[gid] = { l = { x.v.name }, w = x.v.to, why = x.v.why }
      end
    end
    -- Who owes whom, from the rules the players were promised (not the code's
    -- own pairing): every loser owes every winner the stake; in a team game a
    -- played-out match pairs the losers and winners by ascending seat; a forfeit
    -- (why) is the leaver's debt to everyone it named.
    for gid, o in pairs(outcome) do
      if E(T.game).teams and not o.why and o.ls then
        local ls, ws = Util.copy(o.ls), Util.copy(o.ws)
        table.sort(ls); table.sort(ws)
        local L = namesOf(Rs[gid] and Rs[gid][1].n or {}, ls)
        local W = namesOf(Rs[gid] and Rs[gid][1].n or {}, ws)
        if #L == 0 then L, W = o.l, o.w end
        for i = 1, math.min(#L, #W) do want[gid .. "|" .. L[i] .. "|" .. W[i]] = T.sk end
      else
        for _, f in ipairs(o.l) do
          for _, t in ipairs(o.w) do if f ~= t then want[gid .. "|" .. f .. "|" .. t] = T.sk end end
        end
      end
    end
  else
    -- The settlements the clients saw, by gid and seat. A client cut off for
    -- longer than SILENT_AFTER takes the table over on its own (a fork, healed by
    -- core/Succession.lua once it hears the others): what only such a fork saw is
    -- counted when most clients saw it, and listed (T.forks) when not.
    local perName, seenBy, maxSeen = {}, {}, 0
    if os.getenv("SOAK_DUMP") then
      for _, x in ipairs(T.cashouts) do print("cashout seen by " .. x.who .. ": " .. canonList(x.v)) end
      ref.ledger:each(function(e) print("ledger " .. canonList(Ledger.wire(e))) end)
    end
    for _, x in ipairs(T.cashouts) do
      local key = x.v.gid .. "|" .. x.v.seat
      local body = canonList({ x.v.name, x.v.chips, x.v.bought, x.v.pairs })
      local r = seenBy[key]
      if r and r.body ~= body then note("money", "two different settlements " .. key) end
      if not r then r = { body = body, v = x.v, who = {} }; seenBy[key] = r end
      r.who[x.who] = true
      if not x.fork then r.real = true end
    end
    for _, r in pairs(seenBy) do r.n = #sortedKeys(r.who); maxSeen = math.max(maxSeen, r.n) end
    local function person(nm) perName[nm] = perName[nm] or { chips = 0, net = 0 }; return perName[nm] end
    for key, r in pairs(seenBy) do
      if r.real then
        person(r.v.name).chips = person(r.v.name).chips + (r.v.chips - r.v.bought) * ns.HoldemCash.CHIP
        person(r.v.name).settled = true
        for _, p in ipairs(r.v.pairs) do
          local k = r.v.gid .. "|" .. p.f .. "|" .. p.t
          want[k] = (want[k] or 0) + p.c
          person(p.t).net = person(p.t).net + p.c
          person(p.f).net = person(p.f).net - p.c
        end
      else
        T.forks = (T.forks or 0) + 1
        for _, p in ipairs(r.v.pairs) do
          local k = r.v.gid .. "|" .. p.f .. "|" .. p.t
          if have[k] then note("money", "a D of a settlement only a fork saw: " .. k) end
          T.forkKeys = T.forkKeys or {}
          T.forkKeys[k] = true
        end
      end
    end
    -- Each name's settled chips (chips - bought over its records) are its pairs'
    -- net, every pair counted once on either side: checked when the table was
    -- closed (every seat then has its record). The last seat of a table that
    -- emptied without a close has none (its pairs were settled by the others).
    local total = 0
    for nm, x in pairs(perName) do
      total = total + x.chips
      T.checks = T.checks + 1
      if T.closed and x.chips ~= x.net then note("money", nm .. " settled chips " .. x.chips .. " but its pairs net " .. x.net) end
    end
    if T.closed and total ~= 0 then note("money", "chips not conserved over the settlements: " .. total) end
    -- The hands themselves, the same on every client but a fork's: won == put in.
    local hands = {}
    for _, x in ipairs(T.hands) do
      local body = canonList({ x.v.last.contrib, x.v.last.won })
      local sum = 0
      for _, c in pairs(x.v.last.contrib or {}) do sum = sum - c end
      for _, c in pairs(x.v.last.won or {}) do sum = sum + c end
      T.checks = T.checks + 1
      if sum ~= 0 then note("money", x.who .. ": hand " .. x.v.n .. " won and put in differ by " .. sum) end
      hands[x.v.n] = hands[x.v.n] or {}
      hands[x.v.n][body] = (hands[x.v.n][body] or 0) + 1
    end
    for n, bodies in pairs(hands) do
      if #sortedKeys(bodies) > 1 then T.handForks = (T.handForks or 0) + 1 end
      _ = n
    end
  end
  for key, c in pairs(want) do
    T.checks = T.checks + 1
    local gid, creditor = key:match("^(.-)|[^|]*|([^|]*)$")
    if not have[key] and not T.saw[creditor .. "|" .. gid] then
      -- Only a creditor writes a forfeit's or a cash pair's claim (a leaver's own client cannot know
      -- the gid its stand gets): a creditor whose client never applied that event (cut off, crashed) writes none.
      T.away = (T.away or 0) + 1
      if VERBOSE then print("   (creditor away: no D for " .. key .. ")") end
    elseif not have[key] then note("money", "lost: no D for " .. key .. " (" .. c .. ")")
    else
      for amt in pairs(have[key]) do if amt ~= c then note("money", "D " .. key .. " for " .. amt .. ", want " .. c) end end
    end
  end
  for key in pairs(have) do
    T.checks = T.checks + 1
    if not want[key] then note("money", "a D no result explains: " .. key) end
  end
  -- balances: zero-sum, and the same on every client
  local nets = {}
  for _, name in ipairs(T.names) do
    local vv = View.of(sim.clients[name].ledger)
    local sum, parts = 0, {}
    for _, a in ipairs(T.names) do
      for _, b in ipairs(T.names) do
        if a ~= b then sum = sum + View.net(vv, a, b); parts[#parts + 1] = View.net(vv, a, b) end
      end
    end
    if sum ~= 0 then note("money", name .. ": the balances sum to " .. sum) end
    nets[name] = table.concat(parts, ",")
  end
  for _, name in ipairs(T.names) do
    T.checks = T.checks + 1
    -- own entries the guild gave back after a crash count for nothing until the player says they are his (LedgerNet: `un`)
    local held = false
    sim.clients[name].ledger:each(function(e) if e.un then held = true end end)
    if held then T.unHeld = (T.unHeld or 0) + 1
    elseif nets[name] ~= nets[BYSTANDER] then note("money", name .. "'s balances differ from the bystander's") end
  end
  -- the debts' statuses, for the summary
  T.status = {}
  for _, d in ipairs(v.debts) do
    if d.gid:sub(1, #prefix) == prefix then T.status[d.status] = (T.status[d.status] or 0) + 1 end
  end
end

-- No seed reached a dealer before every commit of its round was public (an EV
-- with the commits); the reveal's seeds give every deck that was dealt.
local function checkFair(sim)
  local commits, rounds = {}, {}
  for _, m in ipairs(sim.sent) do
    local msg = m.msg
    if msg.tid == T.tid and msg.t == "EV" and type(msg.a) == "table" and msg.a.k == "fair" then
      local a = msg.a
      local h = a.h
      if a.op == "open" then rounds[h] = rounds[h] or { p = a.p, c = {} } end
      if a.op == "commit" and rounds[h] then rounds[h].c[a.seat] = true end
      if a.op == "commits" and rounds[h] then for seat in pairs(a.c or {}) do rounds[h].c[seat] = true end end
    elseif msg.tid == T.tid and msg.t == "SED" then
      local r = rounds[msg.h]
      T.checks = T.checks + 1
      if r then
        for _, seat in ipairs(r.p or {}) do
          if not r.c[seat] then note("fair", "a seed went to the dealer of round " .. msg.h .. " before seat " .. seat .. "'s commit") end
        end
      end
    end
  end
  _ = commits
  -- verdicts: "bad" is only what a disruption explains
  local disrupted = #T.events > 0
  for _, x in ipairs(T.fairs) do
    T.checks = T.checks + 1
    local v = x.v
    if v.verdict == "bad" then
      local why = v.why
      local explained = disrupted and (why == "noreveal" or why == "nodeal" or why == "void")
      T.bad = (T.bad or 0) + 1
      if not explained then note("fair", x.who .. " judged hand " .. tostring(v.h) .. " bad: " .. tostring(why) .. " @" .. x.at .. " dealer " .. tostring(v.dealer)) end
    end
  end
end

local HONEST_OK = { unseen = true, stand = true }
local function checkFouls()
  for _, f in ipairs(T.fouls) do
    T.checks = T.checks + 1
    if not HONEST_OK[f.why] then note("foul", f.who .. " noted " .. f.why .. " @" .. f.at) end
  end
  for _, d in ipairs(T.desyncs) do note("desync", d) end
end

local function checkStuck(sim)
  for _, name in ipairs(T.names) do
    local c = sim.clients[name]
    T.checks = T.checks + 1
    if c.session and c.session.tid == T.tid then
      note("stuck", name .. " still at the table (" .. tostring(c.session.role) .. ", " .. tostring(c.session.status) .. ")")
    end
    if c.pending then note("stuck", name .. " has a pending request") end
  end
  sim:run(C.TBL_EXPIRE + 5)
  for _, name in ipairs(T.names) do
    T.checks = T.checks + 1
    if sim.clients[name].lobby:get(T.tid) then note("ghost", name .. " still lists the table") end
  end
end

local function timerCount(sim)
  local n = 0
  for _, t in ipairs(sim.timers) do if not t.cancelled and not t.env.dead then n = n + 1 end end
  return n
end

local function checkTimers(sim)
  local a = timerCount(sim)
  sim:run(600)
  local b = timerCount(sim)
  T.checks = T.checks + 1
  T.timers = b
  if b > a + 2 * #T.names then note("timers", "the idle guild's timers grew " .. a .. " -> " .. b) end
  if b > 40 * #T.names then note("timers", b .. " timers for " .. #T.names .. " clients") end
end

local function checkAll(sim)
  local ok, err = xpcall(function()
    -- everyone online (a host gone for good came back above)
    local conv, secs = converge(sim, 1800)
    T.checks = T.checks + 1
    T.conv = secs
    if not conv then
      local counts = {}
      for _, name in ipairs(T.names) do local _, nn = ledgerOf(sim.clients[name]); counts[#counts + 1] = name .. "=" .. nn end
      note("ledger", "did not converge in 1800 s: " .. table.concat(counts, " "))
    else
      local d0
      for _, name in ipairs(T.names) do
        local d = sim.clients[name].ledger:digest()
        d0 = d0 or d
        if d ~= d0 then note("ledger", "digest of " .. name .. " differs") end
      end
    end
    checkResults()
    if T.tid then checkMoney(sim) end
    checkFair(sim)
    checkFouls()
    checkStuck(sim)
    checkTimers(sim)
  end, debug.traceback)
  if not ok then note("lua error (checks)", err) end
end

-- ---------------------------------------------------------------- bots
-- One human hosts a fun table filled with bots (core/Bots.lua), another human
-- is in the guild: the game ends, no error, nothing of the bot table reaches the other.
local function runBots(idx, seed)
  local rng = lcg(seed)
  local games = { "ttt", "deathroll", "santase", "belot", "tabla", "holdem" }
  local game = games[rng(1, #games)]
  T = { idx = idx, seed = seed, game = "bots:" .. game, staked = false, fail = {}, results = {}, fairs = {}, forfeits = {},
    cashouts = {}, hands = {}, claims = {}, saw = {}, desyncs = {}, fouls = {}, events = {}, back = {}, muted = {}, left = {}, gone = {}, joinLater = {}, notMade = {}, checks = 0 }
  local sim = Sim.new()
  sim.rng = rng
  T.sim = sim
  local A, B = NAMES[1], NAMES[2]
  T.names = { A, B }
  local a, envA = sim:add(A, {}); sim:add(B, {})
  local bots = ns.Bots.enable(a, envA, sim.makeEnv)
  sim:run(1); sim:settle()
  local short = SHORT[game]
  local was
  if short then was = E(game)[short]; E(game)[short] = 1 end
  local ok, err = xpcall(function()
    local tid = assert(a:openTable{ game = game, access = "invite", turn = 30 })
    T.tid = tid
    bots:fill()
    sim:run(15)
    if game == "deathroll" or game == "holdem" then a:startGame(); sim:run(3) end
    local hands = rng(2, 6)
    for _ = 1, 4000 do
      local s = a.session
      if not s then break end
      if game == "holdem" and s.state and (s.state.hand or 0) >= hands and not E("holdem").over(s.state) then ns.Cash.close(a) end
      if s.state and s:gameOver() and #T.results > 0 then break end
      if game == "holdem" and s.state and E("holdem").over(s.state) then break end
      if s.state and s.state.turn == s.mySeat then
        if game == "deathroll" then if not s.rolling then a:roll() end
        else
          local Eg = s:engine()
          local act = Eg.bot and Eg.bot(s.state, s.mySeat, a.env.random)
          if act then a:act(act) else a:playAuto() end
        end
      end
      sim:run(1)
    end
    local s = a.session
    if not (s and s.state and (s:gameOver() or (game == "holdem" and E("holdem").over(s.state)))) then note("stuck", "the bot game did not end") end
    a:stand(); sim:run(5)
    bots:closeAll(); sim:run(5)
    -- nothing of the bot table on the real side: B never heard of tid
    for _, m in ipairs(sim.sent) do
      if m.channel == "WHISPER" and m.target == B and m.msg.tid == tid then note("bots", "a whisper of the bot table reached " .. B) end
    end
    if sim.clients[B].lobby:get(tid) then note("bots", B .. " lists the bot table") end
    if sim.clients[B].session then note("bots", B .. " sits somewhere") end
    for _, nm in ipairs(T.names) do
      local _, n = ledgerOf(sim.clients[nm])
      T.checks = T.checks + 1
      if n > 0 then
        local any = false
        sim.clients[nm].ledger:each(function(e) if e.gid and e.gid:find(tid, 1, true) then any = true end end)
        if any then note("bots", nm .. " has a ledger entry of the bot table") end
      end
    end
    checkFouls()
  end, debug.traceback)
  if short then E(game)[short] = was end
  if not ok then note("lua error", err) end
  return sim
end

-- ---------------------------------------------------------------- main
local GAMES = { "ttt", "deathroll", "santase", "belot", "tabla", "holdem", "cash" }
local master = lcg(SEED * 104729 + 3)
local stats = { tables = 0, checks = 0, failed = 0, byGame = {}, steps = 0, conv = 0, status = {}, bad = 0, events = {},
  noR = 0, away = 0, forks = 0, handForks = 0, unHeld = 0, claims = 0 }
local failures = {}
local t0 = os.clock()
for idx = 1, TABLES do
  local seed = ONE and SEED or SEED * 100000 + idx
  local pick = ONLY or GAMES[master(1, #GAMES + 1)] or "bots"
  local staked = master() < 0.6
  if ONE then staked = FLAGS.staked == true end
  local game = pick
  if pick == "cash" then game, staked = "holdem", true end
  if pick == "holdem" then staked = false end
  local sim
  if pick == "bots" then sim = runBots(idx, seed)
  else
    sim = runTable(idx, seed, game, staked)
    checkAll(sim)
  end
  local label = T.game .. (T.staked and "/staked" or "/fun")
  local g = stats.byGame[label] or { n = 0, failed = 0 }
  stats.byGame[label] = g
  g.n = g.n + 1
  stats.tables = stats.tables + 1
  stats.checks = stats.checks + T.checks
  stats.steps = stats.steps + (T.steps or 0)
  stats.bad = stats.bad + (T.bad or 0)
  for _, k in ipairs({ "noR", "away", "forks", "handForks", "unHeld" }) do stats[k] = stats[k] + (T[k] or 0) end
  stats.claims = stats.claims + #(T.claims or {})
  for _, e in ipairs(T.events) do local k = e:match("^(%S+)"); stats.events[k] = (stats.events[k] or 0) + 1 end
  for k, n in pairs(T.status or {}) do stats.status[k] = (stats.status[k] or 0) + n end
  if #T.fail > 0 then
    g.failed = g.failed + 1
    stats.failed = stats.failed + 1
    failures[#failures + 1] = { idx = idx, seed = seed, game = label, n = T.n, fail = T.fail, events = T.events }
    print(string.format("FAIL table %d seed %d %s (%s players): %s", idx, seed, label, tostring(T.n), T.fail[1]))
    if VERBOSE then for i = 2, #T.fail do print("   " .. T.fail[i]) end; print("   events: " .. table.concat(T.events, "; ")) end
  elseif VERBOSE then
    print(string.format("ok table %d %s n=%s steps=%s conv=%s events: %s", idx, label, tostring(T.n), tostring(T.steps), tostring(T.conv), table.concat(T.events, "; ")))
  end
end
print(string.format("\n%d tables, %d checks, %d failed, %.1f s (seed %d%s%s)", stats.tables, stats.checks, stats.failed,
  os.clock() - t0, SEED, ONLY and (", " .. ONLY) or "", WIRE and ", wire" or ""))
for _, k in ipairs(sortedKeys(stats.byGame)) do
  local g = stats.byGame[k]
  print(string.format("  %-22s %4d tables, %d failed", k, g.n, g.failed))
end
local ev = {}
for _, k in ipairs(sortedKeys(stats.events)) do ev[#ev + 1] = k .. "=" .. stats.events[k] end
print("  disruptions: " .. table.concat(ev, " "))
local st = {}
for _, k in ipairs(sortedKeys(stats.status)) do st[#st + 1] = k .. "=" .. stats.status[k] end
print("  debts: " .. table.concat(st, " ") .. "; bad hands (explained) " .. stats.bad)
print(string.format("  host claims by silence %d; settlements only a fork saw %d, hands that differ on a fork %d", stats.claims, stats.forks, stats.handForks))
print(string.format("  known gaps (not failures): results with no R (the host died before its entry went out) %d,", stats.noR))
print(string.format("    debts no claim exists for (the creditor never applied the event: cut off or crashed) %d,", stats.away))
print(string.format("    clients whose own entries wait for their \"mine\" after a crash (balances not compared) %d", stats.unHeld))
if #failures > 0 then
  print("\nFailures (rerun one: SOAK_VERBOSE=1 luajit tools/sim/e2e_soak.lua 1 <seed> <game>; the seed below is table seed):")
  for _, f in ipairs(failures) do
    print(string.format("- table %d %s: luajit tools/sim/e2e_soak.lua 1 %d %s one %s%s", f.idx, f.game, f.seed,
      f.game:match("^bots") and "bots" or (f.game:match("^holdem/staked") and "cash" or f.game:match("^[^/]+")),
      f.game:match("staked") and "staked" or "fun", WIRE and " wire" or ""))
    for i = 1, math.min(#f.fail, 6) do print("    " .. f.fail[i]) end
    print("    events: " .. table.concat(f.events, "; "))
  end
end
os.exit(stats.failed == 0 and 0 or 1)
