local _, ns = ...

-- The resize grip: a window keeps its layout and grows or shrinks as a whole
-- (SetScale), so text, cards, boards and the felt all stay in proportion.
-- Drag the grip at the bottom-right corner; the top-left corner stays where
-- it is. A right click on the grip gives the normal size back. The scale is
-- kept per window key ("main", "table") in ns.db.scale, account-wide.
-- Dialogs that open over a window follow its scale (Resize.follow).
local Theme, L = ns.Theme, ns.L

local Resize = { MIN = 0.6, MAX = 2.0, GRIP = 16 }
ns.Resize = Resize

local GRIP_TEX = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local frames = {} -- key -> the window frame
local followers = {} -- key -> { frame, ... }

local function clampTo(s, lo, hi)
  if s < lo then return lo end
  if s > hi then return hi end
  return s
end

-- The scale saved for `key` (1 when none, or when the value is out of range).
function Resize.get(key)
  local t = ns.db and ns.db.scale
  local s = type(t) == "table" and tonumber(t[key]) or nil
  if s and s >= Resize.MIN and s <= Resize.MAX then return s end
  return 1
end

local function store(key, s)
  if not ns.db then return end
  local t = ns.db.scale
  if type(t) ~= "table" then t = {} end
  t[key] = s
  ns.db.scale = t
end

-- The largest scale at which `f` still fits on the screen (at most MAX).
local function maxScale(f)
  local w, h = f:GetWidth(), f:GetHeight()
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local hi = Resize.MAX
  if w and w > 0 and sw and sw > 0 then hi = math.min(hi, sw / w) end
  if h and h > 0 and sh and sh > 0 then hi = math.min(hi, sh / h) end
  return math.max(hi, Resize.MIN)
end

-- Scales `f` to `s`, its top-left corner held at (left, top) in UIParent units.
local function place(f, s, left, top)
  f:SetScale(s)
  if left and top then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / s, top / s)
  end
end

-- The top-left corner of `f` in UIParent units (nil when it has no layout yet).
local function corner(f)
  local left, top = f:GetLeft(), f:GetTop()
  if not (left and top) then return nil end
  local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  return left * k, top * k
end

local function apply(key, s)
  local f = frames[key]
  if f then
    local left, top = corner(f)
    place(f, s, left, top)
  end
  for _, d in ipairs(followers[key] or {}) do d:SetScale(s) end
end

-- Sets window `key` to scale `s` (clamped) and keeps it.
function Resize.set(key, s)
  local f = frames[key]
  s = clampTo(s, Resize.MIN, f and maxScale(f) or Resize.MAX)
  apply(key, s)
  store(key, s)
  return s
end

-- The scale for a drag: the cursor at (x, y) and the corner at (left, top),
-- all in UIParent units, over a window of w x h at scale 1. The grip follows
-- the cursor along the window's diagonal, so dragging right, down or both
-- grows it and the opposite shrinks it.
function Resize.dragScale(x, y, left, top, w, h)
  return ((x - left) + (top - y)) / (w + h)
end

local function cursor()
  local x, y = GetCursorPosition()
  local k = UIParent:GetEffectiveScale()
  return x / k, y / k
end

local function stopDrag(grip)
  if not grip.drag then return end
  grip:SetScript("OnUpdate", nil)
  local key = grip.drag.key
  grip.drag = nil
  store(key, frames[key]:GetScale())
end

local function onDown(grip, button)
  local f = frames[grip.key]
  if button == "RightButton" then return Resize.set(grip.key, 1) end
  if button ~= "LeftButton" then return end
  local left, top = corner(f)
  if not left then return end
  grip.drag = { key = grip.key, left = left, top = top, hi = maxScale(f) }
  grip:SetScript("OnUpdate", function()
    local d = grip.drag
    if not d then return end
    local x, y = cursor()
    local s = Resize.dragScale(x, y, d.left, d.top, f:GetWidth(), f:GetHeight())
    s = clampTo(s, Resize.MIN, d.hi)
    place(f, s, d.left, d.top)
    for _, dlg in ipairs(followers[d.key] or {}) do dlg:SetScale(s) end
  end)
end

local function tint(grip, on)
  local c = Theme.color[on and "brassLight" or "brass"]
  grip.tex:SetVertexColor(c[1], c[2], c[3], 1)
end

-- Makes window `f` resizable under `key`: a grip in its bottom-right corner,
-- `inset` px in from the edges, and its saved scale applied now.
function Resize.attach(f, key, inset)
  frames[key] = f
  inset = inset or 4
  local grip = CreateFrame("Button", nil, f)
  grip.key = key
  grip:SetSize(Resize.GRIP, Resize.GRIP)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
  grip:SetFrameLevel(f:GetFrameLevel() + 20)
  grip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  grip:EnableMouse(true)
  local tex = grip:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(grip)
  tex:SetTexture(GRIP_TEX)
  grip.tex = tex
  tint(grip, false)
  grip:SetScript("OnMouseDown", onDown)
  grip:SetScript("OnMouseUp", stopDrag)
  grip:SetScript("OnHide", stopDrag)
  grip:SetScript("OnEnter", function(self)
    tint(self, true)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L("resize.tip"))
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function(self)
    tint(self, false)
    GameTooltip:Hide()
  end)
  f:SetScale(Resize.get(key))
  return grip
end

-- Dialog `d` takes the scale of window `key`, now and whenever it changes.
function Resize.follow(d, key)
  followers[key] = followers[key] or {}
  table.insert(followers[key], d)
  d:SetScale(Resize.get(key))
end
