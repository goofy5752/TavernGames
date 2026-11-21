local _, ns = ...

-- Playing cards (mockup 07, variant 1 „Кръчмата на гилдията“): one card widget
-- and a hand fan of them, shared by Сантасе, Белот and Холдем. A face is a
-- 2-char string, rank `23456789TJQKA` + suit `CDHS`; nil is a card face down.
-- In a fan a playable card is "raised" (gold edge, drawn higher), an unplayable
-- one "dim"; a click reaches the owner only from a card that is not dimmed.
local Theme, L, W = ns.Theme, ns.L, ns.W

local Cards = {}
ns.Cards = Cards

Cards.W, Cards.H, Cards.STEP, Cards.RAISE, Cards.DIM = 40, 58, 28, 8, 0.55

-- Left/right texture coordinates of each suit's cell in `suits`.
Cards.COORD = { C = { 0, 0.25 }, D = { 0.25, 0.5 }, H = { 0.5, 0.75 }, S = { 0.75, 1 } }

local NAMED = { T = true, J = true, Q = true, K = true, A = true }

-- The rank as printed on the card: „10“, „J“ … for the letters, else the digit.
function Cards.rank(face)
  local r = face:sub(1, 1)
  if NAMED[r] then return L("card." .. r) end
  return r
end

function Cards.red(face)
  local s = face:sub(2, 2)
  return s == "D" or s == "H"
end

function Cards.suitName(suit) return L("suit." .. suit) end

-- Left edges of `n` cards `w` wide, `step` apart, the whole row centred on 0.
function Cards.layout(n, step, w)
  local xs, left = {}, ((n - 1) * step + w) / 2
  for k = 1, n do xs[k] = (k - 1) * step - left end
  return xs
end

local CARD = {}
CARD.__index = CARD

-- `face` up, or the back for nil.
function CARD:set(face)
  self.face = face
  if face == nil then
    self.body:SetTexture(Theme.tex.card_back)
    self.shade:SetTexture(Theme.tex.card_back)
    self.rank:Hide(); self.pip:Hide(); self.big:Hide()
    return
  end
  self.body:SetTexture(Theme.tex.card)
  self.shade:SetTexture(Theme.tex.card)
  local r, g, b = Theme.rgb(Cards.red(face) and "red" or "cardInk")
  local coord = Cards.COORD[face:sub(2, 2)]
  self.rank:SetText(Cards.rank(face))
  self.rank:SetTextColor(r, g, b)
  for _, t in ipairs({ self.pip, self.big }) do
    t:SetTexCoord(coord[1], coord[2], 0, 1)
    t:SetVertexColor(r, g, b)
  end
  self.rank:Show(); self.pip:Show(); self.big:Show()
end

-- "plain" | "raised" (the gold edge; its owner draws it RAISE higher) | "dim".
function CARD:look(mode)
  self.mode = mode
  for i = 1, 4 do self.edges[i]:SetShown(mode == "raised") end
  self.shade:SetShown(mode == "dim")
end

-- One card, 40 x 58 px times `scale` (default 1).
function Cards.card(parent, scale)
  scale = scale or 1
  local f = CreateFrame("Button", nil, parent)
  f:SetSize(Cards.W * scale, Cards.H * scale)
  f:RegisterForClicks("LeftButtonUp")
  local card = setmetatable({ frame = f, scale = scale }, CARD)

  local body = f:CreateTexture(nil, "BACKGROUND")
  body:SetAllPoints(f)
  card.body = body

  local rank = W.Label(f, "paper", nil, 13 * scale)
  rank:SetFont(Theme.font.uiBold, 13 * scale, "")
  rank:SetDrawLayer("ARTWORK", 1)
  rank:SetPoint("TOPLEFT", f, "TOPLEFT", 3 * scale, -1 * scale)
  card.rank = rank

  local function suit(size)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetTexture(Theme.tex.suits)
    t:SetSize(size * scale, size * scale)
    return t
  end
  card.pip = suit(10)
  card.pip:SetPoint("TOPLEFT", f, "TOPLEFT", 3 * scale, -14 * scale)
  card.big = suit(21)
  card.big:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4 * scale, 2 * scale)

  -- Dimming: the card's own shape in black at 1 - DIM over body, rank and
  -- suits, so all three keep DIM of their brightness and the corners stay round.
  local shade = f:CreateTexture(nil, "OVERLAY")
  shade:SetAllPoints(f)
  shade:SetVertexColor(0, 0, 0, 1 - Cards.DIM)
  card.shade = shade

  card.edges = W.edges(f, 2, "OVERLAY")
  card.edges.setColor(Theme.rgb("gold"))

  card:set(nil)
  card:look("plain")
  return card
end

local FAN = {}
FAN.__index = FAN

-- Shows one card per entry ({i, face, mode}) and hides the spare ones. A click
-- on a card that is not "dim" calls onClick(entry).
function FAN:set(entries, onClick)
  self.onClick = onClick
  local n, scale = #entries, self.scale
  local w = Cards.W * scale
  local xs = Cards.layout(n, self.step, w)
  local level = self.frame:GetFrameLevel()
  for k = 1, n do
    local card = self.cards[k]
    if not card then
      card = Cards.card(self.frame, scale)
      card.frame:SetScript("OnClick", function()
        if card.mode ~= "dim" and self.onClick then self.onClick(card.entry) end
      end)
      self.cards[k] = card
    end
    local e = entries[k]
    local mode = e.mode or "plain"
    card.entry = e
    card:set(e.face)
    card:look(mode)
    card.x, card.y = xs[k], mode == "raised" and Cards.RAISE * scale or 0
    card.frame:SetFrameLevel(level + k)
    card.frame:ClearAllPoints()
    card.frame:SetPoint("BOTTOMLEFT", self.frame, "BOTTOM", card.x, card.y)
    card.frame:Show()
  end
  for k = n + 1, #self.cards do self.cards[k].frame:Hide() end
  self.frame:SetSize(n > 0 and (n - 1) * self.step + w or 0, (Cards.H + Cards.RAISE) * scale)
end

-- A row of cards overlapping by `opts.step` (default STEP) at `opts.scale`
-- (default 1); `fan.frame` is as wide as the row, the owner anchors it.
function Cards.fan(parent, opts)
  opts = opts or {}
  local fan = setmetatable({
    frame = CreateFrame("Frame", nil, parent),
    step = opts.step or Cards.STEP, scale = opts.scale or 1, cards = {},
  }, FAN)
  fan.frame:SetSize(0, (Cards.H + Cards.RAISE) * fan.scale)
  return fan
end
