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
  local SE -- the Сантасе engine
  local function santase(hand, won, tid)
    local st = SE.new{ first = 1 }
    assert(SE.apply(st, 0, { k = "deal", deck = SE.DECK }))
    local view = SE.view(st, 1)
    view.hand, view.won = hand, won or { {}, {} }
    return { game = "santase", status = "live", mySeat = 1, seats = { ME, BOT }, state = view,
      tid = tid or "t#1", epoch = 1, seq = 1, role = "player", gameOver = function() return false end }
  end

  it("Сантасе: the view plays no sound of its own (its sounds: ui/games/GameSounds.lua)", function()
    local w, View, f = viewOf("santase")
    SE = w.ns.Engines.santase
    View.update(f, santase(3, { { 1, 4 }, {} })); View.update(f, santase(4))
    View.update(f, santase(4, { { 1, 4 }, {} })); View.update(f, santase(4, { { 1, 4 }, { 2, 5 } }))
    eq(w.sounds, {}); eq(w.soundFiles, {})
  end)

  it("Белот: the view plays no sound of its own", function()
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
    View.update(f, sess(2, "bid")); View.update(f, sess(3, "deal")); View.update(f, sess(3, "bid"))
    View.update(f, sess(3, "play", { 0, 0 })); View.update(f, sess(3, "play", { 1, 0 })); View.update(f, sess(3, "play", { 2, 1 }))
    eq(w.sounds, {}); eq(w.soundFiles, {})
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

  it("Холдем: the view plays no SOUNDKIT deal or coins (its own files: ui/games/HoldemSounds.lua)", function()
    local w, View, f = viewOf("holdem")
    View.update(f, holdem(w, 1, 30, true)); View.update(f, holdem(w, 1, 50, true))
    View.update(f, holdem(w, 2, 0, true)); View.update(f, holdem(w, 2, 15, false))
    eq(count(w, COIN), 0); eq(count(w, DEAL), 0); eq(w.soundFiles, {})
  end)
end)
