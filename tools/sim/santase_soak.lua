-- Сантасе soak: plays many whole matches on engines/santase.lua and checks every step against an
-- independent reference written from the rules (bg.wikipedia "Сантасе", pagat.com "Sixty-six",
-- belot.bg santase rules, and the help text help.santase.* the players are shown).
--
--   luajit tools/sim/santase_soak.lua [matches] [seed] [e2e]     (from the repository root)
--
-- matches: engine-level matches to 11 (default 5000, about 43 000 hands, ~3.5 min); seed: master seed (default 1); e2e: staked
-- matches played end to end through tests/helpers/sim.lua + play.lua (default 0).
--
-- Checks per step: the engine's legal set equals the reference's; every legal action is accepted;
-- every other candidate (each card face, each marriage, the swap, the close, wrong seat, wrong
-- face, malformed) is refused and leaves the state byte-identical; hands/stock/trick/points/
-- tricks/marriages/turn/dealer/closing equal the reference; 24 cards are conserved; auto is the
-- lowest-value legal card; no view (seat 1, seat 2, watcher) holds a card face it may not see.
-- Per hand: winner, game points and reason equal the reference; the hand ends in at most 12
-- tricks. Per match: snapshot -> restore -> replay gives the identical final state; the result is
-- the reference's; one match in VIEWEVERY is also played on the three views in step (the
-- network path) and every view must agree with the full state.
package.path = "tests/helpers/?.lua;" .. package.path
Loader = require("loader")
local NS = Loader.ns()
local E = NS.Engines.santase

local MATCHES = tonumber(arg[1]) or 5000
local SEED = tonumber(arg[2]) or 1
local E2E = tonumber(arg[3]) or 0
local VIEWEVERY = 10

------------------------------------------------------------------ random
local function rng(seed)
  local x = (seed % 2147483646) + 1
  return function(lo, hi)
    x = (x * 16807) % 2147483647
    return lo + x % (hi - lo + 1)
  end
end

