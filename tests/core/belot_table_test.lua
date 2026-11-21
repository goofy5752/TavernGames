local Sim = require("sim")
local ns = Sim.ns
local E = ns.Engines.belot

local A, B, C, D, W = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров", "Гледач Гледачев"
local SEED = ("ff"):rep(16)
local REAL = ns.Ext.fair
local sim, tid, a, b, c, d, w

-- Four hands of eight faces each (the first five are dealt before the auction) -> the deck
-- that deals them.
local function deckOf(h1, h2, h3, h4)
  local hands, deck = {}, {}
  for seat, str in ipairs({ h1, h2, h3, h4 }) do
    hands[seat] = {}
    for face in str:gmatch("%S+") do hands[seat][#hands[seat] + 1] = face end
    assert(#hands[seat] == 8, "a hand has 8 cards")
  end
  for j = 1, 20 do deck[j] = hands[(j - 1) % 4 + 1][math.floor((j - 1) / 4) + 1] end
  for j = 21, 32 do deck[j] = hands[(j - 1) % 4 + 1][6 + math.floor((j - 21) / 4)] end
  local seen = {}
  for _, face in ipairs(deck) do
    assert(not seen[face], "duplicate " .. face)
    seen[face] = true
  end
  return deck
end

local DECK1 = deckOf(
  "7C 8C 9C TC JC QC KC AC",
  "7D 8D 9D TD JD QD KD AD",
  "7H 8H 9H TH JH QH KH AH",
  "7S 8S 9S TS JS QS KS AS")

local DECK_A = deckOf(
  "AH KH 7H 8C JS 9S 7D 8D",
  "TH QH 9H 7C QS KS AD TD",
  "JH 8H 9C TC 7S 8S JD QD",
  "AC KC QC JC AS TS KD 9D")

-- a hosts Белот, w watches, b, c and d sit at seats 2, 3, 4: the match starts
-- and the first deal is dealt. Every client yields SEED (prepare(sim), when
-- given, runs first: e.g. to feed sim.nextRandom).
local function table4(prepare)
  sim = Sim.new()
  if prepare then prepare(sim) end
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  c = sim:add(C, { cls = "ROGUE" })
  d = sim:add(D, { cls = "DRUID" })
  w = sim:add(W, { cls = "HUNTER" })
  sim:run(1)
  tid = a:openTable{ game = "belot", access = "guild", turn = 45 }; sim:run(3)
  w:watch(tid); sim:run(1)
  b:sit(tid, 2); sim:run(1)
  c:sit(tid, 3); sim:run(1)
  d:sit(tid, 4); sim:run(1)
  return sim, tid
end

-- The current client of the player on `seat`.
local function at(seat) return sim.clients[a.session.seats[seat]] end

-- Each token of `str` bid by the client on turn, one second apart.
local function bid(str)
  for token in str:gmatch("%S+") do
    local seat = a.session.state.turn
    ok(at(seat):act{ k = "bid", b = token }, "bid " .. token)
    sim:run(1)
  end
end

-- n times: the client on turn makes its automatic move (stops when no seat is on turn).
local function autoPlay(n)
  for _ = 1, n do
    local seat = a.session.state.turn
    if not seat then return end
    ok(at(seat):playAuto())
    sim:run(1)
  end
end

-- The number of faces my state knows.
local function known(cl)
  local n = 0
  for _ in pairs(cl.session.state.deck) do n = n + 1 end
  return n
end

local function verdicts(cl)
  local list = {}
  cl:on("fair", function(e) list[#list + 1] = e.verdict end)
  return list
end

local function sentOf(t)
  local out = {}
  for _, m in ipairs(sim.sent) do
    if m.msg.t == t then out[#out + 1] = m end
  end
  return out
end

-- Every card face anywhere in v (keys and values).
local function faces(v, out)
  out = out or {}
  if type(v) == "string" then
    if v:match("^[789TJQKA][CDHS]$") then out[#out + 1] = v end
  elseif type(v) == "table" then
    for k, x in pairs(v) do faces(k, out); faces(x, out) end
  end
  return out
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

-- The "result" payloads `cl` emits from now on.
local function results(cl)
  local list = {}
  cl:on("result", function(r) list[#list + 1] = r end)
  return list
end

-- No fair deal: nothing deals by itself (the test puts ns.Ext.fair = REAL back at its end).
local function rigged() ns.Ext.fair = {} end

-- The host deals `deck` whole (a test shortcut: every client knows every face).
local function dealAll(deck)
  a.session:play(0, { k = "deal", deck = deck }); sim:run(1)
end

-- The play of `face` (or of the first card of the hand) by the client on turn, from its own state.
local function playOne(face)
  local seat = a.session.state.turn
  local st = at(seat).session.state
  local i = st.hands[seat][1]
  if face then
    for k = 1, 32 do if st.deck[k] == face then i = k end end
  end
  ok(at(seat):act{ k = "play", i = i, c = st.deck[i] }, "play " .. tostring(st.deck[i]))
  sim:run(1)
end

-- n times: the client on turn plays the first card of its hand.
local function playFirst(n)
  for _ = 1, n do playOne() end
end

-- Each face of `str` played by the client on turn, one second apart.
local function playFaces(str)
  for face in str:gmatch("%S+") do playOne(face) end
end

-- `cl` ignores every message of type t (only those for which pred(sender, msg)
-- holds, when given) until the returned function is called.
local function drop(cl, t, pred)
  cl.receive = function(self, channel, sender, msg)
    if msg.t == t and (not pred or pred(sender, msg)) then return end
    return ns.Client.receive(self, channel, sender, msg)
  end
  return function() cl.receive = nil end
end

-- An ACT asking for the fair op `op` (for drop).
local function asks(op) return function(_, msg) return type(msg.a) == "table" and msg.a.op == op end end

local function set(list)
  local out = {}
  for _, x in ipairs(list) do out[x] = true end
  return out
end

describe("belot at the table", function()
  it("four players get five cards, then three more; the dealer is the seat before the first bidder", function()
    local sim, tid = table4(); local r = a.session.fair
    eq({ a.session.state.phase, a.session.state.turn, r.d, r.p, r.dealer, r.stage }, { "bid", 1, 4, { 1, 2, 3, 4 }, D, "dealt" })
    local deck = d.session.fair.deck; eq(deck, ns.Fair.deck(E.DECK, { SEED, SEED, SEED, SEED }, tid .. "/" .. r.h)); eq(a.session.fair.deck, nil)
    eq({ known(a), known(b), known(c), known(d), known(w) }, { 5, 5, 5, 5, 0 })
    for q = 1, 4 do for _, i in ipairs(a.session.state.hands[q]) do eq(at(q).session.state.deck[i], deck[i]) end end
    eq(#sentOf("SED"), 3); for _, m in ipairs(sentOf("SED")) do eq(m.target, D) end; eq(#sentOf("PRV"), 3)
    bid("S P P P"); eq({ a.session.state.phase, a.session.state.turn, #a.session.state.hands[2] }, { "play", 1, 8 })
    eq({ known(a), known(b), known(c), known(d), known(w) }, { 8, 8, 8, 8, 0 }); eq(#sentOf("PRV"), 6)
    for _, m in ipairs(sentOf("PRV")) do eq(m.from, D) end
    local h = b.session.seq + 1                                                                    -- a host naming another dealer is refused
    eq(ns.Ext.fair.table(b.session, { k = "fair", op = "open", h = h, d = 3, p = { 1, 2, 3, 4 } }), nil)   -- d = 3 is the formula's seat p[(1 + 1) % 4 + 1]
    eq(ns.Ext.fair.table(b.session, { k = "fair", op = "open", h = h, d = 2, p = { 1, 2, 3, 4 } }), nil)   -- no positive control: it would replace b's round
  end)

  it("the deal passes to the next seat every deal, played or passed out, and every deal is проверена", function()
    table4()
    local atA, atC, atW = verdicts(a), verdicts(c), verdicts(w)
    local dealers = { a.session.fair.d }
    bid("C P P P"); autoPlay(200); eq(a.session.state.turn, nil); sim:run(3)
    eq(a.session.state.res.contract.b, "C")
    for _ = 1, 3 do
      sim:run(8)
      eq({ a.session.state.phase, a.session.fair.stage }, { "bid", "dealt" })
      dealers[#dealers + 1] = a.session.fair.d
      autoPlay(4)
    end
    eq(dealers, { 4, 1, 2, 3 })
    eq(atA, { "ok", "ok", "ok", "ok" }); eq(atC, { "ok", "ok", "ok", "ok" }); eq(atW, { "ok", "ok", "ok", "ok" })
    eq({ a.session.state.round, a.session.state.first }, { 5, 1 })
  end)

  it("no message to another seat or a watcher carries a face it may not see: four shuffled deals with announces, a relog and a late watcher", function()
    -- Seeds from a fixed generator instead of the simulator's constant: every deal is another deck.
    local x = 20261122
    table4(function(sim)
      for n = 1, 4000 do
        x = (x * 1103515245 + 12345) % 2147483648
        sim.nextRandom[n] = math.floor(x / 65536) % 256
      end
    end)
    local X = "Нов Гледач"
    local late = sim:add(X); sim:run(1)
    local watching = { [W] = true, [X] = true }
    local seatOf = {}
    for q = 1, 4 do seatOf[a.session.seats[q]] = q end
    local held, public
    local mark, plays, anns, prvs, decks = 0, 0, 0, 0, {}
    -- Every message since the last check, against what its target may know by now: the cards
    -- its seat holds or held in this deal, and the cards played in it.
    local function check()
      local dealer = at(a.session.fair.d).session
      local deck = dealer.fair.deck
      if deck and a.session.fair.stage == "dealt" then
        local st = dealer.state
        for q, hand in ipairs(ns.Fair.full(st, deck).hands) do
          for _, i in ipairs(hand) do held[q][deck[i]] = true end
        end
        for _, i in ipairs(st.trick) do public[deck[i]] = true end
        if st.last then for _, i in ipairs(st.last.cards) do public[deck[i]] = true end end
      end
      for k = mark + 1, #sim.sent do
        local m = sim.sent[k]
        local fs, q = faces(m.msg), seatOf[m.target]
        if m.channel == "GUILD" then
          eq(fs, {}); ok(m.msg.t ~= "SED" and m.msg.t ~= "PRV" and m.msg.t ~= "PRQ", m.msg.t); eq(hexes(m.msg), {})
        elseif watching[m.target] then
          for _, f in ipairs(fs) do ok(public[f], m.msg.t .. " to a watcher: " .. f) end
        elseif q then
          for _, f in ipairs(fs) do ok(public[f] or held[q][f], m.msg.t .. " to seat " .. q .. ": " .. f) end
        else
          eq(fs, {})
        end
        local ev = m.target == B and m.msg.t == "EV" and type(m.msg.a) == "table" and m.msg.a.k
        if ev == "play" then plays = plays + 1 elseif ev == "ann" then anns = anns + 1 end
        if m.msg.t == "PRV" then prvs = prvs + 1 end
      end
      mark = #sim.sent
    end
    for deal = 1, 4 do
      eq({ a.session.state.phase, a.session.fair.stage }, { "bid", "dealt" })
      held, public = { {}, {}, {}, {} }, {}
      decks[deal] = table.concat(at(a.session.fair.d).session.fair.deck, " ")
      check()
      for token in ("A P P P"):gmatch("%S+") do bid(token); check() end                       -- Всичко коз: every run and four counts
      local steps = 0
      while a.session.state.phase == "play" do
        steps = steps + 1; ok(steps < 100, "the deal does not end")
        autoPlay(1); check()
        if deal == 2 and steps == 9 then                                                         -- mid-deal: a player logs in again, a watcher comes
          sim:relog(C); late:watch(tid); sim:run(3); check()
          eq({ ns.Deal.missing(sim.clients[C].session), late.session ~= nil }, { false, true })
        end
        if deal == 3 and steps == 9 then                                                         -- and the dealer of this deal reloads
          eq(a.session.fair.d, 2); sim:relog(B); sim:run(3); check()
          ok(sim.clients[B].session.fair.deck ~= nil, "the dealer lost its deck")
        end
      end
      sim:run(3); check()                                                                        -- the score and the reveal: every card was played
      sim:run(6)
    end
    eq(plays, 4 * 32)
    ok(anns > 0, "no deal had an announce")
    ok(prvs >= 4 * 6 + 2, "private deals: " .. prvs)
    ok(decks[1] ~= decks[2] and decks[2] ~= decks[3] and decks[3] ~= decks[4], "the same deck twice")
    eq(a.session.fairSeen, { ok = 4, bad = 0 }); eq(w.session.fairSeen, { ok = 4, bad = 0 })
  end)

  it("a snapshot mid-deal shows a newcomer the played cards and only its own hand", function()
    table4()
    local X = "Нов Гледач"
    local x = sim:add(X); sim:run(1)
    bid("S P P P"); autoPlay(6)
    local st = ns.Fair.full(d.session.state, d.session.fair.deck)
    local inHand = {}
    for q = 1, 4 do for _, i in ipairs(st.hands[q]) do inHand[i] = true end end
    local played = {}
    for i = 1, 32 do if not inHand[i] then played[#played + 1] = st.deck[i] end end
    ok(#played > 0)
    local c2 = sim:relog(C); x:watch(tid); sim:run(3)
    local toX, toC
    for _, m in ipairs(sentOf("SNP")) do
      if m.target == X then toX = m end
      if m.target == C then toC = m end
    end
    ok(toX and toC, "no snapshot")
    eq(set(faces(toX.msg.st)), set(played))
    eq(set(faces(toC.msg.st)), set(played))                                                     -- the host does not know C's hand
    eq(ns.Deal.missing(c2.session), false); eq(known(c2), #played + #st.hands[3])
    local prq = 0
    for _, m in ipairs(sentOf("PRQ")) do
      if m.from == C then prq = prq + 1; eq(m.target, D) end
    end
    eq(prq, 1)
  end)

  it("nobody bids: four automatic passes, the deal is passed out, the next seat deals", function()
    local sim = table4(); local seen, atB, atC, atD, atW = verdicts(a), verdicts(b), verdicts(c), verdicts(d), verdicts(w); local mark = #sim.sent
    sim:run(182); eq({ a.session.state.round, a.session.state.first }, { 2, 2 }); eq(a.session.state.res.contract, nil); eq(seen, { "ok" })
    eq(atB, { "ok" }); eq(atC, { "ok" }); eq(atD, { "ok" }); eq(atW, { "ok" })                  -- a pass the host made for a seat would be "forged" there
    local from, acts = {}, { [A] = 0, [B] = 0, [C] = 0, [D] = 0 }
    for k = mark + 1, #sim.sent do
      local m = sim.sent[k]
      local x = type(m.msg.a) == "table" and m.msg.a
      if x and x.k == "bid" and m.msg.t == "EV" and m.target == B then
        eq(x.b, "P"); from[#from + 1] = m.msg.seat
      end
      if x and x.k == "bid" and m.msg.t == "ACT" then acts[m.from] = acts[m.from] + 1 end
    end
    eq(from, { 1, 2, 3, 4 }); eq(acts, { [A] = 0, [B] = 1, [C] = 1, [D] = 1 })
    sim:run(15); eq({ a.session.state.phase, a.session.state.turn, a.session.fair.d, a.session.fair.stage }, { "bid", 2, 1, "dealt" })
  end)

  it("a passed-out deal is closed by its reveal: the dealer's reload and a late void find nothing to annul", function()
    table4()
    local atA, atC = verdicts(a), verdicts(c)
    local h = a.session.fair.h
    bid("P P P P")                                                                  -- phase "deal" again: a void would be refused "phase"
    eq({ a.session.state.phase, a.session.state.first, a.session.fair.h, a.session.fair.stage }, { "deal", 2, h, "done" })
    eq(atA, { "ok" }); eq(atC, { "ok" })
    local d2 = sim:relog(D); sim:run(1)                                             -- before the next open (5 s after the pass-out)
    eq({ d2.session.fair.h, d2.session.fair.d, d2.session.fair.stage }, { h, 4, "done" })      -- the snapshot's closed round fits
    local mark = #sim.sent
    a:receive("WHISPER", D, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "void", h = h } }); sim:run(1)
    for k = mark + 1, #sim.sent do
      local x = sim.sent[k].msg.a
      ok(not (type(x) == "table" and (x.k == "void" or x.op == "void")), "a void went out")
    end
    local desync = 0
    for _, cl in ipairs({ a, b, c, d2, w }) do cl:on("desync", function() desync = desync + 1 end) end
    sim:run(8)
    eq({ a.session.state.phase, a.session.state.turn, a.session.fair.d, a.session.fair.stage }, { "bid", 2, 1, "dealt" })
    eq({ d2.session.fair.h, d2.session.fair.stage, known(d2) }, { a.session.fair.h, "dealt", 5 })
    eq(atA, { "ok" }); eq(desync, 0); eq(a.session.fairVoids, nil)
  end)

  it("a player stands mid-deal: the match ends, his team loses, the result names the leaver", function()
    local sim, tid = table4(); local ra, rw, seen = results(a), results(w), verdicts(a)
    bid("S P P P"); autoPlay(2); c:stand(); sim:run(2)
    eq(#ra, 1); local r = ra[1]; eq({ r.game, r.winners, r.losers, r.left }, { "belot", { 2, 4 }, { 1, 3 }, 3 })
    eq(r.names, { A, B, C, D }); eq(r.seats[3], false); eq(#rw, 1); eq(rw[1].winners, { 2, 4 })
    eq({ a.session.state.phase, a.session.state.winner, a.session.status }, { "match", 2, "aborted" })
    eq({ ns.Session.startable(a) }, { nil, "short" }); eq(a.session.fair, nil); eq(seen, {})
    c:sit(tid, 3); sim:run(3)
    eq({ a.session.status, a.session.state.phase, a.session.state.score, a.session.fair.stage }, { "live", "bid", { 0, 0 }, "dealt" })
  end)

  it("a timeout whose automatic move is lost is played again once the player is back", function()
    local sim = table4(); ok(a:act{ k = "bid", b = "P" }); sim:run(1)
    sim:offline(B); sim:run(60)                                                                  -- B's clock ran out at 45 s; its pass reached nobody
    eq({ a.session.state.turn, #a.session.state.bids }, { 2, 1 })
    sim:online(B); sim:run(6)
    eq({ a.session.state.turn, #a.session.state.bids, a.session.state.bids[2] }, { 3, 2, { s = 2, b = "P" } })
    local acts = 0
    for _, m in ipairs(sentOf("ACT")) do
      if m.from == B and m.msg.a.k == "bid" then acts = acts + 1 end
    end
    ok(acts >= 2 and acts <= 5, "B sent its pass " .. acts .. " times")                          -- every few seconds, not every tick
    eq(#(b.session.sent or {}), 0)                                                               -- and remembers nothing it still waits for
  end)

  it("a timeout that passes while my cards are missing is played once they come", function()
    local sim = table4()
    local restoreB, restoreA = drop(b, "PRV"), drop(a, "PRV")                                     -- the three cards after the auction reach neither
    bid("S P P P"); eq({ ns.Deal.missing(a.session), ns.Deal.missing(b.session), a.session.state.turn }, { true, true, 1 })
    sim:run(47); eq({ a.session.state.turn, #a.session.state.trick, #a.session.state.ann }, { 1, 0, 0 })   -- the host's own seat: no move to make yet
    restoreA(); sim:run(11)
    eq(ns.Deal.missing(a.session), false)
    for _ = 1, 3 do
      if a.session.state.turn == 1 then sim:run(46) end                                          -- an announce first, then the card
    end
    eq({ a.session.state.turn, #a.session.state.trick }, { 2, 1 })
    sim:run(47); eq({ a.session.state.turn, #a.session.state.trick }, { 2, 1 })                  -- a member's seat: the same
    local prq = #sentOf("PRQ")
    restoreB(); sim:run(11)
    ok(#sentOf("PRQ") > prq, "B did not ask for its cards again"); eq(ns.Deal.missing(b.session), false)
    for _ = 1, 3 do
      if a.session.state.turn == 2 then sim:run(46) end
    end
    eq({ a.session.state.turn, #a.session.state.trick }, { 3, 2 })
  end)

  it("a player offline for three minutes is stood up and his team loses", function()
    local sim = table4(); local ra = results(a)
    sim:offline(B); ok(a:act{ k = "bid", b = "P" }); sim:run(170)
    eq({ a.session.state.phase, a.session.state.turn, #a.session.state.bids, #ra }, { "bid", 2, 1, 0 })    -- nobody passed for him
    sim:run(30); eq(#ra, 1); eq({ ra[1].winners, ra[1].losers, ra[1].left, ra[1].names[2] }, { { 1, 3 }, { 2, 4 }, 2, B })
  end)

  it("the dealer reloads mid-trick: its saved round brings the deck back, the same hand goes on and ends проверена", function()
    local sim = table4(); local atA, atC, atW = verdicts(a), verdicts(c), verdicts(w); local h1 = a.session.fair.h
    bid("S P P P"); autoPlay(6)                                                                  -- two cards into the second trick
    local kept = sim.envs[D].db.fairKeep
    eq({ kept.tid, kept.h, kept.seat, kept.me, #kept.deck }, { tid, h1, 4, D, 32 })
    local mark = #sim.sent
    local d2 = sim:relog(D); local atD = verdicts(d2); sim:run(3)
    eq({ a.session.fair.h, a.session.fair.stage, d2.session.fair.h, d2.session.fair.lost }, { h1, "dealt", h1, nil })
    eq(d2.session.fair.deck, kept.deck); eq(ns.Deal.missing(d2.session), false); eq(atA, {})
    autoPlay(100); eq(a.session.state.turn, nil)
    for k = mark + 1, #sim.sent do                                                               -- what was saved stays on the dealer's client
      local m = sim.sent[k]
      local x = type(m.msg.a) == "table" and m.msg.a or {}
      ok(x.k ~= "void" and x.op ~= "void", "a void went out")
      if m.from == D then eq(hexes(m.msg), {}); ok(#faces(m.msg) < 32, "the deck went out") end
    end
    sim:run(6)
    eq(atA, { "ok" }); eq(atC, { "ok" }); eq(atW, { "ok" }); eq(atD, { "unseen" })               -- the dealer itself did not watch it whole
    eq({ a.session.state.round, a.session.fairVoids }, { 2, nil }); ok(a.session.state.score[1] + a.session.state.score[2] > 0)
    eq(sim.envs[D].db.fairKeep, nil)                                                             -- gone with the reveal
  end)

  it("a saved round is kept per table, hand, seat and player, and only while that hand runs", function()
    local sim = table4(); local h1 = a.session.fair.h
    local db = sim.envs[D].db
    eq({ db.fairKeep.h, db.fairKeep.seed, db.fairKeep.seeds }, { h1, SEED, { SEED, SEED, SEED, SEED } })
    eq(sim.envs[A].db.fairKeep, nil); eq(sim.envs[B].db.fairKeep, nil)                           -- only the dealer keeps one
    bid("P P P P"); sim:run(1); eq(db.fairKeep, nil)                                             -- passed out and revealed
    sim:run(8); local h2 = a.session.fair.h; eq({ a.session.fair.d, sim.envs[A].db.fairKeep.h }, { 1, h2 })
    -- a record of another hand, another player or a changed seed is not taken: the deck is lost, the hand is void
    sim:run(1); bid("S P P P")
    local function back(spoil)
      local rec = ns.Util.copy(sim.envs[A].db.fairKeep)
      spoil(rec)
      local trial = { fair = { h = h2, d = 1, p = { 1, 2, 3, 4 }, stage = "dealt", commits = ns.Util.copy(a.session.fair.commits) },
        tid = tid, mySeat = 1, client = { env = { me = A, db = { fairKeep = rec } } } }
      return ns.DealKeep.restore(trial), trial.fair.deck, trial.client.env.db.fairKeep ~= nil
    end
    eq({ back(function() end) }, { true, a.session.fair.deck, true })
    for _, spoil in ipairs{ function(r) r.h = r.h + 1 end, function(r) r.me = B end, function(r) r.tid = "x" end,
      function(r) r.seat = 2 end, function(r) r.seeds[2] = ("00"):rep(16) end, function(r) r.seed = ("00"):rep(16) end } do
      eq({ back(spoil) }, { false, nil, false })
    end
  end)

  it("a void asked for after the eighth trick is refused: the deal is scored", function()
    local sim, tid = table4(); local seen = verdicts(a); local h = a.session.fair.h
    bid("S P P P"); autoPlay(100); eq({ a.session.state.turn, a.session.state.phase }, { nil, "score" })
    local mark = #sim.sent
    a:receive("WHISPER", D, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "void", h = h } }); sim:run(0)
    eq(a.session.state.phase, "score")
    sim:run(6)
    for k = mark + 1, #sim.sent do
      local x = sim.sent[k].msg.a
      ok(not (type(x) == "table" and x.k == "void"), "a void went out")
    end
    eq(seen, { "ok" }); eq(a.session.fairVoids, nil); ok(a.session.state.score[1] + a.session.state.score[2] > 0)
  end)

  it("a dealer without its deck asks for the void again until it comes", function()
    local sim = table4(); local seen = verdicts(a)
    local restore = drop(a, "ACT", asks("void"))
    local d2 = sim:crash(D); sim:run(1); restore()
    eq({ d2.session.fair.voidAsked, d2.session.fair.deck }, { true, nil }); eq(seen, {})
    bid("S P P P"); eq({ a.session.state.phase, seen }, { "play", {} })                          -- the first request was lost
    sim:run(10); eq(seen, { "void" }); eq(a.session.fairVoids, { [D] = 1 })
    local n = 0
    for _, m in ipairs(sentOf("ACT")) do
      if m.from == D and type(m.msg.a) == "table" and m.msg.a.op == "void" then n = n + 1 end
    end
    eq(n, 2)                                                                                     -- asked twice, not on every tick
  end)

  it("the dealer comes back without its saved round: void, the next seat deals, no point moved", function()
    local sim = table4(); local seen = verdicts(a); local h1 = a.session.fair.h
    bid("S P P P"); autoPlay(1); local d2 = sim:crash(D); sim:run(8)
    eq(seen, { "void" }); ok(a.session.fair.h ~= h1); eq({ a.session.fair.d, a.session.fair.stage }, { 1, "dealt" })
    ok(a.session.fair.deck ~= nil); eq(d2.session.fair.deck, nil)                                  -- PB6b: the voiding dealer does not deal again
    eq({ a.session.state.phase, a.session.state.round, a.session.state.first, a.session.state.turn }, { "bid", 1, 2, 2 }); eq(a.session.state.score, { 0, 0 })
  end)

  -- Carried from C Task 3: the dealer gives up a hand that ended before its void came.
  it("the dealer relogs, its void request is lost and the deal is passed out: void, not нередовна; the next seat deals", function()
    local sim = table4(); local atA, atC, atW = verdicts(a), verdicts(c), verdicts(w); local h1 = a.session.fair.h
    local restore = drop(a, "ACT", asks("void"))
    local d2 = sim:crash(D); sim:run(1); restore()
    eq({ d2.session.fair.h, d2.session.fair.voidAsked, d2.session.fair.deck }, { h1, true, nil }); eq(atA, {})
    bid("P P P P")                                                                               -- the dealer passes last
    eq(atA, { "void" }); eq(atC, { "void" }); eq(atW, { "void" }); eq(a.session.fairLast.dealer, D); eq(a.session.fairVoids, { [D] = 1 })
    sim:run(25)
    eq(atA, { "void" }); eq(atC, { "void" }); eq({ a.session.fair.d, a.session.fair.stage }, { 1, "dealt" }); ok(a.session.fair.deck ~= nil)
    eq({ a.session.state.phase, a.session.state.round, a.session.state.first, a.session.state.turn }, { "bid", 2, 2, 2 }); eq(a.session.state.score, { 0, 0 })
    for _, cl in ipairs{ b, c, d2, w } do eq(cl.session.fair.h, a.session.fair.h) end
  end)

  it("a dealer that played in the hand cannot give it up afterwards: a void instead of the reveal is нередовна", function()
    local sim, tid = table4(); local atA, atC = verdicts(a), verdicts(c); local h = a.session.fair.h
    drop(a, "ACT", asks("reveal"))
    bid("S P P P"); autoPlay(100); eq(a.session.state.turn, nil); sim:run(3)
    eq({ a.session.state.phase, a.session.fair.h, a.session.fair.stage }, { "deal", h, "dealt" }); local score = ns.Util.copy(a.session.state.score)
    ok(score[1] + score[2] > 0); eq(d.session.fair.revealed, true)                                -- scored; the reveal was lost
    local mark = #sim.sent
    ns.Deal.submit(d.session, { k = "fair", op = "void", h = h }); sim:run(1)
    for k = mark + 1, #sim.sent do
      local x = sim.sent[k].msg.a
      ok(not (type(x) == "table" and x.k == "void"), "a void went out")
    end
    eq(atA, {}); sim:run(25)
    eq(atA, { "bad" }); eq(atC, { "bad" }); eq(a.session.fairLast.why, "noreveal"); eq(a.session.fairVoids, nil)
    eq(a.session.state.score, score); eq(a.session.fair.stage, "dealt"); ok(a.session.fair.h ~= h)
  end)

  it("a member that came by snapshot still names the leaver", function()
    local sim, tid = table4(); local x = sim:add("Нов Гледач"); sim:run(1)
    bid("S P P P"); autoPlay(2); x:watch(tid); sim:run(3)
    eq(x.session.seatedBefore, { A, B, C, D }); local rx = results(x)
    c:stand(); sim:run(2)
    eq(#rx, 1); eq({ rx[1].left, rx[1].names }, { 3, { A, B, C, D } })
  end)

  it("a player who relogs after an announce still scores the deal", function()
    rigged(); local sim = table4(); dealAll(DECK_A); bid("S P P P")
    playFaces("AH 9H 8H"); ok(d:act{ k = "ann", a = { { t = "s4", i = 4 } } }); sim:run(1)
    playFaces("TS AC 8C 7C 9C KC 9S"); autoPlay(6)
    local c2 = sim:relog(C); local desync = 0
    c2:on("desync", function() desync = desync + 1 end); sim:run(3)
    eq(c2.session.state.deck[4], "AC")
    autoPlay(100); eq(a.session.state.turn, nil); sim:run(4)
    eq(desync, 0); eq(a.session.state.phase, "deal")
    eq(c2.session.state.score, a.session.state.score)
    eq(a.session.state.res.ann[1], { s = 4, t = "s4", i = 4, v = 50, on = true })
    ns.Ext.fair = REAL
  end)

  it("a forged announce scores nothing and the deal is нередовна by the player's name on every client", function()
    local sim, tid = table4()
    bid("S P P P")
    while a.session.state.turn == 1 do autoPlay(1) end                                          -- seat 1 announces what it has and leads
    local i = a.session.state.hands[2][1]                                                       -- a four of jacks, a run of eight and a four of nines on one card
    a:receive("WHISPER", B, { v = 1, t = "ACT", tid = tid, a = { k = "ann", a = { { t = "cJ", i = i }, { t = "s8", i = i }, { t = "c9", i = i } } } })
    sim:run(2); eq(#a.session.state.ann >= 3, true)                                             -- the host cannot check it yet
    autoPlay(100); eq(a.session.state.turn, nil); sim:run(6)
    for _, cl in ipairs{ a, c, d, w } do
      local st, bad, real = cl.session.state, 0, 0
      for _, x in ipairs(st.res.ann) do
        if x.bad then bad = bad + 1; eq({ x.s, x.v, x.on }, { 2, 0, false }) elseif x.on then real = real + x.v end
      end
      eq(bad, 3); eq(st.res.raw[1] + st.res.raw[2], 162 + real + (st.res.valat and 90 or 0)); eq(st.score, a.session.state.score)
      local last = cl.session.fairLast
      eq({ last.verdict, last.why, last.who }, { "bad", "announce", B })
      eq({ ns.Deal.status(cl.session) }, { "fair.announce", B }); eq(ns.Deal.alarm(cl.session), true)
    end
    eq(b.session.fairLast.verdict, "bad")                                                       -- B's own client: somebody played in its name
  end)

  it("вътре and контра score the same on every client", function()
    rigged(); local sim = table4()
    dealAll(DECK1); bid("P C P P P"); playFirst(32); sim:run(3)                       -- seat 2 called clubs; seat 1 holds every club
    for _, cl in ipairs{ a, b, c, d, w } do
      local st = cl.session.state
      eq({ st.res.contract, st.res.raw, st.res.pts, st.res.valat }, { { seat = 2, b = "C", x = 1 }, { 252, 0 }, { 25, 0 }, true }); eq(st.score, { 25, 0 })
    end
    dealAll(DECK1); bid("D X P P P"); playFirst(32); sim:run(3)                       -- seat 2 calls its diamonds, seat 3 doubles
    for _, cl in ipairs{ a, b, c, d, w } do
      local st = cl.session.state
      eq({ st.res.contract, st.res.raw, st.res.pts }, { { seat = 2, b = "D", x = 2 }, { 0, 252 }, { 0, 50 } }); eq(st.score, { 25, 50 }); eq(E.over(st), false)
    end
    ns.Ext.fair = REAL
  end)
end)
