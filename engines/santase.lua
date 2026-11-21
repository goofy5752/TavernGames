local _, ns = ...
ns.Engines = ns.Engines or {}

--[[ Сантасе (Santase, Bulgarian 66): 2 players. Rule table (binding for code and tests):

 1. Deck: 24 cards, ranks 9 J Q K T A in suits C D H S. Card points A 11, T 10, K 4, Q 3, J 2, 9 0
    (120 in the deck). Order inside a suit A > T > K > Q > J > 9 (= the point order).
 2. Deal (action {k="deal", deck=24 faces}): deck[1..3] to the non-dealer, [4..6] to the dealer,
    [7..9] non-dealer, [10..12] dealer; deck[13] is turned face up as the trump card and lies under
    the stock; the stock is drawn from the top in the order deck[14], deck[15], ..., deck[24], and
    the face-up trump card is drawn last. Stock = 12 cards including the trump card.
 3. The non-dealer leads the first trick. The first hand is led by opts.first (seat 1 by default),
    so the other seat deals it. Afterwards the winner of a hand deals the next one (the loser
    leads); after a tie the same dealer deals again.
 4. A trick is won by the higher card of the led suit unless a trump is played; a trump beats any
    non-trump; between two trumps the higher wins. The winner of a trick leads the next one.
 5. While the stock is open and not empty, after every trick the winner draws the top card first,
    then the loser. With two cards left the winner gets the hidden card and the loser the face-up
    trump card.
 6. While the stock is open there is no duty to follow suit: any card may be played.
 7. Once the stock is closed or exhausted, the responder must follow suit and beat the led card if
    able; if he cannot beat it he plays a lower card of the suit; void in the suit he must trump if
    able; otherwise any card.
 8. Marriage = K and Q of one suit in hand: 40 in trumps, 20 otherwise. Declared only by the
    player on lead, as the lead itself: {k="marry", i, c, j, d} plays card i (face c, the K or Q)
    and shows its partner j (face d), which stays face-up in the hand. Allowed in every phase while
    leading, including the very first lead and after closing or exhaustion. Marriage points count
    only once the declarer has won at least one trick (pending until then; never if he wins none).
 9. Exchanging the trump nine {k="swap9", i, c}: the holder of the 9 of trumps, on lead before
    playing, having won at least one trick, while the stock is not closed and holds more than two
    cards (the face-up trump card included), swaps it for the face-up trump card. The taken trump
    card stays face-up in his hand; the nine becomes the face-up card under the stock.
10. Closing {k="close"}: the player on lead, before leading, while the stock is not closed and holds
    more than two cards (trump card included). The leader then leads as usual (he may swap the
    nine before closing, and may declare marriages afterwards). After closing nobody draws and
    rule 7 applies. Closing is allowed on the first lead (no trick needed).
11. The winner of the last trick gets +10 only when the stock was played out (not after closing).
12. 66 is detected automatically (no "calling out"): as soon as a player's points (tricks + counted
    marriages, rule 8) reach 66 — after a trick he wins or a marriage he declares — the hand ends
    and he wins it. A hand ended by a marriage leaves the led card on the table, outside any trick.
13. Game points for the winner of a hand: 3 if the loser won no trick, 2 if the loser has under 33
    points (counted marriages included), 1 otherwise.
14. Closed stock: if the closer reaches 66 he scores by rule 13. If he fails (all cards played
    without his reaching 66) or his opponent reaches 66 first, the opponent scores 2 game points, or
    3 if the opponent had won no trick at the moment of closing.
15. Cards played out with the stock exhausted and neither player at 66 (only 65:65 is possible):
    tie, no game points (rule 3 for the next dealer).
16. Match: first to 11 game points. A player who leaves a live match loses it.

 Actions: seats 1/2 {k="play", i, c}, {k="marry", i, c, j, d}, {k="swap9", i, c}, {k="close"};
 seat 0 {k="deal", deck}, {k="show", cards = {[i] = face}}, {k="void"}. Hand result: s.res = {winner
 (0 = tie), gp, reason = "66" | "fail" | "tie" | "out" (played out below 66 with unequal totals; cannot
 occur)}.
 {k="void"} (phase "play" only): the running hand is annulled, nothing scores and it is dealt again
 (back to phase "deal") with the same s.dealer, so the same seat leads; the game points of the match
 stay. Who holds the deck for the new deal is the extension's business (the next seat, core/Deal.lua).

 Views: a seat sees its own hand, the cards on the table, the last completed trick, the face-up trump
 card, cards shown in a hand (marriage partner, a trump card taken from under the stock), and
 everything once the match is over. Card points, trick counts, marriages and game points are
 public numbers. Randomness: E.system returns {k="deal", need="deck"} when a hand must be dealt; the
 supplier applies it without need and with the deck (apply refuses an action carrying need with "need"):
 on a full state a permutation of E.DECK; on a view any known subset, no deck = an empty one. A view
 that does not know the trump suit yet plays nothing (play and marry are refused with "phase").
 At the table: extension "fair" (core/Deal.lua) shuffles and deals; its dealer (who holds the deck)
 takes turns by seat, while s.dealer above only orders the deal and so decides who leads. E.again: once
 a match is over the host may start a new one, led by its loser (E.nextFirst).
]]

