local _, ns = ...

-- The second pass of an exchange's queue (F4 final review, Ruling F4-F). Under stubs a peer's n
-- cannot rise, so a D, C, N, P or X at or below its mark is never left out for good: Sync:tail
-- gives those apart and they are re-sent, but behind everything no mark covers, of every author
-- (the last x.nre entries of x.q; Sync:queue puts what comes later before them), turned by a
-- per-peer cursor (self.rot: how many of them left for that peer in exchanges that were not
-- heard), so that exchanges cut at LEDGER_EXCHANGE_MAX walk through all of them and none sends
-- only what the last one sent. What a heard exchange (both f, not capped) carried is not re-sent
-- to that peer for LEDGER_REFUSED_TTL s (self.got: memory, so my next session sends each once
-- more; nothing is acknowledged, so "carried" is as sure as Sync:ended's marks). An exchange
-- cut with only re-sent entries left counts as complete (x.cut, Sync:pump), but an author with
-- some of them left is not noted by Sync:fixed (Sync:ended takes it out of x.acted).
local Ledger, C = ns.Ledger, ns.Const
local Sync = ns.LedgerSync

-- Body b left for x's peer in a LEV (Sync:pump): x.left, x.hw[author] when I hold
-- stubs of it (the marks, core/LedgerSyncTail.lua), and one re-sent entry fewer waits in x.q.
function Sync:mark(x, b)
  local a, k = Ledger.author(b.i)
  x.left[#x.left + 1] = b
  if x.re[b] then x.nre, x.went = x.nre - 1, (x.went or 0) + 1 end
  if a and self.L.sn[a] then x.hw[a] = math.max(x.hw[a] or 0, k) end
end

-- Is body b, left out by a mark of `peer`, due to be sent it again?
function Sync:due(peer, b)
  local at = (self.got[peer] or {})[b]
  return not at or self.client.env.now() - at >= C.LEDGER_REFUSED_TTL
end

-- The re-sent entries Sync:tail gave exchange x (x.ag) join its queue, last, from the cursor on.
function Sync:resend(x)
  local list, n = x.ag, #x.ag
  local cur = n > 0 and (self.rot[x.peer] or 0) % n or 0
  for j = 1, n do
    local b = list[(cur + j - 1) % n + 1]
    if not x.qs[b] then x.qs[b], x.re[b], x.q[#x.q + 1], x.nre = true, true, b, x.nre + 1 end
  end
  x.ag = {}
end

-- Exchange x ended, heard (Sync:ended): every D, C, N, P and X that left in it is taken as carried.
function Sync:carried(x)
  local got, now = self.got[x.peer] or setmetatable({}, { __mode = "k" }), self.client.env.now()
  self.got[x.peer] = got
  for _, b in ipairs(x.left) do if b.k ~= "R" and b.k ~= "S" then got[b] = now end end
end

return Sync
