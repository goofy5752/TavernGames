local _, ns = ...

-- The „История“ window's rows laid out (mockup 10, „Ново“): H.layout(pool, blocks, width, onToggle)
-- draws H.blocks (ui/HandHistoryRows.lua) with the widgets of a ns.HistoryKit pool down a scroll
-- content `width` wide -> the height used. Each hand is a block on a faint plate: its header (a
-- click on it calls onToggle(block)), then, open, its rows, or, closed, its one summary line.
-- No row is ever wider than `width`: a text shrinks, then wraps (W.fitWrap), a name under its card
-- too, and the row grows taller instead; the chess cells are ns.HistoryKit.move's.
local Theme, W = ns.Theme, ns.W
local H = ns.HandHistory
local Kit = ns.HistoryKit

local X0, SLOT, NUM, STREET_W = 6, 48, 17, 58 -- the rows' inset, a trick card's slot, the trick number's column, a street's name
local NAME_LEAST = math.ceil(W.WRAP_MIN / Theme.fontScale.ui) -- a card's name at its least (9.1 once scaled)
local SMALL, SMALL_H = Kit.CARD.small[1], Kit.CARD.small[2]
local NORMAL_W, NORMAL_H = Kit.CARD.normal[1], Kit.CARD.normal[2]
local FOLD = { 0x8c / 255, 0x82 / 255, 0x70 / 255 }

local function line(P, x, y, w) P:fill(x, y, w, 1, Theme.color.brassLight[1], Theme.color.brassLight[2], Theme.color.brassLight[3], 0.08) end

-- Small cards from x at y, 3 apart; mode(k) -> the k-th card's mode. -> the right edge.
local function smalls(P, x, y, faces, mode)
  for k, face in ipairs(faces) do P:card(x + (k - 1) * (SMALL + 3), y, "small", face, mode and mode(k)) end
  return x + #faces * (SMALL + 3) - 3
end

local R = {}

