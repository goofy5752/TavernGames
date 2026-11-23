local _, ns = ...

-- The Холдем table (mockup 07 variant 1) over the whole felt, 732 x 440, in a
-- frame of 760 x 532 (`size`); the six plates of the ring lie around it
-- (TableFrame, `ring = true`, ns.HallLayout.ring: me at the bottom, the next
-- seat at my left). It draws only what ns.HoldemModel.build returns: the oval
-- table, the board of five cards, the pot, each seat's two cards (mine big at
-- the bottom, the others' small; a face only where the model has one, none
-- while the deal is still shuffled, mine dimmed once I folded), its bet with
-- a chip or after a hand what it won, the dealer's disc and the blinds' marks
-- at the plates; the line of text, the note of a close and the log of the
-- last hand. Every chip count on the felt is View.amount: coins (chips x
-- HoldemCash.CHIP) at a cash table, where a chip is real silver; the bare
-- number at a fun one, with a chip in the skin's bannerHi beside a bet. On
-- my turn the bet buttons: „½ пот“, „Пот“, „Ва банк“, − and +
-- for the amount, „Пас“, „Чек“ / „Плащам“, „Залагам“ / „Вдигам до“; the host
-- of a running game has „Приключи“. The amount the buttons set is the view's
-- memory (`want`) until any table event; after an accepted action the buttons
-- are dead until the next event (`sent`). Every move goes through
-- client:act; the view never sends chat or rolls.
-- Offsets are from the felt's TOPLEFT, by k = (seat - me) % 6 (a watcher: me = 1).
local Theme, W, L, Cards = ns.Theme, ns.W, ns.L, ns.Cards
local E = ns.Engines.holdem
local M = ns.HoldemModel

local FELT_W, FELT_H = 732, 440
local SEATS = 6
local SMALL, SMALL_STEP, BIG_STEP = 0.6, 26, 46
local CARDS = { [0] = { 323, -322 }, [1] = { 166, -296 }, [2] = { 166, -76 }, [3] = { 341, -42 }, [4] = { 516, -76 }, [5] = { 516, -296 } }
local BET = { [0] = { 366, -300 }, [1] = { 250, -272 }, [2] = { 250, -134 }, [3] = { 366, -110 }, [4] = { 482, -134 }, [5] = { 482, -272 } }
local MARK_X, MARK = 138, 18      -- the dealer disc: centred on (plate.x + 138, plate.y)
local CHIP, CHIP_GAP = 16, 3
local BOARD_X, BOARD_Y, BOARD_STEP = 254, -176, 46
local CENTRE_X, POT_Y, TEXT_Y = 366, -156, -250
local LEFT_X, NOTE_Y, LOG_Y, LEFT_W = 12, -366, -396, 270 -- the note in the close button's place (never both)
local LABEL, LABEL_MIN, LABEL_PAD = 13, 10, 6 -- a button label shrinks to fit its button
local FOLDED_ALPHA, OFF_ALPHA = 0.5, 0.5
-- The finished hand's words with a hand category: the index of the category in the model's text.
local CAT_AT = { ["holdem.won"] = 4, ["holdem.split"] = 3, ["holdem.log"] = 5, ["holdem.logSplit"] = 4 }
-- The model's words with a chip count: the index of the amount in the model's text.
local AMOUNT_AT = { ["holdem.won"] = 3, ["holdem.wonFold"] = 3, ["holdem.split"] = 2, ["holdem.log"] = 4,
  ["holdem.logFold"] = 4, ["holdem.logSplit"] = 3, ["holdem.toCall"] = 2 }
-- The words after a hand, in gold.
local AFTER = { ["holdem.won"] = true, ["holdem.wonFold"] = true, ["holdem.split"] = true, ["holdem.void"] = true, ["holdem.closed"] = true }

local View = { ring = true, size = { 760, 532 } }

-- Is s a table for real money (ns.Stakes.cash) -> bool.
function View.cash(s) return ns.Stakes.cash(s) end

-- A chip count on the felt: coins at a cash table (ns.HoldemCashView.coins), the number at a fun one.
function View.amount(s, chips)
  if View.cash(s) then return ns.HoldemCashView.coins(chips) end
  return tostring(chips)
end

---------------------------------------------------------------------------
-- Acting
---------------------------------------------------------------------------

-- What the table has seen: an event (or another table, or a new host) changes it.
local function eventKey(s) return tostring(s.tid) .. "/" .. tostring(s.epoch) .. "/" .. tostring(s.seq) end

