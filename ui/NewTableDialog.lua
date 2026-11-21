local _, ns = ...

-- „Нова маса“: the game, the stake (stage 1: only „Само за удоволствие“), who
-- may sit (Всеки от гилдията / Само поканени / Групата ми), the turn time
-- (30/45/60/90 s, 45 preselected) and one row per option of the game's engine
-- (E.options, the default preselected, each value by its name, W.optionText).
-- „Отвори“ → client:openTable.
local Theme, W, L, C = ns.Theme, ns.W, ns.L, ns.Const

local D = {
  options = {}, -- option id -> choice group, for the game the dialog is open on
}
ns.NewTableDialog = D

local WIDTH, HEIGHT, EDGE = 400, 330, 12
local LABEL_X, VALUE_X = 24, 170
local OPTION_H = 34 -- one row per engine option, below the turn row
local CHOICE_GAP, RIGHT_MARGIN = 10, 24

local ACCESS = { "guild", "invite", "group" }

local optionSets = {} -- game id -> {frame, groups = {id -> group}, width}

-- A group of radio options; `group.value` is the chosen one.
local function choiceGroup()
  local group = { options = {} }
  function group.set(value)
    group.value = value
    for _, o in ipairs(group.options) do o.dot:SetShown(o.value == value) end
  end
  return group
end

-- One radio option `width` px wide (nil: as wide as its text).
local function addOption(group, parent, text, value, x, y, width)
  local b = CreateFrame("Button", nil, parent)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:RegisterForClicks("LeftButtonUp")
  local ring = b:CreateTexture(nil, "ARTWORK")
  ring:SetSize(16, 16)
  ring:SetPoint("LEFT", b, "LEFT", 0, 0)
  ring:SetTexture(Theme.tex.ring)
  local dot = b:CreateTexture(nil, "OVERLAY")
  dot:SetSize(8, 8)
  dot:SetPoint("CENTER", ring, "CENTER")
  dot:SetTexture(Theme.tex.chair)
  dot:SetVertexColor(Theme.rgb("gold"))
  local fs = W.Label(b, "ui", text, 13)
  fs:SetPoint("LEFT", ring, "RIGHT", 6, 0)
  b:SetSize(width or (22 + fs:GetStringWidth()), 20)
  local o = { frame = b, text = fs, value = value, dot = dot }
  b:SetScript("OnClick", function() group.set(value) end)
  group.options[#group.options + 1] = o
  return o
end

local function rowLabel(f, key, y)
  local fs = W.Label(f, "dim", L(key), 13)
  fs:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_X, y - 3)
  return fs
end

-- The option rows of game `id` (built once, on a layer over the dialog).
local function optionSet(id)
  if optionSets[id] then return optionSets[id] end
  local engine = ns.Games.engine(id)
  local frame = CreateFrame("Frame", nil, D.frame)
  frame:SetAllPoints(D.frame)
  local options = engine and engine.options or {}
  local set = { frame = frame, groups = {}, width = WIDTH, count = #options }
  for i, o in ipairs(options) do
    local y = D.optionsY - (i - 1) * OPTION_H
    rowLabel(frame, "opt." .. id .. "." .. o.id, y)
    local group, x = choiceGroup(), VALUE_X
    group.default = o.default
    for _, value in ipairs(o.choices) do
      local choice = addOption(group, frame, W.optionText(id, o.id, value), value, x, y)
      x = x + choice.frame:GetWidth() + CHOICE_GAP
    end
    set.width = math.max(set.width, x - CHOICE_GAP + RIGHT_MARGIN)
    set.groups[o.id] = group
  end
  optionSets[id] = set
  return set
end

-- Sizes the dialog and its wood to `w` x `h`.
local function resize(w, h)
  D.frame:SetSize(w, h)
  D.wood:SetTexCoord(0, (w - 8) / Theme.texSize.wood, 0, (h - 8) / Theme.texSize.wood)
  D.error:SetWidth(w - 48)
end

local function submit()
  local client = ns.client
  if not client then
    D.error:SetText(L(ns.noGuild and "hall.noguild" or "hall.wait"))
    return
  end
  local opt = {}
  for id, group in pairs(D.options) do opt[id] = group.value end
  local tid, code = client:openTable{ game = D.gameId, access = D.access.value, turn = D.turn.value, opt = opt }
  if tid then
    D.frame:Hide()
  else
    D.error:SetText(L(code == "busy" and "refused.busy" or "dialog.failed"))
  end
end

local function build()
  local parent = (ns.MainWindow and ns.MainWindow.frame) or UIParent
  local f = CreateFrame("Frame", nil, parent)
  D.frame = f
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", parent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  local wood = W.tile(f, Theme.tex.wood, Theme.texSize.wood, WIDTH - 8, HEIGHT - 8)
  wood:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  wood:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  D.wood = wood
  W.nine(f, Theme.tex.frame, Theme.texSize.frame, EDGE, EDGE, "BORDER", true)

  local title = W.Label(f, "heading", L("dialog.title"), 18)
  title:SetPoint("TOP", f, "TOP", 0, -20)
  W.Close(f):SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -16)

  local y = -60
  rowLabel(f, "dialog.game", y)
  D.game = W.Label(f, "heading", "", 15)
  D.game:SetPoint("TOPLEFT", f, "TOPLEFT", VALUE_X, y - 2)

  y = y - 34
  rowLabel(f, "dialog.stake", y)
  D.stake = choiceGroup()
  addOption(D.stake, f, L("dialog.stake.none"), "none", VALUE_X, y, 200)

  y = y - 34
  rowLabel(f, "dialog.access", y)
  D.access = choiceGroup()
  for i, id in ipairs(ACCESS) do
    addOption(D.access, f, L("access." .. id), id, VALUE_X, y - (i - 1) * 24, 200)
  end

  y = y - 3 * 24 - 12
  rowLabel(f, "dialog.turn", y)
  D.turn = choiceGroup()
  for i, s in ipairs(C.TURN_CHOICES) do
    addOption(D.turn, f, L("dialog.seconds", s), s, VALUE_X + (i - 1) * 54, y, 52)
  end
  D.optionsY = y - OPTION_H

  D.error = W.Label(f, "ui", "", 13)
  D.error:SetTextColor(Theme.rgb("oMark"))
  D.error:SetJustifyH("CENTER")
  D.error:SetWidth(WIDTH - 48)
  D.error:SetWordWrap(true)
  D.error:SetPoint("BOTTOM", f, "BOTTOM", 0, 58)

  D.openButton = W.Button(f, L("dialog.open"), submit)
  D.openButton:SetSize(140, 28)
  D.openButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)
  local cancel = W.Button(f, L("dialog.cancel"), function() f:Hide() end)
  cancel:SetSize(110, 28)
  cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
end

-- Opens the dialog for `gameId` with the default choices.
function D.open(gameId)
  if not D.frame then build() end
  D.gameId = gameId or "ttt"
  D.game:SetText(W.gameName(D.gameId))
  D.stake.set("none")
  D.access.set("guild")
  D.turn.set(C.TURN_DEFAULT)
  for id, set in pairs(optionSets) do set.frame:SetShown(id == D.gameId) end
  local set = optionSet(D.gameId)
  set.frame:Show()
  D.options = set.groups
  for _, group in pairs(D.options) do group.set(group.default) end
  resize(set.width, HEIGHT + OPTION_H * set.count)
  D.error:SetText("")
  D.frame:Show()
end
