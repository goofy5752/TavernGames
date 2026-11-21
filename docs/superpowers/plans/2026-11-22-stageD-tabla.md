# Tavern Games Stage D (Табла) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Two guild members (or one member and a bot) play Табла from anywhere in the guild, with no group and no `/roll`: Обикновена → Тапа → Гюлбара in a cycle to 5 points, dice thrown by a commit-reveal between the two players, a board on which a clicked checker lights its legal targets, a move staged step by step with „Върни“ and sent whole with „Готово“, an automatic move on timeout, a `"result"` event, „Нова игра“ after the match, and the rules-book topic „Табла“.

**Architecture:** The engine (`engines/tabla.lua`, merged and reviewed) keeps every rule; it gains the staging helper `E.stage` and declares itself an open game (no `E.view`), so the session treats it like Морски шах: one state on every client, the host's turn clock moves for either seat. Dice are a new, small extension `ns.Ext.dice` in `core/Dice.lua` (not a generalisation of `core/Deal.lua`: no dealer, no private faces, no audit, no replay). A throw is three ordered events inside `EV`: the host opens it with the commit of its own seed, the other player commits and whispers its seed to the host, the host publishes both seeds; every client checks them against the commits and derives the dice itself with `Fair.dice` (the existing `Deck.key`/`Deck.stream`/`Deck.below`). No dice value ever travels. The UI is a pure model (`ui/games/TablaModel.lua`) over `E.stage` and a view that draws it (`ui/games/TablaView.lua`). Two halves: **D1** (Tasks 1–4) makes Табла playable and proven in the simulator without UI; **D2** (Tasks 5–9) adds the textures, the board, the rules book and the in-game check list.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), the stage 1 Ace3 subset, `bash t.sh`, `tests/helpers/sim.lua`, `tests/helpers/wow.lua`, Python 3 standard library for `tools/gen_textures.py`.

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.3 Табла, 5.3а, 6.2, 6.3 „Зарове“, section 8: no cube, to 5 points, mars 2, dice by commit-reveal; these supersede „партия от три“ in 5.3 and the last bullet of 6.3). Roadmap: `docs/superpowers/plans/2026-11-20-games-roadmap.md` (Stage D). Stage C plan (format, the end state this plan builds on): `docs/superpowers/plans/2026-11-22-stageC-belot.md`. Engine contract: `docs/superpowers/notes/engine-contract.md` (Addenda 1–5; Task 9 adds Addendum 6). Rulings: `.superpowers/sdd/engines-parallel/progress.md` (T1–T3, the user's Тапа and Гюлбара decisions), `.superpowers/sdd/2026-11-21-stageB-fairness-santase/progress.md` (the note „has view = hidden info will catch tabla“, decided here). Look: `docs/mockups/07-wow-authentic.html` variant 1 (its Табла strip), `docs/mockups/03-games.html` (`tabla`).

**Stage D starts on `feature/games` after stage C's final review wave is merged.** Line numbers quoted below are from `2819a46` and may have moved; names are binding. It consumes: `ns.Fair` (`seed`, `commit`, `handId`), `ns.Deck` (`key`, `stream`, `below`), the session hooks of stage B (`need`, `table`, `act`, `applied`, `adopted`, `snap`, `hostChanged`), `s.fairTimer`, `engine.again`, `"result"` with `left`/`names`, `W.GoldButton`/`W.GhostButton`, `v.fairLine`, `v.startButton`, `Games.PLAYABLE`.

## Global Constraints

Everything in the stage 1, A, B and C constraint files still holds (`.superpowers/sdd/2026-11-22-stageC-belot/global-constraints.md` and the ones it names). Added for stage D:

- Protocol stays `v=1`. Stage D adds **no message type and no message field**. The throw travels inside `ACT`/`EV` as actions of `k = "throw"` and inside the existing `SNP.fr` (table below).
- Табла's rules are the rule table at the top of `engines/tabla.lua`. Stage D changes no rule; `bash t.sh tests/engines/tabla_test.lua` keeps every existing test except the `E.view` line and the `E.result` expectations that gain `left`.
- **Табла is an open game: the engine has no `E.view`.** „Has `view`“ stays the one marker of hidden information in `core/Session.lua`, `core/Lifecycle.lua` and `core/Member.lua`: for Табла the host holds the whole state, snapshots are whole, the forged-move check does not run, and the host's turn clock plays `E.auto` for whichever seat is on turn.
- **The throw (binding):**
  1. Throw `h` is opened by the host with the event number it gets (`h = seq + 1`); `rollId = Fair.handId(tid, h)` = `tid .. "/" .. h`.
  2. The opener is the host's seat `d`; the other seat is `g = 3 − d`. The open event carries the commit of the opener's seed. `g` commits a fresh seed, sees its own commit come back as an event, and whispers its seed to the host. Until then the opener's seed has not left the opener's client, so `g` reveals blind.
  3. The host publishes both seeds in one event. Every client checks both against the commits and applies the dice `Fair.dice({seed_1, seed_2}, rollId)` (seeds in seat order) itself. No message carries a dice value; a seat-0 `{k="dice"}` event from a host is flagged.
  4. `DICE_WAIT = 10` seconds after the open without `g`'s seed, the host publishes its own seed alone and the dice are `Fair.dice({seed_d}, rollId)`: the silent seat has lost its say over that throw. **A throw is never opened again for the same host**; a new `h` exists only after a host change (the new host does not hold the old seeds; a host that reloads or goes silent after the guest's seed arrived loses its seed, so the new host's throw is a new number).
  5. What this leaves: the host orders the events, so a modified host client could look at `g`'s seed before publishing. The guest's client shows it: a throw replaced after it sent its seed is `"bad", "dodge"`; a throw the host made alone although it sent its commit or its seed counts as unheard, red from the second one in a match; a snapshot that drops or rewrites a throw I revealed to is a dodge. Also left (accepted, F9): a host that `/reload`s or goes silent after the guest's seed arrived loses its seed; after `SILENT_AFTER` the guest hosts and opens a new number, so a modified host gains one re-roll per hosting at the price of the host role and 75 s; no `DealKeep` for dice.
- Timeout = the automatic move: the host's turn timer plays `E.auto` (the first legal full move) after `turn` seconds, for either seat, online or not. Every number of a Гюлбара cascade and a transferred remainder is a turn of its own with a full clock. No automatic loss; a player offline for `OFFLINE_STAND_SECONDS = 180` is stood up and loses the match (no money, no ledger).
- Bots play `E.auto`; Табла has no `E.bot`. `core/Bots.lua` is not edited.
- `core/Session.lua` is **not edited** (539 lines; the limit is below 540). `core/Deal.lua`, `core/DealHooks.lua`, `core/Member.lua`, `core/Lifecycle.lua` are not edited. The throw's wait lives in `s.fairTimer`, which Session's `TIMERS` already cancels. `core/Dice.lua` stays below 300 lines. `ui/TableFrame.lua` changes only in `renderFair`, `fairTooltip` and the header comment (lines 18-20, "On a card table (ns.Deal.status) …") and stays below 660 lines (636 today; no extraction).
- Board: view frame 512 × 260, centred on the felt as Сантасе is. Board 404 × 232 at the frame's top left: an 8 px rim, a left quadrant of six points (x 8–176), the bar 24 wide (176–200), a right quadrant (200–368), the tray 28 wide (368–396). Points 28 × 96, checkers 26 × 26, stacked 17 apart, at most five drawn per point (a number on the fifth above five). The board is always drawn from my side: my point 1 bottom right, 12 bottom left, 13 top left, 24 top right (a watcher: seat 1's side). Seat 1 plays the light checkers, seat 2 the dark ones, on every client.
- Colours (mockup 07, variant 1): field `#2a140b`, bar and tray `#3a2010`, points `#7a1f24` and `#e9d9b6`, light checker `#f3e8d0`, dark checker `#3b1d10`, legal target `#ffd100`. Dice: cream `#f6ecd6`, rim `#8a6a2b`, pips `#a3161c`.
- Textures are generated by `tools/gen_textures.py` (standard library only), appended to `TEXTURES` so the fifteen existing files stay byte-identical.
- Commits are local only, never pushed; every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A player chooses the dice by delaying or withholding its reveal.** Pinned by Task 3 (`a guest that never reveals gets no second throw: after DICE_WAIT the host throws alone`, `the opener's seed leaves its client only in the event that fixes the dice`, `a host that throws again over a seed it was sent is caught by that guest`).
2. **A reconnect in the middle of a throw.** Pinned by Task 3 (`a guest that was away when the throw opened commits from the snapshot`, `a guest that relogs after its commit cannot open it: the host throws alone and nobody is blamed`, `the host vanishes mid-throw: the new host throws under a new number`).
3. **The Гюлбара remainder passes to the opponent.** Pinned by Task 4 (`the cascade's remainder passes to the opponent with a full clock; idle, the host's clock plays it and then the opponent throws`) and Task 6 (`a transferred remainder names whose throw I finish`).
4. **A mother pin ends the game.** Pinned by Task 1 (`stage: a mother pin is a whole move with a die left`), Task 4 (`a mother pin ends the game at the table for 2 points and Гюлбара follows`) and Task 7 (`a mother pin lights „Готово“ after one step`).
5. **„Готово“ sends an illegal partial move.** Pinned by Task 1 (`stage: done only for a whole legal move`), Task 6 (`canDone is false while a die can still be played`) and Task 7 (`„Готово“ is dead until the move is whole and then sends the staged steps as one action`).

Also pinned: dice that no throw gave are flagged (Task 3), the clock moves for both seats and an offline player loses after three minutes (Task 4), a bot match runs through all three variants (Task 4), a watcher holds the same board (Task 2), a table event throws away a staged move (Task 7).

---

## File Structure

```
engines/tabla.lua            no E.view; ext {"dice"}, again, result.left, E.stage (Task 1)
core/Fair.lua                + Fair.dice (Task 2)
core/Dice.lua                NEW ns.Dice, ns.Ext.dice: the throw (Task 2), its failures and the status line (Task 3)
core/Const.lua               + DICE_WAIT
core/Games.lua               PLAYABLE.tabla
core/Help.lua                topic "tabla", block kind "dice", the fair topic's dice paragraph
tools/gen_textures.py        + point, checker, dice
media/point.tga  media/checker.tga  media/dice.tga   NEW
ui/Theme.lua                 the three textures, the board colours
ui/TableFrame.lua            the fairness line of a dice game comes from ns.Dice
ui/HelpBook.lua              block kind "dice"
ui/games/TablaModel.lua      NEW ns.TablaModel (pure)
ui/games/TablaView.lua       NEW
locale/bg.lua  locale/en.lua
tests/engines/tabla_test.lua
tests/core/tabla_table_test.lua   NEW
tests/core/{fair,games,member,bots,locale_help}_test.lua
tests/ui/{theme,hall,table,book}_test.lua, tests/ui/{tabla_model,tabla}_test.lua NEW, tests/wow/slash_test.lua
docs/superpowers/notes/2026-11-stageD-ingame-checks.md  NEW
```

TOC: `core/Dice.lua` right after `core/DealKeep.lua` (keeps the Deal trio together); `ui/games/TablaModel.lua`, then `ui/games/TablaView.lua`, after `ui/games/BelotView.lua`.

### Shared contracts (additions to stages 1, A, B and C)

**Engine, optional:** `E.stage(state, seat, steps) -> {pts, pin, bar, off, left, next, done} | nil` (Табла: the position after a partial move, the dice still open, every single step that may follow, and whether the steps are a whole legal move). An engine without `E.view` is an open game.

**Extension `dice`** (`engine.ext = {"dice"}`): answers the engine's `{k="dice", need="dice"}` with a throw and applies `{k="dice", d = {x, y}}` on every client itself.

**Protocol additions:** none. The shapes inside `ACT`/`EV`/`SNP`, for the reader of `/tavern debug`:

