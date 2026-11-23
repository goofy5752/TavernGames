local _, ns = ...

-- The main window (mockup 02): 1100 x 620, wood with a brass frame, movable,
-- closed by Escape or ×. Title bar: „Tavern Games“, the tab buttons, the gold
-- in the bags, ⓘ (topic "hall") and ×. Tabs are added with addTab; a tab's page
-- is built on its first show. Stage 1 tabs: Зала (ui/Hall.lua) and Настройки
-- (ui/Settings.lua).
local Theme, W, L = ns.Theme, ns.W, ns.L

local MainWindow = {
  WIDTH = 1100, HEIGHT = 620,
  order = {},  -- tab ids in the order they were added
  tabs = {},   -- id -> { titleKey, build, button }
  pages = {},  -- id -> built page frame
  current = nil,
}
ns.MainWindow = MainWindow

local EDGE = 12     -- the brass frame band (media/frame.tga has a 12 px band)
local TITLE_H = 34
local INSET = 14
local TITLE_Y = -(EDGE + TITLE_H / 2) -- vertical centre of the title bar from the top

-- Size of the area every tab page fills.
MainWindow.BODY_W = MainWindow.WIDTH - 2 * INSET
MainWindow.BODY_H = MainWindow.HEIGHT - (EDGE + TITLE_H + 4) - INSET

local function inCombat() return InCombatLockdown() and true or false end

local function refreshGold()
  if MainWindow.gold then MainWindow.gold:SetText(ns.Util.money(GetMoney())) end
end

-- Keys go on to the game again after an Escape held them (`keysHeld`).
local function release(f)
  f.keysHeld = nil
  f:SetPropagateKeyboardInput(true)
end

-- Escape closes the window; every other key goes on to the game. Out of combat
-- only: SetPropagateKeyboardInput may be protected in combat, where Escape just
-- closes the window and still reaches the game. The keys held for the Escape are
-- released on the next frame, or at PLAYER_REGEN_DISABLED if combat starts
-- first (the lockdown begins after that event), so they are never held in combat.
local function onKeyDown(self, key)
  if key == "ESCAPE" then
    if not inCombat() then
      self:SetPropagateKeyboardInput(false)
      self.keysHeld = true
      -- Hand the keyboard back once this key press is over.
      C_Timer.After(0, function()
        if self.keysHeld and not inCombat() then release(self) end
      end)
    end
    self:Hide()
  elseif not inCombat() then
    self:SetPropagateKeyboardInput(true)
  end
end

-- The window takes the keyboard only out of combat and always starts by passing
-- keys on, so it can never keep the game from getting them in combat.
local function takeKeyboard(f)
  if f.keyboardReady or inCombat() then return end
  f:SetPropagateKeyboardInput(true)
  f:EnableKeyboard(true)
  f:SetScript("OnKeyDown", onKeyDown)
  f.keyboardReady = true
end

local function onEvent(self, event)
  if event == "PLAYER_MONEY" then
    refreshGold()
  elseif event == "PLAYER_REGEN_ENABLED" then
    takeKeyboard(self)
    release(self)
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Still allowed here: the lockdown starts after this event.
    if self.keyboardReady then release(self) end
  end
end

-- Out of combat the window always starts by passing keys on. Should keys still
-- be held in combat (no PLAYER_REGEN_DISABLED seen), it does not open: it would
-- swallow every key until combat ends.
local function onShow(self)
  if inCombat() then
    if self.keysHeld then return self:Hide() end
  else
    release(self)
  end
  refreshGold()
end

local function styleTab(id)
  local tab = MainWindow.tabs[id]
  local b = tab.button
  if not b then return end
  local on = MainWindow.current == id
  b.bg:SetShown(on)
  b.underline:SetShown(on)
  b.text:SetTextColor(Theme.rgb(on and "brassLight" or "inkDim"))
end

local function layoutTabs()
  local prev
  for _, id in ipairs(MainWindow.order) do
    local tab = MainWindow.tabs[id]
    local b = tab.button
    if not b then
      b = CreateFrame("Button", nil, MainWindow.titleBar)
      b:RegisterForClicks("LeftButtonUp")
      b.bg = b:CreateTexture(nil, "BACKGROUND")
      b.bg:SetAllPoints(b)
      b.bg:SetColorTexture(0, 0, 0, 0.35)
      b.underline = b:CreateTexture(nil, "BORDER")
      b.underline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
      b.underline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
      b.underline:SetHeight(2)
      b.underline:SetColorTexture(Theme.color.brass[1], Theme.color.brass[2], Theme.color.brass[3], 1)
      b.text = W.Label(b, "ui", L(tab.titleKey), 13)
      b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
      b:SetScript("OnClick", function() MainWindow.show(id) end)
      tab.button = b
    end
    b.text:SetText(L(tab.titleKey))
    b:SetSize(math.max(60, b.text:GetStringWidth() + 24), 24)
    b:ClearAllPoints()
    if prev then
      b:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", 2, 0)
    else
      b:SetPoint("BOTTOMLEFT", MainWindow.title, "BOTTOMRIGHT", 24, -5)
    end
    prev = b
    styleTab(id)
  end
