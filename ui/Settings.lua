local _, ns = ...

-- The „Настройки“ tab: the language (a change applies after a UI reload, which
-- one button offers), „Зает съм (не приемам покани)“ (db.busy: invitations are
-- declined by the addon), the minimap button on/off, „Покажи въведението“, and
-- the addon and protocol versions.
local Theme, W, L, C = ns.Theme, ns.W, ns.L, ns.Const

local Settings = { view = nil }
ns.Settings = Settings

local PANEL_W = 520
local PAD = 18
local ROW = 30

-- A tick box with a label; a click calls onClick(check). check.checked is its
-- state, check:setChecked(on) changes it.
local function check(parent, key, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(PANEL_W - 2 * PAD, 22)
  b:RegisterForClicks("LeftButtonUp")
  local box = CreateFrame("Frame", nil, b)
  box:SetSize(18, 18)
  box:SetPoint("LEFT", b, "LEFT", 0, 0)
  local fill = box:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(box)
  fill:SetColorTexture(0, 0, 0, 0.5)
  W.edges(box, 1).setColor(Theme.rgb("brass"))
  local mark = box:CreateTexture(nil, "ARTWORK")
  mark:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
  mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 4)
  mark:SetColorTexture(Theme.rgb("gold"))
  b.mark = mark
  local label = W.Label(b, "ui", L(key), 14)
  label:SetPoint("LEFT", box, "RIGHT", 10, 0)
  b.label = label
  function b:setChecked(on)
    self.checked = on and true or false
    mark:SetShown(self.checked)
  end
  b:setChecked(false)
  b:SetScript("OnEnter", function() label:SetTextColor(Theme.rgb("gold")) end)
  b:SetScript("OnLeave", function() label:SetTextColor(Theme.rgb("ink")) end)
  b:SetScript("OnClick", function(self) onClick(self) end)
  return b
end

local function heading(parent, key, y)
  local fs = W.Label(parent, "heading", L(key), 15)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -y)
  return fs
end

-- Ticks and the reload prompt from db: the reload prompt shows while the saved
-- language differs from the one this session runs in.
local function sync()
  local v, db = Settings.view, ns.db
  local lang = db.lang or ns.Locale.lang()
  v.langBg:setChecked(lang == "bg")
  v.langEn:setChecked(lang == "en")
  v.reload:SetShown(lang ~= ns.Locale.lang())
  v.busy:setChecked(db.busy)
  v.minimap:setChecked(not db.minimap.hide)
end

local function setLanguage(lang)
  ns.db.lang = lang
  sync()
end

function Settings.build(page)
  local v = {}
  Settings.view = v
  local panel = W.Panel(page)
  panel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  panel:SetSize(PANEL_W, ns.MainWindow.BODY_H)
  local y = PAD

  heading(panel, "settings.lang", y); y = y + ROW
  v.langBg = check(panel, "lang.bg", function() setLanguage("bg") end)
  v.langBg:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW
  v.langEn = check(panel, "lang.en", function() setLanguage("en") end)
  v.langEn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW
  local reload = CreateFrame("Frame", nil, panel)
  reload:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
  reload:SetSize(PANEL_W - 2 * PAD, 30)
  local note = W.Label(reload, "dim", L("settings.reload"), 12)
  note:SetWidth(PANEL_W - 2 * PAD - 106)
  note:SetWordWrap(true)
  note:SetPoint("LEFT", reload, "LEFT", 0, 0)
  v.reloadButton = W.Button(reload, L("settings.reloadNow"), function() ReloadUI() end, true)
  v.reloadButton:SetSize(96, 22)
  v.reloadButton:SetPoint("RIGHT", reload, "RIGHT", 0, 0)
  v.reload = reload
  y = y + ROW + 14

  v.busy = check(panel, "settings.busy", function(self) ns.db.busy = not self.checked; sync() end)
  v.busy:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW
  v.minimap = check(panel, "settings.minimap", function(self) ns.Minimap.setShown(not self.checked); sync() end)
  v.minimap:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW + 8
  v.introButton = W.Button(panel, L("settings.intro"), function() ns.Intro.start(true) end)
  v.introButton:SetSize(200, 26)
  v.introButton:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW + 20

  heading(panel, "settings.about", y); y = y + ROW
  v.version = W.Label(panel, "dim", L("settings.version", C.VERSION), 12)
  v.version:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + 20
  v.protocol = W.Label(panel, "dim", L("settings.protocol", C.PROTOCOL), 12)
  v.protocol:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)

  sync()
  page:HookScript("OnShow", sync)
end

ns.MainWindow.addTab("settings", "tab.settings", Settings.build)
