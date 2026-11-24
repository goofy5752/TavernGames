local Wow = require("wow")

-- The tab „Класация“ (ui/BoardTab.lua) and its virtual list (ui/BookList.lua).
local ME, B, C = "Иван Петров", "Мария Стоянова", "Тодор Ангелов"

local function readyWow(guild, faction)
  local w = Wow.new{ ui = true }
  if faction then w.faction = faction end
  w.inGuild = guild ~= false
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  w.ns.MainWindow.show()
  w:advance(0)
  return w
end

local function plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function settle(w) w:advance(1); w:advance(0) end

-- An entry of kind k by `author`: mine through the ledger's own maker, another's as if it came live.
local seqs = setmetatable({}, { __mode = "k" })
local function entry(w, author, k, fields)
  if author == ME then
    w.ns.client.ledgerNet:make(k, fields)
  else
    w:member(author)
    seqs[w] = seqs[w] or {}
    local n = (seqs[w][author] or 0) + 1
    seqs[w][author] = n
    local e = { i = author .. ":" .. n, k = k, at = w.G.GetServerTime() }
    for key, value in pairs(fields) do e[key] = value end
    w.ns.client.ledgerNet:take(e, author, true)
  end
  settle(w)
end

local games = 0
local function gid() games = games + 1; return ME .. "#1/" .. games end
-- ME hosts a fun game of g: names n, winners w, losers l.
local function result(w, g, n, win, lose)
  entry(w, ME, "R", { gid = gid(), g = g or "ttt", n = n or { ME, B }, w = win or { 1 }, l = lose or { 2 } })
end
-- f owes t c copper, on f's own word (confirmed).
local function owe(w, f, t, c, g)
  w:member(f); w:member(t)
  entry(w, f, "D", { gid = gid(), g = g or "ttt", f = f, t = t, c = c, why = "lost" })
end


-- Never cut: font string fs shrinks to 9 at the least, a word is never wider than its box, and it
-- stays inside a row of `rowH`.
local function fits(fs, rowH)
  ok(select(2, fs:GetFont()) >= 9 - 0.01, "smaller than readable: " .. tostring(fs:GetText()))
  ok(fs:GetUnboundedStringWidth() <= fs:GetWidth() + 0.01 or fs.wordWrap, "cut on one line: " .. tostring(fs:GetText()))
  ok(fs:GetStringHeight() <= rowH, "taller than its row: " .. tostring(fs:GetText()))
  for word in plain(fs:GetText()):gmatch("%S+") do
    local probe = fs.parent:CreateFontString(nil, "OVERLAY"); probe:SetFont(fs:GetFont()); probe:SetText(word)
    ok(probe:GetUnboundedStringWidth() <= fs:GetWidth() + 0.01, "a word cut: " .. word)
  end
end

