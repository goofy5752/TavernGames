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
    -- the same who again draws nothing; the art the client has changed here, so the test forces it
    w:hasFile("Interface\\Icons\\ClassIcon_Priest"); A.reset(); p:set(who); eq(p.source, "sil")
    p:set(who, true); eq(p.source, "class")
    w:hasAtlas("raceicon128-tauren-male"); A.reset(); p:set(who, true); eq({ p.source, p.tex:GetAtlas() }, { "race", "raceicon128-tauren-male" })
    who.unit = "party1"; p:set(who); eq({ p.source, p.tex.portrait }, { "unit", "party1" })
  end)
  it("set draws only when who or what the client knows of him changes; force and nil still draw", function()
    local q = P.new(w.G.UIParent, 40)
    local touched = 0
    local setCoord = q.tex.SetTexCoord
    q.tex.SetTexCoord = function(...) touched = touched + 1; return setCoord(...) end
    local who = { name = B, cls = "PRIEST", race = "Tauren", sex = 2 }
    q:set(who); eq(touched, 1)
    q:set({ name = B, cls = "PRIEST", race = "Tauren", sex = 2 }); eq(touched, 1) -- a new table, the same data
    q:set({ name = B, cls = "PRIEST", race = "Tauren", sex = 2, unit = "party1" }); eq(touched, 2)
    q:set(nil); eq({ touched, q.source }, { 3, "empty" }); q:set(nil); eq(touched, 3)
    q:set(who); q:set(who, true); eq(touched, 5)
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
  it("the turn glow is a halo behind the face, never over it", function()
    -- Same frame as the disc and the face, under the disc: only its rim shows around the portrait.
    ok(p.glow:GetParent() == p.frame, "the glow is in a frame above the face")
    ok(p.bg:GetParent() == p.frame and p.tex:GetParent() == p.frame, "the disc and the face moved")
    eq(p.glow.layer, "BACKGROUND"); eq(p.bg.layer, "BACKGROUND")
    ok((p.glow.sublayer or 0) < (p.bg.sublayer or 0), "the glow is not under the disc")
    ok(p.glow:GetWidth() > p.frame:GetWidth(), "the glow does not reach past the portrait")
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
  it("a group member the client cannot draw (UnitIsVisible false) has no unit: the race icon", function()
    local w2 = Wow.new{ ui = true }
    w2.inGuild, w2.roster = true, { { name = B .. "-Forever", online = true, guid = "Player-1-00000002" },
                                     { name = "Иван Петров-Forever", online = true, guid = Wow.GUID } }
    w2:boot(); w2:firstRunDone(); w2:fire("PLAYER_LOGIN"); w2:fire("GUILD_ROSTER_UPDATE")
    w2:hasAtlas("raceicon128-orc-male")
    local peer = { name = B, cls = "MAGE", race = "Orc", sex = 2 }
    local c = { env = w2.ns.client.env, presence = { get = function(_, n) if n == B then return peer end end } }
    local q = w2.ns.Portrait.new(w2.G.UIParent, 40)
    w2.units.party1 = "Player-1-00000002"
    local who = w2.ns.Portrait.who(c, B); eq(who.unit, "party1")
    q:set(who); eq(q.source, "unit")
    w2.visible.party1 = false
    who = w2.ns.Portrait.who(c, B); eq(who.unit, nil)
    q:set(who); eq({ q.source, q.tex:GetAtlas() }, { "race", "raceicon128-orc-male" })
  end)
  it("without the check APIs a portrait is the silhouette and nothing raises", function()
    local w2 = boot({ ui = true, noArt = true })
    local q = w2.ns.Portrait.new(w2.G.UIParent, 40, { badge = true })
    w2.G.SetPortraitTexture = nil
    q:set({ name = B, cls = "PRIEST", race = "Orc", sex = 2, unit = "party1" }); eq(q.source, "sil")
    q:set(nil); eq(q.source, "empty")
  end)
end)
