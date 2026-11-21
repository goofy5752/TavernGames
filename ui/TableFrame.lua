local _, ns = ...

-- The table frame (mockup 03), shown whenever client.session is non-nil and
-- hidden when it is nil. Felt stretched once inside a wood frame with the brass
-- edge. One nameplate per seat, up to three rows (ns.HallLayout.plates): the
-- name in class color, the game's mark for that seat, and on the player on
-- turn a brass ring, a gold edge and the turn clock. The game's board in the
-- middle, drawn by the view registered for the game id, 16 px lower for every
-- plate row after the first (a view frame at most 236 high starts below two
-- rows of plates, which end 68 px from the top of the felt).
-- A banner across the felt: waiting for players (or for the host to start), an
-- aborted match, a silent host, and for RESYNC_SECONDS after "desync" the
-- resync note. Title bar: the game, the access, turn time and table options,
-- the watcher count and ⓘ (topic = game id). Bottom: „Стани“ (watchers: „Към
-- залата“), „Покани“ for the host while a seat is free (a list of who is in
-- the tavern), „Започни“ / „Нова игра“ for the host of a host-started game
-- while none runs, and one line of news for SAY_SECONDS.
--
-- A view is { build(parent) -> frame, update(frame, session) } and may add
-- seatNote(session, seat) -> text for the plates. Client events only schedule
-- a redraw for the next frame (TableFrame.refresh), as in the hall.
local Theme, W, L = ns.Theme, ns.W, ns.L

local TableFrame = {
  WIDTH = 560, HEIGHT = 420,
  views = {},       -- game id -> view
  built = {},       -- game id -> the view's frame, once built
  frame = nil,      -- the table frame, once built
  view = nil,       -- its widgets
  resyncTid = nil,  -- the table whose resync banner is showing
}
ns.TableFrame = TableFrame

local EDGE, TITLE_H, BOTTOM_H = 12, 28, 40
local PLATE_W, PLATE_H = 190, 26     -- plate size before ns.HallLayout.plates sets the width
local PLATE_NAME_INSET = 28 + 64      -- the plate width the disc and the clock/note keep from the name
local SAY_SECONDS, RESYNC_SECONDS = 5, 3
local PICK_W, PICK_ROWS, PICK_ROW_H = 230, 8, 20

-- view: { build(parent) -> frame, update(frame, session), seatNote(session, seat)? }
function TableFrame.registerView(gameId, view) TableFrame.views[gameId] = view end

local function firstFree(seats)
  for i = 1, #seats do
    if seats[i] == false then return i end
  end
  return nil
end

local function seated(seats, name)
  for i = 1, #seats do
    if seats[i] == name then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- One line at the bottom of the table frame for SAY_SECONDS -> true, or false
-- when the frame is not on screen.
function TableFrame.say(text)
  local v = TableFrame.view
  if not v or not TableFrame.frame:IsShown() then return false end
  v.line:SetText(text)
  v.line:Show()
  if TableFrame.sayTimer then TableFrame.sayTimer:Cancel() end
  TableFrame.sayTimer = C_Timer.NewTimer(SAY_SECONDS, function()
    TableFrame.sayTimer = nil
    v.line:Hide()
  end)
  return true
end

-- „Стани“ / „Към залата“: leave the table and go back to the hall.
function TableFrame.stand()
  local client = ns.client
  if not client then return end
  client:stand()
  ns.MainWindow.show("hall")
end

-- „Започни“ / „Нова игра“: the host starts the next game; a refusal (a click
-- that lost a race with a player standing up, say) is said on the news line.
function TableFrame.startGame()
  local client = ns.client
  if not client then return end
  local started, code = client:startGame()
  if not started then
    TableFrame.say(L(code == "short" and "start.short" or code == "live" and "start.live" or "start.failed"))
  end
end

function TableFrame.invite(name)
  local client = ns.client
  TableFrame.view.picker:Hide()
  if not client then return end
  local who = W.colored(client, name)
  TableFrame.say(L(client:invite(name) and "invite.sent" or "invite.fail", who))
