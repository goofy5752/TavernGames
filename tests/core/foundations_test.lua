local ns = Loader.ns()
local N, U, Bus, Trace = ns.Names, ns.Util, ns.Bus, ns.Trace

describe("foundations", function()
  it("normalizes names", function()
    eq(N.normalize("Иван Петров"), "Иван Петров")
    eq(N.normalize("Knikin Granitfaust-CAMWOWEU4Realm5PvE"), "Knikin Granitfaust")
    eq(N.normalize("  Мария Стоянова "), "Мария Стоянова"); eq(N.normalize(""), nil); eq(N.normalize(nil), nil)
  end)

  it("bus copies, orders, filters", function()
    local bus = Bus.new()
    local got = { x = {}, y = {} }
    bus:join("x", function(ch, from, msg) got.x[#got.x + 1] = { ch, from, msg } end)
    bus:join("y", function(ch, from, msg) got.y[#got.y + 1] = { ch, from, msg } end)

    local m = { v = 1, t = "HI", n = 1 }
    bus:send("x", "GUILD", nil, m); m.n = 99
    bus:send("x", "GUILD", nil, { v = 1, t = "HI", n = 2 })
    bus:flush()
    eq(#got.x, 0, "guild skips the sender")
    eq(got.y, { { "GUILD", "x", { v = 1, t = "HI", n = 1 } }, { "GUILD", "x", { v = 1, t = "HI", n = 2 } } })

    bus.filter = function(_, _, _, msg) return { msg, msg } end
    bus:send("y", "WHISPER", "x", { v = 1, t = "PNG" }); bus:flush()
    eq(#got.x, 2); eq(got.x[1], { "WHISPER", "y", { v = 1, t = "PNG" } }); eq(got.x[2], got.x[1])

    bus.filter = nil
    bus:send("x", "WHISPER", "nobody", { v = 1, t = "PNG" }); bus:flush()
    eq(#got.x, 2); eq(#got.y, 2)
  end)

  it("money formats", function()
    eq(U.money(123456), "12g 34s 56c"); eq(U.money(500000), "50g"); eq(U.money(0), "0c")
    eq(U.money(10003), "1g 3c")
  end)

  it("copy is deep and same compares deeply", function()
    local a = { 1, { x = { "y" } } }
    local b = U.copy(a)
    ok(b ~= a); ok(b[2] ~= a[2]); ok(U.same(a, b))
    b[2].x[1] = "z"; eq(a[2].x[1], "y"); eq(U.same(a, b), false)
    eq(U.same({ 1 }, { 1, 2 }), false); eq(U.same(1, 1), true)
  end)

  it("trace keeps the last 200 lines", function()
    local tr = Trace.new(200)
    local printed = 0
    tr.print = function() printed = printed + 1 end
    for i = 1, 201 do tr:add("out", "WHISPER", "P" .. i, { v = 1, t = "HI" }) end
    local lines = tr:lines()
    eq(#lines, 200)
    ok(lines[1]:find("P2", 1, true), lines[1]); ok(not lines[1]:find("P1 ", 1, true), lines[1])
    ok(lines[200]:find("P201", 1, true), lines[200])
    eq(printed, 201)
  end)

  it("emitter calls every handler with the arguments", function()
    local e = ns.Emitter.new()
    local got = {}
    e:on("x", function(a, b) got[#got + 1] = a .. b end)
    e:on("x", function(a) got[#got + 1] = a end)
    e:emit("x", "p", "q"); e:emit("other", 1)
    eq(got, { "pq", "p" })
  end)
end)

describe("bus re-entry", function()
  it("a flush from inside a delivery neither repeats nor loses messages", function()
    local bus = ns.Bus.new()
    local got = {}
    bus:join("x", function(_, _, msg)
      got[#got + 1] = msg.n
      if msg.n == 1 then bus:send("y", "WHISPER", "x", { v = 1, t = "PNG", n = 3 }); bus:flush() end
    end)
    bus:join("y", function() end)
    bus:send("y", "WHISPER", "x", { v = 1, t = "PNG", n = 1 })
    bus:send("y", "WHISPER", "x", { v = 1, t = "PNG", n = 2 })
    bus:flush()
    eq(got, { 1, 2, 3 })
  end)
end)

describe("trace redaction", function()
  local Sim = require("sim")
  require("hicard_engine")
  local A, B = "Иван Петров", "Мария Стоянова"

  it("PRV faces and SED seeds are shown as counts only; other messages as they are", function()
    local prv = { v = 1, t = "PRV", tid = "x#1", h = 4, cards = { [1] = "9C", [4] = "AD" } }
    local sed = { v = 1, t = "SED", tid = "x#1", h = 4, s = ("ab"):rep(16) }
    eq(Trace.redact(prv), { v = 1, t = "PRV", tid = "x#1", h = 4, cards = "<2>" })
    eq(Trace.redact(sed), { v = 1, t = "SED", tid = "x#1", h = 4, s = "<32>" })
    eq(prv.cards, { [1] = "9C", [4] = "AD" }); eq(sed.s, ("ab"):rep(16))      -- the message itself is untouched
    local prq = { v = 1, t = "PRQ", tid = "x#1", h = 4 }
    ok(Trace.redact(prq) == prq)
    local ev = { v = 1, t = "EV", a = { k = "play", i = 1, c = "9C" } }
    ok(Trace.redact(ev) == ev)
    eq(Trace.redact("junk"), "junk")
    eq(Trace.redact({ t = "PRV", cards = "junk" }).cards, "<?>"); eq(Trace.redact({ t = "SED", s = 5 }).s, "<?>")
  end)

  it("the dealer's debug trace never shows the other player's cards or seed", function()
    local sim = Sim.new()
    local a = sim:add(A, { cls = "MAGE" }); local b = sim:add(B, { cls = "PRIEST" })
    a.env.random = function() return 0x11 end; b.env.random = function() return 0x22 end
    local traces = {}
    for name, cl in pairs{ [A] = a, [B] = b } do
      local tr = Trace.new(500)
      traces[name] = tr
      cl.env.log = function(dir, channel, peer, msg) tr:add(dir, channel, peer, msg) end
    end
    sim:run(1)
    local tid = a:openTable{ game = "hicard", access = "guild", turn = 45 }; sim:run(3)
    b:sit(tid, 2); sim:run(1); a:startGame(); sim:run(1)
    local s = a.session
    eq({ s.fair.d, s.fair.stage }, { 2, "dealt" })                           -- b deals and whispers a its cards
    local deck = b.session.fair.deck
    local hidden = {}                                                        -- a's two cards, known to b's addon only
    for _, i in ipairs(a.session.state.hands[1]) do hidden[#hidden + 1] = deck[i] end
    eq(#hidden, 2)
    local function has(name, text)
      for _, line in ipairs(traces[name]:lines()) do
        if line:find(text, 1, true) then return line end
      end
    end
    for _, f in ipairs(hidden) do eq(has(B, '"' .. f .. '"'), nil) end      -- the dealer's trace
    eq(has(B, ("11"):rep(16)), nil); eq(has(A, ("11"):rep(16)), nil)         -- a's seed, on either side
    ok(has(B, "PRV")); ok(has(B, 'cards="<2>"')); ok(has(B, 's="<32>"')); ok(has(A, 's="<32>"'))
  end)
end)
