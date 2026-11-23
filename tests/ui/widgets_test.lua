local Wow = require("wow")

-- Booted with the ui/ files, PLAYER_LOGIN fired.
local function boot()
  local w = Wow.new{ ui = true }
  w:boot()
  w:firstRunDone()
  w:fire("PLAYER_LOGIN")
  return w
end

local function rgba(T, token) return { T.color[token][1], T.color[token][2], T.color[token][3], 1 } end

describe("ui: widgets", function()
  it("the gold button (mockup `.btn`): gold face, darker lip, dark label, the rim lit under the mouse and while lit", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme; local clicks = 0
    local b = W.GoldButton(w.G.UIParent, "Обяви 40", function() clicks = clicks + 1 end)
    eq({ b:GetSize() }, { 124, 24 }); eq(b.text:GetText(), "Обяви 40")
    eq(b.fill.color, { 0xdc / 255, 0xb4 / 255, 0x67 / 255, 1 }); eq(b.lip.color, { 0x8a / 255, 0x5a / 255, 0x2b / 255, 1 })
    eq({ b.text:GetTextColor() }, rgba(T, "woodDark")); eq(b.edges[1].vertex, rgba(T, "brass"))
    w:hover(b); eq(b.edges[1].vertex, rgba(T, "gold"))
    b.scripts.OnLeave(b); eq(b.edges[1].vertex, rgba(T, "brass"))
    b.lit = true; w:hover(b); b.scripts.OnLeave(b); eq(b.edges[1].vertex, rgba(T, "gold"))
    w:click(b); eq(clicks, 1)
  end)

  it("the window chrome: tinted wood inside the skin's frame, a cap on each top corner", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme
    local f = w.G.CreateFrame("Frame", nil, w.G.UIParent); f:SetSize(300, 200)
    local c = W.chrome(f, 300, 200)
    eq(c.wood:GetTexture(), T.tex.wood); eq(c.wood.points[1], { "TOPLEFT", f, "TOPLEFT", 4, -4 })
    eq(c.wood.points[2], { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4 })
    eq(c.wood.texCoord, { 0, 292 / T.texSize.wood, 0, 192 / T.texSize.wood })
    eq(c.wood.vertex, { T.S.woodTint[1], T.S.woodTint[2], T.S.woodTint[3], 1 })
    eq(#c.frame.pieces, 8)
    for _, p in ipairs(c.frame.pieces) do eq(p:GetTexture(), T.tex.frame); eq(p.layer, "BORDER") end
    eq(T.tex.frame, "Interface\\AddOns\\TavernGames\\media\\skin\\frame_alliance")
    for _, cap in ipairs({ c.caps.left, c.caps.right }) do
      eq(cap:GetTexture(), T.tex.cap); eq({ cap:GetSize() }, { 34, 34 }); eq(cap.layer, "OVERLAY")
    end
    eq(c.caps.left.points[1], { "CENTER", f, "TOPLEFT", 5, -5 }); eq(c.caps.right.points[1], { "CENTER", f, "TOPRIGHT", -5, -5 })
  end)

  it("the crest: ours as a stand-in, the client's when it has one; the mask only where the client masks", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme
    local f = w.G.CreateFrame("Frame", nil, w.G.UIParent)
    local c = W.crest(f, 28)
    eq(c:GetTexture(), T.tex.crest_alliance); eq(c.standIn, true); eq({ c:GetSize() }, { 28, 28 })
    eq(W.crest(f, 20, "horde"):GetTexture(), T.tex.crest_horde)
    w:hasFile("Interface\\Timer\\Alliance-Logo"); w.ns.Art.reset()
    local real = W.crest(f, 28, "alliance")
    eq(real:GetTexture(), "Interface\\Timer\\Alliance-Logo"); ok(not real.standIn)
    local tex = f:CreateTexture()
    local m = W.mask(tex, f)
    ok(m); eq(m.objectType, "MaskTexture"); eq(m:GetTexture(), T.tex.mask)
    eq(m.wrap, { "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE" }); eq(tex.masks, { m })
    eq(W.mask({ SetTexture = function() end }, f), nil)
    eq(W.mask(f:CreateTexture(), { CreateTexture = f.CreateTexture }), nil)
  end)

  it("a panel is a dark translucent fill", function()
    local w = boot()
    eq(w.ns.W.Panel(w.G.UIParent).fill.color, { 0, 0, 0, 0.38 })
  end)

  it("the ghost button (mockup `.btn.ghost`): dark fill, brass rim, its label in the colour asked for", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme; local clicks = 0
    local b = W.GhostButton(w.G.UIParent, "Смени деветката", "brassLight", function() clicks = clicks + 1 end)
    eq({ b:GetSize() }, { 124, 24 }); eq(b.fill.color, W.DARK_FILL); eq({ b.text:GetTextColor() }, rgba(T, "brassLight"))
    eq(b.edges[1].vertex, rgba(T, "brass")); w:hover(b); eq(b.edges[1].vertex, rgba(T, "gold"))
    b.scripts.OnLeave(b); eq(b.edges[1].vertex, rgba(T, "brass"))
    b.lit = true; b.scripts.OnLeave(b); eq(b.edges[1].vertex, rgba(T, "gold"))
    w:click(b); eq(clicks, 1)
  end)
end)