end

---------------------------------------------------------------------------
-- The „Покани“ list
---------------------------------------------------------------------------

local function pickerRow(picker, i)
  local r = picker.rows[i]
  if r then return r end
  local content = picker.scroll.content
  local b = CreateFrame("Button", nil, content)
  b:SetSize(picker.rowW, PICK_ROW_H)
  b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * PICK_ROW_H)
  b:RegisterForClicks("LeftButtonUp")
  local hl = b:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints(b)
  hl:SetColorTexture(Theme.color.brassLight[1], Theme.color.brassLight[2], Theme.color.brassLight[3], 0.08)
  hl:Hide()
  b:SetScript("OnEnter", function() hl:Show() end)
  b:SetScript("OnLeave", function() hl:Hide() end)
  local name = W.Label(b, "ui", "", 12)
  name:SetWidth(picker.rowW - 4)
  name:SetWordWrap(false)
  name:SetPoint("LEFT", b, "LEFT", 2, 0)
  r = { frame = b, name = name }
  b:SetScript("OnClick", function() TableFrame.invite(r.peerName) end)
  picker.rows[i] = r
  return r
end

-- Everyone in the tavern with a compatible addon who is not seated at my table.
local function renderPicker(v, client, s)
  local picker, n = v.picker, 0
  for _, p in ipairs(client.presence:list()) do
    if not p.incompatible and not seated(s.seats, p.name) then
      n = n + 1
      local r = pickerRow(picker, n)
      r.peerName = p.name
      r.name:SetText(p.name)
      r.name:SetTextColor(ns.classColor(p.cls))
      r.frame:Show()
    end
  end
  for i = n + 1, #picker.rows do picker.rows[i].frame:Hide() end
  picker.scroll:setContentHeight(n * PICK_ROW_H)
  picker.empty:SetShown(n == 0)
end

function TableFrame.togglePicker()
  local v, client = TableFrame.view, ns.client
  local s = client and client.session
  if v.picker:IsShown() or not s then return v.picker:Hide() end
  v.picker:Show()
  renderPicker(v, client, s)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function plateWidget(v, i)
  local p = v.plates[i]
  if p then return p end
  local f = CreateFrame("Frame", nil, v.area)
  f:SetSize(PLATE_W, PLATE_H)
  f:SetFrameLevel(v.area:GetFrameLevel() + 2)
  local fill = f:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(f)
  fill:SetColorTexture(32 / 255, 16 / 255, 8 / 255, 0.82)
  local edges = W.edges(f, 1)
  local disc = f:CreateTexture(nil, "ARTWORK")
  disc:SetSize(16, 16)
  disc:SetPoint("LEFT", f, "LEFT", 6, 0)
  local ring = f:CreateTexture(nil, "OVERLAY")
  ring:SetSize(24, 24)
  ring:SetPoint("CENTER", disc, "CENTER")
  ring:SetTexture(Theme.tex.ring)
  local name = W.Label(f, "ui", "", 12)
  name:SetFont(Theme.font.uiBold, 12, "")
  name:SetWordWrap(false)
  name:SetWidth(PLATE_W - PLATE_NAME_INSET)
  name:SetPoint("LEFT", f, "LEFT", 28, 0)
  local clock = W.Label(f, "ui", "", 12)
  clock:SetTextColor(Theme.rgb("gold"))
  clock:SetJustifyH("RIGHT")
  clock:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  local note = W.Label(f, "heading", "", 13)
  note:SetJustifyH("CENTER")
  note:SetPoint("RIGHT", f, "RIGHT", -42, 0)
  p = { frame = f, edges = edges, disc = disc, ring = ring, name = name, note = note, clock = clock }
  v.plates[i] = p
  return p
end

-- The turn clock on the plate of the player on turn.
function TableFrame.tick()
  local v, client = TableFrame.view, ns.client
  local s = client and client.session
  if not v or not s then return end
  local left = s:left()
  if not left then return end
  local secs = math.ceil(left)
  local text = L("table.clock", math.floor(secs / 60), secs % 60)
  for i = 1, #v.plates do
    if v.plates[i].clock:IsShown() then v.plates[i].clock:SetText(text) end
  end
