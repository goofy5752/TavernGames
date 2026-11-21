Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local ns = Sim.ns
local Ledger, C, U = ns.Ledger, ns.Const, ns.Util

-- The real wire, as wow/Adapter.lua installs it: the sync cuts its batches and
-- pages, and the GUILD budget counts its parts, by packed bytes (restored at the end of this file).
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
local stand = ns.LedgerNet.size
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end
local function packed(msg) return #wire:pack(msg) end

-- "Ана" < "Борис" < "Вера" < "Гошо" < "Дара" < "Елена" by bytes; Жана is an author who is never online.
local ANA, BOR, VERA, GOSHO, DARA, ELENA = "Ана Иванова", "Борис Петров", "Вера Колева", "Гошо Тодоров",
  "Дара Маринова", "Елена Попова"
local ZH, YA = "Жана Стоева", "Яна Стоянова" -- by bytes after everyone above
local EPOCH0 = 1700000000

-- The names online, in the guild, past their login queues.
local function world(...)
  local sim, c = Sim.new(), {}
  for _, name in ipairs({ ... }) do c[name] = sim:add(name) end
  sim:run(1)
  sim:settle()
  return sim, c
end

-- A P entry of `author` numbered n (c: its amount, also what makes a twin).
local function pay(author, n, c, at)
  return { i = Ledger.id(author, n), k = "P", at = at or EPOCH0 + n, f = author == ZH and ANA or ZH, c = c or 100 + n, how = "hand" }
end
-- Puts entries into a client's store as if relayed by `from` (default: Жана, no client).
local function give(client, list, from)
  for _, e in ipairs(list) do client.ledger:add(e, from or "Някой") end
