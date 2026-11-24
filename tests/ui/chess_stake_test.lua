local Staked = require("staked")

-- A staked draw of Шах in the UI: its line in „История“, and no bill at my table.
local ME, B = "Иван Петров", "Мария Стоянова"

local function plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- A real player says HI (with a GUID) so Presence knows him.
local function hello(w, name)
  w:member(name)
  w:deliver("GUILD", name, { v = 1, t = "HI", ver = "0.1.0", cls = "PRIEST", id = "Player-1-" .. name })
end

-- The history lines of my client whose text names chess.
local function chessLines(w)
  local out = {}
  for _, l in ipairs(w.ns.HistoryTab.lines(w.ns.client)) do
    if l.kind == "game" and plain(l.text):find("Шах", 1, true) then out[#out + 1] = l end
  end
  return out
end

describe("ui: a staked draw of Шах", function()
  it("the history line says draw, with its own mark", function()
    local w = Staked.readyWow()
    local L = w.ns.L
    w.ns.client.ledgerNet:make("R", { gid = ME .. "#1/1", g = "chess", n = { ME, B }, w = {}, l = {}, sk = 50000 })
    w:advance(1); w:advance(0)
    local lines = chessLines(w)
    eq(#lines, 1)
    eq(plain(lines[1].text), L("history.draw", "Шах", ME .. L("history.and") .. B))
    eq(lines[1].mark, L("history.mark.drawn"))
    eq(lines[1].mark, "реми, без дълг")
    eq(lines[1].amount, w:coins("5g"))
  end)

  it("after a staked draw at my table the bill raises no error and names no debtor", function()
    local w = Staked.readyWow()
    local client = w.ns.client
    local tid = assert(client:openTable{ game = "chess", access = "guild", turn = 45, opt = { clock = 10 }, stake = 50000 })
    w:advance(0)
    hello(w, B)
    w:deliver("WHISPER", B, { v = 1, t = "SIT", tid = tid, seat = 2, sk = 50000 })
    w:advance(0)
    local s = client.session
    eq(s.status, "live")
    s:play(2, { k = "move", f = 13, t = 29 }) -- Мария, white, e2e4
    eq(#s.state.moves, 1)
    ok(client:act{ k = "offer" }); w:advance(0)
    s:play(2, { k = "accept" }); w:advance(0)
    eq(s.state.result.reason, "agreed")
    w.ns.TableFrame.render()
    w:advance(1); w:advance(0)
    eq(w.ns.StakePanels.notes(client, s), nil)
    eq(client.stakes:last(tid), nil)
    local bill = w.ns.TableFrame.view.bill
    ok(not (bill and bill:IsVisible()), "a bill for a draw")
    eq(w.ns.StakePanels.shown, false)
    local lines = chessLines(w)
    eq(#lines, 1)
    eq(lines[1].mark, w.ns.L("history.mark.drawn"))
  end)
end)
