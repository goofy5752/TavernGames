local Wow = require("wow")

local ME, BOT = "Иван Петров", "Bot Ivanov"
-- The sound ids the test client's SOUNDKIT gives each moment's first name (wow/Art.lua SOUNDS).
local OPEN, CLOSE, DEAL, TRICK, COIN = 501, 502, 503, 504, 120

-- In a guild, booted with the ui/ files, PLAYER_LOGIN fired, every moment's sound known to SOUNDKIT.
local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  local K = w.G.SOUNDKIT
  K.IG_CHARACTER_INFO_OPEN, K.IG_CHARACTER_INFO_CLOSE, K.IG_ABILITY_PAGE_TURN = OPEN, CLOSE, DEAL
  K.IG_BACKPACK_OPEN, K.LOOT_WINDOW_COIN_SOUND = TRICK, COIN
  w:boot(); w:firstRunDone(); w:fire("GUILD_ROSTER_UPDATE"); w:fire("PLAYER_LOGIN")
  return w
end

-- How many times sound `id` played.
local function count(w, id)
  local n = 0
  for _, s in ipairs(w.sounds) do if s[1] == id then n = n + 1 end end
  return n
end

-- The view of `game` built over a parent of its own -> w, View, f.
local function viewOf(game)
  local w = guildWow()
  local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent)
  parent:SetSize(732, 440)
  local View = w.ns.TableFrame.views[game]
  return w, View, View.build(parent)
end