end

-- Places the plates on the grid of ns.HallLayout.plates -> the number of rows.
local function renderPlates(v, s, client)
  local n, view = #s.seats, TableFrame.views[s.game]
  local spots, rows = ns.HallLayout.plates(n, v.areaW)
  local turn = s.status == "live" and s.state and s.state.turn
  for i = 1, n do
    local p, name, spot = plateWidget(v, i), s.seats[i], spots[i]
    p.frame:ClearAllPoints()
    p.frame:SetPoint("TOPLEFT", v.area, "TOPLEFT", spot[1], spot[2])
    p.frame:SetWidth(spot[3])
    p.name:SetWidth(spot[3] - PLATE_NAME_INSET)
    if name then
      p.name:SetText(name)
      p.name:SetTextColor(W.nameColor(client, name))
      p.disc:SetTexture(Theme.tex.chair)
      p.disc:SetVertexColor(W.nameColor(client, name))
    else
      p.name:SetText(L("table.free"))
      p.name:SetTextColor(Theme.rgb("inkDim"))
      p.disc:SetTexture(Theme.tex.chair_empty)
      p.disc:SetVertexColor(1, 1, 1)
    end
    p.note:SetText(view and view.seatNote and view.seatNote(s, i) or "")
    local onTurn = turn == i
    p.ring:SetShown(onTurn)
    p.clock:SetShown(onTurn and s.deadline ~= nil)
    p.edges.setColor(Theme.rgb(onTurn and "gold" or "brass"))
    p.frame:Show()
  end
  for i = n + 1, #v.plates do v.plates[i].frame:Hide() end
  return rows
end

-- The board in the middle, 16 px lower for every plate row after the first.
local function renderBoard(v, s, rows)
  for id, frame in pairs(TableFrame.built) do
    if id ~= s.game then frame:Hide() end
  end
  local view = TableFrame.views[s.game]
  if not view then return end
  local board = TableFrame.built[s.game]
  if not board then
    board = view.build(v.area)
    TableFrame.built[s.game] = board
  end
  board:ClearAllPoints()
  board:SetPoint("CENTER", v.area, "CENTER", 0, -6 - 16 * (rows - 1))
  board:SetShown(s.state ~= nil)
  if s.state then view.update(board, s) end
end

-- Precedence: hostSilent > resynced > aborted > the open table's waiting line.
-- A host-started table waits for players, then for its host; a game that is
-- over shows none (the view says who lost).
local function bannerKey(s, engine)
  if s.hostSilent then return "table.hostSilent" end
  if TableFrame.resyncTid == s.tid then return "table.resynced" end
  if s.status == "aborted" then return "table.aborted" end
  if s.status ~= "open" then return nil end
  if engine.start ~= "host" then return "table.waiting" end
  if s:seatedCount() < engine.minSeats then return "table.waitingMore" end
  return s.role == "host" and "table.pressStart" or "table.waitingHost"
end

-- „Започни“ / „Нова игра“: the host of a host-started table while no game
-- runs, enabled exactly when Session:canStart (the check of startGame) says
-- so; right of „Покани“, or of „Стани“ while „Покани“ is hidden. The news
-- line sits right of it while it is shown, else right of „Покани“.
local function renderStart(v, s, engine)
  local can, code = s:canStart()
  local shown = s.role == "host" and engine.start == "host" and code ~= "live"
  local b = v.startButton
  b:SetShown(shown)
  if shown then
    b.text:SetText(L(s.state and "table.again" or "table.start"))
    b:SetEnabled(can == true)
    b:SetAlpha(can and 1 or 0.5)
    b:ClearAllPoints()
    b:SetPoint("LEFT", v.inviteButton:IsShown() and v.inviteButton or v.standButton, "RIGHT", 8, 0)
  end
  v.line:ClearAllPoints()
  v.line:SetPoint("LEFT", shown and b or v.inviteButton, "RIGHT", 14, 0)
  v.line:SetPoint("RIGHT", TableFrame.frame, "BOTTOMRIGHT", -(EDGE + 8), EDGE + 20)
