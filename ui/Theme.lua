local _, ns = ...

-- The tavern look (spec 5.1, mockup 01 option A "Механа"; the faction skins:
-- mockup 08): color tokens as {r, g, b} arrays (0..1), font file paths and
-- texture paths. Data only: Theme.apply needs neither ns.Art nor ns.db.
local MEDIA = "Interface\\AddOns\\TavernGames\\media\\"

local function hex(h)
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

local Theme = {
  color = {
    wood = hex("4a2c1a"),
    woodDark = hex("2e190e"),
    woodLight = hex("5b371f"), -- the floor planks (mockup 02)
    knob = hex("8a2a1a"),      -- the round close button
    -- felt, feltDark, feltHi, brass, brassLight, brassDim (panel edges), banner,
    -- bannerHi, deep, accent, lantern, paperHead: the skin's (Theme.SKINS, Theme.apply).
    ink = hex("f2e6c8"),
    inkDim = hex("c4b48f"),
    gold = hex("f2c94c"),
    goldHi = hex("fbe3a0"),
    goldLo = hex("7a5418"),
    coin = hex("ffe08a"),
    cream = hex("fbf3e2"),
    red = hex("a3161c"),
    oMark = hex("e2735a"),
    good = hex("9fd17a"),
    cardInk = hex("1d1410"),   -- black suits and ranks on a card face
    cardEdge = hex("9c8456"),  -- the card face edge
    boardField = hex("2a140b"), -- the Табла board field (mockup 07, variant 1)
    boardBar = hex("3a2010"),   -- its bar and tray
    pointLight = hex("e9d9b6"), -- the light points (the dark ones are #7a1f24)
    bone = hex("f3e8d0"),       -- the light checker
    walnut = hex("3b1d10"),     -- the dark checker
    glow = hex("ffd100"),       -- a legal target
    clockLow = hex("ff5a4a"),   -- a chess clock under 30 s
  },
  -- Headings keep the tavern face (Alegreya SC); every other text is PT Sans.
  font = {
    heading = MEDIA .. "fonts\\AlegreyaSC-Bold.ttf",
    ui = MEDIA .. "fonts\\PTSans-Regular.ttf",
    uiBold = MEDIA .. "fonts\\PTSans-Bold.ttf",
  },
  -- PT Sans sets the UI's text about 10% wider than Alegreya Sans did at the
  -- same size (measured over both locales): its sizes are scaled so every
  -- label keeps the width the layout was made for. The x-height stays the same.
  fontScale = { ui = 0.91, uiBold = 0.93 },
  tex = {},
  -- Pixel size of each texture file, for tiling and nine-slicing.
  texSize = {
    wood = 256, felt = 256, frame = 64, ring = 128, tabletop = 128, chair = 64, chair_empty = 64,
    button = { 128, 32 }, button_hi = { 128, 32 }, glow = 128, info = 32, icon = 64,
    card = { 64, 128 }, card_back = { 64, 128 }, suits = { 128, 32 }, -- suits: club, diamond, heart, spade
    point = { 32, 128 }, checker = 64, dice = { 128, 64 }, -- Табла: dice = faces 1-4 on top, 5 and 6 below
    oval = { 512, 256 }, chip = 32, -- Холдем: the oval table and a chip
    mug = 64, -- the addon icon's mug alone, by the window title
    botmark = 32, -- the brass cog after a bot's short name (ui/NameTag.lua, tools/gen_botmark.py)
    dropdown = 32, -- the arrow of a drop-down (the game in „Нова маса“, tools/gen_dropdown.py)
  },
}

-- The faction skin textures (media/skin/, tools/gen_faction_textures.py), {w, h} px.
Theme.skinTexSize = {
  felt_alliance = { 256, 256 }, felt_horde = { 256, 256 },
  frame_alliance = { 64, 64 }, frame_horde = { 64, 64 },
  cap_alliance = { 64, 64 }, cap_horde = { 64, 64 },
  stone = { 128, 128 },
  oval_alliance = { 512, 256 }, oval_horde = { 512, 256 },
  crest_alliance = { 128, 128 }, crest_horde = { 128, 128 },
  coins = { 128, 32 }, parchment = { 256, 256 }, pring = { 128, 128 }, mask = { 64, 64 },
  button_alliance = { 128, 32 }, button_hi_alliance = { 128, 32 },
  button_horde = { 128, 32 }, button_hi_horde = { 128, 32 },
  chip = { 32, 32 },
  card_back_alliance = { 64, 128 }, card_back_horde = { 64, 128 },
  cameo = { 64, 64 }, ribbon = { 64, 16 }, sil = { 512, 64 },
}

-- The chess textures (media/chess/, tools/gen_chess_textures.py), {w, h} px: <skin>_<w|b><p n b r q k>
-- (piece style B), the light and dark square of each skin, the dot, the capture ring and the check glow.
Theme.chessTexSize = { dot = { 64, 64 }, ring = { 64, 64 }, check = { 64, 64 } }
for _, skin in ipairs({ "alliance", "horde" }) do
  Theme.chessTexSize["sq_" .. skin .. "_l"], Theme.chessTexSize["sq_" .. skin .. "_d"] = { 64, 64 }, { 64, 64 }
  for _, colour in ipairs({ "w", "b" }) do
    for _, piece in ipairs({ "p", "n", "b", "r", "q", "k" }) do Theme.chessTexSize[skin .. "_" .. colour .. piece] = { 128, 128 } end
  end
end

-- The path of chess texture `name`.
function Theme.chessTex(name) return MEDIA .. "chess\\" .. name end

for name in pairs(Theme.texSize) do Theme.tex[name] = MEDIA .. name end
for name in pairs(Theme.skinTexSize) do Theme.tex[name] = MEDIA .. "skin\\" .. name end

local function skinTex(f)
  return { felt = "felt_" .. f, frame = "frame_" .. f, oval = "oval_" .. f, button = "button_" .. f,
    button_hi = "button_hi_" .. f, cap = "cap_" .. f, crest = "crest_" .. f, chip = "chip" }
end

-- The two skins (spec 5.1): the colour tokens each sets, the skin texture file
-- behind each Theme.tex name, the tint of the window wood, the hall floor and
-- the skin's own SOUNDKIT names by moment (ns.Art.sound tries them first).
Theme.SKINS = {
  alliance = {
    color = {
      felt = hex("13325e"), feltDark = hex("071226"), feltHi = hex("1f4c8a"),
      brass = hex("d8ab4a"), brassLight = hex("f6d98c"), brassDim = hex("6f4f18"),
      banner = hex("1b3f75"), bannerHi = hex("2c5ea6"), deep = hex("0a1830"),
      accent = hex("5fa8ff"), lantern = hex("9cc4ff"), paperHead = hex("173a6e"),
      sqLast = hex("ffd65a"), sqSel = hex("ffe27a"), sqDot = hex("0a1830"), coord = hex("f6d98c"), -- the chess board (alpha: ChessView)
    },
    tex = skinTex("alliance"), woodTint = { 0.85, 0.85, 0.85 }, floor = "stone", sounds = {},
  },
  horde = {
    color = {
      felt = hex("5a0f0e"), feltDark = hex("2a0605"), feltHi = hex("84201a"),
      brass = hex("9a8f86"), brassLight = hex("d6ccc0"), brassDim = hex("3a3431"),
      banner = hex("6e1410"), bannerHi = hex("a3241b"), deep = hex("170b09"),
      accent = hex("ff7a3d"), lantern = hex("ff9a2a"), paperHead = hex("7a1a12"),
      sqLast = hex("ff8c32"), sqSel = hex("ffb066"), sqDot = hex("1e0604"), coord = hex("e6d3b0"),
    },
    tex = skinTex("horde"), woodTint = { 0.62, 0.58, 0.58 }, floor = "planks", sounds = {},
  },
}

ns.Theme = Theme

-- r, g, b of a color token.
function Theme.rgb(token)
  local c = Theme.color[token]
  return c[1], c[2], c[3]
end

-- The picture of game `id` (media/games/<id>.tga, white, tinted by the caller;
-- tools/gen_game_icons.py) -> its path, or nil for a game without one.
local GAME_ICONS = { belot = true, santase = true, tabla = true, holdem = true, ttt = true, deathroll = true, chess = true }
function Theme.gameIcon(id)
  if GAME_ICONS[id] then return MEDIA .. "games\\" .. id end
end

-- Sets font `token` (heading | ui | uiBold) at layout size `size` on a
-- FontString or an EditBox, scaled by Theme.fontScale.
function Theme.setFont(fs, token, size, flags)
  return fs:SetFont(Theme.font[token], size * (Theme.fontScale[token] or 1), flags or "")
end

-- The texture coordinates of die face n (1..6) on the `dice` texture
-- -> left, right, top, bottom, as SetTexCoord takes them.
function Theme.dieCoord(n)
  local c, r = (n - 1) % 4, math.floor((n - 1) / 4)
  return c / 4, (c + 1) / 4, r / 2, (r + 1) / 2
end

-- The skin key: `saved` when it is one, else "horde" for the Horde, else "alliance".
function Theme.resolve(saved, faction)
  if Theme.SKINS[saved] then return saved end
  return faction == "Horde" and "horde" or "alliance"
end

-- Dresses the theme in skin `key`: its colours go into the existing token
-- arrays (so a module holding Theme.color.felt sees them), its files behind
-- the Theme.tex names. Theme.skin is the key, Theme.S the skin.
function Theme.apply(key)
  local skin = Theme.SKINS[key]
  for token, c in pairs(skin.color) do
    local t = Theme.color[token]
    if t then t[1], t[2], t[3] = c[1], c[2], c[3] else Theme.color[token] = { c[1], c[2], c[3] } end
  end
  for name, file in pairs(skin.tex) do Theme.tex[name] = Theme.tex[file] end
  Theme.skin, Theme.S = key, skin
end

-- r, g, b of `token` in the skin of `faction` ("alliance" | "horde"; a deck
-- wears its own faction), whatever skin is applied. A shared token is Theme.color's.
function Theme.factionColor(faction, token)
  local c = Theme.SKINS[Theme.resolve(faction, faction)].color[token] or Theme.color[token]
  return c[1], c[2], c[3]
end

Theme.apply("alliance")
