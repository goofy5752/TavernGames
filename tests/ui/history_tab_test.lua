local Wow = require("wow")

-- The tab „История“ (ui/HistoryTab.lua) and the click-through from „Класация“.
local ME, B, C = "Иван Петров", "Мария Стоянова", "Тодор Ангелов"

local function readyWow(guild)
  local w = Wow.new{ ui = true }
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
-- ME hosts a fun game: names n, winners w, losers l.
local function fun(w, g, n, win, lose)
  entry(w, ME, "R", { gid = gid(), g = g or "ttt", n = n or { ME, B }, w = win or { 1 }, l = lose or { 2 } })
end
-- ME hosts a staked game ME beat B; `by` writes the debt (B: its own word, confirmed; ME: a claim).
local function staked(w, c, by, g)
  local id = gid()
  entry(w, ME, "R", { gid = id, g = g or "ttt", n = { ME, B }, w = { 1 }, l = { 2 }, sk = c })
  entry(w, by or B, "D", { gid = id, g = g or "ttt", f = B, t = ME, c = c, why = "lost" })
  return id
end
-- The body of the debt B owes at gid.
local function debt(w, id)
  local L = w.ns.client.ledger
  for _, x in ipairs(w.ns.LedgerView.of(L).debts) do
    if x.gid == id then
      local a, n = w.ns.Ledger.author(x.ids[1])
      return L:bodies(a, n)[1]
    end
  end
end

