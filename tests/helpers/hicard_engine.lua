-- Test-only card engine "hicard": 2-3 seats, started by the host, extension
-- "fair", a 12-card deck, first to GOAL tricks wins the match.
--   Deal {k="deal", deck} at seat 0 (phase "deal"/"hand"): with n players, in
--   player order starting after the dealer, deck[1..n] one card each, then
--   deck[n+1..2n]; up = 2n+1 (face up); stock = 2n+2 .. 12. The player after
--   the dealer leads. A view accepts no deck or any subset; the full state only
--   a permutation of DECK ("deck").
--   Play {k="play", i, c} by the seat on turn: i in its hand, c its face (a
--   known face must match, an unknown one must not repeat another: "card").
--   Rule H: when every face of that hand is known and it holds a card of the up
--   card's suit, c must be of that suit ("move").
--   A full trick goes to the highest rank (9 < T < J < Q < K < A; ties: the
--   earlier card), +1 point. After trick 1 everybody draws one card from the
--   stock, the winner first, then the others in player order after him. The
--   winner leads. GOAL points end the match; after trick 3 the hand ends and
--   the next player deals.
--   {k="show", cards} fills faces on a view; {k="void"} annuls a hand in play.
--   A view shows the seat's own hand, the trick, the last trick and the up card
--   (everything once the match is over).
local Sim = require("sim")
local copy = Sim.ns.Util.copy

local E = {
  id = "hicard", minSeats = 2, maxSeats = 3, start = "host", ext = { "fair" }, GOAL = 4,
  DECK = { "9C", "TC", "JC", "QC", "KC", "AC", "9D", "TD", "JD", "QD", "KD", "AD" },
}
local N = #E.DECK
local RANK = { ["9"] = 1, T = 2, J = 3, Q = 4, K = 5, A = 6 }
local ISFACE = {}
for _, f in ipairs(E.DECK) do ISFACE[f] = true end

local function suit(f) return f:sub(2, 2) end
local function isIndex(i) return type(i) == "number" and i >= 1 and i <= N and i % 1 == 0 end

local function posOf(list, x)
  for p = 1, #list do
    if list[p] == x then return p end
  end
end

