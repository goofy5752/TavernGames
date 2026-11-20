# Tavern Games Stage B (Card Fairness + Сантасе) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Two guild members (or one member and a bot) play Сантасе to 11 game points on a deal nobody can arrange: every player commits a secret seed, the seeds go privately to the hand's dealer, the deck is derived from all of them, each player is whispered only its own cards, and after every hand each client rebuilds the deck from the published seeds, replays the hand and marks it „проверена“ or „нередовна“ in the table frame.

**Architecture:** A table session's `state` becomes an `E.view` of the game for *this* client's seat on every client, the host included; the host still orders every event and runs the clocks, but it validates on a view and never holds a hidden card of another seat. For each hand one seated player is the **dealer** (the deck holder, rotating by seat): only its client knows the deck, and because a view plus the whole deck *is* the full state, it needs to keep nothing but 24 faces. Public steps of the shuffle (open, commit, deal, show, reveal, void) travel in the host's ordered `EV` stream as requests inside `ACT`; the three private steps are new WHISPER types (`SED` seed to the dealer, `PRV` faces to one seat, `PRQ` "send my faces again"). `core/Fair.lua` is the pure part (seed, commit, deck, audit by full replay); `core/Deal.lua` is the session extension `ns.Ext.fair` that runs the round. Engines signal "I need randomness" in one way: a system action carrying `need`. The plan has two halves: **B1** (Tasks 1–6) builds and proves the protocol in the simulator on a tiny test engine; **B2** (Tasks 7–13) plugs Сантасе in and adds cards, the view and the rules-book topics.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), the stage 1 Ace3 subset, `bash t.sh`, `tests/helpers/sim.lua`, `tests/helpers/wow.lua`, Python 3 standard library for `tools/gen_textures.py`.

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (4, 5.3 Сантасе, 5.3а, 6.2, 6.3, 6.5, 8). Roadmap: `docs/superpowers/plans/2026-11-20-games-roadmap.md` (Stage B). Stage A plan (format, contracts, the end state this plan builds on): `docs/superpowers/plans/2026-11-20-stageA-core-deathroll.md`. Engine contract and rulings: `.superpowers/sdd/engines-parallel/contract.md`, `.superpowers/sdd/engines-parallel/progress.md` (X1, G1, S1–S3). Mockup: `docs/mockups/03-games.html` (`santase`, `.pc`).

**Starts after stage A Tasks 6–12 are committed.** Stage A interfaces this plan consumes: `ns.Ext` with `Session:hook` / `Session:filterAct` / `Session:applyUnsent` and the hooks `act`, `applied`, `adopted`, `hostChanged`; `client:startGame()`, `client:playAuto()`, the `"result"` event; `env.random(lo, hi)` on every env including bots; `ns.Games` with the `PLAYABLE` gate; `Sim:add` options kept across `sim:relog`; `Bots` playing `bot:playAuto()` after 1.5 s, `bots:hostTable(game)`, `bots:inviteMe(game)` and the bot host's own start (Task 7); `/tavern bots host|invite <game>` (Task 8); `ns.Util.contains` and the registry-driven hall (Task 9); `TableFrame` with `HallLayout.plates`, `v.startButton`, the banner order and the board at `CENTER 0, -6` for one plate row (Task 10); `Help.topics` ids `hall, ttt, deathroll, soon`, `BLOCKS` in `ui/HelpBook.lua` and the quoted-label test (Task 11).

## Global Constraints

Everything in the stage 1 and stage A constraint files still holds (`.superpowers/sdd/2026-11-20-stage1-platform-tictactoe/global-constraints.md`, `.superpowers/sdd/2026-11-20-stageA-core-deathroll/global-constraints.md`): Lua 5.1 only, no `math.randomseed`, prefix `TAVG`, GUILD + WHISPER only, byte-for-byte names, `core/` and `engines/` without WoW API or globals and with `env.*` read through the table on every call, every string through `ns.L` with identical bg/en key sets, play for fun only (`stake` nil), timeout = automatic move, version `0.1.0`. Added for stage B:

- Protocol stays `v=1`. New message types, all WHISPER-only and point-to-point: `SED`, `PRV`, `PRQ`. New optional field `SNP.fr`. Everything else is a new action shape inside `ACT`/`EV` (table below).
- A card face may travel only: in its owner's own play action; in a seat-0 `deal`/`show` event when the engine's watcher view (`E.view(state, 0)`) shows it; in a `PRV` from the dealer to the seat whose view shows it. Never in `TBL`, `HI`, any GUILD message, or an `SNP`/`EV` to somebody whose view lacks it.
- Seed = `SEED_BYTES = 16` values of `env.random(0, 255)` as 32 lowercase hex characters. Commit = `ns.Sha256.hex(seed)` (64 hex characters, the hash of the seed *text*). Hand id = `tid .. "/" .. h`. Deck: `p = ns.Deck.permutation(ns.Deck.key(seeds, handId), #E.DECK)` with `seeds` in ascending seat order, `deck[i] = E.DECK[p[i]]`.
- Dealer of the hand: with `p` = the occupied seats ascending and `n` = hands already dealt in this match, seat `p[(n + 1) % #p + 1]` (two players: seat 2, 1, 2, …). The dealer is a fairness role only; who leads stays the engine's business.
- Timing: `FAIR_WAIT = 20` (an undealt round is reopened; an unrevealed hand is given up), `FAIR_ASK_GAP = 5` (missing faces are asked for again).
- Verdicts: `"ok"` („проверена“), `"bad"` („нередовна“), `"unseen"` (I did not see the whole hand), `"void"` (annulled, dealt again). Reasons of `"bad"`, in check order: `seeds`, `commit`, `deal`, `dealt`, `play`, plus `noreveal`.
- Seeds, decks and private faces live in memory only: never in SavedVariables, never printed. `/tavern debug` shows only what this client sent or received.
- Bots are full clients of the protocol. No `SED`/`PRV`/`PRQ` and no message of a bot table ever reaches a real channel (the stage 1 bot invariant, unchanged code path).
- Santase rules are the rule table at the top of `engines/santase.lua`; stage B changes no rule (it adds the `void` action, the `need` marker and a guard).
- `core/Session.lua` stays below 540 lines, `ui/Hall.lua` below 580; new code goes into new files.
- Cards: 40×58 px, fan step 28 px, raised by 8 px, dimmed to 0.55. Textures `card` 64×128, `card_back` 64×128, `suits` 128×32 (♣ ♦ ♥ ♠ left to right, white, tinted in code), generated by `tools/gen_textures.py` (standard library only).
- Commits are local only, never pushed; every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A hidden face reaches somebody who may not see it** (an `SNP` cut for the wrong seat, an `EV`, a `PRV` to the wrong player, the dealer's own table state). Pinned by Task 2 (`a snapshot is cut to the recipient's view`) and Task 4 (`no message to the opponent or a watcher carries a face it may not see`, `the dealer's table state is still only its own view`).
2. **A player reconnects in the middle of a hand** and has lost its cards. Pinned by Task 6 (`a relogged player gets its hand again from the dealer`).
3. **The dealer leaves or reloads mid-hand**, taking the deck with it. Pinned by Task 6 (`the dealer relogs mid-hand: void, the same dealer deals again`, `the dealer stands mid-hand: void, the next player deals`).
4. **A dealer that deals from another deck** than the seeds give. Pinned by Task 5 (`a modified deck is flagged нередовна by everyone`).
5. **A player goes silent during the shuffle** (never commits, or its seed never arrives). Pinned by Task 6 (`a player who never commits: the round is reopened every 20 s`, `a seed that never arrives: the round is reopened`).

Also pinned: a move only the full deck can judge (Task 5), a reveal before the hand is over and requests from a non-dealer (Task 6), a host change mid-hand (Task 6), the host's clock playing a hand it cannot see (Task 2), a system action with `need` reaching `E.apply` (Task 1).

---

## File Structure

```
engines/santase.lua  belot.lua  holdem.lua  tabla.lua   need marker (Task 1); santase: ext, void, again, nextFirst, guard (Task 7)
core/Const.lua             + FAIR_WAIT, FAIR_ASK_GAP, SEED_BYTES
core/Session.lua           need -> hook, `table` hook, SNP per recipient + fr, new WHISPER types and timers (stays < 540)
core/Member.lua            adopted(s, prev, m); own-turn clock calls
core/Lifecycle.lua         a new game as a view, snapshotFor, armAuto, gameOver, startable, E.again
core/Fair.lua              NEW ns.Fair (pure): seed, commit, handId, deck, full, audit
core/Deal.lua              NEW ns.Deal + ns.Ext.fair: round, SED/PRV/PRQ, reveal, verdicts, void, status
core/Games.lua             PLAYABLE.santase
core/Bots.lua              a bot host starts whatever Session.startable allows
core/Help.lua              topics "santase", "fair"; block kind "cards"
tools/gen_textures.py      + card, card_back, suits
ui/Theme.lua               + texSize entries
ui/Cards.lua               NEW ns.Cards: card widget, fan
ui/TableFrame.lua          fairness line, „Нова игра“ for E.again
ui/games/SantaseView.lua   NEW
ui/HelpBook.lua            + BLOCKS.cards
locale/bg.lua  locale/en.lua
tests/helpers/hicard_engine.lua   NEW test engine "hicard"
tests/core/{private,fair,deal,deal_audit,deal_fail,santase_table}_test.lua  NEW
tests/ui/{theme,cards,santase}_test.lua  NEW
docs/superpowers/notes/2026-11-stageB-ingame-checks.md  NEW
```

TOC: `core/Fair.lua` after `core/Deck.lua`; `core/Deal.lua` after `core/Lifecycle.lua`; `ui/Cards.lua` after `ui/Widgets.lua`; `ui/games/SantaseView.lua` after `ui/games/DeathRollView.lua`.

### Shared contracts (additions to stage 1 and stage A)

**Randomness (ruling X1), all engines.** `E.system(state)` returns an action carrying `need` when the table must supply randomness: `need = "deck"` (payload `deck`, always on the action `{k="deal"}`) or `need = "dice"` (payload `d = {a, b}`, on `{k="dice"}`). The session never applies such an action: after its delay it calls the extensions' `need(s, action)`. Whoever supplies the payload applies the same action without `need`. `E.apply` refuses an action that still has `need` with `"need"`.

**Engines that list the extension `fair`** (card games) also provide:

| item | meaning |
|---|---|
| `E.DECK`, `E.view`, `E.hidden`, `{k="show"}` | as in `.superpowers/sdd/engines-parallel/contract.md` |
| view ⊕ deck | `E.view` changes nothing but `deck` and sets `full = false`; a copy of any view with the whole deck and `full = true` behaves as the full state (`Fair.full`) |
| `{k="deal"}` on a view | accepts no deck or any subset; on a state with `full == true` only a complete permutation of `E.DECK` |
| `{k="void"}` at seat 0 | while a hand runs: annul it, nothing scores, back to the phase in which `E.system` asks for the deal; otherwise `"phase"` |
| `E.auto`/`E.legal` | return nothing for a hand whose faces are unknown |
| `E.again` | `true`: once the match is over the host may start a new one with `client:startGame()` |

**`ns.Ext` hooks added:** `need(s, action)` (host), `table(s, a) -> true|nil` (everyone: a seat-0 event the extension owns; `true` = applied, the engine is not asked), `snap(s) -> table|nil` (host: goes out as `SNP.fr`). `adopted` gets the snapshot message as a third argument.

**Protocol additions** (`v=1`):

| where | shape | meaning |
|---|---|---|
| `EV` seat 0 | `{k="fair", op="open", h, d, p}` | the host opens shuffle round `h` (its `seq + 1`), dealer seat `d`, participants `p` |
| `ACT` → `EV` seat 0 | `{k="fair", op="commit", h, c}` → `{…, seat, c}` | a participant's commit |
| `SED` (player → dealer) | `{tid, h, s}` | my seed, once every commit is in |
| `ACT` (dealer) → `EV` seat 0 | `{k="fair", op="deal", h, deck={[i]=face}}` → `{k="deal", deck={[i]=face}}` | dealt; `deck` holds only the faces a watcher sees |
| `PRV` (dealer → player) | `{tid, h, cards={[i]=face}}` | faces only that seat sees: its deal, its draws, the answer to `PRQ` |
| `PRQ` (player → dealer) | `{tid, h}` | send me all my faces again |
| `ACT` (dealer) → `EV` seat 0 | `{k="fair", op="show", h, cards}` → `{k="show", cards}` | faces that became public outside a play |
| `ACT` (dealer) → `EV` seat 0 | `{k="fair", op="reveal", h, s={seed,…}}` → the same as an event | the seeds in `p` order, after the hand |
| `ACT` (dealer) → `EV` seat 0 | `{k="fair", op="void", h}` → `{k="void"}` | the dealer lost the deck |
| `SNP` | `fr = {h, d, p, c, st, n}` | the round: commits `c` by seat, stage `st`, hands dealt `n`; absent when no round |

**Client event added:** `"fair"({tid, game, h, verdict, why, dealer, at})`, once per closed hand on every client at the table.

**Test conventions:** as in stage A (`bash t.sh [file]`, success ends `N passed, 0 failed`; a `--[[ … ]]` body states assertions in words to be written out with exactly those values). Names `A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"`, clients `a, b, c, d`. `SEED = ("ff"):rep(16)` is what the sim's `env.random` yields (it returns `hi`).

---

# Part B1 — the protocol, proven on a test engine

### Task 1: One "randomness needed" convention in the four engines

**Files:**
- Modify: `engines/santase.lua`, `engines/belot.lua`, `engines/holdem.lua`, `engines/tabla.lua`, `tests/engines/santase_test.lua`, `tests/engines/belot_test.lua`, `tests/engines/holdem_test.lua`, `tests/engines/tabla_test.lua`

**Interfaces:**
- Produces (the X1 contract above):
  - santase: `E.system` → `{k="deal", need="deck"}` with delay `0` (phase `"deal"`) or `3` (phase `"hand"`); a `deal` without `deck` on a state with `full == false` is a deal with an empty deck.
  - belot: `E.system` → `{k="deal", need="deck"}` (delays unchanged); `{k="score"}` unchanged.
  - holdem: in phase `"deal"` `E.system` → `{k="deal", need="deck"}, 0` (was nil); `{k="hand"}`, `street`, `showdown` unchanged.
  - tabla: `E.system` → `{k="dice", need="dice", r="open"}` / `{k="dice", need="dice", r="roll", s=seat}` (replaces `{k="need", …}`); `{k="dice", d}` unchanged.
  - all four: `E.apply(state, seat, a)` returns `nil, "need"` when `a.need ~= nil`, before any other check.
  - Each file's header comment states the convention in one line (replacing the old wording: santase „E.system returns {k="deal"} …“, holdem „HAND HANDSHAKE“ phase `"deal"` line, tabla rule 4, belot's `E.system` comment).

