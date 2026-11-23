Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local ns = Sim.ns
local Ledger, C, U = ns.Ledger, ns.Const, ns.Util

-- Stage F4, Task 2: retention in the sync (Sync:lid and Sync:scope count stubs, Sync:tail and
-- its high-water marks, persisted in the ledger store as ruled in J1 a; J5's arrived-after
-- stamp) and the prune itself (Net:prune, once a session). As ruled (J1 a) a body is stubbed
-- by the per-author cap only: the tests lower LEDGER_AUTHOR_ROOM (never by age).

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

describe("ledger F4 sync: stubs and bodies agree", function()
  it("a pruned client and one that keeps everything are equal: no exchange, no entry", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[BOR], rs(ZH, 1, 40, OLD))
    eq(prune(c[ANA], 0), 40)
    eq(c[ANA].ledger:stubCount(), 40); eq(holds(c[ANA], Ledger.id(ZH, 1)), 0)
    eq(digests(c[ANA], c[BOR])[1], digests(c[ANA], c[BOR])[2])
    local mark = #sim.sent
    hello(sim, ANA, BOR); sim:run(400)
    eq(#whispers(sim, ANA, "LVC", mark), 0); eq(#whispers(sim, BOR, "LEV", mark), 0)
  end)

  it("a LID round does not bring a stubbed body back", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 10, OLD)); give(c[BOR], rs(ZH, 1, 10, OLD))
    give(c[ANA], rs(ZH, 10, 10, OLD, 2)); give(c[BOR], rs(ZH, 10, 10, OLD, 3)) -- one twin each at 10: equal n, x differ
    eq(prune(c[ANA], 2), 9) -- 1..9 (10 has twins)
    eq(c[ANA].ledger:vector()[ZH].n, 10); eq(c[BOR].ledger:vector()[ZH].n, 10)
    local mark = #sim.sent
    hello(sim, ANA, BOR); sim:run(400)
    ok(#whispers(sim, ANA, "LID", mark) > 0, "a LID round")
    for n = 1, 9 do eq(holds(c[ANA], Ledger.id(ZH, n)), 0) end
    eq(holds(c[ANA], Ledger.id(ZH, 10)), 3); eq(holds(c[BOR], Ledger.id(ZH, 10)), 3)
    eq(carried(sim, ZH, mark), 2) -- each side's one twin, nothing else
    eq(digests(c[ANA], c[BOR])[1], digests(c[ANA], c[BOR])[2])
  end)

  it("a stub at an id that also holds a body is a twin there: the LID lists agree, nothing at it is resent", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 10, OLD)); give(c[BOR], rs(ZH, 1, 10, OLD))
    eq(prune(c[ANA], 0), 10)
    give(c[ANA], rs(ZH, 5, 5, OLD, 2)); give(c[BOR], rs(ZH, 5, 5, OLD, 2)) -- a twin at stubbed 5, as a body on both
    give(c[ANA], rs(ZH, 10, 10, OLD, 3)); give(c[BOR], rs(ZH, 10, 10, OLD, 4)) -- the difference: other twins at 10
    eq(digests(c[ANA])[1] ~= digests(c[BOR])[1], true)
    local mark = #sim.sent
    hello(sim, ANA, BOR); sim:run(400)
    eq(carried(sim, ZH, mark), 2) -- the twins at 10 only: not 5, not the body under the stub
    eq(holds(c[ANA], Ledger.id(ZH, 5)), 1); eq(c[ANA].ledger:stubCount(), 10)
    eq(digests(c[ANA], c[BOR])[1], digests(c[ANA], c[BOR])[2])
  end)

  it("a pruned, an unpruned and an F1–F3 client converge, and their exchanges stop", function()
    local sim, c = world(ANA, BOR, VERA)
    f3(c[BOR])
    for _, name in ipairs({ ANA, BOR, VERA }) do give(c[name], rs(ZH, 1, 40, OLD)); give(c[name], rs(ZH, 30, 30, OLD, 2)) end
    eq(prune(c[ANA], 20), 21) -- 41 bodies down to 20: 1..21 (30 has twins and stays)
    give(c[ANA], pays(GOSHO, 1, 5)); give(c[BOR], pays(DARA, 1, 5)); give(c[VERA], pays(ELENA, 1, 5))
    local mark = #sim.sent
    hello(sim, ANA, BOR, VERA); sim:run(1500)
    local d = digests(c[ANA], c[BOR], c[VERA])
    eq(d[1], d[2]); eq(d[2], d[3])
    eq(carried(sim, ZH, mark), 0) -- every one holds every ZH entry, as a body or a stub
    eq(holds(c[ANA], Ledger.id(ZH, 1)), 0); eq(c[BOR].ledger:stubCount(), 0); eq(c[VERA].ledger:stubCount(), 0)
    eq(holds(c[BOR], Ledger.id(GOSHO, 5)), 1); eq(holds(c[VERA], Ledger.id(DARA, 5)), 1); eq(holds(c[ANA], Ledger.id(ELENA, 5)), 1)
    mark = #sim.sent
    sim:run(1500) -- heartbeats: the digests agree, nobody starts an exchange
    for _, name in ipairs({ ANA, BOR, VERA }) do eq(#whispers(sim, name, "LVC", mark), 0) end
  end)

  it("three clients, three retention states, converge", function()
    local sim, c = world(ANA, BOR, VERA)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[BOR], rs(ZH, 1, 40, OLD))
    eq(prune(c[ANA], 20), 20)
    hello(sim, ANA, BOR, VERA); sim:run(1500)
    eq(digests(c[VERA], c[BOR])[1], digests(c[VERA], c[BOR])[2])
    eq(holds(c[VERA], Ledger.id(ZH, 1)), 1)
    eq(prune(c[VERA], 20), 20)
    local d = digests(c[ANA], c[BOR], c[VERA])
    eq(d[1], d[2]); eq(d[2], d[3])
  end)
