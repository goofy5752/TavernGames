local _, ns = ...

-- Stubs (F4, Decision R as ruled in J1 a). An author with more than LEDGER_AUTHOR_MAX -
-- LEDGER_AUTHOR_ROOM R+S bodies has its oldest (by at, then number) stubbed down to that
-- count: the body leaves, store.st[author]["<n>.<h>"] = true stays (saved). Age stubs nothing.
-- A stub counts as held wherever the sync looks, as its body did (core/LedgerHash.lua: x,
-- n, the vector), so a pruned store, a full one and an F1–F3 one agree and exchange
-- nothing. Its body offered again is a dup; it counts toward the four bodies of its id; my
-- counter steps over it (Store:add, Store:make). No entry: never in the view. Never
-- stubbed: a D, C, N, P or X; an id with twins; an un body; a denied one (the denied-first
-- rule of a fifth twin, „отречено“); an R or S of a game with a pending debt (StakesClaims
-- reads it). Not in L.rc; L.sn[author][n] = its count (as L.rn). Net:prune: once a session.
local Ledger, C = ns.Ledger, ns.Const
local Store = Ledger.Store
local sort = table.sort

local function hex16(v) return type(v) == "string" and #v == 16 and v:find("^[0-9a-f]+$") ~= nil end
local function named(a) return type(a) == "string" and a ~= "" and #a <= 64 and not a:find("[|,]") end

-- One more stub of (a, n): counted, n is a number of a seen, and the highest stubbed (L.sx; stubs never go).
local function note(L, a, n)
  local sn = L.sn[a] or {}
  L.sn[a], sn[n] = sn, (sn[n] or 0) + 1
  if n > (L.top[a] or 0) then L.top[a] = n end
  if n > (L.sx[a] or 0) then L.sx[a] = n end
end

-- After a load (the bodies filed): the saved stubs, a malformed row or one whose body is held dropped.
function Store:stubLoad()
  local saved, out = self.store.st, {}
  for a, set in pairs(type(saved) == "table" and saved or {}) do
    for it, v in pairs(named(a) and type(set) == "table" and set or {}) do
      local n, h = (type(it) == "string" and it or ""):match("^([1-9]%d*)%.(%x+)$")
      if n and #n <= 9 and hex16(h) and v == true and not self:has(Ledger.id(a, tonumber(n)), h) then
        out[a] = out[a] or {}; out[a][it] = true
        note(self, a, tonumber(n))
      end
    end
  end
  self.store.st = out
  for a in pairs(out) do self.dirty[a] = true; self:advance(a) end -- its x is to be hashed, as after any load
end

-- Do I hold body (a, n) with hash h as a stub?
function Store:stubbed(a, n, h)
  local set = self.store.st[a]
  return set ~= nil and set[n .. "." .. h] == true
end

