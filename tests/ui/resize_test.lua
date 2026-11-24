local Wow = require("wow")

local function boot()
  local w = Wow.new{ ui = true }
  w:boot()
  w:firstRunDone()
  w:fire("PLAYER_LOGIN")
  return w
end

-- The grip of window frame `f`: its child Button with a .key.
local function gripOf(f)
  for _, c in ipairs(f.children or {}) do
    if c.key and c.scripts and c.scripts.OnMouseDown then return c end
  end
end

describe("ui: resize", function()
  it("the main window gets a grip in its bottom-right corner and opens at scale 1", function()
    local w = boot()
    w.ns.MainWindow.show()
    local f = w.ns.MainWindow.frame
    local grip = gripOf(f)
    ok(grip, "no grip")
    eq(grip.key, "main")
    eq(grip.points[1], { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6 }); eq({ grip:GetSize() }, { 24, 24 }); eq(#grip.dots, 6)
    eq(grip.dots[1].color, { w.ns.Theme.color.gold[1], w.ns.Theme.color.gold[2], w.ns.Theme.color.gold[3], 1 })
    eq(f:GetScale(), 1)
  end)

  it("a drag along the diagonal scales the window and holds its top-left corner", function()
    local w = boot()
    w.ns.MainWindow.show()
    local f, R = w.ns.MainWindow.frame, w.ns.Resize
    f.left, f.top = 100, 900 -- in UIParent units at scale 1
    local grip = gripOf(f)
    grip.scripts.OnMouseDown(grip, "LeftButton")
    -- 1100 x 620 at scale 1: the corner is at (1200, 280); 10% more along both edges
    w.cursor = { 100 + 1210, 900 - 682 }
    grip.scripts.OnUpdate(grip, 0)
    local s = f:GetScale()
    ok(math.abs(s - 1.1) < 1e-9, "scale " .. s)
    local p = f.points[#f.points]
    eq(p[1], "TOPLEFT"); eq(p[3], "BOTTOMLEFT")
    ok(math.abs(p[4] * s - 100) < 1e-9 and math.abs(p[5] * s - 900) < 1e-9, "corner moved")
    grip.scripts.OnMouseUp(grip, "LeftButton")
    ok(math.abs(w.ns.db.scale.main - 1.1) < 1e-9, "not kept")
    ok(grip.scripts.OnUpdate == nil, "still dragging")
  end)

  it("the scale stays between the least readable one and what fits on the screen", function()
    local w = boot()
    w.ns.MainWindow.show()
    local f, R = w.ns.MainWindow.frame, w.ns.Resize
    f.left, f.top = 0, 1080
    local grip = gripOf(f)
    grip.scripts.OnMouseDown(grip, "LeftButton")
    w.cursor = { 0, 1080 }
    grip.scripts.OnUpdate(grip, 0)
    eq(f:GetScale(), R.least()) -- a 1080p screen of 1080 units: 8 / 9
    w.cursor = { 9000, -9000 }
    grip.scripts.OnUpdate(grip, 0)
    ok(math.abs(f:GetScale() - 1080 / 620) < 1e-9, "max " .. f:GetScale()) -- 1920 / 1100 is larger
  end)

  -- Review: with „История“ open the scale is held by its room; a click on the grip saved that.
  it("a side window's room is never saved: a click keeps my scale, a drag saves what I dragged to", function()
    local w = boot()
    w.ns.db.scale = { main = 1.5 }
    w.ns.MainWindow.show()
    local f, R = w.ns.MainWindow.frame, w.ns.Resize
    f.left, f.top = 100, 900
    R.extra.main = function() return 500 end -- 1100 + 500 on 1920: 1.2 at most
    R.refit("main")
    ok(math.abs(f:GetScale() - 1.2) < 1e-9, "not held: " .. f:GetScale())
    local grip = gripOf(f)
    local x0, y0 -- the corner where the grip was pressed (the fake keeps f.left in its own units)
    local function at(s) return { x0 + s * 1100, y0 - s * 620 } end
    local function down() -- pressed on the grip's corner, at the scale in use
      local k = f:GetEffectiveScale() / w.G.UIParent:GetEffectiveScale()
      x0, y0 = f:GetLeft() * k, f:GetTop() * k
      w.cursor = at(f:GetScale())
      grip.scripts.OnMouseDown(grip, "LeftButton")
    end
    -- a plain click on the grip
    down()
    grip.scripts.OnUpdate(grip, 0)
    grip.scripts.OnMouseUp(grip, "LeftButton")
    eq(w.ns.db.scale.main, 1.5)
    -- a drag past the side window's room: the window stays on the screen, the drag is saved
    down()
    w.cursor = at(1.6)
    grip.scripts.OnUpdate(grip, 0)
    ok(math.abs(f:GetScale() - 1.2) < 1e-9, "past the screen: " .. f:GetScale())
    grip.scripts.OnMouseUp(grip, "LeftButton")
    ok(math.abs(w.ns.db.scale.main - 1.6) < 1e-9, "saved " .. w.ns.db.scale.main)
    R.extra.main = nil
    R.refit("main") -- the side window closed: my own scale
    ok(math.abs(f:GetScale() - 1.6) < 1e-9, "not mine: " .. f:GetScale())
    -- a drag smaller is saved as such
    down()
    w.cursor = at(1.1)
    grip.scripts.OnUpdate(grip, 0)
    grip.scripts.OnMouseUp(grip, "LeftButton")
    ok(math.abs(w.ns.db.scale.main - 1.1) < 1e-9, "saved " .. w.ns.db.scale.main)
  end)

  it("a right click gives the normal size back; a saved scale is applied on the next build", function()
    local w = boot()
    w.ns.db.scale = { main = 1.4 }
    w.ns.MainWindow.show()
    local f = w.ns.MainWindow.frame
    eq(f:GetScale(), 1.4)
    local grip = gripOf(f)
    grip.scripts.OnMouseDown(grip, "RightButton")
    eq(f:GetScale(), 1); eq(w.ns.db.scale.main, 1)
  end)

  it("an out-of-range saved scale is ignored", function()
    local w = boot()
    w.ns.db.scale = { main = 7 }
    eq(w.ns.Resize.get("main"), 1)
    w.ns.db.scale = { main = "x" }
    eq(w.ns.Resize.get("main"), 1)
  end)

  it("a dialog that follows the main window takes its scale, now and on a change", function()
    local w = boot()
    w.ns.MainWindow.show()
    local R = w.ns.Resize
    local d = w.G.CreateFrame("Frame", nil, w.G.UIParent)
    R.follow(d, "main")
    eq(d:GetScale(), 1)
    R.set("main", 1.25)
    eq(d:GetScale(), 1.25)
    eq(w.ns.MainWindow.frame:GetScale(), 1.25)
  end)

  it("the table frame has its own grip and scale", function()
    local w = boot()
    w.ns.db.scale = { table = 0.9 }
    w.ns.TableFrame.build()
    local f = w.ns.TableFrame.frame
    eq(gripOf(f).key, "table")
    eq(f:GetScale(), 0.9)
  end)

  -- QA: the smallest text the addon draws (W.WRAP_MIN, 9) stays 8 screen pixels tall at the least scale.
  it("the least scale keeps the smallest text 8 screen pixels tall, on any screen", function()
    local w = boot()
    local R, UI = w.ns.Resize, w.G.UIParent
    local function least(uw, uh, pw, ph)
      UI:SetSize(uw, uh)
      w.G.GetPhysicalScreenSize = pw and function() return pw, ph end or nil
      return R.least()
    end
    ok(math.abs(least(1920, 1080) - 8 / 9) < 1e-9, "no screen size: a 1080p screen")
    ok(math.abs(least(1365, 768, 1920, 1080) - 8 / (9 * 1080 / 768)) < 1e-9, "the default UI scale on 1080p")
    eq(least(1365, 768, 3840, 2160), R.MIN) -- 4K: MIN reads well
    for _, case in ipairs({ { 1024, 768, 1440, 1080 }, { 1365, 768, 1920, 1080 }, { 1820, 768, 2560, 1080 }, { 1920, 1080, 1920, 1080 } }) do
      local s = least(unpack(case))
      ok(9 * s * case[4] / case[2] >= 8 - 1e-9, "unreadable at the least scale on " .. case[1] .. "x" .. case[2])
    end
  end)

  it("a saved scale too big for this screen is held to what fits; the saved one stays for a bigger screen", function()
    local w = boot()
    local R, UI = w.ns.Resize, w.G.UIParent
    UI:SetSize(1365, 768); w.G.GetPhysicalScreenSize = function() return 1920, 1080 end
    w.ns.db.scale = { main = 2 }
    w.ns.MainWindow.show()
    local f = w.ns.MainWindow.frame
    ok(math.abs(f:GetScale() - 768 / 620) < 1e-9, "opened past the screen: " .. f:GetScale())
    eq(w.ns.db.scale.main, 2)
    -- the screen grows (the UI scale): the window takes more of its saved scale
    UI:SetSize(1920, 1080); w:fire("UI_SCALE_CHANGED")
    ok(math.abs(f:GetScale() - 1080 / 620) < 1e-9, "not fitted again: " .. f:GetScale())
    -- a dialog that follows takes the scale in use, not the saved one
    local d = w.G.CreateFrame("Frame", nil, UI)
    R.follow(d, "main")
    eq(d:GetScale(), f:GetScale())
  end)

  it("a table of another size fits the screen again: Шах is taller than Белот", function()
    local w = Wow.new{ ui = true }
    w.inGuild = true
    w.roster = { { name = "Иван Петров-Forever", online = true, guid = Wow.GUID } }
    w:boot(); w:firstRunDone(); w:fire("GUILD_ROSTER_UPDATE"); w:fire("PLAYER_LOGIN")
    local UI = w.G.UIParent
    UI:SetSize(1365, 768); w.G.GetPhysicalScreenSize = function() return 1920, 1080 end
    w.ns.db.scale = { table = 1.6 }
    w.ns.client:openTable{ game = "belot", access = "guild", turn = 45 }; w:advance(0)
    local f = w.ns.TableFrame.frame
    eq(f:GetScale(), 1.6) -- 560 x 420 at 1.6 fits 1365 x 768
    w.ns.client:stand(); w:advance(0)
    w.ns.client:openTable{ game = "chess", access = "guild", turn = 45 }; w:advance(0)
    eq({ f:GetWidth(), f:GetHeight() }, { 780, 660 })
    ok(math.abs(f:GetScale() - 768 / 660) < 1e-9, "the chess table passes the screen: " .. f:GetScale())
    w.ns.client:stand(); w:advance(0)
    w.ns.client:openTable{ game = "belot", access = "guild", turn = 45 }; w:advance(0)
    eq(f:GetScale(), 1.6); eq(w.ns.db.scale.table, 1.6)
  end)

  it("the grip names what it does in its tooltip", function()
    local w = boot()
    w.ns.MainWindow.show()
    local grip = gripOf(w.ns.MainWindow.frame)
    grip.scripts.OnEnter(grip)
    eq(w.G.GameTooltip.lines[1], w.ns.L("resize.tip"))
    grip.scripts.OnLeave(grip)
  end)
  -- A clamped window is drawn inside the screen even when its anchor lies past an edge;
  -- the client starts a drag from the anchor, so the window stuck to that edge until the
  -- cursor made up the difference. Every drag now starts from where it is seen.
  it("a drag starts from where the window is seen, even when its anchor lies past an edge", function()
    local w = boot()
    w.ns.MainWindow.show()
    local f = w.ns.MainWindow.frame
    local sw, sh = w.G.UIParent:GetWidth(), w.G.UIParent:GetHeight()
    local fw, fh = f:GetWidth(), f:GetHeight()
    f.left, f.top = sw - fw + 300, fh - 200 -- 300 past the right edge, 200 under the bottom one
    f.scripts.OnDragStart(f)
    ok(f.moving, "not moving")
    local p = f.points[#f.points]
    eq({ p[1], p[3] }, { "TOPLEFT", "BOTTOMLEFT" }); ok(p[2] == w.G.UIParent, "not on UIParent")
    ok(math.abs(p[4] - (sw - fw)) < 1e-9, "left not on the screen: " .. p[4])
    ok(math.abs(p[5] - fh) < 1e-9, "top not on the screen: " .. p[5])
    f.scripts.OnDragStop(f)
    ok(not f.moving, "still moving")
    ok(f.points[#f.points] == p, "let go: the client keeps where it was dropped")
    -- a window inside the screen keeps its place
    f.left, f.top = 200, 800
    f.scripts.OnDragStart(f)
    p = f.points[#f.points]
    eq({ p[4], p[5] }, { 200, 800 })
    f.scripts.OnDragStop(f)
  end)

  it("the title bar's drag and the table's drag start from the seen place too", function()
    local w = boot()
    w.ns.MainWindow.show()
    local f, bar = w.ns.MainWindow.frame, w.ns.MainWindow.titleBar
    f.left, f.top = -150, 700
    bar.scripts.OnDragStart(bar)
    local p = f.points[#f.points]
    eq({ p[4], p[5] }, { 0, 700 })
    bar.scripts.OnDragStop(bar)
    w.ns.TableFrame.build()
    local t = w.ns.TableFrame.frame
    t.left, t.top = 100, w.G.UIParent:GetHeight() + 120 -- above the top edge
    t.scripts.OnDragStart(t)
    p = t.points[#t.points]
    eq({ p[4], p[5] }, { 100, w.G.UIParent:GetHeight() })
    t.scripts.OnDragStop(t)
  end)

  it("growing a window near the right or bottom edge keeps its corner where the whole window fits", function()
    local w = boot()
    w.ns.MainWindow.show()
    local f, R = w.ns.MainWindow.frame, w.ns.Resize
    local sw = w.G.UIParent:GetWidth()
    f.left, f.top = sw - f:GetWidth() - 10, f:GetHeight() + 10 -- 10 from the right and the bottom edge
    local s = R.set("main", 1.2)
    local p = f.points[#f.points]
    eq({ p[1], p[3] }, { "TOPLEFT", "BOTTOMLEFT" })
    ok(math.abs(p[4] * s - (sw - f:GetWidth() * s)) < 1e-6, "left past the right edge: " .. p[4] * s)
    ok(math.abs(p[5] * s - f:GetHeight() * s) < 1e-6, "bottom under the screen: " .. p[5] * s)
  end)
end)
