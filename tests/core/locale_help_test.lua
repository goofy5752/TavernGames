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

  it("every help block and intro key exists in both languages; topics are hall, ttt, deathroll, soon", function()
    local H = ns.Help
    local ids = {}
    for i, t in ipairs(H.topics) do ids[i] = t.id end
    eq(ids, { "hall", "ttt", "deathroll", "soon" })
    eq(#H.intro, 4)
    for _, t in ipairs(H.topics) do
      both(t.title, "topic title")
      local examples = 0
      for _, b in ipairs(t.blocks) do
        both(b.key, "block key")
        if b.kind == "example" then examples = examples + 1 end
        ok(b.kind == "p" or b.kind == "example" or b.kind == "board" or b.kind == "ladder", "bad kind " .. tostring(b.kind))
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
    eq(H.get("nope"), nil)
  end)

  it("every quoted label in the hall, ttt, deathroll and soon help is a UI label, and no help title copies one", function()
    local QUOTES = { bg = { "„", "“" }, en = { "“", "”" } }
    for lang, q in pairs(QUOTES) do
      local ui = {}
      for k, v in pairs(T[lang]) do
        if not k:match("^help%.") and not k:match("^intro%.") then ui[v] = true end
      end
      local checked = 0
      for k, text in pairs(T[lang]) do
        if k:match("^help%.hall%.") or k:match("^help%.ttt%.") or k:match("^help%.deathroll%.") or k =="help.soon.example" then
          local pos = 1
          while true do
            local a, b = text:find(q[1], pos, true)
            if not a then break end
            local c, d = text:find(q[2], b + 1, true)
            ok(c, lang .. " " .. k .. ": unclosed quote")
            if not c then break end
            local label = text:sub(b + 1, c - 1)
            ok(ui[label], lang .. " " .. k .. ": „" .. label .. "“ is not a UI label")
            checked = checked + 1
            pos = d + 1
          end
        end
      end
      ok(checked >= 18, lang .. ": only " .. checked .. " quoted labels found")
      for k, v in pairs(T[lang]) do
        if k:match("^help%.") and k:match("%.title$") then ok(not ui[v], lang .. " " .. k .. " copies a UI label") end
      end
    end
  end)

  it("pinned texts are used verbatim", function()
    eq(T.bg["help.ttt.example"], "Иван е Х, Мария е О. Редуват се. Иван нарежда три Х в редица и печели играта. Който пръв спечели 3 игри, печели мача.")
    eq(T.bg["help.hall.example"], "Виждаш маса с празен стол с пунктир. Кликаш на стола и вече седиш. Ако масата е пълна, кликни на нея, за да гледаш.")
    eq(T.bg["help.soon.p"], "Скоро идват Сантасе, Белот, Табла и Тексас Холдем, и игра на залог с тефтер на дълговете.")
    eq(T.bg["help.deathroll.example"], "Иван и Мария играят от 1000. Иван хвърля 642. Мария хвърля от 1 до 642 и вади 87. Иван вади 12, Мария вади 3. Иван хвърля от 1 до 3 и вади 1. Иван губи и черпи.")
    eq(T.en["deathroll.roll"], "Roll")
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
