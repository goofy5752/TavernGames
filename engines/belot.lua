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
--     deal, passed-out and annulled ones included. The dealer is the seat before `first`.
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
--     defenders score their total rounded as the bigger one, the declarer's total rounded
--     as the smaller one is added to the hanging points.
-- 15. Doubled (x2) / redoubled (x4): the team with the bigger total scores the sum of both
--     totals, rounded by the contract's rule as a bigger total, times the multiplier, plus
--     the hanging points; on equal totals all of that hangs.
-- 16. Match: after a deal a team wins when it has 151+ and more than the other team and it
--     scored in that deal, unless the deal was a валат („с капо не се излиза“) or passed out.
-- 17. Leaving ends the match; the leaver's team loses.
--
-- STATE AND ACTIONS
-- Cards live in state.deck (deck index -> face); hands, tricks and announces hold deck
-- indices. E.view hides every face a seat may not see: it sees its own hand; in the tricks
-- also every card in no hand (the cards played in this deal, so a latecomer can score the
-- announces); everything once the eight tricks are played or the match is over. state.full
-- is true on the state E.new makes and false on every view (a view with the whole deck and
-- full = true is the state).
--   phase "deal":  seat 0 {k="deal", deck=...}: on a full state all 32 faces at 1..32, on a
--                  view any subset or none                                       -> "bid"
--   phase "bid":   the seat on turn {k="bid", b="P"|"C"|"D"|"H"|"S"|"N"|"A"|"X"|"R"}
--                  -> "play", or "deal" again when passed out
--   phase "play":  the seat on turn, optionally once in the first trick before its card,
--                  {k="ann", a={{t="s3".."s8"|"c"|"c9"|"cJ", i=deck index}, ...}}, then
--                  {k="play", i=deck index, c=face, b=true for a belote}         -> "score"
--   phase "score": seat 0 {k="score"} (a view must have been shown the announces' cards;
--                  E.view shows everything by now)                    -> "deal" or "match"
--   any phase:     seat 0 {k="show", cards={[deck index]=face}} fills faces on a view
--   "bid", "play", "score": seat 0 {k="void"} annuls the deal: nothing scores, `first` moves
--                  on (as after a passed-out deal), res is cleared           -> "deal"
-- At the table: extension "fair" (core/Deal.lua) shuffles and deals; E.dealer names the
-- seat that deals the next round. E.again: once a match is over the host may start a new
-- one; E.nextFirst keeps the deal going round (the previous loser does not lead).
-- state.res is the last deal's result: raw (team totals), pts (game points), hang, valat,
-- contract (nil when passed out), ann (every announce with its points v and whether it
-- scored, on). state.score, state.hang, state.winner (team) and state.left (the seat that
-- left) describe the match.

local _, ns = ...
ns.Engines = ns.Engines or {}

local E = { id = "belot", minSeats = 4, maxSeats = 4, TARGET = 151, options = {}, ext = { "fair" }, again = true }
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

-- by rank 7 8 9 T J Q K A
local TRUMP_ORDER = { 1, 2, 7, 5, 8, 3, 4, 6 }
local PLAIN_ORDER = { 1, 2, 3, 7, 4, 5, 6, 8 }
local TRUMP_VALUE = { 0, 0, 14, 10, 20, 3, 4, 11 }
local PLAIN_VALUE = { 0, 0, 0, 10, 2, 3, 4, 11 }

local ANN_VALUE = { b = 20, s3 = 20, s4 = 50, s5 = 100, s6 = 100, s7 = 100, s8 = 100, c = 100, c9 = 150, cJ = 200 }

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function isSeat(seat) return seat == 1 or seat == 2 or seat == 3 or seat == 4 end
local function nextSeat(seat) return seat % 4 + 1 end
local function teamOf(seat) return 2 - seat % 2 end
local function rankOf(face) return RANK[face:sub(1, 1)] end
local function suitOf(face) return face:sub(2, 2) end

-- The faces of a list of deck indices, or nil when one of them is unknown (a view).
local function facesOf(s, list)
  local out = {}
  for n, i in ipairs(list) do
    if not s.deck[i] then return nil end
    out[n] = s.deck[i]
  end
  return out
end

local function resetPlay(s)
  s.trick, s.lead, s.trickNo, s.last = {}, nil, 0, nil
  s.pts, s.took, s.lastWin = { 0, 0 }, { 0, 0 }, nil
  s.ann, s.announced = {}, false
