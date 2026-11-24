local Sim = require("sim")
local ns = Sim.ns
local Bots, E = ns.Bots, ns.Engines and ns.Engines.ttt

local A = "Иван Петров"
local STARTERS = { "Бот Иванов", "Bot Barleybrew", "Бот Петрова" }

local function seated(seats, name)
  for i = 1, #seats do
    if seats[i] == name then return true end
  end
  return false
end

local B = "Мария Стоянова"

-- Does any string anywhere in `msg` equal one of `words`?
local function mentions(msg, words)
  if type(msg) == "string" then
    for i = 1, #words do
      if msg == words[i] then return true end
    end
    return false
  end
  if type(msg) ~= "table" then return false end
  for k, v in pairs(msg) do
    if mentions(k, words) or mentions(v, words) then return true end
  end
  return false
end

describe("bots", function()
  it("one human plays a whole match against a bot without touching the guild channel", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" }); local bots = Bots.enable(a, envA, sim.makeEnv)
    sim:run(1) -- let the bots' HI reach a's Presence before inviting
    local tid = a:openTable{ game = "ttt", access = "invite", turn = 45 }; ok(a:invite("Бот Иванов")); sim:run(5)
    eq(a.session.seats[2], "Бот Иванов")
    for _ = 1, 400 do
      local s = a.session
      if s.state and s.state.phase == "match" then break end
      if s.state and s.state.phase == "play" and s.state.turn == 1 then a:act(E.auto(s.state, 1)) end
      sim:run(1)
    end
    eq(a.session.state.phase, "match")
    eq(sim:count(function(m) return m.channel == "GUILD" and m.from ~= A end), 0)
    eq(sim:count(function(m) return m.channel == "GUILD" and m.msg.tid == tid
      and m.msg.s and (m.msg.s[1] == "Бот Иванов" or m.msg.s[2] == "Бот Иванов") end), 0)
    eq(sim:count(function(m) return m.channel == "WHISPER" and m.target == "Бот Иванов" end), 0)
    ok(#bots.list == 3)
  end)

  it("a bot can host and invite me", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" }); local bots = Bots.enable(a, envA, sim.makeEnv)
    sim:run(1)
    local got
    a:on("invite", function(inv) got = inv end)
    local tid = bots:inviteMe(); sim:run(2)
    ok(got, "no invite event")
    ok(seated(STARTERS, got.host), "host is not a bot: " .. tostring(got.host))
    eq(got.tid, tid); eq(got.game, "ttt")
    eq(a.lobby:get(tid).access, "invite")
    a:answerInvite(tid, "yes"); sim:run(3)
    eq(a.session.tid, tid); eq(a.session.mySeat, 2)
    eq(sim:count(function(m) return m.channel == "GUILD" and m.msg.tid == tid end), 0)
    eq(sim:count(function(m) return m.channel == "GUILD" and m.msg.t == "HI" and m.msg.at == tid end), 0)
  end)

  it("hostTable spawns extra bots up to 12", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" }); local bots = Bots.enable(a, envA, sim.makeEnv)
    for _ = 1, 9 do ok(bots:hostTable()) end
    sim:run(3)
    eq(#a.lobby:tables(), 9); eq(#bots.list, 9)
    ok(a.presence:get("Бот Номер9"), "spawned bot unknown")
    for _ = 10, 12 do ok(bots:hostTable()) end
    eq(bots:hostTable(), nil); eq(#bots.list, 12)
    sim:run(3)
    eq(#a.lobby:tables(), 12)
    eq(sim:count(function(m) return m.channel == "GUILD" and m.msg.t == "TBL" end), 0)
  end)

  it("disable restores env.send and removes the bots from presence", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" })
    local orig = envA.send
    local bots = Bots.enable(a, envA, sim.makeEnv)
    bots:hostTable()
    sim:run(1)
    ok(envA.send ~= orig); ok(a.presence:get("Бот Иванов") ~= nil)
    eq(#a.lobby:tables(), 1)
    Bots.disable(bots); sim:run(1)
    ok(envA.send == orig)
    for _, n in ipairs(STARTERS) do eq(a.presence:get(n), nil, n) end
    eq(#a.lobby:tables(), 0)
  end)

  it("a real player who comes online hears nothing of my bot table", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" }); Bots.enable(a, envA, sim.makeEnv)
    sim:run(1)
    local tid = a:openTable{ game = "ttt", access = "invite", turn = 45 }; sim:run(1)
    ok(a:invite("Бот Иванов")); sim:run(3)
    eq(a.session.seats, { A, "Бот Иванов" })
    local mark = #sim.sent
    local b = sim:add(B, { cls = "ROGUE" }); sim:run(3)
    local words = { tid, STARTERS[1], STARTERS[2], STARTERS[3] }
    local toB = 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      if m.from == A then
        ok(not mentions(m.msg, words), "leak in " .. tostring(m.msg.t) .. " to " .. tostring(m.target))
        if m.target == B then toB = toB + 1 end
      end
    end
    ok(toB > 0, "A never answered B") -- the HI reply went out, without `at`
    eq(b.lobby:get(tid), nil); eq(b.presence:get(A).at, nil)
  end)

  it("a table announced for real gets one real END when it becomes a bot table", function()
    local sim = Sim.new()
    local b = sim:add(B, { cls = "ROGUE" })
    local a, envA = sim:add(A, { cls = "MAGE" }); Bots.enable(a, envA, sim.makeEnv)
    sim:run(1)
    local tid = a:openTable{ game = "ttt", access = "invite", turn = 45 }; sim:run(1)
    ok(b.lobby:get(tid), "B never saw the table"); eq(b.presence:get(A).at, tid)
    local mark = #sim.sent
    ok(a:invite("Бот Иванов")); sim:run(1)
    eq(b.lobby:get(tid), nil); eq(b.presence:get(A).at, nil)
    sim:run(20)
    local ends, leaks = 0, 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      if m.msg.t == "END" and m.msg.tid == tid then ends = ends + 1
      elseif mentions(m.msg, { tid }) then leaks = leaks + 1 end
    end
    eq(ends, 1); eq(leaks, 0)
    eq(a.session.seats[2], "Бот Иванов")
  end)

  it("disable while seated at a bot table leaves it without a word on the guild channel", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" }); local bots = Bots.enable(a, envA, sim.makeEnv)
    local tid = a:openTable{ game = "ttt", access = "invite", turn = 45 }; sim:run(1)
    ok(a:invite("Бот Петрова")); sim:run(3)
    eq(a.session.seats[2], "Бот Петрова")
    local mark = #sim.sent
    Bots.disable(bots); sim:run(2)
    eq(a.session, nil); eq(a.lobby:get(tid), nil)
    local guild = 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      if m.channel == "GUILD" and m.msg.tid == tid then guild = guild + 1 end
    end
    eq(guild, 0)
  end)
end)

describe("bots for any game", function()
  local function setup()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" }); local bots = Bots.enable(a, envA, sim.makeEnv); sim:run(1)
    return sim, a, envA, bots
  end

  it("one human plays Death Roll against two bots: real rolls for me, table rolls for them, nobody invited", function()
    local sim, a = setup()
    local tid = a:openTable{ game = "deathroll", access = "invite", turn = 45, opt = { start = 100 } }; ok(tid)
    ok(a:invite("Бот Иванов")); ok(a:invite("Bot Barleybrew"))
    local mark = #sim.sent -- the real TBL and its END (once a bot was invited) are out
    sim:run(5); eq(a.session:seatedCount(), 3)
    ok(a:startGame()); sim.nextRolls, sim.nextRandom = { 50, 20, 5, 1 }, { 40, 30, 15, 10, 4, 2 }
    for _ = 1, 200 do
      local st = a.session.state; if st.phase == "over" then break end
      if st.turn == 1 and not a.session.rolling then a:roll() end; sim:run(1)
    end
    local st = a.session.state; eq(st.phase, "over"); eq(st.rolls[#st.rolls].n, 1)
    for _, r in ipairs(st.rolls) do eq(r.src, r.seat == 1 and "seen" or "ask") end
    eq(sim.groupInvites, {}); eq(sim:count(function(m) return m.channel == "GUILD" and m.from ~= A end), 0)
    for _, r in ipairs(sim.rolled) do eq(r.from, A) end
    -- Nothing of the bot table (its SIT/ACT/EV/SNP/TBL, a HI placing me there,
    -- a bot's name) reached the real side after the bots were invited.
    local words, real = { tid, STARTERS[1], STARTERS[2], STARTERS[3] }, 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      ok(not mentions(m.msg, words), "leak in " .. tostring(m.msg.t) .. " on " .. m.channel)
      real = real + 1
    end
    ok(real > 0, "A sent nothing for real") -- its HIs went out, without `at`
  end)

  it("a bot hosts Death Roll, I sit, it starts by itself and sees my rolls", function()
    local sim, a, _, bots = setup()
    local tid = bots:hostTable("deathroll"); sim:run(3); a:sit(tid, 2); sim:run(4); eq(a.session.status, "live")
    for _ = 1, 30 do
      if a.session.state.turn == 2 then break end
      sim:run(1)
    end
    eq(a.session.state.turn, 2)
    sim.nextRolls = { 7 }; ok(a:roll()); sim:run(1)
    local rolls = a.session.state.rolls
    local r = rolls[#rolls]
    eq(r.seat, 2); eq(r.n, 7); eq(r.src, "seen")
  end)

  it("a bot host starts the next game when engine.over says so with any truthy value", function()
    require("pick_engine")
    local E = ns.Engines.pick
    E.over = function(st) return st.winner and "yes" or nil end
    local okRun, err = pcall(function()
      local sim, a, _, bots = setup()
      local tid = bots:hostTable("pick"); sim:run(3); a:sit(tid, 2); sim:run(4)
      eq(a.session.status, "live")
      local results = 0
      a:on("result", function() results = results + 1 end)
      for _ = 1, 30 do
        if results > 0 then break end
        if a.session.state.turn == 2 then a:playAuto() end
        sim:run(1)
      end
      eq(results, 1)
      sim:run(3)
      eq(a.session.state.winner, nil) -- the bot started the next game
    end)
    E.over = nil
    assert(okRun, err)
  end)

  it("one human plays a whole Сантасе match against a bot; every hand is checked; nothing leaves the machine", function()
    local sim, a = setup()
    local fair, results = {}, 0; a:on("fair", function(e) fair[#fair + 1] = e.verdict end); a:on("result", function() results = results + 1 end)
    local tid = a:openTable{ game = "santase", access = "invite", turn = 45 }; ok(tid); ok(a:invite("Бот Иванов"))
    local mark = #sim.sent -- the real TBL and its END (once the bot was invited) are out
    sim:run(5)
    eq(a.session.seats[2], "Бот Иванов"); eq({ a:startGame() }, { nil, "mode" })
    for _ = 1, 6000 do
      local st = a.session.state; if ns.Engines.santase.over(st) then break end
      if st.turn == 1 then a:playAuto() end; sim:run(1)
    end
    sim:run(1); eq(ns.Engines.santase.over(a.session.state), true); eq(results, 1); ok(#fair >= 4)
    for _, v in ipairs(fair) do eq(v, "ok") end
    eq(sim:count(function(m) return m.msg.t == "SED" or m.msg.t == "PRV" or m.msg.t == "PRQ" end), 0)
    eq(sim.groupInvites, {}); eq(sim.rolled, {})
    -- Nothing of the bot table (its seeds, faces, events, a bot's name) reached
    -- the real side after the bot was invited.
    local words, real = { tid, STARTERS[1], STARTERS[2], STARTERS[3] }, 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      ok(not mentions(m.msg, words), "leak in " .. tostring(m.msg.t) .. " on " .. m.channel)
      real = real + 1
    end
    ok(real > 0, "A sent nothing for real") -- its HIs went out, without `at`
    local loser = 3 - a.session.state.winner; ok(a:startGame()); sim:run(2); eq(a.session.state.gp, { 0, 0 }); eq(a.session.state.turn, loser)
  end)

  it("a bot hosting Сантасе starts the next match by itself", function()
    local sim, a, _, bots = setup()
    local tid = bots:hostTable("santase"); ok(tid); sim:run(3); a:sit(tid, 2); sim:run(4); eq(a.session.status, "live")
    local results = 0; a:on("result", function() results = results + 1 end)
    for _ = 1, 6000 do
      local st = a.session.state; if ns.Engines.santase.over(st) then break end
      if st.turn == 2 then a:playAuto() end; sim:run(1)
    end
    eq(ns.Engines.santase.over(a.session.state), true); eq(results, 1)
    sim:run(4); eq(a.session.state.gp, { 0, 0 }); eq(a.session.state.phase, "play")
  end)

  it("one human and three bots play a whole Белот match; every deal is checked; nothing leaves the machine", function()
    local sim, a = setup(); local E = ns.Engines.belot
    local fair, res = {}, {}; a:on("fair", function(e) fair[#fair + 1] = e.verdict end); a:on("result", function(r) res[#res + 1] = r end)
    local tid = a:openTable{ game = "belot", access = "invite", turn = 45 }; ok(tid)
    for _, name in ipairs(STARTERS) do ok(a:invite(name)) end
    local mark = #sim.sent; sim:run(5); eq(a.session:seatedCount(), 4); eq(a.session.status, "live")
    for _ = 1, 40000 do
      local st = a.session.state; if E.over(st) then break end
      if st.turn == 1 then a:playAuto() end; sim:run(1)                       -- I only ever pass and play my lowest card
    end
    sim:run(1); local st = a.session.state; eq(E.over(st), true); eq(#res, 1); ok(#fair >= 4)
    eq(res[1].winners, st.winner == 1 and { 1, 3 } or { 2, 4 }); eq(res[1].left, nil); ok(st.score[st.winner] >= 151)
    for _, v in ipairs(fair) do eq(v, "ok") end
    eq(sim:count(function(m) return m.msg.t == "SED" or m.msg.t == "PRV" or m.msg.t == "PRQ" end), 0)
    eq(sim.groupInvites, {}); eq(sim.rolled, {})
    -- Nothing of the bot table (its seeds, faces, events, a bot's name) reached
    -- the real side after the bots were invited.
    local words, real = { tid, STARTERS[1], STARTERS[2], STARTERS[3] }, 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      ok(not mentions(m.msg, words), "leak in " .. tostring(m.msg.t) .. " on " .. m.channel)
      real = real + 1
    end
    ok(real > 0, "A sent nothing for real") -- its HIs went out, without `at`
    local first = st.first; ok(a:startGame()); sim:run(4)
    eq({ a.session.state.score, a.session.state.phase, a.session.state.first }, { { 0, 0 }, "bid", first % 4 + 1 })
  end)

  it("a bot-hosted Белот table fills with bots once I sit, and the bot host starts the next match", function()
    local sim, a, _, bots = setup(); local E = ns.Engines.belot
    local tid = bots:hostTable("belot"); ok(tid); sim:run(3)
    local rec = a.lobby:get(tid); ok(rec, "the bot table is unknown"); eq(#rec.seats, 4)
    local taken = 0
    for i = 1, #rec.seats do if rec.seats[i] then taken = taken + 1 end end
    eq(taken, 1)
    a:sit(tid, 2); sim:run(8)
    local s = a.session; eq(s:seatedCount(), 4); eq(s.mySeat, 2); eq(s.status, "live")
    ok(bots.isBot[s.seats[1]]); ok(bots.isBot[s.seats[3]]); ok(bots.isBot[s.seats[4]])
    local results = 0; a:on("result", function() results = results + 1 end)
    for _ = 1, 40000 do
      local st = a.session.state; if E.over(st) then break end
      if st.turn == 2 then a:playAuto() end; sim:run(1)
    end
    eq(E.over(a.session.state), true); eq(results, 1)
    sim:run(6); eq(a.session.state.score, { 0, 0 }); eq(a.session.state.phase, "bid")
    -- A bot at seat 3 stands: the match ends, the table is aborted with three seated and fills again.
    local short = false
    a:on("session", function(cur)
      if cur and cur.status == "aborted" and cur:seatedCount() == 3 then short = true end
    end)
    local three = a.session.seats[3]
    for k = 1, #bots.list do
      if bots.list[k].env.me == three then bots.list[k]:stand() end
    end
    sim:run(8)
    ok(short, "the table was never aborted with three seated")
    eq(a.session:seatedCount(), 4); eq(a.session.status, "live")
    -- A bot table of Морски шах with me seated invites nobody.
    local sim2, a2, _, bots2 = setup()
    local invs = 0
    bots2.busSend = function(self, from, channel, target, msg)
      if msg.t == "INV" then invs = invs + 1 end
      return Bots.busSend(self, from, channel, target, msg)
    end
    local tid2 = bots2:hostTable("ttt"); ok(tid2); sim2:run(3); a2:sit(tid2, 2); sim2:run(8)
    eq(a2.session:seatedCount(), 2); eq(invs, 0)
    for k = 1, #bots2.list do eq(next(bots2.list[k].invites.sent), nil) end
  end)

  it("a bot table whose invitation was declined or never answered invites again", function()
    local sim, a, _, bots = setup()
    local tid = bots:hostTable("belot"); ok(tid); sim:run(3)
    -- The first invitation of the fill is declined, the second never arrives, the rest are taken.
    local invs = 0
    bots.busSend = function(self, from, channel, target, msg)
      if msg.t == "INV" then
        invs = invs + 1
        if invs == 2 then return end
      end
      return Bots.busSend(self, from, channel, target, msg)
    end
    local declined
    for k = 1, #bots.list do
      local bot = bots.list[k]
      bot:on("invite", function(inv)
        if not declined then declined = bot.env.me; bot:answerInvite(inv.tid, "no") end
      end)
    end
    a:sit(tid, 2); sim:run(4)
    ok(invs >= 2, "no second invitation after the first failed: " .. invs)
    sim:run(ns.Const.INVITE_SECONDS + ns.Const.INVITE_GRACE + 6)                                -- the lost one times out
    ok(invs >= 3, "no invitation after the timeout: " .. invs)
    eq(a.session:seatedCount(), 4); eq(a.session.status, "live")
  end)

  it("one human and a bot play a whole Табла match through all three variants; nothing leaves the machine", function()
    local sim, a = setup(); local E = ns.Engines.tabla
    local fair, res, vars = {}, {}, {}; a:on("fair", function(e) fair[#fair + 1] = e.verdict end); a:on("result", function(r) res[#res + 1] = r end)
    local tid = a:openTable{ game = "tabla", access = "invite", turn = 45 }; ok(tid); ok(a:invite("Бот Иванов"))
    local mark = #sim.sent; sim:run(5); eq(a.session:seatedCount(), 2); eq(a.session.status, "live")
    for _ = 1, 40000 do
      local st = a.session.state; if E.over(st) then break end
      vars[st.var] = true; if st.turn == 1 and st.phase == "move" then a:playAuto() end; sim:run(1)
    end
    sim:run(1); local st = a.session.state; eq(E.over(st), true); eq(#res, 1); eq(res[1].left, nil); ok(st.score[st.winner] >= 5)
    eq(vars, { std = true, tapa = true, gul = true }); ok(#fair >= 60); for _, v in ipairs(fair) do eq(v, "ok") end
    eq(sim.groupInvites, {}); eq(sim.rolled, {})
    -- Nothing of the bot table (its throws, events, a bot's name) reached the
    -- real side after the bot was invited.
    local words, real = { tid, STARTERS[1], STARTERS[2], STARTERS[3] }, 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      ok(not mentions(m.msg, words), "leak in " .. tostring(m.msg.t) .. " on " .. m.channel)
      real = real + 1
    end
    ok(real > 0, "A sent nothing for real") -- its HIs went out, without `at`
    ok(a:startGame()); sim:run(4); eq({ a.session.state.score, a.session.state.game, a.session.state.var }, { { 0, 0 }, 1, "std" }); eq(a.session.diceSeen.bad, 0)
  end)

  it("a bot hosts Табла, throws with me and starts the next match", function()
    local sim, a, _, bots = setup(); local E = ns.Engines.tabla
    local fair, res = {}, {}; a:on("fair", function(e) fair[#fair + 1] = e.verdict end); a:on("result", function(r) res[#res + 1] = r end)
    local tid = bots:hostTable("tabla"); ok(tid); sim:run(3); a:sit(tid, 2); sim:run(4)
    local s = a.session; eq(s.status, "live"); ok(bots.isBot[s.seats[1]]); eq(s.host, s.seats[1])
    eq({ s.diceLast.by, s.diceLast.verdict }, { s.seats[1], "ok" })
    for _ = 1, 40000 do
      local st = a.session.state; if E.over(st) then break end
      if st.turn == 2 and st.phase == "move" then a:playAuto() end; sim:run(1)
    end
    eq(E.over(a.session.state), true); eq(#res, 1); eq(res[1].left, nil)   -- ended by play, nobody stood up
    ok(#fair >= 60, tostring(#fair)); for _, v in ipairs(fair) do eq(v, "ok") end
    sim:run(6); eq(a.session.state.score, { 0, 0 }); eq(#res, 1)
  end)

  it("a bot hosts Холдем and fills its table to six; I sit, play eight hands and nothing leaves the machine", function()
    local sim, a, _, bots = setup(); local E = ns.Engines.holdem
    local tid = bots:hostTable("holdem"); ok(tid); sim:run(3); a:sit(tid, 2); local mark = #sim.sent; sim:run(12)
    local s = a.session; eq({ s:seatedCount(), s.status, s.mySeat, #s.seats }, { 6, "live", 2, 6 })
    local hands, bad = {}, 0; a:on("hand", function(e) hands[#hands + 1] = e end); a:on("fair", function(e) if e.verdict == "bad" then bad = bad + 1 end end)
    for _ = 1, 2000 do
      if #hands >= 8 then break end
      if s.state.turn == 2 then a:playAuto() end; sim:run(1)
    end
    eq(#hands, 8); eq(bad, 0); local sum = 0
    for _, n in pairs(hands[8].chips) do sum = sum + n end
    for _, n in pairs(hands[8].last.left) do sum = sum + n end
    eq(sum, 6000)
    local words = { tid }; for name in pairs(bots.isBot) do words[#words + 1] = name end
    for i = mark + 1, #sim.sent do ok(not mentions(sim.sent[i].msg, words), "leak in " .. tostring(sim.sent[i].msg.t)) end
    eq({ ns.Book.status(s) }, { "seal.sealed", "inkDim", 8, 0 })
  end)

  it("fill does not ask bots into a running game, but for an engine that takes them (botFill)", function()
    local sim, a, _, bots = setup()
    local tid = a:openTable{ game = "deathroll", access = "invite", turn = 30 }; ok(tid); eq(bots:fill(1), 1); sim:run(8)
    eq(a.session:seatedCount(), 2); ok(a:startGame()); sim:run(1); eq({ a.session.status, #a.session.seats - a.session:seatedCount() }, { "live", 3 })
    eq(bots:fill(), nil); sim:run(8); eq(a.session:seatedCount(), 2)
    a.session.gameOver = function() return true end; eq(bots:fill(1), 1)                         -- between two games the table takes them again
  end)

  it("I host Холдем and fill my table with five bots; the close checks every hand", function()
    local sim, a, _, bots = setup(); local E = ns.Engines.holdem
    eq(bots:fill(), nil); local tid = a:openTable{ game = "holdem", access = "invite", turn = 30 }; ok(tid); eq(bots:fill(3), 3); sim:run(8)
    eq(a.session:seatedCount(), 4); local mark = #sim.sent; eq(bots:fill(), 2); sim:run(14); eq({ a.session:seatedCount(), #bots.list }, { 6, 5 })
    local book; a:on("book", function(e) book = e end); ok(a:startGame())
    for _ = 1, 600 do
      local st = a.session.state; if st.hand >= 4 and st.phase == "bet" then break end
      if st.turn == 1 then a:playAuto() end; sim:run(1)
    end
    ok(ns.Cash.close(a))
    for _ = 1, 200 do if book then break end; if a.session.state.turn == 1 then a:playAuto() end; sim:run(1) end
    eq({ book.hands, book.ok, book.bad, book.open }, { 4, 4, 0, 0 })
    local words = { tid }; for name in pairs(bots.isBot) do words[#words + 1] = name end
    for i = mark + 1, #sim.sent do ok(not mentions(sim.sent[i].msg, words), "leak in " .. tostring(sim.sent[i].msg.t)) end
  end)

  it("hostTable and inviteMe refuse a game that is not built", function()
    local _, _, _, bots = setup()
    eq(bots:hostTable("nosuchgame"), nil); eq(bots:inviteMe("nosuchgame"), nil); ok(bots:hostTable()) -- default ttt
  end)

  it("disable restores env.inGroup", function()
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" })
    local orig = envA.inGroup
    local bots = Bots.enable(a, envA, sim.makeEnv); sim:run(1)
    eq(envA.inGroup(bots.list[1].env.guid), true)
    Bots.disable(bots)
    ok(envA.inGroup == orig)
  end)
end)
