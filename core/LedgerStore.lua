local _, ns = ...

-- The per-guild store of the gold ledger (core/Ledger.lua has the entries).
-- The store is a plain table the caller owns (saved variables):
--   ev[author][n] = the first body of an id; tw[author][n] = its further
--   versions (at most 3); me[name] = {seq, born}, my counter; rf = the entries I
--   refused (core/LedgerRefused.lua); st = the stubs of R/S bodies that left the store
--   (core/LedgerStub.lua: held for x, n, the digest, the four of an id). An author's x, the
--   vector and the digest: core/LedgerHash.lua (L.xc, cached per author until that
--   author's bodies change; hashed in slices).
-- A load files every sound body again (hashing nothing); a
-- body that is not sound (no 16-hex h, an X without r or rh, filed under
-- another id, a copy of a body already filed, a fifth version) is dropped. The
-- version of an entry under my name that I made myself (no dr, no rl) is never
-- evicted from my store.
-- My counter: L.base is my saved seq at load plus my own makes; an id of mine
-- more than LEDGER_JUMP above it is asked and moves the counter only on my „Мои са“
-- (not near ID_MAX: there never). While L.adopting
-- (L.fresh: the store held no sound record of mine at load, the adoption window
-- of a new store; the caller sets L.adopting = false when the window closes) an
-- id of mine is adopted when it is at most LEDGER_JUMP above my live counter, and
-- the ids of mine the store holds at load are adopted in ascending order.
local Ledger, C, Util = ns.Ledger, ns.Const, ns.Util
local sort, byteLess = table.sort, ns.Util.byteLess
local BODIES_MAX = 4

local Store = {}; Store.__index = Store
Ledger.Store = Store -- core/LedgerDeny.lua adds Store:denied

-- The keys of t that pass keep (all when nil), sorted by less.
local function keys(t, less, keep)
  local out = {}
  for k in pairs(t or {}) do if not keep or keep(k) then out[#out + 1] = k end end
  sort(out, less)
  return out
end
-- Byte order of h, then of the canonical form (two versions may share an h).
local function before(p, q)
  if p.h ~= q.h then return byteLess(p.h, q.h) end
  return byteLess(Ledger.canon(p), Ledger.canon(q))
end
-- Can stored body b be filed under id (a, n)?
local function sound(b, a, n)
  if type(b) ~= "table" or type(b.h) ~= "string" or #b.h ~= 16 or not b.h:find("^[0-9a-f]+$") then return false end
  if b.k == "X" and not (type(b.r) == "string" and type(b.rh) == "string") then return false end
  local ba, bn = Ledger.author(b.i)
  return ba == a and bn == n
end

local function whole(v) return type(v) == "number" and v == math.floor(v) end

-- The ledger over `store`, for me; `epoch` is my clock. A load hashes nothing.
function Ledger.new(store, me, epoch)
  local ev, tw = type(store.ev) == "table" and store.ev or {}, type(store.tw) == "table" and store.tw or {}
  store.ev, store.tw, store.x = {}, {}, nil -- x of earlier versions: not stored any more
  store.me = type(store.me) == "table" and store.me or {}
  local rec = store.me[me]
  if not (type(rec) == "table" and whole(rec.seq) and rec.seq >= 0 and rec.seq <= Ledger.ID_MAX
    and type(rec.born) == "number") then rec, store.me[me] = nil, nil end
  local L = setmetatable({ store = store, me = me, epoch = epoch, rev = 0, top = {}, run = {}, rc = {}, deny = {}, xc = {}, il = {}, dirty = {}, act = {}, sn = {}, sx = {}, sl = {},
    fresh = rec == nil, adopting = rec == nil, base = rec and rec.seq or 0 }, Store)
  L:refusedLoad()
  for a, byN in pairs(ev) do
    for n, b in pairs(type(byN) == "table" and byN or {}) do
      local all, t = { b }, type(tw[a]) == "table" and tw[a][n]
      for _, x in ipairs(type(t) == "table" and t or {}) do all[#all + 1] = x end
      for _, x in ipairs(all) do
        if sound(x, a, n) and #L:bodies(a, n) < BODIES_MAX and not L:same(a, n, x) then L:move(a, n, x) end
      end
    end
  end
  L:stubLoad()
  L.came = setmetatable({}, { __mode = "k" }) -- came[body] = L.rev when it came after the load (the sync's Sync:tail)
  if L.fresh then for _, k in ipairs(keys(store.ev[me], nil)) do L:bump(k) end end
  return L
end
-- Every body of an id, by ascending h.
function Store:bodies(a, n)
  local first = self.store.ev[a] and self.store.ev[a][n]
  if not first then return {} end
  local out = { first }
  for _, b in ipairs(self.store.tw[a] and self.store.tw[a][n] or {}) do out[#out + 1] = b end
  sort(out, before)
  return out
end
-- The derived counts of a body that comes (d = 1) or goes (d = -1).
function Store:index(a, n, b, d)
  if b.k == "R" or b.k == "S" then self.rc[a] = (self.rc[a] or 0) + d end
  if b.k == "X" then
    local key = b.r .. "|" .. b.rh
    self.deny[key] = self.deny[key] or {}
    self.deny[key][b] = d > 0 or nil
  end
  if n > (self.top[a] or 0) then self.top[a] = n end
  if type(b.at) == "number" and b.at > (self.act[a] or 0) then self.act[a] = b.at end -- the author's newest entry (the sync's order)
end
function Store:advance(a)
  local k, ev, sn = self.run[a] or 0, self.store.ev[a] or {}, self.sn[a] or {}
  while ev[k + 1] or sn[k + 1] do k = k + 1 end
  self.run[a] = k
end
-- Adds body b to id (a, n), or (gone) removes it from an id that holds more than one.
function Store:move(a, n, b, gone)
  local s = self.store
  self:index(a, n, b, gone and -1 or 1)
  self.rev = self.rev + 1
  s.ev[a], s.tw[a] = s.ev[a] or {}, s.tw[a] or {}
  local tw = s.tw[a][n] or {}
  s.tw[a][n] = tw
  if gone and s.ev[a][n] == b then
    s.ev[a][n] = table.remove(tw, 1)
  elseif gone then
    for j = #tw, 1, -1 do if tw[j] == b then table.remove(tw, j) end end
  elseif s.ev[a][n] then
    tw[#tw + 1] = b
  else
    s.ev[a][n] = b
  end
  if #tw == 0 then s.tw[a][n] = nil end
  if self.came and not gone then self.came[b] = self.rev end
  self:stale(a, b.i .. ":" .. b.h, gone)
  self:advance(a)
end
-- The body held under (a, n) with b's h and canonical form, or nil.
function Store:same(a, n, b)
  local canon
  for _, old in ipairs(self:bodies(a, n)) do
    if old.h == b.h then
      canon = canon or Ledger.canon(b)
      if Ledger.canon(old) == canon then return old end
    end
  end
end
-- Did I make this body myself (under my name, got from nobody)?
function Store:mine(b) return Ledger.author(b.i) == self.me and not b.dr and not b.rl end
-- Takes entry `e` from `from` (nil: my own) -> "new" | "dup" | "twin", body | nil, reason.
function Store:add(e, from)
  local good, why = Ledger.valid(e, self.epoch())
  if not good then return nil, why end
  local a, n = Ledger.author(e.i)
  if a == self.me and from ~= nil then self:bump(n) end
  local b = Ledger.wire(e)
  b.h, b.rh = nil, b.h
  b.h = Ledger.hash(b)
  if self:stubbed(a, n, b.h) then return "dup", b end
  local held, old = self:bodies(a, n), self:same(a, n, b)
  if old then
    if from == a and not old.dr then old.dr, old.rl, self.rev = true, nil, self.rev + 1 end
    return "dup", old
  end
  if (b.k == "R" or b.k == "S") and (self.rc[a] or 0) >= C.LEDGER_AUTHOR_MAX then return nil, "full" end
  if from == a then b.dr = true elseif from ~= nil then b.rl = true end
  if #held + (self.sn[a] and self.sn[a][n] or 0) >= BODIES_MAX then
    -- Over the cap: a body its author denied goes first, else the highest h; never one I made.
    held[#held + 1] = b
    local loser
    for _, x in ipairs(held) do
      local dx, dl = self:denied(x), loser and self:denied(loser)
      if not self:mine(x) and (not loser or (dx and not dl) or (dx == dl and before(loser, x))) then loser = x end
    end
    if not loser or loser == b then return nil, "twins" end
    self:move(a, n, loser, true)
  end
  self:move(a, n, b)
  return #held == 0 and "new" or "twin", b
end
-- My record {seq, born}, made when missing.
function Store:record()
  local me = self.store.me
  me[self.me] = me[self.me] or { seq = 0, born = self.epoch() }
  return me[self.me]
end
-- My next entry of `kind`, added -> entry | nil, reason ("full": no number is left).
-- A number already held under my name (a kept far id, a stub) is skipped.
function Store:make(kind, fields)
  local rec = self:record()
  local n = rec.seq + 1
  while self:has(Ledger.id(self.me, n)) or (self.sn[self.me] and self.sn[self.me][n]) do n = n + 1 end
  if n > Ledger.ID_MAX then return nil, "full" end
  local e = Util.copy(fields)
  e.k, e.i, e.at = kind, Ledger.id(self.me, n), self.epoch()
  local status, b = self:add(e)
  if not status then return nil, b end
  rec.seq, self.base = n, math.max(self.base, n)
  return b
end
-- The first body of an id, and its further bodies (a list) or nil.
function Store:get(id)
  local a, n = Ledger.author(id)
  local first = a and self.store.ev[a] and self.store.ev[a][n]
  if not first then return nil end
  return first, self.store.tw[a] and self.store.tw[a][n]
end
-- Do I hold id (with hash h, when given)?
function Store:has(id, h)
  local a, n = Ledger.author(id)
  for _, b in ipairs(a and self:bodies(a, n) or {}) do if h == nil or b.h == h then return true end end
  return false
end
-- Every body, twins included: authors in byte order, then n, then h.
function Store:each(fn)
  for _, a in ipairs(keys(self.store.ev, byteLess)) do for _, e in ipairs(self:above(a, 0)) do fn(e) end end
end
-- How many authors I hold anything of (a body, a stub or a refusal: the vector's) and how many
-- bodies, twins included: a walk, no sort and no hash (/tavern ledger).
function Store:census()
  local s, seen, authors, bodies = self.store, {}, 0, 0
  for _, set in ipairs({ s.ev, s.st, s.rf }) do
    for a, held in pairs(set) do
      if not seen[a] and (set ~= s.ev or next(held)) then seen[a], authors = true, authors + 1 end
    end
  end
  for a, byN in pairs(s.ev) do
    for n in pairs(byN) do bodies = bodies + 1 + #(s.tw[a] and s.tw[a][n] or {}) end
  end
  return authors, bodies
end
-- Every body of the author numbered above n, ascending, twins after their sibling (with
-- `keep`: those for which keep(number, body) is true).
function Store:above(a, n, keep)
  local out = {}
  for _, k in ipairs(keys(self.store.ev[a], nil, function(k) return k > n end)) do
    for _, b in ipairs(self:bodies(a, k)) do if not keep or keep(k, b) then out[#out + 1] = b end end
  end
  return out
end
-- {"<seq>.<h>", ...} (Ledger.item), one per body of the author.
function Store:list(a)
  local out = {}
  for j, b in ipairs(self:above(a, 0)) do out[j] = Ledger.item(b) end
  return out
end

-- The highest number held for an author, holes and denied entries included.
function Store:seen(a) return self.top[a] or 0 end
-- My counter is at least n -> true; false (it stays) when n is more than
-- LEDGER_JUMP above L.base (in the adoption window: above my live counter): too far to
-- move it unasked. With force (my „Мои са“, core/LedgerNet.lua) it goes there however far,
-- except above ID_MAX - 1000000: there nothing moves (the entry stays kept, make skips held numbers).
function Store:bump(n, force)
  if force and n > Ledger.ID_MAX - 1000000 then return true end
  local rec = self:record()
  if self.adopting then
    if n > rec.seq + C.LEDGER_JUMP and not force then return false end
    self.base = math.max(self.base, n)
  elseif n > self.base + C.LEDGER_JUMP and not force then
    return false
  end
  rec.seq = math.max(rec.seq, n)
  return true
end
