local Sim = require("sim")
local ns = Sim.ns
local F, H, S = ns.Fair, require("hicard_engine"), ns.Engines.santase
local SEED, ZERO = ("ff"):rep(16), ("00"):rep(16)

-- An honest two-player hicard hand at table "t", round 1, as seat 1 saw it.
-- deck = F.deck(H.DECK, seeds, "t/1") = 9C AC QC QD JC TC ...: seat 1 holds
-- 9C, QC; seat 2 AC, QD; up JC (clubs).
local function rec()
  local seeds, p = { SEED, SEED }, { 1, 2 }
  return {
    tid = "t", h = 1, p = p, seeds = seeds,
    commits = { [1] = F.commit(SEED), [2] = F.commit(SEED) },
    base = H.snapshot(H.view(H.new{ first = 1, seats = { true, true } }, 0)),
    log = {
      { 0, { k = "deal", deck = { [5] = "JC" } } },
      { 1, { k = "play", i = 1, c = "9C" } },
      { 2, { k = "play", i = 2, c = "AC" } },
    },
    priv = { [1] = "9C", [3] = "QC" },
  }
end

describe("fair", function()
  it("a seed is 16 random bytes in hex and the commit is its SHA-256", function()
    local calls = 0; eq(F.seed(function(lo, hi) calls = calls + 1; eq({ lo, hi }, { 0, 255 }); return 255 end), SEED); eq(calls, 16)
    eq(F.seed(function() return 0 end), ZERO); eq(F.seed(function() return 10 end), ("0a"):rep(16))
    eq(F.commit(SEED), "352302489bc2fcf025cf00cda8308033f97ac87712ce90b4d7cd72c58e4c3af9")
    eq(F.commit("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"); eq(F.handId("Иван Петров#17", 7), "Иван Петров#17/7")
  end)

  it("the deck is the engine's deck in the order the seeds and the hand id give", function()
    eq(table.concat(F.deck(S.DECK, { ZERO, SEED }, "t/1"), " "),
      "QC TH 9S QD JC KS KD JD QS KH TD JH QH KC AH AC 9C AD 9H TC 9D TS AS JS")
    eq(table.concat(F.deck(H.DECK, { SEED, SEED }, "t/1"), " "), "9C AC QC QD JC TC AD JD 9D KD KC TD")
    eq(table.concat(F.deck(H.DECK, { SEED, SEED }, "t/2"), " "), "TD KD TC QD QC 9C AC JD JC KC AD 9D")
    ok(table.concat(F.deck(H.DECK, { SEED, ZERO }, "t/1"), " ") ~= table.concat(F.deck(H.DECK, { ZERO, SEED }, "t/1"), " "))
  end)

  it("full turns a view into the full state without touching the view", function()
    local s = H.new{ first = 1, seats = { true, true } }; ok(H.apply(s, 0, { k = "deal", deck = H.DECK }))
    local v = H.view(s, 2); eq(F.full(v, s.deck), s); eq(v.full, false); eq(v.deck[1], nil)
  end)

  it("an honest hand is ok; each kind of fault is named", function()
    eq({ F.audit(H, rec()) }, { "ok" })
    local r = rec(); r.seeds = { SEED }; eq({ F.audit(H, r) }, { "bad", "seeds" })
    r = rec(); r.p = { 2, 1 }; eq({ F.audit(H, r) }, { "bad", "seeds" })                              -- p not in ascending seat order
    r = rec(); r.p = { 1, 1 }; eq({ F.audit(H, r) }, { "bad", "seeds" })
    r = rec(); r.seeds[2] = ZERO; eq({ F.audit(H, r) }, { "bad", "commit" })
    r = rec(); r.log[1][2].deck[5] = "KC"; eq({ F.audit(H, r) }, { "bad", "deal" })
    r = rec(); table.remove(r.log, 1); eq({ F.audit(H, r) }, { "bad", "deal" })
    r = rec(); r.priv[1] = "TC"; eq({ F.audit(H, r) }, { "bad", "dealt" })
    r = rec(); r.log[2][2].c = "TC"; eq({ F.audit(H, r) }, { "bad", "play" })                         -- a card he did not hold
    r = rec(); r.log[3] = { 2, { k = "play", i = 4, c = "QD" } }; eq({ F.audit(H, r) }, { "bad", "play" })   -- held a club, played a diamond
    r = rec(); r.log[4] = { 0, { k = "stand", seat = 2, why = "left" } }; eq({ F.audit(H, r) }, { "ok" })
  end)
end)
