local _, ns = ...

-- „Класация“ from the ledger view, never stored. The trust rule (F4 Decision T, J4): an R
-- or S is its author's claim and counts per player. Fun R (no sk): for its names when an
-- author is one of them. Staked R: a loss on the loser's word (f of a confirmed debt of
-- the gid, or it wrote the R), a win on a debtor's (t of one), a draw only when an author
-- is a party there. S (Холдем): for its f when f is f or t of a confirmed debt there and
-- an author is a party; won or lost by the sign of f's confirmed copper there. A party of
-- a gid is f or t of a confirmed debt of it that t has claimed too (its own D): both sides
-- spoke, as every honest staked game does, so a self-confirmed debt alone makes none.
-- A name counts once per gid: bodies of a gid with one content (a hash key) are one record
-- (`by`: authors); across its records a debt-backed win or loss (staked R or S) beats a fun
-- one, which beats a draw; on a tie a record with a seated or party author beats one
-- without, then the older keeps it. A fun game is its opener's word (final review I2): a gid
-- is "<opener>#<epoch>/<q>", and where a fun record by the opener names it, no other fun
-- record of that gid counts for anybody (after a host change there is none: the rule above).
-- A record's at (and its e) is its oldest body by a
-- seated or party author, else its oldest body: an outsider's copy moves no game in time.
-- Record {gid, g, at, by, e, sk, why, cash, state, counts[name] = "win"|"loss"|"draw"},
-- lean (J3: Stats.dress names on demand); state "fun", "claim" (no author named and
-- nothing counts, or nothing counts at all), "contested", "pending" (a debt is, or none
-- yet), "confirmed". Stats.games is cached per L.rev; the board and versus
-- (core/LedgerBoard.lua) are one pass over it, asked at most once per 2 s while shown (J3).
local Ledger, View = ns.Ledger, ns.LedgerView
local byteLess, concat = ns.Util.byteLess, table.concat

local Stats = { PERIOD = { week = 604800, month = 2592000 }, KING_GAMES = 5, RUN = 3 }
ns.LedgerStats = Stats

local cache, NONE = setmetatable({}, { __mode = "k" }), {}

local function str(v) return type(v) == "string" end
local function list(v) return type(v) == "table" and v or NONE end
-- A body of the saved variables may hold anything: only one with a number at is a record.
local function timed(e) return type(e.at) == "number" and e.at == e.at end
local function has(l, x) for _, y in ipairs(l) do if y == x then return true end end return false end
local function fun(rec) return rec.sk == nil and not rec.cash end

