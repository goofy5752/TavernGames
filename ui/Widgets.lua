local _, ns = ...

-- The small widget kit of the tavern look: panels, painted buttons, labels in
-- the three Alegreya faces, the ⓘ button, a scroll area and the round close
-- button. Custom methods and fields on the returned frames are lowercase, so
-- they never shadow a WoW widget method.
local Theme, L = ns.Theme, ns.L

local W = {}
ns.W = W

local STYLES = {
  heading = { font = "heading", size = 14, color = "brassLight" },
  ui = { font = "ui", size = 13, color = "ink" },
  dim = { font = "ui", size = 11, color = "inkDim" },
  italic = { font = "italic", size = 13, color = "ink" },
  -- Dark ink on cream paper (the rules book, the intro), without a shadow.
  paper = { font = "ui", size = 13, color = "woodDark", flat = true },
  paperItalic = { font = "italic", size = 13, color = "woodDark", flat = true },
  paperHeading = { font = "heading", size = 18, color = "red", flat = true },
}

-- Nine-slice of the texture at `path` (pixel size `size`, a number or {w, h})
-- whose border band is `margin` px, drawn `edge` px wide on screen. `hollow`
-- leaves the centre out. Returns {pieces, setTexture(path), setColor(r,g,b,a)}.
function W.nine(frame, path, size, margin, edge, layer, hollow)
  local tw, th = size, size
  if type(size) == "table" then tw, th = size[1], size[2] end
  edge = edge or margin
  local u, v = margin / tw, margin / th
  local cols = { { 0, u }, { u, 1 - u }, { 1 - u, 1 } }
  local rows = { { 0, v }, { v, 1 - v }, { 1 - v, 1 } }
  local set, grid = { pieces = {} }, {}
  for r = 1, 3 do
    grid[r] = {}
    for c = 1, 3 do
      if not (hollow and r == 2 and c == 2) then
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetTexture(path)
        t:SetTexCoord(cols[c][1], cols[c][2], rows[r][1], rows[r][2])
        grid[r][c] = t
        set.pieces[#set.pieces + 1] = t
      end
    end
  end
  local tl, tr, bl, br = grid[1][1], grid[1][3], grid[3][1], grid[3][3]
  tl:SetPoint("TOPLEFT", frame, "TOPLEFT"); tl:SetSize(edge, edge)
  tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT"); tr:SetSize(edge, edge)
  bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT"); bl:SetSize(edge, edge)
  br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT"); br:SetSize(edge, edge)
  local top, bottom, left, right = grid[1][2], grid[3][2], grid[2][1], grid[2][3]
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  if grid[2][2] then
    grid[2][2]:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); grid[2][2]:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
  end
  function set.setTexture(p)
    for i = 1, #set.pieces do set.pieces[i]:SetTexture(p) end
  end
  function set.setColor(r, g, b, a)
    for i = 1, #set.pieces do set.pieces[i]:SetVertexColor(r, g, b, a or 1) end
  end
  return set
end

-- A texture tiled over `frame` (or over the area its caller anchors), `w` x `h` px.
function W.tile(frame, path, texSize, w, h, layer)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(path, "REPEAT", "REPEAT")
  t:SetTexCoord(0, w / texSize, 0, h / texSize)
  return t
end

-- A FontString in one of the styles "heading" | "ui" | "dim" | "italic", or
-- "paper" | "paperItalic" | "paperHeading" for text on cream paper.
function W.Label(parent, style, text, size)
  local s = STYLES[style] or STYLES.ui
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Theme.font[s.font], size or s.size, "")
  fs:SetTextColor(Theme.rgb(s.color))
  if s.flat then
    fs:SetShadowOffset(0, 0)
  else
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
  end
  fs:SetJustifyH("LEFT")
  if text then fs:SetText(text) end
  return fs
end

-- `text` wrapped in an inline color code for r, g, b (0..1).
function W.paint(text, r, g, b)
  local function byte(x) return math.floor(x * 255 + 0.5) end
  return string.format("|cff%02x%02x%02x%s|r", byte(r), byte(g), byte(b), text)
end

-- r, g, b of a player's class color (ink when the class is unknown).
function W.nameColor(client, name)
  local cls
  if client and name == client.env.me then
    cls = client.env.cls
  elseif client then
    local p = client.presence:get(name)
    cls = p and p.cls
  end
  return ns.classColor(cls)
end

-- `text` (default: the name) in the player's class color, for inline use.
function W.colored(client, name, text)
  return W.paint(text or name, W.nameColor(client, name))
end

-- The display name of a game id; „Непозната игра“ for an id without a locale
-- entry (the id comes off the wire, so it is never shown as it is).
function W.gameName(id)
  local key = "game." .. tostring(id)
  local s = L(key)
  if s == key then return L("game.unknown") end
  return s