end

function E.new(opts)
  local first = opts and opts.first
  if not isSeat(first) then first = 1 end
  local s = {
    full = true, phase = "deal", round = 1, first = first, turn = nil,
    deck = {}, hands = { {}, {}, {}, {} },
    bids = {}, contract = nil, passes = 0,
    score = { 0, 0 }, hang = 0, res = nil,
    winner = nil, left = nil, open = false,
  }
  resetPlay(s)
  return s
end

---------------------------------------------------------------------------------------------
-- Deal
---------------------------------------------------------------------------------------------

-- A deal action's deck: on a full state all 32 distinct faces at 1..32; on a view nil
-- (nothing known) or up to 32 distinct faces.
local function checkDeck(deck, full)
  if deck == nil and not full then return {} end
  if type(deck) ~= "table" then return nil end
  local out, seen = {}, {}
  for i, face in pairs(deck) do
    if type(i) ~= "number" or i < 1 or i > 32 or i % 1 ~= 0 then return nil end
    if not IS_FACE[face] or seen[face] then return nil end
    seen[face] = true
    out[i] = face
  end
  if full then
    for i = 1, 32 do
      if not out[i] then return nil end
    end
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
  local deck = checkDeck(a.deck, s.full)
  if not deck then return nil, "deck" end
  s.deck = deck
  s.hands = { {}, {}, {}, {} }
  dealCards(s, 1, 20)
  s.bids, s.contract, s.passes = {}, nil, 0
  s.open = false
  resetPlay(s)
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
  s.lead, s.trickNo = s.first, 1
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
-- Tricks
---------------------------------------------------------------------------------------------

-- The position in the trick (faces, in play order) of the card winning it so far.
local function winningCard(b, trick)
  local best, led = 1, suitOf(trick[1])
  if b == "A" or b == "N" then
    local order = b == "A" and TRUMP_ORDER or PLAIN_ORDER
    for n = 2, #trick do
      if suitOf(trick[n]) == led and order[rankOf(trick[n])] > order[rankOf(trick[best])] then best = n end
    end
    return best
  end
  local bestIsTrump = led == b
  for n = 2, #trick do
    local face = trick[n]
    if suitOf(face) == b then
      if not bestIsTrump or TRUMP_ORDER[rankOf(face)] > TRUMP_ORDER[rankOf(trick[best])] then
        best, bestIsTrump = n, true
      end
    elseif not bestIsTrump and suitOf(face) == led
      and PLAIN_ORDER[rankOf(face)] > PLAIN_ORDER[rankOf(trick[best])] then
      best = n
    end
  end
  return best
end

-- The highest trump order among the trick's cards of a suit (0 when there is none).
local function highestTrump(trick, suit)
  local best = 0
  for _, face in ipairs(trick) do
    if suitOf(face) == suit and TRUMP_ORDER[rankOf(face)] > best then best = TRUMP_ORDER[rankOf(face)] end
  end
  return best
end

