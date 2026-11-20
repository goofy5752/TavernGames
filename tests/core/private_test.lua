local Sim = require("sim")
local H = require("hicard_engine")
local ns = Sim.ns

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"
local a, b, d

-- The production extension "fair" (nil until it exists); every test puts it back.
local REAL = ns.Ext.fair

-- A test body that restores ns.Ext.fair whether it passes or fails.
local function restoring(fn)
  return function()
    local fine, err = pcall(fn)
    ns.Ext.fair = REAL
    if not fine then error(err, 0) end
  end
end

-- a hosts hicard (b on seat 2, d online but not at the table) with `ext` as
-- the extension "fair" (nil = none, so nothing deals by itself); started.
-- `turn` defaults to 45.
local function table2(ext, turn)
  ns.Ext.fair = ext
  local sim = Sim.new()
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  d = sim:add(D, { cls = "DRUID" })
  sim:run(1)
  local tid = a:openTable{ game = "hicard", access = "guild", turn = turn or 45 }; sim:run(3)
  b:sit(tid, 2); sim:run(1)
  ok(a:startGame()); sim:run(1)
  return sim, tid
end

-- The last SNP the host whispered to `name`.
local function lastSnapshot(sim, name)
  for i = #sim.sent, 1, -1 do
    local s = sim.sent[i]
    if s.from == A and s.target == name and s.msg.t == "SNP" then return s.msg end
  end
end

describe("private hands", function()
  it("the test engine keeps the contract: view plus deck is the full state", restoring(function()
    local s = H.new{ first = 1, seats = { true, true } }; ok(H.apply(s, 0, { k = "deal", deck = H.DECK }))
    eq(s.hands, { { 1, 3 }, { 2, 4 } }); eq(s.up, 5); eq(s.turn, 1); eq(s.stock, { 6, 7, 8, 9, 10, 11, 12 })
    eq(H.view(s, 1).deck, { [1] = "9C", [3] = "JC", [5] = "KC" }); eq(H.view(s, 0).deck, { [5] = "KC" })
    for q = 0, 2 do local v = H.view(s, q); v.deck, v.full = ns.Util.copy(s.deck), true; eq(v, s) end
    local v = H.view(s, 2); ok(H.apply(v, 1, { k = "play", i = 1, c = "9C" })); eq(v.deck[1], "9C")
    eq({ H.apply(s, 0, { k = "deal", need = "deck" }) }, { nil, "need" }); eq(H.auto(H.view(s, 2), 1), nil)
    ok(H.apply(s, 0, { k = "void" })); eq(s.phase, "deal"); eq(s.hand, 0); eq({ H.system(s) }, { { k = "deal", need = "deck" }, 0 })
  end))

  it("a new game is a view and the need action is offered to the extensions, never played", restoring(function()
    local got = {}
    local sim = table2{ need = function(s, x) got[#got + 1] = x end }
    eq(a.session.state.full, false); eq(b.session.state.full, false)
    local q = a.session.seq; sim:run(5); eq(got, { { k = "deal", need = "deck" } }); eq(a.session.seq, q); eq(a.session.state.phase, "deal")
  end))

  it("an unserved or refused need is offered once, not again and again", restoring(function()
    local got = 0
    -- The hook hands the action back as it is: the engine refuses it ("need").
    local sim = table2{ need = function(s, x) got = got + 1; s:play(0, x) end }
    local q = a.session.seq; sim:run(60); eq(got, 1); eq(a.session.seq, q); eq(a.session.systemTimer, nil)
    -- No extension at all: nothing is offered, nothing fires.
    local sim2 = table2(); local q2 = a.session.seq; sim2:run(60); eq(a.session.seq, q2); eq(a.session.state.phase, "deal")
  end))

  it("a seat-0 event claimed by the table hook does not reach the engine", restoring(function()
    local sim = table2{ table = function(s, x) if x.k == "fair" then s.claimed = (s.claimed or 0) + 1; return true end end }
    local q = a.session.seq
    a.session:play(0, { k = "fair", op = "x" }); sim:run(1); eq(a.session.claimed, 1); eq(b.session.claimed, 1); eq(b.session.seq, q + 1)
    a.session:play(0, { k = "nope" }); sim:run(1); eq(a.session.seq, q + 1)
  end))

  it("a snapshot is cut to the recipient's view", restoring(function()
    local sim, tid = table2(); a.session:play(0, { k = "deal", deck = H.DECK }); sim:run(1)   -- test shortcut: everybody knows all
    local b2 = sim:relog(B); d:watch(tid); sim:run(2)
    eq(b2.session.state.deck, { [2] = "TC", [4] = "QC", [5] = "KC" }); eq(d.session.state.deck, { [5] = "KC" })
    local toB, toD = lastSnapshot(sim, B), lastSnapshot(sim, D)
    eq(toB.st.deck, { [2] = "TC", [4] = "QC", [5] = "KC" }); eq(toB.st.full, false)
    eq(toD.st.deck, { [5] = "KC" })
  end))

  it("the host's clock cannot play a hand it does not see; the player's own client does", restoring(function()
    local sim = table2(); a.session:play(0, { k = "deal", deck = { [5] = "KC" } }); sim:run(1)
    a.session.state.deck[1], a.session.state.deck[3] = "9C", "JC"; b.session.state.deck[2], b.session.state.deck[4] = "TC", "QC"
    ok(a:act{ k = "play", i = 1, c = "9C" }); sim:run(44); eq(#a.session.state.trick, 1)
    sim:run(2); eq(a.session.state.tricks, 1); eq(a.session.state.last, { 1, 2 })       -- b's client played {i=2, c="TC"} at its deadline
    -- b won and leads: its client plays QC (index 4) at its deadline; then the
    -- host's own turn timer plays a's JC (index 3).
    sim:run(46); eq(a.session.state.trick, { { 2, 4 } })
    sim:run(46); eq(a.session.state.last, { 4, 3 }); eq(a.session.state.tricks, 2)
  end))

  it("a member who becomes host keeps no stale auto-move timer", restoring(function()
    local sim = table2(nil, 90); a.session:play(0, { k = "deal", deck = { [5] = "KC" } }); sim:run(1)
    a.session.state.deck[1] = "9C"; b.session.state.deck[2], b.session.state.deck[4] = "TC", "QC"
    ok(a:act{ k = "play", i = 1, c = "9C" }); sim:run(1); ok(b.session.autoTimer)
    sim:offline(A); sim:run(76); eq(b.session.role, "host"); eq(b.session.seq, a.session.seq)
    -- b's own deadline (90 s after a's play) passes: the old member timer plays nothing.
    sim:run(14); eq(#b.session.state.trick, 1)
    -- b's turn timer as host, a fresh full turn from the claim, plays it.
    sim:run(76); eq(#b.session.state.trick, 0); eq(b.session.state.last, { 1, 2 })
  end))
end)
