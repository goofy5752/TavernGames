local _, ns = ...

-- The „Настройки“ tab: the language (a change applies after a UI reload, which
-- one button offers), „Зает съм (не приемам покани)“ (db.busy: invitations are
-- declined by the addon), the minimap button on/off, „Звуци“ (db.sound), „Покажи
-- въведението“, and the addon and protocol versions. A second panel (mockup 08,
-- „Облик и тесте“): the theme tiles (db.theme, applied after a reload) and the
-- deck tiles (db.deck, live: Decks.set redraws an open table); hovering a deck tile shows
-- the whole deck (DeckPreview).
local Theme, W, L, C = ns.Theme, ns.W, ns.L, ns.Const

local Settings = { view = nil }
ns.Settings = Settings

local PANEL_W = 520
local PAD = 18
local ROW = 30
-- The second panel, its tiles (three to a row) and their margin.
local LOOKS_X, LOOKS_W = 530, 542
local TILE_W, TILE_H, GAP = 170, 52, 8
local TX = (LOOKS_W - 3 * TILE_W - 2 * GAP) / 2

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

local function heading(parent, key, y, x)
  local fs = W.Label(parent, "heading", L(key), 15)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or PAD, -y)
  return fs
end

-- A heading with its sub line in the second panel -> the y below them.
local function headed(parent, key, y)
  heading(parent, key, y, TX)
  local sub = W.Label(parent, "dim", L(key .. ".sub"), 12)
  sub:SetPoint("TOPLEFT", parent, "TOPLEFT", TX, -(y + 20))
  return y + 42
end

-- A 170 x 52 tile at x, y of `parent` with the title and sub line right of its
-- picture (the text starts `textX` in) -> { frame, fill, ring, title, sub, pressed }.
local function tile(parent, x, y, textX, title, sub, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(TILE_W, TILE_H)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  b:RegisterForClicks("LeftButtonUp")
  local t = { frame = b, pressed = false }
  t.fill = b:CreateTexture(nil, "BACKGROUND")
  t.fill:SetAllPoints(b)
  t.ring = W.edges(b, 2)
  t.title = W.Label(b, "ui", nil, 14)
  t.title:SetWordWrap(false)
  t.title:SetPoint("TOPLEFT", b, "TOPLEFT", textX, -8)
  W.fit(t.title, title, TILE_W - textX - 6)
  t.sub = W.Label(b, "dim", sub, 11)
  t.sub:SetWidth(TILE_W - textX - 6)
  t.sub:SetWordWrap(true)
  t.sub:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -2)
  b:SetScript("OnEnter", function() t.title:SetTextColor(Theme.rgb("gold")) end)
  b:SetScript("OnLeave", function() t.title:SetTextColor(Theme.rgb("ink")) end)
  b:SetScript("OnClick", onClick)
  return t
end

-- The chosen tile is ringed goldHi on a darker fill.
local function press(t, on)
  t.pressed = on
  t.ring.setColor(Theme.rgb(on and "goldHi" or "brassDim"))
  t.fill:SetColorTexture(0, 0, 0, on and 0.6 or 0.4)
end

