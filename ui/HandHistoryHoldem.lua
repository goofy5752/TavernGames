local _, ns = ...

-- The Холдем part of the hand history's recorder (ui/HandHistory.lua: its rules of what is
-- recorded, its record of a hand).
local E = ns.Engines
local H = ns.HandHistory

-------------------------------------------------------------------------
-- Холдем: each event's change of st.p, seat by seat, against the last one seen
---------------------------------------------------------------------------

local function act(hand, street, seat, k, amt)
  hand.acts[#hand.acts + 1] = { street = street, seat = seat, k = k, amt = amt }
end

-- The seats' state the next event is read against.
local function snapshot(st)
  local p = {}
  for _, i in ipairs(st.order or {}) do
    local q = st.p[i]
    if q then p[i] = { folded = q.folded, total = q.total, allin = q.allin, acted = q.acted } end
  end
  return { p = p, bet = st.bet, street = st.street, turn = st.turn, phase = st.phase }
end

-- What each seat did since `was`: a fold, more chips in (all-in, a bet or raise to
-- its bet on the street, else a call of what it added), or a check on its turn.
local function diff(hand, st, was)
  for _, i in ipairs(st.order or {}) do
    local p, q = st.p[i], was.p[i]
    if p and q then
      if p.folded and not q.folded then
        act(hand, was.street, i, "fold")
      elseif p.total > q.total then
        local k = p.allin and not q.allin and "allin" or st.bet > was.bet and (was.bet == 0 and "bet" or "raise") or "call"
        act(hand, was.street, i, k, k == "call" and p.total - q.total or p.bet)
      elseif p.acted and not q.acted and i == was.turn and was.phase == "bet" and not p.folded then
        act(hand, was.street, i, "check")
      end
    end
  end
end

local function holdem(s, st, b)
  local top = b.hands[#b.hands]
  -- a new game at the table: its hand count is back at 0, or below the last hand's
  if top and ((st.hand or 0) < 1 or st.hand < top.no) then top.closed = true end
  local inHand = E.holdem.inHand(st)
  local last = st.last and st.last.hand == st.hand and st.last or nil
  if not inHand and not last or (st.hand or 0) < 1 then return end
  local hand, fresh = H.handOf(b, st.hand, st.g)
  if b.jump then hand.was = nil end -- after a snapshot: nothing is read against the state before it
  H.names(hand, s, #st.seats)
  hand.sb, hand.bb = st.sb, st.bb
  if fresh then
    for _, x in ipairs({ { st.sbSeat, "sb", st.sb }, { st.bbSeat, "bb", st.bb } }) do
      local p = x[1] and st.p[x[1]]
      if p then act(hand, 0, x[1], x[2], math.min(x[3], p.total)) end -- a short blind posts what it has
    end
  elseif hand.was and not hand.done then
    diff(hand, st, hand.was)
  end
  hand.was = snapshot(st)
  for k = #hand.board + 1, #(st.board or {}) do
    local face = st.deck[st.board[k]]
    if not face then break end
    hand.board[k] = face
  end
  local me = s.mySeat
  local mine = type(me) == "number" and st.p[me]
  if not hand.mine and mine and not mine.gone and mine.cards[1] then
    local f1, f2 = st.deck[mine.cards[1]], st.deck[mine.cards[2]]
    if f1 and f2 then hand.mine, hand.me = { f1, f2 }, me end
  end
  local open = {}
  for _, seat in ipairs(hand.done and {} or E.holdem.faceUp(st)) do -- rule 11a: all of them up on my state, or none yet
    local p = st.p[seat]
    local f1, f2 = st.deck[p.cards[1]], st.deck[p.cards[2]]
    if not (f1 and f2) then open = nil; break end
    open[#open + 1] = { seat = seat, cards = { f1, f2 }, at = st.street }
  end
  hand.open = hand.open or {}
  local had = {}
  for _, x in ipairs(hand.open) do had[x.seat] = true end
  for _, x in ipairs(open or {}) do if not had[x.seat] then hand.open[#hand.open + 1] = x end end
  if last and not hand.done then
    hand.done, hand.void = true, last.void == true
    hand.shown, hand.won = {}, {}
    for _, seat in ipairs(last.shown or {}) do -- the showdown: these hands were turned up for all
      local p = st.p[seat]
      local f1, f2 = p and st.deck[p.cards[1]], p and st.deck[p.cards[2]]
      if f1 and f2 then hand.shown[#hand.shown + 1] = { seat = seat, cards = { f1, f2 }, cat = last.cat and last.cat[seat] } end
    end
    for seat = 1, #st.seats do
      local amt = last.won and last.won[seat]
      if amt and amt > 0 then hand.won[#hand.won + 1] = { seat = seat, amt = amt } end
    end
  end
end

H.RECORD.holdem = holdem

-- The same reading for the table's sounds (ui/games/HoldemSounds.lua): the seats' state an event is read
-- against, and what each seat did since it -> {{street, seat, k, amt}…} in seat order.
H.holdemSnapshot = snapshot
function H.holdemActs(st, was)
  local t = { acts = {} }
  diff(t, st, was)
  return t.acts
end