-- The positions in the hand (faces) of the cards that may be played to the trick (faces).
local function validCards(b, hand, trick)
  local function pick(suit, above)
    local out = {}
    for n, face in ipairs(hand) do
      if (not suit or suitOf(face) == suit) and (not above or TRUMP_ORDER[rankOf(face)] > above) then
        out[#out + 1] = n
      end
    end
    return out
  end
  local every = pick()
  if #trick == 0 or #hand == 1 then return every end
  local led = suitOf(trick[1])
  local follow = pick(led)
  if b == "N" then return #follow > 0 and follow or every end
  if b == "A" or b == led then
    if #follow == 0 then return every end
    local higher = pick(led, highestTrump(trick, led))
    return #higher > 0 and higher or follow
  end
  if #follow > 0 then return follow end
  local trumps = pick(b)
  if #trumps == 0 then return every end
  if #trick > 1 and winningCard(b, trick) == #trick - 1 then return every end
  local best = highestTrump(trick, b)
  if best > 0 then
    local higher = pick(b, best)
    return #higher > 0 and higher or every
  end
  return trumps
end

local function cardValue(b, face)
  local trump = b == "A" or b == suitOf(face)
  return (trump and TRUMP_VALUE or PLAIN_VALUE)[rankOf(face)]
end

-- Whether playing `face` may declare a belote. `hand` (faces, the played card included) may
-- be nil on a view: then holding the other card is not checked.
local function beloteAllowed(b, hand, trick, face)
  local r, suit = rankOf(face), suitOf(face)
  if r ~= RANK.Q and r ~= RANK.K then return false end
  if b == "N" then return false end
  if b == "A" then
    if #trick > 0 and suitOf(trick[1]) ~= suit then return false end
  elseif suit ~= b then
    return false
  end
  if not hand then return true end
  local other = (r == RANK.Q and "K" or "Q") .. suit
  for _, x in ipairs(hand) do
    if x == other then return true end
  end
  return false
end

local function applyPlay(s, seat, a)
  if not isSeat(seat) then return nil, "seat" end
  if s.phase ~= "play" then return nil, "phase" end
  if s.turn ~= seat then return nil, "turn" end
  local i, face, pos = a.i, a.c, nil
  local cards = s.hands[seat]
  for n, x in ipairs(cards) do
    if x == i then pos = n break end
  end
  if not pos or not IS_FACE[face] then return nil, "card" end
  if s.deck[i] then
    if s.deck[i] ~= face then return nil, "card" end
  else
    for _, x in pairs(s.deck) do
      if x == face then return nil, "card" end
    end
  end
  local b = s.contract.b
  local trick = facesOf(s, s.trick)
  if not trick then return nil, "show" end
  local known = s.deck[i]
  s.deck[i] = face
  local hand = facesOf(s, cards)
  s.deck[i] = known
  if hand then
    local allowed = false
    for _, n in ipairs(validCards(b, hand, trick)) do
      if n == pos then allowed = true break end
    end
    if not allowed then return nil, "rule" end
  end
  if a.b and not beloteAllowed(b, hand, trick, face) then return nil, "belot" end

  s.deck[i] = face
  table.remove(cards, pos)
  s.trick[#s.trick + 1] = i
  trick[#trick + 1] = face
  s.announced = false
  if a.b then s.ann[#s.ann + 1] = { s = seat, t = "b", i = i } end
  if #trick < 4 then
    s.turn = nextSeat(seat)
    return true
  end
  local winner = (s.lead + winningCard(b, trick) - 2) % 4 + 1
  local team = teamOf(winner)
  for _, x in ipairs(trick) do s.pts[team] = s.pts[team] + cardValue(b, x) end
  s.took[team] = s.took[team] + 1
  s.last = { cards = s.trick, lead = s.lead, win = winner }
  s.trick = {}
  if s.trickNo == 8 then
    s.lastWin, s.turn, s.lead = winner, nil, nil
    s.phase, s.open = "score", true
  else
    s.trickNo = s.trickNo + 1
    s.lead, s.turn = winner, winner
  end
  return true
end

---------------------------------------------------------------------------------------------
-- Announces
---------------------------------------------------------------------------------------------

local function canAnnounce(s)
  return s.phase == "play" and s.trickNo == 1 and s.contract.b ~= "N" and not s.announced
end

-- What the seat may announce, in the C# engine's order: the fours, the sequences of the
-- cards outside them, then the sequences through a four's card. nil when a face is unknown.
local function availableAnnounces(s, seat)
  local hand = facesOf(s, s.hands[seat])
  if not hand then return nil end
  local at, has = {}, { C = {}, D = {}, H = {}, S = {} }
  for n, face in ipairs(hand) do
    at[face] = s.hands[seat][n]
    has[suitOf(face)][rankOf(face)] = true
  end
  local out, four, anyFour = {}, {}, false
  for r = RANK["9"], RANK.A do
    if has.C[r] and has.D[r] and has.H[r] and has.S[r] then
      four[r], anyFour = true, true
      out[#out + 1] = { t = r == RANK.J and "cJ" or r == RANK["9"] and "c9" or "c", i = at[RANKS[r] .. "S"] }
    end
  end
  local function runs(suit, through)
    local len, hit = 0, false
    for r = 1, 9 do
      if r <= 8 and has[suit][r] and (through or not four[r]) then
        len, hit = len + 1, hit or four[r]
      else
        if len >= 3 and (not through or hit) then
          out[#out + 1] = { t = "s" .. len, i = at[RANKS[r - 1] .. suit] }
        end
        len, hit = 0, false
      end
    end
  end
  for _, suit in ipairs(SUITS) do runs(suit, false) end
  if anyFour then
    for _, suit in ipairs(SUITS) do runs(suit, true) end
  end
  return out
end

-- The faces an announce of type t with top card `face` is made of.
local function announceCards(t, face)
  local r, out = rankOf(face), {}
  if t:sub(1, 1) == "c" then
    for _, suit in ipairs(SUITS) do out[#out + 1] = RANKS[r] .. suit end
  else
    for k = r - tonumber(t:sub(2)) + 1, r do out[#out + 1] = RANKS[k] .. suitOf(face) end
  end
  return out
end

-- Every non-empty set of announces from `avail` in which no card is used twice.
local function announceChoices(s, avail)
  local out = {}
  if not avail then return out end
  local function extend(from, set, used)
    for n = from, #avail do
      local cards, free = announceCards(avail[n].t, s.deck[avail[n].i]), true
      for _, face in ipairs(cards) do
        if used[face] then free = false break end
      end
      if free then
        local set2, used2 = {}, {}
        for k, x in ipairs(set) do set2[k] = x end
        for face in pairs(used) do used2[face] = true end
        set2[#set2 + 1] = { t = avail[n].t, i = avail[n].i }
        for _, face in ipairs(cards) do used2[face] = true end
        out[#out + 1] = set2
        extend(n + 1, set2, used2)
      end
    end
  end
  extend(1, {}, {})
  return out
end

local function applyAnn(s, seat, a)
  if not isSeat(seat) then return nil, "seat" end
  if s.phase ~= "play" then return nil, "phase" end
  if s.turn ~= seat then return nil, "turn" end
  if not canAnnounce(s) then return nil, "phase" end
  local list = a.a
  if type(list) ~= "table" or #list == 0 then return nil, "announce" end
  local avail = availableAnnounces(s, seat)
  local inHand = {}
  for _, i in ipairs(s.hands[seat]) do inHand[i] = true end
  local used, seen, add = {}, {}, {}
  for n, x in ipairs(list) do
    if type(x) ~= "table" or type(x.t) ~= "string" or x.t == "b" or not ANN_VALUE[x.t] then
      return nil, "announce"
    end
    if not inHand[x.i] or seen[x.t .. x.i] then return nil, "announce" end
    seen[x.t .. x.i] = true
    if avail then
      local offered = false
      for _, y in ipairs(avail) do
        if y.t == x.t and y.i == x.i then offered = true break end
      end
      if not offered then return nil, "announce" end
      for _, face in ipairs(announceCards(x.t, s.deck[x.i])) do
        if used[face] then return nil, "announce" end
        used[face] = true
      end
    end
    add[n] = { s = seat, t = x.t, i = x.i }
  end
  for _, x in ipairs(add) do s.ann[#s.ann + 1] = x end
  s.announced = true
  return true
end

---------------------------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------------------------

local ANN_ORDER = { b = 1, s3 = 2, s4 = 3, s5 = 4, s6 = 5, s7 = 6, s8 = 7, c = 8, c9 = 9, cJ = 10 }

-- > 0 when announce x beats y, 0 when they are equal; y may be nil.
local function compareAnnounces(s, x, y)
  if not y then return 1 end
  if ANN_VALUE[x.t] ~= ANN_VALUE[y.t] then return ANN_VALUE[x.t] - ANN_VALUE[y.t] end
  if x.t ~= y.t then return ANN_ORDER[x.t] - ANN_ORDER[y.t] end
  local rx, ry = rankOf(s.deck[x.i]), rankOf(s.deck[y.i])
  if x.t == "c" then return TRUMP_ORDER[rx] - TRUMP_ORDER[ry] end
  return rx - ry
end

-- The announces with their points and whether they score (rule 10); nil when the card of
-- one is unknown.
local function settleAnnounces(s)
  local bestFour, bestSeq
  for _, x in ipairs(s.ann) do
    if x.t ~= "b" then
      if not s.deck[x.i] then return nil end
      if x.t:sub(1, 1) == "c" then
        if compareAnnounces(s, x, bestFour) > 0 then bestFour = x end
      elseif compareAnnounces(s, x, bestSeq) > 0 then
        bestSeq = x
      end
    end
  end
  local tied = false
  for _, x in ipairs(s.ann) do
    if x.t:sub(1, 1) == "s" and teamOf(x.s) ~= teamOf(bestSeq.s) and compareAnnounces(s, x, bestSeq) == 0 then
      tied = true
    end
  end
  local out = {}
  for n, x in ipairs(s.ann) do
    local on
    if x.t == "b" then
      on = true
    elseif x.t:sub(1, 1) == "c" then
      on = teamOf(x.s) == teamOf(bestFour.s)
    else
      on = not tied and teamOf(x.s) == teamOf(bestSeq.s)
    end
    out[n] = { s = x.s, t = x.t, i = x.i, v = ANN_VALUE[x.t], on = on }
  end
  return out
end

-- To the nearest, a half to the even number.
local function roundHalfEven(points)
  local q, r = math.floor(points / 10), points % 10
  if r > 5 or (r == 5 and q % 2 == 1) then return q + 1 end
  return q
end

local function roundPoints(b, points, winner)
  if b == "N" then return roundHalfEven(points) end
  local edge = b == "A" and 4 or 6
  local q, r = math.floor(points / 10), points % 10
  if r > edge or (r == edge and not winner) then return q + 1 end
  return q
end

local function applyScore(s, seat)
  if seat ~= 0 then return nil, "seat" end
  if s.phase ~= "score" then return nil, "phase" end
  local anns = settleAnnounces(s)
  if not anns then return nil, "show" end
  local b, x = s.contract.b, s.contract.x
  local raw = { s.pts[1], s.pts[2] }
  for _, a in ipairs(anns) do
    if a.on then raw[teamOf(a.s)] = raw[teamOf(a.s)] + a.v end
  end
  local last = teamOf(s.lastWin)
  raw[last] = raw[last] + 10
  if b == "N" then raw[1], raw[2] = raw[1] * 2, raw[2] * 2 end
  local valat = false
  for team = 1, 2 do
    if s.took[team] == 0 then
      raw[3 - team] = raw[3 - team] + 90
      valat = true
    end
  end

  local pts, hang = { 0, 0 }, 0
  local d = teamOf(s.contract.seat)
  local o = 3 - d
  if x > 1 then
    local all = roundPoints(b, raw[1] + raw[2], true) * x + s.hang
    if raw[1] > raw[2] then
      pts[1] = all
    elseif raw[2] > raw[1] then
      pts[2] = all
    else
      hang = all
    end
  elseif raw[d] < raw[o] then
    pts[o] = roundHalfEven(raw[1] + raw[2]) + s.hang
  elseif raw[d] == raw[o] then
    pts[o] = roundPoints(b, raw[o], true)
    hang = s.hang + roundPoints(b, raw[d], false)
  else
    pts[d] = roundPoints(b, raw[d], true) + s.hang
    pts[o] = roundPoints(b, raw[o], false)
  end

  s.res = { round = s.round, contract = copy(s.contract), raw = raw, pts = pts, hang = hang, valat = valat, ann = anns }
  s.score[1], s.score[2] = s.score[1] + pts[1], s.score[2] + pts[2]
  s.hang = hang
  local winner
  if s.score[1] >= E.TARGET and s.score[1] > s.score[2] and pts[1] > 0 and not valat then
    winner = 1
  elseif s.score[2] >= E.TARGET and s.score[2] > s.score[1] and pts[2] > 0 and not valat then
    winner = 2
  end
  if winner then
    s.phase, s.winner = "match", winner
  else
    nextDeal(s)
  end
  return true
end

---------------------------------------------------------------------------------------------
-- Faces on a view
---------------------------------------------------------------------------------------------

-- The running deal is annulled: nothing scores, the next seat bids first (and so deals).
local function applyVoid(s, seat)
  if seat ~= 0 then return nil, "seat" end
  if s.phase ~= "bid" and s.phase ~= "play" and s.phase ~= "score" then return nil, "phase" end
  s.phase, s.turn = "deal", nil
  s.deck, s.hands = {}, { {}, {}, {}, {} }
  s.bids, s.contract, s.passes = {}, nil, 0
  s.open, s.res = false, nil
  resetPlay(s)
  s.first = nextSeat(s.first)
  return true
end

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
  v.full = false
  if s.phase == "match" or s.open then return v end
  local keep = {}
  if isSeat(seat) then
    for _, i in ipairs(s.hands[seat]) do keep[i] = true end
  end
  if s.phase == "play" then
    -- every card in no hand has been played in this deal
    local held = {}
    for q = 1, 4 do
      for _, i in ipairs(s.hands[q]) do held[i] = true end
    end
    for i = 1, 32 do
      if not held[i] then keep[i] = true end
    end
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
  if a.need ~= nil then return nil, "need" end
  local k = a.k
  if k == "deal" then return applyDeal(s, seat, a) end
  if k == "bid" then return applyBid(s, seat, a) end
  if k == "play" then return applyPlay(s, seat, a) end
  if k == "ann" then return applyAnn(s, seat, a) end
  if k == "score" then return applyScore(s, seat) end
  if k == "show" then return applyShow(s, seat, a) end
  if k == "void" then return applyVoid(s, seat) end
  return nil, "action"
end

function E.legal(s, seat)
  local out = {}
  if not isSeat(seat) or s.turn ~= seat then return out end
  if s.phase == "bid" then
    for _, b in ipairs(availableBids(s, seat)) do out[#out + 1] = { k = "bid", b = b } end
  elseif s.phase == "play" then
    local hand, trick = facesOf(s, s.hands[seat]), facesOf(s, s.trick)
    if not hand or not trick then return out end
    local b = s.contract.b
    for _, n in ipairs(validCards(b, hand, trick)) do
      out[#out + 1] = { k = "play", i = s.hands[seat][n], c = hand[n] }
      if beloteAllowed(b, hand, trick, hand[n]) then
        out[#out + 1] = { k = "play", i = s.hands[seat][n], c = hand[n], b = true }
      end
    end
    if canAnnounce(s) then
      for _, set in ipairs(announceChoices(s, availableAnnounces(s, seat))) do
        out[#out + 1] = { k = "ann", a = set }
      end
    end
  end
  return out
end

-- A legal action for the seat on turn, from what its view shows: a pass in the auction;
-- in the tricks first every announce it holds (a four before a sequence through it), then
-- a legal card (the first, or a random one), with the belote when it is one.
function E.auto(s, seat, random)
  if not isSeat(seat) or s.turn ~= seat then return nil end
  if s.phase == "bid" then return { k = "bid", b = "P" } end
  if s.phase ~= "play" then return nil end
  local hand, trick = facesOf(s, s.hands[seat]), facesOf(s, s.trick)
  if not hand or not trick then return nil end
  if canAnnounce(s) then
    local set, used = {}, {}
    for _, x in ipairs(availableAnnounces(s, seat)) do
      local cards, free = announceCards(x.t, s.deck[x.i]), true
      for _, face in ipairs(cards) do
        if used[face] then free = false break end
      end
      if free then
        set[#set + 1] = x
        for _, face in ipairs(cards) do used[face] = true end
      end
    end
    if #set > 0 then return { k = "ann", a = set } end
  end
  local b = s.contract.b
  local valid = validCards(b, hand, trick)
  local n = valid[random and random(1, #valid) or 1]
  return { k = "play", i = s.hands[seat][n], c = hand[n], b = beloteAllowed(b, hand, trick, hand[n]) or nil }
end

-- What the table does next: {k="deal", need="deck"} (randomness: the supplier applies it without need
-- and with the shuffled deck; apply refuses an action carrying need with "need") or {k="score"}.
function E.system(s)
  if s.phase == "deal" then return { k = "deal", need = "deck" }, s.res and 5 or 0 end
  if s.phase == "score" then return { k = "score" }, 2 end
end

function E.over(s) return s.phase == "match" end

-- The dealer of the next round: the seat before the one that bids first.
function E.dealer(s) return (s.first + 2) % 4 + 1 end

-- A new match after `prev`: the deal keeps going round, when that seat is occupied.
function E.nextFirst(prev, occupied)
  local f = prev and prev.first
  if not isSeat(f) or not occupied[nextSeat(f)] then return nil end
  return nextSeat(f)
end

function E.result(s)
  if s.phase ~= "match" then return nil end
  local w = s.winner
  return { winners = { w, w + 2 }, losers = { 3 - w, 5 - w }, left = s.left }
end

-- A seated player left: the match is over and the leaver's team has lost.
function E.leave(s, seat)
  if isSeat(seat) and s.phase ~= "match" then
    s.phase, s.turn = "match", nil
    s.winner, s.left = 3 - teamOf(seat), seat
  end
  return true
end

function E.snapshot(s) return copy(s) end
function E.restore(t) return copy(t) end

return E