local function Bd(w) return w.ns.BoardTab end
local function open(w) w.ns.MainWindow.show("board"); w:advance(0); return Bd(w).view end
local function shown(w)
  local out = {}
  for _, r in ipairs(Bd(w).view.list.rows) do
    if r.frame:IsVisible() then out[#out + 1] = r end
  end
  table.sort(out, function(p, q) return p.index < q.index end)
  return out
end

describe("ui: the tab „Класация“", function()
  it("the rows read games, wins, percent, net and favourite", function()
    local w = readyWow()
    result(w); result(w)
    owe(w, B, ME, 50000)
    local rows = Bd(w).lines(w.ns.client, "all", nil).rows
    eq(#rows, 2)
    local r = rows[1]
    eq(plain(r.who), ME); eq(r.name, ME); eq(r.games, "2"); eq(r.wins, "2"); eq(r.pct, "100%")
    eq(plain(r.net), w:coins("+5g")); eq(r.bar, 1); eq(r.fav, "Морски шах")
    eq(rows[2].name, B); eq(plain(rows[2].net), w:coins("−5g")); eq(rows[2].bar, -1); eq(rows[2].pct, "0%")
  end)

  it("a net with silver and a zero net are written", function()
    local w = readyWow()
    owe(w, B, ME, 32000)
    result(w, "ttt", { C, ME }, { 1 }, { 2 })
    local rows = Bd(w).lines(w.ns.client, "all", nil).rows
    local by = {}
    for _, x in ipairs(rows) do by[x.name] = x end
    eq(plain(by[B].net), w:coins("−3g 20s")); eq(plain(by[C].net), "0"); eq(by[C].bar, 0)
  end)

  it("the king line names the highest net; an empty period says the throne is empty", function()
    local w = readyWow()
    eq(Bd(w).lines(w.ns.client, "all", nil).king, "Тронът е празен.")
    owe(w, B, ME, 50000)
    eq(plain(Bd(w).lines(w.ns.client, "all", nil).king), "Кралят/Кралицата на механата: " .. ME)
    w:advance(8 * 86400)
    eq(Bd(w).lines(w.ns.client, "week", nil).king, "Тронът е празен.")
    eq(plain(Bd(w).lines(w.ns.client, "month", nil).king), "Кралят/Кралицата на механата: " .. ME)
  end)

  it("the Horde crowns a chieftain, the Alliance a king or queen", function()
    local w = readyWow(true, "Horde")
    owe(w, B, ME, 50000)
    eq(plain(Bd(w).lines(w.ns.client, "all", nil).king), "Вождът на механата: " .. ME)
    eq(w.ns.L("board.king.horde", "X"), "Вождът на механата: X")
    local a = readyWow()
    owe(a, B, ME, 50000)
    eq(plain(Bd(a).lines(a.ns.client, "all", nil).king), "Кралят/Кралицата на механата: " .. ME)
  end)

  it("every line of the leaderboard has a portrait; the first is ringed in gold", function()
    local w = readyWow()
    result(w); result(w)
    owe(w, B, ME, 50000)
    local v = open(w)
    local rows = shown(w)
    eq(#rows, 2)
    local T = w.ns.Theme
    for _, r in ipairs(rows) do
      ok(r.portrait, "no portrait")
      eq(r.portrait.frame:GetWidth(), 22)
      ok(r.portrait.source ~= nil)
    end
    eq(rows[1].portrait.ring.vertex, { T.color.goldHi[1], T.color.goldHi[2], T.color.goldHi[3], 1 })
    eq(rows[2].portrait.ring.vertex, { T.color.brass[1], T.color.brass[2], T.color.brass[3], 1 })
    local COL = Bd(w).COL
    ok(COL.name[1] >= 34 + 22, "the name starts at " .. COL.name[1])
    ok(v.seal, "no seal")
  end)

  it("a redraw of the rows sets no portrait whose player is unchanged", function()
    local w = readyWow()
    result(w); owe(w, B, ME, 50000)
    local v = open(w)
    local rows = shown(w)
    local touched = 0
    for _, r in ipairs(rows) do
      local setCoord = r.portrait.tex.SetTexCoord
      r.portrait.tex.SetTexCoord = function(...) touched = touched + 1; return setCoord(...) end
    end
    w:click(v.month); w:advance(0); w:click(v.all); w:advance(0)
    eq(#shown(w), 2); eq(touched, 0)
  end)

  it("the period buttons and the game button redraw the rows", function()
    local w = readyWow()
    result(w, "ttt"); owe(w, B, ME, 10000, "ttt")
    result(w, "deathroll", { B, ME }, { 1 }, { 2 })
    w:advance(8 * 86400)
    local v = open(w)
    eq(#shown(w), 0)
    w:click(v.week); w:advance(0)
    eq(#shown(w), 0); ok(v.empty:IsVisible(), "no empty line")
    w:click(v.month); w:advance(0)
    eq(#shown(w), 2)
    w:click(v.all); w:advance(0)
    eq(#shown(w), 2)
    local list = w.ns.Games.list()
    w:click(v.gameBtn); w:advance(0)
    eq(Bd(w).state.game, list[1].id)
    eq(v.gameBtn.text:GetText(), w.ns.W.gameName(list[1].id))
    for _ = 1, #list do w:click(v.gameBtn) end
    eq(Bd(w).state.game, nil); eq(v.gameBtn.text:GetText(), "Всички игри")
  end)

  it("an honour of three wins is written", function()
    local w = readyWow()
    for _ = 1, 3 do result(w) end
    eq(Bd(w).lines(w.ns.client, "all", nil).rows[1].honour, "3 поредни")
    for _ = 1, 3 do result(w, "ttt", { ME, B }, { 2 }, { 1 }) end
    local by = {}
    for _, x in ipairs(Bd(w).lines(w.ns.client, "all", nil).rows) do by[x.name] = x end
    eq(by[B].honour, "3 поредни")
  end)

  it("a new ledger entry redraws the shown tab on the next frame, a hidden tab not at all", function()
    local w = readyWow()
    open(w)
    eq(#shown(w), 0)
    result(w)
    w:advance(2.5)
    eq(#shown(w), 2)
    local renders = 0
    local orig = Bd(w).render
    Bd(w).render = function(...) renders = renders + 1; return orig(...) end
    w.ns.MainWindow.show("hall"); w:advance(0)
    result(w); w:advance(5)
    eq(renders, 0)
    Bd(w).render = orig
    w.ns.MainWindow.show("board"); w:advance(0)
    eq(#shown(w), 2)
  end)

  it("rebuilds the board at most once per two seconds while shown", function()
    local w = readyWow()
    open(w)
    local runs = 0
    local stats = w.ns.LedgerStats
    local orig = stats.board
    stats.board = function(...) runs = runs + 1; return orig(...) end
    local t0 = w.G.GetTime()
    for _ = 1, 6 do result(w) end -- each settles for a second
    w:advance(3)
    local span = w.G.GetTime() - t0
    ok(runs >= 1 and runs <= math.floor(span / 2) + 1, "rebuilt " .. runs .. " in " .. span .. " s")
    eq(plain(shown(w)[1].games:GetText()), "6")
    stats.board = orig
  end)

  it("no guild: the tab shows its empty line", function()
    local w = readyWow(false)
    eq(Bd(w).lines(w.ns.client, "all", nil), { rows = {} })
    local v = open(w)
    ok(v.empty:IsVisible(), "no empty line"); eq(v.empty:GetText(), "Още никой не е играл.")
    eq(#shown(w), 0)
  end)

  it("an empty ledger too", function()
    local w = readyWow()
    local v = open(w)
    ok(v.empty:IsVisible(), "no empty line"); eq(#shown(w), 0)
    eq(Bd(w).lines(w.ns.client, "all", nil).rows, {})
  end)

  it("a click on a row opens the history when the tab exists", function()
    local w = readyWow()
    result(w)
    open(w)
    local got
    w.ns.HistoryTab = { open = function(name) got = name end }
    local r = shown(w)[2]
    r.frame.scripts.OnMouseUp(r.frame, "LeftButton")
    eq(got, B)
    w:hover(r.frame)
    ok(table.concat(w.G.GameTooltip.lines, "\n"):find(B, 1, true), "no tip")
    w.ns.HistoryTab = nil
    r.frame.scripts.OnMouseUp(r.frame, "LeftButton")
  end)

  it("the timer re-checks the two seconds when it fires: a click in between draws once", function()
    local w = readyWow()
    open(w)
    local runs = 0
    local stats = w.ns.LedgerStats
    local orig = stats.board
    stats.board = function(...) runs = runs + 1; return orig(...) end
    w:advance(1.5)
    Bd(w).refresh()               -- due at drawn + 2 s, 0.5 s from now
    w:advance(0.4)
    Bd(w).setPeriod("month")      -- a click: drawn now
    eq(runs, 1)
    w:advance(0.3)                -- the timer has fired, 0.2 s after the click
    eq(runs, 1)
    w:advance(2)
    eq(runs, 2)                   -- it came again once, a full gap after the click
    stats.board = orig
  end)

  it("the ⓘ opens the tab's own topic while it is shown and the hall's after", function()
    local w = readyWow()
    local MW = w.ns.MainWindow
    open(w)
    eq(MW.info.topic, "board")
    MW.show("hall"); eq(MW.info.topic, "hall")
    MW.show("board"); eq(MW.info.topic, "board")
    MW.show("settings"); eq(MW.info.topic, "hall")
  end)

  it("the columns fit the row of 712 px, the honour column holds the longest text, the name column has a header", function()
    local w = readyWow()
    local v = open(w)
    local COL = Bd(w).COL
    local order = { "place", "name", "games", "wins", "pct", "net", "fav", "honour" }
    local prev = 0
    for _, k in ipairs(order) do
      local c = COL[k]
      ok(c[1] >= prev, k .. " overlaps the column before it")
      prev = c[1] + c[2]
    end
    ok(prev <= 712, "the row is " .. prev .. " px")
    ok(COL.honour[2] >= 98, "the honour column is " .. COL.honour[2])
    ok(COL.fav[2] >= 100, "the favourite column is " .. COL.fav[2])
    local pctEnd = COL.pct[1] + COL.pct[2]
    ok(Bd(w).MID - Bd(w).BAR >= pctEnd, "a negative bar starts under the percent")
    eq(v.nameHead:GetText(), "Играч")
  end)

end)

describe("ui: the leaderboard keeps the whole names", function()
  it("a long two-word name: whole (not the short one), shrunk then wrapped in its column; the net never cut", function()
    local w = readyWow()
    local LONG = "Константинопол Велики"
    result(w, "ttt", { ME, LONG }, { 1 }, { 2 }); owe(w, LONG, ME, 99999999)
    open(w)
    local rows = shown(w)
    eq(#rows, 2)
    local r = rows[1].line.name == ME and rows[1] or rows[2]
    local o = r == rows[1] and rows[2] or rows[1]
    eq(plain(o.name:GetText()), LONG) -- the whole name, not the short one
    for _, row in ipairs(rows) do
      for _, key in ipairs({ "place", "name", "games", "wins", "pct", "net", "fav", "honour" }) do fits(row[key], 26) end
    end
    w:hover(o.frame); ok(table.concat(w.G.GameTooltip.lines):find("Константинопол Велики", 1, true), "the tooltip's name")
    ok(not table.concat(w.G.GameTooltip.lines):find("Forever", 1, true), "a realm in the tooltip")
  end)
end)

describe("ui: BookList", function()
  it("500 lines make at most rows + 1 widgets and a wheel refills them", function()
    local w = readyWow()
    local lines = {}
    for i = 1, 500 do lines[i] = { text = "line " .. i } end
    local made, filled = 0, {}
    local list = w.ns.BookList.new(w.ns.MainWindow.frame, {
      width = 300, rowH = 20, rows = 10,
      make = function(row) made = made + 1; row.label = w.ns.W.Label(row.frame, "ui", "", 12) end,
      fill = function(row, line, i) row.label:SetText(line.text); filled[row] = i end,
    })
    list:set(lines)
    eq(made, 11); eq(#list.rows, 11)
    eq(list.rows[1].label:GetText(), "line 1")
    list.scroll:SetVerticalScroll(200)
    list.scroll.scripts.OnMouseWheel(list.scroll, -1)
    eq(made, 11)
    local first
    for _, r in ipairs(list.rows) do
      if r.frame:IsVisible() and (not first or filled[r] < first) then first = filled[r] end
    end
    ok(first >= 10, "not refilled: " .. tostring(first))
    list:set({})
    for _, r in ipairs(list.rows) do eq(r.frame:IsVisible(), false) end
  end)
end)
