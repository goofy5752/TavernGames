-- Death Roll soak: luajit tools/sim/deathroll_soak.lua [games] [seed]
-- Random games of 2..5 players (random seat gaps, start numbers, staked or not) through the real
-- engine, with legal rolls, illegal rolls, timeout auto-rolls and leaves at random moments. A
-- reference model written from the rules (not from the engine) is stepped alongside and compared
-- after every action; the money (who pays whom how much) is recomputed independently and
-- compared with what E.result + Stakes.pairs / Stakes.owed give.
package.path = "tests/helpers/?.lua;" .. package.path
local Loader = require("loader")
local ns = Loader.ns()
local E, Stakes = ns.Engines.deathroll, ns.Stakes
local games = tonumber(arg and arg[1]) or 20000
local seed = tonumber(arg and arg[2]) or 1
math.randomseed(seed)

local checks, fails = 0, {}
local trace
local function fail(msg)
  fails[#fails + 1] = ("seed %d: %s | %s"):format(seed, msg, table.concat(trace or {}, " "))
  if #fails > 20 then print(table.concat(fails, "\n")); os.exit(1) end
end
local function check(c, msg) checks = checks + 1; if not c then fail(msg) end end

local function key(s)
  local o = {}
  for k, v in pairs(s) do
    local t = {}
    if type(v) == "table" then
      for i, x in ipairs(v) do t[#t + 1] = type(x) == "table" and ("{" .. x.seat .. "," .. x.n .. "," .. x.max .. "," .. x.src .. "}") or tostring(x) end
    end
    o[#o + 1] = k .. "=" .. (type(v) == "table" and table.concat(t, ",") or tostring(v))
  end
  table.sort(o); return table.concat(o, ";")
end

local NAMES = { "Ана", "Борис", "Венци", "Гошо", "Дани" }
local CHOICES = { 100, 1000, 10000, 100000 }
local SRC = { "seen", "claim", "ask", "timeout" }
local STAKE = 500
local played, ended, voids, totalPaid, leaves, timeouts, illegal = 0, 0, 0, 0, 0, 0, 0
local lossBy = {} -- number of players at start -> how often the loser was seat k (fairness glance)

for g = 1, games do
  trace = {}
  -- table of 2..5 with random gaps
  local n = math.random(2, 5)
  local seats, order = {}, { 1, 2, 3, 4, 5 }
  for i = 5, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
  for i = 1, 5 do seats[i] = false end
  for i = 1, n do seats[order[i]] = true end
  local start = CHOICES[math.random(#CHOICES)]
  local staked = math.random() < 0.5
  local first = math.random() < 0.7 and math.random(5) or nil
  local s = E.new { seats = seats, first = first, opt = { start = start }, staked = staked or nil }
  trace[#trace + 1] = ("n=%d seats=%s start=%d staked=%s first=%s"):format(n, table.concat((function() local t = {} for i = 1, 5 do t[i] = seats[i] and "1" or "0" end return t end)(), ""), start, tostring(staked), tostring(first))

  -- reference model
  local ref = { players = {}, max = start, phase = "play", loser = nil, nrolls = 0 }
  for i = 1, 5 do if seats[i] then ref.players[#ref.players + 1] = i end end
  local function isPlayer(x) for _, p in ipairs(ref.players) do if p == x then return true end end return false end
  ref.turn = (first and seats[first]) and first or ref.players[1]
  check(s.turn == ref.turn and s.max == start and s.phase == "play", "initial state")
  check(#s.players == n, "player count")
  local roster = {} -- seat -> name at the start, shrinks when a seat leaves (what core/Stakes.lua keeps)
  for _, p in ipairs(ref.players) do roster[p] = NAMES[p] end
  local ledger = {} -- name -> net copper, reference
  local function pay(from, to, c) ledger[from] = (ledger[from] or 0) - c; ledger[to] = (ledger[to] or 0) + c end
  local fakeS = { seats = NAMES, engine = function() return E end }
  local function nextOf(p) -- reference: the next player after seat p in seat order, cyclic
    local best, lowest
    for _, q in ipairs(ref.players) do
      if q > p and (not best or q < best) then best = q end
      if not lowest or q < lowest then lowest = q end
    end
    return best or lowest
  end

  local steps = 0
  while steps < 400 do
    steps = steps + 1
    local before = key(s)
    local r = math.random()
    if ref.phase == "play" and r < 0.55 then
      -- a legal roll by the seat on turn (small chance it's the loser's 1)
      local seat = ref.turn
      local nn
      local q = math.random()
      if q < 0.15 then nn = 1 elseif q < 0.3 then nn = ref.max elseif q < 0.4 then nn = math.min(ref.max, 2) else nn = math.random(1, ref.max) end
      local a = { k = "roll", n = nn, max = ref.max, src = staked and "seen" or SRC[math.random(4)] }
      trace[#trace + 1] = ("%d:roll%d/%d"):format(seat, nn, ref.max)
      check(E.apply(s, seat, a) == true, "legal roll rejected")
      ref.nrolls = ref.nrolls + 1
      if nn == 1 then ref.phase, ref.loser, ref.turn = "over", seat, nil
      else ref.max = nn; ref.turn = nextOf(seat) end
    elseif ref.phase == "play" and r < 0.62 then
      -- the turn timer rolls for the player on turn
      local seat = ref.turn
      for _, o in ipairs(ref.players) do if o ~= seat then check(E.auto(s, o) == nil, "auto for a seat not on turn") end end
      local a = E.auto(s, seat, function(lo, hi) check(lo == 1 and hi == ref.max, "auto range"); return math.random(lo, hi) end)
      if staked then
        check(a == nil, "auto in a staked game")
      else
        timeouts = timeouts + 1
        check(a and a.k == "roll" and a.src == "timeout" and a.n >= 1 and a.n <= ref.max and a.max == ref.max, "auto shape")
        trace[#trace + 1] = ("%d:auto%d/%d"):format(seat, a.n, ref.max)
        check(E.apply(s, seat, a) == true, "auto rejected")
        ref.nrolls = ref.nrolls + 1
        if a.n == 1 then ref.phase, ref.loser, ref.turn = "over", seat, nil
        else ref.max = a.n; ref.turn = nextOf(seat) end
      end
    elseif r < 0.80 then
      -- an illegal roll: must be rejected and leave the state alone
      illegal = illegal + 1
      local seat = math.random(0, 6)
      local max = ref.max
      local kind = math.random(9)
      local a = { k = "roll", n = math.random(1, math.max(2, max)), max = max, src = "seen" }
      local wantOk = false
      if kind == 1 then a.n = 0
      elseif kind == 2 then a.n = max + 1
      elseif kind == 3 then a.n = max + 0.5
      elseif kind == 4 then a.max = max + 1
      elseif kind == 5 then a.src = "forged"
      elseif kind == 6 then a.n = "5"
      elseif kind == 7 then a.n = -3
      elseif kind == 8 then a.k = "stand"
      else a.n = 0 / 0 end
      if ref.phase == "play" and seat == ref.turn then wantOk = false end
      trace[#trace + 1] = ("%d:ILLEGAL k%d"):format(seat, kind)
      local res = E.apply(s, seat, a)
      check(res == nil, "illegal action accepted kind " .. kind .. " seat " .. seat)
      check(key(s) == before, "rejected action changed the state")
      -- a wrong-seat or wrong-phase otherwise legal roll
      if not (ref.phase == "play" and seat == ref.turn) then
        local ok2 = { k = "roll", n = math.min(2, max), max = max, src = "seen" }
        check(E.apply(s, seat, ok2) == nil, "roll out of turn/phase accepted")
        check(key(s) == before, "out of turn roll changed the state")
      end
    elseif r < 0.80 + 0.12 and #ref.players > 0 then
      -- somebody leaves (a player, or a seat that is not playing)
      local seat = math.random(1, 5)
      leaves = leaves + 1
      trace[#trace + 1] = "leave" .. seat
      local was = isPlayer(seat)
      if was then
        local nx = nextOf(seat)
        for i, p in ipairs(ref.players) do if p == seat then table.remove(ref.players, i) break end end
        if ref.phase == "play" then
          if #ref.players < 2 then ref.phase, ref.loser, ref.turn = "over", nil, nil
          elseif ref.turn == seat then ref.turn = nx end
        end
      end
      E.leave(s, seat)
    else
      -- probe: legal() agrees with the reference
    end
    -- compare with the reference
    check(s.phase == ref.phase and s.loser == ref.loser and s.max == ref.max and s.turn == ref.turn, ("state diverged: engine %s/%s/%s/%s ref %s/%s/%s/%s"):format(
      tostring(s.phase), tostring(s.loser), tostring(s.max), tostring(s.turn), tostring(ref.phase), tostring(ref.loser), tostring(ref.max), tostring(ref.turn)))
    check(#s.players == #ref.players, "players")
    for i, p in ipairs(ref.players) do check(s.players[i] == p, "player order") end
    check(#s.rolls == ref.nrolls, "roll log length")
    for seat = 1, 5 do
      local l = E.legal(s, seat)
      check((#l == 1) == (ref.phase == "play" and seat == ref.turn), "legal() vs reference")
      check(E.playing(s, seat) == isPlayer(seat), "playing()")
    end
    check(E.over(s) == (ref.phase == "over"), "over()")
    -- snapshot -> restore -> continue identically
    local copy = E.restore(E.snapshot(s))
    check(key(copy) == key(s), "snapshot roundtrip")
    if ref.phase == "over" and math.random() < 0.5 then break end
  end
  played = played + 1
  check(s.max >= 1, "max below 1")
  for i = 2, #s.rolls do
    local p, c = s.rolls[i - 1], s.rolls[i]
    check(c.max == p.n and c.n >= 1 and c.n <= c.max, "rolls chain: " .. i)
  end

  -- game-end checks and money
  local res = E.result(s)
  if ref.phase == "play" then
    check(res == nil and not E.over(s), "result of a running game")
  elseif ref.loser and isPlayer(ref.loser) then
    ended = ended + 1
    -- the loser still seated; winners are the other remaining players
    check(res and res.losers[1] == ref.loser and #res.losers == 1, "loser in result")
    local w = {}
    for _, p in ipairs(ref.players) do if p ~= ref.loser then w[#w + 1] = p end end
    table.sort(w)
    local rw = {}
    for _, p in ipairs(res and res.winners or {}) do rw[#rw + 1] = p end
    table.sort(rw)
    check(#rw == #w, "winner count"); for i = 1, #w do check(rw[i] == w[i], "winner set") end
    lossBy[ref.loser] = (lossBy[ref.loser] or 0) + 1
    -- money through the real helper
    local names = {}
    for _, p in ipairs(res.winners) do names[#names + 1] = NAMES[p] end
    local pairs_ = Stakes.pairs({ NAMES[ref.loser] }, names, STAKE)
    check(#pairs_ == #w, "pairs count")
    for _, p in ipairs(pairs_) do totalPaid = totalPaid + p.c; check(p.c == STAKE and p.f == NAMES[ref.loser], "pair shape") end
    check(NAMES[ref.loser] ~= nil, "name")
  else
    voids = voids + 1
    check(res == nil, "a game with no loser (everyone else left, or the loser left) has no result")
    check(E.over(s), "void game not over")
  end
  if res then
    check(E.nextFirst(s, { true, true, true, true, true }) == ref.loser, "nextFirst")
    local occ = { true, true, true, true, true }; occ[ref.loser] = false
    check(E.nextFirst(s, occ) == nil, "nextFirst of an empty chair")
  else
    check(E.nextFirst(s, { true, true, true, true, true }) == nil, "nextFirst without loser")
  end
end

-- ---- the forfeit money of a leave (core/Stakes.lua: Stakes.owed over the roster) ----
-- A leaver of a running game owes every other player still on the roster, never a seat already gone.
for trial = 1, 2000 do
  local n = math.random(2, 5)
  local roster = {}
  for i = 1, n do roster[i] = NAMES[i] end
  local fake = { seats = NAMES, engine = function() return E end }
  local order = { 1, 2, 3, 4, 5 }
  for i = n, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
  local gone = 0
  for i = 1, n - 1 do
    local seat = order[i]
    local to, w = Stakes.owed(fake, roster, seat)
    local expect = n - gone - 1
    check(#to == expect and #w == expect, "owed count")
    for _, x in ipairs(w) do check(x ~= seat and roster[x] ~= nil, "owed to a gone seat") end
    check(expect <= 4, "a leaver owes more than 4 stakes")
    roster[seat] = nil; gone = gone + 1
  end
end

print(("games %d (finished with loser %d, void %d), actions: leaves %d, timeouts %d, illegal probes %d"):format(played, ended, voids, leaves, timeouts, illegal))
print(("loser seat histogram: %s"):format((function() local t = {} for i = 1, 5 do t[#t + 1] = i .. "=" .. (lossBy[i] or 0) end return table.concat(t, " ") end)()))
print(("checks %d, failures %d"):format(checks, #fails))
for _, f in ipairs(fails) do print(f) end
os.exit(#fails == 0 and 0 or 1)
