local ns = Loader.ns()
local T = ns.Locale.tables

-- Number of string.format placeholders in s ("%%" is a literal percent sign).
local function placeholders(s)
  local _, n = s:gsub("%%%%", ""):gsub("%%", "")
  return n
end

local function both(key, what)
  ok(type(T.bg[key]) == "string", what .. " missing in bg: " .. tostring(key))
  ok(type(T.en[key]) == "string", what .. " missing in en: " .. tostring(key))
end

describe("locale and help", function()
  it("bg and en have the same keys and the same number of % placeholders per key", function()
    ok(next(T.bg) ~= nil, "bg is empty")
    for k in pairs(T.bg) do ok(T.en[k], "missing in en: " .. k) end
    for k in pairs(T.en) do ok(T.bg[k], "missing in bg: " .. k) end
    for k, v in pairs(T.bg) do
      if T.en[k] then eq(placeholders(T.en[k]), placeholders(v), k) end
    end
  end)

  it("every help block and intro key exists in both languages; topics are hall, ttt, deathroll, santase, belot, tabla, holdem, fair, stakes, ledger, soon", function()
    local H = ns.Help
    local ids = {}
    for i, t in ipairs(H.topics) do ids[i] = t.id end
    eq(ids, { "hall", "ttt", "deathroll", "santase", "belot", "tabla", "holdem", "fair", "stakes", "ledger", "soon" })
    eq(#H.intro, 4)
    for _, t in ipairs(H.topics) do
      both(t.title, "topic title")
      local examples = 0
      for _, b in ipairs(t.blocks) do
        both(b.key, "block key")
        if b.kind == "example" then examples = examples + 1 end
        ok(b.kind == "p" or b.kind == "example" or b.kind == "board" or b.kind == "ladder" or b.kind == "cards" or b.kind == "dice", "bad kind " .. tostring(b.kind))
      end
      ok(examples >= 1, "no example in " .. t.id)
      eq(H.get(t.id), t)
    end
    for _, step in ipairs(H.intro) do both(step.title, "intro title"); both(step.text, "intro text") end
    local boards = {}
    for _, b in ipairs(H.get("ttt").blocks) do
      if b.kind == "board" then boards[#boards + 1] = b end
    end
    eq(#boards, 1); eq(#boards[1].board, 9); eq(#boards[1].line, 3)
    local b = boards[1]
    for _, c in ipairs(b.line) do eq(b.board[c], b.board[b.line[1]]); ok(b.board[c] ~= 0) end
    local dr = H.get("deathroll")
    eq(dr.title, "game.deathroll")
    local ladders = {}
    for _, lb in ipairs(dr.blocks) do
      if lb.kind == "ladder" then ladders[#ladders + 1] = lb end
    end
    eq(#ladders, 1); eq(ladders[1].key, "help.deathroll.ladder"); eq(ladders[1].rolls, { 1000, 642, 87, 12, 3, 1 })
    local sa = H.get("santase")
    eq(sa.title, "game.santase")
    local hands, deck = {}, {}
    for _, f in ipairs(ns.Engines.santase.DECK) do deck[f] = true end
    for _, cb in ipairs(sa.blocks) do
      if cb.kind == "cards" then
        hands[#hands + 1] = cb.cards
        for _, f in ipairs(cb.cards) do ok(deck[f], "not a Сантасе card: " .. tostring(f)) end
      end
    end
    eq(hands, { { "AS", "TS", "KS", "QS", "JS", "9S" }, { "KH", "QH" } })
    local be = H.get("belot")
    eq(be.title, "game.belot")
    local kinds = {}
    for i, bb in ipairs(be.blocks) do kinds[i] = bb.key end
    eq(kinds, { "help.belot.p1", "help.belot.example", "help.belot.bids", "help.belot.contra", "help.belot.cards", "help.belot.trick",
      "help.belot.announce", "help.belot.belote", "help.belot.score", "help.belot.valat", "help.belot.time", "help.belot.fair" })
    local bhands, bdeck = {}, {}
    for _, f in ipairs(ns.Engines.belot.DECK) do bdeck[f] = true end
    for _, cb in ipairs(be.blocks) do
      if cb.kind == "cards" then
        bhands[#bhands + 1] = cb.cards
        for _, f in ipairs(cb.cards) do ok(bdeck[f], "not a Белот card: " .. tostring(f)) end
      end
    end
    eq(bhands, { { "JH", "9H", "AH", "TH", "KH", "QH" }, { "9H", "TH", "JH" }, { "KS", "QS" } })
    eq(be.blocks[5].kind, "cards"); eq(be.blocks[7].kind, "cards"); eq(be.blocks[8].kind, "cards")
    local ta = H.get("tabla")
    eq(ta.title, "game.tabla")
    local tkeys, tkinds, rows = {}, {}, {}
    for i, tb in ipairs(ta.blocks) do
      tkeys[i], tkinds[i] = tb.key, tb.kind
      if tb.kind == "dice" then
        rows[#rows + 1] = tb.dice
        for _, n in ipairs(tb.dice) do ok(type(n) == "number" and n % 1 == 0 and n >= 1 and n <= 6, "not a die: " .. tostring(n)) end
      end
    end
    eq(tkeys, { "help.tabla.p1", "help.tabla.example", "help.tabla.move", "help.tabla.staging", "help.tabla.std", "help.tabla.bearoff",
      "help.tabla.tapa", "help.tabla.gul", "help.tabla.score", "help.tabla.time", "help.tabla.fair" })
    eq(tkinds, { "p", "example", "dice", "p", "p", "p", "p", "dice", "p", "p", "p" })
    eq(rows, { { 6, 3 }, { 4, 5, 6 } })
    eq(H.get("fair").title, "help.fair.title")
    local fb = H.get("fair").blocks
    eq(fb[#fb], { kind = "p", key = "help.fair.sealed" })
    eq(fb[#fb - 1], { kind = "p", key = "help.fair.dice" })
    eq(H.get("nope"), nil)
  end)

  it("every quoted label in the hall, ttt, deathroll, santase, belot, tabla, holdem, fair, stakes, ledger and soon help is a UI label, and no help title copies one", function()
    local QUOTES = { bg = { "„", "“" }, en = { "“", "”" } }
    for lang, q in pairs(QUOTES) do
      local ui, shapes = {}, {}
      for k, v in pairs(T[lang]) do
        if not k:match("^help%.") and not k:match("^intro%.") then
          ui[v] = true
          -- A UI text with %s / %d, as the stakes and ledger help quote it filled in („Дължиш на Мария Колева 1g“).
          if v:find("%%[sd]") then
            shapes[#shapes + 1] = "^" .. v:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"):gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+") .. "$"
          end
        end
      end
      local function filled(label)
        for _, p in ipairs(shapes) do if label:find(p) then return true end end
        return false
      end
      local checked, cards, belot, tabla, holdem, money = 0, 0, 0, 0, 0, 0
      for k, text in pairs(T[lang]) do
        local isMoney = k:match("^help%.stakes%.") or k:match("^help%.ledger%.")
        local card = k:match("^help%.santase%.") or k:match("^help%.fair%.")
        local isBelot = k:match("^help%.belot%.")
        local isTabla = k:match("^help%.tabla%.")
        local isHoldem = k:match("^help%.holdem%.")
        if card or isBelot or isTabla or isHoldem or isMoney or k:match("^help%.hall%.") or k:match("^help%.ttt%.") or k:match("^help%.deathroll%.") or k == "help.soon.example" then
          local pos = 1
          while true do
            local a, b = text:find(q[1], pos, true)
            if not a then break end
            local c, d = text:find(q[2], b + 1, true)
            ok(c, lang .. " " .. k .. ": unclosed quote")
            if not c then break end
            local label = text:sub(b + 1, c - 1)
            ok(ui[label] or (isMoney and filled(label)), lang .. " " .. k .. ": „" .. label .. "“ is not a UI label")
            checked = checked + 1
            if isMoney then money = money + 1 end
            if card then cards = cards + 1 end
            if isBelot then belot = belot + 1 end
            if isTabla then tabla = tabla + 1 end
            if isHoldem then holdem = holdem + 1 end
            pos = d + 1
          end
        end
      end
      ok(checked >= 26, lang .. ": only " .. checked .. " quoted labels found")
      ok(cards >= 8, lang .. ": only " .. cards .. " quoted labels in the santase and fair help")
      ok(belot >= 12, lang .. ": only " .. belot .. " quoted labels in the belot help")
      ok(tabla >= 10, lang .. ": only " .. tabla .. " quoted labels in the tabla help")
      ok(holdem >= 12, lang .. ": only " .. holdem .. " quoted labels in the holdem help")
      ok(money >= 20, lang .. ": only " .. money .. " quoted labels in the stakes and ledger help")
      for k, v in pairs(T[lang]) do
        if k:match("^help%.") and k:match("%.title$") then ok(not ui[v], lang .. " " .. k .. " copies a UI label") end
      end
    end
  end)

  it("the stakes and ledger topics: their blocks, the pinned example, every label they must name; fair gains the stakes block; the intro's payment step", function()
    local H = ns.Help
    local function keys(id)
      local out = {}
      for i, b in ipairs(H.get(id).blocks) do out[i] = b.kind .. " " .. b.key end
      return out
    end
    eq(H.get("stakes").title, "help.stakes.title"); eq(T.bg["help.stakes.title"], "Залози")
    eq(keys("stakes"), { "p help.stakes.p1", "p help.stakes.accept", "example help.stakes.example", "p help.stakes.deathroll",
      "example help.stakes.belot", "p help.stakes.leave", "p help.stakes.again", "p help.stakes.honest", "p help.stakes.cards",
      "p help.stakes.tabla", "p help.stakes.holdem", "example help.stakes.holdem.example", "p help.stakes.holdem.rebuy",
      "p help.stakes.holdem.stand", "p help.stakes.holdem.dealer" })
    eq(H.get("ledger").title, "tab.ledger")
    eq(keys("ledger"), { "p help.ledger.p1", "p help.ledger.pay.trade", "p help.ledger.pay.mail", "p help.ledger.settle",
      "example help.ledger.net", "p help.ledger.alts", "p help.ledger.holds", "p help.ledger.mine" })
    eq(T.bg["help.stakes.example"], "Иван и Мария играят Морски шах за 1g. Мария печели. Иван вижда в „Сметки“: „Дължиш на Мария Колева 1g“ и натиска „Плати“.")
    -- Each label below is the whole text of a UI key and is quoted in the two topics, in both languages.
    local LABELS = { "accounts.title", "accounts.pay", "accounts.settle", "accounts.nudge", "table.stand", "dialog.stake.gold",
      "dialog.stake.none", "stake.ask.yes", "ask.yes", "ask.no", "pay.trade", "pay.mail", "tab.ledger",
      "ask.mine.yes", "ask.mine.no", "ledger.denied" } -- the final review: the own-entries question and the mark „отречено“
    eq(T.bg["accounts.title"] .. " " .. T.bg["dialog.stake.none"] .. " " .. T.bg["stake.ask.yes"], "Сметки Само за удоволствие Приемам и сядам")
    for lang, q in pairs({ bg = { "„", "“" }, en = { "“", "”" } }) do
      local text = {}
      for _, id in ipairs({ "stakes", "ledger" }) do
        for _, b in ipairs(H.get(id).blocks) do text[#text + 1] = T[lang][b.key] end
      end
      text = table.concat(text, " ")
      for _, k in ipairs(LABELS) do
        ok(text:find(q[1] .. T[lang][k] .. q[2], 1, true), lang .. ": the stakes and ledger help never quote " .. k)
      end
    end
    -- What the final review changed, said where a player will look for it.
    ok(T.bg["help.ledger.pay.mail"]:find("остава в „Сметки“", 1, true), "the letter on its way is not said")
    ok(T.bg["help.stakes.honest"]:find("станеш сам", 1, true), "my own stand after a foul is not said")
    local fb = {}
    for i, b in ipairs(H.get("fair").blocks) do fb[i] = b.key end
    eq(fb, { "help.fair.p1", "help.fair.example", "help.fair.how", "help.fair.verify", "help.fair.dealer", "help.fair.bad",
      "help.fair.stakes", "help.fair.dice", "help.fair.sealed" })
    ok(T.bg["help.fair.stakes"]:find("аддонът ти сам оспорва дълга", 1, true), "the fair stakes block")
    eq(H.intro[3], { title = "intro.pay.title", text = "intro.pay.text" })
    eq(T.bg["intro.invite.title"], nil); eq(T.en["intro.invite.text"], nil)
  end)

  it("stage F2 in the stakes topic: the four new blocks, the pinned sentences, the labels they quote, no game of the five left for fun", function()
    for _, k in ipairs({ "help.stakes.belot", "help.stakes.cards", "help.stakes.tabla", "help.stakes.again" }) do both(k, "F2 block") end
    eq(T.bg["help.stakes.belot"], "Иван и Мария играят Белот срещу Петър и Гошо за 1g. Иван и Мария губят. Иван плаща 1g на Петър, а Мария плаща 1g на Гошо. Ако Мария напусне по средата, тя плаща по 1g на Петър и на Гошо, а Иван не дължи нищо.")
    local PINNED = {
      ["help.stakes.cards"] = "Ако една ръка излезе „нередовна“ при теб, аддонът ти оспорва дълга сам.",
      ["help.stakes.tabla"] = "Ако домакинът хвърли без твоето число, аддонът ти оспорва дълга сам.",
      ["help.stakes.again"] = "Останеш ли на масата, играеш и следващата игра за същия залог.",
      ["help.stakes.leave"] = "Дължиш залога на всеки, който е още в играта, освен на партньора си в Белот.", -- ruling G19
    }
    for k, s in pairs(PINNED) do ok(T.bg[k]:find(s, 1, true), k .. " lacks its pinned sentence") end
    ok(T.en["help.stakes.leave"]:find("except your partner in Belot", 1, true), "the Белот partner is not in the en leave block")
    -- Review Focus 5: a slow connection at a throw can contest an honest loss, and the players settle it by word.
    ok(T.bg["help.stakes.tabla"]:find("Бавна връзка", 1, true) and T.bg["help.stakes.tabla"]:find("на думи", 1, true), "the honest cost of D3")
    ok(T.en["help.stakes.tabla"]:find("slow connection", 1, true) and T.en["help.stakes.tabla"]:find("by word", 1, true), "the honest cost of D3 (en)")
    ok(T.bg["help.stakes.again"]:find("30 секунди", 1, true) and T.en["help.stakes.again"]:find("30 seconds", 1, true), "the break")
    -- Residual 26: a letter guards its debt for 30 days, no longer a day.
    ok(T.bg["help.ledger.pay.mail"]:find("30 дни", 1, true) and not T.bg["help.ledger.pay.mail"]:find("денонощие", 1, true), "the mail guard is not 30 days")
    ok(T.en["help.ledger.pay.mail"]:find("30 days", 1, true) and not T.en["help.ledger.pay.mail"]:find("within a day", 1, true), "the mail guard is not 30 days (en)")
    -- The labels the new texts quote are the texts of their UI keys, in both languages.
    local QUOTED = { { "help.stakes.again", "table.toHall" }, { "help.stakes.cards", "fair.v.bad" }, { "help.ledger.pay.mail", "accounts.settle" } }
    for lang, q in pairs({ bg = { "„", "“" }, en = { "“", "”" } }) do
      for _, p in ipairs(QUOTED) do
        ok(T[lang][p[1]]:find(q[1] .. T[lang][p[2]] .. q[2], 1, true), lang .. ": " .. p[1] .. " does not quote " .. p[2])
      end
      eq(T[lang]["help.stakes.belot"]:find(q[1], 1, true), nil, lang .. ": the Белот example quotes nothing")
    end
    eq(T.bg["table.toHall"] .. " / " .. T.bg["fair.v.bad"] .. " / " .. T.bg["accounts.settle"], "Към залата / нередовна / Уредено")
    -- No sentence of the stakes or soon help still keeps Сантасе, Белот or Табла for fun, or for later.
    local LATER = { bg = { names = { "Сантасе", "Белот", "Табла" }, words = { "удоволствие", "скоро", "засега", "Засега" } },
      en = { names = { "Santase", "Belot", "Backgammon" }, words = { "for fun", "soon", "for now", "For now" } } }
    for lang, w in pairs(LATER) do
      local seen = 0
      for k, text in pairs(T[lang]) do
        if k:match("^help%.stakes%.") or k:match("^help%.soon%.") then
          seen = seen + 1
          for sentence in (text .. " "):gmatch("(.-[%.%?!:])%s") do
            for _, g in ipairs(w.names) do
              if sentence:find(g, 1, true) then
                for _, word in ipairs(w.words) do ok(not sentence:find(word, 1, true), lang .. " " .. k .. ": „" .. sentence .. "“") end
              end
            end
          end
        end
      end
      ok(seen >= 13, lang .. ": only " .. seen .. " stakes and soon texts")
    end
    -- The five games are named where the stake is introduced.
    for _, g in ipairs({ "Морски шах", "Death Roll", "Сантасе", "Белот", "Табла" }) do ok(T.bg["help.stakes.p1"]:find(g, 1, true), "p1 lacks " .. g) end
    for _, g in ipairs({ "Tic-tac-toe", "Death Roll", "Santase", "Belot", "Backgammon" }) do ok(T.en["help.stakes.p1"]:find(g, 1, true), "p1 lacks " .. g .. " (en)") end
  end)

  it("stage F3 in the stakes topic: the five Холдем blocks, bg and en, used verbatim", function()
    local BG = {
      ["help.stakes.holdem"] = "В Холдем със залог всеки сяда с вход между 40 и 100 големи блайнда. Един чип е един силвър. Докато играете, не се мести голд: аддонът помни за всеки пот от кого е дошъл всеки силвър.",
      ["help.stakes.holdem.example"] = "Иван, Мария и Kiro играят на 10s/20s. Kiro печели пот от 1g 20s: 40s са от Иван и 80s от Мария. По-късно Иван взима 30s от Kiro. Kiro става: Иван му дължи 10s, Мария му дължи 80s. Сборът по двойки е точно печалбата на Kiro.",
      ["help.stakes.holdem.rebuy"] = "Докупуването се избира при отваряне на масата: „Без“, „Когато свършат чиповете“ или „Винаги до входа“. Станеш ли и седнеш ли пак в същата игра, не получаваш нови чипове даром: носиш поне това, с което си станал.",
      ["help.stakes.holdem.stand"] = "„Стани“ записва сметката ти след края на ръката. Изчезнеш ли за 3 минути, аддонът те вдига сам и записва сметката. Дълговете се потвърждават сами, когато домакинът натисне „Приключи“ и ръцете се проверят с ключовете. Станеш ли по-рано, аддонът те пита за всеки твой дълг.",
      ["help.stakes.holdem.dealer"] = "Аддонът на раздаващия знае тестето на ръката, която раздава. В Холдем това са картите на всички. Играй Холдем за голд само с хора, на които вярваш. Раздаващият може и да анулира ръка, като замълчи, когато е негов ред: чиповете се връщат, а анулирането се брои по име.",
    }
    for k, v in pairs(BG) do
      eq(T.bg[k], v)
      ok(type(T.en[k]) == "string" and T.en[k] ~= "", "en lacks " .. k)
    end
    -- The labels they quote are the texts of their UI keys; the S1 warning and the C9 void are said.
    for lang, q in pairs({ bg = { "„", "“" }, en = { "“", "”" } }) do
      for _, p in ipairs({ { "help.stakes.holdem.rebuy", "optv.holdem.rebuy.none" }, { "help.stakes.holdem.rebuy", "optv.holdem.rebuy.bust" },
        { "help.stakes.holdem.rebuy", "optv.holdem.rebuy.top" }, { "help.stakes.holdem.stand", "table.stand" }, { "help.stakes.holdem.stand", "holdem.close" },
        { "help.holdem.stake", "cash.panel" }, { "help.holdem.stake", "cash.rebuy" }, { "help.holdem.stake", "cash.standNow" } }) do
        ok(T[lang][p[1]]:find(q[1] .. T[lang][p[2]] .. q[2], 1, true), lang .. ": " .. p[1] .. " does not quote " .. p[2])
      end
    end
    ok(T.bg["help.stakes.holdem.dealer"]:find("картите на всички", 1, true) and T.bg["help.stakes.holdem.dealer"]:find("брои по име", 1, true), "S1 and C9")
    ok(T.en["help.stakes.holdem.dealer"]:find("everybody's cards", 1, true) and T.en["help.stakes.holdem.dealer"]:find("counted by name", 1, true), "S1 and C9 (en)")
    ok(T.bg["help.stakes.p1"]:find("Холдем", 1, true) and T.en["help.stakes.p1"]:find("Hold'em", 1, true), "p1 names Холдем")
  end)

  it("pinned texts are used verbatim", function()
    eq(T.bg["help.ttt.example"], "Иван е Х, Мария е О. Редуват се. Иван нарежда три Х в редица и печели играта. Който пръв спечели 3 игри, печели мача.")
    eq(T.bg["help.hall.example"], "Виждаш маса с празен стол с пунктир. Кликаш на стола и вече седиш. Ако масата е пълна, кликни на нея, за да гледаш.")
    -- Stage F3: every game takes a stake; no game is named as coming (H18d).
    eq(T.bg["help.soon.p"], "Залози има на всички игри в механата.")
    eq(T.bg["help.soon.example"], "Искаш да играеш Холдем за злато? Отвори маса „Със залог“ и избери блайндовете.")
    ok(not T.bg["help.soon.example"]:find("всички игри", 1, true) and not T.en["help.soon.example"]:find("all the games", 1, true), "„soon“ still says every game is for fun")
    for _, g in ipairs({ "Морски шах", "Death Roll", "Сантасе", "Белот", "Табла" }) do
      ok(not T.bg["help.soon.example"]:find(g, 1, true), "„soon“ lists a game that takes a stake: " .. g)
    end
    for _, w in ipairs({ "скоро", "Още не може", "Засега" }) do ok(not T.bg["help.soon.p"]:find(w, 1, true) and not T.bg["help.soon.example"]:find(w, 1, true), "„soon“ still says coming: " .. w) end
    eq(T.en["help.soon.p"], "There are stakes on all the games in the tavern.")
    eq(T.en["help.soon.example"], "Want to play Hold'em for gold? Open a table “For a stake” and choose the blinds.")
    for _, w in ipairs({ "soon", "Not yet", "For now" }) do ok(not T.en["help.soon.p"]:find(w, 1, true) and not T.en["help.soon.example"]:find(w, 1, true), "„soon“ still says coming (en): " .. w) end
    eq(T.bg["help.holdem.limits"], "„Без лимит“: можеш да заложиш всичките си чипове по всяко време, с бутона за ва банк. „Пот лимит“: най-много колкото е потът, след като платиш. Пример при блайндове 5/10: пръв си на ход, потът е 15, плащаш 10 и може да вдигнеш до 35. Бутонът „Пот“ слага точно толкова.")
    eq(T.bg["help.holdem.sidepot"], "Иван влиза ва банк със 100 чипа. Мария има 300, Киро 600. Основният пот е 300: по 100 от тримата. За него играят и тримата. Мария и Киро залагат още по 200 помежду си. Това е страничен пот от 400 и е само за тях двамата. Иван може да спечели най-много основния пот.")
    ok(T.bg["help.holdem.fair"]:find("надписът под масата в златно казва кой.", 1, true), "the gold note")
    ok(T.bg["help.holdem.seats"]:find("Само залог, който никой не е платил, се връща при теб.", 1, true), "the uncalled bet")
    ok(T.bg["help.holdem.time"]:find("Ръката се анулира, чиповете се връщат", 1, true), "the lapse voids the hand")
    ok(T.en["help.holdem.time"]:find("the chips go back", 1, true))
    eq(T.bg["help.fair.sealed"], "В Холдем числата не се показват след всяка ръка, а чак при затварянето на масата. Иначе щяха да се видят картите на отказалите се. Дотогава надписът под масата брои запечатаните ръце. Аддонът на раздаващия и тук знае тестето на своята ръка, а раздаващият се сменя с бутона.")
    eq(T.en["holdem.fold"], "Fold"); eq(T.en["holdem.close"], "End game"); eq(T.en["optv.holdem.betting.pl"], "Pot Limit"); eq(T.en["seal.ok"], "All %d hands checked")
    local hb, hc = {}, {}
    for i, b in ipairs(ns.Help.get("holdem").blocks) do
      hb[i] = b.key
      if b.kind == "cards" then hc[#hc + 1] = b.cards end
    end
    eq(hb, { "help.holdem.p1", "help.holdem.example", "help.holdem.blinds", "help.holdem.rounds", "help.holdem.hands", "help.holdem.sidepot",
      "help.holdem.limits", "help.holdem.seats", "help.holdem.time", "help.holdem.fair", "help.holdem.stake" })
    eq(hc, { { "AH", "JH", "7C", "QS", "2D" }, { "TS", "JS", "QS", "KS", "AS" } })
    eq(ns.Help.get("holdem").title, "game.holdem")
    eq(T.bg["help.tabla.tapa"], "На „Тапа“ всичките 15 пула тръгват от едно поле и не се бие. Поле с два или повече чужди пула е затворено за теб. Стъпиш ли върху сам чужд пул, го затискаш: той не мърда, докато всичките ти пулове не си тръгнат оттам. Върху затиснатия пул можеш да слагаш и други свои. Мария затиска последния пул на Иван, останал на началното му поле. Това е майката. Играта свършва веднага и Мария взима 2 точки.")
    eq(T.bg["help.tabla.time"], "Ако времето ти изтече, аддонът изиграва вместо теб първия позволен ход. Не губиш играта. Ако някой стане от масата или го няма повече от три минути, губи партията.")
    -- Pre-flight F13 + D13: the guest cannot pick a die; what a modified host can still do is said honestly (shown and counted, not prevented).
    eq(T.bg["help.fair.dice"], "Заровете на таблата се хвърлят по същия начин. Домакинът заключва своето число. Гостът заключва своето и после го праща само на домакина. Чак тогава домакинът показва двете и всеки аддон сам пресмята заровете. Числото на домакина не излиза, преди да е дошло това на госта. Гостът не може да си избере зар. Подправен аддон на домакина пак може да хвърли сам. Това не може да се спре, но аддонът на госта го показва под масата и го брои. На маса със залог аддонът на госта тогава оспорва дълга сам.")
    -- The final wave: the points of bearing off are counted from my own edge; only the host throws alone.
    ok(T.bg["help.tabla.bearoff"]:find("Полетата се броят от твоя край на дъската: зар 4 изкарва пул от четвъртото поле от края.", 1, true))
    ok(T.en["help.tabla.bearoff"]:find("counted from your own edge of the board", 1, true))
    ok(T.bg["help.tabla.fair"]:find("Ако гостът не се включи до 10 секунди, домакинът хвърля сам", 1, true))
    ok(T.en["help.tabla.tapa"]:find("two or more", 1, true) and T.en["help.tabla.tapa"]:find("more of your own checkers on the one you pinned", 1, true))
    ok(not T.en["help.fair.dice"]:find("stall", 1, true)); eq(T.en["help.tabla.time"]:find("You do not lose the game.", 1, true) ~= nil, true)
    eq(T.en["tabla.undo"], "Undo")
    eq(T.en["tabla.done"], "Done")
    eq(T.en["dice.ok"], "Dice: thrown by both players")
    eq(T.bg["help.belot.contra"], "Противникът е казал игра, а ти мислиш, че ще го биеш? Натисни „Контра“ и точките се броят двойно. Неговият отбор може да отвърне с „Реконтра“ и тогава са четворни. При контра всичките точки от раздаването взима отборът, който е събрал повече.")
    eq(T.bg["help.belot.time"], "Ако времето ти изтече при наддаването, аддонът казва „Пас“. Ако изтече при игра, той обявява каквото държиш и играе най-слабата ти позволена карта. Ако някой стане от масата или го няма повече от три минути, партията свършва и неговият отбор губи. Щом някой седне на свободния стол, започва нова партия. След нормален край домакинът натиска „Нова игра“.")
    eq(T.en["belot.bid.X"], "Double")
    eq(T.en["belot.peek"], "Last trick")
    eq(T.bg["help.fair.dealer"], "Едно нещо да знаеш: аддонът на раздаващия знае цялото тесте в ръката, която раздава. Иначе няма как да ти прати твоите карти. Обикновен играч това не го вижда. Само подправен аддон може да наднича, и то само когато раздава. Затова раздаването минава при следващия играч всяка ръка, а накрая всяка ръка се проверява. На маса със залог това важи с пълна сила: играй карти за голд с хора, на които вярваш.")
    eq(T.bg["help.santase.close"], "Мислиш, че ще стигнеш 66 и без да теглиш? Натисни „Затвори“, когато си на ход и в тестето има повече от две карти. Никой не тегли повече. Не стигнеш ли 66, другият взима 2 игри, а ако дотогава е бил без взятка, взима 3.")
    eq(T.en["help.santase.close"]:match("or 3 if .*$"), "or 3 if they had no trick by then.")
    -- The example ends in two short sentences (spec 5.3а).
    ok(T.bg["help.fair.example"]:find("Никой не може да смени числото си след това. Кутийката му вече е на масата.", 1, true))
    ok(not T.bg["help.fair.example"]:find(":", 1, true), "a colon in the example")
    -- The void rule: named, and the next player deals.
    ok(T.bg["help.fair.bad"]:find("раздава следващият", 1, true), "the void rule is not in the fair help")
    ok(T.en["help.fair.bad"]:find("the next player deals", 1, true), "the void rule is not in the fair help (en)")
    -- A reload alone keeps the dealer's deck; the void is for a dealer who left or crashed.
    ok(T.bg["help.fair.bad"]:find("само презареди играта, аддонът му пази тестето и ръката продължава", 1, true), "the reload rule is not in the fair help")
    ok(T.en["help.fair.bad"]:find("only reloads the game, their addon keeps the deck and the hand goes on", 1, true), "the reload rule is not in the fair help (en)")
    ok(not T.bg["fair.tip.void"]:find("презареди", 1, true) and not T.en["fair.tip.void"]:find("reload", 1, true), "a reload no longer voids a hand")
    -- The announce check at the end of a deal, and how the 90 of a capot count (rule 12 of engines/belot.lua).
    ok(T.bg["help.belot.announce"]:find("Обява без покритие не носи точки", 1, true), "the announce check is not in the Белот help")
    ok(T.en["help.belot.announce"]:find("scores nothing and does not cancel anybody else's", 1, true), "the announce check is not in the Белот help (en)")
    ok(T.bg["help.belot.valat"]:find("90 точки, преди сборът да се раздели на десет", 1, true), "how the 90 count")
    ok(T.bg["help.belot.valat"]:find("след удвояването", 1, true), "the 90 in „Без коз“")
    ok(T.en["help.belot.valat"]:find("90 points are added to its total for the deal, before the total is divided by ten", 1, true), "how the 90 count (en)")
    eq(T.en["help.belot.fair"], "Below the table it says whether the last deal was “verified”. The deal passes to the next player each time, as at a real table.")
    eq(T.en["santase.swap"], "Swap the nine")
    eq(T.bg["help.deathroll.example"], "Иван и Мария играят от 1000. Иван хвърля 642. Мария хвърля от 1 до 642 и вади 87. Иван вади 12, Мария вади 3. Иван хвърля от 1 до 3 и вади 1. Иван губи и черпи.")
    eq(T.en["deathroll.roll"], "Roll")
    -- The Death Roll topic explains both marks after the name and when „Нова игра“ comes.
    ok(T.bg["help.deathroll.tags"]:find("Въпросителна след името", 1, true), "no „?“ in tags")
    ok(T.bg["help.deathroll.tags"]:find("на думата на играча", 1, true), "„?“ is not the player's word")
    ok(T.bg["help.deathroll.tags"]:find("Червена удивителна", 1, true), "no red „!“ in tags")
    ok(T.bg["help.deathroll.roll"]:find("Щом играта свърши, домакинът натиска „Нова игра“", 1, true), "„Нова игра“ unclear")
  end)

  it("L formats and falls back to the key", function()
    eq(ns.L("no.such.key"), "no.such.key")
    eq(ns.Locale.lang(), "bg")
    T.bg["test.fmt"], T.en["test.fmt"] = "%s сяда на %d", "%s sits at %d"
    eq(ns.L("test.fmt", "Иван", 2), "Иван сяда на 2")
    eq(ns.L("game.ttt"), T.bg["game.ttt"])
    ns.Locale.set("en"); eq(ns.Locale.lang(), "en")
    eq(ns.L("test.fmt", "Ivan", 2), "Ivan sits at 2")
    ns.Locale.set("xx"); eq(ns.Locale.lang(), "en")
    ns.Locale.set("bg")
    T.bg["test.fmt"], T.en["test.fmt"] = nil, nil
  end)
end)
