local _, ns = ...

-- What the Холдем table shows, as plain data: each chair's name, stack, bet,
-- state, two cards (a face my view lacks is false, face down), dealer and
-- blind marks and the seat on turn; the board, the pot, the buttons open to
-- me with their amounts, the line of text, the note of a close and the log of
-- the last hand (locale keys). No frames. It reads only s.state (a view),
-- s.mySeat, s.status, s.role, s.seats, s.handNames (the seats when the last
-- hand began) and `want` (the amount the view remembers), and stores nothing.
local E = ns.Engines.holdem

local M = {}

-- `seat`'s name: who held it when the last hand began, else who holds it now, else "?".
local function nameOf(s, seat)
  local n = s.handNames and s.handNames[seat]
  if type(n) ~= "string" then n = s.seats and s.seats[seat] end
  if type(n) ~= "string" then n = "?" end
  return n
end

-- The finished hand `last` in words: "void", or "fold" / "won" / "split" with the first winner of the
-- main pot, what it won in all and its category; nil without a main pot.
local function outcome(last)
  if last.void then return "void" end
  local pot = last.pots and last.pots[1]
  local w = pot and pot.winners[1]
  if not w then return nil end
  local kind = #pot.winners > 1 and "split" or #last.shown > 0 and "won" or "fold"
  return kind, w, last.won[w] or 0, last.cat[w]
end

local function textOf(s, st, m, lastOfHand)
  if m.over then return { "holdem.closed" } end
  if not m.inHand and lastOfHand then
    local kind, w, amount, cat = outcome(st.last)
    if kind == "void" then return { "holdem.void" } end
    if kind == "fold" then return { "holdem.wonFold", nameOf(s, w), amount } end
    if kind == "won" then return { "holdem.won", nameOf(s, w), amount, cat } end
    if kind == "split" then return { "holdem.split", amount, cat } end
  end
  if not m.inHand then return { "holdem.waiting" } end
  if st.phase == "deal" then return { "holdem.shuffling" } end
  local own = m.seated and st.seats[m.me]
  if own and own.away then return { "holdem.away" } end
  if m.mine then
    if m.act.call then return { "holdem.toCall", m.act.call } end
    return { "holdem.yourTurn" }
  end
  if st.turn then return { "holdem.waitFor", nameOf(s, st.turn) } end
  return nil
end

local function logOf(s, last)
  if not last then return nil end
  local kind, w, amount, cat = outcome(last)
  local n = last.hand
  if kind == "void" then return { "holdem.logVoid", n } end
  if kind == "fold" then return { "holdem.logFold", n, nameOf(s, w), amount } end
  if kind == "won" then return { "holdem.log", n, nameOf(s, w), amount, cat } end
  if kind == "split" then return { "holdem.logSplit", n, amount, cat } end
  return nil
end

-- The buttons open to me (E.legal) with the amounts they carry.
local function actOf(st, me)
  local p, chips = st.p[me], st.seats[me].chips
  local act = { fold = true }
  for _, a in ipairs(E.legal(st, me)) do
    if a.k == "check" then act.check = true
    elseif a.k == "call" then act.call = math.min(st.bet - p.bet, chips)
    elseif a.k == "bet" or a.k == "raise" then act.raise = { k = a.k, min = a.to, max = a.max }
    elseif a.k == "allin" then act.allin = p.bet + chips end
  end
  return act
end

local function seatOf(s, st, i, m, lastOfHand)
  local chair, p = st.seats[i], st.p[i]
  local here = p ~= nil and not p.gone             -- a gone record is nobody's hand
  local inIt = m.inHand and here
  local state
  if chair.away then state = "away"
  elseif inIt then state = p.folded and "folded" or p.allin and "allin" or "in"
  elseif chair.chips == 0 then state = "out"
  elseif m.inHand then state = "wait"
  else state = "ready" end
  local cards
  if here and not (p.folded and not (m.seated and i == m.me)) then
    cards = { st.deck[p.cards[1]] or false, st.deck[p.cards[2]] or false }
  end
  local mark
  if st.button == i then mark = "D"
  elseif st.sbSeat == i then mark = "sb"
  elseif st.bbSeat == i then mark = "bb" end
  local seat = {
    name = nameOf(s, i), chips = chair.chips, st = state, cards = cards, mark = mark,
    bet = inIt and p.bet > 0 and p.bet or nil,
    turn = s.status == "live" and st.turn == i,
  }
  if lastOfHand and not m.inHand and not st.last.void then
    seat.won, seat.cat = st.last.won[i], st.last.cat[i]
  end
  return seat
end

-- Everything the Холдем view draws. `want`: the amount the view remembers for a bet or raise (nil: the
-- minimum); it is clamped to what the engine allows.
function M.build(s, want)
  local st = s.state
  local seated = type(s.mySeat) == "number" and st.seats[s.mySeat] ~= nil
  local me = seated and s.mySeat or 1
  local m = {
    me = me, seated = seated, host = s.role == "host", phase = st.phase, hand = st.hand,
    inHand = E.inHand(st), closing = st.closing == true, over = E.over(st),
  }
  local lastOfHand = st.last ~= nil and st.last.hand == st.hand

  local board = {}
  for _, i in ipairs(st.board) do board[#board + 1] = st.deck[i] end
  m.board = board
  local pot = 0
  if m.inHand then
    for _, i in ipairs(st.order) do pot = pot + st.p[i].total end
  end
  m.pot = pot

  local seats = {}
  for i, chair in ipairs(st.seats) do
    if chair then seats[i] = seatOf(s, st, i, m, lastOfHand) end
  end
  m.seats = seats

  m.mine = seated and s.status == "live" and st.turn == me
  if m.mine then
    m.act = actOf(st, me)
    local r = m.act.raise
    if r then
      local function clamp(x) return math.max(r.min, math.min(r.max, x)) end
      local toCall = st.bet - st.p[me].bet
      m.to = clamp(type(want) == "number" and want or r.min)
      m.half = clamp(st.bet + math.floor((pot + toCall) / 2))
      m.potTo = clamp(st.bet + pot + toCall)
      m.step = st.bb
    end
  end

  m.text = textOf(s, st, m, lastOfHand)
  if m.closing and not m.over then m.note = { "holdem.closing" } end
  m.log = logOf(s, st.last)
  return m
end

ns.HoldemModel = M
