# Tavern Games Stage F3 (Холдем за истинско злато) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A guild member opens a Холдем table „Със залог“: every player buys in for 40 to 100 big blinds of real gold and silver, the table keeps an exact record of who took how much from whom, and when a player cashes out, is stood up after three minutes offline, or the game is closed, the right pairs owe the right amounts in the guild ledger. The debtor's own client confirms by itself only what it saw whole, clean and checked against the published keys.

**Architecture:** The pairwise attribution matrix, the buy-ins and the settlement of a seat live in the **engine state** (a new pure file `engines/holdem_cash.lua`, used by `engines/holdem.lua` only when `opts.staked`), so every client computes them from the events it applied and a snapshot carries them. A new file `core/StakesCash.lua` wraps the hooks of F1's extension `stakes` for such an engine: no forfeit, a settlement note per out record of the state (through F1's `Book:outcome`), and a note that waits for the book's verdict. `core/CashOut.lua` holds the two client flows: my buy-in after my sit, and „Стани“ as a `cashout` event followed by the stand. Table parameters (blinds, betting, rebuy mode, turn length) are pinned in my stake note at acceptance.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), the stage 1 Ace3 subset, `core/Sha256.lua`, `bash t.sh`, `tests/helpers/sim.lua`, `tests/helpers/play.lua`, `tests/helpers/wow.lua`, `tests/helpers/frames.lua`.

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.4, 5.5, 5.6, 6.3, 6.4, 6.5, 6.6). Roadmap: `docs/superpowers/plans/2026-11-23-stakes-roadmap.md` (F3, its residual table E1–E10, "The one rule the whole stage rests on", conflict 6). What is built: `docs/superpowers/notes/engine-contract.md` Addenda 7 (the sealed deal), 8 (F1) and 9 (F2); Task 13 adds Addendum 10. Rulings log: `docs/superpowers/notes/2026-11-21-rulings.md` ("Stage E", "Stage F1", "Stage F2", "Accepted residuals").

**Stage F3 starts on `feature/games` at `e62ddc6` (1624 tests).** Names are binding; line numbers are from that commit and may move.

**Precondition, not met when this plan was written:** the rows of `docs/superpowers/notes/2026-11-stageF1-ingame-checks.md` and `2026-11-stageF2-ingame-checks.md` still read `not yet measured`. Nothing in F3 depends on a trade or mail answer. Residual S1 (below) needs the user's confirmation before staked card games are announced; F3 adds Холдем to that list.

## Pre-flight amendments

The pre-flight (`.superpowers/sdd/2026-11-25-stageF3-holdem-cash/preflight.md`) found 18 problems in the first version of this plan. The controller accepted every ruling as proposed; H10 became residual C9. Each landed in the task(s) named; the tag `(H<n>)` marks the place in the text.

| # | Severity | Ruling | Landed in |
|---|---|---|---|
| H1 | Critical | Money names come from the engine's own `who`, recorded in the out record (`rec.names`), never from the chair roster; my own sit reads the record whose `who` or `takenWho` is me | Task 3 (`rec.names`, tests), Task 5 (own sit, `s.cashNames` only for the rename check, clean-sit test), Task 7 (`cashPairs(rec)`, `S`, tests) |
| H2 | High | Any `stand` and any settlement drops the seat from `s.cashNames`; the rename check runs only on a snapshot identical to my state | Task 5 (rule, test), Task 7 (settlement drop) |
| H3 | High | After an event, my pairs from all new records go into one `outcome` call per `gid` | Task 7 |
| H4 | Medium | The wrapped `applied` keeps `s.stakeTurn` and `s.turnAt` across a `buy` or `cashout` of a seat not on turn | Task 5 |
| H5 | Medium | `Play.staked([ns,] id)` is added back in F2's ruled form; Task 12 removes it | Task 4 (added), Task 12 (removed) |
| H6 | Medium | `core/CashOut.lua` sits right after `core/Client.lua` in the TOC | File caps (global), Task 8 |
| H7 | Medium | The UI module is `ns.HoldemCashView` in `ui/games/HoldemCashView.lua`; the engine keeps `ns.HoldemCash` | File caps, File Structure, Tasks 10, 11 |
| H8 | Medium | The dialog skips `at = "stake"` options from Task 3; Task 10 replaces that with the full switch and uses the keys `opt.holdem.rebuy`, `optv.holdem.rebuy.*` | Task 3, Task 10 |
| H9 | Medium | The fun byte-identity test copies `funLog` with a Холдем branch (`startGame`, 10 hands, `Cash.close`) | Task 12 |
| H10 | Medium | New residual C9: the dealer of a hand can void it by going silent at a due step; help sentence and check-list row | Residual table (C9), Task 6 (pin), Task 13 |
| H11 | Low | `core/StakesStart.lua` has 139 lines; Task 5 adds none; the check "≤ 135" is dropped | File caps, Task 5 |
| H12 | Low | My note holds `Games.resolve(game, o, true)` on all three paths | Task 4 |
| H13 | Low | `Book.judge` is wrapped for cash notes when I have no pair for the creditor | Task 7 |
| H14 | Low | An ask counts for E2 only while my client heard the host within `FAIR_ASK_GAP` | Task 6, Task 13 (Addendum 10) |
| H15 | Low | (a) a hand that holds me cancels the cash-out wait; (b) `E.buyRange` returns the codes `buy` refuses; (c) `Client:buy` refuses while `s.stakeAsk` | Task 3 (b), Task 8 (a, b, c), Task 11 (b, c) |
| H16 | Low | (a) `deal` only for a bad hand naming me, any other bad hand reads `unseen` (`s.cashBad[h]`); (b) the reload cost is stated | Task 7 (a), residual C1, Task 13 (b) |
| H17 | Low | A six-seat `S` is pinned valid and one `LEV`; the six-seat close is pinned by GUILD messages and parts | Task 1, Task 12 |
| H18 | Low | (a) `mute`/`evs` come from `holdem_table_test.lua`; (b) Task 9's blinds test asserts the outcome; (c) Task 5 does not edit `core/Cash.lua`; (d) Bulgarian for `help.soon.*`; (e) "no hand" reads "my record is not dealt into the running hand" | Task 5 (a, c, e), Task 9 (b), Task 13 (d) |

## The one rule, and how F3 applies it

**A debt counts only once the debtor's own client has confirmed it, and that client confirms automatically only what it saw itself, whole and clean.** For a cash table:

- **whole:** from my own sit on, my client applied every event of the game itself. My seat begins with no chips and no pair (the engine seats me so), so everything that later makes a debt of mine comes from events I applied. A snapshot that is not the very state I hold (a `/reload`, a login, an asked resync, a new host with another state) makes every later settlement of mine in that game `unseen`: put to me.
- **clean:** no foul of F1 (`forged`, `stand`), no hand closed `"bad"`, and **the amount is my own**: the claim must name exactly the copper my own matrix gives for that pair at that event, else `N "amount"`.
- **checked:** the book of the game has ended on my client (the keys are published) with no bad hand and no open hand that I was dealt into. Until then the note waits; if I leave the table first it reads `unseen`.

Every residual is ruled against this rule in "Residual rulings".

## Global Constraints

Everything in the stage 1, A–E, F1 and F2 constraint files still holds. Added for F3:

