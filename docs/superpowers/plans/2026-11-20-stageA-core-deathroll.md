# Tavern Games Stage A (Shared Core Generalization + Death Roll) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Guild members open a Death Roll table for 2–6 players, are grouped automatically, press „Хвърли“ to make a real server `/roll`, and watch a ladder of rolls in class colours until somebody rolls 1; along the way the hall, the new-table dialog, the table frame, the bots and the rules book stop assuming Морски шах and work for any registered game with 2..9 seats.

**Architecture:** A game is an engine in `ns.Engines` plus an entry in the registry `ns.Games`; everything in `core/` and `ui/` asks the registry. Engines may declare a start mode (`start = "host"`), table options, a `leave` and a `result` function, and session extensions (`ext = {...}`, looked up in `ns.Ext`) that hook into the host's handling of an `ACT`, into every applied event and into "play automatically for me". Death Roll is the engine `deathroll` plus two extensions: `rolls` (turns roll sightings from the chat into events and cross-checks them) and `party` (the host invites seated players into its group). The WoW side only parses the roll line, calls `RandomRoll`/`InviteUnit`/`AcceptGroup`, and feeds the core through new `env` fields; every such call degrades to a visible hint when the client refuses it.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`, modern API), the stage 1 Ace3 subset, the self-written test runner (`bash t.sh`), `tests/helpers/sim.lua` (multi-client simulator) and `tests/helpers/wow.lua` (fake client API + frames).

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.2, 5.3 Death Roll, 5.3а, 6.1, 6.2, 6.3 last bullet, 6.5, 8). Roadmap: `docs/superpowers/plans/2026-11-20-games-roadmap.md`. Mockup: `docs/mockups/03-games.html` (the `droll` panel, `.trail`/`.roll`). Stage 1 plan (format, `env` and message tables): `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md`. Binding rulings: `.superpowers/sdd/2026-11-20-stage1-platform-tictactoe/progress.md`.

## Global Constraints

Everything in `.superpowers/sdd/2026-11-20-stage1-platform-tictactoe/global-constraints.md` still holds (TOC name and `0.1.0`, Lua 5.1 only, no `math.randomseed`, one prefix `TAVG`, GUILD + WHISPER only, full-name identity compared byte-for-byte, `core/` and `engines/` without WoW API or globals and with `env.*` read through the table on every call, only `wow/` and `ui/` touch the API, the three globals, every string through `ns.L` with identical bg/en key sets, the colour and font tokens, 45 s default turn, timeout = automatic move, OneForAll = ideas only, at most one `TBL` per table per 2 s). Added for stage A:

- Protocol stays `v=1`. Stage A adds **no message type**; it adds the optional field `TBL.o` and new action shapes inside `ACT`/`EV` (table below). Point-to-point types stay WHISPER-only.
- Play for fun only: no wagers, ledger, payments or leaderboard; `stake` stays `nil`. A finished game is announced only as the client event `"result"`.
- Engine ids: `ttt`, `deathroll`; registry order `ttt, deathroll, santase, belot, tabla, holdem`. A table has at most `MAX_SEATS = 9` seats.
- Death Roll: `minSeats = 2`, `maxSeats = 6`, start number choices `100, 1000, 10000, 100000` (default `1000`), who rolls 1 loses.
- Roll timing: `ROLL_CLAIM_WAIT = 3`, `ROLL_VERIFY_WAIT = 5`, `ROLL_ECHO_WAIT = 3`, `ROLL_LOG = 20` sightings kept; group: `GROUP_INVITE_GAP = 30`, `PARTY_SIZE = 5`; pending sit/watch: `PENDING_SECONDS = 10`.
- The addon calls `RandomRoll` only from a click on „Хвърли“ or from `/tavern probe roll`. It never calls `SendChatMessage`. Exception to the stage 1 rule "no public-chat output of any kind": a server roll (`RandomRoll`) is the only sanctioned chat-visible output (spec 5.3, 6.3); the real `/roll` is required by spec 5.3. The probe's literal tokens `OK`/`-`/`yes`/`no` count as diagnostic tokens (like the stage 1 probe's `tostring` values), not as strings that need `ns.L`. A timeout or a bot never makes a server roll: the table rolls locally and the entry is tagged.
- Group: only the host's client invites, only players seated at a table whose engine has `needsGroup`, at most once per name per 30 s. The addon never leaves, disbands or converts a group. It accepts a group invite automatically only from the host of the table I am seated at.
- Bot invariant (stage 1 ruling) extends to the new calls: no bot name is ever passed to `env.groupInvite`, and a bot never calls `env.roll`.
- Slash: `/tavern bots [host|invite] [game]`, `/tavern probe [roll]`; the other subcommands are unchanged.
- Commits are local only, never pushed; every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The roll line names the roller differently from the seat** (first name only, full name, own roll as `UnitName`, two seated players with the same first name): the roll must reach the right seat or be ignored, never a wrong seat. Pinned by Task 5 (`finds the seat from a first name…`) and Task 8 (`my own roll is passed under my full name`).
2. **A localized or reordered `RANDOM_ROLL_RESULT`** (`%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)`, magic characters): the pattern must still parse. Pinned by Task 8 (`builds the pattern from positional and plain formats`).
3. **The host cannot see a player's roll** (not grouped, far away): the game must go on and the entry must be marked. Pinned by Task 5 (`a roll the host cannot see is taken as a claim after 3 s`).
4. **Stale, foreign or doubled rolls** (old range, a seat not on turn, an unrelated `/roll 100`, a double click, a forged `src`): none may become an event or be applied twice. Pinned by Task 5 (`chatter never becomes an event`, `a double click rolls once`, `a member cannot forge a seen roll`).
5. **Somebody leaves in the middle of a game with three or more players, or the host leaves mid-turn**: turns skip the leaver, the game continues under the next host, and it ends without a loser when one player remains. Pinned by Task 3 (`a player leaves a three-player game`) and Task 5 (`host leaves mid-turn: the next host takes the roll`).

Also pinned: a bot name reaching `InviteUnit` (Task 7), a snapshot for a game this client does not have (Task 1), a reconnect repeating the `"result"` event (Task 3).

---

## File Structure

```
core/Const.lua             + MAX_SEATS, PENDING_SECONDS, ROLL_*, GROUP_INVITE_GAP, PARTY_SIZE
core/Names.lua             + Names.matches (full name vs the name a chat line shows)
core/Games.lua             NEW registry: order, player counts, engine lookup, table options
core/Session.lua           data, apply, host side, entry points, router; ns.Ext hooks; start/leave/result
core/Member.lua            NEW member side split out of Session.lua (snapshot, events, tick, refusals, ping/sync)
core/Succession.lua        uses Session.seatOf / Session:abortIfShort
core/Lobby.lua             TBL.o, seat-count and option validation
core/Rolls.lua             NEW ns.Rolls + ns.Ext.rolls: sightings, claim, ask, cross-check, client:roll
core/Party.lua             NEW ns.Party + ns.Ext.party: who to invite into the group, auto-accept rule
core/Client.lua            + startGame, playAuto, roll, rollSeen, groupInviteFrom, groupChanged
core/Bots.lua              any game, host-started games, playAuto, env.inGroup wrap, roll forwarding
core/HallLayout.lua        + plates(n, w)
core/Help.lua              + topic "deathroll", block kind "ladder"
engines/tictactoe.lua      + E.result
engines/deathroll.lua      NEW
wow/Adapter.lua            env.random/roll/group/groupInvite wiring
wow/Rolls.lua              NEW ns.RollChat: roll pattern, CHAT_MSG_SYSTEM, PARTY_INVITE_REQUEST, GROUP_ROSTER_UPDATE
wow/Slash.lua              bots host|invite <game>, probe additions, probe roll
ui/HallPeers.lua           NEW „В кръчмата сега“ column split out of Hall.lua
ui/Hall.lua                game list from ns.Games, N chairs, unknown game
ui/NewTableDialog.lua      option rows from the engine
ui/TableFrame.lua          plate grid, „Започни“/„Нова игра“, banners
ui/games/DeathRollView.lua NEW
ui/HelpBook.lua            + BLOCKS.ladder
locale/bg.lua  locale/en.lua
tests/helpers/sim.lua      + env.random/roll/group/groupInvite fakes
tests/helpers/pick_engine.lua NEW test engine "pick" (host-started, 2–4 seats, options, leave, result, ext)
tests/helpers/wow.lua      + roll/party API fakes
docs/superpowers/notes/2026-11-stageA-ingame-checks.md NEW
```

TOC order (`# Core`): `Const, Util, Names, Emitter, Bus, Trace, Games, Presence, Lobby, Succession, Session, Member, Rolls, Party, Invites, Client, Bots, Locale, Help, HallLayout, Wire`. `# Engines`: `tictactoe, deathroll`. `# WoW`: `Adapter, Rolls, Slash`. `# UI`: `HallPeers` directly before `Hall`; `games/DeathRollView` directly after `games/TicTacToeView`. Modules loaded before `engines/` look engines up at call time only.

### Shared contracts (additions to the stage 1 plan's section)

**Engine contract, optional additions** (an engine without them behaves as in stage 1):

| field | meaning |
|---|---|
| `E.start` | `"host"`: the game starts only on `client:startGame()`; absent: starts when every seat is filled |
| `E.options` | array of `{id, choices = {…}, default}`; the chosen values travel as `TBL.o` and reach `E.new` as `opts.opt` |
| `E.new(opts)` | `opts.first` (seat), `opts.seats` (array of booleans, `true` = occupied at start), `opts.opt` (resolved options) |
| `E.auto(state, seat, random)` | third argument `random(lo, hi) -> integer` (the session passes `env.random`) |
| `E.leave(state, seat)` | called on a `stand` event while live; must not fail |
| `E.result(state)` | `nil`, or `{winners = {seat,…}, losers = {seat,…}}` once a game has ended with an outcome |
| `E.over(state)` | `true` when the game has ended and a new one may start; absent: over = `E.result(state) ~= nil` |
| `E.nextFirst(prevState, occupied)` | seat that starts the next game (host only; default: lowest occupied seat) |
| `E.needsGroup` | `true`: players must share a group (extension `party`) |
| `E.ext` | array of names in `ns.Ext` |

**`ns.Ext[name]`** = `{ act = fn(s, seat, a) -> a2|nil, applied = fn(s, seat, a), auto = fn(s) -> true|nil }` (all optional). `act`: host only, on a member's `ACT` before it is played; `nil` drops or holds it. `applied`: host and members, after every applied event (table events have `seat == 0`). `auto`: any seated client, "make my automatic move"; `true` = handled.

