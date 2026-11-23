local _, ns = ...

-- „История“: the table's last hands (ui/HandHistory.lua) in a side window beside
-- the table frame (its child: it moves and scales with it, ui/Resize.lua), never
-- over the felt, its cards or its buttons. The button sits in the title bar left of
-- ⓘ at a Белот, Сантасе or Холдем table only and toggles it; it closes when I leave
-- the table or another table's session comes. The newest hand on top, the hand
-- under way growing as it is played, the list scrolled with the mouse wheel (W.Scroll).
--   Белот / Сантасе: „Ръка N“, the contract or the trump suit, every trick in
--   order — each seat's name in its class colour and its card (the rank and a
--   tiny suit, H.card), then who took it — Сантасе's declarations, close and swap
--   before the trick they open, the hand's result.
--   Холдем: „Ръка N · Блайндове 5 / 10“, my two cards (marked as mine), the
--   actions street by street under the board as it came, the hands shown at the
--   showdown with their category, who won what. Amounts are the table's own
--   (the Холдем view's View.amount: coins at a cash table, chips at a fun one).
-- TableFrame.render calls H.render(v, s) on every redraw; the text is rebuilt
-- only while the panel is open and the history changed (its ver).
local Theme, W, L, Cards = ns.Theme, ns.W, ns.L, ns.Cards
local H = ns.HandHistory

local PANEL_W, PAD, TOP, GAP = 240, 8, 28, 2
local EDGE = 12 -- the window chrome's band, as the table frame's (TableFrame EDGE)
local SIDE_W = PANEL_W + 2 * EDGE -- the side window beside the table frame
local STYLE = { head = { "heading", 13, "gold" }, sub = { "ui", 11, "brassLight" }, line = { "ui", 11, "ink" }, dim = { "ui", 11, "inkDim" } }
local SUIT_CELL = { C = "0:32", D = "32:64", H = "64:96", S = "96:128" } -- the cells of the `suits` strip

local function byte(x) return math.floor(x * 255 + 0.5) end

-- A card as the history prints it: its rank and a tiny suit, red or ink; "?" for none.
function H.card(face)
  if type(face) ~= "string" or not SUIT_CELL[face:sub(2, 2)] then return "?" end
  local r, g, b = Theme.rgb(Cards.red(face) and "oMark" or "ink")
  return W.paint(Cards.rank(face), r, g, b) .. "|T" .. Theme.tex.suits .. ":0:0:0:0:128:32:" .. SUIT_CELL[face:sub(2, 2)]
    .. ":0:32:" .. byte(r) .. ":" .. byte(g) .. ":" .. byte(b) .. "|t"
end

local function cards(list)
  local out = {}
  for k, face in ipairs(list) do out[k] = H.card(face) end
  return table.concat(out, " ")
end

-- The first word of the seat's name in its class colour, "?" for none.
local function who(hand, seat)
  local name = seat and hand.names[seat]
  if type(name) ~= "string" then return "?" end
  return W.colored(ns.client, name, W.firstWord(name))
end

---------------------------------------------------------------------------
-- The words of one hand
---------------------------------------------------------------------------

local function trickLine(add, hand, n, t)
  local parts = {}
  for k, c in ipairs(t.cards) do parts[k] = who(hand, c.seat) .. " " .. H.card(c.face) end
  local text = L("table.historyTrick", n, table.concat(parts, " · "))
  if t.win then text = text .. " · " .. L("table.historyWon", who(hand, t.win)) end
  add("line", text)
end

-- „Игра: Купа, контра“ as the Белот view says it.
local function contractText(c)
  local game = L("belot.bid." .. c.b)
  if c.x == 2 then game = L("belot.x2", game) elseif c.x == 4 then game = L("belot.x4", game) end
  return L("belot.contract", game)
end

local EVENT = { marry = "santase.historyMarry", close = "santase.historyClose", swap = "santase.historySwap" }

local function cardHand(add, hand, game)
  add("head", L("table.historyHand", hand.no))
  if hand.contract then
    add("sub", contractText(hand.contract) .. " · " .. L("belot.by", who(hand, hand.contract.seat)))
  elseif game == "belot" and hand.passed then
    add("dim", L("belot.passed"))
  end
  if hand.tsuit and game == "santase" then add("sub", L("santase.trump", Cards.suitName(hand.tsuit))) end
  local top = 0
  for n in pairs(hand.tricks) do if n > top then top = n end end
  if hand.cur and hand.cur.n > top then top = hand.cur.n end
  for _, e in ipairs(hand.events) do if e.at > top then top = e.at end end
  for n = 1, top do
    for _, e in ipairs(hand.events) do
      if e.at == n then add("dim", L(EVENT[e.k], who(hand, e.seat), e.pts)) end
    end
    local t = hand.tricks[n] or (hand.cur and hand.cur.n == n and hand.cur)
    if t then trickLine(add, hand, n, t) end
  end
  local res = hand.res
  if res then add("sub", res.winner == 0 and L("santase.hand.tie") or L("santase.hand.won", who(hand, res.winner), res.gp)) end
end

local STREET = { [1] = "holdem.historyFlop", [2] = "holdem.historyTurn", [3] = "holdem.historyRiver" }
local BOARD = { [1] = { 1, 3 }, [2] = { 4, 4 }, [3] = { 5, 5 } } -- the board's cards each street brought

local function amount(s, x)
  local view = ns.TableFrame.views.holdem
  return view and view.amount(s, x) or tostring(x)
end

local function holdemHand(add, hand, s)
  add("head", L("table.historyHand", hand.no) .. " · " .. L("holdem.historyBlinds", amount(s, hand.sb or 0), amount(s, hand.bb or 0)))
  if hand.mine then add("sub", L("holdem.historyMine", cards(hand.mine))) end
  for street = 0, 3 do
    if street == 0 then
      add("sub", L("holdem.historyPreflop"))
    elseif hand.board[BOARD[street][2]] then
      local faces = {}
      for k = BOARD[street][1], BOARD[street][2] do faces[#faces + 1] = hand.board[k] end
      add("sub", L(STREET[street], cards(faces)))
    end
    for _, a in ipairs(hand.acts) do
      if a.street == street then
        local verb = a.amt and L("holdem.hist." .. a.k, amount(s, a.amt)) or L("holdem.hist." .. a.k)
        add("line", who(hand, a.seat) .. ": " .. verb)
      end
    end
  end
  if hand.void then return add("dim", L("holdem.void")) end
  for _, x in ipairs(hand.shown or {}) do
    add("line", L("holdem.historyShow", who(hand, x.seat), cards(x.cards), L("holdem.cat." .. tostring(x.cat))))
  end
  local fold = hand.shown and #hand.shown == 0
  for _, x in ipairs(hand.won or {}) do
    add("sub", L(fold and "holdem.historyWonFold" or "holdem.historyWon", who(hand, x.seat), amount(s, x.amt)))
  end
end

-- The panel's text for table s: {style, text} from the newest hand to the oldest.
function H.lines(s)
  local out = {}
  local function add(style, text) out[#out + 1] = { style, text } end
  local b = s and H.tables[s.tid]
  if not b then return out end
  for k = #b.hands, 1, -1 do
    if k < #b.hands then add("dim", " ") end
    if b.game == "holdem" then holdemHand(add, b.hands[k], s) else cardHand(add, b.hands[k], b.game) end
  end
  return out
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function lineAt(panel, i)
  local fs = panel.lines[i]
  if fs then return fs end
  fs = W.Label(panel.scroll.content, "ui", "", 11)
  fs:SetWidth(panel.textW)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  panel.lines[i] = fs
  return fs
end

-- Fills the panel with table s's history (the lines it uses: panel.used).
function H.draw(panel, s)
  local list, y = H.lines(s), 0
  for i, x in ipairs(list) do
    local fs, st = lineAt(panel, i), STYLE[x[1]]
    Theme.setFont(fs, st[1], st[2])
    fs:SetTextColor(Theme.rgb(st[3]))
    fs:SetText(x[2])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", panel.scroll.content, "TOPLEFT", 0, -y)
    fs:Show()
    y = y + fs:GetStringHeight() + GAP
  end
  for i = #list + 1, #panel.lines do panel.lines[i]:Hide() end
  panel.used = #list
  panel.empty:SetShown(#list == 0)
  panel.scroll:setContentHeight(y)
  local b = s and H.tables[s.tid]
  panel.ver, panel.tid = b and b.ver, s and s.tid
end

-- The panel: on its own a dark panel (W.Panel); `framed`, a window with the table
-- frame's chrome (wood and the brass edge), its content EDGE inside.
function H.buildPanel(parent, framed)
  local panel, e
  if framed then
    panel, e = CreateFrame("Frame", nil, parent), EDGE
    panel:SetSize(SIDE_W, 300)
    panel.chrome = W.chrome(panel, SIDE_W, 300)
  else
    panel, e = W.Panel(parent), 0
    panel.fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.95)
    panel:SetSize(PANEL_W, 300)
  end
  panel:EnableMouse(true)
  panel:EnableMouseWheel(true)
  panel.title = W.Label(panel, "heading", L("table.history"), 13)
  panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", e + 10, -(e + 8))
  local x = W.Close(panel)
  x:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(e + 4), -(e + 4))
  panel.close = x
  local scroll = W.Scroll(panel)
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", e + PAD, -(e + TOP))
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(e + PAD), e + PAD)
  panel.textW = PANEL_W - 2 * PAD - 6
  scroll.content:SetWidth(panel.textW)
  panel.scroll = scroll
  panel.lines, panel.used = {}, 0
  panel.empty = W.Label(panel, "dim", L("table.historyEmpty"), 11)
  panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", e + 10, -(e + TOP + 2))
  panel:Hide()
  return panel
end

-- The button and the panel of the table frame (TableFrame.view v), once: the panel
-- is a window of its own BESIDE the frame (its left edge on the frame's right edge,
-- as tall as the frame), a child of it, so it moves and scales with it
-- (ui/Resize.lua) and never lies over the felt, its cards or its buttons.
local function build(v)
  local f = ns.TableFrame.frame
  local panel = H.buildPanel(f, true)
  panel:SetWidth(SIDE_W)
  W.dragBy(panel, f) -- dragging the side window moves the table with it
  panel:SetScript("OnShow", function() H.place(v); H.draw(panel, ns.client and ns.client.session) end)
  v.history = panel
  for _, handle in ipairs({ f, v.title:GetParent(), panel }) do -- the frame, its title bar: moved, placed again
    handle:HookScript("OnDragStop", function() H.place(v) end)
  end
  H.place(v)
  local button = W.GhostButton(f, L("table.history"), "brassLight", function()
    panel:SetShown(not panel:IsShown())
  end)
  button:SetSize(W.textWidth(button.text) + 16, 20)
  button:SetFrameLevel(v.info:GetFrameLevel())
  button:SetPoint("RIGHT", v.info, "LEFT", -8, 0)
  v.historyButton = button
end

-- The side window right of the table frame, or left of it when it would pass the
-- screen's right edge there (the frame is clamped to the screen, the window is not).
function H.place(v)
  local f, panel = ns.TableFrame.frame, v.history
  local left, scale = f:GetLeft(), f:GetEffectiveScale()
  local screen = UIParent:GetWidth() * UIParent:GetEffectiveScale()
  local side = left and (left + f:GetWidth() + SIDE_W) * scale > screen and "left" or "right"
  if panel.side == side then return end
  panel.side = side
  panel:ClearAllPoints()
  if side == "left" then
    panel:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0)
  else
    panel:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
  end
