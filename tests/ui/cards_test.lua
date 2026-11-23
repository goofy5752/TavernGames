local Wow = require("wow")

local ME = "Иван Петров"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired.
local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

local function color(fs) return { fs:GetTextColor() } end

local function rgb(w, token)
  local c = w.ns.Theme.color[token]
  return { c[1], c[2], c[3], 1 }
end

describe("ui: cards", function()
  local w = guildWow()
  local C = w.ns.Cards

  it("a face that is not known has no rank and no colour, and does not break", function()
    eq(C.rank(nil), ""); eq(C.red(nil), false); eq(C.rank("TH"), "10"); eq(C.red("TH"), true); eq(C.red("9S"), false)
  end)

  it("lays a fan out around the centre", function()
    eq(C.layout(6, 28, 40), { -90, -62, -34, -6, 22, 50 }); eq(C.layout(1, 28, 40), { -20 }); eq(C.layout(0, 28, 40), {})
  end)

  it("names ranks and suits", function()
    eq({ C.rank("TS"), C.rank("9H"), C.rank("KD") }, { "10", "9", "K" }); eq({ C.red("9H"), C.red("QD"), C.red("TS"), C.red("AC") }, { true, true, false, false })
    eq(C.suitName("H"), "купа"); eq(C.COORD.S, { 0.75, 1 })
  end)

  it("a fan shows faces, backs, raised and dimmed cards and reports clicks on playable ones", function()
    local fan = C.fan(w.G.UIParent, {}); local got = {}
    fan:set({ { i = 1, face = "KH", mode = "raised" }, { i = 2, mode = "plain" }, { i = 3, face = "TS", mode = "dim" } }, function(e) got[#got + 1] = e.i end)
    local c1, c2, c3 = fan.cards[1], fan.cards[2], fan.cards[3]
    eq({ c1.rank:GetText(), c1.y, c1.x, c1.mode }, { "K", 8, -48, "raised" }); eq(color(c1.rank), rgb(w, "red"))
    eq(c2.face, nil); eq(c2.body:GetTexture(), w.ns.Theme.tex.card_back_alliance); eq(c2.rank:IsVisible(), false); eq(c2.y, 0)
    eq(c3.mode, "dim"); eq(color(c3.rank), rgb(w, "cardInk")); eq(fan.frame:GetWidth(), 96)
    w:click(c1.frame); w:click(c3.frame); w:click(c2.frame); eq(got, { 1, 2 })
    fan:set({ { i = 9, face = "9C", mode = "plain" } }); eq(fan.cards[2].frame:IsVisible(), false); eq(fan.cards[1].x, -20)
  end)

  it("a card is dimmed by a shade of its own shape and raised with a gold edge, its suits tinted and cut from the strip", function()
    local c = C.card(w.G.UIParent)
    c:set("QD"); c:look("dim")
    eq({ c.shade:IsShown(), c.shade:GetTexture(), select(4, c.shade:GetVertexColor()), c.edges[1]:IsShown() }, { true, w.ns.Theme.tex.card, 1 - C.DIM, false })
    eq(c.big.texCoord, { 0.25, 0.5, 0, 1 }); eq({ c.pip:GetVertexColor() }, rgb(w, "red")); eq(c.frame:GetWidth(), 40)
    c:look("raised"); eq({ c.shade:IsShown(), c.edges[1]:IsShown(), { c.edges[1]:GetVertexColor() } }, { false, true, rgb(w, "gold") })
    c:set(nil); eq({ c.shade:GetTexture(), c.pip:IsShown(), c.big:IsShown() }, { w.ns.Theme.tex.card_back_alliance, false, false })
  end)
end)

describe("ui: card faces and backs", function()
  local w = guildWow()
  local C, T = w.ns.Cards, w.ns.Theme
  local ART = "Interface\\Icons\\Achievement_Leader_Tyrande_Whisperwind"
  local function fresh() w.ns.db.deck = nil; w.ns.Art.reset() end
  local function near(a, b) return math.abs(a - b) < 1e-6 end

  it("a court shows its hero in the oval; the ribbon only from 50 px up", function()
    fresh()
    local c = C.card(w.G.UIParent); c:set("KH")
    eq({ c.cameo:IsShown(), c.art, c.sil.layers, c.ribbon:IsShown(), c.big:IsShown() }, { true, "standin", { "hair", "bust", "ears", "crown" }, false, false })
    eq({ c.rank:GetText(), c.rank:IsShown(), c.pip:IsShown() }, { "K", true, true })
    local big = C.card(w.G.UIParent, 1.5); big:set("KH")
    eq({ big.ribbon:IsShown(), big.ribbonText:GetText() }, { true, "Tyrande" })
    big:set("QH"); eq(big.ribbonText:GetText(), "Дама")
    eq(big.sil.layers, { "hair", "bust", "ears" })
  end)

  it("the corner index draws above the cameo, and the cameo's rect is 18 / 13 / 21 percent", function()
    fresh()
    local c = C.card(w.G.UIParent); c:set("KH")
    ok(c.rank:GetParent():GetFrameLevel() > c.sil.frame:GetFrameLevel(), "rank frame not above the silhouette")
    eq(c.pip:GetParent(), c.rank:GetParent()); eq(c.shade:GetParent(), c.rank:GetParent())
    local p = c.cameo.points[1]
    ok(near(p[4], 0.18 * 40) and near(p[5], -0.13 * 58), "cameo top left " .. tostring(p[4]) .. "," .. tostring(p[5]))
    eq(c.chairBack.vertex, { 0x5b / 255, 0x66 / 255, 0x76 / 255, 1 })
  end)

  it("the client's leader icon replaces the silhouette when the client has it", function()
    fresh(); w:hasFile(ART); w.ns.Art.reset()
    local c = C.card(w.G.UIParent); c:set("KH")
    eq({ c.art, c.portrait:GetTexture(), c.sil.frame:IsShown() }, { "client", ART, false })
    ok(#c.portrait.masks == 1, "portrait not masked")
    c:set("KD"); eq({ c.art, c.sil.frame:IsShown(), c.portrait:IsShown() }, { "standin", true, false })
  end)

  it("a king without its leader's icon wears the client's hero of the race, the leader's sex", function()
    fresh(); w.ns.Art.reset()
    local c = C.card(w.G.UIParent)
    c.deck = "orc"; w:hasAtlas("raceicon128-orc-male"); w.ns.Art.reset()
    c:set("KS"); eq({ c.art, c.portrait.atlas, c.sil.frame:IsShown() }, { "client", "raceicon128-orc-male", false })
    c.deck = "undead"; w:hasAtlas("raceicon128-undead-female"); w.ns.Art.reset()
    c:set("KS"); eq({ c.art, c.portrait.atlas }, { "client", "raceicon128-undead-female" })
    c.deck = "troll"; c:set("KS"); eq({ c.art, c.sil.frame:IsShown() }, { "standin", true }) -- neither: the crowned silhouette
  end)

  it("an ace wears the crest, a number its suit in the middle, the back the deck's faction", function()
    fresh()
    local c = C.card(w.G.UIParent)
    c:set("AS"); eq({ c.crest:IsShown(), c.big:IsShown(), c.cameo:IsShown(), c.ribbon:IsShown() }, { true, false, false, false })
    c:set("7D"); eq({ c.big:IsShown(), c.crest:IsShown(), c.cameo:IsShown(), c.big.texCoord }, { true, false, false, { 0.25, 0.5, 0, 1 } })
    eq({ c.big:GetWidth(), c.big:GetHeight(), c.big.points[1][1] }, { 0.46 * 40, 0.46 * 40, "CENTER" })
    c:set(nil)
    eq({ c.body:GetTexture(), c.shade:GetTexture(), c.crest:IsShown(), c.crest:GetWidth(), c.rank:IsShown(), c.cameo:IsShown() }, { T.tex.card_back_alliance, T.tex.card_back_alliance, true, 0.62 * 40, false, false })
  end)

  it("a race deck wears its own faction in any skin and changes live", function()
    fresh()
    local c = C.card(w.G.UIParent); c:set(nil)
    w.ns.Decks.set("tauren"); c:set(nil); eq(c.body:GetTexture(), T.tex.card_back_horde)
    c:set("KS"); eq(c.cameoRing.vertex, { 0x9a / 255, 0x8f / 255, 0x86 / 255, 1 })
    eq(c.chairBack.vertex, { 0x6d / 255, 0x4d / 255, 0x42 / 255, 1 })
    c.deck = "human"; c:set("KS"); eq(c.sil.layers, { "bust", "crown" })
    eq(c.cameoRing.vertex, { 0xd8 / 255, 0xab / 255, 0x4a / 255, 1 })
    fresh()
  end)

  it("without the check APIs every card still draws (stand-ins only)", function()
    local n = Wow.new{ ui = true, noArt = true }; n.inGuild = true
    n.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
    n.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
    n:boot(); n:firstRunDone(); n:fire("GUILD_ROSTER_UPDATE"); n:fire("PLAYER_LOGIN")
    local c = n.ns.Cards.card(n.G.UIParent)
    for _, f in ipairs({ "KH", "QS", "JD", "AC", "5H", "TS" }) do c:set(f); ok(c.body:GetTexture() ~= nil, f) end
    c:set("QS"); eq({ c.art, c.sil.frame:IsShown() }, { "standin", true })
    c:set("AC"); eq(c.crest.standIn, true)
    c:set(nil); eq(c.crest.standIn, true)
  end)
end)