**`env` additions** (all optional; a bot's env has only `random`):

| field | meaning |
|---|---|
| `random(lo, hi)` | integer in `lo..hi` (`math.random` in game) |
| `roll(lo, hi)` | make a server roll (`RandomRoll`); absent when the client has no such function |
| `group()` | `{grouped, leader, raid, size}` of my own group |
| `groupInvite(name)` | invite the full name into my group |

**Protocol additions** (`v=1`, no new `t`):

| where | addition | meaning |
|---|---|---|
| `TBL` (and `SNP.tbl`) | `o` | table options `{id = value}`; omitted when the engine has none |
| `EV` seat 0 | `{k="start", first}` | `first` = seat that begins; absent or not occupied → lowest occupied seat |
| `ACT`, Death Roll | `{k="roll", n, max}` | "I rolled `n` in `1..max`" (the roller's claim) |
| `ACT`, Death Roll | `{k="roll", max, src="ask"}` | "roll for me" (a bot, or a client without `RandomRoll`) |
| `EV`, Death Roll | `{k="roll", n, max, src}` | `src` `"seen"` (host saw the server roll), `"claim"` (host could not see it), `"ask"`, `"timeout"` |

**Client events added:** `"result"({tid, game, opt, seats, winners, losers, at})` (`seats` = names by seat at that moment, `at` = `env.epoch()`), `"rollSeen"(shown, n, lo, hi)`.

**Test commands:** as in stage 1 (`bash t.sh`, `bash t.sh <file-or-dir>`; success ends `N passed, 0 failed`). A `--[[ … ]]` body states the assertions in words; write them out with exactly those values. Names in tests: `A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"`; `a, b, c, d` their clients.

---

### Task 1: Split the member side out of Session.lua; shared helpers; two deferred fixes

**Files:**
- Create: `core/Member.lua`; Modify: `core/Session.lua`, `core/Succession.lua`, `core/Const.lua`, `TavernGames.toc`; Test: `tests/core/member_test.lua`

**Interfaces:**
- Produces: `ns.Util.seatOf(seats, name) -> seat|nil`, with `ns.Session.seatOf = ns.Util.seatOf` (the copies in `Succession.lua` and `Session.lua` go away; `core/Succession.lua` loads before `core/Session.lua`, so it uses `ns.Util.seatOf`, never a file-scope `ns.Session.seatOf`); `ns.Session.message`, `ns.Session.emit` and `ns.Session.refuse` are exported (the former file-locals of `Session.lua`) for `Member.lua` and `Succession.lua`, which call them through `ns.Session` at call time; no helper is copied into another file; `Session:abortIfShort() -> bool` (host: when `status == "live"` and `seatedCount() < engine.minSeats`, emits the `abort` event; replaces the copies in `Session:onStand`, `Succession.sweep`, `Succession.handoff`); `ns.Member.handlers` = `{SNP, EV, TCK, SNO, END}` each `fn(client, sender, m)`, called by `Session.receive`; `ns.Member.adopt(client, sender, m)`. `Session:schedulePing` and `Session:requestSync` move to `core/Member.lua` unchanged. `Const.PENDING_SECONDS = 10`.
- Behaviour kept byte-for-byte except:
  - (final review M1) an `SNP` that fails validation, whose `tbl.s` is a table listing my own name, for a table that is not my current session, is answered with a whispered `STD{tid}` to its sender.
  - (M2) `Session.request` arms a `PENDING_SECONDS` timer when it sets `client.pending`; if the same pending is still there on expiry: `client.pending = nil`, `client.gaveUp = tid`, event `"refused"(tid, "gone")`.

- [ ] **Step 1: Write the failing tests** (`tests/core/member_test.lua`).

```lua
it("a snapshot for a game I do not have is answered with STD", function()
  -- a, b in one sim, sim:run(1)
  b:receive("WHISPER", A, {v=1, t="SNP", tid="x#1", e=1, q=0,
    tbl={tid="x#1", g="nope", h=A, e=1, ac="guild", tn=45, st="open", s={A, B}, w=0}}); sim:run(1)
  local std = {}; for _, s in ipairs(sim.sent) do if s.from == B and s.msg.t == "STD" then std[#std+1] = s end end
  eq(#std, 1); eq(std[1].target, A); eq(std[1].msg.tid, "x#1"); eq(b.session, nil)
end)
it("an unanswered sit request gives up after 10 s with 'gone'", function()
  -- a opens a ttt table, sim:run(3); sim:offline(A); b:sit(tid, 2); record b's "refused" calls
  sim:run(9); eq(#refused, 0); sim:run(2); eq(refused, {{tid, "gone"}}); eq(b.pending, nil)
end)
it("an answer after giving up frees the seat again", function() --[[ as above, then sim:online(A); a:receive("WHISPER", B, {v=1,t="SIT",tid=tid,seat=2});
  sim:run(2): b.session == nil; a.session.seats == {A, false} ]] end)
it("seatOf and abortIfShort", function()
  eq(ns.Util.seatOf({"a", false, "c"}, "c"), 3); eq(ns.Util.seatOf({"a"}, "z"), nil); eq(ns.Session.seatOf, ns.Util.seatOf)
  --[[ ttt live with a, b: a.session.seats[2] = false; eq(a.session:abortIfShort(), true); eq(a.session.status, "aborted");
  a second call returns false ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/member_test.lua`.** Expected: FAIL (`seatOf` nil, no `STD`, no refusal).
- [ ] **Step 3: Implement.** Move `adopt`, `onSnapshot`, `onEvent`, `onTick`, `onRefusal`, `onEnd`, `schedulePing`, `requestSync` to `core/Member.lua`; `Session.receive` dispatches `ns.Member.handlers[t]`. Add the TOC line after `core/Session.lua`. `core/Session.lua` must end below 540 lines (only the member side moves; the entry points stay).
- [ ] **Step 4: Run `bash t.sh tests/core/member_test.lua`, then `bash t.sh`.** Expected: `4 passed, 0 failed`; then everything passes (231).
- [ ] **Step 5: Commit.** `git add core/Member.lua core/Session.lua core/Succession.lua core/Const.lua TavernGames.toc tests/core/member_test.lua` — `refactor(core): split member side out of Session; pending timeout; STD for an unusable snapshot`

### Task 2: Game registry and table options

**Files:**
- Create: `core/Games.lua`; Modify: `core/Const.lua`, `core/Session.lua`, `core/Member.lua`, `core/Lobby.lua`, `TavernGames.toc`; Test: `tests/core/games_test.lua`

**Interfaces:**
- Produces:
  - `ns.Games.ORDER = {"ttt","deathroll","santase","belot","tabla","holdem"}`; `ns.Games.PLAYERS = {ttt="2", deathroll="2–6", santase="2", belot="4", tabla="2", holdem="2–9"}`.
  - `ns.Games.list() -> { {id, players, engine = E|nil}, … }` in `ORDER`; `ns.Games.engine(id) -> E|nil` (nil for a non-string id).
  - `ns.Games.resolve(id, opt) -> table|nil` — nil when the engine is unknown, `opt` is neither nil nor a table, a key is not an option id, or a value is not among that option's `choices`; otherwise a new table with every option id set (given value or `default`). An engine without `options` gives `{}`.
  - `Const.MAX_SEATS = 9`.
  - `client:openTable{game, access, turn, opt}` — new refusal code `"opt"`. Session field `opt` (resolved table). `Session:record()` adds `o = opt` only when `next(opt) ~= nil`. Lobby record field `opt` (`copy(m.o)`, nil when absent). `Member.adopt` sets `s.opt = Games.resolve(t.g, t.o)`.
  - `Lobby.valid(m)` additionally requires: `#m.s <= 9`; `m.o` nil or a table; and for a known engine `#m.s == engine.maxSeats` and `Games.resolve(m.g, m.o) ~= nil`. A record of an unknown game stays valid (it is listed, not joinable).
  - `Session.request`: when the lobby record's game has no engine here → `"refused"(tid, "version")`, nothing is sent.

- [ ] **Step 1: Write the failing tests.** The file registers a test engine `optgame` in `Sim.ns.Engines`: a shallow field copy of the fake engine (`local E = {}; for k, v in pairs(Fake) do E[k] = v end`, with `Fake = require("fake_engine")` as the other tests load it), overriding only `id="optgame"` and `options = { {id="goal", choices={2,3}, default=2} }`; no function body is copied.

```lua
it("lists the six games in order with their player counts", function()
  local l = G.list(); eq(#l, 6); eq(l[1].id, "ttt"); eq(l[1].players, "2"); ok(l[1].engine == ns.Engines.ttt)
  eq(l[2].id, "deathroll"); eq(l[2].players, "2–6"); eq(l[6].id, "holdem"); eq(l[6].engine, nil); eq(G.engine(42), nil)
end)
it("resolve fills defaults and rejects what the engine does not offer", function()
  eq(G.resolve("ttt", nil), {}); eq(G.resolve("optgame", nil), {goal=2}); eq(G.resolve("optgame", {goal=3}), {goal=3})
  eq(G.resolve("optgame", {goal=5}), nil); eq(G.resolve("optgame", {x=1}), nil); eq(G.resolve("optgame", "3"), nil)
  eq(G.resolve("nope", nil), nil); eq(G.resolve("ttt", {goal=2}), nil)
end)
it("options travel with the table", function()
  local tid = a:openTable{game="optgame", access="guild", turn=45, opt={goal=3}}; sim:run(3)
  eq(a.session.opt, {goal=3}); eq(b.lobby:get(tid).opt, {goal=3}); b:sit(tid, 2); sim:run(1); eq(b.session.opt, {goal=3})
  eq({c:openTable{game="optgame", access="guild", turn=45, opt={goal=9}}}, {nil, "opt"})
end)
it("a ttt TBL carries no o field", function() --[[ a opens ttt; sim:run(3): every sent TBL from A has msg.o == nil ]] end)
it("Lobby.valid: seat count and options", function() --[[ base = a valid ttt TBL table; valid; with s of 10 entries -> false;
  with s = {A} (ttt has 2) -> false; g="optgame", s of 3, o={goal=9} -> false; o="x" -> false; g="nope", s={A,false} -> true ]] end)
it("a table of a game I do not have is listed but cannot be joined", function()
  b:receive("GUILD", A, {v=1,t="TBL",tid="x#1",g="nope",h=A,e=1,ac="guild",tn=45,st="open",s={A,false},w=0})
  local n = #sim.sent; b:sit("x#1", 2); eq(refused, {{"x#1", "version"}}); eq(#sim.sent, n); eq(b.lobby:get("x#1").game, "nope")
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/games_test.lua`.** Expected: FAIL (`Games` is nil).
- [ ] **Step 3: Implement** and add `core/Games.lua` to the TOC after `core/Trace.lua`. If an existing test hand-builds a `TBL` whose seat count does not fit its engine, correct that test's record, not the rule. Known case: `tests/core/lobby_test.lua:212-225` (the epoch-tie test from 98cee4d) sends `ttt` TBLs with `s = {D, E, F}` (3 seats); switch those four records to `g = "fake"` (with `require("fake_engine")` registered) so the test still tests the tie.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `6 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Games.lua core/Const.lua core/Session.lua core/Member.lua core/Lobby.lua TavernGames.toc tests/core/games_test.lua tests/core/lobby_test.lua` (plus every other existing test file corrected in Step 3) — `feat(core): game registry and per-game table options`

### Task 3: N-seat game lifecycle — host start, leaving, results, extensions

**Files:**
- Create: `tests/helpers/pick_engine.lua`; Modify: `core/Session.lua`, `core/Member.lua`, `core/Client.lua`, `engines/tictactoe.lua`, `tests/helpers/sim.lua`; Test: `tests/core/lifecycle_test.lua`

**Interfaces:**
- Consumes: Task 2 `opt`; the engine and `ns.Ext` contracts above.
- Produces:
  - `ns.Ext = {}` (created in `core/Session.lua`); `Session:hook(name, ...)` — calls `ns.Ext[x][name](self, ...)` for every `x` in `engine.ext` that has it, returns the first non-nil result; `Session:filterAct(seat, a) -> a|nil` — chains every `act` hook, stops at the first nil. `hook` and `filterAct` skip an `x` when `ns.Ext[x]` is nil (Task 4 depends on it: `deathroll` lists `rolls`/`party` before they exist); the `pick` test engine therefore lists `ext = {"picktest", "absent"}`.
  - `client:startGame() -> true | nil, code` — codes in this order: `"none"` (no session), `"nothost"`, `"mode"` (engine has no `start == "host"`), `"short"` (seated < `minSeats`), `"live"` (status `"live"` and the game is not over: `engine.over(state)` when the engine has it, else `engine.result(state) ~= nil`). Emits `{k="start", first = engine.nextFirst and engine.nextFirst(state, occupied) or <lowest occupied seat>}`.
  - `client:playAuto() -> true | nil, code` — `"none"/"seat"/"live"` as `client:act`; then `session:hook("auto")`; when no hook handled it: `client:act(engine.auto(state, mySeat, env.random))` (`nil, "turn"` when `auto` returns nil).
  - Event `"result"` (payload above), emitted by `Session:apply` on host and members when `engine.result(state)` turns from nil to non-nil; `Member.adopt` records the current value without emitting.
  - `engines/tictactoe.lua`: `E.result(state)` = `{winners={winner}, losers={3 - winner}}` in phase `"match"`, else nil.
  - Sim: `env.random(lo, hi)` = `table.remove(sim.nextRandom, 1) or hi` (`sim.nextRandom = {}`), also on `sim.makeEnv` envs.
- Rules:
  - `Session:startIfFull` does nothing for `start == "host"`.
  - `Session:apply` for `start`: `occupied[i] = seats[i] ~= false`; `first` = `a.first` when that seat is occupied, else the lowest occupied seat; `state = engine.new{first = first, seats = occupied, opt = copy(self.opt)}`. For `stand` while `status == "live"` with a state: `engine.leave(state, a.seat)` when the engine has it. `Session:event` skips `armTimers` for `sit` and for a `stand` that leaves `state.turn` unchanged (stage 1 ruling), but a `stand` that changes `state.turn` re-arms the timers: a fresh full turn for the new player on turn (otherwise the timer keeps the leaver's seat and the next player never times out); the offline sweep stand does the same. A player may sit on a free chair while a game runs; the engine decides when he plays (he is in the next `start`).
  - Host: `Session:onAct` plays `self:filterAct(seat, a)` (dropped when nil). `Session:event` calls `self:hook("applied", seat, a)` after every applied event; `Member`'s `EV` handler does the same. The turn timer calls `engine.auto(state, seat, client.env.random)`.
  - `tests/helpers/pick_engine.lua` registers in `Sim.ns`: engine `pick` — `minSeats=2, maxSeats=4, start="host", ext={"picktest", "absent"}, options={{id="goal", choices={2,3}, default=2}}`; state `{players (occupied seats ascending), turn, n={0,0,0,0}, goal, winner}`; action `{k="inc", by}` by the seat on turn adds `by` to `n[seat]`, at `goal` sets `winner` and `turn=nil`, else the turn goes to the next seat in `players`; `leave` removes the seat and passes its turn on; `result` = nil until `winner` is set (never at `start`, or `#ra == 1` breaks), then `{winners={winner}, losers=<the other players>}`; `nextFirst(prev, occupied)` = `prev.winner` when occupied; `auto(state, seat, random)` = `{k="inc", by=random(1, 1)}` for the seat on turn, nil for a seat that is not on turn. Extension `picktest`: `act` returns nil for `a.k == "drop"`, else `{k="inc", by=1}`; `applied` appends `a.k` to `s.appliedLog`.

- [ ] **Step 1: Write the failing tests.**

```lua
it("a host-started game waits for the host", function()
  local tid = a:openTable{game="pick", access="guild", turn=45}; sim:run(3); b:sit(tid, 2); c:sit(tid, 3); sim:run(1)
  eq(a.session.status, "open"); eq({b:startGame()}, {nil, "nothost"}); ok(a:startGame()); sim:run(1)
  eq(c.session.status, "live"); eq(c.session.state.players, {1,2,3}); eq(c.session.state.turn, 1); eq(c.session.state.goal, 2)
end)
it("startGame refusals", function() --[[ no table: {nil,"none"}; ttt table: {nil,"mode"}; pick alone: {nil,"short"};
  pick running: {nil,"live"} ]] end)
it("a newcomer waits for the next game; the result is announced once; the winner starts", function()
  -- running game of a, b, c; d:sit(tid, 4); sim:run(1); "result" handlers on a, b, c, d collect into lists
  eq(d.session.state.players, {1,2,3})
  ok(a:act{k="inc", by=1}); sim:run(1); ok(b:act{k="inc", by=1}); sim:run(1); ok(c:act{k="inc", by=1}); sim:run(1)
  ok(a:act{k="inc", by=1}); sim:run(1)
  for _, got in ipairs{ra, rb, rc, rd} do eq(#got, 1); eq(got[1].winners, {1}); eq(got[1].losers, {2,3})
    eq(got[1].seats, {A,B,C,D}); eq(got[1].game, "pick"); eq(got[1].tid, tid); eq(got[1].opt, {goal=2}) end
  ok(a:startGame()); sim:run(1); eq(d.session.state.players, {1,2,3,4}); eq(d.session.state.turn, 1); eq(#ra, 1)
end)
it("a player leaves a three-player game: play goes on without his turns, and aborts below two", function()
  -- a, b, c live; a and b act once so it is seat 3's turn
  c:stand(); sim:run(1); eq(a.session.status, "live"); eq(b.session.state.players, {1,2}); eq(b.session.state.turn, 1)
  b:stand(); sim:run(1); eq(a.session.status, "aborted")
end)
it("a player on turn who leaves does not stall the next player's timer", function()
  -- a, b, c live; a and b act once so it is seat 3's turn; sim.nextRandom = {1}
  c:stand(); sim:run(1); eq(a.session.state.turn, 1); sim:run(46)
  eq(#sim.nextRandom, 0); eq(a.session.state.n[1], 2)   -- auto played for seat 1 after a fresh full turn
  --[[ a plain sit while a turn runs does not re-arm: the running player's timeout still fires at its original time ]]
end)
it("the act hook rewrites and drops a member's ACT", function() --[[ b's turn: a:receive("WHISPER", B, {v=1,t="ACT",tid=tid,a={k="inc",by=99}});
  a.session.state.n[2] == 1; then c's turn: ACT {k="drop"} from C leaves a.session.seq unchanged ]] end)
it("applied sees table and game events on host and members", function() --[[ after start and one inc the last two entries of
  a.session.appliedLog and of b.session.appliedLog are {"start","inc"} ]] end)
it("the turn timeout plays auto with env.random", function() --[[ sim.nextRandom = {1}; sim:run(46): #sim.nextRandom == 0;
  a.session.state.n[1] == 1; the EV to B has auto == true ]] end)
it("playAuto makes my move", function() --[[ a's turn: ok(a:playAuto()); n[1] == 1; eq({a:playAuto()}, {nil, "turn"}) ]] end)
it("a reconnect snapshot does not repeat the result", function() --[[ game over (winner 1); b2 = sim:relog(B) with a "result" counter;
  sim:run(2): counter == 0; b2.session.state.winner == 1 ]] end)
it("Морски шах announces its match result once on every client", function() --[[ a, b seated, c watching; X wins three rounds:
  each of a, b, c got exactly one "result" with winners {1}, losers {2}, game "ttt" ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/lifecycle_test.lua`.** Expected: FAIL (`startGame` is nil).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `11 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Session.lua core/Member.lua core/Client.lua engines/tictactoe.lua tests/helpers/sim.lua tests/helpers/pick_engine.lua tests/core/lifecycle_test.lua` — `feat(core): host-started games, leaving mid-game, result event, session extensions`

### Task 4: Death Roll engine

**Files:**
- Create: `engines/deathroll.lua`; Modify: `TavernGames.toc`; Test: `tests/engines/deathroll_test.lua`

**Interfaces:**
- Produces `ns.Engines.deathroll`:
  - `E.id="deathroll"`, `E.minSeats=2`, `E.maxSeats=6`, `E.start="host"`, `E.needsGroup=true`, `E.ext={"rolls","party"}`, `E.options={{id="start", choices={100,1000,10000,100000}, default=1000}}`, `E.SOURCES={seen=true, claim=true, ask=true, timeout=true}`.
  - `E.new(opts) -> state`: `players` (occupied seats ascending), `turn` (`opts.first` when occupied, else `players[1]`), `start` and `max` (`opts.opt.start`, 1000 when absent), `rolls = {}`, `phase = "play"`, `loser = nil`.
  - `E.apply(state, seat, a) -> true | nil, code`, checked in this order: `"action"` (`a` not a table or `a.k ~= "roll"`), `"phase"` (not `"play"`), `"turn"`, `"max"` (`a.max ~= state.max`), `"n"` (not an integer in `1..max`), `"src"` (not in `E.SOURCES`). Effect: appends `{seat, n, max, src}` (named fields) to `rolls`; `n == 1` → `phase="over"`, `loser=seat`, `turn=nil`; otherwise `max = n` and the turn goes to the next seat in `players` (cyclic). A rejected action leaves the state untouched.
  - `E.legal(state, seat)` = `{{k="roll", max=state.max}}` for the seat on turn, else `{}`. `E.auto(state, seat, random)` = `{k="roll", n=(random or math.random)(1, state.max), max=state.max, src="timeout"}` for the seat on turn, else nil. `E.system()` = nil.
  - `E.leave(state, seat)`: removes the seat from `players`; in phase `"play"`: fewer than 2 players left → `phase="over"`, `loser=nil`, `turn=nil`; else if it was that seat's turn the turn goes to the player that followed it.
  - `E.result(state)` = `{losers={loser}, winners=<the other seats in players>}` when `phase == "over"` and `loser`; else nil. `E.over(state)` = `phase == "over"` (a game that ended without a loser has no result but may be restarted).
  - `E.nextFirst(prev, occupied)` = `prev.loser` when `prev` and that seat is occupied, else nil. `E.snapshot`/`E.restore` = deep copy.

- [ ] **Step 1: Write the failing tests.**

```lua
local E = Loader.ns().Engines.deathroll
local function new(seats, first, start) return E.new{seats=seats, first=first, opt={start=start or 100}} end
local function roll(s, seat, n, src) return E.apply(s, seat, {k="roll", n=n, max=s.max, src=src or "seen"}) end
it("declares its contract", function()
  eq({E.id, E.minSeats, E.maxSeats, E.start, E.needsGroup}, {"deathroll", 2, 6, "host", true}); eq(E.ext, {"rolls","party"})
  eq(E.options, {{id="start", choices={100,1000,10000,100000}, default=1000}}); eq(E.new{seats={true,true}}.max, 1000)
end)
it("two players roll down to 1 and the roller of 1 loses", function()
  local s = new({true,true}, 1); eq(s.players, {1,2}); eq(s.turn, 1); eq(s.max, 100)
  ok(roll(s,1,57)); eq(s.max, 57); eq(s.turn, 2); ok(roll(s,2,12)); ok(roll(s,1,3)); ok(roll(s,2,1))
  eq(s.phase, "over"); eq(s.loser, 2); eq(s.turn, nil); eq(#s.rolls, 4)
  eq(s.rolls[1], {seat=1, n=57, max=100, src="seen"}); eq(E.result(s), {losers={2}, winners={1}}); eq(E.over(s), true)
end)
it("rejects in order: action, phase, turn, max, n, src; the state is untouched", function()
  local s = new({true,true}, 1); local before = E.snapshot(s)
  eq({E.apply(s, 1, {k="mark"})}, {nil,"action"}); eq({roll(s,2,5)}, {nil,"turn"})
  eq({E.apply(s, 1, {k="roll", n=5, max=99, src="seen"})}, {nil,"max"})
  for _, n in ipairs{0, 101, 1.5} do eq({roll(s,1,n)}, {nil,"n"}) end
  eq({roll(s,1,5,"magic")}, {nil,"src"}); eq(E.snapshot(s), before)
  ok(roll(s,1,1)); eq({roll(s,2,1)}, {nil,"phase"})
end)
it("rolling the cap keeps the cap and passes the turn", function()
  local s = new({true,true}, 1); ok(roll(s,1,100)); eq(s.max, 100); eq(s.turn, 2)
end)
it("skips empty seats, honours first, falls back to the lowest seat", function()
  local s = new({true,false,true,true}, 3, 1000); eq(s.players, {1,3,4}); eq(s.turn, 3)
  ok(roll(s,3,500)); eq(s.turn, 4); ok(roll(s,4,400)); eq(s.turn, 1); eq(new({true,false,true}, 2).turn, 1)
end)
it("leave: the turn moves on; one player left ends the game without a loser", function()
  local s = new({true,true,true}, 2); E.leave(s, 2); eq(s.players, {1,3}); eq(s.turn, 3); eq(s.phase, "play")
  E.leave(s, 3); eq(s.phase, "over"); eq(s.loser, nil); eq(s.turn, nil); eq(E.result(s), nil); eq(E.over(s), true)
end)
it("auto uses the injected random and is tagged timeout", function()
  local s = new({true,true}, 1)
  eq(E.auto(s, 1, function(lo, hi) eq({lo, hi}, {1, 100}); return 42 end), {k="roll", n=42, max=100, src="timeout"})
  eq(E.auto(s, 2, function() return 1 end), nil); eq(E.legal(s, 1), {{k="roll", max=100}}); eq(E.legal(s, 2), {})
end)
it("the loser starts the next game while still seated", function()
  local s = new({true,true}, 1); ok(roll(s,1,1)); eq(E.nextFirst(s, {true,true}), 1); eq(E.nextFirst(s, {false,true}), nil)
  eq(E.nextFirst(nil, {true,true}), nil)
end)
it("snapshot round-trips and is a copy", function() --[[ as the ttt test: mutate the snapshot's rolls, state unchanged; restore(snapshot) equal ]] end)
it("a game that ended without a loser can be started again", function() --[[ with Sim: a hosts deathroll, b sits, a:startGame();
  c sits mid-game (seat 3); b:stand(); sim:run(1): a.session.status == "live" (two still seated), state.phase == "over", state.loser == nil,
  no "result" event on a; ok(a:startGame()); sim:run(1): c.session.state.players == {1,3}, phase "play" ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/engines/deathroll_test.lua`.** Expected: FAIL (`deathroll` is nil).
- [ ] **Step 3: Implement** `engines/deathroll.lua` and its TOC line. (`ns.Ext.rolls`/`party` do not exist yet: `Session:hook` skips unknown names.)
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `10 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add engines/deathroll.lua TavernGames.toc tests/engines/deathroll_test.lua` — `feat: death roll engine`

### Task 5: Rolls — sightings, claims, table rolls, cross-check

**Files:**
- Create: `core/Rolls.lua`; Modify: `core/Names.lua`, `core/Const.lua`, `core/Client.lua`, `tests/helpers/sim.lua`, `TavernGames.toc`; Test: `tests/core/rolls_test.lua`

**Interfaces:**
- Consumes: Task 3 hooks, Task 4 engine, `env.roll`, `env.random`.
- Produces:
  - `ns.Names.first(name) -> string` — the first word of `name` (the one copy of that rule; `Names.matches`, `sim.rollName` and, later, `W.firstWord` use it).
  - `ns.Names.matches(full, shown) -> bool` — `shown == full`, or `shown` contains no space and equals `Names.first(full)`.
  - `ns.Rolls.roll(client) -> true | nil, code` — the body of `client:roll` (same codes); `client:roll` delegates to it, and the `auto` hook calls it.
  - `ns.Rolls.seatFor(seats, shown) -> seat|nil` — the only seat whose name `matches`; nil when none or more than one.
  - `client:rollSeen(shown, n, lo, hi)` — a server roll seen in chat (`shown` already normalized; my own roll arrives as `env.me`). Emits `"rollSeen"(shown, n, lo, hi)` first, always.
  - `client:roll() -> true | nil, code` (delegates to `ns.Rolls.roll(client)`) — `"none"`, `"seat"`, `"live"`, `"turn"` (not my turn), `"wait"` (my roll is already under way).
  - `ns.Rolls.check(session, index) -> "ok"|"unseen"|"mismatch"|nil` — what this client saw of `state.rolls[index]`.
  - Session fields (local, never sent): `rollLog` (sightings `{seat, n, max, at}`, newest last, at most `ROLL_LOG`), `rollCheck` (index → verdict), `rolling` (`{seen=bool}` or nil), `rollStuck` (bool), `claim` (`{seat, n, max}` or nil).
  - `ns.Ext.rolls = {act, applied, auto}`.
  - Sim: `env.roll(lo, hi)` on every `sim:add` client unless `opts.roll == false` (never on `sim.makeEnv` envs): `n = table.remove(sim.nextRolls, 1) or hi`; appends `{from=, lo=, hi=, n=}` to `sim.rolled`; through `env.after(0, …)` calls `rollSeen` on every client `to` for which `sim.canSee(from, to)` is true, with `from` itself for the roller and `sim.rollName(from)` for the others. Defaults: `sim.nextRolls = {}`, `sim.canSee = function() return true end`, `sim.rollName` = `Names.first` of the name. `Sim:add` stores its `opts` per name and `sim:relog` rebuilds the env from those stored options (not from `{cls, db}` only), so `env.roll` survives a relog.
- Rules (the trust model):
  1. **Sighting.** `rollSeen` is ignored unless I am at a table whose engine lists `rolls`, `lo == 1`, `n` and `hi` are integers and `seatFor` finds a seat. It is logged. Then, when the match is live, the seat is on turn and `hi == state.max`: the **host** plays `{k="roll", n, max=hi, src="seen"}` for that seat; a **member whose own seat it is** whispers `ACT{a={k="roll", n, max=hi}}` to the host and sets `rolling = {seen = true}` (`rolling` may be nil here: after the stuck hint the player types `/roll` by hand).
  2. **Claim** (`act` hook, host): an `ACT` roll is dropped unless `a.max == state.max` and the sender's seat is on turn. `a.src == "ask"` → returns `{k="roll", n=env.random(1, max), max, src="ask"}`. Otherwise `n` must be an integer in `1..max`; the host holds it (`s.claim`) and after `ROLL_CLAIM_WAIT`, if the same seat is still on turn at the same `max`, plays it with `src="claim"`. The hook itself returns nil. Whatever `src` the member sent is ignored.
  3. **`client:roll()`** with `env.roll`: sets `rolling = {seen=false}`, calls `env.roll(1, state.max)`; after `ROLL_ECHO_WAIT` with `rolling` still set and not `seen`: `rolling = nil`, `rollStuck = true`, `"session"` is emitted (the UI then tells the player to type `/roll` by hand). Without `env.roll`: the host plays `{…, n=env.random(1, max), src="ask"}` at once; a member whispers `ACT{a={k="roll", max, src="ask"}}` and sets `rolling = {seen=true}`.
  4. **Applied** (`applied` hook, `a.k == "roll"`): sets `rolling = nil`, `rollStuck = false`, `claim = nil`. For `src` `"seen"`/`"claim"` the entry's verdict is `"ok"` as soon as the log holds a sighting with the same seat, `max` and `n`; otherwise, `ROLL_VERIFY_WAIT` after the event, `"mismatch"` when the log holds a sighting with the same seat and `max` but another `n`, else `"unseen"`; a matching sighting that arrives later turns it into `"ok"`. `"ask"`/`"timeout"` entries get no verdict. On `a.k == "start"`: `rollCheck = {}`. A verdict change emits `"session"`.
  5. **Timeout** needs no hook: the turn timer plays `E.auto` (`src="timeout"`, `EV.auto = true`).
  6. Timers go through `client:after`; every callback first checks that `client.session` is still the same table.
  7. `auto` hook: `Rolls.roll(client)` (produced above; `client:roll` is its wrapper); returns true.

- [ ] **Step 1: Write the failing tests.** `setup(n, opts)` = a sim with the first `n` of `a, b, c`, `a` hosting `deathroll` with `opt={start=100}`, everyone seated, `a:startGame()`, `sim:run(1)` (seat 1 on turn).

```lua
it("finds the seat from a first name, a full name, and refuses two candidates", function()
  local R, N = ns.Rolls, ns.Names
  eq(N.matches("Иван Петров", "Иван"), true); eq(N.matches("Иван Петров", "Иван Петров"), true)
  eq(N.matches("Иван Петров", "Петров"), false); eq(N.matches("Иван Петров", "Иван Иванов"), false)
  eq(R.seatFor({A, B}, "Иван"), 1); eq(R.seatFor({A, false, C}, "Kiro Barley"), 3); eq(R.seatFor({A, B}, "Гошо"), nil)
  eq(R.seatFor({A, "Иван Димов"}, "Иван"), nil); eq(R.seatFor({A, "Иван Димов"}, "Иван Димов"), 2)
end)
it("the host sees a roll and everybody records it as seen and checked", function()
  sim.nextRolls = {57}; ok(a:roll()); sim:run(1)
  eq(b.session.state.rolls, {{seat=1, n=57, max=100, src="seen"}}); eq(b.session.state.max, 57); eq(b.session.state.turn, 2)
  eq(ns.Rolls.check(a.session, 1), "ok"); eq(ns.Rolls.check(b.session, 1), "ok"); eq(sim.rolled, {{from=A, lo=1, hi=100, n=57}})
end)
it("a guest's roll seen by the host needs no claim wait", function()
  sim.nextRolls = {57, 12}; a:roll(); sim:run(1); ok(b:roll()); sim:run(1)
  eq(a.session.state.rolls[2], {seat=2, n=12, max=57, src="seen"})
end)
it("a roll the host cannot see is taken as a claim after 3 s and marked", function()
  sim.canSee = function(from, to) return from == to end
  sim.nextRolls = {57, 12}; a:roll(); sim:run(1); ok(b:roll()); sim:run(2); eq(#a.session.state.rolls, 1)
  sim:run(2); eq(a.session.state.rolls[2], {seat=2, n=12, max=57, src="claim"}); sim:run(6)
  eq(ns.Rolls.check(a.session, 2), "unseen"); eq(ns.Rolls.check(b.session, 2), "ok")
end)
it("chatter never becomes an event", function()
  local q = a.session.seq
  a:rollSeen("Мария", 5, 1, 100)    -- not on turn
  a:rollSeen("Иван", 5, 1, 50)      -- wrong range
  a:rollSeen("Иван", 5, 2, 100)     -- lo ~= 1
  a:rollSeen("Гошо", 5, 1, 100)     -- not seated
  a:rollSeen("Иван", 5.5, 1, 100); sim:run(1); eq(a.session.seq, q); eq(#a.session.state.rolls, 0)
end)
it("a double click rolls once", function()
  ok(a:roll()); eq({a:roll()}, {nil, "wait"}); sim:run(1); eq(#sim.rolled, 1); eq({a:roll()}, {nil, "turn"})
end)
it("a member cannot forge a seen roll", function()
  sim.nextRolls = {57}; a:roll(); sim:run(1)
  a:receive("WHISPER", B, {v=1, t="ACT", tid=a.session.tid, a={k="roll", n=30, max=57, src="seen"}}); sim:run(1)
  eq(#a.session.state.rolls, 1); sim:run(3); eq(a.session.state.rolls[2], {seat=2, n=30, max=57, src="claim"})
  a:receive("WHISPER", B, {v=1, t="ACT", tid=a.session.tid, a={k="roll", n=1, max=57}}); sim:run(4); eq(#a.session.state.rolls, 2)   -- stale range, not on turn
end)
it("a client without /roll asks the table", function()
  -- setup(2, {B = {roll=false}}); a rolls 57; sim.nextRandom = {42}
  ok(b:roll()); sim:run(1); eq(a.session.state.rolls[2], {seat=2, n=42, max=57, src="ask"})
  eq(ns.Rolls.check(a.session, 2), nil); eq(#sim.rolled, 1)
end)
it("timeout: the table rolls, tagged, nobody loses by the clock", function()
  sim.nextRandom = {33}; sim:run(46); eq(b.session.state.rolls[1], {seat=1, n=33, max=100, src="timeout"})
  eq(b.session.state.phase, "play"); eq(b.session.state.turn, 2)
end)
it("a roll that never shows up is reported stuck, then the timeout covers it", function()
  sim.canSee = function() return false end
  ok(a:roll()); sim:run(4); eq(a.session.rollStuck, true); eq(a.session.rolling, nil)
  sim.nextRandom = {9}; sim:run(45); eq(a.session.state.rolls[1].src, "timeout"); eq(a.session.rollStuck, false)
end)
it("a recorded number that differs from what I saw is a mismatch", function()
  b:rollSeen("Иван", 57, 1, 100); a.session:play(1, {k="roll", n=5, max=100, src="seen"}); sim:run(6)
  eq(ns.Rolls.check(b.session, 1), "mismatch")
end)
it("host leaves mid-turn: the next host takes the roll", function()
  -- setup(3); it is the host's (seat 1) turn
  a:stand(); sim:run(2); eq(b.session.role, "host"); eq(b.session.state.players, {2,3}); eq(b.session.state.turn, 2)
  sim.nextRolls = {40}; ok(b:roll()); sim:run(1); eq(c.session.state.rolls, {{seat=2, n=40, max=100, src="seen"}})
end)
it("rollSeen is announced as an event even with no table", function() --[[ fresh client d: handler got ("Иван", 5, 1, 100) ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/rolls_test.lua`.** Expected: FAIL (`Rolls` is nil).
- [ ] **Step 3: Implement** `core/Rolls.lua`, the four constants, `Names.matches`, `Client:roll`/`Client:rollSeen`, the sim fields; TOC line after `core/Member.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `13 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Rolls.lua core/Names.lua core/Const.lua core/Client.lua tests/helpers/sim.lua TavernGames.toc tests/core/rolls_test.lua` — `feat(core): roll sightings, claims, table rolls and cross-check`

### Task 6: Party — automatic group invite

**Files:**
- Create: `core/Party.lua`; Modify: `core/Const.lua`, `core/Client.lua`, `tests/helpers/sim.lua`, `TavernGames.toc`; Test: `tests/core/party_test.lua`

**Interfaces:**
- Consumes: `env.group`, `env.groupInvite`, `env.inGroup(guid)`, `presence:get(name).guid`, the `applied` hook.
- Produces:
  - `ns.Party.missing(s) -> {name, …}` — seated players other than me, in seat order, whose GUID is known to Presence and for whom `env.inGroup(guid)` is false; `{}` when `env.group` is absent.
  - `ns.Party.ensure(s)` — host only, table engine with `needsGroup`, `env.group` and `env.groupInvite` present. With `g = env.group()` and `m = Party.missing(s)`: nobody missing → `s.partyWhy = nil`; `g.grouped and not g.leader` → `s.partyWhy = "notleader"`; `g.grouped and not g.raid and g.size + #m > PARTY_SIZE` → `"full"`; otherwise `partyWhy = nil` and `env.groupInvite(name)` for every missing name not invited in the last `GROUP_INVITE_GAP` seconds (`s.partyAsked[name] = env.now()`).
  - `ns.Ext.party = {applied}` — host: `ensure` after a `sit` and after a `start` event.
  - `client:groupInviteFrom(shown) -> bool` — true only when I hold a seat at a `needsGroup` table, I am not its host, and `Names.matches(session.host, shown)`.
  - `client:groupChanged()` — emits `"session"(client.session)` when a session exists.
  - Sim: `opts.party` (`{grouped, leader, raid, size}`, default `{grouped=false, leader=false, raid=false, size=0}`) → `env.group()`; `env.groupInvite(name)` appends `{from, name}` to `sim.groupInvites`; neither exists on `sim.makeEnv` envs. `opts.party`, `opts.group` and the other `sim:add` options are stored per name and reused by `sim:relog` (see Task 5), so `env.group`/`env.groupInvite` survive a relog.

- [ ] **Step 1: Write the failing tests.**

```lua
it("the host invites a newcomer once, and again at the start only after 30 s", function()
  local tid = a:openTable{game="deathroll", access="guild", turn=45}; sim:run(3); b:sit(tid, 2); sim:run(1)
  eq(sim.groupInvites, {{from=A, name=B}}); a:startGame(); sim:run(1); eq(#sim.groupInvites, 1)
  --[[ finish the game by rolls (sim.nextRolls = {1}), sim:run(31), a:startGame(): #sim.groupInvites == 2 ]]
end)
it("nobody already in my group is invited", function() --[[ a added with group = {B}: after b sits and the start, sim.groupInvites == {};
  ns.Party.missing(a.session) == {} ]] end)
it("a host who is not the leader, or whose party is full, invites nobody and says why", function()
  --[[ a with party {grouped=true, leader=false, raid=false, size=3}: sim.groupInvites == {}; a.session.partyWhy == "notleader";
  a with party {grouped=true, leader=true, raid=false, size=5}: partyWhy == "full"; the same in a raid (raid=true, size=5): one invite ]]
end)
it("a ttt table invites nobody", function() --[[ ttt table, b sits: sim.groupInvites == {} ]] end)
it("only my table's host is auto-accepted", function()
  -- b seated at a's deathroll table, c in the sim but not seated
  eq(b:groupInviteFrom("Иван"), true); eq(b:groupInviteFrom(A), true); eq(b:groupInviteFrom("Kiro"), false)
  eq(a:groupInviteFrom("Мария"), false); eq(c:groupInviteFrom("Иван"), false)
  --[[ b seated at a's ttt table: b:groupInviteFrom("Иван") == false ]]
end)
it("missing lists who is outside my group, for any seated client", function() --[[ a, b, c at one deathroll table, b added with group = {A}:
  ns.Party.missing(b.session) == {C} ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/party_test.lua`.** Expected: FAIL (`Party` is nil).
- [ ] **Step 3: Implement**; TOC line after `core/Rolls.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `6 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Party.lua core/Const.lua core/Client.lua tests/helpers/sim.lua TavernGames.toc tests/core/party_test.lua` — `feat(core): automatic group invite for tables that need a group`

### Task 7: Bots for any game

**Files:**
- Modify: `core/Bots.lua`; Test: `tests/core/bots_test.lua`

**Interfaces:**
- Consumes: `ns.Games.engine`, `client:startGame`, `client:playAuto`, the `"rollSeen"` event.
- Produces: `bots:hostTable(game) -> tid|nil`, `bots:inviteMe(game) -> tid|nil` (`game` defaults to `"ttt"`; nil for a game without an engine; tables open with the engine's default options).
- Behaviour:
  - A bot on turn calls `bot:playAuto()` after 1.5 s (instead of `act(Engine.auto(…))`); the rematch rule for Морски шах is unchanged.
  - A bot hosting a `start == "host"` table calls `bot:startGame()` 2 s after any session change that leaves it startable (seated ≥ `minSeats`, and no game running).
  - `Bots.enable` wraps `env.inGroup` so a bot's GUID counts as in my group (hence no group invite, no "not in your group" hint, and bots may sit at a „Групата ми“ table), and forwards my `"rollSeen"` events to every bot's `rollSeen`. `Bots.disable` restores `env.inGroup` and stops forwarding.

- [ ] **Step 1: Write the failing tests** (added to `tests/core/bots_test.lua`).

```lua
it("one human plays Death Roll against two bots: real rolls for me, table rolls for them, nobody invited", function()
  local a, envA = sim:add(A, {cls="MAGE"}); local bots = Bots.enable(a, envA, sim.makeEnv); sim:run(1)
  ok(a:openTable{game="deathroll", access="invite", turn=45, opt={start=100}})
  ok(a:invite("Бот Иванов")); ok(a:invite("Bot Barleybrew")); sim:run(5); eq(a.session:seatedCount(), 3)
  ok(a:startGame()); sim.nextRolls, sim.nextRandom = {50, 20, 5, 1}, {40, 30, 15, 10, 4, 2}
  for _ = 1, 200 do
    local st = a.session.state; if st.phase == "over" then break end
    if st.turn == 1 and not a.session.rolling then a:roll() end; sim:run(1)
  end
  local st = a.session.state; eq(st.phase, "over"); eq(st.rolls[#st.rolls].n, 1)
  for _, r in ipairs(st.rolls) do eq(r.src, r.seat == 1 and "seen" or "ask") end
  eq(sim.groupInvites, {}); eq(sim:count(function(m) return m.channel == "GUILD" and m.from ~= A end), 0)
  for _, r in ipairs(sim.rolled) do eq(r.from, A) end
end)
it("a bot hosts Death Roll, I sit, it starts by itself and sees my rolls", function()
  local tid = bots:hostTable("deathroll"); sim:run(3); a:sit(tid, 2); sim:run(4); eq(a.session.status, "live")
  --[[ advance until it is my turn; sim.nextRolls = {7}; a:roll(); sim:run(1): the last roll is {seat=2, n=7, src="seen"} ]]
end)
it("hostTable and inviteMe refuse a game that is not built", function()
  eq(bots:hostTable("belot"), nil); eq(bots:inviteMe("holdem"), nil); ok(bots:hostTable())   -- default ttt
end)
it("disable restores env.inGroup", function() --[[ orig = envA.inGroup before enable; after enable envA.inGroup(<a bot's guid>) == true;
  after disable envA.inGroup == orig ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/bots_test.lua`.** Expected: the four new tests FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add core/Bots.lua tests/core/bots_test.lua` — `feat(core): bots host, start and play any registered game`

### Task 8: WoW side — roll line, group calls, slash, probe

**Files:**
- Create: `wow/Rolls.lua`; Modify: `wow/Adapter.lua`, `wow/Slash.lua`, `locale/bg.lua`, `locale/en.lua`, `tests/helpers/wow.lua`, `TavernGames.toc`; Test: `tests/wow/rolls_test.lua`, `tests/wow/slash_test.lua`

**Interfaces:**
- Consumes: `client:rollSeen`, `client:groupInviteFrom`, `client:groupChanged`, `bots:hostTable(game)`, `bots:inviteMe(game)`.
- Produces:
  - `ns.RollChat.pattern(fmt) -> pattern, order | nil` — `fmt` in `string.format` syntax with exactly four specifiers `%s`/`%d` or `%N$s`/`%N$d`; argument 1 = name, 2 = result, 3 = low, 4 = high (plain specifiers count in order of appearance). Literal text is escaped with the exported `Adapter.escape` (the same function `Adapter.pattern` uses; one copy of the rule); a string specifier becomes `(.+)`, a number `(%d+)`; anchored with `^` and `$`. `order[i]` is `"name"`, `"n"`, `"lo"` or `"hi"` for the i-th capture. Anything else → nil.
  - `ns.RollChat.parse(text) -> name, n, lo, hi | nil` — nil for a non-string, for a secret value (`issecretvalue` exists and returns true), or without a match; the name goes through the player-link strip `nameIn` of `wow/Adapter.lua` (exported as `Adapter.nameIn`, reused, not re-implemented) and `Names.normalize`; numbers through `tonumber`. The pattern is built once from the global `RANDOM_ROLL_RESULT` (missing or unusable → `parse` always returns nil).
  - `ns.RollChat.env(env, bot)` — sets `env.random = function(lo, hi) return math.random(lo, hi) end`; unless `bot`: `env.roll` (calls `RandomRoll(lo, hi)`; nil when `RandomRoll` is not a function), `env.group` (`IsInGroup()`, `UnitIsGroupLeader("player")`, `IsInRaid()`, `GetNumGroupMembers()` → `{grouped, leader, raid, size}`), `env.groupInvite` (`C_PartyInfo.InviteUnit`, else the global `InviteUnit`, else nil). `Adapter.createClient` calls it with `bot = false`, `Adapter.botEnv` with `true`.
  - `ns.RollChat.last` — `{raw, name, n, lo, hi, at}` of the last parsed roll line (for the probe).
  - Events (own frame in `wow/Rolls.lua`): `CHAT_MSG_SYSTEM` → `parse`; a name equal to `Names.normalize(UnitName("player"))` is replaced by `client.env.me` only when no other seat at my table `Names.matches` that shown name (a seated namesake): otherwise it is passed as shown, so `seatFor` refuses it (Review Focus 1; the price is that at a table with my namesake my own rolls fall back to the timeout); then `client:rollSeen`. `PARTY_INVITE_REQUEST(inviter)` → when `client:groupInviteFrom(Names.normalize(inviter))` and `AcceptGroup` is a function: `AcceptGroup()`, then on the next frame `StaticPopup_Hide("PARTY_INVITE")` (when that function exists). `GROUP_ROSTER_UPDATE` → `client:groupChanged()`.
  - Slash: `/tavern bots host <game>` and `/tavern bots invite <game>` (`<game>` = an engine id, or `dr` for `deathroll`; missing = `ttt`; unknown → `L("bots.nogame")`). `/tavern probe` additionally prints the type of `RandomRoll`, `C_PartyInfo.InviteUnit`, `InviteUnit`, `AcceptGroup`, `UnitIsGroupLeader`, `StaticPopup_Hide`, and `L("probe.rollfmt", tostring(RANDOM_ROLL_RESULT), <"OK"|"-">)` (whether a pattern was built); the literal `OK`/`-` here and `yes`/`no` below are diagnostic tokens, not `ns.L` strings (see Global Constraints). `probe roll` is one of the two sanctioned `RandomRoll` calls. `/tavern probe roll` calls `RandomRoll(1, 100)` and after 3 s prints `L("probe.roll.ok", raw, name, <yes|no: the name resolved to me>)` or `L("probe.roll.lost")`.
  - Locale keys (bg): `bots.nogame` = „Тази игра още не е готова.“; `probe.rollfmt` = „Формат на /roll: %s (шаблон: %s)“; `probe.roll.ok` = „/roll се вижда: „%s“, име „%s“, това съм аз: %s“; `probe.roll.lost` = „/roll не се видя в чата до 3 сек.“; `slash.help` = „Команди: /tavern (залата), /tavern bots [host | invite] [игра], /tavern debug, /tavern intro, /tavern reset, /tavern probe [roll]“.
  - `tests/helpers/wow.lua`: `G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"`; `G.RandomRoll` records `{lo, hi}` in `w.rolls`; `G.C_PartyInfo = {InviteUnit = …}` records names in `w.groupInvites`; `G.AcceptGroup` counts in `w.accepted`; `G.StaticPopup_Hide` records in `w.popupsHidden`; `G.IsInGroup`, `G.IsInRaid`, `G.UnitIsGroupLeader`, `G.GetNumGroupMembers` read `w.party = {grouped=false, leader=false, raid=false, size=0}`; `issecretvalue` and `InviteUnit` join the `optional` globals.

- [ ] **Step 1: Write the failing tests** (`tests/wow/rolls_test.lua`; `guildWow()` as in `tests/wow/adapter_test.lua`; `ME = "Иван Петров"`, `Wow.FIRST = "Иван"`). The file defines a file-scope `setup()` returning `w, R` (`guildWow()` booted, `R = w.ns.RollChat`); every test starts with `local w, R = setup()` and the tests below use `w`, `R` from it (the per-file `guildWow` copy follows the stage 1 per-file convention and is not new duplication).

```lua
it("builds the pattern from positional and plain formats", function()
  local w, R = setup()
  local p, o = R.pattern("%s rolls %d (%d-%d)"); eq(o, {"name","n","lo","hi"})
  eq({("Иван Петров rolls 57 (1-1000)"):match(p)}, {"Иван Петров", "57", "1", "1000"})
  p, o = R.pattern("%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)"); eq(o, {"name","n","lo","hi"})
  eq({("Hans würfelt. Ergebnis: 7 (1-100)"):match(p)}, {"Hans", "7", "1", "100"})
  p, o = R.pattern("(%3$d-%4$d): %2$d от %1$s"); eq(o, {"lo","hi","n","name"})
  eq(R.pattern("%s rolls %d"), nil); eq(R.pattern(nil), nil); eq(R.pattern("%s %s %d (%d-%d)"), nil)
end)
it("parses a roll line, a player link, and nothing else", function()
  local w, R = setup()
  eq({R.parse("Мария rolls 12 (1-57)")}, {"Мария", 12, 1, 57})
  eq({R.parse("|Hplayer:Мария Стоянова:1|h[Мария Стоянова]|h rolls 12 (1-57)")}, {"Мария Стоянова", 12, 1, 57})
  eq(R.parse("Мария has gone offline."), nil); eq(R.parse(nil), nil)
  w.G.issecretvalue = function() return true end; eq(R.parse("Мария rolls 12 (1-57)"), nil)
end)
it("my own roll is passed under my full name; another player's as shown", function()
  local seen = {}; w.ns.client:on("rollSeen", function(...) seen[#seen+1] = {...} end)
  w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-1000)"); w:fire("CHAT_MSG_SYSTEM", "Мария rolls 3 (1-57)")
  w:fire("CHAT_MSG_SYSTEM", "Мария has gone offline.")
  eq(seen, {{ME, 57, 1, 1000}, {"Мария", 3, 1, 57}}); eq(w.ns.RollChat.last.raw, "Мария rolls 3 (1-57)")
end)
it("a namesake seated at my table keeps the shown name", function()
  -- seated at a delivered table with seats {ME, "Иван Димов"}; seen = collected "rollSeen" calls as above
  w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-1000)"); eq(seen, {{"Иван", 57, 1, 1000}})   -- not ME: seatFor then refuses it
  --[[ the same line with seats {ME, "Мария Стоянова"} gives {{ME, 57, 1, 1000}} ]]
end)
it("env.roll, env.group and env.groupInvite reach the game API; a bot env has only random", function()
  local env = w.ns.client.env; env.roll(1, 87); eq(w.rolls, {{1, 87}})
  w.party = {grouped=true, leader=true, raid=false, size=3}; eq(env.group(), {grouped=true, leader=true, raid=false, size=3})
  env.groupInvite("Мария Стоянова"); eq(w.groupInvites, {"Мария Стоянова"})
  local bot = w.ns.Adapter.botEnv("Бот Иванов", "PRIEST"); eq(bot.roll, nil); eq(bot.groupInvite, nil); eq(type(bot.random(1, 6)), "number")
end)
it("env.roll is absent when the client has no RandomRoll", function() --[[ Wow.new with G.RandomRoll removed before boot: client.env.roll == nil ]] end)
it("a group invite from my Death Roll host is accepted and the popup hidden; any other is left alone", function()
  --[[ B (guild member, HI delivered) hosts a deathroll table by delivered TBL; I sit (deliver the SNP that seats me);
  w:fire("PARTY_INVITE_REQUEST", "Мария"); w:advance(0): w.accepted == 1; w.popupsHidden == {"PARTY_INVITE"};
  w:fire("PARTY_INVITE_REQUEST", "Гошо"): w.accepted still 1 ]]
end)
it("a group change redraws the table", function() --[[ seated as above with a "session" counter: w:fire("GROUP_ROSTER_UPDATE") adds 1 ]] end)
```

Added to `tests/wow/slash_test.lua`:

```lua
it("bots host <game> opens that game; an unknown game says so", function()
  w:slash("bots host dr"); w:advance(1); eq(c.lobby:tables()[1].game, "deathroll")
  w:slash("bots host belot"); eq(#w:chatWith(w.ns.L("bots.nogame")), 1)
end)
it("probe lists the roll and party API and the roll format; probe roll reports what the chat showed", function()
  w:slash("probe"); eq(#w:chatWith("RandomRoll: function"), 1); eq(#w:chatWith("AcceptGroup: function"), 1)
  eq(#w:chatWith("%s rolls %d (%d-%d)"), 1); eq(#w.rolls, 0)
  w:slash("probe roll"); eq(w.rolls, {{1, 100}}); w:fire("CHAT_MSG_SYSTEM", "Иван rolls 64 (1-100)"); w:advance(3)
  eq(#w:chatWith("Иван rolls 64 (1-100)"), 1)
  w:slash("probe roll"); w:advance(3); eq(#w:chatWith(w.ns.L("probe.roll.lost")), 1)
end)
```

- [ ] **Step 2: Run `bash t.sh tests/wow`.** Expected: the new tests FAIL (`RollChat` is nil).
- [ ] **Step 3: Implement**; TOC line `wow/Rolls.lua` between `wow/Adapter.lua` and `wow/Slash.lua`.
- [ ] **Step 4: Run `bash t.sh tests/wow`, then `bash t.sh`.** Expected: all pass (the locale parity test covers the new keys).
- [ ] **Step 5: Commit.** `git add wow/Rolls.lua wow/Adapter.lua wow/Slash.lua locale/bg.lua locale/en.lua tests/helpers/wow.lua TavernGames.toc tests/wow/rolls_test.lua tests/wow/slash_test.lua` — `feat(wow): roll line capture, group invite and accept, probe roll`

### Task 9: Hall and dialog driven by the registry; peers column split

**Files:**
- Create: `ui/HallPeers.lua`; Modify: `ui/Hall.lua`, `ui/NewTableDialog.lua`, `ui/Widgets.lua`, `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`; Test: `tests/ui/hall_test.lua`

**Interfaces:**
- Consumes: `ns.Games.list()`, `engine.options`, `client:openTable{…, opt}`.
- Produces:
  - `ns.HallPeers.build(v, page, x, colH)` and `ns.HallPeers.render(v, client)` — the „В кръчмата сега“ column moved out of `ui/Hall.lua` (`peerWidget`, `whereIs`, `renderPeers`, `canInviteName`, `buildRight`) with its behaviour unchanged; `Hall.clickPeer`, `Hall.invite` and `Hall.view.peers` keep their names. The moved code used Hall locals (`contains`, `firstWord`, `colored`, `hostingWithFreeSeat`, `PEER_H`, `RIGHT_W`): `HallPeers` exports `canInviteName` (which `Hall.clickPeer`, staying in `Hall.lua`, calls); shared helpers move, not copy: `ns.Util.contains` and `W.firstWord` (implemented with `ns.Names.first`, added in Task 5) in `ui/Widgets.lua`; the other locals are exported from `Hall` or `W` as needed. `ui/Hall.lua` must end below 580 lines.
  - Left column: one row per `ns.Games.list()` entry; a row with an engine is active (click → `NewTableDialog.open(id)`), a row without one is dimmed with „Скоро“ (click → rules book topic `"soon"`); the sub-label is `L("games.players", entry.players)`. The bottom „Отвори маса“ button opens the dialog for the first active game.
  - `W.gameName(id)` returns `L("game.unknown")` for an id without a `game.<id>` key (a remote string is never shown).
  - Floor tables: chair name labels are shown only at tables with at most 4 seats (tooltips still name everyone); list rows show seats as `seated/total`.
  - `NewTableDialog.open(id)`: below the turn row, one row per engine option: label `L("opt.<game>.<id>")`, a choice per value shown as `tostring(value)`, the default preselected; the frame is `330 + 34 × <number of options>` high; „Отвори“ passes `opt = {<id> = <chosen>}`. `D.options[id]` is the choice group (for tests).
  - Locale (bg): `game.unknown` = „Непозната игра“; `opt.deathroll.start` = „Начално число“.

- [ ] **Step 1: Write the failing tests** (replace `lists six games: …` and add the rest).

```lua
it("lists six games: Морски шах and Death Roll active, the other four dimmed with „Скоро“", function()
  local games = w.ns.Hall.view.games; eq(#games, 6)
  eq({games[1].id, games[2].id, games[3].id, games[6].id}, {"ttt", "deathroll", "santase", "holdem"})
  for i = 1, 2 do eq(games[i].frame:GetAlpha(), 1); eq(games[i].soon:IsVisible(), false) end
  for i = 3, 6 do ok(games[i].frame:GetAlpha() < 1); eq(games[i].soon:GetText(), "Скоро") end
  eq(#w:texts("2–6 играчи"), 1); w:click(games[2].frame); eq(w.ns.NewTableDialog.gameId, "deathroll")
end)
it("the Death Roll dialog offers the start number, 1000 preselected, and opens with the chosen one", function()
  local D = w.ns.NewTableDialog; D.open("deathroll"); eq(#w:texts("Начално число"), 1)
  local g = D.options.start; eq(#g.options, 4); eq(g.value, 1000); eq(g.options[4].text:GetText(), "100000")
  w:click(g.options[3].frame); w:click(D.openButton)
  eq(w.ns.client.session.game, "deathroll"); eq(w.ns.client.session.opt, {start=10000}); eq(#w.ns.client.session.seats, 6)
  eq(D.frame:GetHeight(), 364)
end)
it("the Морски шах dialog has no option row", function() --[[ D.open("ttt"): next(D.options) == nil; height 330; no visible „Начално число“ ]] end)
it("a six-seat table shows six chairs without name labels; the list shows 2/6", function()
  --[[ deliver a deathroll TBL from B with s = {B, "Kiro Barley", false, false, false, false}: the table widget has 6 visible chair buttons,
  4 of them enabled, 0 visible chair labels; with nine tables delivered the row for that tid shows "2/6" ]]
end)
it("a table of a game this client does not have is named „Непозната игра“ and a chair click is refused", function()
  --[[ TBL with g = "|TInterface\\Icons\\x:16|t", s = {B, false}: one visible text "Непозната игра", none containing "|T";
  click on its empty chair: the footer shows L("refused.version"); nothing is sent ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/hall_test.lua`.** Expected: the five tests FAIL.
- [ ] **Step 3: Implement**; TOC line `ui/HallPeers.lua` directly before `ui/Hall.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add ui/HallPeers.lua ui/Hall.lua ui/NewTableDialog.lua ui/Widgets.lua locale/bg.lua locale/en.lua TavernGames.toc tests/ui/hall_test.lua` — `feat(ui): hall and new-table dialog driven by the game registry`

### Task 10: Table frame for N seats and host-started games

**Files:**
- Modify: `core/HallLayout.lua`, `ui/TableFrame.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/core/hall_layout_test.lua`, `tests/ui/table_test.lua`

**Interfaces:**
- Consumes: `client:startGame()`, `engine.start`, `engine.minSeats`, `engine.over`/`engine.result`, `session.opt`.
- Produces:
  - `ns.HallLayout.plates(n, w) -> {{x, y, pw}, …}, rows` — columns: `n` for `n ≤ 2`, `2` for `n == 4`, otherwise `3`; plate width `190` with at most two columns, else `165`; row `r` (0-based) at `y = -10 - 32·r`; in a row with `cols ≥ 2` column `c` (0-based) at `x = 10 + c·(w - 20 - pw)/(cols - 1)`; a single column is centred (`x = (w - pw)/2`).
  - `TableFrame` places plate `i` at `plates[i]` (TOPLEFT of the felt), sets its width, and shifts the board to `CENTER 0, -6 - 16·(rows - 1)`. A view may still provide `seatNote`.
  - `v.startButton` (right of „Покани“, 110×26; while it is shown the news line anchors to the start button instead of `invite` RIGHT +14, so the two never overlap): shown to the host of a `start == "host"` table while no game runs; text `L("table.start")` before the first game, `L("table.again")` after one; enabled when seated ≥ `minSeats`; click → `client:startGame()`.
  - Banner for a `start == "host"` table with no game running: fewer than `minSeats` seated → `table.waitingMore`; host → `table.pressStart`; others → `table.waitingHost`. Морски шах keeps `table.waiting`. A game that is over shows no banner (the view says who lost). Banner precedence overall (stage 1 order kept): `hostSilent > resynced > aborted > waitingMore/pressStart/waitingHost > waiting`.
  - Layout budget (532×328 felt area): the board sits at `CENTER 0, -6 - 16·(rows - 1)` (6 seats: `-22`), so a view frame must be at most 236 high to start below plate row 2, which ends 68 px from the top; Task 11's `DeathRollView` frame is 512×236.
  - Title meta: after the turn time, `" · " .. L("opt.<game>.<id>") .. " " .. value` for every option.
  - Locale (bg): `table.start` = „Започни“; `table.again` = „Нова игра“; `table.waitingMore` = „Чакаме още играчи…“; `table.pressStart` = „Всички ли са тук? Натисни „Започни“.“; `table.waitingHost` = „Чакаме домакина да започне…“.

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/core/hall_layout_test.lua
it("plates: one row for two, a grid of three columns from three seats on", function()
  local p, rows = H.plates(2, 532); eq(p, {{10, -10, 190}, {332, -10, 190}}); eq(rows, 1)
  p, rows = H.plates(3, 532); eq(p, {{10, -10, 165}, {183.5, -10, 165}, {357, -10, 165}}); eq(rows, 1)
  p, rows = H.plates(4, 532); eq(p, {{10, -10, 190}, {332, -10, 190}, {10, -42, 190}, {332, -42, 190}}); eq(rows, 2)
  p, rows = H.plates(6, 532); eq(rows, 2); eq(p[4], {10, -42, 165}); eq(p[6], {357, -42, 165})
  p, rows = H.plates(9, 532); eq(rows, 3); eq(p[9], {357, -74, 165}); eq(H.plates(1, 532), {{171, -10, 190}})
end)
-- tests/ui/table_test.lua (withBots(), I host a deathroll invite table with opt {start=100})
it("six plates in two rows; alone: „Чакаме още играчи…“ and a disabled „Започни“", function()
  local v = w.ns.TableFrame.view; eq(#w:texts("Чакаме още играчи…"), 1)
  local shown = 0; for _, p in ipairs(v.plates) do if p.frame:IsVisible() then shown = shown + 1 end end; eq(shown, 6)
  eq(v.plates[4].frame:GetWidth(), 165); ok(v.startButton:IsVisible()); eq(v.startButton:IsEnabled(), false)
  eq(#w:texts("Начално число 100"), 1)
end)
it("with a second player „Започни“ starts the game and goes away; after the game it reads „Нова игра“", function()
  --[[ invite „Бот Иванов“ through the picker, w:advance(2): banner L("table.pressStart"), startButton enabled with text „Започни“;
  w:click(v.startButton); w:advance(0): session.status == "live", startButton hidden, no banner;
  end the game: client.session:play(1, {k="roll", n=1, max=100, src="ask"}); w:advance(0): startButton visible with text „Нова игра“ ]]
end)
it("a guest at a host-started table sees „Чакаме домакина да започне…“ and no start button", function()
  --[[ w:slash("bots host dr"); sit on the bot's table before it starts (w:advance(1)): one visible L("table.waitingHost"); startButton hidden ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/hall_layout_test.lua tests/ui/table_test.lua`.** Expected: the new tests FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: all pass (the existing two-seat table tests pin the unchanged look).
- [ ] **Step 5: Commit.** `git add core/HallLayout.lua ui/TableFrame.lua locale/bg.lua locale/en.lua tests/core/hall_layout_test.lua tests/ui/table_test.lua` — `feat(ui): table frame for up to nine seats and host-started games`

### Task 11: Death Roll view and rules-book topic

**Files:**
- Create: `ui/games/DeathRollView.lua`; Modify: `core/Help.lua`, `ui/HelpBook.lua`, `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`; Test: `tests/ui/deathroll_test.lua`, `tests/core/locale_help_test.lua`, `tests/ui/book_test.lua`

**Interfaces:**
- Consumes: `client:roll()`, `ns.Rolls.check`, `ns.Party.missing`, `session.partyWhy`, `session.rolling`, `session.rollStuck`, engine state (`rolls`, `players`, `turn`, `max`, `start`, `phase`, `loser`), `TableFrame.registerView`.
- Produces: `TableFrame.registerView("deathroll", View)` with `View.build`, `View.update`, `View.seatNote`; `View.cells(session) -> {cell, …}` (pure, for tests); the built frame exposes `rollButton` and `cells[i] = {number, label}` (font strings of trail cell `i`); `ns.Help.topics` ids `{"hall", "ttt", "deathroll", "soon"}`; `BLOCKS.ladder` in `ui/HelpBook.lua`.
- View (mockup 03 `droll`), frame 512×236 (not 250: `TableFrame` puts the board at `CENTER 0, -22` for six seats, and anything taller overlaps plate row 2; lay out the lines inside the smaller height):
  - `View.cells(s)`: the trail, left to right, at most 7 cells: `{kind="start", n=state.start}` first when the whole ladder fits (rolls ≤ 5 while playing, ≤ 6 when over), otherwise `{kind="more"}` (shown as „…“) followed by the newest rolls; each roll `{kind="roll", n, seat, name, tag}` with `tag` = `"mismatch"` when `Rolls.check` says so, else `"table"` for `src` `"ask"`/`"timeout"`, else `"unseen"` for `src == "claim"` or a check of `"unseen"`, else nil; while playing the last cell is `{kind="next", seat=state.turn, name}`.
  - Drawing: numbers in Alegreya SC, sizes `30, 28, 26, 24, 22, 22, 22` by cell position, each roll in the roller's class colour (`W.nameColor`); under it the first word of the name, or `L("deathroll.you")` for my seat, or `L("deathroll.startLabel")` for the start cell; „›“ in brass between cells. A rolled 1 is drawn in `oMark` at size 34. The `next` cell is „?“ in `oMark` at alpha 0.35. Tags: `"unseen"` appends „?“ to the label, `"mismatch"` appends „!“ in `red`, `"table"` appends `L("deathroll.tag.table")`; each tagged cell has a tooltip (`deathroll.tip.unseen`, `.mismatch`, `.table`).
  - Under the trail, centred, dim: `L("deathroll.caption")`. Under it, in `oMark`, at most one group line: host with `partyWhy` → `deathroll.group.notleader` / `deathroll.group.full`; else when `Party.missing(s)` is not empty → `L("deathroll.group.missing", <first words, comma-separated>)`.
  - Bottom: my turn → button `L("deathroll.roll")` with the sub-label `L("deathroll.range", state.max)`; click → `client:roll()`; while `session.rolling` the button is disabled and reads `L("deathroll.rolling")`; with `session.rollStuck` the line `L("deathroll.stuck", state.max)` shows above the enabled button. Not my turn → `L("deathroll.waitFor", name)`. Over with a loser → `L("deathroll.lost", name)` in gold; over without → `L("deathroll.void")`. Watchers see the same texts and no button.
  - `View.seatNote(s, seat)`: `L("deathroll.nextGame")` for an occupied seat that is not in `state.players` while a game runs; else `""`.
- Rules book: topic `deathroll` (title `game.deathroll`) with the blocks `p1`, `example`, `ladder`, `roll`, `group`, `time`, `tags`, `leave`; the `ladder` block is `{kind="ladder", key="help.deathroll.ladder", rolls={1000, 642, 87, 12, 3, 1}}` drawn as a row of numbers in paper heading font with „›“ between them and the last one in `red`. The quoted-label test covers `help.deathroll.*` too.
- Locale, pinned bg (en = faithful translations; en pinned where given):
  - `deathroll.roll` = „Хвърли“ (en `Roll`); `deathroll.range` = „от 1 до %d“; `deathroll.rolling` = „Хвърляне…“; `deathroll.stuck` = „Не стана. Напиши /roll %d в чата.“; `deathroll.waitFor` = „Изчакай %s…“; `deathroll.lost` = „%s хвърли 1 и губи!“; `deathroll.void` = „Играта свърши без губещ.“; `deathroll.you` = „Ти“; `deathroll.startLabel` = „старт“; `deathroll.nextGame` = „от следващата игра“; `deathroll.tag.table` = „· маса“.
  - `deathroll.caption` = „Числата идват от истинския /roll в чата, така че никой не може да ги нагласи. Който хвърли 1, губи.“
  - `deathroll.tip.unseen` = „Това хвърляне не го видях в чата. Сигурно не сме в една група.“; `deathroll.tip.mismatch` = „Внимание: в чата видях друго число за това хвърляне.“; `deathroll.tip.table` = „Хвърли го масата, а не /roll: за бот, при изтекло време или когато /roll не работи.“
  - `deathroll.group.missing` = „Не си в група с %s. Хвърлянията се виждат само в група или наблизо.“; `deathroll.group.notleader` = „Не си водач на групата си. Помоли водача да покани останалите.“; `deathroll.group.full` = „Групата ти е пълна. Който е наблизо, пак ще вижда хвърлянията.“
  - `help.deathroll.p1` = „Death Roll е игра на чист късмет за двама до шестима. Първият хвърля от 1 до началното число. Следващият хвърля от 1 до това, което се е паднало. Който хвърли 1, губи.“
  - `help.deathroll.example` = „Иван и Мария играят от 1000. Иван хвърля 642. Мария хвърля от 1 до 642 и вади 87. Иван вади 12, Мария вади 3. Иван хвърля от 1 до 3 и вади 1. Иван губи и черпи.“
  - `help.deathroll.ladder` = „Така изглежда стълбицата. Всяко число е в цвета на този, който го е хвърлил.“
  - `help.deathroll.roll` = „Когато е твой ред, натискаш „Хвърли“. Аддонът прави истински /roll вместо теб, числото идва от сървъра и всички го виждат в чата. Домакинът натиска „Започни“, когато сте поне двама, а после „Нова игра“.“
  - `help.deathroll.group` = „Чуждият /roll се вижда само в група или наблизо. Затова, щом седнеш, домакинът те кани в група и аддонът приема вместо теб. Ако вече си в друга група, просто застанете един до друг.“
  - `help.deathroll.time` = „Ако времето ти изтече, масата хвърля вместо теб. Не губиш служебно, освен ако не се падне 1.“
  - `help.deathroll.tags` = „Въпросителна до число значи, че ти не си го видял в чата. Надпис „· маса“ значи, че го е хвърлила масата: така хвърлят ботовете.“
  - `help.deathroll.leave` = „Ако някой стане по средата, останалите продължават без него. Останеш ли сам, играта свършва без губещ.“
  - `help.soon.p` = „Скоро идват Сантасе, Белот, Табла и Тексас Холдем, и игра на залог с тефтер на дълговете.“; `help.soon.example` = „Засега в кръчмата се играят Морски шах и Death Roll. Другите игри стоят бледи в списъка, с надпис „Скоро“. Щом станат готови, правилата им ще се появят тук, в книжката.“

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/core/locale_help_test.lua: topics are {"hall","ttt","deathroll","soon"}; "ladder" is an allowed kind; the deathroll topic has
-- exactly one ladder block whose rolls are {1000, 642, 87, 12, 3, 1}; the quoted-label loop also covers ^help%.deathroll%.;
-- pinned: T.bg["help.deathroll.example"], T.bg["help.soon.p"] equal the strings above; T.en["deathroll.roll"] == "Roll".
-- tests/ui/deathroll_test.lua — file scope: `guildWow`, `withBots`, `color(fontString)` (the text colour as r,g,b table) and the constants
-- `MAGE`, `PRIEST` (class colours from `ns.Theme`/`W.nameColor`) are copied beside each other under the existing per-file convention
-- (stage 1 tests keep per-file copies; this is not new duplication); `play()` = withBots(), I (seat 1, "Иван Петров", MAGE) host deathroll
-- {start=100}, „Бот Иванов“ (PRIEST) seated through the picker, startButton clicked, w:advance(0); `setup()` calls it and returns
-- `w, V, View` (`V = w.ns.TableFrame.built.deathroll`, `View = w.ns.TableFrame.views.deathroll`); every test starts with `local w, V, View = setup()`.
it("my turn: „Хвърли“ with the range makes one server roll and waits", function()
  eq(#w:texts("от 1 до 100"), 1); w:click(V.rollButton); w:advance(0)
  eq(w.rolls, {{1, 100}}); eq(V.rollButton:IsEnabled(), false); eq(#w:texts("Хвърляне…"), 1)
end)
it("the roll line from chat becomes a ladder entry in my class colour; the bot's roll is tagged „· маса“", function()
  w.ns.client.env.random = function() return 30 end   -- the bot's table roll
  w:click(V.rollButton); w:fire("CHAT_MSG_SYSTEM", "Иван rolls 57 (1-100)"); w:advance(0)
  local cells = View.cells(w.ns.client.session)
  eq(cells[1], {kind="start", n=100}); eq({cells[2].kind, cells[2].n, cells[2].seat, cells[2].tag}, {"roll", 57, 1, nil})
  eq(cells[3].kind, "next"); eq(color(V.cells[2].number), MAGE); eq(#w:texts("Изчакай Бот Иванов…"), 1)
  w:advance(2); cells = View.cells(w.ns.client.session); eq({cells[3].n, cells[3].tag}, {30, "table"}); eq(color(V.cells[3].number), PRIEST)
  eq(#w:texts("· маса"), 1)
end)
it("a roll I did not see gets „?“, a different number gets „!“", function()
  --[[ B (real, delivered) hosts; I am seated as seat 2 by a delivered SNP of a live game; deliver EV roll {seat=1, n=40, max=100, src="seen"};
  w:advance(6): View.cells(...)[2].tag == "unseen"; then with a fired "Мария rolls 41 (1-100)" before the EV: tag == "mismatch" ]]
end)
it("no echo within 3 s: the hint to type /roll by hand, and typing it works", function()
  w:click(V.rollButton); w:advance(3.1); eq(#w:texts("Не стана. Напиши /roll 100 в чата."), 1); eq(V.rollButton:IsEnabled(), true)
  w:fire("CHAT_MSG_SYSTEM", "Иван rolls 9 (1-100)"); w:advance(0); eq(w.ns.client.session.state.max, 9)
end)
it("a long ladder keeps the newest rolls behind „…“; rolling 1 ends it with the loser named", function()
  --[[ play seven rolls through client.session:play with src "ask" (99, 98, …, 93): cells[1].kind == "more", #cells == 7, last is "next";
  then a roll of 1 by seat 2: one visible "Бот Иванов хвърли 1 и губи!"; no roll button; the 1 is drawn at size 34 in oMark ]]
end)
it("the group line names who is outside my group, or why I cannot invite", function()
  --[[ B real, seated at my table with a GUID that w.group does not list: one visible text starting "Не си в група с Мария";
  w.party = {grouped=true, leader=false, raid=false, size=2}; sit event again: one visible L("deathroll.group.notleader") ]]
end)
it("a player who sat down mid-game is marked „от следващата игра“", function() --[[ View.seatNote(session, 3) for a seat occupied after
  the start == "от следващата игра"; for seat 1 == "" ]] end)
-- tests/ui/book_test.lua
it("the Death Roll topic shows the ladder 1000 › 642 › 87 › 12 › 3 › 1 with the last number red", function() --[[ B.open("deathroll"):
  six number strings in that order, the sixth with the colour of Theme "red"; ⓘ on a deathroll table opens this topic ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/deathroll_test.lua tests/core/locale_help_test.lua tests/ui/book_test.lua`.** Expected: FAIL (no view, topic missing).
- [ ] **Step 3: Implement**; TOC line `ui/games/DeathRollView.lua` after `ui/games/TicTacToeView.lua`.
- [ ] **Step 4: Run the three files, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add ui/games/DeathRollView.lua core/Help.lua ui/HelpBook.lua locale/bg.lua locale/en.lua TavernGames.toc tests/ui/deathroll_test.lua tests/core/locale_help_test.lua tests/ui/book_test.lua` — `feat(ui): death roll ladder and its rules-book topic`

### Task 12: In-game check list and documentation

**Files:**
- Create: `docs/superpowers/notes/2026-11-stageA-ingame-checks.md`; Modify: `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` (the `### Shared contracts` tables: add the engine/`env`/protocol additions of this plan as a subsection „Stage A additions“)

**Interfaces:** none (verification and documentation). The notes file holds the table below with a `Result` column, every row `not yet measured`; the user runs the checks in game and the results are written there. Nothing is marked passed on the strength of the unit tests.

- [ ] **Step 1: `bash t.sh`.** Expected: `N passed, 0 failed`.
- [ ] **Step 2: Write the notes file** with these checks (one character unless stated; `/console scriptErrors 1` on throughout):

| # | Check | What to look for |
|---|---|---|
| 1 | `/tavern probe` | `RandomRoll`, `C_PartyInfo.InviteUnit`, `AcceptGroup`, `UnitIsGroupLeader`, `StaticPopup_Hide`: `function`; the `/roll` format line ends with `OK` |
| 2 | `/tavern probe roll` | „/roll се вижда…“; which name form the line carries (first name, full name, realm); „това съм аз: yes“ |
| 3 | `/tavern bots`, open Death Roll („Само поканени“, 100), invite two bots, „Започни“ | six plates in two rows; pressing „Хвърли“ prints a real roll line in chat and adds my number in my class colour; no "action blocked" popup, in and out of combat |
| 4 | same game, bots' turns | their numbers arrive after about 1.5 s tagged „· маса“; no bot name in any outgoing line of `/tavern debug`; no group invite is sent |
| 5 | let my turn run out | the table rolls for me (tagged), the game goes on |
| 6 | on my turn type `/roll <max>` by hand; on another turn type `/roll 100` | the first is taken, the second ignored |
| 7 | finish the game, „Нова игра“ | the loser rolls first; ⓘ opens „Death Roll“ with the ladder picture |
| 8 | `/tavern bots host dr`, sit | the bot starts by itself; my rolls show without „?“ |
| 9 | two guild characters, not grouped: A opens Death Roll, B sits | B is in A's group within a second or two and no invite popup stays on B's screen; does `InviteUnit` accept a full name with a space? Record the form of the inviter's name in `PARTY_INVITE_REQUEST` (first name, full name, realm): the auto-accept matches only the host's first name, so a namesake inviter is a known risk (Review Focus 1: "never a wrong seat") |
| 10 | A and B play a whole game | identical ladders, no „?“, no „!“; record how B's name appears in A's roll line |
| 11 | B stands far away and leaves the group, then rolls | A shows B's number after about 3 s with „?“; the game goes on; the group line names B |
| 12 | A is in a party led by somebody else, opens a table, B sits | no invite; the line „Не си водач на групата си…“ |
| 13 | B is already in another group | the game's "already in a group" message appears once per 30 s at most; the group line shows |
| 14 | three characters if available: one stands mid-game; the host stands on its own turn | play continues; the next player hosts and its roll is taken |
| 15 | `/reload` by a guest mid-game | the ladder comes back from the snapshot; no second „… губи!“ line or result |
| 16 | hall with a Death Roll table and nine bot tables (`/tavern bots host` ×9) | six chairs drawn without overlap; list row shows `1/6`; trace: still one `TBL` per 60 s per table. Note: a finished Death Roll keeps `status = "live"` (phase `"over"`), so between games the table's `st` is `live` and the hall shows „тече“; accepted (changing `st` would make newcomers infer "aborted" on `adopt`) |

- [ ] **Step 3: Update the stage 1 plan's Shared contracts section** with the three tables of this plan (engine additions, `env` additions, protocol additions) under „Stage A additions“, so the message table stays the single reference.
- [ ] **Step 4: Report to the user** which checks need a second account (9–15) and that rows 1–2 decide whether „Хвърли“ and the auto-invite work as built or fall back to the hints.
- [ ] **Step 5: Commit.** `git add docs/superpowers/notes/2026-11-stageA-ingame-checks.md docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` — `docs: stage A in-game check list and protocol additions`

---

## Self-review (applied)

- **Spec coverage (stage A):** 5.2 hall with N chairs and registry-driven game list → Tasks 9, 10; 5.3 Death Roll (ladder in class colours, numbers from the real `/roll`, who rolls 1 loses, 2+ players, automatic group on sitting or the existing group) → Tasks 4, 5, 6, 8, 11; 5.3а ⓘ topic in bg/en with a tavern-talk example and a picture → Task 11; 6.2 host authority, every client applies every event, timeout = automatic action → Tasks 3, 5; 6.3 roll taken from `CHAT_MSG_SYSTEM` through the localized `RANDOM_ROLL_RESULT` → Task 8; 6.5 bots and probe → Tasks 7, 8, 12. Handoff note (split `Session.lua`/`Hall.lua`) → Tasks 1, 9. Final-review items closed on the way: M1 (Tasks 1, 2), M2 (Task 1), M4 in part (seat count, unknown game label: Tasks 2, 9). Deliberately absent: wagers and the spec 8 rule "who rolls 1 pays everybody" (only the `"result"` event exists), ledger, the tabs, commit-reveal.
- **Decisions the plan makes beyond the spec:** six seats for Death Roll; start number from four choices; the host starts the game with a button; a roll the host cannot see is accepted as a claim and marked rather than stalling the table; timeouts and bots get a local table roll rather than a server roll; group invites are accepted automatically from the table's host; no new message type; the list label "2–6 играчи" for Death Roll (part of the six-seat decision; the spec says „2+ играчи“).
- **Step scan:** every task has a failing-test step with exact values, an expected failure, an implement step naming files and pinned values, the two run commands, and a commit with exact paths. No task leaves a rule to "handle as appropriate".
- **Type and name consistency:** engine id `deathroll` everywhere (registry, locale `game.deathroll`, view, slash alias `dr`); roll action `{k="roll", n, max, src}` with `src` in `seen/claim/ask/timeout` in Tasks 4, 5, 7, 11; `client:roll/rollSeen/startGame/playAuto/groupInviteFrom/groupChanged` in Tasks 3, 5, 6, 7, 8, 11; `ns.Rolls` (core) vs `ns.RollChat` (wow); session fields `opt, rollLog, rollCheck, rolling, rollStuck, claim, partyAsked, partyWhy`; `env.random/roll/group/groupInvite` in the contract table, the sim (Tasks 3, 5, 6) and the adapter (Task 8); `HallLayout.plates(n, w)` returns `{x, y, pw}` in Task 10's tests and prose; `E.over` in the contract table, consumed by `startGame` (Task 3), defined by Death Roll (Task 4) and read by the table frame (Task 10).
- **Review Focus:** each of the five has a named test in its owning task (Tasks 3, 5, 8).
- **Proportion:** bodies are given only as rules where the tests do not determine them (the claim/verify timing, the `ensure` order, the pattern builder, the trail window); the rest is signatures, pinned values and tests.
