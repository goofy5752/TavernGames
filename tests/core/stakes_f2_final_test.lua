-- The findings of the final review of stage F2 (Ruling F2-F): what a modified
-- host could make an honest client confirm by itself, and no longer can.
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, View = ns.Const, ns.LedgerView

local I, P, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local SK = 50000

-- The GUILD entries of kind k (C or N) `from` sent about a D at gid.
local function wordsAt(sim, from, k, gid)
  local ds, out = {}, {}
  for _, d in ipairs(Play.entries(sim, nil, "D")) do if d.gid == gid then ds[d.i] = true end end
  for _, e in ipairs(Play.entries(sim, from, k)) do if ds[e.r] then out[#out + 1] = e end end
  return out
end

-- Is the debt gid|f|t among client's asks()?
local function asked(client, gid, f, t)
  for _, d in ipairs(client.stakes:asks()) do
    if d.gid == gid and d.f == f and d.t == t then return true end
  end
  return false
end

-- A staked Белот table that Петър hosts from seat 2: seat 1 Иван, seat 3 Гошо
-- (partners), seat 4 Мария (the host's partner) -> sim, cl, tid.
local function petarHosts()
  local sim, cl = Play.guild(4)
  local tid = assert(cl[I]:openTable{ game = "belot", access = "guild", turn = 45, stake = SK }); sim:run(3)
  cl[P]:sit(tid, 2, SK); sim:run(1)
  cl[I]:stand(); sim:run(3)
  cl[I]:sit(tid, 1, SK); sim:run(1)
  cl[G]:sit(tid, 3, SK); sim:run(1)
  cl[M]:sit(tid, 4, SK); sim:run(1)
  eq({ cl[P].session.role, cl[P].session.status, cl[P].session.seats }, { "host", "live", { I, P, G, M } })
  return sim, cl, tid
end

-- Петър's match is played to its end; each step, before(steps) may act
-- instead of the seat on turn (-> true) -> the last "result", the steps taken.
local function play(sim, host, before)
  local last, steps = nil, 0
  host:on("result", function(r) last = r end)
  for _ = 1, 30000 do
    if host.session:gameOver() then return last, steps end
    steps = steps + 1
    if not (before and before(steps)) then Play.step(sim, host) end
  end
  error("the match did not end")
end

describe("stakes: the final review of F2", function()
  it("belot: the host voids a hand my partner dealt: my loss is put to me, the dealer contests (C1)", function()
    for n = 1, 2 do -- the first such hand is Иван's deal, the second Гошо's
      local sim, cl, tid = petarHosts()
      local host, seen, count, dealer = cl[P], {}, 0, nil
      local r = play(sim, host, function()
        local s = host.session
        local f = s.fair
        if not (f and f.stage == "dealt" and (f.d == 1 or f.d == 3) and s.state.turn and not seen[f.h]) then return false end
        seen[f.h], count = true, count + 1
        if count ~= n then return false end
        local q = s.seq
        s:play(0, { k = "void" })
        ok(s.seq > q, "the void is played")
        dealer = s.seats[f.d]
        sim:run(1)
        return true
      end)
      sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 10)
      eq(r.losers, { 1, 3 }) -- Иван and Гошо lose: Иван owes Петър, Гошо owes Мария
      local gid, partner = tid .. "/" .. r.q, dealer == I and G or I
      local owedBy = { [I] = P, [G] = M }
      eq(#wordsAt(sim, dealer, "N", gid), 1); eq(wordsAt(sim, dealer, "N", gid)[1].why, "deal")
      eq(#wordsAt(sim, partner, "C", gid), 0); eq(#wordsAt(sim, partner, "N", gid), 0)
      ok(asked(cl[partner], gid, partner, owedBy[partner]), "the partner's debt is put to it")
      eq(Play.debt(cl[P], gid, partner, owedBy[partner]).status, "pending")
    end
  end)
end)
