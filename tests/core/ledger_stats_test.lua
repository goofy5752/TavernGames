local ns = Loader.ns()
local Ledger, View, Stats, U = ns.Ledger, ns.LedgerView, ns.LedgerStats, ns.Util

local I, M, P, Q = "Иван Петров", "Мария Колева", "Петър Иванов", "Цвета Димова"
local NOW, DAY = 1700000000, 86400
local G1, G2 = "Иван Петров#1700000000/12", "Иван Петров#1700000000/13"
local function gid(k) return "Маса#1/" .. k end

-- A bystander's ledger (as in ledger_view_test.lua). add(author, kind, fields, n, at)
-- files an entry of that author got from the author, numbered n (default: next).
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
  -- An R of `author`: g "ttt" and gid G1 unless the fields say otherwise.
  function b.result(author, fields, n, at)
    local e = U.copy(fields)
    e.gid, e.g = e.gid or G1, e.g or "ttt"
    return b.add(author, "R", e, n, at)
  end
  function b.debt(author, f, t, c, g, at, game)
    return b.add(author, "D", { gid = g or G1, g = game or "ttt", f = f, t = t, c = c, why = "lost" }, nil, at)
  end
  function b.confirm(author, d) return b.add(author, "C", { r = d.i, dh = d.h }) end
  function b.contest(author, d) return b.add(author, "N", { r = d.i, dh = d.h, why = "no" }) end
  function b.deny(author, e) return b.add(author, "X", { r = e.i, h = e.h }) end
  -- The host's S of f at the cash gid g: names n, the S's own w/l (never read for the outcome).
  function b.stand(author, f, g, n, w, l, c)
    return b.add(author, "S", { gid = g, g = "holdem", f = f, c = c or 20000, sk = 100, n = n, w = w or {}, l = l or {} })
  end
  -- A fun game of author at gid(k), at NOW + k: seat 1 won, seat 2 lost (draw: neither).
  function b.fun(author, k, a, z, draw, game)
    local w, l = { 1 }, { 2 }
    if draw then w, l = {}, {} end
    return b.result(author, { gid = gid(k), g = game, n = { a, z }, w = w, l = l }, nil, NOW + k)
  end
  -- A debt of an honest staked game: t's claim, then f's own D (both sides' word).
  function b.both(f, t, c, g, game, at)
    b.debt(t, f, t, c, g, at, game)
    return b.debt(f, f, t, c, g, at, game)
  end
  -- A staked game at gid(k): a won, z lost; a claimed the debt and z confirmed it (its own D).
  function b.staked(k, a, z, c, game, at)
    b.result(a, { gid = gid(k), g = game, n = { a, z }, w = { 1 }, l = { 2 }, sk = c }, nil, at or NOW + k)
    return b.both(z, a, c, gid(k), game, at or NOW + k)
  end
  return b
end
local function games(b) return Stats.games(b.l) end
local function board(b, opts)
  opts = opts or {}
  opts.period, opts.now = opts.period or "all", opts.now or NOW
  return Stats.board(b.l, opts)
end
local function row(rows, name)
  for _, r in ipairs(rows) do if r.name == name then return r end end
end

describe("ledger stats: the trust rule", function()
  it("a fun result counts on a seated host's word, an outsider's for nobody", function()
    local b = book()
    b.add(I, "R", { gid = G1, g = "ttt", n = { I, M }, w = { 1 }, l = { 2 } })
    b.add(P, "R", { gid = G2, g = "ttt", n = { I, M }, w = { 2 }, l = { 1 } })
    local g = games(b)
    eq(#g, 2)
    eq(g[1].counts, { [I] = "win", [M] = "loss" }); eq(g[1].state, "fun"); eq(g[1].gid, G1); eq(g[1].by, { I })
    eq(g[2].counts, {}); eq(g[2].state, "claim")
  end)

  it("a staked loss counts only on the loser's word, a win only on a debtor's", function()
    local b = book()
    b.add(I, "R", { gid = G1, g = "ttt", n = { I, M }, w = { 1 }, l = { 2 }, sk = 50000 })
    local d = b.debt(I, M, I, 50000, G1)
    eq(games(b)[1].counts, {}); eq(games(b)[1].state, "pending")
    b.confirm(M, d)
    eq(games(b)[1].counts, { [I] = "win", [M] = "loss" }); eq(games(b)[1].state, "confirmed")
    eq(games(b)[1].sk, 50000); eq(games(b)[1].cash, nil)
    local rows = board(b).rows
    eq(rows[1].name, I); eq(rows[1].net, 50000); eq(rows[2].net, -50000)
  end)

  it("a contested debt backs nothing and marks the game", function()
    local b = book()
    b.result(I, { n = { I, M, P }, w = { 1, 2 }, l = { 3 }, sk = 1000, g = "deathroll" })
    b.debt(P, P, I, 1000, G1, nil, "deathroll")
    local d = b.debt(M, P, M, 1000, G1, nil, "deathroll")
    b.contest(P, d)
    local g = games(b)[1]
    eq(g.counts, { [I] = "win", [P] = "loss" }); eq(g.state, "contested")
    eq(row(board(b).rows, M), nil); eq(row(board(b).rows, P).net, -1000)
  end)

  it("a denied R counts for nobody", function()
    local b = book()
    local r = b.result(I, { n = { I, M }, w = { 1 }, l = { 2 } })
    b.deny(I, r)
    eq(#games(b), 0); eq(board(b).rows, {})
  end)

  it("a loser who wrote the R itself has lost", function()
    local b = book()
    b.result(M, { n = { I, M }, w = { 1 }, l = { 2 }, sk = 50000 })
    local g = games(b)[1]
    eq(g.counts, { [M] = "loss" }); eq(g.state, "pending")
  end)

  it("Belot: two confirmed pairs, four names, the leaver's partner draws", function()
    local b = book()
    b.result(M, { g = "belot", n = { I, M, P, Q }, w = { 2, 4 }, l = { 1 }, sk = 10000, why = "left" })
    b.both(I, M, 10000, G1, "belot"); b.both(I, Q, 10000, G1, "belot")
    local g = games(b)[1]
    eq(g.counts, { [I] = "loss", [M] = "win", [Q] = "win", [P] = "draw" }); eq(g.state, "confirmed"); eq(g.why, "left")
  end)

  it("a name counts once per gid", function()
    local b = book()
    b.result(I, { n = { I, M }, w = { 1 }, l = { 2 } }, nil, NOW)
    b.result(I, { n = { I, M, P }, w = { 1 }, l = { 2, 3 } }, nil, NOW + 1)
    local g = games(b)
    eq(#g, 2); eq(g[1].counts, { [I] = "win", [M] = "loss" }); eq(g[2].counts, { [P] = "loss" })
    eq(row(board(b).rows, I).games, 1); eq(row(board(b).rows, M).games, 1)
  end)

  it("two Rs of one game with the same content are one game", function()
    local b = book()
    b.result(M, { n = { I, M }, w = { 1 }, l = { 2 } })
    b.result(I, { n = { I, M }, w = { 1 }, l = { 2 } })
    local g = games(b)
    eq(#g, 1); eq(g[1].by, { I, M }); eq(#g[1].by, 2); eq(g[1].counts, { [I] = "win", [M] = "loss" })
  end)

  it("Холдем: an S counts by confirmed copper at its gid", function()
    local b = book()
    -- won: I owes M at gid(1), confirmed by I (its own D); the S's own w/l say the opposite
    b.stand(I, M, gid(1), { I, M }, { 1 }, { 2 })
    b.both(I, M, 3000, gid(1), "holdem")
    -- lost: M owes I at gid(2)
    b.stand(I, M, gid(2), { I, M })
    b.both(M, I, 2000, gid(2), "holdem")
    -- pending: I's claim on M at gid(3), never confirmed
    b.stand(I, M, gid(3), { I, M })
    b.debt(I, M, I, 2000, gid(3), nil, "holdem")
    local g = games(b)
    eq(#g, 3)
    eq(g[1].counts, { [M] = "win" }); eq(g[1].cash, true); eq(g[1].state, "confirmed"); eq(g[1].g, "holdem")
    eq(g[2].counts, { [M] = "loss" })
    eq(g[3].counts, {}); eq(g[3].state, "pending")
  end)

  it("Холдем: the stander's own S with a confirmed debt counts, without one it adds nothing", function()
    local b = book()
    b.stand(M, M, gid(1), { I, M })
    b.both(M, I, 2000, gid(1), "holdem")
    b.stand(M, M, gid(2), { I, M }) -- a copied or empty cash gid: no debt
    local g = games(b)
    eq(g[1].counts, { [M] = "loss" }); eq(g[2].counts, {}); eq(g[2].state, "claim")
  end)

  it("bodies of tampered saved variables raise nothing and count for nobody", function()
    local H = "0123456789abcdef"
    local function body(n, f) f.i, f.k, f.h, f.gid, f.g = I .. ":" .. n, f.k or "R", H, f.gid or G1, f.g or "ttt"; return f end
    local ev = {
      body(1, { at = "x", n = { I, M }, w = { 1 }, l = { 2 } }),
      body(2, { at = NOW, n = "x", w = { {} }, l = 7 }),
      body(3, { at = NOW, n = { I, {}, 5 }, w = { "a", 2, 3 }, l = {} }),
      body(4, { k = "S", at = 0 / 0, f = M, n = { I, M }, w = {}, l = {}, sk = 100, c = 100 }),
      body(5, { at = NOW + 1, gid = G2, n = { I, M }, w = { 1 }, l = { 2 } }),
    }
    local l = Ledger.new({ ev = { [I] = ev }, tw = {} }, "Свидетел Тихов", function() return NOW end)
    local g = Stats.games(l)
    eq(#g, 3)
    eq(g[1].counts, {}); eq(g[2].counts, { [I] = "draw" }); eq(g[3].counts, { [I] = "win", [M] = "loss" })
    eq(#Stats.board(l, { period = "week", now = NOW }).rows, 2)
    eq({ Stats.dress(g[2]) }, { { I }, {}, {} })
  end)

  it("an empty chair and a seat out of range are skipped", function()
    local b = book()
    b.result(I, { n = { I, false, M }, w = { 1, 5 }, l = { 2, 3 } })
    local g = games(b)[1]
    eq(g.counts, { [I] = "win", [M] = "loss" })
    for _, r in ipairs(board(b).rows) do ok(type(r.name) == "string") end
    eq(#board(b).rows, 2)
    local names, win, lose = Stats.dress(g)
    eq(names, { I, M }); eq(win, { [I] = true }); eq(lose, { [M] = true })
  end)

  it("a record is lean: names and sides are dressed on demand", function()
    local b = book()
    b.result(I, { n = { I, M }, w = { 1 }, l = { 2 } })
    local g = games(b)[1]
    eq(g.names, nil); eq(g.win, nil); eq(g.lose, nil)
    ok(Stats.named(g, M)); ok(not Stats.named(g, P))
    b.stand(I, M, gid(1), { I, M })
    b.both(I, M, 3000, gid(1), "holdem")
    local s = games(b)[2]
    eq({ Stats.dress(s) }, { { M }, { [M] = true }, {} }); ok(Stats.named(s, M)); ok(not Stats.named(s, I))
  end)
end)

describe("ledger stats: forging routes", function()
  it("a modified host inventing a staked result gets nothing", function()
    local b = book()
    -- P hosts, names itself the winner and I the loser, claims the debt and "confirms" it itself
    b.result(P, { n = { P, I }, w = { 1 }, l = { 2 }, sk = 90000 })
    local d = b.debt(P, I, P, 90000)
    b.confirm(P, d)
    local g = games(b)[1]
    eq(g.counts, {}); eq(g.state, "pending"); eq(board(b).rows, {})
  end)

  it("an outsider's staked R gives nobody a draw", function()
    local b = book()
    b.staked(1, I, M, 1000)
    b.result(P, { gid = gid(1), n = { I, M, Q }, w = {}, l = {}, sk = 1000 }, nil, NOW)
    local g = games(b)
    eq(#g, 2)
    local mine = g[1].by[1] == P and g[1] or g[2]
    eq(mine.counts, {}); eq(mine.state, "claim")
    eq(row(board(b).rows, Q), nil); eq(row(board(b).rows, I).wins, 1); eq(row(board(b).rows, M).games, 1)
  end)

  it("a copied R with the sides swapped wins nobody anything", function()
    local b = book()
    b.staked(1, I, M, 1000)
    -- an earlier R of the same gid that names the real loser the winner
    b.result(P, { gid = gid(1), n = { I, M }, w = { 2 }, l = { 1 }, sk = 1000 }, nil, NOW - 10)
    local forged = games(b)[1]
    eq(forged.by, { P }); eq(forged.counts, {})
    eq(games(b)[2].counts, { [I] = "win", [M] = "loss" })
  end)

  it("a player's copied R cannot turn its rival's win into a draw", function()
    local b = book()
    b.staked(1, I, M, 1000)
    -- M (a party: it owes at that gid) writes an earlier R of the same gid in which nobody won
    b.result(M, { gid = gid(1), n = { I, M }, w = {}, l = {}, sk = 1000 }, nil, NOW - 10)
    local r = board(b).rows
    eq(row(r, I).wins, 1); eq(row(r, I).games, 1); eq(row(r, M).games, 1); eq(row(r, M).wins, 0)
  end)

  it("a fun R copied onto a staked gid cannot change the staked outcome", function()
    local b = book()
    b.staked(1, I, M, 1000)
    b.result(M, { gid = gid(1), n = { M, I }, w = { 1 }, l = { 2 } }, nil, NOW) -- M's "fun" win at the same game, earlier
    local r = board(b).rows
    eq(row(r, I).wins, 1); eq(row(r, I).games, 1); eq(row(r, M).wins, 0); eq(row(r, M).games, 1)
    local fun = games(b)[1]
    eq(fun.state, "fun"); eq(fun.counts, {})
  end)

  -- Final review I2: a gid is "<opener>#<epoch>/<q>" (core/Session.lua), and a fun game is its opener's word.
  local function hosted(k) return I .. "#1700000000/" .. k end
  it("a loser's earlier fun R at the host's gid takes none of the host's wins, and no crown", function()
    local b = book()
    for k = 1, 5 do b.result(I, { gid = hosted(k), n = { I, M }, w = { 1 }, l = { 2 } }, nil, NOW - 100 + k) end
    eq(board(b).king, I)
    for k = 1, 5 do b.result(M, { gid = hosted(k), n = { I, M }, w = { 2 }, l = { 1 } }, nil, NOW - 5000 + k) end
    local d = board(b)
    eq(row(d.rows, I).wins, 5); eq(row(d.rows, I).games, 5); eq(row(d.rows, M).wins, 0); eq(row(d.rows, M).games, 5)
    eq(d.king, I)
    local g = games(b)
    eq(#g, 10)
    local forged = g[1].by[1] == M and g[1] or g[2]
    eq(forged.by, { M }); eq(forged.counts, {}); eq(forged.state, "claim")
  end)

  it("one who never sat there and names itself in an earlier fun R at the host's gid gains nothing", function()
    local b = book()
    for k = 1, 5 do b.result(I, { gid = hosted(k), n = { I, M }, w = { 1 }, l = { 2 } }, nil, NOW - 100 + k) end
    for k = 1, 5 do b.result(P, { gid = hosted(k), n = { P, I }, w = { 1 }, l = { 2 } }, nil, NOW - 5000 + k) end
    local d = board(b)
    eq(row(d.rows, I).wins, 5); eq(row(d.rows, I).games, 5); eq(row(d.rows, P), nil); eq(d.king, I)
  end)

  it("without a fun R of the opener that names it (a host that changed) the older seated record keeps the name", function()
    local b = book()
    b.result(M, { gid = hosted(1), n = { M, P }, w = { 1 }, l = { 2 } }, nil, NOW - 10) -- Мария took the table over
    b.result(P, { gid = hosted(1), n = { M, P }, w = { 2 }, l = { 1 } }, nil, NOW - 50)
    b.result(I, { gid = hosted(2), n = { M, P }, w = { 1 }, l = { 2 } }, nil, NOW - 10) -- the opener's, but it is not seated: nobody's
    b.result(P, { gid = hosted(2), n = { M, P }, w = { 2 }, l = { 1 } }, nil, NOW - 50)
    local d = board(b)
    eq(row(d.rows, P).wins, 2); eq(row(d.rows, M).wins, 0); eq(row(d.rows, M).games, 2); eq(row(d.rows, I), nil)
  end)

  it("the opener's fun R takes nothing from a staked result at its gid", function()
    local b = book()
    b.result(M, { gid = hosted(1), n = { M, I }, w = { 1 }, l = { 2 }, sk = 1000 }, nil, NOW)
    b.both(I, M, 1000, hosted(1), nil, NOW)
    b.result(I, { gid = hosted(1), n = { I, M }, w = { 1 }, l = { 2 } }, nil, NOW - 10) -- the opener's "fun" win there
    local r = board(b).rows
    eq(row(r, M).wins, 1); eq(row(r, I).wins, 0); eq(row(r, I).games, 1)
  end)

  it("a stranger's pending D at a fun gid changes nothing", function()
    local b = book()
    for k = 1, 5 do b.fun(I, k, I, M) end
    b.debt(P, Q, P, 100, gid(3), NOW + 3) -- P's own claim that Q owes it at I's fun game: never confirmed
    local d = board(b)
    eq(row(d.rows, I).wins, 5); eq(row(d.rows, I).games, 5); eq(row(d.rows, I).honour, { kind = "wins", n = 5 })
    eq(d.king, I)
    eq(games(b)[3].counts, { [I] = "win", [M] = "loss" }); eq(games(b)[3].state, "fun")
  end)

  it("an outsider's earlier copy of a fun R moves no game out of the week", function()
    local b = book()
    b.result(I, { gid = gid(1), n = { I, M }, w = { 1 }, l = { 2 } }, nil, NOW)
    b.result(P, { gid = gid(1), n = { I, M }, w = { 1 }, l = { 2 } }, nil, NOW - 40 * DAY)
    local g = games(b)
    eq(#g, 1); eq(g[1].at, NOW); eq(g[1].by, { P, I })
    eq(row(board(b, { period = "week" }).rows, I).wins, 1)
  end)

  it("an outsider's earlier staked copy changes no period, filter or favourite game", function()
    local b = book()
    b.staked(1, I, M, 1000)
    b.result(P, { gid = gid(1), g = "dice", n = { I, M }, w = { 1 }, l = { 2 }, sk = 1000 }, nil, NOW - 40 * DAY)
    b.result(P, { gid = gid(1), n = { I, M }, w = { 1 }, l = { 2 }, sk = 1000 }, nil, NOW - 39 * DAY)
    local week = board(b, { period = "week" }).rows
    eq(row(week, I).games, 1); eq(row(week, I).wins, 1); eq(row(week, M).games, 1)
    eq(row(board(b, { game = "ttt" }).rows, I).games, 1); eq(row(board(b, { game = "dice" }).rows, I), nil)
    eq(row(board(b).rows, I).fav, "ttt")
    for _, rec in ipairs(games(b)) do if rec.g == "dice" then eq(rec.counts, {}); eq(rec.state, "claim") end end
  end)

  it("an outsider's earlier copy breaks no run", function()
    local b = book()
    for k = 1, 4 do b.fun(I, k, I, M) end
    b.fun(M, 50, M, I) -- M beat I, later
    b.result(P, { gid = gid(50), n = { M, I }, w = { 1 }, l = { 2 } }, nil, NOW + 2) -- the same content, dated inside I's run
    eq(row(board(b).rows, I).honour, { kind = "wins", n = 4 })
    b = book()
    for k = 1, 4 do b.fun(I, k, I, M) end
    b.staked(50, M, I, 1000)
    b.result(P, { gid = gid(50), g = "dice", n = { M, I }, w = { 1 }, l = { 2 }, sk = 1000 }, nil, NOW + 2)
    b.result(P, { gid = gid(50), n = { M, I }, w = { 1 }, l = { 2 }, sk = 1000 }, nil, NOW + 2)
    eq(row(board(b).rows, I).honour, { kind = "wins", n = 4 }); eq(row(board(b).rows, I).fav, "ttt")
  end)

  it("a forger's self-confirmed debt and a result naming seven others give no draws", function()
    local b = book()
    for k = 1, 4 do b.fun(I, k, I, M) end
    local n = { P, Q, I, M }
    for j = 1, 5 do n[#n + 1] = "Жертва Номер" .. j end
    b.debt(P, P, Q, 100, gid(99), NOW + 2) -- P's own D: confirmed at once, Q never spoke
    b.result(P, { gid = gid(99), n = n, w = { 2 }, l = { 1 }, sk = 100 }, nil, NOW + 2)
    local r = board(b).rows
    eq(row(r, I).games, 4); eq(row(r, I).pct, 100); eq(row(r, I).honour, { kind = "wins", n = 4 })
    eq(row(r, M).games, 4)
    for j = 1, 5 do eq(row(r, "Жертва Номер" .. j), nil) end
  end)

  it("an outsider's staked R that counts is labelled by its debts, not a claim", function()
    local b = book()
    b.result(P, { gid = gid(1), n = { I, M }, w = { 1 }, l = { 2 }, sk = 1000 })
    b.both(M, I, 1000, gid(1))
    local g = games(b)[1]
    eq(g.counts, { [I] = "win", [M] = "loss" }); eq(g.state, "confirmed")
  end)

  it("an outsider's S adds no sitting", function()
    local b = book()
    b.stand(I, M, gid(1), { I, M })
    b.both(M, I, 2000, gid(1), "holdem")
    b.stand(P, I, gid(1), { I, M }) -- P sat nowhere: an extra sitting for I
    local g = games(b)
    local extra = g[1].by[1] == P and g[1] or g[2]
    eq(extra.counts, {}); eq(extra.state, "claim")
    eq(row(board(b).rows, I).games, 0); eq(row(board(b).rows, I).net, 2000); eq(row(board(b).rows, M).games, 1)
  end)

  it("extra S of one seat at one gid count once", function()
    local b = book()
    b.stand(I, M, gid(1), { I, M }, nil, nil, 20000)
    b.stand(I, M, gid(1), { I, M }, nil, nil, 30000)
    b.both(M, I, 2000, gid(1), "holdem")
    eq(#games(b), 2); eq(row(board(b).rows, M).games, 1)
  end)

  it("pending and contested debts count as nothing in the net", function()
    local b = book()
    b.result(I, { n = { I, M }, w = { 1 }, l = { 2 }, sk = 1000 })
    b.debt(I, M, I, 1000)
    local d = b.debt(I, P, I, 1000, gid(2))
    b.contest(P, d)
    eq(board(b).rows, {}); eq(board(b).top, 0)
  end)
end)

describe("ledger stats: the board", function()
  it("an entry an hour ahead is inside the week", function()
    local b = book()
    b.staked(1, I, M, 1000, nil, NOW + 3600)
    local r = board(b, { period = "week" }).rows
    eq(row(r, I).games, 1); eq(row(r, I).net, 1000)
  end)

  it("an entry of 8 days ago is in the month, not the week", function()
    local b = book()
    b.staked(1, I, M, 1000, nil, NOW - 8 * DAY)
    eq(board(b, { period = "week" }).rows, {})
    local r = board(b, { period = "month" }).rows
    eq(row(r, I).games, 1); eq(row(r, I).net, 1000); eq(row(r, M).net, -1000)
    b.staked(2, I, M, 1000, nil, NOW - 31 * DAY)
    eq(row(board(b, { period = "month" }).rows, I).games, 1); eq(row(board(b).rows, I).games, 2)
  end)

  it("rows: games, wins, pct, net; ordered by net, wins, games, name", function()
    local b = book()
    b.staked(1, I, M, 2000)
    b.fun(M, 2, M, P); b.fun(M, 3, M, P); b.fun(P, 4, P, M, true)
    local r = board(b).rows
    eq(#r, 3)
    eq(r[1].name, I); eq(r[1].games, 1); eq(r[1].wins, 1); eq(r[1].pct, 100); eq(r[1].net, 2000)
    eq(r[2].name, P); eq(r[2].games, 3); eq(r[2].wins, 0); eq(r[2].pct, 0); eq(r[2].net, 0)
    eq(r[3].name, M); eq(r[3].games, 4); eq(r[3].wins, 2); eq(r[3].pct, 50); eq(r[3].net, -2000)
    eq(board(b).top, 2000)
    b = book(); b.debt(M, M, I, 1000, gid(9))
    eq(board(b).rows, { { name = I, games = 0, wins = 0, net = 1000 }, { name = M, games = 0, wins = 0, net = -1000 } })
  end)

  it("a pct rounds half up", function()
    local b = book()
    b.fun(I, 1, I, M); b.fun(I, 2, I, M); b.fun(I, 3, M, I)
    eq(row(board(b).rows, I).pct, 67); eq(row(board(b).rows, M).pct, 33)
  end)

  it("the game filter narrows games and net, and fav is nil under it", function()
    local b = book()
    b.staked(1, I, M, 1000, "ttt"); b.staked(2, M, I, 3000, "deathroll")
    b.fun(I, 3, I, M, false, "ttt")
    local r = board(b, { game = "ttt" }).rows
    eq(row(r, I).games, 2); eq(row(r, I).net, 1000); eq(row(r, I).fav, nil)
    r = board(b).rows
    eq(row(r, I).games, 3); eq(row(r, I).net, -2000); eq(row(r, I).fav, "ttt")
  end)

  it("fav breaks a tie by byte order", function()
    local b = book()
    b.fun(I, 1, I, M, false, "ttt"); b.fun(I, 2, I, M, false, "deathroll")
    eq(row(board(b).rows, I).fav, "deathroll")
  end)

  it("honours: eight wins in a row; five losses in a row; a draw breaks a run; two is none", function()
    local b = book()
    for k = 1, 8 do b.fun(I, k, I, M) end
    for k = 11, 15 do b.fun(Q, k, Q, P) end
    local r = board(b).rows
    eq(row(r, I).honour, { kind = "wins", n = 8 }); eq(row(r, M).honour, { kind = "losses", n = 8 })
    eq(row(r, P).honour, { kind = "losses", n = 5 }); eq(row(r, Q).honour, { kind = "wins", n = 5 })
    b = book()
    b.fun(I, 1, I, M); b.fun(I, 2, I, M); b.fun(I, 3, I, M, true); b.fun(I, 4, I, M); b.fun(I, 5, I, M)
    eq(row(board(b).rows, I).honour, nil); eq(row(board(b).rows, M).honour, nil)
  end)

  it("a win run of three goes before a longer losing run", function()
    local b = book()
    for k = 1, 5 do b.fun(I, k, M, I) end
    for k = 6, 8 do b.fun(I, k, I, M) end
    eq(row(board(b).rows, I).honour, { kind = "wins", n = 3 })
    eq(row(board(b).rows, M).honour, { kind = "wins", n = 5 })
  end)

  it("the king is the highest positive net; without gold, the most wins among players with five games; else nil", function()
    local b = book()
    b.staked(1, M, I, 1000)
    for k = 2, 9 do b.fun(I, k, I, P) end
    eq(board(b).king, M)
    b = book()
    for k = 1, 3 do b.fun(I, k, I, M) end
    for k = 4, 5 do b.fun(I, k, M, I) end
    for k = 6, 9 do b.fun(P, k, P, Q) end
    eq(board(b).king, I) -- P won 4 of 4 games: fewer than five
    b = book()
    for k = 1, 4 do b.fun(I, k, I, M) end
    eq(board(b).king, nil)
    eq(board(book()).king, nil)
  end)

  it("the king ignores the game filter", function()
    local b = book()
    b.staked(1, M, I, 1000, "ttt")
    for k = 2, 9 do b.fun(I, k, I, P, false, "deathroll") end
    local d = board(b, { game = "deathroll" })
    eq(d.king, M); eq(row(d.rows, M), nil)
  end)

  it("versus: per opponent won, lost and confirmed copper", function()
    local b = book()
    b.staked(1, I, M, 5000)
    b.fun(I, 2, I, M); b.fun(M, 3, M, I); b.fun(I, 4, I, M, true)
    b.fun(P, 5, P, I)
    b.debt(Q, Q, I, 100, gid(6))
    eq(Stats.versus(b.l, I, { period = "all", now = NOW }), {
      { name = M, won = 2, lost = 1, net = 5000 },
      { name = Q, won = 0, lost = 0, net = 100 },
      { name = P, won = 0, lost = 1, net = 0 },
    })
    eq(Stats.versus(b.l, I, { period = "all", now = NOW, game = "deathroll" }), {})
  end)

  it("the games are computed once per rev", function()
    local b = book()
    b.fun(I, 1, I, M)
    local g = games(b)
    ok(games(b) == g)
    b.fun(I, 2, I, M)
    ok(games(b) ~= g); eq(#games(b), 2)
  end)

  it("the view lists the counted S and P entries in the order of the store", function()
    local b = book()
    local s = b.stand(I, M, gid(1), { I, M })
    local p1 = b.add(I, "P", { f = M, c = 500, how = "hand" })
    local p2 = b.add(I, "P", { f = M, c = 700, how = "trade" })
    b.deny(I, p2)
    local v = View.of(b.l)
    eq(#v.stands, 1); ok(v.stands[1] == s); eq(#v.pays, 1); ok(v.pays[1] == p1)
  end)
end)

describe("ledger stats: cost", function()
  -- A store stand-in of 10 authors x 5000 R (a tenth of them staked, with the loser's own D):
  -- the board must come well inside one frame budget of a lazy, throttled UI rebuild.
  it("the board over 5000 x 10 results stays under its bound", function()
    local entries, names = {}, {}
    for a = 1, 10 do names[a] = "Играч Номеров" .. a end
    for a = 1, 10 do
      for n = 1, 5000 do
        local z = names[a % 10 + 1]
        local g = names[a] .. "#1/" .. n
        local at = NOW - 40 * DAY + a * 5000 + n
        local staked = n % 10 == 0
        entries[#entries + 1] = { i = names[a] .. ":" .. n, k = "R", at = at, gid = g, g = n % 3 == 0 and "deathroll" or "ttt",
          n = { names[a], z }, w = { 1 }, l = { 2 }, sk = staked and 1000 or nil }
        if staked then
          entries[#entries + 1] = { i = z .. ":" .. (100000 + n), k = "D", at = at, gid = g, g = "ttt", f = z, t = names[a], c = 1000, why = "lost" }
        end
      end
    end
    local L = { rev = 1 }
    function L:each(fn) for _, e in ipairs(entries) do fn(e) end end
    function L:denied() return false end
    local t0 = os.clock()
    local g = Stats.games(L)
    local d = Stats.board(L, { period = "all", now = NOW })
    Stats.board(L, { period = "month", now = NOW, game = "ttt" })
    Stats.board(L, { period = "week", now = NOW })
    Stats.versus(L, names[1], { period = "all", now = NOW })
    local spent = os.clock() - t0
    eq(#g, 50000); eq(#d.rows, 10); eq(d.rows[1].games, 10000)
    ok(spent < 1.5, "board over 50000 results took " .. spent .. " s")
  end)

  -- One gid flooded: the board and the history are linear in the bodies of a gid.
  local function standIn(entries)
    local L = { rev = 1, epoch = function() return NOW end }
    function L:each(fn) for _, e in ipairs(entries) do fn(e) end end
    function L:denied() return false end
    return L
  end
  local function spend(L)
    local t0 = os.clock()
    local g = Stats.games(L)
    Stats.board(L, { period = "all", now = NOW }); Stats.board(L, { period = "week", now = NOW, game = "ttt" })
    ns.LedgerHistory.lines(L); ns.LedgerHistory.lines(L, M)
    return g, os.clock() - t0
  end

  it("one author's 4500 distinct results at one gid stay under the bound", function()
    local entries, F = {}, "Фалшив Играч"
    for n = 1, 4500 do
      entries[n] = { i = F .. ":" .. n, k = "R", at = NOW + n, gid = "Маса#1/1", g = "ttt",
        n = { F, M, "А", "Б", "В", "Г", "Д", "Е" }, w = { 1, 3, 4, 5, 6, 7, 8 }, l = { 2, (n % 7) + 3, n } }
    end
    local g, spent = spend(standIn(entries))
    eq(#g, 4500)
    ok(spent < 0.3, "4500 results at one gid took " .. spent .. " s")
  end)

  it("two authors with 4000 S each at one gid raise nothing and stay under the bound", function()
    local entries, G = {}, "Маса#2/1"
    for _, who in ipairs({ I, M }) do
      for n = 1, 4000 do
        entries[#entries + 1] = { i = who .. ":" .. n, k = "S", at = NOW + n, gid = G, g = "holdem", f = who, c = 100 * n,
          sk = 100, n = { I, M }, w = {}, l = {} }
      end
    end
    entries[#entries + 1] = { i = I .. ":9001", k = "R", at = NOW, gid = G, g = "holdem", n = { I, M }, w = { 1 }, l = { 2 } }
    local g, spent = spend(standIn(entries))
    eq(#g, 8001)
    ok(spent < 0.3, "8000 S at one gid took " .. spent .. " s")
  end)
end)
