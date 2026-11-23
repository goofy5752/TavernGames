local Wow = require("wow")

local function boot()
  local w = Wow.new{ ui = true }
  w:boot(); w:firstRunDone(); w:fire("PLAYER_LOGIN")
  return w
end

describe("ui: decks and silhouette", function()
  local w = boot()
  local D, S, T = w.ns.Decks, w.ns.Silhouette, w.ns.Theme

  it("the faction deck follows the skin; a race deck keeps its own faction", function()
    eq(D.faction("faction", "horde"), "horde"); eq(D.faction("tauren", "alliance"), "horde"); eq(D.faction("gnome", "horde"), "alliance")
  end)
  it("courts: a city per suit, or the deck's race on every suit", function()
    eq(D.court("KS", "faction", "alliance"), { race = "human", faction = "alliance", role = "king", label = "Varian" })
    eq(D.court("QH", "faction", "horde").race, "undead"); eq(D.court("JC", "faction", "horde"), { race = "bloodelf", faction = "horde", role = "jack", label = "Вале" })
    eq(D.court("QS", "faction", "alliance").label, "Дама")
    for _, s in ipairs({ "S", "H", "D", "C" }) do eq(D.court("K" .. s, "troll", "alliance").label, "Vol'jin") end
    eq(D.court("AS", "faction", "alliance"), nil); eq(D.court("TS", "orc", "horde"), nil); eq(D.court(nil, "orc", "horde"), nil)
  end)
  it("key and set: saved, unknown reads as faction and is left alone", function()
    w.ns.db.deck = nil; eq(D.key(), "faction")
    D.set("troll"); eq(w.ns.db.deck, "troll"); eq(D.key(), "troll")
    w.ns.db.deck = "darkmoon"; eq(D.key(), "faction"); eq(w.ns.db.deck, "darkmoon")
    w.ns.db.deck = 7; eq(D.key(), "faction"); eq(w.ns.db.deck, 7)
    w.ns.db.deck = nil
  end)
  it("names, in both locales' keys", function()
    eq(D.name("faction", "alliance"), "Градовете на Алианса"); eq(D.name("faction", "horde"), "Градовете на Хордата")
    eq(D.name("bloodelf", "alliance"), "Кръвни елфи"); eq(#D.ORDER, 11)
    for race, r in pairs(D.RACES) do eq(D.CITIES[r.faction] ~= nil, true); ok(D.name(race, "alliance") ~= "deck.race." .. race) end
  end)
  it("silhouette layers: hair and hood under the bust, a king always crowned", function()
    eq(S.layers("nightelf", "king"), { "hair", "bust", "ears", "crown" }); eq(S.layers("undead", "jack"), { "hood", "bust" })
    eq(S.layers("dwarf", "king"), { "bust", "beard", "crown" }); eq(S.layers("gnome", "jack"), { "bust" }); eq(S.layers("murloc", "queen"), { "bust" })
    eq(S.layers("orc", "queen"), { "hair", "bust", "tusks" })
    for race in pairs(D.RACES) do for _, role in ipairs({ "king", "queen", "jack" }) do ok(#S.layers(race, role) <= 4) end end
  end)
  it("a drawn silhouette cuts its cells from the strip and hides the spare layers", function()
    local sil = S.new(w.G.UIParent)
    sil:set({ "hair", "bust", "ears", "crown" })
    eq(#sil.tex, 4)
    eq(sil.tex[1].texCoord or { sil.tex[1]:GetTexCoord() }, { 7 / 8, 1, 0, 1 })
    eq(sil.tex[2].shown ~= false and sil.tex[2]:IsShown(), true)
    sil:set({ "bust" })
    eq(sil.layers, { "bust" }); eq(sil.tex[1]:IsShown(), true)
    for i = 2, 4 do eq(sil.tex[i]:IsShown(), false) end
  end)
end)
