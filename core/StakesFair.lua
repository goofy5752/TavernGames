local _, ns = ...

-- What the fairness layer of a staked game (the "fair" verdicts of
-- core/Deal.lua, the dice counts of core/Dice.lua) means for my debt. A game
-- whose engine has that layer (`fair` or `dice` in engine.ext) is "judged":
-- the extension judges what a snapshot did to the hand or the throw, and for
-- `stakes` a snapshot from a host new to me that is not my state is the same
-- match, "unseen" (core/StakesWatch.lua's `adopted`: Stakes.leadsTo cannot
-- read these states); one my own host pushed on me unasked that changes my
-- state is "forged"; one I asked for or logged in with is "unseen".
--
-- What a closed hand means for my debt (Stakes.fairFoul, from the "fair"
-- event; "my side" = me and the player in my partner's seat):
--   verdict on my client                                   foul
--   "ok"                                                   none
--   "unseen"                                               unseen
--   "bad", why "announce"                                  none (the engine scored it 0 on every client)
--   "bad", why "noreveal", the dealer on my side           unseen
--   any other "bad"                                        deal
--   "void", or "bad" "nodeal", the dealer on my side       none ("nodeal" on my side: unseen)
--   "void" or "bad" "nodeal", the dealer not on my side:
--     that dealer's first in the match                     unseen
--     its second (fairVoids[name] + fairLapses[name] >= 2) deal
-- The verdict of the last hand comes after the event that ended the match:
-- the note of that match waits for it (note.wait) at most STAKE_FAIR_WAIT; a
-- hand still open then reads "unseen". A match that ended by a leave waits
-- for nothing: its running hand gets no verdict.
--
-- What the throws mean for my debt (Stakes.fairCount, from the session's dice
-- counts after the extension `dice` has run): a throw closed "bad" in this
-- match (diceSeen.bad > 0) or diceRobbed > 0 -> dice; diceSeen.unseen > 0 or
-- diceAway > 0 -> unseen.
local Stakes = ns.Stakes
local NONE = {}

-- Does s's engine have a fairness layer that judges its snapshots -> bool.
function Stakes.judged(s)
  local ext = s:engine().ext or NONE
  for _, x in ipairs(ext) do
    if x == "fair" or x == "dice" then return true end
  end
  return false
end
