local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C = ns.Const

-- A seat whose client is cut off (it runs, it hears nothing) at a staked table
-- (e2e soak, tools/sim/e2e_soak.lua: seeds 200031, 200028).
local A, B = Play.NAMES[1], Play.NAMES[2]
local D = "Дара Маринова"
local SK = 25000

local function dsBy(sim, author)
  local out = {}
  for _, e in ipairs(Play.entries(sim, nil, "D")) do
    if ns.Ledger.author(e.i) == author then out[#out + 1] = e end
  end
  return out
end

describe("a seat cut off at a staked table", function()
  -- Two players: alone it cannot tell its own cut from a host gone for good, so it stands the
  -- host up as any host does (fix round 1, review C1), and the host, which nobody follows
  -- either, stood it up: both branches stay, as before. Each branch's claim is only a claim.
  it("two players: each stands the other up; the cut-off branch's claim stays unconfirmed", function()
    local sim, cl = Play.guild(2, { D })
    Play.open(sim, cl, "santase", SK, 2)
    for _ = 1, 4 do Play.step(sim, cl[A]) end
    sim:offline(B); sim:run(C.SILENT_AFTER + 5)
    eq(cl[B].session.role, "host") -- it claimed: it cannot tell its own cut from the host's
    sim:run(C.OFFLINE_STAND_SECONDS + 30)
    sim:online(B); sim:run(C.TBL_HEARTBEAT + C.STAKE_OWE_WAIT + 30)
    for _, e in ipairs(dsBy(sim, B)) do
      local d = Play.debt(cl[D], e.gid, e.f, e.t)
      ok(d == nil or d.status ~= "confirmed", "the cut-off branch's claim " .. e.gid .. ": " .. tostring(d and d.status))
    end
    -- The host stood the silent guest up: its forfeit, B owes A.
    eq(cl[A].session.role, "host"); eq(cl[A].session.epoch, 1)
    local d = dsBy(sim, A)
    eq(#d, 1); eq({ d[1].f, d[1].t, d[1].why }, { B, A, "offline" })
  end)
end)

-- Review C1 (fix round 1): the host of a 2-seat table is gone for good. The guest claims,
-- plays the dead host's timeouts and stands it up offline OFFLINE_STAND_SECONDS after its
-- last message: the forfeit is the dead host's, exactly as before the cut-off fix.
describe("a 2-seat table whose host is gone for good", function()
  local function dead(sim, cl) sim.envs[A].dead = true; sim:offline(A) end
  it("staked ???????: the guest stands the dead host up and wins the stake", function()
    local sim, cl = Play.guild(2, { D })
    Play.open(sim, cl, "santase", SK, 2)
    for _ = 1, 4 do Play.step(sim, cl[A]) end
    dead(sim, cl); sim:run(C.SILENT_AFTER + 5)
    eq(cl[B].session.role, "host")
    sim:run(C.OFFLINE_STAND_SECONDS + 60)
    eq(cl[B].session.seats[1], false); eq(cl[B].session.status, "aborted")
    local ds = Play.entries(sim, nil, "D")
    eq(#ds, 1); eq({ ds[1].f, ds[1].t, ds[1].c }, { A, B, SK })
  end)
  it("?????? ??? for fun, nobody else online: the guest plays the dead host's turns and stands it up", function()
    local sim, cl = Play.guild(2)
    Play.open(sim, cl, "ttt", nil, 2)
    local q = cl[B].session.seq
    dead(sim, cl); sim:run(C.SILENT_AFTER + 5)
    eq(cl[B].session.role, "host")
    sim:run(C.OFFLINE_STAND_SECONDS + 60)
    ok(cl[B].session.seq > q, "the dead host's timeouts were played")
    eq(cl[B].session.seats[1], false)
  end)
  it("cash Hold'em: the dead host is stood up and its pair settled to the guest", function()
    local sim, cl = Play.cash(2)
    Play.hand(sim, cl[A])
    local owe = cl[A].session.state.seats[1].chips < cl[A].session.state.seats[1].bought
    dead(sim, cl); sim:run(C.SILENT_AFTER + 5 + C.OFFLINE_STAND_SECONDS + 60)
    eq(cl[B].session.seats[1], false)
    for _, e in ipairs(Play.entries(sim, nil, "D")) do eq(e.f, owe and A or B) end
  end)
  it("the guest that gives up and stands owes the dead host nothing", function()
    local sim, cl = Play.guild(2, { D })
    Play.open(sim, cl, "santase", SK, 2)
    for _ = 1, 4 do Play.step(sim, cl[A]) end
    dead(sim, cl); sim:run(C.SILENT_AFTER + 30)
    sim:run(C.OFFLINE_STAND_SECONDS); cl[B]:stand(); sim:run(C.STAKE_OWE_WAIT + 10)
    for _, e in ipairs(Play.entries(sim, nil, "D")) do ok(e.f ~= B, "a debt of the guest who stayed") end
  end)
end)

describe("a seat cut off at a cash table", function()
  it("stood up offline meanwhile, back it follows the host again and calls nothing forged", function()
    local sim, cl = Play.cash(3)
    local V = Play.NAMES[3]
    local fouls = {}
    local foul = ns.Stakes.foul
    ns.Stakes.foul = function(s, why) fouls[#fouls + 1] = s.client.env.me .. ":" .. why; return foul(s, why) end
    local okRun, err = pcall(function()
      Play.hand(sim, cl[A])
      sim:offline(B); sim:run(C.OFFLINE_STAND_SECONDS + 40)
      eq(cl[A].session.seats[2], false) -- the host stood the silent seat up
      eq(cl[B].session.role, "host")
      sim:online(B); sim:run(C.TBL_HEARTBEAT + 5)
      eq({ cl[A].session.role, cl[A].session.epoch, cl[V].session.host }, { "host", 1, A })
      local bs = cl[B].session
      ok(bs == nil or (bs.host == A and bs.mySeat == nil), "B: " .. tostring(bs and bs.role))
      eq(#dsBy(sim, B), 0)
      for _, f in ipairs(fouls) do ok(not f:find(":forged", 1, true), f) end
    end)
    ns.Stakes.foul = foul
    if not okRun then error(err, 0) end
  end)
end)

describe("two seats claim a table whose host is gone", function()
  -- e2e soak (seed 1100150): the host died and the first candidate was cut off as well; it
  -- claimed alone, the second claimed with the last seat following it. Back, the first won
  -- the seat tie of their epoch and stayed a host of its own: the table ran on twice.
  it("the one nobody follows follows the one the others follow", function()
    local sim, cl = Play.guild(4)
    local I, P, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
    Play.open(sim, cl, "belot", nil, 4)
    for _ = 1, 4 do Play.step(sim, cl[I]) end
    sim.envs[I].dead = true; sim:offline(I) -- the host's client is gone
    sim:offline(P)
    for _ = 1, C.SILENT_AFTER + 3 * C.CLAIM_STAGGER do
      if cl[M].session.role == "host" then break end
      sim:run(1)
    end
    eq({ cl[P].session.role, cl[M].session.role, cl[G].session.host }, { "host", "host", M })
    sim:online(P); sim:run(C.PING_EVERY + 5)
    eq({ cl[P].session.role, cl[P].session.host, cl[G].session.host, cl[M].session.role }, { "player", M, M, "host" })
    eq({ cl[P].session.seq, cl[G].session.seq, cl[P].session.epoch }, { cl[M].session.seq, cl[M].session.seq, cl[M].session.epoch })
    eq(cl[P].session.state.trickNo, cl[M].session.state.trickNo); eq(cl[P].session.state.turn, cl[M].session.state.turn)
  end)
end)

-- Review I1 (fix round 1): a host that goes silent to one seat alone, while that seat's
-- client keeps hearing the guild, and stands it up "offline": no "unseen" for that stand.
describe("a seat the host alone went silent to", function()
  it("its stand in the host's snapshot stays forged", function()
    local sim, cl = Play.cash(3)
    local V = Play.NAMES[3]
    local fouls = {}
    local foul = ns.Stakes.foul
    ns.Stakes.foul = function(s, why) if s.client.env.me == B then fouls[#fouls + 1] = why end; return foul(s, why) end
    local okRun, err = pcall(function()
      Play.hand(sim, cl[A])
      sim.bus.filter = function(from, to, _, m) if (from == A and to == B) or (from == B and to == A) then return {} end return { m } end
      for t = 1, C.OFFLINE_STAND_SECONDS + 40 do
        if t % 30 == 0 then cl[V].presence:sendGuildHi(false) end -- the guild still reaches B
        sim:run(1)
      end
      eq(cl[A].session.seats[2], false); eq(cl[B].session.role, "host")
      sim.bus.filter = nil; sim:run(C.TBL_HEARTBEAT + 5)
      eq(cl[B].session == nil or cl[B].session.host == A, true)
      local forged = false
      for _, f in ipairs(fouls) do forged = forged or f == "forged" end
      ok(forged, "B's fouls: " .. table.concat(fouls, ","))
    end)
    ns.Stakes.foul = foul
    if not okRun then error(err, 0) end
  end)
end)

-- Fix round 1 (soak seed 4100150 with `dead`): the host of two players was cut off; each stood
-- the other up. The guest, which was there all along, must not take up the cut-off host's
-- branch (its timeouts in the guest's name: "forged" on an honest guest).
describe("two players, the host cut off long", function()
  it("the guest does not give its table to a host nobody follows", function()
    local sim, cl = Play.guild(2)
    Play.open(sim, cl, "ttt", SK, 2)
    local fouls = {}
    local foul = ns.Stakes.foul
    ns.Stakes.foul = function(s, why) if s.client.env.me == B then fouls[#fouls + 1] = why end; return foul(s, why) end
    local okRun, err = pcall(function()
      sim:offline(A); sim:run(C.OFFLINE_STAND_SECONDS + 20)
      eq(cl[B].session.role, "host")
      sim:online(A); sim:run(C.TBL_HEARTBEAT + C.PING_EVERY + 10)
      eq(cl[B].session.host, B)
      for _, f in ipairs(fouls) do ok(f ~= "forged", "B noted forged") end
    end)
    ns.Stakes.foul = foul
    if not okRun then error(err, 0) end
  end)
end)
