local _, ns = ...

-- The invite toast (mockup 02), top centre of the screen: „Покана за <игра>“,
-- „<домакин> те кани на <игра>“ (the host in class color), „Приемам“ /
-- „Не сега“ / „Не ме безпокой 30 мин“ and a bar running down to the
-- invitation's `expires`; for a staked table a line „Залог: 5g“ under the
-- text (the toast STAKE_H taller). A soft sound on show; hidden on "inviteGone". Only
-- invitations that need an answer reach it: core/Invites declines the others
-- by itself (combat, instance, busy, snooze).
--
-- A „Приемам“ that is refused (the table is gone or full, or its record has not
-- arrived yet) shows the refusal on the toast for NOTICE_SECONDS instead. At a
-- staked table „Приемам“ first asks the stake question (ns.StakePanels.askInvite);
-- its answer comes back through InviteToast.acceptStaked.
--
-- Host side: each "inviteAnswer" becomes one line on the table frame (or in the
-- hall footer): accepted, declined, or why the addon declined for them.
local Theme, W, L, C = ns.Theme, ns.W, ns.L, ns.Const

local InviteToast = {
  WIDTH = 350, HEIGHT = 124, STAKE_H = 18,
  frame = nil,     -- built on the first invitation
  tid = nil,       -- the invitation shown
  accepting = nil, -- { tid, untilTime }: a „Приемам“ whose refusal is still shown here
}
InviteToast.BAR_W = InviteToast.WIDTH - 28
ns.InviteToast = InviteToast

local PAD = 14
local NOTICE_SECONDS = 5
local ACCEPT_WATCH = 10 -- seconds after „Приемам“ during which a refusal still lands on the toast
local AUTO = { combat = true, instance = true, busy = true, snooze = true, timeout = true }

local function now() return ns.client.env.now() end

-- The bar: the share of the invitation's time still left.
function InviteToast.tick()
  local t = InviteToast
  if not t.expires then return end
  local share = math.max(0, math.min(1, (t.expires - now()) / C.INVITE_SECONDS))
  t.bar:SetWidth(math.max(1, share * InviteToast.BAR_W))
end

local function build()
  local f = CreateFrame("Frame", nil, UIParent)
  InviteToast.frame = f
  f:SetSize(InviteToast.WIDTH, InviteToast.HEIGHT)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  InviteToast.border = W.chrome(f, InviteToast.WIDTH, InviteToast.HEIGHT).frame

  local title = W.Label(f, "heading", "", 15)
  title:SetTextColor(Theme.rgb("brassLight"))
  title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  InviteToast.title = title
  local text = W.Label(f, "ui", "", 13)
  text:SetWidth(InviteToast.WIDTH - 2 * PAD)
  text:SetWordWrap(true)
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  InviteToast.text = text
  local stake = W.Label(f, "ui", "", 13)
  stake:SetTextColor(Theme.rgb("gold"))
  stake:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
  stake:Hide()
  InviteToast.stake = stake

  local accept = W.Button(f, L("invite.accept"), function() InviteToast.answer("yes") end, true)
  accept:SetSize(84, 22)
  accept:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD + 8)
  local notNow = W.Button(f, L("invite.notNow"), function() InviteToast.answer("no") end, true)
  notNow:SetSize(84, 22)
  notNow:SetPoint("LEFT", accept, "RIGHT", 6, 0)
  local snooze = W.Button(f, L("invite.snooze"), function() InviteToast.answer("snooze") end, true)
  snooze:SetSize(InviteToast.WIDTH - 2 * PAD - 2 * 84 - 12, 22)
  snooze:SetPoint("LEFT", notNow, "RIGHT", 6, 0)
  InviteToast.accept, InviteToast.notNow, InviteToast.snooze = accept, notNow, snooze

  local track = f:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(0, 0, 0, 0.4)
  track:SetSize(InviteToast.BAR_W, 3)
  track:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD - 2)
  local bar = f:CreateTexture(nil, "OVERLAY")
  bar:SetColorTexture(Theme.color.brassLight[1], Theme.color.brassLight[2], Theme.color.brassLight[3], 1)
  bar:SetSize(InviteToast.BAR_W, 3)
  bar:SetPoint("LEFT", track, "LEFT", 0, 0)
  InviteToast.track, InviteToast.bar = track, bar

  f:SetScript("OnUpdate", InviteToast.tick)
  f:Hide()
end

local function setButtons(on)
  InviteToast.accept:SetShown(on)
  InviteToast.notNow:SetShown(on)
  InviteToast.snooze:SetShown(on)
  InviteToast.track:SetShown(on)
  InviteToast.bar:SetShown(on)
end

function InviteToast.hide()
  local t = InviteToast
  t.tid, t.expires = nil, nil
  if t.noticeTimer then t.noticeTimer:Cancel(); t.noticeTimer = nil end
  if t.frame then t.frame:Hide() end
