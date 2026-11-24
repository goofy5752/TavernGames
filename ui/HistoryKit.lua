local _, ns = ...

-- What the move histories are drawn with (mockup 10, „Ново“): the „История“ side window
-- (ui/HandHistoryPanel.lua) and the chess table's move list on parchment (ui/games/ChessPanels.lua).
--   Kit.pool(content, paper) — the widgets of one scroll content, reused on every redraw:
--     pool:begin(), then pool:label / tex / card / button, each placed with pool:put; pool:finish()
--     hides what this draw did not use. pool.placed lists every placed widget's rect
--     { r, x, y, w, h } in the content (x right, y down from its top left), for the fit tests.
--   A mini card: the addon's card face, the rank, the suit cell of `suits`, tinted red or ink;
--     normal 34 x 47 (a trick), small 26 x 36 (the board, a showdown, an event, the trump).
--     Its states: "won" (a gold ring and glow), "dim" (an earlier street's card), "mine" (the
--     accent ring), and no face: the outline of a slot still empty.
--   Kit.move(pool, x, y, width, d, opts): one chess move (ns.ChessModel.describe's d) in a cell
--     `width` wide: the piece's icon, „e2 → e4“, a capture's „×“ and the taken piece's small icon,
--     „=“ and the new piece, the tags „рокада“, „шах“, „мат“. Never wider than its cell: the
--     squares shrink (to W.WRAP_MIN), then what still does not fit goes on a second line of the cell
--     (the tags first, as they come last). Nothing is dropped. -> the cell's height.
local Theme, W, L, Cards = ns.Theme, ns.W, ns.L, ns.Cards

local Kit = {}
ns.HistoryKit = Kit

local function hex(h) return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 end
Kit.hex = hex

Kit.CARD = { normal = { 34, 47, 13, 18 }, small = { 26, 36, 11, 14 } } -- w, h, rank size, suit size

---------------------------------------------------------------------------
-- The mini card
---------------------------------------------------------------------------

local CARD = {}
CARD.__index = CARD

local function miniCard(parent, size)
  local w, h, rs, ss = unpack(Kit.CARD[size])
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local c = setmetatable({ frame = f, w = w, h = h, size = size }, CARD)
  c.glow = f:CreateTexture(nil, "BACKGROUND")
  c.glow:SetTexture(Theme.tex.glow)
  c.glow:SetBlendMode("ADD")
  c.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -7, 7)
  c.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 7, -7)
  c.glow:SetVertexColor(Theme.rgb("goldHi"))
  c.body = f:CreateTexture(nil, "ARTWORK")
  c.body:SetAllPoints(f)
  c.body:SetTexture(Theme.tex.card)
  c.suit = f:CreateTexture(nil, "ARTWORK", nil, 1)
  c.suit:SetTexture(Theme.tex.suits)
  c.suit:SetSize(ss, ss)
  c.suit:SetPoint("CENTER", f, "TOP", 0, -0.6 * h)
  c.rank = W.Label(f, "paper", nil, rs)
  Theme.setFont(c.rank, "uiBold", rs)
  c.rank:SetPoint("TOPLEFT", f, "TOPLEFT", size == "small" and 3 or 4, -2)
  c.shade = f:CreateTexture(nil, "OVERLAY", nil, 2)
  c.shade:SetAllPoints(f)
  c.shade:SetTexture(Theme.tex.card)
  c.shade:SetVertexColor(0, 0, 0, 0.45)
  c.ring = W.edges(f, 2, "OVERLAY")
  c.outline = W.edges(f, 1, "BORDER")
  c.outline.setColor(Theme.color.brassLight[1], Theme.color.brassLight[2], Theme.color.brassLight[3], 0.35)
  return c
end

-- `face` ("KH"; nil: an empty slot) in `mode` (nil | "won" | "dim" | "mine").
function CARD:set(face, mode)
  self.face, self.mode = face, mode
  local up = type(face) == "string" and Cards.COORD[face:sub(2, 2)] ~= nil
  self.body:SetShown(up); self.suit:SetShown(up); self.rank:SetShown(up)
  for i = 1, 4 do self.outline[i]:SetShown(not up) end
  self.glow:SetShown(up and mode == "won")
  self.shade:SetShown(up and mode == "dim")
  local ring = up and (mode == "won" and "gold" or mode == "mine" and "accent")
  for i = 1, 4 do self.ring[i]:SetShown(ring and true or false) end
  if ring then self.ring.setColor(Theme.rgb(ring)) end
  if not up then return end
  local r, g, b = Theme.rgb(Cards.red(face) and "red" or "cardInk")
  local coord = Cards.COORD[face:sub(2, 2)]
  self.suit:SetTexCoord(coord[1], coord[2], 0, 1)
  self.suit:SetVertexColor(r, g, b)
  self.rank:SetText(Cards.rank(face))
  self.rank:SetTextColor(r, g, b)
