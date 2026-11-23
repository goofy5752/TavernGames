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

-- The rank as printed on the card: „10“, „J“ … for the letters, else the
-- digit; "" for a face that is not known.
function Cards.rank(face)
  if type(face) ~= "string" then return "" end
  local r = face:sub(1, 1)
  if NAMED[r] then return L("card." .. r) end
  return r
end

function Cards.red(face)
  if type(face) ~= "string" then return false end
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

local function hex(n) return { math.floor(n / 65536) / 255, math.floor(n / 256) % 256 / 255, n % 256 / 255 } end
-- The disc behind a court's portrait, by the deck's faction.
local CHAIR = { alliance = hex(0x5b6676), horde = hex(0x6d4d42) }
local SEX = { queen = "female", jack = "male" }

-- Under this width (px) a court shows no ribbon: the name would not fit.
Cards.RIBBON_MIN = 50

-- Puts `tex` at the fractions of the card: l, t, r, b inset from its edges.
local function inset(card, region, l, t, r, b)
  local w, h = card.w, card.h
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", card.frame, "TOPLEFT", l * w, -t * h)
  region:SetPoint("BOTTOMRIGHT", card.frame, "BOTTOMRIGHT", -r * w, b * h)
end

-- The crest of faction `fac`, made once per card.
function CARD:crestOf(fac)
  local c = self.crests[fac]
  if not c then
    c = W.crest(self.frame, self.w, fac)
    c:SetDrawLayer("ARTWORK", 2)
    self.crests[fac] = c
  end
  return c
end

-- A court card: the hero in the oval, the label on the ribbon.
function CARD:court(info, fac)
  self.cameo:Show()
  self.chairBack:SetVertexColor(CHAIR[fac][1], CHAIR[fac][2], CHAIR[fac][3], 1)
  local ok = false
  if ns.Art then
    if info.role == "king" then -- the leader, else a hero of the race from the client
      ok = ns.Art.set(self.portrait, "leader", info.race)
        or ns.Art.set(self.portrait, "race", info.race, ns.Art.LEADER_SEX[info.race] or "male")
    else ok = ns.Art.set(self.portrait, "race", info.race, SEX[info.role]) end
  end
  self.art = ok and "client" or "standin"
  self.portrait:SetShown(ok)
  self.sil.frame:SetShown(not ok)
  if not ok then self.sil:set(ns.Silhouette.layers(info.race, info.role)) end
  self.cameoRing:SetVertexColor(Theme.factionColor(fac, "brass"))
  self.cameoRing:Show()
  local wide = self.w >= Cards.RIBBON_MIN
  if wide then
    local r, g, b = Theme.factionColor(fac, "banner")
    self.ribbon:SetVertexColor(r, g, b, 1)
    self.ribbonText:SetText(info.label)
    self.ribbon:Show(); self.ribbonText:Show()
  end
end

-- `face` up, or the back for nil. Reads the deck and skin each time, so a
-- deck change shows on the next set.
function CARD:set(face)
  self.face = face
  local key = self.deck or ns.Decks.key()
  local fac = ns.Decks.faction(key, Theme.skin)
  self.cameo:Hide(); self.cameoRing:Hide(); self.ribbon:Hide(); self.ribbonText:Hide()
  self.big:Hide(); self.art = nil
  for _, c in pairs(self.crests) do c:Hide() end
  if face == nil then
    local back = Theme.tex["card_back_" .. fac]
    self.body:SetTexture(back); self.shade:SetTexture(back)
    self.rank:Hide(); self.pip:Hide()
    local c = self:crestOf(fac)
    self.crest = c
    c:ClearAllPoints(); c:SetSize(0.62 * self.w, 0.62 * self.w); c:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    c:Show()
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
  self.rank:Show(); self.pip:Show()
  local info = ns.Decks.court(face, key, Theme.skin)
  if info then
    self:court(info, info.faction)
  elseif face:sub(1, 1) == "A" then
    local c = self:crestOf(fac)
    self.crest = c
    inset(self, c, 0.14, 0.14, 0.14, 0.18)
    c:Show()
  else
    self.big:Show()
  end
end

-- "plain" | "raised" (the gold edge; its owner draws it RAISE higher) | "dim".
function CARD:look(mode)
  self.mode = mode
  for i = 1, 4 do self.edges[i]:SetShown(mode == "raised") end
  self.shade:SetShown(mode == "dim")
end

