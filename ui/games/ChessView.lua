local _, ns = ...

-- The chess table (mockup 09, piece style B, spec 5.6) over the whole felt, 752 x 568 (the
-- table frame is 780 x 660; `ring = true`: the board is anchored to the felt's corner and the
-- plates go where plateSpots says). Left: a strip of 24 px above the board (the end text, or
-- the opponent's offer of a draw with „Приеми“ and „Откажи“), the board of 8 x 56 px squares in
-- the skin's frame band of 24 px with the coordinates a-h and 1-8 turned to my side (a watcher
-- sees white at the bottom), and under it „Предложи реми“, „Предай се“ (it asks first),
-- „Времето му изтече“ and, to their right, the line of status. Right, 220 px: the opponent's
-- plate with the pieces he took, the move list, my pieces taken and my plate (ui/games/ChessPanels.lua;
-- the plates are the table frame's, ui/TablePlates.lua, with a clock each: seatClock).
-- Two clicks move: one of my pieces selects it (a dot on the free targets, a ring on the
-- captures), a target sends { k = "move", f, t, p } (through the picker of the promotion
-- piece when it promotes), another own piece selects that one, anything else clears; only on
-- my turn. The selection and the picker are dropped whenever the table, the game, the colours,
-- the phase, the turn or the offer change. It draws only what ns.ChessModel.build returns.
local Theme, W, L = ns.Theme, ns.W, ns.L
local M, P = ns.ChessModel, ns.ChessPanels

local SQ, BAND, BOARD = 56, 24, 496
local BOARD_X, STRIP_Y, BOARD_Y, BUTTONS_Y = 8, -4, -32, -536
local LAST_ALPHA = { alliance = 0.48, horde = 0.5 }
local DOT_ALPHA = { alliance = 0.38, horde = 0.42 }
local FILES = { "a", "b", "c", "d", "e", "f", "g", "h" }

local View = { size = { 780, 660 }, ring = true }

local function redraw(f)
  if f.session then View.update(f, f.session) end
end

local function send(f, from, to, promotion)
  local client = ns.client
  f.sel = nil
  if client then client:act({ k = "move", f = from, t = to, p = promotion }) end
  redraw(f) -- the dots go now, not at the host's echo (a refused move leaves nothing behind)
end

-- A click on the cell `i`.
local function onCell(f, i)
  local m = f.model
  if not m or not m.myTurn then return end
  local c = m.cells[i]
  local mine = c.piece ~= 0 and (c.piece > 0) == (m.bottom == 1)
  local target = false
  for _, t in ipairs(m.targets) do if t == c.sq then target = true end end
  if f.sel and target then
    local from = f.sel
    if M.promotes(f.session, from, c.sq) then
      P.promotion(f, f.cells[i], m.bottom, function(letter) send(f, from, c.sq, letter) end)
      return
    end
    send(f, from, c.sq)
  elseif mine and c.sq ~= f.sel then
    f.sel = c.sq
  else
    f.sel = nil
  end
  redraw(f)
end

local function cellWidget(f, i)
  local row, col = math.floor((i - 1) / 8) + 1, (i - 1) % 8 + 1
  local b = CreateFrame("Button", nil, f.board)
  b:SetSize(SQ, SQ)
  b:SetPoint("TOPLEFT", f.board, "TOPLEFT", BAND + (col - 1) * SQ, -(BAND + (row - 1) * SQ))
  b:RegisterForClicks("LeftButtonUp")
  local cell = { button = b, row = row }
  cell.sq = b:CreateTexture(nil, "BACKGROUND")
  cell.sq:SetAllPoints(b)
  cell.last = b:CreateTexture(nil, "ARTWORK", nil, 0)
  cell.last:SetAllPoints(b)
  cell.edges = W.edges(b, 3, "ARTWORK")
  cell.check = b:CreateTexture(nil, "ARTWORK", nil, 1)
  cell.check:SetAllPoints(b)
  cell.check:SetTexture(Theme.chessTex("check"))
  cell.piece = b:CreateTexture(nil, "ARTWORK", nil, 2)
  cell.piece:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -2); cell.piece:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 4)
  cell.dot = b:CreateTexture(nil, "OVERLAY")
  cell.dot:SetAllPoints(b)
  cell.dot:SetTexture(Theme.chessTex("dot"))
  cell.ring = b:CreateTexture(nil, "OVERLAY")
  cell.ring:SetAllPoints(b)
  cell.ring:SetTexture(Theme.chessTex("ring"))
  b:SetScript("OnClick", function() onCell(f, i) end)
  return cell
