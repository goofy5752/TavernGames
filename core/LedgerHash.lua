local _, ns = ...

-- The per-author x, the vector and the digest of the ledger store
-- (core/LedgerStore.lua). An author's x is the first 12 hex of SHA-256 over the
-- sorted "<id>:<h>" of its bodies joined by ",": not a sum, so no set of
-- planted bodies cancels out. Hashing a long author costs tens of ms, so it is
-- done in slices: a change marks the author stale (Store:stale, L.dirty) and
-- L:work(n) feeds at most n items to a running SHA-256, one author after
-- another, giving the same x as one hash over the whole list. A body I refused
-- and still remember (core/LedgerRefused.lua) counts as held in x, and in n where
-- it fills a hole below the highest body I hold. The client hashes
-- LEDGER_HASH_ITEMS items a frame (Net:hash, core/LedgerSend.lua; L.kick asks for
-- it), and whoever needs fresh values waits for them (Net:fresh): a vector, the
-- GUILD HI with my digest, the sync's comparisons. L:vector() and L:digest()
-- called while stale finish the work at once (a store without a client, a
-- test); L:digest(true) gives the last settled digest instead (nil: none yet).
local Ledger, Sha256 = ns.Ledger, ns.Sha256
local Store = Ledger.Store
local concat, sort, byteLess, min = table.concat, table.sort, ns.Util.byteLess, math.min

-- Author a's x is stale: its bodies (or the refusals I remember of it) changed.
function Store:stale(a)
  self.xc[a], self.dirty[a] = nil, true
  if self.job and self.job.a == a then self.job = nil end
  if self.kick then self.kick() end
end

-- Is an x still to be hashed?
function Store:hashing() return next(self.dirty) ~= nil end

-- The sorted "<id>:<h>" of author a's bodies and of its bodies I refused.
function Store:items(a)
  local items = {}
  for j, b in ipairs(self:above(a, 0)) do items[j] = b.i .. ":" .. b.h end
  for _, r in ipairs(self:refusals(a)) do items[#items + 1] = a .. ":" .. r.n .. ":" .. r.h end
  sort(items, byteLess)
  return items
end

-- The highest k with 1..k all held or refused, a refused number counting only below the highest held one.
function Store:reach(a)
  local k, ev, rn, top = self.run[a] or 0, self.store.ev[a] or {}, self.rn[a], self.top[a] or 0
  while rn and k < top and (ev[k + 1] or rn[k + 1]) do k = k + 1 end
  return k
end

-- Hashes at most n items (all that is stale when nil) -> true when every x is fresh.
-- L.hashed counts the items fed.
function Store:work(n)
  n = n or math.huge
  while true do
    local job = self.job
    if not job then
      local a = next(self.dirty)
      if a == nil then return true end
      job = { a = a, items = self:items(a), at = 1, sha = Sha256.stream() }
      self.job = job
    end
    local items, left = job.items, #job.items - job.at + 1
    if left > 0 then
      if n <= 0 then return false end
      local k = min(left, n)
      job.sha:add((job.at > 1 and "," or "") .. concat(items, ",", job.at, job.at + k - 1))
      job.at, n, self.hashed = job.at + k, n - k, (self.hashed or 0) + k
    end
    if job.at > #items then
      self.xc[job.a], self.dirty[job.a], self.job = job.sha:hex():sub(1, 12), nil, nil
    end
  end
end

-- {[author] = {n, x}}: n the highest k with 1..k all held (Store:reach), x as in the header (12 hex);
-- an author of whom I only remember refusals has n = 0.
function Store:vector()
  if self:hashing() then self:work() end
  local out = {}
  for a, byN in pairs(self.store.ev) do
    if next(byN) then out[a] = { n = self:reach(a), x = self.xc[a] } end
  end
  for a in pairs(self.store.rf) do out[a] = out[a] or { n = 0, x = self.xc[a] } end
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