-- Frame levels of the card's layers from `n`: the card, the cameo, its
-- silhouette, then the frame of the corner index, dimming and edge on top of all.
function CARD:level(n)
  self.frame:SetFrameLevel(n)
  self.cameo:SetFrameLevel(n + 1)
  self.sil.frame:SetFrameLevel(n + 2)
  self.over:SetFrameLevel(n + 3)
end
Cards.LEVELS = 4
-- A fan holds at most MAX cards (a Белот hand) and its cards span the TOP
-- levels above the fan's own: a panel over the felt (the board and its fan sit
-- 1 and 2 above it) adds TOP to its level to draw above every card.
Cards.MAX = 8
Cards.TOP = Cards.LEVELS * (Cards.MAX + 1)

-- One card, 40 x 58 px times `scale` (default 1).
function Cards.card(parent, scale)
  scale = scale or 1
  local f = CreateFrame("Button", nil, parent)
  local w, h = Cards.W * scale, Cards.H * scale
  f:SetSize(w, h)
  f:RegisterForClicks("LeftButtonUp")
  local card = setmetatable({ frame = f, scale = scale, w = w, h = h, crests = {} }, CARD)

  local body = f:CreateTexture(nil, "BACKGROUND")
  body:SetAllPoints(f)
  card.body = body

  -- The big suit of a number card, centred.
  card.big = f:CreateTexture(nil, "ARTWORK")
  card.big:SetTexture(Theme.tex.suits)
  card.big:SetSize(0.46 * w, 0.46 * w)
  card.big:SetPoint("CENTER", f, "CENTER", 0, 0)

  -- The ribbon with the court's label.
  card.ribbon = f:CreateTexture(nil, "ARTWORK", nil, 3)
  card.ribbon:SetTexture(Theme.tex.ribbon)
  inset(card, card.ribbon, 0.08, 1 - 0.09 - 0.15, 0.08, 0.09)

  -- The cameo: a disc, the portrait masked in the oval, or the stand-in over it.
  local cameo = CreateFrame("Frame", nil, f)
  inset(card, cameo, 0.18, 0.13, 0.18, 0.21)
  card.cameo = cameo
  card.chairBack = cameo:CreateTexture(nil, "ARTWORK", nil, 0)
  card.chairBack:SetTexture(Theme.tex.chair)
  card.chairBack:SetAllPoints(cameo)
  card.portrait = cameo:CreateTexture(nil, "ARTWORK", nil, 1)
  card.portrait:SetAllPoints(cameo)
  W.mask(card.portrait, cameo)
  card.sil = ns.Silhouette.new(cameo)
  card.sil.frame:SetAllPoints(cameo)

  -- Everything the card shows above its layers: the ring, label, corner index,
  -- dimming and edge.
  local over = CreateFrame("Frame", nil, f)
  over:SetAllPoints(f)
  card.over = over
  card.cameoRing = over:CreateTexture(nil, "OVERLAY", nil, 1)
  card.cameoRing:SetTexture(Theme.tex.cameo)
  card.cameoRing:SetAllPoints(cameo)

  local ribbonText = W.Label(over, "heading", nil, math.max(8, 0.14 * w))
  ribbonText:SetDrawLayer("OVERLAY", 2)
  ribbonText:SetJustifyH("CENTER")
  ribbonText:SetPoint("CENTER", card.ribbon, "CENTER", 0, 0)
  card.ribbonText = ribbonText

  local rank = W.Label(over, "paper", nil, 13 * scale)
  Theme.setFont(rank, "uiBold", 13 * scale)
  rank:SetDrawLayer("OVERLAY", 3)
  rank:SetPoint("TOPLEFT", f, "TOPLEFT", 3 * scale, -1 * scale)
  card.rank = rank

  card.pip = over:CreateTexture(nil, "OVERLAY", nil, 3)
  card.pip:SetTexture(Theme.tex.suits)
  card.pip:SetSize(10 * scale, 10 * scale)
  card.pip:SetPoint("TOPLEFT", f, "TOPLEFT", 3 * scale, -14 * scale)

  -- Dimming: the card's own shape in black at 1 - DIM over everything, so the
  -- corners stay round and every layer keeps DIM of its brightness.
  local shade = over:CreateTexture(nil, "OVERLAY", nil, 6)
  shade:SetAllPoints(f)
  shade:SetVertexColor(0, 0, 0, 1 - Cards.DIM)
  card.shade = shade

  card.edges = W.edges(over, 2, "OVERLAY")
  card.edges.setColor(Theme.rgb("gold"))

  card:level(f:GetFrameLevel())
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
    card:level(level + Cards.LEVELS * k)
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
