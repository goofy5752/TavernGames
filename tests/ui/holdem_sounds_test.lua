local Wow = require("wow")

local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"
local DEAL_KIT = 503 -- the SOUNDKIT deal the Холдем view no longer plays

local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = A .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  w.G.SOUNDKIT.IG_ABILITY_PAGE_TURN = DEAL_KIT
  w:boot(); w:firstRunDone(); w:fire("GUILD_ROSTER_UPDATE"); w:fire("PLAYER_LOGIN")
  return w
end

-- The names of our files played since mark `from` (w.soundFiles: "…\\media\\sounds\\<name>.ogg").
local function heard(w, from)
  local out = {}
  for i = (from or 0) + 1, #w.soundFiles do
    local path, channel = w.soundFiles[i][1], w.soundFiles[i][2]
    eq(channel, "SFX")
    out[#out + 1] = path:match("^Interface\\AddOns\\TavernGames\\media\\sounds\\(.+)%.ogg$") or path
  end
  return out
end

-- A Холдем table of three seats (button 1: seat 2 the small blind, seat 3 the big one, seat 1 first to act
-- preflop), the engine's full state behind it and the session my client holds of it. o: seat (mine; nil: a
-- watcher), role, shown (default true), turn (seconds a turn, default 30).
local function table3(w, o)
  o = o or {}
  local E, HS = w.ns.Engines.holdem, w.ns.HoldemSounds
  HS.reset()
  local t = { st = E.new{ seats = { true, true, true } }, seq = 1, epoch = 1, shown = o.shown ~= false, E = E }
  local seat = o.seat
  if o.watcher then seat = nil elseif seat == nil then seat = 1 end
  local function session()
    local st = t.st
    local s = { game = "holdem", status = "live", mySeat = seat, role = o.role or (seat and "player" or "watcher"),
      seats = { A, B, C, false, false, false }, state = E.view(st, seat or 0), tid = "t#1", epoch = t.epoch, seq = t.seq,
      engine = function() return E end, gameOver = function() return false end }
    if st.phase == "bet" and st.turn then s.deadline = w.ns.client.env.now() + (o.turn or 30) end
    return s
  end
  -- the state as it is now, observed (`again`: the same event once more, a re-render)
  function t.see(again)
    if not again then t.s = session() end
    HS.observe(t.s, t.shown)
    return t
  end
  -- one event: applied to the engine, then observed (`quiet`: not observed, the next see reads it with it)
  function t.apply(seat_, a, quiet)
    local fine, why = E.apply(t.st, seat_, a)
    assert(fine, tostring(a.k) .. " refused: " .. tostring(why))
    t.seq = t.seq + 1
    if not quiet then t.see() end
    return t
  end
  function t.system(quiet) return t.apply(0, (E.system(t.st)), quiet) end
  -- a new hand: its blinds, then its deal, each an event of its own
  function t.deal(quiet) t.apply(0, { k = "hand" }, quiet); return t.apply(0, { k = "deal", deck = E.DECK }, quiet) end
  return t
end

