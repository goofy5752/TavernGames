local _, ns = ...

-- The tavern look (spec 5.1, mockup 01 option A "Механа"): color tokens as
-- {r, g, b} arrays (0..1), font file paths and texture paths. Data only.
local MEDIA = "Interface\\AddOns\\TavernGames\\media\\"

local function hex(h)
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

local Theme = {
  color = {
    wood = hex("4a2c1a"),
    woodDark = hex("2e190e"),
    woodLight = hex("5b371f"), -- the floor planks (mockup 02)
    knob = hex("6b3a1f"),      -- the round close button
    felt = hex("7a1f24"),
    feltDark = hex("2c090b"),
    brass = hex("b0813f"),
    brassLight = hex("e9c98a"),
    brassDim = hex("6e4824"),  -- panel edges
    ink = hex("f3e2c0"),
    inkDim = hex("c9b28a"),
    gold = hex("f2c94c"),
    cream = hex("fbf3e2"),
    red = hex("a3161c"),
    oMark = hex("e2735a"),
    good = hex("9fd17a"),
    cardInk = hex("22170f"),   -- black suits and ranks on a card face
    cardEdge = hex("c7ad82"),  -- the card face edge
    boardField = hex("2a140b"), -- the Табла board field (mockup 07, variant 1)
    boardBar = hex("3a2010"),   -- its bar and tray
    pointLight = hex("e9d9b6"), -- the light points (the dark ones are #7a1f24)
    bone = hex("f3e8d0"),       -- the light checker
    walnut = hex("3b1d10"),     -- the dark checker
    glow = hex("ffd100"),       -- a legal target
  },
  font = {
    heading = MEDIA .. "fonts\\AlegreyaSC-Bold.ttf",
    ui = MEDIA .. "fonts\\AlegreyaSans-Regular.ttf",
    uiBold = MEDIA .. "fonts\\AlegreyaSans-Bold.ttf",
    italic = MEDIA .. "fonts\\Alegreya-Italic.ttf",
  },
  tex = {},
  -- Pixel size of each texture file, for tiling and nine-slicing.
  texSize = {
    wood = 256, felt = 256, frame = 64, ring = 128, tabletop = 128, chair = 64, chair_empty = 64,
    button = { 128, 32 }, button_hi = { 128, 32 }, glow = 128, info = 32, icon = 64,
    card = { 64, 128 }, card_back = { 64, 128 }, suits = { 128, 32 }, -- suits: club, diamond, heart, spade
    point = { 32, 128 }, checker = 64, dice = { 128, 64 }, -- Табла: dice = faces 1-4 on top, 5 and 6 below
  },
}

for name in pairs(Theme.texSize) do Theme.tex[name] = MEDIA .. name end

ns.Theme = Theme

-- r, g, b of a color token.
function Theme.rgb(token)
  local c = Theme.color[token]
  return c[1], c[2], c[3]
end
