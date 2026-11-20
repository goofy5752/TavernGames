local ns = Loader.ns()
local E, H = ns.Engines.holdem, ns.HoldemEval

-- ------------------------------------------------------------------ helpers

-- a table with the given occupied seats; stacks = {[seat] = chips} overrides the starting stack
local function mk(seatList, o)
  o = o or {}
  local seats = {}
  for _, i in ipairs(seatList) do seats[i] = true end
  local s = E.new{ seats = seats, first = o.first, opt = o.opt }
  for i, c in pairs(o.stacks or {}) do s.seats[i].chips = c end
  return s
end

local function split(str) local t = {} for c in str:gmatch("%S+") do t[#t + 1] = c end return t end

-- full deck for the current hand: holes = {[seat] = "AS KD"}, board = five faces (flop turn river)
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

local function start(s, holes, board)
  ok(E.apply(s, 0, { k = "hand" }))
  ok(E.apply(s, 0, { k = "deal", deck = deckFor(s, holes or {}, board) }))
end

local function acts(s, list)
  for _, a in ipairs(list) do
    local r, why = E.apply(s, a[1], { k = a[2], to = a[3] })
    ok(r, "seat " .. a[1] .. " " .. a[2] .. " rejected: " .. tostring(why))
  end
end

local function sys(s)
  local a = E.system(s)
  ok(a, "no system action in phase " .. tostring(s.phase))
  ok(E.apply(s, 0, a))
  return a
end

local function runout(s) while s.phase == "street" or s.phase == "showdown" do sys(s) end end

-- everyone left checks the hand down to the end
local function checkdown(s)
  while s.phase ~= "done" do
    if s.phase == "bet" then acts(s, { { s.turn, "check" } }) else sys(s) end
  end
end

local function chips(s)
  local t = {}
  for i = 1, 9 do if s.seats[i] then t[i] = s.seats[i].chips end end
  return t
end

local function sum(t) local n = 0 for _, v in pairs(t) do n = n + v end return n end

local function kinds(list) local t = {} for i, a in ipairs(list) do t[i] = a.k end return t end

local function rejects(s, seat, a, why)
  local before = E.snapshot(s)
  eq({ E.apply(s, seat, a) }, { nil, why })
  eq(E.snapshot(s), before, "state changed by a rejected action")
end

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

-- every face a view may hold must be visible to that seat
local function assertViewClean(full, seat, v)
  local vis = {}
  for _, i in ipairs(full.board) do vis[i] = true end
  for st in pairs(full.shown) do for _, i in ipairs(full.p[st].cards) do vis[i] = true end end
  if seat ~= 0 and full.p[seat] then for _, i in ipairs(full.p[seat].cards) do vis[i] = true end end
  for i in pairs(v.deck) do ok(vis[i], "seat " .. seat .. " sees deck[" .. i .. "]") end
end

local function plain(v, depth)
  local t = type(v)
  if t == "table" then
    if depth > 20 then return false end
    for k, x in pairs(v) do if not plain(k, depth + 1) or not plain(x, depth + 1) then return false end end
    return true
  end
  return t == "string" or t == "number" or t == "boolean"
end

-- ------------------------------------------------------------------ tests

describe("holdem setup", function()
  it("declares the contract fields, options and the 52-card deck", function()
    eq({ E.id, E.minSeats, E.maxSeats, E.start }, { "holdem", 2, 9, "host" })
    eq(E.options, { { id = "stack", choices = { 1000, 2000, 5000 }, default = 1000 },
      { id = "blinds", choices = { 10, 20, 50 }, default = 10 } })
    eq(#E.DECK, 52); local seen = {}
    for _, f in ipairs(E.DECK) do ok(H.valid(f)); ok(not seen[f]); seen[f] = true end
    local s = mk({ 1, 2 }); eq(E.result(s), nil); eq(E.over(s), false)
  end)
  it("new takes the options, falls back to defaults, seats the occupied chairs", function()
    local s = mk({ 2, 5 }, { opt = { stack = 2000, blinds = 20 } })
    eq({ s.stack, s.bb, s.sb, s.phase }, { 2000, 20, 10, "idle" }); eq(chips(s), { [2] = 2000, [5] = 2000 })
    s = mk({ 1, 2 }, { opt = { stack = 7, blinds = 3 } }); eq({ s.stack, s.bb, s.sb }, { 1000, 10, 5 })
    s = mk({ 1, 2 }, { opt = { blinds = 50 } }); eq({ s.bb, s.sb }, { 50, 25 })
    s = E.new(); eq(chips(s), {}); eq(s.phase, "idle"); eq(E.system(s), nil)
  end)
  it("system asks for a hand only with two playing seats", function()
    eq({ E.system(mk({ 1, 2 })) }, { { k = "hand" }, E.IDLE_DELAY }); eq(E.system(mk({ 4 })), nil)
    local s = mk({ 4 }); rejects(s, 0, { k = "hand" }, "players")
    s = mk({ 1, 2 }); ok(E.apply(s, 0, { k = "hand" })); eq(E.system(s), nil); rejects(s, 0, { k = "hand" }, "phase")
  end)
end)

describe("holdem dealing and blinds", function()
  it("three-handed: button, blinds, dealing indices, first to act, street indices", function()
    local s = mk({ 1, 2, 3 })
    ok(E.apply(s, 0, { k = "hand" }))
    eq({ s.button, s.sbSeat, s.bbSeat, s.order, s.phase, s.hand }, { 1, 2, 3, { 2, 3, 1 }, "deal", 1 })
    eq(chips(s), { 1000, 995, 990 }); eq({ s.p[2].bet, s.p[3].bet, s.bet, s.minRaise }, { 5, 10, 10, 10 })
    ok(E.apply(s, 0, { k = "deal", deck = deckFor(s, {}) }))
    eq({ s.p[2].cards, s.p[3].cards, s.p[1].cards }, { { 1, 4 }, { 2, 5 }, { 3, 6 } })
    eq({ s.phase, s.turn }, { "bet", 1 })
    acts(s, { { 1, "call" }, { 2, "call" }, { 3, "check" } })
    eq(s.phase, "street"); local a = sys(s); eq(a.k, "street")
    local keys = {} for i in pairs(a.cards) do keys[#keys + 1] = i end table.sort(keys); eq(keys, { 8, 9, 10 })
    eq(s.board, { 8, 9, 10 }); eq(s.turn, 2)
    acts(s, { { 2, "check" }, { 3, "check" }, { 1, "check" } }); sys(s); eq(s.board, { 8, 9, 10, 12 })
    acts(s, { { 2, "check" }, { 3, "check" }, { 1, "check" } }); sys(s); eq(s.board, { 8, 9, 10, 12, 14 })
    acts(s, { { 2, "check" }, { 3, "check" }, { 1, "check" } }); eq(s.phase, "showdown")
    a = sys(s); eq(a.k, "showdown"); eq(s.phase, "done"); eq(sum(chips(s)), 3000)
  end)
  it("deal checks the deck; a view deals without one", function()
    local s = mk({ 1, 2 }); ok(E.apply(s, 0, { k = "hand" }))
    local dup = deckFor(s, {}); dup[2] = dup[1]
    rejects(s, 0, { k = "deal", deck = dup }, "card"); rejects(s, 0, { k = "deal", deck = "x" }, "card")
    local bad = deckFor(s, {}); bad[7] = "1Z"; rejects(s, 0, { k = "deal", deck = bad }, "card")
    rejects(s, 1, { k = "deal", deck = deckFor(s, {}) }, "seat")
    local v = E.view(s, 1); ok(E.apply(v, 0, { k = "deal" })); eq(v.deck, {}); eq(v.p[1].cards, { 2, 4 })
    ok(E.apply(s, 0, { k = "deal", deck = deckFor(s, {}) })); eq(s.deck[52] ~= nil, true)
    ok(E.apply(s, 0, { k = "show", cards = { [1] = s.deck[1] } })); eq(E.snapshot(s).phase, "bet")
  end)
  it("heads-up: the button posts the small blind, acts first preflop and last after", function()
    local s = mk({ 1, 2 })
    ok(E.apply(s, 0, { k = "hand" }))
    eq({ s.button, s.sbSeat, s.bbSeat, s.order }, { 1, 1, 2, { 2, 1 } }); eq(chips(s), { 995, 990 })
    ok(E.apply(s, 0, { k = "deal", deck = deckFor(s, {}) }))
    eq({ s.p[2].cards, s.p[1].cards }, { { 1, 3 }, { 2, 4 } }); eq(s.turn, 1)
    acts(s, { { 1, "call" } }); eq(s.turn, 2)
    eq(kinds(E.legal(s, 2)), { "fold", "check", "raise", "allin" })
    acts(s, { { 2, "check" } }); sys(s); eq(s.board, { 6, 7, 8 }); eq(s.turn, 2)
    acts(s, { { 2, "check" } }); eq(s.turn, 1); acts(s, { { 1, "check" } }); sys(s); eq(s.turn, 2)
  end)
  it("the button moves over playing seats only", function()
    local s = mk({ 1, 3, 5, 7 }, { first = 4 })
    local function hand() ok(E.apply(s, 0, { k = "hand" })); local b = s.button
      ok(E.apply(s, 0, { k = "deal", deck = deckFor(s, {}) }))
      while s.phase == "bet" do ok(E.apply(s, s.turn, { k = "fold" })) end
      return b end
    eq(hand(), 5); eq(hand(), 7); eq(hand(), 1)
    s.seats[3].chips = 0; s.seats[3].out = true
    ok(E.apply(s, 0, { k = "join", seat = 2 })); eq(hand(), 2); eq(s.order, { 5, 7, 1, 2 })
    eq(hand(), 5); eq({ s.sbSeat, s.bbSeat }, { 7, 1 })
  end)
  it("a short small blind and a short big blind post all-in", function()
    local s = mk({ 1, 2, 3 }, { stacks = { [2] = 3, [3] = 4 } })
    start(s, { [1] = "2C 3D", [2] = "AS AD", [3] = "KS KD" }, "7H 8H 9C JD 4S")
    eq({ s.p[2].bet, s.p[2].allin, s.p[3].bet, s.p[3].allin, s.bet }, { 3, true, 4, true, 10 })
    eq(s.turn, 1); eq(kinds(E.legal(s, 1)), { "fold", "call" })   -- nobody left to raise against
    acts(s, { { 1, "call" } }); eq(chips(s)[1], 990); eq(s.phase, "street")
    runout(s); eq(s.phase, "done")
    -- main 9 (3 each) to seat 2, side 2 (1+1) to seat 3, seat 1's uncalled 6 back
    eq(s.last.pots, { { amount = 9, eligible = { 2, 3, 1 }, winners = { 2 } }, { amount = 2, eligible = { 3, 1 }, winners = { 3 } } })
    eq(s.last.contrib, { [1] = 4, [2] = 3, [3] = 4 }); eq(s.last.won, { [2] = 9, [3] = 2 })
    eq(chips(s), { 996, 9, 2 })
  end)
  it("heads-up with a short small blind: no betting, run out, the big blind's excess comes back", function()
    local s = mk({ 1, 2 }, { stacks = { [1] = 3 } })
    start(s, { [1] = "AS AD", [2] = "KS KD" }, "7H 8H 9C JD 4S")
    eq(s.phase, "street"); eq(s.turn, nil); runout(s)
    eq(s.last.contrib, { [1] = 3, [2] = 3 }); eq(s.last.won, { [1] = 6 }); eq(chips(s), { 6, 997 })
    eq(s.last.pots, { { amount = 6, eligible = { 2, 1 }, winners = { 1 } } })
  end)
end)

describe("holdem betting", function()
  it("the big blind has the option after limps", function()
    local s = mk({ 1, 2, 3 }); start(s)
    acts(s, { { 1, "call" }, { 2, "call" } }); eq(s.turn, 3)
    eq(E.legal(s, 3), { { k = "fold" }, { k = "check" }, { k = "raise", to = 20, max = 1000 }, { k = "allin" } })
    acts(s, { { 3, "raise", 20 } }); eq(s.turn, 1); eq(kinds(E.legal(s, 1)), { "fold", "call", "raise", "allin" })
  end)
  it("minimum raise is the last full raise; bad amounts, verbs and turns are rejected untouched", function()
    local s = mk({ 1, 2, 3 }); start(s)
    rejects(s, 2, { k = "call" }, "turn"); rejects(s, 1, { k = "check" }, "action")
    rejects(s, 1, { k = "bet", to = 20 }, "action"); rejects(s, 1, { k = "raise", to = 19 }, "amount")
    rejects(s, 1, { k = "raise", to = 1001 }, "amount"); rejects(s, 1, { k = "raise", to = 25.5 }, "amount")
    rejects(s, 1, { k = "raise" }, "amount"); rejects(s, 1, { k = "nope" }, "action"); rejects(s, 1, nil, "action")
    rejects(s, 0, { k = "call" }, "seat"); rejects(s, 10, { k = "call" }, "seat"); rejects(s, 1, { k = "hand" }, "seat")
    acts(s, { { 1, "raise", 30 } }); eq({ s.bet, s.minRaise }, { 30, 20 })
    rejects(s, 2, { k = "raise", to = 49 }, "amount"); acts(s, { { 2, "raise", 50 } })
    eq(E.legal(s, 3)[3], { k = "raise", to = 70, max = 1000 }); acts(s, { { 3, "raise", 200 } }); eq(s.minRaise, 150)
    acts(s, { { 1, "fold" }, { 2, "call" } }); eq(s.phase, "street"); sys(s)
    rejects(s, 2, { k = "raise", to = 20 }, "action"); rejects(s, 2, { k = "bet", to = 9 }, "amount")
    rejects(s, 2, { k = "call" }, "action")
    acts(s, { { 2, "bet", 10 } }); eq({ s.bet, s.minRaise }, { 10, 10 }); rejects(s, 3, { k = "check" }, "action")
    acts(s, { { 3, "raise", 20 }, { 2, "call" } }); eq(s.phase, "street")
    rejects(s, 0, { k = "deal" }, "phase"); rejects(s, 2, { k = "check" }, "phase")
  end)
  it("a short all-in raise does not reopen the betting for a player who already acted", function()
    local s = mk({ 1, 2, 3 }, { stacks = { [3] = 160 } }); start(s)
    acts(s, { { 1, "call" }, { 2, "call" }, { 3, "check" } }); sys(s)
    acts(s, { { 2, "bet", 100 } }); eq(s.turn, 3)
    eq(E.legal(s, 3), { { k = "fold" }, { k = "call" }, { k = "allin" } })     -- 150 is less than a min raise
    acts(s, { { 3, "allin" } }); eq({ s.bet, s.minRaise, s.p[3].allin }, { 150, 100, true })
    eq(E.legal(s, 1), { { k = "fold" }, { k = "call" }, { k = "raise", to = 250, max = 990 }, { k = "allin" } })
    acts(s, { { 1, "call" } }); eq(s.turn, 2)
    eq(E.legal(s, 2), { { k = "fold" }, { k = "call" } })
    rejects(s, 2, { k = "raise", to = 250 }, "action"); rejects(s, 2, { k = "allin" }, "action")
    acts(s, { { 2, "call" } }); eq(s.phase, "street")
  end)
  it("several short all-ins that add up to a full raise reopen the betting", function()
    local s = mk({ 1, 2, 3, 4 }, { stacks = { [3] = 160, [4] = 230 } }); start(s)
    -- order 2 3 4 1; preflop: 4 calls, 1 calls, 2 calls, 3 checks
    acts(s, { { 4, "call" }, { 1, "call" }, { 2, "call" }, { 3, "check" } }); sys(s)
    acts(s, { { 2, "bet", 100 }, { 3, "allin" }, { 4, "allin" } }); eq({ s.bet, s.minRaise }, { 220, 100 })
    eq(E.legal(s, 1)[3], { k = "raise", to = 320, max = 990 }); acts(s, { { 1, "call" } })
    eq(kinds(E.legal(s, 2)), { "fold", "call", "raise", "allin" }); acts(s, { { 2, "raise", 320 } })
    eq(s.turn, 1); acts(s, { { 1, "call" } }); eq(s.phase, "street")
  end)
  it("nobody may raise when every other live player is all-in", function()
    local s = mk({ 1, 2 }, { stacks = { [2] = 100 } }); start(s)
    acts(s, { { 1, "raise", 500 } }); eq(E.legal(s, 2), { { k = "fold" }, { k = "call" } })
    acts(s, { { 2, "call" } }); eq(s.p[2].allin, true); eq(s.phase, "street"); runout(s)
    eq(s.last.contrib, { [1] = 100, [2] = 100 }); eq(sum(chips(s)), 1100)
  end)
  it("auto checks when it can, else folds, and only for the seat on turn", function()
    local s = mk({ 1, 2, 3 }); start(s)
    eq(E.auto(s, 1), { k = "fold" }); eq(E.auto(s, 2), nil); acts(s, { { 1, "call" }, { 2, "call" } })
    eq(E.auto(s, 3), { k = "check" }); eq(E.auto(s, 0), nil); eq(E.legal(s, 1), {}); eq(E.legal(s, 0), {})
  end)
end)

describe("holdem pots and showdown", function()
  it("everyone folds: no showdown, the uncalled raise comes back, the winner's cards stay hidden", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "QS QD" })
    acts(s, { { 1, "raise", 30 }, { 2, "fold" }, { 3, "fold" } })
    eq(s.phase, "done"); eq(chips(s), { 1015, 995, 990 })
    eq(s.last, { hand = 1, contrib = { [1] = 10, [2] = 5, [3] = 10 }, won = { [1] = 25 },
      pots = { { amount = 25, eligible = { 1 }, winners = { 1 } } }, shown = {}, cat = {}, left = {} })
    eq(E.view(s, 2).deck, { [s.p[2].cards[1]] = "KS", [s.p[2].cards[2]] = "KD" }); eq(E.view(s, 0).deck, {})
    eq(E.hidden(s, 1), s.p[1].cards); eq({ E.system(s) }, { { k = "hand" }, E.HAND_DELAY })
  end)
  it("split pot: the odd chip goes to the first winner left of the button; order without a river bet", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "2C 3D", [3] = "4H 5S", [2] = "6C 7C" }, "AS KS QD JC TH")
    acts(s, { { 1, "call" }, { 2, "fold" }, { 3, "check" } }); sys(s)
    for _ = 1, 3 do acts(s, { { 3, "check" }, { 1, "check" } }); sys(s) end
    eq(s.last.pots, { { amount = 25, eligible = { 3, 1 }, winners = { 3, 1 } } })
    eq(s.last.won, { [3] = 13, [1] = 12 }); eq(s.last.shown, { 3, 1 })
    eq(s.last.cat, { [3] = H.STRAIGHT, [1] = H.STRAIGHT }); eq(chips(s), { 1002, 995, 1003 })
  end)
  it("showdown: the river aggressor shows first; folded hands stay hidden", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "QS QD" }, "2C 7D 9H JS 3C")
    acts(s, { { 1, "call" }, { 2, "call" }, { 3, "check" } }); sys(s)
    acts(s, { { 2, "check" }, { 3, "check" }, { 1, "check" } }); sys(s)
    acts(s, { { 2, "bet", 20 }, { 3, "fold" }, { 1, "call" } }); sys(s)
    acts(s, { { 2, "check" }, { 1, "bet", 50 }, { 2, "call" } })
    local a = sys(s); local n = 0 for _ in pairs(a.cards) do n = n + 1 end; eq(n, 9)   -- board + two hands
    eq(s.last.shown, { 1, 2 }); eq(s.last.won, { [1] = 170 }); eq(s.last.cat, { [1] = H.PAIR, [2] = H.PAIR })
    eq(s.last.contrib, { [1] = 80, [2] = 80, [3] = 10 })
    local w = E.view(s, 0)
    for _, i in ipairs(s.p[1].cards) do eq(w.deck[i], s.deck[i]) end
    for _, i in ipairs(s.p[2].cards) do eq(w.deck[i], s.deck[i]) end
    for _, i in ipairs(s.p[3].cards) do eq(w.deck[i], nil) end
    eq(E.hidden(s, 1), {}); eq(E.hidden(s, 3), s.p[3].cards)
  end)
  it("four all-ins at different sizes build three pots", function()
    local s = mk({ 1, 2, 3, 4 }, { stacks = { [2] = 100, [3] = 300, [4] = 600 } })
    start(s, { [2] = "AS AD", [3] = "KS KD", [4] = "QS QD", [1] = "8S 8D" }, "2C 7D 9H JS 3C")
    acts(s, { { 4, "allin" }, { 1, "call" }, { 2, "call" }, { 3, "call" } })
    eq(s.phase, "street"); runout(s)
    eq(s.last.pots, { { amount = 400, eligible = { 2, 3, 4, 1 }, winners = { 2 } },
      { amount = 600, eligible = { 3, 4, 1 }, winners = { 3 } }, { amount = 600, eligible = { 4, 1 }, winners = { 4 } } })
    eq(s.last.contrib, { [1] = 600, [2] = 100, [3] = 300, [4] = 600 }); eq(s.last.won, { [2] = 400, [3] = 600, [4] = 600 })
    eq(chips(s), { 400, 400, 600, 600 }); eq(s.last.shown, { 2, 3, 4, 1 })
    eq({ s.seats[1].out, s.seats[2].out }, { false, false })
  end)
  it("three all-ins: the biggest stack's excess comes back, the short stack wins only the main pot", function()
    local s = mk({ 1, 2, 3 }, { stacks = { [1] = 50, [2] = 200 } })
    start(s, { [1] = "AS AD", [2] = "QS QD", [3] = "KS KD" }, "2C 7D 9H JS 3C")
    acts(s, { { 1, "allin" }, { 2, "call" } }); eq(s.minRaise, 40)
    rejects(s, 3, { k = "raise", to = 89 }, "amount"); acts(s, { { 3, "raise", 500 } })
    eq(E.legal(s, 2), { { k = "fold" }, { k = "call" } }); acts(s, { { 2, "call" } }); eq(s.p[2].allin, true); runout(s)
    eq(s.last.pots, { { amount = 150, eligible = { 2, 3, 1 }, winners = { 1 } }, { amount = 300, eligible = { 2, 3 }, winners = { 3 } } })
    eq(s.last.contrib, { [1] = 50, [2] = 200, [3] = 200 }); eq(chips(s), { 150, 0, 1100 })
    eq(s.seats[2].out, true); eq(sum(s.last.won), sum(s.last.contrib))
  end)
  it("a split side pot and a won main pot", function()
    local s = mk({ 1, 2, 3, 4 }, { stacks = { [2] = 101 } })
    start(s, { [2] = "7S 7H", [3] = "KH QC", [4] = "KD QH", [1] = "2S 3S" }, "KC QS 7D 8C 4H")
    acts(s, { { 4, "raise", 301 }, { 1, "fold" } })
    rejects(s, 2, { k = "allin" }, "action")                        -- short of a call: that is a call
    acts(s, { { 2, "call" }, { 3, "call" } }); checkdown(s)
    -- main 101 x3 = 303 to seat 2; side (301-101) x2 = 400 split by 3 and 4
    eq(s.last.pots, { { amount = 303, eligible = { 2, 3, 4 }, winners = { 2 } }, { amount = 400, eligible = { 3, 4 }, winners = { 3, 4 } } })
    eq(s.last.won, { [2] = 303, [3] = 200, [4] = 200 }); eq(chips(s), { 1000, 303, 899, 899 })
  end)
  it("showdown rejects missing or wrong faces untouched; show fills a view", function()
    local s = mk({ 1, 2 }); start(s, { [1] = "AS AD", [2] = "KS KD" }, "2C 7D 9H JS 3C")
    acts(s, { { 1, "call" }, { 2, "check" } }); for _ = 1, 3 do sys(s); acts(s, { { 2, "check" }, { 1, "check" } }) end
    local v = E.view(s, 0); local a = E.system(s)
    rejects(v, 0, { k = "showdown" }, "card")
    local bad = {} for i, f in pairs(a.cards) do bad[i] = f end; bad[s.p[1].cards[1]] = "KS"
    rejects(s, 0, { k = "showdown", cards = bad }, "card")
    rejects(s, 0, { k = "show", cards = { [s.p[1].cards[1]] = "2H" } }, "card")
    rejects(s, 0, { k = "show", cards = { [53] = "2H" } }, "card"); rejects(s, 0, { k = "show", cards = { [40] = "ZZ" } }, "card")
    ok(E.apply(s, 0, { k = "show", cards = { [s.p[1].cards[1]] = "AS" } }))
    ok(E.apply(v, 0, { k = "show", cards = { [s.p[2].cards[1]] = "KS" } })); eq(v.deck[s.p[2].cards[1]], "KS")
    ok(E.apply(v, 0, a)); ok(E.apply(s, 0, a)); eq(v.last, s.last); eq(chips(v), chips(s))
  end)
