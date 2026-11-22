local ns = Loader.ns()
local Sha256 = ns.Sha256

describe("sha256", function()
  it("matches the FIPS 180-2 vectors", function()
    eq(Sha256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    eq(Sha256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    eq(Sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    eq(Sha256.hex("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
        .. "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"),
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1")
  end)

  it("hashes one million 'a'", function()
    eq(Sha256.hex(string.rep("a", 1000000)),
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
  end)

  it("pads correctly around the block boundaries", function()
    -- Pinned from Python hashlib.sha256(b"a" * n).
    local want = {
      [55] = "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
      [56] = "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
      [63] = "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
      [64] = "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
      [65] = "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
      [119] = "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
      [120] = "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c",
      [128] = "6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e",
    }
    for n, hex in pairs(want) do
      eq(Sha256.hex(string.rep("a", n)), hex, "length " .. n)
    end
  end)

  it("hashes every byte value 0..255", function()
    local bytes = {}
    for i = 0, 255 do bytes[#bytes + 1] = string.char(i) end
    eq(Sha256.hex(table.concat(bytes)), "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880")
  end)

  it("a running hash of parts equals the hash of the parts joined (final review I3)", function()
    local parts = { "", "abc", string.rep("x", 63), "y", string.rep("z", 64), string.rep("w", 129), "", "tail" }
    local s = Sha256.stream()
    for _, p in ipairs(parts) do s:add(p) end
    eq(s:hex(), Sha256.hex(table.concat(parts)))
    eq(Sha256.stream():hex(), Sha256.hex(""))
    for _, n in ipairs({ 55, 56, 63, 64, 65, 119, 120, 128 }) do
      local one, msg = Sha256.stream(), string.rep("a", n)
      for j = 1, n, 7 do one:add(msg:sub(j, j + 6)) end
      eq(one:hex(), Sha256.hex(msg), "length " .. n)
    end
    raises(function() Sha256.stream():add(5) end, "must be a string")
  end)

  it("digest is the 32 raw bytes behind hex", function()
    local d = Sha256.digest("abc")
    eq(type(d), "string")
    eq(#d, 32)
    local hex = d:gsub(".", function(c) return string.format("%02x", c:byte()) end)
    eq(hex, Sha256.hex("abc"))
    eq(d:byte(1), 0xba); eq(d:byte(32), 0xad)
  end)

  it("hex is 64 lowercase hex chars", function()
    local h = Sha256.hex("Tavern")
    eq(#h, 64)
    ok(h:match("^[0-9a-f]+$"), h)
  end)
end)
