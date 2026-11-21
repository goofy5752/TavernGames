local _, ns = ...

-- The login queue of core/LedgerNet.lua, kept in the ledger store's saved
-- variables (store.pending), so a /reload or logout inside it keeps my entries
-- for my next login. The store is account-wide: each row names its owner (a =
-- the character), and a login makes only its own rows and leaves the others.
-- A row keeps its content key (the entry without i and at): at net:settle a
-- row is not made again when my store holds a body of mine above my saved seq
-- with that content (made before a crash, it has come back while I waited);
-- such a body still asked about is mine. One body stands for one row, and only
-- a live, undisputed one (not denied, no queued X of mine against it, not an asked twin).
local Ledger, Util = ns.Ledger, ns.Util
local Net = ns.LedgerNet

-- The content of an entry, in either form: its canonical form without i and at.
function Net.content(e)
  local w = Ledger.wire(e)
  w.i, w.at = nil, nil
  return Ledger.canon(w)
end

-- The saved rows {a, k, f, ck}, malformed ones dropped.
function Net:pending()
  local out, store = {}, self.L.store
  for _, q in ipairs(type(store.pending) == "table" and store.pending or {}) do
    if type(q) == "table" and type(q.a) == "string" and type(q.k) == "string" and type(q.f) == "table"
      and type(q.ck) == "string" then out[#out + 1] = q end
  end
  store.pending = out
  return out
end

-- Queues my entry of `kind` until the login queue closes.
function Net:queue(kind, fields)
  local e, rows = Util.copy(fields), self:pending()
  e.k = kind
  rows[#rows + 1] = { a = self.L.me, k = kind, f = Util.copy(fields), ck = Net.content(e) }
end

-- Closes the adoption window and the login queue: my queued entries are made,
-- unless they came back already. Again later: nothing more happens.
function Net:settle()
  if not self.running then return end
  local L = self.L
  L.adopting, self.waiting = false, false
  local mine, others, used = {}, {}, {}
  for _, q in ipairs(self:pending()) do
    local list = q.a == L.me and mine or others
    list[#list + 1] = q
  end
  L.store.pending = others
  -- Only a live, undisputed body of mine is "already made": not denied, no X of mine queued
  -- against it, not an asked twin.
  local disputed, back = {}, {}
  for _, q in ipairs(mine) do if q.k == "X" then disputed[tostring(q.f.r) .. "|" .. tostring(q.f.h)] = true end end
  for _, b in ipairs(L:above(L.me, self.saved)) do
    local twins = select(2, L:get(b.i))
    if not (L:denied(b) or disputed[b.i .. "|" .. b.h] or (b.un and twins and #twins > 0)) then back[#back + 1] = b end
  end
  for _, q in ipairs(mine) do
    local found
    for _, b in ipairs(back) do
      if not used[b] and Net.content(b) == q.ck then found = b; break end
    end
    if found then
      used[found] = true
      if found.un then found.un, L.rev, self.asked = nil, L.rev + 1, true; self:changed() end
    else
      local done, why = self:make(q.k, q.f)
      if not done and self.client.env.log then self.client.env.log("ledger", nil, nil, "not made: " .. tostring(why)) end
    end
  end
end