end)

describe("holdem seats", function()
  it("join: empty chair only, plays from the next hand", function()
    local s = mk({ 1, 2 }); start(s)
    ok(E.apply(s, 0, { k = "join", seat = 5 })); eq(s.seats[5], { chips = 1000, out = false, leaving = false })
    eq(s.p[5], nil); rejects(s, 0, { k = "join", seat = 5 }, "seat"); rejects(s, 0, { k = "join", seat = 10 }, "seat")
    rejects(s, 3, { k = "join", seat = 3 }, "seat"); rejects(s, 0, { k = "join" }, "seat")
    acts(s, { { 1, "fold" } }); ok(E.apply(s, 0, { k = "hand" })); eq(s.order, { 5, 1, 2 })
  end)
  it("leave between hands removes the seat at once; an empty seat is a no-op", function()
    local s = mk({ 1, 2, 3 }); eq(E.leave(s, 2), true); eq(s.seats[2], false)
    local before = E.snapshot(s); eq(E.leave(s, 2), true); eq(E.leave(s, 0), true); eq(E.snapshot(s), before)
    rejects(s, 0, { k = "leave", seat = 2 }, "seat"); ok(E.apply(s, 0, { k = "leave", seat = 3 })); eq(s.seats[3], false)
    eq(E.system(s), nil)
  end)
  it("leave on turn folds and the hand goes on; the seat goes after the hand with its chips", function()
    local s = mk({ 1, 2, 3 }); start(s)
    acts(s, { { 1, "raise", 40 } }); eq(s.turn, 2); E.leave(s, 2)
    eq({ s.p[2].folded, s.seats[2].leaving, s.turn }, { true, true, 3 }); rejects(s, 2, { k = "call" }, "turn")
    acts(s, { { 3, "call" } }); sys(s); E.leave(s, 2); eq(s.seats[2].leaving, true)
    acts(s, { { 3, "check" }, { 1, "check" } }); checkdown(s)
    eq(s.seats[2], false); eq(s.last.left, { [2] = 995 }); eq(s.last.contrib[2], 5)
    eq(sum(chips(s)) + 995, 3000); ok(E.apply(s, 0, { k = "hand" })); eq({ s.button, s.order }, { 3, { 1, 3 } })
  end)
  it("leave off turn folds; the last live player wins at once", function()
    local s = mk({ 1, 2, 3 }); start(s)
    E.leave(s, 3); eq(s.turn, 1); eq(s.p[3].folded, true)
    acts(s, { { 1, "call" } }); eq(s.turn, 2); E.leave(s, 1)
    eq(s.phase, "done"); eq(s.last.won, { [2] = 25 }); eq(s.last.left, { [1] = 990, [3] = 990 })
    eq(chips(s), { [2] = 1020 }); eq(E.system(s), nil)
  end)
  it("leave while the deck is being shuffled: heads-up ends the hand, the deal is refused", function()
    local s = mk({ 1, 2 }); ok(E.apply(s, 0, { k = "hand" })); E.leave(s, 2)
    -- the big blind's extra 5 was never called and goes back with him
    eq(s.phase, "done"); eq(s.last.won, { [1] = 10 }); eq(s.last.contrib, { [1] = 5, [2] = 5 })
    eq(s.last.left, { [2] = 995 }); rejects(s, 0, { k = "deal", deck = E.DECK }, "phase"); eq(chips(s), { 1005 })
  end)
  it("leave closes the street when the leaver was the last to act", function()
    local s = mk({ 1, 2, 3 }); start(s)
    acts(s, { { 1, "call" }, { 2, "call" } }); E.leave(s, 3); eq(s.phase, "street")
  end)
  it("a seat that joined during the hand leaves at once", function()
    local s = mk({ 1, 2 }); start(s); ok(E.apply(s, 0, { k = "join", seat = 4 })); E.leave(s, 4)
    eq(s.seats[4], false); eq(s.phase, "bet")
  end)
  it("a newcomer on a freed chair sees nothing of the previous player's hand", function()
    -- the previous player folded and stood up between hands
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "3C 6C", [3] = "KS KD" })
    acts(s, { { 1, "raise", 30 }, { 2, "fold" }, { 3, "fold" } }); eq(s.phase, "done")
    E.leave(s, 2); ok(E.apply(s, 0, { k = "join", seat = 2 }))
    eq(E.view(s, 2).deck, {}); eq(E.hidden(s, 2), {}); eq(E.view(s, 1).deck, { [3] = "AS", [6] = "AD" })
    -- the previous player left during the hand and was removed when it ended
    s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "3C 6C", [3] = "KS KD" })
    E.leave(s, 2); acts(s, { { 1, "raise", 30 }, { 3, "fold" } }); eq(s.seats[2], false)
    eq(E.view(s, 2).deck, {}); eq(E.hidden(s, 2), {})
    ok(E.apply(s, 0, { k = "join", seat = 2 })); eq(E.view(s, 2).deck, {}); eq(E.hidden(s, 2), {})
    -- a seat that stays keeps seeing its own folded cards until the next hand
    eq(E.view(s, 3).deck, { [2] = "KS", [5] = "KD" }); eq(E.hidden(s, 3), { 2, 5 })
  end)
  it("a busted seat sits out until it leaves", function()
    local s = mk({ 1, 2, 3 }, { stacks = { [1] = 100 } })
    start(s, { [1] = "2C 3D", [2] = "AS AD", [3] = "7H 8D" }, "KC QS 9D 4C 5H")
    acts(s, { { 1, "allin" }, { 2, "call" }, { 3, "fold" } }); runout(s)
    eq(s.seats[1], { chips = 0, out = true, leaving = false })
    ok(E.apply(s, 0, { k = "hand" })); eq(s.order, { 3, 2 }); eq(s.p[1], nil); eq(s.button, 2)
    ok(E.apply(s, 0, { k = "deal", deck = E.DECK })); acts(s, { { 2, "fold" } })
    eq(chips(s), { 0, 1105, 995 })   -- hand 1: seat 2 won 210; hand 2: seat 2 folded his small blind
    E.leave(s, 3); eq(E.system(s), nil); E.leave(s, 1); eq(chips(s), { [2] = 1105 })
  end)