------------------------------------------------------------------ helpers
local function ser(v, out)
  out = out or {}
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) < type(b)
    end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
      out[#out + 1] = tostring(k); out[#out + 1] = "="; ser(v[k], out); out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = (t == "string") and ("'" .. v .. "'") or tostring(v)
  end
  return out
end
local function S(v) return table.concat(ser(v)) end

local FACES = {}
for _, su in ipairs({ "C", "D", "H", "S" }) do
  for _, r in ipairs({ "9", "J", "Q", "K", "T", "A" }) do FACES[#FACES + 1] = r .. su end
end
local ISFACE = {}
for _, f in ipairs(FACES) do ISFACE[f] = true end

------------------------------------------------------------------ the reference (from the rules)
-- Card points and strength: A 11, 10 10, K 4, Q 3, J 2, 9 0; strength A > 10 > K > Q > J > 9.
local PTS = { A = 11, T = 10, K = 4, Q = 3, J = 2, ["9"] = 0 }
local STR = { A = 6, T = 5, K = 4, Q = 3, J = 2, ["9"] = 1 }
local function R_(f) return f:sub(1, 1) end
local function U_(f) return f:sub(2, 2) end

local Ref = {}
Ref.__index = Ref

function Ref.new(first)
  return setmetatable({ dealer = 3 - first, gp = { 0, 0 }, phase = "deal" }, Ref)
end

function Ref:deal(deck)
  -- The documented deal contract: deck[1..3] and [7..9] to the non-dealer, [4..6] and [10..12]
  -- to the dealer, deck[13] the face-up trump card at the bottom of the stock, drawn last.
  local non, dl = 3 - self.dealer, self.dealer
  self.hands = { {}, {} }
  for i = 1, 3 do self.hands[non][deck[i]] = true end
  for i = 4, 6 do self.hands[dl][deck[i]] = true end
  for i = 7, 9 do self.hands[non][deck[i]] = true end
  for i = 10, 12 do self.hands[dl][deck[i]] = true end
  self.trumpCard, self.tsuit = deck[13], U_(deck[13])
  self.stock = {}
  for i = 14, 24 do self.stock[#self.stock + 1] = deck[i] end
  self.stock[#self.stock + 1] = deck[13]
  self.closed, self.oppHadTrick = nil, nil
  self.pts, self.tricks, self.mar = { 0, 0 }, { 0, 0 }, { 0, 0 }
  self.led, self.last, self.public, self.won = nil, {}, {}, { {}, {} }
  self.turn, self.phase, self.res = non, "play", nil
end

function Ref:total(p) return self.pts[p] + (self.tricks[p] > 0 and self.mar[p] or 0) end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function Ref:stockOpen() return self.closed == nil and #self.stock > 0 end

function Ref:legal(p)
  local out = {}
  if self.phase ~= "play" or self.turn ~= p then return out end
  local h = self.hands[p]
  if not self.led then
    for f in pairs(h) do
      out["P" .. f] = true
      local r = R_(f)
      if (r == "K" and h["Q" .. U_(f)]) or (r == "Q" and h["K" .. U_(f)]) then out["M" .. f] = true end
    end
    -- the nine: on lead, at least one trick won, stock not closed and more than two cards in it
    if h["9" .. self.tsuit] and self.tricks[p] > 0 and self.closed == nil and #self.stock > 2 then out.S = true end
    if self.closed == nil and #self.stock > 2 then out.C = true end
    return out
  end
  if self:stockOpen() then
    for f in pairs(h) do out["P" .. f] = true end
    return out
  end
  -- strict: follow and head; follow lower; trump; anything
  local L = self.led.f
  local tiers = { {}, {}, {}, {} }
  for f in pairs(h) do
    if U_(f) == U_(L) then
      if STR[R_(f)] > STR[R_(L)] then tiers[1][f] = true else tiers[2][f] = true end
    elseif U_(f) == self.tsuit then
      tiers[3][f] = true
    end
    tiers[4][f] = true
  end
  local pick
  if next(tiers[1]) then pick = tiers[1]
  elseif next(tiers[2]) then pick = tiers[2]  -- follow suit: higher ones would be in tier 1
  elseif next(tiers[3]) then pick = tiers[3]
  else pick = tiers[4] end
  -- following suit: a higher card if any, else any card of the suit (tier 1 present => only tier 1)
  for f in pairs(pick) do out["P" .. f] = true end
  return out
end

function Ref:finish(w)
  local gp = 0
  if w then
    local l = 3 - w
    if self.closed and self.closed ~= w then
      gp = self.oppHadTrick and 2 or 3
    elseif self.tricks[l] == 0 then gp = 3
    elseif self:total(l) < 33 then gp = 2
    else gp = 1 end
    self.gp[w] = self.gp[w] + gp
    self.dealer = w
  end
  self.res = { winner = w or 0, gp = gp }
  self.turn = nil
  if w and self.gp[w] >= 11 then self.phase, self.winner = "match", w else self.phase = "hand" end
end

function Ref:apply(p, key)
  local h = self.hands[p]
  if key == "C" then
    self.closed, self.oppHadTrick = p, self.tricks[3 - p] > 0
    return
  end
  if key == "S" then
    local nine = "9" .. self.tsuit
    h[nine] = nil
    h[self.trumpCard] = true
    self.public[self.trumpCard] = true
    self.stock[#self.stock] = nine
    self.trumpCard = nine
    return
  end
  local kind, f = key:sub(1, 1), key:sub(2)
  h[f] = nil
  self.public[f] = nil
  if not self.led then
    self.led = { p = p, f = f }
    self.turn = 3 - p
    if kind == "M" then
      local partner = (R_(f) == "K" and "Q" or "K") .. U_(f)
      self.public[partner] = true
      self.mar[p] = self.mar[p] + (U_(f) == self.tsuit and 40 or 20)
      if self:total(p) >= 66 then self:finish(p) end
    end
    return
  end
  -- the trick
  local L, lp = self.led.f, self.led.p
  local w
  if U_(f) == U_(L) then w = STR[R_(f)] > STR[R_(L)] and p or lp
  elseif U_(f) == self.tsuit then w = p
  else w = lp end
  self.pts[w] = self.pts[w] + PTS[R_(L)] + PTS[R_(f)]
  self.tricks[w] = self.tricks[w] + 1
  self.won[w][L], self.won[w][f] = true, true
  self.last = { L, f }
  self.led = nil
  if self:stockOpen() then
    local a = table.remove(self.stock, 1)
    local b = table.remove(self.stock, 1)
    self.hands[w][a] = true
    self.hands[3 - w][b] = true
    if b == self.trumpCard then self.public[b] = true; self.trumpCard = nil end
    if a == self.trumpCard then error("reference: the winner drew the face-up card") end
  end
  self.turn = w
  local empty = next(self.hands[1]) == nil and next(self.hands[2]) == nil
  if empty and self.closed == nil then self.pts[w] = self.pts[w] + 10 end
  if self:total(w) >= 66 then self:finish(w)
  elseif empty then
    if self.closed then self:finish(3 - self.closed)
    else
      local a, b = self:total(1), self:total(2)
      if a == b then self:finish(nil) else self:finish(a > b and 1 or 2) end
    end
  end
end

function Ref:void()
  self.phase = "deal"
  self.turn = nil
end

-- Faces a seat (1, 2; 0 = watcher) may see right now.
function Ref:visible(p)
  local v = {}
  if p == 1 or p == 2 then for f in pairs(self.hands[p]) do v[f] = true end end
  for f in pairs(self.public) do v[f] = true end
  if self.led then v[self.led.f] = true end
  for _, f in ipairs(self.last) do v[f] = true end
  if self.trumpCard then v[self.trumpCard] = true end
  return v
end

------------------------------------------------------------------ engine glue
local function idx(s, f) for i = 1, 24 do if s.deck[i] == f then return i end end end
local function partnerOf(f) return (R_(f) == "K" and "Q" or "K") .. U_(f) end

local function toAction(s, key)
  if key == "C" then return { k = "close" } end
  if key == "S" then local f = "9" .. s.tsuit; return { k = "swap9", i = idx(s, f), c = f } end
  local kind, f = key:sub(1, 1), key:sub(2)
  if kind == "P" then return { k = "play", i = idx(s, f), c = f } end
  local d = partnerOf(f)
  return { k = "marry", i = idx(s, f), c = f, j = idx(s, d), d = d }
end

local function keyOf(s, a)
  if a.k == "close" then return "C" end
  if a.k == "swap9" then return "S" end
  if a.k == "play" then return "P" .. a.c end
  if a.k == "marry" then
    assert(a.d == partnerOf(a.c) and s.deck[a.j] == a.d and s.deck[a.i] == a.c, "marry action malformed")
    return "M" .. a.c
  end
  return "?" .. tostring(a.k)
end

local function keysStr(set)
  local t = {}
  for k in pairs(set) do t[#t + 1] = k end
  table.sort(t)
  return table.concat(t, " ")
end

------------------------------------------------------------------ checks
local stats = {
  matches = 0, hands = 0, steps = 0, checks = 0, illegalTried = 0, legalTried = 0,
  reasons = {}, gp = {}, closes = 0, swaps = 0, marriages = 0, ties = 0, voids = 0, leaves = 0,
  viewMatches = 0, snapshots = 0, failures = 0, autoMatches = 0, randMatches = 0, mixMatches = 0,
  closerWon = 0, closerLost = 0, last10 = 0, marryEnds = 0, e2e = 0,
}
local failures = {}

local Fail = {}
local function check(cond, msg)
  stats.checks = stats.checks + 1
  if not cond then error(setmetatable({ msg = msg }, Fail), 0) end
end

local function sortedFaces(s, list)
  local t = {}
  for n, i in ipairs(list) do t[n] = s.deck[i] or "?" end
  table.sort(t)
  return table.concat(t, " ")
end
local function setStr(set) local t = {} for f in pairs(set) do t[#t + 1] = f end table.sort(t) return table.concat(t, " ") end

local function compare(s, r)
  check(s.phase == r.phase, "phase " .. tostring(s.phase) .. " vs ref " .. tostring(r.phase))
  check(s.gp[1] == r.gp[1] and s.gp[2] == r.gp[2], "game points " .. S(s.gp) .. " vs ref " .. S(r.gp))
  check(s.dealer == r.dealer, "dealer")
  if r.phase == "deal" then return end
  check(s.turn == r.turn, "turn " .. tostring(s.turn) .. " vs ref " .. tostring(r.turn))
  for p = 1, 2 do
    check(sortedFaces(s, s.hands[p]) == setStr(r.hands[p]), "hand " .. p .. ": " .. sortedFaces(s, s.hands[p]) .. " vs ref " .. setStr(r.hands[p]))
    check(s.pts[p] == r.pts[p], "card points seat " .. p .. " " .. s.pts[p] .. " vs ref " .. r.pts[p])
    check(s.ntr[p] == r.tricks[p], "tricks seat " .. p)
    check(s.mar[p] == r.mar[p], "marriages seat " .. p)
    check(E.points(s, p) == r:total(p), "E.points seat " .. p)
    check(sortedFaces(s, s.won[p]) == setStr(r.won[p]), "won cards seat " .. p)
  end
  local st = {}
  for n, i in ipairs(s.stock) do st[n] = s.deck[i] end
  check(table.concat(st, " ") == table.concat(r.stock, " "), "stock order")
  check((s.trumpI and s.deck[s.trumpI]) == r.trumpCard, "face-up trump card")
  check(s.tsuit == r.tsuit, "trump suit")
  check(s.closed == r.closed, "closed by")
  if r.closed then check(s.closeOpp == r.oppHadTrick, "closeOpp") end
  local trick = r.led and r.led.f or nil
  check((#s.trick == 0 and trick == nil) or (#s.trick == 1 and s.deck[s.trick[1]] == trick), "trick on the table")
  check(sortedFaces(s, s.last) == table.concat((function() local t = { r.last[1], r.last[2] } table.sort(t) return t end)(), " "), "last trick")
  -- conservation: every face exactly once in hands + stock + trick + won
  local seen, n = {}, 0
  local function put(i)
    local f = s.deck[i]
    check(f ~= nil and not seen[f], "conservation: duplicate or unknown card at " .. tostring(i))
    seen[f] = true; n = n + 1
  end
  for p = 1, 2 do for _, i in ipairs(s.hands[p]) do put(i) end; for _, i in ipairs(s.won[p]) do put(i) end end
  for _, i in ipairs(s.stock) do put(i) end
  for _, i in ipairs(s.trick) do put(i) end
  check(n == 24, "conservation: " .. n .. " cards")
  -- hidden = own hand cards that are not public
  for p = 1, 2 do
    local h = {}
    for f in pairs(r.hands[p]) do if not r.public[f] then h[#h + 1] = f end end
    table.sort(h)
    check(sortedFaces(s, E.hidden(s, p)) == table.concat(h, " "), "E.hidden seat " .. p)
  end
end

-- No face that seat p may not see appears anywhere in E.view(s, p).
local function checkViews(s, r)
  if s.phase == "match" or r.phase == "deal" then return end
  for p = 0, 2 do
    local v = E.view(s, p)
    local vis = r:visible(p)
    local function scan(t, path)
      for k, x in pairs(t) do
        if type(x) == "table" then scan(x, path .. "." .. tostring(k))
        elseif type(x) == "string" and ISFACE[x] then
          check(vis[x], "view " .. p .. " leaks " .. x .. " at " .. path .. "." .. tostring(k))
        end
        if type(k) == "string" and ISFACE[k] then check(vis[k], "view " .. p .. " leaks key " .. k) end
      end
    end
    scan(v, "v")
    -- and it holds every face it should see
    for f in pairs(vis) do check(v.deck[idx(s, f)] == f, "view " .. p .. " misses visible " .. f) end
  end
end

local function checkAuto(s, r, p)
  check(E.auto(s, 3 - p) == nil, "auto off turn")
  local a = E.auto(s, p)
  local legal = r:legal(p)
  check(a and a.k == "play" and legal["P" .. a.c], "auto is not a legal play")
  local function key(f) return PTS[R_(f)] * 2 + (U_(f) == r.tsuit and 1 or 0) end
  local best
  for k in pairs(legal) do
    if k:sub(1, 1) == "P" then local v = key(k:sub(2)); if not best or v < best then best = v end end
  end
  check(key(a.c) == best, "auto is not the weakest allowed card: " .. a.c)
end

-- Candidate actions for seat p that the reference calls illegal must be refused, state untouched.
local function checkIllegal(s, r, p, rnd)
  local legal = r:legal(p)
  local before = S(s)
  local tried = {}
  local function refuse(seat, a, what)
    stats.illegalTried = stats.illegalTried + 1
    local okk = E.apply(s, seat, a)
    check(not okk, "accepted illegal " .. what .. " " .. S(a) .. " seat " .. seat)
    tried[#tried + 1] = what
  end
  for _, f in ipairs(FACES) do
    local i = idx(s, f)
    if not legal["P" .. f] then refuse(p, { k = "play", i = i, c = f }, "play") end
    local rk = R_(f)
    if (rk == "K" or rk == "Q") and not legal["M" .. f] then
      local d = partnerOf(f)
      refuse(p, { k = "marry", i = i, c = f, j = idx(s, d), d = d }, "marry")
    end
    if not legal.S then refuse(p, { k = "swap9", i = i, c = f }, "swap") end
    -- a hand card announced with a wrong face
    if s.deck[i] ~= nil then
      local g = FACES[rnd(1, 24)]
      if g ~= f then refuse(p, { k = "play", i = i, c = g }, "wrong face") end
    end
  end
  if legal.S then
    -- swap with a non-nine
    local f = FACES[rnd(1, 24)]
    if f ~= "9" .. r.tsuit then refuse(p, { k = "swap9", i = idx(s, f), c = f }, "swap a non-nine") end
  end
  if not legal.C then refuse(p, { k = "close" }, "close") end
  -- the other seat and the table may do nothing
  for k in pairs(legal) do refuse(3 - p, toAction(s, k), "off turn"); refuse(0, toAction(s, k), "table seat") end
  refuse(p, { k = "play" }, "malformed"); refuse(p, { k = "frob" }, "unknown kind"); refuse(p, "x", "not a table")
  refuse(p, { k = "play", i = 1.5, c = "AS" }, "fractional index")
  refuse(0, { k = "deal", deck = FACES }, "deal mid-hand")
  -- marriage with a non-partner
  for f in pairs(r.hands[p]) do
    if R_(f) == "K" or R_(f) == "Q" then
      for g in pairs(r.hands[p]) do
        if g ~= f and g ~= partnerOf(f) then refuse(p, { k = "marry", i = idx(s, f), c = f, j = idx(s, g), d = g }, "marry non-partner") end
      end
    end
  end
  -- the state is untouched by all those refusals (one fingerprint for the batch)
  check(S(s) == before, "a refused action changed the state (one of: " .. table.concat(tried, ", ") .. ")")
  -- every legal action is accepted (on a copy)
  for k in pairs(legal) do
    stats.legalTried = stats.legalTried + 1
    local c = E.restore(E.snapshot(s))
    local okk, why = E.apply(c, p, toAction(c, k))
    check(okk, "refused legal " .. k .. ": " .. tostring(why))
  end
end

------------------------------------------------------------------ views in step (network path)
local VKEYS = { "phase", "turn", "lead", "dealer", "hand", "closed", "closeOpp", "trumpI", "tsuit", "winner",
  "pts", "ntr", "mar", "gp", "hands", "stock", "trick", "last", "res" }
local function viewAct(views, full, seat, a)
  for p = 0, 2 do
    local va = a.k == "deal" and { k = "deal", deck = {} } or a
    local okk, why = E.apply(views[p], seat, va)
    check(okk, "view " .. p .. " refused " .. tostring(a.k) .. ": " .. tostring(why))
    local want, cards = E.view(full, p).deck, {}
    for i = 1, 24 do if want[i] and views[p].deck[i] == nil then cards[i] = want[i] end end
    if next(cards) then check(E.apply(views[p], 0, { k = "show", cards = cards }), "view show") end
    for _, key in ipairs(VKEYS) do check(S(views[p][key]) == S(full[key]), "view " .. p .. " differs at " .. key) end
  end
  local t = full.turn
  if t and full.phase == "play" then
    check(S(E.legal(views[t], t)) == S(E.legal(full, t)), "legal on the view")
    check(S(E.auto(views[t], t)) == S(E.auto(full, t)), "auto on the view")
  end
end

------------------------------------------------------------------ one match
local function shuffled(rnd)
  local d = {}
  for n, f in ipairs(FACES) do d[n] = f end
  for n = #d, 2, -1 do local m = rnd(1, n); d[n], d[m] = d[m], d[n] end
  return d
end

local function playMatch(mseed, mode, withViews)
  local rnd = rng(mseed)
  local first = rnd(1, 2)
  local s, r = E.new{ first = first }, Ref.new(first)
  local log, actions = {}, {}
  local snapAt, snap = rnd(1, 120), nil
  local views
  if withViews then views = { [0] = E.view(s, 0), [1] = E.view(s, 1), [2] = E.view(s, 2) } end
  local function apply(seat, a)
    if snap then actions[#actions + 1] = { seat, a } end
    local okk, why = E.apply(s, seat, a)
    check(okk, "engine refused " .. S(a) .. ": " .. tostring(why))
    if views then viewAct(views, s, seat, a) end
  end
  local step, hands = 0, 0
  local voidAt = rnd(1, 400) == 1 and rnd(1, 20) or nil
  local leaveAt = rnd(1, 300) == 1 and rnd(1, 150) or nil
  local ok_, err = pcall(function()
    while true do
      step = step + 1
      if step == snapAt and not snap then snap = E.snapshot(s) end
      if leaveAt and step == leaveAt and s.phase ~= "match" then
        local who = rnd(1, 2)
        E.leave(s, who)
        if views then for p = 0, 2 do E.leave(views[p], who) end end
        log[#log + 1] = "leave" .. who
        if snap then actions[#actions + 1] = { "leave", who } end
        check(s.phase == "match" and s.winner == 3 - who, "leave")
        local res = E.result(s)
        check(res.winners[1] == 3 - who and res.losers[1] == who, "result after leave")
        stats.leaves = stats.leaves + 1
        break
      end
      if s.phase == "match" then
        check(r.phase == "match" and s.winner == r.winner, "match winner")
        local res = E.result(s)
        check(res and res.winners[1] == r.winner and res.losers[1] == 3 - r.winner, "E.result")
        check(s.gp[r.winner] >= 11 and s.gp[3 - r.winner] < 11, "match target")
        check(E.nextFirst(s, { true, true }) == 3 - r.winner, "nextFirst: the loser leads the next match")
        break
      end
      if s.phase == "deal" or s.phase == "hand" then
        local sys = E.system(s)
        check(sys and sys.k == "deal" and sys.need == "deck", "system asks for a deck")
        local deck = shuffled(rnd)
        log[#log + 1] = "deal:" .. table.concat(deck, ",")
        apply(0, { k = "deal", deck = deck })
        r:deal(deck)
        hands = hands + 1
        stats.hands = stats.hands + 1
        check(hands < 200, "match does not end")
        compare(s, r)
      else
        check(E.system(s) == nil, "system mid-hand")
        local p = r.turn
        local legal = r:legal(p)
        local eng = {}
        for _, a in ipairs(E.legal(s, p)) do eng[keyOf(s, a)] = true end
        check(keysStr(eng) == keysStr(legal), "legal set: engine [" .. keysStr(eng) .. "] ref [" .. keysStr(legal) .. "]")
        check(next(E.legal(s, 3 - p)) == nil, "legal off turn")
        if rnd(1, 4) == 1 then checkIllegal(s, r, p, rnd) end
        checkAuto(s, r, p)
        if voidAt and step >= voidAt and s.phase == "play" then
          voidAt = nil
          log[#log + 1] = "void"
          apply(0, { k = "void" })
          r:void()
          stats.voids = stats.voids + 1
          hands = hands - 1
          compare(s, r)
        else
          local key
          local useAuto = mode == "auto" or (mode == "mix" and p == 1)
          if useAuto then
            key = "P" .. E.auto(s, p).c
          else
            local ks = {}
            for k in pairs(legal) do ks[#ks + 1] = k end
            table.sort(ks)
            -- bias towards declarations so every rule branch gets exercised often
            local pref = {}
            for _, k in ipairs(ks) do
              local c = k:sub(1, 1)
              if (c == "M" or c == "S") and rnd(1, 2) == 1 or c == "C" and rnd(1, 10) == 1 then pref[#pref + 1] = k end
            end
            if #pref > 0 then key = pref[rnd(1, #pref)] else key = ks[rnd(1, #ks)] end
          end
          log[#log + 1] = p .. ":" .. key
          if key == "C" then stats.closes = stats.closes + 1 end
          if key == "S" then stats.swaps = stats.swaps + 1 end
          if key:sub(1, 1) == "M" then stats.marriages = stats.marriages + 1 end
          local closedBy = r.closed
          apply(p, toAction(s, key))
          r:apply(p, key)
          stats.steps = stats.steps + 1
          compare(s, r)
          checkViews(s, r)
          if r.res and s.res and (r.phase == "hand" or r.phase == "match") and r.turn == nil then
            check(s.res.winner == r.res.winner and s.res.gp == r.res.gp, "hand result " .. S(s.res) .. " vs ref " .. S(r.res))
            stats.reasons[s.res.reason] = (stats.reasons[s.res.reason] or 0) + 1
            stats.gp[s.res.gp] = (stats.gp[s.res.gp] or 0) + 1
            if s.res.winner == 0 then stats.ties = stats.ties + 1 end
            if closedBy then
              if s.res.winner == closedBy then stats.closerWon = stats.closerWon + 1 else stats.closerLost = stats.closerLost + 1 end
            end
            if key:sub(1, 1) == "M" then stats.marryEnds = stats.marryEnds + 1 end
            if not closedBy and #s.hands[1] == 0 and #s.hands[2] == 0 then stats.last10 = stats.last10 + 1 end
            r.res = nil
          end
        end
      end
    end
    -- snapshot -> restore -> replay
    if snap then
      stats.snapshots = stats.snapshots + 1
      local t = E.restore(snap)
      for _, x in ipairs(actions) do
        if x[1] == "leave" then E.leave(t, x[2]) else
          local okk, why = E.apply(t, x[1], x[2])
          check(okk, "replay after restore refused: " .. tostring(why))
        end
      end
      check(S(t) == S(s), "snapshot -> restore -> replay differs")
    end
    if views then
      for p = 0, 2 do check(S(views[p].gp) == S(s.gp) and views[p].phase == s.phase, "view end state") end
      -- once the match is over everything is visible
      for p = 0, 2 do local v = E.view(s, p) for i = 1, 24 do check(v.deck[i] == s.deck[i], "match over: view shows all") end end
    end
  end)
  if not ok_ then
    stats.failures = stats.failures + 1
    local msg = (type(err) == "table" and getmetatable(err) == Fail) and err.msg or tostring(err)
    if #failures < 20 then
      failures[#failures + 1] = string.format("match seed %d mode %s views %s step %d: %s\n  moves: %s",
        mseed, mode, tostring(withViews), step, msg, table.concat(log, " | ", math.max(1, #log - 40)))
    end
  end
end

------------------------------------------------------------------ end to end (sim + play)
local function e2e(n, seed)
  if n <= 0 then return end
  local Play = require("play")
  local Sim = require("sim")
  local V = Sim.ns.LedgerView
  for m = 1, n do
    local okk, err = pcall(function()
      local sim, cl = Play.guild(2)
      local x = (seed * 7919 + m * 104729) % 2147483647 + 1
      local rnd = function(lo, hi)
        x = (x * 1103515245 + 12345) % 2147483648
        return lo + math.floor(x / 65536) % (hi - lo + 1)
      end
      for _, c in pairs(cl) do c.env.random = rnd end
      local SK = 10000 * m
      Play.open(sim, cl, "santase", SK, 2)
      local host, guest = cl[Play.NAMES[1]], cl[Play.NAMES[2]]
      local r = Play.finish(sim, host, 20000)
      check(r and r.winners and #r.winners == 1 and #r.losers == 1, "e2e: a winner and a loser")
      local hs, gs = host.session.state, guest.session.state
      -- both clients ended with the same public match state
      check(S(hs.gp) == S(gs.gp) and hs.winner == gs.winner, "e2e: clients disagree on the result")
      check(hs.gp[hs.winner] >= 11, "e2e: match target")
      sim:run(600)
      -- the debt: loser -> winner, the stake, the same on both ledgers
      local names = host.session.seats
      local W, L = names[hs.winner], names[3 - hs.winner]
      for ci, c in ipairs({ host, guest }) do
        local found = 0
        for _, d in ipairs(V.of(c.ledger).debts) do
          if d.f == L and d.t == W and d.c == SK then found = found + 1 end
          check(not (d.f == W and d.t == L), "e2e: a debt the wrong way")
        end
        if found ~= 1 then print(S(V.of(c.ledger).debts), L, W, SK) end
        check(found == 1, "e2e: debt loser->winner on client " .. ci .. ": " .. found)
      end
      stats.e2e = stats.e2e + 1
      stats.e2eHands = (stats.e2eHands or 0) + hs.hand
    end)
    if not okk then
      stats.failures = stats.failures + 1
      local msg = (type(err) == "table" and getmetatable(err) == Fail) and err.msg or tostring(err)
      failures[#failures + 1] = "e2e match " .. m .. " seed " .. seed .. ": " .. msg
    end
  end
end

------------------------------------------------------------------ main
local t0 = os.clock()
local master = rng(SEED)
for m = 1, MATCHES do
  local mseed = master(1, 2147483000)
  local mode = ({ "rand", "rand", "auto", "mix" })[(m % 4) + 1]
  stats[mode .. "Matches"] = stats[mode .. "Matches"] + 1
  playMatch(mseed, mode, m % VIEWEVERY == 0)
  stats.matches = stats.matches + 1
  if m % VIEWEVERY == 0 then stats.viewMatches = stats.viewMatches + 1 end
end
e2e(E2E, SEED)

print(string.format("santase soak: seed %d, %d matches (%d random, %d auto, %d auto-vs-random; %d also on views), %d hands, %d moves, %.1fs",
  SEED, stats.matches, stats.randMatches, stats.autoMatches, stats.mixMatches, stats.viewMatches, stats.hands, stats.steps, os.clock() - t0))
print(string.format("  checks %d, illegal candidates refused %d, legal accepted %d, snapshot replays %d, voids %d, leaves %d, e2e staked matches %d",
  stats.checks, stats.illegalTried, stats.legalTried, stats.snapshots, stats.voids, stats.leaves, stats.e2e) .. " (" .. (stats.e2eHands or 0) .. " hands)")
local rs = {}
for k, v in pairs(stats.reasons) do rs[#rs + 1] = k .. "=" .. v end
table.sort(rs)
print(string.format("  hand ends: %s; game points 1/2/3: %d/%d/%d; ties %d; closes %d (closer won %d, lost %d); swaps %d; marriages %d (%d ended a hand); played out with last-10 %d",
  table.concat(rs, " "), stats.gp[1] or 0, stats.gp[2] or 0, stats.gp[3] or 0, stats.ties, stats.closes, stats.closerWon, stats.closerLost,
  stats.swaps, stats.marriages, stats.marryEnds, stats.last10))
print("  failures: " .. stats.failures)
for _, f in ipairs(failures) do print("FAIL " .. f) end
os.exit(stats.failures == 0 and 0 or 1)
