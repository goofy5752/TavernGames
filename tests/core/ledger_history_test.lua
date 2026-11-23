local ns = Loader.ns()
local Ledger, History, U, C = ns.Ledger, ns.LedgerHistory, ns.Util, ns.Const

-- Stage F4, Task 4: the chronology (core/LedgerHistory.lua).
local I, M, P, Q = "Иван Петров", "Мария Колева", "Петър Иванов", "Цвета Димова"
local NOW = 1700000000
local function gid(k) return "Маса#1/" .. k end

local function book()
  local b = { l = Ledger.new({}, "Свидетел Тихов", function() return NOW end), seq = {} }
  function b.add(author, kind, fields, n, at)
    n = n or (b.seq[author] or 0) + 1
    b.seq[author] = math.max(b.seq[author] or 0, n)
    local e = U.copy(fields)
    e.k, e.i, e.at = kind, Ledger.id(author, n), at or NOW
    local status, body = b.l:add(e, author)
    assert(status == "new" or status == "twin", "add " .. tostring(body))
    return body
  end
  -- A fun game at gid(k): seat 1 beat seat 2, written by `author` (default a).
  function b.fun(k, a, z, at, author)
    return b.add(author or a, "R", { gid = gid(k), g = "ttt", n = { a, z }, w = { 1 }, l = { 2 } }, nil, at or NOW + k)
  end
  -- A staked game a beat z: a's R, then the D of z (its own: confirmed) or a's (pending).
  function b.staked(k, a, z, c, at, pending)
    at = at or NOW + k
    b.add(a, "R", { gid = gid(k), g = "ttt", n = { a, z }, w = { 1 }, l = { 2 }, sk = c }, nil, at)
    return b.add(pending and a or z, "D", { gid = gid(k), g = "ttt", f = z, t = a, c = c, why = "lost" }, nil, at)
  end
  function b.pay(t, f, c, at) return b.add(t, "P", { f = f, c = c, how = "hand" }, nil, at) end
  function b.deny(author, e, at) return b.add(author, "X", { r = e.i, h = e.h }, nil, at) end
  return b
end
local function kinds(lines)
  local out = {}
  for j, l in ipairs(lines) do out[j] = l.kind end
  return out
end

