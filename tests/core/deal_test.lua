local Sim = require("sim")
local H = require("hicard_engine")
local ns = Sim.ns

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"
local SEED = ("ff"):rep(16)
local sim, tid, a, b, c, d

-- a hosts hicard, b on seat 2 (and c on seat 3 when `three`), d online but not
-- at the table; not started.
local function setup(three)
  sim = Sim.new()
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  c = three and sim:add(C, { cls = "ROGUE" }) or nil
  d = sim:add(D, { cls = "DRUID" })
  sim:run(1)
  tid = a:openTable{ game = "hicard", access = "guild", turn = 45 }; sim:run(3)
  b:sit(tid, 2); sim:run(1)
  if three then c:sit(tid, 3); sim:run(1) end
  return sim, tid
end
local function table2() return setup(false) end
local function table3() return setup(true) end

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

-- Every card face anywhere in v (keys and values).
local function faces(v, out)
  out = out or {}
  if type(v) == "string" then
    if v:match("^[9TJQKA][CDHS]$") then out[#out + 1] = v end
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

local function sentOf(t)
  local out = {}
  for _, m in ipairs(sim.sent) do
    if m.msg.t == t then out[#out + 1] = m end
  end
  return out
end

local function isOpenTo(m, target)
  return m.msg.t == "EV" and m.from == A and m.target == target and type(m.msg.a) == "table" and m.msg.a.op == "open"
end

local function opensTo(target)
  local n = 0
  for _, m in ipairs(sim.sent) do
    if isOpenTo(m, target) then n = n + 1 end
  end
  return n
end

local function act(x) return { v = 1, t = "ACT", tid = tid, a = x } end

describe("deal", function()
  it("a hand is dealt from everyone's seeds and each client knows only its own cards", function()
    local sim, tid = table2(); d:watch(tid); sim:run(1); start()
    local r = a.session.fair; eq({ r.d, r.p, r.stage, r.dealer }, { 2, { 1, 2 }, "dealt", B }); eq(a.session.fairN, 1)
    local deck = b.session.fair.deck; eq(deck, ns.Fair.deck(H.DECK, { SEED, SEED }, tid .. "/" .. r.h)); eq(a.session.fair.deck, nil)
    eq(a.session.state.deck, { [1] = deck[1], [3] = deck[3], [5] = deck[5] }); eq(d.session.state.deck, { [5] = deck[5] })
    eq(b.session.state.deck, { [2] = deck[2], [4] = deck[4], [5] = deck[5] })      -- the dealer's table state is still only its own view
    eq(a.session.state.turn, 1); eq(a.session.state.phase, "play")
  end)

  it("commits come before any seed, and a seed goes only to the dealer", function()
    table2(); start()
    local startAt, kinds, commits, lastCommit = nil, {}, {}, nil
    for i, m in ipairs(sim.sent) do
      if m.msg.t == "EV" and m.from == A then
        local x = m.msg.a
        if m.target == B and m.msg.seat == 0 and x.k == "start" then startAt = i end
        if x.op == "commit" then lastCommit = i end
        if startAt and i > startAt and m.target == B then
          kinds[#kinds + 1] = x.op or x.k
          if x.op == "commit" then commits[#commits + 1] = { x.seat, x.c } end
        end
      end
    end
    ok(startAt); eq(kinds, { "open", "commit", "commit", "deal" })
    eq(commits, { { 1, ns.Fair.commit(SEED) }, { 2, ns.Fair.commit(SEED) } })
    local seeds = sentOf("SED"); eq(#seeds, 1)
    eq({ seeds[1].from, seeds[1].channel, seeds[1].target, seeds[1].msg.s }, { A, "WHISPER", B, SEED })
    local at
    for i, m in ipairs(sim.sent) do
      if m == seeds[1] then at = i end
    end
    ok(at > lastCommit)
    for _, m in ipairs(sim.sent) do
      if m.channel == "GUILD" then
        ok(m.msg.t ~= "SED" and m.msg.t ~= "PRV" and m.msg.t ~= "PRQ")
        eq(faces(m.msg), {}); eq(hexes(m.msg), {})
      end
    end
  end)

  it("no message to the opponent or a watcher carries a face it may not see", function()
    table2(); start(); d:watch(tid)
    local deck = b.session.fair.deck
    local held, public, seen = { {}, {} }, { [deck[5]] = true }, 0
    local SEAT = { [A] = 1, [B] = 2 }
    local function check()
      local full = ns.Fair.full(b.session.state, deck)
      for q = 1, 2 do
        for _, i in ipairs(full.hands[q]) do held[q][i] = true end
      end
      for _, t in ipairs(b.session.state.trick) do public[deck[t[2]]] = true end
      for _, i in ipairs(b.session.state.last) do public[deck[i]] = true end
      for k = seen + 1, #sim.sent do
        local m = sim.sent[k]
        if m.channel == "GUILD" then
          eq(faces(m.msg), {})
        else
          local seat = SEAT[m.target]
          for _, f in ipairs(faces(m.msg)) do
            local fine = public[f] == true
            for i in pairs(seat and held[seat] or {}) do
              if deck[i] == f then fine = true end
            end
            ok(fine, f .. " reached " .. m.target .. " in " .. m.msg.t)
          end
        end
      end
      seen = #sim.sent
    end
    check()
    for _ = 1, 5 do auto(1); check() end
    ok(not a.session:gameOver()); eq(a.session.state.phase, "play")
    local prv = sentOf("PRV"); ok(#prv >= 2)
    for _, m in ipairs(prv) do eq({ m.from, m.channel, m.target }, { B, "WHISPER", A }) end
  end)

  it("a drawn card reaches only the player who drew it", function()
    table2(); start(); auto(2)                                   -- trick 1 done, both drew
    local deck, st = b.session.fair.deck, ns.Fair.full(b.session.state, b.session.fair.deck)
    for _, i in ipairs(st.hands[1]) do eq(a.session.state.deck[i], deck[i]); eq(b.session.state.deck[i], nil) end
    for _, i in ipairs(st.hands[2]) do eq(b.session.state.deck[i], deck[i]); eq(a.session.state.deck[i], nil) end
    eq(#st.hands[1], 2); eq(ns.Deal.missing(a.session), false)
  end)

  it("three players: three commits, two seeds to the dealer on seat 2", function()
    table3(); start()
    local r = a.session.fair; eq(r.p, { 1, 2, 3 }); eq(r.d, 2); eq(r.stage, "dealt")
    local n = 0
    for _, m in ipairs(sentOf("EV")) do
      if m.target == B and m.msg.a.op == "commit" then n = n + 1 end
    end
    eq(n, 3)
    local seeds, from = sentOf("SED"), {}
    eq(#seeds, 2)
    for _, m in ipairs(seeds) do from[m.from] = m.target end
    eq(from, { [A] = B, [C] = B })
    local deck = b.session.fair.deck
    eq(c.session.state.deck, { [3] = deck[3], [6] = deck[6], [7] = deck[7] })
  end)

  it("only the dealer may deal or show, and a second commit is dropped", function()
    table3(); start()
    local r = a.session.fair; eq(r.stage, "dealt"); eq(r.dealer, B)
    local q = a.session.seq
    a:receive("WHISPER", C, act{ k = "fair", op = "show", h = r.h, cards = { [1] = "9C" } })
    a:receive("WHISPER", C, act{ k = "fair", op = "deal", h = r.h, deck = {} })
    a:receive("WHISPER", B, act{ k = "fair", op = "commit", h = r.h, c = ("0"):rep(64) })
    a:receive("WHISPER", B, act{ k = "fair", op = "show", h = r.h + 1, cards = {} })
    sim:run(1); eq(a.session.seq, q)
  end)

  it("a PRV from anyone but the dealer is ignored", function()
    table2(); start()
    local r = a.session.fair
    a:receive("WHISPER", D, { v = 1, t = "PRV", tid = tid, h = r.h, cards = { [2] = "9C" } })
    eq(a.session.state.deck[2], nil); eq(a.session.fair.priv[2], nil)
  end)

  it("a watcher who comes mid-hand adopts the round from the snapshot", function()
    table2(); start(); local r = a.session.fair; d:watch(tid); sim:run(1)
    eq(d.session.fair.h, r.h); eq(d.session.fair.base, nil); eq(d.session.fair.stage, "dealt"); eq(d.session.fairN, 1)
    -- The round in the snapshot is public: no faces, no seeds.
    local snp
    for _, m in ipairs(sentOf("SNP")) do
      if m.target == D then snp = m.msg end
    end
    local keys = {}
    for k in pairs(snp.fr) do keys[#keys + 1] = k end
    table.sort(keys); eq(keys, { "c", "d", "h", "n", "p", "st" })
    eq(faces(snp.fr), {})
    for _, x in ipairs(hexes(snp.fr)) do eq(#x, 64) end
  end)

  it("a seed that overtakes the last commit event is kept, not lost", function()
    table3()
    local queued = {}
    b.receive = function(self, channel, sender, msg)
      if msg.t == "EV" and type(msg.a) == "table" and msg.a.op == "commit" and msg.a.seat == 3 then
        queued[#queued + 1] = { channel, sender, msg }
        return
      end
      return ns.Client.receive(self, channel, sender, msg)
    end
    a:startGame(); sim:run(1)
    local h = a.session.fair.h
    eq(#queued, 1); eq(b.session.fair.h, h); eq(b.session.fair.stage, "commit")
    local fromC = false
    for _, m in ipairs(sentOf("SED")) do
      if m.from == C and m.target == B then fromC = true end
    end
    ok(fromC); eq(b.session.fairEarly[h][C], SEED); eq(b.session.fair.deck, nil); eq(a.session.fair.stage, "seed")
    b.receive = nil
    b:receive(queued[1][1], queued[1][2], queued[1][3]); sim:run(1)
    eq(b.session.fair.stage, "dealt"); eq(a.session.fair.stage, "dealt"); eq(b.session.fairEarly[h], nil)
    eq(a.session.fair.h, h); eq(opensTo(B), 1)
    -- An ordinary two-player run deals as before.
    table2(); start(); eq(a.session.fair.stage, "dealt"); eq(b.session.fair.stage, "dealt"); eq(ns.Deal.missing(a.session), false)
  end)

  it("an open whose participants are not the occupied seats in ascending order is refused", function()
    table2(); start()
    local q, h = a.session.seq, a.session.fair.h
    local open = { k = "fair", op = "open", h = q + 1, d = 1, p = { 1, 1 } }
    a.session:play(0, open); sim:run(1); eq(a.session.seq, q); eq(a.session.fair.h, h)
    eq(b.session:apply(0, open), nil); eq(b.session:apply(0, { k = "fair", op = "open", h = q + 1, d = 2, p = { 2, 1 } }), nil)
    eq(b.session.fair.h, h)
    ok(b.session:apply(0, { k = "fair", op = "open", h = q + 1, d = 1, p = { 1, 2 } })); eq(b.session.fair.h, q + 1)
  end)

  it("repeated need offers during the shuffle open no second round", function()
    table2(); sim:offline(B); start()
    local h = a.session.fair.h; eq(a.session.fair.stage, "commit"); ok(a.session.fairTimer)
    for _ = 1, 3 do ns.Ext.fair.need(a.session, { k = "deal", need = "deck" }) end
    sim:run(5); eq(a.session.fair.h, h); eq(opensTo(B), 1)
  end)
end)
