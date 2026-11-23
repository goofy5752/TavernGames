local ns = Loader.ns()
local Ledger, View, U, C = ns.Ledger, ns.LedgerView, ns.Util, ns.Const

-- Stage F4, Task 1: stubs in the store (core/LedgerStub.lua). As ruled (J1 a) a body is
-- stubbed only by the per-author cap, oldest first; age alone stubs nothing.
local I, M, P = "Иван Петров", "Мария Колева", "Петър Иванов"
local ME = "Свидетел Тихов"
local NOW = 1700000000
local OLD = NOW - 2 * 31536000 -- two years back
local G1, G2 = "Иван Петров#1700000000/12", "Иван Петров#1700000000/13"

-- A bystander's ledger on a movable clock (b.now). add(author, kind, fields, n, at) files an
-- entry of that author got from the author, numbered n (default: the author's next number).
local function book(store)
  local b = { seq = {}, now = NOW }
  b.clock = function() return b.now end
  b.l = Ledger.new(store or {}, ME, b.clock)
  function b.entry(author, kind, fields, n, at)
    n = n or (b.seq[author] or 0) + 1
    b.seq[author] = math.max(b.seq[author] or 0, n)
    local e = U.copy(fields)
    e.k, e.i, e.at = kind, Ledger.id(author, n), at or b.now
    return e
  end
  function b.add(author, kind, fields, n, at)
    local status, body = b.l:add(b.entry(author, kind, fields, n, at), author)
    assert(status == "new" or status == "twin", "add " .. tostring(body))
    return body
  end
  function b.result(author, n, at, gid)
    return b.add(author, "R", { gid = gid or I .. "#1/" .. (n or 0), g = "ttt", n = { I, M }, w = { 1 }, l = { 2 } }, n, at)
  end
  function b.cash(author, n, at)
    return b.add(author, "S", { gid = I .. "#2/" .. n, g = "holdem", f = M, c = 10000, sk = 10000, n = { I, M }, w = { 2 }, l = { 1 } }, n, at)
  end
  function b.debt(author, f, t, c, gid, n, at)
    return b.add(author, "D", { gid = gid or G1, g = "ttt", f = f, t = t, c = c, why = "lost" }, n, at)
  end
  function b.confirm(author, d, at) return b.add(author, "C", { r = d.i, dh = d.h }, nil, at) end
  function b.contest(author, d, at) return b.add(author, "N", { r = d.i, dh = d.h, why = "no" }, nil, at) end
  function b.pay(t, f, c, at) return b.add(t, "P", { f = f, c = c, how = "hand" }, nil, at) end
  function b.deny(author, e, at) return b.add(author, "X", { r = e.i, h = e.h }, nil, at) end
  function b.view() return View.of(b.l) end
  return b
end

-- Runs fn with the cap lowered: LEDGER_AUTHOR_MAX = max, LEDGER_AUTHOR_ROOM = room (restored after).
local function cap(max, room, fn)
  local m, r = C.LEDGER_AUTHOR_MAX, C.LEDGER_AUTHOR_ROOM
  C.LEDGER_AUTHOR_MAX, C.LEDGER_AUTHOR_ROOM = max, room
  local good, err = pcall(fn)
  C.LEDGER_AUTHOR_MAX, C.LEDGER_AUTHOR_ROOM = m, r
  if not good then error(err, 0) end
end

-- What a LID would list of author a: every body's "<n>.<h>" and every stub's, sorted.
local function lidItems(l, a)
  local out = l:list(a)
  for _, s in ipairs(l:stubs(a)) do out[#out + 1] = s.n .. "." .. s.h end
  table.sort(out, U.byteLess)
  return out
end

describe("ledger F4: stubs keep x, n, the digest and every balance", function()
  it("a prune changes no x, no n, no digest and no balance", function()
    local b = book()
    local h = {}
    for n = 1, 6 do h[n] = b.result(M, n, OLD).h end
    local d = b.debt(M, I, M, 50000, G1, 7, OLD); b.confirm(I, d); b.pay(M, I, 20000)
    local v0, dg, cell = b.view(), b.l:digest(), b.l:vector()[M]
    local net, open = View.net(v0, I, M), View.totals(v0).open
    cap(10, 10, function()
      local n, more = b.l:prune(NOW, 100)
      eq(n, 6); eq(more, false)
    end)
    eq(b.l:digest(), dg); eq(b.l:vector()[M].n, cell.n); eq(b.l:vector()[M].x, cell.x)
    eq(View.net(b.view(), I, M), net); eq(View.totals(b.view()).open, open)
    ok(b.l:get(d.i))
    for n = 1, 6 do eq(b.l:get(Ledger.id(M, n)), nil); ok(b.l:stubbed(M, n, h[n])) end
    eq(b.l.rc[M], 0); eq(b.l:stubCount(), 6); eq(b.l:stubTop(M), 6); eq(b.l:stubTop(I), 0)
  end)

  it("a pruned, an unpruned and an F1–F3 store have the same vector, digest and LID items", function()
    local function fill(b)
      for n = 1, 8 do b.result(M, n, OLD + n) end
      for n = 1, 3 do b.cash(P, n, OLD + n) end
      b.result(M, 10, NOW) -- a hole at 9
      local d = b.debt(I, M, I, 30000, G2); b.confirm(M, d)
      b.l:refuse(M, 9, ("e"):rep(16)) -- a remembered refusal fills the hole
    end
    local pruned, kept = book(), book()
    fill(pruned); fill(kept)
    cap(10, 7, function() eq(select(1, pruned.l:prune(NOW, 100)), 6) end) -- M 9 -> 3; P is at 3
    eq(pruned.l.rc[M], 3); eq(pruned.l.rc[P], 3)
    -- An F1–F3 store: the same bodies saved by a client that knows no stubs (no st at all).
    local old = U.copy(kept.l.store); old.st = nil
    local f13 = Ledger.new(old, ME, kept.clock)
    for _, l in ipairs({ kept.l, f13 }) do
      eq(pruned.l:vector(), l:vector()); eq(pruned.l:digest(), l:digest())
      for _, a in ipairs({ M, P, I }) do eq(lidItems(pruned.l, a), lidItems(l, a), a) end
    end
    eq(pruned.l:vector()[M].n, 11) -- 1..8 (6 of them stubs), 9 refused, 10, and Мария's C at 11
    -- A twin that comes later to a stubbed id: both still agree.
    local e = pruned.entry(M, "R", { gid = "other/1", g = "ttt", n = { M, I }, w = { 2 }, l = { 1 } }, 1, NOW)
    eq(pruned.l:add(U.copy(e), M), "new"); eq(kept.l:add(U.copy(e), M), "twin")
    eq(pruned.l:digest(), kept.l:digest()); eq(lidItems(pruned.l, M), lidItems(kept.l, M))
  end)
end)

describe("ledger F4: what is stubbed", function()
  it("age alone stubs nothing (ruling J1 a)", function()
    local b = book()
    for n = 1, 5 do b.result(M, n, OLD) end
    b.debt(I, M, I, 30000, G1, 1, OLD)
    b.now = OLD; b.l:make("R", { gid = "mine/1", g = "ttt", n = { ME, M }, w = { 1 }, l = { 2 } }); b.now = NOW
    local n, more = b.l:prune(NOW, 100)
    eq(n, 0); eq(more, false); eq(b.l:stubCount(), 0)
    for k = 1, 5 do ok(b.l:get(Ledger.id(M, k))) end
    ok(b.l:get(Ledger.id(ME, 1)))
  end)

  it("only R and S are ever stubbed", function()
    local b = book()
    local r, s = b.result(M, 1, OLD), b.cash(M, 2, OLD)
    local d = b.debt(M, I, M, 50000, G1, 3, OLD)
    local c = b.confirm(I, d, OLD)
    local d2 = b.debt(M, I, M, 20000, G2, 4, OLD)
    local nn = b.contest(I, d2, OLD)
    local p = b.pay(M, I, 1000, OLD)
    local x = b.deny(M, p, OLD)
    cap(10, 10, function() eq(select(1, b.l:prune(NOW, 100)), 2) end)
    eq(b.l:get(r.i), nil); eq(b.l:get(s.i), nil); ok(b.l:stubbed(M, 2, s.h))
    for _, e in ipairs({ d, c, d2, nn, p, x }) do
      ok(b.l:get(e.i) == e, e.k .. " survives")
      eq(b.l:stub(e), false, e.k)
    end
  end)

  it("a stubbed entry offered again is a dup and files no body", function()
    local b = book()
    local r = b.result(M, 1, OLD)
    local again = Ledger.wire(r)
    cap(10, 10, function() b.l:prune(NOW, 100) end)
    local rev = b.l.rev
    eq(b.l:add(U.copy(again), "Някой"), "dup")
    eq(b.l:add(U.copy(again), M), "dup")
    eq(b.l:get(r.i), nil); eq(b.l.rev, rev); eq(b.l.rc[M], 0)
  end)

  it("my own entries stay until the cap, then the oldest go first", function()
    local b = book()
    local function mine() return b.l:make("R", { gid = "mine/" .. b.now, g = "ttt", n = { ME, M }, w = { 1 }, l = { 2 } }) end
    b.now = OLD
    for _ = 1, 3 do ok(mine()) end
    b.now = NOW
    eq(select(1, b.l:prune(NOW, 100)), 0)
    for n = 1, 3 do ok(b.l:get(Ledger.id(ME, n)), "an old own R stays below the cap") end
    cap(10, 4, function()
      for _ = 1, 7 do b.now = b.now + 1; ok(mine()) end
      eq(select(2, mine()), "full")
      local n, more = b.l:prune(NOW, 100)
      eq(n, 4); eq(more, false); eq(b.l.rc[ME], 6)
      for k = 1, 4 do eq(b.l:get(Ledger.id(ME, k)), nil) end
      for k = 5, 10 do ok(b.l:get(Ledger.id(ME, k))) end
      local e = mine()
      ok(e); eq(e.i, Ledger.id(ME, 11))
    end)
  end)

  it("the cap rule frees another author too, oldest first", function()
    local b = book()
    b.result(M, 1, NOW - 10); b.result(M, 2, NOW - 50); b.result(M, 3, NOW - 30)
    b.result(M, 4, NOW - 50); b.result(M, 5, NOW)
    b.result(P, 1, OLD); b.result(P, 2, OLD)
    cap(10, 7, function() -- 3 R+S bodies kept per author
      local n, more = b.l:prune(NOW, 100)
      eq(n, 2); eq(more, false)
    end)
    eq(b.l:get(Ledger.id(M, 2)), nil); eq(b.l:get(Ledger.id(M, 4)), nil)
    for _, k in ipairs({ 1, 3, 5 }) do ok(b.l:get(Ledger.id(M, k))) end
    ok(b.l:get(Ledger.id(P, 1))); ok(b.l:get(Ledger.id(P, 2)))
    eq(b.l.rc[M], 3); eq(b.l.rc[P], 2)
  end)

  it("an id with twins and an un body are never stubbed", function()
    local b = book()
    local one = b.result(M, 1, OLD)
    local two = b.add(M, "R", { gid = "twin/1", g = "ttt", n = { M, I }, w = { 2 }, l = { 1 } }, 1, OLD)
    local own = b.l:make("R", { gid = "mine/1", g = "ttt", n = { ME, M }, w = { 1 }, l = { 2 } })
    own.un = true -- put to me after a crash (Net:ask)
    cap(10, 10, function()
      eq(select(1, b.l:prune(NOW, 100)), 0)
      eq(b.l:stub(one), false); eq(b.l:stub(two), false); eq(b.l:stub(own), false)
    end)
    eq(#b.l:bodies(M, 1), 2); ok(b.l:get(own.i) == own); eq(b.l:stubCount(), 0)
  end)

  it("an R of a game whose debt is still pending is not stubbed until the debt is settled", function()
    local b = book()
    local r1 = b.result(I, 1, OLD, G1)
    local r2 = b.result(I, 2, OLD + 1, G2)
    local d = b.debt(I, M, I, 50000, G1, 3, OLD) -- pending: Мария has not said a word
    b.debt(I, M, I, 20000, G2, 4, OLD); b.confirm(M, b.l:get(Ledger.id(I, 4)))
    cap(10, 10, function()
      local n, more = b.l:prune(NOW, 100)
      eq(n, 1); eq(more, false)
      ok(b.l:get(r1.i) == r1, "its debt is pending"); eq(b.l:get(r2.i), nil)
      b.confirm(M, d)
      eq(select(1, b.l:prune(NOW, 100)), 1)
      eq(b.l:get(r1.i), nil)
    end)
  end)

  it("a twin that comes to a stubbed id counts the stub toward the four", function()
    local b = book()
    b.result(M, 1, OLD)
    cap(10, 10, function() eq(select(1, b.l:prune(NOW, 100)), 1) end)
    -- Four more versions of M:1, the one with the highest h last: three are taken, the fourth is refused.
    local vs = {}
    for j = 1, 4 do vs[j] = b.entry(M, "R", { gid = "v/" .. j, g = "ttt", n = { I, M }, w = { 1 }, l = { 2 } }, 1, NOW) end
    table.sort(vs, function(p, q) return U.byteLess(Ledger.hash(p), Ledger.hash(q)) end)
    eq(b.l:add(vs[1], M), "new"); eq(b.l:add(vs[2], M), "twin"); eq(b.l:add(vs[3], M), "twin")
    eq(select(2, b.l:add(vs[4], M)), "twins")
    eq(#b.l:bodies(M, 1), 3); eq(b.l:stubCount(), 1)
  end)

  it("my counter steps over a number of mine I hold only as a stub", function()
    local h = ("ab"):rep(8)
    local b = book({ st = { [ME] = { ["1." .. h] = true } }, me = { [ME] = { seq = 0, born = NOW } } })
    ok(b.l:stubbed(ME, 1, h))
    local e = b.l:make("R", { gid = "mine/1", g = "ttt", n = { ME, M }, w = { 1 }, l = { 2 } })
    eq(e.i, Ledger.id(ME, 2))
  end)
end)

describe("ledger F4: stubs are saved", function()
  it("stubs survive a save and a load", function()
    local b = book()
    local h = {}
    for n = 1, 6 do h[n] = b.result(M, n, OLD).h end
    b.result(P, 1, NOW)
    cap(10, 10, function() b.l:prune(NOW, 100) end)
    local dg, vec = b.l:digest(), b.l:vector()
    for _, store in ipairs({ b.l.store, U.copy(b.l.store) }) do
      local l = Ledger.new(store, ME, b.clock)
      eq(l:digest(), dg); eq(l:vector(), vec)
      for n = 1, 6 do ok(l:stubbed(M, n, h[n])); eq(l:get(Ledger.id(M, n)), nil) end
      eq(l:seen(M), 6); eq(l.rc[M] or 0, 0); eq(l.run[M], 6, "the counted run steps over the stubs (J7)")
      eq(l:stubCount(), 7)
    end
  end)

  it("an author of stubs only keeps its cell", function()
    local function fill(b)
      for n = 1, 6 do b.result(M, n, OLD) end
      b.l:refuse(M, 9, ("c"):rep(16)) -- a refusal of the same author is remembered too (J6)
    end
    local b, kept = book(), book()
    fill(b); fill(kept)
    cap(10, 10, function() eq(select(1, b.l:prune(NOW, 100)), 6) end)
    eq(b.l:vector()[M].n, 6)
    local l = Ledger.new(b.l.store, ME, b.clock)
    eq(l:vector()[M].n, 6); eq(l:vector()[M].x, kept.l:vector()[M].x)
    eq(l:digest(), kept.l:digest())
  end)

  it("a tampered st is dropped row by row", function()
    local b, twin = book(), book()
    local h1, h2 = b.result(M, 1, OLD).h, b.result(M, 2, OLD).h
    twin.result(M, 1, OLD); twin.result(M, 2, OLD)
    local store = b.l.store
    store.st = 5
    local l = Ledger.new(store, ME, b.clock)
    eq(l:stubCount(), 0); eq(l:digest(), twin.l:digest())
    store.st = {
      [M] = { ["x.y"] = true, ["3." .. ("a"):rep(15)] = true, ["2." .. h2] = 1, ["1." .. h1] = true,
        ["4." .. ("A"):rep(16)] = true, ["0." .. ("a"):rep(16)] = true, ["1234567890." .. ("a"):rep(16)] = true,
        [5] = true, ["6." .. ("a"):rep(16)] = "yes" },
      [P] = 7, ["a|b"] = { ["1." .. ("a"):rep(16)] = true }, [""] = { ["1." .. ("a"):rep(16)] = true },
    }
    l = Ledger.new(store, ME, b.clock)
    eq(l:stubCount(), 0); eq(l:digest(), twin.l:digest()); eq(l:vector(), twin.l:vector())
    eq(next(store.st), nil, "the saved set keeps no bad row")
  end)
end)

describe("ledger F4: the prune walks in steps", function()
  it("max bounds one call", function()
    local b = book()
    for n = 1, 6 do b.result(M, n, OLD + n) end
    cap(10, 10, function()
      local n, more = b.l:prune(NOW, 4)
      eq(n, 4); eq(more, true)
      n, more = b.l:prune(NOW, 4)
      eq(n, 2); eq(more, false)
    end)
    for k = 1, 6 do eq(b.l:get(Ledger.id(M, k)), nil) end
  end)

  it("a call visits at most LEDGER_PRUNE_STEP bodies and resumes where it stopped (J2)", function()
    local b = book()
    for n = 1, 12 do b.result(M, n, OLD + 100 - n) end -- the highest numbers are the oldest
    for n = 1, 4 do b.debt(M, I, M, 10000, "g/" .. n, 12 + n) end
    for n = 1, 9 do b.result(P, n, OLD) end -- below the cap: never walked
    local step = C.LEDGER_PRUNE_STEP
    C.LEDGER_PRUNE_STEP = 5
    local good, err = pcall(cap, 19, 10, function() -- 9 R+S bodies kept per author
      local calls, total, more = 0, 0, true
      while more do
        local v = b.l.visited or 0
        local n
        n, more = b.l:prune(NOW, 100)
        calls, total = calls + 1, total + n
        ok((b.l.visited or 0) - v <= 5, "call " .. calls .. " visited " .. ((b.l.visited or 0) - v))
        if calls == 2 then b.result(M, 30, NOW); b.result(P, 30, NOW) end -- the store changes mid-walk
        ok(calls < 20, "the walk ends")
      end
      ok(calls >= 4, "16 bodies of M walked in steps of 5: " .. calls .. " calls")
      eq(total, 4); eq(b.l.rc[M], 9); eq(b.l.rc[P], 10)
      for k = 9, 12 do eq(b.l:get(Ledger.id(M, k)), nil, "M:" .. k .. " is among the oldest") end
      for k = 1, 8 do ok(b.l:get(Ledger.id(M, k))) end
      ok(b.l:get(Ledger.id(M, 30)))
    end)
    C.LEDGER_PRUNE_STEP = step
    if not good then error(err, 0) end
  end)
end)

describe("ledger F4: an idle author's kept list (Decision M5)", function()
  it("an idle author's kept list is dropped once hashed, an active one's is kept", function()
    local b = book()
    b.result(M, 1, NOW - C.LEDGER_IL_IDLE - 1)
    b.result(P, 1, NOW)
    eq(b.l:work(), true)
    eq(b.l.il[M], nil); eq(type(b.l.il[P]), "table")
    b.result(M, 2, NOW - C.LEDGER_IL_IDLE - 1)
    eq(b.l:work(), true)
    local fresh = Ledger.new(U.copy(b.l.store), ME, b.clock)
    eq(fresh:work(), true)
    eq(b.l.xc[M], fresh.xc[M]); eq(b.l.xc[P], fresh.xc[P])
  end)
end)
