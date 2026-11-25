local Wow = require("wow")

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Тодор Ангелов"

local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = A .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
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

-- A table of `game` over engine state `st` and the session my client holds of it, observed by
-- ns.GameSounds as the "session" event would. o: seat (mine, default 1), watcher, role, shown (default
-- true), tid, clock (a timed chess game: my client's clock marks each turn's beginning).
local function driver(w, game, st, o)
  o = o or {}
  local ns = w.ns
  local E, GS = ns.Engines[game], ns.GameSounds
  GS.reset()
  local t = { st = st, seq = 1, epoch = 1, shown = o.shown ~= false, E = E, tid = o.tid or "t#1" }
  local seat = not o.watcher and (o.seat or 1) or nil
  local function session()
    local view = E.view and E.view(t.st, seat or 0) or ns.Util.copy(t.st)
    local s = { game = game, status = "live", mySeat = seat, role = o.role or (seat and "player" or "watcher"),
      seats = { A, B, C, D }, state = view, tid = t.tid, epoch = t.epoch, seq = t.seq, client = ns.client,
      clockAt = t.clockAt }
    function s.engine() return E end
    function s.gameOver()
      if E.over then return E.over(view) and true or false end
      return E.result(view) ~= nil
    end
    return s
  end
  -- the state as it is now, observed (`again`: the same event once more, a re-render)
  function t.see(again)
    if not again then t.s = session() end
    GS.observe(t.s, t.shown)
    return t
  end
  -- one event: applied to the engine, then observed (`quiet`: not observed, the next see reads it with it)
  function t.apply(seat_, a, quiet)
    local fine, why = E.apply(t.st, seat_, a)
    assert(fine, tostring(a.k) .. " refused: " .. tostring(why))
    t.seq = t.seq + 1
    t.clockAt = ns.client.env.now()
    if not quiet then t.see() end
    return t
  end
  -- one event the test makes itself (a leave)
  function t.change(fn, quiet)
    fn(t.st)
    t.seq = t.seq + 1
    if not quiet then t.see() end
    return t
  end
  -- the next sounds of one step: n = mark before it
  function t.step(fn)
    local n = #w.soundFiles
    fn()
    return heard(w, n)
  end
  return t
end

-- `deck` with the faces `at` ({[index] = face}) moved to those indices (the faces they held swapped out).
local function stack(deck, at)
  local out = {}
  for i, f in ipairs(deck) do out[i] = f end
  for i, face in pairs(at) do
    for j, f in ipairs(out) do
      if f == face then out[i], out[j] = out[j], out[i]; break end
    end
  end
  return out
end

local function has(list, x)
  for _, v in ipairs(list) do if v == x then return true end end
  return false
end