- [ ] **Step 1: Write the failing tests** (one new `it` per engine file, and the existing expectations changed).

```lua
-- santase_test.lua
it("asks for a deck with a need marker and refuses a marked action", function()
  local s = E.new{first = 1}; eq({ E.system(s) }, { { k = "deal", need = "deck" }, 0 })
  eq({ E.apply(s, 0, { k = "deal", need = "deck", deck = deckOf(STD) }) }, { nil, "need" })
  eq({ E.apply(s, 0, { k = "deal" }) }, { nil, "deck" })               -- a full state wants the whole deck
  local v = E.view(s, 1); ok(E.apply(v, 0, { k = "deal" })); eq(v.deck, {}); eq(#v.hands[1], 6)
end)
-- belot_test.lua
it("asks for a deck with a need marker", function()
  local s = E.new{}; eq({ E.system(s) }, { { k = "deal", need = "deck" }, 0 })
  eq({ E.apply(s, 0, { k = "deal", need = "deck", deck = DECK1 }) }, { nil, "need" })
end)
-- holdem_test.lua
it("after the hand action the table asks for a deck", function()
  local s = mk({ 1, 2 }); ok(E.apply(s, 0, { k = "hand" })); eq({ E.system(s) }, { { k = "deal", need = "deck" }, 0 })
  eq({ E.apply(s, 0, { k = "deal", need = "deck" }) }, { nil, "need" })
end)
-- tabla_test.lua
it("asks for dice with a need marker", function()
  local s = E.new{}; eq({ E.system(s) }, { { k = "dice", need = "dice", r = "open" }, 0 })
  eq({ E.apply(s, 0, { k = "dice", need = "dice", d = { 3, 5 } }) }, { nil, "need" })
  ok(E.apply(s, 0, { k = "dice", d = { 3, 5 } }))
  --[[ now phase "roll" for the seat that rolled 5: E.system(s) == {k="dice", need="dice", r="roll", s=2}, 0 ]]
end)
```

Existing expectations to change with them: `santase_test.lua` lines 84, 186, 599 (`{k="deal"}` → `{k="deal", need="deck"}`); `belot_test.lua` lines 130, 226, 497 and the two loops that feed `E.system` back (around 796 and 829: a returned action with `need` gets its deck and loses `need`); `holdem_test.lua` lines 139 and 363 (`E.system(s)` in phase `"deal"` is no longer nil) and the helper at line 52 if it meets the marked action; `tabla_test.lua` lines 59, 66 and the loop at 339 (`{k="need", …}` becomes `{k="dice", need="dice", …}`; line 84, an unknown `k`, stays `"action"`).

- [ ] **Step 2: Run `bash t.sh tests/engines`.** Expected: the four new tests FAIL (`need` missing from the system action; `"need"` not returned).
- [ ] **Step 3: Implement** the four edits and the header lines. No rule and no other behaviour changes.
- [ ] **Step 4: Run `bash t.sh tests/engines`, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add engines/santase.lua engines/belot.lua engines/holdem.lua engines/tabla.lua tests/engines/santase_test.lua tests/engines/belot_test.lua tests/engines/holdem_test.lua tests/engines/tabla_test.lua` — `refactor(engines): one need marker for system actions that want randomness`

### Task 2: The session works on views

**Files:**
- Create: `tests/helpers/hicard_engine.lua`; Modify: `core/Session.lua`, `core/Member.lua`, `core/Lifecycle.lua`, `core/Util.lua`; Test: `tests/core/private_test.lua`

**Interfaces:**
- Consumes: stage A `Session:hook`, `Session.playAuto`, `ns.Util.contains` (stage A Task 9; if it lives elsewhere, define it in `core/Util.lua` and alias the other).
- Produces:
  - `Session:newGame(first)` returns `engine.view(state, self.mySeat or 0)` when the engine has `view`. So `session.state` is a view on every client.
  - `Session:snapshotFor(name) -> table|nil` (`core/Lifecycle.lua`): nil without a state; with `engine.view`: `engine.snapshot(engine.view(self.state, seatOf(self.seats, name) or 0))`; else `engine.snapshot(self.state)`. `Session:snapshotTo` sends `st = self:snapshotFor(name)` and `fr = self:hook("snap")`.
  - `Session:armTimers`: a system action with `need` is handed to `self:hook("need", action)` when its delay ends, never to `play`. The turn timer plays `engine.auto` only when the engine has no `view` or the seat on turn is the host's own.
  - `Session:apply`: a seat-0 event for which `self:hook("table", a)` returns true is applied by the extension; the engine is not asked.
  - `Session:armAuto()` (`core/Lifecycle.lua`), called by `Member` after every applied `EV` and after `Member.adopt`: cancels `self.autoTimer`; for a seated member of a live game whose engine has `view`, on its own turn with a `deadline`, arms `autoTimer` for `deadline - now`; on expiry, when it is still the same session at the same `seq`, calls `Session.playAuto(client)`.
  - `Session:gameOver() -> bool` (`core/Lifecycle.lua`): the file-local `over(engine, state)` of stage A exported; false without a state.
  - `Member.adopt` calls `s:hook("adopted", prevState, m)`.
  - `core/Session.lua`: `TIMERS` gains `"fairTimer", "askTimer", "autoTimer"`; `WHISPERED` gains `SED`, `PRV`, `PRQ`; the file-local `contains` is deleted in favour of `ns.Util.contains`. The file must end below 540 lines.
  - `tests/helpers/hicard_engine.lua` registers `Sim.ns.Engines.hicard` (returns it): `id="hicard", minSeats=2, maxSeats=3, start="host", ext={"fair"}, GOAL=4`, `DECK = {"9C","TC","JC","QC","KC","AC","9D","TD","JD","QD","KD","AD"}` (rank order 9 < T < J < Q < K < A).
    - State: `full` (true from `E.new`), `phase` (`"deal"`, `"play"`, `"hand"`, `"match"`), `players` (occupied seats ascending), `dealer`, `turn`, `deck`, `hands[seat]` (deck indices), `up` (index), `stock`, `trick` (array of `{seat, i}`), `last` (indices), `tricks`, `pts` (one entry per table seat, 0 at the start), `pts0` (copy of `pts` at the deal), `hand`, `winner`. `E.new`: `dealer` = the player before `opts.first` (cyclic), phase `"deal"`.
    - `{k="deal", deck}` at seat 0 in phase `"deal"`/`"hand"`: with `n = #players`, in player order starting after the dealer, `deck[1..n]` one card each, then `deck[n+1..2n]`; `up = 2n+1`; `stock = {2n+2, …, 12}`; the player after the dealer is on turn; `hand = hand + 1`; `tricks = 0`. Deck rules as in the contract table (`"deck"`).
    - `{k="play", i, c}` by the seat on turn: `i` in its hand and the face rule of the engine contract (`"card"`). Rule H: when every face of that hand is known and it holds a card of the `up` card's suit, `c` must be of that suit (`"move"`). When every player has played: the highest rank wins (ties: the earlier card), `pts[winner] + 1`, `last` = the trick, `tricks + 1`. After trick 1 every player draws one card from the top of the stock, the winner first, then in player order; the winner leads. `pts[winner] == GOAL` → phase `"match"`, `winner`. After trick 3 otherwise: phase `"hand"`, `turn = nil`, `dealer` = the next player.
    - `{k="show", cards}` as in the contract. `{k="void"}`: phase `"play"` only; back to phase `"deal"` with `hands`, `stock`, `trick`, `last`, `deck` emptied, `up`/`turn` nil, `pts = pts0`, `hand - 1`.
    - `E.system`: phase `"deal"` → `{k="deal", need="deck"}, 0`; phase `"hand"` → the same with delay `1`; else nil. `need` on an applied action → `"need"`.
    - `E.leave(state, seat)` (specified for a trick boundary only; tests use it only there): the seat leaves `players` and its hand is dropped; fewer than two players → phase `"match"`, `winner` = the one left; if it was the dealer the next player is; if it was on turn the next player is.
    - `E.view(state, seat)`: a copy with `full = false` whose `deck` keeps the seat's own hand, the trick, `last` and `up`; everything in phase `"match"`. `E.hidden(state, seat)` = its hand. `E.legal`/`E.auto(state, seat)`: for the seat on turn, the known cards of its hand that rule H allows (rule H only when every face is known), `auto` = the first in hand order; nil/`{}` otherwise. `E.result`/`E.over` in phase `"match"`; `snapshot`/`restore` deep copies.

- [ ] **Step 1: Write the failing tests** (`tests/core/private_test.lua`). `table2()` = a sim with `a` hosting `hicard` (`access="guild"`, `turn=45`), `b` on seat 2, `d` added but not at the table, `a:startGame()`, `sim:run(1)`; returns `sim, tid`. `H = require("hicard_engine")`. `ns.Ext.fair` does not exist yet, so nothing deals by itself; each test that sets `ns.Ext.fair` sets it back to nil at its end.

```lua
it("the test engine keeps the contract: view plus deck is the full state", function()
  local s = H.new{ first = 1, seats = { true, true } }; ok(H.apply(s, 0, { k = "deal", deck = H.DECK }))
  eq(s.hands, { { 1, 3 }, { 2, 4 } }); eq(s.up, 5); eq(s.turn, 1); eq(s.stock, { 6, 7, 8, 9, 10, 11, 12 })
  eq(H.view(s, 1).deck, { [1] = "9C", [3] = "JC", [5] = "KC" }); eq(H.view(s, 0).deck, { [5] = "KC" })
  for q = 0, 2 do local v = H.view(s, q); v.deck, v.full = ns.Util.copy(s.deck), true; eq(v, s) end
  local v = H.view(s, 2); ok(H.apply(v, 1, { k = "play", i = 1, c = "9C" })); eq(v.deck[1], "9C")
  eq({ H.apply(s, 0, { k = "deal", need = "deck" }) }, { nil, "need" }); eq(H.auto(H.view(s, 2), 1), nil)
  ok(H.apply(s, 0, { k = "void" })); eq(s.phase, "deal"); eq(s.hand, 0); eq({ H.system(s) }, { { k = "deal", need = "deck" }, 0 })
end)
it("a new game is a view and the need action is offered to the extensions, never played", function()
  local got = {}; ns.Ext.fair = { need = function(s, a) got[#got + 1] = a end }
  local sim = table2(); eq(a.session.state.full, false); eq(b.session.state.full, false)
  local q = a.session.seq; sim:run(5); eq(got, { { k = "deal", need = "deck" } }); eq(a.session.seq, q); eq(a.session.state.phase, "deal")
end)
it("a seat-0 event claimed by the table hook does not reach the engine", function()
  ns.Ext.fair = { table = function(s, a) if a.k == "fair" then s.claimed = (s.claimed or 0) + 1; return true end end }
  local sim = table2(); local q = a.session.seq
  a.session:play(0, { k = "fair", op = "x" }); sim:run(1); eq(a.session.claimed, 1); eq(b.session.claimed, 1); eq(b.session.seq, q + 1)
  a.session:play(0, { k = "nope" }); sim:run(1); eq(a.session.seq, q + 1)
end)
it("a snapshot is cut to the recipient's view", function()
  local sim, tid = table2(); a.session:play(0, { k = "deal", deck = H.DECK }); sim:run(1)   -- test shortcut: everybody knows all
  local b2 = sim:relog(B); d:watch(tid); sim:run(2)
  eq(b2.session.state.deck, { [2] = "TC", [4] = "QC", [5] = "KC" }); eq(d.session.state.deck, { [5] = "KC" })
  --[[ the last SNP sent to B: msg.st.deck == {[2]="TC",[4]="QC",[5]="KC"}, msg.st.full == false; the one to D: {[5]="KC"} ]]
end)
it("the host's clock cannot play a hand it does not see; the player's own client does", function()
  local sim = table2(); a.session:play(0, { k = "deal", deck = { [5] = "KC" } }); sim:run(1)
  a.session.state.deck[1], a.session.state.deck[3] = "9C", "JC"; b.session.state.deck[2], b.session.state.deck[4] = "TC", "QC"
  ok(a:act{ k = "play", i = 1, c = "9C" }); sim:run(44); eq(#a.session.state.trick, 1)
  sim:run(2); eq(a.session.state.tricks, 1); eq(a.session.state.last, { 1, 2 })       -- b's client played {i=2, c="TC"} at its deadline
  --[[ and the host's own turn still times out through its turn timer: sim:run(46) plays a's first known card ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/private_test.lua`.** Expected: FAIL (`hicard_engine` missing; then `full` is true, no `need` hook call).
