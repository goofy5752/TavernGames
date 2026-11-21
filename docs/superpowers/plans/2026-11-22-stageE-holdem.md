# Tavern Games Stage E (Тексас Холдем) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Two to six guild members (or one member and up to five bots) play Тексас Холдем for chips at a host-started cash table: No Limit or Pot Limit, blinds and starting stack chosen at open time, sitting and standing between hands, a newcomer dealt in from the next hand, a leaver folded, side pots, a showdown that shows only the hands that went to it, the fair deal of stage B with up to six seeds a hand **verified when the table closes**, an oval table with six seats (nine seats wait for a later stage that cuts the message budget, see decision 9), bet buttons that follow the engine's limits, a hand log line, a per-hand `"hand"` event for the later ledger, and the rules-book topic „Тексас Холдем“.

**Architecture:** The engine (`engines/holdem.lua`, merged and reviewed) keeps every rule and gains what the table needs: who shuffles and who deals (`E.players`, `E.dealer` = the button), a marker that a street or the showdown needs faces the host does not have (`need = "faces"`), `void`, sitting a silent seat out (`away`/`back`), and `close`. The deal reuses stage B's `core/Deal.lua` round (commit, seeds to the dealer, private faces, `DealKeep`) with four switches for a *sealed* engine: participants and dealer from the engine, all commits in one event, the dealer supplies each street and the showdown, and the hand is **not revealed** when it ends. Instead every player has one *table key* per sitting; its seed for hand `h` is derived from the key and the hand id, so one key opens all of its commits. A new extension `cash` (`core/Cash.lua`) runs the table (join on sit, the dealer's steps, sitting out, the close, the `"hand"` event) and `core/Book.lua` keeps the book: one small record a hand (participants, commits, the faces I saw), the published keys, and the check that runs when keys come out — a leaver's key at once, everybody's at the close. No rule of Hold'em needs a hidden card to be checked, so the check is: the keys open the commits, and every face I saw is the face of the deck those seeds give. The UI is a pure model (`ui/games/HoldemModel.lua`) and a view on a larger table frame (`ui/games/HoldemView.lua`). Two halves: **E1** (Tasks 0–5) makes Hold'em playable and proven in the simulator; **E2** (Tasks 6–11) adds the table, the rules book and the in-game check list.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), the stage 1 Ace3 subset, `bash t.sh`, `tests/helpers/sim.lua`, `tests/helpers/wow.lua`, Python 3 standard library for `tools/gen_textures.py`.

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.5 without the money: no buy-in, no rebuy, no ledger; 5.3а; 6.2; 6.3 and its „Изключение за Холдем“; section 8). Roadmap: `docs/superpowers/plans/2026-11-20-games-roadmap.md` (Stage E). Stage D plan (format, the end state this plan builds on): `docs/superpowers/plans/2026-11-22-stageD-tabla.md`. Engine contract: `docs/superpowers/notes/engine-contract.md` (Addenda 1–6; Task 11 adds Addendum 7). Rulings: `.superpowers/sdd/engines-parallel/progress.md` (H1–H5), `.superpowers/sdd/2026-11-21-stageB-fairness-santase/progress.md` (PB1–PB8, FW-a), `.superpowers/sdd/2026-11-22-stageC-belot/progress.md` (C-F3 `DealKeep`). Look: `docs/mockups/05-holdem-cash.html` (the table only; its money panels are the stakes stage), `docs/mockups/07-wow-authentic.html` variant 1.

**Stage E starts on `feature/games` after stage D's final review wave is merged.** Line numbers quoted below are from `2c49161` and may have moved; names are binding. It consumes: `ns.Fair`, `ns.Deck`, `ns.Deal` / `ns.Ext.fair` / `ns.DealKeep`, the session hooks, `Session:armAuto`, `engine.again`, `E.bot`, `ns.Cards`, `W.GoldButton`/`W.GhostButton`, `v.fairLine`, `v.startButton`, the ring hook of `ui/TableFrame.lua`, `ns.Dice.status` in `renderFair` (stage D), `Games.PLAYABLE`.

## Global Constraints

Everything in the stage 1, A, B, C and D constraint files still holds (`.superpowers/sdd/2026-11-22-stageD-tabla/global-constraints.md` and the ones it names). Added for stage E:

- Protocol stays `v=1`. Stage E adds **no message type** and **one field**, `SNP.fr.k`. Everything else travels inside `ACT`/`EV` (table below).
- **Chips only.** No gold, no buy-in, no rebuy, no ledger, no `"result"` (`E.result` stays nil). A seat with 0 chips sits out; standing up and sitting down again gives a fresh starting stack (ruling H4: accepted for fun play). `state.last` and the `"hand"` event keep who put how much into which pot, so the stakes stage needs no engine change.
- Hold'em's rules are the rule table at the top of `engines/holdem.lua`. Stage E changes none of rules 1–13; rule 14 changes only in `E.over` (true once the game was closed) and the table gains rules 15–19 (Task 1). Every existing test of `tests/engines/holdem_test.lua` stays as it is.
- **The sealed deal (binding).** An engine with `sealed = true`:
  1. *Who.* The participants of a round are `E.players(state)` (the hand's seats that are still seated and not away, ascending), not the occupied seats; the dealer is `E.dealer(state)`: the button, or the next participant after it when the button's seat has left the hand.
  2. *Key and seeds.* Every seated client has one table key per sitting: `Fair.seed(random)`, kept in `env.db.bookKeep = {tid, me, key, g}` where `g` is the seq of the running game's `start` event (it survives a `/reload` and a relog; it is in no message before it is published and never in the trace). `Book.key` takes a kept key only for the running game (`g` equal to the book's) and never one that is in the book's published keys, so "one key per sitting" does not span games. Its seed for hand `h` is `Fair.handSeed(key, handId)` = the first `2 × SEED_BYTES` hex characters of `SHA256(key .. "/" .. handId)`. The commit of a hand is the commit of that seed, as in stage B.
  3. *One commit event.* The host collects the commits (`fair.pend`) and publishes them together as `{k="fair", op="commits", h, c}` once every participant's is in. While a sealed round is in stage `commit` the line under the felt says `fair.shuffle` for everyone.
  4. *The dealer deals every street.* On a view `E.system` returns `{k="street", need="faces"}` / `{k="showdown", need="faces"}`. The dealer asks the host for the step with the faces (`ACT {k="book", op="step"}`), `STREET_DELAY` after it is due and again every `FAIR_ASK_GAP` while the table stands there; the host plays it as the engine's own event when it is the step the engine waits for and publishes only faces a watcher may then see (`allPublic`). One event a street; a folded or unshown hand is in no event.
  5. *No reveal.* When the hand ends (`not E.inHand(state)`) every client writes its record `{p, c, f, who}` (participants, the commits it holds, every face its state knows plus its private ones, the names at the open) into its book and closes the round `"sealed"`. No seed is revealed, no reveal is waited for. **A voided hand writes its record too** (the public faces the dealer put on the board before the void, my own private faces): the line of `core/Deal.lua` that closes a voided round of a sealed engine calls `ns.Book.seal(s)` first, so a void is checked at the close like a sealed hand. A round with a foul against it, or private faces the engine refused, closes `"bad"` as in stage B.
  6. *Keys.* A player who presses „Стани“ sends its key first; the host publishes it at once (`{k="book", op="keys", m = {[seat] = key}}`). While the game is over, a stand first makes the host publish `book.wait` (the leaver's key included) in one event before the stand is played, so the final event never lacks a key of a seat that has left. When the game is closed every seated client sends its key and the host publishes them in one event as soon as every seated seat's is in, or `BOOK_WAIT = 30` s after the close event at the latest with what it has. A key that arrives after that goes out in a further keys event and a final book takes it (its hands leave `open`, `"book"` is emitted again); a member that sees a final keys event without the key it sent sends it once more. When the last player but one stands up, the host publishes its own key before the table stops. Published keys are part of the snapshot (`SNP.fr.k`, the newest `BOOK_KEYS = 24`).
  7. *The check.* A hand is checked as soon as, for every participant, a key published for that seat at or after the hand (`key.q >= h`) gives a seed whose commit is the one held. Then `deck = Fair.deck(E.DECK, seeds, handId)` and every recorded face must be the deck's: `"ok"`, else `"bad"` (`"deal"`, a `"fair"` event). `BOOK_BATCH = 2` hands a tick of 0.1 s. When the book closes (the keys event of a closed game, or `abort`), the hands still without a key are `open` and the players whose key is missing are named. The event `"book"` carries the totals.
  8. *What this leaves (accepted).* A dealer who stands up mid-hand voids the hand and leaves with every chip it put in (spec 6.3; stacks are free, PE8), unlike any other leaver; the void is pinned by a Task 3 test and its record is checked (rule 5). The dealer's client holds the deck of its hand, as in stage B. A player who vanishes without leaving its key (a crash, three minutes offline) leaves the hands it played **unverified, in amber and by name, not red**: nobody can tell a crash from a dodge. A hand becomes readable for everyone once *all* its players have left, while the table may still run (the spec has the host keep leavers' seeds until the close; published at once they survive a host crash and reveal nothing while one participant still holds its key). A player who stands up gets no verdict unless it stays to watch.