- **Fun Холдем is untouched.** A Холдем table without a stake sends and takes exactly the bytes of `e62ddc6` and its engine state is field for field the same: every new state field, action and branch exists only behind `opts.staked` (engine) or `s.stake ~= nil` (core). `tests/engines/holdem_test.lua`, `tests/core/holdem_table_test.lua` and `tests/ui/holdem_test.lua` stay green unedited; Task 12 pins a fun evening's wire log against `e62ddc6`.
- **Protocol stays `v=1`**, prefix `TAVG`, GUILD + WHISPER only. No new message type. The complete list of what changes on the wire, all of it at a staked Холдем table or in the ledger:

  | where | change | meaning |
  |---|---|---|
  | `TBL.sk`, `SNP.tbl.sk`, `SIT.sk`, `INV.sk` | accepted for `holdem`; the value is the **big blind in copper** (`opt.blinds × 100`) | a table whose `sk` is not that is not listed |
  | `TBL.o`, `SNP.tbl.o` | at a staked table: `rebuy` (`"none"`, `"bust"`, `"top"`) is present and `stack` is absent | the rebuy mode of spec 5.5 |
  | `ACT.a`, `EV.a` at the seat's own number | `{k="buy", n}` and `{k="cashout"}` | my buy-in or rebuy of `n` chips; my seat is settled |
  | `EV.a` `{k="sit"}` → the engine's `join` | carries the name (already in the event) into the state as `who` | "no fresh stack" needs to know who comes back |
  | `SNP.st` of a staked game | `cash`, the seats' `who`, `bought`, `cleared`, `back`; `last.took`; `pots[i].from` | the matrix and the buy-ins |
  | `EV` order at a lapse | the host plays `{k="void"}` before every `{k="away"}` of a lapsed shuffle | no blind is lost to an away |
  | ledger | new kind `S`; `D.why` gains `"cash"` | the STAND record; the debtor's own word for a cash debt |

  **Forward compatibility.** A client of the F1 or F2 version does not list a staked Холдем table (`Lobby.valid`: `sk` on an engine without `stakes`). It refuses an `S` (`"kind"`) and a `D` with `why = "cash"` (`"shape"`), remembers both for 24 h and never relays them (Addendum 8's rule). The creditor's claim is an ordinary `D` with `why = "lost"`, which it takes: for that client a cash debt stays „чака потвърждение“ for good, in no balance. Pinned in Task 1 and Task 12.
- **Chips and gold.** One chip is one silver: `HoldemCash.CHIP = 100` copper. The blind levels are the engine's as built (big blind 10, 20, 50, 100, 200 chips, the small blind half). A buy-in is `MIN_BB = 40` to `MAX_BB = 100` big blinds. `E.stakeOf(opt) = opt.blinds × 100`. No gold moves during play.
- **The rebuy modes** (option `rebuy`, staked tables only, default `"bust"`): `"none"` „Без“: one buy per sitting, and a name that left the game with 0 chips buys no more in that game; `"bust"` „Когато свършат чиповете“: a new buy of 40–100 BB only at 0 chips; `"top"` „Винаги до входа“: any buy that leaves the seat with at most 100 BB. No buy while the seat is dealt into a running hand.
- **Table stakes.** A seat sits down with 0 chips and sits out (`out = true`) until its own `buy`. A name that comes back in the same game after leaving with `c > 0` chips must buy at least `min(c, 100 BB)`.
- **Settlement.** A seat is settled by its own `cashout`, by its removal from the table (a stand between hands, or the end of the hand a stand folded it in), and when the game closes (every seat). The engine writes one out record per settled seat, carrying the names of the engine's own seats (`names`, H1); the event that wrote it gives the ledger id `gid = tid .. "/" .. q`. For a pair, `net = took[a][b] − took[b][a]` chips; the debt is `net × 100` copper from the one who lost to the one who won. The sum of a seat's pair nets is always `chips − bought − cleared`.
- **Who writes what.** Each creditor writes a `D` per pair (`why = "lost"`); the debtor's word for a cash debt is its **own `D`** with `why = "cash"` (never a `C`), or an `N`; the client that hosts at the settling event writes one `S` per out record.
- **Fouls** are F1's and F2's (`Stakes.RANK` unchanged) and are kept for the whole game on my client; my own clean sit resets them. A void or a lapse is no foul at a sealed table (it moves no chip); a hand closed `"bad"` with my name among its players is `deal`, and any other bad hand of the game reads `unseen` (H16a).
- **New constants** (`core/Const.lua`): `CASH_BOOK_WAIT = 86400` (a cash note waits at most this long for the book), `CASH_OUT_WAIT = 30` (my `cashout` not played this long after I asked, with no hand holding me: I stand without it; a hand that deals me in cancels the wait, H15a).
- **Files and caps** (`tests/toc_test.lua`; a cap is never raised; measured with `wc -l` at `e62ddc6`):

  | file | lines now | cap | F3 |
  |---|---|---|---|
  | `core/Deal.lua` | 700 | ≤ 700 | **not edited** |
  | `core/DealHooks.lua` | 390 | < 400 | **not edited** |
  | `core/Cash.lua` | 279 | < 280 | Tasks 4, 6: edits inside existing lines only, net 0 (Task 5 does not edit it, H18c) |
  | `core/Book.lua`, `core/BookKeys.lua`, `core/BookCheck.lua` | 253, 235, 117 | < 260 each | **not edited** |
  | `core/Stakes.lua` | 335 | < 340 | **not edited** (its hooks are wrapped) |
  | `core/StakesBook.lua` | 256 | < 260 | **not edited** |
  | `core/StakesClaims.lua` | 116 | < 120 | **not edited** (`Book.word` is wrapped) |
  | `core/StakesWatch.lua` | 235 | < 260 | Task 5: two edits inside lines |
  | `core/StakesStart.lua` | 139 | < 140 | Task 5: two edits inside lines, no line added (H11) |
  | `core/StakesFair.lua` | 171 | < 200 | Tasks 5, 7: +3 at most |
  | `core/Session.lua` | 525 | < 540 | Task 4: +3 at most |
  | `core/Ledger.lua` | 153 | < 300 | Task 1 |
  | `core/LedgerStore.lua` | 231 | < 260 | Task 1: two edits inside lines |
  | `ui/TableFrame.lua` | 532 | < 600 | Task 11: +10 at most |
  | new `engines/holdem_cash.lua` | | < 200 | Tasks 2, 3 |
  | new `core/StakesCash.lua` | | < 260 | Tasks 5, 7, 9 |
  | new `core/CashOut.lua` | | < 140 | Task 8 |
  | new `ui/games/HoldemCashView.lua` | | < 300 | Task 11 |

  The task that creates a file adds its cap line to `the big files keep their limits`. TOC: `engines/holdem_cash.lua` right before `engines/holdem.lua`; `core/StakesCash.lua` right after `core/Cash.lua`; `core/CashOut.lua` right after `core/Client.lua` (it wraps `Client.sit` and `Client.stand` at load, so `ns.Client` must exist; H6); `ui/games/HoldemCashView.lua` right after `ui/games/HoldemView.lua` (H7).
- **No new saved-variable key.** My stake note gains a field (`db.stakeSat.o`); nothing else is saved: after a `/reload` the matrix comes back in the snapshot, and the sitting is `unseen`.
- **Locale.** Every new string in `locale/bg.lua` and `locale/en.lua` with the same keys and placeholders; Bulgarian in „…“ quotes inside texts. The exact Bulgarian is in the task that adds it; the English is the implementer's translation.
- **Only the tasks named may touch an existing assertion** (Task 12: the "not ready" game of `tests/core/stake_test.lua`; Task 13: `tests/core/locale_help_test.lua`).
- Commits are local only, never pushed, never merged. Every commit message ends with exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A `/reload` in the middle of a cash game.** The player that reloaded is asked about every debt of its later settlements in that game; the others, who saw every event, are unaffected. Pinned by Task 7 (`a /reload mid-game asks only the player that reloaded`).
2. **„Стани“ while the next hand is being dealt.** The `cashout` reaches the host after the `hand` event: it is refused, my client sees itself dealt in, waits for the hand to end and asks again; every client settles me at one event with one amount. Pinned by Task 8 (`a cashout that loses the race with the next hand waits for it`).
3. **A split pot with an odd chip under a side pot.** Three all-ins of different sizes, two winners of the main pot: every seat's pair nets sum to what it won less what it put in, to the chip. Pinned by Task 2 (`three all-ins, a split main pot and an odd chip`, the fuzz test).
4. **The winner's connection drops.** After 180 s it is stood up; it wrote no claim. The losers' clients, clean and checked at the close, write their own `D`; a loser whose note is only `unseen` is asked „Да запиша ли дълга?“. The stood player is asked at its login about what it owes. Pinned by Task 8 (`three minutes offline: the seat is settled and the debts wait for the leaver`) and Task 7 (`an unclaimed debt of an unseen note is put to me`).
5. **A busted player stands up and sits down again.** With `rebuy = "none"` its buy is refused; with `"bust"` it buys 40–100 BB; a player that left with 180 BB comes back with 100 BB at least. Pinned by Task 3 (`standing and sitting again gives no fresh stack`).

Also pinned: the host leaves mid-game (Task 8), „Приключи“ and a walk to the hall before the keys (Task 7), a lapse takes no blind (Task 6), a host that reads a live hand (Task 9), a client of the F2 version in the guild (Tasks 1, 12).

## Residual rulings

**The roadmap's F3 table (rulings log, "Stage E" 1–10).**

| Residual | Ruling | Mechanism, or the reason it may stay | Task |
|---|---|---|---|
| E1 host-initiated stands are a trusted claim | **Re-accepted with a contest** (the F1 rule) | A stand of my seat while my client runs and I did not ask is the foul `stand` (`Stakes.stood`): my client contests that settlement. A stand while my client is away (180 s offline) leaves no note: every claim of it is put to me at my login. A stand never moves a chip by itself between hands; mid-hand it folds my seat, and that settlement is the contested one. | 8, 9 |
| E2 a host that holds a step past `FAIR_WAIT`, then voids | **Closed where it can be told, else re-accepted** | A void returns every chip (engine rule 15) and writes nothing into the matrix (Task 6 pins both), so no void makes a debt. When **I** am the dealer and my client asked for that very step at least twice, each ask sent while my client had heard the host within `FAIR_ASK_GAP` (H14), the void is `forged` (the host ignored my step). A dealer that goes silent itself is C9. When a third player deals, my client cannot tell the dealer from the host: re-accepted, the price is the hand. | 6 |
| E3 the hold is keyed by seat and known only to the host that named it | **Re-accepted** | A seat held out or not is dealt no hand or one hand more: no chip moves. | — |
| E4 a seed lapse a lying dealer provokes | **Re-accepted** | It needs the deck the dealer already knows: that is S1 (below), which is the larger hole and is disclosed. The lapse itself returns every chip. The amber count by name stays. | 6 (pin) |
| E5 an away of my seat after 13 s in stage `commit`; a seed-stage away | **Closed** at a staked table | The host voids the hand before any away of a lapsed shuffle, so an away never takes a blind. A member flags an away of its own dealt-in, unfolded seat in a running hand as `forged`, whatever the stage. **Decision:** void first. Cost: a player can skip its big blind by letting its shuffle lapse (20 s, counted amber by name); the table pays one re-deal. | 6 |
| E6 the host withholds a player's key | **Re-accepted, asked** | A hand I was dealt into that stays `open` when the book ends makes every waiting note of mine `unseen`: put to me, naming the player whose key is missing. | 7 |
| E7 a loading screen excuses one dice throw | n/a (Табла, ruled in F2) | — | — |
| E8 key draw: the host reads one live hand per victim per game | **Shipped with a contest, not closed** (Decision below) | (a) by forged events: the snapshot the host then needs is `forged` when it pushes it, `unseen` when it makes me ask or hands the table to an accomplice; `book.forged` (rule 6a: my key left and the same game runs on) is `forged` too. (b) after my own `/reload`: `unseen` by the login. And whatever the host does, a claim must name my own client's amount. | 9 |
| E9 the dealer's stand-void refund; a player vanishing without a key | **Re-accepted** | The refund moves no chip between players. A vanished key: as E6. A player who stands up gets no verdict: its debts of that sitting are put to it (Decision "The book gates the confirmation"). | 7 |
| E10 six seats | **Kept** (user decision) | — | — |

**Decision (E8): ship with a contest.** The cure the residual names, keys released only against the other participants' word that the hand ended, was weighed and not taken. It needs member-to-member whispers (all table traffic is host-to-member today), a wait at every close, and it changes nothing in the case that matters: heads-up against the host, or at a table whose other players are the host's accomplices, the only "other participants" are the cheaters, and their word is free. What an honest third player's word would add is earlier detection, not a different outcome: with it or without it the victim's client never confirms. **Cost:** a modified host can play one hand per victim per game with the victim's cards known (heads-up; multiway only with every other participant's key). The victim loses no gold automatically: its settlement of that game is contested (`forged`) when the same host pushes the snapshot, and **asked** when the host makes it ask or hands over to an accomplice, so there a victim who presses „Потвърждавам“ pays for a hand played against marked cards. The question says „Не видях цялата игра“. An honest client that heals by snapshot over the end of its last hand has its settlements of that game asked. The host also learns the victim's folded hands of that game.

**S1, for Холдем.** The dealer's client knows the deck of the hand it deals (spec 6.3; Addendum 9, S1): at Холдем that is every hole card, in one hand of six at a full table and every other hand heads-up. Nothing detects it and the victim's client confirms. **Re-accepted as in F2**, with the same warning line (`stake.ask.cards`) in the acceptance question; this is the one item that does not pass the one rule. **The user confirms this before staked Холдем is announced.**

**Addendum 8's stake-aware residuals 10–19, re-judged for Холдем** (all re-accepted; none yields a debt my client confirms):

| # | For a cash table |
|---|---|
| 10 a losing host aborts | An abort settles nothing and no entry is written; the pairs stay in every client's state until the next settling event. A host that ends the table (`END`) while I sit in the running game: `forged`, open note (F1). |
| 12 message loss and my turn clock | As Addendum 7: the host's timeout for my seat only after my own clock ran out and no `ACT` of mine is unmatched. |
| 13 a rollback snapshot | `unseen` or `forged` by the snapshot rule of a judged game. |
| 14 one timeout after my login | `unseen` by the login. |
| 15, 16 a repeated gid; a start after my `/reload` | A new game needs my own `buy`: a start by itself costs me nothing. A repeated gid is asked. |
| 17 an outcome a snapshot brought has no note | A settlement my client saw only in a snapshot (the out counter moved) writes no note: its claims are put to me. |
| 18 claims around a leave | Not used: a cash table writes no `stakeLeft`; my `cashout` is an event I apply myself. |
| 19 the `R` of a leaving host | The leaving host plays its own stand event while it still hosts, so it writes its own `S`. |

**New in F3 (accepted).**

