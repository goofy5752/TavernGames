local _, ns = ...

-- The per-author x, the vector and the digest of the ledger store
-- (core/LedgerStore.lua). An author's x is the first 12 hex of SHA-256 over the
-- sorted "<id>:<h>" of its bodies joined by ",": not a sum, so no set of
-- planted bodies cancels out. Hashing a long author costs tens of ms, so it is
-- done in slices: a change marks the author stale (Store:stale, L.dirty) and
-- L:work(n) feeds at most n items to a running SHA-256, one author after
-- another, giving the same x as one hash over the whole list. The sorted list
-- of an author is kept once built (L.il, memory only): a body that comes or goes
-- is put in or taken out at its place, and only its first build of a session
-- sorts, in slices too (Store:work). A body I refused
-- and still remember (core/LedgerRefused.lua) counts as held in x, and in n where
-- it fills a hole below the highest body I hold. A stub (core/LedgerStub.lua) counts as
-- its body did, in x and in n. An author whose newest entry is older than LEDGER_IL_IDLE
-- keeps no sorted list once hashed (Decision M5). The client hashes
-- LEDGER_HASH_ITEMS items a frame (Net:hash, core/LedgerSend.lua; L.kick asks for
-- it), and whoever needs fresh values waits for them (Net:fresh): a vector, the
-- GUILD HI with my digest, the sync's comparisons. L:vector() and L:digest()
-- called while stale finish the work at once (a store without a client, a
-- test); L:digest(true) gives the last settled digest instead (nil: none yet).
local Ledger, Sha256, C = ns.Ledger, ns.Sha256, ns.Const
local Store = Ledger.Store
local concat, sort, byteLess, min = table.concat, table.sort, ns.Util.byteLess, math.min
local insert, remove, floor = table.insert, table.remove, math.floor

-- The first place in sorted list whose item is not less than item (binary search).
local function place(list, item)
  local lo, hi = 1, #list + 1
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if byteLess(list[mid], item) then lo = mid + 1 else hi = mid end
  end
  return lo
end

-- Author a's x is stale: its bodies (or the refusals I remember of it) changed. item: the
-- "<id>:<h>" that came (gone: that went); a kept list L.il[a] takes it at its place, and
-- without item (or an item it does not hold) the list is dropped, to be built by the next job.
function Store:stale(a, item, gone)
  local list = self.il[a]
  if list and item then
    local j = place(list, item)
    if not gone then insert(list, j, item) elseif list[j] == item then remove(list, j) else self.il[a] = nil end
  else
    self.il[a] = nil
  end
  self.xc[a], self.dirty[a] = nil, true
  if self.job and self.job.a == a then self.job = nil end
  if self.kick then self.kick() end
end

-- Is an x still to be hashed?
function Store:hashing() return next(self.dirty) ~= nil end

