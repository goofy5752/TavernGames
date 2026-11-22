# Tavern Games Stage F2 (залози за Сантасе, Белот и Табла) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A guild member opens a Сантасе, Белот or Табла table „Със залог“; when the match ends or somebody leaves, the right people owe the right amounts in the guild ledger (in Белот two transfers, and a leaver pays both opponents alone), and the debtor's own client confirms the debt by itself only when every hand and every throw of that match closed clean on it.

**Architecture:** Nothing new goes on the wire. The always-on extension `stakes` of F1 already runs at any staked table; F2 teaches it three things in three new small files beside it: who owes whom in a team game and at a leave (`core/Stakes.lua`, `core/StakesBook.lua`), when the next match of a table may begin (`core/StakesStart.lua`), and what the fairness layer of the game (the `"fair"` verdicts of `core/Deal.lua`, the dice counts of `core/Dice.lua`) means for my debt (`core/StakesFair.lua`). The three engines then get `stakes = true`, which by itself switches on F1's forged-move check for Табла. Four F1 leftovers (residuals 24–27) are closed in the ledger and payment files they belong to.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), the stage 1 Ace3 subset, `core/Sha256.lua`, `bash t.sh`, `tests/helpers/sim.lua` (multi-client), `tests/helpers/wow.lua`, `tests/helpers/frames.lua`.

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.4, 5.6, 6.3, 6.4, 6.5, 6.6). Roadmap: `docs/superpowers/plans/2026-11-23-stakes-roadmap.md` (F2, its residual table, "The one rule the whole stage rests on"). What F1 built: `docs/superpowers/notes/engine-contract.md` Addendum 8 (Task 11 adds Addendum 9) and `docs/superpowers/plans/2026-11-23-stageF1-ledger-payments.md`. The fairness layers: Addenda 2–6 of the engine contract. Rulings log: `docs/superpowers/notes/2026-11-21-rulings.md`.

**Stage F2 starts on `feature/games` at `88a48e7` (1481 tests).** Names are binding; line numbers are from that commit and may move.

**Precondition, not met when this plan was written:** every row of `docs/superpowers/notes/2026-11-stageF1-ingame-checks.md` still reads `not yet measured`, and the F1 plan asked for those results before F2. Nothing in F2 depends on a trade or mail API answer except Task 8 (the mail guard), which is written against both outcomes. Rows 2–5 and 29–32 of that list should be measured before F2's own check list (Task 11) is run.

## Pre-flight amendments

The pre-flight scan of this plan (`.superpowers/sdd/2026-11-24-stageF2-card-dice-stakes/preflight.md`, findings G1–G19) was accepted in full as proposed (`progress.md`). Each ruling is written into the task it touches; this table says where.

| # | Ruling in one line | Landed in |
|---|---|---|
| G1 | One outcome per game is decided by the event (`quits` in `applied`, `Book:settle(s, quits)`), not by `r.left`; the staked R moves from `Book:result` to `Book:settle` | Task 1 (and the constraint "One outcome per game") |
| G2 | A partnered leaver confirms by itself only once the ledger holds exactly one R of that game naming its own seat; else wait, then ask; new residual S8 | Task 1 (`core/StakesClaims.lua`); S8 in "New in F2"; Task 11 |
| G3 | A claim from a creditor I do not owe, against my clean final note, gets `N "no"` (also in the `stakeLeft` branch of a partnered engine) | Task 1 |
| G4 | `hold` also holds while a seated player is silent; a host with no known end time holds a full `Stakes.gap` (`s.stakeHoldFrom`); the held-start test is restated | Task 2 |
| G5 | `STAKE_FAIR_WAIT = 40` is added in Task 3, only used in Task 4 | Task 3 (out of Task 4) |
| G6 | `Play.staked(ns, ...)` takes an optional namespace; UI tests apply it to `w.ns` | Task 1, Task 9, Task 10 |
| G7 | `core/StakesWatch.lua` is "≤ 235" after Task 2 | Task 2, caps table |
| G8 | Task 2 makes the one-line `renderStart` edit (`ns.Stakes.gap(s)`) so the UI does not refresh in a loop; Task 9 keeps the rest | Task 2, Task 9 |
| G9 | Review Focus 2 seats Иван and Мария in seats 2 and 4 under Петър's table | Task 1 |
| G10 | `mute`, `grind`, `evs` and the cheating-host scaffolding are copied into the new test files | Task 3, Task 4, Task 5 |
| G11 | `Play.short` records its restore; `Play.restore()` runs every one still pending | Task 1, Task 10 |
| G12 | The Review Focus 3 test is built as the guest dealer's ACT to a loser host; `stakeRec` keeps `h` and `fairHeard` closes it only for that `h` | Task 4 |
| G13 | Task 3's new-host test fixes the dealer or asserts `~= "forged"`; S4 says "every member that follows the new host" | Task 3, S4 |
| G14 | Honest costs S9–S11 | "New in F2"; Task 11 (Addendum 9, check list row 20) |
| G15 | Addendum 9 states the widening of Addendum 8's residuals 2 and 24 | Task 11 (and the row of residual 24) |
| G16 | The first collection of residual 25 walks `store.ev[a]` and `store.tw[a]` unsorted | Task 7 |
| G17 | The mail click hook notes only a money letter, reads both money sources, is cleared at four points; the fake models both click orders | Task 8 (check list row 16 in Task 11) |
| G18 | Holdem in `stake_test` uses six seats | Task 10 |
| G19 | `help.stakes.leave` names the Белот partner exception | Task 11 |


## The one rule, and how F2 applies it

**A debt counts only once the debtor's own client has confirmed it, and that client confirms automatically only what it saw itself, whole and clean.** For the three games "whole and clean" is:

- **whole:** my client applied every event of the match itself, from the start event on. Any snapshot that is not the very state I hold (a login, a `/reload`, an asked resync, a new host) makes the match `unseen`: the debt is put to me.
- **clean:** no foul of F1 (`forged`, `stand`), no hand that closed `"bad"` on my client and no dice foul. Then the debt is contested by my client with the reason `deal` (cards) or `dice` (Табла).

Every residual below is ruled against this rule; the complete list is in "Residual rulings".

## Global Constraints

Everything in the stage 1, A–E and F1 constraint files still holds. Added for F2:

