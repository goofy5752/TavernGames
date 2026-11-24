-- Hold'em soak: luajit tools/sim/holdem_soak.lua [hands] [seed] [evalHands] [stakedHands]
-- (run from the repo root; deterministic per seed). Defaults: 20000 hands, seed 1, 1000000 evaluator hands,
-- 5000 staked hands.
--  A. evaluator: random 7 / 6 / 5-card hands (plain and rank/suit-biased decks) against the independent
--     reference (tools/sim/holdem_ref.lua, every 5-card subset): category, H.describe's ranks, the pick, and
--     the order of two hands on one board (sign of the score difference, ties included).
--  B. fun tables of 2-6 random chairs, random stacks, NL/PL, every blind level, played by random legal moves,
--     E.bot (on its own view) and E.auto, with leaves / aways / joins / voids now and then: an independent
--     betting model checks E.legal, every random legal move is taken and every illegal one refused with the
--     state untouched, the turn order, the board's deck positions, the pots (refund, side pots, split, odd
--     chips), the showdown order, chips conserved; snapshot/restore and a twin state; a member's view
--     replica that follows the hand from its own view; every seat's E.view hides what it should.
--  C. staked tables: random buys / rebuys / top-ups / cashouts / stands, the pair matrix of every hand
--     against won - contrib, and per name: gold out of the out-records == chips cashed - chips bought.
package.path = "tests/helpers/?.lua;tools/sim/?.lua;" .. package.path
local Loader = require("loader")
local R = require("holdem_ref")
local ns = Loader.ns()
local E, H = ns.Engines.holdem, ns.HoldemEval

local HANDS = tonumber(arg[1]) or 20000
local SEED = tonumber(arg[2]) or 1
local EVALN = tonumber(arg[3]) or 1000000
local STAKEDN = tonumber(arg[4]) or 5000

local function newRng(seed)
  local x = (seed * 7919) % 2147483646 + 1
  return function(a, b)
    x = x * 16807 % 2147483647
    if not a then return x / 2147483647 end
    return a + x % (b - a + 1)
  end
end