-- The "<id>:<h>" of author a's bodies, its stubs and its bodies I refused, in no order: a walk, no sort
-- (Store:above sorts every number of the author at once; residual 25).
function Store:items(a)
  local items, tw = {}, self.store.tw[a] or {}
  for n, b in pairs(self.store.ev[a] or {}) do
    items[#items + 1] = b.i .. ":" .. b.h
    for _, t in ipairs(tw[n] or {}) do items[#items + 1] = t.i .. ":" .. t.h end
  end
  for _, s in ipairs(self:stubs(a)) do items[#items + 1] = a .. ":" .. s.n .. ":" .. s.h end
  for _, r in ipairs(self:refusals(a)) do items[#items + 1] = a .. ":" .. r.n .. ":" .. r.h end
  return items
end

-- The highest k with 1..k all held, stubbed or refused, a refused number counting only below the highest held one.
function Store:reach(a)
  local k, ev, sn, rn, top = self.run[a] or 0, self.store.ev[a] or {}, self.sn[a] or {}, self.rn[a], self.top[a] or 0
  while ev[k + 1] or sn[k + 1] or (rn and k < top and rn[k + 1]) do k = k + 1 end
  return k
end

-- The next k items of a building job's list: the least head of its sorted runs, k times.
local function merge(job, k)
  local runs, heads, il = job.runs, job.heads, job.il
  for _ = 1, k do
    local best, low
    for r = 1, #runs do
      local x = runs[r][heads[r]]
      if x and (not low or byteLess(x, low)) then best, low = r, x end
    end
    il[#il + 1], heads[best] = low, heads[best] + 1
  end
end

-- Hashes at most n items (all that is stale when nil) -> true when every x is fresh.
-- An author with a kept list (L.il) feeds it to the hash at once. Without one, its job collects
-- the items in one call (Store:items; they count against n), sorts them in runs of at most n
-- items a call, then merges the runs' heads into the new list while feeding the hash, at most n
-- items a call. L.sorted counts the items sorted, L.hashed the items fed.
function Store:work(n)
  n = n or math.huge
  while true do
    local job = self.job
    if not job then
      local a = next(self.dirty)
      if a == nil then return true end
      if n <= 0 then return false end
      job = { a = a, sha = Sha256.stream(), at = 1, il = self.il[a] }
      if not job.il then
        job.items, job.cut, job.runs, job.heads, job.il = self:items(a), 1, {}, {}, {}
        n = n - #job.items
      end
      self.job = job
    end
    local items = job.items
    local total = items and #items or #job.il
    if n <= 0 and job.at <= total then return false end
    if items and job.cut <= total then
      local k, run = min(total - job.cut + 1, n), {}
      for j = 1, k do run[j] = items[job.cut + j - 1] end
      sort(run, byteLess)
      job.runs[#job.runs + 1], job.heads[#job.heads + 1] = run, 1
      job.cut, n, self.sorted = job.cut + k, n - k, (self.sorted or 0) + k
    elseif job.at <= total then
      local k = min(total - job.at + 1, n)
      if items then merge(job, k) end
      job.sha:add((job.at > 1 and "," or "") .. concat(job.il, ",", job.at, job.at + k - 1))
      job.at, n, self.hashed = job.at + k, n - k, (self.hashed or 0) + k
    end
    if job.at > total then
      local idle = (self.act[job.a] or 0) < self.epoch() - C.LEDGER_IL_IDLE
      self.xc[job.a], self.il[job.a], self.dirty[job.a], self.job = job.sha:hex():sub(1, 12), not idle and job.il or nil, nil, nil
    end
  end
end

-- {[author] = {n, x}}: n the highest k with 1..k all held (Store:reach), x as in the header (12 hex);
-- an author of whom I hold only stubs or remembered refusals is listed with its n too.
function Store:vector()
  if self:hashing() then self:work() end
  local out = {}
  for a, byN in pairs(self.store.ev) do
    if next(byN) then out[a] = { n = self:reach(a), x = self.xc[a] } end
  end
  for _, set in ipairs({ self.store.st, self.store.rf }) do for a in pairs(set) do out[a] = out[a] or { n = self:reach(a), x = self.xc[a] } end end
  return out
end

-- 8 hex of SHA-256 over the sorted "<author>:<x>", cached until the next change.
-- lazy: while an x is stale, the last settled digest (nil: none yet), hashing nothing.
function Store:digest(lazy)
  if lazy and self:hashing() then return self.cache and self.cache.d or nil end
  if self.cache and self.cache.rev == self.rev then return self.cache.d end
  local v, parts, keys = self:vector(), {}, {}
  for a in pairs(v) do keys[#keys + 1] = a end
  sort(keys, byteLess)
  for j, a in ipairs(keys) do parts[j] = a .. ":" .. v[a].x end
  self.cache = { rev = self.rev, d = Sha256.hex(concat(parts, ",")):sub(1, 8) }
  return self.cache.d
end
