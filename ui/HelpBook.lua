local _, ns = ...

-- The rules book (spec 5.3а): a 640 x 480 sheet of cream paper in the brass
-- frame, titled „Книжка с правила“. The topics of core/Help.lua are listed on
-- the left; the right side shows the chosen topic's blocks: "p" as text,
-- "example" as an indented italic block with a brass rule on its left, "board"
-- as a 3x3 mini board (26 px cells) whose `line` cells are gold, with its text
-- beside it. The footer link „Покажи въведението пак“ starts the intro again.
local Theme, W, L = ns.Theme, ns.W, ns.L

local HelpBook = {
  WIDTH = 640, HEIGHT = 480,
  frame = nil,   -- built on the first open
  current = nil, -- the topic id shown
  topics = {},   -- { id, button } per topic, in Help order
  pages = {},    -- "<lang>:<topic id>" -> built page
  page = nil,    -- the page shown
}
ns.HelpBook = HelpBook

local PAD = 24
local TOP = 62           -- the list and the body start this far below the top edge
local LIST_W = 150
local BODY_X = PAD + LIST_W + 18
local BODY_W = HelpBook.WIDTH - BODY_X - PAD
local BODY_H = HelpBook.HEIGHT - TOP - 56
local TEXT_W = BODY_W - 10 -- room for the scroll thumb
local GAP = 12             -- between blocks
local INDENT = 16          -- an example's text, right of its rule
local CELL, CELL_GAP = 26, 2

local function setColor(fs, token) fs:SetTextColor(Theme.rgb(token)) end

-- A wrapped paper text at (x, -y) of `parent`, `w` wide; returns it and its height.
local function text(parent, style, key, x, y, w)
  local fs = W.Label(parent, style, L(key))
  fs:SetWidth(w)
  fs:SetWordWrap(true)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  return fs, fs:GetStringHeight()
end

local BLOCKS = {}

function BLOCKS.p(content, b, y)
  local fs, h = text(content, "paper", b.key, 0, y, TEXT_W)
  return { kind = "p", text = fs }, h
end

function BLOCKS.example(content, b, y)
  local fs, h = text(content, "paperItalic", b.key, 4 + INDENT, y, TEXT_W - 4 - INDENT)
  local rule = content:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(Theme.rgb("brass"))
  rule:SetWidth(2)
  rule:SetHeight(h)
  rule:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
  return { kind = "example", text = fs, rule = rule }, h
end

function BLOCKS.board(content, b, y)
  local side = 3 * CELL + 2 * CELL_GAP
  local cells, lit = {}, {}
  for _, c in ipairs(b.line or {}) do lit[c] = true end
  for i = 1, 9 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local x, cy = 4 + col * (CELL + CELL_GAP), y + row * (CELL + CELL_GAP)
    local bg = content:CreateTexture(nil, "ARTWORK")
    bg:SetSize(CELL, CELL)
    bg:SetPoint("TOPLEFT", content, "TOPLEFT", x, -cy)
    if lit[i] then
      local r, g, bl = Theme.rgb("gold")
      bg:SetColorTexture(r, g, bl, 1)
    else
      local r, g, bl = Theme.rgb("brassLight")
      bg:SetColorTexture(r, g, bl, 0.35)
    end
    local v = b.board[i]
    local mark = W.Label(content, "paperHeading", v == 1 and L("ttt.x") or v == 2 and L("ttt.o") or "", 16)
    setColor(mark, v == 2 and "oMark" or "red")
    mark:SetJustifyH("CENTER")
    mark:SetPoint("CENTER", bg, "CENTER", 0, 0)
    cells[i] = { bg = bg, mark = mark }
  end
  local tx = 4 + side + 14
  local fs, h = text(content, "paper", b.key, tx, y, TEXT_W - tx)
  return { kind = "board", text = fs, cells = cells }, math.max(side, h)
end

