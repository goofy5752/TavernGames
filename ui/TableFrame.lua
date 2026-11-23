local _, ns = ...

-- The table frame (mockup 03), shown whenever client.session is non-nil and
-- hidden when it is nil. The skin's felt stretched once inside the skin's
-- frame with the brass edge, its crest as a watermark (alpha 0.13) and a
-- stitch 14 px inside the edge; the crest again right of the title. One
-- nameplate per seat, up to three rows (ns.HallLayout.plates): the hero, the
-- name in class color, the tricks, the game's mark for that seat, and on the
-- player on turn a gold ring, a gold edge and the turn clock (ui/TablePlates.lua,
-- TableFrame.plates). The game's board in the
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
-- more players when its engine needs more than two seats; a staked table full
-- again counts down the break its start waits for), an aborted match, a silent
-- host, and for RESYNC_SECONDS after "desync" the resync note.
-- The fairness line is ui/TablePanels.lua's (TableFrame.panels.renderFair,
-- .fairTooltip): on a card table (ns.Deal.status) one line at the bottom edge of the felt:
-- the shuffle under way or the verdict on the last hand; on a dice table
-- (ns.Dice.status when Deal has none, the tooltip ns.Dice.tip) the throw
-- under way or the last one's verdict; at a sealed table (ns.Book.status when
-- neither has one, the tooltip ns.Book.tip) the book's count of hands; it
-- opens the rules book on "fair".
-- Title bar: the game, the access, turn time and table options, the stake
-- („Залог: 5g“, a staked table only; a cash table its blinds), the watcher
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
-- seatNote(session, seat) -> text and seatTricks(session, seat) -> number | nil
-- for the plates, `ring = true` and `size`. Client
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
local SAY_SECONDS, RESYNC_SECONDS = 5, 3
local WATERMARK, WATERMARK_ALPHA, STITCH_INSET = 0.6, 0.13, 14 -- the crest: a share of the felt's shorter side
local STITCH = { alliance = { 2, 1, 1, 1, 0.12 }, horde = { 3, 0, 0, 0, 0.45 } } -- skin -> px, r, g, b, a

-- view: { build(parent) -> frame, update(frame, session), seatNote(session, seat)?, seatTricks(session, seat)?, ring?, size? }
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
  if s == nil or s.status ~= "live" or s.mySeat == nil or s:gameOver() or s:engine().cashGame then return false end -- a cash table has no forfeit
  return s:engine().teams == true or TableFrame.panels.forfeitCost(s) ~= nil
end

-- „Стани“ / „Към залата“: leave the table and go back to the hall. While
-- standCosts, the first click only opens the question („Отборът ви губи
-- мача…“, at a staked table „Ако станеш сега…“); its „Стани“ calls this with sure = true.
-- Does my cash-out of table session s wait (client.cashGoing) -> bool.
function TableFrame.cashGoing(client, s)
  return s ~= nil and client.cashGoing ~= nil and client.cashGoing.tid == s.tid
end

-- At a cash table my cash-out is made first and the table stays until it is applied (client.cashGoing, the news
-- line says so; the hall shows when my session ends); while it waits the button reads „Стани веднага“ and stands at once.
function TableFrame.stand(sure)
  local client = ns.client
  if not client then return end
  local v, s = TableFrame.view, client.session
  local going = TableFrame.cashGoing(client, s)
  if v and sure ~= true and TableFrame.standCosts(s) then return TableFrame.panels.confirm(v, s) end
  if v then v.confirm:Hide() end
  client:stand(going or nil)
  if client.session == s and client.cashGoing and s then return TableFrame.say(L("cash.going")) end
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

-- „Добави ботове“: the shared Adapter.fillBots; what it says goes on the news line.
function TableFrame.addBots()
  local got, started = ns.Adapter.fillBots()
  if got == "wait" then return TableFrame.say(L("bots.wait")) end
  TableFrame.say(L(got == "nofill" and "bots.nofill" or started and "bots.on" or "table.addBots.asked"))
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

-- The turn clock on the plate of the player on turn (ui/TablePlates.lua).
function TableFrame.tick()
  local v, client = TableFrame.view, ns.client
  local s = client and client.session
  if v and s then TableFrame.plates.tick(v, s) end
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