describe("ui: Sounds.once", function()
  it("a deal sounds once per hand, my trick once per trick, and nothing when I join mid-hand", function()
    local w = guildWow()
    local S = w.ns.Sounds
    eq(S.once("deal", "t:1:1"), false); eq(S.once("deal", "t:1:1"), false); eq(S.once("deal", "t:1:2"), true)
    eq(count(w, DEAL), 1)
    eq(S.once("trick", "t:2:1"), false); eq(S.once("trick", "t:2:2"), true); eq(S.once("trick", "t:2:2"), false)
    eq(count(w, TRICK), 1)
  end)

  it("first sight is silent per table: another table's first key is remembered quietly too", function()
    local w = guildWow()
    local S = w.ns.Sounds
    eq(S.once("deal", "a:1", "a"), false); eq(S.once("deal", "a:2", "a"), true)
    eq(S.once("deal", "b:7", "b"), false); eq(S.once("deal", "b:8", "b"), true)
    eq(S.once("deal", "a:3", "a"), true)
  end)

  it("a new key that is not audible is remembered without a sound", function()
    local w = guildWow()
    local S = w.ns.Sounds
    eq(S.once("trick", "t:1:0", "t", false), false); eq(S.once("trick", "t:1:1", "t", true), true)
    eq(S.once("trick", "t:2:0", "t", false), false); eq(#w.sounds, 1)
    eq(S.once("trick", "t:2:1", "t", true), true)
  end)

  it("muted: nothing plays", function()
    local w = guildWow()
    local S = w.ns.Sounds
    eq(w.ns.Art.play("coins"), true); local n = #w.sounds
    w.ns.db.sound = false
    eq(S.once("deal", "t:1"), false); eq(S.once("deal", "t:2"), false); eq(#w.sounds, n)
  end)
end)

describe("ui: window sounds", function()
  it("the window opens and closes with a sound", function()
    local w = guildWow()
    local MW = w.ns.MainWindow
    local n = #w.sounds
    MW.show(); eq(#w.sounds, n + 1); eq(w.sounds[n + 1], { OPEN, "SFX" })
    MW.show("settings"); eq(#w.sounds, n + 1) -- already open: no second sound
    MW.hide(); eq(#w.sounds, n + 2); eq(w.sounds[n + 2], { CLOSE, "SFX" })
  end)

  it("the table window opens and closes with a sound", function()
    local w = guildWow()
    w.ns.client:openTable{ game = "santase", access = "invite", turn = 45 }
    w:advance(0)
    local f = w.ns.TableFrame.frame
    ok(f:IsShown(), "no table window"); eq(count(w, OPEN), 1)
    f:Hide(); eq(count(w, CLOSE), 1)
  end)
end)

describe("ui: game sounds", function()
  it("Сантасе at a table I host: its first deal sounds, then my trick once per trick", function()
    local w = guildWow()
    w:slash("bots"); w:advance(0); w:advance(0)
    w.ns.client:openTable{ game = "santase", access = "invite", turn = 45 }
    w:advance(0)
    local v = w.ns.TableFrame.view
    w:click(v.inviteButton)
    for _, r in ipairs(v.picker.rows) do
      if r.frame:IsVisible() and r.name:GetText() == BOT then w:click(r.frame) end
    end
    w:advance(2)
    local s = w.ns.client.session
    eq(s.state.hand, 1); eq(count(w, DEAL), 1)
    w.ns.TableFrame.render(); eq(count(w, DEAL), 1) -- the same hand again: no second sound
    s.state.won = { { 1, 4 }, {} }; w.ns.TableFrame.render(); eq(count(w, TRICK), 1)
    w.ns.TableFrame.render(); eq(count(w, TRICK), 1)
    s.state.won = { { 1, 4 }, { 2, 5 } }; w.ns.TableFrame.render(); eq(count(w, TRICK), 1) -- the other seat's trick
    s.state.won = { { 1, 4, 3, 6 }, { 2, 5 } }; w.ns.TableFrame.render(); eq(count(w, TRICK), 2)
  end)

  local SE -- the Сантасе engine
  local function santase(hand, won, tid)
    local st = SE.new{ first = 1 }
    assert(SE.apply(st, 0, { k = "deal", deck = SE.DECK }))
    local view = SE.view(st, 1)
    view.hand, view.won = hand, won or { {}, {} }
    return { game = "santase", status = "live", mySeat = 1, seats = { ME, BOT }, state = view,
      tid = tid or "t#1", epoch = 1, seq = 1, role = "player", gameOver = function() return false end }
  end

  it("Сантасе: joining mid-hand plays nothing; the next deal sounds", function()
    local w, View, f = viewOf("santase")
    SE = w.ns.Engines.santase
    View.update(f, santase(3, { { 1, 4 }, {} })); eq(#w.sounds, 0)
    View.update(f, santase(3, { { 1, 4 }, {} })); eq(#w.sounds, 0)
    View.update(f, santase(4)); eq(count(w, DEAL), 1); eq(count(w, TRICK), 0)
    View.update(f, santase(4, { { 1, 4 }, {} })); eq(count(w, TRICK), 1)
    View.update(f, santase(9, { { 1, 4 }, {} }, "t#2")); eq(count(w, DEAL), 1); eq(count(w, TRICK), 1) -- another table: first sight
  end)

  it("Белот: one sound per deal, my team's trick once per trick, silent mid-hand", function()
    local w, View, f = viewOf("belot")
    local E = w.ns.Engines.belot
    local function sess(round, phase, took)
      local st = E.new{}
      assert(E.apply(st, 0, { k = "deal", deck = E.DECK }))
      if phase == "play" then
        for _, b in ipairs({ "S", "P", "P", "P" }) do assert(E.apply(st, st.turn, { k = "bid", b = b })) end
      end
      local view = E.view(st, 1)
      view.round, view.phase, view.took = round, phase, took
      return { game = "belot", status = "live", mySeat = 1, seats = { ME, BOT, "В", "Г" }, state = view,
        tid = "t#1", epoch = 1, seq = 1, role = "player" }
    end
    View.update(f, sess(2, "bid")); eq(#w.sounds, 0) -- joined mid-hand
    View.update(f, sess(3, "deal")); eq(#w.sounds, 0) -- the next round waits for its cards
    View.update(f, sess(3, "bid")); eq(count(w, DEAL), 1)
    View.update(f, sess(3, "play", { 0, 0 })); eq(count(w, DEAL), 1); eq(count(w, TRICK), 0)
    View.update(f, sess(3, "play", { 1, 0 })); eq(count(w, TRICK), 1)
    View.update(f, sess(3, "play", { 1, 1 })); eq(count(w, TRICK), 1) -- the other team's
    View.update(f, sess(3, "play", { 2, 1 })); eq(count(w, TRICK), 2)
  end)

  local function holdem(w, hand, pot, cash)
    local E = w.ns.Engines.holdem
    local st = E.new{ seats = { true, true, true } }
    assert(E.apply(st, 0, { k = "hand" })); assert(E.apply(st, 0, { k = "deal", deck = E.DECK }))
    local view = E.view(st, 1)
    view.hand = hand
    for _, i in ipairs(view.order) do view.p[i].total = 0 end
    view.p[view.order[1]].total = pot
    return { game = "holdem", status = "live", mySeat = 1, seats = { ME, BOT, "В", false, false, false }, state = view,
      tid = "t#1", epoch = 1, seq = 1, role = "host", stake = cash and 1000 or nil, engine = function() return E end }
  end

  it("Холдем: a deal sounds per hand; coins sound in the pot of a cash table only", function()
    local w, View, f = viewOf("holdem")
    View.update(f, holdem(w, 1, 30, true)); eq(#w.sounds, 0) -- first sight
    View.update(f, holdem(w, 1, 50, true)); eq(count(w, COIN), 1)
    View.update(f, holdem(w, 1, 50, true)); eq(count(w, COIN), 1)
    View.update(f, holdem(w, 2, 0, true)); eq(count(w, DEAL), 1); eq(count(w, COIN), 1) -- a new hand, the pot empty
    View.update(f, holdem(w, 2, 15, true)); eq(count(w, COIN), 2)
    local w2, View2, f2 = viewOf("holdem")
    View2.update(f2, holdem(w2, 1, 30, false)); View2.update(f2, holdem(w2, 1, 60, false))
    View2.update(f2, holdem(w2, 2, 15, false))
    eq(count(w2, COIN), 0); eq(count(w2, DEAL), 1) -- chips on a fun table: no coins
  end)
end)
