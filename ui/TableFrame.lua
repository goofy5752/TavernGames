local _, ns = ...

-- The table frame (mockup 03), shown whenever client.session is non-nil and
-- hidden when it is nil. Felt stretched once inside a wood frame with the brass
-- edge. One nameplate per seat, up to three rows (ns.HallLayout.plates): the
-- name in class color, the game's mark for that seat, and on the player on
-- turn a brass ring, a gold edge and the turn clock. The game's board in the
-- middle, drawn by the view registered for the game id, 16 px lower for every
-- plate row after the first (a view frame at most 236 high starts below two
-- rows of plates, which end 68 px from the top of the felt). A view with
-- `ring = true` (a team game, Холдем) gets its plates around the felt instead
-- (ns.HallLayout.ring: my seat at the bottom; four seats with the partner on
-- top, six clockwise with the next seat at my left) and its
-- board anchored TOPLEFT to the felt at 0, 0 (the view sizes it to the felt).
-- A view with `size = {w, h}` (Холдем: 760 x 532, a felt of 732 x 440) gets a
-- frame of that size, else the frame is WIDTH x HEIGHT; render sizes it (the
-- frame, the wood, the felt, the banner and the fairness line) whenever the
-- game shown changes.
-- A banner across the felt: waiting for players (or for the host to start;
-- a table that does not start by the host waits for a second player, or for
-- more players when its engine needs more than two seats), an aborted
-- match, a silent host, and for RESYNC_SECONDS after "desync" the resync note.
-- The fairness line is ui/TablePanels.lua's (TableFrame.panels.renderFair,
-- .fairTooltip): on a card table (ns.Deal.status) one line at the bottom edge of the felt:
-- the shuffle under way or the verdict on the last hand; on a dice table
-- (ns.Dice.status when Deal has none, the tooltip ns.Dice.tip) the throw
-- under way or the last one's verdict; at a sealed table (ns.Book.status when
-- neither has one, the tooltip ns.Book.tip) the book's count of hands; it
-- opens the rules book on "fair".
-- Title bar: the game, the access, turn time and table options, the stake
-- („Залог: 5g“, a staked table only), the watcher
-- count and ⓘ (topic = game id). Bottom: „Стани“
-- (watchers: „Към залата“; in a running match of a team game, or a running
-- staked game I play in, it first asks in a small panel above the button,
-- since my partner loses with me, or I lose by forfeit and owe the stake), „Покани“ for the host while a seat is free (a list
-- of who is in the tavern), „Започни“ / „Нова игра“ for the host of a
-- host-started game while none runs and of a game with `again` once it is
-- over, and one line of news for SAY_SECONDS. Once a staked game I played is
-- over, the bill „Сметката“ over the lower felt (ui/StakePanels.lua).
--
-- A view is { build(parent) -> frame, update(frame, session) } and may add
-- seatNote(session, seat) -> text for the plates, `ring = true` and `size`. Client
-- events only schedule a redraw for the next frame (TableFrame.refresh), as in
-- the hall.
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

-- view: { build(parent) -> frame, update(frame, session), seatNote(session, seat)?, ring?, size? }
function TableFrame.registerView(gameId, view) TableFrame.views[gameId] = view end

local function firstFree(seats)
  for i = 1, #seats do
    if seats[i] == false then return i end
  end
  return nil
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

-- Would standing up now cost something -> bool: I am seated in a live game
-- that is not over, of a team game (engine.teams: my partner loses with me),
-- or staked and I play in it (I lose by forfeit: TableFrame.panels.forfeitCost).
function TableFrame.standCosts(s)
  if s == nil or s.status ~= "live" or s.mySeat == nil or s:gameOver() then return false end
  return s:engine().teams == true or TableFrame.panels.forfeitCost(s) ~= nil
end

-- „Стани“ / „Към залата“: leave the table and go back to the hall. While
-- standCosts, the first click only opens the question („Отборът ви губи
-- мача…“, at a staked table „Ако станеш сега…“); its „Стани“ calls this with sure = true.
function TableFrame.stand(sure)
  local client = ns.client
  if not client then return end
  local v = TableFrame.view
  if v and sure ~= true and TableFrame.standCosts(client.session) then return TableFrame.panels.confirm(v, client.session) end
  if v then v.confirm:Hide() end
  client:stand()
  ns.MainWindow.show("hall")
