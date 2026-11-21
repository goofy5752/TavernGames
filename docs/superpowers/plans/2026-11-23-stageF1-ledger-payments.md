# Tavern Games Stage F1 (тефтер, плащане, залози за Морски шах и Death Roll) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A guild member opens a Морски шах or Death Roll table „Със залог“ for an amount in gold and silver; whoever sits accepts the stake explicitly; when the game ends (or somebody leaves) every client writes who owes whom into a guild-wide append-only ledger that syncs between clients, the debtor's client confirms what it saw itself, and the debt is paid by trade or by mail with the amount filled in by the addon and cleared when the creditor's client sees the gold arrive.

**Architecture:** The ledger is a per-guild set of small signed-by-sender entries (`core/Ledger.lua`), from which debts and balances are derived and never stored (`core/LedgerView.lua`). Entries are broadcast live on GUILD by their author and healed between clients by a whispered anti-entropy exchange driven by a digest in `HI` (`core/LedgerNet.lua`, `core/LedgerSync.lua`). An always-on session extension (`core/Stakes.lua`) turns a result or a forfeit into entries and decides, from what my own client saw, whether my debt is confirmed, contested or put to me. Payment is a pure core module (`core/Pay.lua`) fed by two thin WoW bindings (`wow/Trade.lua`, `wow/Mail.lua`) that only fill the game's own frames and report what the trade and mail events show.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), the stage 1 Ace3 subset (AceComm, ChatThrottleLib, AceSerializer, LibDeflate, AceDB), `core/Sha256.lua`, `bash t.sh`, `tests/helpers/sim.lua`, `tests/helpers/wow.lua`.

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.2 „Сметки“, 5.3а, 5.4, 5.6 „Тефтер“ and identity, 6.2, 6.4, 6.5, 6.6; anti-goals of section 2). Roadmap: `docs/superpowers/plans/2026-11-23-stakes-roadmap.md` (F1, its residual table and the spec rulings 1–5, 8, 9). Shared contracts and the message table: `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md`. Engine contract: `docs/superpowers/notes/engine-contract.md` (Task 14 adds Addendum 8). Rulings log: `docs/superpowers/notes/2026-11-21-rulings.md`. Look: `docs/mockups/04-payment-flow.html`, `docs/mockups/06-leaderboard-ledger.html` (the right half, „Тефтерът“), `docs/mockups/02-hub.html` (the column „Сметки“).

**Stage F1 starts on `feature/games` at `97ee876` (993 tests).** Names are binding; line numbers are from that commit and may move.

## Global Constraints

Everything in the stage 1 and A–E constraint files still holds. Added for F1:

- **Fun tables are untouched.** A table without a stake behaves exactly as at `82b0140`: no new event, no new message, no changed timing. The only wire change a fun-only guild sees is the field `HI.ld`, the live `LEV` of a `RESULT` (one GUILD message per finished game from its host), and the whispered sync of those entries. Every existing test stays as it is, except where a task names the test it edits.
- **Money is integer copper.** A stake is an integer, a multiple of 100 (gold and silver only), from `STAKE_MIN = 100` (1s) to `STAKE_MAX = 99999990000`; no other cap (spec: „без таван“). Shown with `Util.money`.
- **The addon never moves gold.** It never calls `AcceptTrade`, `SendMail`, `TakeInboxMoney`, `AutoLootMailItem` or any COD function. It may call `InitiateTrade` from a click, set the money of an open trade, and fill the send-mail fields. `tests/wow` fails if a forbidden function is called.
- **Protocol stays `v=1`**, prefix `TAVG`, GUILD + WHISPER only. Additions (complete list):

  | where | addition | meaning |
  |---|---|---|
  | `TBL`, `SNP.tbl` | `sk` | stake in copper; absent = for fun |
  | `SIT` | `sk` | the stake the sitter accepted; absent at a fun table |
  | `INV` | `sk` | the stake of the table the invitation is for |
  | `SNO.why` | `"stake"` | the `sk` of the `SIT` is not the table's |
  | `HI` | `ld` | 8 hex: digest of my ledger; absent on a client without a guild ledger (a bot) |
  | `EV` seat 0 | `{k="stand", seat, why="idle"}` | staked Death Roll: 180 s on turn without a roll |
  | new `LEV` | G: `ev` (1–4 entries, ≤ 760 packed bytes, **all authored by the sender**); W: `ev` (1–`LEDGER_BATCH` entries, ≤ 1 140 packed bytes, any author, but an entry of another author than the sender is taken only inside an open exchange with the sender), `f = true` on the last batch of an answer | ledger entries |
  | new `LVC` | W: `a = {[author] = {n, x}}`, `r = true` when it answers one; a vector over 1 500 bytes goes in pages of ≤ 1 500 bytes | my per-author vector |
  | new `LID` | W: `au`, `l = {"<seq>.<h6>", ...}`, `r`; paged at ≤ 1 500 bytes | the entries I hold of one author above the common `n`, plus the ids I hold twins for |
  | new `PAY` | W: `c` (copper), `how` = `"trade"`, `"mail"` or `"nudge"` | payer → creditor: "I am paying you `c` now"; creditor → debtor with `"nudge"`: a reminder |

  `LEV`, `LVC`, `LID`, `PAY` carry no `tid`; `core/Session.lua` ignores them already (it returns on a message without a string `tid`).
