local Sim = require("sim")

local A, B = "Иван Петров", "Мария Стоянова"

local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

-- a opens a ttt table (t=4), A goes offline, b asks for seat 2.
local function unanswered()
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  sim:run(1)
  local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
  sim:offline(A)
  local refused = record(b, "refused")
  b:sit(tid, 2)
  return sim, a, b, tid, refused
end

describe("member side", function()
  it("a snapshot for a game I do not have is answered with STD", function()
    local sim = Sim.new()
    local _ = sim:add(A, { cls = "MAGE" })
    local b = sim:add(B, { cls = "PRIEST" })
    sim:run(1)
    b:receive("WHISPER", A, {v=1, t="SNP", tid="x#1", e=1, q=0,
      tbl={tid="x#1", g="nope", h=A, e=1, ac="guild", tn=45, st="open", s={A, B}, w=0}}); sim:run(1)
    local std = {}
    for _, s in ipairs(sim.sent) do if s.from == B and s.msg.t == "STD" then std[#std+1] = s end end
    eq(#std, 1); eq(std[1].target, A); eq(std[1].msg.tid, "x#1"); eq(b.session, nil)
  end)

  it("an unanswered sit request gives up after 10 s with 'gone'", function()
    local sim, _, b, tid, refused = unanswered()
    sim:run(9); eq(#refused, 0)
    sim:run(2); eq(refused, {{tid, "gone"}}); eq(b.pending, nil)
  end)

  it("an answer after giving up frees the seat again", function()
    local sim, a, b, tid = unanswered()
    sim:run(11)
    sim:online(A)
    a:receive("WHISPER", B, {v=1, t="SIT", tid=tid, seat=2})
    sim:run(2)
    eq(b.session, nil); eq(a.session.seats, {A, false})
  end)

  it("seatOf and abortIfShort", function()
    local ns = Sim.ns
    eq(ns.Util.seatOf({"a", false, "c"}, "c"), 3); eq(ns.Util.seatOf({"a"}, "z"), nil)
    eq(ns.Session.seatOf, ns.Util.seatOf)
    local sim = Sim.new()
    local a = sim:add(A, { cls = "MAGE" })
    local b = sim:add(B, { cls = "PRIEST" })
    sim:run(1)
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); sim:run(1)
    eq(a.session.status, "live")
    a.session.seats[2] = false
    eq(a.session:abortIfShort(), true); eq(a.session.status, "aborted")
    eq(a.session:abortIfShort(), false)
  end)
end)
