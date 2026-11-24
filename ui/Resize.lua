local _, ns = ...

-- The resize grip: a window keeps its layout and grows or shrinks as a whole
-- (SetScale), so text, cards, boards and the felt all stay in proportion.
-- Drag the grip at the bottom-right corner; the top-left corner stays where
-- it is. A right click on the grip gives the normal size back. The scale is
-- kept per window key ("main", "table") in ns.db.scale, account-wide.
-- Dialogs that open over a window follow its scale (Resize.follow).
-- The scale in use is the saved one held between two bounds, set again whenever
-- they move (the window's size, a side window shown, the screen): at most what
-- fits on the screen (with Resize.extra[key]'s width beside the window), at
-- least MIN and what keeps the smallest text (FONT_MIN, W.WRAP_MIN) READ_PX
-- screen pixels tall. Fitting on the screen comes first.
local Theme, L = ns.Theme, ns.L

local Resize = { MIN = 0.6, MAX = 2.0, GRIP = 24, READ_PX = 8, FONT_MIN = 9 }
ns.Resize = Resize
local frames = {} -- key -> the window frame
local followers = {} -- key -> { frame, ... }
Resize.extra = {} -- key -> function() -> the width (window units) of what opens beside it

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

-- Screen pixels per UIParent unit: the physical screen's height over UIParent's
-- (a client that does not say its screen's size: a 1080p screen).
function Resize.pixels()
  local h = UIParent:GetHeight()
  local ph = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()) or 1080
  if not (h and h > 0 and ph and ph > 0) then return 1 end
  return ph / h
end

-- The smallest scale that keeps the smallest text readable on this screen (at least MIN).
function Resize.least()
  return math.max(Resize.MIN, Resize.READ_PX / (Resize.FONT_MIN * Resize.pixels()))
end

-- The largest scale at which window `key` (frame `f`) and what opens beside it still fit on the screen
-- (at most MAX); `alone`: the window alone, without what opens beside it (Resize.extra).
local function maxScale(f, key, alone)
  local w, h = f:GetWidth(), f:GetHeight()
  local extra = not alone and Resize.extra[key]
  if w and extra then w = w + (extra() or 0) end
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local hi = Resize.MAX
  if w and w > 0 and sw and sw > 0 then hi = math.min(hi, sw / w) end
  if h and h > 0 and sh and sh > 0 then hi = math.min(hi, sh / h) end
  return hi
end

-- The bounds of window `key`'s scale -> lo, hi (on a screen too small for both, the window fits);
-- `alone`: the window's own, without the room of what opens beside it.
function Resize.bounds(key, alone)
  local f = frames[key]
  local hi = f and maxScale(f, key, alone) or Resize.MAX
  return math.min(Resize.least(), hi), hi
end

-- Scales `f` to `s`, its top-left corner held at (left, top) in UIParent units.
-- The corner is kept inside the screen: grown past the right or bottom edge, the window
-- would be drawn clamped inside it with its anchor still outside, and the next drag
-- would stick to that edge until the cursor made up the difference (W.onScreen).
local function place(f, s, left, top)
  f:SetScale(s)
  if left and top then
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local w, h = (f:GetWidth() or 0) * s, (f:GetHeight() or 0) * s
    if sw and sw > 0 then left = math.max(0, math.min(left, sw - w)) end
    if sh and sh > 0 then top = math.min(sh, math.max(top, h)) end
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

-- Sets window `key` to scale `s` (within its bounds) and keeps it.
function Resize.set(key, s)
  s = clampTo(s, Resize.bounds(key))
  apply(key, s)
  store(key, s)
  return s
end

-- Window `key` at its saved scale held within its bounds again (they moved); the saved scale stays.
function Resize.refit(key)
  local f = frames[key]
  if not f then return end
  local s = clampTo(Resize.get(key), Resize.bounds(key))
  if math.abs(s - f:GetScale()) > 1e-9 then apply(key, s) end
end

-- The screen changed (its size, the UI scale): every window fits again.
function Resize.screenChanged()
  for key in pairs(frames) do Resize.refit(key) end
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

-- The drag ends: the scale it was dragged to is kept, held by the window's own bounds, not by
-- the room of a side window open now (that would lower my scale for good); a plain click on
-- the grip (no drag) keeps the saved scale as it is.
local function stopDrag(grip)
  local d = grip.drag
  if not d then return end
  grip:SetScript("OnUpdate", nil)
  grip.drag = nil
  if d.want then store(d.key, d.want) end
end

local function onDown(grip, button)
  local f = frames[grip.key]
  if button == "RightButton" then return Resize.set(grip.key, 1) end
  if button ~= "LeftButton" then return end
  local left, top = corner(f)
  if not left then return end
  local lo, hi = Resize.bounds(grip.key)
  local alo, ahi = Resize.bounds(grip.key, true)
  local x0, y0 = cursor()
  grip.drag = { key = grip.key, left = left, top = top, lo = lo, hi = hi, alo = alo, ahi = ahi, x = x0, y = y0 }
  grip:SetScript("OnUpdate", function()
    local d = grip.drag
    if not d then return end
    local x, y = cursor()
    if not d.want and math.abs(x - d.x) < 0.5 and math.abs(y - d.y) < 0.5 then return end -- not dragged yet
    local s = Resize.dragScale(x, y, d.left, d.top, f:GetWidth(), f:GetHeight())
    d.want = clampTo(s, d.alo, d.ahi) -- kept: the window's own bounds
    s = clampTo(s, d.lo, d.hi) -- shown: on the screen with what is open beside it
    place(f, s, d.left, d.top)
    for _, dlg in ipairs(followers[d.key] or {}) do dlg:SetScale(s) end
  end)
end

-- The dots light up under the mouse: gold, and the backing a shade darker.
local function tint(grip, on)
  local c = Theme.color[on and "cream" or "gold"]
  for _, d in ipairs(grip.dots) do d:SetColorTexture(c[1], c[2], c[3], 1) end
  grip.bg:SetColorTexture(0, 0, 0, on and 0.85 or 0.65)
end

-- The grip's face, drawn with plain textures (no game art to miss): a dark
-- square in the corner and six gold dots in a stair, the corner's own sign
-- for "pull here". Dot (col, row) counts from the bottom-right.
local DOTS = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 0, 2 } }
local DOT, STEP, PAD = 4, 6, 4

local function face(grip)
  local bg = grip:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(grip)
  grip.bg = bg
  grip.dots = {}
  for _, p in ipairs(DOTS) do
    local d = grip:CreateTexture(nil, "OVERLAY")
    d:SetSize(DOT, DOT)
    d:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -(PAD + p[1] * STEP), PAD + p[2] * STEP)
    grip.dots[#grip.dots + 1] = d
  end
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
  face(grip)
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
  f:SetScale(clampTo(Resize.get(key), Resize.bounds(key)))
  return grip
end

-- Dialog `d` takes the scale of window `key` (the one in use), now and whenever it changes.
function Resize.follow(d, key)
  followers[key] = followers[key] or {}
  table.insert(followers[key], d)
  local f = frames[key]
  d:SetScale(f and f:GetScale() or clampTo(Resize.get(key), Resize.bounds(key)))
end

-- The screen's size or the UI scale changed: the windows fit again.
local watch = CreateFrame("Frame")
watch:RegisterEvent("UI_SCALE_CHANGED")
watch:RegisterEvent("DISPLAY_SIZE_CHANGED")
watch:SetScript("OnEvent", function() Resize.screenChanged() end)
