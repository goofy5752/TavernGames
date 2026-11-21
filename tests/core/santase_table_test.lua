local Sim = require("sim")
local ns = Sim.ns
local E = ns.Engines.santase

local A, B, D = "Иван Петров", "Мария Стоянова", "Пешо Тодоров"
local sim, a, b, d

-- a and b online, d too (a watcher in the first test); no table yet.
local function setup()
  sim = Sim.new()
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  d = sim:add(D, { cls = "DRUID" })
  sim:run(1)
end

local function verdicts(cl)
  local list = {}
  cl:on("fair", function(e) list[#list + 1] = e.verdict end)
  return list
end

describe("santase at the table", function()
  it("two players are dealt six cards each and the trump is public", function()
    setup()
    local tid = a:openTable{ game = "santase", access = "guild", turn = 45 }; sim:run(3); d:watch(tid); b:sit(tid, 2); sim:run(1)
    local function known(cl) local n = 0; for _ in pairs(cl.session.state.deck) do n = n + 1 end; return n end
    eq({ known(a), known(b), known(d) }, { 7, 7, 1 }); eq(#a.session.state.hands[1], 6); eq(a.session.fair.d, 2); eq(a.session.state.turn, 1)
    eq(a.session.state.deck[13], b.session.fair.deck[13]); eq(a.session.state.tsuit, b.session.fair.deck[13]:sub(2, 2))
  end)

  it("the deal passes to the other player every hand and every hand is проверена", function()
    setup()
    local tid = a:openTable{ game = "santase", access = "guild", turn = 45 }; sim:run(3); d:watch(tid); b:sit(tid, 2); sim:run(1)
    local atA, atB, atD = verdicts(a), verdicts(b), verdicts(d)
    local dealers, lastN = {}, nil
    local function note()
      local s = a.session
      if s and s.fairN ~= lastN then
        lastN = s.fairN
        if s.fair and s.fair.stage == "dealt" then dealers[#dealers + 1] = s.fair.d end
      end
    end
    note()
    a:on("session", note)
    for _ = 1, 600 do
      if #atA >= 3 then break end
      local s = a.session
      local seat = s.state.turn
      if seat then sim.clients[s.seats[seat]]:playAuto() end
      sim:run(1)
    end
    sim:run(1)
    eq(atA, { "ok", "ok", "ok" }); eq(dealers, { 2, 1, 2 })
    -- The members, the watcher included, closed the same hands on their own views.
    eq({ atB[1], atB[2], atB[3] }, { "ok", "ok", "ok" }); eq({ atD[1], atD[2], atD[3] }, { "ok", "ok", "ok" })
    -- Only the host asked for the decks: every open is an EV from a, no member requested one.
    local opens = 0
    for _, m in ipairs(sim.sent) do
      local x = type(m.msg.a) == "table" and m.msg.a
      if x and x.k == "fair" and x.op == "open" then
        eq({ m.from, m.msg.t }, { A, "EV" }); opens = opens + 1
      end
    end
    ok(opens >= 3 * 2) -- three hands, each open to b and to d
  end)

  it("my turn times out into my lowest card", function()
    setup()
    local tid = a:openTable{ game = "santase", access = "guild", turn = 45 }; sim:run(3); b:sit(tid, 2); sim:run(1)
    eq(a.session.state.turn, 1); ok(a:playAuto()); sim:run(1)
    eq(a.session.state.turn, 2); eq(#a.session.state.trick, 1)
    local want = E.auto(b.session.state, 2); ok(want)
    local mark = #sim.sent
    sim:run(46)
    eq(a.session.state.trick, {})
    local acts, evs = 0, 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      if m.from == B and m.msg.t == "ACT" and m.msg.a.k == "play" then acts = acts + 1; eq(m.msg.a, want) end
      if m.from == A and m.msg.t == "EV" and m.msg.seat == 2 then evs = evs + 1; eq(m.msg.a, want) end
    end
    eq({ acts, evs }, { 1, 1 })
  end)
end)

-- A small generator so that every client of a run draws from one stream.
local function lcg(seed)
  local x = seed
  return function(lo, hi)
    x = (x * 1103515245 + 12345) % 2147483648
    return lo + math.floor(x / 65536) % (hi - lo + 1)
  end
end

-- a hosts Сантасе, b on seat 2 (d watches when `watched`); every client draws
-- from lcg(seed). -> tid, rnd, log (every verdict as "<tag>:<verdict>[/<why>]",
-- every desync as "<tag>:DESYNC"), listen(client, tag) for a client that logs in again.
local function seated(seed, watched)
  setup()
  local rnd, log = lcg(seed), {}
  local function listen(cl, tag)
    cl.env.random = rnd
    cl:on("fair", function(e) log[#log + 1] = tag .. ":" .. e.verdict .. (e.why and ("/" .. e.why) or "") end)
    cl:on("desync", function() log[#log + 1] = tag .. ":DESYNC" end)
  end
  listen(a, "a"); listen(b, "b"); listen(d, "d")
  local tid = a:openTable{ game = "santase", access = "guild", turn = 45 }; sim:run(3)
  if watched then d:watch(tid) end
  b:sit(tid, 2); sim:run(1)
  return tid, rnd, log, listen
end

-- The player on turn at the table `host` hosts makes a random legal move from its own view.
local function step(rnd, host)
  local s = host.session
  local seat = s.state and s.state.turn
  if seat and s.status == "live" then
    local cl = sim.clients[s.seats[seat]]
    local legal = E.legal(cl.session.state, seat)
    if #legal > 0 then cl:act(legal[rnd(1, #legal)]) end
  end
  sim:run(1)
end

-- Random play until `done()`; fails when it never comes.
local function playUntil(rnd, host, done, what)
  for _ = 1, 3000 do
    if done() then return end
    step(rnd, host)
  end
  error(what .. " never comes")
end

-- Hand number n is dealt, by seat `dealer`.
local function toHand(rnd, n, dealer)
  playUntil(rnd, a, function() return a.session.fairN == n and a.session.fair.stage == "dealt" end, "hand " .. n)
  eq(a.session.fair.d, dealer)
end

local function count(log, pattern)
  local n = 0
  for _, l in ipairs(log) do
    if l:match(pattern) then n = n + 1 end
  end
  return n
end

local function lastOf(log, tag)
  for i = #log, 1, -1 do
    if log[i]:sub(1, #tag + 1) == tag .. ":" then return log[i] end
  end
end

-- Until the host is gone for good and b hosts the table with a back in its seat.
local function untilBHosts()
  for _ = 1, 200 do
    sim:run(1)
    if b.session and b.session.role == "host" and a.session then return end
  end
  error("b never takes the table over")
end

describe("santase at the table: whole matches", function()
  it("random legal matches (plays, marriages, swaps, closes): every verdict проверена, no desync, „Нова игра“ deals", function()
    local hands = 0
    for seed = 1, 12 do
      local _, rnd, log = seated(seed, true)
      playUntil(rnd, a, function() return a.session:gameOver() end, "the end of match " .. seed)
      sim:run(5)
      for _, l in ipairs(log) do
        hands = hands + 1
        ok(l:match(":ok$"), "match " .. seed .. ": " .. l)
      end
      ok(#log >= 3 * 3, "match " .. seed .. ": too few verdicts")
      ok(a:startGame()); sim:run(3)
      eq(a.session.fair and a.session.fair.stage, "dealt", "seed " .. seed); eq(a.session.state.phase, "play")
      eq(a.session.fairSeen, nil)
    end
    ok(hands > 150)
  end)
end)

describe("santase at the table: reloads and a new host", function()
  it("the non-dealer reloads mid-hand: its cards come back, that hand is unseen for it, the next is проверена", function()
    local _, rnd, log, listen = seated(7)
    toHand(rnd, 2, 1)
    for _ = 1, 3 do step(rnd, a) end
    local before = {}
    for _, i in ipairs(b.session.state.hands[2]) do before[i] = b.session.state.deck[i] end
    ok(next(before))
    b = sim:relog(B); listen(b, "b2"); sim:run(3)
    local after = {}
    for _, i in ipairs(b.session.state.hands[2]) do after[i] = b.session.state.deck[i] end
    eq(after, before)
    toHand(rnd, 3, 2); eq(lastOf(log, "b2"), "b2:unseen")
    toHand(rnd, 4, 1); eq(lastOf(log, "b2"), "b2:ok")
    eq(count(log, "DESYNC"), 0); eq(count(log, "^a:ok$"), 3)
  end)

  it("the dealer reloads mid-hand: the hand is void by name, the score stays and the other player deals it again", function()
    local _, rnd, log, listen = seated(7)
    toHand(rnd, 3, 2)
    for _ = 1, 2 do step(rnd, a) end
    local gp, hand = ns.Util.copy(a.session.state.gp), a.session.state.hand
    b = sim:relog(B); listen(b, "b2"); sim:run(4)
    eq(lastOf(log, "a"), "a:void"); eq(a.session.fairLast.dealer, B); eq(a.session.fairVoids, { [B] = 1 })
    eq({ a.session.fairN, a.session.fair.d, a.session.fair.stage }, { 4, 1, "dealt" })
    eq({ a.session.state.hand, a.session.state.gp }, { hand, gp })
    eq({ ns.Deal.status(a.session) }, { "fair.voidBy", B })
    playUntil(rnd, a, function() return a.session:gameOver() end, "the end of the match")
    sim:run(3)
    eq(count(log, "DESYNC"), 0); eq(count(log, "bad"), 0); eq(lastOf(log, "b2"), "b2:ok")
  end)

  it("the host reloads mid-hand: the other player hosts after the silence and the match is played out", function()
    local _, rnd, log, listen = seated(11)
    for _ = 1, 3 do step(rnd, a) end
    eq(a.session.fair.d, 2)                                          -- b deals: the deck stays at the table
    a = sim:relog(A); listen(a, "a2")
    local t0 = sim.clock
    untilBHosts()
    ok(sim.clock - t0 <= 80, "took " .. (sim.clock - t0) .. " s")
    sim:run(5)
    playUntil(rnd, b, function() return b.session:gameOver() end, "the end of the match")
    sim:run(3)
    eq(count(log, "DESYNC"), 0); eq(count(log, "bad"), 0); eq(count(log, "^a2:unseen$"), 1)
    eq(lastOf(log, "b"), "b:ok"); eq(lastOf(log, "a2"), "a2:ok")
  end)

  it("the host reloads while it deals: after the silence the new host voids the hand and deals it", function()
    local _, rnd, log, listen = seated(5)
    toHand(rnd, 2, 1)
    for _ = 1, 2 do step(rnd, a) end
    local gp = ns.Util.copy(a.session.state.gp)
    a = sim:relog(A); listen(a, "a2")
    untilBHosts(); sim:run(8)
    eq(lastOf(log, "b"), "b:void"); eq(b.session.fairLast.dealer, A)
    eq({ b.session.fair.d, b.session.fair.stage, b.session.state.gp }, { 2, "dealt", gp })
    playUntil(rnd, b, function() return b.session:gameOver() end, "the end of the match")
    sim:run(3)
    eq(count(log, "DESYNC"), 0); eq(count(log, "bad"), 0)
  end)
end)

describe("santase at the table: a cheating host", function()
  local X = ("ab"):rep(16)

  -- Hand 1 is dealt (by b); from now on each client has a seed of its own.
  local function beforeHostDeal()
    local tid, rnd, log = seated(3)
    toHand(rnd, 1, 2)
    a.env.random = function() return 0x11 end; b.env.random = function() return 0x22 end
    return tid, rnd, log
  end

  -- Random play until hand n is closed on a.
  local function endOfHand(rnd, n)
    playUntil(rnd, a, function()
      local s = a.session
      return s:gameOver() or s.fairN > n or (s.fairN == n and s.fair.stage == "done")
    end, "the end of hand " .. n)
    sim:run(2)
  end

  -- Runs fn with `undo` called afterwards, whether it passes or fails.
  local function with(undo, fn)
    local fine, err = pcall(fn)
    undo()
    if not fine then error(err, 0) end
  end

  it("it forges my commit and deals from seeds of its own: нередовна (mine) on my side", function()
    local tid, rnd, log = beforeHostDeal()
    local F = ns.Ext.fair
    local realAct = F.act
    F.act = function(s, seat, x)
      if s.client == a and x.k == "fair" and x.op == "commit" and seat == 2 and s.fair and s.fair.d == 1 then
        x = { k = "fair", op = "commit", h = x.h, c = ns.Fair.commit(X) }
      end
      return realAct(s, seat, x)
    end
    with(function() F.act = realAct end, function()
      playUntil(rnd, a, function() return a.session.fair.d == 1 and a.session.fair.stage == "seed" end, "the shuffle of hand 2")
      local r = a.session.fair
      ns.Member.handlers.SED(a, B, { tid = tid, h = r.h, s = X }); sim:run(1)
      eq(a.session.fair.stage, "dealt")
      eq(a.session.fair.deck, ns.Fair.deck(E.DECK, { ("11"):rep(16), X }, tid .. "/" .. r.h))
    end)
    endOfHand(rnd, 2)
    eq(lastOf(log, "b"), "b:bad/mine"); eq(ns.Deal.alarm(b.session), true)
  end)

  it("it swaps its own commit by snapshot after seeing my seed: нередовна (commit) on my side", function()
    local tid, rnd, log = beforeHostDeal()
    local S2 = ("cd"):rep(16)
    local realSED, swapped = ns.Member.handlers.SED, nil
    ns.Member.handlers.SED = function(client, sender, m)
      local s = client.session
      if client == a and s and s.fair and s.fair.d == 1 and s.fair.stage == "seed" and not swapped then
        swapped = s.fair.h
        local f = s.fair
        f.seed = S2; f.seeds = f.seeds or {}; f.seeds[1] = S2; f.commits[1] = ns.Fair.commit(S2)
        s:snapshotTo(B)
      end
      return realSED(client, sender, m)
    end
    with(function() ns.Member.handlers.SED = realSED end, function()
      playUntil(rnd, a, function() return swapped and a.session.fair.stage == "dealt" end, "the deal of hand 2")
    end)
    eq(a.session.fair.deck, ns.Fair.deck(E.DECK, { S2, ("22"):rep(16) }, tid .. "/" .. swapped))
    endOfHand(rnd, 2)
    eq(lastOf(log, "b"), "b:bad/commit")
  end)

  it("it plays my card for me: нередовна (forged) on my side, and its own table is told", function()
    local _, rnd, log = beforeHostDeal()
    toHand(rnd, 2, 1)
    playUntil(rnd, a, function() return a.session.state.turn == 2 end, "the turn of seat 2")
    local worst = E.auto(ns.Fair.full(a.session.state, a.session.fair.deck), 2) -- the dealer knows that hand
    ok(worst)
    a.session:play(2, worst, true); sim:run(1)
    eq(b.session.fair.foul, "forged")
    endOfHand(rnd, 2)
    eq(lastOf(log, "b"), "b:bad/forged"); eq(lastOf(log, "a"), "a:ok")
    eq({ a.session.fairCry.name, a.session.fairCry.why }, { B, "forged" })
  end)

  it("it sits on the seeds instead of dealing: нередовна (nodeal) by name after 20 s", function()
    local _, rnd, log = beforeHostDeal()
    local real = ns.Fair.deck
    -- While a is the dealer of a shuffle, its addon gets no deck out of the seeds.
    ns.Fair.deck = function(...)
      local r = a.session.fair
      if r and r.d == 1 and r.stage == "seed" then return nil end
      return real(...)
    end
    with(function() ns.Fair.deck = real end, function()
      playUntil(rnd, a, function() return a.session.fair.d == 1 and a.session.fair.stage == "seed" end, "the shuffle of hand 2")
      local h = a.session.fair.h
      sim:run(21)
      eq(lastOf(log, "b"), "b:bad/nodeal")
      eq(b.session.fairLast, { h = h, verdict = "bad", why = "nodeal", dealer = A, n = 1 })
    end)
  end)

  it("a show that publishes a card still in a hand or in the stock is not relayed", function()
    local tid, rnd = seated(9)
    local s = a.session
    eq({ s.fair.d, s.fair.stage }, { 2, "dealt" })
    local deck, q = b.session.fair.deck, s.seq
    a:receive("WHISPER", B, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "show", h = s.fair.h, cards = { [1] = deck[1] } } })
    a:receive("WHISPER", B, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "show", h = s.fair.h, cards = { [14] = deck[14] } } })
    eq(s.seq, q)
    step(rnd, a); ok(s.seq > q)
  end)
end)
