local Wow = require("wow")

-- The stake at the table in the UI: the new-table dialog, the question before
-- a staked chair, the stake in the hall, the invitation and the table header,
-- the warning on „Стани“, the bill „Сметката“ and the start refusals.
local ME, B, C, D = "Иван Петров", "Мария Стоянова", "Тодор Ангелов", "Дара Колева"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired.
local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

-- ... and my login queue has closed: my ledger entries leave at once.
local function readyWow()
  local w = guildWow()
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  return w
end

local function lastSent(w, t)
  local all = w:sentOf(t)
  return all[#all]
end

-- `text` without inline colour codes.
local function plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function has(text, needle) return plain(text):find(needle, 1, true) ~= nil end

local function count(text, needle)
  local n, from = 0, 1
  text = plain(text)
  while true do
    local i, j = text:find(needle, from, true)
    if not i then return n end
    n, from = n + 1, j + 1
  end
end

-- A real player says HI (with a GUID) so Presence knows him.
local function hello(w, name)
  w:member(name)
  w:deliver("GUILD", name, { v = 1, t = "HI", ver = "0.1.0", cls = "PRIEST", id = "Player-1-" .. name })
end

-- Another host's table in the hall: its TBL with stake `sk` (nil: for fun).
local function tbl(w, host, sk, game, seats)
  local tid = host .. "#1"
  w:member(host)
  w:deliver("GUILD", host, { v = 1, t = "TBL", tid = tid, g = game or "ttt", h = host, e = 1, ac = "guild", tn = 45,
                             st = "open", s = seats or { host, false }, w = 0, sk = sk,
                             o = (game == "deathroll") and { start = 1000 } or nil })
  w:advance(0)
  return tid
end

-- I host a staked table of `game` at `sk`; `others` sit down, each by its SIT with that stake.
local function host(w, game, sk, others)
  local tid = w.ns.client:openTable{ game = game, access = "guild", turn = 45, stake = sk,
                                     opt = game == "deathroll" and { start = 1000 } or nil }
  assert(tid, "the staked table did not open")
  w:advance(0)
  for i, name in ipairs(others or {}) do
    hello(w, name)
    w.partyNames[name] = true
    w:deliver("WHISPER", name, { v = 1, t = "SIT", tid = tid, seat = i + 1, sk = sk })
    w:advance(0)
  end
  return tid, w.ns.client.session
end

-- Морски шах at 5g against Мария, the match one round from my win: I win it.
local function wonMatch(w)
  local tid, s = host(w, "ttt", 50000, { B })
  assert(s.status == "live", "the match did not start")
  s.state.score = { 2, 0 }
  local client = w.ns.client
  client:act({ k = "mark", c = 1 }); s:play(2, { k = "mark", c = 4 })
  client:act({ k = "mark", c = 2 }); s:play(2, { k = "mark", c = 5 })
  client:act({ k = "mark", c = 3 })
  w:advance(0)
  assert(s.state.phase == "match", "the match is not over")
  return tid, s
end

-- My D entry against `f` in my ledger.
local function myClaim(w, f)
  local found
  w.ns.client.ledger:each(function(e) if e.k == "D" and e.f == f then found = e end end)
  return found
end

-- `name`'s live word (C, or N with why) about my claim `d`.
local function word(w, name, n, d, kind, why)
  w:deliver("GUILD", name, { v = 1, t = "LEV", ev = {
    { i = name .. ":" .. n, k = kind, at = w.G.GetServerTime(), r = d.i, dh = d.h, why = why } } })
  w:advance(1)
  w:advance(0)
end

describe("ui: the stake in the new-table dialog", function()
  it("the dialog opens for fun by default and sends no stake", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local Dlg = w.ns.NewTableDialog
    Dlg.open("ttt")
    eq(Dlg.stake.value, "none")
    w:click(Dlg.openButton)
    local s = w.ns.client.session
    ok(s, "no table"); eq(s.stake, nil)
    eq(lastSent(w, "TBL").msg.sk, nil)
  end)

  it("„Със залог“ is offered only for Морски шах and Death Roll", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local Dlg, L = w.ns.NewTableDialog, w.ns.L
    eq(L("dialog.stake.gold"), "Със залог")
    for _, id in ipairs({ "ttt", "deathroll" }) do
      Dlg.open(id)
      eq(#Dlg.stake.options, 2)
      eq({ Dlg.stake.options[1].text:GetText(), Dlg.stake.options[2].text:GetText() }, { "Само за удоволствие", "Със залог" })
      ok(Dlg.stake.options[2].frame:IsVisible(), "no „Със залог“ for " .. id)
    end
    for _, id in ipairs({ "santase", "belot", "tabla", "holdem" }) do
      Dlg.open(id)
      eq(#Dlg.stake.options, 1)
      eq(Dlg.stake.options[1].text:GetText(), "Само за удоволствие")
      eq(#w:texts("Със залог"), 0)
    end
  end)

  it("„Със залог“ shows two boxes and sends copper; Tab moves between them", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local Dlg = w.ns.NewTableDialog
    Dlg.open("ttt")
    eq(Dlg.goldBox:IsVisible(), false); eq(Dlg.frame:GetHeight(), 330)
    w:click(Dlg.stake.options[2].frame)
    eq(Dlg.stake.value, "gold")
    ok(Dlg.goldBox:IsVisible() and Dlg.silverBox:IsVisible(), "no amount boxes")
    eq(#w:texts("Залог на човек"), 1)
    eq(Dlg.frame:GetHeight(), 330 + 34)
    ok(Dlg.goldBox:HasFocus(), "the gold box has no focus")
    Dlg.goldBox.scripts.OnTabPressed(Dlg.goldBox); ok(Dlg.silverBox:HasFocus(), "Tab did not reach silver")
    Dlg.silverBox.scripts.OnTabPressed(Dlg.silverBox); ok(Dlg.goldBox:HasFocus(), "Tab did not come back")
    Dlg.goldBox:SetText("5"); Dlg.silverBox:SetText("25")
    w:click(Dlg.openButton)
    local s = w.ns.client.session
    ok(s, "no table"); eq(s.stake, 52500)
    eq(lastSent(w, "TBL").msg.sk, 52500)
    eq(Dlg.frame:IsShown(), false)
    -- Back to fun: the boxes go and the height is the old one.
    w.ns.client:stand(); w:advance(0)
    Dlg.open("deathroll"); w:click(Dlg.stake.options[2].frame)
    eq(Dlg.frame:GetHeight(), 364 + 34)
    w:click(Dlg.stake.options[1].frame)
    eq(Dlg.goldBox:IsVisible(), false); eq(Dlg.frame:GetHeight(), 364)
  end)

  it("a bad amount keeps the dialog open with the reason", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local Dlg, L = w.ns.NewTableDialog, w.ns.L
    eq(L("dialog.stake.bad"), "Залогът е поне 1s, в голд и силвър.")
    for _, parts in ipairs({ { "", "" }, { "", "100" }, { "0", "0" }, { "2", "100" } }) do
      Dlg.open("deathroll"); w:click(Dlg.stake.options[2].frame)
      Dlg.goldBox:SetText(parts[1]); Dlg.silverBox:SetText(parts[2])
      local sent = #w:sentOf("TBL")
      w:click(Dlg.openButton)
      eq(w.ns.client.session, nil); eq(#w:sentOf("TBL"), sent)
      ok(Dlg.frame:IsShown(), "dialog closed"); eq(Dlg.error:GetText(), L("dialog.stake.bad"))
    end
    -- Silver alone is a stake.
    Dlg.goldBox:SetText(""); Dlg.silverBox:SetText("50")
    w:click(Dlg.openButton)
    eq(w.ns.client.session.stake, 5000)
  end)
end)

describe("ui: the question before a staked chair", function()
  it("a click on a chair of a staked table asks first", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local P, L = w.ns.StakePanels, w.ns.L
    local tid = tbl(w, B, 50000)
    local sits = #w:sentOf("SIT")
    w:click(w.ns.Hall.view.tables[1].chairs[2].button)
    eq(#w:sentOf("SIT"), sits)
    ok(P.askFrame:IsShown(), "no question")
    eq(P.askTitle:GetText(), "Маса със залог")
    eq(P.askText:GetText(), "Залогът е 5g. Ако загубиш, дължиш 5g на победителя.")
    eq(count(P.askText:GetText(), "5g"), 2)
    eq(P.askLeave:GetText(), L("stake.ask.leave"))
    eq(P.askYes.text:GetText(), "Приемам и сядам"); eq(P.askNo.text:GetText(), "Отказ")
    w:click(P.askNo)
    eq(P.askFrame:IsShown(), false); eq(#w:sentOf("SIT"), sits)
    w:click(w.ns.Hall.view.tables[1].chairs[2].button)
    w:click(P.askYes)
    eq(P.askFrame:IsShown(), false)
    local sit = lastSent(w, "SIT")
    eq({ sit.target, sit.msg.tid, sit.msg.seat, sit.msg.sk }, { B, tid, 2, 50000 })
  end)

  it("a fun table sits at once, as today", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local tid = tbl(w, B, nil)
    w:click(w.ns.Hall.view.tables[1].chairs[2].button)
    local sit = lastSent(w, "SIT")
    ok(sit, "no SIT"); eq({ sit.msg.tid, sit.msg.seat, sit.msg.sk }, { tid, 2, nil })
    eq(w.ns.StakePanels.askFrame == nil or not w.ns.StakePanels.askFrame:IsShown(), true)
  end)

  it("a click on a row of the list asks first too", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local P, view = w.ns.StakePanels, w.ns.Hall.view
    local staked = tbl(w, B, 50000)
    local fun = tbl(w, C, nil)
    for i = 1, 7 do tbl(w, "Гост " .. i) end
    eq(w.ns.Hall.mode, "list")
    local function row(tid)
      for _, r in ipairs(view.rows) do if r.frame:IsVisible() and r.tid == tid then return r end end
    end
    local sits = #w:sentOf("SIT")
    w:click(row(staked).action)
    eq(#w:sentOf("SIT"), sits); ok(P.askFrame:IsShown(), "no question")
    w:click(P.askYes)
    local sit = lastSent(w, "SIT")
    eq({ sit.target, sit.msg.seat, sit.msg.sk }, { B, 2, 50000 })
    w:click(row(fun).action)
    sit = lastSent(w, "SIT")
    eq({ sit.target, sit.msg.seat, sit.msg.sk }, { C, 2, nil })
    eq(P.askFrame:IsShown(), false)
  end)

  it("Death Roll's question names the worst case", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local P = w.ns.StakePanels
    tbl(w, B, 10000, "deathroll", { B, false, false, false, false })
    w:click(w.ns.Hall.view.tables[1].chairs[3].button)
    eq(P.askText:GetText(), "Залогът е 1g. Който хвърли 1, плаща по 1g на всеки от останалите, най-много 4g.")
    w:click(P.askYes)
    eq({ lastSent(w, "SIT").msg.seat, lastSent(w, "SIT").msg.sk }, { 3, 10000 })
  end)

  it("a seat my client was asked about after a crash: „Приемам и сядам“ accepts its stake", function()
    local w = readyWow()
    local P, client = w.ns.StakePanels, w.ns.client
    local accepted = 0
    client.acceptStake = function() accepted = accepted + 1; return true end
    local tid, s = host(w, "deathroll", 20000)
    s.stakeAsk = true -- as Member.adopt leaves an asked seat (core/Stake.lua)
    client.events:emit("stakeAsk", tid, 20000)
    w:advance(0)
    ok(P.askFrame:IsShown(), "no question")
    eq(P.askText:GetText(), "Залогът е 2g. Който хвърли 1, плаща по 2g на всеки от останалите, най-много 8g.")
    w:click(P.askYes)
    eq(accepted, 1); eq(P.askFrame:IsShown(), false)
    -- Asked again, no answer: the question goes with the seat.
    client.events:emit("stakeAsk", tid, 20000); w:advance(0)
    ok(P.askFrame:IsShown(), "no second question")
    s.stakeAsk = nil
    client.events:emit("session", s); w:advance(0)
    eq(P.askFrame:IsShown(), false); eq(accepted, 1)
  end)
end)

describe("ui: the stake in the hall, the invitation and the table header", function()
  it("the tooltips and the list row show the stake; a fun table says „За удоволствие“", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local L, tip, view = w.ns.L, w.G.GameTooltip, w.ns.Hall.view
    eq(L("table.stake.none"), "За удоволствие")
    local staked = tbl(w, B, 50000)
    local t = view.tables[1]
    w:hover(t.top)
    eq(tip.lines[4], "Залог: 5g")
    w:hover(t.chairs[2].button)
    eq(tip.lines, { L("hall.tip.sit"), "Залог: 5g" })
    local fun = tbl(w, C, nil)
    for i = 1, 7 do tbl(w, "Гост " .. i) end
    local subs = {}
    for _, r in ipairs(view.rows) do if r.frame:IsVisible() then subs[r.tid] = r.sub:GetText() end end
    eq(subs[staked], "Всеки от гилдията · 45 с на ход · Залог: 5g")
    eq(subs[fun], "Всеки от гилдията · 45 с на ход · За удоволствие")
  end)

  it("the invitation shows the stake line only for a staked table", function()
    local w = guildWow()
    local T = w.ns.InviteToast
    w:member(B)
    w:deliver("WHISPER", B, { v = 1, t = "INV", tid = B .. "#1", g = "ttt", h = B, s = { B, false }, sk = 50000 })
    w:advance(0)
    ok(T.frame:IsShown(), "no toast")
    ok(T.stake:IsVisible(), "no stake line"); eq(T.stake:GetText(), "Залог: 5g")
    eq(T.frame:GetHeight(), T.HEIGHT + T.STAKE_H)
    T.answer("no")
    w:deliver("WHISPER", B, { v = 1, t = "INV", tid = B .. "#2", g = "ttt", h = B, s = { B, false } })
    w:advance(0)
    ok(T.frame:IsShown(), "no second toast")
    eq(T.stake:IsVisible(), false); eq(T.frame:GetHeight(), T.HEIGHT)
  end)

  it("the table header shows the stake", function()
    local w = readyWow()
    host(w, "ttt", 50000)
    local v = w.ns.TableFrame.view
    ok(v.stake:IsVisible(), "no stake label"); eq(v.stake:GetText(), "Залог: 5g")
    w.ns.client:stand(); w:advance(0)
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }; w:advance(0)
    eq(v.stake:IsVisible(), false)
  end)
end)

describe("ui: „Стани“ at a staked table", function()
  it("„Стани“ in a live staked game asks first and names the amount", function()
    local w = readyWow()
    local TF, L = w.ns.TableFrame, w.ns.L
    local _, s = host(w, "ttt", 50000, { B })
    eq(s.status, "live")
    ok(TF.standCosts(s), "no cost")
    w:click(TF.view.standButton)
    ok(TF.view.confirm:IsShown(), "no question"); eq(w.ns.client.session, s)
    eq(TF.view.confirm.text:GetText(), "Ако станеш сега, губиш служебно и дължиш 5g.")
    eq(L("stand.stake", "5g"), TF.view.confirm.text:GetText())
    w:click(TF.view.confirm.no)
    eq(TF.view.confirm:IsShown(), false); eq(w.ns.client.session, s)
  end)

  it("Death Roll with three other players: the stake times the others", function()
    local w = readyWow()
    local TF = w.ns.TableFrame
    local _, s = host(w, "deathroll", 50000, { B, C, D })
    w:advance(0)
    w:click(TF.view.startButton); w:advance(0)
    eq(s.status, "live")
    w:click(TF.view.standButton)
    eq(TF.view.confirm.text:GetText(), "Ако станеш сега, губиш служебно и дължиш 15g.")
    w:click(TF.view.confirm.yes); w:advance(0)
    eq(w.ns.client.session, nil)
  end)

  it("after the game is over it does not ask", function()
    local w = readyWow()
    local TF = w.ns.TableFrame
    local _, s = wonMatch(w)
    eq(TF.standCosts(s), false)
    w:click(TF.view.standButton); w:advance(0)
    eq(w.ns.client.session, nil)
  end)

  it("a fun table does not ask, as today", function()
    local w = readyWow()
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }; w:advance(0)
    hello(w, B); w:deliver("WHISPER", B, { v = 1, t = "SIT", tid = w.ns.client.session.tid, seat = 2 }); w:advance(0)
    eq(w.ns.client.session.status, "live")
    eq(w.ns.TableFrame.standCosts(w.ns.client.session), false)
  end)
end)

describe("ui: the bill", function()
  it("the bill shows who owes whom and follows the ledger", function()
    local w = readyWow()
    local P, L = w.ns.StakePanels, w.ns.L
    local tid = wonMatch(w)
    local client = w.ns.client
    local note = client.stakes:last(tid)
    ok(note, "no note")
    eq(P.billRows(client, note), { { f = B, t = ME, c = 50000, status = "pending" } })
    local bill = w.ns.TableFrame.view.bill
    ok(bill:IsVisible(), "no bill")
    eq(bill.title:GetText(), "Сметката")
    eq(plain(bill.lines[1].text:GetText()), "Мария дължи на Иван 5g")
    ok(bill.lines[1].text:GetText():find("|c", 1, true), "names not in class colour")
    eq(bill.lines[1].mark:GetText(), L("bill.pending")); ok(bill.lines[1].mark:IsVisible(), "no pending mark")
    eq(bill.lines[2] == nil or not bill.lines[2].text:IsVisible(), true)
    eq(bill:GetHeight(), 48 + 22); eq(bill:GetWidth(), 360)
    local d = myClaim(w, B)
    ok(d, "no claim of mine")
    word(w, B, 1, d, "C")
    eq(P.billRows(client, note)[1].status, "confirmed")
    eq(bill.lines[1].mark:IsVisible(), false)
    word(w, B, 2, d, "N", "no")
    eq(P.billRows(client, note)[1].status, "contested")
    eq(bill.lines[1].mark:GetText(), "оспорен"); ok(bill.lines[1].mark:IsVisible(), "no contested mark")
  end)

  it("the board's own result line hides while the bill shows", function()
    local w = readyWow()
    wonMatch(w)
    local f = w.ns.TableFrame.built.ttt
    ok(w.ns.TableFrame.view.bill:IsVisible(), "no bill")
    eq(f.result:IsVisible(), false); eq(f.rematch:IsVisible(), false)
  end)

  it("a forfeit's bill says why", function()
    local w = readyWow()
    local tid, s = host(w, "ttt", 50000, { B })
    w.ns.client:act({ k = "mark", c = 1 }); w:advance(0)
    w:deliver("WHISPER", B, { v = 1, t = "STD", tid = tid }); w:advance(0)
    local bill = w.ns.TableFrame.view.bill
    ok(bill and bill:IsVisible(), "no bill")
    eq(plain(bill.lines[1].text:GetText()), "Мария напусна играта и губи служебно.")
    eq(bill.lines[1].mark:IsVisible(), false)
    eq(plain(bill.lines[2].text:GetText()), "Мария дължи на Иван 5g")
    eq(bill:GetHeight(), 48 + 2 * 22)
    -- bill.idle comes from the note's why (the host's own idle forfeit has a D "left").
    w.ns.client.stakes:last(tid).why = "idle"
    w.ns.TableFrame.render()
    eq(plain(bill.lines[1].text:GetText()), "Мария не хвърли 3 минути и губи служебно.")
    eq(s.status, "aborted")
  end)

  it("the bill's buttons: Морски шах", function()
    local w = readyWow()
    local TF = w.ns.TableFrame
    local _, s = wonMatch(w)
    local bill = TF.view.bill
    eq(bill.toHall.text:GetText(), "Към залата"); eq(bill.rematch.text:GetText(), "Реванш на същата маса")
    w:click(bill.rematch); w:advance(0)
    eq(s.state.rematch[1], true)
    eq(bill.rematch:IsVisible(), false); ok(has(bill.waiting:GetText(), "Мария"), "no waiting line")
    w:click(bill.toHall); w:advance(0)
    eq(w.ns.client.session, nil); eq(TF.frame:IsShown(), false)
  end)

  it("the bill's buttons: Death Roll, the host and a guest", function()
    local w = readyWow()
    local TF, L = w.ns.TableFrame, w.ns.L
    local _, s = host(w, "deathroll", 10000, { B })
    w:advance(0)
    w:click(TF.view.startButton); w:advance(0)
    eq(s.status, "live")
    local started = 0
    local start = TF.startGame
    TF.startGame = function() started = started + 1 end
    -- My roll of 1 at once: I lose.
    s:play(s.state.turn, { k = "roll", n = s.state.turn == 1 and 1 or 50, max = s.state.max, src = "seen" })
    if not s:gameOver() then s:play(s.state.turn, { k = "roll", n = 1, max = s.state.max, src = "seen" }) end
    w:advance(0)
    ok(s:gameOver(), "the game is not over")
    local bill = TF.view.bill
    ok(bill:IsVisible(), "no bill"); ok(bill.rematch:IsVisible(), "no rematch for the host")
    eq(TF.built.deathroll.status:IsVisible(), false) -- the view's own „… хвърли 1 и губи!“ is under the bill
    w:click(bill.rematch)
    eq(started, 1)
    TF.startGame = start
    -- A guest has no rematch: the host starts the next game.
    s.role = "player"; TF.render()
    eq(bill.rematch:IsVisible(), false)
    eq(L("bill.rematch"), "Реванш на същата маса")
  end)
end)

describe("ui: the start of a staked game", function()
  it("„Започни“ refused for the group says start.group on the news line; for the break start.break", function()
    local w = readyWow()
    local TF, L = w.ns.TableFrame, w.ns.L
    local _, s = host(w, "deathroll", 10000, { B })
    w.partyNames[B] = nil
    w:advance(0)
    ok(TF.view.startButton:IsVisible() and TF.view.startButton:IsEnabled(), "„Започни“ cannot be clicked")
    w:click(TF.view.startButton)
    eq(TF.view.line:GetText(), L("start.group"))
    eq(L("start.group"), "Всички на масата трябва да са в групата ти, преди да започнете.")
    w.partyNames[B] = true
    w:click(TF.view.startButton); w:advance(0)
    eq(s.status, "live")
    s:play(s.state.turn, { k = "roll", n = 1, max = s.state.max, src = "seen" }); w:advance(0)
    ok(s:gameOver(), "not over")
    w:click(TF.view.startButton)
    eq(TF.view.line:GetText(), "Изчакай малко: играчите решават дали остават.")
    eq(TF.view.startButton:GetAlpha(), 0.5)
    w:advance(w.ns.Const.STAKE_BREAK + 0.1)
    eq(TF.view.startButton:GetAlpha(), 1)
    w:click(TF.view.startButton); w:advance(0)
    ok(not s:gameOver(), "the next game did not start")
  end)

  it("the refusals of a staked sit are said in the footer", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local L = w.ns.L
    w.ns.client.events:emit("refused", "x#1", "stake")
    eq(w.ns.Hall.view.footer:GetText(), "Залогът на масата е друг. Виж го и седни отново.")
    w.ns.client.events:emit("refused", "x#1", "roll")
    eq(w.ns.Hall.view.footer:GetText(), L("refused.roll"))
  end)
end)
