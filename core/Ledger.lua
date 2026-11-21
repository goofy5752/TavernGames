local _, ns = ...

-- The guild's gold ledger: append-only entries `i = "<author>:<n>"` of the
-- kinds R (result), D (debt), C (confirm), N (contest), P (paid) and X (deny),
-- their canonical hash and validation, and the per-guild store. The store is a
-- plain table the caller owns (saved variables):
--   ev[author][n] = the first body of an id; tw[author][n] = its further bodies
--   (twins, at most 3); me[name] = {seq, born}, my counter; x[author] = the sum
--   mod 2^32 of the first 8 hex of each of that author's bodies' h.
-- A stored entry keeps its own hash in `h`, plus `dr` (got from its author) or
-- `rl` (relayed). An X's own field `h` (the denied entry's hash) is kept as
-- `rh` in the store; `wire` and `canon` give it back as `h`.
local Ledger = {}
ns.Ledger = Ledger

local C, Sha256, Util = ns.Const, ns.Sha256, ns.Util
local concat, sort, floor, byteLess = table.concat, table.sort, math.floor, ns.Util.byteLess

local FIELDS = { "i", "k", "at", "gid", "g", "f", "t", "c", "why", "r", "h", "how", "sk", "n", "w", "l" }
local NAME_MAX, SIZE_MAX, BODIES_MAX, W32, W24 = 64, 600, 4, 4294967296, 16777216
local PAID_MAX = 99999999999 -- copper: a payment is any whole amount up to the gold cap

local function set(...) local s = {} for _, v in ipairs({ ... }) do s[v] = true end return s end
-- The fields of each kind: true = required, false = optional.
local KINDS = {
  R = { gid = true, g = true, n = true, w = true, l = true, sk = false, why = false },
  D = { gid = true, g = true, f = true, t = true, c = true, why = true },
  C = { r = true }, N = { r = true, why = true }, P = { f = true, c = true, how = true }, X = { r = true, h = true },
}
local WHY = { D = set("lost", "left", "offline", "idle"), N = set("forged", "roll", "stand", "amount", "no"),
  R = set("left", "offline", "idle") }
local HOW = set("trade", "mail", "hand")