end

-- The display name of the value of a table option: the locale's
-- optv.<game>.<id>.<value> („Без лимит“, „5/10“), else the value as it is.
function W.optionText(game, id, value)
  local key = "optv." .. tostring(game) .. "." .. tostring(id) .. "." .. tostring(value)
  local s = L(key)
  if s == key then return tostring(value) end
  return s
end

-- The first word of a player's name ("Иван Петров" -> "Иван").
function W.firstWord(name) return ns.Names.first(name) end

-- A `px` wide line along each side of `frame`, tinted by setColor(r, g, b, a).
-- Returns {top, bottom, left, right, setColor}.
function W.edges(frame, px, layer)
  local set = {}
  local function line(p1, p2, horizontal)
    local t = frame:CreateTexture(nil, layer or "BORDER")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint(p1, frame, p1); t:SetPoint(p2, frame, p2)
    if horizontal then t:SetHeight(px) else t:SetWidth(px) end
    set[#set + 1] = t
  end
  line("TOPLEFT", "TOPRIGHT", true); line("BOTTOMLEFT", "BOTTOMRIGHT", true)
  line("TOPLEFT", "BOTTOMLEFT", false); line("TOPRIGHT", "BOTTOMRIGHT", false)
  function set.setColor(r, g, b, a)
    for i = 1, 4 do set[i]:SetVertexColor(r, g, b, a or 1) end
  end
  return set
end

-- Cream paper inside the brass frame (media/frame.tga, a 12 px band drawn
-- 12 px wide) over all of `frame`. Returns the paper texture and the nine-slice.
function W.paper(frame)
  local paper = frame:CreateTexture(nil, "BACKGROUND")
  paper:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
  paper:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  paper:SetColorTexture(Theme.rgb("cream"))
  return paper, W.nine(frame, Theme.tex.frame, Theme.texSize.frame, 12, 12, "BORDER", true)
end

-- A dark translucent panel with a thin brass edge (mockup `.panel`).
function W.Panel(parent)
  local f = CreateFrame("Frame", nil, parent)
  local fill = f:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(f)
  fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.55)
  f.fill = fill
  local r, g, b = Theme.rgb("brassDim")
  local function line(p1, p2, horizontal)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r, g, b, 1)
    t:SetPoint(p1, f, p1); t:SetPoint(p2, f, p2)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
  end
  line("TOPLEFT", "TOPRIGHT", true); line("BOTTOMLEFT", "BOTTOMRIGHT", true)
  line("TOPLEFT", "BOTTOMLEFT", false); line("TOPRIGHT", "BOTTOMRIGHT", false)
  return f
end

-- GameTooltip on hover; `fill(tooltip)` adds the lines.
function W.tooltip(frame, fill)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A painted button (red paint, brass rim; lit on hover). `small` makes it 64 x 20.
-- `button.text` is its label.
function W.Button(parent, text, onClick, small)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(small and 64 or 120, small and 20 or 26)
  b:RegisterForClicks("LeftButtonUp")
  local face = W.nine(b, Theme.tex.button, Theme.texSize.button, 6, small and 5 or 6, "BACKGROUND")
  b.face = face
  local fs = W.Label(b, "heading", text, small and 12 or 14)
  fs:SetTextColor(Theme.rgb("ink"))
  fs:SetJustifyH("CENTER")
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text = fs
  b:SetScript("OnEnter", function() face.setTexture(Theme.tex.button_hi) end)
  b:SetScript("OnLeave", function() face.setTexture(Theme.tex.button) end)
  b:SetScript("OnMouseDown", function() fs:SetPoint("CENTER", b, "CENTER", 1, -1) end)
  b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", b, "CENTER", 0, 0) end)
  b:SetScript("OnClick", function(self, mouse) if onClick then onClick(self, mouse) end end)
  return b
end

-- The dark translucent fill of the ghost button and of the card tables'
-- bubbles, r, g, b, a.
W.DARK_FILL = { 32 / 255, 16 / 255, 8 / 255, 0.85 }

-- The rim of a mockup button: gold under the mouse and while `b.lit`, else brass.
local function litRim(b)
  b:SetScript("OnEnter", function() b.edges.setColor(Theme.rgb("gold")) end)
  b:SetScript("OnLeave", function() b.edges.setColor(Theme.rgb(b.lit and "gold" or "brass")) end)
end