end

-- inv: the "invite" event's table {tid, game, host, seats, expires, stake}.
function InviteToast.show(inv)
  if not InviteToast.frame then build() end
  InviteToast.hide()
  local t, game = InviteToast, W.gameName(inv.game)
  t.tid, t.expires, t.game, t.inv = inv.tid, inv.expires, game, inv
  t.title:SetText(L("invite.title", game))
  t.text:SetText(L("invite.text", W.colored(ns.client, inv.host), game))
  local blinds = inv.stake ~= nil and ns.StakePanels.blinds(inv.game, inv.stake) -- a cash table: its blinds
  t.stake:SetText(blinds and L("table.blinds", blinds) or inv.stake ~= nil and L("invite.stake", ns.Util.money(inv.stake)) or "")
  t.stake:SetShown(inv.stake ~= nil)
  t.frame:SetHeight(t.HEIGHT + (inv.stake ~= nil and t.STAKE_H or 0))
  setButtons(true)
  t.tick()
  t.frame:Show()
  t.frame:Raise()
  local sound = SOUNDKIT and SOUNDKIT.TELL_MESSAGE -- absent on some clients
  if sound then PlaySound(sound, "SFX") end
end

-- A line on the toast in place of the invitation, for NOTICE_SECONDS.
local function notice(text)
  local t = InviteToast
  if not t.frame then return end
  t.hide()
  t.title:SetText(L("invite.title", t.game or ""))
  t.text:SetText(text)
  t.stake:Hide()
  setButtons(false)
  t.frame:Show()
  t.noticeTimer = C_Timer.NewTimer(NOTICE_SECONDS, function()
    t.noticeTimer = nil
    t.frame:Hide()
  end)
end

-- "yes" | "no" | "snooze" for the invitation shown. A "yes" to a staked
-- table asks the stake question first.
function InviteToast.answer(kind)
  local t, client = InviteToast, ns.client
  local tid, inv = t.tid, t.inv
  t.hide()
  if not tid or not client then return end
  if kind == "yes" and inv and inv.tid == tid and inv.stake ~= nil then return ns.StakePanels.askInvite(inv) end
  if kind == "yes" then t.accepting = { tid = tid, untilTime = now() + ACCEPT_WATCH } end
  client:answerInvite(tid, kind)
end

-- The answer to the stake question of an invitation to table tid (stake sk):
-- yes accepts it (expired meanwhile: I sit at that stake, as from a chair),
-- else it is declined while it still stands.
function InviteToast.acceptStaked(tid, sk, yes)
  local client = ns.client
  if not client then return end
  local r = client.invites.received
  local open = r ~= nil and r.tid == tid
  if not yes then
    if open then client:answerInvite(tid, "no") end
    return
  end
  InviteToast.accepting = { tid = tid, untilTime = now() + ACCEPT_WATCH }
  if open then return client:answerInvite(tid, "yes") end
  local rec = client.lobby:get(tid)
  local seat
  for i = 1, rec and #rec.seats or 0 do
    if rec.seats[i] == false then seat = seat or i end
  end
  if not seat then return client.events:emit("refused", tid, rec and "taken" or "gone") end
  client:sit(tid, seat, sk)
end

local function refused(tid, why)
  local a = InviteToast.accepting
  if not a or a.tid ~= tid then return end
  InviteToast.accepting = nil
  if now() <= a.untilTime then notice(L("refused." .. tostring(why))) end
end

-- The host's line about an answer to its invitation.
function InviteToast.answerText(name, a, why)
  local who = W.colored(ns.client, name)
  if a == "yes" then return L("invite.accepted", who) end
  if a == "auto" and AUTO[why] then return L("invite.auto." .. why, who) end
  return L("invite.declined", who)
end

local function answered(name, a, why)
  local text = InviteToast.answerText(name, a, why)
  if not ns.TableFrame.say(text) then ns.Hall.say(text) end
end

-- The toast is drawn on the next frame, so a drawing error never breaks the
-- protocol code that emitted "invite"; an invitation gone by then is not shown.
local incoming

ns.ready(function(client)
  client:on("invite", function(inv)
    incoming = inv
    C_Timer.After(0, function()
      if incoming ~= inv then return end
      incoming = nil
      InviteToast.show(inv)
    end)
  end)
  client:on("inviteGone", function(tid)
    if incoming and incoming.tid == tid then incoming = nil end
    if tid == InviteToast.tid then InviteToast.hide() end
  end)
  client:on("refused", refused)
  client:on("session", function(s)
    local a = InviteToast.accepting
    if a and s and s.tid == a.tid then InviteToast.accepting = nil end
  end)
  client:on("inviteAnswer", answered)
end)
