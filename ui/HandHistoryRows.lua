local _, ns = ...

-- What the „История“ window shows of each hand (mockup 10, „Ново“), as plain data the panel
-- (ui/HandHistoryPanel.lua) lays out: H.blocks(s) -> the hands of table s, the newest first, each
--   { hand, title, what (text) | trump (a face) + after (text), sum (the line of a closed hand),
--     open, rows = { … } }
-- and a row one of
--   legend { items = {{ dot = {r, g, b}, text }} }        Белот: who plays with whom
--   trick  { n, slots, cards = {{ face, name, color, won }}, pts, side = "us" | "them" | nil, cur }
--   event  { text, cards = {faces} }                     Сантасе: 20/40, the nine, the close
--   note   { text }  result { text, coin }
--   mine   { text, cards }  street { name, cards, dim = how many are an earlier street's }
--   acts   { list = {{ name, color, text, style = "fold" | "raise" | "allin" | nil }} }
--   show   { name, color, cards, cat, best }
--   side, moves (chess: ui/ChessHistory.lua)
-- Names are Names.short among the hand's seats in the class colour. The points of a trick and the
-- running total come from the cards played and the contract, by the engines' own values (Белот:
-- E.cardValue and the last trick's 10; Сантасе: E.VALUE and the 10 of a stock played out); a
-- finished Белот hand shows the totals the deal scored (hand.score: st.res.raw).
local Theme, W, L, Cards = ns.Theme, ns.W, ns.L, ns.Cards
local H = ns.HandHistory

-- The open state a click left on a hand (its record; for the session), else the newest is open.
H.opened = setmetatable({}, { __mode = "k" })
function H.isOpen(hand, newest)
  local o = H.opened[hand]
  if o == nil then return newest and true or false end
  return o
end
function H.toggle(hand, newest) H.opened[hand] = not H.isOpen(hand, newest) end

-- The seat's short name (Names.short among the hand's seats) and its class colour {r, g, b}.
function H.who(hand, seat)
  local name = seat and hand.names[seat]
  if type(name) ~= "string" then return "?", { Theme.rgb("ink") } end
  return ns.Names.short(name, hand.names), { W.nameColor(ns.client, name) }
end

-- The same, painted in its colour for a sentence.
function H.whoText(hand, seat)
  local name, c = H.who(hand, seat)
  return W.paint(name, c[1], c[2], c[3])
end

local GREEN, RED = { 0x8f / 255, 0xd1 / 255, 0x8a / 255 }, { Theme.rgb("oMark") }
H.SIDE = { us = GREEN, them = RED }

local function seated(s, n)
  local me = s and s.mySeat
  return type(me) == "number" and me >= 1 and me <= n and me or nil
end

local function count(n) return n == 1 and L("table.historyTricks1") or L("table.historyTricks", n) end

-- The tricks and events of a card game hand in order: trick(n, t) for each trick (the one under
-- way too), event(e) before the trick it opens.
local function walk(hand, trick, event)
  local top = 0
  for n in pairs(hand.tricks) do if n > top then top = n end end
  if hand.cur and hand.cur.n > top then top = hand.cur.n end
  for _, e in ipairs(hand.events) do if e.at > top then top = e.at end end
  for n = 1, top do
    for _, e in ipairs(hand.events) do if e.at == n then event(e) end end
    local t = hand.tricks[n] or (hand.cur and hand.cur.n == n and hand.cur)
    if t then trick(n, t, t == hand.cur) end
  end
end

local function trickRow(hand, n, t, cur, slots, pts, side)
  local cards = {}
  for k, c in ipairs(t.cards) do
    local name, color = H.who(hand, c.seat)
    cards[k] = { face = c.face, name = name, color = color, won = not cur and c.seat == t.win }
  end
  return { k = "trick", n = n, slots = slots, cards = cards, pts = not cur and pts or nil, side = not cur and side or nil, cur = cur }
end

---------------------------------------------------------------------------
-- Белот
---------------------------------------------------------------------------

local function team(seat) return 2 - seat % 2 end

-- „Игра: ♠ Пика, контра · каза Petrova“: the suit's icon before a suit contract.
local function contractText(hand)
  local c = hand.contract
  local game = L("belot.bid." .. c.b)
  if Cards.COORD[c.b] then game = ns.HistoryKit.suitTag(c.b) .. " " .. game end
  if c.x == 2 then game = L("belot.x2", game) elseif c.x == 4 then game = L("belot.x4", game) end
  return L("belot.contract", game) .. " · " .. L("belot.by", H.whoText(hand, c.seat))