end)

describe("ledger F4 sync: a newcomer and a stub holder (Sync:tail)", function()
  it("a newcomer gets a stub holder's bodies once and never again", function()
    local sim, c = world(ANA, BOR) -- Ана holds 1..40 (old) and 41..60 (fresh), pruned; Борис nothing
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 60, EPOCH0))
    eq(prune(c[ANA], 20), 40)
    hello(sim, ANA, BOR); sim:run(400)
    eq(holds(c[BOR], Ledger.id(ZH, 41)), 1); eq(holds(c[BOR], Ledger.id(ZH, 60)), 1); eq(holds(c[BOR], Ledger.id(ZH, 1)), 0)
    local sent = c[ANA].ledgerSync.stats.sent
    give(c[ANA], rs(ZH, 61, 61, EPOCH0)); give(c[BOR], { pay(BOR, 1) }) -- both cells and both digests move
    hello(sim, ANA, BOR); sim:run(400)
    eq(c[ANA].ledgerSync.stats.sent - sent, 1) -- the new entry only, not 41..60 again
    eq(holds(c[BOR], Ledger.id(ZH, 61)), 1)
  end)

  it("the same newcomer over six more differences is sent nothing it holds", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 60, EPOCH0))
    prune(c[ANA], 20)
    hello(sim, ANA, BOR); sim:run(400)
    eq(holds(c[BOR], Ledger.id(ZH, 60)), 1)
    local sent, mark = c[ANA].ledgerSync.stats.sent, #sim.sent
    for n = 1, 6 do
      give(c[BOR], { pay(BOR, n) })
      hello(sim, ANA, BOR); sim:run(400)
    end
    eq(c[ANA].ledgerSync.stats.sent, sent)
    eq(carried(sim, ZH, mark), 0)
    eq(holds(c[ANA], Ledger.id(BOR, 6)), 1) -- the exchanges ran
  end)

  it("a stub holder that answers (the newcomer asks) sends the tail once, too", function()
    local sim, c = world(ANA, VERA) -- Ана, the lower name, is the newcomer and asks
    give(c[VERA], rs(ZH, 1, 40, OLD)); give(c[VERA], rs(ZH, 41, 60, EPOCH0))
    eq(prune(c[VERA], 20), 40)
    hello(sim, ANA, VERA); sim:run(400)
    eq(holds(c[ANA], Ledger.id(ZH, 41)), 1); eq(holds(c[ANA], Ledger.id(ZH, 60)), 1)
    local mark = #sim.sent
    for n = 1, 3 do
      give(c[ANA], { pay(ANA, n) })
      hello(sim, ANA, VERA); sim:run(400)
    end
    eq(carried(sim, ZH, mark), 0)
    eq(holds(c[VERA], Ledger.id(ANA, 3)), 1)
  end)

  it("the marks are kept with the store: the next session sends the newcomer nothing it holds", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 60, EPOCH0))
    prune(c[ANA], 20)
    hello(sim, ANA, BOR); sim:run(400)
    eq(holds(c[BOR], Ledger.id(ZH, 60)), 1)
    local a = sim:relog(ANA) -- a new session: memory is gone, the store stays
    sim:run(31) -- past the login queue
    eq(a.ledger:stubCount(), 40)
    local mark = #sim.sent
    give(c[BOR], { pay(BOR, 1) }); give(a, rs(ZH, 61, 61, EPOCH0))
    hello(sim, ANA, BOR); sim:run(400)
    eq(carried(sim, ZH, mark), 1) -- 61 only
    eq(holds(a, Ledger.id(BOR, 1)), 1); eq(holds(c[BOR], Ledger.id(ZH, 61)), 1)
  end)

  it("a partner that lost its store is sent the tail again", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 60, EPOCH0))
    prune(c[ANA], 20)
    hello(sim, ANA, BOR); sim:run(400)
    sim.envs[BOR].db.ledger = {} -- a new install
    local b = sim:relog(BOR)
    sim:run(31)
    eq(holds(b, Ledger.id(ZH, 41)), 0)
    hello(sim, ANA, BOR); sim:run(400)
    eq(holds(b, Ledger.id(ZH, 41)), 1); eq(holds(b, Ledger.id(ZH, 60)), 1)
  end)

  it("a body that came after my send, below the mark, is still sent (J5)", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 49, EPOCH0)); give(c[ANA], rs(ZH, 51, 60, EPOCH0))
    prune(c[ANA], 20)
    hello(sim, ANA, BOR); sim:run(400)
    eq(holds(c[BOR], Ledger.id(ZH, 60)), 1); eq(holds(c[BOR], Ledger.id(ZH, 50)), 0)
    local mark = #sim.sent
    give(c[ANA], rs(ZH, 50, 50, EPOCH0)) -- relayed to me later, below the 60 Борис was sent
    give(c[BOR], { pay(BOR, 1) })
    hello(sim, ANA, BOR); sim:run(400)
    eq(holds(c[BOR], Ledger.id(ZH, 50)), 1)
    eq(carried(sim, ZH, mark), 1)
  end)

  it("a newcomer after the author was stubbed settles: bounded traffic, no entry resent", function()
    local sim, c = world(ANA, BOR, VERA) -- Ана and Борис both pruned, Вера the newcomer
    for _, name in ipairs({ ANA, BOR }) do give(c[name], rs(ZH, 1, 40, OLD)); give(c[name], rs(ZH, 41, 60, EPOCH0)) end
    prune(c[ANA], 20); prune(c[BOR], 20)
    hello(sim, ANA, BOR, VERA); sim:run(1200)
    eq(holds(c[VERA], Ledger.id(ZH, 41)), 1); eq(holds(c[VERA], Ledger.id(ZH, 1)), 0) -- Cost 2: 1..40 exist nowhere
    eq(carried(sim, ZH, 0), 40) -- 41..60 once from each holder at most
    local mark = #sim.sent
    sim:run(3000) -- the digests still differ: vectors only, every peer gap at most
    eq(carried(sim, ZH, mark), 0)
    local lvc = #whispers(sim, ANA, "LVC", mark) + #whispers(sim, BOR, "LVC", mark) + #whispers(sim, VERA, "LVC", mark)
    ok(lvc <= 2 * 2 * (3000 / C.LEDGER_PEER_GAP + 1), "vectors " .. lvc)
    local lev = #whispers(sim, ANA, "LEV", mark) + #whispers(sim, BOR, "LEV", mark) + #whispers(sim, VERA, "LEV", mark)
    ok(lev <= lvc, "LEVs " .. lev)
  end)
