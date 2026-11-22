Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local ns = Sim.ns
local Ledger, C, U = ns.Ledger, ns.Const, ns.Util

-- The sync fixes of the stage F1 final review (I3, I4, I5), with the real wire as
-- wow/Adapter.lua installs it (restored at the end of this file).
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
local stand = ns.LedgerNet.size
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end

-- "Ана" < "Борис" < "Вера" by bytes; Жана is an author who is never online.
local ANA, BOR, VERA, ZH = "Ана Иванова", "Борис Петров", "Вера Колева", "Жана Стоева"
local EPOCH0 = 1700000000

-- The names online, in the guild, past their login queues.
local function world(...)
  local sim, c = Sim.new(), {}
  for _, name in ipairs({ ... }) do c[name] = sim:add(name) end
  sim:run(1)
  sim:settle()
  return sim, c
end

-- A P entry of `author` numbered n.
local function pay(author, n, c, f)
  return { i = Ledger.id(author, n), k = "P", at = EPOCH0 + n % 1000, f = f or (author == ZH and ANA or ZH), c = c or 100 + n, how = "hand" }
end
-- Puts entries into a client's store as if relayed by somebody who is not online.
local function give(client, list)
  for _, e in ipairs(list) do client.ledger:add(e, "Някой") end
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
-- The whispered sync messages of type t after sim.sent[mark] (from `from`, when given).
local function whispers(sim, t, mark, from)
  local out = {}
  for j, s in ipairs(sim.sent) do
    if j > (mark or 0) and s.channel == "WHISPER" and s.msg.t == t and (not from or s.from == from) then out[#out + 1] = s end
  end
  return out
end
local function entries(list) local n = 0; for _, s in ipairs(list) do n = n + #s.msg.ev end; return n end
-- Every call of L:work is recorded: {n, items hashed}.
local function watch(L)
  local calls, work = {}, L.work
  L.work = function(self, n)
    local before = self.hashed or 0
    local done = work(self, n)
    calls[#calls + 1] = { n = n, items = (self.hashed or 0) - before }
    return done
  end
  return calls
end
-- No call hashed more than a frame's share, and none was unbounded.
local function sliced(calls, what)
  for _, call in ipairs(calls) do
    ok(call.n ~= nil and call.n <= C.LEDGER_HASH_ITEMS, what .. ": an unbounded hash")
    ok(call.items <= C.LEDGER_HASH_ITEMS, what .. ": " .. call.items .. " items in one frame")
  end
end

describe("ledger final review: the x hash is sliced across frames (I3)", function()
  it("a 5000-body author is hashed LEDGER_HASH_ITEMS a frame; the HI and the vector wait for it", function()
    ok(C.LEDGER_HASH_ITEMS <= 500, "a frame's share")
    local sim, c = world(ANA, BOR)
    local a, b = c[ANA], c[BOR]
    local calls = watch(a.ledger)
    give(a, pays(ZH, 1, 5000))
    ok(a.ledger:hashing(), "stale")
    local mark = #sim.sent
    a.presence:sendGuildHi(false) -- my digest is not ready: the HI waits
    eq(#sim.sent, mark)
    sim:run(0)
    eq(a.ledger:hashing(), false)
    eq(#a.ledger:above(ZH, 0), 5000)
    ok(#calls >= math.ceil(5000 / C.LEDGER_HASH_ITEMS), "split: " .. #calls); sliced(calls, "Ана")
    local items = {}
    for j, body in ipairs(a.ledger:above(ZH, 0)) do items[j] = body.i .. ":" .. body.h end
    table.sort(items, U.byteLess)
    eq(a.ledger:vector()[ZH].x, ns.Sha256.hex(table.concat(items, ",")):sub(1, 12)) -- equals the unsliced hash
    local his = {}
    for j, s in ipairs(sim.sent) do if j > mark and s.from == ANA and s.msg.t == "HI" then his[#his + 1] = s.msg end end
    eq(#his, 1); eq(his[1].ld, a.ledger:digest())

    -- A login: the whole ledger is stale; the first HI goes only once the digest is ready.
    a:stop(); a = sim:relog(ANA)
    calls = watch(a.ledger)
    mark = #sim.sent
    ok(a.ledger:hashing(), "a load hashes nothing")
    eq(#sim.sent, mark)
    sim:run(0)
    his = {}
    for j, s in ipairs(sim.sent) do if j > mark and s.from == ANA and s.msg.t == "HI" and s.channel == "GUILD" then his[#his + 1] = s.msg end end
    eq(#his, 1); eq(his[1].re, true); eq(#his[1].ld, 8); eq(his[1].ld, a.ledger:digest())
    ok(#calls >= math.ceil(5000 / C.LEDGER_HASH_ITEMS), "split at login: " .. #calls); sliced(calls, "Ана at login")

    -- The exchange with Борис: every take makes Жана's x stale on his side; nobody hashes it whole in one frame.
    local bcalls = watch(b.ledger)
    sim:settle()
    sim:run(120)
    ok(entries(whispers(sim, "LEV", mark, ANA)) >= C.LEDGER_EXCHANGE_MAX, "an exchange ran")
    ok(#whispers(sim, "LVC", mark) >= 1, "a vector went, after the hash")
    sliced(calls, "Ана in the exchange"); sliced(bcalls, "Борис in the exchange")
    ok(#bcalls > 0, "Борис hashed in slices")
  end)
end)

describe("ledger final review: an entry one side refuses (I4)", function()
  -- Ана holds 40 entries of Вера; number 3 names Жана, whom Борис's guild roster does not list.
  local function disagreeing()
    local sim, c = world(ANA, BOR)
    local members = { [ANA] = true, [BOR] = true, [VERA] = true }
    sim.envs[BOR].member = function(name) return members[name] == true end
    for n = 1, 40 do give(c[ANA], { pay(VERA, n, nil, n == 3 and ZH or ANA) }) end
    return sim, c[ANA], c[BOR], members
  end
  -- One round: both say HI, then a peer gap passes -> the whispered LEV entries, LVC pages and LID pages of it.
  local function round(sim)
    local mark = #sim.sent
    hello(sim, ANA, BOR)
    sim:run(C.LEDGER_PEER_GAP + 30)
    return entries(whispers(sim, "LEV", mark)), #whispers(sim, "LVC", mark), #whispers(sim, "LID", mark)
  end

  it("two clients that disagree on one entry reach a steady state: the tail is sent once, then nothing", function()
    local sim, a, b = disagreeing()
    local sent = round(sim)
    eq(sent, 40) -- the whole of Вера, once
    eq(b.ledger:get(VERA .. ":3"), nil); eq(#b.ledger:above(VERA, 0), 39)
    eq(b.ledger:refused(VERA, 3, a.ledger:get(VERA .. ":3").h), true)
    -- Борис counts the refused entry as held: the same cell, the same digest, nothing to ask for.
    eq(b.ledger:vector()[VERA], a.ledger:vector()[VERA]); eq(b.ledger:vector()[VERA].n, 40)
    eq(b.ledger:digest(), a.ledger:digest())
    for _ = 1, 4 do eq({ round(sim) }, { 0, 0, 0 }) end
    -- It is no entry of his: not in his view, not in his list of bodies.
    eq(#ns.LedgerView.of(b.ledger).rows, 0); eq(b.ledger:list(VERA)[3], "4." .. b.ledger:get(VERA .. ":4").h)
    -- Remembered across a relog (saved with the store).
    b:stop(); b = sim:relog(BOR); sim.envs[BOR].member = function(name) return name ~= ZH end
    sim:run(1); sim:settle()
    eq(b.ledger:digest(), a.ledger:digest())
    eq({ round(sim) }, { 0, 0, 0 })
  end)

  it("a refusal is forgotten after 24 h: the entry is offered once more, and taken once it is acceptable", function()
    local sim, a, b, members = disagreeing()
    round(sim)
    local h = a.ledger:get(VERA .. ":3").h
    local rf = sim.envs[BOR].db.ledger["МЕХАНАТА"].rf
    local till = rf[VERA]["3." .. h]
    ok(till > EPOCH0 + sim.clock and till <= EPOCH0 + sim.clock + C.LEDGER_REFUSED_TTL, "saved with its expiry")
    eq(C.LEDGER_REFUSED_TTL, 86400)
    -- As if 24 h had passed (the expiry moved back instead of the clock forward).
    rf[VERA]["3." .. h] = EPOCH0 + sim.clock
    eq(b.ledger:refused(VERA, 3, h), false)
    b.ledger:forget(); sim:run(0)
    eq(rf[VERA], nil); eq(b.ledger:vector()[VERA].n, 2)
    ok(b.ledger:digest() ~= a.ledger:digest(), "a difference again")
    eq(round(sim), 38) -- offered once more: the tail above 2; still no member: refused again
    eq(b.ledger:refused(VERA, 3, h), true)
    eq(b.ledger:digest(), a.ledger:digest()); eq({ round(sim) }, { 0, 0, 0 })
    -- The hourly sweep forgets it by itself; Жана has joined the guild by then: taken.
    rf = sim.envs[BOR].db.ledger["МЕХАНАТА"].rf
    rf[VERA]["3." .. h] = EPOCH0 + sim.clock + 10
    members[ZH] = true
    local mark = #sim.sent
    sim:run(3600 + C.HI_HEARTBEAT + C.LEDGER_JITTER_MAX + 60)
    eq(entries(whispers(sim, "LEV", mark)), 38)
    ok(b.ledger:get(VERA .. ":3"), "taken"); eq(b.ledger:refused(VERA, 3, h), false); eq(rf[VERA], nil)
    eq(b.ledger:digest(), a.ledger:digest()); eq({ round(sim) }, { 0, 0, 0 })
  end)

  it("an entry my version cannot hash as its holder does: the pair settles on vectors only, no resend loop", function()
    local sim, c = world(ANA, BOR)
    local a, b = c[ANA], c[BOR]
    for n = 1, 40 do give(a, { pay(VERA, n) }) end
    -- As if number 3 were of a kind a later version writes: Борис cannot take it, nor name it as Ана does.
    sim.bus.filter = function(from, to, _, msg)
      if from == ANA and to == BOR and msg.t == "LEV" then
        for _, e in ipairs(msg.ev) do if e.i == VERA .. ":3" then e.k, e.zz = "S", 1 end end
      end
      return { msg }
    end
    eq(round(sim), 40)
    eq(b.ledger:get(VERA .. ":3"), nil)
    ok(b.ledger:digest() ~= a.ledger:digest(), "they cannot agree")
    for _ = 1, 2 do -- offered twice more (the first time may have been lost on its way), by lists, not by the tail
      local e2, _, lid2 = round(sim)
      ok(e2 <= 1, "at most the one entry again: " .. e2); ok(lid2 <= 4, "one list round: " .. lid2)
    end
    for _ = 1, 4 do
      local e, lvc, lid = round(sim)
      eq({ e, lid }, { 0, 0 }); ok(lvc <= 2, "the two vectors at most: " .. lvc)
    end
    -- Something new of Вера still flows.
    give(a, { pay(VERA, 41) })
    sim:run(0)
    local e = round(sim)
    ok(e >= 1 and e <= 2, "the new entry: " .. e); ok(b.ledger:get(VERA .. ":41"), "taken")
  end)

  it("the refused set is bounded per author; past it nothing more is remembered", function()
    local sim, c = world(ANA, BOR)
    local b = c[BOR]
    local members = { [ANA] = true, [BOR] = true, [VERA] = true }
    sim.envs[BOR].member = function(name) return members[name] == true end
    for n = 1, C.LEDGER_REFUSED_MAX + 5 do
      eq(b.ledgerNet:take(pay(VERA, n, nil, ZH), VERA, true), nil)
    end
    local n = 0
    for _ in pairs(sim.envs[BOR].db.ledger["МЕХАНАТА"].rf[VERA]) do n = n + 1 end
    eq(n, C.LEDGER_REFUSED_MAX)
    eq(b.ledger:refused(VERA, 1, Ledger.hash(pay(VERA, 1, nil, ZH))), true)
    eq(b.ledger:refused(VERA, C.LEDGER_REFUSED_MAX + 1, Ledger.hash(pay(VERA, C.LEDGER_REFUSED_MAX + 1, nil, ZH))), false)
    -- Offered again once it is acceptable, a refused entry is taken and forgotten as refused.
    members[ZH] = true
    eq(b.ledgerNet:take(pay(VERA, 1, nil, ZH), VERA, true), "new")
    eq(b.ledger:refused(VERA, 1, Ledger.hash(pay(VERA, 1, nil, ZH))), false)
    eq(b.ledgerNet:take(pay(VERA, C.LEDGER_REFUSED_MAX + 1, nil, ZH), VERA, true), "new")
  end)
end)

ns.LedgerNet.size = stand
