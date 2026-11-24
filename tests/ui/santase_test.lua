local Wow = require("wow")

local ME = "Иван Петров"
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

-- I open Сантасе „Само поканени“, „Bot Ivanov“ takes the invitation through
-- the „Покани“ picker and a hand is dealt: the view's frame and the view.
local function santaseWithBot()
  local w = withBots()
  w.ns.client:openTable{ game = "santase", access = "invite", turn = 45 }
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

  it("a 40 and a 20 in hand: the button says „Обяви 20 / 40“, not just 40", function()
    local w, V, View = boot(); local s = w.ns.client.session; s.state = E.view(full(), 1)
    s.state.deck[3], s.state.deck[9] = "KS", "QS" -- TS 9S become a plain marriage beside KH QH (trump)
    local m = View.model(s, false)
    eq({ m.buttons.marry, m.buttons.marryBoth }, { 40, true })
    show(w, s.state); eq(V.marryButton.text:GetText(), "Обяви 20 / 40")
    s.state = E.view(full(), 1); m = View.model(s, false); eq({ m.buttons.marry, m.buttons.marryBoth }, { 40, nil })
  end)

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

  it("a completed trick stays on the felt for 1.5 s; a new lead ends the hold at once; the last trick of a hand is held", function()
    local w, V, View = boot(); local s = w.ns.client.session
    local function seen() return { V.trick[1].frame:IsVisible() and V.trick[1].face, V.trick[2].frame:IsVisible() and V.trick[2].face } end
    local st = full(); show(w, E.view(st, 1))
    ok(E.apply(st, 1, { k = "play", i = 9, c = "9S" })); show(w, E.view(st, 1)); eq(seen(), { "9S", false })
    ok(E.apply(st, 2, { k = "play", i = 4, c = "AS" })); show(w, E.view(st, 1))
    eq(seen(), { "9S", "AS" }); eq(V.lastCards[1].frame:IsVisible(), false)                    -- not twice on the felt
    w:advance(1.4); eq(seen(), { "9S", "AS" })
    w:advance(0.2); eq(seen(), { false, false }); eq({ V.lastCards[1].face, V.lastCards[2].face }, { "9S", "AS" })
    -- a lead during the hold: seat 2 took the first trick and leads
    local w2, V2 = boot(); local st2 = full(); w2.ns.client.session.state = E.view(st2, 1); w2.ns.TableFrame.render()
    ok(E.apply(st2, 1, { k = "play", i = 9, c = "9S" })); ok(E.apply(st2, 2, { k = "play", i = 4, c = "AS" })); show(w2, E.view(st2, 1))
    local lead = E.legal(st2, 2)[1]; ok(E.apply(st2, 2, lead)); show(w2, E.view(st2, 1))
    eq({ V2.trick[1].frame:IsVisible(), V2.trick[2].frame:IsVisible(), V2.trick[1].face }, { true, false, E.view(st2, 1).deck[lead.i] })
    w2:advance(2); eq({ V2.trick[1].frame:IsVisible(), V2.trick[2].frame:IsVisible() }, { true, false })
    -- the last trick of a hand: the hand's end waits for the hold
    local w3, V3 = boot(); local st3 = full(); w3.ns.client.session.state = E.view(st3, 1); w3.ns.TableFrame.render()
    ok(E.apply(st3, 1, { k = "play", i = 9, c = "9S" })); ok(E.apply(st3, 2, { k = "play", i = 4, c = "AS" }))
    st3.phase, st3.res = "hand", { winner = 2, gp = 1, reason = "66" }; show(w3, E.view(st3, 1))
    eq({ V3.trick[1].face, V3.trick[2].face }, { "9S", "AS" }); eq(#plainTexts(w3, "взима ръката"), 1)
    w3:advance(1.6); eq({ V3.trick[1].frame:IsVisible(), V3.trick[2].frame:IsVisible() }, { false, false })
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
    ok(V.stockCard.frame:GetFrameLevel() > V.trumpCard.over:GetFrameLevel(), "the stock must clear the trump card's top layers")
    eq(#w:texts("Последна взятка"), 1); eq({ V.lastCards[1].face, V.lastCards[2].face }, { "9S", "AS" })
  end)

  it("Сантасе and Белот count tricks on the plates", function()
    local st = full(); ok(E.apply(st, 1, { k = "play", i = 9, c = "9S" })); ok(E.apply(st, 2, { k = "play", i = 4, c = "AS" })) -- seat 2 wins
    local w, _, View = boot(); local s = w.ns.client.session; show(w, E.view(st, 1))
    local v, T = w.ns.TableFrame.view, w.ns.Theme
    eq({ View.seatTricks(s, 1), View.seatTricks(s, 2) }, { 0, 1 })
    local pip = v.plates[2].tricks[1]
    ok(pip:IsVisible(), "no pip on the winner's plate"); eq(v.plates[2].tricks[2]:IsVisible(), false)
    for k = 1, 8 do eq(v.plates[1].tricks[k]:IsVisible(), false, "pip " .. k) end
    eq({ pip:GetSize() }, { 5, 8 }); eq(pip.color, { T.color.banner[1], T.color.banner[2], T.color.banner[3], 1 })
    eq(v.plates[2].tricks[2].points[1], { "LEFT", pip, "RIGHT", 3, 0 })
    st.phase, st.res = "hand", { winner = 2, gp = 1, reason = "66" }; show(w, E.view(st, 1))
    eq(View.seatTricks(s, 2), nil); eq(pip:IsVisible(), false)                         -- outside play: none
  end)

  it("„Обяви“ is the gold button of the mockup; „Смени деветката“ stays the dark one", function()
    local w, V = boot(); show(w, E.view(full(), 1))
    local T = w.ns.Theme
    eq({ V.marryButton.text:GetTextColor() }, { T.color.woodDark[1], T.color.woodDark[2], T.color.woodDark[3], 1 })
    eq(V.marryButton.fill.color, { 0xdc / 255, 0xb4 / 255, 0x67 / 255, 1 })
    eq(V.marryButton.lip.color, { 0x8a / 255, 0x5a / 255, 0x2b / 255, 1 })
    eq({ V.swapButton.text:GetTextColor() }, { T.color.brassLight[1], T.color.brassLight[2], T.color.brassLight[3], 1 })
    w:click(V.marryButton); eq(V.marryButton.lit, true)                          -- armed: the rim lights up
    eq(V.marryButton.edges[1].vertex, { T.color.gold[1], T.color.gold[2], T.color.gold[3], 1 })
  end)

  it("a table that is not live plays nothing from a click", function()
    local w, V = boot(); local s = w.ns.client.session; show(w, E.view(full(), 1))
    local sent; w.ns.client.act = function(_, a) sent = a; return true end
    s.status = "aborted"; w.ns.TableFrame.render()
    w:click(V.myFan.cards[1].frame); eq(sent, nil)
    s.status = "live"; w.ns.TableFrame.render()
    w:click(V.myFan.cards[1].frame); ok(sent)
  end)

  it("the end of the match is what the session says it is (Session:gameOver), not a phase name", function()
    local w, _, View = boot(); local s = w.ns.client.session
    local st = E.view(full(), 1); st.winner = 2; show(w, st)
    eq(View.model(s, false).text, { "santase.yourTurn" })
    s.gameOver = function() return true end
    eq(View.model(s, false).text, { "santase.match", BOT })
    w.ns.TableFrame.render(); eq(#plainTexts(w, "Ivanov " .. w.ns.W.BOT_MARK .. " печели партията!"), 1)
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
    eq(m.text, { "santase.waitFor", ME }); eq(#plainTexts(w, "Изчакай Иван…"), 1)
    eq(V.marryButton:IsVisible(), false); eq(V.closeButton:IsVisible(), false)
    eq(View.seatNote(s, 1), "0 точки")
    st.phase, st.res = "hand", { winner = 1, gp = 2, reason = "66" }; show(w, st)
    eq(#plainTexts(w, "Иван взима ръката: +2"), 1); eq(View.seatNote(s, 1), "")
    st.phase, st.winner = "match", 2; show(w, st)
    eq(#plainTexts(w, "Ivanov " .. w.ns.W.BOT_MARK .. " печели партията!"), 1)
  end)

  it("a player who left is named although the seat is empty now", function()
    local w, V, View = boot(); local s = w.ns.client.session
    local st = E.view(full(), 1); show(w, st)
    s.seats[2] = false; E.leave(st, 2); show(w, st)
    eq(#plainTexts(w, "Ivanov " .. w.ns.W.BOT_MARK .. " стана от масата."), 1)
    eq(View.model(s, false).text, { "santase.match", ME }) -- without the view's memory: the winner
  end)

  it("the end line of the match hides under the bill of a staked match (StakePanels.shown); nothing else does", function()
    local w, V, View = boot(); local s = w.ns.client.session
    local P = w.ns.StakePanels
    local st = E.view(full(), 1); show(w, st)
    P.shown = true; View.update(V, s)
    eq(V.text:IsVisible(), true); eq(plain(V.text:GetText()), "Твой ход") -- a running match keeps its line
    st.phase, st.winner = "match", 2
    P.shown = false; View.update(V, s)
    eq(V.text:IsVisible(), true); eq(plain(V.text:GetText()), "Ivanov " .. w.ns.W.BOT_MARK .. " печели партията!")
    P.shown = true; View.update(V, s)
    eq(V.text:IsVisible(), false)
    P.shown = false; View.update(V, s)
    eq(V.text:IsVisible(), true); eq(plain(V.text:GetText()), "Ivanov " .. w.ns.W.BOT_MARK .. " печели партията!")
  end)

  it("solo against a bot from a real deal: six faces for me, six backs for the bot, a click plays", function()
    local w, V = boot(); local s = w.ns.client.session
    eq(#s.state.hands[1], 6); for k = 1, 6 do ok(V.myFan.cards[k].face); eq(V.oppFan.cards[k].face, nil) end
    ok(V.trumpCard.face); local i = V.myFan.cards[1].entry.i; w:click(V.myFan.cards[1].frame); w:advance(0)
    eq(s.state.trick[1], i); w:advance(2); eq(#s.state.trick, 0)       -- the bot answered after 1.5 s and the trick was taken
    -- (2 s, not 3: a bot that takes the trick leads the next one 1.5 s later, at 3 s)
  end)
end)
