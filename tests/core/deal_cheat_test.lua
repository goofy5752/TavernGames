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
    eq({ ns.Deal.status(a.session) }, { "fair.protest", C })
    eq(ns.Deal.alarm(a.session), true)
    eq({ ns.Deal.status(c.session) }, { "fair.last", "bad" })
    -- Asked twice, or for a hand that is not the last one: nothing more.
    local q = a.session.seq
    a:receive("WHISPER", C, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "protest", h = p[1].h, why = "dealt" } })
    a:receive("WHISPER", C, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "protest", h = 1, why = "dealt" } })
    a:receive("WHISPER", C, { v = 1, t = "ACT", tid = tid, a = { k = "fair", op = "protest", h = a.session.fair.h, why = "x" } })
    sim:run(1); eq(a.session.seq, q)
  end)
end)