describe("ui: Белот's sounds", function()
  -- Seat 1's first five cards (deck 1, 5, 9, 13, 17): 7, 8, 9, Q, K of spades: a tierce and a belote in spades.
  local function belot(w, o)
    local E = w.ns.Engines.belot
    local t = driver(w, "belot", E.new{ first = 1 }, o)
    t.deck = stack(E.DECK, { [1] = "7S", [5] = "8S", [9] = "9S", [13] = "QS", [17] = "KS" })
    return t, E
  end

  it("a whole deal: the deal, my turns, the announce, the belote, cards, tricks, scores", function()
    local w = guildWow()
    local t, E = belot(w, { role = "host" })
    t.see(); eq(heard(w), {}) -- first sight: silent
    eq(t.step(function() t.apply(0, { k = "deal", deck = t.deck }) end), { "turn", "cards_deal" })
    eq(t.step(function() t.apply(1, { k = "bid", b = "S" }) end), {})
    eq(t.step(function() t.apply(2, { k = "bid", b = "P" }) end), {})
    eq(t.step(function() t.apply(3, { k = "bid", b = "P" }) end), {})
    eq(t.step(function() t.apply(4, { k = "bid", b = "P" }) end), { "turn" }) -- the play begins: I lead
    eq(t.step(function() t.apply(1, E.announce(t.st, 1)) end), { "declare" }) -- терца: still my turn
    eq(t.step(function() t.apply(1, { k = "play", i = 17, c = "KS", b = true }) end), { "declare", "card_play" }) -- белот
    local tricks = 0
    while t.st.phase == "play" do -- the others' announces and cards, then the rest of the deal
      local a = E.auto(t.st, t.st.turn)
      local got = t.step(function() t.apply(t.st.turn, a) end)
      if a.k == "ann" then eq(got, { "declare" })
      elseif #t.st.trick == 0 then ok(has(got, "trick_take"), "a trick without its sound"); tricks = tricks + 1
      else eq(got, t.st.turn == 1 and { "turn", "card_play" } or { "card_play" }) end
    end
    eq(tricks, 8)
    eq(t.step(function() t.apply(0, { k = "score" }) end), { "hand_end" })
    eq(t.step(function() t.see(true) end), {}) -- a redraw: nothing again
    eq(t.step(function() t.apply(0, { k = "deal", deck = E.DECK }) end), { "cards_deal" }) -- seat 2 bids first now
    eq(w.sounds, {}) -- no SOUNDKIT sound at all
  end)

  it("contra and recontra are declarations; my next bid is my turn", function()
    local w = guildWow()
    local t = belot(w).see()
    t.apply(0, { k = "deal", deck = t.deck }); t.apply(1, { k = "bid", b = "S" })
    eq(t.step(function() t.apply(2, { k = "bid", b = "X" }) end), { "declare" }) -- контра
    eq(t.step(function() t.apply(3, { k = "bid", b = "R" }) end), { "declare" }) -- реконтра
    eq(t.step(function() t.apply(4, { k = "bid", b = "P" }) end), { "turn" })
  end)

  it("a passed-out deal has no scores' sound; the next deal sounds", function()
    local w = guildWow()
    local t = belot(w).see()
    t.apply(0, { k = "deal", deck = t.deck })
    for _, seat in ipairs({ 1, 2, 3 }) do t.apply(seat, { k = "bid", b = "P" }) end
    eq(t.step(function() t.apply(4, { k = "bid", b = "P" }) end), {})
    eq(t.step(function() t.apply(0, { k = "deal", deck = t.deck }) end), { "cards_deal" })
  end)

  it("the match's end: the jingle of my side once, and no scores' sound beside it; a watcher hears the scores", function()
    for _, o in ipairs({ { seat = 1 }, { seat = 2 }, { watcher = true } }) do
      local w = guildWow()
      local t, E = belot(w, o)
      t.see(); t.apply(0, { k = "deal", deck = t.deck })
      t.apply(1, { k = "bid", b = "S" }); for _, seat in ipairs({ 2, 3, 4 }) do t.apply(seat, { k = "bid", b = "P" }) end
      while t.st.phase == "play" do t.apply(t.st.turn, E.auto(t.st, t.st.turn)) end
      local peek = w.ns.Util.copy(t.st); assert(E.apply(peek, 0, { k = "score" }))
      local team = peek.res.pts[1] > 0 and 1 or 2 -- the team that scores this deal wins the match with it
      t.st.score = team == 1 and { 151, 0 } or { 0, 151 }
      local got = t.step(function() t.apply(0, { k = "score" }) end)
      eq(t.st.phase, "match")
      if o.watcher then eq(got, { "hand_end" })
      else eq(got, { (o.seat % 2 == 1) == (team == 1) and "game_win" or "game_lose" }) end
      eq(t.step(function() t.see(true) end), {})
    end
  end)

  it("a leave ends the match: my partner's leave loses it for me, an opponent's wins it", function()
    local w = guildWow()
    local t, E = belot(w, { seat = 1 })
    t.see(); t.apply(0, { k = "deal", deck = t.deck })
    eq(t.step(function() t.change(function(st) E.leave(st, 3) end) end), { "game_lose" })
    eq(t.step(function() t.see(true) end), {}) -- once
    t, E = belot(w, { seat = 1 })
    t.see(); t.apply(0, { k = "deal", deck = t.deck })
    eq(t.step(function() t.change(function(st) E.leave(st, 2) end) end), { "game_win" })
  end)
end)

