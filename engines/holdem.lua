--[==[ Texas Hold'em: No-Limit / Pot-Limit cash table, chips only (pure Lua 5.1).

RULES
 1. A 9-chair table, a hand needs 2+ playing seats (occupied, chips > 0, not leaving). Options:
    betting = "nl" No Limit / "pl" Pot Limit (default "nl"); blinds = big blind 10 / 20 / 50 / 100 / 200 with
    the small blind half of it, i.e. 5/10, 10/20, 25/50, 50/100, 100/200 (default 10 = 5/10); stack = the
    starting stack in big blinds 50 / 100 / 200 (default 100), starting chips = stack x big blind (state.stack,
    e.g. 100 x 20 = 2000). An unknown value falls back to the default. No antes, no gold, no buy-in, no rebuy.
 2. Seats: {k="join", seat=s} at seat 0 seats a player on an empty chair with the starting stack; he is dealt
    in from the next hand. E.leave(state, s) (or {k="leave", seat=s} at seat 0): a seat in the current hand
    is folded at once (its chips in the pot stay there) and removed when the hand ends; any other seat is
    removed at once. A seat with 0 chips after a hand sits out (seats[s].out = true) until it leaves.
    When a chair is vacated its record of the last hand is flagged gone: whoever sits there next sees none
    of those cards (E.view, E.hidden). A busted seat may stand up and sit down again for a fresh starting
    stack (play chips). A join on a chair whose player stood up during this hand (leaving) is accepted, one
    newcomer a chair: the leaver's hand is gone at once (flagged gone, the newcomer owes no face of it), the
    leaver is folded and goes with its chips when the hand ends as any leaver does (state.last.left), and
    the newcomer is seated with the starting stack then. A leave of that chair before the hand ends is the
    newcomer's: he is not seated.
 3. Button: the first hand's button is the first playing seat at or after opts.first (default 1); every
    next hand it moves to the next playing seat clockwise (seat numbers upwards, 9 wraps to 1).
 4. Blinds: small blind = first playing seat left of the button, big blind = the next one; heads-up the
    button posts the small blind. A player short of his blind posts all he has and is all-in. Preflop the
    amount to call is always the full big blind and the first raise must be at least one big blind more.
 5. Dealing, by deck index (n = players in the hand, dealt clockwise starting left of the button): first
    card to each player = 1..n, second card = n+1..2n; burn 2n+1, flop 2n+2..2n+4, burn 2n+5, turn 2n+6,
    burn 2n+7, river 2n+8.
 6. First to act: preflop the player left of the big blind (heads-up: the button); on flop, turn and river
    the first live player left of the button (heads-up: the big blind). Then clockwise.
 7. On his turn a player may: fold (always); check (nothing to call); call (all he has if short);
    bet {to} (no bet on this street yet, to >= big blind); raise {to} (to >= current bet + the last full
    raise size); allin (all his chips as a bet/raise). `to` is his total bet on this street.
    The cap on `to` (minimum raises are the same in both modes):
    - No Limit: his whole stack, to <= bet + chips (his bet on this street plus his chips behind).
    - Pot Limit: the call plus the pot after the call. With pot = the sum of every dealt-in seat's chips put
      in this hand (all streets, this street's bets and folded players' chips included) and toCall = the
      current bet - his bet: maxTo = min(his bet + chips, current bet + pot + toCall). So at 5/10 preflop the
      first to act may raise to 35 (10 + 15 + 10), heads-up the button to 30 (10 + 15 + 5), the big blind
      after a limp to 30 (10 + 20 + 0); a bet into an unopened street is at most the pot (0 + pot + 0).
      allin is allowed only when his bet + chips <= that cap (all-in for less than the pot is fine); above
      it allin is refused ("amount") and the raise up to the cap is his biggest option. A bet/raise above
      the cap is refused ("amount"). The cap is never below the minimum raise: a full raise size is at most
      the raiser's bet, already in the pot, and pot + toCall holds at least a big blind whenever a seat that
      can act faces it. The cap counts the chips actually posted: a short blind counts what it put in, not
      the full blind.
 8. An all-in raise smaller than a full raise does not change the minimum raise size and does not reopen
    the betting: a player who already acted on this street may raise again only if the bet grew by at least
    the full raise size since his last action (several short all-ins together can reopen it). Nobody may
    bet or raise when no other live player has chips behind.
 9. A street ends when every live player with chips has acted and matched the bet, or when at most one
    live player has chips and he has matched every other live bet. With nobody left to bet, the remaining
    streets are dealt one by one without betting.
10. Everyone but one folds: he wins every pot at once, nobody shows, his cards stay hidden.
11. Showdown: every live hand is shown (no mucking). The last bettor/raiser of the river shows first,
    else the first live player left of the button; then clockwise. Best five of seven (holdem_eval.lua).
12. Pots: contributions are layered by size. A layer only one player paid into is an uncalled bet and goes
    back to him. A pot is won only by live players who paid its whole layer; folded chips stay in the pot
    (a layer that only folded players paid into, which only a leave can cause, joins the pot below it).
    Consecutive layers with the same live players make one pot. Each pot is split among its best live hands;
    odd chips go one at a time to those winners in order from the first seat left of the button.
13. state.last, the record of the finished hand: { hand = n, contrib = {[seat] = chips put in minus chips
    returned, for every seat dealt in}, won = {[seat] = chips won from pots}, pots = {{amount, eligible =
    {seats}, winners = {seats}}, ...} (main pot first), shown = {seats in showdown order} ({} without a
    showdown), cat = {[seat] = hand category}, left = {[seat] = chips a leaver took} }.
    sum(won) == sum(contrib) always.
14. A cash table has no match end: E.result is nil; E.over is false until the game is closed (rule 17).
    E.auto: check if possible, else fold.
15. {k="void"} at seat 0, only during a hand (phase deal, bet, street or showdown; else "phase"): every
    seat dealt in gets back all it put in this hand (nothing stays in the pot), nothing is shown,
    state.last = {hand, void = true, contrib = {}, won = {}, pots = {}, shown = {}, cat = {}, left};
    leavers go and busted seats sit out as after any hand. The hand count and the button stay, so the
    next hand moves the button on.
16. {k="away", seat} at seat 0 sits an occupied seat out ("seat" if empty or already away): in a hand it is
    folded as a leave folds it (its chips stay in the pot) but it keeps its chair; an away seat is not a
    playing seat (rule 1) and is dealt no hand. {k="back"} by the seat itself, in any phase, only while it
    is away ("seat"): it is dealt in again from the next hand.
17. {k="close"} at seat 0 ("phase" once given): the running hand is played out, then the phase is
    "closed" (at once outside a hand): the game is over (E.over), nothing is dealt, hand and join are
    refused with "phase" (join already once the close is given).
18. Who shuffles and deals (E.players, E.dealer): the players of a hand are the seats of state.order still
    in their chair, not leaving and not away (a record flagged gone, rule 2, is nobody's), ascending ({}
    before the first hand); the dealer is the button while it is one of them, else the next of them
    clockwise after it (nil without a button).
19. A street or the showdown on a state that lacks one of its faces (a view): E.system returns
    {k="street"/"showdown", need="faces"}, 0; the faces come from whoever holds the deck.

HAND HANDSHAKE (the deck comes from the fairness layer, so the engine cannot deal on its own)
 - phase "idle"/"done": E.system returns {k="hand"} once 2+ seats can play. The host applies it: the button
   moves, the blinds are posted, state.order (the hand's seats in dealing order) is fixed, phase "deal".
   state.order is who takes part in the commit-reveal shuffle.
 - phase "deal": E.system returns {k="deal", need="deck"}, 0 (randomness: apply refuses an action carrying
   need with "need"). The host runs the shuffle and applies {k="deal", deck = faces}, the
   full deck (deck[i] = E.DECK[p[i]]). A member applies {k="deal"} without the deck (or with a partial
   one) to its view, then {k="show", cards = {[i] = face}} with its own two cards. Phase "bet".
   If leaves fold all but one player meanwhile, that hand is already settled (phase "done") and the deal
   is refused with "phase": the host drops that shuffle.
 - phase "bet": the seat on turn (state.turn) acts; the host's turn timer applies E.auto.
 - phase "street": E.system returns {k="street", cards = {[i] = face}} = the next street's faces (flop,
   turn or river); applied everywhere, it deals that street.
 - phase "showdown": E.system returns {k="showdown", cards = {[i] = face}} = the board and every live hand;
   applied everywhere, it settles the pots. Phase "done" ("closed" after a close), state.last is the record.
 - At the table only the dealer (E.dealer) holds the deck: on everybody else's view E.system says
   {k="street"/"showdown", need="faces"} (rule 19); the dealer supplies the street and the showdown with
   their faces and the host applies that action everywhere.
 - {k="show", cards} at seat 0 fills faces on a view; on the full state it only checks them.
]==]
local _, ns = ...
ns.Engines = ns.Engines or {}
local H = ns.HoldemEval

