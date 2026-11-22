local _, ns = ...

-- The pages, vectors and lists of core/LedgerSync.lua: a vector or a list goes
-- in pages of at most PAGE packed bytes, m = true on all but the last; a LID
-- list holds Ledger.item of my bodies of one author in its scope (above the
-- common n, at the ids I hold twins for, at the ids the other list names).
local Ledger, C, Util = ns.Ledger, ns.Const, ns.Util
local Net, Sync = ns.LedgerNet, ns.LedgerSync
local item, sorted = Ledger.item, Sync.sorted

-- `data` (keyed: a map, by key; else a list) as messages base + {[key] = part} of
-- at most PAGE packed bytes and LEDGER_PAGE_ITEMS items, m = true on all but the last;
-- they go out in turn. Past LEDGER_EX_PAGES x LEDGER_PAGE_ITEMS items, the rest is left out
-- (what a partner takes in one exchange).
function Sync:pages(x, base, key, data, keyed)
  local keys = keyed and sorted(data) or {}
  if not keyed then for j = 1, #data do keys[j] = j end end
  for j = #keys, C.LEDGER_EX_PAGES * C.LEDGER_PAGE_ITEMS + 1, -1 do keys[j] = nil end
  local function page(from, k) -- measured with m (the last page loses it)
    local msg, part = Util.copy(base), {}
    for j = from, from + k - 1 do
      if keyed then part[keys[j]] = data[keys[j]] else part[#part + 1] = data[j] end
    end
    msg[key], msg.m = part, true
    return msg
  end
  local from, list = 1, {}
  repeat -- an empty map or list is one empty page
    local left = #keys - from + 1
    local k = left > 0 and math.max(1, Net.fit(math.min(left, C.LEDGER_PAGE_ITEMS), Sync.PAGE,
      function(k) return page(from, k) end)) or 0

    list[#list + 1], from = page(from, k), from + k
  until from > #keys
  list[#list].m = nil
  for _, msg in ipairs(list) do self.out[#self.out + 1] = { x = x, msg = msg } end
  self:pump()
end

-- My bodies of author au in a LID's scope: above n, at ids I hold twins for, at the ids in `at` (all: every one).
function Sync:scope(au, n, at, all)
  local out, bodies = {}, self.L:above(au, 0)
  for j, b in ipairs(bodies) do
    local twin = (bodies[j - 1] and bodies[j - 1].i == b.i) or (bodies[j + 1] and bodies[j + 1].i == b.i)
    local bn = select(2, Ledger.author(b.i))
    if all or bn > n or twin or at[bn] then out[#out + 1] = b end
  end
  return out
end

-- My LID for author au (answer: to one I got; all: my whole list).
function Sync:lid(x, au, n, at, answer, all)
  local list, set = {}, {}
  for _, b in ipairs(self:scope(au, n, at, all)) do list[#list + 1] = item(b); set[item(b)] = true end
  for _, r in ipairs(self.L:refusals(au)) do -- what I refused counts as held: the partner does not send it again
    local it = r.n .. "." .. r.h
    if (all or r.n > n or at[r.n]) and not set[it] then list[#list + 1] = it; set[it] = true end
  end
  if not answer then x.lidN[au], x.lidMine[au], x.lidAll[au] = n, set, all end
  self:pages(x, { v = C.PROTOCOL, t = "LID", au = au, r = answer or nil }, "l", list, false)
end

-- A list l of au came: I queue my bodies in its scope that it lacks -> the ids it names, how many I queued, its set.
function Sync:lacks(x, au, n, l)
  local set, at, send = {}, {}, {}
  for _, s in ipairs(l) do
    local k = tonumber(s:match("^(%d+)%."))
    set[s], at[k or 0] = true, true
  end
  for _, b in ipairs(self:scope(au, n, at)) do if not set[item(b)] then send[#send + 1] = b end end
  self:queue(x, send)
  return at, #send, set
end

-- What my complete exchanges with `peer` left as it was: sig[author] = {s, n}, the
-- two cells ("<their n>:<x>|<my n>:<x>") I acted on and in how many exchanges in a
-- row; kept LEDGER_REFUSED_TTL s, at most FIX_MAX authors. With `acted` (an
-- exchange's x.acted) those are noted.
local FIX_MAX = 500
function Sync:fixed(peer, acted)
  local f, now = self.fix[peer], self.client.env.now()
  if not f or now - f.at >= C.LEDGER_REFUSED_TTL then f = { at = now, n = 0, sig = {} }; self.fix[peer] = f end
  for a, s in pairs(acted or {}) do
    local old = f.sig[a]
    if old or f.n < FIX_MAX then f.n, f.sig[a] = f.n + (old and 0 or 1), { s = s, n = old and old.s == s and old.n + 1 or 1 } end
  end
  return f.sig
end

-- The partner's whole vector came. P: what A lacks goes, and my answer (where A
-- is not behind). A: what P lacks where I am ahead; equal n: LID. An author whose
-- two cells are as two complete exchanges in a row left them is not acted on again.
function Sync:vector(x)
  x.hold = self.L:hashing() or nil
  if x.hold then return self:later(function() if self.by[x.peer] == x then self:vector(x) end end) end
  local L, mine, back, fix = self.L, self.L:vector(), {}, self:fixed(x.peer)
  x.acted = {}
  for _, a in ipairs(sorted(x.ask and x.v or mine)) do
    local m, t = mine[a], x.v[a]
    local sig = (t and t.n .. ":" .. t.x or "-") .. "|" .. (m and m.n .. ":" .. m.x or "-")
    local was = fix[a]
    local go = not (t and m and t.x == m.x) and not (was and was.s == sig and was.n >= 2) -- they differ, and not as twice before
    if go and not x.ask then x.acted[a] = sig; self:queue(x, L:above(a, t and t.n or 0)) end
    if not x.ask and t and t.x ~= m.x and t.n >= m.n then back[a] = m end
    if go and x.ask and m and m.n > t.n then x.acted[a] = sig; self:queue(x, L:above(a, t.n)) end
    if go and x.ask and m and m.n == t.n and x.lidOut < C.LEDGER_LID_AUTHORS then
      x.acted[a], x.lidOut = sig, x.lidOut + 1
      self:lid(x, a, m.n, {})
    end
  end
  for a in pairs(x.ask and {} or x.v) do if not mine[a] then back[a] = { n = 0, x = ("0"):rep(12) } end end
  if next(back) then x.answered = true; self:pages(x, { v = C.PROTOCOL, t = "LVC", r = true }, "a", back, true) end
  self:pump()
end

local function name(v) return type(v) == "string" and v ~= "" and #v <= 64 and not v:find("[|,]") end
local function cell(v) return type(v) == "table" and type(v.n) == "number" and v.n >= 0 and v.n == math.floor(v.n)
  and type(v.x) == "string" and #v.x == 12 and v.x:find("^[0-9a-f]+$") ~= nil end
Sync.name = name
-- A page of a vector (keyed) or of a list into acc -> true when it was the last.
function Sync.gather(acc, part, keyed, more)
  for k, v in pairs(part) do
    if keyed and name(k) and cell(v) then acc[k] = { n = v.n, x = v.x } end
    if not keyed and type(k) == "number" and type(v) == "string" and #v <= 26 and v:find("^%d+%.[0-9a-f]+$") then
      acc[#acc + 1] = v
    end
  end
  return not more
end
