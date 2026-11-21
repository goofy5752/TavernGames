local Sim = require("sim")
local H = require("hicard_engine")
local ns = Sim.ns

-- A cheating host or dealer against an honest client (final review, findings
-- 1, 2 and 5): the honest client's own verdict must turn нередовна.
local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"
local SA, SB = ("11"):rep(16), ("22"):rep(16)
local sim, tid, a, b, c, d
local got -- client -> the "fair" payloads it received

-- a hosts hicard, b on seat 2 (c on seat 3 when `three`), d online; not
-- started. a's seeds are SA, b's SB.
local function setup(three)
  sim, got = Sim.new(), {}
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  c = three and sim:add(C, { cls = "ROGUE" }) or nil
  d = sim:add(D, { cls = "DRUID" })
  a.env.random = function() return 0x11 end
  b.env.random = function() return 0x22 end
  for _, cl in ipairs{ a, b, d, c } do
    local list = {}
    got[cl] = list
    cl:on("fair", function(e) list[#list + 1] = e end)
  end
  sim:run(1)
  tid = a:openTable{ game = "hicard", access = "guild", turn = 45 }; sim:run(3)
  b:sit(tid, 2); sim:run(1)
  if three then c:sit(tid, 3); sim:run(1) end
end

local function auto(n)
  for _ = 1, n do
    local s = a.session
    local cl = sim.clients[s.seats[s.state.turn]]
    ok(cl:playAuto())
    sim:run(1)
  end
end

-- Automatic moves until the running hand is over.
local function finish()
  local hand = a.session.state.hand
  for _ = 1, 12 do
    local st = a.session.state
    if not st.turn or st.hand ~= hand then return end
    auto(1)
  end
  error("the hand does not end")
end

-- The first hand (dealer seat 2) played out; the second (dealer = the host) is next.
local function toHostDeal()
  a:startGame(); sim:run(1); finish()
end

local function last(cl) return got[cl][#got[cl]] end

local function protests()
  local out = {}
  for _, m in ipairs(sim.sent) do
    local x = m.msg.t == "EV" and type(m.msg.a) == "table" and m.msg.a
    if x and x.op == "protest" and m.target == B then out[#out + 1] = x end
  end
  return out
end

describe("deal cheats: the shuffle", function()
  it("a host-dealer that forges my commit and deals from its own seeds: нередовна (mine)", function()
    setup()
    local X = ("ab"):rep(16) -- the seed the host invents for B
    local F = ns.Ext.fair
    local realAct = F.act
    F.act = function(s, seat, x)
      if s.client == a and x.k == "fair" and x.op == "commit" and seat == 2 and s.fair and s.fair.d == 1 then
        x = { k = "fair", op = "commit", h = x.h, c = ns.Fair.commit(X) }
      end
      return realAct(s, seat, x)
    end
    toHostDeal(); sim:run(2)
    local r = a.session.fair
    eq({ r.d, r.stage }, { 1, "seed" })
    ns.Member.handlers.SED(a, B, { tid = tid, h = r.h, s = X }); sim:run(1)
    F.act = realAct
    eq(a.session.fair.stage, "dealt")
    eq(a.session.fair.deck, ns.Fair.deck(H.DECK, { SA, X }, tid .. "/" .. r.h))
    finish(); sim:run(1)
    local e = last(b)
    eq({ e.h, e.verdict, e.why }, { r.h, "bad", "mine" })
    eq(b.session.fairLast.why, "mine")
  end)

  it("a host-dealer that swaps its own commit by snapshot after seeing my seed: нередовна (commit)", function()
    setup()
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
    toHostDeal(); sim:run(2)
    ns.Member.handlers.SED = realSED
    local r = a.session.fair
    eq({ r.d, r.stage, r.h }, { 1, "dealt", swapped })
    eq(r.deck, ns.Fair.deck(H.DECK, { S2, SB }, tid .. "/" .. r.h))
    finish(); sim:run(1)
    local e = last(b)
    eq({ e.h, e.verdict, e.why }, { r.h, "bad", "commit" })
    -- Only b was shown the other commit: it tells the table what it saw.
    eq(a.session.fairCry, { h = r.h, seat = 2, name = B, why = "commit" })
  end)

  it("a commit dropped by one snapshot and committed again with another value: нередовна (commit)", function()
    setup(true)
    a:startGame(); sim:run(1); finish(); sim:run(2)                  -- hand 2, dealer seat 3
    local s, r = c.session, c.session.fair
    eq({ r.stage, r.d }, { "dealt", 3 })
    local held = r.held[1]
    ok(held ~= nil)
    r.stage = "commit"; r.commits[1] = nil
    -- The host drops seat 1's commit and orders another one for it.
    ok(ns.Ext.fair.table(s, { k = "fair", op = "commit", h = r.h, seat = 1, c = ns.Fair.commit(SB) }))
    eq(r.foul, "commit"); eq(r.held[1], held)
  end)

  it("the seed revealed for my seat is not the one I made: нередовна (mine), even with no replay left", function()
    setup()
    a:startGame(); sim:run(1)
    local r = b.session.fair
    ok(r.seed == SB and r.seat == 2)
    b.session.fair.seed = ("77"):rep(16)                             -- as if the reveal named another seed for me
    b.session.fair.base, b.session.fair.log = nil, nil
    finish(); sim:run(1)
    eq({ last(b).verdict, last(b).why }, { "bad", "mine" })
    eq({ last(a).verdict }, { "ok" })
  end)

  it("the cheated player tells the table: everyone else's line names him", function()
    setup(true)
    a:startGame(); sim:run(1)
    eq(a.session.fair.d, 2)
    c.session.fair.lied = true                                       -- what the dealer sent c is not the deck's
    finish(); sim:run(1)
    eq({ last(c).verdict, last(c).why }, { "bad", "dealt" })
    eq(last(a).verdict, "ok")
    local p = protests()
    eq(#p, 1); eq({ p[1].seat, p[1].why, p[1].h }, { 3, "dealt", last(c).h })
    eq(a.session.fairCry, { h = last(c).h, seat = 3, name = C, why = "dealt" })
    sim:run(3)                                                       -- the next hand is dealt
    -- A claim beside my own verdict, which stays what it is and decides the colour.
    eq({ ns.Deal.status(a.session) }, { "fair.last", "ok" }); eq(ns.Deal.alarm(a.session), false)
    eq({ ns.Deal.claim(a.session) }, { C, "dealt" }); eq({ ns.Deal.claim(c.session) }, {})
    eq({ ns.Deal.status(c.session) }, { "fair.last", "bad" })
    -- Asked twice, or for a hand that is not the last one: nothing more.
    local q = a.session.seq
    a:receive("WHISPER", C, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "protest", h = p[1].h, why = "dealt" } })
    a:receive("WHISPER", C, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "protest", h = 1, why = "dealt" } })
    a:receive("WHISPER", C, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "protest", h = a.session.fair.h, why = "x" } })
    sim:run(1); eq(a.session.seq, q)
  end)
