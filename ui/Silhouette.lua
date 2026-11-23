local _, ns = ...

-- The stand-in portrait/cameo (spec 5.3): a bust and accessory layers, cut from
-- the cells of media/skin/sil (a strip of 8 cells, Theme.tex.sil).
local Theme, Decks = ns.Theme, ns.Decks

local Silhouette = {
  CELL = { bust = 1, crown = 2, horns = 3, ears = 4, hood = 5, beard = 6, tusks = 7, hair = 8 },
}
ns.Silhouette = Silhouette

local POOL = 4
local BEHIND = { hair = true, hood = true }
local ROLE_KEY = { king = "k", queen = "q", jack = "j" }

-- The layers of a `role` ("king" | "queen" | "jack") of `race`, in draw order:
-- hair and hood, the bust, then the rest. A king is always crowned.
function Silhouette.layers(race, role)
  local r = Decks.RACES[race]
  if not r then return { "bust" } end
  local acc = {}
  for _, a in ipairs(r[ROLE_KEY[role] or "j"]) do acc[#acc + 1] = a end
  if role == "king" then
    local has = false
    for _, a in ipairs(acc) do if a == "crown" then has = true end end
    if not has then acc[#acc + 1] = "crown" end
  end
  local out = {}
  for _, a in ipairs(acc) do if BEHIND[a] then out[#out + 1] = a end end
  out[#out + 1] = "bust"
  for _, a in ipairs(acc) do if not BEHIND[a] then out[#out + 1] = a end end
  return out
end

-- A silhouette in a frame `sil.frame` the caller sizes and anchors.
function Silhouette.new(parent)
  local sil = { frame = CreateFrame("Frame", nil, parent), tex = {}, layers = {} }
  for i = 1, POOL do
    local t = sil.frame:CreateTexture(nil, "ARTWORK", nil, i)
    t:SetAllPoints(sil.frame)
    t:Hide()
    sil.tex[i] = t
  end
  -- Draws `layers` (a list of layer names); the spare textures are hidden.
  function sil:set(layers)
    self.layers = layers
    for i = 1, POOL do
      local t, name = self.tex[i], layers[i]
      local n = name and Silhouette.CELL[name]
      if n then
        t:SetTexture(Theme.tex.sil)
        t:SetTexCoord((n - 1) / 8, n / 8, 0, 1)
        t:Show()
      else
        t:Hide()
      end
    end
  end
  return sil
end
