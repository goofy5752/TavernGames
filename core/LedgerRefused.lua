local _, ns = ...

-- The entries my client refused (Net:take: a name my guild roster does not
-- list, an author's clock too far ahead, a full author, a fifth twin, a kind or
-- a shape this version does not know): store.rf[author]["<n>.<h>"] = the epoch
-- it is forgotten at (LEDGER_REFUSED_TTL after the refusal; a clock refusal as
-- soon as its time has come), saved with the store. While remembered my vector
-- counts it as held (core/LedgerHash.lua: x hashes its "<id>:<h>", n runs
-- through its number where that fills a hole, a LID lists it), so a partner
-- that holds it sees no difference and does not send its author's tail again.
-- It is no entry: never in the view, never relayed. Offered again all the same
-- (a live LEV, or the next exchange once it is forgotten) it is taken if it
-- has become acceptable. The fifth twin of an id is not remembered: every
-- client drops the same one. Bounded: LEDGER_REFUSED_MAX per author,
-- LEDGER_REFUSED_AUTHORS authors; past a bound nothing more is remembered (then
-- the sync's own note of exchanges that changed nothing, Sync:fixed, stops the
-- resends). An entry of a kind or shape my version does not know hashes here
-- to another h than on its holder, so the two never agree on that author: they
-- settle on exchanging their vectors only (Sync:fixed again).
local Ledger, C = ns.Ledger, ns.Const
local Store, Net = Ledger.Store, ns.LedgerNet

local function hex16(v) return type(v) == "string" and #v == 16 and v:find("^[0-9a-f]+$") ~= nil end
local function named(a) return type(a) == "string" and a ~= "" and #a <= 64 and not a:find("[|,]") end
local function whole(v) return type(v) == "number" and v == math.floor(v) end

-- After a load: the saved set, malformed and expired rows dropped; L.rn[author][n] = how many refused bodies.
function Store:refusedLoad()
  local saved, now, out = self.store.rf, self.epoch(), {}
  self.rn, self.rfAuthors = {}, 0
  for a, set in pairs(type(saved) == "table" and saved or {}) do
    for it, till in pairs(named(a) and type(set) == "table" and set or {}) do
      local n, h = tostring(it):match("^([1-9]%d*)%.(%x+)$")
      if n and #n <= 9 and hex16(h) and whole(till) and till > now and till <= now + C.LEDGER_REFUSED_TTL then
        out[a] = out[a] or {}
        out[a][it] = till
        self.dirty[a] = true -- its x is to be hashed, as after any load (an author of whom I hold no body, too)
        self:refusedCount(a, tonumber(n), 1)
      end
    end
  end
  self.store.rf = out
end

function Store:refusedCount(a, n, d)
  local rn = self.rn[a]
  if not rn then rn = {}; self.rn[a] = rn; self.rfAuthors = self.rfAuthors + 1 end
  rn[n] = (rn[n] or 0) + d
  if rn[n] <= 0 then rn[n] = nil end
  if next(rn) == nil then self.rn[a], self.store.rf[a], self.rfAuthors = nil, nil, self.rfAuthors - 1 end
end

-- Do I remember refusing body (a, n) with hash h?
function Store:refused(a, n, h)
  local set = self.store.rf[a]
  local till = set and set[n .. "." .. h]
  return till ~= nil and till > self.epoch()
end

-- Remembers the refusal of (a, n, h) until `till` (default: LEDGER_REFUSED_TTL from now) -> true | false (a bound).
function Store:refuse(a, n, h, till)
  local rf, now = self.store.rf, self.epoch()
  if not (named(a) and hex16(h)) then return false end
  local set, it = rf[a], n .. "." .. h
  if set and set[it] then return true end
  local count = 0
  for _ in pairs(set or {}) do count = count + 1 end
  if count >= C.LEDGER_REFUSED_MAX or (not set and self.rfAuthors >= C.LEDGER_REFUSED_AUTHORS) then return false end
  rf[a] = set or {}
  rf[a][it] = math.max(now + 1, math.min(till or math.huge, now + C.LEDGER_REFUSED_TTL))
  self:refusedCount(a, n, 1)
  self.rev = self.rev + 1
  self:stale(a)
  return true
end

-- Forgets the refusal of (a, n, h) (it was taken after all), or every refusal that has expired (no arguments).
function Store:forget(a, n, h)
  local rf, now = self.store.rf, self.epoch()
  for author, set in pairs(a and { [a] = rf[a] } or rf) do
    for it, till in pairs(set) do
      if (a and it == n .. "." .. h) or (not a and till <= now) then
        set[it] = nil
        self:refusedCount(author, tonumber(it:match("^%d+")), -1)
        self.rev = self.rev + 1
        self:stale(author)
      end
    end
  end
end

-- The refused bodies of author a as {n, h}, in no order.
function Store:refusals(a)
  local out = {}
  for it in pairs(self.store.rf[a] or {}) do
    local n, h = it:match("^(%d+)%.(%x+)$")
    out[#out + 1] = { n = tonumber(n), h = h }
  end
  return out
end

-- Entry e of `author`, number n, was not taken: remembered (see the header), when
-- its fields are plain enough to hash (Ledger.plain) -> nil.
function Net:refuse(e, author, n)
  if not Ledger.plain(e) then return nil end
  local at = type(e.at) == "number" and e.at or nil
  local late = at and at > self.L.epoch() + C.LEDGER_FUTURE and at - C.LEDGER_FUTURE or nil -- only its clock is ahead
  self.L:refuse(author, n, Ledger.hash(e), late)
  return nil
end

-- Once an hour: the refusals that have expired are forgotten (my vector changes with them).
function Net:sweep()
  self.L:forget()
  self:arm("sweepTimer", 3600, Net.sweep)
end