describe("ledger history: the chronology", function()
  it("games and payments interleave, newest first", function()
    local b = book()
    b.fun(1, I, M, NOW - 500)
    b.pay(I, M, 300, NOW - 300)
    b.fun(2, M, P, NOW - 100)
    local lines = History.lines(b.l)
    eq(kinds(lines), { "game", "pay", "game" })
    eq(lines[1].at, NOW - 100); eq(lines[1].rec.gid, gid(2))
    eq(lines[2].at, NOW - 300); eq(lines[2].f, M); eq(lines[2].t, I); eq(lines[2].c, 300); eq(lines[2].how, "hand")
    eq(lines[2].rl, nil)
    eq(lines[3].rec.gid, gid(1))
  end)

  it("a payment got from a third party is marked relayed", function()
    local b = book()
    eq(b.l:add({ k = "P", i = Ledger.id(I, 1), at = NOW, f = M, c = 5, how = "hand" }, Q), "new")
    eq(History.lines(b.l)[1].rl, true)
  end)

  it("a tie in time sorts a game before a payment before a denied entry, then by id bytes", function()
    local b = book()
    b.fun(1, I, M, NOW)
    b.pay(P, Q, 10, NOW)
    b.pay(I, Q, 10, NOW)
    local x = b.fun(2, M, Q, NOW)
    b.deny(M, x, NOW)
    local lines = History.lines(b.l)
    eq(kinds(lines), { "game", "pay", "pay", "denied" })
    eq(lines[2].t, I); eq(lines[3].t, P) -- by id bytes
  end)

  it("a pending and a contested staked game are listed with their state", function()
    local b = book()
    b.staked(1, I, M, 50000, nil, true)
    b.staked(2, P, Q, 20000)
    local d = b.staked(3, I, P, 10000, nil, true)
    b.add(P, "N", { r = d.i, dh = d.h, why = "no" })
    local by = {}
    for _, l in ipairs(History.lines(b.l)) do by[l.rec.gid] = l.rec end
    eq(by[gid(1)].state, "pending"); eq(by[gid(1)].counts, {}); eq(by[gid(1)].sk, 50000)
    eq(by[gid(2)].state, "confirmed"); eq(by[gid(2)].sk, 20000)
    eq(by[gid(3)].state, "contested")
  end)

  it("a denied result stays, as denied, and is in no game line", function()
    local b = book()
    local r = b.fun(1, I, M, NOW - 10)
    b.deny(I, r, NOW - 5)
    local lines = History.lines(b.l)
    eq(kinds(lines), { "denied" })
    eq(lines[1].entry.i, r.i); eq(lines[1].at, NOW - 10)
  end)

  it("a denied payment and a denied stand are listed; a denied debt is not", function()
    local b = book()
    b.deny(I, b.pay(I, M, 700, NOW - 3))
    b.deny(P, b.add(P, "S", { gid = gid(9), g = "holdem", f = P, c = 100, sk = 100, n = { P, Q }, w = {}, l = {} }, nil, NOW - 2))
    b.deny(I, b.add(I, "D", { gid = gid(8), g = "ttt", f = M, t = I, c = 100, why = "lost" }))
    eq(kinds(History.lines(b.l)), { "denied", "denied" })
  end)

  it("the name filter keeps a player's games, payments and denied entries only", function()
    local b = book()
    b.fun(1, I, M, NOW - 90)
    b.fun(2, P, Q, NOW - 80)
    b.pay(I, M, 100, NOW - 70)
    b.pay(P, Q, 100, NOW - 60)
    b.deny(Q, b.fun(3, Q, P, NOW - 50), NOW - 40)
    b.deny(P, b.add(P, "P", { f = Q, c = 5, how = "hand" }, nil, NOW - 30))
    eq(kinds(History.lines(b.l, M)), { "pay", "game" })
    eq(#History.lines(b.l), 6)
    eq(kinds(History.lines(b.l, Q)), { "denied", "denied", "pay", "game" })
    eq(History.lines(b.l, "Никой"), {})
  end)

  it("a Холдем sitting is a game line of its player", function()
    local b = book()
    b.add(P, "S", { gid = gid(9), g = "holdem", f = P, c = 100, sk = 100, n = { P, Q }, w = {}, l = {} }, nil, NOW - 2)
    b.fun(1, I, M, NOW - 5)
    local lines = History.lines(b.l, P)
    eq(kinds(lines), { "game" }); eq(lines[1].rec.cash, true)
    eq(#History.lines(b.l, Q), 0)
  end)

  it("a stubbed result is gone from the lines and its payments stay", function()
    local b = book()
    local m, r = C.LEDGER_AUTHOR_MAX, C.LEDGER_AUTHOR_ROOM
    C.LEDGER_AUTHOR_MAX, C.LEDGER_AUTHOR_ROOM = 10, 7
    local good, err = pcall(function()
      for k = 1, 9 do b.fun(k, I, M, NOW - 100 + k) end
      b.pay(I, M, 50, NOW - 20)
      eq(#History.lines(b.l), 10)
      eq(b.l:prune(NOW, 100), 6)
      local lines = History.lines(b.l)
      eq(kinds(lines), { "pay", "game", "game", "game" })
      eq(lines[2].rec.gid, gid(9))
      eq(#History.lines(b.l, M), 4)
    end)
    C.LEDGER_AUTHOR_MAX, C.LEDGER_AUTHOR_ROOM = m, r
    if not good then error(err, 0) end
  end)

  it("the lines are built once per rev and name", function()
    local b = book()
    b.fun(1, I, M, NOW - 5)
    local a = History.lines(b.l)
    ok(History.lines(b.l) == a, "same rev, same name: the same table")
    local m = History.lines(b.l, M)
    ok(m ~= a)
    ok(History.lines(b.l, M) == m)
    b.pay(I, M, 5, NOW - 4)
    local c = History.lines(b.l, M)
    ok(c ~= m); eq(#c, 2)
  end)

  it("the cache holds one entry: a name asked before is built again (J3)", function()
    local b = book()
    b.fun(1, I, M, NOW - 5)
    local a = History.lines(b.l, I)
    History.lines(b.l, M)
    ok(History.lines(b.l, I) ~= a)
  end)

  it("a denial arriving after the lines were cached invalidates them", function()
    local b = book()
    local r = b.fun(1, I, M, NOW - 10)
    local a = History.lines(b.l)
    eq(kinds(a), { "game" })
    b.deny(I, r, NOW - 5)
    local c = History.lines(b.l)
    ok(c ~= a, "the old lines were served")
    eq(kinds(c), { "denied" })
  end)

  it("twin bodies of one id and one time keep a fixed order, by their hashes", function()
    local b = book()
    local x = b.add(I, "R", { gid = gid(1), g = "ttt", n = { I, M }, w = { 1 }, l = { 2 } }, 1, NOW)
    local y = b.add(I, "R", { gid = gid(2), g = "ttt", n = { I, P }, w = { 2 }, l = { 1 } }, 1, NOW)
    eq(x.i, y.i); ok(x.h ~= y.h)
    local first = History.lines(b.l)
    eq(#first, 2)
    local want = x.h < y.h and gid(1) or gid(2)
    eq(first[1].rec.gid, want)
  end)

  it("an empty ledger has no lines", function()
    eq(History.lines(book().l), {})
  end)
end)