function R.trick(P, row, y, wd, first)
  if not first then line(P, X0, y, wd) end
  y = y + 4
  P:text(X0, y + 16, 14, tostring(row.n), "heading", 12, "inkDim", "CENTER")
  -- A name under its card in the card's slot; when one does not hold its slot on one line at its
  -- least size (a WoW name's word has up to 12 letters), the names take two lines, the odd cards'
  -- on the first and the even cards' on the second, each as wide as two slots: never broken.
  local stagger = false
  for k = 1, row.slots do
    local c = row.cards[k]
    if c and P:measure(c.name, "ui", NAME_LEAST) > SLOT - 2 then stagger = true end
  end
  local tall, first = 0, 0
  for pass = 1, stagger and 2 or 1 do
    for k = 1, row.slots do
      local c, sx = row.cards[k], X0 + NUM + (k - 1) * SLOT
      if pass == 1 then P:card(sx + (SLOT - 2 - NORMAL_W) / 2, y, "normal", c and c.face, c and c.won and "won" or nil) end
      if c and (not stagger or (k % 2 == 1) == (pass == 1)) then
        local nx, nw, ny = sx, SLOT - 2, y + NORMAL_H + 2 + (pass == 2 and first or 0)
        if stagger then nw = 2 * SLOT - 4; nx = math.max(0, math.min(wd + X0 - nw, sx + (SLOT - 2) / 2 - nw / 2)) end
        local _, h = P:text(nx, ny, nw, c.name, "ui", 10, c.color, "CENTER")
        if c.full then P:hover(nx, ny, nw, h, c.full) end
        if pass == 1 then first = math.max(first, h) end
        tall = math.max(tall, (pass == 2 and first or 0) + h)
      end
    end
  end
  local px = X0 + NUM + row.slots * SLOT
  local text, color = "…", "inkDim"
  if row.pts then text, color = "+" .. row.pts, row.side and H.SIDE[row.side] or "ink" end
  P:text(px, y + 16, wd + X0 - px, text, "uiBold", 12, color, "RIGHT")
  return 4 + NORMAL_H + 2 + math.max(tall, 12) + 4
end

function R.event(P, row, y, wd)
  local x, w = X0 + 14, wd - 14
  local cw = #row.cards > 0 and #row.cards * (SMALL + 3) - 3 or 0
  local text = P:measure(row.text, "ui", 11)
  local h
  if cw == 0 or text + 6 + cw <= w - 12 then -- one line: the words, the cards after them
    local _, th = P:text(x + 6, y + 3 + (cw > 0 and (SMALL_H - 14) / 2 or 0), w - 12 - (cw > 0 and cw + 6 or 0), row.text, "ui", 11, "goldHi")
    if cw > 0 then smalls(P, x + 6 + math.min(text, w - 12 - cw - 6) + 6, y + 3, row.cards) end
    h = math.max(th, cw > 0 and SMALL_H or 0) + 6
  else -- the words, the cards under them
    local _, th = P:text(x + 6, y + 3, w - 12, row.text, "ui", 11, "goldHi")
    smalls(P, x + 6, y + 3 + th + 2, row.cards)
    h = th + 2 + SMALL_H + 6
  end
  P:fill(x, y + 2, w, h - 2, Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.12)
  return h + 2
end

function R.result(P, row, y, wd)
  local text = row.coin and (W.coinTag("gold") .. " " .. row.text) or row.text
  local _, h = P:text(X0 + 6, y + 10, wd - 12, text, "ui", 12, "ink")
  P:fill(X0, y + 5, wd, h + 10, 0, 0, 0, 0.3)
  return h + 15
end

function R.note(P, row, y, wd)
  local _, h = P:text(X0, y + 2, wd, row.text, "ui", 11, "inkDim")
  return h + 4
end

function R.mine(P, row, y, wd)
  local fs = P:text(X0, y + 12, wd - 2 * (SMALL + 3) - 6, row.text, "ui", 11, "inkDim")
  smalls(P, X0 + math.min(W.textWidth(fs), wd - 2 * (SMALL + 3) - 6) + 6, y + 2, row.cards, function() return "mine" end)
  return SMALL_H + 8
end

function R.street(P, row, y, wd, first)
  if not first then line(P, X0, y, wd) end
  local _, h = P:text(X0, y + 5 + (#row.cards > 0 and (SMALL_H - 15) / 2 or 0), STREET_W - 6, row.name, "heading", 12, "brassLight")
  smalls(P, X0 + STREET_W, y + 5, row.cards, function(k) return k <= row.dim and "dim" or nil end)
  return 5 + math.max(h, #row.cards > 0 and SMALL_H or 0) + 3
end

-- Who and what, in two columns under the street's board.
function R.acts(P, row, y, wd)
  local x, aw = X0 + STREET_W, wd - STREET_W
  local whoW = 0
  for _, a in ipairs(row.list) do whoW = math.max(whoW, P:measure(a.name, "ui", 11)) end
  whoW = math.min(math.ceil(whoW), math.floor(aw * 0.45))
  local top = y
  for _, a in ipairs(row.list) do
    local _, h1 = P:text(x, y, whoW, a.name, "ui", 11, a.color)
    if a.full then P:hover(x, y, whoW, h1, a.full) end
    local bold = a.style == "raise" or a.style == "allin"
    local color = a.style == "fold" and FOLD or a.style == "raise" and "goldHi" or a.style == "allin" and "oMark" or "ink"
    local _, h2 = P:text(x + whoW + 8, y, aw - whoW - 8, a.text, bold and "uiBold" or "ui", 11, color)
    y = y + math.max(h1, h2) + 2
  end
  return y - top + 2
end

-- A hand turned up: who, the two cards, its category (under the cards when it does not fit beside).
function R.show(P, row, y, wd)
  line(P, X0, y, wd)
  local nameW = math.min(P:measure(row.name, "ui", 11), 90)
  local _, nh = P:text(X0, y + 4 + (SMALL_H - 14) / 2, nameW, row.name, "ui", 11, row.color)
  if row.full then P:hover(X0, y + 4 + (SMALL_H - 14) / 2, nameW, nh, row.full) end
  local cx = smalls(P, X0 + nameW + 6, y + 4, row.cards) + 6
  local font, color = row.best and "uiBold" or "ui", row.best and "goldHi" or "inkDim"
  local room = X0 + wd - cx
  local h = math.max(nh, SMALL_H)
  if P:measure(row.cat, font, 11) <= room or room >= 80 then
    local _, ch = P:text(cx, y + 4 + (SMALL_H - 14) / 2, room, row.cat, font, 11, color)
    h = math.max(h, ch + (SMALL_H - 14) / 2)
  else
    local _, ch = P:text(X0 + nameW + 6, y + 4 + SMALL_H + 2, X0 + wd - (X0 + nameW + 6), row.cat, font, 11, color)
    h = SMALL_H + 2 + ch
  end
  return h + 8
end

-- Chess: the two sides, each its king's icon and its name.
function R.side(P, row, y, wd)
  local x, left, right, lh, top = X0 + 16, X0 + 16, X0 + wd, 18, y
  for k, s in ipairs(row.list) do
    local need = 20 + P:measure(s.name, "ui", 11) + (k < #row.list and 14 or 0)
    if x > left and x + need > right then x, y = left, y + lh + 2 end
    P:piece(x, y, 16, s.piece, true)
    local fs, sh = P:text(x + 20, y + 2, right - x - 20, s.name, "ui", 11, s.color)
    if s.full then P:hover(x + 20, y + 2, math.min(W.textWidth(fs), right - x - 20), sh, s.full) end
    x = x + 20 + math.min(W.textWidth(fs), right - x - 20) + 4
    if k < #row.list then P:text(x, y + 2, 10, "·", "ui", 11, "inkDim"); x = x + 10 end
  end
  return y - top + lh + 6
end

function R.moves(P, row, y, wd)
  return Kit.moveRows(P, X0, y, wd, row.rows, {}) + 4
end

-- The header of a hand: ▶ / ▼, „Ръка N“, what it was played for (Сантасе: the trump card).
local function header(P, block, y, width, onToggle)
  local top = y
  y = y + 5
  local right = width - 6
  -- a trump card beside the title: the title in the middle of the card's height
  local tw = P:measure(block.title, "heading", 14)
  local beside = block.trump and 28 + tw + P:measure(block.what, "ui", 11) + P:measure(block.after, "ui", 11) + SMALL + 8 <= right
  local dy = beside and (SMALL_H - 18) / 2 or 0
  P:text(6, y + 3 + dy, 12, block.open and "▼" or "▶", "heading", 10, "inkDim")
  local fs, th = P:text(22, y + dy, width - 28, block.title, "heading", 14, "gold")
  local x = 22 + math.min(W.textWidth(fs), width - 28) + 6
  local h = th
  if block.trump then
    if not beside then x, y = 22, y + th + 2 end
    local fa = P:text(x, y + (SMALL_H - 14) / 2, right - x, block.what, "ui", 11, "brassLight")
    local cx = x + math.min(W.textWidth(fa), right - x) + 4
    P:card(cx, y, "small", block.trump)
    P:text(cx + SMALL + 4, y + (SMALL_H - 14) / 2, math.max(1, right - cx - SMALL - 4), block.after, "ui", 11, "brassLight")
    h = y - top - 5 + SMALL_H
  elseif block.what then
    if right - x < 90 then x, y = 22, y + th + 2 end
    local _, wh = P:text(x, y + 3, right - x, block.what, "ui", 11, "brassLight")
    h = math.max(h, y - top - 5 + 3 + wh)
  end
  h = h + 10
  P:button(0, top, width, h, function() onToggle(block) end)
  return h
end

function H.layout(P, blocks, width, onToggle)
  local y = 0
  for _, block in ipairs(blocks) do
    local top = y
    y = y + header(P, block, y, width, onToggle)
    if block.open then
      local wd, first = width - 2 * X0, true
      for _, row in ipairs(block.rows) do
        y = y + R[row.k](P, row, y, wd, first)
        first = first and not (row.k == "trick" or row.k == "street")
      end
      y = y + 4
    elseif block.sum then
      local text = block.coin and (W.coinTag("gold") .. " " .. block.sum) or block.sum
      local _, h = P:text(22, y, width - 28, text, "ui", 11, "inkDim")
      y = y + h + 6
    end
    P:fill(0, top, width, y - top, 1, 0.92, 0.75, 0.035)
    y = y + 10
  end
  return y
end
