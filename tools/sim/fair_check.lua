-- Can a deal be predicted or biased? Checks of the seed combination of the fair
-- deal (core/Fair.lua, core/Deck.lua) with the real code, independent of any table:
--   1. the shuffle is uniform: every permutation of 4 cards equally often, every
--      card of 52 equally often in every position (chi-square, fixed thresholds);
--   2. one honest seed is enough: the other seats choose theirs as they like
--      (all zeros, the honest seat's own commit, a copy of an earlier seed of
--      it) and the deck is still uniform over the honest seed;
--   3. a seat that grinds its own seed before it commits (it tries K seeds and
--      keeps the one it likes best) gains nothing: what it likes depends on the
--      seeds it cannot know yet;
--   4. a change of any one seed, of the hand id or of the order of the seeds
--      changes the deck (no seed is ignored, no two hands share a deck);
--   5. the dice are uniform and fair over one honest seed too;
--   6. a seed is unpredictable from the ones a client already published (its
--      secret pool, Fair.seed): seeds of one client never repeat and look random.
-- Usage (repo root): luajit tools/sim/fair_check.lua [trials] [seed]
package.path = "tests/helpers/?.lua;" .. package.path
Loader = require("loader")
local ns = Loader.ns()
local Fair, Deck, Sha256 = ns.Fair, ns.Deck, ns.Sha256
local DECK = ns.Engines.holdem.DECK -- 52 cards
local N = tonumber(arg[1]) or 20000
local SEED = tonumber(arg[2]) or 1

local x = (SEED * 7919 + 1) % 2147483646 + 1
-- MINSTD (Park-Miller): every product stays below 2^53, exact in a double (an LCG mod 2^31 with a
-- 31-bit multiplier is not, and cycles short)
local function rnd(lo, hi) x = (x * 48271) % 2147483647; return lo + math.floor(x / 2147483647 * (hi - lo + 1)) end
local function hex(n) local t = {} for i = 1, n do t[i] = string.format("%02x", rnd(0, 255)) end return table.concat(t) end
local function seed() return hex(16) end

local fails, checks = 0, 0
local function check(okv, what)
  checks = checks + 1
  if not okv then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end
end

-- chi-square statistic of counts against a uniform expectation
local function chi(counts, k, total)
  local e, s = total / k, 0
  for i = 1, k do local d = (counts[i] or 0) - e; s = s + d * d / e end
  return s
end
-- a loose upper bound for chi-square with df degrees of freedom (mean df, sd sqrt(2 df)): df + 5 sd
local function bound(df) return df + 5 * math.sqrt(2 * df) end

-- 1. uniform permutations of 4, and card positions in 52
do
  local perms, idx = {}, {}
  local function key(p) return table.concat(p, ",") end
  local n = 0
  local function gen(a, k)
    if k > #a then n = n + 1; idx[key(a)] = n; return end
    for i = k, #a do a[k], a[i] = a[i], a[k]; gen(a, k + 1); a[k], a[i] = a[i], a[k] end
  end
  gen({ 1, 2, 3, 4 }, 1)
  for _ = 1, N do
    local p = Deck.permutation(Deck.key({ seed(), seed() }, "t/" .. rnd(1, 999)), 4)
    local i = idx[key(p)]
    perms[i] = (perms[i] or 0) + 1
  end
  local s = chi(perms, 24, N)
  check(s < bound(23), string.format("permutations of 4 uniform over %d shuffles (chi2 %.1f, df 23)", N, s))
  local pos = {}
  local M = math.floor(N / 4)
  for _ = 1, M do
    local d = Fair.deck(DECK, { seed(), seed(), seed() }, "t/" .. rnd(1, 99999))
    for i = 1, 52 do if d[i] == "AS" then pos[i] = (pos[i] or 0) + 1 end end
  end
  s = chi(pos, 52, M)
  check(s < bound(51), string.format("the ace of spades is in every position of 52 equally often (%d decks, chi2 %.1f, df 51)", M, s))
end

-- 2. one honest seed is enough, whatever the others choose
do
  local honestPrev = seed()
  local adversaries = {
    { "all zeros", function() return ("0"):rep(32) end },
    { "the honest commit's head", function(h) return Fair.commit(h):sub(1, 32) end }, -- not possible (commit first), worst case anyway
    { "a copy of an earlier seed of the honest seat", function() return honestPrev end },
  }
  for _, adv in ipairs(adversaries) do
    local first = {}
    local M = math.floor(N / 2)
    for _ = 1, M do
      local h = seed()
      local d = Fair.deck(DECK, { adv[2](h), h }, "tid/7")
      local c = d[1]
      first[c] = (first[c] or 0) + 1
    end
    local counts, i = {}, 0
    for _, c in ipairs(DECK) do i = i + 1; counts[i] = first[c] or 0 end
    local s = chi(counts, 52, M)
    check(s < bound(51), string.format("other seed = %s: the first card is uniform over the honest seed (chi2 %.1f)", adv[1], s))
  end
