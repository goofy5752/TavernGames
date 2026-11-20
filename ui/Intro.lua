local _, ns = ...

-- The first run (spec 5.3а, 6.6). The first time the main window would open
-- while no language is chosen, a dialog „Език / Language“ asks for one
-- („Български“ / „English“), then the intro follows: the four cards of
-- Help.intro (hall -> sitting -> invites -> ⓘ) with „Напред“, „Назад“,
-- „Пропусни“ and a 1/4 counter. Finishing or skipping sets db.introDone and
-- opens the main window. Intro.start(true) shows the cards again at any time.
local W, L = ns.W, ns.L

local Intro = {
  WIDTH = 440, HEIGHT = 240,
  frame = nil, -- the intro card, built on first use
  step = 1,
  tab = nil,   -- the main window tab to open once the first run is over
  lang = {},   -- the language dialog: frame, title, bg, en, border
}
ns.Intro = Intro

local PAD = 26
local LANG_W, LANG_H = 340, 150

local function shown(f) return f ~= nil and f:IsShown() end

local function card(w, h)
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(w, h)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  local _, border = W.paper(f)
  return f, border
end

local function render()
  local steps = ns.Help.intro
  local s = steps[Intro.step]
  Intro.title:SetText(L(s.title))
  Intro.text:SetText(L(s.text))
  Intro.counter:SetText(L("intro.count", Intro.step, #steps))
  Intro.nextButton.text:SetText(L("intro.next"))
  Intro.back.text:SetText(L("intro.back"))
  Intro.skip.text:SetText(L("intro.skip"))
  Intro.back:SetShown(Intro.step > 1)
end

local function finish()
  ns.db.introDone = true
  Intro.frame:Hide()
  local tab = Intro.tab
  Intro.tab = nil
  if ns.MainWindow then ns.MainWindow.show(tab) end
end

local function go(delta)
  local n = Intro.step + delta
  if n > #ns.Help.intro then return finish() end
  Intro.step = math.max(1, n)
  render()
end

local function buildCards()
  local f, border = card(Intro.WIDTH, Intro.HEIGHT)
  Intro.frame, Intro.border = f, border
  local title = W.Label(f, "paperHeading", "", 18)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  Intro.title = title
  local counter = W.Label(f, "paper", "", 13)
  counter:SetJustifyH("RIGHT")
  counter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD - 2)
  Intro.counter = counter
  local text = W.Label(f, "paper", "", 14)
  text:SetWidth(Intro.WIDTH - 2 * PAD)
  text:SetWordWrap(true)
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
  Intro.text = text

  local nextButton = W.Button(f, "", function() go(1) end)
  nextButton:SetSize(96, 24)
  nextButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD - 4)
  Intro.nextButton = nextButton
  local back = W.Button(f, "", function() go(-1) end)
  back:SetSize(96, 24)
  back:SetPoint("RIGHT", nextButton, "LEFT", -8, 0)
  Intro.back = back
  local skip = W.Button(f, "", finish)
  skip:SetSize(96, 24)
  skip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD - 4)
  Intro.skip = skip
  f:Hide()
end

-- Shows the intro from its first card. Unless `force`, only while it has not
-- been seen; returns whether it is shown.
function Intro.start(force)
  if not force and ns.db.introDone then return false end
  if Intro.lang.frame then Intro.lang.frame:Hide() end
  if not Intro.frame then buildCards() end
  Intro.step = 1
  render()
  Intro.frame:Show()
  return true
end

local function choose(lang)
  ns.db.lang = lang
  ns.Locale.set(lang)
  Intro.lang.frame:Hide()
  Intro.start(true)
end

local function buildLanguage()
  local d = Intro.lang
  d.frame, d.border = card(LANG_W, LANG_H)
  d.title = W.Label(d.frame, "paperHeading", L("lang.title"), 18)
  d.title:SetJustifyH("CENTER")
  d.title:SetPoint("TOP", d.frame, "TOP", 0, -PAD - 4)
  d.bg = W.Button(d.frame, L("lang.bg"), function() choose("bg") end)
  d.bg:SetPoint("BOTTOM", d.frame, "BOTTOM", -68, PAD + 6)
  d.en = W.Button(d.frame, L("lang.en"), function() choose("en") end)
  d.en:SetPoint("BOTTOM", d.frame, "BOTTOM", 68, PAD + 6)
end

-- True while the first run is not over: no language chosen or the intro unseen.
function Intro.pending()
  local db = ns.db
  return db ~= nil and (db.lang == nil or not db.introDone)
end

-- The first run, in place of opening the main window on `tabId`; the window
-- opens on that tab once the intro is finished or skipped.
function Intro.firstRun(tabId)
  Intro.tab = tabId
  if ns.db.lang == nil then
    if shown(Intro.frame) then Intro.frame:Hide() end
    if not Intro.lang.frame then buildLanguage() end
    Intro.lang.frame:Show()
  elseif not shown(Intro.frame) then
    Intro.start(false)
  end
end