local function redraw(f)
  if f.session then View.update(f, f.session) end
end

-- An action to the client; accepted, the buttons are dead until the next event (not
-- the event it may already have drawn: the host plays it at once).
local function send(f, a)
  local client, key = ns.client, f.key
  if a and client and not f.sent and client:act(a) and f.key == key then f.sent = true end
  redraw(f)
end

-- The amount the buttons set: `x` kept within the engine's range for my raise.
local function setWant(f, x)
  local m = f.model
  local r = m and m.act and m.act.raise
  if not r or f.sent then return end
  f.want = math.max(r.min, math.min(r.max, x))
  redraw(f)
end

local function onCall(f)
  local m = f.model
  if m and m.act then send(f, { k = m.act.check and "check" or "call" }) end
end

local function onRaise(f)
  local m = f.model
  local r = m and m.act and m.act.raise
  if r then send(f, { k = r.k, to = m.to }) end
end

local function onClose(f)
  local client = ns.client
  if client then ns.Cash.close(client) end
  redraw(f)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

-- A card at (x, y), `scale` of 40 x 58; the widget is its frame, `.card` the card.
local function card(f, x, y, scale)
  local c = Cards.card(f, scale)
  c.frame:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  c.frame.card = c
  c.frame:Hide()
  return c.frame
end

local function ghost(f, text, w, h, x, y, onClick)
  local b = W.GhostButton(f, text, "brassLight", onClick)
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  b:Hide()
  return b
end

local function gold(f, w, h, x, y, onClick)
  local b = W.GoldButton(f, "", onClick)
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  b:Hide()
  return b
end

-- The dealer disc (the chip tinted cream with „D“) or a blind's mark, centred on (x, y).
local function mark(f, x, y)
  local m = CreateFrame("Frame", nil, f)
  m:SetSize(MARK, MARK)
  m:SetPoint("CENTER", f, "TOPLEFT", x, y)
  m:SetFrameLevel(f:GetFrameLevel() + 8) -- above the plates and a card's layers (a card spans 4 levels)
  local disc = m:CreateTexture(nil, "ARTWORK")
  disc:SetTexture(Theme.tex.chip)
  disc:SetAllPoints(m)
  disc:SetVertexColor(Theme.rgb("cream"))
  m.disc = disc
  local button = W.Label(m, "heading", L("holdem.button"), 11)
  button:SetTextColor(Theme.rgb("woodDark"))
  button:SetShadowOffset(0, 0)
  button:SetJustifyH("CENTER")
  button:SetPoint("CENTER", m, "CENTER", 0, 0)
  m.button = button
  local blind = W.Label(m, "dim", "", 10)
  blind:SetJustifyH("CENTER")
  blind:SetPoint("CENTER", m, "CENTER", 0, 0)
  m.blind = blind
  m:Hide()
  return m
end

-- The widgets of place k: two cards, the chip and the bet, the mark.
local function place(f, k, plate)
  local x, y = CARDS[k][1], CARDS[k][2]
  local p = {}
  if k == 0 then
    p.cards = { card(f, x, y), card(f, x + BIG_STEP, y) }
  else
    p.cards = { card(f, x, y, SMALL), card(f, x + SMALL_STEP, y, SMALL) }
  end
  p.chip = f:CreateTexture(nil, "ARTWORK")
  p.chip:SetTexture(Theme.tex.chip)
  p.chip:SetVertexColor(Theme.rgb("bannerHi")) -- a fun table's chip, in the skin's colour
  p.chip:SetSize(CHIP, CHIP)
  p.chip:Hide()
  p.bet = W.Label(f, "ui", "", 12)
  p.bet:SetWordWrap(false)
  p.bet:Hide()
  p.mark = mark(f, plate[1] + MARK_X, plate[2])
  return p
end

-- f.seat[seat] = the place of that seat as seen from `me`.
local function mapSeats(f, me)
  for seat = 1, SEATS do f.seat[seat] = f.place[(seat - me) % SEATS] end
end

