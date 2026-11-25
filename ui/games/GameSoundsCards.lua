local _, ns = ...

-- The card tables' sounds (ui/games/GameSounds.lua reads them), each step against the last one of the same
-- deal (Белот: st.round, Сантасе: st.hand):
--   Белот   a hand dealt (its first five cards: phase "bid" of a new round) "cards_deal"; any card played
--           "card_play"; a trick taken (by anyone) "trick_take"; a declaration: an announce, a belote, a
--           contra or a recontra "declare"; a played deal's scores (st.res of a new round, not a passed-out
--           deal, not with the match's end jingle) "hand_end"; my turn to bid or play "turn".
--   Сантасе a hand dealt "cards_deal"; a card played "card_play"; a trick taken "trick_take"; a marriage
--           20 / 40 "declare"; the stock closed "stock_close"; the trump nine swapped "nine_swap"; my turn
--           to play "turn".
-- The most telling first: the scores, a deal, a trick taken, a declaration, then the card that came with it.
local GS = ns.GameSounds

local function sum(t) return ((t or {})[1] or 0) + ((t or {})[2] or 0) end

-- The step from `was` to `cur` is within one deal -> true; a new deal appends "cards_deal".
local function sameDeal(cur, was, out)
  if cur.dealt and cur.dealt ~= was.dealt then out[#out + 1] = "cards_deal" end
  return cur.deal == was.deal and not (cur.dealt and cur.dealt ~= was.dealt)
end

GS.games.belot = {
  read = function(st)
    local tricks, calls = sum(st.took), #(st.ann or {})
    for _, b in ipairs(st.bids or {}) do if b.b == "X" or b.b == "R" then calls = calls + 1 end end
    local live = st.phase == "bid" or st.phase == "play" or st.phase == "score"
    return {
      deal = st.round, dealt = live and st.round or nil, tricks = tricks, cards = tricks * 4 + #(st.trick or {}),
      calls = calls, scored = st.res and st.res.contract and st.res.round or nil,
    }
  end,
  sounds = function(cur, was, out, _, ending)
    if cur.scored and cur.scored ~= was.scored and not ending then out[#out + 1] = "hand_end" end
    if not sameDeal(cur, was, out) then return end
    if cur.tricks > was.tricks then out[#out + 1] = "trick_take" end
    if cur.calls > was.calls then out[#out + 1] = "declare" end
    if cur.cards > was.cards then out[#out + 1] = "card_play" end
  end,
  turn = function(s)
    local st = s.state
    if s.role == "watcher" or st.turn ~= s.mySeat or (st.phase ~= "bid" and st.phase ~= "play") then return nil end
    return tostring(st.round) .. ":" .. st.phase .. ":" .. #(st.bids or {}) .. ":" .. (sum(st.took) * 4 + #(st.trick or {}))
  end,
}

GS.games.santase = {
  read = function(st)
    local tricks = sum(st.ntr)
    return {
      deal = st.hand, dealt = st.phase == "play" and st.hand or nil, tricks = tricks, cards = tricks * 2 + #(st.trick or {}),
      mar = sum(st.mar), closed = st.closed ~= nil, trump = st.trumpI,
    }
  end,
  sounds = function(cur, was, out)
    if not sameDeal(cur, was, out) then return end
    if cur.tricks > was.tricks then out[#out + 1] = "trick_take" end
    if cur.mar > was.mar then out[#out + 1] = "declare" end
    if cur.closed and not was.closed then out[#out + 1] = "stock_close" end
    if cur.trump and was.trump and cur.trump ~= was.trump then out[#out + 1] = "nine_swap" end
    if cur.cards > was.cards then out[#out + 1] = "card_play" end
  end,
  turn = function(s)
    local st = s.state
    if s.role == "watcher" or st.turn ~= s.mySeat or st.phase ~= "play" then return nil end
    return tostring(st.hand) .. ":" .. (sum(st.ntr) * 2 + #(st.trick or {}))
  end,
}
