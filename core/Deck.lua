local _, ns = ...

-- Deterministic deck shuffle for the commit-reveal deal (spec 6.3). Every
-- client that knows the revealed seeds derives the same order.
--
-- Exact construction (any reimplementation must match it byte for byte):
--   be32(x)          = x as 4 big-endian bytes, 0 <= x < 2^32
--   key(seeds, hand) = be32(#seed_1) .. seed_1 .. ... .. be32(#seed_n) .. seed_n
--                      .. be32(#hand) .. hand
--                      (a numeric hand id is first turned into its decimal text)
--   block j          = SHA256(key .. be32(j)), j = 0, 1, 2, ...
--   stream           = the 8 big-endian 32-bit words of block 0, then those
--                      of block 1, ... (word order = byte order of the digest)
--   below(n)         = draw w; redraw while w >= 2^32 - (2^32 % n); return w % n
--   permutation(n)   = p = {1, ..., n}; for i = n down to 2:
--                      j = below(i) + 1; swap p[i], p[j]
-- Every seed and the hand id are length-prefixed, so {"ab","c"} and {"a","bc"}
-- give different keys. Spec 6.3's "Shuffle(SHA256(seed_1 .. seed_n .. handId))"
-- is this: SHA-256 in counter mode over the key is the hash-based PRNG.
local Deck = {}
ns.Deck = Deck

local Sha256 = ns.Sha256
local floor, byte, char = math.floor, string.byte, string.char

local W32 = 4294967296 -- 2^32

local function be32(x)
  local b4 = x % 256; x = (x - b4) / 256
  local b3 = x % 256; x = (x - b3) / 256
  local b2 = x % 256
  return char((x - b2) / 256, b2, b3, b4)
end

local function isInteger(n)
  return type(n) == "number" and n == floor(n)
end

-- The shuffle key for one hand: the revealed seeds in seat order, then the
-- hand id (a string, or an integer below 10^14).
function Deck.key(seeds, handId)
  assert(type(seeds) == "table", "Deck.key: seeds must be a list of strings")
  if isInteger(handId) and handId > -1e14 and handId < 1e14 then
    handId = tostring(handId)
  end
  assert(type(handId) == "string", "Deck.key: hand id must be a string or an integer")
  local parts = {}
  for i = 1, #seeds do
    local s = seeds[i]
    assert(type(s) == "string", "Deck.key: seed " .. i .. " is not a string")
    parts[#parts + 1] = be32(#s)
    parts[#parts + 1] = s
  end
  parts[#parts + 1] = be32(#handId)
  parts[#parts + 1] = handId
  return table.concat(parts)
end

-- A generator of 32-bit unsigned integers (as numbers in [0, 2^32)).
function Deck.stream(key)
  assert(type(key) == "string", "Deck.stream: key must be a string")
  local counter, block, pos = 0, nil, 33
  return function()
    if pos > 32 then
      block = Sha256.digest(key .. be32(counter))
      counter = counter + 1
      pos = 1
    end
    local b1, b2, b3, b4 = byte(block, pos, pos + 3)
    pos = pos + 4
    return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
  end
end

-- Uniform integer in 0..n-1 from a stream, for 1 <= n <= 2^32.
function Deck.below(nextWord, n)
  assert(isInteger(n) and n >= 1 and n <= W32, "Deck.below: bound must be an integer in 1..2^32")
  local limit = W32 - W32 % n
  local w = nextWord()
  while w >= limit do w = nextWord() end
  return w % n
end

-- Fisher-Yates permutation of 1..n driven by the stream of `key`.
function Deck.permutation(key, n)
  assert(isInteger(n) and n >= 0, "Deck.permutation: size must be a non-negative integer")
  local p = {}
  for i = 1, n do p[i] = i end
  local nextWord = Deck.stream(key)
  for i = n, 2, -1 do
    local j = Deck.below(nextWord, i) + 1
    p[i], p[j] = p[j], p[i]
  end
  return p
end

return Deck
