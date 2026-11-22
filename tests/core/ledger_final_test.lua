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

ns.LedgerNet.size = stand