end

-- The inline suit icon of a text (its cell of `suits`, red or ink), as H.card draws it.
local SUIT_CELL = { C = "0:32", D = "32:64", H = "64:96", S = "96:128" }
local function byte(x) return math.floor(x * 255 + 0.5) end
function Kit.suitTag(suit, token)
  if not SUIT_CELL[suit] then return "" end
  local r, g, b = Theme.rgb(token or ((suit == "D" or suit == "H") and "oMark" or "ink"))
  return "|T" .. Theme.tex.suits .. ":0:0:0:0:128:32:" .. SUIT_CELL[suit] .. ":0:32:" .. byte(r) .. ":" .. byte(g) .. ":" .. byte(b) .. "|t"
end

---------------------------------------------------------------------------
-- The pool
---------------------------------------------------------------------------

local POOL = {}
POOL.__index = POOL

-- The pool of scroll content `content`; `paper`: its text sits on parchment (no shadow).
function Kit.pool(content, paper)
  return setmetatable({ content = content, paper = paper, kinds = {}, used = {}, placed = {} }, POOL)
end

function POOL:begin()
  for kind in pairs(self.kinds) do self.used[kind] = 0 end
  self.placed = {}
end

-- The next free widget of `kind`, made by make() when the pool has none.
function POOL:take(kind, make)
  local list = self.kinds[kind]
  if not list then list = {}; self.kinds[kind] = list end
  local n = (self.used[kind] or 0) + 1
  self.used[kind] = n
  local x = list[n]
  if not x then x = make(); list[n] = x end
  return x
end

function POOL:finish()
  for kind, list in pairs(self.kinds) do
    for n = (self.used[kind] or 0) + 1, #list do
      local x = list[n]
      local r = x.frame or x
      r:Hide()
    end
  end
end

