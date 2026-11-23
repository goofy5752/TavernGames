-- ui/Theme.lua is data only: load it on its own into a fresh namespace.
local ns = {}
loadfile("ui/Theme.lua")("TavernGames", ns)
local Theme = ns.Theme
local MEDIA = "Interface\\AddOns\\TavernGames\\media\\"

describe("theme", function()
  it("every texture in the theme exists as a 32-bit TGA of the listed size", function()
    local n = 0
    for name, size in pairs(Theme.texSize) do
      local w, h = type(size) == "table" and size[1] or size, type(size) == "table" and size[2] or size
      local f = io.open("media/" .. name .. ".tga", "rb"); ok(f, "missing media/" .. name .. ".tga")
      if f then local d = f:read(18); f:close(); eq({ d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256, d:byte(17) }, { w, h, 32 }, name); n = n + 1 end
    end
    eq(Theme.texSize.card, { 64, 128 }); eq(Theme.texSize.card_back, { 64, 128 }); eq(Theme.texSize.suits, { 128, 32 })
    eq(Theme.texSize.point, { 32, 128 }); eq(Theme.texSize.checker, 64); eq(Theme.texSize.dice, { 128, 64 })
    eq(Theme.texSize.oval, { 512, 256 }); eq(Theme.texSize.chip, 32); ok(n >= 20)
    eq({ Theme.rgb("glow") }, { 1, 209 / 255, 0 })
  end)

  it("the skin follows the saved key, else the faction, else Alliance", function()
    eq(Theme.resolve(nil, "Horde"), "horde"); eq(Theme.resolve(nil, "Alliance"), "alliance")
    eq(Theme.resolve(nil, "Neutral"), "alliance"); eq(Theme.resolve(nil, nil), "alliance")
    eq(Theme.resolve("alliance", "Horde"), "alliance"); eq(Theme.resolve("darkmoon", "Horde"), "horde"); eq(Theme.resolve(7, nil), "alliance")
    eq(Theme.resolve("horde", "Alliance"), "horde")
  end)

  it("apply repaints the tokens in place and swaps the skin's textures", function()
    eq(Theme.skin, "alliance"); ok(Theme.S == Theme.SKINS.alliance) -- applied when the file loads
    local felt, deep = Theme.color.felt, Theme.color.deep; Theme.apply("horde")
    ok(Theme.color.felt == felt); ok(Theme.color.deep == deep)
    eq({ Theme.rgb("felt") }, { 0x5a / 255, 0x0f / 255, 0x0e / 255 })
    eq({ Theme.rgb("paperHead") }, { 0x7a / 255, 0x1a / 255, 0x12 / 255 })
    eq(Theme.tex.felt, MEDIA .. "skin\\felt_horde"); eq(Theme.tex.cap, MEDIA .. "skin\\cap_horde")
    eq(Theme.tex.chip, MEDIA .. "skin\\chip"); eq(Theme.skin, "horde"); ok(Theme.S == Theme.SKINS.horde)
    eq(Theme.S.floor, "planks"); eq(Theme.S.woodTint, { 0.62, 0.58, 0.58 }); eq(Theme.S.sounds, {})
    Theme.apply("alliance"); eq({ Theme.rgb("brass") }, { 0xd8 / 255, 0xab / 255, 0x4a / 255 })
    eq(Theme.tex.felt, MEDIA .. "skin\\felt_alliance"); eq(Theme.tex.button_hi, MEDIA .. "skin\\button_hi_alliance")
    eq(Theme.S.floor, "stone"); eq(Theme.S.woodTint, { 0.85, 0.85, 0.85 })
  end)

  it("both skins set the same tokens; the shared ones are the same in either skin", function()
    local keys = {}
    for k in pairs(Theme.SKINS.alliance.color) do keys[#keys + 1] = k end
    table.sort(keys)
    eq(keys, { "accent", "banner", "bannerHi", "brass", "brassDim", "brassLight", "deep", "felt", "feltDark", "feltHi",
      "lantern", "paperHead" })
    for _, k in ipairs(keys) do ok(Theme.SKINS.horde.color[k], k) end
    for _, s in pairs({ "alliance", "horde" }) do
      Theme.apply(s)
      eq({ Theme.rgb("ink") }, { 0xf2 / 255, 0xe6 / 255, 0xc8 / 255 }); eq({ Theme.rgb("knob") }, { 0x8a / 255, 0x2a / 255, 0x1a / 255 })
      eq({ Theme.rgb("goldHi") }, { 0xfb / 255, 0xe3 / 255, 0xa0 / 255 }); eq({ Theme.rgb("coin") }, { 1, 0xe0 / 255, 0x8a / 255 })
      eq({ Theme.rgb("glow") }, { 1, 209 / 255, 0 })
    end
    Theme.apply("alliance")
  end)

  it("factionColor reads a named skin whatever skin is applied", function()
    Theme.apply("alliance")
    eq({ Theme.factionColor("horde", "banner") }, { 0x6e / 255, 0x14 / 255, 0x10 / 255 })
    eq({ Theme.factionColor("alliance", "banner") }, { 0x1b / 255, 0x3f / 255, 0x75 / 255 })
    eq({ Theme.factionColor("horde", "ink") }, { Theme.rgb("ink") }) -- a shared token
    eq({ Theme.rgb("banner") }, { 0x1b / 255, 0x3f / 255, 0x75 / 255 })
  end)

  it("every skin texture equals the size of the texture it replaces", function()
    local function wh(size) if type(size) == "table" then return { size[1], size[2] } end return { size, size } end
    for _, s in ipairs({ "alliance", "horde" }) do
      for name, file in pairs(Theme.SKINS[s].tex) do
        ok(Theme.skinTexSize[file], s .. " " .. name .. " -> " .. file)
        if Theme.texSize[name] then eq(wh(Theme.skinTexSize[file]), wh(Theme.texSize[name]), file) end
        eq(Theme.tex[file], MEDIA .. "skin\\" .. file)
      end
    end
    for name in pairs(Theme.SKINS.alliance.tex) do
      eq(Theme.skinTexSize[Theme.SKINS.alliance.tex[name]], Theme.skinTexSize[Theme.SKINS.horde.tex[name]], name)
    end
    eq(Theme.SKINS.alliance.tex.crest, "crest_alliance"); eq(Theme.SKINS.horde.tex.crest, "crest_horde")
    eq(Theme.SKINS.horde.tex.chip, "chip")
  end)

  it("a die face is cut from the dice texture: faces 1-4 on the top row, 5 and 6 below", function()
    eq({ Theme.dieCoord(1) }, { 0, 0.25, 0, 0.5 }); eq({ Theme.dieCoord(3) }, { 0.5, 0.75, 0, 0.5 }); eq({ Theme.dieCoord(4) }, { 0.75, 1, 0, 0.5 })
    eq({ Theme.dieCoord(5) }, { 0, 0.25, 0.5, 1 }); eq({ Theme.dieCoord(6) }, { 0.25, 0.5, 0.5, 1 })
  end)
end)