end

-- „Започни“ / „Нова игра“: the host starts the next game; a refusal (a click
-- that lost a race with a player standing up, say; at a staked table a player
-- outside my group, or the break after a game) is said on the news line.
local START_WHY = { short = "start.short", live = "start.live", group = "start.group", ["break"] = "start.break" }
function TableFrame.startGame()
  local client = ns.client
  if not client then return end
  local started, code = client:startGame()
  if not started then TableFrame.say(L(START_WHY[code] or "start.failed")) end
end

function TableFrame.invite(name)
  local client = ns.client
  TableFrame.view.picker:Hide()
  if not client then return end
  local who = W.colored(client, name)
  TableFrame.say(L(client:invite(name) and "invite.sent" or "invite.fail", who))
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

-- Places the plates on the grid of ns.HallLayout.plates, or around the felt
-- (ns.HallLayout.ring) for a ring view -> the number of rows.
local function renderPlates(v, s, client)
  local n, view = #s.seats, TableFrame.views[s.game]
  local spots, rows
  if view and view.ring then
    spots, rows = ns.HallLayout.ring(n, v.areaW, v.areaH, s.mySeat or 1)
  else
    spots, rows = ns.HallLayout.plates(n, v.areaW)
  end
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

-- The board in the middle, 16 px lower for every plate row after the first;
-- a ring view's board over the whole felt.
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
  if view.ring then
    board:SetPoint("TOPLEFT", v.area, "TOPLEFT", 0, 0)
  else
    board:SetPoint("CENTER", v.area, "CENTER", 0, -6 - 16 * (rows - 1))
  end
  board:SetShown(s.state ~= nil)
  if s.state then view.update(board, s) end
end

-- Precedence: hostSilent > resynced > aborted > the open table's waiting line.
-- A host-started table waits for players, then for its host; any other open
-- table for a second player, or for more players when its engine needs more
-- than two seats; a game that is over shows none (the view says who lost).
local function bannerKey(s, engine)
  if s.hostSilent then return "table.hostSilent" end
  if TableFrame.resyncTid == s.tid then return "table.resynced" end
  if s.status == "aborted" then return "table.aborted" end
  if s.status ~= "open" then return nil end
  if engine.start ~= "host" then return engine.minSeats > 2 and "table.waitingMore" or "table.waiting" end
  if s:seatedCount() < engine.minSeats then return "table.waitingMore" end
  return s.role == "host" and "table.pressStart" or "table.waitingHost"
end

-- „Започни“ / „Нова игра“: the host of a host-started table while no game
-- runs, and of a game with `again` once Session:gameOver; bright exactly when
-- Session.startable (the check of startGame) says so, and enabled then and
-- while a staked table waits for the group or the break (a click says why);
-- redrawn when the break ends; right of „Покани“, or
-- of „Стани“ while „Покани“ is hidden. The news line sits right of it while it
-- is shown, else right of „Покани“.
local function renderStart(v, s, engine, client)
  local can, code = ns.Session.startable(client)
  local shown = s.role == "host" and code ~= "live"
    and (engine.start == "host" or engine.again and s:gameOver())
  local b = v.startButton
  b:SetShown(shown)
  if shown and code == "break" and not TableFrame.breakTimer then
    local left = s.stakeEndedAt + ns.Const.STAKE_BREAK - client.env.now()
    TableFrame.breakTimer = C_Timer.NewTimer(math.max(0, left) + 0.05, function()
      TableFrame.breakTimer = nil
      TableFrame.refresh()
    end)
  end
  if shown then
    b.text:SetText(L(s.state and "table.again" or "table.start"))
    b:SetEnabled(can == true or code == "group" or code == "break")
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
      text = text .. " · " .. L("opt." .. s.game .. "." .. id) .. " " .. W.optionText(s.game, id, opt[id])
    end
  end
  return text
end

-- Sizes the table frame to w x h: the frame, the wood, the felt (areaW x
-- areaH), the banner across it and the fairness line under it.
local function fit(v, w, h)
  TableFrame.frame:SetSize(w, h)
  v.wood:SetTexCoord(0, (w - 8) / Theme.texSize.wood, 0, (h - 8) / Theme.texSize.wood)
  v.areaW = w - 2 * (EDGE + 2)
  v.areaH = h - (EDGE + TITLE_H) - (EDGE + BOTTOM_H)
  v.area:SetSize(v.areaW, v.areaH)
  v.felt:SetSize(v.areaW, v.areaH)
  v.banner:SetWidth(v.areaW)
  v.fairLine:SetWidth(v.areaW - 40)
