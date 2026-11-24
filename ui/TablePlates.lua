local _, ns = ...

-- The plates of the table frame, split out of ui/TableFrame.lua: one per seat,
-- on the grid of ns.HallLayout.plates, or around the felt (ns.HallLayout.ring)
-- for a ring view. A plate is a WoW unit frame (spec 5.5, mockup 08) in a bar
-- of 26 px: on the bar's left end the seat's hero (ui/Portrait.lua, 30 px, with
-- the class badge; the empty chair on a free seat), its ring gold and glowing
-- while the seat is on turn; the name 40 px in, in class colour; under it,
-- a pip for every trick the seat took (the view's seatTricks, at most eight) in
-- a row centred on the bar's bottom edge, under the name's column and below the
-- line of text, so a long name, the note and the clock never meet it; the
-- game's mark for the seat (seatNote); on the plate on turn a gold edge, the
-- turn clock and a 3 px gold line along the bar's bottom (under the pips) as
-- wide as the share of the turn time left. A portrait is set only when the
-- seat's hero changes. The name is the short one among the table's seats
-- (ui/NameTag.lua, a bot's with its cog), shrunk and then wrapped in its column,
-- never cut; a hover over the plate gives the whole name. TableFrame.plates is
-- what the frame calls.
local TableFrame = ns.TableFrame
local Theme, W, L, Portrait = ns.Theme, ns.W, ns.L, ns.Portrait

local PLATE_W, PLATE_H = 190, 26          -- plate size before ns.HallLayout.plates sets the width
local PORTRAIT, NAME_X = 30, 40           -- the hero centred on the bar's left end; the name after it
local NOTE_RIGHT, NOTE_GAP, NAME_MIN = 42, 4, 32 -- the note ends 42 px in (the clock's room); a gap to the name; the least name a wide note leaves
local NOTE_EDGE = 6                       -- where the note ends on a plate that shows no clock
local NAME_LEAST = 16                     -- a name's column is never narrower (W.fitWrap breaks it by letters there)
local PIPS, PIP_W, PIP_H, PIP_GAP = 8, 5, 8, 3 -- eight reach NAME_X + 61: inside the name's column on every plate
local PIP_Y = 1                           -- the pips' middle over the bar's bottom edge, clear of the line of text
local TURN_H = 3                          -- the turn bar along the bottom
local CLOCK_LOW = 300                     -- tenths: a seat clock under 30 s turns clockLow

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
  local portrait = Portrait.new(f, PORTRAIT, { badge = true })
  portrait.frame:SetPoint("CENTER", f, "LEFT", 0, 0)
  local name = W.Label(f, "ui", "", 12)
  Theme.setFont(name, "uiBold", 12)
  name:SetPoint("LEFT", f, "LEFT", NAME_X, 0)
  local clock = W.Label(f, "ui", "", 12)
  clock:SetTextColor(Theme.rgb("gold"))
  clock:SetJustifyH("RIGHT")
  clock:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  local note = W.Label(f, "heading", "", 13)
  note:SetJustifyH("CENTER")
  note:SetPoint("RIGHT", f, "RIGHT", -NOTE_RIGHT, 0)
  local bar = f:CreateTexture(nil, "ARTWORK")
  bar:SetColorTexture(Theme.rgb("gold"))
  bar:SetHeight(TURN_H)
  bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  bar:Hide()
  local tricks = {}
  for k = 1, PIPS do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetSize(PIP_W, PIP_H)
    t:SetColorTexture(Theme.rgb("banner"))
    if k == 1 then
      t:SetPoint("LEFT", f, "BOTTOMLEFT", NAME_X, PIP_Y)
    else
      t:SetPoint("LEFT", tricks[k - 1], "RIGHT", PIP_GAP, 0)
    end
    t:Hide()
    tricks[k] = t
  end
  p = { frame = f, edges = edges, portrait = portrait, name = name, note = note, clock = clock, bar = bar, tricks = tricks }
  W.nameTip(f, function() return p.seatName end)
  v.plates[i] = p
  return p
end

-- The seat's hero on the portrait (set again only when he changes, ui/Portrait.lua).
local function hero(p, client, name)
  p.portrait:set(name and Portrait.who(client, name) or nil)
end

-- `n` pips (nil: none, at most PIPS).
local function pips(p, n)
  n = n and math.min(n, PIPS) or 0
  for k = 1, PIPS do p.tricks[k]:SetShown(k <= n) end
end

-- The turn bar as wide as the share of the turn time left (`left` s).
local function fillBar(p, s, left)
  local turn = type(s.turn) == "number" and s.turn > 0 and s.turn or nil
  local w = p.frame:GetWidth()
  if turn then w = w * math.min(left, turn) / turn end
  p.bar:SetWidth(math.max(1, w))
end

-- A view with seatClock(s, seat) (-> tenths | "none" | nil, chess) shows the clock of every seat:
-- ns.ChessModel.clockText, in clockLow under CLOCK_LOW tenths, else gold; "none" is the sign for no
-- limit with no bar; the turn bar only on the plate on turn of a timed game, as wide as the time left of the base.
local function seatClock(p, s, view, seat)
  local t = view.seatClock(s, seat)
  p.clock:SetShown(t ~= nil)
  local number = type(t) == "number"
  local base = s.state and s.state.base
  local bar = number and base and s.state.phase == "play" and s.state.turn == seat
  p.bar:SetShown(bar or false)
  if t == nil then return end
  -- every frame: only what changed is set again; a running clock's text once a whole second
  local secs, low = number and math.ceil(t / 10) or nil, number and t < CLOCK_LOW
  if not number or p.clockSecs ~= secs then
    p.clockSecs = secs
    local text = ns.ChessModel.clockText(number and t or nil)
    if p.clockText ~= text then p.clockText = text; p.clock:SetText(text) end
  end
  if p.clockLow ~= low then p.clockLow = low; p.clock:SetTextColor(Theme.rgb(low and "clockLow" or "gold")) end
  if bar then
    local w = math.max(1, p.frame:GetWidth() * math.min(t, base) / base)
    if p.barWidth ~= w then p.barWidth = w; p.bar:SetWidth(w) end
  end
end

-- The turn clock and the turn bar on the plate of the player on turn (a view with seatClock: on every plate).
local function tick(v, s)
  local view = TableFrame.views[s.game]
  if view and view.seatClock then
    for i = 1, #s.seats do if v.plates[i] then seatClock(v.plates[i], s, view, i) end end
    return
  end
  local left = s:left()
  if not left then return end
  local secs = math.ceil(left)
  local text = L("table.clock", math.floor(secs / 60), secs % 60)
  for i = 1, #v.plates do
    local p = v.plates[i]
    if p.clock:IsShown() then
      p.clock:SetText(text)
      fillBar(p, s, left)
    end
  end
end

-- The note, and the name in what the note leaves: the name ends NOTE_GAP before the note,
-- and the two never meet. The name comes first: it keeps its own width on one line if it
-- can, and NAME_MIN at least (a stack in coins at Холдем). The note shrinks (W.fit, never
-- under W.WRAP_MIN) into what is left; still too wide, it wraps (W.fitWrap: „199g 95s“ on
-- two lines at 9 fit the bar). The name shrinks, then wraps: never cut. The clock keeps its
-- room right of the note (NOTE_RIGHT) while it shows; a plate without a clock gives the note
-- that room too (NOTE_EDGE), so a long name keeps its size off turn. A name that holds the room
-- on one line at 9 but not beside the note gets the bar's upper line and the note its lower one:
-- a name's word (12 letters at most in WoW) is never broken by its letters.
local function widthOf(fs, text, floor)
  W.fit(fs, text, floor and 0 or math.huge, floor)
  return W.textWidth(fs)
end
local function widestWord(fs, text) -- at the font fs has now
  local most = 0
  for word in text:gmatch("%S+") do
    fs:SetText(word)
    most = math.max(most, W.textWidth(fs))
  end
  fs:SetText(text)
  return most
end
-- Two lines in the bar (STACK): the name in the upper, the note in the lower, each at most STACK_SIZE.
local STACK_UP, STACK_DOWN, STACK_SIZE = 6.5, -4, 10
local function capped(fs)
  local path, size, flags = fs:GetFont()
  if size > STACK_SIZE then fs:SetFont(path, STACK_SIZE, flags) end
end
-- The room the sign of no limit („∞“, seatClock "none") takes right of the note: its own, not NOTE_RIGHT.
local function signRoom(p)
  local old = p.clock:GetText(); p.clock:SetText(ns.ChessModel.clockText(nil))
  local room = NOTE_EDGE + W.textWidth(p.clock) + NOTE_GAP; p.clock:SetText(old)
  return math.min(NOTE_RIGHT, room)
end

-- `clocked`: true (a running clock's room), a number (that room: the sign of no limit) or nil.
local function noteAndName(p, w, text, name, clocked)
  local right = type(clocked) == "number" and clocked or clocked and NOTE_RIGHT or NOTE_EDGE
  p.note:ClearAllPoints()
  p.name:ClearAllPoints()
  local room = w - right - NAME_X
  local least = widthOf(p.note, text, W.WRAP_MIN)
  local nameLeast = widthOf(p.name, name, W.WRAP_MIN)
  -- a name that fits the room on one line at 9, but not beside the note: the note goes under it
  if text ~= "" and nameLeast <= room and nameLeast + NOTE_GAP + least > room then
    p.name:SetPoint("LEFT", p.frame, "LEFT", NAME_X, STACK_UP)
    p.note:SetPoint("RIGHT", p.frame, "RIGHT", -right, STACK_DOWN)
    p.note:SetWidth(0)
    W.fitWrap(p.name, name, room)
    capped(p.name)
    if least <= room then W.fit(p.note, text, room, W.WRAP_MIN) else W.fitWrap(p.note, text, room) end
    capped(p.note)
    return
  end
  p.name:SetPoint("LEFT", p.frame, "LEFT", NAME_X, 0)
  p.note:SetPoint("RIGHT", p.frame, "RIGHT", -right, 0)
  local want = math.max(NAME_MIN, math.min(widthOf(p.name, name), room - NOTE_GAP - least))
  local noteW = math.max(room - want - NOTE_GAP, widestWord(p.note, text))
  p.note:SetWidth(0)
  if least <= noteW then
    W.fit(p.note, text, noteW, W.WRAP_MIN)
    noteW = W.textWidth(p.note)
  else
    W.fitWrap(p.note, text, noteW)
  end
  W.fitWrap(p.name, name, math.max(NAME_LEAST, room - noteW - NOTE_GAP))
end

-- Places the plates on the grid of ns.HallLayout.plates, or around the felt
-- (ns.HallLayout.ring) for a ring view -> the number of rows.
local function render(v, s, client)
  local n, view = #s.seats, TableFrame.views[s.game]
  local spots, rows
  if view and view.plateSpots then
    spots, rows = view.plateSpots(s, v.areaW, v.areaH)
  elseif view and view.ring then
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
    p.seatName = name or nil
    if name then
      p.name:SetTextColor(W.nameColor(client, name))
    else
      p.name:SetTextColor(Theme.rgb("inkDim"))
    end
    hero(p, client, name or nil)
    local onTurn = turn == i
    local clocked -- the clock shows on this plate: every seat's in a game of seat clocks, else the one on turn in a timed game
    local c = view and view.seatClock and view.seatClock(s, i) -- "none": only the sign of no limit, in its own room
    if view and view.seatClock then clocked = c == "none" and signRoom(p) or c ~= nil else clocked = onTurn and s.deadline ~= nil end
    noteAndName(p, spot[3], view and view.seatNote and view.seatNote(s, i) or "", name and W.short(name, s.seats) or L("table.free"), clocked)
    p.portrait:turn(onTurn and name ~= false and name ~= nil) -- an empty chair never glows
    if view and view.seatClock then
      seatClock(p, s, view, i)
    else
      p.clockText, p.clockSecs, p.clockLow, p.barWidth = nil, nil, nil, nil -- a seatClock view sets them again
      local timed = onTurn and s.deadline ~= nil
      p.clock:SetShown(timed)
      p.bar:SetShown(timed)
      if timed then fillBar(p, s, s:left() or 0) end
    end
    p.edges.setColor(Theme.rgb(onTurn and "gold" or "brass"))
    pips(p, view and view.seatTricks and view.seatTricks(s, i))
    p.frame:Show()
  end
  for i = n + 1, #v.plates do v.plates[i].frame:Hide() end
  return rows
end

TableFrame.plates = { render = render, tick = tick }
