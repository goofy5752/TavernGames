local _, ns = ...

-- The Белот table (mockup 07 variant 1, the gold `.btn` of mockup 03) over
-- the whole felt, 532 x 328; the four plates of the ring lie around it
-- (TableFrame, `ring = true`). It draws only what ns.BelotModel.build
-- returns: top left the contract and who called it, top right the team score
-- to 151 and the hanging points; in the centre the trick as a cross by seat
-- (my card at the bottom, my partner's on top) or, during the auction, the
-- bids open to me; over each player the bubble of what he bid or announced;
-- after a deal its summary in the centre; „Последна взятка“ on the left
-- shows the last trick, dimmed, until any table event; „Обяви“ on the right
-- while the engine offers an announce; my fan at the bottom, the cards I may
-- not play dimmed, and above it whose turn it is or how the match ended.
-- Every move goes through client:act; the view never sends chat or rolls.
local Theme, W, L, Cards = ns.Theme, ns.W, ns.L, ns.Cards
local E = ns.Engines.belot
local M = ns.BelotModel

local BIDS = { "P", "C", "D", "H", "S", "N", "A", "X", "R" }
local SUIT_BIDS = { C = true, D = true, H = true, S = true }
-- TOPLEFT offsets and widths of the bid buttons, 24 high.
local BID_SPOT = {
  C = { 180, -60, 40 }, D = { 224, -60, 40 }, H = { 268, -60, 40 }, S = { 312, -60, 40 },
  N = { 180, -88, 84 }, A = { 268, -88, 84 },
  P = { 180, -116, 84 }, X = { 268, -116, 84 }, R = { 268, -116, 84 },
}
local TRICK_SPOT = { [0] = { 246, -122 }, [1] = { 292, -89 }, [2] = { 246, -56 }, [3] = { 200, -89 } }
local BUBBLE_SPOT = { [0] = { 357, -280 }, [1] = { 364, -133 }, [2] = { 191, -38 }, [3] = { 17, -133 } }
local BUTTON_H, SIDE_BUTTON_W, SUIT_ICON = 24, 124, 16
local BUBBLE_W, BUBBLE_H = 150, 18
local SUMMARY_W = 170
local MY_FAN_Y = 60 -- the fan's bottom edge above the frame's

local View = { ring = true }

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

-- `seat`'s name: who held it during the match (the view's memory), else who
-- holds it now; nil for an empty seat.
local function nameOf(f, s, seat)
  local n = f.names and f.names[seat] or s.seats and s.seats[seat]
  if type(n) == "string" then return n end
  return nil
end

local function colouredName(f, s, seat)
  local n = nameOf(f, s, seat)
  if not n then return L("table.free") end
  return W.colored(ns.client, n)
end

-- „Игра: Купа, контра“.
local function contractText(c)
  local game = L("belot.bid." .. c.b)
  if c.x == 2 then game = L("belot.x2", game) elseif c.x == 4 then game = L("belot.x4", game) end
  return L("belot.contract", game)
end

local function join(keys)
  local out = {}
  for k, key in ipairs(keys) do out[k] = L(key) end
  return table.concat(out, ", ")
end

-- The opening code of the inkDim colour, to resume it after a coloured name.
local function dimCode() return W.paint("", Theme.rgb("inkDim")):sub(1, 10) end

