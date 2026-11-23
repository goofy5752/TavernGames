-- Every faction skin texture exists as a 32-bit TGA of the size the later tasks rely on.
local SIZES = {
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
