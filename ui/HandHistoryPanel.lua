local _, ns = ...

-- „История“: the table's last hands (ui/HandHistory.lua) in a side window beside
-- the table frame (its child: it moves and scales with it, ui/Resize.lua), never
-- over the felt, its cards or its buttons. The button sits in the title bar left of
-- ⓘ at a Белот, Сантасе or Холдем table only and toggles it; it closes when I leave
-- the table or another table's session comes. The newest hand on top, the hand
-- under way growing as it is played, the list scrolled with the mouse wheel (W.Scroll),
-- vertically only. What each hand shows is ui/HandHistoryRows.lua's (mockup 10, „Ново“), its
-- rows of mini cards, names and points ui/HandHistoryDraw.lua's, nothing ever wider than the
-- list: a text shrinks, then wraps. The newest hand is open, the older ones closed to one line
-- until a click on their header. Amounts are the table's own (the Холдем view's View.amount:
-- coins at a cash table, chips at a fun one).
-- TableFrame.render calls H.render(v, s) on every redraw; the rows are rebuilt
-- only while the panel is open and the history changed (its ver), or a header was clicked.
local Theme, W, L = ns.Theme, ns.W, ns.L
local H = ns.HandHistory

local PANEL_W, PAD, TOP = 280, 8, 28
local EDGE = 12 -- the window chrome's band, as the table frame's (TableFrame EDGE)
local SIDE_W = PANEL_W + 2 * EDGE -- the side window beside the table frame

-- Fills the panel with table s's history (H.blocks, laid out by H.layout in its pool); a
-- click on a hand's header opens or closes it and draws again. A fault in it never stops the
-- table's render (as the recorder's, ui/HandHistory.lua): it is noted (H.lastError), the list
-- left empty with its line, and not drawn again until the history changes.
local function fill(panel, s)
  local blocks = H.blocks(s)
  panel.pool:begin()
  local y = H.layout(panel.pool, blocks, panel.textW, function(block)
    H.toggle(block.hand, block.newest)
    H.draw(panel, panel.s)
  end)
  panel.pool:finish()
  panel.used = #blocks
  panel.empty:SetShown(#blocks == 0)
  panel.scroll:setContentHeight(y)
end

function H.draw(panel, s)
  panel.s = s
  local fine, why = pcall(fill, panel, s)
  if not fine then
    H.lastError = why
    pcall(panel.pool.begin, panel.pool) -- nothing half drawn stays
    pcall(panel.pool.finish, panel.pool)
    panel.used = 0
    panel.empty:Show()
    panel.scroll:setContentHeight(0)
  end
  local b = s and H.tables[s.tid]
  panel.ver, panel.tid = b and b.ver, s and s.tid
end

-- The panel: on its own a dark panel (W.Panel); `framed`, a window with the table
-- frame's chrome (wood and the brass edge), its content EDGE inside.
function H.buildPanel(parent, framed)
  local panel, e
  if framed then
    panel, e = CreateFrame("Frame", nil, parent), EDGE
    panel:SetSize(SIDE_W, 300)
    panel.chrome = W.chrome(panel, SIDE_W, 300)
  else
    panel, e = W.Panel(parent), 0
    panel.fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.95)
    panel:SetSize(PANEL_W, 300)
  end
  panel:EnableMouse(true)
  panel:EnableMouseWheel(true)
  panel.title = W.Label(panel, "heading", L("table.history"), 13)
  panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", e + 10, -(e + 8))
  local x = W.Close(panel)
  x:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(e + 4), -(e + 4))
  panel.close = x
  if framed then -- the list on a dark ground with a thin brass edge (mockup 10's window)
    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", e + PAD - 4, -(e + TOP - 4))
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(e + PAD - 4), e + PAD - 4)
    local fill = list:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(list)
    fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.92)
    W.edges(list, 1, "BORDER").setColor(Theme.rgb("brassDim"))
    panel.list = list
  end
  local scroll = W.Scroll(panel)
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", e + PAD, -(e + TOP))
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(e + PAD), e + PAD)
  panel.textW = PANEL_W - 2 * PAD - 6
  scroll.content:SetWidth(panel.textW)
  panel.scroll = scroll
  panel.pool, panel.used = ns.HistoryKit.pool(scroll.content), 0
  panel.empty = W.Label(panel.list or panel, "dim", L("table.historyEmpty"), 11) -- on the list's dark ground, not under it
  panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", e + 10, -(e + TOP + 2))
  panel:Hide()
  return panel
end