-- maxSeats is what a table offers (the message budget of the sealed deal, see the stage E plan); the
-- engine itself plays any seats it is given on its 9 chairs.
local E = { id = "holdem", minSeats = 2, maxSeats = 6, start = "host",
  ext = { "fair", "cash" }, again = true, sealed = true, publicAuto = true, watchers = 1, botFill = 6,
  HAND_DELAY = 4, IDLE_DELAY = 2, STREET_DELAY = 1 }
ns.Engines.holdem = E

local CHAIRS = 9
E.DECK = {}
for _, su in ipairs({ "C", "D", "H", "S" }) do
  for _, r in ipairs({ "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A" }) do
    E.DECK[#E.DECK + 1] = r .. su
  end
end

E.options = {
  { id = "betting", choices = { "nl", "pl" }, default = "nl" },        -- No Limit / Pot Limit
  { id = "blinds", choices = { 10, 20, 50, 100, 200 }, default = 10 }, -- big blind; small blind = half
  { id = "stack", choices = { 50, 100, 200 }, default = 100 },         -- starting stack in big blinds
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function isInt(x) return type(x) == "number" and x % 1 == 0 end

local function choice(id, v)
  for _, o in ipairs(E.options) do
    if o.id == id then
      for _, c in ipairs(o.choices) do if c == v then return v end end
      return o.default
    end
  end
end

-- first seat after `from` (exclusive) clockwise over the 9 chairs that satisfies pred
local function nextSeat(from, pred)
  for d = 1, CHAIRS do
    local i = (from + d - 1) % CHAIRS + 1
    if pred(i) then return i end
  end
end

local function playingFn(s)
  return function(i) local st = s.seats[i]; return st and st.chips > 0 and not st.leaving and not st.away end
end
local function countPlaying(s)
  local n, f = 0, playingFn(s)
  for i = 1, CHAIRS do if f(i) then n = n + 1 end end
  return n
end

local function inHand(s) return s.phase == "deal" or s.phase == "bet" or s.phase == "street" or s.phase == "showdown" end
local function live(s, i) local p = s.p[i]; return p ~= nil and not p.folded end
local function canAct(s, i) local p = s.p[i]; return p ~= nil and not p.folded and not p.allin end
local function needs(s, i)
  local p = s.p[i]
  return canAct(s, i) and (not p.acted or p.bet < s.bet)
end

function E.new(opts)
  opts = opts or {}
  local o = type(opts.opt) == "table" and opts.opt or {}
  local bb = choice("blinds", o.blinds)
  local stack = choice("stack", o.stack) * bb          -- starting chips
  local first = opts.first
  if not isInt(first) or first < 1 or first > CHAIRS then first = 1 end
  local s = {
    stack = stack, bb = bb, sb = math.floor(bb / 2), betting = choice("betting", o.betting), first = first,
    seats = {}, phase = "idle", hand = 0, button = nil, sbSeat = nil, bbSeat = nil,
    order = {}, p = {}, deck = {}, board = {}, shown = {}, ptr = 0, street = 0,
    bet = 0, minRaise = bb, turn = nil, aggr = nil, last = nil,
  }
  for i = 1, CHAIRS do
    s.seats[i] = (type(opts.seats) == "table" and opts.seats[i]) and { chips = stack, out = false, leaving = false } or false
  end
  return s
end

-- ---------------------------------------------------------------- cards

-- Validates cards = {[i] = face}: indices in range (and in `allowed` when given), valid faces, no clash
-- with a known face at that index or the same face known at another index. Fills on success.
local function fillCards(s, cards, allowed)
  if type(cards) ~= "table" then return nil, "card" end
  local where = {}
  for i, f in pairs(s.deck) do where[f] = i end
  local seen = {}
  for i, f in pairs(cards) do
    if not isInt(i) or i < 1 or i > #E.DECK or (allowed and not allowed[i]) then return nil, "card" end
    if not H.valid(f) then return nil, "card" end
    if s.deck[i] ~= nil and s.deck[i] ~= f then return nil, "card" end
    if (where[f] and where[f] ~= i) or (seen[f] and seen[f] ~= i) then return nil, "card" end
    seen[f] = i
  end
  for i, f in pairs(cards) do s.deck[i] = f end
  return true
end

local function streetIdx(s)
  if s.street == 0 then return { s.ptr + 1, s.ptr + 2, s.ptr + 3 } end
  return { s.ptr + 1 }
end

local function showdownIdx(s)
  local idx = {}
  for _, i in ipairs(s.board) do idx[#idx + 1] = i end
  for _, seat in ipairs(s.order) do
    if live(s, seat) then
      for _, i in ipairs(s.p[seat].cards) do idx[#idx + 1] = i end
    end
  end
  return idx
end

local function facesOf(s, idx)
  local t = {}
  for _, i in ipairs(idx) do t[i] = s.deck[i] end
  return t
end

-- ---------------------------------------------------------------- settlement

local function sameSet(a, b)
  if #a ~= #b then return false end
  for k = 1, #a do if a[k] ~= b[k] then return false end end
  return true
end

-- The end of a hand once the chips are paid out and s.last is written: leavers go with their chips
-- (a taken chair gets the newcomer's fresh stack), a seat with 0 chips sits out.
local function settle(s)
  for i = 1, CHAIRS do
    local st = s.seats[i]
    if st and st.leaving then
      s.last.left[i] = st.chips
      s.seats[i] = st.taken and { chips = s.stack, out = false, leaving = false } or false
      s.p[i].gone = true          -- kept for the table display, no longer anyone's own hand
    elseif st then
      st.out = st.chips == 0
    end
  end
  s.phase, s.turn = s.closing and "closed" or "done", nil
end

-- scores: nil when everyone else folded; else {[seat] = score} for every live seat
local function finish(s, scores, cats, showOrder)
  local c, levels, seenL = {}, {}, {}
  for _, i in ipairs(s.order) do
    c[i] = s.p[i].total
    if c[i] > 0 and not seenL[c[i]] then seenL[c[i]] = true; levels[#levels + 1] = c[i] end
  end
  table.sort(levels)
  local pots, refund, prev = {}, {}, 0
  for _, L in ipairs(levels) do
    local payers, eligible = {}, {}
    for _, i in ipairs(s.order) do
      if c[i] >= L then
        payers[#payers + 1] = i
        if live(s, i) then eligible[#eligible + 1] = i end
      end
    end
    local amt, top = (L - prev) * #payers, pots[#pots]
    if #payers == 1 then
      refund[payers[1]] = (refund[payers[1]] or 0) + amt       -- uncalled
    elseif #eligible == 0 and top then
      top.amount = top.amount + amt                             -- dead chips join the pot below
    else
      if #eligible == 0 then
        for _, i in ipairs(s.order) do if live(s, i) then eligible[#eligible + 1] = i end end
      end
      if top and sameSet(top.eligible, eligible) then top.amount = top.amount + amt
      else pots[#pots + 1] = { amount = amt, eligible = eligible } end
    end
    prev = L
  end
  local won = {}
  for _, pot in ipairs(pots) do
    local winners = {}
    if scores then
      local best = -1
      for _, i in ipairs(pot.eligible) do if scores[i] > best then best = scores[i] end end
      for _, i in ipairs(pot.eligible) do if scores[i] == best then winners[#winners + 1] = i end end
    else
      winners = copy(pot.eligible)
    end
    pot.winners = winners
    local share = math.floor(pot.amount / #winners)
    local odd = pot.amount - share * #winners
    for k, i in ipairs(winners) do
      won[i] = (won[i] or 0) + share + (k <= odd and 1 or 0)
    end
  end
  local contrib = {}
  for _, i in ipairs(s.order) do
    contrib[i] = c[i] - (refund[i] or 0)
    local st = s.seats[i]
    st.chips = st.chips + (refund[i] or 0) + (won[i] or 0)
  end
  s.shown = {}
  for _, i in ipairs(showOrder or {}) do s.shown[i] = true end
  s.last = { hand = s.hand, contrib = contrib, won = won, pots = pots, shown = showOrder or {},
    cat = cats or {}, left = {} }
  settle(s)
end

-- After any change inside a hand: settle a fold-win, close the street, or move the turn.
-- from: the seat to search clockwise after; nil keeps the current turn while it still has to act.
local function progress(s, from)
  local nLive, actors = 0, {}
  for _, i in ipairs(s.order) do
    if live(s, i) then nLive = nLive + 1 end
    if canAct(s, i) then actors[#actors + 1] = i end
  end
  if nLive == 1 then return finish(s, nil) end
  if s.phase ~= "bet" then return end
  local closed
  if #actors == 0 then
    closed = true
  elseif #actors == 1 then
    local me, maxOther = actors[1], 0
    for _, i in ipairs(s.order) do
      if i ~= me and live(s, i) and s.p[i].bet > maxOther then maxOther = s.p[i].bet end
    end
    closed = s.p[me].bet >= maxOther
  else
    closed = true
    for _, i in ipairs(actors) do if needs(s, i) then closed = false end end
  end
  if closed then
    s.turn = nil
    s.phase = s.street == 3 and "showdown" or "street"
    return
  end
  if from == nil and s.turn and needs(s, s.turn) then return end
  s.turn = nextSeat(from or s.turn, function(i) return needs(s, i) end)
end

-- ---------------------------------------------------------------- table actions

local function startHand(s)
  if s.phase ~= "idle" and s.phase ~= "done" then return nil, "phase" end
  if countPlaying(s) < 2 then return nil, "players" end
  local playing = playingFn(s)
  local button = s.button and nextSeat(s.button, playing) or nextSeat(s.first - 1, playing)
  local order, i = {}, button
  repeat
    i = nextSeat(i, playing)
    order[#order + 1] = i
  until i == button
  s.button, s.order, s.p = button, order, {}
  for _, seat in ipairs(order) do
    s.p[seat] = { bet = 0, total = 0, folded = false, allin = false, acted = false, at = 0, cards = {} }
  end
  if #order == 2 then s.sbSeat, s.bbSeat = button, order[1]
  else s.sbSeat, s.bbSeat = order[1], order[2] end
  local function post(seat, amount)
    local p, st = s.p[seat], s.seats[seat]
    local x = math.min(amount, st.chips)
    st.chips, p.bet, p.total = st.chips - x, p.bet + x, p.total + x
    if st.chips == 0 then p.allin = true end
  end
  post(s.sbSeat, s.sb)
  post(s.bbSeat, s.bb)
  s.hand = s.hand + 1
  s.deck, s.board, s.shown, s.ptr, s.street = {}, {}, {}, 0, 0
  s.bet, s.minRaise, s.turn, s.aggr = s.bb, s.bb, nil, nil
  s.phase = "deal"
  return true
end

local function deal(s, a)
  if s.phase ~= "deal" then return nil, "phase" end
  if a.deck ~= nil then
    if type(a.deck) ~= "table" then return nil, "card" end
    local saved = s.deck
    s.deck = {}
    local okFill = fillCards(s, a.deck)
    if not okFill then s.deck = saved; return nil, "card" end
  else
    s.deck = {}
  end
  local n = #s.order
  for j, seat in ipairs(s.order) do s.p[seat].cards = { j, n + j } end
  s.ptr = 2 * n + 1          -- the first burn card
  s.phase = "bet"
  progress(s, s.bbSeat)
  return true
end

local function street(s, a)
  if s.phase ~= "street" then return nil, "phase" end
  local idx = streetIdx(s)
  if a.cards ~= nil then
    local allowed = {}
    for _, i in ipairs(idx) do allowed[i] = true end
    local okFill, why = fillCards(s, a.cards, allowed)
    if not okFill then return nil, why end
  end
  for _, i in ipairs(idx) do s.board[#s.board + 1] = i end
  s.ptr = s.ptr + #idx + 1   -- next burn card
  s.street = s.street + 1
  for _, i in ipairs(s.order) do
    local p = s.p[i]
    p.bet, p.acted, p.at = 0, false, 0
  end
  s.bet, s.minRaise, s.aggr, s.turn = 0, s.bb, nil, nil
  s.phase = "bet"
  progress(s, s.button)
  return true
end

local function showdown(s, a)
  if s.phase ~= "showdown" then return nil, "phase" end
  local idx = showdownIdx(s)
  local cards = a.cards or {}
  local allowed = {}
  for _, i in ipairs(idx) do
    allowed[i] = true
    if s.deck[i] == nil and (type(cards) ~= "table" or cards[i] == nil) then return nil, "card" end
  end
  local okFill, why = fillCards(s, cards, allowed)
  if not okFill then return nil, why end
  local scores, cats, order = {}, {}, {}
  for _, seat in ipairs(s.order) do
    if live(s, seat) then
      local f = {}
      for _, i in ipairs(s.board) do f[#f + 1] = s.deck[i] end
      for _, i in ipairs(s.p[seat].cards) do f[#f + 1] = s.deck[i] end
      scores[seat], cats[seat] = H.best(f)
    end
  end
  local first = (s.aggr and live(s, s.aggr)) and s.aggr or nextSeat(s.button, function(i) return live(s, i) end)
  local i = first
  repeat
    order[#order + 1] = i
    i = nextSeat(i, function(x) return live(s, x) end)
  until i == first
  finish(s, scores, cats, order)
  return true
end

local function leave(s, seat)
  if not isInt(seat) or seat < 1 or seat > CHAIRS or not s.seats[seat] then return nil, "seat" end
  local st, p = s.seats[seat], s.p[seat]
  if inHand(s) and p then
    if st.leaving then st.taken = nil; return true end   -- a newcomer on the chair stands up again
    st.leaving = true
    if not p.folded then
      p.folded = true
      progress(s, s.turn == seat and seat or nil)
    end
  else
    s.seats[seat] = false
    if p then p.gone = true end   -- last hand's record of this chair belongs to nobody now
  end
  return true
end

-- rule 2: an empty chair, or one whose player stood up during this hand (the leaver's hand is gone at once)
local function join(s, seat)
  if s.closing then return nil, "phase" end
  if not isInt(seat) or seat < 1 or seat > CHAIRS then return nil, "seat" end
  local st = s.seats[seat]
  if not st then
    s.seats[seat] = { chips = s.stack, out = false, leaving = false }
    return true
  end
  if not (inHand(s) and st.leaving and not st.taken) then return nil, "seat" end
  st.taken, s.p[seat].gone = true, true
  return true
end

-- rule 15: every chip back, nothing shown, the hand is over
local function void(s)
  if not inHand(s) then return nil, "phase" end
  for _, i in ipairs(s.order) do
    local p, st = s.p[i], s.seats[i]
    if st then st.chips = st.chips + p.total end
    p.bet, p.total = 0, 0
  end
  s.shown = {}
  s.last = { hand = s.hand, void = true, contrib = {}, won = {}, pots = {}, shown = {}, cat = {}, left = {} }
  settle(s)
  return true
end

-- rule 16: the seat sits out; in a hand it is folded as a leave folds it, but it keeps its chair
local function away(s, seat)
  local st = isInt(seat) and s.seats[seat]
  if not st or st.away then return nil, "seat" end
  local p = s.p[seat]
  st.away = true
  if inHand(s) and p and not p.folded then
    p.folded = true
    progress(s, s.turn == seat and seat or nil)
  end
  return true
end

-- rule 17: the running hand is played out, then the game is over
local function close(s)
  if s.closing then return nil, "phase" end
  s.closing = true
  if not inHand(s) then s.phase, s.turn = "closed", nil end
  return true
end

-- ---------------------------------------------------------------- player actions

local function otherHasChips(s, seat)
  for _, i in ipairs(s.order) do
    if i ~= seat and canAct(s, i) then return true end
  end
  return false
end

local function canRaise(s, seat)
  local p, st = s.p[seat], s.seats[seat]
  if st.chips <= s.bet - p.bet then return false end
  if p.acted and s.bet - p.at < s.minRaise then return false end
  return otherHasChips(s, seat)
end

-- The highest total `to` the seat may bet/raise to (rule 7): his whole stack in No Limit; in Pot Limit
-- also at most the bet plus the pot after his call. Second value: may he go all-in (stack within the cap).
local function raiseCap(s, seat)
  local p = s.p[seat]
  local stackTo = p.bet + s.seats[seat].chips
  if s.betting ~= "pl" then return stackTo, true end
  local pot = 0
  for _, i in ipairs(s.order) do pot = pot + s.p[i].total end
  local toCall = s.bet - p.bet
  local potTo = s.bet + pot + toCall
  if stackTo <= potTo then return stackTo, true end
  return potTo, false
end

local function act(s, seat, a)
  if not isInt(seat) or seat < 1 or seat > CHAIRS then return nil, "seat" end
  if s.phase ~= "bet" then return nil, "phase" end
  if s.turn ~= seat then return nil, "turn" end
  local p, st, k = s.p[seat], s.seats[seat], a.k
  local toCall = s.bet - p.bet
  local function put(x)
    st.chips, p.bet, p.total = st.chips - x, p.bet + x, p.total + x
    if st.chips == 0 then p.allin = true end
  end
  if k == "fold" then
    p.folded = true
  elseif k == "check" then
    if toCall > 0 then return nil, "action" end
  elseif k == "call" then
    if toCall <= 0 then return nil, "action" end
    put(math.min(toCall, st.chips))
  elseif k == "bet" or k == "raise" or k == "allin" then
    if not canRaise(s, seat) then return nil, "action" end
    local maxTo, allinOK = raiseCap(s, seat)
    local to
    if k == "allin" then
      if not allinOK then return nil, "amount" end
      to = maxTo
    else
      if (k == "bet") ~= (s.bet == 0) then return nil, "action" end
      to = a.to
      local min = k == "bet" and s.bb or s.bet + s.minRaise
      if not isInt(to) or to < min or to > maxTo then return nil, "amount" end
    end
    put(to - p.bet)
    if to - s.bet >= s.minRaise then s.minRaise = to - s.bet end
    s.bet, s.aggr = to, seat
  else
    return nil, "action"
  end
  p.acted, p.at = true, s.bet
  progress(s, seat)
  return true
end

-- ---------------------------------------------------------------- contract

function E.apply(s, seat, a)
  if type(a) ~= "table" then return nil, "action" end
  if a.need ~= nil then return nil, "need" end
  local k = a.k
  if k == "hand" or k == "deal" or k == "street" or k == "showdown" or k == "show"
     or k == "join" or k == "leave" or k == "void" or k == "away" or k == "close" then
    if seat ~= 0 then return nil, "seat" end
    if k == "hand" then return startHand(s) end
    if k == "deal" then return deal(s, a) end
    if k == "street" then return street(s, a) end
    if k == "showdown" then return showdown(s, a) end
    if k == "show" then return fillCards(s, a.cards) end
    if k == "leave" then return leave(s, a.seat) end
    if k == "void" then return void(s) end
    if k == "away" then return away(s, a.seat) end
    if k == "close" then return close(s) end
    return join(s, a.seat)
  end
  if k == "back" then                -- rule 16: in any phase, before the turn check
    local st = isInt(seat) and s.seats[seat]
    if not st or not st.away then return nil, "seat" end
    st.away = false
    return true
  end
  return act(s, seat, a)
end

function E.leave(s, seat)
  leave(s, seat)
  return true
end

function E.legal(s, seat)
  if s.phase ~= "bet" or s.turn == nil or s.turn ~= seat then return {} end
  local p = s.p[seat]
  local out = { { k = "fold" } }
  out[2] = (s.bet - p.bet > 0) and { k = "call" } or { k = "check" }
  if canRaise(s, seat) then
    local maxTo, allinOK = raiseCap(s, seat)
    local min = s.bet == 0 and s.bb or s.bet + s.minRaise
    if min < maxTo or (min == maxTo and not allinOK) then
      out[#out + 1] = { k = s.bet == 0 and "bet" or "raise", to = min, max = maxTo }
    end
    if allinOK then out[#out + 1] = { k = "allin" } end
  end
  return out
end

function E.auto(s, seat)
  if s.phase ~= "bet" or s.turn == nil or s.turn ~= seat then return nil end
  if s.bet - s.p[seat].bet > 0 then return { k = "fold" } end
  return { k = "check" }
end

-- A bot's move, on its view (nil off turn or without both own faces): a level 1-3 from its cards
-- (preflop the two ranks, postflop its best hand), a raise of half the pot now and then (40 / 8 / 3 in 100
-- by level), else check, call by level and price, or fold.
local function botLevel(s, mine)
  if #s.board == 0 then
    local a, b = H.rank(mine[1]), H.rank(mine[2])
    local hi, lo = math.max(a, b), math.min(a, b)
    local score
    if hi == lo then score = 40 + 2 * hi
    else
      score = hi + lo
      if H.suit(mine[1]) == H.suit(mine[2]) then score = score + 3 end
      if hi - lo <= 1 then score = score + 2 end
    end
    return score >= 26 and 3 or score >= 18 and 2 or 1
  end
  local f = { mine[1], mine[2] }
  for _, i in ipairs(s.board) do
    if s.deck[i] == nil then return nil end
    f[#f + 1] = s.deck[i]
  end
  local _, cat = H.best(f)
  return cat >= H.TWOPAIR and 3 or cat == H.PAIR and 2 or 1
end

function E.bot(s, seat, random)
  if s.phase ~= "bet" or s.turn == nil or s.turn ~= seat then return nil end
  local p = s.p[seat]
  local mine = { s.deck[p.cards[1]], s.deck[p.cards[2]] }
  if not mine[1] or not mine[2] then return nil end
  local level = botLevel(s, mine)
  if not level then return nil end
  local r, pot, toCall = random(1, 100), 0, s.bet - p.bet
  for _, i in ipairs(s.order) do pot = pot + s.p[i].total end
  if r <= (level == 3 and 40 or level == 2 and 8 or 3) then
    for _, a in ipairs(E.legal(s, seat)) do
      if a.k == "bet" or a.k == "raise" then
        return { k = a.k, to = math.max(a.to, math.min(a.max, s.bet + math.floor(pot / 2))) }
      end
    end
  end
  if toCall <= 0 then return { k = "check" } end
  if level == 3 or (level == 2 and toCall <= math.max(s.bb, math.floor(pot / 2)))
     or (level == 1 and toCall <= s.bb and r <= 50) then
    return { k = "call" }
  end
  return { k = "fold" }
end

function E.system(s)
  if s.phase == "idle" or s.phase == "done" then
    if countPlaying(s) >= 2 then return { k = "hand" }, s.phase == "done" and E.HAND_DELAY or E.IDLE_DELAY end
  elseif s.phase == "deal" then
    return { k = "deal", need = "deck" }, 0
  elseif s.phase == "street" or s.phase == "showdown" then
    local idx = s.phase == "street" and streetIdx(s) or showdownIdx(s)
    for _, i in ipairs(idx) do
      if s.deck[i] == nil then return { k = s.phase, need = "faces" }, 0 end   -- rule 19
    end
    return { k = s.phase, cards = facesOf(s, idx) }, E.STREET_DELAY
  end
end

E.inHand = inHand

-- rule 18: who shuffles: the hand's seats still seated and not away, ascending (a gone record is
-- nobody's: its chair was vacated, whoever sits there now was not dealt in)
local function here(s, i)
  local p, st = s.p[i], s.seats[i]
  return p ~= nil and not p.gone and st and not st.leaving and not st.away
end

function E.players(s)
  local t = {}
  for _, i in ipairs(s.order) do if here(s, i) then t[#t + 1] = i end end
  table.sort(t)
  return t
end

-- rule 18: who deals: the button, else the next of those seats after it
function E.dealer(s)
  if not s.button then return nil end
  if here(s, s.button) then return s.button end
  return nextSeat(s.button, function(i) return here(s, i) end)
end

function E.view(s, seat)
  local v = copy(s)
  local vis = {}
  for _, i in ipairs(s.board) do vis[i] = true end
  for st in pairs(s.shown) do
    for _, i in ipairs(s.p[st].cards) do vis[i] = true end
  end
  local own = seat and s.p[seat]
  if own and not own.gone then
    for _, i in ipairs(own.cards) do vis[i] = true end
  end
  v.deck = {}
  for i, f in pairs(s.deck) do if vis[i] then v.deck[i] = f end end
  return v
end

function E.hidden(s, seat)
  local p = s.p[seat]
  if not p or p.gone or s.shown[seat] then return {} end
  return copy(p.cards)
end

function E.result() return nil end
function E.over(s) return s.phase == "closed" end
function E.snapshot(s) return copy(s) end
function E.restore(t) return copy(t) end

return E
