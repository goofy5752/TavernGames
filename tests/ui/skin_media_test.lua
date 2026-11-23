-- Every faction skin texture (Theme.skinTexSize) exists as a 32-bit TGA of the size the later tasks rely on.
local ns = {}
loadfile("ui/Theme.lua")("TavernGames", ns)
local SIZES = ns.Theme.skinTexSize

describe("skin media", function()
  it("lists 25 textures", function()
    local n = 0
    for _ in pairs(SIZES) do n = n + 1 end
    eq(n, 25)
  end)

  it("every file exists and its header reads { w, h, 32 }", function()
    for name, size in pairs(SIZES) do
      local f = io.open("media/skin/" .. name .. ".tga", "rb"); ok(f, "missing media/skin/" .. name .. ".tga")
      if f then
        local d = f:read(18); f:close()
        eq({ d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256, d:byte(17) }, { size[1], size[2], 32 }, name)
      end
    end
  end)
end)
