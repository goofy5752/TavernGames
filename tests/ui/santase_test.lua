local Wow = require("wow")

local ME = "Иван Петров"
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

-- I open Сантасе „Само поканени“, „Бот Иванов“ takes the invitation through
-- the „Покани“ picker and a hand is dealt: the view's frame and the view.
local function santaseWithBot()
  local w = withBots()
  w.ns.client:openTable{ game = "santase", access = "invite", turn = 45 }
  w:advance(0)
  local v = w.ns.TableFrame.view
  w:click(v.inviteButton)
  local row
  for _, r in ipairs(v.picker.rows) do
    if r.frame:IsVisible() and r.name:GetText() == BOT then row = r end
  end
  assert(row, "no row for the bot in the picker")
  w:click(row.frame)
  w:advance(2)
  return w, w.ns.TableFrame.built.santase, w.ns.TableFrame.views.santase
end

local function show(w, state)
  w.ns.client.session.state = state
  w.ns.TableFrame.render()
end

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

-- DM[i] = the face of deck index i: seat 1 (me) holds 1–3 and 7–9, seat 2 4–6
-- and 10–12, the trump card is JH.
local DM = { "KH", "QH", "TS", "AS", "JC", "QC", "JD", "AD", "9S", "KC", "TC", "AC",
             "JH", "9D", "QD", "KD", "TD", "9H", "TH", "AH", "JS", "QS", "KS", "9C" }

