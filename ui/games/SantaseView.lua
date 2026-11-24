local _, ns = ...

-- The Сантасе table (mockup 03 `santase`, cards of mockup 07 variant 1), 512 x
-- 260: the opponent's fan at the top (backs, faces only where my view knows
-- them); left at mid height the stock as a back with the face-up trump card
-- half under it (turned down once the stock is closed, gone once it is empty)
-- over the stock count and the trump suit; in the centre the trick, the
-- leader's card on the left; right of it, small and dimmed, the last trick;
-- at the right edge „Обяви 20/40“, „Смени деветката“ and „Затвори“, each only
-- while the engine allows it; at the bottom my fan, the playable cards raised
-- and the others dimmed when the rules forbid some; above it whose turn it is
-- or how the hand or the match ended; top left the match score.
-- „Обяви“ arms a declaration: only the kings and queens with a partner are
-- raised and a click on one declares it; a second click on „Обяви“, a click on
-- a card or any table event disarms it. Every move goes through client:act.
local Theme, W, L, Cards = ns.Theme, ns.W, ns.L, ns.Cards
local E = ns.Engines.santase

local WIDTH, HEIGHT = 512, 260
local OPP_SCALE, OPP_STEP, LAST_SCALE = 0.8, 20, 0.7
local MID_Y = -70                    -- top of the stock, the trick and the buttons
local TRICK_GAP = 16                 -- between the two cards of the trick
local STOCK_X, TRUMP_DX = 30, 22     -- the stock's left edge; the trump card that far right of it
local LAST_X = 72                    -- left edge of the last trick, right of the centre
local BUTTON_W, BUTTON_H, BUTTON_GAP = 124, 24, 6
local MY_FAN_Y, TEXT_Y = 14, 88      -- from the bottom of the frame
local SUITS = { C = 1, D = 2, H = 3, S = 4 }

local View = {}

local function suit(face) return face:sub(2, 2) end
local function value(face) return E.VALUE[face:sub(1, 1)] end

-- The cards of `seat` as {i, face} (face where the view knows it): by suit
-- C D H S, inside a suit by card points descending, unknown faces last in
-- hand order.
local function sortedHand(st, seat)
  local out = {}
  for pos, i in ipairs(st.hands and st.hands[seat] or {}) do
    out[#out + 1] = { i = i, face = st.deck[i], pos = pos }
  end
  table.sort(out, function(a, b)
    local fa, fb = a.face, b.face
    if (fa ~= nil) ~= (fb ~= nil) then return fa ~= nil end
    if fa and fb then
      if suit(fa) ~= suit(fb) then return SUITS[suit(fa)] < SUITS[suit(fb)] end
      if value(fa) ~= value(fb) then return value(fa) > value(fb) end
    end
    return a.pos < b.pos
  end)
  for _, c in ipairs(out) do c.pos = nil end
  return out
end

-- `seat`'s name: who held it during the match (`names`, the view's memory),
-- else who holds it now; nil for an empty seat.
local function nameOf(s, seat, names)
  local n = names and names[seat] or s.seats[seat]
  if type(n) == "string" then return n end
  return nil
end

local function textOf(s, st, mine, declare, names)
  local phase = st.phase
  if s:gameOver() then
    local gone = st.left and nameOf(s, st.left, names)
    if gone then return { "santase.left", gone } end
    local winner = st.winner and nameOf(s, st.winner, names)
    return winner and { "santase.match", winner } or nil
  elseif phase == "hand" then
    local res = st.res
    if not res then return nil end
    if res.winner == 0 then return { "santase.hand.tie" } end
    local winner = nameOf(s, res.winner, names)
    return winner and { "santase.hand.won", winner, res.gp } or nil
  elseif phase == "play" then
    if mine then return { declare and "santase.pick" or "santase.yourTurn" } end
    local turn = st.turn and nameOf(s, st.turn, names)
    return turn and { "santase.waitFor", turn } or nil
  end
  return nil
end

