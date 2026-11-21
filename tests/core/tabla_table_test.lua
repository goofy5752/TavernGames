local Sim = require("sim")
local ns = Sim.ns
local E = ns.Engines.tabla

local A, B, W = "Иван Петров", "Мария Стоянова", "Гледач Гледачев"
local SEED = ("ff"):rep(16)
local COMMIT = "352302489bc2fcf025cf00cda8308033f97ac87712ce90b4d7cd72c58e4c3af9"
local FIRST = { { 24, 20 }, { 24, 20 }, { 13, 9 }, { 13, 9 } } -- a legal first move of seat 1 with 4:4
local sim, a, b, w

-- A table of Табла hosted by a, watched by w; B is not seated yet.
local function table2(turn)
  sim = Sim.new()
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  w = sim:add(W, { cls = "DRUID" })
  sim:run(1)
  local tid = a:openTable{ game = "tabla", access = "guild", turn = turn or 45 }; sim:run(3)
  w:watch(tid); sim:run(1)
  return sim, tid
end

local function seat(tid) b:sit(tid or a.session.tid, 2); sim:run(1) end

-- The `a` of every EV sent to `name` after index `from` of sim.sent, in order.
local function evs(name, from)
  local out = {}
  for i = from + 1, #sim.sent do
    local m = sim.sent[i]
    if m.target == name and m.msg.t == "EV" then out[#out + 1] = m.msg.a end
  end
  return out
end

-- The "fair" payloads that client emits from now on.
local function fairs(cl)
  local list = {}
  cl:on("fair", function(e) list[#list + 1] = e end)
  return list
end

describe("tabla at the table", function()
  it("two players throw together: three events a throw, the dice on no wire, the same board for everyone", function()
    local sim, tid = table2(); local mark = #sim.sent; seat(); eq(tid, "Иван Петров#1700000001")
    eq({ ns.Fair.dice({ SEED, SEED }, tid .. "/3") }, { 6, 1 }); eq({ ns.Fair.dice({ SEED, SEED }, tid .. "/6") }, { 4, 4 })
    local st = a.session.state                                                        -- sit, start, the opening throw (seat 1 starts), its own throw
    eq({ st.phase, st.turn, st.dice, st.left, a.session.seq }, { "move", 1, { 4, 4 }, { 4, 4, 4, 4 }, 8 })
    local ev = evs(B, mark); eq(#ev, 7); eq(ev[1], { k = "start" })
    eq(ev[2], { k = "throw", op = "open", h = 3, c = COMMIT }); eq(ev[3], { k = "throw", op = "commit", h = 3, seat = 2, c = COMMIT })
    eq(ev[4], { k = "throw", op = "seeds", h = 3, s = { SEED, SEED } }); eq({ ev[5].op, ev[5].h, ev[7].op, ev[7].h }, { "open", 6, "seeds", 6 })
    eq(b.session.state, st); eq(w.session.state, st)
    for _, cl in ipairs{ a, b, w } do
      eq(cl.session.diceLast, { h = 6, verdict = "ok", by = A }); eq(cl.session.diceSeen, { ok = 2, alone = 0, bad = 0 }); eq(cl.session.throw.done, true)
      eq({ ns.Dice.status(cl.session) }, { "dice.ok", "good" })
    end
    eq(sim:count(function(m) return m.msg.t == "EV" and m.msg.a.k == "dice" end), 0)
    eq(sim:count(function(m) return m.from == B and m.msg.t == "ACT" end), 4)             -- a commit and a seed per throw
    eq(sim:count(function(m) return m.channel == "GUILD" and (m.msg.t == "EV" or m.msg.t == "ACT") end), 0)
  end)

  it("a turn is one move event, then the next throw", function()
    local sim, tid = table2(); seat(); local seen = fairs(w)
    eq({ a:act{ k = "move", steps = { { 24, 20 } } } }, { nil, "move" }); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)
    local st = b.session.state; eq({ st.turn, st.phase, st.dice, b.session.seq }, { 2, "move", { 4, 3 }, 12 }); eq(b.session.diceLast.h, 10)
    eq({ #seen, seen[1].h, seen[1].verdict, seen[1].game }, { 1, 10, "ok", "tabla" }); eq(w.session.state, a.session.state)
    ok(b:act(E.auto(b.session.state, 2))); sim:run(1); eq({ a.session.state.turn, a.session.state.dice, a.session.seq }, { 1, { 1, 4 }, 16 })
  end)

  it("the table hook takes only what fits the throw", function()
    local sim, tid = table2(); seat(); local s, T = b.session, ns.Ext.dice.table
    eq(T(s, { k = "throw", op = "open", h = s.seq + 1, c = COMMIT }), nil)               -- the engine wants no dice now
    eq(T(s, { k = "throw", op = "seeds", h = 6, s = { SEED, SEED } }), nil)             -- that throw is closed
    eq(T(s, { k = "move", steps = {} }), nil); eq(ns.Ext.dice.act(a.session, 2, { k = "move", steps = {} }), { k = "move", steps = {} })
    eq(ns.Ext.dice.act(a.session, 2, { k = "throw", op = "seed", h = 6, s = SEED }), nil); eq(a.session.seq, 8)
    eq(ns.Ext.dice.snap(a.session), nil); eq(ns.Dice.status({ engine = function() return ns.Engines.ttt end }), nil)   -- not a dice game
  end)
end)
