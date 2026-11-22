local ns = Loader.ns()
local E, HC = ns.Engines.holdem, ns.HoldemCash

-- ------------------------------------------------------------------ helpers

local function split(str) local t = {} for c in str:gmatch("%S+") do t[#t + 1] = c end return t end

-- the full deck of the current hand: holes = {[seat] = "AS KD"}, board = five faces (flop turn river)
local function deckFor(s, holes, board)
  local n, d, used = #s.order, {}, {}
  local function put(i, f) assert(not used[f], "duplicate " .. f); d[i] = f; used[f] = true end
  for j, seat in ipairs(s.order) do
    if holes[seat] then local c = split(holes[seat]); put(j, c[1]); put(n + j, c[2]) end
  end
  if board then
    local b, pos = split(board), { 2 * n + 2, 2 * n + 3, 2 * n + 4, 2 * n + 6, 2 * n + 8 }
    for k, i in ipairs(pos) do put(i, b[k]) end
  end
  local r = 1
  for i = 1, 52 do
    if not d[i] then
      while used[E.DECK[r]] do r = r + 1 end
      put(i, E.DECK[r])
    end
  end
  return d
end

local function apply(s, seat, a)
  local r, why = E.apply(s, seat, a)
  ok(r, "seat " .. seat .. " " .. tostring(a.k) .. " rejected: " .. tostring(why))
end

-- to the end of the hand: every street and showdown dealt, every bettor left checks
local function checkdown(s)
  while s.phase ~= "done" do
    if s.phase == "bet" then apply(s, s.turn, { k = "check" })
    else apply(s, 0, (E.system(s))) end
  end
end

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
  if s.phase ~= "done" then checkdown(s) end
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
          balanced(s)
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
