local _, ns = ...

-- The hand history of the table I sit or watch at (Белот, Сантасе, Холдем): a
-- recorder fed by the client's "session" event, the same state the views draw,
-- kept in memory only (never saved, never sent), the last MAX hands of the
-- table, dropped as soon as I leave it (no session, or another table). The
-- panel that shows it is ui/HandHistoryPanel.lua. A snapshot (my events jumped,
-- or another epoch) keeps the hand's record and reads the next change from it.
--
-- It records only what the whole table has seen face up, whatever else my view
-- may know:
--   Белот / Сантасе: the cards played to a trick (st.trick, st.last), the
--     contract (the auction is public), the trump suit (the face-up card),
--     Сантасе's declarations (the points of st.mar), the close and the swap of
--     the nine, the hand's result. Never a face of a hand or of the stock, not
--     even once the match is over and the view holds every face.
--   Холдем: the blinds, every action (fold / check / call / bet / raise /
--     all-in, from what each seat put in: st.p), the board, the result, the
--     hole cards of the seats in st.last.shown (the showdown), those an all-in
--     turned up before it (E.faceUp, once every one of them is face up on my state:
--     open = {{seat, cards, at = the street}}) and my own two cards (s.mySeat;
--     marked as mine when drawn). Never a folded or unshown hand.
--
-- HandHistory.tables[tid] = { game, hands = { oldest … newest }, ver } and a
-- hand = { key, no, names = {seat -> name}, … }:
--   card games: tricks = {[n] = { cards = {{seat, face}…}, win }}, cur (the trick
--     under way), contract (Белот), tsuit, events = {{at = trick, k, seat, pts}},
--     res (Сантасе);
--   Холдем: sb, bb, acts = {{street, seat, k, amt}…}, board = {faces}, mine,
--     me, open, shown = {{seat, cards, cat}}, won = {{seat, amt}}, void, done.
local E = ns.Engines

local H = { MAX = 10, GAMES = { belot = true, santase = true, holdem = true }, tables = {} }
ns.HandHistory = H

local function suit(face) return type(face) == "string" and face:sub(2, 2) or nil end

-- The record of table s, a new one for another game.
local function bookOf(s)
  local b = H.tables[s.tid]
  if not b or b.game ~= s.game then
    b = { game = s.game, hands = {}, ver = 0 }
    H.tables[s.tid] = b
  end
  return b
end

