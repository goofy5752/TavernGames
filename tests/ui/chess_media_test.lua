-- The chess textures (tools/gen_chess_textures.py) exist as 32-bit TGAs of the sizes the board view relies on.
local EXPECT = {}
for _, faction in ipairs({ "alliance", "horde" }) do
  for _, colour in ipairs({ "w", "b" }) do
    for _, piece in ipairs({ "p", "n", "b", "r", "q", "k" }) do
      EXPECT[faction .. "_" .. colour .. piece] = { 128, 128 }
    end
  end
end
for _, name in ipairs({ "sq_alliance_l", "sq_alliance_d", "sq_horde_l", "sq_horde_d", "dot", "ring", "check" }) do
  EXPECT[name] = { 64, 64 }
end

describe("chess media", function()
  it("lists 31 textures", function()
    local n = 0
    for _ in pairs(EXPECT) do n = n + 1 end
    eq(n, 31)
  end)

  it("every file exists and its header reads { w, h, 32 }", function()
    for name, size in pairs(EXPECT) do
      local f = io.open("media/chess/" .. name .. ".tga", "rb"); ok(f, "missing media/chess/" .. name .. ".tga")
      if f then
        local d = f:read(18); f:close()
        eq({ d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256, d:byte(17) }, { size[1], size[2], 32 }, name)
      end
    end
  end)
end)
