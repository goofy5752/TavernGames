-- Белот (Bulgarian Belot), 4 seats, teams 1+3 vs 2+4, match to 151.
-- The rules are a port of NikolayIT/BelotGameEngine (MIT, see LICENSE-THIRD-PARTY.md),
-- src/Belot.Engine at commit a4a6e4d; tests/engines/belot_test.lua replays matches the C#
-- engine played (tools/belot-parity) and compares every decision and score.
--
-- RULES
--  1. Deck: 32 cards, ranks 7 8 9 T J Q K A, suits C D H S. Seats 1..4 sit in turn order
--     (1 South, 2 East, 3 North, 4 West in the C# engine); teams: 1 = seats 1+3, 2 = seats 2+4.
--  2. Deal ({k="deal", deck=...} at seat 0): deck[1..20] go one at a time to seats 1,2,3,4,
--     1,2,... (five each), always starting at seat 1. After the auction ends in a contract,
--     deck[21..32] go the same way (three each). A passed-out deal never deals them.
--  3. `first` bids first and leads the first trick; it moves to the next seat after every
--     deal, passed-out ones included.
--  4. Auction ({k="bid", b=...}): contracts rank C < D < H < S < N (Без коз) < A (Всичко коз);
--     a bid must be higher than the contract so far. "P" passes. "X" (контра) is open to the
--     opponents of the declarer on an undoubled contract, "R" (реконтра) to the declarer's
--     team on a doubled one; both leave the contract with the declarer. A higher contract may
--     still be bid over a doubled or redoubled one and clears the doubling.
--  5. The auction ends after 4 passes in a row when nobody has bid (passed out: nobody scores,
--     the hanging points stay) or after 3 passes in a row once there is a contract.
--  6. Card order, weakest first: trump 7 8 Q K T A 9 J; plain 7 8 9 J Q K T A.
--     Card points: trump J 20, 9 14, A 11, T 10, K 4, Q 3; plain A 11, T 10, K 4, Q 3, J 2.
--     In A every suit is trump, in N none.
--  7. Tricks ({k="play", i=, c=, b=}): the leader plays anything; a seat with one card plays
--     it. Otherwise:
--     a. N: follow the led suit if you can, else anything.
--     b. A, or a suit contract when trump is led: follow the led suit, and with a card of it
--        higher than every card of that suit in the trick you must play higher (also over
--        your partner); without the suit, anything.
--     c. Suit contract, plain suit led: follow suit (any card of it). Without it: with no
--        trump, anything; if your partner's card is winning the trick so far, anything;
--        if a trump was played, a higher trump if you have one, else anything; if no trump
--        was played, any trump.
--  8. Trick winner: the highest trump played (suit contract), else the highest card of the
--     led suit (trump order in A, plain order otherwise). The winner leads the next trick.
--  9. Announces ({k="ann", a={{t=, i=}, ...}}), not in N, only in the first trick, at your
--     turn before your card: sequences in one suit in the order 7 8 9 T J Q K A — "s3"
--     терца 20, "s4" кварта 50, "s5".."s8" квинта 100 (a longer run is one announce) — and
--     four of a kind: "c" T/Q/K/A 100, "c9" 150, "cJ" 200 (7s and 8s do not count). `i` is
--     the deck index of the top card (of the spade for a four of a kind). A card takes part
--     in one announce only: the offered list is the fours, then the sequences of the other
--     cards, then the sequences through a four's card (declared instead of that four).
-- 10. Which announces score (settled when the deal is scored): among the fours the best
--     one decides — it and every four of the same team score. Among the sequences likewise,
--     except that when the best sequence is matched by an equal one of the other team no
--     sequence scores at all. Order: more points, then longer (s8 > s7 > s6 > s5), then the
--     top card (trump order for fours, 7..A for sequences; suits do not matter).
-- 11. Белот 20 (flag b on the play): playing the K or Q while holding the other one of the
--     same suit; suit contract: the trump suit only; A: when leading, or when the suit is
--     the led one; never in N. Always scores.
-- 12. Deal score ({k="score"} at seat 0 after the 8th trick). Team total = card points +
--     scoring announces + 10 for the last trick; in N the total is doubled; a team that took
--     all eight tricks (валат) gets +90 after that.
-- 13. Rounding to game points: A: total/10, remainder > 4 rounds up, == 4 rounds up only
--     for the team with the smaller total; suit: the same with 6; N and every "вътре" sum:
--     to the nearest, a remainder of 5 to the even number (C# Math.Round).
-- 14. Undoubled: declarer's total > the other: both teams score their rounded totals, the
--     declarer's team also takes the hanging points. Smaller („вътре“): the defenders score
--     the rounded sum of both totals plus the hanging points. Equal („висяща“): the
--     defenders score their rounded total, the declarer's rounded total is added to the
--     hanging points.
-- 15. Doubled (x2) / redoubled (x4): the team with the bigger total scores the rounded sum
--     of both totals times the multiplier, plus the hanging points; on equal totals all of
--     that hangs.
-- 16. Match: after a deal a team wins when it has 151+ and more than the other team and it
--     scored in that deal, unless the deal was a валат („с капо не се излиза“) or passed out.
-- 17. Leaving ends the match; the leaver's team loses.
--
-- Cards live in state.deck (deck index -> face); hands, tricks and announces hold deck
-- indices. E.view hides every face a seat may not see: it sees its own hand, the current
-- trick and the last taken trick, and everything once the eight tricks are played or the
-- match is over.

local _, ns = ...
ns.Engines = ns.Engines or {}

local E = { id = "belot", minSeats = 4, maxSeats = 4, TARGET = 151, options = {} }
ns.Engines.belot = E

local SUITS = { "C", "D", "H", "S" }
local RANKS = { "7", "8", "9", "T", "J", "Q", "K", "A" }
local RANK = {}
for r, ch in ipairs(RANKS) do RANK[ch] = r end

-- The unshuffled deck, in the C# engine's Card.AllCards order.
E.DECK = {}
local IS_FACE = {}
for _, su in ipairs(SUITS) do
  for _, ch in ipairs(RANKS) do
    E.DECK[#E.DECK + 1] = ch .. su
    IS_FACE[ch .. su] = true
  end
end

local BIDS = { "C", "D", "H", "S", "N", "A" }
local BID_RANK = { C = 1, D = 2, H = 3, S = 4, N = 5, A = 6 }

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function isSeat(seat) return seat == 1 or seat == 2 or seat == 3 or seat == 4 end
local function nextSeat(seat) return seat % 4 + 1 end
local function teamOf(seat) return 2 - seat % 2 end

function E.new(opts)
  local first = opts and opts.first
  if not isSeat(first) then first = 1 end
  return {
    phase = "deal", round = 1, first = first, turn = nil,
    deck = {}, hands = { {}, {}, {}, {} },
    bids = {}, contract = nil, passes = 0,
    score = { 0, 0 }, hang = 0, res = nil,
    winner = nil, left = nil, open = false,
  }
end

---------------------------------------------------------------------------------------------
-- Deal
---------------------------------------------------------------------------------------------

-- A deal action's deck: nil (nothing known, a view), or up to 32 distinct faces.
local function checkDeck(deck)
  if deck == nil then return {} end
  if type(deck) ~= "table" then return nil end
  local out, seen = {}, {}
  for i, face in pairs(deck) do
    if type(i) ~= "number" or i < 1 or i > 32 or i % 1 ~= 0 then return nil end
    if not IS_FACE[face] or seen[face] then return nil end
    seen[face] = true
    out[i] = face
  end
  return out
end

local function dealCards(s, from, to)
  for j = from, to do
    local hand = s.hands[(j - 1) % 4 + 1]
    hand[#hand + 1] = j
  end
end

local function applyDeal(s, seat, a)
  if seat ~= 0 then return nil, "seat" end
  if s.phase ~= "deal" then return nil, "phase" end
  local deck = checkDeck(a.deck)
  if not deck then return nil, "deck" end
  s.deck = deck
  s.hands = { {}, {}, {}, {} }
  dealCards(s, 1, 20)
  s.bids, s.contract, s.passes = {}, nil, 0
  s.open = false
  s.phase, s.turn = "bid", s.first
  return true
end

---------------------------------------------------------------------------------------------
-- Auction
---------------------------------------------------------------------------------------------

local function availableBids(s, seat)
  local c = s.contract
  local top = c and BID_RANK[c.b] or 0
  local out = { "P" }
  for _, b in ipairs(BIDS) do
    if BID_RANK[b] > top then out[#out + 1] = b end
  end
  if c and c.x ~= 4 then
    local declaring = teamOf(seat) == teamOf(c.seat)
    if c.x == 2 then
      if declaring then out[#out + 1] = "R" end
    elseif not declaring then
      out[#out + 1] = "X"
    end
  end
  return out
end

local function nextDeal(s)
  s.round = s.round + 1
  s.first = nextSeat(s.first)
  s.phase, s.turn = "deal", nil
end

local function startPlay(s)
  dealCards(s, 21, 32)
  s.phase, s.turn = "play", s.first
end

local function applyBid(s, seat, a)
  if not isSeat(seat) then return nil, "seat" end
  if s.phase ~= "bid" then return nil, "phase" end
  if s.turn ~= seat then return nil, "turn" end
  local b, allowed = a.b, false
  for _, x in ipairs(availableBids(s, seat)) do
    if x == b then allowed = true break end
  end
  if not allowed then return nil, "bid" end
  if b == "X" then
    s.contract.x = 2
  elseif b == "R" then
    s.contract.x = 4
  elseif b ~= "P" then
    s.contract = { seat = seat, b = b, x = 1 }
  end
  s.bids[#s.bids + 1] = { s = seat, b = b }
  s.passes = b == "P" and s.passes + 1 or 0
  if not s.contract and s.passes == 4 then
    -- passed out: nobody scores, the hanging points wait for the next played deal
    s.res = { round = s.round, raw = { 0, 0 }, pts = { 0, 0 }, hang = s.hang, valat = false, ann = {} }
    nextDeal(s)
  elseif s.contract and s.passes == 3 then
    startPlay(s)
  else
    s.turn = nextSeat(seat)
  end
  return true
end

---------------------------------------------------------------------------------------------
-- Faces on a view
---------------------------------------------------------------------------------------------

local function applyShow(s, seat, a)
  if seat ~= 0 then return nil, "seat" end
  if type(a.cards) ~= "table" then return nil, "action" end
  local at = {}
  for i, face in pairs(s.deck) do at[face] = i end
  for i, face in pairs(a.cards) do
    if type(i) ~= "number" or i < 1 or i > 32 or i % 1 ~= 0 or not IS_FACE[face] then
      return nil, "card"
    end
    if (s.deck[i] or face) ~= face or (at[face] or i) ~= i then return nil, "card" end
    at[face] = i
  end
  for i, face in pairs(a.cards) do s.deck[i] = face end
  return true
end

function E.view(s, seat)
  local v = copy(s)
  if s.phase == "match" or s.open then return v end
  local keep = {}
  if isSeat(seat) then
    for _, i in ipairs(s.hands[seat]) do keep[i] = true end
  end
  for i = 1, 32 do
    if not keep[i] then v.deck[i] = nil end
  end
  return v
end

function E.hidden(s, seat)
  if not isSeat(seat) or s.phase == "match" or s.open then return {} end
  return copy(s.hands[seat])
end

---------------------------------------------------------------------------------------------

function E.apply(s, seat, a)
  if type(a) ~= "table" then return nil, "action" end
  local k = a.k
  if k == "deal" then return applyDeal(s, seat, a) end
  if k == "bid" then return applyBid(s, seat, a) end
  if k == "show" then return applyShow(s, seat, a) end
  return nil, "action"
end

function E.legal(s, seat)
  local out = {}
  if not isSeat(seat) or s.turn ~= seat then return out end
  if s.phase == "bid" then
    for _, b in ipairs(availableBids(s, seat)) do out[#out + 1] = { k = "bid", b = b } end
  end
  return out
end

function E.system(s)
  if s.phase == "deal" then return { k = "deal" }, s.res and 5 or 0 end
end

function E.over(s) return s.phase == "match" end

function E.snapshot(s) return copy(s) end
function E.restore(t) return copy(t) end

return E
