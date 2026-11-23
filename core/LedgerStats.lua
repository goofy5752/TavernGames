local _, ns = ...

-- „Класация“ from the ledger view, never stored. The trust rule (F4 Decision T, J4): an R
-- or S is its author's claim and counts per player. Fun R (no sk): for its names when an
-- author is one of them, never at a gid with a debt. Staked R: a loss on the loser's word
-- (f of a confirmed debt of the gid, or it wrote the R), a win on a debtor's (t of one), a
-- draw only when an author is f or t of one. S (Холдем): for its f when f and an author are
-- each f or t of one; won or lost by the sign of f's confirmed copper there. A name counts
-- once per gid: same bodies of a gid are one record (`by`: authors); across its records a
-- win or loss beats a draw, else the oldest keeps it. Record {gid, g, at, by, e (the oldest
-- body), sk, why, cash, state, counts[name] = "win"|"loss"|"draw"}, lean (J3: Stats.dress
-- names on demand); state "fun", "claim" (no author named, or nothing counts), "contested",
-- "pending" (a debt is, or none yet), "confirmed". Stats.games is cached per L.rev; board
-- and versus are one pass over it, asked at most once per 2 s while shown (J3).
local Ledger, View = ns.Ledger, ns.LedgerView
local byteLess, floor, abs, max = ns.Util.byteLess, math.floor, math.abs, math.max

local Stats = { PERIOD = { week = 604800, month = 2592000 }, KING_GAMES = 5, RUN = 3 }
ns.LedgerStats = Stats

local cache, NONE, RANK = setmetatable({}, { __mode = "k" }), {}, { win = 2, loss = 2, draw = 1 }

