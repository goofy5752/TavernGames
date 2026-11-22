Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, Ledger, View, U = ns.Const, ns.Ledger, ns.LedgerView, ns.Util

-- The real wire, as wow/Adapter.lua installs it (restored at the end of this file).
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
local stand = ns.LedgerNet.size
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end

local A, B, P = "Иван Петров", "Мария Стоянова", "Петър Колев"
local NOW = 1700000000
local GID = "Иван Петров#5/41"

-- The STAND record of Мария's seat at a Холдем table of Иван.
local S = { i = "Иван Петров:7", k = "S", at = 100, gid = GID, g = "holdem", f = B,
  c = 80000, sk = 2000, n = { A, B, false, false, false, false }, w = { 1 }, l = {}, why = "left" }

-- A wire entry of `kind` numbered n by `author`, made at NOW.
local function entry(kind, author, n, fields)
  local e = U.copy(fields)
  e.k, e.i, e.at = kind, Ledger.id(author, n), NOW
  return e
end
local function debt(author, n, c, why)
  return entry("D", author, n, { gid = GID, g = "holdem", f = B, t = A, c = c, why = why })
end
local function L() return Ledger.new({}, "Свидетел Тихов", function() return NOW end) end

-- Runs fn with Const[key] = value, then restores it.
local function patched(key, value, fn)
  local old = C[key]
  C[key] = value
  local s, err = pcall(fn)
  C[key] = old
  if not s then error(err, 0) end
end

