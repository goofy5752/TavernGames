-- Independent Hold'em reference for tools/sim/holdem_soak.lua, written from the rules (Robert's Rules of
-- Poker, Poker TDA), not from engines/holdem_eval.lua or engines/holdem.lua:
--   R.rank5(faces)       -> the value of exactly five faces as a tuple {category, tie-break ranks...}
--   R.best(faces)        -> the best tuple of 5..7 faces (every 5-card subset), and the five faces it uses
--   R.cmp(a, b)          -> 1 / 0 / -1, tuples compared lexicographically
--   R.pots(order, total, live, scoreOf, button) -> refund, pots, won: the uncalled bet back, the main pot and
--                           the side pots by the all-in caps of the live hands, each split among its best
--                           hands, odd chips one by one from the first seat left of the button
local R = {}

local RV = { ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  T = 10, J = 11, Q = 12, K = 13, A = 14 }
R.RV = RV

-- categories: 1 high card, 2 pair, 3 two pair, 4 trips, 5 straight, 6 flush, 7 full house, 8 quads,
-- 9 straight flush (a royal flush is the ace-high one)
function R.rank5(f)
  local cnt, suit1, flush = {}, f[1]:sub(2, 2), true
  for i = 1, 5 do
    local r = RV[f[i]:sub(1, 1)]
    cnt[r] = (cnt[r] or 0) + 1
    if f[i]:sub(2, 2) ~= suit1 then flush = false end
  end
  local quads, trips, pairs, singles = {}, {}, {}, {}
  for r = 14, 2, -1 do
    local c = cnt[r]
    if c == 4 then quads[#quads + 1] = r
    elseif c == 3 then trips[#trips + 1] = r
    elseif c == 2 then pairs[#pairs + 1] = r
    elseif c == 1 then singles[#singles + 1] = r end
  end
  local top
  if #singles == 5 then
    if singles[1] - singles[5] == 4 then top = singles[1]
    elseif singles[1] == 14 and singles[2] == 5 and singles[3] == 4 and singles[4] == 3 and singles[5] == 2 then
      top = 5                                                  -- the wheel: the ace plays low
    end
  end
  local s = singles
  if top and flush then return { 9, top } end
  if #quads == 1 then return { 8, quads[1], s[1] } end
  if #trips == 1 and #pairs == 1 then return { 7, trips[1], pairs[1] } end
  if flush then return { 6, s[1], s[2], s[3], s[4], s[5] } end
  if top then return { 5, top } end
  if #trips == 1 then return { 4, trips[1], s[1], s[2] } end
  if #pairs == 2 then return { 3, pairs[1], pairs[2], s[1] } end
  if #pairs == 1 then return { 2, pairs[1], s[1], s[2], s[3] } end
  return { 1, s[1], s[2], s[3], s[4], s[5] }
end

function R.cmp(a, b)
  for i = 1, 6 do
    local x, y = a[i] or 0, b[i] or 0
    if x ~= y then return x > y and 1 or -1 end
  end
  return 0
end

-- every 5-card subset: the n - 5 cards left out, n = 5..7
function R.best(faces)
  local n, best, used = #faces, nil, nil
  local function try(skipA, skipB)
    local five = {}
    for i = 1, n do if i ~= skipA and i ~= skipB then five[#five + 1] = faces[i] end end
    local t = R.rank5(five)
    if not best or R.cmp(t, best) > 0 then best, used = t, five end
  end
  if n == 5 then try()
  elseif n == 6 then for a = 1, 6 do try(a) end
  else for a = 1, 6 do for b = a + 1, 7 do try(a, b) end end end
  return best, used
end

-- order: the hand's seats clockwise from the first left of the button (the button last);
-- total[seat]: chips the seat put in this hand; live[seat]: not folded; scoreOf(seat) -> tuple or nil (a
-- fold-win: the one live seat takes everything)
function R.pots(order, total, live)
  local t, refund = {}, {}
  local hi, hiSeat, second = -1, nil, -1
  for _, i in ipairs(order) do
    t[i] = total[i]
    if t[i] > hi then hi, hiSeat, second = t[i], i, hi
    elseif t[i] > second then second = t[i] end
  end
  if hiSeat and hi > second then            -- the part of the biggest bet nobody matched goes back
    refund[hiSeat] = hi - math.max(second, 0)
    t[hiSeat] = math.max(second, 0)
  end
  local caps, seen = {}, {}
  for _, i in ipairs(order) do
    if live[i] and t[i] > 0 and not seen[t[i]] then seen[t[i]] = true; caps[#caps + 1] = t[i] end
  end
  table.sort(caps)
  local pots, prev = {}, 0
  for _, c in ipairs(caps) do
    local amt, elig = 0, {}
    for _, i in ipairs(order) do
      amt = amt + math.min(t[i], c) - math.min(t[i], prev)
      if live[i] and t[i] >= c then elig[#elig + 1] = i end
    end
    pots[#pots + 1] = { amount = amt, eligible = elig }
    prev = c
  end
  local dead = 0                             -- folded chips above every live hand's cap (only a leave)
  for _, i in ipairs(order) do if t[i] > prev then dead = dead + t[i] - prev end end
  if dead > 0 and #pots == 0 then          -- the live hands put in nothing (everyone else left): all theirs
    local elig = {}
    for _, i in ipairs(order) do if live[i] then elig[#elig + 1] = i end end
    pots[1] = { amount = dead, eligible = elig }
  elseif dead > 0 then pots[#pots].amount = pots[#pots].amount + dead end
  return refund, pots
end

-- splits the pots: scores[seat] = tuple (nil for a fold-win) -> won[seat], pots with winners
function R.award(pots, scores)
  local won = {}
  for _, pot in ipairs(pots) do
    local winners = {}
    if scores then
      local best
      for _, i in ipairs(pot.eligible) do
        if not best or R.cmp(scores[i], best) > 0 then best = scores[i] end
      end
      for _, i in ipairs(pot.eligible) do if R.cmp(scores[i], best) == 0 then winners[#winners + 1] = i end end
    else
      for _, i in ipairs(pot.eligible) do winners[#winners + 1] = i end
    end
    pot.winners = winners
    local share = math.floor(pot.amount / #winners)
    local odd = pot.amount - share * #winners
    for k, i in ipairs(winners) do               -- eligible is in seat order from left of the button
      won[i] = (won[i] or 0) + share + (k <= odd and 1 or 0)
    end
  end
  return won
end

return R
