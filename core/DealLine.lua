local _, ns = ...

-- The fairness line of the table frame (Deal.status, Deal.claim, Deal.alarm), split
-- out of core/Deal.lua; it reads only the session's fair state.
local Deal = ns.Deal
local contains = ns.Util.contains

-- The table frame's fairness line -> locale key, argument | nil: nil for an
-- engine without the extension "fair".
function Deal.status(s)
  if not contains(s:engine().ext or {}, "fair") then return nil end
  local fair = s.fair
  if fair and fair.stage == "commit" then
    for _, q in ipairs(fair.p) do
      local name = s.seats[q]
      if q ~= s.mySeat and fair.commits[q] == nil and name then return "fair.waiting", name end
    end
    return "fair.shuffle"
  elseif fair and fair.stage == "seed" then
    return "fair.dealing", fair.dealer
  end
  local last = s.fairLast
  if not last then return nil end
  if last.verdict == "void" then
    -- By name; with the count from the dealer's second one in this match.
    if not last.dealer then return "fair.void" end
    if (last.n or 1) > 1 then return "fair.voidMany", last.dealer, last.n end
    return "fair.voidBy", last.dealer
  end
  if last.verdict == "bad" and last.why == "announce" and last.who then return "fair.announce", last.who end
  return "fair.last", last.verdict
end

-- Another seat's complaint about the hand my line speaks of (the last one I
-- closed) -> name, why | nil. A claim, shown beside my own verdict; it ends
-- when the next hand closes.
function Deal.claim(s)
  local last, cry = s.fairLast, s.fairCry
  if cry and cry.name and cry.seat ~= s.mySeat and last and last.h ~= nil and last.h == cry.h then
    return cry.name, cry.why
  end
  return nil
end

-- Does the fairness line warn (red)? Only what my own client found: a bad
-- hand in this match, or a dealer who gave up or did not deal a second hand.
function Deal.alarm(s)
  local last, seen = s.fairLast, s.fairSeen
  for _, n in pairs(s.fairVoids or {}) do
    if n > 1 then return true end
  end
  return (last and last.verdict == "bad") or (seen and seen.bad > 0) or false
end
