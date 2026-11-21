local ns = Loader.ns()
local Ledger, U, C = ns.Ledger, ns.Util, ns.Const

local I, M, P = "Иван Петров", "Мария Колева", "Петър Иванов"
local NOW = 1700000000

local function L(me) return Ledger.new({}, me or "Иван Петров", function() return 1700000000 end) end
local D = { k = "D", gid = "Иван Петров#1700000000/12", g = "ttt", f = "Мария Колева", t = "Иван Петров", c = 50000, why = "lost" }

-- A wire entry of `kind` numbered `n` by `author`, made at NOW.
local function entry(kind, author, n, fields)
  local e = U.copy(fields)
  e.k, e.i, e.at = kind, Ledger.id(author, n), NOW
  return e
end

-- One correct entry of each kind.
local GOOD = {
  R = function() return entry("R", I, 1, { gid = I .. "#1700000000/12", g = "ttt", n = { I, M }, w = { 1 }, l = { 2 }, sk = 50000 }) end,
  D = function() return entry("D", I, 1, D) end,
  C = function() return entry("C", M, 2, { r = I .. ":1" }) end,
  N = function() return entry("N", M, 2, { r = I .. ":1", why = "forged" }) end,
  P = function() return entry("P", I, 3, { f = M, c = 50000, how = "trade" }) end,
  X = function() return entry("X", I, 4, { r = I .. ":1", h = "0123456789abcdef" }) end,
}

local function good(e) eq({ Ledger.valid(e, NOW) }, { true }) end
local function bad(e, reason) eq({ Ledger.valid(e, NOW) }, { nil, reason }) end
local function with(kind, field, value) local e = GOOD[kind](); e[field] = value; return e end

-- A claim of Мария (the debtor) against Иван under id "Мария Колева:1".
local function claim(c) return entry("D", M, 1, { gid = "Иван Петров#1700000000/12", g = "ttt", f = M, t = I, c = c, why = "lost" }) end
-- Мария's payment number n (she is the creditor of Иван).
local function paid(n, c) return entry("P", M, n, { f = I, c = c or 100 * n, how = "hand" }) end

-- Runs fn with Const[key] = value, then restores it.
local function patched(key, value, fn)
  local old = C[key]
  C[key] = value
  local s, err = pcall(fn)
  C[key] = old
  if not s then error(err, 0) end
end