end
local function pays(author, from, to, c)
  local out = {}
  for n = from, to do out[#out + 1] = pay(author, n, c) end
  return out
end
-- Each named client tells the guild its digest (a GUILD HI).
local function hello(sim, ...)
  for _, name in ipairs({ ... }) do sim.clients[name].presence:sendGuildHi(false) end
  sim:run(0)
end
-- The whispers of type t from `from` (to `to`, when given) after sim.sent[mark]; "LVC" is an asking one, "LVC r" an answer.
local function whispers(sim, from, t, mark, to)
  local out, r = {}, t == "LVC r" or nil
  if r then t = "LVC" end
  for j, s in ipairs(sim.sent) do
    if j > (mark or 0) and s.from == from and s.channel == "WHISPER" and s.msg.t == t and (not to or s.target == to)
      and (t ~= "LVC" or s.msg.r == r) then
      out[#out + 1] = s
    end
  end
  return out
end
local function entries(list) local n = 0; for _, s in ipairs(list) do n = n + #s.msg.ev end; return n end
local function digests(...)
  local out = {}
  for j, c in ipairs({ ... }) do out[j] = c.ledger:digest() end
  return out
end
local function holds(c, id) local first, more = c.ledger:get(id); return first and 1 + (more and #more or 0) or 0 end
-- The jitter of the brief: LEDGER_JITTER_MIN + (byte sum of me .. peer .. ld) % 16.
local function jitter(me, peer, ld)
  local sum, s = 0, me .. peer .. ld
  for j = 1, #s do sum = sum + s:byte(j) end
  return C.LEDGER_JITTER_MIN + sum % 16
end
-- A name of exactly `len` bytes, Cyrillic letters (a last odd byte Latin), from a fixed sequence.
local seed = 11
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return math.floor(seed / 65536) % n end
local function named(len)
  local out, b = {}, 0
  while b + 2 <= len do
    local c = 0x430 + rnd(32)
    out[#out + 1] = string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64); b = b + 2
  end
  if b < len then out[#out + 1] = string.char(97 + rnd(26)) end
  return table.concat(out)
end

describe("ledger sync: the digest in HI", function()
  it("HI carries the digest and it follows the log; a bot's HI has none", function()
    local sim, c = world(ANA, BOR)
    local a = c[ANA]
    local function lastHi()
      local hi
      for _, s in ipairs(sim.sent) do if s.from == ANA and s.msg.t == "HI" and s.channel == "GUILD" then hi = s.msg end end
      return hi
    end
    eq(lastHi().ld, a.ledger:digest()); eq(#lastHi().ld, 8)
    local before = a.ledger:digest()
    ok(a.ledgerNet:make("P", { f = BOR, c = 100, how = "hand" }), "made")
    sim:run(120) -- the next HI: the heartbeat
    ok(lastHi().ld ~= before, "a new digest"); eq(lastHi().ld, a.ledger:digest())
    eq(c[BOR].presence.peers[ANA].ld, a.ledger:digest())
    local name = "Бот Тестов"
    local bot = sim:join(name, sim.makeEnv(name, "WARRIOR"))
    sim:run(1)
    local hi
    for _, s in ipairs(sim.sent) do if s.from == name and s.msg.t == "HI" then hi = s.msg end end
    ok(hi, "the bot said HI"); eq(hi.ld, nil); eq(bot.ledgerSync, nil)
    eq(a.presence.peers[name].ld, nil)
  end)
end)

describe("ledger sync: the exchange", function()
  it("a newcomer behind by 20 entries catches up from one partner", function()
    local sim, c = world(BOR, VERA)
    for n = 1, 20 do c[VERA].ledgerNet:make("P", { f = BOR, c = 100 + n, how = "hand" }); sim:run(1) end
    sim:run(3)
    eq(c[BOR].ledger:digest(), c[VERA].ledger:digest())
    local mark = #sim.sent
    local a = sim:add(ANA)
    sim:run(40)
    local lvc = whispers(sim, ANA, "LVC", mark)
    eq(#lvc, 1)
    local from = lvc[1].target
    ok(from == BOR or from == VERA, "asked one of them")
    local other = from == BOR and VERA or BOR
    local lev = whispers(sim, from, "LEV", mark, ANA)
    eq(#lev, 4); eq(entries(lev), 20); eq(lev[4].msg.f, true)
    for _, s in ipairs(lev) do ok(#s.msg.ev <= 6, "at most 6") end
    eq(#whispers(sim, other, "LEV", mark), 0) -- exactly one responder for these 20
    eq(digests(a, c[BOR], c[VERA]), { c[BOR].ledger:digest(), c[BOR].ledger:digest(), c[BOR].ledger:digest() })
    eq(sim:count(function(s) return s.at >= lvc[1].at and s.channel == "GUILD" and s.msg.t ~= "HI" end), 0)
    eq(a.ledgerSync:busy(), false); eq(a.ledgerSync.stats.got, 20); eq(sim.clients[from].ledgerSync.stats.sent, 20)
  end)

  it("the lower name starts, the higher one never does", function()
    local sim, c = world(ANA, VERA)
    give(c[ANA], pays(ZH, 1, 5))
    local mark = #sim.sent
    hello(sim, ANA, VERA)
    sim:run(40)
    eq(#whispers(sim, ANA, "LVC", mark), 1); eq(#whispers(sim, VERA, "LVC", mark), 0)
    eq(digests(c[ANA], c[VERA]), digests(c[ANA], c[ANA]))
  end)

  it("both directions in one exchange", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], pays(DARA, 1, 3)); give(c[BOR], pays(ELENA, 1, 5))
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(40)
    eq(#whispers(sim, ANA, "LVC", mark), 1)
    local back = whispers(sim, BOR, "LVC r", mark)
    eq(#back, 1); eq(back[1].msg.r, true); eq(back[1].msg.a, { [DARA] = { n = 0, x = "000000" } })
    eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
    eq(holds(c[BOR], DARA .. ":3"), 1); eq(holds(c[ANA], ELENA .. ":5"), 1)
  end)

  it("a hole is healed", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], { pay(VERA, 1), pay(VERA, 2), pay(VERA, 3), pay(VERA, 5) }); give(c[BOR], pays(VERA, 1, 5))
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(40)
    local ids = {}
    for _, s in ipairs(whispers(sim, BOR, "LEV", mark, ANA)) do for _, e in ipairs(s.msg.ev) do ids[#ids + 1] = e.i end end
    eq(ids, { VERA .. ":4", VERA .. ":5" }) -- 5 again, a dup
    eq(holds(c[ANA], VERA .. ":4"), 1); eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
  end)
end)

describe("ledger sync: conflicts", function()
  it("equal runs, different sets, are healed by LID", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], pays(VERA, 1, 3)); give(c[ANA], { pay(VERA, 6) })
    give(c[BOR], pays(VERA, 1, 3)); give(c[BOR], { pay(VERA, 7) })
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(40)
    local mine, theirs = whispers(sim, ANA, "LID", mark), whispers(sim, BOR, "LID", mark)
    eq(#mine, 1); eq(#theirs, 1); eq(mine[1].msg.r, nil); eq(theirs[1].msg.r, true)
    eq(mine[1].msg.au, VERA); eq(#mine[1].msg.l, 1); eq(#theirs[1].msg.l, 1)
    for _, cl in ipairs({ c[ANA], c[BOR] }) do eq(holds(cl, VERA .. ":6"), 1); eq(holds(cl, VERA .. ":7"), 1) end
    eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
  end)

  it("twins reach everyone, also inside the run", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], pays(VERA, 1, 3)); give(c[ANA], { pay(VERA, 4, 500) })
    give(c[BOR], pays(VERA, 1, 3)); give(c[BOR], { pay(VERA, 4, 900) })
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(40)
    for _, cl in ipairs({ c[ANA], c[BOR] }) do
      local first, more = cl.ledger:get(VERA .. ":4")
      ok(first and more and #more == 1, "both bodies")
      eq({ first.c + more[1].c }, { 1400 })
    end
    eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
    -- Both held one body under the id: the lists of the scope were equal, so Ана sent her whole list once.
    local lid = whispers(sim, ANA, "LID", mark)
    eq(#lid, 2); eq(#lid[1].msg.l, 0); eq(#lid[2].msg.l, 4)
  end)

  it("twins held inside the run are listed: one LID each way", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], pays(VERA, 1, 4)); give(c[ANA], { pay(VERA, 2, 7) })
    give(c[BOR], pays(VERA, 1, 4)); give(c[BOR], { pay(VERA, 2, 8) })
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(40)
    eq(holds(c[ANA], VERA .. ":2"), 3); eq(holds(c[BOR], VERA .. ":2"), 3)
    eq(#whispers(sim, ANA, "LID", mark), 1); eq(#whispers(sim, ANA, "LID", mark)[1].msg.l, 2)
    eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
  end)

  it("twins of one id held as twins: every body is fetched", function()

    local sim, c = world(ANA, BOR)
    give(c[ANA], { pay(VERA, 4, 1), pay(VERA, 4, 2) }); give(c[BOR], { pay(VERA, 4, 2), pay(VERA, 4, 3) })
    hello(sim, ANA, BOR)
    sim:run(40)
    eq(holds(c[ANA], VERA .. ":4"), 3); eq(holds(c[BOR], VERA .. ":4"), 3)
    eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
  end)

  -- The bodies of Жана:4 by ascending h (the eviction order).
  local function bodies(count)
    local list = {}
    for k = 1, count do list[k] = pay(ZH, 4, 1000 + k) end
    local L = Ledger.new({}, "Никой", function() return EPOCH0 end)
    local h = {}
    for _, e in ipairs(list) do h[e] = select(2, L:add(U.copy(e), "Някой")).h end
    table.sort(list, function(p, q) return h[p] < h[q] end)
    return list
  end

  it("three bodies converge (F4): every client holds the same set", function()
    local b = bodies(4)
    local sim, c = world(ANA, BOR, VERA)
    give(c[ANA], { b[1], b[2] }); give(c[BOR], { b[2], b[3] }); give(c[VERA], { b[4] })
    hello(sim, ANA, BOR, VERA)
    sim:run(900)
    for _, cl in ipairs({ c[ANA], c[BOR], c[VERA] }) do eq(holds(cl, ZH .. ":4"), 4) end
    eq(digests(c[ANA], c[BOR], c[VERA]), digests(c[ANA], c[ANA], c[ANA]))
  end)

  it("five bodies: the highest h is dropped everywhere", function()
    local b = bodies(5)
    local sim, c = world(ANA, BOR, VERA)
    give(c[ANA], { b[1], b[2] }); give(c[BOR], { b[2], b[3] }); give(c[VERA], { b[4], b[5] })
    hello(sim, ANA, BOR, VERA)
    sim:run(900)
    for _, cl in ipairs({ c[ANA], c[BOR], c[VERA] }) do
      local first, more = cl.ledger:get(ZH .. ":4")
      local got = { first.c }
      for _, x in ipairs(more or {}) do got[#got + 1] = x.c end
      table.sort(got)
      local want = { b[1].c, b[2].c, b[3].c, b[4].c }
      table.sort(want)
      eq(got, want)
    end
    eq(digests(c[ANA], c[BOR], c[VERA]), digests(c[ANA], c[ANA], c[ANA]))
  end)

  it("a denied forgery syncs with its denial", function()
    local sim, c = world(ANA, BOR)
    c[ANA].ledger.store.me[ANA].seq = 10
    c[ANA]:stop()
    local a = sim:relog(ANA)
    sim:run(1); sim:settle()
    local forged = pay(ANA, 9, 777)
    give(c[BOR], { forged }, VERA)
    hello(sim, BOR)
    sim:run(60)
    local held = a.ledger:get(forged.i)
    ok(held, "the exchange brought it"); eq(a.ledger:denied(held), true)
    local x = c[BOR].ledger:get(ANA .. ":11")
    ok(x and x.k == "X" and x.r == forged.i, "Борис holds the X"); eq(c[BOR].ledger:denied(c[BOR].ledger:get(forged.i)), true)
    sim:run(200)
    eq(a.ledger:digest(), c[BOR].ledger:digest())
  end)
end)

describe("ledger sync: limits", function()
  it("a lying partner cannot make me upload everything; the next exchange continues", function()
    local sim, c = world(ANA, BOR)
    give(c[BOR], pays(ZH, 1, 400))
    local mark = #sim.sent
    -- A vector that lacks every author, whispered by hand under Ана's name: at most 300 go
    -- (50 batches in 100 s, before the heartbeat at 120 s tells Ана that she really lacks them).
    c[BOR].ledgerSync:receive(ANA, { v = 1, t = "LVC", a = {} })
    sim:run(110)
    local lev = whispers(sim, BOR, "LEV", mark, ANA)
    eq(entries(lev), 300); eq(lev[#lev].msg.f, true)
    eq(c[ANA].ledger:seen(ZH), 0) -- outside an exchange of hers: Жана's entries are not taken
    -- Ана really lacks them: one exchange brings 300, the next one the rest.
    while not (c[ANA].ledger:seen(ZH) > 0 and not c[ANA].ledgerSync:busy()) and sim.clock < 700 do sim:run(1) end
    eq(c[ANA].ledger:seen(ZH), 300); eq(holds(c[ANA], ZH .. ":300"), 1)
    ok(c[ANA].ledger:digest() ~= c[BOR].ledger:digest(), "not yet")
    sim:run(600)
    eq(c[ANA].ledger:seen(ZH), 400); eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
  end)

  it("a LEV of foreign authors outside an exchange is dropped; inside one it is taken, relayed", function()
    local sim, c = world(ANA, BOR)
    local a = c[ANA]
    local foreign = { v = 1, t = "LEV", ev = { pay(VERA, 1), pay(VERA, 2) } }
    a:receive("WHISPER", BOR, U.copy(foreign)); sim:run(1)
    eq(a.ledger:seen(VERA), 0)
    a:receive("WHISPER", BOR, { v = 1, t = "LEV", ev = { pay(BOR, 3), pay(VERA, 3) } }); sim:run(1)
    eq(a.ledger:seen(BOR), 0) -- one foreign entry: dropped whole
    a:receive("WHISPER", BOR, { v = 1, t = "LEV", ev = { pay(BOR, 1) } }); sim:run(1)
    local own = a.ledger:get(BOR .. ":1")
    ok(own, "the sender's own: taken"); eq(own.dr, true)
    -- Inside an open exchange with Борис (Ана asks him: he holds 60 entries she lacks).
    give(c[BOR], pays(GOSHO, 1, 60))
    hello(sim, BOR)
    sim:run(jitter(ANA, BOR, c[BOR].ledger:digest()))
    ok(a.ledgerSync.ask and a.ledgerSync.ask.peer == BOR, "an exchange with Борис is open")
    a:receive("WHISPER", BOR, U.copy(foreign))
    local got = a.ledger:get(VERA .. ":1")
    ok(got, "taken in the exchange"); eq(got.rl, true); eq(got.dr, nil)
    a:receive("WHISPER", BOR, { v = 1, t = "LEV", ev = { pay(BOR, 2) } })
    eq(a.ledger:get(BOR .. ":2").dr, true)
    local seven = { v = 1, t = "LEV", ev = pays(DARA, 1, 7) }
    a:receive("WHISPER", BOR, seven)
    eq(a.ledger:seen(DARA), 0) -- 7 entries: dropped whole
    a:receive("WHISPER", BOR, { v = 1, t = "LEV", ev = pays(DARA, 1, 6) })
    eq(a.ledger:seen(DARA), 6)
    -- One exchange takes at most LEDGER_EXCHANGE_MAX entries.
    local took = a.ledgerSync.ask.took
    for k = 0, 50 do a:receive("WHISPER", BOR, { v = 1, t = "LEV", ev = pays(YA, 6 * k + 1, 6 * k + 6) }) end
    eq(a.ledgerSync.ask.took, C.LEDGER_EXCHANGE_MAX); eq(a.ledger:seen(YA), C.LEDGER_EXCHANGE_MAX - took)
  end)

  it("an exchange waits while in an instance", function()
    local sim, c = world(ANA, BOR)
    local inside = { [ANA] = true, [BOR] = false }
    for _, name in ipairs({ ANA, BOR }) do
      c[name].env.status = function() return { combat = false, instance = inside[name], busy = false } end
    end
    give(c[BOR], pays(ZH, 1, 60))
    local mark = #sim.sent
    hello(sim, BOR)
    sim:run(60)
    eq(#whispers(sim, ANA, "LVC", mark), 0)
    inside[ANA] = false
    sim:run(25)
    eq(#whispers(sim, ANA, "LVC", mark), 1)
    local lev = whispers(sim, BOR, "LEV", mark)
    ok(#lev >= 2 and #lev < 10, "running: " .. #lev)
    inside[BOR] = true
    local now = #lev
    sim:run(10)
    eq(#whispers(sim, BOR, "LEV", mark), now) -- no batch in the instance
    inside[BOR] = false
    sim:run(30)
    eq(entries(whispers(sim, BOR, "LEV", mark)), 60); eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
  end)

  it("one exchange at a time: a serving responder ignores another LVC, whose exchange ends after 30 s", function()
    local names = { ANA, BOR, VERA, GOSHO, DARA, ELENA }
    local sim, c = world(unpack(names))
    for j, name in ipairs(names) do give(c[name], { pay(ZH, j) }) end
    give(c[VERA], pays(ZH, 10, 40)) -- Ана's exchange with Вера lasts a while
    local most = 0
    hello(sim, unpack(names))
    for _ = 1, 600 do
      sim:run(1)
      local open = 0
      for _ in pairs(c[ANA].ledgerSync.by) do open = open + 1 end
      most = math.max(most, open)
    end
    eq(most, 1)
    local d = c[ANA].ledger:digest()
    for _, name in ipairs(names) do eq(c[name].ledger:digest(), d) end
    -- Вера serves Ана; Борис's LVC to her is ignored and his exchange ends exactly 30 s after it.
    give(c[ANA], pays(ELENA, 1, 60)); give(c[BOR], { pay(DARA, 1) })
    local mark = #sim.sent
    c[ANA].ledgerSync:begin(VERA)
    sim:run(1)
    ok(c[VERA].ledgerSync.serve and c[VERA].ledgerSync.serve.peer == ANA, "Вера serves Ана")
    c[BOR].ledgerSync:begin(VERA)
    sim:run(0)
    eq(#whispers(sim, BOR, "LVC", mark, VERA), 1)
    sim:run(29); ok(c[BOR].ledgerSync.ask, "still open at 29 s"); eq(#whispers(sim, VERA, "LVC", mark, BOR), 0)
    eq(#whispers(sim, VERA, "LEV", mark, BOR), 0)
    sim:run(1); eq(c[BOR].ledgerSync.ask, nil)
  end)

  it("a partner that vanishes mid-exchange", function()
    local sim, c = world(ANA, BOR)
    give(c[BOR], pays(ZH, 1, 60)); give(c[BOR], { pay(YA, 1) }) -- Яна's entry comes last, and Вера lacks it
    local mark = #sim.sent
    hello(sim, BOR)
    local first
    for _ = 1, 30 do
      sim:run(1)
      first = whispers(sim, BOR, "LEV", mark)[1]
      if first then break end
    end
    ok(first, "a first batch")
    sim:offline(BOR)
    local v = sim:add(VERA)
    give(v, pays(ZH, 1, 60))
    hello(sim, VERA)
    sim:run(29 - (sim.clock - first.at)); ok(c[ANA].ledgerSync.ask and c[ANA].ledgerSync.ask.peer == BOR, "open")
    sim:run(1); ok(not (c[ANA].ledgerSync.ask and c[ANA].ledgerSync.ask.peer == BOR), "given up 30 s after that batch")
    eq(c[ANA].ledger:seen(ZH), 6) -- what arrived is kept
    sim:run(40)
    eq(#whispers(sim, ANA, "LVC", mark, VERA), 1); eq(c[ANA].ledger:seen(ZH), 60)
    -- Борис back: not asked again before 300 s from the first ask.
    sim:online(BOR)
    local asked = whispers(sim, ANA, "LVC", mark, BOR)[1].at
    hello(sim, BOR)
    sim:run(asked + C.LEDGER_PEER_GAP - 1 - sim.clock)
    eq(#whispers(sim, ANA, "LVC", mark, BOR), 1)
    hello(sim, BOR)
    sim:run(30)
    eq(#whispers(sim, ANA, "LVC", mark, BOR), 2); eq(holds(c[ANA], YA .. ":1"), 1)
  end)

  it("equal digests: no whisper at all", function()
    local sim, c = world(ANA, BOR)
    give(c[ANA], pays(ZH, 1, 5)); give(c[BOR], pays(ZH, 1, 5))
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(300)
    eq(sim:count(function(s) return s.channel == "WHISPER" and s.at > sim.sent[mark].at end), 0)
  end)

  it("the jitter is re-checked", function()
    local sim, c = world(ANA, BOR)
    give(c[BOR], { pay(ZH, 1) })
    local mark = #sim.sent
    hello(sim, BOR) -- Ана sees the difference
    sim:run(2)
    give(c[ANA], { pay(ZH, 1) })
    hello(sim, BOR) -- before the jitter fires: his digest is hers now
    sim:run(40)
    eq(#whispers(sim, ANA, "LVC", mark), 0)
  end)

  it("the jitter is derived, not drawn", function()
    local sim, c = world(ANA, BOR)
    sim.nextRandom = { 7, 7, 7 }
    give(c[BOR], { pay(ZH, 1) })
    local mark = #sim.sent
    hello(sim, BOR)
    local seen = sim.clock
    local ld = c[ANA].presence.peers[BOR].ld
    eq(ld, c[BOR].ledger:digest())
    sim:run(40)
    local lvc = whispers(sim, ANA, "LVC", mark)
    eq(#lvc, 1); eq(lvc[1].at - seen, jitter(ANA, BOR, ld))
    ok(lvc[1].at - seen >= C.LEDGER_JITTER_MIN and lvc[1].at - seen <= C.LEDGER_JITTER_MAX, "in range")
    eq(sim.nextRandom, { 7, 7, 7 })
  end)

  it("a sync message from a peer that is not listed in presence is ignored", function()
    local sim, c = world(ANA, BOR)
    local who = "Чужд Човек"
    local mark = #sim.sent
    c[ANA]:receive("WHISPER", who, { v = 1, t = "LVC", a = {} })
    c[ANA]:receive("WHISPER", who, { v = 1, t = "LEV", ev = { pay(who, 1) } })
    c[ANA]:receive("WHISPER", who, { v = 1, t = "LID", au = who, l = {} })
    sim:run(5)
    eq(c[ANA].ledger:seen(who), 0); eq(c[ANA].ledgerSync:busy(), false)
    eq(sim:count(function(s) return s.channel == "WHISPER" and s.at > sim.sent[mark].at end), 0)
  end)
end)

describe("ledger sync: the budget (packed with the real wire)", function()
  local A25, B25 = named(25), named(25)
  -- A D entry between the two 25-byte names, numbered n (a different game each).
  local function debt(n)
    return { i = Ledger.id(A25, 1000 + n), k = "D", at = EPOCH0 + 37 * n, gid = A25 .. "#" .. EPOCH0 .. "/" .. (100 + 7 * n),
      g = "deathroll", f = A25, t = B25, c = 99999990000, why = "lost" }
  end
  -- A five-seat R of `author`, numbered n, with names of `len` bytes (49: 2 x 12 Cyrillic letters).
  local function result(author, n, len)
    local names = {}
    for j = 1, 5 do names[j] = named(len) end
    return { i = Ledger.id(author, n), k = "R", at = EPOCH0 + n, gid = author .. "#" .. EPOCH0 .. "/" .. n, g = "deathroll",
      n = names, w = { 1 }, l = { 2, 3, 4, 5 }, sk = 99999990000 }
  end

  it("a batch, a vector and HI", function()
    local six = {}
    for n = 1, 6 do six[n] = Ledger.wire(debt(n)); ok(Ledger.valid(six[n]), "a valid D") end
    local lev = packed({ v = 1, t = "LEV", ev = six, f = true })
    ok(lev <= 1140, "6 D: " .. lev)
    -- The sync sends those 6 in one batch; every batch is within 1 140 packed bytes, so one of
    -- five-seat R entries with 64-byte names holds fewer than 6 (six with 49-byte names pack to about 1 120:
    -- within 1 140, but above the cut, which keeps LedgerNet.SLACK in hand).
    local sim, c = world(ANA, BOR)
    give(c[BOR], six)
    for n = 1, 6 do give(c[BOR], { result(ZH, n, 49) }) end
    for n = 1, 12 do give(c[BOR], { result(YA, n, 64) }) end
    local mark = #sim.sent
    hello(sim, BOR)
    sim:run(60)
    local batches, ds, cut = whispers(sim, BOR, "LEV", mark, ANA), 0, 0
    eq(entries(batches), 24)
    for _, b in ipairs(batches) do
      local size, kinds = packed(b.msg), {}
      for _, e in ipairs(b.msg.ev) do kinds[Ledger.author(e.i) == YA and "R64" or e.k] = true end
      ok(size <= 1140, "batch: " .. size)
      if kinds.D and #b.msg.ev == 6 then ds = ds + 1 end
      if kinds.R64 and not kinds.R and not kinds.D then cut = cut + 1; ok(#b.msg.ev < 6, "R batch of " .. #b.msg.ev) end
    end
    eq(ds, 1); ok(cut >= 2, "R batches cut by bytes: " .. cut)

    -- My live LEVs of R entries stay within 760 packed bytes each.
    mark = #sim.sent
    for n = 1, 4 do c[ANA].ledgerNet:make("R", { gid = ANA .. "#" .. EPOCH0 .. "/" .. n, g = "deathroll",
      n = { named(64), named(64), named(64), named(64), named(64) }, w = { 1 }, l = { 2, 3, 4, 5 } }) end
    sim:run(15)
    local live, sent = 0, 0
    for j, s in ipairs(sim.sent) do
      if j > mark and s.from == ANA and s.channel == "GUILD" and s.msg.t == "LEV" then
        live, sent = live + 1, sent + #s.msg.ev; ok(packed(s.msg) <= 760, "live: " .. packed(s.msg))
      end
    end
    ok(live >= 2, "cut by bytes: " .. live); eq(sent, 4)
    -- A vector of 60 authors with 25-byte names is one page.
    local v = {}
    for _ = 1, 60 do v[named(25)] = { n = 1000 + rnd(4000), x = string.format("%06x", rnd(16777216)) } end
    local size = packed({ v = 1, t = "LVC", a = v })
    ok(size <= 1500, "LVC 60: " .. size)
    -- HI grows by at most 16 packed bytes.
    local hi = c[ANA].presence:hi(false)
    local with = packed(hi)
    hi.ld = nil
    ok(with - packed(hi) <= 16, "HI: " .. with .. " - " .. packed(hi))
  end)

  it("a vector that does not fit 1 500 bytes goes in pages inside the one exchange", function()
    local sim, c = world(ANA, BOR)
    local authors = {}
    for k = 1, 100 do
      local name = named(64)
      authors[k] = name
      give(c[ANA], { { i = Ledger.id(name, 1), k = "P", at = EPOCH0, f = ZH, c = 100 + k, how = "hand" } })
    end
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(300)
    local pages = whispers(sim, ANA, "LVC", mark, BOR)
    ok(#pages >= 2, "pages: " .. #pages)
    local count = 0
    for j, s in ipairs(pages) do
      ok(packed(s.msg) <= 1500, "page " .. j .. ": " .. packed(s.msg))
      eq(s.msg.m, j < #pages and true or nil)
      for _ in pairs(s.msg.a) do count = count + 1 end
    end
    eq(count, 100)
    ok(pages[#pages].at - pages[1].at < C.LEDGER_SYNC_TIMEOUT, "one exchange")
    eq(c[BOR].ledger:seen(authors[100]), 1); eq(c[ANA].ledger:digest(), c[BOR].ledger:digest())
  end)

  it("a vector of 60 authors with 25-byte names is one page", function()
    local sim, c = world(ANA, BOR)
    for k = 1, 60 do give(c[ANA], { { i = Ledger.id(named(25), 1), k = "P", at = EPOCH0, f = ZH, c = 100 + k, how = "hand" } }) end
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(40)
    local pages = whispers(sim, ANA, "LVC", mark, BOR)
    eq(#pages, 1); eq(pages[1].msg.m, nil)
    local count = 0
    for _ in pairs(pages[1].msg.a) do count = count + 1 end
    eq(count, 60); ok(packed(pages[1].msg) <= 1500, "LVC 60: " .. packed(pages[1].msg))
  end)

  it("the rate: 60 entries in 10 batches, two seconds apart", function()

    local sim, c = world(ANA, BOR, VERA)
    give(c[BOR], pays(ZH, 1, 60))
    local mark = #sim.sent
    hello(sim, BOR)
    sim:run(60)
    local lev = whispers(sim, BOR, "LEV", mark, ANA)
    eq(#lev, 10); eq(entries(lev), 60)
    for j = 2, 10 do eq(lev[j].at - lev[j - 1].at, 2) end
  end)

  it("the rate at a live table of the sender: six seconds apart", function()
    local sim, c = world(ANA, BOR, VERA)
    local tid = c[BOR]:openTable{ game = "ttt", access = "guild", turn = 45 }
    sim:run(2)
    c[VERA]:sit(tid, 2); sim:run(2)
    eq(c[BOR].session.status, "live"); eq(c[BOR].session.mySeat, 1)
    give(c[BOR], pays(ELENA, 1, 30))
    local mark = #sim.sent
    hello(sim, BOR)
    sim:run(40)
    local lev = whispers(sim, BOR, "LEV", mark, ANA)
    ok(#lev >= 4, "batches: " .. #lev)
    for j = 2, 4 do eq(lev[j].at - lev[j - 1].at, 6) end
  end)

  it("a batch goes out only after the previous one reported done", function()
    local sim, c = world(ANA, BOR)
    give(c[BOR], pays(ZH, 1, 30))
    local env, held = c[BOR].env, {}
    local send = env.send
    env.send = function(channel, target, msg, done)
      if msg.t == "LEV" and channel == "WHISPER" then return send(channel, target, msg, function() held[#held + 1] = done end) end
      return send(channel, target, msg, done)
    end
    local mark = #sim.sent
    hello(sim, BOR)
    sim:run(25)
    eq(#whispers(sim, BOR, "LEV", mark), 1)
    sim:run(20) -- still nothing: the callback is held (Ана gives up 30 s after the batch)
    eq(#whispers(sim, BOR, "LEV", mark), 1)
    env.send = send
    held[1]()
    sim:run(0)
    ok(#whispers(sim, BOR, "LEV", mark) >= 2, "the next one after done")
  end)

  it("the GUILD parts: my live LEVs and sync HI stay within 10 parts in any 10 s", function()
    local sim, c = world(ANA, BOR)
    give(c[BOR], pays(ZH, 1, 6))
    local mark = #sim.sent
    hello(sim, BOR)
    for _ = 1, 30 do
      sim:run(1)
      if #whispers(sim, BOR, "LEV", mark) > 0 then break end
    end
    for n = 1, 24 do c[ANA].ledgerNet:make("R", { gid = ANA .. "#" .. EPOCH0 .. "/" .. n, g = "deathroll",
      n = { named(25), named(25), named(25), named(25), named(25) }, w = { 1 }, l = { 2, 3, 4, 5 } }) end
    sim:run(90)
    local parts, shipped, his = {}, 0, 0
    for j, s in ipairs(sim.sent) do
      if j > mark and s.from == ANA and s.channel == "GUILD" and (s.msg.t == "LEV" or s.msg.t == "HI") then
        parts[#parts + 1] = { at = s.at, n = math.ceil(packed(s.msg) / 255) }
        if s.msg.t == "LEV" then shipped = shipped + #s.msg.ev else his = his + 1 end
      end
    end
    eq(shipped, 24); eq(his, 1)
    local total = 0
    for _, p in ipairs(parts) do total = total + p.n end
    ok(total > 10, "the budget is binding: " .. total)
    for _, p in ipairs(parts) do
      local inside = 0
      for _, q in ipairs(parts) do if q.at >= p.at and q.at < p.at + 10 then inside = inside + q.n end end
      ok(inside <= 10, "parts in 10 s from " .. p.at .. ": " .. inside)
    end
  end)

  it("after an exchange that changed my digest I send one GUILD HI, and not a second within 30 s", function()
    local sim, c = world(ANA, BOR)
    give(c[BOR], { pay(ZH, 1) })
    local mark = #sim.sent
    hello(sim, BOR)
    while sim:count(function(s) return s.from == ANA and s.msg.t == "HI" and s.at > sim.sent[mark].at end) == 0 do sim:run(1) end
    -- Right after: Борис leaves, Вера comes with another entry; Ана's exchange with her ends within 30 s.
    sim:offline(BOR)
    local v = sim:add(VERA)
    give(v, { pay(ZH, 2) })
    hello(sim, VERA)
    sim:run(60) -- before the heartbeat

    local his = {}
    for j, s in ipairs(sim.sent) do
      if j > mark and s.from == ANA and s.channel == "GUILD" and s.msg.t == "HI" then his[#his + 1] = s end
    end
    eq(#his, 2); ok(his[2].at - his[1].at >= C.LEDGER_HI_GAP, "30 s apart: " .. (his[2].at - his[1].at))
    eq(his[2].msg.ld, c[ANA].ledger:digest())
    eq(c[ANA].ledger:digest(), v.ledger:digest())
  end)

  it("an exchange's end closes the adoption window of a new store", function()
    local sim, c = world(BOR)
    give(c[BOR], pays(ZH, 1, 30))
    local start
 = sim.clock
    local a = sim:add(ANA)
    eq(a.ledgerNet:adopting(), true)
    while not a.ledgerSync:busy() and sim.clock < start + 25 do sim:run(1) end
    ok(a.ledgerSync:busy(), "an exchange")
    while a.ledgerSync:busy() do sim:run(1) end
    ok(sim.clock < start + C.LEDGER_ADOPT_WAIT, "before the window would end by itself")
    eq(a.ledgerNet:adopting(), false)
  end)
end)

ns.LedgerNet.size = stand
