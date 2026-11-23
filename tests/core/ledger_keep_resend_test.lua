Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local ns = Sim.ns
local Ledger, C, U = ns.Ledger, ns.Const, ns.Util

-- Stage F4, the final review (Ruling F4-F): the order of an exchange's queue under stubs (first
-- what no mark covers, of every author; the re-sent D, C, N, P and X last, turned by a per-peer
-- cursor, and not again within LEDGER_REFUSED_TTL once a heard exchange carried them), and a
-- mark committed at a heard cut end too. Every holder here has relogged: its bodies are loaded
-- from disk (no L.came stamp), as on a real client.

-- The real wire, as wow/Adapter.lua installs it (restored at the end of this file).
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
local stand = ns.LedgerNet.size
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end

-- "Ана" < "Борис" < "Вера" < "Дара" by bytes; Жана is an author who is never online.
local ANA, BOR, VERA, DARA = "Ана Иванова", "Борис Петров", "Вера Колева", "Дара Маринова"
local ZH, GOSHO, ELENA = "Жана Стоева", "Гошо Тодоров", "Елена Попова"
local EPOCH0 = 1700000000
local OLD = EPOCH0 - 2 * 31536000 -- two years back

local function world(...)
  local sim, c = Sim.new(), {}
  for _, name in ipairs({ ... }) do c[name] = sim:add(name) end
  sim:run(1)
  sim:settle()
  return sim, c
end
local function give(client, list, from)
  for _, e in ipairs(list) do client.ledger:add(e, from or "Някой") end
end
-- R entries of `author` numbered from..to, dated `at` (default: EPOCH0 + n); `tag` makes a twin.
local function rs(author, from, to, at, tag)
  local out = {}
  for n = from, to do
    out[#out + 1] = { i = Ledger.id(author, n), k = "R", at = at or EPOCH0 + n, gid = ANA .. "#" .. (tag or 1) .. "/" .. n,
      g = "ttt", n = { ANA, BOR }, w = { 1 }, l = { 2 } }
  end
  return out
end
local function pay(author, n, c)
  return { i = Ledger.id(author, n), k = "P", at = EPOCH0 + n, f = author == ZH and ANA or ZH, c = c or 100 + n, how = "hand" }
