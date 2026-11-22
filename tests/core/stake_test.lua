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
  -- One group for all: a staked Death Roll starts only so (Session:canStart "group").
  for _, env in pairs(sim.envs) do env.inGroup = function() return true end end
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
    for _, game in ipairs({ "holdem" }) do
      local tid, why = a:openTable{ game = game, access = "guild", turn = 45, stake = 50000 }
      eq(tid, nil); eq(why, "stake"); eq(a.session, nil)
    end
    local tid = fakeTBL(sim, c, "holdem", { P, false, false, false, false, false }, 50000)
    eq(b.lobby:get(tid), nil)
    -- The same table for fun is listed; a staked Death Roll opens.
    tid = fakeTBL(sim, c, "holdem", { P, false, false, false, false, false }, nil)
    ok(b.lobby:get(tid), "a fun holdem TBL is listed")
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
    eq(b.env.db.stakeSat, { tid = tid, sk = 50000, tn = 45 })
    local sit = sent(sim, B, "SIT"); eq(sit[#sit].msg.sk, 50000)
    -- A repeated click without the stake while seated: the snapshot again, my note and seat stay.
    local mark = #sim.sent
    b:sit(tid, 2); sim:run(1)
    eq(b.env.db.stakeSat, { tid = tid, sk = 50000, tn = 45 }); eq(b.session.mySeat, 2); eq(a.session.seats[2], B)
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
    -- The match runs: I go, but I give up no seat (no STD; the foul is noted: Task 7 fix round 4, C1).
    eq(#sent(sim, B, "STD", mark), 0); eq(b.session, nil)
    eq(refused, { { tid, "stake" } })
    eq(a.session.seats[2], B); eq(b.env.db.stakeSeen[tid .. "/" .. a.session.seq].foul, "forged")
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
    local mark = #sim.sent
    -- A bot has no ledger: its own sit refuses at once and sends nothing (F1 Task 5).
    local r, why = bot:sit(tid, 2)
    eq(r, nil); eq(why, "stake"); sim:run(1)
    eq(#sent(sim, name, "SIT", mark), 0); eq(#sent(sim, A, "SNO", mark), 0)
    -- A hand-sent SIT without sk still gets SNO "stake".
    bot:send("WHISPER", A, { v = 1, t = "SIT", tid = tid, seat = 2 }); sim:run(1)
    local sno = sent(sim, A, "SNO", mark)
    eq(#sno, 1); eq(sno[1].target, name); eq(sno[1].msg.why, "stake")
    eq(a.session.seats[2], false)
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

    -- A bot hosting a staked table that waits for a third player fills nobody in
    -- (the test engine is registered for this part only, removed even on a failure).
    ns.Engines.fillstake = FS
    local done, err = pcall(function()
      local host = bots.list[2]
      -- A bot has no ledger, so its client opens no staked table (F1 Task 5); the
      -- session is opened past that check to pin Bots:fill's own guard.
      eq({ host:openTable{ game = "fillstake", access = "guild", turn = 45, stake = 50000 } }, { nil, "stake" })
      local tid = ns.Session.open(host, { game = "fillstake", access = "guild", turn = 45, stake = 50000 }); sim:run(1)
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
    end)
    ns.Engines.fillstake = nil
    if not done then error(err, 0) end
  end)

  it("a note of another table written in this run accepts no stake here (C1)", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    b:sit(tid, 2, 50000); sim:run(1); eq(b.session.mySeat, 2)
    b:stand(); sim:run(1)
    local fun = c:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
    b:sit(fun, 2); sim:run(1); eq(b.session.tid, fun)
    b:stand(); sim:run(1)
    eq(b.env.db.stakeSat, nil) -- my stand cleared the note (fix round 2)
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
    eq(a.env.db.stakeSat, { tid = tid, sk = 50000, tn = 45 })
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
    eq(b:acceptStake(), true); eq(b.env.db.stakeSat, { tid = tid, sk = 50000, tn = 45 }); eq(b:acceptStake(), nil)
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
    eq(b.env.db.stakeSat, { tid = tid, sk = 50000, tn = 45 })
    eq(b.session and b.session.mySeat, 2); eq(a.session.seats[2], B); eq(refused, {})
  end)

  it("an INV with a stake for a game that takes none is dropped (M2)", function()
    local sim, _, b, c = setup()
    local invites = record(b, "invite")
    c:send("WHISPER", B, { v = 1, t = "INV", tid = P .. "#1", g = "holdem", h = P, s = { P, false, false, false, false, false }, sk = 50000 }); sim:run(1)
    eq(invites, {})
    c:send("WHISPER", B, { v = 1, t = "INV", tid = P .. "#2", g = "ttt", h = P, s = { P, false }, sk = 50000 }); sim:run(1)
    eq(#invites, 1); eq(invites[1][1].stake, 50000)
  end)

  it("positive control: a fun six-seat Holdem INV is taken", function()
    local sim, _, b, c = setup()
    local invites = record(b, "invite")
    c:send("WHISPER", B, { v = 1, t = "INV", tid = P .. "#1", g = "holdem", h = P, s = { P, false, false, false, false, false } }); sim:run(1)
    eq(#invites, 1); eq(invites[1][1].stake, nil)
  end)

  it("a watcher seated by the host without a SIT of mine is stood up (C-A)", function()
    local sim, a, _, c = setup()
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    c:watch(tid); sim:run(1); eq(c.session.role, "watcher"); eq(c.session.stake, 50000)
    local refused, asks = record(c, "refused"), record(c, "stakeAsk")
    local mark = #sim.sent
    a.session.watcherSet[P], a.session.watchers = nil, 0
    a.session:event(0, { k = "sit", seat = 2, name = P }); a.session:snapshotTo(P); sim:run(1)
    eq(c.session, nil); ok(#sent(sim, P, "STD", mark) >= 1, "no STD")
    eq(refused, { { tid, "stake" } }); eq(asks, {}); eq(a.session.seats[2], false)
  end)

  -- Мария sat at Иван's staked table and stood up; then she watched Петър's
  -- table and left it. Иван's modified client seats her again and pushes a snapshot.
  local function leftAndWatched(relog)
    local sim, a, b, c, tid = seatedAt(50000)
    b:stand(); sim:run(1)
    eq(b.env.db.stakeSat, nil)
    local u = c:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
    b:watch(u); sim:run(1); eq(b.session.tid, u)
    b:stand(); sim:run(1)
    if relog then b = sim:relog(B); sim:run(1) end
    local refused, asks = record(b, "refused"), record(b, "stakeAsk")
    local mark = #sim.sent
    a.session:event(0, { k = "sit", seat = 2, name = B }); a.session:snapshotTo(B); sim:run(1)
    return sim, a, b, tid, refused, asks, mark
  end

  it("a stand withdraws my note: a re-seat by the host stands me up (C-B)", function()
    local sim, a, b, tid, refused, asks, mark = leftAndWatched(false)
    eq(b.session, nil); ok(#sent(sim, B, "STD", mark) >= 1, "no STD")
    eq(refused, { { tid, "stake" } }); eq(asks, {}); eq(a.session.seats[2], false)
  end)

  it("a stand withdraws my note: after a relog a re-seat is never silent (C-B)", function()
    local sim, a, b, tid, refused, asks, mark = leftAndWatched(true)
    eq(b.session, nil); ok(#sent(sim, B, "STD", mark) >= 1, "no STD")
    eq(refused, { { tid, "stake" } }); eq(asks, {}); eq(a.session.seats[2], false)
  end)

  it("a refused SIT withdraws my note", function()
    local sim, a, b = setup()
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    b:sit(tid, 3, 50000); sim:run(1) -- no such seat: "taken"
    eq(b.env.db.stakeSat, nil); eq(b.session, nil)
  end)

  it("an asked seat is stood up at the next game's start, back to back with the last roll (I-A)", function()
    local sim, a, b = setup()
    local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, opt = { start = 100 }, stake = 50000 }
    sim:run(3); b:sit(tid, 2, 50000); sim:run(1)
    ok(a:startGame()); sim:run(1)
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B)
    local asks, refused = record(b, "stakeAsk"), record(b, "refused")
    local newGame = false
    b:on("session", function(s)
      if s and s.state and s.state.phase == "play" and #s.state.rolls == 0 and s.seq > 2 then newGame = true end
    end)
    sim:run(3)
    eq(b.session.mySeat, 2); eq(asks, { { tid, 50000 } })
    -- Иван's last roll and the next start reach Мария in one delivery.
    local held = {}
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then held[#held + 1] = m; return {} end
      return { m }
    end
    sim.nextRolls = { 1 }; ok(a:roll()); sim:run(0)
    ok(a.session:gameOver(), "the game ended"); sim:run(ns.Const.STAKE_BREAK); ok(a:startGame()); sim:run(0)
    sim.bus.filter = nil
    eq(#held, 2)
    for i = 1, #held do sim.bus:send(A, "WHISPER", B, held[i]) end
    sim:run(1)
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(newGame, false)
    eq(a.session.seats[2], false)
  end)

  it("a fresh login with a loaded note of another table is asked (m1)", function()
    local sim, _, b, _, tid = seatedAt(50000)
    sim.envs[B].db.stakeSat = { tid = "Петър Колев#1", sk = 100 }
    b = sim:relog(B)
    local asks = record(b, "stakeAsk")
    sim:run(3)
    eq(b.session.mySeat, 2); eq(b.session.stake, 50000); eq(asks, { { tid, 50000 } })
  end)

  it("a sit EV naming me that I never asked for stands me up before it counts (C-1)", function()
    local sim, a, _, c = setup()
    local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    c:watch(tid); sim:run(1)
    local refused, live = record(c, "refused"), false
    c:on("session", function(s) if s and s.status == "live" then live = true end end)
    local mark = #sim.sent
    a.session.watcherSet[P], a.session.watchers = nil, 0
    a.session:event(0, { k = "sit", seat = 2, name = P }); a.session:startIfFull(); sim:run(1)
    eq(c.session, nil); eq(#sent(sim, P, "STD", mark), 1); eq(refused, { { tid, "stake" } })
    eq(live, false); eq(a.session.seats[2], false)
  end)

  it("an asked seat goes before a rematch, back to back with the winning mark (I-1)", function()
    local sim, a, b, _, tid = seatedAt(50000)
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B); sim:run(3)
    eq(b.session.stakeAsk, true)
    -- One mark from the end of the match, on both clients.
    local near = { board = { 1, 1, 0, 2, 2, 0, 0, 0, 0 }, turn = 1, score = { 2, 0 }, round = 3, first = 1,
      phase = "play", draw = false, rematch = { false, false } }
    a.session.state, b.session.state = ns.Util.copy(near), ns.Util.copy(near)
    local refused, rematched = record(b, "refused"), false
    b:on("session", function(s) if s and s.state and s.state.score[1] == 0 and s.state.phase == "play" then rematched = true end end)
    ok(a:act{ k = "mark", c = 3 }); ok(a:act{ k = "rematch" }); a.session:play(2, { k = "rematch" })
    eq(a.session.state.phase, "play"); eq(a.session.state.score, { 0, 0 })
    sim:run(1)
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(rematched, false)
  end)

  it("an asked seat stands up at a snapshot that brings what it did not see (I-2)", function()
    local sim, a, b = setup()
    local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, opt = { start = 100 }, stake = 50000 }
    sim:run(3); b:sit(tid, 2, 50000); sim:run(1)
    ok(a:startGame()); sim:run(1)
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B); sim:run(3)
    eq(b.session.stakeAsk, true)
    local refused = record(b, "refused")
    -- Иван withholds his last roll from Мария and starts the next game: her SYN gets a snapshot of it.
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" and not (m.a and m.a.k == "start") then return {} end
      return { m }
    end
    sim.nextRolls = { 1 }; ok(a:roll()); sim:run(0)
    ok(a.session:gameOver(), "the game ended"); sim:run(ns.Const.STAKE_BREAK); ok(a:startGame()); sim:run(1)
    sim.bus.filter = nil
    sim:run(1)
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false)
  end)

  it("after a clean stand and a relog a re-seat into a running game is never kept (m-1)", function()
    local sim, a, b, _, tid = seatedAt(50000)
    b:stand(); sim:run(1)
    b = sim:relog(B); sim:run(1)
    local refused, asks = record(b, "refused"), record(b, "stakeAsk")
    a.session:event(0, { k = "sit", seat = 2, name = B }); a.session:startIfFull(); a.session:snapshotTo(B); sim:run(1)
    eq(b.session, nil); eq(asks, {}); eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false)
  end)

  -- A staked Death Roll of Иван; Мария crashed into her seat (asked), then Иван rolled once.
  local function askedAtDeathRoll()
    local sim, a, b = setup()
    local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, opt = { start = 100 }, stake = 50000 }
    sim:run(3); b:sit(tid, 2, 50000); sim:run(1)
    ok(a:startGame()); sim:run(1)
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B); sim:run(3)
    sim.nextRolls = { 50 }; ok(a:roll()); sim:run(1)
    eq(b.session.stakeAsk, true); eq(b.session.seq, a.session.seq); eq(#b.session.state.rolls, 1)
    return sim, a, b, tid
  end

  it("an asked seat keeps a snapshot of its own game and stands at one of another game at its own q (I-1)", function()
    local sim, a, b, tid = askedAtDeathRoll()
    local refused, fresh = record(b, "refused"), false
    b:on("session", function(s) if s and s.state and #s.state.rolls == 0 then fresh = true end end)
    -- The very game she holds, again: the question stays.
    a.session:snapshotTo(B); sim:run(1)
    eq(b.session.mySeat, 2); eq(b.session.stakeAsk, true); eq(refused, {})
    -- Another game at the same q, with no event between.
    local mark, q = #sim.sent, b.session.seq
    a.session.state = a.session:newGame(1)
    a.session:snapshotTo(B); sim:run(1)
    eq(sent(sim, A, "SNP", mark)[1].msg.q, q)
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(fresh, false)
    ok(#sent(sim, B, "STD", mark) >= 1, "Мария sent no STD"); eq(a.session.seats[2], false)
  end)

  it("an asked seat stands at a snapshot of another game that it asked for itself (I-1)", function()
    local sim, a, b, tid = askedAtDeathRoll()
    local refused, fresh = record(b, "refused"), false
    b:on("session", function(s) if s and s.state and #s.state.rolls == 0 then fresh = true end end)
    -- A TCK ahead of her makes her ask; the answer is another game at her own q.
    a.session.state = a.session:newGame(1)
    local mark = #sim.sent
    sim.bus:send(A, "WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq + 1 })
    sim:run(1)
    eq(#sent(sim, B, "SYN", mark), 1)
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(fresh, false); eq(a.session.seats[2], false)
  end)

  it("the game my client holds is counted, and an asked seat is kept for that one only (I-1)", function()
    local sim, a, b, _, tid = seatedAt(50000)
    local ga, gb = a.session.gameNo, b.session.gameNo -- local counts: hers took a snapshot and the start
    eq(ga, 1); eq(gb, 2)
    local near = { board = { 1, 1, 0, 2, 2, 0, 0, 0, 0 }, turn = 1, score = { 2, 0 }, round = 3, first = 1,
      phase = "play", draw = false, rematch = { false, false } }
    a.session.state, b.session.state = ns.Util.copy(near), ns.Util.copy(near)
    ok(a:act{ k = "mark", c = 3 }); ok(a:act{ k = "rematch" }); sim:run(1)
    eq(a.session.gameNo, ga); eq(b.session.gameNo, gb)
    ok(b:act{ k = "rematch" }); sim:run(1)
    eq(a.session.state.phase, "play"); eq(a.session.gameNo, ga + 1); eq(b.session.gameNo, gb + 1)
    a.session:snapshotTo(B); sim:run(1)
    eq(b.session.gameNo, gb + 2) -- a snapshot is another game for all she can tell
    -- Asked: the question names the game; a duplicate snapshot keeps it, another game under it stands her up.
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B); sim:run(3)
    local refused = record(b, "refused")
    eq(b.session.stakeAsk, true); eq(b.session.stakeGame, b.session.gameNo)
    a.session:snapshotTo(B); sim:run(1)
    eq(b.session.stakeGame, b.session.gameNo); eq(refused, {})
    b.session.gameNo = b.session.gameNo + 1; ns.Session.emit(b); sim:run(0)
    eq(b.session, nil); eq(refused, { { tid, "stake" } })
  end)

  it("a reload while asked does not bring the seat back (m-1)", function()
    local sim, a, b, tid = askedAtDeathRoll()
    b = sim:relog(B)
    local asks, refused = record(b, "stakeAsk"), record(b, "refused")
    sim:run(3)
    eq(b.session, nil); eq(asks, {}); eq(refused, { { tid, "stake" } }); eq(a.session.seats[2], false)
  end)

  -- Мария crashed into her seat of Иван's staked ttt match: asked.
  local function askedAtTTT()
    local sim, a, b, _, tid = seatedAt(50000)
    sim.envs[B].db.stakeSat = nil
    b = sim:relog(B); sim:run(3)
    eq(b.session.stakeAsk, true)
    local refused, seen = record(b, "refused"), { host = false }
    b:on("session", function(s) if s and s.role == "host" then seen.host = true end end)
    return sim, a, b, tid, refused, seen
  end

  it("an asked seat named in a handoff stands up instead of hosting, a SIT right behind (I-2)", function()
    local sim, a, b, tid, refused, seen = askedAtTTT()
    sim.bus:send(A, "WHISPER", B, { v = 1, t = "HND", tid = tid, e = a.session.epoch + 1, to = B, inv = {} })
    sim.bus:send(A, "WHISPER", B, { v = 1, t = "SIT", tid = tid, seat = 1, sk = 50000 })
    sim:run(1)
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(seen.host, false)
    eq(b.env.db.stakeSat, nil); eq(a.session.seats[2], false)
  end)

  it("an asked seat stands up instead of claiming a silent host's table, STD and SIT right behind (I-2)", function()
    local sim, _, b, tid, refused, seen = askedAtTTT()
    sim:offline(A)
    for _ = 1, 120 do
      if not b.session or b.session.role == "host" then break end
      sim:run(1)
    end
    sim:online(A)
    sim.bus:send(A, "WHISPER", B, { v = 1, t = "STD", tid = tid })
    sim.bus:send(A, "WHISPER", B, { v = 1, t = "SIT", tid = tid, seat = 1, sk = 50000 })
    sim:run(1)
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(seen.host, false); eq(b.env.db.stakeSat, nil)
  end)

  it("a sit EV naming me is applied while my own SIT note for the table stands (m-3)", function()
    local sim, a, _, c = setup()
    local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, stake = 50000 }; sim:run(3)
    c:watch(tid); sim:run(1)
    local refused = record(c, "refused")
    -- His SIT is on its way (the note is written); the host's sit EV reaches him before any snapshot.
    sim.bus.filter = function(from, _, _, m) return (from == P and m.t == "SIT") and {} or { m } end
    c:sit(tid, 2, 50000); sim:run(0)
    sim.bus.filter = nil
    eq(c.env.db.stakeSat, { tid = tid, sk = 50000, tn = 45, o = { start = 1000 } })
    a.session.watcherSet[P], a.session.watchers = nil, 0
    a.session:event(0, { k = "sit", seat = 2, name = P }); sim:run(1)
    eq(c.session.seats[2], P); eq(c.session.seq, a.session.seq); eq(refused, {})
  end)

  it("Session.lua keeps its limit", function()
    local n = 0
    for _ in io.lines("core/Session.lua") do n = n + 1 end
    ok(n < 540, "Session.lua " .. n)
  end)
end)