describe("ui: Сантасе's sounds", function()
  -- Seat 1 (the non-dealer, leading) holds AC 9S KH (deck 1..3) and QH JC 9C (7..9); seat 2 only diamonds;
  -- the trump card AS (13): spades. Then QC to seat 1, KC to seat 2, TC, 9H ...
  local function santase(w, o)
    local E = w.ns.Engines.santase
    local t = driver(w, "santase", E.new{ first = 1 }, o)
    t.deck = stack(E.DECK, { [1] = "AC", [2] = "9S", [3] = "KH", [4] = "9D", [5] = "JD", [6] = "QD", [7] = "QH",
      [8] = "JC", [9] = "9C", [10] = "KD", [11] = "TD", [12] = "AD", [13] = "AS", [14] = "QC", [15] = "KC" })
    return t, E
  end

  it("a hand: the deal, my turn, cards, tricks, the nine swapped, a marriage, the stock closed", function()
    local w = guildWow()
    local t, E = santase(w, { role = "host" })
    t.see(); eq(heard(w), {})
    eq(t.step(function() t.apply(0, { k = "deal", deck = t.deck }) end), { "turn", "cards_deal" })
    eq(t.step(function() t.apply(1, { k = "play", i = 1, c = "AC" }) end), { "card_play" })
    eq(t.step(function() t.apply(2, E.auto(t.st, 2)) end), { "turn", "trick_take" }) -- my trick: I lead again
    eq(t.step(function() t.apply(1, { k = "swap9", i = 2, c = "9S" }) end), { "nine_swap" })
    eq(t.step(function() t.apply(1, { k = "marry", i = 3, c = "KH", j = 7, d = "QH" }) end), { "declare", "card_play" })
    eq(t.step(function() t.apply(2, E.auto(t.st, 2)) end), { "turn", "trick_take" })
    eq(t.step(function() t.apply(1, { k = "close" }) end), { "stock_close" })
    eq(t.step(function() t.see(true) end), {})
    eq(t.step(function() t.apply(1, E.auto(t.st, 1)) end), { "card_play" })
    eq(w.sounds, {})
  end)

  it("the match's end: win, lose, nothing for a watcher; a new hand after a void sounds its deal", function()
    for _, o in ipairs({ { seat = 1, want = "game_win" }, { seat = 2, want = "game_lose" }, { watcher = true } }) do
      local w = guildWow()
      local t, E = santase(w, o)
      t.see(); t.apply(0, { k = "deal", deck = t.deck })
      eq(t.step(function() t.apply(0, { k = "void" }) end), {})
      eq(has(t.step(function() t.apply(0, { k = "deal", deck = t.deck }) end), "cards_deal"), true)
      eq(t.step(function() t.change(function(st) E.leave(st, 2) end) end), o.want and { o.want } or {})
    end
  end)
end)

describe("ui: Табла's sounds", function()
  -- A game in progress, seat 1 to roll: its checkers on its own points `mine`, seat 2's on `theirs`.
  local function tabla(w, mine, theirs, o)
    local E = w.ns.Engines.tabla
    local st = E.new{}
    for q = 1, 24 do st.pts[1][q], st.pts[2][q] = mine[q] or 0, theirs[q] or 0 end
    st.phase, st.turn = "roll", 1
    return driver(w, "tabla", st, o), E
  end

  it("the opening roll, a roll, a move, a hit, a checker borne off", function()
    local w = guildWow()
    local E = w.ns.Engines.tabla
    local t = driver(w, "tabla", E.new{}, { role = "host" }).see()
    eq(t.step(function() t.apply(0, { k = "dice", d = { 4, 4 } }) end), { "dice_roll" }) -- a tie: again
    eq(t.step(function() t.apply(0, { k = "dice", d = { 3, 5 } }) end), { "dice_roll" }) -- seat 2 starts
    eq(t.step(function() t.apply(0, { k = "dice", d = { 6, 1 } }) end), { "dice_roll" })
    eq(t.step(function() t.apply(2, E.auto(t.st, 2)) end), { "checker_move" })
    eq(t.step(function() t.see(true) end), {})
    -- seat 2 alone on seat 1's point 3 (its own 22): 6/3 hits it
    t = tabla(w, { [6] = 15 }, { [22] = 1, [1] = 14 }).see()
    eq(t.step(function() t.apply(0, { k = "dice", d = { 3, 1 } }) end), { "dice_roll" })
    eq(t.step(function() t.apply(1, { k = "move", steps = { { 6, 3 }, { 6, 5 } } }) end), { "checker_hit" })
    -- every checker at home: 6/off 5/off
    t = tabla(w, { [6] = 10, [5] = 5 }, { [1] = 15 }).see()
    t.apply(0, { k = "dice", d = { 6, 5 } })
    eq(t.step(function() t.apply(1, { k = "move", steps = { { 6, 0 }, { 5, 0 } } }) end), { "checker_off" })
    eq(w.sounds, {})
  end)

  it("a roll and its move in one update play both, the move first; the match's end plays the jingle", function()
    local w = guildWow()
    local t, E = tabla(w, { [6] = 15 }, { [1] = 15 }, { role = "host" })
    t.see()
    eq(t.step(function() t.apply(0, { k = "dice", d = { 2, 1 } }, true); t.apply(1, E.auto(t.st, 1), true); t.see() end),
      { "checker_move", "dice_roll" })
    eq(t.step(function() t.change(function(st) E.leave(st, 2) end) end), { "game_win" })
  end)
end)