end)

describe("holdem views", function()
  it("views show only own cards, the board and showdown hands", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "QS QD" }, "2C 7D 9H JS 3C")
    eq(E.view(s, 1).deck, { [3] = "AS", [6] = "AD" }); eq(E.view(s, 0).deck, {}); eq(E.view(s, nil).deck, {})
    eq(E.view(s, 7).deck, {}); eq(E.hidden(s, 2), { 1, 4 }); eq(E.hidden(s, 9), {})
    acts(s, { { 1, "call" }, { 2, "call" }, { 3, "check" } }); eq(E.view(s, 0).deck, {}); sys(s)
    eq(E.view(s, 0).deck, { [8] = "2C", [9] = "7D", [10] = "9H" })
    local v = E.view(s, 2); v.deck[8] = nil; eq(s.deck[8], "2C")   -- a copy
    eq(#E.view(s, 1).p[2].cards, 2)
  end)
  it("a hand on the full state replays on every seat's view with show actions", function()
    local s = mk({ 1, 2, 3 }, { stacks = { [3] = 300 } })
    local views = {}
    for _, i in ipairs({ 0, 1, 2, 3 }) do views[i] = E.view(s, i) end
    local function step(seat, a)
      ok(E.apply(s, seat, a))
      for sv, v in pairs(views) do
        if a.k == "deal" then
          ok(E.apply(v, 0, { k = "deal" }))
          if s.p[sv] then
            local own = {} for _, i in ipairs(s.p[sv].cards) do own[i] = s.deck[i] end
            ok(E.apply(v, 0, { k = "show", cards = own }))
          end
        else
          ok(E.apply(v, seat, a))
        end
        eq(v, E.view(s, sv), "view of seat " .. sv); assertViewClean(s, sv, v)
        eq(E.legal(v, s.turn or 1), E.legal(s, s.turn or 1)); eq(E.auto(v, s.turn or 1), E.auto(s, s.turn or 1))
      end
    end
    step(0, { k = "hand" })
    step(0, { k = "deal", deck = deckFor(s, { [1] = "AS AD", [2] = "KS KD", [3] = "QS QD" }, "2C 7D 9H JS 3C") })
    step(1, { k = "raise", to = 30 }); step(2, { k = "call" }); step(3, { k = "allin" }); step(1, { k = "call" })
    step(2, { k = "fold" })
    while s.phase ~= "done" do step(0, (E.system(s))) end
    eq(s.last.won, { [1] = 630 }); eq(chips(s), { 1330, 970, 0 })
    for sv, v in pairs(views) do eq(v.last, s.last); eq(chips(v), chips(s)); eq(v.seats, s.seats) end
  end)
  it("snapshot is plain data and round-trips mid-hand", function()
    local s = mk({ 1, 2, 3 }); start(s, {}, nil); acts(s, { { 1, "raise", 30 }, { 2, "call" } })
    local t = E.snapshot(s); ok(plain(t, 0)); local r = E.restore(t)
    eq(r, s); t.seats[1].chips = 1; eq(s.seats[1].chips, 970); eq(E.snapshot(E.restore(E.snapshot(s))), E.snapshot(s))
    acts(s, { { 3, "call" } }); acts(r, { { 3, "call" } }); sys(s); sys(r); eq(r, s)
  end)
