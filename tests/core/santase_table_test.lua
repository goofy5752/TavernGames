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