local checks, failures, MAXFAIL = 0, {}, 20
local ctx = ""
local function fail(msg)
  failures[#failures + 1] = ctx .. ": " .. msg
  io.write("FAIL ", ctx, ": ", msg, "\n")
  if #failures >= MAXFAIL then error("too many failures", 0) end
end
local function check(cond, msg) checks = checks + 1; if not cond then fail(msg()) end end

local function ser(v, depth)
  depth = depth or 0
  if type(v) ~= "table" then return tostring(v) end
  if depth > 6 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local t = {}
  for _, k in ipairs(keys) do t[#t + 1] = tostring(k) .. "=" .. ser(v[k], depth + 1) end
  return "{" .. table.concat(t, ",") .. "}"
end
local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, x in pairs(a) do if not deepEq(x, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- ====================================================================== A. evaluator

local function evalSoak(rng, n)
  local FULL = {}
  for _, su in ipairs({ "C", "D", "H", "S" }) do
    for _, r in ipairs({ "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A" }) do FULL[#FULL + 1] = r .. su end
  end
  local function subdeck(ranks, suits)
    local d = {}
    for su in suits:gmatch(".") do for r in ranks:gmatch(".") do d[#d + 1] = r .. su end end
    return d
  end
  local DECKS = { FULL, FULL, subdeck("23456789TJQKA", "CD"), subdeck("A2345678", "CDHS"),
    subdeck("TJQKA9", "CDHS"), subdeck("A2345K", "SH"), subdeck("789TJ", "CDHS") }
  local cats, byCat = {}, {}
  local function draw(deck, k)
    local d = {}
    for i = 1, #deck do d[i] = deck[i] end
    local out = {}
    for i = 1, k do
      local j = rng(i, #d)
      d[i], d[j] = d[j], d[i]
      out[i] = d[i]
    end
    return out
  end
  for g = 1, n do
    ctx = "eval #" .. g
    local deck = DECKS[rng(1, #DECKS)]
    local cards = draw(deck, 9)
    local size = g % 10 == 0 and 6 or g % 10 == 1 and 5 or 7
    local a = {}
    for i = 1, size do a[i] = cards[i] end
    local ref, used = R.best(a)
    local sc, cat, pick = H.best(a)
    cats[ref[1]] = (cats[ref[1]] or 0) + 1
    check(cat == ref[1], function() return table.concat(a, " ") .. " cat " .. tostring(cat) .. " ref " .. ser(ref) end)
    local five = {}
    for k = 1, 5 do five[k] = a[pick[k]] end
    check(R.cmp(R.rank5(five), ref) == 0, function() return table.concat(a, " ") .. " pick not best" end)
    local d = H.describe(a)
    local want = {}
    for k = 2, #ref do want[#want + 1] = ref[k] end
    check(d.cat == ref[1] and deepEq(d.ranks, want) and d.name == H.NAMES[ref[1]],
      function() return table.concat(a, " ") .. " describe " .. ser(d) .. " ref " .. ser(ref) end)
    -- describe of the two hole cards alone
    local hd = H.describe({ a[1], a[2] })
    local r1, r2 = R.RV[a[1]:sub(1, 1)], R.RV[a[2]:sub(1, 1)]
    local hw = r1 == r2 and { cat = 2, ranks = { r1 } } or { cat = 1, ranks = { math.max(r1, r2), math.min(r1, r2) } }
    check(hd.cat == hw.cat and deepEq(hd.ranks, hw.ranks), function() return a[1] .. " " .. a[2] .. " hole describe " .. ser(hd) end)
    -- a second hand on the same board (7-card only): the same order as the reference, ties included
    if size == 7 then
      local b = { cards[8], cards[9], a[3], a[4], a[5], a[6], a[7] }
      local refB = R.best(b)
      local scB = H.best(b)
      local want2 = R.cmp(ref, refB)
      local got = sc > scB and 1 or sc < scB and -1 or 0
      byCat[want2] = (byCat[want2] or 0) + 1
      check(got == want2, function()
        return table.concat(a, " ") .. " vs " .. table.concat(b, " ") .. " engine " .. got .. " ref " .. want2
      end)
    end
  end
  return cats, byCat
end

-- ====================================================================== B/C. tables

local CHAIRS = 9
local function nextCW(from, pred)
  for d = 1, CHAIRS do
    local i = (from + d - 1) % CHAIRS + 1
    if pred(i) then return i end
  end
end

local stats = { hands = 0, showdowns = 0, foldwins = 0, voids = 0, sidepots = 0, splits = 0, oddchips = 0,
  runouts = 0, headsup = 0, pl = 0, illegal = 0, legalTried = 0, views = 0, restores = 0, twins = 0,
  replicas = 0, leaves = 0, joins = 0, aways = 0, bots = 0, autos = 0, randoms = 0, shortAllinRaise = 0,
  reopenDenied = 0, buys = 0, cashouts = 0, stands = 0, outRecs = 0, tables = 0, cat = {} }

-- ---------------------------------------------------------------- the reference betting model

-- T: { s = engine state, rs = {[chair] = {chips, away, leaving, taken, who}}, bb, sb, stack, pl, staked,
--      button, first }
local function playing(T, i) local r = T.rs[i]; return r and r.chips > 0 and not r.leaving and not r.away end

local function refStart(T)
  local button = T.button and nextCW(T.button, function(i) return playing(T, i) end)
    or nextCW(T.first - 1, function(i) return playing(T, i) end)
  local Rh = { order = {}, p = {}, button = button, gone = {}, everUp = {}, boardIdx = {}, street = 0, done = false }
  local i = button
  repeat
    i = nextCW(i, function(x) return playing(T, x) end)
    Rh.order[#Rh.order + 1] = i
  until i == button
  local n = #Rh.order
  Rh.n = n
  for _, seat in ipairs(Rh.order) do T.rs[seat].fresh = nil end
  for j, seat in ipairs(Rh.order) do
    Rh.p[seat] = { bet = 0, total = 0, folded = false, allin = false, acted = false, at = 0, cards = { j, n + j } }
  end
  if n == 2 then Rh.sbSeat, Rh.bbSeat = button, Rh.order[1]        -- heads-up: the button is the small blind
  else Rh.sbSeat, Rh.bbSeat = Rh.order[1], Rh.order[2] end
  local function post(seat, amt)
    local x = math.min(amt, T.rs[seat].chips)
    T.rs[seat].chips = T.rs[seat].chips - x
    local p = Rh.p[seat]
    p.bet, p.total = p.bet + x, p.total + x
    if T.rs[seat].chips == 0 then p.allin = true end
  end
  post(Rh.sbSeat, T.sb); post(Rh.bbSeat, T.bb)
  Rh.curBet, Rh.full, Rh.aggr = T.bb, T.bb, nil      -- a short big blind still makes the call the full blind
  T.button = button
  return Rh
end

local function rLive(Rh, i) local p = Rh.p[i]; return p and not p.folded end
local function rCanAct(Rh, i) local p = Rh.p[i]; return p and not p.folded and not p.allin end
local function rNeeds(Rh, i) local p = Rh.p[i]; return rCanAct(Rh, i) and (not p.acted or p.bet < Rh.curBet) end

-- after a change: fold-win, the round closed, or the next to act (from: search after it; nil keeps the turn)
local function refProgress(Rh, from)
  local nLive, actors = 0, {}
  for _, i in ipairs(Rh.order) do
    if rLive(Rh, i) then nLive = nLive + 1 end
    if rCanAct(Rh, i) then actors[#actors + 1] = i end
  end
  if nLive == 1 then Rh.foldwin, Rh.turn, Rh.closed = true, nil, false; return end
  local closed = true
  if #actors == 1 then                -- alone with chips: nothing to do once he matched every live bet
    local me, maxOther = actors[1], 0
    for _, i in ipairs(Rh.order) do
      if i ~= me and rLive(Rh, i) and Rh.p[i].bet > maxOther then maxOther = Rh.p[i].bet end
    end
    closed = Rh.p[me].bet >= maxOther
  else
    for _, i in ipairs(actors) do if rNeeds(Rh, i) then closed = false end end
  end
  if closed then Rh.turn, Rh.closed = nil, true; return end
  Rh.closed = false
  if from == nil and Rh.turn and rNeeds(Rh, Rh.turn) then return end
  Rh.turn = nextCW(from or Rh.turn, function(i) return rNeeds(Rh, i) end)
end

-- what the seat on turn may do: { toCall, canAgg, minTo, maxTo, allinOK, stackTo }
local function refOptions(T, Rh, seat)
  local p, chips = Rh.p[seat], T.rs[seat].chips
  local o = { toCall = Rh.curBet - p.bet, stackTo = p.bet + chips }
  local other = false
  for _, i in ipairs(Rh.order) do if i ~= seat and rCanAct(Rh, i) then other = true end end
  -- a bet / raise needs chips beyond the call, an opponent with chips, and (having acted) a full raise
  -- faced since (TDA 2015 rule 44, Robert's Rules section 14 no-limit rules 3 and 5)
  local reopened = not p.acted or (Rh.curBet - p.at >= Rh.full)
  o.canAgg = chips > o.toCall and other and reopened
  o.denied = chips > o.toCall and other and not reopened
  o.minTo = Rh.curBet == 0 and T.bb or Rh.curBet + Rh.full
  if T.pl then                         -- pot limit: the call plus the pot after the call
    local pot = 0
    for _, i in ipairs(Rh.order) do pot = pot + Rh.p[i].total end
    local potTo = Rh.curBet + pot + o.toCall
    o.maxTo = math.min(o.stackTo, potTo)
    o.allinOK = o.stackTo <= potTo
  else
    o.maxTo, o.allinOK = o.stackTo, true
  end
  return o
end

local function refLegalList(T, Rh, seat)
  if Rh.turn ~= seat then return {} end
  local o = refOptions(T, Rh, seat)
  local out = { { k = "fold" }, o.toCall > 0 and { k = "call" } or { k = "check" } }
  if o.canAgg then
    if o.minTo < o.maxTo or (o.minTo == o.maxTo and not o.allinOK) then
      out[#out + 1] = { k = Rh.curBet == 0 and "bet" or "raise", to = o.minTo, max = o.maxTo }
    end
    if o.allinOK then out[#out + 1] = { k = "allin" } end
  end
  return out
end

-- is action a legal for the seat (by the rules)? second value: the total `to` of an aggressive action
local function refLegal(T, Rh, seat, a)
  if type(a) ~= "table" or a.need ~= nil then return false end
  if Rh.turn == nil or seat ~= Rh.turn then return false end
  local o = refOptions(T, Rh, seat)
  local k = a.k
  if k == "fold" then return true end
  if k == "check" then return o.toCall == 0 end
  if k == "call" then return o.toCall > 0 end
  if k == "allin" then return o.canAgg and o.allinOK, o.stackTo end
  if k == "bet" or k == "raise" then
    if not o.canAgg then return false end
    if (k == "bet") ~= (Rh.curBet == 0) then return false end
    local to = a.to
    if type(to) ~= "number" or to % 1 ~= 0 then return false end
    return to >= o.minTo and to <= o.maxTo, to
  end
  return false
end

local function refAct(T, Rh, seat, a)
  local p, rs = Rh.p[seat], T.rs[seat]
  local function put(x)
    rs.chips, p.bet, p.total = rs.chips - x, p.bet + x, p.total + x
    if rs.chips == 0 then p.allin = true end
  end
  local _, to = refLegal(T, Rh, seat, a)
  if a.k == "fold" then p.folded = true
  elseif a.k == "call" then put(math.min(Rh.curBet - p.bet, rs.chips))
  elseif a.k ~= "check" then
    put(to - p.bet)
    if to - Rh.curBet >= Rh.full then Rh.full = to - Rh.curBet
    else stats.shortAllinRaise = stats.shortAllinRaise + 1 end
    Rh.curBet, Rh.aggr = to, seat
  end
  p.acted, p.at = true, Rh.curBet
  refProgress(Rh, seat)
end

local function refStreet(T, Rh)
  local n = Rh.n
  if Rh.street == 0 then for _, i in ipairs({ 2 * n + 2, 2 * n + 3, 2 * n + 4 }) do Rh.boardIdx[#Rh.boardIdx + 1] = i end
  elseif Rh.street == 1 then Rh.boardIdx[#Rh.boardIdx + 1] = 2 * n + 6
  else Rh.boardIdx[#Rh.boardIdx + 1] = 2 * n + 8 end    -- a burn card before each street
  Rh.street = Rh.street + 1
  for _, i in ipairs(Rh.order) do local p = Rh.p[i]; p.bet, p.acted, p.at = 0, false, 0 end
  Rh.curBet, Rh.full, Rh.aggr, Rh.turn = 0, T.bb, nil, nil
  refProgress(Rh, Rh.button)          -- postflop the first live seat left of the button (heads-up: the big blind)
end

-- all the hands face up: betting over (between streets / before the showdown), 2+ live, at most one with chips
local function refFaceUp(Rh)
  if not Rh.closed or Rh.done then return {} end
  local up, actors = {}, 0
  for _, i in ipairs(Rh.order) do
    if rLive(Rh, i) then up[#up + 1] = i end
    if rCanAct(Rh, i) then actors = actors + 1 end
  end
  if #up < 2 or actors > 1 then return {} end
  return up
end

-- the hand is over (fold-win, showdown or void): the chips, the record, leavers go, the newcomers sit
local function refFinish(T, Rh, deck, void)
  local total, live = {}, {}
  for _, i in ipairs(Rh.order) do total[i] = Rh.p[i].total; live[i] = rLive(Rh, i) end
  local expect = { won = {}, contrib = {}, shown = {}, cat = {}, left = {}, refund = {} }
  if void then
    for _, i in ipairs(Rh.order) do T.rs[i].chips = T.rs[i].chips + total[i] end
  else
    local refund, pots = R.pots(Rh.order, total, live)
    local scores
    if not Rh.foldwin then
      scores = {}
      for _, i in ipairs(Rh.order) do
        if live[i] then
          local f = {}
          for _, x in ipairs(Rh.boardIdx) do f[#f + 1] = deck[x] end
          for _, x in ipairs(Rh.p[i].cards) do f[#f + 1] = deck[x] end
          scores[i] = R.best(f)
          expect.cat[i] = scores[i][1]
          stats.cat[scores[i][1]] = (stats.cat[scores[i][1]] or 0) + 1
        end
      end
      -- who shows first: the river's last aggressor, else the first live seat left of the button
      local first = (Rh.aggr and live[Rh.aggr]) and Rh.aggr or nextCW(Rh.button, function(x) return live[x] end)
      local i = first
      repeat
        expect.shown[#expect.shown + 1] = i
        i = nextCW(i, function(x) return live[x] end)
      until i == first
    end
    local won = R.award(pots, scores)
    if #pots > 1 then stats.sidepots = stats.sidepots + 1 end
    for _, pot in ipairs(pots) do
      if #pot.winners > 1 then
        stats.splits = stats.splits + 1
        if pot.amount % #pot.winners ~= 0 then stats.oddchips = stats.oddchips + 1 end
      end
    end
    expect.won, expect.refund, expect.pots = won, refund, pots
    for _, i in ipairs(Rh.order) do
      expect.contrib[i] = total[i] - (refund[i] or 0)
      T.rs[i].chips = T.rs[i].chips + (refund[i] or 0) + (won[i] or 0)
    end
  end
  for i = 1, CHAIRS do
    local r = T.rs[i]
    if r and r.leaving then
      expect.left[i] = r.chips
      if not T.staked then T.left = T.left + r.chips end
      if r.taken then
        T.rs[i] = { chips = T.staked and 0 or T.stack, who = r.takenWho }
        if not T.staked then T.injected = T.injected + T.stack end
      else T.rs[i] = nil end
      Rh.gone[i] = true
    end
  end
  Rh.done = true
  Rh.closed = false
  return expect
end

-- ---------------------------------------------------------------- engine-side checks

local function phaseOf(s) return s.phase end

-- every seat's view (and a watcher's) shows exactly the board, its own cards, the shown hands and the hands
-- an all-in turned up
local function checkViews(T, Rh)
  local s = T.s
  local shown = {}
  if Rh.done then for _, i in ipairs(Rh.shownList or {}) do shown[#shown + 1] = i end end
  local up = (s.phase == "street" or s.phase == "showdown") and refFaceUp(Rh) or {}
  check(deepEq(E.faceUp(s), up), function() return "faceUp " .. ser(E.faceUp(s)) .. " ref " .. ser(up) end)
  for seat = 0, CHAIRS do
    for _, dealtOnly in ipairs({ false, true }) do
      if not dealtOnly or #up > 0 then
        local vis = {}
        for _, x in ipairs(Rh.boardIdx) do vis[x] = true end
        for _, i in ipairs(shown) do for _, x in ipairs(Rh.p[i].cards) do vis[x] = true end end
        if not dealtOnly then for _, i in ipairs(up) do for _, x in ipairs(Rh.p[i].cards) do vis[x] = true end end end
        if Rh.p[seat] and not Rh.gone[seat] and Rh.dealt then
          for _, x in ipairs(Rh.p[seat].cards) do vis[x] = true end
        end
        local v = E.view(s, seat, dealtOnly)
        stats.views = stats.views + 1
        local okv = true
        for x in pairs(v.deck) do if not vis[x] or v.deck[x] ~= s.deck[x] then okv = false end end
        for x in pairs(vis) do if v.deck[x] == nil and s.deck[x] ~= nil then okv = false end end
        check(okv, function()
          local got = {}
          for x in pairs(v.deck) do got[#got + 1] = x end
          table.sort(got)
          return "view of seat " .. seat .. (dealtOnly and " (dealt)" or "") .. " shows " .. table.concat(got, ",")
            .. " expected " .. ser(vis)
        end)
      end
    end
  end
end

local function sameTable(T, Rh)
  local s = T.s
  for i = 1, CHAIRS do
    local r, st = T.rs[i], s.seats[i]
    check((r and true or false) == (st and true or false),
      function() return "chair " .. i .. " occupied: ref " .. tostring(r ~= nil) .. " engine " .. tostring(st and true) end)
    if r and st then
      check(r.chips == st.chips, function() return "chair " .. i .. " chips ref " .. r.chips .. " engine " .. st.chips end)
    end
  end
  if Rh and not Rh.done then
    check(s.turn == Rh.turn, function() return "turn engine " .. tostring(s.turn) .. " ref " .. tostring(Rh.turn) end)
    check(s.bet == Rh.curBet, function() return "bet engine " .. tostring(s.bet) .. " ref " .. Rh.curBet end)
    for _, i in ipairs(Rh.order) do
      local p, q = s.p[i], Rh.p[i]
      check(p.bet == q.bet and p.total == q.total and p.folded == q.folded and p.allin == q.allin,
        function() return "seat " .. i .. " engine " .. ser(p) .. " ref " .. ser(q) end)
    end
  end
end

local harvest
local function conserved(T)
  harvest(T)
  local sum = T.left
  for i = 1, CHAIRS do
    local st = T.s.seats[i]
    if st then sum = sum + st.chips end
  end
  if E.inHand(T.s) then for _, i in ipairs(T.s.order) do sum = sum + T.s.p[i].total end end
  if T.staked then
    sum = sum + T.cashedOut
    check(sum == T.bought, function() return "staked chips " .. sum .. " bought " .. T.bought end)
  else
    check(sum == T.injected, function() return "chips " .. sum .. " injected " .. T.injected end)
  end
end

-- ---------------------------------------------------------------- one hand

local SYSTEM_JUNK = { { k = "hand" }, { k = "deal" }, { k = "street" }, { k = "showdown", cards = {} } }

local function shuffle(rng)
  local d = {}
  for i = 1, 52 do d[i] = E.DECK[i] end
  for i = 52, 2, -1 do local j = rng(1, i); d[i], d[j] = d[j], d[i] end
  return d
end

-- the staked out records written since the last look: per name the gold moved and the chips cashed
function harvest(T)
  local cash = T.s.cash
  if not cash then return end
  for _, rec in ipairs(cash.outs) do
    if rec.n > T.outSeen then
      T.outSeen = rec.n
      stats.outRecs = stats.outRecs + 1
      local own = 0
      for j, x in pairs(rec.net) do
        own = own + x
        local other = rec.names[j] or ("?" .. j)
        T.gold[other] = (T.gold[other] or 0) - x
      end
      local who = rec.who or ("?" .. rec.seat)
      T.gold[who] = (T.gold[who] or 0) + own
      T.delta[who] = (T.delta[who] or 0) + rec.chips - rec.bought
      T.leftWith[who] = rec.chips
      T.cashedOut = T.cashedOut + rec.chips
    end
  end
end

local function applyBoth(T, seat, a, rv, twin)
  local okE, why = E.apply(T.s, seat, a)
  if rv then
    local okR, whyR = E.apply(rv.s, seat, a)
    check(okR == okE, function() return "replica " .. ser(a) .. " engine " .. tostring(okE) .. "/" .. tostring(why) .. " replica " .. tostring(okR) .. "/" .. tostring(whyR) end)
  end
  if twin then E.apply(twin, seat, a) end
  return okE, why
end

local function playHand(T, rng)
  local s = T.s
  local log = {}
  T.log = log
  local a0 = E.system(s)
  if not a0 or a0.k ~= "hand" then return false end
  local before = ser(s)
  check(E.apply(s, 0, { k = "street" }) == nil and ser(s) == before, function() return "street before a hand taken" end)
  check(E.apply(s, 0, a0), function() return "hand refused" end)
  local Rh = refStart(T)
  stats.hands = stats.hands + 1
  if Rh.n == 2 then stats.headsup = stats.headsup + 1 end
  if T.pl then stats.pl = stats.pl + 1 end
  check(s.button == Rh.button and s.sbSeat == Rh.sbSeat and s.bbSeat == Rh.bbSeat and deepEq(s.order, Rh.order),
    function() return "button/blinds engine " .. ser({ s.button, s.sbSeat, s.bbSeat, s.order }) .. " ref "
      .. ser({ Rh.button, Rh.sbSeat, Rh.bbSeat, Rh.order }) end)
  sameTable(T, nil)
  conserved(T)
  -- a member's replica: its own view from the deal on (no deck), its own two cards shown to it
  local rv
  if rng(1, 3) == 1 then
    rv = { seat = Rh.order[rng(1, #Rh.order)], s = E.restore(E.snapshot(s)) }
    stats.replicas = stats.replicas + 1
  end
  local twin
  local deck = shuffle(rng)
  check(E.apply(s, 0, { k = "deal", deck = deck }), function() return "deal refused" end)
  Rh.dealt = true
  if rv then
    check(E.apply(rv.s, 0, { k = "deal" }), function() return "replica deal refused" end)
    local own = {}
    for _, x in ipairs(Rh.p[rv.seat].cards) do own[x] = deck[x] end
    check(E.apply(rv.s, 0, { k = "show", cards = own }), function() return "replica show refused" end)
  end
  refProgress(Rh, Rh.bbSeat)        -- preflop: left of the big blind (heads-up: the button)
  if Rh.foldwin then Rh.closed = false end
  local steps, voided = 0, false
  local style = rng(1, 4)           -- 1 random, 2 bots, 3 passive, 4 mixed

  local function replicaSync()
    if not rv then return end
    local up = E.faceUp(rv.s)
    if #up > 0 then                 -- the dealer's seat-0 show of the hands face up (Deal.sync)
      local cards = {}
      for _, i in ipairs(up) do for _, x in ipairs(s.p[i].cards) do cards[x] = s.deck[x] end end
      E.apply(rv.s, 0, { k = "show", cards = cards })
    end
    -- the replica holds what its view shows, plus the hands it was shown face up before a leave folded them
    local vd = E.view(s, rv.seat).deck
    for _, i in ipairs(refFaceUp(Rh)) do Rh.everUp[i] = true end
    local okd = true
    for x, f in pairs(vd) do if rv.s.deck[x] ~= f then okd = false end end
    for x, f in pairs(rv.s.deck) do
      if vd[x] == nil then
        local ofUp = false      -- (or its own hand, once a newcomer took its chair: the chair's view is his now)
        if Rh.gone[rv.seat] then for _, y in ipairs(Rh.p[rv.seat].cards) do if y == x then ofUp = true end end end
        for i in pairs(Rh.everUp) do for _, y in ipairs(Rh.p[i].cards) do if y == x then ofUp = true end end end
        if not ofUp then okd = false else stats.upThenFolded = (stats.upThenFolded or 0) + 1 end
      end
    end
    check(okd, function() return "replica deck " .. ser(rv.s.deck) .. " view " .. ser(vd) end)
    local sa, sb = rv.s.deck, s.deck
    rv.s.deck, s.deck = {}, {}
    local same = deepEq(rv.s, s)
    rv.s.deck, s.deck = sa, sb
    check(same, function() return "replica state differs" end)
  end

  while not Rh.done do
    steps = steps + 1
    if steps > 400 then fail("hand does not end"); break end
    ctx = T.ctx .. " hand " .. s.hand .. " step " .. steps
    if Rh.foldwin then
      Rh.expect = refFinish(T, Rh, deck, false)
      break
    end
    -- now and then a table event in the middle of the hand
    local ev = rng(1, 100)
    if ev <= 2 then                                            -- a seat stands up
      local seat = rng(1, CHAIRS)
      local r = T.rs[seat]
      if r then
        log[#log + 1] = "leave " .. seat
        stats.leaves = stats.leaves + 1
        applyBoth(T, 0, { k = "leave", seat = seat }, rv, twin)
        if Rh.p[seat] then
          if r.leaving then r.taken, r.takenWho = nil, nil
          else
            r.leaving = true
            if not Rh.p[seat].folded then
              Rh.p[seat].folded = true
              refProgress(Rh, Rh.turn == seat and seat or nil)
            end
          end
        else T.rs[seat] = nil; if not T.staked then T.left = T.left + r.chips end end
      end
    elseif ev == 3 then                                        -- someone sits down
      local seat = rng(1, CHAIRS)
      local r = T.rs[seat]
      local who = T.staked and T.names[rng(1, #T.names)] or nil
      for j = 1, CHAIRS do if who and T.rs[j] and (T.rs[j].who == who or T.rs[j].takenWho == who) then who = false end end
      local okJ = false              -- staked: a name already at the table does not sit twice (the core's rule)
      if who ~= false then
        okJ = applyBoth(T, 0, { k = "join", seat = seat, who = who }, rv, twin)
        local want = ((not r) or (r.leaving and not r.taken and Rh.p[seat] ~= nil)) and true or false
        check((okJ and true or false) == want, function() return "join of chair " .. seat .. " " .. tostring(okJ) .. " ref " .. ser(r) .. " eng " .. ser(T.s.seats[seat]) .. " " .. T.s.phase end)
      end
      if okJ then
        log[#log + 1] = "join " .. seat
        stats.joins = stats.joins + 1
        if not r then
          T.rs[seat] = { chips = T.staked and 0 or T.stack, who = who }
          if not T.staked then T.injected = T.injected + T.stack end
        else r.taken, r.takenWho = true, who; Rh.gone[seat] = true end
      end
    elseif ev == 4 then                                        -- a seat is sat out
      local seat = rng(1, CHAIRS)
      local r = T.rs[seat]
      local okA = applyBoth(T, 0, { k = "away", seat = seat }, rv, twin)
      check((okA and true or false) == (r ~= nil and not r.away), function() return "away " .. seat end)
      if okA then
        log[#log + 1] = "away " .. seat
        stats.aways = stats.aways + 1
        r.away = true
        if Rh.p[seat] and not Rh.p[seat].folded then
          Rh.p[seat].folded = true
          refProgress(Rh, Rh.turn == seat and seat or nil)
        end
      end
    elseif ev == 5 and rng(1, 10) == 1 then                    -- the hand is voided
      log[#log + 1] = "void"
      check(applyBoth(T, 0, { k = "void" }, rv, twin), function() return "void refused" end)
      stats.voids = stats.voids + 1
      voided = true
      local expect = refFinish(T, Rh, deck, true)
      Rh.expect = expect
      break
    end
    if Rh.foldwin then
      Rh.expect = refFinish(T, Rh, deck, false)
      break
    end
    if rng(1, 20) == 1 then                                    -- snapshot -> restore -> play on
      local snap = E.snapshot(s)
      local back = E.restore(snap)
      check(deepEq(back, s), function() return "restore differs" end)
      T.s, s = back, back
      stats.restores = stats.restores + 1
    end
    if not twin and rng(1, 30) == 1 then twin = E.restore(E.snapshot(s)); stats.twins = stats.twins + 1 end
    if steps % 3 == 1 then checkViews(T, Rh) end
    replicaSync()
    sameTable(T, Rh)
    conserved(T)
    if Rh.closed then
      -- between streets / the showdown: the engine must want the next step, from the right deck positions
      local a = E.system(s)
      local want = Rh.street == 3 and "showdown" or "street"
      check(s.phase == want and a and a.k == want, function() return "phase " .. s.phase .. " system " .. ser(a) .. " want " .. want end)
      if not a then break end
      if #refFaceUp(Rh) > 0 and Rh.street < 3 and not Rh.countedRunout then
        Rh.countedRunout = true; stats.runouts = stats.runouts + 1
      end
      if rv then
        local va = E.system(rv.s)
        local holeKnown = true
        if a.k == "street" then
          check(va and va.need == "faces", function() return "replica system " .. ser(va) end)
        end
      end
      if a.k == "street" then
        local want = {}
        local n = Rh.n
        local idx = Rh.street == 0 and { 2 * n + 2, 2 * n + 3, 2 * n + 4 } or { Rh.street == 1 and 2 * n + 6 or 2 * n + 8 }
        for _, x in ipairs(idx) do want[x] = deck[x] end
        check(deepEq(a.cards, want), function() return "street cards " .. ser(a.cards) .. " want " .. ser(want) end)
        check(applyBoth(T, 0, a, rv, twin), function() return "street refused" end)
        refStreet(T, Rh)
        if Rh.foldwin then Rh.closed = false end
      else
        check(applyBoth(T, 0, a, rv, twin), function() return "showdown refused" end)
        Rh.expect = refFinish(T, Rh, deck, false)
        Rh.shownList = Rh.expect.shown
      end
    else
      local seat = Rh.turn
      check(s.phase == "bet" and s.turn == seat, function() return "turn engine " .. tostring(s.turn) .. " " .. s.phase .. " ref " .. tostring(seat) end)
      if s.turn ~= seat then break end
      local legal = E.legal(s, seat)
      local want = refLegalList(T, Rh, seat)
      check(deepEq(legal, want), function() return "legal engine " .. ser(legal) .. " ref " .. ser(want) end)
      local o = refOptions(T, Rh, seat)
      if o.denied then stats.reopenDenied = stats.reopenDenied + 1 end
      -- illegal and legal tries: refused ones leave the state untouched, accepted ones agree with the rules
      local snap = E.snapshot(s)
      local cands = {}
      local function X() local c = { o.minTo - 1, o.minTo, o.maxTo, o.maxTo + 1, o.stackTo, rng(0, o.stackTo + 5), o.minTo + 0.5 }; return c[rng(1, #c)] end
      for _ = 1, 4 do
        local kinds = { "fold", "check", "call", "bet", "raise", "allin", "dance" }
        cands[#cands + 1] = { k = kinds[rng(1, #kinds)], to = X() }
      end
      cands[#cands + 1] = { k = "raise" }
      cands[#cands + 1] = { k = "call", need = "deck" }
      for _, c in ipairs(cands) do
        local legalR = refLegal(T, Rh, seat, c)
        if legalR then
          local cp = E.restore(snap)
          local okC, why = E.apply(cp, seat, c)
          stats.legalTried = stats.legalTried + 1
          check(okC, function() return "legal " .. ser(c) .. " refused: " .. tostring(why) end)
        else
          local okC = E.apply(s, seat, c)
          stats.illegal = stats.illegal + 1
          check(not okC and deepEq(s, snap), function() return "illegal " .. ser(c) .. " taken or state changed" end)
          if okC then T.s = E.restore(snap); s = T.s end
        end
      end
      local other = nextCW(seat, function(i) return i ~= seat end)
      local wrong = { k = legal[rng(1, #legal)].k, to = o.minTo }
      check(not E.apply(s, other, wrong) and not E.apply(s, 0, wrong) and deepEq(s, snap), function() return "out of turn taken" end)
      local junk = SYSTEM_JUNK[rng(1, #SYSTEM_JUNK)]
      check(not E.apply(s, 0, junk) and deepEq(s, snap), function() return "system " .. junk.k .. " taken while betting" end)
      stats.illegal = stats.illegal + 3
      -- the move
      local a
      local pick = style == 4 and rng(1, 3) or style
      if pick == 2 or (pick == 3 and rng(1, 4) == 1) then
        local view = E.view(s, seat)
        a = E.bot(view, seat, rng)
        stats.bots = stats.bots + 1
      elseif pick == 3 then
        a = E.auto(s, seat)
        if a.k == "fold" and rng(1, 3) > 1 then a = { k = "call" } end
        stats.autos = stats.autos + 1
      end
      if not a or rng(1, 10) == 1 then
        if rng(1, 15) == 1 then a = E.auto(s, seat); stats.autos = stats.autos + 1
        else
          local l = legal[rng(1, #legal)]
          a = { k = l.k }
          if l.to then
            local r = rng(1, 4)
            a.to = r == 1 and l.to or r == 2 and l.max or rng(l.to, l.max)
          end
          stats.randoms = stats.randoms + 1
        end
      end
      check(refLegal(T, Rh, seat, a), function() return "chosen move not legal by the rules: " .. ser(a) end)
      log[#log + 1] = seat .. ":" .. a.k .. (a.to and (" " .. a.to) or "")
      local okM, why = applyBoth(T, seat, a, rv, twin)
      check(okM, function() return "move " .. ser(a) .. " refused: " .. tostring(why) end)
      if not okM then break end
      refAct(T, Rh, seat, a)
      if Rh.foldwin then Rh.closed = false end
    end
  end
  if not Rh.expect then return true end
  -- the hand is over: compare the record and every chair
  ctx = T.ctx .. " hand " .. s.hand .. " end"
  harvest(T)
  local ex, L = Rh.expect, s.last
  check(s.phase == "done" or s.phase == "closed", function() return "phase after the hand " .. s.phase end)
  if voided then
    check(L.void == true, function() return "void record" end)
  else
    if Rh.foldwin then stats.foldwins = stats.foldwins + 1 else stats.showdowns = stats.showdowns + 1 end
    local won = {}
    for i, x in pairs(L.won) do if x ~= 0 then won[i] = x end end
    local wwon = {}
    for i, x in pairs(ex.won) do if x ~= 0 then wwon[i] = x end end
    check(deepEq(won, wwon), function() return "won engine " .. ser(L.won) .. " ref " .. ser(ex.won) .. " pots " .. ser(L.pots) .. " ref pots " .. ser(ex.pots) end)
    check(deepEq(L.contrib, ex.contrib), function() return "contrib engine " .. ser(L.contrib) .. " ref " .. ser(ex.contrib) end)
    check(deepEq(L.shown, ex.shown), function() return "shown engine " .. ser(L.shown) .. " ref " .. ser(ex.shown) end)
    check(deepEq(L.cat, ex.cat), function() return "cat engine " .. ser(L.cat) .. " ref " .. ser(ex.cat) end)
    local sw, sc = 0, 0
    for _, x in pairs(L.won) do sw = sw + x end
    for _, x in pairs(L.contrib) do sc = sc + x end
    check(sw == sc, function() return "sum(won) " .. sw .. " ~= sum(contrib) " .. sc end)
    if L.took then                                          -- staked: the pair matrix of the hand
      for _, i in ipairs(Rh.order) do
        local net = 0
        for j, x in pairs(L.took[i] or {}) do net = net + x end
        for w, row in pairs(L.took) do net = net - (row[i] or 0) end
        check(net == (L.won[i] or 0) - (L.contrib[i] or 0),
          function() return "took of seat " .. i .. " " .. net .. " ~= won - contrib" end)
      end
    end
  end
  check(deepEq(L.left, ex.left), function() return "left engine " .. ser(L.left) .. " ref " .. ser(ex.left) end)
  sameTable(T, nil)
  conserved(T)
  checkViews(T, Rh)
  if rv then
    local sa, sb = rv.s.deck, s.deck
    rv.s.deck, s.deck = {}, {}
    check(deepEq(rv.s, s), function() return "replica after the hand differs" end)
    rv.s.deck, s.deck = sa, sb
  end
  if twin then check(deepEq(twin, s), function() return "twin differs" end) end
  T.lastRh = Rh
  return true
end

-- ---------------------------------------------------------------- tables

local BLINDS = { 10, 20, 50, 100, 200 }
local NAMES = { "Ivan", "Maria", "Petar", "Gosho", "Kiro", "Nadya", "Toni", "Lili", "Zhoro", "Vanya", "Mitko" }

local function randStack(rng, bb)
  local r = rng(1, 10)
  if r <= 2 then return rng(1, 3 * bb) end
  if r <= 7 then return rng(bb, 60 * bb) end
  return rng(60 * bb, 300 * bb)
end

local function newTable(rng, id, staked)
  local nSeats = rng(2, 6)
  local seats, chairs = {}, {}
  while #chairs < nSeats do
    local c = rng(1, CHAIRS)
    if not seats[c] then seats[c] = true; chairs[#chairs + 1] = c end
  end
  local opt = { betting = rng(1, 2) == 1 and "nl" or "pl", blinds = BLINDS[rng(1, 5)], stack = ({ 50, 100, 200 })[rng(1, 3)],
    rebuy = ({ "none", "bust", "top" })[rng(1, 3)] }
  local first = rng(1, CHAIRS)
  local names = {}
  if staked then for _, c in ipairs(chairs) do names[c] = NAMES[c] end end
  local s = E.new({ seats = seats, first = first, opt = opt, staked = staked, names = names })
  local T = { s = s, rs = {}, bb = s.bb, sb = s.sb, stack = s.stack, pl = s.betting == "pl", staked = staked,
    first = first, injected = 0, left = 0, ctx = "table " .. id, bought = 0, cashedOut = 0, gold = {}, delta = {},
    outSeen = 0, names = NAMES, rebuy = opt.rebuy, leftWith = {} }
  for _, c in ipairs(chairs) do
    if staked then
      T.rs[c] = { chips = 0, who = names[c] }
    else
      local chips = randStack(rng, s.bb)
      s.seats[c].chips = chips
      T.rs[c] = { chips = chips }
      T.injected = T.injected + chips
    end
  end
  return T
end

-- between hands at a fun table: busted seats stand, empty chairs fill, aways come back
local function betweenFun(T, rng)
  local s = T.s
  for i = 1, CHAIRS do
    local r = T.rs[i]
    if r and r.chips == 0 and rng(1, 3) == 1 then
      check(E.apply(s, 0, { k = "leave", seat = i }), function() return "stand refused" end)
      T.rs[i] = nil
    elseif r and r.away and rng(1, 2) == 1 then
      check(E.apply(s, i, { k = "back" }), function() return "back refused" end)
      r.away = false
    elseif not r and rng(1, 12) == 1 then
      check(E.apply(s, 0, { k = "join", seat = i }), function() return "join refused" end)
      local chips = rng(1, 2) == 1 and s.stack or randStack(rng, T.bb)
      s.seats[i].chips = chips
      T.rs[i] = { chips = chips }
      T.injected = T.injected + chips
    end
  end
end

-- rule 20 between hands, read from the rule text: what the seat may buy -> lo, hi | nil, code
local function refRange(T, r)
  local min, max = 40 * T.bb, 100 * T.bb
  if (r.bought or 0) == 0 then
    local back = r.who and T.leftWith[r.who]
    if back == 0 and T.rebuy == "none" then return nil, "rebuy" end
    return math.max(min, math.min(back or 0, max)), max
  end
  if T.rebuy == "none" or (T.rebuy == "bust" and r.chips > 0) then return nil, "rebuy" end
  if r.chips == 0 then return min, max end
  if r.chips < max then return 1, max - r.chips end
  return nil, "full"
end

-- for every seat that bought: sum of its pair nets with the occupied seats == chips - bought - cleared
local function pairBalance(T)
  local s = T.s
  for i = 1, CHAIRS do
    local st = s.seats[i]
    if st and st.bought > 0 then
      local n = 0
      for j = 1, CHAIRS do if j ~= i and s.seats[j] then n = n + ns.HoldemCash.net(s.cash, i, j) end end
      check(n == st.chips - st.bought - st.cleared, function() return "pair balance of chair " .. i .. " " .. n
        .. " ~= " .. st.chips .. " - " .. st.bought .. " - " .. st.cleared end)
    end
  end
end

-- between hands at a staked table: buys, cashouts, stands, sits
local function betweenStaked(T, rng)
  local s = T.s
  pairBalance(T)
  for i = 1, CHAIRS do
    local r = T.rs[i]
    ctx = T.ctx .. " between, chair " .. i
    if r then
      local x = rng(1, 10)
      local lo, hi = E.buyRange(s, i)
      local rlo, rhi = refRange(T, r)
      check(lo == rlo and hi == rhi, function() return "buy range " .. tostring(lo) .. ".." .. tostring(hi) .. " ref "
        .. tostring(rlo) .. ".." .. tostring(rhi) .. " " .. ser(r) end)
      if x <= 5 and lo then
        local n = rng(1, 6) == 1 and hi + 1 or rng(lo, hi)
        local okB = E.apply(s, i, { k = "buy", n = n })
        check((okB and true or false) == (n <= hi), function() return "buy " .. n .. " in " .. lo .. ".." .. hi end)
        if okB then
          if (r.bought or 0) == 0 then r.fresh = true end
          r.chips, r.bought = r.chips + n, (r.bought or 0) + n; T.bought = T.bought + n; stats.buys = stats.buys + 1
        end
      elseif x == 6 then
        local okC = E.apply(s, i, { k = "cashout" })
        local wantC = (r.bought or 0) > 0 and not r.fresh      -- no cashout before a hand dealt it in since its buy
        check((okC and true or false) == wantC, function() return "cashout " .. tostring(okC) .. " ref " .. tostring(wantC) end)
        if okC then r.chips, r.bought = 0, 0; stats.cashouts = stats.cashouts + 1 end
        harvest(T)
      elseif x == 7 and rng(1, 3) == 1 then
        check(E.apply(s, 0, { k = "leave", seat = i }), function() return "stand refused" end)
        T.rs[i] = nil
        stats.stands = stats.stands + 1
        harvest(T)
      elseif r.away and x == 8 then
        E.apply(s, i, { k = "back" }); r.away = false
      end
    elseif rng(1, 6) == 1 then
      local who = NAMES[rng(1, #NAMES)]
      local taken = false
      for j = 1, CHAIRS do if T.rs[j] and T.rs[j].who == who then taken = true end end
      if not taken then
        check(E.apply(s, 0, { k = "join", seat = i, who = who }), function() return "join refused" end)
        T.rs[i] = { chips = 0, who = who }
      end
    end
  end
  harvest(T)
end

local function runTables(rng, total, staked)
  local played, id = 0, 0
  while played < total do
    id = id + 1
    stats.tables = stats.tables + 1
    local T = newTable(rng, (staked and "S" or "F") .. id, staked)
    if staked then betweenStaked(T, rng) end
    local hands = rng(5, 60)
    local idle = 0
    for _ = 1, hands do
      ctx = T.ctx
      local okH, err = pcall(playHand, T, rng)
      if not okH then
        if err == "too many failures" then error(err, 0) end
        fail("error: " .. tostring(err) .. " log " .. table.concat(T.log or {}, " | "))
        break
      end
      if err then played = played + 1; idle = 0 else idle = idle + 1 end
      if staked then betweenStaked(T, rng) else betweenFun(T, rng) end
      if idle > 20 then break end
      if played >= total then break end
    end
    ctx = T.ctx .. " close"
    E.apply(T.s, 0, { k = "close" })
    if E.inHand(T.s) then
      check(false, function() return "close in a hand" end)
    end
    harvest(T)
    if staked then
      conserved(T)
      for name, g in pairs(T.gold) do
        check(g == (T.delta[name] or 0), function() return "gold of " .. name .. " " .. g .. " ~= chips cashed - bought " .. tostring(T.delta[name]) end)
      end
      for name, d in pairs(T.delta) do
        check((T.gold[name] or 0) == d, function() return "gold of " .. name .. " missing" end)
      end
    end
  end
end

-- ====================================================================== main

local t0 = os.clock()
local rng = newRng(SEED)
local okRun, err = pcall(function()
  local cats, order = evalSoak(rng, EVALN)
  io.write(string.format("evaluator: %d hands, categories %s, pair order (>/=/<) %d/%d/%d  [%.1fs]\n", EVALN,
    ser(cats), order[1] or 0, order[0] or 0, order[-1] or 0, os.clock() - t0))
  runTables(rng, HANDS, false)
  io.write(string.format("fun tables done [%.1fs]\n", os.clock() - t0))
  runTables(rng, STAKEDN, true)
end)
if not okRun then io.write("stopped: ", tostring(err), "\n") end
io.write(string.format("seed %d: %d checks, %d failures [%.1fs]\n", SEED, checks, #failures, os.clock() - t0))
io.write(ser(stats), "\n")
os.exit(#failures == 0 and okRun and 0 or 1)
