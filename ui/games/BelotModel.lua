local _, ns = ...

-- What the Белот table shows, as plain data: my hand sorted with each card's
-- mode, the bids open to me, the announce the engine offers me, the trick
-- (or the last trick on request), the bubbles over the seats, the contract,
-- the dealer, the score, the last deal's summary and the line of text.
-- No frames. It reads only s.state (a view: a face the view lacks stays
-- nil), s.mySeat, s.status, s.seats and the optional `names` (seat -> who
-- held it during the match, the view's memory), and stores nothing; what it
-- returns is its own (the contract is a copy, not the state's table).
-- Bubbles come from the engine's record only (state.bids, state.ann) and
-- name an announce by its kind, never by a face.
local E = ns.Engines.belot

local M = {}

local SUITS = { C = 1, D = 2, H = 3, S = 4 }
-- Strength inside a suit, higher = stronger: trump J 9 A T K Q 8 7, plain A T K Q J 9 8 7.
local TRUMP = { J = 8, ["9"] = 7, A = 6, T = 5, K = 4, Q = 3, ["8"] = 2, ["7"] = 1 }
local PLAIN = { A = 8, T = 7, K = 6, Q = 5, J = 4, ["9"] = 3, ["8"] = 2, ["7"] = 1 }

local function suit(face) return face:sub(2, 2) end
local function isSeat(seat) return seat == 1 or seat == 2 or seat == 3 or seat == 4 end

-- The strength of `face` under the contract `b` (nil before a bid).
local function strength(b, face)
  local trump = b == "A" or b == suit(face)
  return (trump and TRUMP or PLAIN)[face:sub(1, 1)]
end

-- The cards of `seat` as {i, face}: by suit C D H S, the strongest first,
-- unknown faces last in hand order.
local function sortedHand(st, seat)
  local b = st.contract and st.contract.b
  local out = {}
  for pos, i in ipairs(st.hands and st.hands[seat] or {}) do
    out[#out + 1] = { i = i, face = st.deck[i], pos = pos }
  end
  table.sort(out, function(x, y)
    local fx, fy = x.face, y.face
    if (fx ~= nil) ~= (fy ~= nil) then return fx ~= nil end
    if fx and fy then
      if suit(fx) ~= suit(fy) then return SUITS[suit(fx)] < SUITS[suit(fy)] end
      return strength(b, fx) > strength(b, fy)
    end
    return x.pos < y.pos
  end)
  for _, c in ipairs(out) do c.pos = nil end
  return out
end

-- `seat`'s name: who held it during the match (`names`), else who holds it
-- now; nil for an empty seat.
local function nameOf(s, seat, names)
  local n = names and names[seat] or s.seats and s.seats[seat]
  if type(n) == "string" then return n end
  return nil
end

local function contains(list, i)
  for _, x in ipairs(list or {}) do
    if x == i then return true end
  end
  return false
end

-- seat -> list of locale keys, from the engine's record only.
local function bubblesOf(st)
  local out = {}
  local function add(seat, key)
    out[seat] = out[seat] or {}
    out[seat][#out[seat] + 1] = key
  end
  if st.phase == "bid" then
    local last = {}
    for _, x in ipairs(st.bids or {}) do last[x.s] = x.b end
    for seat = 1, 4 do
      if last[seat] then add(seat, "belot.bid." .. last[seat]) end
    end
  elseif st.phase == "play" then
    local trick = st.trick or {}
    local lastCards = #trick == 0 and st.last and st.last.cards or nil
    for _, x in ipairs(st.ann or {}) do
      if x.t ~= "b" then
        if st.trickNo <= 2 then add(x.s, "belot.ann." .. x.t) end
      elseif contains(trick, x.i) or contains(lastCards, x.i) then
        add(x.s, "belot.ann.b")
      end
    end
  end
  return out
end

-- The last deal's result as my side sees it; nil outside "deal"/"match".
local function summaryOf(st, team)
  local res = st.res
  if not res or (st.phase ~= "deal" and st.phase ~= "match") then return nil end
  local c = res.contract
  local inside, hanging = false, false
  if c then
    local d = 2 - c.seat % 2
    inside = res.raw[d] < res.raw[3 - d]
    hanging = res.raw[d] == res.raw[3 - d]
  end
  local anns = {}
  for n, x in ipairs(res.ann or {}) do anns[n] = { seat = x.s, t = x.t, v = x.v, on = x.on } end
  return {
    passed = c == nil, contract = c and { seat = c.seat, b = c.b, x = c.x }, us = res.pts[team], them = res.pts[3 - team],
    hang = res.hang, valat = res.valat, inside = inside, hanging = hanging, anns = anns,
  }
end

local function textOf(s, st, seated, team, mine, names)
  if E.over(st) then
    local gone = st.left and nameOf(s, st.left, names)
    if gone then return { "belot.left", gone } end
    if not st.winner then return nil end
    if seated then return { st.winner == team and "belot.match.us" or "belot.match.them" } end
    local w1, w2 = nameOf(s, st.winner, names), nameOf(s, st.winner + 2, names)
    return w1 and w2 and { "belot.match.names", w1, w2 } or nil
  end
  local phase = st.phase
  if phase == "deal" then
    return st.res and st.res.contract == nil and { "belot.passed" } or nil
  elseif phase == "bid" or phase == "play" then
    if mine then return { phase == "bid" and "belot.yourBid" or "belot.yourTurn" } end
    local turn = st.turn and nameOf(s, st.turn, names)
    return turn and { "belot.waitFor", turn } or nil
  end
  return nil
end

-- Everything the Белот view draws. `peek`: show the last trick instead of
-- the running one. `names` (optional): seat -> who held it during the match.
function M.build(s, peek, names)
  local st = s.state
  local seated = isSeat(s.mySeat)
  local me = seated and s.mySeat or 1
  local team = 2 - me % 2
  local pos = {}
  for seat = 1, 4 do pos[seat] = (seat - me) % 4 end
  local phase = st.phase
  local mine = seated and s.status == "live" and (phase == "bid" or phase == "play") and st.turn == me

  local bids, plays, announce = {}, {}, nil
  if mine then
    for _, a in ipairs(E.legal(st, me)) do
      if a.k == "bid" then
        bids[a.b] = true
      elseif a.k == "play" then
        plays[a.i] = true
      end
    end
    if phase == "play" then announce = E.announce(st, me) end
  end

  local hand = sortedHand(st, me)
  local all = true
  for _, c in ipairs(hand) do all = all and plays[c.i] == true end
  for _, c in ipairs(hand) do
    if not mine or phase ~= "play" or all then
      c.mode = "plain"
    else
      c.mode = plays[c.i] and "raised" or "dim"
    end
  end

  local trick, lead, peeking = st.trick or {}, st.lead, nil
  if peek and st.last then
    trick, lead, peeking = st.last.cards, st.last.lead, true
  end
  local cards = {}
  for k, i in ipairs(trick) do
    cards[k] = { seat = (lead + k - 2) % 4 + 1, i = i, face = st.deck[i] }
  end

  local dealt = phase == "bid" or phase == "play" or phase == "score"
  return {
    me = me, seated = seated, team = team, pos = pos, mine = mine,
    hand = hand, bids = bids, announce = announce,
    trick = cards, peeking = peeking, canPeek = phase == "play" and st.last ~= nil,
    bubbles = bubblesOf(st), contract = st.contract and { seat = st.contract.seat, b = st.contract.b, x = st.contract.x },
    dealer = dealt and E.dealer(st) or nil,
    score = { us = st.score[team], them = st.score[3 - team], hang = st.hang },
    summary = summaryOf(st, team),
    text = textOf(s, st, seated, team, mine, names),
  }
end

ns.BelotModel = M
