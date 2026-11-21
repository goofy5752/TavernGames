local _, ns = ...

-- The panels of the table frame, split out of ui/TableFrame.lua: the „Покани“
-- list, the „Стани“ question, and the fairness line under the felt (its text and
-- its tooltip): a card table's (ns.Deal), else a dice table's (ns.Dice), else a
-- sealed table's book (ns.Book.status for the line, ns.Book.tip for the
-- tooltip), each read at call time. TableFrame.panels is what the frame calls.
local TableFrame = ns.TableFrame
local Theme, W, L = ns.Theme, ns.W, ns.L

local PICK_W, PICK_ROWS, PICK_ROW_H = 230, 8, 20

local function seated(seats, name)
  for i = 1, #seats do
    if seats[i] == name then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- The „Покани“ list
---------------------------------------------------------------------------

local function pickerRow(picker, i)
  local r = picker.rows[i]
  if r then return r end
  local content = picker.scroll.content
  local b = CreateFrame("Button", nil, content)
  b:SetSize(picker.rowW, PICK_ROW_H)
  b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * PICK_ROW_H)
  b:RegisterForClicks("LeftButtonUp")
  local hl = b:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints(b)
  hl:SetColorTexture(Theme.color.brassLight[1], Theme.color.brassLight[2], Theme.color.brassLight[3], 0.08)
  hl:Hide()
  b:SetScript("OnEnter", function() hl:Show() end)
  b:SetScript("OnLeave", function() hl:Hide() end)
  local name = W.Label(b, "ui", "", 12)
  name:SetWidth(picker.rowW - 4)
  name:SetWordWrap(false)
  name:SetPoint("LEFT", b, "LEFT", 2, 0)
  r = { frame = b, name = name }
  b:SetScript("OnClick", function() TableFrame.invite(r.peerName) end)
  picker.rows[i] = r
  return r
end

-- Everyone in the tavern with a compatible addon who is not seated at my table.
local function renderPicker(v, client, s)
  local picker, n = v.picker, 0
  for _, p in ipairs(client.presence:list()) do
    if not p.incompatible and not seated(s.seats, p.name) then
      n = n + 1
      local r = pickerRow(picker, n)
      r.peerName = p.name
      r.name:SetText(p.name)
      r.name:SetTextColor(ns.classColor(p.cls))
      r.frame:Show()
    end
  end
  for i = n + 1, #picker.rows do picker.rows[i].frame:Hide() end
  picker.scroll:setContentHeight(n * PICK_ROW_H)
  picker.empty:SetShown(n == 0)
end

function TableFrame.togglePicker()
  local v, client = TableFrame.view, ns.client
  local s = client and client.session
  if v.picker:IsShown() or not s then return v.picker:Hide() end
  v.picker:Show()
  renderPicker(v, client, s)
end

-- The text of `key`, or nil when the locale has none (never the raw key).
local function known(key, ...)
  local text = L(key, ...)
  if text ~= key then return text end
  return nil
end

-- The fairness line: Deal.status(s) -> key, arg, arg2; "fair.last" carries
-- the verdict, spelled out. Another seat's complaint about that hand
-- (Deal.claim) follows it as a claim by name. The colour is my own client's
-- finding: red while Deal.alarm(s) (a bad hand or a dealer's second void in
-- this match), else amber with a claim, green on a verified hand.
-- A dice table: Dice.status(s) -> key, tone, arg, arg2, shown in that tone
-- (a name whose seat emptied, nil, as „?“; so in the dice tooltip). With
-- neither, a sealed table's book: Book.status(s) -> key, tone, arg, arg2, drawn
-- as a dice line is.
local function renderFair(v, s)
  local line = v.fairLine
  local key, arg, arg2 = ns.Deal.status(s)
  if not key then
    local tone
    key, tone, arg, arg2 = ns.Dice.status(s)
    if not key then key, tone, arg, arg2 = ns.Book.status(s) end
    line:SetShown(key ~= nil)
    if key then line.text:SetText(L(key, arg or "?", arg2 or "?")); line.text:SetTextColor(Theme.rgb(tone)) end
    return
  end
  line:Show()
  if key == "fair.last" then arg = known("fair.v." .. tostring(arg)) or "?" end
  -- The dealer's seat emptied during the deal (the hand is void soon): no name to show.
  if key == "fair.dealing" and arg == nil then key = "fair.shuffle" end
  local text = arg ~= nil and L(key, arg, arg2) or L(key)
  local claimer = (key == "fair.last" or key == "fair.lapse" or key:sub(1, 9) == "fair.void") and ns.Deal.claim(s) or nil
  if claimer then text = text .. " · " .. L("fair.claim", claimer) end
  line.text:SetText(text)
  local verdict = key == "fair.last" and s.fairLast.verdict
  local amber = claimer or key == "fair.lapse"
  line.text:SetTextColor(Theme.rgb(ns.Deal.alarm(s) and "red" or amber and "gold" or verdict == "ok" and "good" or "inkDim"))
end

