-- Hold'em hand evaluator (pure Lua 5.1). Faces are 2-char strings: rank 2-9 T J Q K A + suit C D H S.
-- H.best(faces) takes 5..7 faces and returns score, category, pick:
--   score    a number, higher = better; equal scores split the pot. score = category * 15^5 + the
--            tie-break ranks in base 15 (most significant first).
--   category 1 high card, 2 pair, 3 two pair, 4 trips, 5 straight, 6 flush, 7 full house, 8 quads,
--            9 straight flush (royal flush = ace-high straight flush).
--   pick     the input positions of the five cards used (ascending).
-- Tie-breaks: straight / straight flush by the top card (wheel A-2-3-4-5 counts 5 high, also the steel
-- wheel); quads, full house, trips, two pair, pair by the grouped ranks then the kickers; high card and
-- flush by all five ranks. Suits never break a tie.
local _, ns = ...

local H = { HIGH = 1, PAIR = 2, TWOPAIR = 3, TRIPS = 4, STRAIGHT = 5, FLUSH = 6, FULL = 7, QUADS = 8, SFLUSH = 9 }
H.NAMES = { "high", "pair", "twopair", "trips", "straight", "flush", "full", "quads", "straightflush" }
ns.HoldemEval = H

local RANKS = { ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  T = 10, J = 11, Q = 12, K = 13, A = 14 }
local SUITS = { C = true, D = true, H = true, S = true }

function H.valid(face)
  return type(face) == "string" and #face == 2 and RANKS[face:sub(1, 1)] ~= nil and SUITS[face:sub(2, 2)] == true
end
function H.rank(face) return RANKS[face:sub(1, 1)] end
function H.suit(face) return face:sub(2, 2) end

local function encode(cat, ks)
  local v = cat
  for i = 1, 5 do v = v * 15 + (ks[i] or 0) end
  return v
end

-- score of exactly five faces
function H.rank5(f)
  local r, flush = {}, true
  local s1 = H.suit(f[1])
  for i = 1, 5 do
    r[i] = H.rank(f[i])
    if H.suit(f[i]) ~= s1 then flush = false end
  end
  table.sort(r, function(a, b) return a > b end)
  local distinct = true
  for i = 2, 5 do if r[i] == r[i - 1] then distinct = false end end
  local top
  if distinct then
    if r[1] - r[5] == 4 then top = r[1]
    elseif r[1] == 14 and r[2] == 5 then top = 5 end   -- wheel A-2-3-4-5
  end
  if top then
    local cat = flush and H.SFLUSH or H.STRAIGHT
    return encode(cat, { top }), cat
  end
  if flush then return encode(H.FLUSH, r), H.FLUSH end
  -- group ranks: by count desc, then rank desc (r is already rank desc)
  local groups = {}
  for i = 1, 5 do
    local g = groups[#groups]
    if g and g.r == r[i] then g.n = g.n + 1 else groups[#groups + 1] = { r = r[i], n = 1 } end
  end
  table.sort(groups, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.r > b.r end)
  local ks = {}
  for i, g in ipairs(groups) do ks[i] = g.r end
  local n1, n2 = groups[1].n, groups[2].n
  local cat
  if n1 == 4 then cat = H.QUADS
  elseif n1 == 3 and n2 == 2 then cat = H.FULL
  elseif n1 == 3 then cat = H.TRIPS
  elseif n1 == 2 and n2 == 2 then cat = H.TWOPAIR
  elseif n1 == 2 then cat = H.PAIR
  else cat = H.HIGH end
  return encode(cat, ks), cat
end

-- best five of 5..7 faces
function H.best(faces)
  local n = #faces
  local bestScore, bestCat, bestPick = -1, nil, nil
  local pick, five = {}, {}
  local function rec(start, depth)
    if depth > 5 then
      for i = 1, 5 do five[i] = faces[pick[i]] end
      local sc, cat = H.rank5(five)
      if sc > bestScore then
        bestScore, bestCat = sc, cat
        bestPick = { pick[1], pick[2], pick[3], pick[4], pick[5] }
      end
      return
    end
    for i = start, n - (5 - depth) do
      pick[depth] = i
      rec(i + 1, depth + 1)
    end
  end
  rec(1, 1)
  return bestScore, bestCat, bestPick
end

return H