-- Everything the drawing needs; `declare`: „Обяви“ is armed. `names`
-- (optional): seat -> who held it during the match (see View.update).
function View.model(s, declare, names)
  local st = s.state
  local seated = s.mySeat == 1 or s.mySeat == 2
  local me = seated and s.mySeat or 1
  local opp = 3 - me
  local mine = seated and s.status == "live" and st.phase == "play" and st.turn == me
  local buttons, plays, marries = { close = false }, {}, {}
  if mine then
    for _, a in ipairs(E.legal(st, me)) do
      if a.k == "play" then
        plays[a.i] = true
      elseif a.k == "marry" then
        marries[a.i] = true
        local v = suit(a.c) == st.tsuit and 40 or 20
        -- a 40 and a 20 both in hand: the button names both, the card picked says which
        if buttons.marry and buttons.marry ~= v then buttons.marryBoth = true end
        buttons.marry = (buttons.marry == 40 or v == 40) and 40 or 20
      elseif a.k == "swap9" then
        buttons.swap = buttons.swap or a
      elseif a.k == "close" then
        buttons.close = true
      end
    end
  end

  local hand = sortedHand(st, me)
  local all = true
  for _, c in ipairs(hand) do all = all and plays[c.i] == true end
  for _, c in ipairs(hand) do
    if not mine then
      c.mode = "plain"
    elseif declare then
      c.mode = marries[c.i] and "raised" or "dim"
    elseif all then
      c.mode = "plain"
    else
      c.mode = plays[c.i] and "raised" or "dim"
    end
  end

  local oppHand = {}
  for _, i in ipairs(st.hands and st.hands[opp] or {}) do oppHand[#oppHand + 1] = { i = i, face = st.deck[i] } end
  local trick = {}
  for k, i in ipairs(st.trick or {}) do
    trick[k] = { seat = k == 1 and st.lead or 3 - st.lead, i = i, face = st.deck[i] }
  end
  local last = {}
  for k, i in ipairs(st.last or {}) do last[k] = st.deck[i] end

  return {
    me = me, opp = opp, mine = mine, hand = hand, oppHand = oppHand,
    stock = #(st.stock or {}), trump = st.trumpI and st.deck[st.trumpI] or nil, tsuit = st.tsuit,
    closed = st.closed ~= nil, trick = trick, last = last, buttons = buttons,
    text = textOf(s, st, mine, declare, names),
  }
end

-- „N точки“ on the plates while a hand runs.
function View.seatNote(s, seat)
  local st = s.state
  if not st or st.phase ~= "play" or (seat ~= 1 and seat ~= 2) then return "" end
  return L("santase.points", E.points(st, seat))
end

-- The pips on a plate: the tricks the seat took in the hand under way.
function View.seatTricks(s, seat)
  local st = s.state
  if not st or st.phase ~= "play" or (seat ~= 1 and seat ~= 2) then return nil end
  local won = st.won and st.won[seat]
  return won and #won / 2 or nil
end

---------------------------------------------------------------------------
-- Acting
---------------------------------------------------------------------------

-- What the table has seen: an event (or another table, or a new host) changes it.
local function eventKey(s) return tostring(s.tid) .. "/" .. tostring(s.epoch) .. "/" .. tostring(s.seq) end

-- My legal action of kind `k` (on card `i` when given), or nil.
local function legalAction(s, k, i)
  local st = s.state
  if not st or s.status ~= "live" or not (s.mySeat == 1 or s.mySeat == 2) then return nil end
  for _, a in ipairs(E.legal(st, s.mySeat)) do
    if a.k == k and (i == nil or a.i == i) then return a end
  end
  return nil
end

local function session()
  local client = ns.client
  local s = client and client.session
  if s and s.game == E.id and s.state then return client, s end
end

local function act(f, a)
  local client, s = session()
  f.armed = false
  if client and a then client:act(a) end
  if s then View.update(f, s) end
end

local function onCard(f, entry)
  local _, s = session()
  if not s then return end
  act(f, legalAction(s, f.armed and "marry" or "play", entry.i))
end

local function toggleArmed(f)
  local _, s = session()
  if not s then return end
  f.armed = not f.armed
  f.armedAt = eventKey(s)
  View.update(f, s)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function caption(f, style, size)
  local fs = W.Label(f, style, "", size)
  fs:SetWordWrap(false)
  return fs
end

function View.build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(WIDTH, HEIGHT)
  f.armed, f.names = false, {}
  local level = f:GetFrameLevel()

  f.score = caption(f, "dim", 12)
  f.score:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -18)

  f.oppFan = Cards.fan(f, { scale = OPP_SCALE, step = OPP_STEP })
  f.oppFan.frame:SetPoint("TOP", f, "TOP", 0, 0)

  f.trumpCard = Cards.card(f)
  f.trumpCard:level(level + 1)
  f.trumpCard.frame:SetPoint("TOPLEFT", f, "TOPLEFT", STOCK_X + TRUMP_DX, MID_Y - 4)
  f.stockCard = Cards.card(f)
  f.stockCard:level(level + 1 + Cards.LEVELS)
  f.stockCard.frame:SetPoint("TOPLEFT", f, "TOPLEFT", STOCK_X, MID_Y)
  f.stockText = caption(f, "dim", 11)
  f.stockText:SetPoint("TOPLEFT", f, "TOPLEFT", STOCK_X - 4, MID_Y - Cards.H - 8)
  f.trumpText = caption(f, "dim", 11)
  f.trumpText:SetPoint("TOPLEFT", f.stockText, "BOTTOMLEFT", 0, -2)

  f.trick = {}
  for k = 1, 2 do
    local card = Cards.card(f)
    local x = k == 1 and -(Cards.W + TRICK_GAP / 2) or TRICK_GAP / 2
    card.frame:SetPoint("TOPLEFT", f, "TOP", x, MID_Y)
    f.trick[k] = card
  end

  f.lastLabel = caption(f, "dim", 11)
  f.lastLabel:SetText(L("santase.last"))
  f.lastLabel:SetPoint("TOPLEFT", f, "TOP", LAST_X, MID_Y + 4)
  f.lastCards = {}
  for k = 1, 2 do
    local card = Cards.card(f, LAST_SCALE)
    card:look("dim")
    card.frame:SetPoint("TOPLEFT", f, "TOP", LAST_X + (k - 1) * (Cards.W * LAST_SCALE + 4), MID_Y - 12)
    f.lastCards[k] = card
  end

  f.marryButton = W.GoldButton(f, L("santase.marry40"), function() toggleArmed(f) end)
  f.swapButton = W.GhostButton(f, L("santase.swap"), "brassLight", function()
    local _, s = session()
    if s then act(f, legalAction(s, "swap9")) end
  end)
  f.closeButton = W.Button(f, L("santase.close"), function()
    local _, s = session()
    if s then act(f, legalAction(s, "close")) end
  end)
  f.closeButton:SetSize(BUTTON_W, BUTTON_H)
  f.buttons = { f.marryButton, f.swapButton, f.closeButton }

  f.myFan = Cards.fan(f)
  f.myFan.frame:SetPoint("BOTTOM", f, "BOTTOM", 0, MY_FAN_Y)
  f.text = W.Label(f, "heading", "", 15)
  f.text:SetJustifyH("CENTER")
  f.text:SetWordWrap(false)
  f.text:SetPoint("CENTER", f, "BOTTOM", 0, TEXT_Y)
  return f
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- Who sits where while the match runs, so the line at its end can still name
-- a player whose seat emptied when he left.
local function remember(f, s)
  if f.namesTid ~= s.tid then f.namesTid, f.names = s.tid, {} end
  if not s:gameOver() then
    for seat = 1, 2 do f.names[seat] = s.seats[seat] or nil end
  end
