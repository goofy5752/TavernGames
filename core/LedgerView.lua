local _, ns = ...

-- Debts and balances derived from the ledger store (core/LedgerStore.lua), never
-- stored. A logical debt is the key "gid|f|t"; its claims are its D entries that
-- are not denied. f's word about it is its own D (attesting that D's c), a C
-- (attesting the claim it names) or an N; the newest by n decides (on a tie an N,
-- then the smaller amount): "confirmed", "contested", or "pending" without one. A C
-- or N names one exact claim, by its id r and its hash dh, and counts only for
-- that body and only when its author is the debt's f: a twin, a copy or a moved
-- claim under the same id has no word of f's, and when two bodies of one id share
-- that h (a collision) it counts for none. The amount is f's newest
-- attestation, else the smallest claim; clash: f attested an amount and a
-- creditor's claim names another. Only confirmed debts enter a balance:
-- gross(f, t) = max(0, confirmed f->t - the c of t's P with that f),
-- net(a, b) = gross(a, b) - gross(b, a); a P beyond the gross stays as credit of
-- that pair. A row's open part is what is left of a confirmed debt once the paid
-- and netted copper of its pair has cleared that pair's debts oldest first.
-- The R entries are indexed by gid (View.results).
-- View.of(L) is cached per store until L.rev changes; a rebuild is linear in the
-- whole ledger (tens of ms on a large one), so callers ask for it once per batch
-- of entries (a LEV) or behind a short debounce, never per entry or per frame.
local Ledger, C = ns.Ledger, ns.Const
local byteLess, max, min, floor = ns.Util.byteLess, math.max, math.min, math.floor

local View = {}
ns.LedgerView = View

local cache = setmetatable({}, { __mode = "k" })
local COPPER_MAX = 99999999999

local function cell(t, a) t[a] = t[a] or {}; return t[a] end
local function get(t, a, b) return t[a] and t[a][b] or 0 end
local function add(t, a, b, c) local r = cell(t, a); r[b] = (r[b] or 0) + c end
local function str(v) return type(v) == "string" end
-- A whole copper amount (the store's own saved variables could hold anything).
local function copper(v) return type(v) == "number" and v >= 1 and v <= COPPER_MAX and v == floor(v) end
local function claimOk(e, a)
  return str(e.gid) and str(e.f) and str(e.t) and e.f ~= e.t and (a == e.f or a == e.t)
    and copper(e.c) and type(e.at) == "number"
end

-- Is word (n, kind, c) newer than w?
local function newer(w, n, kind, c)
  if not w then return true end
  if n ~= w.n then return n > w.n end
  if (kind == "N") ~= (w.kind == "N") then return kind == "N" end
  return (c or 0) < (w.c or 0)
end
-- f's entry `id` (number n) about debt d: kind "D", "C" (both attest c) or "N".
local function say(d, n, kind, c, id)
  if newer(d.word, n, kind, c) then d.word = { n = n, kind = kind, c = c, id = id } end
  if kind ~= "N" and newer(d.attest, n, kind, c) then d.attest = { n = n, kind = kind, c = c } end
end

-- The C or N `e` of author a, number n, over the claim bodies `vers` ({debt, claim})
-- under its r: it counts for the one body whose h is its dh, when a is that debt's f.
-- Two bodies with that h under one id are a collision (the creditor made both): none counts.
local function word(e, a, n, vers)
  local hit
  for _, x in ipairs(vers or {}) do
    if x[2].h == e.dh then
      if hit then return end
      hit = x
    end
  end
  if hit and hit[1].f == a then say(hit[1], n, e.k, e.k == "C" and hit[2].c or nil, e.i) end
end

-- The status, amount and oldest claim of debt d, its working fields dropped.
local function settle(d)
  local first, low = nil, nil
  for _, e in ipairs(d.claims) do
    if not first or e.at < first.at then first = e end
    low = min(low or e.c, e.c)
  end
  d.at, d.g, d.why = first.at, first.g, first.why
  d.status = not d.word and "pending" or d.word.kind == "N" and "contested" or "confirmed"
  d.said, d.c, d.clash = d.word and d.word.id, d.attest and d.attest.c or low, false
  if d.attest then
    for _, e in ipairs(d.claims) do if Ledger.author(e.i) == d.t and e.c ~= d.c then d.clash = true end end
  end
  d.claims, d.word, d.attest = nil, nil, nil
end

local function build(L)
  local v = { rev = L.rev, debts = {}, sum = {}, pay = {}, peers = {}, denials = {}, rows = {}, results = {} }
  local byKey, byId, words = {}, {}, {}
  L:each(function(e)
    if e.un then return end -- an own entry put to me after a crash (core/LedgerNet.lua) counts for nothing
    if L:denied(e) then v.denials[#v.denials + 1] = e; return end
    local a, n = Ledger.author(e.i)
    if e.k == "D" and claimOk(e, a) then
      local key = e.gid .. "|" .. e.f .. "|" .. e.t
      local d = byKey[key]
      if not d then
        d = { key = key, gid = e.gid, f = e.f, t = e.t, ids = {}, claims = {} }
        byKey[key], v.debts[#v.debts + 1] = d, d
      end
      d.claims[#d.claims + 1] = e
      -- the bodies of one id come in one run, so a repeated id is the last one
      if d.ids[#d.ids] ~= e.i then d.ids[#d.ids + 1] = e.i end
      byId[e.i] = byId[e.i] or {}
      byId[e.i][#byId[e.i] + 1] = { d, e }
      if a == e.f then say(d, n, "D", e.c, e.i) end
    elseif (e.k == "C" or e.k == "N") and str(e.r) and str(e.dh) then
      words[#words + 1] = { e, a, n }
    elseif e.k == "R" and str(e.gid) then
      local r = cell(v.results, e.gid)
      r[#r + 1] = e
    elseif e.k == "P" and str(e.f) and copper(e.c) then
      add(v.pay, a, e.f, e.c)
      cell(v.peers, a)[e.f], cell(v.peers, e.f)[a] = true, true
    end
  end)
  for _, w in ipairs(words) do word(w[1], w[2], w[3], byId[w[1].r]) end
  for _, d in ipairs(v.debts) do
    settle(d)
    if d.status == "confirmed" then
      add(v.sum, d.f, d.t, d.c)
      cell(v.peers, d.f)[d.t], cell(v.peers, d.t)[d.f] = true, true
    end
  end
  table.sort(v.debts, function(p, q)
    if p.at ~= q.at then return p.at < q.at end
    return byteLess(p.key, q.key)
  end)
  -- Rows: per pair, the copper paid or netted (sum - what is still owed) clears the oldest first.
  local clear = {}
  for _, d in ipairs(v.debts) do
    local open = d.c
    if d.status == "confirmed" then
      local left = cell(clear, d.f)[d.t] or get(v.sum, d.f, d.t) - max(0, View.net(v, d.f, d.t))
      local take = min(d.c, left)
      open, clear[d.f][d.t] = d.c - take, left - take
    end
    v.rows[#v.rows + 1] = { debt = d, open = open }
  end
  return v
end

-- The view of store L, rebuilt only when L.rev changed.
function View.of(L)
  local v = cache[L]
  if not v or v.rev ~= L.rev then v = build(L); cache[L] = v end
  return v
end

-- What f owes t on its confirmed debts, less what t recorded as paid by f, never below 0.
function View.gross(v, f, t) return max(0, get(v.sum, f, t) - get(v.pay, t, f)) end
-- Positive: a owes b.
function View.net(v, a, b) return View.gross(v, a, b) - View.gross(v, b, a) end
-- The copper t recorded as paid by f (its P entries that are not denied).
function View.paid(v, f, t) return get(v.pay, t, f) end

-- {{name, net}} of my pairs with a net (> 0: I owe): largest absolute first, then name bytes.
function View.accounts(v, me)
  local out = {}
  for b in pairs(v.peers[me] or {}) do
    local n = View.net(v, me, b)
    if n ~= 0 then out[#out + 1] = { name = b, net = n } end
  end
  table.sort(out, function(p, q)
    local x, y = math.abs(p.net), math.abs(q.net)
    if x ~= y then return x > y end
    return byteLess(p.name, q.name)
  end)
  return out
end

-- The pending debts I am the debtor of, oldest first, at most LEDGER_CLAIMS_OPEN per creditor.
function View.claims(v, me)
  local out, per = {}, {}
  for _, d in ipairs(v.debts) do
    if d.f == me and d.status == "pending" and (per[d.t] or 0) < C.LEDGER_CLAIMS_OPEN then
      per[d.t], out[#out + 1] = (per[d.t] or 0) + 1, d
    end
  end
  return out
end

-- {{debt, open}} in the order of the debts; a pending or contested debt is open in full.
function View.rows(v) return v.rows end

-- {open, count, top, topSum}: the open copper and rows of the confirmed debts, and the
-- name owing the most (the sum of its positive nets; ties by name bytes).
function View.totals(v)
  local out = { open = 0, count = 0, topSum = 0 }
  for _, r in ipairs(v.rows) do
    if r.debt.status == "confirmed" and r.open > 0 then out.open, out.count = out.open + r.open, out.count + 1 end
  end
  for a, peers in pairs(v.peers) do
    local s = 0
    for b in pairs(peers) do s = s + max(0, View.net(v, a, b)) end
    if s > 0 and (s > out.topSum or (s == out.topSum and byteLess(a, out.top))) then out.top, out.topSum = a, s end
  end
  return out
end

-- The R entries of gid that are neither denied nor put to me, in the order of L:each.
function View.results(v, gid) return v.results[gid] or {} end

-- The denied entries, in the order of L:each.
function View.denied(v) return v.denials end

return View
