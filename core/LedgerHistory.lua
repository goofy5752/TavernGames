local _, ns = ...

-- „История“ from the ledger, never stored: every game record of LedgerStats (counted or
-- not), every payment (P) and every denied R, S or P, newest first. It shows what my
-- client knows and nothing it cannot back: a record keeps its state and its authors, so
-- the tab can say whose word a result is (F4 Decision T). A stub has no body, so a game
-- that left the store is not here; payments and debts never leave. Lines are lean
-- (J3): a game line holds the record, a pay or denied line the entry itself; the names
-- are dressed when a row first comes on screen (Stats.dress). With `name`: only lines
-- that name it. One entry is cached: the last (store, rev, name) asked.
-- Line: {kind = "game", at, rec} | {kind = "pay", at, f, t (its author), c, how, rl} |
-- {kind = "denied", at, entry}. Order: at desc, game < pay < denied, then id bytes.
local Ledger, View = ns.Ledger, ns.LedgerView
local byteLess = ns.Util.byteLess

local History = {}
ns.LedgerHistory = History

local RANK = { game = 1, pay = 2, denied = 3 }
local DENIED = { R = true, S = true, P = true }
local cache = {}

local function at(e) return type(e.at) == "number" and e.at == e.at and e.at or 0 end
local function has(l, x)
  if type(l) ~= "table" then return false end
  for _, y in ipairs(l) do if y == x then return true end end
  return false
end
-- Does a denied entry name `name` (its author, its f, a name of its n)?
local function names(e, name)
  return Ledger.author(e.i) == name or e.f == name or has(e.n, name)
end

local function before(p, q)
  if p.at ~= q.at then return p.at > q.at end
  if p.kind ~= q.kind then return RANK[p.kind] < RANK[q.kind] end
  return byteLess(p.id, q.id)
end

local function build(L, name)
  local out, Stats = {}, ns.LedgerStats
  local function put(line, id) line.id = id; out[#out + 1] = line end
  for _, rec in ipairs(Stats.games(L)) do
    if not name or Stats.named(rec, name) then put({ kind = "game", at = rec.at, rec = rec }, rec.e.i) end
  end
  local v = View.of(L)
  for _, e in ipairs(v.pays) do
    if not name or e.f == name or Ledger.author(e.i) == name then
      put({ kind = "pay", at = at(e), f = e.f, t = Ledger.author(e.i), c = e.c, how = e.how, rl = e.rl }, e.i)
    end
  end
  for _, e in ipairs(View.denied(v)) do
    if DENIED[e.k] and type(e.i) == "string" and (not name or names(e, name)) then
      put({ kind = "denied", at = at(e), entry = e }, e.i)
    end
  end
  table.sort(out, before)
  for _, line in ipairs(out) do line.id = nil end
  return out
end

-- The lines of store L (newest first), for `name` only when given.
function History.lines(L, name)
  local c = cache
  if c.L ~= L or c.rev ~= L.rev or c.name ~= name then
    cache = { L = L, rev = L.rev, name = name, lines = build(L, name) }
    c = cache
  end
  return c.lines
end

return History