end
local function pays(author, from, to)
  local out = {}
  for n = from, to do out[#out + 1] = pay(author, n) end
  return out
end
local function hello(sim, ...)
  for _, name in ipairs({ ... }) do sim.clients[name].presence:sendGuildHi(false) end
  sim:run(0)
end
local function whispers(sim, from, t, mark)
  local out = {}
  for j, s in ipairs(sim.sent) do
    if j > (mark or 0) and s.from == from and s.channel == "WHISPER" and s.msg.t == t then out[#out + 1] = s end
  end
  return out
end
-- How many entries of `author` went in whispered LEVs after sim.sent[mark] (from `from`, when given).
local function carried(sim, author, mark, from)
  local n = 0
  for j, s in ipairs(sim.sent) do
    if j > (mark or 0) and s.channel == "WHISPER" and s.msg.t == "LEV" and (not from or s.from == from) then
      for _, e in ipairs(s.msg.ev) do if Ledger.author(e.i) == author then n = n + 1 end end
    end
  end
  return n
end
local function digests(...)
  local out = {}
  for j, c in ipairs({ ... }) do out[j] = c.ledger:digest() end
  return out
end
local function holds(c, id) local first, more = c.ledger:get(id); return first and 1 + (more and #more or 0) or 0 end
-- Runs fn with LEDGER_AUTHOR_ROOM set so that an author past `limit` R+S bodies is pruned (restored after).
local function room(limit, fn)
  local r = C.LEDGER_AUTHOR_ROOM
  C.LEDGER_AUTHOR_ROOM = C.LEDGER_AUTHOR_MAX - limit
  local good, err = pcall(fn)
  C.LEDGER_AUTHOR_ROOM = r
  if not good then error(err, 0) end
end
-- A direct prune of client c down to `limit` R+S bodies per author -> how many stubs.
local function prune(c, limit)
  local made
  room(limit, function() made = select(1, c.ledger:prune(c.env.epoch(), 100000)) end)
  return made
end

-- An F1–F3 client: its sync sends L:above(author, n) as before F4 and never prunes. (Holding no
-- stub, its LID lists and twin checks are the F1–F3 ones; the test checks it holds none.)
local function f3(client)
  client.ledgerSync.tail = function(self, x, a, t) return self.L:above(a, t and t.n or 0) end
  client.ledgerSync.mark = function() end
  client.ledgerNet.prune = function() end
end

-- Entries of ZH numbered from..to: R entries dated `at`, but at ks.D, ks.C, ks.N, ks.P and ks.X a D
-- (ZH owes Ана), a C and an N of that D, a P and an X that denies the R just below it.
local function heavy(from, to, at, ks)
  local out, d = {}, { k = "D", at = EPOCH0, gid = ZH .. "#" .. EPOCH0 .. "/1", g = "ttt", f = ZH, t = ANA, c = 1000, why = "lost" }
  d.i = Ledger.id(ZH, ks.D)
  for n = from, to do
    local e = rs(ZH, n, n, at)[1]
    if n == ks.D then e = d end
    if n == ks.C then e = { i = Ledger.id(ZH, n), k = "C", at = EPOCH0 + n, r = d.i, dh = Ledger.hash(d) } end
    if n == ks.N then e = { i = Ledger.id(ZH, n), k = "N", at = EPOCH0 + n, r = d.i, dh = Ledger.hash(d), why = "forged" } end
    if n == ks.P then e = pay(ZH, n) end
    if n == ks.X then
      local r = rs(ZH, n - 1, n - 1, at)[1]
      e = { i = Ledger.id(ZH, n), k = "X", at = EPOCH0 + n, r = r.i, h = Ledger.hash(r) }
    end
    out[#out + 1] = e
  end
  return out
end
-- Does client c hold every one of the D, C, N, P and X of `ks`?
local function kinds(c, ks)
  for _, k in ipairs({ "D", "C", "N", "P", "X" }) do
    if holds(c, Ledger.id(ZH, ks[k])) == 0 then return false, k .. " at " .. ks[k] end
  end
  return true
end
local function count(c, from, to)
  local n = 0
  for k = from, to do n = n + holds(c, Ledger.id(ZH, k)) end
  return n
end
-- Prunes client c's ZH down to `limit` R+S bodies (every step) -> its stub count.
local function pruneAll(c, limit)
  room(limit, function() local more = true; while more do _, more = c.ledger:prune(0, 100000) end end)
  return c.ledger:stubCount()
end
-- `rounds` differences between Ана and `peer` (a fresh P of the peer on its client), each with an exchange.
local function rounds(sim, peer, n, base)
  for k = 1, n do
    give(sim.clients[peer], { pay(peer, (base or 0) + k) })
    hello(sim, ANA, peer); sim:run(400)
  end
end
local YANA = "Яна Русева" -- sorts after ZH by bytes

local function mixed(from, to, isP)
  local out = {}
  for n = from, to do out[#out + 1] = isP(n) and pay(ZH, n) or rs(ZH, n, n, EPOCH0)[1] end
  return out
end
local function yana(n) return { i = Ledger.id(YANA, n), k = "P", at = EPOCH0, f = ANA, c = 500 + n, how = "hand" } end
-- Every entry `from` whispered in LEVs after sim.sent[mark].
local function sentBy(sim, from, mark)
  local n = 0
  for j, s in ipairs(sim.sent) do
    if j > mark and s.from == from and s.channel == "WHISPER" and s.msg.t == "LEV" then n = n + #s.msg.ev end
  end
  return n
end
-- One difference between Ана and `peer` and its exchange -> how many entries `holder` sent in it.
local function round(sim, peer, k, holder)
  local mark = #sim.sent
  rounds(sim, peer, 1, k - 1)
  return sentBy(sim, holder or ANA, mark)
end

describe("ledger F4 sync: the re-sent D, C, N, P and X never block an exchange (C1; bodies loaded from disk)", function()
  it("one author with 360 P: a newcomer gets all of it, a P relayed later and a later author's P", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], mixed(41, 460, function(n) return n <= 400 end))
    give(c[ANA], { yana(1) })
    eq(pruneAll(c[ANA], 60), 40)
    local mark = #sim.sent
    local a = sim:relog(ANA); sim:run(31)
    for r = 1, 2 do round(sim, BOR, r) end
    eq(count(c[BOR], 41, 460), 420); eq(holds(c[BOR], Ledger.id(YANA, 1)), 1)
    eq(sentBy(sim, ANA, mark), 421) -- each entry once: no exchange repeats the 300 of the one before
    eq(a.ledgerSync.high[BOR].a[ZH], 460)
    for r = 3, 6 do eq(round(sim, BOR, r), 0) end -- it holds all it can: nothing is carried
    give(a, { pay(ZH, 461), pay(ZH, 30, 7), yana(2) }) -- relayed to Ана later: above the mark, below it, another author
    eq(round(sim, BOR, 7), 3)
    eq(holds(c[BOR], Ledger.id(ZH, 461)), 1); eq(holds(c[BOR], Ledger.id(ZH, 30)), 1); eq(holds(c[BOR], Ledger.id(YANA, 2)), 1)
    eq(round(sim, BOR, 8), 0)
  end)

  it("four stub-held authors with 100 P each converge, and the author after them", function()
    local sim, c = world(ANA, BOR)
    local authors = { ZH, GOSHO, ELENA, DARA }
    local function r(au, n, at) return { i = Ledger.id(au, n), k = "R", at = at, gid = au .. "#1/" .. n, g = "ttt", n = { ANA, BOR }, w = { 1 }, l = { 2 } } end
    for _, au in ipairs(authors) do
      local list = {}
      for n = 1, 10 do list[#list + 1] = r(au, n, OLD) end
      for n = 11, 110 do list[#list + 1] = pay(au, n) end
      for n = 111, 120 do list[#list + 1] = r(au, n, EPOCH0 + n) end
      give(c[ANA], list)
    end
    give(c[ANA], { yana(1) })
    eq(pruneAll(c[ANA], 10), 40)
    local mark = #sim.sent
    local a = sim:relog(ANA); sim:run(31)
    local function got()
      local n = 0
      for _, au in ipairs(authors) do for k = 11, 120 do n = n + holds(c[BOR], Ledger.id(au, k)) end end
      return n
    end
    for k = 1, 2 do round(sim, BOR, k) end
    eq(got(), 440); eq(holds(c[BOR], Ledger.id(YANA, 1)), 1)
    eq(sentBy(sim, ANA, mark), 441)
    for k = 3, 6 do eq(round(sim, BOR, k), 0) end
    give(a, { yana(2), pay(DARA, 121) })
    eq(round(sim, BOR, 7), 2)
    eq(holds(c[BOR], Ledger.id(YANA, 2)), 1); eq(holds(c[BOR], Ledger.id(DARA, 121)), 1)
  end)

  it("an active author's new entry costs the newcomer that entry, not its 100 P again (the holder asks)", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], mixed(41, 200, function(n) return n <= 140 end))
    eq(pruneAll(c[ANA], 60), 40)
    local mark = #sim.sent
    local a = sim:relog(ANA); sim:run(31)
    round(sim, BOR, 1)
    eq(sentBy(sim, ANA, mark), 160)
    for r = 2, 7 do
      give(a, rs(ZH, 199 + r, 199 + r, EPOCH0))
      eq(round(sim, BOR, r), 1)
    end
    eq(count(c[BOR], 41, 206), 166)
  end)

  it("the same when the holder answers (the newcomer asks)", function()
    local sim, c = world(ANA, VERA)
    give(c[VERA], rs(ZH, 1, 40, OLD)); give(c[VERA], mixed(41, 200, function(n) return n <= 140 end))
    eq(pruneAll(c[VERA], 60), 40)
    sim:offline(ANA); local v = sim:relog(VERA); sim:run(31); sim:online(ANA)
    eq(round(sim, ANA, 1, VERA), 160)
    eq(count(c[ANA], 41, 200), 160)
    for r = 2, 7 do
      give(v, rs(ZH, 199 + r, 199 + r, EPOCH0))
      eq(round(sim, ANA, r, VERA), 1)
    end
    eq(count(c[ANA], 41, 206), 166)
  end)

  it("a holder's next session sends the D, C, N, P and X below its marks once more, all of them, behind what is new", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], mixed(41, 760, function(n) return n <= 740 end))
    eq(pruneAll(c[ANA], 20), 40)
    local a = sim:relog(ANA); sim:run(31)
    for r = 1, 3 do round(sim, BOR, r) end
    eq(count(c[BOR], 41, 760), 720)
    local mark = #sim.sent
    a = sim:relog(ANA) -- the marks stay (the store), what the exchanges carried is forgotten
    eq(a.ledgerSync.high[BOR].a[ZH], 760)
    give(a, { yana(1) })
    sim:run(31)
    round(sim, BOR, 11) -- two exchanges at most: not all of the 700 P
    eq(holds(c[BOR], Ledger.id(YANA, 1)), 1) -- what is new went before them
    for r = 12, 14 do round(sim, BOR, r) end
    ok(a.ledgerSync.fix[BOR].sig[YANA], "an exchange cut with only re-sent entries left is complete: Sync:fixed notes it")
    eq(carried(sim, ZH, mark, ANA), 700) -- each once: ZH's cells never changed meanwhile, and it was not given up
    eq(sentBy(sim, ANA, mark), 701)
    for r = 15, 17 do eq(round(sim, BOR, r), 0) end
  end)
end)

describe("ledger F4 sync: a mark is committed at a heard cut end (I1)", function()
  it("a holder that relogs after every two exchanges still brings a newcomer 960 bodies, with few sent twice", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 1000, EPOCH0))
    eq(pruneAll(c[ANA], 960), 40)
    local mark = #sim.sent
    local a = sim:relog(ANA); sim:run(31)
    for s = 1, 5 do
      rounds(sim, BOR, 2, s * 10)
      a = sim:relog(ANA); sim:run(31)
    end
    eq(count(c[BOR], 41, 1000), 960)
    local sent = carried(sim, ZH, mark, ANA) -- only an exchange a relog broke off is sent again
    ok(sent <= 960 + C.LEDGER_EXCHANGE_MAX, "carried " .. sent)
    eq(a.ledgerSync.high[BOR].a[ZH], 1000)
  end)
end)

