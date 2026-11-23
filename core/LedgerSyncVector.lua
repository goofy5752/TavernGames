local _, ns = ...

-- The vector side of core/LedgerSync.lua: what the two vectors of an exchange
-- make each side do (Sync:vector), my note of exchanges that changed nothing
-- (Sync:fixed), and a vector that does not fit LEDGER_EX_PAGES pages: only a
-- part of it goes, the authors the partner is known to differ on first, then
-- by their newest entry (Sync:order, Sync:cells, Sync:asking), so that every
-- exchange does some of the work and none is refused whole. What goes of an
-- author's tail: Sync:tail (core/LedgerSyncTail.lua; L:above when I hold no stub).
local C, Util = ns.Const, ns.Util
local Sync = ns.LedgerSync
local sorted, byteLess = Sync.sorted, Util.byteLess
local ZERO = ("0"):rep(12)

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

-- The order of the authors of `cells` for a vector to `peer` that does not fit
-- LEDGER_EX_PAGES pages: `first` (a list), then the rest by their newest entry,
-- newest first, turned by how many of them my earlier partial vectors to that
-- peer covered (self.cur[peer]), so that every author is reached in turn
-- -> the order, how many came first.
function Sync:order(peer, cells, first)
  local seen, out, rest, act = {}, {}, {}, self.L.act
  for _, a in ipairs(first) do if cells[a] and not seen[a] then seen[a], out[#out + 1] = true, a end end
  for a in pairs(cells) do if not seen[a] then rest[#rest + 1] = a end end
  table.sort(rest, function(p, q)
    local x, y = act[p] or 0, act[q] or 0
    if x ~= y then return x > y end
    return byteLess(p, q)
  end)
  local head, cur = #out, #rest > 0 and (self.cur[peer] or 0) % #rest or 0
  for j = 1, #rest do out[#out + 1] = rest[(cur + j - 1) % #rest + 1] end
  return out, head
end

-- My vector for exchange x goes out: `cells` whole when they fit LEDGER_EX_PAGES pages;
-- else the part that fits, in the order `first` (a list of authors), then Sync:order's,
-- marked p = true on every page when `mark` (an asking vector: the partner must not
-- take an author it does not list for one I lack).
function Sync:cells(x, base, cells, first, mark)
  local list, cut = self:paged(base, "a", cells, sorted(cells))
  if cut then
    local order, head = self:order(x.peer, cells, first)
    local used
    base = Util.copy(base)
    base.p = mark or nil
    list, cut, used = self:paged(base, "a", cells, order)
    self.cur[x.peer] = (self.cur[x.peer] or 0) + math.max(0, used - head)
  end
  self:post(x, list)
end

-- My asking vector for exchange x: my cells, and first of all the authors the
-- partner's last answer showed me behind on or lacking (self.want[peer], listed
-- with n = 0 when I hold nothing of them), each for two exchanges.
function Sync:asking(x)
  local cells, want, first = self.L:vector(), self.want[x.peer] or {}, {}
  for a, left in pairs(want) do
    cells[a] = cells[a] or { n = 0, x = ZERO }
    first[#first + 1] = a
    want[a] = left > 1 and left - 1 or nil
  end
  table.sort(first, byteLess)
  self:cells(x, { v = C.PROTOCOL, t = "LVC" }, cells, first, true)
end

-- The partner's whole vector came. P: what A lacks goes, and my answer (where A
-- is not behind). A: what P lacks where I am ahead; equal n: LID. An author whose
-- two cells are as two complete exchanges in a row left them is not acted on again.
-- A's vector may be a part (x.partial): of an author of mine it does not list I
-- send nothing; my cell goes with my answer instead, as far as the pages reach,
-- and A, where it is behind or lacks the author, lists it first next time.
function Sync:vector(x)
  x.hold = self.L:hashing() or nil
  if x.hold then return self:later(function() if self.by[x.peer] == x then self:vector(x) end end) end
  local L, mine, back, fix = self.L, self.L:vector(), {}, self:fixed(x.peer)
  local extra, want = {}, self.want[x.peer] or {}
  x.acted, x.rev0 = {}, L.rev -- what comes to me after rev0 is not in this exchange's queue (Sync:tail)
  for _, a in ipairs(sorted(x.ask and x.v or mine)) do
    local m, t = mine[a], x.v[a]
    local sig = (t and t.n .. ":" .. t.x or "-") .. "|" .. (m and m.n .. ":" .. m.x or "-")
    local was = fix[a]
    local go = not (t and m and t.x == m.x) and not (was and was.s == sig and was.n >= 2) -- they differ, and not as twice before
    if not x.ask and not t and x.partial then
      extra[a] = m
    elseif go and not x.ask then
      x.acted[a] = sig; self:queue(x, self:tail(x, a, t))
    end
    if not x.ask and t and t.x ~= m.x and t.n >= m.n then back[a] = m end
    if go and x.ask and m and m.n > t.n then x.acted[a] = sig; self:queue(x, self:tail(x, a, t)) end
    if go and x.ask and m and m.n == t.n and x.lidOut < C.LEDGER_LID_AUTHORS then
      x.acted[a], x.lidOut = sig, x.lidOut + 1
      self:lid(x, a, m.n, {})
    end
    if x.ask and (not m or (m.x ~= t.x and m.n < t.n)) then want[a] = 2 end
  end
  if x.ask then self.want[x.peer] = want end
  for a in pairs(x.ask and {} or x.v) do if not mine[a] then back[a] = { n = 0, x = ZERO } end end
  local first = sorted(back)
  for a, m in pairs(extra) do back[a] = m end
  if next(back) then x.answered = true; self:cells(x, { v = C.PROTOCOL, t = "LVC", r = true }, back, first) end
  self:pump()
end
