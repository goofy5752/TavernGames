local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, E, Stakes, U = ns.Const, ns.Engines.holdem, ns.Stakes, ns.Util

-- Stage F3, Task 7: a seat's settlement becomes pair debts that wait for the
-- book (core/StakesCashOwe.lua).
local restore = Play.staked("holdem")
local A, B, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local K, N6 = Play.MORE[1], Play.MORE[2]
local ALL = { A, B, M, G, K, N6 } -- the name of chair i
local SK = 1000 -- blinds 10: the big blind of 10 chips of one silver

-- A guild of the six names of ALL; Иван opens a staked Холдем (blinds 10, turn 30), the
-- names of `chairs` sit in their chairs, Иван starts, and every chair c buys buys[c]
-- chips (default 1000; false: no buy) -> sim, cl, tid (tests/core/stakes_cash_table_test.lua).
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
-- turn checking or calling from its own client (E.bot goes all in: the table would bust).
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

-- n hands played out at host's table.
local function hands(sim, host, n)
  for _ = 1, n do calm(sim, host) end
end

-- The "cashout" events of every client of cl (name -> list); a client made later is added by watch(got, name, client).
local function watch(got, name, client)
  got[name] = got[name] or {}
  client:on("cashout", function(v) table.insert(got[name], v) end)
end
local function outs(cl)
  local got = {}
  for name, c in pairs(cl) do watch(got, name, c) end
  return got
end

-- Every client at the table holds the matrix `took` (seat -> seat -> chips; the same on every state).
local function setTook(cl, took)
  for _, c in pairs(cl) do
    local st = c.session and c.session.state
    if st and st.cash then st.cash.took = U.copy(took) end
  end
end

-- The host's „Приключи“ between hands, the hand played out if one runs, the keys out and checked.
local function close(sim, host)
  assert(ns.Cash.close(host))
  sim:run(1)
  if E.inHand(host.session.state) then calm(sim, host) end
  sim:run(C.BOOK_WAIT + 5)
end

-- The gid of the first "cashout" event in list with `why` (any: nil).
local function gidOf(list, why, seat)
  for _, v in ipairs(list) do
    if (why == nil or v.why == why) and (seat == nil or v.seat == seat) then return v.gid end
  end
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

-- What `debtor` said about its debt gid|debtor|t: {kind, why} of its own D (k "D", why "cash"),
-- its C or N on a claim of that debt, in the order sent.
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

-- Is the debt key among client's asks -> bool.
local function asked(client, key)
  for _, d in ipairs(client.stakes:asks()) do if d.key == key then return true end end
  return false
end

-- Seat i has a pair in the matrix of state st -> bool.
local function paired(st, i)
  for j = 1, 9 do if j ~= i and ns.HoldemCash.net(st.cash, i, j) ~= 0 then return true end end
  return false
end

-- Hands until Мария (seat 3) has a pair, at least `least` -> the host's state copied right after.
local function playUntilPaired(sim, host, least)
  for n = 1, 20 do
    hands(sim, host, 1)
    if n >= least and paired(host.session.state, 3) then return U.copy(host.session.state) end
  end
  error("Мария never has a pair")
end

-- f() with t[k] = v, t[k] given back after it, even when f fails (the failure raised again).
local function patched(t, k, v, f)
  local was = t[k]
  t[k] = v
  local done, err = pcall(f)
  t[k] = was
  if not done then error(err, 0) end
end

-- Seat of `name` in ALL.
local function seatOf(name) for i, n in ipairs(ALL) do if n == name then return i end end end

