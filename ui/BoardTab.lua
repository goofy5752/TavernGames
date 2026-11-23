local _, ns = ...

-- The tab „Класация“ (spec 5.6): who wins in the tavern, computed from the ledger
-- (core/LedgerBoard.lua), never stored. Three period buttons (a week, a month, all
-- time) and one game button that cycles „Всички игри“ and each game (Decision G); a head
-- line names the king or queen of the tavern; then one line per player on paper: the
-- place, the name, games, wins, the percent, a bar for the gold net (green to the right
-- of its middle when it is positive, red to the left when negative, at most 60 px a
-- side, with the amount), the favourite game and an honour (a run of three or more wins
-- or losses). A click on a line opens that player's history (ui/HistoryTab.lua) when it
-- exists. The page redraws on "ledger", on the next frame and at most once per 2 s,
-- only while it is shown (J3); the buttons and OnShow redraw at once.
local Theme, W, L = ns.Theme, ns.W, ns.L
local Stats, money = ns.LedgerStats, ns.W.money

local BoardTab = {
  view = nil,
  state = { period = "week", game = nil },
  DARK = 0.55,  -- class colours darkened for the cream paper, as in „Тефтер“
  GAP = 2,      -- seconds between two rebuilds from the ledger's events
}
ns.BoardTab = BoardTab

local BOOK_W, PAD, HEAD_H, ROW_H, ROWS = 760, 14, 90, 26, 14
local BAR, MID = 60, 352 -- the bar's longest side, and its middle from the row's left
local PERIODS = { "week", "month", "all" }
local GREEN, RED, RULE = { 0.27, 0.48, 0.2 }, { 0.66, 0.2, 0.18 }, { 0xd9 / 255, 0xc4 / 255, 0x9a / 255 }
-- Columns: x from the row's left, width, justification.
local COL = {
  place = { 6, 22, "RIGHT" }, name = { 56, 98, "LEFT" }, games = { 156, 40, "RIGHT" }, wins = { 200, 46, "RIGHT" },
  pct = { 250, 40, "RIGHT" }, net = { MID + BAR + 6, 84, "LEFT" }, fav = { MID + BAR + 92, 104, "LEFT" }, honour = { 614, 98, "LEFT" },
}
BoardTab.COL, BoardTab.MID, BoardTab.BAR = COL, MID, BAR

---------------------------------------------------------------------------
-- The lines
---------------------------------------------------------------------------

-- A name in its class colour, darkened for the paper; plain without a known class.
local function paint(client, who)
  local p = who ~= client.env.me and client.presence:get(who)
  local cls = who == client.env.me and client.env.cls or p and p.cls
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  if not (cls and colors and colors[cls]) then return who end
  local r, g, b = ns.classColor(cls)
  return W.paint(who, r * BoardTab.DARK, g * BoardTab.DARK, b * BoardTab.DARK)
end

-- „+5g“, „−3g 20s“ or „0“.
local function signed(copper)
  if copper > 0 then return "+" .. money(copper) end
  if copper < 0 then return "−" .. money(-copper) end
  return "0"
end

local function honour(h)
  if not h then return nil end
  return L(h.kind == "wins" and "board.honour.wins" or "board.honour.losses", h.n)
end

-- {king = text|nil, rows = {{name, who, games, wins, pct, net, bar, fav, honour}}}, the texts ready to draw.
function BoardTab.lines(client, period, game)
  if not (client and client.ledger) then return { rows = {} } end
  local b = Stats.board(client.ledger, { period = period, game = game, now = client.env.epoch() })
  local out = { king = b.king and L(Theme.skin == "horde" and "board.king.horde" or "board.king", paint(client, b.king)) or L("board.king.none"), rows = {} }
  for i, r in ipairs(b.rows) do
    out.rows[i] = {
      name = r.name, who = paint(client, r.name), games = tostring(r.games), wins = tostring(r.wins),
      pct = r.pct and r.pct .. "%" or "–", net = signed(r.net), bar = b.top > 0 and r.net / b.top or 0,
      fav = r.fav and W.gameName(r.fav) or "", honour = honour(r.honour), king = r.name == b.king,
    }
  end
  return out
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function column(f, key, text, size, style)
  local c = COL[key]
  local fs = W.Label(f, style or "paper", text or "", size or 13)
  fs:SetTextColor(Theme.rgb("felt"))
  fs:SetPoint("LEFT", f, "LEFT", c[1], 0)
  fs:SetWidth(c[2])
  fs:SetJustifyH(c[3])
  fs:SetWordWrap(false)
  return fs
