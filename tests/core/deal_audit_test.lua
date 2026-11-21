local Sim = require("sim")
local H = require("hicard_engine")
local ns = Sim.ns

local A, B, D = "Иван Петров", "Мария Стоянова", "Пешо Тодоров"
local SEED = ("ff"):rep(16)
-- The seeds of the honest runs: every client its own, so a wrong audit cannot pass by accident.
local SA, SB = ("11"):rep(16), ("22"):rep(16)
local sim, tid, a, b, d
local got -- client -> the "fair" payloads it received

-- a hosts hicard, b on seat 2, d online but not at the table; not started.
-- `bytes` (optional) = name -> the byte that client's env.random always yields.
local function setup(bytes)
  sim, got = Sim.new(), {}
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  d = sim:add(D, { cls = "DRUID" })
  for _, cl in ipairs{ a, b, d } do
    local list = {}
    got[cl] = list
    cl:on("fair", function(e) list[#list + 1] = e end)
  end
  for name, byte in pairs(bytes or {}) do
    sim.clients[name].env.random = function() return byte end
  end
  sim:run(1)
  tid = a:openTable{ game = "hicard", access = "guild", turn = 45 }; sim:run(3)
  b:sit(tid, 2); sim:run(1)
  return sim, tid
end
local function table2() return setup() end
local function honest() return setup({ [A] = 0x11, [B] = 0x22 }) end

local function start() a:startGame(); sim:run(1) end

-- n times: the client whose seat is on turn plays its automatic move.
local function auto(n)
  for _ = 1, n do
    local s = a.session
    local cl = sim.clients[s.seats[s.state.turn]]
    ok(cl:playAuto())
    sim:run(1)
  end
end

-- Automatic moves until the hand (or the match) is over.
local function finish()
  for _ = 1, 12 do
    if not a.session.state.turn then return end
    auto(1)
  end
  error("the hand does not end")
end

local function events(cl) return got[cl] end

-- The clock reaches t.
local function runTo(t)
  if t > sim.clock then sim:run(t - sim.clock) end
end

-- When the host ordered the last play.
local function lastPlayAt()
  local at
  for _, m in ipairs(sim.sent) do
    if m.msg.t == "EV" and m.from == A and type(m.msg.a) == "table" and m.msg.a.k == "play" then at = m.at end
  end
  return at
end

-- Plays the match to its end -> hands dealt, h of the last round. With
-- `withhold`: the dealer of hand number `withhold` keeps its seeds to itself.
local function playMatch(withhold)
  for _ = 1, 80 do
    local s = a.session
    if s:gameOver() then return s.fairN, s.fair.h end
    if withhold and s.fairN == withhold and s.fair.stage == "dealt" then
      sim.clients[s.fair.dealer].session.fair.revealed = true
    end
    if s.state.turn then auto(1) else sim:run(1) end
  end
  error("the match does not end")
end

-- Every string anywhere in v that looks like a seed or a commit (32 or 64 lowercase hex).
local function hexes(v, out)
  out = out or {}
  if type(v) == "string" then
    if (#v == 32 or #v == 64) and v:match("^[0-9a-f]+$") then out[#out + 1] = v end
  elseif type(v) == "table" then
    for k, x in pairs(v) do hexes(k, out); hexes(x, out) end
  end
  return out
end

local function sentOf(t)
  local out = {}
  for _, m in ipairs(sim.sent) do
    if m.msg.t == t then out[#out + 1] = m end
  end
  return out
end

local function opensTo(target)
  local n = 0
  for _, m in ipairs(sim.sent) do
    if m.msg.t == "EV" and m.from == A and m.target == target and type(m.msg.a) == "table" and m.msg.a.op == "open" then
      n = n + 1
    end
  end
  return n
end

local function isReveal(m)
  return (m.msg.t == "ACT" or m.msg.t == "EV") and type(m.msg.a) == "table" and m.msg.a.op == "reveal"
end

-- A seed of `seeds` travels only to the dealer (SED) and, after the hand, in the reveal.
local function seedsOnlyInRevealAndSED(seeds)
  local secret = {}
  for _, x in ipairs(seeds) do secret[x] = true end
  for _, m in ipairs(sim.sent) do
    for _, x in ipairs(hexes(m.msg)) do
      if secret[x] then ok(m.msg.t == "SED" or isReveal(m), m.msg.t .. " from " .. m.from .. " carries a seed") end
    end
  end
end

-- Sets sim.nextRandom so that A's seed, with B's SEED, gives a deck of hand h
-- that satisfies pred.
local function rig(sim, tid, h, pred)
  for k = 0, 255 do
    local seedA = string.format("%02x", k) .. ("ff"):rep(15)
    if pred(ns.Fair.deck(H.DECK, { seedA, SEED }, tid .. "/" .. h)) then
      sim.nextRandom = { k }
      for i = 2, 16 do sim.nextRandom[i] = 255 end
      return
    end
  end
  error("rig: no seed gives such a deck")
end

local function act(x) return { v = 1, t = "ACT", tid = tid, a = x } end

describe("deal audit", function()
  it("after the hand everyone replays it and marks it проверена", function()
    local sim, tid = honest(); d:watch(tid); sim:run(1); start(); local h = a.session.fair.h; auto(6); sim:run(1)
    for _, cl in ipairs{ a, b, d } do
      eq(#events(cl), 1); local e = events(cl)[1]
      eq({ e.tid, e.h, e.verdict, e.why, e.dealer, e.game }, { tid, h, "ok", nil, B, "hicard" })
      eq(type(e.at), "number")
      eq(cl.session.fairLast, { h = h, verdict = "ok", dealer = B }); eq(cl.session.fairSeen, { ok = 1, bad = 0 })
    end
    -- The reveal EV carries the seeds in seat order, after the last play and before the next open.
    local lastPlay, reveal, nextOpen
    for i, m in ipairs(sim.sent) do
      if m.msg.t == "EV" and m.from == A and m.target == D then
        local x = m.msg.a
        if x.k == "play" then lastPlay = i end
        if x.op == "reveal" then reveal = i; eq({ x.h, x.s }, { h, { SA, SB } }) end
        if x.op == "open" and x.h ~= h then nextOpen = nextOpen or i end
      end
    end
    ok(lastPlay and reveal and nextOpen); ok(lastPlay < reveal); ok(reveal < nextOpen)
    seedsOnlyInRevealAndSED({ SA, SB })
  end)

  it("the deal passes to the next seat and the host can be the dealer", function()
    local sim, tid = honest(); d:watch(tid); sim:run(1); start(); auto(6); sim:run(2)
    local r = a.session.fair; eq({ r.d, r.stage, r.dealer }, { 1, "dealt", A }); eq(a.session.fairN, 2)
    local deck = a.session.fair.deck; ok(deck ~= nil); eq(b.session.fair.deck, nil)
    eq(deck, ns.Fair.deck(H.DECK, { SA, SB }, tid .. "/" .. r.h))
    eq(b.session.state.deck, { [1] = deck[1], [3] = deck[3], [5] = deck[5] })
    local toB = 0
    for _, m in ipairs(sentOf("PRV")) do
      ok(not (m.from == A and m.target == A))
      if m.from == A and m.target == B then toB = toB + 1 end
    end
    ok(toB >= 1)
    finish(); sim:run(1)
    for _, cl in ipairs{ a, b, d } do
      eq(#events(cl), 2); eq({ events(cl)[2].verdict, events(cl)[2].dealer, events(cl)[2].h }, { "ok", A, r.h })
      eq(cl.session.fairSeen, { ok = 2, bad = 0 })
    end
  end)

  it("a watcher who came mid-hand cannot vouch for it", function()
    local sim, tid = honest(); start(); d:watch(tid); sim:run(1); auto(6); sim:run(1)
    eq(#events(d), 1); eq({ events(d)[1].verdict, events(d)[1].why }, { "unseen", nil })
    eq(d.session.fairSeen, { ok = 0, bad = 0 })
    eq(events(a)[1].verdict, "ok"); eq(events(b)[1].verdict, "ok")
    -- The snapshot the watcher got mid-hand carried no seed.
    seedsOnlyInRevealAndSED({ SA, SB })
  end)

  it("a modified deck is flagged нередовна by everyone", function()
    local sim, tid = honest(); d:watch(tid); sim:run(1)
    local real = ns.Deck.permutation
    ns.Deck.permutation = function(key, n) local p = real(key, n); p[1], p[2] = p[2], p[1]; return p end
    start(); ns.Deck.permutation = real; auto(6); sim:run(1)
    eq({ events(a)[1].verdict, events(a)[1].why }, { "bad", "dealt" })      -- the card A was sent is not the deck's
    eq({ events(b)[1].verdict, events(b)[1].why }, { "bad", "dealt" })
    eq({ events(d)[1].verdict, events(d)[1].why }, { "bad", "play" })       -- A played a face the deck does not have there
    eq(a.session.fairSeen, { ok = 0, bad = 1 }); eq(d.session.fairSeen, { ok = 0, bad = 1 })
    eq(a.session.fairLast, { h = events(a)[1].h, verdict = "bad", why = "dealt", dealer = B })
  end)

  it("a move only the full deck can judge passes at the table and is flagged at the reveal", function()
    local sim, tid = table2(); d:watch(tid); sim:run(1)
    local function suit(f) return f:sub(2, 2) end
    rig(sim, tid, a.session.seq + 2, function(k) return suit(k[2]) ~= suit(k[4]) end)     -- B holds one card of each suit
    start(); local deck = b.session.fair.deck; local off = suit(deck[2]) == suit(deck[5]) and 4 or 2
    eq(a.session.fair.commits[1] ~= a.session.fair.commits[2], true)                 -- two different seeds
    auto(1); local q = a.session.seq
    a:receive("WHISPER", B, { v = 1, t = "ACT", tid = tid, a = { k = "play", i = off, c = deck[off] } }); sim:run(1)
    eq(a.session.seq > q, true)                                                 -- the host, on its view, cannot refuse it
    finish(); sim:run(1)
    eq({ events(a)[1].verdict, events(a)[1].why }, { "bad", "play" })
    eq({ events(d)[1].verdict, events(d)[1].why }, { "bad", "play" })
  end)

  it("a late reveal is not followed by a stale reopen", function()
    local sim = honest(); start(); auto(5); local h = a.session.fair.h
    local held = {}
    a.receive = function(self, channel, sender, msg)
      if msg.t == "ACT" and type(msg.a) == "table" and msg.a.op == "reveal" then
        held[#held + 1] = { channel, sender, msg }
        return
      end
      return ns.Client.receive(self, channel, sender, msg)
    end
    auto(1); sim:run(1)
    eq(#held, 1); eq(a.session.fair.stage, "dealt"); eq(a.session.fair.wantOpen, true)
    local timer = a.session.fairTimer; ok(timer)
    for _ = 1, 3 do ns.Ext.fair.need(a.session, { k = "deal", need = "deck" }) end
    eq(a.session.fairTimer, timer); eq(opensTo(B), 1)                            -- armed once, nothing reopened
    sim:run(9); a.receive = nil
    a:receive(held[1][1], held[1][2], held[1][3])                                -- 10 s after the need
    ok(a.session.fair.h ~= h); eq(opensTo(B), 2)                                 -- the next round opens at once
    sim:run(15); eq(opensTo(B), 2); eq(a.session.fair.stage, "dealt")
    for _, cl in ipairs{ a, b } do
      eq(#events(cl), 1); eq({ events(cl)[1].verdict, events(cl)[1].h }, { "ok", h })
    end
  end)


  it("a dealer that never reveals: the next round opens 20 s after the hand and the hand is нередовна", function()
    local sim = honest(); start(); auto(5); local h = a.session.fair.h
    b.session.fair.revealed = true                                               -- the dealer keeps its seeds to itself
    auto(1); local t0 = lastPlayAt()
    ok(a.session.fairTimer); sim:run(1); eq(a.session.fair.wantOpen, true)
    for _, m in ipairs(sim.sent) do ok(not isReveal(m)) end
    runTo(t0 + 19); eq(opensTo(B), 1); eq(#events(a), 0)
    runTo(t0 + 21); eq(opensTo(B), 2)
    for _, cl in ipairs{ a, b } do
      eq(#events(cl), 1); eq({ events(cl)[1].verdict, events(cl)[1].why, events(cl)[1].h }, { "bad", "noreveal", h })
    end
    eq(a.session.fairSeen, { ok = 0, bad = 1 })
    local r = a.session.fair; ok(r.h ~= h); eq({ r.d, r.stage }, { 1, "dealt" })
  end)

  it("a host dealing without the commits: нередовна, and no round is left", function()
    local sim, tid = honest(); d:watch(tid); sim:run(1); sim:offline(B); start()
    eq(a.session.fair.stage, "commit"); eq(d.session.fair.stage, "commit")
    local h = a.session.fair.h
    a.session:play(0, { k = "deal" }); sim:run(1)
    for _, cl in ipairs{ a, d } do
      eq(#events(cl), 1); eq({ events(cl)[1].verdict, events(cl)[1].why, events(cl)[1].h }, { "bad", "commit", h })
      eq(cl.session.fair, nil); eq(cl.session.fairSeen, { ok = 0, bad = 1 })
    end
  end)

  it("a deal after a closed hand is нередовна without touching that hand's verdict", function()
    local sim, tid = honest(); d:watch(tid); sim:run(1); sim:offline(B); start()
    for _, cl in ipairs{ a, d } do cl.session.fair.stage = "done" end           -- as after a closed hand
    a.session:play(0, { k = "deal" }); sim:run(1)
    for _, cl in ipairs{ a, d } do
      eq(#events(cl), 1); eq({ events(cl)[1].verdict, events(cl)[1].why, events(cl)[1].h }, { "bad", "commit", nil })
      eq(cl.session.fairLast, { verdict = "bad", why = "commit" }); eq(cl.session.fair, nil)
    end
  end)

  it("an honest last hand of the match is проверена, and a new match starts with no verdict", function()
    local sim, tid = honest(); d:watch(tid); sim:run(1); start()
    local n, last = playMatch()
    for _, cl in ipairs{ a, b, d } do
      eq(#events(cl), n)                                                         -- every hand, the last one too
      eq({ events(cl)[n].verdict, events(cl)[n].h }, { "ok", last })
      eq(cl.session.fairLast.verdict, "ok"); eq(cl.session.fairSeen, { ok = n, bad = 0 })
    end
    sim:run(25)
    for _, cl in ipairs{ a, b, d } do eq(#events(cl), n) end                    -- nothing more after the wait
    ok(a:startGame()); sim:run(1)
    for _, cl in ipairs{ a, b, d } do eq({ cl.session.fairLast, cl.session.fairSeen }, {}); eq(#events(cl), n) end
  end)

  it("a dealer that withholds the last hand of the match: нередовна after the wait, on everyone", function()
    honest(); start(); local n = playMatch()                                     -- how many hands the match takes
    local sim, tid = honest(); d:watch(tid); sim:run(1); start()
    local _, last = playMatch(n)
    eq(a.session.fairN, n); local t0 = lastPlayAt()
    for _, m in ipairs(sim.sent) do
      if isReveal(m) then ok(m.msg.a.h ~= last) end
    end
    runTo(t0 + 19)
    for _, cl in ipairs{ a, b, d } do eq(#events(cl), n - 1); eq(cl.session.fair.stage, "dealt") end
    runTo(t0 + 21)
    for _, cl in ipairs{ a, b, d } do
      eq(#events(cl), n); eq({ events(cl)[n].verdict, events(cl)[n].why, events(cl)[n].h }, { "bad", "noreveal", last })
      eq(cl.session.fairSeen, { ok = n - 1, bad = 1 }); eq(cl.session.fairLast.why, "noreveal")
    end
    eq(opensTo(B), n)                                                            -- no round opened after the match
  end)

  it("„Нова игра“ before the wait is over: the withheld last hand is нередовна, then the match starts clean", function()
    honest(); start(); local n = playMatch()
    local sim, tid = honest(); d:watch(tid); sim:run(1); start()
    local _, last = playMatch(n)
    sim:run(5)
    for _, cl in ipairs{ a, b, d } do eq(#events(cl), n - 1) end
    ok(a:startGame()); sim:run(1)
    for _, cl in ipairs{ a, b, d } do
      eq(#events(cl), n); eq({ events(cl)[n].verdict, events(cl)[n].why, events(cl)[n].h }, { "bad", "noreveal", last })
      eq({ cl.session.fairLast, cl.session.fairSeen }, {})
      eq({ cl.session.fairN, cl.session.fair.stage }, { 1, "dealt" })
    end
    sim:run(25)
    for _, cl in ipairs{ a, b, d } do eq(#events(cl), n) end
  end)

  it("a hand closed noreveal takes no late reveal and no second noreveal: one verdict", function()
    honest(); start(); local n = playMatch()
    local sim, tid = honest(); d:watch(tid); sim:run(1); start()
    local _, last = playMatch(n); runTo(lastPlayAt() + 21)
    for _, cl in ipairs{ a, b, d } do
      eq(#events(cl), n); eq({ events(cl)[n].why, cl.session.fair.stage }, { "noreveal", "done" })
    end
    local r = a.session.fair
    local dealer = sim.clients[r.dealer].session.fair
    local seeds = {}
    for k, q in ipairs(r.p) do seeds[k] = dealer.seeds[q] end
    -- The withheld seeds, late: neither the host nor a member takes them now.
    local late = { k = "fair", op = "reveal", h = last, s = seeds }
    local again = { k = "fair", op = "noreveal", h = last }
    for _, x in ipairs{ late, again } do
      local q = a.session.seq
      if r.dealer ~= A then
        a:receive("WHISPER", r.dealer, act(x)); eq(a.session.seq, q)          -- the dealer's own late ACT
      end
      a.session:play(0, x); eq(a.session.seq, q)                               -- the host orders it anyway
      eq(ns.Ext.fair.table(a.session, x), nil)
      for _, cl in ipairs{ b, d } do                                           -- an EV that orders it reaches a member
        local s = cl.session
        eq(s:apply(0, x), nil)
        cl:receive("WHISPER", A, { v = 1, t = "EV", tid = tid, e = s.epoch, q = s.seq + 1, seat = 0, a = x })
      end
      sim:run(2)
    end
    for _, cl in ipairs{ a, b, d } do
      eq(#events(cl), n); eq({ events(cl)[n].verdict, events(cl)[n].why, events(cl)[n].h }, { "bad", "noreveal", last })
      eq(cl.session.fairSeen, { ok = n - 1, bad = 1 }); eq(cl.session.fairLast, { h = last, verdict = "bad", why = "noreveal", dealer = r.dealer })
    end
  end)
end)
