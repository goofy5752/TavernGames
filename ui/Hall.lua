local _, ns = ...

-- The hall tab (mockup 02 option A). Left: „Отвори маса“ with the games of the
-- registry (ns.Games.list: a game with an engine opens the new-table dialog,
-- the others are dimmed with „Скоро“). Centre: the floor plan of the guild's
-- tables (HallLayout), a scroll list above 8 tables, or a message (no guild,
-- name lookup, empty hall). Right: „Сметки“ (ui/Accounts.lua), ACCOUNTS_H high,
-- over „В кръчмата сега“ (ui/HallPeers.lua), where a click on a name offers
-- „Покани“ while I host a table with a free seat.
-- Footer: a refusal for 5 s; the "newer version" note once it is known.
-- A staked table shows its stake in its tooltips and its list row (a fun
-- row says „За удоволствие“), and a click that would sit there asks first
-- (ns.StakePanels.ask).
--
-- Client events only schedule a redraw for the next frame (Hall.refresh), so a
-- burst of events draws once and a drawing error never breaks the protocol code
-- that emitted the event.
local Theme, W, L, HallLayout = ns.Theme, ns.W, ns.L, ns.HallLayout

local Hall = {
  view = nil,              -- widgets, once the tab is built
  mode = nil,              -- "floor" | "list" | "empty" | "noguild" | "wait"
  selected = nil,          -- the name whose „Покани“ is offered
  updateAvailable = false, -- a newer protocol version was seen
}
ns.Hall = Hall

local FOOTER_SECONDS = 5
local LEFT_W, GAP = 190, 10
Hall.RIGHT_W = 250 -- the right column: „Сметки“ (ui/Accounts.lua) over the peers (ui/HallPeers.lua)
Hall.ACCOUNTS_H = 190
local FOOTER_H, HEADER_H = 22, 28
local TABLE_SIZE, TOP_SIZE, CHAIR_R, LABEL_R = 150, 94, 60, 80
local GAME_H, ROW_H = 40, 40
-- Chair name labels fit around a table of at most this many seats; at a larger
-- one only the tooltips name the players.
local LABELLED_SEATS = 4

local MESSAGES = { noguild = "hall.noguild", wait = "hall.wait", empty = "hall.empty" }

local firstWord = W.firstWord

-- The first UTF-8 character of `text`.
local function initial(text) return text:match("^[%z\1-\127\194-\244][\128-\191]*") or "" end

local gameName = W.gameName

local function firstFree(seats)
  for i = 1, #seats do
    if seats[i] == false then return i end
  end
  return nil
end

local function seatedCount(seats)
  local n = 0
  for i = 1, #seats do
    if seats[i] then n = n + 1 end
  end
  return n
end

local nameColor, colored = W.nameColor, W.colored

-- Am I at this table (host, player or watcher)?
local function here(client, rec)
  local s = client.session
  return s ~= nil and s.tid == rec.tid
end

-- My session as host with a free seat, or nil.
function Hall.hostingWithFreeSeat(client)
  local s = client and client.session
  if s and s.role == "host" and firstFree(s.seats) then return s end
  return nil
end

local function color(fs, token) fs:SetTextColor(Theme.rgb(token)) end

-- „Залог: 5g“ of a staked table, the blinds („5s/10s“) of a cash table, nil for fun.
local function stakeText(rec)
  if rec.stake == nil then return nil end
  local engine = ns.Games.engine(rec.game)
  if engine and engine.stakeOf then return L("hall.blinds", ns.Util.money(rec.stake / 2), ns.Util.money(rec.stake)) end
  return L("table.stake", ns.Util.money(rec.stake))
end

-- Sits in `seat` of table rec; a staked table asks first.
local function sit(client, rec, seat)
  if rec.stake ~= nil then return ns.StakePanels.ask(rec, seat) end
  client:sit(rec.tid, seat)
end

---------------------------------------------------------------------------
-- Footer
---------------------------------------------------------------------------