-- The content key of body e (rule 5's fields, and an S's own): a string is length-prefixed,
-- another value typed and closed by "|", a list counted, so two keys are equal only when the
-- contents are (any table in a seat reads the same).
local function key(e)
  local out = {}
  local function put(v)
    local t = type(v)
    if t == "string" then out[#out + 1] = #v .. ":" .. v
    elseif t == "number" or t == "boolean" then out[#out + 1] = t:sub(1, 1) .. tostring(v) .. "|"
    else out[#out + 1] = t == "nil" and "-|" or "?|" end
  end
  for _, f in ipairs({ "k", "g", "sk", "why", "f", "c" }) do put(e[f]) end
  for _, f in ipairs({ "n", "w", "l" }) do
    local l = list(e[f])
    out[#out + 1] = "#" .. #l .. "|"
    for j = 1, #l do put(l[j]) end
  end
  return concat(out)
end

-- Bodies oldest first: at, author bytes, id bytes, hash; records: at, gid bytes, then their e.
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

-- Per gid of a debt: role[name] (1: f, 2: t, 3: both, of a confirmed debt), cop[name] (its
-- signed confirmed copper there), party[name] (f or t of a confirmed debt t claimed too),
-- and pending/contested = true when a debt there is.
local function index(v)
  local by = {}
  local function mark(r, name, bit) local o = r[name] or 0; if o % (bit * 2) < bit then r[name] = o + bit end end
  for _, d in ipairs(v.debts) do
    local x = by[d.gid] or { role = {}, cop = {}, party = {} }
    by[d.gid], x[d.status] = x, true
    if d.status == "confirmed" then
      mark(x.role, d.f, 1); mark(x.role, d.t, 2)
      x.cop[d.f], x.cop[d.t] = (x.cop[d.f] or 0) - d.c, (x.cop[d.t] or 0) + d.c
      for _, id in ipairs(d.ids) do if Ledger.author(id) == d.t then x.party[d.f], x.party[d.t] = true, true end end
    end
  end
  return by
end

-- Rules 2-4 for record rec at a gid with debt index x (nil: no debt there) -> is an author seated.
local function judge(rec, x)
  local e, counts, role, party, n = rec.e, rec.counts, x and x.role or NONE, x and x.party or NONE, list(rec.e.n)
  local seated, sides = false, false
  for _, a in ipairs(rec.by) do seated, sides = seated or has(n, a), sides or party[a] == true end
  local free = fun(rec)
  if free and not seated then return false end
  if rec.cash and role[e.f] and sides then
    local c = x.cop[e.f] or 0
    counts[e.f] = c > 0 and "win" or c < 0 and "loss" or "draw"
  end
  local w, l = list(e.w), list(e.l)
  for i, name in ipairs(rec.cash and NONE or n) do
    if str(name) and not counts[name] then
      local r = role[name] or 0
      if has(w, i) then counts[name] = (free or r >= 2) and "win" or nil
      elseif has(l, i) then counts[name] = (free or r % 2 == 1 or has(rec.by, name)) and "loss" or nil
      elseif free or sides then counts[name] = "draw" end
    end
  end
  return seated
end

-- The state of rec once rule 5 has run (seated: an author is one of its names).
local function label(rec, x, seated)
  if fun(rec) then return seated and "fun" or "claim" end
  local any = next(rec.counts) ~= nil
  if not seated and not any then return "claim" end
  return x and x.contested and "contested" or ((x and x.pending) or (not x and any)) and "pending"
    or any and "confirmed" or "claim"
end

-- The records of the bodies es (Rs and Ss, oldest first) of one gid, appended to out; then
-- rule 5 across them: a name stays in the record of its highest weight, the first of it.
local function group(out, id, es, x)
  local recs, byKey, backed, seated, best, party = {}, {}, {}, {}, {}, x and x.party or NONE
  local opener, own, owned = str(id) and id:match("^(.*)#%d+/%d+$"), {}, false
  for _, e in ipairs(es) do
    if timed(e) then
      local k, a = #es > 1 and key(e) or "", Ledger.author(e.i)
      local rec = byKey[k]
      if not rec then
        rec = { gid = id, g = e.g, at = e.at, by = {}, e = e, sk = e.sk, why = e.why, cash = e.k == "S" or nil, counts = {} }
        byKey[k], recs[#recs + 1] = rec, rec
      end
      if not has(rec.by, a) then rec.by[#rec.by + 1] = a end
      if not backed[rec] and (has(list(e.n), a) or party[a]) then backed[rec], rec.e, rec.at = true, e, e.at end
      if a == opener and fun(rec) and has(list(e.n), a) then own[rec], owned = true, true end
    end
  end
  for _, rec in ipairs(recs) do
    seated[rec] = judge(rec, x)
    if owned and fun(rec) and not own[rec] then rec.counts, seated[rec] = {}, false end -- the opener's word stands
  end
  local function weight(rec, how)
    return (how == "draw" and 1 or fun(rec) and 2 or 3) * 2 + (backed[rec] and 1 or 0)
  end
  if #recs > 1 then table.sort(recs, before) end
  for _, rec in ipairs(#recs > 1 and recs or NONE) do
    for name, how in pairs(rec.counts) do
      local b = best[name]
      if not b then best[name] = rec
      elseif weight(rec, how) > weight(b, b.counts[name]) then b.counts[name], best[name] = nil, rec
      else rec.counts[name] = nil end
    end
  end
  for _, rec in ipairs(recs) do rec.state = label(rec, x, seated[rec]); out[#out + 1] = rec end
end

local function build(v)
  local debts, out, stands = index(v), {}, {}
  for _, e in ipairs(v.stands) do if timed(e) then stands[e.gid] = stands[e.gid] or {}; table.insert(stands[e.gid], e) end end
  for id, rs in pairs(v.results) do
    local es, ss = rs, stands[id]
    if ss or #rs > 1 then -- a copy: the view's own list stays as it is
      es = {}
      for _, e in ipairs(ss or NONE) do es[#es + 1] = e end
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

return Stats
