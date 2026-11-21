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

-- Sets the stacks on every client's state (between hands), as if earlier hands had been played.
local function stacks(t)
  for _, c in pairs(sim.clients) do
    if c.session and c.session.state then
      for seat, n in pairs(t) do c.session.state.seats[seat].chips = n end
    end
  end
end
local function total(c)
  local n = 0
  for _, x in pairs(chips(c)) do n = n + x end
  return n
end
local function hands(c) local t = {}; c:on("hand", function(e) t[#t + 1] = e end); return t end
-- Every "fair" verdict a client closes from now on, as "verdict:why".
local function verdicts(c) local t = {}; c:on("fair", function(e) t[#t + 1] = e.verdict .. ":" .. tostring(e.why) end); return t end
-- Runs fn(msg, sender) before `c` takes each message (true drops it), or with `after` once it took it.
local function tap(c, fn, after)
  local recv = c.receive
  c.receive = function(self, channel, sender, msg)
    if not after and fn(msg, sender) then return end
    recv(self, channel, sender, msg)
    if after then fn(msg, sender) end
  end
end

describe("holdem: leaving, silence and the clock", function()
  it("a player who stands mid-hand is folded and his chips stay in the pots; nothing is lost", function()
    -- Under KEY(i) seat 1 holds the straight, seat 4 three aces, seat 3 nothing: the shortest stack is the best hand,
    -- so the main pot and the side pot go to different players (the brief's 600/300/100/600 gave seat 1 both).
    tableN(4); ok(cl[1]:startGame()); sim:run(1); stacks{ 100, 300, 600, 600 }; local seen = hands(w); sim:run(2)
    eq({ st().order, st().turn, chips() }, { { 2, 3, 4, 1 }, 4, { 100, 295, 590, 600 } })
    act("allin"); act("call"); act("call"); eq({ st().turn, chips() }, { 3, { 0, 0, 590, 0 } })
    cl[2]:stand(); sim:run(1); eq({ st().p[2].folded, st().seats[2].leaving, st().turn, host().session.seats[2] }, { true, true, 3, false })
    act("call"); sim:run(4); local l = seen[1].last
    eq(l.pots, { { amount = 400, eligible = { 3, 4, 1 }, winners = { 1 } }, { amount = 1200, eligible = { 3, 4 }, winners = { 4 } } })
    eq({ l.contrib, l.won, l.left, l.shown }, { { 100, 300, 600, 600 }, { [1] = 400, [4] = 1200 }, { [2] = 0 }, { 3, 4, 1 } })
    eq({ #seen, seen[1].n, seen[1].game, seen[1].tid, seen[1].chips }, { 1, 1, "holdem", tid, { [1] = 400, [3] = 0, [4] = 1200 } })
    eq(seen[1].names, { N[1], N[2], N[3], N[4], false, false }); eq(seen[1].opt, { betting = "nl", blinds = 10, stack = 100 })   -- six chairs (E.maxSeats)
    eq({ total(), st().seats[2], st().seats[3].out, cl[3].session.state.last }, { 1600, false, true, l })
    sim:run(5); eq({ st().hand, E.players(st()), st().seats[3].chips }, { 2, { 1, 4 }, 0 })
  end)
  it("a seat that does not commit in FAIR_WAIT sits out; back, its client deals it in again", function()
    tableN(3); sim:offline(N[3]); ok(cl[1]:startGame()); sim:run(3); local mark = #sim.sent
    eq({ st().phase, cl[1].session.fair.stage, cl[1].session.fair.h, chips() }, { "deal", "commit", 5, { 1000, 995, 990 } })
    sim:run(18); eq(cl[1].session.fair.h, 5); sim:run(1)
    eq(kinds(evs(W, mark)), { "away", "open", "commits", "deal" }); eq(evs(W, mark)[1], { k = "away", seat = 3 })
    eq({ st().seats[3].away, st().p[3].folded, cl[1].session.fair.h, cl[1].session.fair.p, st().phase, st().turn }, { true, true, 7, { 1, 2 }, "bet", 1 })
    auto(2); sim:run(5); eq({ st().hand, st().order, chips() }, { 2, { 1, 2 }, { 990, 1000, 995 } })     -- seat 2 won 5 of seat 3's blind, the uncalled half came back; heads-up now
    local c3 = sim:relog(N[3]); sim:run(2); eq({ st().seats[3].away, c3.session.mySeat }, { false, 3 })
    eq(sim:count(function(m) return m.from == N[3] and m.msg.t == "ACT" and m.msg.a.k == "back" end), 1)
    auto(3); sim:run(5); eq({ st().order, ns.Deal.alarm(c3.session), c3.session.fair.p }, { { 1, 2, 3 }, false, { 1, 2, 3 } })
  end)
  it("the clock: my client checks or folds at my deadline; the host does it for a silent seat AUTO_GRACE later", function()
    tableN(3, nil, 30); ok(cl[1]:startGame()); sim:run(3); eq({ st().turn, cl[1].session:left(), ns.Const.AUTO_GRACE }, { 1, 29, 7 })
    act("call"); sim:run(29); eq(st().turn, 2); sim:run(1)                 -- seat 2 owes 5 more: its own client folds
    eq({ st().turn, st().p[2].folded }, { 3, true }); eq(sim:count(function(m) return m.from == N[2] and m.msg.t == "ACT" and m.msg.a.k == "fold" end), 1)
    sim:offline(N[3]); sim:run(36); eq(st().turn, 3); sim:run(2); eq({ st().phase, st().turn, #st().board }, { "bet", 3, 3 })   -- the host checks for seat 3
    eq(sim:count(function(m) return m.target == W and m.msg.t == "EV" and m.msg.seat == 3 and m.msg.auto == true and m.msg.a.k == "check" end), 1)
    eq(sim:count(function(m) return m.target == W and m.msg.t == "EV" and m.msg.seat == 2 and m.msg.auto == true end), 0)
  end)
  it("a timeout the host plays for me after my deadline is not forged; a move before it is", function()
    tableN(3, nil, 30); ok(cl[1]:startGame()); sim:run(3); act("call"); local s = cl[2].session
    s.autoTimer.cancel(); s.autoTimer = nil; sim:run(37)                                         -- my client sleeps through its deadline
    eq({ st().turn, st().p[2].folded, s.state.p[2].folded, s.fair.foul }, { 3, true, true, nil })
    eq(ns.Member.timedOut(s, { seat = 2, auto = true, a = { k = "fold" } }), false)                -- no deadline of mine is running now
    act("check"); sim:run(2); eq(st().turn, 3); cl[1].session:play(3, { k = "check" }, true); sim:run(1)   -- the host moves for seat 3 at once
    eq({ cl[3].session.fair.foul, cl[2].session.fair.foul }, { "forged", nil })
    auto(8); sim:run(4); eq({ cl[3].session.fairLast.verdict, cl[3].session.fairLast.why, ns.Deal.alarm(cl[3].session) }, { "bad", "forged", true })
    eq({ ns.Book.status(cl[3].session) }, { "seal.bad", "red", 1 }); eq({ ns.Book.status(cl[2].session) }, { "seal.sealed", "inkDim", 1, 0 })
  end)
  it("the dealer reloads and the hand goes on; a dealer who is gone: the hand is void after FAIR_WAIT and he sits out", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); sim:run(5); eq({ st().hand, cl[1].session.fair.d, st().turn }, { 2, 2, 2 })
    sim.envs[N[2]].random = rnd(7)                                                               -- a regenerated key would not be KEY(2)
    local c2 = sim:relog(N[2]); sim:run(2); eq({ c2.session.fair.stage, c2.session.fair.deck ~= nil, sim.envs[N[2]].db.bookKeep }, { "dealt", true, { tid = tid, me = N[2], key = KEY(2), g = 3 } })
    act("call"); act("call"); act("check"); sim:run(1); eq({ #st().board, st().turn }, { 3, 3 })     -- the reloaded dealer dealt the flop
    act("check"); act("check"); act("check"); sim:offline(N[2]); local seen = hands(w)             -- the turn card is due and its dealer is gone
    eq({ st().phase, chips() }, { "street", { 990, 985, 995 } }); sim:run(19); eq(st().phase, "street"); sim:run(1)
    eq({ st().phase, st().last.void, chips(), st().seats[2].away, total() }, { "done", true, { 1000, 995, 1005 }, true, 3000 })
    eq({ ns.Deal.status(cl[1].session) }, { "fair.voidBy", N[2] }); eq({ #seen, seen[1].last.void }, { 1, true })
    eq(cl[1].session.book.n, 2)                                                        -- the void was written into the book (n counts it); its record is checked at the close
    sim:run(5); eq({ st().hand, st().order }, { 3, { 1, 3 } })
  end)
  it("a fold the host plays for me before my own deadline is forged, whatever `left` it sends", function()
    tableN(3, nil, 30); ok(cl[1]:startGame()); sim:run(3); act("call"); local s = cl[2].session
    ok(s.turnAt ~= nil, "my own clock started when the turn reached me")
    cl[1].session:play(2, { k = "fold" }, true); sim:run(1)                                       -- the host folds me at once and calls it a timeout
    eq({ s.fair.foul, ns.Member.timedOut(s, { seat = 2, auto = true, a = { k = "fold" }, left = 0 }) }, { "forged", false })
  end)
  it("an away of my seat in a dealt hand is a fold nobody asked for: forged; the legitimate aways are not", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3)
    cl[1].session:play(0, { k = "away", seat = 3 }); sim:run(1)
    eq({ cl[3].session.fair.foul, cl[2].session.fair.foul }, { "forged", nil })
  end)
  it("a shuffle stuck in stage seed: the silent dealer sits out and the deal passes on", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); eq(st().phase, "done")                -- hand 1 is over; hand 2 is seat 2's to deal
    local cries = { verdicts(cl[1]), verdicts(cl[3]), verdicts(w) }; local mark
    tap(cl[2], function(m)                                                                         -- the dealer goes silent right after the commits event
      if m.t == "EV" and m.a.op == "commits" then sim:offline(N[2]); mark = #sim.sent end
    end, true)
    sim:run(5); eq({ cl[1].session.fair.stage, cl[1].session.fair.d, cl[2].session.fair.stage }, { "seed", 2, "seed" })
    sim:run(20)
    eq(kinds(evs(W, mark)), { "away", "open", "commits", "deal" }); eq(evs(W, mark)[1], { k = "away", seat = 2 })
    eq({ cl[1].session.fair.d, cl[1].session.fair.p, cl[1].session.fair.stage, st().seats[2].away }, { 3, { 1, 3 }, "dealt", true })
    for _, t in ipairs(cries) do
      for _, v in ipairs(t) do ok(not v:find("^bad"), "a round closed " .. v) end
    end
  end)
  it("the host deals and a seed never reaches it: the hand is void, it and the seat it names sit out, and both are back", function()
    tableN(4); local mark = #sim.sent
    tap(cl[1], function(m, from) return m.t == "SED" and from == N[2] end)                         -- seat 2's seeds never reach the host
    ok(cl[1]:startGame()); sim:run(3); eq({ cl[1].session.fair.stage, cl[1].session.fair.d }, { "seed", 1 })
    sim:run(20)                                                                                      -- the host named seat 2 (op "missing"): void, then both sit out
    eq(kinds(evs(W, mark)), { "start", "hand", "open", "commits", "void", "away", "back", "away" })
    eq({ evs(W, mark)[6], evs(W, mark)[8] }, { { k = "away", seat = 1 }, { k = "away", seat = 2 } })   -- the host is back at once; seat 2 after a hand without it
    eq({ st().last.void, st().seats[1].away, st().seats[2].away, ns.Deal.alarm(cl[2].session) }, { true, false, true, false })
    sim:run(5); eq({ st().hand, E.players(st()), cl[1].session.fair.p, st().seats[2].away }, { 2, { 1, 3, 4 }, { 1, 3, 4 }, false })
  end)
  it("a member that reloads in stage seed sends its seed again", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); eq(st().phase, "done")
    local dropped = 0
    tap(cl[2], function(m, from)                                                                   -- the dealer never gets seat 3's first seed
      if m.t == "SED" and from == N[3] and dropped == 0 then dropped = 1; return true end
    end)
    sim:run(5); local h = cl[1].session.fair.h
    eq({ dropped, cl[1].session.fair.stage, cl[2].session.fair.d, cl[3].session.fair.seedSent }, { 1, "seed", 2, true })
    local mark = #sim.sent; local c3 = sim:relog(N[3]); sim.envs[N[3]].random = rnd(7); sim:run(2)   -- a regenerated key would be KEY(7)
    local sent = {}
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]; if m.from == N[3] and m.msg.t == "SED" then sent[#sent + 1] = m.msg end
    end
    eq(#sent, 1); eq({ sent[1].h, sent[1].s }, { h, Fair.handSeed(KEY(3), tid .. "/" .. h) }); eq(sent[1].s, ns.Book.seedFor(c3.session, h))
    eq({ cl[1].session.fair.stage, c3.session.fair.stage, st().phase, ns.Deal.alarm(c3.session) }, { "dealt", "dealt", "bet", false })
  end)
  it("a void writes the hand's record", function()
    -- Hand 2 (seat 2 deals) is voided after the flop because its dealer is gone; `swap` changes a flop card of its deck first.
    local function voided(swap)
      tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); sim:run(5); eq(cl[1].session.fair.d, 2)
      local h = cl[1].session.fair.h
      if swap then local d = cl[2].session.fair.deck; d[8], d[20] = d[20], d[8] end
      act("call"); act("call"); act("check"); sim:run(1); eq(#st().board, 3); act("check"); act("check"); act("check")
      sim:offline(N[2]); sim:run(21); eq({ st().phase, st().last.void }, { "done", true })
      return h, deckOf(h, 3)
    end
    -- Would the close's check pass this record: is every face it holds the deck's?
    local function honest(rec, deck)
      for i, f in pairs(rec.f) do if deck[i] ~= f then return false end end
      return true
    end
    local h, deck = voided()
    for _, c in ipairs{ cl[1], cl[3], w } do
      local b = c.session.book; eq({ b.n, #b.open, b.rec[h] ~= nil }, { 2, 2, true })
      eq({ b.rec[h].f[8], b.rec[h].f[9], b.rec[h].f[10], b.rec[h].p }, { deck[8], deck[9], deck[10], { 1, 2, 3 } })
      eq(honest(b.rec[h], deck), true)
    end
    local mine = cl[1].session.state.p[1].cards                                                   -- my own hole cards; a watcher has none
    eq({ cl[1].session.book.rec[h].f[mine[1]], cl[1].session.book.rec[h].f[mine[2]], w.session.book.rec[h].f[mine[1]] }, { deck[mine[1]], deck[mine[2]], nil })
    h, deck = voided(true)
    for _, c in ipairs{ cl[1], cl[3], w } do
      local rec = c.session.book.rec[h]; eq({ rec.f[8], honest(rec, deck) }, { deck[20], false })
    end
  end)
  it("the dealer stands mid-hand: the hand is void and its chips come back", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); local before = chips(); sim:run(5)
    eq({ st().hand, cl[1].session.fair.d, st().turn }, { 2, 2, 2 }); local h, after = cl[1].session.fair.h, chips()
    act("raise", 30); cl[2]:stand(); sim:run(2)
    local l = st().last
    eq({ l.hand, l.void, chips()[1], chips()[3], l.left[2], st().seats[2] }, { 2, true, before[1], before[3], after[2], false })
    eq(total() + l.left[2], 3000)
    for _, c in ipairs{ cl[1], cl[3], w } do
      local b = c.session.book; eq({ b.n, b.rec[h] ~= nil, c.session.fairLast.verdict }, { 2, true, "void" })
    end
  end)
end)

describe("holdem: silence, the host held to it (fix round 1)", function()
  -- Hand 2 of a three-seat table (seat 2 deals) up to its flop due; the dealer's own step is held back.
  local function hand2FlopDue(n)
    tableN(n or 3); ok(cl[1]:startGame()); sim:run(3); auto(n or 3); sim:run(5); eq(cl[1].session.fair.d, 2)
    act("call"); act("call"); act("check")
    local s2 = cl[2].session; if s2.stepTimer then s2.stepTimer.cancel(); s2.stepTimer = nil end
    sim:offline(N[2]); eq(st().phase, "street")
  end
  it("I1: the host changes while a street waits on a silent dealer: the new host voids it FAIR_WAIT after it was due", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); act("call"); act("call"); act("check")             -- hand 1: the host deals; the flop is due
    local s1 = cl[1].session; ok(s1.stepTimer, "the dealer's step is armed"); s1.stepTimer.cancel(); s1.stepTimer = nil
    sim:offline(N[1]); local due, before = sim.clock, nil
    for _ = 1, 150 do if host() then break end; before = cl[3].session.state.phase; sim:run(1) end
    local took = sim.clock; ok(host() and host() ~= cl[1], "a new host"); eq(before, "street")       -- still standing there until the takeover
    sim:run(2)
    eq({ st().phase, st().last.void, st().seats[1].away, took - due >= ns.Const.FAIR_WAIT }, { "done", true, true, true })
    for _, c in ipairs{ cl[2], cl[3] } do eq(c.session.fairLast.verdict, "void") end                -- an honest void: nobody calls it forged
    ok(w.session.fairLast.verdict ~= "bad", "the watcher, back by WAT after the event, missed the end: unseen")
  end)
  it("I2: an away of my seat after my blind and before its shuffle opens is forged; the next round carries it", function()
    tableN(3); local need, once = ns.Ext.fair.need, true
    ns.Ext.fair.need = function(s, a)
      if once and s == cl[1].session then once = false; s:play(0, { k = "away", seat = 2 }) end         -- the host sits seat 2 out right after its blind
      return need(s, a)
    end
    ok(cl[1]:startGame()); sim:run(3); ns.Ext.fair.need = need
    eq({ st().seats[2].away, st().p[2].folded, cl[1].session.fair.p }, { true, true, { 1, 3 } })
    eq({ cl[2].session.fair.foul, cl[3].session.fair.foul, w.session.fair.foul }, { "forged", nil, nil })
    auto(3); eq({ cl[2].session.fairLast.verdict, cl[2].session.fairLast.why, ns.Deal.alarm(cl[3].session) }, { "bad", "forged", false })
  end)
  it("I2: an away of my seat in stage commit is forged before FAIR_WAIT; at FAIR_WAIT, my commit lost, it is not", function()
    tableN(3); sim:offline(N[2]); ok(cl[1]:startGame()); sim:run(3); eq(cl[1].session.fair.stage, "commit")
    cl[1].session:play(0, { k = "away", seat = 3 }); sim:run(1)
    eq({ cl[3].session.fair.foul, w.session.fair.foul }, { "forged", nil })
    tableN(3); tap(cl[1], function(m, from) return m.t == "ACT" and from == N[3] and m.a.op == "commit" end)   -- seat 3's commit never reaches the host
    ok(cl[1]:startGame()); sim:run(3); eq(cl[1].session.fair.stage, "commit"); sim:run(19)
    eq({ cl[1].session.fair.p, st().seats[3].away, cl[3].session.fair.foul }, { { 1, 2 }, true, nil })
    sim.envs[N[3]].send("WHISPER", N[1], ns.Session.message("ACT", { tid = tid, a = { k = "back" } })); sim:run(1)
    eq(st().seats[3].away, true)                                                                       -- not back while the hand it sat out of runs
    auto(3); eq({ st().phase, st().seats[3].away, ns.Deal.alarm(cl[3].session), cl[3].session.fairSeen.bad }, { "done", false, false, 0 })
  end)
  it("I3/R2: a member that withholds its seed sits out with the dealer; the hand is void first, nobody's blind is lost", function()
    tableN(4); ok(cl[1]:startGame()); sim:run(3); auto(4); eq(st().phase, "done"); local before = chips()
    tap(cl[2], function(m, from) return m.t == "SED" and from == N[3] end)                             -- seat 3 withholds its seed from dealer 2
    local mark = #sim.sent; sim:run(5); eq({ cl[1].session.fair.stage, cl[1].session.fair.d, st().hand }, { "seed", 2, 2 })
    eq(chips()[3] < before[3], true)                                                                   -- seat 3 posted its blind
    sim:run(20)
    eq(sim:count(function(m) return m.from == N[2] and m.msg.t == "ACT" and m.msg.a.op == "missing" and ns.Util.same(m.msg.a.seats, { 3 }) end), 1)
    local e = evs(W, mark); eq({ kinds(e)[4], e[5], e[6] }, { "void", { k = "away", seat = 2 }, { k = "away", seat = 3 } })
    eq({ st().hand, st().last.void, chips() }, { 2, true, before })                                    -- every blind came back: naming seats gains the dealer nothing
    eq(sim:count(function(m) return m.target == W and m.msg.t == "EV" and m.msg.a.op == "open" and m.msg.a.h > cl[2].session.fairLast.h end), 0)
    eq({ cl[2].session.fairLast.verdict, cl[3].session.fairLast.verdict, ns.Deal.alarm(cl[3].session), ns.Deal.alarm(w.session) }, { "void", "void", false, false })
    for _, c in ipairs{ cl[1], cl[3], w } do eq({ ns.Deal.status(c.session) }, { "fair.lapse", N[2], 1 }); eq(c.session.fairVoids, nil) end   -- amber, apart
    sim:run(5); eq({ st().hand, E.players(st()), st().seats[2].away, st().seats[3].away }, { 3, { 1, 2, 4 }, false, false })   -- seat 3 missed hand 3; back once it was dealt
  end)
  it("I-3: a withholder cannot void consecutive hands: the next hand is dealt without it and finishes", function()
    tableN(4); ok(cl[1]:startGame()); sim:run(3); auto(4); eq(st().phase, "done")
    for _, i in ipairs{ 1, 2, 4 } do tap(cl[i], function(m, from) return m.t == "SED" and from == N[3] end) end   -- seat 3 withholds its seed from every dealer
    sim:run(25); eq({ st().hand, st().last.void, st().seats[2].away, st().seats[3].away }, { 2, true, false, true })
    eq(sim:count(function(m) return m.from == N[3] and m.msg.t == "ACT" and m.msg.a.k == "back" end), 1)   -- asked at once, held by the host
    sim:run(6); eq({ st().hand, st().phase, st().order, cl[1].session.fair.d, st().seats[3].away }, { 3, "bet", { 1, 2, 4 }, 4, false })
    auto(6); eq({ st().last.hand, st().last.void }, { 3, nil })                                     -- hand 3 was played to its end
    eq(sim:count(function(m) return m.target == W and m.msg.t == "EV" and m.msg.seat == 3 and m.msg.a.k == "back" end), 1)
    eq({ ns.Deal.alarm(cl[3].session), cl[3].session.fair and cl[3].session.fair.foul }, { false, nil })
  end)
  it("I-4: lapses of one dealer stay amber, however many", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); local s = cl[2].session
    for i = 1, 2 do ns.Deal.close(s, "void", nil, { h = 100 + i, dealer = N[3], stage = "seed" }) end
    local k, d, n = ns.Deal.status(s); eq({ k, d, n, ns.Deal.alarm(s) }, { "fair.lapse", N[3], 2, false })
    ns.Deal.close(s, "void", nil, { h = 103, dealer = N[3], stage = "dealt" }); ns.Deal.close(s, "void", nil, { h = 104, dealer = N[3], stage = "dealt" })
    k, d, n = ns.Deal.status(s); eq({ k, d, n, ns.Deal.alarm(s) }, { "fair.voidMany", N[3], 2, true })   -- voids of a dealt hand count as before
  end)
  it("m-1: the dealer's last seed comes late, its deal is lost and the lapse voids: not forged on the dealer", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); eq(st().phase, "done")
    local recv, held = cl[2].receive, nil
    tap(cl[2], function(m, from) if m.t == "SED" and from == N[3] and not held then held = m; return true end end)
    tap(cl[1], function(m, from) return m.t == "ACT" and from == N[2] and m.a.op == "deal" end)          -- the deal never reaches the host
    sim:run(15); eq({ cl[1].session.fair.missing, cl[2].session.fair.stage }, { { 3 }, "seed" })
    recv(cl[2], "WHISPER", N[3], held); sim:run(1); ok(cl[2].session.fair.deck, "the dealer dealt")
    sim:run(9); eq({ st().last.void, cl[2].session.fairLast.verdict, cl[2].session.fairLast.why }, { true, "void", nil })
  end)
  it("I4: a void earlier than FAIR_WAIT by my own clock is forged; the overdue one is not", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); sim:run(5); eq({ st().hand, st().phase }, { 2, "bet" })
    cl[1].session:play(0, { k = "void" }); sim:run(1)                                                  -- in the betting, its dealer at the table
    eq({ cl[3].session.fairLast.verdict, cl[3].session.fairLast.why, w.session.fairLast.why }, { "bad", "forged", "forged" })
    hand2FlopDue(); sim:run(10); cl[1].session:play(0, { k = "void" }); sim:run(1)                     -- the step is due, 10 s only
    eq({ cl[3].session.fairLast.verdict, cl[3].session.fairLast.why }, { "bad", "forged" })
    hand2FlopDue(); sim:run(21)
    eq({ st().last.void, cl[3].session.fairLast.verdict, w.session.fairLast.verdict, ns.Deal.alarm(cl[3].session) }, { true, "void", "void", false })
  end)
  it("M2: a sit and a stand while the step is overdue do not put the void off", function()
    hand2FlopDue(); local c4 = sim:add(N[4]); sim.envs[N[4]].random = rnd(4); sim:run(9)
    c4:sit(tid, 4); sim:run(5); eq(host().session.seats[4], N[4]); c4:stand(); sim:run(6)
    eq({ st().phase, st().last.void, st().seats[2].away }, { "done", true, true })
  end)
  it("a dealer that lost its deck cannot void a sealed hand at once; the host's wait does it", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); sim:run(5); eq(cl[1].session.fair.d, 2)
    cl[2].session.fair.voidAsked = nil; ns.Deal.submit(cl[2].session, { k = "fair", op = "void", h = cl[2].session.fair.h }); sim:run(1)
    eq({ st().phase, st().hand }, { "bet", 2 })
  end)
end)

-- Holds every message to `c` from now until `secs` later, then delivers them in order (a backlog that drains).
local function hold(c, secs)
  local recv, queue, until_ = c.receive, {}, sim.clock + secs
  c.receive = function(self, channel, sender, msg)
    if sim.clock < until_ or #queue > 0 then queue[#queue + 1] = { channel, sender, msg } else recv(self, channel, sender, msg) end
  end
  sim.envs[c.env.me].after(secs, function()
    local q = queue; queue = {}
    for _, m in ipairs(q) do recv(c, m[1], m[2], m[3]) end
  end)
end

describe("holdem: silence, the host held to it (fix round 2)", function()
  it("R1: the dealer sat out at once in stage seed is forged on its own client", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); eq(st().phase, "done")
    tap(cl[2], function(m, from) return m.t == "SED" and from == N[3] end)
    sim:run(5); eq({ cl[2].session.fair.stage, cl[2].session.fair.d }, { "seed", 2 })
    cl[1].session:play(0, { k = "away", seat = 2 }); sim:run(1)
    eq({ cl[2].session.fair.foul, cl[3].session.fair.foul }, { "forged", nil })
  end)
  it("M-a: a void in stage commit is forged even after FAIR_WAIT", function()
    tableN(3); sim:offline(N[2]); ok(cl[1]:startGame()); sim:run(3); eq(cl[1].session.fair.stage, "commit")
    sim:run(15); cl[1].session:play(0, { k = "void" }); sim:run(1)
    eq({ cl[3].session.fairLast.verdict, cl[3].session.fairLast.why }, { "bad", "forged" })
  end)
  it("R3: a member that missed the check that made the step due does not call the new host's overdue void forged", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3)
    tap(cl[3], function(m) return m.t == "EV" and m.a.k == "check" end)                               -- seat 3 never sees its own check come back
    act("call"); act("call"); act("check")
    local s1 = cl[1].session; ok(s1.stepTimer, "the dealer's step is armed"); s1.stepTimer.cancel(); s1.stepTimer = nil
    eq({ st().phase, cl[3].session.state.phase, cl[3].session.dueKey }, { "street", "bet", nil }); sim:offline(N[1])
    for _ = 1, 150 do if host() then break end; sim:run(1) end
    sim:run(2); eq({ st().last.void, cl[2].session.fairLast.verdict, cl[3].session.fairLast.verdict }, { true, "void", "void" })
  end)
  it("an honest offline stand flags nobody (a host's stand is its claim)", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); sim:offline(N[3])
    for _ = 1, 400 do if not st().seats[3] then break end; auto(1) end
    eq({ host().session.seats[3], cl[2].session.seats[3] }, { false, false })
    eq({ cl[2].session.fair and cl[2].session.fair.foul or nil, ns.Deal.alarm(cl[2].session), ns.Deal.alarm(w.session) }, { nil, false, false })
  end)
  it("M-c: a forged away after my blind that ends the hand before any shuffle turns my last hand forged", function()
    tableN(2); ok(cl[1]:startGame()); sim:run(3); act("fold"); eq(cl[2].session.fairLast.verdict, "sealed")
    local need, once = ns.Ext.fair.need, true
    ns.Ext.fair.need = function(s, a)
      if once and s == cl[1].session then once = false; s:play(0, { k = "away", seat = 2 }) end
      return need(s, a)
    end
    sim:run(5); ns.Ext.fair.need = need
    eq({ st().hand, st().phase, cl[2].session.fairLast.verdict, cl[2].session.fairLast.why, ns.Deal.alarm(cl[1].session) }, { 2, "done", "bad", "forged", false })
  end)
  it("M-d: a member whose events come in a backlog that drains is not flagged by the honest lapse (the clock's slack)", function()
    tableN(3); tap(cl[1], function(m, from) return m.t == "ACT" and from == N[3] and m.a.op == "commit" end)
    ok(cl[1]:startGame()); sim:run(1); hold(cl[3], 6); sim:run(2); eq(cl[1].session.fair.stage, "commit")   -- the open reaches seat 3 6 s late
    sim:run(19); eq({ st().seats[3].away, cl[3].session.state.seats[3].away, cl[3].session.fair.foul }, { true, true, nil })
  end)
  it("M-d: the dealer's list of missing seeds is checked; a demoted host drops its wait", function()
    tableN(4); ok(cl[1]:startGame()); sim:run(3); auto(4)
    tap(cl[2], function(m, from) return m.t == "SED" and (from == N[3] or from == N[4]) end)
    sim:run(5); local s, A = cl[1].session, ns.Ext.cash.act; local h = s.fair.h; eq({ s.fair.stage, s.fair.d }, { "seed", 2 })
    A(s, 3, { k = "book", op = "missing", h = h, seats = { 4 } }); A(s, 2, { k = "book", op = "missing", h = h + 1, seats = { 4 } })
    eq(s.fair.missing, nil)                                                                            -- not the dealer; not this round
    A(s, 2, { k = "book", op = "missing", h = h, seats = { 2, 7, 4, 4, "x" } }); eq(s.fair.missing, { 4 })   -- itself, a stranger, twice
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); sim:run(5); act("call"); act("call"); act("check")
    local s2 = cl[2].session; if s2.stepTimer then s2.stepTimer.cancel(); s2.stepTimer = nil end
    sim:offline(N[2]); s = cl[1].session; ok(s.stepTimer and s.stepWaits, "the host waits for the step")
    s.role = "player"; ns.Ext.cash.hostChanged(s); eq({ s.stepTimer, s.stepWaits }, { nil, nil })
  end)
end)