-- Precedence: hostSilent > resynced > the held start (a staked table full again,
-- s.holdTimer: key, whole seconds or the silent player, seconds left) > aborted > the open table's line. A host-started table waits for players, then for
-- its host; any other open table for a second player, or for more players when
-- its engine needs more than two seats; a game that is over shows none (the view says who lost).
local function bannerKey(s, engine)
  if s.hostSilent then return "table.hostSilent" end
  if TableFrame.resyncTid == s.tid then return "table.resynced" end
  local left, silent
  if s.holdTimer and s.role == "host" then left, silent = ns.Stakes.held(s) end
  if left then return silent and "table.holdSilent" or "table.holdStart", silent and W.colored(ns.client, silent) or math.max(1, math.ceil(left)), left end
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
    local left = ns.Stakes.held(s)
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
    b:SetPoint("LEFT", v.inviteButton:IsShown() and v.inviteButton or v.standButton, "RIGHT", 6, 0)
  end
  local bots = v.botsButton
  local canBots = ns.Bots.canFill(s)
  bots:SetShown(canBots)
  if canBots then
    bots:ClearAllPoints()
    bots:SetPoint("LEFT", shown and b or v.inviteButton:IsShown() and v.inviteButton or v.standButton, "RIGHT", 6, 0)
  end
  v.line:ClearAllPoints()
  v.line:SetPoint("LEFT", canBots and bots or shown and b or v.inviteButton, "RIGHT", 8, 0)
  v.line:SetPoint("RIGHT", TableFrame.frame, "BOTTOMRIGHT", -(EDGE + 24), EDGE + 20) -- clear of the resize grip
end