- [ ] **Step 3: Implement.** Check `wc -l core/Session.lua` is below 540.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `5 passed, 0 failed`; all pass (Морски шах and Death Roll have no `view`: their behaviour is unchanged).
- [ ] **Step 5: Commit.** `git add tests/helpers/hicard_engine.lua core/Session.lua core/Member.lua core/Lifecycle.lua core/Util.lua tests/core/private_test.lua` — `feat(core): sessions hold a view of the game; snapshots per recipient; need and table hooks`

### Task 3: Fair — seeds, commits, deck, audit (pure)

**Files:**
- Create: `core/Fair.lua`; Modify: `core/Const.lua`, `TavernGames.toc`; Test: `tests/core/fair_test.lua`

**Interfaces:**
- Consumes: `ns.Sha256.hex`, `ns.Deck.key`, `ns.Deck.permutation` (called through `ns.Deck` at call time, never cached: a test replaces it).
- Produces `ns.Fair` (no session, no env):
  - `Fair.seed(random) -> string` — 16 × `random(0, 255)` as `%02x`.
  - `Fair.commit(seed) -> string` = `ns.Sha256.hex(seed)`. `Fair.handId(tid, h) -> string` = `tid .. "/" .. h`.
  - `Fair.deck(DECK, seeds, handId) -> {face, …}` (the Global Constraints formula).
  - `Fair.full(view, deck) -> state` — a deep copy of `view` with `deck` = a copy of `deck` and `full = true`.
  - `Fair.audit(engine, rec) -> "ok" | "bad", why` with `rec = {tid, h, p, commits, seeds, base, log, priv}` (`seeds` in `p` order, `commits` by seat, `base` = the engine snapshot when the round opened, `log` = array of `{seat, a}` since then, `priv` = faces I was shown privately). Checks in this order, first failure wins:
    1. `"seeds"`: `#seeds ~= #p` or a non-string.
    2. `"commit"`: `Fair.commit(seeds[k]) ~= commits[p[k]]` for some `k`.
    3. `"deal"`: the log has no seat-0 `deal`, or a face in its `deck` differs from `deck[i]`.
    4. `"dealt"`: some `priv[i] ~= deck[i]`.
    5. `"play"`: replay on `Fair.full(engine.restore(base), base.deck)`: a seat-0 `sit` is skipped, `stand` calls `engine.leave(state, a.seat)`, `deal` is applied as `{k="deal", deck=deck}`, everything else through `engine.apply(state, seat, a)`; any refusal fails.
  - `Const.FAIR_WAIT = 20`, `Const.FAIR_ASK_GAP = 5`, `Const.SEED_BYTES = 16`.

- [ ] **Step 1: Write the failing tests.**

