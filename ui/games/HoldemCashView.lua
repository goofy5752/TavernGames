local _, ns = ...

-- The account of a staked Холдем (ns.HoldemCashView, not ns.HoldemCash: that is the engine's module, H7), drawn
-- over the felt of ns.HoldemView from the model's `cash` (ns.HoldemModel):
--   „Сметка“ at the felt's top right opens a panel of three tabs: „Ти срещу всеки“ (per opponent what it took
--   from me, what I took, the net), „Всички“ (every seat's buy-in, chips and net) and „Ръце“ (the newest
--   30 hands of this table heard in this run, `lines`). A chip is one silver (HoldemCash.CHIP); `coins(chips)`: in coins.
--   „Вход“ (my seat has bought nothing) or „Докупи“ (it has), while the model has a range (`cash.lo`: never
--   inside my hand, after the close, while my stake is still asked): a stepper of 10 big blinds between
--   the range's ends (both always reachable) and „Потвърди“, which is client:buy(n).
-- `line(client, ev)` is the words of one finished hand (the client event "hand"), one row per winner.
local W, L, Theme = ns.W, ns.L, ns.Theme
local money = ns.W.money -- names: W.short among the hand's or the table's (ui/NameTag.lua)

local V = {}
ns.HoldemCashView = V

local PANEL_W, PANEL_H, TAB_Y, TOP = 268, 300, -30, -56
local ROW_H, NAME_W, COL_W, KEEP = 18, 66, 60, 30
local TABS = { { "cash.tab.mine", 96 }, { "cash.tab.all", 70 }, { "cash.tab.hands", 62 } }
local HEAD = { { "cash.col.gave", "cash.col.took", "cash.col.net" }, { "cash.col.bought", "cash.col.chips", "cash.col.net" } }
local STEP_BB = 10 -- the stepper moves 10 big blinds

local kept = {} -- tid -> {line, ...}, the newest first, for this run

---------------------------------------------------------------------------
-- The words of a hand
---------------------------------------------------------------------------

function V.coins(chips) return money(chips * ns.HoldemCash.CHIP) end
local cash = V.coins

-- The signed amount of a net (the sign of a loss only).
local function signed(chips) return chips < 0 and "-" .. cash(-chips) or cash(chips) end

