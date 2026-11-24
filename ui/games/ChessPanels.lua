local _, ns = ...

-- The side column of the chess table and its two small dialogs (mockup 09, spec 5.6),
-- all children of the board frame `f` that ui/games/ChessView.lua builds (and so of the
-- scaled table frame). Panels.build(f) / Panels.update(f, s, m) draw what ns.ChessModel
-- returns: the strip of pieces each seat took (small, overlapping, with „+N“ for the lead)
-- under the opponent's plate and over mine (the plates are the table frame's, placed by
-- the view's plateSpots), and between them the move list on parchment in a W.Scroll, two
-- moves a row (number, white, black), the last one marked, scrolled to the end at a new move.
-- Panels.promotion(f, cell, colour, onPick) is the four pieces in a skin frame over the
-- promotion square, Panels.confirmResign(f, onYes) the small „Предай се?“ dialog.
local Theme, W, L = ns.Theme, ns.W, ns.L

local Panels = { X = 520, W = 220, TOP_STRIP = -34, LIST_TOP = -64, LIST_H = 440, STRIP_H = 24, PLATE_H = 26 }
ns.ChessPanels = Panels

local LETTER = { "p", "n", "b", "r", "q", "k" }
local TAKEN_SIZE, TAKEN_STEP, TAKEN_MAX = 22, 11, 15
local ROW_H, NO_W, SAN_W = 18, 30, 76
local SQUARE, PROMO_LEVEL, DIALOG_W, DIALOG_H = 56, 30, 250, 96

-- The texture path of a piece (1..6 white, -1..-6 black) in the applied skin.
function Panels.pieceTex(piece)
  return Theme.chessTex(Theme.skin .. "_" .. (piece > 0 and "w" or "b") .. LETTER[math.abs(piece)])
end

local function strip(f, y)
  local s = { pieces = {} }
  for k = 1, TAKEN_MAX do
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetSize(TAKEN_SIZE, TAKEN_SIZE)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", Panels.X + 4 + (k - 1) * TAKEN_STEP, y - 1)
    t:Hide()
    s.pieces[k] = t
  end
  s.lead = W.Label(f, "ui", "", 13)
  s.lead:SetTextColor(Theme.rgb("goldHi"))
  s.lead:SetJustifyH("RIGHT")
  s.lead:SetPoint("TOPRIGHT", f, "TOPLEFT", Panels.X + Panels.W - 6, y - 4)
  return s
end

local function fillStrip(s, taken, lead)
  for k = 1, TAKEN_MAX do
    local piece = taken[k]
    s.pieces[k]:SetShown(piece ~= nil)
    if piece then s.pieces[k]:SetTexture(Panels.pieceTex(piece)) end
  end
  s.lead:SetText(lead and ("+" .. lead) or "")
end

local function listRow(p, k)
  local row = p.rows[k]
  if row then return row end
  local c = p.scroll.content
  local y = -(k - 1) * ROW_H
  row = { no = W.Label(c, "paper", "", 13), white = W.Label(c, "paper", "", 13), black = W.Label(c, "paper", "", 13) }
  row.mark = c:CreateTexture(nil, "BACKGROUND")
  row.mark:SetColorTexture(Theme.rgb("goldLo"))
  row.mark:SetHeight(ROW_H - 2)
  row.no:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y - 1)
  row.white:SetPoint("TOPLEFT", c, "TOPLEFT", NO_W + 8, y - 1)
  row.black:SetPoint("TOPLEFT", c, "TOPLEFT", NO_W + 8 + SAN_W, y - 1)
  p.rows[k] = row
  return row
end

local function paint(fs, text, last)
  fs:SetText(text or "")
  if last then fs:SetTextColor(Theme.rgb("goldHi")) else fs:SetTextColor(Theme.rgb("woodDark")) end
end

-- Builds the strips and the move list in the board frame `f` (-> f.side).
function Panels.build(f)
  local p = { rows = {} }
  f.side = p
  p.top, p.bottom = strip(f, Panels.TOP_STRIP), strip(f, -(f:GetHeight() - Panels.PLATE_H - 8 - Panels.STRIP_H))
  local book = CreateFrame("Frame", nil, f)
  book:SetSize(Panels.W, Panels.LIST_H)
  book:SetPoint("TOPLEFT", f, "TOPLEFT", Panels.X, Panels.LIST_TOP)
  W.paper(book)
  p.book = book
  p.scroll = W.Scroll(book)
  p.scroll:SetPoint("TOPLEFT", book, "TOPLEFT", 14, -14)
  p.scroll:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -14, 14)
  p.scroll:SetSize(Panels.W - 28, Panels.LIST_H - 28)
  p.scroll.content:SetWidth(Panels.W - 28)
  return p
end

