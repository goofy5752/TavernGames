local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, E, U = ns.Const, ns.Engines.holdem, ns.Util

-- Stage F3, Task 8: the buy-in follows my sit; „Стани“ is a cashout, then the
-- stand; three minutes offline settle the seat (core/CashOut.lua).
local A, B, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local K, N6 = Play.MORE[1], Play.MORE[2]
local ALL = { A, B, M, G, K, N6 } -- the name of chair i
local SK = 1000 -- blinds 10: the big blind of 10 chips of one silver

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
-- turn checking or calling from its own client; `wait` seconds before each move (default 0).
local function calm(sim, host, wait)
  inHand(sim, host)
  local hs = host.session
  local hand = hs.state.hand
  for _ = 1, 300 do
    local st = hs.state
    if not (E.inHand(st) and st.hand == hand) then return end
    local c = st.phase == "bet" and st.turn and sim.clients[hs.seats[st.turn]]
    if c and wait then sim:run(wait); st = hs.state end
    if c and E.inHand(st) and st.phase == "bet" and st.turn and sim.clients[hs.seats[st.turn]] == c then
      c:act{ k = st.bet > st.p[st.turn].bet and "call" or "check" }
    end
    sim:run(1)
  end
  error("the hand did not end")
end

local function hands(sim, host, n)
  for _ = 1, n do calm(sim, host) end
end

-- The "cashout" events of every client of cl (name -> list).
local function outs(cl)
  local got = {}
  for name, c in pairs(cl) do
    got[name] = {}
    c:on("cashout", function(v) table.insert(got[name], v) end)
  end
  return got
end

-- Every client at the table holds the matrix `took` (seat -> seat -> chips).
local function setTook(cl, took)
  for _, c in pairs(cl) do
    local st = c.session and c.session.state
    if st and st.cash then st.cash.took = U.copy(took) end
  end
end

