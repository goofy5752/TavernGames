local Staked = require("staked")
local guildWow = Staked.guildWow

-- Шах in the hall and in the new-table dialog: the game time instead of the turn time.

-- How many visible texts are exactly `text` („5 мин“ is also inside „15 мин“).
local function shown(w, text)
  local n = 0
  for _, r in ipairs(w:texts(text)) do if r.text == text then n = n + 1 end end
  return n
end

-- The dialog is open on `game`; „Със залог“ chosen when `stake`.
local function opened(game, stake)
  local w = guildWow(); w.ns.MainWindow.show()
  local D = w.ns.NewTableDialog
  D.open(game)
  if stake then w:click(D.stakeGold.options[2].frame) end
  return w, D
end

describe("ui: Шах in the hall and the new-table dialog", function()
  it("the hall lists chess last", function()
    local w = guildWow(); w.ns.MainWindow.show()
    local games = w.ns.Hall.view.games
    eq(#games, 7); eq(games[7].id, "chess"); eq(games[7].name:GetText(), "Шах")
  end)

  it("the dialog shows the game time and hides the turn time", function()
    local w = opened("chess")
    for _, t in ipairs{ "Време за партия", "5 мин", "10 мин", "15 мин", "30 мин", "Без лимит" } do
      eq(shown(w, t), 1, t)
    end
    eq(shown(w, "Време за ход"), 0)
    local w2, D2 = opened("chess", true)
    eq(shown(w2, "Без лимит"), 0); eq(shown(w2, "Време за партия"), 1); eq(shown(w2, "Време за ход"), 0)
    local w3 = opened("ttt")
    eq(shown(w3, "Време за ход"), 1)
  end)

  it("the table is opened with the chosen time", function()
    local w, D = opened("chess")
    for _, o in ipairs(D.options.clock.options) do
      if o.value == 15 then w:click(o.frame) end
    end
    w:click(D.openButton)
    local client = w.ns.client
    ok(client.session, "no table")
    eq(client.session.opt.clock, 15); eq(client.session.turn, w.ns.Const.TURN_DEFAULT)
  end)

  it("the hall row and tooltip show the game time of a table opened with the default options", function()
    local w, D = opened("chess")
    w:click(D.openButton) -- nothing chosen: the default time
    w:advance(0)
    local sent = w:sentOf("TBL")
    local advert = assert(sent[#sent], "no TBL").msg
    -- another member sees that advert (its host renamed: I am the viewer here)
    local B, viewer = "Мария Стоянова", guildWow()
    viewer.ns.MainWindow.show()
    local m = viewer.ns.Util.copy(advert)
    eq(m.o, { clock = 10 })
    m.h, m.tid, m.s = B, B .. "#1", { B, false }
    viewer:member(B); viewer:deliver("GUILD", B, m); viewer:advance(0)
    local t = viewer.ns.Hall.view.tables[1]
    eq(t.tid, B .. "#1")
    viewer:hover(t.top)
    local tip = table.concat(viewer.G.GameTooltip.lines, " | ")
    ok(tip:find("Време за партия 10 мин", 1, true), tip)
    -- eight more tables turn the floor into the list: the row says the same
    for i = 1, 8 do
      local host = "Гост " .. i
      viewer:member(host)
      viewer:deliver("GUILD", host, { v = 1, t = "TBL", tid = host .. "#1", g = "ttt", h = host, e = 1, ac = "guild", tn = 45,
        st = "open", s = { host, false }, w = 0 })
    end
    viewer:advance(0)
    local row
    for _, r in ipairs(viewer.ns.Hall.view.rows) do
      if r.frame:IsVisible() and r.title:GetText():find("Шах", 1, true) then row = r end
    end
    ok(row, "no chess row")
    ok(row.sub:GetText():find("Време за партия 10 мин", 1, true), row.sub:GetText())
  end)

  it("the title names the game time once", function()
    local w = guildWow(); local T = w.ns.TableFrame
    T.registerView("chess", { update = function() end,
      build = function(parent) return w.G.CreateFrame("Frame", nil, parent) end })
    w.ns.client:openTable{ game = "chess", access = "guild", turn = 45, opt = { clock = 10 } }; w:advance(0)
    local meta = T.view.meta:GetText()
    local n, from = 0, 1
    while true do
      local i, j = meta:find("Време за партия 10 мин", from, true)
      if not i then break end
      n, from = n + 1, j + 1
    end
    eq(n, 1, meta); eq(meta:find("с на ход", 1, true), nil, meta)
  end)

  it("Session.open refuses a staked table without a limit", function()
    local w = guildWow()
    local tid, why = w.ns.client:openTable{ game = "chess", access = "guild", turn = 45, stake = 50000, opt = { clock = 0 } }
    eq(tid, nil); eq(why, "opt")
  end)
end)
