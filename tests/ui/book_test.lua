local Wow = require("wow")

local ME = "Иван Петров"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired.
-- `fresh` keeps the first run pending (no language chosen, intro not seen).
local function guildWow(fresh, saved)
  local w = Wow.new{ ui = true, saved = saved }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot()
  if not fresh then w:firstRunDone() end
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

local function rgba(w, token)
  local c = w.ns.Theme.color[token]
  return { c[1], c[2], c[3], 1 }
end

local function shown(f) return f ~= nil and f:IsShown() end

-- frame.tga nine-slice: a 12 px source band drawn 12 px wide.
local function framed(w, border)
  local corner = border.pieces[1]
  eq(corner:GetTexture(), w.ns.Theme.tex.frame)
  eq({ corner:GetSize() }, { 12, 12 })
  eq(corner.texCoord, { 0, 12 / 64, 0, 12 / 64 })
end

describe("ui: rules book", function()
  it("opens 640x480 on „Залата“ for nil or an unknown topic, framed at 12/12, with four topics", function()
    local w = guildWow()
    local B, L = w.ns.HelpBook, w.ns.L
    B.open()
    ok(shown(B.frame), "not shown")
    eq({ B.frame:GetWidth(), B.frame:GetHeight() }, { 640, 480 })
    eq(B.current, "hall")
    eq(B.title:GetText(), "Книжка с правила")
    framed(w, B.border)
    eq(B.paper.color, rgba(w, "cream"))
    local names = {}
    for i, t in ipairs(B.topics) do names[i] = t.id .. "=" .. t.button.text:GetText() end
    eq(names, { "hall=Залата", "ttt=Морски шах", "deathroll=Death Roll", "soon=Скоро" })
    B.open("nope"); eq(B.current, "hall")
    eq(B.introLink.text:GetText(), "Покажи въведението пак")
    eq(w:newGlobals(), { "SLASH_TAVERNGAMES1", "TavernGamesDB" })
  end)

  it("draws p as text, example as indented italic with a brass rule, board as 3x3 26 px with a gold line", function()
    local w = guildWow()
    local B, L, Theme = w.ns.HelpBook, w.ns.L, w.ns.Theme
    B.open("ttt")
    eq(B.current, "ttt")
    local topic = w.ns.Help.get("ttt")
    local blocks = B.page.blocks
    eq(#blocks, #topic.blocks)
    for i, b in ipairs(topic.blocks) do
      eq(blocks[i].kind, b.kind); eq(blocks[i].text:GetText(), L(b.key)); ok(blocks[i].text:IsVisible(), b.key)
    end
    local p, ex, board = blocks[1], blocks[2], blocks[3]
    eq(p.text:GetFont(), Theme.font.ui)
    eq(ex.text:GetFont(), Theme.font.italic)
    eq(ex.rule.color, rgba(w, "brass")); eq(ex.rule:GetWidth(), 2)
    local _, _, _, px = unpack(p.text.points[1]); local _, _, _, ex_x = unpack(ex.text.points[1])
    ok(ex_x > px, "example not indented")
    -- each block sits below the one before
    local _, _, _, _, y1 = unpack(p.text.points[1]); local _, _, _, _, y2 = unpack(ex.text.points[1])
    ok(y2 < y1, "blocks not stacked")
    eq(#board.cells, 9)
    local gold = rgba(w, "gold")
    for i, cell in ipairs(board.cells) do
      eq({ cell.bg:GetSize() }, { 26, 26 })
      local c = cell.bg.color
      if i <= 3 then eq(c, gold) else ok(not (c[1] == gold[1] and c[2] == gold[2] and c[3] == gold[3]), "cell " .. i .. " is gold") end
    end
    eq(board.cells[1].mark:GetText(), "Х"); eq(board.cells[4].mark:GetText(), "О"); eq(board.cells[6].mark:GetText(), "")
    ok(B.page.scroll.contentHeight > 0, "no content height")
  end)

  it("a topic click switches the page; × closes the book", function()
    local w = guildWow()
    local B, L = w.ns.HelpBook, w.ns.L
    B.open("hall")
    local hallPage = B.page
    w:click(B.topics[4].button)
    eq(B.current, "soon"); eq(hallPage:IsShown(), false); ok(B.page:IsVisible(), "soon page hidden")
    eq(B.page.blocks[1].text:GetText(), L("help.soon.p"))
    eq({ B.topics[4].button.text:GetTextColor() }, rgba(w, "red"))
    w:click(B.topics[1].button); ok(hallPage:IsVisible(), "hall page not back")
    w:click(B.close); eq(B.frame:IsShown(), false)
  end)

  it("ⓘ in the title bar opens „Залата“, ⓘ on a table opens „Морски шах“", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    w:click(w.ns.MainWindow.info)
    eq(w.ns.HelpBook.current, "hall"); ok(w.ns.HelpBook.frame:IsShown(), "book not open")
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    w:click(w.ns.TableFrame.view.info)
    eq(w.ns.HelpBook.current, "ttt")
  end)

  it("the Death Roll topic shows the ladder 1000 › 642 › 87 › 12 › 3 › 1 with the last number red", function()
    local w = guildWow()
    local B, Theme = w.ns.HelpBook, w.ns.Theme
    B.open("deathroll")
    eq(B.current, "deathroll")
    local topic = w.ns.Help.get("deathroll")
    local ladder
    for i, b in ipairs(topic.blocks) do
      eq(B.page.blocks[i].kind, b.kind)
      if b.kind == "ladder" then ladder = B.page.blocks[i] end
    end
    ok(ladder, "no ladder block")
    eq(ladder.text:GetText(), w.ns.L("help.deathroll.ladder"))
    local numbers = {}
    for i, fs in ipairs(ladder.numbers) do
      numbers[i] = fs:GetText()
      ok(fs:IsVisible(), "number " .. i .. " hidden")
      eq(fs:GetFont(), Theme.font.heading)
    end
    eq(numbers, { "1000", "642", "87", "12", "3", "1" })
    eq({ ladder.numbers[6]:GetTextColor() }, rgba(w, "red"))
    ok(not (ladder.numbers[5]:GetTextColor() == Theme.color.red[1]), "only the last one is red")
    eq(#ladder.arrows, 5)
    for _, a in ipairs(ladder.arrows) do eq(a:GetText(), "›") end
    -- ⓘ on a Death Roll table opens this topic.
    B.frame:Hide()
    w.ns.client:openTable{ game = "deathroll", access = "guild", turn = 45, opt = { start = 100 } }
    w:advance(0)
    w:click(w.ns.TableFrame.view.info)
    eq(B.current, "deathroll"); ok(B.frame:IsShown(), "book not open")
  end)

  it("„Покажи въведението пак“ reopens the intro at 1/4", function()
    local w = guildWow()
    w.ns.HelpBook.open()
    w:click(w.ns.HelpBook.introLink)
    ok(shown(w.ns.Intro.frame), "no intro"); eq(w.ns.Intro.step, 1); eq(w.ns.Intro.counter:GetText(), "1/4")
  end)
end)

describe("ui: first run", function()
  it("the first open asks the language; English sets db.lang and the locale, then the intro in English", function()
    local w = guildWow(true)
    local I, MW = w.ns.Intro, w.ns.MainWindow
    w:slash("")
    eq(shown(MW.frame), false)
    ok(shown(I.lang.frame), "no language dialog")
    eq(I.lang.title:GetText(), "Език / Language")
    eq(I.lang.bg.text:GetText(), "Български"); eq(I.lang.en.text:GetText(), "English")
    framed(w, I.lang.border)
    w:click(I.lang.en)
    eq(w.ns.db.lang, "en"); eq(w.ns.Locale.lang(), "en")
    eq(I.lang.frame:IsShown(), false)
    ok(shown(I.frame), "no intro")
    framed(w, I.border)
    eq(I.counter:GetText(), "1/4")
    eq(I.title:GetText(), "The hall"); eq(I.text:GetText(), w.ns.Locale.tables.en["intro.hall.text"])
    eq(I.nextButton.text:GetText(), "Next"); eq(I.skip.text:GetText(), "Skip")
    eq(I.back:IsShown(), false)
    eq(shown(MW.frame), false)
  end)

  it("„Напред“ and „Назад“ walk the 4 cards; finishing sets introDone and opens the hall", function()
    local w = guildWow(true)
    local I, MW, L, Help = w.ns.Intro, w.ns.MainWindow, w.ns.L, w.ns.Help
    w:slash("")
    w:click(I.lang.bg)
    eq(w.ns.db.lang, "bg")
    eq(I.nextButton.text:GetText(), "Напред"); eq(I.back.text:GetText(), "Назад"); eq(I.skip.text:GetText(), "Пропусни")
    for step = 1, 4 do
      eq(I.counter:GetText(), step .. "/4")
      eq(I.title:GetText(), L(Help.intro[step].title)); eq(I.text:GetText(), L(Help.intro[step].text))
      if step < 4 then w:click(I.nextButton) end
    end
    w:click(I.back); eq(I.counter:GetText(), "3/4"); ok(I.back:IsShown(), "no Назад on 3/4")
    w:click(I.nextButton)
    eq(w.ns.db.introDone, false)
    w:click(I.nextButton)
    eq(w.ns.db.introDone, true); eq(I.frame:IsShown(), false)
    ok(shown(MW.frame), "the hall did not open"); eq(MW.current, "hall")
  end)

  it("„Пропусни“ sets introDone and opens the window; later opens skip the first run", function()
    local w = guildWow(true)
    local I, MW = w.ns.Intro, w.ns.MainWindow
    w:slash(""); w:click(I.lang.bg); w:click(I.nextButton)
    w:click(I.skip)
    eq(w.ns.db.introDone, true); eq(I.frame:IsShown(), false); ok(shown(MW.frame), "no window")
    w:slash(""); eq(MW.frame:IsShown(), false)
    w:slash(""); ok(MW.frame:IsShown(), "no window"); eq(I.frame:IsShown(), false); eq(I.lang.frame:IsShown(), false)
  end)

  it("not shown again after a reload; Intro.start(force) only when forced", function()
    local w = guildWow(true)
    local I = w.ns.Intro
    w:slash(""); w:click(I.lang.en); w:click(I.skip)
    w:fire("PLAYER_LOGOUT")
    local w2 = guildWow(true, w.G.TavernGamesDB)
    local I2, MW2 = w2.ns.Intro, w2.ns.MainWindow
    eq(w2.ns.Locale.lang(), "en")
    w2:slash("")
    ok(shown(MW2.frame), "no window"); eq(shown(I2.frame), false); eq(shown(I2.lang.frame), false)
    eq(I2.start(false), false); eq(shown(I2.frame), false)
    w2:slash("intro")
    ok(shown(I2.frame), "/tavern intro did not show it"); eq(I2.counter:GetText(), "1/4")
  end)

  it("a chosen language with the intro unseen goes straight to the intro", function()
    local w = guildWow(true)
    w.ns.db.lang = "bg"
    w.ns.MainWindow.show()
    eq(shown(w.ns.Intro.lang.frame), false); ok(shown(w.ns.Intro.frame), "no intro")
    eq(shown(w.ns.MainWindow.frame), false)
  end)

  it("/tavern reset brings the language dialog back", function()
    local w = guildWow()
    w:slash("reset")
    w:slash("")
    ok(shown(w.ns.Intro.lang.frame), "no language dialog")
  end)
end)

describe("ui: settings", function()
  local function settings(w)
    w.ns.MainWindow.show("settings")
    return w.ns.Settings.view
  end

  it("is the „Настройки“ tab after „Зала“ and shows the addon and protocol versions", function()
    local w = guildWow()
    local MW = w.ns.MainWindow
    MW.show()
    eq(MW.order, { "hall", "settings" })
    eq(MW.tabs.settings.button.text:GetText(), "Настройки")
    local v = settings(w)
    eq(v.version:GetText(), "Версия на аддона: 0.1.0")
    eq(v.protocol:GetText(), "Версия на протокола: 1")
    ok(v.version:IsVisible(), "version hidden")
  end)

  it("language: the saved one is ticked; the other asks to reload with one button", function()
    local w = guildWow()
    local v = settings(w)
    eq(v.langBg.label:GetText(), "Български"); eq(v.langEn.label:GetText(), "English")
    eq(v.langBg.checked, true); eq(v.langEn.checked, false)
    eq(v.reload:IsVisible(), false)
    w:click(v.langEn)
    eq(w.ns.db.lang, "en"); eq(v.langEn.checked, true); eq(v.langBg.checked, false)
    eq(w.ns.Locale.lang(), "bg") -- applied by the reload
    ok(v.reload:IsVisible(), "no reload prompt")
    eq(v.reloadButton.text:GetText(), "Презареди")
    eq(w.reloads, 0)
    w:click(v.reloadButton)
    eq(w.reloads, 1)
    w:click(v.langBg)
    eq(w.ns.db.lang, "bg"); eq(v.reload:IsVisible(), false)
  end)

  it("„Зает съм (не приемам покани)“ sets db.busy and keeps invitation toasts away", function()
    local w = guildWow()
    local v = settings(w)
    eq(v.busy.label:GetText(), "Зает съм (не приемам покани)")
    eq(v.busy.checked, false); eq(v.busy.mark:IsShown(), false)
    w:click(v.busy)
    eq(w.ns.db.busy, true); eq(v.busy.checked, true); ok(v.busy.mark:IsShown(), "no tick")
    w:slash("bots invite"); w:advance(0); w:advance(0); w:advance(0)
    eq(shown(w.ns.InviteToast.frame), false)
    w:click(v.busy)
    eq(w.ns.db.busy, false)
  end)

  it("the minimap button switch hides and shows the button", function()
    local w = guildWow()
    local v = settings(w)
    eq(v.minimap.checked, true)
    w:click(v.minimap)
    eq(w.icons.TavernGames.shown, false); eq(w.ns.db.minimap.hide, true); eq(v.minimap.checked, false)
    w:click(v.minimap)
    eq(w.icons.TavernGames.shown, true); eq(w.ns.db.minimap.hide, false)
  end)

  it("„Покажи въведението“ starts the intro", function()
    local w = guildWow()
    local v = settings(w)
    eq(v.introButton.text:GetText(), "Покажи въведението")
    w:click(v.introButton)
    ok(shown(w.ns.Intro.frame), "no intro"); eq(w.ns.Intro.counter:GetText(), "1/4")
  end)
end)