local function whole(v) return type(v) == "number" and v == floor(v) end
-- The keys of t that pass keep (all when nil), sorted by less.
local function keys(t, less, keep)
  local out = {}
  for k in pairs(t or {}) do if not keep or keep(k) then out[#out + 1] = k end end
  sort(out, less)
  return out
end
function Ledger.id(author, n) return author .. ":" .. n end
-- The author and number of an id (the text before the last colon), or nil.
function Ledger.author(id)
  if type(id) ~= "string" then return nil end
  local a, n = id:match("^(.*):([1-9]%d*)$")
  if not a or a == "" or #n > 9 then return nil end
  return a, tonumber(n)
end
-- Field f of an entry of either form as it is sent: h is an X's denied hash
-- (`rh` when stored), never the local hash.
local function field(e, f)
  if f ~= "h" then return e[f] end
  return e.k == "X" and (e.rh or e.h) or nil
end
local function part(v)
  if v == nil then return "" elseif v == false then return "-" elseif type(v) ~= "table" then return tostring(v) end
  local out = {}
  for j, x in ipairs(v) do out[j] = part(x) end
  return concat(out, ",")
end
-- The fields in FIELDS order joined by "|"; hash: its first 8 hex of SHA-256.
function Ledger.canon(e)
  local out = {}
  for j, f in ipairs(FIELDS) do out[j] = part(field(e, f)) end
  return concat(out, "|")
end
function Ledger.hash(e) return Sha256.hex(Ledger.canon(e)):sub(1, 8) end
-- The entry as sent: its canonical fields only (lists copied), an X's denied hash as h.
function Ledger.wire(e)
  local w = {}
  for _, f in ipairs(FIELDS) do
    local v = field(e, f)
    w[f] = type(v) == "table" and { unpack(v) } or v
  end
  return w
end

local function name(v) return type(v) == "string" and v ~= "" and #v <= NAME_MAX and not v:find("[|,]") end
local function seat(v) return whole(v) and v >= 1 and v <= C.MAX_SEATS end
local function nameOrEmpty(v) return v == false or name(v) end
-- A list of min..MAX_SEATS elements and no other keys, each passing `each`.
local function list(v, each, min)
  if type(v) ~= "table" then return false end
  local count = 0
  for _ in pairs(v) do count = count + 1 end
  if count < min or count > C.MAX_SEATS then return false end
  for j = 1, count do if v[j] == nil or not each(v[j]) then return false end end
  return true
end
-- Each field's check: the reason when it fails, else false (c and why are checked per kind).
local function person(v) return not name(v) and "name" end
local function seats(v) return not list(v, seat, 0) and "shape" end
local CHECK = {
  gid = function(v) return not (type(v) == "string" and not v:find("|", 1, true) and v:find("./%d+$")) and "shape" end,
  g = function(v) return not (type(v) == "string" and #v <= 32 and v:find("^[%w_]+$")) and "shape" end,
  f = person, t = person, w = seats, l = seats,
  n = function(v) return not list(v, nameOrEmpty, 1) and "name" end,
  sk = function(v) return not ns.Stake.valid(v) and "amount" end,
  r = function(v) return not Ledger.author(v) and "shape" end,
  h = function(v) return not (type(v) == "string" and v:find("^%x%x%x%x%x%x%x%x$")) and "shape" end,
  how = function(v) return not HOW[v] and "shape" end,
}
local function amount(e)
  if e.k == "D" then return ns.Stake.valid(e.c) end
  return whole(e.c) and e.c >= 1 and e.c <= PAID_MAX
end
local function right(e, author)
  if e.k == "D" then return e.f ~= e.t and (author == e.f or author == e.t) end
  if e.k == "P" then return author ~= e.f end
  return e.k ~= "X" or Ledger.author(e.r) == author
end

-- Is `e` a well-formed entry its author may write -> true | nil, reason.
function Ledger.valid(e, now)
  if type(e) ~= "table" then return nil, "shape" end
  local author = Ledger.author(e.i)
  if not author then return nil, "id" end
  local fields = KINDS[e.k]
  if not fields then return nil, "kind" end
  if not whole(e.at) or e.at < 0 or (now and e.at > now + C.LEDGER_FUTURE) then return nil, "time" end
  if not name(author) then return nil, "name" end
  for j = 4, #FIELDS do
    local f, v = FIELDS[j], field(e, FIELDS[j])
    if (fields[f] == nil and v ~= nil) or (fields[f] == true and v == nil) then return nil, "shape" end
    local why = v ~= nil and CHECK[f] and CHECK[f](v)
    if why then return nil, why end
  end
  if e.why ~= nil and not WHY[e.k][e.why] then return nil, "shape" end
  if fields.c and not amount(e) then return nil, "amount" end
  if not right(e, author) then return nil, "right" end
  if #Ledger.canon(e) > SIZE_MAX then return nil, "size" end
  return true
end

local Store = {}; Store.__index = Store

-- The ledger over `store`, for me; `epoch` is my clock. A load hashes nothing.
function Ledger.new(store, me, epoch)
  for _, key in ipairs({ "ev", "tw", "me", "x" }) do store[key] = store[key] or {} end
  local L = setmetatable({ store = store, me = me, epoch = epoch, rev = 0, top = {}, run = {}, rc = {}, deny = {} }, Store)
  for a, byN in pairs(store.ev) do
    local sum = 0
    for n in pairs(byN) do
      for _, b in ipairs(L:bodies(a, n)) do L:index(a, n, b, 1); sum = (sum + tonumber(b.h, 16)) % W32 end
    end
    store.x[a] = store.x[a] or sum
    L:advance(a)
  end
  return L
end
-- Every body of an id, by ascending h.
function Store:bodies(a, n)
  local first = self.store.ev[a] and self.store.ev[a][n]
  if not first then return {} end
  local out = { first }
  for _, b in ipairs(self.store.tw[a] and self.store.tw[a][n] or {}) do out[#out + 1] = b end
  sort(out, function(p, q) return byteLess(p.h, q.h) end)
  return out
end
-- The derived counts of a body that comes (d = 1) or goes (d = -1).
function Store:index(a, n, b, d)
  if b.k == "R" then self.rc[a] = (self.rc[a] or 0) + d end
  if b.k == "X" then self.deny[b.r .. "|" .. b.rh] = (self.deny[b.r .. "|" .. b.rh] or 0) + d end
  if n > (self.top[a] or 0) then self.top[a] = n end
end
function Store:advance(a)
  local k, ev = self.run[a] or 0, self.store.ev[a]
  while ev[k + 1] do k = k + 1 end
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
  s.x[a] = ((s.x[a] or 0) + (gone and -1 or 1) * tonumber(b.h, 16)) % W32
  self:advance(a)
end
-- Takes entry `e` from `from` (nil: my own) -> "new" | "dup" | "twin", body | nil, reason.
function Store:add(e, from)
  local good, why = Ledger.valid(e, self.epoch())
  if not good then return nil, why end
  local a, n = Ledger.author(e.i)
  local b = Ledger.wire(e)
  b.h, b.rh = nil, b.h
  b.h = Ledger.hash(b)
  local held = self:bodies(a, n)
  for _, old in ipairs(held) do
    if old.h == b.h then
      if from == a and not old.dr then old.dr, old.rl, self.rev = true, nil, self.rev + 1 end
      return "dup", old
    end
  end
  if b.k == "R" and (self.rc[a] or 0) >= C.LEDGER_AUTHOR_MAX then return nil, "full" end
  if from == a then b.dr = true elseif from ~= nil then b.rl = true end
  if #held >= BODIES_MAX then
    -- Over the cap: a body its author denied goes first, else the highest h.
    held[#held + 1] = b
    local loser
    for _, x in ipairs(held) do
      local dx, dl = self:denied(x), loser and self:denied(loser)
      if not loser or (dx and not dl) or (dx == dl and byteLess(loser.h, x.h)) then loser = x end
    end
    if loser == b then return nil, "twins" end
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
-- My next entry of `kind`, added -> entry | nil, reason.
function Store:make(kind, fields)
  local rec = self:record()
  local n = math.max(rec.seq, self:seen(self.me)) + 1
  local e = Util.copy(fields)
  e.k, e.i, e.at = kind, Ledger.id(self.me, n), self.epoch()
  local status, b = self:add(e)
  if not status then return nil, b end
  rec.seq = n
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
-- {[author] = {n, x}}: n the highest k with 1..k all held, x the low 24 bits of the sum as 6 hex.
function Store:vector()
  local out = {}
  for a, byN in pairs(self.store.ev) do
    if next(byN) then out[a] = { n = self.run[a] or 0, x = string.format("%06x", self.store.x[a] % W24) } end
  end
  return out
end
-- 8 hex of SHA-256 over the sorted "<author>:<x>", cached until the next change.
function Store:digest()
  if self.cache and self.cache.rev == self.rev then return self.cache.d end
  local v, parts = self:vector(), {}
  for j, a in ipairs(keys(v, byteLess)) do parts[j] = a .. ":" .. v[a].x end
  self.cache = { rev = self.rev, d = Sha256.hex(concat(parts, ",")):sub(1, 8) }
  return self.cache.d
end
-- Every body of the author numbered above n, ascending, twins after their sibling.
function Store:above(a, n)
  local out = {}
  for _, k in ipairs(keys(self.store.ev[a], nil, function(k) return k > n end)) do
    for _, b in ipairs(self:bodies(a, k)) do out[#out + 1] = b end
  end
  return out
end
-- {"<seq>.<h6>", ...}, one per body of the author.
function Store:list(a)
  local out = {}
  for j, b in ipairs(self:above(a, 0)) do out[j] = select(2, Ledger.author(b.i)) .. "." .. b.h:sub(1, 6) end
  return out
end
-- Did e's author deny exactly this body (an X naming e.i and e.h)?
function Store:denied(e) return e.h ~= nil and (self.deny[e.i .. "|" .. e.h] or 0) > 0 end
-- The highest number held for an author, holes and denied entries included.
function Store:seen(a) return self.top[a] or 0 end
-- My counter is at least n.
function Store:bump(n) local rec = self:record(); rec.seq = math.max(rec.seq, n) end

return Ledger
