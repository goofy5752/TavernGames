local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local Games, E = ns.Games, ns.Engines.holdem

-- Stage F3, Task 4: a staked Холдем table's options, its stake (the big blind
-- in copper), the options my note pins, and the names the engine gets.
local A, B, P = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3]
local SK = 1000 -- the stake of blinds 10: 10 chips of one silver

-- A guild of Иван, Петър and Мария; Иван opens Холдем at `sk` (nil: for fun) -> sim, cl, tid.
local function opened(sk, opt)
  local sim, cl = Play.guild(3)
  local tid = assert(cl[A]:openTable{ game = "holdem", access = "guild", turn = 30, opt = opt, stake = sk })
  sim:run(3)
  return sim, cl, tid
end

-- The last GUILD TBL `from` sent.
local function lastTBL(sim, from)
  local out
  for _, m in ipairs(sim.sent) do
    if m.channel == "GUILD" and m.from == from and m.msg.t == "TBL" then out = m.msg end
  end
  return out
end

-- Every `how` the hook `adopted` of the extension stakes hears on `client` while f runs.
local function spyHow(client, f)
  local list, Ext = {}, ns.Ext.stakes
  local real = Ext.adopted
  Ext.adopted = function(s, prev, m, how)
    if s.client == client then list[#list + 1] = how end
    return real(s, prev, m, how)
  end
  local fine, err = pcall(f)
  Ext.adopted = real
  if not fine then error(err, 0) end
  return list
end

describe("the table I accepted: blinds, betting, rebuy", function()
  it("staked options: rebuy only with a stake, stack only without", function()
    eq(Games.resolve("holdem", nil), { betting = "nl", blinds = 10, stack = 100 })
    eq(Games.resolve("holdem", nil, true), { betting = "nl", blinds = 10, rebuy = "bust" })
    eq(Games.resolve("holdem", { rebuy = "top" }), nil); eq(Games.resolve("holdem", { stack = 50 }, true), nil)
    eq(Games.resolve("santase", nil, true), Games.resolve("santase", nil))
    eq(Games.resolve("deathroll", { start = 100 }, true), Games.resolve("deathroll", { start = 100 }))
  end)

  it("the stake of a cash table is its big blind in copper", function()
    eq(E.stakeOf({ blinds = 20 }), 2000)
    eq(ns.Stake.allowed("holdem", 2000, { blinds = 20 }), true); eq(ns.Stake.allowed("holdem", 5000, { blinds = 20 }), false)
    eq(ns.Stake.allowed("holdem", 2000), true) -- no options given: a stake as before
    eq(ns.Stake.allowed("ttt", 50000, {}), true) -- an engine without stakeOf ignores them
    eq(ns.Stake.worst("holdem", 2000), 200000)
    eq(ns.Stake.worst("ttt", 2000), 2000); eq(ns.Stake.worst("belot", 2000), 4000)
  end)

  it("openTable refuses a stake that is not the big blind, and a fun option with a stake", function()
    local sim, cl = Play.guild(1)
    local host = cl[A]
    eq({ host:openTable{ game = "holdem", access = "guild", turn = 30, opt = { blinds = 20 }, stake = 1000 } }, { nil, "stake" })
    eq({ host:openTable{ game = "holdem", access = "guild", turn = 30, opt = { stack = 50 }, stake = 1000 } }, { nil, "opt" })
    eq({ host:openTable{ game = "holdem", access = "guild", turn = 30, opt = { rebuy = "top" } } }, { nil, "opt" })
    ok(host:openTable{ game = "holdem", access = "guild", turn = 30, opt = { blinds = 20, rebuy = "top" }, stake = 2000 })
    eq(host.session.opt, { betting = "nl", blinds = 20, rebuy = "top" }); eq(host.session.stake, 2000)
    sim:run(1)
  end)

  it("a TBL whose sk is not its blinds is not listed", function()
    local sim, cl = Play.guild(3)
    local function fake(o, sk)
      cl[P]:send("GUILD", nil, { v = 1, t = "TBL", tid = P .. "#1", g = "holdem", h = P, e = 1, ac = "guild",
        tn = 30, st = "open", s = { P, false, false, false, false, false }, w = 0, sk = sk, o = o })
      sim:run(1)
      return cl[B].lobby:get(P .. "#1")
    end
    eq(fake({ blinds = 20 }, 1000), nil)
    eq(fake({ blinds = 10, stack = 100 }, 1000), nil) -- a fun option at a staked table
    eq(fake({ blinds = 10, rebuy = "top" }, nil), nil) -- a staked option at a fun table
    ok(fake({ blinds = 20 }, 2000), "blinds 20 at 20s is listed")
  end)

  it("a staked TBL announces rebuy and no stack; a fun one stack and no rebuy", function()
    local sim = opened(SK)
    eq(lastTBL(sim, A).o, { betting = "nl", blinds = 10, rebuy = "bust" }); eq(lastTBL(sim, A).sk, SK)
    sim = opened(nil)
    eq(lastTBL(sim, A).o, { betting = "nl", blinds = 10, stack = 100 }); eq(lastTBL(sim, A).sk, nil)
  end)

  it("my note keeps the options I sat down to", function()
    local sim, cl, tid = opened(SK)
    eq(cl[A].env.db.stakeSat, { tid = tid, sk = SK, tn = 30, o = { betting = "nl", blinds = 10, rebuy = "bust" } })
    cl[B]:sit(tid, 2, SK); sim:run(1)
    eq(cl[B].session.mySeat, 2)
    eq(cl[B].env.db.stakeSat.o, { betting = "nl", blinds = 10, rebuy = "bust" })
    eq(cl[B].session.opt, { betting = "nl", blinds = 10, rebuy = "bust" })
    -- The note is a copy: my session's options are not it.
    ok(cl[B].env.db.stakeSat.o ~= cl[B].session.opt and cl[A].env.db.stakeSat.o ~= cl[A].session.opt)
    -- A fun table notes no options.
    sim, cl, tid = opened(nil)
    cl[B]:sit(tid, 2); sim:run(1)
    eq(cl[A].env.db.stakeSat, { tid = tid, tn = 30 }); eq(cl[B].env.db.stakeSat, { tid = tid, tn = 30 })
  end)

  it("my note holds the resolved options, not the lobby record's raw ones (H12)", function()
    local sim, cl, tid = opened(SK)
    -- The host announces and pushes its options without the default rebuy.
    cl[A].session.opt.rebuy = nil
    cl[B].lobby:get(tid).opt.rebuy = nil
    local hows = spyHow(cl[B], function() cl[B]:sit(tid, 2, SK); sim:run(1) end)
    eq(cl[B].session.mySeat, 2)
    eq(cl[B].env.db.stakeSat.o.rebuy, "bust"); eq(cl[B].session.opt.rebuy, "bust")
    eq(#hows, 1); eq(hows[1].o, false)
    ok(cl[A]:startGame()); sim:run(1)
    eq(cl[B].session.state.cash.rebuy, "bust")
    -- The host's snapshot of the running game still leaves the default out: no foul.
    hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(hows[1].o, false); eq(cl[B].session.stakeFoul, nil)
  end)

  it("a snapshot with another rebuy mode keeps mine, says so and is forged", function()
    local sim, cl, tid = opened(SK)
    cl[B]:sit(tid, 2, SK); sim:run(1)
    ok(cl[A]:startGame()); sim:run(1)
    eq(cl[B].session.stakeFoul, nil)
    cl[A].session.opt.rebuy = "top"
    local hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(#hows, 1); eq(hows[1].o, true)
    eq(cl[B].session.opt.rebuy, "bust"); eq(cl[B].env.db.stakeSat.o.rebuy, "bust")
    eq(cl[B].session.stakeFoul, "forged") -- the state is the one I hold: only the options are other
    -- Another betting kind too; my own options back from the host: nothing to say.
    cl[A].session.opt.rebuy, cl[A].session.opt.betting = "bust", "pl"
    hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(hows[1].o, true); eq(cl[B].session.opt, { betting = "nl", blinds = 10, rebuy = "bust" })
    cl[A].session.opt.betting = "nl"
    hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(hows[1].o, false)
  end)

  it("a note without options takes the snapshot's, once", function()
    local sim, cl, tid = opened(SK)
    cl[B]:sit(tid, 2, SK); sim:run(1)
    cl[B].env.db.stakeSat.o = nil -- a note an F2 client wrote
    local hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(hows[1].o, false); eq(cl[B].env.db.stakeSat.o, { betting = "nl", blinds = 10, rebuy = "bust" })
    cl[A].session.opt.rebuy = "none"
    hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(hows[1].o, true); eq(cl[B].session.opt.rebuy, "bust")
  end)

  it("a relog keeps my pinned options, and host succession keeps them (M2)", function()
    local sim, cl, tid = opened(SK)
    cl[B]:sit(tid, 2, SK); sim:run(1)
    cl[P]:sit(tid, 3, SK); sim:run(1)
    ok(cl[A]:startGame()); sim:run(1)
    cl[A].session.opt.rebuy = "top"
    local b = sim:relog(B); sim:run(3)
    cl[A].session:snapshotTo(B); sim:run(1)
    eq(b.session.opt.rebuy, "bust"); eq(b.env.db.stakeSat.o.rebuy, "bust")
    eq(b.session.stakeFoul, "forged")
    -- The host goes: a member who claims hosts with the options it accepted.
    cl[A].session.opt.rebuy = "bust"
    cl[A]:stop(); sim:run(200)
    local host
    for _, c in ipairs({ b, cl[P] }) do
      if c.session and c.session.role == "host" then host = c end
    end
    ok(host, "a member hosts")
    eq(host.session.opt, { betting = "nl", blinds = 10, rebuy = "bust" })
    eq(host.env.db.stakeSat.o.rebuy, "bust")
  end)

  it("an accepted ask notes the table's options", function()
    local sim, cl, tid = opened(SK)
    cl[B]:sit(tid, 2, SK); sim:run(1)
    ok(cl[A]:startGame()); sim:run(1)
    sim.envs[B].db.stakeSat = nil -- a crash lost my note
    local b = sim:relog(B); sim:run(3)
    eq(b.session.stakeAsk, true)
    eq(b:acceptStake(), true)
    eq(b.env.db.stakeSat, { tid = tid, sk = SK, tn = 30, o = { betting = "nl", blinds = 10, rebuy = "bust" } })
  end)

  it("the engine's seats carry the names at a staked table and none at a fun one", function()
    local sim, cl, tid = opened(SK)
    cl[B]:sit(tid, 2, SK); sim:run(1)
    ok(cl[A]:startGame()); sim:run(1)
    eq(cl[A].session.state.seats[1].who, A); eq(cl[A].session.state.seats[2].who, B)
    eq(cl[B].session.state.seats[2].who, B)
    cl[P]:sit(tid, 3, SK); sim:run(1)
    eq(cl[A].session.state.seats[3].who, P); eq(cl[B].session.state.seats[3].who, P)
    sim, cl, tid = opened(nil)
    cl[B]:sit(tid, 2); sim:run(1)
    ok(cl[A]:startGame()); sim:run(1)
    eq(cl[A].session.state.seats[2].who, nil); eq(cl[A].session.state.cash, nil)
    cl[P]:sit(tid, 3); sim:run(1)
    eq(cl[A].session.state.seats[3].who, nil)
  end)

  it("Play.cash seats, starts and buys", function()
    local sim, cl = Play.cash(3, nil, { 1000, 600, 400 })
    local host = cl[A]
    local st = host.session.state
    eq(host.session.stake, SK); eq(st.cash.rebuy, "bust")
    for i, n in ipairs({ 1000, 600, 400 }) do
      eq(st.seats[i].bought, n); eq(st.seats[i].who, Play.NAMES[i])
    end
    for _ = 1, 30 do
      if E.inHand(host.session.state) then break end
      sim:run(1)
    end
    ok(E.inHand(host.session.state), "a hand begins")
    Play.hand(sim, host)
    ok(host.session.state.hand >= 1)
    local sum = 0
    for i = 1, 3 do sum = sum + host.session.state.seats[i].chips end
    eq(sum, 2000)
  end)

  it("a leaver that sits again by name is held to the stack it left with", function()
    local sim, cl, tid = Play.cash(3)
    local host, K = cl[A], Play.NAMES[3]
    cl[K]:stand(); sim:run(1)
    for _ = 1, 400 do
      if not host.session.state.seats[3] then break end
      Play.step(sim, host)
    end
    eq(host.session.state.seats[3], false)
    local left = host.session.state.cash.left[K]
    ok(type(left) == "number" and left > 400, "left with " .. tostring(left))
    cl[K]:sit(tid, 3, SK); sim:run(1)
    eq(cl[K].session.mySeat, 3)
    eq(host.session.state.seats[3].who, K)
    eq(E.buyRange(host.session.state, 3), math.min(left, 1000))
    eq(E.buyRange(cl[K].session.state, 3), math.min(left, 1000))
    eq({ cl[K]:act{ k = "buy", n = 400 } }, { nil, "amount" })
    ok(cl[K]:act{ k = "buy", n = math.min(left, 1000) }); sim:run(1)
    eq(host.session.state.seats[3].bought, math.min(left, 1000))
  end)

  it("a Death Roll note holds its start; a snapshot with another keeps mine, says so and is forged (I1)", function()
    local sim, cl = Play.guild(3)
    local tid = assert(cl[A]:openTable{ game = "deathroll", access = "guild", turn = 45, stake = 50000 }); sim:run(3)
    eq(cl[A].env.db.stakeSat, { tid = tid, sk = 50000, tn = 45, o = { start = 1000 } })
    cl[B]:sit(tid, 2, 50000); sim:run(1)
    eq(cl[B].env.db.stakeSat, { tid = tid, sk = 50000, tn = 45, o = { start = 1000 } })
    eq(cl[B].session.opt, { start = 1000 })
    cl[A].session.opt.start = 100
    local hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(#hows, 1); eq(hows[1].o, true)
    eq(cl[B].session.opt.start, 1000); eq(cl[B].env.db.stakeSat.o.start, 1000)
    eq(cl[B].session.stakeFoul, "forged")
    -- Opened with another start: the note holds that one.
    local sim2, cl2 = Play.guild(2)
    assert(cl2[A]:openTable{ game = "deathroll", access = "guild", turn = 45, stake = 50000, opt = { start = 100 } })
    sim2:run(3)
    eq(cl2[A].env.db.stakeSat.o, { start = 100 })
  end)

  it("an older Death Roll note without options takes the snapshot's, once (I1)", function()
    local sim, cl = Play.guild(3)
    local tid = assert(cl[A]:openTable{ game = "deathroll", access = "guild", turn = 45, stake = 50000 }); sim:run(3)
    cl[B]:sit(tid, 2, 50000); sim:run(1)
    cl[B].env.db.stakeSat.o = nil -- an F1/F2 note
    local hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(hows[1].o, false); eq(cl[B].env.db.stakeSat.o, { start = 1000 })
    cl[A].session.opt.start = 100
    hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(hows[1].o, true); eq(cl[B].session.opt.start, 1000)
  end)

  it("a note missing a newly added option's default does not make honest snapshots forged (M1)", function()
    local sim, cl, tid = opened(SK)
    cl[B]:sit(tid, 2, SK); sim:run(1)
    cl[B].env.db.stakeSat.o.rebuy = nil -- written by a build without that option
    local hows = spyHow(cl[B], function() cl[A].session:snapshotTo(B); sim:run(1) end)
    eq(hows[1].o, false); eq(cl[B].session.stakeFoul, nil)
    eq(cl[B].session.opt, { betting = "nl", blinds = 10, rebuy = "bust" })
  end)

  it("an option's `at` is fun, stake or nothing; anything else is an error (M3)", function()
    local o = ns.Games.engine("holdem").options[1]
    local old = o.at
    o.at = "stakes"
    local fine = pcall(Games.resolve, "holdem", nil, true)
    o.at = old
    eq(fine, false)
    eq(Games.resolve("holdem", nil, true), { betting = "nl", blinds = 10, rebuy = "bust" })
  end)
end)
