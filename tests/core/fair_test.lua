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
  -- An env whose generator gives `n` every time (the worst one there is).
  local function envOf(n, me)
    local env = { me = me or "Иван Петров", guid = "Player-1", calls = 0, now = function() return 12.5 end, epoch = function() return 1700000000 end }
    env.random = function(lo, hi) env.calls = env.calls + 1; eq({ lo, hi }, { 0, 255 }); return n end
    return env
  end
  local function isSeed(x) return type(x) == "string" and #x == 32 and not x:find("[^0-9a-f]") end

  it("a seed is 16 bytes in hex out of the client's secret pool, never the generator's own output; the commit is its SHA-256", function()
    local seed, env = Sim.realSeed, envOf(255)
    local x = seed(env, "dice|t#1/3"); ok(isSeed(x), x); ok(x ~= SEED); eq(env.calls, 64)
    local y, z = seed(env, "dice|t#1/3"), seed(env, "deal|t#1/3"); ok(isSeed(y) and isSeed(z)); eq(env.calls, 64)   -- the pool is built once
    ok(x ~= y and y ~= z and x ~= z)                                           -- the counter and the purpose both tell seeds apart
    local other = seed(envOf(255, "Мария Стоянова"), "dice|t#1/3"); ok(isSeed(other) and other ~= x)   -- another client, the same generator
    ok(seed(envOf(0), "dice|t#1/3") ~= x)
    local late = envOf(255); late.now = function() return 99 end; ok(seed(late, "dice|t#1/3") ~= x)
    local rich = envOf(255); rich.entropy = function() return "e" end; ok(seed(rich, "dice|t#1/3") ~= x)
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

  it("a table key gives one seed a hand; the same key and hand give the same seed", function()
    eq(F.handSeed(SEED, "t#1/1"), "8a096ed15cb70ed784b4785d4e17cd5b"); eq(F.handSeed(SEED, "t#1/2"), "b68638cff5e56a73ad112fbb79444292")
    eq(F.handSeed(ZERO, "t#1/1"), "e5095b93260184a29b277f91645c49da")
    eq(F.commit(F.handSeed(SEED, "t#1/1")), "b64fd9e94132a8c73a533d601ce4cacad546b9e7e2a47fb7941ca992e85be5ec")
    local d = F.deck(ns.Engines.holdem.DECK, { F.handSeed(SEED, "t#1/1"), F.handSeed(ZERO, "t#1/1") }, "t#1/1"); eq({ d[1], d[2], d[3], d[52] }, { "TS", "7C", "9C", "8C" })
  end)

  it("dice come from the seeds and the throw's id; each die is uniform", function()
    eq({ F.dice({ ZERO, SEED }, "t#1/1") }, { 4, 5 }); eq({ F.dice({ SEED, ZERO }, "t#1/1") }, { 2, 1 }); eq({ F.dice({ ZERO, SEED }, "t#1/2") }, { 1, 4 })
    eq({ F.dice({ SEED, SEED }, "t#1/1") }, { 3, 3 }); eq({ F.dice({ ZERO }, "t#1/1") }, { 1, 4 }); eq({ F.dice({ ("ab"):rep(16) }, "t#1/7") }, { 2, 2 })
    local n, doubles = { 0, 0, 0, 0, 0, 0 }, 0
    for i = 1, 3600 do
      local x, y = F.dice({ ZERO, SEED }, "x/" .. i); n[x] = n[x] + 1; n[y] = n[y] + 1
      if x == y then doubles = doubles + 1 end
    end
    eq(n, { 1213, 1208, 1188, 1239, 1169, 1183 }); eq(doubles, 601)
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