end

local function label(parent, size, point, x, y)
  local fs = W.Label(parent, "ui", "", size)
  Theme.setFont(fs, "uiBold", size)
  fs:SetJustifyH("CENTER")
  fs:SetPoint("CENTER", parent, point, x, y)
  return fs
end

function View.build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(752, 568)
  local board = CreateFrame("Frame", nil, f)
  board:SetSize(BOARD, BOARD)
  board:SetPoint("TOPLEFT", f, "TOPLEFT", BOARD_X, BOARD_Y)
  local fill = board:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(board)
  fill:SetColorTexture(Theme.rgb("deep"))
  f.board, f.frameBand = board, W.nine(board, Theme.tex.frame, Theme.texSize.frame, 12, BAND, "BORDER", true)
  f.files, f.ranks, f.cells = {}, {}, {}
  for k = 1, 8 do
    f.files[k] = label(board, 12, "BOTTOMLEFT", BAND + (k - 0.5) * SQ, BAND / 2)
    f.ranks[k] = label(board, 12, "TOPLEFT", BAND / 2, -(BAND + (k - 0.5) * SQ))
  end
  for i = 1, 64 do f.cells[i] = cellWidget(f, i) end
  P.build(f)

  -- The strip over the board: the end text, or the offer of a draw.
  local strip = CreateFrame("Frame", nil, f)
  strip:SetSize(BOARD, 24)
  strip:SetPoint("TOPLEFT", f, "TOPLEFT", BOARD_X, STRIP_Y)
  strip.fill = strip:CreateTexture(nil, "BACKGROUND")
  strip.fill:SetAllPoints(strip)
  strip.fill:SetColorTexture(unpack(W.DARK_FILL))
  strip.edges = W.edges(strip, 1)
  strip.edges.setColor(Theme.rgb("brass"))
  strip.text = W.Label(strip, "heading", "", 14)
  strip.text:SetTextColor(Theme.rgb("goldHi"))
  strip.text:SetPoint("LEFT", strip, "LEFT", 10, 0)
  f.accept = W.GoldButton(strip, L("chess.accept"), function() ns.client:act({ k = "accept" }) end)
  f.decline = W.GhostButton(strip, L("chess.decline"), "ink", function() ns.client:act({ k = "decline" }) end)
  for _, b in ipairs({ f.accept, f.decline }) do b:SetHeight(20) end
  f.decline:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
  f.accept:SetPoint("RIGHT", f.decline, "LEFT", -6, 0)
  f.strip = strip

  -- Under the board.
  f.offer = W.GhostButton(f, L("chess.offer"), "gold", function() ns.client:act({ k = "offer" }) end)
  f.resign = W.GhostButton(f, L("chess.resign"), "oMark", function()
    P.confirmResign(f, function() ns.client:act({ k = "resign" }) end)
  end)
  f.claim = W.GoldButton(f, L("chess.claim"), function() ns.Clock.claim(ns.client) end)
  f.claim:SetWidth(150)
  f.offer:SetPoint("TOPLEFT", f, "TOPLEFT", BOARD_X, BUTTONS_Y)
  f.resign:SetPoint("LEFT", f.offer, "RIGHT", 8, 0)
  f.claim:SetPoint("LEFT", f.resign, "RIGHT", 8, 0)
  f.status = W.Label(f, "dim", "", 13)
  f.status:SetJustifyH("RIGHT")
  return f
end

-- The line of status right of the last button shown, ending clear of my plate's portrait (the plates'
-- column is right of the board): shrunk, then wrapped, never under a plate.
local STATUS_GAP = 12
local STATUS_RIGHT = math.min(BOARD_X + BOARD, P.X - 15 - 8) -- clear of my plate's portrait (30 px, centred on its left end)
local function drawStatus(f, text)
  local x, right = BOARD_X, BOARD_X
  for _, b in ipairs({ f.offer, f.resign, f.claim }) do -- each anchored right of the one before
    right = right + (b == f.offer and 0 or 8) + b:GetWidth()
    if b:IsShown() then x = right + STATUS_GAP end
  end
  f.status:ClearAllPoints()
  f.status:SetPoint("LEFT", f, "TOPLEFT", x, BUTTONS_Y - 12)
  W.fitWrap(f.status, text, math.max(1, STATUS_RIGHT - x))