-- One line in the hall footer for FOOTER_SECONDS; a newer line replaces it.
function Hall.say(text)
  local v = Hall.view
  if not v then return end
  v.footer:SetText(text)
  v.footer:Show()
  if Hall.footerTimer then Hall.footerTimer:Cancel() end
  Hall.footerTimer = C_Timer.NewTimer(FOOTER_SECONDS, function()
    Hall.footerTimer = nil
    v.footer:Hide()
  end)
end

---------------------------------------------------------------------------
-- Clicks and tooltips
---------------------------------------------------------------------------

function Hall.clickChair(t, seat)
  local client = ns.client
  if client and t.rec then sit(client, t.rec, seat) end
end

function Hall.clickTable(t)
  local client, rec = ns.client, t.rec
  if not client or not rec or here(client, rec) then return end
  if rec.state == "live" then client:watch(rec.tid) end
end

function Hall.clickRow(r)
  local client, rec = ns.client, r.rec
  if not client or not rec then return end
  if r.act == "sit" then
    sit(client, rec, firstFree(rec.seats))
  elseif r.act == "watch" then
    client:watch(rec.tid)
  end
end

function Hall.clickPeer(r)
  local client = ns.client
  if client and r.peerName and ns.HallPeers.canInviteName(client, r.peerName) and Hall.selected ~= r.peerName then
    Hall.selected = r.peerName
  else
    Hall.selected = nil
  end
  Hall.render()
end

function Hall.invite(name)
  local client = ns.client
  Hall.selected = nil
  if client and client:invite(name) then
    Hall.say(L("invite.sent", name))
  else
    Hall.say(L("invite.fail", name))
  end
  Hall.render()
end

function Hall.tableTooltip(tip, rec)
  local client = ns.client
  if not rec or not client then return end
  tip:SetText(L("hall.host", gameName(rec.game), colored(client, rec.host)), Theme.rgb("gold"))
  for i = 1, #rec.seats do
    local name = rec.seats[i]
    if name then tip:AddLine(name, nameColor(client, name)) end
  end
  tip:AddLine(L("access." .. tostring(rec.access)) .. " · " .. L("hall.turn", rec.turn), Theme.rgb("inkDim"))
  if stakeText(rec) then tip:AddLine(stakeText(rec), Theme.rgb("gold")) end
  if here(client, rec) then return end
  if firstFree(rec.seats) then
    tip:AddLine(L("hall.tip.sit"), Theme.rgb("good"))
  elseif rec.state == "live" then
    tip:AddLine(L("hall.tip.watch"), Theme.rgb("good"))
  end
end

function Hall.chairTooltip(tip, rec, seat)
  local client = ns.client
  if not rec or not client then return end
  local name = rec.seats[seat]
  if name then
    tip:SetText(name, nameColor(client, name))
  else
    tip:SetText(L("hall.tip.sit"), Theme.rgb("good"))
    if stakeText(rec) then tip:AddLine(stakeText(rec), Theme.rgb("gold")) end
  end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function pulse(frame, elapsed)
  frame.pulseTime = (frame.pulseTime or 0) + elapsed
  frame.glowTexture:SetAlpha(0.55 + 0.35 * math.sin(frame.pulseTime * math.pi))
end

