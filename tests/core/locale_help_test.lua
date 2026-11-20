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

  it("every help block and intro key exists in both languages; topics are hall, ttt, soon", function()
    local H = ns.Help
    local ids = {}
    for i, t in ipairs(H.topics) do ids[i] = t.id end
    eq(ids, { "hall", "ttt", "soon" })
    eq(#H.intro, 4)
    for _, t in ipairs(H.topics) do
      both(t.title, "topic title")
      local examples = 0
      for _, b in ipairs(t.blocks) do
        both(b.key, "block key")
        if b.kind == "example" then examples = examples + 1 end
        ok(b.kind == "p" or b.kind == "example" or b.kind == "board", "bad kind " .. tostring(b.kind))
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
    eq(H.get("nope"), nil)
  end)

  it("pinned texts are used verbatim", function()
    eq(T.bg["help.ttt.example"], "Иван е Х, Мария е О. Редуват се. Иван нарежда три Х в редица и печели играта. Който пръв спечели 3 игри, печели мача.")
    eq(T.bg["help.hall.example"], "Виждаш маса с празен стол с пунктир. Кликаш на стола и вече седиш. Ако масата е пълна, кликни на нея, за да гледаш.")
    eq(T.bg["help.soon.p"], "Скоро идват Death Roll, Белот, Сантасе, Табла и Тексас Холдем, и игра на залог с тефтер на дълговете.")
  end)

  it("L formats and falls back to the key", function()
    eq(ns.L("no.such.key"), "no.such.key")
    eq(ns.Locale.lang(), "bg")
    T.bg["test.fmt"], T.en["test.fmt"] = "%s сяда на %d", "%s sits at %d"
    eq(ns.L("test.fmt", "Иван", 2), "Иван сяда на 2")
    eq(ns.L("help.ttt.title"), T.bg["help.ttt.title"])
    ns.Locale.set("en"); eq(ns.Locale.lang(), "en")
    eq(ns.L("test.fmt", "Ivan", 2), "Ivan sits at 2")
    ns.Locale.set("xx"); eq(ns.Locale.lang(), "en")
    ns.Locale.set("bg")
    T.bg["test.fmt"], T.en["test.fmt"] = nil, nil
  end)
end)