- **Ledger entry** (the wire form is the stored form minus the local fields `h`, `rl`, `dr`). `i` = `"<author>:<n>"`, `n` an integer from 1; the author is the text before the **last** colon. `at` = `env.epoch()` of the author.

  | `k` | fields | who may author it |
  |---|---|---|
  | `R` result | `gid, g, n` (names by seat, `false` = empty), `w`, `l` (seat lists), `sk` (absent = fun), `why` (absent, or the forfeit reason) | anyone (the table's host) |
  | `D` debt | `gid, g, f` (debtor), `t` (creditor), `c` (a valid stake), `why` = `"lost"`, `"left"`, `"offline"` or `"idle"` | `f` or `t`; `f ~= t` |
  | `C` confirm | `r` (id of a `D`) | counts only when the author is that `D`'s `f` |
  | `N` contest | `r` (id of a `D`), `why` = `"forged"`, `"roll"`, `"stand"`, `"amount"` or `"no"` | counts only when the author is that `D`'s `f` |
  | `P` paid | `f` (debtor), `c` (any integer from 1 to 99 999 999 999: a payment is not a stake), `how` = `"trade"`, `"mail"` or `"hand"` | the creditor (the author **is** the creditor) |
  | `X` deny | `r` (an id), `h` (8 hex, the hash of the denied entry) | the author named in `r` |

  `gid` = `"<tid>/<q>"`, `q` the number of the table event that ended the game or stood the leaver up. A name is at most 64 bytes; a canonical entry at most 600 bytes; `at` at most `LEDGER_FUTURE = 3600` s ahead of my clock. Anything else is dropped without an error.
- **Hash and canonical form.** `Ledger.canon(e)` = the fields in this fixed order joined by `|`, an absent field as the empty string, `false` as `-`, a list joined by `,`: `i, k, at, gid, g, f, t, c, why, r, h, how, sk, n, w, l` (the `h` here is `X`'s field, never the local hash). `Ledger.hash(e)` = the first 8 hex characters of SHA-256 of that string.
- **Derived, never stored.** Debts, balances, the column „Сметки“ and the tab „Тефтер“ are computed from the entries. The only other saved state is my own outcome notes and the stake I sat down for (`env.db.stakeSeen`, `env.db.stakeLeft`, `env.db.stakeSat`), which are never sent.
- **A logical debt** is the key `gid | f | t`. Its `D` entries that are not denied are its claims. It is `confirmed` when a claim is authored by `f`, or `f` authored a `C` for one of its claims; `contested` when `f`'s newest entry about it (by `n`; its own `D` counts as a confirmation) is an `N`; else `pending`. Its amount is the amount `f` attested (its own `D`, or the claim its `C` names), else the smallest claim; `clash = true` when a creditor's claim names another amount than `f` attested. Only confirmed debts enter a balance.
- **Balances.** `gross(f, t) = max(0, Σ confirmed debts f→t − Σ c of t's P entries with that f)`; `net(a, b) = gross(a, b) − gross(b, a)` (positive: `a` owes `b`). „Плати“ and „Уредено“ always work on the net of a pair: debts to one person are one transfer (spec 5.4, economy holds).
- **Denials.** An entry whose id names me as author and that my own log does not hold is answered with one `X` (never while the adoption window of a new store is open, and never for an unsaved entry of a crash, which is asked about, below). Denials go out batched (at most 4 per `LEV`), at most `LEDGER_DENY_RATE = 8` per minute, the rest queued. A denied entry and every `C`/`N`/`P` it is counts for nothing on every client; it stays in the log and the tab shows it as „отречено“; a client that got it **directly from its author** (`dr`) shows „отречено от автора си“ instead.
- **Twins.** Different entries under one id are all kept, up to 4 per id, and every non-denied body counts; they sync by `LID`. When over 4, a client drops a body denied by its author first, then the one with the highest `h`, so all clients converge once the `X` has spread. My counter always jumps above every id seen under my name, denied or not. An honest client makes a twin only after losing its saved variables.
- **Adoption window and the crash question.** WoW writes saved variables only at logout, so no session flag survives a crash. A client whose ledger store holds no record `store.me[name]` (a new install or lost files) does not deny unknown entries under its own name: it adopts them and moves its counter above them until its first sync exchange ends or `LEDGER_ADOPT_WAIT = 30` s after start, whichever comes first. On every other login an unknown entry under my id with `n ≤` my saved `seq`, or a different body under an id I hold, is forged and I deny it at once. An unknown own entry with `n >` my saved `seq` (a crash) is neither adopted silently nor denied: my counter jumps above it at once, it counts for nothing on my own client, and one question among the questions of „Сметки“ lists them (`ask.mine`: „Мои са“ keeps them, „Не са мои“ denies them). On every login the entries I want to author myself are queued for `LEDGER_ADOPT_WAIT` s, so my next id is above whatever the guild holds. Accepted residual: a forger who catches the window of a new store can plant entries under my name.
- **Sync budget (binding; pinned by tests in Task 6 and Task 14 with the real wire format, never above these caps).**
  - One packed entry of kind `D`, `C`, `N`, `P` or `X` is at most 190 bytes (a `D` between two 2 × 12-letter Cyrillic names, 49 bytes each); an `R` may be larger (a five-seat Death Roll `R` is about 420–440 bytes). A live GUILD `LEV` carries at most 4 entries and 760 packed bytes; a whispered `LEV` at most `LEDGER_BATCH` entries and 1 140 packed bytes.
  - The GUILD caps count `LEV` and sync `HI` only, in 255-byte parts as Forever's throttle counts them (10 in reserve, 1 a second): no client sends more than 10 such parts within any 10 s. `net:make` coalesces my entries made within `LEDGER_COALESCE = 2` s into one `LEV` of at most 4.
  - A finished two-player staked game costs at most 4 GUILD messages in the whole guild (`R`, `D`, `C`, and one spare for a fallback); a five-player Death Roll at most 10 (1 + 4 + 4 batched into 1, plus spares), and no client sends more than 3 of them. A fun game costs 1.
  - `HI` grows by at most 16 packed bytes.
  - Sync by whisper only. One exchange at a time as initiator and one as responder per client. A responder sends at most `LEDGER_BATCH = 6` entries per `LEV`, one `LEV` per `LEDGER_SEND_GAP = 2` s (`LEDGER_SEND_GAP_BUSY = 6` s while I sit at a live table): at most 570 bytes a second, below ChatThrottleLib's 800, at priority `BULK` so that table traffic (`ALERT`/`NORMAL`) always goes first. The next whisper batch goes only after the previous one has left (the optional `env.send` done-callback, which AceComm's `SendCommMessage` gives; the sim calls it at once).
  - An exchange starts only from the byte-lower name of a pair whose `HI.ld` differ, `LEDGER_JITTER_MIN = 5` + (byte sum of `me .. peer .. ld`) % 16 s after the difference is seen (derived, never `env.random`, so the ledger's timers consume no game randomness; `LEDGER_JITTER_MAX = 20` is the top of that range) and only if it still stands; no exchange starts or continues while `env.status().instance`; not again with the same peer for `LEDGER_PEER_GAP = 300` s; it is given up `LEDGER_SYNC_TIMEOUT = 30` s after the partner's last message. After an exchange that changed my digest I send one GUILD `HI`, at most one per `LEDGER_HI_GAP = 30` s.
  - A vector is sent in pages of at most 1 500 bytes (6 addon messages), all inside the one exchange, at most once per exchange per side; a vector of 60 authors with 25-byte names is one page.
  - One exchange sends and takes at most `LEDGER_EXCHANGE_MAX = 300` entries (the next exchange continues). `LID` lists only the entries above the common `n` plus the ids I hold twins for.
  - An entry is taken only when its author, and every name in `f`/`t`/`n`, is a guild member (the optional `env.member(name)`; absent, as in the sim, means all) or already has entries in my store.
  - No entry is ever deleted in F1 (retention is F4). Hard caps: `LEDGER_AUTHOR_MAX = 5000` `R` entries per author (past it an `R` is dropped; `C`, `N`, `P`, `X` and `D` are never dropped), `LEDGER_CLAIMS_OPEN = 20` pending claims per creditor shown or asked about; beyond that cap an entry is stored but not acted on.
- **Stake-aware play (the F1 games).**
  - Only `ttt` and `deathroll` take a stake (`stakes = true` in their engines); `Session.open` refuses `stake` for any other game, and the dialog offers „Със залог“ for those two only. A client without `client.ledger` cannot open or sit at a staked table.
  - Морски шах: the forged-move check of the card games runs on a staked Морски шах table (`engine.view or (s.stake and not engine.idle)`; Death Roll rolls are judged by `Rolls.audit` alone), the host plays another seat's timeout `AUTO_GRACE = 7` s after the deadline and a member accepts it only when its own clock ran out (`Member.timedOut`).
  - Death Roll: the engine of a staked game accepts only `src = "seen"` and has no automatic roll; the host cannot start it while a seated player is not in its group (`canStart` → `"group"`); a seat on turn for `OFFLINE_STAND_SECONDS = 180` s without a roll is stood up with `why = "idle"` (the idle timer fires only while `s.role == "host"` and is re-armed in `hostChanged`). At a staked table `canStart` answers `"break"` until `STAKE_BREAK = 10` s after the last game ended, by the host's clock; a member whose clock says the new game began earlier notes `forged` for that game.
  - Leaving: „Стани“ in a live staked game forfeits at once, after the warning; offline forfeits when the host stands the seat up after 180 s, as today. A forfeit is owed to every other player still in that game. The host's own idle forfeit is recorded as `"left"` (its own client wrote `stakeLeft` through `Client:stand`).
  - Bots never sit at a staked table: they decline (`INR auto "busy"`) any invitation with `sk`, `Bots:fill` does nothing there, and no ledger entry is authored for a table `Bots:tableKind` calls a bot table (the client asks the optional `env.noLedger(tid)` that `Bots.enable` installs).
- **Fouls** my client notes against the running game of a staked table (the first of the higher rank wins; reset when a new game begins; a foul raised by the event that starts a game is set after the reset, so it counts against the new game): `forged` (an event for my seat I did not send and that is no due timeout; an `auto` event for my seat while an ACT I sent before my own deadline is still unmatched in `s.sent`; an event of my host my engine refused; a pushed snapshot that contradicts the game I hold, or whose `staked` flag differs from my accepted stake; a game that began earlier than my own clock says it could) > `roll` (Death Roll: a recorded roll I saw with another number, a roll for my seat that I did not make, or an `idle` stand of my seat after my client saw its own roll on that turn at the current max) > `stand` (my seat stood up while my client ran and I did not ask, unless `idle` and my own clock agrees) > `unseen` (a snapshot I asked for or logged in with brought me into the game; a snapshot from a changed host that is a prefix of my game: same board cells or same first rolls; a recorded roll I never saw).
- **What my client does with a claim against me** (`D` with `f` = me, authored by `t`): my note for that `gid` has the pair and the amount and no foul → `C`; a foul `forged`, `roll` or `stand` → `N` with that reason; another amount → `N` `"amount"`; I pressed „Стани“ myself at that table (`stakeLeft`, the claim's `why = "left"`, the amount is the table's stake, within `STAKE_LEFT_WINDOW = 600` s, once per creditor) → `C`; anything else (no note: I was offline; foul `unseen`) → it is put to me („Потвърждавам“ / „Оспорвам“). If I noted a clean loss and no claim arrives within `STAKE_OWE_WAIT = 60` s, my client authors the `D` itself.
- **Payment detection.** A `P` is authored only by the creditor's client: automatically after a completed trade in which no item changed hands and the payer's `PAY` came within `PAY_WINDOW = 300` s; automatically when money is taken from a letter whose subject starts with `Tavern Games:` and whose sender matches exactly one of my debtors; in every other case in which gold came from a debtor it is put to me. The amount is `min(received, net(payer, me))`; nothing is recorded when the net is not positive. „Уредено“ authors a `P` `"hand"` for the whole net.
- **Files.** `core/Session.lua` stays below 540 lines: Task 2 first moves `Session:invitedList` and `Session:addInvited` to `core/Invites.lua`, then adds four lines; every other edit to it is inside an existing line.
- **Existing tests.** A test that compares a whole `HI`, or counts every GUILD message after a game with a result, now sees `ld` and the host's `LEV`; the task that causes it (5, 6 or 8) updates exactly those assertions and lists them in its report. No other existing assertion changes.
- **The budget numbers are caps, measured at each pinning test's first green run.** If a measurement exceeds a cap, lower `LEDGER_BATCH` (or the entries per live `LEV`) until it holds; never raise a cap. New caps in `tests/toc_test.lua`: `core/Ledger.lua` < 300, `core/LedgerView.lua` < 260, `core/LedgerNet.lua` < 240, `core/LedgerSync.lua` < 300, `core/Stakes.lua` < 340, `core/Pay.lua` < 240. If Task 8 would cross 340 in `core/Stakes.lua`, it moves the money half (notes, claims, `asks`/`answer`, `review`) to a new `core/StakesBook.lua` (< 260, TOC right after `core/Stakes.lua`); a cap is never raised. The existing caps stay.
- **Locale.** Every new string in `locale/bg.lua` and `locale/en.lua` with the same keys and placeholders; Bulgarian in „…“ quotes inside texts. The exact Bulgarian of each label is in the task that adds it; the English is the implementer's translation.
- Commits are local only, never pushed; every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A crash between a payment and the next logout.** The creditor's client records the `P`, crashes, and comes back without it in its saved variables (WoW writes them only at logout, so no session flag survives a crash). Expected: after a crash my unsaved `P` is asked about, not denied, and keeping it clears the debt; a clean author still denies what it never wrote. Pinned by Task 5 (`a crashed author is asked about its unsaved entries, not denied`, `a clean author denies what it never wrote`) and Task 12 (`the own-entries question`).
2. **A trade that is not a payment.** A debtor buys an item from the creditor, or gives gold for another reason. Expected: nothing is recorded without a question. Pinned by Task 9 (`a trade with an item is put to me, never recorded`, `gold without a PAY is put to me`, `more gold than owed records only the debt`).
3. **A namesake.** Two guild members share a first name; the trade partner, the mail sender and the roll line may show only the first name. Expected: never a payment or a roll credited to the wrong person. Pinned by Task 9 (`a letter from a first name that fits two debtors is put to me with both`), Task 10 (`the trade partner is resolved by GUID, not by the shown name`), Task 7 (`a namesake's roll under my seat is the foul roll`).
4. **A stake changed under a seated player.** A host announces 1g, the player accepts, the host's next snapshot says 100g. Expected: the player's client stands up and no debt above what it accepted is ever confirmed by it. Pinned by Task 2 (`a snapshot with another stake than I accepted stands me up`) and Task 8 (`a claim for more than the table's stake is contested as amount`).
5. **A loser who logs out the second the game ends.** Expected: the claim waits as „чака потвърждение“ and is confirmed by the loser's client at its next login without a question, because its note of the game was written before the logout. Pinned by Task 8 (`the loser's note survives a relog and confirms the late claim`).

Also pinned: forged entries of every kind (Tasks 3, 5), twins and holes (Task 6), a responder that vanishes mid-sync (Task 6), a forfeit by „Стани“, by offline and by idleness (Tasks 7, 8), a host that stands an online player up (Task 8), mutual debts and partial payment (Task 4), the mail fee and a closed mailbox (Tasks 10, 12).

## File Structure

| File | Responsibility |
|---|---|
| `core/Stake.lua` (new) | The stake amount: validity, g/s parts, a player's worst case |
| `core/Ledger.lua` (new) | Entries: canonical form, hash, validation, the per-guild store, my counter, vector and digest |
| `core/LedgerView.lua` (new) | Pure derivation: logical debts, status, gross and net, rows, totals |
| `core/LedgerNet.lua` (new) | Live `LEV`, direct against relayed, `DENY`, the adoption window, the author queue |
| `core/LedgerSync.lua` (new) | The whispered exchange (`LVC`, `LEV`, `LID`), its timers and budget |
| `core/Stakes.lua` (new) | Extension `stakes` (always on at a staked table): roster, fouls, forfeits, idle stands, outcome notes, claims and their answers |
| `core/StakesBook.lua` (new, only if Task 8 would cross the cap of `Stakes.lua`) | The money half of `stakes`: notes, claims, `asks`/`answer`, `review` |
| `core/Pay.lua` (new) | Intents (`PAY`), what a finished trade or a taken letter means, „Уредено“, „Напомни“ |
| `wow/Trade.lua`, `wow/Mail.lua` (new) | Game events and frames ↔ `env.trade`, `env.mail`, `client.pay` |
| `ui/StakePanels.lua` (new) | The acceptance question at a chair, the bill „Сметката“ |
| `ui/Accounts.lua` (new) | The hall column „Сметки“ with its questions |
| `ui/PayDialog.lua` (new) | „Плащане“: Трейд / Поща |
| `ui/LedgerTab.lua` (new) | The tab „Тефтер“ |
| modified | `core/Const.lua`, `core/Session.lua`, `core/Lifecycle.lua`, `core/Member.lua`, `core/Lobby.lua`, `core/Invites.lua`, `core/Presence.lua`, `core/Rolls.lua`, `core/Client.lua`, `core/Bots.lua`, `core/Help.lua`, `engines/tictactoe.lua`, `engines/deathroll.lua`, `wow/Adapter.lua`, `wow/Rolls.lua`, `wow/Slash.lua`, `ui/NewTableDialog.lua`, `ui/Hall.lua`, `ui/HallPeers.lua`, `ui/InviteToast.lua`, `ui/TableFrame.lua`, `ui/TablePanels.lua`, `ui/games/TicTacToeView.lua`, `ui/games/DeathRollView.lua`, `locale/*.lua`, `TavernGames.toc`, `tests/helpers/sim.lua`, `tests/helpers/wow.lua`, `tests/toc_test.lua` |

TOC order of the new core files: `core/Stake.lua` after `core/Games.lua`; `core/Ledger.lua`, `core/LedgerView.lua`, `core/LedgerNet.lua`, `core/LedgerSync.lua`, `core/Pay.lua`, `core/Stakes.lua` (and `core/StakesBook.lua` right after it, if it exists) after `core/Invites.lua` and before `core/Client.lua`. `wow/Trade.lua`, `wow/Mail.lua` after `wow/Adapter.lua`. UI: `ui/StakePanels.lua` after `ui/TablePanels.lua`; `ui/Accounts.lua` before `ui/HallPeers.lua`; `ui/PayDialog.lua` after `ui/NewTableDialog.lua`; `ui/LedgerTab.lua` after `ui/Hall.lua` (so the tab order is Зала, Тефтер, Настройки).

**New `env` fields** (all optional; a client without `guild` runs no ledger net and sends no `HI.ld`):

| field | meaning |
|---|---|
| `guild` | the key of the ledger store: the guild's name and the realm, `guild .. "-" .. GetRealmName()` (local only, never sent). Read when the client is created; nil there means no ledger and a log line |
| `db.ledger` | `{[guild] = store}`, account-wide (AceDB `global`) |
| `db.stakeSeen`, `db.stakeLeft` | my outcome notes, per character |
| `db.stakeSat` | `{tid, sk}`: the stake of the table I last sat down at, per character |
| `member(name)` | true when the name is a guild member (the adapter's roster); absent = every name (the sim) |
| `date(t)` | `{d, m, day}` of epoch `t` (`day` = a local day number); the adapter fills it from WoW's `date("*t", t)`, the sim and the fallback use UTC arithmetic; core never calls `os.date` |
| `noLedger(tid)` | true for a table `Bots:tableKind` calls a bot table; installed by `Bots.enable` |
| `send` done-callback | `env.send(..., done)` calls `done` when the message has left (AceComm's callback); the sim calls it at once |
| `money()` | copper in my bags |
| `trade.state(name)` | `"ok"` (a unit of that player is in trade range), `"far"`, `"none"` (no unit: not targeted, not grouped) |
| `trade.open(name, copper)` | start a trade with that player and remember the amount to fill in when it opens → `true` or `nil` |
| `mail.state()` | `"open"` or `"closed"` |
| `mail.fill(name, subject, body, copper)` | fill the send-mail frame → `true` or `nil` |
| `mail.fee()` | copper the post takes for one letter (30 when the client cannot say) |

**Client events added:** `"ledger"()` (the log changed), `"forfeit"({tid, game, q, seat, name, to, why, sk, at})`, `"payAsk"()`, `"debtAsk"()` and `"mineAsk"()` (the lists `client.pay:asks()` / `client.stakes:asks()` / `client.ledgerNet:asks()` changed), `"nudge"(name, copper)`. `"result"` gains `q` (the event number that ended the game) and `sk`.

---

### Task 1: Probes of the trade and mail API, the saved-variable keys, the check list

**Files:**
- Modify: `wow/Slash.lua` (`PROBE_APIS`, new `Slash.probeTrade`, `Slash.probeMail`, the `probe` dispatcher), `wow/Adapter.lua:17-27` (`CHAR_KEYS`, `GLOBAL_KEYS`, `DEFAULTS`), `locale/bg.lua`, `locale/en.lua`, `tests/helpers/wow.lua`
- Create: `docs/superpowers/notes/2026-11-stageF1-ingame-checks.md`
- Test: `tests/wow/slash_test.lua`, `tests/wow/adapter_test.lua`

**Interfaces:**
- Produces: db keys `stakeSeen`, `stakeLeft`, `stakeSat` (char) and `ledger` (global) in `Adapter.CHAR_KEYS` / `Adapter.GLOBAL_KEYS` (exported and scanned by `tests/wow/adapter_test.lua` "lists every db key the code uses" since `97ee876`); `/tavern probe trade`, `/tavern probe mail`; the fake client's `self.forbidden` set and call log.

- [ ] **Step 1: Write the failing tests**

`tests/wow/adapter_test.lua` (the key scan "lists every db key the code uses" is already in HEAD and covers core, ui and wow, so it guards every later task):
- `the ledger is account-wide and the notes are per character`: `ns.db.ledger = {x = 1}` lands in `aceDB.global.ledger`; `ns.db.stakeSeen = {}`, `ns.db.stakeLeft = {}` and `ns.db.stakeSat = {}` in `aceDB.char`.

`tests/wow/slash_test.lua`:
- `probe lists the trade and mail API by presence only`: after `/tavern probe` the chat has one line per path of `PROBE_APIS`; the list contains exactly these new paths: `SetTradeMoney`, `GetPlayerTradeMoney`, `GetTargetTradeMoney`, `C_TradeInfo.GetTradeMoney`, `MoneyInputFrame_SetCopper`, `TradePlayerInputMoneyFrame`, `CheckInteractDistance`, `GetSendMailPrice`, `SendMailNameEditBox`, `SendMailSubjectEditBox`, `SendMailBodyEditBox`, `MailEditBox`, `SendMailMoney`, `MailFrameTab_OnClick`, `GetInboxNumItems`, `GetInboxHeaderInfo`, `C_Mail.GetInboxHeaderInfo`, `TakeInboxMoney`, `AutoLootMailItem`, `hooksecurefunc`, `GetGuildInfo`; none of `AcceptTrade`, `SendMail`, `TakeInboxMoney`, `AutoLootMailItem`, `InitiateTrade`, `SetTradeMoney`, `SetSendMailMoney` was called by `/tavern probe` (checked through the fake's call log; `InitiateTrade`, `SetTradeMoney` and `SetSendMailMoney` are not in the fake's `forbidden` set, because Task 10 must call them).
- `probe trade prints every trade event of the next trade`: `/tavern probe trade`, then fire `TRADE_SHOW`, `TRADE_MONEY_CHANGED`, `TRADE_ACCEPT_UPDATE(1, 1)`, `UI_INFO_MESSAGE(_, ERR_TRADE_COMPLETE)`, `TRADE_CLOSED` on the fake with `GetPlayerTradeMoney() = 0`, `GetTargetTradeMoney() = 50000`, `UnitName("NPC") = "Мария"`, `UnitGUID("NPC") = "Player-1-00000002"`: the chat has five lines, each naming its event; the `TRADE_ACCEPT_UPDATE` line contains `50000`, `Мария` and `Player-1-00000002`; after `TRADE_CLOSED` a further `TRADE_SHOW` prints nothing.
- `probe mail prints the inbox rows and the price`: with `mailOpen = true`, two inbox rows (`"Мария"`, `"Tavern Games: 5g"`, 50000) and (`"Auction House"`, `"x"`, 0), `GetSendMailPrice() = 30`: three lines (two rows with sender, subject, money; one with `30`); with the mailbox closed one line with the key `probe.mail.closed`.

- [ ] **Step 2: Run them, expect failures** — `bash t.sh tests/wow` → the four tests fail (one in `adapter_test.lua`, three in `slash_test.lua`).

- [ ] **Step 3: Implement**

`Adapter.CHAR_KEYS` gains `stakeSeen`, `stakeLeft`, `stakeSat`; `Adapter.GLOBAL_KEYS` gains `ledger` (and `DEFAULTS` if needed). The fake client gets `GetPlayerTradeMoney`, `GetTargetTradeMoney`, `UnitName`/`UnitGUID` for `"NPC"`, the inbox and send-mail functions, `ERR_TRADE_COMPLETE`, `ERR_TRADE_CANCELLED`, `hooksecurefunc`, a call log, and `self.forbidden` (a set of names; calling one fails the test) that holds only the Global "never" set: `AcceptTrade`, `SendMail`, `TakeInboxMoney` and `AutoLootMailItem` when called by addon code, `SetSendMailCOD` and any COD function. `Slash.probeTrade()` registers a frame for `TRADE_SHOW`, `TRADE_MONEY_CHANGED`, `TRADE_PLAYER_ITEM_CHANGED`, `TRADE_TARGET_ITEM_CHANGED`, `TRADE_ACCEPT_UPDATE`, `TRADE_REQUEST_CANCEL`, `TRADE_CLOSED`, `UI_INFO_MESSAGE`, `UI_ERROR_MESSAGE` (each under `pcall`), prints `probe.trade.event` with the event, its arguments, both money values and the partner's name and GUID, and unregisters at the first `TRADE_CLOSED` after a `TRADE_SHOW`. Strings: `probe.trade.armed` „Проба: направи един трейд с друг играч. Записвам всяко събитие.“, `probe.trade.event`, `probe.mail.row`, `probe.mail.price`, `probe.mail.closed` „Проба: отвори пощенска кутия и опитай пак.“.

- [ ] **Step 4: Write the check list** `docs/superpowers/notes/2026-11-stageF1-ingame-checks.md` in the format of `2026-11-stageA-ingame-checks.md` (every row `not yet measured`), with these rows now (later tasks append theirs):

| # | Check | What to look for |
|---|---|---|
| 1 | `/tavern probe` | which of `SetTradeMoney` / `C_TradeInfo.SetTradeMoney`, `GetPlayerTradeMoney` / `C_TradeInfo.GetTradeMoney`, `GetInboxHeaderInfo` / `C_Mail.GetInboxHeaderInfo`, `MoneyInputFrame_SetCopper`, `GetSendMailPrice`, `hooksecurefunc` are `function`; `GetGuildInfo` |
| 2 | `/tavern probe trade`, then trade 1s to a second character | the order of the events; whether `UI_INFO_MESSAGE` carries `ERR_TRADE_COMPLETE`; whether both money values are still readable at `TRADE_ACCEPT_UPDATE(1,1)` and at `TRADE_CLOSED`; the form of `UnitName("NPC")` (first name, full name, realm) and whether `UnitGUID("NPC")` is a roster GUID |
| 3 | the same, cancelled by the other side | which event tells a cancel from a completion |
| 4 | `/tavern probe mail` at a mailbox with a letter with money from a guild character | the sender's form in the inbox row; the price line; whether a money value is a plain number (`issecretvalue`) |
| 5 | send 1s by mail between two accounts | the delivery delay (one hour between accounts?); the fee actually taken |
| 6 | several small trades and letters in a row | does an economy hold appear; its message text |

- [ ] **Step 5: Run** `bash t.sh` → all green (993 + 4 = 997).
- [ ] **Step 6: Commit** `feat(wow): probes of the trade and mail API; the stake and ledger db keys are declared`.

### Task 2: The stake on the table

**Files:**
- Create: `core/Stake.lua`, `tests/core/stake_test.lua`
- Modify: `core/Const.lua`, `core/Session.lua` (`record`, `check`, `onRequest`, `open`, `request`, `receive`; the two moved functions), `core/Invites.lua` (the two moved functions; `INV.sk`; `Invites:answer` sits with the invitation's `sk`), `core/Lobby.lua` (`fromTBL`, `valid`), `core/Member.lua` (`adopt`), `core/Client.lua` (`sit`), `core/Bots.lua` (decline an invitation with `sk`; `fill` does nothing at a staked table), `engines/tictactoe.lua`, `engines/deathroll.lua` (`stakes = true`), `tests/helpers/sim.lua` (`db.stakeSat` kept across relogs), `TavernGames.toc`
- Test: `tests/core/stake_test.lua`, `tests/core/session_test.lua` (no edit expected; it must stay green)

**Interfaces:**
- Produces:
  - `ns.Stake.MIN = 100`, `ns.Stake.MAX = 99999990000`
  - `Stake.valid(c) -> bool`; `Stake.fromParts(gold, silver) -> copper | nil`; `Stake.worst(gameId, copper) -> copper` (Death Roll: `copper * (maxSeats - 1)`; otherwise `copper`)
  - `client:openTable{game, access, turn, opt, stake}` → `nil, "stake"` for an invalid stake or for a game whose engine has no `stakes = true` (only `ttt` and `deathroll` have it)
  - `client:sit(tid, seat, sk)`; `Session.request(client, kind, tid, seat, sk)` (a `SIT` writes `db.stakeSat = {tid = tid, sk = sk}`)
  - session field `s.stake` (copper or nil) on host and members; lobby record field `stake`; `Session:record().sk`
  - `SNO.why = "stake"`; the `"invite"` event's payload gains `stake`

- [ ] **Step 1: Write the failing tests** (`tests/core/stake_test.lua`, with `tests/helpers/sim.lua`)

```lua
it("valid: whole silver from 1s to the gold cap", function()
  eq(Stake.valid(100), true); eq(Stake.valid(50000), true); eq(Stake.valid(99999990000), true)
  eq(Stake.valid(99), false); eq(Stake.valid(150), false); eq(Stake.valid(0), false)
  eq(Stake.valid(-100), false); eq(Stake.valid(100.5), false); eq(Stake.valid("100"), false)
  eq(Stake.valid(99999990100), false); eq(Stake.valid(nil), false)
end)
it("fromParts", function()
  eq(Stake.fromParts(5, 0), 50000); eq(Stake.fromParts(0, 25), 2500); eq(Stake.fromParts(12, 50), 125000)
  eq(Stake.fromParts(0, 0), nil); eq(Stake.fromParts(1, 100), nil); eq(Stake.fromParts(-1, 0), nil); eq(Stake.fromParts(1.5, 0), nil)
end)
it("worst: Death Roll pays everyone else", function()
  eq(Stake.worst("deathroll", 10000), 40000); eq(Stake.worst("ttt", 10000), 10000)
end)
```
Simulator tests (Иван hosts, Мария and Петър are guild members):
- `a staked table announces sk and a fun table none`: Иван opens `ttt` with `stake = 50000`; the GUILD `TBL` has `sk == 50000`; Мария's `lobby:get(tid).stake == 50000`. A table opened without `stake`: the `TBL` has no `sk` key and equals, field for field, the `TBL` of the same call at `82b0140` (compare with a literal table).
- `openTable refuses a bad stake`: `stake = 150` → `nil, "stake"`; no `TBL` sent.
- `a stake is refused for a game that is not ready`: `openTable{game = "santase", stake = 50000}` (and `belot`, `tabla`, `holdem`) → `nil, "stake"`; a hand-made `TBL` for `santase` with `sk = 50000` from a guild member → `lobby:get` is nil.
- `a sit must carry the table's stake`: Мария `client:sit(tid, 2)` → her `"refused"` event is `(tid, "stake")`, seat 2 stays `false`; `client:sit(tid, 2, 10000)` → `"stake"`; `client:sit(tid, 2, 50000)` → seated, her `session.stake == 50000`.
- `a sit at a fun table with an sk is refused`: fun table, `client:sit(tid, 2, 100)` → `"stake"`.
- `a watcher needs no stake`: Петър `client:watch(tid)` → adopted, `session.stake == 50000`.
- `a TBL with a malformed sk is not listed`: a hand-made `TBL` with `sk = 150` from a guild member → `lobby:get` is nil.
- `the stake travels with the table to a new host`: Мария seated, Иван stands → Мария hosts; her `TBL` has `sk == 50000`.
- `a snapshot with another stake than I accepted stands me up` (Review Focus 4): Мария seated at 10000; a filter on the bus rewrites `SNP.tbl.sk` of Иван's next snapshot to 1000000; Мария's client sends `STD`, has no session, and emitted `"refused"(tid, "stake")`.
- `an invitation shows the stake and its yes sits with it`: Иван invites Мария at a staked `"invite"` table; her `"invite"` event carries `stake == 50000`; `answerInvite(tid, "yes")` → her `SIT` has `sk == 50000` and she is seated.
- `a relog into my staked seat keeps it` (F11): Мария seated at 50000, `sim:relog` → her adopted snapshot keeps her seat, `session.stake == 50000`, no `STD` sent; with her `db.stakeSat` note removed (a crash) the seat is also kept, `s.stake == t.sk`, and the foul is `unseen` once Task 7 exists (here only the seat and the stake are asserted); with a note of another `sk` she stands up and gets `"refused"(tid, "stake")`.
- `a bot never gets a seat at a staked table`: a bot client (`sim.makeEnv`) calls `client:sit(tid, 2)` → `SNO` `"stake"`.
- `a bot declines an invitation to a staked table` (the invitation path): Иван invites a bot at a staked table → the bot answers `INR auto "busy"` and is not seated; `Bots:fill` and the auto-fill add no bot to a staked table; an invitation to a fun table is accepted as today.
- `Session.lua keeps its limit`: `ok(lines("core/Session.lua") < 540)` (already in `tests/toc_test.lua`; run it).

- [ ] **Step 2: Run** `bash t.sh tests/core/stake_test.lua` → fails (`Stake` is nil).

- [ ] **Step 3: Implement**

1. Move `Session:invitedList` and `Session:addInvited` verbatim from `core/Session.lua` to the end of `core/Invites.lua` (they stay methods of `ns.Session`; they are called at run time only).
2. `core/Session.lua`: `record()` gets the line `sk = self.stake,`; `open` refuses `opts.stake ~= nil and not (ns.Stake.valid(opts.stake) and the game's engine has stakes = true)` with `"stake"` and sets `stake = opts.stake` in the session literal; `check(sender, kind, seat, sk)` returns `"stake"` for a `SIT` whose `sk ~= self.stake`, after the access check and before the seat check; `onRequest(sender, kind, seat, sk)` and the `SIT` branch of `receive` pass `m.sk`; `request(client, kind, tid, seat, sk)` puts `sk` into the `SIT` (inside its existing line) and, for a `SIT`, writes `db.stakeSat = {tid = tid, sk = sk}` (the key is declared in Task 1).
3. `Lobby.fromTBL`: `stake = m.sk`; `Lobby.valid`: `m.sk == nil or (ns.Stake.valid(m.sk) and the game's engine has stakes = true)`. `engines/tictactoe.lua` and `engines/deathroll.lua` get `stakes = true`; every other engine has none.
4. `Member.adopt`: `s.stake = t.sk`; before anything else is changed: when I hold a seat in `t.s` and my note `db.stakeSat` is for this `tid` and `.sk ~= t.sk` → send `STD`, `Session.leave(client)` if I had the session, emit `"refused"(m.tid, "stake")`, return. A fresh adopt into my seat compares `t.sk` with that note, so a `/reload` or a login back to my seat keeps it; with no note for this table (a crash) the seat is kept, `s.stake = t.sk` and the foul is `unseen` (Task 7), so the question shows the amount.
5. `Invites`: `INV` carries `sk = s.stake`; the invitation record and the `"invite"` event carry `stake`; `Invites:answer(tid, "yes")` calls `client:sit(tid, seat, inv.stake)`. `core/Bots.lua`: a bot declines (`INR auto "busy"`) any invitation with `sk`, and `Bots:fill` and the auto-fill do nothing at a staked table.

- [ ] **Step 4: Run** `bash t.sh` → green. `wc -l core/Session.lua` ≤ 526.
- [ ] **Step 5: Commit** `feat(core): a table may carry a stake; a sit accepts it or is refused`.

### Task 3: Ledger entries and the store

**Files:**
- Create: `core/Ledger.lua`, `tests/core/ledger_test.lua`
- Modify: `core/Const.lua` (the `LEDGER_*`, `STAKE_*`, `PAY_*`, `NUDGE_GAP`, `MAIL_FEE = 30` constants named in Global Constraints), `TavernGames.toc`, `tests/toc_test.lua` (cap `< 300`)

**Interfaces:**
- Consumes: `ns.Sha256`, `ns.Util`.
- Produces:
  - `Ledger.new(store, me, epoch) -> L` — `store` is a plain table the caller owns (`{}` when new; `L` fills `store.ev`, `store.tw`, `store.me`, `store.x`); `me` my name; `epoch` a function. `L.rev` counts changes.
  - `Ledger.id(author, n) -> string`; `Ledger.author(id) -> author, n | nil`
  - `Ledger.canon(e) -> string`; `Ledger.hash(e) -> string` (8 hex); `Ledger.wire(e) -> table` (a copy without `h`, `rl`, `dr`)
  - `Ledger.valid(e, now) -> true | nil, reason` — reasons `"shape"`, `"id"`, `"kind"`, `"amount"`, `"name"`, `"right"`, `"time"`, `"size"`
  - `L:add(e, from) -> "new" | "dup" | "twin" | nil, reason` — `from` = the sender's name, nil for my own; sets `h`, `dr = true` when `from == author`, `rl = true` when `from` is another name; reasons of `valid` plus `"full"` (the author cap, counted on `R` entries only) and `"twins"` (the body is the one dropped when an id holds more than 4)
  - `L:make(kind, fields) -> entry` — my next id, `at = epoch()`, added, counter saved in `store.me[me].seq`
  - `L:get(id) -> entry | nil, twins | nil` (`twins` = the further bodies of that id, a list); `L:has(id, h) -> bool`; `L:each(fn)` (every entry, twins included, authors in byte order, then `n`, then `h`)
  - `L:vector() -> {[author] = {n, x}}` (`n` = the highest `k` with every id `1..k` held; `x` = the sum mod 2^32 of the first 8 hex of each of that author's bodies' `h`, shown as 6 hex (the low 24 bits); it is incremental, kept in `store.x[author]` and updated on every add); `L:digest() -> string` (8 hex of SHA-256 over `"<author>:<x>"` sorted, joined by `,`, cached by `L.rev`; the empty log gives 8 hex of SHA-256 of `""`)
  - `L:above(author, n) -> {entries}` (every held entry of the author with a number above `n`, twins included, ascending); `L:list(author) -> {"<seq>.<h6>", ...}` (`h6` = the first 6 of `h`)
  - `L:denied(e) -> bool` (an `X` of `e`'s author names `e.i` and `e.h`)
  - `L:seen(author) -> n` (the highest number held for an author, holes included, denied or not); `L:bump(n)` (my counter is at least `n`; it is called for every id seen under my name, denied or not)

- [ ] **Step 1: Write the failing tests** (`tests/core/ledger_test.lua`)

```lua
local function L(me) return Ledger.new({}, me or "Иван Петров", function() return 1700000000 end) end
local D = { k = "D", gid = "Иван Петров#1700000000/12", g = "ttt", f = "Мария Колева", t = "Иван Петров", c = 50000, why = "lost" }

it("id and author split on the last colon", function()
  eq(Ledger.id("Иван Петров", 7), "Иван Петров:7")
  local a, n = Ledger.author("Иван Петров:7"); eq(a, "Иван Петров"); eq(n, 7)
  eq(Ledger.author("Иван"), nil); eq(Ledger.author("Иван:0"), nil); eq(Ledger.author("Иван:1.5"), nil); eq(Ledger.author(":3"), nil)
end)
it("canon is the fixed field order; hash is 8 hex and ignores local fields", function()
  local l = L(); local e = l:make("D", D)
  eq(Ledger.canon(e), "Иван Петров:1|D|1700000000|Иван Петров#1700000000/12|ttt|Мария Колева|Иван Петров|50000|lost|||||||")
  eq(#e.h, 8); ok(e.h:match("^%x+$"))
  local w = Ledger.wire(e); eq(w.h, nil); eq(Ledger.hash(w), e.h)
  w.c = 50100; ok(Ledger.hash(w) ~= e.h)
end)
it("make numbers my entries from 1 and saves the counter", function()
  local store = {}; local l = Ledger.new(store, "Иван Петров", function() return 5 end)
  eq(l:make("D", D).i, "Иван Петров:1"); eq(l:make("P", { f = "Мария Колева", c = 100, how = "hand" }).i, "Иван Петров:2")
  eq(store.me["Иван Петров"].seq, 2)
  eq(Ledger.new(store, "Иван Петров", function() return 6 end):make("P", { f = "Мария Колева", c = 100, how = "hand" }).i, "Иван Петров:3")
end)
```
`valid` (one `it` per row; each builds a full entry and changes one thing; `now = 1700000000`):

| change | result |
|---|---|
| a correct `R`, `D`, `C`, `N`, `P`, `X` | `true` |
| not a table; `i` missing; `k = "Z"` | `"shape"`, `"id"`, `"kind"` |
| `D` with `c = 150`, `c = 0`, `c = "5"`; `P` with `c = 0`; `P` with `c = 1.5` | `"amount"` |
| `P` with `c = 150` (copper is a payment, not a stake); `P` with `c = 99999999999` | `true` |
| `D` with `f == t`; `D` authored by a third name; `X` whose `r` names another author | `"right"` |
| `D` with `f` of 65 bytes; `R` with ten names | `"name"` |
| `D` with `f` of 49 bytes and of 64 bytes | `true` |
| `at = now + 3601`; `at = 1.5` | `"time"` |
| `D` with `why = "x"`; `P` with `how = "cod"`; `N` with `why = "because"` | `"shape"` |
| `R` with a `gid` of 600 bytes | `"size"` |
| a five-seat staked Death Roll `R` with 24-letter Cyrillic names (about 440 canonical bytes) | `true` |
| `C` whose `r` is not an id | `"shape"` |
| `P` with `f` equal to its author | `"right"` |

Store tests:
- `add: new, dup, twin, and no fifth`: add a relayed `D` → `"new"`; the same again → `"dup"`; the same id with `c = 60000` → `"twin"`, `l:get(id)` returns both; two more bodies → `"twin"` (four bodies kept); a fifth body with the highest `h` → `nil, "twins"`; a fifth with a lower `h` is kept and the highest-`h` body is dropped, so two ledgers that got the five bodies in different orders hold the same four; a body denied by its author is dropped before any other.
- `add marks direct and relayed`: `l:add(e, "Мария Колева")` for Мария's entry → `dr == true`, `rl == nil`; `l:add(e2, "Петър Иванов")` for Мария's entry → `rl == true`, `dr == nil`; a later direct copy of a relayed entry sets `dr` and clears `rl` and returns `"dup"`.
- `the author cap counts R only`: with `LEDGER_AUTHOR_MAX` patched to 3, the fourth `R` of one author → `nil, "full"`; a `D`, `C`, `N`, `P` and `X` of that author are still added.
- `x is incremental and bounded`: adding one entry to an author with 5 000 `R` hashes one body, not 5 001 (count the `Ledger.hash`/SHA calls); `digest()` called twice without a change hashes once (cached by `L.rev`).
- `my counter jumps above every id seen under my name`: a denied entry `"Иван Петров:9"` → `L:seen` is 9 and the next `make` is number 10.
- `vector: contiguous n and a set digest`: entries 1, 2, 3, 5 of Мария → `vector()["Мария Колева"].n == 3`; adding 4 → 5; `x` changes with every add and is equal on two ledgers that got the same entries in different orders.
- `digest: equal sets, equal digests; one more entry, another digest; an empty log has one`.
- `above and list`: `above("Мария Колева", 3)` returns 5 (then 4 and 5 after the add, ascending, a twin after its sibling); `list` has one `"<seq>.<h6>"` per entry, twins included.
- `denied`: an `X` by Мария naming her entry's `i` and `h` → `denied(e) == true`; an `X` with another `h` → false (the twin is not denied); an `X` authored by Петър naming Мария's entry is refused by `valid` (`"right"`).
- `the store round-trips`: `Ledger.new(copy(store), ...)` gives the same `digest()` and `vector()`.

- [ ] **Step 2: Run** `bash t.sh tests/core/ledger_test.lua` → fails.
- [ ] **Step 3: Implement** `core/Ledger.lua`. Store layout: `store.ev[author][n] = entry`, `store.tw[author][n] = {further bodies}` (up to 3), `store.me[name] = {seq, born}`, `store.x[author] = the running sum`. `x` is updated on add, never recomputed from the log; `h` is stored with the entry so a load hashes nothing.
- [ ] **Step 4: Run** `bash t.sh` → green.
- [ ] **Step 5: Commit** `feat(core): ledger entries, their validation and the per-guild store`.

### Task 4: Debts and balances

**Files:**
- Create: `core/LedgerView.lua`, `tests/core/ledger_view_test.lua`
- Modify: `TavernGames.toc`, `tests/toc_test.lua` (cap `< 260`)

**Interfaces:**
- Consumes: Task 3's `L:each`, `L:denied`, `L:get`, `L.rev`.
- Produces:
  - `View.of(L) -> view` (rebuilt only when `L.rev` changed)
  - `view.debts` — array, oldest first (by the claim's `at`, then key bytes), of `{key, gid, g, f, t, c, at, why, status, clash, ids = {claim ids}, said = id of f's C or N or own D}`; `status` is `"pending"`, `"confirmed"` or `"contested"`
  - `View.gross(view, f, t) -> copper`; `View.net(view, a, b) -> copper`
  - `View.accounts(view, me) -> {{name, net}}` (`net` > 0: I owe; pairs with net 0 left out; largest absolute first, then name bytes)
  - `View.claims(view, me) -> {debt, ...}` (pending debts with `f == me`, at most `LEDGER_CLAIMS_OPEN` per creditor, oldest first)
  - `View.rows(view) -> {{debt, open}}` (`open` = copper of that debt still unpaid after netting and first-in-first-out payment; pending and contested debts have `open = c`)
  - `View.totals(view) -> {open, count, top, topSum}` (sum and count of rows with `open > 0` among confirmed debts; the name with the largest sum of positive nets and that sum)
  - `View.paid(view, f, t) -> copper` (sum of non-denied `P`)
  - `View.denied(view) -> {entry, ...}` (denied entries, for Task 13), added only if `core/LedgerView.lua` stays below 260 lines; otherwise Task 13 reads denied and relayed entries itself through `L:each` + `L:denied`

- [ ] **Step 1: Write the failing tests** (names: И = „Иван Петров“, М = „Мария Колева“, П = „Петър Иванов“; `g1`, `g2` two gids)

| test | entries | assertions |
|---|---|---|
| `a claim alone is pending and in no balance` | И: `D` М→И 5g | one debt, `status == "pending"`, `net(М, И) == 0`, `claims(view, М)` has it |
| `the debtor's C confirms it` | + М: `C` of it | `"confirmed"`, `net(М, И) == 50000`, `accounts(view, М) == {{name = И, net = 50000}}`, `accounts(view, И) == {{name = М, net = -50000}}` |
| `a C by somebody else counts for nothing` | + П: `C` of it instead | `"pending"` |
| `the debtor's own D is a confirmed debt` | М: `D` М→И 5g | `"confirmed"` |
| `claim and own D of one game are one debt` | both | one debt, `c == 50000`, `#ids == 2` |
| `the debtor's amount wins; the clash shows` | И claims 5g, М: own `D` 1g | `c == 10000`, `clash == true`, `net == 10000` |
| `the newest word of the debtor decides` | `C` then `N` → | `"contested"`, `net == 0`; `N` then `C` → `"confirmed"` |
| `a denied claim is no debt` | И: `D`; И: `X` of it | `#view.debts == 0` |
| `a denied C un-confirms` | `D`, М: `C`, М: `X` of her `C` | `"pending"` |
| `a payment lowers the gross, never below zero` | confirmed 5g; И: `P` f=М 2g | `gross(М, И) == 30000`; a second `P` of 9g → `gross == 0`, `net == 0` |
| `a P counts only for its author as creditor` | П: `P` f=М 5g | `gross(М, И)` unchanged |
| `mutual debts are netted` | М→И 5g, И→М 3g, both confirmed | `net(М, И) == 20000`, `net(И, М) == -20000`; `accounts(view, И)` has `net == -20000` |
| `paying the net settles both` | + И: `P` f=М 2g | both nets 0; every row `open == 0` |
| `rows: first in, first out` | М→И 5g (older), М→И 3g; `P` 6g | row 1 `open == 0`, row 2 `open == 20000` |
| `totals` | М→И 5g, П→И 2g confirmed; М→П 1g pending | `open == 70000`, `count == 2`, `top == М`, `topSum == 50000` |
| `claims are capped per creditor` | 25 pending claims of И against М | `#claims(view, М) == 20` (the oldest) |
| `twins both count` | two confirmed `D` twins of different games under one id | two debts |
| `the view is rebuilt only on change` | `View.of(L) == View.of(L)` (same table); after `L:make` another table |

- [ ] **Step 2: Run** → fails. **Step 3: Implement** `core/LedgerView.lua` (one pass over `L:each`; no state outside the cached view). **Step 4:** `bash t.sh` → green. **Step 5: Commit** `feat(core): debts and balances derived from the ledger`.

### Task 5: Live entries, denial, the adoption window

**Files:**
- Create: `core/LedgerNet.lua`, `tests/core/ledger_net_test.lua`
- Modify: `core/Client.lua` (`Client.new` composes `self.ledger`, `self.ledgerNet` when `env.guild` and `env.db` exist; `receive` passes messages on; `start`/`stop` call `ledgerNet:start()`/`:stop()`; `openTable{stake}` and a staked `sit` return `nil, "stake"` locally when `client.ledger` is nil; no ledger and a log line when `env.guild` is nil at creation), `wow/Adapter.lua` (`env.guild` = `GetGuildInfo("player") .. "-" .. GetRealmName()`, read when the client is created; `env.member`; the store `ns.db.ledger`; `Adapter.priority(msg, channel)`, called from `rawSend`, which knows the channel: `LVC`, `LID` and a `LEV` on `WHISPER` → `"BULK"`, a `LEV` on `GUILD` stays `"NORMAL"`), `tests/helpers/sim.lua` (`sim:add` gives `env.guild = opts.guild or "МЕХАНАТА"` and `db.ledger = {}`, both kept across `sim:relog`; `sim.makeEnv`, the bots' env, gives neither; `sim:settle()` calls `ledgerNet:settle()` on every client, so a test need not wait out the adoption window of a new store; `sim:crash(name)` keeps its current semantics (it drops `fairKeep`) and also restores `db.ledger`, `db.stakeSeen`, `db.stakeLeft` and `db.stakeSat` to their copy at the last `client:stop()`), `TavernGames.toc`, `tests/toc_test.lua` (cap `< 240`), `tests/wow/adapter_test.lua`

**Interfaces:**
- Consumes: Tasks 3, 4; `Client:send`, `Client:after`.
- Produces:
  - `client.ledger` (a `Ledger`, store `env.db.ledger[env.guild]`), `client.ledgerNet`; both nil without `env.guild`
  - `net:make(kind, fields) -> entry | "queued"` — my new entry: added at once and sent as a GUILD `LEV` together with the entries I make within `LEDGER_COALESCE = 2` s (at most 4 per `LEV`); for `LEDGER_ADOPT_WAIT` s after every login it is queued and made when that time is over
  - `net:take(entry, from, live) -> "new" | "dup" | "twin" | nil` — an entry from the net (also used by Task 6): validated, taken only when its author and every name in `f`/`t`/`n` is a guild member (`env.member`) or already has entries in my store, added, own-name check, `"ledger"` emitted once per message. The rule that a whispered entry of another author than the sender is taken only inside an open exchange is Task 6's
  - `net:adopting() -> bool` (true only for a store without my `store.me` record); `net:settle()` (closes that window and the login queue: Task 6 calls it when my first exchange ends)
  - `net:asks() -> {entry, ...}` (unknown own entries with `n >` my saved `seq`: the crash question); `net:answer(keep)` (`true`: they count, denied by nobody; `false`: one `X` each)
  - client events `"ledger"`, `"mineAsk"`

- [ ] **Step 1: Write the failing tests** (simulator; И, М, П in the guild)

- `my entry reaches everyone online as one GUILD LEV`: И `ledgerNet:make("P", {f = М, c = 100, how = "hand"})` → after `LEDGER_COALESCE` (2 s) one GUILD message `t == "LEV"`, `#ev == 1`; М and П hold it with `dr == true`; each emitted `"ledger"` once.
- `entries made within two seconds leave as one LEV`: three `make` calls within 2 s → one GUILD `LEV` with `#ev == 3`; five → two `LEV` (4 and 1).
- `a live LEV must be all the sender's own`: П sends a GUILD `LEV` with an entry authored by И → nobody stores it. A GUILD `LEV` with 5 entries → dropped whole.
- `an invalid entry is dropped and the rest of the message is kept`: a `LEV` with one valid and one `c = 150` entry → one stored.
- `an entry under my name that I never wrote is denied once` (forged ledger event): П relays М a `C` whose `i` is `"Иван Петров:9"` (the test calls `net:take(entry, П)`; the gate of the whisper path is Task 6's); М relays nothing; when the entry reaches И the same way, И's client makes one `X` with `r = "Иван Петров:9"` and that entry's `h`; a second copy makes no second `X`; on М, once the `X` arrived, `ledger:denied(entry) == true`.
- `a clean author denies what it never wrote` (Review Focus 1): И (saved `seq` 3) stops cleanly (`client:stop()`), relogs, and gets a relayed entry `"Иван Петров:2"` it does not hold, or a different body under an id it holds → `X` at once; the counter is above it.
- `a crashed author is asked about its unsaved entries, not denied` (Review Focus 1): И makes `P` number 1 (М holds it), then `sim:crash("Иван Петров")` (the store comes back as at the last `client:stop()`, without it, saved `seq` 0); М relays it back → И holds it as uncounted, made no `X`, `net:asks()` has it, `"mineAsk"` was emitted, `store.me[И].seq == 1` and И's next own entry is number 2; `net:answer(true)` → the entry counts, the debtor's net is cleared (Task 4 view) and no `X` was made; in a second run `net:answer(false)` → one `X`.
- `while logging in, my own entries wait`: after any login И calls `net:make(...)` at once → `"queued"`, nothing sent; after `LEDGER_ADOPT_WAIT` (30 s) the entry is made with a number above every id seen under my name and sent.
- `a new install adopts`: a client with an empty `db.ledger` and no `store.me` entry adopts for the window (`net:adopting() == true`, no question); after `net:settle()` an unknown own entry is denied.
- `a foreign author is taken only when it is a guild member or known`: with `env.member` set, an entry of an invented author (or naming an invented name in `f`/`t`/`n`) → `nil`; an entry of an author that already has entries is taken; with `env.member` absent (the sim) every name is taken.
- `denials go out batched and rate-limited`: 20 forged entries under my name → 20 `X` made at once, sent at most 4 per `LEV` and at most `LEDGER_DENY_RATE = 8` per minute, the rest queued until the next minute.
- `a client without a ledger cannot open or sit at a staked table`: a bot env (no `env.guild`) `openTable{game = "ttt", stake = 50000}` → `nil, "stake"`, and `client:sit(tid, 2, 50000)` → `"stake"` locally with no `SIT` sent. This edits Task 2's `a bot never gets a seat at a staked table`: the bot's `sit` now refuses locally; a hand-sent `SIT` without `sk` still gets `SNO "stake"`.
- `Adapter.priority(msg, channel)` (`tests/wow/adapter_test.lua`): `LVC`, `LID` and a `LEV` on `WHISPER` → `"BULK"`; a `LEV` on `GUILD` → `"NORMAL"`. `env.guild` is `guild .. "-" .. realm`; with `GetGuildInfo` returning nil at creation there is no ledger and a log line.
- `a relayed entry is marked; a direct copy clears the mark`.
- `an entry dated more than an hour ahead is refused`.
- `a client without a guild has no ledger`: a bot env (`sim.makeEnv`) → `client.ledger == nil`, a `LEV` it receives is ignored without an error (that its `HI` has no `ld` is asserted in Task 6, once `ld` exists).
- `nothing is sent or taken after stop`.

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** `net:start()` reads whether `store.me[me]` exists (a missing record opens the adoption window of a new store) and creates it with `seq = 0`; there is no `clean` flag. Own-name check in `net:take`: `author == me` and `not ledger:has(i, h)` before the add → `ledger:bump(n)` always (denied or not); then window open: adopt (add); else `n ≤` my saved `seq` (or another body under an id I hold) → deny (`net:make("X", {r = i, h = hash})`, the forged entry is still stored so the denial has something to point at); else (`n >` saved `seq`, a crash) → store it uncounted, put it in `net:asks()` and emit `"mineAsk"`. `net:answer` adopts or denies them. The saved `seq` is the value in the store at login.
- [ ] **Step 4:** `bash t.sh` → green. **Step 5: Commit** `feat(core): ledger entries travel live; an entry forged under my name is denied; a crash is asked about`.

### Task 6: Sync between clients

**Files:**
- Create: `core/LedgerSync.lua`, `tests/core/ledger_sync_test.lua`
- Modify: `core/Presence.lua` (`Presence:hi` adds `ld`; `Presence:receive` stores `p.ld` and calls `client.ledgerSync:peer(name, ld)` on every `HI` with a valid 8-hex `ld`), `core/Client.lua` (compose `self.ledgerSync`, pass `LVC`, `LEV` by whisper and `LID` to it), `wow/Adapter.lua` (`env.send` takes an optional done-callback, passed to AceComm's `SendCommMessage`), `tests/helpers/sim.lua` (the sim's `env.send` calls it at once), `TavernGames.toc`, `tests/toc_test.lua` (cap `< 300`)

**Interfaces:**
- Consumes: `net:take`, `net:settle`, `L:vector`, `L:digest`, `L:above`, `L:list`, `L:has`.
- Produces: `client.ledgerSync`; `sync:peer(name, ld)`; `sync:receive(sender, msg)`; `sync:busy() -> bool`; `sync.stats = {sent, got}` (entries; for the tests and `/tavern debug`).

**The exchange** (A = the byte-lower name; all whispers):
1. A sees `P.ld ~= L:digest()`, waits the derived jitter (`LEDGER_JITTER_MIN + (byte sum of me .. peer .. ld) % 16` s, never `env.random`), checks again (P still listed, digests still differ, no exchange of mine running, the peer gap passed, not `env.status().instance`) and sends `LVC {a = vector}` (in pages of ≤ 1 500 bytes, all inside this exchange). A's exchange is open.
2. P, when it serves nobody, answers. For every author where `x` differs or that A lacks, it queues `L:above(author, A.n)` (`A.n = 0` for an author A lacks). If for any such author A is ahead of P (`A.n > P.n`) or A has an author P lacks, P first sends `LVC {a = <only those authors, P's own n and x>, r = true}`; A queues `L:above(author, P.n)` for each of them.
3. Authors where both `n` are equal and `x` differ (a hole above the run, a twin): A sends `LID {au, l}` for each, at most `LEDGER_LID_AUTHORS = 3` per exchange; `l` lists only the entries above the common `n` plus the ids I hold twins for, paged at ≤ 1 500 bytes; P queues every entry of that author that is not in `l` and answers `LID {au, l = <P's list>, r = true}`; A queues what is not in P's list.
4. Queues go out as `LEV` batches at the budgeted rate; the last batch of a side has `f = true` (a side with nothing to send sends `LEV {ev = {}, f = true}`). The exchange ends when both sides sent `f`, or 30 s after the partner's last message. At the end: `net:settle()`; if my digest changed, one GUILD `HI` (at most one per 30 s).
5. A responder that is already serving ignores a new `LVC` (the asker times out and tries the next difference it sees).
6. Acceptance and limits: a whispered `LEV` carrying an author other than its sender is taken only inside an open exchange with that sender (a `LEV` of the sender's own entries is taken as before); one exchange sends and takes at most `LEDGER_EXCHANGE_MAX = 300` entries (the next exchange continues); the next batch goes out only after the previous one has left (`env.send` done-callback); no exchange starts or continues while `env.status().instance`.

- [ ] **Step 1: Write the failing tests** (simulator; names chosen so that „Ана“ < „Борис“ < „Вера“ by bytes)

- `HI carries the digest and it follows the log`: `HI.ld == ledger:digest()`; after an entry the next `HI` has the new one; a bot's `HI` (`sim.makeEnv`, no guild) has no `ld` (moved here from Task 5).
- `a newcomer behind by 20 entries catches up from one partner`: Борис and Вера hold 20 entries of Вера; Ана logs in empty. After the jitter Ана whispers one `LVC`; Борис or Вера (whichever name pairs first: assert it is exactly one responder for these 20) sends 4 `LEV` batches of at most 6; Ана's digest equals theirs; no GUILD message other than `HI` was sent during the exchange.
- `the lower name starts, the higher one never does`: Вера behind Ана → Ана sends the `LVC`, Вера none.
- `both directions in one exchange`: Ана has 3 entries Борис lacks, Борис 5 that Ана lacks → after one exchange both digests are equal; Борис's `LVC` had `r == true` and only the authors Ана was ahead on.
- `a hole is healed`: Ана holds 1, 2, 3, 5 of Вера, Борис 1..5 → Ана gets 4 (and 5 again as a `dup`).
- `equal runs, different sets, are healed by LID` (sync conflict): Ана holds Вера's 1..3 and 6; Борис 1..3 and 7 → one `LID` each way, then both hold 6 and 7.
- `twins reach everyone` (sync conflict): Ана and Борис hold different bodies under `"Вера:4"` → after the exchange both hold both, `L:get` returns two, digests equal.
- `three bodies converge` (F4): Ана holds bodies a and b of `"Вера:4"`, Борис holds b and c, Вера's client holds d → after the exchanges (all pairs) every client holds the same set of at most 4 bodies and the digests are equal; with a fifth body the highest-`h` one is dropped everywhere.
- `a lying partner cannot make me upload everything`: a partner whose vector says it lacks every author gets at most `LEDGER_EXCHANGE_MAX = 300` entries in one exchange; the next exchange continues.
- `a LEV of foreign authors outside an exchange is dropped`: Борис whispers Ана a `LEV` with entries of Вера while no exchange with Борис is open → nothing stored; inside an open exchange they are taken and marked relayed; a `LEV` of Борис's own entries is taken either way.
- `an exchange waits while in an instance`: `env.status().instance` true → no `LVC` is sent and a running exchange sends no further batch; it resumes when false.
- `a denied forgery syncs with its denial`: Борис holds a forged `"Ана:9"` (relayed); the exchange brings it to Ана, who denies it; Борис ends with the `X`.
- `one exchange at a time`: with five peers that all differ, Ана never has two open exchanges; a responder serving Ана ignores Борис's `LVC`, and Борис's exchange ends after exactly 30 s.
- `a partner that vanishes mid-exchange` (disconnect): Борис goes offline after its first batch → Ана's exchange ends 30 s after that batch; what arrived is kept; Ана does not ask Борис again for 300 s but may ask Вера.
- `equal digests: no whisper at all`.
- `the jitter is re-checked`: Ана sees a difference, Борис's next `HI` (before the jitter fires) has Ана's digest → no `LVC`.
- `the jitter is derived, not drawn`: the `LVC` leaves `5 + (byte sum of me .. peer .. ld) % 16` s after the difference is seen, and `env.random` / `sim.nextRandom` is never called by the sync (a test that preloads `nextRandom` finds it untouched).
- `the budget of a batch and of a vector` (binding numbers, packed with the real `ns.Wire` over AceSerializer and LibDeflate as `tests/core/holdem_table_test.lua` does): a `LEV` of 6 `D` entries between two 25-byte names is at most 1 140 bytes (a batch is also cut by packed bytes: ≤ 1 140 by whisper, ≤ 760 on GUILD, so a batch of five-seat `R` entries holds fewer than 6); a `LVC` of 60 authors with 25-byte names at most 1 500; a vector that does not fit 1 500 bytes (100 authors with 64-byte names) goes in pages of at most 1 500 bytes inside the one exchange; an `HI` with `ld` at most 16 bytes longer than without.
- `the rate`: 60 queued entries leave in 10 batches, two seconds apart; with a live table session on the sender, six seconds apart; a batch goes out only after the previous one reported done through `env.send`'s callback (a test with a held callback sends nothing more).
- `the GUILD parts`: after an exchange the GUILD `HI` and any live `LEV` of one client are at most 10 parts of 255 bytes within any 10 s.
- `a LEV batch by whisper inside an exchange may carry any author and marks them relayed; one with 7 entries is dropped`.
- `after an exchange that changed my digest I send one GUILD HI, and not a second within 30 s`.
- `a sync message from a peer that is not listed in presence is ignored`.

- [ ] **Step 2: Run** → fails. **Step 3: Implement** `core/LedgerSync.lua`. **Step 4:** `bash t.sh` → green.
- [ ] **Step 5:** append to the check list: row 7 „two characters, one with 30 entries more: `/tavern debug` on both shows one `LVC`, `LEV` batches two seconds apart, no error, no disconnect; `/tavern` stays usable meanwhile“; row 8 „the same while playing Холдем on the sending client: the table does not stall“.
- [ ] **Step 6: Commit** `feat(core): ledger sync by whisper, one partner at a time, within the message budget`.

### Task 7: Stake-aware play for Морски шах and Death Roll

**Files:**
- Create: `core/Stakes.lua` (the extension and the fouls only; Task 8 adds the money), `tests/core/stakes_play_test.lua`
- Modify: `core/Lifecycle.lua` (`Session:hook` and `Session:filterAct` also call `ns.Ext.stakes` when `self.stake`; `Session:newGame` passes `staked = self.stake ~= nil`; `Session:canStart` → `"group"`, and `"break"` until `STAKE_BREAK = 10` s after the last staked game ended (the host's clock); `noteResult` adds `q = self.seq + 1` and `sk = self.stake` to `"result"`), `core/Member.lua` (`onEvent`: `engine.view` → `(engine.view or (s.stake and not engine.idle))`; `Member.timedOut`: `engine.publicAuto` → `(engine.publicAuto or (s.stake and not engine.view))`; after `engine.restore` of a snapshot `state.staked = s.stake ~= nil`, with the foul `forged` when the snapshot said otherwise), `core/Session.lua` (inside existing lines only: `armTimers` grace `(engine.view or self.stake)`; `"idleTimer"` in `TIMERS`), `core/Client.lua` (`Client:sit` refuses locally, event `"refused"(tid, "roll")`, a seat at a staked table whose engine has `idle` when `env.roll` is absent), `engines/deathroll.lua`, `core/Rolls.lua`, `wow/Rolls.lua` (`rollerName` passes a roll line as `env.me` only while a `RandomRoll` with that range ran in the last `ROLL_ECHO_WAIT` s, the addon's own call or the player's `/roll` caught with `hooksecurefunc("RandomRoll")`; otherwise the line passes as shown), `locale/*.lua` (`roll.unheard` „Домакинът не видя хвърлянето ти. Остани в групата и хвърли пак.“), `TavernGames.toc`, `tests/toc_test.lua` (cap `core/Stakes.lua < 340`)
- Test: `tests/core/stakes_play_test.lua`, `tests/engines/deathroll_test.lua`, `tests/wow/rolls_test.lua`

**Interfaces:**
- Produces:
  - `ns.Ext.stakes` with the hooks `applied`, `forged`, `refused`, `adopted`, `hostChanged`, `leaving`
  - session fields: `s.stakeRoster` (seat → name of who plays the running game; nil while none runs), `s.stakeFoul` (nil or `"forged"`, `"roll"`, `"stand"`, `"unseen"`), `s.stakeLive` (bool)
  - `Stakes.foul(s, why)` (keeps the higher rank), `Stakes.RANK = {forged = 4, roll = 3, stand = 2, unseen = 1}`
  - `Rolls.audit(s) -> nil | "roll" | "unseen"` (from `s.rollCheck`: a mismatch is `roll`, unseen is `unseen`; plus a per-index set `s.rollNotMine`, filled at verify time, for a roll of my seat that I did not make; it never reads `s.rollLog`, which keeps only `ROLL_LOG = 20` sightings). The note's roll part is final `ROLL_VERIFY_WAIT` s after the result
  - Death Roll: `state.staked`; `E.idle = true` (the marker for the idle stand)
  - `Session:canStart()` codes `"group"` and `"break"`; the local refusal `"roll"`

- [ ] **Step 1: Write the failing tests**

Engine (`tests/engines/deathroll_test.lua`, new `describe("staked")`):
```lua
local s = E.new({ seats = { true, true }, first = 1, opt = { start = 100 }, staked = true })
eq(s.staked, true)
eq({ E.apply(s, 1, { k = "roll", n = 40, max = 100, src = "claim" }) }, { nil, "src" })
eq({ E.apply(s, 1, { k = "roll", n = 40, max = 100, src = "ask" }) }, { nil, "src" })
eq({ E.apply(s, 1, { k = "roll", n = 40, max = 100, src = "timeout" }) }, { nil, "src" })
eq(E.apply(s, 1, { k = "roll", n = 40, max = 100, src = "seen" }), true)
eq(E.auto(s, 2, function() return 1 end), nil)
eq(E.snapshot(s).staked, true)
-- a game without `staked` behaves as before: every existing test of the file stays green
```

Simulator (`tests/core/stakes_play_test.lua`; staked tables, И hosts):
- `the hooks of stakes run only at a staked table`: a spy on `ns.Ext.stakes.applied` is called at a staked `ttt` table and never at a fun one.
- `ttt: a move the host makes for my seat is the foul forged` (residual F8): a bus filter makes И's client emit an `EV` for seat 2 that М never sent → М's `session.stakeFoul == "forged"`; at a fun table the same event leaves no field set and no hook called.
- `ttt: the host's timeout for my seat is taken only after my own clock ran out`: М on turn; И's timer plays М's automatic move 45 + 7 s after the turn began → no foul on М. With the bus delivering an `EV{auto = true}` for М's seat after 10 s → `"forged"`.
- `ttt: the host waits AUTO_GRACE before it moves for the other seat, and not for its own`: sent at 52 s for seat 2, at 45 s for seat 1. Fun table: 45 s for both (unchanged).
- `ttt: an event my engine refuses is forged`.
- `ttt: an auto move for my seat while my ACT is unmatched is forged` (F10): М sent an ACT before her own deadline and it is still unmatched in `s.sent`; an `auto` event for her seat arrives → `"forged"`; with no ACT outstanding the same event after her clock ran out is no foul.
- `a snapshot I asked for into a running game is unseen; a pushed one that changes it is forged`: М reloads mid-game (`sim:relog`) → `stakeFoul == "unseen"`; a snapshot from И nobody asked for whose board contradicts М's at the same `q` → `"forged"`.
- `an honest takeover is unseen, not forged` (F21): И goes silent, М (who missed the last event) is replaced by П as host; П's pushed snapshot (`how.changed`) is a prefix of М's game (same board cells; Death Roll: the same first rolls) → `"unseen"`; a snapshot that contradicts it → `"forged"`.
- `the staked flag comes from what I accepted` (F29): a host snapshot of a staked Death Roll with `staked = false` → after `engine.restore` М's `state.staked == true` and `stakeFoul == "forged"`; claim, ask and timeout rolls stay refused.
- `the foul is reset when the next game begins` (ttt „Реванш“; Death Roll „Нова игра“); `a foul raised by the event that starts a game counts against the new game` (F20): a forged `rematch` for М's seat starts a new staked match → `stakeFoul == "forged"` after the reset.
- `a staked game gets a break` (F20): at a staked table `canStart` → `nil, "break"` until 10 s after the last game ended by the host's clock, then `true`; a member whose clock says the new game began earlier than 10 s after the end notes `"forged"` for that game; a fun table starts at once as today.
- `the roster is who plays the running game`: Death Roll with И, М seated, „Започни“, then П sits → `stakeRoster == {И, М}` on every client (П's too, from its snapshot: `E.playing`).
- `death roll: the host cannot start while a seated player is not in its group`: `client:startGame()` → `nil, "group"`; once `env.inGroup` says yes → `true`. Fun table: starts as today.
- `death roll: a client that cannot /roll gets no staked seat`: a client added with `roll = false` calls `client:sit(tid, 2, 50000)` → its `"refused"` event is `(tid, "roll")` and no `SIT` is sent; at a fun table it sits as today.
- `death roll: only a roll the host saw counts`: М rolls where the host cannot see it (`sim.canSee`) → after 3 s no event; after И sees the same roll (canSee restored, М rolls again) → the event with `src == "seen"`.
- `death roll: nobody rolls for a silent seat; 180 s on turn stands it up as idle`: М on turn and silent → no roll event at 45 s; at 180 s the event `{k = "stand", seat = 2, why = "idle"}`; a roll at 179 s cancels it; the timer restarts with every turn and follows a host change; it fires only while `s.role == "host"` (a demoted host plays no idle stand and cancels it) and is re-armed in `hostChanged` (F22).
- `death roll: the host's own idle seat hands the table over` (`client:stand()` after 180 s on its own turn); the forfeit is recorded as `why = "left"` (its own client wrote `stakeLeft` through `Client:stand`), and the note keeps `why = "idle"` for the bill.
- `death roll: a staked game played cleanly has no foul` (F8): a full staked Death Roll game with rolls for every seat → no seat's `stakeFoul` is set at the end.
- `death roll: an idle stand after my own roll is the foul roll` (F10): М saw her own roll on her turn at the current max, the host ignored it and stood her up `idle` at 180 s (her clock agrees) → `stakeFoul == "roll"`; without a roll of hers on that turn the same stand is no foul.
- `death roll: a roll the host never played clears my rolling flag` (F10): М rolled at a staked table, the host plays nothing within `ROLL_CLAIM_WAIT + ROLL_VERIFY_WAIT` → `s.rolling` is cleared and the hint `roll.unheard` is shown; a host that plays it in time shows no hint.
- `a namesake's roll under my seat is the foul roll` (Review Focus 3): М = „Мария Колева“ seated; a roll line shown as „Мария“ that М's client did not make is taken by the host as М's; on М's client `Rolls.audit(s) == "roll"` (through `s.rollNotMine`).
- `a namesake's roll line is shown as shown` (`tests/wow/rolls_test.lua`, F9): a roll line with my first name and a range for which no `RandomRoll` ran in the last `ROLL_ECHO_WAIT` s is passed to the core as shown, not as `env.me`; with the addon's own `RandomRoll` (or the player's `/roll` caught by the `hooksecurefunc`) of that range just before, it passes as `env.me`.
- `Rolls.audit`: every recorded roll seen with the same number → nil; one seen with another number → `"roll"`; one never seen → `"unseen"`; `"roll"` wins over `"unseen"`; a game of more than 20 rolls keeps its early rolls in the audit (they come from `s.rollCheck`, not `s.rollLog`).
- `a stand of my own seat while my client runs is the foul stand, unless idle and my clock agrees`: И's client plays `{k="stand", seat = 2, why = "offline"}` while М is connected → М noted `"stand"` before its session ended; `why = "idle"` at 180 s by М's clock → no foul; `why = "idle"` at 60 s → `"stand"`.

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** The idle timer is the host's: armed from `applied` when `engine.idle`, `s.stake`, the game is live and a seat is on turn; it fires `OFFLINE_STAND_SECONDS` after that seat came on turn, only while `s.role == "host"`, and is re-armed in `hostChanged`. `canStart` compares the host's clock with the time the last staked game ended (`STAKE_BREAK`). A foul raised by the event that starts a game is set after the reset. `s.stakeLive` = `s.status == "live" and s.state ~= nil and not s:gameOver()`, recomputed at the end of every hook; when it turns true the roster is taken (occupied seats that `engine.playing` accepts, or all occupied seats) and the foul cleared.
- [ ] **Step 4:** `bash t.sh` → green; `wc -l core/Session.lua` < 540.
- [ ] **Step 5:** append check-list rows: 9 „staked Death Roll, three characters in one party: every roll shows without „?“; a player outside the party cannot be started with („Започни“ says why)“; 10 „a third guild character with the first name of a seated player types `/roll <max>` on that player's turn: what the table does, and that the seated player's line turns red“; 11 „leave a staked Death Roll turn untouched for three minutes: stood up, the bill names the idle player“.
- [ ] **Step 6: Commit** `feat(core): a staked table checks forged moves in open games; staked Death Roll takes only seen rolls and stands an idle seat`.

### Task 8: From a game to the ledger

**Files:**
- Modify: `core/Stakes.lua` (if it would cross 340 lines, the money half — notes, claims, `asks`/`answer`, `review` — moves to the new `core/StakesBook.lua`, < 260, TOC right after `core/Stakes.lua`, with its cap in `tests/toc_test.lua`; the cap is never raised), `core/Client.lua` (compose `self.stakes = ns.Stakes.new(self)` when the client has a ledger; `stakes:start()` after `ledgerNet:start()`), `core/Bots.lua` (`Bots.enable` installs `env.noLedger(tid)`), `tests/helpers/sim.lua` (`db.stakeSeen`, `db.stakeLeft` kept across relogs)
- Create: `tests/core/stakes_ledger_test.lua`

**Interfaces:**
- Consumes: `"result"` (with `q`, `sk`), the hooks and fields of Task 7, `net:make`, `View.of`, `View.claims`.
- Produces:
  - `Stakes.pairs(losers, winners, c) -> {{f, t, c}}` (names; every loser to every winner)
  - `stakes:note(gid, note)`; `env.db.stakeSeen[gid] = {at, g, sk, pairs, why, foul, tid}`; `env.db.stakeLeft[tid] = {at, sk, names, used = {}}`; notes older than `STAKE_SEEN_KEEP = 1209600` s are dropped at start
  - client event `"forfeit"`
  - `stakes:asks() -> {debt, ...}` (claims against me that my client could not decide; from `View.claims`); `stakes:answer(debtKey, yes)` (authors `C` or `N` `"no"` for every claim of that debt); the client event `"debtAsk"` is emitted whenever `stakes:asks()` changes
  - `stakes:review()` (runs on `"ledger"`, after every note and at start, and again `ROLL_VERIFY_WAIT` s after a result, when the note's roll part is final; idempotent; a claim that arrives earlier waits as pending)
  - `stakes:last(tid) -> note | nil` (the newest note of a table: the bill reads it)

**Rules** (beyond Global Constraints):
- On `"result"` at a staked table: `gid = tid .. "/" .. q`; pairs from the result's `names`; my note is written first (with `s.stakeFoul`; for an engine with the extension `rolls` the roll part is final `ROLL_VERIFY_WAIT` s after the result, and the note then holds the higher of `s.stakeFoul` and `Rolls.audit(s)`), then: the host authors `R`; every winner's client authors one `D` per pair it is the creditor of (`why = "lost"`, or the forfeit reason when the result has `left`); a loser's client arms `STAKE_OWE_WAIT`.
- On a seat-0 `stand` applied while `s.stakeLive` was true before it and `s.stakeRoster[seat]` is a name: the forfeit. `to` = the roster's other names that have not left; `gid = tid .. "/" .. s.seq`; the event `"forfeit"`; the same authoring as above with `why` = the stand's `why` (`"left"`, `"offline"`, `"idle"`). The leaver's seat leaves the roster.
- On `leaving` (I press „Стани“) while `s.stakeLive` and I am in the roster: `stakeLeft[tid]` is written before the `STD` goes out.
- At a fun table: the host authors `R` (no `sk`) on `"result"`; nothing else.
- At a table for which `env.noLedger(tid)` is true (a bot table): no entry is authored.
- Several entries of one client for one outcome go out in one `LEV` (at most 4 per message): `net:make` coalesces the entries made within `LEDGER_COALESCE` s.
- When the roll part of a note is still pending, a claim against me waits; after `ROLL_VERIFY_WAIT` s `review` answers it.

- [ ] **Step 1: Write the failing tests** (simulator; stake 5g = 50000 unless said; every scenario begins with `sim:settle()` unless it is about the adoption window)

- `ttt: the loser owes the winner; three entries, all confirmed`: И beats М. GUILD carried exactly (after the 2 s coalescing, counting `LEV` only): И's `LEV` with `R` and `D` (М→И, 50000, `"lost"`, `gid = tid .. "/" .. q` of the winning move), М's `LEV` with `C`. On П (a bystander) `View.net(view, М, И) == 50000` and the debt is `"confirmed"`.
- `ttt: a rematch is a second debt with its own gid`.
- `a fun game writes only its result`: one `R` without `sk`, no `D`.
- `a bot table writes no entry` (F12): with `env.noLedger(tid)` true (a table `Bots:tableKind` calls a bot table, a bot seated) no `R` and no `D` is authored, staked or fun.
- `stakes:asks() emits debtAsk` (F19): `"debtAsk"` fires when a claim joins `stakes:asks()` and when `answer` removes it, and not when nothing changed.
- `death roll, four players: who rolls 1 owes each of the others` (spec 8): three `D` claims from three authors, one `LEV` with three `C` from the loser; nets 50000 each; the host's `R` lists four names, `l = {loser seat}`.
- `ttt: pressing „Стани“ mid-game forfeits at once` (forfeit): М `client:stand()` in a live game → every client emitted `"forfeit"` with `name == М`, `to == {И}`, `why == "left"`; И claims; М's client (now without a session) confirms from its `stakeLeft` note; the debt is confirmed. The table then aborts as today.
- `a second claim for the same leave from the same creditor is not confirmed by the leave note` → it is in `stakes:asks()`.
- `standing up after the game is over costs nothing`; `a watcher or a player who sat down mid-game leaving costs nothing`.
- `death roll, three players: a leaver owes both others and the game goes on`: П leaves on М's turn → two claims against П (`"left"`); later М rolls 1 → М owes И only (П is no winner); nets: П→И, П→М, М→И, each 50000.
- `offline: the forfeit waits for the leaver` (disconnect; spec 5.4): М goes offline; after 180 s И's client stands her up → `D` with `why == "offline"`, `"pending"` on every client; no `C` from anyone. М logs in an hour later: after the sync her `stakes:asks()` has that debt; `stakes:answer(key, true)` → `C`, confirmed everywhere.
- `the leaver may contest`: `stakes:answer(key, false)` → `N` with `why == "no"`; the debt is `"contested"`, in no balance, and no longer in `asks()`.
- `a host that stands an online player up gets a contested debt` (residual E1): И's client plays an `"offline"` stand of М while М is connected → М's client answers И's claim with `N` `"stand"` without asking her.
- `a forged move turns into a contest, not a debt` (residual F8): the forged-move scenario of Task 7 played to И's win → М's client authors `N` `"forged"`; `View.net == 0` everywhere.
- `death roll: a roll I saw differently contests as roll; one I did not see is put to me`; `a claim that arrives before the roll verdict waits` (the note's roll part is final `ROLL_VERIFY_WAIT` s after the result; the claim stays pending, then `review` answers it).
- `death roll: a modified host's idle stand after my own roll is contested as roll` (F10): the Task 7 scenario played to И's win → М's client authors `N` `"roll"` for the claim.
- `ttt: an auto move for my seat with my ACT unmatched is contested as forged` (F10): the Task 7 scenario played to И's win → `N` `"forged"`.
- `a /reload mid-game keeps my staked seat and no forfeit is written` (F11): М `sim:relog` in a live staked game → she is still seated, no `"forfeit"` event and no `D` against her.
- `a claim for more than the table's stake is contested as amount` (Review Focus 4): И's client claims 500g for a 5g game → `N` `"amount"`.
- `a claim about a game I never played is put to me, not confirmed`; `twenty-five such claims from one creditor show twenty`.
- `the claim may come before or after my note`: deliver И's `LEV` to М before М applied the last move (bus filter delays the `EV`) → still exactly one `C`.
- `the loser's note survives a relog and confirms the late claim` (Review Focus 5): М's client noted the loss; И's `LEV` is dropped by the bus; М relogs; the sync brings the claim → `C` without a question.
- `no claim within 60 s: the loser writes the debt itself`: И crashes on the winning move (its client applied it, sent nothing more) → at 60 s М authors `D` (author М, `f = М`, `t = И`), `"confirmed"`; a claim by И for the same `gid` that arrives later (a hand-made `D` in the test) leaves it one debt of 50000.
- `the host hands over mid-game and the debts still come`: И (host) stands in a live game → forfeit by И owed to М, claimed by М, the new host; `R` authored by М.
- `a snapshot that already shows the result writes nothing`: П reloads after the end → no entry from П.
- `review is idempotent`: calling `stakes:review()` ten times adds no entry.
- `the guild cost of a game` (budget, real wire): a two-player staked game is at most 4 GUILD messages, a five-player Death Roll at most 10 with no sender above 3 (counted as `LEV` and sync `HI` messages, and in 255-byte parts: at most 10 parts per client within any 10 s); a `LEV` with 4 `C` entries is below 600 packed bytes.

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** **Step 4:** `bash t.sh` → green.
- [ ] **Step 5:** check-list rows: 12 „two characters, staked Морски шах: both see the same bill; a third character sees the debt in „Тефтер“ within a few seconds“; 13 „the loser alt-F4s on the last move: the debt waits, and is confirmed without a question when it logs in“; 14 „the loser goes offline mid-game for three minutes, then logs in: the question appears once, with the game and the amount“.
- [ ] **Step 6: Commit** `feat(core): results and forfeits of a staked table become ledger entries; my client confirms only what it saw`.

### Task 9: Payment (core)

**Files:**
- Create: `core/Pay.lua`, `tests/core/pay_test.lua`
- Modify: `core/Client.lua` (compose `self.pay`, pass `PAY`), `tests/helpers/sim.lua` (fakes `env.money`, `env.trade`, `env.mail` recording their calls in `sim.trades`, `sim.mails`; `opts.mailbox`, `opts.near = {names}`; `env.date(t)` from UTC arithmetic), `TavernGames.toc`, `tests/toc_test.lua` (cap `< 240`)

**Interfaces:**
- Consumes: `View.net`, `View.accounts`, `net:make`, `Names.matches`, `env.trade`, `env.mail`, `env.money`, `env.date`.
- Produces:
  - `pay:owed(name) -> copper` (`View.net(view, me, name)` when positive, else 0); `pay:due(name) -> copper` (the other direction)
  - `pay:options(name) -> {trade = "ok" | "far" | "none" | "off", mail = "open" | "closed" | "off", fee, short}` (`"off"`: the client lacks the API; `short` = copper I lack for the amount, plus the fee by mail; 0 when I have enough)
  - `pay:byTrade(name) -> true | nil, code` (`"none"` nothing owed, `"far"`, `"off"`, `"short"`); `pay:byMail(name) -> true | nil, code` (`"none"`, `"closed"`, `"off"`, `"short"`); both send `PAY {c, how}` to the creditor when presence lists it
  - `Pay.subject(view, me, name) -> string` — `"Tavern Games: "` followed by the open debts' games and dates, newest first (`"<game label> <dd.mm>"`, `dd.mm` from `env.date(at)` (`d`, `m`), joined by `" + "`), cut at 64 bytes on a character boundary; `Pay.TAG = "Tavern Games:"`
  - `pay:traded({name, gave, got, items})` — a completed trade with a guild member (`name` the full name, copper I gave and got, `items` = any item on either side)
  - `pay:mailed({shown, subject, c})` — money taken from a letter (`shown` = the sender as the inbox shows it)
  - `pay:asks() -> {{id, name | names, c, how}}`; `pay:answer(id, name | false)` (records the `P` for that debtor, or drops the question)
  - `pay:settle(name) -> {entry, ...} | nil` („Уредено“: `P` `"hand"` for the whole `pay:due(name)`; over 99 999 999 999 copper it splits into several `P`); `pay:nudge(name) -> true | nil, "wait"` (`PAY` `"nudge"`, once per `NUDGE_GAP = 3600` s per debtor); `pay:waiting(name) -> bool` (I announced a payment and no `P` came yet)
  - client events `"payAsk"`, `"nudge"(name, copper)`

- [ ] **Step 1: Write the failing tests** (И is owed 5g by М; confirmed)

- `owed and due are the two sides of the net`.
- `byTrade announces the payment and opens the trade for the net`: М near И → `sim.trades == {{from = М, name = И, c = 50000}}`, one whisper `PAY {c = 50000, how = "trade"}`; `pay:waiting(И) == true`.
- `byTrade: far, nothing owed, not enough gold`: `nil, "far"` / `"none"` / `"short"` (money 49999); nothing sent.
- `a finished trade after a PAY records the payment` (trade detection): И's `pay:traded{name = М, gave = 0, got = 50000, items = false}` → one `P {f = М, c = 50000, how = "trade"}`; nets 0; М's `waiting` false.
- `more gold than owed records only the debt` (Review Focus 2): `got = 80000` → `c == 50000`.
- `less gold than owed is a part payment`: `got = 20000` → `c == 20000`, `pay:owed` on М = 30000.
- `gold both ways counts the difference`: `gave = 10000, got = 30000` → `c == 20000`; `gave >= got` → nothing.
- `gold without a PAY is put to me` (Review Focus 2): no `PAY` before → no entry; `pay:asks()` has `{name = М, c = 50000, how = "trade"}`; `pay:answer(id, М)` → the `P`; `pay:answer(id, false)` → no entry, the question is gone.
- `a PAY older than 300 s does not count`.
- `a trade with an item is put to me, never recorded` (Review Focus 2).
- `gold from somebody who owes me nothing is ignored` (no entry, no question).
- `only the creditor records`: М's own `pay:traded{gave = 50000, got = 0}` makes no entry.
- `byMail fills the letter and announces it`: mailbox open → `sim.mails == {{to = И, subject = "Tavern Games: Морски шах 14.11", c = 50000}}` (the game's `game.ttt` label in the client's language and the debt's day and month from the sim's UTC `env.date`; `1700000000` is 14.11 in UTC, and the test never calls `os.date`), body = the locale key `pay.mail.body`; `PAY {how = "mail"}` only when И is listed online.
- `byMail needs the fee on top`: money 50029 → `nil, "short"`, `options.short == 1`; 50030 → sent.
- `subject: several games, newest first, cut at 64 bytes on a character boundary`.
- `money taken from a tagged letter of my one debtor records the payment` (mail detection): `pay:mailed{shown = "Мария Колева", subject = "Tavern Games: Морски шах 14.11", c = 50000}` → `P` `"mail"`; the same with `shown = "Мария"` (first name only) → the same.
- `a letter from a first name that fits two debtors is put to me with both` (Review Focus 3): debtors „Мария Колева“ and „Мария Стоянова“ → no entry; the question lists both names; `pay:answer(id, "Мария Стоянова")` records hers.
- `an untagged letter from a debtor is put to me; from anybody else ignored`.
- `a letter with more than is owed records only the debt`.
- `Уредено clears the whole net by hand`: `pay:settle(М)` → `P` `"hand"` 50000; with nothing due → nil.
- `a payment with copper is valid; Уредено over the cap splits` (F24): `pay:traded{gave = 0, got = 1500}` for a net of 50000 → `P` with `c == 1500`; a net of 150 000 000 000 settled by hand → two `P` (99 999 999 999 and the rest), net 0.
- `Напомни: one whisper an hour`: `pay:nudge(М)` → `PAY {c = 50000, how = "nudge"}`, М emits `"nudge"(И, 50000)`; again at once → `nil, "wait"`; a `nudge` from somebody I owe nothing emits nothing.
- `a PAY from a peer that is not in presence, or with a bad c or how, is ignored`.
- `mutual debts: paying the net by trade clears both` (И owes М 3g, М owes И 5g → М pays 2g → every net 0).

- [ ] **Step 2: Run** → fails. **Step 3: Implement** `core/Pay.lua`. **Step 4:** `bash t.sh` → green.
- [ ] **Step 5: Commit** `feat(core): payment by trade and by mail, recorded by the creditor's client only`.

### Task 10: Trade and mail in the game client

**Files:**
- Create: `wow/Trade.lua`, `wow/Mail.lua`, `tests/wow/trade_test.lua`, `tests/wow/mail_test.lua`
- Modify: `wow/Adapter.lua` (`createClient` sets `env.money`, `env.trade`, `env.mail`, `env.date` (from WoW's `date("*t", t)`: `{d, m, day}`); `Adapter.nameOfGUID(guid) -> full name | nil` from the roster scan), `tests/helpers/wow.lua` (trade and mail state, `fireTrade`, `fireMail` helpers), `TavernGames.toc`

**Interfaces:**
- Consumes: `client.pay:traded`, `client.pay:mailed`; the API spellings probed in Task 1.
- Produces: `ns.Trade.state(name)`, `ns.Trade.open(name, copper)`, `ns.Mail.state()`, `ns.Mail.fill(name, subject, body, copper)`, `ns.Mail.fee()`; `Adapter.nameOfGUID`.

**Rules:**
- Every game function is looked up at call time with both spellings and skipped when absent: set trade money = `C_TradeInfo.SetTradeMoney` or `SetTradeMoney` (called under `pcall`: it may be blocked when called from an event rather than a click), then `MoneyInputFrame_SetCopper(TradePlayerInputMoneyFrame, c)` when both exist; read = `GetPlayerTradeMoney`/`GetTargetTradeMoney` or `C_TradeInfo.GetTradeMoney`; inbox = `GetInboxHeaderInfo` or `C_Mail.GetInboxHeaderInfo`. With no way to set the money, or when the set-money call fails under `pcall`, `Trade.open` still opens the trade and the dialog shows the amount to type (`trade.state` stays `"ok"`); with no `InitiateTrade`, `"off"`.
- A unit for `name`: `target`, then `party1..4`, then `raid1..40`, the first whose `UnitGUID` is the roster GUID of that name. Range: `CheckInteractDistance(unit, 2)`; when the function is missing or raises (combat), the state is `"ok"` and the game itself refuses a far trade.
- A trade's partner is resolved by `UnitGUID("NPC")` through `Adapter.nameOfGUID`; a partner that is not a guild member is ignored. The amounts are read at every `TRADE_MONEY_CHANGED` and `TRADE_ACCEPT_UPDATE`; items are noted from `TRADE_PLAYER_ITEM_CHANGED`/`TRADE_TARGET_ITEM_CHANGED`. The trade counts as completed on `UI_INFO_MESSAGE` with `ERR_TRADE_COMPLETE` after both sides accepted; `TRADE_CLOSED` or `TRADE_REQUEST_CANCEL` without it drops the record. (Check-list rows 2 and 3 decide whether this holds on Forever; if the completion message is absent the fallback is "both accepted, then `TRADE_CLOSED`, and `GetMoney()` changed by exactly `got − gave`".)
- The amount is set once, at the first `TRADE_SHOW` after `Trade.open` whose partner is that player, within 30 s; never in a trade the addon did not open.
- Mail: `Mail.state()` is `"open"` between `MAIL_SHOW` and `MAIL_CLOSED`. `Mail.fill` switches to the send tab (`MailFrameTab_OnClick(nil, 2)` when present), sets the three edit boxes (the body is `SendMailBodyEditBox` or `MailEditBox`, whichever exists, the same way as the other fields) and `SetSendMailMoney(c)` (and `MoneyInputFrame_SetCopper(SendMailMoney, c)`), never COD, never `SendMail`. `Mail.fee()` = `GetSendMailPrice()` or 30.
- Money taken from a letter: `hooksecurefunc` on `TakeInboxMoney` and `AutoLootMailItem` reads that row's sender, subject and money **before** the game changes it (the hook runs after the call: so the rows are cached at every `MAIL_INBOX_UPDATE` and the hook reads the cache), and reports `pay:mailed` when the next `MAIL_INBOX_UPDATE` shows that row without money or gone. Without `hooksecurefunc`: a cached row with money that is without money at the next update, while `GetMoney()` rose by that amount.

- [ ] **Step 1: Write the failing tests** (fake client; `Wow.new` with a roster of „Иван Петров“ (me), „Мария Колева“ GUID `Player-1-00000002`)

`tests/wow/trade_test.lua`:
- `state: no unit, far, ok`: no target → `"none"`; target Мария with `CheckInteractDistance` false → `"far"`; true → `"ok"`; `CheckInteractDistance` raising → `"ok"`; `InitiateTrade` absent → `"off"`.
- `open starts the trade with the unit and fills the amount when it shows`: `Trade.open("Мария Колева", 50000)` → `InitiateTrade` called with `"target"`; at `TRADE_SHOW` (partner GUID Мария's) the set-money function got 50000, once; a second `TRADE_SHOW` sets nothing.
- `a trade the addon did not open is never filled`.
- `a blocked set-money call is not an error`: the fake's set-money function raises → `Trade.open` still returns `true`, the trade opens, nothing is filled, and the state stays `"ok"` so the dialog shows `pay.trade.type`.
- `the classic and the modern spelling both work`: with only `SetTradeMoney` / only `C_TradeInfo.SetTradeMoney` defined.
- `a completed trade is reported with both amounts`: money 0 / 50000, both accept, `UI_INFO_MESSAGE(ERR_TRADE_COMPLETE)` → `client.pay:traded` got `{name = "Мария Колева", gave = 0, got = 50000, items = false}` once.
- `the trade partner is resolved by GUID, not by the shown name` (Review Focus 3): `UnitName("NPC")` = „Мария“ and the roster has two „Мария …“ → the reported name is the one whose GUID matches.
- `a cancelled trade reports nothing` (`TRADE_CLOSED` without the completion; `UI_ERROR_MESSAGE(ERR_TRADE_CANCELLED)`).
- `an item on either side sets items = true`.
- `a trade with a stranger reports nothing`.
- `the forbidden functions are never called` (`AcceptTrade`).

`tests/wow/mail_test.lua`:
- `state follows MAIL_SHOW and MAIL_CLOSED`.
- `fill writes recipient, subject, body and money and sends nothing`: the three edit boxes' text and `SetSendMailMoney(50000)`; `SendMail`, `SetSendMailCOD` not called.
- `fill uses whichever body box exists`: with only `SendMailBodyEditBox`, with only `MailEditBox`, the body text lands in the one present.
- `fee is the game's price, 30 without it`.
- `taking the money of a letter reports it once`: inbox row (`"Мария"`, `"Tavern Games: Морски шах 14.11"`, 50000); `TakeInboxMoney(1)` by the player (the fake calls the hook), then `MAIL_INBOX_UPDATE` with the row's money 0 → `pay:mailed{shown = "Мария", subject = ..., c = 50000}` once; a further update reports nothing.
- `auto-loot of a letter with money reports it too`; `a letter deleted with its money untaken reports nothing`; `a letter without money reports nothing`.
- `without hooksecurefunc the bag money decides`.
- `the addon never takes the money itself` (`TakeInboxMoney`, `AutoLootMailItem` not called by addon code: the fake distinguishes the player's call).

- [ ] **Step 2: Run** `bash t.sh tests/wow` → fails. **Step 3: Implement.** **Step 4:** `bash t.sh` → green.
- [ ] **Step 5:** check-list rows: 15 „„Плати“ → „Трейд“ next to the creditor: the trade opens with the amount filled in; no "action blocked"; in and out of combat“; 16 „after the trade both clients show the debt struck through within seconds“; 17 „at a mailbox: the letter is filled, the money box shows the amount, „Send“ is the game's own button“; 18 „the receiver takes the money: the debt is struck through on both“; 19 „a trade for an item with the same player: a question appears, nothing is recorded“; 20 „the recipient form the mail frame accepts for „Име Фамилия“ (full name, with a realm, first name only), and which body box (`SendMailBodyEditBox` / `MailEditBox`) is filled“.
- [ ] **Step 6: Commit** `feat(wow): trade and mail bindings: fill the amount, report what arrived, never press the button`.

### Task 11: UI — the stake at the table

**Files:**
- Create: `ui/StakePanels.lua`, `tests/ui/stake_test.lua`
- Modify: `ui/NewTableDialog.lua` (the stake row, shown only for `ttt` and `deathroll`), `ui/Hall.lua` (`Hall.clickChair`, `Hall.clickRow`'s "sit" (list mode), through `StakePanels.ask` as well, `Hall.tableTooltip`, `Hall.chairTooltip`, the list row: the stake), `ui/InviteToast.lua` (the stake line), `ui/TableFrame.lua` (`TableFrame.standCosts`, the header's stake label, the bill), `ui/TablePanels.lua` (the confirm panel's text), `ui/games/TicTacToeView.lua`, `ui/games/DeathRollView.lua` (hide their own result line while the bill shows), `locale/*.lua`, `TavernGames.toc`
- Edit: `tests/ui/hall_test.lua:390` (`eq(#D.stake.options, 1)` becomes 2 options for `ttt` and `deathroll`, 1 for every other game)

**Interfaces:**
- Consumes: `Stake.fromParts`, `Stake.worst`, `client:openTable{stake}`, `client:sit(tid, seat, sk)`, `"result"`, `"forfeit"`, `client.stakes:last(tid)`, `View.of`.
- Produces: `ns.StakePanels.ask(rec, seat)` (the acceptance question), `ns.StakePanels.bill(v, s)` (shown inside the table frame), `StakePanels.billRows(client, note) -> {{f, t, c, status}}`, `TableFrame.standCosts(s)` true also for a live staked game I play in.

**Strings (Bulgarian; keys as given):**

| key | text |
|---|---|
| `dialog.stake.gold` | „Със залог“ |
| `dialog.stake.amount` | „Залог на човек“ |
| `dialog.stake.bad` | „Залогът е поне 1s, в голд и силвър.“ |
| `stake.ask.title` | „Маса със залог“ |
| `stake.ask.text` | „Залогът е %s. Ако загубиш, дължиш %s на победителя.“ |
| `stake.ask.each` | „Залогът е %s. Който хвърли 1, плаща по %s на всеки от останалите, най-много %s.“ |
| `stake.ask.leave` | „Ако станеш по време на игра или изчезнеш за 3 минути, губиш служебно.“ |
| `stake.ask.yes` | „Приемам и сядам“ |
| `stake.ask.no` | „Отказ“ |
| `refused.stake` | „Залогът на масата е друг. Виж го и седни отново.“ |
| `refused.roll` | „На тази маса се хвърля само с истински /roll, а твоят клиент не може.“ |
| `table.stake` | „Залог: %s“ |
| `table.stake.none` | „За удоволствие“ |
| `stand.stake` | „Ако станеш сега, губиш служебно и дължиш %s.“ |
| `start.group` | „Всички на масата трябва да са в групата ти, преди да започнете.“ |
| `start.break` | „Изчакай малко: играчите решават дали остават.“ |
| `bill.title` | „Сметката“ |
| `bill.row` | „%s дължи на %s %s“ |
| `bill.pending` | „чака потвърждение“ |
| `bill.contested` | „оспорен“ |
| `bill.left` | „%s напусна играта и губи служебно.“ |
| `bill.idle` | „%s не хвърли 3 минути и губи служебно.“ |
| `bill.rematch` | „Реванш на същата маса“ |
| `invite.stake` | „Залог: %s“ |

- [ ] **Step 1: Write the failing tests** (`tests/ui/stake_test.lua`, the fake client with `opts.ui`)
- `the dialog opens for fun by default and sends no stake`: `D.open("ttt")`, submit → `openTable` got `stake == nil`.
- `„Със залог“ is offered only for Морски шах and Death Roll`: the stake row has 2 options (fun, stake) for `ttt` and `deathroll` and 1 for `santase`, `belot`, `tabla`, `holdem` (the edited `hall_test.lua:390`).
- `„Със залог“ shows two boxes and sends copper`: choose it, gold `5`, silver `25`, submit → `stake == 52500`.
- `a bad amount keeps the dialog open with the reason`: gold and silver empty, or silver `100` → no call, the error line is `dialog.stake.bad`.
- `a click on a chair of a staked table asks first`: `Hall.clickChair` on a record with `stake = 50000` → no `SIT` yet; the panel shows `stake.ask.text` with „5g“ twice and `stake.ask.leave`; „Приемам и сядам“ → `client:sit(tid, seat, 50000)`; „Отказ“ → nothing sent. A fun table sits at once, as today.
- `a click on a row of the list asks first too` (F16): `Hall.clickRow` in list mode on a staked table → the same question (no `SIT` yet; „Приемам и сядам“ → `client:sit(tid, firstFree, sk)`); on a fun table it sits at once.
- `Death Roll's question names the worst case`: stake 1g → the text has „1g“, „1g“ and „4g“.
- `the tooltips and the list row show the stake; a fun table says „За удоволствие“`.
- `the invitation shows the stake line only for a staked table`.
- `the table header shows the stake`.
- `„Стани“ in a live staked game asks first and names the amount`: `standCosts` true; the confirm text is `stand.stake` with „5g“ (Death Roll with three other players: „15g“, `Stake`'s amount times the roster's others); after the game is over it does not ask.
- `the bill shows who owes whom and follows the ledger`: after a `"result"` the bill has the title, one row `bill.row` („Мария дължи на Иван 5g“, names in class colour) with `bill.pending`; when the `C` arrives the mark is gone; an `N` shows `bill.contested`.
- `a forfeit's bill says why` (`bill.left` / `bill.idle` above the rows; `bill.idle` is chosen from the note's `why`, so the host's own idle forfeit, whose `D` says `"left"`, still shows `bill.idle`).
- `the bill's buttons`: „Към залата“ (the existing label key of the table frame) calls `TableFrame.stand`; „Реванш на същата маса“ sends the engine's rematch for `ttt`, calls `TableFrame.startGame` for the host of a Death Roll table, and is hidden for a Death Roll guest.
- `„Започни“ refused for the group says start.group on the news line`; refused for the break (`"break"`) it says `start.break`.
- `bg and en have the same keys` (the existing parity test covers it; run it).

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** The bill is a panel over the lower part of the felt (it must not cover the board's winning line or the roll ladder): 360 × (48 + 22 per row) px, centred, `BOTTOM` of the felt + 12. `ui/TableFrame.lua` stays below 600 lines: the bill lives entirely in `ui/StakePanels.lua` and is called from one line of the frame's render.
- [ ] **Step 4:** `bash t.sh` → green.
- [ ] **Step 5:** check-list rows: 21 „the new-table dialog with „Със залог“: nothing clipped at the default and at a low UI scale; Tab moves between the two boxes“; 22 „the acceptance question for Death Roll reads naturally with 2 and with 5 seats“; 23 „the bill does not cover the winning line or the last rolls“.
- [ ] **Step 6: Commit** `feat(ui): a table for a stake: the dialog, the acceptance at the chair, the warning on leaving, the bill`.

### Task 12: UI — „Сметки“ and „Плащане“

**Files:**
- Create: `ui/Accounts.lua`, `ui/PayDialog.lua`, `tests/ui/accounts_test.lua`
- Modify: `ui/HallPeers.lua` (`HallPeers.build(v, page, x, y, h)`: the peers list starts below the accounts), `ui/Hall.lua` (builds `ns.Accounts` in the right column, 190 px high, above „В кръчмата сега“), `locale/*.lua`, `TavernGames.toc`

**Interfaces:**
- Consumes: `View.accounts`, `client.pay` (Task 9), `client.stakes:asks/answer` (Task 8), `client.ledgerNet:asks/answer` (Task 5), the events `"ledger"`, `"payAsk"`, `"debtAsk"`, `"mineAsk"`, `"nudge"`, `W.Info`.
- Produces: `ns.Accounts.build(v, page, x, y, w, h)`, `Accounts.rows(client) -> {{kind = "ask" | "payAsk" | "mine" | "owe" | "owed", ...}}` (questions first, then what I owe, then what I am owed), `ns.PayDialog.open(name)`.

**Strings:**

| key | text |
|---|---|
| `accounts.title` | „Сметки“ |
| `accounts.none` | „Нямаш сметки.“ |
| `accounts.owe` | „Дължиш на %s %s“ |
| `accounts.owed` | „%s ти дължи %s“ |
| `accounts.pay` | „Плати“ |
| `accounts.nudge` | „Напомни“ |
| `accounts.nudged` | „Напомнено“ |
| `accounts.settle` | „Уредено“ |
| `accounts.settle.sure` | „Получи ли %s от %s? Това изчиства сметката.“ |
| `accounts.waiting` | „чака %s да потвърди“ |
| `ask.debt` | „%s казва, че му дължиш %s от %s (%s).“ |
| `ask.debt.left` | „Напуснал си масата и губиш служебно.“ |
| `ask.debt.unseen` | „Не видях цялата игра.“ |
| `ask.yes` | „Потвърждавам“ |
| `ask.no` | „Оспорвам“ |
| `ask.pay` | „%s ти даде %s. Към сметката ли е?“ |
| `ask.pay.yes` | „Да, към сметката“ |
| `ask.pay.no` | „Не“ |
| `ask.pay.who` | „От кого са тези %s?“ |
| `ask.mine` | „Тези записи на твое име не са запазени на този компютър. Твои ли са?“ |
| `ask.mine.yes` | „Мои са“ |
| `ask.mine.no` | „Не са мои“ |
| `nudge.say` | „%s ти напомня: дължиш %s.“ |
| `pay.title` | „Плащане“ |
| `pay.to` | „на %s“ |
| `pay.trade` | „Трейд“ |
| `pay.trade.text` | „Отваря трейд с %s и попълва сумата. Ти натискаш „Trade“.“ |
| `pay.trade.far` | „%s не е до теб.“ |
| `pay.trade.none` | „Избери %s за цел или го покани в група.“ |
| `pay.trade.type` | „Впиши сумата сам: %s.“ |
| `pay.mail` | „Поща“ |
| `pay.mail.text` | „Писмото е попълнено. Ти натискаш „Send“.“ |
| `pay.mail.closed` | „Отвори пощенска кутия.“ |
| `pay.mail.body` | „Изплатено през Tavern Games. Наздраве!“ |
| `pay.fee` | „Трейдът е без такса. Пощата взима %s и писмото може да пътува до час.“ |
| `pay.hold` | „Много чести преводи могат временно да задействат защитата срещу купуване на голд. Затова плащаш всичко към един човек наведнъж.“ |
| `pay.short` | „Не ти достигат %s.“ |
| `pay.off` | „Този клиент не позволява това. Плати ръчно и помоли %s да натисне „Уредено“.“ |

- [ ] **Step 1: Write the failing tests** (`tests/ui/accounts_test.lua`)
- `no accounts: the empty line`; `I owe: the row and „Плати“`; `I am owed: the row with „Напомни“ and „Уредено“`.
- `rows are the nets, one per person, questions first`: И owes М 5g and is owed 2g by П, plus one debt question → `Accounts.rows` kinds in order `ask`, `owe`, `owed`.
- `a debt question has two buttons and they answer it`: „Потвърждавам“ → `stakes:answer(key, true)`; „Оспорвам“ → `false`; the text is `ask.debt` with the creditor, the amount, the game label and the date, plus `ask.debt.left` for a forfeit or `ask.debt.unseen` for a game I did not see whole.
- `the own-entries question` (Review Focus 1, F3): with entries under my name above my saved `seq`, `Accounts.rows` has a `"mine"` row among the questions with `ask.mine` and two buttons; „Мои са“ → `ledgerNet:answer(true)`, „Не са мои“ → `ledgerNet:answer(false)`; the row is gone after either, and `"mineAsk"` re-renders the column.
- `the column header and the payment dialog carry an ⓘ` (F19): `W.Info(…, "ledger")` on the „Сметки“ header and on `PayDialog`.
- `a payment question with one name has „Да, към сметката“ / „Не“; with several, one button per name and „Не“`.
- `„Уредено“ asks once more before it clears` (the text `accounts.settle.sure` with the amount and the name), then calls `pay:settle`.
- `„Напомни“ turns into „Напомнено“ for an hour`; the debtor's chat frame gets `nudge.say` once.
- `the column follows the ledger without a reload` (`"ledger"` re-renders it).
- `„Плати“ opens the dialog with the net and the two ways`: trade `"ok"` → the „Трейд“ button is enabled with `pay.trade.text`; `"far"` / `"none"` → disabled with that line; mail `"closed"` → disabled with `pay.mail.closed`; `"open"` → enabled; `pay.fee` shows the fee (`Util.money(30)` = „30c“) and `pay.hold` is always shown.
- `not enough gold says how much is missing and disables that way` (by mail the fee counts).
- `a client without the API shows pay.off`.
- `after „Трейд“ the row says who is to confirm` (`accounts.waiting`), until the `P` arrives.
- `the dialog closes when the debt is gone`.
- `the peers list still shows below the accounts and scrolls` (the existing hall tests stay green; `HallPeers` rows start at the new offset).

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** **Step 4:** `bash t.sh` → green.
- [ ] **Step 5:** check-list rows: 24 „the hall's right column with six accounts and two questions: nothing overlaps „В кръчмата сега““; 25 „„Плащане“ next to the creditor, far from it, at a mailbox, away from one: the right lines and buttons“; 26 „kill the client process after a payment and relog: the question „Тези записи на твое име не са запазени на този компютър. Твои ли са?“ appears among the questions of „Сметки“, and „Мои са“ clears the debt“.
- [ ] **Step 6: Commit** `feat(ui): the hall column „Сметки“ and the payment dialog`.

### Task 13: UI — the tab „Тефтер“

**Files:**
- Create: `ui/LedgerTab.lua`, `tests/ui/ledger_tab_test.lua`
- Modify: `locale/*.lua`, `TavernGames.toc`

**Interfaces:**
- Consumes: `View.rows`, `View.totals`, `View.of`, `L:each` + `L:denied` (the denied and relayed entries, `dr`/`rl`; `View.denied` too when Task 4 added it), `env.date`, `ns.MainWindow.addTab`, `W.Scroll`, the ⓘ of the title bar (topic `"ledger"`, Task 14).
- Produces: `ns.LedgerTab.build(page)`, `LedgerTab.lines(client) -> {{text parts, state}}` (`state`: `"open"`, `"paid"`, `"pending"`, `"contested"`, `"denied"`), the tab `"ledger"` with the title key `tab.ledger`.

**Strings:** `tab.ledger` „Тефтер“; `ledger.head` „Открити дългове в гилдията: %s в %d записа“; `ledger.empty` „Тефтерът е празен. Никой никому не дължи.“; `ledger.row` „%s → %s“; `ledger.part` „остават %s от %s“; `ledger.pending` „чака потвърждение“; `ledger.contested` „оспорен“; `ledger.denied` „отречено“; `ledger.reneged` „отречено от автора си“; `ledger.relayed` „пренесено“; `ledger.clash` „спор за сумата“; `ledger.top` „Най-голям длъжник: %s (%s)“; `ledger.age.today` „днес“; `ledger.age.yesterday` „вчера“; `ledger.age.days` „%d дни“.

- [ ] **Step 1: Write the failing tests**
- `the tab sits between Зала and Настройки`: `MainWindow.order == {"hall", "ledger", "settings"}`.
- `an empty ledger says so`.
- `the head counts the open confirmed debts`: two open debts of 5g and 2g → `ledger.head` with „7g“ and 2.
- `rows: open first (newest first), then pending, contested, paid, denied`; a paid row's text objects are struck through (the row's `state == "paid"` and its strike texture is shown); a partly paid row shows `ledger.part` („остават 2g от 5g“).
- `a pending and a contested row carry their mark and are in no total`.
- `a denied entry is listed as „отречено“; one I got directly from its author as „отречено от автора си“`.
- `a relayed entry carries „пренесено“ in its tooltip`.
- `the age label`: same day → „днес“, the day before → „вчера“, five days → „5 дни“ (calendar days from `env.date(t).day`, now from `env.epoch()`; a debt made at 23:50 and read at 00:10 is „вчера“).
- `the foot names the biggest debtor`; nobody owes → the foot is hidden.
- `names are in class colour when the class is known (presence), ink otherwise`.
- `the tab follows the ledger` (`"ledger"` re-renders an open page; a hidden page renders on show).
- `two hundred rows scroll and build only the visible widgets` (at most the page's row count + 2 widgets created).

- [ ] **Step 2: Run** → fails. **Step 3: Implement** (the look of `docs/mockups/06-leaderboard-ledger.html`, right half: Alegreya Italic rows on the paper texture already generated for the rules book). **Step 4:** `bash t.sh` → green.
- [ ] **Step 5:** check-list row 27 „„Тефтер“ with real entries from two characters: both show the same rows and the same head“.
- [ ] **Step 6: Commit** `feat(ui): the tab „Тефтер“`.

### Task 14: The rules book, the documents, the end-to-end pins

**Files:**
- Modify: `core/Help.lua` (topics `stakes`, `ledger`; the `fair` topic gains one block; the intro's invites step becomes the payment step („Сметки“ → „Плати“), so the intro keeps 4 steps; `help.soon.*` is rewritten: „Залози има засега на Морски шах и Death Roll; Сантасе, Белот, Табла и Холдем идват скоро.“ style), `ui/HelpBook.lua` only if a block kind is missing (none is expected), `locale/*.lua`, `tests/core/locale_help_test.lua` (the topic list and the quoted-label check gain the two topics; lines 25–30 and 151–152, the topic list and the pinned `help.soon.p`/`example`, are edited), `tests/ui/book_test.lua` (the intro's "1/4" step text is edited), `docs/superpowers/notes/engine-contract.md` (Addendum 8), `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` (a section „Stage F1 additions“ under "Shared contracts": the protocol table and the `env` table of this plan, copied), `docs/superpowers/notes/2026-11-21-rulings.md` (a section "Stage F1": the roadmap's F1 residual table with "closed" / "re-accepted" and the test that pins each, plus the pre-flight residuals, re-accepted with no code beyond the crash question, the acceptance rules and the author queue: (a) a relayed `C`/own `D`/`P` counts on third clients before its author has been heard from (spec 6.4 accepts relayed entries, marked „пренесено“; the victim's own client never counts it and denies it when it sees it), pinned by Task 5 `a relayed entry is marked; a direct copy clears the mark` and `an entry under my name that I never wrote is denied once`; (b) a creditor's modified client can take the gold and never record `P`, the debtor's row says „чака %s да потвърди“, pinned by Task 12 `after „Трейд“ the row says who is to confirm`; (c) a forger can plant entries under my name in the window of a new store, pinned by Task 5 `a new install adopts`; (d) ledger growth, no retention until F4, pinned by Task 3 `the author cap counts R only`; (e) `gid` stays `tid/q`: after a lost-event takeover a gid can repeat, and it lands as an asked question, never as an automatic `C`, pinned by Task 7 `an honest takeover is unseen, not forged`), `docs/superpowers/notes/2026-11-stageF1-ingame-checks.md`
- Create: `tests/core/stakes_flow_test.lua`

**Interfaces:**
- Consumes: everything above. Produces: nothing new.

**Help topics** (tavern talk, short sentences, one example each, every quoted label a real UI label):
- `stakes` (title key `help.stakes.title` „Залози“): `p1` what a staked table is and that „Само за удоволствие“ changes nothing; `accept` the question at the chair; `example` „Иван и Мария играят Морски шах за 1g. Мария печели. Иван вижда в „Сметки“: „Дължиш на Мария Колева 1g“ и натиска „Плати“.“; `deathroll` who pays whom with three players and the worst case; `leave` „Стани“ during a game, three minutes offline, three minutes without a roll; `honest` my addon confirms only what it saw itself, and what „оспорен“ means.
- `ledger` (title key `tab.ledger`): `p1` one book for the whole guild, everybody sees the same; `pay.trade` and `pay.mail` step by step, the fee, the hour a letter may travel; `settle` „Уредено“ and „Напомни“; `net` debts both ways are set off (example with 5g and 3g); `alts` paying from another character is not seen: ask for „Уредено“ (spec 5.6); `holds` why everything to one person goes in one transfer.
- `fair` gains `help.fair.stakes`: on a staked table nobody moves or rolls for you; if the table does, your addon contests the debt by itself.

- [ ] **Step 1: Write the failing tests**

`tests/core/locale_help_test.lua`: the topic list is `hall, ttt, deathroll, santase, belot, tabla, holdem, fair, stakes, ledger, soon` (the edit of lines 25–30); the rewritten `help.soon.p`/`example` no longer say that all games are for fun (the edit of lines 151–152), and `tests/ui/book_test.lua` pins the intro's four steps with the payment step; every key of the two topics exists in both languages; the pinned example sentence above is in `locale/bg.lua` verbatim; every quoted label in the two topics („Сметки“, „Плати“, „Уредено“, „Напомни“, „Стани“, „Със залог“, „Само за удоволствие“, „Приемам и сядам“, „Потвърждавам“, „Оспорвам“, „Трейд“, „Поща“, „Тефтер“) is the text of a UI key.

`tests/core/stakes_flow_test.lua` (the whole road in the simulator, real wire sizes; four guild members А, Б, В, Г):
- `from the chair to the cleared debt`: А opens Морски шах for 2g 50s; Б accepts and sits; А wins; Б's client confirms; В (a bystander) and Г (offline the whole time) — В shows `net(Б, А) == 25000`; Б pays by trade (near, `PAY`, the fake trade completes on both) → А's `P`; every online client shows net 0 and the row `"paid"`; Г logs in → after one exchange Г's digest equals А's and its rows are the same list.
- `the whole road stays inside the budget`: GUILD messages of the game and the payment ≤ 5 in total, no client above 3; Г's catch-up is whispers only; bytes sent by any one client in any 10 s window ≤ 8 000.
- `two tables end in the same second`: both games' entries arrive everywhere, no id is reused, digests agree.
- `a guild of two versions`: a client at `v = 2` gets nothing but the version handling of today; its `HI` without a usable `ld` starts no exchange.
- `a fun-only evening is byte-identical but for HI.ld and R`: the full message log of an existing fun scenario with every client online throughout (the first of `tests/core/session_test.lua`'s two-player games, replayed here) equals the log at `82b0140` after removing `ld` from every `HI` and dropping `LEV` messages (the reference log is a literal in the test, generated once from the `82b0140` build by the implementer and committed with the test).

- [ ] **Step 2: Run** → fails. **Step 3: Implement** the help content and the documents. Addendum 8 states, in the style of Addendum 7: the always-on extension and its hooks; `staked` in `E.new`'s options; `E.idle`; the fouls and their ranks; the rule "a staked open game is checked like a view game" (`engine.view or (s.stake and not engine.idle)`: Death Roll is judged by `Rolls.audit` alone) and what it amends (Addendum 6's "the forged-move check does not run" now holds only for a fun table and for Death Roll); the `"result"` fields `q` and `sk`; the residuals F1 closed, the ones it re-accepted with their argument, and the two new ones (the adoption window of a new store and the crash question; a winner whose client missed the final event relies on the loser's own `D`).
- [ ] **Step 4:** `bash t.sh` → all green; note the final test count in the commit message.
- [ ] **Step 5: Commit** `docs+test: the rules book on stakes and the ledger; Addendum 8; the F1 protocol table; the end-to-end budget pins`.

---

## After the last task

Run the whole-branch review against the Review Focus list and the F1 residual table of the roadmap, then the in-game check list (`docs/superpowers/notes/2026-11-stageF1-ingame-checks.md`, rows 1–27; rows 1–6 first, since rows 2–4 can change Task 10's event rules). F2's plan is written after those results are in.
