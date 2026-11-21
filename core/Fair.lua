local _, ns = ...

-- The fair deal's pure part (spec 6.3): seeds and their commits, the deck the
-- revealed seeds give, and the audit of a closed hand by replaying it on the
-- full state. No session, no env: randomness comes in as an argument.
-- ns.Deck and ns.Sha256 are read at call time (a test may replace them).
local Fair = {}
ns.Fair = Fair

local format = string.format

-- SEED_BYTES values of random(0, 255) as lowercase hex.
function Fair.seed(random)
  local out = {}
  for i = 1, ns.Const.SEED_BYTES do out[i] = format("%02x", random(0, 255)) end
  return table.concat(out)
end

-- The commit of a seed: the SHA-256 of its text, in hex.
function Fair.commit(seed)
  return ns.Sha256.hex(seed)
end

function Fair.handId(tid, h)
  return tid .. "/" .. h
end

-- DECK in the order the seeds (ascending seat order) and the hand id give.
function Fair.deck(DECK, seeds, handId)
  local p = ns.Deck.permutation(ns.Deck.key(seeds, handId), #DECK)
  local out = {}
  for i = 1, #DECK do out[i] = DECK[p[i]] end
  return out
end

-- A view with the whole deck: behaves as the full state. `view` is untouched.
function Fair.full(view, deck)
  local copy = ns.Util.copy
  local s = copy(view)
  s.deck, s.full = copy(deck), true
  return s
end

-- Checks a closed hand; first failure wins. rec = {tid, h, p, commits, seeds,
-- base, log, priv, faces}: p = the participants' seats, strictly ascending
-- (else "seeds"), seeds in p order, commits by seat, base = the engine
-- snapshot when the round opened, log = {seat, a} since then, priv = faces I
-- was shown privately. Without base (I did not see the hand from its start)
-- there is no replay: the seeds are still checked against the commits, and
-- priv and `faces` (every face my state knows now) against the deck they give
-- ("dealt", "deal"). -> "ok" | "bad", why | "unseen"
function Fair.audit(engine, rec)
  local p, seeds, commits = rec.p, rec.seeds, rec.commits or {}
  if type(seeds) ~= "table" or #seeds ~= #p then return "bad", "seeds" end
  for k = 1, #p do
    if type(p[k]) ~= "number" or (k > 1 and p[k] <= p[k - 1]) then return "bad", "seeds" end
  end
  for k = 1, #p do
    if type(seeds[k]) ~= "string" then return "bad", "seeds" end
  end
  for k = 1, #p do
    if Fair.commit(seeds[k]) ~= commits[p[k]] then return "bad", "commit" end
  end

  local deck = Fair.deck(engine.DECK, seeds, Fair.handId(rec.tid, rec.h))
  if not rec.base then
    for i, f in pairs(rec.priv or {}) do
      if deck[i] ~= f then return "bad", "dealt" end
    end
    for i, f in pairs(rec.faces or {}) do
      if deck[i] ~= f then return "bad", "deal" end
    end
    return "unseen"
  end
  local dealt = false
  for _, e in ipairs(rec.log) do
    local a = e[2]
    if e[1] == 0 and type(a) == "table" and a.k == "deal" then
      if a.deck ~= nil and type(a.deck) ~= "table" then return "bad", "deal" end
      for i, f in pairs(a.deck or {}) do
        if deck[i] ~= f then return "bad", "deal" end
      end
      dealt = true
    end
  end
  if not dealt then return "bad", "deal" end

  for i, f in pairs(rec.priv or {}) do
    if deck[i] ~= f then return "bad", "dealt" end
  end

  local base = rec.base
  local state = Fair.full(engine.restore(base), base.deck)
  for _, e in ipairs(rec.log) do
    local seat, a = e[1], e[2]
    local k = seat == 0 and type(a) == "table" and a.k
    if k == "stand" then
      if engine.leave then engine.leave(state, a.seat) end
    elseif k == "deal" then
      if not engine.apply(state, 0, { k = "deal", deck = deck }) then return "bad", "play" end
    elseif k ~= "sit" then
      if not engine.apply(state, seat, a) then return "bad", "play" end
    end
  end
  return "ok"
end

return Fair