-- Ticks, tiles and the reload prompt from db: the reload prompt shows while the
-- saved language or theme differs from the one this session runs in (the
-- theme's note when both do). An unknown saved theme or deck reads as the default.
local function sync()
  local v, db = Settings.view, ns.db
  local lang = db.lang or ns.Locale.lang()
  local theme = Theme.resolve(db.theme, ns.Adapter.faction())
  local newLang, newTheme = lang ~= ns.Locale.lang(), theme ~= Theme.skin
  v.langBg:setChecked(lang == "bg")
  v.langEn:setChecked(lang == "en")
  v.reload:SetShown(newLang or newTheme)
  v.reloadNote:SetText(L(newTheme and "settings.reloadTheme" or "settings.reload"))
  v.busy:setChecked(db.busy)
  v.minimap:setChecked(not db.minimap.hide)
  v.sound:setChecked(db.sound ~= false)
  for key, t in pairs(v.themeTiles) do press(t, key == theme) end
  local deck = ns.Decks.key()
  for key, t in pairs(v.deckTiles) do press(t, key == deck) end
end

local function setLanguage(lang)
  ns.db.lang = lang
  sync()
end

-- The second panel: „Облик“ (the two skins) and „Тесте“ (the faction deck,
-- then the ten races three to a row under their caption).
local function buildLooks(page, v)
  local panel = W.Panel(page)
  panel:SetPoint("TOPLEFT", page, "TOPLEFT", LOOKS_X, 0)
  panel:SetSize(LOOKS_W, ns.MainWindow.BODY_H)
  v.looks = panel
  local y = headed(panel, "settings.theme", 14)
  v.themeTiles = {}
  for i, key in ipairs({ "alliance", "horde" }) do
    local name = "settings.theme." .. key
    local t = tile(panel, TX + (i - 1) * (TILE_W + GAP), y, 46, L(name), L(name .. ".sub"), function()
      ns.db.theme = key
      sync()
    end)
    t.crest = W.crest(t.frame, 30, key)
    t.crest:SetPoint("LEFT", t.frame, "LEFT", 8, 0)
    v.themeTiles[key] = t
  end
  y = headed(panel, "settings.deck", y + TILE_H + 16)
  v.deckTiles = {}
  for i, key in ipairs(ns.Decks.ORDER) do
    local x, rowY = TX, y
    if i == 2 then
      local races = W.Label(panel, "dim", L("settings.deck.races"), 12)
      races:SetWidth(LOOKS_W - 2 * TX)
      races:SetWordWrap(true)
      races:SetPoint("TOPLEFT", panel, "TOPLEFT", TX, -(y + TILE_H + 6))
      y = y + TILE_H + 38
    end
    if i > 1 then
      x, rowY = TX + (i - 2) % 3 * (TILE_W + GAP), y + math.floor((i - 2) / 3) * (TILE_H + GAP)
    end
    local race = ns.Decks.RACES[key]
    local sub = race and L("settings.deck.king", race.king) or L("settings.deck.faction")
    local t = tile(panel, x, rowY, 52, ns.Decks.name(key, Theme.skin), sub, function()
      ns.Decks.set(key)
      sync()
    end)
    t.card = ns.Cards.card(t.frame, 0.95)
    t.card.frame:EnableMouse(false) -- the tile takes the click
    t.card.frame:SetPoint("LEFT", t.frame, "LEFT", 7, 0)
    t.card.deck = key
    t.card:set("KS")
    v.deckTiles[key] = t
    -- hovering shows the whole deck to the tile's left, level with it (inside the window)
    local px = x - ns.DeckPreview.W - GAP
    local py = math.max(0, math.min(ns.MainWindow.BODY_H - ns.DeckPreview.H, rowY + (TILE_H - ns.DeckPreview.H) / 2))
    t.frame:HookScript("OnEnter", function()
      v.preview = v.preview or ns.DeckPreview.new(panel)
      ns.DeckPreview.show(v.preview, key, ns.Decks.name(key, Theme.skin), sub, px, py)
    end)
    t.frame:HookScript("OnLeave", function() if v.preview then ns.DeckPreview.hide(v.preview) end end)
  end
  panel:HookScript("OnHide", function() if v.preview then ns.DeckPreview.hide(v.preview) end end)
end

-- „Направено с ♥ от goofy5752“ and two addresses under the versions: the source code and the
-- Discord server. The heart is the red suit of our own cards. The client cannot open a web
-- page, so each address sits in a read-only box: a click selects all of it, Ctrl+C copies it.
local function heart()
  local r, g, b = Theme.rgb("oMark")
  local function byte(x) return math.floor(x * 255 + 0.5) end
  return "|T" .. Theme.tex.suits .. ":0:0:0:-1:128:32:64:96:0:32:" .. byte(r) .. ":" .. byte(g) .. ":" .. byte(b) .. "|t"
end

local function selectAll(self) if self.HighlightText then self:HighlightText() end end

-- One read-only address box at (x, -y), w wide.
local function addressBox(panel, url, x, y, w)
  local box = CreateFrame("EditBox", nil, panel)
  box:SetSize(w, 22)
  box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
  box:SetAutoFocus(false)
  Theme.setFont(box, "ui", 12)
  box:SetTextColor(Theme.rgb("brassLight"))
  box:SetTextInsets(6, 6, 0, 0)
  local fill = box:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(box)
  fill:SetColorTexture(unpack(W.DARK_FILL))
  W.edges(box, 1).setColor(Theme.rgb("brass"))
  box:SetText(url)
  box:SetScript("OnEditFocusGained", selectAll)
  box:SetScript("OnMouseUp", selectAll)
  -- read-only: whatever is typed, the address comes back
  box:SetScript("OnTextChanged", function(self, user)
    if user and self:GetText() ~= url then self:SetText(url); selectAll(self) end
  end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  W.tooltip(box, function(t) t:SetText(L("settings.copyHint")) end)
  return box
end

local function buildCredits(panel, v, y)
  local C = ns.Const
  v.credit = W.Label(panel, "heading", "", 15)
  v.credit:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
  v.credit:SetText(L("settings.madeBy", heart(), W.paint(C.AUTHOR, Theme.rgb("gold"))))
  v.credit:SetTextColor(Theme.rgb("inkDim"))
  y = y + 28
  -- the labels in one column, the boxes lined up after the wider one
  local rows = { { "settings.repo", C.REPO, "repo" }, { "settings.discord", C.DISCORD, "discord" } }
  local labels, lw = {}, 0
  for i, row in ipairs(rows) do
    labels[i] = W.Label(panel, "dim", L(row[1]), 12)
    lw = math.max(lw, W.textWidth(labels[i]))
  end
  for i, row in ipairs(rows) do
    labels[i]:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y + 4))
    v[row[3]] = addressBox(panel, row[2], PAD + lw + 8, y, PANEL_W - 2 * PAD - lw - 8)
    v[row[3] .. "Label"] = labels[i]
    y = y + 28
  end
  v.copyHint = W.Label(panel, "dim", L("settings.copyHint"), 11)
  v.copyHint:SetPoint("TOPLEFT", v.discord, "BOTTOMLEFT", 2, -4)
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
  note:SetWidth(PANEL_W - 2 * PAD - 130)
  note:SetWordWrap(true)
  note:SetPoint("LEFT", reload, "LEFT", 0, 0)
  v.reloadNote = note
  v.reloadButton = W.Button(reload, L("settings.reloadNow"), function() ReloadUI() end, true)
  v.reloadButton:SetSize(120, 22)
  v.reloadButton:SetPoint("RIGHT", reload, "RIGHT", 0, 0)
  v.reload = reload
  y = y + ROW + 14

  v.busy = check(panel, "settings.busy", function(self) ns.db.busy = not self.checked; sync() end)
  v.busy:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW
  v.minimap = check(panel, "settings.minimap", function(self) ns.Minimap.setShown(not self.checked); sync() end)
  v.minimap:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW
  v.sound = check(panel, "settings.sound", function(self) ns.db.sound = not self.checked; sync() end)
  v.sound:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW + 8
  v.introButton = W.Button(panel, L("settings.intro"), function() ns.Intro.start(true) end)
  v.introButton:SetSize(200, 26)
  v.introButton:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + ROW + 20

  heading(panel, "settings.about", y); y = y + ROW
  v.version = W.Label(panel, "dim", L("settings.version", C.VERSION), 12)
  v.version:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + 20
  v.protocol = W.Label(panel, "dim", L("settings.protocol", C.PROTOCOL), 12)
  v.protocol:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y); y = y + 30
  buildCredits(panel, v, y)

  buildLooks(page, v)
  sync()
  page:HookScript("OnShow", sync)
end

ns.MainWindow.addTab("settings", "tab.settings", Settings.build)