-- The lines of the last deal's summary (see the brief of the view).
local function summaryText(f, s, m)
  local sum = m.summary
  if sum.passed then return L("belot.passed") end
  local c = sum.contract
  local lines = {
    contractText(c) .. "  " .. L("belot.by", colouredName(f, s, c.seat)),
    L("belot.sum.points", sum.us, sum.them),
  }
  if sum.inside then
    lines[#lines + 1] = L(2 - c.seat % 2 == m.team and "belot.sum.inside.us" or "belot.sum.inside.them")
  end
  if sum.hanging then lines[#lines + 1] = L("belot.sum.hanging", sum.hang) end
  if sum.valat then lines[#lines + 1] = L("belot.sum.valat") end
  for _, a in ipairs(sum.anns) do
    local kind = L("belot.ann." .. a.t)
    if a.on then
      lines[#lines + 1] = L("belot.sum.ann", colouredName(f, s, a.seat), kind, a.v)
    else
      lines[#lines + 1] = W.paint(L("belot.sum.off", colouredName(f, s, a.seat) .. dimCode(), kind), Theme.rgb("inkDim"))
    end
  end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Acting
---------------------------------------------------------------------------

-- What the table has seen: an event (or another table, or a new host) changes it.
local function eventKey(s) return tostring(s.tid) .. "/" .. tostring(s.epoch) .. "/" .. tostring(s.seq) end

local function act(f, a)
  local s, client = f.session, ns.client
  if a and s and client then client:act(a) end
  if s then View.update(f, s) end
end

-- My play of card `i`, with the belote when the engine offers one; nil when
-- I may not play it.
local function playOf(s, i)
  local st, seat = s.state, s.mySeat
  if not st or s.status ~= "live" then return nil end
  local found
  for _, a in ipairs(E.legal(st, seat)) do
    if a.k == "play" and a.i == i and (not found or a.b) then found = a end
  end
  return found
end

local function onCard(f, entry)
  local s = f.session
  if s then act(f, playOf(s, entry.i)) end
end

local function togglePeek(f)
  local s = f.session
  if not s then return end
  f.peek = not f.peek
  f.peekAt = eventKey(s)
  View.update(f, s)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

-- The gold button of the mockup (`.btn`): a gold face with a darker lip at
-- its lower edge and a dark label; `button.text`. Its rim lights up under
-- the mouse.
local GOLD_FACE, GOLD_LIP = { 0xdc / 255, 0xb4 / 255, 0x67 / 255 }, { 0x8a / 255, 0x5a / 255, 0x2b / 255 }
local function goldButton(parent, w, text, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, BUTTON_H)
  b:RegisterForClicks("LeftButtonUp")
  b.fill = b:CreateTexture(nil, "BACKGROUND")
  b.fill:SetAllPoints(b)
  b.fill:SetColorTexture(GOLD_FACE[1], GOLD_FACE[2], GOLD_FACE[3], 1)
  b.lip = b:CreateTexture(nil, "BORDER")
  b.lip:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.lip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.lip:SetHeight(2)
  b.lip:SetColorTexture(GOLD_LIP[1], GOLD_LIP[2], GOLD_LIP[3], 1)
  b.edges = W.edges(b, 1, "ARTWORK") -- above the lip
  b.edges.setColor(Theme.rgb("brass"))
  local fs = W.Label(b, "heading", text, 13)
  fs:SetTextColor(Theme.rgb("woodDark"))
  fs:SetJustifyH("CENTER")
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text = fs
  b:SetScript("OnEnter", function() b.edges.setColor(Theme.rgb("gold")) end)
  b:SetScript("OnLeave", function() b.edges.setColor(Theme.rgb("brass")) end)
  b:SetScript("OnClick", function() onClick() end)
  return b
end

-- The brass-rimmed dark button (`.btn.ghost`); its rim is gold while
-- `button.lit` or under the mouse.
local function ghostButton(parent, text, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(SIDE_BUTTON_W, BUTTON_H)
  b:RegisterForClicks("LeftButtonUp")
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(b)
  fill:SetColorTexture(32 / 255, 16 / 255, 8 / 255, 0.85)
  b.edges = W.edges(b, 1)
  b.edges.setColor(Theme.rgb("brass"))
  local fs = W.Label(b, "heading", text, 13)
  fs:SetTextColor(Theme.rgb("brassLight"))
  fs:SetJustifyH("CENTER")
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text = fs
  b.lit = false
  b:SetScript("OnEnter", function() b.edges.setColor(Theme.rgb("gold")) end)
  b:SetScript("OnLeave", function() b.edges.setColor(Theme.rgb(b.lit and "gold" or "brass")) end)
  b:SetScript("OnClick", function() onClick() end)
  return b
end

-- A bid button: the suit from the `suits` texture for C D H S, else the bid's name.
local function bidButton(f, b)
  local spot = BID_SPOT[b]
  local button = goldButton(f, spot[3], SUIT_BIDS[b] and "" or L("belot.bid." .. b), function()
    act(f, { k = "bid", b = b })
  end)
  button:SetPoint("TOPLEFT", f, "TOPLEFT", spot[1], spot[2])
  if SUIT_BIDS[b] then
    local t = button:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Theme.tex.suits)
    t:SetSize(SUIT_ICON, SUIT_ICON)
    t:SetTexCoord(Cards.COORD[b][1], Cards.COORD[b][2], 0, 1)
    t:SetVertexColor(Theme.rgb((b == "H" or b == "D") and "red" or "ink"))
    t:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.suit = t
  end
  button:Hide()
  return button
end

-- A bubble over a player: dark fill, brass edge, gold text; `bubble.text`.
local function bubble(f, k)
  local b = CreateFrame("Frame", nil, f)
  b:SetSize(BUBBLE_W, BUBBLE_H)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", BUBBLE_SPOT[k][1], BUBBLE_SPOT[k][2])
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(b)
  fill:SetColorTexture(32 / 255, 16 / 255, 8 / 255, 0.85)
  b.edges = W.edges(b, 1)
  b.edges.setColor(Theme.rgb("brass"))
  local fs = W.Label(b, "heading", "", 11)
  fs:SetTextColor(Theme.rgb("gold"))
  fs:SetJustifyH("CENTER")
  fs:SetWordWrap(false)
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text = fs
  b:Hide()
  return b
end

function View.build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(parent:GetWidth(), parent:GetHeight())
  f.names, f.peek = {}, false

  f.contract = W.Label(f, "dim", "", 11)
  f.contract:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -12)
  f.score = W.Label(f, "dim", "", 11)
  f.score:SetJustifyH("RIGHT")
  f.score:SetPoint("TOPRIGHT", f, "TOPLEFT", 522, -12)

  f.trick = {}
  for k = 0, 3 do
    local card = Cards.card(f)
    card.frame:SetPoint("TOPLEFT", f, "TOPLEFT", TRICK_SPOT[k][1], TRICK_SPOT[k][2])
    card.frame:Hide()
    f.trick[k] = card
  end

  f.bidButtons = {}
  for _, b in ipairs(BIDS) do f.bidButtons[b] = bidButton(f, b) end

  f.bubbles = {}
  for k = 0, 3 do f.bubbles[k] = bubble(f, k) end

  f.summary = W.Label(f, "ui", "", 11)
  f.summary:SetWidth(SUMMARY_W)
  f.summary:SetJustifyH("CENTER")
  f.summary:SetWordWrap(true)
  f.summary:SetPoint("TOP", f, "TOPLEFT", 266, -64)
  f.summary:Hide()

  f.announceButton = goldButton(f, SIDE_BUTTON_W, "", function()
    act(f, f.model and f.model.announce)
  end)
  f.announceButton:SetPoint("TOPLEFT", f, "TOPLEFT", 392, -172)
  f.announceButton:Hide()
  f.peekButton = ghostButton(f, L("belot.peek"), function() togglePeek(f) end)
  f.peekButton:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -172)
  f.peekButton:Hide()

  f.myFan = Cards.fan(f)
  f.myFan.frame:SetPoint("BOTTOM", f, "BOTTOM", 0, MY_FAN_Y)
  f.text = W.Label(f, "heading", "", 15)
  f.text:SetJustifyH("CENTER")
  f.text:SetWordWrap(false)
  f.text:SetPoint("CENTER", f, "TOPLEFT", 266, -192)
  return f
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- „разд.“ on the plate of the dealer of the deal under way (the model's rule).
function View.seatNote(s, seat)
  if not s.state then return "" end
  return M.build(s).dealer == seat and L("belot.dealer") or ""
end

-- Who sits where while the match runs, so the line at its end can still name
-- a player whose seat emptied when he left.
local function remember(f, s)
  if f.namesTid ~= s.tid then f.namesTid, f.names = s.tid, {} end
  if not E.over(s.state) then
    for seat = 1, 4 do f.names[seat] = s.seats[seat] or nil end
  end
end

local function drawTop(f, s, m)
  local c = m.contract
  if c then f.contract:SetText(contractText(c) .. "\n" .. L("belot.by", colouredName(f, s, c.seat))) end
  f.contract:SetShown(c ~= nil)
  local sc = m.score
  local target = L("belot.target")
  if (sc.hang or 0) > 0 then target = target .. " · " .. L("belot.hang", sc.hang) end
  f.score:SetText(L(m.seated and "belot.score.us" or "belot.score.watch", sc.us, sc.them) .. "\n" .. target)
end

local function drawTrick(f, m)
  for k = 0, 3 do f.trick[k].frame:Hide() end
  for _, c in ipairs(m.trick) do
    local card = f.trick[m.pos[c.seat]]
    card:set(c.face)
    card:look(m.peeking and "dim" or "plain")
    card.frame:Show()
  end
end

local function drawBubbles(f, m)
  for k = 0, 3 do f.bubbles[k]:Hide() end
  for seat = 1, 4 do
    local keys = m.bubbles[seat]
    if keys then
      local b = f.bubbles[m.pos[seat]]
      b.text:SetText(join(keys))
      b:Show()
    end
  end
end

local function drawButtons(f, m)
  for _, b in ipairs(BIDS) do f.bidButtons[b]:SetShown(m.bids[b] == true) end
  local a = m.announce
  if a then
    local keys = {}
    for k, x in ipairs(a.a) do keys[k] = "belot.ann." .. x.t end
    f.announceButton.text:SetText(L("belot.announce", join(keys)))
  end
  f.announceButton:SetShown(a ~= nil)
  local peek = f.peekButton
  peek.lit = f.peek
  peek.edges.setColor(Theme.rgb(f.peek and "gold" or "brass"))
  peek:SetShown(m.canPeek)
end

local function drawText(f, st, m)
  local t = m.text
  if not t then
    f.text:SetText("")
    f.text:Hide()
    return
  end
  local args = {}
  for k = 2, #t do
    local x = t[k]
    args[k - 1] = type(x) == "string" and W.colored(ns.client, x) or x
  end
  f.text:SetText(L(t[1], unpack(args)))
  f.text:SetTextColor(Theme.rgb((st.phase == "deal" or E.over(st)) and "gold" or "ink"))
  f.text:Show()
end

function View.update(f, s)
  f.session = s
  local st = s.state
  remember(f, s)
  if f.peekAt ~= eventKey(s) then f.peek = false end
  local m = M.build(s, nil, f.names)
  if f.peek and m.canPeek then
    m = M.build(s, true, f.names)
  else
    f.peek = false
  end
  f.model = m

  drawTop(f, s, m)
  drawTrick(f, m)
  drawBubbles(f, m)
  drawButtons(f, m)
  if m.summary then f.summary:SetText(summaryText(f, s, m)) end
  f.summary:SetShown(m.summary ~= nil)
  f.myFan:set(m.hand, function(entry) onCard(f, entry) end)
  drawText(f, st, m)
end

ns.TableFrame.registerView(E.id, View)