local function buildPage(topic)
  local page = CreateFrame("Frame", nil, HelpBook.frame)
  page:SetPoint("TOPLEFT", HelpBook.frame, "TOPLEFT", BODY_X, -TOP)
  page:SetSize(BODY_W, BODY_H)
  local scroll = W.Scroll(page)
  scroll:SetAllPoints(page)
  scroll:SetSize(BODY_W, BODY_H)
  scroll.content:SetWidth(TEXT_W)
  page.scroll = scroll
  page.blocks = {}
  local y = 0
  for i, b in ipairs(topic.blocks) do
    local block, h = BLOCKS[b.kind](scroll.content, b, y)
    page.blocks[i] = block
    y = y + h + GAP
  end
  scroll:setContentHeight(y)
  return page
end

local function styleTopics()
  for _, t in ipairs(HelpBook.topics) do
    local on = t.id == HelpBook.current
    t.button.bg:SetShown(on)
    setColor(t.button.text, on and "red" or "woodDark")
  end
end

local function showTopic(id)
  local topic = ns.Help.get(id) or ns.Help.get("hall")
  HelpBook.current = topic.id
  local key = ns.Locale.lang() .. ":" .. topic.id
  local page = HelpBook.pages[key]
  if not page then
    page = buildPage(topic)
    HelpBook.pages[key] = page
  end
  for k, other in pairs(HelpBook.pages) do
    if k ~= key then other:Hide() end
  end
  page:Show()
  HelpBook.page = page
  styleTopics()
end

local function topicButton(f, topic, i)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(LIST_W, 26)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TOP - (i - 1) * 30)
  b:RegisterForClicks("LeftButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  local r, g, bl = Theme.rgb("brassLight")
  bg:SetColorTexture(r, g, bl, 0.35)
  b.bg = bg
  local fs = W.Label(b, "paper", L(topic.title), 15)
  fs:SetPoint("LEFT", b, "LEFT", 8, 0)
  b.text = fs
  b:SetScript("OnClick", function() showTopic(topic.id) end)
  return b
end

-- Red text on the paper that acts as a link.
local function link(parent, key, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp")
  local fs = W.Label(b, "paper", L(key))
  setColor(fs, "red")
  fs:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.text = fs
  b:SetSize(fs:GetStringWidth() + 4, 18)
  b:SetScript("OnEnter", function() setColor(fs, "woodDark") end)
  b:SetScript("OnLeave", function() setColor(fs, "red") end)
  b:SetScript("OnClick", onClick)
  return b
end

local function build()
  local f = CreateFrame("Frame", nil, UIParent)
  HelpBook.frame = f
  f:SetSize(HelpBook.WIDTH, HelpBook.HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  HelpBook.paper, HelpBook.border = W.paper(f)

  local title = W.Label(f, "paperHeading", L("book.title"), 20)
  title:SetJustifyH("CENTER")
  title:SetPoint("TOP", f, "TOP", 0, -24)
  HelpBook.title = title
  local close = W.Close(f)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -18)
  HelpBook.close = close

  for i, topic in ipairs(ns.Help.topics) do
    HelpBook.topics[i] = { id = topic.id, button = topicButton(f, topic, i) }
  end
  local divider = f:CreateTexture(nil, "ARTWORK")
  local r, g, b = Theme.rgb("brass")
  divider:SetColorTexture(r, g, b, 0.5)
  divider:SetWidth(1)
  divider:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + LIST_W + 8, -TOP)
  divider:SetHeight(BODY_H)

  HelpBook.introLink = link(f, "book.intro", function()
    if ns.Intro then ns.Intro.start(true) end
  end)
  HelpBook.introLink:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 24)
end

-- Opens the book on `topicId` ("hall" when nil or unknown).
function HelpBook.open(topicId)
  if not HelpBook.frame then build() end
  -- The language may have been chosen since the book was built (first run).
  HelpBook.title:SetText(L("book.title"))
  for i, topic in ipairs(ns.Help.topics) do HelpBook.topics[i].button.text:SetText(L(topic.title)) end
  local intro = HelpBook.introLink
  intro.text:SetText(L("book.intro"))
  intro:SetWidth(intro.text:GetStringWidth() + 4)
  HelpBook.frame:Show()
  showTopic(topicId)
end