local function mockButton(parent, text, color, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(124, 24)
  b:RegisterForClicks("LeftButtonUp")
  b.fill = b:CreateTexture(nil, "BACKGROUND")
  b.fill:SetAllPoints(b)
  local fs = W.Label(b, "heading", text, 13)
  fs:SetTextColor(Theme.rgb(color))
  fs:SetJustifyH("CENTER")
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text = fs
  b.lit = false
  b:SetScript("OnClick", function() onClick() end)
  return b
end

-- The gold button of the mockups (plain `.btn`), 124 x 24: a gold face with
-- a darker lip at its lower edge and a dark label; `button.text`, `.fill`,
-- `.lip`, `.edges`. Its rim lights up while `button.lit` or under the mouse.
local GOLD_FACE, GOLD_LIP = { 0xdc / 255, 0xb4 / 255, 0x67 / 255 }, { 0x8a / 255, 0x5a / 255, 0x2b / 255 }
function W.GoldButton(parent, text, onClick)
  local b = mockButton(parent, text, "woodDark", onClick)
  b.fill:SetColorTexture(GOLD_FACE[1], GOLD_FACE[2], GOLD_FACE[3], 1)
  b.lip = b:CreateTexture(nil, "BORDER")
  b.lip:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.lip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.lip:SetHeight(2)
  b.lip:SetColorTexture(GOLD_LIP[1], GOLD_LIP[2], GOLD_LIP[3], 1)
  b.edges = W.edges(b, 1, "ARTWORK") -- above the lip
  b.edges.setColor(Theme.rgb("brass"))
  litRim(b)
  return b
end

-- The brass-rimmed dark button of the mockups (`.btn.ghost`), 124 x 24, its
-- label in the colour token `color`; `button.text`, `.fill`, `.edges`. Its
-- rim lights up while `button.lit` or under the mouse.
function W.GhostButton(parent, text, color, onClick)
  local b = mockButton(parent, text, color, onClick)
  b.fill:SetColorTexture(unpack(W.DARK_FILL))
  b.edges = W.edges(b, 1)
  b.edges.setColor(Theme.rgb("brass"))
  litRim(b)
  return b
end

-- The ⓘ button: opens the rules book on `topicId`.
function W.Info(parent, topicId)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 18)
  b:RegisterForClicks("LeftButtonUp")
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints(b)
  t:SetTexture(Theme.tex.info)
  b.icon = t
  b.topic = topicId
  W.tooltip(b, function(tip) tip:SetText(L("book.title")) end)
  b:HookScript("OnEnter", function() t:SetVertexColor(Theme.rgb("gold")) end)
  b:HookScript("OnLeave", function() t:SetVertexColor(1, 1, 1) end)
  b:SetScript("OnClick", function(self)
    if ns.HelpBook then ns.HelpBook.open(self.topic) end
  end)
  return b
end

-- A mouse-wheel scroll area. `scroll.content` is the child to fill (the caller
-- sets its width); `scroll:setContentHeight(h)` after filling it.
function W.Scroll(parent)
  local s = CreateFrame("ScrollFrame", nil, parent)
  local content = CreateFrame("Frame", nil, s)
  content:SetSize(1, 1)
  s:SetScrollChild(content)
  s.content = content
  s.contentHeight = 0
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetWidth(3)
  thumb:SetColorTexture(Theme.color.brass[1], Theme.color.brass[2], Theme.color.brass[3], 0.6)
  thumb:Hide()
  s.thumb = thumb

  local function range()
    return math.max(0, s.contentHeight - (s:GetHeight() or 0))
  end
  function s:update()
    local r, h = range(), self:GetHeight() or 0
    local v = math.min(self:GetVerticalScroll(), r)
    self:SetVerticalScroll(v)
    if r <= 0 or h <= 0 then return thumb:Hide() end
    local th = math.max(16, h * h / self.contentHeight)
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(h - th) * v / r)
    thumb:Show()
  end
  function s:setContentHeight(h)
    self.contentHeight = h
    content:SetHeight(math.max(1, h))
    self:update()
  end
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, delta)
    self:SetVerticalScroll(math.max(0, math.min(range(), self:GetVerticalScroll() - delta * 40)))
    self:update()
  end)
  s:SetScript("OnSizeChanged", function(self) self:update() end)
  return s
end

-- The round close button (×) that hides `parent`.
function W.Close(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(20, 20)
  b:RegisterForClicks("LeftButtonUp")
  local disc = b:CreateTexture(nil, "BACKGROUND")
  disc:SetAllPoints(b)
  disc:SetTexture(Theme.tex.chair)
  disc:SetVertexColor(Theme.rgb("knob"))
  local x = W.Label(b, "heading", "×", 16)
  x:SetJustifyH("CENTER")
  x:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.text = x
  b:SetScript("OnEnter", function() x:SetTextColor(Theme.rgb("gold")) end)
  b:SetScript("OnLeave", function() x:SetTextColor(Theme.rgb("brassLight")) end)
  b:SetScript("OnClick", function() parent:Hide() end)
  return b
end
