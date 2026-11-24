local Wow = require("wow")

local A, B = "Иван Петров", "Мария Стоянова"
local BOT = "Bot Ivanov"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired.
local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = A .. "-Forever", online = true, guid = Wow.GUID } }
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

local E = guildWow().ns.Engines.tabla -- the engine's code, for states built by hand

-- The helpers at the top of tests/engines/tabla_test.lua, verbatim.
local function arr(m) local t = {} for i = 1, 24 do t[i] = (m and m[i]) or 0 end return t end
local function sum(t) local n = 0 for i = 1, 24 do n = n + t[i] end return n end
local GAME = { std = 1, tapa = 2, gul = 3 }

-- A position with `turn` about to roll. m1/m2: own point -> count; off defaults to the rest of 15.
local function pos(var, turn, m1, m2, o)
  o = o or {}
  local s = E.new{}
  s.game, s.var = GAME[var], var
  s.pts, s.pin = { arr(m1), arr(m2) }, { arr(o.pin1), arr(o.pin2) }
  s.bar = o.bar or { 0, 0 }
  s.off = {}
  for seat = 1, 2 do
    s.off[seat] = (o.off and o.off[seat]) or (15 - sum(s.pts[seat]) - s.bar[seat])
  end
  s.rolls = o.rolls or { 0, 0 }
  s.turn, s.phase = turn, "roll"
  return s
end
local function roll(s, a, b) ok(E.apply(s, 0, { k = "dice", d = { a, b } })) end

local current -- the view of the running test's sandbox, for draw()

