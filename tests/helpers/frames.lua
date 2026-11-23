-- Fake WoW widgets for testing ui/: frames, buttons, scroll frames, textures and
-- font strings with the widget methods ui/ uses. A method missing here raises
-- ("attempt to call method ..."), so a misspelt or invented API call fails the
-- test instead of passing silently. No layout engine: GetWidth/GetHeight report
-- only what SetSize/SetWidth/SetHeight set.
local Frames = {}

local Region = {}
Region.__index = Region

function Region:GetObjectType() return self.objectType end
function Region:GetParent() return self.parent end
function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints(rel) self.points = { { "ALL", rel or self.parent } } end
function Region:GetNumPoints() return #self.points end
function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
function Region:GetSize() return self.width, self.height end
-- Scale and screen position: SetScale is kept; GetLeft/GetTop report only what a
-- test sets in .left / .top (there is no layout engine).
function Region:SetScale(s) self.scale = s end
function Region:GetScale() return self.scale or 1 end
function Region:GetEffectiveScale()
  local s, r = 1, self
  while r do s = s * (r.scale or 1); r = r.parent end
  return s
end
function Region:GetLeft() return self.left end
function Region:GetTop() return self.top end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetAlpha() return self.alpha end
function Region:IsShown() return self.shown end
function Region:IsVisible()
  local r = self
  while r do
    if not r.shown then return false end
    r = r.parent
  end
  return true
end

-- OnShow/OnHide on `frame` and on every shown descendant frame, as WoW does
-- when a parent's visibility changes.
local function fire(frame, script)
  local fn = frame.scripts and frame.scripts[script]
  if fn then fn(frame) end
  for _, child in ipairs(frame.children or {}) do
    if child.shown then fire(child, script) end
  end
end

function Region:Show()
  if self.shown then return end
  self.shown = true
  if self:IsVisible() then fire(self, "OnShow") end
end
function Region:Hide()
  if not self.shown then return end
  local was = self:IsVisible()
  self.shown = false
  if was then fire(self, "OnHide") end
end
function Region:SetShown(on) if on then self:Show() else self:Hide() end end

-- Textures
local Texture = setmetatable({}, { __index = Region })
Texture.__index = Texture
function Texture:SetTexture(path, wrapH, wrapV)
  self.texture, self.color, self.atlas, self.wrap = path, nil, nil, { wrapH, wrapV }
  return true
