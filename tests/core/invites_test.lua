local Sim = require("sim")
require("fake_engine")
local I = Sim.ns.Invites

local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"

local function setup(opts)
  opts = opts or {}
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST", status = opts.statusB })
  local c = sim:add(C, { cls = "ROGUE" })
  sim:run(1)
  return sim, a, b, c
end

-- Every emission of `event` on `client`, as a list of argument lists.
local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

local function sentBy(sim, from, mark, pred)
  local out = {}
  for i, s in ipairs(sim.sent) do
    if i > mark and s.from == from and (not pred or pred(s)) then out[#out + 1] = s end
  end
  return out
end

describe("invites", function()
  it("invite -> yes seats the guest at an invite-only table", function()
    local sim, a, b = setup()
    local got
    b:on("invite", function(inv) got = inv end)
    local answers = record(a, "inviteAnswer")
    local tid = a:openTable{game="ttt", access="invite", turn=45}; sim:run(3); ok(a:invite(B)); sim:run(1)
    eq(got.tid, tid); eq(got.host, A); eq(got.game, "ttt"); eq(got.seats, { A, false })
    eq(got.expires, sim:now() + 30)
    b:answerInvite(tid, "yes"); sim:run(3); eq(a.session.seats, {A, B})
    eq(answers, { { B, "yes" } }); eq(b.session.mySeat, 2)
  end)

  it("auto-decline reasons, in order", function()
    eq(I.autoReason({combat=true, instance=true}, 0, 100, false), "combat")
    eq(I.autoReason({instance=true}, 0, 100, false), "instance"); eq(I.autoReason({}, 0, 100, true), "busy")
    eq(I.autoReason({}, 200, 100, false), "snooze"); eq(I.autoReason({}, 200, 200, false), nil)
    eq(I.autoReason({busy=true}, 200, 100, false), "busy")
  end)

  it("invitee in combat: no toast event, host hears ('auto','combat')", function()
    local sim, a, b = setup({ statusB = { combat = true } })
    local invites, answers = record(b, "invite"), record(a, "inviteAnswer")
    a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    eq(#invites, 0); eq(answers, { { B, "auto", "combat" } })
  end)

  it("invitee at another table auto-declines 'busy'", function()
    local sim, a, b, c = setup()
    local invites, answers = record(b, "invite"), record(a, "inviteAnswer")
    local ctid = c:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    b:watch(ctid); sim:run(1)
    a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    eq(#invites, 0); eq(answers, { { B, "auto", "busy" } })
  end)

  it("unanswered invite times out at 30 s", function()
    local sim, a, b = setup()
    local gone, answers = record(b, "inviteGone"), record(a, "inviteAnswer")
    local tid = a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(29)
    eq(gone, {}); eq(answers, {})
    sim:run(2)
    eq(answers, { { B, "auto", "timeout" } }); eq(gone, { { tid } })
    sim:run(30); eq(#answers, 1) -- the host's own fallback stays quiet
    ok(a:invite(B)) -- no longer pending
  end)

  it("an invitee that never answers is given up by the host a little later", function()
    local sim, a = setup()
    local answers = record(a, "inviteAnswer")
    a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    sim:offline(B)
    ok(a:invite(B)); sim:run(34); eq(answers, {})
    sim:run(1); eq(answers, { { B, "auto", "timeout" } })
    ok(a:invite(B))
  end)

  it("snooze lasts 30 minutes", function()
    local sim, a, b = setup()
    local invites, answers = record(b, "invite"), record(a, "inviteAnswer")
    local tid = a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1); eq(#invites, 1)
    local t0 = sim.envs[B].epoch()
    b:answerInvite(tid, "snooze"); sim:run(1)
    eq(sim.envs[B].db.snoozeUntil, t0 + 1800); eq(answers, { { B, "no" } })
    ok(a:invite(B)); sim:run(1)
    eq(#invites, 1); eq(answers[2], { B, "auto", "snooze" })
    sim:run(1801)
    ok(a:invite(B)); sim:run(1)
    eq(#invites, 2); eq(invites[2][1].tid, tid)
  end)

  it("no declines, and the host may invite again", function()
    local sim, a, b = setup()
    local answers = record(a, "inviteAnswer")
    local tid = a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    eq({ a:invite(B) }, { nil, "pending" })
    b:answerInvite(tid, "no"); sim:run(1)
    eq(answers, { { B, "no" } }); eq(b.session, nil); eq(sim.envs[B].db.snoozeUntil, 0)
    ok(a:invite(B))
  end)

  it("invite refusals: nothost, unknown, seated, pending", function()
    local sim, a, b, c = setup()
    eq({ a:invite(B) }, { nil, "nothost" })
    local tid = a:openTable{game="fake", access="guild", turn=45}; sim:run(3)
    local m0 = #sim.sent
    eq({ a:invite("Никой Никой") }, { nil, "unknown" })
    eq({ a:invite(A) }, { nil, "unknown" })
    b:sit(tid, 2); sim:run(3)
    eq({ a:invite(B) }, { nil, "seated" })
    eq({ b:invite(C) }, { nil, "nothost" }) -- only the host invites
    eq(#sentBy(sim, A, m0, function(s) return s.msg.t == "INV" end), 0)
    ok(a:invite(C)); eq({ a:invite(C) }, { nil, "pending" })
    eq(#sentBy(sim, A, m0, function(s) return s.msg.t == "INV" end), 1)
    sim:run(1); c:sit(tid, 3); sim:run(3)
    eq(a.session.seats, { A, B, C })
    eq({ a:invite(C) }, { nil, "nothost" }) -- no free seat
  end)

  it("one pending invite per invitee: a second is auto-answered 'busy'", function()
    local sim, a, b, c = setup()
    local invites, answers = record(b, "invite"), record(c, "inviteAnswer")
    local tid = a:openTable{game="ttt", access="invite", turn=45}
    c:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    ok(c:invite(B)); sim:run(1)
    eq(#invites, 1); eq(invites[1][1].tid, tid); eq(answers, { { B, "auto", "busy" } })
  end)

  it("INV and INR count only by whisper", function()
    local sim, a, b = setup()
    local invites, answers = record(b, "invite"), record(a, "inviteAnswer")
    local tid = a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    local m0 = #sim.sent
    b:receive("GUILD", A, { v = 1, t = "INV", tid = tid, g = "ttt", h = A, s = { A, false } }); sim:run(1)
    eq(#invites, 0); eq(#sentBy(sim, B, m0, function(s) return s.msg.t == "INR" end), 0)
    ok(a:invite(B))
    a:receive("GUILD", B, { v = 1, t = "INR", tid = tid, a = "no" }); sim:run(0)
    -- the real INV is answered by whisper below, never the GUILD copies
    sim:run(1); eq(#invites, 1); eq(answers, {})
    -- an INV naming somebody else as host is ignored, not answered
    local m1 = #sim.sent
    b:receive("WHISPER", C, { v = 1, t = "INV", tid = tid, g = "ttt", h = A, s = { A, false } }); sim:run(0)
    eq(#invites, 1); eq(#sentBy(sim, B, m1, function(s) return s.msg.t == "INR" end), 0)
  end)

  it("stale yes after the chair was taken is refused 'taken'", function()
    local sim, a, b, c = setup()
    local refused, gone = record(b, "refused"), record(b, "inviteGone")
    local tid = a:openTable{game="ttt", access="guild", turn=45}; ok(a:invite(B)); sim:run(1)
    c:sit(tid, 2); sim:run(1)
    eq(gone, { { tid } })
    b:answerInvite(tid, "yes"); sim:run(1)
    eq(refused, { { tid, "taken" } }); eq(b.session, nil)
    eq(a.session.seats, { A, C }); eq(gone, { { tid } })
  end)

  it("two invitees who say yes in the same tick are both seated, the second at the next free seat", function()
    local sim, a, b, c = setup()
    local rb, rc = record(b, "refused"), record(c, "refused")
    local tid = a:openTable{game="fake", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); ok(a:invite(C)); sim:run(1)
    b:answerInvite(tid, "yes"); c:answerInvite(tid, "yes"); sim:run(3) -- both ask for seat 2
    eq(a.session.seats, { A, B, C }); eq(b.session.mySeat, 2); eq(c.session.mySeat, 3)
    eq(rb, {}); eq(rc, {})
  end)

  it("yes after the table closed is refused 'gone'", function()
    local sim, a, b = setup()
    local refused, gone = record(b, "refused"), record(b, "inviteGone")
    local answers = record(a, "inviteAnswer")
    local tid = a:openTable{game="ttt", access="invite", turn=45}; ok(a:invite(B)); sim:run(1)
    a:stand(); sim:run(1)
    eq(gone, { { tid } })
    b:answerInvite(tid, "yes"); sim:run(1)
    eq(refused, { { tid, "gone" } }); eq(b.session, nil); eq(gone, { { tid } })
    sim:run(60); eq(answers, {}) -- the closed table forgot its invite
  end)

  it("the invited list travels to the next host: an invited watcher keeps watching", function()
    local sim, a, b, c = setup()
    local refused = record(c, "refused")
    local tid = a:openTable{game="fake", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    b:answerInvite(tid, "yes"); sim:run(3)
    -- invited after b's snapshot and its INA lost: only the HND can tell b about c
    sim.bus.filter = function(_, _, _, m) return m.t == "INA" and {} or { m } end
    ok(a:invite(C)); sim:run(1); c:answerInvite(tid, "no")
    sim.bus.filter = nil
    c:watch(tid); sim:run(3)
    eq(a.session.seats, { A, B, false }); eq(c.session.role, "watcher"); eq(b.session.invited[C], nil)
    a:stand(); sim:run(10)
    eq(b.session.role, "host"); eq(b.session.invited[C], true)
    eq(c.session.role, "watcher"); eq(c.session.host, B); eq(c.session.stale, nil)
    eq(refused, {})
    -- the old host may come back to its own table
    a:watch(tid); sim:run(3); eq(a.session.role, "watcher")
  end)

  it("a claimant after a silent host keeps the invited list from its snapshot", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); ok(a:invite(C)); sim:run(1)
    b:answerInvite(tid, "yes"); sim:run(3)
    c:watch(tid); sim:run(3)
    sim:offline(A); sim:run(100)
    eq(b.session.role, "host"); eq(b.session.invited[C], true)
    eq(c.session.role, "watcher"); eq(c.session.host, B)
  end)

  it("a claimant after a silent host knows invitations sent after its snapshot", function()
    local sim, a, b, c = setup()
    local refused = record(c, "refused")
    local tid = a:openTable{game="fake", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    b:answerInvite(tid, "yes"); sim:run(3)
    ok(a:invite(C)); sim:run(1); c:answerInvite(tid, "no")
    eq(b.session.invited[C], true) -- told at once, not by a later snapshot
    c:watch(tid); sim:run(3); eq(c.session.role, "watcher")
    sim:offline(A); sim:run(100)
    eq(b.session.role, "host"); eq(b.session.invited[C], true)
    eq(c.session.role, "watcher"); eq(c.session.host, B); eq(c.session.stale, nil)
    eq(refused, {})
  end)

  it("INA counts only by whisper from my current host, at my epoch", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="fake", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    b:answerInvite(tid, "yes"); sim:run(3)
    local N = "Нов Клиент"
    b:receive("GUILD", A, { v = 1, t = "INA", tid = tid, e = 1, n = N })
    b:receive("WHISPER", C, { v = 1, t = "INA", tid = tid, e = 1, n = N })
    b:receive("WHISPER", A, { v = 1, t = "INA", tid = tid, e = 2, n = N })
    b:receive("WHISPER", A, { v = 1, t = "INA", tid = "other#1", e = 1, n = N })
    eq(b.session.invited[N], nil)
    b:receive("WHISPER", A, { v = 1, t = "INA", tid = tid, e = 1, n = N })
    eq(b.session.invited[N], true)
    -- the host itself ignores it
    a:receive("WHISPER", B, { v = 1, t = "INA", tid = tid, e = 1, n = "X Y" })
    eq(a.session.invited["X Y"], nil)
  end)

  it("stop() forgets a shown invitation", function()
    local sim, a, b = setup()
    local gone = record(b, "inviteGone")
    a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    ok(a:invite(B)); sim:run(1)
    b:stop()
    eq(b.invites.received, nil); eq(gone, {})
  end)
end)