end

-- The two teams' labels and seats, mine first: „ние“ / „те“, a watcher's „долу и горе“ / „ляво и дясно“.
local function teams(me)
  if me then
    local mine = team(me)
    return { { L("table.historyUs"), mine, me, (me + 1) % 4 + 1, GREEN }, { L("table.historyThem"), 3 - mine, me % 4 + 1, (me + 2) % 4 + 1, RED } }
  end
  return { { L("belot.historyTeamA"), 1, 1, 3, { Theme.rgb("goldHi") } }, { L("belot.historyTeamB"), 2, 2, 4, { Theme.rgb("accent") } } }
end

local function belot(hand, s)
  local me = seated(s, 4)
  local T = teams(me)
  local block = { what = hand.contract and contractText(hand), rows = {} }
  local rows = block.rows
  if hand.names[1] then
    local items = {}
    for k, x in ipairs(T) do
      items[k] = { dot = x[5], text = L("table.historyTeam", x[1], H.whoText(hand, x[3]), H.whoText(hand, x[4])) }
    end
    rows[#rows + 1] = { k = "legend", items = items }
  end
  local sum, tricks = { 0, 0 }, 0
  walk(hand, function(n, t, cur)
    local pts
    if not cur and hand.contract then
      pts = n == 8 and 10 or 0
      for _, c in ipairs(t.cards) do pts = pts + (ns.Engines.belot.cardValue(hand.contract.b, c.face) or 0) end
      -- Без коз: the engine doubles the hand's points (with the last 10; no announces in N), so a
      -- trick counts double and the tricks add up to the final line. Контра / реконтра multiply
      -- only the result, never a trick.
      if hand.contract.b == "N" then pts = pts * 2 end
      sum[team(t.win)] = sum[team(t.win)] + pts
      tricks = tricks + 1
    end
    local side = me and t.win and (team(t.win) == team(me) and "us" or "them")
    rows[#rows + 1] = trickRow(hand, n, t, cur, 4, pts, side)
  end, function() end)
  local a, b = T[1][2], T[2][2]
  local total = hand.score or sum
  local score = L("table.historyScore", T[1][1], total[a], T[2][1], total[b])
  if hand.score then
    block.sum = count(tricks) .. " · " .. score .. (hand.valat and ", " .. L("belot.historyValat") or "")
    rows[#rows + 1] = { k = "result", text = block.sum }
  elseif hand.passed then
    block.sum = L("belot.passed")
    rows[#rows + 1] = { k = "note", text = block.sum }
  elseif tricks > 0 then
    block.sum = L("table.historySoFar", score)
    rows[#rows + 1] = { k = "result", text = block.sum }
  end
  return block
end

---------------------------------------------------------------------------
-- Сантасе
---------------------------------------------------------------------------

local EVENT = { marry = "santase.historyMarry", close = "santase.historyClose", swap = "santase.historySwap" }

local function santase(hand, s)
  local me = seated(s, 2)
  local block = { rows = {} }
  local rows = block.rows
  if hand.trump then
    block.what, block.trump, block.after = L("santase.historyTrump"), hand.trump, Cards.suitName(hand.trump:sub(2, 2))
  elseif hand.tsuit then
    block.what = L("santase.trump", ns.HistoryKit.suitTag(hand.tsuit) .. " " .. Cards.suitName(hand.tsuit))
  end
  local V, tricks = ns.Engines.santase.VALUE, 0
  walk(hand, function(n, t, cur)
    local pts = 0
    for _, c in ipairs(t.cards) do pts = pts + (V[c.face and c.face:sub(1, 1)] or 0) end
    if n == 12 and not hand.shut then pts = pts + 10 end -- the stock played out: the last trick's 10
    if not cur then tricks = tricks + 1 end
    rows[#rows + 1] = trickRow(hand, n, t, cur, 2, pts, me and t.win and (t.win == me and "us" or "them"))
  end, function(e)
    local cards
    if e.k == "marry" and e.suit then cards = { "K" .. e.suit, "Q" .. e.suit } end
    if e.k == "swap" and hand.tsuit then cards = { "9" .. hand.tsuit } end
    rows[#rows + 1] = { k = "event", text = L(EVENT[e.k], H.whoText(hand, e.seat), e.pts), cards = cards or {} }
  end)
  local res = hand.res
  if res then
    local p = res.pts
    if res.winner == 0 then
      block.sum = p and L("santase.historyTie", p[1], p[2]) or L("santase.hand.tie")
    else
      block.sum = p and L("santase.historyWon", H.whoText(hand, res.winner), res.gp, p[res.winner])
        or L("santase.hand.won", H.whoText(hand, res.winner), res.gp)
    end
    rows[#rows + 1] = { k = "result", text = block.sum }
  elseif tricks > 0 then
    block.sum = count(tricks)
  end
  return block
end

---------------------------------------------------------------------------
-- Холдем
---------------------------------------------------------------------------

local STREET = { [0] = "holdem.historyPreflop", "holdem.historyStreet1", "holdem.historyStreet2", "holdem.historyStreet3" }
local BOARD = { [0] = 0, 3, 4, 5 } -- the board's cards after each street
local STYLE = { fold = "fold", bet = "raise", raise = "raise", allin = "allin" }

local function amount(s, x)
  local view = ns.TableFrame.views.holdem
  return view and view.amount(s, x) or tostring(x)
end

local function holdem(hand, s)
  local block = { what = L("holdem.historyBlinds", amount(s, hand.sb or 0), amount(s, hand.bb or 0)), rows = {} }
  local rows = block.rows
  if hand.mine then rows[#rows + 1] = { k = "mine", text = L("holdem.historyMineLabel"), cards = hand.mine } end
  for street = 0, 3 do
    if street == 0 or hand.board[BOARD[street]] then
      local cards = {}
      for k = 1, BOARD[street] do cards[k] = hand.board[k] end
      rows[#rows + 1] = { k = "street", name = L(STREET[street]), cards = cards, dim = street > 0 and BOARD[street - 1] or 0 }
    end
    local list = {}
    for _, a in ipairs(hand.acts) do
      if a.street == street then
        local name, color = H.who(hand, a.seat)
        local text = a.amt and L("holdem.hist." .. a.k, amount(s, a.amt)) or L("holdem.hist." .. a.k)
        list[#list + 1] = { name = name, color = color, text = text, style = STYLE[a.k] }
      end
    end
    if #list > 0 then rows[#rows + 1] = { k = "acts", list = list } end
    for _, x in ipairs(hand.open or {}) do
      if x.at == street then
        local name, color = H.who(hand, x.seat)
        rows[#rows + 1] = { k = "show", name = name, color = color, cards = x.cards, cat = L("holdem.historyTurned") }
      end
    end
  end
  if hand.void then
    block.sum = L("holdem.void")
    rows[#rows + 1] = { k = "note", text = block.sum }
    return block
  end
  local won = {}
  for _, x in ipairs(hand.won or {}) do won[x.seat] = true end
  for _, x in ipairs(hand.shown or {}) do
    local name, color = H.who(hand, x.seat)
    rows[#rows + 1] = { k = "show", name = name, color = color, cards = x.cards, cat = L("holdem.cat." .. tostring(x.cat)), best = won[x.seat] }
  end
  local fold, lines = hand.shown and #hand.shown == 0, {}
  for _, x in ipairs(hand.won or {}) do
    local text = L(fold and "holdem.historyWonFold" or "holdem.historyWon", H.whoText(hand, x.seat), amount(s, x.amt))
    lines[#lines + 1] = text
    rows[#rows + 1] = { k = "result", text = text, coin = true }
  end
  if #lines > 0 then block.sum, block.coin = table.concat(lines, " · "), true end
  return block
end

H.BLOCK.belot, H.BLOCK.santase, H.BLOCK.holdem = belot, santase, holdem

-- The hands of table s for the panel, the newest first (see the top of the file).
function H.blocks(s)
  local out = {}
  local b = s and H.tables[s.tid]
  if not b or not H.BLOCK[b.game] then return out end
  for k = #b.hands, 1, -1 do
    local hand = b.hands[k]
    local block = H.BLOCK[b.game](hand, s)
    block.hand = hand
    block.title = block.title or L(b.game == "chess" and "chess.history.game" or "table.historyHand", hand.no)
    block.newest = k == #b.hands
    block.open = H.isOpen(hand, block.newest)
    out[#out + 1] = block
  end
  return out
end