end

local function showCard(card, shown, face)
  if shown then card:set(face) end
  card.frame:SetShown(shown)
end

local function drawStock(f, m)
  local any = m.stock > 0
  showCard(f.stockCard, any, nil)
  showCard(f.trumpCard, any, (not m.closed) and m.trump or nil)
  local line1 = m.closed and L("santase.closed") or (any and L("santase.stock", m.stock)) or nil
  f.stockText:SetText(line1 or "")
  f.stockText:SetShown(line1 ~= nil)
  f.trumpText:SetText(m.tsuit and L("santase.trump", Cards.suitName(m.tsuit)) or "")
  f.trumpText:SetShown(m.tsuit ~= nil)
end

-- The visible buttons stacked at the right edge from the top of the middle band.
local function drawButtons(f, m)
  local b = m.buttons
  f.marryButton.text:SetText(L(b.marryBoth and "santase.marryBoth" or b.marry == 40 and "santase.marry40" or "santase.marry20"))
  f.marryButton.lit = f.armed
  f.marryButton.edges.setColor(Theme.rgb(f.armed and "gold" or "brass"))
  f.marryButton:SetShown(b.marry ~= nil)
  f.swapButton:SetShown(b.swap ~= nil)
  f.closeButton:SetShown(b.close)
  local y = MID_Y
  for _, button in ipairs(f.buttons) do
    if button:IsShown() then
      button:ClearAllPoints()
      button:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
      y = y - BUTTON_H - BUTTON_GAP
    end
  end
