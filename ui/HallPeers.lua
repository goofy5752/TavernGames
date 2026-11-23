local _, ns = ...

-- The lower part of the hall's right column (below „Сметки“, ui/Accounts.lua),
-- „В кръчмата сега“: every guild member with the
-- addon, in class color, and where they are (in the hall, at a table, watching).
-- A click on a name offers „Покани“ while I host a table with a free seat
-- (Hall.clickPeer, Hall.invite). Hall is looked up at call time: this file
-- loads before ui/Hall.lua.
local Theme, W, L, Util = ns.Theme, ns.W, ns.L, ns.Util

local HallPeers = {}
ns.HallPeers = HallPeers

local PEER_H = 26

-- May I invite `name` to my table now: I host with a free seat, the name is
-- not seated there, and its client speaks our protocol?
function HallPeers.canInviteName(client, name)
  local s = ns.Hall.hostingWithFreeSeat(client)
  if not s or Util.contains(s.seats, name) then return false end
  local p = client.presence:get(name)
  return p ~= nil and not p.incompatible
end

local function peerWidget(v, i)
  local r = v.peers[i]
  if r then return r end
  local content = v.peerScroll.content
  local b = CreateFrame("Button", nil, content)
  b:SetSize(v.peerW, PEER_H)
  b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * PEER_H)
  b:RegisterForClicks("LeftButtonUp")
  local hl = b:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints(b)
  hl:SetColorTexture(Theme.color.brassLight[1], Theme.color.brassLight[2], Theme.color.brassLight[3], 0.08)
  hl:Hide()
  b:SetScript("OnEnter", function() hl:Show() end)
  b:SetScript("OnLeave", function() hl:Hide() end)
  local name = W.Label(b, "ui", "", 12)
  name:SetWidth(v.peerW - 100)
  name:SetWordWrap(false)
  name:SetPoint("LEFT", b, "LEFT", 28, 0)
  local portrait = ns.Portrait.new(b, 22)
  portrait.frame:SetPoint("LEFT", b, "LEFT", 2, 0)
  local status = W.Label(b, "dim", "")
  status:SetJustifyH("RIGHT")
  status:SetPoint("RIGHT", b, "RIGHT", -2, 0)
  r = { frame = b, name = name, status = status, portrait = portrait }
  local invite = W.Button(b, L("hall.invite"), function() ns.Hall.invite(r.peerName) end, true)
  invite:SetSize(64, 18)
  invite:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  invite:Hide()
  r.invite = invite
  b:SetScript("OnClick", function() ns.Hall.clickPeer(r) end)
  v.peers[i] = r
  return r
end

local function whereIs(client, p, byTid)
  if p.incompatible then return L("peers.incompatible") end
  local rec = p.at and byTid[p.at]
  if not rec then return L("peers.hall") end
  if Util.contains(rec.seats, p.name) then
    return L("peers.at", W.colored(client, rec.host, W.firstWord(rec.host)))
  end
  return L("peers.watching")
end

-- Fills the column from the presence list (empty without a client).
function HallPeers.render(v, client)
  local Hall = ns.Hall
  local peers, byTid = {}, {}
  if client then
    peers = client.presence:list()
    local recs = client.lobby:tables()
    for i = 1, #recs do byTid[recs[i].tid] = recs[i] end
  end
  local selectedListed = false
  for i, p in ipairs(peers) do
    local r = peerWidget(v, i)
    r.peerName = p.name
    r.name:SetText(p.name)
    local who = ns.Portrait.who(client, p.name)
    local key = table.concat({ p.name, tostring(who.cls), tostring(who.race), tostring(who.sex), tostring(who.unit) }, "|")
    if r.shown ~= key then r.shown = key; r.portrait:set(who) end
    r.name:SetTextColor(ns.classColor(p.cls))
    r.status:SetText(whereIs(client, p, byTid))
    local offer = Hall.selected == p.name and HallPeers.canInviteName(client, p.name)
    if offer then selectedListed = true end
    r.invite:SetShown(offer)
    r.status:SetShown(not offer)
    r.frame:Show()
  end
  for i = #peers + 1, #v.peers do v.peers[i].frame:Hide() end
  if not selectedListed then Hall.selected = nil end
  v.peerScroll:setContentHeight(#peers * PEER_H)
  v.peerEmpty:SetShown(#peers == 0)
end

-- The column's panel at (x, y below the top: under „Сметки“) on `page`, h high (Hall.RIGHT_W wide).
function HallPeers.build(v, page, x, y, h)
  local width = ns.Hall.RIGHT_W
  local right = W.Panel(page)
  right:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
  right:SetSize(width, h)
  v.peerPanel = right
  W.Label(right, "heading", L("peers.title")):SetPoint("TOPLEFT", right, "TOPLEFT", 10, -10)
  local scroll = W.Scroll(right)
  scroll:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -32)
  scroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -8, 8)
  v.peerW = width - 16 - 6
  scroll.content:SetWidth(v.peerW)
  v.peerScroll = scroll
  v.peerEmpty = W.Label(right, "dim", L("peers.empty"), 12)
  v.peerEmpty:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -34)
end