describe("ui: chess sounds", function()
  local function chess(w, o, fen)
    local ns = w.ns
    local E, R = ns.Engines.chess, ns.ChessRules
    local st = E.new{ first = 1, opt = { clock = (o or {}).minutes or 0 } }
    if fen then
      local pos = assert(R.fromFen(fen))
      st.board, st.side, st.castle, st.ep, st.half, st.full = pos.board, pos.side, pos.castle, pos.ep, pos.half, pos.full
      st.turn = pos.side == 1 and st.white or 3 - st.white
      st.seen = { [R.key(st)] = 1 }
    end
    return driver(w, "chess", st, o), E
  end
  local function sq(name) return (tonumber(name:sub(2, 2)) - 1) * 8 + ("abcdefgh"):find(name:sub(1, 1), 1, true) end
  local function move(t, word)
    local p = word:sub(5, 5)
    return t.apply(t.st.turn, { k = "move", f = sq(word:sub(1, 2)), t = sq(word:sub(3, 4)), p = p ~= "" and p or nil })
  end

  it("a move, a capture, check, castling, a promotion: one sound each", function()
    local w = guildWow()
    local t = chess(w).see()
    eq(t.step(function() move(t, "e2e4") end), { "chess_move" })
    eq(t.step(function() t.see(true) end), {})
    eq(t.step(function() move(t, "d7d5") end), { "chess_move" })
    eq(t.step(function() move(t, "e4d5") end), { "chess_capture" })
    eq(t.step(function() move(t, "d8d5") end), { "chess_capture" })
    eq(t.step(function() move(t, "b1c3") end), { "chess_move" })
    eq(t.step(function() move(t, "d5e5") end), { "chess_check" })
    t = chess(w, nil, "r3k3/6P1/8/8/8/8/8/R3K2R w KQq - 0 1").see()
    eq(t.step(function() move(t, "e1g1") end), { "chess_castle" })
    eq(t.step(function() move(t, "e8c8") end), { "chess_castle" }) -- O-O-O
    eq(t.step(function() move(t, "g7g8q") end), { "chess_promote" })
    t = chess(w, nil, "4k3/6P1/8/8/8/8/8/4K3 w - - 0 1").see()
    eq(t.step(function() move(t, "g7g8q") end), { "chess_promote" }) -- g8=Q+: the promotion before the check
    eq(w.sounds, {})
  end)

  it("a mate is the game's end: the loser's and the winner's jingle, the watcher's move; a draw", function()
    for _, o in ipairs({ { seat = 1, want = { "game_lose", "chess_move" } }, { seat = 2, want = { "game_win", "chess_move" } },
        { watcher = true, want = { "chess_move" } } }) do
      local w = guildWow()
      local t = chess(w, o).see()
      for _, word in ipairs({ "f2f3", "e7e5", "g2g4" }) do move(t, word) end
      eq(t.step(function() move(t, "d8h4") end), o.want) -- Qh4#: no check sound
      eq(t.step(function() t.see(true) end), {})
    end
    local w = guildWow()
    local t = chess(w).see()
    move(t, "e2e4"); move(t, "e7e5")
    t.apply(1, { k = "offer" })
    eq(t.step(function() t.apply(2, { k = "accept" }) end), { "game_draw" })
  end)

  it("my clock: a tick a second in my last ten, also hidden; none for a watcher, none muted", function()
    local w = guildWow()
    local t = chess(w, { seat = 2, minutes = 1, shown = false }).see()
    eq(t.step(function() move(t, "e2e4") end), {}) -- my turn, a minute on my clock
    eq(t.step(function() w:advance(49.9) end), {})
    eq(t.step(function() w:advance(0.2) end), { "tick" }) -- 10 s left
    eq(t.step(function() t.see(true) end), {}) -- a redraw ticks nothing again
    eq(t.step(function() w:advance(9) end), { "tick", "tick", "tick", "tick", "tick", "tick", "tick", "tick", "tick" })
    eq(t.step(function() w:advance(5) end), {}) -- time is up: the flag is the table's
    -- my move stops the ticks
    t = chess(w, { seat = 2, minutes = 1 }).see()
    move(t, "e2e4")
    eq(#t.step(function() w:advance(53) end), 3)
    eq(t.step(function() move(t, "e7e5") end), { "chess_move" })
    eq(t.step(function() w:advance(30) end), {})
    -- a watcher, the mute
    t = chess(w, { watcher = true, minutes = 1 }).see()
    move(t, "e2e4")
    eq(t.step(function() w:advance(61) end), {})
    t = chess(w, { seat = 2, minutes = 1 }).see()
    move(t, "e2e4")
    w.ns.db.sound = false
    eq(t.step(function() w:advance(61) end), {})
  end)
end)

describe("ui: Морски шах's and Death Roll's sounds", function()
  it("Морски шах: X and O placed, the winning line, the match's end", function()
    local w = guildWow()
    local E = w.ns.Engines.ttt
    local t = driver(w, "ttt", E.new{ first = 1 }, { seat = 2 }).see()
    eq(t.step(function() t.apply(1, { k = "mark", c = 1 }) end), { "ttt_x" })
    eq(t.step(function() t.apply(2, { k = "mark", c = 4 }) end), { "ttt_o" })
    t.apply(1, { k = "mark", c = 2 }); t.apply(2, { k = "mark", c = 5 })
    eq(t.step(function() t.apply(1, { k = "mark", c = 3 }) end), { "ttt_line", "ttt_x" })
    eq(t.step(function() t.apply(0, { k = "next" }) end), {}) -- a fresh board
    t.st.score = { 0, 2 }
    t.apply(2, { k = "mark", c = 1 }); t.apply(1, { k = "mark", c = 4 }); t.apply(2, { k = "mark", c = 2 })
    t.apply(1, { k = "mark", c = 5 })
    eq(t.step(function() t.apply(2, { k = "mark", c = 3 }) end), { "game_win", "ttt_line" }) -- 3 rounds: my match
    eq(t.step(function() t.see(true) end), {})
    eq(w.sounds, {})
  end)

  it("Death Roll: every roll, the 1 that loses, the jingle of the loser and of the others", function()
    for _, o in ipairs({ { seat = 3, want = "game_lose" }, { seat = 1, want = "game_win" }, { watcher = true } }) do
      local w = guildWow()
      local E = w.ns.Engines.deathroll
      local t = driver(w, "deathroll", E.new{ seats = { true, true, true }, first = 1, opt = { start = 100 } }, o).see()
      local function roll(n) return t.apply(t.st.turn, { k = "roll", max = t.st.max, n = n, src = "seen" }) end
      eq(t.step(function() roll(40) end), { "die_roll" })
      eq(t.step(function() roll(7) end), { "die_roll" })
      eq(t.step(function() roll(1) end), o.want and { o.want, "roll_one" } or { "roll_one" })
      eq(t.step(function() t.see(true) end), {})
    end
  end)

  it("Death Roll: the loss paid at my table plays the coins in place of the toast's", function()
    local w = guildWow()
    local GS, client = w.ns.GameSounds, w.ns.client
    w.ns.TableFrame.build(); w.ns.TableFrame.frame:Show()
    local me = client.ledger.me
    client.session = { game = "deathroll", seats = { me, B, false } }
    eq(GS.settled(client, { from = B, to = me }), true); eq(heard(w), { "coins_pay" })
    eq(GS.settled(client, { from = C, to = me }), false) -- not of my table
    client.session.game = "ttt"; eq(GS.settled(client, { from = B, to = me }), false)
    client.session.game = "deathroll"; w.ns.TableFrame.frame:Hide(); eq(GS.settled(client, { from = me, to = B }), false)
    client.session = nil
    eq(heard(w), { "coins_pay" })
  end)
end)

describe("ui: the games' sounds, every game", function()
  it("silent on joining and on a snapshot: another epoch, another role, a member's events jumped", function()
    local w = guildWow()
    local E = w.ns.Engines.ttt
    local t = driver(w, "ttt", E.new{ first = 1 }, { seat = 2 })
    t.apply(1, { k = "mark", c = 1 }, true); t.see() -- I join here
    eq(heard(w), {})
    t.epoch = 2; t.apply(2, { k = "mark", c = 5 }); eq(heard(w), {}) -- another epoch: a snapshot
    t.apply(1, { k = "mark", c = 2 }, true); t.apply(2, { k = "mark", c = 6 }, true); t.see() -- jumped by two
    eq(heard(w), {})
    eq(t.step(function() t.apply(1, { k = "mark", c = 9 }) end), { "ttt_x" }) -- the next event sounds again
    t = driver(w, "ttt", E.new{ first = 1 }, { seat = 2, tid = "t#2" }) -- another table: its first sight
    t.apply(1, { k = "mark", c = 1 }, true); eq(t.step(function() t.see() end), {})
  end)

  it("several events in one update play at most two, the latest first", function()
    local w = guildWow()
    local E = w.ns.Engines.belot
    local t = driver(w, "belot", E.new{ first = 2 }, { seat = 1, role = "host" }).see()
    t.apply(0, { k = "deal", deck = E.DECK }, true)
    t.apply(2, { k = "bid", b = "S" }, true); t.apply(3, { k = "bid", b = "X" }, true)
    eq(t.step(function() t.see() end), { "cards_deal" }) -- the deal, the contra: one deal sound (the contra is of it)
    t.apply(4, { k = "bid", b = "R" }, true); t.apply(1, { k = "bid", b = "P" }, true); t.apply(2, { k = "bid", b = "P" }, true)
    t.apply(3, { k = "bid", b = "P" }, true)
    repeat t.apply(t.st.turn, E.auto(t.st, t.st.turn), true) until t.st.trickNo == 2
    local got = t.step(function() t.see() end) -- a recontra, announces, a trick of four cards
    eq(#got, 2); eq(got[1] == "turn" and got[2] or got[1], "trick_take")
  end)

  it("the table's sounds only while its window shows; muted, nothing", function()
    local w = guildWow()
    local E = w.ns.Engines.santase
    local t = driver(w, "santase", E.new{ first = 1 }, { seat = 2, shown = false }).see()
    eq(t.step(function() t.apply(0, { k = "deal", deck = E.DECK }) end), {}) -- seat 1 leads
    eq(t.step(function() t.apply(1, E.auto(t.st, 1)) end), { "turn" }) -- my turn, also hidden
    eq(t.step(function() t.change(function(st) E.leave(st, 1) end) end), {}) -- the match's end: a table sound
    local w2 = guildWow()
    w2.ns.db.sound = false
    t = driver(w2, "santase", E.new{ first = 1 }, { seat = 1 }).see()
    t.apply(0, { k = "deal", deck = E.DECK }); t.apply(1, E.auto(t.st, 1)); t.change(function(st) E.leave(st, 2) end)
    eq(w2.soundFiles, {})
  end)

  it("a real table I host: the session event feeds the sounds, and Art.playFile knows every file", function()
    local w = guildWow()
    w:slash("bots"); w:advance(0); w:advance(0)
    w.ns.client:openTable{ game = "santase", access = "invite", turn = 45 }
    w:advance(0)
    local v = w.ns.TableFrame.view
    w:click(v.inviteButton)
    for _, r in ipairs(v.picker.rows) do
      if r.frame:IsVisible() and r.peerName == "Bot Ivanov" then w:click(r.frame) end
    end
    w:advance(2)
    eq(w.ns.client.session.state.hand, 1)
    ok(has(heard(w), "cards_deal"), "the first deal is heard")
    eq(w.ns.GameSounds.lastError, nil)
    for name in pairs(w.ns.Art.FILES) do
      local f = io.open("media/sounds/" .. name .. ".ogg", "rb")
      ok(f, "missing media/sounds/" .. name .. ".ogg")
      if f then ok(f:read(4) == "OggS", name .. ".ogg is not an Ogg file"); f:close() end
    end
  end)
end)
