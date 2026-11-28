local _, ns = ...

-- The stake at the table, the panels of ui/:
-- * The question before I sit at a staked table (StakePanels.ask, from a chair
--   or a row of the hall): „Маса със залог“, what I owe if I lose (Death Roll:
--   to each of the others, the most it can come to: ns.Stake.worst; a team
--   game: one opponent, and both when I leave) and what a leave costs; at a
--   card table (an engine with `view`) a warning under it, the frame WARN_H
--   taller: the dealer's client knows the deck of its own deal (residual S1);
--   „Приемам и сядам“ sits with that stake (client:sit), „Отказ“
--   sends nothing (a sit question goes when its table leaves the hall). An
--   invitation to a staked table asks it too (StakePanels.askInvite, from the
--   toast's „Приемам“): yes accepts the invitation (ns.InviteToast.acceptStaked),
--   „Отказ“ declines it. The same question keeps a seat my client was asked about
--   after a crash or a fresh login ("stakeAsk"): its yes is client:acceptStake;
--   unanswered, the game's end stands me up (core/Stake.lua) and the question
--   goes. No other question replaces that one while it is open; an
--   invitation's waits and is asked right after it.
-- * The bill „Сметката“ (StakePanels.bill, from the table frame's render), a
--   strip at the bottom of the felt (BILL_W wide, BILL_TOP + BILL_ROW per line,
--   BILL_Y above the felt's bottom, at most BILL_LINES lines, the last of them
--   „… и още N“ when more would come: below the bottom row of the Морски шах
--   board and the Death Roll ladder) once the staked game I played is over: for each
--   outcome of that game my client noted (the "result" and the "forfeit"s of
--   it, client.stakes' notes), why a forfeit was one (the note's why: „idle“,
--   else a leave; a team game: the leaver pays both opponents), then who owes
--   whom, the names short among the bill's (ui/NameTag.lua; a hover over the
--   bill gives the whole names) in class colour, each row marked „чака
--   потвърждение“ or „оспорен“ as the ledger has it; a line too long for its
--   row shrinks, then wraps onto more rows (W.fitWrap), never cut; in its header „Към залата“ and „Реванш на същата маса“ (Морски
--   шах: the engine's rematch; Death Roll, Сантасе, Белот, Табла: the host's
--   next game). A seated guest of an engine with `again` reads instead when
--   the host may begin the next match at the same stake (the rest of
--   Stakes.held, counted down by the table frame) and that „Към залата“ is
--   how to say no. StakePanels.shown says whether it is up, so the game views
--   hide their own result line. At a cash table (Холдем; a note with `why = "cash"`, heard by the client
--   event "cashout") a note's reason line is `bill.cash` (who stood up) or `bill.cash.close` (the game
--   closed), then its pairs, and `bill.cash.wait` while a note still waits for the keys; a note with
--   no pair of mine is no bill. P.blinds: the „5s/10s“ a cash table shows in place of a stake.
local Theme, W, L = ns.Theme, ns.W, ns.L
local money = ns.W.money

local P = {
  shown = false,  -- the bill is up (read by the game views)
  question = nil, -- {kind = "sit" | "invite" | "keep", tid, seat, sk, game}: the question shown
  queued = nil,   -- an invitation's question waiting for the asked seat's ("keep") to be answered
}
ns.StakePanels = P

local ASK_W, ASK_H, WARN_H = 380, 200, 44
local BUY_H, BUY_STEP = 34, 10 -- a cash table's buy-in stepper, in big blinds (MIN_BB to MAX_BB)
local BILL_W, BILL_TOP, BILL_ROW, BILL_Y, BILL_LINES = 500, 32, 18, 6, 6
local MARK_W = 112 -- the row's mark, right of its text