local function tableWidget(v, i)
  local t = v.tables[i]
  if t then return t end
  local f = CreateFrame("Frame", nil, v.floor)
  f:SetSize(TABLE_SIZE, TABLE_SIZE)
  local glow = f:CreateTexture(nil, "BACKGROUND")
  glow:SetSize(TABLE_SIZE + 20, TABLE_SIZE + 20)
  glow:SetPoint("CENTER", f, "CENTER")
  glow:SetTexture(Theme.tex.glow)
  glow:SetBlendMode("ADD")
  f.glowTexture = glow

  local top = CreateFrame("Button", nil, f)
  top:SetSize(TOP_SIZE, TOP_SIZE)
  top:SetPoint("CENTER", f, "CENTER")
  top:RegisterForClicks("LeftButtonUp")
  local wood = top:CreateTexture(nil, "BACKGROUND")
  wood:SetAllPoints(top)
  wood:SetTexture(Theme.tex.tabletop)
  local felt = top:CreateTexture(nil, "BORDER")
  felt:SetSize(TOP_SIZE - 18, TOP_SIZE - 18)
  felt:SetPoint("CENTER", top, "CENTER")
  felt:SetTexture(Theme.tex.chair)
  felt:SetVertexColor(Theme.rgb("felt"))

  local game = W.Label(top, "heading", "", 14)
  game:SetJustifyH("CENTER")
  game:SetPoint("CENTER", top, "CENTER", 0, 11)
  local host = W.Label(top, "ui", "", 11)
  host:SetJustifyH("CENTER")
  host:SetPoint("CENTER", top, "CENTER", 0, -4)
  local state = W.Label(top, "ui", "", 11)
  state:SetJustifyH("CENTER")
  color(state, "gold")
  state:SetPoint("CENTER", top, "CENTER", 0, -18)

  t = { frame = f, glow = glow, top = top, game = game, host = host, state = state, chairs = {} }
  top:SetScript("OnClick", function() Hall.clickTable(t) end)
  W.tooltip(top, function(tip) Hall.tableTooltip(tip, t.rec) end)
  v.tables[i] = t
  return t
end

local function chairWidget(t, i)
  local c = t.chairs[i]
  if c then return c end
  local b = CreateFrame("Button", nil, t.frame)
  b:SetSize(26, 26)
  b:SetFrameLevel(t.top:GetFrameLevel() + 1)
  b:RegisterForClicks("LeftButtonUp")
  local rim = b:CreateTexture(nil, "BORDER")
  rim:SetAllPoints(b)
  rim:SetTexture(Theme.tex.chair)
  rim:SetVertexColor(Theme.rgb("woodDark"))
  local disc = b:CreateTexture(nil, "ARTWORK")
  disc:SetPoint("CENTER", b, "CENTER")
  local label = W.Label(t.frame, "ui", "", 11)
  label:SetJustifyH("CENTER")
  c = { button = b, rim = rim, disc = disc, label = label }
  b:SetScript("OnClick", function() Hall.clickChair(t, i) end)
  W.tooltip(b, function(tip) Hall.chairTooltip(tip, t.rec, i) end)
  b:HookScript("OnEnter", function() if c.empty then disc:SetVertexColor(Theme.rgb("gold")) end end)
  b:HookScript("OnLeave", function() if c.empty then disc:SetVertexColor(1, 1, 1) end end)
  t.chairs[i] = c
  return c
end

local function fillTable(t, rec, client)
  t.rec, t.tid = rec, rec.tid
  local mine = here(client, rec)
  t.game:SetText(gameName(rec.game))
  t.host:SetText(firstWord(rec.host))
  t.host:SetTextColor(nameColor(client, rec.host))
  t.state:SetText(L("hall.live"))
  t.state:SetShown(rec.state == "live")
  local n = #rec.seats
  local labelled = n <= LABELLED_SEATS
  local spots = HallLayout.chairs(n, CHAIR_R)
  local k = LABEL_R / CHAIR_R
  for i = 1, n do
    local c, name = chairWidget(t, i), rec.seats[i]
    local x, y = spots[i][1], spots[i][2]
    c.button:ClearAllPoints()
    c.button:SetPoint("CENTER", t.frame, "CENTER", x, y)
    c.label:ClearAllPoints()
    c.label:SetPoint("CENTER", t.frame, "CENTER", x * k, y * k)
    c.empty = not name
    if name then
      c.rim:Show()
      c.disc:SetTexture(Theme.tex.chair)
      c.disc:SetSize(22, 22)
      c.disc:SetVertexColor(nameColor(client, name))
      c.label:SetText(firstWord(name))
      c.label:SetTextColor(nameColor(client, name))
      c.label:SetShown(labelled)
      c.button:SetEnabled(false)
    else
      c.rim:Hide()
      c.disc:SetTexture(Theme.tex.chair_empty)
      c.disc:SetSize(26, 26)
      c.disc:SetVertexColor(1, 1, 1)
      c.label:Hide()
      c.button:SetEnabled(not mine)
    end
    c.button:Show()
  end
  for i = n + 1, #t.chairs do
    t.chairs[i].button:Hide()
    t.chairs[i].label:Hide()
  end
  t.glow:SetShown(mine)
  t.frame:SetScript("OnUpdate", mine and pulse or nil)