end

-- The plates: the opponent's at the top of the side column, mine (a watcher: white's) at the bottom.
function View.plateSpots(s, _, areaH)
  local bottom = M.bottomSeat(s)
  local spots = {}
  spots[bottom] = { P.X, -(areaH - P.PLATE_H - 4), P.W }
  spots[3 - bottom] = { P.X, -4, P.W }
  return spots, 1
end

-- The colour of the seat, for the plates.
function View.seatNote(s, seat)
  local st = s.state
  if not st or not st.white then return nil end
  return L(seat == st.white and "chess.white" or "chess.black")
end

-- The time of the seat in tenths, "none" without a limit, nil when no game is on. Asked every
-- frame, it also redraws the table once the claim opens or closes: a host that withholds its
-- own flag sends no event to redraw on.
function View.seatClock(s, seat)
  local st = s.state
  if not st or s.status ~= "live" then return nil end
  if not st.clock then return "none" end
  local f = ns.TableFrame.built.chess
  if f and f.claim:IsShown() ~= ns.Clock.canClaim(s) then ns.TableFrame.refresh() end
  return ns.Clock.left(s, seat)
end

-- The files and ranks along the board, turned to the colour at the bottom.
local function coordinates(f, bottom)
  for k = 1, 8 do
    f.files[k]:SetText(FILES[bottom == 1 and k or 9 - k])
    f.ranks[k]:SetText(tostring(bottom == 1 and 9 - k or k))
    f.files[k]:SetTextColor(Theme.rgb("coord"))
    f.ranks[k]:SetTextColor(Theme.rgb("coord"))
  end
end

local function drawCell(cell, c, skin, myTurn)
  local light = ((c.sq - 1) % 8 + math.floor((c.sq - 1) / 8)) % 2 == 1 -- a1 is dark
  cell.sq:SetTexture(Theme.chessTex("sq_" .. skin .. (light and "_l" or "_d")))
  cell.last:SetColorTexture(Theme.rgb("sqLast"))
  cell.last:SetAlpha(LAST_ALPHA[skin])
  cell.last:SetShown(c.last)
  cell.edges.setColor(Theme.rgb("sqSel"))
  for k = 1, 4 do cell.edges[k]:SetShown(c.sel) end
  cell.check:SetShown(c.check)
  cell.piece:SetShown(c.piece ~= 0)
  if c.piece ~= 0 then cell.piece:SetTexture(P.pieceTex(c.piece)) end
  for _, name in ipairs({ "dot", "ring" }) do
    cell[name]:SetVertexColor(Theme.rgb("sqDot"))
    cell[name]:SetAlpha(DOT_ALPHA[skin])
    cell[name]:SetShown(c[name])
  end
  cell.button:SetEnabled(myTurn)
end

-- What the table has seen: another one of these drops the selection and the picker.
local function signature(s, st)
  return table.concat({ tostring(s.tid), #st.moves, tostring(st.white), tostring(st.phase), tostring(st.turn), tostring(st.offer) }, "/")
end

function View.update(f, s)
  local st = s.state
  f.session = s
  local sig = signature(s, st)
  if sig ~= f.sig then
    f.sel, f.sig = nil, sig
    if f.side.promo then f.side.promo.close() end
    if f.side.confirm and st.phase ~= "play" then f.side.confirm.close() end
  end
  local m = M.build(s, f.sel)
  f.model = m
  local skin = Theme.skin
  coordinates(f, m.bottom)
  for i = 1, 64 do drawCell(f.cells[i], m.cells[i], skin, m.myTurn) end
  P.update(f, s, m)

  local me = s.mySeat
  local offered = m.offerFor ~= nil and m.offerFor == me
  f.strip:SetShown(m.banner ~= nil or offered)
  f.strip.text:SetText(m.banner or (offered and L("chess.offered", M.seatName(s, st.offer)) or ""))
  f.accept:SetShown(m.banner == nil and offered)
  f.decline:SetShown(m.banner == nil and offered)
  f.offer:SetShown(m.canOffer)
  f.resign:SetShown(m.canResign)
  f.claim:SetShown(m.canClaim)
  drawStatus(f, m.status)
  if not m.canResign and f.side.confirm then f.side.confirm.close() end
end

ns.TableFrame.registerView("chess", View)
