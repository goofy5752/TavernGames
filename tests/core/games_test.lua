local Sim = require("sim")
local Fake = require("fake_engine")
local ns = Sim.ns
local G = ns.Games

local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"

-- Test engine "optgame": the fake engine with one table option.
local E = {}
for k, v in pairs(Fake) do E[k] = v end
E.id = "optgame"
E.options = { { id = "goal", choices = { 2, 3 }, default = 2 } }
ns.Engines.optgame = E

local function setup()
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  local c = sim:add(C, { cls = "ROGUE" })
  sim:run(1)
  return sim, a, b, c
end

local function refusals(client)
  local list = {}
  client:on("refused", function(tid, why) list[#list + 1] = { tid, why } end)
  return list
end

describe("game registry", function()
  it("lists the six games in order with their player counts", function()
    local l = G.list(); eq(#l, 6); eq(l[1].id, "ttt"); eq(l[1].players, "2"); ok(l[1].engine == ns.Engines.ttt)
    eq(l[2].id, "deathroll"); eq(l[2].players, "2–5"); eq(l[6].id, "holdem"); eq(l[6].engine, nil); eq(G.engine(42), nil)
    -- engines exist but are not playable until their integration stage lands (santase: stage B)
    ok(ns.Engines.belot ~= nil); ok(ns.Engines.holdem ~= nil)
    eq(G.engine("belot"), nil); eq(G.engine("tabla"), nil); eq(G.engine("holdem"), nil)
    ok(G.list()[3].engine == ns.Engines.santase); eq(G.list()[4].engine, nil)
    ok(G.engine("ttt") ~= nil); ok(G.engine("deathroll") ~= nil); ok(G.engine("santase") == ns.Engines.santase)
    ok(G.engine("optgame") == ns.Engines.optgame)
  end)

  it("resolve fills defaults and rejects what the engine does not offer", function()
    eq(G.resolve("ttt", nil), {}); eq(G.resolve("optgame", nil), {goal=2}); eq(G.resolve("optgame", {goal=3}), {goal=3})
    eq(G.resolve("optgame", {goal=5}), nil); eq(G.resolve("optgame", {x=1}), nil); eq(G.resolve("optgame", "3"), nil)
    eq(G.resolve("nope", nil), nil); eq(G.resolve("ttt", {goal=2}), nil)
  end)

  it("options travel with the table", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="optgame", access="guild", turn=45, opt={goal=3}}; sim:run(3)
    eq(a.session.opt, {goal=3}); eq(b.lobby:get(tid).opt, {goal=3}); b:sit(tid, 2); sim:run(1); eq(b.session.opt, {goal=3})
    eq({c:openTable{game="optgame", access="guild", turn=45, opt={goal=9}}}, {nil, "opt"})
  end)

  it("a ttt TBL carries no o field", function()
    local sim, a = setup()
    local mark = #sim.sent
    a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    local n = 0
    for i, s in ipairs(sim.sent) do
      if i > mark and s.from == A and s.msg.t == "TBL" then
        n = n + 1; eq(s.msg.o, nil)
      end
    end
    ok(n > 0)
    eq(a.session.opt, {}); eq(a.lobby:get(a.session.tid).opt, nil)
  end)

  it("Lobby.valid: seat count and options", function()
    local valid = ns.Lobby.valid
    local function base(fields)
      local m = { tid = "X#1", g = "ttt", h = A, e = 1, ac = "guild", tn = 45, st = "open", s = { A, false }, w = 0 }
      for k, v in pairs(fields or {}) do m[k] = v end
      return m
    end
    eq(valid(base()), true)
    local ten = {}
    for i = 1, 10 do ten[i] = false end
    ten[1] = A
    eq(valid(base{ s = ten }), false)
    eq(valid(base{ s = { A } }), false)
    eq(valid(base{ g = "optgame", s = { A, false, false }, o = { goal = 9 } }), false)
    eq(valid(base{ g = "optgame", s = { A, false, false }, o = { goal = 3 } }), true)
    eq(valid(base{ o = "x" }), false)
    eq(valid(base{ g = "nope", s = { A, false } }), true)
  end)

  it("a table of a game I do not have is listed but cannot be joined", function()
    local sim, _, b = setup()
    local refused = refusals(b)
    b:receive("GUILD", A, {v=1,t="TBL",tid="x#1",g="nope",h=A,e=1,ac="guild",tn=45,st="open",s={A,false},w=0})
    local n = #sim.sent; b:sit("x#1", 2); eq(refused, {{"x#1", "version"}}); eq(#sim.sent, n); eq(b.lobby:get("x#1").game, "nope")
  end)

  it("a TBL for an unintegrated engine game (belot) is treated like an unknown game", function()
    local sim, _, b = setup()
    local refused = refusals(b)
    b:receive("GUILD", A, {v=1,t="TBL",tid="x#2",g="belot",h=A,e=1,ac="guild",tn=45,st="open",s={A,false,false,false},w=0})
    local n = #sim.sent; b:sit("x#2", 2); eq(refused, {{"x#2", "version"}}); eq(#sim.sent, n); eq(b.lobby:get("x#2").game, "belot")
  end)
end)
