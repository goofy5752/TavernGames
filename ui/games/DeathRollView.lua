local _, ns = ...

-- The Death Roll ladder (mockup 03 `droll`, `.trail`/`.roll`), 512 x 236: at
-- most seven cells left to right with „›“ in brass between them, the start
-- number first (or „…“ once the older rolls no longer fit), every roll in the
-- roller's class colour (Alegreya SC 30, 28, 26, 24, 22, 22, 22 by position; a
-- rolled 1 in the O-mark colour at 34) over the roller's first name or „Ти“,
-- and while the game runs a faint „?“ for the player on turn. A roll the table
-- made (a bot, a timeout) reads „· маса“, a roll I did not see in chat „?“, one
-- I saw with another number a red „!“, each with a tooltip. Under the trail the
-- caption and at most one line about the group. At the bottom: on my turn
-- „Хвърли“ with the range (the only place a server roll is started; disabled
-- while it is under way, with the /roll hint above it when it never showed up
-- in chat), else „Изчакай <Име>…“; once over, who lost, or that nobody did.
local Theme, W, L = ns.Theme, ns.W, ns.L
local Rolls, Party = ns.Rolls, ns.Party
local E = ns.Engines.deathroll

local WIDTH, HEIGHT = 512, 236
local MAX_CELLS = 7
local SIZES = { 30, 28, 26, 24, 22, 22, 22 }
local ONE_SIZE, NEXT_ALPHA, ROLLING_ALPHA = 34, 0.35, 0.5
local TRAIL_TOP, CELL_H, LABEL_H = 10, 60, 16 -- a cell: the number over a label line
local ARROW_SIZE, ARROW_GAP, MIN_GAP = 14, 8, 2 -- „›“ and the room on each side of it
local TEXT_W = 470
local TABLE_SOURCES = { ask = true, timeout = true }
local TIPS = { unseen = "deathroll.tip.unseen", mismatch = "deathroll.tip.mismatch", table = "deathroll.tip.table" }
local GROUP_WHY = { notleader = "deathroll.group.notleader", full = "deathroll.group.full" }

local View = {}

-- The tag of state.rolls[i] as this client sees it (see View.cells).
local function tagOf(s, i, roll)
  local check = Rolls.check(s, i)
  if check == "mismatch" then return "mismatch" end
  if TABLE_SOURCES[roll.src] then return "table" end
  if roll.src == "claim" or check == "unseen" then return "unseen" end
  return nil
end

