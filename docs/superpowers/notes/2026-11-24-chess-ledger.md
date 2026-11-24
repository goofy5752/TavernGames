# SDD ledger — plan: docs/superpowers/plans/2026-11-24-chess.md

Spec: docs/superpowers/specs/2026-11-24-chess-design.md (reachable)
Branch: feature/chess (base 5ca12f7). Worktrees: ../tg-chess-N on chess/task-N, merged back into feature/chess.
Ruling: run tasks in parallel waves in separate worktrees, against the skill default of serial — user explicitly asked for this — cost if wrong: merge conflicts, resolved at merge.


## Pre-flight scan

Scope: plan `docs/superpowers/plans/2026-11-24-chess.md`, spec (binding) `docs/superpowers/specs/2026-11-24-chess-design.md`, repo at 5ca12f7. Claims about repo code were checked against the files named. 35 rows: 25 task pairs, 10 single tasks.

### A. Task pairs (shared file or interface)

| # | Tasks | Produced -> consumed | Found |
|---|---|---|---|
| P1 | 1 -> 2 | `R.start/fromFen/copy/moves/find/make/key/status/inCheck/insufficient/bare`, the position fields inline in the state | match. Gap: Task 2's repetition test (`g1f3 g8f6 f3g1 f6g8` twice -> `repetition`) passes only if `E.new` puts the start key in `seen` at count 1, and the plan never says so (only `Chess.at` does) |
| P2 | 1 -> 9 | `R.moves`/`R.make` used by the bot; Task 9 Step 4 may rewrite `R.moves` as make-unmake | **mismatch**: `engines/chess_rules.lua` is not in Task 9's Files, and it is a STRICT-review file |
| P3 | 1 -> 10 | the `if f then` guard in "the chess files keep their limits" | match (Task 10 swaps it for `ok(f, "missing " .. l[1])`) |
| P4 | 1 -> 2,4,5,7,8,9 | the limits table (rules 420, san 140, chess 360, bot 220, Clock 240, StakesChess 220, Model 200, Panels 300, View 420, ChessHistory 120) | match: every task states the same limit |
| P5 | 2 -> 4 | `E.clock`, `E.firstSeat`, `apply(s, seat, a, dt)`, `auto`, `nextFirst`, state `clock base turn moves claimed` | match. `Session.act` (core/Session.lua:471) checks without `dt`, so `dt or 0` covers it; `Lifecycle.startGame` (l.230-231) already calls `nextFirst` when a state exists |
| P6 | 2 -> 5 | `SC.leads` replays `E.new{first = white, opt = {clock = base/600}}` plus every move's `dt` and compares position, clock, taken, seen, half, full, san, result | match, provided the `seen` seeding of P1 is the same on both sides |
| P7 | 2 -> 6 | `E.options`: two `clock` entries, `at = fun` and `at = stake` | match: `Games.resolve`/`offered` (core/Games.lua:56-86) and `optionSet` (ui/NewTableDialog.lua:80) already split by `at`. `metaText` (ui/TableFrame.lua:263) loops over `engine.options`, so it needs the `at` filter the plan adds. Hold'em's ids are unique, so its title text does not change |
| P8 | 2 -> 7 | state fields, actions `move offer accept decline resign`, reason codes | match |
| P9 | 2 -> 8 | `moves[i].san`, `result.winner/reason`, `white` | match |
| P10 | 2 -> 9 | the temporary `E.bot` (Task 2) is removed by Task 9; `chess_bot.lua` loads after `chess.lua` | match |
| P11 | 3 -> 7 | 31 media names -> `Theme.chessTexSize` | names match. **Defect**: both tasks write the same TGA header check (`chess_media_test` and Task 7's "every chess texture the theme names exists") |
| P12 | 3 -> 8 | `media/chess/` line in LICENSE-THIRD-PARTY; the mockup's `HORSE`+`BASE` for the icon | match (`gen_game_icons.parse` handles the `a` arcs in `BASE`) |
| P13 | 4 -> 5 | `Clock.left`, `clockSeen`, `Clock.FLAG_TOL` read by `SC.adopted` ("flag against me while `Clock.left(s, me) > FLAG_TOL` by a clock that saw the turn begin") | **mismatch**: Task 4 runs `Clock.adopted` *before* `s:hook("adopted")`. It re-marks, and for a finished state it clears `clockAt` and `clockSeen` (`mark` clears when not `timed`). So `SC.adopted` always sees `clockSeen` false, and a host can forge a flag through a snapshot |
| P14 | 4 -> 5 | `Clock.claim` -> `Stakes.foul(s, "forged")`, used by "a stand after a failed claim is contested" | match |
| P15 | 4 -> 7 | `Clock.left(s, seat)`, `Clock.canClaim(s)`, `Clock.claim(client)` | match. `seatClock` returns `"none"` and `Model.clockText(nil)` returns ∞; TablePlates maps one to the other |
| P16 | 4 -> 9 | Task 9's bots test checks "time = 6000 - dt + 50 for the `dt` of its entry in `state.moves`" | **mismatch**: only Task 4's `Clock.stamp` produces `dt`, and Task 9 runs in wave C in parallel with Task 4 (Task 9 depends on 1 and 2 only). Without Task 4, `dt` is nil |
| P17 | 4, 6, 9 (wave C) | TavernGames.toc: core section (4) and engines section (9); Task 6 does not touch the toc | match. `core/Clock.lua` loads before `core/Session.lua` and the Stakes files, so it must look up `ns.Session` and `ns.Stakes` at call time, not at the top of the file |
| P18 | 6 -> 5 | `game.chess` („Шах“) in `chess_stake_test` (`L("history.draw", "Шах", …)`) | match through the wave order (6 in C, 5 in D). Task 5's "Depends on" does not list Task 6 |
| P19 | 5, 7 (wave D) | locale (history.mark.* vs chess.*), toc (core vs ui) | match: different regions |
| P20 | 5, 8 (beside each other) | locale (history.mark.* vs chess.history.*/help.chess.*), toc (core vs ui) | match |
| P21 | 6 -> 7 | `game.chess`, `W.optionText`, the dialog keeping `C.TURN_DEFAULT` | match |
| P22 | 6 -> 8 | the help topic `chess` after `holdem` | **mismatch**: `tests/core/locale_help_test.lua:29` pins the topic list `{ "hall", …, "holdem", "fair", … }`. Adding the topic breaks it, and the file is not in Task 8's Files (Task 8 even assumes the test might already cover it) |
| P23 | 7 -> 8 | `ns.ChessModel.san`, `chess.end.*` (with `%s` = winner or loser, derivable from `res.winner`), `ui/Theme.lua` (7: tokens, 8: `GAME_ICONS`) | match (sequential) |
| P24 | 2 -> 4/5 | `E.auto` = `{k="flag"}` on turn, used by the stakes `forged` hook's `blind` test (core/Stakes.lua:288) | match: a flag after a login comes out `unseen` (Review Focus 2) |
| P25 | 8 -> 10 | README test count (8), final count (10) | match |

### B. Each task against itself

| # | Task | Found |
|---|---|---|
| T1 | Rules | Consistent. FENs, square numbers (e5 = 37, d6 = 44, d5 = 36, a7 = 49, a8 = 57) and perft numbers (20/400/8902, 48/2039, 14/191/2812, 6/264, 44/1486) checked. Trivial: the sample test leaves out `local R = ns.ChessRules` and the `describe` wrapper. The toc_test `it` asserts nothing while files are missing (by design until Task 10) |
| T2 | Engine + SAN | SAN fixtures checked (Nbd2, R1a3, Qh4e1, a8=Q+, exd6, Qh4#); clock arithmetic checked (2930, 51, 3050). Gaps: the `seen` seeding (P1); the garbage test calls `same(s, before)`, and the runner (tests/run.lua) has no global `same`, only `eq` and `ok` |
| T3 | Textures | **mismatch**: the plan says to import `flatten_path` and not edit `gen_faction_textures.py`, but `flatten_path` (l.59-125) accepts only full-ellipse arcs (`assert … "only full-ellipse arcs"`) and has no `Q`. The mockup shapes use the quarter arcs `a3 3 0 0 1 3 3` (BASE, every piece), the half arcs `a3 3 0 0 1 0 6` and `a4.5 4.5 0 0 1 9 0`, and `Q` (alliance queen). The script fails on the first piece |
| T4 | Clock | Session +2 lines (`local dt`, armTimers line) -> 527 < 540, OK. **Mismatches**: (a) the tolerance test "104 passes, 106 does not" calls a function the interface does not name; (b) the tests cannot all pass with any `TOL_BASE + TOL_PER*n`. With 0.8 s lag each way, an honest host's own-move sum grows by about 16 tenths per guest move (the round trip; spec: "lag is the player's"), so 20 own moves need b + 20p > 320. "dt+30 caught within 5 moves" needs b + 5p < 150, and the unit test fixes b + p = 105. That gives p > 11.4 and p < 11.25 at once; (c) `Clock.after` says "any other event of that seat" fails a claim, while `Clock.claim` and spec 5.3 say "another move"; (d) host side: the chess line sits inside `if seat then`, so when a game ends `Clock.arm` is never called and `clockKey` is never cleared. If that game ended at 0 moves (white flagged, resigned or agreed before moving), the next game's turn has `#moves == clockKey == 0` and keeps the old `clockAt`: the first move is stamped with the break and refused `"time"`, and the deadline is already past; (e) `flagDue` returns false while an entry of `s.sent` is from this turn, so at a staked table an honest host's flag after a late move (sent in time, arrived after the deadline) is `forged`. Spec 5.3 judges the flag by my clock alone |
| T5 | Stakes | StakesWatch +~5 lines (235 -> ~240 < 260), HistoryTab in place on l.31, LedgerStats ~+6 (< 260): OK. **mismatch**: `Stakes.sent` is called twice for a member's own action, once by `Member.sendAct` (core/Member.lua:220) and once by the stakes `applied` hook (core/Stakes.lua:270). The generic log removes the copy (`sentIn`), but `SC.sent` "appends". The list then holds every move twice, `SC.adopted` reads "a different move at a place I hold", and every honest snapshot is `forged`. Also: `SC.adopted` vs the clock ordering (P13) |
| T6 | Registry/compat | **mismatch**: the old-client namespace (`require("loader").ns()`) loads the same new `locale/*.lua`, so `old.L("game.chess")` is „Шах“, not `"game.chess"`, and `W.gameName` would not give „Непозната игра“. Trivial: `old:sit(tid, 2)` should be the old *client*, not the namespace. Line refs (Hall 179/373, TableFrame 262-272, games_test 31-32, hall_test 152-153) checked |
| T7 | View | **mismatches**: (a) `Sounds.once` keeps the first key of a kind in a scope silently (ui/Sounds.lua:29, `last == nil` -> false). Calling only the winning kind per ply means the first capture, first check and first game end of a table play nothing, so "a capture plays chessCapture…" fails; (b) the selection-clear rule (#moves, white, tid) misses events that end the game without a move (resign, accept). The test "select, then the opponent's event arrives" can only be such an event: an opponent's move cannot arrive on my turn; (c) the UI tests "click e2 …" need me as white, but at a table I host I am seat 1 = black in game 1, so the session must be set by hand. TablePlates 156 + additions < 260 OK |
| T8 | History/help/docs | **mismatches**: (a) the chess game is keyed by `s.gameNo`, but ui/HandHistory.lua:52 says "Never s.gameNo, which every adopted snapshot moves on" (core/Member.lua:144). A snapshot of the same game would start a second entry; (b) the locale_help_test topic list (P22). Defect: "the existing hand_history_test passes untouched" written as an `it` asserts nothing. HandHistory/Panel edits in place (286 < 290, 299) OK |
| T9 | Bot | **mismatches**: (a) `E.bot` returns nil "when seat is not on turn", yet an offer stands only during the offerer's own turn (Task 2: only the seat on turn offers). So `{k="accept"}` cannot be reached, and its test needs an impossible state. `Bots.nextAction` (core/Bots.lua:170) also returns early unless `st.turn == s.mySeat`. Spec 5.9 requires the bot to accept; (b) bots test: at my table the bot is seat 2 = white and moves first, not "after my first move"; (c) P16; (d) P2. Eval is "for the side to move", so it must be negated when the bot is not on turn |
| T10 | Final | Consistent (guard removal, the grep, the media diff, the zip contents) |

### C. Things a code reviewer would flag

- Task 1: the limits test ends in `ok(true)` and checks nothing for files not yet written (accepted until Task 10).
- Tasks 3 and 7 both write the TGA header check for the same 31 files.
- Tasks 4 and 5 each judge "is the flag against me honest by my clock" (`Clock.flagDue` and `SC.adopted`): one rule in two places.
- Task 8: "the other games' histories are unchanged" as a test that asserts nothing.
- Task 2: a temporary random `E.bot` that Task 9 deletes (throwaway code; justified by the bot's `playAuto` fallback).

### D. Conflicts with the Global Constraints or the spec

- Spec 5.3 (claim): a failed claim is "друг ход" (another move) or nothing; Task 4's `Clock.after` says "any other event".
- Spec 5.3 (flag of my seat): honest only "по моя часовник", by my clock alone; Task 4's `flagDue` adds the `s.sent` exception, which charges an honest host under lag.
- Spec 5.3 / Review Focus Q "can an honest host be charged": the tolerance numbers cannot meet both the 0.8 s lag test and the catch tests (T4 b).
- Spec 5.9: the bot accepts a draw when losing; the plan makes that unreachable (T9 a).
- Spec 5.10: an old client shows „Непозната игра“; the planned test cannot show it (T6).
- Spec 5.5: the guest is white in the first game. `Session.startGame` (core/Lifecycle.lua:230) passes `first = lowest` when there is no state, so a host-started first game would give white to seat 1. It only matters if a chess table can reach `startGame` without a state (e.g. after an abort or a successor without a state).
- Spec 5.7 lets the executor edit the shared texture tools if their outputs stay the same; the plan forbids editing them. That is stricter, not a conflict, but together with T3 it leaves no working parser.
- Global Constraints: no breach found. Task 9 Step 4 editing `chess_rules.lua` is a scope problem, not a constraint breach.

### E. Rulings

- P1/T2 seen seeding: Ruling: `E.new` sets `seen = { [R.key(start)] = 1 }`, and `SC.leads` replays from that — FIDE counts the starting position, and Task 2's own repetition test needs it — cost if wrong: the threefold draw comes one cycle late and the replay check disagrees with the host.
- T2 `same`: Ruling: the garbage test uses `eq(s, before)` — the runner has no global `same` — cost if wrong: an error instead of a test.
- P2: Ruling: add `engines/chess_rules.lua` to Task 9's Files as an optional edit that must keep perft green and get a STRICT re-review — the plan already allows the rewrite — cost if wrong: an unreviewed rules change.
- P11: Ruling: Task 7's test only checks that `Theme.chessTexSize` has exactly Task 3's 31 names and sizes; the header check stays in `chess_media_test` — remove the duplicate — cost if wrong: one redundant test.
- P13: Ruling: `Clock.adopted` saves the pre-snapshot clock (`s.clockPrev = { at, key, seen, left }`) before re-marking, and `SC.adopted` judges the flag through one helper `Clock.flagHonest(s, seat, prev)`, the same helper `flagDue` uses — spec 5.4 requires a forged flag in a snapshot to be caught, and this also merges the duplicated rule — cost if wrong: a staked host wins by pushing a flagged snapshot.
- P16 / T9 c: Ruling: Task 9 asserts only that the bot's answer is legal and applies; the `6000 - dt + 50` check moves to Task 4's `chess_table_test`, or Task 9 moves to wave D — `dt` exists only after Task 4 — cost if wrong: Task 9 red in its worktree.
- P17: Ruling: `core/Clock.lua` reaches `ns.Session`, `ns.Stakes` and `ns.Engines` only inside functions — load order — cost if wrong: nil upvalues at runtime.
- P18: Ruling: add Task 6 to Task 5's "Depends on" — it uses „Шах“ — cost if wrong: none while the waves hold.
- P22 / T8 b: Ruling: Task 8 adds `tests/core/locale_help_test.lua` to its Files and puts `"chess"` after `"holdem"` in the pinned list and the title (extend, not loosen) — the suite must stay green — cost if wrong: one red test at merge.
- T3: Ruling: `gen_chess_textures.py` turns fill paths into polygons with `parse` imported from `tools/gen_game_icons.py` (it handles any `A`, `Q`, `C`; the import has no side effects thanks to `__main__`), and uses `flatten_path` only for the open strokes (`sl`, `tl`, which have no arcs). Both shared files stay unedited — the plan's "do not edit" holds and spec 5.7 asks for real arcs and curves — cost if wrong: the script fails on BASE.
- T4 a: Ruling: add `Clock.tolerance(n) -> TOL_BASE + TOL_PER * n` to the interface; the 104/106 test is written as `tolerance(1) - 1` / `+ 1` — the test needs a named function — cost if wrong: the test reaches into locals.
- T4 b: Ruling: the lag test uses 0.4 s each way, and the 0.8 s case goes to the in-game follow-up, keeping b = 100, p = 5 (at 0.4 s: 8 per move, 160 < 200 at 20 moves; dt+30 caught by move 5) — spec 5.3 puts catching theft first (the 40 % argument) and leaves the numbers to a measured test — cost if wrong: an honest host with a round trip over ~1 s is charged in long staked games. The note must say so.
- T4 c: Ruling: only a `move` by the claimed seat, or nothing within `AUTO_GRACE`, fails a claim; `flag` and `resign` end it cleanly — spec 5.3 says "друг ход" — cost if wrong: a host that resigns after a claim is charged.
- T4 d: Ruling: the armTimers line goes before `if seat then` (`if engine.clock then return ns.Clock.arm(self, engine, seat) end`), and `Clock.arm` with no seat clears through `mark` — same line count, and the host clears like members do — cost if wrong: after a game with no moves, the next game's first move is refused and white is flagged at once.
- T4 e: Ruling: in `flagDue`, an entry of `s.sent` from this turn keeps the flag from being honest only if it was sent at least `TOL_BASE` tenths before my own deadline. A move sent at the last second belongs to the player (the lag is his) — spec 5.3: lag counts against the player; the flag is judged by my clock — cost if wrong: an honest host is charged for a last-second move.
- T5: Ruling: `SC.sent` keeps one entry per (ply, kind) (`#state.moves` when sent), so the send and its applied echo are one entry — `Member.sendAct` and the `applied` hook both call `Stakes.sent` — cost if wrong: every honest snapshot is `forged`.
- T6: Ruling: the old client's namespace also deletes the `game.chess`, `opt.chess.*` and `optv.chess.*` keys from its locale tables (an old build has none of them) before the `W.gameName` check, and `sit` is called on the old client — spec 5.10 is about what an old build shows — cost if wrong: the test fails, or tests nothing if loosened.
- T7 a: Ruling: every draw calls `Sounds.once` for all four kinds, each with its own key (move: `tid:#moves`; capture, check: `tid:` the ply of the last capture or check; end: `tid:gameNo:over`), and passes `audible = false` to the losers of check > capture > move — this is the `Sounds.once` contract (first key silent) — cost if wrong: first sounds missing.
- T7 b: Ruling: the selection and the picker are also cleared when `phase`, `turn` or `offer` changes; the test's "opponent's event" is a resign (or decline) on my turn — Review Focus 6 — cost if wrong: a stale picker after the game ends.
- T7 c: Ruling: the click tests set me as white by hand (`Chess.at`, or the second game) — a host is black in game 1 — cost if wrong: the test waits for a bot move.
- T8 a: Ruling: a chess history entry starts when `#moves` goes down (or `white` changes) against the top entry, or the top entry is over and a new game began; never on `gameNo` — ui/HandHistory.lua's rule — cost if wrong: duplicate games after every snapshot.
- T8 defect: Ruling: drop the "passes untouched" `it`; the full suite run is the proof — no test that asserts nothing — cost if wrong: none.
- T9 a: Ruling: `E.bot` checks for a standing offer of the other seat before the turn test, the eval is negated for the side not to move, and `core/Bots.lua` `nextAction` also calls `engine.bot` when `st.offer` is the other seat's (add `core/Bots.lua` to Task 9's Files) — spec 5.9 — cost if wrong: the bot never accepts.
- T9 b: Ruling: the bots test lets the bot (white, seat 2) move first and then checks my reply round — spec 5.5 — cost if wrong: the test waits on the wrong side.
- D (startGame): Ruling: in `Session.startGame`, a `firstSeat` engine with no state sends `start` without `first` (so `newGame` uses `firstSeat`) — spec 5.5 — cost if wrong: in a rare restart, seat 1 gets white in game 1.

## Execution
- Task 1: dispatched (opus) BASE 5ca12f7, worktree ../tg-chess-1 chess/task-1, implementer a2b4ca1792ee27c7a
- Task 3: dispatched (sonnet) BASE 5ca12f7, worktree ../tg-chess-3 chess/task-3, implementer aa84460a7a0ff60b1
- Task 3: complete (commits 5ca12f7..37ac123, review clean, 4 minor noted) — merged into feature/chess
- Task 1: implementer DONE 7b56f15 (perft deep checks ok); strict review dispatched (opus)
- Task 1: complete (commits 5ca12f7..7b56f15, review clean) — merged
- Parked (T1 minor, for T2/T5): epTarget does not check ep rank vs side; a forged snapshot could carry an impossible ep — T2 restore/T5 snapshot check should validate ep rank (side 1 -> rank 6, side -1 -> rank 3)
- Task 2: dispatched (opus) BASE 8b07633, worktree ../tg-chess-2, implementer a2f6256ab05add184
- Task 2: implementer DONE_WITH_CONCERNS f5e9e04 (renamed placeholder id chess->nosuchgame in 4 old tests; restore drops impossible ep); strict review dispatched
- Task 2: complete (commits 8b07633..f5e9e04, review clean, minors noted) — merged
- Parked (T2 review, for T5): a forged snapshot with bad clock/wait/board/side makes apply raise instead of refuse — T5 snapshot check must validate structure (board 64 ints in -6..6, side ±1, clock nil or two non-neg ints, etc.) before adopting
- Wave C dispatched, BASE ec075a2: Task 4 (opus, ../tg-chess-4, aa06bbbc8d456c4b0), Task 6 (sonnet, ../tg-chess-6, a1e9d7cd0dcbb55d8), Task 9 (sonnet, ../tg-chess-9, a5fbb1ca7ba19cfb2)
- Task 6: implementer DONE_WITH_CONCERNS 894f8ad (controller verified full suite 2292/0); icons_test skips chess until T8 — T8 must remove skip and change sibling test id
- Task 9: implementer DONE 367d061 (BOT_NODES 3000, ~41ms joff); core/Bots.lua acts on standing offer
- Task 6: review 1 needs fixes (compat tests: seating-SNP STD branch untested, ledger check vacuous; goto in icons_test) — fix round 1 sent (review head 894f8ad)
- Task 9: review 1 needs fixes (unbounded capture search; unsearched root fallback) — fix round 1 sent (review head 367d061)
- Task 9: minor (deferred): capture search stands pat in check (comment requested)
- Task 6: fix round 1/5 (4 addressed, 0 open; commits 894f8ad..a01282d)
- Task 6: complete (commits ec075a2..a01282d, review clean after 1 round) — merged
- Task 9: fix round 1/5 (3 addressed, 0 open; commits 367d061..c1be195)
- Task 9: minor (deferred): static fallback (cap hit in first root move) ignores mate/stalemate — unreachable at cap 3000
- Task 9: complete (commits ec075a2..c1be195, review clean after 1 round) — merged
- Task 4: implementer DONE b3d4626 (Clock.lua 235/<240; Session 527); review dispatched
- Task 4: review 1 needs fixes (1 Critical, 2 Important, 4 Minor)
- Ruling (T4 C1): credit each own move in the audit with my measured round trip (echo arrival − sentAt), capped at 10 tenths per move; extend lag test to 40+ own moves at 0.4 s each way and keep "dt+30 caught by move 5" — spec 5.3 says an honest host must not be charged — cost if wrong: a host may hide up to 1 s/move by slowing echoes
- Ruling (T4 I1): an unseen turn still runs the time check; "gone by my clock" is honest, "not gone" on an unseen turn is unseen, not forged — a late start only adds time — cost if wrong: none known
- Ruling (T4 I2): Task 5 owns auditing my own moves delivered inside a snapshot (dt vs my sentAt/clockPrev) in StakesChess; Task 4 exposes what it needs from Clock (sum update helper); Clock.lua's own new-file limit may rise to < 280 — Clock.lua is new in this plan, the no-raise rule is for pre-existing files — cost if wrong: a snapshot-forcing host could bypass the audit until T5
- Ruling (T4 m3): silence after a due claim is forged only if the host is still online by my presence view; if it is offline, no foul — the existing offline stand/succession path makes it lose by `left` — spec intent: a cheat is disputed, a disconnect loses — cost if wrong: a silent-but-online host is still disputed (as spec)
- Task 4: minor (deferred): a same-turn adopt after a host change keeps counting (rare, 2 seats)
- Ruling: Task 7 started early on feature/chess + chess/task-4 pre-fix (9c9ca9d) — it consumes only Clock.left/canClaim/claim, stable across the T4 fix round — cost if wrong: re-merge of T4 fixes into T7 before review
- Task 7: dispatched (sonnet) BASE 9c9ca9d, ../tg-chess-7, implementer af7c8b60a659c9108
- Task 4: fix round 1 sent (review head b3d4626)
- Task 4: fix round 1/5 (6 addressed, 0 open; commits b3d4626..fe94587)
- Task 4: complete (commits ec075a2..fe94587, review clean after 1 round) — merged
- Task 5: dispatched (opus) BASE 5ce8bda, ../tg-chess-5, implementer a7020d1204b771371
- Task 7: implementer DONE_WITH_CONCERNS c8a82db (table 780x660; no real-client run; theme_test token list extended)
- Task 7: review 1 Approved (0 C/I, 7 minor). Controller chose to fix minors 1,2,3,5 now (user-visible) — polish round sent; minors 4,6,7 deferred:
  - Task 7: minor (deferred): ChessModel guards s.engine~=nil for test fakes
  - Task 7: minor (deferred): tests check picker parent not position; media names count not list
  - Task 7: minor (deferred): chessEnd sound key tid:over:#moves:white instead of ruled tid:gameNo:over (documented, equivalent)
- Task 7: polish round (4 addressed, 0 open; commits 9e0bb16..72a09b1)
- Task 7: complete (commits 9c9ca9d..72a09b1, review clean) — merged
- Task 8: dispatched (sonnet) BASE b58edd9, ../tg-chess-8, implementer ac3e226a717db0832
- Task 8: implementer DONE_WITH_CONCERNS 02d42be (HelpBook height 520->540 for 14th topic)
- Task 8: review 1 needs fixes (README bot-opponent claim; minors: FIDE wording, checked-games line, history 0-move clause, ep wording, header comment) — fix round 1 sent (head 02d42be)
- Task 5: implementer DONE_WITH_CONCERNS 0a93cf3 (edited core/Member.lua +10 to drop forged chess SNP before Clock crash; wow/Adapter.lua db key stakeChess)
- Task 8: fix round 1/5 (6 addressed, 0 open; commits 02d42be..2d04198)
- Task 8: minor (deferred): ChessHistory may add an empty entry if a transitional non-over state follows a finished game
- Task 8: complete (commits b58edd9..2d04198, review clean after 1 round) — merged; README count must be refreshed in T10 after T5 merge
- Task 5: complete (commits 5ce8bda..0a93cf3, review Approved, 8 minor) — merged
- Task 5: Ruling (m1): login leniency also covers resign/agreed/offer/claim missing from my log → "unseen", not "forged" — WoW cannot tell a crash from a /reload; "unseen" still puts any claim to me, nothing auto-paid — cost if wrong: a forged resign at my login is only "unseen"
- Task 5: Ruling (m2): history rewrite before my saved point at login → "unseen" (documented) — same reason
- Task 5: minor (deferred): db.stakeChess ~1.4 KB per 40-move game vs spec "< 1 KB" (fold ply into word)
- Task 5: minor (deferred): a staked snapshot replays the game 3-5x (~45 ms hitch on 200 plies) — cache last validated state
- Task 5: minor (deferred): SC.valid refuses unknown chess state fields — add a pointer comment at E.new
- Task 5: minor (deferred): WAIT duplicated (export E.WAIT)
- Task 5: minor (deferred): LedgerStats empty w/l → "drawn" is generic; no non-chess test
- Task 5: minor (deferred): a broken SNP from a successor/at login dropped without a foul (no money effect)
- All tasks 1-9 merged into feature/chess (4ef1056, 2399 passing). Final whole-branch review dispatched (fable), agent a8b7134b7abc5a79a
- Final review (fable): ready for in-game test; 3 Important (staked host drops my last-seconds move then flags unjudged — Clock.lua:144 TOL_BASE window; claim button never appears by itself — refresh from seatClock; claim race charges honest host), 5 Minor
- Ruling (final I3): revises T4 m3/claim: a claim may be sent only after my clock has shown 0 for FLAG_TOL + RTT_MAX, and a move arriving within that window after my zero does not fail the claim — closes the honest-host race — cost if wrong: claims appear ~2 s later
- Final fix wave dispatched (opus) in ../tg-chess-10 on chess/task-10, BASE 4ef1056: I1, I2, I3, m4 (flag zeroes loser clock), m5 (picker OnHide), m6 (LedgerStats drawn rule test / gate), Task 10 steps 1-2 (guard, spec walk, README count)
- Final review: minor (deferred): TablePlates seatClock string.format twice per frame
- Final fix wave: re-review all 7 addressed, 0 open (commits 4ef1056..d23200f) — merged