-- The strips and the move list for the model `m` of session `s`.
function Panels.update(f, s, m)
  local p, st = f.side, s.state
  local mine = m.bottom == 1 and st.white or 3 - st.white
  fillStrip(p.bottom, m.taken[mine], m.lead[mine])
  fillStrip(p.top, m.taken[3 - mine], m.lead[3 - mine])
  for k, r in ipairs(m.rows) do
    local row = listRow(p, k)
    paint(row.no, r.no .. ".", false)
    paint(row.white, r.white, r.lastWhite)
    paint(row.black, r.black, r.lastBlack)
    row.mark:ClearAllPoints()
    local lastW, lastB = r.lastWhite, r.lastBlack
    row.mark:SetPoint("TOPLEFT", p.scroll.content, "TOPLEFT", (lastW and NO_W + 6 or NO_W + 6 + SAN_W), -(k - 1) * ROW_H - 1)
    row.mark:SetWidth(SAN_W - 4)
    row.mark:SetShown(lastW or lastB or false)
    for _, fs in ipairs({ row.no, row.white, row.black }) do fs:Show() end
  end
  for k = #m.rows + 1, #p.rows do
    local row = p.rows[k]
    row.no:Hide(); row.white:Hide(); row.black:Hide(); row.mark:Hide()
  end
  local grew = #m.rows ~= (p.shownRows or 0)
  p.shownRows = #m.rows
  p.scroll:setContentHeight(#m.rows * ROW_H + 4)
  if grew then
    p.scroll:SetVerticalScroll(math.max(0, p.scroll.contentHeight - p.scroll:GetHeight()))
    p.scroll:update()
  end
end

-- The picker of the promotion piece over the cell `cell` (of the board `f`: { button, row }):
-- queen, rook, bishop, knight from the top, in a skin frame, `colour` 1 or -1; a click on
-- one calls onPick("q" | "r" | "b" | "n") and closes it, a click anywhere else only closes it.
-- Built once per board, then placed again -> { frame, catcher, buttons = { q, r, b, n }, close }.
function Panels.promotion(f, cell, colour, onPick)
  local pick = f.side.promo
  if not pick then
    local catcher = CreateFrame("Button", nil, f)
    catcher:SetAllPoints(f)
    catcher:SetFrameLevel(f:GetFrameLevel() + PROMO_LEVEL)
    catcher:RegisterForClicks("LeftButtonUp")
    local box = CreateFrame("Frame", nil, f)
    box:SetFrameLevel(f:GetFrameLevel() + PROMO_LEVEL + 2)
    box:SetSize(SQUARE + 8, 4 * SQUARE + 8)
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(box)
    fill:SetColorTexture(Theme.rgb("deep"))
    W.nine(box, Theme.tex.frame, Theme.texSize.frame, 12, 6, "BORDER", true)
    pick = { frame = box, catcher = catcher, buttons = {}, pieces = {} }
    function pick.close() box:Hide(); catcher:Hide() end
    catcher:SetScript("OnClick", pick.close)
    for i, letter in ipairs({ "q", "r", "b", "n" }) do
      local b = CreateFrame("Button", nil, box)
      b:SetSize(SQUARE, SQUARE)
      b:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4 - (i - 1) * SQUARE)
      b:RegisterForClicks("LeftButtonUp")
      local t = b:CreateTexture(nil, "ARTWORK")
      t:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3); t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
      local hi = b:CreateTexture(nil, "BACKGROUND")
      hi:SetAllPoints(b)
      hi:SetColorTexture(Theme.rgb("gold"))
      hi:SetAlpha(i == 1 and 0.25 or 0)
      b:SetScript("OnEnter", function() hi:SetAlpha(0.35) end)
      b:SetScript("OnLeave", function() hi:SetAlpha(i == 1 and 0.25 or 0) end)
      b:SetScript("OnClick", function() pick.close(); pick.onPick(letter) end)
      pick.buttons[letter], pick.pieces[i] = b, t
    end
    f.side.promo = pick
  end
  pick.onPick = onPick
  for i, t in ipairs(pick.pieces) do t:SetTexture(Panels.pieceTex(colour * (6 - i))) end
  local up = cell.row <= 4 -- a cell on the upper half: the picker hangs down from it, else it climbs up
  pick.frame:ClearAllPoints()
  pick.frame:SetPoint(up and "TOPLEFT" or "BOTTOMLEFT", cell.button, up and "TOPLEFT" or "BOTTOMLEFT", -4, up and 4 or -4)
  pick.frame:Show(); pick.catcher:Show()
  return pick
end

-- The dialog „Да се предадеш ли?“ in the middle of the board `f`: „Предавам се“ calls onYes,
-- „Играя нататък“ closes it. Built once per board -> { frame, yes, no, close }.
function Panels.confirmResign(f, onYes)
  local d = f.side.confirm
  if not d then
    local box = CreateFrame("Frame", nil, f)
    box:SetFrameLevel(f:GetFrameLevel() + PROMO_LEVEL)
    box:SetSize(DIALOG_W, DIALOG_H)
    box:SetPoint("CENTER", f, "LEFT", Panels.X / 2 - 4, 0) -- over the board, clear of the plates
    box:EnableMouse(true)
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(box)
    fill:SetColorTexture(Theme.rgb("deep"))
    W.nine(box, Theme.tex.frame, Theme.texSize.frame, 12, 12, "BORDER", true)
    d = { frame = box }
    function d.close() box:Hide() end
    local ask = W.Label(box, "heading", L("chess.resign.ask"), 16)
    ask:SetJustifyH("CENTER")
    ask:SetPoint("TOP", box, "TOP", 0, -20)
    d.yes = W.Button(box, L("chess.resign.yes"), function() d.close(); d.onYes() end, true)
    d.no = W.Button(box, L("chess.resign.no"), d.close, true)
    for _, b in ipairs({ d.yes, d.no }) do b:SetSize(104, 24) end
    d.yes:SetPoint("BOTTOMLEFT", box, "BOTTOM", -108, 16)
    d.no:SetPoint("BOTTOMLEFT", box, "BOTTOM", 4, 16)
    f.side.confirm = d
  end
  d.onYes = onYes
  d.frame:Show()
  return d
end