local E = { id = "santase", minSeats = 2, maxSeats = 2, GOAL = 11, TARGET = 66, options = {}, ext = { "fair" }, again = true }
ns.Engines.santase = E

local RANKS = { "9", "J", "Q", "K", "T", "A" }
local SUITS = { "C", "D", "H", "S" }
local VALUE = { ["9"] = 0, J = 2, Q = 3, K = 4, T = 10, A = 11 }
local N = 24
E.VALUE = VALUE

E.DECK = {}
for _, su in ipairs(SUITS) do
  for _, r in ipairs(RANKS) do E.DECK[#E.DECK + 1] = r .. su end
end
local ISFACE = {}
for _, f in ipairs(E.DECK) do ISFACE[f] = true end

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function rank(f) return f:sub(1, 1) end
local function suit(f) return f:sub(2, 2) end
local function val(f) return VALUE[rank(f)] end
local function posOf(list, x) for p, v in ipairs(list) do if v == x then return p end end end
local function isIndex(i) return type(i) == "number" and i >= 1 and i <= N and i % 1 == 0 end

-- May index i carry face c here? Known faces must match; an unknown one must not repeat another.
local function faceOk(s, i, c)
  if type(c) ~= "string" or not ISFACE[c] then return false end
  local known = s.deck[i]
  if known ~= nil then return known == c end
  for j = 1, N do if s.deck[j] == c then return false end end
  return true
end

local function strict(s) return s.closed ~= nil or #s.stock == 0 end
local function stockOpen(s) return s.closed == nil and #s.stock > 2 end

function E.points(s, seat)
  return s.pts[seat] + (s.ntr[seat] > 0 and s.mar[seat] or 0)
end

-- Cards of `hand` allowed against `led` under rule 7; nil when a needed face is unknown.
local function obligations(s, hand, face, led)
  local ts = s.tsuit
  if not ts or not led then return nil end
  local ls, lv = suit(led), val(led)
  local head, follow, trumps, all = {}, {}, {}, {}
  for _, i in ipairs(hand) do
    local f = face(i)
    if not f then return nil end
    all[i] = true
    if suit(f) == ls then
      follow[i] = true
      if val(f) > lv then head[i] = true end
    elseif suit(f) == ts then
      trumps[i] = true
    end
  end
  if next(head) then return head end
  if next(follow) then return follow end
  if next(trumps) then return trumps end
  return all
end

local function finishHand(s, w, reason)
  local gp = 0
  if w then
    local l = 3 - w
    if s.closed and s.closed ~= w then gp = s.closeOpp and 2 or 3
    elseif s.ntr[l] == 0 then gp = 3
    elseif E.points(s, l) < 33 then gp = 2
    else gp = 1 end
    s.gp[w] = s.gp[w] + gp
    s.dealer = w
  end
  s.res = { winner = w or 0, gp = gp, reason = reason }
  s.turn = nil
  if w and s.gp[w] >= E.GOAL then
    s.phase, s.winner = "match", w
  else
    s.phase = "hand"
  end
end

local function resolveTrick(s)
  local L, R = s.trick[1], s.trick[2]
  local lf, rf = s.deck[L], s.deck[R]
  local resp = 3 - s.lead
  local beats
  if suit(rf) == suit(lf) then beats = val(rf) > val(lf) else beats = suit(rf) == s.tsuit end
  local w = beats and resp or s.lead
  s.pts[w] = s.pts[w] + val(lf) + val(rf)
  s.ntr[w] = s.ntr[w] + 1
  table.insert(s.won[w], L); table.insert(s.won[w], R)
  s.last = { L, R }
  s.trick = {}
  if s.closed == nil and #s.stock > 0 then
    table.insert(s.hands[w], table.remove(s.stock, 1))
    local b = table.remove(s.stock, 1)
    table.insert(s.hands[3 - w], b)
    if b == s.trumpI then s.shown[b] = true; s.trumpI = nil end
  end
  s.lead, s.turn = w, w
  local out = #s.hands[w] == 0
  if out and s.closed == nil then s.pts[w] = s.pts[w] + 10 end
  if E.points(s, w) >= E.TARGET then
    finishHand(s, w, "66")
  elseif out then
    if s.closed then
      finishHand(s, 3 - s.closed, "fail")
    else
      local a, b = E.points(s, 1), E.points(s, 2)
      if a == b then finishHand(s, nil, "tie") else finishHand(s, a > b and 1 or 2, "out") end
    end
  end
end

local function play(s, seat, a, marry)
  local hand = s.hands[seat]
  local i, c = a.i, a.c
  if not isIndex(i) or not posOf(hand, i) or not faceOk(s, i, c) then return nil, "card" end
  local j, d = a.j, a.d
  if marry then
    if #s.trick ~= 0 then return nil, "move" end
    if not isIndex(j) or j == i or not posOf(hand, j) or d == c or not faceOk(s, j, d) then
      return nil, "card"
    end
    local r = rank(c)
    if (r ~= "K" and r ~= "Q") or suit(d) ~= suit(c) or rank(d) ~= (r == "K" and "Q" or "K") then
      return nil, "move"
    end
  elseif #s.trick == 1 and strict(s) then
    local set = obligations(s, hand, function(x) if x == i then return c end return s.deck[x] end,
      s.deck[s.trick[1]])
    if set and not set[i] then return nil, "move" end
  end
  s.deck[i] = c
  table.remove(hand, posOf(hand, i))
  s.shown[i] = nil
  table.insert(s.trick, i)
  if marry then
    s.deck[j] = d
    s.shown[j] = true
    s.mar[seat] = s.mar[seat] + (suit(c) == s.tsuit and 40 or 20)
  end
  if #s.trick == 1 then
    s.turn = 3 - seat
    if marry and E.points(s, seat) >= E.TARGET then finishHand(s, seat, "66") end
  else
    resolveTrick(s)
  end
  return true
end

local function canSwap(s, seat)
  return #s.trick == 0 and stockOpen(s) and s.trumpI ~= nil and s.ntr[seat] > 0 and s.tsuit ~= nil
end

local function swap9(s, seat, a)
  if not canSwap(s, seat) then return nil, "move" end
  local hand, i, c = s.hands[seat], a.i, a.c
  if not isIndex(i) or not posOf(hand, i) or c ~= "9" .. s.tsuit or not faceOk(s, i, c) then
    return nil, "card"
  end
  local t = s.trumpI
  s.deck[i] = c
  hand[posOf(hand, i)] = t
  s.shown[t] = true
  s.stock[#s.stock] = i
  s.trumpI = i
  return true
end

local function deal(s, a)
  local d = a.deck
  if d == nil and not s.full then d = {} end
  if type(d) ~= "table" then return nil, "deck" end
  for k in pairs(d) do if not isIndex(k) then return nil, "deck" end end
  local seen = {}
  for i = 1, N do
    local f = d[i]
    if f ~= nil then
      if type(f) ~= "string" or not ISFACE[f] or seen[f] then return nil, "deck" end
      seen[f] = true
    elseif s.full then
      return nil, "deck"
    end
  end
  s.deck = {}
  for i = 1, N do s.deck[i] = d[i] end
  local non, dl = 3 - s.dealer, s.dealer
  s.hands = { {}, {} }
  for i = 1, 3 do table.insert(s.hands[non], i) end
  for i = 4, 6 do table.insert(s.hands[dl], i) end
  for i = 7, 9 do table.insert(s.hands[non], i) end
  for i = 10, 12 do table.insert(s.hands[dl], i) end
  s.trumpI = 13
  s.tsuit = s.deck[13] and suit(s.deck[13]) or nil
  s.stock = {}
  for i = 14, N do table.insert(s.stock, i) end
  table.insert(s.stock, 13)
  s.closed, s.closeOpp = nil, nil
  s.trick, s.last = {}, {}
  s.won = { {}, {} }
  s.ntr, s.pts, s.mar = { 0, 0 }, { 0, 0 }, { 0, 0 }
  s.shown = {}
  s.res = nil
  s.hand = s.hand + 1
  s.lead, s.turn = non, non
  s.phase = "play"
  return true
end

local function show(s, a)
  if s.phase == "deal" then return nil, "phase" end
  local cards = a.cards
  if type(cards) ~= "table" then return nil, "card" end
  local seen = {}
  for i, f in pairs(cards) do
    if not isIndex(i) or seen[f] or not faceOk(s, i, f) then return nil, "card" end
    seen[f] = true
  end
  for i, f in pairs(cards) do s.deck[i] = f end
  if not s.tsuit and s.deck[13] then s.tsuit = suit(s.deck[13]) end
  return true
end

-- The running hand is annulled: back to the deal, the same s.dealer (the same leader), the match score kept.
local function void(s)
  if s.phase ~= "play" then return nil, "phase" end
  s.phase, s.hand = "deal", s.hand - 1
  s.turn, s.res, s.closed, s.closeOpp, s.trumpI, s.tsuit = nil, nil, nil, nil, nil, nil
  s.deck, s.hands, s.stock, s.trick, s.last, s.won, s.shown = {}, { {}, {} }, {}, {}, {}, { {}, {} }, {}
  s.ntr, s.pts, s.mar = { 0, 0 }, { 0, 0 }, { 0, 0 }
  return true
end

function E.new(opts)
  local first = (opts and opts.first) == 2 and 2 or 1
  return {
    full = true, phase = "deal", dealer = 3 - first, hand = 0, gp = { 0, 0 },
    deck = {}, hands = { {}, {} }, stock = {}, trick = {}, last = {}, won = { {}, {} },
    ntr = { 0, 0 }, pts = { 0, 0 }, mar = { 0, 0 }, shown = {},
  }
end

function E.apply(s, seat, a)
  if type(a) ~= "table" then return nil, "action" end
  if a.need ~= nil then return nil, "need" end
  local k = a.k
  if k == "deal" or k == "show" or k == "void" then
    if seat ~= 0 then return nil, "seat" end
    if k == "show" then return show(s, a) end
    if k == "void" then return void(s) end
    if s.phase ~= "deal" and s.phase ~= "hand" then return nil, "phase" end
    return deal(s, a)
  elseif k == "play" or k == "marry" or k == "swap9" or k == "close" then
    if seat ~= 1 and seat ~= 2 then return nil, "seat" end
    if s.phase ~= "play" or (s.tsuit == nil and (k == "play" or k == "marry")) then return nil, "phase" end
    if s.turn ~= seat then return nil, "turn" end
    if k == "play" then return play(s, seat, a, false) end
    if k == "marry" then return play(s, seat, a, true) end
    if k == "swap9" then return swap9(s, seat, a) end
    if #s.trick ~= 0 or not stockOpen(s) then return nil, "move" end
    s.closed = seat
    s.closeOpp = s.ntr[3 - seat] > 0
    return true
  end
  return nil, "action"
end

function E.legal(s, seat)
  local out = {}
  if s.phase ~= "play" or s.turn ~= seat or s.tsuit == nil then return out end
  local hand = s.hands[seat]
  local leading = #s.trick == 0
  local set
  if not leading and strict(s) then
    set = obligations(s, hand, function(x) return s.deck[x] end, s.deck[s.trick[1]])
  end
  for _, i in ipairs(hand) do
    local f = s.deck[i]
    if f and (not set or set[i]) then out[#out + 1] = { k = "play", i = i, c = f } end
  end
  if not leading then return out end
  for _, i in ipairs(hand) do
    local f = s.deck[i]
    if f and (rank(f) == "K" or rank(f) == "Q") then
      local want = (rank(f) == "K" and "Q" or "K") .. suit(f)
      for _, j in ipairs(hand) do
        if s.deck[j] == want then out[#out + 1] = { k = "marry", i = i, c = f, j = j, d = want } end
      end
    end
  end
  if canSwap(s, seat) then
    for _, i in ipairs(hand) do
      if s.deck[i] == "9" .. s.tsuit then out[#out + 1] = { k = "swap9", i = i, c = s.deck[i] } end
    end
  end
  if stockOpen(s) then out[#out + 1] = { k = "close" } end
  return out
end

-- Lowest-value legal card (a non-trump before a trump of equal value); never declares or closes.
function E.auto(s, seat)
  local best, bk
  for _, a in ipairs(E.legal(s, seat)) do
    if a.k == "play" then
      local key = val(a.c) * 2 + (suit(a.c) == s.tsuit and 1 or 0)
      if not bk or key < bk then best, bk = a, key end
    end
  end
  return best
end

function E.system(s)
  if s.phase == "deal" then return { k = "deal", need = "deck" }, 0 end
  if s.phase == "hand" then return { k = "deal", need = "deck" }, 3 end
end

function E.view(s, seat)
  local v = copy(s)
  v.full = false
  if s.phase == "match" then return v end
  local vis = {}
  if seat == 1 or seat == 2 then for _, i in ipairs(s.hands[seat]) do vis[i] = true end end
  for i in pairs(s.shown) do vis[i] = true end
  for _, i in ipairs(s.trick) do vis[i] = true end
  for _, i in ipairs(s.last) do vis[i] = true end
  if s.trumpI then vis[s.trumpI] = true end
  v.deck = {}
  for i = 1, N do if vis[i] then v.deck[i] = s.deck[i] end end
  return v
end

function E.hidden(s, seat)
  local out = {}
  for _, i in ipairs(s.hands[seat] or {}) do
    if not s.shown[i] then out[#out + 1] = i end
  end
  return out
end

function E.leave(s, seat)
  if (seat == 1 or seat == 2) and s.phase ~= "match" then
    s.phase, s.winner, s.left, s.turn = "match", 3 - seat, seat, nil
  end
end

function E.result(s)
  if s.phase == "match" and s.winner then return { winners = { s.winner }, losers = { 3 - s.winner } } end
end

function E.over(s) return s.phase == "match" end

-- A new match after `prev`: its loser leads, when that seat is occupied.
function E.nextFirst(prev, occupied)
  local w = prev and prev.winner
  if w and occupied[3 - w] then return 3 - w end
  return nil
end

function E.snapshot(s) return copy(s) end
function E.restore(t) return copy(t) end

return E