-- One row per winner of the finished hand `ev.last` (ascending seat), as the client event "hand" carries it.
local function words(client, ev)
  local last, names = ev.last, type(ev.names) == "table" and ev.names or {}
  local n = ev.n or last.hand
  if last.void then return { L("cash.hand.void", n) } end
  local function who(seat)
    local name = names[seat]
    if type(name) ~= "string" then return "?" end
    return name == client.env.me and L("cash.hand.you") or W.short(name, names)
  end
  local winners, out = {}, {}
  for w, row in pairs(type(last.took) == "table" and last.took or {}) do
    if type(row) == "table" and next(row) then winners[#winners + 1] = w end
  end
  table.sort(winners)
  for _, w in ipairs(winners) do
    local from, sum, froms = {}, 0, {}
    for j in pairs(last.took[w]) do from[#from + 1] = j end
    table.sort(from)
    for _, j in ipairs(from) do
      sum = sum + last.took[w][j]
      froms[#froms + 1] = L("cash.hand.from", cash(last.took[w][j]), who(j))
    end
    local name = W.short(names[w], names)
    local cat = type(last.cat) == "table" and last.cat[w]
    local shown = type(last.shown) == "table" and #last.shown > 0 and cat
    local parts = table.concat(froms, ", ")
    out[#out + 1] = shown and L("cash.hand", n, name, cash(sum), L("holdem.cat." .. tostring(cat)), parts)
      or L("cash.hand.fold", n, name, cash(sum), parts)
  end
  return out
end

-- The line of a hand: one row per winner, joined by a newline ("" for a hand that moved nothing).
function V.line(client, ev) return table.concat(words(client, ev), "\n") end

-- The newest KEEP lines of table tid heard in this run, the newest first.
function V.lines(tid)
  local out = {}
  for i, line in ipairs(kept[tid] or {}) do out[i] = line end
  return out
end

local function hear(client, ev)
  local last = type(ev) == "table" and ev.last
  if type(last) ~= "table" or type(ev.tid) ~= "string" then return end
  local staked = type(last.took) == "table" or (last.void and type(ev.opt) == "table" and ev.opt.rebuy ~= nil)
  if not staked then return end
  local list = kept[ev.tid] or {}
  kept[ev.tid] = list
  local rows = words(client, ev)
  for i = #rows, 1, -1 do table.insert(list, 1, rows[i]) end
  for i = #list, KEEP + 1, -1 do list[i] = nil end
  ns.TableFrame.refresh()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function rowOf(c, i)
  local r = c.rows[i]
  if r then return r end
  local f = CreateFrame("Frame", nil, c.scroll.content)
  f:SetSize(PANEL_W - 22, ROW_H)
  r = { frame = f, cells = {} }
  W.nameTip(f, function() return r.name end) -- a row's whole name
  for j = 1, 4 do
    local cell = W.Label(f, j == 1 and "ui" or "dim", "", 12)
    cell:SetWordWrap(false)
    cell:SetJustifyH(j == 1 and "LEFT" or "RIGHT")
    r.cells[j] = cell
  end
  c.rows[i] = r
  return r
end

-- Row i of the list at height y: `cells` (up to 4 texts; one: the whole width, wrapped) -> its height.
local function setRow(c, i, y, cells, head)
  local r = rowOf(c, i)
  r.frame:ClearAllPoints()
  r.frame:SetPoint("TOPLEFT", c.scroll.content, "TOPLEFT", 0, -y)
  local one, h = #cells == 1, ROW_H
  r.name = cells.name
  for j = 1, 4 do
    local cell = r.cells[j]
    cell:ClearAllPoints()
    if one then
      cell:SetPoint("TOPLEFT", r.frame, "TOPLEFT", 0, 0)
      cell:SetWidth(PANEL_W - 22)
      cell:SetWordWrap(true)
    else
      cell:SetPoint("TOPLEFT", r.frame, "TOPLEFT", j == 1 and 0 or NAME_W + COL_W * (j - 2), 0)
      cell:SetWidth(j == 1 and NAME_W or COL_W)
      cell:SetWordWrap(false)
    end
    if one then W.fit(cell, cells[j] or "", math.huge) else W.fitWrap(cell, cells[j] or "", cell:GetWidth()) end -- shrinks, then wraps
    cell:SetTextColor(Theme.rgb(head and "inkDim" or (j == 1 or one) and "ink" or "inkDim"))
    cell:SetShown(cells[j] ~= nil)
    if cells[j] then h = math.max(h, cell:GetStringHeight() + 4) end
  end
  r.frame:SetHeight(h)
  r.frame:Show()
  return h
end

local function fillPanel(f, s, m)
  local c, cash_ = f.cash, m.cash
  for j, t in ipairs(c.tabs) do t:SetAlpha(c.tab == j and 1 or 0.6) end
  local rows, y, i = {}, 0, 0
  if c.tab == 3 then
    for _, line in ipairs(V.lines(s.tid)) do rows[#rows + 1] = { line } end
    if #rows == 0 then rows[1] = { "" } end
  else
    local mine = c.tab == 1
    local head = HEAD[c.tab]
    rows[1] = { "", L(head[1]), L(head[2]), L(head[3]), head = true }
    for _, e in ipairs(mine and cash_.mine or cash_.all) do
      rows[#rows + 1] = mine and { W.short(e.name, s.seats), cash(e.gave), cash(e.took), signed(e.net), name = e.name }
        or { W.short(e.name, s.seats), cash(e.bought), cash(e.chips), signed(e.net), name = e.name }
    end
  end
  for _, cells in ipairs(rows) do
    i = i + 1
    y = y + setRow(c, i, y, cells, cells.head)
  end
  for k = i + 1, #c.rows do c.rows[k].frame:Hide() end
  c.scroll:setContentHeight(y)
end

-- The panel and the stepper share the place: opening one closes the other, the same button closes its own.
local function show(c, what)
  local panel, buy = what == "panel" and not c.panel:IsShown(), what == "buy" and not c.buyBox:IsShown()
  c.panel:SetShown(panel)
  c.buyBox:SetShown(buy)
end

-- Draws again what the view last drew (a tab, the panel opening).
local function again(f)
  if f.session and f.model then V.update(f, f.session, f.model) end
end

local function stepBuy(f, d)
  local c = f.cash
  local r = c.range
  if not (r and c.n) then return end
  c.n = math.max(r.lo, math.min(r.hi, c.n + d * r.step))
  W.fit(c.amount, cash(c.n), c.amount:GetWidth())
end

-- The words of a refusal code of client:buy (a short line per code; any other code is named).
local function refusal(code)
  local key = "cash.buy.no." .. tostring(code)
  local text = L(key)
  return text ~= key and text or L("cash.buy.no", tostring(code))
end

function V.build(f)
  local c = { tab = 1, rows = {} }
  f.cash = c
  V.board = f
  c.button = W.GhostButton(f, L("cash.button"), "brassLight", function() show(c, "panel"); again(f) end)
  c.button:SetSize(84, 22)
  c.button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
  c.buy = W.GhostButton(f, L("cash.buy"), "brassLight", function()
    local r = c.range
    c.n = r and r.hi
    show(c, "buy")
    if r then stepBuy(f, 0) end
  end)
  c.buy:SetSize(84, 22)
  c.buy:SetPoint("TOPRIGHT", f, "TOPRIGHT", -98, -8)
  for _, b in ipairs({ c.button, c.buy }) do b:Hide() end

  local panel = W.Panel(f, W.SOLID) -- solid: the plates under it do not show through
  c.panel = panel
  panel:SetSize(PANEL_W, PANEL_H)
  panel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -34)
  panel:SetFrameLevel(f:GetFrameLevel() + ns.Cards.TOP + 20) -- above the bill, as before it rose over the cards
  panel:EnableMouse(true)
  c.title = W.Label(panel, "heading", L("cash.panel"), 14)
  c.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
  c.tabs = {}
  local x = 8
  for j, t in ipairs(TABS) do
    local b = W.Button(panel, L(t[1]), function() c.tab = j; again(f) end, true)
    b:SetSize(t[2], 20)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, TAB_Y)
    x = x + t[2] + 2
    c.tabs[j] = b
  end
  c.scroll = W.Scroll(panel)
  c.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, TOP)
  c.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
  c.scroll.content:SetWidth(PANEL_W - 22)
  panel:Hide()

  local box = W.Panel(f, W.SOLID) -- the stepper of a buy-in
  c.buyBox = box
  box:SetSize(PANEL_W, 34)
  box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -34)
  box:SetFrameLevel(f:GetFrameLevel() + ns.Cards.TOP + 20)
  box:EnableMouse(true)
  c.minus = W.Button(box, L("holdem.minus"), function() stepBuy(f, -1) end, true)
  c.minus:SetSize(26, 22)
  c.minus:SetPoint("LEFT", box, "LEFT", 6, 0)
  c.amount = W.Label(box, "ui", "", 13)
  c.amount:SetJustifyH("CENTER")
  c.amount:SetPoint("LEFT", c.minus, "RIGHT", 4, 0)
  c.amount:SetWidth(70)
  c.plus = W.Button(box, L("holdem.plus"), function() stepBuy(f, 1) end, true)
  c.plus:SetSize(26, 22)
  c.plus:SetPoint("LEFT", c.amount, "RIGHT", 4, 0)
  c.confirm = W.Button(box, L("cash.buy.ok"), function()
    local client = ns.client
    local done, code
    if client and c.n then done, code = client:buy(c.n) end
    if client and c.n and not done then ns.TableFrame.say(refusal(code)) end
    box:Hide()
  end, true)
  c.confirm:SetSize(84, 22)
  c.confirm:SetPoint("RIGHT", box, "RIGHT", -6, 0)
  box:Hide()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- Called from the Холдем view's update: `m` the model with `cash` (a fun table: nothing shown).
function V.update(f, s, m)
  local c, cash_ = f.cash, m.cash
  if not c then return end
  c.button:SetShown(cash_ ~= nil)
  local lo = cash_ and cash_.lo
  c.range = lo and { lo = lo, hi = cash_.hi, step = STEP_BB * s.state.bb } or nil
  c.buy:SetShown(lo ~= nil)
  if lo then
    local bought = s.state.seats[m.me].bought
    c.buy.text:SetText(L(bought == 0 and "cash.buy" or "cash.rebuy"))
    if c.buyBox:IsShown() then
      c.n = math.max(lo, math.min(cash_.hi, c.n or cash_.hi))
      W.fit(c.amount, cash(c.n), c.amount:GetWidth())
    end
  else
    c.buyBox:Hide()
  end
  if not cash_ then c.panel:Hide() elseif not m.seated and c.tab == 1 then c.tab = 2 end -- a watcher has no „Ти срещу всеки“
  if c.panel:IsShown() then fillPanel(f, s, m) end
end

ns.ready(function(client)
  client:on("hand", function(ev) hear(client, ev) end)
  client:on("buyLow", function(lo) -- a floor above my pick: the stepper opens at the floor
    local f = V.board
    local c = f and f.cash
    if not (c and c.range and lo) then return end
    c.panel:Hide(); c.buyBox:Show(); c.n = lo; stepBuy(f, 0)
    ns.TableFrame.say(L("cash.buy.low", cash(c.n)))
  end)
  client:on("session", function(s) -- a table that ended frees its hands
    for tid in pairs(kept) do if not (s and s.tid == tid) then kept[tid] = nil end end
  end)
end)