-- The view's frame over a 532 x 328 parent; every move is recorded in `acts`.
local function setup()
  local w = guildWow()
  local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent)
  parent:SetSize(532, 328)
  local View = w.ns.TableFrame.views.tabla
  assert(View, "no view registered for tabla")
  local f = View.build(parent)
  current = View
  local acts = {}
  w.ns.client.act = function(_, a) acts[#acts + 1] = a; return true end
  return w, View, f, acts
end

-- A session at seat `seat` (nil: a watcher) over `state`.
local function sess(state, seat)
  return { game = "tabla", status = "live", mySeat = seat, seats = { A, B }, state = state,
    tid = "t#1", epoch = 1, seq = 1, role = seat and "player" or "watcher" }
end
local function draw(f, st, seat) current.update(f, sess(st, seat)) end

-- The `.seat` of every visible checker of a point (or the bar), base first.
local function shownCheckers(p)
  local out = {}
  for _, c in ipairs(p.checkers) do
    if c:IsVisible() then out[#out + 1] = c.seat end
  end
  return out
end

-- The sorted list of the points whose glow is visible.
local function lit(f)
  local out = {}
  for q = 1, 24 do
    if f.spikes[q].glow:IsVisible() then out[#out + 1] = q end
  end
  return out
end

describe("ui: Табла view", function()
  it("24 points from my side, the bar and the tray; checkers by seat; five drawn and a number above that", function()
    local w, View, f = setup(); local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1); draw(f, st, 1)
    eq(f.spikes[1].points[1], { "TOPLEFT", f, "TOPLEFT", 340, -128 }); eq(f.spikes[6].points[1], { "TOPLEFT", f, "TOPLEFT", 200, -128 })
    eq(f.spikes[7].points[1], { "TOPLEFT", f, "TOPLEFT", 148, -128 }); eq(f.spikes[12].points[1], { "TOPLEFT", f, "TOPLEFT", 8, -128 })
    eq(f.spikes[13].points[1], { "TOPLEFT", f, "TOPLEFT", 8, -8 }); eq(f.spikes[24].points[1], { "TOPLEFT", f, "TOPLEFT", 340, -8 })
    eq({ f.bar.points[1], { f.bar:GetSize() } }, { { "TOPLEFT", f, "TOPLEFT", 176, -8 }, { 24, 216 } }); eq(f.tray.points[1], { "TOPLEFT", f, "TOPLEFT", 368, -8 })
    eq({ f.spikes[1].tri.texCoord, f.spikes[13].tri.texCoord }, { { 0, 1, 1, 0 }, nil }); eq({ f:GetSize() }, { 512, 260 })
    eq(shownCheckers(f.spikes[24]), { 1, 1 }); eq(shownCheckers(f.spikes[1]), { 2, 2 }); eq(shownCheckers(f.spikes[6]), { 1, 1, 1, 1, 1 }); eq(f.spikes[6].count:IsVisible(), false)
    eq({ f.dice[1].texCoord, f.dice[2].texCoord }, { { 0.5, 0.75, 0, 0.5 }, { 0, 0.25, 0, 0.5 } }); eq(f.title:GetText(), "Обикновена · игра 1"); eq(f.score:GetText(), "0 : 0 · до 5")
    draw(f, pos("tapa", 1, { [24] = 15 }, { [24] = 15 }), 2); eq(#shownCheckers(f.spikes[24]), 5); eq(f.spikes[24].count:GetText(), "15"); eq(shownCheckers(f.spikes[1])[1], 1)
    eq({ View.seatNote(sess(st, 1), 1), View.seatNote(sess(st, 1), 2), View.seatNote(sess(nil, 1), 1) }, { "бели · 0", "черни · 0", "" })
  end)

  it("the Табла bar carries the crest", function()
    for _, case in ipairs({ { "Alliance", "alliance" }, { "Horde", "horde" } }) do
      local w = Wow.new{ ui = true }; w.faction = case[1]; w:boot(); w:fire("PLAYER_LOGIN")
      local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent); parent:SetSize(532, 328)
      local f = w.ns.TableFrame.views.tabla.build(parent)
      local T, c = w.ns.Theme, f.crest
      ok(c, "no crest"); eq({ c:GetSize() }, { 40, 40 }); eq(c:GetAlpha(), 0.8); ok(c.standIn, "not our stand-in")
      eq(c:GetTexture(), T.tex["crest_" .. case[2]]); eq(c.points[1], { "CENTER", f.bar, "CENTER", 0, 0 })
      eq({ c.layer, c.sublayer }, { "ARTWORK", -1 }); eq({ f.bar.checkers[1].layer, f.bar.checkers[1].sublayer or 0 }, { "ARTWORK", 0 }) -- under the checkers
      local felt, light = T.color.felt, T.color.pointLight
      eq(f.spikes[1].tri.vertex, { felt[1], felt[2], felt[3], 1 }); eq(f.spikes[2].tri.vertex, { light[1], light[2], light[3], 1 })
    end
  end)

  it("„Готово“ is dead until the move is whole and then sends the staged steps as one action", function()
    local w, View, f, acts = setup(); local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1); draw(f, st, 1)
    eq({ lit(f), f.doneButton.enabled, f.undoButton.enabled, f.text:GetText() }, { {}, false, false, "Твой ход: кликни пул" })
    w:click(f.spikes[7]); eq(f.pick, nil); w:click(f.spikes[8]); eq({ f.pick, lit(f), f.spikes[8].ring:GetAlpha() }, { 8, { 5, 7 }, 1 })
    w:click(f.spikes[5]); eq({ f.staged, f.pick, lit(f) }, { { { 8, 5 } }, nil, {} }); eq({ #shownCheckers(f.spikes[8]), #shownCheckers(f.spikes[5]) }, { 2, 1 })
    eq({ f.doneButton.enabled, f.undoButton.enabled, f.dice[1]:GetAlpha(), f.dice[2]:GetAlpha(), f.stepsLeft:GetText() }, { false, true, 0.4, 1, "Остават: 1" })
    eq(f.doneButton:IsEnabled(), false)                                                    -- a partial move never leaves the client (a click on a dead button raises in Wow:click)
    w:click(f.spikes[6]); w:click(f.spikes[5]); eq({ f.doneButton.enabled, f.text:GetText() }, { true, "Ходът е нареден. Натисни „Готово“." })
    w:click(f.undoButton); eq({ f.staged, f.doneButton.enabled, #shownCheckers(f.spikes[6]) }, { { { 8, 5 } }, false, 5 })
    w:click(f.spikes[6]); w:click(f.spikes[5]); w:click(f.doneButton); eq(acts, { { k = "move", steps = { { 8, 5 }, { 6, 5 } } } })
    eq({ f.doneButton:IsEnabled(), f.undoButton:IsEnabled(), #acts, #f.staged }, { false, false, 1, 2 })   -- sent (`f.sent`): both buttons are dead, nothing moves until the event is back
    w:click(f.spikes[13]); eq({ f.pick, #f.staged }, { nil, 2 })                       -- the checkers are dead too
    local s = sess(st, 1); s.seq = 2; View.update(f, s); eq({ f.sent, f.staged, f.undoButton.enabled }, { nil, {}, false })
    w.ns.client.act = function() return nil, "refused" end                               -- a refused move is thrown away
    w:click(f.spikes[8]); w:click(f.spikes[5]); w:click(f.spikes[6]); w:click(f.spikes[5]); w:click(f.doneButton)
    eq({ f.staged, f.sent, f.doneButton.enabled, #shownCheckers(f.spikes[8]) }, { {}, nil, false, 3 })
  end)

  it("the end line of the match hides under the bill of a staked match (StakePanels.shown); nothing else does", function()
    local w, View, f = setup(); local P = w.ns.StakePanels
    local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1)
    P.shown = true; draw(f, st, 1)
    eq({ f.text:IsVisible(), f.text:GetText() }, { true, "Твой ход: кликни пул" })
    st.phase, st.winner = "match", 1
    P.shown = false; draw(f, st, 1)
    eq({ f.text:IsVisible(), f.text:GetText() }, { true, "Печелиш партията!" })
    P.shown = true; draw(f, st, 1)
    eq(f.text:IsVisible(), false)
    P.shown = false; draw(f, st, 1)
    eq({ f.text:IsVisible(), f.text:GetText() }, { true, "Печелиш партията!" })
  end)

  it("a table event throws the staged move away; a watcher has no buttons and nothing to pick", function()
    local w, View, f, acts = setup(); local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1); draw(f, st, 1)
    w:click(f.spikes[8]); w:click(f.spikes[5]); local s = sess(st, 1); s.seq = 2; View.update(f, s); eq({ f.staged, f.pick, #shownCheckers(f.spikes[8]) }, { {}, nil, 3 })
    draw(f, st, nil); eq({ f.doneButton:IsVisible(), f.undoButton:IsVisible(), f.spikes[8].ring:IsVisible() }, { false, false, false })
    w:click(f.spikes[8]); eq(f.pick, nil); draw(f, st, 2); eq({ f.doneButton:IsVisible(), f.doneButton.enabled, #w:texts("Изчакай ") }, { true, false, 1 })
  end)

  it("a mother pin lights „Готово“ after one step; bearing off goes to the tray; a blocked roll is confirmed empty", function()
    local w, View, f, acts = setup(); local mp = pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 }); roll(mp, 3, 5); draw(f, mp, 1)
    w:click(f.spikes[4]); eq(lit(f), { 1 }); w:click(f.spikes[1]); eq({ f.doneButton.enabled, shownCheckers(f.spikes[1]) }, { true, { 2, 1 } })
    w:click(f.doneButton); eq(acts[1], { k = "move", steps = { { 4, 1 } } })

    w, View, f, acts = setup(); local bo = pos("std", 1, { [2] = 1, [1] = 1 }, { [24] = 15 }); roll(bo, 6, 5); draw(f, bo, 1)
    eq({ f.tray.glow:IsVisible(), f.tray.own:GetText(), f.tray.opp:IsVisible() }, { false, "13", false })
    w:click(f.spikes[2]); eq(f.tray.glow:IsVisible(), true); w:click(f.tray); eq({ f.staged, f.tray.own:GetText(), f.tray.glow:IsVisible() }, { { { 2, 0 } }, "14", false })

    w, View, f, acts = setup()
    local u = pos("std", 1, { [24] = 2, [13] = 12 }, { [6] = 2, [5] = 2, [4] = 2, [3] = 2, [2] = 2, [1] = 2, [24] = 3 }, { bar = { 1, 0 } }); roll(u, 3, 4); draw(f, u, 1)
    eq({ shownCheckers(f.bar), f.bar.ring:IsVisible(), f.text:GetText(), f.doneButton.enabled }, { { 1 }, false, "Нямаш ход. Натисни „Готово“.", true })
    w:click(f.doneButton); eq(acts, { { k = "move", steps = {} } })

    w, View, f, acts = setup(); local e = pos("std", 1, { [24] = 2, [13] = 12 }, { [24] = 15 }, { bar = { 1, 0 } }); roll(e, 3, 4); draw(f, e, 1)
    eq(f.bar.ring:IsVisible(), true); w:click(f.bar); eq({ f.pick, f.bar.ring:GetAlpha() }, { 25, 1 }); eq(lit(f), { 21, 22 })
  end)

  it("solo against a bot from a real throw: dice on the board, the dice line under the felt, the rules book on „Табла“", function()
    local w = withBots(); local client, T = w.ns.client, w.ns.TableFrame
    client:openTable{ game = "tabla", access = "invite", turn = 45 }; w:advance(0)
    local v = T.view
    w:click(v.inviteButton)
    local row
    for _, r in ipairs(v.picker.rows) do
      if r.frame:IsVisible() and r.name:GetText() == BOT then row = r end
    end
    assert(row, "no row for the bot in the picker")
    w:click(row.frame); w:advance(3)
    local V, s = T.built.tabla, client.session
    ok(V, "no Табла board"); ok(s.state.dice ~= nil, "no dice thrown")
    local function playMine()
      local guard = 0
      while not V.doneButton:IsEnabled() do
        guard = guard + 1; assert(guard < 20, "the move never became whole")
        local clicked = false
        if V.bar.ring:IsVisible() and V.pick ~= 25 then w:click(V.bar); clicked = true end
        for q = 1, 24 do
          if not clicked and V.spikes[q].ring:IsVisible() and V.pick == nil then w:click(V.spikes[q]); clicked = true end
        end
        for q = 1, 24 do
          if not clicked and V.spikes[q].glow:IsVisible() then w:click(V.spikes[q]); clicked = true end
        end
        if not clicked and V.tray.glow:IsVisible() then w:click(V.tray); clicked = true end
        assert(clicked, "nothing to click")
      end
      w:click(V.doneButton)
    end
    local guard = 0
    while not (s.state.phase == "move" and s.state.turn == 1) do
      guard = guard + 1; assert(guard < 20, "my move never came"); w:advance(3)
    end
    eq({ V.dice[1]:IsVisible(), V.dice[2]:IsVisible() }, { true, true })
    ok(v.fairLine:IsVisible(), "no dice line"); eq(v.fairLine.text:GetText(), "Зарове: хвърлени от двамата играчи")
    eq({ v.fairLine.text:GetTextColor() }, { w.ns.Theme.color.good[1], w.ns.Theme.color.good[2], w.ns.Theme.color.good[3], 1 })
    eq(v.info.topic, "tabla"); eq({ v.plates[1].note:GetText(), v.plates[2].note:GetText() }, { "бели · 0", "черни · 0" })
    local seq = s.seq
    playMine(); w:advance(3)
    ok(s.seq >= seq + 4, "the game did not move on: " .. tostring(s.seq) .. " after " .. tostring(seq))
  end)
end)