end

local function rowWidget(v, i)
  local r = v.rows[i]
  if r then return r end
  local content = v.list.content
  local f = CreateFrame("Frame", nil, content)
  f:SetSize(v.listW, ROW_H - 2)
  f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
  local mark = f:CreateTexture(nil, "ARTWORK")
  mark:SetPoint("TOPLEFT", f, "TOPLEFT")
  mark:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
  mark:SetWidth(3)
  mark:SetColorTexture(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 1)
  local line = f:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, -1)
  line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, -1)
  line:SetHeight(1)
  line:SetColorTexture(Theme.color.brass[1], Theme.color.brass[2], Theme.color.brass[3], 0.25)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetSize(28, 28)
  icon:SetPoint("LEFT", f, "LEFT", 8, 0)
  icon:SetTexture(Theme.tex.tabletop)
  local title = W.Label(f, "ui", "", 13)
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 2)
  local sub = W.Label(f, "dim", "")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  r = { frame = f, mark = mark, title = title, sub = sub }
  local action = W.Button(f, "", function() Hall.clickRow(r) end, true)
  action:SetSize(74, 22)
  action:SetPoint("RIGHT", f, "RIGHT", -4, 0)
  local state = W.Label(f, "dim", "", 12)
  state:SetWidth(60)
  state:SetPoint("RIGHT", action, "LEFT", -12, 0)
  local seats = W.Label(f, "ui", "", 13)
  seats:SetPoint("RIGHT", state, "LEFT", -12, 0)
  r.action, r.state, r.seats = action, state, seats
  v.rows[i] = r
  return r
end

