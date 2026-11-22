local _, ns = ...

-- SHA-256 (FIPS 180-4) in pure Lua 5.1 arithmetic: no bit library, no integer
-- overflow. A 32-bit word is a double in [0, 2^32); every intermediate stays
-- below 2^53, so all of it is exact.
--   rotr/shr: multiply, divide, floor, %
--   add mod 2^32: plain sum, then % 2^32
--   xor: nibble by nibble through one 16x16 table (built once at load)
--   and: x AND y = (x + y - (x XOR y)) / 2
local Sha256 = {}
ns.Sha256 = Sha256

local floor, byte, char, format, concat = math.floor, string.byte, string.char, string.format, table.concat

local W32 = 4294967296 -- 2^32

-- XOR4[a * 16 + b] = a XOR b for nibbles a, b (256 entries). Each entry uses
-- the one for (a/2, b/2), which has a smaller index, so one forward pass fills it.
local XOR4 = { [0] = 0 }
for a = 0, 15 do
  for b = 0, 15 do
    if a + b > 0 then
      XOR4[a * 16 + b] = (a + b) % 2 + 2 * XOR4[floor(a / 2) * 16 + floor(b / 2)]
    end
  end
end

-- XOR of two words, one nibble at a time from the low end.
local function bxor(x, y)
  local r, p = 0, 1
  for _ = 1, 7 do
    local xa, ya = x % 16, y % 16
    r = r + XOR4[xa * 16 + ya] * p
    x, y, p = (x - xa) / 16, (y - ya) / 16, p * 16
  end
  return r + XOR4[x * 16 + y] * p
end

local function band(x, y)
  return (x + y - bxor(x, y)) / 2
end

-- Rotate right by n (0 < n < 32): the low n bits move to the top.
local function rotr(x, n)
  local p = 2 ^ n
  local low = x % p
  return low * (W32 / p) + (x - low) / p
end

local function shr(x, n)
  local p = 2 ^ n
  return (x - x % p) / p
end

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local H0 = {
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

local W = {} -- message schedule, reused by every block

-- Compress the 64-byte block of `s` starting at byte `at` into the state H.
local function compress(H, s, at)
  for t = 1, 16 do
    local b1, b2, b3, b4 = byte(s, at, at + 3)
    W[t] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
    at = at + 4
  end
  for t = 17, 64 do
    local w15, w2 = W[t - 15], W[t - 2]
    local s0 = bxor(bxor(rotr(w15, 7), rotr(w15, 18)), shr(w15, 3))
    local s1 = bxor(bxor(rotr(w2, 17), rotr(w2, 19)), shr(w2, 10))
    W[t] = (W[t - 16] + s0 + W[t - 7] + s1) % W32
  end

  local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
  for t = 1, 64 do
    local S1 = bxor(bxor(rotr(e, 6), rotr(e, 11)), rotr(e, 25))
    -- Ch: the two halves have disjoint bits, so XOR is a sum.
    local ch = band(e, f) + band(W32 - 1 - e, g)
    local t1 = h + S1 + ch + K[t] + W[t]
    local S0 = bxor(bxor(rotr(a, 2), rotr(a, 13)), rotr(a, 22))
    -- Maj = (a AND b) OR (c AND (a XOR b)); disjoint bits again.
    local axb = bxor(a, b)
    local maj = (a + b - axb) / 2 + band(c, axb)
    h, g, f, e = g, f, e, (d + t1) % W32
    d, c, b, a = c, b, a, (t1 + S0 + maj) % W32
  end

  H[1] = (H[1] + a) % W32; H[2] = (H[2] + b) % W32
  H[3] = (H[3] + c) % W32; H[4] = (H[4] + d) % W32
  H[5] = (H[5] + e) % W32; H[6] = (H[6] + f) % W32
  H[7] = (H[7] + g) % W32; H[8] = (H[8] + h) % W32
end

-- Closes the hash of a message of `len` bytes whose last, incomplete block is `tail`.
local function close(H, tail, len)
  -- Tail: the remaining bytes, 0x80, zeros, then the bit length as 8
  -- big-endian bytes, filling one or two final blocks.
  local zeros = (55 - #tail) % 64
  local bits = len * 8
  local lenBytes = {}
  for i = 8, 1, -1 do
    lenBytes[i] = char(bits % 256)
    bits = floor(bits / 256)
  end
  tail = tail .. "\128" .. string.rep("\0", zeros) .. concat(lenBytes)
  for at = 1, #tail, 64 do compress(H, tail, at) end
  return H
end

-- The eight state words after hashing `msg`.
local function words(msg)
  assert(type(msg) == "string", "Sha256: message must be a string")
  local H = {}
  for i = 1, 8 do H[i] = H0[i] end
  local len = #msg
  local full = len - len % 64
  for at = 1, full, 64 do compress(H, msg, at) end
  return close(H, msg:sub(full + 1), len)
end

-- The 32 bytes of the state words H.
local function bytes(H)
  local out = {}
  for i = 1, 8 do
    local w = H[i]
    local b4 = w % 256; w = (w - b4) / 256
    local b3 = w % 256; w = (w - b3) / 256
    local b2 = w % 256
    out[i] = char((w - b2) / 256, b2, b3, b4)
  end
  return concat(out)
end

local function hexOf(s) return (s:gsub(".", function(c) return format("%02x", byte(c)) end)) end

-- 32-byte binary digest.
function Sha256.digest(msg) return bytes(words(msg)) end

-- 64 lowercase hex characters (built per byte: %x of a number >= 2^31 is not
-- portable across Lua 5.1 builds).
function Sha256.hex(msg) return hexOf(Sha256.digest(msg)) end

-- A running hash, for a message that comes in parts: s:add(part) any number of
-- times, then s:hex() once -> the hex of the parts joined.
function Sha256.stream()
  local H, rest, len = {}, "", 0
  for i = 1, 8 do H[i] = H0[i] end
  local s = {}
  function s:add(part)
    assert(type(part) == "string", "Sha256: message must be a string")
    len = len + #part
    local buf = rest .. part
    local full = #buf - #buf % 64
    for at = 1, full, 64 do compress(H, buf, at) end
    rest = buf:sub(full + 1)
  end
  function s:hex() return hexOf(bytes(close(H, rest, len))) end
  return s
end

return Sha256
