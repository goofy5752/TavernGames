local Wow = require("wow")

local ME, B = "Иван Петров", "Мария Стоянова"
local BOT = "Бот Иванов"

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

local function botNamed(w, name)
  for _, bot in ipairs(w.ns.bots.list) do
    if bot.env.me == name then return bot end
  end
end

local function rgb(w, token)
  local c = w.ns.Theme.color[token]
  return { c[1], c[2], c[3], 1 }
end

local function color(fs) return { fs:GetTextColor() } end

local MAGE, PRIEST = { 0.25, 0.78, 0.92, 1 }, { 1, 1, 1, 1 }

-- I host an invite-only table and „Бот Иванов“ takes the invitation through the „Покани“ picker.
local function matchWithBot()
  local w = withBots()
  w.ns.client:openTable{ game = "ttt", access = "invite", turn = 45 }
  w:advance(0)
  local v = w.ns.TableFrame.view
  w:click(v.inviteButton)
  local row
  for _, r in ipairs(v.picker.rows) do
    if r.frame:IsVisible() and r.name:GetText() == BOT then row = r end
  end
  assert(row, "no row for the bot in the picker")
  w:click(row.frame)
  w:advance(1.2)
  return w, v
end

local function cells(w) return w.ns.TableFrame.built.ttt.cells end