end)

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

describe("ledger F4 sync: no mark keeps a body from a peer that lacks it (bodies loaded from disk)", function()
  it("a reinstall against a heavy author's holder: every D, C, N, P and X of it arrives, and the rest", function()
    local sim, c = world(ANA, BOR)
    local ks = { D = 380, C = 390, P = 400, N = 410, X = 420 }
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], heavy(41, 500, EPOCH0, ks))
    eq(pruneAll(c[ANA], 455), 40)
    local a = sim:relog(ANA); sim:run(31) -- loaded from disk: no body came this session
    rounds(sim, BOR, 3)
    eq(count(c[BOR], 41, 500), 460) -- Борис caught up
    sim.envs[BOR].db.ledger = {} -- then lost his store
    local b = sim:relog(BOR); sim:run(31)
    rounds(sim, BOR, 6, 10)
    ok(kinds(b, ks))
    eq(count(b, 41, 500), 460)
    eq(a.ledger:stubCount(), 40)
  end)

  it("a newcomer offline for a moment mid-exchange later gets every D, C, N, P and X", function()
    local sim, c = world(ANA, BOR)
    local ks = { D = 50, C = 51, P = 55, N = 57, X = 59 }
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], heavy(41, 60, EPOCH0, ks))
    eq(pruneAll(c[ANA], 15), 40)
    sim:offline(BOR); sim:relog(ANA); sim:run(31); sim:online(BOR) -- Ана's login HI does not reach Борис
    hello(sim, ANA, BOR)
    local t = 0
    while holds(c[BOR], Ledger.id(ZH, 41)) == 0 and t < 60 do sim:run(1); t = t + 1 end
    eq(holds(c[BOR], Ledger.id(ZH, 41)), 1); eq(holds(c[BOR], Ledger.id(ZH, 55)), 0)
    sim:offline(BOR); sim:run(40); sim:online(BOR) -- Ана's next LEVs are lost
    rounds(sim, BOR, 8)
    ok(kinds(c[BOR], ks))
    local a = sim:relog(ANA); sim:run(31)
    rounds(sim, BOR, 2, 10)
    ok(kinds(c[BOR], ks))
  end)

  it("a holder that answers, its newcomer offline mid-exchange: the P arrives later", function()
    local sim, c = world(ANA, VERA) -- Ана, the lower name, is the newcomer and asks
    local ks = { D = 50, C = 51, P = 55, N = 57, X = 59 }
    give(c[VERA], rs(ZH, 1, 40, OLD)); give(c[VERA], heavy(41, 60, EPOCH0, ks))
    eq(pruneAll(c[VERA], 15), 40)
    sim:offline(ANA); sim:relog(VERA); sim:run(31); sim:online(ANA)
    hello(sim, ANA, VERA)
    local t = 0
    while holds(c[ANA], Ledger.id(ZH, 41)) == 0 and t < 60 do sim:run(1); t = t + 1 end
    eq(holds(c[ANA], Ledger.id(ZH, 55)), 0)
    sim:offline(ANA); sim:run(40); sim:online(ANA) -- Вера's exchange ended heard (Ана's f came first): its LEVs count as carried
    for k = 1, 2 do give(c[ANA], { pay(ANA, k) }); hello(sim, ANA, VERA); sim:run(400) end
    eq(holds(c[ANA], Ledger.id(ZH, 55)), 0) -- not again within a day of this session (Ruling F4-F) ...
    sim:relog(VERA); sim:run(31) -- ... her next session sends them once more
    for k = 3, 5 do give(c[ANA], { pay(ANA, k) }); hello(sim, ANA, VERA); sim:run(400) end
    ok(kinds(c[ANA], ks))
  end)

  it("... or a day later in the same session", function()
    local sim, c = world(ANA, VERA)
    local ks = { D = 50, C = 51, P = 55, N = 57, X = 59 }
    give(c[VERA], rs(ZH, 1, 40, OLD)); give(c[VERA], heavy(41, 60, EPOCH0, ks))
    eq(pruneAll(c[VERA], 15), 40)
    sim:offline(ANA); sim:relog(VERA); sim:run(31); sim:online(ANA)
    hello(sim, ANA, VERA)
    local t = 0
    while holds(c[ANA], Ledger.id(ZH, 41)) == 0 and t < 60 do sim:run(1); t = t + 1 end
    sim:offline(ANA); sim:run(40); sim:online(ANA)
    sim:run(C.LEDGER_REFUSED_TTL)
    for k = 1, 3 do give(c[ANA], { pay(ANA, k) }); hello(sim, ANA, VERA); sim:run(400) end
    ok(kinds(c[ANA], ks))
  end)

  it("a body that came late, below the mark, reaches the peer after the holder relogs", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 49, EPOCH0)); give(c[ANA], rs(ZH, 51, 60, EPOCH0))
    eq(pruneAll(c[ANA], 19), 40)
    local a = sim:relog(ANA); sim:run(31)
    hello(sim, ANA, BOR); sim:run(400)
    eq(holds(c[BOR], Ledger.id(ZH, 60)), 1); eq(holds(c[BOR], Ledger.id(ZH, 50)), 0)
    give(a, { pay(ZH, 50) }) -- a P of ZH relayed to Ана late, below the mark 60
    a = sim:relog(ANA); sim:run(31)
    rounds(sim, BOR, 4)
    eq(holds(c[BOR], Ledger.id(ZH, 50)), 1)
  end)

  it("a holder that took more than an exchange of an author this session delivers all of it, and the authors after it", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD))
    eq(pruneAll(c[ANA], 0), 40)
    local a = sim:relog(ANA); sim:run(31) -- the stubs loaded from disk
    give(a, heavy(41, 500, EPOCH0, { D = 300, C = 310, P = 450, N = 460, X = 470 })) -- came this session
    give(a, { { i = Ledger.id(YANA, 1), k = "P", at = EPOCH0, f = ANA, c = 500, how = "hand" } })
    rounds(sim, BOR, 5)
    eq(count(c[BOR], 41, 500), 460)
    eq(holds(c[BOR], Ledger.id(YANA, 1)), 1)
  end)

  it("what a cut exchange queued below an older mark and did not send goes in the next one", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 400, EPOCH0))
    eq(pruneAll(c[ANA], 360), 40)
    local a = sim:relog(ANA); sim:run(31)
    rounds(sim, BOR, 3)
    eq(count(c[BOR], 41, 400), 360) -- caught up: Ана's mark for Борис is 400
    give(a, rs(ZH, 41, 400, EPOCH0, 2)) -- 360 twins come to Ана, more than one exchange carries
    rounds(sim, BOR, 4, 10)
    eq(count(c[BOR], 41, 400), 720)
  end)