- **Silence.** A shuffle not dealt after `FAIR_WAIT`: in stage `commit` the participants whose commit is missing are sat out (`{k="away", seat}`, their blind stays as dead money) and the round opens again without them; in stage `seed` (every commit in, the dealer silent or a seed lost) the **dealer** is sat out (`{k="away", seat = fair.d}`) and the deal passes to the next participant, so the same dealer is never reopened forever. A street or showdown that is `FAIR_WAIT` overdue: the host voids the hand (every chip back) and sits the dealer out. A client that sees its own seat away sends `{k="back"}` (it is here) and is dealt in from the next hand. After `OFFLINE_STAND_SECONDS = 180` the seat is stood up as everywhere.
- **The clock.** Timeout = check if possible, else fold (`E.auto`, public data only, `E.publicAuto = true`). My own client plays it at my deadline (stage B). For such an engine the host also plays it for another seat `AUTO_GRACE = 7` s after the deadline (this amends PB5 for Hold'em only: the timeout needs no hidden card, so the table need not wait three minutes for an offline player). A member does not count such an event as forged when **its own** deadline has passed (it keeps `s.turnAt`, its own `env.now()` when it applied the event that put its seat on turn, and requires `now >= turnAt + the table's turn time`, ignoring the `left` the host sent) and the action is `E.auto`'s; any other move for its seat that it did not send still is, and so is an `away` of its own seat while its round is `dealt`, or in stage `seed` unless it is that round's dealer (a fold by another name).
- **The close.** The host's „Приключи“ plays `{k="close"}`: the running hand is played out, then `E.over`. The table stays; „Нова игра“ starts a new game with fresh stacks, new keys and a new book. It is refused with code `"book"` (`Session:canStart`) while the host's book of the closed game is not `published`; on every client the `start` event first runs the old book to its end synchronously (`Book.close` and every check, `"book"` emitted), and `adopted` with a new game does the same, before the book is dropped.
- **Volume (design limit, measured in the simulator with the real wire format, binding: PE11's fallback).** Hold'em is a **six-seat** table (`E.maxSeats = 6`) with **at most one watcher** (`E.watchers = 1`), and the turn clock `Session:left()` is sent in whole seconds (rounded up), because the real clock `GetTime()` is a float that AceSerializer sends as about 19 extra bytes an event. One event is then at most 6 whispers of about 145 bytes (packed, plus ChatThrottleLib's 40). A full ring played to the showdown with every seat in every street is 32 events: at most 200 host whispers and 31 000 bytes (expected 192 and about 29 KB; Task 5 pins the numbers measured at its first green run, never larger than these caps), about 36 s of ChatThrottleLib's 800 bytes a second; an ordinary hand is about 15 KB. PE11 reads: at most 25 KB a hand holds with no watcher, each watcher adds about 4.7 KB. Nine seats and three watchers (about 73 KB) are arithmetically out of reach under `v=1`, one `EV` a member and no new message type, so **nine seats wait for a later message-budget stage** (decision 9). The largest message is measured with distinct commits (six commits are about 260 bytes packed, two addon message parts): Task 5 pins it.
- **Files.** `core/Session.lua` stays at 539 lines (below 540): exactly **four** edits, each inside its own line or line pair, no line added (the `TIMERS` list, the watcher cap, the turn timer, and `Session:left()`: the `return` of its line 103 becomes `return math.ceil(math.max(0, self.deadline - self.client.env.now()))`; Tasks 2, 3, 5). `core/Deal.lua` ends the stage at or below 700 lines (Task 0 moves the fairness line out first), `core/DealHooks.lua` below 400, `core/Book.lua` below 260, `core/Cash.lua` below 280, `ui/TableFrame.lua` below 600 (Task 0 moves its two panels and the fairness-line code out). `tests/toc_test.lua` checks these (Task 0 the first four and the frame, Task 2 adds Book and Cash).
- **Table (felt 732 × 440, frame 760 × 532).** Seat `k = (seat − me) % 6` (a watcher: `me = 1`), clockwise from me at the bottom: the next seat is at my left. Offsets from the felt's `TOPLEFT`:

  | k | plate (150 wide) | cards | bet (centre) |
  |---|---|---|---|
  | 0 | 291, −388 | 323, −322 (two 40 × 58, 46 apart) | 366, −300 |
  | 1 | 10, −300 | 166, −296 | 250, −272 |
  | 2 | 10, −80 | 166, −76 | 250, −134 |
  | 3 | 291, −10 | 341, −42 | 366, −110 |
  | 4 | 572, −80 | 516, −76 | 482, −134 |
  | 5 | 572, −300 | 516, −296 | 482, −272 |

  The frame is 760 × 532 because `TableFrame.build` gives `areaW = W − 2 · (EDGE + 2)` and `areaH = H − 92`, i.e. 732 × 440. The other seats' cards are `Cards.card(parent, 0.6)` (24 × 34.8), 26 apart. The oval is 456 × 236 at `(138, −97)`; the board is five cards 40 × 58, 46 apart, from `(254, −176)`; the pot line is centred on `(366, −156)`, the text line on `(366, −250)`. The dealer disc (18 × 18) is centred on `(plate.x + 138, plate.y)`.
- Textures are generated by `tools/gen_textures.py`, appended to `TEXTURES` so every existing file stays byte-identical.
- Commits are local only, never pushed; every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A folded hand leaks before the close.** Pinned by Task 2 (`three players to a showdown: one event a street; the folded kings stay in the dealer's whisper`, `heads-up: four events to the deal, each player gets only its own two cards`), Task 8 (`a folded seat has no cards; an unshown hand lies face down`) and Task 9 (`the view draws a face only where the model has one`).
2. **Side-pot chip conservation across leavers.** Pinned by Task 1 (`void gives every chip back, shows nothing and lets a leaver go with his stack`) and Task 3 (`a player who stands mid-hand is folded and his chips stay in the pots; nothing is lost`).
3. **A host crash before the close.** Pinned by Task 4 (`the host vanishes before the close: the table goes on under the next host, his hands stay open and name him`, `the host is back in time: his key is still his and every hand is checked`).
4. **A newcomer sitting mid-hand.** Pinned by Task 2 (`a newcomer sits mid-hand: chips at once, no cards, dealt in from the next hand`) and Task 8 (`a newcomer waits for the next hand`).
5. **The Pot Limit cap in the UI against the engine.** Pinned by Task 8 (`Pot Limit: the biggest raise the buttons offer is the engine's cap; no „Ва банк“ above it`, `the buttons agree with the engine on random states`) and Task 9 (`„Пот“ and „+“ never leave the engine's range; the raise button sends what it shows`).

Also pinned: a dealer who is gone (Task 3), a timeout that is and is not forged (Task 3), a card that was not the deck's (Task 4), the message budget of a full table (Task 5), a bot table (Task 5).

---

## File Structure

```
engines/holdem.lua           ext, sealed, players, dealer, need "faces", void, away/back, close, bot (Task 1)
core/DealLine.lua            NEW: Deal.status, Deal.claim, Deal.alarm moved out of Deal.lua (Task 0)
core/Deal.lua                players, inHand, one commits event, no reveal for a sealed engine, hook lapsed (Tasks 2, 3)
core/DealHooks.lua           op "commits", the stand guard, fits for an engine with players, fr.k (Tasks 2, 4)
core/Fair.lua                + Fair.handSeed (Task 2)
core/Book.lua                NEW ns.Book: key, seeds, records (Task 2); keys, check, close, status, tip (Task 4)
core/Cash.lua                NEW ns.Cash, ns.Ext.cash: the table (Tasks 2, 3), the keys and the close (Task 4)
core/Session.lua             four in-line edits (Tasks 2, 3, 5, 5)
core/Member.lua              + Member.timedOut (Task 3)
core/Client.lua              stand calls the hook `leaving` (Task 4)
core/Const.lua               AUTO_GRACE, BOOK_WAIT, BOOK_KEYS, BOOK_BATCH
core/Games.lua               PLAYABLE.holdem
core/Bots.lua                botFill, Bots:fill (Task 5)
core/HallLayout.lua          ring for six seats (Task 6)
core/Help.lua                topic "holdem", the fair topic's sealed paragraph, "soon"
wow/Slash.lua                /tavern bots fill [n]
tools/gen_textures.py        + oval, chip;  media/oval.tga  media/chip.tga  NEW
ui/Theme.lua                 the two textures
ui/TablePanels.lua           NEW: the „Покани“ list, the stand question and the fairness line (renderFair, fairTooltip), moved out of TableFrame.lua (Task 0); the book branch (Task 6)
ui/TableFrame.lua            a view's own frame size (Task 6)
ui/Widgets.lua  ui/NewTableDialog.lua   option values by name (Task 6)
ui/games/HoldemModel.lua     NEW ns.HoldemModel (pure)
ui/games/HoldemView.lua      NEW
locale/bg.lua  locale/en.lua
tests/toc_test.lua, tests/engines/holdem_test.lua, tests/core/holdem_table_test.lua NEW,
tests/core/{fair,games,member,bots,hall_layout,locale_help}_test.lua,
tests/ui/{theme,hall,table,book}_test.lua, tests/ui/{holdem_model,holdem}_test.lua NEW, tests/wow/slash_test.lua
docs/superpowers/notes/2026-11-stageE-ingame-checks.md  NEW
```

TOC: `core/DealLine.lua`, `core/Book.lua`, `core/Cash.lua` in that order right after `core/DealKeep.lua` (before `core/Dice.lua`); `ui/TablePanels.lua` right after `ui/TableFrame.lua`; `ui/games/HoldemModel.lua`, then `ui/games/HoldemView.lua`, after `ui/games/TablaView.lua`.

### Shared contracts (additions to stages 1, A, B, C and D)

**Engine, optional:** `E.players(state) -> {seat, …}` ascending (who shuffles); `E.inHand(state) -> bool` (the fair layer's "hand over" is its negation); `E.sealed` (no reveal a hand; the book); `E.publicAuto` (the automatic move needs no hidden card: the host may play it for any seat after `AUTO_GRACE`); `E.watchers` (a cap below `MAX_WATCHERS`); `E.botFill` (a bot host invites idle bots up to this many seats, also while live); a system action `{k, need = "faces"}` (the dealer supplies it).

**Extension `cash`** (`engine.ext = {"fair", "cash"}`, in that order: `fair`'s hooks run first). New hooks, under `pcall` like the others: `lapsed(s)` (host: a shuffle was not dealt in `FAIR_WAIT`, called before it is opened again), `leaving(s)` (my client is about to stand up).

**Protocol additions.** One field: `SNP.fr.k`. The shapes inside `ACT`/`EV`:

| where | shape | meaning |
|---|---|---|
| `EV` seat 0 | `{k="fair", op="commits", h, c = {[seat] = commit}}` | every commit of a sealed round, in one event (instead of one `commit` a seat) |
| `ACT` | `{k="book", op="step", h, a = {k = "street" \| "showdown", cards = {[i] = face}}}` | the dealer supplies the step the engine waits for; the host plays `a` at seat 0 |
| `ACT` | `{k="book", op="key", m}` | my table key, 32 hex: before I stand up, and when the game is closed |
| `EV` seat 0 | `{k="book", op="keys", m = {[seat] = key}}` | published keys: a leaver's at once, everybody's at the close (may be empty) |
| `EV` seat 0 | `{k="close"}`, `{k="away", seat}`, `{k="void"}` | the host ends the game after this hand; a silent seat sits out; the hand is annulled |
| `ACT` → `EV` seat n | `{k="back"}` | my seat is dealt in again |
| `ACT` → `EV` seat n | `{k="fold"}`, `{k="check"}`, `{k="call"}`, `{k="bet", to}`, `{k="raise", to}`, `{k="allin"}` | a move; `to` = my whole bet on this street |
| `SNP.fr.k` | `{{seat, q, key}, …}` or absent | the keys published in the running book, oldest first, at most `BOOK_KEYS` |

**Session fields (sealed games):** `s.book = {key, g, rec = {[h] = {p, c, f, who, tried}}, open = {h, …}, keys = {{seat, q, m}, …}, seen = {ok, bad, open}, n, given, wait, sent, out, published, closed, final, missing, forged}` (`g` = the seq of the game's `start` event); `s.turnAt` (my own `env.now()` when I applied the event that put my seat on turn); `s.handSeen`, `s.handNames` (the seats when the last hand began); `fair.pend` (host: commits not yet published), `fair.who`; timers `s.stepTimer`, `s.keysTimer`, `s.bookTimer`.

**Client events:** `"hand"`: `{tid, game, opt, n, last, chips = {[seat] = chips after the hand}, names, at}` once a hand on every client that saw it end (`last` = a copy of `state.last`: `hand, contrib, won, pots = {{amount, eligible, winners}}, shown, cat, left`, or `void = true`). `"book"`: `{tid, game, hands, ok, bad, open, missing = {name, …}, at}` when my book closes. `"fair"` also carries `verdict = "sealed"` for every hand put into the book and `"bad"`, `why = "deal"` for a hand that fails the check.

**Test conventions:** as in stages B–D. `N = {"Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров", "Нади Колева", "Гошо Илиев", "Ели Маринова", "Дидо Ангелов", "Зара Попова"}`, `W = "Гледач Гледачев"`; in the UI tests `A, B, C = N[1], N[2], N[3]`. `SEED = ("ff"):rep(16)` (shape-only uses, `tests/core/fair_test.lua`). **Every table client has its own random**, so keys differ by seat and a key used under the wrong seat, a seed passed out of seat order or a key regenerated after a relog is caught: the table test file defines `local function rnd(i) return function(lo, hi) return (lo + i) % (hi + 1) end end` and `local function KEY(i) return ("%02x"):format(i):rep(16) end`; `tableN` sets `sim.envs[N[i]].random = rnd(i)` right after `sim:add`, a client added later sets it before it sits, and a relogged client's env gets `rnd(7)` before `sim:relog` (so a regenerated key would differ from `KEY(i)`). The key of the client at seat `i` is `KEY(i)` (`Fair.seed` draws a byte at a time with `random(0, 255)`; if it draws otherwise, `rnd` is adapted so that the keys differ by seat) and its seed of hand `h` is `Fair.handSeed(KEY(i), tid .. "/" .. h)`. The pinned hex values and the deck-dependent literals of Tasks 2 to 5 (faces, winners, chips after a showdown, `seq` after a showdown) were produced by the prototype under one shared key and are **re-derived once under `KEY(i)`**: run the test, check by hand that the engine's rules explain the new value, paste it; the structure of every assertion (who, which events, how many) stays. A member's turn clock starts one simulated second after the host's (the event is delivered on the next drain). `mk`, `start`, `acts`, `sys`, `checkdown`, `chips`, `rejects` are the helpers at the top of `tests/engines/holdem_test.lua`. Every commit step's message is followed by the trailer line of the Global Constraints.

---

# Part E1 — Hold'em at the table, proven in the simulator

### Task 0: Room in the two big files

**Files:**
- Create: `core/DealLine.lua`, `ui/TablePanels.lua`; Modify: `core/Deal.lua`, `ui/TableFrame.lua`, `TavernGames.toc`; Test: `tests/toc_test.lua`

**Interfaces:**
- Produces (moves only, no behaviour changes, every existing test stays as it is):
  - `core/DealLine.lua`: `Deal.status`, `Deal.claim`, `Deal.alarm` with their comments, verbatim, defined on `ns.Deal` (`local Deal = ns.Deal`, `local contains = ns.Util.contains`). Deal.lua's header gets one line saying where the fairness line lives.
  - `ui/TablePanels.lua` (loaded after `ui/TableFrame.lua`): `PICK_W`, `PICK_ROWS`, `PICK_ROW_H`, `pickerRow`, `renderPicker`, `buildPicker`, `buildConfirm` and `TableFrame.togglePicker`, verbatim; **and the fairness-line code** (`known`, `renderFair`, `fairTooltip`, with stage D Task 7's dice branch and its `L("dice.why." .. arg)` mapping, about 55 lines), verbatim. It sets `TableFrame.panels = { build = function(v, f) buildPicker(v, f); buildConfirm(v, f) end, renderPicker = renderPicker, renderFair = renderFair, fairTooltip = fairTooltip }`. `TableFrame.build` calls `TableFrame.panels.build(v, f)` where it called the two builders, `TableFrame.render` calls `TableFrame.panels.renderPicker(v, client, s)` and `TableFrame.panels.renderFair(...)`, the line's tooltip handler calls `TableFrame.panels.fairTooltip(...)`. `TableFrame.invite`, `v.picker`, `v.confirm`, `v.fairLine` keep their names. Why this much: after stage D Task 7 `ui/TableFrame.lua` is about 650 lines; the panels take about 95 and the fairness-line code about 55 out (about 500 left), so that Task 6's frame size and book branch do not blow the 600 cap.

- [ ] **Step 1: Write the failing test** (`tests/toc_test.lua`, a new `it`):

```lua
it("the big files keep their limits", function()
  local function lines(path) local n = 0; for _ in io.lines(path) do n = n + 1 end; return n end
  ok(lines("core/Session.lua") < 540, "Session.lua"); ok(lines("core/Deal.lua") <= 700, "Deal.lua " .. lines("core/Deal.lua"))
  ok(lines("core/DealHooks.lua") < 400, "DealHooks.lua"); ok(lines("ui/TableFrame.lua") < 600, "TableFrame.lua " .. lines("ui/TableFrame.lua"))
end)
```

- [ ] **Step 2: Run `bash t.sh tests/toc_test.lua`.** Expected: FAIL (`Deal.lua 725`).
- [ ] **Step 3: Move the code**; add the two TOC lines.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass, the count of tests grown by one. `wc -l core/Deal.lua ui/TableFrame.lua`: about 680 and 500 (the 650 of stage D Task 7, less the panels and the fairness line).
- [ ] **Step 5: Commit.** `git add core/DealLine.lua core/Deal.lua ui/TablePanels.lua ui/TableFrame.lua TavernGames.toc tests/toc_test.lua` — `refactor: the fairness line and the table's panels move to files of their own`

### Task 1: The engine: what the table needs

**Files:**
- Modify: `engines/holdem.lua`, `tests/engines/holdem_test.lua`

**Interfaces:**
- Consumes: the file-locals `inHand`, `nextSeat`, `progress`, `finish`, `playingFn`, `streetIdx`, `showdownIdx`, `facesOf`, `canRaise`, `raiseCap`.
- Produces:
  - Fields: `E.ext = {"fair", "cash"}`, `E.again = true`, `E.sealed = true`, `E.publicAuto = true`, `E.watchers = 1`, `E.botFill = 6`; and `E.maxSeats` goes from 9 to **6** (the one existing assertion of it, `holdem_test.lua` line 122, reads `{ "holdem", 2, 6, "host" }`; PE11's fallback, see Global "Volume"). The engine still plays any seat count its `mk` is given.
  - `E.inHand(s)` = phase `deal`, `bet`, `street` or `showdown`. `E.players(s)` = the seats of `s.order` whose chair is occupied, not `leaving` and not `away`, ascending (`{}` before the first hand). `E.dealer(s)` = nil without a button; the button when it is one of those seats (`s.p[i]` exists, seated, not leaving, not away); else the next such seat clockwise after it.
  - `E.system`: in phase `street` / `showdown`, when a face of `streetIdx` / `showdownIdx` is unknown: `{k = <phase>, need = "faces"}, 0`; with every face known as before (`cards`, `STREET_DELAY`).
  - Seat 0 `{k="join", seat}` on a chair that is `leaving` (a player stood up mid-hand): accepted. The engine marks `s.p[seat].gone = true` at once (so `E.view` and `E.hidden` stop showing the leaver's cards and the newcomer owes no face), keeps the leaver's chips for `last.left[seat]`, and `finish` seats the fresh stack at that chair instead of clearing it. Header rule 2 says so.
  - Seat 0 `{k="void"}`: only while `inHand`, else `"phase"`. Every seat of `s.order` still in its chair gets `s.p[i].total` back; `s.shown = {}`; `s.last = {hand = s.hand, void = true, contrib = {}, won = {}, pots = {}, shown = {}, cat = {}, left = {}}`; then the end of `finish` (a new file-local `settle(s)`: leavers go with `last.left[i] = chips`, `out` for 0 chips, phase `"done"`, or `"closed"` when `s.closing`). `s.hand` and the button stay, so the next `hand` moves the button on.
  - Seat 0 `{k="away", seat}`: an occupied seat that is not away (`"seat"` otherwise) gets `away = true`; in a hand, not yet folded, it is folded as `leave` folds it (its chips stay in the pot, `progress`), but it keeps its chair. An away seat is not `playing`. Seat n `{k="back"}`: in any phase, only for a seat that is away (`"seat"`): `away = false`; handled before the turn check.
  - Seat 0 `{k="close"}`: `"phase"` when `s.closing`; sets `s.closing = true`; outside a hand the phase becomes `"closed"` at once. In `"closed"`: `E.over(s)` is true, `E.system` nil, `hand` is `"phase"`, `join` is `"phase"` (also while `closing`).
  - `E.bot(s, seat, random) -> action | nil` on a view: nil off turn or without both own faces. `r = random(1, 100)`; `pot` = the sum of `p.total`; `toCall = s.bet − p.bet`. Level preflop from the two ranks `hi >= lo` (2–14): a pair scores `40 + 2 × hi`, else `hi + lo`, `+3` suited, `+2` when `hi − lo <= 1`; level 3 from 26, level 2 from 18, else 1. Postflop from `H.best` of my cards and the board: category `>= 3` level 3, a pair level 2, else 1. With a `bet`/`raise` entry `a` in `E.legal` and `r <= 40` (level 3), `<= 8` (level 2) or `<= 3` (level 1): `{k = a.k, to = max(a.to, min(a.max, s.bet + floor(pot / 2)))}`. Else nothing to call: `check`. Else `call` when level 3, or level 2 and `toCall <= max(bb, floor(pot / 2))`, or level 1 and `toCall <= bb` and `r <= 50`. Else `fold`.
  - Header: rules 15 `void`, 16 `away`/`back`, 17 `close` (and rule 14: the game is over once closed), 18 who shuffles and deals, 19 `need = "faces"`; the handshake block says the dealer supplies street and showdown; rule 2 says a busted seat may stand and sit again for a fresh stack and that a `join` on a chair that is `leaving` is accepted (the leaver's hand is gone at once); rule 7 states that the cap counts chips actually posted.

- [ ] **Step 1: Write the failing tests** (a new `describe("holdem at the table")` at the end of the file).

```lua
describe("holdem at the table", function()
  it("declares what the table needs", function()
    eq(E.ext, { "fair", "cash" }); eq({ E.again, E.sealed, E.publicAuto, E.watchers, E.botFill, E.maxSeats }, { true, true, true, 1, 6, 6 })
    eq({ E.dealer(mk({ 1, 2 })), E.inHand(mk({ 1, 2 })), E.players(mk({ 1, 2 })) }, { nil, false, {} })
  end)
  it("who shuffles and who deals: the hand's seats that are still here; the button, else the next of them", function()
    local s = mk({ 2, 4, 6 }, { first = 4 }); ok(E.apply(s, 0, { k = "hand" }))     -- six seats at most
    eq({ s.button, s.order, E.players(s), E.dealer(s), E.inHand(s) }, { 4, { 6, 2, 4 }, { 2, 4, 6 }, 4, true })
    ok(E.apply(s, 0, { k = "join", seat = 3 })); eq(E.players(s), { 2, 4, 6 })
    E.leave(s, 4); eq({ E.players(s), E.dealer(s), s.phase }, { { 2, 6 }, 6, "deal" })
    ok(E.apply(s, 0, { k = "away", seat = 6 })); eq({ E.players(s), s.phase, E.inHand(s) }, { { 2 }, "done", false })
  end)
  it("a chair vacated mid-hand takes a newcomer at once: the leaver's cards are gone, its chips go with it, the stack is seated at the end of the hand", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "7C 2D" }, "3H 8S 9C JD 4C")
    E.leave(s, 3); eq({ s.seats[3].leaving, s.p[3].gone }, { true, nil })
    ok(E.apply(s, 0, { k = "join", seat = 3 })); eq({ s.p[3].gone, s.seats[3].leaving, s.seats[3].chips, E.hidden(s, 3) }, { true, true, 990, {} })
    eq(E.view(s, 3).deck, {})                                                        -- no face of the leaver is shown to the newcomer
    acts(s, { { 1, "fold" } }); eq({ s.phase, chips(s), s.last.left }, { "done", { 1000, 1010, 1000 }, { [3] = 990 } })   -- seat 3 now holds a fresh stack
    ok(E.apply(s, 0, { k = "hand" })); eq(E.players(s), { 1, 2, 3 })
  end)
  it("a street and the showdown need their faces: asked from whoever holds the deck", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "7C 2D" }, "3H 8S 9C JD 4C")
    acts(s, { { 1, "call" }, { 2, "call" }, { 3, "check" } })
    local v = E.view(s, 2)
    eq({ E.system(s) }, { { k = "street", cards = { [8] = "3H", [9] = "8S", [10] = "9C" } }, E.STREET_DELAY })
    eq({ E.system(v) }, { { k = "street", need = "faces" }, 0 }); eq({ E.apply(v, 0, { k = "street", need = "faces" }) }, { nil, "need" })
    sys(s); checkdown(s); eq(s.last.won, { [1] = 30 })
    local t = mk({ 1, 2, 3 }); start(t, { [1] = "AS AD", [2] = "KS KD", [3] = "7C 2D" }, "3H 8S 9C JD 4C")
    acts(t, { { 1, "call" }, { 2, "call" }, { 3, "check" } }); sys(t)
    while t.phase ~= "showdown" do if t.phase == "bet" then acts(t, { { t.turn, "check" } }) else sys(t) end end
    eq({ E.system(E.view(t, 0)) }, { { k = "showdown", need = "faces" }, 0 }); eq(E.system(t).k, "showdown")
  end)
  it("void gives every chip back, shows nothing and lets a leaver go with his stack", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "7C 2D" }, "3H 8S 9C JD 4C")
    acts(s, { { 1, "raise", 40 }, { 2, "call" } }); E.leave(s, 3); eq(chips(s), { 960, 960, 990 })
    ok(E.apply(s, 0, { k = "void" }))
    eq({ s.phase, s.turn, s.hand, s.button, s.shown }, { "done", nil, 1, 1, {} }); eq(chips(s), { 1000, 1000 })
    eq(s.last, { hand = 1, void = true, contrib = {}, won = {}, pots = {}, shown = {}, cat = {}, left = { [3] = 1000 } })
    eq(E.view(s, 0).deck, {}); rejects(s, 0, { k = "void" }, "phase"); rejects(mk({ 1, 2 }), 0, { k = "void" }, "phase")
    ok(E.apply(s, 0, { k = "hand" })); eq({ s.button, s.hand }, { 2, 2 })                 -- the deal has passed on
    local d = mk({ 1, 2 }); ok(E.apply(d, 0, { k = "hand" })); ok(E.apply(d, 0, { k = "void" })); eq(chips(d), { 1000, 1000 })
  end)
  it("away folds the seat and deals it out until it is back", function()
    local s = mk({ 1, 2, 3 }); start(s); rejects(s, 2, { k = "back" }, "seat"); rejects(s, 0, { k = "away", seat = 4 }, "seat")
    ok(E.apply(s, 0, { k = "away", seat = 1 })); eq({ s.p[1].folded, s.turn, s.seats[1].away, s.seats[1].leaving }, { true, 2, true, false })
    rejects(s, 0, { k = "away", seat = 1 }, "seat"); acts(s, { { 2, "fold" } }); eq({ s.phase, chips(s) }, { "done", { 1000, 995, 1005 } })
    ok(E.apply(s, 0, { k = "hand" })); eq({ s.order, s.button, E.players(s) }, { { 3, 2 }, 2, { 2, 3 } })
    ok(E.apply(s, 1, { k = "back" })); eq(s.seats[1].away, false); rejects(s, 1, { k = "back" }, "seat")
    ok(E.apply(s, 0, { k = "void" })); ok(E.apply(s, 0, { k = "hand" })); eq(s.order, { 1, 2, 3 })
    local one = mk({ 1, 2 }); ok(E.apply(one, 0, { k = "away", seat = 2 })); eq(E.system(one), nil)
  end)
  it("close ends the game after the running hand; nothing is dealt after it", function()
    local s = mk({ 1, 2 }); ok(E.apply(s, 0, { k = "close" })); eq({ s.phase, E.over(s), E.system(s) }, { "closed", true, nil })
    rejects(s, 0, { k = "close" }, "phase"); rejects(s, 0, { k = "hand" }, "phase"); rejects(s, 0, { k = "join", seat = 4 }, "phase")
    s = mk({ 1, 2, 3 }); start(s); ok(E.apply(s, 0, { k = "close" })); eq({ s.phase, E.over(s), s.turn }, { "bet", false, 1 })
    acts(s, { { 1, "fold" }, { 2, "fold" } }); eq({ s.phase, E.over(s), E.system(s), s.last.won }, { "closed", true, nil, { [3] = 10 } })
    eq(chips(s), { 1000, 995, 1005 }); eq(E.snapshot(E.view(s, 1)).closing, true)
  end)
  it("a bot checks, calls or folds by its cards and raises now and then", function()
    local function r(n) return function(lo, hi) eq({ lo, hi }, { 1, 100 }); return n end end
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "9C 8C", [3] = "7C 2D" }, "3H 8S 9D JD 4C")
    eq(E.bot(E.view(s, 1), 1, r(100)), { k = "call" }); eq(E.bot(E.view(s, 1), 1, r(40)), { k = "raise", to = 20 })
    eq(E.bot(E.view(s, 2), 1, r(1)), nil); eq(E.bot(E.view(s, 1), 2, r(1)), nil)                -- not my cards; not my turn
    acts(s, { { 1, "raise", 40 } }); eq(E.bot(E.view(s, 2), 2, r(100)), { k = "fold" }); eq(E.bot(E.view(s, 2), 2, r(8)), { k = "raise", to = 70 })
    acts(s, { { 2, "call" } }); eq(E.bot(E.view(s, 3), 3, r(50)), { k = "fold" }); eq(E.bot(E.view(s, 3), 3, r(3)), { k = "raise", to = 85 })
    acts(s, { { 3, "fold" } }); sys(s)                                                           -- flop 3H 8S 9D: seat 2 has two pair
    eq({ s.turn, E.bot(E.view(s, 2), 2, r(100)), E.bot(E.view(s, 2), 2, r(40)) }, { 2, { k = "check" }, { k = "bet", to = 45 } })
    acts(s, { { 2, "bet", 45 } }); eq(E.bot(E.view(s, 1), 1, r(100)), { k = "call" })            -- one pair calls half the pot or less
    local w = mk({ 1, 2, 3 }); start(w, { [1] = "QS 5D", [2] = "9C 8C", [3] = "7C 2D" }, "3H 8S 9D JD 4C")
    eq(E.bot(E.view(w, 1), 1, r(50)), { k = "call" }); eq(E.bot(E.view(w, 1), 1, r(51)), { k = "fold" })   -- a weak hand limps half the time
    local p = mk({ 1, 2, 3 }, { opt = { betting = "pl" } }); start(p, { [1] = "AS AD" })
    eq(E.bot(E.view(p, 1), 1, r(1)), { k = "raise", to = 20 }); eq(E.auto(p, 1), { k = "fold" })
  end)
end)
```

- [ ] **Step 2: Run `bash t.sh tests/engines/holdem_test.lua`.** Expected: the eight new tests FAIL (`E.ext` is nil; `"action"` for `void`, `away`, `close`; `E.bot` is nil; `join` on a `leaving` chair is refused); the 44 old ones pass, except line 122's `maxSeats` assertion, which Step 3 changes to 6 with the field.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `52 passed, 0 failed`; all pass (Hold'em is not playable yet).
- [ ] **Step 5: Commit.** `git add engines/holdem.lua tests/engines/holdem_test.lua` — `feat(holdem): the engine names who shuffles and deals; void, sitting out, close and a bot`

### Task 2: A hand at the table: the sealed deal

**Files:**
- Create: `core/Book.lua`, `core/Cash.lua`, `tests/core/holdem_table_test.lua`; Modify: `core/Deal.lua`, `core/DealHooks.lua`, `core/DealLine.lua`, `core/Fair.lua`, `core/Const.lua`, `core/Games.lua`, `core/Session.lua`, `TavernGames.toc`, `tests/toc_test.lua`, `tests/core/fair_test.lua`, `tests/core/games_test.lua`, `tests/core/member_test.lua`, `tests/core/bots_test.lua`, `tests/ui/hall_test.lua`, `tests/wow/slash_test.lua`

**Interfaces:**
- Consumes: Task 1; `Deal.submit`, `Deal.close`, `Deal.int` (`allPublic` is added to it; the comment of `Deal.int` names Cash as a reader beside Deal.lua and DealHooks.lua), `DealKeep.clear`, `Fair.full`, `Session:play`, `Session:armTimers`.
- Produces:
  - `Fair.handSeed(key, handId)` (Global Constraints, rule 2). `Const.BOOK_WAIT = 30`, `BOOK_KEYS = 24`, `BOOK_BATCH = 2`. `Games.PLAYABLE.holdem = true` (the comment: every game of ORDER is integrated; the gate stays for a game added later). `core/Session.lua`: the last line of `TIMERS` also lists `"stepTimer", "keysTimer", "bookTimer"`.
  - `core/Deal.lua`: a file-local `players(s)` = `engine.players(s.state)` when the engine has it and there is a state, else `occupiedSeats(s.seats)`; used in `Deal.open` and `participantsFit`. `handDone`: for an engine with `inHand`, `not engine.inHand(s.state)` (after the `gameOver` line). `request`, op `commit`, for a sealed engine: the commit goes into `fair.pend[seat]` and, once every seat of `fair.p` has one, `s:play(0, {k="fair", op="commits", h, c = copy(fair.pend)})`; other engines as before. `Deal.react`, stage `commit`: `fair.seed = ns.Book.seedFor(s, fair.h) or Fair.seed(…)`; stage `seed`: when `fair.seed` is missing (a `/reload`) and `Fair.commit(Book.seedFor(s, fair.h))` equals `fair.held[me]`, take that seed and send SED again; stage `dealt`: no `reveal` for a sealed engine. `Deal.int.allPublic`.
  - `core/DealHooks.lua`: `table`, op `commits`: the round's `h`, a sealed engine, `a.c` a table with exactly the seats of `fair.p`, each fitting `commitFits`: every one through `sawCommit` into `fair.commits`, stage `"seed"`. `applied`, a `stand` during a shuffle: the round reopens only when `contains(fair.p, a.seat)`. `fits`: the "I am one of the participants" check is skipped for an engine with `players`.
  - `core/DealLine.lua`: `Deal.status` returns `"fair.shuffle"` for a sealed engine in stage `commit` and nil when `fairLast.verdict == "sealed"`.
  - `core/Book.lua` (`ns.Book`; its header states rules 2, 5, 6, 7 and the session fields): `Book.of(s)` (the book, made on first use: `{rec = {}, open = {}, keys = {}, seen = {ok = 0, bad = 0, open = 0}, n = 0, given = {}}`); `Book.isKey(m)` (a string of `2 × SEED_BYTES` lowercase hex); `Book.key(s)` (the book's key; else `env.db.bookKeep = {tid, me, key, g}` when its `tid` and `me` are mine, its `g` is `book.g` (the seq of the running game's `start` event) and its key is one that is not among the book's published `keys`; else a new one, written to `env.db.bookKeep`); `Book.seedFor(s, h)` (nil for an engine that is not sealed or without my seat); `Book.seal(s)` (rule 5, also called for a voided round, see Task 3: `n + 1`; with `fair.foul` or `fair.lied`: `seen.bad + 1` and `Deal.close(s, "bad", fair.foul or "dealt")`; else the record and `Deal.close(s, "sealed")`); `Book.status(s) -> key, tone, arg, arg2 | nil` (nil for another engine or without a book; `"seal.bad", "red", seen.bad` when any; nil while `n == 0`; else `"seal.sealed", "inkDim", #open, seen.ok`; Task 4 adds the closed book).
  - `core/Cash.lua` (`ns.Cash`, `ns.Ext.cash`; nothing is sent from `table`):
    - `Cash.submit(s, a)`: the host handles it at once for its own seat, a member whispers `ACT`.
    - hook `act(s, seat, a)`: anything but `k == "book"` passes; op `step` (host): the round's `h`, `seat == fair.d`, stage `dealt`, `E.system(s.state)` has `need == "faces"` and `a.a.k` is its `k`, `a.a.cards` a table, `allPublic(s, ev, ev.cards)` for `ev = {k = a.a.k, cards = a.a.cards}` → `s:play(0, ev)`. Every book action returns nil.
    - hook `applied(s, seat, a)`: at seat 0 `start`: first the old book runs to its end synchronously (`Book.close` and every check, `"book"` emitted; skipped when there is none or it is final); then the book, `s.handSeen`, `s.handNames`, `s.bookTimer` and `env.db.bookKeep` are dropped, and the new book gets `g = s.seq`. `sit` in a live game: `engine.apply(state, 0, {k="join", seat})` on every client (also on a chair that is `leaving`: the engine marks the leaver's hand gone, so the newcomer owes no face and sends no PRQ) and `book.given[seat] = nil`; the host then calls `s:armTimers()` when no seat is on turn (a sit does not re-arm, and two players may now be enough for a hand). `hand`: `s.handNames = copy(s.seats)`. `open`: `fair.who = {[seat] = name}` for the participants. Then *react* (also from `adopted`): a round in stage `dealt` whose hand is over → `Book.seal(s)`; a round in stage `commit`/`seed` whose hand is over (leaves settled it before the deal) is dropped (`s.fair = nil`, `DealKeep.clear`, the host stops its wait); then the step.
    - *The step* (`s.stepTimer`, cancelled and armed again on every react): with a round in stage `dealt`, a live game and `E.system(state).need == "faces"`: the dealer with its deck sends `ACT {k="book", op="step", h, a}` with `a` = the `k` and `cards` of `E.system(Fair.full(s.state, fair.deck))`, `E.STREET_DELAY` after the react and again every `FAIR_ASK_GAP` while `s.seq` has not moved.
    - hook `adopted(s, prev, m)`: when the snapshot is of a new game (its `start` seq differs from `book.g`) the old book first runs to its end as at `start`; `s.handSeen = state.last and state.last.hand`; `s.handNames` when unset; `fair.who` when unset; react.
  - TOC: `core/Book.lua`, `core/Cash.lua` after `core/DealLine.lua`.

- [ ] **Step 1: Write the failing tests.** `tests/core/fair_test.lua` (a new `it`):

```lua
it("a table key gives one seed a hand; the same key and hand give the same seed", function()
  eq(F.handSeed(SEED, "t#1/1"), "8a096ed15cb70ed784b4785d4e17cd5b"); eq(F.handSeed(SEED, "t#1/2"), "b68638cff5e56a73ad112fbb79444292")
  eq(F.handSeed(ZERO, "t#1/1"), "e5095b93260184a29b277f91645c49da")
  eq(F.commit(F.handSeed(SEED, "t#1/1")), "b64fd9e94132a8c73a533d601ce4cacad546b9e7e2a47fb7941ca992e85be5ec")
  local d = F.deck(ns.Engines.holdem.DECK, { F.handSeed(SEED, "t#1/1"), F.handSeed(ZERO, "t#1/1") }, "t#1/1"); eq({ d[1], d[2], d[3], d[52] }, { "TS", "7C", "9C", "8C" })
end)
```

`tests/core/holdem_table_test.lua`, file scope:

```lua
local Sim = require("sim")
local ns = Sim.ns
local E, Fair = ns.Engines.holdem, ns.Fair

local N = { "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров", "Нади Колева", "Гошо Илиев", "Ели Маринова", "Дидо Ангелов", "Зара Попова" }
local W = "Гледач Гледачев"
local SEED = ("ff"):rep(16)
-- every client has its own random: its table key is KEY(i), so a key under the wrong seat or a regenerated key shows
local function rnd(i) return function(lo, hi) return (lo + i) % (hi + 1) end end
local function KEY(i) return ("%02x"):format(i):rep(16) end
local sim, tid, cl, w

-- n players at seats 1..n (N[1] hosts), W watches; the game is not started yet (at most 6: Hold'em has six seats).
local function tableN(n, opt, turn)
  sim = Sim.new(); cl = {}
  for i = 1, n do cl[i] = sim:add(N[i]); sim.envs[N[i]].random = rnd(i) end
  w = sim:add(W); sim:run(1)
  tid = cl[1]:openTable{ game = "holdem", access = "guild", turn = turn or 30, opt = opt }; sim:run(3)
  w:watch(tid); sim:run(1)
  for i = 2, n do cl[i]:sit(tid, i); sim:run(1) end
  return sim, tid
end
local function host()
  for i = 1, #cl do
    local c = sim.clients[N[i]]
    if c.session and c.session.role == "host" and not sim.offlineSet[N[i]] then return c end
  end
end
local function st() return host().session.state end
local function at(seat) return sim.clients[host().session.seats[seat]] end
local function act(k, to)
  local seat = st().turn
  local r, why = at(seat):act{ k = k, to = to }
  ok(r, "seat " .. tostring(seat) .. " " .. k .. ": " .. tostring(why)); sim:run(1)
end
-- n seconds; whoever is on turn (and not in `skip`) makes its automatic move
local function auto(n, skip)
  for _ = 1, n do
    local t = st().turn
    if t and not (skip and skip[t]) then at(t):playAuto() end
    sim:run(1)
  end
end
local function evs(name, from)
  local out = {}
  for i = from + 1, #sim.sent do
    local m = sim.sent[i]
    if m.target == name and m.msg.t == "EV" then out[#out + 1] = m.msg.a end
  end
  return out
end
local function kinds(list)
  local out = {}
  for i, a in ipairs(list) do out[i] = a.k == "fair" and a.op or a.k end
  return out
end
local function chips(c)
  local t = {}
  for i = 1, 9 do local x = (c or host()).session.state.seats[i]; if x then t[i] = x.chips end end
  return t
end
local function mentions(v, words)
  if type(v) == "string" then
    for _, x in ipairs(words) do if v:find(x, 1, true) then return true end end
    return false
  end
  if type(v) ~= "table" then return false end
  for k, x in pairs(v) do if mentions(k, words) or mentions(x, words) then return true end end
  return false
end
local function deckOf(h, n)
  local seeds = {}
  for i = 1, n do seeds[i] = Fair.handSeed(KEY(i), tid .. "/" .. h) end
  return Fair.deck(E.DECK, seeds, tid .. "/" .. h)
end
```

```lua
describe("holdem at the table", function()
  it("heads-up: four events to the deal, each player gets only its own two cards", function()
    tableN(2); eq(tid, "Иван Петров#1700000001"); local mark = #sim.sent
    ok(cl[1]:startGame()); sim:run(3)
    local C4 = { Fair.commit(Fair.handSeed(KEY(1), tid .. "/4")), Fair.commit(Fair.handSeed(KEY(2), tid .. "/4")) }; local deck = deckOf(4, 2)
    ok(C4[1] ~= C4[2], "the two seats' commits differ"); eq(Fair.handSeed(KEY(1), tid .. "/4"):len(), 32)   -- the pinned hex of each seed is re-derived once
    eq(evs(W, mark), { { k = "start", first = 1 }, { k = "hand" }, { k = "fair", op = "open", h = 4, d = 1, p = { 1, 2 } },
      { k = "fair", op = "commits", h = 4, c = C4 }, { k = "deal", deck = {} } })
    local s = cl[1].session.state
    eq({ s.phase, s.turn, s.button, s.order, cl[1].session.seq, cl[1].session.fair.stage }, { "bet", 1, 1, { 2, 1 }, 6, "dealt" })
    eq({ deck[1], deck[2], deck[3], deck[4] }, { "7S", "9C", "3D", "TS" })
    eq(cl[1].session.state.deck, { [2] = deck[2], [4] = deck[4] }); eq(cl[2].session.state.deck, { [1] = deck[1], [3] = deck[3] }); eq(w.session.state.deck, {})
    eq(sim:count(function(m) return m.msg.t == "PRV" end), 1); eq(sim:count(function(m) return m.msg.t == "SED" end), 1)
    eq(sim:count(function(m) return m.msg.t == "PRV" and m.from == N[1] and m.target == N[2] and ns.Util.same(m.msg.cards, { [1] = deck[1], [3] = deck[3] }) end), 1)
    eq(sim:count(function(m) return (m.channel == "GUILD" or m.msg.t == "EV" or m.msg.t == "SNP") and mentions(m.msg, { deck[1], deck[2], deck[3], deck[4] }) end), 0)
    eq({ ns.Deal.status(cl[2].session) }, {}); eq(ns.Book.status(cl[2].session), nil)
    act("fold"); eq({ st().phase, chips(), cl[2].session.fair.stage, cl[2].session.fairLast.verdict }, { "done", { 995, 1005 }, "done", "sealed" })
    eq({ ns.Book.status(cl[2].session) }, { "seal.sealed", "inkDim", 1, 0 }); eq({ ns.Book.status(w.session) }, { "seal.sealed", "inkDim", 1, 0 })
    eq(cl[1].session.book.rec[4], { p = { 1, 2 }, c = C4, f = { [2] = deck[2], [4] = deck[4] }, who = { N[1], N[2] } })
    eq(cl[1].session.book.rec[4].c, C4); eq(cl[2].session.book.rec[4].c, C4)                  -- each seat's own commit under its own seat
    sim:run(5); eq({ st().button, st().hand, cl[1].session.fair.h, cl[1].session.fair.d }, { 2, 2, 9, 2 })
  end)

  it("three players to a showdown: one event a street; the folded kings stay in the dealer's whisper", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); local mark = #sim.sent; local deck = deckOf(5, 3)
    eq({ deck[1], deck[4], st().order, st().turn, cl[1].session.seq }, { "KS", "KC", { 2, 3, 1 }, 1, 7 })   -- seat 2 holds two kings
    act("call"); act("fold"); act("check"); sim:run(1); eq({ st().phase, st().turn, #st().board }, { "bet", 3, 3 })
    for _ = 1, 3 do act("check"); act("check"); sim:run(1) end
    local e = evs(W, mark)
    eq(kinds(e), { "call", "fold", "check", "street", "check", "check", "street", "check", "check", "street", "check", "check", "showdown" })
    eq(e[4], { k = "street", cards = { [8] = "7S", [9] = "3H", [10] = "2S" } }); eq(e[7], { k = "street", cards = { [12] = "8C" } })
    eq(e[13], { k = "showdown", cards = { [2] = "8H", [5] = "9D", [3] = "6S", [6] = "4H", [8] = "7S", [9] = "3H", [10] = "2S", [12] = "8C", [14] = "TC" } })
    local l = st().last; eq({ l.shown, l.won, l.cat, l.contrib }, { { 3, 1 }, { [3] = 25 }, { [1] = 1, [3] = 2 }, { 10, 5, 10 } }); eq(chips(), { 990, 995, 1015 })
    eq(w.session.state.deck, e[13].cards); eq(cl[3].session.state, E.view(cl[3].session.state, 3)); eq(cl[2].session.state.deck[1], "KS")
    eq(sim:count(function(m) return mentions(m.msg, { "KS", "KC" }) end), 1)
    eq(sim:count(function(m) return m.msg.t == "PRV" and m.target == N[2] and mentions(m.msg, { "KS", "KC" }) end), 1)
    eq(sim:count(function(m) return m.msg.t == "EV" and (m.msg.a.k == "book" or m.msg.a.op == "reveal" or m.msg.a.op == "noreveal") end), 0)
    for _, c in ipairs{ cl[1], cl[2], cl[3], w } do
      eq({ ns.Book.status(c.session) }, { "seal.sealed", "inkDim", 1, 0 }); eq(c.session.fairSeen, { ok = 0, bad = 0 }); eq(ns.Deal.alarm(c.session), false)
    end
  end)
  it("the dealer is the button; a member refuses another dealer or other participants", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); local T = ns.Ext.fair.table
    eq({ cl[2].session.fair.d, cl[2].session.fair.p, st().button }, { 1, { 1, 2, 3 }, 1 })
    auto(3); sim:run(5); eq({ st().hand, st().button, cl[3].session.fair.d, cl[3].session.fair.h, cl[3].session.fair.stage }, { 2, 2, 2, 11, "dealt" })
    auto(3); local s = cl[3].session; eq({ s.state.phase, s.seq }, { "done", 15 }); sim:offline(N[3])
    ok(E.apply(s.state, 0, { k = "hand" })); s.seq = 16; eq({ s.state.button, E.dealer(s.state) }, { 3, 3 })   -- the next hand, by hand
    eq(T(s, { k = "fair", op = "open", h = 17, d = 2, p = { 1, 2, 3 } }), nil); eq(T(s, { k = "fair", op = "open", h = 17, d = 3, p = { 1, 3 } }), nil)
    eq(T(s, { k = "fair", op = "open", h = 18, d = 3, p = { 1, 2, 3 } }), nil); eq(T(s, { k = "fair", op = "open", h = 17, d = 3, p = { 1, 2, 3 } }), true)
    local c = Fair.commit(SEED)
    eq(T(s, { k = "fair", op = "commits", h = 17, c = { c, c } }), nil); eq(T(s, { k = "fair", op = "commits", h = 17, c = { c, c, c, c } }), nil)
    eq(T(s, { k = "fair", op = "commits", h = 16, c = { c, c, c } }), nil); eq(s.fair.stage, "commit")
    eq(T(s, { k = "fair", op = "commits", h = 17, c = { c, c, c } }), true); eq({ s.fair.stage, s.fair.commits }, { "seed", { c, c, c } })
  end)
  it("a newcomer sits mid-hand: chips at once, no cards, dealt in from the next hand", function()
    tableN(2); ok(cl[1]:startGame()); sim:run(3); local c5 = sim:add(N[5]); sim.envs[N[5]].random = rnd(5); sim:run(1); c5:sit(tid, 5); sim:run(1)
    local s = c5.session
    eq({ s.mySeat, s.state.seats[5], s.state.p[5], s.state.order, s.state.deck, s.fair.stage, s.fair.p }, { 5, { chips = 1000, out = false, leaving = false }, nil, { 2, 1 }, {}, "dealt", { 1, 2 } })
    eq({ cl[2].session.state.seats[5].chips, w.session.state.seats[5].chips, st().turn, cl[1].session:left() }, { 1000, 1000, 1, 27 })
    eq({ c5:act{ k = "fold" } }, { nil, "turn" }); eq(sim:count(function(m) return m.target == N[5] and m.msg.t == "PRV" end), 0)
    act("fold"); eq({ ns.Book.status(s) }, { "seal.sealed", "inkDim", 1, 0 }); sim:run(5)
    eq({ st().hand, st().button, st().order, s.fair.p, s.fair.d }, { 2, 2, { 5, 1, 2 }, { 1, 2, 5 }, 2 })
    eq({ #E.hidden(s.state, 5), s.state.deck[1] ~= nil, s.state.deck[4] ~= nil, ns.Deal.alarm(s), s.fairSeen.bad }, { 2, true, true, false, 0 })
    eq(chips(), { 985, 1005, [5] = 995 })                                                      -- hand 2: seat 5 posts the small blind, seat 1 the big one
  end)
  it("the line under the felt: the shuffle, then silence until the book speaks", function()
    tableN(2); sim:offline(N[2]); ok(cl[1]:startGame()); sim:run(3)
    eq({ cl[1].session.fair.stage, cl[1].session.fair.commits, cl[1].session.fair.pend }, { "commit", {}, { Fair.commit(Fair.handSeed(KEY(1), tid .. "/4")) } })
    eq({ ns.Deal.status(cl[1].session) }, { "fair.shuffle" }); eq({ ns.Deal.status(w.session) }, { "fair.shuffle" })
    eq(ns.Ext.fair.snap(cl[1].session), { h = 4, d = 1, p = { 1, 2 }, c = {}, st = "commit", n = 0 })
  end)
  it("a newcomer sits in the chair of a player who stood up this hand: no PRV, no face of the leaver anywhere, dealt in from the next hand", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); cl[3]:stand(); sim:run(1)
    local c4 = sim:add(N[4]); sim.envs[N[4]].random = rnd(4); sim:run(1); local mark = #sim.sent; c4:sit(tid, 3); sim:run(2)
    local s = c4.session
    eq({ s.mySeat, s.state.seats[3].leaving, s.state.p[3].gone, #E.hidden(s.state, 3), s.state.deck }, { 3, true, true, 0, {} })
    eq(sim:count(function(m) return m.from == N[4] and m.msg.t == "PRQ" end), 0); eq(sim:count(function(m) return m.target == N[4] and m.msg.t == "PRV" end), 0)
    auto(6); sim:run(5)
    eq({ st().hand, E.players(st()), cl[1].session.fair.p, #E.hidden(s.state, 3), ns.Deal.alarm(s) }, { 2, { 1, 2, 3 }, { 1, 2, 3 }, 2, false })
  end)
end)
```

`tests/toc_test.lua` (the size `it` of Task 0 gains the two caps):

```lua
ok(lines("core/Book.lua") < 260, "Book.lua " .. lines("core/Book.lua")); ok(lines("core/Cash.lua") < 280, "Cash.lua " .. lines("core/Cash.lua"))
```

Existing tests to change (no game is gated any more; the gate itself stays tested by gating one by hand): `tests/core/games_test.lua` (the list test: `ok(G.engine("holdem") == ns.Engines.holdem)`, `ok(G.list()[6].engine == ns.Engines.holdem)`; the TBL test of an unintegrated engine sets `ns.Games.PLAYABLE.holdem = nil` at its start and `true` at its end); `tests/core/member_test.lua` around line 36 (the same two lines around the test; its `ok(…)` guard reads the gated flag); `tests/core/bots_test.lua` around line 366 (`hostTable("chess")` and `inviteMe("chess")` are nil); `tests/ui/hall_test.lua` (all six games active, none dimmed, no „Скоро“; the dimmed-game test sets `w.ns.Games.PLAYABLE.holdem = nil` before `MainWindow.show()`); `tests/wow/slash_test.lua` (the two „не е готова“ checks use `bots host chess`; new: `w:slash("bots host holdem"); w:advance(1)` lists a table with `game == "holdem"`).

- [ ] **Step 2: Run `bash t.sh tests/core/fair_test.lua tests/core/holdem_table_test.lua`.** Expected: FAIL (`F.handSeed` is nil; `openTable` returns nil, `"game"`). The two new size asserts of `tests/toc_test.lua` fail until the files exist.
- [ ] **Step 3: Implement** and change the listed tests.
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: `6 passed, 0 failed` in the table file; all pass (the size test now also holds Book and Cash to their caps), among them every Сантасе and Белот table test unchanged. `wc -l core/Session.lua` is 539.
- [ ] **Step 5: Commit.** `git add core/Book.lua core/Cash.lua core/Deal.lua core/DealHooks.lua core/DealLine.lua core/Fair.lua core/Const.lua core/Games.lua core/Session.lua TavernGames.toc tests/core tests/ui/hall_test.lua tests/wow/slash_test.lua` — `feat: Холдем at the table on a sealed deal; one table key a player, no reveal a hand`

### Task 3: Leaving, silence and the clock

**Files:**
- Modify: `core/Cash.lua`, `core/Deal.lua`, `core/Session.lua`, `core/Member.lua`, `core/Lifecycle.lua` (the hook list in its comment), `core/Const.lua`; Test: `tests/core/holdem_table_test.lua`

**Interfaces:**
- Produces:
  - `Const.AUTO_GRACE = 7`. `core/Session.lua`, `armTimers`, two lines changed in place: the early return reads `if engine.view and seat ~= self.mySeat and not engine.publicAuto then return end` and the timer waits `self.turn + (seat ~= self.mySeat and engine.view and C.AUTO_GRACE or 0)`.
  - `Member.timedOut(s, m) -> bool`: `m.auto == true`, the engine has `publicAuto`, and `m.a` is `engine.auto(s.state, m.seat)`, and **my own** clock has run out: `s.turnAt` (my `env.now()` when I applied the event that put my seat on turn) is set and `now >= s.turnAt + s.turn` (`s.turn` = the table's turn time from TBL); the host's `left` is ignored, because a modified host would send `left = 0` and fold me at once. `onEvent` calls the hook `forged` only when the event is neither mine (`Member.mine`) nor that. It also calls `forged` for `{k="away", seat = s.mySeat}` while my round is in stage `dealt`, or in stage `seed` unless I am that round's dealer (the legitimate aways are stage `commit`, the dealer right after a void, and the dealer in stage `seed`).
  - `core/Deal.lua`, `fairWaitOver`: `s:hook("lapsed")` on the line that reopens a shuffle, before `Deal.open(s)`. The line that closes a round whose hand was voided calls `ns.Book.seal(s)` first when the engine is sealed, so the void's record (the faces known so far) goes into the book, and then closes the round `"void"` as before.
  - `core/Cash.lua`: hook `lapsed(s)` (host): in stage `commit` `s:play(0, {k="away", seat})` for every participant without a commit in `fair.pend`; in stage `seed` `s:play(0, {k="away", seat = fair.d})` (the deal passes to the next participant). The step, on a host that is not the dealer: `FAIR_WAIT` after the step became due with `s.seq` unmoved it plays `{k="void"}` and `{k="away", seat = fair.d}`. React: a live game in which my own seat is away → `Session.act(client, {k="back"})`. The `"hand"` event (Shared contracts): in `applied`, whenever `state.last.hand ~= s.handSeen`, with `names = s.handNames`.

- [ ] **Step 1: Write the failing tests** (appended).

```lua
-- Sets the stacks on every client's state (between hands), as if earlier hands had been played.
local function stacks(t)
  for _, c in pairs(sim.clients) do
    if c.session and c.session.state then
      for seat, n in pairs(t) do c.session.state.seats[seat].chips = n end
    end
  end
end
local function total(c)
  local n = 0
  for _, x in pairs(chips(c)) do n = n + x end
  return n
end
local function hands(c) local t = {}; c:on("hand", function(e) t[#t + 1] = e end); return t end

describe("holdem: leaving, silence and the clock", function()
  it("a player who stands mid-hand is folded and his chips stay in the pots; nothing is lost", function()
    tableN(4); ok(cl[1]:startGame()); sim:run(1); stacks{ 600, 300, 100, 600 }; local seen = hands(w); sim:run(2)
    eq({ st().order, st().turn, chips() }, { { 2, 3, 4, 1 }, 4, { 600, 295, 90, 600 } })
    act("allin"); act("call"); act("call"); eq({ st().turn, chips() }, { 3, { 0, 0, 90, 0 } })
    cl[2]:stand(); sim:run(1); eq({ st().p[2].folded, st().seats[2].leaving, st().turn, host().session.seats[2] }, { true, true, 3, false })
    act("call"); sim:run(4); local l = seen[1].last
    eq(l.pots, { { amount = 400, eligible = { 3, 4, 1 }, winners = { 3 } }, { amount = 1200, eligible = { 4, 1 }, winners = { 1 } } })
    eq({ l.contrib, l.won, l.left, l.shown }, { { 600, 300, 100, 600 }, { [1] = 1200, [3] = 400 }, { [2] = 0 }, { 3, 4, 1 } })
    eq({ #seen, seen[1].n, seen[1].game, seen[1].tid, seen[1].chips }, { 1, 1, "holdem", tid, { [1] = 1200, [3] = 400, [4] = 0 } })
    eq(seen[1].names, { N[1], N[2], N[3], N[4], false, false, false, false, false }); eq(seen[1].opt, { betting = "nl", blinds = 10, stack = 100 })
    eq({ total(), st().seats[2], st().seats[4].out, cl[3].session.state.last }, { 1600, false, true, l })
    sim:run(5); eq({ st().hand, E.players(st()), st().seats[4].chips }, { 2, { 1, 3 }, 0 })
  end)
  it("a seat that does not commit in FAIR_WAIT sits out; back, its client deals it in again", function()
    tableN(3); sim:offline(N[3]); ok(cl[1]:startGame()); sim:run(3); local mark = #sim.sent
    eq({ st().phase, cl[1].session.fair.stage, cl[1].session.fair.h, chips() }, { "deal", "commit", 5, { 1000, 995, 990 } })
    sim:run(18); eq(cl[1].session.fair.h, 5); sim:run(1)
    eq(kinds(evs(W, mark)), { "away", "open", "commits", "deal" }); eq(evs(W, mark)[1], { k = "away", seat = 3 })
    eq({ st().seats[3].away, st().p[3].folded, cl[1].session.fair.h, cl[1].session.fair.p, st().phase, st().turn }, { true, true, 7, { 1, 2 }, "bet", 1 })
    auto(2); sim:run(5); eq({ st().hand, st().order, chips() }, { 2, { 1, 2 }, { 990, 1000, 995 } })     -- seat 2 won 5 of seat 3's blind, the uncalled half came back; heads-up now
    local c3 = sim:relog(N[3]); sim:run(2); eq({ st().seats[3].away, c3.session.mySeat }, { false, 3 })
    eq(sim:count(function(m) return m.from == N[3] and m.msg.t == "ACT" and m.msg.a.k == "back" end), 1)
    auto(3); sim:run(5); eq({ st().order, ns.Deal.alarm(c3.session), c3.session.fair.p }, { { 1, 2, 3 }, false, { 1, 2, 3 } })
  end)
  it("the clock: my client checks or folds at my deadline; the host does it for a silent seat AUTO_GRACE later", function()
    tableN(3, nil, 30); ok(cl[1]:startGame()); sim:run(3); eq({ st().turn, cl[1].session:left(), ns.Const.AUTO_GRACE }, { 1, 29, 7 })
    act("call"); sim:run(29); eq(st().turn, 2); sim:run(1)                 -- seat 2 owes 5 more: its own client folds
    eq({ st().turn, st().p[2].folded }, { 3, true }); eq(sim:count(function(m) return m.from == N[2] and m.msg.t == "ACT" and m.msg.a.k == "fold" end), 1)
    sim:offline(N[3]); sim:run(36); eq(st().turn, 3); sim:run(2); eq({ st().phase, st().turn, #st().board }, { "bet", 3, 3 })   -- the host checks for seat 3
    eq(sim:count(function(m) return m.target == W and m.msg.t == "EV" and m.msg.seat == 3 and m.msg.auto == true and m.msg.a.k == "check" end), 1)
    eq(sim:count(function(m) return m.target == W and m.msg.t == "EV" and m.msg.seat == 2 and m.msg.auto == true end), 0)
  end)
  it("a timeout the host plays for me after my deadline is not forged; a move before it is", function()
    tableN(3, nil, 30); ok(cl[1]:startGame()); sim:run(3); act("call"); local s = cl[2].session
    s.autoTimer.cancel(); s.autoTimer = nil; sim:run(37)                                         -- my client sleeps through its deadline
    eq({ st().turn, st().p[2].folded, s.state.p[2].folded, s.fair.foul }, { 3, true, true, nil })
    eq(ns.Member.timedOut(s, { seat = 2, auto = true, a = { k = "fold" } }), false)                -- no deadline of mine is running now
    act("check"); sim:run(2); eq(st().turn, 3); cl[1].session:play(3, { k = "check" }, true); sim:run(1)   -- the host moves for seat 3 at once
    eq({ cl[3].session.fair.foul, cl[2].session.fair.foul }, { "forged", nil })
    auto(8); sim:run(4); eq({ cl[3].session.fairLast.verdict, cl[3].session.fairLast.why, ns.Deal.alarm(cl[3].session) }, { "bad", "forged", true })
    eq({ ns.Book.status(cl[3].session) }, { "seal.bad", "red", 1 }); eq({ ns.Book.status(cl[2].session) }, { "seal.sealed", "inkDim", 1, 0 })
  end)
  it("the dealer reloads and the hand goes on; a dealer who is gone: the hand is void after FAIR_WAIT and he sits out", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); auto(3); sim:run(5); eq({ st().hand, cl[1].session.fair.d, st().turn }, { 2, 2, 2 })
    sim.envs[N[2]].random = rnd(7)                                                               -- a regenerated key would be KEY(7)
    local c2 = sim:relog(N[2]); sim:run(2); eq({ c2.session.fair.stage, c2.session.fair.deck ~= nil, sim.envs[N[2]].db.bookKeep }, { "dealt", true, { tid = tid, me = N[2], key = KEY(2), g = 3 } })
    act("call"); act("call"); act("check"); sim:run(1); eq({ #st().board, st().turn }, { 3, 3 })     -- the reloaded dealer dealt the flop
    act("check"); act("check"); act("check"); sim:offline(N[2]); local seen = hands(w)             -- the turn card is due and its dealer is gone
    eq({ st().phase, chips() }, { "street", { 990, 985, 995 } }); sim:run(19); eq(st().phase, "street"); sim:run(1)
    eq({ st().phase, st().last.void, chips(), st().seats[2].away, total() }, { "done", true, { 1000, 995, 1005 }, true, 3000 })
    eq({ ns.Deal.status(cl[1].session) }, { "fair.voidBy", N[2] }); eq({ #seen, seen[1].last.void }, { 1, true })
    eq(cl[1].session.book.n, 2)                                                        -- the void was written into the book (n counts it); its record is checked at the close
    sim:run(5); eq({ st().hand, st().order }, { 3, { 1, 3 } })
  end)
  it("a fold the host plays for me before my own deadline is forged, whatever `left` it sends", function()
    tableN(3, nil, 30); ok(cl[1]:startGame()); sim:run(3); act("call"); local s = cl[2].session
    ok(s.turnAt ~= nil, "my own clock started when the turn reached me")
    cl[1].session:play(2, { k = "fold" }, true); sim:run(1)                                       -- the host folds me at once and calls it a timeout
    eq({ s.fair.foul, ns.Member.timedOut(s, { seat = 2, auto = true, a = { k = "fold" }, left = 0 }) }, { "forged", false })
  end)
  it("an away of my seat in a dealt hand is a fold nobody asked for: forged; the legitimate aways are not", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3)
    cl[1].session:play(0, { k = "away", seat = 3 }); sim:run(1)
    eq({ cl[3].session.fair.foul, cl[2].session.fair.foul }, { "forged", nil })
  end)
  --[[ the next four are scenario tests (each one `it`); their values are named, the timing is the table's (FAIR_WAIT = 20):
  "a shuffle stuck in stage seed: the silent dealer sits out and the deal passes on": tableN(3); hand 1 played by auto(3); in hand 2 (dealer seat 2)
  the dealer's client goes offline after the commits event (stage "seed"); after FAIR_WAIT the events to W are { away seat = 2, open, commits, deal }
  with fair.d == 3 and fair.p == { 1, 3 }; no round is closed "bad"/"nodeal" on any client;
  "a member that reloads in stage seed sends its seed again": the same table, a member that is not the dealer /reloads in stage "seed" (sim:relog
  with rnd(7) in its env): it sends exactly one more SED, taken from Book.seedFor, and the dealer deals;
  "a void writes the hand's record": a hand voided after the flop (the dealer offline, as the test above): every client's book.n counts it, its
  record has f with the flop faces and the hand is checked "ok" at the close (a swapped flop card in the dealer's deck before the void turns the
  close of that table "bad" for hand h);
  "the dealer stands mid-hand: the hand is void and its chips come back": tableN(3), seat 2 dealing hand 2, after one bet cl[2]:stand(): the hand
  ends void (state.last.void), chips of seats 1 and 3 are what they were before the hand, the stander's chips went with it (last.left[2]
  equals its stack after the blinds), total() over the seated plus last.left is unchanged, and the void's record is in the book. ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/holdem_table_test.lua`.** Expected: the eleven new tests FAIL (no `"hand"` event; the shuffle is opened again with the same three seats; the turn stays at seat 3; `Member.timedOut` is nil; the hand stays in `"street"`).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `17 passed, 0 failed`; all pass. `wc -l core/Session.lua` is 539.
- [ ] **Step 5: Commit.** `git add core/Cash.lua core/Deal.lua core/Session.lua core/Member.lua core/Lifecycle.lua core/Const.lua tests/core/holdem_table_test.lua` — `feat(core): a silent seat sits out, a lost dealer voids the hand, the host plays a public timeout`

### Task 4: The book: keys, the close, the check

**Files:**
- Modify: `core/Book.lua`, `core/Cash.lua`, `core/DealHooks.lua`, `core/Client.lua`, `core/Lifecycle.lua` (comment, and one line of `Session:canStart`); Test: `tests/core/holdem_table_test.lua`

**Interfaces:**
- Produces:
  - `Client:stand()` calls `self.session:hook("leaving")` before `Session.stand`. `Session:canStart` (`core/Lifecycle.lua`) gains one line: for a sealed engine, a book that is `closed` and not `published` refuses with code `"book"` (the comment lists the code), so „Нова игра“ cannot erase a verification that has not run.
  - `core/Book.lua`: `Book.addKeys(s, map)` (seats ascending: `keys[#keys + 1] = {seat, q = s.seq, m}`; under my own seat a key that is not mine sets `forged` and `seen.bad + 1`; mine sets `out` and drops `env.db.bookKeep`; then `Book.run`); `Book.check(s, h) -> "ok" | "bad" | nil, missing` (rule 7); `Book.run(s)` (one `s.bookTimer` of 0.1 s while a hand is ready: every participant has a key at or after it and it was not tried with this many keys; a verdict removes the record, counts it and, when bad, emits `"fair"`; with nothing ready and the book closed: the end); the end (the first time; a key that arrives later reopens it: the hands it opens leave `open`, `seen.open` shrinks, `"book"` is emitted again): the hands left are counted `open`, `missing` = the names (`rec.who`) of the seats without a key, sorted by bytes, `final = true`, event `"book"`, `"session"`; `Book.close(s)` (`closed = true`, `Book.run`); `Book.snap(s)` (`{{seat, q, m}, …}`, the newest `BOOK_KEYS`, nil without one or for another engine); `Book.adopt(s, list)` (well-formed entries not yet known by seat and key are added; `Book.run`); `Book.status` for a final book: `"seal.bad", "red", n`; `"seal.open", "gold", seen.open, missing[1]`; `"seal.ok", "good", seen.ok`; `Book.tip(s) -> {{tone, key, arg}, …}`: `{"ink", "seal.tip"}`, with bad hands `{"red", "seal.tip.bad", n}`, for every missing name `{"gold", "seal.tip.open", name}`.
  - `core/DealHooks.lua`: `snap` adds `k = ns.Book.snap(s)` to both shapes it returns.
  - `core/Cash.lua`: `Cash.close(client) -> true | nil, code` (`"none"`, `"nothost"`, `"live"`: no live game, or already closing): `s:play(0, {k="close"})`. Hook `table`: `{k="book", op="keys", m}` with `m` a table whose every key is an occupied seat and every value a key → true; anything else of `k == "book"` nil. Hook `act`, op `key` (host): a key, the first from that seat since it sat (`book.given`): while the game is not over it is published at once; once `E.over`, it is kept in `book.wait` and all are published when every seated seat's is in; a `stand` handled while `E.over` first publishes `book.wait` (the leaver's key included) in one event and then plays the stand, so the final event carries only seats still occupied and is never refused; a key that arrives after `book.published` goes out in a further keys event. Hook `applied`: `keys` → `Book.addKeys`, and `Book.close` when `E.over(state)`; `abort` → `Book.close`; a `stand` that leaves fewer than `minSeats` in a live game: the host publishes its own key at once (before `Session` aborts). React, once `E.over`: my key is sent (once: `book.sent`) and the host arms `s.keysTimer` (`BOOK_WAIT = 30`, counted from the close event; the publish is early when every seated key is in), after which it publishes what it has (the first publish sets `book.published`); a member that sees a final keys event without the key it sent sends it once more (`book.resent`). Hook `leaving(s)`: seated in a live game with my key neither sent nor out: the key is sent and `env.db.bookKeep` dropped. Hook `adopted`: `Book.adopt(s, m.fr and m.fr.k)`. Hook `hostChanged`: `s.keysTimer` is dropped and a key I sent but did not see published is due again (`book.sent = nil`).

- [ ] **Step 1: Write the failing tests** (appended).

```lua
local function books(c) local t = {}; c:on("book", function(e) t[#t + 1] = e end); return t end
-- n hands played by automatic moves (each ends when the first seat to act folds its way round)
local function play(n)
  local target = st().hand + n
  for _ = 1, 400 do
    if st().hand >= target and st().phase == "bet" then return end
    local t = st().turn
    if t then at(t):playAuto() end
    sim:run(1)
  end
  error("the hands did not come")
end

describe("holdem: the book", function()
  it("close: the hand is played out, every seat's key comes in one event, every client checks every hand", function()
    tableN(3); local bk = { books(cl[1]), books(cl[3]), books(w) }; ok(cl[1]:startGame()); sim:run(3); play(3)
    eq(st().hand, 4); eq({ ns.Cash.close(cl[2]) }, { nil, "nothost" }); local mark = #sim.sent
    eq(ns.Cash.close(cl[1]), true); eq({ ns.Cash.close(cl[1]) }, { nil, "live" })
    eq({ st().closing, st().phase, E.over(st()) }, { true, "bet", false }); auto(3); sim:run(1)
    eq({ st().phase, cl[3].session:gameOver(), cl[1].session.status }, { "closed", true, "live" })
    local e = evs(W, mark); eq(kinds(e), { "close", "fold", "fold", "book" }); eq(e[4], { k = "book", op = "keys", m = { KEY(1), KEY(2), KEY(3) } })
    eq(sim:count(function(m) return m.msg.t == "ACT" and m.msg.a.k == "book" and m.msg.a.op == "key" end), 2)
    sim:run(3)
    for i = 1, 3 do eq(bk[i], { { tid = tid, game = "holdem", hands = 4, ok = 4, bad = 0, open = 0, missing = {}, at = bk[i][1].at } }) end
    for _, c in ipairs{ cl[1], cl[2], cl[3], w } do eq({ ns.Book.status(c.session) }, { "seal.ok", "good", 4 }) end
    eq(sim.envs[N[2]].db.bookKeep, nil); sim:run(10); eq(st().hand, 4)                              -- nothing is dealt after the close
    ok(cl[1]:startGame()); sim:run(3); eq({ st().hand, chips(), cl[2].session.book.n, #cl[2].session.book.keys }, { 1, { 1000, 995, 990 }, 0, 0 })
  end)
  it("a leaver's key goes out at once; a hand whose players have all left is checked while the game runs", function()
    tableN(4); ok(cl[1]:startGame()); sim:run(1); stacks{ [1] = 0, [4] = 0 }; sim:run(2)        -- hand 1 is between seats 2 and 3 only
    eq({ st().order, cl[1].session.fair.p }, { { 3, 2 }, { 2, 3 } }); auto(1); stacks{ [1] = 1000, [4] = 1000 }; sim:run(5)
    eq({ st().hand, #st().order, (ns.Book.status(cl[4].session)) }, { 2, 4, "seal.sealed" }); local mark = #sim.sent
    cl[2]:stand(); sim:run(1); local e = evs(W, mark)                                          -- seat 2 leaves hand 2 (seat 3 deals it)
    eq(kinds(e), { "book", "stand" }); eq(e[1], { k = "book", op = "keys", m = { [2] = KEY(2) } }); eq(sim.envs[N[2]].db.bookKeep, nil)
    eq(cl[4].session.book.keys, { { seat = 2, q = 14, m = KEY(2) } }); eq({ ns.Book.status(cl[4].session) }, { "seal.sealed", "inkDim", 1, 0 })
    auto(4); eq({ st().phase, cl[4].session.book.n }, { "done", 2 }); cl[3]:stand(); sim:run(2)
    for _, c in ipairs{ cl[1], cl[4], w } do eq({ ns.Book.status(c.session) }, { "seal.sealed", "inkDim", 1, 1 }) end   -- hand 1 is checked, hand 2 waits
    eq({ cl[1].session.status, host().session:seatedCount() }, { "live", 2 })
    eq(ns.Ext.fair.snap(cl[1].session).k, { { 2, 14, KEY(2) }, { 3, 18, KEY(3) } })
  end)
  it("the last but one stands up: the host's own key closes the book before the table stops", function()
    tableN(2); local bk, bw = books(cl[1]), books(w); ok(cl[1]:startGame()); sim:run(3); play(2); local mark = #sim.sent
    cl[2]:stand(); sim:run(1); local e = evs(W, mark)
    eq(kinds(e), { "book", "stand", "book", "abort" }); eq({ e[1].m, e[3].m }, { { [2] = KEY(2) }, { KEY(1) } }); eq(cl[1].session.status, "aborted")
    sim:run(3); eq({ bk[1].hands, bk[1].ok, bk[1].open, bw[1].ok, #bk }, { 3, 3, 0, 3, 1 }); eq({ ns.Book.status(w.session) }, { "seal.ok", "good", 3 })
  end)
  it("the host vanishes before the close: the table goes on under the next host, his hands stay open and name him", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); play(2); sim:offline(N[1])
    for _ = 1, 100 do if cl[2].session.role == "host" then break end; sim:run(1) end
    eq({ cl[2].session.role, cl[3].session.host, cl[2].session.state.hand }, { "host", N[2], 3 }); local b3, bw = books(cl[3]), books(w)
    play(3); eq({ st().seats[1].away, #st().order }, { true, 2 }); eq(ns.Cash.close(cl[2]), true); auto(4); eq(st().phase, "closed")
    sim:run(30); eq(evs(W, 0)[#evs(W, 0)], { k = "book", op = "keys", m = { [2] = KEY(2), [3] = KEY(3) } }); sim:run(4)   -- seat 1's key never comes: BOOK_WAIT
    eq({ b3[1].hands, b3[1].ok, b3[1].bad, b3[1].open, b3[1].missing, bw[1].open }, { 6, 3, 0, 3, { N[1] }, 3 })
    eq({ ns.Book.status(cl[3].session) }, { "seal.open", "gold", 3, N[1] })
  end)
  it("the host is back in time: his key is still his and every hand is checked", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); play(2); sim:offline(N[1])
    for _ = 1, 100 do if cl[2].session.role == "host" then break end; sim:run(1) end
    sim.envs[N[1]].random = rnd(7)                                                                 -- a regenerated key would be KEY(7), not his
    local c1 = sim:relog(N[1]); sim:run(2); eq({ c1.session.role, c1.session.mySeat, sim.envs[N[1]].db.bookKeep.key }, { "player", 1, KEY(1) }); local b1, b3 = books(c1), books(cl[3])
    play(2); eq(ns.Cash.close(cl[2]), true); auto(4); sim:run(6)
    eq({ b3[1].hands, b3[1].ok, b3[1].open, b1[1].hands, b1[1].ok, b1[1].open }, { 5, 5, 0, 3, 3, 0 })      -- his own book starts where he came back
  end)
  it("a card that was not the deck's turns its hand bad at the close, on every client", function()
    tableN(2); local fw = {}; w:on("fair", function(e) if e.verdict == "bad" then fw[#fw + 1] = e end end)
    ok(cl[1]:startGame()); sim:run(3); local d = cl[1].session.fair.deck; d[6], d[40] = d[40], d[6]   -- the dealer swaps the first flop card
    act("call"); act("check"); sim:run(1); eq({ #st().board, w.session.state.deck[6] }, { 3, d[6] }); act("check"); act("bet", 10); act("fold")
    eq({ ns.Book.status(w.session) }, { "seal.sealed", "inkDim", 1, 0 }); ok(ns.Cash.close(cl[1])); sim:run(3)
    eq({ #fw, fw[1].h, fw[1].why, fw[1].game }, { 1, 4, "deal", "holdem" })
    for _, c in ipairs{ cl[1], cl[2], w } do eq({ ns.Book.status(c.session) }, { "seal.bad", "red", 1 }); eq(c.session.book.seen, { ok = 0, bad = 1, open = 0 }) end
  end)
  it("a key under my seat that is not mine; a member that missed a key gets it with the snapshot", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); play(1); sim:offline(N[3])
    cl[1].session:play(0, { k = "book", op = "keys", m = { [2] = ("00"):rep(16) } }); sim:run(1)
    eq({ cl[2].session.book.forged, (ns.Book.status(cl[2].session)) }, { true, "seal.bad" }); eq(#cl[3].session.book.keys, 0)
    sim:online(N[3]); sim:run(31); eq(cl[3].session.book.keys, { { seat = 2, q = cl[1].session.book.keys[1].q, m = ("00"):rep(16) } })
    local T = ns.Ext.cash.table
    eq(T(cl[2].session, { k = "book", op = "keys", m = { [5] = SEED } }), nil); eq(T(cl[2].session, { k = "book", op = "keys", m = { [1] = "xyz" } }), nil)
    eq(T(cl[2].session, { k = "book", op = "keys", m = {} }), true); eq(T(cl[2].session, { k = "book", op = "key", m = SEED }), nil)
  end)
  --[[ the next three are scenario tests (each one `it`); their values are named:
  "„Нова игра“ does not skip the check": tableN(3), play(2), close, auto(4) until the game is closed; with the host's book not yet `published`
  (seat 3 offline so its key is late) ns.Cash startGame is refused: { cl[1]:startGame() } == { nil, "book" }; after BOOK_WAIT (30 s) it starts, and on
  every client the old book ended with its "book" event before the new game's first event; a client that was offline at the close and adopts a
  snapshot of the new game ends its old book first (one "book" event, its hands counted open), and Book.key(s) on it ignores its stale
  env.db.bookKeep (its g is the old game's) and draws a new key (a different rnd): the new game's seeds are not public;
  "close, one player stands within a second: every hand still ok": tableN(3), play(3), close; the hand is played out, game over; seat 3 sends its
  key and presses „Стани“ at once: the host publishes book.wait (with seat 3's key) in one event before the stand event, then the final keys
  event carries only seats 1 and 2; on every client { book.hands, book.ok, book.bad, book.open } == { 4, 4, 0, 0 } and missing == {};
  "a key after the publish: the hands leave open": tableN(3), play(2), close; seat 3's client is offline at the close and comes back after the
  publish (BOOK_WAIT): the first "book" event has open == 2 and missing == { N[3] }; seat 3's key (KEY(3)) goes out in a further keys event
  and the second "book" event on every client reads { ok = 2, open = 0, missing = {} }; a member whose key was missing from a final keys event
  sends it once more (sim:count of its ACT key messages == 2) and not a third time. ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/holdem_table_test.lua`.** Expected: the ten new tests FAIL (`Cash.close` is nil; no `book` event; `"book"` is never emitted).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `27 passed, 0 failed`; all pass. `wc -l core/Book.lua core/Cash.lua`: below 260 and 280.
- [ ] **Step 5: Commit.** `git add core/Book.lua core/Cash.lua core/DealHooks.lua core/Client.lua core/Lifecycle.lua tests/core/holdem_table_test.lua` — `feat(core): the book of a Холдем table: keys when a player leaves and at the close, every hand checked`

### Task 5: Bots, and what a full table costs

**Files:**
- Modify: `core/Bots.lua`, `core/Session.lua`, `wow/Slash.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/core/holdem_table_test.lua`, `tests/core/bots_test.lua`, `tests/wow/slash_test.lua`

**Interfaces:**
- Produces:
  - `core/Session.lua`, two edits, both in place (no line added; the file stays at 539 lines, below 540): `check`: `self.watchers >= (self:engine().watchers or C.MAX_WATCHERS)`; and `Session:left()` (line 103): `return math.ceil(math.max(0, self.deadline - self.client.env.now()))`, so the clock rides in whole seconds (the real `GetTime()` float would cost about 19 bytes an event). With the two edits of Tasks 2 and 3 that is the fourth in-line edit of the stage.
  - `core/Bots.lua`: `wantsFill` — a bot host with `engine.botFill` fills also while live, up to `botFill` seats (others as before: not live, below `minSeats`). `Bots:fill(n) -> asked | nil`: nil with bot mode off or when I host no table; `asked = min(n or free, free)` of my free seats; one idle bot (`Bots:idle`) is invited every `FILL_AFTER` s while I host that table, no invitation of mine is pending and bots are left to ask (a bot is invited once my presence knows it). The header comment says both.
  - `wow/Slash.lua`: `/tavern bots fill [n]` (bots are switched on first, as for `host`): `ns.bots:fill(tonumber(n))`; nil → `L("bots.nofill")` = „Първо отвори маса, после напълни с ботове.“ (`Open a table first, then fill it with bots.`); `slash.help` names it.

- [ ] **Step 1: Write the tests.** `tests/core/holdem_table_test.lua` (appended; the three `Loader.lib` lines of `tests/core/wire_test.lua` go to the top of the file):

```lua
describe("holdem: what a full table costs", function()
  -- counts what the host whispered since `mark`, with the real wire format: whispers, bytes (packed + 40 of ChatThrottleLib), the biggest, the events W got
  local function cost(mark)
    local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
    local n, bytes, biggest, events = 0, 0, 0, 0
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      if m.from == N[1] and m.channel == "WHISPER" then
        local size = #wire:pack(m.msg) + 40; n = n + 1; bytes = bytes + size; biggest = math.max(biggest, size)
        if m.msg.t == "EV" then ok(m.msg.left == nil or m.msg.left == math.floor(m.msg.left), "left is whole seconds") end
        if m.msg.t == "EV" and m.target == W then events = events + 1 end
      end
    end
    return n, bytes, biggest, events
  end
  it("six players and one watcher: one hand played to the showdown stays inside the budget; a second watcher is refused", function()
    tableN(6); local w2 = sim:add("Втори Гледач"); sim:run(1)
    local refused = {}; w2:on("refused", function(t, why) refused[#refused + 1] = why end)
    w2:watch(tid); sim:run(1); eq({ cl[1].session.watchers, refused }, { 1, { "full" } })
    ok(cl[1]:startGame()); sim:run(1); local mark = #sim.sent; sim:run(2)                       -- the hand event comes 2 s after the start
    for _ = 1, 200 do
      local t = st().turn; if not t then if st().phase == "done" then break end; sim:run(1) else act(st().bet > st().p[t].bet and "call" or "check") end
    end
    eq({ st().phase, #st().last.shown, host().session.seq }, { "done", 6, 41 })                 -- 41 = the 9 events before the mark and the 32 after
    local n, bytes, biggest, events = cost(mark)
    eq(events, 32); ok(n <= 200, "whispers " .. n); ok(bytes <= 31000, "bytes " .. bytes)       -- expected 192 and about 29 000; the first green run writes the measured values here (never above these caps)
    ok(biggest - 40 <= 2 * 255, "one event is more than two addon message parts: " .. biggest) -- six distinct commits are about 260 packed; pin `eq(biggest, <measured>)`
    local s1 = cl[1].session; local d = s1.deadline; s1.deadline = s1.client.env.now() + 12.25; eq(s1:left(), 13); s1.deadline = d   -- the sim's clock is whole seconds: check the rounding itself
  end)
  it("an ordinary hand (three fold before the flop, three check it down) costs about half", function()
    tableN(6); ok(cl[1]:startGame()); sim:run(1); local mark = #sim.sent; sim:run(2)
    for _ = 1, 3 do act("fold") end
    for _ = 1, 200 do
      local t = st().turn; if not t then if st().phase == "done" then break end; sim:run(1) else act(st().bet > st().p[t].bet and "call" or "check") end
    end
    eq(st().phase, "done"); local n, bytes = cost(mark)
    ok(n <= 100, "whispers " .. n); ok(bytes <= 16500, "bytes " .. bytes)                      -- about 15 000; pinned to the measured value at the first green run
  end)
end)
```

`tests/core/bots_test.lua` (`setup()` and `mentions` are the file's):

```lua
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
```

`tests/wow/slash_test.lua`: `w:slash("bots fill")` with no table says `bots.nofill`; after `w.ns.client:openTable{ game = "holdem", access = "invite", turn = 45 }` and `w:slash("bots fill 2"); w:advance(6)` the session has three seats taken.

- [ ] **Step 2: Run `bash t.sh tests/core/holdem_table_test.lua tests/core/bots_test.lua tests/wow/slash_test.lua`.** Expected: FAIL (the second watcher is let in; `Session:left()` is fractional; the bot table stays at two seats; `bots.fill` is nil).
- [ ] **Step 3: Implement.** If the budget test fails, the fix is in what is sent (Tasks 2–4) or in the seat count, never in the caps (six seats and one watcher are PE11's fallback; the numbers of Global "Volume" are the pinned design limit).
- [ ] **Step 4: Run the three files, then `bash t.sh`.** Expected: `29 passed, 0 failed` in the table file; all pass. `wc -l core/Session.lua` is 539.
- [ ] **Step 5: Commit.** `git add core/Bots.lua core/Session.lua wow/Slash.lua locale/bg.lua locale/en.lua tests/core/holdem_table_test.lua tests/core/bots_test.lua tests/wow/slash_test.lua` — `feat: bots fill a Холдем table; six seats, one watcher, whole-second clock; the message budget of a full ring pinned`

**— End of E1. Boundary check before E2: `bash t.sh` green, the Review Focus tests of Tasks 1–4 exist and pass. E2 changes no rule and no message of Tasks 1–5. —**

---

# Part E2 — the table, the rules book

### Task 6: A big table: the frame, the ring of six, the book's line, option names

**Files:**
- Modify: `core/HallLayout.lua`, `ui/TableFrame.lua`, `ui/TablePanels.lua`, `ui/Widgets.lua`, `ui/NewTableDialog.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/core/hall_layout_test.lua`, `tests/ui/table_test.lua`

**Interfaces:**
- Produces:
  - `HallLayout.ring(6, w, h, me)`: plates 150 wide, by `k = (seat − me) % 6`: `0 → ((w − 150) / 2, −(h − 52))`; `1 → (10, −(h − 140))`; `2 → (10, −80)`; `3 → ((w − 150) / 2, −10)`; `4 → (w − 160, −80)`; `5 → (w − 160, −(h − 140))`; one row. Four seats as before, any other count (nine included: nine seats wait for a later stage) the grid.
  - `ui/TableFrame.lua`: a view may have `size = {w, h}` (Hold'em: `{760, 532}`, so the felt is 732 × 440: `areaH = H − 92`); `render` sizes the frame to it (else to `WIDTH`, `HEIGHT`) whenever the game shown changes: the frame, the wood's texture coordinates (as `NewTableDialog`'s `resize`), `v.areaW`, `v.areaH`, the felt's size, the banner's and the fairness line's width. The header comment says so.
  - `ui/TablePanels.lua` (the fairness-line code moved there by Task 0): `TableFrame.panels.renderFair`: when `ns.Deal.status(s)` and `ns.Dice.status(s)` are both nil, `key, tone, arg, arg2 = ns.Book.status(s)` draws the line as a dice line is drawn (`L(key, arg, arg2)` in `Theme.rgb(tone)`); `TableFrame.panels.fairTooltip` prints `ns.Book.tip(s)` for such a session (`L(key, arg)` in the line's tone). Stage D's `L("dice.why." .. arg)` mapping of a tip's reason argument applies to `Dice.tip` lines only, never to `Book.tip`'s arguments (counts and names). Both are read at call time. The header comment says both.
  - `W.optionText(game, id, value)`: `L("optv." .. game .. "." .. id .. "." .. tostring(value))` when the locale has it, else `tostring(value)`; used for the choices of `ui/NewTableDialog.lua` and in `metaText`.
  - Locale (bg; en in brackets), a new section `-- Холдем: options and the book's line`: `opt.holdem.betting` = „Залагане“ (`Betting`); `opt.holdem.blinds` = „Блайндове“ (`Blinds`); `opt.holdem.stack` = „Стек“ (`Stack`); `optv.holdem.betting.nl` = „Без лимит“ (`No Limit`); `optv.holdem.betting.pl` = „Пот лимит“ (`Pot Limit`); `optv.holdem.blinds.10` … `.200` = „5/10“, „10/20“, „25/50“, „50/100“, „100/200“; `optv.holdem.stack.50`, `.100`, `.200` = „50 ГБ“, „100 ГБ“, „200 ГБ“ (`50 BB` …); `seal.sealed` = „Ръце за проверка при затварянето: %d · вече проверени: %d“ (`Hands to check at the close: %d · checked so far: %d`); `seal.ok` = „Всичките %d ръце са проверени“ (`All %d hands checked`); `seal.open` = „Непроверени ръце: %d. %s не остави ключа си“; `seal.bad` = „Нередовни ръце: %d“; `seal.tip` = „В Холдем разбъркването се показва чак при затварянето на масата, за да не се видят картите на отказалите се. Дотогава всяка ръка стои запечатана. Накрая аддонът ги проверява всичките наведнъж.“; `seal.tip.bad` = „Нередовни ръце: %d. Показана е карта, която не е от тестето. Кажи на останалите.“; `seal.tip.open` = „%s си тръгна, без да остави ключа си. Ръцете с него не могат да се проверят.“

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/core/hall_layout_test.lua
it("six seats around a big felt, mine at the bottom, the next at my left", function()
  local spots, rows = L.ring(6, 732, 440, 1); eq(rows, 1)
  eq(spots, { { 291, -388, 150 }, { 10, -300, 150 }, { 10, -80, 150 }, { 291, -10, 150 }, { 572, -80, 150 }, { 572, -300, 150 } })
  local r = L.ring(6, 732, 440, 4); eq({ r[4], r[5], r[3], r[1] }, { { 291, -388, 150 }, { 10, -300, 150 }, { 572, -300, 150 }, { 291, -10, 150 } })
  eq(L.ring(4, 532, 328, 1)[1], { 183.5, -276, 165 }); local _, g = L.ring(9, 732, 440, 1); ok(g > 1, "nine seats are a grid again")
end)
-- tests/ui/table_test.lua
it("a view with a size gets its own frame and felt; another game puts the frame back", function()
  --[[ guildWow(); TableFrame.registerView("holdem", { size = { 760, 532 }, ring = true, build = <a plain frame>, update = function() end });
  client:openTable{ game = "holdem", access = "guild", turn = 45 }; w:render(): { TableFrame.frame:GetSize() } == { 760, 532 };
  { v.areaW, v.areaH } == { 732, 440 }; six plates shown, v.plates[1].frame.points[1] == { "TOPLEFT", v.area, "TOPLEFT", 291, -388 },
  v.plates[2] at 10, -300, v.plates[3] at 10, -80, v.plates[4] at 291, -10, v.plates[6] at 572, -300, v.plates[7] is nil, every plate 150 wide; v.fairLine is 692 wide;
  v.meta reads „Всеки от гилдията · … · Залагане Без лимит · Блайндове 5/10 · Стек 100 ГБ“.
  client:stand(); client:openTable{ game = "ttt", … }; w:render(): the frame is 560 x 420 again and v.areaW == 532 ]]
end)
it("the book's line under the felt and its tooltip; the dialog names the option values", function()
  --[[ at a Холдем table, with w.ns.Book.status returning in turn "seal.sealed", "inkDim", 12, 3; "seal.ok", "good", 15; "seal.open", "gold", 4, A;
  "seal.bad", "red", 1: the line reads „Ръце за проверка при затварянето: 12 · вече проверени: 3“, „Всичките 15 ръце са проверени“,
  „Непроверени ръце: 4. Иван Петров не остави ключа си“, „Нередовни ръце: 1“, each in Theme.rgb of its tone; with w.ns.Book.tip returning
  { { "ink", "seal.tip" }, { "gold", "seal.tip.open", A } } the tooltip's second line is „Иван Петров си тръгна, без да остави ключа си. Ръцете с него не могат да се проверят.“;
  a Сантасе table still reads ns.Deal.status. NewTableDialog for "holdem": #w:texts("Без лимит") == 1, #w:texts("5/10") == 1, #w:texts("100 ГБ") == 1 ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/hall_layout_test.lua tests/ui/table_test.lua`.** Expected: FAIL (six seats come back as a grid; the frame is 560 wide).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: all pass (the locale key sets of bg and en are identical). `wc -l ui/TableFrame.lua` is below 600 (about 520 with the frame size; the book branch is in `ui/TablePanels.lua`).
- [ ] **Step 5: Commit.** `git add core/HallLayout.lua ui/TableFrame.lua ui/TablePanels.lua ui/Widgets.lua ui/NewTableDialog.lua locale/bg.lua locale/en.lua tests/core/hall_layout_test.lua tests/ui/table_test.lua` — `feat(ui): a table frame a view can size, six plates in a ring, the book's line, option values by name`

### Task 7: Table textures

**Files:**
- Modify: `tools/gen_textures.py`, `ui/Theme.lua`; Create: `media/oval.tga`, `media/chip.tga`; Test: `tests/ui/theme_test.lua`

**Interfaces:**
- Produces: `Theme.texSize.oval = {512, 256}`, `chip = 32` (and `Theme.tex.oval`, `.chip`).
- Drawing (the file's `cover`, `sd_circle` and an ellipse distance of the same kind): `oval` = an ellipse filling 512 × 256: a rim 14 px wide in the wood colours (`#4a2c1a` to `#2e190e`), a brass line 3 px (`#b0813f`) inside it, the inside a radial felt (`#8d2a30` at the centre to `#4d1216` at the line), transparent outside; `chip` = a disc of radius 14 in 32 × 32, `#f2c94c` with a 2 px rim `#8a5a10` and a dashed ring of radius 9 in `#7a5210` (eight dashes). Both entries are **appended** to `TEXTURES`.

- [ ] **Step 1: Write the failing test** (in the existing `it` of `tests/ui/theme_test.lua`): `eq(Theme.texSize.oval, { 512, 256 }); eq(Theme.texSize.chip, 32); ok(n >= 20)`.
- [ ] **Step 2: Run `bash t.sh tests/ui/theme_test.lua`.** Expected: FAIL (`oval` is nil).
- [ ] **Step 3: Implement**, then run `"C:\Users\daxx\AppData\Local\Python\bin\python.exe" tools/gen_textures.py`. Expected output ends with `media/oval.tga 512x256`, `media/chip.tga 32x32`, and `git status --short media` lists only those two files as new.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add tools/gen_textures.py ui/Theme.lua media/oval.tga media/chip.tga tests/ui/theme_test.lua` — `feat(media): the oval table and a chip for Холдем`

### Task 8: The Hold'em model

**Files:**
- Create: `ui/games/HoldemModel.lua`; Modify: `TavernGames.toc`; Test: `tests/ui/holdem_model_test.lua`

**Interfaces:**
- Consumes: `ns.Engines.holdem` (`legal`, `inHand`, `over`; the state fields `phase`, `hand`, `button`, `sbSeat`, `bbSeat`, `order`, `p`, `seats`, `board`, `deck`, `bet`, `bb`, `turn`, `last`, `closing`).
- Produces `ns.HoldemModel.build(s, want) -> model`. It reads only `s.state` (a view), `s.mySeat`, `s.status`, `s.role`, `s.seats`, `s.handNames` (a plain table will do) and `want` (the amount the view remembers, or nil). It stores nothing.
  - `me` = my seat, or 1 for a watcher; `seated`; `host` = `s.role == "host"`; `phase`, `hand`; `inHand = E.inHand(state)`; `closing = state.closing == true`; `over = E.over(state)`.
  - `board` = the faces of `state.board` in order (only dealt cards); `pot` = the sum of `p.total` over `state.order` while `inHand`, else 0.
  - `seats[i]` (nil for an empty chair) = `{name, chips, bet, st, cards, mark, turn, won, cat}`: `bet` = `p.bet` when in the hand and above 0; `st`, the first that fits: `"away"`; in the hand (`inHand` and `state.p[i]` not gone) `"folded"`, `"allin"`, `"in"`; `"out"` with 0 chips; `"wait"` while a hand runs without the seat; else `"ready"`. `cards`: nil without a `p[i]` of the current or the last hand, nil for a folded seat that is not mine; else `{f1 or false, f2 or false}` from the view (false = face down). `mark`: `"D"` on the button, else `"sb"`, `"bb"` (nil before the first hand). `turn` = live and `state.turn == i`. After a hand (`not inHand`, `state.last` of this hand, not void): `won = last.won[i]`, `cat = last.cat[i]`.
  - `mine` = seated, live, `state.turn == me`. Only then: `act` from `E.legal(state, me)`: `fold = true`; `check = true` or `call = min(toCall, my chips)`; `raise = {k, min, max}` from the `bet`/`raise` entry; `allin = my bet + my chips` when `{k="allin"}` is legal. With `act.raise`: `to = clamp(want or min)`, `half = clamp(state.bet + floor((pot + toCall) / 2))`, `potTo = clamp(state.bet + pot + toCall)` (`clamp` to `[min, max]`), `step = state.bb`.
  - `text = {key, …}`, the first that applies: `over` → `{"holdem.closed"}`; a void last hand, not `inHand` → `{"holdem.void"}`; not `inHand` with `last` of this hand → one main-pot winner without a showdown `{"holdem.wonFold", name, amount}`, with one `{"holdem.won", name, amount, cat}`, several `{"holdem.split", amount, cat}` (`amount` = what the first winner of the first pot won in all); not `inHand` → `{"holdem.waiting"}`; phase `"deal"` → `{"holdem.shuffling"}`; my own seat away → `{"holdem.away"}`; `mine` → `{"holdem.toCall", n}` or `{"holdem.yourTurn"}`; a seat on turn → `{"holdem.waitFor", name}`; else nil. `note` = `{"holdem.closing"}` while `closing` and not `over`. `log` = for the last finished hand `{"holdem.log", n, name, amount, cat}`, `{"holdem.logFold", n, name, amount}`, `{"holdem.logSplit", n, amount, cat}` or `{"holdem.logVoid", n}`; nil before one. A name is `s.handNames[seat]`, else `s.seats[seat]`, else `"?"`.

- [ ] **Step 1: Write the failing tests.** File scope: `guildWow()` as in the other UI tests; `M, E = w.ns.HoldemModel, w.ns.Engines.holdem`; `hand3(opt, stacks)` = `E.new{ seats = { true, true, true }, opt = opt }`, the stacks set, then `{k="hand"}` and `{k="deal", deck = E.DECK}` (seat 2 holds 2C 5C, seat 3 3C 6C, seat 1 4C 7C; the board comes 9C TC JC, KC, 2D); `sess(st, seat)` = `{ game = "holdem", status = "live", mySeat = seat, role = seat == 1 and "host" or "player", seats = { A, B, C, false, false, false }, state = E.view(st, seat or 0) }`; `build(st, seat, want)` = `M.build(sess(st, seat), want)`; `try(st, seat, a)` = `E.apply(E.restore(E.snapshot(st)), seat, a)`.

```lua
it("the table from my seat: stacks, bets, marks, my two cards, what I may do", function()
  local st = hand3(); local m = build(st, 1)
  eq({ m.me, m.seated, m.host, m.mine, m.hand, m.pot, m.board, m.phase, m.inHand }, { 1, true, true, true, 1, 15, {}, "bet", true })
  eq(m.seats[1], { name = A, chips = 1000, st = "in", cards = { "4C", "7C" }, mark = "D", turn = true })
  eq(m.seats[2], { name = B, chips = 995, bet = 5, st = "in", cards = { false, false }, mark = "sb", turn = false })
  eq(m.seats[3], { name = C, chips = 990, bet = 10, st = "in", cards = { false, false }, mark = "bb", turn = false }); eq(m.seats[4], nil)
  eq(m.act, { fold = true, call = 10, raise = { k = "raise", min = 20, max = 1000 }, allin = 1000 }); eq({ m.to, m.half, m.potTo, m.step }, { 20, 22, 35, 10 })
  eq({ build(st, 1, 500).to, build(st, 1, 5000).to, build(st, 1, 3).to, m.text }, { 500, 1000, 20, { "holdem.toCall", 10 } })
  m = build(st, 2); eq({ m.mine, m.act, m.to, m.seats[2].cards, m.seats[1].cards, m.text }, { false, nil, nil, { "2C", "5C" }, { false, false }, { "holdem.waitFor", A } })
  m = build(st, nil); eq({ m.me, m.seated, m.mine, m.seats[1].cards, m.seats[3].cards }, { 1, false, false, { false, false }, { false, false } })
end)
it("Pot Limit: the biggest raise the buttons offer is the engine's cap; no „Ва банк“ above it", function()
  local st = hand3{ betting = "pl" }; local m = build(st, 1)
  eq(m.act, { fold = true, call = 10, raise = { k = "raise", min = 20, max = 35 } }); eq({ m.to, m.half, m.potTo, build(st, 1, 999).to }, { 20, 22, 35, 35 })
  ok(try(st, 1, { k = "raise", to = m.potTo })); eq({ try(st, 1, { k = "raise", to = m.potTo + 1 }) }, { nil, "amount" }); eq({ try(st, 1, { k = "allin" }) }, { nil, "amount" })
  E.apply(st, 1, { k = "raise", to = 35 }); m = build(st, 2)
  eq(m.act, { fold = true, call = 30, raise = { k = "raise", min = 60, max = 115 } }); eq({ m.half, m.potTo }, { 75, 115 }); ok(try(st, 2, { k = "raise", to = 115 }))
  m = build(hand3(nil, { [1] = 15 }), 1); eq({ m.act, m.to, m.potTo }, { { fold = true, call = 10, allin = 15 }, nil, nil })      -- too short to raise: all-in only
  eq(build(hand3(nil, { [1] = 8 }), 1).act, { fold = true, call = 8 })
end)
it("the buttons agree with the engine on random states", function()
  --[[ the fuzz loop of tests/engines/holdem_test.lua (its LCG seeded 20261124; 60 hands, No Limit and Pot Limit alternating, 2-6 seats): at every
  state with a seat on turn, m = build(st, seat): m.act.raise is nil exactly when E.legal has no bet/raise entry, else its k, min, max are that
  entry's k, to, max; m.act.allin is set exactly when { k = "allin" } is legal; try() accepts { k = raise.k, to = x } for x = m.to, m.half, m.potTo
  and refuses to = raise.max + 1; then the engine's own random legal action is applied. At least 300 states with a raise were checked ]]
end)
it("the flop, a bet to face, the showdown and the log", function()
  local st = hand3(); E.apply(st, 1, { k = "call" }); E.apply(st, 2, { k = "call" }); E.apply(st, 3, { k = "check" }); E.apply(st, 0, E.system(st))
  local m = build(st, 2); eq({ m.board, m.pot, m.mine, m.act, m.text }, { { "9C", "TC", "JC" }, 30, true, { fold = true, check = true, raise = { k = "bet", min = 10, max = 990 }, allin = 990 }, { "holdem.yourTurn" } })
  E.apply(st, 2, { k = "bet", to = 20 }); m = build(st, 3)
  eq({ m.act.call, m.act.raise, m.half, m.potTo, m.seats[2].bet, m.pot }, { 20, { k = "raise", min = 40, max = 990 }, 55, 90, 20, 50 })
  E.apply(st, 3, { k = "fold" }); E.apply(st, 1, { k = "call" }); m = build(st, 2)
  eq({ m.seats[3].st, m.seats[3].cards, build(st, 3).seats[3].cards }, { "folded", nil, { "3C", "6C" } })                    -- a folded seat has no cards; I still see my own
  while st.phase ~= "done" do if st.phase == "bet" then E.apply(st, st.turn, { k = "check" }) else E.apply(st, 0, E.system(st)) end end
  m = build(st, 3); eq({ m.board, m.pot, m.inHand, m.seats[1].cards, m.seats[2].cards, m.seats[3].cards }, { { "9C", "TC", "JC", "KC", "2D" }, 0, false, { "4C", "7C" }, { "2C", "5C" }, { "3C", "6C" } })
  eq({ m.seats[1].won, m.seats[1].cat, m.seats[2].won, m.text, m.log }, { 70, 6, nil, { "holdem.won", A, 70, 6 }, { "holdem.log", 1, A, 70, 6 } })
  eq(build(st, nil).seats[3].cards, nil)                                                                                     -- a watcher never saw the folded hand
end)
it("an unshown hand lies face down; a newcomer waits for the next hand; away, out, void and the close in words", function()
  local st = hand3(); E.apply(st, 0, { k = "join", seat = 5 }); local s = sess(st, 5); s.seats[5] = "Нади Колева"; local m = M.build(s)
  eq({ m.seats[5].st, m.seats[5].cards, m.seats[5].chips, m.mine, m.text }, { "wait", nil, 1000, false, { "holdem.waitFor", A } })
  E.apply(st, 1, { k = "fold" }); E.apply(st, 2, { k = "fold" }); m = build(st, 1)
  eq({ m.text, m.log, m.seats[3].cards, m.seats[3].won }, { { "holdem.wonFold", C, 10 }, { "holdem.logFold", 1, C, 10 }, { false, false }, 10 })
  --[[ a seat with away = true: st "away", and on its own client text { "holdem.away" }; chips 0 between hands: "out"; one playing seat: { "holdem.waiting" };
  phase "deal": { "holdem.shuffling" }; after { k = "void" }: text { "holdem.void" }, log { "holdem.logVoid", 1 }; { k = "close" } in a hand: note
  { "holdem.closing" }; once closed: text { "holdem.closed" }, over == true; two winners of the main pot: { "holdem.split", amount, cat };
  a leaver's name comes from s.handNames when s.seats[seat] is false ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/holdem_model_test.lua`.** Expected: FAIL (`HoldemModel` is nil).
- [ ] **Step 3: Implement**; TOC line `ui/games/HoldemModel.lua` after `ui/games/TablaView.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `5 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add ui/games/HoldemModel.lua TavernGames.toc tests/ui/holdem_model_test.lua` — `feat(ui): the Холдем table as a pure model`

### Task 9: The Hold'em view

**Files:**
- Create: `ui/games/HoldemView.lua`; Modify: `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`; Test: `tests/ui/holdem_test.lua`

**Interfaces:**
- Consumes: `ns.HoldemModel.build`, `ns.HallLayout.ring`, `ns.Cards.card`, `client:act`, `ns.Cash.close`, `TableFrame.registerView`, `W.GoldButton`, `W.GhostButton`, `W.Label`, `W.colored`, the textures of Task 7.
- Produces: `TableFrame.registerView("holdem", View)` with `View.ring = true`, `View.size = {760, 532}`, `View.build(parent)` (a frame over the whole felt, 732 × 440), `View.update(f, s)`, `View.seatNote(s, seat)` = the seat's chips as a number, or `L("holdem.note.away")`, `L("holdem.note.out")`, `L("holdem.note.wait")` for those states, `""` without a state or a player. The frame exposes `oval`, `board[1..5]`, `pot`, `text`, `note`, `log`, `seat[1..6]` = `{cards = {c1, c2}, bet, chip, mark}`, `foldButton`, `callButton`, `raiseButton`, `minusButton`, `plusButton`, `halfButton`, `potButton`, `allinButton`, `closeButton`, and its memory `want`.
- `View.update` stores `f.session = s`; `f.want` is forgotten whenever the key `tid/epoch/seq` changes; it draws `M.build(s, f.want)`.
- Drawing (Global Constraints, the table; `k = (seat − model.me) % 6`):
  - `oval` 456 × 236 at `(138, −97)`. `board[j]`: cards 40 × 58 at `(254 + 46 × (j − 1), −176)`, shown for the dealt ones. `pot` = `L("holdem.pot", model.pot)`, gold 14, centred on `(366, −156)`, shown while `pot > 0`. `text` heading 14 centred on `(366, −250)`, gold after a hand; a name in it is class-coloured, a category is `L("holdem.cat." .. cat)`. `note` dim 11 at `(366, −232)`, 200 wide with word wrap, centred (clear of the bet labels of k = 1 and 5 at `(250/482, −272)`).
  - `seat[i].cards`: for `k = 0` two cards 40 × 58 at `(323, −322)` and `(369, −322)`; for the others two `Cards.card(f, 0.6)` at the table's `cards` offset and 26 right of it. Hidden without `model.seats[i].cards`; a `false` face is the card's back; a face is drawn **only** where the model has one. A folded seat of mine: my cards at alpha 0.5.
  - `seat[i].chip` (the `chip` texture 16 × 16) and `seat[i].bet` (ui 12, gold, right of it) centred on the table's `bet` offset: the bet while `model.seats[i].bet`; after a hand `„+N“` in `good` for `won`. `seat[i].mark` 18 × 18 centred on `(plate.x + 138, plate.y)`: the `chip` texture tinted `cream` with „D“ on the button; the text of `holdem.sb` / `holdem.bb` (dim 10) on the blinds.
  - Buttons (shown only when `model.mine`; every ghost button is `W.GhostButton(parent, text, "brassLight", onClick)`, the colour argument as in stage D Task 4): `halfButton` (ghost 64 × 22) at `(476, −336)`, `potButton` (ghost 64 × 22) at `(546, −336)`, `allinButton` (ghost 96 × 22) at `(616, −336)`, `minusButton` and `plusButton` (ghost 24 × 24) at `(476, −362)` and `(596, −362)`, `foldButton` (ghost 70 × 26) at `(476, −388)`, `callButton` (gold 86 × 26) at `(550, −388)`, `raiseButton` (gold 86 × 26) at `(640, −388)`. The three rows (−336, −362, −388) are clear of the small cards and plate of k = 5 (516–722 × 296–330.8) and of the fairness line (416–434 on a 440 felt). `callButton` reads `L("holdem.check")` or `L("holdem.call", n)`; `raiseButton` reads `L("holdem.bet", to)` or `L("holdem.raise", to)`; without `model.act.raise` the raise row is hidden (`raiseButton`, `minusButton`, `plusButton`, `halfButton`, `potButton`); `allinButton` reads `L("holdem.allin", n)` and is hidden without `model.act.allin`.
  - `closeButton` (ghost 96 × 22, `L("holdem.close")`) at `(12, −366)`: the host of a live game that is neither closing nor over. `log` dim 11 at `(12, −396)`, 270 wide, left: `L(model.log…)`.
- Clicks (each redraws): `minusButton` / `plusButton`: `f.want = clamp(model.to ∓ model.step)`; `halfButton`: `f.want = model.half`; `potButton`: `f.want = model.potTo`. `foldButton` → `client:act({k="fold"})`; `callButton` → `{k="check"}` or `{k="call"}`; `raiseButton` → `{k = model.act.raise.k, to = model.to}`; `allinButton` → `{k="allin"}`. After an action that was accepted the buttons are dead until the next event (`f.sent`, cleared with `f.want`). `closeButton` → `ns.Cash.close(ns.client)`.
- Locale (bg; en in brackets), a new section `-- Холдем` after the Табла section: `holdem.fold` = „Пас“ (`Fold`); `holdem.check` = „Чек“ (`Check`); `holdem.call` = „Плащам %d“ (`Call %d`); `holdem.bet` = „Залагам %d“ (`Bet %d`); `holdem.raise` = „Вдигам до %d“ (`Raise to %d`); `holdem.allin` = „Ва банк %d“ (`All-in %d`); `holdem.half` = „½ пот“ (`½ pot`); `holdem.potB` = „Пот“ (`Pot`); `holdem.close` = „Приключи“ (`End game`); `holdem.pot` = „Пот %d“ (`Pot %d`); `holdem.sb` = „МБ“ (`SB`); `holdem.bb` = „ГБ“ (`BB`); `holdem.note.away` = „настрана“; `holdem.note.out` = „без чипове“; `holdem.note.wait` = „от следващата“; `holdem.cat.1` … `.9` = „висока карта“, „двойка“, „две двойки“, „тройка“, „кента“, „флош“, „фул хаус“, „каре“, „кент флош“; `holdem.yourTurn` = „Твой ход“; `holdem.toCall` = „Твой ход: %d за плащане“; `holdem.waitFor` = „Изчакай %s…“; `holdem.shuffling` = „Разбъркваме заедно…“; `holdem.waiting` = „Чакаме втори играч с чипове“; `holdem.away` = „Седиш настрана. Връщаш се от следващата ръка.“; `holdem.won` = „%s взе %d с %s“; `holdem.wonFold` = „%s взе %d. Останалите се отказаха.“; `holdem.split` = „Потът се дели: по %d с %s“; `holdem.void` = „Ръката е анулирана. Залозите са върнати.“; `holdem.closing` = „Последна ръка: след нея играта приключва.“; `holdem.closed` = „Играта приключи. Аддонът проверява ръцете.“; `holdem.log` = „#%d %s взе %d с %s“ (`#%d %s won %d with %s`); `holdem.logFold` = „#%d %s взе %d без показване“; `holdem.logSplit` = „#%d потът се раздели: по %d с %s“; `holdem.logVoid` = „#%d анулирана“. Where no English is pinned it is a faithful translation.

- [ ] **Step 1: Write the failing tests.** `tests/ui/holdem_test.lua`, file scope: `setup()` = `guildWow()`, a parent frame of 732 × 440 under `UIParent`, `f = View.build(parent)`, `w.ns.client.act` replaced by a stub that records the action in `acts` and returns true; returns `w, View, f, acts`. `hand3` and `sess` as in Task 8 plus `tid = "t#1", epoch = 1, seq = 1`; `draw(f, st, seat)` = `View.update(f, sess(st, seat))`. `faces(seatWidget)` = for its two cards `"-"` when hidden, `"back"` when face down, else the face.

```lua
it("six places from my seat; the view draws a face only where the model has one", function()
  local w, View, f = setup(); local st = hand3(); draw(f, st, 1)
  eq({ { f:GetSize() }, View.ring, View.size }, { { 732, 440 }, true, { 760, 532 } }); eq(f.oval.points[1], { "TOPLEFT", f, "TOPLEFT", 138, -97 })
  eq({ faces(f.seat[1]), faces(f.seat[2]), faces(f.seat[3]), faces(f.seat[4]) }, { { "4C", "7C" }, { "back", "back" }, { "back", "back" }, { "-", "-" } })
  eq({ f.seat[1].cards[1].points[1], f.seat[2].cards[1].points[1], f.seat[2].cards[2].points[1] },
     { { "TOPLEFT", f, "TOPLEFT", 323, -322 }, { "TOPLEFT", f, "TOPLEFT", 166, -296 }, { "TOPLEFT", f, "TOPLEFT", 192, -296 } })
  eq({ f.seat[2].bet:GetText(), f.seat[3].bet:GetText(), f.seat[1].bet:IsVisible(), f.pot:GetText(), f.board[1]:IsVisible() }, { "5", "10", false, "Пот 15", false })
  eq({ f.seat[1].mark:IsVisible(), #w:texts("МБ"), #w:texts("ГБ") }, { true, 1, 1 })
  eq({ View.seatNote(sess(st, 1), 2), View.seatNote(sess(st, 1), 4), View.seatNote(sess(nil, 1), 1) }, { "995", "", "" })
  draw(f, st, 3); eq({ faces(f.seat[3]), faces(f.seat[1]), f.seat[3].cards[1].points[1] }, { { "3C", "6C" }, { "back", "back" }, { "TOPLEFT", f, "TOPLEFT", 323, -322 } })
  draw(f, st, nil); eq({ faces(f.seat[1]), faces(f.seat[2]), f.foldButton:IsVisible(), f.closeButton:IsVisible() }, { { "back", "back" }, { "back", "back" }, false, false })
end)
it("„Пот“ and „+“ never leave the engine's range; the raise button sends what it shows", function()
  local w, View, f, acts = setup(); local st = hand3{ betting = "pl" }; draw(f, st, 1)
  eq({ f.callButton.text:GetText(), f.raiseButton.text:GetText(), f.allinButton:IsVisible(), f.potButton:IsVisible() }, { "Плащам 10", "Вдигам до 20", false, true })
  w:click(f.plusButton); eq({ f.want, f.raiseButton.text:GetText() }, { 30, "Вдигам до 30" }); w:click(f.plusButton); w:click(f.plusButton); eq(f.want, 35)
  w:click(f.minusButton); eq(f.want, 25); w:click(f.halfButton); eq(f.want, 22); w:click(f.potButton); eq({ f.want, f.raiseButton.text:GetText() }, { 35, "Вдигам до 35" })
  w:click(f.raiseButton); eq(acts, { { k = "raise", to = 35 } }); ok(E.apply(st, 1, acts[1])); eq({ f.raiseButton:IsEnabled(), f.foldButton:IsEnabled() }, { false, false })
  local s = sess(st, 2); s.seq = 2; View.update(f, s); eq({ f.want, f.callButton.text:GetText(), f.raiseButton.text:GetText() }, { nil, "Плащам 30", "Вдигам до 60" })
  w:click(f.callButton); eq({ acts[2], #acts, f.foldButton:IsEnabled() }, { { k = "call" }, 2, false })   -- sent: the buttons are dead until the event is back
end)
it("No Limit: „Ва банк“ sends all-in; a short stack has no raise row; check when nothing is owed", function()
  --[[ hand3() drawn for seat 1: allinButton reads „Ва банк 1000“, a click sends { k = "allin" }. hand3(nil, { [1] = 15 }): raiseButton, plusButton,
  minusButton, halfButton and potButton hidden, allinButton „Ва банк 15“, callButton „Плащам 10“. After call, call: seat 3's callButton reads „Чек“ and
  sends { k = "check" }; on the flop seat 2's raiseButton reads „Залагам 10“ and sends { k = "bet", to = 10 } ]]
end)
it("after the showdown: the shown hands, what was won, the words and the log; a folded hand stays down for a watcher", function()
  --[[ the hand of Task 8's fourth test played to the end, drawn for seat 3 (folded): faces of seats 1 and 2 are their cards, seat 3's own at alpha 0.5;
  board 9C TC JC KC 2D visible; f.seat[1].bet reads „+70“; text „Иван Петров взе 70 с флош“; log „#1 Иван Петров взе 70 с флош“; pot hidden.
  Drawn for a watcher: faces(f.seat[3]) == { "-", "-" } ]]
end)
it("the host's „Приключи“; solo with bots from a real deal", function()
  --[[ a live state drawn for the host (seat 1): closeButton visible; with w.ns.Cash.close stubbed a click calls it with the client; drawn for seat 2:
  hidden; a closing state: hidden for the host too and f.note reads „Последна ръка: след нея играта приключва.“.
  withBots(); I open Холдем „Само поканени“, w.ns.bots:fill(2), w:advance(6), TableFrame.startGame(), w:advance(4): V = TableFrame.built.holdem,
  TableFrame.frame is 760 x 532, my two cards are faces, the bots' are backs, TableFrame.view.info.topic == "holdem"; when it is my turn a click on
  V.callButton moves the game on (client.session.seq grows); after eight hands of w:advance with my clicks no script error and the line under the
  felt reads „Ръце за проверка при затварянето: …“ ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/holdem_test.lua`.** Expected: FAIL (no view registered for `holdem`).
- [ ] **Step 3: Implement**; TOC line `ui/games/HoldemView.lua` after `ui/games/HoldemModel.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `5 passed, 0 failed`; all pass (the locale key sets of bg and en are identical).
- [ ] **Step 5: Commit.** `git add ui/games/HoldemView.lua locale/bg.lua locale/en.lua TavernGames.toc tests/ui/holdem_test.lua` — `feat(ui): the Холдем table: six seats on an oval, bets, the board and the bet buttons`

### Task 10: Rules-book topic „Тексас Холдем“

**Files:**
- Modify: `core/Help.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/core/locale_help_test.lua`, `tests/ui/book_test.lua`

**Interfaces:**
- Produces:
  - `ns.Help.topics` ids `{"hall", "ttt", "deathroll", "santase", "belot", "tabla", "holdem", "fair", "soon"}`. Topic `holdem` (title `game.holdem`), blocks in this order: `p1`, `example` (kind `example`), `blinds`, `rounds` (kind `cards`, `{"AH", "JH", "7C", "QS", "2D"}`), `hands` (kind `cards`, `{"TS", "JS", "QS", "KS", "AS"}`), `sidepot` (kind `example`), `limits`, `seats`, `time`, `fair`. The topic `fair` gains a last block `{kind = "p", key = "help.fair.sealed"}` (after stage D's `help.fair.dice`). The quoted-label test also covers `^help%.holdem%.`.
- Locale: the `help.holdem.*` keys go in a new section `-- Rules book: Тексас Холдем` after `-- Rules book: Табла` in both files. Pinned bg (en = faithful translations in the same simple tone, quoting the English labels of Tasks 6 and 9):
  - `help.holdem.p1` = „Тексас Холдем е покер за двама до шестима души. Всеки получава две свои карти, а на масата се отварят пет общи. Печели най-добрата комбинация от пет карти измежду твоите две и общите пет. Печелиш и ако всички други се откажат. Играе се с чипове, без голд.“
  - `help.holdem.example` = „Киро отваря маса: „Без лимит“, блайндове „5/10“, стек „100 ГБ“. Сядат Нади и Иван и Киро натиска „Започни“. Всеки има по 1000 чипа. Мария идва по средата на ръка. Сяда веднага, но карти получава от следващата.“
  - `help.holdem.blinds` = „Преди картите двама души слагат задължителен залог. Играчът вляво от бутона „D“ слага малкия блайнд, следващият слага големия. Бутонът се мести с едно място наляво всяка ръка. Когато сте двама, малкият блайнд е на бутона.“
  - `help.holdem.rounds` = „Залага се четири пъти: с двете карти в ръка, после след първите три общи карти (флоп), след четвъртата (търн) и след петата (ривър). На свой ред избираш: „Пас“ и си вън от ръката, „Чек“, ако няма какво да плащаш, „Плащам“, или вдигаш.“
  - `help.holdem.hands` = „Комбинациите от слаба към силна: висока карта, двойка, две двойки, тройка, кента (пет поредни), флош (пет от една боя), фул хаус (тройка и двойка), каре, кент флош. При равни ръце потът се дели.“
  - `help.holdem.sidepot` = „Иван влиза ва банк със 100 чипа. Мария има 300, Киро 600. Основният пот е 300: по 100 от тримата. За него играят и тримата. Мария и Киро залагат още по 200 помежду си. Това е страничен пот от 400 и е само за тях двамата. Иван може да спечели най-много основния пот.“
  - `help.holdem.limits` = „„Без лимит“: можеш да заложиш всичките си чипове по всяко време с „Ва банк“. „Пот лимит“: най-много колкото е потът, след като платиш. Пример при блайндове 5/10: пръв си на ход, потът е 15, плащаш 10 и може да вдигнеш до 35. Бутонът „Пот“ слага точно толкова.“
  - `help.holdem.seats` = „Сядаш и ставаш, когато поискаш. Станеш ли по средата на ръка, картите ти се хвърлят, а заложеното остава в пота. Свършат ли ти чиповете, стоиш без карти. Стани и седни пак и получаваш нов стек. Домакинът натиска „Приключи“ и играта спира след текущата ръка.“
  - `help.holdem.time` = „Изтече ли времето ти, аддонът играе „Чек“, ако може, иначе „Пас“. Ако те няма, домакинът прави същото няколко секунди по-късно, а от следващата ръка сядаш настрана, докато се върнеш. След три минути без теб мястото ти се освобождава.“
  - `help.holdem.fair` = „Тестето се разбърква от всички в ръката, както в другите игри с карти. Разликата е в проверката. Ако разбъркването се показваше след всяка ръка, всички щяха да видят какво си хвърлил. Затова всеки пази един свой ключ до края. Който става, оставя ключа си. При „Приключи“ излизат всички ключове и аддонът проверява всяка ръка. Ако някой изчезне, без да остави ключа си, ръцете с него остават непроверени и надписът под масата го казва по име.“
  - `help.fair.sealed` = „В Холдем числата не се показват след всяка ръка, а чак при затварянето на масата. Иначе щяха да се видят картите на отказалите се. Дотогава надписът под масата брои запечатаните ръце. Аддонът на раздаващия и тук знае тестето на своята ръка, а раздаващият се сменя с бутона.“
  - `help.soon.p` = „Скоро идва игра на залог с тефтер на дълговете.“; `help.soon.example` = „Засега всички игри в кръчмата са за удоволствие: Морски шах, Death Roll, Сантасе, Белот, Табла и Тексас Холдем. Когато залозите станат готови, правилата им ще се появят тук, в книжката.“

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/core/locale_help_test.lua: topics are {"hall","ttt","deathroll","santase","belot","tabla","holdem","fair","soon"}; the holdem topic has
-- exactly two cards blocks, {"AH","JH","7C","QS","2D"} and {"TS","JS","QS","KS","AS"}, and two example blocks; the last block of the fair topic is
-- help.fair.sealed; the quoted-label loop also covers ^help%.holdem%. and finds at least 12 labels there in each language;
-- pinned: T.bg["help.holdem.limits"], T.bg["help.holdem.sidepot"], T.bg["help.holdem.fair"], T.bg["help.fair.sealed"], T.bg["help.soon.p"] equal the
-- strings above; T.en["holdem.fold"] == "Fold"; T.en["holdem.close"] == "End game"; T.en["optv.holdem.betting.pl"] == "Pot Limit";
-- T.en["seal.ok"] == "All %d hands checked".
-- tests/ui/book_test.lua
it("the Тексас Холдем topic is listed between Табла and the fair deal and draws its two rows of cards", function()
  --[[ the topic list reads …, "tabla=Табла", "holdem=Тексас Холдем", fair, soon; B.open("holdem"): the page's blocks of kind "cards" are two, with
  five cards each; HelpBook.current == "holdem"; B.open("fair"): the last block's text is L("help.fair.sealed") ]]
end)
```

Existing tests to change: the topic lists and titles in `tests/core/locale_help_test.lua` and `tests/ui/book_test.lua` gain Тексас Холдем (the index of `fair` in `book_test` moves by one).

- [ ] **Step 2: Run `bash t.sh tests/core/locale_help_test.lua tests/ui/book_test.lua`.** Expected: FAIL (the topic is missing; `help.soon.p` still names Тексас Холдем).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add core/Help.lua locale/bg.lua locale/en.lua tests/core/locale_help_test.lua tests/ui/book_test.lua` — `feat(ui): rules-book topic for Тексас Холдем`

### Task 11: In-game check list and documentation

**Files:**
- Create: `docs/superpowers/notes/2026-11-stageE-ingame-checks.md`; Modify: `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` (`### Shared contracts`: a subsection „Stage E additions“), `docs/superpowers/notes/engine-contract.md` („Addendum 7 (stage E, Холдем)“)

**Interfaces:** none. The notes file holds the table below with a `Result` column, every row `not yet measured`. Nothing is marked passed on the strength of the unit tests.

- [ ] **Step 1: `bash t.sh`.** Expected: `N passed, 0 failed`.
- [ ] **Step 2: Write the notes file** (`/console scriptErrors 1` throughout; rows 1–9 need one character, rows 10–19 two or three characters in different zones, row 20 as many guild members as can be found):

| # | Check | What to look for |
|---|---|---|
| 1 | `/tavern bots`, open Холдем „Само поканени“, `/tavern bots fill 5`, „Започни“ | the dialog names „Без лимит“ / „Пот лимит“, „5/10“ …, „100 ГБ“; the frame is the big one (760 × 532); six plates around the oval, mine at the bottom; my two cards face up, the bots' face down; „D“, „МБ“, „ГБ“ at the right seats |
| 2 | my turn | „Пас“, „Плащам N“ or „Чек“, „Вдигам до N“; „−“ / „+“ move the amount by a big blind; „½ пот“, „Пот“, „Ва банк N“; the clock runs on my plate |
| 3 | a Pot Limit table | no „Ва банк“ while my stack is above the pot; „Пот“ gives the biggest amount and it is accepted |
| 4 | a hand to the showdown | flop, turn and river come about a second apart; only the hands that went to the showdown turn face up; „+N“ at the winner; „X взе N с …“; the log line at the bottom left |
| 5 | everybody folds to one player | no card is shown; „… Останалите се отказаха.“ |
| 6 | an all-in with three stacks of different size | the pots are paid as the rules-book example says; the chips of all seats still add up |
| 7 | let my clock run out | „Чек“ when nothing is owed, else „Пас“; no script error |
| 8 | lose all chips; „Стани“ and sit again | „без чипове“ on my plate and no cards; after sitting again a fresh stack from the next hand |
| 9 | „Приключи“ as host | „Последна ръка…“; after the hand „Играта приключи…“; within some seconds the line under the felt reads „Всичките N ръце са проверени“ in green; „Нова игра“ starts with fresh stacks; ⓘ opens „Тексас Холдем“ |
| 10 | two characters in different zones | hands are dealt; each sees only its own cards; `/tavern debug` shows no face of the other player before a showdown and no `keys` line before a „Стани“ or the close |
| 11 | a third character sits in the middle of a hand | it sits at once with a stack, gets no cards, is dealt in the next hand; no red line on any client |
| 12 | a player presses „Стани“ in the middle of a hand | folded, its bet stays; `/tavern debug` on the others shows its `keys` line; the table goes on |
| 13 | a player's client is closed (not „Стани“) on its turn | the host plays check or fold about 7 s after its clock; at the next deal the table waits about 20 s once, then deals without it („настрана“ on its plate); back within three minutes it is dealt in again |
| 14 | the dealer (the button) `/reload`s in the middle of a hand | the hand goes on; the next street comes |
| 15 | the dealer's client is closed in the middle of a hand | about 20 s after the street is due: „Ръката е анулирана от …“, every bet back, the next hand is dealt without it |
| 16 | the host logs out | after about 75 s another player hosts and the hands go on; when that host presses „Приключи“ the line reads „Непроверени ръце: N. … не остави ключа си“ in amber; the same with the old host back in time: all checked |
| 17 | `/reload` as a player between two hands, then play on to the close | my seat, my stack and my cards come back; at the close the others still read all hands checked (my key survived) |
| 18 | a watcher from the start; a second one tries to come | the same board and bets, no cards but the shown ones, no buttons; the second gets „масата е пълна“ |
| 19 | the last but one player stands up | the table stops („Играта е прекъсната.“) and the host's line reads all hands checked |
| 20 | as many real players as possible (ideally six and one watcher; note what a seventh player or a second watcher would have cost), a quick hand in which many fold at once | with `/tavern debug`: events arrive in order on every client; note the delay between a click and the event on the farthest client (ChatThrottleLib); no disconnect, no „desync“ banner; note the frame rate while the book is checked at the close of a long game |
| 21 | the table at UI scale 0.65 and 1.0 | the small cards, the bets and the buttons are readable and do not overlap the plates or the line under the felt |

- [ ] **Step 3: Update the two documents**: the stage 1 plan's Shared contracts gets this plan's contract items under „Stage E additions“ (the engine's optional fields, the extension `cash` and the hooks `lapsed` and `leaving`, the action table, `SNP.fr.k`, the session fields, the events `"hand"` and `"book"`); `docs/superpowers/notes/engine-contract.md` gets Addendum 7 (stage E, Холдем): the eight rules of the sealed deal; `E.players`, `E.dealer` for Hold'em, `E.inHand`, `need = "faces"`; `void` for Hold'em (every chip back, the button moves on); `away`/`back`; `close` and `E.over`; `E.publicAuto` and `AUTO_GRACE` (amends PB5 and the forged rule of Addendum 3 for such an engine); the host's `sit` → `join`; `env.db.bookKeep` beside `fairKeep` (amends „never in SavedVariables“ once more); the design limit of the Global Constraints; what a sealed deal leaves open (rule 8).
- [ ] **Step 4: Report to the user** which rows need more than one character, the measured budget of a full table, and the decisions of the Self-review.
- [ ] **Step 5: Commit.** `git add docs/superpowers/notes/2026-11-stageE-ingame-checks.md docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md docs/superpowers/notes/engine-contract.md` — `docs: stage E in-game check list and contract additions`

---

## Self-review (applied)

- **Spec coverage:** 5.5 „минимум 2, максимум 9, сядаш и ставаш между ръцете“ → the maximum is **6** for now (decision 9) and Tasks 1–3 (a newcomer plays from the next hand, a leaver is folded); „блайндове, зададени при отваряне“ and the user's No Limit / Pot Limit and stack in big blinds → the engine's options, Task 6 names them; „от кого точно е дошъл всеки сребърник“ → not built (no money), but `state.last` and the `"hand"` event carry contributions and pots (Task 3); „Отпадане без „Стани“: след 3 минути“ → unchanged, with sitting out before it (Task 3); „Излизане на домакина: масата минава към следващия играч и не спира“ → Task 4, check list row 16; 6.3 „Изключение за Холдем“ → Tasks 2 and 4 (kept until the close; a leaver hands its key over; verification of all hands at the close), with the deviation named in decision 2; 5.3 „Валидните ходове се подчертават“ → Tasks 8–9 (only legal buttons, the engine's range); 5.3а → Task 10; 6.5 bots and trace → Task 5, rows 1, 10; roadmap „message volume“ → Task 5 and the Global Constraints; roadmap „dealer or host leaving mid-hand: hand void, bets returned“ → Tasks 1 and 3 (the dealer; a host that leaves is not the deck's holder unless it deals); rulings H1–H5 → the engine as merged; G1 → Task 2.
- **Verified before writing:** a prototype of Task 1's engine changes, of the edits to `core/Deal.lua`, `core/DealHooks.lua`, `core/Session.lua`, `core/Member.lua`, `core/Client.lua`, `core/Bots.lua` and of the whole `core/Book.lua` (219 lines) and `core/Cash.lua` (230 lines) was run in the simulator against `2c49161`. Every test of Tasks 1–5 in this plan is the test that passed there, with these values at nine seats and three watchers (the engine file: 51 passed; the table file: 18 passed; the two bot tests; the pre-flight rulings then moved the plan to 52 and 29 tests, six seats and one watcher, and distinct keys, so every deck-dependent literal is re-derived once, see Test conventions), and the rest of the suite stayed green except the three gate tests Task 2 lists. From those runs also: the budget numbers at nine seats and three watchers (503 whispers, 73 020 bytes, with the real serializer and deflate; the shipped six-seat figures of Global "Volume" are the pre-flight arithmetic from those runs, pinned by Task 5 at its first green run); twenty hands of nine players closed and checked `ok` on every client; one hundred hands of nine players are checked in 0.2 s under LuaJIT (the WoW client is slower: check list row 20). Not run: Task 0's moves, `Deal.status` in its new file, `Book.tip`, the slash command, `HallLayout.ring` for six, and everything in `ui/` (Tasks 6–10): their values come from the engine runs quoted in Task 8 and from the geometry table.
- **Decisions the plan makes beyond the spec (the user may contest):**
  1. **One table key a player instead of one seed a hand to publish.** Nine players times some hundred hands of seeds could not be published through the addon channel at the close; one key of 32 characters a player can. The per-hand commit and the seed sent to the dealer stay as in stage B.
  2. **A leaver's key is published at once, not kept by the host until the close.** It survives a host crash and reveals nothing while any player of a hand still holds its key; the price: a hand all of whose players have left can be read (by a modified client; the UI never shows it) while the table still runs.
  3. **A player who vanishes without its key leaves its hands „непроверени“, amber and by name, not red.** Stage B calls a missing reveal нередовна; here one disconnect would paint a whole night red. So a cheat who pulls the plug ends named and unverified, not proven.
  4. **Who stands up gets no verdict** unless it stays to watch; the others' check covers every public card and their own.
  5. **The host plays check/fold for a silent seat 7 s after its clock** (PB5 amended for Hold'em), and **a seat whose client does not answer the shuffle in 20 s sits out** until the client is back, instead of the table waiting three minutes.
  6. **A dealer whose client is gone costs the table that hand** (void after 20 s, every chip back), as the roadmap sketched; a `/reload` does not.
  7. **„Приключи“ is the host's**; the game also closes when only one player is left. A table whose players all vanish never closes: each client then keeps what it has checked so far.
  8. **Fresh stack by standing up and sitting down again** (H4); no rebuy button.
  9. **Six seats and one watcher at most** at a Hold'em table, a whole-second turn clock, and commits in one event: PE11's fallback, the design limit for ChatThrottleLib (a full ring about 29 KB a hand for the host, an ordinary hand about 15 KB). **Nine seats (the spec's maximum) and three watchers wait for a later message-budget stage**: at nine the same hand is about 73 KB, and 40 KB is arithmetically out of reach under `v=1`, one `EV` a member and no new message type (the fixed cost per whisper is about 120 bytes); that stage needs batched events or a new message type.
  10. **No slider**: „−“ / „+“ by a big blind and „½ пот“, „Пот“, „Ва банк“. **A bigger table frame** (760 × 532, felt 732 × 440) for this game only.
  11. Bots: check, call or fold by a simple strength of their cards, a raise in 40, 8 or 3 of a hundred turns; a bot host fills its table to six, `/tavern bots fill` fills mine to six.
  12. The fairness line during play counts sealed hands; green only after the close.
- **Step scan:** every task has tests with exact values, an expected failure, an implement step with files, signatures and pinned values, both run commands, and a commit with exact paths. Task 0 is a move with a size test. The tests of Tasks 6–10 that are written as comments name every value they assert.
- **Type and name consistency:** `E.players`, `E.dealer`, `E.inHand`, `need = "faces"`, `void`, `away`/`back`, `close`, `E.bot` in Tasks 1–3 and the contract; `Fair.handSeed(key, handId)` in Tasks 2 and 4; `{k="fair", op="commits"}`, `{k="book", op="step" | "key" | "keys"}` in Tasks 2–4 and the protocol table; `ns.Book` (`of`, `isKey`, `key`, `seedFor`, `seal`, `addKeys`, `check`, `run`, `close`, `snap`, `adopt`, `status`, `tip`) and `ns.Cash` (`submit`, `close`) in Tasks 2–6 and 9; book fields `rec`, `open`, `keys`, `seen`, `n`, `given`, `wait`, `sent`, `out`, `published`, `closed`, `final`, `missing`, `forged`; hooks `lapsed`, `leaving`; events `"hand"` (`n`, `last`, `chips`, `names`) and `"book"` (`hands`, `ok`, `bad`, `open`, `missing`); `Member.timedOut`; `Bots:fill`; `ns.HoldemModel.build(s, want)` with `me, seated, host, phase, hand, inHand, closing, over, board, pot, seats, mine, act, to, half, potTo, step, text, note, log` in Tasks 8–9; widget names of Task 9 in its tests; locale prefixes `holdem.`, `book.`, `optv.holdem.`, `help.holdem.`; topic id `holdem`.
- **Review Focus:** each of the five has named tests in Tasks 1–4, 8 and 9.
- **Proportion:** the core is given as rules, signatures and the tests that ran; the eight rules of the sealed deal are spelled out because what is revealed when is the whole point. The model's ladders and the view's geometry are written down because the tests alone do not determine them. E1 (Tasks 0–5) is complete and testable without any UI; E2 adds no protocol and no rule.
