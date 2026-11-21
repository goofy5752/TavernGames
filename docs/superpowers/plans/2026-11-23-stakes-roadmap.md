# Tavern Games: roadmap for the stakes stage (sub-stages F1–F4)

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.4, 5.5, 5.6, 6.4, 6.5, 6.6 bind). **Base:** branch `feature/games` at `82b0140` (six games for fun, 991 tests). **Rulings log:** `docs/superpowers/notes/2026-11-21-rulings.md`, section "Accepted residuals". **Engine contract:** `docs/superpowers/notes/engine-contract.md` (Addenda 1–7; F1 adds Addendum 8).

## User decisions that shape every sub-stage

- Payment by **both trade and mail**. The addon fills the amount in; the player presses the game's own Trade / Send button. No COD.
- Each table is „Само за удоволствие“ (exactly today's behaviour, byte for byte on the wire except the new `HI.ld` field) or „Със залог“ with an amount in gold and silver.
- Hold'em is PokerStars-style: each player picks its own buy-in between 40 and 100 big blinds in real gold/silver (blinds 10s/25s give 10g–25g). No Limit / Pot Limit and the blind levels as built. Six seats.
- Everything is tested with edge cases: disconnects, forfeits, team debts, split pots, trade and mail detection, forged ledger events, sync conflicts.
- Protocol stays `v=1`, prefix `TAVG`, GUILD + WHISPER only. Bulgarian strings in „…“ quotes, bg/en parity.

## The one rule the whole stage rests on

**A debt counts only once the debtor's own client has confirmed it, and that client confirms automatically only what it saw itself, whole and clean.** Every cheating gap that was accepted for chip play is re-examined against this rule: if the worst a modified host can do is produce a debt that the victim's client contests by itself (visible to the whole guild as „оспорен“, never in a balance), the gap is re-accepted; if it can produce a debt the victim's client would confirm, it must be closed before that game takes stakes. Each sub-stage's residual table below says which.

## Sub-stages (sequential; each one playable and checkable in game on its own)

### F1 — the ledger, sync, payments, stakes for Морски шах and Death Roll

Plan: `docs/superpowers/plans/2026-11-23-stageF1-ledger-payments.md`.

- Append-only guild ledger (`RESULT`, `DEBT`, `CONFIRM`, `PAID`, `DENY`, plus the new `CONTEST`), saved per guild; debts and balances derived from the log only.
- Live broadcast on GUILD, anti-entropy sync by whisper with an explicit traffic budget, forged-event handling (`DENY`), id clashes, crash and reinstall recovery.
- The table option „Със залог“ (`TBL.sk`), explicit acceptance at the chair and in the invitation.
- Forfeit on leave for the two games; the bill („Сметката“); the hall column „Сметки“; the tab „Тефтер“.
- Payment by trade and by mail: prefill, detection, „Уредено“, „Напомни“.
- Probes of the trade and mail API on Forever, and the in-game check list.

Residuals F1 must close or re-accept:

| Residual | Ruling for F1 |
|---|---|
| Stage A P3: an unseen roll is taken as a claim after 3 s | **Closed** on a staked table: only a server roll the host saw (`src = "seen"`) is a roll; the engine refuses any other source. |
| Stage A P4: timeouts and asks are rolled by the host's `env.random` | **Closed** on a staked table: no automatic roll at all. A seat that does not roll for 180 s is stood up (`why = "idle"`) and forfeits. |
| Stage A check-list row 17: a namesake's `/roll` lands on a seated player | **Re-accepted with a contest**: my client knows its own rolls (the adapter passes my own roll under my full name); a recorded roll for my seat that I did not make is the foul `roll`, and my client contests the debt. |
| Stage D residual 1 (F8): in an open game a modified host can move for the guest | **Closed** for Морски шах on a staked table: the forged-move check of the card games runs there too, with the host's timeout allowed only after my own clock ran out. The mechanism is the one F2 reuses for Табла. |
| "When a client is behind by events the moves in between cannot be checked" | **Re-accepted**: a game I did not see whole (a snapshot I asked for, a login) is never confirmed automatically; my client asks me. |
| Stage E residual 1: host-initiated stands are a trusted claim | **Re-accepted with a contest** for the F1 games: a forfeit is confirmed automatically only when I pressed „Стани“ myself, or (idle) my own clock agrees; a stand of my seat while my client is running and I did not ask for it is the foul `stand`. An offline forfeit waits for my own confirmation at my next login, as the spec says. |

### F2 — stakes for Сантасе, Белот and Табла

- Forfeit on leave for the three games; Belot's team debts (the leaver pays both opponents, the partner nothing) and the pairing of losers with winners (two transfers, not four).
- The fairness verdict of every hand feeds the debtor's automatic confirmation: a match with a hand that closed `bad` on my client is contested by my client, one with `unseen` hands is put to me.
- The open-game forged-move check of F1 switched on for Табла; dice verdicts feed the confirmation the same way.

Residuals F2 must close or re-accept (rulings log, "Stage D, Tabla dice" 1–7, and the card-game counts):

| Residual | Expected ruling (to be confirmed in the F2 plan) |
|---|---|
| D1 F8 forged move | Closed by F1's check. |
| D2 F9 host reload re-rolls one throw | Must be **closed or priced**: a kept seed for the opener (`DealKeep` for dice), or the re-rolled throw counts as a foul on the guest's client from the first one on a staked table. |
| D3 a throw made alone is proved only against the opener's commit | Must be **closed**: on a staked table an alone throw the guest's client had sent its part to is a foul from the first one (not „unheard from the second“). |
| D4 the host could look at the guest's seed before publishing | Re-accept: its own commit is out first, it gains nothing. |
| D5 after a `/reload` a client takes an alone proof as it fits | Re-accept under the F1 rule: such a match is `unseen`, never confirmed automatically. |
| D6 a loading screen excuses one throw | Re-accept under the same rule: the match is `unseen` on my client. |
| D7 a watcher's false `dodge` | Re-accept: watchers hold no stake. |
| Stage B/C: a dealer's void, no-deal and seed lapses are only counted | Must be ruled: on a staked table the second void of a dealer in a match forfeits the match for its side (or the count stays a colour; the F2 plan decides with the numbers of the check list). |
| Stage C: nobody acts for an offline Belot player for 180 s | Already the spec's forfeit; F2 only adds the debts. |

### F3 — Hold'em cash

- Buy-in per player between 40 and 100 big blinds (user decision; replaces the spec's table-wide „Вход“), the three rebuy modes of spec 5.5, the pairwise attribution matrix from the `"hand"` event (side pots, split pots), the live panel „Сметка на масата“, the `STAND` settlement event, the automatic stand after three minutes offline.
- Table stakes: a seat with 0 chips sits out until a rebuy; standing up and sitting down again no longer gives a fresh stack.

Residuals F3 must close or re-accept (rulings log, "Stage E" 1–10):

| Residual | Expected ruling (to be confirmed in the F3 plan) |
|---|---|
| E1 host-initiated stands | The F1 rule (contest by the stood seat) plus: a `STAND` settlement needs the stood player's confirmation like a forfeit. |
| E2 hold-then-void, E3 the hold keyed by seat, E4 a provoked seed lapse, E5 early away | Must be **closed or priced**: a void returns every chip (no money moves), so the price is tempo, not gold; the plan must show that no void or away can move chips between players, then re-accept. |
| E6 key withholding | Must be ruled: an `open` (unverified) hand on a staked table makes the settlement of the players in it `unseen` (manual confirmation). |
| E8 key draw (the host reads one live hand per victim per game) | Must be **closed** before gold rides on it (the residual itself names the cure: keys released only against the other participants' signed word that the hand ended), or Hold'em stakes ship with the settlement of that hand contested by the victim's client (it flags the forged end red already). The F3 plan decides; this is the hardest item of the stage. |
| E9 the dealer's stand-void refund; a player vanishing without a key | The refund moves no chips between players: re-accept. A vanished key: as E6. |
| E10 six seats | Kept (user decision). |

### F4 — Класация, История, housekeeping

- The tabs „Класация“ (period × game, the columns and honours of spec 5.6, „Кралят/Кралицата на механата“) and „История“, both computed from the log.
- Which `RESULT` events count (a host-authored result is a claim): the trust rule is decided here.
- Log retention and compaction (spec 9 leaves it to the implementer); F1–F3 never delete an event.
- Polishing found by the F1–F3 check lists.

## Why this split

The suggested three-way split is kept and a fourth stage is added. The spec's own stage 2 bundles ledger, sync, payment **and** leaderboard and history; the last two read the log and write nothing, so they can wait without blocking a single wager, and F1 is already the largest of the four. The order inside F1–F3 follows the cost of a mistake: F1 carries the two games with no hidden information, F2 the games whose fairness layer already gives a verdict per hand, F3 the one game whose residuals include an open protocol hole (E8).

## Where the shared pieces land

| Piece | Lands in | Reused by |
|---|---|---|
| `TBL.sk`, `SIT.sk`, `INV.sk`, `SNO "stake"` | F1 | F2, F3 (blinds and buy-in range ride in `TBL.o` as today) |
| Ledger entries, validation, store, derived debts and balances | F1 | F2, F3 (`STAND`), F4 |
| Live broadcast, anti-entropy sync, `DENY`, twins | F1 | all |
| The always-on extension `stakes`: outcome, forfeit, fouls, automatic confirmation | F1 | F2 (verdict feeds), F3 (settlement) |
| The open-game forged-move check on a staked table | F1 | F2 (Табла) |
| Payment (trade, mail, „Уредено“, „Напомни“), „Сметки“, „Тефтер“, the bill | F1 | F2 (team pairing in the bill), F3 (settlement rows) |
| Team pairing of debts | F2 | — |
| Attribution matrix, `STAND` | F3 | F4 |

## Spec conflicts and rulings (all sub-stages)

1. **Client API.** Spec 3 says Forever runs the modern client (`C_TradeInfo.SetTradeMoney`); the stakes brief treats it as Classic-era-like (`SetTradeMoney`, `GetPlayerTradeMoney`). The stage 1 probe table is still "not yet measured". Ruling: every trade and mail call is feature-detected with both spellings, F1 extends `/tavern probe`, and nothing in the core depends on which one exists.
2. **Who presses Send.** Spec 5.4 lets the addon's own button call `SendMail`. Ruling: the addon only fills the game's own mail and trade frames; the player presses the game's button. This is the anti-goal „мести голд без клик“ read strictly.
3. **Automatic confirmation.** Spec 6.4 has the debtor's client confirm "automatically at the end of the game". Ruling: automatically only when that client saw the game whole and clean (the rule above); otherwise it contests or asks. This adds one event kind the spec does not list, `CONTEST`.
4. **Leaving.** Spec 5.4 forfeits a player "offline or away from the table for 3 minutes"; spec 6.2 and 8 say a timeout is never a loss; today „Стани“ in a two-player game aborts it at once. Ruling: on a staked table „Стани“ forfeits at once (after a warning), offline forfeits after 180 s, a turn timeout still plays the automatic move (except Death Roll, which has no fair automatic roll: 180 s without a roll forfeits).
5. **Sync summary.** Spec 6.4 has every client announce a per-author summary on GUILD at login. Ruling: an 8-character digest rides in `HI`; the per-author vector goes by whisper to one partner at a time (the budget in the F1 plan).
6. **Hold'em.** Spec 5.5 says up to 9 seats and one table-wide „Вход“; spec 8 says No-Limit only. The user decisions (6 seats, own buy-in 40–100 BB, NL/PL) win.
7. **Build order.** Spec 7 puts the ledger in stage 2, before four of the games. The games were built first; nothing else changes.
8. **Mockup 04** shows the mail subject „Krachma: …“ and the mode „Всички към една каса“. The spec already renamed the addon and dropped the mode; the subject is `Tavern Games: …`.
9. **Found while planning (not a spec conflict):** `wow/Adapter.lua` routes saved-variable keys through `CHAR_KEYS`/`GLOBAL_KEYS` and raises on any other key; `bookKeep` and `bookSpent` (written by `core/Book.lua` and `core/BookKeys.lua`) are in neither list. Read from the code, not run in game: in the client those writes raise inside the hooks, so Hold'em's table key is neither kept nor spent. F1 Task 1 adds the keys and a test that every `env.db` key the core writes is declared.
