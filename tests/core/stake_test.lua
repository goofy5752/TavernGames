local Sim = require("sim")
local ns = Sim.ns
local Stake, Bots = ns.Stake, ns.Bots

local A, B, P = "Иван Петров", "Мария Стоянова", "Петър Колев"

-- Иван hosts, Мария and Петър are guild members.
local function setup()
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  local c = sim:add(P, { cls = "ROGUE" })
  sim:run(1)
  return sim, a, b, c
end

-- Every emission of `event` on `client`, as a list of argument lists.
local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

-- The messages of type `t` from `from` after sim.sent[mark], as sim.sent rows.
local function sent(sim, from, t, mark)
  local out = {}
  for i, s in ipairs(sim.sent) do
    if i > (mark or 0) and s.from == from and s.msg.t == t then out[#out + 1] = s end
  end
  return out
end

local function lastGuildTBL(sim, from, mark)
  local list, out = sent(sim, from, "TBL", mark), nil
  for _, s in ipairs(list) do
    if s.channel == "GUILD" then out = s.msg end
  end
  return out
end

-- A staked ttt table of Иван with Мария seated at `sk`.
local function seatedAt(sk)
  local sim, a, b, c = setup()
  local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = sk }; sim:run(3)
  b:sit(tid, 2, sk); sim:run(1)
  return sim, a, b, c, tid
end

-- A hand-made TBL of `game` with `sk`, sent on GUILD by `client`.
local function fakeTBL(sim, client, game, seats, sk)
  local tid = client.env.me .. "#1"
  client:send("GUILD", nil, { v = 1, t = "TBL", tid = tid, g = game, h = client.env.me, e = 1, ac = "guild",
    tn = 45, st = "open", s = seats, w = 0, sk = sk })
  sim:run(1)
  return tid
end

-- A test-only engine like "fake" that takes stakes and waits for three players.
local FS = { id = "fillstake", minSeats = 3, maxSeats = 3, stakes = true }
function FS.new() return { n = 0, turn = 1 } end
function FS.apply() return nil, "action" end
function FS.legal() return {} end
function FS.auto() return nil end
function FS.system() return nil end
FS.snapshot, FS.restore = ns.Util.copy, ns.Util.copy

local TTT = ns.Engines.ttt

-- Both players of a ttt table play E.auto until the match is over.
local function playOut(sim, host, guest)
  for _ = 1, 200 do
    local s = host.session
    if not s or s:gameOver() then return end
    local seat = s.state and s.state.turn
    if seat == 1 then host:act(TTT.auto(s.state, 1)) elseif seat == 2 and guest.session then guest:act(TTT.auto(guest.session.state, 2)) end
    sim:run(1)
  end
end

