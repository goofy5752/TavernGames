local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, E, U = ns.Const, ns.Engines.holdem, ns.Util

-- Stage F3, the fix wave after the final review (Ruling F3-F): I1 (a settlement that moved
-- nothing writes nothing), I2 (no late key while the lobby still seats me), and the code Minors.
local A, B, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local K, N6 = Play.MORE[1], Play.MORE[2]
local ALL = { A, B, M, G, K, N6 } -- the name of chair i
local SK = 1000 -- blinds 10: the big blind of 10 chips of one silver
local W = "Гледач Гледачев"

-- A guild of the six names of ALL; Иван opens a staked Холдем (blinds 10, turn 30), the
-- names of `chairs` sit in their chairs, Иван starts, and every chair c buys buys[c]
-- chips (default 1000; false: no buy) -> sim, cl, tid.
local function cash(chairs, buys)
  local sim, cl = Play.guild(4, Play.MORE)
  for i, name in ipairs(ALL) do sim.envs[name].random = function(lo, hi) return (lo + i) % (hi + 1) end end
  local tid = assert(cl[A]:openTable{ game = "holdem", access = "guild", turn = 30, opt = { blinds = 10 }, stake = SK })
  sim:run(3)
  for _, c in ipairs(chairs) do
    if c ~= 1 then cl[ALL[c]]:sit(tid, c, SK); sim:run(1) end
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

-- The hand that runs at host's table (the next one when none runs) played out, every seat on
-- turn checking or calling from its own client.
local function calm(sim, host)
  inHand(sim, host)
  local hs = host.session
  local hand = hs.state.hand
  for _ = 1, 300 do
    local st = hs.state
    if not (E.inHand(st) and st.hand == hand) then return end
    local c = st.phase == "bet" and st.turn and sim.clients[hs.seats[st.turn]]
    if c then c:act{ k = st.bet > st.p[st.turn].bet and "call" or "check" } end
    sim:run(1)
  end
  error("the hand did not end")
end

-- Every client at the table holds the matrix `took` (seat -> seat -> chips).
local function setTook(cl, took)
  for _, c in pairs(cl) do
    local st = c.session and c.session.state
    if st and st.cash then st.cash.took = U.copy(took) end
  end
end

-- How many keys t has.
local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- The host's events with a.k == k from sim.sent[mark + 1] on, each once (by q).
local function evs(sim, from, k, mark)
  local seen, n = {}, 0
  for i = (mark or 0) + 1, #sim.sent do
    local m = sim.sent[i]
    if m.from == from and m.msg.t == "EV" and not seen[m.msg.q] and m.msg.a.k == k then seen[m.msg.q] = true; n = n + 1 end
  end
  return n
end

-- What the table wrote for good since `mark`: the S entries on GUILD, and on client w its notes,
-- waiting notes, late-key registrations and timers armed.
local function written(sim, w, mark)
  local S = 0
  for i = mark + 1, #sim.sent do
    local m = sim.sent[i]
    if m.channel == "GUILD" and m.msg.t == "LEV" then
      for _, e in ipairs(m.msg.ev or {}) do if e.k == "S" then S = S + 1 end end
    end
  end
  return { S = S, notes = count(w.env.db.stakeSeen), waits = count(w.cashWaits), late = count(w.cashLate), finals = count(w.stakes.finals) }
end

