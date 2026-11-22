local ns = Loader.ns()
local E, HC = ns.Engines.holdem, ns.HoldemCash

-- ------------------------------------------------------------------ helpers

local HH = require("holdem")(E)
local deckFor, apply, checkdown = HH.deckFor, HH.apply, HH.checkdown

-- a staked table at chairs 1..#stacks with those chips (opts.first = script.first)
local function table_(stacks, first)
  local seats = {}
  for i = 1, #stacks do seats[i] = true end
  local s = E.new({ seats = seats, first = first, staked = true })
  for i, c in ipairs(stacks) do s.seats[i].chips = c end
  return s
end

-- script = { first, holes, board, acts = { {seat, k, to} | {0, "leave", seat} | {0, "void"} } }; the hand is
-- played to its end (checked down) unless it was voided
local function hand(s, script)
  apply(s, 0, { k = "hand" })
  apply(s, 0, { k = "deal", deck = deckFor(s, script.holes or {}, script.board) })
  for _, a in ipairs(script.acts or {}) do
    if a[1] == 0 and a[2] == "leave" then apply(s, 0, { k = "leave", seat = a[3] })
    elseif a[1] == 0 then apply(s, 0, { k = a[2] })
    else apply(s, a[1], { k = a[2], to = a[3] }) end
  end
  checkdown(s)
  return s
end

local function play(stacks, script) return hand(table_(stacks, script.first), script) end

-- for every seat i of the hand: the sum of its pair nets is what it won less what it put in
local function balanced(s)
  local L, m = s.last, { took = s.last.took }
  for i, put in pairs(L.contrib) do
    local n = 0
    for j = 1, 9 do if j ~= i then n = n + HC.net(m, i, j) end end
    eq(n, (L.won[i] or 0) - put, "seat " .. i .. " of hand " .. L.hand)
  end
end