local function Ht(w) return w.ns.HistoryTab end
local function open(w, name) Ht(w).open(name); w:advance(0); return Ht(w).view end
local function shown(w)
  local out = {}
  for _, r in ipairs(Ht(w).view.list.rows) do
    if r.frame:IsVisible() then out[#out + 1] = r end
  end
  table.sort(out, function(p, q) return p.index < q.index end)
  return out
end

describe("ui: the tab „История“", function()
  it("a fun game, a staked game and a payment read as lines, newest first", function()
    local w = readyWow()
    fun(w); w:advance(60)
    staked(w, 50000); w:advance(60)
    entry(w, ME, "P", { f = B, c = 10000, how = "hand" })
    local lines = Ht(w).lines(w.ns.client)
    eq(#lines, 3)
    eq({ lines[1].kind, lines[2].kind, lines[3].kind }, { "pay", "game", "game" })
    eq(plain(lines[1].text), "Мария Стоянова плати на Иван Петров")
    eq(lines[1].mark, "Уредено"); eq(lines[1].amount, "1g")
    eq(plain(lines[2].text), "Морски шах: Иван Петров победи Мария Стоянова")
    eq(lines[2].mark, "потвърдено"); eq(lines[2].amount, "5g")
    eq(plain(lines[3].text), "Морски шах: Иван Петров победи Мария Стоянова")
    eq(lines[3].mark, "за удоволствие"); eq(lines[3].amount, "")
    ok(lines[1].at > lines[2].at and lines[2].at > lines[3].at, "not newest first")
    eq(lines[3].age, "днес")
  end)

  it("a draw, a forfeit and a Холдем sitting have their own words", function()
    local w = readyWow()
    fun(w, "ttt", { ME, B }, {}, {})
    entry(w, ME, "R", { gid = gid(), g = "deathroll", n = { ME, B }, w = { 1 }, l = { 2 }, why = "left" })
    entry(w, ME, "S", { gid = gid(), g = "holdem", f = ME, c = 100, sk = 100, n = { ME, B }, w = {}, l = {} })
    local texts = {}
    for _, l in ipairs(Ht(w).lines(w.ns.client)) do texts[#texts + 1] = plain(l.text) end
    table.sort(texts)
    eq(texts, {
      "Death Roll: Мария Стоянова напусна",
      "Морски шах: Иван Петров и Мария Стоянова, равен",
      "Тексас Холдем: Иван Петров стана от масата",
    })
  end)

  it("a pending game is marked „чака потвърждение“, a contested one „оспорен“, a denied one „отречено“", function()
    local w = readyWow()
    local g1 = staked(w, 20000, ME)
    w:advance(10)
    local g2 = staked(w, 30000, ME)
    w:advance(10)
    local lines = Ht(w).lines(w.ns.client)
    eq({ lines[1].mark, lines[2].mark }, { "чака потвърждение", "чака потвърждение" })
    local d = debt(w, g2)
    entry(w, B, "N", { r = d.i, dh = d.h, why = "no" })
    lines = Ht(w).lines(w.ns.client)
    eq({ lines[1].mark, lines[2].mark }, { "оспорен", "чака потвърждение" })
    fun(w)
    local r = Ht(w).lines(w.ns.client)[1]
    eq(r.kind, "game")
    local e = w.ns.LedgerHistory.lines(w.ns.client.ledger)[1].rec.e
    entry(w, ME, "X", { r = e.i, h = e.h })
    local top = Ht(w).lines(w.ns.client)[1]
    eq(top.kind, "denied"); eq(top.mark, "отречено")
    eq(plain(top.text), "Морски шах: Иван Петров победи Мария Стоянова")
    ok(g1 ~= g2)
  end)

  it("a staked word nobody backs is a claim, and the tooltip says whose", function()
    local w = readyWow()
    w:member(C)
    entry(w, B, "R", { gid = B .. "#1/1", g = "ttt", n = { B, C }, w = { 1 }, l = { 2 }, sk = 10000 })
    local l = Ht(w).lines(w.ns.client)[1]
    eq(l.mark, "само твърдение")
    ok(l.tip:find("по думите на " .. B, 1, true), l.tip)
  end)

  it("the tooltip names the host whose word a fun result is", function()
    local w = readyWow()
    fun(w)
    open(w)
    local r = shown(w)[1]
    w:hover(r.frame)
    local tip = table.concat(w.G.GameTooltip.lines, "\n")
    ok(tip:find("по думите на " .. ME, 1, true), tip)
    ok(tip:find("Морски шах", 1, true), tip)
  end)

  it("open(name) shows that player's lines and the head-to-head; „Всички“ clears it", function()
    local w = readyWow()
    fun(w); staked(w, 50000)
    w:member(C)
    entry(w, B, "R", { gid = B .. "#1/1", g = "ttt", n = { B, C }, w = { 1 }, l = { 2 } })
    local v = open(w)
    eq(#shown(w), 3); eq(plain(v.title:GetText()), "История"); ok(not v.all:IsVisible(), "button without a filter")
    eq(#Ht(w).head(w.ns.client, nil), 0)
    v = open(w, B)
    eq(w.ns.MainWindow.current, "history")
    eq(#shown(w), 3)
    eq(plain(v.title:GetText()), "История на Мария Стоянова")
    ok(v.all:IsVisible(), "no „Всички“")
    local head = Ht(w).head(w.ns.client, B)
    eq(#head, 2)
    eq(plain(head[1].text), "срещу Иван Петров: 0 победи, 2 загуби, −5g")
    ok(plain(v.versus[1]:GetText()):find("срещу Иван Петров", 1, true), "head line not drawn")
    w:click(v.all); w:advance(0)
    eq(plain(v.title:GetText()), "История"); eq(Ht(w).state.name, nil)
    ok(not v.all:IsVisible(), "button stays")
    eq(#shown(w), 3)
    open(w, C)
    eq(#shown(w), 1)
  end)

  it("a click on a row of „Класация“ opens the history of that player", function()
    local w = readyWow()
    fun(w)
    w.ns.MainWindow.show("board"); w:advance(0)
    local rows = {}
    for _, r in ipairs(w.ns.BoardTab.view.list.rows) do if r.frame:IsVisible() then rows[#rows + 1] = r end end
    table.sort(rows, function(p, q) return p.index < q.index end)
    local r = rows[2]
    r.frame.scripts.OnMouseUp(r.frame, "LeftButton")
    w:advance(0)
    eq(w.ns.MainWindow.current, "history")
    eq(Ht(w).state.name, r.line.name)
    eq(#shown(w), 1)
  end)

  it("3000 lines: at most 17 row widgets, and only the rows on screen have text", function()
    local w = readyWow()
    local L, now = w.ns.client.ledger, w.G.GetServerTime()
    for j = 1, 3000 do
      local st = L:add({ i = ME .. ":" .. (500 + j), k = "R", at = now - 4000 + j, gid = ME .. "#9/" .. j, g = "ttt",
        n = { ME, B }, w = { 1 }, l = { 2 } }, nil)
      assert(st == "new", tostring(st))
    end
    local v = open(w)
    eq(#v.list.lines, 3000)
    ok(#v.list.rows <= 17, "built " .. #v.list.rows .. " row widgets")
    local dressed = 0
    for _, l in ipairs(v.list.lines) do if l.text then dressed = dressed + 1 end end
    ok(dressed <= 17, "dressed " .. dressed .. " lines")
    for _ = 1, 400 do v.list.scroll.scripts.OnMouseWheel(v.list.scroll, -1) end
    ok(#v.list.rows <= 17, "scrolling built " .. #v.list.rows)
    ok(shown(w)[1].index > 1, "did not scroll")
  end)

  it("no guild and an empty ledger show the empty line", function()
    local w = readyWow(false)
    eq(Ht(w).lines(w.ns.client), {})
    local v = open(w)
    ok(v.empty:IsVisible(), "no empty line"); eq(v.empty:GetText(), "Още няма история.")
    eq(#shown(w), 0)
    local w2 = readyWow()
    local v2 = open(w2)
    ok(v2.empty:IsVisible(), "no empty line"); eq(#shown(w2), 0)
    eq(Ht(w2).head(w2.ns.client, ME), {})
  end)

  it("rebuilds at most once per two seconds while shown, and not at all hidden", function()
    local w = readyWow()
    open(w)
    local runs = 0
    local hist = w.ns.LedgerHistory
    local orig = hist.lines
    hist.lines = function(...) runs = runs + 1; return orig(...) end
    local t0 = w.G.GetTime()
    for _ = 1, 6 do fun(w) end
    w:advance(3)
    local span = w.G.GetTime() - t0
    ok(runs >= 1 and runs <= math.floor(span / 2) + 1, "rebuilt " .. runs .. " in " .. span .. " s")
    eq(#shown(w), 6)
    w.ns.MainWindow.show("hall"); w:advance(0)
    runs = 0
    fun(w); w:advance(5)
    eq(runs, 0)
    hist.lines = orig
    w.ns.MainWindow.show("history"); w:advance(0)
    eq(#shown(w), 7)
  end)
end)
