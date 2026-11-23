local _, ns = ...

-- What goes of an author's tail in an exchange of core/LedgerSync.lua (F4, Decision R; J1 a, J5,
-- Ruling F4-F). A newcomer never gets the bodies I hold only as stubs, so its n stays below
-- them and L:above(author, n) would resend it all every time. Each LEV notes the highest number
-- it carried of an author I hold stubs of (Sync:mark). Sync:tail leaves out what is at or below
-- the peer's mark and came to me before the last heard exchange that acted on its author
-- (L.came, self.since: memory, J5), unless that one queued and did not send it (self.owe):
-- an R or S for good, any other kind (D, C, N, P, X) to be re-sent last (core/LedgerSyncAgain.lua).
-- Heard: both f, not capped; cut or not, it commits its marks to the ledger store (never above
-- an entry it queued and did not send): store.hw[peer] = {at = my epoch at the row's first
-- commit (kept), a = {[author] = n}}, gone LEDGER_HW_KEEP s after it, at most LEDGER_HW_PEERS
-- rows (a new one drops the oldest); a load drops malformed rows and cells and an author's I
-- hold no stub of. A partner that holds nothing of the author (a new install) is sent L:above,
-- and its mark of that author goes.
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

-- Exchange x ended (Sync:finish; capped: at LEDGER_EX_MAX or the page cap). Heard: what came to me
-- before its x.rev0 is what the peer got or holds, of each author it acted on, save what it
-- queued and did not send (owed, and no mark of it reaches that); its marks are committed.
function Sync:ended(x, capped)
  local peer = x.peer
  if not (x.fMine and x.fTheirs) or capped then self.rot[peer] = (self.rot[peer] or 0) + (x.went or 0); return end
  local since, owe = self.since[peer] or {}, self.owe[peer] or setmetatable({}, { __mode = "k" })
  self.since[peer], self.owe[peer] = since, owe
  for a in pairs(x.rev0 and x.acted or {}) do since[a] = x.rev0 end
  for _, b in ipairs(x.left) do owe[b] = nil end
  for _, list in ipairs({ x.rest or {}, x.q }) do
    for _, b in ipairs(list) do
      local a, k = Ledger.author(b.i)
      if x.re[b] then x.acted[a] = nil else owe[b] = true end -- a re-sent one waits its turn (Sync:resend)
      if not x.re[b] and x.hw[a] and x.hw[a] >= k then x.hw[a] = k - 1 end
    end
  end
  self:carried(x)
  if not next(x.hw) then return end
  local row = self:row(peer, true)
  for a, k in pairs(x.hw) do row.a[a] = math.max(row.a[a] or 0, k) end
end

-- The bodies of author a that exchange x queues for a partner whose cell is t (nil: it lacks a):
-- L:above(a, n); when I hold stubs of a above n, less what Sync:ended lets me leave out -> those,
-- and the D, C, N, P and X among the left out that are due again (Sync:resend).
function Sync:tail(x, a, t)
  local L, n, peer = self.L, t and t.n or 0, x.peer
  local row = self:row(peer)
  if row and (not t or t.x == ZERO) then row.a[a] = nil end -- it holds nothing of a: my mark of a is wrong
  local h = t and t.x ~= ZERO and L:stubTop(a) > n and row and row.a[a] or 0
  if h <= n then return L:above(a, n) end
  local since, owe, came, again = (self.since[peer] or {})[a] or 0, self.owe[peer] or {}, L.came, {}
  return L:above(a, n, function(k, b)
    if k > h or (came[b] or 0) > since or owe[b] == true then return true end
    if b.k ~= "R" and b.k ~= "S" and self:due(peer, b) then again[#again + 1] = b end
    return false
  end), again
end
