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
    eq(grip.points[1], { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3 })
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

  it("the scale stays between MIN and what fits on the screen", function()
    local w = boot()
    w.ns.MainWindow.show()
    local f, R = w.ns.MainWindow.frame, w.ns.Resize
    f.left, f.top = 0, 1080
    local grip = gripOf(f)
    grip.scripts.OnMouseDown(grip, "LeftButton")
    w.cursor = { 0, 1080 }
    grip.scripts.OnUpdate(grip, 0)
    eq(f:GetScale(), R.MIN)
    w.cursor = { 9000, -9000 }
    grip.scripts.OnUpdate(grip, 0)
    ok(math.abs(f:GetScale() - 1080 / 620) < 1e-9, "max " .. f:GetScale()) -- 1920 / 1100 is larger
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
    w.ns.db.scale = { table = 0.8 }
    w.ns.TableFrame.build()
    local f = w.ns.TableFrame.frame
    eq(gripOf(f).key, "table")
    eq(f:GetScale(), 0.8)
  end)

  it("the grip names what it does in its tooltip", function()
    local w = boot()
    w.ns.MainWindow.show()
    local grip = gripOf(w.ns.MainWindow.frame)
    grip.scripts.OnEnter(grip)
    eq(w.G.GameTooltip.lines[1], w.ns.L("resize.tip"))
    grip.scripts.OnLeave(grip)
  end)
end)
