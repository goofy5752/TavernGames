local Sim = require("sim")
local ns = Sim.ns
local E, Fair = ns.Engines.holdem, ns.Fair

local N = { "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров", "Нади Колева", "Гошо Илиев", "Ели Маринова", "Дидо Ангелов", "Зара Попова" }
local W = "Гледач Гледачев"
local SEED = ("ff"):rep(16)
-- every client has its own random: its table key is KEY(i), so a key under the wrong seat or a regenerated key shows
local function rnd(i) return function(lo, hi) return (lo + i) % (hi + 1) end end
local function KEY(i) return ("%02x"):format(i):rep(16) end
local sim, tid, cl, w

-- n players at seats 1..n (N[1] hosts), W watches; the game is not started yet (at most 6: Hold'em has six seats).
local function tableN(n, opt, turn)
  sim = Sim.new(); cl = {}
  for i = 1, n do cl[i] = sim:add(N[i]); sim.envs[N[i]].random = rnd(i) end
  w = sim:add(W); sim:run(1)
  tid = cl[1]:openTable{ game = "holdem", access = "guild", turn = turn or 30, opt = opt }; sim:run(3)
  w:watch(tid); sim:run(1)
  for i = 2, n do cl[i]:sit(tid, i); sim:run(1) end
  return sim, tid
end
local function host()
  for i = 1, #cl do
    local c = sim.clients[N[i]]
    if c.session and c.session.role == "host" and not sim.offlineSet[N[i]] then return c end
  end
end
local function st() return host().session.state end
local function at(seat) return sim.clients[host().session.seats[seat]] end
local function act(k, to)
  local seat = st().turn
  local r, why = at(seat):act{ k = k, to = to }
  ok(r, "seat " .. tostring(seat) .. " " .. k .. ": " .. tostring(why)); sim:run(1)
end
-- n seconds; whoever is on turn (and not in `skip`) makes its automatic move
local function auto(n, skip)
  for _ = 1, n do
    local t = st().turn
    if t and not (skip and skip[t]) then at(t):playAuto() end
    sim:run(1)
  end
end
local function evs(name, from)
  local out = {}
  for i = from + 1, #sim.sent do
    local m = sim.sent[i]
    if m.target == name and m.msg.t == "EV" then out[#out + 1] = m.msg.a end
  end
  return out
end
local function kinds(list)
  local out = {}
  for i, a in ipairs(list) do out[i] = a.k == "fair" and a.op or a.k end
  return out
end
local function chips(c)
  local t = {}
  for i = 1, 9 do local x = (c or host()).session.state.seats[i]; if x then t[i] = x.chips end end
  return t
end
local function mentions(v, words)
  if type(v) == "string" then
    for _, x in ipairs(words) do if v:find(x, 1, true) then return true end end
    return false
  end
  if type(v) ~= "table" then return false end
  for k, x in pairs(v) do if mentions(k, words) or mentions(x, words) then return true end end
  return false
end
local function deckOf(h, n)
  local seeds = {}
  for i = 1, n do seeds[i] = Fair.handSeed(KEY(i), tid .. "/" .. h) end
  return Fair.deck(E.DECK, seeds, tid .. "/" .. h)
end

describe("holdem at the table", function()
  it("heads-up: four events to the deal, each player gets only its own two cards", function()
    tableN(2); eq(tid, "Иван Петров#1700000001"); local mark = #sim.sent
    ok(cl[1]:startGame()); sim:run(3)
    local C4 = { Fair.commit(Fair.handSeed(KEY(1), tid .. "/4")), Fair.commit(Fair.handSeed(KEY(2), tid .. "/4")) }; local deck = deckOf(4, 2)
    ok(C4[1] ~= C4[2], "the two seats' commits differ"); eq(Fair.handSeed(KEY(1), tid .. "/4"):len(), 32)   -- the pinned hex of each seed is re-derived once
    eq(evs(W, mark), { { k = "start", first = 1 }, { k = "hand" }, { k = "fair", op = "open", h = 4, d = 1, p = { 1, 2 } },
      { k = "fair", op = "commits", h = 4, c = C4 }, { k = "deal", deck = {} } })
    local s = cl[1].session.state
    eq({ s.phase, s.turn, s.button, s.order, cl[1].session.seq, cl[1].session.fair.stage }, { "bet", 1, 1, { 2, 1 }, 6, "dealt" })
    eq({ deck[1], deck[2], deck[3], deck[4] }, { "JD", "6D", "9D", "4C" })
    eq(cl[1].session.state.deck, { [2] = deck[2], [4] = deck[4] }); eq(cl[2].session.state.deck, { [1] = deck[1], [3] = deck[3] }); eq(w.session.state.deck, {})
    eq(sim:count(function(m) return m.msg.t == "PRV" end), 1); eq(sim:count(function(m) return m.msg.t == "SED" end), 1)
    eq(sim:count(function(m) return m.msg.t == "PRV" and m.from == N[1] and m.target == N[2] and ns.Util.same(m.msg.cards, { [1] = deck[1], [3] = deck[3] }) end), 1)
    eq(sim:count(function(m) return (m.channel == "GUILD" or m.msg.t == "EV" or m.msg.t == "SNP") and mentions(m.msg, { deck[1], deck[2], deck[3], deck[4] }) end), 0)
    eq({ ns.Deal.status(cl[2].session) }, {}); eq(ns.Book.status(cl[2].session), nil)
    act("fold"); eq({ st().phase, chips(), cl[2].session.fair.stage, cl[2].session.fairLast.verdict }, { "done", { 995, 1005 }, "done", "sealed" })
    eq({ ns.Book.status(cl[2].session) }, { "seal.sealed", "inkDim", 1, 0 }); eq({ ns.Book.status(w.session) }, { "seal.sealed", "inkDim", 1, 0 })
    eq(cl[1].session.book.rec[4], { p = { 1, 2 }, c = C4, f = { [2] = deck[2], [4] = deck[4] }, who = { N[1], N[2] } })
    eq(cl[1].session.book.rec[4].c, C4); eq(cl[2].session.book.rec[4].c, C4)                  -- each seat's own commit under its own seat
    sim:run(5); eq({ st().button, st().hand, cl[1].session.fair.h, cl[1].session.fair.d }, { 2, 2, 9, 2 })
  end)

  it("three players to a showdown: one event a street; the folded kings stay in the dealer's whisper", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); local mark = #sim.sent; local deck = deckOf(5, 3)
    eq({ deck[1], deck[4], st().order, st().turn, cl[1].session.seq }, { "9C", "3D", { 2, 3, 1 }, 1, 7 })   -- seat 2's two cards (re-derived under KEY(i): the kings are seat 1's now)
    act("call"); act("fold"); act("check"); sim:run(1); eq({ st().phase, st().turn, #st().board }, { "bet", 3, 3 })
    for _ = 1, 3 do act("check"); act("check"); sim:run(1) end
    local e = evs(W, mark)
    eq(kinds(e), { "call", "fold", "check", "street", "check", "check", "street", "check", "check", "street", "check", "check", "showdown" })
    eq(e[4], { k = "street", cards = { [8] = "7C", [9] = "TD", [10] = "5D" } }); eq(e[7], { k = "street", cards = { [12] = "JC" } })
    eq(e[13], { k = "showdown", cards = { [2] = "8D", [5] = "3S", [3] = "KH", [6] = "KD", [8] = "7C", [9] = "TD", [10] = "5D", [12] = "JC", [14] = "3C" } })
    local l = st().last; eq({ l.shown, l.won, l.cat, l.contrib }, { { 3, 1 }, { [1] = 25 }, { [1] = 2, [3] = 2 }, { 10, 5, 10 } }); eq(chips(), { 1015, 995, 990 })
    eq(w.session.state.deck, e[13].cards); eq(cl[3].session.state, E.view(cl[3].session.state, 3)); eq(cl[2].session.state.deck[1], "9C")
    eq(sim:count(function(m) return mentions(m.msg, { "9C", "3D" }) end), 1)
    eq(sim:count(function(m) return m.msg.t == "PRV" and m.target == N[2] and mentions(m.msg, { "9C", "3D" }) end), 1)
    eq(sim:count(function(m) return m.msg.t == "EV" and (m.msg.a.k == "book" or m.msg.a.op == "reveal" or m.msg.a.op == "noreveal") end), 0)
    for _, c in ipairs{ cl[1], cl[2], cl[3], w } do
      eq({ ns.Book.status(c.session) }, { "seal.sealed", "inkDim", 1, 0 }); eq(c.session.fairSeen, { ok = 0, bad = 0 }); eq(ns.Deal.alarm(c.session), false)
    end
  end)
  it("the dealer is the button; a member refuses another dealer or other participants", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); local T = ns.Ext.fair.table
    eq({ cl[2].session.fair.d, cl[2].session.fair.p, st().button }, { 1, { 1, 2, 3 }, 1 })
    auto(3); sim:run(5); eq({ st().hand, st().button, cl[3].session.fair.d, cl[3].session.fair.h, cl[3].session.fair.stage }, { 2, 2, 2, 11, "dealt" })
    auto(3); local s = cl[3].session; eq({ s.state.phase, s.seq }, { "done", 15 }); sim:offline(N[3])
    ok(E.apply(s.state, 0, { k = "hand" })); s.seq = 16; eq({ s.state.button, E.dealer(s.state) }, { 3, 3 })   -- the next hand, by hand
    eq(T(s, { k = "fair", op = "open", h = 17, d = 2, p = { 1, 2, 3 } }), nil); eq(T(s, { k = "fair", op = "open", h = 17, d = 3, p = { 1, 3 } }), nil)
    eq(T(s, { k = "fair", op = "open", h = 18, d = 3, p = { 1, 2, 3 } }), nil); eq(T(s, { k = "fair", op = "open", h = 17, d = 3, p = { 1, 2, 3 } }), true)
    local c = Fair.commit(SEED)
    eq(T(s, { k = "fair", op = "commits", h = 17, c = { c, c } }), nil); eq(T(s, { k = "fair", op = "commits", h = 17, c = { c, c, c, c } }), nil)
    eq(T(s, { k = "fair", op = "commits", h = 16, c = { c, c, c } }), nil); eq(s.fair.stage, "commit")
    eq(T(s, { k = "fair", op = "commits", h = 17, c = { c, c, c } }), true); eq({ s.fair.stage, s.fair.commits }, { "seed", { c, c, c } })
  end)
  it("a newcomer sits mid-hand: chips at once, no cards, dealt in from the next hand", function()
    tableN(2); ok(cl[1]:startGame()); sim:run(3); local c5 = sim:add(N[5]); sim.envs[N[5]].random = rnd(5); sim:run(1); c5:sit(tid, 5); sim:run(1)
    local s = c5.session
    eq({ s.mySeat, s.state.seats[5], s.state.p[5], s.state.order, s.state.deck, s.fair.stage, s.fair.p }, { 5, { chips = 1000, out = false, leaving = false }, nil, { 2, 1 }, {}, "dealt", { 1, 2 } })
    eq({ cl[2].session.state.seats[5].chips, w.session.state.seats[5].chips, st().turn, cl[1].session:left() }, { 1000, 1000, 1, 27 })
    eq({ c5:act{ k = "fold" } }, { nil, "turn" }); eq(sim:count(function(m) return m.target == N[5] and m.msg.t == "PRV" end), 0)
    act("fold"); eq({ ns.Book.status(s) }, { "seal.sealed", "inkDim", 1, 0 }); sim:run(5)
    eq({ st().hand, st().button, st().order, s.fair.p, s.fair.d }, { 2, 2, { 5, 1, 2 }, { 1, 2, 5 }, 2 })
    eq({ #E.hidden(s.state, 5), s.state.deck[1] ~= nil, s.state.deck[4] ~= nil, ns.Deal.alarm(s), s.fairSeen.bad }, { 2, true, true, false, 0 })
    eq(chips(), { 985, 1005, [5] = 995 })                                                      -- hand 2: seat 5 posts the small blind, seat 1 the big one
  end)
  it("the line under the felt: the shuffle, then silence until the book speaks", function()
    tableN(2); sim:offline(N[2]); ok(cl[1]:startGame()); sim:run(3)
    eq({ cl[1].session.fair.stage, cl[1].session.fair.commits, cl[1].session.fair.pend }, { "commit", {}, { Fair.commit(Fair.handSeed(KEY(1), tid .. "/4")) } })
    eq({ ns.Deal.status(cl[1].session) }, { "fair.shuffle" }); eq({ ns.Deal.status(w.session) }, { "fair.shuffle" })
    eq(ns.Ext.fair.snap(cl[1].session), { h = 4, d = 1, p = { 1, 2 }, c = {}, st = "commit", n = 0 })
  end)
  it("a newcomer sits in the chair of a player who stood up this hand: no PRV, no face of the leaver anywhere, dealt in from the next hand", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); cl[3]:stand(); sim:run(1)
    local c4 = sim:add(N[4]); sim.envs[N[4]].random = rnd(4); sim:run(1); local mark = #sim.sent; c4:sit(tid, 3); sim:run(2)
    local s = c4.session
    eq({ s.mySeat, s.state.seats[3].leaving, s.state.p[3].gone, #E.hidden(s.state, 3), s.state.deck }, { 3, true, true, 0, {} })
    eq(sim:count(function(m) return m.from == N[4] and m.msg.t == "PRQ" end), 0); eq(sim:count(function(m) return m.target == N[4] and m.msg.t == "PRV" end), 0)
    auto(5); sim:run(5)                                                 -- hand 1 ends at the first fold; hand 2 runs, seat 3 is on turn
    eq({ st().hand, E.players(st()), cl[1].session.fair.p, #E.hidden(s.state, 3), ns.Deal.alarm(s) }, { 2, { 1, 2, 3 }, { 1, 2, 3 }, 2, false })
  end)
end)

describe("holdem: the step and the key", function()
  -- heads-up, hand 1 (seat 1 hosts and deals): the preflop betting is over, the flop is due; the dealer's own step is held back
  local function flopDue()
    tableN(2); ok(cl[1]:startGame()); sim:run(3); act("call"); act("check")
    local s = cl[1].session; eq(st().phase, "street"); ok(s.stepTimer, "the dealer's step is armed")
    s.stepTimer.cancel(); s.stepTimer = nil
    local d = deckOf(4, 2)
    return s, d, { [6] = d[6], [7] = d[7], [8] = d[8] }
  end
  it("the host plays a step only with every face it deals; a forged step of any kind is refused", function()
    local s, d, flop = flopDue(); local A, q = ns.Ext.cash.act, s.seq
    local function step(seat, a, h) return A(s, seat, { k = "book", op = "step", h = h or s.fair.h, a = a }) end
    eq(step(1, { k = "street", cards = {} }), nil); eq(step(1, { k = "street" }), nil)                    -- no faces
    eq(step(1, { k = "street", cards = { [6] = d[6], [7] = d[7] } }), nil)                              -- two of the flop's three
    eq(step(2, { k = "street", cards = flop }), nil)                                                    -- not the dealer
    eq(step(1, { k = "showdown", cards = flop }), nil); eq(step(1, { k = "street", cards = flop }, s.fair.h + 1), nil)
    local hole = ns.Util.copy(flop); hole[1] = d[1]; eq(step(1, { k = "street", cards = hole }), nil)    -- seat 2's hole card
    sim:run(1); eq({ s.seq, st().phase, #st().board }, { q, "street", 0 })
    step(1, { k = "street", cards = flop }); sim:run(1)
    eq({ s.seq, st().phase, #st().board, cl[2].session.state.deck[6], w.session.state.deck[8] }, { q + 1, "bet", 3, d[6], d[8] })
    eq(cl[2].session.fair.foul, nil)
  end)
  it("a street event without its faces is the foul deal on every client; the hand closes bad", function()
    local s = flopDue(); s:play(0, { k = "street", cards = {} }); sim:run(1)
    eq({ cl[1].session.fair.foul, cl[2].session.fair.foul, w.session.fair.foul }, { "deal", "deal", "deal" })
    act("fold")
    for _, c in ipairs{ cl[1], cl[2], w } do
      eq({ c.session.fairLast.verdict, c.session.fairLast.why }, { "bad", "deal" }); eq({ ns.Book.status(c.session) }, { "seal.bad", "red", 1 })
    end
  end)
  it("a key I have spent never deals again, whatever the book or the kept key says", function()
    tableN(2); ok(cl[1]:startGame()); sim:run(3); local s, env = cl[2].session, sim.envs[N[2]]
    eq(ns.Book.key(s), KEY(2)); ns.Book.spend(s); env.random = rnd(7)
    eq({ ns.Book.key(s), env.db.bookKeep.key, env.db.bookSpent }, { KEY(7), KEY(7), { { tid = tid, me = N[2], key = KEY(2) } } })
    env.db.bookKeep = { tid = tid, me = N[2], key = KEY(2), g = s.book.g }                         -- a kept key that is spent
    local c2 = sim:relog(N[2]); sim.envs[N[2]].random = rnd(8); sim:run(2)
    eq({ c2.session.book.g, ns.Book.key(c2.session), sim.envs[N[2]].db.bookKeep.key }, { 2, KEY(8), KEY(8) })
    c2.session.book.key = KEY(2); eq(ns.Book.key(c2.session), KEY(8))                             -- in memory, too
    for _ = 1, 40 do ns.Book.spend(c2.session) end; eq(#env.db.bookSpent, 32)
  end)
end)