-- Places region r at x, y of the content, w x h (a size only when w is given), and notes its rect.
function POOL:put(r, x, y, w, h)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
  if w then r:SetSize(w, h) end
  r:Show()
  self.placed[#self.placed + 1] = { r = r, x = x, y = y, w = w or 0, h = h or 0 }
  return r
end

-- A font string: font token, size, colour token or {r, g, b}; one line, as wide as its text.
function POOL:label(font, size, color)
  local fs = self:take("label", function() return W.Label(self.content, self.paper and "paper" or "ui", nil, 11) end)
  fs.fitFont = nil
  Theme.setFont(fs, font, size)
  if type(color) == "table" then fs:SetTextColor(color[1], color[2], color[3]) else fs:SetTextColor(Theme.rgb(color)) end
  fs:SetWidth(0)
  fs:SetWordWrap(false)
  fs:SetJustifyH("LEFT")
  fs:SetText("")
  return fs
end

-- A label placed at x, y: `text` in `width` (shrunk, then wrapped: W.fitWrap) -> fs, its height.
function POOL:text(x, y, width, text, font, size, color, justify)
  local fs = self:label(font, size, color)
  local h = W.fitWrap(fs, text, width)
  if justify then fs:SetJustifyH(justify) end
  self:put(fs, x, y)
  local placed = self.placed[#self.placed]
  placed.w, placed.h, placed.box = math.min(width, W.textWidth(fs)), h, width
  if justify == "RIGHT" or justify == "CENTER" then placed.w = width end
  return fs, h
end

-- A texture: its file (nil: a colour), cleared of the last use's tint, coords and blend.
function POOL:tex(layer, sub)
  local t = self:take("tex:" .. (layer or "ARTWORK") .. (sub or 0), function() return self.content:CreateTexture(nil, layer or "ARTWORK", nil, sub) end)
  t:SetTexCoord(0, 1, 0, 1)
  t:SetVertexColor(1, 1, 1, 1)
  t:SetBlendMode("BLEND")
  t:SetAlpha(1)
  return t
end

-- A flat colour block (r, g, b, a) at x, y, w x h.
function POOL:fill(x, y, w, h, r, g, b, a, layer)
  local t = self:tex(layer or "BACKGROUND")
  t:SetColorTexture(r, g, b, a)
  return self:put(t, x, y, w, h)
end

-- A mini card ("normal" | "small") at x, y.
function POOL:card(x, y, size, face, mode)
  local c = self:take("card:" .. size, function() return miniCard(self.content, size) end)
  c:set(face, mode)
  self:put(c.frame, x, y, c.w, c.h)
  self.placed[#self.placed].card = c
  return c
end

-- An invisible click area at x, y, w x h calling onClick.
function POOL:button(x, y, w, h, onClick)
  local b = self:take("button", function()
    local f = CreateFrame("Button", nil, self.content)
    f:RegisterForClicks("LeftButtonUp")
    f.hi = f:CreateTexture(nil, "BACKGROUND")
    f.hi:SetAllPoints(f)
    f.hi:SetColorTexture(1, 0.92, 0.75, 0.06)
    f.hi:Hide()
    f:SetScript("OnEnter", function() f.hi:Show() end)
    f:SetScript("OnLeave", function() f.hi:Hide() end)
    return f
  end)
  b:SetScript("OnClick", onClick)
  return self:put(b, x, y, w, h)
end

-- A chess piece's icon (signed piece) `size` px at x, y; `disc`: on a small light disc, so a dark
-- piece reads on the dark window.
function POOL:piece(x, y, size, piece, disc)
  if disc then
    local d = self:tex("ARTWORK", 0)
    d:SetTexture(Theme.tex.chair)
    d:SetVertexColor(hex("d9c497"))
    self:put(d, x, y, size, size)
  end
  local t = self:tex("ARTWORK", 1)
  t:SetTexture(ns.ChessPanels.pieceTex(piece))
  return self:put(t, x, y, size, size)
end

---------------------------------------------------------------------------
-- A chess move in its cell
---------------------------------------------------------------------------

local ICON, TAKEN, GAP, PAD, ROW = 18, 14, 2, 3, 20
local TAG = { chk = { "8a1d12", "ffd9c8" }, mate = { "e0b24e", "2b1d12" }, cs = { "goldHi", "goldHi" } }

-- The parts of move d: { kind = "icon" | "text" | "tag", w, … }, the text ones measured at `size`.
local function parts(d, size)
  local out = {}
  local function text(s, font, color, sz) out[#out + 1] = { kind = "text", s = s, font = font, color = color, size = sz or size } end
  out[#out + 1] = { kind = "icon", piece = d.piece, w = ICON }
  text(d.from, "uiBold", "sq")
  if d.capture then text("×", "uiBold", "x") else text("→", "heading", "arrow", math.max(W.WRAP_MIN, size - 2)) end
  text(d.to, "uiBold", "sq")
  if d.take then out[#out + 1] = { kind = "icon", piece = d.take, w = TAKEN } end
  if d.promo then
    text("=", "uiBold", "arrow")
    out[#out + 1] = { kind = "icon", piece = d.promo, w = ICON }
  end
  if d.castle then out[#out + 1] = { kind = "tag", s = L("chess.history.castle"), tag = "cs" } end
  if d.mate then out[#out + 1] = { kind = "tag", s = L("chess.history.mate"), tag = "mate" }
  elseif d.check then out[#out + 1] = { kind = "tag", s = L("chess.history.check"), tag = "chk" } end
  return out
end

-- Measures the text parts with a scratch font string of the pool.
local function measure(pool, list)
  local fs = pool.scratch
  if not fs then
    fs = W.Label(pool.content, "ui", "", 12)
    fs:Hide()
    pool.scratch = fs
  end
  local total = 0
  for k, p in ipairs(list) do
    if p.kind == "text" then
      Theme.setFont(fs, p.font, p.size); fs:SetText(p.s); p.w = W.textWidth(fs)
    elseif p.kind == "tag" then
      Theme.setFont(fs, "uiBold", 9); fs:SetText(p.s); p.w = W.textWidth(fs) + 6
    end
    total = total + p.w + (k > 1 and GAP or 0)
  end
  return total
end

-- The colours of the move's texts on the dark window or on parchment.
local INK = {
  dark = { sq = { Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3] }, arrow = { Theme.color.inkDim[1], Theme.color.inkDim[2], Theme.color.inkDim[3] }, x = { hex("e2735a") } },
  paper = { sq = { hex("2b1d12") }, arrow = { hex("7a6242") }, x = { hex("b3261e") } },
}

-- opts: { paper = true (the parchment list), last = true (the last move, marked) }.
function Kit.move(pool, x, y, width, d, opts)
  opts = opts or {}
  local avail = width - 2 * PAD
  local size, list = 12, nil
  repeat
    list = parts(d, size)
    local total = measure(pool, list)
    if total <= avail or size <= W.WRAP_MIN then break end
    size = size - 1
  until false
  -- the parts in lines: a part that would pass the cell's edge starts the next line
  local lines, cur, cx = {}, {}, 0
  for _, p in ipairs(list) do
    local need = (#cur > 0 and GAP or 0) + p.w
    if #cur > 0 and cx + need > avail then lines[#lines + 1] = cur; cur, cx = {}, 0; need = p.w end
    p.at = cx + (#cur > 0 and GAP or 0)
    cur[#cur + 1] = p
    cx = cx + need
  end
  lines[#lines + 1] = cur
  local widest = 0
  for _, line in ipairs(lines) do
    local last = line[#line]
    widest = math.max(widest, last.at + last.w)
  end
  local h = #lines * ROW
  if opts.last then
    local mw = math.min(width, widest + 2 * PAD)
    if opts.paper then
      pool:fill(x, y, mw, h, 180 / 255, 130 / 255, 40 / 255, 0.3)
    else
      pool:fill(x, y, mw, h, Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.28)
    end
    local er, eg, eb = Theme.rgb("gold")
    if opts.paper then er, eg, eb = hex("9c6a1a") end
    pool:fill(x, y, mw, 1, er, eg, eb, 1, "BORDER"); pool:fill(x, y + h - 1, mw, 1, er, eg, eb, 1, "BORDER")
    pool:fill(x, y, 1, h, er, eg, eb, 1, "BORDER"); pool:fill(x + mw - 1, y, 1, h, er, eg, eb, 1, "BORDER")
  end
  local ink = INK[opts.paper and "paper" or "dark"]
  for n, line in ipairs(lines) do
    local ly = y + (n - 1) * ROW
    for _, p in ipairs(line) do
      local px = x + PAD + p.at
      if p.kind == "icon" then
        pool:piece(px, ly + (ROW - p.w) / 2, p.w, p.piece, not opts.paper)
      elseif p.kind == "text" then
        local fs = pool:label(p.font, p.size, ink[p.color])
        fs:SetText(p.s)
        pool:put(fs, px, ly + (ROW - p.size * 1.2) / 2)
        local placed = pool.placed[#pool.placed]
        placed.w, placed.h = W.textWidth(fs), p.size
      else
        local tc = TAG[p.tag]
        local br, bg, bb = hex(tc[1] == "goldHi" and "f2c94c" or tc[1])
        local alpha = p.tag == "cs" and (opts.paper and 0.15 or 0.18) or 1
        if p.tag == "cs" and opts.paper then br, bg, bb = hex("785014") end
        pool:fill(px, ly + 4, p.w, ROW - 8, br, bg, bb, alpha, "BORDER")
        local color = p.tag == "cs" and (opts.paper and { hex("6a420a") } or "goldHi") or { hex(tc[2]) }
        local fs = pool:label("uiBold", 9, color)
        fs:SetText(p.s)
        pool:put(fs, px + 3, ly + 5)
        local placed = pool.placed[#pool.placed]
        placed.w, placed.h = W.textWidth(fs), 9
      end
    end
  end
  return h
end

-- The move list rows { no, white, black, lastWhite, lastBlack } at x, y, `width` wide: the number in
-- a column NO_W wide, white's move, black's move in two equal cells; a row as tall as its taller
-- cell -> the height of them all.
Kit.NO_W = 22
function Kit.moveRows(pool, x, y, width, rows, opts)
  opts = opts or {}
  local cell = math.floor((width - Kit.NO_W - 2 * GAP) / 2)
  local top = y
  for _, r in ipairs(rows) do
    local no = opts.paper and { hex("6b5232") } or "inkDim"
    local fs = pool:label("ui", 11, no)
    fs:SetText(r.no .. ".")
    fs:SetWidth(Kit.NO_W - 3)
    fs:SetJustifyH("RIGHT")
    pool:put(fs, x, y + 4)
    local placed = pool.placed[#pool.placed]
    placed.w, placed.h = Kit.NO_W - 3, 11
    local h = Kit.move(pool, x + Kit.NO_W + GAP, y, cell, r.white, { paper = opts.paper, last = r.lastWhite })
    if r.black then
      h = math.max(h, Kit.move(pool, x + Kit.NO_W + 2 * GAP + cell, y, cell, r.black, { paper = opts.paper, last = r.lastBlack }))
    end
    y = y + h + 1
  end
  return y - top
end
