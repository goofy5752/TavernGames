-- ui/Theme.lua is data only: load it on its own into a fresh namespace.
local ns = {}
loadfile("ui/Theme.lua")("TavernGames", ns)
local Theme = ns.Theme

describe("theme", function()
  it("every texture in the theme exists as a 32-bit TGA of the listed size", function()
    local n = 0
    for name, size in pairs(Theme.texSize) do
      local w, h = type(size) == "table" and size[1] or size, type(size) == "table" and size[2] or size
      local f = io.open("media/" .. name .. ".tga", "rb"); ok(f, "missing media/" .. name .. ".tga")
      if f then local d = f:read(18); f:close(); eq({ d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256, d:byte(17) }, { w, h, 32 }, name); n = n + 1 end
    end
    eq(Theme.texSize.card, { 64, 128 }); eq(Theme.texSize.card_back, { 64, 128 }); eq(Theme.texSize.suits, { 128, 32 })
    eq(Theme.texSize.point, { 32, 128 }); eq(Theme.texSize.checker, 64); eq(Theme.texSize.dice, { 128, 64 }); ok(n >= 18)
    eq({ Theme.rgb("glow") }, { 1, 209 / 255, 0 })
  end)
end)