-- The button and the panel of the table frame (TableFrame.view v), once: the panel
-- is a window of its own BESIDE the frame (its left edge on the frame's right edge,
-- as tall as the frame), a child of it, so it moves and scales with it
-- (ui/Resize.lua) and never lies over the felt, its cards or its buttons.
local function build(v)
  local f = ns.TableFrame.frame
  local panel = H.buildPanel(f, true)
  panel:SetWidth(SIDE_W)
  W.dragBy(panel, f) -- dragging the side window moves the table with it
  -- open, the window takes room beside the frame: the frame's scale fits both on the screen (ui/Resize.lua)
  ns.Resize.extra.table = function() return panel:IsShown() and SIDE_W or 0 end
  panel:SetScript("OnShow", function()
    ns.Resize.refit("table")
    H.place(v)
    H.draw(panel, ns.client and ns.client.session)
  end)
  panel:SetScript("OnHide", function() ns.Resize.refit("table") end)
  v.history = panel
  for _, handle in ipairs({ f, v.title:GetParent(), panel }) do -- the frame, its title bar: moved, placed again
    handle:HookScript("OnDragStart", function() v.dragging = true end) -- held: a redraw leaves it be
    handle:HookScript("OnDragStop", function() v.dragging = nil; H.place(v) end)
  end
  H.place(v)
  local button = W.GhostButton(f, L("table.history"), "brassLight", function()
    panel:SetShown(not panel:IsShown())
  end)
  button:SetSize(W.textWidth(button.text) + 16, 20)
  button:SetFrameLevel(v.info:GetFrameLevel())
  button:SetPoint("RIGHT", v.info, "LEFT", -8, 0)
  v.historyButton = button
end

-- The side window right of the table frame, or left of it when it would pass the
-- screen's right edge there (the frame is clamped to the screen, the window is not).
-- When it fits on neither side and the window is open, the frame moves left just enough for
-- it on the right: the scale keeps the two within the screen's width (Resize.extra), so it
-- never passes an edge. Closed, the frame stays where it is (no room is taken then).
function H.place(v)
  local f, panel = ns.TableFrame.frame, v.history
  local left, scale = f:GetLeft(), f:GetEffectiveScale()
  local screen = UIParent:GetWidth() * UIParent:GetEffectiveScale()
  local side = "right"
  if left then
    local width, need = f:GetWidth() * scale, SIDE_W * scale
    if (left * scale) + width + need > screen then
      side = "left"
      local top = f:GetTop()
      if left * scale - need < -0.5 and top and panel:IsShown() then -- neither side: the frame moves over
        side = "right"
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.max(0, screen - width - need) / scale, top)
      end
    end
  end
  if panel.side == side then return end
  panel.side = side
  panel:ClearAllPoints()
  if side == "left" then
    panel:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0)
  else
    panel:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
  end
end

-- The title bar's options line (v.meta), never wider than the room between the crest
-- and what stands right of it (the stake after it, then the watcher count, „История“
-- and ⓘ): on one line when it fits, else shrunk, then wrapped (the bar holds two lines).
local function fitMeta(v, kept)
  local bar = ns.TableFrame.frame:GetWidth() - 2 * EDGE
  local left = 8 + W.textWidth(v.title) + 6 + 20 + 6
  local right = 6 + v.info:GetWidth() + 12
  if kept then right = right + 8 + v.historyButton:GetWidth() end
  if v.watchers:IsShown() then right = right + 12 + W.textWidth(v.watchers) end
  if v.stake:IsShown() then right = right + 10 + W.textWidth(v.stake) end
  local text = v.meta:GetText() or ""
  W.fit(v.meta, text, math.huge) -- its own size, to measure
  W.fitWrap(v.meta, text, math.max(1, math.min(W.textWidth(v.meta), bar - left - right))) -- shrunk, then two lines: never cut
end

-- From TableFrame.render: the button at a table whose game keeps a history (the
-- watcher count left of it), else neither; the panel closed at another table; the
-- open panel redrawn when the history changed.
function H.render(v, s)
  if not v.historyButton then build(v) end
  local kept = s ~= nil and H.GAMES[s.game] == true
  if not kept or v.historyTid ~= s.tid then v.history:Hide() end
  v.historyTid = s and s.tid
  v.historyButton:SetShown(kept)
  v.watchers:ClearAllPoints()
  v.watchers:SetPoint("RIGHT", kept and v.historyButton or v.info, "LEFT", -12, 0)
  fitMeta(v, kept)
  if v.history:IsShown() and not v.dragging then H.place(v) end
  local h = ns.TableFrame.frame:GetHeight()
  if v.history.h ~= h then -- the wood tiles, never stretches, as the frame's (TableFrame fit)
    v.history.h = h
    v.history.chrome.wood:SetTexCoord(0, (SIDE_W - 8) / Theme.texSize.wood, 0, (h - 8) / Theme.texSize.wood)
  end
  local b = kept and H.tables[s.tid]
  if v.history:IsShown() and (v.history.tid ~= s.tid or v.history.ver ~= (b and b.ver)) then H.draw(v.history, s) end
end

-- I left my table: its panel goes with it (TableFrame.render draws nothing without a session).
ns.ready(function(client)
  client:on("session", function(s)
    local v = ns.TableFrame.view
    if not s and v and v.history then v.history:Hide(); v.historyTid = nil end
  end)
end)
