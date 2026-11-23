-- Белот soak: plays whole matches through engines/belot.lua and checks them against a
-- reference written from the rules (belot.bg "Belot Rules", bg.wikipedia "Бридж-белот" and
-- the help text, locale help.belot.*), not from the engine's code.
--
--   luajit tools/sim/belot_soak.lua [matches = 10000] [seed = 1] [only match n]
--
-- Run from the repository root. Deterministic per seed; a failure prints the seed and the
-- match number (rerun with the third argument to replay only that match) and the move list.
-- Players: random legal moves (random bids incl. контра/реконтра, random announce subsets,
-- belote claimed or not), the engine's bot (E.bot on the seat's own view), the timeout move
-- (E.auto), and mixes of the three. Checks:
--   * deal: 5 then 8 cards a seat, 32 distinct cards, each deal's cards back in play
--   * bids: the legal set equals the reference set; every illegal bid / wrong seat refused
--   * cards: the legal set equals the reference follow/trump/overtrump set; belote options;
--     every illegal card, wrong face, false belote, wrong seat refused
--   * announces: the offered announces equal the reference combinations; illegal ones refused
--   * a refused action leaves the state untouched
--   * trick winners, card points (152/120/248 a deal), 8 tricks of 4 cards
--   * deal score: raw totals, game points, hanging points, valat, match total and winner
--     recomputed by the reference scorer
--   * four client views (each seat's own view, fed only the actions and its own cards)
--     reach the same scores; a view never shows another seat's hidden cards; a seat's view
--     gives the same legal moves as the full state
--   * snapshot -> restore -> the restored copy plays on in lockstep with the original
--   * every match ends (cap on deals)

package.path = "tests/helpers/?.lua;" .. package.path
local ns = {}
assert(loadfile("engines/belot.lua"))("TavernGames", ns)
local E = ns.Engines.belot

local MATCHES = tonumber(arg[1]) or 10000
local SEED = tonumber(arg[2]) or 1
local ONLY = tonumber(arg[3])

---------------------------------------------------------------------------------------------
-- RNG (LCG, independent of math.random)
---------------------------------------------------------------------------------------------
local rngState = 1
local function seed(x) rngState = x % 2147483647; if rngState <= 0 then rngState = rngState + 2147483646 end end
local function rand(a, b)
  rngState = (rngState * 48271) % 2147483647
  if not a then return rngState / 2147483647 end
  return a + rngState % (b - a + 1)
end
local function pick(list) return list[rand(1, #list)] end

---------------------------------------------------------------------------------------------
-- Reference rules (from the rule texts)
---------------------------------------------------------------------------------------------
local SUITS = { "C", "D", "H", "S" }
local SEQ = { "7", "8", "9", "T", "J", "Q", "K", "A" }     -- order for sequences
local SEQI = {}
for n, r in ipairs(SEQ) do SEQI[r] = n end
-- strength (higher wins); points
local TR_STR = { ["7"] = 1, ["8"] = 2, Q = 3, K = 4, T = 5, A = 6, ["9"] = 7, J = 8 }
local PL_STR = { ["7"] = 1, ["8"] = 2, ["9"] = 3, J = 4, Q = 5, K = 6, T = 7, A = 8 }
local TR_PTS = { J = 20, ["9"] = 14, A = 11, T = 10, K = 4, Q = 3, ["8"] = 0, ["7"] = 0 }
local PL_PTS = { A = 11, T = 10, K = 4, Q = 3, J = 2, ["9"] = 0, ["8"] = 0, ["7"] = 0 }
local BIDR = { C = 1, D = 2, H = 3, S = 4, N = 5, A = 6 }

local function rk(f) return f:sub(1, 1) end
local function st(f) return f:sub(2, 2) end
local function team(seat) return (seat == 1 or seat == 3) and 1 or 2 end
local function isTrump(con, suit) return con == "A" or con == suit end
local function strength(con, f) return (isTrump(con, st(f)) and TR_STR or PL_STR)[rk(f)] end
local function points(con, f) return (isTrump(con, st(f)) and TR_PTS or PL_PTS)[rk(f)] end
-- does card c take the trick from the card cur that is winning it
local function beats(con, c, cur)
  if st(c) == st(cur) then return strength(con, c) > strength(con, cur) end
  return con ~= "A" and con ~= "N" and st(c) == con
end
local function winnerPos(con, trick)
  local w = 1
  for n = 2, #trick do if beats(con, trick[n], trick[w]) then w = n end end
  return w
end

-- the faces of `hand` that may be played to `trick` (faces)
local function refLegal(con, hand, trick)
  if #trick == 0 or #hand == 1 then return hand end
  local led = st(trick[1])
  local follow, trumps = {}, {}
  for _, f in ipairs(hand) do
    if st(f) == led then follow[#follow + 1] = f end
    if con ~= "N" and isTrump(con, st(f)) then trumps[#trumps + 1] = f end
  end
  if #follow > 0 then
    if con ~= "N" and isTrump(con, led) then
      -- trump led (or all trumps): go higher than every card of the suit in the trick
      local top = 0
      for _, f in ipairs(trick) do if st(f) == led and TR_STR[rk(f)] > top then top = TR_STR[rk(f)] end end
      local up = {}
      for _, f in ipairs(follow) do if TR_STR[rk(f)] > top then up[#up + 1] = f end end
      if #up > 0 then return up end
    end
    return follow
  end
  if con == "N" or con == "A" or #trumps == 0 then return hand end
  local w = winnerPos(con, trick)
  if w == #trick - 1 then return hand end             -- partner is winning the trick
  local cur = trick[w]
  if st(cur) == con then                               -- an opponent's trump wins: overtrump
    local up = {}
    for _, f in ipairs(trumps) do if TR_STR[rk(f)] > TR_STR[rk(cur)] then up[#up + 1] = f end end
    if #up > 0 then return up end
    return hand
  end
  return trumps
end

local function refBelote(con, hand, trick, f)
  if con == "N" or (rk(f) ~= "K" and rk(f) ~= "Q") then return false end
  if con == "A" then
    if #trick > 0 and st(trick[1]) ~= st(f) then return false end
  elseif st(f) ~= con then
    return false
  end
  local other = (rk(f) == "K" and "Q" or "K") .. st(f)
  for _, x in ipairs(hand) do if x == other then return true end end
  return false
end

-- combinations a hand (faces) can announce: list of {t=, top=face, cards={faces}}
local CARRE_T = { ["9"] = "c9", J = "cJ", T = "c", Q = "c", K = "c", A = "c" }
local function refCombos(hand)
  local has = {}
  for _, f in ipairs(hand) do has[f] = true end
  local out, inCarre = {}, {}
  for _, r in ipairs({ "9", "T", "J", "Q", "K", "A" }) do
    if has[r .. "C"] and has[r .. "D"] and has[r .. "H"] and has[r .. "S"] then
      out[#out + 1] = { t = CARRE_T[r], top = r .. "S", cards = { r .. "C", r .. "D", r .. "H", r .. "S" } }
      for _, s in ipairs(SUITS) do inCarre[r .. s] = true end
    end
  end
  local seen = {}
  local function runs(avoid)
    for _, s in ipairs(SUITS) do
      local run = {}
      for n = 1, 9 do
        local f = SEQ[n] and SEQ[n] .. s
        if f and has[f] and not (avoid and inCarre[f]) then
          run[#run + 1] = f
        else
          if #run >= 3 then
            local key = run[1] .. run[#run]
            if not seen[key] then
              seen[key] = true
              out[#out + 1] = { t = "s" .. #run, top = run[#run], cards = run }
            end
          end
          run = {}
        end
      end
    end
  end
  runs(false)
  runs(true)
  return out
end

local ANNV = { s3 = 20, s4 = 50, s5 = 100, s6 = 100, s7 = 100, s8 = 100, c = 100, c9 = 150, cJ = 200 }

-- which announces score; anns = list of {s=seat, t=, top=face}; returns points by team
local function refSettle(anns, belotes)
  local pts = { 0, 0 }
  local bestC, bestS
  for _, a in ipairs(anns) do
    if a.t:sub(1, 1) == "c" then
      local key = ANNV[a.t] * 100 + TR_STR[rk(a.top)]
      if not bestC or key > bestC.key then bestC = { key = key, team = team(a.s) } end
    else
      local key = tonumber(a.t:sub(2)) * 100 + SEQI[rk(a.top)]
      if not bestS or key > bestS.key then bestS = { key = key, team = team(a.s) } end
    end
  end
  local tied = false
  for _, a in ipairs(anns) do
    if a.t:sub(1, 1) == "s" and team(a.s) ~= bestS.team
      and tonumber(a.t:sub(2)) * 100 + SEQI[rk(a.top)] == bestS.key then tied = true end
  end
  for _, a in ipairs(anns) do
    local t = team(a.s)
    if a.t:sub(1, 1) == "c" then
      if t == bestC.team then pts[t] = pts[t] + ANNV[a.t] end
    elseif not tied and t == bestS.team then
      pts[t] = pts[t] + ANNV[a.t]
    end
  end
  for _, b in ipairs(belotes) do pts[team(b)] = pts[team(b)] + 20 end
  return pts, tied
end

-- rounding to game points: suit: the higher total rounds up from 7, the lower from 6;
-- all trumps: the higher from 5, the lower from 4; no trumps (doubled): from 5. `lower`:
-- the team counts as the one with fewer points.
local stats = { r5N = 0 }
local function refRound(con, p, lower)
  local q, r = math.floor(p / 10), p % 10
  local edge
  if con == "N" then edge = 5; if r == 5 then stats.r5N = stats.r5N + 1 end
  elseif con == "A" then edge = lower and 4 or 5
  else edge = lower and 6 or 7 end
  return r >= edge and q + 1 or q
end
local function refRoundSum(p) local q, r = math.floor(p / 10), p % 10; return r >= 5 and q + 1 or q end

---------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------
local function deepEq(a, b, path)
  if type(a) ~= type(b) then return false, path end
  if type(a) ~= "table" then return a == b, path end
  for k, v in pairs(a) do
    local okay, p = deepEq(v, b[k], (path or "") .. "." .. tostring(k))
    if not okay then return false, p end
  end
  for k in pairs(b) do if a[k] == nil then return false, (path or "") .. "." .. tostring(k) end end
  return true
end
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
local function ser(v)
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. ser(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function setOf(list) local t = {} for _, x in ipairs(list) do t[x] = true end return t end
local function sameSet(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end
local function keys(t) local o = {} for k in pairs(t) do o[#o + 1] = tostring(k) end table.sort(o) return table.concat(o, " ") end

local checks, failures, failLog = 0, 0, {}
local curMatch, curLog, curSeed
local function check(cond, what)
  checks = checks + 1
  if cond then return true end
  failures = failures + 1
  if #failLog < 15 then
    failLog[#failLog + 1] = string.format("match %d (seed %d): %s\n    moves: %s", curMatch, curSeed, what,
      table.concat(curLog, " "):sub(-1500))
  end
  error("soak-fail", 0)
end

local function handFaces(s, seat)
  local out = {}
  for n, i in ipairs(s.hands[seat]) do out[n] = s.deck[i] end
  return out
end
local function trickFaces(s)
  local out = {}
  for n, i in ipairs(s.trick) do out[n] = s.deck[i] end
  return out
end

---------------------------------------------------------------------------------------------
-- one match
---------------------------------------------------------------------------------------------
local totals = { matches = 0, deals = 0, passed = 0, tricks = 0, contracts = {}, x2 = 0, x4 = 0,
  inside = 0, hanging = 0, valat = 0, anns = 0, annTie = 0, belotes = 0, illegal = 0, snaps = 0,
  views = 0, wins151 = 0, blockedValat = 0, blockedZero = 0, modes = {} }

local function playMatch(m)
  curMatch, curLog = m, {}
  curSeed = SEED * 1000003 + m
  seed(curSeed)
  for _ = 1, 3 + curSeed % 7 do rand() end     -- neighbouring seeds start apart
  seed(rand(1, 2147483646) + curSeed * 7919)
  for _ = 1, 5 do rand() end
  local modeRoll = rand()
  local mode = modeRoll < 0.4 and "random" or modeRoll < 0.8 and "bot" or "mixed"
  totals.modes[mode] = (totals.modes[mode] or 0) + 1
  local kind = {}
  for q = 1, 4 do
    kind[q] = mode == "mixed" and pick({ "random", "bot", "auto" }) or mode
  end
  -- four timeouts pass for ever (E.auto never bids): somebody has to play
  if kind[1] == "auto" and kind[2] == "auto" and kind[3] == "auto" and kind[4] == "auto" then kind[1] = "random" end
  local passRate = 0.45 + rand() * 0.4
  local first = rand(1, 4)
  local s = E.new({ first = first })
  local clients = {}
  for q = 1, 4 do clients[q] = E.view(s, q) end
  local lock      -- restored copy playing in lockstep, or nil
  local score, hang, refFirst = { 0, 0 }, 0, first

  local function log(seat, a)
    local t = a.k
    if a.k == "bid" then t = a.b
    elseif a.k == "play" then t = a.c .. (a.b and "*" or "")
    elseif a.k == "ann" then
      local p = {}
      for _, x in ipairs(a.a) do p[#p + 1] = x.t .. ":" .. tostring(x.i) end
      t = "ann[" .. table.concat(p, ",") .. "]"
    end
    curLog[#curLog + 1] = seat .. ":" .. t
  end

  -- apply to the full state, the four clients and the lockstep copy
  local function doApply(seat, a, clientA)
    log(seat, a)
    local okay, why = E.apply(s, seat, copy(a))
    check(okay, "refused " .. ser(a) .. " by seat " .. seat .. ": " .. tostring(why))
    for q = 1, 4 do
      local ok2, why2 = E.apply(clients[q], seat, copy(clientA and clientA[q] or a))
      check(ok2, "client " .. q .. " refused " .. ser(a) .. ": " .. tostring(why2))
    end
    if lock then
      check(E.apply(lock, seat, copy(a)), "restored copy refused " .. ser(a))
    end
  end

  -- an action that must be refused, without touching the state
  local function mustRefuse(seat, a, what)
    local before = copy(s)
    local okay = E.apply(s, seat, a)
    check(not okay, "accepted illegal " .. what .. " " .. ser(a) .. " by seat " .. tostring(seat))
    local same, path = deepEq(before, s)
    check(same, "refused " .. what .. " changed the state at " .. tostring(path))
    totals.illegal = totals.illegal + 1
  end

  local function checkViews()
    totals.views = totals.views + 1
    for q = 1, 4 do
      local v = E.view(s, q)
      check(v.full == false, "view full flag")
      if not (s.phase == "match" or s.open) then
        for p = 1, 4 do
          for _, i in ipairs(s.hands[p]) do
            if p == q then
              check(v.deck[i] == s.deck[i], "view hides own card")
            else
              check(v.deck[i] == nil, "view of seat " .. q .. " shows seat " .. p .. "'s card " .. tostring(s.deck[i]))
            end
          end
        end
      end
      -- what the client state knows must never exceed what a view may show
      if not (s.phase == "match" or s.open) then
        for p = 1, 4 do
          if p ~= q then
            for _, i in ipairs(s.hands[p]) do
              check(clients[q].deck[i] == nil, "client " .. q .. " knows seat " .. p .. "'s card")
            end
          end
        end
      end
    end
  end

  local dealNo = 0
  while s.phase ~= "match" do
    dealNo = dealNo + 1
    check(dealNo <= 400, "match does not end")
    check(s.phase == "deal", "expected deal phase, got " .. tostring(s.phase))
    check(s.first == refFirst, "first to bid " .. tostring(s.first) .. " expected " .. refFirst)
    local sys = E.system(s)
    check(sys and sys.k == "deal" and sys.need == "deck", "system asks for a deck")
    mustRefuse(0, { k = "deal", deck = E.DECK, need = "deck" }, "deal with need")
    mustRefuse(1, { k = "deal", deck = E.DECK }, "deal by a seat")
    -- shuffle
    local deck = {}
    for n = 1, 32 do deck[n] = E.DECK[n] end
    for n = 32, 2, -1 do local k = rand(1, n); deck[n], deck[k] = deck[k], deck[n] end
    local bad = copy(deck); bad[5] = bad[6]
    mustRefuse(0, { k = "deal", deck = bad }, "deal with a duplicate")
    local cdeal = {}
    for q = 1, 4 do
      local own = {}
      for j = q, 32, 4 do own[j] = deck[j] end
      cdeal[q] = { k = "deal", deck = own }
    end
    curLog[#curLog + 1] = "|deal " .. table.concat(deck, "")
    doApply(0, { k = "deal", deck = deck }, cdeal)
    totals.deals = totals.deals + 1
    -- deal check: five each
    local all = {}
    for q = 1, 4 do
      check(#s.hands[q] == 5, "five cards each")
      for _, i in ipairs(s.hands[q]) do check(not all[i], "card dealt twice"); all[i] = true end
    end

    -- auction
    local con, x, decl, passes, bidCount = nil, 1, nil, 0, 0
    while s.phase == "bid" do
      local seat = s.turn
      check(seat == (bidCount == 0 and refFirst or seat), "first bidder")
      -- reference legal bids
      local ref = { P = true }
      for b, r in pairs(BIDR) do if not con or r > BIDR[con] then ref[b] = true end end
      if con and x == 1 and team(seat) ~= team(decl) then ref.X = true end
      if con and x == 2 and team(seat) == team(decl) then ref.R = true end
      local got = {}
      for _, a in ipairs(E.legal(s, seat)) do got[a.b] = true end
      check(sameSet(ref, got), "legal bids " .. keys(got) .. " expected " .. keys(ref))
      local cgot = {}
      for _, a in ipairs(E.legal(clients[seat], seat)) do cgot[a.b] = true end
      check(sameSet(ref, cgot), "client legal bids differ")
      -- illegal bids
      if rand() < 0.06 then
        local b = pick({ "P", "C", "D", "H", "S", "N", "A", "X", "R", "Z" })
        if not ref[b] then mustRefuse(seat, { k = "bid", b = b }, "bid") end
        mustRefuse(seat % 4 + 1, { k = "bid", b = "P" }, "bid off turn")
      end
      if rand() < 0.01 then checkViews() end
      local a
      local kd = kind[seat]
      if kd == "bot" then
        a = E.bot(clients[seat], seat, function(lo, hi) return rand(lo, hi) end)
      elseif kd == "auto" then
        a = E.auto(clients[seat], seat)
      else
        if rand() < passRate then a = { k = "bid", b = "P" }
        else
          local opts = {}
          for b in pairs(ref) do if b ~= "P" then opts[#opts + 1] = b end end
          table.sort(opts)
          a = { k = "bid", b = #opts > 0 and pick(opts) or "P" }
        end
      end
      check(a and a.k == "bid" and ref[a.b], "move " .. ser(a) .. " not a legal bid")
      doApply(seat, a)
      bidCount = bidCount + 1
      if a.b == "P" then passes = passes + 1
      else
        passes = 0
        if a.b == "X" then x = 2 elseif a.b == "R" then x = 4 else con, x, decl = a.b, 1, seat end
      end
      if not con and passes == 4 then
        check(s.phase == "deal", "four passes redeal")
      elseif con and passes == 3 then
        check(s.phase == "play", "three passes after a bid end the auction")
      else
        check(s.phase == "bid" and s.turn == seat % 4 + 1, "auction goes on to the next seat")
      end
    end
    if not con then
      totals.passed = totals.passed + 1
      check(s.score[1] == score[1] and s.score[2] == score[2] and s.hang == hang, "passed-out deal scores nothing")
      refFirst = refFirst % 4 + 1
    else
      totals.contracts[con] = (totals.contracts[con] or 0) + 1
      if x == 2 then totals.x2 = totals.x2 + 1 elseif x == 4 then totals.x4 = totals.x4 + 1 end
      check(s.contract.b == con and s.contract.x == x and s.contract.seat == decl, "contract")
      -- eight cards each, the deal's cards
      local dealt = {}
      for q = 1, 4 do
        check(#s.hands[q] == 8, "eight cards each")
        local f = {}
        for j = q, 32, 4 do f[#f + 1] = j end
        local h = copy(s.hands[q])
        table.sort(h)
        check(table.concat(h, ",") == table.concat(f, ","), "seat " .. q .. " got its dealt cards")
        dealt[q] = handFaces(s, q)
      end

      local snapAt = rand() < 0.25 and rand(1, 32) or nil
      local refPts, refTook, played, anns, belotes = { 0, 0 }, { 0, 0 }, {}, {}, {}
      local lastWinner, leader = nil, refFirst
      local announcedBy = {}
      for trickNo = 1, 8 do
        check(s.turn == leader, "leader of trick " .. trickNo)
        local trick = {}
        for pos = 1, 4 do
          local seat = s.turn
          check(seat == (leader + pos - 2) % 4 + 1, "turn order")
          if snapAt and (trickNo - 1) * 4 + pos == snapAt then
            lock = E.restore(E.snapshot(s))
            local same = deepEq(lock, s)
            check(same, "restore(snapshot) differs")
            totals.snaps = totals.snaps + 1
          end
          local hand = handFaces(s, seat)
          local refSet = setOf(refLegal(con, hand, trick))
          -- engine legal: cards, belote options, announces
          local cards, belo, annSets = {}, {}, {}
          for _, a in ipairs(E.legal(s, seat)) do
            if a.k == "play" then
              check(s.deck[a.i] == a.c, "legal card face")
              if a.b then belo[a.c] = true else cards[a.c] = true end
            else
              annSets[#annSets + 1] = a.a
            end
          end
          check(sameSet(refSet, cards), string.format("legal cards {%s} expected {%s} (%s, hand %s, trick %s)",
            keys(cards), keys(refSet), con, table.concat(hand, " "), table.concat(trick, " ")))
          local refBelo = {}
          for f in pairs(refSet) do if refBelote(con, hand, trick, f) then refBelo[f] = true end end
          check(sameSet(refBelo, belo), "belote options {" .. keys(belo) .. "} expected {" .. keys(refBelo) .. "}")
          local cLegal = E.legal(clients[seat], seat)
          check(deepEq(cLegal, E.legal(s, seat)), "client legal moves differ from the full state's")
          -- announces
          local mayAnn = trickNo == 1 and con ~= "N" and not announcedBy[seat]
          local combos = mayAnn and refCombos(dealt[seat]) or {}
          if mayAnn then
            local offered = {}
            for _, set in ipairs(annSets) do
              if #set == 1 then offered[set[1].t .. s.deck[set[1].i]] = true end
            end
            local refOff = {}
            for _, c in ipairs(combos) do refOff[c.t .. c.top] = true end
            check(sameSet(refOff, offered), "offered announces {" .. keys(offered) .. "} expected {" .. keys(refOff) .. "}")
            -- number of compatible subsets
            local nsub = 0
            for mask = 1, 2 ^ #combos - 1 do
              local used, okay = {}, true
              for n = 1, #combos do
                if math.floor(mask / 2 ^ (n - 1)) % 2 == 1 then
                  for _, f in ipairs(combos[n].cards) do
                    if used[f] then okay = false end
                    used[f] = true
                  end
                end
              end
              if okay then nsub = nsub + 1 end
            end
            check(nsub == #annSets, "announce sets " .. #annSets .. " expected " .. nsub)
          else
            check(#annSets == 0, "announces offered out of turn/trick/contract")
          end
          -- illegal moves
          if rand() < 0.06 then
            totals.illegal = totals.illegal
            for _, f in ipairs(hand) do
              if not refSet[f] then
                local i
                for _, j in ipairs(s.hands[seat]) do if s.deck[j] == f then i = j end end
                mustRefuse(seat, { k = "play", i = i, c = f }, "card")
                break
              end
            end
            for _, f in ipairs(hand) do
              if refSet[f] and not refBelo[f] then
                local i
                for _, j in ipairs(s.hands[seat]) do if s.deck[j] == f then i = j end end
                mustRefuse(seat, { k = "play", i = i, c = f, b = true }, "belote")
                -- wrong face
                local wrong = s.deck[(i % 32) + 1]
                if wrong ~= f then mustRefuse(seat, { k = "play", i = i, c = wrong }, "face") end
                break
              end
            end
            local other = (seat % 4) + 1
            if #s.hands[other] > 0 then
              local j = s.hands[other][1]
              mustRefuse(seat, { k = "play", i = j, c = s.deck[j] }, "another seat's card")
              mustRefuse(other, { k = "play", i = j, c = s.deck[j] }, "card off turn")
            end
            if not mayAnn then
              mustRefuse(seat, { k = "ann", a = { { t = "s3", i = s.hands[seat][1] } } }, "announce")
            else
              -- a combination not in the hand
              local t = pick({ "s3", "s4", "s5", "c", "c9", "cJ" })
              local i = pick(s.hands[seat])
              local okc = false
              for _, c in ipairs(combos) do if c.t == t and c.top == s.deck[i] then okc = true end end
              if not okc then mustRefuse(seat, { k = "ann", a = { { t = t, i = i } } }, "announce") end
              if #combos > 0 then
                local c = combos[1]
                local i1
                for _, j in ipairs(s.hands[seat]) do if s.deck[j] == c.top then i1 = j end end
                mustRefuse(seat, { k = "ann", a = { { t = c.t, i = i1 }, { t = c.t, i = i1 } } }, "announce twice")
              end
              mustRefuse(seat, { k = "ann", a = {} }, "empty announce")
            end
          end
          if rand() < 0.01 then checkViews() end

          -- the move
          local kd = kind[seat]
          local function moveOf()
            if kd == "bot" then return E.bot(clients[seat], seat, function(lo, hi) return rand(lo, hi) end) end
            if kd == "auto" then return E.auto(clients[seat], seat) end
            if mayAnn and #combos > 0 and rand() < 0.75 then
              -- a random compatible subset, in random order
              local set, used = {}, {}
              for _, c in ipairs(combos) do
                local free = true
                for _, f in ipairs(c.cards) do if used[f] then free = false end end
                if free and rand() < 0.7 then
                  for _, f in ipairs(c.cards) do used[f] = true end
                  local i
                  for _, j in ipairs(s.hands[seat]) do if s.deck[j] == c.top then i = j end end
                  table.insert(set, rand(1, #set + 1), { t = c.t, i = i })
                end
              end
              if #set > 0 then return { k = "ann", a = set } end
            end
            local opts = {}
            for f in pairs(refSet) do opts[#opts + 1] = f end
            table.sort(opts)
            local f = pick(opts)
            local i
            for _, j in ipairs(s.hands[seat]) do if s.deck[j] == f then i = j end end
            return { k = "play", i = i, c = f, b = (refBelo[f] and rand() < 0.85) or nil }
          end
          local a = moveOf()
          if a.k == "ann" then
            check(mayAnn, "announce when not allowed")
            for _, y in ipairs(a.a) do
              local f = s.deck[y.i]
              local okc = false
              for _, c in ipairs(combos) do if c.t == y.t and c.top == f then okc = true end end
              check(okc, "bot/auto announce " .. y.t .. " " .. tostring(f) .. " not a combination")
              anns[#anns + 1] = { s = seat, t = y.t, top = f }
            end
            announcedBy[seat] = true
            mayAnn = false
            totals.anns = totals.anns + #a.a
            doApply(seat, a)
            -- announcing is once
            mustRefuse(seat, { k = "ann", a = a.a }, "second announce")
            check(s.turn == seat, "announce keeps the turn")
            a = moveOf()
            check(a.k == "play", "after the announce, a card")
          end
          check(a.k == "play" and refSet[a.c] and s.deck[a.i] == a.c, "move " .. ser(a) .. " not a legal card")
          check(not a.b or refBelo[a.c], "move claims a false belote")
          if a.b then belotes[#belotes + 1] = seat; totals.belotes = totals.belotes + 1 end
          if mayAnn then announcedBy[seat] = true end
          doApply(seat, a)
          check(not played[a.c], "card played twice")
          played[a.c] = true
          trick[#trick + 1] = a.c
        end
        -- trick done
        local w = winnerPos(con, trick)
        local wseat = (leader + w - 2) % 4 + 1
        local tp = 0
        for _, f in ipairs(trick) do tp = tp + points(con, f) end
        refPts[team(wseat)] = refPts[team(wseat)] + tp
        refTook[team(wseat)] = refTook[team(wseat)] + 1
        check(s.last and s.last.win == wseat and #s.last.cards == 4, "trick " .. trickNo .. " winner " ..
          tostring(s.last and s.last.win) .. " expected " .. wseat .. " (" .. table.concat(trick, " ") .. ", " .. con .. ")")
        check(s.pts[1] == refPts[1] and s.pts[2] == refPts[2], "card points after trick " .. trickNo)
        leader, lastWinner = wseat, wseat
        totals.tricks = totals.tricks + 1
      end
      local n = 0
      for _ in pairs(played) do n = n + 1 end
      check(n == 32, "32 cards played")
      for q = 1, 4 do check(#s.hands[q] == 0, "hands empty") end
      check(refPts[1] + refPts[2] == (con == "N" and 120 or con == "A" and 248 or 152), "card points total")
      check(s.phase == "score", "score phase after eight tricks")
      checkViews()
      -- clients: every card is face up now
      local showAll = {}
      for i = 1, 32 do showAll[i] = s.deck[i] end
      for q = 1, 4 do check(E.apply(clients[q], 0, { k = "show", cards = showAll }), "client show") end
      mustRefuse(1, { k = "score" }, "score by a seat")

      -- reference deal score
      local annPts, tied = refSettle(anns, belotes)
      if tied then totals.annTie = totals.annTie + 1 end
      local raw = { refPts[1] + annPts[1], refPts[2] + annPts[2] }
      raw[team(lastWinner)] = raw[team(lastWinner)] + 10
      if con == "N" then raw[1], raw[2] = raw[1] * 2, raw[2] * 2 end
      local valat = false
      for t = 1, 2 do
        if refTook[t] == 8 then raw[t] = raw[t] + 90; valat = true end
      end
      local d = team(decl)
      local o = 3 - d
      local pts, newHang = { 0, 0 }, 0
      if x > 1 then
        local all = refRoundSum(raw[1] + raw[2]) * x + hang
        if raw[1] == raw[2] then newHang = all
        else pts[raw[1] > raw[2] and 1 or 2] = all end
      elseif raw[d] > raw[o] then
        pts[d] = refRound(con, raw[d], false) + hang
        pts[o] = refRound(con, raw[o], true)
      elseif raw[d] < raw[o] then
        pts[o] = refRoundSum(raw[1] + raw[2]) + hang
        totals.inside = totals.inside + 1
      else
        pts[o] = refRound(con, raw[o], false)
        newHang = hang + refRound(con, raw[d], true)
        totals.hanging = totals.hanging + 1
      end
      if valat then totals.valat = totals.valat + 1 end
      doApply(0, { k = "score" })
      local res = s.res
      check(res.raw[1] == raw[1] and res.raw[2] == raw[2], string.format("raw %d:%d expected %d:%d (%s x%d)",
        res.raw[1], res.raw[2], raw[1], raw[2], con, x))
      check(res.pts[1] == pts[1] and res.pts[2] == pts[2], string.format("points %d:%d expected %d:%d (raw %d:%d %s x%d decl team %d hang %d)",
        res.pts[1], res.pts[2], pts[1], pts[2], raw[1], raw[2], con, x, d, hang))
      check(res.hang == newHang, "hanging " .. tostring(res.hang) .. " expected " .. newHang)
      check(res.valat == valat, "valat flag")
      score[1], score[2], hang = score[1] + pts[1], score[2] + pts[2], newHang
      check(s.score[1] == score[1] and s.score[2] == score[2] and s.hang == hang, "match score")
      for q = 1, 4 do
        check(deepEq(clients[q].score, s.score) and clients[q].hang == s.hang and deepEq(clients[q].res.pts, res.pts),
          "client " .. q .. " scored differently")
        check(E.foul(clients[q]) == nil, "client " .. q .. " sees a foul")
      end
      if lock then
        local same, path = deepEq(lock, s)
        check(same, "restored copy diverged at " .. tostring(path))
        lock = nil
      end
      -- match end by the rules: 151+, more than the other, not on a valat
      local want
      for t = 1, 2 do
        if score[t] >= 151 and score[t] > score[3 - t] and not valat then want = t end
      end
      local wantEngine = want and pts[want] > 0 and want or nil
      if want and not wantEngine then totals.blockedZero = totals.blockedZero + 1 end
      for t = 1, 2 do
        if score[t] >= 151 and score[t] > score[3 - t] and valat then totals.blockedValat = totals.blockedValat + 1 end
      end
      if wantEngine then
        check(s.phase == "match" and s.winner == wantEngine, "match should end, winner " .. wantEngine)
        totals.wins151 = totals.wins151 + 1
      else
        check(s.phase == "deal", "match should go on (score " .. score[1] .. ":" .. score[2] .. ")")
        refFirst = refFirst % 4 + 1
      end
    end
    if s.phase == "deal" then
      -- the next deal: the hands of the clients were sorted above; keep the lockstep simple
      lock = nil
    end
  end
  local r = E.result(s)
  check(r and r.winners[1] == s.winner and r.winners[2] == s.winner + 2, "result")
  totals.matches = totals.matches + 1
end

local t0 = os.clock()
local from, to = ONLY or 1, ONLY or MATCHES
for m = from, to do
  local okay, err = pcall(playMatch, m)
  if not okay and err ~= "soak-fail" then
    failures = failures + 1
    if #failLog < 15 then
      failLog[#failLog + 1] = string.format("match %d (seed %d): error %s\n    moves: %s", m, curSeed, tostring(err),
        table.concat(curLog or {}, " "):sub(-1500))
    end
  end
end

print(string.format("belot soak: seed %d, %d matches (%s), %d deals (%d passed out), %d tricks, %.1fs",
  SEED, totals.matches, (function() local p = {} for k, v in pairs(totals.modes) do p[#p + 1] = k .. " " .. v end table.sort(p) return table.concat(p, ", ") end)(),
  totals.deals, totals.passed, totals.tricks, os.clock() - t0))
local cs = {}
for _, b in ipairs({ "C", "D", "H", "S", "N", "A" }) do cs[#cs + 1] = b .. " " .. (totals.contracts[b] or 0) end
print("contracts: " .. table.concat(cs, ", ") .. string.format("; contra %d, recontra %d; inside %d, hanging %d, valat %d",
  totals.x2, totals.x4, totals.inside, totals.hanging, totals.valat))
print(string.format("announces %d (tied sequences %d), belotes %d; illegal moves refused %d; snapshots %d; view checks %d",
  totals.anns, totals.annTie, totals.belotes, totals.illegal, totals.snaps, totals.views))
print(string.format("matches won %d; a 151+ lead not closed on a valat deal %d, on a deal the leader scored 0 in %d; N remainder 5: %d",
  totals.wins151, totals.blockedValat, totals.blockedZero, stats.r5N))
print(string.format("checks %d, failures %d", checks, failures))
for _, f in ipairs(failLog) do print("FAIL " .. f) end
os.exit(failures == 0 and 0 or 1)
