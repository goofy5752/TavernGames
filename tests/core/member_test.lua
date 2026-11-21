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

  it("a snapshot for a game that is not playable yet is answered with STD", function()
    local sim = Sim.new()
    local a = sim:add(A, { cls = "MAGE" })
    local b = sim:add(B, { cls = "PRIEST" })
    sim:run(1)
    sim.ns.Games.PLAYABLE.holdem = nil -- gated by hand: every game of ORDER is integrated
    ok(sim.ns.Engines.holdem and not sim.ns.Games.PLAYABLE.holdem, "holdem must be a gated engine")
    b:receive("WHISPER", A, {v=1, t="SNP", tid="x#1", e=1, q=0,
      tbl={tid="x#1", g="holdem", h=A, e=1, ac="guild", tn=45, st="open", s={A, B}, w=0}}); sim:run(1)
    local std = {}
    for _, s in ipairs(sim.sent) do if s.from == B and s.msg.t == "STD" then std[#std+1] = s end end
    eq(#std, 1); eq(std[1].target, A); eq(std[1].msg.tid, "x#1"); eq(b.session, nil)
    -- A session without resolved options still gives its record.
    a:openTable{game="ttt", access="guild", turn=45}; a.session.opt = nil
    eq(a.session:record().o, nil)
    sim.ns.Games.PLAYABLE.holdem = true
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

  -- The STD messages B sent about table `tid`.
  local function stds(sim, tid)
    local n = 0
    for _, s in ipairs(sim.sent) do if s.from == B and s.msg.t == "STD" and s.msg.tid == tid then n = n + 1 end end
    return n
  end

  for _, game in ipairs{ "ttt", "santase" } do
    it("a snapshot nobody asked for, of a table I was never at, is not adopted (" .. game .. ")", function()
      local sim = Sim.new()
      local a, b = sim:add(A, { cls = "MAGE" }), sim:add(B, { cls = "PRIEST" }); sim:run(1)
      local tid = a:openTable{ game = game, access = "guild", turn = 45 }; sim:run(3)
      b:sit(tid, 2); sim:run(2); eq({ b.session.tid, b.session.mySeat, b.session.status }, { tid, 2, "live" })   -- my own request: adopted
      local sa, other = a.session, A .. "#1700000099"
      a:send("GUILD", nil, sim.ns.Session.message("END", { tid = tid, e = sa.epoch })); sa.tid = other   -- the table ends under me and
      sa:snapshotTo(B); sim:run(2)                                                              -- "another one" seats me unasked
      eq(b.session, nil); ok(stds(sim, other) >= 1, "no STD"); eq(b.presence.at, nil)
      sa.tid, sa.seats[2] = tid, B; sa:snapshotTo(B); sim:run(1); eq({ b.session.tid, b.session.mySeat }, { tid, 2 })   -- the table I was at takes me back
    end)
  end

  it("the snapshots I may get unasked: my seat after a login, a table I was at; and the ones I asked for", function()
    local sim = Sim.new()
    local a, b = sim:add(A, { cls = "MAGE" }), sim:add(B, { cls = "PRIEST" }); sim:run(1)
    local tid = a:openTable{ game = "ttt", access = "invite", turn = 45 }; sim:run(3)
    ok(a:invite(B)); sim:run(1); b:answerInvite(tid, "yes"); sim:run(3); eq({ b.session.tid, b.session.mySeat }, { tid, 2 })   -- an invitation I took
    local b2 = sim:relog(B); sim:run(2); eq({ b2.session.tid, b2.session.mySeat }, { tid, 2 })   -- a login: my seat is still mine
    sim = Sim.new(); a, b = sim:add(A, { cls = "MAGE" }), sim:add(B, { cls = "PRIEST" }); sim:run(1)
    tid = a:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
    b:watch(tid); sim:run(1); eq({ b.session.tid, b.session.role }, { tid, "watcher" })           -- watching
    b:stand(); sim:run(1); eq(b.session, nil); a.session.seats[2] = B; a.session:snapshotTo(B); sim:run(1)
    eq(b.session, nil); ok(stds(sim, tid) >= 2)                                                   -- a table I left myself: not even that one
    local c = sim:add("Трети Играч", { cls = "ROGUE" }); sim:run(1)                              -- a host of my own table that ended it
    local mine = c:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3); c:stand(); sim:run(1); eq(c.session, nil)
    a.session.seats[2] = "Трети Играч"; a.session:snapshotTo("Трети Играч"); sim:run(1); eq(c.session, nil)
  end)
end)
