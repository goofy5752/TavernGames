local _, ns = ...

-- What goes of an author's tail in an exchange of core/LedgerSync.lua (F4, Decision R
-- as ruled in J1 a and J5). A partner that never got the bodies I hold only as stubs
-- (a newcomer after the author passed the cap) stays below them for good: its n for
-- that author does not reach them, and L:above(author, n) would send it everything
-- above n again in every exchange. So each LEV of mine notes, per peer, the highest
-- number of every author I hold stubs of that it carried (Sync:mark, from Sync:pump),
-- and Sync:tail leaves out what lies below that mark, except bodies that came to me
-- after the last exchange with that peer that acted on that author and sent all it
-- queued (L.came and self.since, memory only: J5).
-- The marks are kept in the ledger store (saved: a newcomer is not sent the same
-- bodies again in every session): store.hw[peer] = {at = my epoch at its last mark,
-- a = {[author] = n}}; at most LEDGER_HW_PEERS peers (a new one drops the oldest); a
-- load drops every malformed row and every row LEDGER_HW_KEEP s old. A partner that
-- holds nothing of the author (a new install) is sent L:above again, as before.
local Ledger, C, Util = ns.Ledger, ns.Const, ns.Util
local Sync = ns.LedgerSync
local byteLess, sorted, ZERO = Util.byteLess, Sync.sorted, ("0"):rep(12)

local function number(v) return type(v) == "number" and v >= 1 and v <= Ledger.ID_MAX and v == math.floor(v) end
-- The peers of `rows`, the newest mark first.
local function newest(rows)
  local peers = sorted(rows)
  table.sort(peers, function(p, q)
    if rows[p].at ~= rows[q].at then return rows[p].at > rows[q].at end
    return byteLess(p, q)
  end)
  return peers
end

-- The saved marks of ledger L, sound and bounded (they become L.store.hw) -> the rows.
function Sync.marks(L)
  local saved, now, out = L.store.hw, L.epoch(), {}
  for peer, row in pairs(type(saved) == "table" and saved or {}) do
    if Sync.name(peer) and type(row) == "table" and type(row.at) == "number" and row.at > now - C.LEDGER_HW_KEEP
      and row.at <= now + C.LEDGER_FUTURE and type(row.a) == "table" then
      out[peer] = { at = row.at, a = {} }
      for a, n in pairs(row.a) do if Sync.name(a) and number(n) then out[peer].a[a] = n end end
    end
  end
  local peers = newest(out)
  for j = C.LEDGER_HW_PEERS + 1, #peers do out[peers[j]] = nil end
  L.store.hw = out
  return out
end

-- Body b left for x's peer in a LEV: its number raises the mark of its author, when I hold stubs of it.
function Sync:mark(x, b)
  local a, k = Ledger.author(b.i)
  if not (a and self.L.sn[a]) then return end
  local rows = self.high
  if not rows[x.peer] then
    local peers = newest(rows)
    if #peers >= C.LEDGER_HW_PEERS then rows[peers[#peers]] = nil end
    rows[x.peer] = { a = {} }
  end
  local row = rows[x.peer]
  row.at, row.a[a] = self.L.epoch(), math.max(row.a[a] or 0, k)
end

-- Exchange x sent all it queued (Sync:finish): for each author it acted on, what came to
-- me before its x.rev0 (Sync:vector) is what its peer got or holds.
function Sync:sentAll(x)
  local since = self.since[x.peer] or {}
  self.since[x.peer] = since
  for a in pairs(x.rev0 and x.acted or {}) do since[a] = x.rev0 end
end

-- The bodies of author a that exchange x queues for a partner whose cell is t (nil: it
-- lacks a): L:above(a, n), less, when I hold stubs of a above n and it holds some of a,
-- the bodies at or below its mark that came to me before self.since[peer][a].
function Sync:tail(x, a, t)
  local L, n, row = self.L, t and t.n or 0, self.high[x.peer]
  local h = row and t and t.x ~= ZERO and L:stubTop(a) > n and row.a[a] or 0
  if h <= n then return L:above(a, n) end
  local out, since = {}, (self.since[x.peer] or {})[a] or 0
  for _, b in ipairs(L:above(a, n)) do
    if select(2, Ledger.author(b.i)) > h or (L.came[b] or 0) > since then out[#out + 1] = b end
  end
  return out
end