```lua
local F, H, S = ns.Fair, require("hicard_engine"), ns.Engines.santase
local SEED, ZERO = ("ff"):rep(16), ("00"):rep(16)
it("a seed is 16 random bytes in hex and the commit is its SHA-256", function()
  local calls = 0; eq(F.seed(function(lo, hi) calls = calls + 1; eq({ lo, hi }, { 0, 255 }); return 255 end), SEED); eq(calls, 16)
  eq(F.seed(function() return 0 end), ZERO); eq(F.seed(function() return 10 end), ("0a"):rep(16))
  eq(F.commit(SEED), "352302489bc2fcf025cf00cda8308033f97ac87712ce90b4d7cd72c58e4c3af9")
  eq(F.commit("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"); eq(F.handId("Иван Петров#17", 7), "Иван Петров#17/7")
end)
it("the deck is the engine's deck in the order the seeds and the hand id give", function()
  eq(table.concat(F.deck(S.DECK, { ZERO, SEED }, "t/1"), " "),
    "QC TH 9S QD JC KS KD JD QS KH TD JH QH KC AH AC 9C AD 9H TC 9D TS AS JS")
  eq(table.concat(F.deck(H.DECK, { SEED, SEED }, "t/1"), " "), "9C AC QC QD JC TC AD JD 9D KD KC TD")
  eq(table.concat(F.deck(H.DECK, { SEED, SEED }, "t/2"), " "), "TD KD TC QD QC 9C AC JD JC KC AD 9D")
  ok(table.concat(F.deck(H.DECK, { SEED, ZERO }, "t/1"), " ") ~= table.concat(F.deck(H.DECK, { ZERO, SEED }, "t/1"), " "))
end)
it("full turns a view into the full state without touching the view", function()
  local s = H.new{ first = 1, seats = { true, true } }; ok(H.apply(s, 0, { k = "deal", deck = H.DECK }))
  local v = H.view(s, 2); eq(F.full(v, s.deck), s); eq(v.full, false); eq(v.deck[1], nil)
end)
-- rec(): base = H.snapshot(H.view(H.new{first=1, seats={true,true}}, 0)); seeds {SEED, SEED}; p {1, 2}; commits by F.commit;
-- deck = F.deck(H.DECK, seeds, "t/1") = 9C AC QC QD JC TC …: seat 1 holds 9C, QC; seat 2 AC, QD; up JC (clubs).
-- log = { {0, {k="deal", deck={[5]="JC"}}}, {1, {k="play", i=1, c="9C"}}, {2, {k="play", i=2, c="AC"}} }; tid "t", h 1; priv {[1]="9C",[3]="QC"}
it("an honest hand is ok; each kind of fault is named", function()
  eq({ F.audit(H, rec()) }, { "ok" })
  local r = rec(); r.seeds = { SEED }; eq({ F.audit(H, r) }, { "bad", "seeds" })
  r = rec(); r.seeds[2] = ZERO; eq({ F.audit(H, r) }, { "bad", "commit" })
  r = rec(); r.log[1][2].deck[5] = "KC"; eq({ F.audit(H, r) }, { "bad", "deal" })
  r = rec(); table.remove(r.log, 1); eq({ F.audit(H, r) }, { "bad", "deal" })
  r = rec(); r.priv[1] = "TC"; eq({ F.audit(H, r) }, { "bad", "dealt" })
  r = rec(); r.log[2][2].c = "TC"; eq({ F.audit(H, r) }, { "bad", "play" })                         -- a card he did not hold
  r = rec(); r.log[3] = { 2, { k = "play", i = 4, c = "QD" } }; eq({ F.audit(H, r) }, { "bad", "play" })   -- held a club, played a diamond
  r = rec(); r.log[4] = { 0, { k = "stand", seat = 2, why = "left" } }; eq({ F.audit(H, r) }, { "ok" })
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/fair_test.lua`.** Expected: FAIL (`Fair` is nil).
- [ ] **Step 3: Implement** `core/Fair.lua`, the three constants, the TOC line after `core/Deck.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `4 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Fair.lua core/Const.lua TavernGames.toc tests/core/fair_test.lua` — `feat(core): seeds, commits, deck from seeds and the hand audit`

### Task 4: Deal — the shuffle round and the private deal

**Files:**
- Create: `core/Deal.lua`; Modify: `TavernGames.toc`; Test: `tests/core/deal_test.lua`

**Interfaces:**
- Consumes: Task 2 hooks and `Session:gameOver`, Task 3 `ns.Fair`, `ns.Member.handlers`, `ns.Session.message`, `client:after`, `env.random`.
- Produces `ns.Deal` and `ns.Ext.fair = {need, table, act, applied, adopted, snap}`; `ns.Member.handlers.SED/PRV/PRQ` (each `fn(client, sender, m)`).
  - Session fields (local; only `snap` leaves the client): `s.fair` = the round `{h, d, p, dealer (name), commits, stage ("commit"|"seed"|"dealt"|"done"), seed, seedSent, seeds, deck, dealing, sent, pub, priv, lied, base, log}`; `s.fairN` = hands dealt in this match.
  - `Deal.open(s)` (host), `Deal.submit(s, a)` (a request to the host: handled at once when I host, else whispered as `ACT{tid, a}`), `Deal.react(s)` (whatever my role owes the round now; idempotent), `Deal.learn(s, cards)`, `Deal.sync(s)` (dealer), `Deal.missing(s) -> bool` (a deck index of `engine.hidden(state, mySeat)` whose face I do not know).
- Rules:
  1. **Need** (host, `need` hook, `action.need == "deck"`): calls `Deal.open(s)` unless a round in stage `"commit"`/`"seed"` is running with `s.fairTimer` armed (Task 5 adds one more case; the timer itself is Task 6's).
  2. **Open** (host): `s:play(0, {k="fair", op="open", h = s.seq + 1, d = p[(n + 1) % #p + 1], p = <occupied seats ascending>})` with `n = s.fairN or 0`.
  3. **`table` hook** (everyone; status `"live"`; it only changes `s.fair`, it never sends). `open`: valid when `h` is an integer, `#p >= 2`, every `p[k]` is an occupied seat and `d == p[(n + 1) % #p + 1]`; then `s.fair = {h, d, p, dealer = seats[d], commits = {}, stage = "commit", priv = {}, base = engine.snapshot(s.state), log = {}}`. `commit`: valid when `h == fair.h`, stage `"commit"`, `seat` is in `p` without a commit and `c` is a 64-character string; stored; when every participant has one the stage is `"seed"`. Anything else returns nil (the event is refused).
  4. **`act` hook** (host): an action with `k == "fair"` never reaches the engine (the hook returns nil). `commit` from a participant passing rule 3's checks → `s:play(0, {k="fair", op="commit", h, seat, c})`. `deal` from seat `d` with the right `h` in stage `"seed"` and a table `deck` → `s:play(0, {k="deal", deck = a.deck})`. `show` from seat `d` in stage `"dealt"` with a table `cards` → `s:play(0, {k="show", cards = a.cards})`. Everything else is dropped.
  5. **`applied` hook** (everyone, after every event): seat-0 `start` or `abort` → `s.fair = nil`, `s.fairN = 0`. Otherwise, with a round: every event that is not `k == "fair"` is appended to `fair.log` as `{seat, copy(a)}` (when the round has a log); a seat-0 `deal` in stage `"seed"` → stage `"dealt"`, `s.fairN + 1`; then `Deal.react(s)`. All sending happens here or in `adopted`, never inside `table` (an event sent from inside `apply` would overtake the one being applied).
  6. **`react`** by stage. `"commit"`: a participant with neither a seed nor a commit makes `seed = Fair.seed(env.random)` and submits `{k="fair", op="commit", h, c = Fair.commit(seed)}`. `"seed"`: a participant holding its seed — the dealer keeps `seeds[mySeat] = seed`; the others whisper `SED{tid, h, s = seed}` to `fair.dealer` once (`seedSent`). `"dealt"`: `Deal.learn(s, {})` (applies what I was already told); the dealer with a deck calls `Deal.sync(s)`.
  7. **`SED`** (dealer): taken when I am seat `d` of round `m.h` in stage `"seed"`, the sender is a participant and `Fair.commit(m.s) == commits[seat]`. With every participant's seed and not yet `dealing`: `deck = Fair.deck(engine.DECK, <seeds in p order>, Fair.handId(tid, h))`; a trial `full = Fair.full(s.state, s.state.deck)` gets `{k="deal", deck=deck}`; `pub = engine.view(full, 0).deck`; `fair.deck, fair.pub, fair.sent, fair.dealing = deck, pub, {}, true`; submit `{k="fair", op="deal", h, deck = pub}`.
  8. **`sync`** (dealer, stage `"dealt"`): `full = Fair.full(s.state, fair.deck)`; `known = engine.view(s.state, 0).deck` (what the event stream already made public). First the faces of `engine.view(full, 0).deck` in neither `known` nor `fair.pub`: one submit `{k="fair", op="show", h, cards}`, marked in `fair.pub`. Then for every participant seat `q` still occupied: the faces of `engine.view(full, q).deck` that are in none of `known`, `fair.pub`, `sent[q]` — for my own seat `Deal.learn(s, them)`, for another seat one `PRV{tid, h, cards}` to its name; marked in `sent[q]`.
  9. **`PRV`**: taken from `fair.dealer` for round `m.h == fair.h` with a table `cards` → `Deal.learn(s, m.cards)`. `learn` merges into `fair.priv`; in stage `"dealt"` with a non-empty `priv` it tries `{k="show", cards = priv}` at seat 0 on a copy of `s.state`: accepted → that copy is the state and `"session"` is emitted; refused → `fair.lied = true`.
  10. **`snap`** (host): `{h, d, p, c = commits, st = stage, n = s.fairN or 0}` or nil. (`adopted` and `PRQ` come in Task 6.)
  11. Every timer and handler first checks that `client.session` is the same session and `s.fair` the same round.

- [ ] **Step 1: Write the failing tests** (`tests/core/deal_test.lua`). Helpers: `table2()` = `a` hosts `hicard`, `b` on seat 2, `d` added, not started; `table3()` adds `c` on seat 3; `start()` = `a:startGame(); sim:run(1)`; `auto(n)` = `n` times: the client whose seat is on turn (looked up in `sim.clients` by the seat's name, so a relogged client is used) calls `playAuto()`, then `sim:run(1)`; `faces(v)` = every string anywhere in `v` matching `^[9TJQKA][CDHS]$`; `sentOf(t)` = the entries of `sim.sent` with `msg.t == t`. With two players the dealer of hand 1 is seat 2 (`b`, not the host), of hand 2 seat 1.

```lua
it("a hand is dealt from everyone's seeds and each client knows only its own cards", function()
  local sim, tid = table2(); d:watch(tid); sim:run(1); start()
  local r = a.session.fair; eq({ r.d, r.p, r.stage, r.dealer }, { 2, { 1, 2 }, "dealt", B }); eq(a.session.fairN, 1)
  local deck = b.session.fair.deck; eq(deck, ns.Fair.deck(H.DECK, { SEED, SEED }, tid .. "/" .. r.h)); eq(a.session.fair.deck, nil)
  eq(a.session.state.deck, { [1] = deck[1], [3] = deck[3], [5] = deck[5] }); eq(d.session.state.deck, { [5] = deck[5] })
  eq(b.session.state.deck, { [2] = deck[2], [4] = deck[4], [5] = deck[5] })      -- the dealer's table state is still only its own view
  eq(a.session.state.turn, 1); eq(a.session.state.phase, "play")
end)
it("commits come before any seed, and a seed goes only to the dealer", function()
  --[[ after start(): the EVs from A in order are open, commit, commit, deal (the open first); both commit events carry
  c == ns.Fair.commit(SEED) and seats 1 and 2; sentOf("SED") == exactly one entry: from A, channel "WHISPER", target B, msg.s == SEED,
  and its index in sim.sent is greater than the index of the last commit EV; no message on GUILD has t SED/PRV or a field named s/c/deck ]]
end)
it("no message to the opponent or a watcher carries a face it may not see", function()
  --[[ table2(), d watches after start() (so its SNP is mid-hand). deck = b.session.fair.deck; held[1], held[2] = sets of deck indices.
  After start() and after each of 5 auto(1) steps (the deal, the first trick with its draws, and on into the third trick; the hand is not over):
    held[q] gains every index in ns.Fair.full(b.session.state, deck).hands[q];
    public = {deck[5]} plus the face of every index in b.session.state.trick and .last so far (accumulated);
    for every new entry m of sim.sent: on GUILD faces(m.msg) == {}; to D every face is in public;
    to A (seat 1) / to B (seat 2) every face is in public or is deck[i] for an i in held[seat].
  At the end ok(#sentOf("PRV") >= 2) (the deal and the draw), every PRV is from B to A. ]]
end)
it("a drawn card reaches only the player who drew it", function()
  local sim = table2(); start(); auto(2)                                   -- trick 1 done, both drew
  local deck, st = b.session.fair.deck, ns.Fair.full(b.session.state, b.session.fair.deck)
  for _, i in ipairs(st.hands[1]) do eq(a.session.state.deck[i], deck[i]); eq(b.session.state.deck[i], nil) end
  for _, i in ipairs(st.hands[2]) do eq(b.session.state.deck[i], deck[i]); eq(a.session.state.deck[i], nil) end
  eq(#st.hands[1], 2); eq(ns.Deal.missing(a.session), false)
end)
it("three players: three commits, two seeds to the dealer on seat 2", function()
  --[[ table3(); start(): fair.p == {1,2,3}, fair.d == 2; sentOf("SED") has two entries, from A and C, both to B;
  c.session.state.deck == {[3]=deck[3], [6]=deck[6], [7]=deck[7]} with deck = b.session.fair.deck ]]
end)
it("only the dealer may deal or show, and a second commit is dropped", function()
  --[[ table3(); start() (stage "dealt", the dealer is B); q = a.session.seq; ACT{a=…} stands for {v=1, t="ACT", tid=tid, a=…};
  a:receive("WHISPER", C, ACT{a={k="fair", op="show", h=r.h, cards={[1]="9C"}}});
  a:receive("WHISPER", C, ACT{a={k="fair", op="deal", h=r.h, deck={}}}); a:receive("WHISPER", B, ACT{a={k="fair", op="commit", h=r.h, c=("0"):rep(64)}});
  a:receive("WHISPER", B, ACT{a={k="fair", op="show", h=r.h + 1, cards={}}}); sim:run(1): a.session.seq == q ]]
end)
it("a PRV from anyone but the dealer is ignored", function()
  --[[ after start(): a:receive("WHISPER", D, {v=1, t="PRV", tid=tid, h=r.h, cards={[2]="9C"}}): a.session.state.deck[2] == nil,
  a.session.fair.priv[2] == nil ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/deal_test.lua`.** Expected: FAIL (`Deal` is nil; no round opens).
- [ ] **Step 3: Implement** `core/Deal.lua` (rules 1–11) and its TOC line after `core/Lifecycle.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `7 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Deal.lua TavernGames.toc tests/core/deal_test.lua` — `feat(core): commit-reveal shuffle round and private deal`

### Task 5: Deal — reveal, audit and verdicts

**Files:**
- Modify: `core/Deal.lua`; Test: `tests/core/deal_audit_test.lua`

**Interfaces:**
- Produces:
  - `Deal.handOver(s) -> bool` — a round in stage `"dealt"` whose hand is finished: `s:gameOver()`, or `engine.system(s.state)` returns an action with `need == "deck"`.
  - `Deal.close(s, verdict, why)` — sets `s.fairLast = {h, verdict, why, dealer}`, counts `s.fairSeen = {ok = n, bad = n}`, stage `"done"`, emits `"fair"({tid, game, h, verdict, why, dealer, at = env.epoch()})` and `"session"`.
  - Session fields: `s.fairLast`, `s.fairSeen`; round fields `revealed`, `out` (the published seeds), `wantOpen`.
- Rules:
  12. **Reveal** (dealer, in `react`, stage `"dealt"`): when `Deal.handOver(s)` and not `revealed`: submit `{k="fair", op="reveal", h, s = <seeds in p order>}`.
  13. **Host** (`act` hook): `reveal` from seat `d` with the right `h`, in stage `"dealt"`, with `Deal.handOver(s)` and `s` an array of `#p` strings → `s:play(0, {k="fair", op="reveal", h, s})`.
  14. **`table` hook**, `reveal`: valid under the same conditions; stores `fair.out`. In `applied`: `Deal.close(s, …)` with `"bad", "dealt"` when `fair.lied`; else `"unseen"` when the round has no `base`; else `Fair.audit(engine, {tid, h, p, commits, seeds = out, base, log, priv})`. The host then opens the next round at once when `fair.wantOpen`.
  15. **Need while a reveal is due** (host, extends rule 1): a round in stage `"dealt"` → `wantOpen = true` and `fairTimer = FAIR_WAIT` → `Deal.open(s)`.
  16. **A round replaced while still `"dealt"`** (`table` hook, `open`): the old one is closed `"bad", "noreveal"` first. A seat-0 `deal` applied when no round is in stage `"seed"` (a host dealing without the commits): `Deal.close(s, "bad", "commit")` and `s.fair = nil`.
  17. A seat-0 `start` also clears `s.fairLast` and `s.fairSeen`.

- [ ] **Step 1: Write the failing tests.** Helpers as in Task 4, plus `events(client)` = the list of `"fair"` payloads that client received, and `rig(sim, tid, h, pred)`: for `k = 0..255` builds `seedA = string.format("%02x", k) .. ("ff"):rep(15)` and returns after setting `sim.nextRandom = {k, 255 ×15}` for the first `k` whose `ns.Fair.deck(H.DECK, {seedA, SEED}, tid .. "/" .. h)` satisfies `pred(deck)`; errors when none does. It is called before `a:startGame()` with `h = a.session.seq + 2` (the start event, then the open).

```lua
it("after the hand everyone replays it and marks it проверена", function()
  local sim, tid = table2(); d:watch(tid); sim:run(1); start(); local h = a.session.fair.h; auto(6); sim:run(1)
  for _, cl in ipairs{ a, b, d } do
    eq(#events(cl), 1); local e = events(cl)[1]; eq({ e.tid, e.h, e.verdict, e.why, e.dealer, e.game }, { tid, h, "ok", nil, B, "hicard" })
    eq(cl.session.fairLast.verdict, "ok"); eq(cl.session.fairSeen, { ok = 1, bad = 0 })
  end
  --[[ the reveal EV carries s == {SEED, SEED}; it comes after the last play EV and before the next open EV in sim.sent ]]
end)
it("the deal passes to the next seat and the host can be the dealer", function()
  --[[ as the test above, then sim:run(2): a new round is dealt with fair.d == 1, a.session.fair.deck ~= nil, b.session.fair.deck == nil,
  b.session.state.deck holds exactly b's two cards and the up card; no PRV goes from A to A; auto(6); sim:run(1): a second "ok" on a, b, d ]]
end)
it("a watcher who came mid-hand cannot vouch for it", function()
  --[[ d:watch(tid) after start(); auto(6); sim:run(1): events(d)[1].verdict == "unseen"; a and b got "ok" ]]
end)
it("a modified deck is flagged нередовна by everyone", function()
  local sim, tid = table2(); d:watch(tid); sim:run(1)
  local real = ns.Deck.permutation
  ns.Deck.permutation = function(key, n) local p = real(key, n); p[1], p[2] = p[2], p[1]; return p end
  start(); ns.Deck.permutation = real; auto(6); sim:run(1)
  eq({ events(a)[1].verdict, events(a)[1].why }, { "bad", "dealt" })      -- the card A was sent is not the deck's
  eq({ events(b)[1].verdict, events(b)[1].why }, { "bad", "dealt" })
  eq({ events(d)[1].verdict, events(d)[1].why }, { "bad", "play" })       -- A played a face the deck does not have there
  eq(a.session.fairSeen, { ok = 0, bad = 1 })
end)
it("a move only the full deck can judge passes at the table and is flagged at the reveal", function()
  local sim, tid = table2(); d:watch(tid); sim:run(1)
  local function suit(f) return f:sub(2, 2) end
  rig(sim, tid, a.session.seq + 2, function(k) return suit(k[2]) ~= suit(k[4]) end)     -- B holds one card of each suit
  start(); local deck = b.session.fair.deck; local off = suit(deck[2]) == suit(deck[5]) and 4 or 2
  auto(1); local q = a.session.seq
  a:receive("WHISPER", B, { v = 1, t = "ACT", tid = tid, a = { k = "play", i = off, c = deck[off] } }); sim:run(1)
  eq(a.session.seq > q, true)                                                 -- the host, on its view, cannot refuse it
  --[[ finish the hand with auto until Deal.handOver(a.session) (b resyncs by itself); sim:run(1):
  events(a)[1] and events(d)[1] are {verdict="bad", why="play"} ]]
end)
it("a dealer that never reveals: the next round opens after 20 s and the hand is нередовна", function()
  --[[ table2(); start(); auto(5); b.session.fair.revealed = true (the dealer keeps its seeds to itself); auto(1): no EV with op "reveal";
  sim:run(22): a second open EV went out; events(a)[1] and events(b)[1] are {verdict="bad", why="noreveal"}; the new round is dealt (d == 1) ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/deal_audit_test.lua`.** Expected: FAIL (no `"fair"` event, `fairLast` nil).
- [ ] **Step 3: Implement** rules 12–17.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `6 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Deal.lua tests/core/deal_audit_test.lua` — `feat(core): seeds revealed after the hand; every client audits and marks it`

### Task 6: Deal — silent players, reconnects, void and redeal, host change

**Files:**
- Modify: `core/Deal.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/core/deal_fail_test.lua`

**Interfaces:**
- Produces: `Deal.status(s) -> key, arg | nil` (pure, for the table frame): nil for an engine without the extension `fair`; stage `"commit"` → `"fair.waiting", <name of the first participant other than me without a commit>`, or `"fair.shuffle"` when none; stage `"seed"` → `"fair.dealing", fair.dealer`; otherwise `s.fairLast` → `"fair.void"` for a void, else `"fair.last", verdict`; else nil. Round fields `fresh`, `voidAsked`.
- Rules:
  18. **Reopen** (host): `Deal.open` arms `fairTimer = FAIR_WAIT`; on expiry, when I still host, the round is the same and still in `"commit"`/`"seed"`, and `engine.system(s.state)` still wants a deck: `Deal.open(s)` again (a new `h`; everybody makes a fresh seed). `Deal.open` itself does nothing when the engine does not want a deck.
  19. **A stand during the shuffle** (host, `applied`, seat-0 `stand`, stage `"commit"`/`"seed"`): `Deal.open(s)` at once.
  20. **The dealer's seat stands mid-hand** (host, `applied`, `a.seat == fair.d`, stage `"dealt"`, not `Deal.handOver(s)`, not `s:gameOver()`, `s:seatedCount() >= engine.minSeats`): `s:play(0, {k="void"})`.
  21. **Void** (`applied`, seat-0 `void`, everyone): `Deal.close(s, "void")`, `s.fairN - 1`, `s.fair = nil`. The host's timers then ask for the deal again (rule 1).
  22. **Adoption** (`adopted(s, prev, m)`): `m.fr` not a well-formed round → `s.fair = nil`. The same `h` as my round → I keep `seed`, `seedSent`, `seeds`, `deck`, `dealing`, `sent`, `pub`, `priv`, `revealed`; `commits`, `stage` come from `fr`; `base` and `log` are dropped (I missed events: this hand will be `"unseen"` for me). Another `h` → a new round from `fr` with `priv = {}`, no `base`/`log`, `fresh = true`. `s.fairN = fr.n`. Then `Deal.react(s)`.
  23. **`react` additions.** Stage `"dealt"`, I am the dealer without a deck, the hand is not over and not `voidAsked`: submit `{k="fair", op="void", h}`. Stage `"dealt"`, I am a participant other than the dealer and `Deal.missing(s)`: when `fresh`, whisper `PRQ{tid, h}` to the dealer now and clear `fresh`; else arm `askTimer = FAIR_ASK_GAP` once, and on expiry whisper `PRQ` if I still miss a face.
  24. **Host** (`act` hook): `void` from seat `d` with the right `h`, stage `"dealt"`, hand not over → `s:play(0, {k="void"})`.
  25. **`PRQ`** (dealer with a deck): from a participant of round `m.h` → `sent[seat] = {}`, `Deal.sync(s)`.
  26. A new host needs no rule of its own: `becomeHost` re-arms the timers, the engine still wants its deck when the round was not dealt, and rule 1 finds no `fairTimer` of mine, so a fresh round opens; a dealt hand simply goes on, because the deck is with the dealer and requests go to `s.host` as it is at the moment of sending.
- Locale (bg; en = faithful translations): `fair.shuffle` = „Разбъркваме заедно…“; `fair.waiting` = „Чакаме %s за разбъркването…“; `fair.dealing` = „%s раздава…“; `fair.void` = „Ръката е анулирана. Раздава се отново.“; `fair.last` = „Последната ръка: %s“; `fair.v.ok` = „проверена“ (en `verified`); `fair.v.bad` = „нередовна“ (en `irregular`); `fair.v.unseen` = „не съм я гледал цялата“.

- [ ] **Step 1: Write the failing tests.** Helpers as before; `table3()` has the dealer of hand 1 on seat 2 (`b`), the host on seat 1, `c` on seat 3 holding deck indices 3 and 6, the up card at 7. `drop(client, t)` replaces `client.receive` on the instance with a wrapper that ignores messages of type `t` and returns a function restoring it.

```lua
it("a player who never commits: the round is reopened every 20 s until he is back", function()
  local sim, tid = table2(); sim:offline(B); a:startGame(); sim:run(1)
  local h1 = a.session.fair.h; eq(a.session.fair.stage, "commit"); eq({ ns.Deal.status(a.session) }, { "fair.waiting", B })
  sim:run(20); ok(a.session.fair.h ~= h1); eq(a.session.fair.stage, "commit")
  --[[ exactly two open EVs were sent by A ]]
  sim:online(B); sim:run(20); eq(a.session.fair.stage, "dealt"); eq(b.session.fair.stage, "dealt"); eq(ns.Deal.missing(a.session), false)
end)
it("a seed that never arrives: the round is reopened", function()
  local sim = table2(); local restore = drop(b, "SED"); start()
  local h1 = a.session.fair.h; eq(a.session.fair.stage, "seed"); eq({ ns.Deal.status(a.session) }, { "fair.dealing", B })
  restore(); sim:run(20); ok(a.session.fair.h ~= h1); eq(a.session.fair.stage, "dealt")
end)
it("a relogged player gets its hand again from the dealer", function()
  local sim, tid = table3(); start(); local deck, h = b.session.fair.deck, a.session.fair.h
  local n = #sentOf("PRV"); local c2 = sim:relog(C); sim:run(2)
  eq(c2.session.state.deck, { [3] = deck[3], [6] = deck[6], [7] = deck[7] })
  --[[ exactly one PRQ in sim.sent: from C to B with h; exactly one new PRV: from B to C with cards == {[3]=deck[3], [6]=deck[6]};
  after the hand (auto(9); sim:run(1)) c2's "fair" event says "unseen", a's says "ok" ]]
end)
it("the dealer relogs mid-hand: void, the same dealer deals again", function()
  local sim = table3(); start(); local h1 = a.session.fair.h; auto(1)
  local b2 = sim:relog(B); sim:run(3)
  eq(events(a)[1].verdict, "void"); ok(a.session.fair.h ~= h1); eq({ a.session.fair.d, a.session.fair.stage }, { 2, "dealt" })
  eq(a.session.state.hand, 1); eq(a.session.state.pts, { 0, 0, 0 }); ok(b2.session.fair.deck ~= nil); eq(a.session.fairN, 1)
end)
it("the dealer stands mid-hand: void, the next player deals", function()
  local sim = table3(); start(); b:stand(); sim:run(3)
  eq(a.session.state.players, { 1, 3 }); eq(events(a)[1].verdict, "void")
  eq({ a.session.fair.d, a.session.fair.p, a.session.fair.stage }, { 3, { 1, 3 }, "dealt" }); ok(c.session.fair.deck ~= nil)
end)
it("a player stands during the shuffle: the round restarts without him", function()
  local sim = table3(); local restore = drop(b, "SED"); start(); eq(a.session.fair.stage, "seed")
  restore(); c:stand(); sim:run(1); eq({ a.session.fair.p, a.session.fair.stage }, { { 1, 2 }, "dealt" })
end)
it("the host leaves mid-hand: the next host carries the same hand on", function()
  local sim = table3(); start(); local h1 = a.session.fair.h
  a:stand(); sim:run(2); eq(b.session.role, "host"); eq({ b.session.fair.h, b.session.fair.stage }, { h1, "dealt" })
  --[[ play on with auto until Deal.handOver(b.session); sim:run(1): events(b)[1].verdict == "ok" and events(c)[1].verdict == "ok" ]]
end)
it("a reveal before the hand is over, and a void or reveal from another seat, are refused", function()
  --[[ table3(); start(); q = a.session.seq; raw ACTs to the host: from B {k="fair", op="reveal", h, s={SEED,SEED,SEED}} (hand not over);
  from C {k="fair", op="void", h}; from C {k="fair", op="reveal", h, s={SEED,SEED,SEED}}; sim:run(1): a.session.seq == q ]]
end)
it("the status line follows the round", function()
  --[[ ttt table: Deal.status == nil; hicard after start(): nil (no verdict yet); after the hand: {"fair.last", "ok"};
  after a void: {"fair.void"}; T.bg["fair.v.ok"] == "проверена", T.bg["fair.v.bad"] == "нередовна", T.en["fair.v.ok"] == "verified" ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/deal_fail_test.lua`.** Expected: FAIL (the round never reopens; no `PRQ`; no void).
- [ ] **Step 3: Implement** rules 18–26, `Deal.status`, the locale keys.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `9 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Deal.lua locale/bg.lua locale/en.lua tests/core/deal_fail_test.lua` — `feat(core): shuffle timeouts, reconnect mid-hand, void and redeal`

**— End of B1. Boundary check before B2: `bash t.sh` green, and the five Review Focus tests above exist and pass. B2 changes no rule of Tasks 2–6. —**

---

# Part B2 — Сантасе, cards, the rules book

### Task 7: Сантасе at the table — fair contract, new match, bots

**Files:**
- Modify: `engines/santase.lua`, `core/Games.lua`, `core/Lifecycle.lua`, `core/Bots.lua`, `tests/engines/santase_test.lua`, `tests/core/games_test.lua`, `tests/core/bots_test.lua`, `tests/ui/hall_test.lua`, `tests/wow/slash_test.lua`; Test: `tests/core/santase_table_test.lua`

**Interfaces:**
- Consumes: Tasks 1–6; stage A `client:startGame`, the bot host's own start (stage A Task 7), `bots:inviteMe(game)`.
- Produces:
  - `engines/santase.lua`: `E.ext = {"fair"}`; `E.again = true`; `E.nextFirst(prev, occupied)` = `3 - prev.winner` when `prev.winner` and that seat is occupied, else nil (the loser leads the new match); `{k="void"}` at seat 0 in phase `"play"` (else `"phase"`): phase `"deal"`, `hand - 1`, `turn`/`res`/`closed`/`closeOpp`/`trumpI`/`tsuit` nil, `deck`, `hands`, `stock`, `trick`, `last`, `won`, `shown` emptied, `ntr`/`pts`/`mar` zeroed, `dealer` and `gp` untouched; `play` and `marry` are refused with `"phase"` while `s.tsuit == nil` (review minor 1); rule-table line „Actions“ gains `{k="void"}`.
  - `Games.PLAYABLE.santase = true`.
  - `Session.startable(client) -> true | nil, code` (`core/Lifecycle.lua`): the checks of `startGame` without the event. Code `"mode"` now means: the engine has neither `start == "host"`, nor (`again` and `s:gameOver()`). `Session.startGame` calls it.
  - `core/Bots.lua`: a bot host starts a game 2 s after any session change that leaves `Session.startable(bot)` true (replaces the stage A condition, which it includes).

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/engines/santase_test.lua
it("void annuls the running hand and the same dealer deals again", function()
  local s = dealt(); local i = s.hands[1][1]; ok(E.apply(s, 1, { k = "play", i = i, c = s.deck[i] }))
  ok(E.apply(s, 0, { k = "void" })); eq({ s.phase, s.hand, s.dealer, s.turn }, { "deal", 0, 2, nil }); eq(s.gp, { 0, 0 }); eq(s.deck, {})
  eq({ E.system(s) }, { { k = "deal", need = "deck" }, 0 }); ok(E.apply(s, 0, { k = "deal", deck = deckOf(STD) })); eq(s.hand, 1)
  local t = E.new{ first = 1 }; eq({ E.apply(t, 0, { k = "void" }) }, { nil, "phase" })
end)
it("a view plus the deck is the full state, mid-hand", function()
  --[[ s = dealt(), two plays and the draws: for q = 0, 1, 2: ns.Fair.full(E.view(s, q), s.deck) deep-equals s ]]
end)
it("a view that has not learned the trump refuses to play", function()
  local v = E.view(E.new{ first = 1 }, 1); ok(E.apply(v, 0, { k = "deal" })); eq({ E.apply(v, 1, { k = "play", i = 1, c = "AS" }) }, { nil, "phase" })
end)
it("declares the fair contract", function() eq(E.ext, { "fair" }); eq(E.again, true)
  eq(E.nextFirst({ winner = 1 }, { true, true }), 2); eq(E.nextFirst({ winner = 1 }, { true, false }), nil); eq(E.nextFirst({}, { true, true }), nil) end)
-- tests/core/santase_table_test.lua
it("two players are dealt six cards each and the trump is public", function()
  local tid = a:openTable{ game = "santase", access = "guild", turn = 45 }; sim:run(3); d:watch(tid); b:sit(tid, 2); sim:run(1)
  local function known(cl) local n = 0; for _ in pairs(cl.session.state.deck) do n = n + 1 end; return n end
  eq({ known(a), known(b), known(d) }, { 7, 7, 1 }); eq(#a.session.state.hands[1], 6); eq(a.session.fair.d, 2); eq(a.session.state.turn, 1)
  eq(a.session.state.deck[13], b.session.fair.deck[13]); eq(a.session.state.tsuit, b.session.fair.deck[13]:sub(2, 2))
end)
it("the deal passes to the other player every hand and every hand is проверена", function()
  --[[ play by playAuto for whoever is on turn until three "fair" events arrived at a: their verdicts are {"ok","ok","ok"};
  the dealers recorded at each deal (a.session.fair.d when fairN changes) are {2, 1, 2} ]]
end)
it("my turn times out into my lowest card", function()
  --[[ b sits, hand dealt, a plays auto; then sim:run(46): seat 2's card was played by b's own client: a.session.state.trick is empty again
  (trick resolved) and the EV for seat 2 exists ]]
end)
-- tests/core/bots_test.lua
it("one human plays a whole Сантасе match against a bot; every hand is checked; nothing leaves the machine", function()
  local a, envA = sim:add(A, { cls = "MAGE" }); local bots = Bots.enable(a, envA, sim.makeEnv); sim:run(1)
  local fair, results = {}, 0; a:on("fair", function(e) fair[#fair + 1] = e.verdict end); a:on("result", function() results = results + 1 end)
  ok(a:openTable{ game = "santase", access = "invite", turn = 45 }); ok(a:invite("Бот Иванов")); sim:run(5)
  eq({ a:startGame() }, { nil, "mode" })
  for _ = 1, 6000 do
    local st = a.session.state; if ns.Engines.santase.over(st) then break end
    if st.turn == 1 then a:playAuto() end; sim:run(1)
  end
  sim:run(1); eq(ns.Engines.santase.over(a.session.state), true); eq(results, 1); ok(#fair >= 4)
  for _, v in ipairs(fair) do eq(v, "ok") end
  eq(sim:count(function(m) return m.msg.t == "SED" or m.msg.t == "PRV" or m.msg.t == "PRQ" or m.from ~= A end), 0)
  local loser = 3 - a.session.state.winner; ok(a:startGame()); sim:run(2); eq(a.session.state.gp, { 0, 0 }); eq(a.session.state.turn, loser)
end)
it("a bot hosting Сантасе starts the next match by itself", function()
  --[[ tid = bots:hostTable("santase"); a:sit(tid, 2); play to the end as above; sim:run(4): a.session.state.gp == {0, 0} and phase "play" ]]
end)
```

Existing tests to change: `tests/core/games_test.lua` (`G.list()[3].engine == ns.Engines.santase`; `G.engine("belot") == nil` stays); `tests/ui/hall_test.lua` (three active games, three dimmed: indices 1–3 and 4–6); `tests/wow/slash_test.lua` gains `w:slash("bots host santase")` → the listed table's `game == "santase"`.

- [ ] **Step 2: Run `bash t.sh tests/engines/santase_test.lua tests/core/santase_table_test.lua tests/core/bots_test.lua`.** Expected: the new tests FAIL (`void` unknown, `santase` not playable).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run those files, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add engines/santase.lua core/Games.lua core/Lifecycle.lua core/Bots.lua tests/engines/santase_test.lua tests/core/santase_table_test.lua tests/core/games_test.lua tests/core/bots_test.lua tests/ui/hall_test.lua tests/wow/slash_test.lua` — `feat: Сантасе at the table on a fair deal, new match by the host, bots as full players`

### Task 8: Card textures

**Files:**
- Modify: `tools/gen_textures.py`, `ui/Theme.lua`; Create: `media/card.tga`, `media/card_back.tga`, `media/suits.tga`; Test: `tests/ui/theme_test.lua`

**Interfaces:**
- Produces: `Theme.texSize.card = {64, 128}`, `card_back = {64, 128}`, `suits = {128, 32}` (and so `Theme.tex.card`, `.card_back`, `.suits`); `Theme.color.cardInk = hex("22170f")`, `cardEdge = hex("c7ad82")`.
- Drawing (signed-distance shapes with the file's `cover`/`sd_round_rect`/`sd_circle`): `card` = a rounded rectangle filling the texture (radius 8) in `#fbf3e2` with a 2 px edge `#c7ad82`, transparent outside; `card_back` = the same shape with 45° stripes 8 px wide alternating `#3b1d10` / `#5c311a` and a 2 px edge `#c19350`; `suits` = four 32×32 cells, white on transparent: club (three circles and a stem), diamond (`|x| + |y| ≤ r`), heart (two circles over a downward triangle), spade (the heart upside down plus a stem). The three entries are **appended** to `TEXTURES` (the shared `rng` must not shift for the earlier files).

- [ ] **Step 1: Write the failing test** (`tests/ui/theme_test.lua`; `ui/Theme.lua` is data only: `loadfile("ui/Theme.lua")("TavernGames", ns)`).

```lua
it("every texture in the theme exists as a 32-bit TGA of the listed size", function()
  local n = 0
  for name, size in pairs(Theme.texSize) do
    local w, h = type(size) == "table" and size[1] or size, type(size) == "table" and size[2] or size
    local f = io.open("media/" .. name .. ".tga", "rb"); ok(f, "missing media/" .. name .. ".tga")
    if f then local d = f:read(18); f:close(); eq({ d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256, d:byte(17) }, { w, h, 32 }, name); n = n + 1 end
  end
  eq(Theme.texSize.card, { 64, 128 }); eq(Theme.texSize.card_back, { 64, 128 }); eq(Theme.texSize.suits, { 128, 32 }); ok(n >= 15)
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/theme_test.lua`.** Expected: FAIL (`card` is nil).
- [ ] **Step 3: Implement**, then run `py tools/gen_textures.py` (on this machine the interpreter is `py`; `python` elsewhere). Expected output ends with `media/card.tga 64x128`, `media/card_back.tga 64x128`, `media/suits.tga 128x32`, and `git status --short media` lists only those three files as new (the twelve existing files are byte-identical).
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `1 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add tools/gen_textures.py ui/Theme.lua media/card.tga media/card_back.tga media/suits.tga tests/ui/theme_test.lua` — `feat(media): card face, card back and suit textures`

### Task 9: The card widget and the fan

**Files:**
- Create: `ui/Cards.lua`; Modify: `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`; Test: `tests/ui/cards_test.lua`

**Interfaces:**
- Consumes: Task 8 textures, `W.Label`, `W.edges`, `Theme`.
- Produces `ns.Cards` (reused by Belot and Hold'em):
  - `Cards.W, Cards.H, Cards.STEP, Cards.RAISE, Cards.DIM = 40, 58, 28, 8, 0.55`.
  - `Cards.rank(face) -> text` — `L("card.T")` … `L("card.A")` for `T J Q K A`, the digit itself otherwise; `Cards.red(face) -> bool` (suits `D`, `H`); `Cards.suitName(suit) -> L("suit.<suit>")`; `Cards.COORD = {C = {0, 0.25}, D = {0.25, 0.5}, H = {0.5, 0.75}, S = {0.75, 1}}` (left/right texture coordinates in `suits`).
  - `Cards.layout(n, step, w) -> {x1, …, xn}` — left edges of `n` cards centred on 0: `x[k] = (k - 1)·step − ((n − 1)·step + w)/2`.
  - `Cards.card(parent, scale) -> card` — `{frame (Button), body, rank, pip, big, edges, face, mode}` with `card:set(face|nil)` (nil = the back: `card_back`, no rank or suit) and `card:look(mode)`: `"plain"`; `"raised"` (a 2 px gold edge, drawn `RAISE` higher by its owner); `"dim"` (body, suit and rank at `DIM` brightness). The rank sits top-left (`uiBold`, 13), a small suit under it (10 px), a large suit bottom-right (21 px); red faces in `red`, black in `cardInk`.
  - `Cards.fan(parent, opts) -> fan` — `opts = {step = 28, scale = 1}`; `fan:set(entries, onClick)` with `entries = {{i, face, mode}, …}`: shows `#entries` cards at `Cards.layout` offsets (each records `x`, `y` — `RAISE` when raised, else 0 — `face`, `mode`, `entry`), hides the rest; a click on a card that is not `"dim"` calls `onClick(entry)`; `fan.cards` are the widgets, `fan.frame` the frame (`(n − 1)·step + W` wide).
- Locale (identical in bg and en unless given): `card.T` = „10“, `card.J` = „J“, `card.Q` = „Q“, `card.K` = „K“, `card.A` = „A“; `suit.C` = „спатия“ (en `clubs`), `suit.D` = „каро“ (`diamonds`), `suit.H` = „купа“ (`hearts`), `suit.S` = „пика“ (`spades`).

- [ ] **Step 1: Write the failing tests** (`guildWow()` as in the other UI tests; `C = w.ns.Cards`).

```lua
it("lays a fan out around the centre", function()
  eq(C.layout(6, 28, 40), { -90, -62, -34, -6, 22, 50 }); eq(C.layout(1, 28, 40), { -20 }); eq(C.layout(0, 28, 40), {})
end)
it("names ranks and suits", function()
  eq({ C.rank("TS"), C.rank("9H"), C.rank("KD") }, { "10", "9", "K" }); eq({ C.red("9H"), C.red("QD"), C.red("TS"), C.red("AC") }, { true, true, false, false })
  eq(C.suitName("H"), "купа"); eq(C.COORD.S, { 0.75, 1 })
end)
it("a fan shows faces, backs, raised and dimmed cards and reports clicks on playable ones", function()
  local fan = C.fan(w.G.UIParent, {}); local got = {}
  fan:set({ { i = 1, face = "KH", mode = "raised" }, { i = 2, mode = "plain" }, { i = 3, face = "TS", mode = "dim" } }, function(e) got[#got + 1] = e.i end)
  local c1, c2, c3 = fan.cards[1], fan.cards[2], fan.cards[3]
  eq({ c1.rank:GetText(), c1.y, c1.x, c1.mode }, { "K", 8, -48, "raised" }); eq(color(c1.rank), rgb(w, "red"))
  eq(c2.face, nil); eq(c2.body:GetTexture(), w.ns.Theme.tex.card_back); eq(c2.rank:IsVisible(), false); eq(c2.y, 0)
  eq(c3.mode, "dim"); eq(color(c3.rank), rgb(w, "cardInk")); eq(fan.frame:GetWidth(), 96)
  w:click(c1.frame); w:click(c3.frame); w:click(c2.frame); eq(got, { 1, 2 })
  fan:set({ { i = 9, face = "9C", mode = "plain" } }); eq(fan.cards[2].frame:IsVisible(), false); eq(fan.cards[1].x, -20)
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/cards_test.lua`.** Expected: FAIL (`Cards` is nil).
- [ ] **Step 3: Implement**; TOC line `ui/Cards.lua` after `ui/Widgets.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `3 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add ui/Cards.lua locale/bg.lua locale/en.lua TavernGames.toc tests/ui/cards_test.lua` — `feat(ui): card widget and hand fan`

### Task 10: Table frame — the fairness line and „Нова игра“

**Files:**
- Modify: `ui/TableFrame.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/ui/table_test.lua`

**Interfaces:**
- Consumes: `ns.Deal.status`, `s.fairLast`, `s.fairSeen`, `Session.startable`, `engine.again`, stage A `v.startButton`, `W.tooltip`, `ns.HelpBook.open` (called through `ns.HelpBook` at click time).
- Produces:
  - `v.fairLine` — a button with one text line (12 pt, centred) at the bottom edge of the felt (`BOTTOM` of `v.area`, 6 px up), shown when `Deal.status(s)` returns a key. Text: `L(key, arg)`, except `"fair.last"` → `L("fair.last", L("fair.v." .. verdict))`. Colour: `red` when the last verdict is `"bad"` or `s.fairSeen.bad > 0`; `good` for `"ok"`; `inkDim` otherwise. Click → `ns.HelpBook.open("fair")`. Tooltip: `L("fair.tip." .. verdict)`; for `"bad"` `L("fair.tip.bad", L("fair.why." .. why))`; plus `L("fair.badCount", n)` on a second line when `fairSeen.bad > 0`.
  - `v.startButton` (stage A): also shown to the host of a game with `engine.again` once `s:gameOver()`, with the text `L("table.again")`; enabled when `Session.startable(client)`.
- Locale (bg): `fair.tip.ok` = „Всички на масата дадоха своята част от разбъркването. След ръката аддонът нареди тестето наново и провери всеки ход.“; `fair.tip.unseen` = „Дошъл си по средата на ръката, затова аддонът не може да я провери. Следващата ще бъде проверена.“; `fair.tip.void` = „Раздаващият излезе или презареди играта. Ръката не се брои.“; `fair.tip.bad` = „Проверката не излезе: %s Кажи на останалите.“; `fair.why.seeds` = „липсва част от разбъркването.“; `fair.why.commit` = „някой е сменил своята част от разбъркването.“; `fair.why.deal` = „обърнатата карта не е от това тесте.“; `fair.why.dealt` = „картите, които получих, не са от това тесте.“; `fair.why.play` = „изигран е ход, който правилата не позволяват, или карта, която играчът не е държал.“; `fair.why.noreveal` = „раздаващият не показа разбъркването.“; `fair.badCount` = „Нередовни ръце на тази маса: %d“.

- [ ] **Step 1: Write the failing tests** (`santaseWithBot()` = `withBots()`, I open Сантасе „Само поканени“, the bot is invited through the picker, `w:advance(2)`: a hand is dealt).

```lua
it("a card table shows the last hand's verdict; a Морски шах table shows none", function()
  local w, v = santaseWithBot(); local s = w.ns.client.session
  s.fairLast, s.fairSeen = { h = 5, verdict = "ok", dealer = BOT }, { ok = 1, bad = 0 }; w.ns.TableFrame.render()
  eq(v.fairLine.text:GetText(), "Последната ръка: проверена"); eq(color(v.fairLine.text), rgb(w, "good"))
  s.fairLast, s.fairSeen = { h = 9, verdict = "bad", why = "play", dealer = BOT }, { ok = 1, bad = 1 }; w.ns.TableFrame.render()
  eq(v.fairLine.text:GetText(), "Последната ръка: нередовна"); eq(color(v.fairLine.text), rgb(w, "red"))
  local opened; w.ns.HelpBook.open = function(id) opened = id end; w:click(v.fairLine); eq(opened, "fair")
  --[[ hovering shows a tooltip containing "Проверката не излезе: изигран е ход" and "Нередовни ръце на тази маса: 1";
  s.fairLast = {verdict="void"}: "Ръката е анулирана. Раздава се отново."; in matchWithBot() (ttt): v.fairLine is hidden ]]
end)
it("during the shuffle the line says who we are waiting for", function()
  --[[ s.fair = {stage="commit", p={1,2}, commits={[1]="x"}, dealer=BOT}; render: "Чакаме Бот Иванов за разбъркването…";
  stage "seed": "Бот Иванов раздава…" ]]
end)
it("after the match the host gets „Нова игра“", function()
  --[[ santaseWithBot(): startButton hidden while the match runs; set s.state.phase, s.state.winner = "match", 1; render:
  startButton visible, enabled, text „Нова игра“; w:click(v.startButton); w:advance(2): s.state.gp == {0, 0}, startButton hidden ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/table_test.lua`.** Expected: the three new tests FAIL (`fairLine` is nil).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add ui/TableFrame.lua locale/bg.lua locale/en.lua tests/ui/table_test.lua` — `feat(ui): the table shows whether the last hand was verified; new match button`

### Task 11: The Сантасе view

**Files:**
- Create: `ui/games/SantaseView.lua`; Modify: `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`; Test: `tests/ui/santase_test.lua`

**Interfaces:**
- Consumes: `ns.Cards`, `ns.Engines.santase` (`legal`, `points`, state fields `hands`, `deck`, `stock`, `trumpI`, `tsuit`, `closed`, `trick`, `last`, `lead`, `turn`, `gp`, `res`, `phase`, `winner`, `left`, `shown`), `client:act`, `TableFrame.registerView`.
- Produces: `TableFrame.registerView("santase", View)` with `View.build`, `View.update`, `View.seatNote`, and the pure `View.model(session, declare) -> model`; the built frame exposes `myFan`, `oppFan`, `trick` (two card widgets), `stockCard`, `trumpCard`, `marryButton`, `swapButton`, `closeButton`, `text`.
- `View.model` (everything the drawing needs; `declare` = the „Обяви“ button is armed):
  - `me` = my seat, or 1 for a watcher; `opp = 3 − me`; `mine` = I am seated and it is my turn in phase `"play"`.
  - `hand` = my cards as `{i, face, mode}`, sorted by suit `C D H S`, inside a suit by card points descending, unknown faces last. Modes: not `mine` → all `"plain"`; `mine` and `declare` → the cards that have a `marry` action `"raised"`, the others `"dim"`; `mine` otherwise → when some card has no `play` action: playable `"raised"`, the others `"dim"`; when all are playable: `"plain"`. A watcher's `hand` is seat 1's cards without faces.
  - `oppHand` = the opponent's cards as `{i, face}` (a face only where my view knows it: a shown marriage partner, a trump card taken from under the stock).
  - `stock = #state.stock`, `trump` = the face at `state.trumpI` or nil, `tsuit`, `closed = state.closed ~= nil`, `trick = {{seat, i, face}, …}` (the leader first), `last` = the faces of `state.last`.
  - `buttons = {marry = 40 | 20 | nil, swap = <the swap9 action> | nil, close = bool}` from `E.legal(state, me)` when `mine`, else all nil/false; `marry` is 40 when a `marry` action is in the trump suit.
  - `text = {key, …}`: phase `"match"` → `{"santase.left", <name of state.left>}` when somebody left, else `{"santase.match", <winner's name>}`; phase `"hand"` → `{"santase.hand.tie"}` or `{"santase.hand.won", name, res.gp}`; phase `"play"` → `{"santase.pick"}` when `declare`, `{"santase.yourTurn"}` when `mine`, else `{"santase.waitFor", <name on turn>}`; phase `"deal"` → nil.
- Drawing (frame 512×260, mockup 03): the opponent's fan at the top (scale 0.8, backs, known faces face up); left, at mid height: the stock as a back with the trump card half-covered to its right (a back over it when closed; nothing when the stock is empty), under them `L("santase.stock", n)` and `L("santase.trump", Cards.suitName(tsuit))` (or `L("santase.closed")`); centre: the two trick cards (the leader's left); right of centre, at scale 0.7 and dimmed, the last trick under `L("santase.last")`; right edge, stacked: `marryButton` (`santase.marry20`/`santase.marry40`), `swapButton` (`santase.swap`), `closeButton` (`santase.close`, red), each shown only when its `buttons` entry is set; bottom: my fan; above it, centred, `text` (gold in phases `"hand"`/`"match"`); top-left `L("santase.score", gp[me], gp[opp])`.
- Clicks: a card → armed: the `marry` action whose `i` is that card; else its `play` action; through `client:act`. `marryButton` toggles the armed state; `swapButton` and `closeButton` act at once. The armed state ends with any event. `View.seatNote(s, seat)` = `L("santase.points", E.points(state, seat))` while a hand runs, else `""`.
- Locale (bg; en faithful, pinned where given): `santase.marry20` = „Обяви 20“ (en `Declare 20`); `santase.marry40` = „Обяви 40“ (`Declare 40`); `santase.swap` = „Смени деветката“ (`Swap the nine`); `santase.close` = „Затвори“ (`Close`); `santase.pick` = „Избери попа или дамата“; `santase.stock` = „Тесте: %d карти“; `santase.trump` = „Коз: %s“; `santase.closed` = „Тестето е затворено“; `santase.last` = „Последна взятка“; `santase.points` = „%d точки“; `santase.score` = „до 11 игри · %d : %d“; `santase.yourTurn` = „Твой ход“; `santase.waitFor` = „Изчакай %s…“; `santase.hand.won` = „%s взима ръката: +%d“; `santase.hand.tie` = „Равна ръка. Никой не взима игра.“; `santase.match` = „%s печели партията!“; `santase.left` = „%s стана от масата.“

- [ ] **Step 1: Write the failing tests.** File scope: `santaseWithBot()` as in Task 10 returning `w, V, View` (`V = w.ns.TableFrame.built.santase`); `E = w.ns.Engines.santase`; `show(w, state)` = `w.ns.client.session.state = state; w.ns.TableFrame.render()`. Decks by hand (`DM[i]` = face of deck index `i`): `DM = {"KH","QH","TS", "AS","JC","QC", "JD","AD","9S", "KC","TC","AC", "JH", "9D","QD","KD","TD","9H","TH","AH","JS","QS","KS","9C"}` — seat 1 (me) holds indices 1–3 and 7–9, seat 2 indices 4–6 and 10–12, the trump card is `JH`. `full()` = `E.new{first = 1}` with `DM` dealt.

```lua
it("my lead: the hand sorted by suit, a 40 to declare, „Затвори“ offered, no swap", function()
  local w, V, View = santaseWithBot(); local s = w.ns.client.session; s.state = E.view(full(), 1)
  local m = View.model(s, false); local ids, modes = {}, {}
  for k, c in ipairs(m.hand) do ids[k], modes[k] = c.i, c.mode end
  eq(ids, { 8, 7, 1, 2, 3, 9 }); eq(modes, { "plain", "plain", "plain", "plain", "plain", "plain" })   -- AD JD | KH QH | TS 9S
  eq({ m.buttons.marry, m.buttons.swap, m.buttons.close }, { 40, nil, true }); eq({ m.stock, m.trump, m.tsuit, m.closed }, { 12, "JH", "H", false })
  eq(m.text, { "santase.yourTurn" }); eq(#m.oppHand, 6); eq(m.oppHand[1].face, nil)
  show(w, s.state); eq(V.marryButton:IsVisible(), true); eq(V.marryButton.text:GetText(), "Обяви 40"); eq(V.swapButton:IsVisible(), false)
  eq(V.closeButton:IsVisible(), true); eq(#w:texts("Тесте: 12 карти"), 1); eq(#w:texts("Коз: купа"), 1); eq(V.oppFan.cards[1].face, nil)
end)
it("armed „Обяви 40“: only the king and queen are raised, and a click declares", function()
  local w, V, View = santaseWithBot(); local s = w.ns.client.session; show(w, E.view(full(), 1))
  w:click(V.marryButton); local modes = {}; for k, c in ipairs(View.model(s, true).hand) do modes[k] = c.mode end
  eq(modes, { "dim", "dim", "raised", "raised", "dim", "dim" }); eq(#w:texts("Избери попа или дамата"), 1)
  local sent; w.ns.client.act = function(_, a) sent = a; return true end
  w:click(V.myFan.cards[3].frame); eq(sent, { k = "marry", i = 1, c = "KH", j = 2, d = "QH" })
end)
it("closed stock: cards I may not play are dimmed and not clickable", function()
  local st = full(); ok(E.apply(st, 1, { k = "play", i = 9, c = "9S" })); ok(E.apply(st, 2, { k = "play", i = 4, c = "AS" }))   -- seat 2 wins, draws 14, I draw 15
  ok(E.apply(st, 2, { k = "close" })); ok(E.apply(st, 2, { k = "play", i = 12, c = "AC" }))
  local w, V, View = santaseWithBot(); local s = w.ns.client.session; show(w, E.view(st, 1))
  local ids, modes = {}, {}; for k, c in ipairs(View.model(s, false).hand) do ids[k], modes[k] = c.i, c.mode end
  eq(ids, { 8, 15, 7, 1, 2, 3 }); eq(modes, { "dim", "dim", "dim", "raised", "raised", "dim" })     -- no club: I must trump with KH or QH
  local sent; w.ns.client.act = function(_, a) sent = a; return true end
  w:click(V.myFan.cards[1].frame); eq(sent, nil); w:click(V.myFan.cards[4].frame); eq(sent, { k = "play", i = 1, c = "KH" })
  eq(#w:texts("Тестето е затворено"), 1); eq(V.closeButton:IsVisible(), false); eq(V.trick[1].face, "AC")
end)
it("„Смени деветката“ shows only when the swap is legal", function()
  --[[ st = full(); st.ntr[1] = 1; st.deck[9], st.deck[18] = st.deck[18], st.deck[9] (index 9 is now 9H): View.model(view of seat 1).buttons.swap
  == {k="swap9", i=9, c="9H"} and the button is visible; with st.ntr[1] = 0 it is nil and hidden ]]
end)
it("a watcher sees two hands of backs and no buttons; the end of a hand and of the match are announced", function()
  --[[ E.view(full(), 0) with session.mySeat = nil, role "watcher": every model.hand face nil, buttons {nil, nil, false}, text {"santase.waitFor", ME};
  state.phase, state.res = "hand", {winner=1, gp=2, reason="66"}: one visible "Иван Петров взима ръката: +2";
  state.phase, state.winner = "match", 2: one visible "Бот Иванов печели партията!"; View.seatNote(s, 1) == "" then, "0 точки" mid-hand ]]
end)
it("solo against a bot from a real deal: six faces for me, six backs for the bot, a click plays", function()
  local w, V = santaseWithBot(); local s = w.ns.client.session
  eq(#s.state.hands[1], 6); for k = 1, 6 do ok(V.myFan.cards[k].face); eq(V.oppFan.cards[k].face, nil) end
  ok(V.trumpCard.face); local i = V.myFan.cards[1].entry.i; w:click(V.myFan.cards[1].frame); w:advance(0)
  eq(s.state.trick[1], i); w:advance(3); eq(#s.state.trick, 0)       -- the bot answered after 1.5 s and the trick was taken
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/santase_test.lua`.** Expected: FAIL (no view registered).
- [ ] **Step 3: Implement**; TOC line `ui/games/SantaseView.lua` after `ui/games/DeathRollView.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `6 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add ui/games/SantaseView.lua locale/bg.lua locale/en.lua TavernGames.toc tests/ui/santase_test.lua` — `feat(ui): Сантасе table view`

### Task 12: Rules-book topics „Сантасе“ and „Защо раздаването е честно“

**Files:**
- Modify: `core/Help.lua`, `ui/HelpBook.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/core/locale_help_test.lua`, `tests/ui/book_test.lua`

**Interfaces:**
- Produces: `ns.Help.topics` ids `{"hall", "ttt", "deathroll", "santase", "fair", "soon"}`; block kind `"cards"` = `{kind="cards", key, cards={face, …}}` drawn by `BLOCKS.cards` as a row of `ns.Cards.card` widgets (scale 0.8, 4 px apart) above the text. (`HelpBook.current` already holds the id of the topic showing.)
  - Topic `santase` (title `game.santase`): blocks `p1`, `example`, `cards` (cards `AS TS KS QS JS 9S`), `trick`, `strict`, `marriage` (kind `cards`, `KH QH`), `swap`, `close`, `score`, `time`, `fair`.
  - Topic `fair` (title `help.fair.title`): blocks `p1`, `example`, `how`, `verify`, `dealer`, `bad`.
  - The quoted-label test also covers `^help%.santase%.` and `^help%.fair%.` (every „…“ in them is a UI label).
- Locale, pinned bg (en = faithful translations in the same simple tone):
  - `help.santase.p1` = „Сантасе е игра за двама с 24 карти, от деветка до асо. Целта е първи да събереш 66 точки в ръката. Който спечели ръката, взима от 1 до 3 игри. Партията е до 11 игри.“
  - `help.santase.example` = „Иван и Мария сядат на маса. Всеки получава шест карти, а една карта се обръща под тестето: тя показва коза. Мария играе десетка пика. Иван няма по-силна пика и дава вале. Мария прибира двете карти и вече има 12 точки. После двамата теглят по карта и Мария играе пак.“
  - `help.santase.cards` = „Картите по сила: асо 11 точки, десетка 10, поп (K) 4, дама (Q) 3, вале (J) 2, деветка 0.“
  - `help.santase.trick` = „Докато в тестето има карти, играеш каквато карта искаш. Взима по-силната карта от същата боя, а козът бие всяка друга боя. Който вземе, тегли пръв и играе пръв.“
  - `help.santase.strict` = „Щом тестето свърши или някой го затвори, вече се отговаря на боята и се надцаква, ако можеш. Нямаш ли от боята, цакаш с коз. Картите, които не може да играеш, са потъмнени.“
  - `help.santase.marriage` = „Поп и дама от една боя носят 20 точки, а от коза носят 40. Когато си на ход и държиш двете, се появява бутон „Обяви 20“ или „Обяви 40“. Натискаш го и играеш попа или дамата. Точките се броят, щом имаш поне една взятка.“
  - `help.santase.swap` = „Имаш деветката от коза и поне една взятка? Когато си на ход, с „Смени деветката“ я разменяш за обърнатата карта под тестето. Става само докато в тестето има повече от две карти.“
  - `help.santase.close` = „Мислиш, че ще стигнеш 66 и без да теглиш? Натисни „Затвори“, когато си на ход и в тестето има повече от две карти. Никой не тегли повече. Не стигнеш ли 66, другият взима 2 игри, а ако е бил без взятка, взима 3.“
  - `help.santase.score` = „Ръката свършва сама, щом някой събере 66. Той взима 1 игра. Ако другият има под 33 точки, взима 2. Ако другият няма нито една взятка, взима 3. Последната взятка носи 10 точки, когато тестето е изиграно докрай.“
  - `help.santase.time` = „Ако времето ти изтече, аддонът играе най-слабата ти позволена карта. Не губиш служебно. След партията домакинът натиска „Нова игра“.“
  - `help.santase.fair` = „Под масата пише дали последната ръка е „проверена“. Какво значи това, виж в темата за честното раздаване.“
  - `help.fair.title` = „Защо раздаването е честно“
  - `help.fair.p1` = „В игрите с карти никой не разбърква тестето сам. Всеки на масата дава по едно тайно число и редът на картите излиза от всички числа заедно. Докато поне един на масата е честен, никой не може да нагласи картите.“
  - `help.fair.example` = „Иван и Мария играят Сантасе. Всеки си намисля тайно число и го заключва в кутийка. Двамата слагат кутийките на масата. Чак тогава Иван дава числото си на Мария, защото тя раздава тази ръка. Мария събира двете числа и от тях излиза редът на картите. Никой не е могъл да смени числото си, след като е видял чуждото: кутийката вече е била на масата.“
  - `help.fair.how` = „Кутийката е отпечатък на числото. От отпечатъка числото не може да се познае. После обаче всеки може да провери, че числото е същото.“
  - `help.fair.verify` = „След всяка ръка числата се показват на всички. Твоят аддон сам нарежда тестето наново и минава през цялата ръка: дали картите, които получи, са от това тесте и дали всеки ход е бил позволен. Ако всичко излиза, под масата пише „проверена“. Ако нещо не излиза, пише „нередовна“ и това го виждат всички на масата.“
  - `help.fair.dealer` = „Едно нещо да знаеш: аддонът на раздаващия знае цялото тесте в ръката, която раздава. Иначе няма как да ти прати твоите карти. Обикновен играч това не го вижда. Само подправен аддон може да наднича, и то само когато раздава. Затова раздаването минава при следващия играч всяка ръка, а накрая всяка ръка се проверява.“
  - `help.fair.bad` = „Видиш ли „нередовна“, кажи на останалите. Посочи надписа с мишката и ще видиш какво точно не излиза. Една ръка може да е нередовна и защото раздаващият е излязъл точно накрая, без да покаже числата.“
  - `help.soon.p` = „Скоро идват Белот, Табла и Тексас Холдем, и игра на залог с тефтер на дълговете.“; `help.soon.example` = „Засега в кръчмата се играят Морски шах, Death Roll и Сантасе. Другите игри стоят бледи в списъка, с надпис „Скоро“. Щом станат готови, правилата им ще се появят тук, в книжката.“

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/core/locale_help_test.lua: topics are {"hall","ttt","deathroll","santase","fair","soon"}; "cards" is an allowed kind; the santase topic
-- has exactly two cards blocks, with cards {"AS","TS","KS","QS","JS","9S"} and {"KH","QH"}; every face in them is in ns.Engines.santase.DECK;
-- the quoted-label loop also covers ^help%.santase%. and ^help%.fair%. and checks at least 8 more labels;
-- pinned: T.bg["help.fair.dealer"], T.bg["help.santase.close"], T.bg["help.soon.p"] equal the strings above; T.en["santase.swap"] == "Swap the nine".
-- tests/ui/book_test.lua
it("the Сантасе topic draws its cards; ⓘ on a Сантасе table opens it; the fair topic is reachable", function()
  --[[ B.open("santase"): the page holds 8 card widgets, the first with rank text "A" and face "AS", the last two "K" and "Q" in red;
  B.open("fair"): one visible text starting "В игрите с карти никой не разбърква тестето сам"; HelpBook.current == "fair";
  on a Сантасе table (santaseWithBot) w:click(v.info): HelpBook.current == "santase" ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/locale_help_test.lua tests/ui/book_test.lua`.** Expected: FAIL (topics missing).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add core/Help.lua ui/HelpBook.lua locale/bg.lua locale/en.lua tests/core/locale_help_test.lua tests/ui/book_test.lua` — `feat(ui): rules-book topics for Сантасе and the fair deal`

### Task 13: In-game check list and documentation

**Files:**
- Create: `docs/superpowers/notes/2026-11-stageB-ingame-checks.md`; Modify: `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` (`### Shared contracts`: a subsection „Stage B additions“), `.superpowers/sdd/engines-parallel/contract.md` (an addendum: the `need` marker, view ⊕ deck, `void`, `E.again`)

**Interfaces:** none. The notes file holds the table below with a `Result` column, every row `not yet measured`. Nothing is marked passed on the strength of the unit tests.

- [ ] **Step 1: `bash t.sh`.** Expected: `N passed, 0 failed`.
- [ ] **Step 2: Write the notes file** (`/console scriptErrors 1` throughout; rows 8–14 need a second account, row 13 a third):

| # | Check | What to look for |
|---|---|---|
| 1 | `/tavern bots`, open Сантасе „Само поканени“, invite a bot | six cards face up for me, six backs for the bot, the trump half under the stock, within about a second; no hitch when the hand is dealt (pure-Lua SHA-256) |
| 2 | `/tavern debug` through one hand | my outgoing lines to the bot carry only the cards I play; `SED` goes only to the dealer, `PRV` comes only from it; no GUILD line has a card, a seed or a commit |
| 3 | finish a hand | under the felt „Последната ръка: проверена“; hovering explains it; clicking opens „Защо раздаването е честно“ |
| 4 | the three buttons | „Обяви 20/40“ only on my lead with king and queen in hand (armed: only those two raised); „Смени деветката“ only with the trump nine, a trick taken and more than two stock cards; „Затвори“ only on my lead with more than two stock cards |
| 5 | after closing, or with the stock empty | cards I may not play are dimmed and do nothing when clicked |
| 6 | let my turn run out | my lowest allowed card is played; I do not lose the hand by the clock |
| 7 | play to 11 | „… печели партията!“, one result, „Нова игра“ starts a match led by the loser; ⓘ opens „Сантасе“ with the card pictures |
| 8 | two characters: A opens, B sits | both get cards; neither trace shows the other's hand; both read „проверена“ after the hand; the dealer alternates (the line „… раздава…“ if it ever lingers) |
| 9 | B (not the dealer) `/reload`s mid-hand | B's cards are back within about two seconds; play goes on; B reads „не съм я гледал цялата“ for that hand, „проверена“ for the next |
| 10 | the dealer `/reload`s mid-hand | „Ръката е анулирана. Раздава се отново.“ on both; the same player deals; no game point moved |
| 11 | B logs out during the shuffle (stand up from the keyboard right after sitting) | A reads „Чакаме B за разбъркването…“; when B is back within 3 minutes a hand is dealt within 20 s; otherwise B is stood up and the table reads „Играта е прекъсната.“ |
| 12 | B logs out on its own turn mid-hand | nothing is played for B (nobody can see its cards); B back: its clock plays or B plays; B away 3 minutes: stood up, A wins the match |
| 13 | a third character watches from the start, and another joins mid-hand | backs for both hands; its trace has no hidden card; „проверена“ for the first, „не съм я гледал цялата“ for the latecomer |
| 14 | the host stands mid-hand | Сантасе ends the match for the leaver (rule 16); the other player's frame names the winner |
| 15 | card art at UI scale 0.65 and 1.0 | ranks and suits readable, red and black distinct, the raised edge and the dimming visible on the felt |
| 16 | count the whispers of one deal with `/tavern debug` | about ten addon whispers per hand per player; no ChatThrottleLib delay visible |

- [ ] **Step 3: Update the two documents**: the stage 1 plan's Shared contracts gets this plan's three tables (randomness, fair-engine contract, protocol additions) under „Stage B additions“; the engines contract gets the addendum.
- [ ] **Step 4: Report to the user** which rows need a second account and that row 12 is the known price of hidden hands (see Self-review, decisions).
- [ ] **Step 5: Commit.** `git add docs/superpowers/notes/2026-11-stageB-ingame-checks.md docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md .superpowers/sdd/engines-parallel/contract.md` — `docs: stage B in-game check list and protocol additions`

---

## Self-review (applied)

- **Spec coverage:** 6.3 step 1 (dealer rotates by seat) → Task 4 rule 2, Task 5 `the deal passes…`; step 2 (commit to all) → Task 4 rules 3–6; step 3 (seed only to the dealer, commits checked) → Task 4 rules 6–7; step 4 (deck from all seeds and the hand id, private deal) → Tasks 3, 4 rules 7–9; step 5 (seeds published, every client checks commits, deck and every played card, marks the hand, visible to all) → Tasks 3, 5, 10; "dealer leaves mid-hand → annulled, dealt again" → Task 6 rules 20–24; 6.2 (host orders events and clocks, every client applies every event, reconnect = public snapshot + private data) → Tasks 2, 6; timeout = automatic action → Task 2 (`armAuto`), Task 7; 5.3 Сантасе (stock and trump left, three buttons only when legal, legal raised, illegal dimmed) → Tasks 9, 11; 5.3а topics in bg/en with tavern-talk examples and pictures → Task 12; 6.5 bots and trace → Task 7, check list rows 1–2; ruling X1 → Task 1; ruling G1 → Task 7. Anti-goal "a modified client sees other hands in a deal it does not make" → the host works on a view (Task 2), tested in Task 4.
- **Decisions the plan makes beyond the spec (the user may contest):**
  1. The **dealer, not the host, holds the deck**; the host orders events on a view. A host that held it would see every hand of every deal, which the spec names as failure. Cost: the host cannot judge follow-suit for a hand it does not see; such a move passes and is flagged at the reveal.
  2. The dealer **role rotates strictly by seat** (2, 1, 2, …) and is separate from Santase's own rule "the winner of a hand deals the next" (which now only decides who leads). Otherwise a player who keeps winning would hold the deck every hand.
  3. The **dealer publishes all seeds** in one event instead of each player its own: a commit binds, so the dealer cannot forge one, and a player who left cannot block the check.
  4. Commits, the public deal and the reveal ride in the host's ordered `EV` stream (reliable, reaches watchers, healed by the existing resync); only `SED`, `PRV`, `PRQ` are new types.
  5. A silent player during the shuffle is **waited for** (round reopened every 20 s, then the 3-minute offline rule); nobody shuffles on his behalf.
  6. An **offline player's turn is not played** for him in a card game (nobody else may know his cards); an online but idle player's own client plays at the deadline.
  7. A dealer who reloads loses the deck: the hand is void and dealt again. A dealer who vanishes exactly at the end of a hand makes it „нередовна“ (`noreveal`).
  8. A client that did not see the whole hand says „не съм я гледал цялата“ instead of vouching.
  9. After a Santase match the **host** starts the next one („Нова игра“); the loser leads.
  10. The rules-book says plainly that the dealer's addon knows the deck of its own deals.
- **Step scan:** every task has failing tests with exact values (deck vectors in Task 3 were computed with the repository's `Sha256`/`Deck`), an expected failure, an implement step with files, signatures and pinned values, both run commands, and a commit with exact paths. No rule is left to "handle as appropriate"; `E.leave` of the test engine is deliberately specified for a trick boundary only and used only there.
- **Type and name consistency:** `need = "deck" | "dice"` in Tasks 1, 2, 4, 7; hooks `need`, `table`, `snap`, `adopted(s, prev, m)` in the contract, Task 2 and Tasks 4–6; round record `s.fair` with `h, d, p, dealer, commits, stage, seed, seeds, deck, sent, pub, priv, base, log, out` and stages `commit, seed, dealt, done` in Tasks 4–6 and 10; `s.fairN`, `s.fairLast`, `s.fairSeen` in Tasks 4, 5, 6, 10; messages `SED{tid, h, s}`, `PRV{tid, h, cards}`, `PRQ{tid, h}`, `SNP.fr = {h, d, p, c, st, n}` in the table, Task 2 (`WHISPERED`) and Tasks 4, 6; verdicts `ok, bad, unseen, void` and reasons `seeds, commit, deal, dealt, play, noreveal` in Tasks 3, 5, 6, 10 and the locale keys `fair.v.*`, `fair.why.*`, `fair.tip.*`; `Session.startable`, `Session:gameOver`, `Session:snapshotFor`, `Session:armAuto` in Tasks 2, 5, 7, 10; `ns.Cards` (`card`, `fan`, `layout`, `rank`, `red`, `suitName`) in Tasks 9, 11, 12; engine id `santase` and locale prefix `santase.` throughout.
- **Review Focus:** each of the five has named tests in Tasks 2, 4, 5 and 6.
- **Proportion:** the protocol is given as 26 numbered rules because the tests alone do not determine the order of checks or who sends what; the pure functions, the widget and the view are signatures, pinned values and tests. B1 (Tasks 1–6) is complete and testable without any UI; B2 adds no protocol rule.
