local Wow = require("wow")

local ME = "Иван Петров"
local BOT = "Бот Иванов"

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
  it("opens 640x520 on „Залата“ for nil or an unknown topic, framed at 12/12, with thirteen topics", function()
    local w = guildWow()
    local B, L = w.ns.HelpBook, w.ns.L
    B.open()
    ok(shown(B.frame), "not shown")
    eq({ B.frame:GetWidth(), B.frame:GetHeight() }, { 640, 520 })
    eq(B.current, "hall")
    eq(B.title:GetText(), "Книжка с правила")
    framed(w, B.border)
    eq(B.paper.color, rgba(w, "cream"))
    local names = {}
    for i, t in ipairs(B.topics) do names[i] = t.id .. "=" .. t.button.text:GetText() end
    eq(names, { "hall=Залата", "ttt=Морски шах", "deathroll=Death Roll", "santase=Сантасе", "belot=Белот", "tabla=Табла", "holdem=Тексас Холдем", "fair=Защо раздаването е честно", "stakes=Залози", "ledger=Тефтер", "board=Класация", "history=История", "soon=Скоро" })
    -- a long title wraps inside the list and its row grows to hold it
    for _, t in ipairs(B.topics) do
      local fs = t.button.text
      ok(fs:GetWidth() <= 150, t.id .. " title wider than the list")
      ok(t.button:GetHeight() >= fs:GetStringHeight(), t.id .. " title taller than its row")
    end
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
    w:click(B.topics[13].button)
    eq(B.current, "soon"); eq(hallPage:IsShown(), false); ok(B.page:IsVisible(), "soon page hidden")
    eq(B.page.blocks[1].text:GetText(), L("help.soon.p"))
    eq({ B.topics[13].button.text:GetTextColor() }, rgba(w, "red"))
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

  it("the stakes and ledger topics draw their blocks; the ⓘ of „Тефтер“ opens the ledger topic; the thirteen rows fit above the intro link", function()
    local w = guildWow()
    local B, L, Help = w.ns.HelpBook, w.ns.L, w.ns.Help
    for _, id in ipairs({ "stakes", "ledger" }) do
      B.open(id)
      eq(B.current, id)
      local topic = Help.get(id)
      eq(#B.page.blocks, #topic.blocks)
      for i, b in ipairs(topic.blocks) do
        eq(B.page.blocks[i].kind, b.kind); eq(B.page.blocks[i].text:GetText(), L(b.key)); ok(B.page.blocks[i].text:IsVisible(), b.key)
      end
    end
    B.open("fair")
    local keys = {}
    for i, b in ipairs(B.page.blocks) do keys[i] = b.text:GetText() end
    ok(w.ns.Util.contains(keys, L("help.fair.stakes")), "no stakes block in the fair topic")
    B.frame:Hide()
    w.ns.MainWindow.show("ledger")
    w:click(w.ns.MainWindow.info)
    eq(B.current, "ledger"); ok(B.frame:IsShown(), "book not open")
    -- The list starts 62 px below the top; the body (and the list) end 56 px above the bottom.
    for _, lang in ipairs({ "bg", "en" }) do
      w.ns.Locale.set(lang)
      B.open("hall")
      local last = B.topics[#B.topics].button
      local _, _, _, _, y = unpack(last.points[1])
      ok(-y + last:GetHeight() <= B.HEIGHT - 56, lang .. ": the last topic row ends at " .. (-y + last:GetHeight()))
    end
    w.ns.Locale.set("bg")
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
    for i = 1, 5 do eq({ ladder.numbers[i]:GetTextColor() }, rgba(w, "woodDark"), "number " .. i) end
    eq(#ladder.arrows, 5)
    for _, a in ipairs(ladder.arrows) do eq(a:GetText(), "›") end
    -- ⓘ on a Death Roll table opens this topic.
    B.frame:Hide()
    w.ns.client:openTable{ game = "deathroll", access = "guild", turn = 45, opt = { start = 100 } }
    w:advance(0)
    w:click(w.ns.TableFrame.view.info)
    eq(B.current, "deathroll"); ok(B.frame:IsShown(), "book not open")
  end)

  it("the Сантасе topic draws its cards; ⓘ on a Сантасе table opens it; the fair topic is reachable", function()
    local w = guildWow()
    w:slash("bots")
    w:advance(0); w:advance(0)
    local B, L = w.ns.HelpBook, w.ns.L
    B.open("santase")
    eq(B.current, "santase")
    local topic = w.ns.Help.get("santase")
    local cards = {}
    for i, b in ipairs(topic.blocks) do
      local block = B.page.blocks[i]
      eq(block.kind, b.kind); eq(block.text:GetText(), L(b.key)); ok(block.text:IsVisible(), b.key)
      if b.kind == "cards" then
        local _, _, _, _, textY = unpack(block.text.points[1])
        for _, c in ipairs(block.cards) do
          cards[#cards + 1] = c
          ok(c.frame:IsVisible(), "card " .. tostring(c.face) .. " hidden")
          eq(c.scale, 0.8)
          local _, _, _, _, cardY = unpack(c.frame.points[1])
          ok(cardY > textY, "card " .. c.face .. " not above its text")
        end
        -- 4 px apart
        for k = 2, #block.cards do
          local _, _, _, x1 = unpack(block.cards[k - 1].frame.points[1])
          local _, _, _, x2 = unpack(block.cards[k].frame.points[1])
          eq(x2 - x1, w.ns.Cards.W * 0.8 + 4)
        end
      end
    end
    eq(#cards, 8)
    eq(cards[1].face, "AS"); eq(cards[1].rank:GetText(), "A")
    eq(cards[7].face, "KH"); eq(cards[7].rank:GetText(), "K")
    eq(cards[8].face, "QH"); eq(cards[8].rank:GetText(), "Q")
    eq({ cards[7].rank:GetTextColor() }, rgba(w, "red")); eq({ cards[8].rank:GetTextColor() }, rgba(w, "red"))
    eq({ cards[1].rank:GetTextColor() }, rgba(w, "cardInk"))

    B.open("fair")
    eq(B.current, "fair")
    local starts = 0
    for _, block in ipairs(B.page.blocks) do
      local t = block.text:GetText()
      if block.text:IsVisible() and t:sub(1, #"В игрите с карти никой не разбърква тестето сам") == "В игрите с карти никой не разбърква тестето сам" then
        starts = starts + 1
      end
    end
    eq(starts, 1)

    B.frame:Hide()
    w.ns.client:openTable{ game = "santase", access = "invite", turn = 45 }
    w:advance(0)
    local v = w.ns.TableFrame.view
    w:click(v.inviteButton)
    local row
    for _, r in ipairs(v.picker.rows) do
      if r.frame:IsVisible() and r.name:GetText() == BOT then row = r end
    end
    assert(row, "no row for the bot in the picker")
    w:click(row.frame)
    w:advance(2)
    w:click(w.ns.TableFrame.view.info)
    eq(B.current, "santase"); ok(B.frame:IsShown(), "book not open")
  end)

  it("the Белот topic draws its cards and is listed between Сантасе and the fair deal", function()
    local w = guildWow()
    local B, L = w.ns.HelpBook, w.ns.L
    B.open()
    local names = {}
    for i, t in ipairs(B.topics) do names[i] = t.id .. "=" .. t.button.text:GetText() end
    eq(names[4], "santase=Сантасе"); eq(names[5], "belot=Белот"); eq(names[8], "fair=Защо раздаването е честно")
    B.open("belot")
    eq(B.current, "belot")
    local topic = w.ns.Help.get("belot")
    local cards = {}
    for i, b in ipairs(topic.blocks) do
      local block = B.page.blocks[i]
      eq(block.kind, b.kind); eq(block.text:GetText(), L(b.key)); ok(block.text:IsVisible(), b.key)
      if b.kind == "cards" then
        for _, c in ipairs(block.cards) do
          cards[#cards + 1] = c
          ok(c.frame:IsVisible(), "card " .. tostring(c.face) .. " hidden")
        end
      end
    end
    eq(#cards, 11)
    eq(cards[1].face, "JH"); eq(cards[1].rank:GetText(), "J")
    eq({ cards[1].rank:GetTextColor() }, rgba(w, "red"))
    eq(cards[10].face, "KS"); eq(cards[10].rank:GetText(), "K")
    eq(cards[11].face, "QS"); eq(cards[11].rank:GetText(), "Q")
    eq({ cards[10].rank:GetTextColor() }, rgba(w, "cardInk")); eq({ cards[11].rank:GetTextColor() }, rgba(w, "cardInk"))
  end)

  it("the Табла topic draws its dice and is listed between Белот and the fair deal", function()
    local w = guildWow()
    local B, L = w.ns.HelpBook, w.ns.L
    B.open()
    local names = {}
    for i, t in ipairs(B.topics) do names[i] = t.id .. "=" .. t.button.text:GetText() end
    eq(names, { "hall=Залата", "ttt=Морски шах", "deathroll=Death Roll", "santase=Сантасе", "belot=Белот", "tabla=Табла", "holdem=Тексас Холдем", "fair=Защо раздаването е честно", "stakes=Залози", "ledger=Тефтер", "board=Класация", "history=История", "soon=Скоро" })
    B.open("tabla")
    eq(B.current, "tabla")
    local topic = w.ns.Help.get("tabla")
    local rows = {}
    for i, b in ipairs(topic.blocks) do
      local block = B.page.blocks[i]
      eq(block.kind, b.kind); eq(block.text:GetText(), L(b.key)); ok(block.text:IsVisible(), b.key)
      if b.kind == "dice" then
        rows[#rows + 1] = block.dice
        for _, d in ipairs(block.dice) do
          ok(d:IsVisible(), "a die is hidden"); eq(d:GetTexture(), w.ns.Theme.tex.dice)
        end
      end
    end
    eq(#rows, 2); eq(#rows[1], 2); eq(#rows[2], 3)
    local six, three = rows[1][1], rows[1][2]
    eq(six.texCoord, { 0.25, 0.5, 0.5, 1 }); eq(three.texCoord, { 0.5, 0.75, 0, 0.5 })
    eq({ six:GetSize() }, { 28, 28 }); eq({ three:GetSize() }, { 28, 28 })
    local _, _, _, x1, y1 = unpack(six.points[1]); local _, _, _, x2, y2 = unpack(three.points[1])
    eq(x2 - x1, 34); eq(y2, y1)
    -- the text sits below its dice
    local _, _, _, _, ty = unpack(B.page.blocks[3].text.points[1])
    ok(ty <= y1 - 28, "the text is not below the dice")
    eq(rows[2][3].texCoord, { 0.25, 0.5, 0.5, 1 })
    B.open("fair")
    local blocks = B.page.blocks
    eq(blocks[#blocks - 1].text:GetText(), L("help.fair.dice"))
  end)

  it("the Тексас Холдем topic is listed between Табла and the fair deal and draws its two rows of cards", function()
    local w = guildWow()
    local B, L = w.ns.HelpBook, w.ns.L
    B.open()
    local names = {}
    for i, t in ipairs(B.topics) do names[i] = t.id .. "=" .. t.button.text:GetText() end
    eq(names[6], "tabla=Табла"); eq(names[7], "holdem=Тексас Холдем"); eq(names[8], "fair=Защо раздаването е честно")
    B.open("holdem")
    eq(B.current, "holdem"); eq(w.ns.HelpBook.current, "holdem")
    local topic = w.ns.Help.get("holdem")
    local rows = {}
    for i, b in ipairs(topic.blocks) do
      local block = B.page.blocks[i]
      eq(block.kind, b.kind); eq(block.text:GetText(), L(b.key)); ok(block.text:IsVisible(), b.key)
      if b.kind == "cards" then rows[#rows + 1] = block.cards end
    end
    eq(#rows, 2); eq(#rows[1], 5); eq(#rows[2], 5)
    B.open("fair")
    local blocks = B.page.blocks
    eq(blocks[#blocks].text:GetText(), L("help.fair.sealed"))
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
      -- Spec 5.3а: hall, sitting, paying („Сметки“ -> „Плати“), the ⓘ book.
      eq(I.title:GetText(), ({ "Залата", "Сядане", "Сметки и плащане", "Книжката с правила" })[step])
      if step == 3 then
        ok(I.text:GetText():find("„Сметки“", 1, true) and I.text:GetText():find("„Плати“", 1, true), "the payment step names „Сметки“ and „Плати“")
      end
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
    eq(MW.order, { "hall", "ledger", "board", "history", "settings" })
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
