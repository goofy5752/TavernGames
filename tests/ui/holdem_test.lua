local Wow = require("wow")

local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired; `faction` (default Alliance) picks the skin.
local function guildWow(faction)
  local w = Wow.new{ ui = true }
  w.faction = faction or w.faction
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

local E = guildWow().ns.Engines.holdem -- the engine's code, for states built by hand

-- Seats 1-3 dealt from E.DECK as it is: seat 2 holds 2C 5C, seat 3 3C 6C, seat 1 4C 7C; the board comes
-- 9C TC JC, KC, 2D. stacks = {[seat] = chips} before the hand. `deck` (optional) replaces E.DECK.
local function hand3(opt, stacks, deck)
  local st = E.new{ seats = { true, true, true }, opt = opt }
  for i, c in pairs(stacks or {}) do st.seats[i].chips = c end
  ok(E.apply(st, 0, { k = "hand" })); ok(E.apply(st, 0, { k = "deal", deck = deck or E.DECK }))
  return st
end
local function sess(st, seat)
  return { game = "holdem", status = "live", mySeat = seat, role = seat == 1 and "host" or "player",
    seats = { A, B, C, false, false, false }, state = st and E.view(st, seat or 0), tid = "t#1", epoch = 1, seq = 1 }
end

local current -- the view of the running test's sandbox, for draw()