| # | Residual |
|---|---|
| C1 | A player who leaves before the book ends is asked about every debt of that sitting (its client holds no verdict). Only players still at the table when the keys are published confirm by themselves. After a `/reload` the notes of **all** my earlier settlements of that game that still waited for the book come back asked, not only the later ones: the wait does not survive a reload (H16b). |
| C2 | A winner stood up offline writes no claim. Its debts are written by the losers' clients (their own `D` when clean and checked, a question when `unseen`); a loser that declines the question leaves no entry. |
| C3 | A client of the F1 or F2 version shows a cash debt as „чака потвърждение“ for good, and counts the creditor's `P` for it as credit of that pair, so a later confirmed debt of the same debtor to the same creditor reads as paid there. The cure is the update. |
| C4 | A player can skip a big blind by letting its shuffle lapse (E5's price). |
| C5 | An honest race is a contest in one case: my `cashout` is never played by the host and I stand after `CASH_OUT_WAIT`; my note is then `unseen`. |
| C6 | A host can seat an accomplice with chips it never bought, by a snapshot or by forged `buy` events for that seat. No pair debt of mine depends on another seat's chips or buy-ins, only on the hands I played; the accomplice owes me what my matrix says. |
| C7 | S13 of F2 holds: a host that names a seat falsely before I sit is not caught (collusion). |
| C8 | A book verdict that comes after a note's final (a late key) is not taken: the note stays asked. |
| C9 | The dealer of a hand can void it by going silent at a due step (its client dies or withholds the step; a dealer seat that stands is voided at once). A void returns every chip, so a dealer losing an all-in (a missed draw on the river) takes its chips back and the winner loses the pot. It makes no debt that my client confirms wrongly, so the one rule holds, but it is an escape from a lost hand: **shown to the user beside S1**. Counted by name (`fairVoids`, red at two, `fair.voidMany`). Pinned in Task 6; named in the help text (`help.stakes.holdem.dealer`) and the check list (Task 13). |

**The plan's decisions, with their cost** (Task 13 copies them into the rulings log):

- **Decision (chips):** one chip is one silver, and `sk` is the big blind in copper. Cost: the smallest table is 5s/10s (buy-in 4g–10g), the largest 1g/2g (80g–200g); the roadmap's example "10s/25s" is not a level the engine has (10s/20s gives 8g–20g).
- **Decision (the matrix is engine state):** attribution, buy-ins and settlement are computed by `engines/holdem.lua` on every client and ride in the snapshot. Cost: a staked snapshot is larger (measured in Task 12); in return a `/reload` loses nothing and nothing new is saved.
- **Decision (the book gates the confirmation):** a cash note waits for the book and reads `unseen` if I leave first (C1). The alternative, confirming at the stand what was clean event by event, lets a dealer that supplied a false face at a showdown collect a confirmed debt before any key is published. Cost: C1; one click per creditor for everyone who leaves before „Приключи“.
- **Decision (cash-out is an event):** „Стани“ sends `{k="cashout"}` and stands only after my client applied it, so the settlement has one event number on every client, mine included. Cost: „Стани“ inside a hand takes effect when the hand ends.
- **Decision („Винаги до входа“):** the buy-in is per player, so "up to the buy-in" is up to the table's 100 BB. A returning name brings at least what it left with, capped at 100 BB. Cost: a player that left with more than 100 BB comes back with 100 BB.
- **Decision (no break):** `Stakes.gap` is 0 for a cash table: a new game gives nobody chips, so staying seated accepts nothing. Cost: none.
- **Decision (the debtor's word is its own `D`):** so that an F1/F2 client, which takes any `C`, keeps a cash debt pending. Cost: C3.
- **Decision (`S` is written by the host):** like `R`, it is a claim for История (F4), never a debt. Cost: a modified host can write a false `S`; nothing reads it for money.

## File Structure

| File | Responsibility |
|---|---|
| `engines/holdem_cash.lua` (new) | Pure: the attribution of a hand's pots to pairs, the matrix, the buy rules, the settlement of a seat. `ns.HoldemCash`. |
| `engines/holdem.lua` | Uses it when `opts.staked`: `cash` in the state, `buy`, `cashout`, `join` with `who`, settlement at a leave and at the close; `E.cashGame`, `E.stakeOf`, `E.buyRange`; the options `stack` (fun) and `rebuy` (staked). |
| `core/Games.lua`, `core/Stake.lua`, `core/Lobby.lua`, `core/Session.lua`, `core/Member.lua`, `core/Lifecycle.lua` | Staked options, `sk = stakeOf(opt)`, my note's `o`, the names for `E.new`. |
| `core/Cash.lua`, `core/Member.lua` | `join` with `who`; void before away; the dealer's ignored step; `still` for `buy` and `cashout`. |
| `core/StakesCash.lua` (new) | The extension `stakes` at a cash table: no forfeit, my own names, snapshot checks, out records → notes, claims and `S`, the book's verdict for a note, the debtor's own `D`. |
| `core/CashOut.lua` (new, loaded after `core/Client.lua`) | My buy-in after my sit; „Стани“ as cashout, then stand. |
| `core/Ledger.lua`, `core/LedgerStore.lua` | Kind `S`, `D.why = "cash"`. |
| `ui/NewTableDialog.lua`, `ui/StakePanels.lua`, `ui/Hall.lua` | The staked Холдем table in the dialog, the question with the buy-in, the hall's line. |
| `ui/games/HoldemCashView.lua` (new, `ns.HoldemCashView`), `ui/games/HoldemModel.lua`, `ui/games/HoldemView.lua`, `ui/TableFrame.lua`, `ui/Accounts.lua`, `ui/LedgerTab.lua` | „Сметка на масата“, „Докупи“, the stand, the bill, the ledger rows. |
| `tests/helpers/play.lua` | `Play.cash`, `Play.hand`, `Play.MORE`. |

---

### Task 1: The ledger takes a STAND and a cash debt

**Files:**
- Modify: `core/Ledger.lua` (`KINDS`, `WHY`), `core/LedgerStore.lua` (lines 85 and 146: `b.k == "R"` becomes `(b.k == "R" or b.k == "S")`), `tests/toc_test.lua` (nothing: both caps exist)
- Create: `tests/core/ledger_cash_test.lua`

**Interfaces:**
- Produces: entry kind `S` = `{ gid, g, f, c, sk, n, w, l, why }`: `f` the name of the settled player, `c` what it bought in copper, `sk` the table's big blind in copper, `n` the names by seat (`false` for an empty chair), `w` the seats it won from, `l` the seats it lost to, `why` optional: `"left"`, `"offline"`, `"close"`. Anybody may author one (as `R`). `D.why` also takes `"cash"`. The canonical field order `FIELDS` is **not** changed (no new field: a new one would change every hash).

- [ ] **Step 1: Write the failing tests** (`tests/core/ledger_cash_test.lua`)

```lua
local S = { i = "Иван Петров:7", k = "S", at = 100, gid = "Иван Петров#5/41", g = "holdem", f = "Мария Стоянова",
  c = 80000, sk = 2000, n = { "Иван Петров", "Мария Стоянова", false, false, false, false }, w = { 1 }, l = {}, why = "left" }
it("an S is a valid entry; its hash is stable", function()
  eq(Ledger.valid(S, 200), true)
  eq(#Ledger.hash(S), 16); eq(Ledger.hash(S), Ledger.hash(ns.Util.copy(S)))
end)
it("an S needs f, c, sk, n, w, l; its why is one of three", function()
  for _, f in ipairs({ "gid", "g", "f", "c", "sk", "n", "w", "l" }) do
    local e = ns.Util.copy(S); e[f] = nil
    eq({ Ledger.valid(e, 200) }, { nil, "shape" }, f)
  end
  local e = ns.Util.copy(S); e.why = "lost"; eq({ Ledger.valid(e, 200) }, { nil, "shape" })
  e.why = nil; eq(Ledger.valid(e, 200), true)
  e.c = 0; eq({ Ledger.valid(e, 200) }, { nil, "amount" })
end)
it("a D may say cash; the hash of every older entry is what it was", function()
  local d = { i = "Мария Стоянова:3", k = "D", at = 100, gid = "Иван Петров#5/41", g = "holdem", f = "Мария Стоянова", t = "Иван Петров", c = 12300, why = "cash" }
  eq(Ledger.valid(d, 200), true)
  d.why = "lost" -- the field order is untouched: 17 fields, the last eight empty
  eq(Ledger.canon(d), "Мария Стоянова:3|D|100|Иван Петров#5/41|holdem|Мария Стоянова|Иван Петров|12300|lost||||||||")
end)
```
Store and view tests:
- `S entries count against the author cap with R`: with `C.LEDGER_AUTHOR_MAX` lowered to 3 for the test, two `R` and one `S` of one author are taken and a second `S` is refused `"full"`; a `D` of that author is still taken.
- `the debtor's own D with why cash confirms the creditor's claim`: the creditor's `D` (`why = "lost"`, `c = 12300`) then the debtor's own `D` at the same gid and pair (`why = "cash"`, `c = 12300`) → `View.of(L).debts` has that debt `confirmed`, `c == 12300`, `clash == false`; with `c = 12000` in the debtor's `D` → `clash == true`.
- `a client of the F2 version keeps a cash debt pending` : a store whose `take` refuses kind `S` and a `D` with `why == "cash"` as `e62ddc6`'s `Ledger.valid` does (wrap `net.take` as `tests/core/stakes_f2_flow_test.lua` line 421 does for `N`) holds the creditor's `D`, not the debtor's and not the `S`: the debt is `pending` there, `View.net` of the pair is 0, both refused entries are `ledger:refused`.
- `a six-seat S with six 12-letter Cyrillic names (24 bytes each) is valid and fits one live LEV` (H17): the canonical form stays under the 600-byte cap and `LedgerSend` packs it into one part. An `S` whose names are 64 bytes each (about 660 bytes) is refused `"size"`; that is accepted as a residual (an `S` is a claim for История only, never money) and goes into the rulings log in Task 13.

- [ ] **Step 2: Run** `bash t.sh tests/core/ledger_cash_test.lua` → fails (`"kind"` for the `S`).
- [ ] **Step 3: Implement.** `KINDS.S = { gid = true, g = true, f = true, c = true, sk = true, n = true, w = true, l = true, why = false }`; `WHY.S = set("left", "offline", "close")`; `WHY.D` gains `"cash"`. `amount` and `right` need no change (an `S`'s `c` is any whole copper from 1; anybody may write one). The two `LedgerStore` lines.
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `feat(ledger): the STAND entry and the cash reason of a debt`.

### Task 2: The engine knows who took what from whom

**Files:**
- Create: `engines/holdem_cash.lua`, `tests/engines/holdem_cash_test.lua`
- Modify: `engines/holdem.lua` (`E.new`, `finish`), `TavernGames.toc`, `tests/toc_test.lua` (the cap line `engines/holdem_cash.lua < 200`), `tests/helpers/loader.lua` only if engines are listed there by hand

**Interfaces:**
- Produces (`local HC = ns.HoldemCash`):
  - `HC.CHIP = 100`, `HC.MIN_BB = 40`, `HC.MAX_BB = 100`
  - `HC.new(rebuy) -> { rebuy = rebuy, took = {}, outN = 0, outs = {}, left = {} }` (the `cash` table of a staked state)
  - `HC.attribute(pots) -> took`: `pots = { { amount, winners = {seats}, from = {[seat] = chips} }, ... }` → `took[w][j]` = chips winner `w` took from seat `j` in this hand (`j ~= w`; zero entries absent)
  - `HC.add(cash, took)`: adds a hand's `took` into `cash.took`
  - `HC.net(cash, a, b) -> number`: `(took[a][b] or 0) − (took[b][a] or 0)`
  - `engines/holdem.lua`: `E.new(opts)` with `opts.staked == true` sets `s.cash = HC.new(<the resolved rebuy option, default "bust">)`; without it the state has no `cash` field. `finish` (the end of a hand that was not voided), only when `s.cash`: every pot gets `from`, `s.last.took = HC.attribute(pots)`, `HC.add(s.cash, s.last.took)`.

**The algorithm** (the tests do not determine it; all clients must agree to the chip):
- `from`: in `finish`'s loop over the levels, the chips of layer `L` (`L − prev` from each payer) are credited to `from` of the pot that layer went into (the new pot, the pot it was merged into, or the pot below for a dead layer); an uncalled layer (one payer) is credited nowhere.
- `HC.attribute`, per pot with winners `W` in the pot's `winners` order: a winner's own `from` comes back to it. For every other contributor `j`, ascending by seat: `q = floor(from[j] / #W)` goes to each winner, and the `from[j] − q × #W` chips left over go one each to the winners, continuing round-robin from where the last contributor's leftovers stopped (the pointer starts at the pot's first winner and runs through the whole pot). This gives each winner exactly its share less its own contribution, the odd chips to the same winners `finish` gives them to.

- [ ] **Step 1: Write the failing tests** (`tests/engines/holdem_cash_test.lua`; `play(stacks, script)` builds a staked state by hand with the given chips per seat and applies a scripted hand with a fixed deck, as `tests/engines/holdem_test.lua`'s helpers do)

```lua
it("one pot, one winner: each loser's chips are the winner's", function()
  local t = HC.attribute({ { amount = 300, winners = { 2 }, from = { [1] = 100, [2] = 100, [3] = 100 } } })
  eq(t, { [2] = { [1] = 100, [3] = 100 } })
end)
it("a split pot (a synthetic one): both winners take half of each loser, the odd chip to the first", function()
  local t = HC.attribute({ { amount = 305, winners = { 3, 1 }, from = { [1] = 100, [2] = 105, [3] = 100 } } })
  eq(t, { [3] = { [2] = 53 }, [1] = { [2] = 52 } })
end)
it("three all-ins, a split main pot and an odd chip", function()
  -- stacks 51 / 125 / 300, all in; seats 1 and 2 split the main pot of 153, seat 2 wins the side pot,
  -- seat 3 wins nothing but its uncalled layer
  local s = play({ 51, 125, 300 }, ALLIN_SPLIT)
  eq(s.last.pots[1].from, { [1] = 51, [2] = 51, [3] = 51 }); eq(s.last.pots[2].from, { [2] = 74, [3] = 74 })
  local w = s.last.pots[1].winners                      -- the odd chip is the first winner's
  local side = function(i) return i == 2 and 74 or 0 end
  eq(s.last.took[w[1]][3] - side(w[1]), 26); eq(s.last.took[w[2]][3] - side(w[2]), 25)
  eq(HC.net(s.cash, 1, 2), 0); eq(HC.net(s.cash, 1, 3) + HC.net(s.cash, 2, 3), 125)
end)
```
Further tests, each asserting `s.last.took` and, for every seat `i` of the hand, `sum_j HC.net(hand, i, j) == (last.won[i] or 0) − last.contrib[i]`:
- `everyone folds to a raise: the winner takes the blinds, the uncalled raise is nobody's`.
- `folded chips in a side pot go to that pot's winner`.
- `a leaver's dead layer joins the pot below` (rule 12's leave case).
- `a voided hand writes nothing`: after `{k="void"}` `s.cash.took` is what it was and `s.last.took == nil`.
- `the matrix adds up over hands`: two scripted hands, `s.cash.took` is the sum.
- `fuzz: 300 random hands at 2 to 6 seats`: random legal actions (`E.legal`, a seeded generator), random stacks 1–400; after every hand the identity above holds for every seat and `s.cash.took` has no negative and no self entry.
- `a fun state has no cash and its last has no took`: `E.new({ seats = { true, true } })` has `cash == nil`; after a hand `last.took == nil` and `last.pots[1].from == nil`.

- [ ] **Step 2: Run** `bash t.sh tests/engines/holdem_cash_test.lua` → fails (`HoldemCash` is nil).
- [ ] **Step 3: Implement** `engines/holdem_cash.lua` (`HC.new`, `HC.attribute`, `HC.add`, `HC.net`) and the two edits of `engines/holdem.lua`. The header comment of `engines/holdem.lua` gets rule 20 ("a staked table: see `engines/holdem_cash.lua`") and nothing in rules 1–19 changes.
- [ ] **Step 4: Run** `bash t.sh` → green; `tests/engines/holdem_test.lua` unedited.
- [ ] **Step 5: Commit** `feat(holdem): the pairwise attribution of every pot, in the staked state`.

### Task 3: Buy-in, rebuy, table stakes, cash-out

**Files:**
- Modify: `engines/holdem_cash.lua`, `engines/holdem.lua` (`E.new`, `E.options`, `join`, `leave`, `settle`, `close`, `startHand`, `E.apply`, the contract block), `tests/engines/holdem_cash_test.lua`, `ui/NewTableDialog.lua` (`optionSet`: one line, H8)
- Create: `tests/ui/holdem_dialog_test.lua`

**Interfaces:**
- Consumes: Task 2's `HC`.
- Produces:
  - `E.cashGame = true`, `E.CHIP = HC.CHIP`, `E.stakeOf(opt) -> opt.blinds * HC.CHIP`, `E.buyRange(state, seat) -> lo, hi | nil, code`, where `code` is exactly what `buy` would refuse: `"hand"`, `"phase"`, `"rebuy"` or `"full"` (H15b).
  - `E.options`: `stack` gains `at = "fun"`; a fourth option `{ id = "rebuy", choices = { "none", "bust", "top" }, default = "bust", at = "stake" }` (Task 4 teaches `Games.resolve` the field `at`; until then this task's tests call `E.new` directly).
  - A staked seat record: `{ chips = 0, out = true, leaving = false, who = <name or nil>, bought = 0, cleared = 0, back = <chips that name left this game with, or nil> }`. `E.new` with `opts.staked` builds every occupied seat so, `who = opts.names and opts.names[i]`.
  - `{k="join", seat, who}` at seat 0: a staked seat as above, `back = s.cash.left[who]`.
  - `{k="buy", n}` by the seat: chips and `bought` grow by `n`, `out = false`. At a fun table the engine does not know the action: it falls through to the refusal any unknown action gets today. Refused at a staked table: `"hand"` while the seat is dealt into the running hand (in `s.order`, its `p` not `gone`) ; `"phase"` once the close is given; `"rebuy"` when the mode forbids it; `"full"` when the seat is at its top; `"amount"` outside the range. `buy` asks `HC.range` first, so `E.buyRange` and `buy` always agree.
  - `HC.range(s, seat) -> lo, hi | nil, code` (`E.buyRange`), with `bb = s.bb`, `min = 40 × bb`, `max = 100 × bb`, `c = chips`; first `nil, "phase"` once the close is given and `nil, "hand"` while the seat is dealt into the running hand (H15b), then:
    - first buy of the sitting (`bought == 0`): `back == 0` and mode `"none"` → `nil, "rebuy"`; else `lo = max(min, math.min(back or 0, max))`, `hi = max`;
    - later, `"none"` → `nil, "rebuy"`; `"bust"` → `c == 0` and `lo, hi = min, max`, else `nil, "rebuy"`; `"top"` → `c == 0` and `min, max`, else `c < max` and `1, max − c`, else `nil, "full"`.
  - `{k="cashout"}` by the seat (a staked table only, as `buy`): `"hand"` while dealt into the running hand, `"seat"` when `bought == 0`. It settles the seat and keeps it seated: `back = chips`, `chips = 0`, `out = true`, `bought = 0`, `cleared = 0`.
  - `HC.settle(s, seat) -> rec`: for every other occupied seat `j` in ascending order with `n = HC.net(s.cash, seat, j) ~= 0`: `rec.net[j] = n`, `s.seats[j].cleared = s.seats[j].cleared − n`; the seat's row and column of `took` are removed; `s.cash.left[who] = chips` when `who`; `s.cash.outN = s.cash.outN + 1`; `rec = { n = outN, seat, who, chips, bought, net, names }` where `names = {[j] = s.seats[j].who}` for each `j` of `net`, taken before any chair changes hands (H1: money names come from the engine's own `who`, never from the chair list; a leaving seat keeps the leaver's `who`) is appended to `s.cash.outs`. Called only for a seat with `bought > 0`.
  - Where the engine settles: `cashout`; `leave` of a seat outside a hand (before the chair empties); `settle` (the end of a hand) for every `leaving` seat, before its chair empties or is given to the newcomer (who is then seated as a staked seat with the `who` its `join` carried, kept on the leaving seat as `takenWho`); the moment the phase becomes `"closed"` (in `close` outside a hand, in `settle` after a closing hand): every seat with `bought > 0`, ascending, each as a cashout.
  - `startHand` empties `s.cash.outs` (the counter `outN` runs on).
  - **The identity** every test checks after every action outside a hand, for every occupied seat `i`: `sum over occupied j of HC.net(s.cash, i, j) == chips_i − bought_i − cleared_i`.

- [ ] **Step 1: Write the failing tests** (added to `tests/engines/holdem_cash_test.lua`; `T(opt)` = `E.new({ staked = true, seats = {true, true, true}, names = {"A", "B", "C"}, opt = opt })` at blinds 10)

```lua
it("a staked seat sits with nothing and buys 40 to 100 big blinds", function()
  local s = T()
  eq(s.seats[1], { chips = 0, out = true, leaving = false, who = "A", bought = 0, cleared = 0 })
  eq(E.system(s), nil)                                   -- nobody can play yet
  eq({ E.buyRange(s, 1) }, { 400, 1000 })
  eq({ E.apply(s, 1, { k = "buy", n = 399 }) }, { nil, "amount" })
  eq({ E.apply(s, 1, { k = "buy", n = 1001 }) }, { nil, "amount" })
  eq(E.apply(s, 1, { k = "buy", n = 600 }), true); eq(E.apply(s, 2, { k = "buy", n = 1000 }), true)
  eq(s.seats[1].chips, 600); eq(s.seats[1].bought, 600); eq(s.seats[1].out, false)
  eq(E.system(s).k, "hand")
end)
it("the three rebuy modes", function()
  for mode, want in pairs({ none = { nil, "rebuy" }, bust = { 400, 1000 }, top = { 400, 1000 } }) do
    local s = T({ rebuy = mode }); E.apply(s, 1, { k = "buy", n = 400 }); s.seats[1].chips = 0
    eq({ E.buyRange(s, 1) }, want, mode)
  end
  local s = T({ rebuy = "top" }); E.apply(s, 1, { k = "buy", n = 400 })
  eq({ E.buyRange(s, 1) }, { 1, 600 }); s.seats[1].chips = 1000; eq({ E.buyRange(s, 1) }, { nil, "full" })
  s = T({ rebuy = "bust" }); E.apply(s, 1, { k = "buy", n = 400 }); eq({ E.buyRange(s, 1) }, { nil, "rebuy" })
end)
it("a fun table knows neither action and its state is unchanged", function()
  local f = E.new({ seats = { true, true } })
  eq((E.apply(f, 1, { k = "buy", n = 500 })), nil); eq((E.apply(f, 1, { k = "cashout" })), nil)
  eq(f.seats[1], { chips = 1000, out = false, leaving = false }); eq(f.cash, nil)
end)
```
Further tests (each also checks the identity):
- `no buy and no cashout while I am dealt in` : during a hand both are `nil, "hand"` for a seat of `s.order`; a seat that sat down during the hand may buy.
- `a cashout settles my pairs and keeps my chair`: after two scripted hands in which seat 1 won 120 from seat 2 and lost 30 to seat 3: `cashout` by seat 1 appends `{ n = 1, seat = 1, who = "A", chips = <its chips>, bought = <its buys>, net = { [2] = 120, [3] = -30 } }`; `HC.net` of every pair of seat 1 is 0; seat 2's `cleared` is `-120`, seat 3's `30`; seat 1 has `chips = 0, bought = 0, cleared = 0, out = true, back = <its chips>`; a second `cashout` is `nil, "seat"`.
- `a stand between hands settles and empties the chair`; `a stand in a hand settles when the hand ends, with the chips it folded`: the record appears at the action that ends the hand, and its `net` holds what the leaver's folded chips made.
- `two leavers of one hand are settled at one action, their pair once`.
- `the close settles every seat, each pair once`: three seats; after `{k="close"}` outside a hand `s.cash.outs` has one record per seat with `bought > 0`, a pair's net appears in exactly one of them, every seat has 0 chips and its `back`.
- `standing and sitting again gives no fresh stack` (Review Focus 5): seat 1 busts and leaves; `join {seat = 1, who = "A"}`: `back == 0`; mode `"none"` → `buyRange` `nil, "rebuy"`; mode `"bust"` → `400, 1000`. Seat 2 leaves with 1800 chips and joins again: `buyRange` `1000, 1000`; with 700: `700, 1000`; with 150: `400, 1000`. Another name on that chair: `400, 1000`.
- `a newcomer on a leaving chair is seated staked when the hand ends`.
- `a newcomer on a leaving chair owes nothing of the leaver's hand` (H1): seat 2 stands in a hand and its chair is taken by `join {seat = 2, who = "D"}` before the hand ends; when the hand ends the leaver's record has `who == "B"` and `names[j]` is the engine's own `who` of every `j` of its `net`; none of its pairs names "D"; the newcomer's own later record names "D" and nobody else's hand.
- `E.buyRange gives the code buy would refuse` (H15b): `"hand"` for a seat dealt into the running hand, `"phase"` after the close, `"rebuy"` in mode `"none"` after a buy, `"full"` in mode `"top"` at 100 BB; `buy` returns the same code in each case.
- `a fun Холдем dialog sends no rebuy` (H8, `tests/ui/holdem_dialog_test.lua`): the options the dialog draws and submits for a fun Холдем table are `betting`, `blinds` and `stack` only.
- `the records of the last hand go at the next hand; the counter runs on`.
- `fuzz: 200 random sessions` (seeded): random buys within range, hands by random legal actions, cashouts, leaves and joins between and inside hands; the identity holds after every action outside a hand, and for every out record `sum of rec.net == rec.chips − rec.bought − <that seat's cleared before the record>`.

- [ ] **Step 2: Run** → fails (`E.buyRange` is nil).
- [ ] **Step 3: Implement** in `engines/holdem_cash.lua` (`HC.seat(who, back)`, `HC.range`, `HC.buy`, `HC.settle`) and `engines/holdem.lua`. `playingFn` needs no change (a staked seat without chips is not playing). The engine's header rule 20 lists the staked rules of this task in six lines. `ui/NewTableDialog.lua`'s `optionSet` skips an option with `at = "stake"` (one line, H8): from this task on a fun Холдем table opened from the dialog must not send `rebuy`. Task 10 replaces that line with the full staked/fun switch.
- [ ] **Step 4: Run** `bash t.sh` → green; `wc -l engines/holdem_cash.lua` < 200.
- [ ] **Step 5: Commit** `feat(holdem): buy-in, the rebuy modes, table stakes and the settlement of a seat`.

### Task 4: The table I accepted: blinds, betting, rebuy

**Files:**
- Modify: `core/Games.lua` (`Games.resolve`), `core/Stake.lua` (`Stake.allowed`, `Stake.note`, `Stake.accept`, `Stake.worst`), `core/Lobby.lua` (`Lobby.valid`), `core/Session.lua` (`Session.open` lines 380–392, `Session.request` lines 414–431), `core/Member.lua` (`Member.adopt` lines 99–121), `core/Lifecycle.lua` (`Session:newGame`), `core/Cash.lua` (the `join` line of `applied`, edited in place), `tests/helpers/play.lua`
- Create: `tests/core/stake_cash_test.lua`

**Interfaces:**
- Consumes: Task 3's `E.options` (`at`), `E.stakeOf`, `E.cashGame`.
- Produces:
  - `Games.resolve(id, opt, staked) -> table | nil`: an option with `at = "stake"` is resolved only when `staked`, one with `at = "fun"` only when not; a key of an option that is not resolved makes the whole `opt` invalid (`nil`). Two-argument calls behave as before for every engine whose options have no `at`.
  - `Stake.allowed(id, c, opt) -> bool`: as before, and for an engine with `stakeOf`, when `opt` is given, `c == engine.stakeOf(opt)`.
  - `Stake.note(client, tid, sk, tn, o)`: `db.stakeSat = { tid, sk, tn, o }` (`o`: a copy of the resolved options I accepted; nil at a fun table).
  - `Stake.worst(id, copper)`: an engine with `cashGame` → `copper * 100` (one full buy-in; the question's text says the rest).
  - `Session.open`: resolves `opt` with `opts.stake ~= nil` first, then `Stake.allowed(opts.game, opts.stake, opt)`, and notes `opt`. `Session.request` notes the options of the table as my client sees them (`s.opt`, else the lobby record's `opt`). `Stake.accept` notes `s.opt`. On all three paths (open, request, accept) the noted `o` is `Games.resolve(game, o, true)`, never the lobby record's raw `o` (H12: `Lobby.fromTBL` copies `m.o` as it came, so a default may be missing, and a host that only left one out would read `forged`).
  - `Lobby.valid(m)`: `Games.resolve(m.g, m.o, m.sk ~= nil)` and `Stake.allowed(m.g, m.sk, <that>)`.
  - `Member.adopt`: `s.opt = Games.resolve(t.g, t.o, t.sk ~= nil)`; then, with my note for this table at this stake: a note with `o` keeps it (`s.opt = copy(note.o)`) and sets `how.o = true` when the snapshot's differ; a note without `o` takes the snapshot's, once (as `tn`).
  - `Session:newGame` passes `names = self.stake ~= nil and copy(self.seats) or nil` to `engine.new`.
  - `core/Cash.lua`: the engine's `join` carries `who = s.stake and a.name or nil`.
  - `tests/helpers/play.lua`: `Play.MORE = { "Kiro Barley", "Нади Колева" }` (seats 5 and 6); `Play.cash(n, opt, buys) -> sim, cl, tid`: a guild of `n` (`Play.NAMES`, then `Play.MORE`), every client with its own random (`sim.envs[name].random`, as `tests/core/holdem_table_test.lua`'s `rnd`), `NAMES[1]` opens staked Холдем (`opt` default `{ blinds = 10 }`, `stake = E.stakeOf(opt)`, `turn = 30`), the others sit with that `sk`, the host starts, every seat `i` plays `{k="buy", n = buys and buys[i] or 1000}` from its own client, `sim:run(1)` each; `Play.hand(sim, host, limit)`: `Play.step` until a hand that was running has ended (error after `limit or 400` steps). `Play.staked([ns,] id) -> restore` (H5; F2's ruled form, which `2ae81c3` removed): an optional namespace first (default `Sim.ns`, G6); it sets `Engines[id].stakes = true` and returns a restore that is also recorded in `pending`, so `Play.restore()` runs it too (G11). Before Task 12 a test file that needs the staked table begins with `local restore = Play.staked("holdem")` and ends with `restore()`; Task 12 removes the helper again.

- [ ] **Step 1: Write the failing tests** (`tests/core/stake_cash_test.lua`)

```lua
it("staked options: rebuy only with a stake, stack only without", function()
  eq(Games.resolve("holdem", nil), { betting = "nl", blinds = 10, stack = 100 })
  eq(Games.resolve("holdem", nil, true), { betting = "nl", blinds = 10, rebuy = "bust" })
  eq(Games.resolve("holdem", { rebuy = "top" }), nil); eq(Games.resolve("holdem", { stack = 50 }, true), nil)
  eq(Games.resolve("santase", nil, true), Games.resolve("santase", nil))
end)
it("the stake of a cash table is its big blind in copper", function()
  eq(E.stakeOf({ blinds = 20 }), 2000)
  eq(ns.Stake.allowed("holdem", 2000, { blinds = 20 }), true); eq(ns.Stake.allowed("holdem", 5000, { blinds = 20 }), false)
  eq(ns.Stake.worst("holdem", 2000), 200000)
end)
```
Simulator tests:
- `openTable refuses a stake that is not the big blind` (`nil, "stake"`), and `opt = { stack = 50 }` with a stake (`nil, "opt"`).
- `a TBL whose sk is not its blinds is not listed`; `a staked TBL announces rebuy and no stack; a fun one stack and no rebuy`.
- `my note keeps the options I sat down to`: after `cl:sit(tid, 2, sk)`, `db.stakeSat.o == { betting = "nl", blinds = 10, rebuy = "bust" }`; the opener's too.
- `my note holds the resolved options, not the lobby record's raw ones` (H12): a TBL whose `o` lacks the default `rebuy` is taken by `Session.request`; `db.stakeSat.o.rebuy == "bust"`, and a host that plays the default is no `forged`.
- `a snapshot with another rebuy mode keeps mine and says so`: the host pushes an `SNP` whose `tbl.o.rebuy` is `"top"` → the member's `s.opt.rebuy == "bust"`; the hook `adopted` got `how.o == true` (a spy extension as `tests/core/stakes_cards_test.lua` uses).
- `the engine's seats carry the names at a staked table and none at a fun one`: after the start `host.session.state.seats[2].who == NAMES[2]`; a later sit's seat too; at a fun table `seats[2].who == nil`.
- `Play.cash seats, starts and buys`: every seat has its chips and a hand begins.

- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement.** `core/Session.lua` grows by at most 3 lines: the stake check of line 380 moves below the `resolve` of line 384 (a move, not an addition); the two `Stake.note` calls gain an argument.
- [ ] **Step 4: Run** `bash t.sh` → green; `wc -l core/Session.lua` < 540, `core/Cash.lua` 279.
- [ ] **Step 5: Commit** `feat(stakes): a cash table's stake is its blinds; the options I accepted are pinned`.

### Task 5: The extension `stakes` at a cash table

**Files:**
- Create: `core/StakesCash.lua`, `tests/core/stakes_cash_table_test.lua`
- Modify: `core/StakesStart.lua` (`Stakes.gap`, `Stakes.held`: one edit inside a line each; no line is added, the file has 139, H11), `core/StakesFair.lua` (`Stakes.fairFoul`: one line), `core/StakesWatch.lua` (`doneForMe` line 104 and `turnKey` line 192: each also requires `st.round`), `TavernGames.toc`, `tests/toc_test.lua` (cap `core/StakesCash.lua < 260`). `core/Cash.lua` is not edited here (H18c).

**Interfaces:**
- Consumes: Task 3's state (`st.cash`, the staked seat record), Task 4's `how.o` and `s.opt`.
- Produces (in `ns.Stakes`; the file wraps `ns.Ext.stakes.applied`, `adopted`, `leaving`, `gone` and adds `still`, outermost, as `core/StakesStart.lua` and `core/StakesFair.lua` wrap them):
  - `Stakes.cash(s) -> bool`: `s.stake ~= nil` and the engine has `cashGame`.
  - **No forfeit.** At a cash table every wrapped hook sets `s.stakeRoster = nil` before and after the original runs. With no roster F1's `quits`, `forfeit`, `quit` (no `db.stakeLeft`), `tellStood` and the renamed-seat loop of `core/StakesStart.lua` do nothing. `Stakes.stood` (my seat stood while I did not ask) stays as it is.
  - `s.cashNames` (seat → name; local, never sent): kept **only for the rename check below**; no money reads it (H1: pairs and the `S` take their names from the out record, which takes them from the engine's own `who`). Set from `s.seats` at the `start` event and at an adoption with no state before or `how.fresh`; a `sit` event adds its `a.name`; any applied `stand` drops its seat from it, and so does any settlement (Task 7) (H2).
  - **A snapshot at a cash table** (before the original `adopted`): `how.o`, or a state whose `bb`, `betting` or `cash.rebuy` is not my `s.opt`'s, or a staked state without `cash` → `Stakes.pend(s, "forged")`. The rename check runs **only when the snapshot's state equals my state** (`same(prev, st)`, as F2's C3 fix does at `core/StakesStart.lua:116`; H2): for the occupied staked seats of `s.seats`, a seat of `s.cashNames` that the snapshot shows under another name → `forged` from my host, `unseen` from a host new to me by name (`how.moved`), and my name for it stays. Outside an identical state the check has nothing to add: a state that differs is already `unseen` or `forged` by F1's rule, and the names of money live in the state (H1).
  - **My own sit starts my sitting** (after the original `adopted`): when my own SIT took me in (`how.req or how.sit or (how.sat and not how.fresh)`), my seat is read as **the record whose `who` (or `takenWho`) is me** (H1), not as `st.seats[s.mySeat]`: on a chair the leaver still holds, that record is the leaver's. A record of mine with `chips == 0`, `bought == 0`, no pair in `cash.took` and **not dealt into the running hand** (H18e: a hand may be running), or a taken chair whose `takenWho` is me with no record of mine yet, is a clean sit: `s.stakeFoul` becomes only what this very adoption's checks above raised (nil when none). With chips, a buy or a pair in my name there: `forged`.
  - `ns.Ext.stakes.still(s, seat, a)`: `true` for a seat's `buy` or `cashout` at a cash table (the turn clock of the seat on turn is left alone); after such an event the host, with no seat on turn, calls `s:armTimers()` (two seats with chips may now be enough for a hand).
  - **My turn clock across another seat's buy** (H4): the wrapped `applied` at a cash table saves `s.stakeTurn` and `s.turnAt` before the original runs and puts them back after it when the event is a `buy` or `cashout` of a seat that is not on turn. (On a member `Stakes.applied` calls `refresh(s, start, seat ~= 0)` and would restart my clock, so an honest host timeout after my lost ACT could come before my clock ran out and read `forged`; the host keeps its own timer through `still`.)
  - `Stakes.gap(s)` is 0 for a cash table and `Stakes.held` skips the silent-seat rule there.
  - `Stakes.fairFoul`: for a sealed engine, `"bad"` → `deal`, everything else → nil.

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_cash_table_test.lua`; begins with `local restore = Play.staked("holdem")`, ends with `restore()`; `mute` and `evs` are copied from `tests/core/holdem_table_test.lua` and the Табла tests (they are not in `stakes_cards_test.lua`, H18a); the cheating-host scaffolding is copied from `tests/core/stakes_cards_test.lua`)
  - `a stand at a cash table is no forfeit`: Мария stands between hands → no `"forfeit"` event on any client, `db.stakeLeft == nil` on hers, no `R` was sent.
  - `my own sit into a running game starts clean`: Гошо sits while a hand runs → `stakeFoul == nil` on his client; he buys, plays a hand: still nil.
  - `a watcher that sits starts clean`.
  - `a relog into my seat is unseen`: `sim:relog(Мария)` mid-game → her `stakeFoul == "unseen"`, the others' nil.
  - `a snapshot of my very state that renames a seat is forged from my host, unseen from a new one` (C3 of F2): assert `s.cashNames[3]` is still the old name.
  - `a snapshot with other blinds or another rebuy mode in its state is forged`.
  - `my seat with chips I did not buy at my own sit is forged`.
  - `my sit onto a taken chair is clean` (H1): Мария stands in a hand, Гошо sits into her chair before the hand ends; at his own sit and after the hand's settlement his `stakeFoul` is nil.
  - `cashout, stand, a sit I missed, an asked snapshot: unseen, not forged` (H2): a stand drops the seat from `s.cashNames`; the snapshot differs from my state, so the rename check does not run.
  - `a buy during my turn leaves my clock; the host's timeout after my lost ACT is no foul` (H4): another seat's `buy` leaves `s.stakeTurn` and `s.turnAt` as they were; my ACT is dropped, the host times my seat out at deadline + `AUTO_GRACE`, and my client holds no foul.
  - `a Холдем snapshot is not read as a Морски шах board`: seats 1 and 6 heads-up, the flop out (deck indices 6–8 on the board), seat 6 asks for a snapshot (`s:requestSync()` after a muted event) → `unseen`, not `forged`; no hook raised (`env.strictHooks`).
  - `no break between cash games`: after the close and the keys the host's `canStart()` is `true` at once, and a start one second after the close is no foul on the members.
  - `a buy leaves the turn clock alone, and a second buy starts a hand`: the host's `s.deadline` is unchanged by another seat's `buy`; at a table where one seat has chips, the second seat's `buy` is followed by a `hand` event.
  - `a void and a second void of one dealer are no foul at a cash table` (F2's count does not apply); `a hand closed bad is deal`.
  - `a buy in my name that I did not send is forged`.
- [ ] **Step 2: Run** → fails (`core/StakesCash.lua` is not in the TOC; then the forfeit event appears).
- [ ] **Step 3: Implement** as specified. `core/StakesCash.lua` begins with a header comment that states the rules of this task in the style of `core/StakesStart.lua`.
- [ ] **Step 4: Run** `bash t.sh` → green; `wc -l core/StakesStart.lua` ≤ 139 (the cap `< 140` binds; no line added, H11), `core/StakesFair.lua` < 200, `core/StakesWatch.lua` ≤ 235, `core/Cash.lua` unchanged.
- [ ] **Step 5: Commit** `feat(stakes): the cash table: no forfeit, my own names, my own sit starts my sitting`.

### Task 6: No void and no away moves a chip (E2, E4, E5)

**Files:**
- Modify: `core/Cash.lua` (`lapsed`: lines 143 and 148; `ask`: the `Cash.submit` line; all inside the line), `core/Member.lua` (`Member.unasked`), `core/StakesCash.lua` (`s.hostHeard`)
- Create: `tests/core/stakes_cash_void_test.lua`

**Interfaces:**
- Produces:
  - Host, `lapsed` at a staked table: in stage `commit` the first away of a silent committer is preceded by `{k="void"}` when the hand still runs; in stage `seed` the void is played whether or not seats were named. A fun table plays exactly what it plays today.
  - `s.stepAsks = { k = <dueKey>, n = <how often> }`: the dealer's client counts its asks for the step that is due, **an ask only while my client has heard the host within `C.FAIR_ASK_GAP` before sending it** (H14). `s.hostHeard` is the `env.now()` of the last EV, SNP or TCK of the host that my client took, stamped in `core/StakesCash.lua`'s wrapped `applied` and `adopted` and by the member's TCK path. Honest cost, stated in Addendum 10 (Task 13): a host that ignores my step right after a fresh TCK is caught only by a second counted ask.
  - `Member.unasked` at a staked table: a `void` in stage `commit` is asked for once `FAIR_WAIT − AUTO_GRACE` has passed since the open by my clock (an honest host voids there now); an `away` of my dealt-in, unfolded seat while the hand runs is unasked in every stage; a `void` of a dealt hand is unasked when I deal it and `s.stepAsks.k == s.dueKey` with `n >= 2`.

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_cash_void_test.lua`; every test records the chips of every seat and a copy of `state.cash.took` when the hand begins and compares after)
  - `a commit lapse voids first: the silent big blind keeps its blind`: the big blind's client is muted; after `C.FAIR_WAIT + 1` the host's events are `void`, then `away`; every seat's chips are those before the hand; `cash.took` is unchanged; no member holds a foul.
  - `a seed lapse with no seat named voids first` (the dealer silent): the small blind's chips are back.
  - `a fun table's lapse is as before`: the same script without a stake: `away` and no `void`, the blind stays (the events are compared with the list `e62ddc6` plays, written into the test).
  - `an early void of a commit round is forged on a member; one after the wait is not`.
  - `an away of my live seat in a running hand is forged at a staked table` (a modified host plays it in stage `commit` 14 s after the open, which a fun table takes).
  - `the dealer whose step the host ignores: its void is forged on the dealer (E2)`: the host drops every `ACT {op="step"}`; after `FAIR_WAIT` it voids → the dealer's `stakeFoul == "forged"`; a third player's is nil; every chip is back.
  - `a dealer that asked once and lost its link is not charged`: one ask, then the dealer is offline; the void is no foul on it after it comes back.
  - `a provoked seed lapse returns every chip and is counted by name (E4)`: `s.fairLapses[dealer] == 1`, chips and matrix unchanged.
  - `two asks into a dead link: no foul` (H14): the dealer's link is down for about 6 s from the moment the step is due, two asks are sent into it and lost, and the honest void at `FAIR_WAIT` is no foul on it; with the link up for both asks the same void is `forged`.
  - `a dealer that goes silent at a due showdown voids a lost all-in (C9)` (H10): the dealer's client is muted after the all-in is called; after `FAIR_WAIT` the hand is void, every chip is back, `cash.took` is unchanged, `s.fairVoids[dealer] == 1`, and at two the amber count turns red (`fair.voidMany`).
- [ ] **Step 2: Run** → fails (the blind is gone).
- [ ] **Step 3: Implement.** `core/Cash.lua` stays at 279 lines: the three edits are inside lines 143, 148 and the `Cash.submit` line of `ask`.
- [ ] **Step 4: Run** `bash t.sh` → green; `tests/core/holdem_table_test.lua` unedited.
- [ ] **Step 5: Commit** `fix(holdem): at a staked table a lapse voids before it sits anyone out; the dealer's ignored step is forged`.

### Task 7: A settlement becomes debts, and waits for the book

**Files:**
- Modify: `core/StakesCash.lua`, `core/StakesFair.lua` (`Stakes.audit`: one line), `core/Const.lua` (`CASH_BOOK_WAIT`)
- Create: `tests/core/stakes_cash_settle_test.lua`

**Interfaces:**
- Consumes: Task 3's out records (`st.cash.outs`, `outN`), Task 1's `S` and `"cash"`, F1's `Book:outcome(s, gid, pairs, why, noted)`, `Book:pending`, `Book:final`, `Book:owe`, `Book.word`, the client events `"book"` and `"fair"`, `ns.Book.of(s)`.
- Produces:
  - `s.cashOutSeen` (local): the highest out record my client handled. After every applied event (after the original `applied`), for each record above it, in order: `gid = s.tid .. "/" .. s.seq`; a snapshot only moves the counter (`s.cashOutSeen = st.cash.outN`: no note). **My pairs of all the event's new records are collected first, and one `outcome` call is made per `gid`** (H3: the close settles every seat at one event, so records share a `gid`, and `Book:outcome` and `Book:pending` would keep only the last record's pairs). The `"cashout"` client event and the host's `S` stay one per record.
  - `Stakes.cashPairs(rec) -> {{f, t, c}}` (H1): for each seat `j` of `rec.net` ascending: `n > 0` → `{ f = rec.names[j], t = rec.who, c = n * 100 }`, `n < 0` → the reverse with `-n * 100`; a pair with a name missing is left out. It reads only the record the engine wrote from my own state, never `s.cashNames` or `s.seats`.
  - Client event `"cashout"`: `{ tid, gid, seat, name, chips, bought, pairs, why, at }` (every client, every record; `why`: nil for the seat's own `cashout`, the stand's `why` (`"left"`, `"offline"`) for a seat stood up, kept in `s.cashWhy[seat]` until the hand that folded it ends, `"close"` when the game closed).
  - The client that hosts at that event, not at a bot table: `book:make("S" .. gid .. "|" .. rec.seat, "S", { gid, g = s.game, f = rec.who, c = rec.bought * 100, sk = s.stake, n = <rec.names with rec.who at rec.seat, as a list by seat, false for none>, w = <seats with net > 0>, l = <seats with net < 0>, why = <"left" | "offline" | "close" | nil> })`.
  - My pairs of the event (all new records merged, H3): `client.stakes:outcome(s, gid, mine, "lost", "cash")`, one call per `gid` (the creditor's `D` says `"lost"`, the note's `why` is `"cash"`).
  - `Stakes.sealedAudit(s, gid) -> { read, wait = C.CASH_BOOK_WAIT }`, which `Stakes.audit` returns for a sealed engine at a staked table (so `Book:outcome` writes the note waiting, in one step). `read()` is `Stakes.cashVerdict(s, book, h)` with `book = ns.Book.of(s)` and `h = s.state.hand` taken when the note is written:
    - `book.forged` → `"forged"`, or `"unseen"` when `book.held` (my own key stayed: rule 6a's honest case);
    - else a bad hand `h` in `s.cashBad` (the `"fair"` events that close a hand `"bad"` carry `h`; each sets `s.cashBad[h] = true`) whose record `book.rec[h].who` names me → `"deal"` (H16a: a bad hand before my sit, or one I was not dealt into, does not count here);
    - else the book not `final` → `"unseen"`;
    - else an open hand `x <= h` whose record names me among its players (`rec.who`) → `"unseen"`;
    - else any other bad hand of the game in `s.cashBad` → `"unseen"` (H16a);
    - else nil.
  - The final of a waiting note (`client.cashWaits[gid] = tid`): at the `"book"` event of its table, and when my session is no longer at that table (`"session"`). Then `client.stakes:final(gid)`, and when the note's `owe` time has passed, `client.stakes:owe(gid)` at once; `"debtAsk"` is emitted.
  - The debtor's word: `Book.word` is wrapped: a `"C"` for a body whose game's engine has `cashGame` is my own `D` `{ gid, g, f, t, c = b.c, why = "cash" }` under the key `"O" .. d.key` (the path F1 uses for a wide id). An `N` is unchanged.
  - `Book:owing() -> {{ gid, t, c, key }}`: my final cash notes with foul `unseen` in which I owe `t`, older than `STAKE_OWE_WAIT`, with no debt `gid|me|t` in the ledger and not answered. `Book:admit(key, yes) -> true | nil`: yes writes my own `D` (`why = "cash"`); either answer is remembered for this run.
  - Any seat settled leaves `s.cashNames` (with Task 5's stand; H2). The pairs never read it (H1).
  - `Book.judge` is wrapped for a note of a cash game (the game's engine has `cashGame`), and the wrap acts only when my note has **no pair** `f = me, t = b.t` (H13: `core/StakesClaims.lua:67` falls back to `note.sk`, which at a cash table is 1 BB, and a coincidence must not decide): for a clean final note the claim is contested `N "no"`; for a note whose foul is `unseen` the claim is asked; everything else goes to the original. About 6 lines.

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_cash_settle_test.lua`; `Play.cash(3)`; hands by `Play.hand`; a cash-out is `cl:act({ k = "cashout" })` here, Task 8 adds the button's flow)
  - `a cashout: the pairs owe by the matrix, to the copper`: after three hands Мария cashes out. Every client emitted one `"cashout"` with the same `gid` and `pairs`; each pair's `c` is `|HC.net| × 100` of the host's state before the event; each creditor sent one `D` with `why == "lost"`; the host sent one `S` with `f == Мария`, `c == 1000 * 100`, `w` and `l` the seats by sign; no member sent an `S`.
  - `the sum by pairs is the total result`: the signed copper of Мария's pairs adds up to `(chips − bought) × 100` of her seat before the event.
  - `the debts wait for the book and confirm at the close`: before the close every debt above is `pending` and nobody's `asks()` holds it (the notes wait). `ns.Cash.close(host)`, the hand played out, `sim:run(C.BOOK_WAIT + 5)`: every debt of the close's gid and of Мария's cashout whose debtor still sits is `confirmed`; each debtor's word is its own `D` with `why == "cash"`; `Play.entries(sim, nil, "C")` is empty.
  - `a player who walks to the hall before the keys is asked (C1)`: Гошо stands right after the close event → his debts stay `pending` and are in his `asks()`; `answer(key, true)` writes his own `D` and the debt is `confirmed`.
  - `a /reload mid-game asks only the player that reloaded` (Review Focus 1).
  - `a claim with another amount is contested`: a modified creditor's `D` with `c + 100` → `N` `"amount"`; `a claim from a player I owe nothing is contested`: against a clean, checked note (after the close), `N` `"no"`.
  - `a pre-planted claim at the next event's gid is not confirmed before the book`: a `D` with the right pair and amount is in the ledger before the cashout event → no word of the debtor until the final.
  - `a hand with a missing key: its players are asked, the others confirm (E6)`: the host never publishes Мария's key (its `Book.take` drops it); a player dealt into a hand with her is asked and the debt's note has `foul == "unseen"`; a player who sat out those hands confirms.
  - `a hand that closes bad contests`: a modified dealer client supplies a false river face in a showdown; at the close every debtor's word is `N` `"deal"`.
  - `an unclaimed debt of an unseen note is put to me` (Review Focus 4): the creditor is offline and writes nothing; a debtor whose note is `unseen` has it in `owing()` after `C.STAKE_OWE_WAIT`; `admit(key, true)` writes its own `D`; a debtor whose note became clean and checked later than `STAKE_OWE_WAIT` writes its own `D` at the final by itself.
  - `a settlement my client saw only in a snapshot writes no note`.
  - `nothing is written at a bot table`.
  - `a newcomer on a leaving chair owes nothing of the leaver's hand` (H1): the leaver's pairs name the leaver on every client, and the `S` has the leaver's `f` and `n`; the newcomer's own later pairs name the newcomer; the newcomer's client writes no `D` for the leaver's hand.
  - `the close at three seats: seat 3's note holds both pairs` (H3): seat 3 owes seats 1 and 2 at one event; its note at that `gid` has both pairs, and both creditors' claims are confirmed.
  - `a claim from a creditor my note has no pair for` (H13): a clean, checked note → `N "no"`, even for a claim of exactly 1 BB; a note with foul `unseen` → the claim is asked; a claim with a pair of mine goes to F1's judge unchanged.
  - `a bad hand I was not dealt into reads unseen, one with me in it reads deal` (H16a): a hand closed bad before my sit does not make my note `deal`; a hand closed bad whose players name me does.
- [ ] **Step 2: Run** → fails (no `"cashout"` event).
- [ ] **Step 3: Implement.** The `"book"` and `"session"` listeners are registered by wrapping `Stakes.new` (as it registers `"fair"`), so `core/StakesBook.lua` is not edited.
- [ ] **Step 4: Run** `bash t.sh` → green; `wc -l core/StakesCash.lua` < 260 (if the file would cross it, `Book:owing`, `Book:admit`, the `Book.word` wrap and the `Book.judge` wrap move to a new `core/StakesCashOwe.lua`, cap < 100, TOC right after `core/StakesCash.lua`).
- [ ] **Step 5: Commit** `feat(stakes): a seat's settlement becomes pair debts that wait for the book`.

### Task 8: Buy-in at the chair, „Стани“ as a cash-out, three minutes offline

**Files:**
- Create: `core/CashOut.lua`, `tests/core/stakes_cash_out_test.lua`
- Modify: `core/Client.lua` (`Client.new`: one line, `ns.CashOut.watch(self)` after `ns.Stake.watch(self)`), `core/Const.lua` (`CASH_OUT_WAIT`), `TavernGames.toc` (`core/CashOut.lua` right after `core/Client.lua`, never after `core/Cash.lua`: it wraps `Client.sit` and `Client.stand` at load, and `Client.lua` would redefine them afterwards; H6), `tests/toc_test.lua` (cap `core/CashOut.lua < 140`)

**Interfaces:**
- Consumes: `E.buyRange`, `Stakes.cash`, Task 7's settlement.
- Produces (`core/CashOut.lua` redefines `Client.sit` and `Client.stand` around the originals):
  - `Client:sit(tid, seat, sk, buy)`: as before; `buy` (chips) is kept as `client.cashWant = { tid = tid, n = buy }`. `Client:wantBuy(tid, n)` sets the same (an invitation's yes).
  - `Client:buy(n) -> true | nil, code`: `self:act({ k = "buy", n = n })`; it refuses with `"stake"` while `s.stakeAsk` (a stake I have not accepted cannot play for gold, H15c).
  - On every `"session"` event: while `client.cashWant` names my table, it is a cash table, live, I am seated, my seat's `bought == 0` and `E.buyRange` gives a range, my client plays `buy` with the wish clamped into the range, once per event number; the wish goes when my seat shows the buy, when `buyRange` refuses with `"rebuy"` or `"full"`, and when I leave the table; a `"hand"` or `"phase"` refusal only waits (H15b).
  - `CashOut.owes(s) -> bool`: a cash table, live, I am seated at my accepted stake (not an asked seat), and my seat's `bought > 0`.
  - `Client:stand(now)`: when `not now and CashOut.owes(s)`, it does not stand: `client.cashGoing = { tid, at = env.now() }`, the event `"cashGoing"(tid)`, and `cashout` is played as soon as no running hand holds me (at once, or at the event that ends the hand; once per event number). When my client has applied my own `cashout` (my seat's `bought == 0`), the original stand runs (`"cashGoing"(nil)`). If `C.CASH_OUT_WAIT` passes after a `cashout` I played while no hand held me and it was not applied, the original stand runs without it (C5: my client has no note of that settlement). A hand that deals me in while that wait runs cancels it; it is armed again with the next `cashout` I play (H15a), so „Стани“ never stands me mid-hand and folds what I put in.
  - `Client:stand(true)` and every stand where `CashOut.owes` is false behave as before.

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_cash_out_test.lua`)
  - `sit with a buy-in: my client buys once the game holds my seat`: `cl:sit(tid, 3, sk, 600)` into a running game → after `sim:run(2)` seat 3 has 600 chips, `bought == 600`, one `buy` event. At a table not started yet the wish waits and is played after the start.
  - `a wish outside the range is clamped`: a name that left with 700 chips sits again with a wish of 400 → it buys 700.
  - `„Стани“ between hands: cashout, then the stand; one gid on every client, mine included`: Мария's `db.stakeSeen` holds a note at the cashout event's gid with her pairs; the stand event that follows makes no `"cashout"` event; her key is published; her session is gone.
  - `„Стани“ inside a hand waits for its end`: `cashGoing` is set, she can still act, no `cashout` event before the hand ends, then both.
  - `a cashout that loses the race with the next hand waits for it` (Review Focus 2): the host plays `{k="hand"}` before her `ACT` arrives (`host.session:play(0, { k = "hand" })` right after `cl:stand()`, before `sim:run`) → the `cashout` is not in the host's event log for that hand; after the hand it is; the `"cashout"` event of every client names the same pairs.
  - `a host that never plays my cashout: I stand after CASH_OUT_WAIT and its claims are put to me (C5)`.
  - `the host leaves mid-game: its cashout, its own S, the handoff; the table plays on`.
  - `three minutes offline: the seat is settled and the debts wait for the leaver` (Review Focus 4): `sim:offline(Гошо)`; after `C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER` a stand `"offline"`; one out record, the host's `S` has `why == "offline"`; Гошо's debts are `pending`; `sim:relog(Гошо)`, `sim:settle()` → they are in his `asks()`.
  - `an offline seat loses no blind after its shuffle lapsed`: its chips at the stand are its chips after the hand in which it went silent, less nothing.
  - `heads-up: the other player's cashout and stand end the game with every pair settled`: the table aborts; the player who stays has `chips − bought − cleared == 0`.
  - `an asked seat stands at once`; `a fun table's stand sends what it sent` (no `cashout`, the events compared with the fun list).
  - `the next hand deals me in while the CASH_OUT_WAIT runs: the wait is cancelled` (H15a): I am not stood up mid-hand, nothing I put in is folded, and the next `cashout` I play arms it again.
  - `an asked seat cannot buy` (H15c): `cl:buy(400)` while `s.stakeAsk` → `nil, "stake"`.
  - `a transient refusal keeps my wish` (H15b): a wish made while a hand holds me is played after the hand; it is dropped only by `"rebuy"` or `"full"`.
- [ ] **Step 2: Run** → fails (`client.cashWant` is never played).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `feat(stakes): the buy-in follows my sit; „Стани“ cashes out first; an offline seat is settled`.

### Task 9: A modified host at a cash table (E1, E8)

**Files:**
- Modify: `core/StakesCash.lua` (the book's forged mark as a foul)
- Create: `tests/core/stakes_cash_cheat_test.lua`

**Interfaces:**
- Produces: at the end of the wrapped `applied` and `adopted` of a cash table, `s.book and s.book.forged` → `Stakes.foul(s, s.book.held and "unseen" or "forged")`.

Every test ends with the same three assertions for the victim `V`: no debt with `f == V` is `confirmed` on any client; `V`'s client sent no own `D` and no `C`; and the test's expected word (`N` with a reason, or the debt in `V:asks()`).

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_cash_cheat_test.lua`; the modified host is built as in `tests/core/stakes_cards_test.lua`: its `send` is wrapped so the test chooses what each member gets)
  - `E8: the host ends my hand and the game by forged events, takes my key, and pushes me back`: the host whispers `V` a fold of every other player and a `close`; assert the host received `V`'s key while the real hand runs; it pushes the real snapshot → `V`'s `stakeFoul == "forged"`; at `V`'s next settlement its word is `N "forged"`.
  - `E8: the same, the host makes me ask for the snapshot`: `unseen`; the debt is asked and its note says `unseen`.
  - `E8: the same, the host hands the table to an accomplice`: `unseen`, asked.
  - `E8: my own /reload in a hand, and a snapshot that says the hand and the game ended`: my key goes; `unseen`, asked.
  - `E8 heads-up: the host claims what its own play made`: `N "amount"`.
  - `a move, a buy and a cashout in my name are forged`: three cases, each `N "forged"`.
  - `the host folds me before my clock ran out: forged; after it: clean`.
  - `the host stands me up while my client runs (E1)`: `N "stand"`.
  - `the host shows me another player's fold that the player never made`: my claim against that player gets its `N "amount"`; no debt of the pair is confirmed either way.
  - `the host ends the table while I sit in the running game`: the open note; `N "forged"`.
  - `a start with the host's blinds above mine` (H18b): the host starts a game at the next blind level; my engine plays my own blinds (`newGame` uses my `s.opt`), so the host's minimum raise is refused on my side. Assert the outcome, not the refusal: no debt of mine is confirmed, and the word is `N "amount"` or my `stakeFoul` is `"forged"`. (A host with **lower** blinds is the one whose raises my engine refuses: its minimum raise is below mine. A host with higher blinds is not a case: my engine plays my own blinds and accepts what it sends. Wording fixed in Task 13, after Task 9's review M2.)
  - `an accomplice with chips it never bought costs me only what my matrix says (C6)`: the debt I confirm at a clean, checked close is exactly `HC.net × 100` of my own state.
- [ ] **Step 2: Run** → the E8 tests that rest on the book's mark alone fail.
- [ ] **Step 3: Implement** the mapping. Any other failing test of this file is a finding: fix it in the file the earlier task named, and say so in the report.
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `test(stakes): a modified host at a cash table gets a contest or a question, never a confirmation`.

### Task 10: UI: opening a cash table, the question with the buy-in

**Files:**
- Modify: `ui/NewTableDialog.lua` (`optionSet`, `layout`, `submit`, `buildStake`), `ui/StakePanels.lua` (`askText`, `buildAsk`, `showAsk`, `P.answer`), `ui/Hall.lua` and `ui/HallPeers.lua` wherever a table's stake is written, `ui/InviteToast.lua` only if `acceptStaked` needs the wish passed, `locale/bg.lua`, `locale/en.lua`, `tests/ui/stake_test.lua`, `tests/ui/hall_test.lua`

**Interfaces:**
- Consumes: `Games.resolve(id, opt, staked)`, `E.stakeOf`, `HoldemCash.MIN_BB`/`MAX_BB` (the engine's `ns.HoldemCash`; the UI module is `ns.HoldemCashView`, H7), `Client:sit(tid, seat, sk, buy)`, `Client:wantBuy`.
- Produces:
  - The dialog, for a game whose engine has `stakeOf`: with „Със залог“ chosen the gold and silver boxes are hidden, the options with `at = "fun"` are hidden and those with `at = "stake"` shown, a line under the blinds says `dialog.cash.range`, and `submit` passes `stake = engine.stakeOf(opt)` with only the options of a staked table. With „Само за удоволствие“ the dialog is what it is today. This replaces the one-line skip of `at = "stake"` options that Task 3 put into `optionSet` with the full staked/fun switch (H8).
  - The question at a chair or a hall row of such a table: `stake.ask.cash` with the blinds and the range, the rebuy line of the table's mode, `stake.ask.cards`, and a stepper: „−“ / „+“ in steps of 10 BB between 40 and 100, default 100, labelled `stake.ask.buy`. „Приемам и сядам“ calls `client:sit(tid, seat, sk, bb × blinds)`; from an invitation it calls `client:wantBuy(tid, n)` and then accepts the invitation. The question of an asked seat (`"stakeAsk"`) has no stepper.
  - The hall's stake text for such a table: `hall.blinds`.
  - The opener is asked nothing: it buys in at the table with „Вход“ (Task 11), as anybody may who sat down without a wish.
- Strings (bg; the money values are formatted by the existing `money`):
  - `dialog.cash.range` = „Блайндове %s/%s. Всеки сяда с вход между %s и %s.“
  - `opt.holdem.rebuy` = „Докупуване“, `optv.holdem.rebuy.none` = „Без“, `optv.holdem.rebuy.bust` = „Когато свършат чиповете“, `optv.holdem.rebuy.top` = „Винаги до входа“ (H8: the dialog, `Widgets` and `TableFrame`'s meta line build their keys as `opt.<game>.<id>` and `optv.<game>.<id>.<value>`)
  - `stake.ask.cash` = „Блайндове %s/%s. Сядаш с вход между %s и %s в истинско злато. Докато играеш, не се мести голд. Като станеш, аддонът записва кой на кого колко дължи.“
  - `stake.ask.rebuy.none` = „Без докупуване: загубиш ли входа, край за тази игра.“, `stake.ask.rebuy.bust` = „Докупуваш нов вход, когато чиповете ти свършат.“, `stake.ask.rebuy.top` = „Докупуваш по всяко време между ръцете, най-много до %s.“
  - `stake.ask.buy` = „Вход: %d големи блайнда = %s“
  - `hall.blinds` = „%s/%s“

- [ ] **Step 1: Write the failing tests** (`tests/ui/stake_test.lua`, with `Play.staked(w.ns, "holdem")`): `the dialog of a staked Холдем hides the amount and the stack and offers the rebuy mode`; `its table opens at the stake of its blinds` (`sk == 2000` for blinds 20, `opt.rebuy == "top"`, no `opt.stack`); `a fun Холдем dialog is unchanged` (the option groups and the `openTable` argument as today); `the question shows the range, the mode and the dealer warning, and steps the buy-in from 40 to 100`; `its yes sits with the stake and the buy-in` (the spy on `client.sit` got `(tid, seat, 1000, 600)` after four „−“); `an invitation's yes keeps the wish`; `the hall writes the blinds of a cash table`; `the rebuy labels are read from opt.holdem.rebuy and optv.holdem.rebuy.* in the dialog and in the table's meta line, none shows its key` (H8).
- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `feat(ui): a cash table in the dialog and the question with the buy-in`.

### Task 11: UI: „Сметка на масата“, „Докупи“, the stand, the bill

**Files:**
- Create: `ui/games/HoldemCashView.lua`, `tests/ui/holdem_cash_test.lua`
- Modify: `ui/games/HoldemModel.lua` (`M.build`), `ui/games/HoldemView.lua` (two buttons, the call of the panel's update), `ui/TableFrame.lua` (`TableFrame.stand`, `TableFrame.standCosts`), `ui/StakePanels.lua` (`P.billRows`, `P.bill`: the reason lines of a cash note), `ui/Accounts.lua` (the question list and the entry line), `ui/LedgerTab.lua` (the label of `why = "cash"`), `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`, `tests/toc_test.lua` (cap `ui/games/HoldemCashView.lua < 300`), `tests/ui/accounts_test.lua`, `tests/ui/stake_test.lua`

**Interfaces:**
- Consumes: `st.cash`, the staked seat record, `E.buyRange`, the client events `"hand"` (its `last.took`), `"cashout"`, `"cashGoing"`, `client.stakes:owing()`, `:admit`, `CashOut.owes`.
- Produces:
  - `M.build(s, want)` gains `m.cash` at a staked table (nil at a fun one): `{ mode, mine = { { seat, name, took, gave, net } }, all = { { seat, name, bought, chips, net } }, lo, hi }`: `took` = `cash.took[me][seat]`, `gave` = `cash.took[seat][me]`, `net` their difference; in `all`, `net = chips − bought`; `lo, hi` = `E.buyRange` for my seat, nil when it refuses (inside my hand, after the close, a mode that forbids it; H15b) and nil while `s.stakeAsk` (H15c). Chips are shown as money (`chips × 100` copper).
  - `ns.HoldemCashView` (H7: not `ns.HoldemCash`, the engine's module, which this one would replace at load): `build(view)`, `update(view, s, m)`, `line(client, ev) -> string` (one line of „Ръце“ from a `"hand"` event), `lines(tid) -> {string}` (the newest 30, kept per table for this run).
    - A button „Сметка“ on the table opens a panel 268 × 300 at the felt's top right with three tabs: „Ти срещу всеки“ (per opponent: взел от теб, взел си, нето), „Всички“ (вход, чипове, нето), „Ръце“.
    - A button „Вход“ (my seat has bought nothing) or „Докупи“ (it has) while `m.cash.lo`: a stepper between `lo` and `hi` in steps of 10 BB (the ends always reachable) and „Потвърди“ → `client:buy(n)`.
  - `TableFrame.stand`: at a cash table where `CashOut.owes(s)`, „Стани“ calls `client:stand()` and stays at the table; the news line says `cash.going`; the hall is shown when my session ends. `standCosts` is false for an engine with `cashGame`.
  - The bill: a cash note's reason line is `bill.cash` (or `bill.cash.close`), and while the note waits, `bill.cash.wait`.
  - „Сметки“: a question for each `owing()` entry (`ask.cash.owe`, yes → `admit(key, true)`, no → `admit(key, false)`); a debt question whose note is a cash note with `unseen` adds `ask.cash.unseen`; my entries list writes an `S` as `accounts.entry.S`.
- Strings (bg):
  - `cash.panel` = „Сметка на масата“, `cash.tab.mine` = „Ти срещу всеки“, `cash.tab.all` = „Всички“, `cash.tab.hands` = „Ръце“
  - `cash.col.gave` = „взел от теб“, `cash.col.took` = „взел си“, `cash.col.net` = „нето“, `cash.col.bought` = „вход“, `cash.col.chips` = „чипове“
  - `cash.hand` = „#%d %s взе %s с %s (%s)“, `cash.hand.fold` = „#%d %s взе %s (%s)“, `cash.hand.from` = „%s от %s“, `cash.hand.you` = „теб“, `cash.hand.void` = „#%d анулирана, чиповете са върнати“
  - `cash.buy` = „Вход“, `cash.rebuy` = „Докупи“, `cash.buy.ok` = „Потвърди“
  - `cash.going` = „Ставаш след края на ръката. Сметката ти се записва.“
  - `bill.cash` = „%s стана от масата. Сметката по двойки:“, `bill.cash.close` = „Играта приключи. Сметката по двойки:“, `bill.cash.wait` = „Ръцете се проверяват с ключовете. Остани на масата, за да се потвърди сметката ти сама.“
  - `ask.cash.unseen` = „Ръцете от тази игра не са проверени при теб.“, `ask.cash.owe` = „%s не е записал вземане. Според твоя аддон му дължиш %s от Холдем. Да го запиша ли?“
  - `accounts.entry.S` = „%s стана от Холдем (вход %s)“, `why.cash` = „Холдем“

- [ ] **Step 1: Write the failing tests** (`tests/ui/holdem_cash_test.lua`, `tests/helpers/frames.lua`): `the model of a staked table has the three views and a fun one none`; `the line of a hand names the winner, the hand and where each silver came from` (the spec's example: `"#36 Kiro взе 1g 20s с две двойки (40s от теб, 80s от Nadya)"` from a `"hand"` event with `last.took = { [3] = { [1] = 40, [2] = 80 } }`, me in seat 1); `a split pot gives one line per winner`; `a voided hand says so`; `„Вход“ before my first buy, „Докупи“ when the mode allows, neither inside my hand nor while my stake is still asked (H15c)`; `the stepper stays inside the range and „Потвърди“ buys`; `„Стани“ at a cash table keeps the table open until the cashout, then goes to the hall`; `the bill of a cash-out lists the pairs and says it waits for the keys`; `a debt nobody claimed is asked in „Сметки“ and its yes writes my D` (`tests/ui/accounts_test.lua`).
- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bash t.sh` → green; `wc -l ui/TableFrame.lua` < 600.
- [ ] **Step 5: Commit** `feat(ui): „Сметка на масата“, the buy-in button, the stand and the bill of a cash table`.

### Task 12: The switch, and the whole road

**Files:**
- Modify: `engines/holdem.lua` (`stakes = true` in the engine table), `tests/core/stake_test.lua` (`a stake is refused for a game that is not ready`: Холдем was the last such game; the test now registers a throwaway engine without `stakes` through `tests/helpers/fake_engine.lua` and asserts the refusal for it; the fake `TBL` of line 130 moves to that engine), every F3 test file (the `Play.staked("holdem")` line and its `restore()` go), `tests/helpers/play.lua` (`Play.staked` and its entry in `pending` are removed again, H5)
- Create: `tests/core/stakes_cash_flow_test.lua`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_cash_flow_test.lua`; `funLog`, `chunks` and `ser` are copied from `tests/core/stakes_f2_flow_test.lua`)
  - `an evening at a cash table`: six players (`Play.cash(6, { blinds = 10, rebuy = "bust" }, { 400, 600, 800, 1000, 1000, 500 })`), hands by `E.bot`. In order: 12 hands; one player `/reload`s; 8 hands; a player with no chips buys again; one player cashes out and leaves; one goes offline and is stood up after 180 s; 8 hands; the host stands (the table goes on under its successor); 6 hands; the new host presses „Приключи“; `sim:run(C.BOOK_WAIT + 10)`. Asserted:
    - every `"cashout"` event of the client hosting at the time has, for each of its pairs, exactly one debt in every client's ledger with that `gid`, `f`, `t` and `c`;
    - for every settled sitting, the signed copper of its debts is `(chips − bought) × 100` of the out record, and over the whole evening the signed sum over all players is 0;
    - the debts of the players seated at the close whose clients saw every event are `confirmed` by their own `D` (`why == "cash"`); those of the player that reloaded, of the one that left and of the one stood up offline are `pending` and in that player's `asks()` (the offline one after `sim:relog`);
    - no `C`, no `R`, no `"forfeit"`; one `S` per out record; no hook raised (`env.strictHooks`).
  - `a fun-only Холдем evening is byte-identical` (H9): `funLog` as copied from `tests/core/stakes_f2_flow_test.lua` waits for the seats to fill and loops until `gameOver()`, which Холдем never reaches (`start = "host"`, no end by play), so the copy gets a Холдем branch: `host:startGame()`, a fixed 10 hands by `E.bot` with the shared generator, `ns.Cash.close(host)`, the hand played out, then `sim:run(C.BOOK_WAIT + 10)`. `funLog("holdem", 3, 1)` through `chunks()` equals the line count and the chunk hashes of the same function run on a worktree of `e62ddc6` (`git worktree add <scratch>/tg-e62 e62ddc6`, run the generator there once, paste its output into `FUN_E62DDC6`, `git worktree remove`).
  - `a client of the F2 version in the guild keeps cash debts pending and the sync settles`: its `take` refuses `S` and a `D` with `why == "cash"`; after a short evening (three players, one cashout, the close) every cash debt is `pending` on it, `View.net` of every pair is 0 there, and a new member's login needs at most two exchanges with it.
  - `the message budget of a staked hand`: an ordinary staked hand at six seats with the watcher, and a full ring, are measured (whispers and packed bytes, as `tests/core/holdem_table_test.lua` pins the fun ones) and pinned at the measured value + 5 %; the packed size of a staked snapshot at six seats is pinned the same way. If the ordinary staked hand is more than 10 % above the fun pin (23 500 B), stop and report BLOCKED with the numbers.
  - `the six-seat close costs` (H17): a close at six seats makes six `S`, up to 15 creditor `D` and up to 15 debtor `D`; the GUILD messages and parts per client (through `Net:afford`'s 10 parts per 10 s queue, `LedgerSend.lua:66–75`) are measured and pinned at the measured value + 5 %.
  - `a bot declines a staked Холдем invitation and fills no staked table`.
- [ ] **Step 2: Run** → the evening fails at `openTable` (`"stake"`) once the `Play.staked` lines are gone.
- [ ] **Step 3: Implement** the flag and the test edits; remove `Play.staked` from `tests/helpers/play.lua`.
- [ ] **Step 4: Run** `bash t.sh` three times → green each time (if the evening takes more than 20 s, halve the hand counts and say so in the report).
- [ ] **Step 5: Commit** `feat(holdem): Холдем takes a stake`.

### Task 13: The rules book, Addendum 10, the documents, the check list

**Files:**
- Modify: `core/Help.lua` (topic `stakes` gains the blocks below; topic `holdem` gains one block that points to them), `locale/bg.lua`, `locale/en.lua`, `tests/core/locale_help_test.lua` (the pinned `help.soon.*` lines and the quoted-label check), `docs/superpowers/notes/engine-contract.md` (Addendum 10), `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` (a section „Stage F3 additions“ after „Stage F2 additions“: this plan's wire table, the engine's new optional fields `cashGame`, `stakeOf`, `buyRange`, the option field `at`, the session and client fields, the events `"cashout"` and `"cashGoing"`, the two constants), `docs/superpowers/notes/2026-11-21-rulings.md` (a section "Stage F3": the tables of "Residual rulings" with the test that pins each, every "Decision:" with its cost, the rulings made during execution; in "Accepted residuals" the Stage E items are marked ruled, with a pointer), `docs/superpowers/plans/2026-11-23-stakes-roadmap.md` (the F3 table's "Expected ruling" column gets the ruling as built; nothing else)
- Create: `docs/superpowers/notes/2026-11-stageF3-ingame-checks.md`

**Interfaces:** none (texts).

- Strings (bg), each a block of the topic `stakes`:
  - `help.stakes.holdem` = „В Холдем със залог всеки сяда с вход между 40 и 100 големи блайнда. Един чип е един силвър. Докато играете, не се мести голд: аддонът помни за всеки пот от кого е дошъл всеки силвър.“
  - `help.stakes.holdem.example` = „Иван, Мария и Kiro играят на 10s/20s. Kiro печели пот от 1g 20s: 40s са от Иван и 80s от Мария. По-късно Иван взима 30s от Kiro. Kiro става: Иван му дължи 10s, Мария му дължи 80s. Сборът по двойки е точно печалбата на Kiro.“
  - `help.stakes.holdem.rebuy` = „Докупуването се избира при отваряне на масата: „Без“, „Когато свършат чиповете“ или „Винаги до входа“. Станеш ли и седнеш ли пак в същата игра, не получаваш нови чипове даром: носиш поне това, с което си станал.“
  - `help.stakes.holdem.stand` = „„Стани“ записва сметката ти след края на ръката. Изчезнеш ли за 3 минути, аддонът те вдига сам и записва сметката. Дълговете се потвърждават сами, когато домакинът натисне „Приключи“ и ръцете се проверят с ключовете. Станеш ли по-рано, аддонът те пита за всеки твой дълг.“
  - `help.stakes.holdem.dealer` = „Аддонът на раздаващия знае тестето на ръката, която раздава. В Холдем това са картите на всички. Играй Холдем за голд само с хора, на които вярваш. Раздаващият може и да анулира ръка, като замълчи, когато е негов ред: чиповете се връщат, а анулирането се брои по име.“
  - `help.soon.p` = „Залози има на всички игри в механата.“, `help.soon.example` = „Искаш да играеш Холдем за злато? Отвори маса „Със залог“ и избери блайндовете.“ (H18d: the old texts say Холдем for gold is coming; no game is named as coming any more.)

- [ ] **Step 1: Write the failing test** in `tests/core/locale_help_test.lua`: `stage F3 in the stakes topic: the five Холдем blocks, bg and en, used verbatim`, and the `help.soon.*` assertion now names no game as coming.
- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Write the texts and the documents.**
  - **Addendum 10** states, as built: the files; the wire table; chips and `sk`; the engine's staked rules (seat record, `buy`, `cashout`, `HC.range`, where a seat is settled, the identity); the attribution algorithm; `Games.resolve`'s `at`; my note's `o` and `how.o`; the cash rules of the extension (no forfeit, `s.cashNames`, the snapshot checks, my own sit); void before away and `Member.unasked` at a staked table (**this amends Addendum 7's silence rules** for a staked table); the settlement, `S`, the debtor's own `D`, the book's verdict for a note (**this amends Addendum 9's "The last hand's verdict"** for a sealed engine), `owing`; the cash-out flow; the residual rulings E1–E10, S1 for Холдем, 10–19 re-judged, C1–C9; the honest cost of H14 (an ask counts only while my client heard the host within `FAIR_ASK_GAP`, so a host that ignores my step right after a fresh TCK is caught only by a second counted ask: a one-sided loss); that after a `/reload` all earlier waiting notes of that game come back asked (H16b); the refusal of an `S` with 64-byte names (H17); the decisions with their cost; every number measured in Task 12.
  - **The check list** (`2026-11-stageF3-ingame-checks.md`, each row `not yet measured`): open a staked table at each blind level; the question and the stepper; buy-in, rebuy in each mode; a hand with a side pot against the panel's three views; „Стани“ between hands and inside a hand; a `/reload` mid-game (the question at the cash-out); a disconnect for three minutes; the host's leave; „Приключи“, the 30 s of the keys, the bill turning from „чака потвърждение“ to confirmed; walking to the hall before the keys; payment of a cash debt by trade and by mail; an F2-version client beside the table (the row stays pending there); the time of a staked hand at six seats on a real link; a lapse at a staked table (the blind comes back); the dealer disconnects at the river of an all-in: the hand is void and counted by name (C9).
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `docs: Addendum 10, the rules book and the check list of stage F3`.

## After the last task

A whole-stage review over `e62ddc6..HEAD` with the cheating-host probes of F2's final review as its model: for every route in "Residual rulings" the reviewer tries to make a victim's client write its own `D` for a debt it did not see whole, clean and checked. Then the in-game check list, and the user's answer on S1.