-- The record of hand `no` of game `gid` (Холдем's state.g where core/Cash.lua set it at
-- `start`, else none: a new game is seen by its hand count going back, see holdem();
-- none for the card games, whose new match begins with a "deal" phase that closes the
-- last hand): the newest one, or a new one on top while that is another hand, closed,
-- or ended with its game (`over`: the state is still that game's end). Never s.gameNo,
-- which every adopted snapshot moves on. The oldest beyond MAX go. -> hand, fresh
local function handOf(b, no, gid, over)
  local key = tostring(gid or "") .. ":" .. tostring(no)
  local top = b.hands[#b.hands]
  if top and top.key == key and not top.closed and (over or not top.ended) then
    top.ended = top.ended or over
    return top, false
  end
  local hand = { key = key, no = no, names = {}, tricks = {}, events = {}, acts = {}, board = {}, ended = over }
  b.hands[#b.hands + 1] = hand
  while #b.hands > H.MAX do table.remove(b.hands, 1) end
  return hand, true
end

local function close(b)
  local top = b.hands[#b.hands]
  if top then top.closed = true end
end

-- Who holds each seat, kept from the first time the hand saw it.
local function names(hand, s, n)
  for seat = 1, n do
    local who = s.handNames and s.handNames[seat]
    if type(who) ~= "string" then who = s.seats and s.seats[seat] end
    if hand.names[seat] == nil and type(who) == "string" then hand.names[seat] = who end
  end
end

---------------------------------------------------------------------------
-- Белот: st.last = { cards, lead, win }; the tricks done = st.took[1] + st.took[2]
---------------------------------------------------------------------------

local function belot(s, st, b)
  local phase, top = st.phase, b.hands[#b.hands]
  if phase == "deal" then -- between deals, or a void: the next deal is another hand
    local res = st.res -- a passed-out deal leaves res without a contract, naming its round; a void none
    if top and not top.closed and res and res.contract == nil and res.round == top.no then top.passed = true end
    return close(b)
  end
  if phase == "match" and top then top.ended = true end
  if phase ~= "bid" and phase ~= "play" and phase ~= "score" then return end
  local hand = handOf(b, st.round)
  names(hand, s, 4)
  local c = st.contract
  if c then hand.contract = { seat = c.seat, b = c.b, x = c.x } end
  if phase == "bid" then return end
  local done = (st.took and st.took[1] or 0) + (st.took and st.took[2] or 0)
  local last = st.last
  if last and done > 0 and not hand.tricks[done] then
    local cards = {}
    for k, i in ipairs(last.cards) do cards[k] = { seat = (last.lead + k - 2) % 4 + 1, face = st.deck[i] } end
    hand.tricks[done] = { cards = cards, win = last.win }
  end
  hand.cur = nil
  if st.trick and #st.trick > 0 and st.lead then
    local cards = {}
    for k, i in ipairs(st.trick) do cards[k] = { seat = (st.lead + k - 2) % 4 + 1, face = st.deck[i] } end
    hand.cur = { n = done + 1, cards = cards }
  end
end

---------------------------------------------------------------------------
-- Сантасе: st.last = { led, answer }; its winner leads now (st.lead); the tricks
-- done = st.ntr[1] + st.ntr[2]
---------------------------------------------------------------------------

-- Did the answer `rf` beat the led `lf` under trump suit ts (rule 4)?
local function beats(lf, rf, ts)
  if not lf or not rf then return false end
  if suit(rf) == suit(lf) then return E.santase.VALUE[rf:sub(1, 1)] > E.santase.VALUE[lf:sub(1, 1)] end
  return suit(rf) == ts
end

local function event(hand, at, k, seat, pts)
  hand.events[#hand.events + 1] = { at = at, k = k, seat = seat, pts = pts }
end

local function santase(s, st, b)
  local phase = st.phase
  if phase == "deal" then return close(b) end
  if phase ~= "play" and phase ~= "hand" and phase ~= "match" then return end
  local hand = handOf(b, st.hand, nil, phase == "match")
  if b.jump then hand.was = nil end
  names(hand, s, 2)
  hand.tsuit = hand.tsuit or st.tsuit
  local done = (st.ntr and st.ntr[1] or 0) + (st.ntr and st.ntr[2] or 0)
  local nine = st.trumpI ~= nil and st.tsuit ~= nil and st.deck[st.trumpI] == "9" .. st.tsuit -- the face-up card is the nine (kept as a flag, not a face)
  local was = hand.was
  if was then -- numbers and flags only: no face is kept from them
    local at = #(st.trick or {}) == 1 and done + 1 or done
    for seat = 1, 2 do
      local pts = (st.mar[seat] or 0) - (was.mar[seat] or 0)
      if pts > 0 then event(hand, at, "marry", seat, pts) end
    end
    if st.closed and not was.closed then event(hand, done + 1, "close", st.closed) end
    if nine and not was.nine and was.trumpI and st.trumpI ~= was.trumpI then
      event(hand, done + 1, "swap", st.turn)
    end
  end
  hand.was = { mar = { st.mar[1], st.mar[2] }, closed = st.closed, trumpI = st.trumpI, nine = nine }
  local last = st.last
  if done > 0 and last and #last == 2 and not hand.tricks[done] and st.lead then
    local lf, rf = st.deck[last[1]], st.deck[last[2]]
    local win = st.lead
    local led = beats(lf, rf, st.tsuit) and 3 - win or win
    hand.tricks[done] = { cards = { { seat = led, face = lf }, { seat = 3 - led, face = rf } }, win = win }
  end
  hand.cur = nil
  if st.trick and #st.trick == 1 and st.lead then
    hand.cur = { n = done + 1, cards = { { seat = st.lead, face = st.deck[st.trick[1]] } } }
  end
  if (phase == "hand" or phase == "match") and st.res and not hand.res then
    hand.res = { winner = st.res.winner, gp = st.res.gp }
  end
end

---------------------------------------------------------------------------
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
  local hand, fresh = handOf(b, st.hand, st.g)
  if b.jump then hand.was = nil end -- after a snapshot: nothing is read against the state before it
  names(hand, s, #st.seats)
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

local RECORD = { belot = belot, santase = santase, holdem = holdem }

-- The client's session changed (s, nil once I left): another table's history goes,
-- the table's state is read into its own.
function H.observe(s)
  for tid in pairs(H.tables) do
    if not s or tid ~= s.tid then H.tables[tid] = nil end
  end
  if not s or not H.GAMES[s.game] or type(s.state) ~= "table" then return end
  local b = bookOf(s)
  -- A snapshot (another epoch, or my events jumped: Member.adopt) replaces the state at once:
  -- the next change is read from it, not from the state before it.
  b.jump = b.seq ~= nil and (s.epoch ~= b.epoch or (s.seq ~= b.seq and s.seq ~= b.seq + 1))
  b.seq, b.epoch = s.seq, s.epoch
  RECORD[s.game](s, s.state, b)
  b.ver = b.ver + 1
end

ns.ready(function(client)
  client:on("session", function(s)
    -- a fault in the history must never stop the table: it is noted, not raised
    local fine, why = pcall(H.observe, s)
    if not fine then H.lastError = why end
  end)
end)