-- The stubs of author a as {n, h}, in no order.
function Store:stubs(a)
  local out = {}
  for it in pairs(self.store.st[a] or {}) do
    local n, h = it:match("^(%d+)%.(%x+)$")
    out[#out + 1] = { n = tonumber(n), h = h }
  end
  return out
end

-- The highest number of author a held as a stub (0: none); how many stubs of every author.
function Store:stubTop(a) return self.sx[a] or 0 end
function Store:stubCount()
  local count = 0
  for _, sn in pairs(self.sn) do for _, c in pairs(sn) do count = count + c end end
  return count
end

-- Body b becomes a stub -> true | false (not an R or S, put to me, denied by its author, or its
-- id holds another body or a stub). Its "<id>:<h>" stays in x and in the kept list (no Store:stale),
-- and the counted run (L.run) stays: the stub fills its number.
function Store:stub(b)
  if type(b) ~= "table" or not (b.k == "R" or b.k == "S") or b.un or self:denied(b) then return false end
  local a, n = Ledger.author(b.i)
  local s = self.store
  if not (a and s.ev[a] and s.ev[a][n] == b) or (s.tw[a] and s.tw[a][n]) or (self.sn[a] and self.sn[a][n]) then return false end
  self:index(a, n, b, -1)
  s.ev[a][n], s.st[a] = nil, s.st[a] or {}
  s.st[a][n .. "." .. b.h], self.rev = true, self.rev + 1
  note(self, a, n)
  return true
end

-- The gids of every pending debt (its R or S stays a body).
local function pending(L)
  local out = {}
  for _, d in ipairs(ns.LedgerView.of(L).debts) do if d.status == "pending" then out[d.gid] = true end end
  return out
end

-- One step of the walk of author run.a's bodies `ev` from where the last one stopped
-- (run.key), at most `step` bodies -> the step left. The R/S bodies that may be stubbed are
-- noted (run.at[n] = at), sorted oldest first at the end (run.cand). A walk whose key
-- went away starts again; next() after a change of the table is guarded.
local function walk(L, run, ev, step)
  if run.ev ~= ev or (run.key ~= nil and ev[run.key] == nil) then run.ev, run.key, run.at = ev, nil, {} end
  local tw, sn = L.store.tw[run.a] or {}, L.sn[run.a] or {}
  local good, k, b = pcall(next, ev, run.key)
  if not good then run.key, run.at = nil, {}; k, b = next(ev) end
  while k ~= nil and step > 0 do
    step, L.visited = step - 1, (L.visited or 0) + 1 -- L.visited: the bodies visited (for the tests)
    if (b.k == "R" or b.k == "S") and not b.un and not tw[k] and not sn[k] and type(b.at) == "number" then run.at[k] = b.at end
    run.key = k
    k, b = next(ev, k)
  end
  if k == nil then
    local cand, at = {}, run.at
    for n in pairs(at) do cand[#cand + 1] = n end
    sort(cand, function(p, q) if at[p] ~= at[q] then return at[p] < at[q] end return p < q end)
    run.cand, run.i = cand, 1
  end
  return step
end

-- Stubs by the cap rule, at most `max` stubs and LEDGER_PRUNE_STEP bodies visited a call
-- -> count, more (true: call again). A run (L.pr) takes the authors over the cap when it
-- begins and walks one at a time, resumably, sorting that author's candidates only. `now`:
-- the caller's clock; the cap rule reads none.
function Store:prune(now, max)
  local limit = C.LEDGER_AUTHOR_MAX - C.LEDGER_AUTHOR_ROOM
  local run = self.pr
  if not run then
    run = { list = {}, j = 1 }; self.pr = run
    for a, c in pairs(self.rc) do if c > limit then run.list[#run.list + 1] = a end end
  end
  local made, step, games = 0, C.LEDGER_PRUNE_STEP, nil
  while run.j <= #run.list do
    run.a = run.list[run.j]
    local ev = self.store.ev[run.a] or {}
    if (self.rc[run.a] or 0) <= limit or (run.cand and run.i > #run.cand) then
      run.j, run.ev, run.key, run.at, run.cand = run.j + 1, nil, nil, nil, nil -- the next author
    elseif made >= max or step <= 0 then
      break
    elseif not run.cand then
      step = walk(self, run, ev, step)
    else
      games = games or pending(self)
      local b = ev[run.cand[run.i]]
      run.i, step, self.visited = run.i + 1, step - 1, (self.visited or 0) + 1
      if b and not games[b.gid] and self:stub(b) then made = made + 1 end
    end
  end
  if run.j > #run.list then self.pr = nil end
  return made, self.pr ~= nil
end

-- Once a session, LEDGER_PRUNE_WAIT s after login (Net:start): Store:prune, a step of at most
-- LEDGER_PRUNE_STEP bodies each 5 s, never while my login queue waits, an x is to be hashed or
-- an exchange runs (a queued body must not become a stub). A prune changes no digest: no HI.
local Net = ns.LedgerNet
function Net:prune()
  if self.waiting or self.L:hashing() or self.client.ledgerSync:busy() then return self:arm("pruneTimer", 5, Net.prune) end
  local n, more = self.L:prune(self.L.epoch(), C.LEDGER_PRUNE_STEP)
  if n > 0 then self:changed() end
  if more then self:arm("pruneTimer", 5, Net.prune) end
end
