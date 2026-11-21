local _, ns = ...

-- The dealer and its deck across a /reload (core/Deal.lua describes the round).
-- Only the dealer's client can deal the rest of a hand, so a dealer that lost
-- its deck had to give the hand up (void) - and a /reload at a bad moment was
-- a way out of a lost deal. So the dealer keeps its round's secrets where a
-- /reload keeps them, in the saved variables: env.db.fairKeep = {tid, h, seat,
-- me, seed (mine), seeds (seat -> seed), deck}, written once the deck is made
-- (Keep.save, from tryDeal in core/Deal.lua). A client that comes back as the
-- dealer of that very table, hand and seat, under the same name, takes them up
-- again (Keep.restore, from Deal.react) when every seed still matches the
-- commits the host shows; the hand then goes on without a void. The dealer
-- itself did not watch the hand whole and closes it "unseen"; everybody else
-- audits it as usual. A record that does not fit is dropped; so is the
-- round's own when it closes (Keep.clear, from Deal.close: reveal, void,
-- no-reveal) and the table's at a start or an abort. One record at most: a
-- new deal replaces it. The record is read and written here only: it is in no
-- message and no trace line (the trace shows messages, core/Trace.lua).
-- Only a dealer that cannot restore (a crash, another computer) gives the hand
-- up, as before: Keep.giveUp asks the host for the void and asks again every
-- FAIR_ASK_GAP while the hand runs and the deck is gone (a request can be
-- lost; the host ignores one after the void), VOID_ASKS times at most.
local Keep = {}
ns.DealKeep = Keep

local C = ns.Const
local Fair = ns.Fair
local copy = ns.Util.copy

local VOID_ASKS = 12

-- Dealer: my round's secrets, once the deck is made.
function Keep.save(s)
  local fair, env = s.fair, s.client.env
  if not (env.db and fair and fair.deck and fair.seeds and s.mySeat == fair.d) then return end
  env.db.fairKeep = {
    tid = s.tid, h = fair.h, seat = fair.d, me = env.me,
    seed = fair.seed, seeds = copy(fair.seeds), deck = copy(fair.deck),
  }
end

-- Does the record belong to my round as its dealer, with every seed the one
-- committed to?
local function fits(s, rec)
  local fair = s.fair
  if type(rec) ~= "table" or rec.tid ~= s.tid or rec.h ~= fair.h or rec.me ~= s.client.env.me
      or rec.seat ~= fair.d or s.mySeat ~= fair.d or (fair.stage ~= "seed" and fair.stage ~= "dealt")
      or type(rec.seeds) ~= "table" or type(rec.deck) ~= "table" or rec.seed ~= rec.seeds[rec.seat] then
    return false
  end
  for k = 1, #fair.p do
    local seed = rec.seeds[fair.p[k]]
    if type(seed) ~= "string" or Fair.commit(seed) ~= fair.commits[fair.p[k]] then return false end
  end
  return true
end

-- Dealer without the round's secrets (it came back by a snapshot): takes them
-- from the record when it is this round's -> bool. A record that is not is
-- dropped. In a shuffle the deal is then asked for again (tryDeal); in a
-- dealt hand every seat is sent its faces again and I learn my own.
function Keep.restore(s)
  local fair, db = s.fair, s.client.env.db
  local rec = db and db.fairKeep
  if not fair or rec == nil then return false end
  if not fits(s, rec) then
    db.fairKeep = nil
    return false
  end
  fair.seed, fair.seat, fair.own = rec.seed, rec.seat, Fair.commit(rec.seed)
  fair.seeds = copy(rec.seeds)
  if fair.stage == "dealt" then fair.deck, fair.pub, fair.sent = copy(rec.deck), {}, {} end
  return true
end

-- The record of `round` (of my table, whatever the hand, without one) is dropped.
function Keep.clear(s, round)
  local db = s.client.env.db
  local rec = db and db.fairKeep
  if type(rec) == "table" and rec.tid == s.tid and (not round or rec.h == round.h) then db.fairKeep = nil end
end

-- Dealer, my deck is gone and the hand still runs: the host is asked to void
-- it, now and again every FAIR_ASK_GAP while that holds.
function Keep.giveUp(s)
  local fair = s.fair
  if fair.voidAsked then return end
  fair.voidAsked = true
  local chain, left = {}, VOID_ASKS
  fair.voidChain = chain
  local function ask()
    left = left - 1
    ns.Deal.submit(s, { k = "fair", op = "void", h = fair.h })
    if left <= 0 then return end
    s.client:after(C.FAIR_ASK_GAP, function()
      if s.client.session ~= s or s.fair ~= fair or fair.voidChain ~= chain or fair.stage ~= "dealt"
          or fair.deck or ns.Deal.handOver(s) then
        return
      end
      ask()
    end)
  end
  ask()
end

return Keep