end

-- After the access and the turn time: " · <option> <value>" for every option.
local function metaText(s, engine)
  local text = L("access." .. tostring(s.access)) .. " · " .. L("hall.turn", s.turn or 0)
  local options, opt = engine.options or {}, s.opt or {}
  for i = 1, #options do
    local id = options[i].id
    if opt[id] ~= nil then
      text = text .. " · " .. L("opt." .. s.game .. "." .. id) .. " " .. tostring(opt[id])
    end
  end
  return text
end

-- Redraws the table frame now; shows it while I am at a table, hides it otherwise.
function TableFrame.render()
  local client = ns.client
  local s = client and client.session
  if not s then
    if TableFrame.frame then TableFrame.frame:Hide() end
    return
  end
  if not TableFrame.frame then TableFrame.build() end
  local f, v = TableFrame.frame, TableFrame.view
  if v.tid ~= s.tid then
    v.tid = s.tid
    v.picker:Hide()
  end
  if not f:IsShown() then
    f:Show()
    f:Raise()
  end
  local engine = s:engine()
  v.title:SetText(W.gameName(s.game))
  v.meta:SetText(metaText(s, engine))
  v.info.topic = s.game
  local watchers = s.watchers or 0
  v.watchers:SetText(L("table.watchers", watchers))
  v.watchers:SetShown(watchers > 0)
  renderBoard(v, s, renderPlates(v, s, client))
  local key = bannerKey(s, engine)
  if key then v.bannerText:SetText(L(key)) end
  v.banner:SetShown(key ~= nil)
  v.standButton.text:SetText(L(s.role == "watcher" and "table.toHall" or "table.stand"))
  local canInvite = s.role == "host" and firstFree(s.seats) ~= nil
  v.inviteButton:SetShown(canInvite)
  if not canInvite then
    v.picker:Hide()
  elseif v.picker:IsShown() then
    renderPicker(v, client, s)
  end
  renderStart(v, s, engine)
  TableFrame.tick()
end

-- Redraws on the next frame; several calls in one frame draw once.
function TableFrame.refresh()
  if TableFrame.scheduled then return end
  TableFrame.scheduled = true
  C_Timer.After(0, function()
    TableFrame.scheduled = false
    TableFrame.render()
  end)
end

-- The board was out of step with the host (it is being healed): say so for a while.
function TableFrame.resynced(tid)
  TableFrame.resyncTid = tid
  if TableFrame.resyncTimer then TableFrame.resyncTimer:Cancel() end
  TableFrame.resyncTimer = C_Timer.NewTimer(RESYNC_SECONDS, function()
    TableFrame.resyncTimer = nil
    TableFrame.resyncTid = nil
    TableFrame.refresh()
  end)
  TableFrame.refresh()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function buildPicker(v, f)
  local picker = W.Panel(f)
  picker.fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.95)
  picker:SetSize(PICK_W, 30 + PICK_ROWS * PICK_ROW_H + 8)
  picker:SetPoint("BOTTOMLEFT", v.inviteButton, "TOPLEFT", 0, 6)
  picker:SetFrameLevel(f:GetFrameLevel() + 20)
  picker:EnableMouse(true)
  W.Label(picker, "heading", L("table.pick"), 13):SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -9)
  local scroll = W.Scroll(picker)
  scroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 8, -30)
  scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -8, 8)
  picker.rowW = PICK_W - 16 - 6
  scroll.content:SetWidth(picker.rowW)
  picker.scroll = scroll
  picker.rows = {}
  picker.empty = W.Label(picker, "dim", L("peers.empty"), 12)
  picker.empty:SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -32)
  picker:Hide()
  v.picker = picker
end

