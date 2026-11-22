local Wow = require("wow")

local ME, B, C = "Иван Петров", "Мария Стоянова", "Тодор Ангелов"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired.
local function guildWow(saved)
  local w = Wow.new{ ui = true, saved = saved }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

local function hi(w, name, cls, at)
  w:member(name)
  w:deliver("GUILD", name, { v = 1, t = "HI", ver = "0.1.0", cls = cls, id = "Player-" .. name, at = at })
  w:advance(0) -- the hall redraws on the next frame
end

local function tbl(w, host, seats, state, game)
  local tid = host .. "#1"
  w:member(host)
  w:deliver("GUILD", host, { v = 1, t = "TBL", tid = tid, g = game or "ttt", h = host, e = 1, ac = "guild", tn = 45,
                             st = state or "open", s = seats or { host, false }, w = 0 })
  w:advance(0)
  return tid
end

local function visible(list)
  local n = 0
  for _, x in ipairs(list) do
    if x.frame:IsVisible() then n = n + 1 end
  end
  return n
end

local function lastSent(w, t)
  local all = w:sentOf(t)
  return all[#all]
end

describe("ui: main window", function()
  it("builds 1100x620 with the hall tab, title, ⓘ and close, and creates no globals", function()
    local w = guildWow()
    local MW = w.ns.MainWindow
    MW.show()
    local f = MW.frame
    ok(f and f:IsShown(), "window not shown")
    eq({ f:GetWidth(), f:GetHeight() }, { 1100, 620 })
    eq(MW.current, "hall")
    eq(MW.order, { "hall", "ledger", "settings" })
    eq(MW.title:GetText(), "Tavern Games")
    eq(MW.title:GetFont(), w.ns.Theme.font.heading)
    ok(MW.info:IsVisible(), "no ⓘ"); ok(MW.close:IsVisible(), "no close")
    ok(f.movable and f.clamped, "not movable")
    eq(w:newGlobals(), { "SLASH_TAVERNGAMES1", "TavernGamesDB" })
  end)

  it("/tavern toggles it and Escape closes it without swallowing other keys", function()
    local w = guildWow()
    local MW = w.ns.MainWindow
    w:slash(""); ok(MW.frame:IsShown(), "not opened")
    w:key(MW.frame, "W"); eq(MW.frame.propagate, true); ok(MW.frame:IsShown(), "closed on W")
    w:key(MW.frame, "ESCAPE"); eq(MW.frame:IsShown(), false); eq(MW.frame.propagate, false)
    w:advance(0); eq(MW.frame.propagate, true)
    w:slash(""); ok(MW.frame:IsShown(), "not reopened")
    w:click(MW.close); eq(MW.frame:IsShown(), false)
  end)

  it("Escape in combat closes it and lets the key through", function()
    local w = guildWow()
    local MW = w.ns.MainWindow
    MW.show(); w.combat = true
    local before = MW.frame.propagate
    w:key(MW.frame, "ESCAPE")
    eq(MW.frame:IsShown(), false); eq(MW.frame.propagate, before)
  end)

  it("Escape, then combat before the next frame: keys are handed back before the lockdown", function()
    local w = guildWow()
    local MW = w.ns.MainWindow
    MW.show()
    w:key(MW.frame, "ESCAPE"); eq(MW.frame.propagate, false)
    -- PLAYER_REGEN_DISABLED fires before InCombatLockdown() turns true
    w:fire("PLAYER_REGEN_DISABLED"); w.combat = true
    eq(MW.frame.propagate, true)
    w:advance(0); MW.show()
    ok(MW.frame:IsShown(), "not reopened"); eq(MW.frame.propagate, true)
    w:key(MW.frame, "W"); eq(MW.frame.propagate, true)
  end)

  it("keys still held in combat (no PLAYER_REGEN_DISABLED seen): it does not open until combat ends", function()
    local w = guildWow()
    local MW = w.ns.MainWindow
    MW.show()
    w:key(MW.frame, "ESCAPE"); w.combat = true; w:advance(0)
    eq(MW.frame.propagate, false)
    MW.show(); eq(MW.frame:IsShown(), false)
    w.combat = false; w:fire("PLAYER_REGEN_ENABLED"); eq(MW.frame.propagate, true)
    MW.show(); ok(MW.frame:IsShown(), "not reopened")
  end)

  it("built in combat, it takes the keyboard only once combat ends", function()
    local w = guildWow()
    local MW = w.ns.MainWindow
    w.combat = true; MW.show()
    eq(MW.frame.keyboard, nil); eq(MW.frame.scripts.OnKeyDown, nil)
    w.combat = false; w:fire("PLAYER_REGEN_ENABLED")
    eq(MW.frame.keyboard, true); eq(MW.frame.propagate, true)
  end)

  it("shows the gold in the bags and follows PLAYER_MONEY", function()
    local w = guildWow()
    w.money = 1843200
    local MW = w.ns.MainWindow
    MW.show()
    eq(MW.gold:GetText(), "184g 32s")
    w.money = 123456; w:fire("PLAYER_MONEY")
    eq(MW.gold:GetText(), "12g 34s 56c")
    eq(#w:texts(w.ns.L("main.gold")), 1)
  end)

  it("ⓘ opens the rules book on the hall topic", function()
    local w = guildWow()
    local opened = {}
    w.ns.HelpBook = { open = function(id) opened[#opened + 1] = id end }
    w.ns.MainWindow.show()
    w:click(w.ns.MainWindow.info)
    eq(opened, { "hall" })
  end)

  it("addTab adds a tab button in order and builds its page on first show only", function()
    local w = guildWow()
    local MW, built = w.ns.MainWindow, 0
    MW.addTab("extra", "addon.title", function(parent) built = built + 1; ok(parent, "no parent") end)
    MW.show(); eq(MW.order, { "hall", "ledger", "settings", "extra" }); eq(built, 0)
    MW.show("extra"); eq(MW.current, "extra"); eq(built, 1)
    ok(not MW.pages.hall:IsShown(), "hall page still shown")
    MW.show("hall"); MW.show("extra"); eq(built, 1)
  end)
end)

describe("ui: hall", function()
  it("lists six games: Морски шах, Death Roll, Сантасе, Белот, Табла and Холдем, all active", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local games = w.ns.Hall.view.games
    eq(#games, 6)
    eq({ games[1].id, games[2].id, games[3].id, games[5].id, games[6].id }, { "ttt", "deathroll", "santase", "tabla", "holdem" })
    eq(games[1].name:GetText(), "Морски шах")
    for i = 1, 6 do eq(games[i].frame:GetAlpha(), 1); eq(games[i].soon:IsVisible(), false) end
    eq(#w:texts("2–5 играчи"), 1)
    w:click(games[2].frame)
    ok(w.ns.NewTableDialog.frame:IsVisible(), "dialog not open")
    eq(w.ns.NewTableDialog.gameId, "deathroll")
  end)

  it("a dimmed game opens the rules book on „soon“; „Отвори маса“ opens the first active game", function()
    local w = guildWow()
    local opened = {}
    w.ns.HelpBook = { open = function(id) opened[#opened + 1] = id end }
    w.ns.Games.PLAYABLE.holdem = nil -- gated by hand: every game of ORDER is integrated
    w.ns.MainWindow.show()
    w:click(w.ns.Hall.view.games[6].frame)
    eq(opened, { "soon" })
    w:click(w.ns.Hall.view.openButton)
    eq(w.ns.NewTableDialog.gameId, "ttt")
  end)

  it("an empty hall says so", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    eq(w.ns.L("hall.empty"), "Няма отворени маси. Отвори първата!")
    eq(w.ns.Hall.mode, "empty")
    eq(#w:texts("Няма отворени маси. Отвори първата!"), 1)
  end)

  it("not in a guild: the no-guild message instead of tables", function()
    local w = Wow.new{ ui = true }
    w:boot(); w:firstRunDone(); w:fire("PLAYER_LOGIN")
    w.ns.MainWindow.show()
    eq(w.ns.Hall.mode, "noguild")
    eq(#w:texts(w.ns.L("hall.noguild")), 1)
    eq(w.ns.Hall.view.floor:IsVisible(), false); eq(w.ns.Hall.view.list:IsVisible(), false)
    w:slash("bots"); w:slash("bots host"); w:advance(3)
    eq(w.ns.Hall.mode, "floor")
    eq(#w:texts(w.ns.L("hall.noguild")), 0)
  end)

  it("a table: occupied chair in class color with the first name, a click on the dashed chair sits", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    hi(w, B, "MAGE")
    local tid = tbl(w, B)
    eq(w.ns.Hall.mode, "floor")
    local t = w.ns.Hall.view.tables[1]
    ok(t.frame:IsVisible(), "table hidden"); eq(t.tid, tid)
    eq(t.game:GetText(), "Морски шах")
    local c1, c2 = t.chairs[1], t.chairs[2]
    eq(c1.disc:GetTexture(), w.ns.Theme.tex.chair)
    eq({ c1.disc:GetVertexColor() }, { 0.25, 0.78, 0.92, 1 })
    eq(c1.label:GetText(), "Мария")
    eq({ c1.label:GetTextColor() }, { 0.25, 0.78, 0.92, 1 })
    eq(t.host:GetText(), "Мария"); eq({ t.host:GetTextColor() }, { 0.25, 0.78, 0.92, 1 })
    eq(c2.disc:GetTexture(), w.ns.Theme.tex.chair_empty); eq(c2.label:IsVisible(), false)
    w:click(c2.button)
    local sit = lastSent(w, "SIT")
    ok(sit, "no SIT"); eq(sit.dist, "WHISPER"); eq(sit.target, B); eq({ sit.msg.tid, sit.msg.seat }, { tid, 2 })
  end)

  it("tooltips name the table, its players and what a click does", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    hi(w, B, "MAGE")
    tbl(w, B)
    local t, tip = w.ns.Hall.view.tables[1], w.G.GameTooltip
    w:hover(t.top)
    eq(tip.lines, { "Морски шах при |cff40c7ebМария Стоянова|r", B, "Всеки от гилдията · 45 с на ход",
                    "Кликни празния стол, за да седнеш" })
    w:hover(t.chairs[1].button); eq(tip.lines, { B })
    w:hover(t.chairs[2].button); eq(tip.lines, { "Кликни празния стол, за да седнеш" })
    local g = w.ns.Theme.color.gold
    eq({ t.chairs[2].disc:GetVertexColor() }, { g[1], g[2], g[3], 1 })
    t.chairs[2].button.scripts.OnLeave(t.chairs[2].button)
    eq({ t.chairs[2].disc:GetVertexColor() }, { 1, 1, 1, 1 })
  end)

  it("a live table shows „тече“ and a click on it watches", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local tid = tbl(w, B, { B, C }, "live")
    local t = w.ns.Hall.view.tables[1]
    eq(t.state:GetText(), "тече"); ok(t.state:IsVisible(), "тече hidden")
    w:click(t.top)
    local wat = lastSent(w, "WAT")
    ok(wat, "no WAT"); eq(wat.target, B); eq(wat.msg.tid, tid)
  end)

  it("my table comes first and glows, pulsing", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    tbl(w, B)
    local mine = w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    local tables = w.ns.Hall.view.tables
    eq(tables[1].tid, mine)
    ok(tables[1].glow:IsVisible(), "no glow"); eq(tables[2].glow:IsVisible(), false)
    w:render(0.5); local a1 = tables[1].glow:GetAlpha()
    w:render(0.5); local a2 = tables[1].glow:GetAlpha()
    ok(a1 ~= a2, "glow does not pulse")
  end)

  it("nine tables switch the centre from the floor to the list", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local view = w.ns.Hall.view
    hi(w, "Гост 1", "WARRIOR")
    for i = 1, 8 do tbl(w, "Гост " .. i) end
    eq(w.ns.Hall.mode, "floor"); eq(visible(view.tables), 8)
    ok(view.floor:IsVisible(), "floor hidden"); eq(view.list:IsVisible(), false)
    tbl(w, "Гост 9", { "Гост 9", C }, "live")
    eq(w.ns.Hall.mode, "list"); eq(view.floor:IsVisible(), false); ok(view.list:IsVisible(), "list hidden")
    eq(visible(view.rows), 9)
    local first, last = view.rows[1], view.rows[9]
    eq(first.title:GetText(), "Морски шах при |cffc79c6eГост 1|r")
    eq(view.rows[2].title:GetText(), "Морски шах при |cfff3e2c0Гост 2|r") -- no class known: ink
    eq(first.seats:GetText(), "1/2"); eq(first.state:GetText(), "чака"); eq(first.action.text:GetText(), "Седни")
    eq(last.seats:GetText(), "2/2"); eq(last.state:GetText(), "тече"); eq(last.action.text:GetText(), "Гледай")
    w:click(first.action)
    eq({ lastSent(w, "SIT").target, lastSent(w, "SIT").msg.seat }, { "Гост 1", 2 })
    w:click(last.action)
    eq(lastSent(w, "WAT").target, "Гост 9")
    local list = view.list
    list.scripts.OnMouseWheel(list, -1); eq(list:GetVerticalScroll(), 40)
    list.scripts.OnMouseWheel(list, 1); eq(list:GetVerticalScroll(), 0)
  end)

  it("a five-seat table shows five chairs without name labels; the list shows 2/5", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local view = w.ns.Hall.view
    local tid = tbl(w, B, { B, "Kiro Barley", false, false, false }, "open", "deathroll")
    eq(w.ns.Hall.mode, "floor")
    local t = view.tables[1]
    eq(t.tid, tid); eq(t.game:GetText(), "Death Roll")
    local shown, enabled, labels = 0, 0, 0
    for _, c in ipairs(t.chairs) do
      if c.button:IsVisible() then shown = shown + 1 end
      if c.button:IsVisible() and c.button:IsEnabled() then enabled = enabled + 1 end
      if c.label:IsVisible() then labels = labels + 1 end
    end
    eq({ shown, enabled, labels }, { 5, 3, 0 })
    w:hover(t.top)
    eq({ w.G.GameTooltip.lines[2], w.G.GameTooltip.lines[3] }, { B, "Kiro Barley" })
    for i = 1, 8 do tbl(w, "Гост " .. i) end
    eq(w.ns.Hall.mode, "list")
    local row
    for _, r in ipairs(view.rows) do
      if r.frame:IsVisible() and r.tid == tid then row = r end
    end
    ok(row, "no row for the Death Roll table"); eq(row.seats:GetText(), "2/5")
  end)

  it("a table of a game this client does not have is named „Непозната игра“ and a chair click is refused", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    eq(w.ns.L("game.unknown"), "Непозната игра")
    local tid = tbl(w, B, { B, false }, "open", "|TInterface\\Icons\\x:16|t")
    local t = w.ns.Hall.view.tables[1]
    eq(t.tid, tid)
    eq(#w:texts("Непозната игра"), 1); eq(#w:texts("|T"), 0)
    local sent = #w.sent
    w:click(t.chairs[2].button)
    eq(w.ns.Hall.view.footer:GetText(), w.ns.L("refused.version"))
    eq(#w.sent, sent)
  end)

  it("„В кръчмата сега“ lists names in class color and where they are", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local D = "Дара Колева"
    local tid = tbl(w, D, { D, C }, "live")
    hi(w, D, "WARRIOR", tid); hi(w, B, "MAGE"); hi(w, C, "WARRIOR", tid); hi(w, "Яна Жекова", "MAGE", tid)
    local rows, byName = w.ns.Hall.view.peers, {}
    for _, r in ipairs(rows) do
      if r.frame:IsVisible() then byName[r.name:GetText()] = r end
    end
    eq(byName[B].status:GetText(), "в залата")
    eq({ byName[B].name:GetTextColor() }, { 0.25, 0.78, 0.92, 1 })
    eq(byName[C].status:GetText(), "на маса при |cffc79c6eДара|r")
    eq({ byName[C].name:GetTextColor() }, { 0.78, 0.61, 0.43, 1 })
    eq(byName["Яна Жекова"].status:GetText(), "гледа")
  end)

  it("while I host with a free seat a click on a name offers „Покани“", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    hi(w, B, "MAGE")
    local row = w.ns.Hall.view.peers[1]
    w:click(row.frame); eq(row.invite:IsVisible(), false)
    w.ns.client:openTable{ game = "ttt", access = "invite", turn = 45 }
    w:advance(0)
    w:click(row.frame); ok(row.invite:IsVisible(), "no Покани")
    eq(row.invite.text:GetText(), "Покани")
    w:click(row.invite)
    local inv = lastSent(w, "INV")
    ok(inv, "no INV"); eq(inv.target, B)
  end)

  it("refusals show in the footer for 5 s", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local L, footer = w.ns.L, w.ns.Hall.view.footer
    eq(L("refused.version"), "Трябва ти по-нова версия на Tavern Games.")
    for _, why in ipairs({ "taken", "full", "access", "busy", "gone" }) do
      ok(L("refused." .. why) ~= "refused." .. why, "missing refused." .. why)
    end
    w.ns.client.events:emit("refused", "x#1", "version")
    eq(footer:GetText(), L("refused.version")); ok(footer:IsVisible(), "footer hidden")
    w:advance(3); w.ns.client.events:emit("refused", "x#1", "taken")
    eq(footer:GetText(), L("refused.taken"))
    w:advance(4.9); ok(footer:IsVisible(), "gone too early")
    w:advance(0.2); eq(footer:IsVisible(), false)
  end)

  it("a newer version is announced once", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    eq(w.ns.L("update.available"), "Има по-нова версия на Tavern Games.")
    w:member(B); w:member(C)
    w:deliver("GUILD", B, { v = 2, t = "HI" })
    w:deliver("GUILD", C, { v = 2, t = "HI" })
    w:advance(0)
    eq(#w:chatWith("Има по-нова версия на Tavern Games."), 1)
    eq(#w:texts("Има по-нова версия на Tavern Games."), 1)
  end)
end)

describe("ui: new-table dialog", function()
  it("offers only „Само за удоволствие“, three access options and 30/45/60/90 with 45 preselected", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local D = w.ns.NewTableDialog
    D.open("ttt")
    eq(D.game:GetText(), "Морски шах")
    eq(#D.stake.options, 2); eq(D.stake.options[1].text:GetText(), "Само за удоволствие"); eq(D.stake.value, "none")
    local labels = {}
    for i, o in ipairs(D.access.options) do labels[i] = o.text:GetText() end
    eq(labels, { "Всеки от гилдията", "Само поканени", "Групата ми" }); eq(D.access.value, "guild")
    local turns = {}
    for i, o in ipairs(D.turn.options) do turns[i] = o.value end
    eq(turns, { 30, 45, 60, 90 }); eq(D.turn.value, 45)
  end)

  it("„Отвори“ opens the table with the chosen options and closes the dialog", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local D = w.ns.NewTableDialog
    w:click(w.ns.Hall.view.openButton)
    ok(D.frame:IsVisible(), "dialog hidden")
    w:click(D.access.options[2].frame); w:click(D.turn.options[3].frame)
    eq(D.access.value, "invite"); eq(D.turn.value, 60)
    w:click(D.openButton)
    local s = w.ns.client.session
    ok(s, "no table"); eq({ s.game, s.access, s.turn }, { "ttt", "invite", 60 })
    eq(D.frame:IsShown(), false)
    w:advance(0)
    eq(w.ns.Hall.view.tables[1].tid, s.tid)
  end)

  it("the Death Roll dialog offers the start number, 1000 preselected, and opens with the chosen one", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local D = w.ns.NewTableDialog
    D.open("deathroll")
    eq(D.game:GetText(), "Death Roll")
    eq(#w:texts("Начално число"), 1)
    local g = D.options.start
    eq(#g.options, 4); eq(g.value, 1000); eq(g.options[4].text:GetText(), "100000")
    eq(D.frame:GetHeight(), 364)
    w:click(g.options[3].frame)
    w:click(D.openButton)
    local s = w.ns.client.session
    ok(s, "no table"); eq(s.game, "deathroll"); eq(s.opt, { start = 10000 }); eq(#s.seats, 5)
  end)

  it("the Морски шах dialog has no option row", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local D = w.ns.NewTableDialog
    D.open("deathroll"); D.open("ttt")
    eq(next(D.options), nil)
    eq(D.frame:GetHeight(), 330)
    eq(#w:texts("Начално число"), 0)
    D.open("deathroll")
    eq(D.frame:GetHeight(), 364); eq(#w:texts("Начално число"), 1); eq(D.options.start.value, 1000)
  end)

  it("opening while already at a table shows the busy refusal and keeps the dialog", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    local D = w.ns.NewTableDialog
    D.open("ttt"); w:click(D.openButton)
    ok(D.frame:IsShown(), "dialog closed")
    eq(D.error:GetText(), w.ns.L("refused.busy"))
  end)
end)

describe("ui: minimap", function()
  it("an LDB launcher TavernGames with the mug icon; left click toggles the window", function()
    local w = guildWow()
    local icon = w.icons.TavernGames
    ok(icon, "not registered")
    eq(icon.obj.type, "launcher"); eq(icon.obj.icon, w.ns.Theme.tex.icon)
    ok(icon.db == w.ns.db.minimap, "not the saved minimap table"); eq(icon.shown, true)
    icon.obj.OnClick(nil, "LeftButton"); ok(w.ns.MainWindow.frame:IsShown(), "not opened")
    icon.obj.OnClick(nil, "LeftButton"); eq(w.ns.MainWindow.frame:IsShown(), false)
  end)

  it("setShown hides and shows the button and remembers it", function()
    local w = guildWow()
    w.ns.Minimap.setShown(false)
    eq(w.icons.TavernGames.shown, false); eq(w.ns.db.minimap.hide, true)
    w.ns.Minimap.setShown(true)
    eq(w.icons.TavernGames.shown, true); eq(w.ns.db.minimap.hide, false)
  end)

  it("stays hidden when db.minimap.hide is set", function()
    local w = guildWow()
    w.ns.db.minimap.hide = true
    w:fire("PLAYER_LOGOUT")
    local w2 = guildWow(w.G.TavernGamesDB)
    eq(w2.icons.TavernGames.shown, false)
  end)
end)