end)

describe("ledger F4 sync: the marks in the store", function()
  local clock = { t = EPOCH0 }
  local function sync(store)
    local L = Ledger.new(store, ANA, function() return clock.t end)
    return ns.LedgerSync.new({ env = { now = function() return 0 end } }, L, nil), L
  end
  -- ZH 1..3 as stubs, then ZH `from`..`to` as bodies that came this session.
  local function stubbed(L, from, to)
    for _, e in ipairs(rs(ZH, 1, 3, OLD)) do L:add(e, BOR) end
    room(0, function() L:prune(EPOCH0, 100) end)
    for _, e in ipairs(rs(ZH, from or 4, to or 6, EPOCH0)) do L:add(e, BOR) end
  end
  -- An exchange with `peer`, as Sync:open and Sync:vector make it, at its end: both f (heard), acted on ZH.
  local function ex(peer, L, acted, more)
    local x = { peer = peer, hw = {}, left = {}, q = {}, qs = {}, ag = {}, re = {}, nre = 0, rev0 = L.rev, acted = acted or { [ZH] = "s" }, fMine = true, fTheirs = true }
    for k, v in pairs(more or {}) do x[k] = v end
    return x
  end
  local CELL = { n = 0, x = "0123456789ab" } -- the peer holds some of ZH, none of 1..3

  it("a load keeps sound rows of the last 7 days, at most 200 peers (the oldest go), only authors I hold stubs of", function()
    clock.t = EPOCH0
    local now = EPOCH0
    local hw = {
      [BOR] = { at = now - 10, a = { [ZH] = 60, [GOSHO] = 0, [ELENA] = 1.5, [""] = 3, [DARA] = 7 } },
      [VERA] = { at = now - C.LEDGER_HW_KEEP, a = { [ZH] = 60 } },
      [DARA] = { at = "x", a = { [ZH] = 60 } },
      ["a|b"] = { at = now, a = { [ZH] = 60 } },
      [ELENA] = 5,
    }
    for j = 1, 201 do hw["Пир" .. j] = { at = now - 1000 + j, a = { [ZH] = j } } end
    local s, L = sync({ hw = hw, st = { [ZH] = { ["1." .. ("ab"):rep(8)] = true }, [GOSHO] = { ["1." .. ("cd"):rep(8)] = true } } })
    eq(L:stubTop(ZH), 1)
    eq(s.high[BOR].a[ZH], 60); eq(s.high[BOR].a[GOSHO], nil); eq(s.high[BOR].a[ELENA], nil); eq(s.high[BOR].a[""], nil)
    eq(s.high[BOR].a[DARA], nil) -- no stub of hers: dropped (a row's authors are bounded by my stubs)
    eq(s.high[VERA], nil); eq(s.high[DARA], nil); eq(s.high["a|b"], nil); eq(s.high[ELENA], nil)
    local count = 0
    for _ in pairs(L.store.hw) do count = count + 1 end
    eq(count, C.LEDGER_HW_PEERS)
    eq(s.high["Пир1"], nil); eq(s.high["Пир2"], nil); ok(s.high["Пир201"], "the newest stays")
    eq(L.store.hw, s.high)
  end)

  it("a mark is noted in its exchange and committed when the exchange was heard, cut or not", function()
    clock.t = EPOCH0
    local hw = {}
    for j = 1, C.LEDGER_HW_PEERS do hw["Пир" .. j] = { at = EPOCH0 - 1000 + j, a = {} } end
    local s, L = sync({ hw = hw })
    L:add(pay(GOSHO, 1), BOR)
    stubbed(L)
    local x = ex(DARA, L)
    s:mark(x, (L:get(Ledger.id(GOSHO, 1)))); s:mark(x, (L:get(Ledger.id(ZH, 5)))); s:mark(x, (L:get(Ledger.id(ZH, 4))))
    eq(x.hw[GOSHO], nil); eq(x.hw[ZH], 5); eq(#x.left, 3)
    eq(s.high[DARA], nil) -- nothing before its end
    s:ended(ex(DARA, L, nil, { fTheirs = false, hw = { [ZH] = 6 } })) -- the partner's last word never came
    s:ended(ex(DARA, L, nil, { hw = { [ZH] = 6 } }), true) -- capped
    eq(s.high[DARA], nil); eq(s.since[DARA], nil)
    eq(#s:tail(ex(DARA, L), ZH, CELL), 3)
    local b6 = L:get(Ledger.id(ZH, 6))
    s:ended(ex(DARA, L, nil, { cut = true, hw = { [ZH] = 5 }, rest = { b6 } })) -- cut, heard: committed (final review I1)
    eq(s.high[DARA].a[ZH], 5); eq(s.high[DARA].at, EPOCH0); eq(L.store.hw[DARA].a[ZH], 5)
    eq(s.high["Пир1"], nil); ok(s.high["Пир2"], "the next oldest stays")
    local tail = s:tail(ex(DARA, L), ZH, CELL)
    eq(#tail, 1); eq(tail[1], b6) -- 4 and 5 went
    s:ended(ex(DARA, L, nil, { cut = true, hw = { [ZH] = 6 }, rest = { b6 } })) -- no mark reaches what was queued and not sent
    eq(s.high[DARA].a[ZH], 5)
    s:ended(x)
    eq(s.high[DARA].a[ZH], 5) -- a mark only grows
    s:ended(ex(DARA, L, nil, { hw = { [ZH] = 6 }, left = { b6 } }))
    eq(s.high[DARA].a[ZH], 6); eq(#s:tail(ex(DARA, L), ZH, CELL), 0)
  end)

  it("a row lives LEDGER_HW_KEEP s from its first commit: a later commit keeps its date", function()
    clock.t = EPOCH0
    local s, L = sync({})
    stubbed(L)
    s:ended(ex(DARA, L, nil, { hw = { [ZH] = 5 } }))
    clock.t = EPOCH0 + C.LEDGER_HW_KEEP - 10
    s:ended(ex(DARA, L, nil, { hw = { [ZH] = 6 } }))
    eq(s.high[DARA].at, EPOCH0); eq(s.high[DARA].a[ZH], 6)
    eq(#s:tail(ex(DARA, L), ZH, CELL), 0)
    clock.t = EPOCH0 + C.LEDGER_HW_KEEP
    eq(#s:tail(ex(DARA, L), ZH, CELL), 3) -- the row went: L:above again
    eq(s.high[DARA], nil)
    s:ended(ex(DARA, L, nil, { hw = { [ZH] = 6 } }))
    eq(s.high[DARA].at, EPOCH0 + C.LEDGER_HW_KEEP) -- a new row
    clock.t = EPOCH0 + 2 * C.LEDGER_HW_KEEP
    local s2 = sync(L.store) -- the next session, a week on: the load drops it
    eq(s2.high[DARA], nil)
  end)

  it("the tail leaves out for good only an R or S: a D, C, N, P or X at or below the mark is to be re-sent", function()
    clock.t = EPOCH0
    local s, L = sync({})
    stubbed(L, 4, 3)
    for _, e in ipairs(heavy(4, 9, EPOCH0, { D = 4, C = 5, N = 6, P = 7, X = 9 })) do eq(L:add(e, BOR), "new") end
    s:ended(ex(DARA, L, nil, { hw = { [ZH] = 9 } }))
    local tail, again = s:tail(ex(DARA, L), ZH, CELL)
    eq(#tail, 0); eq(#again, 5) -- not the R at 8
    for _, b in ipairs(again) do ok(b.k ~= "R", b.k) end
    local x = ex(DARA, L)
    s:queue(x, tail, again); s:resend(x)
    eq(#x.q, 5) -- they go, behind what no mark covers (core/LedgerSyncAgain.lua)
  end)

  it("an exchange that did not act on an author leaves that author's late bodies to be sent", function()
    clock.t = EPOCH0
    local s, L = sync({})
    stubbed(L); for _, e in ipairs(rs(ZH, 8, 9, EPOCH0)) do L:add(e, BOR) end
    local x1 = ex(DARA, L)
    for _, b in ipairs(L:above(ZH, 0)) do s:mark(x1, b) end
    s:ended(x1)
    eq(#s:tail(x1, ZH, CELL), 0) -- all of it went
    L:add(rs(ZH, 7, 7, EPOCH0)[1], BOR) -- late, below the mark 9
    s:ended(ex(DARA, L, { [GOSHO] = "s" })) -- heard, but it did not act on ZH
    local tail = s:tail(ex(DARA, L), ZH, CELL)
    eq(#tail, 1); eq(tail[1].i, Ledger.id(ZH, 7))
    eq(#s:tail(ex(DARA, L), ZH, nil), 6) -- a partner that holds nothing of ZH: everything, as before
    eq(s.high[DARA].a[ZH], nil) -- and my mark of it went
  end)

  it("what a cut exchange queued and did not send is owed, below an older mark too", function()
    clock.t = EPOCH0
    local s, L = sync({})
    stubbed(L); for _, e in ipairs(rs(ZH, 8, 9, EPOCH0)) do L:add(e, BOR) end
    s:ended(ex(DARA, L, nil, { hw = { [ZH] = 9 } })) -- the mark: 9
    L:add(rs(ZH, 7, 7, EPOCH0)[1], BOR)
    local b7 = L:get(Ledger.id(ZH, 7))
    s:ended(ex(DARA, L, nil, { cut = true, rest = { b7 } })) -- 7 queued, the exchange cut before it left
    local tail = s:tail(ex(DARA, L), ZH, CELL)
    eq(#tail, 1); eq(tail[1], b7)
    s:ended(ex(DARA, L, nil, { fTheirs = false, left = { b7 } })) -- it left, but the end was not heard
    eq(#s:tail(ex(DARA, L), ZH, CELL), 1)
    s:ended(ex(DARA, L, nil, { left = { b7 } }))
    eq(#s:tail(ex(DARA, L), ZH, CELL), 0)
  end)
end)

describe("ledger F4: the prune of a session (Net:prune)", function()
  it("the prune runs once after login, off the hash and off an exchange", function()
    room(0, function()
      local sim, c = world(ANA)
      give(c[ANA], rs(ZH, 1, 5, OLD))
      local ld = c[ANA].presence.sentLd
      sim:run(C.LEDGER_PRUNE_WAIT - 2) -- t = PRUNE_WAIT - 1 (the login was at 0)
      eq(c[ANA].ledger:stubCount(), 0)
      sim:run(7)
      eq(c[ANA].ledger:stubCount(), 5)
      eq(c[ANA].presence.sentLd, ld)
      give(c[ANA], rs(ZH, 6, 8, OLD)) -- later in the same session: no second prune
      sim:run(600)
      eq(c[ANA].ledger:stubCount(), 5)
      local a = sim:relog(ANA) -- the next session prunes again
      sim:run(C.LEDGER_PRUNE_WAIT + 6)
      eq(a.ledger:stubCount(), 8)
    end)
  end)

  it("a client stopped before the prune is due never prunes (Client:stop cancels the timer)", function()
    room(0, function()
      local sim, c = world(ANA)
      give(c[ANA], rs(ZH, 1, 5, OLD))
      ok(c[ANA].ledgerNet.pruneTimer, "armed")
      c[ANA]:stop()
      eq(c[ANA].ledgerNet.pruneTimer, nil)
      sim:run(C.LEDGER_PRUNE_WAIT + 30)
      eq(c[ANA].ledger:stubCount(), 0)
    end)
  end)

  it("the prune waits while an exchange runs", function()
    room(0, function()
      local sim, c = world(ANA, BOR)
      give(c[ANA], rs(ZH, 1, 5, OLD))
      local sync = c[ANA].ledgerSync
      sync.by[BOR] = {} -- an exchange is open
      sim:run(C.LEDGER_PRUNE_WAIT + 20)
      eq(c[ANA].ledger:stubCount(), 0)
      sync.by[BOR] = nil
      sim:run(6)
      eq(c[ANA].ledger:stubCount(), 5)
    end)
  end)

  it("a prune of 1200 candidates goes in steps", function()
    room(0, function()
      local sim, c = world(ANA)
      give(c[ANA], rs(ZH, 1, 1200, OLD))
      sim:run(C.LEDGER_PRUNE_WAIT - 2)
      local last, most, steps = c[ANA].ledger:stubCount(), 0, 0
      eq(last, 0)
      while sim.clock < C.LEDGER_PRUNE_WAIT + 20 do -- the login was at 0: within LEDGER_PRUNE_WAIT + 20 s
        sim:run(1)
        local now = c[ANA].ledger:stubCount()
        if now > last then steps = steps + 1 end
        most, last = math.max(most, now - last), now
      end
      eq(sim.clock, C.LEDGER_PRUNE_WAIT + 20); eq(last, 1200)
      ok(most <= C.LEDGER_PRUNE_STEP, "at most a step a moment: " .. most)
      ok(steps >= 3, "steps " .. steps)
    end)
  end)

  it("a denied R or S is never stubbed", function()
    local sim, c = world(ANA)
    local r = rs(ZH, 1, 3, OLD)
    give(c[ANA], r)
    local b = c[ANA].ledger:get(r[2].i)
    give(c[ANA], { { i = Ledger.id(ZH, 4), k = "X", at = OLD + 1, r = b.i, h = b.h } }, ZH)
    ok(c[ANA].ledger:denied(b), "denied")
    eq(c[ANA].ledger:stub(b), false)
    eq(prune(c[ANA], 0), 2)
    eq(holds(c[ANA], r[2].i), 1); eq(holds(c[ANA], r[1].i), 0)
    sim:run(0)
  end)
end)

ns.LedgerNet.size = stand