-- The trail, left to right, at most MAX_CELLS cells: {kind="start", n} when
-- every roll fits beside it, else {kind="more"} and the newest rolls; each roll
-- {kind="roll", n, seat, name, tag} (name nil once that seat left the game, so
-- whoever took the chair since is not named; tag "mismatch" | "table" | "unseen" | nil);
-- while the game runs, last, {kind="next", seat, name} for the player on turn.
function View.cells(s)
  local st, out = s.state, {}
  local playing = not s:gameOver()
  local room = MAX_CELLS - (playing and 2 or 1)
  local rolls, from = st.rolls, 1
  if #rolls <= room then
    out[1] = { kind = "start", n = st.start }
  else
    out[1] = { kind = "more" }
    from = #rolls - room + 1
  end
  for i = from, #rolls do
    local r = rolls[i]
    local name = E.playing(st, r.seat) and s.seats[r.seat] or nil
    out[#out + 1] = { kind = "roll", n = r.n, seat = r.seat, name = name, tag = tagOf(s, i, r) }
  end
  if playing then out[#out + 1] = { kind = "next", seat = st.turn, name = s.seats[st.turn] or nil } end
  return out
end

-- „от следващата игра“ on the plate of a player who sat down after the game began.
function View.seatNote(s, seat)
  local st = s.state
  if not s.seats[seat] or not st or s.status ~= "live" or s:gameOver() then return "" end
  for i = 1, #st.players do
    if st.players[i] == seat then return "" end
  end
  return L("deathroll.nextGame")
end

local function showTip(cell)
  if not cell.tip then return end
  GameTooltip:SetOwner(cell.frame, "ANCHOR_TOP")
  GameTooltip:SetText(L(cell.tip), 1, 1, 1, 1, true)
  GameTooltip:Show()
  cell.tipShown = true
end

local function hideTip(cell)
  if cell.tipShown then GameTooltip:Hide() end
  cell.tipShown = false
end

local function cellWidget(f, i)
  local fr = CreateFrame("Frame", nil, f)
  fr:SetSize(40, CELL_H)
  fr:EnableMouse(true)
  local cell = { frame = fr }
  cell.number = W.Label(fr, "heading", "", SIZES[i])
  cell.number:SetJustifyH("CENTER")
  cell.number:SetPoint("BOTTOM", fr, "BOTTOM", 0, LABEL_H)
  cell.label = W.Label(fr, "dim", "", 11)
  cell.label:SetJustifyH("CENTER")
  cell.label:SetWordWrap(false)
  cell.label:SetPoint("BOTTOM", fr, "BOTTOM", 0, 0)
  fr:SetScript("OnEnter", function() showTip(cell) end)
  fr:SetScript("OnLeave", function() hideTip(cell) end)
  return cell
end

local function centred(f, style, size, width)
  local fs = W.Label(f, style, "", size)
  fs:SetJustifyH("CENTER")
  fs:SetWordWrap(true)
  fs:SetWidth(width)
  return fs
end

function View.build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(WIDTH, HEIGHT)
  f.cells, f.arrows = {}, {}
  for i = 1, MAX_CELLS do f.cells[i] = cellWidget(f, i) end
  for i = 1, MAX_CELLS - 1 do
    local a = W.Label(f, "heading", "›", ARROW_SIZE)
    a:SetTextColor(Theme.rgb("brass"))
    f.arrows[i] = a
  end
  f.caption = centred(f, "dim", 12, TEXT_W)
  f.caption:SetText(L("deathroll.caption"))
  f.caption:SetPoint("TOP", f, "TOP", 0, -(TRAIL_TOP + CELL_H + 10))
  f.group = centred(f, "ui", 12, TEXT_W)
  f.group:SetTextColor(Theme.rgb("oMark"))
  f.group:SetPoint("TOP", f.caption, "BOTTOM", 0, -6)

  f.rollButton = W.Button(f, L("deathroll.roll"), function()
    local client = ns.client
    if client then client:roll() end
  end)
  f.rollButton:SetSize(140, 26)
  f.rollButton:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)
  f.range = centred(f, "dim", 11, TEXT_W)
  f.range:SetPoint("TOP", f.rollButton, "BOTTOM", 0, -3)
  f.stuck = centred(f, "ui", 12, TEXT_W)
  f.stuck:SetTextColor(Theme.rgb("oMark"))
  f.stuck:SetPoint("BOTTOM", f.rollButton, "TOP", 0, 6)
  f.status = centred(f, "heading", 15, TEXT_W)
  f.status:SetPoint("CENTER", f, "BOTTOM", 0, 31)
  return f
end

-- Number text, size, r, g, b and alpha of a cell at position `pos`.
local function numberLook(c, pos, client)
  local size = SIZES[pos]
  if c.kind == "start" then return tostring(c.n), size, Theme.color.ink, 1 end
  if c.kind == "more" then return "…", size, Theme.color.inkDim, 1 end
  if c.kind == "next" then return "?", size, Theme.color.oMark, NEXT_ALPHA end
  if c.n == 1 then return "1", ONE_SIZE, Theme.color.oMark, 1 end
  return tostring(c.n), size, c.name and { W.nameColor(client, c.name) } or Theme.color.ink, 1
end

local function labelText(c, s)
  local text = ""
  if c.kind == "start" then
    text = L("deathroll.startLabel")
  elseif c.kind ~= "more" then
    text = c.name and (c.seat == s.mySeat and L("deathroll.you") or W.firstWord(c.name)) or ""
  end
  if c.tag == "unseen" then
    text = text .. "?"
  elseif c.tag == "mismatch" then
    text = text .. W.paint("!", Theme.rgb("red"))
  elseif c.tag == "table" then
    text = text .. " " .. L("deathroll.tag.table")
  end
  return text
end

-- Draws the cells and returns their widths.
local function drawCells(f, s, cells, client)
  local widths = {}
  for i = 1, MAX_CELLS do
    local cell, c = f.cells[i], cells[i]
    if c then
      local text, size, color, alpha = numberLook(c, i, client)
      cell.number:SetFont(Theme.font.heading, size, "")
      cell.number:SetText(text)
      cell.number:SetTextColor(color[1], color[2], color[3])
      cell.number:SetAlpha(alpha)
      cell.label:SetText(labelText(c, s))
      cell.tip = c.tag and TIPS[c.tag] or nil
      if not cell.tip then hideTip(cell) end
      widths[i] = math.max(cell.number:GetStringWidth(), cell.label:GetStringWidth()) + 4
      cell.frame:SetWidth(widths[i])
      cell.frame:Show()
    else
      cell.tip = nil
      hideTip(cell)
      cell.frame:Hide()
    end
  end
  return widths
end

-- Centres the trail; the room beside each „›“ shrinks when it would not fit.
local function layout(f, widths)
  local n, sum = #widths, 0
  for i = 1, n do sum = sum + widths[i] end
  local arrowW = f.arrows[1]:GetStringWidth()
  local gap = ARROW_GAP
  if n > 1 and sum + (n - 1) * (arrowW + 2 * gap) > WIDTH then
    gap = math.max(MIN_GAP, (WIDTH - sum - (n - 1) * arrowW) / (2 * (n - 1)))
  end
  local x = -(sum + (n - 1) * (arrowW + 2 * gap)) / 2
  local arrowY = -(TRAIL_TOP + CELL_H - LABEL_H - SIZES[1] / 2)
  for i = 1, MAX_CELLS - 1 do f.arrows[i]:SetShown(i < n) end
  for i = 1, n do
    local fr = f.cells[i].frame
    fr:ClearAllPoints()
    fr:SetPoint("TOPLEFT", f, "TOP", x, -TRAIL_TOP)
    x = x + widths[i]
    if i < n then
      local a = f.arrows[i]
      a:ClearAllPoints()
      a:SetPoint("LEFT", f, "TOP", x + gap, arrowY)
      x = x + arrowW + 2 * gap
    end
  end
end

-- Host who cannot invite: why; else who is not in my group; else nil.
-- Names (first words) in class colour inside the line's own colour.
local function groupText(s, client)
  local why = s.role == "host" and s.partyWhy and GROUP_WHY[s.partyWhy]
  if why then return L(why) end
  local missing = Party.missing(s)
  if #missing == 0 then return nil end
  local firsts = {}
  for i = 1, #missing do firsts[i] = W.colored(client, missing[i], W.firstWord(missing[i])) end
  return L("deathroll.group.missing", table.concat(firsts, ", "))
end

-- The line at the bottom when there is no button: whom we wait for, who lost
-- (Session:gameOver and the engine's result), or that nobody did -> text,
-- color (nil: none). The name is in class colour inside the line's colour.
local function statusLine(s, myTurn, client)
  local st = s.state
  if s:gameOver() then
    local result = E.result(st)
    -- A loser who has left since: nobody seated now is named.
    if not result then return (not st.loser) and L("deathroll.void") or nil, Theme.color.inkDim end
    local loser = s.seats[result.losers[1]]
    if loser then return L("deathroll.lost", W.colored(client, loser)), Theme.color.gold end
    return nil
  end
  if s.status ~= "live" or myTurn then return nil end
  local name = s.seats[st.turn]
  if not name then return nil end
  return L("deathroll.waitFor", W.colored(client, name)), Theme.color.ink
end

function View.update(f, s)
  local client, st = ns.client, s.state
  layout(f, drawCells(f, s, View.cells(s), client))

  local group = groupText(s, client)
  f.group:SetText(group or "")
  f.group:SetShown(group ~= nil)

  local myTurn = s.status == "live" and not s:gameOver() and s.mySeat ~= nil and st.turn == s.mySeat
  local rolling = s.rolling ~= nil
  f.rollButton:SetShown(myTurn)
  f.range:SetShown(myTurn)
  f.stuck:SetShown(myTurn and s.rollStuck == true and not rolling)
  if myTurn then
    f.rollButton.text:SetText(L(rolling and "deathroll.rolling" or "deathroll.roll"))
    f.rollButton:SetEnabled(not rolling)
    f.rollButton:SetAlpha(rolling and ROLLING_ALPHA or 1)
    f.range:SetText(L("deathroll.range", st.max))
    f.stuck:SetText(L("deathroll.stuck", st.max))
  end
  local text, color = statusLine(s, myTurn, client)
  f.status:SetText(text or "")
  if color then f.status:SetTextColor(color[1], color[2], color[3]) end
  f.status:SetShown(text ~= nil)
end

ns.TableFrame.registerView(E.id, View)