end

local function makeRow(r)
  local f = r.frame
  local rule = f:CreateTexture(nil, "BACKGROUND")
  rule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
  rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  r.portrait = ns.Portrait.new(f, ROW_H - 4)
  r.portrait.frame:SetPoint("LEFT", f, "LEFT", COL.place[1] + COL.place[2] + 2, 0)
  r.place, r.name = column(f, "place", "", 12), column(f, "name", "", 14, "paperNote")
  r.games, r.wins, r.pct = column(f, "games"), column(f, "wins"), column(f, "pct")
  r.pos, r.neg = f:CreateTexture(nil, "ARTWORK"), f:CreateTexture(nil, "ARTWORK")
  r.pos:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 1)
  r.neg:SetColorTexture(RED[1], RED[2], RED[3], 1)
  r.pos:SetPoint("LEFT", f, "LEFT", MID, 0)
  r.neg:SetPoint("RIGHT", f, "LEFT", MID, 0)
  r.pos:SetHeight(10); r.neg:SetHeight(10)
  r.net = column(f, "net", "", 12)
  r.fav, r.honour = column(f, "fav", "", 12, "paperNote"), column(f, "honour", "", 11, "paperNote")
  W.tooltip(f, function(tip) if r.line then tip:SetText(L("board.row.tip", r.line.name)) end end)
  f:SetScript("OnMouseUp", function()
    if r.line and ns.HistoryTab then ns.HistoryTab.open(r.line.name) end
  end)
end

local function fillRow(r, line, i)
  r.line = line
  r.place:SetText(i .. ".")
  r.name:SetText(line.who)
  r.portrait:set(ns.Portrait.who(ns.client, line.name))
  r.portrait:turn(line.king)
  r.games:SetText(line.games); r.wins:SetText(line.wins); r.pct:SetText(line.pct)
  r.net:SetText(line.net)
  r.pos:SetShown(line.bar > 0); r.neg:SetShown(line.bar < 0)
  if line.bar > 0 then r.pos:SetWidth(math.max(1, line.bar * BAR)) end
  if line.bar < 0 then r.neg:SetWidth(math.max(1, -line.bar * BAR)) end
  r.fav:SetText(line.fav)
  r.honour:SetText(line.honour or "")
end