end

local function build()
  local f = CreateFrame("Frame", nil, UIParent)
  MainWindow.frame = f
  f:SetSize(MainWindow.WIDTH, MainWindow.HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  takeKeyboard(f)
  ns.Resize.attach(f, "main", 6)

  -- Wood inside the brass frame (tiled, slightly darker than the hall floor).
  local wood = W.tile(f, Theme.tex.wood, Theme.texSize.wood, MainWindow.WIDTH - 8, MainWindow.HEIGHT - 8)
  wood:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  wood:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  wood:SetVertexColor(0.85, 0.85, 0.85)
  W.nine(f, Theme.tex.frame, Theme.texSize.frame, EDGE, EDGE, "BORDER", true)

  -- Title bar: the drag handle, with everything on it above it.
  local bar = CreateFrame("Frame", nil, f)
  MainWindow.titleBar = bar
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -EDGE)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -EDGE, -EDGE)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local title = W.Label(bar, "heading", L("addon.title"), 20)
  title:SetPoint("LEFT", f, "TOPLEFT", EDGE + 10, TITLE_Y)
  MainWindow.title = title

  local close = W.Close(f)
  close:SetFrameLevel(bar:GetFrameLevel() + 2)
  close:SetPoint("RIGHT", f, "TOPRIGHT", -(EDGE + 8), TITLE_Y)
  MainWindow.close = close

  local info = W.Info(f, "hall")
  info:SetFrameLevel(bar:GetFrameLevel() + 2)
  info:SetPoint("RIGHT", close, "LEFT", -10, 0)
  MainWindow.info = info

  local gold = W.Label(bar, "ui", "", 13)
  gold:SetTextColor(Theme.rgb("gold"))
  gold:SetPoint("RIGHT", info, "LEFT", -14, 0)
  MainWindow.gold = gold
  local goldLabel = W.Label(bar, "ui", L("main.gold"), 13)
  goldLabel:SetTextColor(Theme.rgb("inkDim"))
  goldLabel:SetPoint("RIGHT", gold, "LEFT", -4, 0)

  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, -(EDGE + TITLE_H + 4))
  body:SetSize(MainWindow.BODY_W, MainWindow.BODY_H)
  MainWindow.body = body

  f:RegisterEvent("PLAYER_MONEY")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:SetScript("OnEvent", onEvent)
  f:SetScript("OnShow", onShow)
  f:Hide()
  layoutTabs()
end

-- Adds a tab (or replaces the build function of an existing one). `buildFn(page)`
-- fills the page frame the first time the tab is shown.
function MainWindow.addTab(id, titleKey, buildFn)
  local tab = MainWindow.tabs[id]
  if tab then
    tab.titleKey, tab.build = titleKey, buildFn
  else
    MainWindow.tabs[id] = { titleKey = titleKey, build = buildFn }
    MainWindow.order[#MainWindow.order + 1] = id
  end
  if MainWindow.frame then layoutTabs() end
end

local function selectTab(id)
  MainWindow.current = id
  for pid, page in pairs(MainWindow.pages) do
    if pid ~= id then page:Hide() end
  end
  local page = MainWindow.pages[id]
  if not page then
    page = CreateFrame("Frame", nil, MainWindow.body)
    page:SetAllPoints(MainWindow.body)
    MainWindow.pages[id] = page
    MainWindow.tabs[id].build(page)
  end
  page:Show()
  for _, tid in ipairs(MainWindow.order) do styleTab(tid) end
end

-- Opens the window on `tabId` (default: the tab shown last, else the first).
-- On the first run the language choice and the intro (ui/Intro.lua) come
-- first; they open the window when they are done.
function MainWindow.show(tabId)
  if ns.Intro and ns.Intro.pending() then return ns.Intro.firstRun(tabId) end
  if not MainWindow.frame then build() end
  local id = tabId or MainWindow.current or MainWindow.order[1]
  MainWindow.frame:Show()
  if id and MainWindow.tabs[id] then selectTab(id) end
end

function MainWindow.hide()
  if MainWindow.frame then MainWindow.frame:Hide() end
end

function MainWindow.toggle()
  if MainWindow.frame and MainWindow.frame:IsShown() then
    MainWindow.frame:Hide()
  else
    MainWindow.show()
  end
end