end
function Texture:GetTexture() return self.texture end
function Texture:SetAtlas(name) self.atlas, self.texture, self.color = name, nil, nil end
function Texture:GetAtlas() return self.atlas end
function Texture:SetColorTexture(r, g, b, a) self.color, self.texture, self.atlas = { r, g, b, a or 1 }, nil, nil end
-- A mask texture (Frame:CreateMaskTexture) added to this texture; kept in order in .masks.
function Texture:AddMaskTexture(mask)
  self.masks = self.masks or {}
  self.masks[#self.masks + 1] = mask
end
function Texture:SetTexCoord(...) self.texCoord = { ... } end
function Texture:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
function Texture:GetVertexColor()
  local v = self.vertex or { 1, 1, 1, 1 }
  return v[1], v[2], v[3], v[4]
end
function Texture:SetBlendMode(mode) self.blend = mode end
function Texture:SetDrawLayer(layer, sub) self.layer, self.sublayer = layer, sub end

-- Font strings
local FontString = setmetatable({}, { __index = Region })
FontString.__index = FontString
function FontString:SetFont(path, size, flags)
  assert(type(path) == "string" and type(size) == "number", "SetFont(path, size)")
  self.font = { path, size, flags }
  return true
end
function FontString:GetFont() return self.font[1], self.font[2], self.font[3] end
function FontString:SetText(text)
  assert(text == nil or type(text) == "string" or type(text) == "number", "SetText takes a string")
  if text ~= nil then assert(self.font, "SetText before SetFont") end
  self.text = text and tostring(text) or nil
end
function FontString:GetText() return self.text end
function FontString:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
function FontString:GetTextColor()
  local c = self.textColor or { 1, 1, 1, 1 }
  return c[1], c[2], c[3], c[4]
end
function FontString:SetJustifyH(j) self.justifyH = j end
function FontString:SetJustifyV(j) self.justifyV = j end
function FontString:SetWordWrap(on) self.wordWrap = on end
function FontString:SetShadowOffset(x, y) self.shadow = { x, y } end
function FontString:SetShadowColor(...) self.shadowColor = { ... } end
function FontString:SetDrawLayer(layer, sub) self.layer, self.sublayer = layer, sub end
function FontString:GetStringWidth()
  local _, n = (self.text or ""):gsub("[^\128-\191]", "")
  return n * (self.font and self.font[2] or 12) * 0.5
end
-- Wrapped height: as many lines as the text needs at the width set (one line
-- when no width is set), 1.25 x the font size each.
function FontString:GetStringHeight()
  local size = self.font and self.font[2] or 12
  local lines = 1
  if self.width and self.width > 0 then lines = math.max(1, math.ceil(self:GetStringWidth() / self.width)) end
  return lines * size * 1.25
end

-- Frames
local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame

function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
  local prev = self.scripts[name]
  self.scripts[name] = prev and function(...) prev(...); fn(...) end or fn
end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:EnableMouse(on) self.mouse = on end
function Frame:EnableMouseWheel(on) self.wheel = on end
function Frame:EnableKeyboard(on) self.keyboard = on end
function Frame:SetPropagateKeyboardInput(on) self.propagate = on end
function Frame:SetMovable(on) self.movable = on end
function Frame:RegisterForDrag(...) self.drag = { ... } end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:SetClampedToScreen(on) self.clamped = on end
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:GetFrameStrata() return self.strata or "MEDIUM" end
function Frame:SetFrameLevel(n) self.level = n end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetToplevel(on) self.toplevel = on end
function Frame:SetParent(p)
  local old = self.parent and self.parent.children
  if old then
    for i = #old, 1, -1 do
      if old[i] == self then table.remove(old, i) end
    end
  end
  self.parent = p
  if p and p.children then p.children[#p.children + 1] = self end
end
function Frame:Raise() end

function Frame:CreateTexture(name, layer, template, sub)
  assert(name == nil, "named textures create globals")
  local t = setmetatable({
    objectType = "Texture", parent = self, shown = true, alpha = 1, points = {}, width = 0, height = 0,
    layer = layer, sublayer = sub,
  }, Texture)
  self.regions[#self.regions + 1] = t
  return t
end

-- A mask: a texture region of object type "MaskTexture", with the texture methods.
function Frame:CreateMaskTexture(name, layer, template, sub)
  local m = self:CreateTexture(name, layer, template, sub)
  m.objectType = "MaskTexture"
  return m
end

function Frame:CreateFontString(name, layer, template)
  assert(name == nil, "named font strings create globals")
  local fs = setmetatable({
    objectType = "FontString", parent = self, shown = true, alpha = 1, points = {}, width = 0, height = 0,
    layer = layer,
  }, FontString)
  self.regions[#self.regions + 1] = fs
  return fs
end

-- Buttons
local Button = setmetatable({}, { __index = Frame })
Button.__index = Button
function Button:RegisterForClicks(...) self.clicks = { ... } end
function Button:Enable() self.enabled = true end
function Button:Disable() self.enabled = false end
function Button:SetEnabled(on) self.enabled = on and true or false end
function Button:IsEnabled() return self.enabled end

-- Scroll frames
local ScrollFrame = setmetatable({}, { __index = Frame })
ScrollFrame.__index = ScrollFrame
function ScrollFrame:SetScrollChild(child) self.child = child end
function ScrollFrame:GetScrollChild() return self.child end
function ScrollFrame:SetVerticalScroll(v) self.vscroll = v end
function ScrollFrame:GetVerticalScroll() return self.vscroll or 0 end
function ScrollFrame:GetVerticalScrollRange()
  if not self.child then return 0 end
  return math.max(0, self.child:GetHeight() - self:GetHeight())
end

-- Edit boxes: the text, the font, and the keyboard focus (one box of the
-- sandbox at a time); a test runs OnTabPressed / OnEnterPressed by hand.
local EditBox = setmetatable({}, { __index = Frame })
EditBox.__index = EditBox
function EditBox:SetText(text)
  assert(text == nil or type(text) == "string" or type(text) == "number", "SetText takes a string")
  self.text = text and tostring(text) or ""
end
function EditBox:GetText() return self.text or "" end
function EditBox:SetFont(path, size, flags)
  assert(type(path) == "string" and type(size) == "number", "SetFont(path, size)")
  self.font = { path, size, flags }
  return true
end
function EditBox:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
function EditBox:SetJustifyH(j) self.justifyH = j end
function EditBox:SetTextInsets(...) self.insets = { ... } end
function EditBox:SetAutoFocus(on) self.autoFocus = on end
function EditBox:SetNumeric(on) self.numeric = on end
function EditBox:SetMaxLetters(n) self.maxLetters = n end
function EditBox:SetFocus()
  local f = self.focus
  if f.box and f.box ~= self then f.box.focused = false end
  f.box, self.focused = self, true
end
function EditBox:ClearFocus()
  if self.focus.box == self then self.focus.box = nil end
  self.focused = false
end
function EditBox:HasFocus() return self.focused == true end

local KINDS = { Frame = Frame, Button = Button, ScrollFrame = ScrollFrame, EditBox = EditBox }

-- CreateFrame for the sandbox. `onCreate(frame)` records every frame (for events).
function Frames.factory(G, onCreate)
  local focus = {} -- the edit box with the keyboard focus
  return function(kind, name, parent, template)
    local mt = KINDS[kind or "Frame"]
    assert(mt, "fake CreateFrame: unsupported frame type " .. tostring(kind))
    local f = setmetatable({
      objectType = kind or "Frame", name = name, parent = parent, template = template,
      shown = true, alpha = 1, points = {}, width = 0, height = 0,
      events = {}, scripts = {}, regions = {}, children = {}, enabled = true,
    }, mt)
    if kind == "EditBox" then f.focus = focus end
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    if name then G[name] = f end
    onCreate(f)
    return f
  end
end

-- GameTooltip: records the lines of the last tooltip shown.
function Frames.tooltip(frameFactory)
  local tip = frameFactory("Frame")
  tip.lines = {}
  function tip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
  function tip:SetText(text) self.lines = { text } end
  function tip:AddLine(text) self.lines[#self.lines + 1] = text end
  function tip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. " | " .. b end
  function tip:ClearLines() self.lines = {} end
  return tip
end

-- Every font string (recursively, including child frames) under `frame` whose
-- text contains `needle` and that is visible.
function Frames.visibleTexts(frames, needle)
  local out = {}
  for _, f in ipairs(frames) do
    for _, r in ipairs(f.regions) do
      if r.objectType == "FontString" and r.text and r:IsVisible() and r.text:find(needle, 1, true) then
        out[#out + 1] = r
      end
    end
  end
  return out
end

return Frames