end

-- Redraws the table frame now; shows it while I am at a table, hides it otherwise.
function TableFrame.render()
  local client = ns.client
  local s = client and client.session
  if not s then
    if TableFrame.frame then
      TableFrame.view.confirm:Hide()
      TableFrame.frame:Hide()
    end
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
  if v.game ~= s.game then
    v.game = s.game
    local size = (TableFrame.views[s.game] or {}).size
    fit(v, size and size[1] or TableFrame.WIDTH, size and size[2] or TableFrame.HEIGHT)
  end
  local engine = s:engine()
  v.title:SetText(W.gameName(s.game))
  v.meta:SetText(metaText(s, engine))
  v.info.topic = s.game
  local watchers = s.watchers or 0
  v.watchers:SetText(L("table.watchers", watchers))
  v.watchers:SetShown(watchers > 0)
  v.stake:SetText(s.stake and L("table.stake", ns.Util.money(s.stake)) or "")
  v.stake:SetShown(s.stake ~= nil)
  ns.StakePanels.bill(v, s) -- before the board: its view hides its own result line under the bill
  renderBoard(v, s, renderPlates(v, s, client))
  local key = bannerKey(s, engine)
  if key then v.bannerText:SetText(L(key)) end
  v.banner:SetShown(key ~= nil)
  v.standButton.text:SetText(L(s.role == "watcher" and "table.toHall" or "table.stand"))
  if not TableFrame.standCosts(s) then v.confirm:Hide() end -- the match ended meanwhile
  local canInvite = s.role == "host" and firstFree(s.seats) ~= nil
  v.inviteButton:SetShown(canInvite)
  if not canInvite then
    v.picker:Hide()
  elseif v.picker:IsShown() then
    TableFrame.panels.renderPicker(v, client, s)
  end
  TableFrame.panels.renderFair(v, s)
  renderStart(v, s, engine, client)
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

function TableFrame.build()
  local W_, H_ = TableFrame.WIDTH, TableFrame.HEIGHT
  local f = CreateFrame("Frame", nil, UIParent)
  TableFrame.frame = f
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
  v.wood = wood
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
  v.stake = W.Label(bar, "ui", "", 12)
  v.stake:SetTextColor(Theme.rgb("gold"))
  v.stake:SetPoint("LEFT", v.meta, "RIGHT", 10, 0)
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
  v.area = area
  local felt = area:CreateTexture(nil, "BACKGROUND")
  felt:SetAllPoints(area)
  felt:SetTexture(Theme.tex.felt)
  v.felt = felt
  W.edges(area, 2).setColor(Theme.rgb("brass"))

  -- The banner across the felt, above the board.
  local banner = CreateFrame("Frame", nil, area)
  banner:SetHeight(36) -- as wide as the felt (fit)
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

  -- The fairness line at the bottom edge of the felt.
  local fairLine = CreateFrame("Button", nil, area)
  fairLine:SetHeight(18) -- 40 px narrower than the felt (fit)
  fairLine:SetPoint("BOTTOM", area, "BOTTOM", 0, 6)
  fairLine:SetFrameLevel(area:GetFrameLevel() + 8)
  fairLine:RegisterForClicks("LeftButtonUp")
  local fairText = W.Label(fairLine, "ui", "", 12)
  fairText:SetJustifyH("CENTER")
  fairText:SetWordWrap(false)
  fairText:SetAllPoints(fairLine)
  fairLine.text = fairText
  fairLine:SetScript("OnClick", function() if ns.HelpBook then ns.HelpBook.open("fair") end end)
  W.tooltip(fairLine, function(tip) TableFrame.panels.fairTooltip(tip) end)
  fairLine:Hide()
  v.fairLine = fairLine

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
  TableFrame.panels.build(v, f)
  fit(v, W_, H_)

  f:SetScript("OnUpdate", TableFrame.tick)
  f:Hide()
end

ns.ready(function(client)
  client:on("session", TableFrame.refresh)
  client:on("peers", TableFrame.refresh)
  client:on("desync", TableFrame.resynced)
  client:on("fair", TableFrame.refresh)
  TableFrame.refresh()
end)
