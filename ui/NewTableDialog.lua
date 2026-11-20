local _, ns = ...

-- „Нова маса“: the game, the stake (stage 1: only „Само за удоволствие“), who
-- may sit (Всеки от гилдията / Само поканени / Групата ми) and the turn time
-- (30/45/60/90 s, 45 preselected). „Отвори“ → client:openTable.
local Theme, W, L, C = ns.Theme, ns.W, ns.L, ns.Const

local D = {}
ns.NewTableDialog = D

local WIDTH, HEIGHT, EDGE = 400, 330, 12
local LABEL_X, VALUE_X = 24, 170

local ACCESS = { "guild", "invite", "group" }

-- A group of radio options; `group.value` is the chosen one.
local function choiceGroup()
  local group = { options = {} }
  function group.set(value)
    group.value = value
    for _, o in ipairs(group.options) do o.dot:SetShown(o.value == value) end
  end
  return group
end

local function addOption(group, parent, text, value, x, y, width)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 20)
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

local function submit()
  local client = ns.client
  if not client then
    D.error:SetText(L(ns.noGuild and "hall.noguild" or "hall.wait"))
    return
  end
  local tid, code = client:openTable{ game = D.gameId, access = D.access.value, turn = D.turn.value }
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
  local key = "game." .. D.gameId
  D.game:SetText(L(key))
  D.stake.set("none")
  D.access.set("guild")
  D.turn.set(C.TURN_DEFAULT)
  D.error:SetText("")
  D.frame:Show()
end
