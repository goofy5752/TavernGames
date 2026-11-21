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