local function str(v) return type(v) == "string" end
local function list(v) return type(v) == "table" and v or NONE end
-- A body of the saved variables may hold anything: only one with a number at is a record.
local function timed(e) return type(e.at) == "number" and e.at == e.at end
local function has(l, x) for _, y in ipairs(l) do if y == x then return true end end return false end
local function sameList(p, q)
  p, q = list(p), list(q)
  for j = 1, max(#p, #q) do if p[j] ~= q[j] then return false end end
  return true
end
-- Do bodies p and q tell one game (rule 5's fields, and an S's own)?
local function same(p, q)
  return p.k == q.k and p.g == q.g and p.sk == q.sk and p.why == q.why and p.f == q.f and p.c == q.c
    and sameList(p.n, q.n) and sameList(p.w, q.w) and sameList(p.l, q.l)
end
-- Bodies oldest first: at, author bytes, id bytes, hash; records: at, gid bytes, then their oldest body.
local function older(p, q)
  if p.at ~= q.at then return p.at < q.at end
  local a, b = Ledger.author(p.i), Ledger.author(q.i)
  if a ~= b then return byteLess(a, b) end
  if p.i ~= q.i then return byteLess(p.i, q.i) end
  return byteLess(p.h or "", q.h or "")
end
local function before(p, q)
  if p.at ~= q.at then return p.at < q.at end
  if p.gid ~= q.gid then return byteLess(p.gid, q.gid) end
  return older(p.e, q.e)
end
-- Rows sorted by keys: "name" ascending by bytes, "-name" descending, "|name|" by |x| descending.
local function order(rows, ...)
  local keys = {}
  for j, k in ipairs({ ... }) do keys[j] = { k:match("^[-|]?([^|]+)"), k:sub(1, 1) } end
  table.sort(rows, function(p, q)
    for _, k in ipairs(keys) do
      local x, y, how = p[k[1]], q[k[1]], k[2]
      if how == "|" then x, y = abs(x), abs(y) end
      if x ~= y then if how == "-" or how == "|" then return x > y end return byteLess(x, y) end
    end
    return false
  end)
  return rows
end

-- Per gid of a debt: role[name] (1: f, 2: t, 3: both, of a confirmed debt), cop[name] (its
-- signed confirmed copper there), and pending/contested = true when a debt there is.
local function index(v)
  local by = {}
  local function mark(r, name, bit) local o = r[name] or 0; if o % (bit * 2) < bit then r[name] = o + bit end end
  for _, d in ipairs(v.debts) do
    local x = by[d.gid] or { role = {}, cop = {} }
    by[d.gid], x[d.status] = x, true
    if d.status == "confirmed" then
      mark(x.role, d.f, 1); mark(x.role, d.t, 2)
      x.cop[d.f], x.cop[d.t] = (x.cop[d.f] or 0) - d.c, (x.cop[d.t] or 0) + d.c
    end
  end
  return by
end

-- Rules 2-4 for record rec at a gid with debt index x (nil: no debt there).
local function judge(rec, x)
  local e, counts, role, n = rec.e, rec.counts, x and x.role or NONE, list(rec.e.n)
  local seated, party = false, false
  for _, a in ipairs(rec.by) do seated, party = seated or has(n, a), party or role[a] ~= nil end
  local fun = e.sk == nil and not rec.cash
  if fun then
    rec.state = (seated and not x) and "fun" or "claim"
    if rec.state == "claim" then return end
  elseif rec.cash and role[e.f] and party then
    local c = x.cop[e.f] or 0
    counts[e.f] = c > 0 and "win" or c < 0 and "loss" or "draw"
  end
  local w, l = list(e.w), list(e.l)
  for i, name in ipairs(rec.cash and NONE or n) do
    if str(name) and not counts[name] then
      local r = role[name] or 0
      if has(w, i) then counts[name] = (fun or r >= 2) and "win" or nil
      elseif has(l, i) then counts[name] = (fun or r % 2 == 1 or has(rec.by, name)) and "loss" or nil
      elseif fun or party then counts[name] = "draw" end
    end
  end
  if fun then return end
  local any = next(counts) ~= nil
  rec.state = not seated and "claim" or x and x.contested and "contested"
    or ((x and x.pending) or (not x and any)) and "pending" or any and "confirmed" or "claim"
end

-- The records of the bodies es (Rs and Ss, oldest first) of one gid, appended to out; then
-- rule 5 across them: a name stays in the first record of its highest rank.
local function group(out, id, es, x)
  local recs, best = {}, {}
  for _, e in ipairs(es) do
    local a, rec = Ledger.author(e.i), nil
    for _, r in ipairs(recs) do if same(r.e, e) then rec = r; break end end
    if rec and not has(rec.by, a) then rec.by[#rec.by + 1] = a end
    if not rec and timed(e) then
      recs[#recs + 1] = { gid = id, g = e.g, at = e.at, by = { a }, e = e, sk = e.sk, why = e.why, cash = e.k == "S" or nil, counts = {} }
    end
  end
  for _, rec in ipairs(recs) do judge(rec, x); out[#out + 1] = rec end
  for _, rec in ipairs(#recs > 1 and recs or NONE) do
    for name, how in pairs(rec.counts) do
      local b = best[name]
      if not b then best[name] = rec
      elseif RANK[how] > RANK[b.counts[name]] then b.counts[name], best[name] = nil, rec
      else rec.counts[name] = nil end
    end
  end
end

local function build(v)
  local debts, out, stands = index(v), {}, {}
  for _, e in ipairs(v.stands) do if timed(e) then stands[e.gid] = stands[e.gid] or {}; table.insert(stands[e.gid], e) end end
  for id, rs in pairs(v.results) do
    local es, ss = rs, stands[id]
    if ss or #rs > 1 then -- a copy: the view's own list stays as it is
      es = { unpack(ss or NONE) }
      for _, e in ipairs(rs) do if timed(e) then es[#es + 1] = e end end
      table.sort(es, older)
    end
    group(out, id, es, debts[id])
  end
  for id, ss in pairs(stands) do if not v.results[id] then table.sort(ss, older); group(out, id, ss, debts[id]) end end
  table.sort(out, before)
  return out
end

-- The records of store L, oldest first.
function Stats.games(L)
  local c = cache[L]
  if not c or c.rev ~= L.rev then c = { rev = L.rev, games = build(View.of(L)) }; cache[L] = c end
  return c.games
end

-- The names of rec's body (strings, by seat) and the sets of those it says won and lost;
-- an S names its f alone, won or lost as it counts.
function Stats.dress(rec)
  local e, names, win, lose = rec.e, {}, {}, {}
  if rec.cash then
    local how = rec.counts[e.f]
    return { e.f }, how == "win" and { [e.f] = true } or win, how == "loss" and { [e.f] = true } or lose
  end
  local n = list(e.n)
  for _, x in ipairs(n) do if str(x) then names[#names + 1] = x end end
  for _, s in ipairs(list(e.w)) do if str(n[s]) then win[n[s]] = true end end
  for _, s in ipairs(list(e.l)) do if str(n[s]) then lose[n[s]] = true end end
  return names, win, lose
end
-- Does rec's body name `name`?
function Stats.named(rec, name) return rec.cash and rec.e.f == name or not rec.cash and has(list(rec.e.n), name) end

-- The start of opts' period (nil: all time); is x (a record or a debt) in scope; fn(d) per confirmed debt in scope.
local function scope(L, opts)
  local p = Stats.PERIOD[opts.period]
  return p and (opts.now or L.epoch()) - p, opts.game
end
local function inside(x, from, game) return (not from or x.at >= from) and (not game or x.g == game) end
local function confirmed(L, from, game, fn)
  for _, d in ipairs(View.of(L).debts) do if d.status == "confirmed" and inside(d, from, game) then fn(d) end end
end

-- The board rows in scope (net, wins, games desc, name bytes): every name with a counted
-- game or a confirmed net; fav (none under a game filter); honour: a win run first.
local function tally(L, from, game)
  local t, rows = {}, {}
  local function row(name) t[name] = t[name] or { games = 0, wins = 0, net = 0, run = 0, bw = 0, bl = 0, per = {} }; return t[name] end
  for _, rec in ipairs(Stats.games(L)) do
    for name, how in pairs(inside(rec, from, game) and rec.counts or NONE) do
      local r = row(name)
      r.games, r.wins = r.games + 1, r.wins + (how == "win" and 1 or 0)
      if how == r.kind then r.run = r.run + 1 else r.kind, r.run = how, 1 end
      if how == "win" then r.bw = max(r.bw, r.run) elseif how == "loss" then r.bl = max(r.bl, r.run) end
      if str(rec.g) then r.per[rec.g] = (r.per[rec.g] or 0) + 1 end
    end
  end
  confirmed(L, from, game, function(d) row(d.f).net, row(d.t).net = row(d.f).net - d.c, row(d.t).net + d.c end)
  for name, r in pairs(t) do
    local out = { name = name, games = r.games, wins = r.wins, net = r.net }
    if r.games > 0 then out.pct = floor(r.wins * 100 / r.games + 0.5) end
    for g, k in pairs(game and NONE or r.per) do
      local best = out.fav and r.per[out.fav]
      if not best or k > best or (k == best and byteLess(g, out.fav)) then out.fav = g end
    end
    if r.bw >= Stats.RUN then out.honour = { kind = "wins", n = r.bw }
    elseif r.bl >= Stats.RUN then out.honour = { kind = "losses", n = r.bl } end
    if r.games > 0 or r.net ~= 0 then rows[#rows + 1] = out end
  end
  return order(rows, "-net", "-wins", "-games", "name")
end

-- Rule 6: the highest positive net; else the most wins among players with KING_GAMES games
-- (in board order, so the first row of the most wins).
local function king(rows)
  if rows[1] and rows[1].net > 0 then return rows[1].name end
  local best
  for _, r in ipairs(rows) do if r.games >= Stats.KING_GAMES and r.wins > (best and best.wins or 0) then best = r end end
  return best and best.name
end

-- opts = {period = "week"|"month"|"all", game = id|nil, now = epoch} -> {rows, king, top}.
function Stats.board(L, opts)
  local from, game = scope(L, opts)
  local rows, top = tally(L, from, game), 0
  for _, r in ipairs(rows) do top = max(top, abs(r.net)) end
  return { rows = rows, king = king(game and tally(L, from, nil) or rows), top = top }
end

-- {{name, won, lost, net}}: per opponent of `name`, the counted games on opposite sides
-- and the confirmed copper between them (> 0: name won it); |net|, games, name bytes.
function Stats.versus(L, name, opts)
  local from, game = scope(L, opts)
  local by, out = {}, {}
  local function opp(o) if not by[o] then by[o] = { name = o, won = 0, lost = 0, net = 0, n = 0 }; out[#out + 1] = by[o] end return by[o] end
  for _, rec in ipairs(Stats.games(L)) do
    local me = rec.counts[name]
    for o, how in pairs((me == "win" or me == "loss") and inside(rec, from, game) and rec.counts or NONE) do
      if how ~= me and how ~= "draw" then
        local x = opp(o)
        x.won, x.lost, x.n = x.won + (me == "win" and 1 or 0), x.lost + (me == "loss" and 1 or 0), x.n + 1
      end
    end
  end
  confirmed(L, from, game, function(d)
    if d.t == name then opp(d.f).net = opp(d.f).net + d.c elseif d.f == name then opp(d.t).net = opp(d.t).net - d.c end
  end)
  for j = #out, 1, -1 do if out[j].n == 0 and out[j].net == 0 then table.remove(out, j) end end
  order(out, "|net|", "-n", "name")
  for _, x in ipairs(out) do x.n = nil end
  return out
end

return Stats