-- The view's frame over a 732 x 440 parent; every action is recorded in `acts`.
local function setup(faction)
  local w = guildWow(faction)
  local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent)
  parent:SetSize(732, 440)
  local View = w.ns.TableFrame.views.holdem
  assert(View, "no view registered for holdem")
  local f = View.build(parent)
  current = View
  local acts = {}
  w.ns.client.act = function(_, a) acts[#acts + 1] = a; return true end
  return w, View, f, acts
end
local function draw(f, st, seat) current.update(f, sess(st, seat)) end
-- The same, as the table's event number `seq` (a new event: the view forgets what it remembered).
local function drawAt(f, st, seat, seq) local s = sess(st, seat); s.seq = seq; current.update(f, s) end

-- A seat's two cards: "-" hidden, "back" face down, else the face.
local function faces(seat)
  local out = {}
  for j, c in ipairs(seat.cards) do
    if not c:IsVisible() then out[j] = "-" elseif c.card.face == nil then out[j] = "back" else out[j] = c.card.face end
  end
  return out
end
-- A text without its colour codes.
local function plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

describe("ui: the Холдем view", function()
  it("six places from my seat; the view draws a face only where the model has one", function()
    local w, View, f = setup(); local st = hand3(); draw(f, st, 1)
    eq({ { f:GetSize() }, View.ring, View.size }, { { 732, 440 }, true, { 760, 532 } }); eq(f.oval.points[1], { "TOPLEFT", f, "TOPLEFT", 138, -97 })
    eq({ faces(f.seat[1]), faces(f.seat[2]), faces(f.seat[3]), faces(f.seat[4]) }, { { "4C", "7C" }, { "back", "back" }, { "back", "back" }, { "-", "-" } })
    eq({ f.seat[1].cards[1].points[1], f.seat[2].cards[1].points[1], f.seat[2].cards[2].points[1] },
       { { "TOPLEFT", f, "TOPLEFT", 323, -322 }, { "TOPLEFT", f, "TOPLEFT", 166, -296 }, { "TOPLEFT", f, "TOPLEFT", 192, -296 } })
    eq({ f.seat[2].bet:GetText(), f.seat[3].bet:GetText(), f.seat[1].bet:IsVisible(), f.pot:GetText(), f.board[1]:IsVisible() }, { "5", "10", false, "Пот 15", false })
    eq({ f.seat[1].mark:IsVisible(), #w:texts("МБ"), #w:texts("ГБ") }, { true, 1, 1 })
    eq({ View.seatNote(sess(st, 1), 2), View.seatNote(sess(st, 1), 4), View.seatNote(sess(nil, 1), 1) }, { "995", "", "" })
    draw(f, st, 3); eq({ faces(f.seat[3]), faces(f.seat[1]), f.seat[3].cards[1].points[1] }, { { "3C", "6C" }, { "back", "back" }, { "TOPLEFT", f, "TOPLEFT", 323, -322 } })
    draw(f, st, nil); eq({ faces(f.seat[1]), faces(f.seat[2]), f.foldButton:IsVisible(), f.closeButton:IsVisible() }, { { "back", "back" }, { "back", "back" }, false, false })
    -- the big cards are 40 x 58, the others 0.6 of that; the board 46 apart from (254, -176)
    eq({ { f.seat[1].cards[1]:GetSize() }, { f.seat[2].cards[1]:GetSize() } }, { { 40, 58 }, { 24, 34.8 } })
    eq({ f.board[1].points[1], f.board[5].points[1], { f.board[5]:GetSize() } }, { { "TOPLEFT", f, "TOPLEFT", 254, -176 }, { "TOPLEFT", f, "TOPLEFT", 438, -176 }, { 40, 58 } })
    -- the anchors: the pot, the text, the note and the log, the marks, the buttons
    eq({ f.pot.points[1], f.text.points[1], f.note.points[1], f.log.points[1] },
       { { "CENTER", f, "TOPLEFT", 366, -156 }, { "CENTER", f, "TOPLEFT", 366, -250 }, { "TOPLEFT", f, "TOPLEFT", 12, -366 }, { "TOPLEFT", f, "TOPLEFT", 12, -396 } })
    eq({ f.note:GetWidth(), f.log:GetWidth() }, { 270, 270 })
    eq({ f.seat[1].mark.points[1], f.seat[2].mark.points[1], f.seat[4].mark.points[1] },
       { { "CENTER", f, "TOPLEFT", 429, -388 }, { "CENTER", f, "TOPLEFT", 148, -300 }, { "CENTER", f, "TOPLEFT", 429, -10 } })
    local function at(b) local p = b.points[1]; return { p[4], p[5], b:GetWidth(), b:GetHeight() } end
    eq({ at(f.halfButton), at(f.potButton), at(f.allinButton), at(f.minusButton), at(f.plusButton), at(f.foldButton), at(f.callButton), at(f.raiseButton), at(f.closeButton) },
       { { 476, -336, 64, 22 }, { 546, -336, 64, 22 }, { 616, -336, 96, 22 }, { 476, -362, 24, 24 }, { 596, -362, 24, 24 },
         { 476, -388, 56, 26 }, { 536, -388, 86, 26 }, { 626, -388, 100, 26 }, { 12, -366, 96, 22 } })
    -- the shuffle: nobody holds a card yet, so none is drawn
    local sh = E.new{ seats = { true, true, true } }; ok(E.apply(sh, 0, { k = "hand" })); draw(f, sh, 2)
    eq({ faces(f.seat[1]), faces(f.seat[2]), faces(f.seat[3]), f.text:GetText() }, { { "-", "-" }, { "-", "-" }, { "-", "-" }, "Разбъркваме заедно…" })
  end)

  it("a fun table counts chips: plain numbers, a chip in the faction's colour, never a coin", function()
    for _, faction in ipairs({ "Alliance", "Horde" }) do
      local w, View, f = setup(faction); local T = w.ns.Theme; local st = hand3(); draw(f, st, 1)
      local skin = faction == "Horde" and "horde" or "alliance"
      eq({ T.skin, f.oval:GetTexture(), f.oval:GetTexture() == T.tex["oval_" .. skin] }, { skin, T.tex.oval, true })
      eq({ View.seatNote(sess(st, 1), 1), View.seatNote(sess(st, 1), 2), f.pot:GetText(), f.seat[2].bet:GetText(), f.seat[3].bet:GetText() },
         { "1000", "995", "Пот 15", "5", "10" })
      eq({ f.callButton.text:GetText(), f.raiseButton.text:GetText(), f.allinButton.text:GetText(), f.text:GetText() },
         { "Плащам 10", "Вдигам до 20", "Ва банк 1000", "Твой ход: 10 за плащане" })
      local bannerHi = { T.color.bannerHi[1], T.color.bannerHi[2], T.color.bannerHi[3], 1 }
      eq({ f.seat[2].chip:IsVisible(), f.seat[2].chip:GetTexture(), { f.seat[2].chip:GetVertexColor() }, { f.seat[3].chip:GetVertexColor() } },
         { true, T.tex.chip, bannerHi, bannerHi })
      eq({ T.SKINS[skin].color.bannerHi[1], { f.seat[1].mark.disc:GetVertexColor() } }, { T.color.bannerHi[1], { T.color.cream[1], T.color.cream[2], T.color.cream[3], 1 } })
      -- the chip and its bet side by side, the pair centred on the bet's place
      local p, sw = f.seat[2], f.seat[2].bet:GetStringWidth()
      eq({ p.chip.points[1], p.bet.points[1] }, { { "LEFT", f, "TOPLEFT", 250 - (16 + 3 + sw) / 2, -272 }, { "LEFT", f, "TOPLEFT", 250 - (16 + 3 + sw) / 2 + 19, -272 } })
      eq(#w:texts("|T"), 0)
    end
  end)

  it("„Пот“ and „+“ never leave the engine's range; the raise button sends what it shows", function()
    local w, View, f, acts = setup(); local st = hand3{ betting = "pl" }; draw(f, st, 1)
    eq({ f.callButton.text:GetText(), f.raiseButton.text:GetText(), f.allinButton:IsVisible(), f.potButton:IsVisible() }, { "Плащам 10", "Вдигам до 20", false, true })
    w:click(f.plusButton); eq({ f.want, f.raiseButton.text:GetText() }, { 30, "Вдигам до 30" }); w:click(f.plusButton); w:click(f.plusButton); eq(f.want, 35)
    w:click(f.minusButton); eq(f.want, 25); w:click(f.halfButton); eq(f.want, 22); w:click(f.potButton); eq({ f.want, f.raiseButton.text:GetText() }, { 35, "Вдигам до 35" })
    w:click(f.raiseButton); eq(acts, { { k = "raise", to = 35 } }); ok(E.apply(st, 1, acts[1])); eq({ f.raiseButton:IsEnabled(), f.foldButton:IsEnabled() }, { false, false })
    local s = sess(st, 2); s.seq = 2; View.update(f, s); eq({ f.want, f.callButton.text:GetText(), f.raiseButton.text:GetText() }, { nil, "Плащам 30", "Вдигам до 60" })
    w:click(f.callButton); eq({ acts[2], #acts, f.foldButton:IsEnabled() }, { { k = "call" }, 2, false })   -- sent: the buttons are dead until the event is back
    -- six digits at the 200 bb option: the label shrinks until it fits its button, and grows back
    drawAt(f, hand3({ blinds = 200, stack = 200 }, { [1] = 240000, [2] = 240000, [3] = 240000 }), 1, 9)
    local function size(b) return select(2, b.text:GetFont()) end
    eq({ f.raiseButton.text:GetText(), size(f.raiseButton), f.allinButton.text:GetText() }, { "Вдигам до 400", 13, "Ва банк 240000" })
    f.want = 123456; View.update(f, f.session)
    eq({ f.raiseButton.text:GetText(), f.callButton.text:GetText() }, { "Вдигам до 123456", "Плащам 200" })
    ok(size(f.raiseButton) < 13 and size(f.raiseButton) >= 10, "the label kept its size")
    for _, b in ipairs({ f.raiseButton, f.allinButton, f.callButton }) do ok(b.text:GetStringWidth() <= b:GetWidth() - 6, b.text:GetText() .. " is wider than its button") end
    f.want = nil; View.update(f, f.session); eq(size(f.raiseButton), 13)
    -- a refused action leaves the buttons alive
    drawAt(f, st, 2, 3); w.ns.client.act = function() return nil, "refused" end
    w:click(f.foldButton); eq({ f.sent, f.foldButton:IsEnabled(), f.callButton:IsEnabled() }, { nil, true, true })
  end)

  it("No Limit: „Ва банк“ sends all-in; a short stack has no raise row; check when nothing is owed", function()
    local w, View, f, acts = setup(); local st = hand3(); draw(f, st, 1)
    eq({ f.allinButton:IsVisible(), f.allinButton.text:GetText(), f.foldButton.text:GetText(), f.halfButton.text:GetText(), f.potButton.text:GetText() },
       { true, "Ва банк 1000", "Пас", "½ пот", "Пот" })
    w:click(f.allinButton); eq(acts, { { k = "allin" } })

    drawAt(f, hand3(nil, { [1] = 15 }), 1, 2)
    eq({ f.raiseButton:IsVisible(), f.plusButton:IsVisible(), f.minusButton:IsVisible(), f.halfButton:IsVisible(), f.potButton:IsVisible() }, { false, false, false, false, false })
    eq({ f.allinButton.text:GetText(), f.callButton.text:GetText(), f.foldButton:IsVisible() }, { "Ва банк 15", "Плащам 10", true })

    st = hand3(); ok(E.apply(st, 1, { k = "call" })); ok(E.apply(st, 2, { k = "call" })); drawAt(f, st, 3, 3)
    eq(f.callButton.text:GetText(), "Чек"); w:click(f.callButton); eq(acts[2], { k = "check" })
    ok(E.apply(st, 3, { k = "check" })); ok(E.apply(st, 0, E.system(st))); drawAt(f, st, 2, 4)
    eq({ f.raiseButton.text:GetText(), f.callButton.text:GetText() }, { "Залагам 10", "Чек" }); w:click(f.raiseButton); eq(acts[3], { k = "bet", to = 10 })
    -- not my turn: no buttons
    drawAt(f, st, 3, 5); eq({ f.foldButton:IsVisible(), f.callButton:IsVisible(), f.raiseButton:IsVisible(), f.allinButton:IsVisible() }, { false, false, false, false })
  end)

  it("after the showdown: the shown hands, what was won, the words and the log; a folded hand stays down for a watcher", function()
    local w, View, f = setup()
    local st = hand3(); ok(E.apply(st, 1, { k = "call" })); ok(E.apply(st, 2, { k = "call" })); ok(E.apply(st, 3, { k = "check" })); ok(E.apply(st, 0, E.system(st)))
    ok(E.apply(st, 2, { k = "bet", to = 20 })); ok(E.apply(st, 3, { k = "fold" })); ok(E.apply(st, 1, { k = "call" }))
    drawAt(f, st, 3, 2); eq({ faces(f.seat[3]), f.seat[3].cards[1]:GetAlpha(), f.seat[1].cards[1]:GetAlpha() }, { { "3C", "6C" }, 0.5, 1 })   -- folded: my cards dimmed
    local guard = 0
    while st.phase ~= "done" do
      guard = guard + 1; assert(guard < 20, "the hand did not end")
      if st.phase == "bet" then ok(E.apply(st, st.turn, { k = "check" })) else ok(E.apply(st, 0, E.system(st))) end
    end
    draw(f, st, 3)
    eq({ faces(f.seat[1]), faces(f.seat[2]), faces(f.seat[3]), f.seat[3].cards[1]:GetAlpha(), f.seat[3].cards[2]:GetAlpha() }, { { "4C", "7C" }, { "2C", "5C" }, { "3C", "6C" }, 0.5, 0.5 })
    local board = {}
    for j = 1, 5 do board[j] = f.board[j]:IsVisible() and f.board[j].card.face or "-" end
    eq(board, { "9C", "TC", "JC", "KC", "2D" })
    eq({ f.seat[1].bet:GetText(), { f.seat[1].bet:GetTextColor() }, f.seat[2].bet:IsVisible(), f.seat[1].chip:IsVisible() },
       { "+70", { w.ns.Theme.color.good[1], w.ns.Theme.color.good[2], w.ns.Theme.color.good[3], 1 }, false, true })
    eq({ plain(f.text:GetText()), { f.text:GetTextColor() }, f.log:GetText(), f.pot:IsVisible() },
       { "Иван Петров взе 70 с флош", { w.ns.Theme.color.gold[1], w.ns.Theme.color.gold[2], w.ns.Theme.color.gold[3], 1 }, "#1 Иван Петров взе 70 с флош", false })
    ok(f.text:GetText() ~= plain(f.text:GetText()), "the name is not coloured")
    draw(f, st, nil); eq(faces(f.seat[3]), { "-", "-" })
  end)

  it("an all-in turns the live hands up before the board runs out, for a watcher too; a folded hand stays down", function()
    local w, View, f = setup()
    local st = hand3(); ok(E.apply(st, 1, { k = "call" })); ok(E.apply(st, 2, { k = "fold" })); ok(E.apply(st, 3, { k = "check" }))
    ok(E.apply(st, 0, E.system(st))); ok(E.apply(st, 3, { k = "check" })); ok(E.apply(st, 1, { k = "check" }))
    ok(E.apply(st, 0, E.system(st))); ok(E.apply(st, 3, { k = "allin" }))
    draw(f, st, nil); eq({ faces(f.seat[1]), faces(f.seat[2]), faces(f.seat[3]) }, { { "back", "back" }, { "-", "-" }, { "back", "back" } }) -- the call is open
    ok(E.apply(st, 1, { k = "call" })); eq(#st.board, 4)
    for _, seat in ipairs({ 0, 1, 3 }) do
      draw(f, st, seat ~= 0 and seat or nil)
      eq({ faces(f.seat[1]), faces(f.seat[2]), faces(f.seat[3]) }, { { "4C", "7C" }, { "-", "-" }, { "3C", "6C" } }, "seat " .. seat)
      for _, face in ipairs({ "2C", "5C" }) do eq(#w:texts(face), 0) end
    end
  end)

  it("the host's „Приключи“; solo with bots from a real deal", function()
    local w, View, f = setup(); local st = hand3(); draw(f, st, 1)
    local called = {}
    w.ns.Cash.close = function(client) called[#called + 1] = client end
    eq({ f.closeButton:IsVisible(), f.closeButton.text:GetText() }, { true, "Приключи" }); w:click(f.closeButton); eq({ #called, called[1] == w.ns.client }, { 1, true })
    draw(f, st, 2); eq(f.closeButton:IsVisible(), false)
    ok(E.apply(st, 0, { k = "close" })); drawAt(f, st, 1, 2)
    eq({ f.closeButton:IsVisible(), f.note:IsVisible(), f.note:GetText(), f.note.points[1] }, { false, true, "Последна ръка: след нея играта приключва.", { "TOPLEFT", f, "TOPLEFT", 12, -366 } })

    w = withBots(); local client, T = w.ns.client, w.ns.TableFrame
    client:openTable{ game = "holdem", access = "invite", turn = 45 }; w:advance(0)
    eq(w.ns.bots:fill(2), 2); w:advance(6); T.startGame(); w:advance(4)
    local V, s = T.built.holdem, client.session
    ok(V, "no Холдем table"); eq({ T.frame:GetSize() }, { 760, 532 }); eq(T.view.info.topic, "holdem")
    local guard = 0
    while not (s.state.phase == "bet") do guard = guard + 1; assert(guard < 20, "no hand dealt"); w:advance(1) end
    local mine, others = faces(V.seat[s.mySeat]), {}
    for i = 1, 3 do if i ~= s.mySeat then others[#others + 1] = faces(V.seat[i]) end end
    ok(mine[1] ~= "-" and mine[1] ~= "back" and mine[2] ~= "-" and mine[2] ~= "back", "my cards are not faces")
    eq(others, { { "back", "back" }, { "back", "back" } })
    guard = 0
    while not V.callButton:IsVisible() do guard = guard + 1; assert(guard < 60, "my turn never came"); w:advance(1) end
    local seq = s.seq
    w:click(V.callButton); w:advance(1)
    ok(s.seq > seq, "the game did not move on")
    guard = 0
    while s.state.hand < 9 do
      guard = guard + 1; assert(guard < 600, "eight hands were not played: " .. tostring(s.state.hand))
      if V.callButton:IsVisible() and V.callButton:IsEnabled() then          -- check, else fold: my stack outlasts the eight hands whatever the bots do
        w:click(V.callButton.text:GetText() == "Чек" and V.callButton or V.foldButton)
      end
      w:advance(1)
    end
    local line = T.view.fairLine
    ok(line:IsVisible(), "no book line"); ok(line.text:GetText():find("Ръце за проверка при затварянето: ", 1, true), line.text:GetText())
  end)

  describe("my hand label", function()
    -- Checks and calls until the board has n cards (a hand3 table: nobody raises).
    local function toBoard(st, n)
      local guard = 0
      while #st.board < n do
        guard = guard + 1; assert(guard < 40, "no board")
        if st.phase == "bet" then
          local a = { k = "call" }; for _, l in ipairs(E.legal(st, st.turn)) do if l.k == "check" then a = { k = "check" } end end
          ok(E.apply(st, st.turn, a))
        else ok(E.apply(st, 0, E.system(st))) end
      end
    end
    -- Draws seat `seat`'s view with its hole cards and the board faces replaced (a pair, a house…).
    local function drawWith(f, st, seat, hole, board)
      local s = sess(st, seat)
      for j = 1, 2 do s.state.deck[s.state.p[seat].cards[j]] = hole[j] end
      for j, face in ipairs(board or {}) do s.state.deck[s.state.board[j]] = face end
      s.seq = (f.seqN or 1) + 1; f.seqN = s.seq
      current.update(f, s)
    end
    local function label(f) return f.handLabel:IsVisible() and plain(f.handLabel:GetText()) or nil end

    it("preflop it reads my two cards alone; after the flop, turn and river it follows the board", function()
      local w, View, f = setup()
      local st = hand3()
      drawWith(f, st, 3, { "AS", "AD" })
      eq(label(f), "Чифт аса")
      drawWith(f, st, 3, { "AS", "KD" }); eq(label(f), "Висока карта: асо")
      toBoard(st, 3); drawWith(f, st, 3, { "AS", "AD" }, { "2C", "5D", "9H" }); eq(label(f), "Чифт аса")
      toBoard(st, 4); drawWith(f, st, 3, { "AS", "AD" }, { "2C", "5D", "9H", "AC" }); eq(label(f), "Тройка аса")
      toBoard(st, 5); drawWith(f, st, 3, { "AS", "AD" }, { "2C", "5D", "9H", "AC", "AH" }); eq(label(f), "Каре аса")
      local c = w.ns.Theme.color.goldHi
      eq({ f.handLabel:GetTextColor() }, { c[1], c[2], c[3], 1 })
    end)
    it("the other categories in words, the house with the ranks", function()
      local w, View, f = setup()
      local st = hand3(); toBoard(st, 5)
      local function is(hole, board, text) drawWith(f, st, 3, hole, board); eq(label(f), text) end
      is({ "7S", "7D" }, { "2C", "5D", "9H", "KC", "3D" }, "Чифт седмици")
      is({ "AS", "KD" }, { "AC", "KH", "9H", "2C", "3D" }, "Два чифта: аса и попове")
      is({ "7S", "7D" }, { "7C", "5D", "9H", "KC", "3D" }, "Тройка седмици")
      is({ "9S", "8D" }, { "TC", "JH", "QH", "2C", "3D" }, "Кента до дама")
      is({ "AS", "2D" }, { "3C", "4H", "5H", "KC", "9D" }, "Кента до петица")
      is({ "9S", "8D" }, { "7C", "6H", "5H", "KC", "2D" }, "Кента до деветка")
      w.ns.Locale.set("en"); is({ "9S", "8D" }, { "7C", "6H", "5H", "KC", "2D" }, "Straight to the Nine"); w.ns.Locale.set("bg")
      is({ "AS", "9S" }, { "2S", "5S", "KS", "KC", "3D" }, "Флош до асо")
      is({ "AS", "AD" }, { "AC", "QH", "QD", "2C", "3D" }, "Фул хаус (AAA QQ)")
      is({ "9S", "8S" }, { "TS", "JS", "QS", "2C", "3D" }, "Кент флош до дама")
      is({ "AS", "KS" }, { "QS", "JS", "TS", "2C", "3D" }, "Роял флош")
    end)
    it("hidden for a watcher, a folded hand and while the deal is shuffled; nothing of it is sent", function()
      local w, View, f = setup()
      local st = hand3()
      local sent = #w.sent
      drawWith(f, st, 3, { "AS", "AD" }); eq(label(f), "Чифт аса")
      draw(f, st, nil); eq(label(f), nil)
      ok(E.apply(st, 1, { k = "call" })); ok(E.apply(st, 2, { k = "call" })); ok(E.apply(st, 3, { k = "fold" }))
      drawWith(f, st, 3, { "AS", "AD" }); eq(label(f), nil)
      eq(#w.sent, sent)
      for _, m in ipairs(w.sent) do ok(not tostring(m.text or m.msg or m):find("аса", 1, true)) end
    end)
    it("is not recomputed while the cards stay the same", function()
      local w, View, f = setup()
      local st = hand3(); local n = 0
      local describe = w.ns.HoldemEval.describe
      w.ns.HoldemEval.describe = function(x) n = n + 1; return describe(x) end
      drawWith(f, st, 3, { "AS", "AD" }); drawWith(f, st, 3, { "AS", "AD" }); drawWith(f, st, 3, { "AS", "AD" })
      eq(n, 1)
    end)
  end)
end)
