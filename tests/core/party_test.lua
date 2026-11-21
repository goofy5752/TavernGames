local Sim = require("sim")
local ns = Sim.ns

local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"

-- a, b, c in one sim (opts[name] merged into their sim:add options), presence exchanged.
local function clients(opts)
  opts = opts or {}
  local sim = Sim.new()
  local cls = { [A] = "MAGE", [B] = "PRIEST", [C] = "ROGUE" }
  local list = {}
  for i, name in ipairs({ A, B, C }) do
    local o = { cls = cls[name] }
    for k, v in pairs(opts[name] or {}) do o[k] = v end
    list[i] = sim:add(name, o)
  end
  sim:run(1)
  return sim, list[1], list[2], list[3]
end

-- clients(opts); a opens a `game` table, b sits in seat 2: -> sim, a, b, c, tid
local function seated(game, opts)
  local sim, a, b, c = clients(opts)
  local tid = a:openTable{game=game, access="guild", turn=45}; sim:run(3)
  b:sit(tid, 2); sim:run(1)
  return sim, a, b, c, tid
end

describe("party", function()
  it("the host invites a newcomer once, and again at the start only after 30 s", function()
    local sim, a, b = clients()
    local tid = a:openTable{game="deathroll", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); sim:run(1)
    eq(sim.groupInvites, {{from=A, name=B}}); ok(a:startGame()); sim:run(1); eq(#sim.groupInvites, 1)
    sim.nextRolls = {1}; ok(a:roll()); sim:run(1); eq(a.session.state.phase, "over")
    sim:run(31); ok(a:startGame()); sim:run(1)
    eq(#sim.groupInvites, 2); eq(sim.groupInvites[2], {from=A, name=B})
  end)

  it("nobody already in my group is invited", function()
    local sim, a = seated("deathroll", { [A] = { group = { B } } })
    ok(a:startGame()); sim:run(1)
    eq(sim.groupInvites, {}); eq(ns.Party.missing(a.session), {})
  end)

  it("a host who is not the leader, or whose party is full, invites nobody and says why", function()
    local sim, a = seated("deathroll", { [A] = { party = { grouped=true, leader=false, raid=false, size=3 } } })
    eq(sim.groupInvites, {}); eq(a.session.partyWhy, "notleader")
    sim, a = seated("deathroll", { [A] = { party = { grouped=true, leader=true, raid=false, size=5 } } })
    eq(sim.groupInvites, {}); eq(a.session.partyWhy, "full")
    sim, a = seated("deathroll", { [A] = { party = { grouped=true, leader=true, raid=true, size=5 } } })
    eq(sim.groupInvites, {{from=A, name=B}}); eq(a.session.partyWhy, nil)
  end)

  it("a ttt table invites nobody", function()
    local sim, a = seated("ttt")
    eq(a.session.status, "live"); eq(sim.groupInvites, {})
  end)

  it("only my table's host is auto-accepted", function()
    local sim, a, b, c = seated("deathroll")
    eq(b:groupInviteFrom("Иван"), true); eq(b:groupInviteFrom(A), true); eq(b:groupInviteFrom("Kiro"), false)
    eq(a:groupInviteFrom("Мария"), false); eq(c:groupInviteFrom("Иван"), false)
    sim, a, b = seated("ttt")
    eq(b.session.mySeat, 2); eq(b:groupInviteFrom("Иван"), false)
  end)

  -- The host invites (env.groupInvite) before its SNP reaches the sitter, so the
  -- invite is asked about while the sit request is still pending.
  it("the invite that arrives before the snapshot is accepted from the host I asked to sit with", function()
    local sim, a, b, c = clients()
    local tid = a:openTable{game="deathroll", access="guild", turn=45}; sim:run(3)
    local asked = {}
    local invite = a.env.groupInvite
    a.env.groupInvite = function(who)
      local cl = sim.clients[who]
      asked[#asked + 1] = { who = who, session = cl.session ~= nil, host = cl:groupInviteFrom("Иван"),
        other = cl:groupInviteFrom("Kiro") }
      invite(who)
    end
    b:sit(tid, 2); sim:run(1)
    eq(asked, {{ who = B, session = false, host = true, other = false }})
    eq(b.session.mySeat, 2); eq(b:groupInviteFrom("Иван"), true)
  end)

  it("a pending watch, or a pending sit at a table without a group, accepts nothing", function()
    local sim, a, b, c = clients()
    local tid = a:openTable{game="deathroll", access="guild", turn=45}; sim:run(3)
    c:watch(tid); ok(c.pending ~= nil); eq(c:groupInviteFrom("Иван"), false)
    sim, a, b = clients()
    tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); ok(b.pending ~= nil); eq(b:groupInviteFrom("Иван"), false)
  end)

  it("a watcher who asks for a seat accepts the host's invite before the snapshot", function()
    local sim, a, b, c = clients()
    local tid = a:openTable{game="deathroll", access="guild", turn=45}; sim:run(3)
    b:watch(tid); sim:run(1); eq(b.session.role, "watcher"); eq(b:groupInviteFrom("Иван"), false)
    local asked
    a.env.groupInvite = function(who) asked = sim.clients[who]:groupInviteFrom("Иван") end
    b:sit(tid, 2); sim:run(1)
    eq(asked, true); eq(b.session.mySeat, 2)
    -- A watcher whose sit request was refused, or is old, accepts nothing.
    c:watch(tid); sim:run(1); c:sit(tid, 2); eq(c:groupInviteFrom("Иван"), true); sim:run(1)
    eq(c.session.role, "watcher"); eq(c:groupInviteFrom("Иван"), false)
    c.env.send = function() end; c:sit(tid, 2); eq(c:groupInviteFrom("Иван"), true)
    sim:run(10); eq(c:groupInviteFrom("Иван"), false)
  end)

  it("an extension that errors after the sit is traced, and the sitter still gets the table", function()
    local sim, a, b = clients()
    local lines = {}
    a.env.strictHooks = false -- this checks the in-game behaviour: the error is contained
    a.env.log = function(dir, channel, peer, msg) lines[#lines + 1] = { dir, channel, peer, msg } end
    a.env.group = function() error("no IsInRaid") end
    local tid = a:openTable{game="deathroll", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); sim:run(1)
    ok(b.session and b.session.mySeat == 2, "the sitter has no table")
    eq(a.session.seats[2], B); eq(a.lobby:get(tid).seats[2], B)
    local errors = {}
    for _, l in ipairs(lines) do
      if l[1] == "error" then errors[#errors + 1] = l end
    end
    eq(#errors, 1); eq({ errors[1][2], errors[1][3] }, { "ext", "party.applied" })
    ok(tostring(errors[1][4]):find("no IsInRaid", 1, true), tostring(errors[1][4]))
    sim:run(11); eq(b.session.mySeat, 2)
  end)

  it("missing lists who is outside my group, for any seated client", function()
    local sim, a, b, c = clients({ [B] = { group = { A } } })
    local tid = a:openTable{game="deathroll", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); c:sit(tid, 3); sim:run(1)
    eq(ns.Party.missing(b.session), {C})
  end)

  it("groupChanged emits the session only when there is one", function()
    local sim, a, b = seated("deathroll")
    local seen = {}
    b:on("session", function(s) seen[#seen + 1] = s end)
    local c = sim.clients[C]; local none = 0
    c:on("session", function() none = none + 1 end)
    b:groupChanged(); c:groupChanged()
    eq(#seen, 1); ok(seen[1] == b.session); eq(none, 0)
  end)
end)
