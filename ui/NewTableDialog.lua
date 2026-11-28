local _, ns = ...

-- „Нова маса“: the game (a drop-down of every playable game: a pick opens the dialog
-- on that game, who may sit and the turn time kept), the stake („Само за удоволствие“, and for a game
-- whose engine has `stakes = true` also „Със залог“, which opens a row
-- „Залог на човек“ with a gold and a silver box, Tab between them), who
-- may sit (Всеки от гилдията / Само поканени / Групата ми), the turn time
-- (30/45/60/90 s, 45 preselected) and one row per option of the game's engine
-- (E.options, the default preselected, each value by its name, W.optionText).
-- „Отвори“ → client:openTable (the stake in copper, ns.Stake.fromParts; a bad
-- amount keeps the dialog open with the reason).
local Theme, W, L, C = ns.Theme, ns.W, ns.L, ns.Const
local money = ns.W.money

local D = {
  options = {}, -- option id -> choice group, for the game the dialog is open on
}
ns.NewTableDialog = D

local WIDTH, HEIGHT = 400, 330
local LABEL_X, VALUE_X = 24, 170
local OPTION_H = 34 -- one row per engine option, below the turn row
local RANGE_H = 34 -- the range line of a cash table, under its blinds
local AMOUNT_H = 34 -- the row „Залог на човек“, below the stake row while „Със залог“ is chosen
local CHOICE_GAP, RIGHT_MARGIN = 10, 24

local ACCESS = { "guild", "invite", "group" }

local optionSets = {} -- game id -> {frame, groups = {id -> group}, width}

-- A group of radio options; `group.value` is the chosen one, `group.changed(value)` hears a choice.
local function choiceGroup()
  local group = { options = {} }
  function group.set(value)
    group.value = value
    for _, o in ipairs(group.options) do o.dot:SetShown(o.value == value) end
    if group.changed then group.changed(value) end
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

-- The range line of a cash table: its blinds and what a buy-in may be.
local function rangeLine(engine, set)
  local sk = engine.stakeOf({ blinds = set.groups.blinds.value })
  local HC = ns.HoldemCash
  set.range:SetText(L("dialog.cash.range", money(sk / 2), money(sk), money(HC.MIN_BB * sk), money(HC.MAX_BB * sk)))
end

