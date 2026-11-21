local _, ns = ...

-- The dice line of the table frame and its tooltip (core/Dice.lua; rules:
-- engine contract, Addendum 6): what my client can say of the throws of this
-- match from the session's dice fields.
local Dice = ns.Dice
local contains = ns.Util.contains

-- Is the dice line red: a bad throw in this match, or two went unheard.
function Dice.alarm(s)
  return (s.diceSeen ~= nil and s.diceSeen.bad > 0) or (s.diceUnheard or 0) >= 2
end

-- The table frame's dice line -> locale key, colour token, arg, arg2 | nil:
-- nil for an engine without the extension "dice", and before the first throw.
function Dice.status(s)
  if not contains(s:engine().ext or {}, "dice") then return nil end
  local throw, last, red = s.throw, s.diceLast, Dice.alarm(s) and "red" or nil
  if throw and not throw.done then return "dice.rolling", red or "inkDim" end
  if not last then return nil end
  if last.verdict == "ok" then return "dice.ok", red or "good" end
  if last.verdict == "bad" then return "dice.bad", "red" end
  if last.verdict == "unseen" then return "dice.unseen", red or "gold" end
  if last.n >= 2 then return "dice.aloneMany", red or "gold", last.by, last.n end
  return "dice.alone", red or "gold", last.by, last.silent
end

-- The dice line's tooltip -> {{colour token, locale key, arg}, ...}.
function Dice.tip(s)
  local out = { { "ink", "dice.tip" } }
  if s.diceBad then out[#out + 1] = { "red", "dice.tip.bad", s.diceBad } end
  if s.diceUnheard then out[#out + 1] = { "red", "dice.unheard", s.diceUnheard } end
  if s.diceAway then out[#out + 1] = { "ink", "dice.away", s.diceAway } end -- my own loading screens: nobody's fault
  local cry = s.diceCry -- another seat's claim: shown, it changes no colour of mine
  if cry and cry.seat ~= s.mySeat then out[#out + 1] = { "gold", "dice.cry", cry.name, cry.why } end
  return out
end

return Dice
