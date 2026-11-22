local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, E, U, HC = ns.Const, ns.Engines.holdem, ns.Util, ns.HoldemCash

-- Stage F3, Task 9: a modified host at a cash table (E1, E8, and the cheats of Tasks 5-8).
-- Every scenario is played with the victim's real client and ends with `victim`: no debt
-- of the victim confirmed on any client, no own D and no C from its client, and its word
-- a contest (N with the reason) or a question; the honest twin of a scenario confirms.
local A, B, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local K, N6 = Play.MORE[1], Play.MORE[2]
local ALL = { A, B, M, G, K, N6 } -- the name of chair i
local SK = 1000 -- blinds 10: the big blind of 10 chips of one silver

-- A guild of the six names of ALL; Иван opens a staked Холдем (opt, default blinds 10; turn 30),
-- the names of `chairs` sit in their chairs, Иван starts, and every chair c buys buys[c] chips
-- (default 1000; false: no buy) -> sim, cl, tid (tests/core/stakes_cash_table_test.lua).
local function cash(chairs, opt, buys)
  local sim, cl = Play.guild(4, Play.MORE)
  for i, name in ipairs(ALL) do
    local n = i -- each client its own stream (a second key at one table is a new one)
    sim.envs[name].random = function(lo, hi) n = n + 1; return lo + (n * 7 + i) % (hi - lo + 1) end
  end
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

-- One second at a time, every seat on turn checking or calling from its own client but the
-- seats of `idle` (their turn runs out), until host's state meets want(st) in a hand (an error
-- after 600 s).
local function till(sim, host, want, idle)
  local hs = host.session
  for _ = 1, 600 do
    local st = hs.state
    if E.inHand(st) and want(st) then return end
    local c = E.inHand(st) and st.phase == "bet" and st.turn and not (idle and idle[st.turn]) and sim.clients[hs.seats[st.turn]]
    if c then c:act{ k = st.bet > st.p[st.turn].bet and "call" or "check" } end
    sim:run(1)
  end
  error("never")
end

-- The hand that runs at host's table (the next one when none runs) played out as in `till`.
local function calm(sim, host, idle)
  inHand(sim, host)
  local hs = host.session
  local hand = hs.state.hand
  for _ = 1, 600 do
    local st = hs.state
    if not (E.inHand(st) and st.hand == hand) then return end
    local c = st.phase == "bet" and st.turn and not (idle and idle[st.turn]) and sim.clients[hs.seats[st.turn]]
    if c then c:act{ k = st.bet > st.p[st.turn].bet and "call" or "check" } end
    sim:run(1)
  end
  error("the hand did not end")
end

local function hands(sim, host, n)
  for _ = 1, n do calm(sim, host) end
end

-- Every client at the table holds the matrix `took` (seat -> seat -> chips: took[w][l], l owes w).
local function setTook(cl, took)
  for _, c in pairs(cl) do
    local st = c.session and c.session.state
    if st and st.cash then st.cash.took = U.copy(took) end
  end
end

-- The host's „Приключи“, the hand played out if one runs, the keys out and checked.
local function close(sim, host, idle)
  assert(ns.Cash.close(host))
  sim:run(1)
  if E.inHand(host.session.state) then calm(sim, host, idle) end
  sim:run(C.BOOK_WAIT + 5)
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

-- The gid of the first "cashout" event in list with `why` (any: nil) and `seat` (any: nil).
local function gidOf(list, why, seat)
  for _, v in ipairs(list) do
    if (why == nil or v.why == why) and (seat == nil or v.seat == seat) then return v.gid end
  end
end

local function asked(client, key)
  for _, d in ipairs(client.stakes:asks()) do if d.key == key then return true end end
  return false
end

