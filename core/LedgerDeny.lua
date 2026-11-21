local _, ns = ...

-- Denials of the ledger store (core/LedgerStore.lua). A body is denied when
-- an X of its author names it (e.i and e.h) and that X is not denied in turn,
-- recursively. The deny index holds only an X whose author is its target's
-- author (Ledger.valid), so it is that body's deniers. The graph is walked with
-- an explicit stack (no recursion, no depth limit), and every node it settles
-- is memoised until the store changes (L.rev): one sweep over every body costs
-- one visit per node (L.visits counts them). A cycle can only come from
-- tampered saved variables: a denier met again while it is still being settled
-- counts as standing there, so the answer then depends on the query order.
local Store = ns.Ledger.Store

local function key(b) return b.i .. "|" .. b.h end

-- Is the body under key k denied -> bool.
local function settle(self, k)
  local memo, deny = self.memo, self.deny
  if memo[k] ~= nil then return memo[k] end
  local open = { [k] = true }
  local stack = { { k = k, list = {}, at = 1 } }
  for x in pairs(deny[k] or {}) do stack[1].list[#stack[1].list + 1] = x end
  self.visits = (self.visits or 0) + 1
  while #stack > 0 do
    local top = stack[#stack]
    local result, push = false, nil
    while top.at <= #top.list do
      local dk = key(top.list[top.at])
      local v = memo[dk]
      if v == nil and open[dk] then v = false end
      if v == nil then push = dk; break end
      if v == false then result = true; break end -- a standing X of the author: denied
      top.at = top.at + 1
    end
    if push then
      local frame = { k = push, list = {}, at = 1 }
      for x in pairs(deny[push] or {}) do frame.list[#frame.list + 1] = x end
      open[push], stack[#stack + 1] = true, frame
      self.visits = (self.visits or 0) + 1
    else
      memo[top.k], open[top.k], stack[#stack] = result, nil, nil
    end
  end
  return memo[k]
end

-- Did e's author deny exactly this body, by an X that stands?
function Store:denied(e)
  if e.h == nil then return false end
  if self.memoRev ~= self.rev then self.memo, self.memoRev = {}, self.rev end
  return settle(self, key(e))
end