describe("a cash settlement becomes pair debts", function()
  it("a cashout: the pairs owe by the matrix, to the copper", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    local before = playUntilPaired(sim, host, 3)
    ok(cl[M]:act{ k = "cashout" }); sim:run(3)
    for _, name in ipairs({ A, B, M }) do eq(#got[name], 1, name) end
    local v = got[A][1]
    eq({ v.seat, v.name, v.bought, v.why }, { 3, M, 1000, nil })
    for _, name in ipairs({ B, M }) do eq({ got[name][1].gid, got[name][1].pairs }, { v.gid, v.pairs }, name) end
    ok(#v.pairs > 0, "Мария has a pair")
    local w, l = {}, {}
    for j = 1, 3 do
      local n = ns.HoldemCash.net(before.cash, 3, j)
      if j ~= 3 and n > 0 then w[#w + 1] = j elseif j ~= 3 and n < 0 then l[#l + 1] = j end
    end
    for _, p in ipairs(v.pairs) do
      local other = p.f == M and p.t or p.f
      local n = ns.HoldemCash.net(before.cash, 3, seatOf(other))
      eq(p.c, math.abs(n) * 100)
      eq({ p.f, p.t }, n > 0 and { other, M } or { M, other })
      local ds = {}
      for _, e in ipairs(Play.entries(sim, p.t, "D")) do if e.gid == v.gid and e.f == p.f then ds[#ds + 1] = e end end
      eq(#ds, 1, p.t); eq({ ds[1].why, ds[1].c }, { "lost", p.c })
    end
    local S = Play.entries(sim, A, "S")
    eq(#S, 1)
    eq({ S[1].gid, S[1].f, S[1].c, S[1].sk, S[1].w, S[1].l, S[1].why }, { v.gid, M, 1000 * 100, SK, w, l, nil })
    eq(S[1].n[3], M)
    eq(#Play.entries(sim, B, "S") + #Play.entries(sim, M, "S"), 0)
  end)

  it("the sum by pairs is the total result", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    local before = playUntilPaired(sim, host, 2)
    ok(cl[M]:act{ k = "cashout" }); sim:run(1)
    local sum = 0
    for _, p in ipairs(got[M][1].pairs) do sum = sum + (p.t == M and p.c or -p.c) end
    local seat = before.seats[3]
    eq(seat.cleared, 0)
    eq(sum, (seat.chips - seat.bought) * 100)
  end)

  it("the debts wait for the book and confirm at the close", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    playUntilPaired(sim, host, 3)
    ok(cl[M]:act{ k = "cashout" }); sim:run(5)
    local v = got[A][1]
    ok(#v.pairs > 0)
    for _, p in ipairs(v.pairs) do
      eq(Play.debt(cl[p.f], v.gid, p.f, p.t).status, "pending")
      for _, name in ipairs({ A, B, M }) do eq(asked(cl[name], v.gid .. "|" .. p.f .. "|" .. p.t), false, name) end
      eq(words(sim, p.f, v.gid, p.t), {})
    end
    setTook(cl, { [1] = { [2] = 20 } }) -- something to settle at the close: Петър owes Иван 20 chips
    close(sim, host)
    local closing = gidOf(got[A], "close")
    ok(closing, "the close settled seats")
    local all = {}
    for _, x in ipairs(got[A]) do for _, p in ipairs(x.pairs) do all[#all + 1] = { x.gid, p } end end
    ok(#all > #v.pairs, "the close made a debt")
    for _, gp in ipairs(all) do
      local gid, p = gp[1], gp[2]
      for _, name in ipairs({ A, B, M }) do eq(Play.debt(cl[name], gid, p.f, p.t).status, "confirmed", name .. " " .. gid) end
      eq(words(sim, p.f, gid, p.t), { { k = "D", why = "cash" } })
    end
    eq(#Play.entries(sim, nil, "C"), 0)
  end)

  it("a player who walks to the hall before the keys is asked (C1)", function()
    local sim, cl = Play.cash(4)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 2)
    setTook(cl, { [1] = { [4] = 30 } }) -- Гошо owes Иван 30 chips
    assert(ns.Cash.close(host)); sim:run(1)
    ok(E.over(host.session.state), "closed between hands")
    cl[G]:stand(); sim:run(5)
    local gid = gidOf(got[A], "close")
    local key = gid .. "|" .. G .. "|" .. A
    eq(Play.debt(cl[G], gid, G, A).status, "pending")
    ok(asked(cl[G], key), "put to Гошо")
    eq(cl[G].stakes:seen()[gid].foul, "unseen")
    sim:run(C.BOOK_WAIT + 5)
    eq(Play.debt(cl[A], gid, G, A).status, "pending") -- the keys do not answer for him
    ok(cl[G].stakes:answer(key, true)); sim:run(3)
    eq(words(sim, G, gid, A), { { k = "D", why = "cash" } })
    eq(Play.debt(cl[A], gid, G, A).status, "confirmed")
  end)

  it("a /reload mid-game asks only the player that reloaded", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    inHand(sim, host)
    sim:run(1)
    cl[M] = sim:relog(M); sim:run(3)
    watch(got, M .. "+", cl[M])
    eq(cl[M].session.stakeFoul, "unseen")
    calm(sim, host)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 20, [3] = 30 } }) -- Петър owes Иван 20, Мария 30
    close(sim, host)
    local gid = gidOf(got[A], "close")
    eq(gidOf(got[M .. "+"], "close"), gid)
    eq(Play.debt(cl[A], gid, B, A).status, "confirmed")
    eq(words(sim, B, gid, A), { { k = "D", why = "cash" } })
    eq(Play.debt(cl[A], gid, M, A).status, "pending")
    ok(asked(cl[M], gid .. "|" .. M .. "|" .. A), "put to Мария")
    eq(words(sim, M, gid, A), {})
    eq(asked(cl[B], gid .. "|" .. B .. "|" .. A), false)
  end)

  it("a claim with another amount is contested", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 20 } }) -- Петър owes Иван 20 chips
    local net = cl[A].ledgerNet
    local make = net.make
    net.make = function(self, kind, f) -- Иван's modified client claims 1s more
      if kind == "D" then f.c = f.c + 100 end
      return make(self, kind, f)
    end
    close(sim, host)
    local gid = gidOf(got[A], "close")
    eq(words(sim, B, gid, A), { { k = "N", why = "amount" } })
  end)

  it("a claim that names another game: my word is still my own D of the cash game (M1)", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 20 } }) -- Петър owes Иван 20 chips
    local net = cl[A].ledgerNet
    local make = net.make
    net.make = function(self, kind, f) -- Иван's modified client names a fun game in its claim
      if kind == "D" then f.g = "tabla" end
      return make(self, kind, f)
    end
    close(sim, host)
    local gid = gidOf(got[A], "close")
    eq(words(sim, B, gid, A), { { k = "D", why = "cash" } })
    local own
    for _, e in ipairs(Play.entries(sim, B, "D")) do if e.gid == gid and e.f == B then own = e end end
    eq(own and own.g, "holdem")
    eq(#Play.entries(sim, nil, "C"), 0)
  end)

  it("a claim from a player I owe nothing is contested", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 20 } }) -- Петър owes Иван 20 chips, Мария nothing
    close(sim, host)
    local gid = gidOf(got[A], "close")
    eq(words(sim, B, gid, A), { { k = "D", why = "cash" } })
    ok(cl[M].ledgerNet:make("D", { gid = gid, g = "holdem", f = B, t = M, c = 2000, why = "lost" })); sim:run(6)
    eq(words(sim, B, gid, M), { { k = "N", why = "no" } })
  end)

  it("a pre-planted claim at the next event's gid is not confirmed before the book", function()
    local sim, cl, tid = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [3] = 25 } }) -- Мария owes Иван 25 chips
    local gid = tid .. "/" .. (host.session.seq + 1)
    local e = assert(cl[A].ledgerNet:make("D", { gid = gid, g = "holdem", f = M, t = A, c = 2500, why = "lost" }))
    eq(cl[M].ledgerNet:take(ns.Ledger.wire(e), A, true), "new") -- in Мария's ledger before the event
    ok(cl[M]:act{ k = "cashout" }); sim:run(5)
    eq(got[M][1].gid, gid)
    eq(words(sim, M, gid, A), {})
    eq(Play.debt(cl[A], gid, M, A).status, "pending")
    eq(asked(cl[M], gid .. "|" .. M .. "|" .. A), false)
    close(sim, host)
    eq(words(sim, M, gid, A), { { k = "D", why = "cash" } })
    eq(Play.debt(cl[A], gid, M, A).status, "confirmed")
  end)

  it("a hand with a missing key: its players are asked, the others confirm (E6)", function()
    local sim, cl = cash({ 1, 2, 3, 4 }, { [4] = false })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 2) -- Иван, Петър and Мария; Гошо sits out without chips
    setTook(cl, { [3] = { [1] = 10 } }) -- Иван owes Мария 10 chips
    ok(cl[M]:act{ k = "cashout" }); sim:run(1)
    local take = ns.Book.take
    patched(ns.Book, "take", function(s, seat, a) -- the host never publishes Мария's key
      if s.client == host and seat == 3 then return end
      return take(s, seat, a)
    end, function()
      ok(cl[G]:act{ k = "buy", n = 1000 }); sim:run(1)
      hands(sim, host, 2) -- Иван, Петър and Гошо
      setTook(cl, { [1] = { [4] = 20 }, [4] = { [2] = 10 } }) -- Гошо owes Иван 20, Петър owes Гошо 10
      close(sim, host)
    end)
    local out, closing = gidOf(got[A], nil, 3), gidOf(got[A], "close")
    ok(host.session.book.final and #host.session.book.missing == 1, "the book ended without Мария's key")
    eq(Play.debt(cl[A], closing, G, A).status, "confirmed")
    eq(words(sim, G, closing, A), { { k = "D", why = "cash" } })
    eq(Play.debt(cl[B], closing, B, G).status, "pending")
    ok(asked(cl[B], closing .. "|" .. B .. "|" .. G), "put to Петър")
    eq(cl[B].stakes:seen()[closing].foul, "unseen")
    eq(Play.debt(cl[A], out, A, M).status, "pending")
    ok(asked(cl[A], out .. "|" .. A .. "|" .. M), "put to Иван")
  end)

  it("a hand that closes bad contests", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    local hs, liar = host.session, nil
    for _ = 1, 6 do -- a hand dealt by another seat than the host's
      inHand(sim, host)
      for _ = 1, 20 do if hs.state.phase == "bet" then break end sim:run(1) end
      local d = E.dealer(hs.state)
      if d ~= 1 then liar = cl[ALL[d]]; break end
      calm(sim, host)
    end
    ok(liar, "a dealer that is not the host")
    local submit, idx, face = ns.Cash.submit, nil, nil
    patched(ns.Cash, "submit", function(s, a) -- the dealer's modified client gives a false river, and holds to it at the showdown
      local step = s.client == liar and a.k == "book" and a.op == "step" and type(a.a) == "table" and a.a
      if step and step.k == "street" and #s.state.board == 4 then
        idx, face = next(step.cards), s.fair.deck[52]
        step.cards[idx] = face
      elseif step and step.k == "showdown" and idx then
        step.cards[idx] = face
      end
      return submit(s, a)
    end, function()
      for _ = 1, 200 do -- every seat checks or calls to the showdown
        local st = hs.state
        if not E.inHand(st) then break end
        if st.phase == "bet" and st.turn then
          cl[ALL[st.turn]]:act{ k = st.bet > st.p[st.turn].bet and "call" or "check" }
        end
        sim:run(1)
      end
    end)
    ok(idx, "the river was false")
    setTook(cl, { [1] = { [2] = 20, [3] = 30 } }) -- Петър and Мария owe Иван
    close(sim, host)
    ok(hs.book.seen.bad > 0, "the book found the river false")
    local gid = gidOf(got[A], "close")
    eq(words(sim, B, gid, A), { { k = "N", why = "deal" } })
    eq(words(sim, M, gid, A), { { k = "N", why = "deal" } })
  end)

  it("an unclaimed debt of an unseen note is put to me", function()
    local sim, cl = cash({ 1, 2, 3, 4 })
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    cl[M] = sim:relog(M); sim:run(3) -- Мария's notes of this game are unseen
    watch(got, M .. "+", cl[M])
    calm(sim, host)
    local book = cl[B].stakes
    local make = book.make
    book.make = function(self, key, kind, f) -- Петър's client is gone: it writes no claim
      if kind == "D" and f.t == B then return nil end
      return make(self, key, kind, f)
    end
    setTook(cl, { [2] = { [3] = 15, [4] = 12 } }) -- Мария owes Петър 15, Гошо 12
    ok(cl[M]:act{ k = "cashout" }); ok(cl[G]:act{ k = "cashout" }); sim:run(1)
    local gm, gg = gidOf(got[A], nil, 3), gidOf(got[A], nil, 4)
    sim:run(C.STAKE_OWE_WAIT + 10)
    eq(cl[M].stakes:owing(), {}) -- waiting for the book
    eq(words(sim, G, gg, B), {})
    close(sim, host)
    eq(words(sim, G, gg, B), { { k = "D", why = "cash" } }) -- clean and checked after STAKE_OWE_WAIT: by itself
    eq(Play.debt(cl[B], gg, G, B).status, "confirmed")
    local key = gm .. "|" .. M .. "|" .. B
    eq(cl[M].stakes:owing(), { { gid = gm, t = B, c = 1500, key = key } })
    eq(words(sim, M, gm, B), {})
    ok(cl[M].stakes:admit(key, true)); sim:run(3)
    eq(words(sim, M, gm, B), { { k = "D", why = "cash" } })
    eq(Play.debt(cl[B], gm, M, B).status, "confirmed")
    eq(cl[M].stakes:owing(), {})
    eq(cl[M].stakes:admit(key, true), nil)
  end)

  it("a settlement my client saw only in a snapshot writes no note", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [3] = { [2] = 10 } }) -- Петър owes Мария 10 chips
    sim.bus.filter = function(_, to, _, m)
      if to == B and m.t == "EV" and type(m.a) == "table" and m.a.k == "cashout" then return {} end
      return { m }
    end
    ok(cl[M]:act{ k = "cashout" }); sim:run(1)
    sim.bus.filter = nil
    cl[B].session:requestSync(); sim:run(5)
    eq(cl[B].session.state.seats[3].bought, 0)
    local gid = gidOf(got[A], nil, 3)
    eq(#got[B], 0)
    eq(cl[B].stakes:seen()[gid], nil)
    ok(asked(cl[B], gid .. "|" .. B .. "|" .. M), "the claim is put to Петър")
    eq(words(sim, B, gid, M), {})
  end)

  it("nothing is written at a bot table", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    for _, env in pairs(sim.envs) do env.noLedger = function() return true end end
    hands(sim, host, 1)
    setTook(cl, { [1] = { [3] = 10 } })
    local from = #entries(sim)
    ok(cl[M]:act{ k = "cashout" }); sim:run(5)
    eq(#got[A], 1)
    eq(#entries(sim), from)
    eq(cl[M].stakes:seen()[got[A][1].gid], nil)
  end)

  it("a newcomer on a leaving chair owes nothing of the leaver's hand (H1)", function()
    local sim, cl, tid = cash({ 1, 2, 3, 4 })
    local host, got = cl[A], outs(cl)
    local hs = host.session
    for _ = 1, 6 do
      inHand(sim, host)
      if U.contains(E.players(hs.state), 4) then break end
      calm(sim, host)
    end
    ok(U.contains(E.players(hs.state), 4), "Гошо is dealt in")
    setTook(cl, { [4] = { [1] = 10 } }) -- Иван owes Гошо 10 chips (and the hand adds its own)
    cl[G]:stand(true); sim:run(1) -- at once, mid-hand (core/CashOut.lua)
    cl[K]:sit(tid, 4, SK); sim:run(1)
    watch(got, K, cl[K])
    ok(hs.state.seats[4].leaving and hs.state.seats[4].takenWho == K, "Kiro takes the leaving chair")
    calm(sim, host); sim:run(3)
    local gid = gidOf(got[A], nil, 4)
    ok(gid, "Гошо's record")
    for _, name in ipairs({ A, B, M, K }) do
      local v
      for _, x in ipairs(got[name]) do if x.gid == gid then v = x end end
      ok(v, name)
      eq({ v.seat, v.name, v.why }, { 4, G, "left" }, name)
      ok(#v.pairs > 0, name)
      for _, p in ipairs(v.pairs) do ok(p.f == G or p.t == G, name); ok(p.f ~= K and p.t ~= K, name) end
    end
    local S
    for _, e in ipairs(Play.entries(sim, A, "S")) do if e.gid == gid then S = e end end
    eq({ S.f, S.n[4], S.why }, { G, G, "left" })
    eq(cl[K].stakes:seen()[gid].pairs, {}) -- Kiro applied it: a note that owes nobody (I1)
    for _, e in ipairs(Play.entries(sim, K, "D")) do ok(e.gid ~= gid, "Kiro writes no D for Гошо's hand") end
    ok(cl[K]:act{ k = "buy", n = 1000 }); sim:run(1)
    setTook(cl, { [1] = { [4] = 5 } }) -- Kiro owes Иван 5 chips
    ok(cl[K]:act{ k = "cashout" }); sim:run(1)
    local mine = got[K][#got[K]]
    eq({ mine.seat, mine.name, mine.pairs }, { 4, K, { { f = K, t = A, c = 500 } } })
  end)

  it("the close at three seats: seat 3's note holds both pairs (H3)", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [3] = 20 }, [2] = { [3] = 10 } }) -- Мария owes Иван 20 and Петър 10
    close(sim, host)
    local gid = gidOf(got[A], "close")
    local pairs = cl[M].stakes:seen()[gid].pairs
    table.sort(pairs, function(x, y) return x.t < y.t end)
    local want = { { f = M, t = A, c = 2000 }, { f = M, t = B, c = 1000 } }
    table.sort(want, function(x, y) return x.t < y.t end)
    eq(pairs, want)
    eq(Play.debt(cl[A], gid, M, A).status, "confirmed")
    eq(Play.debt(cl[A], gid, M, B).status, "confirmed")
  end)

  it("a claim from a creditor my note has no pair for (H13)", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    cl[M] = sim:relog(M); sim:run(3) -- Мария's note is unseen
    calm(sim, host)
    setTook(cl, { [1] = { [2] = 20 }, [3] = { [1] = 10 } }) -- Петър owes Иван 20, Иван owes Мария 10
    close(sim, host)
    local gid = gidOf(got[A], "close")
    eq(words(sim, B, gid, A), { { k = "D", why = "cash" } }) -- a claim with a pair of mine: F1's judge
    -- Clean and checked, no pair for the creditor: contested, even at exactly 1 BB.
    ok(cl[M].ledgerNet:make("D", { gid = gid, g = "holdem", f = B, t = M, c = SK, why = "lost" }))
    -- Иван's note has no pair in which he owes Петър.
    ok(cl[B].ledgerNet:make("D", { gid = gid, g = "holdem", f = A, t = B, c = SK, why = "lost" }))
    -- Unseen, no pair for the creditor: asked (not "amount").
    ok(cl[B].ledgerNet:make("D", { gid = gid, g = "holdem", f = M, t = B, c = 2 * SK, why = "lost" }))
    sim:run(6)
    eq(words(sim, B, gid, M), { { k = "N", why = "no" } })
    eq(words(sim, A, gid, B), { { k = "N", why = "no" } })
    eq(words(sim, M, gid, B), {})
    ok(asked(cl[M], gid .. "|" .. M .. "|" .. B), "put to Мария")
  end)

  it("a bad hand I was not dealt into reads unseen, one with me in it reads deal (H16a)", function()
    local sim, cl, tid = cash({ 1, 2, 3, 4 }, { [4] = false })
    local host, got = cl[A], outs(cl)
    local hs = host.session
    inHand(sim, host)
    for _ = 1, 20 do if hs.state.phase == "bet" then break end sim:run(1) end
    ok(not U.contains(E.players(hs.state), 4), "Гошо sits out")
    for _ = 1, 20 do -- to the flop
      if hs.state.phase == "street" then break end
      local st = hs.state
      if st.phase == "bet" and st.turn then cl[ALL[st.turn]]:act{ k = st.bet > st.p[st.turn].bet and "call" or "check" } end
      sim:run(1)
    end
    eq(hs.state.phase, "street")
    if hs.stepTimer then hs.stepTimer.cancel(); hs.stepTimer = nil end
    hs:play(0, { k = "street", cards = {} }); sim:run(1) -- a street without its faces: the hand closes bad
    calm(sim, host)
    eq(cl[B].session.stakeFoul, "deal")
    eq(cl[G].session.stakeFoul, nil) -- Гошо was not dealt into it
    cl[K]:sit(tid, 5, SK); sim:run(1) -- a hand closed bad before Kiro's sit
    watch(got, K, cl[K])
    ok(cl[G]:act{ k = "buy", n = 1000 }); ok(cl[K]:act{ k = "buy", n = 1000 }); sim:run(1)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 20, [4] = 10, [5] = 5 } }) -- Петър, Гошо and Kiro owe Иван
    close(sim, host)
    local gid = gidOf(got[A], "close")
    eq(cl[G].stakes:seen()[gid].foul, "unseen")
    -- Kiro sat after the bad hand closed: his book never heard of it (a snapshot carries no bad hand), and it holds none of his chips.
    eq(cl[K].stakes:seen()[gid].foul, nil)
    eq(cl[B].stakes:seen()[gid].foul, "deal")
    eq(words(sim, B, gid, A), { { k = "N", why = "deal" } })
    eq(words(sim, G, gid, A), {})
    ok(asked(cl[G], gid .. "|" .. G .. "|" .. A), "put to Гошо")
  end)

  it("a stand I hear of only by SNO \"gone\" leaves an open note without a stake, beside my note of that event", function()
    local sim, cl = Play.cash(3)
    local host = cl[A]
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 20 } }) -- Петър owes Иван 20 chips
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" and m.a and m.a.k == "stand" then return {} end
      return { m }
    end
    local bs = cl[B].session
    bs.stakeStood = true -- my stand was judged in this game already: the open note carries no foul
    local mine = { at = 1, tid = bs.tid, g = "holdem", sk = SK, q = bs.seq, why = "cash", pairs = {} }
    cl[B].stakes:seen(true)[bs.tid .. "/" .. bs.seq] = mine -- my note of the last event I applied
    local s = host.session
    ns.Succession.untrack(s, B)
    s:event(0, { k = "stand", seat = 2, why = "offline" }); s:recordChanged()
    local gid = s.tid .. "/" .. s.seq
    sim:run(C.PING_EVERY + 5)
    sim.bus.filter = nil
    eq(cl[B].session, nil)
    local seen = cl[B].env.db.stakeSeen
    eq(seen[bs.tid .. "/" .. bs.seq], mine)
    local open = seen[bs.tid .. "/" .. bs.seq .. "+open"]
    eq({ open.open, open.sk, open.foul }, { true, nil, nil })
    eq(Play.debt(cl[B], gid, B, A).status, "pending")
    eq(words(sim, B, gid, A), {}) -- not "amount" against a big blind
    ok(asked(cl[B], gid .. "|" .. B .. "|" .. A), "put to Петър")
  end)

  it("a host that starts the next game before the last one's keys are out: those notes are asked, never confirmed", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [2] = 20, [3] = 30 } }) -- Петър and Мария owe Иван
    local take = ns.Book.take
    patched(ns.Book, "take", function(s, seat, a) -- Петър's key is late: the host waits BOOK_WAIT for it
      if s.client == host and seat == 2 then return end
      return take(s, seat, a)
    end, function() assert(ns.Cash.close(host)); sim:run(3) end)
    local gid = gidOf(got[A], "close")
    ok(gid and not host.session.book.published, "no key is out yet")
    eq({ host:startGame() }, { nil, "book" }) -- an honest host waits for the keys
    local g = host.session.state.g
    host.session.book.published = true -- a modified one does not
    assert(host:startGame()); sim:run(C.BOOK_WAIT + 5)
    for _, name in ipairs({ B, M }) do ok(cl[name].session.state.g ~= g, name .. " plays the next game") end
    for _, name in ipairs({ B, M }) do
      eq(cl[name].stakes:seen()[gid].foul, "unseen", name)
      eq(Play.debt(cl[A], gid, name, A).status, "pending", name)
      ok(asked(cl[name], gid .. "|" .. name .. "|" .. A), name)
      eq(words(sim, name, gid, A), {}, name)
    end
  end)

  it("a claim at an event that settled only others: contested when clean, after the book (I1)", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    setTook(cl, { [1] = { [3] = 10 } }) -- Мария owes Иван 10 chips, Петър nobody
    ok(cl[M]:act{ k = "cashout" }); sim:run(3)
    local gid = gidOf(got[A], nil, 3)
    local note = cl[B].stakes:seen()[gid]
    eq({ note and note.pairs, note and note.wait }, { {}, true })
    ok(cl[M].ledgerNet:make("D", { gid = gid, g = "holdem", f = B, t = M, c = SK, why = "lost" })); sim:run(6)
    eq(words(sim, B, gid, M), {}) -- waiting for the book
    eq(asked(cl[B], gid .. "|" .. B .. "|" .. M), false)
    close(sim, host)
    eq(words(sim, B, gid, M), { { k = "N", why = "no" } })
    eq(Play.debt(cl[M], gid, B, M).status, "contested")
  end)

  it("a claim at an event that settled only others: asked when unseen (I1)", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    hands(sim, host, 1)
    cl[B] = sim:relog(B); sim:run(3) -- Петър's notes of this game are unseen
    calm(sim, host)
    setTook(cl, { [1] = { [3] = 10 } }) -- Мария owes Иван 10 chips, Петър nobody
    ok(cl[M]:act{ k = "cashout" }); sim:run(3)
    local gid = gidOf(got[A], nil, 3)
    eq(cl[B].stakes:seen()[gid].pairs, {})
    ok(cl[M].ledgerNet:make("D", { gid = gid, g = "holdem", f = B, t = M, c = SK, why = "lost" })); sim:run(6)
    close(sim, host)
    eq(words(sim, B, gid, M), {})
    ok(asked(cl[B], gid .. "|" .. B .. "|" .. M), "put to Петър")
  end)

  it("an open that replaces my dealt hand: its bad close is mine, deal (I2)", function()
    local sim, cl = Play.cash(3)
    local host, got = cl[A], outs(cl)
    local hs = host.session
    hands(sim, host, 1)
    inHand(sim, host)
    for _ = 1, 20 do if hs.state.phase == "bet" then break end sim:run(1) end
    ok(hs.fair and hs.fair.stage == "dealt" and U.contains(hs.fair.p, 2), "Петър's hand is dealt")
    eq(cl[B].session.stakeFoul, nil)
    if hs.fairTimer then hs.fairTimer.cancel(); hs.fairTimer = nil end
    -- A modified host opens a new round over the dealt hand, with the same players.
    hs:play(0, { k = "fair", op = "open", h = hs.seq + 1, d = E.dealer(hs.state), p = U.copy(hs.fair.p) }); sim:run(1)
    eq(cl[B].session.stakeFoul, "deal")
    for _ = 1, 300 do if not E.inHand(hs.state) then break end sim:run(1) end -- the hand that lost its round ends by itself
    ok(not E.inHand(hs.state), "the hand ended")
    setTook(cl, { [1] = { [2] = 20 } }) -- Петър owes Иван 20 chips
    close(sim, host)
    local gid = gidOf(got[A], "close")
    ok(gid, "the close settled seats")
    eq(words(sim, B, gid, A), { { k = "N", why = "deal" } })
  end)

  it("Stakes.cashPairs names the record's own names and leaves out a missing one", function()
    local rec = { seat = 2, who = B, net = { [1] = 5, [3] = -7, [4] = 2 }, names = { [1] = A, [3] = M } }
    eq(Stakes.cashPairs(rec), { { f = A, t = B, c = 500 }, { f = B, t = M, c = 700 } })
  end)
end)

restore()