-- Tooltip lines {tone, key, arg, arg2}, each in its tone; spell(key, args) may
-- rewrite the arguments first.
local function tipLines(tip, lines, spell)
  for i, t in ipairs(lines) do
    local args = { t[3], t[4] }
    if spell then spell(t[2], args) end
    local text, r, g, b = L(t[2], args[1] or "?", args[2] or "?"), Theme.rgb(t[1])
    if i == 1 then tip:SetText(text, r, g, b, 1, true) else tip:AddLine(text, r, g, b, true) end
  end
end

local function diceWhy(key, args)
  local why = key == "dice.cry" and 2 or key == "dice.tip.bad" and 1
  if why then args[why] = known("dice.why." .. tostring(args[why])) or L("fair.why.unknown") end
end

-- The tooltip of the fairness line: what the line means (why a bad hand
-- failed, a void), another player's claim about that hand, then in red the count of bad
-- hands of this match and every dealer's voided or undealt hands. With no
-- hand closed yet, or a verdict without a text: the line itself. A dice
-- table: the lines of Dice.tip(s), a reason spelled out (dice.why.*). A
-- sealed table's book: the lines of Book.tip(s) as they are (their arguments
-- are counts and names, never a reason to spell out).
local function fairTooltip(tip)
  local s = ns.client and ns.client.session
  if not s then return end
  if not ns.Deal.status(s) then
    if ns.Dice.status(s) then return tipLines(tip, ns.Dice.tip(s), diceWhy) end
    local book = ns.Book.tip(s)
    if book then return tipLines(tip, book) end
  end
  local last, seen = s.fairLast, s.fairSeen
  local text
  if last and last.verdict == "bad" then
    text = L("fair.tip.bad", known("fair.why." .. tostring(last.why)) or L("fair.why.unknown"))
  elseif last then
    text = known("fair.tip." .. tostring(last.lapse and "lapse" or last.verdict))
  end
  local r, g, b = Theme.rgb("ink")
  tip:SetText(text or TableFrame.view.fairLine.text:GetText(), r, g, b, 1, true)
  local key = ns.Deal.status(s)
  local claimer, claim = ns.Deal.claim(s)
  if claimer and (key == "fair.last" or key == "fair.lapse" or (key or ""):sub(1, 9) == "fair.void") then
    r, g, b = Theme.rgb("gold")
    tip:AddLine(L("fair.tip.claim", claimer, known("fair.cry." .. tostring(claim)) or L("fair.why.unknown")), r, g, b, true)
  end
  r, g, b = Theme.rgb("red")
  if seen and seen.bad > 0 then tip:AddLine(L("fair.badCount", seen.bad), r, g, b, true) end
  local names = {}
  for name in pairs(s.fairVoids or {}) do names[#names + 1] = name end
  table.sort(names, ns.Util.byteLess)
  for _, name in ipairs(names) do tip:AddLine(L("fair.voidCount", name, s.fairVoids[name]), r, g, b, true) end
end

local function buildPicker(v, f)
  local picker = W.Panel(f)
  picker.fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.95)
  picker:SetSize(PICK_W, 30 + PICK_ROWS * PICK_ROW_H + 8)
  picker:SetPoint("BOTTOMLEFT", v.inviteButton, "TOPLEFT", 0, 6)
  picker:SetFrameLevel(f:GetFrameLevel() + 20)
  picker:EnableMouse(true)
  W.Label(picker, "heading", L("table.pick"), 13):SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -9)
  local scroll = W.Scroll(picker)
  scroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 8, -30)
  scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -8, 8)
  picker.rowW = PICK_W - 16 - 6
  scroll.content:SetWidth(picker.rowW)
  picker.scroll = scroll
  picker.rows = {}
  picker.empty = W.Label(picker, "dim", L("peers.empty"), 12)
  picker.empty:SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -32)
  picker:Hide()
  v.picker = picker
end

-- The question before „Стани“ costs my team the match: above the button.
local function buildConfirm(v, f)
  local panel = W.Panel(f)
  panel.fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.95)
  panel:SetSize(250, 82)
  panel:SetPoint("BOTTOMLEFT", v.standButton, "TOPLEFT", 0, 6)
  panel:SetFrameLevel(f:GetFrameLevel() + 22)
  panel:EnableMouse(true)
  local text = W.Label(panel, "ui", L("table.standWarn"), 12)
  text:SetWidth(230)
  text:SetJustifyH("LEFT")
  text:SetTextColor(Theme.rgb("gold"))
  text:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
  panel.text = text
  panel.yes = W.Button(panel, L("table.standYes"), function() TableFrame.stand(true) end, true)
  panel.yes:SetSize(100, 22)
  panel.yes:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 9)
  panel.no = W.Button(panel, L("table.standNo"), function() panel:Hide() end, true)
  panel.no:SetSize(110, 22)
  panel.no:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 9)
  panel:Hide()
  v.confirm = panel
end

TableFrame.panels = {
  build = function(v, f) buildPicker(v, f); buildConfirm(v, f) end,
  renderPicker = renderPicker,
  renderFair = renderFair,
  fairTooltip = fairTooltip,
}