describe("ui: table frame", function()
  it("is shown while I am at a table and hidden when I leave; no new globals", function()
    local w = guildWow()
    local TF = w.ns.TableFrame
    eq(TF.frame == nil or not TF.frame:IsShown(), true)
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    ok(TF.frame:IsShown(), "not shown")
    eq({ TF.frame:GetWidth(), TF.frame:GetHeight() }, { TF.WIDTH, TF.HEIGHT })
    local felt = TF.view.felt
    eq(felt:GetTexture(), w.ns.Theme.tex.felt)
    eq(felt.wrap, { nil, nil }); eq(felt.texCoord, nil) -- stretched once, never tiled
    eq(TF.view.title:GetText(), "Морски шах")
    w:click(TF.view.standButton)
    w:advance(0)
    eq(TF.frame:IsShown(), false)
    eq(w.ns.client.session, nil)
    ok(w.ns.MainWindow.frame:IsShown(), "the hall did not open")
    eq(w:newGlobals(), { "SLASH_TAVERNGAMES1", "TavernGamesDB" })
  end)

  it("alone at my table: „Чакаме втори играч…“, my plate in class color, a free plate, „Покани“ and „Стани“", function()
    local w = guildWow()
    local L = w.ns.L
    eq(L("table.waiting"), "Чакаме втори играч…")
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    local v = w.ns.TableFrame.view
    ok(v.banner:IsVisible(), "no banner"); eq(v.bannerText:GetText(), "Чакаме втори играч…")
    eq(v.plates[1].name:GetText(), ME); eq(color(v.plates[1].name), MAGE)
    eq(v.plates[1].note:GetText(), "|cffe9c98aХ|r")
    eq(v.plates[2].name:GetText(), L("table.free"))
    eq(v.plates[1].ring:IsVisible(), false); eq(v.plates[1].clock:IsVisible(), false)
    ok(v.inviteButton:IsVisible(), "no Покани"); eq(v.inviteButton.text:GetText(), "Покани")
    eq(v.standButton.text:GetText(), "Стани")
    eq(v.watchers:IsVisible(), false)
  end)

  it("ⓘ opens the rules book on the game's topic", function()
    local w = guildWow()
    local opened = {}
    w.ns.HelpBook = { open = function(id) opened[#opened + 1] = id end }
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    w:click(w.ns.TableFrame.view.info)
    eq(opened, { "ttt" })
  end)

  it("„Покани“ lists who is in the tavern; a click invites, the bot sits and the match starts", function()
    local w, v = matchWithBot()
    local s = w.ns.client.session
    eq(s.seats, { ME, BOT }); eq(s.status, "live")
    eq(v.picker:IsShown(), false)
    eq(v.inviteButton:IsVisible(), false) -- no free seat any more
    eq(v.banner:IsVisible(), false)
    eq(v.line:GetText(), "|cffffffff" .. BOT .. "|r прие поканата.")
    eq(v.plates[2].name:GetText(), BOT); eq(color(v.plates[2].name), PRIEST)
    eq(v.plates[2].note:GetText(), "|cffe2735aО|r")
    -- I start: the ring and the clock are on my plate, the edge is gold.
    ok(v.plates[1].ring:IsVisible(), "no ring on my plate"); eq(v.plates[2].ring:IsVisible(), false)
    eq(v.plates[1].ring:GetTexture(), w.ns.Theme.tex.ring)
    eq({ v.plates[1].edges[1]:GetVertexColor() }, rgb(w, "gold"))
    w:render(0.02)
    eq(v.plates[1].clock:GetText(), "0:45")
    w:advance(4.5); w:render(0.02)
    eq(v.plates[1].clock:GetText(), "0:41")
  end)

  it("the picker skips seated players and says when nobody is there", function()
    local w = guildWow()
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    local v = w.ns.TableFrame.view
    w:click(v.inviteButton)
    ok(v.picker:IsShown(), "picker hidden")
    ok(v.picker.empty:IsVisible(), "no empty note"); eq(v.picker.empty:GetText(), w.ns.L("peers.empty"))
    w:click(v.inviteButton)
    eq(v.picker:IsShown(), false)
  end)

  it("plays a round against the bot: marks, the bot answers, the ring moves, the line glows, the score", function()
    local w, v = matchWithBot()
    local c = cells(w)
    w:click(c[1].button); w:advance(0)
    eq(c[1].mark:GetText(), "Х"); eq(color(c[1].mark), rgb(w, "brassLight"))
    -- The bot's turn: my cells are dimmed and not clickable, the ring is on the bot.
    eq(c[5].button:IsEnabled(), false); ok(c[5].button:GetAlpha() < 1, "not dimmed")
    ok(v.plates[2].ring:IsVisible(), "ring did not move"); eq(v.plates[1].ring:IsVisible(), false)
    w:advance(1.6)
    eq(c[2].mark:GetText(), "О"); eq(color(c[2].mark), rgb(w, "oMark"))
    ok(c[5].button:IsEnabled(), "my turn but not clickable"); eq(c[5].button:GetAlpha(), 1)
    w:click(c[4].button); w:advance(1.6) -- the bot takes 3
    w:click(c[7].button); w:advance(0)
    local gold = rgb(w, "gold")
    for _, i in ipairs({ 1, 4, 7 }) do
      eq({ c[i].edges[1]:GetVertexColor() }, gold, "edge " .. i)
      eq(c[i].bg.color[1], gold[1], "background " .. i)
    end
    ok(c[2].bg.color[1] ~= gold[1], "a cell off the line glows")
    eq(w.ns.TableFrame.built.ttt.score:GetText(), "1 : 0")
    eq(w.ns.TableFrame.built.ttt.upTo:GetText(), "до 3 победи")
    w:advance(3); w:advance(0)
    eq(c[1].mark:GetText(), ""); ok(c[1].bg.color[1] ~= gold[1], "glow stayed")
    ok(v.plates[2].ring:IsVisible(), "the other player does not start the next round")
    w:advance(1.6)
    eq(c[1].mark:GetText(), "О")
    -- My turn runs out: the first empty cell is filled for me.
    w:advance(45); w:advance(0)
    eq(c[2].mark:GetText(), "Х")
  end)

  it("the bot stands up mid-match: „Играта е прекъсната.“ and „Покани“ again", function()
    local w, v = matchWithBot()
    eq(w.ns.L("table.aborted"), "Играта е прекъсната.")
    botNamed(w, BOT):stand()
    w:advance(0); w:advance(0)
    ok(v.banner:IsVisible(), "no banner"); eq(v.bannerText:GetText(), "Играта е прекъсната.")
    ok(v.inviteButton:IsVisible(), "no Покани")
    eq(cells(w)[5].button:IsEnabled(), false)
  end)

  it("a watcher: „Към залата“, the watcher count, host silence and the resync banner", function()
    local w = withBots()
    w:slash("bots host"); w:advance(0); w:advance(0)
    local rec = w.ns.client.lobby:tables()[1]
    w.ns.client:watch(rec.tid)
    w:advance(0); w:advance(0)
    local s = w.ns.client.session
    eq(s.role, "watcher")
    local v, L = w.ns.TableFrame.view, w.ns.L
    eq(v.standButton.text:GetText(), "Към залата")
    eq(v.inviteButton:IsVisible(), false)
    ok(v.watchers:IsVisible(), "no watcher count"); eq(v.watchers:GetText(), "Гледат: 1")
    eq(L("table.hostSilent"), "Връзката с домакина се губи…")
    s.hostSilent = true
    w.ns.client.events:emit("session", s); w:advance(0)
    eq(v.bannerText:GetText(), "Връзката с домакина се губи…")
    s.hostSilent = false
    w.ns.client.events:emit("desync", s.tid); w:advance(0)
    eq(v.bannerText:GetText(), L("table.resynced")); ok(v.banner:IsVisible(), "no resync banner")
    w:advance(2.9); ok(v.banner:IsVisible(), "gone too early")
    w:advance(0.2)
    eq(v.bannerText:GetText(), "Чакаме втори играч…")
    w:click(v.standButton); w:advance(0)
    eq(w.ns.TableFrame.frame:IsShown(), false)
    ok(w.ns.MainWindow.frame:IsShown(), "the hall did not open"); eq(w.ns.MainWindow.current, "hall")
  end)

  it("the host hears every kind of answer to an invitation as one line", function()
    local w = guildWow()
    w.ns.client:openTable{ game = "ttt", access = "invite", turn = 45 }
    w:advance(0)
    local v, emit = w.ns.TableFrame.view, function(...) w.ns.client.events:emit("inviteAnswer", ...) end
    local who = "|cfff3e2c0" .. B .. "|r" -- class unknown: ink
    local cases = {
      { { "yes" }, who .. " прие поканата." },
      { { "no" }, who .. " отказа поканата." },
      { { "auto", "combat" }, who .. " е в бой." },
      { { "auto", "instance" }, who .. " е в подземие." },
      { { "auto", "busy" }, who .. " е зает." },
      { { "auto", "snooze" }, who .. " не иска покани сега." },
      { { "auto", "timeout" }, who .. " не отговори." },
    }
    for _, case in ipairs(cases) do
      emit(B, case[1][1], case[1][2])
      eq(v.line:GetText(), case[2])
    end
    ok(v.line:IsVisible(), "line hidden")
    w:advance(5.1); eq(v.line:IsVisible(), false)
  end)
end)

describe("ui: table frame, host-started games", function()
  -- I host an invite-only Death Roll table with the start number 100.
  local function drTable()
    local w = withBots()
    w.ns.client:openTable{ game = "deathroll", access = "invite", turn = 45, opt = { start = 100 } }
    w:advance(0)
    return w, w.ns.TableFrame.view
  end

  local function visiblePlates(v)
    local shown = 0
    for _, p in ipairs(v.plates) do if p.frame:IsVisible() then shown = shown + 1 end end
    return shown
  end

  it("five plates in two rows; alone: „Чакаме още играчи…“ and a disabled „Започни“", function()
    local w, v = drTable()
    eq(#w:texts("Чакаме още играчи…"), 1)
    eq(visiblePlates(v), 5)
    eq(v.plates[4].frame:GetWidth(), 165)
    eq(v.plates[4].frame.points[1], { "TOPLEFT", v.area, "TOPLEFT", 10, -42 })
    ok(v.startButton:IsVisible(), "no Започни"); eq(v.startButton:IsEnabled(), false)
    eq(v.startButton.text:GetText(), "Започни")
    eq(#w:texts("Начално число 100"), 1)
  end)

  -- „Бот Иванов“ takes my invitation through the „Покани“ picker.
  local function inviteBot(w, v)
    w:click(v.inviteButton)
    local row
    for _, r in ipairs(v.picker.rows) do
      if r.frame:IsVisible() and r.name:GetText() == BOT then row = r end
    end
    assert(row, "no row for the bot in the picker")
    w:click(row.frame)
    w:advance(2)
  end

  it("with a second player „Започни“ starts the game and goes away; after the game it reads „Нова игра“", function()
    local w, v = drTable()
    local L, client = w.ns.L, w.ns.client
    inviteBot(w, v)
    eq(client.session.seats[2], BOT)
    ok(v.banner:IsVisible(), "no banner"); eq(v.bannerText:GetText(), L("table.pressStart"))
    eq(L("table.pressStart"), "Всички ли са тук? Натисни „Започни“.")
    ok(v.startButton:IsVisible(), "no Започни"); eq(v.startButton:IsEnabled(), true)
    eq(v.startButton.text:GetText(), "Започни")
    eq(v.line.points[1][2], v.startButton) -- the news line sits right of „Започни“
    w:click(v.startButton); w:advance(0)
    eq(client.session.status, "live")
    eq(v.startButton:IsVisible(), false); eq(v.banner:IsVisible(), false)
    eq(v.line.points[1][2], v.inviteButton)
    client.session:play(1, { k = "roll", n = 1, max = 100, src = "ask" }); w:advance(0)
    ok(v.startButton:IsVisible(), "no Нова игра"); eq(v.startButton.text:GetText(), "Нова игра")
    eq(v.startButton:IsEnabled(), true)
    eq(v.banner:IsVisible(), false) -- the view says who lost
  end)

  it("„Започни“ is enabled exactly when startGame would start, also for a truthy non-boolean engine.over", function()
    local w, v = drTable()
    local client, E = w.ns.client, w.ns.Engines.deathroll
    local s = client.session
    local function agrees(label)
      local can, code = s:canStart()
      eq(v.startButton:IsShown(), code ~= "live", label .. ": shown")
      if v.startButton:IsShown() then eq(v.startButton:IsEnabled(), can == true, label .. ": enabled") end
    end
    E.over = function(st) return st.phase == "over" and "yes" or nil end
    local okRun, err = pcall(function()
      agrees("alone")
      inviteBot(w, v); agrees("two seated")
      w:click(v.startButton); w:advance(0); agrees("live")
      eq(v.startButton:IsShown(), false)
      s:play(1, { k = "roll", n = 1, max = 100, src = "ask" }); w:advance(0); agrees("over")
      eq(v.startButton:IsEnabled(), true); eq(v.startButton.text:GetText(), "Нова игра")
      w:click(v.startButton); w:advance(0)
      eq(s.state.phase, "play"); eq(v.startButton:IsShown(), false)
    end)
    E.over = nil
    assert(okRun, err)
  end)

  it("a refused start says why on the news line", function()
    local w, v = drTable()
    eq(v.startButton:IsEnabled(), false)
    w.ns.TableFrame.startGame() -- a click that lost a race: still alone
    ok(v.line:IsVisible(), "no news line"); eq(v.line:GetText(), "Още няма достатъчно играчи.")
    eq(w.ns.client.session.status, "open")
  end)

  it("with every seat taken „Започни“ moves next to „Стани“", function()
    local w, v = drTable()
    local s = w.ns.client.session
    for i = 2, #s.seats do s.seats[i] = "Играч " .. i end
    w.ns.client.events:emit("session", s); w:advance(0)
    eq(v.inviteButton:IsShown(), false)
    local p = v.startButton.points[1]
    ok(p[2] == v.standButton, "not next to Стани"); eq({ p[1], p[3], p[4], p[5] }, { "LEFT", "RIGHT", 8, 0 })
    s.seats[5] = false
    w.ns.client.events:emit("session", s); w:advance(0)
    ok(v.startButton.points[1][2] == v.inviteButton, "not next to Покани")
  end)

  it("a guest at a host-started table sees „Чакаме домакина да започне…“ and no start button", function()
    local w = withBots()
    w:slash("bots host dr"); w:advance(0); w:advance(0)
    local rec = w.ns.client.lobby:tables()[1]
    eq(rec.game, "deathroll")
    w.ns.client:sit(rec.tid, 2)
    w:advance(1)
    local s, v, L = w.ns.client.session, w.ns.TableFrame.view, w.ns.L
    eq(s.role, "player"); eq(s.status, "open")
    eq(L("table.waitingHost"), "Чакаме домакина да започне…")
    eq(#w:texts(L("table.waitingHost")), 1)
    eq(v.startButton:IsVisible(), false)
  end)
end)

describe("ui: Морски шах view", function()
  local E

  local function setup()
    local w = guildWow()
    E = w.ns.Engines.ttt
    local view = w.ns.TableFrame.views.ttt
    local f = view.build(w.G.CreateFrame("Frame", nil, w.G.UIParent))
    local acts = {}
    w.ns.client.act = function(_, a) acts[#acts + 1] = a; return true end
    return w, view, f, acts
  end

  local function session(state, seat)
    return { game = "ttt", status = "live", role = seat and "player" or "watcher", mySeat = seat,
             seats = { ME, B }, state = state }
  end

  it("3x3 cells of 62 px with 6 px gaps, marks in Alegreya SC 44", function()
    local w, view, f = setup()
    view.update(f, session(E.new(), 1))
    eq(#f.cells, 9)
    eq({ f.cells[1].button:GetSize() }, { 62, 62 })
    local p1, p2, p4 = f.cells[1].button.points[1], f.cells[2].button.points[1], f.cells[4].button.points[1]
    eq(p2[4] - p1[4], 68); eq(p1[5] - p4[5], 68)
    eq({ f.cells[1].mark:GetFont() }, { w.ns.Theme.font.heading, 44, "" })
  end)

  it("on my turn an empty cell shows a ghost of my mark on hover and a click marks it", function()
    local w, view, f, acts = setup()
    local st = E.new(); st.board[1] = 1; st.turn = 2
    view.update(f, session(st, 2))
    local c = f.cells
    w:hover(c[5].button)
    ok(c[5].ghost:IsVisible(), "no ghost"); eq(c[5].ghost:GetText(), "О"); eq(c[5].ghost:GetAlpha(), 0.25)
    c[5].button.scripts.OnLeave(c[5].button)
    eq(c[5].ghost:IsVisible(), false)
    w:hover(c[1].button); eq(c[1].ghost:IsVisible(), false)
    w:click(c[5].button)
    eq(acts, { { k = "mark", c = 5 } })
    eq(c[1].button:IsEnabled(), false)
  end)

  it("not my turn, or a watcher: the cells are dimmed and not clickable", function()
    local _, view, f = setup()
    view.update(f, session(E.new(), 2))
    for i = 1, 9 do eq(f.cells[i].button:IsEnabled(), false); ok(f.cells[i].button:GetAlpha() < 1) end
    view.update(f, session(E.new(), nil))
    for i = 1, 9 do eq(f.cells[i].button:IsEnabled(), false); ok(f.cells[i].button:GetAlpha() < 1) end
    view.update(f, session(E.new(), 1))
    for i = 1, 9 do eq(f.cells[i].button:IsEnabled(), true); eq(f.cells[i].button:GetAlpha(), 1) end
  end)

  it("the score under „до 3 победи“, the winning line in gold, the result undimmed", function()
    local w, view, f = setup()
    local st = E.new()
    st.board = { 1, 2, 0, 2, 1, 0, 0, 0, 1 }; st.line = { 1, 5, 9 }; st.score = { 2, 1 }
    st.turn, st.phase = nil, "round"
    view.update(f, session(st, 2))
    eq(f.upTo:GetText(), "до 3 победи"); eq(f.score:GetText(), "2 : 1")
    local gold = rgb(w, "gold")
    for _, i in ipairs({ 1, 5, 9 }) do eq({ f.cells[i].edges[1]:GetVertexColor() }, gold) end
    for i = 1, 9 do eq(f.cells[i].button:GetAlpha(), 1) end
    eq(f.rematch:IsVisible(), false); eq(f.result:IsVisible(), false)
  end)

  it("phase match: the winner, „Реванш“, then „Чакаме <Име>…“; watchers see only the winner", function()
    local w, view, f, acts = setup()
    local st = E.new()
    st.board = { 1, 1, 1, 2, 2, 0, 0, 0, 0 }; st.line = { 1, 2, 3 }; st.score = { 3, 1 }
    st.turn, st.phase, st.winner = nil, "match", 1
    view.update(f, session(st, 2))
    ok(f.result:IsVisible(), "no result"); eq(f.result:GetText(), "|cff40c7eb" .. ME .. "|r печели мача!")
    ok(f.rematch:IsVisible(), "no Реванш"); eq(f.rematch.text:GetText(), "Реванш")
    eq(f.waiting:IsVisible(), false)
    w:click(f.rematch)
    eq(acts, { { k = "rematch" } })
    st.rematch = { false, true }
    view.update(f, session(st, 2))
    eq(f.rematch:IsVisible(), false)
    ok(f.waiting:IsVisible(), "no waiting line"); eq(f.waiting:GetText(), "Чакаме |cff40c7eb" .. ME .. "|r…")
    view.update(f, session(st, nil))
    ok(f.result:IsVisible(), "watcher sees no result")
    eq(f.rematch:IsVisible(), false); eq(f.waiting:IsVisible(), false)
  end)
end)

describe("ui: invite toast", function()
  local function invited(w)
    w:slash("bots invite"); w:advance(0); w:advance(0); w:advance(0)
  end

  it("shows the invitation with three buttons, a sound and a 30 s bar", function()
    local w = withBots()
    local T, L = w.ns.InviteToast, w.ns.L
    invited(w)
    ok(T.frame:IsShown(), "no toast")
    eq(T.title:GetText(), "Покана за Морски шах")
    local host = w.ns.client.invites.received.host
    ok(T.text:GetText():find("те кани на Морски шах", 1, true), "text: " .. tostring(T.text:GetText()))
    ok(T.text:GetText():find(host, 1, true), "no host name")
    eq(T.accept.text:GetText(), L("invite.accept")); eq(T.notNow.text:GetText(), L("invite.notNow"))
    eq(T.snooze.text:GetText(), L("invite.snooze"))
    eq(T.snooze.text:GetText(), "Не ме безпокой 30 мин")
    -- frame.tga nine-slice: a 12 px source band drawn 12 px wide, like every framed window.
    local corner = T.border.pieces[1]
    eq(corner:GetTexture(), w.ns.Theme.tex.frame)
    eq({ corner:GetSize() }, { 12, 12 })
    eq(corner.texCoord, { 0, 12 / 64, 0, 12 / 64 })
    eq(#w.sounds, 1)
    w:render(0.02); eq(T.bar:GetWidth(), T.BAR_W)
    w:advance(15); w:render(0.02)
    ok(math.abs(T.bar:GetWidth() - T.BAR_W / 2) < 1, "bar " .. T.bar:GetWidth())
    w:advance(15.1)
    eq(T.frame:IsShown(), false)
  end)

  it("„Приемам“ sits me at the table", function()
    local w = withBots()
    invited(w)
    local tid = w.ns.client.invites.received.tid
    w:click(w.ns.InviteToast.accept)
    eq(w.ns.InviteToast.frame:IsShown(), false)
    w:advance(0); w:advance(0)
    local s = w.ns.client.session
    ok(s, "not seated"); eq(s.tid, tid); eq(s.role, "player")
    ok(w.ns.TableFrame.frame:IsShown(), "no table frame")
  end)

  it("„Не сега“ closes it; „Не ме безпокой 30 мин“ keeps the next one away", function()
    local w = withBots()
    local T = w.ns.InviteToast
    invited(w)
    w:click(T.notNow)
    eq(T.frame:IsShown(), false); eq(w.ns.client.session, nil)
    w:advance(3)
    invited(w)
    ok(T.frame:IsShown(), "no second toast")
    w:click(T.snooze)
    eq(T.frame:IsShown(), false)
    ok(w.ns.db.snoozeUntil > w.G.GetServerTime(), "no snooze")
    local sounds = #w.sounds
    w:advance(3)
    invited(w)
    eq(T.frame:IsShown(), false); eq(#w.sounds, sounds)
  end)

  it("in combat no toast is shown", function()
    local w = withBots()
    w.combat = true
    invited(w)
    eq(w.ns.InviteToast.frame == nil or not w.ns.InviteToast.frame:IsShown(), true)
    eq(#w.sounds, 0)
  end)

  it("a „Приемам“ refused locally shows the refusal on the toast, then it goes", function()
    local w = guildWow()
    local T = w.ns.InviteToast
    w:member(B)
    w:deliver("WHISPER", B, { v = 1, t = "INV", tid = B .. "#1", g = "ttt", h = B, s = { B, false } })
    w:advance(0)
    ok(T.frame:IsShown(), "no toast")
    w:click(T.accept)
    ok(T.frame:IsShown(), "the refusal is not shown")
    eq(T.text:GetText(), w.ns.L("refused.gone"))
    eq(T.accept:IsVisible(), false); eq(T.bar:IsVisible(), false)
    w:advance(5.1)
    eq(T.frame:IsShown(), false)
  end)

  it("hides when the invitation goes stale", function()
    local w = guildWow()
    local T = w.ns.InviteToast
    w:member(B)
    w:deliver("WHISPER", B, { v = 1, t = "INV", tid = B .. "#1", g = "ttt", h = B, s = { B, false } })
    w:advance(0)
    ok(T.frame:IsShown(), "no toast")
    w.ns.client.invites:drop(true)
    eq(T.frame:IsShown(), false)
    -- Gone before the toast was drawn: never shown.
    local T2 = "Тодор Ангелов"
    w:member(T2)
    w:deliver("WHISPER", T2, { v = 1, t = "INV", tid = T2 .. "#1", g = "ttt", h = T2, s = { T2, false } })
    w.ns.client.invites:drop(true)
    w:advance(0)
    eq(T.frame:IsShown(), false)
    eq(#w.sounds, 1)
  end)

  it("shows without a sound and without an error when the sound constant is missing", function()
    for _, kit in ipairs({ {}, false }) do
      local w = guildWow()
      local T = w.ns.InviteToast
      w.G.SOUNDKIT = kit or nil
      w:member(B)
      w:deliver("WHISPER", B, { v = 1, t = "INV", tid = B .. "#1", g = "ttt", h = B, s = { B, false } })
      w:advance(0)
      ok(T.frame:IsShown(), "no toast"); eq(#w.sounds, 0)
    end
  end)
end)
