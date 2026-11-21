local Sim = require("sim")
local ns = Sim.ns
local E = ns.Engines.belot

local A, B, C, D, W = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров", "Гледач Гледачев"
local SEED = ("ff"):rep(16)
local sim, tid, a, b, c, d, w

-- a hosts Белот, w watches, b, c and d sit at seats 2, 3, 4: the match starts
-- and the first deal is dealt. Every client yields SEED.
local function table4()
  sim = Sim.new()
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

  it("no message to another seat or a watcher carries a face it may not see, through a whole deal", function()
    table4()
    local deck = d.session.fair.deck
    local held, public = { {}, {}, {}, {} }, {}
    local seatOf = {}
    for q = 1, 4 do seatOf[a.session.seats[q]] = q end
    local mark, plays, steps = 0, 0, 0
    local function check()
      local st = d.session.state
      for q, hand in ipairs(ns.Fair.full(st, deck).hands) do
        for _, i in ipairs(hand) do held[q][deck[i]] = true end
      end
      for _, i in ipairs(st.trick) do public[deck[i]] = true end
      if st.last then for _, i in ipairs(st.last.cards) do public[deck[i]] = true end end
      for k = mark + 1, #sim.sent do
        local m = sim.sent[k]
        local fs, q = faces(m.msg), seatOf[m.target]
        if m.channel == "GUILD" then
          eq(fs, {}); ok(m.msg.t ~= "SED" and m.msg.t ~= "PRV" and m.msg.t ~= "PRQ", m.msg.t); eq(hexes(m.msg), {})
        elseif m.target == W then
          for _, f in ipairs(fs) do ok(public[f], "to the watcher: " .. f) end
        elseif q then
          for _, f in ipairs(fs) do ok(public[f] or held[q][f], "to seat " .. q .. ": " .. f) end
        end
        if m.target == B and m.msg.t == "EV" and type(m.msg.a) == "table" and m.msg.a.k == "play" then plays = plays + 1 end
      end
      mark = #sim.sent
    end
    check()
    for token in ("H P P P"):gmatch("%S+") do bid(token); check() end
    while a.session.state.phase == "play" do
      steps = steps + 1; ok(steps < 100, "the deal does not end")
      autoPlay(1); check()
    end
    eq(plays, 32)
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
    local sim = table4(); local seen = verdicts(a); local mark = #sim.sent
    sim:run(182); eq({ a.session.state.round, a.session.state.first }, { 2, 2 }); eq(a.session.state.res.contract, nil); eq(seen, { "ok" })
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
end)
