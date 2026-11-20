local ns = Loader.ns()
local Deck, Sha256 = ns.Deck, ns.Sha256

-- Known answers below were computed once by an independent Python reference
-- (hashlib + struct, same construction as core/Deck.lua) and pinned.
local KEY_HEX = "00000005616c70686100000004626574610000000668616e642d31"

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function isPermutation(p, n)
  if #p ~= n then return false end
  local seen = {}
  for i = 1, n do
    local v = p[i]
    if type(v) ~= "number" or v < 1 or v > n or v % 1 ~= 0 or seen[v] then return false end
    seen[v] = true
  end
  return true
end

local function list(words)
  local i = 0
  return function() i = i + 1; return assert(words[i], "stream exhausted") end
end

describe("deck key", function()
  it("length-prefixes every seed and the hand id", function()
    local k = Deck.key({ "alpha", "beta" }, "hand-1")
    eq(hex(k), KEY_HEX)
    eq(k, "\0\0\0\5alpha\0\0\0\4beta\0\0\0\6hand-1")
  end)

  it("is unambiguous where a plain concatenation is not", function()
    ok(Deck.key({ "ab", "c" }, "h") ~= Deck.key({ "a", "bc" }, "h"))
    ok(Deck.key({ "a" }, "bh") ~= Deck.key({ "ab" }, "h"))
    ok(Deck.key({ "a", "b" }, "h") ~= Deck.key({ "a" }, "bh"))
    ok(Deck.key({}, "h") ~= Deck.key({ "" }, "h"))
  end)

  it("takes a numeric hand id as its decimal text", function()
    eq(Deck.key({ "s" }, 17), Deck.key({ "s" }, "17"))
  end)

  it("rejects non-string seeds and odd hand ids", function()
    raises(function() Deck.key({ "a", 5 }, "h") end, "seed")
    raises(function() Deck.key({ "a" }, nil) end, "hand")
    raises(function() Deck.key({ "a" }, 1.5) end, "hand")
    raises(function() Deck.key("a", "h") end, "seeds")
  end)
end)

describe("deck stream", function()
  it("block 0 is SHA256(key .. 00 00 00 00), cross-checked with hashlib", function()
    local k = Deck.key({ "alpha", "beta" }, "hand-1")
    eq(Sha256.hex(k .. "\0\0\0\0"), "f55341cabf063d07e18e99130ce2ea032155076ed8c75c77b38c305aaee41e12")
    local nxt = Deck.stream(k)
    eq(nxt(), 0xf55341ca); eq(nxt(), 0xbf063d07); eq(nxt(), 0xe18e9913); eq(nxt(), 0x0ce2ea03)
    eq(nxt(), 0x2155076e); eq(nxt(), 0xd8c75c77); eq(nxt(), 0xb38c305a); eq(nxt(), 0xaee41e12)
  end)

  it("continues into block 1 (counter 00 00 00 01)", function()
    local k = Deck.key({ "alpha", "beta" }, "hand-1")
    local nxt = Deck.stream(k)
    for _ = 1, 8 do nxt() end
    eq(nxt(), 1838587557); eq(nxt(), 2130837741)
    local d = Sha256.digest(k .. "\0\0\0\1")
    local b1, b2, b3, b4 = d:byte(1, 4)
    eq(((b1 * 256 + b2) * 256 + b3) * 256 + b4, 1838587557)
  end)

  it("is deterministic per key and independent per call", function()
    local a, b = Deck.stream("k"), Deck.stream("k")
    local first = a()
    eq(b(), first)
    eq(Deck.stream("k")(), first)
    ok(Deck.stream("K")() ~= first)
  end)
end)