-- `name` short among `named` (the names of the bill and the table's seats), in class colour.
local function first(client, name, named) return W.shortColored(client, name, named) end

-- „5s/10s“ for a cash table of `game` (its stake is its big blind), nil for any other table.
function P.blinds(game, sk)
  local engine = ns.Games.engine(game)
  if engine and engine.stakeOf and sk ~= nil then return L("hall.blinds", money(sk / 2), money(sk)) end
end

---------------------------------------------------------------------------
-- The question
---------------------------------------------------------------------------

-- What I owe if I lose at a table of game `game`, stake `sk` (a team game:
-- one stake to one opponent, Stake.worst when I leave).
local function askText(game, sk)
  local engine = ns.Games.engine(game)
  if engine and engine.stakeOf then -- a cash table: its stake is its big blind
    local HC = ns.HoldemCash
    return L("stake.ask.cash", money(sk / 2), money(sk), money(HC.MIN_BB * sk), money(HC.MAX_BB * sk))
  end
  local worst = ns.Stake.worst(game, sk)
  if engine and engine.teams then return L("stake.ask.team", money(sk), money(sk), money(sk), money(worst)) end
  if worst > sk then return L("stake.ask.each", money(sk), money(sk), money(worst)) end
  return L("stake.ask.text", money(sk), money(sk))
end

local function buildAsk()
  local f = CreateFrame("Frame", nil, UIParent)
  P.askFrame = f
  ns.Resize.follow(f, "main")
  f:SetSize(ASK_W, ASK_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  P.askWood = W.chrome(f, ASK_W, ASK_H).wood
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
  P.askWarn = W.Label(f, "ui", L("stake.ask.cards"), 12) -- a card table only (showAsk)
  P.askWarn:SetTextColor(Theme.rgb("oMark"))
  P.askWarn:SetWidth(ASK_W - 48)
  P.askWarn:SetWordWrap(true)
  P.askWarn:SetPoint("TOPLEFT", P.askLeave, "BOTTOMLEFT", 0, -10)
  P.askWarn:Hide()
  local row = CreateFrame("Frame", nil, f) -- a cash table's buy-in: „−“ the amount „+“
  P.buyRow = row
  row:SetSize(ASK_W - 48, 24)
  row:SetPoint("TOPLEFT", P.askWarn, "BOTTOMLEFT", 0, -10)
  P.buyMinus = W.Button(row, L("holdem.minus"), function() P.stepBuy(-BUY_STEP) end, true)
  P.buyMinus:SetSize(30, 24)
  P.buyMinus:SetPoint("LEFT", row, "LEFT", 0, 0)
  P.buyPlus = W.Button(row, L("holdem.plus"), function() P.stepBuy(BUY_STEP) end, true)
  P.buyPlus:SetSize(30, 24)
  P.buyPlus:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  P.buyText = W.Label(row, "ui", "", 13)
  P.buyText:SetJustifyH("CENTER")
  P.buyText:SetPoint("LEFT", P.buyMinus, "RIGHT", 6, 0)
  P.buyText:SetPoint("RIGHT", P.buyPlus, "LEFT", -6, 0)
  row:Hide()
  P.askYes = W.Button(f, L("stake.ask.yes"), function() P.answer(true) end)
  P.askYes:SetSize(170, 28)
  P.askYes:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)
  P.askNo = W.Button(f, L("stake.ask.no"), function() P.answer(false) end)
  P.askNo:SetSize(110, 28)
  P.askNo:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
  f:Hide()
end

-- The buy-in I chose in big blinds, moved by `d` between MIN_BB and MAX_BB.
function P.stepBuy(d)
  local HC, q = ns.HoldemCash, P.question
  P.buyBB = math.max(HC.MIN_BB, math.min(HC.MAX_BB, (P.buyBB or HC.MAX_BB) + d))
  if q then P.buyText:SetText(L("stake.ask.buy", P.buyBB, money(P.buyBB * q.sk))) end
end

-- The rebuy line of a cash table's mode (the lobby's record or my own table; nothing when unknown).
local function rebuyLine(q)
  local client = ns.client
  local rec = client and client.lobby:get(q.tid)
  local s = client and client.session
  local mode = rec and rec.opt and rec.opt.rebuy or (s and s.tid == q.tid and s.opt and s.opt.rebuy)
  if mode == "top" then return L("stake.ask.rebuy.top", money(ns.HoldemCash.MAX_BB * q.sk)) end
  return L(mode and "stake.ask.rebuy." .. mode or "stake.ask.rebuy.unknown") -- an invitation does not carry the mode
end