function TableFrame.build()
  local W_, H_ = TableFrame.WIDTH, TableFrame.HEIGHT
  local f = CreateFrame("Frame", nil, UIParent)
  TableFrame.frame = f
  f:SetSize(W_, H_)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  local v = { plates = {} }
  TableFrame.view = v

  local wood = W.tile(f, Theme.tex.wood, Theme.texSize.wood, W_ - 8, H_ - 8)
  wood:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  wood:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  wood:SetVertexColor(0.85, 0.85, 0.85)
  W.nine(f, Theme.tex.frame, Theme.texSize.frame, EDGE, EDGE, "BORDER", true)

  -- Title bar: the drag handle.
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -EDGE)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -EDGE, -EDGE)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  v.title = W.Label(bar, "heading", "", 16)
  v.title:SetPoint("LEFT", bar, "LEFT", 8, 0)
  v.meta = W.Label(bar, "dim", "", 12)
  v.meta:SetPoint("LEFT", v.title, "RIGHT", 12, 0)
  v.info = W.Info(f, "ttt")
  v.info:SetFrameLevel(bar:GetFrameLevel() + 2)
  v.info:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
  v.watchers = W.Label(bar, "dim", "", 12)
  v.watchers:SetJustifyH("RIGHT")
  v.watchers:SetPoint("RIGHT", v.info, "LEFT", -12, 0)

  -- The felt: the radial vignette stretched once over the whole area.
  local area = CreateFrame("Frame", nil, f)
  area:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 2, -(EDGE + TITLE_H))
  area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(EDGE + 2), EDGE + BOTTOM_H)
  v.areaW = W_ - 2 * (EDGE + 2)
  v.areaH = H_ - (EDGE + TITLE_H) - (EDGE + BOTTOM_H)
  area:SetSize(v.areaW, v.areaH)
  v.area = area
  local felt = area:CreateTexture(nil, "BACKGROUND")
  felt:SetAllPoints(area)
  felt:SetTexture(Theme.tex.felt)
  v.felt = felt
  W.edges(area, 2).setColor(Theme.rgb("brass"))

  -- The banner across the felt, above the board.
  local banner = CreateFrame("Frame", nil, area)
  banner:SetSize(v.areaW, 36)
  banner:SetPoint("CENTER", area, "CENTER", 0, 0)
  banner:SetFrameLevel(area:GetFrameLevel() + 10)
  local shade = banner:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints(banner)
  shade:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.8)
  local bannerText = W.Label(banner, "heading", "", 16)
  bannerText:SetTextColor(Theme.rgb("gold"))
  bannerText:SetJustifyH("CENTER")
  bannerText:SetPoint("CENTER", banner, "CENTER", 0, 0)
  banner:Hide()
  v.banner, v.bannerText = banner, bannerText

  -- Bottom: „Стани“, „Покани“ and the news line.
  local stand = W.Button(f, L("table.stand"), TableFrame.stand)
  stand:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE + 4, EDGE + 7)
  v.standButton = stand
  local invite = W.Button(f, L("hall.invite"), TableFrame.togglePicker)
  invite:SetSize(100, 26)
  invite:SetPoint("LEFT", stand, "RIGHT", 8, 0)
  v.inviteButton = invite
  local start = W.Button(f, L("table.start"), TableFrame.startGame)
  start:SetSize(110, 26)
  start:SetPoint("LEFT", invite, "RIGHT", 8, 0)
  start:Hide()
  v.startButton = start
  local line = W.Label(f, "ui", "", 12)
  line:SetTextColor(Theme.rgb("gold"))
  line:SetJustifyH("RIGHT")
  line:SetWordWrap(false)
  line:SetPoint("LEFT", invite, "RIGHT", 14, 0)
  line:SetPoint("RIGHT", f, "BOTTOMRIGHT", -(EDGE + 8), EDGE + 20)
  line:Hide()
  v.line = line
  buildPicker(v, f)

  f:SetScript("OnUpdate", TableFrame.tick)
  f:Hide()
end

ns.ready(function(client)
  client:on("session", TableFrame.refresh)
  client:on("peers", TableFrame.refresh)
  client:on("desync", TableFrame.resynced)
  TableFrame.refresh()
end)
