local _, ns = ...

-- The tavern sign in the middle of the hall's header row: the faction crest on
-- each side of the guild's name (heading font, goldHi), and a small dim note
-- „само за гилдията“ after it, on a plate in the skin's banner colour with a
-- brass edge. It is centred on the header and never reaches the title at the
-- left or the hint at the right: the name shrinks (W.fit) and, at its least,
-- is cut at its column; when even that leaves no room the note goes first.
-- Hidden without a guild or while its name is not known (Adapter.guildName).
-- Hover: the name and who may see the tables. Hall.render calls HallSign.render.
local Theme, W, L = ns.Theme, ns.W, ns.L

local HallSign = {}
ns.HallSign = HallSign

local CREST, PAD, GAP, NOTE_GAP, SIGN_H = 18, 8, 6, 10, 24
local SIDE = 12   -- clear space kept to the title and to the hint
local NAME_FLOOR = 10

function HallSign.build(v, centre, top)
  local f = CreateFrame("Frame", nil, centre)
  f:SetHeight(SIGN_H)
  f:SetPoint("CENTER", centre, "TOP", 0, -top / 2)
  f:EnableMouse(true)
  f.plate = f:CreateTexture(nil, "BACKGROUND")
  f.plate:SetAllPoints(f)
  f.plate:SetColorTexture(Theme.rgb("banner"))
  f.plate:SetAlpha(0.85)
  f.edges = W.edges(f, 1)
  f.edges.setColor(Theme.rgb("brass"))
  f.crestL, f.crestR = W.crest(f, CREST), W.crest(f, CREST)
  f.name = W.Label(f, "heading", "", 15)
  f.name:SetTextColor(Theme.rgb("goldHi"))
  f.name:SetWordWrap(false)
  f.note = W.Label(f, "dim", L("hall.guild.note"), 11)
  f.crestL:SetPoint("LEFT", f, "LEFT", PAD, 0)
  f.name:SetPoint("LEFT", f.crestL, "RIGHT", GAP, 0)
  f.crestR:SetPoint("LEFT", f.name, "RIGHT", GAP, 0)
  f.note:SetPoint("LEFT", f.crestR, "RIGHT", NOTE_GAP, 0)
  W.tooltip(f, function(tip)
    tip:SetText(f.guild or "", Theme.rgb("goldHi"))
    tip:AddLine(L("hall.guild.tip"), Theme.rgb("inkDim"), true)
  end)
  f:Hide()
  v.sign = f
end

-- Redraws the sign for the guild's name now.
function HallSign.render(v)
  local f = v.sign
  local name = not ns.noGuild and ns.Adapter and ns.Adapter.guildName() or nil
  f.guild = name
  f:SetShown(name ~= nil)
  if not name then return end
  local avail = v.centreW - 2 * (10 + math.max(W.textWidth(v.title), W.textWidth(v.hint)) + SIDE)
  local fixed = 2 * PAD + 2 * CREST + 2 * GAP
  local noteW = NOTE_GAP + W.textWidth(f.note)
  f.note:SetShown(true)
  f.name:SetWidth(0)
  W.fit(f.name, name, avail - fixed - noteW, NAME_FLOOR)
  if W.textWidth(f.name) > avail - fixed - noteW then -- no room for the note: the name has it
    f.note:Hide()
    noteW = 0
    f.name:SetWidth(0)
    W.fit(f.name, name, avail - fixed, NAME_FLOOR)
  end
  local nameW = math.min(W.textWidth(f.name), avail - fixed - noteW)
  f.name:SetWidth(nameW)
  f:SetWidth(fixed + nameW + noteW)
end
