local _, ns = ...

-- The deck tiles' preview in „Настройки“: hovering a deck shows its whole face side, one row
-- per suit (spades, hearts, diamonds, clubs) of jack, queen, king and ace, and its back, big,
-- beside them. The cards are the table's own (Cards.card with the deck set), so the preview is
-- exactly what that deck deals. A tooltip: it takes no mouse and sits above the window.
local Theme, W, L = ns.Theme, ns.W, ns.L

local DeckPreview = {}
ns.DeckPreview = DeckPreview

DeckPreview.SUITS = { "S", "H", "D", "C" }
DeckPreview.RANKS = { "J", "Q", "K", "A" }
DeckPreview.SCALE, DeckPreview.BACK_SCALE = 1.2, 2 -- under Cards.RIBBON_MIN: no ribbons, as on the table
local PAD, GAP, HEAD = 12, 6, 44

local CW, CH = ns.Cards.W * DeckPreview.SCALE, ns.Cards.H * DeckPreview.SCALE
local BW, BH = ns.Cards.W * DeckPreview.BACK_SCALE, ns.Cards.H * DeckPreview.BACK_SCALE
local GRID_W = #DeckPreview.RANKS * CW + (#DeckPreview.RANKS - 1) * GAP
local GRID_H = #DeckPreview.SUITS * CH + (#DeckPreview.SUITS - 1) * GAP
DeckPreview.W = math.floor(PAD + GRID_W + 2 * GAP + BW + PAD + 0.5)
DeckPreview.H = math.floor(PAD + HEAD + GRID_H + PAD + 0.5)

local function quiet(card)
  card.frame:EnableMouse(false)
  return card
end

-- The preview, hidden, as a child of `parent` -> { frame, title, sub, cards = {face -> card}, back }.
function DeckPreview.new(parent)
  local f = W.Panel(parent, { W.SOLID[1], W.SOLID[2], W.SOLID[3], 1 }) -- opaque: nothing of the window shows through
  f:SetFrameStrata("TOOLTIP")
  f:SetSize(DeckPreview.W, DeckPreview.H)
  f:EnableMouse(false)
  W.edges(f, 1).setColor(Theme.rgb("brass"))
  local p = { frame = f, cards = {} }
  p.title = W.Label(f, "heading", nil, 15)
  p.title:SetTextColor(Theme.rgb("gold"))
  p.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  p.sub = W.Label(f, "dim", nil, 12)
  p.sub:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + 22))
  for row, suit in ipairs(DeckPreview.SUITS) do
    for col, rank in ipairs(DeckPreview.RANKS) do
      local card = quiet(ns.Cards.card(f, DeckPreview.SCALE))
      card.frame:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (col - 1) * (CW + GAP), -(PAD + HEAD + (row - 1) * (CH + GAP)))
      p.cards[rank .. suit] = card
    end
  end
  p.back = quiet(ns.Cards.card(f, DeckPreview.BACK_SCALE))
  p.back.frame:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + GRID_W + 2 * GAP, -(PAD + HEAD + (GRID_H - BH) / 2))
  f:Hide()
  return p
end

-- Shows deck `key` with its title and sub line, the top left corner at (x, -y) of the parent.
function DeckPreview.show(p, key, title, sub, x, y)
  p.key = key
  W.fit(p.title, title, DeckPreview.W - 2 * PAD)
  W.fit(p.sub, sub, DeckPreview.W - 2 * PAD)
  for face, card in pairs(p.cards) do
    card.deck = key
    card:set(face)
  end
  p.back.deck = key
  p.back:set(nil)
  p.frame:ClearAllPoints()
  p.frame:SetPoint("TOPLEFT", p.frame:GetParent(), "TOPLEFT", x, -y)
  p.frame:Show()
end

function DeckPreview.hide(p)
  p.key = nil
  p.frame:Hide()
end