end

-- The title bar's options line (v.meta) on one line, never wider than the room
-- between the crest and what stands right of it (the stake after it, then the
-- watcher count, „История“ and ⓘ).
local function fitMeta(v, kept)
  local bar = ns.TableFrame.frame:GetWidth() - 2 * EDGE
  local left = 8 + W.textWidth(v.title) + 6 + 20 + 6
  local right = 6 + v.info:GetWidth() + 12
  if kept then right = right + 8 + v.historyButton:GetWidth() end
  if v.watchers:IsShown() then right = right + 12 + W.textWidth(v.watchers) end
  if v.stake:IsShown() then right = right + 10 + W.textWidth(v.stake) end
  v.meta:SetWordWrap(false)
  v.meta:SetWidth(math.max(1, math.min(W.textWidth(v.meta), bar - left - right)))
end

-- From TableFrame.render: the button at a table whose game keeps a history (the
-- watcher count left of it), else neither; the panel closed at another table; the
-- open panel redrawn when the history changed.
function H.render(v, s)
  if not v.historyButton then build(v) end
  local kept = s ~= nil and H.GAMES[s.game] == true
  if not kept or v.historyTid ~= s.tid then v.history:Hide() end
  v.historyTid = s and s.tid
  v.historyButton:SetShown(kept)
  v.watchers:ClearAllPoints()
  v.watchers:SetPoint("RIGHT", kept and v.historyButton or v.info, "LEFT", -12, 0)
  fitMeta(v, kept)
  if v.history:IsShown() then H.place(v) end
  local h = ns.TableFrame.frame:GetHeight()
  if v.history.h ~= h then -- the wood tiles, never stretches, as the frame's (TableFrame fit)
    v.history.h = h
    v.history.chrome.wood:SetTexCoord(0, (SIDE_W - 8) / Theme.texSize.wood, 0, (h - 8) / Theme.texSize.wood)
  end
  local b = kept and H.tables[s.tid]
  if v.history:IsShown() and (v.history.tid ~= s.tid or v.history.ver ~= (b and b.ver)) then H.draw(v.history, s) end
end

-- I left my table: its panel goes with it (TableFrame.render draws nothing without a session).
ns.ready(function(client)
  client:on("session", function(s)
    local v = ns.TableFrame.view
    if not s and v and v.history then v.history:Hide(); v.historyTid = nil end
  end)
end)
