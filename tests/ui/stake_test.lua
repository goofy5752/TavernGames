local Wow = require("wow")

-- The stake at the table in the UI: the new-table dialog, the question before
-- a staked chair, the stake in the hall, the invitation and the table header,
-- the warning on „Стани“, the bill „Сметката“ and the start refusals.
local ME, B, C, D = "Иван Петров", "Мария Стоянова", "Тодор Ангелов", "Дара Колева"

local Staked = require("staked")
local guildWow, readyWow = Staked.guildWow, Staked.readyWow

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
    w.group["Player-1-" .. name] = true -- in my group: a staked Death Roll starts only so
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

  it("„Със залог“ is offered only for the five games that take a stake", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local Dlg, L = w.ns.NewTableDialog, w.ns.L
    eq(L("dialog.stake.gold"), "Със залог")
    for _, id in ipairs({ "ttt", "deathroll", "santase", "belot", "tabla" }) do
      Dlg.open(id)
      eq(#Dlg.stake.options, 2)
      eq({ Dlg.stake.options[1].text:GetText(), Dlg.stake.options[2].text:GetText() }, { "Само за удоволствие", "Със залог" })
      ok(Dlg.stake.options[2].frame:IsVisible(), "no „Със залог“ for " .. id)
    end
    for _, id in ipairs({ "holdem" }) do
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
    eq(bill:GetHeight(), 32 + 18); eq(bill:GetWidth(), 500)
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
    eq(bill:GetHeight(), 32 + 2 * 18)
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
    w.partyNames[B], w.group["Player-1-" .. B] = nil, nil
    w:advance(0)
    ok(TF.view.startButton:IsVisible() and TF.view.startButton:IsEnabled(), "„Започни“ cannot be clicked")
    w:click(TF.view.startButton)
    eq(TF.view.line:GetText(), L("start.group"))
    eq(L("start.group"), "Всички на масата трябва да са в групата ти, преди да започнете.")
    w.partyNames[B], w.group["Player-1-" .. B] = true, true
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

-- Fix round 1 (task-11-review.md): the bill's geometry, the invitation's question, the minors.
local E = "Яна Жекова"

-- How far above the felt's bottom the top of the bill reaches.
local function billTop(v) return v.bill.points[1][5] + v.bill:GetHeight() end

-- How far above the felt's bottom `y` px under the top of the board frame `f` is.
local function boardY(v, f, y) return v.areaH / 2 + f.points[1][5] + f:GetHeight() / 2 - y end

describe("ui: the bill keeps clear of the board (fix round 1)", function()
  it("a Морски шах bill never reaches the board's bottom row", function()
    local w = readyWow()
    wonMatch(w)
    local v, f = w.ns.TableFrame.view, w.ns.TableFrame.built.ttt
    local cell = f.cells[7].button
    local bottomRow = boardY(v, f, -cell.points[1][5] + cell:GetHeight())
    eq(v.bill.points[1], { "BOTTOM", v.area, "BOTTOM", 0, 6 })
    ok(billTop(v) < bottomRow, "the bill reaches " .. billTop(v) .. ", the bottom row starts at " .. bottomRow)
    -- The header strip: the title left, the buttons right.
    eq(v.bill.title.points[1], { "TOPLEFT", v.bill, "TOPLEFT", 12, -6 })
    eq(v.bill.rematch.points[1], { "TOPRIGHT", v.bill, "TOPRIGHT", -8, -4 })
    eq(v.bill.toHall.points[1], { "RIGHT", v.bill.rematch, "LEFT", -6, 0 })
  end)

  it("a Death Roll bill of five players keeps 6 lines, the last „… и още 3“, below the ladder and the caption", function()
    local w = readyWow()
    local TF, L = w.ns.TableFrame, w.ns.L
    eq(L("bill.more", 3), "… и още 3")
    local tid, s = host(w, "deathroll", 10000, { B, C, D, E })
    w:advance(0)
    w:click(TF.view.startButton); w:advance(0)
    eq(s.status, "live")
    w:deliver("WHISPER", E, { v = 1, t = "STD", tid = tid }); w:advance(0) -- a forfeit to the four of us: 5 lines
    s:play(s.state.turn, { k = "roll", n = 1, max = s.state.max, src = "seen" }); w:advance(0) -- 3 more rows
    ok(s:gameOver(), "not over")
    local v, f = TF.view, TF.built.deathroll
    local shown = 0
    for _, line in ipairs(v.bill.lines) do if line.text:IsVisible() then shown = shown + 1 end end
    eq(shown, 6)
    eq(plain(v.bill.lines[1].text:GetText()), "Яна напусна играта и губи служебно.")
    eq(plain(v.bill.lines[6].text:GetText()), "… и още 3"); eq(v.bill.lines[6].mark:IsVisible(), false)
    eq(v.bill:GetHeight(), 32 + 6 * 18)
    local ladder = boardY(v, f, -f.cells[1].frame.points[1][5] + f.cells[1].frame:GetHeight())
    local under = boardY(v, f, -f.caption.points[1][5] + f.caption:GetStringHeight())
    if f.group:IsVisible() then under = under - 6 - f.group:GetStringHeight() end
    ok(billTop(v) <= ladder and billTop(v) <= under, "the bill reaches " .. billTop(v) .. " (ladder " .. ladder .. ", text " .. under .. ")")
  end)
end)

describe("ui: the invitation to a staked table asks first (fix round 1)", function()
  -- Мария invites me to her staked table of `game`.
  local function invited(w, game, sk)
    local seats = game == "deathroll" and { B, false, false, false, false } or { B, false }
    local tid = tbl(w, B, sk, game, seats)
    w:deliver("WHISPER", B, { v = 1, t = "INV", tid = tid, g = game, h = B, s = seats, sk = sk })
    w:advance(0)
    return tid
  end

  it("„Приемам“ sends no SIT; the question names Death Roll's worst case and the leave; its yes sits at the stake", function()
    local w = guildWow()
    local T, P = w.ns.InviteToast, w.ns.StakePanels
    local tid = invited(w, "deathroll", 10000)
    local sits = #w:sentOf("SIT")
    w:click(T.accept)
    eq(#w:sentOf("SIT"), sits); eq(T.frame:IsShown(), false)
    ok(P.askFrame:IsShown(), "no question")
    eq(P.askText:GetText(), "Залогът е 1g. Който хвърли 1, плаща по 1g на всеки от останалите, най-много 4g.")
    eq(P.askLeave:GetText(), w.ns.L("stake.ask.leave"))
    w:click(P.askYes)
    local sit = lastSent(w, "SIT")
    eq({ sit.target, sit.msg.tid, sit.msg.seat, sit.msg.sk }, { B, tid, 2, 10000 })
    eq(lastSent(w, "INR").msg.a, "yes")
  end)

  it("„Отказ“ declines the invitation", function()
    local w = guildWow()
    local T, P = w.ns.InviteToast, w.ns.StakePanels
    invited(w, "ttt", 50000)
    local sits = #w:sentOf("SIT")
    w:click(T.accept); w:click(P.askNo)
    eq(#w:sentOf("SIT"), sits); eq(lastSent(w, "INR").msg.a, "no")
  end)

  it("an invitation gone while the question was open: its yes sits at the stake all the same", function()
    local w = guildWow()
    local T, P = w.ns.InviteToast, w.ns.StakePanels
    local tid = invited(w, "ttt", 50000)
    w:click(T.accept)
    w.ns.client.invites:drop(true)
    w:click(P.askYes)
    local sit = lastSent(w, "SIT")
    ok(sit, "no SIT"); eq({ sit.msg.tid, sit.msg.seat, sit.msg.sk }, { tid, 2, 50000 })
  end)

  it("a fun invitation's „Приемам“ sits at once, as today", function()
    local w = guildWow()
    local T = w.ns.InviteToast
    invited(w, "ttt", nil)
    w:click(T.accept)
    eq({ lastSent(w, "SIT").msg.seat, lastSent(w, "SIT").msg.sk }, { 2, nil })
    eq(w.ns.StakePanels.askFrame == nil or not w.ns.StakePanels.askFrame:IsShown(), true)
  end)
end)

describe("ui: the stake, the minors of fix round 1", function()
  it("a sit question does not replace the question about my asked seat (M1); „Отказ“ there accepts nothing (M5)", function()
    local w = readyWow()
    w.ns.MainWindow.show()
    local P, client = w.ns.StakePanels, w.ns.client
    local accepted = 0
    client.acceptStake = function() accepted = accepted + 1; return true end
    local tid, s = host(w, "deathroll", 20000)
    s.stakeAsk = true
    client.events:emit("stakeAsk", tid, 20000); w:advance(0)
    P.ask({ tid = C .. "#1", game = "ttt", stake = 50000, seats = { C, false } }, 2)
    eq(P.question.kind, "keep"); ok(has(P.askText:GetText(), "2g"), "the keep question was replaced")
    w:click(P.askNo)
    eq(accepted, 0); eq(P.askFrame:IsShown(), false)
  end)

  it("a staked invitation accepted while my asked seat's question is open is asked right after it (Task 11 M-a)", function()
    local w = readyWow()
    w.ns.MainWindow.show()
    local P, client = w.ns.StakePanels, w.ns.client
    local accepted, answers = 0, {}
    client.acceptStake = function() accepted = accepted + 1; return true end
    w.ns.InviteToast.acceptStaked = function(tid, sk, yes) answers[#answers + 1] = { tid, sk, yes } end
    local tid, s = host(w, "deathroll", 20000)
    s.stakeAsk = true
    client.events:emit("stakeAsk", tid, 20000); w:advance(0)
    P.askInvite({ tid = C .. "#1", game = "ttt", stake = 50000 }) -- the toast's „Приемам“
    eq(P.question.kind, "keep"); ok(has(P.askText:GetText(), "2g"), "the keep question was replaced")
    w:click(P.askYes)
    eq(accepted, 1)
    ok(P.askFrame:IsShown(), "the invitation's question is not asked"); eq(P.question.kind, "invite")
    ok(has(P.askText:GetText(), "5g"), "not the invitation's stake")
    w:click(P.askYes)
    eq(answers, { { C .. "#1", 50000, true } }); eq(P.askFrame:IsShown(), false)
  end)

  it("a client without a ledger is told why it cannot sit (M2)", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local P = w.ns.StakePanels
    tbl(w, B, 50000)
    w.ns.client.ledger = nil
    w:click(w.ns.Hall.view.tables[1].chairs[2].button)
    w:click(P.askYes)
    eq(w.ns.Hall.view.footer:GetText(), w.ns.L("refused.stake"))
  end)

  it("the „Стани“ question follows the roster while it is open (M3)", function()
    local w = readyWow()
    local TF = w.ns.TableFrame
    local tid, s = host(w, "deathroll", 50000, { B, C, D })
    w:advance(0)
    w:click(TF.view.startButton); w:advance(0)
    eq(s.status, "live")
    w:click(TF.view.standButton)
    eq(TF.view.confirm.text:GetText(), "Ако станеш сега, губиш служебно и дължиш 15g.")
    w:deliver("WHISPER", D, { v = 1, t = "STD", tid = tid }); w:advance(0)
    ok(TF.view.confirm:IsShown(), "the question went")
    eq(TF.view.confirm.text:GetText(), "Ако станеш сега, губиш служебно и дължиш 10g.")
  end)

  it("a sit question goes when its table leaves the hall (M4)", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local P = w.ns.StakePanels
    local tid = tbl(w, B, 50000)
    w:click(w.ns.Hall.view.tables[1].chairs[2].button)
    ok(P.askFrame:IsShown(), "no question")
    w:deliver("GUILD", B, { v = 1, t = "END", tid = tid, e = 1 }); w:advance(0)
    eq(P.askFrame:IsShown(), false)
  end)

  it("the gold box takes up to STAKE_MAX; a letter or more is a bad amount (M5)", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local Dlg, L = w.ns.NewTableDialog, w.ns.L
    for _, parts in ipairs({ { "5a", "" }, { "9999999", "99" }, { "5", "-1" } }) do
      Dlg.open("ttt"); w:click(Dlg.stake.options[2].frame)
      Dlg.goldBox:SetText(parts[1]); Dlg.silverBox:SetText(parts[2])
      w:click(Dlg.openButton)
      eq(w.ns.client.session, nil); eq(Dlg.error:GetText(), L("dialog.stake.bad"))
    end
    Dlg.goldBox:SetText("9999999"); Dlg.silverBox:SetText("")
    w:click(Dlg.openButton)
    eq(w.ns.client.session.stake, w.ns.Const.STAKE_MAX)
  end)

  it("the break's redraw goes with the table (M6)", function()
    local w = readyWow()
    local TF = w.ns.TableFrame
    local _, s = host(w, "deathroll", 10000, { B })
    w:advance(0)
    w:click(TF.view.startButton); w:advance(0)
    s:play(s.state.turn, { k = "roll", n = 1, max = s.state.max, src = "seen" }); w:advance(0)
    ok(TF.breakTimer, "no break timer")
    w.ns.client:stand(); w:advance(0)
    eq(TF.breakTimer, nil)
  end)
end)

-- Stage F2, Task 9: the staked table of Сантасе, Белот and Табла.

-- The running match at my table s (I host it) ends, `winner` (a seat; Белот: a
-- team) the winner, as the event that ends it does on my client: its
-- "result", the event's number, the hook of the extension stakes, the redraw.
local function over(w, s, winner)
  s.state.phase, s.state.winner = "match", winner
  s:noteResult()
  s.seq = s.seq + 1
  w.ns.Ext.stakes.applied(s, 0, { k = "end" })
  w.ns.Session.emit(s.client)
  w:advance(0)
end

-- The visible lines of the bill, colour codes stripped, each with its mark ("" for none).
local function billLines(v)
  local out = {}
  for _, line in ipairs(v.bill.lines) do
    if line.text:IsVisible() then out[#out + 1] = { plain(line.text:GetText()), line.mark:IsVisible() and line.mark:GetText() or "" } end
  end
  return out
end

describe("ui: the staked table of Сантасе, Белот and Табла (F2)", function()
  it("the question at a Белот chair names both prices", function()
    local w = readyWow()
    w.ns.MainWindow.show()
    local P, L = w.ns.StakePanels, w.ns.L
    eq(L("stake.ask.team", "1g", "1g", "1g", "2g"), "Залогът е 1g. Ако отборът ти загуби, плащаш 1g на един от противниците. "
      .. "Ако напуснеш играта, плащаш по 1g и на двамата, общо 2g. Партньорът ти не дължи нищо.")
    tbl(w, B, 10000, "belot", { B, false, false, false })
    w:click(w.ns.Hall.view.tables[1].chairs[2].button)
    ok(P.askFrame:IsShown(), "no question")
    eq(P.askText:GetText(), L("stake.ask.team", "1g", "1g", "1g", "2g"))
    w:click(P.askNo)
    for _, game in ipairs({ "santase", "tabla" }) do
      P.ask({ tid = C .. "#1", game = game, stake = 10000 }, 2)
      eq(P.askText:GetText(), L("stake.ask.text", "1g", "1g"), game)
      w:click(P.askNo)
    end
  end)

  it("a card table warns about the dealer", function()
    local w = readyWow()
    local P, L = w.ns.StakePanels, w.ns.L
    eq(L("stake.ask.cards"), "Аддонът на раздаващия знае тестето на ръката, която раздава. Играй карти за голд с хора, на които вярваш.")
    local function asked(card, what)
      ok(P.askFrame:IsShown(), "no question: " .. what)
      eq(P.askWarn:IsVisible(), card, what)
      -- the text, the leave line and the warning clear the buttons, whatever their height
      local need = 52 + P.askText:GetStringHeight() + 10 + P.askLeave:GetStringHeight() + (card and 10 + P.askWarn:GetStringHeight() or 0)
      local gap = P.askFrame:GetHeight() - 48 - need
      ok(gap >= 20, what .. ": the text runs into the buttons, gap " .. gap)
      ok(P.askFrame:GetHeight() >= (card and 200 + 44 or 200), what)
      if card then
        eq(P.askWarn:GetText(), L("stake.ask.cards"))
        eq(P.askWarn.points[1], { "TOPLEFT", P.askLeave, "BOTTOMLEFT", 0, -10 })
      end
    end
    for _, game in ipairs({ "santase", "belot", "tabla", "ttt", "deathroll", "belot" }) do
      P.ask({ tid = C .. "#1", game = game, stake = 10000 }, 2)
      asked(game == "santase" or game == "belot", game)
      w:click(P.askNo)
    end
    for _, game in ipairs({ "belot", "tabla" }) do
      P.askInvite({ tid = C .. "#2", game = game, stake = 10000 })
      asked(game == "belot", "invitation " .. game)
      w:click(P.askNo)
    end
    -- The asked seat's question.
    local tid, s = host(w, "santase", 10000)
    s.stakeAsk = true
    w.ns.client.acceptStake = function() return true end
    w.ns.client.events:emit("stakeAsk", tid, 10000); w:advance(0)
    eq(P.question.kind, "keep")
    asked(true, "asked seat")
  end)

  it("„Стани“ in a staked Белот match names what I owe", function()
    local w = readyWow()
    local TF, L = w.ns.TableFrame, w.ns.L
    local _, s = host(w, "belot", 10000, { B, C, D })
    eq(s.status, "live")
    w:click(TF.view.standButton)
    ok(TF.view.confirm:IsShown(), "no question")
    eq(TF.view.confirm.text:GetText(), L("stand.stake.team", "1g", "2g"))
    eq(TF.view.confirm.text:GetText(), "Ако станеш сега, отборът ти губи. Дължиш по 1g на двамата противници, общо 2g. Партньорът ти не дължи нищо.")
    ok(TF.view.confirm:GetHeight() >= TF.view.confirm.text:GetStringHeight() + 48, "the text runs into the buttons")
    w:click(TF.view.confirm.no)
    w.ns.client:stand(); w:advance(0)
    local _, s2 = host(w, "santase", 10000, { B })
    eq(s2.status, "live")
    w:click(TF.view.standButton)
    eq(TF.view.confirm.text:GetText(), L("stand.stake", "1g"))
    eq(TF.view.confirm:GetHeight(), 82)
  end)

  it("the bill of a Белот match shows two rows", function()
    local w = readyWow()
    local L = w.ns.L
    local _, s = host(w, "belot", 10000, { B, C, D })
    local v = w.ns.TableFrame.view
    over(w, s, 1) -- my team (seats 1 and 3) won: seat 2 owes me, seat 4 my partner
    ok(v.bill:IsVisible(), "no bill"); eq(w.ns.StakePanels.shown, true)
    eq(v.bill.title:GetText(), "Сметката")
    eq(billLines(v), { { "Мария дължи на Иван 1g", L("bill.pending") }, { "Дара дължи на Тодор 1g", L("bill.pending") } })
    eq(v.bill:GetHeight(), 32 + 2 * 18)
    word(w, B, 1, myClaim(w, B), "C")
    eq(billLines(v), { { "Мария дължи на Иван 1g", "" }, { "Дара дължи на Тодор 1g", L("bill.pending") } })
    eq(w.ns.TableFrame.built.belot.text:IsVisible(), false)
  end)

  it("the bill of a leave names the leaver and its two debts", function()
    local w = readyWow()
    local L = w.ns.L
    eq(L("bill.left.team", "Мария"), "Мария напусна играта и плаща на двамата противници. Партньорът в отбора не дължи нищо.")
    local tid = host(w, "belot", 10000, { B, C, D })
    local v = w.ns.TableFrame.view
    w:deliver("WHISPER", B, { v = 1, t = "STD", tid = tid }); w:advance(0) -- seat 2: owes seats 1 and 3, never its partner in 4
    ok(v.bill:IsVisible(), "no bill")
    eq(billLines(v), { { L("bill.left.team", "Мария"), "" }, { "Мария дължи на Иван 1g", L("bill.pending") },
                       { "Мария дължи на Тодор 1g", L("bill.pending") } })
    eq(v.bill:GetHeight(), 32 + 4 * 18) -- the leave line takes two rows
    -- My partner leaves: I owe nothing and am owed nothing, so no bill and the view's own line.
    w.ns.client:stand(); w:advance(2) -- another table (its id has another second in it)
    local tid2 = host(w, "belot", 10000, { B, C, D })
    ok(tid2 ~= tid, "the same table id")
    w:deliver("WHISPER", C, { v = 1, t = "STD", tid = tid2 }); w:advance(0)
    eq(w.ns.StakePanels.shown, false); eq(v.bill:IsVisible(), false)
    local f = w.ns.TableFrame.built.belot
    ok(f.text:IsVisible(), "no end line"); ok(has(f.text:GetText(), "Тодор Ангелов"), plain(f.text:GetText()))
  end)

  it("a guest's bill says when the next match may begin", function()
    local w = readyWow()
    local TF, L = w.ns.TableFrame, w.ns.L
    eq(L("bill.again.wait", 25), "Домакинът може да започне нова игра за същия залог след 25 сек. Не искаш ли, натисни „Към залата“.")
    eq(L("bill.again.ready"), "Домакинът може да започне нова игра за същия залог. Не искаш ли, натисни „Към залата“.")
    local _, s = host(w, "santase", 10000, { B })
    local v = TF.view
    over(w, s, 1)
    w:advance(5)
    s.role = "player"; TF.render() -- a guest's view of the same table
    local lines = billLines(v)
    eq(lines[#lines], { L("bill.again.wait", 25), "" })
    eq(v.bill.rematch:IsVisible(), false); eq(v.startButton:IsVisible(), false)
    eq(v.bill:GetHeight(), 32 + 3 * 18) -- the row, and the guest's line on two
    w:advance(1.5)
    lines = billLines(v)
    eq(lines[#lines], { L("bill.again.wait", 24), "" })
    -- The host: „Реванш на същата маса“ is „Нова игра“; the start button dim inside the break.
    s.role = "host"; TF.render()
    eq(#billLines(v), 1)
    ok(v.bill.rematch:IsVisible(), "no rematch for the host"); eq(v.bill.rematch.text:GetText(), "Реванш на същата маса")
    local started, start = 0, TF.startGame
    TF.startGame = function() started = started + 1 end
    w:click(v.bill.rematch)
    eq(started, 1)
    TF.startGame = start
    ok(v.startButton:IsVisible() and v.startButton:IsEnabled(), "no start button to click")
    eq(v.startButton:GetAlpha(), 0.5)
    w:advance(w.ns.Stakes.gap(s) - 6.5 + 0.1) -- the break is over: drawn again by itself
    eq(v.startButton:GetAlpha(), 1)
    s.role = "player"; TF.render()
    lines = billLines(v)
    eq(lines[#lines], { L("bill.again.ready"), "" })
    -- A seated host silent for SILENT_AFTER: the line names the seat the start waits for.
    s.lastHeard[ME] = nil
    s.lastHeard[B] = w.ns.client.env.now() - w.ns.Const.SILENT_AFTER
    TF.render()
    lines = billLines(v)
    eq(lines[#lines], { L("bill.again.silent", "Мария"), "" })
  end)

  it("after a leave the opponents' bill waits for a player to sit", function()
    local w = readyWow()
    local TF, L = w.ns.TableFrame, w.ns.L
    local tid, s = host(w, "belot", 10000, { B, C, D })
    w:deliver("WHISPER", B, { v = 1, t = "STD", tid = tid }); w:advance(0)
    s.role, s.status = "player", "live"; TF.render() -- a guest's table stays live while a seat is empty
    local lines = billLines(TF.view)
    eq(lines[#lines], { L("bill.again.short"), "" })
    eq(L("bill.again.short"), "Домакинът може да започне нова игра, щом на масата седне играч. Не искаш ли, натисни „Към залата“.")
  end)

  it("the guest's countdown ends with the break, drawn again by itself", function()
    local w = readyWow()
    local TF, L = w.ns.TableFrame, w.ns.L
    local _, s = host(w, "tabla", 10000, { B })
    over(w, s, 2)
    s.role = "player"; TF.render()
    local lines = billLines(TF.view)
    eq(lines[#lines], { L("bill.again.wait", 30), "" })
    w:advance(30.1)
    lines = billLines(TF.view)
    eq(lines[#lines], { L("bill.again.ready"), "" })
    eq(TF.countTimer, nil)
  end)
end)

-- Stage F3, Task 10: a cash table (staked Холдем) in the dialog, the question with the buy-in, the hall.
describe("ui: a cash table in the dialog and the question", function()
  local Play = require("play")
  local SEATS = 6

  -- A guild world where Холдем takes a stake (Play.staked, undone after the test).
  local function cash(fn)
    local w = guildWow()
    Play.staked(w.ns, "holdem")
    w.ns.MainWindow.show()
    local ok_, err = pcall(fn, w)
    Play.restore()
    if not ok_ then error(err, 0) end
  end

  local function cashTable(w, hostName, o)
    local seats = { hostName }
    for i = 2, SEATS do seats[i] = false end
    local tid = hostName .. "#1"
    w:member(hostName)
    w:deliver("GUILD", hostName, { v = 1, t = "TBL", tid = tid, g = "holdem", h = hostName, e = 1, ac = "guild", tn = 45,
                                   st = "open", s = seats, w = 0, sk = 1000, o = o or { betting = "nl", blinds = 10, rebuy = "top" } })
    w:advance(0)
    return tid
  end

  local function stakeChosen(w, Dlg)
    Dlg.open("holdem")
    w:click(Dlg.stake.options[2].frame)
  end

  it("the dialog of a staked Холдем hides the amount and the stack and offers the rebuy mode", function()
    cash(function(w)
      local Dlg, L = w.ns.NewTableDialog, w.ns.L
      Dlg.open("holdem")
      eq(#Dlg.stake.options, 2)
      stakeChosen(w, Dlg)
      eq(Dlg.stake.value, "gold")
      eq(Dlg.amount:IsVisible(), false); eq(Dlg.goldBox:IsVisible(), false)
      local ids = {}
      for id in pairs(Dlg.options) do ids[#ids + 1] = id end
      table.sort(ids)
      eq(ids, { "betting", "blinds", "rebuy" }); eq(Dlg.options.rebuy.value, "bust")
      eq(#w:texts("Докупуване"), 1); eq(#w:texts("Стек"), 0)
      eq(#w:texts("Когато свършат чиповете"), 1); eq(#w:texts("Винаги до входа"), 1)
      eq(Dlg.rangeText:GetText(), L("dialog.cash.range", "5s", "10s", "4g", "10g"))
      eq(Dlg.rangeText:GetText(), "Блайндове 5s/10s. Всеки сяда с вход между 4g и 10g.")
      w:click(Dlg.options.blinds.options[2].frame)
      eq(Dlg.rangeText:GetText(), "Блайндове 10s/20s. Всеки сяда с вход между 8g и 20g.")
    end)
  end)

  it("its table opens at the stake of its blinds", function()
    cash(function(w)
      local Dlg = w.ns.NewTableDialog
      stakeChosen(w, Dlg)
      w:click(Dlg.options.blinds.options[2].frame)
      w:click(Dlg.options.rebuy.options[3].frame)
      local sent, client = nil, w.ns.client
      local real = client.openTable
      client.openTable = function(self, o) sent = o; return real(self, o) end
      w:click(Dlg.openButton)
      eq(sent.stake, 2000); eq(sent.opt, { betting = "nl", blinds = 20, rebuy = "top" })
      eq(sent.opt.stack, nil)
      ok(client.session, "no table"); eq(client.session.stake, 2000)
      eq(lastSent(w, "TBL").msg.sk, 2000)
      w:advance(0)
      local meta = w.ns.TableFrame.view.meta:GetText()
      ok(has(meta, "Докупуване Винаги до входа"), meta)
      eq(has(meta, "opt.holdem"), false); eq(has(meta, "optv.holdem"), false)
    end)
  end)

  it("a fun Холдем dialog is unchanged", function()
    cash(function(w)
      local Dlg = w.ns.NewTableDialog
      Dlg.open("holdem")
      local ids = {}
      for id in pairs(Dlg.options) do ids[#ids + 1] = id end
      table.sort(ids)
      eq(ids, { "betting", "blinds", "stack" }); eq(Dlg.set.count, 3)
      eq(Dlg.rangeText, nil)
      eq(Dlg.frame:GetHeight(), 330 + 34 * 3)
      local sent
      w.ns.client.openTable = function(_, o) sent = o; return nil, "busy" end
      w:click(Dlg.openButton)
      eq(sent.opt, { betting = "nl", blinds = 10, stack = 100 }); eq(sent.stake, nil)
      -- to the stake and back: the stack is there again, the rebuy gone
      w:click(Dlg.stake.options[2].frame); w:click(Dlg.stake.options[1].frame)
      eq(Dlg.stake.value, "none"); eq(Dlg.options.stack.value, 100); eq(Dlg.options.rebuy, nil)
      w:click(Dlg.openButton)
      eq(sent.opt, { betting = "nl", blinds = 10, stack = 100 }); eq(sent.stake, nil)
    end)
  end)

  it("the question shows the range, the mode and the dealer warning, and steps the buy-in from 40 to 100", function()
    cash(function(w)
      local P, L = w.ns.StakePanels, w.ns.L
      local tid = cashTable(w, B)
      w:click(w.ns.Hall.view.tables[1].chairs[2].button)
      ok(P.askFrame:IsShown(), "no question")
      eq(P.askText:GetText(), L("stake.ask.cash", "5s", "10s", "4g", "10g"))
      eq(P.askLeave:GetText(), L("stake.ask.rebuy.top", "10g"))
      ok(P.askWarn:IsShown(), "no dealer warning")
      ok(has(P.askWarn:GetText(), L("stake.ask.cards")), "S1 missing")
      ok(has(P.askWarn:GetText(), L("stake.ask.void")), "C9 missing")
      ok(P.buyRow:IsShown(), "no stepper")
      eq(P.buyText:GetText(), "Вход: 100 големи блайнда = 10g")
      for _ = 1, 4 do w:click(P.buyMinus) end
      eq(P.buyText:GetText(), "Вход: 60 големи блайнда = 6g")
      for _ = 1, 5 do w:click(P.buyMinus) end
      eq(P.buyText:GetText(), L("stake.ask.buy", 40, "4g"))
      for _ = 1, 9 do w:click(P.buyPlus) end
      eq(P.buyText:GetText(), L("stake.ask.buy", 100, "10g"))
      ok(P.askFrame:GetHeight() >= 52 + P.askText:GetStringHeight() + P.askLeave:GetStringHeight() + P.askWarn:GetStringHeight() + 68)
      -- the rebuy line of each mode
      w:click(P.askNo)
      for mode, host in pairs({ none = C, bust = D }) do
        local other = cashTable(w, host, { betting = "nl", blinds = 10, rebuy = mode })
        for _, t in ipairs(w.ns.Hall.view.tables) do
          if t.tid == other and t.frame:IsVisible() then w:click(t.chairs[2].button) end
        end
        eq(P.askLeave:GetText(), L("stake.ask.rebuy." .. mode))
        w:click(P.askNo)
      end
    end)
  end)

  it("its yes sits with the stake and the buy-in", function()
    cash(function(w)
      local P = w.ns.StakePanels
      local tid = cashTable(w, B)
      local got
      w.ns.client.sit = function(_, ...) got = { ... } end
      w:click(w.ns.Hall.view.tables[1].chairs[2].button)
      for _ = 1, 4 do w:click(P.buyMinus) end
      w:click(P.askYes)
      eq(got, { tid, 2, 1000, 600 }); eq(P.askFrame:IsShown(), false)
      -- the next question starts at 100 again
      w:click(w.ns.Hall.view.tables[1].chairs[2].button)
      eq(P.buyText:GetText(), "Вход: 100 големи блайнда = 10g")
      w:click(P.askYes)
      eq(got, { tid, 2, 1000, 1000 })
    end)
  end)

  it("an invitation's yes keeps the wish", function()
    cash(function(w)
      local P, client = w.ns.StakePanels, w.ns.client
      local tid = cashTable(w, B)
      local calls = {}
      client.wantBuy = function(_, t, n) calls[#calls + 1] = { "want", t, n } end
      client.answerInvite = function(_, t, a) calls[#calls + 1] = { "answer", t, a } end
      client.invites.received = { tid = tid, game = "holdem", host = B, seats = 6, expires = 1e9, stake = 1000 }
      P.askInvite({ tid = tid, game = "holdem", stake = 1000 })
      ok(P.buyRow:IsShown(), "no stepper")
      for _ = 1, 2 do w:click(P.buyMinus) end
      w:click(P.askYes)
      eq(calls, { { "want", tid, 800 }, { "answer", tid, "yes" } })
      calls = {}
      P.askInvite({ tid = tid, game = "holdem", stake = 1000 })
      w:click(P.askNo)
      eq(calls, { { "answer", tid, "no" } })
    end)
  end)

  it("the question of an asked seat has no stepper and no wish", function()
    cash(function(w)
      local P, client = w.ns.StakePanels, w.ns.client
      local tid = assert(client:openTable{ game = "holdem", access = "guild", turn = 45, stake = 1000, opt = { blinds = 10 } })
      w:advance(0)
      local s = client.session
      s.stakeAsk = true
      local accepted, wished = 0, 0
      client.acceptStake = function() accepted = accepted + 1; return true end
      client.wantBuy = function() wished = wished + 1 end
      client.events:emit("stakeAsk", tid, 1000); w:advance(0)
      ok(P.askFrame:IsShown(), "no question")
      eq(P.buyRow:IsShown(), false)
      w:click(P.askYes)
      eq({ accepted, wished }, { 1, 0 })
    end)
  end)

  -- Stage F3, Task 8: the real client behind the question (no spy): the chair's yes and an invitation's yes.
  it("the real client takes the buy-in of a chair's yes and of an invitation's yes", function()
    cash(function(w)
      local P, client = w.ns.StakePanels, w.ns.client
      local tid = cashTable(w, B)
      w:click(w.ns.Hall.view.tables[1].chairs[2].button)
      for _ = 1, 4 do w:click(P.buyMinus) end
      w:click(P.askYes)
      local sit = lastSent(w, "SIT")
      eq({ sit.msg.tid, sit.msg.seat, sit.msg.sk }, { tid, 2, 1000 })
      eq(client.cashWant, { tid = tid, n = 600 })
      client:stand(); w:advance(0)
      eq(client.cashWant, nil)
      local seats = { B, false, false, false, false, false }
      w:deliver("WHISPER", B, { v = 1, t = "INV", tid = tid, g = "holdem", h = B, s = seats, sk = 1000 })
      w:advance(0)
      w:click(w.ns.InviteToast.accept)
      ok(P.buyRow:IsShown(), "no stepper")
      for _ = 1, 2 do w:click(P.buyMinus) end
      w:click(P.askYes)
      sit = lastSent(w, "SIT")
      eq({ sit.msg.tid, sit.msg.sk }, { tid, 1000 })
      eq(lastSent(w, "INR").msg.a, "yes")
      eq(client.cashWant, { tid = tid, n = 800 })
    end)
  end)

  it("the hall writes the blinds of a cash table", function()
    cash(function(w)
      local view = w.ns.Hall.view
      local staked = cashTable(w, B)
      for i = 1, 8 do tbl(w, "Гост " .. i) end
      eq(w.ns.Hall.mode, "list")
      local found
      for _, r in ipairs(view.rows) do if r.frame:IsVisible() and r.tid == staked then found = r end end
      ok(found, "no row")
      ok(has(found.sub:GetText(), "5s/10s"), found.sub:GetText()); eq(has(found.sub:GetText(), "Залог"), false)
    end)
  end)

  it("the rebuy labels are read from opt.holdem.rebuy and optv.holdem.rebuy.*, none shows its key", function()
    local w = guildWow()
    local L = w.ns.L
    eq(L("opt.holdem.rebuy"), "Докупуване")
    eq(L("optv.holdem.rebuy.none"), "Без"); eq(L("optv.holdem.rebuy.bust"), "Когато свършат чиповете"); eq(L("optv.holdem.rebuy.top"), "Винаги до входа")
    eq(w.ns.W.optionText("holdem", "rebuy", "top"), "Винаги до входа")
    for _, k in ipairs({ "dialog.cash.range", "stake.ask.cash", "stake.ask.buy", "stake.ask.void", "hall.blinds",
                         "stake.ask.rebuy.none", "stake.ask.rebuy.bust", "stake.ask.rebuy.top" }) do
      ok(L(k) ~= k, "no text for " .. k)
    end
  end)
end)
