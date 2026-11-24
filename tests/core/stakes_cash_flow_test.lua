Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, E, Ledger, View, U = ns.Const, ns.Engines.holdem, ns.Ledger, ns.LedgerView, ns.Util

-- The whole road of a staked Холдем (stage F3 Task 12), with the real wire
-- format as wow/Adapter.lua installs it (restored at the end of this file).
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
local stand = ns.LedgerNet.size
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end

local A, B, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local K, N6 = Play.MORE[1], Play.MORE[2]
local ALL = { A, B, M, G, K, N6 } -- the name of chair i (Play.cash)

-- A small generator so that every client of a run draws from one stream
-- (copied from tests/core/stakes_f2_flow_test.lua).
local function lcg(seed)
  local x = seed
  return function(lo, hi)
    x = (x * 1103515245 + 12345) % 2147483648
    return lo + math.floor(x / 65536) % (hi - lo + 1)
  end
end

-- The client that hosts the table now (online), or nil.
local function host(sim)
  for name, c in pairs(sim.clients) do
    if c.session and c.session.role == "host" and not sim.offlineSet[name] then return c end
  end
end

-- One second: the seat on turn at the host's table moves from its own client (E.bot with the
-- shared generator BOT, else its automatic move), unless that client is offline.
local BOT
local function step(sim)
  local s = host(sim).session
  local seat = s.status == "live" and s.state and s.state.turn
  local name = seat and s.seats[seat]
  local c = name and not sim.offlineSet[name] and sim.clients[name]
  if c and c.session and c.session.state then
    local a = E.bot(c.session.state, seat, BOT)
    if a then c:act(a) else c:playAuto() end
  end
  sim:run(1)
end

-- Between hands, when fewer than two seats hold chips: every online seat out of chips buys MIN_BB
-- big blinds again from its own client, where the table's rebuy mode lets it -> how many bought.
local function rebuy(sim)
  local s = host(sim).session
  local st, live, n = s.state, 0, 0
  if E.inHand(st) then return 0 end
  for i = 1, 9 do if st.seats[i] and st.seats[i].chips > 0 then live = live + 1 end end
  if live >= 2 then return 0 end
  for i = 1, 9 do
    local x, name = st.seats[i], s.seats[i]
    if x and x.chips == 0 and x.bought > 0 and name and not sim.offlineSet[name] and E.buyRange(st, i) then
      assert(sim.clients[name]:buy(ns.HoldemCash.MIN_BB * st.bb))
      n = n + 1
    end
  end
  sim:run(1)
  return n
end

-- n hands played out at the host's table (each one an error after 600 s), fewer when no hand can be
-- dealt (mode "none": the table is out of chips); stats counts the all-ins, the side pots and the
-- rebuys of `rebuy`.
local function hands(sim, n, stats)
  for _ = 1, n do
    local hand
    for i = 1, 600 do
      local st = host(sim).session.state
      if hand and not (E.inHand(st) and st.hand == hand) then
        if st.last and st.last.hand == hand and #(st.last.pots or {}) > 1 then stats.side = stats.side + 1 end
        break
      end
      if not hand and E.inHand(st) then hand = st.hand end
      for seat, p in pairs(st.p or {}) do
        local key = tostring(st.hand) .. "/" .. seat
        if p.allin and not stats.seen[key] then stats.seen[key], stats.allin = true, stats.allin + 1 end
      end
      if not hand then
        local got = rebuy(sim)
        stats.rebuys = stats.rebuys + got
        local live = 0
        for j = 1, 9 do if st.seats[j] and st.seats[j].chips > 0 then live = live + 1 end end
        if got == 0 and live < 2 and (st.phase == "done" or st.phase == "idle") then stats.stuck = true; return end
      end
      assert(i < 600, "the hand did not end")
      step(sim)
    end
  end
end

-- One second at a time until no hand runs at the host's table (an error after 600 s).
local function between(sim)
  for _ = 1, 600 do
    if not E.inHand(host(sim).session.state) then return end
    step(sim)
  end
  error("the hand did not end")
end

