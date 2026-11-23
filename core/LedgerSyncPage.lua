local _, ns = ...

-- The pages, vectors and lists of core/LedgerSync.lua: a vector or a list goes
-- in pages of at most PAGE packed bytes, m = true on all but the last; a LID
-- list holds Ledger.item of my bodies of one author in its scope (above the
-- common n, at the ids I hold twins for, at the ids the other list names), then
-- the refusals and the stubs I hold in that scope as "<n>.<h>" (held: never sent
-- to me again). A stub counts as its body did, also for the twins of its id, so
-- a pruned client and one that keeps everything list the same items.
local Ledger, C, Util = ns.Ledger, ns.Const, ns.Util
local Net, Sync = ns.LedgerNet, ns.LedgerSync
local item, sorted = Ledger.item, Sync.sorted

-- `data` (a map with its keys in the order `keys`; without keys a list) as messages
-- base + {[key] = part} of at most PAGE packed bytes and LEDGER_PAGE_ITEMS items, m = true
-- on all but the last. Past LEDGER_EX_PAGES pages the rest is left out (what a partner
-- takes in one exchange) -> the messages, whether something was left out, how many items went.
function Sync:paged(base, key, data, keys)
  local keyed = keys ~= nil
  keys = keys or {}
  if not keyed then for j = 1, #data do keys[j] = j end end
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
  until from > #keys or #list >= C.LEDGER_EX_PAGES
  list[#list].m = nil
  return list, from <= #keys, from - 1
end

-- The messages `list` of exchange x go out in turn.
function Sync:post(x, list)
  for _, msg in ipairs(list) do self.out[#self.out + 1] = { x = x, msg = msg } end
  self:pump()
end

-- `data` (keyed: a map, in the byte order of its keys; else a list) goes out in pages (Sync:paged).
function Sync:pages(x, base, key, data, keyed)
  self:post(x, (self:paged(base, key, data, keyed and sorted(data) or nil)))
end

-- My bodies of author au in a LID's scope: above n, at ids I hold twins for (a stub counts), at the ids in `at` (all: every one).
function Sync:scope(au, n, at, all)
  local out, bodies, sn = {}, self.L:above(au, 0), self.L.sn[au] or {}
  for j, b in ipairs(bodies) do
    local bn = select(2, Ledger.author(b.i))
    local twin = sn[bn] or (bodies[j - 1] and bodies[j - 1].i == b.i) or (bodies[j + 1] and bodies[j + 1].i == b.i)
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
  local ev, sn = self.L.store.ev[au] or {}, self.L.sn[au] or {}
  for _, s in ipairs(self.L:stubs(au)) do -- a stub as its body; a twin where its id holds another
    local it = s.n .. "." .. s.h
    if (all or s.n > n or at[s.n] or ev[s.n] or sn[s.n] > 1) and not set[it] then list[#list + 1] = it; set[it] = true end
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
