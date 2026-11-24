local Wow = require("wow")

local function boot()
  local w = Wow.new{ ui = true }
  w:boot()
  w:firstRunDone()
  w:fire("PLAYER_LOGIN")
  return w
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

-- The addon path of a texture -> its file in the repository.
local function file(path) return path:gsub("^Interface\\AddOns\\TavernGames\\", ""):gsub("\\", "/") .. ".tga" end

describe("ui: game pictures and the title mug", function()
  it("every game in the hall shows its picture on the felt disc, tinted light brass", function()
    local w = boot()
    w.ns.MainWindow.show()
    local T = w.ns.Theme
    for _, g in ipairs(w.ns.Hall.view.games) do
      local pic = g.frame.pic
      ok(pic, "no picture for " .. g.id)
      eq(pic:GetTexture(), T.gameIcon(g.id))
      ok(exists(file(pic:GetTexture())), "missing file for " .. g.id)
      eq({ pic:GetSize() }, { 24, 24 })
      eq(pic.vertex, { T.color.brassLight[1], T.color.brassLight[2], T.color.brassLight[3], 1 })
    end
  end)

  it("a game without a picture keeps its first letter", function()
    local w = boot()
    eq(w.ns.Theme.gameIcon("nosuchgame"), nil)
  end)

  it("the mug stands before the title", function()
    local w = boot()
    w.ns.MainWindow.show()
    local MW = w.ns.MainWindow
    eq(MW.mug:GetTexture(), w.ns.Theme.tex.mug)
    ok(exists(file(MW.mug:GetTexture())), "media/mug.tga missing")
    eq(MW.title.points[1], { "LEFT", MW.mug, "RIGHT", 2, 0 })
  end)

  it("the crest stands right of the title, the first tab past it", function()
    local w = boot()
    w.ns.MainWindow.show()
    local MW, T = w.ns.MainWindow, w.ns.Theme
    eq(MW.crest:GetTexture(), T.tex.crest_alliance); eq({ MW.crest:GetSize() }, { 28, 28 })
    eq(MW.crest.points[1], { "LEFT", MW.title, "RIGHT", 6, 0 })
    local first = MW.tabs[MW.order[1]].button
    eq(first.points[1], { "BOTTOMLEFT", MW.title, "BOTTOMRIGHT", 60, -5 })
  end)
end)