end

-- The line of text; the match's end line hides under the bill of a staked match (ns.StakePanels.shown).
local function drawText(f, s, m)
  local t = m.text
  if not t or (s:gameOver() and ns.StakePanels.shown) then
    f.text:SetText("")
    f.text:Hide()
    return
  end
  local args = {}
  for k = 2, #t do args[k - 1] = t[k] end
  if type(args[1]) == "string" then args[1] = W.colored(ns.client, args[1]) end
  f.text:SetText(L(t[1], unpack(args)))
  local phase = s.state.phase
  f.text:SetTextColor(Theme.rgb((phase == "hand" or s:gameOver()) and "gold" or "ink"))
  f.text:Show()
end

function View.update(f, s)
  f.session = s
  local st = s.state
  remember(f, s)
  local hand, mine = st.hand or 0, View.seatTricks(s, s.mySeat) or 0
  ns.Sounds.once("deal", s.tid .. ":" .. hand, s.tid, hand > 0)
  ns.Sounds.once("trick", s.tid .. ":" .. hand .. ":" .. mine, s.tid, mine > 0)
  if f.armedAt ~= eventKey(s) then f.armed = false end
  local m = View.model(s, f.armed, f.names)
  if f.armed and not (m.mine and m.buttons.marry) then
    f.armed = false
    m = View.model(s, false, f.names)
  end

  local last = st.last or {}
  local key = #last > 0 and (tostring(st.hand) .. ":" .. table.concat(last, ",")) or nil
  local holding = ns.TrickHold.check(f, s.tid, key, #(st.trick or {}) > 0, function()
    if f.session == s then View.update(f, s) end
  end)
  if holding then -- the trick just taken stays on the felt; its small copy waits
    m.trick, m.last = { { seat = 0, i = last[1], face = m.last[1] }, { seat = 0, i = last[2], face = m.last[2] } }, {}
  end

  f.score:SetText(L("santase.score", st.gp[m.me], st.gp[m.opp]))
  local opp = {}
  for k, c in ipairs(m.oppHand) do opp[k] = { i = c.i, face = c.face, mode = "plain" } end
  f.oppFan:set(opp)
  drawStock(f, m)
  for k = 1, 2 do
    local c = m.trick[k]
    showCard(f.trick[k], c ~= nil, c and c.face)
  end
  local hasLast = #m.last > 0
  f.lastLabel:SetShown(hasLast)
  for k = 1, 2 do
    local face = m.last[k]
    showCard(f.lastCards[k], hasLast and k <= #m.last, face)
  end
  drawButtons(f, m)
  f.myFan:set(m.hand, function(entry) onCard(f, entry) end)
  drawText(f, s, m)
end

ns.TableFrame.registerView(E.id, View)
