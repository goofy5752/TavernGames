local _, ns = ...

-- What goes of an author's tail in an exchange of core/LedgerSync.lua (F4, Decision R; J1 a, J5,
-- Task 2 review). A newcomer never gets the bodies I hold only as stubs, so its n stays below
-- them and L:above(author, n) would resend it all every time. Each LEV notes the highest number
-- it carried of an author I hold stubs of (Sync:mark); Sync:tail leaves out an R or S at or
-- below the peer's mark that came to me before the last heard exchange that acted on its
-- author (L.came, self.since: memory, J5), unless that one queued and did not send it
-- (self.owe). Any other kind (D, C, N, P, X) always goes. Heard: both f, not capped. Its marks
-- count for the session (self.hot); not cut either, it commits them to the ledger store:
-- store.hw[peer] = {at = my epoch at the row's first commit (kept), a = {[author] = n}}, gone
-- LEDGER_HW_KEEP s after it, at most LEDGER_HW_PEERS rows (a new one drops the oldest); a load
-- drops malformed rows and cells and an author's I hold no stub of. A partner that holds
-- nothing of the author (a new install) is sent L:above, and its marks of that author go.
local Ledger, C, Util = ns.Ledger, ns.Const, ns.Util
local Sync = ns.LedgerSync
local byteLess, sorted, ZERO = Util.byteLess, Sync.sorted, ("0"):rep(12)

local function number(v) return type(v) == "number" and v >= 1 and v <= Ledger.ID_MAX and v == math.floor(v) end
-- The peers of `rows`, the oldest row last.
local function newest(rows)
  local peers = sorted(rows)
  table.sort(peers, function(p, q)
    if rows[p].at ~= rows[q].at then return rows[p].at > rows[q].at end
    return byteLess(p, q)
  end)
  return peers
end

-- The saved marks of ledger L (after its load: L.sn), sound and bounded (they become L.store.hw) -> the rows.
function Sync.marks(L)
  local saved, now, out = L.store.hw, L.epoch(), {}
  for peer, row in pairs(type(saved) == "table" and saved or {}) do
    if Sync.name(peer) and type(row) == "table" and type(row.at) == "number" and row.at > now - C.LEDGER_HW_KEEP
      and row.at <= now + C.LEDGER_FUTURE and type(row.a) == "table" then
      out[peer] = { at = row.at, a = {} }
      for a, n in pairs(row.a) do if L.sn[a] and number(n) then out[peer].a[a] = n end end
    end
  end
  local peers = newest(out)
  for j = C.LEDGER_HW_PEERS + 1, #peers do out[peers[j]] = nil end
  L.store.hw = out
  return out
end

-- The store's row of `peer` while it is younger than LEDGER_HW_KEEP s (an older one goes); with
-- `make`, a new one when there is none (a new peer past LEDGER_HW_PEERS drops the oldest row).
function Sync:row(peer, make)
  local rows, now = self.high, self.L.epoch()
  if rows[peer] and rows[peer].at <= now - C.LEDGER_HW_KEEP then rows[peer] = nil end
  if make and not rows[peer] then
    local peers = newest(rows)
    if #peers >= C.LEDGER_HW_PEERS then rows[peers[#peers]] = nil end
    rows[peer] = { at = now, a = {} }
  end
  return rows[peer]
end

-- Body b left for x's peer in a LEV (Sync:pump): x.left, and x.hw[author] when I hold stubs of it.
function Sync:mark(x, b)
  local a, k = Ledger.author(b.i)
  x.left[#x.left + 1] = b
  if a and self.L.sn[a] then x.hw[a] = math.max(x.hw[a] or 0, k) end
end

-- Exchange x ended (Sync:finish; capped: at LEDGER_EX_MAX or the page cap). Heard: what came to me
-- before its x.rev0 is what the peer got or holds, of each author it acted on, save what it
-- queued and did not send (owed); its marks count; not cut either: they are committed.
function Sync:ended(x, capped)
  if not (x.fMine and x.fTheirs) or capped then return end
  local peer = x.peer
  local since, owe, hot = self.since[peer] or {}, self.owe[peer] or setmetatable({}, { __mode = "k" }), self.hot[peer] or {}
  self.since[peer], self.owe[peer], self.hot[peer] = since, owe, hot
  for a in pairs(x.rev0 and x.acted or {}) do since[a] = x.rev0 end
  for _, b in ipairs(x.left) do owe[b] = nil end
  for _, list in ipairs({ x.rest or {}, x.q }) do for _, b in ipairs(list) do owe[b] = true end end
  for a, k in pairs(x.hw) do hot[a] = math.max(hot[a] or 0, k) end
  if x.cut or not next(hot) then return end
  local row = self:row(peer, true)
  for a, k in pairs(hot) do row.a[a] = math.max(row.a[a] or 0, k) end
  self.hot[peer] = nil
end

-- The bodies of author a that exchange x queues for a partner whose cell is t (nil: it lacks a):
-- L:above(a, n), less, when I hold stubs of a above n, the R and S Sync:ended let me leave out.
function Sync:tail(x, a, t)
  local L, n, peer, hot = self.L, t and t.n or 0, x.peer, self.hot[x.peer] or {}
  local row = self:row(peer)
  if not t or t.x == ZERO then -- it holds nothing of a: my marks of a are wrong
    if row then row.a[a] = nil end
    hot[a] = nil
  end
  local h = t and t.x ~= ZERO and L:stubTop(a) > n and math.max(row and row.a[a] or 0, hot[a] or 0) or 0
  if h <= n then return L:above(a, n) end
  local since, owe, came = (self.since[peer] or {})[a] or 0, self.owe[peer] or {}, L.came
  return L:above(a, n, function(k, b)
    return k > h or (b.k ~= "R" and b.k ~= "S") or (came[b] or 0) > since or owe[b] == true
  end)
end