end

-- 3. grinding one's own seed before the commit gains nothing
do
  local K, wins, M = 64, 0, math.floor(N / 8)
  for _ = 1, M do
    -- the grinder keeps, of K seeds, the one that would deal it an ace first IF the other seed were "0..0"
    local best
    for _ = 1, K do
      local g = seed()
      local d = Fair.deck(DECK, { g, ("0"):rep(32) }, "tid/9")
      if d[1]:sub(1, 1) == "A" then best = g; break end
      best = best or g
    end
    local d = Fair.deck(DECK, { best, seed() }, "tid/9") -- the other seat's real seed
    if d[1]:sub(1, 1) == "A" then wins = wins + 1 end
  end
  local p, e = wins / M, 4 / 52
  local sd = math.sqrt(e * (1 - e) / M)
  check(math.abs(p - e) < 5 * sd, string.format("a grinder that tries %d seeds gets an ace first %.4f of %d deals (fair %.4f)", K, p, M, e))
end

-- 4. every seed, the order and the hand id count
do
  local a, b, c = seed(), seed(), seed()
  local base = table.concat(Fair.deck(DECK, { a, b, c }, "t/1"), " ")
  local same = 0
  local function differs(d) if table.concat(d, " ") == base then same = same + 1 end end
  differs(Fair.deck(DECK, { seed(), b, c }, "t/1"))
  differs(Fair.deck(DECK, { a, seed(), c }, "t/1"))
  differs(Fair.deck(DECK, { a, b, seed() }, "t/1"))
  differs(Fair.deck(DECK, { b, a, c }, "t/1"))
  differs(Fair.deck(DECK, { a, b, c }, "t/2"))
  differs(Fair.deck(DECK, { a .. b:sub(1, 1), b:sub(2), c }, "t/1")) -- the length prefix: no splice
  check(same == 0, "a change of any seed, of their order, of the hand id or of a seed boundary changes the deck")
end

-- 5. dice
do
  local faces, M = {}, N
  for _ = 1, M do
    local d1, d2 = Fair.dice({ ("0"):rep(32), seed() }, "tid/" .. rnd(1, 99))
    faces[(d1 - 1) * 6 + d2] = (faces[(d1 - 1) * 6 + d2] or 0) + 1
  end
  local s = chi(faces, 36, M)
  check(s < bound(35), string.format("the 36 throws are equally likely over one honest seed (chi2 %.1f, df 35)", s))
end

-- 6. a client's seeds (its secret pool) never repeat and their bytes are uniform
do
  local env = { me = "Иван Петров", guid = "Player-0000-00000001", now = function() return 12 end, epoch = function() return 1700000012 end,
    random = function(lo, hi) return lo end } -- the worst generator: always the same value
  local seen, bytes, M, dup = {}, {}, math.floor(N / 4), 0
  for i = 1, M do
    local sd = Fair.seed(env, "deal|t/" .. i)
    if seen[sd] then dup = dup + 1 end
    seen[sd] = true
    for j = 1, #sd, 2 do local v = tonumber(sd:sub(j, j + 1), 16) + 1; bytes[v] = (bytes[v] or 0) + 1 end
  end
  check(dup == 0, string.format("%d seeds of one client (a constant env.random) never repeat", M))
  local s = chi(bytes, 256, M * 16)
  check(s < bound(255), string.format("their bytes are uniform (chi2 %.1f, df 255)", s))
  -- a second client with the same name and clock but its own guid: other seeds
  local env2 = {}
  for k, v in pairs(env) do env2[k] = v end
  env2.guid = "Player-0000-00000002"
  check(Fair.seed(env2, "deal|t/1") ~= Fair.seed({ me = env.me, guid = env.guid, now = env.now, epoch = env.epoch, random = env.random }, "deal|t/1"),
    "two clients never share their seeds")
end
_ = Sha256

print(string.format("\n%d checks, %d failed (trials %d, seed %d)", checks, fails, N, SEED))
os.exit(fails == 0 and 0 or 1)
