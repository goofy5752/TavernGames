local Wow = require("wow")

local function boot(opts)
  local w = Wow.new(opts or { ui = true })
  w:boot(); w:firstRunDone(); w:fire("PLAYER_LOGIN")
  return w
end

local B = "Борислав"
local function rgb(t) local r, g, b = t:GetVertexColor(); return { r, g, b } end

describe("ui: the hero portrait", function()
  local w = boot()
  local P, A, T = w.ns.Portrait, w.ns.Art, w.ns.Theme
  local p = P.new(w.G.UIParent, 60, { badge = true })

  it("the chain: my group's real portrait, the race icon, the class icon, our silhouette", function()
    local who = { name = B, cls = "PRIEST", race = "Tauren", sex = 2 }
    p:set(who); eq({ p.source, p.sil.layers }, { "sil", { "bust", "horns" } })
    w:hasFile("Interface\\Icons\\ClassIcon_Priest"); A.reset(); p:set(who); eq(p.source, "class")
    w:hasAtlas("raceicon128-tauren-male"); A.reset(); p:set(who); eq({ p.source, p.tex:GetAtlas() }, { "race", "raceicon128-tauren-male" })
    who.unit = "party1"; p:set(who); eq({ p.source, p.tex.portrait }, { "unit", "party1" })
  end)
  it("a peer without race or with a hostile one never reaches an atlas name", function()
    w:hasAtlas("raceicon128-tauren-male")
    local q = P.new(w.G.UIParent, 60)
    q:set({ name = B, cls = "PRIEST", race = "Tauren-male!!", sex = 2 }); eq(q.source, "class")
    q:set({ name = B, cls = "PRIEST", race = string.rep("x", 300), sex = 2 }); eq(q.source, "class")
    q:set({ name = B, cls = "PRIEST", race = {}, sex = 7 }); eq(q.source, "class")
    q:set({ name = B, cls = "PRIEST", race = "Tauren", sex = 7 }); eq(q.source, "class")
    q:set({ name = B, cls = "PRIEST" }); eq(q.source, "class")
    A.reset()
    q:set({ name = B, cls = "ROGUE", race = "Tauren-male!!", sex = 2 }); eq(q.source, "sil")
    q:set({ name = B, cls = "ROGUE" }); eq(q.source, "sil")
  end)
  it("an empty seat is an outline; the player on turn is ringed in gold", function()
    p:set(nil)
    eq(p.source, "empty"); eq(p.tex:GetTexture(), T.tex.chair_empty); eq(p.ring:IsShown(), false)
    p:set({ name = B, cls = "PRIEST", race = "Orc", sex = 3 })
    eq(p.ring:IsShown(), true)
    p:turn(true); eq(p.glow:IsShown(), true); eq(rgb(p.ring), { T.rgb("goldHi") })
    p:turn(false); eq(p.glow:IsShown(), false); eq(rgb(p.ring), { T.rgb("brass") })
  end)
  it("the parts: sizes, mask, and a silhouette queen for a woman", function()
    eq({ p.frame:GetWidth(), p.frame:GetHeight() }, { 60, 60 })
    eq(p.badge:GetWidth(), 24); eq(p.ring:GetTexture(), T.tex.pring); eq(p.ring:GetWidth(), 64)
    eq(#p.tex.masks, 1)
    A.reset()
    p:set({ name = B, cls = "ROGUE", race = "Orc", sex = 3 }); eq({ p.source, p.sil.layers }, { "sil", { "hair", "bust", "tusks" } })
  end)
  it("who: me from env with unit player; a peer from presence; a far group member has no unit", function()
    local c = { env = { me = "Ана", cls = "MAGE", race = "Human", sex = 3 } }
    w.ns.Adapter.env = c.env
    local me = P.who(c, c.env.me)
    eq({ me.name, me.unit }, { c.env.me, "player" }); eq(me.race, c.env.race)
    local fake = { env = c.env, presence = { get = function(_, n) if n == B then return { name = B, cls = "MAGE", race = "Orc", sex = 2 } end end } }
    local peer = P.who(fake, B)
    eq({ peer.cls, peer.race, peer.sex, peer.unit }, { "MAGE", "Orc", 2, nil })
    eq(P.who(fake, "Nobody").unit, nil)
  end)
  it("without the check APIs a portrait is the silhouette and nothing raises", function()
    local w2 = boot({ ui = true, noArt = true })
    local q = w2.ns.Portrait.new(w2.G.UIParent, 40, { badge = true })
    w2.G.SetPortraitTexture = nil
    q:set({ name = B, cls = "PRIEST", race = "Orc", sex = 2, unit = "party1" }); eq(q.source, "sil")
    q:set(nil); eq(q.source, "empty")
  end)
end)
