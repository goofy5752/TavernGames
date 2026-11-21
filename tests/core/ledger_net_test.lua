local Sim = require("sim")
local ns = Sim.ns
local Ledger, View, U = ns.Ledger, ns.LedgerView, ns.Util

local I, M, P = "Иван Петров", "Мария Колева", "Петър Иванов"
local GUILD = "МЕХАНАТА"
local EPOCH0 = 1700000000
local G1 = "Иван Петров#1700000000/12"
local H16 = "fedcba9876543210"

-- И, М and П in the guild, past the adoption window and the login queue.
local function setup()
  local sim = Sim.new()
  local i, m, p = sim:add(I), sim:add(M), sim:add(P)
  sim:run(1)
  sim:settle()
  return sim, i, m, p
end

-- Every emission of `event` on `client`, as a list of argument lists.
local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

-- The LEV messages `from` sent after sim.sent[mark], as sim.sent rows.
local function levs(sim, from, mark)
  local out = {}
  for j, s in ipairs(sim.sent) do
    if j > mark and s.from == from and s.msg.t == "LEV" then out[#out + 1] = s end
  end
  return out
end

-- The entries in the LEVs of `from` after mark.
local function shipped(sim, from, mark)
  local n = 0
  for _, s in ipairs(levs(sim, from, mark)) do n = n + #s.msg.ev end
  return n
end

-- A wire entry of `author` numbered n.
local function entry(author, n, kind, fields, at)
  local e = U.copy(fields)
  e.i, e.k, e.at = Ledger.id(author, n), kind, at or EPOCH0
  return e
end
local function pay(author, n, f, c) return entry(author, n, "P", { f = f, c = c, how = "hand" }) end

-- The X entries of the client's own name in its store.
local function xs(client)
  local out = {}
  for _, b in ipairs(client.ledger:above(client.env.me, 0)) do if b.k == "X" then out[#out + 1] = b end end
  return out
end

local function store(sim, name) return sim.envs[name].db.ledger[GUILD] end

-- A clean logout and login of `name`, its saved counter set to seq first; past the login queue.
local function veteran(sim, name, seq)
  store(sim, name).me[name].seq = seq
  sim.clients[name]:stop()
  local c = sim:relog(name)
  sim:run(1)
  sim:settle()
  return c
end

describe("ledger net: live entries", function()
  it("my entry reaches everyone online as one GUILD LEV", function()
    local sim, i, m, p = setup()
    local seen = { record(i, "ledger"), record(m, "ledger"), record(p, "ledger") }
    local mark = #sim.sent
    local e = i.ledgerNet:make("P", { f = M, c = 100, how = "hand" })
    eq(e.i, I .. ":1")
    sim:run(1); eq(#levs(sim, I, mark), 0)
    sim:run(1)
    local l = levs(sim, I, mark)
    eq(#l, 1); eq(l[1].channel, "GUILD"); eq(#l[1].msg.ev, 1); eq(l[1].msg.ev[1], Ledger.wire(e))
    for _, c in ipairs({ m, p }) do
      local b = c.ledger:get(e.i)
      ok(b, "not held"); eq(b.dr, true); eq(b.rl, nil); eq(b.h, e.h)
    end
    eq(#seen[1], 1); eq(#seen[2], 1); eq(#seen[3], 1)
  end)

  it("entries made within two seconds leave as one LEV", function()
    local sim, i, m = setup()
    local mark = #sim.sent
    i.ledgerNet:make("P", { f = M, c = 1, how = "hand" }); sim:run(1)
    i.ledgerNet:make("P", { f = M, c = 2, how = "hand" }); i.ledgerNet:make("P", { f = M, c = 3, how = "hand" })
    sim:run(1)
    local l = levs(sim, I, mark)
    eq(#l, 1); eq(#l[1].msg.ev, 3)
    sim:run(5); eq(#levs(sim, I, mark), 1)
    mark = #sim.sent
    for c = 4, 8 do i.ledgerNet:make("P", { f = M, c = c, how = "hand" }) end
    sim:run(2)
    l = levs(sim, I, mark)
    eq(#l, 2); eq(#l[1].msg.ev, 4); eq(#l[2].msg.ev, 1)
    eq(m.ledger:seen(I), 8)
  end)

  it("a live LEV must be all the sender's own", function()
    local sim, i, m, p = setup()
    p:send("GUILD", nil, { v = 1, t = "LEV", ev = { pay(I, 1, M, 5) } }); sim:run(1)
    eq(m.ledger:get(I .. ":1"), nil); eq(i.ledger:get(I .. ":1"), nil); eq(#xs(i), 0)
    p:send("GUILD", nil, { v = 1, t = "LEV", ev = { pay(P, 1, M, 5), pay(I, 2, M, 5) } }); sim:run(1)
    eq(m.ledger:get(P .. ":1"), nil)
    local five = {}
    for n = 1, 5 do five[n] = pay(P, n, M, n) end
    p:send("GUILD", nil, { v = 1, t = "LEV", ev = five }); sim:run(1)
    eq(m.ledger:seen(P), 0); eq(i.ledger:seen(P), 0)
    p:send("GUILD", nil, { v = 1, t = "LEV", ev = { five[1], five[2], five[3], five[4] } }); sim:run(1)
    eq(m.ledger:seen(P), 4)
  end)

  it("an invalid entry is dropped and the rest of the message is kept", function()
    local sim, _, m, p = setup()
    local bad = entry(P, 2, "D", { gid = G1, g = "ttt", f = M, t = P, c = 150, why = "lost" })
    p:send("GUILD", nil, { v = 1, t = "LEV", ev = { pay(P, 1, M, 5), bad } }); sim:run(1)
    ok(m.ledger:get(P .. ":1"), "the valid one is kept"); eq(m.ledger:get(P .. ":2"), nil)
  end)

  it("a relayed entry is marked; a direct copy clears the mark", function()
    local sim, i, m = setup()
    local seen = record(i, "ledger")
    local e = pay(M, 1, P, 5)
    eq(i.ledgerNet:take(e, P), "new")
    local b = i.ledger:get(M .. ":1")
    eq(b.rl, true); eq(b.dr, nil)
    sim:run(1); eq(#seen, 1)
    m:send("GUILD", nil, { v = 1, t = "LEV", ev = { e } }); sim:run(1)
    eq(b.dr, true); eq(b.rl, nil); eq(#seen, 2)
    eq(i.ledgerNet:take(e, P), "dup"); eq(b.dr, true); eq(b.rl, nil)
  end)

  it("an entry dated more than an hour ahead is refused", function()
    local sim, i = setup()
    local now = EPOCH0 + sim.clock
    eq(i.ledgerNet:take(entry(M, 1, "P", { f = P, c = 5, how = "hand" }, now + 3601), P), nil)
    eq(i.ledgerNet:take(entry(M, 1, "P", { f = P, c = 5, how = "hand" }, now + 3600), P), "new")
  end)

  it("a foreign author is taken only when it is a guild member or known", function()
    local sim, _, m, p = setup()
    local ghost, members = "Измислен Човек", { [I] = true, [M] = true, [P] = true }
    m.env.member = function(name) return members[name] == true end
    eq(m.ledgerNet:take(pay(ghost, 1, P, 5), P), nil)
    eq(m.ledgerNet:take(pay(P, 1, ghost, 5), P), nil)
    eq(m.ledgerNet:take(entry(P, 2, "D", { gid = G1, g = "ttt", f = ghost, t = P, c = 100, why = "lost" }), P), nil)
    eq(m.ledgerNet:take(entry(I, 1, "R", { gid = G1, g = "ttt", n = { I, ghost }, w = { 1 }, l = { 2 } }), P), nil)
    eq(m.ledgerNet:take(entry(I, 1, "R", { gid = G1, g = "ttt", n = { I, false, P }, w = { 1 }, l = { 3 } }), P), "new")
    -- A member then, an author in my store now: still taken once the roster no longer lists him.
    members[ghost] = true
    eq(m.ledgerNet:take(pay(ghost, 1, P, 5), P), "new")
    members[ghost] = nil
    eq(m.ledgerNet:take(pay(ghost, 2, P, 6), P), "new")
    eq(m.ledgerNet:take(pay(P, 1, ghost, 5), P), "new")
    -- Without env.member (the sim) every name is taken.
    eq(p.ledgerNet:take(pay("Друг Човек", 1, M, 5), M), "new")
    eq(sim.envs[P].member, nil)
  end)

  it("no ledger broadcast inside an instance", function()
    local sim, i, m = setup()
    local inside = true
    i.env.status = function() return { combat = false, instance = inside, busy = false } end
    local mark = #sim.sent
    local e = i.ledgerNet:make("P", { f = M, c = 5, how = "hand" })
    sim:run(10); eq(#levs(sim, I, mark), 0)
    inside = false
    sim:run(2)
    eq(#levs(sim, I, mark), 1); ok(m.ledger:get(e.i), "arrived")
  end)

  it("nothing is sent or taken after stop", function()
    local sim, i, m = setup()
    local e = i.ledgerNet:make("P", { f = M, c = 5, how = "hand" })
    local mark = #sim.sent
    i:stop()
    -- my entry of the last seconds still left, before the BYE
    local l = levs(sim, I, mark)
    eq(#l, 1); eq(sim.sent[#sim.sent].msg.t, "BYE")
    sim:run(1); ok(m.ledger:get(e.i), "arrived")
    mark = #sim.sent
    eq(i.ledgerNet:make("P", { f = M, c = 6, how = "hand" }), nil)
    eq(i.ledgerNet:take(pay(M, 1, P, 5), M), nil)
    m:send("GUILD", nil, { v = 1, t = "LEV", ev = { pay(M, 2, P, 5) } })
    sim:run(120)
    eq(i.ledger:get(M .. ":1"), nil); eq(i.ledger:get(M .. ":2"), nil)
    local after = 0
    for j = mark + 1, #sim.sent do if sim.sent[j].from == I then after = after + 1 end end
    eq(after, 0)
  end)
end)

describe("ledger net: my name", function()
  it("an entry under my name that I never wrote is denied once", function()
    local sim, _, m = setup()
    local i = veteran(sim, I, 9)
    local forged = entry(I, 9, "C", { r = M .. ":1", dh = H16 })
    local mark = #sim.sent
    eq(m.ledgerNet:take(forged, P), "new")
    sim:run(5); eq(#levs(sim, M, mark), 0) -- М relays nothing
    eq(i.ledgerNet:take(forged, P), "new")
    local x = xs(i)
    eq(#x, 1); eq(x[1].i, I .. ":10"); eq(x[1].r, I .. ":9"); eq(x[1].rh, i.ledger:get(I .. ":9").h)
    eq(i.ledgerNet:take(forged, P), "dup"); eq(#xs(i), 1)
    local held = m.ledger:get(I .. ":9")
    eq(m.ledger:denied(held), false)
    sim:run(2)
    ok(m.ledger:get(I .. ":10"), "the X arrived"); eq(m.ledger:denied(held), true)
    eq(i.ledger:denied(i.ledger:get(I .. ":9")), true); eq(#i.ledgerNet:asks(), 0)
  end)

  it("a clean author denies what it never wrote", function()
    local sim = setup()
    local i = veteran(sim, I, 3)
    -- An id at or below my saved counter that I do not hold.
    eq(i.ledgerNet:take(pay(I, 2, M, 5), P), "new")
    local x = xs(i)
    eq(#x, 1); eq(x[1].r, I .. ":2"); eq(x[1].i, I .. ":4"); eq(store(sim, I).me[I].seq, 4)
    -- An id far above my counter is forged too.
    eq(i.ledgerNet:take(pay(I, 5000, M, 5), P), "new")
    eq(#xs(i), 2); eq(store(sim, I).me[I].seq, 5)
    -- Another body under an id I held at login (made in an earlier session).
    local mine = i.ledgerNet:make("P", { f = M, c = 7, how = "hand" })
    eq(mine.i, I .. ":6")
    sim:run(2)
    i = veteran(sim, I, 6)
    eq(i.ledgerNet:take(pay(I, 6, M, 700), P), "twin")
    x = xs(i)
    eq(#x, 3); eq(x[3].r, I .. ":6"); ok(x[3].rh ~= mine.h, "my own body is not denied")
    eq(i.ledger:denied(i.ledger:get(mine.i)), false); eq(#i.ledgerNet:asks(), 0)
  end)

  it("a body at an id I made in this run (a collision) is asked about; neither real entry is erased", function()
    local sim, i, m = setup()
    -- Mine has left already: it stays, the other body is put to me, nothing is denied.
    local mine = i.ledgerNet:make("P", { f = M, c = 7, how = "hand" })
    sim:run(2); ok(m.ledger:get(mine.i), "mine left")
    local other = pay(I, 1, P, 900)
    eq(m.ledgerNet:take(other, P), "twin"); eq(i.ledgerNet:take(other, P), "twin")
    sim:run(3)
    eq(#xs(i), 0); eq(#i.ledgerNet:asks(), 1); eq(i.ledgerNet:asks()[1].c, 900)
    ok(i.ledger:has(mine.i, mine.h), "mine is kept")
    local bodies = { m.ledger:get(mine.i) }
    eq(#bodies[2], 1); eq(m.ledger:denied(bodies[1]), false); eq(m.ledger:denied(bodies[2][1]), false)
    eq(View.paid(View.of(m.ledger), M, I), 7); eq(View.paid(View.of(m.ledger), P, I), 900)
    eq(View.paid(View.of(i.ledger), M, I), 7); eq(View.paid(View.of(i.ledger), P, I), 0) -- uncounted on my own client
    eq(m.ledger:seen(I), 1) -- no copy of mine under another id
    -- Mine has not left yet: it is made again under a fresh id, the old body never leaves.
    local mark = #sim.sent
    local soon = i.ledgerNet:make("P", { f = M, c = 8, how = "hand" })
    eq(soon.i, I .. ":2")
    eq(i.ledgerNet:take(pay(I, 2, P, 800), P), "twin")
    sim:run(3)
    eq(#xs(i), 0); eq(#i.ledgerNet:asks(), 2); eq(i.ledger:has(soon.i, soon.h), false)
    local again = i.ledger:get(I .. ":3")
    eq(again.k, "P"); eq(again.f, M); eq(again.c, 8); eq(again.how, "hand")
    local l = levs(sim, I, mark)
    eq(#l, 1); eq(#l[1].msg.ev, 1); eq(l[1].msg.ev[1].i, I .. ":3")
    eq(m.ledger:has(soon.i, soon.h), false); ok(m.ledger:get(I .. ":3"), "the new copy left")
    eq(View.paid(View.of(m.ledger), M, I), 15)
  end)

  -- The run of the crash question: И was paid 1g by М, crashed, and the guild shows it its P again.
  local function crashed()
    local sim, i, m = setup()
    i:stop(); i = sim:relog(I); sim:run(1); sim:settle() -- a clean logout: saved seq 0
    local d = m.ledgerNet:make("D", { gid = G1, g = "ttt", f = M, t = I, c = 10000, why = "lost" })
    sim:run(2)
    local p = i.ledgerNet:make("P", { f = M, c = 10000, how = "hand" })
    eq(p.i, I .. ":1")
    sim:run(2)
    eq(View.net(View.of(i.ledger), M, I), 0); ok(m.ledger:get(p.i), "М holds it")
    i = sim:crash(I)
    sim:run(1)
    eq(i.ledger:get(p.i), nil); eq(store(sim, I).me[I].seq, 0)
    local asked = record(i, "mineAsk")
    eq(i.ledgerNet:take(Ledger.wire(m.ledger:get(d.i)), M), "new")
    eq(i.ledgerNet:take(Ledger.wire(m.ledger:get(p.i)), M), "new")
    sim:run(1)
    return sim, i, m, p, asked
  end

  it("a crashed author is asked about its unsaved entries, not denied", function()
    local sim, i, m, p, asked = crashed()
    local held = i.ledger:get(p.i)
    eq(held.un, true); eq(#xs(i), 0); eq(i.ledgerNet:adopting(), false)
    local asks = i.ledgerNet:asks()
    eq(#asks, 1); ok(asks[1] == held, "the held body is asked about")
    eq(#asked, 1); eq(store(sim, I).me[I].seq, 1)
    eq(View.net(View.of(i.ledger), M, I), 10000) -- uncounted on my own client
    eq(Ledger.wire(held).un, nil)
    sim:settle()
    eq(i.ledgerNet:make("P", { f = P, c = 5, how = "hand" }).i, I .. ":2")
    sim:run(2)
    local mark = #sim.sent
    eq(i.ledgerNet:answer(true), true)
    sim:run(3)
    eq(held.un, nil); eq(#i.ledgerNet:asks(), 0); eq(#asked, 2)
    eq(View.net(View.of(i.ledger), M, I), 0); eq(#xs(i), 0); eq(#levs(sim, I, mark), 0)
    eq(View.net(View.of(m.ledger), M, I), 0)
    eq(i.ledgerNet:answer(true), nil)
  end)

  it("a crashed author that says they are not its own denies them", function()
    local sim, i, m, p = crashed()
    sim:settle()
    eq(i.ledgerNet:answer(false), true)
    local x = xs(i)
    eq(#x, 1); eq(x[1].r, p.i); eq(x[1].rh, p.h); eq(#i.ledgerNet:asks(), 0)
    sim:run(3)
    eq(m.ledger:denied(m.ledger:get(p.i)), true); eq(View.net(View.of(m.ledger), M, I), 10000)
    eq(View.net(View.of(i.ledger), M, I), 10000)
  end)

  it("an unanswered question is put again after the next login", function()
    local sim, i, _, p = crashed()
    i:stop(); i = sim:relog(I)
    local asked = record(i, "mineAsk")
    sim:run(1)
    eq(#asked, 1); eq(#i.ledgerNet:asks(), 1); eq(i.ledgerNet:asks()[1].i, p.i); eq(#xs(i), 0)
    eq(View.net(View.of(i.ledger), M, I), 10000)
  end)

  it("an uncounted X of mine denies nothing until I keep it", function()
    local sim, _, m = setup()
    local i = veteran(sim, I, 0)
    local lost = pay(I, 1, M, 300)
    local held = select(2, Ledger.new({}, M, function() return EPOCH0 end):add(lost, I))
    eq(i.ledgerNet:take(lost, M), "new")
    eq(i.ledgerNet:take(entry(I, 2, "X", { r = lost.i, h = held.h }), M), "new")
    eq(#i.ledgerNet:asks(), 2); eq(i.ledger:denied(i.ledger:get(lost.i)), false)
    eq(i.ledgerNet:answer(true), true)
    eq(i.ledger:denied(i.ledger:get(lost.i)), true); eq(#xs(i), 1)
  end)

  it("a forgery seen in the login queue is denied by the next session after a /reload", function()
    local sim, _, m = setup()
    store(sim, I).me[I].seq = 9
    sim.clients[I]:stop()
    local i = sim:relog(I)
    sim:run(1)
    eq(i.ledgerNet:take(pay(I, 4, M, 5), P), "new")
    eq(#xs(i), 0); eq(#store(sim, I).pending, 1)
    local mark = #sim.sent
    i:stop(); i = sim:relog(I); sim:run(1) -- the /reload
    eq(#xs(i), 0)
    sim:settle(); sim:run(2)
    local x = xs(i)
    eq(#x, 1); eq(x[1].r, I .. ":4"); eq(x[1].i, I .. ":10"); eq(#store(sim, I).pending, 0)
    eq(shipped(sim, I, mark), 1); ok(m.ledger:get(I .. ":10"), "the X left")
  end)

  it("a far id refused in a new store's window is denied by the next session", function()
    local sim = Sim.new()
    local i = sim:add(I)
    sim:add(M); sim:run(1)
    eq(i.ledgerNet:take(pay(I, 5000, M, 5), M), "new")
    i:stop(); i = sim:relog(I); sim:run(1)
    eq(i.ledgerNet:adopting(), false); eq(#xs(i), 0)
    sim:settle()
    local x = xs(i)
    eq(#x, 1); eq(x[1].r, I .. ":5000")
  end)

  it("an entry made in the first seconds after a login survives a /reload", function()
    local sim, i, m = setup()
    i:stop(); i = sim:relog(I); sim:run(1)
    eq(i.ledgerNet:make("P", { f = M, c = 10000, how = "hand" }), "queued") -- „Уредено“
    i:stop(); i = sim:relog(I); sim:run(1)
    local mark = #sim.sent
    sim:settle(); sim:run(2)
    local got = m.ledger:get(I .. ":1")
    ok(got, "made and sent"); eq(got.c, 10000); eq(shipped(sim, I, mark), 1)
    i:stop(); i = sim:relog(I); sim:settle(); sim:run(2)
    eq(m.ledger:seen(I), 1) -- made once
  end)

  it("the crash question is per entry, and at most LEDGER_MINE_ASK are open", function()
    local sim = setup()
    local i = veteran(sim, I, 0)
    local a, b = pay(I, 1, M, 100), pay(I, 2, P, 200)
    i.ledgerNet:take(a, M); i.ledgerNet:take(b, M)
    local asks = i.ledgerNet:asks()
    eq(#asks, 2)
    eq(i.ledgerNet:answer(asks[1], true), true)
    eq(#i.ledgerNet:asks(), 1); eq(i.ledgerNet:asks()[1].i, b.i); eq(View.paid(View.of(i.ledger), M, I), 100)
    eq(i.ledgerNet:answer(a.i, false), nil) -- answered already
    eq(i.ledgerNet:answer(b.i, false), true)
    local x = xs(i)
    eq(#x, 1); eq(x[1].r, b.i); eq(#i.ledgerNet:asks(), 0)
    -- A forger fills the open questions first; my real lost entry then waits, unshown, never denied.
    for n = 4, 3 + ns.Const.LEDGER_MINE_ASK do i.ledgerNet:take(pay(I, n, M, n), M) end
    local shown, more = i.ledgerNet:asks()
    eq(#shown, ns.Const.LEDGER_MINE_ASK); eq(more, 0); eq(#xs(i), 1)
    local real = pay(I, 900, P, 12345)
    eq(i.ledgerNet:take(real, M), "new")
    shown, more = i.ledgerNet:asks()
    eq(#shown, ns.Const.LEDGER_MINE_ASK); eq(more, 1); eq(#xs(i), 1)
    eq(i.ledger:get(real.i).un, true); eq(View.paid(View.of(i.ledger), P, I), 0)
    eq(i.ledgerNet:answer(real.i, true), nil) -- not shown: not answered
    eq(i.ledgerNet:answer(shown[1], false), true) -- a slot frees
    shown, more = i.ledgerNet:asks()
    eq(#shown, ns.Const.LEDGER_MINE_ASK); eq(more, 0); eq(shown[#shown].i, real.i)
    eq(i.ledgerNet:answer(real.i, true), true); eq(View.paid(View.of(i.ledger), P, I), 12345); eq(#xs(i), 2)
  end)

  it("two characters share one ledger store: a login makes only its own queued rows", function()
    local sim = Sim.new()
    local A, B = I, "Иван Второй"
    local db = { lang = "bg", introDone = false, busy = false, snoozeUntil = 0, debug = false, minimap = {} }
    local a = sim:add(A, { db = db })
    local m = sim:add(M)
    sim:run(1); sim:settle()
    store(sim, A).me[A].seq = 9
    a:stop(); a = sim:relog(A); sim:run(1)
    eq(a.ledgerNet:make("P", { f = M, c = 10000, how = "hand" }), "queued")
    eq(a.ledgerNet:take(pay(A, 4, M, 5), M), "new") -- a forgery: its X waits in the queue
    eq(#db.ledger[GUILD].pending, 2)
    a:stop(); sim:offline(A)
    local b = sim:add(B, { db = db })
    sim:run(1); sim:settle(); sim:run(2)
    eq(b.ledger:seen(B), 0); eq(m.ledger:seen(B), 0); eq(#db.ledger[GUILD].pending, 2)
    b:stop(); sim:offline(B)
    a = sim:relog(A); sim:run(1); sim:settle(); sim:run(2)
    local x = xs(a)
    eq(#x, 1); eq(x[1].r, A .. ":4")
    local got = m.ledger:get(A .. ":10")
    ok(got, "A's own P made by A"); eq(got.k, "P"); eq(got.c, 10000); ok(m.ledger:get(A .. ":11"), "A's X sent")
    eq(#db.ledger[GUILD].pending, 0)
  end)

  it("a queued row made before a crash is not made again when it comes back", function()
    local sim, i, m = setup()
    i:stop(); i = sim:relog(I); sim:run(1)
    eq(i.ledgerNet:make("P", { f = M, c = 10000, how = "hand" }), "queued")
    eq(i.ledgerNet:make("P", { f = M, c = 10000, how = "hand" }), "queued") -- two equal payments: both are real
    i:stop(); i = sim:relog(I); sim:run(1) -- the queue is saved
    sim:settle(); sim:run(2)
    eq(View.paid(View.of(m.ledger), M, I), 20000)
    i = sim:crash(I); sim:run(1) -- back to the saved variables of the logout: the rows, seq 0
    eq(#store(sim, I).pending, 2)
    for n = 1, 2 do eq(i.ledgerNet:take(Ledger.wire(m.ledger:get(I .. ":" .. n)), M), "new") end
    eq(#i.ledgerNet:asks(), 2)
    local mark = #sim.sent
    sim:settle(); sim:run(3)
    eq(#i.ledgerNet:asks(), 0); eq(shipped(sim, I, mark), 0); eq(#store(sim, I).pending, 0)
    eq(View.paid(View.of(m.ledger), M, I), 20000); eq(View.paid(View.of(i.ledger), M, I), 20000)
    eq(m.ledger:seen(I), 2)
  end)

  it("while logging in, my own entries wait", function()
    local sim, i, m = setup()
    i:stop(); i = sim:relog(I); sim:run(1)
    local mark = #sim.sent
    eq(i.ledgerNet:make("P", { f = M, c = 100, how = "hand" }), "queued")
    -- meanwhile the guild shows me an entry of mine numbered 4 (from a session my store lost)
    eq(i.ledgerNet:take(pay(I, 4, P, 7), M), "new")
    sim:run(25); eq(#levs(sim, I, mark), 0); eq(#xs(i), 0)
    sim:run(10)
    local l = levs(sim, I, mark)
    eq(#l, 1); eq(#l[1].msg.ev, 1); eq(l[1].msg.ev[1].i, I .. ":5"); ok(m.ledger:get(I .. ":5"), "sent")
  end)

  it("a new install adopts", function()
    local sim = Sim.new()
    local i, m = sim:add(I), sim:add(M)
    sim:run(1)
    eq(i.ledgerNet:adopting(), true)
    local asked = record(i, "mineAsk")
    eq(i.ledgerNet:take(pay(I, 3, M, 50), M), "new")
    eq(i.ledgerNet:take(pay(I, 3, M, 51), P), "twin")
    eq(i.ledgerNet:take(pay(I, 5000, M, 5), P), "new") -- too far above my counter: not mine
    sim:run(1)
    eq(#i.ledgerNet:asks(), 0); eq(#xs(i), 0); eq(#asked, 0); eq(i.ledger:get(I .. ":3").un, nil)
    eq(store(sim, I).me[I].seq, 3)
    eq(View.net(View.of(i.ledger), M, I), 0)
    sim:settle()
    eq(i.ledgerNet:adopting(), false)
    local x = xs(i)
    eq(#x, 1); eq(x[1].r, I .. ":5000"); eq(x[1].i, I .. ":4")
    -- After the window: another body under an id I hold is denied.
    eq(i.ledgerNet:take(pay(I, 3, M, 52), P), "twin")
    eq(#xs(i), 2); eq(#i.ledgerNet:asks(), 0)
    -- A store with my record never adopts; the window of a new one ends by itself.
    m:stop(); m = sim:relog(M); sim:run(1); eq(m.ledgerNet:adopting(), false)
    local p = sim:add(P)
    sim:run(1); eq(p.ledgerNet:adopting(), true)
    sim:run(28); eq(p.ledgerNet:adopting(), true)
    sim:run(1); eq(p.ledgerNet:adopting(), false)
  end)

  it("denials go out batched and rate-limited", function()
    local sim, _, m = setup()
    local i = veteran(sim, I, 100)
    local mark = #sim.sent
    for n = 1, 20 do i.ledgerNet:take(pay(I, n, M, n), P) end
    eq(#xs(i), 20)
    sim:run(2)
    for _, s in ipairs(levs(sim, I, mark)) do
      eq(s.channel, "GUILD"); ok(#s.msg.ev <= 4, "at most 4 per LEV")
      for _, e in ipairs(s.msg.ev) do eq(e.k, "X") end
    end
    eq(shipped(sim, I, mark), 8); eq(#levs(sim, I, mark), 2)
    sim:run(59); eq(shipped(sim, I, mark), 8)
    sim:run(1); eq(shipped(sim, I, mark), 16)
    sim:run(59); eq(shipped(sim, I, mark), 16)
    sim:run(1); eq(shipped(sim, I, mark), 20); eq(#levs(sim, I, mark), 5)
    sim:run(120); eq(shipped(sim, I, mark), 20)
    local denied = 0
    m.ledger:each(function(e) if e.k ~= "X" and m.ledger:denied(e) then denied = denied + 1 end end)
    eq(denied, 0) -- М never held the forgeries; it holds the 20 X
    eq(m.ledger:seen(I), 120)
  end)
end)

describe("ledger net: a client without a guild", function()
  it("a client without a guild has no ledger", function()
    local sim, i = setup()
    local name = "Бот Тестов"
    local bot = sim:join(name, sim.makeEnv(name, "WARRIOR"))
    sim:run(1)
    eq(bot.ledger, nil); eq(bot.ledgerNet, nil); eq(bot.env.guild, nil); eq(bot.env.db.ledger, nil)
    i.ledgerNet:make("P", { f = M, c = 5, how = "hand" })
    sim:run(3) -- the bot gets the LEV and ignores it
    eq(bot.ledger, nil)
  end)

  it("a client without a ledger cannot open or sit at a staked table", function()
    local sim, i = setup()
    local name = "Бот Тестов"
    local bot = sim:join(name, sim.makeEnv(name, "WARRIOR"))
    sim:run(1)
    local tid, why = bot:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }
    eq(tid, nil); eq(why, "stake"); eq(bot.session, nil)
    local staked = i:openTable{ game = "ttt", access = "guild", turn = 45, stake = 50000 }
    sim:run(3)
    local mark = #sim.sent
    local r, w = bot:sit(staked, 2, 50000)
    eq(r, nil); eq(w, "stake")
    r, w = bot:sit(staked, 2)
    eq(r, nil); eq(w, "stake")
    sim:run(2)
    eq(sim:count(function(s) return s.from == name and s.msg.t == "SIT" end), 0)
    eq(i.session.seats[2], false)
    -- A fun table: as ever.
    ok(bot:openTable{ game = "ttt", access = "guild", turn = 45 }, "a fun table opens")
  end)
end)

describe("sim: a crash", function()
  it("comes back to the saved variables of the last clean logout", function()
    local sim, i = setup()
    local db = sim.envs[I].db
    db.stakeSat, db.stakeSeen = { tid = "a#1", sk = 100 }, { x = 1 }
    i:stop(); sim:relog(I); sim:run(1)
    db.stakeSat, db.stakeLeft, db.fairKeep = { tid = "b#2", sk = 200 }, { y = 2 }, { tid = "b#2" }
    sim:crash(I)
    eq(db.stakeSat, { tid = "a#1", sk = 100 }); eq(db.stakeSeen, { x = 1 }); eq(db.stakeLeft, nil); eq(db.fairKeep, nil)
    eq(sim.envs[I].guild, GUILD); ok(sim.envs[I].db.ledger[GUILD].me[I], "the store as at the logout")
  end)
end)