local function fillRow(r, rec, client)
  r.rec, r.tid = rec, rec.tid
  r.title:SetText(L("hall.host", gameName(rec.game), colored(client, rec.host)))
  r.sub:SetText(L("access." .. tostring(rec.access)) .. " · " .. L("hall.turn", rec.turn) .. " · " .. (stakeText(rec) or L("table.stake.none")))
  r.seats:SetText(seatedCount(rec.seats) .. "/" .. #rec.seats)
  r.state:SetText(L(rec.state == "live" and "hall.live" or "hall.waiting"))
  local mine = here(client, rec)
  r.mark:SetShown(mine)
  if mine then
    r.act = nil
  elseif firstFree(rec.seats) then
    r.act = "sit"
  else
    r.act = "watch"
  end
  r.action.text:SetText(r.act == "sit" and L("hall.sit") or L("hall.watch"))
  r.action:SetShown(r.act ~= nil)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function renderFloor(v, recs, client)
  local slots = HallLayout.slots(#recs, v.floorW, v.floorH)
  for i, rec in ipairs(recs) do
    local t = tableWidget(v, i)
    fillTable(t, rec, client)
    t.frame:ClearAllPoints()
    t.frame:SetPoint("CENTER", v.floor, "TOPLEFT", slots[i][1], -slots[i][2])
    t.frame:Show()
  end
  for i = #recs + 1, #v.tables do
    v.tables[i].frame:Hide()
    v.tables[i].frame:SetScript("OnUpdate", nil)
  end
end

local function renderList(v, recs, client)
  for i, rec in ipairs(recs) do
    local r = rowWidget(v, i)
    fillRow(r, rec, client)
    r.frame:Show()
  end
  for i = #recs + 1, #v.rows do v.rows[i].frame:Hide() end
  v.list:setContentHeight(#recs * ROW_H)
end

-- Redraws the hall now (only while it is on screen; OnShow redraws it).
function Hall.render()
  local v = Hall.view
  if not v or not v.page:IsVisible() then return end
  local client = ns.client
  local recs, mode = {}, nil
  if not client then
    mode = ns.noGuild and "noguild" or "wait"
  else
    recs = HallLayout.order(client.lobby:tables(), client.env.me)
    mode = #recs == 0 and "empty" or HallLayout.mode(#recs)
  end
  Hall.mode = mode
  local key = MESSAGES[mode]
  if key then v.message:SetText(L(key)) end
  v.message:SetShown(key ~= nil)
  v.floor:SetShown(mode == "floor")
  v.list:SetShown(mode == "list")
  v.hint:SetShown(mode == "floor")
  if mode == "floor" then
    renderFloor(v, recs, client)
  elseif mode == "list" then
    renderList(v, recs, client)
  end
  ns.Accounts.render(v, client)
  ns.HallPeers.render(v, client)
  v.note:SetShown(Hall.updateAvailable)
end

-- Redraws on the next frame; several calls in one frame draw once.
function Hall.refresh()
  if Hall.scheduled then return end
  Hall.scheduled = true
  C_Timer.After(0, function()
    Hall.scheduled = false
    Hall.render()
  end)
end

---------------------------------------------------------------------------
-- Building the tab
---------------------------------------------------------------------------

local function buildLeft(v, page, colH)
  local left = W.Panel(page)
  left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  left:SetSize(LEFT_W, colH)
  W.Label(left, "heading", L("hall.open")):SetPoint("TOPLEFT", left, "TOPLEFT", 10, -10)
  local firstActive
  for i, g in ipairs(ns.Games.list()) do
    local row = CreateFrame("Button", nil, left)
    row:SetSize(LEFT_W - 20, GAME_H - 2)
    row:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -32 - (i - 1) * GAME_H)
    row:RegisterForClicks("LeftButtonUp")
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(row)
    hl:SetColorTexture(Theme.color.brassLight[1], Theme.color.brassLight[2], Theme.color.brassLight[3], 0.08)
    hl:Hide()
    row:SetScript("OnEnter", function() hl:Show() end)
    row:SetScript("OnLeave", function() hl:Hide() end)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    icon:SetTexture(Theme.tex.chair)
    icon:SetVertexColor(Theme.rgb("felt"))
    local rim = row:CreateTexture(nil, "OVERLAY")
    rim:SetSize(36, 36)
    rim:SetPoint("CENTER", icon, "CENTER")
    rim:SetTexture(Theme.tex.ring)
    local title = gameName(g.id)
    -- The game's picture on the felt disc; its first letter for a game without one.
    local path = Theme.gameIcon(g.id)
    if path then
      local pic = row:CreateTexture(nil, "OVERLAY", nil, 1)
      pic:SetSize(24, 24)
      pic:SetPoint("CENTER", icon, "CENTER", 0, 0)
      pic:SetTexture(path)
      pic:SetVertexColor(Theme.rgb("brassLight"))
      row.pic = pic
    else
      local letter = W.Label(row, "heading", initial(title), 14)
      color(letter, "cream")
      letter:SetJustifyH("CENTER")
      letter:SetPoint("CENTER", icon, "CENTER", 0, 0)
    end
    local name = W.Label(row, "ui", title, 13)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, 1)
    local sub = W.Label(row, "dim", L("games.players", g.players))
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    local soon = W.Label(row, "dim", L("games.soon"))
    color(soon, "gold")
    soon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 5)
    if g.engine then
      firstActive = firstActive or g.id
      soon:Hide()
      row:SetScript("OnClick", function() ns.NewTableDialog.open(g.id) end)
    else
      row:SetAlpha(0.45)
      row:SetScript("OnClick", function() if ns.HelpBook then ns.HelpBook.open("soon") end end)
    end
    v.games[i] = { id = g.id, frame = row, name = name, soon = soon }
  end
  local open = W.Button(left, L("hall.open"), function() ns.NewTableDialog.open(firstActive) end)
  open:SetSize(LEFT_W - 20, 28)
  open:SetPoint("BOTTOM", left, "BOTTOM", 0, 12)
  v.openButton = open
end