-- A countdown on the felt (the held start, a guest's bill line), `left` s to go: redrawn as its whole second changes.
local function countdown(left)
  if TableFrame.countTimer or not left or left <= 0 then return end
  TableFrame.countTimer = C_Timer.NewTimer(left - math.ceil(left) + 1.01, function()
    TableFrame.countTimer = nil
    TableFrame.refresh()
  end)
end

-- After the access and the turn time: " · <option> <value>" for every option.
local function metaText(s, engine)
  local text = L("access." .. tostring(s.access)) .. " · " .. L("hall.turn", s.turn or 0)
  local options, opt = engine.options or {}, s.opt or {}
  for i = 1, #options do
    local id = options[i].id
    if opt[id] ~= nil and not (id == "blinds" and s.stake and engine.cashGame) then -- a cash table's blinds are its stake line
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
  local mark = WATERMARK * math.min(v.areaW, v.areaH)
  v.watermark:SetSize(mark, mark)
  v.watermark:ClearAllPoints()
  v.watermark:SetPoint("CENTER", v.area, "CENTER", 0, 0.04 * mark) -- 4 % of its height above the middle
  v.banner:SetWidth(v.areaW)
  v.fairLine:SetWidth(v.areaW - 40)
end

-- Redraws the table frame now; shows it while I am at a table, hides it otherwise.
function TableFrame.render()
  local client = ns.client
  local s = client and client.session
  if not s then
    if TableFrame.breakTimer then TableFrame.breakTimer:Cancel(); TableFrame.breakTimer = nil end
    if TableFrame.countTimer then TableFrame.countTimer:Cancel(); TableFrame.countTimer = nil end
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
  local blinds = s.stake and ns.StakePanels.blinds(s.game, s.stake) -- a cash table shows its blinds, not its big blind as a stake
  v.stake:SetText(blinds and L("table.blinds", blinds) or s.stake and L("table.stake", ns.W.money(s.stake)) or "")
  v.stake:SetShown(s.stake ~= nil)
  local billLeft = ns.StakePanels.bill(v, s) -- before the board: its view hides its own result line under the bill
  renderBoard(v, s, TableFrame.plates.render(v, s, client))
  local key, secs, left = bannerKey(s, engine)
  if key then v.bannerText:SetText(secs and L(key, secs) or L(key)) end
  v.banner:SetShown(key ~= nil)
  countdown(left or billLeft)
  W.fit(v.standButton.text, L(TableFrame.cashGoing(client, s) and "cash.standNow" or s.role == "watcher" and "table.toHall" or "table.stand"), 84)
  if not TableFrame.standCosts(s) then v.confirm:Hide() elseif v.confirm:IsShown() then TableFrame.panels.confirm(v, s) end -- ended, or the cost moved
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

-- Brings my table window up in front of the tavern window (built, drawn and
-- shown even when I had closed it) -> true, or false without a session.
function TableFrame.focus()
  local client = ns.client
  if not (client and client.session) then return false end
  TableFrame.render()
  TableFrame.frame:Show()
  TableFrame.frame:Raise()
  return true
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
  W.dragBy(f)
  ns.Resize.attach(f, "table", 6)
  local v = { plates = {} }
  TableFrame.view = v

  local chrome = W.chrome(f, W_, H_)
  v.wood, v.chrome = chrome.wood, chrome

  -- Title bar: the drag handle.
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -EDGE)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -EDGE, -EDGE)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  W.dragBy(bar, f)
  v.title = W.Label(bar, "heading", "", 16)
  v.title:SetPoint("LEFT", bar, "LEFT", 8, 0)
  v.crest = W.crest(bar, 20)
  v.crest:SetPoint("LEFT", v.title, "RIGHT", 6, 0)
  v.meta = W.Label(bar, "dim", "", 12)
  v.meta:SetPoint("LEFT", v.crest, "RIGHT", 6, 0)
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
  -- The skin's crest as a watermark (sized in fit) and the stitch 14 px inside
  -- the edge, in a frame at the felt's own level, under the board.
  v.watermark = W.crest(area, 1)
  v.watermark:SetAlpha(WATERMARK_ALPHA)
  local seam = CreateFrame("Frame", nil, area)
  seam:SetPoint("TOPLEFT", area, "TOPLEFT", STITCH_INSET, -STITCH_INSET)
  seam:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -STITCH_INSET, STITCH_INSET)
  seam:SetFrameLevel(area:GetFrameLevel())
  local stitch = STITCH[Theme.skin] or STITCH.alliance
  v.stitch = W.edges(seam, stitch[1])
  v.stitch.setColor(stitch[2], stitch[3], stitch[4], stitch[5])
  v.stitch.frame = seam

  -- The banner across the felt, above the board.
  local banner = CreateFrame("Frame", nil, area)
  banner:SetHeight(36) -- as wide as the felt (fit)
  banner:SetPoint("CENTER", area, "CENTER", 0, 0)
  banner:SetFrameLevel(area:GetFrameLevel() + ns.Cards.TOP + 10) -- above a full hand (ui/Cards.lua)
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
  stand:SetSize(96, 26)
  stand:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE + 4, EDGE + 7)
  v.standButton = stand
  local invite = W.Button(f, L("hall.invite"), TableFrame.togglePicker)
  invite:SetSize(80, 26)
  invite:SetPoint("LEFT", stand, "RIGHT", 6, 0)
  v.inviteButton = invite
  local start = W.Button(f, L("table.start"), TableFrame.startGame)
  start:SetSize(88, 26)
  start:SetPoint("LEFT", invite, "RIGHT", 6, 0)
  start:Hide()
  v.startButton = start
  local bots = W.Button(f, L("table.addBots"), TableFrame.addBots)
  bots:SetSize(96, 26)
  W.fit(bots.text, L("table.addBots"), 84)
  W.tooltip(bots, function(tip) tip:SetText(L("table.addBots.tip"), Theme.rgb("inkDim")) end)
  bots:Hide()
  v.botsButton = bots
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
  ns.Sounds.window(f)
end

ns.ready(function(client)
  client:on("session", TableFrame.refresh)
  client:on("cashGoing", function(tid) -- my cash-out waits, or went: my table ended
    local open = TableFrame.frame and TableFrame.frame:IsShown() -- a window I closed stays closed
    if tid == nil and not client.session and open then ns.MainWindow.show("hall") end; TableFrame.refresh()
  end)
  client:on("peers", TableFrame.refresh)
  client:on("desync", TableFrame.resynced)
  client:on("fair", TableFrame.refresh)
  TableFrame.refresh()
end)
