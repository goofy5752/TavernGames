local _, ns = ...

-- The payer's guard against paying twice (core/Pay.lua): db.paySent[name] =
-- {at, c, paid, how}, saved per character, so it outlives a /reload and a
-- relog. It is written only when gold has left me for a creditor I owe
-- (Pay:sent): my side of a completed trade (Pay:traded) or a letter the game
-- says it sent (wow/Mail.lua), never when a trade is merely opened or a letter
-- filled. `paid` is what that creditor had recorded from me then; c the copper
-- that left (a second payment meanwhile adds to it). The guard is live while
-- the creditor's P entries since have not covered c and it is younger than
-- PAY_GUARD (24 h) for a trade, PAY_GUARD_MAIL (30 days: a letter with gold lies
-- in the box that long) for a letter; a dead one is dropped. While it is live
-- „Плати“ offers only what has not left yet (Pay:left).
local C, Names, View = ns.Const, ns.Names, ns.LedgerView
local Pay = ns.Pay
local floor, max = math.floor, math.max

local HOW = { trade = true, mail = true }
local function whole(v) return type(v) == "number" and v >= 0 and v == floor(v) end

-- My live guard for `name` -> {at, c (the copper not yet recorded), how} | nil.
function Pay:guard(name)
  local all = self.env.db.paySent
  local g = type(all) == "table" and all[name] or nil
  if g == nil then return nil end
  local sound = type(g) == "table" and whole(g.at) and whole(g.c) and whole(g.paid) and HOW[g.how] == true
  local open = sound and g.paid + g.c - View.paid(self:view(), self.env.me, name) or 0
  local life = sound and g.how == "mail" and C.PAY_GUARD_MAIL or C.PAY_GUARD
  if open <= 0 or self.env.epoch() - g.at >= life then
    all[name] = nil
    return nil
  end
  return { at = g.at, c = open, how = g.how }
end

-- Did gold of mine leave for `name` that no P of its has answered yet?
function Pay:waiting(name) return self:guard(name) ~= nil end

-- What I owe `name` that has not left me yet.
function Pay:left(name)
  local g = self:guard(name)
  return max(0, self:owed(name) - (g and g.c or 0))
end

-- Gold has left me: m = {name (a full name) | shown (a recipient as typed), c,
-- how = "trade" | "mail"}. Guarded when it went to exactly one name I owe
-- -> true | nil; "paySent"(name).
function Pay:sent(m)
  if type(m) ~= "table" or not (whole(m.c) and m.c >= 1) or not HOW[m.how] then return nil end
  local name, me = m.name, self.env.me
  if name == nil then
    local shown, fit = Names.normalize(m.shown), {}
    for _, a in ipairs(View.accounts(self:view(), me)) do
      if a.net > 0 and Names.matches(a.name, shown) then fit[#fit + 1] = a.name end
    end
    if #fit ~= 1 then return nil end
    name = fit[1]
  end
  if type(name) ~= "string" or self:owed(name) == 0 then return nil end
  local db, old = self.env.db, self:guard(name)
  if type(db.paySent) ~= "table" then db.paySent = {} end
  db.paySent[name] = { at = self.env.epoch(), c = (old and old.c or 0) + m.c,
    paid = View.paid(self:view(), me, name), how = m.how }
  self.client.events:emit("paySent", name)
  return true
end