-- for every pair of the hand: what w took from j lies between the floored and the rounded-up sums of j's
-- equal shares (from[j] / #winners) over the pots w won and j did not; nothing when there is no such pot
local function bounded(s)
  local lo, hi = {}, {}
  for _, pot in ipairs(s.last.pots) do
    local n, isW = #pot.winners, {}
    for _, w in ipairs(pot.winners) do isW[w] = true end
    for j, x in pairs(pot.from) do
      if not isW[j] then
        for _, w in ipairs(pot.winners) do
          local key = w * 10 + j
          lo[key] = (lo[key] or 0) + math.floor(x / n); hi[key] = (hi[key] or 0) + math.ceil(x / n)
        end
      end
    end
  end
  for w = 1, 9 do
    for j = 1, 9 do
      local t, key = s.last.took[w] and s.last.took[w][j] or 0, w * 10 + j
      if not (t >= (lo[key] or 0) and t <= (hi[key] or 0)) then
        error("hand " .. s.last.hand .. ": took[" .. w .. "][" .. j .. "] = " .. t .. " outside "
          .. (lo[key] or 0) .. ".." .. (hi[key] or 0), 2)
      end
    end
  end
end

local BOARD = "2C 7D 9H JS 3C"

-- stacks 51 / 125 / 300: seat 3 (the button, first to act) goes all in, 1 and 2 call all in short;
-- seats 1 and 2 tie (aces and kings), seat 3 has nothing
local ALLIN_SPLIT = { first = 3, holes = { [1] = "AS KD", [2] = "AH KC", [3] = "2C 3D" }, board = "AD KH 7S 8C 9D",
  acts = { { 3, "allin" }, { 1, "call" }, { 2, "call" } } }

-- ------------------------------------------------------------------ tests

describe("holdem cash: the attribution of a pot", function()
  it("declares the chip and the buy-in range", function()
    eq({ HC.CHIP, HC.MIN_BB, HC.MAX_BB }, { 100, 40, 100 })
    eq(HC.new("top"), { rebuy = "top", took = {}, outN = 0, outs = {}, left = {} })
  end)
  it("one pot, one winner: each loser's chips are the winner's", function()
    local t = HC.attribute({ { amount = 300, winners = { 2 }, from = { [1] = 100, [2] = 100, [3] = 100 } } })
    eq(t, { [2] = { [1] = 100, [3] = 100 } })
  end)
  it("a split pot (a synthetic one): both winners take half of each loser, the odd chip to the first", function()
    local t = HC.attribute({ { amount = 305, winners = { 3, 1 }, from = { [1] = 100, [2] = 105, [3] = 100 } } })
    eq(t, { [3] = { [2] = 53 }, [1] = { [2] = 52 } })
  end)
  it("odd chips go round the winners across the contributors of one pot, ascending by seat", function()
    -- winners 4, 2, 6 paid 10 each; seats 1, 3, 5 put in 11, 2, 1: remainders 2, 2, 1 go 4 2 | 6 4 | 2
    local t = HC.attribute({ { amount = 44, winners = { 4, 2, 6 },
      from = { [5] = 1, [1] = 11, [3] = 2, [2] = 10, [4] = 10, [6] = 10 } } })
    eq(t, { [4] = { [1] = 4, [3] = 1 }, [2] = { [1] = 4, [5] = 1 }, [6] = { [1] = 3, [3] = 1 } })
    -- what finish pays: share 14, odd 2 -> 15, 15, 14; less each winner's own 10
    local function row(w) local n = 0 for _, x in pairs(t[w]) do n = n + x end return n end
    eq({ row(4), row(2), row(6) }, { 15 - 10, 15 - 10, 14 - 10 })
  end)
  it("add sums the hands and net is one pair's balance", function()
    local c = HC.new("bust")
    HC.add(c, { [2] = { [1] = 30 } }); HC.add(c, { [1] = { [2] = 10, [3] = 5 } }); HC.add(c, { [2] = { [1] = 2 } })
    eq(c.took, { [2] = { [1] = 32 }, [1] = { [2] = 10, [3] = 5 } })
    eq({ HC.net(c, 2, 1), HC.net(c, 1, 2), HC.net(c, 1, 3), HC.net(c, 3, 1), HC.net(c, 4, 5) }, { 22, -22, 5, -5, 0 })
  end)
end)

describe("holdem cash: the staked state", function()
  it("a staked state has the cash table, the rebuy mode resolved", function()
    eq(E.new({ seats = { true, true }, staked = true }).cash, HC.new("bust"))
    eq(E.new({ seats = { true, true }, staked = true, opt = { rebuy = "none" } }).cash.rebuy, "none")
    eq(E.new({ seats = { true, true }, staked = true, opt = { rebuy = "top" } }).cash.rebuy, "top")
    eq(E.new({ seats = { true, true }, staked = true, opt = { rebuy = "free" } }).cash.rebuy, "bust")
  end)
  it("a fun state has no cash and its last has no took", function()
    local s = E.new({ seats = { true, true } })
    eq(s.cash, nil)
    hand(s, { holes = { [1] = "AS AD", [2] = "KS KD" }, board = BOARD, acts = { { 1, "call" } } })
    eq(s.last.took, nil); eq(s.last.pots[1].from, nil); eq(s.cash, nil)
  end)
  it("three all-ins, a split main pot and an odd chip", function()
    -- stacks 51 / 125 / 300, all in; seats 1 and 2 split the main pot of 153, seat 2 wins the side pot,
    -- seat 3 wins nothing but its uncalled layer
    local s = play({ 51, 125, 300 }, ALLIN_SPLIT)
    eq(s.last.pots[1].from, { [1] = 51, [2] = 51, [3] = 51 }); eq(s.last.pots[2].from, { [2] = 74, [3] = 74 })
    local w = s.last.pots[1].winners                      -- the odd chip is the first winner's
    local side = function(i) return i == 2 and 74 or 0 end
    eq(s.last.took[w[1]][3] - side(w[1]), 26); eq(s.last.took[w[2]][3] - side(w[2]), 25)
    eq(HC.net(s.cash, 1, 2), 0); eq(HC.net(s.cash, 1, 3) + HC.net(s.cash, 2, 3), 125)
    eq(s.last.took, { [1] = { [3] = 26 }, [2] = { [3] = 99 } }); balanced(s)
  end)
  it("everyone folds to a raise: the winner takes the blinds, the uncalled raise is nobody's", function()
    local s = play({ 1000, 1000, 1000 }, { acts = { { 1, "raise", 30 }, { 2, "fold" }, { 3, "fold" } } })
    eq(s.last.pots, { { amount = 25, eligible = { 1 }, winners = { 1 }, from = { [1] = 10, [2] = 5, [3] = 10 } } })
    eq(s.last.took, { [1] = { [2] = 5, [3] = 10 } }); eq(s.cash.took, s.last.took); balanced(s)
  end)
  it("folded chips in a side pot go to that pot's winner", function()
    -- seat 2 all in for 101 wins the main pot; seat 1 folds on the flop after 301, seat 3 beats seat 4
    local s = play({ 1000, 101, 1000, 1000 }, { holes = { [2] = "AS AD", [3] = "KS KD", [4] = "QS QD", [1] = "8S 8D" },
      board = BOARD, acts = { { 4, "raise", 301 }, { 1, "call" }, { 2, "call" }, { 3, "call" }, { 0, "street" },
        { 3, "bet", 100 }, { 4, "call" }, { 1, "fold" } } })
    eq(s.last.pots[2], { amount = 800, eligible = { 3, 4 }, winners = { 3 }, from = { [1] = 200, [3] = 300, [4] = 300 } })
    eq(s.last.took, { [2] = { [1] = 101, [3] = 101, [4] = 101 }, [3] = { [1] = 200, [4] = 300 } }); balanced(s)
  end)
  it("a leaver's dead layer joins the pot below", function()
    -- 50 and 100 all in; seats 3 and 4 put in 200 each and leave: their top layer is nobody's to win
    local s = play({ 50, 100, 1000, 1000 }, { holes = { [1] = "AS AD", [2] = "KS KD", [3] = "QS QD", [4] = "8S 8D" },
      board = BOARD, acts = { { 4, "raise", 200 }, { 1, "call" }, { 2, "call" }, { 3, "call" },
        { 0, "leave", 3 }, { 0, "leave", 4 } } })
    eq(s.last.pots, { { amount = 200, eligible = { 2, 1 }, winners = { 1 }, from = { [1] = 50, [2] = 50, [3] = 50, [4] = 50 } },
      { amount = 350, eligible = { 2 }, winners = { 2 }, from = { [2] = 50, [3] = 150, [4] = 150 } } })
    eq(s.last.took, { [1] = { [2] = 50, [3] = 50, [4] = 50 }, [2] = { [3] = 150, [4] = 150 } }); balanced(s)
    eq(s.last.left, { [3] = 800, [4] = 800 })
  end)
  it("a voided hand writes nothing", function()
    local s = play({ 1000, 1000, 1000 }, { acts = { { 1, "raise", 30 }, { 2, "fold" }, { 3, "fold" } } })
    local before = E.snapshot(s).cash
    hand(s, { acts = { { 2, "raise", 40 }, { 0, "void" } } })
    eq(s.last.void, true); eq(s.last.took, nil); eq(s.cash, before)
  end)
  it("the matrix adds up over hands", function()
    local s = play({ 1000, 1000, 1000 }, { acts = { { 1, "raise", 30 }, { 2, "fold" }, { 3, "fold" } } })
    local first = E.snapshot(s).last.took
    hand(s, { holes = { [3] = "AS AD", [1] = "KS KD", [2] = "QS QD" }, board = BOARD,
      acts = { { 2, "call" }, { 3, "call" }, { 1, "check" } } })
    local second = s.last.took
    eq(first, { [1] = { [2] = 5, [3] = 10 } }); eq(second, { [3] = { [1] = 10, [2] = 10 } })
    eq(s.cash.took, { [1] = { [2] = 5, [3] = 10 }, [3] = { [1] = 10, [2] = 10 } })
    eq({ HC.net(s.cash, 1, 3), HC.net(s.cash, 3, 2) }, { 0, 10 })
  end)
end)

-- ------------------------------------------------------------------ fuzz

-- seeded Park-Miller LCG (exact in doubles)
local function lcg(seed)
  local x = seed % 2147483646 + 1
  return function(lo, hi)
    x = x * 16807 % 2147483647
    return lo + x % (hi - lo + 1)
  end
end

local function shuffled(rnd)
  local d = {}
  for i, f in ipairs(E.DECK) do d[i] = f end
  for i = #d, 2, -1 do local j = rnd(1, i); d[i], d[j] = d[j], d[i] end
  return d
end

describe("holdem cash: fuzz", function()
  it("fuzz: 300 random hands at 2 to 6 seats", function()
    local stats, played = { split = 0, side = 0, dead = 0, voids = 0, odd = 0 }, 0
    local function check(cond, msg) if not cond then error(msg, 2) end end
    for seed = 1, 6 do
      local rnd = lcg(seed * 104729)
      local s = E.new({ seats = {}, first = rnd(1, 9), staked = true, opt = { blinds = 10 } })
      local sum = {}
      for _ = 1, 50 do
        -- 2 to 6 chairs, each with 1 to 400 chips
        local want = rnd(2, 6)
        for i = 1, 9 do
          local st = s.seats[i]
          if st then st.chips, st.out = rnd(1, 400), false end
        end
        local n = 0
        for i = 1, 9 do if s.seats[i] then n = n + 1 end end
        while n > want do
          local i = rnd(1, 9)
          if s.seats[i] then apply(s, 0, { k = "leave", seat = i }); n = n - 1 end
        end
        while n < want do
          local i = rnd(1, 9)
          if not s.seats[i] then apply(s, 0, { k = "join", seat = i }); s.seats[i].chips = rnd(1, 400); n = n + 1 end
        end
        apply(s, 0, { k = "hand" }); apply(s, 0, { k = "deal", deck = shuffled(rnd) })
        while s.phase ~= "done" do
          if s.phase == "bet" then
            local legal = E.legal(s, s.turn)
            local a = legal[rnd(1, #legal)]
            if a.max then a = { k = a.k, to = rnd(a.to, a.max) } end
            apply(s, s.turn, a)
            if s.phase ~= "done" then
              local r = rnd(1, 60)
              if r == 1 then apply(s, 0, { k = "void" })
              elseif r <= 4 then
                local v = s.order[rnd(1, #s.order)]
                if s.seats[v] and not s.seats[v].leaving then apply(s, 0, { k = "leave", seat = v }) end
              end
            end
          else
            apply(s, 0, (E.system(s)))
          end
        end
        played = played + 1
        local L = s.last
        if L.void then
          stats.voids = stats.voids + 1; check(L.took == nil, "a void wrote took")
        else
          balanced(s); bounded(s)
          for w, row in pairs(L.took) do
            for j, x in pairs(row) do
              check(w ~= j and x > 0 and x % 1 == 0, "bad entry " .. w .. "/" .. j)
              sum[w] = sum[w] or {}; sum[w][j] = (sum[w][j] or 0) + x
            end
          end
          for _, pot in ipairs(L.pots) do
            if #pot.winners > 1 then
              stats.split = stats.split + 1
              if pot.amount % #pot.winners ~= 0 then stats.odd = stats.odd + 1 end
            end
            local paid, live = 0, {}
            for _, i in ipairs(pot.eligible) do live[i] = true end
            for i, c in pairs(pot.from) do paid = paid + c; if not live[i] then stats.dead = stats.dead + 1 end end
            check(paid == pot.amount, "from ~= amount")
          end
          if #L.pots > 1 then stats.side = stats.side + 1 end
        end
        for w, row in pairs(s.cash.took) do
          for j, x in pairs(row) do check(w ~= j and x > 0, "cash.took " .. w .. "/" .. j) end
        end
        eq(s.cash.took, sum, "the matrix is the sum of the hands")
      end
    end
    eq(played, 300)
    ok(stats.side >= 20, "side pots " .. stats.side); ok(stats.split >= 1, "splits " .. stats.split)
    ok(stats.odd >= 1, "odd chips " .. stats.odd); ok(stats.voids >= 1, "voids " .. stats.voids)
    ok(stats.dead >= 20, "folded chips " .. stats.dead)
  end)
end)

-- ------------------------------------------------------------------ buy-in, rebuy, table stakes, cash-out

local function T(opt) return E.new({ staked = true, seats = { true, true, true }, names = { "A", "B", "C" }, opt = opt }) end

local function buy(s, seat, n) apply(s, seat, { k = "buy", n = n }) end

local function codes(...) return { ... } end

-- for every occupied seat i: the sum of its pair nets over the occupied seats is chips - bought - cleared
local function identity(s, msg)
  for i = 1, 9 do
    local st = s.seats[i]
    if st then
      local n = 0
      for j = 1, 9 do if j ~= i and s.seats[j] then n = n + HC.net(s.cash, i, j) end end
      eq(n, st.chips - st.bought - st.cleared, (msg or "identity") .. ", seat " .. i)
    end
  end
end

-- seat 1 takes 120 from seat 2 heads-up (seat 3 has not bought yet), then loses 30 to seat 3:
-- chips 1090 / 880 / 1030, each bought 1000
local function twoHands(opt)
  local s = T(opt)
  buy(s, 1, 1000); buy(s, 2, 1000)
  hand(s, { holes = { [1] = "AS AD", [2] = "KS KD" }, board = BOARD, acts = { { 1, "raise", 120 }, { 2, "call" } } })
  eq(s.last.took, { [1] = { [2] = 120 } }); identity(s)
  buy(s, 3, 1000)
  hand(s, { holes = { [3] = "AS AD", [1] = "KS KD", [2] = "QS QD" }, board = BOARD,
    acts = { { 2, "fold" }, { 3, "raise", 30 }, { 1, "call" } } })
  eq(s.last.took, { [3] = { [1] = 30 } })
  eq({ s.seats[1].chips, s.seats[2].chips, s.seats[3].chips }, { 1090, 880, 1030 }); identity(s)
  return s
end

describe("holdem cash: buy-in, rebuy, table stakes, cash-out", function()
  it("a staked seat sits with nothing and buys 40 to 100 big blinds", function()
    local s = T()
    eq(s.seats[1], { chips = 0, out = true, leaving = false, who = "A", bought = 0, cleared = 0 })
    eq(E.system(s), nil)                                   -- nobody can play yet
    eq({ E.buyRange(s, 1) }, { 400, 1000 })
    eq({ E.apply(s, 1, { k = "buy", n = 399 }) }, { nil, "amount" })
    eq({ E.apply(s, 1, { k = "buy", n = 1001 }) }, { nil, "amount" })
    eq(E.apply(s, 1, { k = "buy", n = 600 }), true); eq(E.apply(s, 2, { k = "buy", n = 1000 }), true)
    eq(s.seats[1].chips, 600); eq(s.seats[1].bought, 600); eq(s.seats[1].out, false)
    eq(E.system(s).k, "hand")
    identity(s)
  end)
  it("declares the cash game, the chip and the stake of a table", function()
    eq({ E.cashGame, E.CHIP, E.stakeOf({ blinds = 20 }) }, { true, 100, 2000 })
    eq(T({ blinds = 50 }).bb, 50); eq({ E.buyRange(T({ blinds = 50 }), 2) }, { 2000, 5000 })
    eq(codes(E.apply(T(), 1, { k = "buy", n = 400.5 })), { nil, "amount" })
  end)
  it("the three rebuy modes", function()
    for mode, want in pairs({ none = { nil, "rebuy" }, bust = { 400, 1000 }, top = { 400, 1000 } }) do
      local s = T({ rebuy = mode }); E.apply(s, 1, { k = "buy", n = 400 }); s.seats[1].chips = 0
      eq({ E.buyRange(s, 1) }, want, mode)
    end
    local s = T({ rebuy = "top" }); E.apply(s, 1, { k = "buy", n = 400 })
    eq({ E.buyRange(s, 1) }, { 1, 600 }); s.seats[1].chips = 1000; eq({ E.buyRange(s, 1) }, { nil, "full" })
    s = T({ rebuy = "bust" }); E.apply(s, 1, { k = "buy", n = 400 }); eq({ E.buyRange(s, 1) }, { nil, "rebuy" })
  end)
  it("a top-up adds to the seat and its buys", function()
    local s = T({ rebuy = "top" }); buy(s, 1, 400); buy(s, 1, 250)
    eq({ s.seats[1].chips, s.seats[1].bought }, { 650, 650 }); eq({ E.buyRange(s, 1) }, { 1, 350 })
    eq(codes(E.apply(s, 1, { k = "buy", n = 351 })), { nil, "amount" }); identity(s)
  end)
  it("a fun table knows neither action and its state is unchanged", function()
    local f = E.new({ seats = { true, true } })
    eq((E.apply(f, 1, { k = "buy", n = 500 })), nil); eq((E.apply(f, 1, { k = "cashout" })), nil)
    eq(f.seats[1], { chips = 1000, out = false, leaving = false }); eq(f.cash, nil)
    apply(f, 0, { k = "join", seat = 3, who = "D" }); eq(f.seats[3], { chips = 1000, out = false, leaving = false })
  end)
  it("no buy and no cashout while I am dealt in", function()
    local s = T(); buy(s, 1, 1000); buy(s, 2, 1000); apply(s, 0, { k = "leave", seat = 3 })
    eq(s.cash.outs, {}); eq(s.cash.outN, 0)               -- a seat that never bought is not settled
    apply(s, 0, { k = "hand" }); apply(s, 0, { k = "deal", deck = deckFor(s, {}) })
    for _, i in ipairs(s.order) do
      eq(codes(E.apply(s, i, { k = "buy", n = 500 })), { nil, "hand" })
      eq(codes(E.apply(s, i, { k = "cashout" })), { nil, "hand" })
      eq({ E.buyRange(s, i) }, { nil, "hand" })
    end
    apply(s, 0, { k = "join", seat = 3, who = "D" })       -- sat down during the hand: not dealt in
    eq({ E.buyRange(s, 3) }, { 400, 1000 }); buy(s, 3, 400)
    eq(E.apply(s, 3, { k = "cashout" }), true); eq(s.seats[3].back, 400)
    checkdown(s); identity(s)
  end)
  it("a cashout settles my pairs and keeps my chair", function()
    local s = twoHands()
    apply(s, 1, { k = "cashout" })
    eq(s.cash.outs, { { n = 1, seat = 1, who = "A", chips = 1090, bought = 1000, net = { [2] = 120, [3] = -30 },
      names = { [2] = "B", [3] = "C" } } })
    for j = 2, 3 do eq({ HC.net(s.cash, 1, j), HC.net(s.cash, j, 1) }, { 0, 0 }) end
    eq({ s.seats[2].cleared, s.seats[3].cleared }, { -120, 30 })
    eq(s.seats[1], { chips = 0, out = true, leaving = false, who = "A", bought = 0, cleared = 0, back = 1090 })
    eq(s.cash.left, { A = 1090 }); identity(s)
    eq(codes(E.apply(s, 1, { k = "cashout" })), { nil, "seat" })
    eq({ E.buyRange(s, 1) }, { 1000, 1000 })               -- it comes back with what it took, at most 100 BB
  end)
  it("a stand between hands settles and empties the chair", function()
    local s = twoHands()
    apply(s, 0, { k = "leave", seat = 1 })
    eq(s.cash.outs, { { n = 1, seat = 1, who = "A", chips = 1090, bought = 1000, net = { [2] = 120, [3] = -30 },
      names = { [2] = "B", [3] = "C" } } })
    eq(s.seats[1], false); eq(s.cash.left, { A = 1090 }); eq(s.cash.took, {}); identity(s)
  end)
  it("a stand in a hand settles when the hand ends, with the chips it folded", function()
    local s = T(); buy(s, 1, 1000); buy(s, 2, 1000); buy(s, 3, 1000)
    apply(s, 0, { k = "hand" }); apply(s, 0, { k = "deal", deck = deckFor(s, {}) })
    apply(s, 1, { k = "raise", to = 100 }); apply(s, 2, { k = "call" }); apply(s, 3, { k = "call" })
    apply(s, 0, { k = "leave", seat = 1 })
    eq(s.cash.outs, {}); eq(s.seats[1].leaving, true)
    apply(s, 0, (E.system(s))); apply(s, 2, { k = "bet", to = 50 })
    eq(s.cash.outs, {})
    apply(s, 3, { k = "fold" })                            -- the action that ends the hand
    eq(s.cash.outs, { { n = 1, seat = 1, who = "A", chips = 900, bought = 1000, net = { [2] = -100 },
      names = { [2] = "B" } } })
    eq(s.last.left, { [1] = 900 }); eq(s.seats[1], false); identity(s)
  end)
  it("two leavers of one hand are settled at one action, their pair once", function()
    local s = twoHands()
    apply(s, 0, { k = "hand" }); apply(s, 0, { k = "deal", deck = deckFor(s, {}) })
    apply(s, 0, { k = "leave", seat = 1 }); eq(s.cash.outs, {})
    apply(s, 0, { k = "leave", seat = 2 })                 -- seat 3 wins the blinds: the hand ends here
    eq(s.cash.outs, {
      { n = 1, seat = 1, who = "A", chips = 1085, bought = 1000, net = { [2] = 120, [3] = -35 }, names = { [2] = "B", [3] = "C" } },
      { n = 2, seat = 2, who = "B", chips = 875, bought = 1000, net = { [3] = -5 }, names = { [3] = "C" } } })
    eq(s.last.took, { [3] = { [1] = 5, [2] = 5 } })                -- seat 2's second 5 was uncalled
    eq({ s.seats[1], s.seats[2] }, { false, false }); eq(s.seats[3].cleared, 40); identity(s)
  end)
  it("both blinds leave during the deal: the button wins them, and it balances", function()
    local s = T(); buy(s, 1, 1000); buy(s, 2, 1000); buy(s, 3, 1000)
    apply(s, 0, { k = "hand" }); eq({ s.button, s.sbSeat, s.bbSeat, s.phase }, { 1, 2, 3, "deal" })
    apply(s, 0, { k = "leave", seat = 2 }); apply(s, 0, { k = "leave", seat = 3 })
    eq(s.phase, "done"); eq(s.last.took, { [1] = { [2] = 5, [3] = 5 } }); balanced(s); bounded(s)
    eq(s.last.left, { [2] = 995, [3] = 995 })
    eq(s.cash.outs, {
      { n = 1, seat = 2, who = "B", chips = 995, bought = 1000, net = { [1] = -5 }, names = { [1] = "A" } },
      { n = 2, seat = 3, who = "C", chips = 995, bought = 1000, net = { [1] = -5 }, names = { [1] = "A" } } })
    eq(s.seats[1].chips, 1010); identity(s)
  end)
  it("the close settles every seat, each pair once", function()
    local s = twoHands()
    hand(s, { holes = { [2] = "AS AD", [1] = "KS KD", [3] = "QS QD" }, board = BOARD,
      acts = { { 3, "call" }, { 1, "call" }, { 2, "check" } } })
    eq(s.last.took, { [2] = { [1] = 10, [3] = 10 } }); identity(s)
    apply(s, 0, { k = "close" })
    eq(s.phase, "closed"); eq(E.over(s), true)
    eq(s.cash.outs, {
      { n = 1, seat = 1, who = "A", chips = 1080, bought = 1000, net = { [2] = 110, [3] = -30 }, names = { [2] = "B", [3] = "C" } },
      { n = 2, seat = 2, who = "B", chips = 900, bought = 1000, net = { [3] = 10 }, names = { [3] = "C" } },
      { n = 3, seat = 3, who = "C", chips = 1020, bought = 1000, net = {}, names = {} } })
    for i, c in ipairs({ 1080, 900, 1020 }) do
      eq(s.seats[i], { chips = 0, out = true, leaving = false, who = ({ "A", "B", "C" })[i], bought = 0, cleared = 0, back = c })
    end
    eq(s.cash.took, {}); identity(s)
  end)
  it("a close during a hand settles every seat when the hand ends", function()
    local s = T(); buy(s, 1, 1000); buy(s, 2, 1000)
    apply(s, 0, { k = "hand" }); apply(s, 0, { k = "deal", deck = deckFor(s, { [1] = "AS AD", [2] = "KS KD" }, BOARD) })
    apply(s, 0, { k = "close" }); eq(s.cash.outs, {})
    eq(codes(E.apply(s, 0, { k = "join", seat = 4, who = "D" })), { nil, "phase" })
    apply(s, 1, { k = "call" }); apply(s, 2, { k = "check" }); eq(s.cash.outs, {})
    checkdown(s)
    eq(s.phase, "closed")
    eq(s.cash.outs, {
      { n = 1, seat = 1, who = "A", chips = 1010, bought = 1000, net = { [2] = 10 }, names = { [2] = "B" } },
      { n = 2, seat = 2, who = "B", chips = 990, bought = 1000, net = {}, names = {} } })
    eq({ s.seats[1].chips, s.seats[2].chips, s.seats[3].chips }, { 0, 0, 0 }); eq(E.system(s), nil); identity(s)
  end)
  it("standing and sitting again gives no fresh stack", function()
    for _, mode in ipairs({ "none", "bust" }) do
      local s = T({ rebuy = mode }); buy(s, 1, 400); buy(s, 2, 1000)
      hand(s, { holes = { [1] = "KS KD", [2] = "AS AD" }, board = BOARD, acts = { { 1, "allin" }, { 2, "call" } } })
      eq(s.seats[1].chips, 0)
      apply(s, 0, { k = "leave", seat = 1 }); eq(s.cash.left.A, 0)
      apply(s, 0, { k = "join", seat = 1, who = "A" }); eq(s.seats[1].back, 0)
      eq({ E.buyRange(s, 1) }, mode == "none" and { nil, "rebuy" } or { 400, 1000 }, mode)
      eq(s.seats[2].chips, 1400)
      apply(s, 0, { k = "leave", seat = 2 }); apply(s, 0, { k = "join", seat = 2, who = "B" })
      eq({ E.buyRange(s, 2) }, { 1000, 1000 })               -- left with 140 BB: comes back with 100
      for _, c in ipairs({ { 700, 700 }, { 150, 400 } }) do  -- left with 700, with 150 (the record says so)
        apply(s, 0, { k = "leave", seat = 2 }); s.cash.left.B = c[1]
        apply(s, 0, { k = "join", seat = 2, who = "B" }); eq({ E.buyRange(s, 2) }, { c[2], 1000 }, c[1])
      end
      apply(s, 0, { k = "leave", seat = 2 }); apply(s, 0, { k = "join", seat = 2, who = "D" })
      eq({ E.buyRange(s, 2) }, { 400, 1000 })               -- another name on that chair
    end
  end)
  it("a newcomer on a leaving chair is seated staked when the hand ends", function()
    local s = T(); buy(s, 1, 1000); buy(s, 2, 1000); buy(s, 3, 1000)
    apply(s, 0, { k = "hand" }); apply(s, 0, { k = "deal", deck = deckFor(s, {}) })
    apply(s, 0, { k = "leave", seat = 2 }); apply(s, 0, { k = "join", seat = 2, who = "D" })
    eq(s.seats[2].who, "B"); eq(s.seats[2].takenWho, "D")
    eq(codes(E.apply(s, 2, { k = "buy", n = 500 })), { nil, "hand" })   -- the chair is still the leaver's
    checkdown(s)
    eq(s.seats[2], { chips = 0, out = true, leaving = false, who = "D", bought = 0, cleared = 0 })
    eq({ E.buyRange(s, 2) }, { 400, 1000 }); identity(s)
  end)
  it("a newcomer who stands again before the hand ends is not seated", function()
    local s = T(); buy(s, 1, 1000); buy(s, 2, 1000); buy(s, 3, 1000)
    apply(s, 0, { k = "hand" }); apply(s, 0, { k = "deal", deck = deckFor(s, {}) })
    apply(s, 0, { k = "leave", seat = 2 }); apply(s, 0, { k = "join", seat = 2, who = "D" })
    apply(s, 0, { k = "leave", seat = 2 }); eq(s.seats[2].takenWho, nil)
    checkdown(s); eq(s.seats[2], false); eq(s.cash.outs[1].who, "B"); identity(s)
  end)
  it("a newcomer on a leaving chair owes nothing of the leaver's hand", function()
    local s = T(); buy(s, 1, 1000); buy(s, 2, 1000); buy(s, 3, 1000)
    apply(s, 0, { k = "hand" })
    apply(s, 0, { k = "deal", deck = deckFor(s, { [1] = "AS AD", [3] = "KS KD", [2] = "QS QD" }, BOARD) })
    apply(s, 1, { k = "call" }); apply(s, 2, { k = "call" }); apply(s, 3, { k = "check" })
    apply(s, 0, { k = "leave", seat = 2 }); apply(s, 0, { k = "join", seat = 2, who = "D" })
    checkdown(s)
    local rec = s.cash.outs[1]
    eq(rec, { n = 1, seat = 2, who = "B", chips = 990, bought = 1000, net = { [1] = -10 }, names = { [1] = "A" } })
    for j in pairs(rec.net) do eq(rec.names[j], s.seats[j].who) end
    eq(s.seats[2].who, "D"); eq(HC.net(s.cash, 2, 1), 0); eq(HC.net(s.cash, 2, 3), 0); identity(s)
    buy(s, 2, 400)
    hand(s, { acts = { { 2, "raise", 50 }, { 3, "fold" }, { 1, "fold" } } })
    eq(s.last.took, { [2] = { [1] = 10, [3] = 5 } })
    apply(s, 2, { k = "cashout" }); apply(s, 1, { k = "cashout" })
    eq(s.cash.outs, {
      { n = 2, seat = 2, who = "D", chips = 415, bought = 400, net = { [1] = 10, [3] = 5 }, names = { [1] = "A", [3] = "C" } },
      { n = 3, seat = 1, who = "A", chips = 1010, bought = 1000, net = { [3] = 10 }, names = { [3] = "C" } } })
    identity(s)
  end)
  it("E.buyRange gives the code buy would refuse", function()
    local s = T(); buy(s, 1, 1000); buy(s, 2, 1000)
    apply(s, 0, { k = "hand" })
    eq({ E.buyRange(s, 1) }, { nil, "hand" }); eq(codes(E.apply(s, 1, { k = "buy", n = 500 })), { nil, "hand" })
    apply(s, 0, { k = "close" })
    eq({ E.buyRange(s, 3) }, { nil, "phase" }); eq(codes(E.apply(s, 3, { k = "buy", n = 500 })), { nil, "phase" })
    s = T({ rebuy = "none" }); buy(s, 1, 400)
    eq({ E.buyRange(s, 1) }, { nil, "rebuy" }); eq(codes(E.apply(s, 1, { k = "buy", n = 400 })), { nil, "rebuy" })
    s = T({ rebuy = "top" }); buy(s, 1, 1000)
    eq({ E.buyRange(s, 1) }, { nil, "full" }); eq(codes(E.apply(s, 1, { k = "buy", n = 1 })), { nil, "full" })
    eq({ E.buyRange(s, 4) }, { nil, "seat" }); eq(codes(E.apply(s, 4, { k = "buy", n = 400 })), { nil, "seat" })
  end)
  it("the records of the last hand go at the next hand; the counter runs on", function()
    local s = twoHands()
    apply(s, 1, { k = "cashout" }); apply(s, 2, { k = "cashout" })
    eq({ #s.cash.outs, s.cash.outs[2].n, s.cash.outs[2].net }, { 2, 2, {} })
    buy(s, 1, 1000); buy(s, 2, 880)
    apply(s, 0, { k = "hand" }); eq(s.cash.outs, {}); eq(s.cash.outN, 2)
    apply(s, 0, { k = "deal", deck = deckFor(s, {}) }); checkdown(s)
    apply(s, 0, { k = "leave", seat = 3 })
    eq({ #s.cash.outs, s.cash.outs[1].n, s.cash.outs[1].who }, { 1, 3, "C" }); identity(s)
  end)
end)

-- 200 seeded sessions on the engine's own chips: buys within range, hands by random legal actions, cash-outs,
-- leaves and joins between and inside hands, voids, a close between or inside a hand. After every action
-- outside a hand: the identity, and every chip is a bought chip still at the table or one a record took out.
-- Every record's nets sum to its chips - bought - that seat's cleared just before it; its names are the
-- engine's own who of those chairs before the action.
describe("holdem cash: session fuzz", function()
  it("fuzz: 200 random sessions", function()
    local MODES, LEVELS = { "none", "bust", "top" }, { 10, 20, 50, 100, 200 }
    local stats = { buys = 0, rebuys = 0, cashouts = 0, refused = 0, amount = 0, inHand = 0, taken = 0,
      back = 0, closeInHand = 0, hands = 0, voids = 0, deal = 0, handOut = 0 }
    for seed = 1, 200 do
      local rnd = lcg(seed * 7919)
      local seats, names, want = {}, {}, rnd(2, 6)
      while want > 0 do
        local i = rnd(1, 9)
        if not seats[i] then seats[i] = true; names[i] = "P" .. i; want = want - 1 end
      end
      local s = E.new({ staked = true, seats = seats, names = names, first = rnd(1, 9),
        opt = { rebuy = MODES[rnd(1, 3)], blinds = LEVELS[rnd(1, 5)] } })
      local boughtAll, tookOut = 0, 0
      local function seatedName(nm)
        for i = 1, 9 do local st = s.seats[i]; if st and (st.who == nm or st.takenWho == nm) then return true end end
      end
      local function pickName()
        while true do local nm = "P" .. rnd(1, 12); if not seatedName(nm) then return nm end end
      end
      local function conserved(msg)
        local at = 0
        for i = 1, 9 do if s.seats[i] then at = at + s.seats[i].chips end end
        eq(at + tookOut, boughtAll, msg)
      end
      -- one action, its new records checked (a buy taken counts its chips as bought)
      local function step(seat, a)
        local cleared, who, n0, was = {}, {}, s.cash.outN, E.inHand(s)
        for i = 1, 9 do local st = s.seats[i]; if st then cleared[i], who[i] = st.cleared, st.who end end
        local r, why = E.apply(s, seat, a)
        if r and a.k == "buy" then boughtAll = boughtAll + a.n end
        local outs, adj = s.cash.outs, {}
        for k = #outs - (s.cash.outN - n0) + 1, #outs do
          local rec, sum = outs[k], 0
          for j, x in pairs(rec.net) do sum = sum + x; eq(rec.names[j], who[j], "names") end
          eq(rec.who, who[rec.seat], "who")
          eq(sum, rec.chips - rec.bought - (cleared[rec.seat] - (adj[rec.seat] or 0)), "record " .. rec.n)
          for j, x in pairs(rec.net) do adj[j] = (adj[j] or 0) + x end
          tookOut = tookOut + rec.chips
        end
        if not E.inHand(s) then identity(s, "seed " .. seed); conserved("seed " .. seed) end
        if was and not E.inHand(s) and s.cash.outN > n0 then stats.handOut = stats.handOut + 1 end
        return r, why
      end
      local function tryBuy(i)
        local st = s.seats[i]
        if not st then return end
        local lo, hi = E.buyRange(s, i)
        if not lo then
          eq(codes(step(i, { k = "buy", n = rnd(1, 30000) })), { nil, hi }); stats.refused = stats.refused + 1
          return
        end
        if rnd(1, 8) == 1 then
          eq(codes(step(i, { k = "buy", n = rnd(1, 2) == 1 and lo - 1 or hi + 1 })), { nil, "amount" })
          stats.amount = stats.amount + 1
          return
        end
        local n = rnd(lo, hi)
        if st.bought > 0 then stats.rebuys = stats.rebuys + 1 end
        if st.bought == 0 and (st.back or 0) > 0 then stats.back = stats.back + 1 end
        eq(step(i, { k = "buy", n = n }), true); stats.buys = stats.buys + 1
      end
      -- something a player or the host does at any time
      local function event(inside)
        local r, i = rnd(1, 10), rnd(1, 9)
        local st = s.seats[i]
        if r <= 4 then tryBuy(i)
        elseif r == 5 then
          if st then
            local dealt = inside and (st.leaving or (s.p[i] and not s.p[i].gone))
            local ok_, why = step(i, { k = "cashout" })
            if dealt then eq(why, "hand"); stats.inHand = stats.inHand + 1
            elseif ok_ then stats.cashouts = stats.cashouts + 1 end
          end
        elseif r <= 7 then
          if st then step(0, { k = "leave", seat = i }) end
        else
          if inside then                                   -- in a hand: a leaving chair first, if there is one
            for j = 1, 9 do
              local o = s.seats[j]
              if o and o.leaving and not o.taken then i, st = j, o end
            end
          end
          if not s.closing and (not st or (inside and st.leaving and not st.taken)) then
            if st then stats.taken = stats.taken + 1 end
            eq(step(0, { k = "join", seat = i, who = pickName() }), true)
          end
        end
      end
      local closed = false
      for _ = 1, 12 do
        for _ = 1, rnd(1, 8) do event(false) end
        if E.system(s) then
          step(0, { k = "hand" })
          if rnd(1, 8) == 1 then step(0, { k = "leave", seat = s.order[rnd(1, #s.order)] }); stats.deal = stats.deal + 1 end
          if s.phase == "deal" then step(0, { k = "deal", deck = shuffled(rnd) }) end
          while E.inHand(s) do
            if s.phase == "bet" then
              local legal = E.legal(s, s.turn)
              local a = legal[rnd(1, #legal)]
              if a.max then a = { k = a.k, to = rnd(a.to, a.max) } end
              eq(step(s.turn, a), true)
            else
              step(0, (E.system(s)))
            end
            if E.inHand(s) then
              local r = rnd(1, 40)
              if r <= 8 then event(true)
              elseif r == 9 and rnd(1, 3) == 1 then step(0, { k = "void" })
              elseif r == 10 and rnd(1, 8) == 1 and not s.closing then step(0, { k = "close" }); stats.closeInHand = stats.closeInHand + 1 end
            end
          end
          stats.hands = stats.hands + 1
          if s.last.void then stats.voids = stats.voids + 1 else balanced(s); bounded(s) end
          if s.phase == "closed" then closed = true; break end
        end
      end
      if not closed then step(0, { k = "close" }) end
      eq(s.phase, "closed")
      for i = 1, 9 do
        local st = s.seats[i]
        if st then eq({ st.chips, st.bought, st.cleared }, { 0, 0, 0 }, "closed seat " .. i) end
      end
      eq(s.cash.took, {}, "seed " .. seed .. ": the matrix is settled"); eq(tookOut, boughtAll)
    end
    for k, floor in pairs({ buys = 700, rebuys = 100, cashouts = 100, refused = 300, amount = 100, inHand = 15,
      taken = 8, back = 70, closeInHand = 10, hands = 500, voids = 15, deal = 60, handOut = 20 }) do
      ok(stats[k] >= floor, k .. " " .. stats[k])
    end
  end)
end)
