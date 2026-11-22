local _, ns = ...

-- The stake at the table, the panels of ui/:
-- * The question before I sit at a staked table (StakePanels.ask, from a chair
--   or a row of the hall): „Маса със залог“, what I owe if I lose (Death Roll:
--   to each of the others, the most it can come to: ns.Stake.worst) and what a
--   leave costs; „Приемам и сядам“ sits with that stake (client:sit), „Отказ“
--   sends nothing. The same question keeps a seat my client was asked about
--   after a crash or a fresh login ("stakeAsk"): its yes is client:acceptStake;
--   unanswered, the game's end stands me up (core/Stake.lua) and the question goes.
-- * The bill „Сметката“ (StakePanels.bill, from the table frame's render), over
--   the lower part of the felt once the staked game I played is over: for each
--   outcome of that game my client noted (the "result" and the "forfeit"s of
--   it, client.stakes' notes), why a forfeit was one (the note's why: „idle“,
--   else a leave), then who owes whom, the names in class colour, each row
--   marked „чака потвърждение“ or „оспорен“ as the ledger has it; „Към
--   залата“ and „Реванш на същата маса“ (Морски шах: the engine's rematch;
--   Death Roll: the host's next game, none for a guest). StakePanels.shown says
--   whether it is up, so the game views hide their own result line.
local Theme, W, L = ns.Theme, ns.W, ns.L
local money = ns.Util.money

local P = {
  shown = false,  -- the bill is up (read by the game views)
  question = nil, -- {kind = "sit" | "keep", tid, seat, sk, game}: the question shown
}
ns.StakePanels = P

local ASK_W, ASK_H = 380, 200
local BILL_W, BILL_BASE, BILL_ROW = 360, 48, 22

local function first(client, name) return W.colored(client, name, W.firstWord(name)) end

---------------------------------------------------------------------------
-- The question
---------------------------------------------------------------------------

-- What I owe if I lose at a table of game `game`, stake `sk`.
local function askText(game, sk)
  local worst = ns.Stake.worst(game, sk)
  if worst > sk then return L("stake.ask.each", money(sk), money(sk), money(worst)) end
  return L("stake.ask.text", money(sk), money(sk))
end

local function buildAsk()
  local f = CreateFrame("Frame", nil, UIParent)
  P.askFrame = f
  f:SetSize(ASK_W, ASK_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  local wood = W.tile(f, Theme.tex.wood, Theme.texSize.wood, ASK_W - 8, ASK_H - 8)
  wood:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  wood:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  W.nine(f, Theme.tex.frame, Theme.texSize.frame, 12, 12, "BORDER", true)
  P.askTitle = W.Label(f, "heading", L("stake.ask.title"), 17)
  P.askTitle:SetJustifyH("CENTER")
  P.askTitle:SetPoint("TOP", f, "TOP", 0, -20)
  P.askText = W.Label(f, "ui", "", 13)
  P.askText:SetWidth(ASK_W - 48)
  P.askText:SetWordWrap(true)
  P.askText:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -52)
  P.askLeave = W.Label(f, "ui", L("stake.ask.leave"), 12)
  P.askLeave:SetTextColor(Theme.rgb("gold"))
  P.askLeave:SetWidth(ASK_W - 48)
  P.askLeave:SetWordWrap(true)
  P.askLeave:SetPoint("TOPLEFT", P.askText, "BOTTOMLEFT", 0, -10)
  P.askYes = W.Button(f, L("stake.ask.yes"), function() P.answer(true) end)
  P.askYes:SetSize(170, 28)
  P.askYes:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)
  P.askNo = W.Button(f, L("stake.ask.no"), function() P.answer(false) end)
  P.askNo:SetSize(110, 28)
  P.askNo:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
  f:Hide()
end

local function showAsk(q)
  if not P.askFrame then buildAsk() end
  P.question = q
  P.askText:SetText(askText(q.game, q.sk))
  P.askFrame:Show()
  P.askFrame:Raise()
end

local function hideAsk()
  P.question = nil
  if P.askFrame then P.askFrame:Hide() end
end

-- The question before sitting in seat `seat` of the staked table `rec` (a lobby record).
function P.ask(rec, seat)
  if not (rec and rec.stake ~= nil and seat) then return end
  showAsk({ kind = "sit", tid = rec.tid, seat = seat, sk = rec.stake, game = rec.game })
end

-- „Приемам и сядам“ (yes) or „Отказ“.
function P.answer(yes)
  local q, client = P.question, ns.client
  hideAsk()
  if not (yes and q and client) then return end
  if q.kind == "keep" then
    client:acceptStake()
  else
    client:sit(q.tid, q.seat, q.sk)
  end
end

---------------------------------------------------------------------------
-- The bill
---------------------------------------------------------------------------

-- The outcomes of my staked table, in the order heard: {tid, {gid, no}...};
-- no: the table's s.stakeNo then (the game they belong to, core/Stakes.lua).
local heard = {}

local function hear(tid, q)
  local s = ns.client and ns.client.session
  if not (s and s.tid == tid and s.stake ~= nil and type(q) == "number") then return end
  if heard.tid ~= tid then heard = { tid = tid } end
  local gid = tid .. "/" .. q
  for _, h in ipairs(heard) do if h.gid == gid then return end end
  heard[#heard + 1] = { gid = gid, no = s.stakeNo }
end

-- My notes of the staked game just over at my table s, in the order heard ->
-- {note, ...} | nil (a game still running, a fun table, no note of mine).
function P.notes(client, s)
  if s.stake == nil or not client.stakes or heard.tid ~= s.tid or ns.Stakes.running(s) then return nil end
  local seen, out = client.stakes:seen(), {}
  for _, h in ipairs(heard) do
    local n = seen[h.gid]
    if h.no == s.stakeNo and type(n) == "table" and type(n.pairs) == "table" then out[#out + 1] = n end
  end
  return #out > 0 and out or nil
end

-- The rows of a note: every pair as the ledger has it now -> {{f, t, c,
-- status}} (status "pending" | "confirmed" | "contested"; a debt my ledger
-- does not hold yet is pending at the note's amount).
function P.billRows(client, note)
  local debts, out = {}, {}
  if client.ledger then
    for _, d in ipairs(ns.LedgerView.of(client.ledger).debts) do debts[d.key] = d end
  end
  local gid = tostring(note.tid) .. "/" .. tostring(note.q)
  for _, p in ipairs(note.pairs or {}) do
    local d = debts[gid .. "|" .. p.f .. "|" .. p.t]
    out[#out + 1] = { f = p.f, t = p.t, c = d and d.c or p.c, status = d and d.status or "pending" }
  end
  return out
end

local MARK = { pending = { "bill.pending", "inkDim" }, contested = { "bill.contested", "red" } }

local function lineWidget(b, i)
  local line = b.lines[i]
  if line then return line end
  local y = -24 - (i - 1) * BILL_ROW
  local text = W.Label(b, "ui", "", 12)
  text:SetWordWrap(false)
  text:SetPoint("TOPLEFT", b, "TOPLEFT", 14, y)
  local mark = W.Label(b, "dim", "", 11)
  mark:SetJustifyH("RIGHT")
  mark:SetPoint("TOPRIGHT", b, "TOPRIGHT", -14, y - 1)
  line = { text = text, mark = mark }
  b.lines[i] = line
  return line
end

-- One line of the bill: `text`, and a row's mark for `status` (nil: a reason line).
local function setLine(b, i, text, status)
  local line, mark = lineWidget(b, i), MARK[status]
  line.text:SetWidth(BILL_W - 28 - (status and 112 or 0))
  line.text:SetText(text)
  line.text:Show()
  line.mark:SetText(mark and L(mark[1]) or "")
  if mark then line.mark:SetTextColor(Theme.rgb(mark[2])) end
  line.mark:SetShown(mark ~= nil)
end

local function buildBill(v)
  local b = W.Panel(v.area)
  b.fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.92)
  b:SetSize(BILL_W, BILL_BASE + BILL_ROW)
  b:SetPoint("BOTTOM", v.area, "BOTTOM", 0, 12)
  b:SetFrameLevel(v.area:GetFrameLevel() + 12)
  b:EnableMouse(true)
  b.title = W.Label(b, "heading", L("bill.title"), 14)
  b.title:SetJustifyH("CENTER")
  b.title:SetPoint("TOP", b, "TOP", 0, -6)
  b.lines = {}
  b.toHall = W.Button(b, L("table.toHall"), function() ns.TableFrame.stand() end, true)
  b.toHall:SetSize(110, 20)
  b.toHall:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 10, 4)
  b.rematch = W.Button(b, L("bill.rematch"), function() P.rematch() end, true)
  b.rematch:SetSize(180, 20)
  b.rematch:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -10, 4)
  b.waiting = W.Label(b, "dim", "", 12)
  b.waiting:SetJustifyH("RIGHT")
  b.waiting:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -12, 8)
  b:Hide()
  v.bill = b
end

-- Морски шах: my „Реванш“ (rematch, asked: whom I wait for); Death Roll: the
-- host's next game; nothing for a Death Roll guest or a match nobody can replay.
local function rematchState(s, client)
  local st, me = s.state, s.mySeat
  if s.game ~= "ttt" then return s.role == "host" and "start" or nil end
  if not (st and s.status == "live" and st.phase == "match" and (me == 1 or me == 2) and s.seats[3 - me]) then return nil end
  if st.rematch and st.rematch[me] then return "asked", s.seats[3 - me] end
  return "ask"
end

function P.rematch()
  local client = ns.client
  local s = client and client.session
  if not s then return end
  local what = rematchState(s, client)
  if what == "ask" then
    client:act({ k = "rematch" })
  elseif what == "start" then
    ns.TableFrame.startGame()
  end
end

-- Draws the bill over the felt of the table frame `v` while P.notes has one
-- for my table s, else hides it; sets P.shown.
function P.bill(v, s)
  local client = ns.client
  local notes = client and P.notes(client, s)
  P.shown = notes ~= nil
  if not notes then
    if v.bill then v.bill:Hide() end
    return
  end
  if not v.bill then buildBill(v) end
  local b, n = v.bill, 0
  for _, note in ipairs(notes) do
    local leaver = note.why ~= "lost" and note.pairs[1] and note.pairs[1].f
    if leaver then
      n = n + 1
      setLine(b, n, L(note.why == "idle" and "bill.idle" or "bill.left", first(client, leaver)), nil)
    end
    for _, r in ipairs(P.billRows(client, note)) do
      n = n + 1
      setLine(b, n, L("bill.row", first(client, r.f), first(client, r.t), money(r.c)), r.status)
    end
  end
  for i = n + 1, #b.lines do b.lines[i].text:Hide(); b.lines[i].mark:Hide() end
  b:SetHeight(BILL_BASE + BILL_ROW * n)
  local what, other = rematchState(s, client)
  b.rematch:SetShown(what == "ask" or what == "start")
  b.waiting:SetText(what == "asked" and L("ttt.waitingFor", W.colored(client, other)) or "")
  b.waiting:SetShown(what == "asked")
  b:Show()
end

ns.ready(function(client)
  client:on("result", function(r) if r.sk ~= nil then hear(r.tid, r.q) end end)
  client:on("forfeit", function(f) if f.sk ~= nil then hear(f.tid, f.q) end end)
  client:on("ledger", function() if P.shown then ns.TableFrame.refresh() end end)
  -- Drawn on the next frame (a drawing error never breaks Member.adopt), while the seat is still asked.
  client:on("stakeAsk", function(tid, sk)
    C_Timer.After(0, function()
      local s = client.session
      if not (s and s.tid == tid and s.stakeAsk and s.stake == sk) then return end
      showAsk({ kind = "keep", tid = tid, sk = sk, game = s.game })
    end)
  end)
  client:on("session", function(s)
    local q = P.question
    if q and q.kind == "keep" and not (s and s.tid == q.tid and s.stakeAsk) then hideAsk() end
  end)
end)