describe("ledger: the STAND record and the cash debt", function()
  it("an S is a valid entry; its hash is stable", function()
    eq(Ledger.valid(S, 200), true)
    eq(#Ledger.hash(S), 16); eq(Ledger.hash(S), Ledger.hash(U.copy(S)))
  end)
  it("an S needs f, c, sk, n, w, l; its why is one of three", function()
    for _, f in ipairs({ "gid", "g", "f", "c", "sk", "n", "w", "l" }) do
      local e = U.copy(S); e[f] = nil
      eq({ Ledger.valid(e, 200) }, { nil, "shape" }, f)
    end
    local e = U.copy(S); e.why = "lost"; eq({ Ledger.valid(e, 200) }, { nil, "shape" })
    for _, why in ipairs({ "left", "offline", "close" }) do e.why = why; eq(Ledger.valid(e, 200), true, why) end
    e.why = nil; eq(Ledger.valid(e, 200), true)
    e.c = 0; eq({ Ledger.valid(e, 200) }, { nil, "amount" })
  end)
  it("a D may say cash; the hash of every older entry is what it was", function()
    local d = { i = "Мария Стоянова:3", k = "D", at = 100, gid = GID, g = "holdem", f = B, t = A, c = 12300, why = "cash" }
    eq(Ledger.valid(d, 200), true)
    d.why = "lost" -- the field order is untouched: 17 fields, the last eight empty
    eq(Ledger.canon(d), "Мария Стоянова:3|D|100|Иван Петров#5/41|holdem|Мария Стоянова|Иван Петров|12300|lost||||||||")
  end)

  it("S entries count against the author cap with R", function()
    patched("LEDGER_AUTHOR_MAX", 3, function()
      local l = L()
      eq(l:add(entry("R", A, 1, { gid = "t/1", g = "ttt", n = { A, B }, w = { 1 }, l = { 2 } }), A), "new")
      eq(l:add(entry("R", A, 2, { gid = "t/2", g = "ttt", n = { A, B }, w = { 1 }, l = { 2 } }), A), "new")
      local s = U.copy(S); s.i, s.at = Ledger.id(A, 3), NOW
      eq(l:add(s, A), "new")
      s = U.copy(S); s.i, s.at, s.gid = Ledger.id(A, 4), NOW, "Иван Петров#5/42"
      eq({ l:add(s, A) }, { nil, "full" })
      eq(l:add(entry("D", A, 5, { gid = GID, g = "holdem", f = B, t = A, c = 100, why = "lost" }), A), "new")
    end)
  end)

  it("the debtor's own D with why cash confirms the creditor's claim", function()
    local l = L()
    eq(l:add(debt(A, 1, 12300, "lost"), A), "new")
    eq(l:add(debt(B, 1, 12300, "cash"), B), "new")
    local v = View.of(l)
    eq(#v.debts, 1); eq(v.debts[1].status, "confirmed"); eq(v.debts[1].c, 12300); eq(v.debts[1].clash, false)
    eq(View.net(v, B, A), 12300)

    l = L()
    eq(l:add(debt(A, 1, 12300, "lost"), A), "new")
    eq(l:add(debt(B, 1, 12000, "cash"), B), "new")
    v = View.of(l)
    eq(v.debts[1].status, "confirmed"); eq(v.debts[1].c, 12000); eq(v.debts[1].clash, true)
  end)

  it("a client of the F2 version keeps a cash debt pending", function()
    local sim = Sim.new()
    local a, b, p = sim:add(A), sim:add(B), sim:add(P)
    sim:run(1)
    sim:settle()
    -- П's client refuses an S and a D that says cash, as the F2 version's Ledger.valid does.
    local take = p.ledgerNet.take
    p.ledgerNet.take = function(self, e, from, live)
      if type(e) == "table" and (e.k == "S" or (e.k == "D" and e.why == "cash")) then
        local author, n = Ledger.author(e.i)
        if author then return self:refuse(e, author, n) end
      end
      return take(self, e, from, live)
    end
    local gid = A .. "#" .. NOW .. "/41"
    local claim = a.ledgerNet:make("D", { gid = gid, g = "holdem", f = B, t = A, c = 12300, why = "lost" })
    local own = b.ledgerNet:make("D", { gid = gid, g = "holdem", f = B, t = A, c = 12300, why = "cash" })
    local st = a.ledgerNet:make("S", { gid = gid, g = "holdem", f = B, c = 80000, sk = 2000,
      n = { A, B, false, false, false, false }, w = { 1 }, l = {}, why = "left" })
    ok(claim and own and st, "all three made")
    sim:run(C.LEDGER_COALESCE + 5)
    -- Everyone else confirms; П holds the claim only, pending, in no balance.
    for _, c in ipairs({ a, b }) do
      eq(Play.debt(c, gid, B, A).status, "confirmed", c.env.me)
      ok(c.ledger:get(st.i), c.env.me)
    end
    local d = Play.debt(p, gid, B, A)
    ok(d, "П holds the claim"); eq(d.status, "pending")
    ok(p.ledger:get(claim.i)); eq((p.ledger:get(own.i)), nil); eq((p.ledger:get(st.i)), nil)
    eq(View.net(View.of(p.ledger), B, A), 0)
    eq(p.ledger:refused(B, select(2, Ledger.author(own.i)), Ledger.hash(own)), true)
    eq(p.ledger:refused(A, select(2, Ledger.author(st.i)), Ledger.hash(st)), true)
  end)

  it("a six-seat S with six 12-letter Cyrillic names is valid and fits one live LEV (H17)", function()
    local names = { "Александрина", "Константинов", "Светлозарова", "Добромирчева", "Христофорова", "Владиславова" }
    for _, name in ipairs(names) do eq(#name, 24, name) end
    local host = names[1]
    local sim = Sim.new()
    local clients = {}
    for _, name in ipairs(names) do clients[name] = sim:add(name) end
    sim:run(1)
    sim:settle()
    local fields = { gid = host .. "#" .. NOW .. "/123", g = "holdem", f = names[2], c = 2000000, sk = 20000,
      n = U.copy(names), w = { 3, 4 }, l = { 1, 5, 6 }, why = "offline" }
    local mark = #sim.sent
    local e = clients[host].ledgerNet:make("S", fields)
    ok(e, "made")
    eq(Ledger.valid(Ledger.wire(e), NOW + 10), true)
    local size = #Ledger.canon(e)
    ok(size < 600, "canon " .. size)
    sim:run(C.LEDGER_COALESCE + 1)
    local levs = {}
    for j, s in ipairs(sim.sent) do
      if j > mark and s.from == host and s.channel == "GUILD" and s.msg.t == "LEV" then levs[#levs + 1] = s.msg end
    end
    eq(#levs, 1); eq(#levs[1].ev, 1); eq(levs[1].ev[1], Ledger.wire(e))
    local packed = #wire:pack(levs[1])
    ok(packed <= 760 - ns.LedgerNet.SLACK, "packed " .. packed)
    for _, name in ipairs(names) do ok(clients[name].ledger:get(e.i), name) end

    -- Names of 64 bytes each make the S too long: refused "size" (a residual: an S is never money).
    local long = {}
    for j = 1, 6 do long[j] = string.rep("Я", 31) .. string.char(0xD0, 0x90 + j) end
    for _, name in ipairs(long) do eq(#name, 64) end
    local big = { i = long[1] .. ":1", k = "S", at = NOW, gid = long[1] .. "#" .. NOW .. "/123", g = "holdem", f = long[2],
      c = 2000000, sk = 20000, n = long, w = { 3, 4 }, l = { 1, 5, 6 }, why = "offline" }
    ok(#Ledger.canon(big) > 600, "canon " .. #Ledger.canon(big))
    eq({ Ledger.valid(big, NOW) }, { nil, "size" })
  end)
end)

ns.LedgerNet.size = stand
