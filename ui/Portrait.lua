local _, ns = ...

-- The round hero portrait (spec 5.5) and its fallback chain: the unit's own
-- portrait, the race icon, the class icon, our silhouette. A portrait is set
-- only when its data changes; nothing here runs per frame.
local Theme, W, Art, Silhouette = ns.Theme, ns.W, ns.Art, ns.Silhouette

local Portrait = {}
ns.Portrait = Portrait

local DISC = { 0x24 / 255, 0x30 / 255, 0x3d / 255 }

local function lookup(name)
  return ns.Adapter and ns.Adapter.lookup and ns.Adapter.lookup(name)
end

-- Who sits there: { name, cls, race, sex, unit }. Me from client.env, a peer
-- from the presence list; the unit is the one the client can draw right now.
function Portrait.who(client, name)
  local env, row = client.env, nil
  if env and name == env.me then
    row = { name = name, cls = env.cls, race = env.race, sex = env.sex }
  else
    local peer = client.presence and client.presence:get(name)
    row = { name = name, cls = peer and peer.cls, race = peer and peer.race, sex = peer and peer.sex }
  end
  local adapter = ns.Adapter
  row.unit = adapter and adapter.unitOf and adapter.unitOf(name) or nil
  return row
end

local function tint(tex, token)
  tex:SetVertexColor(Theme.rgb(token))
end

-- A portrait of `size` px square in `parent`; opts.badge adds the class badge.
function Portrait.new(parent, size, opts)
  local p = { frame = CreateFrame("Frame", nil, parent), source = "empty" }
  local f = p.frame
  f:SetSize(size, size)

  -- The turn glow: a halo behind the portrait, under the disc, so only its rim
  -- shows around the face (a glow in the frame above would cover the face).
  p.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  p.glow:SetTexture(Theme.tex.glow)
  p.glow:SetPoint("CENTER", f, "CENTER")
  p.glow:SetSize(size * 1.9, size * 1.9)
  tint(p.glow, "goldHi")
  p.glow:Hide()

  p.bg = f:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints(f)
  p.bg:SetTexture(Theme.tex.mask)
  p.bg:SetVertexColor(DISC[1], DISC[2], DISC[3])

  p.tex = f:CreateTexture(nil, "ARTWORK")
  p.tex:SetAllPoints(f)
  W.mask(p.tex, f)

  p.sil = Silhouette.new(f)
  p.sil.frame:SetAllPoints(f)
  p.sil.frame:Hide()

  -- Ring and badge sit in a frame above the silhouette's.
  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints(f)
  top:SetFrameLevel(f:GetFrameLevel() + 5)
  p.top = top

  p.ring = top:CreateTexture(nil, "OVERLAY")
  p.ring:SetTexture(Theme.tex.pring)
  p.ring:SetPoint("CENTER", f, "CENTER")
  p.ring:SetSize(size + 4, size + 4)
  tint(p.ring, "brass")

  if opts and opts.badge then
    local b = size * 0.4
    p.badge = top:CreateTexture(nil, "OVERLAY", nil, 2)
    p.badge:SetSize(b, b)
    p.badge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    p.badge:Hide()
  end

  function p:turn(on)
    if on then tint(self.ring, "goldHi"); self.glow:Show() else tint(self.ring, "brass"); self.glow:Hide() end
  end

  local function setBadge(self, cls)
    local b = self.badge
    if not b then return end
    b:SetTexCoord(0, 1, 0, 1)
    if cls and Art.set(b, "class", cls) then
      b:SetVertexColor(1, 1, 1)
    else
      b:SetTexture(Theme.tex.chair)
      b:SetVertexColor(ns.classColor(cls))
    end
    b:Show()
  end

  -- Shows `who` (see Portrait.who), or an empty seat for nil; nothing to do
  -- while who and what the client knows of him are the ones shown, unless `force`.
  function p:set(who, force)
    local key = who and table.concat({ tostring(who.name), tostring(who.cls), tostring(who.race),
                                       tostring(who.sex), tostring(who.unit) }, "\1") or ""
    if key == self.key and not force then return end
    self.key = key
    local tex, sil = self.tex, self.sil
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(1, 1, 1)
    sil.frame:Hide()
    tex:Show()
    if not who then
      self.source = "empty"
      tex:SetTexture(Theme.tex.chair_empty)
      self.ring:Hide(); self.glow:Hide()
      if self.badge then self.badge:Hide() end
      return
    end
    self.ring:Show()
    local race = type(who.race) == "string" and Art.RACE[who.race] or nil
    local sex = type(who.sex) == "number" and Art.SEX[who.sex] or nil
    local portrait = lookup("SetPortraitTexture")
    if who.unit and type(portrait) == "function" and pcall(portrait, tex, who.unit) then
      self.source = "unit"
    elseif race and sex and Art.set(tex, "race", race, sex) then
      self.source = "race"
    elseif who.cls and Art.set(tex, "class", who.cls) then
      self.source = "class"
    else
      self.source = "sil"
      tex:Hide()
      sil:set(Silhouette.layers(race, who.sex == 3 and "queen" or "jack"))
      sil.frame:Show()
    end
    setBadge(self, who.cls)
  end

  p:set(nil)
  return p
end
