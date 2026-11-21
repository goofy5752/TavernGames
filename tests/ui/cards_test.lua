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
    eq(c2.face, nil); eq(c2.body:GetTexture(), w.ns.Theme.tex.card_back); eq(c2.rank:IsVisible(), false); eq(c2.y, 0)
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
    c:set(nil); eq({ c.shade:GetTexture(), c.pip:IsShown(), c.big:IsShown() }, { w.ns.Theme.tex.card_back, false, false })
  end)
end)