-- Every GUILD LEV entry of the sim -> list.
local function entries(sim)
  local out = {}
  for _, m in ipairs(sim.sent) do
    if m.channel == "GUILD" and m.msg.t == "LEV" then
      for _, e in ipairs(m.msg.ev or {}) do out[#out + 1] = e end
    end
  end
  return out
end

-- What `debtor` said about the claims of its debt gid|debtor|t: its own D (why), its C or N
-- (why), in the order sent (tests/core/stakes_cash_settle_test.lua).
local function words(sim, debtor, gid, t)
  local all, claims, out = entries(sim), {}, {}
  for _, e in ipairs(all) do
    if e.k == "D" and e.gid == gid and e.f == debtor and e.t == t and ns.Ledger.author(e.i) == t then claims[e.i] = true end
  end
  for _, e in ipairs(all) do
    local by = ns.Ledger.author(e.i)
    if by == debtor and e.k == "D" and e.gid == gid and e.f == debtor and e.t == t then out[#out + 1] = { k = "D", why = e.why } end
    if by == debtor and (e.k == "C" or e.k == "N") and claims[e.r] then out[#out + 1] = { k = e.k, why = e.why } end
  end
  return out
end

-- The end of every cheating scenario, for the victim V: no debt of V is confirmed on any
-- client of cl; V's client wrote no own D (f == V) and no C; its word on the debt gid|V|t is
-- `want` ({k = "N", why = ...}), or that debt is put to V (want == "ask").
local function victim(sim, cl, V, gid, t, want)
  for name, c in pairs(cl) do
    for _, d in ipairs(ns.LedgerView.of(c.ledger).debts) do
      if d.f == V then ok(d.status ~= "confirmed", name .. " confirms " .. d.key) end
    end
  end
  for _, e in ipairs(Play.entries(sim, V, "D")) do ok(e.f ~= V, "the victim's own D at " .. tostring(e.gid)) end
  eq(#Play.entries(sim, V, "C"), 0)
  ok(gid and t, "the debt")
  if want == "ask" then
    eq(words(sim, V, gid, t), {})
    ok(asked(cl[V], gid .. "|" .. V .. "|" .. t), "put to the victim")
  else
    eq(words(sim, V, gid, t), { want })
  end
end

-- The honest end: V's own D (why "cash") on the debt gid|V|t, confirmed on every client of cl.
local function honest(sim, cl, V, gid, t)
  ok(gid and t, "the debt")
  eq(words(sim, V, gid, t), { { k = "D", why = "cash" } })
  for name, c in pairs(cl) do eq(Play.debt(c, gid, V, t).status, "confirmed", name) end
end

-- The modified host's wire to `to`: while r.cut every EV and SNP of the host to `to` is lost
-- and its TCK names `to`'s own q (no gap to ask about); r.swap(m) -> another message for an
-- EV it picks. The test sends `to` what it wants (r.ev, r.push).
local function rig(sim, host, to)
  local r, hn = { cut = false }, host.env.me
  sim.bus.filter = function(from, dest, ch, m)
    if from ~= hn or dest ~= to or ch ~= "WHISPER" then return { m } end
    local x = r.swap and m.t == "EV" and r.swap(m)
    if x then return { x } end
    if r.cut and (m.t == "EV" or m.t == "SNP") then return {} end
    local vs = sim.clients[to].session
    if r.cut and m.t == "TCK" and vs then
      local t = U.copy(m)
      t.q = vs.seq
      return { t }
    end
    return { m }
  end
  -- The event (seat, a) for `to` alone, at its next q.
  function r.ev(seat, a)
    local hs, vs = host.session, sim.clients[to].session
    sim.clients[to]:receive("WHISPER", hn, ns.Session.message("EV", { tid = hs.tid, e = hs.epoch, q = vs.seq + 1, seat = seat, a = a }))
    sim:run(0)
  end
  -- The host's own snapshot for `to`, pushed unasked (the wire is whole again first).
  function r.push(mutate)
    local hs = host.session
    r.cut = false
    local st = U.copy(hs:snapshotFor(to))
    if mutate then mutate(st) end
    sim.clients[to]:receive("WHISPER", hn, ns.Session.message("SNP", { tid = hs.tid, e = hs.epoch, q = hs.seq, tbl = hs:record(),
      st = st, left = hs:left(), inv = hs:invitedList(), fr = hs:hook("snap") }))
    sim:run(0)
  end
  -- The host's heartbeat at its own q (the wire whole again): `to` asks for the snapshot.
  function r.tick()
    local hs = host.session
    r.cut = false
    sim.envs[hn].send("WHISPER", to, ns.Session.message("TCK", { tid = hs.tid, e = hs.epoch, q = hs.seq }))
    sim:run(1)
  end
  function r.stop() sim.bus.filter = nil end
  return r
end

-- f() with t[k] = v, t[k] given back after it, even when f fails (the failure raised again).
local function patched(t, k, v, f)
  local was = t[k]
  t[k] = v
  local done, err = pcall(f)
  t[k] = was
  if not done then error(err, 0) end
end

-- The seat after v among the seats of `list` (ascending, round).
local function after(v, list)
  for i, x in ipairs(list) do if x == v then return list[i % #list + 1] end end
end

-- E8, the key draw, at host's table of the seats `list`, the victim at seat v (dealt into the
-- running hand, its seed in): at the turn of the seat after it, none of the others acted yet,
-- the host whispers it a fold of every other seat and a close; its client sees its hand and
-- its game end and sends its key, which the host keeps to itself -> r (rig to the victim,
-- cut), the key {m, live}.
local function draw(sim, cl, v, list)
  local host, V = cl[A], ALL[v]
  till(sim, host, function(st)
    if not (st.phase == "bet" and st.turn == after(v, list)) then return false end
    for _, x in ipairs(list) do -- every seat in the hand, the others to act yet (their folds end it)
      if not (st.p[x] and not st.p[x].folded and (x == v or not st.p[x].acted)) then return false end
    end
    return true
  end)
  local r, key = rig(sim, host, V), nil
  local take = ns.Book.take
  patched(ns.Book, "take", function(s, seat, a)
    if s.client == host and seat == v then key = { m = a.m, live = E.inHand(s.state) }; return end
    return take(s, seat, a)
  end, function()
    r.cut = true
    local vs = cl[V].session
    for _ = 1, #list do
      if E.inHand(vs.state) and vs.state.turn ~= v then r.ev(vs.state.turn, { k = "fold" }) end
    end
    ok(not E.inHand(vs.state), "the victim's hand is over on its client")
    r.ev(0, { k = "close" })
    ok(E.over(vs.state), "the game is over on the victim's client")
    sim:run(1)
  end)
  ok(key and key.live, "the host holds the victim's key while the real hand runs")
  return r, key
end

describe("a modified host at a cash table: the key draw (E8)", function()
  -- Петър (seat 2) owes Иван 40 chips; the key draw, the real hand played with his turns run
  -- out; back(r) brings him back; the close -> sim, cl, the close's gid.
  local function keyDraw(back, late)
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    if back then
      local r = draw(sim, cl, 2, { 1, 2, 3 })
      calm(sim, host, { [2] = true })
      if late then -- the real game ends without him
        setTook(cl, { [1] = { [2] = 40 } })
        close(sim, host, { [2] = true })
      end
      back(r, sim, cl)
      r.stop()
    end
    if not late then
      setTook(cl, { [1] = { [2] = 40 } })
      close(sim, host)
    end
    sim:run(C.STAKE_OWE_WAIT + 5)
    return sim, cl, gidOf(got[A], "close")
  end

  it("the honest table: my debt is confirmed", function()
    local sim, cl, gid = keyDraw(nil)
    honest(sim, cl, B, gid, A)
  end)

  it("E8: the host ends my hand and the game by forged events, takes my key, and pushes me back", function()
    local sim, cl, gid = keyDraw(function(r, _, cl)
      r.push()
      eq(cl[B].session.stakeFoul, "forged")
    end)
    victim(sim, cl, B, gid, A, { k = "N", why = "forged" })
  end)

  -- The snapshot rule alone would make this a question (asked); my key left at the game's end
  -- and the same game runs on under the same host: the book is forged (rule 6a), and so am I.
  it("E8: the same, the host makes me ask for the snapshot of the running game", function()
    local sim, cl, gid = keyDraw(function(r, _, cl)
      r.tick()
      ok(not E.over(cl[B].session.state), "the running game is back")
      ok(cl[B].session.book.forged, "the book is forged")
      eq(cl[B].session.stakeFoul, "forged")
    end)
    victim(sim, cl, B, gid, A, { k = "N", why = "forged" })
  end)

  -- My notes of the end I was told wait for the book; the table's own end differs: they are
  -- forged, not confirmed by the keys (Task 9 finding: they were confirmed, my own D written).
  it("E8: the same, the host lets me back only once the real game is over", function()
    local sim, cl, gid = keyDraw(function(r, _, cl)
      r.tick()
      ok(E.over(cl[B].session.state), "the game is over")
      ok(cl[B].session.book.forged, "the end I was told is not the table's: the book is forged")
      eq(cl[B].session.stakeFoul, "forged")
    end, true)
    victim(sim, cl, B, gid, A, "ask")
  end)

  -- Мария (seat 3) owes Петър 40 chips; the key draw; Иван hands the table to Петър, who takes
  -- it with her key read. push: his snapshot reaches her unasked; else she asks for it. late:
  -- the real game is closed first (her turns run out).
  local function accomplice(push, late)
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [2] = { [3] = 40 } })
    local r = draw(sim, cl, 3, { 1, 2, 3 })
    calm(sim, host, { [3] = true })
    if late then
      setTook(cl, { [2] = { [3] = 40 } })
      close(sim, host, { [3] = true })
    end
    r.stop()
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == M and (m.t == "EV" or m.t == "SNP") then return {} end -- the old host's stand: lost too
      if not push and from == B and to == M and m.t == "SNP" and not cl[M].session.asked then return {} end -- she asks
      return { m }
    end
    host:stand(true); sim:run(1)
    eq(cl[B].session.role, "host")
    sim:run(C.PING_EVERY + 5)
    sim.bus.filter = nil
    eq(cl[M].session.host, B)
    if not late then
      ok(not cl[M].session.book.forged, "no key of mine left under this host")
      setTook(cl, { [2] = { [3] = 40 } })
      close(sim, cl[B])
    end
    sim:run(C.STAKE_OWE_WAIT + 5)
    return sim, cl, gidOf((late and got[A]) or got[B], "close")
  end

  it("E8: the same, the host hands the table to an accomplice, who makes me ask", function()
    local sim, cl, gid = accomplice(false)
    victim(sim, cl, M, gid, B, "ask")
    eq(cl[M].stakes:seen()[gid].foul, "unseen")
  end)

  it("E8: the same, the accomplice pushes its snapshot on me", function()
    local sim, cl, gid = accomplice(true)
    victim(sim, cl, M, gid, B, { k = "N", why = "forged" })
  end)

  it("E8: the same, the accomplice takes the table once the real game is over: my notes of the told end are asked", function()
    local sim, cl, gid = accomplice(false, true)
    local s = cl[M].session
    ok(s.book.forged and s.book.held, "the book is held for a question")
    eq(s.stakeFoul, "unseen")
    for g, n in pairs(cl[M].stakes:seen()) do
      if g ~= gid and #n.pairs > 0 then eq({ n.wait, n.foul }, { nil, "unseen" }, g) end
    end
    victim(sim, cl, M, gid, B, "ask")
  end)

  it("E8: my own /reload in a hand, and a snapshot that says the hand and the game ended", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    till(sim, host, function(st)
      return st.phase == "bet" and st.turn == 3 and st.p[2] and not st.p[2].folded and not st.p[1].acted and not st.p[3].acted
    end)
    local key
    local take = ns.Book.take
    patched(ns.Book, "take", function(s, seat, a)
      if s.client == host and seat == 2 then key = { m = a.m, live = E.inHand(s.state) }; return end
      return take(s, seat, a)
    end, function()
      sim.bus.filter = function(from, to, _, m) -- the host answers my login with the hand and the game over
        if from == A and to == B and m.t == "SNP" and type(m.st) == "table" then
          local x = U.copy(m)
          local st = E.restore(x.st)
          for _ = 1, 3 do
            if E.inHand(st) and st.turn ~= 2 then assert(E.apply(st, st.turn, { k = "fold" })) end
          end
          assert(E.apply(st, 0, { k = "close" }))
          x.st = E.snapshot(st)
          return { x }
        end
        return { m }
      end
      cl[B] = sim:relog(B); sim:run(2)
      sim.bus.filter = nil
    end)
    ok(E.over(cl[B].session.state), "the game is over on my client")
    ok(key and key.live, "the host holds my key while the real hand runs")
    local r = rig(sim, host, B)
    r.cut = true
    calm(sim, host, { [2] = true })
    setTook(cl, { [1] = { [2] = 40 } })
    close(sim, host, { [2] = true })
    r.tick()
    r.stop()
    sim:run(C.STAKE_OWE_WAIT + 5)
    victim(sim, cl, B, gidOf(got[A], "close"), A, "ask")
  end)

  it("E8 heads-up: the host claims what its own play made", function()
    for _, cheat in ipairs({ false, true }) do
      local sim, cl = cash({ 1, 2 })
      local host, got = cl[A], outs(cl)
      local hs = host.session
      hands(sim, host, 1)
      setTook(cl, { [1] = { [2] = 200 } }) -- Петър owes Иван 200 chips
      if not cheat then
        close(sim, host)
        honest(sim, cl, B, gidOf(got[A], "close"), A)
      else
        local r, key = draw(sim, cl, 2, { 1, 2 })
        local fake = gidOf(got[B], "close")
        ok(fake, "the close on Петър's client")
        calm(sim, host, { [2] = true }) -- the hand Иван plays with Петър's cards known
        local owed = HC.net(hs.state.cash, 1, 2) * 100
        ok(cl[A].ledgerNet:make("D", { gid = fake, g = "holdem", f = B, t = A, c = owed, why = "lost" })); sim:run(3)
        -- The keys of Петър's game, so that his book is checked and final.
        r.ev(0, { k = "book", op = "keys", m = { [1] = hs.book.key, [2] = key.m }, g = hs.book.g, f = true })
        sim:run(C.BOOK_WAIT)
        r.stop()
        ok(cl[B].session.book.final and cl[B].stakes:seen()[fake].foul == nil, "Петър's note is clean and checked")
        victim(sim, cl, B, fake, A, { k = "N", why = "amount" })
      end
    end
  end)
end)

describe("a modified host at a cash table: forged in my name", function()
  -- Петър (seat 2) owes Иван 40 chips at the close of a three-seat table, cheat(sim, cl) played
  -- first (nil: none) -> sim, cl, the close's gid.
  local function owing(cheat, chairs, buys)
    local sim, cl, tid = cash(chairs or { 1, 2, 3 }, nil, buys)
    local host, got = cl[A], outs(cl)
    if cheat then cheat(sim, cl, tid) end
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    close(sim, host)
    return sim, cl, gidOf(got[A], "close")
  end

  it("a move in my name is forged; my own is clean", function()
    for _, cheat in ipairs({ false, true }) do
      local sim, cl, gid = owing(function(sim, cl)
        local hs = cl[A].session
        till(sim, cl[A], function(st) return st.phase == "bet" and st.turn == 2 end)
        local st = hs.state
        local a = { k = st.bet > st.p[2].bet and "call" or "check" }
        if cheat then hs:play(2, a) else cl[B]:act(a) end
        sim:run(1)
        eq(cl[B].session.stakeFoul, cheat and "forged" or nil)
      end)
      if cheat then victim(sim, cl, B, gid, A, { k = "N", why = "forged" }) else honest(sim, cl, B, gid, A) end
    end
  end)

  it("a buy in my name is forged; my own is clean", function()
    for _, cheat in ipairs({ false, true }) do
      local sim, cl, gid = owing(function(sim, cl)
        if cheat then cl[A].session:play(2, { k = "buy", n = 1000 }) else cl[B]:act{ k = "buy", n = 1000 } end
        sim:run(1)
        eq(cl[A].session.state.seats[2].bought, 1000)
        eq(cl[B].session.stakeFoul, cheat and "forged" or nil)
      end, nil, { [2] = false })
      if cheat then victim(sim, cl, B, gid, A, { k = "N", why = "forged" }) else honest(sim, cl, B, gid, A) end
    end
  end)

  it("a cashout in my name is forged (Task 7), and my wish buys once (Task 8 review I1); my own is clean", function()
    for _, cheat in ipairs({ false, true }) do
      local sim, cl = Play.guild(4, Play.MORE)
      for i, name in ipairs(ALL) do sim.envs[name].random = function(lo, hi) return (lo + i) % (hi + 1) end end
      local tid = assert(cl[A]:openTable{ game = "holdem", access = "guild", turn = 30, opt = { blinds = 10 }, stake = SK })
      sim:run(3)
      cl[M]:sit(tid, 3, SK); sim:run(1)
      assert(cl[A]:startGame()); sim:run(1)
      ok(cl[A]:act{ k = "buy", n = 1000 }); ok(cl[M]:act{ k = "buy", n = 1000 }); sim:run(1)
      local host, got, mark = cl[A], outs(cl), #sim.sent
      cl[B]:sit(tid, 2, SK, 1000); sim:run(2) -- my wish: my client buys 1000 chips
      eq(host.session.state.seats[2].bought, 1000)
      hands(sim, host, 2)
      setTook(cl, { [1] = { [2] = 40 } })
      if cheat then host.session:play(2, { k = "cashout" }) else ok(cl[B]:act{ k = "cashout" }) end
      sim:run(3)
      eq(host.session.state.seats[2].bought, 0)
      local buys = 0
      for i = mark + 1, #sim.sent do
        local m = sim.sent[i]
        if m.from == A and m.target == M and m.msg.t == "EV" and m.msg.seat == 2 and m.msg.a.k == "buy" then buys = buys + 1 end
      end
      eq(buys, 1)
      eq(cl[B].session.stakeFoul, cheat and "forged" or nil)
      local gid = gidOf(got[A], nil, 2)
      close(sim, host)
      if cheat then victim(sim, cl, B, gid, A, { k = "N", why = "forged" }) else honest(sim, cl, B, gid, A) end
    end
  end)

  it("the host folds me before my clock ran out: forged; after it: clean", function()
    for _, cheat in ipairs({ false, true }) do
      local sim, cl, gid = owing(function(sim, cl)
        local hs = cl[A].session
        till(sim, cl[A], function(st) return st.phase == "bet" and st.turn == 2 end)
        if cheat then
          hs:play(2, E.auto(hs.state, 2), true); sim:run(1)
        else
          till(sim, cl[A], function(st) return st.turn ~= 2 end, { [2] = true }) -- the host's own timer
          sim:run(1)
        end
        eq(cl[B].session.stakeFoul, cheat and "forged" or nil)
      end)
      if cheat then victim(sim, cl, B, gid, A, { k = "N", why = "forged" }) else honest(sim, cl, B, gid, A) end
    end
  end)

  it("the host stands me up while my client runs (E1)", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    local hs = host.session
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    ns.Succession.untrack(hs, B)
    hs:event(0, { k = "stand", seat = 2, why = "offline" }); hs:recordChanged()
    local gid = gidOf(got[A], nil, 2)
    ok(gid, "my seat is settled")
    sim:run(C.PING_EVERY + 5) -- my client hears it by SNO "gone": an open note
    eq(cl[B].session, nil)
    local open
    for _, n in pairs(cl[B].env.db.stakeSeen) do if n.open then open = n end end
    eq(open and open.foul, "stand")
    close(sim, host)
    sim:run(C.STAKE_OWE_WAIT)
    victim(sim, cl, B, gid, A, { k = "N", why = "stand" })
  end)

  it("the host shows me another player's fold that the player never made", function()
    for _, cheat in ipairs({ false, true }) do
      local sim, cl = cash({ 1, 2, 3 })
      local host, got = cl[A], outs(cl)
      local hs = host.session
      hands(sim, host, 1)
      setTook(cl, { [3] = { [2] = 50 } }) -- Петър owes Мария 50 chips
      -- Иван folds; Петър's turn with Мария in the hand.
      for _ = 1, 600 do
        local st = hs.state
        if E.inHand(st) and st.phase == "bet" and st.turn == 2 and st.p[1].folded and st.p[3] and not st.p[3].folded then break end
        local c = E.inHand(st) and st.phase == "bet" and st.turn and sim.clients[hs.seats[st.turn]]
        if c then c:act{ k = st.turn == 1 and "fold" or (st.bet > st.p[st.turn].bet and "call" or "check") } end
        sim:run(1)
      end
      local st = hs.state
      eq({ st.turn, st.p[1].folded }, { 2, true })
      if not cheat then
        ok(cl[B]:act{ k = "fold" }); sim:run(1) -- Петър folds himself
        cl[M]:stand(); sim:run(3) -- Мария's „Стани“: her cashout, then the stand
      else
        local r = rig(sim, host, M)
        local q = hs.seq + 1
        r.swap = function(m) -- Мария sees Петър fold at the q of his real move
          if m.q ~= q or m.seat ~= 2 then return nil end
          local x = U.copy(m)
          x.a = { k = "fold" }
          r.cut = true
          return x
        end
        -- Петър raises (the turn comes back to Мария: no other event before her stand).
        ok(cl[B]:act(st.bet == 0 and { k = "bet", to = st.bb } or { k = "raise", to = st.bet + st.minRaise })); sim:run(1)
        eq({ hs.seq, hs.state.turn }, { q, 3 })
        ok(not E.inHand(cl[M].session.state) and E.inHand(hs.state), "the hand is over for Мария alone")
        cl[M]:stand(); sim:run(1) -- her cashout goes to the host, which refuses it in its hand
        eq({ cl[M].session.mySeat, hs.seq }, { 3, q })
        r.swap = nil
        ns.Succession.untrack(hs, M)
        hs:event(0, { k = "stand", seat = 3, why = "left" }); hs:recordChanged()
        r.ev(3, { k = "cashout" }) -- Мария sees her own cashout at the q of the stand the others see
        sim:run(3)
        r.stop()
        eq(cl[M].session, nil)
      end
      local gid = gidOf(got[A], nil, 3)
      ok(gid and gidOf(got[M], nil, 3) == gid, "one gid for Мария's settlement on both sides")
      local claim
      for _, e in ipairs(Play.entries(sim, M, "D")) do if e.gid == gid then claim = e end end
      ok(claim and claim.f == B, "Мария's claim against Петър")
      setTook(cl, {})
      close(sim, host)
      if cheat then
        victim(sim, cl, B, gid, M, { k = "N", why = "amount" })
        for _, c in pairs(cl) do ok(Play.debt(c, gid, B, M).status ~= "confirmed") end
      else
        honest(sim, cl, B, gid, M)
      end
    end
  end)

  it("the host ends the table while I sit in the running game", function()
    local sim, cl, tid = cash({ 1, 2, 3 })
    local host = cl[A]
    local hs = host.session
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    local gid = tid .. "/" .. (hs.seq + 1)
    hs:finish(); sim:run(1)
    eq(cl[B].session, nil)
    local note = cl[B].env.db.stakeSeen[tid .. "/" .. hs.seq]
    ok(note and note.open and note.foul == "forged", "the open note")
    ok(host.ledgerNet:make("D", { gid = gid, g = "holdem", f = B, t = A, c = 4000, why = "lost" })); sim:run(5)
    victim(sim, cl, B, gid, A, { k = "N", why = "forged" })
  end)

  -- My engine plays my own blinds (newGame uses my s.opt): the host's blinds and every call
  -- after them are other chips on its state than on mine. The outcome is asserted, not the
  -- refusal: my claim-free debt is never confirmed against the host's amount.
  it("a start with the host's blinds above mine (H18b)", function()
    local sim, cl = cash({ 1, 2 })
    local host, got = cl[A], outs(cl)
    local hs = host.session
    hands(sim, host, 1)
    setTook(cl, {}) -- the first game settles nothing
    close(sim, host)
    hs.opt.blinds = 20 -- the modified host's next game is at the next blind level
    assert(host:startGame()); sim:run(1)
    eq({ hs.state.bb, cl[B].session.state.bb }, { 20, 10 })
    for _, name in ipairs({ A, B }) do ok(cl[name]:act{ k = "buy", n = 1000 }); sim:run(1) end
    for _ = 1, 20 do -- hands until Петър owes Иван on his own state
      calm(sim, host)
      if HC.net(cl[B].session.state.cash, 1, 2) > 0 then break end
    end
    ok(HC.net(cl[B].session.state.cash, 1, 2) > 0, "Петър owes Иван on his own state")
    local was = #got[A]
    close(sim, host)
    sim:run(C.STAKE_OWE_WAIT)
    local gid
    for i = was + 1, #got[A] do gid = gid or got[A][i].gid end
    ok(gid, "the host's close")
    if cl[B].session.stakeFoul ~= "forged" then
      victim(sim, cl, B, gid, A, { k = "N", why = "amount" })
    else
      victim(sim, cl, B, gid, A, { k = "N", why = "forged" })
    end
  end)

  it("an accomplice with chips it never bought costs me only what my matrix says (C6)", function()
    local sim, cl = cash({ 1, 2, 3 }, nil, { [3] = false })
    local host, got = cl[A], outs(cl)
    host.session:play(3, { k = "buy", n = 1000 }) -- Мария's chips: her client sent no buy (she is in it)
    sim:run(1)
    hands(sim, host, 1)
    local hs = host.session
    for _ = 1, 6 do -- hands Мария wins from Петър: he calls her first raise and folds to the next; Иван folds
      if HC.net(cl[B].session.state.cash, 3, 2) > 0 then break end
      inHand(sim, host)
      local hand, called = hs.state.hand, false
      for _ = 1, 300 do
        local st = hs.state
        if not (E.inHand(st) and st.hand == hand) then break end
        local t = st.phase == "bet" and st.turn
        if t == 3 then cl[M]:act(st.bet == 0 and { k = "bet", to = st.bb } or { k = "raise", to = st.bet + st.minRaise })
        elseif t == 1 then cl[A]:act{ k = "fold" }
        elseif t == 2 and st.bet > st.p[2].bet then cl[B]:act{ k = called and "fold" or "call" }; called = true
        elseif t then cl[ALL[t]]:act{ k = "check" } end
        sim:run(1)
      end
    end
    local mine = U.copy(cl[B].session.state.cash)
    ok(HC.net(mine, 3, 2) > 0, "Петър owes Мария")
    close(sim, host)
    local gid = gidOf(got[A], "close")
    for _, j in ipairs({ 1, 3 }) do
      local n = HC.net(mine, j, 2)
      if n > 0 then
        honest(sim, cl, B, gid, ALL[j])
        for _, e in ipairs(Play.entries(sim, B, "D")) do if e.gid == gid and e.t == ALL[j] then eq(e.c, n * 100) end end
      end
    end
  end)
end)

describe("a modified host at a cash table: the snapshot and the book", function()
  it("a re-sit while my record still leaves the hand is a question (Task 5); after the hand it is clean", function()
    for _, cheat in ipairs({ false, true }) do
      local sim, cl, tid = cash({ 1, 2, 3, 4 })
      local host, got = cl[A], outs(cl)
      local hs = host.session
      hands(sim, host, 1)
      till(sim, host, function(st) return st.phase == "bet" and U.contains(E.players(st), 2) and E.dealer(st) ~= 2 end)
      cl[B]:stand(true); sim:run(1) -- at once, mid-hand (core/CashOut.lua)
      eq(E.inHand(hs.state) and hs.state.seats[2].leaving, true)
      if not cheat then calm(sim, host) end
      cl[B]:sit(tid, 5, SK); sim:run(1)
      eq(cl[B].session.stakeFoul, cheat and "unseen" or nil)
      if cheat then calm(sim, host) end -- no buy while my old record leaves the hand ("hand")
      ok(cl[B]:act{ k = "buy", n = 1000 }); sim:run(1)
      hands(sim, host, 1)
      setTook(cl, { [1] = { [5] = 40 } })
      close(sim, host)
      local gid = gidOf(got[A], "close")
      if cheat then victim(sim, cl, B, gid, A, "ask") else honest(sim, cl, B, gid, A) end
    end
  end)

  it("a renamed seat in a snapshot of my very state: forged from my host, a question from a new one", function()
    for _, how in ipairs({ "honest", "mine", "new" }) do
      local sim, cl = cash({ 1, 2, 3 })
      local host, got = cl[A], outs(cl)
      local hs = host.session
      hands(sim, host, 1)
      inHand(sim, host)
      local m = ns.Session.message("SNP", { tid = hs.tid, e = hs.epoch, q = hs.seq, tbl = hs:record(), st = U.copy(hs:snapshotFor(B)),
        left = hs:left(), inv = hs:invitedList(), fr = hs:hook("snap") })
      local from = A
      if how ~= "honest" then m.tbl.s[3] = G end
      if how == "new" then from, m.tbl.h, m.tbl.e, m.e = M, M, hs.epoch + 1, hs.epoch + 1 end
      cl[B]:receive("WHISPER", from, m); sim:run(0)
      eq(cl[B].session.stakeFoul, ({ honest = nil, mine = "forged", new = "unseen" })[how])
      calm(sim, host)
      setTook(cl, { [1] = { [2] = 40 } })
      close(sim, host)
      local gid = gidOf(got[A], "close")
      if how == "honest" then honest(sim, cl, B, gid, A)
      elseif how == "mine" then victim(sim, cl, B, gid, A, { k = "N", why = "forged" })
      else victim(sim, cl, B, gid, A, "ask") end
    end
  end)

  it("other blinds or another rebuy mode in my host's snapshot: forged", function()
    for _, mutate in ipairs({ function(st) st.bb = 20 end, function(st) st.cash.rebuy = "top" end, function(st) st.sb = st.bb end }) do
      local sim, cl = cash({ 1, 2, 3 })
      local host, got = cl[A], outs(cl)
      hands(sim, host, 1)
      local r = rig(sim, host, B)
      r.push(mutate)
      r.stop()
      eq(cl[B].session.stakeFoul, "forged")
      hands(sim, host, 1)
      setTook(cl, { [1] = { [2] = 40 } })
      close(sim, host)
      victim(sim, cl, B, gidOf(got[A], "close"), A, { k = "N", why = "forged" })
    end
  end)

  it("a host that starts the next game before the last one's keys are out: asked, never confirmed", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    local take = ns.Book.take
    patched(ns.Book, "take", function(s, seat, a) -- Мария's key is late: an honest host waits for it
      if s.client == host and seat == 3 then return end
      return take(s, seat, a)
    end, function() assert(ns.Cash.close(host)); sim:run(3) end)
    local gid = gidOf(got[A], "close")
    host.session.book.published = true -- the modified host does not wait
    assert(host:startGame()); sim:run(C.BOOK_WAIT + 5)
    victim(sim, cl, B, gid, A, "ask")
  end)

  -- I1 (Task 9 review): the small blind is pinned like the big one. Мария sits into the running
  -- game; the host's snapshot to her carries sb (the honest one: half the big blind).
  it("the small blind in the snapshot of my sit: the host's sb = bb is forged; the honest one is clean", function()
    for _, cheat in ipairs({ false, true }) do
      local sim, cl, tid = cash({ 1, 2 })
      local host, got = cl[A], outs(cl)
      hands(sim, host, 1)
      if cheat then
        host.session.state.sb, cl[B].session.state.sb = 10, 10
        sim.bus.filter = function(from, to, _, m)
          if from == A and to == M and m.t == "SNP" and type(m.st) == "table" then
            local x = U.copy(m)
            x.st.sb = 10
            return { x }
          end
          return { m }
        end
      end
      cl[M]:sit(tid, 3, SK); sim:run(1)
      sim.bus.filter = nil
      eq(cl[M].session.stakeFoul, cheat and "forged" or nil)
      assert(cl[M]:act{ k = "buy", n = 1000 }); sim:run(1)
      hands(sim, host, 1)
      setTook(cl, { [1] = { [3] = 40 } })
      close(sim, host)
      local gid = gidOf(got[A], "close")
      if cheat then victim(sim, cl, M, gid, A, { k = "N", why = "forged" }) else honest(sim, cl, M, gid, A) end
    end
  end)

  it("a host that waits for the keys before the next game: confirmed (the honest twin)", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    close(sim, host)
    local gid = gidOf(got[A], "close")
    assert(host:startGame()); sim:run(C.STAKE_OWE_WAIT + 5)
    honest(sim, cl, B, gid, A)
  end)

  it("the same host pushes me a finished game with a different end: forged, a contest", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    local r = rig(sim, host, B)
    assert(ns.Cash.close(host)); sim:run(1)
    ok(E.over(cl[B].session.state), "the game is over on my client")
    r.push(function(st) st.hand = st.hand + 1 end)
    r.stop()
    eq(cl[B].session.stakeFoul, "forged")
    sim:run(C.BOOK_WAIT + 5)
    sim:run(C.STAKE_OWE_WAIT + 5)
    victim(sim, cl, B, gidOf(got[A], "close"), A, { k = "N", why = "forged" })
  end)

  it("a forged S record of the host changes no balance and no note", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 40 } })
    close(sim, host)
    sim:run(C.STAKE_OWE_WAIT + 5)
    local gid = gidOf(got[A], "close")
    local function state()
      local out = {}
      for name, c in pairs(cl) do
        local v = ns.LedgerView.of(c.ledger)
        local keys = {}
        for g, n in pairs(c.stakes:seen()) do keys[#keys + 1] = g .. ":" .. tostring(n.foul) .. ":" .. tostring(n.wait) end
        table.sort(keys)
        out[name] = { ns.LedgerView.net(v, B, A), ns.LedgerView.net(v, A, B), ns.LedgerView.net(v, M, A), keys }
      end
      return out
    end
    local before = state()
    ok(host.ledgerNet:make("S", { gid = gid, g = "holdem", f = B, c = 80000, sk = SK,
      n = { A, B, false, false, false, false }, w = { 1 }, l = {}, why = "left" }))
    sim:run(C.LEDGER_COALESCE + 5)
    eq(state(), before)
  end)

  it("my one buy in top mode played twice by the host: forged", function()
    local sim, cl = cash({ 1, 2, 3 }, { blinds = 10, rebuy = "top" }, { [2] = false })
    local hs = cl[A].session
    assert(cl[B]:act{ k = "buy", n = 500 }); sim:run(1)
    eq(hs.state.seats[2].bought, 500)
    eq(cl[B].session.stakeFoul, nil)
    hs:play(2, { k = "buy", n = 500 }); sim:run(1)
    eq(cl[B].session.stakeFoul, "forged")
  end)

  it("a key withheld (E6): every player dealt in with it is asked", function()
    local sim, cl = cash({ 1, 2, 3 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    local take = ns.Book.take
    patched(ns.Book, "take", function(s, seat, a) -- the host never publishes Мария's key
      if s.client == host and seat == 3 then return end
      return take(s, seat, a)
    end, function()
      setTook(cl, { [1] = { [2] = 40 } })
      close(sim, host)
    end)
    ok(host.session.book.final and #host.session.book.missing == 1, "the book ended without Мария's key")
    victim(sim, cl, B, gidOf(got[A], "close"), A, "ask")
  end)
end)
