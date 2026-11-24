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
--     the face-up trump card (Сантасе), Сантасе's declarations (the points of
--     st.mar, the suit of the card they lead: both of the pair are shown), the
--     close and the swap of the nine, the hand's result (Сантасе: its points,
--     E.points; Белот: the team totals of st.res.raw). Never a face of a hand or
--     of the stock, not even once the match is over and the view holds every face.
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
--     under way), contract (Белот), score = {us, them} and valat (Белот: st.res.raw),
--     tsuit, trump (the face-up card), shut (closed), events = {{at = trick, k, seat,
--     pts, suit}}, res = {winner, gp, pts} (Сантасе);
--   Холдем: sb, bb, acts = {{street, seat, k, amt}…}, board = {faces}, mine,
--     me, open, shown = {{seat, cards, cat}}, won = {{seat, amt}}, void, done.
local E = ns.Engines

local H = { MAX = 10, GAMES = { belot = true, santase = true, holdem = true }, RECORD = {}, BLOCK = {}, tables = {} }
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
function H.handOf(b, no, gid, over)
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
function H.names(hand, s, n)
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
  local res = st.res -- the deal just scored: its team totals, as the table's score shows them
  if top and not top.closed and not top.score and res and res.contract and res.raw and res.round == top.no then
    top.score, top.valat = { res.raw[1], res.raw[2] }, res.valat or nil
  end
  if phase == "deal" then -- between deals, or a void: the next deal is another hand
    -- a passed-out deal leaves res without a contract, naming its round; a void none
    if top and not top.closed and res and res.contract == nil and res.round == top.no then top.passed = true end
    return close(b)
  end
  if phase == "match" and top then top.ended = true end
  if phase ~= "bid" and phase ~= "play" and phase ~= "score" then return end
  local hand = H.handOf(b, st.round)
  H.names(hand, s, 4)
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

local function event(hand, at, k, seat, pts, su)
  hand.events[#hand.events + 1] = { at = at, k = k, seat = seat, pts = pts, suit = su }
end

local function santase(s, st, b)
  local phase = st.phase
  if phase == "deal" then return close(b) end
  if phase ~= "play" and phase ~= "hand" and phase ~= "match" then return end
  local hand = H.handOf(b, st.hand, nil, phase == "match")
  if b.jump then hand.was = nil end
  H.names(hand, s, 2)
  hand.tsuit = hand.tsuit or st.tsuit
  hand.trump = hand.trump or st.trumpI and st.deck[st.trumpI] -- face up under the stock, for all
  hand.shut = hand.shut or st.closed ~= nil or nil
  local done = (st.ntr and st.ntr[1] or 0) + (st.ntr and st.ntr[2] or 0)
  local nine = st.trumpI ~= nil and st.tsuit ~= nil and st.deck[st.trumpI] == "9" .. st.tsuit -- the face-up card is the nine (kept as a flag, not a face)
  local was = hand.was
  if was then -- numbers and flags only: no face is kept from them
    local led = #(st.trick or {}) == 1 and st.trick[1] or st.last and st.last[1] -- the pair's card led
    local at = #(st.trick or {}) == 1 and done + 1 or done
    for seat = 1, 2 do
      local pts = (st.mar[seat] or 0) - (was.mar[seat] or 0)
      if pts > 0 then event(hand, at, "marry", seat, pts, suit(led and st.deck[led])) end
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
    hand.res = { winner = st.res.winner, gp = st.res.gp, pts = { E.santase.points(st, 1), E.santase.points(st, 2) } }
  end
end

H.RECORD.belot, H.RECORD.santase = belot, santase

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
  H.RECORD[s.game](s, s.state, b)
  b.ver = b.ver + 1
end

ns.ready(function(client)
  client:on("session", function(s)
    -- a fault in the history must never stop the table: it is noted, not raised
    local fine, why = pcall(H.observe, s)
    if not fine then H.lastError = why end
  end)
end)