describe("ledger entries", function()
  it("id and author split on the last colon", function()
    eq(Ledger.id("Иван Петров", 7), "Иван Петров:7")
    local a, n = Ledger.author("Иван Петров:7"); eq(a, "Иван Петров"); eq(n, 7)
    eq(Ledger.author("Иван"), nil); eq(Ledger.author("Иван:0"), nil); eq(Ledger.author("Иван:1.5"), nil); eq(Ledger.author(":3"), nil)
  end)
  it("canon is the fixed field order; hash is 16 hex and ignores local fields", function()
    local l = L(); local e = l:make("D", D)
    eq(Ledger.canon(e), "Иван Петров:1|D|1700000000|Иван Петров#1700000000/12|ttt|Мария Колева|Иван Петров|50000|lost|||||||")
    eq(#e.h, 16); ok(e.h:match("^[0-9a-f]+$"))
    local w = Ledger.wire(e); eq(w.h, nil); eq(Ledger.hash(w), e.h)
    w.c = 50100; ok(Ledger.hash(w) ~= e.h)
  end)
  it("make numbers my entries from 1 and saves the counter", function()
    local store = {}; local l = Ledger.new(store, "Иван Петров", function() return 5 end)
    eq(l:make("D", D).i, "Иван Петров:1"); eq(l:make("P", { f = "Мария Колева", c = 100, how = "hand" }).i, "Иван Петров:2")
    eq(store.me["Иван Петров"].seq, 2)
    eq(Ledger.new(store, "Иван Петров", function() return 6 end):make("P", { f = "Мария Колева", c = 100, how = "hand" }).i, "Иван Петров:3")
  end)
  it("an X keeps the denied hash as its field h on the wire and in canon", function()
    local l = L(); local e = l:make("X", { r = I .. ":1", h = "0123456789abcdef" })
    eq(e.rh, "0123456789abcdef"); ok(e.h ~= "0123456789abcdef")
    eq(Ledger.canon(e), "Иван Петров:1|X|1700000000|||||||Иван Петров:1|0123456789abcdef|||||")
    local w = Ledger.wire(e); eq(w.h, "0123456789abcdef"); eq(w.rh, nil); eq(Ledger.hash(w), e.h)
  end)
  it("a list joins by commas and false is a dash", function()
    local e = entry("R", I, 1, { gid = "t/1", g = "deathroll", n = { I, false, M }, w = { 1 }, l = { 3 } })
    eq(Ledger.canon(e), "Иван Петров:1|R|1700000000|t/1|deathroll|||||||||Иван Петров,-,Мария Колева|1|3")
  end)
end)

describe("ledger valid", function()
  it("a correct R, D, C, N, P, X", function()
    for _, k in ipairs({ "R", "D", "C", "N", "P", "X" }) do good(GOOD[k]()) end
  end)
  it("not a table; i missing; k = Z", function()
    bad("D", "shape"); bad(with("D", "i", nil), "id"); bad(with("D", "k", "Z"), "kind")
  end)
  it("D with a bad amount; P with c = 0 or 1.5", function()
    bad(with("D", "c", 150), "amount"); bad(with("D", "c", 0), "amount"); bad(with("D", "c", "5"), "amount")
    bad(with("P", "c", 0), "amount"); bad(with("P", "c", 1.5), "amount")
  end)
  it("P with copper and with the gold cap", function()
    good(with("P", "c", 150)); good(with("P", "c", 99999999999))
  end)
  it("D with f == t; D authored by a third name; X naming another author", function()
    bad(with("D", "f", I), "right")
    local e = GOOD.D(); e.i = Ledger.id(P, 1); bad(e, "right")
    bad(with("X", "r", M .. ":1"), "right")
  end)
  it("D with f of 65 bytes; R with ten names", function()
    bad(with("D", "f", string.rep("Ж", 32) .. "a"), "name")
    local ten = {}
    for j = 1, 10 do ten[j] = "Играч" .. j end
    bad(with("R", "n", ten), "name")
  end)
  it("D with f of 49 bytes and of 64 bytes", function()
    local f49 = string.rep("Ж", 12) .. " " .. string.rep("Ш", 12)
    eq(#f49, 49); good(with("D", "f", f49)); good(with("D", "f", string.rep("Ж", 32)))
  end)
  it("at too far ahead; at not whole", function()
    bad(with("D", "at", NOW + 3601), "time"); bad(with("D", "at", 1.5), "time")
    good(with("D", "at", NOW + 3600))
  end)
  it("D with why = x; P with how = cod; N with why = because", function()
    bad(with("D", "why", "x"), "shape"); bad(with("P", "how", "cod"), "shape"); bad(with("N", "why", "because"), "shape")
  end)
  it("R with a gid of 600 bytes", function()
    bad(with("R", "gid", string.rep("x", 597) .. "/12"), "size")
  end)
  it("a five-seat staked Death Roll R with 24-letter Cyrillic names", function()
    local function name(a, b) return string.rep(a, 12) .. " " .. string.rep(b, 12) end
    local names = { name("А", "Б"), name("В", "Г"), name("Д", "Е"), name("Ж", "З"), name("И", "К") }
    local e = entry("R", names[1], 1, { gid = names[1] .. "#1700000000/12", g = "deathroll", n = names,
      w = { 1 }, l = { 2, 3, 4, 5 }, sk = 99999990000 })
    good(e)
    local size = #Ledger.canon(e)
    ok(size > 400 and size <= 600, "canonical bytes " .. size)
  end)
  it("C whose r is not an id", function()
    bad(with("C", "r", "Иван Петров"), "shape")
  end)
  it("P with f equal to its author", function()
    bad(with("P", "f", I), "right")
  end)
  it("a field of another kind or a separator inside a field", function()
    bad(with("C", "c", 100), "shape"); bad(with("D", "gid", "a|b/1"), "shape")
    bad(with("D", "f", "Мария,Колева"), "name"); bad(with("R", "w", { 1, "x" }), "shape")
  end)
end)

describe("ledger store", function()
  it("add: new, dup, twin, and no fifth", function()
    local l = L()
    local id = Ledger.id(M, 1)
    eq(l:add(claim(50000), P), "new"); eq(l:add(claim(50000), P), "dup")
    eq(l:add(claim(60000), P), "twin")
    local first, tw = l:get(id); eq(first.c, 50000); eq(#tw, 1); eq(tw[1].c, 60000)
    eq(l:add(claim(70000), P), "twin"); eq(l:add(claim(80000), P), "twin")
    local _, tw4 = l:get(id); eq(#tw4, 3)

    -- Five bodies of one id, by ascending h.
    local s = {}
    for j = 1, 5 do s[j] = claim(10000 * j) end
    table.sort(s, function(a, b) return U.byteLess(Ledger.hash(a), Ledger.hash(b)) end)
    local a, b = L(), L()
    for j = 1, 4 do eq(a:add(s[j], P), j == 1 and "new" or "twin") end
    eq({ a:add(s[5], P) }, { nil, "twins" })
    for _, j in ipairs({ 5, 2, 3, 4 }) do b:add(s[j], P) end
    eq(b:add(s[1], P), "twin")
    eq(b:has(id, Ledger.hash(s[5])), false)
    eq(a:list(M), b:list(M)); eq(#a:list(M), 4); eq(a:digest(), b:digest())

    -- A body its author denied goes first.
    local c = L()
    for j = 1, 4 do c:add(s[j], P) end
    eq(c:add(entry("X", M, 2, { r = id, h = Ledger.hash(s[1]) }), P), "new")
    eq(c:add(s[5], P), "twin")
    eq(c:has(id, Ledger.hash(s[1])), false); eq(c:has(id, Ledger.hash(s[5])), true)
  end)
  it("add marks direct and relayed", function()
    local l = L()
    local e, e2 = paid(1), paid(2)
    eq(l:add(e, M), "new"); local s = l:get(e.i); eq(s.dr, true); eq(s.rl, nil)
    eq(l:add(e2, P), "new"); local s2 = l:get(e2.i); eq(s2.rl, true); eq(s2.dr, nil)
    eq(l:add(e2, M), "dup"); eq(s2.dr, true); eq(s2.rl, nil)
    eq(l:add(e2, P), "dup"); eq(s2.dr, true); eq(s2.rl, nil)
    local mine = l:make("P", { f = M, c = 100, how = "hand" }); eq(mine.dr, nil); eq(mine.rl, nil)
  end)
  it("the author cap counts R only", function()
    patched("LEDGER_AUTHOR_MAX", 3, function()
      local l = L()
      for n = 1, 3 do eq(l:add(entry("R", M, n, { gid = "t/" .. n, g = "ttt", n = { M, I }, w = { 1 }, l = { 2 } }), M), "new") end
      eq({ l:add(entry("R", M, 4, { gid = "t/4", g = "ttt", n = { M, I }, w = { 1 }, l = { 2 } }), M) }, { nil, "full" })
      eq(l:add(entry("D", M, 5, { gid = "t/3", g = "ttt", f = M, t = I, c = 100, why = "lost" }), M), "new")
      eq(l:add(entry("C", M, 6, { r = I .. ":1" }), M), "new")
      eq(l:add(entry("N", M, 7, { r = I .. ":2", why = "no" }), M), "new")
      eq(l:add(paid(8), M), "new")
      eq(l:add(entry("X", M, 9, { r = M .. ":1", h = "0123456789abcdef" }), M), "new")
    end)
  end)
  it("x is incremental and bounded", function()
    local store, sum = { ev = { [M] = {} }, tw = {}, me = {}, x = {} }, 0
    for n = 1, 5000 do
      local h = string.format("%08x%08x", n * 7919, n)
      store.ev[M][n] = { i = Ledger.id(M, n), k = "R", at = NOW, gid = "t/" .. n, g = "ttt", n = { M, I }, w = { 1 }, l = { 2 }, h = h }
      sum = (sum + tonumber(h, 16)) % 4294967296
    end
    store.x[M] = sum
    local calls, hex = 0, ns.Sha256.hex
    ns.Sha256.hex = function(s) calls = calls + 1; return hex(s) end
    local s, err = pcall(function()
      local l = Ledger.new(store, I, function() return NOW end)
      eq(calls, 0, "a load hashes nothing")
      eq(l:add(paid(5001), M), "new"); eq(calls, 1, "one add hashes one body")
      eq(l:vector()[M].n, 5001)
      calls = 0
      local d = l:digest(); eq(l:digest(), d); eq(calls, 1, "the digest is cached")
    end)
    ns.Sha256.hex = hex
    if not s then error(err, 0) end
  end)
  it("my counter jumps above every id seen under my name", function()
    local l = L()
    local forged = entry("C", I, 9, { r = M .. ":1" })
    eq(l:add(forged, P), "new"); eq(l:seen(I), 9)
    local x = l:make("X", { r = forged.i, h = l:get(forged.i).h })
    eq(x.i, I .. ":10"); eq(l:denied(l:get(forged.i)), true)
    l:bump(20); eq(l:make("P", { f = M, c = 100, how = "hand" }).i, I .. ":21")
    eq(l:seen(M), 0)
  end)
  it("vector: contiguous n and a set digest", function()
    local a, b = L(), L()
    local xs = {}
    for _, n in ipairs({ 1, 2, 3, 5 }) do
      a:add(paid(n), M)
      local x = a:vector()[M].x
      ok(x:match("^%x%x%x%x%x%x$")); ok(not xs[x], "x changes with every add"); xs[x] = true
    end
    eq(a:vector()[M].n, 3)
    a:add(paid(4), M); eq(a:vector()[M].n, 5); ok(not xs[a:vector()[M].x])
    for _, n in ipairs({ 4, 5, 3, 1, 2 }) do b:add(paid(n), P) end
    eq(a:vector(), b:vector())
  end)
  it("digest: equal sets, equal digests; one more entry, another digest; an empty log has one", function()
    eq(L():digest(), ns.Sha256.hex(""):sub(1, 8)); eq(L():digest(), "e3b0c442")
    local a, b = L(), L()
    a:add(paid(1), M); a:add(GOOD.R(), I); a:add(claim(50000), P)
    b:add(claim(50000), M); b:add(paid(1), P); b:add(GOOD.R(), P)
    eq(a:digest(), b:digest()); eq(#a:digest(), 8)
    local before = a:digest()
    a:add(paid(2), M); ok(a:digest() ~= before)
    b:add(claim(60000), P); ok(b:digest() ~= before)
  end)
  it("above and list", function()
    local l = L()
    for _, n in ipairs({ 1, 2, 3, 5 }) do l:add(paid(n), M) end
    local function ids(list) local out = {} for j, e in ipairs(list) do out[j] = e.i end return out end
    eq(ids(l:above(M, 3)), { M .. ":5" })
    l:add(paid(4), M); l:add(paid(5, 7700), M)
    local up = l:above(M, 3)
    eq(ids(up), { M .. ":4", M .. ":5", M .. ":5" }); ok(U.byteLess(up[2].h, up[3].h), "a twin after its sibling")
    local list = l:list(M)
    eq(#list, 6)
    local first = l:get(M .. ":1"); eq(list[1], "1." .. first.h:sub(1, 6))
    for _, s in ipairs(list) do ok(s:match("^%d+%.%x%x%x%x%x%x$"), s) end
    eq(l:above(P, 0), {}); eq(l:list(P), {})
  end)
  it("each walks authors in byte order, then n, then h", function()
    local l = L()
    l:add(paid(2), M); l:add(paid(1), M); l:add(paid(1, 7700), M); l:add(GOOD.P(), I)
    local seen = {}
    l:each(function(e) seen[#seen + 1] = e end)
    eq(#seen, 4); eq(seen[1].i, I .. ":3"); eq(seen[2].i, M .. ":1"); eq(seen[3].i, M .. ":1"); eq(seen[4].i, M .. ":2")
    ok(U.byteLess(seen[2].h, seen[3].h))
  end)
  it("denied", function()
    local l = L()
    eq(l:add(claim(50000), M), "new"); eq(l:add(claim(60000), M), "twin")
    local e, tw = l:get(M .. ":1")
    l:add(entry("X", M, 2, { r = e.i, h = e.h }), M)
    eq(l:denied(e), true); eq(l:denied(tw[1]), false)
    eq({ l:add(entry("X", P, 1, { r = e.i, h = tw[1].h }), P) }, { nil, "right" })
  end)
  it("the store round-trips", function()
    local store = {}
    local l = Ledger.new(store, I, function() return NOW end)
    l:add(claim(50000), M); l:add(claim(60000), P); l:add(paid(3), M); l:make("P", { f = M, c = 100, how = "hand" })
    local copy = Ledger.new(U.copy(store), I, function() return NOW end)
    eq(copy:digest(), l:digest()); eq(copy:vector(), l:vector()); eq(copy:list(M), l:list(M))
    eq(copy:seen(I), 1); eq(copy:make("P", { f = M, c = 100, how = "hand" }).i, I .. ":2")
  end)
end)

describe("ledger hardening", function()
  it("a forged id far above my counter never moves it (C)", function()
    local l = L()
    eq(l:add(entry("C", I, 999999999, { r = M .. ":1" }), P), "new")
    eq(l:seen(I), 999999999); eq(l:bump(999999999), false)
    eq(l:make("P", { f = M, c = 100, how = "hand" }).i, I .. ":1")
    eq(l:add(entry("C", I, 1001, { r = M .. ":1" }), P), "new"); eq(l:bump(1001), true)
    eq(l:make("P", { f = M, c = 100, how = "hand" }).i, I .. ":1002")
    eq(l:add(entry("C", I, 2003, { r = M .. ":1" }), P), "new")
    eq(l:make("P", { f = M, c = 100, how = "hand" }).i, I .. ":1003")
    eq(C.LEDGER_JUMP, 1000)
  end)
  it("make never writes an id that author() refuses (C)", function()
    local store = { me = { [I] = { seq = 999999999, born = 1 } } }
    local l = Ledger.new(store, I, function() return NOW end)
    eq({ l:make("P", { f = M, c = 100, how = "hand" }) }, { nil, "full" })
    eq(store.me[I].seq, 999999999)
  end)
  it("an X its author denied denies nothing (I-1)", function()
    local l = L()
    eq(l:add(paid(1), M), "new")
    local real = l:get(M .. ":1")
    l:add(entry("X", M, 2, { r = real.i, h = real.h }), P)
    eq(l:denied(real), true)
    local forged = l:get(M .. ":2")
    l:add(entry("X", M, 3, { r = forged.i, h = forged.h }), M)
    eq(l:denied(forged), true); eq(l:denied(real), false)
  end)
  it("my own version of my entry is never evicted (I-2)", function()
    local s = {}
    for j = 1, 5 do s[j] = entry("P", I, 1, { f = M, c = 100 * j, how = "hand" }) end
    table.sort(s, function(a, b) return U.byteLess(Ledger.hash(a), Ledger.hash(b)) end)
    local mine, other = L(), L(P)
    local made = mine:make("P", { f = M, c = s[5].c, how = "hand" })
    eq(made.h, Ledger.hash(s[5]))
    other:add(s[5], I)
    for j = 1, 3 do eq(mine:add(s[j], P), "twin"); eq(other:add(s[j], M), "twin") end
    eq({ mine:add(s[4], P) }, { nil, "twins" }); eq(other:add(s[4], M), "twin")
    eq(mine:has(made.i, made.h), true); eq(other:has(made.i, made.h), false)
  end)
  it("h is 16 hex; the same h with another canon is another version (I-3)", function()
    eq(#Ledger.hash(GOOD.D()), 16)
    local hash = Ledger.hash
    Ledger.hash = function() return "0000000000000000" end
    local s, err = pcall(function()
      local l = L()
      eq(l:add(claim(50000), P), "new"); eq(l:add(claim(60000), P), "twin"); eq(l:add(claim(50000), P), "dup")
      local _, tw = l:get(M .. ":1"); eq(#tw, 1)
    end)
    Ledger.hash = hash
    if not s then error(err, 0) end
  end)
  it("a name of a dash, an r with a bad author, an X h not 16 lowercase hex", function()
    bad(with("R", "n", { "-", M }), "name")
    bad(with("C", "r", string.rep("Ж", 40) .. ":1"), "shape"); bad(with("C", "r", "a|b,c:1"), "shape")
    bad(with("X", "h", "0123456789ABCDEF"), "shape"); bad(with("X", "h", "0123abcd"), "shape")
  end)
  it("a load drops malformed bodies and recomputes x", function()
    local store = {}
    local l = Ledger.new(store, I, function() return NOW end)
    l:add(paid(1), M); l:add(paid(2), M)
    local good = l:vector()
    local copy = U.copy(store)
    copy.ev[M][3] = { i = M .. ":3", k = "P" }                       -- no h
    copy.ev[M][4] = { i = M .. ":4", k = "X", r = M .. ":1", h = "0123456789abcdef" } -- no rh
    copy.ev[M][5] = "junk"; copy.ev[M]["6"] = paid(6); copy.ev[P] = 7
    copy.ev[M][7] = l:get(M .. ":1")                                  -- under another number
    copy.x[M] = 12345
    local re = Ledger.new(copy, I, function() return NOW end)
    eq(re:vector(), good); eq(re:list(M), l:list(M)); eq(re:seen(M), 2)
  end)
end)
