local _, ns = ...

-- Composes the core modules; the only API ui/ and wow/ call.
local Client = {}
Client.__index = Client
ns.Client = Client

local C = ns.Const

function Client.new(env)
  local self = setmetatable({ env = env, events = ns.Emitter.new(), timers = {}, running = false }, Client)
  self.presence = ns.Presence.new(self)
  self.lobby = ns.Lobby.new(self)
  self.session = nil -- see core/Session.lua
  self.pending = nil -- { tid, host } of an unanswered SIT/WAT
  self.invites = ns.Invites.new(self)
  self.stakeNoted = false -- a db.stakeSat note was written in this run (see ns.Stake.note)
  ns.Stake.watch(self)
  ns.CashOut.watch(self) -- my buy-in after my sit, „Стани“ as a cash-out (core/CashOut.lua)
  if env.guild and env.db then
    self:openLedger()
  elseif not env.guild and env.log then
    env.log("ledger", nil, nil, "no guild: no ledger")
  end
  return self
end

-- The guild's gold ledger (env.db.ledger[env.guild]); a client without a guild has none.
function Client:openLedger()
  local env = self.env
  local ledgers = env.db.ledger or {}
  env.db.ledger = ledgers
  ledgers[env.guild] = ledgers[env.guild] or {}
  self.ledger = ns.Ledger.new(ledgers[env.guild], env.me, env.epoch)
  self.ledgerNet = ns.LedgerNet.new(self, self.ledger)
  self.ledgerSync = ns.LedgerSync.new(self, self.ledger, self.ledgerNet)
  self.stakes = ns.Stakes.new(self) -- outcomes to the ledger, claims against me (core/StakesBook.lua)
  self.pay = ns.Pay.new(self) -- trade, mail, „Уредено“, „Напомни“ (core/Pay.lua)
end

