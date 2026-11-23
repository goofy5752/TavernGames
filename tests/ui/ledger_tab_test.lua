local Wow = require("wow")

-- The tab „Тефтер“ (ui/LedgerTab.lua): every debt of the guild as a line in the
-- innkeeper's book, open ones first, the paid ones struck through, the denied
-- ones marked; the head counts the open debts, the foot names the biggest debtor.
local ME, B, C, D = "Иван Петров", "Мария Стоянова", "Тодор Ангелов", "Дара Колева"
local MIDNIGHT = 1700006400 -- 2023-11-15 00:00 UTC (the fake date is UTC)

-- In a guild, booted with the ui/ files, my login queue closed, the window shown.
local function readyWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
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
local function now(w) return w.G.GetServerTime() end

local counters, games = {}, 0
local function gid() games = games + 1; return "Мария Стоянова#1/" .. games end

-- `author`'s entry of kind k with `fields`, taken from `from` (default: its
-- author, live); `quiet` leaves the ledger's moment open (no settle).
local function entry(w, author, k, fields, from, quiet)
  w:member(author)
  counters[w] = counters[w] or {}
  local n = (counters[w][author] or 0) + 1
  counters[w][author] = n
  local e = { i = author .. ":" .. n, k = k, at = now(w) }
  for key, value in pairs(fields) do e[key] = value end
  if from then
    w:member(from)
    w.ns.client.ledgerNet:take(e, from, false)
  else
    w.ns.client.ledgerNet:take(e, author, true)
  end
  if not quiet then settle(w) end
  return w.ns.client.ledger:get(e.i)
end

-- f owes t c copper: f's own D (confirmed), or t's claim (pending) when by = t.
local function debt(w, f, t, c, opts)
  opts = opts or {}
  w:member(f); w:member(t)
  return entry(w, opts.by or f, "D", { gid = gid(), g = opts.g or "ttt", f = f, t = t, c = c, why = "lost", at = opts.at },
    opts.from, opts.quiet)
end
local function paid(w, f, t, c) w:member(f); return entry(w, t, "P", { f = f, c = c, how = "hand" }) end
local function contest(w, d) return entry(w, d.f, "N", { r = d.i, dh = d.h, why = "no" }) end
local function deny(w, b) return entry(w, (b.i:match("^(.*):")), "X", { r = b.i, h = b.h }) end

local function T(w) return w.ns.LedgerTab.view end
local function open(w)
  w.ns.MainWindow.show("ledger")
  w:advance(0)
  return T(w)
end

