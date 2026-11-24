local Wow = require("wow")

local ME, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"
local BOT = "Bot Ivanov"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired.
local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

-- Bots on and heard (their HI reached me).
local function withBots()
  local w = guildWow()
  w:slash("bots")
  w:advance(0); w:advance(0)
  return w
end

local function color(fs) return { fs:GetTextColor() } end

local function rgb(w, token)
  local c = w.ns.Theme.color[token]
  return { c[1], c[2], c[3], 1 }
end

local MAGE, PRIEST = { 0.25, 0.78, 0.92, 1 }, { 1, 1, 1, 1 }

-- `text` without inline colour codes (|cAARRGGBB … |r).
local function plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Visible font strings whose text, colour codes stripped, contains the plain `needle`.
local function plainTexts(w, needle)
  local out = {}
  for _, f in ipairs(w.frames) do
    for _, r in ipairs(f.regions) do
      if r.objectType == "FontString" and r.text and r:IsVisible() and plain(r.text):find(needle, 1, true) then
        out[#out + 1] = r
      end
    end
  end
  return out
end

-- I host a Death Roll table from 100; „Bot Ivanov“ sits through the „Покани“
-- picker and I press „Започни“: my turn first.
local function play()
  local w = withBots()
  w.ns.client:openTable{ game = "deathroll", access = "guild", turn = 45, opt = { start = 100 } }
  w:advance(0)
  local v = w.ns.TableFrame.view
  w:click(v.inviteButton)
  local row
  for _, r in ipairs(v.picker.rows) do
    if r.frame:IsVisible() and r.peerName == BOT then row = r end
  end
  assert(row, "no row for the bot in the picker")
  w:click(row.frame)
  w:advance(2)
  w:click(v.startButton)
  w:advance(0)
  return w
end

local function setup()
  local w = play()
  return w, w.ns.TableFrame.built.deathroll, w.ns.TableFrame.views.deathroll
end

-- A real player says HI (with a GUID) so Presence knows him.
local function hello(w, name, guid)
  w:member(name)
  w:deliver("GUILD", name, { v = 1, t = "HI", ver = "0.1.0", cls = "PRIEST", id = guid })
end

-- I leave my bot table; B (real) hosts a live game from 100 in which I hold
-- seat 2 and B is on turn: its TBL, my request and the SNP that seats me.
-- `seats` and `st` replace that table's seats and game state.
local function seatedAtB(w, seats, st)
  w.ns.client:stand(); w:advance(0)
  hello(w, B, "Player-1-00000002")
  local tid = B .. "#1"
  local tbl = { tid = tid, g = "deathroll", h = B, e = 1, ac = "guild", tn = 45, st = "live",
                s = seats or { B, ME, false, false, false }, w = 0, o = { start = 100 } }
  local announce = { v = 1, t = "TBL" }
  for k, v in pairs(tbl) do announce[k] = v end
  w:deliver("GUILD", B, announce)
  w.ns.client:sit(tid, 2) -- a snapshot of a table I never asked for is not adopted
  st = st or { players = { 1, 2 }, turn = 1, start = 100, max = 100, rolls = {}, phase = "play" }
  w:deliver("WHISPER", B, { v = 1, t = "SNP", tid = tid, e = 1, q = 1, tbl = tbl, st = st, left = 45 })
  w:advance(0)
  local s = w.ns.client.session
  assert(s and s.tid == tid and s.mySeat == 2, "not seated at B's table")
  return tid
end

-- B's event: seat 1 rolled 40 of 100 and B saw it.
local function bRolled40(w, tid)
  w:deliver("WHISPER", B, { v = 1, t = "EV", tid = tid, e = 1, q = 2, seat = 1, left = 45,
                            a = { k = "roll", n = 40, max = 100, src = "seen" } })
end

describe("ui: Death Roll view", function()
  it("my turn: „Хвърли“ with the range makes one server roll and waits", function()
    local w, V, View = setup()
    eq(w.ns.client.session.state.turn, 1)
    ok(V.rollButton:IsVisible(), "no roll button"); eq(V.rollButton.text:GetText(), "Хвърли")
    eq(#w:texts("от 1 до 100"), 1)
    eq(w.rolls, {})
    w:click(V.rollButton); w:advance(0)
    eq(w.rolls, { { 1, 100 } }); eq(V.rollButton:IsEnabled(), false); eq(#w:texts("Хвърляне…"), 1)
    eq(#View.cells(w.ns.client.session), 2) -- start and next
  end)

  it("the roll line from chat becomes a ladder entry in my class colour; the bot's roll is tagged „· маса“", function()
    local w, V, View = setup()
    local L = w.ns.L
    w.ns.client.env.random = function() return 30 end -- the bot's table roll
    w:click(V.rollButton); w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-100)"); w:advance(0)
    local cells = View.cells(w.ns.client.session)
    eq(cells[1], { kind = "start", n = 100 })
    eq({ cells[2].kind, cells[2].n, cells[2].seat, cells[2].tag }, { "roll", 57, 1, nil })
    eq(cells[3].kind, "next"); eq(cells[3].seat, 2); eq(cells[3].name, BOT)
    eq(V.cells[1].number:GetText(), "100"); eq(V.cells[1].label:GetText(), "старт")
    eq(V.cells[2].number:GetText(), "57"); eq(color(V.cells[2].number), MAGE)
    eq(V.cells[2].label:GetText(), "Ти")
    eq(V.cells[3].number:GetText(), "?"); eq(V.cells[3].number:GetAlpha(), 0.35)
    eq(color(V.cells[3].number), rgb(w, "oMark")); eq(V.cells[3].label:GetText(), "Bot")
    local wait = plainTexts(w, "Изчакай Bot Ivanov…")
    eq(#wait, 1); eq(wait[1]:GetText(), "Изчакай |cffffffffBot Ivanov|r…")
    eq(V.rollButton:IsVisible(), false)
    eq(#w:texts(L("deathroll.caption")), 1)
    w:advance(2)
    cells = View.cells(w.ns.client.session)
    eq({ cells[3].n, cells[3].tag }, { 30, "table" }); eq(color(V.cells[3].number), PRIEST)
    eq(#w:texts("· маса"), 1); eq(V.cells[3].label:GetText(), "Bot · маса")
    w:hover(V.cells[3].frame); eq(w.G.GameTooltip.lines[1], L("deathroll.tip.table"))
    eq({ V.cells[1].number:GetFont() }, { w.ns.Theme.font.heading, 30, "" })
    eq(select(2, V.cells[2].number:GetFont()), 28); eq(select(2, V.cells[3].number:GetFont()), 26)
    eq(#w:texts("от 1 до 30"), 1) -- my turn again
  end)

  it("a roll I did not see gets „?“, a different number gets „!“", function()
    local w, _, View = setup()
    local tid = seatedAtB(w)
    bRolled40(w, tid); w:advance(6)
    local cells = View.cells(w.ns.client.session)
    eq(cells[2].n, 40); eq(cells[2].tag, "unseen")
    local V = w.ns.TableFrame.built.deathroll
    eq(V.cells[2].label:GetText(), "Мария?")
    w:hover(V.cells[2].frame); eq(w.G.GameTooltip.lines[1], w.ns.L("deathroll.tip.unseen"))

    w = setup()
    tid = seatedAtB(w)
    w:fire("CHAT_MSG_SYSTEM", "Мария rolls 41 (1-100)")
    bRolled40(w, tid); w:advance(6)
    cells = View.cells(w.ns.client.session)
    eq(cells[2].tag, "mismatch")
    V = w.ns.TableFrame.built.deathroll
    eq(V.cells[2].label:GetText(), "Мария|cffa3161c!|r")
    w:hover(V.cells[2].frame); eq(w.G.GameTooltip.lines[1], w.ns.L("deathroll.tip.mismatch"))
  end)

  it("no echo within 3 s: the hint to type /roll by hand, and typing it works", function()
    local w, V = setup()
    w:click(V.rollButton); w:advance(3.1)
    eq(#w:texts("Не стана. Напиши /roll 100 в чата."), 1)
    eq(V.rollButton:IsEnabled(), true); eq(V.rollButton.text:GetText(), "Хвърли")
    w:fire("CHAT_MSG_SYSTEM", "Иван rolls 9 (1-100)"); w:advance(0)
    eq(w.ns.client.session.state.max, 9)
    eq(#w:texts("Не стана."), 0)
  end)

  it("a roll the host of a staked game never played: the hint to stay in the group and roll again", function()
    local w, V = setup()
    local s = w.ns.client.session
    s.rollUnheard = true; w.ns.client.events:emit("session", s); w:advance(0)
    eq(#w:texts("Домакинът не видя хвърлянето ти. Остани в групата и хвърли пак."), 1); eq(#w:texts("Не стана."), 0)
    eq(V.rollButton:IsEnabled(), true)
    s.rollUnheard = nil; w.ns.client.events:emit("session", s); w:advance(0)
    eq(#w:texts("Домакинът не видя"), 0)
  end)

  it("my turn at a staked game outside the host's group: a warning before „Хвърли“", function()
    local w = setup()
    seatedAtB(w, nil, { players = { 1, 2 }, turn = 2, start = 100, max = 100, rolls = {}, phase = "play" })
    local client = w.ns.client
    local s = client.session
    s.state.staked = true; client.events:emit("session", s); w:advance(0)
    eq(#w:texts(w.ns.L("roll.nohost")), 1)
    -- The GUID the host announced in its HI does not count: only my own roster.
    w.group["Player-1-00000002"] = true; client.events:emit("session", s); w:advance(0)
    eq(#w:texts(w.ns.L("roll.nohost")), 1)
    w.partyNames["Мария Стоянова"] = true; client.events:emit("session", s); w:advance(0)
    eq(#w:texts(w.ns.L("roll.nohost")), 0)
  end)

  it("a long ladder keeps the newest rolls behind „…“; rolling 1 ends it with the loser named", function()
    local w, V, View = setup()
    local s = w.ns.client.session
    for n = 99, 93, -1 do
      s:play(s.state.turn, { k = "roll", n = n, max = s.state.max, src = "ask" })
    end
    w:advance(0)
    local cells = View.cells(s)
    eq(#cells, 7); eq(cells[1].kind, "more"); eq(cells[7].kind, "next")
    eq({ cells[2].n, cells[6].n }, { 97, 93 })
    eq(V.cells[1].number:GetText(), "…")
    eq(#s.state.rolls, 7); eq(s.state.turn, 2)
    s:play(2, { k = "roll", n = 1, max = 93, src = "ask" })
    w:advance(0)
    cells = View.cells(s)
    eq(#cells, 7); eq(cells[1].kind, "more"); eq(cells[7].n, 1)
    local lost = plainTexts(w, "Bot Ivanov хвърли 1 и губи!")
    eq(#lost, 1); eq(color(lost[1]), rgb(w, "gold"))
    -- the loser's name in his class colour (PRIEST) inside the gold line
    eq(lost[1]:GetText(), "|cffffffffBot Ivanov|r хвърли 1 и губи!")
    eq(lost[1]:GetText(), w.ns.L("deathroll.lost", w.ns.W.colored(w.ns.client, BOT)))
    eq(V.rollButton:IsVisible(), false)
    eq(select(2, V.cells[7].number:GetFont()), 34); eq(color(V.cells[7].number), rgb(w, "oMark"))
    eq(V.cells[7].number:GetText(), "1")
  end)

  it("a game everyone else left ends without a loser", function()
    local w, V = setup()
    local s = w.ns.client.session
    for _, bot in ipairs(w.ns.bots.list) do
      if bot.env.me == BOT then bot:stand() end
    end
    w:advance(1)
    eq(s.seats[2], false); eq(s.state.phase, "over"); eq(s.state.loser, nil)
    eq(#w:texts("Играта свърши без губещ."), 1); eq(V.rollButton:IsVisible(), false)
  end)

  it("a newcomer on the chair of the loser who left is neither the loser nor the first to roll", function()
    local w, V, View = setup()
    local s = w.ns.client.session
    s:play(1, { k = "roll", n = 50, max = 100, src = "ask" })
    s:play(2, { k = "roll", n = 1, max = 50, src = "ask" })
    w:advance(0)
    eq(#plainTexts(w, "Bot Ivanov хвърли 1 и губи!"), 1)
    for _, bot in ipairs(w.ns.bots.list) do
      if bot.env.me == BOT then bot:stand() end
    end
    w:advance(1)
    hello(w, B, "Player-1-00000002")
    w:deliver("WHISPER", B, { v = 1, t = "SIT", tid = s.tid, seat = 2 }); w:advance(0)
    eq(s.seats[2], B)
    local cells = View.cells(s)
    eq({ cells[2].seat, cells[2].name }, { 1, ME }); eq({ cells[3].seat, cells[3].name }, { 2, nil })
    eq(plain(V.cells[3].label:GetText()):find("Мария", 1, true), nil)
    eq(#plainTexts(w, "хвърли 1 и губи!"), 0)
    ok(w.ns.client:startGame()); w:advance(0)
    eq(s.state.turn, 1)
  end)

  it("the rolls of my chair from before I sat down are not mine", function()
    local w, V, View = setup()
    local st = { players = { 1, 3 }, turn = 1, start = 100, max = 60, phase = "play",
                 rolls = { { seat = 2, n = 80, max = 100, src = "seen" }, { seat = 3, n = 60, max = 80, src = "seen" } } }
    seatedAtB(w, { B, ME, C, false, false }, st)
    local s = w.ns.client.session
    local cells = View.cells(s)
    eq({ cells[2].seat, cells[2].name }, { 2, nil }); eq({ cells[3].seat, cells[3].name }, { 3, C })
    eq(plain(V.cells[2].label:GetText()):find(w.ns.L("deathroll.you"), 1, true), nil)
    eq(plain(V.cells[3].label:GetText()):sub(1, 4), "Kiro")
  end)

  it("the group line names who is outside my group, or why I cannot invite", function()
    local w, V = setup()
    local L, tid = w.ns.L, w.ns.client.session.tid
    hello(w, B, "Player-1-00000002")
    w:deliver("WHISPER", B, { v = 1, t = "SIT", tid = tid, seat = 3 }); w:advance(0)
    eq(w.ns.client.session.seats[3], B)
    local line = plainTexts(w, "Не си в група с")
    eq(#line, 1); eq(plain(line[1]:GetText()):sub(1, #"Не си в група с Мария"), "Не си в група с Мария")
    -- „Мария“ in her class colour (PRIEST, white here) inside the oMark line.
    eq(line[1]:GetText(), L("deathroll.group.missing", "|cffffffffМария|r"))
    eq(line[1]:GetText(), L("deathroll.group.missing", w.ns.W.colored(w.ns.client, B, "Мария")))
    eq(color(line[1]), rgb(w, "oMark"))
    w.party = { grouped = true, leader = false, raid = false, size = 2 }
    hello(w, C, "Player-1-00000003")
    w:deliver("WHISPER", C, { v = 1, t = "SIT", tid = tid, seat = 4 }); w:advance(0)
    eq(w.ns.client.session.partyWhy, "notleader")
    eq(#w:texts(L("deathroll.group.notleader")), 1); eq(#plainTexts(w, "Не си в група с"), 0)
    ok(V:IsVisible(), "view hidden")
  end)

  it("a player who sat down mid-game is marked „от следващата игра“", function()
    local w, _, View = setup()
    local s = w.ns.client.session
    s.seats[3] = C
    eq(View.seatNote(s, 3), "от следващата игра")
    eq(View.seatNote(s, 1), ""); eq(View.seatNote(s, 4), "")
    w.ns.client.events:emit("session", s); w:advance(0)
    eq(w.ns.TableFrame.view.plates[3].note:GetText(), "от следващата игра")
  end)
end)