describe("ui: Сантасе view", function()
  local E = guildWow().ns.Engines.santase -- the engine's code, for states built by hand
  local function full()
    local st = E.new{ first = 1 }
    assert(E.apply(st, 0, { k = "deal", deck = DM }))
    return st
  end
  local boot = santaseWithBot

  it("my lead: the hand sorted by suit, a 40 to declare, „Затвори“ offered, no swap", function()
    local w, V, View = boot(); local s = w.ns.client.session; s.state = E.view(full(), 1)
    local m = View.model(s, false); local ids, modes = {}, {}
    for k, c in ipairs(m.hand) do ids[k], modes[k] = c.i, c.mode end
    eq(ids, { 8, 7, 1, 2, 3, 9 }); eq(modes, { "plain", "plain", "plain", "plain", "plain", "plain" })   -- AD JD | KH QH | TS 9S
    eq({ m.buttons.marry, m.buttons.swap, m.buttons.close }, { 40, nil, true }); eq({ m.stock, m.trump, m.tsuit, m.closed }, { 12, "JH", "H", false })
    eq(m.text, { "santase.yourTurn" }); eq(#m.oppHand, 6); eq(m.oppHand[1].face, nil)
    show(w, s.state); eq(V.marryButton:IsVisible(), true); eq(V.marryButton.text:GetText(), "Обяви 40"); eq(V.swapButton:IsVisible(), false)
    eq(V.closeButton:IsVisible(), true); eq(#w:texts("Тесте: 12 карти"), 1); eq(#w:texts("Коз: купа"), 1); eq(V.oppFan.cards[1].face, nil)
  end)

  it("armed „Обяви 40“: only the king and queen are raised, and a click declares", function()
    local w, V, View = boot(); local s = w.ns.client.session; show(w, E.view(full(), 1))
    w:click(V.marryButton); local modes = {}; for k, c in ipairs(View.model(s, true).hand) do modes[k] = c.mode end
    eq(modes, { "dim", "dim", "raised", "raised", "dim", "dim" }); eq(#w:texts("Избери попа или дамата"), 1)
    eq(V.myFan.cards[1].mode, "dim"); eq(V.myFan.cards[3].mode, "raised")
    local sent; w.ns.client.act = function(_, a) sent = a; return true end
    w:click(V.myFan.cards[3].frame); eq(sent, { k = "marry", i = 1, c = "KH", j = 2, d = "QH" })
    eq(#w:texts("Избери попа или дамата"), 0); eq(V.myFan.cards[1].mode, "plain") -- the click ended the armed state
  end)

  it("„Обяви“ is disarmed by a second click and by any event", function()
    local w, V = boot(); local s = w.ns.client.session; show(w, E.view(full(), 1))
    w:click(V.marryButton); eq(#w:texts("Избери попа или дамата"), 1)
    w:click(V.marryButton); eq(#w:texts("Избери попа или дамата"), 0)
    w:click(V.marryButton); s.seq = s.seq + 1; w.ns.TableFrame.render()
    eq(#w:texts("Избери попа или дамата"), 0); eq(#w:texts("Твой ход"), 1)
  end)

  it("closed stock: cards I may not play are dimmed and not clickable", function()
    local st = full(); ok(E.apply(st, 1, { k = "play", i = 9, c = "9S" })); ok(E.apply(st, 2, { k = "play", i = 4, c = "AS" }))   -- seat 2 wins, draws 14, I draw 15
    ok(E.apply(st, 2, { k = "close" })); ok(E.apply(st, 2, { k = "play", i = 12, c = "AC" }))
    local w, V, View = boot(); local s = w.ns.client.session; show(w, E.view(st, 1))
    local ids, modes = {}, {}; for k, c in ipairs(View.model(s, false).hand) do ids[k], modes[k] = c.i, c.mode end
    eq(ids, { 8, 15, 7, 1, 2, 3 }); eq(modes, { "dim", "dim", "dim", "raised", "raised", "dim" })     -- no club: I must trump with KH or QH
    local sent; w.ns.client.act = function(_, a) sent = a; return true end
    w:click(V.myFan.cards[1].frame); eq(sent, nil); w:click(V.myFan.cards[4].frame); eq(sent, { k = "play", i = 1, c = "KH" })
    eq(#w:texts("Тестето е затворено"), 1); eq(V.closeButton:IsVisible(), false); eq(V.trick[1].face, "AC")
    eq(V.trumpCard.face, nil); ok(V.trumpCard.frame:IsVisible()) -- turned down over the stock
    eq(#w:texts("Последна взятка"), 1); eq({ V.lastCards[1].face, V.lastCards[2].face }, { "9S", "AS" })
  end)

  it("„Смени деветката“ shows only when the swap is legal", function()
    local st = full(); st.ntr[1] = 1; st.deck[9], st.deck[18] = st.deck[18], st.deck[9] -- index 9 is now 9H
    local w, V, View = boot(); local s = w.ns.client.session; show(w, E.view(st, 1))
    eq(View.model(s, false).buttons.swap, { k = "swap9", i = 9, c = "9H" })
    eq(V.swapButton:IsVisible(), true); eq(V.swapButton.text:GetText(), "Смени деветката")
    local sent; w.ns.client.act = function(_, a) sent = a; return true end
    w:click(V.swapButton); eq(sent, { k = "swap9", i = 9, c = "9H" })
    w:click(V.closeButton); eq(sent, { k = "close" })
    st.ntr[1] = 0; show(w, E.view(st, 1))
    eq(View.model(s, false).buttons.swap, nil); eq(V.swapButton:IsVisible(), false)
  end)

  it("a watcher sees two hands of backs and no buttons; the end of a hand and of the match are announced", function()
    local w, V, View = boot(); local s = w.ns.client.session
    s.mySeat, s.role = nil, "watcher"
    local st = E.view(full(), 0); show(w, st)
    local m = View.model(s, false)
    eq(#m.hand, 6); for _, c in ipairs(m.hand) do eq(c.face, nil); eq(c.mode, "plain") end
    eq({ m.buttons.marry, m.buttons.swap, m.buttons.close }, { nil, nil, false })
    eq(m.text, { "santase.waitFor", ME }); eq(#plainTexts(w, "Изчакай Иван Петров…"), 1)
    eq(V.marryButton:IsVisible(), false); eq(V.closeButton:IsVisible(), false)
    eq(View.seatNote(s, 1), "0 точки")
    st.phase, st.res = "hand", { winner = 1, gp = 2, reason = "66" }; show(w, st)
    eq(#plainTexts(w, "Иван Петров взима ръката: +2"), 1); eq(View.seatNote(s, 1), "")
    st.phase, st.winner = "match", 2; show(w, st)
    eq(#plainTexts(w, "Бот Иванов печели партията!"), 1)
  end)

  it("a player who left is named although the seat is empty now", function()
    local w, V, View = boot(); local s = w.ns.client.session
    local st = E.view(full(), 1); show(w, st)
    s.seats[2] = false; E.leave(st, 2); show(w, st)
    eq(#plainTexts(w, "Бот Иванов стана от масата."), 1)
    eq(View.model(s, false).text, { "santase.match", ME }) -- without the view's memory: the winner
  end)

  it("solo against a bot from a real deal: six faces for me, six backs for the bot, a click plays", function()
    local w, V = boot(); local s = w.ns.client.session
    eq(#s.state.hands[1], 6); for k = 1, 6 do ok(V.myFan.cards[k].face); eq(V.oppFan.cards[k].face, nil) end
    ok(V.trumpCard.face); local i = V.myFan.cards[1].entry.i; w:click(V.myFan.cards[1].frame); w:advance(0)
    eq(s.state.trick[1], i); w:advance(2); eq(#s.state.trick, 0)       -- the bot answered after 1.5 s and the trick was taken
    -- (2 s, not 3: a bot that takes the trick leads the next one 1.5 s later, at 3 s)
  end)
end)