| where | shape | meaning |
|---|---|---|
| `EV` seat 0 | `{k="throw", op="open", h, c}` | the host opens throw `h` (= the event's `q`); `c` = the commit of its own seed, 64 hex |
| `ACT` → `EV` seat 0 | `{k="throw", op="commit", h, c}` → `{k="throw", op="commit", h, seat, c}` | the other seat's commit |
| `ACT` | `{k="throw", op="seed", h, s}` | the other seat's seed, 32 hex, to the host only; never relayed as it is |
| `EV` seat 0 | `{k="throw", op="seeds", h, s = {[seat] = seed}}` | both seeds, or the opener's alone after `DICE_WAIT`; every client derives and applies the dice |
| `SNP.fr` | `{h, d, c = {[seat] = commit}}`, or absent | the throw still running (public data): number, opener's seat, commits |
| `ACT` → `EV` seat 1–2 | `{k="move", steps = {{from, to}, …}}` | a whole turn; `from = 25` the bar, `to = 0` off |
| `EV` seat 0 | `{k="next"}` | the next game, 3 s after one ended |

**Session fields (dice games):** `s.throw = {h, d, commits, seed, own, asked, sent, done, alone, reload, foul, replaced}`; `s.diceLast = {h, verdict, why, by, silent, n}`; `s.diceSeen = {ok, alone, bad}`; `s.diceAlone[name]`; `s.diceUnheard`.

**Client event:** `"fair"` is also emitted for every closed throw: `{tid, game, h, verdict = "ok" | "alone" | "bad", why, at}`.

**Test conventions:** as in stages B and C. Names `A, B, W = "Иван Петров", "Мария Стоянова", "Гледач Гледачев"`, clients `a, b, w`. `SEED = ("ff"):rep(16)`, `ZERO = ("00"):rep(16)`, `COMMIT = "352302489bc2fcf025cf00cda8308033f97ac87712ce90b4d7cd72c58e4c3af9"` (= `Fair.commit(SEED)`). In the simulator `env.random` returns its upper bound unless `sim.nextRandom` is filled, so every seed is `SEED` and the dice of throw `h` are `ns.Fair.dice({SEED, SEED}, tid .. "/" .. h)`. `arr`, `sum`, `GAME`, `pos`, `roll`, `mv` are the helpers at the top of `tests/engines/tabla_test.lua`; a test file outside it copies them verbatim. Every commit step's message is followed by the trailer line of the Global Constraints.

---

# Part D1 — Табла at the table, proven in the simulator

### Task 1: The engine: an open game, staging, „Нова игра“

**Files:**
- Modify: `engines/tabla.lua`, `tests/engines/tabla_test.lua`

**Interfaces:**
- Consumes: the file-locals `gen`, `step`, `key`, `copyPos`, `distinct`, `without` of `engines/tabla.lua`.
- Produces:
  - `E.view` is removed. `E.ext = {"dice"}`, `E.again = true` (no `E.nextFirst`: a new match begins with the opening throw). `E.result(s)` also returns `left = s.quit`.
  - `E.stage(s, seat, steps) -> t | nil`. nil unless `s.phase == "move"`, `s.turn == seat` and `steps` is a list of `{from, to}` number pairs that can be played in that order as the beginning of some move `E.apply` accepts. Otherwise `t` with:
    - `pts, pin, bar, off` = the position after the steps (fresh tables shaped as the state's; `s` is untouched);
    - `left` = the dice not yet used, for the first die assignment that still leads to a legal move;
    - `done` = `E.apply(s, seat, {k="move", steps = steps})` would accept;
    - `next` = every distinct `{from, to}` such that `steps` plus that step is again stageable, sorted by `from` descending, then `to` descending; `{}` when `done`.
  - How: `local _, byKey = gen(s)`; a step is tried with every distinct open die as `sim` does; a position with dice `rem` is viable when its `key` is in `byKey` or some `step` with a die of `rem` leads to a viable one (memoised per call by `key(p)` and `rem`). With no legal move at all `E.stage(s, seat, {})` is `{done = true, next = {}, left = <the dice>}`.
  - Header: rule 4 says the dice come from the extension `dice`; „STATE AND ACTIONS“ (a new short block under the rules) states: open game, no view; `E.stage`; `E.again`.

- [ ] **Step 1: Write the failing tests** (a new `describe("tabla staging")`; `NOMOVE` is the file's).

```lua
it("an open game: no view, dice by the extension, a new match on request, the result names a leaver", function()
  eq(E.view, nil); eq(E.ext, { "dice" }); eq(E.again, true); eq(E.nextFirst, nil)
  local s = E.new{}; roll(s, 5, 2); E.leave(s, 1); eq(E.result(s), { winners = { 2 }, losers = { 1 }, left = 1 })
end)
it("stage: what may follow a partial move, and done only for a whole legal move", function()
  local s = E.new{}; roll(s, 6, 1); roll(s, 3, 1)                                     -- seat 1 moves a 3 and a 1
  local r = E.stage(s, 1, {})
  eq({ r.done, r.left }, { false, { 3, 1 } }); eq(r.next, { { 24, 23 }, { 24, 21 }, { 13, 10 }, { 8, 7 }, { 8, 5 }, { 6, 5 }, { 6, 3 } })
  r = E.stage(s, 1, { { 8, 5 } }); eq({ r.done, r.left }, { false, { 1 } }); eq(r.next, { { 24, 23 }, { 8, 7 }, { 6, 5 }, { 5, 4 } })
  eq({ E.apply(E.restore(E.snapshot(s)), 1, { k = "move", steps = { { 8, 5 } } }) }, { nil, "move" })
  r = E.stage(s, 1, { { 24, 23 } }); eq(r.left, { 3 }); eq(r.next, { { 24, 21 }, { 23, 20 }, { 13, 10 }, { 8, 5 }, { 6, 3 } })
  r = E.stage(s, 1, { { 8, 5 }, { 6, 5 } }); eq({ r.done, r.left, r.next }, { true, {}, {} })
  eq(r.pts[1], arr{ [24] = 2, [13] = 5, [8] = 2, [6] = 4, [5] = 2 }); eq(s.pts[1][8], 3); eq(s.left, { 3, 1 })
  eq(E.stage(s, 2, {}), nil); eq(E.stage(s, 1, { { 8, 4 } }), nil); eq(E.stage(s, 1, { { 8, 5 }, { 6, 5 }, { 6, 5 } }), nil)
  eq(E.stage(s, 1, "x"), nil); eq(E.stage(s, 1, { { 8 } }), nil); eq(E.stage(E.new{}, 1, {}), nil)
end)
it("stage: a double, a blocked roll, bearing off", function()
  local d = pos("std", 1, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }); roll(d, 6, 6)
  local r = E.stage(d, 1, {}); eq(r.left, { 6, 6, 6, 6 }); eq(r.next, { { 24, 18 }, { 13, 7 }, { 8, 2 } })
  r = E.stage(d, 1, { { 24, 18 }, { 24, 18 }, { 13, 7 } }); eq({ r.done, r.left }, { false, { 6 } }); eq(r.next, { { 13, 7 }, { 8, 2 } })
  local u = pos("std", 1, { [24] = 2, [13] = 12 }, { [6] = 2, [5] = 2, [4] = 2, [3] = 2, [2] = 2, [1] = 2, [24] = 3 }, { bar = { 1, 0 } }); roll(u, 3, 4)
  eq(E.legal(u, 1), NOMOVE); r = E.stage(u, 1, {}); eq({ r.done, r.next, r.left }, { true, {}, { 3, 4 } })
  local bo = pos("std", 1, { [2] = 1, [1] = 1 }, { [24] = 15 }); roll(bo, 6, 5)
  eq(E.stage(bo, 1, {}).next, { { 2, 0 } }); r = E.stage(bo, 1, { { 2, 0 } }); eq({ r.done, r.left, r.next }, { false, { 5 }, { { 1, 0 } } })
  eq(E.stage(bo, 1, { { 2, 0 }, { 1, 0 } }).done, true)
end)
it("stage: a mother pin is a whole move with a die left; a cascade number that cannot be finished is whole too", function()
  local mp = pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 }); roll(mp, 3, 5)
  eq(E.stage(mp, 1, {}).next, { { 10, 7 }, { 4, 1 } }); local r = E.stage(mp, 1, { { 4, 1 } }); eq({ r.done, r.left, r.next }, { true, { 5 }, {} })
  eq(r.pin[2][24], 1); eq(E.stage(mp, 1, { { 4, 1 }, { 10, 5 } }), nil)
  local g = pos("gul", 1, { [24] = 1, [12] = 1 }, { [7] = 1, [20] = 14 }, { rolls = { 3, 0 } }); roll(g, 5, 5)
  eq(E.stage(g, 1, {}).next, { { 12, 7 } }); r = E.stage(g, 1, { { 12, 7 } }); eq({ r.done, r.left, r.next }, { false, { 5, 5, 5 }, { { 7, 2 } } })
  r = E.stage(g, 1, { { 12, 7 }, { 7, 2 } }); eq({ r.done, r.left }, { true, { 5, 5 } })
end)
it("stage agrees with legal and apply on random positions", function()
  --[[ the loop of the fuzz test with its LCG seeded 20261123, 30 games: at every position with a seat to move (the first 400 of them),
  for every move m of E.legal(s, seat): for k = 0 .. #m.steps − 1 the result of E.stage(s, seat, <the first k steps>) is not nil, has
  done == false and its `next` contains m.steps[k + 1]; E.stage(s, seat, m.steps).done == true and its `next` is {}.
  And for every step x of E.stage(s, seat, {}).next: E.stage(s, seat, { x }) ~= nil. bad == 0; at least 1000 moves were checked ]]
end)
```

Existing test to change: `snapshot round-trips mid-game, view is an equal copy` (around line 119) drops `eq(E.view(s, 2), E.snapshot(s))` and is renamed `snapshot round-trips mid-game`; `a seat that leaves loses the match…` (around line 324) and `variants cycle…` compare `E.result` as the engine now returns it: `left = 1` for `s` in the first, `left = 1` / `left = 2` for `t` in the second (`variants cycle…` gains no `left` where nobody left). Nothing else in the file changes.

- [ ] **Step 2: Run `bash t.sh tests/engines/tabla_test.lua`.** Expected: the five new tests FAIL (`E.view` is a function; `E.stage` is nil).
- [ ] **Step 3: Implement** in `engines/tabla.lua`. No rule changes.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass (Табла is not playable yet, so nothing else moves).
- [ ] **Step 5: Commit.** `git add engines/tabla.lua tests/engines/tabla_test.lua` — `feat(tabla): an open game with a staging helper; a new match on request`

### Task 2: A throw by two players

**Files:**
- Create: `core/Dice.lua`, `tests/core/tabla_table_test.lua`; Modify: `core/Fair.lua`, `core/Const.lua`, `core/Games.lua`, `TavernGames.toc`, `tests/core/fair_test.lua`, `tests/core/games_test.lua`, `tests/core/member_test.lua`, `tests/core/bots_test.lua`, `tests/ui/hall_test.lua`, `tests/wow/slash_test.lua`

**Interfaces:**
- Consumes: Task 1; `Fair.seed`, `Fair.commit`, `Fair.handId`, `Deck.key`, `Deck.stream`, `Deck.below`, `Session:play`, `Session.message`, `s.fairTimer`.
- Produces:
  - `Fair.dice(seeds, rollId) -> x, y`: `local next = Deck.stream(Deck.key(seeds, rollId))`; `x = Deck.below(next, 6) + 1`, then `y` the same way. (This is spec 6.3's „SHA256(seed_a ‖ seed_b ‖ rollId) mod 6, twice“ with length-prefixed seeds and without the bias of a plain `mod`.)
  - `Const.DICE_WAIT = 10`. `Games.PLAYABLE.tabla = true` (comment: holdem E remains).
  - `core/Dice.lua`: `ns.Dice`, `ns.Ext.dice`. Its header states the throw (Global Constraints, rules 1–5) and the session fields. Nothing is sent from the `table` hook (as in `core/DealHooks.lua`); sending happens in `applied`, `adopted`, the `act` hook and the wait.
    - `Dice.open(s)` (host, seated, and `engine.system(s.state)` asks for `need == "dice"`; else nothing): `h = s.seq + 1`, a fresh seed kept in `s.diceMine = {h, seed}`, the wait replaced (`s.fairTimer`, `DICE_WAIT`, Task 3 gives it its effect), then `s:play(0, {k="throw", op="open", h = h, c = Fair.commit(seed)})`.
    - hook `need(s, action)`: host and `action.need == "dice"` only; `need` returns whenever `s.throw` exists and is not `done` (re-arming the wait if it is missing; the session offers `need` after every event); else `Dice.open(s)`. Only an explicit `Dice.open` (the forged host of Task 3 test 6) opens over a running throw, because rule 4 binds.
    - hook `table(s, a)`, `a.k == "throw"` only (anything else: nil, the engine gets it). Returns true when applied, nil to refuse:
      - `open`: `a.h == s.seq + 1`, `a.c` is 64 hex, the host's name holds a seat `d`, the engine asks for dice → `s.throw = {h = a.h, d = d, commits = {[d] = a.c}}`.
      - `commit`: the running throw's `h`, `a.seat == 3 − d` and occupied, no commit there yet, `a.c` 64 hex → stored.
      - `seeds`: the running throw's `h`; `a.s` a table with no key but `d` and `g`; `a.s[d]` is `2 × SEED_BYTES` hex and its commit is `commits[d]`; `a.s[g]` absent, or hex with its commit equal to `commits[g]`. Dice = `Fair.dice({a.s[1], a.s[2]}, Fair.handId(s.tid, h))`, or of `{a.s[d]}` alone; applied on a copy of `s.state` through `engine.apply(copy, 0, {k="dice", d = {x, y}})` (refused → nil), then `s.state = copy`, `throw.done = true`, `throw.alone = g` when `a.s[g]` is absent.
    - hook `act(s, seat, a)`: an action that is not `k == "throw"` passes through. A throw action is never played as it is: for the running throw's `h` from seat `g`, for `commit` (none yet, 64 hex) the hook calls `s:play(0, {k="throw", op="commit", h, seat = g, c})` itself; for `seed` (both commits in, the host holds its own seed, `Fair.commit(a.s) == commits[g]`) it calls `s:play(0, {k="throw", op="seeds", h, s = {[d] = throw.seed, [g] = a.s}})` itself. The hook returns nil for every throw action (as DealHooks' `act` does: a non-nil result would be played at the member's seat, where the engine refuses `k = "throw"`); anything else is dropped.
    - hook `applied(s, seat, a)`: `start`/`abort` at seat 0 drop the throw and the wait (`start` also `s.diceLast`, `s.diceSeen`, `s.diceAlone`, `s.diceUnheard`). After `open`: the host moves `s.diceMine.seed` into `throw.seed` (`throw.own = a.c`); the player at `g` that is not the host makes its seed (`throw.seed`, `throw.own`) and whispers `ACT {k="throw", op="commit", h, c}` (`throw.asked`; repeated every 3 s, twice at most, see Task 3). After `commit` for my own seat with `a.c == throw.own`: `ACT {k="throw", op="seed", h, s}` (`throw.sent`; repeated like the commit). After `seeds`: the host stops the wait and the throw closes: `s.diceLast = {h, verdict = "ok", by = <the opener's name>}`, `s.diceSeen.ok + 1`, client event `"fair"`.
    - hook `snap(s)`: `{h, d, c = copy(commits)}` while a throw runs, else nil.
    - `Dice.status(s) -> key, tone, arg, arg2 | nil` (nil for an engine without the extension `dice`); in this task `"dice.rolling", "inkDim"` while a throw runs and `"dice.ok", "good"` after one closed `"ok"`; nil before the first throw.
  - TOC: `core/Dice.lua` after `core/DealKeep.lua`.

- [ ] **Step 1: Write the failing tests.** `tests/core/fair_test.lua` (new `it`):

```lua
it("dice come from the seeds and the throw's id; each die is uniform", function()
  eq({ F.dice({ ZERO, SEED }, "t#1/1") }, { 4, 5 }); eq({ F.dice({ SEED, ZERO }, "t#1/1") }, { 2, 1 }); eq({ F.dice({ ZERO, SEED }, "t#1/2") }, { 1, 4 })
  eq({ F.dice({ SEED, SEED }, "t#1/1") }, { 3, 3 }); eq({ F.dice({ ZERO }, "t#1/1") }, { 1, 4 }); eq({ F.dice({ ("ab"):rep(16) }, "t#1/7") }, { 2, 2 })
  local n, doubles = { 0, 0, 0, 0, 0, 0 }, 0
  for i = 1, 3600 do
    local x, y = F.dice({ ZERO, SEED }, "x/" .. i); n[x] = n[x] + 1; n[y] = n[y] + 1
    if x == y then doubles = doubles + 1 end
  end
  eq(n, { 1213, 1208, 1188, 1239, 1169, 1183 }); eq(doubles, 601)
end)
```

`tests/core/tabla_table_test.lua`. Helpers: `table2(turn)` = a new sim, `a, b, w` added in that order, `sim:run(1)`; `tid = a:openTable{ game = "tabla", access = "guild", turn = turn or 45 }`, `sim:run(3)`; `w:watch(tid)`, `sim:run(1)`; returns `sim, tid` (B is not seated yet). `seat()` = `b:sit(tid, 2); sim:run(1)`. `evs(name, from)` = the `a` of every `EV` sent to `name` after index `from` of `sim.sent`, in order. `fairs(cl)` = the list of that client's `"fair"` payloads. `E = ns.Engines.tabla`, `FIRST = { { 24, 20 }, { 24, 20 }, { 13, 9 }, { 13, 9 } }` (a legal first move of seat 1 with 4:4).

```lua
it("two players throw together: three events a throw, the dice on no wire, the same board for everyone", function()
  local sim, tid = table2(); local mark = #sim.sent; seat(); eq(tid, "Иван Петров#1700000001")
  eq({ ns.Fair.dice({ SEED, SEED }, tid .. "/3") }, { 6, 1 }); eq({ ns.Fair.dice({ SEED, SEED }, tid .. "/6") }, { 4, 4 })
  local st = a.session.state                                                        -- sit, start, the opening throw (seat 1 starts), its own throw
  eq({ st.phase, st.turn, st.dice, st.left, a.session.seq }, { "move", 1, { 4, 4 }, { 4, 4, 4, 4 }, 8 })
  local ev = evs(B, mark); eq(#ev, 7); eq(ev[1], { k = "start" })
  eq(ev[2], { k = "throw", op = "open", h = 3, c = COMMIT }); eq(ev[3], { k = "throw", op = "commit", h = 3, seat = 2, c = COMMIT })
  eq(ev[4], { k = "throw", op = "seeds", h = 3, s = { SEED, SEED } }); eq({ ev[5].op, ev[5].h, ev[7].op, ev[7].h }, { "open", 6, "seeds", 6 })
  eq(b.session.state, st); eq(w.session.state, st)
  for _, cl in ipairs{ a, b, w } do
    eq(cl.session.diceLast, { h = 6, verdict = "ok", by = A }); eq(cl.session.diceSeen, { ok = 2, alone = 0, bad = 0 }); eq(cl.session.throw.done, true)
    eq({ ns.Dice.status(cl.session) }, { "dice.ok", "good" })
  end
  eq(sim:count(function(m) return m.msg.t == "EV" and m.msg.a.k == "dice" end), 0)
  eq(sim:count(function(m) return m.from == B and m.msg.t == "ACT" end), 4)             -- a commit and a seed per throw
  eq(sim:count(function(m) return m.channel == "GUILD" and (m.msg.t == "EV" or m.msg.t == "ACT") end), 0)
end)
it("a turn is one move event, then the next throw", function()
  local sim, tid = table2(); seat(); local seen = fairs(w)
  eq({ a:act{ k = "move", steps = { { 24, 20 } } } }, { nil, "move" }); ok(a:act{ k = "move", steps = FIRST }); sim:run(1)
  local st = b.session.state; eq({ st.turn, st.phase, st.dice, b.session.seq }, { 2, "move", { 4, 3 }, 12 }); eq(b.session.diceLast.h, 10)
  eq({ #seen, seen[1].h, seen[1].verdict, seen[1].game }, { 1, 10, "ok", "tabla" }); eq(w.session.state, a.session.state)
  ok(b:act(E.auto(b.session.state, 2))); sim:run(1); eq({ a.session.state.turn, a.session.state.dice, a.session.seq }, { 1, { 1, 4 }, 16 })
end)
it("the table hook takes only what fits the throw", function()
  local sim, tid = table2(); seat(); local s, T = b.session, ns.Ext.dice.table
  eq(T(s, { k = "throw", op = "open", h = s.seq + 1, c = COMMIT }), nil)               -- the engine wants no dice now
  eq(T(s, { k = "throw", op = "seeds", h = 6, s = { SEED, SEED } }), nil)             -- that throw is closed
  eq(T(s, { k = "move", steps = {} }), nil); eq(ns.Ext.dice.act(a.session, 2, { k = "move", steps = {} }), { k = "move", steps = {} })
  eq(ns.Ext.dice.act(a.session, 2, { k = "throw", op = "seed", h = 6, s = SEED }), nil); eq(a.session.seq, 8)
  eq(ns.Ext.dice.snap(a.session), nil); eq(ns.Dice.status({ engine = function() return ns.Engines.ttt end }), nil)   -- not a dice game
end)
```

Existing tests to change (Табла is no longer the gated game; Холдем is): `tests/core/games_test.lua` (the list test: `ok(G.engine("tabla") == ns.Engines.tabla)`, `ok(G.list()[5].engine == ns.Engines.tabla)`, `eq(G.list()[6].engine, nil)`; the TBL test around line 95 uses `g="holdem"`); `tests/core/member_test.lua` around line 42 (`holdem` as the gated engine); `tests/core/bots_test.lua` around line 366 (`hostTable("holdem")` is nil); `tests/ui/hall_test.lua` around lines 148–172 (five active games, one dimmed: indices 1–5 and 6; the dimmed click uses `games[6]`); `tests/wow/slash_test.lua` (the two `bots host tabla` → „не е готова“ checks use `holdem`; new: `w:slash("bots host tabla"); w:advance(1)` lists a table with `game == "tabla"`).

- [ ] **Step 2: Run `bash t.sh tests/core/fair_test.lua tests/core/tabla_table_test.lua`.** Expected: FAIL (`F.dice` is nil; `openTable` returns nil, `"game"`).
- [ ] **Step 3: Implement** `Fair.dice`, the constant, `core/Dice.lua` as far as this task describes it, the TOC line, `PLAYABLE.tabla` and the test changes.
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add core/Dice.lua core/Fair.lua core/Const.lua core/Games.lua TavernGames.toc tests/core/tabla_table_test.lua tests/core/fair_test.lua tests/core/games_test.lua tests/core/member_test.lua tests/core/bots_test.lua tests/ui/hall_test.lua tests/wow/slash_test.lua` — `feat: Табла at the table; dice thrown by a commit-reveal of the two players`

### Task 3: A throw that goes wrong

**Files:**
- Modify: `core/Dice.lua`; Test: `tests/core/tabla_table_test.lua`

**Interfaces:**
- Produces (all in `core/Dice.lua`):
  - **The wait.** `DICE_WAIT` after `Dice.open`, on my own table, still its host, the same `h` not done and my seed in hand: `s:play(0, {k="throw", op="seeds", h, s = {[d] = throw.seed}})`. On every client such a throw closes `verdict = "alone"`, with `silent` = the name at `g`, `s.diceAlone[by] + 1` and `n` = that count. A client at `g` that had sent its commit (`throw.asked`) or its seed (`throw.sent`) also counts `s.diceUnheard + 1`. To keep honest losses rare the guest repeats its last throw ACT (the commit, or the seed once its commit is in) every 3 s while that throw runs, twice at most (the host's act hook already ignores a second commit and a seed after the close).
  - **`adopted(s, prev, m, how)`.** A host keeps nothing. A member takes `m.fr` only when it is well formed (`h` an integer not above `m.q`, `d` 1 or 2, `c[d]` 64 hex, `c[g]` absent or 64 hex) and the adopted state asks for dice; else no throw. A throw of the number I already hold keeps my seed, my `own` and what I sent is asked again (`sent = nil`); the opener's commit having changed is the foul `"commit"`. A commit under my own seat that is not my `own`: `reload = true` only when `how.fresh` (I logged in again); otherwise it is the foul `"mine"` whether or not I hold a seed. A throw I hold, not done, for which I sent my commit or seed, that the snapshot drops or replaces by another `h`: closed `"bad", "dodge"` when the snapshot is unsolicited (`not how.asked and not how.changed`), else counted as unheard (`s.diceUnheard + 1`; I missed events and cannot judge). A non-fresh member takes no `fr` whose `h <= max(throw and throw.h or 0, diceLast and diceLast.h or 0)` other than the throw it holds. Then my part is done as in `applied`: commit when my seat has none, reveal when my own commit stands.
  - **`hostChanged(s)`**: the throw, `s.diceMine` and the wait are dropped on every client; the new host's timers offer `need` and it opens a throw with a new number.
  - **Fouls** (`throw.foul`, the first one wins, decides the verdict `"bad"` with that reason when the throw closes): `"mine"` (the commit event under my seat is not my commit; I then send no seed), `"commit"`. Two verdicts need no running throw: an `open` that replaces a throw of mine that was not done, under the same host, after I had sent my seed, closes the replaced one `"bad", "dodge"` (in `applied`; the `table` hook keeps it as `throw.replaced`); a seat-0 `{k="dice"}` event closes `"bad", "forged"` with `h` = that event's number.
  - **`Dice.status(s)`** in full: `"dice.rolling", "inkDim"` while a throw runs; else by `s.diceLast`: `"dice.ok", "good"`; `"dice.alone", "gold", by, silent`, or from that opener's second one in the match `"dice.aloneMany", "gold", by, n`; `"dice.bad", "red"`. The tone is `"red"` whenever `Dice.alarm(s)`: a bad throw in this match (`s.diceSeen.bad > 0`) or `s.diceUnheard >= 2`.
  - **`Dice.tip(s) -> {{tone, key, arg}, …}`** for the tooltip: always `{"ink", "dice.tip"}`; after a bad throw `{"red", "dice.tip.bad", <why>}`; with `s.diceUnheard` `{"red", "dice.unheard", n}`.

- [ ] **Step 1: Write the failing tests** (appended; `mute(name, op)` = wraps `sim.envs[name].send` so that an `ACT` with `a.k == "throw"` and `a.op == op` is dropped while the client believes it sent it, and returns a function that lifts it; `mentions(msg, words)` copied from `tests/core/bots_test.lua`; `SA = ("01"):rep(16)`).

```lua
it("a guest that never reveals gets no second throw: after DICE_WAIT the host throws alone", function()
  local sim, tid = table2(); for i = 1, 16 do sim.nextRandom[i] = 1 end; local mark = #sim.sent      -- A's first seed is SA, B's is SEED
  mute(B, "seed"); seat()
  eq({ a.session.state.phase, a.session.seq, a.session.throw.h, a.session.throw.commits[2] }, { "open", 4, 3, COMMIT })
  eq({ ns.Dice.status(a.session) }, { "dice.rolling", "inkDim" }); eq(sim:count(function(m) return mentions(m.msg, { SA }) end), 0)
  sim:run(9); eq({ a.session.state.phase, a.session.seq }, { "open", 4 })
  sim:run(1); local st = a.session.state
  eq({ ns.Fair.dice({ SA }, tid .. "/3") }, { 4, 1 }); eq({ st.phase, st.turn, st.dice }, { "roll", 1, { 4, 1 } }); eq(b.session.state.dice, { 4, 1 })
  local ev = evs(W, mark)                                                                -- sit, start, then the throw
  eq({ ev[3].op, ev[4].op, ev[5] }, { "open", "commit", { k = "throw", op = "seeds", h = 3, s = { SA } } })
  eq(ev[6], { k = "throw", op = "open", h = 6, c = COMMIT })                             -- the next throw, not this one again
  eq(a.session.diceLast, { h = 3, verdict = "alone", by = A, silent = B, n = 1 }); eq({ ns.Dice.status(w.session) }, { "dice.rolling", "inkDim" })
  eq({ b.session.diceUnheard, ns.Dice.alarm(b.session), a.session.diceUnheard }, { 1, false, nil })
  sim:run(10); eq({ a.session.diceLast.h, a.session.diceLast.n, a.session.state.phase }, { 6, 2, "move" }); eq({ ns.Dice.status(a.session) }, { "dice.aloneMany", "gold", A, 2 })
  eq({ b.session.diceUnheard, ns.Dice.alarm(b.session), ns.Dice.alarm(a.session), ns.Dice.alarm(w.session) }, { 2, true, false, false })
  eq(ns.Dice.tip(b.session), { { "ink", "dice.tip" }, { "red", "dice.unheard", 2 } })
  sim, tid = table2(); mute(B, "commit"); seat(); sim:run(10)                              -- the host never sees the guest's commit and throws alone
  eq({ b.session.diceUnheard, a.session.diceLast.verdict }, { 1, "alone" })
end)
it("the opener's seed leaves its client only in the event that fixes the dice", function()
  local sim, tid = table2(); for i = 1, 16 do sim.nextRandom[i] = 1 end; seat()
  local first, guest
  for i, m in ipairs(sim.sent) do
    if not first and mentions(m.msg, { SA }) then first = i end
    if not guest and m.from == B and m.msg.t == "ACT" and m.msg.a.op == "seed" then guest = i end
  end
  ok(guest < first); eq({ sim.sent[first].msg.t, sim.sent[first].msg.a.op, sim.sent[first].msg.a.s }, { "EV", "seeds", { SA, SEED } })
  eq(a.session.state.dice ~= nil, true); eq({ ns.Fair.dice({ SA, SEED }, tid .. "/3") }, { 3, 5 })
end)
it("a guest that was away when the throw opened commits from the snapshot", function()
  local sim, tid = table2(); seat(); sim:offline(B); ok(a:act{ k = "move", steps = FIRST }); sim:run(2)
  eq({ a.session.state.phase, a.session.throw.h, a.session.throw.commits[2], a.session.seq }, { "roll", 10, nil, 10 })
  eq(ns.Ext.dice.snap(a.session), { h = 10, d = 1, c = { COMMIT } })
  local b2 = sim:relog(B); sim:run(2)
  eq({ a.session.state.phase, a.session.state.dice, a.session.seq }, { "move", { 4, 3 }, 12 }); eq(a.session.diceLast, { h = 10, verdict = "ok", by = A })
  eq(b2.session.diceLast.verdict, "ok"); eq(b2.session.state, a.session.state)
end)
it("a guest that relogs after its commit cannot open it: the host throws alone and nobody is blamed", function()
  local sim, tid = table2(); mute(B, "seed"); seat(); local atA = fairs(a)
  local b2 = sim:relog(B); local atB = fairs(b2); sim:run(3)
  eq({ b2.session.throw.h, b2.session.throw.reload, b2.session.throw.seed, b2.session.throw.foul }, { 3, true, nil, nil })
  sim:run(8); eq({ atA[1].verdict, atA[2].verdict, atB[1].verdict, atB[2].verdict }, { "alone", "ok", "alone", "ok" })
  eq({ b2.session.diceUnheard, ns.Dice.alarm(b2.session), ns.Dice.alarm(a.session) }, { nil, false, false }); eq(b2.session.state, a.session.state)
end)
it("the host vanishes mid-throw: the new host throws under a new number", function()
  local sim, tid = table2(); local lift = mute(B, "seed"); seat(); sim:offline(A); lift()
  for _ = 1, 100 do if b.session.role == "host" then break end; sim:run(1) end                 -- 75 s of silence
  eq({ b.session.role, b.session.throw.h, b.session.throw.d, b.session.state.phase }, { "host", 5, 2, "open" })
  sim:run(10); eq({ ns.Fair.dice({ SEED }, tid .. "/5") }, { 2, 2 })
  eq(b.session.diceLast, { h = 5, verdict = "alone", by = B, silent = A, n = 1 }); eq({ b.session.state.dice, b.session.state.phase }, { { 2, 2 }, "open" })
end)
it("a host that throws again over a seed it was sent is caught by that guest; dice that no throw gave are flagged", function()
  local sim, tid = table2(); mute(B, "seed"); seat(); local atB, atW = fairs(b), fairs(w)
  ns.Dice.open(a.session); sim:run(1)                                                       -- a second open over throw 3
  eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, 3, "bad", "dodge" }); eq(#atW, 0); eq(ns.Dice.alarm(b.session), true)
  a.session:play(0, { k = "dice", d = { 6, 2 } }); sim:run(1)
  eq({ atW[1].verdict, atW[1].why, w.session.state.dice }, { "bad", "forged", { 6, 2 } }); eq({ ns.Dice.status(w.session) }, { "dice.rolling", "red" })
  eq(ns.Dice.tip(w.session)[2], { "red", "dice.tip.bad", "forged" })
end)
it("a snapshot from my own host that drops or rewrites a throw I revealed to is caught", function()
  local sim, tid = table2(); mute(B, "seed"); seat(); local atB = fairs(b)                 -- B holds throw 3 and has sent its seed
  a.session.throw = nil; a.session:snapshotTo(B); sim:run(1)
  eq({ atB[1].h, atB[1].verdict, atB[1].why }, { 3, "bad", "dodge" })
  sim:run(10); local s = b.session                                                          -- throw 6 opens; B commits and reveals again
  a.session.throw.commits[2] = ns.Fair.commit(ZERO); a.session:snapshotTo(B); sim:run(1)    -- the host's own commit under B's seat, not B's own
  a.session:play(0, { k = "throw", op = "seeds", h = s.throw.h, s = { SEED, ZERO } }); sim:run(1)
  eq({ atB[#atB].verdict, atB[#atB].why }, { "bad", "mine" })
  local old = s.throw.h; ns.Ext.dice.adopted(s, nil, { q = s.seq, fr = { h = 3, d = 1, c = { COMMIT } } }, {}); eq(s.throw.h, old)   -- an fr at or below h 6 is not taken
end)
it("seeds that do not open the commits are refused", function()
  local sim, tid = table2(); mute(B, "seed"); seat(); local s, T = b.session, ns.Ext.dice.table
  eq(T(s, { k = "throw", op = "seeds", h = 3, s = { SEED, ZERO } }), nil); eq(T(s, { k = "throw", op = "seeds", h = 3, s = { [2] = SEED } }), nil)
  eq(T(s, { k = "throw", op = "seeds", h = 3, s = { SEED, SEED, SEED } }), nil); eq(T(s, { k = "throw", op = "seeds", h = 4, s = { SEED, SEED } }), nil)
  eq(T(s, { k = "throw", op = "commit", h = 3, seat = 2, c = COMMIT }), nil); eq(T(s, { k = "throw", op = "commit", h = 3, seat = 1, c = COMMIT }), nil)
  eq({ s.state.phase, s.throw.done }, { "open", nil }); eq(T(s, { k = "throw", op = "seeds", h = 3, s = { SEED, SEED } }), true); eq(s.state.dice, { 6, 1 })
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/tabla_table_test.lua`.** Expected: the first, fourth, fifth, sixth and the new snapshot test FAIL (the throw never ends; no `"alone"`; no `"dodge"`); the third fails on the snapshot round (`adopted` is missing); the second and the last pass already and stay as pins.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `11 passed, 0 failed`; all pass. `wc -l core/Dice.lua` is below 300.
- [ ] **Step 5: Commit.** `git add core/Dice.lua tests/core/tabla_table_test.lua` — `feat(core): a silent player loses its say over a throw; reconnects and a new host mid-throw`

### Task 4: The whole game at the table and with a bot

**Files:**
- Test: `tests/core/tabla_table_test.lua`, `tests/core/bots_test.lua`; Modify: `core/Dice.lua` only if a test below fails

**Interfaces:** none new. These are the pins of Review Focus 3 and 4 and of the user's decisions about timeouts, leaving and bots. On a prototype of Tasks 1–3 every one of them passed with the values written here, so the expected result of Step 2 is that they pass; a failure is a defect of Tasks 1–3 and is fixed there, not by changing a value.

- [ ] **Step 1: Write the tests.** `rigged(state)` = `ns.Ext.dice = {}` (nothing throws by itself), `table2()`, `seat()`, then `a.session.state, b.session.state, w.session.state` = three copies of `state`; `dice(x, y)` = `a.session:play(0, { k = "dice", d = { x, y } }); sim:run(1)`; the test ends with `ns.Ext.dice = REAL` (`local REAL = ns.Ext.dice` at file scope). `results(cl)` = that client's `"result"` payloads.

```lua
it("nobody moves: the host's clock plays the first legal move for either seat", function()
  local sim, tid = table2(30); seat(); local mark = #sim.sent
  eq({ a.session.state.turn, a.session:left(), E.auto(a.session.state, 1).steps }, { 1, 30, { { 24, 20 }, { 24, 20 }, { 20, 16 }, { 20, 16 } } })
  sim:run(29); eq(a.session.seq, 8); sim:run(1)
  eq({ a.session.state.turn, a.session.state.phase, a.session.state.dice, a.session.seq, a.session:left() }, { 2, "move", { 4, 3 }, 12, 30 })
  sim:run(30); eq({ a.session.state.turn, a.session.seq }, { 1, 16 }); eq(b.session.state, a.session.state)
  eq(sim:count(function(m) return m.target == B and m.msg.t == "EV" and m.msg.auto == true end), 2)
  eq(sim:count(function(m) return m.msg.t == "ACT" and m.msg.a.k == "move" end), 0)
end)
it("a player offline for three minutes is stood up and loses; meanwhile the host throws alone", function()
  local sim, tid = table2(30); seat(); local res = results(a); sim:offline(B); local t0 = sim.clock
  for _ = 1, 200 do if #res > 0 then break end; sim:run(1) end
  ok(sim.clock - t0 >= 180 and sim.clock - t0 <= 185); eq({ res[1].game, res[1].winners, res[1].losers, res[1].left, res[1].names }, { "tabla", { 1 }, { 2 }, 2, { A, B } })
  eq(a.session.status, "aborted"); ok(a.session.diceSeen.alone >= 3); eq(a.session.diceSeen.bad, 0)
end)
it("a player who stands up loses the match and the result names it", function()
  local sim, tid = table2(); seat(); local res = results(w); b:stand(); sim:run(2)
  eq({ #res, res[1].winners, res[1].losers, res[1].left }, { 1, { 1 }, { 2 }, 2 }); eq({ w.session.state.phase, w.session.state.winner }, { "match", 1 })
end)
it("the cascade's remainder passes to the opponent with a full clock; idle, the host's clock plays it and then the opponent throws", function()
  local sim = rigged(pos("gul", 1, { [24] = 1, [12] = 1 }, { [7] = 1, [20] = 14 }, { rolls = { 3, 0 } }))
  dice(5, 5); eq({ b.session.state.left, b.session.state.cv }, { { 5, 5, 5, 5 }, 5 })
  ok(a:act{ k = "move", steps = { { 12, 7 }, { 7, 2 } } }); sim:run(1); local st = b.session.state
  eq({ st.turn, st.phase, st.left, st.cv, st.xfer, b.session:left() }, { 2, "move", { 5, 5 }, 5, true, 45 })
  eq({ b:act{ k = "move", steps = { { 20, 15 } } } }, { nil, "move" })                 -- half of the remainder is not a move
  sim:run(43); eq(a.session.state.left, { 5, 5 }); sim:run(1); st = a.session.state
  eq({ st.turn, st.phase, st.left, st.cv, st.pts[2][15], st.pts[2][20] }, { 2, "move", { 6, 6, 6, 6 }, 6, 2, 12 })
  sim:run(45); st = a.session.state; eq({ st.turn, st.phase, st.left, st.cv, st.xfer, st.rolls }, { 2, "roll", nil, nil, nil, { 4, 0 } })
  eq(b.session.state, st); eq(w.session.state, st); ns.Ext.dice = REAL
end)
it("a mother pin ends the game at the table for 2 points and Гюлбара follows", function()
  local sim = rigged(pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 })); local res = results(a)
  dice(3, 5); ok(a:act{ k = "move", steps = { { 4, 1 } } }); sim:run(1); local st = b.session.state
  eq({ st.phase, st.gw, st.gp, st.score, st.pin[2][24], st.turn, #res }, { "game", 1, 2, { 2, 0 }, 1, nil, 0 })
  sim:run(3); st = w.session.state; eq({ st.phase, st.var, st.game, st.turn, st.score }, { "roll", "gul", 3, 1, { 2, 0 } }); ns.Ext.dice = REAL
end)
```

`tests/core/bots_test.lua` (`setup()` and `mentions` as in the file):

```lua
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
  --[[ as in the Сантасе test: no entry of sim.sent after mark mentions tid or the bot's name, and A sent something for real ]]
  ok(a:startGame()); sim:run(4); eq({ a.session.state.score, a.session.state.game, a.session.state.var }, { { 0, 0 }, 1, "std" }); eq(a.session.diceSeen.bad, 0)
end)
it("a bot hosts Табла, throws with me and starts the next match", function()
  --[[ tid = bots:hostTable("tabla"); sim:run(3); a:sit(tid, 2); sim:run(4): a.session.status == "live", a.session.diceLast.by is the bot's name,
  verdict "ok". Play to the end with my seat 2 on auto (as above); exactly one result; sim:run(6): a.session.state.score == {0, 0} ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/tabla_table_test.lua tests/core/bots_test.lua`.** Expected: all pass (`16 passed, 0 failed` in the first file). Measured on the prototype: the bot match ended 0:5 after three games, 168 throws, about 300 simulated seconds, under half a second of wall time.
- [ ] **Step 3: If one fails**, fix the defect in `core/Dice.lua` or `engines/tabla.lua` (never the value), and add the case to the task it belongs to.
- [ ] **Step 4: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add tests/core/tabla_table_test.lua tests/core/bots_test.lua` (and `core/Dice.lua` if touched) — `test: Табла timeouts, leaving, the cascade's remainder, a mother pin and a bot match pinned at the table`

**— End of D1. Boundary check before D2: `bash t.sh` green, the Review Focus tests of Tasks 1, 3 and 4 exist and pass. D2 changes no rule and no message of Tasks 1–4. —**

---

# Part D2 — the board, the rules book

### Task 5: Board textures

**Files:**
- Modify: `tools/gen_textures.py`, `ui/Theme.lua`; Create: `media/point.tga`, `media/checker.tga`, `media/dice.tga`; Test: `tests/ui/theme_test.lua`

**Interfaces:**
- Produces: `Theme.texSize.point = {32, 128}`, `checker = 64`, `dice = {128, 64}` (and so `Theme.tex.point`, `.checker`, `.dice`); `Theme.color.boardField = hex("2a140b")`, `boardBar = hex("3a2010")`, `pointLight = hex("e9d9b6")`, `bone = hex("f3e8d0")`, `walnut = hex("3b1d10")`, `glow = hex("ffd100")`.
- Drawing (the file's `cover`, `sd_convex`, `sd_circle`, `sd_round_rect`): `point` = a white triangle on transparent, base the whole top edge, tip at the bottom centre (the view flips it for the lower row and tints it); `checker` = a white disc of radius 30 centred in 64 × 64 with a rim 3 px wide and a ring of radius 18, 2 px wide, both at grey 0.45 (tinted in code: bone or walnut); `dice` = six 32 × 32 cells, faces 1–4 in the top row and 5, 6 in the bottom row (the last two cells transparent): a rounded square (radius 5) `#f6ecd6` with a 2 px rim `#8a6a2b` and pips of radius 3 in `#a3161c` at the mockup's places scaled to 32 (`PIPS` of `docs/mockups/07-wow-authentic.html`, × 32 / 30). The three entries are **appended** to `TEXTURES`.

- [ ] **Step 1: Write the failing test** (in the existing `it` of `tests/ui/theme_test.lua`): `eq(Theme.texSize.point, { 32, 128 }); eq(Theme.texSize.checker, 64); eq(Theme.texSize.dice, { 128, 64 }); ok(n >= 18)`; and `eq({ Theme.rgb("glow") }, { 1, 209 / 255, 0 })`.
- [ ] **Step 2: Run `bash t.sh tests/ui/theme_test.lua`.** Expected: FAIL (`point` is nil).
- [ ] **Step 3: Implement**, then run `"C:\Users\daxx\AppData\Local\Python\bin\python.exe" tools/gen_textures.py` (or `py tools/gen_textures.py`). Expected output ends with `media/point.tga 32x128`, `media/checker.tga 64x64`, `media/dice.tga 128x64`, and `git status --short media` lists only those three files as new.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add tools/gen_textures.py ui/Theme.lua media/point.tga media/checker.tga media/dice.tga tests/ui/theme_test.lua` — `feat(media): point, checker and dice textures for the Табла board`

### Task 6: The Табла model

**Files:**
- Create: `ui/games/TablaModel.lua`; Modify: `TavernGames.toc`; Test: `tests/ui/tabla_model_test.lua`

**Interfaces:**
- Consumes: `ns.Engines.tabla` (`stage`, `abs`, `over`; state fields `phase`, `turn`, `var`, `game`, `score`, `pts`, `pin`, `bar`, `off`, `dice`, `left`, `rolls`, `cv`, `xfer`, `gw`, `gp`, `winner`, `quit`).
- Produces `ns.TablaModel.build(s, staged, pick, names) -> model`. It reads only `s.state`, `s.mySeat`, `s.status`, `s.seats` (a plain table will do) and `names` (optional: seat → who held it during the match). It stores nothing.
  - `me` = my seat, or 1 for a watcher; `op = 3 − me`; `seated`; `var`, `game`; `score = {me = state.score[me], op = state.score[op]}`.
  - `mine` = seated, `s.status == "live"`, phase `"move"`, `state.turn == me`. `stage` = `E.stage(state, me, staged)` when `mine`; when that is nil the staged steps no longer fit: `reset = true` and the model is built as with `staged = {}`.
  - The position is `stage` when `mine`, else the state. `points[q]` for `q = 1 … 24` in **my** numbering = `{own = pts[me][q], opp = pts[op][x], under}` with `x = E.abs(var, 2, q)` (the other seat's number of my point; the mapping is its own inverse) and `under = "own"` when `pin[me][q] == 1`, `"opp"` when `pin[op][x] == 1`, else nil (whose pinned checker lies at the bottom). `bar = {own, opp}`, `off = {own, opp}`.
  - `dice` = `{state.cv, state.cv}` while `state.cv` (a Гюлбара cascade: `state.dice` stays the thrown pair while `left` is the cascade number), else `state.dice` (nil before the first throw); `left` = `stage.left` when `mine`, else `state.left or {}`; `rolling` = `s.status == "live"` and phase `"open"` or `"roll"`.
  - `from` = `{[q] = true}` for every first element of `stage.next` (25 = the bar), `{}` when not `mine`; `pick` = the given `pick` when `from[pick]`, else nil; `to` = `{[q] = true}` for every `{pick, q}` in `stage.next` (0 = the tray), `{}` without a pick.
  - `canUndo` = `mine` and `#staged > 0`; `canDone` = `mine` and `stage.done`; `stuck` = `canDone` and `#staged == 0`.
  - `text = {key, …}`, the first that applies: `E.over(state)` → `{"tabla.left", name of state.quit}` when `state.quit`, else seated `{state.winner == me and "tabla.match.won" or "tabla.match.lost"}`, a watcher `{"tabla.match.name", name of the winner}`. Phase `"game"` → `{"tabla.game.mother", name of gw}` when `var == "tapa"`, `gp == 2` and the loser's `pin[…][24] == 1`; `{"tabla.game.mars", name}` when `gp == 2`; else `{"tabla.game.won", name}`. Phase `"open"` → `{"tabla.opening"}`. Phase `"roll"` → `{"tabla.opens", name of turn}` while `state.game == 1`, `state.dice` is set and `state.rolls` is `{0, 0}`; else `{"tabla.rolling", name of turn}`. Phase `"move"`, `mine`: `{"tabla.stuck"}` when `stuck`; `{"tabla.ready"}` when `canDone`; `{"tabla.pickTarget"}` with a pick; `{"tabla.xfer.mine", cv, name of op}` when `state.xfer`; `{"tabla.cascade", cv}` when `state.cv`; else `{"tabla.yourTurn"}`. Phase `"move"`, not mine: `{"tabla.xfer", name of turn, cv, name of the other}` when `state.xfer`, else `{"tabla.waitFor", name of turn}`. Otherwise nil. A name is `names[seat]`, else `s.seats[seat]`, else `"?"`.

- [ ] **Step 1: Write the failing tests.** File scope: `guildWow()` as in the other UI tests; `M, E = w.ns.TablaModel, w.ns.Engines.tabla`; `sess(state, seat)` = `{ game = "tabla", status = "live", mySeat = seat, seats = { A, B }, state = state }`; `build(st, seat, staged, pick)` = `M.build(sess(st, seat), staged or {}, pick)`; `set(t)` = the sorted list of the keys of `t`; the engine-test helpers copied.

```lua
it("the board from my side; what I may pick, where it may land; canDone is false while a die can still be played", function()
  local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1); local m = build(st, 1)
  eq({ m.me, m.mine, m.var, m.dice, m.left, m.score, m.rolling }, { 1, true, "std", { 3, 1 }, { 3, 1 }, { me = 0, op = 0 }, false })
  eq({ m.points[24], m.points[1], m.points[6], m.points[19], m.points[12], m.points[17] },
     { { own = 2, opp = 0 }, { own = 0, opp = 2 }, { own = 5, opp = 0 }, { own = 0, opp = 5 }, { own = 0, opp = 5 }, { own = 0, opp = 3 } })
  eq({ set(m.from), set(m.to), m.pick, m.canUndo, m.canDone, m.text }, { { 6, 8, 13, 24 }, {}, nil, false, false, { "tabla.yourTurn" } })
  m = build(st, 1, {}, 8); eq({ m.pick, set(m.to), m.text }, { 8, { 5, 7 }, { "tabla.pickTarget" } }); eq(build(st, 1, {}, 7).pick, nil)
  m = build(st, 1, { { 8, 5 } }); eq({ m.points[8].own, m.points[5].own, m.left, set(m.from), m.canUndo, m.canDone }, { 2, 1, { 1 }, { 5, 6, 8, 24 }, true, false })
  m = build(st, 1, { { 8, 5 }, { 6, 5 } }); eq({ m.canDone, set(m.from), m.left, m.text, m.stuck }, { true, {}, {}, { "tabla.ready" }, false })
  m = build(st, 1, { { 8, 4 } }); eq({ m.reset, m.points[8].own, m.canUndo }, { true, 3, false })
  m = build(st, 2); eq({ m.me, m.mine, set(m.from), m.points[1], m.points[24], m.text }, { 2, false, {}, { own = 0, opp = 2 }, { own = 2, opp = 0 }, { "tabla.waitFor", A } })
  m = build(st, nil); eq({ m.me, m.seated, m.mine, m.canDone }, { 1, false, false, false })
end)
it("a pinned checker lies under its pinner; Гюлбара puts the opponent's start on my 12", function()
  local s = pos("tapa", 1, { [10] = 1, [9] = 1, [24] = 13 }, { [18] = 1, [20] = 1, [24] = 13 }); roll(s, 3, 2); mv(s, { { 10, 7 }, { 9, 7 } })
  eq(build(s, 1).points[7], { own = 2, opp = 1, under = "opp" }); eq(build(s, 2).points[18], { own = 1, opp = 2, under = "own" })
  local g = pos("gul", 1, { [24] = 15 }, { [24] = 15 })
  eq({ build(g, 1).points[24], build(g, 1).points[12], build(g, 2).points[12] }, { { own = 15, opp = 0 }, { own = 0, opp = 15 }, { own = 0, opp = 15 } })
end)
it("the bar, the tray and a roll with no move", function()
  local bo = pos("std", 1, { [2] = 1, [1] = 1 }, { [24] = 15 }); roll(bo, 6, 5); local m = build(bo, 1, {}, 2)
  eq({ set(m.to), m.off }, { { 0 }, { own = 13, opp = 0 } }); eq(build(bo, 1, { { 2, 0 } }).off.own, 14)
  local u = pos("std", 1, { [24] = 2, [13] = 12 }, { [6] = 2, [5] = 2, [4] = 2, [3] = 2, [2] = 2, [1] = 2, [24] = 3 }, { bar = { 1, 0 } })
  eq(build(u, 1).rolling, true); roll(u, 3, 4); m = build(u, 1)
  eq({ m.bar, set(m.from), m.canDone, m.stuck, m.text }, { { own = 1, opp = 0 }, {}, true, true, { "tabla.stuck" } })
  local e = pos("std", 1, { [24] = 2, [13] = 12 }, { [24] = 15 }, { bar = { 1, 0 } }); roll(e, 3, 4); eq(set(build(e, 1).from), { 25 })
end)
it("a transferred remainder names whose throw I finish; the cascade names its number", function()
  local g = pos("gul", 1, { [24] = 1, [12] = 1 }, { [7] = 1, [20] = 14 }, { rolls = { 3, 0 } }); roll(g, 5, 5)
  eq(build(g, 1).text, { "tabla.cascade", 5 }); local c = E.restore(E.snapshot(g)); c.cv, c.left = 6, { 6, 6, 6, 6 }; eq(build(c, 2).dice, { 6, 6 }); mv(g, { { 12, 7 }, { 7, 2 } })
  eq({ build(g, 2).mine, build(g, 2).text, build(g, 2).left }, { true, { "tabla.xfer.mine", 5, A }, { 5, 5 } }); eq(build(g, 1).text, { "tabla.xfer", B, 5, A })
end)
it("the throw, the end of a game and of the match in words", function()
  local st = E.new{}; eq(build(st, 1).text, { "tabla.opening" }); eq(build(st, 1).dice, nil); roll(st, 6, 1); eq(build(st, 2).text, { "tabla.opens", A })
  roll(st, 3, 1); mv(st, { { 8, 5 }, { 6, 5 } }); eq(build(st, 1).text, { "tabla.rolling", B })
  local mp = pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 }); roll(mp, 3, 5); mv(mp, { { 4, 1 } }); eq(build(mp, 2).text, { "tabla.game.mother", A })
  --[[ a game won 1 point: {"tabla.game.won", name}; gp == 2 in "std": {"tabla.game.mars", name}; phase "match", winner 2: seat 2 {"tabla.match.won"},
  seat 1 {"tabla.match.lost"}, a watcher {"tabla.match.name", B}; state.quit = 1 with seats[1] = false and names = {A, B}: {"tabla.left", A} ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/tabla_model_test.lua`.** Expected: FAIL (`TablaModel` is nil).
- [ ] **Step 3: Implement**; TOC line `ui/games/TablaModel.lua` after `ui/games/BelotView.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `5 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add ui/games/TablaModel.lua TavernGames.toc tests/ui/tabla_model_test.lua` — `feat(ui): the Табла board as a pure model`

### Task 7: The Табла view and the dice line

**Files:**
- Create: `ui/games/TablaView.lua`; Modify: `ui/TableFrame.lua`, `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`; Test: `tests/ui/tabla_test.lua`, `tests/ui/table_test.lua`

**Interfaces:**
- Consumes: `ns.TablaModel.build`, `ns.Dice.status`, `ns.Dice.tip`, `client:act`, `TableFrame.registerView`, `W.GoldButton`, `W.GhostButton`, `W.Label`, `W.colored`, the textures of Task 5.
- Produces: `TableFrame.registerView("tabla", View)` with `View.build(parent)`, `View.update(f, s)`, `View.seatNote(s, seat)` = `L(seat == 1 and "tabla.light" or "tabla.dark", state.score[seat])`, `""` without a state. The frame (512 × 260) exposes `points[1..24]`, `bar`, `tray`, `dice[1..2]`, `stepsLeft`, `undoButton`, `doneButton`, `title`, `score`, `text`, and the view's memory `staged`, `pick`.
- `View.update` stores `f.session = s`, keeps `f.names`/`f.namesTid` as BelotView does, and holds the staged move: `f.staged` (a list of steps) and `f.pick` are emptied whenever the key `tid/epoch/seq` changes (any table event) and when the model says `reset`; `f.sent` (a move went to the host) is cleared the same way. It then draws `M.build(s, f.staged, f.pick, f.names)`.
- Clicks (each redraws): a point `q` (the bar: 25; the tray: 0) with `model.to[q]` appends `{pick, q}` to `f.staged` and drops the pick; else with `model.from[q]` it becomes the pick (the picked one again: no pick); else nothing. `undoButton` removes the last staged step and the pick. `doneButton`, only while `model.canDone` and not `f.sent`: `ns.client:act({k="move", steps = <a copy of f.staged>})`; true → `f.sent = true` (the buttons and the checkers are dead until the event comes back: after a send `IsEnabled()` is false for both buttons); refused → `f.staged = {}`.
- Drawing, offsets from the frame's `TOPLEFT`:
  - The rim 404 × 232 at `(0, 0)` in `wood`; the field `(8, −8)` 388 × 216 in `boardField`; `bar` a button 24 × 216 at `(176, −8)` and `tray` a button 28 × 216 at `(368, −8)`, both `boardBar`.
  - `points[q]`: a button 28 × 96. Bottom row at `y = −128`: `x = 200 + (6 − q) × 28` for `q = 1 … 6`, `x = 8 + (12 − q) × 28` for `7 … 12`. Top row at `y = −8`: `x = 8 + (q − 13) × 28` for `13 … 18`, `x = 200 + (q − 19) × 28` for `19 … 24`. Its `tri` is the `point` texture (the lower row with `SetTexCoord(0, 1, 1, 0)`), tinted `felt` on odd `q` and `pointLight` on even `q`.
  - Checkers: up to five `checker` textures 26 × 26 per point, centred across, 17 apart from the point's base (the top row grows down, the bottom row up); first the pinned checker (`under`), then the opponent's or mine; each has `.seat` (whose colour: `bone` for seat 1, `walnut` for seat 2). Above five: `count` (font 11, on the fifth) shows the number. `bar` shows mine in its lower half and the opponent's in its upper half the same way; `tray.own` (bottom) and `tray.opp` (top) are numbers, hidden at 0.
  - `points[q].glow`, `bar.glow`, `tray.glow`: the `glow` texture over the widget, tinted `glow`, alpha 0.45, shown for `model.to[q]`. `points[q].ring` (the `ring` texture, 30 × 30 around the outermost checker; `bar.ring` likewise): shown for `model.from[q]`, alpha 1 on the pick, else 0.45.
  - Right column (x 412–512): `title` = `L("tabla.title", L("tabla.var." .. var), game)` heading 14 at `(412, −4)`; `score` = `L("tabla.score", me, op)` dim 11 at `(412, −24)`; `dice[1]`, `dice[2]` 32 × 32 at `(426, −70)` and `(466, −70)`, the face `n` cut from `dice` by `SetTexCoord(c / 4, (c + 1) / 4, r / 2, (r + 1) / 2)` with `c = (n − 1) % 4`, `r = floor((n − 1) / 4)`; hidden without `model.dice` or while `rolling` in phase `"open"`; alpha 0.4 for a die whose value is not in `model.left` (a double: both, once `left` is empty); `stepsLeft` = `L("tabla.stepsLeft", #model.left)` dim 11 at `(412, −110)`, shown in phase `"move"`; `undoButton` = `W.GhostButton(f, L("tabla.undo"), "brassLight", fn)` then `SetSize(96, 24)` (as SantaseView/BelotView; the default is 124 × 24) at `(414, −176)`, shown for a seated player, alpha 0.5 and disabled unless `canUndo`; `doneButton` = `W.GoldButton` (`SetSize(96, 24)`) at `(414, −206)`, `L("tabla.done")`, the same with `canDone`.
  - `text`: heading 14, centred on `(202, −246)`, gold in phases `"game"` and `"match"`; a name in it is class-coloured.
- `ui/TableFrame.lua`: `renderFair` asks `ns.Deal.status(s)` first and, when that is nil, `key, tone, arg, arg2 = ns.Dice.status(s)`: the line shows `L(key, arg, arg2)` in `Theme.rgb(tone)`. `fairTooltip`, for a session whose `ns.Dice.status` is not nil, prints the lines of `ns.Dice.tip(s)` instead (`L(key, arg)`, a reason as `L("dice.why." .. arg)`). Both are read at call time (`ns.Dice.status(s)`, never a file-local copy: a test replaces them). The line still opens the rules book on `"fair"`. The header comment says so.
- Locale (bg; en in brackets), new sections `-- Табла` and `-- Dice (table line)` after the Белот section in both files: `tabla.var.std` = „Обикновена“ (`Standard`); `tabla.var.tapa` = „Тапа“ (`Tapa`); `tabla.var.gul` = „Гюлбара“ (`Gul bara`); `tabla.title` = „%s · игра %d“ (`%s · game %d`); `tabla.score` = „%d : %d · до 5“ (`%d : %d · to 5`); `tabla.light` = „бели · %d“ (`light · %d`); `tabla.dark` = „черни · %d“ (`dark · %d`); `tabla.undo` = „Върни“ (`Undo`); `tabla.done` = „Готово“ (`Done`); `tabla.stepsLeft` = „Остават: %d“ (`Left: %d`); `tabla.opening` = „Хвърляме по един зар за първи ход…“; `tabla.opens` = „%s започва.“; `tabla.rolling` = „%s хвърля…“; `tabla.yourTurn` = „Твой ход: кликни пул“ (`Your move: click a checker`); `tabla.pickTarget` = „Кликни светнало поле“; `tabla.ready` = „Ходът е нареден. Натисни „Готово“.“; `tabla.stuck` = „Нямаш ход. Натисни „Готово“.“; `tabla.waitFor` = „Изчакай %s…“; `tabla.cascade` = „Гюлбара: играеш чифт %d“; `tabla.xfer.mine` = „Доиграваш чифт %d на %s“; `tabla.xfer` = „%s доиграва чифт %d на %s“; `tabla.game.won` = „%s печели играта.“; `tabla.game.mars` = „Марс! %s взима 2 точки.“; `tabla.game.mother` = „Затисната майка! %s взима 2 точки.“; `tabla.match.won` = „Печелиш партията!“; `tabla.match.lost` = „Губиш партията.“; `tabla.match.name` = „%s печели партията!“; `tabla.left` = „%s стана от масата.“; `dice.rolling` = „Хвърляме заровете заедно…“; `dice.ok` = „Зарове: хвърлени от двамата играчи“ (`Dice: thrown by both players`); `dice.alone` = „%s хвърли сам: %s не се включи навреме“; `dice.aloneMany` = „%s хвърли сам вече %d пъти в тази партия“; `dice.bad` = „Зарове: нередовни“; `dice.tip` = „Всеки от двамата дава по едно тайно число и заровете излизат от двете. Никой не знае какво ще се падне, преди да е дал своето.“; `dice.tip.bad` = „Проверката не излезе: %s Кажи на другия.“; `dice.why.forged` = „заровете не дойдоха от хвърляне на двамата.“; `dice.why.dodge` = „домакинът получи моето число и хвърли наново.“; `dice.why.mine` = „моето число е подменено.“; `dice.why.commit` = „домакинът смени своето число, след като го даде.“; `dice.unheard` = „Дадох числото си навреме, а домакинът хвърли сам: %d пъти.“ Where no English is pinned it is a faithful translation.

- [ ] **Step 1: Write the failing tests.** `tests/ui/tabla_test.lua`, file scope: `setup()` = `guildWow()`, a parent frame of 532 × 328 under `UIParent`, `f = View.build(parent)`, `w.ns.client.act` replaced by a stub that records the action in `acts` and returns true; returns `w, View, f, acts`. `sess(state, seat)` as in Task 6 plus `tid = "t#1", epoch = 1, seq = 1, role = seat and "player" or "watcher"`; `draw(f, st, seat)` = `View.update(f, sess(st, seat))`. `shownCheckers(p)` = the `.seat` of every visible checker of that widget, base first. `lit(f)` = the sorted list of `q` whose `f.points[q].glow` is visible.

```lua
it("24 points from my side, the bar and the tray; checkers by seat; five drawn and a number above that", function()
  local w, View, f = setup(); local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1); draw(f, st, 1)
  eq(f.points[1].points[1], { "TOPLEFT", f, "TOPLEFT", 340, -128 }); eq(f.points[6].points[1], { "TOPLEFT", f, "TOPLEFT", 200, -128 })
  eq(f.points[7].points[1], { "TOPLEFT", f, "TOPLEFT", 148, -128 }); eq(f.points[12].points[1], { "TOPLEFT", f, "TOPLEFT", 8, -128 })
  eq(f.points[13].points[1], { "TOPLEFT", f, "TOPLEFT", 8, -8 }); eq(f.points[24].points[1], { "TOPLEFT", f, "TOPLEFT", 340, -8 })
  eq({ f.bar.points[1], { f.bar:GetSize() } }, { { "TOPLEFT", f, "TOPLEFT", 176, -8 }, { 24, 216 } }); eq(f.tray.points[1], { "TOPLEFT", f, "TOPLEFT", 368, -8 })
  eq({ f.points[1].tri.texCoord, f.points[13].tri.texCoord }, { { 0, 1, 1, 0 }, nil }); eq({ f:GetSize() }, { 512, 260 })
  eq(shownCheckers(f.points[24]), { 1, 1 }); eq(shownCheckers(f.points[1]), { 2, 2 }); eq(shownCheckers(f.points[6]), { 1, 1, 1, 1, 1 }); eq(f.points[6].count:IsVisible(), false)
  eq({ f.dice[1].texCoord, f.dice[2].texCoord }, { { 0.5, 0.75, 0, 0.5 }, { 0, 0.25, 0, 0.5 } }); eq(f.title:GetText(), "Обикновена · игра 1"); eq(f.score:GetText(), "0 : 0 · до 5")
  draw(f, pos("tapa", 1, { [24] = 15 }, { [24] = 15 }), 2); eq(#shownCheckers(f.points[24]), 5); eq(f.points[24].count:GetText(), "15"); eq(shownCheckers(f.points[1])[1], 1)
  eq({ View.seatNote(sess(st, 1), 1), View.seatNote(sess(st, 1), 2), View.seatNote(sess(nil, 1), 1) }, { "бели · 0", "черни · 0", "" })
end)
it("„Готово“ is dead until the move is whole and then sends the staged steps as one action", function()
  local w, View, f, acts = setup(); local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1); draw(f, st, 1)
  eq({ lit(f), f.doneButton.enabled, f.undoButton.enabled, f.text:GetText() }, { {}, false, false, "Твой ход: кликни пул" })
  w:click(f.points[7]); eq(f.pick, nil); w:click(f.points[8]); eq({ f.pick, lit(f), f.points[8].ring:GetAlpha() }, { 8, { 5, 7 }, 1 })
  w:click(f.points[5]); eq({ f.staged, f.pick, lit(f) }, { { { 8, 5 } }, nil, {} }); eq({ #shownCheckers(f.points[8]), #shownCheckers(f.points[5]) }, { 2, 1 })
  eq({ f.doneButton.enabled, f.undoButton.enabled, f.dice[1]:GetAlpha(), f.dice[2]:GetAlpha(), f.stepsLeft:GetText() }, { false, true, 0.4, 1, "Остават: 1" })
  eq(f.doneButton:IsEnabled(), false)                                                    -- a partial move never leaves the client (a click on a dead button raises in Wow:click)
  w:click(f.points[6]); w:click(f.points[5]); eq({ f.doneButton.enabled, f.text:GetText() }, { true, "Ходът е нареден. Натисни „Готово“." })
  w:click(f.undoButton); eq({ f.staged, f.doneButton.enabled, #shownCheckers(f.points[6]) }, { { { 8, 5 } }, false, 5 })
  w:click(f.points[6]); w:click(f.points[5]); w:click(f.doneButton); eq(acts, { { k = "move", steps = { { 8, 5 }, { 6, 5 } } } })
  eq({ f.doneButton:IsEnabled(), f.undoButton:IsEnabled(), #acts, #f.staged }, { false, false, 1, 2 })   -- sent (`f.sent`): both buttons are dead, nothing moves until the event is back
end)
it("a table event throws the staged move away; a watcher has no buttons and nothing to pick", function()
  local w, View, f, acts = setup(); local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1); draw(f, st, 1)
  w:click(f.points[8]); w:click(f.points[5]); local s = sess(st, 1); s.seq = 2; View.update(f, s); eq({ f.staged, f.pick, #shownCheckers(f.points[8]) }, { {}, nil, 3 })
  draw(f, st, nil); eq({ f.doneButton:IsVisible(), f.undoButton:IsVisible(), f.points[8].ring:IsVisible() }, { false, false, false })
  w:click(f.points[8]); eq(f.pick, nil); draw(f, st, 2); eq({ f.doneButton:IsVisible(), f.doneButton.enabled, #w:texts("Изчакай ") }, { true, false, 1 })
end)
it("a mother pin lights „Готово“ after one step; bearing off goes to the tray; a blocked roll is confirmed empty", function()
  local w, View, f, acts = setup(); local mp = pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 }); roll(mp, 3, 5); draw(f, mp, 1)
  w:click(f.points[4]); eq(lit(f), { 1 }); w:click(f.points[1]); eq({ f.doneButton.enabled, shownCheckers(f.points[1]) }, { true, { 2, 1 } })
  w:click(f.doneButton); eq(acts[1], { k = "move", steps = { { 4, 1 } } })
  --[[ bo = pos("std", 1, {[2]=1,[1]=1}, {[24]=15}) with 6:5 in a fresh setup: click points[2] → f.tray.glow visible; click f.tray → staged {{2,0}},
  f.tray.own text "14". The blocked position `u` of Task 6 with 3:4: bar shows one checker of seat 1, text „Нямаш ход. Натисни „Готово“.“,
  a click on doneButton sends { k = "move", steps = {} }. A std position with bar = {1, 0} that can enter: f.bar.ring visible, a click on the bar picks 25 ]]
end)
it("solo against a bot from a real throw: dice on the board, the dice line under the felt, the rules book on „Табла“", function()
  --[[ withBots(); I open Табла „Само поканени“ and invite „Бот Иванов“ through the „Покани“ picker; w:advance(3). V = TableFrame.built.tabla,
  s = client.session: s.state.dice ~= nil; both V.dice visible once the phase is "move"; TableFrame.view.fairLine is visible with the text
  „Зарове: хвърлени от двамата играчи“ in the `good` colour; TableFrame.view.info.topic == "tabla"; the two plates read „бели · 0“ and „черни · 0“.
  When it is my move: click a point with V.points[q].ring visible, then a lit point, until V.doneButton is enabled; click it; w:advance(3):
  s.state.turn went to the bot and came back or the game moved on (s.seq grew by at least 4) ]]
end)
```

`tests/ui/table_test.lua` (new `it`): `the fairness line of a dice game: throwing, thrown by both, the host alone, bad` — with a stub `w.ns.Dice.status` returning in turn `"dice.rolling", "inkDim"`; `"dice.ok", "good"`; `"dice.alone", "gold", A, B`; `"dice.bad", "red"`: the line's text is „Хвърляме заровете заедно…“, „Зарове: хвърлени от двамата играчи“, „Иван Петров хвърли сам: Мария Стоянова не се включи навреме“, „Зарове: нередовни“ and its colour `Theme.rgb` of the tone; with `w.ns.Dice.tip` returning `{ { "ink", "dice.tip" }, { "red", "dice.tip.bad", "forged" } }` the tooltip's second line is „Проверката не излезе: заровете не дойдоха от хвърляне на двамата. Кажи на другия.“; a Сантасе table still reads `ns.Deal.status`.

- [ ] **Step 2: Run `bash t.sh tests/ui/tabla_test.lua tests/ui/table_test.lua`.** Expected: FAIL (no view registered for `tabla`; the line is hidden).
- [ ] **Step 3: Implement**; TOC line `ui/games/TablaView.lua` after `ui/games/TablaModel.lua`.
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: `5 passed, 0 failed` in the first; all pass (the locale key sets of bg and en are identical). `wc -l ui/TableFrame.lua` is below 660.
- [ ] **Step 5: Commit.** `git add ui/games/TablaView.lua ui/TableFrame.lua locale/bg.lua locale/en.lua TavernGames.toc tests/ui/tabla_test.lua tests/ui/table_test.lua` — `feat(ui): Табла board with a staged move; the dice line`

### Task 8: Rules-book topic „Табла“

**Files:**
- Modify: `core/Help.lua`, `ui/HelpBook.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/core/locale_help_test.lua`, `tests/ui/book_test.lua`

**Interfaces:**
- Produces:
  - Block kind `"dice"` (`core/Help.lua` header, `ui/HelpBook.lua` `BLOCKS.dice`): a row of die faces `dice = {n, …}` (the `dice` texture, 28 × 28, 6 apart, from x 4) above the text `key`; the block returns `{kind = "dice", text, dice = {textures}}`.
  - `ns.Help.topics` ids `{"hall", "ttt", "deathroll", "santase", "belot", "tabla", "fair", "soon"}`. Topic `tabla` (title `game.tabla`), blocks in this order: `p1`, `example` (kind `example`), `move` (kind `dice`, `{6, 3}`), `staging`, `std`, `bearoff`, `tapa`, `gul` (kind `dice`, `{4, 5, 6}`), `score`, `time`, `fair`. The topic `fair` gains a last block `{kind = "p", key = "help.fair.dice"}`. The quoted-label test also covers `^help%.tabla%.`.
- Locale: the `help.tabla.*` keys go in a new section `-- Rules book: Табла` after `-- Rules book: Белот` in both files. Pinned bg (en = faithful translations in the same simple tone, quoting the English labels of Task 7):
  - `help.tabla.p1` = „Таблата е за двама. Всеки има по 15 пула, води ги по дъската към своя дом и после ги изкарва навън. Който пръв изкара всичките, печели играта. Игрите се редуват: „Обикновена“, „Тапа“, „Гюлбара“ и пак отначало. Партията е до 5 точки.“
  - `help.tabla.example` = „Иван и Мария сядат на табла. Всеки хвърля по един зар: Иван 6, Мария 1. Иван е пръв и хвърля двата зара наново: 4 и 3. Мести един пул с четири полета и друг с три. После хвърля Мария.“
  - `help.tabla.move` = „Всеки зар е един ход на един пул. Един и същ пул може да изиграе и двата зара. Чифт се играе четири пъти. Трябва да изиграеш колкото може повече от хвърленото. Ако става само единият зар, играеш по-големия. Ако няма никакъв ход, натискаш „Готово“ и редът минава.“
  - `help.tabla.staging` = „Как се мести: кликаш свой пул и полетата, на които може да стъпи, светват. Кликаш светнало поле и пулът отива там. Сбърка ли, „Върни“ връща последната стъпка. Когато целият ход е нареден, натискаш „Готово“ и чак тогава другият го вижда.“
  - `help.tabla.std` = „На „Обикновена“ не може да стъпиш на поле с два или повече чужди пула. Ако там има само един, го биеш и той отива на преградата в средата. Бит пул трябва първо да влезе обратно, в дома на противника, преди да местиш друг. Няма ли къде да влезе, хвърлянето пропада.“
  - `help.tabla.bearoff` = „Когато всичките ти пулове са в дома ти (последните шест полета), започваш да ги изкарваш. Зар 4 изкарва пул от четвъртото поле. С по-голям зар изкарваш от най-далечното заето поле, ако по-назад нямаш пулове. Кликаш пула и после светналата кутия вдясно.“
  - `help.tabla.tapa` = „На „Тапа“ всичките 15 пула тръгват от едно поле и не се бие. Стъпиш ли върху сам чужд пул, го затискаш: той не мърда, докато не си тръгнеш оттам. Мария затиска последния пул на Иван, останал на началното му поле. Това е майката. Играта свършва веднага и Мария взима 2 точки.“
  - `help.tabla.gul` = „На „Гюлбара“ двамата обикалят дъската в една посока и не се бие: дори един чужд пул затваря полето. От четвъртото си хвърляне нататък чифтът се играе нагоре. Иван хвърля 4:4, играе четири четворки, после четири петици и четири шестици. Заседне ли на петиците, останалото го доиграва Мария със своите пулове и чак после хвърля за себе си.“
  - `help.tabla.score` = „Спечелена игра е 1 точка. Марс е 2 точки: изкарал си всичките си пулове, а другият още няма нито един изкаран. Затисната майка на „Тапа“ също е 2 точки. Следващата игра започва победителят. Който стигне 5 точки, печели партията. После домакинът натиска „Нова игра“.“
  - `help.tabla.time` = „Ако времето ти изтече, аддонът изиграва вместо теб първия позволен ход. Не губиш служебно. Ако някой стане от масата или го няма повече от три минути, губи партията.“
  - `help.tabla.fair` = „Заровете не ги хвърля сървърът, затова не е нужно да сте в група или един до друг. Всеки от двамата дава по едно тайно число и заровете излизат от двете заедно. Ако единият не се включи до 10 секунди, другият хвърля сам и играта продължава.“
  - `help.fair.dice` = „Заровете на таблата се хвърлят по същия начин. Домакинът заключва своето число. Гостът заключва своето и го показва. Чак тогава домакинът показва двете и всеки аддон сам пресмята заровете. Числото на домакина не излиза, преди да е дошло това на госта. Гостът не може да си избере зар. Подправен аддон на домакина би могъл да хвърли сам или наново, но аддонът на госта го вижда и надписът под масата почервенява.“ (en likewise: the guest cannot pick a die; a modified host addon could throw alone or again, but the guest's addon sees it and the line under the table turns red)
  - `help.soon.p` = „Скоро идва Тексас Холдем, и игра на залог с тефтер на дълговете.“; `help.soon.example` = „Засега в кръчмата се играят Морски шах, Death Roll, Сантасе, Белот и Табла. Тексас Холдем стои блед в списъка, с надпис „Скоро“. Щом стане готов, правилата му ще се появят тук, в книжката.“

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/core/locale_help_test.lua: topics are {"hall","ttt","deathroll","santase","belot","tabla","fair","soon"}; the tabla topic has exactly two
-- dice blocks, {6, 3} and {4, 5, 6}, every value an integer 1..6; the last block of the fair topic is help.fair.dice;
-- the quoted-label loop also covers ^help%.tabla%. and finds at least 10 labels there in each language;
-- pinned: T.bg["help.tabla.tapa"], T.bg["help.tabla.time"], T.bg["help.fair.dice"], T.bg["help.soon.p"], T.bg["help.soon.example"] equal the
-- strings above; T.en["tabla.undo"] == "Undo"; T.en["tabla.done"] == "Done"; T.en["dice.ok"] == "Dice: thrown by both players".
-- tests/ui/book_test.lua
it("the Табла topic draws its dice and is listed between Белот and the fair deal", function()
  --[[ the topic list reads hall, ttt, deathroll, santase, belot, "tabla=Табла", fair, soon; B.open("tabla"): the page's blocks of kind "dice" are two,
  with 2 and 3 textures; the first block's textures have texCoord {0.25, 0.5, 0.5, 1} (6) and {0.5, 0.75, 0, 0.5} (3), 28 x 28, the second 34 px
  right of the first; HelpBook.current == "tabla"; B.open("fair"): the last block's text is L("help.fair.dice") ]]
end)
```

Existing tests to change: `tests/core/locale_help_test.lua:25/37/88` (the kind allowlist at :37 gains `"dice"`; the topic titles at :25 and :88 gain Табла) and `tests/ui/book_test.lua:47/215` (the topic list at :47 gains `tabla=Табла`; :215 reads `names[7] == "fair=…"`, was `names[6]`).

- [ ] **Step 2: Run `bash t.sh tests/core/locale_help_test.lua tests/ui/book_test.lua`.** Expected: FAIL (the topic is missing; `help.soon.p` still names Табла).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add core/Help.lua ui/HelpBook.lua locale/bg.lua locale/en.lua tests/core/locale_help_test.lua tests/ui/book_test.lua` — `feat(ui): rules-book topic for Табла`

### Task 9: In-game check list and documentation

**Files:**
- Create: `docs/superpowers/notes/2026-11-stageD-ingame-checks.md`; Modify: `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` (`### Shared contracts`: a subsection „Stage D additions“), `docs/superpowers/notes/engine-contract.md` („Addendum 6 (stage D, Табла)“)

**Interfaces:** none. The notes file holds the table below with a `Result` column, every row `not yet measured`. Nothing is marked passed on the strength of the unit tests.

- [ ] **Step 1: `bash t.sh`.** Expected: `N passed, 0 failed`.
- [ ] **Step 2: Write the notes file** (`/console scriptErrors 1` throughout; rows 1–9 need one character, rows 10–18 two characters in different zones and not in a group, rows 15 and 18 a third as a watcher):

| # | Check | What to look for |
|---|---|---|
| 1 | `/tavern bots`, open Табла „Само поканени“, invite a bot | the board with my home bottom right; „Хвърляме по един зар за първи ход…“, then who starts; the plates read „бели · 0“ and „черни · 0“; under the felt „Зарове: хвърлени от двамата играчи“ in green |
| 2 | my move | my movable checkers carry a faint ring; a click lights the legal points in yellow; a click on a lit point moves the checker; the used die fades; „Остават: N“ counts down |
| 3 | „Върни“ and „Готово“ | „Върни“ takes back one step at a time; „Готово“ is dull until the whole move is staged; the bot sees nothing before „Готово“ |
| 4 | a double | four steps; „Остават: 4“ at the start |
| 5 | a roll with no legal move | „Нямаш ход. Натисни „Готово“.“; „Готово“ is lit at once |
| 6 | let the clock run out with half a move staged | the first legal move is played for me; my staged steps are gone; no loss |
| 7 | play Обикновена to bearing off | a hit checker lies on the bar and must enter first; in the home board a click on a checker lights the tray; the tray counts |
| 8 | the second game, Тапа | 15 on one point with the number „15“; a pinned checker lies under its pinner and cannot be picked; a mother pin ends the game with „Затисната майка!“ |
| 9 | the third game, Гюлбара, a double after the third throw | „Гюлбара: играеш чифт N“, each number its own „Готово“; a remainder the bot cannot play comes to me as „Доиграваш …“; play to 5 points: one result, „Нова игра“ starts with the opening throw; ⓘ opens „Табла“ with the dice pictures |
| 10 | two characters in different zones, no group | the table fills; every throw lands in under about a second; no `/roll` line in chat; both read the same dice |
| 11 | `/tavern debug` on both during one throw | the lines `open`, `commit`, the guest's `seed` and `seeds`, in that order; no line with dice values; the host's seed appears only in `seeds` |
| 12 | the guest `/reload`s while a throw is running | at most ten seconds later the dice are there; „… хвърли сам: … не се включи навреме“ in amber; the next throw is green again; no script error |
| 13 | the guest `/reload`s on its own move | the board, the dice and the clock are back within about two seconds; it can still stage and send its move |
| 14 | the host logs out mid-game | after about 75 s the guest hosts the table, a new throw is made, play goes on; back within three minutes the old host continues as guest; after three minutes it is stood up and loses |
| 15 | a watcher from the start, and one who comes mid-game | the same board and dice as the players, seat 1's side, no buttons, no rings |
| 16 | the guest enters a loading screen (hearthstone) on the host's throw | the host throws alone after ten seconds; play is not held up; the guest returns to the right board |
| 17 | a player presses „Стани“ mid-game | „… стана от масата.“; the other wins the match; the banner „Играта е прекъсната.“ |
| 18 | count the whispers of one turn with `/tavern debug` (two players and a watcher) | the host sends about 8 addon whispers a turn (four events to two members), the guest 3; no visible ChatThrottleLib delay over a whole game |
| 19 | the table at UI scale 0.65 and 1.0 | 26 px checkers and 28 px points are clickable; the numbers on a stack are readable; the right column, the dice line and the plates do not overlap |
| 20 | a long double in Тапа or Гюлбара with many checkers out | no hitch when a checker is clicked (`E.stage` on a double: watch the frame rate) |

- [ ] **Step 3: Update the two documents**: the stage 1 plan's Shared contracts gets this plan's contract items (`E.stage`, the extension `dice`, the action table, the session fields, the `"fair"` event for a throw) under „Stage D additions“; `docs/superpowers/notes/engine-contract.md` gets Addendum 6 (stage D, Табла): Табла has no `E.view` (this replaces „still provide it“ of the Dice section: an engine without `view` is an open game and the host's clock moves for either seat); `E.stage`; `E.again` without `E.nextFirst`; the throw's five rules; a seat-0 `{k="dice"}` is applied by the extension, never sent; the automatic-move retry of Addendum 5 is view-only, so an open game has exactly one automatic move per deadline (the host's turn timer); the forged-move check does not run for an open game: the host may move for any seat of an open game and the guest sees it on its own board, as in Морски шах; a host that is lost or silent after seeing the guest's seed re-rolls the throw once per hosting (no `DealKeep` for dice).
- [ ] **Step 4: Report to the user** which rows need two characters, that bots play the first legal move (a weak opponent), and the decisions of the Self-review.
- [ ] **Step 5: Commit.** `git add docs/superpowers/notes/2026-11-stageD-ingame-checks.md docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md docs/superpowers/notes/engine-contract.md` — `docs: stage D in-game check list and contract additions`

---

## Self-review (applied)

- **Spec coverage:** 5.3 Табла (three modes, two players) → the engine as merged, its rules unchanged (Task 1 adds contract functions only); „заровете се генерират с commit-reveal между двамата, а не със сървърен `/roll`… от всяко място в гилдията“ → Tasks 2–3, check list rows 10–11; „позволените крайни позиции светят“ → Tasks 6–7 (`to`, `glow`); „ходът се потвърждава с „Върни“/„Готово““ → Tasks 1, 6, 7; 5.3а topic in bg/en with tavern talk and small pictures → Task 8; 6.2 timeout = automatic move, no automatic loss → Task 4; 6.3 „двамата играчи публикуват commit, после двата seed-а… всичко се показва веднага“ → Task 2 (both commits are events, both seeds are one event, the dice are derived by every client at once); section 8 (no cube, Обикновена → Тапа → Гюлбара, to 5, mars 2) → the engine, pinned at the table in Task 4; 6.5 bots and trace → Task 4, rows 1, 11; roadmap „auto-move = first legal full move“, „an opponent who goes silent between commit and reveal“ → Tasks 3–4; ruling G1 (flip the flag) → Task 2; the stage B note on `view` → Task 1 and Addendum 6.
- **Verified before writing:** a prototype of Task 1's engine changes and of the whole `core/Dice.lua` (about 190 lines) was run in the simulator against the code at `2819a46`, with no other change. From those runs: every `E.stage` vector of Task 1; the six `Fair.dice` vectors and the distribution over 3600 throws; the event sequence and numbers of Task 2 (`seq` 8, dice 6:1 then 4:4, then 4:3 at throw 10 and 1:4 at throw 14); the lapse at exactly ten seconds with dice 4:1 from the opener's seed alone and no leak of that seed before it; the snapshot commit of a guest that was away; the relog after a commit; the new host after 75 s with throw 5 and dice 2:2; the clock moving both seats at 30 and 60 s; the stand after 180 s with `left = 2` (the test allows up to 185); the cascade remainder played by the host's clock at 45 and 90 s; the mother pin (`{2, 0}`, Гюлбара next); a human-on-auto against a bot through three games (168 throws, all `"ok"`), a bot-hosted match and „Нова игра“. Not run (not prototyped): the `"dodge"` and `"mine"` fouls, `Dice.tip`, the model and everything in `ui/`.
- **Decisions the plan makes beyond the spec (the user may contest):**
  1. **The throw is ordered so that nobody reveals knowing the other's seed first: the host commits in the open, the guest commits and reveals blind, the host publishes both.** The spec's „both publish a commit, then both seeds“ is kept in substance. What it cannot cure: the host orders events, so a *modified* host client could peek. That is shown on the guest's client (red), not prevented.
  2. **A silent player is not waited for and the throw is not repeated: after 10 seconds the host throws alone** (amber line, counted per match). A re-throw with a new id, as the roadmap sketched, would hand the silent side a second draw. The cost: a guest in a loading screen has no say in that one throw; the dice are still random.
  3. **No dice value travels at all**; every client derives the dice from the seeds. A bare dice event from a host is applied (the host is authoritative) and flagged `"bad"`.
  4. **Табла has no `E.view`**, so, unlike the card games, the host's clock moves for an idle or offline opponent (the first legal move). Accepted risk: with no `E.view` the forged-move check (Member.lua:155, view-only) does not run, so a modified host may play any legal move for the guest's seat at any moment; the guest sees it on its own board, as in Морски шах (Addendum 6). After three minutes offline he is stood up and loses the match.
  5. „Готово“ is always explicit, also for a roll with no legal move; each number of a Гюлбара cascade is its own „Готово“ with a full clock, and so is a transferred remainder.
  6. Seat 1 always plays the light checkers, seat 2 the dark ones; the board is always drawn from my own side.
  7. After a match the host presses „Нова игра“; the new match starts again with Обикновена and the opening throw (no „loser starts“).
  8. Bots play `E.auto`, the first legal move: a weak opponent, enough to see every rule.
  9. The dice line reuses the fairness line under the felt and opens the „fair“ topic, which gains one paragraph about dice.
  10. The table frame keeps its 560 × 420 size: the board is 404 × 232 with 26 px checkers (check list row 19).
- **Step scan:** every task has tests with exact values, an expected result, an implement step with files, signatures and pinned values, both run commands, and a commit with exact paths. Task 4 says openly that it implements nothing: its tests are the regression pins of Review Focus 3 and 4 and of the timeout, leaving and bot decisions, and passed on the prototype. Task 3 says which two of its tests pass before it.
- **Type and name consistency:** `E.stage(state, seat, steps)` with `pts, pin, bar, off, left, next, done` in Tasks 1, 6 and the contract; `Fair.dice(seeds, rollId)` in Tasks 2–4; action `k = "throw"` with `op` `open`, `commit`, `seed`, `seeds` in Tasks 2–3 and the protocol table; session fields `throw`, `diceMine`, `diceLast` (`h, verdict, why, by, silent, n`), `diceSeen`, `diceAlone`, `diceUnheard` in Tasks 2–4; verdicts `ok`, `alone`, `bad` and reasons `mine`, `commit`, `dodge`, `forged` in Task 3 and the locale of Task 7; `Dice.open`, `Dice.status(s) -> key, tone, arg, arg2`, `Dice.alarm`, `Dice.tip` in Tasks 2, 3, 7; `ns.TablaModel.build(s, staged, pick, names)` with `me, op, seated, var, game, score, mine, reset, points, bar, off, dice, left, rolling, from, pick, to, canUndo, canDone, stuck, text` in Tasks 6–7; widget names `points, bar, tray, dice, stepsLeft, undoButton, doneButton, title, score, text, staged, pick` in Task 7 and its tests; locale prefixes `tabla.` and `dice.`; topic id `tabla`; block kind `dice`.
- **Review Focus:** each of the five has named tests in Tasks 1, 3, 4, 6 and 7.
- **Proportion:** the engine and core changes are given as signatures, rules and pinned values; the throw's hooks are spelled out because the order of who reveals when is the whole point; the model's `text` ladder and the view's geometry are written down because the tests alone do not determine them. D1 (Tasks 1–4) is complete and testable without any UI; D2 adds no protocol and no rule.