describe("stake", function()
  it("valid: whole silver from 1s to the gold cap", function()
    eq(Stake.valid(100), true); eq(Stake.valid(50000), true); eq(Stake.valid(99999990000), true)
    eq(Stake.valid(99), false); eq(Stake.valid(150), false); eq(Stake.valid(0), false)
    eq(Stake.valid(-100), false); eq(Stake.valid(100.5), false); eq(Stake.valid("100"), false)
    eq(Stake.valid(99999990100), false); eq(Stake.valid(nil), false)
    eq(Stake.MIN, 100); eq(Stake.MAX, 99999990000)
  end)

  it("fromParts", function()
    eq(Stake.fromParts(5, 0), 50000); eq(Stake.fromParts(0, 25), 2500); eq(Stake.fromParts(12, 50), 125000)
    eq(Stake.fromParts(0, 0), nil); eq(Stake.fromParts(1, 100), nil); eq(Stake.fromParts(-1, 0), nil); eq(Stake.fromParts(1.5, 0), nil)
  end)

  it("worst: Death Roll pays everyone else", function()
    eq(Stake.worst("deathroll", 10000), 40000); eq(Stake.worst("ttt", 10000), 10000)
  end)

  it("a staked table announces sk and a fun table none", function()
    local sim, a, b = setup()
    local mark = #sim.sent
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(1)
    eq(lastGuildTBL(sim, A, mark).sk, 50000)
    eq(b.lobby:get(tid).stake, 50000); eq(a.session.stake, 50000); eq(a.session:record().sk, 50000)

    local sim2, a2, b2 = setup()
    mark = #sim2.sent
    local tid2 = a2:openTable{ game = "ttt", access = "guild", turn = 45 }; sim2:run(1)
    -- Field for field the TBL of the same call at 82b0140.
    eq(lastGuildTBL(sim2, A, mark), { v = 1, t = "TBL", tid = tid2, g = "ttt", h = A, e = 1, ac = "guild", tn = 45,
      st = "open", s = { A, false }, w = 0 })
    eq(b2.lobby:get(tid2).stake, nil); eq(a2.session.stake, nil)
  end)

  it("openTable refuses a bad stake", function()
    local sim, a = setup()
    local mark = #sim.sent
    local tid, why = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 150 }; sim:run(3)
    eq(tid, nil); eq(why, "stake"); eq(a.session, nil)
    eq(#sent(sim, A, "TBL", mark), 0)
  end)

  it("a stake is refused for a game that is not ready", function()
    local sim, a, b, c = setup()
    for _, game in ipairs({ "santase", "belot", "tabla", "holdem" }) do
      local tid, why = a:openTable{ game = game, access = "guild", turn = 45, stake = 50000 }
      eq(tid, nil); eq(why, "stake"); eq(a.session, nil)
    end
    local tid = fakeTBL(sim, c, "santase", { P, false }, 50000)
    eq(b.lobby:get(tid), nil)
    -- The same table for fun is listed; a staked Death Roll opens.
    tid = fakeTBL(sim, c, "santase", { P, false }, nil)
    ok(b.lobby:get(tid), "a fun santase TBL is listed")
    tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    ok(tid, "a staked deathroll opens"); eq(b.lobby:get(tid).stake, 50000)
  end)

  it("a sit must carry the table's stake", function()
    local sim, a, b = setup()
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    local refused = record(b, "refused")
    b:sit(tid, 2); sim:run(1)
    eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false); eq(b.session, nil)
    b:sit(tid, 2, 10000); sim:run(1)
    eq(refused, { { tid, "stake" }, { tid, "stake" } }); eq(a.session.seats[2], false)
    b:sit(tid, 2, 50000); sim:run(1)
    eq(a.session.seats[2], B); eq(b.session.mySeat, 2); eq(b.session.stake, 50000)
    eq(#refused, 2)
    eq(b.env.db.stakeSat, { tid = tid, sk = 50000 })
    local sit = sent(sim, B, "SIT"); eq(sit[#sit].msg.sk, 50000)
    -- A repeated click without the stake while seated: the snapshot again, my note and seat stay.
    local mark = #sim.sent
    b:sit(tid, 2); sim:run(1)
    eq(b.env.db.stakeSat, { tid = tid, sk = 50000 }); eq(b.session.mySeat, 2); eq(a.session.seats[2], B)
    eq(#sent(sim, B, "STD", mark), 0); eq(#refused, 2)
  end)

  it("a sit at a fun table with an sk is refused", function()
    local sim, a, b = setup()
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
    local refused = record(b, "refused")
    b:sit(tid, 2, 100); sim:run(1)
    eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false)
    b:sit(tid, 2); sim:run(1)
    eq(a.session.seats[2], B); eq(b.session.stake, nil)
    local sit = sent(sim, B, "SIT"); eq(sit[#sit].msg, { v = 1, t = "SIT", tid = tid, seat = 2 })
  end)

  it("a watcher needs no stake", function()
    local sim, a, b, c, tid = seatedAt(50000)
    c:watch(tid); sim:run(1)
    eq(c.session.role, "watcher"); eq(c.session.stake, 50000); eq(a.session.watchers, 1)
  end)

  it("a TBL with a malformed sk is not listed", function()
    local sim, _, b, c = setup()
    local tid = fakeTBL(sim, c, "ttt", { P, false }, 150)
    eq(b.lobby:get(tid), nil)
    fakeTBL(sim, c, "ttt", { P, false }, "50000"); eq(b.lobby:get(tid), nil)
    fakeTBL(sim, c, "ttt", { P, false }, 50000); eq(b.lobby:get(tid).stake, 50000)
  end)

  it("the stake travels with the table to a new host", function()
    local sim, a, b, _, tid = seatedAt(50000)
    local mark = #sim.sent
    a:stand(); sim:run(3)
    eq(b.session.role, "host"); eq(b.session.stake, 50000)
    local tbl = lastGuildTBL(sim, B, mark)
    eq(tbl.tid, tid); eq(tbl.h, B); eq(tbl.sk, 50000)
  end)

  it("a snapshot with another stake than I accepted stands me up", function()
    local sim, a, b, _, tid = seatedAt(10000)
    eq(b.session.mySeat, 2)
    local refused = record(b, "refused")
    local mark = #sim.sent
    sim.bus.filter = function(from, _, _, m)
      if from == A and m.t == "SNP" then m.tbl.sk = 1000000 end
      return { m }
    end
    a.session:snapshotTo(B); sim:run(1)
    sim.bus.filter = nil
    eq(#sent(sim, B, "STD", mark), 1); eq(b.session, nil)
    eq(refused, { { tid, "stake" } })
    eq(a.session.seats[2], false)
  end)

  it("an invitation shows the stake and its yes sits with it", function()
    local sim, a, b = setup()
    local got
    b:on("invite", function(inv) got = inv end)
    local mark = #sim.sent
    local tid = a:openTable{ game = "ttt", access = "invite", turn = 45, stake = 50000 }; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    eq(sent(sim, A, "INV", mark)[1].msg.sk, 50000)
    eq(got.tid, tid); eq(got.stake, 50000)
    b:answerInvite(tid, "yes"); sim:run(1)
    eq(sent(sim, B, "SIT", mark)[1].msg.sk, 50000)
    eq(a.session.seats[2], B); eq(b.session.stake, 50000)
  end)

  it("a fun invitation carries no stake", function()
    local sim, a, b = setup()
    local got
    b:on("invite", function(inv) got = inv end)
    local mark = #sim.sent
    local tid = a:openTable{ game = "ttt", access = "invite", turn = 45 }; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    eq(sent(sim, A, "INV", mark)[1].msg, { v = 1, t = "INV", tid = tid, g = "ttt", h = A, s = { A, false } })
    eq(got.stake, nil)
  end)

  it("a relog into my staked seat keeps it", function()
    local sim, a, b, _, tid = seatedAt(50000)
    local mark = #sim.sent
    b = sim:relog(B); sim:run(3)
    eq(b.session and b.session.mySeat, 2); eq(b.session.stake, 50000)
    eq(#sent(sim, B, "STD", mark), 0); eq(a.session.seats[2], B)

    -- A crash: no note of this table. The seat is kept with the host's stake.
    sim.envs[B].db.stakeSat = nil
    mark = #sim.sent
    b = sim:relog(B); sim:run(3)
    eq(b.session and b.session.mySeat, 2); eq(b.session.stake, 50000)
    eq(#sent(sim, B, "STD", mark), 0); eq(a.session.seats[2], B)

    -- A note of another stake for this table: I stand up.
    sim.envs[B].db.stakeSat = { tid = tid, sk = 10000 }
    mark = #sim.sent
    b = sim:relog(B)
    local refused = record(b, "refused")
    sim:run(3)
    eq(b.session, nil); eq(#sent(sim, B, "STD", mark), 1)
    eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false)
  end)

  it("a bot never gets a seat at a staked table", function()
    local sim, a = setup()
    local name = "Бот Тестов"
    local bot = sim:join(name, sim.makeEnv(name, "WARRIOR")); sim:run(1)
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    local refused = record(bot, "refused")
    local mark = #sim.sent
    bot:sit(tid, 2); sim:run(1)
    local sno = sent(sim, A, "SNO", mark)
    eq(#sno, 1); eq(sno[1].target, name); eq(sno[1].msg.why, "stake")
    eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false)
  end)

  it("a bot declines an invitation to a staked table", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" }); local bots = Bots.enable(a, envA, sim.makeEnv); sim:run(1)
    local answers = record(a, "inviteAnswer")
    a:openTable{ game = "ttt", access = "invite", turn = 45, stake = 50000 }; sim:run(1)
    ok(a:invite("Бот Иванов")); sim:run(5)
    eq(answers, { { "Бот Иванов", "auto", "busy" } }); eq(a.session.seats[2], false)
    eq(bots.list[1].session, nil)
    -- Bots:fill adds nobody to a staked table.
    eq(bots:fill(), nil); sim:run(10)
    eq(a.session.seats[2], false); eq(#answers, 1)
    a:stand(); sim:run(3)

    -- A bot hosting a staked table that waits for a third player fills nobody in.
    ns.Engines.fillstake = FS
    local host = bots.list[2]
    local tid = host:openTable{ game = "fillstake", access = "guild", turn = 45, stake = 50000 }; sim:run(1)
    a:sit(tid, 2, 50000); sim:run(5)
    eq(host.session.seats, { host.env.me, A, false }); eq(next(host.invites.sent), nil)
    a:stand(); sim:run(3)
    host:stand(); sim:run(3)

    -- An invitation to a fun table is accepted as today, and the auto-fill works there.
    tid = host:openTable{ game = "fillstake", access = "guild", turn = 45 }; sim:run(1)
    a:sit(tid, 2); sim:run(5)
    eq(host.session.seats[3] ~= false, true)
    a:stand(); sim:run(3)
    answers = record(a, "inviteAnswer")
    a:openTable{ game = "ttt", access = "invite", turn = 45 }; sim:run(1)
    local idle = bots:idle()
    sim:run(1) -- a bot spawned just now: my presence hears its HI first
    ok(a:invite(idle.env.me)); sim:run(5)
    eq(answers, { { idle.env.me, "yes" } }); eq(a.session.seats[2], idle.env.me)
    ns.Engines.fillstake = nil
  end)

  it("a note of another table written in this run accepts no stake here (C1)", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    b:sit(tid, 2, 50000); sim:run(1); eq(b.session.mySeat, 2)
    b:stand(); sim:run(1)
    local fun = c:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
    b:sit(fun, 2); sim:run(1); eq(b.session.tid, fun)
    b:stand(); sim:run(1)
    eq(b.env.db.stakeSat, { tid = fun })
    -- Иван's modified client seats Мария again and pushes a snapshot at another stake.
    local refused, asks = record(b, "refused"), record(b, "stakeAsk")
    local mark = #sim.sent
    a.session:event(0, { k = "sit", seat = 2, name = B })
    sim.bus.filter = function(from, _, _, m)
      if from == A and m.t == "SNP" then m.tbl.sk = 5000000 end
      return { m }
    end
    a.session:snapshotTo(B); sim:run(1)
    sim.bus.filter = nil
    eq(b.session, nil); ok(#sent(sim, B, "STD", mark) >= 1, "no STD"); eq(a.session.seats[2], false)
    eq(refused, { { tid, "stake" } }); eq(asks, {})
    -- At a fun table the same note matches: seated as before.
    local sim2, a2, b2, c2 = setup()
    local t1 = a2:openTable{ game = "ttt", access = "guild", turn = 45 }; sim2:run(3)
    b2:sit(t1, 2); sim2:run(1); b2:stand(); sim2:run(1)
    local t2 = c2:openTable{ game = "ttt", access = "guild", turn = 45 }; sim2:run(3)
    b2:sit(t2, 2); sim2:run(1); b2:stand(); sim2:run(1)
    a2.session:event(0, { k = "sit", seat = 2, name = B }); a2.session:snapshotTo(B); sim2:run(1)
    eq(b2.session and b2.session.tid, t1); eq(b2.session.mySeat, 2); eq(b2.session.stake, nil)
  end)

  it("the opener's own note keeps its stake after a relog (I1)", function()
    local sim, a, b, _, tid = seatedAt(50000)
    eq(a.env.db.stakeSat, { tid = tid, sk = 50000 })
    ok(a:act{ k = "mark", c = 1 }); sim:run(1)
    local last = 0; for _, s in ipairs(sim.sent) do if s.from == A then last = s.at end end
    sim:run(10); local a2 = sim:relog(A); sim:run(1)
    local refused, asks = record(a2, "refused"), record(a2, "stakeAsk")
    local mark = #sim.sent
    sim.bus.filter = function(from, _, _, m)
      if from == B and m.t == "SNP" then m.tbl.sk = 1000000 end
      return { m }
    end
    sim:run(last + 75 - sim:now()); sim:run(2)
    sim.bus.filter = nil
    eq(b.session.role, "host")
    eq(a2.session, nil); ok(#sent(sim, A, "STD", mark) >= 1, "Иван sent no STD")
    eq(refused[1], { tid, "stake" }); eq(asks, {})
  end)

  it("a crash into my staked seat keeps it for the running game only (I2)", function()
    local sim, a, b, _, tid = seatedAt(50000)
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B)
    local asks, refused = record(b, "stakeAsk"), record(b, "refused")
    sim:run(3)
    eq(b.session.mySeat, 2); eq(b.session.stake, 50000); eq(asks, { { tid, 50000 } })
    playOut(sim, a, b); sim:run(1)
    ok(a.session:gameOver(), "the match ended")
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false)
  end)

  it("a crash into my staked seat, accepted, keeps it after the game (I2)", function()
    local sim, a, b, _, tid = seatedAt(50000)
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B)
    local refused = record(b, "refused")
    sim:run(3)
    eq(b:acceptStake(), true); eq(b.env.db.stakeSat, { tid = tid, sk = 50000 }); eq(b:acceptStake(), nil)
    playOut(sim, a, b); sim:run(3)
    eq(b.session.mySeat, 2); eq(refused, {}); eq(a.session.seats[2], B)
  end)

  it("a crash into my staked seat with no game running stands me up at once (I2)", function()
    local sim, a, b = setup()
    local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    b:sit(tid, 2, 50000); sim:run(1); eq(a.session.status, "open")
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B)
    local asks, refused = record(b, "stakeAsk"), record(b, "refused")
    sim:run(3)
    eq(b.session, nil); eq(asks, {}); eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false)
    eq(b:acceptStake(), nil)
  end)

  it("a second click while my SIT is unanswered keeps its note (M1)", function()
    local sim, a, b = setup()
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    local refused = record(b, "refused")
    b:sit(tid, 2, 50000); b:sit(tid, 2); sim:run(2)
    eq(b.env.db.stakeSat, { tid = tid, sk = 50000 })
    eq(b.session and b.session.mySeat, 2); eq(a.session.seats[2], B); eq(refused, {})
  end)

  it("an INV with a stake for a game that takes none is dropped (M2)", function()
    local sim, _, b, c = setup()
    local invites = record(b, "invite")
    c:send("WHISPER", B, { v = 1, t = "INV", tid = P .. "#1", g = "santase", h = P, s = { P, false }, sk = 50000 }); sim:run(1)
    eq(invites, {})
    c:send("WHISPER", B, { v = 1, t = "INV", tid = P .. "#2", g = "ttt", h = P, s = { P, false }, sk = 50000 }); sim:run(1)
    eq(#invites, 1); eq(invites[1][1].stake, 50000)
  end)

  it("Session.lua keeps its limit", function()
    local n = 0
    for _ in io.lines("core/Session.lua") do n = n + 1 end
    ok(n < 540, "Session.lua " .. n)
  end)
end)