-- My guild's name came after I started: right after login the game client may
-- not know it yet (wow/Adapter.lua asks again on the guild's events). The ledger
-- opens now, as it would have at the start -> true | nil (a ledger already, no
-- name, no saved variables).
function Client:joinGuild(guild)
  if self.ledger or type(guild) ~= "string" or guild == "" or not self.env.db then return nil end
  self.env.guild = guild
  self:openLedger()
  if self.running then self.ledgerNet:start(); self.stakes:start() end
  if self.env.log then self.env.log("ledger", nil, nil, "guild known: ledger opened") end
  self.events:emit("ledger")
  return true
end

function Client:on(event, fn) self.events:on(event, fn) end

-- One-shot timer through env.after, tracked so stop() can cancel it.
function Client:after(seconds, fn)
  local timer, handle = {}, nil
  timer.cancel = function()
    self.timers[timer] = nil
    if handle then handle.cancel() end
  end
  self.timers[timer] = true
  handle = self.env.after(seconds, function()
    if not self.timers[timer] then return end
    self.timers[timer] = nil
    fn()
  end)
  return timer
end

-- `done` (optional): called once the message has left (env.send's done-callback).
function Client:send(channel, target, msg, done)
  self.env.send(channel, target, msg, done)
  if self.env.log then self.env.log("out", channel, target, msg) end
end

function Client:start()
  if self.running then return end
  self.running = true
  if self.ledgerNet then self.ledgerNet:start(); self.stakes:start() end
  self.presence:start()
end

function Client:stop()
  if not self.running then return end
  self.running = false
  if self.session and self.session.stake ~= nil then ns.Stakes.save(self.session) end -- what I sent there, as it stands now
  ns.Session.stop(self) -- keeps the seat; END only for a host alone (no HI: BYE follows)
  if self.ledgerNet then self.ledgerNet:stop(); self.ledgerSync:stop() end -- my entries of the last seconds still go out
  self:send("GUILD", nil, { v = C.PROTOCOL, t = "BYE" })
  for timer in pairs(self.timers) do timer.cancel() end
  self.timers = {}
  self.invites:drop(false) -- a shown invitation does not outlive the client
end

function Client:peerOffline(name)
  self.presence:remove(name)
end

-- opts {game, access, turn, opt, stake} -> tid | nil, code ("busy" "game" "stake" "access" "turn" "opt").
-- `stake`: copper (ns.Stake.valid), only for a game whose engine has `stakes = true`; nil = for fun.
-- A client without a ledger (no guild: a bot) opens no staked table.
function Client:openTable(opts)
  if type(opts) == "table" and opts.stake ~= nil and not self.ledger then return nil, "stake" end
  return ns.Session.open(self, opts)
end

-- Refusals arrive as the event "refused"(tid, why). `sk`: the table's stake I
-- accept (nil at a fun table); any other is refused "stake". A client without a
-- ledger (a bot) sits at no staked table -> nil, "stake" at once, nothing sent.
-- A client without /roll (env.roll) sits at no staked Death Roll (an engine
-- with `idle` takes only rolls the host saw): "refused"(tid, "roll") and nil, "roll".
function Client:sit(tid, seat, sk)
  local rec, s = self.lobby:get(tid), self.session
  local staked = sk ~= nil or (rec and rec.stake ~= nil) or (s and s.tid == tid and s.stake ~= nil)
  if not self.ledger and staked then return nil, "stake" end
  local engine = ns.Games.engine(rec and rec.game or (s and s.tid == tid and s.game))
  if staked and not self.env.roll and engine and engine.idle then
    ns.Session.refuse(self, tid, "roll")
    return nil, "roll"
  end
  ns.Session.request(self, "SIT", tid, seat, sk)
end

-- After "stakeAsk"(tid, sk): I accept that stake and keep my seat -> true | nil
-- (nothing asked). Unaccepted, the end of the running game stands me up.
function Client:acceptStake() return ns.Stake.accept(self) end
function Client:watch(tid) ns.Session.request(self, "WAT", tid) end

-- Stands up or stops watching (the extensions hear of it first: hook `leaving`);
-- my stake note goes (ns.Stake), so no host can seat me there again at it.
function Client:stand()
  if self.session then self.session:hook("leaving") end
  ns.Session.stand(self)
  ns.Stake.clear(self)
end

-- A move by my seat -> true | nil, code (see Session.act).
function Client:act(action) return ns.Session.act(self, action) end

-- Host: start the next game of a host-started game -> true | nil, code (see Session.startGame).
function Client:startGame() return ns.Session.startGame(self) end

-- My automatic move -> true | nil, code (see Session.playAuto).
function Client:playAuto() return ns.Session.playAuto(self) end

-- My roll in a game with server rolls -> true | nil, code (see Rolls.roll).
function Client:roll() return ns.Rolls.roll(self) end

-- A server roll seen in chat (`shown` normalized, my own as env.me); emits
-- "rollSeen"(shown, n, lo, hi) first, always (see Rolls.seen).
function Client:rollSeen(shown, n, lo, hi) ns.Rolls.seen(self, shown, n, lo, hi) end

-- A group invite from `shown` (normalized): accept it automatically? Only from
-- the host of the table where I hold a seat, when its game needs a group.
function Client:groupInviteFrom(shown) return ns.Party.inviteFrom(self, shown) end

-- My group changed (who is in it, its leader or size): "session" again.
function Client:groupChanged()
  if self.session then ns.Session.emit(self) end
end

-- Host of a table with a free seat: invite `name` -> true | nil, code
-- ("nothost" "unknown" "seated" "pending"). The answer arrives as "inviteAnswer".
function Client:invite(name) return self.invites:send(name) end

-- An "invite" event's table: answer "yes", "no" or "snooze" (see core/Invites.lua).
function Client:answerInvite(tid, answer) self.invites:answer(tid, answer) end

function Client:receive(channel, sender, msg)
  if not self.running then return end
  -- Guild traffic reached me (Succession.claim: was I cut off?). Not a whisper: a host that stops
  -- hearing me while I hear others whisper (one-way loss) must not make my stand there "forged".
  if channel == "GUILD" then self.heardAt = self.env.now() end
  if self.env.log then self.env.log("in", channel, sender, msg) end
  if type(msg) ~= "table" or msg.v == nil or msg.t == nil then return end
  if type(sender) ~= "string" or sender == self.env.me then return end
  if msg.v ~= C.PROTOCOL then
    self.presence:incompatible(sender)
    if type(msg.v) == "number" and msg.v > C.PROTOCOL and not self.updateSeen then
      self.updateSeen = true
      self.events:emit("update")
    end
    -- A whispered SIT/WAT with a string tid also gets the "version" refusal;
    -- every other v ~= 1 message stops here.
    if channel == "WHISPER" and (msg.t == "SIT" or msg.t == "WAT") and type(msg.tid) == "string" then
      ns.Session.refuseVersion(self, sender, msg.tid)
    end
    return
  end
  self.presence:receive(channel, sender, msg)
  self.lobby:receive(channel, sender, msg)
  ns.Session.receive(self, channel, sender, msg)
  self.invites:receive(channel, sender, msg)
  if self.ledgerNet then self.ledgerNet:receive(channel, sender, msg) end
  if self.ledgerSync and channel == "WHISPER" and (msg.t == "LVC" or msg.t == "LEV" or msg.t == "LID") then
    self.ledgerSync:receive(sender, msg)
  end
  if self.pay and channel == "WHISPER" and msg.t == "PAY" then self.pay:receive(sender, msg) end
end
