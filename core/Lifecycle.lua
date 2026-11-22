local _, ns = ...

-- The game lifecycle of a table session (core/Session.lua), installed on the
-- Session metatable: the engine's extensions (ns.Ext, see Session:hook), a new
-- game from the occupied seats, the "result" event (with `left`, the seat whose
-- leaving ended the game, and `names`, the table as it sat before the event
-- that ended it), and the entry points
-- startGame (games with engine.start == "host", which Session:startIfFull never
-- starts, and the next match of an engine with `again` once one is over; its
-- checks are Session.startable / Session:canStart and Session:gameOver, shared
-- with the bots and the table frame) and playAuto. Session:apply calls newGame and noteResult;
-- Session:onAct passes a member's action through filterAct before playing it;
-- a new host (core/Succession.lua) applies its catch-up events with applyUnsent.
-- A game whose engine has `view` is held as my seat's view on every client:
-- snapshots are cut per recipient (snapshotFor) and a member's own clock plays
-- its own hand on timeout (armAuto), again every AUTO_RETRY seconds while the
-- turn stays mine (the move was lost, or my cards had not come yet).
local Session = ns.Session
local C = ns.Const
local copy, seatOf = ns.Util.copy, ns.Util.seatOf

-- Extensions ns.Ext[x], x in engine.ext (a name not registered is skipped), and
-- at a staked table (s.stake) last of all ns.Ext.stakes (core/Stakes.lua): hook
-- calls `name` on every one that has it and returns the first non-nil result;
-- filterAct passes a member's action through their act hooks until one drops it.
-- Hooks: act, applied, auto (see the shared contracts), adopted(s, prevState, m,
-- how) after the snapshot m replaced my state (how: see Member.adopt),
-- hostChanged(s) when my table changed host; refused(s, seat, a) (member: an
-- event of my host that does not apply), forged(s, seat, a) (member, engine
-- with `view`, or a staked table's engine without `idle`: an event for my seat
-- that I did not send and that is no public timeout due by my own clock, or a
-- seat-0 event no honest host plays now; Member.timedOut, Member.unasked),
-- stuck(s) (my deadline passed and I have no automatic move to make: e.g. my cards are missing);
-- need(s, action) (host: a system action that needs randomness), lapsed(s)
-- (host: a shuffle was not dealt in FAIR_WAIT; called before it is opened again),
-- table(s, a) -> true (a seat-0 event the extension applied itself), snap(s)
-- -> the SNP field `fr`, leaving(s) (my client stands up: Client:stand, before
-- its STD), gone(s) (member: my host answered SNO "gone" while I held a seat,
-- before my session ends), ended(s) -> true (member, staked: my host's END or its
-- snapshot at another stake, before my session ends). A hook that raises counts as nil: the error goes to
-- env.log ("error", "ext", "<ext>.<hook>", message), so it cannot cut short the
-- request, event or snapshot handling around it (e.g. the sitter's SNP after a sit);
-- an act hook that raises drops the action.
local function call(s, id, x, name, ...)
  local ok, got = pcall(x[name], s, ...)
  if ok then return got end
  local env = s.client.env
  if env.log then env.log("error", "ext", id .. "." .. name, tostring(got)) end
  if env.strictHooks then error(got, 0) end -- tests only: the WoW adapter never sets it
  return nil
end

local NONE, STAKED = {}, {} -- STAKED[ext]: that list with "stakes" last

local function exts(s)
  local ext = s:engine().ext or NONE
  if s.stake == nil then return ext end
  local list = STAKED[ext]
  if not list then
    list = { unpack(ext) }
    list[#list + 1] = "stakes"
    STAKED[ext] = list
  end
  return list
end

function Session:hook(name, ...)
  local ext, out = exts(self), nil
  for i = 1, #ext do
    local x = ns.Ext[ext[i]]
    local r = nil
    if x and x[name] then r = call(self, ext[i], x, name, ...) end
    if out == nil then out = r end
  end
  return out
end

-- An event a new host orders for itself before its snapshots go out (the old
-- host's stand that never reached it, the abort of a short table): applied and
-- counted without being sent, then the extensions' `applied`. -> true | nil
function Session:applyUnsent(seat, a)
  if not self:apply(seat, a) then return nil end
  self.seq = self.seq + 1
  self:hook("applied", seat, a)
  return true
end

function Session:filterAct(seat, a)
  local ext = exts(self)
  for i = 1, #ext do
    local x = ns.Ext[ext[i]]
    if a ~= nil and x and x.act then a = call(self, ext[i], x, "act", seat, a) end
  end
  return a
end

-- Seat -> true when occupied, and the lowest occupied seat.
local function occupied(seats)
  local out, lowest = {}, nil
  for i = 1, #seats do
    out[i] = seats[i] ~= false
    lowest = lowest or (out[i] and i or nil)
  end
  return out, lowest
end

-- The engine state of a new game: `first` when that seat is occupied, else the
-- lowest occupied seat begins; opts.staked at a staked table. With
-- engine.view: my seat's view of it.
function Session:newGame(first)
  local seats, lowest = occupied(self.seats)
  local engine = self:engine()
  local state = engine.new({ first = seats[first] and first or lowest, seats = seats, opt = copy(self.opt), staked = self.stake ~= nil })
  if engine.view then return engine.view(state, self.mySeat or 0) end
  return state
end

-- The SNP state for `name` -> table | nil (no state): with engine.view cut to
-- what that seat (0 for a watcher) may see of mine.
function Session:snapshotFor(name)
  if not self.state then return nil end
  local engine = self:engine()
  if not engine.view then return engine.snapshot(self.state) end
  return engine.snapshot(engine.view(self.state, seatOf(self.seats, name) or 0))
end

-- After every applied EV and every adopted snapshot (the host: from its
-- extension's `applied`). In a live game whose engine has `view`, on my own
-- turn with a deadline, my client makes my automatic move when the deadline
-- passes (the host cannot: it does not see my hand) unless the table moved on.
-- While the table still stands at that very event the move is made again
-- every AUTO_RETRY seconds, AUTO_RETRIES times at most: the ACT may have been
-- lost (the host refuses a second one, "turn"), or there was no move to make
-- yet because my cards had not come (hook `stuck`: they are asked for again).
-- A host's own move at the deadline is its turn timer's (Session:armTimers);
-- only the retries are made here.
local AUTO_RETRY, AUTO_RETRIES = 5, 36

function Session:armAuto()
  if self.autoTimer then self.autoTimer.cancel(); self.autoTimer = nil end
  local client, st = self.client, self.state
  if not (self.mySeat and self.status == "live" and st and self:engine().view) then return end
  if st.turn ~= self.mySeat or not self.deadline then return end
  local seq, tries = self.seq, 0
  local function fire()
    self.autoTimer = nil
    if client.session ~= self or self.seq ~= seq or self.status ~= "live" then return end
    if (self.role ~= "host" or tries > 0) and not Session.playAuto(client) then self:hook("stuck") end
    tries = tries + 1
    -- A host's move is applied at once and has armed the next turn already.
    if self.seq == seq and not self.autoTimer and tries <= AUTO_RETRIES then
      self.autoTimer = client:after(AUTO_RETRY, fire)
    end
  end
  self.autoTimer = client:after(math.max(0, self.deadline - client.env.now()), fire)
end

-- The engine's result turned from nil to a value: event "result" (once), with
-- left = the seat whose leaving ended the game (the engine's r.left, else nil),
-- names = seat -> name or false as the table sat before the event that
-- ended it, q = the number of that event and sk = the table's stake (nil: for
-- fun). While there is no result, s.seatedBefore keeps that copy of the
-- seats (Member.adopt sets it too, for a member whose first event ends the game).
-- s.gameNo (local, never sent) names the game my client holds: it goes up
-- when a game begins here, by a start (`began`) or inside the engine (a known
-- result is gone again: Морски шах's rematch), and with every snapshot that
-- replaces my state (Member.adopt). An asked seat is kept for one gameNo only
-- (ns.Stake.ask).
function Session:noteResult(began)
  local engine = self:engine()
  local r = self.state and engine.result and engine.result(self.state)
  if began or (self.resultSeen and not r) then self.gameNo = (self.gameNo or 0) + 1 end
  if r and not self.resultSeen then
    self.client.events:emit("result", {
      tid = self.tid, game = self.game, opt = copy(self.opt), seats = copy(self.seats),
      winners = copy(r.winners), losers = copy(r.losers), left = r.left,
      names = copy(self.seatedBefore or self.seats), at = self.client.env.epoch(),
      q = self.seq + 1, sk = self.stake,
    })
  end
  if not r then self.seatedBefore = copy(self.seats) end
  self.resultSeen = r and true or false
end

-- The game has ended and the next may start -> bool: any truthy engine.over,
-- else a known result; false without a state.
function Session:gameOver()
  local engine, state = self:engine(), self.state
  if not state then return false end
  if engine.over then return engine.over(state) and true or false end
  return engine.result ~= nil and engine.result(state) ~= nil
end

-- Would startGame start the next game now -> true | nil, code: "nothost",
-- "mode" (the engine has neither start == "host" nor `again` with the game
-- over: it starts by itself), "short" (fewer than minSeats seated), "live" (a
-- game is running and not over), "book" (a sealed game is over at a live table and my book has
-- not published its keys yet: the check of every hand would be lost; an aborted
-- table's book is closed and waits for nothing); at a staked table "group" (a
-- seated player outside my group, for an engine that needs one: Stakes.grouped)
-- and "break" (Stakes.gap has not passed by my clock since the last game
-- ended: s.stakeEndedAt, core/Stakes.lua). The checks of startGame, no effect.
function Session:canStart()
  if self.role ~= "host" then return nil, "nothost" end
  local engine, over = self:engine(), self:gameOver()
  if engine.start ~= "host" and not (engine.again and over) then return nil, "mode" end
  if self:seatedCount() < engine.minSeats then return nil, "short" end
  if self.status == "live" and not over then return nil, "live" end
  if engine.sealed and over and self.status == "live" and not (self.book and self.book.published) then return nil, "book" end
  if self.stake ~= nil and engine.needsGroup and not ns.Stakes.grouped(self) then return nil, "group" end
  if self.stake ~= nil and self.stakeEndedAt and self.client.env.now() < self.stakeEndedAt + ns.Stakes.gap(self) then return nil, "break" end
  return true
end

-- Session:canStart for my table -> true | nil, code ("none": no table).
function Session.startable(client)
  local s = client.session
  if not s then return nil, "none" end
  return s:canStart()
end

-- Host: the next game begins -> true | nil, code of Session.startable.
function Session.startGame(client)
  local can, code = Session.startable(client)
  if not can then return nil, code end
  local s = client.session
  local engine = s:engine()
  local seats, first = occupied(s.seats)
  if engine.nextFirst and s.state then first = engine.nextFirst(s.state, seats) or first end
  s:event(0, { k = "start", first = first })
  s:recordChanged()
  return true
end

-- My automatic move -> true | nil, code as Session.act ("turn": none to make).
-- An extension's auto hook may make it instead.
function Session.playAuto(client)
  local s = client.session
  if not s then return nil, "none" end
  if not s.mySeat then return nil, "seat" end
  if s.status ~= "live" then return nil, "live" end
  if s:hook("auto") then return true end
  local a = s:engine().auto(s.state, s.mySeat, client.env.random)
  if not a then return nil, "turn" end
  return Session.act(client, a)
end
