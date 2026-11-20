local _, ns = ...

-- The Морски шах board (mockup 03 `.ttt`): 3x3 cells of 62 px with 6 px gaps,
-- X in light brass and O in #e2735a (Alegreya SC 44). On my turn an empty cell
-- shows a faint ghost of my mark on hover and a click marks it; when it is not
-- my turn, or I only watch, the cells are dimmed and not clickable. The cells
-- of `state.line` glow gold. Above the board: „до 3 победи“ and the score
-- (seat 1 : seat 2). In phase "match": the winner and „Реванш“, then „Чакаме
-- <Име>…“ once I asked for it (watchers see only the winner).
local Theme, W, L = ns.Theme, ns.W, ns.L
local E = ns.Engines.ttt

local CELL, GAP, TOP_H, BOTTOM_H = 62, 6, 46, 54
local BOARD = 3 * CELL + 2 * GAP
local DIM_ALPHA, GHOST_ALPHA = 0.55, 0.25
local MARK = { "ttt.x", "ttt.o" }
local MARK_COLOR = { "brassLight", "oMark" }

local View = {}

local function setCellLook(cell, glowing)
  local c = Theme.color[glowing and "gold" or "woodDark"]
  cell.bg:SetColorTexture(c[1], c[2], c[3], glowing and 0.18 or 0.7)
  cell.edges.setColor(Theme.rgb(glowing and "gold" or "brassDim"))
end

local function showGhost(cell)
  cell.ghost:SetShown(cell.playable and cell.hovered)
end

local function cellWidget(f, i)
  local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(CELL, CELL)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", col * (CELL + GAP), -(TOP_H + row * (CELL + GAP)))
  b:RegisterForClicks("LeftButtonUp")
  local cell = { button = b }
  cell.bg = b:CreateTexture(nil, "BACKGROUND")
  cell.bg:SetAllPoints(b)
  cell.edges = W.edges(b, 1)
  cell.mark = W.Label(b, "heading", "", 44)
  cell.mark:SetJustifyH("CENTER")
  cell.mark:SetPoint("CENTER", b, "CENTER", 0, 0)
  cell.ghost = W.Label(b, "heading", "", 44)
  cell.ghost:SetJustifyH("CENTER")
  cell.ghost:SetPoint("CENTER", b, "CENTER", 0, 0)
  cell.ghost:SetAlpha(GHOST_ALPHA)
  cell.ghost:Hide()
  b:SetScript("OnEnter", function() cell.hovered = true; showGhost(cell) end)
  b:SetScript("OnLeave", function() cell.hovered = false; showGhost(cell) end)
  b:SetScript("OnClick", function()
    local client = ns.client
    if client and cell.playable then client:act({ k = "mark", c = i }) end
  end)
  setCellLook(cell, false)
  return cell
end

function View.build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(BOARD, TOP_H + BOARD + BOTTOM_H)
  f.upTo = W.Label(f, "dim", L("ttt.upTo", E.WINS), 12)
  f.upTo:SetJustifyH("CENTER")
  f.upTo:SetPoint("TOP", f, "TOP", 0, 0)
  f.score = W.Label(f, "heading", "", 20)
  f.score:SetTextColor(Theme.rgb("brassLight"))
  f.score:SetJustifyH("CENTER")
  f.score:SetPoint("TOP", f.upTo, "BOTTOM", 0, -2)
  f.cells = {}
  for i = 1, 9 do f.cells[i] = cellWidget(f, i) end
  local below = -(TOP_H + BOARD + 8)
  f.result = W.Label(f, "heading", "", 16)
  f.result:SetTextColor(Theme.rgb("gold"))
  f.result:SetJustifyH("CENTER")
  f.result:SetPoint("TOP", f, "TOP", 0, below)
  f.rematch = W.Button(f, L("ttt.rematch"), function()
    local client = ns.client
    if client then client:act({ k = "rematch" }) end
  end, true)
  f.rematch:SetSize(100, 22)
  f.rematch:SetPoint("TOP", f.result, "BOTTOM", 0, -6)
  f.waiting = W.Label(f, "dim", "", 12)
  f.waiting:SetJustifyH("CENTER")
  f.waiting:SetPoint("TOP", f.result, "BOTTOM", 0, -9)
  return f
end

-- The mark of `seat` in its color, for the table frame's nameplates.
function View.seatNote(_, seat)
  if not MARK[seat] then return nil end
  return W.paint(L(MARK[seat]), Theme.rgb(MARK_COLOR[seat]))
end

local function paintMark(fs, seat)
  fs:SetText(L(MARK[seat]))
  fs:SetTextColor(Theme.rgb(MARK_COLOR[seat]))
end

function View.update(f, s)
  local st, me, client = s.state, s.mySeat, ns.client
  local live = s.status == "live"
  local myTurn = live and st.phase == "play" and me ~= nil and st.turn == me
  local dim = not live or (st.phase == "play" and not myTurn)
  local glowing = {}
  for _, c in ipairs(st.line or {}) do glowing[c] = true end
  for i = 1, 9 do
    local cell, v = f.cells[i], st.board[i]
    if v == 1 or v == 2 then
      paintMark(cell.mark, v)
    else
      cell.mark:SetText("")
    end
    setCellLook(cell, glowing[i] == true)
    cell.playable = myTurn and v == 0
    cell.button:SetEnabled(cell.playable)
    cell.button:SetAlpha(dim and DIM_ALPHA or 1)
    if me == 1 or me == 2 then paintMark(cell.ghost, me) end
    cell.ghost:SetAlpha(GHOST_ALPHA)
    showGhost(cell)
  end
  f.score:SetText(L("ttt.score", st.score[1], st.score[2]))

  local match = live and st.phase == "match"
  local winner = match and s.seats[st.winner]
  f.result:SetText(winner and L("ttt.winner", W.colored(client, winner)) or "")
  f.result:SetShown(winner and true or false)
  local player = match and (me == 1 or me == 2)
  local asked = player and st.rematch and st.rematch[me]
  local other = player and s.seats[3 - me]
  f.rematch:SetShown(player and not asked)
  f.waiting:SetText(asked and other and L("ttt.waitingFor", W.colored(client, other)) or "")
  f.waiting:SetShown(asked and other and true or false)
end

ns.TableFrame.registerView(E.id, View)