local function buildCentre(v, page, x, w, colH)
  local centre = W.Panel(page)
  centre:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
  centre:SetSize(w, colH)
  -- Floor planks (mockup 02): lighter wood, a seam every 22 px down and 64 px across.
  centre.fill:Hide()
  local planks = W.tile(centre, Theme.tex.wood, Theme.texSize.wood, w - 2, colH - 2)
  planks:SetPoint("TOPLEFT", centre, "TOPLEFT", 1, -1)
  planks:SetPoint("BOTTOMRIGHT", centre, "BOTTOMRIGHT", -1, 1)
  for y = 22, colH - 2, 22 do
    local s = centre:CreateTexture(nil, "BORDER")
    s:SetColorTexture(0, 0, 0, 0.18)
    s:SetPoint("TOPLEFT", centre, "TOPLEFT", 1, -y)
    s:SetSize(w - 2, 1)
  end
  for sx = 64, w - 2, 64 do
    local s = centre:CreateTexture(nil, "BORDER")
    s:SetColorTexture(0, 0, 0, 0.25)
    s:SetPoint("TOPLEFT", centre, "TOPLEFT", sx, -1)
    s:SetSize(1, colH - 2)
  end
  W.Label(centre, "heading", L("hall.title")):SetPoint("TOPLEFT", centre, "TOPLEFT", 10, -8)
  v.hint = W.Label(centre, "dim", L("hall.hint"), 12)
  v.hint:SetPoint("TOPRIGHT", centre, "TOPRIGHT", -10, -10)

  local floor = CreateFrame("Frame", nil, centre)
  floor:SetPoint("TOPLEFT", centre, "TOPLEFT", 0, -HEADER_H)
  floor:SetSize(w, colH - HEADER_H)
  v.floor, v.floorW, v.floorH = floor, w, colH - HEADER_H

  local message = W.Label(centre, "ui", "", 15)
  color(message, "inkDim")
  message:SetJustifyH("CENTER")
  message:SetWidth(w - 80)
  message:SetWordWrap(true)
  message:SetPoint("CENTER", floor, "CENTER", 0, 0)
  v.message = message

  local list = W.Scroll(centre)
  list:SetPoint("TOPLEFT", centre, "TOPLEFT", 8, -HEADER_H)
  list:SetPoint("BOTTOMRIGHT", centre, "BOTTOMRIGHT", -8, 8)
  v.listW = w - 16 - 6
  list.content:SetWidth(v.listW)
  v.list = list
end

function Hall.build(page)
  local v = { page = page, games = {}, tables = {}, rows = {}, peers = {} }
  Hall.view = v
  local bodyW, bodyH = ns.MainWindow.BODY_W, ns.MainWindow.BODY_H
  local colH = bodyH - FOOTER_H
  local centreW = bodyW - LEFT_W - Hall.RIGHT_W - 2 * GAP
  buildLeft(v, page, colH)
  buildCentre(v, page, LEFT_W + GAP, centreW, colH)
  local rightX = LEFT_W + GAP + centreW + GAP
  ns.Accounts.build(v, page, rightX, 0, Hall.RIGHT_W, Hall.ACCOUNTS_H)
  ns.HallPeers.build(v, page, rightX, Hall.ACCOUNTS_H + GAP, colH - Hall.ACCOUNTS_H - GAP)

  local footer = W.Label(page, "ui", "", 13)
  color(footer, "gold")
  footer:SetJustifyH("CENTER")
  footer:SetPoint("BOTTOM", page, "BOTTOM", 0, 4)
  footer:Hide()
  v.footer = footer
  local note = W.Label(page, "dim", L("update.available"), 12)
  color(note, "gold")
  note:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 4)
  note:Hide()
  v.note = note

  page:SetScript("OnShow", Hall.render)
  Hall.render()
end

ns.MainWindow.addTab("hall", "tab.hall", Hall.build)

ns.ready(function(client)
  client:on("peers", Hall.refresh)
  client:on("tables", Hall.refresh)
  client:on("session", Hall.refresh)
  client:on("refused", function(_, why) Hall.say(L("refused." .. tostring(why))) end)
  client:on("update", function()
    Hall.updateAvailable = true
    if ns.Adapter and ns.Adapter.say then ns.Adapter.say(L("update.available")) end
    Hall.refresh()
  end)
  Hall.refresh()
end)
