local Wow = require("wow")

local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"

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

local w = guildWow()
local M, E = w.ns.HoldemModel, w.ns.Engines.holdem

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
    seats = { A, B, C, false, false, false }, state = E.view(st, seat or 0) }
end
local function build(st, seat, want) return M.build(sess(st, seat), want) end
local function try(st, seat, a) return E.apply(E.restore(E.snapshot(st)), seat, a) end
-- The street or showdown the full state waits for, else the hand; the deal from E.DECK.
local function system(st)
  local a = E.system(st)
  if a.k == "deal" then a = { k = "deal", deck = E.DECK } end
  ok(E.apply(st, 0, a))
end

-- seeded Park-Miller LCG (exact in doubles), as in tests/engines/holdem_test.lua
local function lcg(seed)
  local x = seed % 2147483646 + 1
  return function(lo, hi)
    x = x * 16807 % 2147483647
    return lo + x % (hi - lo + 1)
  end
end
local function shuffled(rnd)
  local d = {}
  for i, f in ipairs(E.DECK) do d[i] = f end
  for i = #d, 2, -1 do local j = rnd(1, i); d[i], d[j] = d[j], d[i] end
  return d
end

describe("ui: the Холдем model", function()
  it("the table from my seat: stacks, bets, marks, my two cards, what I may do", function()
    local st = hand3(); local m = build(st, 1)
    eq({ m.me, m.seated, m.host, m.mine, m.hand, m.pot, m.board, m.phase, m.inHand }, { 1, true, true, true, 1, 15, {}, "bet", true })
    eq(m.seats[1], { name = A, chips = 1000, st = "in", cards = { "4C", "7C" }, mark = "D", turn = true })
    eq(m.seats[2], { name = B, chips = 995, bet = 5, st = "in", cards = { false, false }, mark = "sb", turn = false })
    eq(m.seats[3], { name = C, chips = 990, bet = 10, st = "in", cards = { false, false }, mark = "bb", turn = false }); eq(m.seats[4], nil)
    eq(m.act, { fold = true, call = 10, raise = { k = "raise", min = 20, max = 1000 }, allin = 1000 }); eq({ m.to, m.half, m.potTo, m.step }, { 20, 22, 35, 10 })
    eq({ build(st, 1, 500).to, build(st, 1, 5000).to, build(st, 1, 3).to, m.text }, { 500, 1000, 20, { "holdem.toCall", 10 } })
    m = build(st, 2); eq({ m.mine, m.act, m.to, m.seats[2].cards, m.seats[1].cards, m.text }, { false, nil, nil, { "2C", "5C" }, { false, false }, { "holdem.waitFor", A } })
    m = build(st, nil); eq({ m.me, m.seated, m.mine, m.seats[1].cards, m.seats[3].cards }, { 1, false, false, { false, false }, { false, false } })
    eq({ m.host, m.closing, m.over, m.note, m.log }, { false, false, false, nil, nil })
  end)

  it("Pot Limit: the biggest raise the buttons offer is the engine's cap; no „Ва банк“ above it", function()
    local st = hand3{ betting = "pl" }; local m = build(st, 1)
    eq(m.act, { fold = true, call = 10, raise = { k = "raise", min = 20, max = 35 } }); eq({ m.to, m.half, m.potTo, build(st, 1, 999).to }, { 20, 22, 35, 35 })
    ok(try(st, 1, { k = "raise", to = m.potTo })); eq({ try(st, 1, { k = "raise", to = m.potTo + 1 }) }, { nil, "amount" }); eq({ try(st, 1, { k = "allin" }) }, { nil, "amount" })
    E.apply(st, 1, { k = "raise", to = 35 }); m = build(st, 2)
    eq(m.act, { fold = true, call = 30, raise = { k = "raise", min = 60, max = 115 } }); eq({ m.half, m.potTo }, { 75, 115 }); ok(try(st, 2, { k = "raise", to = 115 }))
    m = build(hand3(nil, { [1] = 15 }), 1); eq({ m.act, m.to, m.potTo }, { { fold = true, call = 10, allin = 15 }, nil, nil })      -- too short to raise: all-in only
    eq(build(hand3(nil, { [1] = 8 }), 1).act, { fold = true, call = 8 })
  end)

  it("the buttons agree with the engine on random states", function()
    local rnd, hands, raises, states = lcg(20261124), 0, 0, 0
    local function check(cond, msg) if not cond then error(msg, 2) end end
    local t = 0
    while hands < 60 do                                               -- tables of up to 10 hands, No Limit and Pot Limit in turn
      t = t + 1
      local n, seats = rnd(2, 6), {}
      for i = 1, n do seats[i] = true end
      local st = E.new{ seats = seats, first = rnd(1, n), opt = { betting = t % 2 == 1 and "nl" or "pl", blinds = 10 * rnd(1, 2), stack = 50 } }
      local played = 0
      while true do
        local a = E.system(st)
        if not a then break end                                       -- fewer than two seats with chips
        if a.k == "hand" then
          if played == 10 or hands == 60 then break end
          played, hands = played + 1, hands + 1
        end
        if a.k == "deal" then a = { k = "deal", deck = shuffled(rnd) } end
        check(E.apply(st, 0, a), "system " .. a.k)
        while st.phase == "bet" do
          local seat = st.turn
          states = states + 1
          local m, legal = build(st, seat), E.legal(st, seat)
          check(m.mine, "not mine on turn")
          local sized, allin
          for _, la in ipairs(legal) do
            if la.k == "bet" or la.k == "raise" then sized = la end
            if la.k == "allin" then allin = true end
          end
          check((m.act.raise == nil) == (sized == nil), "raise offered " .. tostring(m.act.raise ~= nil))
          check((m.act.allin ~= nil) == (allin == true), "allin offered " .. tostring(m.act.allin))
          if sized then
            raises = raises + 1
            local r = m.act.raise
            check(r.k == sized.k and r.min == sized.to and r.max == sized.max, "raise entry")
            for _, x in ipairs({ m.to, m.half, m.potTo }) do
              check(try(st, seat, { k = r.k, to = x }), r.k .. " to " .. x .. " refused")
            end
            local res, why = try(st, seat, { k = r.k, to = r.max + 1 })
            check(res == nil and why == "amount", "above the max accepted")
          end
          local pick = legal[rnd(1, 10) == 1 and 1 or rnd(2, #legal)]   -- a fold 1 time in 10 or so
          local act = { k = pick.k }
          if pick.max then act.to = rnd(1, 2) == 1 and pick.to or rnd(pick.to, pick.max) end
          check(E.apply(st, seat, act), "random " .. pick.k)
        end
      end
    end
    ok(raises >= 300, "states with a raise " .. raises .. " of " .. states)
  end)

  it("the flop, a bet to face, the showdown and the log", function()
    local st = hand3(); E.apply(st, 1, { k = "call" }); E.apply(st, 2, { k = "call" }); E.apply(st, 3, { k = "check" }); E.apply(st, 0, E.system(st))
    local m = build(st, 2); eq({ m.board, m.pot, m.mine, m.act, m.text }, { { "9C", "TC", "JC" }, 30, true, { fold = true, check = true, raise = { k = "bet", min = 10, max = 990 }, allin = 990 }, { "holdem.yourTurn" } })
    E.apply(st, 2, { k = "bet", to = 20 }); m = build(st, 3)
    eq({ m.act.call, m.act.raise, m.half, m.potTo, m.seats[2].bet, m.pot }, { 20, { k = "raise", min = 40, max = 990 }, 55, 90, 20, 50 })
    E.apply(st, 3, { k = "fold" }); E.apply(st, 1, { k = "call" }); m = build(st, 2)
    eq({ m.seats[3].st, m.seats[3].cards, build(st, 3).seats[3].cards }, { "folded", nil, { "3C", "6C" } })                    -- a folded seat has no cards; I still see my own
    while st.phase ~= "done" do if st.phase == "bet" then E.apply(st, st.turn, { k = "check" }) else E.apply(st, 0, E.system(st)) end end
    m = build(st, 3); eq({ m.board, m.pot, m.inHand, m.seats[1].cards, m.seats[2].cards, m.seats[3].cards }, { { "9C", "TC", "JC", "KC", "2D" }, 0, false, { "4C", "7C" }, { "2C", "5C" }, { "3C", "6C" } })
    eq({ m.seats[1].won, m.seats[1].cat, m.seats[2].won, m.text, m.log }, { 70, 6, nil, { "holdem.won", A, 70, 6 }, { "holdem.log", 1, A, 70, 6 } })
    eq({ m.seats[3].folded, m.seats[1].folded, build(st, 1).seats[3].folded, build(st, nil).seats[3].folded }, { true, nil, nil, nil })    -- my folded hand, mine only
    eq(build(st, nil).seats[3].cards, nil)                                                                                     -- a watcher never saw the folded hand
    eq({ m.seats[1].st, m.seats[1].bet, m.seats[1].turn, m.mine, m.act }, { "ready", nil, false, false, nil })
  end)

  it("an unshown hand lies face down; a newcomer waits for the next hand; away, out, void and the close in words", function()
    local st = hand3(); E.apply(st, 0, { k = "join", seat = 5 }); local s = sess(st, 5); s.seats[5] = "Нади Колева"; local m = M.build(s)
    eq({ m.seats[5].st, m.seats[5].cards, m.seats[5].chips, m.mine, m.text }, { "wait", nil, 1000, false, { "holdem.waitFor", A } })
    E.apply(st, 1, { k = "fold" }); E.apply(st, 2, { k = "fold" }); m = build(st, 1)
    eq({ m.text, m.log, m.seats[3].cards, m.seats[3].won }, { { "holdem.wonFold", C, 10 }, { "holdem.logFold", 1, C, 10 }, { false, false }, 10 })
    -- the winner stands up before the next hand: its name comes from the names at the hand's start
    E.leave(st, 3); s = sess(st, 1); s.seats[3] = false; m = M.build(s)
    eq({ m.seats[3], m.text, m.log }, { nil, { "holdem.wonFold", "?", 10 }, { "holdem.logFold", 1, "?", 10 } })
    s.handNames = { A, B, C, false, false, false }; m = M.build(s)
    eq({ m.text, m.log }, { { "holdem.wonFold", C, 10 }, { "holdem.logFold", 1, C, 10 } })

    -- away: in a hand it is folded but keeps its chair; its own client says so
    st = hand3(); ok(E.apply(st, 0, { k = "away", seat = 2 }))
    eq({ build(st, 1).seats[2].st, build(st, 2).seats[2].st, build(st, 2).text, build(st, 3).text }, { "away", "away", { "holdem.away" }, { "holdem.waitFor", A } })

    -- busted between hands: out
    st = hand3(nil, { [2] = 5 }); E.apply(st, 1, { k = "fold" })
    while st.phase ~= "done" do system(st) end
    m = build(st, 1); eq({ m.seats[2].st, m.seats[2].chips, m.seats[3].st, m.text }, { "out", 0, "ready", { "holdem.won", C, 10, 6 } })

    -- before a hand and with one playing seat: waiting; ready seats, no marks
    m = build(E.new{ seats = { true, true, true } }, 1)
    eq({ m.text, m.seats[1], m.inHand, m.pot, m.log }, { { "holdem.waiting" }, { name = A, chips = 1000, st = "ready", turn = false }, false, 0, nil })
    eq(build(E.new{ seats = { true } }, 1).text, { "holdem.waiting" })

    -- the shuffle
    st = E.new{ seats = { true, true, true } }; ok(E.apply(st, 0, { k = "hand" }))
    m = build(st, 2); eq({ m.phase, m.text, m.mine, m.pot, m.seats[2].st }, { "deal", { "holdem.shuffling" }, false, 15, "in" })

    -- a void
    st = hand3(); ok(E.apply(st, 0, { k = "void" })); m = build(st, 1)
    eq({ m.text, m.log, m.pot, m.seats[1].won, m.seats[3].chips }, { { "holdem.void" }, { "holdem.logVoid", 1 }, 0, nil, 1000 })

    -- the close: the hand is played out, then the table is closed
    st = hand3(); ok(E.apply(st, 0, { k = "close" })); m = build(st, 1)
    eq({ m.closing, m.over, m.note, m.text }, { true, false, { "holdem.closing" }, { "holdem.toCall", 10 } })
    E.apply(st, 1, { k = "fold" }); E.apply(st, 2, { k = "fold" }); m = build(st, 1)
    eq({ m.closing, m.over, m.note, m.text, m.log, m.phase }, { true, true, nil, { "holdem.closed" }, { "holdem.logFold", 1, C, 10 }, "closed" })

    -- two winners of the main pot: the board is a royal flush, everyone plays it
    local deck, board = {}, { [8] = "AS", [9] = "KS", [10] = "QS", [12] = "JS", [14] = "TS" }
    local used = {}
    for _, f in pairs(board) do used[f] = true end
    local r = 1
    for i = 1, 52 do
      if board[i] then deck[i] = board[i]
      else
        while used[E.DECK[r]] do r = r + 1 end
        deck[i], r = E.DECK[r], r + 1
      end
    end
    st = hand3(nil, nil, deck); E.apply(st, 1, { k = "call" }); E.apply(st, 2, { k = "call" }); E.apply(st, 3, { k = "check" })
    while st.phase ~= "done" do if st.phase == "bet" then E.apply(st, st.turn, { k = "check" }) else system(st) end end
    m = build(st, 2); eq({ m.text, m.log, m.seats[1].won, m.seats[2].won, m.seats[3].cat }, { { "holdem.split", 10, 9 }, { "holdem.logSplit", 1, 10, 9 }, 10, 10, 9 })
  end)
end)