- **Fun tables are untouched.** A table without a stake sends and takes exactly the bytes of `88a48e7`: no new event, message, field or timing. Every new branch is behind `s.stake ~= nil` (or runs only in the extension `stakes`, which a fun table never walks). `tests/core/stakes_flow_test.lua` `a fun-only evening is byte-identical but for HI.ld and R` stays green unedited, and Task 10 adds the same pin for the three games.
- **Protocol stays `v=1`**, prefix `TAVG`, GUILD + WHISPER only. **No new message and no new field.** The complete list of what changes on the wire:

  | where | change | meaning |
  |---|---|---|
  | `TBL.sk`, `SNP.tbl.sk`, `SIT.sk`, `INV.sk` | now accepted for `santase`, `belot`, `tabla` (`engine.stakes == true`) | as F1 |
  | ledger `N.why` | two more values: `"deal"`, `"dice"` | my client contests because a hand, or a throw, was not clean on it |
  | `EV` timing at a staked table of a game with `E.again` | the host's start after a leave and a refilled seat waits for the break | see "The next match" |

  A client of the F1 version refuses an `N` with a reason it does not know (Addendum 8's forward-compatibility rule) and does not list a staked table of the three games; for it such a debt stays „чака потвърждение“, which is never a balance.
- **Only `ttt`, `deathroll`, `santase`, `belot`, `tabla` take a stake.** The three get `stakes = true` in Task 10 and not before; a task before it that needs a staked table of them sets the flag in its test file through `tests/helpers/play.lua` (`Play.staked`, restored at the end of the file; a UI test applies it to its own `w.ns`, ruling G6). `holdem` stays without it (F3).
- **Who owes whom.**
  - A match that ends by play: `Stakes.pairs` (every loser owes every winner the stake) for an engine without `E.teams`; `Stakes.matched` for one with it: winners and losers each sorted by seat, the i-th loser owes the i-th winner the stake. Белот: two transfers, never four.
  - A leave („Стани“, offline 180 s) in a running match: the leaver owes the stake to every other player of the roster **except its partner** (`E.partner(seat)`, Белот only). The partner owes nothing and is owed nothing. A second stand after that event costs nothing: the match is already over.
  - The most a player can lose at one table: `Stake.worst`: Death Roll `stake × (maxSeats − 1)`; an engine with `E.teams`: `stake × 2`; else the stake.
  - One outcome per game: an event that both ends the match in the engine (`E.leave`, a `"result"`) and is a stand of a roster seat is settled once, by the forfeit path, and the **event** decides it, not `r.left` (Сантасе's result has none): in `ns.Ext.stakes.applied` the forfeit condition (`seat == 0 and a.k == "stand" and live and roster and type(roster[a.seat]) == "string"`) is computed once as `quits` and `Book:settle(s, quits)` drops the result when it is set (no outcome, no `R`). At a staked table the host's `R` for a match that ended by play is written by `Book:settle` (it moved there from `Book:result`); `Book:result` keeps the fun table's `R` exactly as it is (`r.sk == nil`), and the engines are not touched. The forfeit's `R` is `l = {leaver's seat}`, `w` = the seats it owes, written by the host, or by the successor when the host is the leaver, as in F1.
- **The next match (`E.again`: Сантасе, Белот, Табла).** At a staked table no match begins sooner than `STAKE_BREAK_MATCH = 30` s after the last one ended, by the host's clock: the host's „Нова игра“ answers `"break"` until then, and a table that fills up again after a leave starts by itself only when the break is over (the hook `hold`). A member's client takes a start as clean when the break has passed by its own clock (`AUTO_GRACE` left for the transport); an earlier one is `forged` against the new match. Staying seated through the break is the acceptance of the next match; the bill says so. Морски шах and Death Roll keep F1's rules (`STAKE_BREAK = 10`).
- **Fouls and their ranks** (`Stakes.RANK`): `forged = 4`, `roll = 3`, `deal = 3`, `dice = 3`, `stand = 2`, `unseen = 1`. A game has `roll`, `deal` or `dice`, never two of them. `StakesClaims` contests (`N`) for `forged`, `roll`, `deal`, `dice`, `stand`; asks for `unseen`.
- **What a closed hand means for my debt** (`Stakes.fairFoul`, from the `"fair"` event of `core/Deal.lua`; "my side" = me and the player in my partner's seat):

  | verdict on my client | foul |
  |---|---|
  | `"ok"` | none |
  | `"unseen"` | `unseen` |
  | `"bad"`, `why = "announce"` | none (the engine scored that announce 0 on every client; Addendum 5) |
  | `"bad"`, `why = "noreveal"` and the dealer is on my side | `unseen` |
  | any other `"bad"` | `deal` |
  | `"void"`, or `"bad"` `"nodeal"`, the dealer on my side | none (`nodeal` on my side: `unseen`) |
  | `"void"` or `"bad"` `"nodeal"`, the dealer not on my side: that dealer's first in the match | `unseen` |
  | the same dealer's second (`s.fairVoids[name] + s.fairLapses[name] >= 2`) | `deal` |

  The verdict of the last hand comes after the event that ended the match: the note of that match waits for it (`note.wait`, as for a Death Roll verdict) at most `STAKE_FAIR_WAIT = 40` s (`FAIR_WAIT` + `AUTO_GRACE` + 13 s of slack); a hand still open then reads `unseen`. A match that ended by a leave waits for nothing: its running hand gets no verdict (ruling PC3).
- **What the throws mean for my debt** (`Stakes.fairCount`, from the session's dice counts after the extension `dice` has run): a throw closed `"bad"` in this match (`s.diceSeen.bad > 0`) or `s.diceRobbed > 0` → `dice`; `s.diceSeen.unseen > 0` or `s.diceAway > 0` → `unseen`. `s.diceRobbed` (new, per match, reset and kept exactly where `s.diceUnheard` is) counts: a throw my host made alone after my client had sent its commit or its seed for it and my own loading screen does not excuse it; and a running throw my **seed** had left for that died with a host change. A throw made alone while my client had sent nothing is no foul (my own silence); one I logged in over without my kept seed is `unseen` by the login.
- **Snapshots at a staked table of a game with a fairness extension** (`fair` or `dice` in `engine.ext`; `Stakes.judged`): the extension judges what the snapshot did to the hand or the throw (its verdict feeds the rows above). For `stakes` the rule is F1's with one change: a snapshot from a host new to me (`how.changed`) that is not the state I hold is the same match, `unseen` (it is not held against Морски шах's `leadsTo`, which cannot read these states). A snapshot my own host pushed on me unasked that changes my state is `forged`; one I asked for or logged in with is `unseen`.
- **No card face in `db.stakeLog`.** `Stakes.save` stores no state (`st = nil`) for an engine with `view`.
- **Residual 24–27 constants:** `PAY_GUARD_MAIL = 2592000` (30 days: a letter with gold lies in the box that long); `PAY_GUARD = 86400` stays for a trade.
- **Files and caps** (`tests/toc_test.lua`; a cap is never raised):

  | file | lines now | cap | F2 |
  |---|---|---|---|
  | `core/Stakes.lua` | 335 | < 340 | net change ≤ 0: every F2 edit is inside an existing line or replaces lines; no comment line added (the new fouls are described in `core/StakesFair.lua`); the one `quits` line of ruling G1 is paid for by the −2 of `forfeit` |
  | `core/StakesWatch.lua` | 258 | < 260 | Task 2 moves `Stakes.began` and `Stakes.badStart` out first; ≤ 235 after (ruling G7: the cap of `toc_test` binds) |
  | `core/StakesBook.lua` | 220 | < 260 | about +15 |
  | `core/StakesClaims.lua` | 94 | < 120 | about +7 lines (rulings G2, G3) |
  | `core/Session.lua` | 524 | < 540 | +1 line (`startIfFull`), one line edited (`TIMERS`) |
  | `core/Deal.lua` | 700 | ≤ 700 | **not edited** |
  | `core/DealHooks.lua` | 390 | < 400 | **not edited** |
  | `core/LedgerHash.lua` | 95 | < 160 | Task 7; if it would cross, the sorted list moves to a new `core/LedgerSort.lua` (< 120, TOC right after it) |
  | `core/LedgerNet.lua` | 216 | < 240 | Task 6, +3 at most |
  | `core/LedgerStore.lua` | 227 | < 260 | Task 6, +2 |
  | `core/PayGuard.lua` | 64 | < 120 | Task 8 |
  | `ui/TableFrame.lua` | 517 | < 600 | Task 2 edits one line in place (G8); Task 9, +15 at most |
  | new `core/StakesStart.lua` | | < 140 | Task 2 |
  | new `core/StakesFair.lua` | | < 200 | Tasks 4, 5 |

  TOC: `core/StakesStart.lua` right after `core/StakesWatch.lua`; `core/StakesFair.lua` right after it (both wrap hooks of `ns.Ext.stakes`, so they load after the files that define them).
- **Locale.** Every new string in `locale/bg.lua` and `locale/en.lua` with the same keys and placeholders; Bulgarian in „…“ quotes inside texts. The exact Bulgarian is in the task that adds it; the English is the implementer's translation.
- **Existing tests.** No existing assertion changes except the ones a task names (Task 6: the far-id lines of four tests of `tests/core/ledger_net_test.lua`; Task 10: the "not ready" games of `tests/core/stake_test.lua`; Task 11: the topic texts of `tests/core/locale_help_test.lua`).
- Commits are local only, never pushed, never merged; every commit message ends with the attribution trailer the stage folder's `global-constraints.md` names.

## Review Focus

1. **A `/reload` in the middle of a Белот match.** The player that reloaded must be asked about its debt (or the debt owed to it is unaffected); the three others, who saw every hand, confirm by themselves. Pinned by Task 3 (`belot: a /reload mid-match asks only the player that reloaded`).
2. **Both partners press „Стани“ in the same second.** Exactly one of them (the one whose stand the host orders first) owes both opponents; the other owes nothing, and the note its own client wrote for a forfeit that never happened confirms nothing: a claim against it waits for an R that names its own seat and is put to it otherwise (ruling G2, residual S8). Pinned by Task 1 (`belot: both partners stand at once: one leaver, two debts`).
3. **The match ends on the last card and the dealer logs out before the reveal.** The loser's client must not confirm inside the wait, and afterwards contests (`deal`) when the dealer was an opponent, asks when the dealer was on its side, or when the dealer is the silent host and no `noreveal` is ever ordered (asked at `STAKE_FAIR_WAIT`). Pinned by Task 4 (`the last hand is never revealed: the loser waits, then contests`, `my own partner's missing reveal is a question, not a contest`).
4. **The host presses „Нова игра“ the second the bill appears.** It answers `"break"` for 30 s; a guest that pressed „Към залата“ inside the break is in no new match and owes nothing; a start a modified host sends early is `forged` on the guest. Pinned by Task 2 (`the next match waits for the break`, `a start inside the break is forged against the new match`).
5. **A ten-second network hiccup at a throw.** The host throws alone after `DICE_WAIT`; the guest that had sent its commit contests a loss of that match (`dice`), and the host sees „оспорен“. This is the price of closing D3, stated to both players in the rules book. Pinned by Task 5 (`a throw made alone against my commit contests the match from the first one`) and Task 11 (`help.stakes.tabla` says it).

Also pinned: forfeit during the first shuffle (Task 1), a leave by the host (Task 1), offline 180 s in Белот (Task 1), a dealer's void once and twice (Task 4), a host that re-rolls by reloading (Task 5), a host move for my seat in Табла (Task 5), a client of the F1 version in the guild (Task 10).

## Residual rulings

**The roadmap's F2 table.**

| Residual | Ruling | Mechanism, or the reason it may stay | Task |
|---|---|---|---|
| D1 (F8) forged move in an open game | **Closed** at a staked Табла | F1's check (`engine.view or (s.stake and not engine.idle)`), on by `stakes = true`; the host's timeout only after my own clock ran out | 5, 10 |
| D2 (F9) a host reload or silence re-rolls one throw | **Closed by a contest** (priced, no kept seed for the opener) | A running throw my seed had left for that dies with a host change counts in `s.diceRobbed`: foul `dice` from the first one. **Decision:** no `DealKeep` for the opener: a kept seed helps only an honest host, and a `/reload` loses the host role anyway. Cost: an honest host that disconnects in the second between my seed and its seeds event gets my loss of that match contested. | 5 |
| D3 a throw made alone is proved only against the opener's commit | **Closed by a contest** | An alone throw after my client had sent its commit or seed, not excused by my own loading screen: `s.diceRobbed`, foul `dice` from the first one. Cost: Review Focus 5. | 5 |
| D4 the host could look at the guest's seed before publishing | **Re-accepted** | Its own commit is out first; what it can still do with that knowledge (not publish) is D2 and D3. | — |
| D5 after a `/reload` a client takes an alone proof as it fits | **Re-accepted** | A login is `unseen` (F1): never confirmed automatically. | 5 (pin) |
| D6 a loading screen excuses one throw | **Re-accepted** | `s.diceAway > 0` is `unseen`: the match is put to me. | 5 |
| D7 a watcher's false `dodge` | **Re-accepted** | A watcher holds no stake and writes no entry. | — |
| Stage B/C: a dealer's void, no-deal and seed lapse are only counted | **Closed by a contest; no forfeit.** | The count feeds my confirmation: an opponent dealer's first void or no-deal makes the match `unseen` (asked), its second `deal` (contested); my side's cost me nothing. **Decision:** no automatic forfeit for the second void: the host would have to order it and the host may be the cheater; and the cheater's client never confirms its debt anyway, so a forfeit adds nothing a contest lacks. Cost: one free re-deal per opponent dealer and match is paid for only by a question to the loser. | 4 |
| Stage C: nobody acts for an offline Белот player for 180 s | **The spec's forfeit** | The stand (`why = "offline"`) is a leave: the leaver owes both opponents, the partner nothing; the debt waits for the leaver's answer at its login. | 1 |

**F1's deferred residuals.**

| Residual | Ruling | Mechanism | Task |
|---|---|---|---|
| 24 an own id more than `LEDGER_JUMP` above my counter is denied automatically | **Closed: asked, with a ratchet on the answer** | Such an entry is put to me like a crash's (uncounted, never denied unasked); my counter moves above it only when I answer „Мои са“. Cost: a forger can add such questions (bounded by `LEDGER_MINE_ASK`, as residual 2 of Addendum 8, which it widens: Addendum 9 states how, ruling G15). | 6 |
| 25 the sort of a 5 000-entry author's list in one frame | **Closed** | The author's sorted list is kept and a new item is inserted into it; the first build of a session sorts `LEDGER_HASH_ITEMS` items a frame and merges the runs while feeding the hash. | 7 |
| 26 the payer's 24 h guard against slow mail | **Closed** | A guard set by a letter lives `PAY_GUARD_MAIL` (30 days) or until the creditor's `P`. Cost: a letter the creditor's client never records keeps „Плати“ off for 30 days; „Уредено“ by the creditor clears it. | 8 |
| 27 without the `SendMail` hook the guard takes the letter the addon filled | **Closed** | The click of the game's own send button is hooked as well (a frame script hook, no `hooksecurefunc` needed) and reads the recipient and the money; with neither hook no guard is set at all. | 8 |

**Addendum 8's stake-aware residuals 10–19, re-judged for the three games** (all re-accepted; none yields a debt my client confirms):

| # | For Сантасе, Белот, Табла |
|---|---|
| 10 a losing host aborts | No entry is written, so nothing can be confirmed; the next start is `forged` on the members (an abort with every seat full, then a start). The victim loses a win, not gold. |
| 11 a colluding successor | Death Roll only. Табла's twin (a host change over my seed) is D2. |
| 12 message loss and my turn clock | Табла only (the host's timeout): as Морски шах. Cards: the host never moves for my seat. |
| 13 a rollback snapshot | `unseen` or `forged` by the snapshot rule above; the fairness extension adds `round` / `dodge`. |
| 14 one timeout after my login | Табла: `unseen` by the login. |
| 15, 16 a repeated gid; an honest start after my own `/reload` | Asked, never confirmed. |
| 17 a game a snapshot ended has no note | The winner relies on the loser's own `D`; unchanged. |
| 18 claims around a leave | Unchanged; the partner's simultaneous stand is Review Focus 2 and S8. |
| 19 the `R` of a leaving host | Its successor's, as in F1 (constraint "One outcome per game"). |

**New in F2 (accepted, stated in Addendum 9 and where named in the rules book).**

| # | Residual | Why it stays |
|---|---|---|
| S1 | **The dealer's client knows the deck of the hand it deals** (spec 6.3; `help.fair.dealer`). A modified client reads the opponents' cards in every hand it deals, nothing detects it, and the victim's client confirms the debt. This is the one item that does **not** pass the one rule. | **Decision:** re-accepted as the spec's own design, with a plain warning in the acceptance question of every staked card table (Task 9). Closing it needs a deal that no single client knows (mental poker), which Lua 5.1 without big numbers cannot pay for; stage E's sealed deal does not solve it either. Cost: card games for gold are for people who trust each other's clients. **The user should confirm this before the three games are announced.** |
| S2 | Staying seated through the 30 s break is the acceptance of the next match. | **Decision:** F1's rule for Death Roll, with a longer break. An explicit „Реванш“ from every seat needs a table event outside a live match, which `Session:apply` and `Session:onAct` do not take (the file is at its cap). Cost: a player who walks away without „Към залата“ is dealt into the next match and its own client plays its timeouts. |
| S3 | An honest alone throw (lag over 10 s) or an honest host's disconnect inside the seed window contests the guest's loss. | The price of D2 and D3. |
| S4 | Any login or resync of mine during a match makes my debt of it a question; a host change in a card game makes it one for every member that follows the new host. | The one rule, read strictly. |
| S5 | The partner of a leaver has no note, so no bill: it sees the game's own end line. | It owes and is owed nothing. |
| S6 | A sore loser with an honest client can make its own debt a question or a contest (a `/reload`, a pulled cable at a throw). | The debt is then „чака потвърждение“ or „оспорен“ before the whole guild, never a balance; the spec makes a debt official only by the debtor's `CONFIRM`. |
| S7 | A protest forged in my name after the match's last hand closed revises that hand to `"bad"` too late for a note that is already final. | It moves no point and no gold. |
| S8 | A forging host that orders one partner's stand first and writes an `R` naming the other gets that other's confirmation; the first partner is then asked about the honest claims. | Ruling G2. The partner whose stand lost the race waits for exactly one `R` of that game naming its own seat before its client confirms anything (Task 1), so a forged claim alone confirms nothing; a forger that controls the host can still name the other seat. Death Roll's milder twin (the second leaver owes at `q + 1` anyway) stays under Addendum 8's residual 18. |
| S9 | A dealer that disconnects honestly before its last reveal makes its opponents contest (`deal`). | Ruling G14(a): the card twin of S3. |
| S10 | Белот's `"nodeal"` can follow a fourth player's silence in the shuffle, and the second one per dealer contests. | Ruling G14(b). |
| S11 | A loser who goes to the hall before the last reveal is asked: `s.stakeRec` dies with the session. | Ruling G14(c). |

## File Structure

| File | Responsibility |
|---|---|
| `core/StakesStart.lua` (new) | When a staked game may begin: `Stakes.began`, `Stakes.badStart` (moved from `core/StakesWatch.lua`), `Stakes.gap`, the hook `hold` (the break, and a silent seat) and its timer, `s.stakeHoldFrom` |
| `core/StakesFair.lua` (new) | What the game's fairness layer means for my debt: `Stakes.judged`, `Stakes.fairFoul`, `Stakes.fairHeard`, `Stakes.fairCount`, `Stakes.audit` (the pending verdict of a match that just ended) |
| `tests/helpers/play.lua` (new) | Staked tables of the three games in the simulator, driven by the engines' own automatic moves |
| `core/Stakes.lua` | `forfeit` and `quit` ask `Stakes.owed`; `applied` computes `quits`; `RANK`; `save` |
| `core/StakesBook.lua` | `Stakes.matched`, `Stakes.owed`; one outcome per game (`Book:settle(s, quits)`, which also writes the staked `R`); the generic pending verdict (`Book:pending`, `Book:final`) |
| `core/StakesWatch.lua` | the `adopted` hook's rule for a judged game |
| `core/StakesClaims.lua`, `core/Ledger.lua` | the reasons `deal`, `dice`; the partner's wait for the one `R` of a leave (G2); `N "no"` for a creditor I do not owe (G3) |
| `core/Stake.lua` | `Stake.worst` for a team game |
| `core/Dice.lua`, `core/DiceMember.lua`, `core/DiceCheck.lua` | `s.diceRobbed` |
| `core/Session.lua`, `core/Lifecycle.lua` | `startIfFull` asks `hold`; `canStart` uses `Stakes.gap` |
| `engines/belot.lua` | `E.partner`; in Task 10 `stakes = true` (also `engines/santase.lua`, `engines/tabla.lua`) |
| `core/LedgerNet.lua`, `core/LedgerStore.lua` | residual 24 |
| `core/LedgerHash.lua` | residual 25 |
| `core/PayGuard.lua`, `wow/Mail.lua`, `tests/helpers/wow.lua` | residuals 26, 27 |
| `ui/StakePanels.lua`, `ui/TablePanels.lua`, `ui/TableFrame.lua`, `ui/Accounts.lua`, `ui/games/SantaseView.lua`, `ui/games/BelotView.lua`, `ui/games/TablaView.lua` | the staked table of the three games |
| `core/Help.lua`, `locale/*.lua`, the documents | Task 11 |

**New session fields** (local, never sent): `s.holdTimer` (host: the start that waits for the break), `s.stakeHoldFrom` (host: when it took over a table whose end time it does not know), `s.stakeRec = {gid, h, open, late}` (`h`: the number of the last hand) (the match that just ended: its last hand's verdict is still out), `s.diceRobbed`. **New constants:** `STAKE_BREAK_MATCH = 30`, `STAKE_FAIR_WAIT = 40` (Task 3), `PAY_GUARD_MAIL = 2592000`. **No new `env` field, no new client event, no new db key.**

---

### Task 1: Who owes whom: the team match and the leaver

**Files:**
- Create: `tests/helpers/play.lua`, `tests/core/stakes_team_test.lua`
- Modify: `engines/belot.lua` (`E.partner`), `core/Stake.lua` (`Stake.worst`), `core/StakesBook.lua` (`Stakes.matched`, `Stakes.owed`, `Book:result`, `Book:settle`), `core/Stakes.lua` (`applied`: the `quits` flag, G1; `forfeit` lines 221–223 and `quit` line 245: the two loops become calls of `Stakes.owed`; `quit`'s two `stakeLeft` records gain `g = s.game` inside their existing line), `core/StakesClaims.lua` (`Book:judge`: G2, G3)
- Test: `tests/core/stakes_team_test.lua`; `tests/core/stakes_ledger_test.lua` and `tests/core/stake_test.lua` stay green unedited

**Interfaces:**
- Consumes: F1's `Stakes.pairs`, `Book:outcome`, `Book:make`, the `"result"` and `"forfeit"` events.
- Produces:
  - `E.partner(seat) -> seat` in `engines/belot.lua`: `(seat + 1) % 4 + 1`. No other engine has it.
  - `Stakes.owed(s, roster, seat) -> names, seats`: the roster's other players in seat order, without `engine.partner(seat)` when the engine has it.
  - `Stakes.matched(losers, winners, c) -> {{f, t, c}}`: both name lists as given (the caller passes them by ascending seat), the i-th loser to the i-th winner; extra names of the longer list are dropped.
  - `Stake.worst(id, copper)`: an engine with `teams` → `copper * 2`.
  - `Book:settle(s, quits)`: `quits` set (the event is a roster seat's stand) → the result is dropped, no outcome and no `R`; else the outcome as before and, at a staked table, the host's `R` (moved here from `Book:result`, G1).
  - `tests/helpers/play.lua` (`local Play = require("play")`):
    - `Play.NAMES` = `{ "Иван Петров", "Петър Колев", "Мария Стоянова", "Гошо Тодоров" }` (seats 1–4: Иван and Мария are partners in Белот)
    - `Play.staked(ns, ...)` sets `ns.Engines[id].stakes = true` for each id given and returns a function that puts the old values back and then runs `Play.restore()` (called at the end of the test file). `ns` is optional, a table when given, default `Sim.ns`: `Play`/`Sim` share that namespace, but every `Wow.new` builds its own, so a UI test passes `w.ns` (ruling G6)
    - `Play.guild(n, more) -> sim, cl` (`cl[name]`): `n` of `NAMES` plus the names in `more`, each `sim:add`ed, `sim:run(1)`, `sim:settle()`
    - `Play.open(sim, cl, game, sk, n) -> tid`: `NAMES[1]` opens (`access = "guild"`, `turn = 45`, `stake = sk`; `sk = nil` for fun), `NAMES[2..n]` sit in seats 2..n with `sk`, one `sim:run(1)` each; the match is live
    - `Play.step(sim, host)`: the seat on turn at `host`'s table acts from its own client (`engine.bot(view, seat, random)` when the engine has it, else `client:playAuto()`); then `sim:run(1)`; with no seat on turn only `sim:run(1)`
    - `Play.finish(sim, host, limit) -> result`: `Play.step` until `host.session:gameOver()` (error after `limit or 6000` steps); returns the last `"result"` payload `host` emitted
    - `Play.short(id) -> restore`: lowers the engine's match target to 1 so the first scored hand or game ends the match (`E.GOAL` for `santase`, `E.TARGET` for `belot` and `tabla`: all three are read at run time), records its restore as pending, and returns a function that puts the target back
    - `Play.restore()`: runs every `Play.short` restore still pending (the function `Play.staked` returns calls it, so a failing `it` that never reached its own restore cannot leave `E.TARGET = 1` for the files that run after; ruling G11)
    - `Play.debt(client, gid, f, t) -> debt | nil` from `View.of(client.ledger).debts`; `Play.entries(sim, from, k) -> {entry}` (the GUILD `LEV` entries of kind `k` sent by `from`, or by anyone when `from == nil`)

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_team_test.lua`; the file begins with `local restore = Play.staked("santase", "belot", "tabla")` and ends with `restore()`; `SK = 50000`)

```lua
it("Stakes.matched pairs by position; Stakes.pairs is unchanged", function()
  eq(Stakes.matched({ "L1", "L2" }, { "W1", "W2" }, 100), { { f = "L1", t = "W1", c = 100 }, { f = "L2", t = "W2", c = 100 } })
  eq(#Stakes.pairs({ "L1", "L2" }, { "W1", "W2" }, 100), 4)
end)
it("E.partner and the worst case", function()
  local E = ns.Engines.belot
  eq(E.partner(1), 3); eq(E.partner(2), 4); eq(E.partner(3), 1); eq(E.partner(4), 2)
  eq(ns.Stake.worst("belot", 10000), 20000); eq(ns.Stake.worst("santase", 10000), 10000); eq(ns.Stake.worst("tabla", 10000), 10000)
end)
```
Simulator tests:
- `belot: the losers pay the winners in two transfers, not four`: four players, a staked match played to its end (`Play.finish`); with `r` the result: exactly two debts exist on every client for `gid = tid .. "/" .. r.q`, loser of the lower seat → winner of the lower seat and the other two, each `c == SK`, each `confirmed` after `sim:run(3)`; `Play.entries(sim, nil, "D")` for that gid has exactly 2 entries; the host sent one `R` whose `w` and `l` are the result's.
- `belot: a leaver pays both opponents and the partner nothing`: Мария (seat 3) presses `client:stand()` in the running match → on Петър and Гошо a debt Мария → each of them, `why == "left"`, both `confirmed` (her quit note); no debt with `f` or `t` = Иван exists on any client; the host's `R` for that gid has `l == { 3 }`, `w == { 2, 4 }`, `why == "left"`; exactly one `R` and two `D` were sent for that gid (the `"result"` with `left` writes nothing of its own).
- `belot: both partners stand at once: one leaver, two debts` (Review Focus 2, ruling G9): Петър hosts, so open the table by hand, not with `Play.open` (the opener takes seat 1): Иван sits in seat 2, Гошо in seat 3, Мария in seat 4, and the test asserts `E.partner(2) == 4`; Иван and Мария both call `client:stand()` before any `sim:run`; after `sim:run(3)`: the two debts name as `f` the one whose stand the host's event log has first; the other has no debt on any client, its `db.stakeSeen` note for that gid stays without a claim, and after `sim:run(C.STAKE_OWE_WAIT + 5)` it authored no `D`.
- `belot: both partners stand at once: a forged claim against the one whose stand lost the race is asked, never confirmed` (G2): the same seating; a modified opponent client writes a `D` at that gid (`why == "left"`, the table's stake, a creditor in the loser-of-the-race's `stakeLeft.names`) under the opponent's name → that client authors no `C`: the claim is `"wait"` while the ledger holds no `R` of that gid, and in its `asks()` once `C.STAKE_OWE_WAIT` has passed since `left.at`, and at once when the only `R` names the other seat. The first partner's own claims still get their `C` once the single `R` naming its seat is held.
- `belot: a claim from the wrong winner of a clean match is contested` (G3): a staked match played out clean; a modified client writes `D` Иван → Гошо (the loser's other winner, not the one Иван owes) at that gid → Иван's client authors `N` with `why == "no"`, no `C`, and Иван's `asks()` is empty. The same in the leave branch: after Мария's stand a `D` from Иван (her partner, not in her `stakeLeft.names`) at the leave's gid → `N` `"no"`.
- `belot: the leaver's partner then stands: it costs nothing`: after Мария's stand, Иван stands → no further `D` or `R`.
- `belot: three minutes offline is a leave: the debts wait for the leaver` : `sim:offline(Гошо)`, `sim:run(C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER)` → debts Гошо → Иван and Гошо → Мария with `why == "offline"`, `status == "pending"`; Петър has none; `sim:relog(Гошо)`, `sim:settle()`, `sim:run(5)` → Гошо's `client.stakes:asks()` holds both; `answer(key, true)` on both → `confirmed`.
- `santase: one outcome for a leave, not two`: two players; the guest stands mid-hand → the host's `db.stakeSeen` has one note for that gid, one `D` was sent, one `R` (`l == { 2 }`); the leaver's client confirmed; the creditor's `D` says `why == "left"` (ruling G1: not `"lost"`).
- `santase: a forfeit during the first shuffle` : the guest stands right after the start, before the first deal is dealt (`host.session.fair.stage ~= "dealt"`) → the same single debt; no hook raised (`env.strictHooks`); the note has no `wait`.
- `tabla: the host leaves mid-match and its successor writes the R`: Иван (host) stands while a throw is open → Петър hosts; Петър's `R` (`l == { 1 }`, `w == { 2 }`, `why == "left"`), Петър's `D`, Иван's `C`; Иван's client sent no `R`.
- `a fun table of each game writes its R as before`: `Play.open(..., nil, n)` for the three games, one leave each: the host's `R` is the entry `88a48e7` writes (`w`, `l` of the engine's result; `why == "left"` for Белот and Табла, no `why` for Сантасе, whose result carries no `left`: ruling G1), no `D`.

- [ ] **Step 2: Run** `bash t.sh tests/core/stakes_team_test.lua` → fails (`play` is not found; then `Stakes.matched` is nil).

- [ ] **Step 3: Implement**
  1. `tests/helpers/play.lua` as specified.
  2. `E.partner`; `Stake.worst`.
  3. `core/StakesBook.lua`: `Stakes.matched` and `Stakes.owed` beside `Stakes.pairs`. `Book:result`: at a staked table (`r.sk ~= nil`) it writes no `R` (the fun table's `R`, `r.sk == nil`, stays exactly as before). `Book:settle(s, quits)`: when `quits` is set it returns before writing an outcome or an `R` (the forfeit path of the same event writes both); otherwise the host's `R` is written here, and the pairs come from `Stakes.matched` when the engine has `teams` (names of `r.losers` and of `r.winners`, each by ascending seat), else from `Stakes.pairs`.
  4. `core/Stakes.lua`: in `applied`, `local quits = seat == 0 and a.k == "stand" and live and roster and type(roster[a.seat]) == "string"` (the condition of line 282, computed once; the event decides, not `r.left`) and the call `settle(s, quits)`; in `forfeit`, `to, w = Stakes.owed(s, roster, a.seat)` replaces the loop (lines 221–223); in `quit`, `to = Stakes.owed(s, roster, s.mySeat)` replaces the loop of line 245, and the two `stakeLeft` records gain `g = s.game` inside their existing line. Nothing else in the file changes.
  5. `core/StakesClaims.lua`, in `Book:judge` (about +7 lines). In the `stakeLeft` branch: `local E = left.g and ns.Games.engine(left.g)`; when `E and E.partner` and `b.t` is not in `left.names` → `return "N", "no"` (G3). For the confirming `"left"` claim of such an engine (G2) the claim also needs the ledger to hold exactly one `R` of `b.gid` with `#l == 1` and `n[l[1]] == me` (the `R` bodies are found as `Book:claims` finds `D` bodies, through `L:bodies`): no `R` yet → `"wait"` (re-judged on `"ledger"`) until `C.STAKE_OWE_WAIT` has passed since `left.at` (`env.epoch()`), then `"ask"`; more than one `R`, or an `R` naming another seat → `"ask"`. In the final-note branch, `local p, mine; for _, x in ipairs(note.pairs or {}) do if x.f == me then mine = true; if x.t == b.t then p = x end end end` and, before the amount check, `if mine and not p and not note.foul then return "N", "no" end` (G3).
- [ ] **Step 4: Run** `bash t.sh` → green; `wc -l core/Stakes.lua` ≤ 335 (−2 for `forfeit`, +1 for `quits`) and `core/StakesClaims.lua` < 120.
- [ ] **Step 5: Commit** `feat(stakes): team pairs, the leaver pays the opponents alone, one outcome per game`.

### Task 2: The next match of a staked table

**Files:**
- Create: `core/StakesStart.lua`, `tests/core/stakes_again_test.lua`
- Modify: `core/StakesWatch.lua` (`Stakes.began` with its comment, from line 62, and `Stakes.badStart` with its comment, from line 248, leave the file; one line `Stakes.sentIn = sentIn` is added), `core/Const.lua` (`STAKE_BREAK_MATCH = 30`), `core/Session.lua` (`TIMERS` gains `"holdTimer"` inside its existing line; `startIfFull` gains one line), `core/Lifecycle.lua` (`canStart`: `C.STAKE_BREAK` → `ns.Stakes.gap(self)`), `ui/TableFrame.lua` (`renderStart`, line 273: the same one in-line edit, `ns.Stakes.gap(s)`, so the 30 s break is not dated with 10 s and the frame does not refresh every 0.05 s; G8), `TavernGames.toc`, `tests/toc_test.lua` (cap `core/StakesStart.lua` < 140)
- Test: `tests/core/stakes_again_test.lua`, `tests/ui/table_test.lua` (one test); `tests/core/stakes_play_test.lua` stays green unedited

**Interfaces:**
- Consumes: `Play` (Task 1); F1's `s.stakeEndedAt`, `s.stakeStatus`, `s.stakeHad`, `s.stakeRefill`, `Stakes.pend`.
- Produces:
  - `Stakes.gap(s) -> seconds`: `C.STAKE_BREAK_MATCH` for an engine with `again`, else `C.STAKE_BREAK`.
  - `ns.Ext.stakes.hold(s) -> true | nil` (host): true while the engine has `again` and any of these holds: `s.stakeEndedAt` is set and `env.now() < s.stakeEndedAt + Stakes.gap(s)`; `s.stakeEndedAt` is nil, `s.stakeHoldFrom` is set and `env.now() < s.stakeHoldFrom + Stakes.gap(s)`; a seated player other than me was last heard more than `C.SILENT_AFTER` ago (`s.lastHeard[name]`: the sweep of `Succession.lua` stands that seat up in time and the table is then short). It then arms `s.holdTimer` (for the rest of the break, or 5 s for a silent seat, which re-checks until the seat is heard or stood up). The timer calls `s:startIfFull()`, `s:recordChanged()` and emits `"session"`, only while that session is still mine and I host it.
  - `s.stakeHoldFrom` (host, local): `hostChanged` and `adopted` set it to `env.now()` when the state shows the game over (`s:gameOver()`) and `s.stakeEndedAt == nil` (a successor that came in by a snapshot after the end), so that host holds a full `Stakes.gap` from that moment and its members, whose clocks show the real end, do not flag its honest start `forged`.
  - `Session:startIfFull()`: after its first line, `if self.stake ~= nil and self:hook("hold") then return end`.
  - `Stakes.began(s, snap)` and `Stakes.badStart(s)` with the bodies below.
  - The wrapped hook `ns.Ext.stakes.hostChanged`: after the original, a client that hosts an `again` table that is not live arms `s.holdTimer` for `max(0, rest of the break)` (the start an old host was holding is not lost); with `s.stakeEndedAt == nil` and the game over it sets `s.stakeHoldFrom` first and the rest is `Stakes.gap` from it (G4).

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_again_test.lua`, the three games staked through `Play.staked`; `Play.short` for each)

- `the next match waits for the break` (Review Focus 4), once for each of the three games: the match ends at host clock `t`; `host:startGame()` → `nil, "break"` at `t + 29`; `true` at `t + 30`; the new match's `gid` differs and a second debt arises at its end.
- `a guest that goes to the hall inside the break is in no new match`: Сантасе; the guest stands at `t + 5` → no forfeit, no `D`; the host's table is `aborted`, `startGame()` → `nil, "short"`.
- `a start inside the break is forged against the new match`: the host is made to send `EV {k = "start"}` at `t + 5` (call `host.session:event(0, { k = "start", first = 1 })`); the guest's `session.stakeFoul == "forged"`; the match is played out and the guest loses → its client authors `N` with `why == "forged"`, no `C`. The same start at `t + 30 − C.AUTO_GRACE` is clean.
- `a start while the match runs is forged`: as F1's Death Roll test, for Табла.
- `a refilled table starts when the break is over`: Белот; Мария leaves mid-match at `t` (forfeit, table `aborted`); a fifth guild member sits in seat 3 at `t + 5` → still not live at `t + 29`, live at `t + 30`; the three who stayed have `stakeFoul == nil` in the new match; the newcomer too.
- `a refill after the break starts at once`: the fifth member sits at `t + 40` → live in the same second.
- `the held start survives a host change, and never seats a silent player` (G4): Белот, the refill at `t + 5`; the old host is `sim:offline`d at `t + 6` and the new host takes over after `SILENT_AFTER`: there is no start while the old host is silent (the table is not live); when the old host comes back (`sim:online`) and is heard, the match starts by itself, not before `t + 30` by the new host's own clock. A second case: the old host never comes back → after the sweep stands it up the table is stood short (`startGame()` → `nil, "short"`) and no forfeit is written against it.
- `a host that came in by snapshot after the end holds a full break` (G4): Сантасе; the host's successor adopts a snapshot of a finished game (`stakeEndedAt == nil`); a refill at once does not start before `Stakes.gap(s)` from the takeover, and the members' `stakeFoul` stays nil.
- `an abort with every seat full, then a start, is forged` for Сантасе (F1's Морски шах test with the other engine).
- `Морски шах and Death Roll keep their rules`: `Stakes.gap` is 10 for both; `tests/core/stakes_play_test.lua` unedited and green.
- `a fun table of an again game starts and restarts as before`: the host's „Нова игра“ right after the match, and a refill, both start at once (no `hold`: the extension is not walked).
- `the start button is not redrawn in a loop during the break` (G8; `tests/ui/table_test.lua`, `Play.staked(w.ns, "belot")` right after `Wow.new`): the host's frame after a match that ended at `t`: with the clock at `t + 10`, the table frame refreshes at most twice in the next 20 s (once, for the rest of `Stakes.gap(s)`), not every 0.05 s.

- [ ] **Step 2: Run** `bash t.sh tests/core/stakes_again_test.lua` → fails (`Stakes.gap` is nil).

- [ ] **Step 3: Implement.** First move `Stakes.began` and `Stakes.badStart` verbatim to `core/StakesStart.lua` (its header says what the file holds; their callers in `core/Stakes.lua` reach them through `ns.Stakes` at run time, so no call changes) and run `bash t.sh` (green, nothing else changed). Then the new bodies; the two rules they add are the only behaviour change:

```lua
-- A later match of an `again` table rests on the break (badStart), not on my log.
function Stakes.began(s, snap)
  local seat, engine = s.mySeat, s:engine()
  if s.role == "host" or engine.start == "host" or (snap and snap.fresh) then return end
  if engine.again and s.stakeHad then return end
  -- ... the rest as moved (my own sit or „Реванш“ since the last game began)
end

function Stakes.badStart(s)
  local engine = s:engine()
  if s.stakeLive then return true end
  local hosted = engine.start == "host" or (engine.again and s.stakeStatus == "live") -- the host's start
  if not hosted and (s.stakeStatus == "live" or (s.stakeHad and s.stakeRefill ~= "filled")) then return true end
  if not (hosted or engine.again) then return false end
  return s.stakeEndedAt ~= nil and s.client.env.now() < s.stakeEndedAt + Stakes.gap(s) - C.AUTO_GRACE
end
```
`sentIn` is local to `core/StakesWatch.lua`: the added line `Stakes.sentIn = sentIn` there gives it to `began`.
The hook of Task 2 and the two rules G4 adds to it (the timer arm is the session's own timer call, as `armTimers` uses it):

```lua
-- A staked `again` table's start waits for the break, and while a seated player is silent.
function ns.Ext.stakes.hold(s)
  local engine, env = s:engine(), s.client.env
  if not engine.again then return end
  local now, wait = env.now(), 0
  local from = s.stakeEndedAt or s.stakeHoldFrom
  if from then wait = from + Stakes.gap(s) - now end
  for name, at in pairs(s.lastHeard) do
    if name ~= env.me and ns.Util.contains(s.seats, name) and now - at > C.SILENT_AFTER then wait = math.max(wait, 5) end
  end
  if wait <= 0 then return end
  -- arm (replace) s.holdTimer for `wait` s: s:startIfFull(), s:recordChanged(), emit "session", while the session is mine and I host it
  return true
end
```
- [ ] **Step 4: Run** `bash t.sh` → green; `wc -l core/Session.lua` = 525, `core/StakesWatch.lua` ≤ 235 (ruling G7), `core/StakesStart.lua` < 140.
- [ ] **Step 5: Commit** `feat(stakes): the next match of a staked card or dice table waits for the break`.

### Task 3: A staked card table plays: snapshots, a new host, a relog

**Files:**
- Create: `tests/core/stakes_cards_test.lua`
- Modify: `core/StakesWatch.lua` (the `adopted` hook, inside its existing lines), `core/Stakes.lua` (`Stakes.save`, inside its existing line), `core/Const.lua` (`STAKE_FAIR_WAIT = 40`, moved here from Task 4: this task's first test uses it; G5), `core/StakesFair.lua` (created here with `Stakes.judged` only), `TavernGames.toc`, `tests/toc_test.lua` (cap `core/StakesFair.lua` < 200)

**Interfaces:**
- Consumes: `Play`; F1's fouls and `Stakes.leadsTo`.
- Produces:
  - `Stakes.judged(s) -> bool`: the engine's `ext` holds `"fair"` or `"dice"`.
  - In the `adopted` hook: `local prefix = not forward and how.changed and (Stakes.judged(s) or leadsTo(st, prev))`. Nothing else in the hook changes; for a judged game `forward` is always false (`leadsTo` reads only Морски шах and Death Roll states), so: identical → nothing; pushed by my own host → `forged`; from a host new to me → the same match, `unseen`; asked or a login → `unseen`.
  - `Stakes.save`: `st` is `nil` for an engine with `view`.

- [ ] **Step 1: Write the failing tests** (Сантасе and Белот, staked through `Play.staked`; each test reads `client.session.stakeFoul` and, after the match, the ledger)

- `a clean staked santase match: the loser confirms by itself`: `Play.finish`; `sim:run(C.STAKE_FAIR_WAIT + 5)`; one debt, `confirmed`; the loser's entries are one `C` and nothing else. (Until Task 4 lands, the verdict of the last hand is not waited for; the assertion already holds.)
- `belot: a /reload mid-match asks only the player that reloaded` (Review Focus 1): Гошо `sim:relog`s in the third deal; the match is played out; if Гошо's team lost: Гошо's debt is `pending` and is in Гошо's `asks()`, the other loser's is `confirmed`; if it won: both debts `confirmed`. (The test reads the result and asserts the branch that happened; a second run with the seeds of `sim.nextRandom` chosen so that the other team wins covers the other branch.)
- `a new host mid-match is unseen for every member that follows it, forged for none` (G13): Сантасе; the host goes `sim:offline` mid-hand; the test arranges that the new host deals the running hand, so its own `fairHeard` has no void to judge and `stakeFoul` is nil (where the dealer cannot be fixed, assert `~= "forged"`); when the old host comes back (`sim:online`, a snapshot), its foul is `unseen`; Белот: three members follow the new host, each `unseen`, none `forged`.
- `a snapshot my own host pushes on me that changes my hand is forged`: Сантасе; the host sends the guest an unasked `SNP` built from its `snapshotFor` with one more played card; guest `forged`; at the end `N` `forged`.
- `the host plays my card for me: contested as forged`: the scenario of `tests/core/santase_table_test.lua` `it plays my card for me`, at a staked table: `stakeFoul == "forged"`, `N` `forged` (that scenario's scaffolding is a local of that file: copy it into this test file and leave the source unedited; G10).
- `the host stands a present player up: contested as stand` : Белот; the host calls `session:event(0, { k = "stand", seat = 4, why = "offline" })` for the online Гошо → Гошо's client: `N` `stand` on both claims.
- `no card face is saved with my log`: after three plays of mine `env.db.stakeLog.st == nil` at a Сантасе table, and is a table at a staked Морски шах table.
- `a /reload of the dealer mid-hand: the hand goes on, the dealer's debt is a question`: Сантасе; the dealer `sim:relog`s (its `fairKeep` restores the deck); the match is played out; if the dealer lost, its debt is in its `asks()`; the other player's client holds no foul.

- [ ] **Step 2: Run** `bash t.sh tests/core/stakes_cards_test.lua` → fails (the new-host test reads `forged`; `stakeLog.st` is a table).
- [ ] **Step 3: Implement** `STAKE_FAIR_WAIT = 40` in `core/Const.lua`, the two in-line edits and `core/StakesFair.lua` with its header (the table "What a closed hand means for my debt" and "What the throws mean" of Global Constraints, as comments) and `Stakes.judged`.
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `feat(stakes): a judged game's snapshots are unseen from a new host, forged from my own; no faces in the saved log`.

### Task 4: The verdict of every hand feeds the confirmation (Сантасе, Белот)

**Files:**
- Modify: `core/StakesFair.lua`, `core/StakesBook.lua` (`Stakes.new` subscribes to `"fair"`; `Book:outcome` and `Book:quit` use `Stakes.audit` and the new `Book:pending`; `Book:final`), `core/Stakes.lua` (`RANK`, inside its line), `core/StakesClaims.lua` (`BAD`, inside its line), `core/Ledger.lua` (`WHY.N`, inside its line)
- Test: `tests/core/stakes_cards_test.lua` (new `describe`), `tests/core/ledger_test.lua` (one row)

**Interfaces:**
- Consumes: `C.STAKE_FAIR_WAIT` (Task 3); the client event `"fair"` `{tid, game, h, verdict, why, dealer, who, at}` of `core/Deal.lua` (emitted synchronously inside the hook that closes the hand); `s.fairVoids`, `s.fairLapses`, `s.fair`; `s.stakeLive` (as of the last `stakes` hook).
- Produces:
  - `Stakes.RANK.deal = 3`, `Stakes.RANK.dice = 3`; `BAD` of `core/StakesClaims.lua` gains `deal`, `dice`; `Ledger`'s `WHY.N` gains `"deal"`, `"dice"`.
  - `Stakes.fairFoul(s, v) -> "deal" | "dice" | "unseen" | nil`: the cards table of Global Constraints for an engine with `"fair"`; for one with `"dice"`: `"bad"` → `"dice"`, `"unseen"` → `"unseen"`, else nil. "My side": `env.me` and `s.seats[engine.partner(s.mySeat)]` when the engine has `partner` and I am seated.
  - `Stakes.fairHeard(client, v)`: for my staked table only. While `s.stakeLive`: `Stakes.foul(s, foul)`. Otherwise, when `s.stakeRec` is open and `v.h == rec.h` (the verdict of the last hand, not of any hand): `rec.late` = the worse of it and the foul, `rec.open = false`, `client.stakes:final(rec.gid)`. **It reads `s.stakeLive`, never `Stakes.running(s)`:** the start of the next match closes an unrevealed hand inside the fair extension's hook, when a new state already exists but the `stakes` hook has not run.
  - `Stakes.audit(s, gid, left) -> a | nil`, `a = {read = function() -> foul | nil, wait = seconds}`:
    - an engine with `"rolls"` in `ext`: `read` = `ns.Rolls.audit(rec)` with `rec = ns.Rolls.auditOf(s.client, gid) or s`, `wait = C.ROLL_FINAL_WAIT` (F1's behaviour, unchanged);
    - an engine with `"fair"` and without `sealed`, `not left`, and a round still open (`s.fair and s.fair.stage ~= "done"`): `s.stakeRec = {gid = gid, h = s.fair.h, open = true}`; `read` = the worse of `rec.late` and (`rec.open` and `"unseen"`); `wait = C.STAKE_FAIR_WAIT`;
    - else nil.
  - `Book:pending(gid, note, base, a)`: `note.foul` = the worse of `base` and `a.read()`, `note.wait = true` when `a`; a `final` function (once: `note.foul` = the worse of `base` and `a.read()`, `note.wait = nil`, `self:review()`) is kept in `self.finals[gid]` and armed after `a.wait`. `Book:final(gid)` runs it early. `Book:outcome` and `Book:quit` call it in the place of their roll code (`left` = the outcome is a forfeit).

- [ ] **Step 1: Write the failing tests**

`tests/core/ledger_test.lua`, in the `valid` table: `N` with `why = "deal"` and with `why = "dice"` → `true`.

`tests/core/stakes_cards_test.lua`, `describe("the verdict feeds the confirmation")`. A hand is made bad the way `tests/core/santase_table_test.lua` (`a cheating host`, lines 259–360) and `tests/core/deal_cheat_test.lua` do it; a void the way `the dealer comes back without its deck mid-hand` does (`sim:crash(dealer)`). Their scaffolding is local to those files: copy what is needed into this test file and leave them unedited (G10).

```lua
it("Stakes.fairFoul: the table of the plan", function()
  local s = fakeSession{ me = "Иван Петров", seat = 1, seats = { "Иван Петров", "Петър Колев", "Мария Стоянова", "Гошо Тодоров" }, game = "belot" }
  local function f(v) return Stakes.fairFoul(s, v) end
  eq(f{ verdict = "ok" }, nil); eq(f{ verdict = "unseen" }, "unseen")
  eq(f{ verdict = "bad", why = "announce", dealer = "Петър Колев" }, nil)
  eq(f{ verdict = "bad", why = "play", dealer = "Мария Стоянова" }, "deal")
  eq(f{ verdict = "bad", why = "noreveal", dealer = "Петър Колев" }, "deal")
  eq(f{ verdict = "bad", why = "noreveal", dealer = "Мария Стоянова" }, "unseen")
  s.fairVoids = { ["Петър Колев"] = 1 }
  eq(f{ verdict = "void", dealer = "Петър Колев" }, "unseen")
  eq(f{ verdict = "bad", why = "nodeal", dealer = "Петър Колев" }, "unseen")
  s.fairVoids = { ["Петър Колев"] = 1 }; s.fairLapses = { ["Петър Колев"] = 1 }
  eq(f{ verdict = "void", dealer = "Петър Колев" }, "deal")
  s.fairVoids = { ["Мария Стоянова"] = 3 }
  eq(f{ verdict = "void", dealer = "Мария Стоянова" }, nil); eq(f{ verdict = "void", dealer = "Иван Петров" }, nil)
end)
```
(`fakeSession` is a local of the test: a table with `client = {env = {me = ...}}`, `mySeat`, `seats`, `game`, and `engine` returning `ns.Games.engine(game)`.)

Simulator tests:
- `a hand that closed bad on my client contests the match`: Сантасе; in hand 2 the host deals from seeds of its own (`mine` on the guest); the match is played out and the guest loses (choose the seeds so; else assert the branch) → the guest's `N` with `why == "deal"`, no `C`; the debt is `contested` on a third guild member.
- `a bad hand is sticky through a resync`: after that hand the guest asks for a snapshot (`session:requestSync()`); foul stays `deal` (rank 3 over `unseen`).
- `the loser waits for the last hand's reveal, then confirms`: a clean match; a bus filter holds the dealer's reveal of the last hand for 10 s; at +5 s the loser's note has `wait == true`, `foul == "unseen"`, and no `C` or `N` was authored although the claim is there; at +11 s one `C`.
- `the last hand is never revealed: the loser waits, then contests` (Review Focus 3, G12): the loser is the host and the winner a guest, the dealer of the last hand; its reveal is dropped as the guest dealer's `ACT` to the host (dropping a host-relayed `EV` instead makes a gap and an asked snapshot, `unseen` by `Member.lua`, not a missing reveal); no word of the loser before `FAIR_WAIT`; after the host's `noreveal` event the hand is `bad` and the result is `N` `deal` (not left to `STAKE_FAIR_WAIT`).
- `a silent dealer that is the host: the debt is asked at STAKE_FAIR_WAIT` (G12): the winner is the host and the dealer of the last hand and goes silent, so no `noreveal` is ever ordered; the loser's note keeps `wait` until `STAKE_FAIR_WAIT`, then the hand reads `unseen` → the debt is in its `asks()`, no `N`.
- `my own partner's missing reveal is a question, not a contest`: Белот; the last hand's dealer is the loser's partner and its reveal is dropped → the loser's debt is in its `asks()`; no `N`.
- `a note still waiting at a logout stays unseen`: the loser `sim:relog`s inside the wait → its note has `foul == "unseen"`, `wait == nil`; the claim is asked.
- `an opponent's void: once is a question, twice a contest`: Сантасе; the opponent dealer `sim:crash`es mid-hand once (void) → at the end the loser's debt is asked; with a second crash of the same dealer in the same match → `N` `deal`. `my own void costs me nothing`: the loser itself crashed once as dealer: its debt is asked because of the login (`unseen`), and the **other** player's client holds no foul from that void.
- `a forged announce does not contest`: Белот; the scenario of `tests/core/belot_table_test.lua` `a forged announce scores nothing…`; the losers' clients confirm.
- `a leave waits for no verdict`: Сантасе; the guest stands mid-hand → its `C` comes within 3 s; no note has `wait`.
- `a verdict that the next start brings does not touch the new match`: the last hand is left unrevealed, the host starts the next match at the break → the old match's note becomes final (`deal` for the loser when the dealer was the winner), and `session.stakeFoul` of the new match is nil on both.
- `Death Roll's pending roll verdict behaves as before`: `tests/core/stakes_ledger_test.lua` unedited and green (the generic `Book:pending` replaced its code).

- [ ] **Step 2: Run** `bash t.sh tests/core/stakes_cards_test.lua tests/core/ledger_test.lua` → fails.
- [ ] **Step 3: Implement** as the Interfaces block says. `Stakes.new` gains `client:on("fair", function(v) Stakes.fairHeard(client, v) end)`.
- [ ] **Step 4: Run** `bash t.sh` → green; `wc -l core/Stakes.lua core/StakesBook.lua core/StakesClaims.lua` under their caps.
- [ ] **Step 5: Commit** `feat(stakes): a bad hand contests the match, an unseen one or a void asks; the last hand's verdict is waited for`.

### Task 5: Табла for gold: the forged-move check and the dice

**Files:**
- Create: `tests/core/stakes_tabla_test.lua`
- Modify: `core/Dice.lua` (`unheard` returns whether it counted against the host; `close`; the reset at `start`, lines 236–237), `core/DiceMember.lua` (the `hostChanged` count, line 184), `core/DiceCheck.lua` (the kept-field list, lines 90–91, and the counts a bad start keeps, lines 118–120), `core/StakesFair.lua` (`Stakes.fairCount`, the four wrapped hooks)

**Interfaces:**
- Consumes: `Play`; `Stakes.pend`; `s.diceSeen`, `s.diceAway`; F1's `Member.timedOut` and the forged-move check (they need no edit: `engine.view or (s.stake and not engine.idle)` is already true for a staked Табла).
- Produces:
  - `s.diceRobbed` (number | nil), per match: +1 in `close` when the verdict is `"alone"`, `s.mySeat == throw.alone`, `throw.asked or throw.sent`, and `unheard(s)` counted it against the host (not `away`); +1 in `core/DiceMember.lua`'s `hostChanged` when the dropped running throw has `t.sent` and `unheard(s, true)` counted it against the host. Reset, kept across `END` and kept at a bad start exactly where `s.diceUnheard` is.
  - `Stakes.fairCount(s)`: for an engine with `"dice"` only, and only while `s.stakeLive` (a foul left pending between two matches would land on the next one): `Stakes.pend(s, "dice")` when `s.diceSeen.bad > 0` or `(s.diceRobbed or 0) > 0`; else `Stakes.pend(s, "unseen")` when `(s.diceSeen.unseen or 0) > 0` or `(s.diceAway or 0) > 0`.
  - `core/StakesFair.lua` wraps `ns.Ext.stakes.applied`, `.adopted`, `.hostChanged` and `.refused`: `Stakes.fairCount(s)` runs **before** the original (the extension `dice` has run already; the original's `refresh` turns the pending foul into the game's, after its reset when the event begins a new game, and before `Book:settle` writes the note).

- [ ] **Step 1: Write the failing tests** (Табла staked through `Play.staked`; `mute`, `grind` and `evs` are locals of `tests/core/tabla_table_test.lua`: copy them into this test file and leave that one unedited; G10)

- `a clean staked tabla match: the loser confirms by itself`: `Play.short("tabla")`, `Play.finish`; one debt, `confirmed`; both clients `stakeFoul == nil` throughout.
- `the host moves for my seat: contested as forged (D1)`: on the guest's turn the host calls `session:play(2, auto)` at once → guest `forged`; at the end `N` `forged`.
- `the host's timeout for my seat is taken only after my own clock ran out`: turn 45 s; the host's automatic move at `45 + AUTO_GRACE` is clean on the guest; the same event sent at 10 s is `forged`.
- `a throw made alone against my commit contests the match from the first one (D3)` (Review Focus 5): the guest's seed message is dropped (`mute(B, "seed")`); after `DICE_WAIT` the host throws alone → guest `session.diceRobbed == 1`, `stakeFoul == "dice"`; the guest loses → `N` with `why == "dice"`.
- `a throw made alone while my client said nothing is no foul`: the guest is `sim:offline` for the whole throw and back before `OFFLINE_STAND_SECONDS`: the resync makes the match `unseen` (asked), `diceRobbed` stays nil.
- `my own loading screen: the match is put to me, not contested (D6)`: `sim:loading(B, true)` (the flag only: the events still reach the guest) and the guest's seed message dropped; the host throws alone → `diceAway == 1`, `diceRobbed == nil`, foul `unseen`; a second alone throw under the same screen → `diceRobbed == 1`, foul `dice`. A throw that only a resync shows me (the messages were lost with the screen) is never counted in `diceRobbed`: the asked snapshot makes the match `unseen`.
- `a host that reloads over my seed re-rolls: contested (D2)`: the guest's seed has left (`throw.sent`), the host `sim:relog`s before its seeds event; after `SILENT_AFTER` the guest hosts and throws under a new number → guest `diceRobbed == 1`, foul `dice`; the old host, back by a snapshot, is `unseen`. With only the guest's **commit** sent when the host vanished: `diceRobbed == nil` (the opener knew nothing).
- `a seat-0 dice event is contested`: the host plays `{k = "dice", d = {6, 6}}` → guest `dice`.
- `a host that throws again over my seed (dodge) is contested`: the scenario of `a host that throws again over a seed it was sent…` at a staked table → `dice`.
- `after my /reload a valid alone proof is taken, and my debt is a question (D5)`: the guest `sim:crash`es mid-match; the host throws alone meanwhile; the guest's foul is `unseen`, never `dice`.
- `the counts are the match's`: `diceRobbed` is nil after the next start; a `start` while the match runs keeps it (and is `forged`).
- `a fun tabla table runs no stakes code`: every hook of `ns.Ext.stakes` is wrapped with a counter for the test; a fun match with one alone throw against the guest's commit calls none of them; `Dice.status(s)` and `Dice.tip(s)` on the guest are what `88a48e7` gives for that script (`s.diceRobbed` is counted there too and shown nowhere).

- [ ] **Step 2: Run** `bash t.sh tests/core/stakes_tabla_test.lua` → fails (`diceRobbed` is nil; the foul is nil).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bash t.sh` → green (`tests/core/tabla_table_test.lua` and `tests/core/dice_review_test.lua` unedited).
- [ ] **Step 5: Commit** `feat(stakes): a staked Табла: forged moves, alone throws and re-rolls contest the match`.

### Task 6: Residual 24: an own id far above my counter is asked, not denied

**Files:**
- Modify: `core/LedgerNet.lua` (`Net:own`, `Net:answer`), `core/LedgerStore.lua` (`Store:bump`)
- Test: `tests/core/ledger_net_test.lua`

**Interfaces:**
- Produces: `Store:bump(n, force) -> bool`: with `force` the counter goes to at least `n` whatever the distance. `Net:own`: outside the adoption window a body new to me under my name that is too far (`not near`), that I did not hold (`not held`) and whose number is above my saved seq is **asked** (`self:ask(b)`), not denied; inside the window a far one is asked as well (the denial "once the window has closed" goes). `held` and `n <= self.saved` still deny. `Net:answer(which, true)` calls `L:bump(n, true)` for each kept body of mine.

- [ ] **Step 1: Write the failing tests** (`tests/core/ledger_net_test.lua`)
- `a second computer far behind asks about its own real entries (residual 24)`: Иван's store with saved seq 5; a relayed `P` under `"Иван Петров:1500"` arrives → no `X` is made, the body has `un == true`, `L:record().seq == 5` (the counter did not move), `net:asks()` lists it, and it counts for nothing in `View.of(L)`.
- `„Мои са“ for a far entry moves the counter above it`: `net:answer(body, true)` → `un == nil`, the next `net:make` has number 1501.
- `„Не са мои“ for a far entry denies it and leaves the counter`: `net:answer(body, false)` → one `X`, and that `X` has number 6.
- `a far id in the adoption window is asked too`: a new store; `"Иван Петров:5000"` arrives → asked; after the window closes no `X` exists.
- Four existing tests of `tests/core/ledger_net_test.lua` pin the old rule and are edited, each only where it speaks of the far id: `a clean author denies what it never wrote` (lines 225–227: the id 5000 is now asked, no second `X`, so the saved seq stays 4 and the numbers after it are one lower), `a far id refused in a new store's window is denied by the next session` (renamed `…is asked, in that session and the next`: no `X` after `sim:settle()`, the body in `asks()`), `a forged body with my queued row's content…` (line 469: the far body is asked, not queued for denial; the fresh id of my `P` is one lower) and the final review's I6 test at lines 505–520 (three asked bodies, `View.paid` is 0 before and after the window, no `X`). The part of each about an id at or below my saved seq, and `tests/core/ledger_test.lua` (`Store:bump` without `force`), stay as they are.

- [ ] **Step 2: Run** `bash t.sh tests/core/ledger_net_test.lua` → the four fail (an `X` is made).
- [ ] **Step 3: Implement.** In `Net:own` the branch `elseif not near or held or n <= self.saved then self:deny(b)` becomes `elseif held or n <= self.saved then self:deny(b)`, and the adoption branch becomes `self:ask(b)`; the header comment lines 19 and 24 are corrected in place.
- [ ] **Step 4: Run** `bash t.sh` → green; `core/LedgerNet.lua` < 240.
- [ ] **Step 5: Commit** `fix(ledger): an own id far above my counter is put to me, never denied unasked (residual 24)`.

### Task 7: Residual 25: the author's sorted list is kept and built in slices

**Files:**
- Modify: `core/LedgerHash.lua` (`Store:items`, `Store:work`, `Store:stale`), and wherever a body leaves or enters an author's set (`core/LedgerStore.lua` `Store:index` / `Store:move`, `core/LedgerRefused.lua`'s remember and forget) only through the one call `self:stale(a, item, gone)`
- Test: `tests/core/ledger_final_test.lua`

**Interfaces:**
- Produces:
  - `L.il[a]`: author `a`'s byte-sorted `"<id>:<h>"` items (memory only, never saved), present once a hash job of `a` has finished.
  - `Store:stale(a, item, gone)`: as today, and when `L.il[a]` exists and `item` is given, the item is inserted at (or, with `gone`, removed from) its place found by binary search with `byteLess`; without `item` the list is dropped (rebuilt by the next job).
  - `Store:work(n)`: a job of an author without `L.il[a]` first collects its unsorted items in one call that walks `pairs(store.ev[a])` and `store.tw[a]` itself (not `Store:items`, whose `Store:above` sorts every number of the author in one frame, a sort `L.sorted` does not count; ruling G16), then sorts them in runs of at most `n` items a call (`L.sorted` counts the items handed to `table.sort`), then feeds the hash from a merge of the runs' heads, at most `n` items a call, building `L.il[a]` as it goes. A job of an author with `L.il[a]` feeds from the list at once. The `x` is byte-for-byte the one of `88a48e7`.

- [ ] **Step 1: Write the failing tests** (`tests/core/ledger_final_test.lua`, beside `a 5000-body author is hashed LEDGER_HASH_ITEMS a frame…`)
- `the sort of a 5000-body author is sliced as well (residual 25)`: a store with 5 000 `R` of one author, loaded; repeat `L:work(C.LEDGER_HASH_ITEMS)` until it returns true: the collecting call does not grow `L.sorted` at all, and between any two later calls `L.sorted` grew by at most `LEDGER_HASH_ITEMS` and `L.hashed` by at most `LEDGER_HASH_ITEMS`; the final `L:vector()[author].x` equals the `x` of a second store that hashed the same bodies in one go (`L:work()`).
- `one more body of that author sorts nothing`: after the above, add one `R`; until fresh again `L.sorted` does not grow, and `x` equals the one-go `x` of the 5 001 bodies.
- `a dropped twin and a forgotten refusal leave the list right`: add a twin, deny it so it is dropped, forget a remembered refusal: `x` equals the one-go `x` each time.
- `runs merge in byte order, not number order`: an author with ids 2, 10, 100 (their items sort as `…:10:`, `…:100:`, `…:2:`) and `n = 1`: the `x` equals the one-go `x`.

- [ ] **Step 2: Run** `bash t.sh tests/core/ledger_final_test.lua` → fails (`L.sorted` is nil).
- [ ] **Step 3: Implement.** The merge keeps one index per run and picks the least head by `byteLess` (17 runs for 5 000 items: a linear scan is enough).
- [ ] **Step 4: Run** `bash t.sh` → green; `core/LedgerHash.lua` < 160 (else the list code moves to `core/LedgerSort.lua`, < 120, with its TOC line and cap).
- [ ] **Step 5: Commit** `perf(ledger): an author's sorted list is kept and first built in slices (residual 25)`.

### Task 8: Residuals 26 and 27: the mail guard

**Files:**
- Modify: `core/Const.lua` (`PAY_GUARD_MAIL`), `core/PayGuard.lua` (`Pay:guard`), `wow/Mail.lua` (`sent`, `clicked`, `left`, `hook`, the clears), `tests/helpers/wow.lua` (the fake `SendMailMailButton` with `HookScript`, `SendMailSendMoneyButton:GetChecked()` and a `Click()` that models both orders (the default sends first, then runs the hooked scripts; `clickOrder = "hooks first"` runs them before the fake `SendMail`)), `ui/Accounts.lua` (the tooltip key by `g.how`), `locale/bg.lua`, `locale/en.lua`
- Test: `tests/core/pay_test.lua`, `tests/wow/mail_test.lua`, `tests/ui/accounts_test.lua`

**Interfaces:**
- Produces:
  - `Pay:guard(name)`: a guard with `how == "mail"` is live for `C.PAY_GUARD_MAIL`, one with `"trade"` for `C.PAY_GUARD`; everything else as today.
  - `wow/Mail.lua`: `clicked()`, hooked to the game's send button (`SendMailMailButton:HookScript("OnClick", clicked)`, looked up at call time under `pcall`, once). It notes only a letter that sends money (ruling G17):

    ```lua
    local clickedNote -- {to, c}: what the game's „Send“ saw at the click, until the game answers

    local function clicked()
      local check, box = lookup("SendMailSendMoneyButton"), lookup("SendMailNameEditBox")
      local okCheck, on = call(check, "GetChecked")
      if not (okCheck and on) then clickedNote = nil; return end -- a COD letter (money not checked) sets no guard
      local okTo, to = call(box, "GetText")
      local okMoney, c = false, nil
      local money, copper, frame = fn("GetSendMailMoney"), fn("MoneyInputFrame_GetCopper"), lookup("SendMailMoney")
      if money then okMoney, c = pcall(money)
      elseif copper and frame then okMoney, c = pcall(copper, frame) end
      clickedNote = okTo and type(to) == "string" and to ~= "" and okMoney and plain(c) and c > 0 and { to = to, c = c } or nil
    end
    ```
    (`call` returns `pcall`'s first result only; where it must return the value as well, the implementer extends it in place.) `clickedNote` is cleared at `MAIL_FAILED`, at `MAIL_CLOSED`, at each `Mail.fill`, and after one `MAIL_SEND_SUCCESS` (`left()` uses it once). `left()` reports the letter the `SendMail` hook saw, else `clickedNote`; **with neither it reports nothing** (the letter the addon filled is no longer taken on trust).
  - Locale: `accounts.sent.tip.mail` „Писмото вече е тръгнало. Ако парите са взети, помоли за „Уредено“. „Плати“ се връща след 30 дни без запис.“; `accounts.sent.tip` (unchanged) stays for a trade.

- [ ] **Step 1: Write the failing tests**
- `tests/core/pay_test.lua`: `a letter guards its debt for thirty days, a trade for one (residual 26)`: `pay:sent{name, c, how = "mail"}`; at `+86 401` s `pay:waiting(name)` is still true and `pay:left(name) == 0`; at `+2 592 001` s it is false and the whole net is offered again; the same with `how = "trade"` is false at `+86 401` s.
- `tests/wow/mail_test.lua`:
  - `without hooksecurefunc the click on Send tells what left (residual 27)`: a fake with `noHooks`; the addon fills a letter to Мария for 5g; the player changes the recipient box to „Петър“ and the money to 2g and clicks the send button; `MAIL_SEND_SUCCESS` → `client.pay:sent` was called once with `shown == "Петър"`, `c == 20000`.
  - `with neither hook nothing is guarded`: a fake with `noHooks` and no `SendMailMailButton`; a filled letter, `MAIL_SEND_SUCCESS` → `client.pay:sent` was not called.
  - `the SendMail hook still wins`: with `hooksecurefunc` the recipient and money of the `SendMail` call are reported, whatever the boxes say.
  - `the addon still never calls SendMail` (the fake's `forbidden` set; the hook is a post-hook of the player's click).
  - `a COD letter sets no guard` (G17): the player checks COD (money not checked) and clicks; `MAIL_SEND_SUCCESS` → `client.pay:sent` was not called.
  - `a failed or cancelled send leaves no note` (G17): a click, then `MAIL_FAILED` (or `MAIL_CLOSED`), then a `MAIL_SEND_SUCCESS` of a letter that had no click → not guarded; one `MAIL_SEND_SUCCESS` uses a note once (the next success without a click reports nothing); a `Mail.fill` clears the note.
  - the three click tests above run under both click orders of the fake (`clickOrder` default and `"hooks first"`), and the money is read once through `GetSendMailMoney` and once through `MoneyInputFrame_GetCopper(SendMailMoney)`.
- `tests/ui/accounts_test.lua`: `the row of a letter on its way explains the thirty days`: the tooltip of a row guarded by a letter is `accounts.sent.tip.mail`; by a trade `accounts.sent.tip`.

- [ ] **Step 2: Run** `bash t.sh tests/core/pay_test.lua tests/wow/mail_test.lua tests/ui/accounts_test.lua` → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `fix(pay): a letter guards its debt for 30 days; only a letter the game was seen sending sets the guard (residuals 26, 27)`.

### Task 9: UI: the staked table of the three games

**Files:**
- Modify: `ui/StakePanels.lua` (`askText`, the warning line, `rematchState`, the bill's leave line and its guest line), `ui/TablePanels.lua` (`forfeitCost`, the confirm text), `ui/TableFrame.lua` (the waiting line while the host holds a start; the `renderStart` edit `ns.Stakes.gap(s)` was made in Task 2, G8), `ui/games/SantaseView.lua`, `ui/games/BelotView.lua`, `ui/games/TablaView.lua` (the match-end line hides under the bill), `locale/bg.lua`, `locale/en.lua`
- Test: `tests/ui/stake_test.lua`, `tests/ui/santase_test.lua`, `tests/ui/belot_test.lua`, `tests/ui/tabla_test.lua`, `tests/ui/table_test.lua`

**Interfaces:**
- Consumes: `Stake.worst`, `Stakes.owed`, `Stakes.gap`, `E.teams`, `E.partner`, `P.notes`, `P.billRows` (F1), `Play.staked(ns, ...)` (Task 1).
- Produces (strings; Bulgarian exact):

  | key | text |
  |---|---|
  | `stake.ask.team` | „Залогът е %s. Ако отборът ти загуби, плащаш %s на един от противниците. Ако напуснеш играта, плащаш по %s и на двамата, общо %s. Партньорът ти не дължи нищо.“ |
  | `stake.ask.cards` | „Аддонът на раздаващия знае тестето на ръката, която раздава. Играй карти за голд с хора, на които вярваш.“ |
  | `stand.stake.team` | „Ако станеш сега, отборът ти губи. Дължиш по %s на двамата противници, общо %s. Партньорът ти не дължи нищо.“ |
  | `bill.left.team` | „%s напусна играта и плаща на двамата противници. Партньорът му не дължи нищо.“ |
  | `bill.again.wait` | „Домакинът може да започне нова игра за същия залог след %d сек. Не искаш ли, натисни „Към залата“.“ |
  | `bill.again.ready` | „Домакинът може да започне нова игра за същия залог. Не искаш ли, натисни „Към залата“.“ |
  | `table.holdStart` | „Новата игра започва след %d сек.“ |

- [ ] **Step 1: Write the failing tests** (the frames fake of `tests/helpers/frames.lua`, as `tests/ui/stake_test.lua` does; each test applies `Play.staked(w.ns, ...)` right after `Wow.new` through a local `stakedWow()` helper, with no file-level restore: the namespace of a `Wow.new` is its own and dies with the test; G6)
- `the question at a Белот chair names both prices`: `StakePanels.ask` for a Белот record at 1g → the text is `stake.ask.team` with `1g`, `1g`, `1g`, `2g`; for Сантасе and Табла it is F1's `stake.ask.text`.
- `a card table warns about the dealer`: for Сантасе and Белот the line `stake.ask.cards` is shown under the leave line and the frame is 44 px taller; for Табла, Морски шах and Death Roll it is hidden and the frame has F1's height. The same for the invitation's question and the asked seat's.
- `„Стани“ in a staked Белот match names what I owe`: the confirm panel's text is `stand.stake.team` with `1g`, `2g`; in Сантасе F1's `stand.stake` with `1g`.
- `the bill of a Белот match shows two rows`: after a match played out, `P.bill` has the title and exactly two `bill.row` lines, each with its mark as the ledger has it; `the bill of a leave names the leaver and its two debts` (`bill.left.team`, two rows; the partner's client: `P.shown == false` and the view's own end line is shown).
- `a guest's bill says when the next match may begin`: Сантасе guest, 5 s after the end: the line is `bill.again.wait` with 25; after the break `bill.again.ready`; the host has „Реванш на същата маса“, which calls `TableFrame.startGame()`; inside the break the start button is enabled and dim (F1's `"break"` behaviour) and is redrawn when `Stakes.gap(s)` is over.
- `the views hide their end line under the bill`: for each of the three views, with `ns.StakePanels.shown = true` the match-end text is hidden; with false it is shown as at `88a48e7`.
- `a full table that waits for the break says so`: the host's status line is `table.holdStart` with the seconds left while `s.holdTimer` is armed.
- `bg and en have the same keys and placeholders` (the existing parity test covers the new keys; run it).

- [ ] **Step 2: Run** `bash t.sh tests/ui` → the new tests fail.
- [ ] **Step 3: Implement.** `askText(game, sk)`: an engine with `teams` → `stake.ask.team`; Death Roll as today; else `stake.ask.text`. The warning line is a third label of the question frame, shown for an engine with `view`. `forfeitCost(s)` = `s.stake * #ns.Stakes.owed(s, roster, s.mySeat)`. `rematchState` returns `"wait", seconds` or `"ready"` for a seated guest of an engine with `again` while the game is over and the table live. The bill keeps its place (the bottom strip of the felt); what it covers in the three views is row 6 of the check list (Task 11).
- [ ] **Step 4: Run** `bash t.sh` → green; `ui/TableFrame.lua` < 600.
- [ ] **Step 5: Commit** `feat(ui): the staked table of Сантасе, Белот and Табла: the question, the leave, the bill, the break`.

### Task 10: The switch, and the whole road

**Files:**
- Modify: `engines/santase.lua`, `engines/belot.lua`, `engines/tabla.lua` (`stakes = true` in the engine table), `tests/core/stake_test.lua` (line 126: the games that are not ready are `{ "holdem" }`; lines 130–134 and 416 use `holdem` where they need a game without stakes; a `fakeTBL(..., "holdem", ...)` there takes six seats, `{ P, false, false, false, false, false }`, because Lobby refuses a TBL whose seat count is not `maxSeats` (`Lobby.lua:40`); G18), the F2 test files (their `Play.staked(...)` line goes and the closing `restore()` becomes `Play.restore()`; the UI tests' `stakedWow()` helpers and calls go), `tests/helpers/play.lua` (`Play.staked` goes; `Play.short` and `Play.restore` stay)
- Create: `tests/core/stakes_f2_flow_test.lua`

**Interfaces:**
- Consumes: everything above. Produces: `engine.stakes == true` for the three games; nothing else.

- [ ] **Step 1: Write the failing tests** (`tests/core/stakes_f2_flow_test.lua`, the real wire as `tests/core/stakes_ledger_test.lua` installs it; guild members А, Б, В, Г and a bystander Д)
- `the dialog's games`: `ns.Stake.allowed(id, 50000)` is true for `ttt`, `deathroll`, `santase`, `belot`, `tabla` and false for `holdem`; a staked `TBL` of each of the five is listed by a guild member's lobby.
- `from the chair to the cleared debt, three times`: for each of the three games: opened for 2g 50s, everyone accepts and sits, the match is played out, the debtors' clients confirm, Д shows the right nets (`25000` per pair; Белот: two pairs), one debtor pays by trade (`PAY`, the fake trade completes) → the creditor's `P`; every online client shows that pair cleared.
- `a guest is disconnected mid-match and comes back in time`: Сантасе; `sim:offline(Б)` for 60 s, `sim:online(Б)`; the match is played out; Б's debt (if Б lost) is asked, А's (if А lost) confirmed; no forfeit was written.
- `a guest is disconnected for good`: Табла; `sim:offline(Б)`; after 180 s (+ the sweep) the forfeit `why == "offline"`, `pending`; Б logs in a day later (`sim:run(86400)`, `sim:relog`) → asked once, with the game and the amount.
- `the host is disconnected for good mid-match`: Белот; the host goes offline; a member takes the table, stands the old host up after 180 s: the old host owes both opponents, its partner nothing; the successor wrote the `R`.
- `a reload at every seat of a Белот match`: each of the four players `sim:relog`s once in a different deal; the match ends; every debt is `pending` (asked), none `contested`, none `confirmed` by itself.
- `a forged ledger entry about a card match is denied by its author`: a relayed `C` under a loser's name for a `D` it never confirmed → that loser's client authors `X`; the debt is not `confirmed` anywhere after the sync.
- `a client of the F1 version keeps the debt pending and the sync settles`: one bystander's `ledgerNet.take` is wrapped for the test so that an `N` whose `why` is `deal` or `dice` goes to `net:refuse(e, author, n)` (what F1's `Ledger.valid` does with a reason it does not know); after a contested match it holds the `D`, not the `N`, shows the debt `pending` and in no balance, and two exchanges with a new client later nothing more is sent between them (the refused set).
- `the budget of a staked card match`: the GUILD messages of one finished staked Белот match in the whole guild ≤ 7 (`R`, two `D`, two `C`, two spare), no client above 3; of a Сантасе or Табла match ≤ 4.
- `a fun-only evening of the three games is byte-identical`: for each of the three games a fun match script (the first whole-match test of `tests/core/santase_table_test.lua`, `belot_table_test.lua`, `tabla_table_test.lua`, replayed here with fixed randoms) gives a message log equal to the reference log of `88a48e7` (a literal in the test, generated once from the `88a48e7` build by the implementer with `git stash`/`git worktree` and committed with the test; `HI.ld` and `LEV` are already in that reference).

- [ ] **Step 2: Run** `bash t.sh tests/core/stakes_f2_flow_test.lua` → fails (`openTable` answers `"stake"`).
- [ ] **Step 3: Implement** the three flags and the test edits.
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `feat: Сантасе, Белот and Табла take a stake`.

### Task 11: The rules book, Addendum 9, the documents, the check list

**Files:**
- Modify: `core/Help.lua` (topic `stakes` gains four blocks; the comment of line 107), `locale/bg.lua`, `locale/en.lua`, `tests/core/locale_help_test.lua` (the pinned `help.soon.*` lines and the quoted-label check), `docs/superpowers/notes/engine-contract.md` (Addendum 9), `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` (a section „Stage F2 additions“ after „Stage F1 additions“: the wire table of this plan's Global Constraints, the new session fields and constants), `docs/superpowers/notes/2026-11-21-rulings.md` (a section "Stage F2": the three tables of "Residual rulings" with the test that pins each, and every "Decision:" of this plan with its cost; in "Accepted residuals" the Stage D items are marked ruled, with a pointer), `docs/superpowers/plans/2026-11-23-stakes-roadmap.md` (the F2 table's "Expected ruling" column gets the ruling as built; nothing else)
- Create: `docs/superpowers/notes/2026-11-stageF2-ingame-checks.md`

**Help texts** (tavern talk, short sentences, every quoted label a real UI label; Bulgarian exact for the pinned ones):
- `help.stakes.cards`: on a staked card table my addon checks every hand; a hand that is „нередовна“ on my addon means it contests the debt by itself; one it did not see whole (a reload, a new host) means it asks me. Pinned: „Ако една ръка излезе „нередовна“ при теб, аддонът ти оспорва дълга сам.“
- `help.stakes.belot` (example block, pinned verbatim): „Иван и Мария играят Белот срещу Петър и Гошо за 1g. Иван и Мария губят. Иван плаща 1g на Петър, а Мария плаща 1g на Гошо. Ако Мария напусне по средата, тя плаща по 1g на Петър и на Гошо, а Иван не дължи нищо.“
- `help.stakes.tabla`: the dice need both numbers; if the host throws without mine although my addon sent it, or reloads after it saw mine, my addon contests the debt; a slow connection at a throw can do the same, and then the two of us settle it by word. Pinned: „Ако домакинът хвърли без твоето число, аддонът ти оспорва дълга сам.“
- `help.stakes.again`: after a match the host may start the next one for the same stake after 30 seconds; whoever does not want it presses „Към залата“ before that; staying seated means playing. Pinned: „Останеш ли на масата, играеш и следващата игра за същия залог.“
- `help.stakes.p1` names the five games; `help.soon.p` „Залози има на Морски шах, Death Roll, Сантасе, Белот и Табла. Тексас Холдем за злато идва скоро.“; `help.soon.example` „Искаш да играеш Холдем за злато? Още не може. Засега Тексас Холдем е само за удоволствие.“; `help.fair.dealer` gains one sentence: „На маса със залог това важи с пълна сила: играй карти за голд с хора, на които вярваш.“; `help.fair.dice`'s last sentence becomes „На маса със залог аддонът на госта тогава оспорва дълга сам.“; `help.ledger.pay.mail` says 30 days where it said 24 hours.
- `help.stakes.leave` (existing key, `locale/bg.lua:103`) gains „освен на партньора си в Белот“ after „Дължиш залога на всеки, който е още в играта“ (ruling G19; the key is covered by the locale parity test).

**Addendum 9** (the style of Addendum 8) states: the files; `E.partner`; `Stakes.owed` and `Stakes.matched` and the rule "one outcome per game" with whose `R` it is and that the event, not `r.left`, decides it (`quits`); the break and the hook `hold` (and that `Session:startIfFull` asks it, the one new line of `core/Session.lua`); the fouls `deal` and `dice` and their rank; the two tables (hand → foul, throws → foul) and that `fairHeard` reads `s.stakeLive`; `Stakes.audit`, `Book:pending`, `STAKE_FAIR_WAIT`; `s.diceRobbed` and where it is counted, reset and kept (amending Addendum 6's field list); the snapshot rule for a judged game (amending Addendum 8's "A snapshot is my game"); `db.stakeLog` without a state for a view engine; residuals 24–27 as built (amending Addendum 8's residuals 4, 24 and the payment paragraph); the three tables of "Residual rulings", S1 first and in bold, with S8–S11 (G2, G14) after S7; the `stakeLeft` claim of a partnered engine (the wait for the one `R` naming me, `N "no"` for a creditor I do not owe); under residuals 2 and 24 of Addendum 8 the two widenings of ruling G15 (a forged `C` at a far id under a debtor's name, which F1 denied automatically, now counts on every other client until „Не са мои“; near asked entries move the counter to `base + LEDGER_JUMP`, so in residual 2's own scenario the next own id can land on one of my far real ids, a twin, until the answer); the forward-compatibility note on the two `N` reasons.

**The check list** `docs/superpowers/notes/2026-11-stageF2-ingame-checks.md`, in the format of the F1 list, every row `not yet measured`:

| # | Check | What to look for |
|---|---|---|
| 1 | two characters, staked Сантасе, a whole match | both see the same bill within about 20 s of the last card (the reveal); the loser's row turns from „чака потвърждение“ to plain without a question |
| 2 | four characters, staked Белот, a whole match | two rows in the bill, the same on all four; a fifth character sees two debts in „Тефтер“ |
| 3 | staked Белот, one player presses „Стани“ mid-deal | the warning names both opponents and the total; the bill names the leaver and two rows; the partner sees no bill and owes nothing |
| 4 | staked Белот, one player alt-F4s for more than three minutes | stood up; two debts „чака потвърждение“; at its login one question per debt |
| 5 | the acceptance question for Сантасе, Белот, Табла at the default and a low UI scale | nothing clipped; the card warning reads naturally |
| 6 | the bill at the end of a staked match of each of the three games | what it covers: the last trick, the Белот summary, the Табла bar and dice; whether the end line under it is missed |
| 7 | staked Сантасе, the dealer `/reload`s mid-hand | the hand goes on; at the end the dealer is asked about its debt, the other is not |
| 8 | staked Сантасе, the dealer alt-F4s mid-hand and logs in again | „Ръката е анулирана от …“; at the end the other player, if it lost, gets a question |
| 9 | staked Табла, a whole match | no question, the debt confirmed; the dice line stays green |
| 10 | staked Табла, the guest enters and leaves a loading screen (a hearthstone, an instance portal) during a throw | the dice line is amber; at the end the guest is asked, not contested |
| 11 | staked Табла, the guest's connection is cut for 15 s at a throw (pull the cable) | the host throws alone; the guest's row reads „оспорен“ if it loses; how often this happens on a normal evening |
| 12 | staked Табла, the host `/reload`s right after the guest's dice animation starts | the guest hosts after about 75 s; if the guest loses, „оспорен“ |
| 13 | the host presses „Нова игра“ at once after a staked match | the button is dim, says why, and lights up after 30 s; the guests' bill counts down |
| 14 | after a leave at a staked Белот table a fifth player sits within 10 s | „Новата игра започва след N сек.“; the match starts by itself at 30 s |
| 15 | a staked Табла turn left untouched | the host plays the timeout 7 s after the clock; the idle player's row is not „оспорен“ |
| 16 | a letter sent with the game's „Send“ after changing the amount by hand | the row says the amount actually sent; `/console taintLog 1` names no blocked action; a COD letter sets no guard |
| 17 | a letter left in the box for more than a day | „Плати“ stays off; the tooltip says 30 days |
| 18 | log in with a ledger of one author with thousands of entries (F1 row 31 again) | no hitch above a frame or two at login and when a game ends |
| 19 | the rules book in both languages: „Залози“ | the four new blocks fit; the example reads right |
| 20 | over a normal evening of staked card games, count the no-deals, voids and contested matches | S9–S11: how often an honest dealer's disconnect, a fourth player's silence in a Белот shuffle, or a loser's trip to the hall before the last reveal costs a contest or a question |

- [ ] **Step 1: Write the failing tests** (`tests/core/locale_help_test.lua`): the four new keys exist in both languages; the three pinned sentences and the Белот example are in `locale/bg.lua` verbatim; `help.soon.p` and `help.soon.example` are the new texts; every quoted label in the new blocks („Към залата“, „нередовна“, „Уредено“) is the text of a UI key; `help.stakes.leave` holds „освен на партньора си в Белот“; no help text still says that Сантасе, Белот or Табла are only for fun (`help.soon.*`, `help.stakes.*`).
- [ ] **Step 2: Run** `bash t.sh tests/core/locale_help_test.lua` → fails.
- [ ] **Step 3: Implement** the help content, then write the documents and the check list.
- [ ] **Step 4: Run** `bash t.sh` → all green; note the final test count in the commit message.
- [ ] **Step 5: Commit** `docs: the rules book on card and dice stakes; Addendum 9; the F2 protocol notes, rulings and check list`.

---

## After the last task

Run the whole-branch review against the Review Focus list and the three tables of "Residual rulings" (each row must name a green test or say "no code"), then put **S1** (the dealer's client knows its deck) before the user: it is the one residual this plan accepts against the letter of the one rule. Then the in-game check list (`docs/superpowers/notes/2026-11-stageF2-ingame-checks.md`), rows 11 and 12 first: they measure the price of D2 and D3 on a real connection, and if an honest evening produces contested debts, `DICE_WAIT` at a staked table is the number to revisit. F3's plan is written after those results are in.