local function showAsk(q)
  if not P.askFrame then buildAsk() end
  local open = P.question
  if open and open.kind == "keep" and q.kind ~= "keep" and P.askFrame:IsShown() then -- the asked seat first
    if q.kind == "invite" then P.queued = q end
    return
  end
  P.question = q
  P.askText:SetText(askText(q.game, q.sk))
  local engine = ns.Games.engine(q.game)
  local cards = engine ~= nil and engine.view ~= nil
  local cash = engine ~= nil and engine.stakeOf ~= nil
  local stepper = cash and q.kind ~= "keep" -- a seat I am asked about keeps the buy-in it has
  q.cash = stepper
  -- a cash table has no forfeit: its line is the rebuy mode; its warning has the void of a silent dealer too
  P.askLeave:SetText(cash and rebuyLine(q) or L("stake.ask.leave"))
  P.askWarn:SetText(cash and (L("stake.ask.cards") .. " " .. L("stake.ask.void")) or L("stake.ask.cards"))
  P.askWarn:SetShown(cards)
  P.buyRow:SetShown(stepper)
  if stepper then P.buyBB = nil; P.stepBuy(ns.HoldemCash.MAX_BB) end
  -- the frame grows with its text: 52 above, 68 below (a 20 gap, 28 of buttons, a 20 margin)
  local need = 52 + P.askText:GetStringHeight() + 10 + P.askLeave:GetStringHeight() + (cards and 10 + P.askWarn:GetStringHeight() or 0)
    + (stepper and BUY_H or 0) + 68
  local h = math.max(ASK_H + (cards and WARN_H or 0) + (stepper and BUY_H or 0), need)
  P.askFrame:SetHeight(h)
  P.askWood:SetTexCoord(0, (ASK_W - 8) / Theme.texSize.wood, 0, (h - 8) / Theme.texSize.wood)
  P.askFrame:Show()
  P.askFrame:Raise()
end

local function hideAsk()
  P.question = nil
  if P.askFrame then P.askFrame:Hide() end
  local q = P.queued
  P.queued = nil
  if q then showAsk(q) end
end

-- The question before sitting in seat `seat` of the staked table `rec` (a lobby record).
function P.ask(rec, seat)
  if not (rec and rec.stake ~= nil and seat) then return end
  showAsk({ kind = "sit", tid = rec.tid, seat = seat, sk = rec.stake, game = rec.game })
end

-- The question before accepting the invitation inv ({tid, game, stake}) to a staked table.
function P.askInvite(inv)
  showAsk({ kind = "invite", tid = inv.tid, sk = inv.stake, game = inv.game })
end