-- The events `from` (the host) sent, each once (by q), from sim.sent[mark + 1] on -> {{q, seat, a}}.
local function evs(sim, from, mark)
  local seen, out = {}, {}
  for i = (mark or 0) + 1, #sim.sent do
    local m = sim.sent[i]
    if m.from == from and m.msg.t == "EV" and not seen[m.msg.q] then
      seen[m.msg.q] = true
      out[#out + 1] = { q = m.msg.q, seat = m.msg.seat, a = m.msg.a }
    end
  end
  return out
end

-- Of evs(...): the ones with a.k == k (and seat, when given).
local function evsOf(sim, from, k, seat, mark)
  local out = {}
  for _, e in ipairs(evs(sim, from, mark)) do
    if e.a.k == k and (seat == nil or e.seat == seat or e.a.seat == seat) then out[#out + 1] = e end
  end
  return out
end

-- The ACTs `from` whispered with a.k == k, from sim.sent[mark + 1] on.
local function acts(sim, from, k, mark)
  local n = 0
  for i = (mark or 0) + 1, #sim.sent do
    local m = sim.sent[i]
    if m.from == from and m.msg.t == "ACT" and type(m.msg.a) == "table" and m.msg.a.k == k then n = n + 1 end
  end
  return n
end

local function asked(client, key)
  for _, d in ipairs(client.stakes:asks()) do if d.key == key then return true end end
  return false
end

local function paired(st, i)
  for j = 1, 9 do if j ~= i and ns.HoldemCash.net(st.cash, i, j) ~= 0 then return true end end
  return false
end

-- Hands until Мария (seat 3) has a pair, at least `least`; between hands after it.
local function playUntilPaired(sim, host, least)
  for n = 1, 20 do
    hands(sim, host, 1)
    if n >= least and paired(host.session.state, 3) then return end
  end
  error("Мария never has a pair")
end

-- The "cashGoing" events of client -> list (false for nil).
local function goings(client)
  local list = {}
  client:on("cashGoing", function(tid) list[#list + 1] = tid or false end)
  return list
end

-- Only the WHISPERs between x and y are lost while `on`.
local function cut(sim, x, y)
  sim.bus.filter = function(from, to, ch, m)
    if ch == "WHISPER" and ((from == x and to == y) or (from == y and to == x)) then return {} end
    return { m }
  end
  return function() sim.bus.filter = nil end
end

describe("the buy-in follows my sit", function()
  it("sit with a buy-in: my client buys once the game holds my seat", function()
    local sim, cl, tid = cash({ 1, 2 })
    local host = cl[A]
    local mark = #sim.sent
    cl[M]:sit(tid, 3, SK, 600); sim:run(2)
    local st = host.session.state
    eq(st.seats[3].bought, 600)
    local b = evsOf(sim, A, "buy", 3, mark)
    eq(#b, 1); eq(b[1].a, { k = "buy", n = 600 })
    eq(cl[M].cashWant, nil)
    sim:run(10)
    eq(#evsOf(sim, A, "buy", 3, mark), 1)
    -- At a table not started yet the wish waits and is played after the start.
    local sim2, cl2 = Play.guild(4, Play.MORE)
    local tid2 = assert(cl2[A]:openTable{ game = "holdem", access = "guild", turn = 30, opt = { blinds = 10 }, stake = SK })
    sim2:run(3)
    cl2[B]:sit(tid2, 2, SK, 500); sim2:run(5)
    eq(#evsOf(sim2, A, "buy"), 0)
    eq(cl2[B].cashWant, { tid = tid2, n = 500, q = nil })
    assert(cl2[A]:startGame()); sim2:run(1)
    eq(cl2[A].session.state.seats[2].bought, 500)
    eq(#evsOf(sim2, A, "buy", 2), 1)
  end)

  it("a wish above the range is clamped down; a floor above my pick is never bought (buyLow)", function()
    local sim, cl, tid = cash({ 1, 2, 3 }, { 1000, 1000, 700 })
    local host = cl[A]
    ok(not (E.inHand(host.session.state) and host.session.state.p[3]), "Мария is not dealt in")
    cl[M]:stand(); sim:run(1)
    eq(cl[M].session, nil)
    eq(host.session.state.cash.left[M], 700)
    local low = {}
    cl[M]:on("buyLow", function(...) low[#low + 1] = { ... } end)
    local mark = #sim.sent
    cl[M]:sit(tid, 3, SK, 400); sim:run(1)
    eq(#evsOf(sim, A, "buy", 3, mark), 0) -- never more than I picked
    eq(cl[M].cashWant, nil)
    eq(low, { { 700, 400 } })
    eq(host.session.state.seats[3].bought, 0)
    -- a pick above the ceiling is clamped down
    local _, hi = E.buyRange(host.session.state, 3)
    cl[M]:wantBuy(tid, hi + 500)
    ns.Session.emit(cl[M]); sim:run(1)
    local bs = evsOf(sim, A, "buy", 3, mark)
    eq(#bs, 1); eq(bs[1].a.n, hi)
    eq(#low, 1)
  end)

  it("one wish buys at most once: a forged cashout right after my buy brings no second buy", function()
    local sim, cl, tid = cash({ 1, 2 })
    local hs = cl[A].session
    local play, forged = hs.play, false
    hs.play = function(self, seat, a, ...)
      local r = { play(self, seat, a, ...) }
      if seat == 3 and a.k == "buy" and not forged then forged = true; play(self, 3, { k = "cashout" }) end
      return unpack(r)
    end
    local mark = #sim.sent
    cl[M]:sit(tid, 3, SK, 600); sim:run(3)
    ok(forged, "the host forged the cashout")
    eq(acts(sim, M, "buy", mark), 1)
    eq(cl[M].cashWant, nil)
    sim:run(10)
    eq(acts(sim, M, "buy", mark), 1)
  end)

  it("an asked seat cannot buy (H15c)", function()
    local sim, cl, tid = cash({ 1, 2 })
    cl[M]:sit(tid, 3, SK); sim:run(1)
    local s = cl[M].session
    s.stakeAsk, s.stakeGame = true, s.gameNo
    eq({ cl[M]:buy(400) }, { nil, "stake" })
    cl[M]:wantBuy(tid, 400)
    local mark = #sim.sent
    ns.Session.emit(cl[M]); sim:run(1)
    eq(#evsOf(sim, A, "buy", 3, mark), 0)
    eq(cl[M].cashWant.n, 400)
    s.stakeAsk = nil
    ns.Session.emit(cl[M]); sim:run(1)
    eq(#evsOf(sim, A, "buy", 3, mark), 1)
  end)

  it("a transient refusal keeps my wish (H15b)", function()
    local sim, cl, tid = cash({ 1, 2, 3, 4 })
    local host = cl[A]
    hands(sim, host, 1)
    inHand(sim, host)
    ok(U.contains(E.players(host.session.state), 4), "Гошо is dealt in")
    cl[G]:stand(true); sim:run(1)
    ok(host.session.state.seats[4].leaving, "his record still leaves")
    local mark = #sim.sent
    cl[G]:sit(tid, 5, SK, 1000); sim:run(1)
    eq(cl[G].session.mySeat, 5)
    eq({ E.buyRange(cl[G].session.state, 5) }, { nil, "hand" })
    eq(#evsOf(sim, A, "buy", 5, mark), 0)
    eq(cl[G].cashWant.n, 1000)
    calm(sim, host); sim:run(1)
    local left = host.session.state.cash.left[G]
    local b = evsOf(sim, A, "buy", 5, mark)
    eq(#b, 1); eq(b[1].a.n, math.min(left, 1000))
    eq(cl[G].cashWant, nil)
  end)
end)

describe("„Стани“ is a cashout, then the stand", function()
  it("„Стани“ between hands: cashout, then the stand; one gid on every client, mine included", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    playUntilPaired(sim, host, 2)
    ok(not E.inHand(host.session.state), "between hands")
    local mark = #sim.sent
    cl[M]:stand(); sim:run(1)
    for _, name in ipairs({ A, B, M }) do eq(#got[name], 1, name) end
    local v = got[A][1]
    eq({ v.seat, v.name, v.why }, { 3, M, nil })
    for _, name in ipairs({ B, M }) do eq({ got[name][1].gid, got[name][1].pairs }, { v.gid, v.pairs }, name) end
    ok(#v.pairs > 0, "she has a pair")
    eq(cl[M].env.db.stakeSeen[v.gid].pairs, v.pairs)
    local co, st = evsOf(sim, A, "cashout", 3, mark), evsOf(sim, A, "stand", 3, mark)
    eq(#co, 1); eq(#st, 1)
    ok(st[1].q > co[1].q, "the stand follows the cashout")
    local key
    for _, k in ipairs(host.session.book.keys) do if k.seat == 3 then key = k end end
    ok(key, "her key is published")
    eq(cl[M].session, nil)
    eq(host.session.seats[3], false)
  end)

  it("„Стани“ inside a hand waits for its end", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    local going = goings(cl[M])
    inHand(sim, host)
    ok(U.contains(E.players(host.session.state), 3), "Мария is dealt in")
    local mark = #sim.sent
    cl[M]:stand(); sim:run(1)
    eq(cl[M].cashGoing.tid, tid)
    eq(going, { tid })
    eq(cl[M].session.mySeat, 3)
    local hs, acted = host.session, 0
    local hand = hs.state.hand
    for _ = 1, 300 do
      local st = hs.state
      if not (E.inHand(st) and st.hand == hand) then break end
      eq(#got[A], 0)
      local c = st.phase == "bet" and st.turn and sim.clients[hs.seats[st.turn]]
      if c then
        local r = c:act{ k = st.bet > st.p[st.turn].bet and "call" or "check" }
        if c == cl[M] then ok(r, "she can still act"); acted = acted + 1 end
      end
      sim:run(1)
    end
    ok(acted > 0, "she acted")
    eq(#got[A], 1); eq(got[A][1].seat, 3)
    eq(#evsOf(sim, A, "stand", 3, mark), 1)
    eq(cl[M].session, nil)
    eq(going, { tid, false })
  end)

  it("a cashout that loses the race with the next hand waits for it (Review Focus 2)", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    playUntilPaired(sim, host, 1)
    ok(not E.inHand(host.session.state), "between hands")
    local mark = #sim.sent
    cl[M]:stand()
    host.session:play(0, { k = "hand" })
    sim:run(1)
    local hand = host.session.state.hand
    ok(E.inHand(host.session.state) and host.session.state.p[3], "she is dealt in")
    eq(acts(sim, M, "cashout", mark), 1)
    eq(#evsOf(sim, A, "cashout", nil, mark), 0)
    ok(cl[M].session and cl[M].session.mySeat == 3, "still seated")
    calm(sim, host); sim:run(1)
    local co = evsOf(sim, A, "cashout", 3, mark)
    eq(#co, 1)
    local ended
    for _, e in ipairs(evs(sim, A, mark)) do if e.a.k == "showdown" or e.a.k == "fold" then ended = e.q end end
    ok(co[1].q > ended, "after the hand")
    ok(host.session.state.hand == hand or not E.inHand(host.session.state), "no hand between")
    for _, name in ipairs({ A, B, M }) do eq(#got[name], 1, name) end
    for _, name in ipairs({ B, M }) do eq({ got[name][1].gid, got[name][1].pairs }, { got[A][1].gid, got[A][1].pairs }, name) end
    eq(cl[M].session, nil)
  end)

  -- NB: this cuts the link for the whole wait, so it tests a dead link; the honest-link
  -- variant (the host gets my cashout, the hand goes on) is the H15a test below.
  it("a host that never plays my cashout: I stand after CASH_OUT_WAIT and its claims are put to me (C5)", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    ok(not E.inHand(host.session.state), "between hands")
    setTook(cl, { [1] = { [3] = 50 } }) -- Мария owes Иван 50 chips
    local heal = cut(sim, A, M) -- the link between Мария and her host is dead
    cl[M]:stand(); sim:run(1)
    ok(cl[M].session, "she waits for her cashout")
    sim:run(C.CASH_OUT_WAIT - 3)
    ok(cl[M].session, "still waiting")
    heal(); sim:run(3)
    eq(cl[M].session, nil)
    eq(#got[M], 0) -- my client has no note of that settlement
    for _ = 1, 60 do
      if host.session.seats[3] == false and #got[A] > 0 then break end
      sim:run(1)
    end
    eq(host.session.seats[3], false)
    local v = got[A][1]
    eq({ v.seat, v.name }, { 3, M })
    sim:run(10)
    local key = v.gid .. "|" .. M .. "|" .. A
    ok(Play.debt(cl[M], v.gid, M, A), "the claim is there")
    ok(asked(cl[M], key), "put to her")
    eq(cl[M].stakes:seen()[v.gid], nil)
  end)

  it("the next hand deals me in while the CASH_OUT_WAIT runs: the wait is cancelled (H15a)", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    hands(sim, host, 1)
    ok(not E.inHand(host.session.state), "between hands")
    sim.bus.filter = function(from, to, ch, m) -- the host never gets her cashout
      if from == M and m.t == "ACT" and m.a.k == "cashout" then return {} end
      return { m }
    end
    local mark = #sim.sent
    cl[M]:stand(); sim:run(1)
    eq(acts(sim, M, "cashout", mark), 1)
    inHand(sim, host)
    ok(host.session.state.p[3], "the next hand deals her in")
    local from = sim:now()
    calm(sim, host, 8) -- a slow hand: longer than CASH_OUT_WAIT
    ok(sim:now() - from > C.CASH_OUT_WAIT, "the hand outlasts the wait")
    eq(cl[M].session and cl[M].session.mySeat, 3) -- not stood up mid-hand
    eq(#evsOf(sim, A, "stand", 3, mark), 0)
    eq(#evsOf(sim, A, "fold", 3, mark), 0) -- nothing she put in is folded
    sim:run(1)
    eq(acts(sim, M, "cashout", mark), 2) -- played again after the hand
    -- ... and armed again: the link dies, no hand reaches her, she stands after the wait.
    sim.bus.filter = nil
    local heal = cut(sim, A, M)
    sim:run(C.CASH_OUT_WAIT + 1)
    heal()
    eq(cl[M].session, nil)
  end)

  it("the wait's timer re-checks the hand: dealt in within the same frame, I am not stood up", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host = cl[A]
    hands(sim, host, 1)
    ok(not E.inHand(host.session.state), "between hands")
    local heal = cut(sim, A, M)
    cl[M]:stand(); sim:run(C.CASH_OUT_WAIT - 1)
    ok(cl[M].session, "still waiting")
    local st = cl[M].session.state -- the deal lands; no "session" step has run yet
    st.phase, st.p = "bet", { [3] = {} }
    sim:run(2)
    heal()
    ok(cl[M].session, "not stood up into a running hand")
  end)

  it("the host leaves mid-game: its cashout, its own S, the handoff; the table plays on", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [2] = { [1] = 20 } }) -- Иван owes Петър 20 chips
    ok(not E.inHand(host.session.state), "between hands")
    cl[A]:stand(); sim:run(3)
    eq(cl[A].session, nil)
    for _, name in ipairs({ A, B, M }) do eq(#got[name], 1, name) end
    local v = got[B][1]
    eq({ v.seat, v.name, v.why }, { 1, A, nil })
    eq(got[A][1].gid, v.gid)
    local S = Play.entries(sim, A, "S")
    eq(#S, 1); eq({ S[1].gid, S[1].f }, { v.gid, A })
    eq(cl[B].session.role, "host")
    inHand(sim, cl[B])
    eq(E.players(cl[B].session.state), { 2, 3 })
  end)

  it("heads-up: the other player's cashout and stand end the game with every pair settled", function()
    local sim, cl = cash({ 1, 2 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 2)
    ok(not E.inHand(host.session.state), "between hands")
    cl[B]:stand(); sim:run(1)
    eq(cl[B].session, nil)
    eq(#got[A], 1); eq(got[A][1].seat, 2)
    eq(host.session.status, "aborted")
    local st = host.session.state
    local r = st.seats[1]
    eq(r.chips - r.bought - r.cleared, 0)
    eq(next(st.cash.took), nil)
  end)

  it("an asked seat stands at once; a fun table's stand sends what it sent", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    hands(sim, host, 1)
    local s = cl[M].session
    s.stakeAsk, s.stakeGame = true, s.gameNo
    local mark = #sim.sent
    cl[M]:stand()
    eq(cl[M].session, nil)
    sim:run(1)
    eq(acts(sim, M, "cashout", mark), 0)
    eq(#evsOf(sim, A, "stand", 3, mark), 1)
    -- ... and the asked seat my client stands up itself (ns.Stake.standUp) too, though it clears the ask first.
    local sb = cl[B].session
    sb.stakeAsk, sb.stakeGame = true, sb.gameNo
    ns.Stake.standUp(cl[B], sb)
    eq(cl[B].session, nil)
    sim:run(1)
    eq(acts(sim, B, "cashout", mark), 0)
    -- A fun Холдем: the stand is the STD, no cashout, and the host's one stand event.
    local sim2, cl2 = Play.guild(3)
    local tid2 = assert(cl2[A]:openTable{ game = "holdem", access = "guild", turn = 30 })
    sim2:run(3)
    cl2[B]:sit(tid2, 2); sim2:run(1)
    cl2[M]:sit(tid2, 3); sim2:run(1)
    assert(cl2[A]:startGame()); sim2:run(1)
    calm(sim2, cl2[A])
    mark = #sim2.sent
    cl2[M]:stand(); sim2:run(1)
    local mine = {}
    for i = mark + 1, #sim2.sent do
      local m = sim2.sent[i]
      if m.from == M and m.channel == "WHISPER" then mine[#mine + 1] = m.msg.t .. (m.msg.a and " " .. m.msg.a.k or "") end
    end
    eq(mine, { "ACT book", "STD" }) -- my key first (core/BookKeys.lua), then the stand
    local host2 = {}
    for _, e in ipairs(evs(sim2, A, mark)) do if e.seat == 0 and e.a.seat == 3 then host2[#host2 + 1] = e.a end end
    eq(host2, { { k = "stand", seat = 3, why = "left" } })
    eq(cl2[M].session, nil)
  end)
end)

describe("three minutes offline", function()
  -- Гошо goes silent between hands, owing Иван 30 chips -> sim, cl, got, his chips then.
  local function silent()
    local sim, cl = cash({ 1, 2, 3, 4 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    ok(not E.inHand(host.session.state), "between hands")
    setTook(cl, { [1] = { [4] = 30 } })
    local chips = host.session.state.seats[4].chips
    sim:offline(G)
    for _ = 1, C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER do
      if host.session.seats[4] == false and #got[A] > 0 then break end
      sim:run(1)
    end
    return sim, cl, got, chips
  end

  it("three minutes offline: the seat is settled and the debts wait for the leaver (Review Focus 4)", function()
    local sim, cl, got = silent()
    local host = cl[A]
    eq(host.session.seats[4], false)
    local st = evsOf(sim, A, "stand", 4)
    eq(#st, 1); eq(st[1].a.why, "offline")
    local recs = {}
    for _, v in ipairs(got[A]) do if v.seat == 4 then recs[#recs + 1] = v end end
    eq(#recs, 1); eq({ recs[1].name, recs[1].why }, { G, "offline" })
    local gid = recs[1].gid
    sim:run(5)
    local S
    for _, e in ipairs(Play.entries(sim, A, "S")) do if e.gid == gid then S = e end end
    eq({ S.f, S.why }, { G, "offline" })
    eq(Play.debt(cl[A], gid, G, A).status, "pending")
    local g = sim:relog(G)
    sim:settle(); sim:run(60)
    ok(asked(g, gid .. "|" .. G .. "|" .. A), "put to Гошо")
  end)

  it("an offline seat loses no blind after its shuffle lapsed", function()
    local _, _, got, chips = silent()
    local rec
    for _, v in ipairs(got[A]) do if v.seat == 4 then rec = v end end
    eq(rec.chips, chips)
  end)
end)