-- The visible lines of the book: {who, amount, age, mark} in plain text.
local function shown(w)
  local out, rows = {}, {}
  for _, r in ipairs(T(w).rows) do if r.frame:IsVisible() then rows[#rows + 1] = r end end
  table.sort(rows, function(p, q) return p.index < q.index end)
  for _, r in ipairs(rows) do
    out[#out + 1] = { plain(r.who:GetText()), plain(r.amount:GetText()), plain(r.age:GetText()),
      r.mark:IsVisible() and plain(r.mark:GetText()) or nil }
  end
  return out
end
local function states(w)
  local out = {}
  for _, l in ipairs(w.ns.LedgerTab.lines(w.ns.client)) do out[#out + 1] = l.state end
  return out
end

describe("ui: the tab „Тефтер“", function()
  it("the tab sits between Зала and Настройки, its ⓘ opens the ledger topic", function()
    local w = readyWow()
    local MW = w.ns.MainWindow
    eq(MW.order, { "hall", "ledger", "board", "history", "settings" })
    eq(MW.tabs.ledger.button.text:GetText(), "Тефтер")
    eq(MW.info.topic, "hall")
    open(w)
    eq(MW.current, "ledger"); eq(MW.info.topic, "ledger")
    MW.show("hall"); eq(MW.info.topic, "hall")
    MW.show("ledger"); eq(MW.info.topic, "ledger")
    MW.show("settings"); eq(MW.info.topic, "hall")
  end)

  it("an empty ledger says so", function()
    local w = readyWow()
    local v = open(w)
    ok(v.empty:IsVisible(), "no empty line"); eq(v.empty:GetText(), "Тефтерът е празен. Никой никому не дължи.")
    eq(v.head:IsVisible(), false); eq(v.foot:IsVisible(), false)
    eq(shown(w), {}); eq(w.ns.LedgerTab.lines(w.ns.client), {})
  end)

  it("the head counts the open confirmed debts", function()
    local w = readyWow()
    debt(w, B, C, 50000)
    debt(w, D, C, 20000)
    local v = open(w)
    ok(v.head:IsVisible(), "no head"); eq(v.head:GetText(), w:coins("Открити дългове в гилдията: 7g в 2 записа"))
    eq(v.empty:IsVisible(), false)
  end)

  it("rows: open first (newest first), then pending, contested, paid, denied; paid struck, part paid", function()
    local w = readyWow()
    local L = w.ns.L
    local gone = debt(w, D, B, 10000)                          -- denied by its author
    paid(w, C, D, 40000); debt(w, C, D, 40000)                 -- paid in full (the P came first)
    local fought = debt(w, C, B, 30000, { by = B })            -- Мария's claim, contested by Тодор
    contest(w, fought)
    debt(w, D, B, 60000, { by = B })                           -- Мария's claim, pending
    w:advance(60); debt(w, B, C, 50000); paid(w, B, C, 30000)  -- open, 2g of 5g left
    w:advance(60); debt(w, D, C, 20000)                        -- open, newest
    deny(w, gone)
    open(w)
    eq(states(w), { "open", "open", "pending", "contested", "paid", "denied" })
    eq(shown(w), {
      { "Дара Колева » Тодор Ангелов", w:coins("2g"), "днес" },
      { "Мария Стоянова » Тодор Ангелов", w:coins("остават 2g от 5g"), "днес" },
      { "Дара Колева » Мария Стоянова", w:coins("6g"), "днес", "чака потвърждение" },
      { "Тодор Ангелов » Мария Стоянова", w:coins("3g"), "днес", "оспорен" },
      { "Тодор Ангелов » Дара Колева", w:coins("4g"), "днес" },
      { "Дара Колева » Мария Стоянова", w:coins("1g"), "днес", "отречено от автора си" },
    })
    local rows = T(w).rows
    table.sort(rows, function(p, q) return p.index < q.index end)
    eq(rows[5].line.state, "paid")
    ok(rows[5].strike:IsVisible(), "the paid row is not struck through")
    for _, j in ipairs({ 1, 2, 3, 4, 6 }) do eq(rows[j].strike:IsVisible(), false) end
    eq(L("ledger.part", "2g", "5g"), "остават 2g от 5g")
  end)

  it("a pending and a contested row carry their mark and are in no total", function()
    local w = readyWow()
    debt(w, D, B, 60000, { by = B })
    local fought = debt(w, C, B, 30000, { by = B })
    contest(w, fought)
    debt(w, B, C, 10000)
    local v = open(w)
    eq(v.head:GetText(), w:coins("Открити дългове в гилдията: 1g в 1 записа"))
    local marks = {}
    for _, l in ipairs(shown(w)) do marks[#marks + 1] = l[4] or "-" end
    eq(marks, { "-", "чака потвърждение", "оспорен" })
    eq(v.foot:GetText(), w:coins("Най-голям длъжник: Мария Стоянова (1g)"))
  end)

  it("a denied entry is „отречено“; one I got directly from its author „отречено от автора си“", function()
    local w = readyWow()
    local forged = debt(w, B, D, 70000, { from = C }) -- under Мария's name, relayed by Тодор
    deny(w, forged)
    local reneged = debt(w, D, C, 20000)               -- Дара's own, then her denial
    deny(w, reneged)
    open(w)
    eq(states(w), { "denied", "denied" })
    local marks = {}
    for _, l in ipairs(shown(w)) do marks[l[1]] = l[4] end
    eq(marks, { ["Мария Стоянова » Дара Колева"] = "отречено", ["Дара Колева » Тодор Ангелов"] = "отречено от автора си" })
    eq(T(w).head:IsVisible(), true); eq(T(w).head:GetText(), w:coins("Открити дългове в гилдията: 0c в 0 записа"))
    eq(T(w).foot:IsVisible(), false)
  end)

  it("a denied payment is listed as the payer's line", function()
    local w = readyWow()
    debt(w, B, C, 50000)
    local p = paid(w, B, C, 50000)
    deny(w, p)
    open(w)
    eq(states(w), { "open", "denied" })
    eq(shown(w)[2], { "Мария Стоянова » Тодор Ангелов", w:coins("5g"), "днес", "отречено от автора си" })
  end)

  it("a relayed entry carries „пренесено“ in its tooltip", function()
    local w = readyWow()
    debt(w, B, C, 50000, { from = D, g = "deathroll" }) -- Мария's own D, relayed by Дара
    debt(w, D, C, 20000)                                -- straight from its author
    open(w)
    local rows = T(w).rows
    table.sort(rows, function(p, q) return p.index < q.index end)
    eq(plain(rows[1].who:GetText()), "Дара Колева » Тодор Ангелов")
    w:hover(rows[1].frame)
    local tip = table.concat(w.G.GameTooltip.lines, "\n")
    ok(not tip:find("пренесено", 1, true), "a direct entry says relayed: " .. tip)
    w:hover(rows[2].frame)
    tip = table.concat(w.G.GameTooltip.lines, "\n")
    ok(tip:find("пренесено", 1, true), "no relayed line: " .. tip)
    ok(tip:find("Death Roll", 1, true), "no game: " .. tip)
    eq(w.ns.LedgerTab.lines(w.ns.client)[2].relayed, true)
    eq(w.ns.LedgerTab.lines(w.ns.client)[1].relayed, false)
  end)

  it("the age label counts calendar days", function()
    local w = readyWow()
    w:advance(MIDNIGHT + 600 - now(w)) -- 00:10
    debt(w, B, C, 10000, { at = MIDNIGHT - 5 * 86400 + 60 })
    debt(w, D, C, 10000, { at = MIDNIGHT - 600 })      -- 23:50 yesterday
    debt(w, C, ME, 10000, { at = MIDNIGHT + 60 })      -- 00:01 today
    open(w)
    local ages = {}
    for _, l in ipairs(shown(w)) do ages[#ages + 1] = l[3] end
    eq(ages, { "днес", "вчера", "5 дни" })
  end)

  it("the foot names the biggest debtor; nobody owes, no foot", function()
    local w = readyWow()
    debt(w, B, C, 50000); debt(w, B, D, 20000); debt(w, D, C, 60000)
    local v = open(w)
    ok(v.foot:IsVisible(), "no foot"); eq(plain(v.foot:GetText()), w:coins("Най-голям длъжник: Мария Стоянова (7g)"))
    paid(w, B, C, 50000); paid(w, B, D, 20000); paid(w, D, C, 60000)
    eq(v.foot:IsVisible(), false)
    eq(states(w), { "paid", "paid", "paid" })
  end)

  it("names are in class colour when the class is known (presence), ink otherwise", function()
    local w = readyWow()
    w:member(B)
    w:deliver("GUILD", B, { v = 1, t = "HI", ver = "0.1.0", cls = "MAGE", id = "Player-1-" .. B })
    debt(w, B, C, 50000)
    open(w)
    local text = T(w).rows[1].who:GetText()
    local r, g, b = w.ns.classColor("MAGE")
    local k = w.ns.LedgerTab.DARK
    ok(text:find(w.ns.W.paint(B, r * k, g * k, b * k), 1, true), "Мария not in her class colour: " .. text)
    ok(not text:find("|c%x+" .. C), "Тодор coloured without a class: " .. text)
    ok(text:find(C, 1, true), "no Тодор")
    eq({ T(w).rows[1].who:GetTextColor() }, { w.ns.Theme.color.woodDark[1], w.ns.Theme.color.woodDark[2], w.ns.Theme.color.woodDark[3], 1 })
  end)

  it("the tab follows the ledger; a hidden page renders on show", function()
    local w = readyWow()
    open(w)
    debt(w, B, C, 50000)
    eq(#shown(w), 1); eq(T(w).empty:IsVisible(), false)
    w.ns.MainWindow.show("hall"); w:advance(0)
    local renders, orig = 0, w.ns.LedgerTab.render
    w.ns.LedgerTab.render = function(...) renders = renders + 1; return orig(...) end
    debt(w, D, C, 20000)
    eq(#T(w).lines, 1)
    w.ns.MainWindow.show("ledger")
    eq(#T(w).lines, 2); eq(#shown(w), 2)
    ok(renders >= 1, "not rendered on show")
  end)

  it("two 64-byte names and a long mark never reach the amount; the tooltip has the whole line", function()
    local w = readyWow()
    local F, T2 = string.rep("Я", 32), string.rep("Ж", 32) -- 64 bytes each, the longest name
    eq({ #F, #T2 }, { 64, 64 })
    w:member(F); w:member(T2)
    local g = gid()
    local own = entry(w, F, "D", { gid = g, g = "ttt", f = F, t = T2, c = 50000, why = "lost" })
    entry(w, T2, "D", { gid = g, g = "ttt", f = F, t = T2, c = 60000, why = "lost" }) -- another amount: clash
    contest(w, own)
    debt(w, T2, F, 999900); paid(w, T2, F, 100) -- „остават 99g 98s от 99g 99s“
    local v = open(w)
    local rows = {}
    for _, r in ipairs(v.rows) do if r.frame:IsVisible() then rows[#rows + 1] = r end end
    eq(#rows, 2)
    -- The horizontal extent of a font string in its row: its box when it has a
    -- width, else its text, from its one anchor (on the row or on another label).
    local edges
    function edges(fs, r)
      local p = fs.points[1]
      local size = (fs.width or 0) > 0 and fs.width or fs:GetStringWidth()
      local base
      if p[2] == r.frame then
        base = p[3]:find("RIGHT") and v.rowW or 0
      else
        local l, rt = edges(p[2], r)
        base = p[3]:find("RIGHT") and rt or l
      end
      local x = base + (p[4] or 0)
      if p[1]:find("RIGHT") then return x - size, x end
      return x, x + size
    end
    for _, r in ipairs(rows) do
      local wl, wr = edges(r.who, r)
      local ml, mr = r.mark:IsVisible() and edges(r.mark, r) or wr, r.mark:IsVisible() and select(2, edges(r.mark, r)) or wr
      local al, ar = edges(r.amount, r)
      local gl = edges(r.age, r)
      ok(wr <= ml, "the names run into the mark: " .. wr .. " > " .. ml)
      ok(mr <= al, "the mark runs into the amount: " .. mr .. " > " .. al)
      ok(ar <= gl, "the amount runs into the age")
      ok(wl >= 0 and select(2, edges(r.age, r)) <= v.rowW, "out of the row")
      for _, fs in ipairs({ r.who, r.mark, r.amount }) do eq(fs.wordWrap, false) end
      ok(r.amount:GetStringWidth() <= r.amount:GetWidth(), "the amount is clipped: " .. r.amount:GetText())
      w:hover(r.frame)
      local tip = table.concat(w.G.GameTooltip.lines, "\n")
      ok(plain(tip):find(plain(r.who:GetText()), 1, true), "the tooltip lacks the whole line: " .. tip)
    end
    local marks = {}
    for _, l in ipairs(shown(w)) do marks[#marks + 1] = l[4] or "-" end
    eq(marks, { "-", "оспорен · спор за сумата" })
    eq(shown(w)[1][2], w:coins("остават 99g 98s от 99g 99s"))
  end)

  it("two hundred rows scroll and build only the visible widgets", function()
    local w = readyWow()
    local names = {}
    for j = 1, 10 do names[j] = "Длъжник" .. j end
    for j = 1, 200 do
      w:advance(1)
      debt(w, names[(j - 1) % 10 + 1], C, 10000 + j * 100, { quiet = true })
    end
    settle(w)
    local v = open(w)
    eq(#v.lines, 200)
    ok(#v.rows <= v.ROWS + 2, "built " .. #v.rows .. " row widgets for " .. v.ROWS .. " rows")
    local first = shown(w)[1]
    eq(first[2], w:coins("3g")) -- the newest: 1g + 200 * 1s
    for _ = 1, 400 do v.scroll.scripts.OnMouseWheel(v.scroll, -1) end
    local after = shown(w)
    eq(after[#after][2], w:coins("1g 1s")) -- the oldest
    ok(#v.rows <= v.ROWS + 2, "scrolling built more widgets: " .. #v.rows)
    eq(v.scroll.contentHeight, 200 * v.ROW_H)
  end)
end)