-- Does my client hold the guild's ledger, which a staked table needs -> bool. One
-- started before the game client knew my guild gets it now when the name is
-- known (wow/Adapter.lua's joinGuild); else "refused.ledger" is said, never a
-- wrong reason („другия залог“).
function P.ledgerReady(client, say)
  if not client.ledger and ns.Adapter and ns.Adapter.joinGuild then ns.Adapter.joinGuild() end
  if client.ledger then return true end
  say(L("refused.ledger"))
  return false
end

-- „Приемам и сядам“ (yes) or „Отказ“.
function P.answer(yes)
  local q, client = P.question, ns.client
  hideAsk()
  if not (q and client) then return end
  local buy = q.cash and P.buyBB * q.sk / ns.HoldemCash.CHIP -- chips: a big blind of the table is `blinds` chips
  if q.kind == "invite" then
    if yes and buy then client:wantBuy(q.tid, buy) end
    return ns.InviteToast.acceptStaked(q.tid, q.sk, yes)
  end
  if not yes then return end
  if q.kind == "keep" then
    client:acceptStake()
  elseif P.ledgerReady(client, ns.Hall.say) then -- a client without a ledger sits at no staked table
    client:sit(q.tid, q.seat, q.sk, buy)
  end
end

---------------------------------------------------------------------------
-- The bill
---------------------------------------------------------------------------

-- The outcomes of my staked table, in the order heard: {tid, {gid, no}...};
-- no: the table's s.stakeNo then (the game they belong to, core/Stakes.lua).
local heard = {}

-- `who`, `why`: a cash table's settlement (the "cashout" event): the seat's name and why it was settled.
local function hear(tid, q, who, why)
  local s = ns.client and ns.client.session
  if not (s and s.tid == tid and s.stake ~= nil and type(q) == "number") then return end
  if heard.tid ~= tid then heard = { tid = tid } end
  local gid = tid .. "/" .. q
  for _, h in ipairs(heard) do if h.gid == gid then return end end
  heard[#heard + 1] = { gid = gid, no = s.stakeNo, who = who, why = why }
end

-- My notes of the staked game just over at my table s, in the order heard ->
-- {note, ...}, {the heard entry of each: {who, why} of a cash table} | nil (a game still running, a fun
-- table, no note of mine; a note with no pair of mine is no bill).
function P.notes(client, s)
  if s.stake == nil or not client.stakes or heard.tid ~= s.tid or ns.Stakes.running(s) then return nil end
  local seen, out, hs = client.stakes:seen(), {}, {}
  for _, h in ipairs(heard) do
    local n = seen[h.gid]
    if h.no == s.stakeNo and type(n) == "table" and type(n.pairs) == "table" and #n.pairs > 0 then
      out[#out + 1] = n
      hs[#out] = h
    end
  end
  return #out > 0 and out or nil, hs
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
  local text = W.Label(b, "ui", "", 12)
  text:SetJustifyH("LEFT")
  local mark = W.Label(b, "dim", "", 11)
  mark:SetJustifyH("RIGHT")
  line = { text = text, mark = mark }
  b.lines[i] = line
  return line
end

-- Line i of the bill, `row` rows under its header: `text`, and a row's mark
-- for `status` (nil: a reason line, a sentence: it wraps at its own size). A
-- row too wide for its place first shrinks, then wraps onto more rows
-- (W.fitWrap): never cut -> the rows it takes.
local function setLine(b, i, row, text, status)
  local line, mark = lineWidget(b, i), MARK[status]
  local y, width = -(BILL_TOP - 4) - row * BILL_ROW, BILL_W - 28 - (status and MARK_W or 0)
  line.text:ClearAllPoints()
  line.text:SetPoint("TOPLEFT", b, "TOPLEFT", 14, y)
  line.mark:ClearAllPoints()
  line.mark:SetPoint("TOPRIGHT", b, "TOPRIGHT", -14, y - 1)
  local rows = math.max(1, math.ceil(W.fitWrap(line.text, text, width, not status and math.huge or nil) / BILL_ROW - 0.001))
  line.text:Show()
  line.mark:SetText(mark and L(mark[1]) or "")
  if mark then line.mark:SetTextColor(Theme.rgb(mark[2])) end
  line.mark:SetShown(mark ~= nil)
  return rows
end

local function buildBill(v)
  local b = W.Panel(v.area)
  b.fill:SetColorTexture(20 / 255, 10 / 255, 5 / 255, 0.92)
  b:SetSize(BILL_W, BILL_TOP + BILL_ROW)
  b:SetPoint("BOTTOM", v.area, "BOTTOM", 0, BILL_Y)
  b:SetFrameLevel(v.area:GetFrameLevel() + ns.Cards.TOP + 12) -- above a full hand (ui/Cards.lua)
  b:EnableMouse(true)
  -- The header strip: the title left, „Към залата“ and „Реванш на същата маса“ right.
  b.title = W.Label(b, "heading", L("bill.title"), 14)
  b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -6)
  b.lines = {}
  b.rematch = W.Button(b, L("bill.rematch"), function() P.rematch() end, true)
  b.rematch:SetSize(180, 20)
  b.rematch:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -4)
  b.toHall = W.Button(b, L("table.toHall"), function() ns.TableFrame.stand() end, true)
  b.toHall:SetSize(110, 20)
  b.toHall:SetPoint("RIGHT", b.rematch, "LEFT", -6, 0)
  W.nameTip(b, function() return b.named end) -- the whole names of the bill
  b.waiting = W.Label(b, "dim", "", 12) -- in the place of „Реванш“ once I asked for it
  b.waiting:SetJustifyH("RIGHT")
  b.waiting:SetPoint("RIGHT", b, "TOPRIGHT", -12, -14)
  b:Hide()
  v.bill = b
end

-- Морски шах: my „Реванш“ (rematch, asked: whom I wait for); every other
-- game: the host's next game; a seated guest of an engine with `again` while
-- the table is live: "wait", the whole seconds and the seconds left of
-- Stakes.held, then "ready"; nothing for a Death Roll guest or a match nobody can replay.
local function rematchState(s, client)
  local st, me = s.state, s.mySeat
  if s.game ~= "ttt" and s.role == "host" then return "start" end
  if s.game ~= "ttt" then
    if not (s:engine().again and s.status == "live" and s:gameOver() and me and s.seats[me] == client.env.me) then return nil end
    if s:seatedCount() < s:engine().minSeats then return "short" end
    local left, silent = ns.Stakes.held(s)
    if silent then return "silent", silent, left end
    if left > 0 then return "wait", math.ceil(left), left end
    return "ready"
  end
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
-- for my table s, else hides it; sets P.shown -> the seconds left of a
-- guest's countdown on it, or nil.
function P.bill(v, s)
  local client = ns.client
  local notes, hs = nil, nil
  if client then notes, hs = P.notes(client, s) end
  P.shown = notes ~= nil
  if not notes then
    if v.bill then v.bill:Hide() end
    return nil
  end
  if not v.bill then buildBill(v) end
  local b, items, team = v.bill, {}, s:engine().teams
  local waits, named = false, {}
  local function name(n) if type(n) == "string" then named[#named + 1] = n end end
  for _, n in ipairs(s.seats) do name(n) end
  for i, note in ipairs(notes) do
    name(hs[i] and hs[i].who)
    for _, p in ipairs(note.pairs) do name(p.f); name(p.t) end
  end
  local function first(c, n) return W.shortColored(c, n, named) end
  b.named = named
  for i, note in ipairs(notes) do
    if note.why == "cash" then -- one sitting: who stood up (or the close), then the pairs, then the keys' line
      local h = hs[i]
      items[#items + 1] = { h.why == "close" and L("bill.cash.close") or L("bill.cash", first(client, h.who or "?")) }
      if note.wait == true and not waits then waits = true; items[#items + 1] = { L("bill.cash.wait") } end -- before any overflow
    else
      local leaver = note.why ~= "lost" and note.pairs[1] and note.pairs[1].f
      local why = note.why == "idle" and "bill.idle" or team and "bill.left.team" or "bill.left"
      if leaver then items[#items + 1] = { L(why, first(client, leaver)) } end
    end
    for _, r in ipairs(P.billRows(client, note)) do
      items[#items + 1] = { L("bill.row", first(client, r.f), first(client, r.t), money(r.c)), r.status }
    end
  end
  local n, rows = math.min(#items, BILL_LINES), 0
  for i = 1, n do
    local item = items[i]
    if i == BILL_LINES and #items > BILL_LINES then item = { L("bill.more", #items - BILL_LINES + 1) } end
    rows = rows + setLine(b, i, rows, item[1], item[2])
  end
  local what, other, left = rematchState(s, client)
  if what == "wait" or what == "ready" or what == "silent" or what == "short" then -- a guest: when the next match may begin
    n = n + 1
    local line = what == "silent" and L("bill.again.silent", first(client, other)) or what == "wait" and L("bill.again.wait", other)
      or what == "short" and L("bill.again.short") or L("bill.again.ready")
    rows = rows + setLine(b, n, rows, line)
  end
  for i = n + 1, #b.lines do b.lines[i].text:Hide(); b.lines[i].mark:Hide() end
  b:SetHeight(BILL_TOP + BILL_ROW * rows)
  b.rematch:SetShown(what == "ask" or what == "start")
  b.waiting:SetText(what == "asked" and L("ttt.waitingFor", first(client, other)) or "")
  b.waiting:SetShown(what == "asked")
  b:Show()
  return left
end

-- My own cash-out applied and my table gone: my bill once, from my own note, in the hall's line.
function P.sayMine(client)
  local gid, note = P.mine, P.mine and client.stakes and client.stakes:seen()[P.mine]
  P.mine = nil
  if type(note) ~= "table" or type(note.pairs) ~= "table" or #note.pairs == 0 then return end
  local out = {}
  local named = {}
  for _, p in ipairs(note.pairs) do named[#named + 1] = p.f; named[#named + 1] = p.t end
  for _, r in ipairs(P.billRows(client, note)) do out[#out + 1] = L("bill.row", first(client, r.f, named), first(client, r.t, named), money(r.c)) end
  if #out > 0 then ns.Hall.say(L("bill.cash.mine", table.concat(out, "; "))) end
end

ns.ready(function(client)
  client:on("result", function(r) if r.sk ~= nil then hear(r.tid, r.q) end end)
  client:on("forfeit", function(f) if f.sk ~= nil then hear(f.tid, f.q) end end)
  client:on("cashout", function(e)
    hear(e.tid, tonumber(tostring(e.gid):match("/(%d+)$")), e.name, e.why)
    if e.name == client.env.me and e.why == nil then P.mine = e.gid end -- my own „Стани“: my bill is shown when it ends
  end)
  client:on("cashGoing", function(tid) if tid == nil then P.sayMine(client) end end)
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
  client:on("tables", function()
    local q = P.question
    if q and q.kind == "sit" and not client.lobby:get(q.tid) then hideAsk() end
  end)
end)
