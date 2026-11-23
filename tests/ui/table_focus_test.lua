local Wow = require("wow")

local ME, B = "Иван Петров", "Мария Стоянова"

local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot(); w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE"); w:fire("PLAYER_LOGIN")
  return w
end

describe("ui: my table comes to the front", function()
  it("a click on my table in the hall shows and raises the table window above the main one", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    local TF, MW = w.ns.TableFrame, w.ns.MainWindow
    MW.frame:Raise() -- the tavern window in front
    TF.frame:Hide()
    ok(TF.frame:GetFrameLevel() <= MW.frame:GetFrameLevel(), "setup")
    w:click(w.ns.Hall.view.tables[1].top)
    ok(TF.frame:IsShown(), "table hidden")
    ok(TF.frame:GetFrameLevel() > MW.frame:GetFrameLevel(), "not in front")
  end)

  it("the tooltip of my table says so", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    w:hover(w.ns.Hall.view.tables[1].top)
    local lines = w.G.GameTooltip.lines
    eq(lines[#lines], w.ns.L("hall.tip.mine"))
  end)

  it("the list row of my table has „Към масата“ that focuses; another table still sits", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local view = w.ns.Hall.view
    local mine = w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    for i = 1, 8 do
      local host = "Гост " .. i
      w:member(host)
      w:deliver("GUILD", host, { v = 1, t = "TBL", tid = host .. "#1", g = "ttt", h = host, e = 1, ac = "guild", tn = 45, st = "open", s = { host, false }, w = 0 })
    end
    w:advance(0)
    eq(w.ns.Hall.mode, "list")
    local row = view.rows[1]
    eq(row.tid, mine)
    eq(row.act, "open"); ok(row.action:IsVisible(), "no button")
    eq(row.action.text:GetText(), "Към масата")
    local TF, MW = w.ns.TableFrame, w.ns.MainWindow
    MW.frame:Raise(); TF.frame:Hide()
    w:click(row.action)
    ok(TF.frame:IsShown() and TF.frame:GetFrameLevel() > MW.frame:GetFrameLevel(), "not focused")
    eq(view.rows[2].action.text:GetText(), "Седни")
  end)

  it("a mouse-down on either window raises it", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    local TF, MW = w.ns.TableFrame, w.ns.MainWindow
    MW.frame.scripts.OnMouseDown(MW.frame)
    ok(MW.frame:GetFrameLevel() > TF.frame:GetFrameLevel(), "main not raised")
    TF.frame.scripts.OnMouseDown(TF.frame)
    ok(TF.frame:GetFrameLevel() > MW.frame:GetFrameLevel(), "table not raised")
  end)
end)
