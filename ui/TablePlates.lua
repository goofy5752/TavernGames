local _, ns = ...

-- The plates of the table frame, split out of ui/TableFrame.lua: one per seat,
-- on the grid of ns.HallLayout.plates, or around the felt (ns.HallLayout.ring)
-- for a ring view. A plate is a WoW unit frame (spec 5.5, mockup 08) in a bar
-- of 26 px: on the bar's left end the seat's hero (ui/Portrait.lua, 30 px, with
-- the class badge; the empty chair on a free seat), its ring gold and glowing
-- while the seat is on turn; the name 40 px in, in class colour; right of the
-- name a pip for every trick the seat took (the view's seatTricks, at most
-- eight); the game's mark for the seat (seatNote); on the plate on turn a gold
-- edge, the turn clock and a 3 px gold line along the bar's bottom as wide as
-- the share of the turn time left. A portrait is set only when the seat's hero
-- changes. TableFrame.plates is what the frame calls.
local TableFrame = ns.TableFrame
local Theme, W, L, Portrait = ns.Theme, ns.W, ns.L, ns.Portrait

local PLATE_W, PLATE_H = 190, 26          -- plate size before ns.HallLayout.plates sets the width
local PORTRAIT, NAME_X = 30, 40           -- the hero centred on the bar's left end; the name after it
local PLATE_NAME_INSET = NAME_X + 64      -- the plate width the portrait and the clock/note keep from the name
local PIPS, PIP_W, PIP_H, PIP_GAP = 8, 5, 8, 3
local TURN_H = 3                          -- the turn bar along the bottom

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
  name:SetWordWrap(false)
  name:SetWidth(PLATE_W - PLATE_NAME_INSET)
  name:SetPoint("LEFT", f, "LEFT", NAME_X, 0)
  local clock = W.Label(f, "ui", "", 12)
  clock:SetTextColor(Theme.rgb("gold"))
  clock:SetJustifyH("RIGHT")
  clock:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  local note = W.Label(f, "heading", "", 13)
  note:SetJustifyH("CENTER")
  note:SetPoint("RIGHT", f, "RIGHT", -42, 0)
  local bar = f:CreateTexture(nil, "ARTWORK")
  bar:SetColorTexture(Theme.rgb("gold"))
  bar:SetHeight(TURN_H)
  bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  bar:Hide()
  local tricks = {}
  for k = 1, PIPS do
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetSize(PIP_W, PIP_H)
    t:SetColorTexture(Theme.rgb("banner"))
    if k > 1 then t:SetPoint("LEFT", tricks[k - 1], "RIGHT", PIP_GAP, 0) end
    t:Hide()
    tricks[k] = t
  end
  p = { frame = f, edges = edges, portrait = portrait, name = name, note = note, clock = clock, bar = bar, tricks = tricks }
  v.plates[i] = p
  return p
end

-- The seat's hero on the portrait, set again only when who sits there (or what
-- the client knows of him) changes.
local function hero(p, client, name)
  local who = name and Portrait.who(client, name) or nil
  local key = who and table.concat({ who.name, tostring(who.cls), tostring(who.race), tostring(who.sex), tostring(who.unit) }, "\1") or ""
  if p.heroKey == key then return end
  p.heroKey = key
  p.portrait:set(who)
end

-- `n` pips (nil: none, at most PIPS) right after the name's text.
local function pips(p, n)
  n = n and math.min(n, PIPS) or 0
  if n > 0 then
    local first = p.tricks[1]
    first:ClearAllPoints()
    first:SetPoint("LEFT", p.name, "LEFT", math.min(p.name:GetStringWidth(), p.name:GetWidth()) + 4, 0)
  end
  for k = 1, PIPS do p.tricks[k]:SetShown(k <= n) end
end

-- The turn clock and the turn bar on the plate of the player on turn.
local function tick(v, s)
  local left = s:left()
  if not left then return end
  local secs = math.ceil(left)
  local text = L("table.clock", math.floor(secs / 60), secs % 60)
  local turn = type(s.turn) == "number" and s.turn > 0 and s.turn or nil
  for i = 1, #v.plates do
    local p = v.plates[i]
    if p.clock:IsShown() then
      p.clock:SetText(text)
      local w = p.frame:GetWidth()
      if turn then w = w * math.min(left, turn) / turn end
      p.bar:SetWidth(math.max(1, w))
    end
  end
end

-- Places the plates on the grid of ns.HallLayout.plates, or around the felt
-- (ns.HallLayout.ring) for a ring view -> the number of rows.
local function render(v, s, client)
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
    else
      p.name:SetText(L("table.free"))
      p.name:SetTextColor(Theme.rgb("inkDim"))
    end
    hero(p, client, name or nil)
    p.note:SetText(view and view.seatNote and view.seatNote(s, i) or "")
    local onTurn = turn == i
    p.portrait:turn(onTurn and name ~= false and name ~= nil) -- an empty chair never glows
    p.clock:SetShown(onTurn and s.deadline ~= nil)
    p.bar:SetShown(onTurn and s.deadline ~= nil)
    p.edges.setColor(Theme.rgb(onTurn and "gold" or "brass"))
    pips(p, view and view.seatTricks and view.seatTricks(s, i))
    p.frame:Show()
  end
  for i = n + 1, #v.plates do v.plates[i].frame:Hide() end
  return rows
end

TableFrame.plates = { render = render, tick = tick }