describe("ledger F4 sync: the second pass (Sync:tail, Sync:resend)", function()
  local clock = { t = EPOCH0, now = 0 }
  local function sync()
    local L = Ledger.new({}, ANA, function() return clock.t end)
    return ns.LedgerSync.new({ env = { now = function() return clock.now end } }, L, nil), L
  end
  local CELL = { n = 0, x = "0123456789ab" }
  -- An exchange with DARA as Sync:open makes it, after its vector acted on ZH.
  local function ex(L)
    return { peer = DARA, hw = {}, left = {}, q = {}, qs = {}, ag = {}, re = {}, nre = 0, rev0 = L.rev, acted = { [ZH] = "s" }, fMine = true, fTheirs = true }
  end
  -- x's queue as Sync:vector fills it for ZH; then its first `n` leave -> the numbers that left.
  local function run(s, x, n)
    s:queue(x, s:tail(x, ZH, CELL)); s:resend(x)
    local out = {}
    for _ = 1, math.min(n, #x.q) do
      local b = table.remove(x.q, 1)
      s:mark(x, b); out[#out + 1] = select(2, Ledger.author(b.i))
    end
    return out
  end
  -- ZH 1..3 stubs, R 4, P 5..14, R 15, loaded; the peer's mark at 15.
  local function setup()
    clock.t, clock.now = EPOCH0, 0
    local s, L = sync()
    for _, e in ipairs(rs(ZH, 1, 3, OLD)) do L:add(e, BOR) end
    room(0, function() L:prune(EPOCH0, 100) end)
    for _, e in ipairs(mixed(4, 15, function(n) return n >= 5 and n <= 14 end)) do L:add(e, BOR) end
    local x = ex(L); x.hw[ZH] = 15
    s:ended(x)
    eq(s.high[DARA].a[ZH], 15)
    return s, L
  end

  it("the tail gives what no mark covers and, apart, the D, C, N, P and X below the mark; those go last", function()
    local s, L = setup()
    L:add(rs(ZH, 16, 16, EPOCH0)[1], BOR)
    local x = ex(L)
    local fresh, again = s:tail(x, ZH, CELL)
    eq(#fresh, 1); eq(fresh[1].i, Ledger.id(ZH, 16)); eq(#again, 10)
    s:queue(x, fresh, again)
    s:queue(x, { (L:get(Ledger.id(ZH, 4))) }) -- a LID's find, queued later: still before the re-sent
    s:resend(x)
    s:queue(x, { (L:get(Ledger.id(ZH, 15))) })
    eq(#x.q, 13)
    eq(x.q[1].i, Ledger.id(ZH, 16)); eq(x.q[2].i, Ledger.id(ZH, 4)); eq(x.q[3].i, Ledger.id(ZH, 15)); eq(x.q[4].i, Ledger.id(ZH, 5))
  end)

  it("the cursor turns the re-sent ones: exchanges that are cut walk through all of them", function()
    local s, L = setup()
    local x = ex(L); x.fTheirs = false -- its end is not heard: nothing is taken as carried
    eq(run(s, x, 4), { 5, 6, 7, 8 }); s:ended(x)
    x = ex(L); x.fTheirs = false
    eq(run(s, x, 4), { 9, 10, 11, 12 }); s:ended(x)
    x = ex(L); x.fTheirs = false
    eq(run(s, x, 4), { 13, 14, 5, 6 }); s:ended(x)
  end)

  it("what a heard exchange carried is not re-sent for LEDGER_REFUSED_TTL s; the rest is", function()
    local s, L = setup()
    local x = ex(L)
    eq(run(s, x, 4), { 5, 6, 7, 8 }); s:ended(x) -- heard; six re-sent ones stay unsent
    local fresh, again = s:tail(ex(L), ZH, CELL)
    eq(#fresh, 0); eq(#again, 6) -- they are not owed: they stay behind what no mark covers
    x = ex(L)
    eq(run(s, x, 99), { 9, 10, 11, 12, 13, 14 }); s:ended(x)
    x = ex(L)
    eq(run(s, x, 99), {})
    clock.now = C.LEDGER_REFUSED_TTL - 1
    eq(run(s, ex(L), 99), {})
    clock.now = C.LEDGER_REFUSED_TTL
    eq(#run(s, ex(L), 99), 10) -- a day on: once more
  end)

  it("an author with re-sent ones left unsent is not noted by Sync:fixed (it is taken out of x.acted)", function()
    local s, L = setup()
    local x = ex(L)
    run(s, x, 4)
    s:ended(x)
    eq(x.acted[ZH], nil) -- Sync:fixed does not note ZH: its re-sent ones are not through
    x = ex(L)
    run(s, x, 99)
    s:ended(x)
    eq(x.acted[ZH], nil); eq(x.held[ZH], true) -- the four of the first exchange are stamped for the day: held back, ZH is not given up on (N1)
    clock.now = C.LEDGER_REFUSED_TTL
    x = ex(L)
    run(s, x, 99)
    s:ended(x)
    eq(x.acted[ZH], "s") -- the stamp is over: nothing is held back
  end)
end)

ns.LedgerNet.size = stand
