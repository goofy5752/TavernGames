local _, ns = ...

-- My two flows at a cash table (Stakes.cash: staked Холдем); it wraps
-- Client.sit and Client.stand, so it loads right after core/Client.lua (H6).
--   The buy-in follows my sit: the `buy` (chips) of Client:sit, or
--     Client:wantBuy (an invitation's yes), is my wish client.cashWant = {tid,
--     n}. At every "session", while it names my live table and my own record
--     (its `who` is me) bought nothing, my client plays `buy` with the wish clamped
--     down into E.buyRange, never while a buy I sent is unmatched (s.sent): one wish
--     buys once. A floor above my pick is not bought: the wish goes, "buyLow"(lo,
--     pick). It also goes when my record shows the buy, at "rebuy" or "full", and when
--     I leave; "hand", "phase" and a stake I did not accept ("stake", H15c) only wait (H15b).
--   „Стани“ (Client:stand) while CashOut.owes: client.cashGoing = {tid, at},
--     "cashGoing"(tid), and `cashout` once no running hand holds me (once per
--     event number). My cashout applied (owes no more), the original stand
--     runs, "cashGoing"(nil). CASH_OUT_WAIT after a cashout I played with no
--     hand holding me, still not applied: the stand runs without it (C5). A
--     hand that deals me in cancels that wait; my next cashout arms it (H15a).
--   Client:stand(true), any stand while CashOut.owes is false, or of a seat no hand dealt in since its buy (`fresh`): as before.
local CashOut = {}
ns.CashOut = CashOut

local Client, C, sit, stand = ns.Client, ns.Const, ns.Client.sit, ns.Client.stand

-- My own record of the table's state, or nil.
local function mine(s)
  local st = s.state
  local r = s.mySeat and type(st) == "table" and type(st.seats) == "table" and st.seats[s.mySeat]
  if type(r) == "table" and r.who == s.client.env.me and type(r.bought) == "number" then return r end
end

-- Is my seat dealt into the running hand -> bool.
local function held(s)
  local st = s.state
  local p = s:engine().inHand(st) and type(st.p) == "table" and st.p[s.mySeat]
  return type(p) == "table" and not p.gone
end

-- A cash table, live, my accepted stake (not an asked seat), my own record bought chips -> bool.
function CashOut.owes(s)
  local r = s and ns.Stakes.cash(s) and s.status == "live" and not s.stakeAsk and mine(s)
  return r ~= nil and r ~= false and r.bought > 0
end

-- My cash-out goes (its wait too), around `f` (the original stand, or nothing).
local function drop(client, f)
  local g = client.cashGoing
  client.cashGoing = nil
  if g and g.timer then g.timer.cancel() end
  if f then f(client) end
  if g then client.events:emit("cashGoing", nil) end
end
local function leave(client) client.cashWant = nil; drop(client, stand) end

-- A buy of mine still unmatched (sent, its event not seen yet).
local function buying(s)
  for _, e in ipairs(s.role ~= "host" and s.sent or {}) do
    if type(e.a) == "table" and e.a.k == "buy" then return true end
  end
  return false
end

local function wish(client, s, want)
  local r = s.status == "live" and ns.Stakes.cash(s) and mine(s)
  if not r then return end
  if r.bought > 0 or (want.q and not buying(s)) then client.cashWant = nil; return end -- one wish buys once
  if buying(s) then return end
  local lo, hi = s:engine().buyRange(s.state, s.mySeat)
  if not lo then
    if hi == "rebuy" or hi == "full" then client.cashWant = nil end
    return
  end
  local n = type(want.n) == "number" and want.n or lo
  if n < lo then client.cashWant = nil; return client.events:emit("buyLow", lo, n) end -- never more than I picked
  if client:buy(math.min(hi, n)) then want.q = s.seq end
end

local function cashOut(client, s, g)
  if not CashOut.owes(s) then return leave(client) end
  if held(s) then
    if g.timer then g.timer.cancel(); g.timer = nil end
    return
  end
  if g.q == s.seq or not client:act({ k = "cashout" }) then return end
  g.q = s.seq
  if not CashOut.owes(s) then return leave(client) end -- applied at once: I host
  if g.timer then return end
  g.timer = client:after(C.CASH_OUT_WAIT, function()
    g.timer = nil
    if client.cashGoing == g and client.session and client.session.tid == g.tid and not held(client.session) then leave(client) end
  end)
end

-- My table as it stands now: the wish and the cash-out (see the header).
function CashOut.step(client)
  local s, want, p = client.session, client.cashWant, client.pending
  if want and not (s and s.tid == want.tid) and not (p and p.tid == want.tid) then client.cashWant, want = nil, nil end
  if client.cashGoing and not (s and s.tid == client.cashGoing.tid) then drop(client) end
  if want and s then wish(client, s, want) end
  local g = client.cashGoing
  if g and s and client.session == s then cashOut(client, s, g) end
end

function CashOut.watch(client)
  client:on("session", function()
    if not (client.cashWant or client.cashGoing) or client.cashStep then return end
    client.cashStep = client:after(0, function()
      client.cashStep = nil
      CashOut.step(client)
    end)
  end)
end

-- As before; `buy` (chips, a cash table) is my wish (a sit without one keeps the wish for that table).
function Client:sit(tid, seat, sk, buy)
  local w = self.cashWant
  self.cashWant = buy ~= nil and { tid = tid, n = buy } or (w and w.tid == tid and w or nil)
  return sit(self, tid, seat, sk)
end

-- An invitation's yes: my buy-in at that table.
function Client:wantBuy(tid, n) self.cashWant = { tid = tid, n = n } end

-- My buy-in or rebuy of n chips -> true | nil, code ("stake": a stake I have not accepted plays for no gold).
function Client:buy(n)
  if self.session and self.session.stakeAsk then return nil, "stake" end
  return self:act({ k = "buy", n = n })
end

-- „Стани“ (see the header); now = true: at once, as before.
function Client:stand(now)
  local s = self.session
  if now or not CashOut.owes(s) or mine(s).fresh then return leave(self) end
  if not (self.cashGoing and self.cashGoing.tid == s.tid) then
    self.cashGoing = { tid = s.tid, at = self.env.now() }
    self.events:emit("cashGoing", s.tid)
  end
  CashOut.step(self)
end