describe("deck below", function()
  it("rejects the biased tail instead of taking a modulo", function()
    -- n = 3: limit = 2^32 - (2^32 % 3) = 2^32 - 1, so 2^32 - 1 is redrawn.
    eq(Deck.below(list({ 4294967295, 5 }), 3), 2)
    eq(Deck.below(list({ 4294967294 }), 3), 4294967294 % 3)
    -- n = 3 * 2^30 on the real stream: words 1 and 3 are >= 3 * 2^30 and redrawn.
    local nxt = Deck.stream(Deck.key({ "alpha", "beta" }, "hand-1"))
    eq(Deck.below(nxt, 3 * 2 ^ 30), 3204857095)
    eq(Deck.below(nxt, 3 * 2 ^ 30), 216197635)
  end)

  it("stays in range", function()
    local nxt = Deck.stream("range")
    for n = 1, 60 do
      local v = Deck.below(nxt, n)
      ok(v >= 0 and v < n and v % 1 == 0, "n=" .. n .. " got " .. v)
    end
    eq(Deck.below(list({ 0 }), 2 ^ 32), 0)
  end)

  it("refuses a bad bound", function()
    raises(function() Deck.below(list({ 1 }), 0) end, "bound")
    raises(function() Deck.below(list({ 1 }), 2.5) end, "bound")
    raises(function() Deck.below(list({ 1 }), 2 ^ 32 + 1) end, "bound")
  end)
end)

describe("deck permutation", function()
  local k = Deck.key({ "alpha", "beta" }, "hand-1")

  it("matches the pinned orders for 24, 32 and 52 cards", function()
    eq(Deck.permutation(k, 24),
      { 17, 19, 10, 12, 5, 15, 3, 4, 2, 14, 13, 18, 8, 1, 7, 6, 9, 23, 16, 21, 24, 22, 20, 11 })
    eq(Deck.permutation(k, 32),
      { 18, 15, 2, 25, 14, 28, 20, 10, 21, 1, 6, 8, 12, 7, 3, 4, 24, 29, 13, 32, 19, 23, 5, 22, 16, 17, 9, 27,
        26, 31, 30, 11 })
    eq(Deck.permutation(k, 52),
      { 28, 42, 20, 35, 33, 34, 22, 13, 30, 18, 39, 6, 14, 27, 23, 24, 37, 16, 40, 44, 2, 8, 10, 12, 45, 51, 26,
        25, 49, 21, 7, 36, 5, 9, 46, 43, 19, 17, 29, 41, 31, 15, 4, 38, 1, 48, 3, 52, 32, 50, 11, 47 })
  end)

  it("is a valid permutation of 1..n", function()
    for _, n in ipairs({ 1, 2, 24, 32, 52 }) do
      for i = 1, 20 do
        local p = Deck.permutation(Deck.key({ "s" .. i }, n), n)
        ok(isPermutation(p, n), "n=" .. n .. " key " .. i)
      end
    end
    eq(Deck.permutation("x", 0), {})
  end)

  it("same key gives the same order, different keys different orders", function()
    eq(Deck.permutation(k, 52), Deck.permutation(k, 52))
    local seen, distinct = {}, 0
    for i = 1, 50 do
      local s = table.concat(Deck.permutation(Deck.key({ "seed", tostring(i) }, "hand"), 52), ",")
      if not seen[s] then seen[s] = true; distinct = distinct + 1 end
    end
    eq(distinct, 50)
    ok(table.concat(Deck.permutation(Deck.key({ "ab", "c" }, "h"), 52), ",")
      ~= table.concat(Deck.permutation(Deck.key({ "a", "bc" }, "h"), 52), ","))
  end)

  it("spreads 3000 shuffles of 4 evenly over the 24 orders", function()
    local counts, total = {}, 3000
    for i = 1, total do
      local s = table.concat(Deck.permutation(Deck.key({ "u" }, i), 4))
      counts[s] = (counts[s] or 0) + 1
    end
    local orders, chi2, expected = 0, 0, total / 24
    for _, c in pairs(counts) do
      orders = orders + 1
      ok(c > 70 and c < 180, "order count " .. c .. " out of bounds")
      chi2 = chi2 + (c - expected) ^ 2 / expected
    end
    eq(orders, 24)
    -- 23 degrees of freedom: mean 23, p(chi2 > 60) is about 4e-5.
    ok(chi2 < 60, "chi2 " .. chi2)
  end)

  it("refuses a bad size", function()
    raises(function() Deck.permutation("k", -1) end, "size")
    raises(function() Deck.permutation("k", 3.5) end, "size")
  end)
end)