describe("F3-F I1: a settlement that moved nothing writes nothing", function()
  -- Иван hosts, Петър sits; neither has bought (no hand can run); a watcher looks on -> sim, cl, tid, the watcher.
  local function lonely()
    local sim, cl, tid = cash({ 1, 2 }, { [1] = false, [2] = false })
    local w = sim:add(W); sim:run(1); sim:settle()
    w:watch(tid); sim:run(1)
    eq(cl[A].session.watchers, 1)
    return sim, cl, tid, w
  end

  it("200 rounds of buy and cashout from a seat no hand dealt in: refused, nothing written", function()
    local sim, cl, tid, w = lonely()
    cl[G]:sit(tid, 4, SK); sim:run(1)
    local mark = #sim.sent
    for _ = 1, 200 do
      local s = cl[G].session
      if s.state.seats[4].bought == 0 then ok(cl[G]:act{ k = "buy", n = 400 }) end
      sim:run(1)
      eq({ cl[G]:act{ k = "cashout" } }, { nil, "early" })
      ns.Member.sendAct(s, { k = "cashout" }) -- a modified client sends it anyway: the host's engine refuses
      sim:run(1)
    end
    eq({ evs(sim, A, "buy", mark), evs(sim, A, "cashout", mark) }, { 1, 0 })
    eq(cl[A].session.state.cash.outN, 0)
    eq(written(sim, w, mark), { S = 0, notes = 0, waits = 0, late = 0, finals = 0 })
    eq(written(sim, cl[A], mark), { S = 0, notes = 0, waits = 0, late = 0, finals = 0 })
  end)

  it("200 rounds of sit, buy and stand: every stand settles an empty record; no S, no note, no timer", function()
    local sim, cl, tid, w = lonely()
    local outs, mark = 0, #sim.sent
    w:on("cashout", function(v) outs = outs + 1; eq({ v.name, v.pairs, v.chips, v.bought }, { G, {}, 400, 400 }) end)
    for _ = 1, 200 do
      cl[G]:sit(tid, 4, SK, 400); sim:run(2)
      eq(cl[A].session.state.seats[4].bought, 400)
      cl[G]:stand(); sim:run(1)
      eq(cl[G].session, nil)
    end
    eq({ outs, cl[A].session.state.cash.outN }, { 200, 200 }) -- the engine settled each; the table still shows them
    for _, c in ipairs({ w, cl[A], cl[G] }) do
      eq(written(sim, c, mark), { S = 0, notes = 0, waits = 0, late = 0, finals = 0 }, c.env.me)
    end
  end)

  it("the close with a seat no hand dealt in: its empty record writes nothing, the others' do", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local w = sim:add(W); sim:run(1); sim:settle()
    w:watch(tid); sim:run(1)
    calm(sim, cl[A])
    cl[G]:sit(tid, 4, SK, 400); sim:run(2)
    for _ = 1, 3 do if not E.inHand(cl[A].session.state) then break end; calm(sim, cl[A]) end
    ok(cl[A].session.state.seats[4].fresh, "Гошо bought and was dealt no hand")
    setTook(cl, { [1] = { [2] = 20 } }) -- Петър owes Иван 20 chips
    local mark = #sim.sent
    assert(ns.Cash.close(cl[A])); sim:run(C.BOOK_WAIT + 5)
    local S = Play.entries(sim, A, "S")
    local who = {}
    for _, e in ipairs(S) do who[e.f] = true end
    eq(who, { [A] = true, [B] = true, [M] = true }) -- none for Гошо
    eq(written(sim, w, mark).S, 3)
    eq(count(cl[G].env.db.stakeSeen), 1) -- his one note of the event: the others' records, no pair of his
  end)

  it("a final note's 24 h timer is cancelled", function()
    local sim, cl = cash({ 1, 2, 3 })
    calm(sim, cl[A])
    setTook(cl, { [1] = { [2] = 20 } })
    assert(ns.Cash.close(cl[A])); sim:run(C.BOOK_WAIT + C.STAKE_OWE_WAIT + 30)
    eq(count(cl[B].stakes.finals), 0)
    local far = 0
    for _, t in ipairs(sim.timers) do
      if t.env == cl[B].env and not t.cancelled and t.due - sim.clock > C.CASH_BOOK_WAIT - 3600 then far = far + 1 end
    end
    eq(far, 0, "a 24 h timer of a final note still armed")
  end)
end)

