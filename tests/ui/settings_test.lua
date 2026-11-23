local Wow = require("wow")

-- Booted with the ui/ files, the first run done, the „Настройки“ tab shown.
local function settings(opts)
  local w = Wow.new{ ui = true, saved = opts and opts.saved }
  if opts and opts.faction then w.faction = opts.faction end
  if opts and opts.noFaction then rawset(w.G, "UnitFactionGroup", nil) end
  w:boot(); w:firstRunDone(); w:fire("PLAYER_LOGIN")
  w.ns.MainWindow.show("settings")
  return w, w.ns.Settings.view
end

describe("ui: settings, Облик and Тесте", function()
  it("a second panel right of the first, with the headings and their sub lines", function()
    local w, v = settings()
    eq({ v.looks:GetWidth(), v.looks.points[1][4] }, { 542, 530 })
    ok(#w:texts("Облик") >= 1); ok(#w:texts("рамки, сукно, гербове, звуци") == 1)
    ok(#w:texts("гърбът, асата и фигурите") == 1)
    ok(#w:texts("Една раса на всички бои: попът е лидерът, дамата и валето са от расата") == 1)
  end)

  it("theme tiles: a crest, the title and the sub; the resolved one is ringed", function()
    local w, v = settings{ faction = "Horde" }
    local a, h = v.themeTiles.alliance, v.themeTiles.horde
    eq({ a.frame:GetWidth(), a.frame:GetHeight() }, { 170, 52 })
    eq(a.title:GetText(), "Alliance"); eq(a.sub:GetText(), "лапис и злато")
    eq(h.title:GetText(), "Horde"); eq(h.sub:GetText(), "кръв и желязо")
    eq(h.crest:GetTexture(), w.ns.Theme.tex.crest_horde); eq(a.crest:GetTexture(), w.ns.Theme.tex.crest_alliance)
    eq(w.ns.db.theme, nil); eq(h.pressed, true); eq(a.pressed, false)
    local function rgba(token) local r, g, b = w.ns.Theme.rgb(token); return { r, g, b, 1 } end
    eq({ h.ring[1]:GetVertexColor() }, rgba("goldHi")); eq({ a.ring[1]:GetVertexColor() }, rgba("brassDim"))
  end)

  it("a theme tile saves the choice and offers the reload; the running skin stays", function()
    local w, v = settings()
    w:click(v.themeTiles.horde.frame); eq(w.ns.db.theme, "horde"); eq(w.ns.Theme.skin, "alliance")
    eq(v.themeTiles.horde.pressed, true); eq(v.themeTiles.alliance.pressed, false)
    eq(v.reload:IsShown(), true); ok(#w:texts("Новият облик идва след презареждане") == 1)
    eq(v.reloadButton.text:GetText(), "Презареди сега"); eq(v.reloadButton:GetWidth(), 120)
    w:click(v.reloadButton); eq(w.reloads, 1)
    w:click(v.themeTiles.alliance.frame); eq(v.reload:IsShown(), false)
  end)

  it("the reload note: the language alone, or the theme note when both changed", function()
    local w, v = settings()
    w:click(v.langEn)
    ok(#w:texts("Новият език идва след презареждане") == 1); eq(#w:texts("Новият облик"), 0)
    w:click(v.themeTiles.horde.frame)
    ok(#w:texts("Новият облик идва след презареждане") == 1); eq(#w:texts("Новият език"), 0)
    w:click(v.langBg)
    ok(#w:texts("Новият облик идва след презареждане") == 1)
  end)

  it("a client without UnitFactionGroup boots, registers its events and dresses in Alliance", function()
    local w, v = settings{ noFaction = true }
    eq(w.G.UnitFactionGroup, nil); eq(w.ns.Theme.skin, "alliance"); eq(w.ns.Adapter.faction(), nil)
    local registered = false
    for _, f in ipairs(w.frames) do if f.events.PLAYER_LOGOUT then registered = true end end
    ok(registered, "OnEnable registered the events")
    eq(v.themeTiles.alliance.pressed, true); eq(v.reload:IsShown(), false)
  end)

  it("an unknown saved theme reads as the faction's, is left alone and raises nothing", function()
    local w, v = settings()
    w.ns.db.theme = "darkmoon"; w.ns.db.deck = "murloc"
    w.ns.MainWindow.show("hall"); w.ns.MainWindow.show("settings")
    eq(v.themeTiles.alliance.pressed, true); eq(v.deckTiles.faction.pressed, true)
    eq(v.reload:IsShown(), false); eq(w.ns.db.theme, "darkmoon"); eq(w.ns.db.deck, "murloc")
  end)

  it("eleven deck tiles, each with its own king; a click changes the cards at once", function()
    local w, v = settings()
    eq(#w.ns.Decks.ORDER, 11); for _, k in ipairs(w.ns.Decks.ORDER) do ok(v.deckTiles[k], k) end
    local t = v.deckTiles.tauren
    eq({ t.frame:GetWidth(), t.frame:GetHeight() }, { 170, 52 })
    eq(t.card.deck, "tauren"); eq(t.card.face, "KS")
    eq(t.card.sil.layers, { "bust", "horns", "crown" })
    eq(t.title:GetText(), "Таурени"); eq(t.sub:GetText(), "поп Cairne")
    eq(v.deckTiles.faction.title:GetText(), "Градовете на Алианса")
    eq(v.deckTiles.faction.sub:GetText(), "четири града, четири лидера")
    eq(v.deckTiles.faction.pressed, true)
    local refreshed = 0
    local refresh = w.ns.TableFrame.refresh
    w.ns.TableFrame.refresh = function(...) refreshed = refreshed + 1; return refresh(...) end
    w:click(v.deckTiles.orc.frame); eq(w.ns.db.deck, "orc"); eq(v.reload:IsShown(), false)
    eq(refreshed, 1); eq(v.deckTiles.orc.pressed, true); eq(v.deckTiles.faction.pressed, false)
  end)

  it("deck tiles: the faction tile first, then the races three to a row inside the panel", function()
    local w, v = settings()
    local D = v.deckTiles
    local function xy(k) local p = D[k].frame.points[1]; return { p[4], p[5] } end
    local f, h, n, d, g = xy("faction"), xy("human"), xy("nightelf"), xy("dwarf"), xy("gnome")
    eq(h[1], f[1]); ok(h[2] < f[2], "the races below the faction tile")
    eq(n[2], h[2]); eq(d[2], h[2]); eq(g[1], h[1]); ok(g[2] < h[2])
    ok(d[1] + 170 <= 542, "the third tile inside the panel")
    local last = xy("bloodelf")
    ok(-last[2] + 52 <= w.ns.MainWindow.BODY_H, "the last row inside the panel")
  end)
end)

describe("ui: settings, Звуци", function()
  it("the sound check sits under the minimap check and mutes everything", function()
    local w, v = settings()
    eq(v.sound.label:GetText(), "Звуци"); eq(v.sound.checked, true)
    ok(v.sound.points[1][5] < v.minimap.points[1][5], "not under the minimap check")
    w.G.SOUNDKIT.LOOT_WINDOW_COIN_SOUND = 120
    local n = #w.sounds
    eq(w.ns.Art.play("coins"), true); eq(#w.sounds, n + 1)
    w:click(v.sound)
    eq(w.ns.db.sound, false); eq(v.sound.checked, false)
    eq(w.ns.Art.play("coins"), false); eq(#w.sounds, n + 1)
    w:click(v.sound)
    eq(w.ns.db.sound, true); eq(w.ns.Art.play("coins"), true)
  end)
end)