describe("ui: Холдем's sounds", function()
  it("a whole hand: blinds, deal, my turn, every action, each street's board, the win", function()
    local w = guildWow()
    local t = table3(w, { role = "host" }).see() -- before the first hand: first sight, silent
    eq(heard(w), {})
    local n = #w.soundFiles
    t.apply(0, { k = "hand" }); eq(heard(w, n), { "call" }) -- the blinds go in
    n = #w.soundFiles; t.apply(0, { k = "deal", deck = t.E.DECK }); eq(heard(w, n), { "turn", "deal" })
    n = #w.soundFiles; t.apply(1, { k = "raise", to = 30 }); eq(heard(w, n), { "bet" })
    n = #w.soundFiles; t.apply(2, { k = "fold" }); eq(heard(w, n), { "fold" })
    n = #w.soundFiles; t.apply(3, { k = "call" }); eq(heard(w, n), { "call" })
    n = #w.soundFiles; t.system(); eq(heard(w, n), { "board" }) -- the flop; seat 3 acts first
    n = #w.soundFiles; t.apply(3, { k = "check" }); eq(heard(w, n), { "turn", "check" })
    n = #w.soundFiles; t.apply(1, { k = "allin" }); eq(heard(w, n), { "allin" })
    n = #w.soundFiles; t.apply(3, { k = "call" }); eq(heard(w, n), { "allin" }) -- a call of all its chips: all in, the board runs out
    n = #w.soundFiles; t.system(); eq(heard(w, n), { "board" }) -- the turn
    n = #w.soundFiles; t.system(); eq(heard(w, n), { "board" }) -- the river
    n = #w.soundFiles; t.system(); eq(heard(w, n), { "win" }) -- the showdown
    eq(w.sounds, {}) -- no SOUNDKIT deal or coins at Холдем any more
  end)

  it("a fold that leaves one seat: the fold and the win together", function()
    local w = guildWow()
    local t = table3(w, { seat = 2 }).see()
    t.deal(); t.apply(1, { k = "fold" })
    local n = #w.soundFiles
    t.apply(2, { k = "fold" }); eq(heard(w, n), { "win", "fold" })
  end)

  it("silent on the first state seen: joining mid-hand, another table, a snapshot", function()
    local w = guildWow()
    local t = table3(w).deal(true)
    t.apply(1, { k = "call" }, true); t.see() -- I join here, mid-hand
    eq(heard(w), {})
    t.see(true); t.see(true); eq(heard(w), {}) -- a re-render of the same state: nothing again
    t.epoch = 2; t.apply(2, { k = "call" }); eq(heard(w), {}) -- another epoch: a snapshot
    t.apply(3, { k = "check" }, true); t.apply(0, (t.E.system(t.st)), true); t.see() -- my events jumped by two: a snapshot
    eq(heard(w), {})
    local n = #w.soundFiles
    t.apply(2, { k = "check" }); eq(heard(w, n), { "check" }) -- the next event sounds again
  end)

  it("several actions in one update play only the latest one", function()
    local w = guildWow()
    local t = table3(w, { seat = 1, role = "host" }).see()
    t.deal(true); t.apply(1, { k = "call" }); local n = #w.soundFiles
    t.apply(2, { k = "raise", to = 40 }, true); t.apply(3, { k = "fold" }, true); t.see() -- the host's update holds two events
    eq(heard(w, n), { "turn", "fold" })
    n = #w.soundFiles
    t.apply(1, { k = "call" }, true); t.system(true); t.apply(2, { k = "bet", to = 20 }, true); t.see() -- my call, the flop, a bet
    eq(heard(w, n), { "turn", "board" }) -- at most two: my turn first, then the board; the actions drop
  end)

  it("a watcher hears the table, never a turn, a tick or a timeout", function()
    local w = guildWow()
    local t = table3(w, { watcher = true }).see()
    t.deal(); eq(heard(w), { "call", "deal" }) -- the blinds, then the deal
    local n = #w.soundFiles
    t.apply(1, { k = "call" }); eq(heard(w, n), { "call" })
    n = #w.soundFiles; w:advance(40); eq(heard(w, n), {}) -- seat 2's clock is not mine
  end)

  it("with the table window hidden only my turn, my ticks and my timeout play", function()
    local w = guildWow()
    local t = table3(w, { seat = 2, shown = false }).see()
    t.deal(); eq(heard(w), {})
    t.apply(1, { k = "call" }); eq(heard(w), { "turn" })
    w:advance(30.1)
    eq(heard(w), { "turn", "tick", "tick", "tick", "tick", "tick", "tickLast", "tickLast", "tickLast", "tickLast", "tickLast", "timeout" })
    local n = #w.soundFiles
    t.apply(2, { k = "fold" }); eq(heard(w, n), {}) -- the table plays for me: the fold is the table's
  end)

  it("my clock: tick at 10 … 6, tickLast at 5 … 1, each once, then the timeout; nothing twice", function()
    local w = guildWow()
    local t = table3(w, { seat = 1, turn = 30 }).see()
    t.deal(); local n = #w.soundFiles
    w:advance(19.9); eq(heard(w, n), {})
    w:advance(0.2); eq(heard(w, n), { "tick" }) -- 10 seconds left
    w:advance(4.0); eq(heard(w, n), { "tick", "tick", "tick", "tick", "tick" })
    t.see(true); t.see(true) -- re-renders do not play a second
    w:advance(5.0); eq(heard(w, n), { "tick", "tick", "tick", "tick", "tick", "tickLast", "tickLast", "tickLast", "tickLast", "tickLast" })
    w:advance(1.0); eq(heard(w, n)[11], "timeout"); eq(#heard(w, n), 11)
    n = #w.soundFiles
    t.apply(1, { k = "fold" }); eq(heard(w, n), { "fold" }) -- the table played for me: no second timeout
    w:advance(60); eq(heard(w, n), { "fold" })
  end)

  it("the ticks stop as soon as I act; no timeout follows", function()
    local w = guildWow()
    local t = table3(w, { seat = 1 }).see()
    t.deal(); local n = #w.soundFiles
    w:advance(21.5); eq(heard(w, n), { "tick", "tick" })
    w.ns.HoldemSounds.acted(w.ns.HoldemSounds.key(t.s)) -- my button was accepted; the event is on its way
    w:advance(5); eq(heard(w, n), { "tick", "tick" })
    t.apply(1, { k = "call" }); eq(heard(w, n), { "tick", "tick", "call" })
    w:advance(30); eq(#heard(w, n), 3)
  end)

  it("a host that plays my timeout before my clock looks: the timeout plays with the table's move", function()
    local w = guildWow()
    local t = table3(w, { seat = 1, role = "host", turn = 30 }).see()
    t.deal(); local n = #w.soundFiles
    w:advance(29.9995)
    t.apply(1, { k = "fold" }); eq(heard(w, n)[#heard(w, n) - 1], "timeout"); eq(heard(w, n)[#heard(w, n)], "fold")
    local m = #w.soundFiles; w:advance(5); eq(heard(w, m), {})
  end)

  it("muted (the Sounds checkbox off): nothing plays, the clock neither", function()
    local w = guildWow()
    w.ns.db.sound = false
    local t = table3(w, { seat = 2 }).see()
    t.deal(); t.apply(1, { k = "raise", to = 40 }); w:advance(40); t.apply(2, { k = "fold" })
    eq(w.soundFiles, {})
  end)

  it("the view's button stops my clock: an accepted action", function()
    local w = guildWow()
    local t = table3(w, { seat = 1 }).see()
    t.deal()
    local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent); parent:SetSize(732, 440)
    local View = w.ns.TableFrame.views.holdem
    local f = View.build(parent)
    w.ns.client.act = function() return true end
    View.update(f, t.s)
    local n = #w.soundFiles
    w:click(f.foldButton)
    w:advance(40); eq(heard(w, n), {})
  end)
end)

describe("ui: Art.playFile", function()
  it("plays our file by name on the SFX channel; unknown names and a client without it play nothing", function()
    local w = guildWow()
    local Art = w.ns.Art
    eq(Art.playFile("turn"), true)
    eq(w.soundFiles[1], { "Interface\\AddOns\\TavernGames\\media\\sounds\\turn.ogg", "SFX" })
    eq(Art.playFile("nope"), false); eq(#w.soundFiles, 1)
    w.ns.db.sound = false; eq(Art.playFile("turn"), false); w.ns.db.sound = true
    rawset(w.G, "PlaySoundFile", nil); eq(Art.playFile("turn"), false); eq(#w.soundFiles, 1)
  end)

  it("every file it names ships in media/sounds", function()
    local w = guildWow()
    for name in pairs(w.ns.Art.FILES) do
      local f = io.open("media/sounds/" .. name .. ".ogg", "rb")
      ok(f, "missing media/sounds/" .. name .. ".ogg")
      if f then f:close() end
    end
  end)
end)

describe("ui: Холдем's sounds at a real table", function()
  it("a table I host with bots: our files play, the SOUNDKIT deal does not", function()
    local w = guildWow()
    w:slash("bots"); w:advance(0); w:advance(0)
    w.ns.client:openTable{ game = "holdem", access = "invite", turn = 30 }
    w:advance(0)
    w:slash("bots fill 2"); w:advance(6)
    w.ns.TableFrame.startGame()
    for _ = 1, 30 do w:advance(1) end
    local names = {}
    for _, x in ipairs(heard(w)) do names[x] = true end
    ok(names.deal, "no deal: " .. table.concat(heard(w), " "))
    ok(names.call, "no blinds: " .. table.concat(heard(w), " "))
    for _, s in ipairs(w.sounds) do ok(s[1] ~= DEAL_KIT, "the SOUNDKIT deal played") end
  end)
end)