-- The option rows of game `id` for a table of `mode` ("fun" | "stake": an option with `at` is
-- only in its own mode, as Games.resolve has it), built once, on a layer over the rows below
-- the stake. A cash table (engine.stakeOf) has a line under its blinds: the range.
local function optionSet(id, mode)
  local engine = ns.Games.engine(id)
  local split = false
  for _, o in ipairs(engine and engine.options or {}) do split = split or o.at ~= nil end
  local key = split and (id .. ":" .. mode) or id
  if optionSets[key] then return optionSets[key] end
  local frame = CreateFrame("Frame", nil, D.body)
  frame:SetAllPoints(D.body)
  local options = {}
  for _, o in ipairs(engine and engine.options or {}) do
    if o.at == nil or o.at == mode then options[#options + 1] = o end
  end
  -- An engine with a game clock hides the turn row: its option rows start at that place.
  local timed = engine ~= nil and engine.clock == true
  local set = { frame = frame, groups = {}, width = WIDTH, count = #options - (timed and 1 or 0), extra = 0, id = id }
  local y = timed and D.turnY or D.optionsY
  for _, o in ipairs(options) do
    rowLabel(frame, "opt." .. id .. "." .. o.id, y)
    local group, x = choiceGroup(), VALUE_X
    group.default = o.default
    for _, value in ipairs(o.choices) do
      local choice = addOption(group, frame, W.optionText(id, o.id, value), value, x, y)
      x = x + choice.frame:GetWidth() + CHOICE_GAP
    end
    set.width = math.max(set.width, x - CHOICE_GAP + RIGHT_MARGIN)
    set.groups[o.id] = group
    y = y - OPTION_H
    if mode == "stake" and engine.stakeOf and o.id == "blinds" then
      set.range = W.Label(frame, "dim", "", 12)
      set.range:SetWidth(WIDTH - 2 * LABEL_X)
      set.range:SetWordWrap(true)
      set.range:SetJustifyH("LEFT")
      set.range:SetPoint("TOPLEFT", frame, "TOPLEFT", LABEL_X, y + 4)
      set.extra = RANGE_H
      y = y - RANGE_H
      group.changed = function() rangeLine(engine, set) end
    end
  end
  for _, group in pairs(set.groups) do group.set(group.default) end
  optionSets[key] = set
  return set
end

-- Sizes the dialog and its wood to `w` x `h`.
local function resize(w, h)
  D.frame:SetSize(w, h)
  D.wood:SetTexCoord(0, (w - 8) / Theme.texSize.wood, 0, (h - 8) / Theme.texSize.wood)
  D.error:SetWidth(w - 48)
end

-- The stake row as chosen: „Залог на човек“ and the rows below it AMOUNT_H
-- lower while „Със залог“ is (a cash table has no amount: its stake is its
-- blinds); the option rows of that mode; the dialog as wide as its widest row.
local function layout()
  if not D.gameId then return end
  local chosen = D.stake.value == "gold"
  local engine = ns.Games.engine(D.gameId)
  local gold = chosen and not (engine and engine.stakeOf)
  local set = optionSet(D.gameId, chosen and "stake" or "fun")
  if set ~= D.set then
    for _, other in pairs(optionSets) do other.frame:Hide() end
    if D.set and D.set.id == set.id then -- the choices both modes share carry over
      for id, group in pairs(D.set.groups) do
        if set.groups[id] and group.value ~= nil then set.groups[id].set(group.value) end
      end
    end
    set.frame:Show()
    D.set, D.options, D.rangeText = set, set.groups, set.range
  end
  D.amount:SetShown(gold)
  D.body:ClearAllPoints()
  D.body:SetPoint("TOPLEFT", D.frame, "TOPLEFT", 0, gold and -AMOUNT_H or 0)
  D.body:SetPoint("BOTTOMRIGHT", D.frame, "BOTTOMRIGHT", 0, 0)
  local width = D.set.width
  if D.stake == D.stakeGold then width = math.max(width, D.stakeW) end
  resize(width, HEIGHT + OPTION_H * D.set.count + D.set.extra + (gold and AMOUNT_H or 0))
  if gold then
    D.goldBox:SetFocus()
  else
    D.goldBox:ClearFocus(); D.silverBox:ClearFocus()
  end
end

-- A box's whole number (empty: 0) -> n | nil (not a number).
local function part(box)
  local text = box:GetText():gsub("%s", "")
  if text == "" then return 0 end
  return tonumber(text:match("^%d+$") or "")
end

local function submit()
  local client = ns.client
  if not client then
    D.error:SetText(L(ns.noGuild and "hall.noguild" or "hall.wait"))
    return
  end
  local opt = {}
  for id, group in pairs(D.options) do opt[id] = group.value end
  local stake
  if D.stake.value == "gold" then
    local engine = ns.Games.engine(D.gameId)
    if engine and engine.stakeOf then
      stake = engine.stakeOf(opt) -- a cash table: its stake is its big blind
    else
      local gold, silver = part(D.goldBox), part(D.silverBox)
      stake = gold and silver and ns.Stake.fromParts(gold, silver)
      if not stake then return D.error:SetText(L("dialog.stake.bad")) end
    end
  end
  if stake ~= nil and not ns.StakePanels.ledgerReady(client, function(text) D.error:SetText(text) end) then return end
  local tid, code = client:openTable{ game = D.gameId, access = D.access.value, turn = D.turn.value, opt = opt, stake = stake }
  if tid then
    D.frame:Hide()
  else
    D.error:SetText(L(code == "busy" and "refused.busy" or "dialog.failed"))
  end
end

-- A box for whole gold or silver, `letters` digits at most, and its unit after it.
local function moneyBox(parent, x, y, width, letters, unit)
  local b = CreateFrame("EditBox", nil, parent)
  b:SetSize(width, 22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + 1)
  b:SetAutoFocus(false)
  b:SetNumeric(true)
  b:SetMaxLetters(letters)
  Theme.setFont(b, "ui", 13)
  b:SetTextColor(Theme.rgb("ink"))
  b:SetJustifyH("RIGHT")
  b:SetTextInsets(6, 6, 0, 0)
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(b)
  fill:SetColorTexture(unpack(W.DARK_FILL))
  W.edges(b, 1).setColor(Theme.rgb("brass"))
  b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  b:SetScript("OnEnterPressed", function() submit() end)
  local fs = W.Label(parent, "ui", unit, 13)
  fs:SetPoint("LEFT", b, "RIGHT", 4, 0)
  return b
end

-- The stake row: one group for a game without stakes, one with „Със залог“
-- beside „Само за удоволствие“ (D.stakeW: the dialog width it needs).
local function buildStake(f, y)
  rowLabel(f, "dialog.stake", y)
  D.stakeFun = choiceGroup()
  addOption(D.stakeFun, f, L("dialog.stake.none"), "none", VALUE_X, y, 200)
  D.stakeGold = choiceGroup()
  local fun = addOption(D.stakeGold, f, L("dialog.stake.none"), "none", VALUE_X, y)
  local x = VALUE_X + fun.frame:GetWidth() + CHOICE_GAP
  local gold = addOption(D.stakeGold, f, L("dialog.stake.gold"), "gold", x, y)
  D.stakeW = x + gold.frame:GetWidth() + RIGHT_MARGIN
  D.stakeGold.changed = layout

  local amount = CreateFrame("Frame", nil, f)
  amount:SetAllPoints(f)
  rowLabel(amount, "dialog.stake.amount", y - AMOUNT_H)
  -- the coin icons after the boxes, as the Холдем cash panel shows amounts (W.coinTag)
  D.goldBox = moneyBox(amount, VALUE_X, y - AMOUNT_H, 76, 7, W.coinTag("gold"))
  D.silverBox = moneyBox(amount, VALUE_X + 76 + 24, y - AMOUNT_H, 40, 2, W.coinTag("silver"))
  D.goldBox:SetScript("OnTabPressed", function() D.silverBox:SetFocus() end)
  D.silverBox:SetScript("OnTabPressed", function() D.goldBox:SetFocus() end)
  amount:Hide()
  D.amount = amount
end

local function showGroup(group, on)
  for _, o in ipairs(group.options) do o.frame:SetShown(on) end
end

local PICK_W, PICK_H = 200, 26 -- the game drop-down and each line of its list

-- A line of the game drop-down: the game's picture and its name.
local function gameLine(parent, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, PICK_H)
  b:RegisterForClicks("LeftButtonUp")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(PICK_H - 8, PICK_H - 8)
  b.icon:SetPoint("LEFT", b, "LEFT", 6, 0)
  b.text = W.Label(b, "heading", "", 15)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  return b
end

local function showGame(line, id)
  local path = Theme.gameIcon(id)
  line.icon:SetTexture(path)
  line.icon:SetVertexColor(Theme.rgb("brassLight"))
  line.icon:SetShown(path ~= nil)
  line.text:SetText(W.gameName(id))
end

-- Opens the dialog on game `id` from the drop-down, keeping who may sit and the turn time.
function D.switch(id)
  local access, turn = D.access.value, D.turn.value
  D.open(id)
  if access then D.access.set(access) end
  if turn then D.turn.set(turn) end
end

-- The game row: the chosen game in a box with an arrow; a click opens the list of every
-- playable game under it (the chosen one in gold), a click on one opens the dialog on it.
local function buildPicker(f, y)
  local pick = gameLine(f, PICK_W)
  pick:SetPoint("TOPLEFT", f, "TOPLEFT", VALUE_X, y + 5)
  local fill = pick:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(pick)
  fill:SetColorTexture(unpack(W.DARK_FILL))
  W.edges(pick, 1).setColor(Theme.rgb("brass"))
  local arrow = pick:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(16, 16)
  arrow:SetPoint("RIGHT", pick, "RIGHT", -6, 0)
  arrow:SetTexture(Theme.tex.dropdown)
  arrow:SetVertexColor(Theme.rgb("brassLight"))
  pick.arrow = arrow
  local list = CreateFrame("Frame", nil, pick)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -2)
  list:EnableMouse(true)
  local ground = list:CreateTexture(nil, "BACKGROUND")
  ground:SetAllPoints(list)
  ground:SetColorTexture(unpack(W.SOLID))
  W.edges(list, 1).setColor(Theme.rgb("brass"))
  local items = {}
  for _, g in ipairs(ns.Games.list()) do
    if g.engine then
      local item = gameLine(list, PICK_W - 2)
      item:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1 - #items * PICK_H)
      local hl = item:CreateTexture(nil, "BACKGROUND")
      hl:SetAllPoints(item)
      hl:SetColorTexture(Theme.color.brassLight[1], Theme.color.brassLight[2], Theme.color.brassLight[3], 0.12)
      hl:Hide()
      item:SetScript("OnEnter", function() hl:Show() end)
      item:SetScript("OnLeave", function() hl:Hide() end)
      item.id = g.id
      showGame(item, g.id)
      item:SetScript("OnClick", function()
        list:Hide()
        if g.id ~= D.gameId then D.switch(g.id) end
      end)
      items[#items + 1] = item
    end
  end
  list:SetSize(PICK_W, #items * PICK_H + 2)
  list:Hide()
  pick:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
  W.tooltip(pick, function(t) t:SetText(L("dialog.pickGame")) end)
  D.picker, D.pickList, D.pickItems = pick, list, items
  D.game = pick.text -- the chosen game's name
end

-- The drop-down shows game `id`, and its list marks it in gold.
local function pickerShows(id)
  showGame(D.picker, id)
  for _, item in ipairs(D.pickItems) do
    item.text:SetTextColor(Theme.rgb(item.id == id and "gold" or "ink"))
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
  D.wood = W.chrome(f, WIDTH, HEIGHT).wood

  local title = W.Label(f, "heading", L("dialog.title"), 18)
  title:SetPoint("TOP", f, "TOP", 0, -20)
  W.Close(f):SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -16)

  local y = -60
  rowLabel(f, "dialog.game", y)
  buildPicker(f, y)

  y = y - 34
  buildStake(f, y)

  -- The rows below the stake: AMOUNT_H lower while the amount row shows (layout).
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  D.body = body

  y = y - 34
  rowLabel(body, "dialog.access", y)
  D.access = choiceGroup()
  for i, id in ipairs(ACCESS) do
    addOption(D.access, body, L("access." .. id), id, VALUE_X, y - (i - 1) * 24, 200)
  end

  y = y - 3 * 24 - 12
  D.turnY = y
  D.turnLabel = rowLabel(body, "dialog.turn", y)
  D.turn = choiceGroup()
  for i, s in ipairs(C.TURN_CHOICES) do
    addOption(D.turn, body, L("dialog.seconds", s), s, VALUE_X + (i - 1) * 54, y, 52)
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
  f:SetScript("OnHide", function() D.goldBox:ClearFocus(); D.silverBox:ClearFocus(); D.pickList:Hide() end)
end

-- Opens the dialog for `gameId` with the default choices (for fun).
function D.open(gameId)
  if not D.frame then build() end
  D.gameId = gameId or "ttt"
  pickerShows(D.gameId)
  D.pickList:Hide()
  local engine = ns.Games.engine(D.gameId)
  local staked = engine ~= nil and engine.stakes == true
  showGroup(D.stakeFun, not staked)
  showGroup(D.stakeGold, staked)
  D.stake = staked and D.stakeGold or D.stakeFun
  local timed = engine ~= nil and engine.clock == true
  D.turnLabel:SetShown(not timed) -- the game time stands in for the turn time (D.turn keeps its default)
  showGroup(D.turn, not timed)
  D.goldBox:SetText("")
  D.silverBox:SetText("")
  D.access.set("guild")
  D.turn.set(C.TURN_DEFAULT)
  D.set = nil
  for _, set in pairs(optionSets) do
    set.frame:Hide()
    for _, group in pairs(set.groups) do group.set(group.default) end
  end
  D.stake.set("none")
  layout()
  D.error:SetText("")
  D.frame:Show()
end