-- Every KEY message of the sim from sim.sent[mark + 1] on -> {{from, channel, m}, ...}.
local function keys(sim, mark)
  local out = {}
  for i = (mark or 0) + 1, #sim.sent do
    local m = sim.sent[i]
    if m.msg.t == "KEY" then out[#out + 1] = { m.from, m.channel, m.msg.m } end
  end
  return out
end

describe("F3-F I2: no late key while the lobby still seats me", function()
  -- Heads-up, a hand runs; Петър relogs inside it and the host's snapshot never reaches him
  -- -> sim, cl, the mark before his relog, the key his running hand is committed to.
  local function relogged()
    local sim, cl = cash({ 1, 2 })
    calm(sim, cl[A])
    inHand(sim, cl[A])
    for _ = 1, 30 do if cl[A].session.state.phase == "bet" then break end; sim:run(1) end
    eq(cl[A].session.state.phase, "bet")
    local kept = sim.envs[B].db.bookKeep
    ok(kept and kept.sk and ns.Book.isKey(kept.key), "Петър's kept key of the staked table")
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "SNP" then return {} end
      return { m }
    end
    local mark = #sim.sent
    cl[B] = sim:relog(B)
    return sim, cl, mark, kept.key
  end

  it("a relog inside a hand with the snapshot lost: no key goes while the host still seats me", function()
    local sim, cl, mark = relogged()
    local seated = 0
    for _ = 1, 4 * C.LEDGER_ADOPT_WAIT + 10 do -- the first check at 30 s and three more
      sim:run(1)
      if cl[A].session and cl[A].session.seats[2] == B then
        seated = seated + 1
        eq(keys(sim, mark), {}, "a live key on GUILD at " .. sim.clock)
      end
    end
    ok(seated > C.LEDGER_ADOPT_WAIT + 5, "the host seated me past the first check: " .. seated .. " s")
    eq(cl[B].session, nil) -- no snapshot ever came
    ok(cl[B].lobby:get(cl[A].session.tid), "the lobby lists the table")
  end)

  -- A client that runs is never stood up as offline (its guild messages are heard): his link drops.
  it("... and once the host has stood me up, the check after my next login sends it: once", function()
    local sim, cl, mark, key = relogged()
    local tid = cl[A].session.tid
    sim:run(C.LEDGER_ADOPT_WAIT + 5)
    eq(keys(sim, mark), {})
    sim:offline(B); sim.envs[B].dead = true
    for _ = 1, C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER + 60 do
      if not (cl[A].session and cl[A].session.seats[2] == B) then break end
      sim:run(1)
      if cl[A].session and cl[A].session.seats[2] == B then eq(keys(sim, mark), {}, "a live key on GUILD at " .. sim.clock) end
    end
    ok(not (cl[A].session and cl[A].session.seats[2] == B), "the host stood Петър up")
    sim.bus.filter = nil
    eq(keys(sim, mark), {})
    cl[B] = sim:relog(B)
    sim:run(2 * C.LEDGER_ADOPT_WAIT + 5)
    eq(keys(sim, mark), { { B, "GUILD", key } })
    local rec = cl[B].lobby:get(tid)
    ok(not rec or not U.contains(rec.seats, B), "the lobby seats me no more")
    sim:run(10 * C.LEDGER_ADOPT_WAIT)
    eq(#keys(sim, mark), 1) -- no check runs on after the send
  end)

  it("the checks stop with the 24 h window: the kept key is given up, nothing is sent", function()
    local sim, cl, mark = relogged()
    sim:run(C.LEDGER_ADOPT_WAIT + 5)
    local db = sim.envs[B].db
    ok(type(db.bookKeep.late) == "number", "the first check stamped the window")
    db.bookKeep.late = db.bookKeep.late - C.CASH_BOOK_WAIT
    sim:run(C.LEDGER_ADOPT_WAIT + 5)
    eq(db.bookKeep, nil)
    sim.bus.filter = nil
    sim:run(C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER + 120)
    eq(keys(sim, mark), {})
  end)
end)
