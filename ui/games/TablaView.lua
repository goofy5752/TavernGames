local _, ns = ...

-- The Табла board (mockup 07 variant 1, the Табла strip), 512 x 260, centred
-- on the felt as Сантасе is. Left the board 404 x 232 from my side (a
-- watcher: seat 1's): a wood rim, the dark field, 24 points of 28 x 96 (my
-- point 1 bottom right, 12 bottom left, 13 top left, 24 top right), the bar
-- between the quadrants and the tray on the right. Up to five checkers per
-- point, 17 px apart from its base (a pinned checker first), a number on the
-- fifth above five; light checkers for seat 1, dark for seat 2. A ring on
-- each checker I may pick (bright on the picked one), a glow on each point
-- the picked checker may land on. Right: the variant and the game, the score
-- to 5, the dice (a played one dimmed), the steps left, „Върни“ and
-- „Готово“; under the board the line of text. It draws only what
-- ns.TablaModel.build returns. A move is staged here step by step and goes
-- to the client as one action on „Готово“; any table event throws a staged
-- move away. The view never sends chat or rolls.
-- The frame keeps the 24 point buttons in `spikes` (not `points`: the test
-- fake keeps a frame's anchors in its `points` field).
local Theme, W, L = ns.Theme, ns.W, ns.L
local E = ns.Engines.tabla
local M = ns.TablaModel

local WIDTH, HEIGHT = 512, 260
local BOARD_W, BOARD_H, RIM = 404, 232, 8
local POINT_W, POINT_H = 28, 96
local CHECKER, STEP, SHOWN = 26, 17, 5
local BAR_X, BAR_W, TRAY_X, TRAY_W = 176, 24, 368, 28
local TOP_Y, BOTTOM_Y = -8, -128
local COL_X = 412                 -- the right column
local DIE, DICE_Y = 32, -70
local DIE_X = { 426, 466 }
local BUTTON_X, BUTTON_W, BUTTON_H = 414, 96, 24
local GLOW_ALPHA, RING_DIM, DIE_DIM, OFF_ALPHA = 0.45, 0.45, 0.4, 0.5
local BAR, TRAY = 25, 0           -- the bar and the tray as points of a step
local COLOUR = { "bone", "walnut" } -- seat -> checker colour token

local View = {}

---------------------------------------------------------------------------
-- Acting
---------------------------------------------------------------------------

-- What the table has seen: an event (or another table, or a new host) changes it.
local function eventKey(s) return tostring(s.tid) .. "/" .. tostring(s.epoch) .. "/" .. tostring(s.seq) end

local function redraw(f)
  if f.session then View.update(f, f.session) end
end

-- A click on point `q` (the bar: 25, the tray: 0): land the picked checker
-- there, else pick the checker on it (the picked one again: drop the pick).
local function onPoint(f, q)
  local m = f.model
  if not m or f.sent then return end
  if m.to[q] then
    f.staged[#f.staged + 1] = { f.pick, q }
    f.pick = nil
  elseif m.from[q] then
    f.pick = f.pick ~= q and q or nil
  end
  redraw(f)
end

local function onUndo(f)
  if f.sent then return end
  f.staged[#f.staged] = nil
  f.pick = nil
  redraw(f)
end

local function onDone(f)
  local m, client = f.model, ns.client
  if not m or not m.canDone or f.sent or not client then return end
  local steps = {}
  for i, step in ipairs(f.staged) do steps[i] = { step[1], step[2] } end
  if client:act({ k = "move", steps = steps }) then
    f.sent = true
  else
    f.staged, f.pick = {}, nil
  end
  redraw(f)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function fill(f, token, x, y, w, h, layer)
  local t = f:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(Theme.color[token][1], Theme.color[token][2], Theme.color[token][3], 1)
  t:SetSize(w, h)
  t:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  return t
end

-- Five checkers on `widget` from its `edge` ("TOP" grows down, "BOTTOM"
-- up), appended to `list`; the number above five on the fifth -> that label.
local function stack(widget, edge, list)
  local dir = edge == "TOP" and -1 or 1
  local fifth
  for k = 1, SHOWN do
    local c = widget:CreateTexture(nil, "ARTWORK")
    c:SetTexture(Theme.tex.checker)
    c:SetSize(CHECKER, CHECKER)
    c:SetPoint(edge, widget, edge, 0, dir * (k - 1) * STEP)
    c:Hide()
    list[#list + 1] = c
    fifth = c
  end
  local count = W.Label(widget, "heading", "", 11)
  count:SetJustifyH("CENTER")
  count:SetPoint("CENTER", fifth, "CENTER", 0, 0)
  count:Hide()
  return count
end

-- The glow over a target and the ring around a checker I may pick.
local function marks(widget)
  local glow = widget:CreateTexture(nil, "OVERLAY")
  glow:SetTexture(Theme.tex.glow)
  glow:SetAllPoints(widget)
  glow:SetVertexColor(Theme.rgb("glow"))
  glow:SetAlpha(GLOW_ALPHA)
  glow:SetBlendMode("ADD")
  glow:Hide()
  widget.glow = glow
  local ring = widget:CreateTexture(nil, "OVERLAY")
  ring:SetTexture(Theme.tex.ring)
  ring:SetSize(CHECKER + 4, CHECKER + 4)
  ring:Hide()
  widget.ring = ring
end

local function spot(f, q, x, y, w, h)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", function() onPoint(f, q) end)
  return b
end

-- Point q's TOPLEFT on the board from my side.
local function pointXY(q)
  if q <= 6 then return 200 + (6 - q) * POINT_W, BOTTOM_Y end
  if q <= 12 then return 8 + (12 - q) * POINT_W, BOTTOM_Y end
  if q <= 18 then return 8 + (q - 13) * POINT_W, TOP_Y end
  return 200 + (q - 19) * POINT_W, TOP_Y
end

local function point(f, q)
  local x, y = pointXY(q)
  local p = spot(f, q, x, y, POINT_W, POINT_H)
  local tri = p:CreateTexture(nil, "BACKGROUND")
  tri:SetTexture(Theme.tex.point)
  tri:SetAllPoints(p)
  if q <= 12 then tri:SetTexCoord(0, 1, 1, 0) end -- the lower row points up
  tri:SetVertexColor(Theme.rgb(q % 2 == 1 and "felt" or "pointLight"))
  p.tri = tri
  p.checkers = {}
  p.count = stack(p, q <= 12 and "BOTTOM" or "TOP", p.checkers)
  marks(p)
  return p
end

local function trayNumber(tray, edge, y)
  local fs = W.Label(tray, "heading", "", 13)
  fs:SetJustifyH("CENTER")
  fs:SetPoint(edge, tray, edge, 0, y)
  fs:Hide()
  return fs
end

function View.build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(WIDTH, HEIGHT)
  f.names, f.staged = {}, {}

  fill(f, "wood", 0, 0, BOARD_W, BOARD_H)
  fill(f, "boardField", RIM, -RIM, BOARD_W - 2 * RIM, BOARD_H - 2 * RIM, "BORDER")

  f.spikes = {}
  for q = 1, 24 do f.spikes[q] = point(f, q) end

  local bar = spot(f, BAR, BAR_X, -RIM, BAR_W, BOARD_H - 2 * RIM)
  fill(bar, "boardBar", 0, 0, BAR_W, BOARD_H - 2 * RIM)
  bar.checkers = {}
  bar.count = stack(bar, "BOTTOM", bar.checkers)    -- mine, in its lower half
  bar.countOpp = stack(bar, "TOP", bar.checkers)    -- the opponent's, in its upper half
  marks(bar)
  f.bar = bar

  local tray = spot(f, TRAY, TRAY_X, -RIM, TRAY_W, BOARD_H - 2 * RIM)
  fill(tray, "boardBar", 0, 0, TRAY_W, BOARD_H - 2 * RIM)
  tray.own = trayNumber(tray, "BOTTOM", 8)
  tray.opp = trayNumber(tray, "TOP", -8)
  marks(tray)
  f.tray = tray

  f.title = W.Label(f, "heading", "", 14)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", COL_X, -4)
  f.score = W.Label(f, "dim", "", 11)
  f.score:SetPoint("TOPLEFT", f, "TOPLEFT", COL_X, -24)
  f.dice = {}
  for k = 1, 2 do
    local d = f:CreateTexture(nil, "ARTWORK")
    d:SetTexture(Theme.tex.dice)
    d:SetSize(DIE, DIE)
    d:SetPoint("TOPLEFT", f, "TOPLEFT", DIE_X[k], DICE_Y)
    d:Hide()
    f.dice[k] = d
  end
  f.stepsLeft = W.Label(f, "dim", "", 11)
  f.stepsLeft:SetPoint("TOPLEFT", f, "TOPLEFT", COL_X, -110)

  f.undoButton = W.GhostButton(f, L("tabla.undo"), "brassLight", function() onUndo(f) end)
  f.undoButton:SetSize(BUTTON_W, BUTTON_H)
  f.undoButton:SetPoint("TOPLEFT", f, "TOPLEFT", BUTTON_X, -176)
  f.doneButton = W.GoldButton(f, L("tabla.done"), function() onDone(f) end)
  f.doneButton:SetSize(BUTTON_W, BUTTON_H)
  f.doneButton:SetPoint("TOPLEFT", f, "TOPLEFT", BUTTON_X, -206)

  f.text = W.Label(f, "heading", "", 14)
  f.text:SetJustifyH("CENTER")
  f.text:SetWordWrap(false)
  f.text:SetPoint("CENTER", f, "TOPLEFT", BOARD_W / 2, -246)
  return f
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- „бели · 2“ / „черни · 1“: the plate's colour and games won.
function View.seatNote(s, seat)
  if not s.state then return "" end
  return L(seat == 1 and "tabla.light" or "tabla.dark", s.state.score[seat])
end

-- Who sits where while the match runs, so the line at its end can still name
-- a player whose seat emptied when he left.
local function remember(f, s)
  if f.namesTid ~= s.tid then f.namesTid, f.names = s.tid, {} end
  if not E.over(s.state) then
    for seat = 1, 2 do f.names[seat] = s.seats[seat] or nil end
  end
end

-- Checkers `first` .. `last` of `list` as a stack of `seats` (base first);
-- the number on the fifth above five -> the outermost checker drawn.
local function drawStack(list, first, count, seats)
  local n = #seats
  for k = 1, SHOWN do
    local c, seat = list[first + k - 1], seats[k]
    if seat then
      c.seat = seat
      c:SetVertexColor(Theme.rgb(COLOUR[seat]))
    end
    c:SetShown(seat ~= nil)
  end
  count:SetText(tostring(n))
  count:SetTextColor(Theme.rgb(n > 0 and seats[math.min(n, SHOWN)] == 1 and "woodDark" or "ink"))
  count:SetShown(n > SHOWN)
  return n > 0 and list[first + math.min(n, SHOWN) - 1] or nil
end

local function rep(list, seat, n)
  for _ = 1, n do list[#list + 1] = seat end
  return list
end

-- The seats of a point's checkers, base first: the pinned one, then the rest.
local function pointSeats(m, pt)
  if pt.under == "own" then return rep(rep({ m.me }, m.op, pt.opp), m.me, pt.own - 1) end
  if pt.under == "opp" then return rep(rep({ m.op }, m.me, pt.own), m.op, pt.opp - 1) end
  return rep(rep({}, m.me, pt.own), m.op, pt.opp)
end

local function drawMarks(widget, m, q, outer)
  widget.glow:SetShown(m.to[q] == true)
  local from = m.from[q] == true and outer ~= nil
  if from then
    widget.ring:ClearAllPoints()
    widget.ring:SetPoint("CENTER", outer, "CENTER", 0, 0)
    widget.ring:SetAlpha(m.pick == q and 1 or RING_DIM)
  end
  widget.ring:SetShown(from)
end

local function drawBoard(f, m)
  for q = 1, 24 do
    local p = f.spikes[q]
    drawMarks(p, m, q, drawStack(p.checkers, 1, p.count, pointSeats(m, m.points[q])))
  end
  local bar = f.bar
  local mine = drawStack(bar.checkers, 1, bar.count, rep({}, m.me, m.bar.own))
  drawStack(bar.checkers, SHOWN + 1, bar.countOpp, rep({}, m.op, m.bar.opp))
  drawMarks(bar, m, BAR, mine)
  local tray = f.tray
  tray.own:SetText(tostring(m.off.own))
  tray.own:SetShown(m.off.own > 0)
  tray.opp:SetText(tostring(m.off.opp))
  tray.opp:SetShown(m.off.opp > 0)
  tray.glow:SetShown(m.to[TRAY] == true)
end

local function contains(list, x)
  for _, y in ipairs(list) do
    if y == x then return true end
  end
  return false
end

local function drawSide(f, st, m)
  f.title:SetText(L("tabla.title", L("tabla.var." .. tostring(m.var)), m.game))
  f.score:SetText(L("tabla.score", m.score.me, m.score.op))
  local dice = m.dice
  local shown = dice ~= nil and not (m.rolling and st.phase == "open")
  for k = 1, 2 do
    local d = f.dice[k]
    if shown then
      d:SetTexCoord(Theme.dieCoord(dice[k]))
      d:SetAlpha(contains(m.left, dice[k]) and 1 or DIE_DIM)
    end
    d:SetShown(shown)
  end
  f.stepsLeft:SetText(L("tabla.stepsLeft", #m.left))
  f.stepsLeft:SetShown(st.phase == "move")
  for _, pair in ipairs({ { f.undoButton, m.canUndo }, { f.doneButton, m.canDone } }) do
    local b, on = pair[1], pair[2] and not f.sent
    b:SetShown(m.seated)
    b:SetEnabled(on)
    b:SetAlpha(on and 1 or OFF_ALPHA)
  end
end

-- The line of text; the match's end line hides under the bill of a staked match (ns.StakePanels.shown).
local function drawText(f, st, m)
  local t = m.text
  if not t or (E.over(st) and ns.StakePanels.shown) then
    f.text:SetText("")
    f.text:Hide()
    return
  end
  local args = {}
  for k = 2, #t do
    local x = t[k]
    args[k - 1] = type(x) == "string" and W.colored(ns.client, x) or x
  end
  f.text:SetText(L(t[1], unpack(args)))
  f.text:SetTextColor(Theme.rgb((st.phase == "game" or st.phase == "match") and "gold" or "ink"))
  f.text:Show()
end

function View.update(f, s)
  f.session = s
  local st = s.state
  remember(f, s)
  local key = eventKey(s)
  if f.key ~= key then f.key, f.staged, f.pick, f.sent = key, {}, nil, nil end
  local m = M.build(s, f.staged, f.pick, f.names)
  if m.reset then
    f.staged, f.pick, f.sent = {}, nil, nil
    m = M.build(s, f.staged, nil, f.names)
  end
  f.pick = m.pick
  f.model = m

  drawBoard(f, m)
  drawSide(f, st, m)
  drawText(f, st, m)
end

ns.TableFrame.registerView(E.id, View)