function View.build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(parent:GetWidth(), parent:GetHeight())

  f.oval = f:CreateTexture(nil, "BACKGROUND")
  f.oval:SetTexture(Theme.tex.oval)
  f.oval:SetSize(456, 236)
  f.oval:SetPoint("TOPLEFT", f, "TOPLEFT", 138, -97)

  f.board = {}
  for j = 1, 5 do f.board[j] = card(f, BOARD_X + BOARD_STEP * (j - 1), BOARD_Y) end

  f.pot = W.Label(f, "heading", "", 14)
  f.pot:SetTextColor(Theme.rgb("gold"))
  f.pot:SetJustifyH("CENTER")
  f.pot:SetWordWrap(false)
  f.pot:SetPoint("CENTER", f, "TOPLEFT", CENTRE_X, POT_Y)
  f.pot:Hide()

  f.text = W.Label(f, "heading", "", 14)
  f.text:SetJustifyH("CENTER")
  f.text:SetWordWrap(false)
  f.text:SetPoint("CENTER", f, "TOPLEFT", CENTRE_X, TEXT_Y)
  f.text:Hide()

  f.note = W.Label(f, "dim", "", 11)
  f.note:SetWidth(LEFT_W)
  f.note:SetWordWrap(true)
  f.note:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_X, NOTE_Y)
  f.note:Hide()

  f.log = W.Label(f, "dim", "", 11)
  f.log:SetWidth(LEFT_W)
  f.log:SetWordWrap(false)
  f.log:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_X, LOG_Y)
  f.log:Hide()

  local plates = ns.HallLayout.ring(SEATS, FELT_W, FELT_H, 1) -- seat k + 1 sits at place k
  f.place, f.seat = {}, {}
  for k = 0, SEATS - 1 do f.place[k] = place(f, k, plates[k + 1]) end
  mapSeats(f, 1)

  f.halfButton = ghost(f, L("holdem.half"), 64, 22, 476, -336, function() if f.model then setWant(f, f.model.half) end end)
  f.potButton = ghost(f, L("holdem.potB"), 64, 22, 546, -336, function() if f.model then setWant(f, f.model.potTo) end end)
  f.allinButton = ghost(f, "", 96, 22, 616, -336, function() send(f, { k = "allin" }) end)
  f.minusButton = ghost(f, L("holdem.minus"), 24, 24, 476, -362, function()
    if f.model and f.model.to then setWant(f, f.model.to - f.model.step) end
  end)
  f.plusButton = ghost(f, L("holdem.plus"), 24, 24, 596, -362, function()
    if f.model and f.model.to then setWant(f, f.model.to + f.model.step) end
  end)
  f.foldButton = ghost(f, L("holdem.fold"), 56, 26, 476, -388, function() send(f, { k = "fold" }) end)
  f.callButton = gold(f, 86, 26, 536, -388, function() onCall(f) end)
  f.raiseButton = gold(f, 100, 26, 626, -388, function() onRaise(f) end)
  f.closeButton = ghost(f, L("holdem.close"), 96, 22, 12, -366, function() onClose(f) end)
  ns.HoldemCashView.build(f) -- „Сметка“ and „Вход“ / „Докупи“ of a staked table (ui/games/HoldemCashView.lua)
  return f
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- The plate's note: the seat's chips, or why it does not play this hand.
local NOTE = { away = "holdem.note.away", out = "holdem.note.out", wait = "holdem.note.wait" }
function View.seatNote(s, seat)
  if not s.state then return "" end
  local ms = M.build(s).seats[seat]
  if not ms then return "" end
  if NOTE[ms.st] then return L(NOTE[ms.st]) end
  return View.amount(s, ms.chips)
end

-- The model's words {key, args…} in the locale: the category by its name,
-- the amount by View.amount, each name in its class colour when `colour`.
local function words(s, t, colour)
  local key, at = t[1], CAT_AT[t[1]]
  local args = {}
  for k = 2, at or #t do
    local x = t[k]
    if k == at then
      x = L("holdem.cat." .. tostring(x))
    elseif k == AMOUNT_AT[key] then
      x = View.amount(s, x)
    elseif type(x) == "string" and colour then
      x = W.colored(ns.client, x)
    end
    args[k - 1] = x
  end
  return L(key, unpack(args))
end

local function drawCards(p, ms, m, folded)
  local shown = ms ~= nil and ms.cards ~= nil and m.phase ~= "deal" -- no card exists while the deal is shuffled
  for j = 1, 2 do
    local c = p.cards[j]
    if shown then
      c.card:set(ms.cards[j] or nil)
      c:SetAlpha(folded and FOLDED_ALPHA or 1)
    end
    c:SetShown(shown)
  end
end

