# Tavern Games: roadmap for the remaining five games (stages A–E)

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md`. **Base:** branch `feature/games` on top of `feature/stage1` (platform + Морски шах, 227 tests).

**User decisions that shape every stage**
- All five games are **play-for-fun only**: no wagers, no ledger, no payments, no leaderboard. `stake` stays `nil`. Each finished game is announced as the client event `"result"` (introduced in A) so a later ledger can subscribe without touching the games.
- Every game is playable **solo with `/tavern bots`** and with real guildmates.
- Turn timeout = an automatic legal move, never an automatic loss.
- Each stage ships its rules-book topic (bg + en, tavern-talk examples) and an in-game check list.
- Protocol stays `v=1`, prefix `TAVG`, GUILD + WHISPER only, point-to-point types WHISPER-only.

Each stage gets its own detailed plan (`docs/superpowers/plans/2026-11-20-stage<X>-….md`), written when the previous stage is done, so it can use what the in-game checks found.

## Where the shared pieces land

| Piece | Lands in | Reused by |
|---|---|---|
| Game registry (`core/Games.lua`), per-game table options (`TBL.o`) | A | B, C, D, E |
| N seats (2..9): hall chairs, table plates, seating, succession, bots | A | C (4), E (9) |
| Host-started games, joining mid-game for the next one, `Engine.leave` | A | E (between-hands join/stand) |
| `"result"` client event, `Engine.result` | A | all; the later ledger |
| Session extensions (`ns.Ext`: `act`, `applied`, `auto` hooks) | A (`rolls`, `party`) | B (`fair`), D (`dice`) |
| `env.random(lo, hi)` | A | B, C, D, E (seeds) |
| `Session.lua` / `Hall.lua` split | A | all |
| SHA-256 (pure Lua, own code, NIST vectors) | B | C, D, E |
| Commit-reveal (`core/Fair.lua`), deterministic shuffle (`core/Deck.lua`) | B | C, E; D (dice variant) |
| Private per-seat data: `Engine.view(state, seat)`, per-recipient `SNP`, private deal whispers | B | C, E |
| Card textures (`tools/gen_textures.py`), card-hand widget (`ui/Cards.lua`) | B | C, E |
| Team seats (partners opposite, team score, team result) | C | later stakes |
| Dice by commit-reveal, board widget with legal-move highlights, staged move (`Върни`/`Готово`) | D | — |
| Seats that sit out, chips, per-hand result with contributions | E | later ledger (pairwise attribution) |

## Stage A — shared core generalization + Death Roll

- **Deliverable:** Death Roll for 2–6 players at one table, numbers from the real server `/roll`; the hall, new-table dialog, table frame, bots and rules book driven by the game registry instead of hard-coded Морски шах. Detailed plan: `docs/superpowers/plans/2026-11-20-stageA-core-deathroll.md`.
- **Introduces:** everything marked A above; `/roll` capture (`CHAT_MSG_SYSTEM` + localized `RANDOM_ROLL_RESULT`); the roll trust model (host sees the roll; a roll the host cannot see is taken as the roller's claim and shown with „?“; every client marks what it saw itself); automatic group invite by the host and auto-accept by the seated player.
- **Risks:** whether the roll line names players by first name, full name or with a realm (unmeasured: the stage 1 probe file is still empty); whether `RandomRoll`, `C_PartyInfo.InviteUnit`, `AcceptGroup` may be called from addon code on Forever (the wiki lists no protection; `RandomRoll`/`InviteUnit` carry `AllowedWhenUntainted`); invites to a full name with a space. The design degrades: typing `/roll N` by hand works, a blocked invite leaves a hint line, an unseen roll is still played.
- **Testable in game:** solo — open Death Roll, invite two bots, „Започни“, press „Хвърли“ (a real `/roll` line appears in chat), bots' rolls tagged „маса“. Two clients — auto group, identical ladders, no „?“.

## Stage B — card fairness + Сантасе

- **Deliverable:** Сантасе for two (24 cards 9–A, 66, 20/40, swap the nine, closing, game points 3/2/1, to 11) on a fair deal.
- **Introduces:** SHA-256; `core/Fair.lua` (every player commits `SHA256(seed)`, seeds go to the dealer, deck = Fisher–Yates over a SHA-256 stream of `seed_1‖…‖seed_n‖handId`, seeds published after the hand, every client re-checks deck and played cards and marks the hand „проверена“ / „нередовна“); private hands (the dealer whispers each player only its cards; `Engine.view` so snapshots and watchers never carry a hidden card); dealer rotation; "dealer left mid-hand → hand void, redeal"; card art and `ui/Cards.lua` (fan, legal cards raised, illegal dimmed); rules topics „Сантасе“ and „Защо раздаването е честно“.
- **New wire types (to be fixed in the B plan):** commit, seed-to-dealer, private deal, reveal.
- **Risks:** this is the one stage that changes the session model — today every client applies every event on the full state; with hidden cards a client validates only what it can see and verifies the rest at reveal. Reconnect mid-hand needs the dealer (not the host) to resend the private hand. Pure-arithmetic SHA-256 speed in Lua 5.1 (no `bit` in `core/`). Santase closing/last-trick/marriage edge rules need a pinned rule table in the plan.
- **Testable in game:** solo vs one bot (bots are full clients, so they commit, reveal and verify like players); `/tavern debug` shows that no message to a watcher or to the opponent carries my hand; after each hand the frame shows „проверена“. Two clients: a modified dealer deck is flagged „нередовна“ (simulated in tests).

## Stage C — Белот

- **Deliverable:** Belot for four in two teams to 151, rules ported from NikolayIT/BelotGameEngine (MIT; only `src/Belot.Engine/`, nothing from `etc/Other implementations`).
- **Introduces:** team seats (1+3 vs 2+4; partner plate opposite, team score, team result in `"result"`); bidding and contra/recontra UI; announcement bubbles; four-seed fairness (reuse of B with n = 4); parity fixtures: a small C# console under `tools/belot-parity/` drives the original engine with fixed decks and scripted players and writes Lua fixtures; the Lua engine must reproduce every bid, trick and score.
- **Risks:** needs a .NET SDK on the dev machine (user OK required) and the C# engine may not accept an injected deck without a shim (MIT allows one, kept out of the addon); the largest rule surface of the five; long games (many hands) make mid-hand reconnect and "a player is offline for 3 minutes in a team game" matter. Attribution text in `LICENSE-THIRD-PARTY.md`.
- **Testable in game:** solo with three bots (bots play `Engine.auto`: pass / lowest legal card); four real players for the acceptance run; fixtures run in `bash t.sh`.

## Stage D — Табла

- **Deliverable:** Обикновена → Тапа → Гюлбара in a cycle, match to 5 points, mars = 2, no doubling cube.
- **Introduces:** dice by commit-reveal between the two players (both commit, both reveal at once, dice = `SHA256(seed_a‖seed_b‖rollId)`; reuses `Fair`'s primitives, nothing hidden so the reveal is immediate); one move generator with three rule tables; board widget (24 points, bar, bearing off, glowing legal targets); staged move with „Върни“/„Готово“ sent as one action; auto-move = first legal full move.
- **Risks:** legal-move generation (both dice when possible, the larger die when only one, doubles; Тапа pinning; Гюлбара's cascading doubles) — the variant rules must be pinned with the user before the plan; two message round trips per roll; an opponent who goes silent between commit and reveal (resolved by the host's turn timer: new roll id).
- **Testable in game:** solo vs a bot through all three variants; two clients from different zones (no `/roll`, no group needed).

## Stage E — Тексас Холдем

- **Deliverable:** No-Limit Hold'em, 2–9 players, chips only (a fixed starting stack and blinds chosen at open time; no buy-in money, no rebuy money, no pairwise ledger).
- **Introduces:** oval table with nine view-placed seats; sit and stand between hands (the A mechanism: a newcomer joins the next hand, a leaver's hand is folded); betting rounds, side pots, split pots; hand evaluator; rotating dealer with n-player fairness from B; **seeds revealed at table close** for all hands at once (a player who stands early hands its seeds to the host); the per-hand `"result"` carries who put how much into each pot, so the later ledger can do pairwise attribution without engine changes.
- **Risks:** message volume (every event is up to 8 whispers; needs a check against ChatThrottleLib with 9 seats); dealer or host leaving mid-hand with money in the pot (hand void, bets returned); all-in/side-pot arithmetic; showdown reveal without leaking folded hands; reconnect with a private hand.
- **Testable in game:** solo with up to eight bots (bots check/call/fold by `Engine.auto` plus a little randomness); two or three real clients for join/stand between hands and the close-time verification.

## Order, and what could change it

1. **Run the stage 1 two-client acceptance and `/tavern probe` during stage A, not after it.** Name format and instance behaviour are still unmeasured and Death Roll leans on both (roll-line names, invite by full name).
2. **B is the riskiest infrastructure.** If its plan turns out larger than one stage, split it: B1 = SHA-256 + commit-reveal + shuffle + private data with a throwaway "high card" engine, B2 = Сантасе + cards UI.
3. **D does not depend on C.** If the Belot parity tooling (C# toolchain, deck injection) stalls, swap C and D; the user's order is kept otherwise.
4. The parity fixtures for C can be generated any time after B's deck format is fixed; starting them early removes C's main schedule risk.
5. Deferred from stage 1 and still open after A: the table frame cannot be minimised (final review M5); watcher cannot take a freed chair without leaving (M6); `Names.normalize` hyphen rule (M8) — decide after the probe.