-- The "cashout" events of client c that it emitted while it hosted, into list.
local function hosted(list, c)
  c:on("cashout", function(v)
    if c.session and c.session.role == "host" then list[#list + 1] = v end
  end)
end

local function q(gid) return tonumber(gid:match("/(%d+)$")) end

-- Every GUILD LEV entry of the sim -> list.
local function entries(sim)
  local out = {}
  for _, m in ipairs(sim.sent) do
    if m.channel == "GUILD" and m.msg.t == "LEV" then
      for _, e in ipairs(m.msg.ev or {}) do out[#out + 1] = e end
    end
  end
  return out
end

-- Is the debt key among client's asks -> bool.
local function asked(client, key)
  for _, d in ipairs(client.stakes:asks()) do if d.key == key then return true end end
  return false
end

-- The evening of the brief (rebuy mode `mode`; with `vanish`, Kiro goes offline and is stood up):
-- six players at blinds 10, hands by E.bot. 12 hands; Мария reloads inside a hand; 8 hands; a seat
-- buys again (bust: from no chips; top: up to 100 BB; none: refused); Гошо stands inside a hand
-- (his cashout at its end); Kiro offline for OFFLINE_STAND_SECONDS (vanish); 8 hands; the host
-- stands (its successor hosts on); 6 hands; the new host's „Приключи“; BOOK_WAIT + 10 s; Kiro
-- relogs (vanish); 300 s of sync -> sim, cl, outs (the "cashout" events of the client hosting at
-- the time), stats, the new host, forfeits. opt (with vanish): before(sim, cl), called before
-- Kiro's relog; key, the key his saved variables hold then (a forged one); never: he stays away.
local function evening(mode, vanish, opt)
  opt = opt or {}
  BOT = lcg(opt.seed or 7)
  local sim, cl = Play.cash(6, { blinds = 10, rebuy = mode }, { 400, 600, 800, 1000, 1000, 500 })
  local outs, stats, forfeits = {}, { allin = 0, side = 0, rebuys = 0, seen = {} }, { n = 0 }
  local function watch(c)
    hosted(outs, c)
    c:on("forfeit", function() forfeits.n = forfeits.n + 1 end)
  end
  for _, c in pairs(cl) do watch(c) end
  hands(sim, 12, stats)
  -- Мария reloads in the middle of a hand.
  for _ = 1, 30 do if E.inHand(host(sim).session.state) then break end; step(sim) end
  ok(E.inHand(host(sim).session.state), "Мария reloads inside a hand")
  cl[M] = sim:relog(M); watch(cl[M]); sim:run(3)
  eq(cl[M].session.stakeFoul, "unseen")
  between(sim)
  hands(sim, 8, stats)
  -- A seat buys again, as the mode lets it.
  between(sim)
  local hs = host(sim).session
  local st, who = hs.state, nil
  for i = 1, 6 do
    local x, name = st.seats[i], hs.seats[i]
    local want = x and x.bought > 0 and (mode == "top" and x.chips < ns.HoldemCash.MAX_BB * st.bb or x.chips == 0)
    if not who and want and name ~= G and name ~= K then who = i end
  end
  stats.again = who ~= nil -- no seed has to bust a seat by now (the seeds together do: COVER)
  local x, name = st.seats[who or 0], hs.seats[who or 0]
  local before = x and x.bought
  if not who then
  elseif mode == "none" then
    eq({ E.buyRange(st, who) }, { nil, "rebuy" })
    eq({ cl[name]:buy(400) }, { nil, "rebuy" })
  else
    local n = mode == "top" and ns.HoldemCash.MAX_BB * st.bb - x.chips or 400
    ok(cl[name]:buy(n)); sim:run(2)
    eq(host(sim).session.state.seats[who].bought, before + n)
    stats.rebuys = stats.rebuys + 1
  end
  -- Гошо stands inside a hand: his cashout comes at its end, then his stand.
  for _ = 1, 30 do if E.inHand(host(sim).session.state) then break end; step(sim) end
  cl[G]:stand(); sim:run(1)
  between(sim); sim:run(3)
  eq(cl[G].session, nil)
  if vanish then
    -- Kiro's connection drops (his client stops, as WoW leaves the world); stood up after 180 s.
    sim:offline(K); sim.envs[K].dead = true
    for _ = 1, C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER + 600 do
      if host(sim).session.seats[5] == false then break end
      step(sim)
    end
    eq(host(sim).session.seats[5], false)
  end
  hands(sim, 8, stats)
  -- The host stands: the table goes on under its successor.
  between(sim)
  cl[A]:stand(); sim:run(3)
  eq(cl[A].session, nil)
  local h = host(sim)
  ok(h and h ~= cl[A], "a successor hosts")
  hands(sim, 6, stats)
  -- The new host's „Приключи“, the hand played out, the keys out.
  assert(ns.Cash.close(h)); sim:run(1)
  between(sim)
  sim:run(C.BOOK_WAIT + 10)
  if vanish then
    if opt.before then opt.before(sim, cl) end
    if opt.key then sim.envs[K].db.bookKeep.key = opt.key end
    if not opt.never then cl[K] = sim:relog(K); sim:settle() end
  end
  sim:run(300)
  return sim, cl, outs, stats, h, forfeits.n
end

-- The debt key of Book:owing (an unseen note's debt nobody claimed) -> its entry, or nil.
local function owing(client, key)
  for _, o in ipairs(client.stakes:owing()) do if o.key == key then return o end end
end

-- What every evening keeps: every pair of every out record is one debt with its amount on every
-- client, a sitting's debts sum to its result, the nets of the evening to 0; no C, no R, no
-- forfeit; one S per out record, its seats bounded by its names. `clean`: the debtors whose own D
-- confirms their debts; every other debt is pending and put to its debtor. A pair whose creditor
-- wrote no claim (only a name in `gone` may: whether it was a creditor before it went is the
-- seed's) and whose debtor is not clean is in no ledger: it is the debtor's question „Да го
-- запиша ли?“ (Book:owing). x.contest: the debtors whose debts are contested (no own D, no
-- question); x.either: the debtors whose debts are contested or put to them, each debt by what
-- its own book holds (the seed's), never confirmed; x.away: the names whose client is gone at the
-- end (not looked at). -> the names that owe.
local function checked(sim, cl, outs, h, forfeits, clean, gone, x)
  local final, said, claimed = {}, {}, {}
  local contest, away, either = x and x.contest or {}, x and x.away or {}, x and x.either or {}
  for _, name in ipairs(ALL) do if not away[name] then final[#final + 1] = cl[name] end end
  for _, e in ipairs(entries(sim)) do
    if e.k == "D" and e.why == "cash" and Ledger.author(e.i) == e.f then said[e.gid .. "|" .. e.f .. "|" .. e.t] = true end
    if e.k == "D" and Ledger.author(e.i) == e.t then claimed[e.gid .. "|" .. e.f .. "|" .. e.t] = true end
  end
  local n, total, owes = 0, 0, {}
  for _, v in ipairs(outs) do
    for _, p in ipairs(v.pairs) do
      local key = v.gid .. "|" .. p.f .. "|" .. p.t
      owes[p.f] = true
      if not claimed[key] then ok(gone and gone[p.t], "the creditor's claim: " .. key) end
      if not claimed[key] and not clean[p.f] then
        for _, c in ipairs(final) do eq(Play.debt(c, v.gid, p.f, p.t), nil, c.env.me .. ": " .. key) end
        local o = not away[p.f] and owing(cl[p.f], key)
        if contest[p.f] then ok(not o, "not put to " .. p.f .. ": " .. key)
        elseif either[p.f] then eq(o and o.c or p.c, p.c)
        elseif not away[p.f] then ok(o, "put to " .. p.f .. ": " .. key); eq(o and o.c, p.c) end
        ok(not said[key], "no own D: " .. key)
      else
        n = n + 1
        local status
        for _, c in ipairs(final) do
          local d = Play.debt(c, v.gid, p.f, p.t)
          ok(d, c.env.me .. " holds " .. key)
          eq(d and d.c, p.c, c.env.me)
          status = status or (d and d.status)
          if d and either[p.f] and not clean[p.f] then
            ok(d.status == "contested" or d.status == "pending", c.env.me .. ": " .. key .. " is " .. d.status)
            eq(d.status, status, c.env.me .. ": " .. key)
          elseif d then
            eq(d.status, clean[p.f] and "confirmed" or contest[p.f] and "contested" or "pending", c.env.me .. ": " .. key)
          end
        end
        if clean[p.f] then ok(said[key], "the debtor's own D: " .. key) else
          if not away[p.f] then eq(asked(cl[p.f], key), status == "pending", "put to " .. p.f .. ": " .. key) end
          ok(not said[key], "no own D: " .. key)
        end
      end
    end
    total = total + (v.chips - v.bought)
  end
  for _, c in ipairs(final) do eq(#View.of(c.ledger).debts, n, c.env.me) end
  eq(total, 0) -- no chip came from nowhere
  table.sort(outs, function(x, y) if q(x.gid) ~= q(y.gid) then return q(x.gid) < q(y.gid) end return x.seat < y.seat end)
  local last = {}
  for _, v in ipairs(outs) do
    local from, sum = last[v.name] or 0, 0
    for _, o in ipairs(outs) do
      if q(o.gid) > from and q(o.gid) <= q(v.gid) then
        for _, p in ipairs(o.pairs) do
          if p.t == v.name then sum = sum + p.c elseif p.f == v.name then sum = sum - p.c end
        end
      end
    end
    eq(sum, (v.chips - v.bought) * ns.HoldemCash.CHIP, v.name .. " at " .. v.gid)
    last[v.name] = q(v.gid)
  end
  eq(#Play.entries(sim, nil, "C"), 0); eq(#Play.entries(sim, nil, "R"), 0); eq(forfeits, 0)
  local S = Play.entries(sim, nil, "S")
  eq(#S, #outs)
  for _, v in ipairs(outs) do
    local hit
    for _, e in ipairs(S) do if e.gid == v.gid and e.f == v.name then hit = e end end
    ok(hit, "the S of " .. v.name .. " at " .. v.gid)
    if hit then
      eq({ hit.c, hit.n[v.seat], hit.why }, { v.bought * ns.HoldemCash.CHIP, v.name, v.why })
      for _, list in ipairs({ hit.w, hit.l }) do
        for _, x in ipairs(list) do ok(x >= 1 and x <= #hit.n and type(hit.n[x]) == "string", "a seat of the S: " .. x) end
      end
    end
  end
  return owes
end

-- Every evening runs under each of these bot seeds (F3-F C1: seed 7 alone hid the false "forged"
-- of a handover after a hand with unshown cards).
local SEEDS = { 3, 4, 6, 7, 13 }

describe("a staked Холдем evening", function()
  -- Kiro's hands in the book of client: how many stay open there.
  local function kiros(client)
    local book, n = client.session.book, 0
    for _, x in ipairs(book.open) do if book.rec[x] ~= nil and book.rec[x].who[5] == K then n = n + 1 end end
    return n
  end
  -- What the seeds show together (asserted once, by the last test below: no single seed has to
  -- bust a seat twice, make a side pot, or make Мария a debtor).
  local COVER = { allin = 0, side = 0, rebuys = 0, again = 0, owesM = 0, owesN = 0, clean = {}, rebought = {} }
  local function shape(stats, outs)
    COVER.allin, COVER.side = math.max(COVER.allin, stats.allin), math.max(COVER.side, stats.side)
    COVER.rebuys, COVER.again = math.max(COVER.rebuys, stats.rebuys), COVER.again + (stats.again and 1 or 0)
    local why = {}
    for _, v in ipairs(outs) do why[v.name .. "/" .. tostring(v.why)] = true end
    for _, k in ipairs({ G .. "/nil", K .. "/offline", A .. "/nil", B .. "/close", M .. "/close", N6 .. "/close" }) do
      ok(why[k], "an out record " .. k)
    end
  end

  for _, seed in ipairs(SEEDS) do
    -- Kiro is stood up offline, so his key does not come out at the close: every hand he was dealt
    -- into stays open, and every note at or after such a hand of a player dealt into it reads unseen.
    -- He comes back after the close: his client publishes the key it kept, the books take it, and the
    -- waiting notes are judged on it as at the close: the clean debtors confirm by their own D.
    it("an evening at a cash table [seed " .. seed .. "]", function()
      local sim, cl, outs, stats, h, forfeits = evening("bust", true, { seed = seed })
      shape(stats, outs)
      local owes = checked(sim, cl, outs, h, forfeits, { [B] = true, [N6] = true }, { [K] = true })
      COVER.owesM, COVER.owesN = COVER.owesM + (owes[M] and 1 or 0), COVER.owesN + (owes[N6] and 1 or 0)
      for _, name in ipairs({ B, N6 }) do
        eq(kiros(cl[name]), 0, name .. ": Kiro's hands are checked")
        eq(cl[name].session.book.seen.bad, 0, name)
      end
      local db, late = sim.envs[K].db, {}
      eq(db.bookSpent[#db.bookSpent].key, db.bookKeep.key) -- spent: it never deals again
      for _, m in ipairs(sim.sent) do if m.msg.t == "KEY" then late[#late + 1] = { m.from, m.channel, m.msg.m } end end
      eq(late, { { K, "GUILD", db.bookKeep.key } }) -- once; Мария, who reloaded seated, sent hers by the close
    end)

    -- He never comes back (E9: as E6): he played from the first hand, so no debtor's client confirms
    -- anything: every debt of the evening is put to its debtor.
    it("an evening at a cash table where the player stood up offline never comes back [seed " .. seed .. "]", function()
      local sim, cl, outs, stats, h, forfeits = evening("bust", true, { never = true, seed = seed })
      shape(stats, outs)
      checked(sim, cl, outs, h, forfeits, {}, { [K] = true }, { away = { [K] = true } })
      for _, name in ipairs({ B, N6 }) do ok(kiros(cl[name]) > 0, name .. ": a hand of Kiro's stays open") end
    end)

    -- A late key is committed: one that gives none of his commits is no gap but a lie. His hands are
    -- bad, and every debtor whose final book holds one it was dealt into contests; the others keep
    -- their questions (Гошо and Иван left before the close). Петър and Нади were dealt into the first
    -- hand with him; Мария's book begins at her reload, so each debt of hers is contested or still a
    -- question by whether she shared a hand with him after it (the seed's).
    it("a forged late key: Kiro's hands are bad and the debts of those at the close are contested [seed " .. seed .. "]", function()
      local sim, cl, outs, stats, h, forfeits = evening("bust", true, { key = string.rep("ab", C.SEED_BYTES), seed = seed })
      shape(stats, outs)
      checked(sim, cl, outs, h, forfeits, {}, { [K] = true }, { contest = { [B] = true, [N6] = true }, either = { [M] = true } })
      for _, name in ipairs({ B, N6 }) do
        eq(kiros(cl[name]), 0, name)
        ok(cl[name].session.book.seen.bad > 0, name .. ": bad hands")
      end
    end)

    -- Нади answers every question of the evening before Kiro is back (no to each): her word stands,
    -- the late key changes none of her notes; Петър, who answered nothing, is judged on it (clean).
    it("a late key after a question was answered changes nothing of that note [seed " .. seed .. "]", function()
      local answered = 0
      local sim, cl, outs, stats, h, forfeits = evening("bust", true, { before = function(sim, cl)
        sim:run(C.STAKE_OWE_WAIT + 5)
        for _, d in ipairs(cl[N6].stakes:asks()) do answered = answered + 1; ok(cl[N6].stakes:answer(d.key, false)) end
        for _, o in ipairs(cl[N6].stakes:owing()) do answered = answered + 1; ok(cl[N6].stakes:admit(o.key, false)) end
        sim:run(5)
      end, seed = seed })
      shape(stats, outs)
      ok(answered > 0, "Нади was asked")
      checked(sim, cl, outs, h, forfeits, { [B] = true }, { [K] = true }, { contest = { [N6] = true } })
    end)

    for _, mode in ipairs({ "bust", "top", "none" }) do
      it("an evening where every key comes out: the clean debtors confirm by their own D (" .. mode .. ") [seed " .. seed .. "]", function()
        local sim, cl, outs, stats, h, forfeits = evening(mode, false, { seed = seed })
        COVER.rebought[mode] = math.max(COVER.rebought[mode] or 0, stats.rebuys)
        COVER.allin = math.max(COVER.allin, stats.allin)
        local owes = checked(sim, cl, outs, h, forfeits, { [B] = true, [N6] = true, [K] = true })
        for name in pairs(owes) do if name == B or name == N6 or name == K then COVER.clean[mode] = true end end
      end)
    end
  end

  it("the seeds together: all-ins, a side pot, rebuys, a seat that bought again, clean debtors in every mode", function()
    ok(COVER.allin >= 3 and COVER.side >= 1, "all-ins " .. COVER.allin .. ", side pots " .. COVER.side)
    ok(COVER.rebuys >= 2 and COVER.again >= 1, "rebuys " .. COVER.rebuys .. ", a seat to buy again " .. COVER.again)
    ok(COVER.owesM >= 1 and COVER.owesN >= 1, "Мария and Нади owe in an evening")
    for _, mode in ipairs({ "bust", "top", "none" }) do ok(COVER.clean[mode], "a clean debtor owes (" .. mode .. ")") end
    ok(COVER.rebought.bust >= 1 and COVER.rebought.top >= 1, "rebuys where the mode lets a seat")
  end)
end)

-- A client of the F2 version ------------------------------------------------------------

describe("a client of the F2 version in the guild", function()
  it("a client of the F2 version in the guild keeps cash debts pending and the sync settles", function()
    BOT = lcg(3)
    local sim, cl = Play.cash(3)
    -- Д, a bystander of the F2 version: its take refuses an S and a D that says cash, as F2's Ledger.valid does.
    local D = "Дара Маринова"
    local d = sim:add(D); sim:run(1); sim:settle()
    local take = d.ledgerNet.take
    d.ledgerNet.take = function(self, e, from, live)
      if type(e) == "table" and (e.k == "S" or (e.k == "D" and e.why == "cash")) then
        local author, n = Ledger.author(e.i)
        if author then return self:refuse(e, author, n) end
      end
      return take(self, e, from, live)
    end
    local outs = {}
    for _, c in pairs(cl) do hosted(outs, c) end
    -- A short evening: hands until Мария has a pair, her „Стани“ (a cashout, then the stand), the close.
    local st
    for _ = 1, 30 do
      hands(sim, 1, { allin = 0, side = 0, rebuys = 0, seen = {} })
      st = host(sim).session.state
      local paired = false
      for j = 1, 3 do if j ~= 3 and ns.HoldemCash.net(st.cash, 3, j) ~= 0 then paired = true end end
      if paired then break end
    end
    between(sim)
    cl[M]:stand(); sim:run(3)
    eq(cl[M].session, nil)
    hands(sim, 2, { allin = 0, side = 0, rebuys = 0, seen = {} })
    assert(ns.Cash.close(cl[A])); sim:run(1)
    between(sim)
    sim:run(C.BOOK_WAIT + C.STAKE_OWE_WAIT + 10)
    local cashD, S, n = 0, 0, 0
    for _, e in ipairs(entries(sim)) do
      if e.k == "S" then S = S + 1 end
      if e.k == "D" and e.why == "cash" then
        cashD = cashD + 1
        eq((d.ledger:get(e.i)), nil); eq(d.ledger:refused(Ledger.author(e.i), select(2, Ledger.author(e.i)), Ledger.hash(e)), true)
      end
      if e.k == "S" then eq((d.ledger:get(e.i)), nil); eq(d.ledger:refused(Ledger.author(e.i), select(2, Ledger.author(e.i)), Ledger.hash(e)), true) end
    end
    ok(S >= 2 and cashD >= 1, "S " .. S .. ", the debtors' own D " .. cashD)
    -- Every cash debt the others confirmed is pending on Д, in no balance.
    for _, v in ipairs(outs) do
      for _, p in ipairs(v.pairs) do
        n = n + 1
        eq(Play.debt(cl[A], v.gid, p.f, p.t).status, p.f == M and "pending" or "confirmed", p.f .. "|" .. p.t)
        local x = Play.debt(d, v.gid, p.f, p.t)
        ok(x, "Д holds the claim"); eq(x and x.status, "pending")
      end
    end
    ok(n > 0, "the evening made debts")
    for _, a in ipairs({ A, B, M }) do
      for _, b in ipairs({ A, B, M }) do eq(View.net(View.of(d.ledger), a, b), 0, a .. "|" .. b) end
    end
    -- A new member logs in: at most two exchanges with Д, then nothing more between them.
    local E2 = "Яна Нова"
    local e = sim:add(E2)
    local mark = #sim.sent
    sim:run(1500)
    local function among(s) return (s.from == D and s.target == E2) or (s.from == E2 and s.target == D) end
    local exchanges, last = 0, 0
    for i = mark + 1, #sim.sent do
      local s = sim.sent[i]
      if among(s) and s.msg.t == "LVC" and not s.msg.r then exchanges = exchanges + 1 end
      if among(s) and (s.msg.t == "LVC" or s.msg.t == "LID" or s.msg.t == "LEV") then last = s.at end
    end
    ok(exchanges <= 2, "exchanges between Д and the new member: " .. exchanges)
    ok(last < sim.clock - 2 * C.LEDGER_PEER_GAP, "a sync message between them at " .. last)
    -- The refused entries count as held in Д's digest: the guild's digests agree, no exchange is due.
    for _, c in ipairs({ e, d, cl[B], cl[M] }) do eq(c.ledger:digest(), cl[A].ledger:digest(), c.env.me) end
    for _, v in ipairs(outs) do
      for _, p in ipairs(v.pairs) do eq(Play.debt(e, v.gid, p.f, p.t).status, Play.debt(cl[A], v.gid, p.f, p.t).status) end
    end
    -- Д never relayed an S or a cash D.
    for _, s in ipairs(sim.sent) do
      if s.from == D and s.msg.t == "LEV" then
        for _, x in ipairs(s.msg.ev or {}) do ok(x.k ~= "S" and x.why ~= "cash", "Д relayed " .. x.i) end
      end
    end
  end)
end)

-- The message budget ---------------------------------------------------------------------

-- Counts what the host whispered since `mark` and the dealer's private whispers (PRV), with the
-- real wire format (as tests/core/holdem_table_test.lua does, where the host deals): whispers,
-- bytes (packed + 40 of ChatThrottleLib), the biggest, the events W got, the whispers by type.
local function cost(sim, from, W, mark)
  local n, bytes, biggest, events, byType = 0, 0, 0, 0, {}
  for i = mark + 1, #sim.sent do
    local m = sim.sent[i]
    if m.channel == "WHISPER" and (m.from == from or m.msg.t == "PRV") then
      local size = #wire:pack(m.msg) + 40
      n, bytes, biggest = n + 1, bytes + size, math.max(biggest, size)
      byType[m.msg.t] = (byType[m.msg.t] or 0) + 1
      if m.msg.t == "EV" and m.target == W then events = events + 1 end
    end
  end
  return n, bytes, biggest, events, byType
end

-- A staked six-seat table (Play.cash) and a watcher; the hand that runs played out, then the
-- next one begins -> sim, cl, the watcher's name, the mark before the hand event.
local function watched()
  local sim, cl, tid = Play.cash(6)
  local W = "Гледач Гледачев"
  local w = sim:add(W); sim:run(1)
  local refused = {}
  w:on("refused", function(_, why) refused[#refused + 1] = why end)
  w:watch(tid); sim:run(1)
  eq({ cl[A].session.watchers, refused }, { 1, {} })
  between(sim)
  for _ = 1, 30 do
    if host(sim).session.state.phase == "done" and not E.inHand(host(sim).session.state) then break end
    sim:run(1)
  end
  local mark = #sim.sent
  for _ = 1, 30 do if E.inHand(host(sim).session.state) then break end; sim:run(1) end
  ok(E.inHand(host(sim).session.state), "a hand runs")
  return sim, cl, W, mark
end

-- The seat on turn: `k` from its own client.
local function act(sim, k)
  local s = host(sim).session
  local seat = s.state.turn
  ok(sim.clients[s.seats[seat]]:act{ k = k }, "seat " .. seat .. " " .. k); sim:run(1)
end

-- Every seat on turn calls or checks until the hand is over.
local function down(sim)
  for _ = 1, 300 do
    local st = host(sim).session.state
    if not E.inHand(st) then return end
    local t = st.phase == "bet" and st.turn
    if t then act(sim, st.bet > st.p[t].bet and "call" or "check") else sim:run(1) end
  end
  error("the hand did not end")
end

describe("staked Холдем: what a full table costs", function()
  -- Measured at the first green run (pinned at the top of the range + 5 %): the ordinary hand (three
  -- fold before the flop, three check it down) 23 events to 6 (5 members, the watcher), the dealer's
  -- 5 PRV and the host's SED to the dealer, 22 886-23 285 B (the fun pin: 22 000-22 500, at most
  -- 23 500 B, where the host deals); the full ring 32 events, 30 438-31 080 B; the snapshot of a
  -- staked game at six seats 1 129-1 140 B packed. TCK: at most one heartbeat round in a hand.
  it("the message budget of a staked hand", function()
    local sim, _, W, mark = watched()
    for _ = 1, 3 do act(sim, "fold") end
    down(sim)
    local n, bytes, _, events, byType = cost(sim, A, W, mark)
    local tck = byType.TCK or 0; byType.TCK = nil
    eq({ events, byType }, { 23, { EV = 138, PRV = 5, SED = 1 } })
    ok(tck <= 6, "TCK " .. tck); eq(n, 144 + tck)
    ok(bytes <= 24450, "the ordinary staked hand: bytes " .. bytes)
    ok(bytes <= 23500 * 1.1, "more than 10 % above the fun pin: " .. bytes)
    -- the full ring: nobody folds, six hands shown
    local mark2 = #sim.sent
    for _ = 1, 30 do if E.inHand(host(sim).session.state) then break end; sim:run(1) end
    down(sim)
    eq(#host(sim).session.state.last.shown, 6)
    local n2, bytes2, biggest2, events2, byType2 = cost(sim, A, W, mark2)
    local tck2 = byType2.TCK or 0; byType2.TCK = nil
    eq({ events2, byType2 }, { 32, { EV = 192, PRV = 5, SED = 1 } })
    ok(tck2 <= 6, "TCK " .. tck2); eq(n2, 198 + tck2)
    ok(bytes2 <= 32650, "the full ring: bytes " .. bytes2)
    ok(biggest2 - 40 <= 2 * 255, "one event is more than two addon message parts: " .. biggest2)
    -- the snapshot of a staked game at six seats, the matrix and the buy-ins in it
    local smark = #sim.sent
    host(sim).session:snapshotTo(B); sim:run(1)
    local snp
    for i = smark + 1, #sim.sent do if sim.sent[i].msg.t == "SNP" and sim.sent[i].target == B then snp = sim.sent[i].msg end end
    ok(snp and snp.st.cash, "a staked snapshot")
    local size = #wire:pack(snp)
    ok(size <= 1200, "the staked snapshot: " .. size)
  end)

  -- H17. Measured at the first green run (pinned + 5 %): six S, 15 creditor D, 15 debtor D; the host
  -- 4 GUILD messages in 6 parts (its six S and its claims), every other client 3 in 3-4 parts; 19
  -- messages and 22 parts in all; no client above 10 parts in any 10 s (Net:afford).
  it("the six-seat close costs", function()
    local sim, cl = Play.cash(6)
    hands(sim, 2, { allin = 0, side = 0, rebuys = 0, seen = {} })
    between(sim)
    -- every pair of the six owes: seat i took 10 x j chips from every seat j > i
    local took = {}
    for i = 1, 6 do took[i] = {}; for j = i + 1, 6 do took[i][j] = 10 * j end end
    for _, c in pairs(cl) do
      local st = c.session and c.session.state
      if st and st.cash then st.cash.took = U.copy(took) end
    end
    local outs = {}
    for _, c in pairs(cl) do hosted(outs, c) end
    local mark = #sim.sent
    assert(ns.Cash.close(cl[A])); sim:run(1)
    between(sim)
    sim:run(C.BOOK_WAIT + C.STAKE_OWE_WAIT + 30)
    local S, claims, own, per, parts, windows = 0, 0, 0, {}, {}, {}
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      if m.channel == "GUILD" and (m.msg.t == "LEV" or m.msg.t == "HI") then
        local p = math.ceil(ns.LedgerNet.size(m.msg) / 255)
        per[m.from], parts[m.from] = (per[m.from] or 0) + 1, (parts[m.from] or 0) + p
        windows[m.from] = windows[m.from] or {}
        table.insert(windows[m.from], { at = m.at, p = p })
        for _, e in ipairs(m.msg.ev or {}) do
          if e.k == "S" then S = S + 1 end
          if e.k == "D" and e.why == "lost" then claims = claims + 1 end
          if e.k == "D" and e.why == "cash" then own = own + 1 end
        end
      end
    end
    eq({ S, claims, own }, { 6, 15, 15 })
    local msgs, all = 0, 0
    for _, name in ipairs(ALL) do
      local m, p = per[name] or 0, parts[name] or 0
      msgs, all = msgs + m, all + p
      local cap = name == A and { 4, 6 } or { 3, 4 }
      ok(m <= cap[1] and p <= cap[2], name .. ": " .. m .. " GUILD messages, " .. p .. " parts")
      local list = windows[name] or {}
      for _, x in ipairs(list) do
        local used = 0
        for _, y in ipairs(list) do if y.at <= x.at and x.at - y.at < 10 then used = used + y.p end end
        ok(used <= 10, name .. ": parts within 10 s " .. used)
      end
    end
    ok(msgs <= 19 and all <= 23, "the close: " .. msgs .. " GUILD messages, " .. all .. " parts")
    for _, name in ipairs(ALL) do
      for _, v in ipairs(outs) do
        for _, p in ipairs(v.pairs) do eq(Play.debt(cl[name], v.gid, p.f, p.t).status, "confirmed", name) end
      end
    end
  end)
end)

-- Bots -----------------------------------------------------------------------------------

describe("bots and a staked Холдем", function()
  it("a bot declines a staked Холдем invitation and fills no staked table", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" })
    local bots = ns.Bots.enable(a, envA, sim.makeEnv); sim:run(1)
    local answers = {}
    a:on("inviteAnswer", function(...) answers[#answers + 1] = { ... } end)
    local SK = E.stakeOf({ blinds = 10 })
    ok(a:openTable{ game = "holdem", access = "invite", turn = 30, opt = { blinds = 10 }, stake = SK }); sim:run(1)
    local bot = bots.list[1].env.me
    ok(a:invite(bot)); sim:run(5)
    eq(answers, { { bot, "auto", "busy" } }); eq(a.session.seats[2], false)
    eq(bots.list[1].session, nil)
    eq(bots:fill(), nil); sim:run(10)
    eq(a.session.seats, { A, false, false, false, false, false }); eq(#answers, 1)
    a:stand(); sim:run(3)
    -- A bot hosting a staked Холдем (past its client's own refusal: a bot has no ledger) fills nobody in.
    local host = bots.list[2]
    eq({ host:openTable{ game = "holdem", access = "guild", turn = 30, opt = { blinds = 10 }, stake = SK } }, { nil, "stake" })
    local tid = ns.Session.open(host, { game = "holdem", access = "guild", turn = 30, opt = { blinds = 10 }, stake = SK }); sim:run(1)
    ok(tid, "opened past the check")
    eq(bots:fill(), nil)
    a:sit(tid, 2, SK); sim:run(10)
    eq(next(host.invites.sent), nil)
    for i = 3, 6 do eq(host.session.seats[i], false, "seat " .. i) end
  end)
end)

-- A fun-only evening (H9) -----------------------------------------------------------------

local FUN = { "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров" }
local CLS = { "MAGE", "PRIEST", "ROGUE", "DRUID" }

local function ser(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y)
    if type(x) ~= type(y) then return type(x) < type(y) end
    return x < y
  end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = (type(k) == "string" and k or "[" .. tostring(k) .. "]") .. "=" .. ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

-- A whole fun match of `game` (n seats; every client draws from lcg(seed)): FUN[1] hosts,
-- FUN[2..n] sit; the seat on turn moves from its own client (engine.bot, else its automatic
-- move) once a second. Холдем (H9: no start by the seats, no end by play): the host starts,
-- FUN_HANDS hands are played, the host's „Приключи“, the hand played out, then BOOK_WAIT + 10 s;
-- any other game until the match is over, then 40 s. -> the message log, a line per message.
local FUN_HANDS = 10
local function funLog(game, n, seed)
  local sim = Sim.new()
  local rnd, cl = lcg(seed), {}
  for i = 1, n do cl[i] = sim:add(FUN[i], { cls = CLS[i] }); cl[i].env.random = rnd end
  sim:run(1)
  local host = cl[1]
  local tid = host:openTable{ game = game, access = "guild", turn = 45 }; sim:run(3)
  for i = 2, n do cl[i]:sit(tid, i); sim:run(1) end
  local steps = 0
  local function move()
    steps = steps + 1
    assert(steps < 6000, "the match did not end")
    local s = host.session
    local seat = s.status == "live" and s.state and s.state.turn
    local c = seat and sim.clients[s.seats[seat]]
    if c and c.session and c.session.state then
      local E, a = c.session:engine(), nil
      if E.bot then a = E.bot(c.session.state, seat, rnd) end
      if a then c:act(a) else c:playAuto() end
    end
    sim:run(1)
  end
  if game == "holdem" then
    local E = ns.Engines.holdem
    assert(host:startGame()); sim:run(1)
    for _ = 1, FUN_HANDS do
      while not E.inHand(host.session.state) do move() end
      local hand = host.session.state.hand
      while E.inHand(host.session.state) and host.session.state.hand == hand do move() end
    end
    assert(ns.Cash.close(host)); sim:run(1)
    while E.inHand(host.session.state) do move() end
    sim:run(C.BOOK_WAIT + 10)
  else
    while not host.session:gameOver() do move() end
    sim:run(40)
  end
  local out = {}
  for _, s in ipairs(sim.sent) do
    out[#out + 1] = s.at .. " " .. s.from .. " " .. s.channel .. " " .. tostring(s.target) .. " " .. ser(s.msg)
  end
  return out
end

-- The log in chunks of 100 lines -> the line count, the first 16 hex of SHA-256 of each chunk (its lines joined by "\n").
-- The reference was recorded at version 0.1.0: the addon's own version in a log line (its HI's
-- ver=) reads as that one again, so a version bump alone never breaks the byte-identical check.
local REF_VERSION = "0.1.0"
local function asRecorded(line)
  local own = 'ver="' .. tostring(ns.Const.VERSION) .. '"'
  local i, j = line:find(own, 1, true)
  if not i then return line end
  return line:sub(1, i - 1) .. 'ver="' .. REF_VERSION .. '"' .. line:sub(j + 1)
end

local function chunks(log)
  local norm = {}
  for i, line in ipairs(log) do norm[i] = asRecorded(line) end
  log = norm
  local out = {}
  for from = 1, #log, 100 do
    out[#out + 1] = ns.Sha256.hex(table.concat(log, "\n", from, math.min(from + 99, #log))):sub(1, 16)
  end
  return #log, table.concat(out, " ")
end

-- funLog("holdem", 3, 1) through chunks() on the build of e62ddc6 (before stage F3): generated
-- once, by the same functions, from a worktree of that commit.
local FUN_E62DDC6 = { 589,
  "a91ffe1187769ecf 71e8bd92bd449c35 f4bfdee819869910 356557f48a925e6d 8a4c9e9eaaab1acd b299a35c4c11496f" }

describe("stakes F3: a fun Холдем is untouched", function()
  it("a fun-only Холдем evening is byte-identical", function()
    local log = funLog("holdem", 3, 1)
    local lines, sums = chunks(log)
    eq(lines, FUN_E62DDC6[1])
    local got, want = {}, {}
    for h in sums:gmatch("%S+") do got[#got + 1] = h end
    for h in FUN_E62DDC6[2]:gmatch("%S+") do want[#want + 1] = h end
    for i = 1, math.max(#got, #want) do
      if got[i] ~= want[i] then
        eq(got[i], want[i], "lines " .. (100 * i - 99) .. "-" .. (100 * i) .. ", from: " .. tostring(log[100 * i - 99]))
        break
      end
    end
    eq(got, want)
    -- the evening is what it says: ten hands dealt, the close, every key out
    local dealt, keys = 0, 0
    for _, l in ipairs(log) do
      if l:find('k="hand"', 1, true) and l:find(FUN[2], 1, true) then dealt = dealt + 1 end
      if l:find('op="keys"', 1, true) and l:find("f=true", 1, true) then keys = keys + 1 end
    end
    eq(dealt, FUN_HANDS); ok(keys >= 1, "the final keys")
  end)
end)

ns.LedgerNet.size = stand