-- Redraws the page now (only while it is on screen; OnShow redraws it).
function BoardTab.render()
  local v = BoardTab.view
  if not v or not v.page:IsVisible() then return end
  v.drawn = GetTime()
  local st, client = BoardTab.state, ns.client
  local data = BoardTab.lines(client, st.period, st.game)
  v.list:set(data.rows)
  v.empty:SetShown(#data.rows == 0)
  v.head:SetShown(data.king ~= nil)
  v.head:SetText(data.king or "")
  for _, p in ipairs(PERIODS) do
    local b = v[p]
    if p == st.period then b.text:SetTextColor(Theme.rgb("gold")) else b.text:SetTextColor(Theme.rgb("ink")) end
  end
  v.gameBtn.text:SetText(st.game and W.gameName(st.game) or L("board.games.all"))
end

function BoardTab.setPeriod(p)
  BoardTab.state.period = p
  BoardTab.render()
end

-- „Всички игри“, then each game of the list, then round again.
function BoardTab.nextGame()
  local st, list, nextId = BoardTab.state, ns.Games.list(), nil
  if st.game == nil then
    nextId = list[1] and list[1].id
  else
    for i, g in ipairs(list) do if g.id == st.game then nextId = list[i + 1] and list[i + 1].id end end
  end
  st.game = nextId
  BoardTab.render()
end

-- Redraws on a ledger event: on the next frame, at most once per GAP s, only while shown.
-- When the timer fires the gap is checked again: a click or a hide and show in between
-- already drew the page, and the timer waits out what is left of the gap.
local function arm()
  local v = BoardTab.view
  BoardTab.scheduled = true
  local wait = math.max(0, (v.drawn or -BoardTab.GAP) + BoardTab.GAP - GetTime())
  C_Timer.After(wait, function()
    if not v.page:IsVisible() then BoardTab.scheduled = false; return end
    if GetTime() - (v.drawn or -BoardTab.GAP) < BoardTab.GAP - 1e-6 then return arm() end
    BoardTab.scheduled = false
    BoardTab.render()
  end)
end

function BoardTab.refresh()
  local v = BoardTab.view
  if BoardTab.scheduled or not v or not v.page:IsVisible() then return end
  arm()
end

function BoardTab.build(page)
  local panel = W.Panel(page)
  panel:SetSize(BOOK_W, ns.MainWindow.BODY_H)
  panel:SetPoint("TOP", page, "TOP", 0, 0)
  local title = W.Label(panel, "heading", L("tab.board"), 15)
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -10)
  local v = { page = page, panel = panel }
  local x = PAD
  for _, p in ipairs(PERIODS) do
    v[p] = W.Button(panel, L("board." .. p), function() BoardTab.setPeriod(p) end, true)
    v[p]:SetWidth(84)
    v[p]:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -34)
    x = x + 90
  end
  v.gameBtn = W.Button(panel, L("board.games.all"), function() BoardTab.nextGame() end, true)
  v.gameBtn:SetWidth(160)
  v.gameBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", x + 10, -34)
  v.head = W.Label(panel, "dim", "", 13)
  v.head:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -62)
  local book = CreateFrame("Frame", nil, panel)
  book:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -HEAD_H)
  book:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
  W.paper(book)
  v.seal = W.seal(book, 56)
  local cols = CreateFrame("Frame", nil, book)
  cols:SetSize(BOOK_W - 20 - 2 * PAD, 18)
  cols:SetPoint("TOPLEFT", book, "TOPLEFT", PAD, -10)
  for _, key in ipairs({ "games", "wins", "pct", "fav" }) do column(cols, key, L("board.col." .. key), 11, "paperNote") end
  v.nameHead = column(cols, "name", L("board.col.name"), 11, "paperNote")
  local net = column(cols, "net", L("board.col.net"), 11, "paperNote")
  net:ClearAllPoints()
  net:SetPoint("LEFT", cols, "LEFT", MID - BAR, 0)
  net:SetWidth(2 * BAR)
  net:SetJustifyH("CENTER")
  v.list = ns.BookList.new(book, { width = BOOK_W - 20 - 2 * PAD, rowH = ROW_H, rows = ROWS, make = makeRow, fill = fillRow })
  v.list.scroll:SetPoint("TOPLEFT", book, "TOPLEFT", PAD, -PAD - 18)
  v.empty = W.Label(book, "paperNote", L("board.empty"), 14)
  v.empty:SetPoint("TOPLEFT", book, "TOPLEFT", PAD + 22, -PAD - 28)
  BoardTab.view = v
  -- The ⓘ of the title bar opens this tab's topic while it is shown, the hall's after.
  local function topic(id) if ns.MainWindow.info then ns.MainWindow.info.topic = id end end
  page:SetScript("OnShow", function() topic("board"); BoardTab.render() end)
  page:SetScript("OnHide", function() topic("hall") end)
  topic("board") -- built when first shown: OnShow has not run for it
  BoardTab.render()
end

ns.MainWindow.addTab("board", "tab.board", BoardTab.build)

ns.ready(function(client)
  client:on("ledger", BoardTab.refresh)
end)