-- The player after `seat` in `players`, cyclic.
local function nextOf(players, seat)
  local p = posOf(players, seat)
  return p and players[p % #players + 1]
end

-- May index i carry face c here? Known faces must match; an unknown one must not repeat another.
local function faceOk(s, i, c)
  if type(c) ~= "string" or not ISFACE[c] then return false end
  if s.deck[i] ~= nil then return s.deck[i] == c end
  for j = 1, N do
    if s.deck[j] == c then return false end
  end
  return true
end

-- Rule H for `hand` -> the suit every play must have, or nil (no duty or not checkable).
local function duty(s, hand)
  local up = s.up and s.deck[s.up]
  if not up then return nil end
  local has = false
  for _, i in ipairs(hand) do
    local f = s.deck[i]
    if not f then return nil end
    if suit(f) == suit(up) then has = true end
  end
  return has and suit(up) or nil
end

function E.new(opts)
  local players, pts, hands = {}, {}, {}
  for i = 1, #opts.seats do
    if opts.seats[i] then players[#players + 1] = i end
    pts[i], hands[i] = 0, {}
  end
  local first = posOf(players, opts.first) or 1
  return {
    full = true, phase = "deal", players = players, dealer = players[(first - 2) % #players + 1],
    turn = nil, deck = {}, hands = hands, up = nil, stock = {}, trick = {}, last = {},
    tricks = 0, pts = pts, pts0 = copy(pts), hand = 0, winner = nil,
  }
end

local function deal(s, a)
  local d = a.deck
  if d == nil and not s.full then d = {} end
  if type(d) ~= "table" then return nil, "deck" end
  for k in pairs(d) do
    if not isIndex(k) then return nil, "deck" end
  end
  local seen = {}
  for i = 1, N do
    local f = d[i]
    if f ~= nil then
      if type(f) ~= "string" or not ISFACE[f] or seen[f] then return nil, "deck" end
      seen[f] = true
    elseif s.full then
      return nil, "deck"
    end
  end
  local n, order, seat = #s.players, {}, s.dealer
  for p = 1, n do seat = nextOf(s.players, seat); order[p] = seat end
  s.deck = {}
  for i = 1, N do s.deck[i] = d[i] end
  for i = 1, #s.hands do s.hands[i] = {} end
  for p = 1, n do
    s.hands[order[p]] = { p, n + p }
  end
  s.up, s.stock = 2 * n + 1, {}
  for i = 2 * n + 2, N do s.stock[#s.stock + 1] = i end
  s.trick, s.last = {}, {}
  s.turn, s.phase, s.hand, s.tricks = order[1], "play", s.hand + 1, 0
  s.pts0 = copy(s.pts)
  return true
end

local function resolveTrick(s)
  local best = s.trick[1]
  for p = 2, #s.trick do
    local t = s.trick[p]
    if RANK[s.deck[t[2]]:sub(1, 1)] > RANK[s.deck[best[2]]:sub(1, 1)] then best = t end
  end
  local w = best[1]
  s.pts[w] = s.pts[w] + 1
  s.last = {}
  for p = 1, #s.trick do s.last[p] = s.trick[p][2] end
  s.trick, s.tricks, s.turn = {}, s.tricks + 1, w
  if s.pts[w] == E.GOAL then
    s.phase, s.winner, s.turn = "match", w, nil
  elseif s.tricks == 1 then
    local seat = w
    for _ = 1, #s.players do
      local hand = s.hands[seat]
      hand[#hand + 1] = table.remove(s.stock, 1)
      seat = nextOf(s.players, seat)
    end
  elseif s.tricks == 3 then
    s.phase, s.turn, s.dealer = "hand", nil, nextOf(s.players, s.dealer)
  end
end

local function play(s, seat, a)
  local hand = s.hands[seat]
  local p = posOf(hand, a.i)
  if not p or not faceOk(s, a.i, a.c) then return nil, "card" end
  local must = duty(s, hand)
  if must and suit(a.c) ~= must then return nil, "move" end
  s.deck[a.i] = a.c
  table.remove(hand, p)
  s.trick[#s.trick + 1] = { seat, a.i }
  if #s.trick == #s.players then
    resolveTrick(s)
  else
    s.turn = nextOf(s.players, seat)
  end
  return true
end

local function show(s, a)
  if s.phase == "deal" then return nil, "phase" end
  if type(a.cards) ~= "table" then return nil, "card" end
  local seen = {}
  for i, f in pairs(a.cards) do
    if not isIndex(i) or seen[f] or not faceOk(s, i, f) then return nil, "card" end
    seen[f] = true
  end
  for i, f in pairs(a.cards) do s.deck[i] = f end
  return true
end

local function void(s)
  if s.phase ~= "play" then return nil, "phase" end
  for i = 1, #s.hands do s.hands[i] = {} end
  s.stock, s.trick, s.last, s.deck = {}, {}, {}, {}
  s.up, s.turn = nil, nil
  s.pts, s.phase, s.hand = copy(s.pts0), "deal", s.hand - 1
  return true
end

function E.apply(s, seat, a)
  if type(a) ~= "table" then return nil, "action" end
  if a.need ~= nil then return nil, "need" end
  local k = a.k
  if k == "deal" or k == "show" or k == "void" then
    if seat ~= 0 then return nil, "seat" end
    if k == "show" then return show(s, a) end
    if k == "void" then return void(s) end
    if s.phase ~= "deal" and s.phase ~= "hand" then return nil, "phase" end
    return deal(s, a)
  elseif k == "play" then
    if seat == 0 then return nil, "seat" end
    if s.phase ~= "play" then return nil, "phase" end
    if s.turn ~= seat then return nil, "turn" end
    return play(s, seat, a)
  end
  return nil, "action"
end

function E.legal(s, seat)
  local out = {}
  if s.phase ~= "play" or s.turn ~= seat then return out end
  local hand = s.hands[seat]
  local must = duty(s, hand)
  for _, i in ipairs(hand) do
    local f = s.deck[i]
    if f and (not must or suit(f) == must) then out[#out + 1] = { k = "play", i = i, c = f } end
  end
  return out
end

function E.auto(s, seat) return E.legal(s, seat)[1] end

function E.system(s)
  if s.phase == "deal" then return { k = "deal", need = "deck" }, 0 end
  if s.phase == "hand" then return { k = "deal", need = "deck" }, 1 end
end

function E.view(s, seat)
  local v = copy(s)
  v.full = false
  if s.phase == "match" then return v end
  local vis = {}
  for _, i in ipairs(s.hands[seat] or {}) do vis[i] = true end
  for _, t in ipairs(s.trick) do vis[t[2]] = true end
  for _, i in ipairs(s.last) do vis[i] = true end
  if s.up then vis[s.up] = true end
  v.deck = {}
  for i in pairs(vis) do v.deck[i] = s.deck[i] end
  return v
end

function E.hidden(s, seat) return copy(s.hands[seat] or {}) end

-- At a trick boundary: the seat's hand is dropped; one player left wins.
function E.leave(s, seat)
  if s.phase == "match" or not posOf(s.players, seat) then return end
  local after = nextOf(s.players, seat)
  table.remove(s.players, posOf(s.players, seat))
  s.hands[seat] = {}
  if #s.players < 2 then
    s.phase, s.winner, s.turn = "match", s.players[1], nil
    return
  end
  if s.dealer == seat then s.dealer = after end
  if s.turn == seat then s.turn = after end
end

function E.result(s)
  if s.phase ~= "match" then return nil end
  local losers = {}
  for _, p in ipairs(s.players) do
    if p ~= s.winner then losers[#losers + 1] = p end
  end
  return { winners = { s.winner }, losers = losers }
end

function E.over(s) return s.phase == "match" end

E.snapshot, E.restore = copy, copy

Sim.ns.Engines.hicard = E
return E