end)

-- ------------------------------------------------------------------ fuzz

-- Plays `hands` hands from LCG-shuffled decks. Actions: E.auto 3 times in 10, else a random legal action
-- (a random amount for bet/raise). Seats join and leave between hands and now and then mid-hand.
-- withViews: every seat's view (and a watcher's) replays the stream and must equal E.view of the full state.
local function fuzz(seed, hands, withViews)
  local rnd = lcg(seed)
  local n, seatList = rnd(2, 9), {}
  for i = 1, 9 do if #seatList < n and rnd(1, 9) <= n then seatList[#seatList + 1] = i end end
  if #seatList < 2 then seatList = { 1, 9 } end
  local s = mk(seatList, { first = rnd(1, 9) })
  local injected, gone, played = #seatList * s.stack, 0, 0
  local stats = { showdown = 0, sidepots = 0, split = 0, midLeave = 0, players = {} }
  local views = {}
  if withViews then for i = 0, 9 do views[i] = E.view(s, i) end end
  local function check(cond, msg) if not cond then error(msg, 2) end end
  -- Leak check independent of the engine's seat records: every sitting gets a player id, every dealt
  -- index remembers the player it went to; a chair sees only the cards of the player sitting in it now.
  local owner, pids, dealtTo = {}, 0, {}
  for _, i in ipairs(seatList) do pids = pids + 1; owner[i] = pids end
  local viewOwner = {}
  for _, i in ipairs(seatList) do viewOwner[i] = owner[i] end
  local function leakCheck(sv, v)
    local me = (sv ~= 0 and s.seats[sv]) and owner[sv] or nil
    local vis = {}
    for _, i in ipairs(s.board) do vis[i] = true end
    for st in pairs(s.shown) do for _, i in ipairs(s.p[st].cards) do vis[i] = true end end
    for i, pid in pairs(dealtTo) do if pid == me then vis[i] = true end end
    for i in pairs(v.deck) do check(vis[i], "chair " .. sv .. " sees deck[" .. i .. "]") end
    for _, i in ipairs(E.hidden(s, sv)) do
      check(me ~= nil and dealtTo[i] == me, "hidden of chair " .. sv .. " lists deck[" .. i .. "]")
    end
  end
  local function apply(seat, a)
    local r, why = E.apply(s, seat, a)
    check(r, "rejected " .. tostring(a.k) .. " at seat " .. seat .. ": " .. tostring(why))
    if a.k == "join" then pids = pids + 1; owner[a.seat] = pids end
    if a.k == "hand" then dealtTo = {} end
    if a.k == "deal" then
      for _, seat2 in ipairs(s.order) do
        for _, i in ipairs(s.p[seat2].cards) do dealtTo[i] = owner[seat2] end
      end
    end
    for sv, v in pairs(views) do
      if a.k == "deal" then
        check(E.apply(v, 0, { k = "deal" }), "view deal")
        if s.p[sv] then
          local own = {} for _, i in ipairs(s.p[sv].cards) do own[i] = s.deck[i] end
          check(E.apply(v, 0, { k = "show", cards = own }), "view show")
        end
      else
        check(E.apply(v, seat, a), "view " .. sv .. " rejected " .. a.k)
      end
      -- a client that stood up is gone (its view kept what it saw); whoever sits next starts from a snapshot
      local occupant = (sv ~= 0 and s.seats[sv]) and owner[sv] or nil
      if occupant ~= viewOwner[sv] then v = E.view(s, sv); views[sv], viewOwner[sv] = v, occupant end
      eq(v, E.view(s, sv), "view " .. sv .. " diverged")
      leakCheck(sv, v)
    end
  end
  while played < hands do
    -- between hands: busted seats leave, empty chairs fill, now and then someone stands up
    for i = 1, 9 do
      local st = s.seats[i]
      if st and (st.out and rnd(1, 2) == 1 or rnd(1, 40) == 1) then gone = gone + st.chips; apply(0, { k = "leave", seat = i }) end
      if not s.seats[i] and rnd(1, 8) == 1 then apply(0, { k = "join", seat = i }); injected = injected + s.stack end
    end
    local playing = 0
    for i = 1, 9 do if s.seats[i] and s.seats[i].chips > 0 then playing = playing + 1 end end
    for i = 1, 9 do
      if playing < 2 and not s.seats[i] then apply(0, { k = "join", seat = i }); injected = injected + s.stack; playing = playing + 1 end
    end
    for sv = 0, 9 do leakCheck(sv, E.view(s, sv)) end   -- the window where a newcomer sits on a freed chair
    local a, delay = E.system(s); check(a and a.k == "hand" and delay > 0, "no hand due")
    apply(0, a); check(E.system(s) == nil, "system acts during the shuffle")
    stats.players[#s.order] = true
    apply(0, { k = "deal", deck = shuffled(rnd) })
    while s.phase ~= "done" do
      if s.phase == "bet" then
        local seat = s.turn
        local legal = E.legal(s, seat)
        check(#legal >= 2, "too few legal actions")
        if withViews then
          eq(E.legal(views[seat], seat), legal, "legal on the view"); eq(E.auto(views[seat], seat), E.auto(s, seat))
        end
        for _, la in ipairs(legal) do
          check(E.apply(E.restore(E.snapshot(s)), seat, la), "legal action refused: " .. la.k)
        end
        local act
        if rnd(1, 10) <= 3 then
          act = E.auto(s, seat, rnd)
        else
          act = legal[rnd(1, #legal)]
          if act.max then act = { k = act.k, to = rnd(act.to, rnd(1, 3) == 1 and act.max or math.min(act.max, act.to * 3)) } end
        end
        apply(seat, act)
        if s.phase ~= "done" and rnd(1, 100) == 1 then
          local victim = s.order[rnd(1, #s.order)]
          if s.seats[victim] and not s.seats[victim].leaving then
            apply(0, { k = "leave", seat = victim }); stats.midLeave = stats.midLeave + 1
          end
        end
      else
        local sa = E.system(s); check(sa, "stuck in phase " .. s.phase); apply(0, sa)
      end
    end
    played = played + 1
    local L = s.last
    check(L.hand == s.hand, "record of another hand")
    check(sum(L.won) == sum(L.contrib), "won ~= contrib in hand " .. s.hand)
    local potSum = 0
    for _, pot in ipairs(L.pots) do
      potSum = potSum + pot.amount; check(#pot.winners >= 1, "pot without winner")
      if #pot.winners > 1 then stats.split = stats.split + 1 end
    end
    check(potSum == sum(L.won), "pots ~= won")
    if #L.shown > 0 then stats.showdown = stats.showdown + 1 end
    if #L.pots > 1 then stats.sidepots = stats.sidepots + 1 end
    gone = gone + sum(L.left)
    local onTable = 0
    for i = 1, 9 do
      local st = s.seats[i]
      if st then
        check(st.chips >= 0, "negative chips"); check(st.out == (st.chips == 0), "out flag")
        onTable = onTable + st.chips
      end
    end
    check(onTable + gone == injected, "chips not conserved after hand " .. s.hand)
  end
  return played, stats
end

describe("holdem fuzz", function()
  it("300 hands with 2-9 players driven by auto and random legal actions conserve every chip", function()
    local total, agg = 0, { showdown = 0, sidepots = 0, split = 0, midLeave = 0, players = {} }
    for seed = 1, 6 do
      local played, st = fuzz(seed * 7919, 50, false)
      total = total + played
      for k in pairs(agg) do if k ~= "players" then agg[k] = agg[k] + st[k] end end
      for p in pairs(st.players) do agg.players[p] = true end
    end
    eq(total, 300)
    ok(agg.showdown >= 30, "showdowns " .. agg.showdown); ok(agg.sidepots >= 10, "side pots " .. agg.sidepots)
    ok(agg.split >= 1, "splits " .. agg.split); ok(agg.midLeave >= 5, "mid-hand leaves " .. agg.midLeave)
    for p = 2, 9 do ok(agg.players[p], "no hand with " .. p .. " players") end
  end)
  it("30 hands replayed on every seat's view stay identical to the views of the full state", function()
    local played = fuzz(424242, 30, true)
    eq(played, 30)
  end)
end)