end)

-- The last snapshot the host sent to `name`, as a message of its own.
local function snapshotFor(name)
  for i = #sim.sent, 1, -1 do
    local m = sim.sent[i]
    if m.msg.t == "SNP" and m.target == name then return ns.Util.copy(m.msg) end
  end
  error("no snapshot for " .. name)
end

-- `cl` loses every EV until the returned function is called.
local function deaf(cl)
  cl.receive = function(self, channel, sender, msg)
    if msg.t == "EV" then return end
    return ns.Client.receive(self, channel, sender, msg)
  end
  return function() cl.receive = nil end
end

describe("deal cheats: the round a snapshot brings", function()
  -- The shuffle of hand 1 held open (b never commits); c's snapshot of it.
  local function shuffling()
    setup(true); sim:offline(B); a:startGame(); sim:run(1)
    eq({ a.session.fair.stage, c.session.fair.stage }, { "commit", "commit" })
    a.session:snapshotTo(C); sim:run(0)
    return snapshotFor(C)
  end

  it("a round whose participants are not the seated players is refused; a deal on it is нередовна", function()
    local m = shuffling()
    eq(m.fr.p, { 1, 2, 3 })
    m.fr.p, m.fr.d, m.fr.h, m.fr.c = { 1, 2 }, 1, m.fr.h + 1, {}; m.q = m.q + 1 -- c is no seed source any more
    c.session.asked = true
    c:receive("WHISPER", A, m)
    eq(c.session.fair, nil)
    local s = c.session
    c:receive("WHISPER", A, { v = 1, t = "EV", tid = tid, e = s.epoch, q = s.seq + 1, seat = 0, a = { k = "deal", deck = {} } })
    eq({ last(c).verdict, last(c).why }, { "bad", "commit" })
  end)

  it("a round with another dealer than the turn gives, a seat that does not exist or a wrong count is refused", function()
    for _, change in ipairs{
      function(fr) fr.d = 1 end,                       -- the host makes itself the dealer
      function(fr) fr.p = { 1, 2, 9 } end,
      function(fr) fr.n = -1 end,
      function(fr) fr.n = 0.5 end,
      function(fr) fr.h = fr.h + 100 end,              -- a round from the future
    } do
      local m = shuffling()
      eq(m.fr.d, 2)
      change(m.fr); m.fr.h = m.fr.h + 1; m.fr.c = {}; m.q = m.q + 1; c.session.asked = true
      c:receive("WHISPER", A, m)
      eq(c.session.fair, nil)
    end
    -- The same snapshot unchanged is taken.
    local m = shuffling()
    c.session.asked = true; c:receive("WHISPER", A, m)
    eq(c.session.fair.h, m.fr.h)
  end)

  it("another round that already carries a commit under my seat: нередовна (mine)", function()
    local m = shuffling()
    local mine = c.session.fair.own; ok(mine)
    m.fr.h, m.q = m.fr.h + 1, m.q + 1; m.fr.c = { [3] = mine }
    c.session.asked = true
    c:receive("WHISPER", A, m)
    eq({ c.session.fair.h, c.session.fair.foul }, { m.fr.h, "mine" })
    -- A client that has just logged in again cannot know: it takes the commit.
    local c2 = sim:relog(C); sim:run(2)
    eq(c2.session.fair.stage, "commit"); ok(c2.session.fair.commits[3]); eq(c2.session.fair.foul, nil)
  end)

  it("the same round with other participants or another dealer: нередовна (round)", function()
    local m = shuffling()
    m.fr.d = 3; m.fr.n = 1
    c.session.asked = true; c:receive("WHISPER", A, m)
    eq({ c.session.fair.d, c.session.fair.foul }, { 2, "round" })
  end)

  it("a snapshot I did not ask for that skips events of a hand I was watching whole: нередовна (round)", function()
    setup(true); a:startGame(); sim:run(1); auto(1)
    local hear = deaf(c); auto(1); hear()
    a.session:snapshotTo(C); sim:run(1)                              -- pushed on me
    eq(c.session.seq, a.session.seq)
    finish(); sim:run(1)
    eq({ last(c).verdict, last(c).why }, { "bad", "round" }); eq(last(a).verdict, "ok")
    eq(b.session.fairCry, { h = last(c).h, seat = 3, name = C, why = "round" })
  end)

  it("a snapshot I asked for after losing an event: не съм я гледал цялата", function()
    setup(true); a:startGame(); sim:run(1); auto(1)
    local hear = deaf(c); auto(1); hear()
    c.session:requestSync(); sim:run(1)
    eq(c.session.seq, a.session.seq)
    finish(); sim:run(1)
    eq({ last(c).verdict, last(c).why }, { "unseen", nil })
  end)

  it("a snapshot of the very event I am at that drops my hand or ends it: нередовна (round), not unseen", function()
    for _, change in ipairs{
      function(fr) return { n = fr.n } end,                          -- no round at all
      function(fr) fr.st = "done"; return fr end,
      function(fr) fr.h = fr.h + 1; return fr end,
    } do
      setup(true); a:startGame(); sim:run(1); auto(1)
      a.session:snapshotTo(C); sim:run(0)
      local m = snapshotFor(C); eq(m.q, c.session.seq)
      local h = c.session.fair.h
      m.fr = change(m.fr); c.session.asked = true
      c:receive("WHISPER", A, m)
      eq({ last(c).h, last(c).verdict, last(c).why }, { h, "bad", "round" })
    end
  end)

  it("an event my engine refuses during a hand is evidence: нередовна (play), not unseen", function()
    setup(true); a:startGame(); sim:run(1); auto(1)
    local s = c.session
    local desync = 0; c:on("desync", function() desync = desync + 1 end)
    c:receive("WHISPER", A, { v = 1, t = "EV", tid = tid, e = s.epoch, q = s.seq + 1, seat = 1, a = { k = "play", i = 12, c = "AD" } })
    eq(desync, 1); eq(c.session.fair.foul, "play")
    sim:run(1); finish(); sim:run(1)
    eq({ last(c).verdict, last(c).why }, { "bad", "play" })
    eq(b.session.fairCry, { h = last(c).h, seat = 3, name = C, why = "play" })
  end)

  it("a reason every client reaches by itself is not told again", function()
    setup(true); a:startGame(); sim:run(1)
    b.session.fair.revealed = true                                   -- the dealer keeps the seeds to itself
    finish(); sim:run(22)
    for _, cl in ipairs{ a, b, c } do eq({ got[cl][1].verdict, got[cl][1].why }, { "bad", "noreveal" }) end
    eq(a.session.fairCry, nil)
  end)

  -- Re-review of the fix wave: a complaint is a claim, not a verdict.
  it("a member who lies about an honest hand changes nobody's verdict or colour, and the claim ends with its hand", function()
    setup(true)
    a:startGame(); sim:run(1); finish(); sim:run(1)
    eq(last(b).verdict, "ok"); eq(last(a).verdict, "ok")
    local h = a.session.fairLast.h
    a:receive("WHISPER", C, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "protest", h = h, why = "mine" } })
    sim:run(0)
    for _, cl in ipairs{ a, b } do
      eq({ ns.Deal.status(cl.session) }, { "fair.last", "ok" }); eq(ns.Deal.alarm(cl.session), false)
      eq({ ns.Deal.claim(cl.session) }, { C, "mine" })
      eq(cl.session.fairSeen, { ok = 1, bad = 0 })
    end
    sim:run(3); finish(); sim:run(1)                                  -- the next hand closes: the claim is gone
    for _, cl in ipairs{ a, b } do
      ok(cl.session.fairLast.h ~= h)
      eq({ ns.Deal.status(cl.session) }, { "fair.last", "ok" }); eq(ns.Deal.alarm(cl.session), false)
      eq({ ns.Deal.claim(cl.session) }, {})
    end
  end)

  it("a complaint the host orders in my name: my verdict for that hand turns нередовна (forged) and I say so", function()
    setup(true)
    a:startGame(); sim:run(1); finish(); sim:run(1)
    local h = a.session.fairLast.h
    eq(last(b).verdict, "ok"); eq(b.session.fairSeen, { ok = 1, bad = 0 })
    local n = #got[b]
    a.session:play(0, { k = "fair", op = "protest", h = h, seat = 2, why = "mine" }); sim:run(1)
    eq(#got[b], n + 1); eq({ last(b).h, last(b).verdict, last(b).why }, { h, "bad", "forged" })
    eq(b.session.fairLast, { h = h, verdict = "bad", why = "forged", dealer = B })
    eq(b.session.fairSeen, { ok = 0, bad = 1 }); eq(ns.Deal.alarm(b.session), true)
    -- b tells the table what really happened; c sees that claim, its own verdict untouched.
    eq({ ns.Deal.claim(c.session) }, { B, "forged" })
    eq({ ns.Deal.status(c.session) }, { "fair.last", "ok" }); eq(ns.Deal.alarm(c.session), false)
    -- b's own complaint coming back is its own: nothing more happens.
    eq(#got[b], n + 1)
    -- In a hand still running the round is marked instead.
    sim:run(3); eq(b.session.fair.stage, "dealt")
    a.session:play(0, { k = "fair", op = "protest", h = b.session.fair.h, seat = 2, why = "dealt" }); sim:run(1)
    eq(b.session.fair.foul, "forged")
  end)

  it("with no replay left the shuffle and every face I saw are still checked against the revealed deck", function()
    setup()
    local real = ns.Deck.permutation
    ns.Deck.permutation = function(key, n) local p = real(key, n); p[1], p[2] = p[2], p[1]; return p end
    a:startGame(); sim:run(1); ns.Deck.permutation = real
    d:watch(tid); sim:run(1)                                         -- came mid-hand: nothing to replay
    eq(d.session.fair.base, nil)
    finish(); sim:run(1)
    eq({ last(d).verdict, last(d).why }, { "bad", "deal" })
    -- The honest case stays "unseen" (deal_audit_test: a watcher who came mid-hand).
  end)

  it("an open whose number is not the event's own is refused", function()
    setup(true); sim:offline(B); a:startGame(); sim:run(1)
    local s = c.session
    eq(ns.Ext.fair.table(s, { k = "fair", op = "open", h = s.seq, d = 2, p = { 1, 2, 3 } }), nil)
    ok(ns.Ext.fair.table(s, { k = "fair", op = "open", h = s.seq + 1, d = 2, p = { 1, 2, 3 } }))
  end)
end)

describe("deal cheats: a move in my name", function()
  it("the host plays my card for me: my verdict is нередовна (forged) and the table hears it", function()
    setup(true); a:startGame(); sim:run(1); auto(1); eq(a.session.state.turn, 2)
    local h = a.session.fair.h
    local want = H.auto(b.session.state, 2)
    a.session:play(2, want, true)                                    -- the host-ordered "automatic" move of seat 2
    sim:run(1); eq(b.session.fair.foul, "forged"); eq(c.session.fair.foul, nil)
    finish(); sim:run(1)
    eq({ got[b][1].h, got[b][1].verdict, got[b][1].why }, { h, "bad", "forged" })
    eq(got[c][1].verdict, "ok")
    eq(c.session.fairCry, { h = h, seat = 2, name = B, why = "forged" })
  end)

  it("my own moves, two in a row and my own timeout are mine", function()
    setup(true); a:startGame(); sim:run(1)
    local s = b.session
    -- Two actions on their way at once: both come back, in order.
    ns.Member.sendAct(s, { k = "x", n = 1 }); ns.Member.sendAct(s, { k = "x", n = 2 })
    ok(ns.Member.mine(s, { k = "x", n = 1 })); ok(ns.Member.mine(s, { k = "x", n = 2 }))
    eq(ns.Member.mine(s, { k = "x", n = 2 }), false)                 -- each of them once
    -- One the host dropped is forgotten with the next one that comes back.
    ns.Member.sendAct(s, { k = "x", n = 3 }); ns.Member.sendAct(s, { k = "x", n = 4 })
    ok(ns.Member.mine(s, { k = "x", n = 4 })); eq(ns.Member.mine(s, { k = "x", n = 3 }), false)
    for n = 1, 20 do ns.Member.sendAct(s, { k = "x", n = n }) end; eq(#s.sent, 8)
    -- A whole hand where b's last move is its own deadline: проверена.
    auto(1); eq(a.session.state.turn, 2); sim:run(46)
    ok(a.session.state.turn ~= 2)
    finish(); sim:run(1)
    eq(got[b][1].verdict, "ok")
  end)
end)

describe("deal cheats: what the dealer publishes", function()
  local function act(x) return { v = 1, t = "ACT", tid = tid, a = x } end

  it("the host refuses a deal or a show that publishes a face a watcher may not see", function()
    setup()
    local held
    a.receive = function(self, channel, sender, msg)
      if msg.t == "ACT" and type(msg.a) == "table" and msg.a.op == "deal" then held = ns.Util.copy(msg); return end
      return ns.Client.receive(self, channel, sender, msg)
    end
    a:startGame(); sim:run(1); a.receive = nil
    ok(held); eq(a.session.fair.stage, "seed")
    local deck, h, q = b.session.fair.deck, a.session.fair.h, a.session.seq
    eq(held.a.deck, { [5] = deck[5] })                               -- the up card only
    -- With a card of the host's hand in it (anybody watching would see it).
    a:receive("WHISPER", B, act{ k = "fair", op = "deal", h = h, deck = { [5] = deck[5], [1] = deck[1] } })
    eq({ a.session.seq, a.session.fair.stage }, { q, "seed" })
    a:receive("WHISPER", B, held)
    eq({ a.session.seq, a.session.fair.stage }, { q + 1, "dealt" }); sim:run(1)
    q = a.session.seq
    a:receive("WHISPER", B, act{ k = "fair", op = "show", h = h, cards = { [2] = deck[2] } }) -- a card b still holds
    a:receive("WHISPER", B, act{ k = "fair", op = "show", h = h, cards = { [9] = deck[9] } }) -- a card of the stock
    eq(a.session.seq, q)
    finish(); sim:run(1)
    eq(last(a).verdict, "ok"); eq(last(b).verdict, "ok")
  end)
end)
