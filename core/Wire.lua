local _, ns = ...

-- Wire format: message table <-> addon-channel text.
-- pack: serialize, deflate, encode for the addon channel (no NUL bytes).
-- unpack: the reverse; nil on any failure or a non-table result, never raises.
local Wire = {}
Wire.__index = Wire
ns.Wire = Wire

function Wire.new(serializer, deflate)
  return setmetatable({ serializer = serializer, deflate = deflate }, Wire)
end

function Wire:pack(msg)
  local raw = self.serializer:Serialize(msg)
  return self.deflate:EncodeForWoWAddonChannel(self.deflate:CompressDeflate(raw))
end

local function decode(self, str)
  if type(str) ~= "string" or str == "" then return nil end
  local compressed = self.deflate:DecodeForWoWAddonChannel(str)
  if not compressed then return nil end
  local raw = self.deflate:DecompressDeflate(compressed)
  if not raw then return nil end
  local okDecode, msg = self.serializer:Deserialize(raw)
  if okDecode and type(msg) == "table" then return msg end
  return nil
end

function Wire:unpack(str)
  local okCall, msg = pcall(decode, self, str)
  if okCall then return msg end
  return nil
end