-- The bet, or after a hand what the seat won, centred on the table's bet offset: at a fun
-- table with a chip before it, at a cash table alone (its coin is in the text).
local function drawBet(f, s, p, k, ms)
  local text, colour
  if ms and ms.bet then
    text, colour = View.amount(s, ms.bet), "gold"
  elseif ms and ms.won and ms.won > 0 then
    text, colour = "+" .. View.amount(s, ms.won), "good"
  end
  local chip = text ~= nil and not View.cash(s)
  if text then
    p.bet:SetText(text)
    p.bet:SetTextColor(Theme.rgb(colour))
    local lead = chip and CHIP + CHIP_GAP or 0
    local x = BET[k][1] - (lead + p.bet:GetStringWidth()) / 2
    p.chip:ClearAllPoints()
    p.chip:SetPoint("LEFT", f, "TOPLEFT", x, BET[k][2])
    p.bet:ClearAllPoints()
    p.bet:SetPoint("LEFT", f, "TOPLEFT", x + lead, BET[k][2])
  end
  p.chip:SetShown(chip)
  p.bet:SetShown(text ~= nil)
end

local function drawMark(p, ms)
  local m, kind = p.mark, ms and ms.mark
  if kind == "sb" or kind == "bb" then m.blind:SetText(L("holdem." .. kind)) end
  m.disc:SetShown(kind == "D")
  m.button:SetShown(kind == "D")
  m.blind:SetShown(kind == "sb" or kind == "bb")
  m:SetShown(kind ~= nil)
end

local function drawSeats(f, s, m)
  mapSeats(f, m.me)
  for seat = 1, SEATS do
    local p, ms = f.seat[seat], m.seats[seat]
    drawCards(p, ms, m, ms ~= nil and ms.folded == true)
    drawBet(f, s, p, (seat - m.me) % SEATS, ms)
    drawMark(p, ms)
  end
end

local function drawTable(f, s, m)
  for j = 1, 5 do
    local c, face = f.board[j], m.board[j]
    if face then c.card:set(face) end
    c:SetShown(face ~= nil)
  end
  if m.pot > 0 then f.pot:SetText(L("holdem.pot", View.amount(s, m.pot))) end
  f.pot:SetShown(m.pot > 0)
end

-- `text` on button b in the largest size from LABEL down to LABEL_MIN that leaves LABEL_PAD of its width.
local function fitLabel(b, text)
  local fs, size = b.text, LABEL
  fs:SetFont(Theme.font.heading, size, "")
  fs:SetText(text)
  while size > LABEL_MIN and fs:GetStringWidth() > b:GetWidth() - LABEL_PAD do
    size = size - 1
    fs:SetFont(Theme.font.heading, size, "")
  end
end

local function setButton(f, b, shown, text)
  if shown and text then fitLabel(b, text) end
  local on = shown and not f.sent
  b:SetShown(shown)
  b:SetEnabled(on)
  b:SetAlpha(on and 1 or OFF_ALPHA)
end

local function drawButtons(f, s, m)
  local a = m.mine and m.act or nil
  local r = a and a.raise
  setButton(f, f.foldButton, a ~= nil)
  setButton(f, f.callButton, a ~= nil and (a.check or a.call) ~= nil,
    a and (a.check and L("holdem.check") or a.call and L("holdem.call", View.amount(s, a.call))))
  setButton(f, f.raiseButton, r ~= nil, r and L(r.k == "bet" and "holdem.bet" or "holdem.raise", View.amount(s, m.to)))
  for _, b in ipairs({ f.minusButton, f.plusButton, f.halfButton, f.potButton }) do setButton(f, b, r ~= nil) end
  setButton(f, f.allinButton, a ~= nil and a.allin ~= nil, a and a.allin and L("holdem.allin", View.amount(s, a.allin)))
  f.closeButton:SetShown(m.host and s.status == "live" and not m.closing and not m.over)
end

local function drawWords(f, s, m)
  local t = m.text
  if t then
    f.text:SetText(words(s, t, true))
    f.text:SetTextColor(Theme.rgb(AFTER[t[1]] and "gold" or "ink"))
  end
  f.text:SetShown(t ~= nil)
  if m.note then f.note:SetText(words(s, m.note)) end
  f.note:SetShown(m.note ~= nil)
  if m.log then f.log:SetText(words(s, m.log)) end
  f.log:SetShown(m.log ~= nil)
end

function View.update(f, s)
  f.session = s
  local key = eventKey(s)
  if f.key ~= key then f.key, f.want, f.sent = key, nil, nil end
  local m = M.build(s, f.want)
  f.model = m
  drawSeats(f, s, m)
  drawTable(f, s, m)
  drawButtons(f, s, m)
  drawWords(f, s, m)
  ns.HoldemCashView.update(f, s, m)
end

ns.TableFrame.registerView(E.id, View)
