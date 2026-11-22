Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, E, Stakes = ns.Const, ns.Engines.holdem, ns.Stakes

-- Stage F3, Task 5: the extension `stakes` at a cash table (core/StakesCash.lua).
local A, B, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local K, N6 = Play.MORE[1], Play.MORE[2]
local ALL = { A, B, M, G, K, N6 } -- the name of chair i, for the tables of this file
local SK = 1000 -- blinds 10: the big blind of 10 chips of one silver

-- The EV actions `name` was whispered after the first `from` messages of sim.sent
-- (copied from tests/core/holdem_table_test.lua).
local function evs(sim, name, from)
  local out = {}
  for i = from + 1, #sim.sent do
    local m = sim.sent[i]
    if m.target == name and m.msg.t == "EV" then out[#out + 1] = m.msg.a end
  end
  return out
end

-- `name`'s ACTs (of kind k; any when nil) go nowhere until the returned function is called
-- (the Табла tests' mute, for the ACTs of a cash table) -> that function, the count dropped.
local function mute(sim, name, k)
  local env, dropped, on = sim.envs[name], { n = 0 }, true
  local send = env.send
  env.send = function(channel, target, msg, done)
    local act = msg.t == "ACT" and msg.a
    if on and type(act) == "table" and (k == nil or act.k == k) then dropped.n = dropped.n + 1; return end
    return send(channel, target, msg, done)
  end
  return function() on = false end, dropped
end

-- A guild of the six names of ALL; Иван opens a staked Холдем (opt, default blinds 10; turn 30), the
-- names of `chairs` (chair numbers) sit in their chairs, Иван starts, and every chair c buys
-- buys[c] chips (default 1000; false: no buy) -> sim, cl, tid.
local function cash(chairs, opt, buys)
  local sim, cl = Play.guild(4, Play.MORE)
  for i, name in ipairs(ALL) do sim.envs[name].random = function(lo, hi) return (lo + i) % (hi + 1) end end
  opt = opt or { blinds = 10 }
  local sk = E.stakeOf(opt)
  local tid = assert(cl[A]:openTable{ game = "holdem", access = "guild", turn = 30, opt = opt, stake = sk })
  sim:run(3)
  for _, c in ipairs(chairs) do
    if c ~= 1 then cl[ALL[c]]:sit(tid, c, sk); sim:run(1) end
  end
  assert(cl[A]:startGame())
  sim:run(1)
  for _, c in ipairs(chairs) do
    local n = buys and buys[c]
    if n ~= false then assert(cl[ALL[c]]:act{ k = "buy", n = n or 1000 }); sim:run(1) end
  end
  return sim, cl, tid
end

-- One second at a time until a hand runs at host's table (an error after 30 s).
local function inHand(sim, host)
  for _ = 1, 30 do
    if E.inHand(host.session.state) then return end
    sim:run(1)
  end
  error("no hand begins")
end

-- The seat on turn moves (Play.step) until `seat` is on turn at host's table.
local function untilTurn(sim, host, seat)
  for _ = 1, 200 do
    if host.session.state.turn == seat then return end
    Play.step(sim, host)
  end
  error("seat " .. seat .. " never comes on turn")
end

-- host's snapshot for `to` as the message of `from` (default: the host) at epoch + e,
-- with `names` (seat -> name) put over its seats and mutate(st) run on its state
-- (tests/core/stakes_f2_final_test.lua's renamedSnapshot, with the state).
local function snapshot(host, to, names, from, e, mutate)
  local hs = host.session
  local tbl = hs:record()
  for seat, name in pairs(names or {}) do tbl.s[seat] = name end
  tbl.h, tbl.e = from or tbl.h, hs.epoch + (e or 0)
  local st = ns.Util.copy(hs:snapshotFor(to))
  if mutate then mutate(st) end
  return ns.Session.message("SNP", { tid = hs.tid, e = tbl.e, q = hs.seq, tbl = tbl, st = st,
    left = hs:left(), inv = hs:invitedList(), fr = hs:hook("snap") })
end

-- A session of the engine `game` for Stakes.fairFoul (tests/core/stakes_cards_test.lua's fakeSession).
local function fakeSession(o)
  return { client = { env = { me = o.me } }, mySeat = o.seat, seats = o.seats, game = o.game, stake = o.stake,
    engine = function(self) return ns.Games.engine(self.game) end }
end

describe("stakes at a cash table", function()
  it("a stand at a cash table is no forfeit", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    cl[G]:sit(tid, 4, SK); sim:run(1) -- a newcomer: the running hand is the game it takes up
    local forfeits = 0
    for _, c in pairs(cl) do c:on("forfeit", function() forfeits = forfeits + 1 end) end
    Play.hand(sim, host)
    ok(not E.inHand(host.session.state), "between hands")
    cl[M]:stand(); sim:run(1)
    eq(host.session.seats[3], false)
    eq(forfeits, 0)
    eq(cl[M].env.db.stakeLeft, nil)
    eq(#Play.entries(sim, nil, "R"), 0)
    for _, name in ipairs({ A, B, G }) do eq(cl[name].session.stakeRoster, nil, name) end
    -- In a hand too: Гошо buys, is dealt in and stands.
    ok(cl[G]:act{ k = "buy", n = 1000 }); sim:run(1)
    inHand(sim, host)
    ok(ns.Util.contains(E.players(host.session.state), 4), "Гошо is dealt in")
    cl[G]:stand(); sim:run(1)
    eq({ forfeits, cl[G].env.db.stakeLeft, #Play.entries(sim, nil, "R") }, { 0, nil, 0 })
  end)

  it("my own sit into a running game starts clean", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    cl[G]:sit(tid, 4, SK); sim:run(1)
    eq(cl[G].session.mySeat, 4)
    eq(cl[G].session.stakeFoul, nil)
    ok(cl[G]:act{ k = "buy", n = 1000 }); sim:run(1)
    eq(host.session.state.seats[4].bought, 1000)
    Play.hand(sim, host) -- the hand I sat into
    inHand(sim, host)
    ok(ns.Util.contains(E.players(host.session.state), 4), "dealt in")
    Play.hand(sim, host) -- a hand I play
    eq(cl[G].session.stakeFoul, nil)
    for _, name in ipairs({ A, B, M }) do eq(cl[name].session.stakeFoul, nil, name) end
  end)

  it("a watcher that sits starts clean", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    cl[G]:watch(tid); sim:run(1)
    eq(cl[G].session.role, "watcher")
    Play.hand(sim, host)
    inHand(sim, host)
    cl[G]:sit(tid, 4, SK); sim:run(1)
    eq(cl[G].session.mySeat, 4)
    eq(cl[G].session.stakeFoul, nil)
  end)

  it("a relog into my seat is unseen", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    Play.step(sim, host)
    local m = sim:relog(M); sim:run(3)
    eq(m.session.mySeat, 3)
    eq(m.session.stakeFoul, "unseen")
    for _, name in ipairs({ A, B }) do eq(cl[name].session.stakeFoul, nil, name) end
  end)

  it("a relog that clicks its own table before the host's snapshot is unseen, not forged (task 5 review, m3)", function()
    for _, kind in ipairs({ "watch", "sit" }) do
      local sim, cl, tid = cash({ 1, 2, 3 })
      local host = cl[A]
      inHand(sim, host)
      Play.hand(sim, host)
      sim.bus.filter = function(from, to, _, m) -- the host's snapshot for my login is lost
        if from == A and to == M and m.t == "SNP" then return {} end
        return { m }
      end
      local m = sim:relog(M); sim:run(3)
      sim.bus.filter = nil
      ok(m.session == nil and m.lobby:get(tid), "no table yet, but the lobby lists it")
      if kind == "watch" then m:watch(tid) else m:sit(tid, 5, SK) end
      sim:run(1) -- the host's "already here" snapshot
      eq(m.session.mySeat, 3, kind)
      eq(m.session.stakeFoul, "unseen", kind)
    end
    -- A newcomer's second click before the answer is still his own sit.
    local sim, cl, tid = cash({ 1, 2, 3 })
    inHand(sim, cl[A])
    cl[G]:sit(tid, 4, SK); cl[G]:sit(tid, 4, SK); sim:run(1)
    eq({ cl[G].session.mySeat, cl[G].session.stakeFoul }, { 4, nil })
  end)

  it("a snapshot of my very state that renames a seat is forged from my host, unseen from a new one", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    Play.step(sim, host)
    eq(cl[B].session.cashNames, { A, B, M })
    -- My very state under the names I hold: nothing.
    cl[B]:receive("WHISPER", A, snapshot(host, B)); sim:run(0)
    eq(cl[B].session.stakeFoul, nil)
    -- From my own host, a seat under another name: forged; my name for it stays.
    cl[B]:receive("WHISPER", A, snapshot(host, B, { [3] = G })); sim:run(0)
    eq(cl[B].session.seats[3], G)
    eq(cl[B].session.stakeFoul, "forged")
    eq(cl[B].session.cashNames[3], M)
    -- From a host new to me: a question.
    sim, cl = cash({ 1, 2, 3 })
    host = cl[A]
    inHand(sim, host)
    Play.step(sim, host)
    cl[B]:receive("WHISPER", M, snapshot(host, B, { [3] = G }, M, 1)); sim:run(0)
    eq(cl[B].session.host, M)
    eq(cl[B].session.stakeFoul, "unseen")
    eq(cl[B].session.cashNames[3], M)
  end)

  it("a snapshot with other blinds or another rebuy mode in its state is forged", function()
    local cases = {
      function(st) st.bb = 20 end,
      function(st) st.betting = "pl" end,
      function(st) st.cash.rebuy = "top" end,
      function(st) st.cash = nil end,
    }
    for i, mutate in ipairs(cases) do
      local sim, cl = cash({ 1, 2, 3 })
      local host = cl[A]
      inHand(sim, host)
      Play.step(sim, host)
      cl[B].session.asked = true -- as if I asked: the snapshot alone would be a question
      cl[B]:receive("WHISPER", A, snapshot(host, B, nil, nil, nil, mutate)); sim:run(0)
      eq(cl[B].session.stakeFoul, "forged", "case " .. i)
    end
    -- My very options in the state: a question only.
    local sim, cl = cash({ 1, 2, 3 })
    inHand(sim, cl[A])
    Play.step(sim, cl[A])
    cl[B].session.asked = true
    cl[B]:receive("WHISPER", A, snapshot(cl[A], B, nil, nil, nil, function(st) st.seats[1].chips = st.seats[1].chips + 1 end)); sim:run(0)
    eq(cl[B].session.stakeFoul, "unseen")
  end)

  it("my seat with chips I did not buy at my own sit is forged", function()
    local cases = {
      function(st) st.seats[4].chips, st.seats[4].bought, st.seats[4].out = 500, 500, false end,
      function(st) st.seats[4].chips = 500 end,
      function(st) st.cash.took[4] = { [1] = 50 } end,
      function(st) st.seats[4].cleared = 50 end, -- a forged `cleared` (task 5 review, m1)
    }
    for i, mutate in ipairs(cases) do
      local sim, cl, tid = cash({ 1, 2, 3 })
      inHand(sim, cl[A])
      sim.bus.filter = function(from, to, _, m)
        if from == A and to == G and m.t == "SNP" and type(m.st) == "table" then mutate(m.st) end
        return { m }
      end
      cl[G]:sit(tid, 4, SK); sim:run(1)
      sim.bus.filter = nil
      eq(cl[G].session.mySeat, 4)
      eq(cl[G].session.stakeFoul, "forged", "case " .. i)
    end
  end)

  it("my sit onto a taken chair is clean (H1)", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    ok(ns.Util.contains(E.players(host.session.state), 3), "Мария is dealt in")
    cl[M]:stand(true); sim:run(1) -- at once, mid-hand (core/CashOut.lua)
    ok(E.inHand(host.session.state) and host.session.state.seats[3].leaving, "her chair is still hers")
    cl[G]:sit(tid, 3, SK); sim:run(1)
    eq(cl[G].session.mySeat, 3)
    local st = cl[G].session.state
    eq({ st.seats[3].who, st.seats[3].takenWho }, { M, G })
    eq(cl[G].session.stakeFoul, nil)
    Play.hand(sim, host)
    eq(cl[G].session.state.seats[3].who, G)
    eq(cl[G].session.stakeFoul, nil)
    ok(cl[G]:act{ k = "buy", n = 1000 }); sim:run(1)
    eq(cl[G].session.stakeFoul, nil)
  end)

  it("a re-sit while my leaving record is in the hand is not clean (task 5 review, C1)", function()
    for _, forge in ipairs({ false, true }) do
      local sim, cl, tid = cash({ 1, 2, 3, 4 })
      local host = cl[A]
      inHand(sim, host)
      Play.hand(sim, host)
      inHand(sim, host)
      local hst = host.session.state
      ok(ns.Util.contains(E.players(hst), 4) and hst.seats[4].bought == 1000, "Гошо is dealt in with 1000 bought")
      cl[G]:stand(true); sim:run(1) -- at once, mid-hand (core/CashOut.lua)
      ok(E.inHand(host.session.state) and host.session.state.seats[4].leaving, "his record still leaves")
      if forge then -- the host adds 900 to the matrix of his old record
        sim.bus.filter = function(from, to, _, m)
          if from == A and to == G and m.t == "SNP" and type(m.st) == "table" then
            m.st.cash.took[1] = m.st.cash.took[1] or {}
            m.st.cash.took[1][4] = (m.st.cash.took[1][4] or 0) + 900
          end
          return { m }
        end
      end
      cl[G]:sit(tid, 5, SK); sim:run(1)
      sim.bus.filter = nil
      local gs, why = cl[G].session, forge and "forged matrix" or "honest"
      eq(gs.mySeat, 5)
      eq({ gs.state.seats[4].who, gs.state.seats[4].leaving }, { G, true })
      eq(gs.stakeFoul, "unseen", why)
      Play.hand(sim, host)
      eq(gs.state.cash.outs[#gs.state.cash.outs].who, G) -- his old record settled from the snapshot's matrix
      eq(gs.stakeFoul, "unseen", why)
    end
  end)

  it("a seated player's repeated SIT is no foul (task 5 review, I1)", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    Play.hand(sim, host)
    eq(cl[B].session.stakeFoul, nil)
    cl[B]:sit(tid, 5, SK); sim:run(1) -- a click on a free chair: the host's "already here" snapshot
    eq({ cl[B].session.mySeat, host.session.seats[5] }, { 2, false })
    eq(cl[B].session.stakeFoul, nil)
  end)

  it("cashout, stand, a sit I missed, an asked snapshot: unseen, not forged (H2)", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    Play.hand(sim, host)
    ok(cl[M]:act{ k = "cashout" }); sim:run(1)
    eq(host.session.state.seats[3].bought, 0)
    cl[M]:stand(); sim:run(1)
    eq(cl[B].session.cashNames[3], nil) -- a stand drops the seat
    sim.bus.filter = function(_, to, _, m)
      if to == B and m.t == "EV" and type(m.a) == "table" and m.a.k == "sit" then return {} end
      return { m }
    end
    cl[G]:sit(tid, 3, SK); sim:run(1)
    sim.bus.filter = nil
    eq(cl[B].session.seats[3], false)
    cl[B].session:requestSync(); sim:run(1)
    eq(cl[B].session.seats[3], G)
    eq(cl[B].session.stakeFoul, "unseen")
  end)

  it("a stand and a sit both missed, then my host's snapshot of my very state: unseen, never forged", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    Play.hand(sim, host)
    sim.bus.filter = function(_, to, _, m)
      if to == B and m.t == "EV" and type(m.a) == "table" and (m.a.k == "sit" or m.a.k == "stand") then return {} end
      return { m }
    end
    cl[M]:stand(); sim:run(1)
    cl[G]:sit(tid, 3, SK); sim:run(1)
    sim.bus.filter = nil
    eq(cl[B].session.seats[3], M)
    cl[B].session:requestSync(); sim:run(1)
    eq({ cl[B].session.seats[3], cl[B].session.stakeFoul }, { G, "unseen" })
    eq(cl[B].session.cashNames[3], G) -- the names of the state I took up
    host.session:snapshotTo(B); sim:run(0)
    eq(cl[B].session.stakeFoul, "unseen")
  end)

  it("a buy during my turn leaves my clock; the host's timeout of my silent turn is no foul (H4)", function()
    -- Pins the clock restore: Борис sends no move (mute drops only his own timeout ACT).
    -- A move he sent and lost before the deadline is still forged by F1's rule (core/Member.lua).
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    untilTurn(sim, host, 2)
    local s = cl[B].session
    local t, at = s.stakeTurn, s.turnAt
    ok(t and t.seat == 2 and at, "my clock runs")
    local unmute = mute(sim, B)
    sim:run(8)
    cl[G]:sit(tid, 4, SK); sim:run(1)
    ok(cl[G]:act{ k = "buy", n = 1000 }); sim:run(1)
    eq(host.session.state.seats[4].bought, 1000)
    ok(s.stakeTurn == t, "my turn's clock is the one it was"); eq(s.turnAt, at)
    for _ = 1, 40 do
      if host.session.state.turn ~= 2 then break end
      sim:run(1)
    end
    unmute()
    ok(host.session.state.turn ~= 2, "the host timed my seat out")
    eq(s.stakeFoul, nil); eq(s.fair.foul, nil)
  end)

  it("a Холдем snapshot is not read as a Морски шах board", function()
    for _, newHost in ipairs({ false, true }) do
      local sim, cl, tid = cash({ 1, 6 })
      local host = cl[A]
      inHand(sim, host)
      cl[G]:sit(tid, 3, SK); sim:run(1) -- seated, no chips: the hand stays heads-up
      for _ = 1, 30 do
        if #host.session.state.board == 3 and host.session.state.turn then break end
        Play.step(sim, host)
      end
      local s = cl[N6].session
      eq(s.state.board, { 6, 7, 8 })
      eq(s.stakeFoul, nil)
      if newHost then
        -- A sit I miss keeps the turn; then a seated player calls itself the host with the table's state.
        sim.bus.filter = function(_, to, _, m)
          if to == N6 and m.t == "EV" and type(m.a) == "table" and m.a.k == "sit" then return {} end
          return { m }
        end
        cl[K]:sit(tid, 4, SK); sim:run(1)
        sim.bus.filter = nil
        cl[N6]:receive("WHISPER", G, snapshot(host, N6, nil, G, 1)); sim:run(0)
        eq(s.host, G)
      else
        sim.bus.filter = function(_, to, _, m) return (to == N6 and m.t == "EV") and {} or { m } end
        Play.step(sim, host)
        sim.bus.filter = nil
        s:requestSync(); sim:run(1)
      end
      eq(s.stakeFoul, "unseen", newHost and "a new host" or "my host")
    end
  end)

  it("no break between cash games", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    Play.hand(sim, host)
    ok(ns.Cash.close(host)); sim:run(1)
    eq(host.session.state.phase, "closed")
    for _ = 1, 30 do
      if host.session.book.published then break end
      sim:run(1)
    end
    ok(host.session.book.published, "the keys are out")
    eq(ns.Stakes.gap(host.session), 0)
    eq(host.session:canStart(), true)
    -- A seated player silent for SILENT_AFTER holds no start either (the rule of an `again` match).
    local heard = host.session.lastHeard[M]
    host.session.lastHeard[M] = sim:now() - C.SILENT_AFTER - 1
    local wait, silent = Stakes.held(host.session)
    ok(wait <= 0 and silent == nil, "no hold")
    host.session.lastHeard[M] = heard
    ok(host:startGame()); sim:run(1)
    for _, name in ipairs({ B, M }) do eq(cl[name].session.stakeFoul, nil, name) end
    -- A start one second after the close, by a host that does not wait for the keys: no foul of the break.
    sim, cl = cash({ 1, 2, 3 })
    host = cl[A]
    inHand(sim, host)
    Play.hand(sim, host)
    ok(ns.Cash.close(host)); sim:run(1)
    eq(host.session.state.phase, "closed")
    eq(Stakes.badStart(cl[B].session), nil); ok(Stakes.held(cl[B].session) <= 0, "no break on my clock")
    host.session:event(0, { k = "start", first = 1 }); sim:run(1)
    eq(cl[B].session.state.phase, "idle")
    for _, name in ipairs({ B, M }) do eq(cl[name].session.stakeFoul, nil, name) end
  end)

  it("a buy leaves the turn clock alone, and a second buy starts a hand", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    inHand(sim, host)
    untilTurn(sim, host, 2)
    sim:run(5)
    local deadline = host.session.deadline
    cl[G]:sit(tid, 4, SK); sim:run(1)
    ok(cl[G]:act{ k = "buy", n = 1000 }); sim:run(0)
    eq(host.session.deadline, deadline)
    -- One seat with chips: no hand; the second buy deals one.
    sim, cl = cash({ 1, 2 }, nil, { [2] = false })
    host = cl[A]
    sim:run(10)
    eq(host.session.state.hand, 0)
    local mark = #sim.sent
    ok(cl[B]:act{ k = "buy", n = 1000 }); sim:run(E.IDLE_DELAY + 1)
    local kinds = {}
    for _, a in ipairs(evs(sim, B, mark)) do kinds[#kinds + 1] = a.k end
    eq({ kinds[1], kinds[2] }, { "buy", "hand" })
  end)

  it("a void and a second void of one dealer are no foul at a cash table; a hand closed bad is deal", function()
    local s = fakeSession{ me = A, seat = 1, seats = { A, B, M }, game = "holdem", stake = SK }
    eq(Stakes.fairFoul(s, { verdict = "void", dealer = B }), nil)
    s.fairVoids = { [B] = 1 }
    eq(Stakes.fairFoul(s, { verdict = "void", dealer = B }), nil)
    s.fairVoids, s.fairLapses = { [B] = 2 }, { [B] = 1 }
    eq(Stakes.fairFoul(s, { verdict = "void", dealer = B }), nil)
    eq(Stakes.fairFoul(s, { verdict = "void", dealer = A }), nil)
    eq(Stakes.fairFoul(s, { verdict = "bad", why = "nodeal", dealer = B }), "deal")
    eq(Stakes.fairFoul(s, { verdict = "bad", why = "deal", dealer = A }), "deal")
    eq(Stakes.fairFoul(s, { verdict = "bad", why = "noreveal", dealer = A }), "deal")
    eq(Stakes.fairFoul(s, { verdict = "ok" }), nil); eq(Stakes.fairFoul(s, { verdict = "unseen" }), nil)
    -- At the table: a street without its faces closes the hand bad.
    local sim, cl = cash({ 1, 2 })
    local host = cl[A]
    inHand(sim, host)
    for _ = 1, 20 do
      if host.session.state.phase == "bet" then break end
      sim:run(1)
    end
    eq(host.session.fair.d, 1) -- the host deals
    for _ = 1, 2 do
      local seat = host.session.state.turn
      local a = host.session.state.bet > host.session.state.p[seat].bet and "call" or "check"
      ok(cl[ALL[seat]]:act{ k = a }); sim:run(1)
    end
    local hs = host.session
    eq(hs.state.phase, "street")
    ok(hs.stepTimer, "the dealer's step is armed")
    hs.stepTimer.cancel(); hs.stepTimer = nil
    hs:play(0, { k = "street", cards = {} }); sim:run(1)
    eq(cl[B].session.fair.foul, "deal")
    ok(cl[ALL[hs.state.turn]]:act{ k = "fold" }); sim:run(2)
    eq(cl[B].session.fairLast.verdict, "bad")
    eq(cl[B].session.stakeFoul, "deal")
  end)

  it("a buy in my name that I did not send is forged", function()
    local sim, cl = cash({ 1, 2, 3 }, nil, { [3] = false })
    local host = cl[A]
    sim:run(1)
    eq(cl[M].session.stakeFoul, nil)
    host.session:play(3, { k = "buy", n = 1000 }); sim:run(1)
    eq(host.session.state.seats[3].bought, 1000)
    eq(cl[M].session.stakeFoul, "forged")
    eq(cl[B].session.stakeFoul, nil)
  end)

  it("the matrix of a snapshot keeps its seat numbers on the wire (Task 2 review)", function()
    local sim, cl = cash({ 1, 6 })
    local host = cl[A]
    for _ = 1, 4 do
      inHand(sim, host)
      Play.hand(sim, host)
      if next(host.session.state.cash.took) then break end
    end
    local took = host.session.state.cash.took
    ok(next(took), "a hand moved chips")
    local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
    local m = snapshot(host, B)
    local back = wire:unpack(wire:pack(m))
    eq(back, m)
    for w, row in pairs(back.st.cash.took) do
      eq(type(w), "number")
      for j in pairs(row) do eq(type(j), "number") end
    end
    eq(back.st.cash.took, took)
  end)
end)
