# Tavern Games Stage C (Белот) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Four guild members (or one member and three bots) play Белот in two teams, seats 1+3 against 2+4 with the partner opposite, to 151 on the stage B fair deal with four seeds: auction with контра and реконтра, announces shown as bubbles at the players, a trick area for four, the team score, a look at the last trick, a team result in the `"result"` event, and „Нова игра“ after the match.

**Architecture:** Belot runs on stage B's messages unchanged: the engine joins the fair contract (`full`, `void`, `ext = {"fair"}`, `again`) and `core/Deal.lua` deals it like Сантасе, five cards before the auction and three after it (the dealer's `Deal.sync` whispers whatever a seat's view gained). Three things are new in the core, all small: the engine may name the dealer (`E.dealer`), so the seat that holds the deck is the seat that deals by Belot custom; a bot asks the engine for a bot move (`E.bot`) before the timeout move (`E.auto`); and the `"result"` event names who left. The UI is a ring of four plates around the felt (`HallLayout.ring`, a view with `ring = true`), a pure model (`ui/games/BelotModel.lua`) and the view that draws it (`ui/games/BelotView.lua`). The plan has two halves: **C1** (Tasks 1–5) makes Belot playable and proven in the simulator without UI; **C2** (Tasks 6–10) adds the table, the rules-book topic and the in-game check list.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), the stage 1 Ace3 subset, `bash t.sh`, `tests/helpers/sim.lua`, `tests/helpers/wow.lua`. No new texture, no .NET run (the parity fixtures are only replayed).

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.3 Белот, 5.3а, 5.4 for the forfeit idea, 6.2, 6.3, 6.5). Roadmap: `docs/superpowers/plans/2026-11-20-games-roadmap.md` (Stage C). Stage B plan (format, contracts, the end state this plan builds on): `docs/superpowers/plans/2026-11-21-stageB-fairness-santase.md`. Engine contract: `docs/superpowers/notes/engine-contract.md` (Addendum 4 is stage C). Rulings B1–B4 and PB1–PB8: `docs/superpowers/notes/2026-11-21-rulings.md` (the `.superpowers/` progress files are not committed). Card style: mockup `docs/mockups/07-wow-authentic.html`, variant 1, as already built in `ui/Cards.lua`.

**Stage C starts on `feature/games` after `feature/stageB` (Tasks 1–13 and its final fix wave) is merged.** Line numbers quoted below are from stageB `2dc5951` and may have moved; names are binding. It consumes from B: `ns.Ext.fair` / `ns.Deal` (`Deal.status`, `Deal.missing`, `Deal.handOver`), `ns.Fair`, sessions on views (`Session:snapshotFor`, `Session:armAuto`, `Session:gameOver`, `Session.startable`), `engine.again` / `engine.nextFirst`, `ns.Cards`, `v.fairLine`, `v.startButton`, the `cards` help block, `Games.PLAYABLE`.

## Global Constraints

Everything in the stage 1, stage A and stage B constraint files still holds (`.superpowers/sdd/2026-11-21-stageB-fairness-santase/global-constraints.md` and the two it names). Added for stage C:

- Protocol stays `v=1`. Stage C adds **no message type and no field**. Belot's own action shapes travel inside `ACT`/`EV` (table below).
- Belot's rules are the rule table at the top of `engines/belot.lua`; stage C changes no rule of the auction, the tricks, the announces or the score. `bash t.sh tests/engines/belot_test.lua` keeps replaying all 60 fixture matches of `tests/fixtures/belot/`; the fixtures and `tools/belot-parity/` are not touched.
- Teams: team 1 = seats 1+3, team 2 = seats 2+4. `"result"`: `winners = {w, w + 2}`, `losers = {3 − w, 5 − w}` (seats); `losers[k]` is paired with `winners[k]`.
- Dealer: an engine with `E.dealer(state)` names the dealer of the next round itself; Belot: `(state.first + 2) % 4 + 1`, the seat before the one that bids first (first match: seat 4, then 1, 2, 3, …; a passed-out deal and a void move it on; the no-deal reopen applies no void, so the same dealer deals it). Engines without `E.dealer` keep B's formula `p[(n + 1) % #p + 1]`. PC1 amends PB8 for Belot: the deal keeps rotating across matches (`E.nextFirst = prev.first % 4 + 1`), the previous loser does not lead the next match.
- `core/Deal.lua` is split first (Task 0): the `ns.Ext.fair` hooks live in `core/DealHooks.lua`, which reaches Deal's private helpers only through `Deal.int`. New code goes into new files; neither file grows toward the old 962 lines.
- Timeout = the automatic move of the player's **own** client (the host's clock only for the host's own seat, as in B): in the auction a pass; in the tricks first every announce held, then the lowest legal card. Nobody passes or plays for an offline player: after `OFFLINE_STAND_SECONDS = 180` he is stood up, the match ends and his team loses (no money, no ledger).
- Bots: `E.BOT_BID = 34`, `E.BOT_LUCK = 6`; a bot bids suits only (never Без коз, Всичко коз, контра or реконтра); the fourth to speak never passes a deal out.
- The face rule of stage B is unchanged. A bubble, a plate note or the model shows an announce by its kind only, never a face my view lacks.
- `core/Session.lua` is **not edited** (539 lines; the limit is below 540). `ui/Hall.lua` stays below 580. `ui/TableFrame.lua` gets only the ring hook and the waiting line.
- Felt 532 × 328 px. Ring plates 165 wide at `(183.5, −276)` bottom, `(357, −105)` right, `(183.5, −10)` top, `(10, −105)` left; my seat (a watcher: seat 1) is at the bottom, the next seat in turn order on the right.
- Cards are `ui/Cards.lua` as it is (40×58, step 28, raised 8, dimmed 0.55). `tools/gen_textures.py` and `media/` are not touched.
- Commits are local only, never pushed; every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A partner's or an opponent's face reaches somebody who may not see it** (an `SNP` to a newcomer, an `EV`, a `PRV`, a bubble, the model). Pinned by Task 3 (`no message to another seat or a watcher carries a face it may not see, through a whole deal`, `a snapshot mid-deal shows a newcomer the played cards and only its own hand`) and Task 7 (`the model holds no face outside my hand and the cards on the table`).
2. **An announce is shown that the engine did not count.** Pinned by Task 7 (`bubbles are the engine's record: bids, announces of the first two tricks, a belote on the table`, `the summary names an announce that lost as not counted`) and Task 8 (`„Обяви“ sends the engine's set and shows no bubble until the table recorded it`).
3. **A player leaves or goes offline mid-deal in a four-player game.** Pinned by Task 4 (`a player stands mid-deal: the match ends, his team loses, the result names the leaver`, `a player offline for three minutes is stood up and his team loses`).
4. **The auction stalls when everyone times out.** Pinned by Task 3 (`nobody bids: four automatic passes, the deal is passed out, the next seat deals`) and Task 2 (`bots alone never pass a deal out and every match ends`).
5. **The team result is wrong after контра or вътре.** Pinned by Task 4 (`вътре and контра score the same on every client`) and Task 7 (`the summary says who is вътре, the doubling and each side's points`).

Also pinned: the fair dealer is the Belot dealer and a host naming another is refused (Task 3), a dealer's reload voids the deal (Task 4), a player who relogs after an announce can still score the deal (Tasks 1 and 4), an all-bot table fills and finishes (Task 5).

---

## File Structure

```
engines/belot.lua            fair contract, void, dealer, nextFirst, view keeps played cards (Task 1); announce, auto, bot (Task 2)
core/Deal.lua                the dealer of a round: E.dealer first, else the formula (dealerFor); shrinks in Task 0
core/DealHooks.lua           NEW (Task 0): the ns.Ext.fair hooks, wellFormed, fits, agrees moved out of Deal.lua; `fits` follows dealerFor (Task 3)
core/Games.lua               PLAYABLE.belot
core/Lifecycle.lua           "result" gains left and names
core/Member.lua              Member.adopt keeps seatedBefore (Task 4)
core/Bots.lua                E.bot before playAuto; a bot host fills its table with bots
core/HallLayout.lua          + HallLayout.ring
core/Help.lua                topic "belot"
ui/TableFrame.lua            ring views; „Чакаме още играчи…“ for a table of more than two
ui/games/BelotModel.lua      NEW ns.BelotModel (pure)
ui/games/BelotView.lua       NEW
locale/bg.lua  locale/en.lua
tests/engines/belot_test.lua
tests/core/belot_table_test.lua   NEW
tests/core/{games,member,bots,hall_layout,locale_help}_test.lua
tests/ui/{hall,table,book}_test.lua, tests/ui/{belot_model,belot}_test.lua NEW, tests/wow/slash_test.lua
docs/superpowers/notes/2026-11-stageC-ingame-checks.md  NEW
```

TOC: `core/DealHooks.lua` right after `core/Deal.lua` (Task 0); `ui/games/BelotModel.lua`, then `ui/games/BelotView.lua`, after `ui/games/SantaseView.lua`.

### Shared contracts (additions to stages 1, A and B)

**Engine, optional:** `E.dealer(state) -> seat` (who deals the next round; public data only); `E.bot(state, seat, random) -> action | nil` (a bot's move for the seat on turn, from its view; nil = use `E.auto`); `E.announce(state, seat) -> {k="ann", a} | nil` (Belot: everything the seat on turn may still announce).

**Protocol additions:** none. For the reader of `/tavern debug`, the Belot shapes inside `ACT`/`EV`:

| where | shape | meaning |
|---|---|---|
| `ACT` → `EV` seat 1–4 | `{k="bid", b}` | `b` = `P C D H S N A X R` |
| `ACT` → `EV` seat 1–4 | `{k="ann", a={{t, i}, …}}` | `t` = `s3…s8 c c9 cJ`, `i` = deck index of the top card (ruling B3) |
| `ACT` → `EV` seat 1–4 | `{k="play", i, c, b}` | `b = true`: with a belote |
| `EV` seat 0 | `{k="score"}`, `{k="void"}` | the host after the eighth trick; a deal annulled (stage B rule 21) |

**Client event changed:** `"result"` also carries `left` (the seat whose leaving ended the game, or nil) and `names` (seat → name or `false`, as seated before the event that ended it).

**Test conventions:** as in stage B. Names `A, B, C, D, W = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров", "Гледач Гледачев"`, clients `a, b, c, d, w`. `SEED = ("ff"):rep(16)`. `deckOf`, `DECK1` and `DECK_A` are the ones at the top of `tests/engines/belot_test.lua`; a test file outside it copies them verbatim. In `DECK_A` seat `q` holds deck indices `q, q+4, …, q+16` and `q+20, q+24, q+28`: seat 1 `AH KH 7H 8C JS | 9S 7D 8D`, seat 2 `TH QH 9H 7C QS | KS AD TD`, seat 3 `JH 8H 9C TC 7S | 8S JD QD`, seat 4 `AC KC QC JC AS | TS KD 9D`. Every commit step's message is followed by the trailer line of the Global Constraints.

---

# Part C1 — Belot at the table, proven in the simulator

### Task 0: Split core/Deal.lua (no behaviour change)

**Files:**
- Create: `core/DealHooks.lua`; Modify: `core/Deal.lua`, `TavernGames.toc`

**Interfaces:**
- Consumes: stage B's `core/Deal.lua` (962 lines at `6736b40`).
- Produces:
  - `core/DealHooks.lua`: the `ns.Ext.fair` hook table plus `wellFormed`, `fits`, `agrees` (today's lines 604–914 of `core/Deal.lua`), moved verbatim. It starts with `local Deal = ns.Deal; local int = Deal.int` and local aliases of what it uses.
  - `Deal.int`: one table exporting the file-locals the moved code uses: `isInt`, `STAGES`, `PRIVATE`, `foul`, `sawCommit`, `commitFits`, `participantsFit`, `revealFits`, `dealerOf`, `armWait`, `stopWait`, `revise`, `seedsIn`, `takeOver`. Its comment says: private to `core/Deal.lua` and `core/DealHooks.lua`, nothing else reads it. `Deal.status`, `Deal.missing`, `Deal.handOver`, `Deal.open` stay public in `Deal.lua`.
  - `TavernGames.toc`: `core/DealHooks.lua` on the line after `core/Deal.lua`. Any test helper that lists files by hand gets it in the same place.
  - Both header comments say what lives where. No behaviour changes; `ns.Ext.fair` is assigned at load exactly as before (tests that swap `ns.Ext.fair = REAL` keep working).

- [ ] **Step 1: Run `bash t.sh`.** Record `N passed, 0 failed`.
- [ ] **Step 2: Move** the hooks and the three checks into `core/DealHooks.lua`, export the helpers through `Deal.int`, add the TOC line, update both header comments. Change nothing else.
- [ ] **Step 3: Run `bash t.sh`.** Expected: the same `N passed, 0 failed`. `wc -l core/Deal.lua core/DealHooks.lua`: each well under 962 (about 600 and about 350).
- [ ] **Step 4: Commit.** `git add core/Deal.lua core/DealHooks.lua TavernGames.toc` — `refactor(core): the fair hooks move from Deal.lua into DealHooks.lua`, trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

### Task 1: The Belot engine joins the fair contract

**Files:**
- Modify: `engines/belot.lua`, `tests/engines/belot_test.lua`

**Interfaces:**
- Consumes: the fair-engine contract of stage B („Engines that list the extension `fair`“).
- Produces:
  - `E.ext = {"fair"}`, `E.again = true`. `E.new` sets `full = true`; `E.view` sets `full = false` on every copy it returns.
  - `{k="deal"}` at seat 0: on a state with `full == true` the deck must hold all 32 faces at indices 1..32 (`"deck"`); on a view any subset or none (as today).
  - `{k="void"}` at seat 0 (another seat: `"seat"`) in phase `"bid"`, `"play"` or `"score"` (else `"phase"`): phase `"deal"`, `turn` nil, `deck = {}`, `hands` four empty lists, `bids = {}`, `contract` nil, `passes = 0`, `open = false`, the play fields as `resetPlay` leaves them; `first = first % 4 + 1` (as a passed-out deal does, so the next seat bids first and `E.dealer` names the next seat: PB6b, engine-contract Addendum 3); `res = nil` (the hanging points live in `s.hang`); `round`, `score`, `hang` untouched.
  - `E.dealer(s) = (s.first + 2) % 4 + 1`. `E.nextFirst(prev, occupied) = prev.first % 4 + 1` when that seat is occupied, else nil (the deal keeps going round into the next match).
  - `E.view(s, seat)`: besides the seat's own hand, in phase `"play"` every deck index that is in no hand (the cards played in this deal; this replaces „the current trick and the last taken trick“). A view of the auction still shows only the own five cards. Reason: `{k="score"}` needs the face of every announce's card, and a client that came by snapshot mid-deal would otherwise be refused (`"show"`) and resync; a host in that position would stall.
  - Header: rule 3 gains „the dealer is the seat before `first`“; „STATE AND ACTIONS“ states the view rule, `full`, `void`, `E.again`/`E.nextFirst`.

- [ ] **Step 1: Write the failing tests** (new `it`s in `describe("belot core")` / `("belot views")`).

```lua
it("declares the fair contract", function()
  eq(E.ext, { "fair" }); eq(E.again, true)
  local s = E.new {}; eq(s.full, true); eq(E.view(s, 1).full, false)
  eq({ E.apply(s, 0, { k = "deal" }) }, { nil, "deck" })
  local short = { unpack(DECK1) }; short[32] = nil
  eq({ E.apply(s, 0, { k = "deal", deck = short }) }, { nil, "deck" })
  local v = E.view(s, 3); ok(E.apply(v, 0, { k = "deal", deck = { [3] = "7H" } })); eq(v.deck, { [3] = "7H" })
end)
it("the dealer sits before the seat that bids first and moves on every deal", function()
  local s = E.new { first = 1 }; eq(E.dealer(s), 4); deal(s); bids(s, "P P P P"); eq(s.first, 2); eq(E.dealer(s), 1)
  eq(E.dealer(E.new { first = 3 }), 2); eq(E.dealer(E.new { first = 4 }), 3)
  eq(E.nextFirst({ first = 4 }, { true, true, true, true }), 1); eq(E.nextFirst({ first = 2 }, { true, true, false, true }), nil)
end)
it("void annuls the running deal; the next seat bids first and deals, and no point moves", function()
  local s = started(DECK_A, "S P P P"); plays(s, "AH 9H 8H TS AC")
  s.score, s.hang, s.res = { 30, 12 }, 4, { round = 0 }
  ok(E.apply(s, 0, { k = "void" }))
  eq({ s.phase, s.round, s.first, s.passes, s.open }, { "deal", 1, 2, 0, false }); eq(s.turn, nil); eq(s.contract, nil); eq(s.res, nil); eq(E.dealer(s), 1)
  eq(s.deck, {}); eq(s.hands, { {}, {}, {}, {} }); eq(s.bids, {}); eq(s.ann, {}); eq(s.pts, { 0, 0 }); eq(s.score, { 30, 12 }); eq(s.hang, 4)
  eq({ E.system(s) }, { { k = "deal", need = "deck" }, 0 }); deal(s, DECK_A); eq(s.turn, 2)
  eq({ E.apply(E.new {}, 0, { k = "void" }) }, { nil, "phase" }); eq({ E.apply(started(DECK_A, "S"), 2, { k = "void" }) }, { nil, "seat" })
end)
it("a view plus the deck is the full state, in the auction and mid-play", function()
  --[[ for s = started(DECK_A, "S P P") and for started(DECK_A, "S P P P") after plays "AH 9H 8H TS AC 8C", for q = 0..4:
  local f = E.view(s, q); f.deck, f.full = E.snapshot(s).deck, true; eq(f, s) ]]
end)
it("a view keeps every card played in this deal, so a latecomer can score it", function()
  local s = started(DECK_A, "S P P P"); plays(s, "AH 9H 8H"); ok(ann(s, "s4:AC")); plays(s, "TS AC 8C 7C 9C KC 9S")
  local seen = {}; for _, face in pairs(E.view(s, 0).deck) do seen[#seen + 1] = face end; table.sort(seen)
  eq(seen, { "7C", "8C", "8H", "9C", "9H", "9S", "AC", "AH", "KC", "TS" })
  eq(E.view(s, 3).deck[idx(s, "AC")], "AC"); eq(E.view(s, 3).deck[idx(s, "KS")], nil)      -- KS is still in seat 2's hand
  local b = started(DECK_A, "S P"); eq(E.view(b, 0).deck, {})
  eq(E.view(b, 2).deck, { [2] = "TH", [6] = "QH", [10] = "9H", [14] = "7C", [18] = "QS" })
end)
```

Existing tests to change with them: `a view shows the current and the last trick only` (around line 401) is replaced by the last test above; `deal and show work on a view` (around 249) builds its view as `E.view(E.new {}, 1)`; `newTable` (around 671) builds `t.views[seat]` as `E.view(E.new { first = first }, seat)`; `assertViewHidesTheRest` (around 705) also allows, while `s.phase == "play"`, every index that is in no hand. Nothing else in the file may change, the parity block least of all.

- [ ] **Step 2: Run `bash t.sh tests/engines/belot_test.lua`.** Expected: the five new tests FAIL (`ext` is nil; `void` is `"action"`; `dealer` is nil; the view hides `AC`).
- [ ] **Step 3: Implement** in `engines/belot.lua`. No rule of play or scoring changes.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass, the 60 fixture matches included (Belot is not playable yet, so nothing else moves).
- [ ] **Step 5: Commit.** `git add engines/belot.lua tests/engines/belot_test.lua` — `feat(belot): fair contract, void, the dealer's seat; a view keeps the cards played`

### Task 2: Timeouts play the lowest card; bots bid

**Files:**
- Modify: `engines/belot.lua`, `tests/engines/belot_test.lua`

**Interfaces:**
- Produces:
  - `E.announce(s, seat) -> {k="ann", a = set} | nil`: the set `E.auto` builds today (every offered announce in the offered order whose cards are still free), moved into its own function; nil unless `seat` is on turn in phase `"play"`, announcing is still open (`canAnnounce`), every face of the hand is known and the set is not empty.
  - `E.auto(s, seat, random)`: auction → `{k="bid", b="P"}` (unchanged); tricks → `E.announce(s, seat)` when it gives one, else the legal card with the smallest key `(card points under the contract, plain before trump, position in the hand)`, with `b = true` when a belote is allowed. `random` is accepted and ignored.
  - `E.BOT_BID = 34`, `E.BOT_LUCK = 6`, `E.bot(s, seat, random) -> action | nil`:
    1. Not phase `"bid"` → `E.auto(s, seat, random)`. Not on turn → nil. A face of the hand unknown → a pass.
    2. For each suit `strength = Σ trump points of my cards of it (J 20, 9 14, A 11, T 10, K 4, Q 3) + 10 × (their number − 1)`, 0 for a suit I do not hold. `best` = the strongest suit, among equals the higher in `C < D < H < S`.
    3. `best` does not outrank the contract so far → a pass.
    4. Bid `best` when, checked in this order, `strength >= E.BOT_BID`, or nobody has bid and three have passed (`not s.contract and s.passes == 3`), or `random` is given and `random(1, E.BOT_LUCK) == 1` (called only when the first two fail). Else a pass.

- [ ] **Step 1: Write the failing tests.** `describe("belot auto")`: the second `it` is replaced, the others are new.

```lua
it("announces what it holds, then plays its lowest legal card, with the belote", function()
  local s = started(deckWith { [1] = "9C 9D 9H 9S TC JC TD JD" }, "A P P P")
  eq(E.announce(s, 1), { k = "ann", a = { { t = "c9", i = idx(s, "9S") } } }); eq(E.auto(s, 1), E.announce(s, 1)); eq(E.announce(s, 2), nil)
  ok(E.apply(s, 1, E.auto(s, 1))); eq(E.announce(s, 1), nil)
  eq(E.auto(s, 1), { k = "play", i = idx(s, "TC"), c = "TC" })                      -- a ten (10) under a nine (14) and a jack (20)
  eq(E.auto(s, 1, function() return 99 end), { k = "play", i = idx(s, "TC"), c = "TC" })
  local t = started(DECK_A, "S P P P"); plays(t, "AH 9H 8H TS AC 8C 7C 9C KC 9S")
  eq(E.auto(t, 2), { k = "play", i = idx(t, "QH"), c = "QH" }); eq(E.auto(t, 3), nil)   -- QH and QS both 3: the plain one
  local u = started(deckWith { [1] = "QS KS JS 9S AS TS AH TH" }, "S P P P")
  eq(E.auto(u, 1), { k = "ann", a = { { t = "s6", i = idx(u, "AS") } } }); ok(E.apply(u, 1, E.auto(u, 1)))
  eq(E.auto(u, 1), { k = "play", i = idx(u, "QS"), c = "QS", b = true })
end)
it("a bot bids its strong suit, and never under the contract", function()
  local d = E.new {}; deal(d, DECK_A)
  eq(E.bot(E.view(d, 1), 1), { k = "bid", b = "H" }); eq(E.bot(E.view(d, 2), 2), nil)         -- AH KH 7H: 15 + 20
  bids(d, "H"); eq(E.bot(E.view(d, 2), 2), { k = "bid", b = "P" })                              -- hearts 47, but hearts are bid
  bids(d, "P"); eq(E.bot(E.view(d, 3), 3), { k = "bid", b = "P" })                              -- clubs 34, but clubs rank under hearts
  bids(d, "P"); eq(E.bot(E.view(d, 4), 4), { k = "bid", b = "P" }); eq(E.bot(E.view(d, 1), 4), { k = "bid", b = "P" })   -- an unseen hand passes
end)
it("the fourth to speak bids its best suit rather than pass the deal out; luck bids a weak hand", function()
  local weak = "7C 8D 7H 8S 7D 8C 9C TC"                                                        -- five cards: diamonds 10, the rest 0
  local w = started(deckWith { [4] = weak }, "P P P"); eq(E.bot(E.view(w, 4), 4), { k = "bid", b = "D" })
  eq(E.bot(E.view(started(deckWith { [4] = weak }, "P P H"), 4), 4, function() return 1 end), { k = "bid", b = "P" })
  local x = E.new {}; deal(x, deckWith { [1] = weak }); local calls = 0
  local function rnd(n) return function(lo, hi) calls = calls + 1; eq({ lo, hi }, { 1, 6 }); return n end end
  eq(E.bot(E.view(x, 1), 1), { k = "bid", b = "P" }); eq(E.bot(E.view(x, 1), 1, rnd(6)), { k = "bid", b = "P" })
  eq(E.bot(E.view(x, 1), 1, rnd(1)), { k = "bid", b = "D" }); eq(calls, 2)
  local d = E.new {}; deal(d, DECK_A); eq(E.bot(E.view(d, 1), 1, rnd(1)), { k = "bid", b = "H" }); eq(calls, 2)   -- strong: luck not asked
  local p = started(DECK_A, "S P P P"); eq(E.bot(p, 1), E.auto(p, 1))
end)
it("bots alone never pass a deal out and every match ends", function()
  --[[ the loop of the fuzz test above with rnd = lcg(20261122), every seat's action = E.bot(E.view(s, seat), seat, rnd),
  until 300 deals were dealt: every action is accepted; after every action that leaves phase "deal" with s.res set,
  s.res.contract ~= nil; ok(matches >= 10) ]]   -- measured on a prototype: 309 deals, 22 matches, none passed out, at most 17 deals in a match
end)
```

- [ ] **Step 2: Run `bash t.sh tests/engines/belot_test.lua`.** Expected: the four tests FAIL (`announce` and `bot` are nil; auto plays `9C`).
- [ ] **Step 3: Implement.** The header comment of `E.auto` states the new card rule and that bots use `E.bot`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass (the two older fuzz tests and `a валат in clubs…` do not depend on which legal card `auto` picks).
- [ ] **Step 5: Commit.** `git add engines/belot.lua tests/engines/belot_test.lua` — `feat(belot): a timeout plays the lowest legal card; a bidding heuristic for bots`

### Task 3: Belot at the table — the dealer, the deal in two parts, the auction clock

**Files:**
- Modify: `core/Deal.lua`, `core/DealHooks.lua`, `core/Games.lua`, `tests/core/games_test.lua`, `tests/core/member_test.lua`, `tests/core/bots_test.lua`, `tests/ui/hall_test.lua`, `tests/wow/slash_test.lua`; Test: `tests/core/belot_table_test.lua`

**Interfaces:**
- Consumes: Tasks 1–2; stage B `ns.Deal`, `ns.Ext.fair`, `Session:armAuto`.
- Produces:
  - `core/Deal.lua`: the file-local `dealerOf(p, n)` becomes `dealerFor(s, p)`: `d = engine.dealer and s.state and engine.dealer(s.state)`; `d` when it is one of `p`, else `p[((s.fairN or 0) + 1) % #p + 1]`. Used at every place `dealerOf` is used: `Deal.open`, the `open` check of the `table` hook, and the two checks in `fits` (both in `core/DealHooks.lua`, reached through `Deal.int.dealerFor`). The header comments of both files say so, and so does the `fits` comment.
  - `fits` (snapshot rounds, `core/DealHooks.lua`): a shuffle (`commit`/`seed`) round checks `fr.d == dealerFor(s, fr.p)`. A dealt round that is still running (`not Deal.handOver(s)`) checks the same. A dealt round that is over, or a `done` round: an engine without `E.dealer` keeps the formula (`dealerOf(fr.p, fr.n - 1)`); with `E.dealer` it only checks that `fr.d` is one of `fr.p`, because after the score or a pass-out `first` has already moved on. Reason: a newcomer or a relogged player must keep the round (PB7, PB6b); with the formula every Belot SNP round would be dropped and the table would stall (a relogged player never sends PRQ, a relogged dealer never asks for the void).
  - `Games.PLAYABLE.belot = true` (comment: tabla D, holdem E remain).

- [ ] **Step 1: Write the failing tests** (`tests/core/belot_table_test.lua`). Helpers: `table4()` = a new sim, `a, b, c, d, w` added in that order, `sim:run(1)`; `tid = a:openTable{ game = "belot", access = "guild", turn = 45 }`, `sim:run(3)`; `w:watch(tid)`, `sim:run(1)`; `b:sit(tid, 2)`, `c:sit(tid, 3)`, `d:sit(tid, 4)`, each followed by `sim:run(1)`; returns `sim, tid`. `at(seat)` = `sim.clients[a.session.seats[seat]]`. `bid(str)` = for each token the client on turn does `:act{ k = "bid", b = token }` (must return true), then `sim:run(1)`. `autoPlay(n)` = `n` times: no seat on turn → stop; `at(turn):playAuto()`; `sim:run(1)`. `known(cl)` = the number of faces in `cl.session.state.deck`. `verdicts(cl)`, `sentOf(t)`, `faces(v)` as in stage B with the pattern `^[789TJQKA][CDHS]$`. `E = ns.Engines.belot`.

```lua
it("four players get five cards, then three more; the dealer is the seat before the first bidder", function()
  local sim, tid = table4(); local r = a.session.fair
  eq({ a.session.state.phase, a.session.state.turn, r.d, r.p, r.dealer, r.stage }, { "bid", 1, 4, { 1, 2, 3, 4 }, D, "dealt" })
  local deck = d.session.fair.deck; eq(deck, ns.Fair.deck(E.DECK, { SEED, SEED, SEED, SEED }, tid .. "/" .. r.h)); eq(a.session.fair.deck, nil)
  eq({ known(a), known(b), known(c), known(d), known(w) }, { 5, 5, 5, 5, 0 })
  for q = 1, 4 do for _, i in ipairs(a.session.state.hands[q]) do eq(at(q).session.state.deck[i], deck[i]) end end
  eq(#sentOf("SED"), 3); for _, m in ipairs(sentOf("SED")) do eq(m.target, D) end; eq(#sentOf("PRV"), 3)
  bid("S P P P"); eq({ a.session.state.phase, a.session.state.turn, #a.session.state.hands[2] }, { "play", 1, 8 })
  eq({ known(a), known(b), known(c), known(d), known(w) }, { 8, 8, 8, 8, 0 }); eq(#sentOf("PRV"), 6)
  for _, m in ipairs(sentOf("PRV")) do eq(m.from, D) end
  local h = b.session.seq + 1                                                                    -- a host naming another dealer is refused
  eq(ns.Ext.fair.table(b.session, { k = "fair", op = "open", h = h, d = 3, p = { 1, 2, 3, 4 } }), nil)   -- d = 3 is the formula's seat p[(1 + 1) % 4 + 1]
  eq(ns.Ext.fair.table(b.session, { k = "fair", op = "open", h = h, d = 2, p = { 1, 2, 3, 4 } }), nil)   -- no positive control: it would replace b's round
end)
it("the deal passes to the next seat every deal, played or passed out, and every deal is проверена", function()
  --[[ table4(); verdicts on a, c and w; dealers = {a.session.fair.d}. Deal 1: bid("C P P P"); autoPlay until no seat is on turn; sim:run(3)
  (the score); a.session.state.res.contract.b == "C". Then three times: sim:run(8) (the next deal is there: phase "bid"), note a.session.fair.d,
  autoPlay(4) (four passes). At the end: dealers == {4, 1, 2, 3}; the verdicts of a, c and w are {"ok", "ok", "ok", "ok"};
  a.session.state.round == 5 and a.session.state.first == 1 ]]
end)
it("no message to another seat or a watcher carries a face it may not see, through a whole deal", function()
  --[[ table4(); deck = d.session.fair.deck; held[q] = sets of deck indices; public = a set of faces.
  After table4(), after each token of bid("H P P P") and after each autoPlay(1) while a.session.state.phase == "play":
    held[q] gains every index in ns.Fair.full(d.session.state, deck).hands[q];
    public gains the face of every index in d.session.state.trick and in d.session.state.last.cards;
    for every new entry m of sim.sent: on GUILD faces(m.msg) == {}; to W every face is in public;
    to the name on seat q every face is in public or is deck[i] for an i in held[q].
  At the end 32 play EVs went to B, and no GUILD message has t SED/PRV/PRQ or a 32- or 64-character hex string ]]
end)
it("a snapshot mid-deal shows a newcomer the played cards and only its own hand", function()
  --[[ table4(); x = sim:add("Нов Гледач"); bid("S P P P"); autoPlay(6); st = ns.Fair.full(d.session.state, d.session.fair.deck);
  played = the faces of every index in no hand of st. c2 = sim:relog(C); x:watch(tid); sim:run(3).
  The last SNP to "Нов Гледач": the set faces(msg.st) == played. The last SNP to C: faces(msg.st) == played (the host does not know C's hand).
  Then ns.Deal.missing(c2.session) == false, known(c2) == #played + #st.hands[3], exactly one PRQ went from C to D ]]
end)
it("nobody bids: four automatic passes, the deal is passed out, the next seat deals", function()
  local sim = table4(); local seen = verdicts(a); local mark = #sim.sent
  sim:run(182); eq({ a.session.state.round, a.session.state.first }, { 2, 2 }); eq(a.session.state.res.contract, nil); eq(seen, { "ok" })
  --[[ after mark: the EVs to B with a.k == "bid" are four, all b == "P", from seats 1, 2, 3, 4 in that order; B, C and D each sent
  exactly one ACT with a bid (their own clocks); A sent none ]]
  sim:run(15); eq({ a.session.state.phase, a.session.state.turn, a.session.fair.d, a.session.fair.stage }, { "bid", 2, 1, "dealt" })
end)
```

Existing tests to change: `tests/core/games_test.lua` (the list test: `ok(G.engine("belot") == ns.Engines.belot)`, `ok(G.list()[4].engine == ns.Engines.belot)`, `eq(G.list()[5].engine, nil)`; the TBL test uses `g="tabla"` with `s={A,false}`); `tests/core/member_test.lua` around line 42 (`tabla` as the gated engine, `s={A, B}`); `tests/core/bots_test.lua` (`hostTable("tabla")` is nil); `tests/ui/hall_test.lua` (four active games, two dimmed: indices 1–4 and 5–6; the dimmed click uses `games[5]`); `tests/wow/slash_test.lua` (the two `bots host belot` → „не е готова“ checks use `tabla`; new: `w:slash("bots host belot"); w:advance(1)` lists a table with `game == "belot"`).

- [ ] **Step 2: Run `bash t.sh tests/core/belot_table_test.lua`.** Expected: FAIL (`openTable` returns nil, `"game"`).
- [ ] **Step 3: Implement** `dealerFor` at all four sites (`Deal.open`, the `table` open check, both `fits` checks, the last two in `core/DealHooks.lua`), `PLAYABLE.belot`, and the test changes.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `5 passed, 0 failed`; all pass (the `hicard` and Сантасе deal tests keep the formula: neither engine has `dealer`).
- [ ] **Step 5: Commit.** `git add core/Deal.lua core/DealHooks.lua core/Games.lua tests/core/belot_table_test.lua tests/core/games_test.lua tests/core/member_test.lua tests/core/bots_test.lua tests/ui/hall_test.lua tests/wow/slash_test.lua` — `feat: Белот at the table on a fair deal; the engine names the dealer`

### Task 4: Leaving, going offline, the dealer's reload, the team result

**Files:**
- Modify: `core/Lifecycle.lua`, `core/Member.lua`; Test: `tests/core/belot_table_test.lua`

**Interfaces:**
- Produces: `Session:noteResult()` — the `"result"` payload gains `left = r.left` and `names = copy(self.seatedBefore or self.seats)`; whenever the engine has no result yet it stores `self.seatedBefore = copy(self.seats)` (so `names` is the table as it sat before the stand that ended the game). `Member.adopt` also sets `s.seatedBefore = copy(s.seats)` when the adopted state has no result, so a member that came by snapshot and whose first event is the ending stand still names the leaver (`Session.lua` stays untouched). The header comment of `core/Lifecycle.lua` names both fields.
- Nothing else changes: a stand at a live Belot table already ends the match through `E.leave`, the host's `abortIfShort` then aborts the short table and drops the round (no verdict for that deal), `startable` says `"short"`, and a fourth player sitting down starts a new match by `startIfFull`.

- [ ] **Step 1: Write the failing tests** (appended to `tests/core/belot_table_test.lua`; `results(cl)` = the list of `"result"` payloads of that client; `rigged()` = `ns.Ext.fair = {}` before `table4()` and `ns.Ext.fair = REAL` at the end of the test, with `local REAL = ns.Ext.fair` at file scope, so nothing deals by itself; `dealAll(deck)` = `a.session:play(0, { k = "deal", deck = deck }); sim:run(1)` (a test shortcut: every client knows every face); `playFirst(n)` = `n` times: the client on turn plays the first card of its hand (`i = hands[turn][1]`, `c = deck[i]` from its own state), `sim:run(1)`).

```lua
it("a player stands mid-deal: the match ends, his team loses, the result names the leaver", function()
  local sim, tid = table4(); local ra, rw, seen = results(a), results(w), verdicts(a)
  bid("S P P P"); autoPlay(2); c:stand(); sim:run(2)
  eq(#ra, 1); local r = ra[1]; eq({ r.game, r.winners, r.losers, r.left }, { "belot", { 2, 4 }, { 1, 3 }, 3 })
  eq(r.names, { A, B, C, D }); eq(r.seats[3], false); eq(#rw, 1); eq(rw[1].winners, { 2, 4 })
  eq({ a.session.state.phase, a.session.state.winner, a.session.status }, { "match", 2, "aborted" })
  eq({ ns.Session.startable(a) }, { nil, "short" }); eq(a.session.fair, nil); eq(seen, {})
  c:sit(tid, 3); sim:run(3)
  eq({ a.session.status, a.session.state.phase, a.session.state.score, a.session.fair.stage }, { "live", "bid", { 0, 0 }, "dealt" })
end)
it("a player offline for three minutes is stood up and his team loses", function()
  local sim = table4(); local ra = results(a)
  sim:offline(B); ok(a:act{ k = "bid", b = "P" }); sim:run(170)
  eq({ a.session.state.phase, a.session.state.turn, #a.session.state.bids, #ra }, { "bid", 2, 1, 0 })    -- nobody passed for him
  sim:run(30); eq(#ra, 1); eq({ ra[1].winners, ra[1].losers, ra[1].left, ra[1].names[2] }, { { 1, 3 }, { 2, 4 }, 2, B })
end)
it("the dealer relogs mid-deal: void, the next seat deals, no point moved", function()
  local sim = table4(); local seen = verdicts(a); local h1 = a.session.fair.h
  bid("S P P P"); autoPlay(1); local d2 = sim:relog(D); sim:run(8)
  eq(seen, { "void" }); ok(a.session.fair.h ~= h1); eq({ a.session.fair.d, a.session.fair.stage }, { 1, "dealt" })
  ok(a.session.fair.deck ~= nil); eq(d2.session.fair.deck, nil)                                  -- PB6b: the voiding dealer does not deal again
  eq({ a.session.state.phase, a.session.state.round, a.session.state.first, a.session.state.turn }, { "bid", 1, 2, 2 }); eq(a.session.state.score, { 0, 0 })
end)
it("a member that came by snapshot still names the leaver", function()
  --[[ table4(); x = sim:add("Нов Гледач"); bid("S P P P"); autoPlay(2); x:watch(tid); sim:run(3) (x adopts a snapshot, no result yet:
  x.session.seatedBefore == { A, B, C, D }); rx = results(x); c:stand(); sim:run(2): #rx == 1, rx[1].left == 3, rx[1].names == { A, B, C, D } ]]
end)
it("a player who relogs after an announce still scores the deal", function()
  --[[ rigged(); table4(); dealAll(DECK_A); bid("S P P P"); plays AH, 9H, 8H by the seat on turn; ok(d:act{ k = "ann", a = { { t = "s4", i = 4 } } }); sim:run(1);
  plays TS AC 8C 7C 9C KC 9S; autoPlay(6). c2 = sim:relog(C) counting its "desync" events; sim:run(3): c2.session.state.deck[4] == "AC".
  autoPlay until no seat is on turn; sim:run(4): the desync count is 0; a.session.state.phase == "deal";
  c2.session.state.score == a.session.state.score; a.session.state.res.ann[1] == { s = 4, t = "s4", i = 4, v = 50, on = true }; ns.Ext.fair = REAL ]]
end)
it("вътре and контра score the same on every client", function()
  rigged(); local sim = table4()
  dealAll(DECK1); bid("P C P P P"); playFirst(32); sim:run(3)                       -- seat 2 called clubs; seat 1 holds every club
  for _, cl in ipairs{ a, b, c, d, w } do
    local st = cl.session.state
    eq({ st.res.contract, st.res.raw, st.res.pts, st.res.valat }, { { seat = 2, b = "C", x = 1 }, { 252, 0 }, { 25, 0 }, true }); eq(st.score, { 25, 0 })
  end
  dealAll(DECK1); bid("D X P P P"); playFirst(32); sim:run(3)                       -- seat 2 calls its diamonds, seat 3 doubles
  for _, cl in ipairs{ a, b, c, d, w } do
    local st = cl.session.state
    eq({ st.res.contract, st.res.raw, st.res.pts }, { { seat = 2, b = "D", x = 2 }, { 0, 252 }, { 0, 50 } }); eq(st.score, { 25, 50 }); eq(E.over(st), false)
  end
  ns.Ext.fair = REAL
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/belot_table_test.lua`.** Expected: the first two new tests and the snapshot-member test FAIL (`left` and `names` are nil); the other three pass already and stay as regression pins.
- [ ] **Step 3: Implement** `noteResult` and the `Member.adopt` line.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `11 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add core/Lifecycle.lua core/Member.lua tests/core/belot_table_test.lua` — `feat(core): the result names who left; Белот forfeits, voids and team scores pinned`

### Task 5: Bots that bid, and bot tables that fill

**Files:**
- Modify: `core/Bots.lua`, `tests/core/bots_test.lua`

**Interfaces:**
- Consumes: `E.bot`, `client:act`, `client:invite`, `Bots:idle`, `bot.invites.sent`.
- Produces:
  - `nextAction(bot)`: on its turn a bot does `local a = engine.bot and engine.bot(st, s.mySeat, bot.env.random)`; `bot:act(a)` when `a` is not nil, else `bot:playAuto()`. Still after `MOVE_AFTER`.
  - Filling: `FILL_AFTER = 1`. After any session change of a bot that hosts a table with `status ~= "live"` (open, or aborted after a stand) and `2 <= s:seatedCount() < engine.minSeats` and no invitation of its own pending (`next(bot.invites.sent) == nil`), it invites `self:idle()` once `FILL_AFTER` has passed (one bot per change, so a table of four fills in about three seconds after the first guest sat). `behave` gets the `Bots` object for this. A table of a two-player game never fills this way.
  - The header comment of `core/Bots.lua` states both.

- [ ] **Step 1: Write the failing tests** (`setup()` and `mentions` as in the file).

```lua
it("one human and three bots play a whole Белот match; every deal is checked; nothing leaves the machine", function()
  local sim, a = setup(); local E = ns.Engines.belot
  local fair, res = {}, {}; a:on("fair", function(e) fair[#fair + 1] = e.verdict end); a:on("result", function(r) res[#res + 1] = r end)
  local tid = a:openTable{ game = "belot", access = "invite", turn = 45 }; ok(tid)
  for _, name in ipairs(STARTERS) do ok(a:invite(name)) end
  local mark = #sim.sent; sim:run(5); eq(a.session:seatedCount(), 4); eq(a.session.status, "live")
  for _ = 1, 40000 do
    local st = a.session.state; if E.over(st) then break end
    if st.turn == 1 then a:playAuto() end; sim:run(1)                       -- I only ever pass and play my lowest card
  end
  sim:run(1); local st = a.session.state; eq(E.over(st), true); eq(#res, 1); ok(#fair >= 4)
  eq(res[1].winners, st.winner == 1 and { 1, 3 } or { 2, 4 }); eq(res[1].left, nil); ok(st.score[st.winner] >= 151)
  for _, v in ipairs(fair) do eq(v, "ok") end
  eq(sim:count(function(m) return m.msg.t == "SED" or m.msg.t == "PRV" or m.msg.t == "PRQ" end), 0)
  --[[ as in the Сантасе test: no entry of sim.sent after mark mentions tid or a bot's name, and A sent something for real ]]
  local first = st.first; ok(a:startGame()); sim:run(4)
  eq({ a.session.state.score, a.session.state.phase, a.session.state.first }, { { 0, 0 }, "bid", first % 4 + 1 })
end)
it("a bot-hosted Белот table fills with bots once I sit, and the bot host starts the next match", function()
  --[[ tid = bots:hostTable("belot"); sim:run(3): one seat taken. a:sit(tid, 2); sim:run(8): a.session:seatedCount() == 4, seats 3 and 4 are
  bots (bots.isBot), a.session.status == "live". Play to the end as above with my seat 2; sim:run(6): a.session.state.score == {0, 0} and
  the phase is "bid". Then a bot at seat 3 stands (bots.list[k]:stand()); sim:run(8): the table was "aborted" with 3 seated and is filled again,
  a.session:seatedCount() == 4 and the status is "live". A bot table of Морски шах with me seated invites nobody (no INV in the bots' traffic: bots.list[k].invites.sent stays empty) ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/bots_test.lua`.** Expected: the two tests FAIL (every deal is passed out until the loop ends; the table stays at two).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add core/Bots.lua tests/core/bots_test.lua` — `feat(bots): bots bid through the engine's bot move and fill a table of four`

**— End of C1. Boundary check before C2: `bash t.sh` green, the Review Focus tests of Tasks 2–4 exist and pass. C2 changes no rule of Tasks 1–5. —**

---

# Part C2 — the table for four, the rules book

### Task 6: Four plates around the felt

**Files:**
- Modify: `core/HallLayout.lua`, `ui/TableFrame.lua`; Test: `tests/core/hall_layout_test.lua`, `tests/ui/table_test.lua`

**Interfaces:**
- Produces:
  - `HallLayout.ring(n, w, h, me) -> spots, 1`: for `n == 4`, `spots[seat] = {x, y, 165}` by `k = (seat − me) % 4`: `0` → `{(w − 165) / 2, −(h − 52)}`, `1` → `{w − 175, −105}`, `2` → `{(w − 165) / 2, −10}`, `3` → `{10, −105}`. Any other `n`: `HallLayout.plates(n, w)`.
  - `ui/TableFrame.lua`: a view with `ring = true` gets its plates from `HallLayout.ring(#s.seats, v.areaW, v.areaH, s.mySeat or 1)`, and its board is anchored `TOPLEFT` to the felt's `TOPLEFT` at `0, 0` (the view builds a frame as large as the felt: `parent:GetWidth()`, `parent:GetHeight()`). `bannerKey`: an open table whose engine does not start by the host waits with `"table.waitingMore"` when `engine.minSeats > 2`, else `"table.waiting"`. The header comment states both.

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/core/hall_layout_test.lua
it("ring: my seat at the bottom, the next on the right, the partner on top", function()
  local p, rows = H.ring(4, 532, 328, 1)
  eq(p, { { 183.5, -276, 165 }, { 357, -105, 165 }, { 183.5, -10, 165 }, { 10, -105, 165 } }); eq(rows, 1)
  eq(H.ring(4, 532, 328, 3), { { 183.5, -10, 165 }, { 10, -105, 165 }, { 183.5, -276, 165 }, { 357, -105, 165 } })
  eq(H.ring(2, 532, 328, 1), (H.plates(2, 532)))
end)
-- tests/ui/table_test.lua
it("a ring view: four plates around the felt, the board over the whole felt, „Чакаме още играчи…“", function()
  local w = withBots(); local T = w.ns.TableFrame
  T.registerView("belot", { ring = true, update = function() end, build = function(parent)
    local f = w.G.CreateFrame("Frame", nil, parent); f:SetSize(parent:GetWidth(), parent:GetHeight()); return f end })
  w.ns.client:openTable{ game = "belot", access = "invite", turn = 45 }; w:advance(0); local v = T.view
  eq(v.plates[1].frame.points[1], { "TOPLEFT", v.area, "TOPLEFT", 183.5, -276 }); eq(v.plates[3].frame.points[1], { "TOPLEFT", v.area, "TOPLEFT", 183.5, -10 })
  eq(v.plates[2].frame.points[1], { "TOPLEFT", v.area, "TOPLEFT", 357, -105 }); eq(v.plates[4].frame.points[1], { "TOPLEFT", v.area, "TOPLEFT", 10, -105 })
  eq(v.plates[4].frame:GetWidth(), 165); eq(#w:texts("Чакаме още играчи…"), 1); eq(#w:texts("Чакаме втори играч…"), 0)
  eq(T.built.belot.points[1], { "TOPLEFT", v.area, "TOPLEFT", 0, 0 }); eq({ T.built.belot:GetSize() }, { 532, 328 })
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/hall_layout_test.lua tests/ui/table_test.lua`.** Expected: both FAIL (`ring` is nil; the plates sit in the grid at `10, −10`).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: all pass (Морски шах, Death Roll and Сантасе keep the grid and the centred board).
- [ ] **Step 5: Commit.** `git add core/HallLayout.lua ui/TableFrame.lua tests/core/hall_layout_test.lua tests/ui/table_test.lua` — `feat(ui): a ring of four plates around the felt for team games`

### Task 7: The Belot model

**Files:**
- Create: `ui/games/BelotModel.lua`; Modify: `TavernGames.toc`; Test: `tests/ui/belot_model_test.lua`

**Interfaces:**
- Consumes: `ns.Engines.belot` (`legal`, `announce`, `dealer`, `over`; state fields `phase`, `turn`, `first`, `hands`, `deck`, `bids`, `contract`, `trick`, `lead`, `trickNo`, `last`, `ann`, `score`, `hang`, `res`, `winner`, `left`).
- Produces `ns.BelotModel.build(s, peek, names) -> model`. It reads only `s.state`, `s.mySeat`, `s.status`, `s.seats` (a plain table will do) and `names` (optional: seat → who held it during the match). It never stores anything.
  - `me` = my seat, or 1 for a watcher; `seated`; `team = 2 − me % 2`; `pos[seat] = (seat − me) % 4` (0 bottom, 1 right, 2 top, 3 left).
  - `mine` = seated, `s.status == "live"`, phase `"bid"` or `"play"`, `state.turn == me`.
  - `hand` = my cards as `{i, face, mode}`: by suit `C D H S`; inside a suit the strongest first, in trump order (`J 9 A T K Q 8 7`) when the contract makes that suit trump, else in plain order (`A T K Q J 9 8 7`); unknown faces last in hand order (a watcher: seat 1's cards without faces). Modes as in Сантасе: not `mine` or not phase `"play"` → `"plain"`; `mine` in the tricks → when some card has no `play` action the playable ones `"raised"` and the rest `"dim"`, otherwise all `"plain"`.
  - `bids` = `{[b] = true}` for every `bid` action in `E.legal(state, me)` when `mine` in the auction, else `{}`. `announce` = `E.announce(state, me)` when `mine` in the tricks, else nil.
  - `trick` = `{{seat, i, face}, …}` in play order (`seat = (lead + k − 2) % 4 + 1`); with `peek` and `state.last`: the last trick's cards from `state.last.lead` instead, and `peeking = true`. `canPeek` = phase `"play"` and `state.last ~= nil`.
  - `bubbles[seat]` = a list of locale keys, absent when empty, built **only** from the state: auction → `"belot.bid." .. b` of the seat's last entry in `state.bids`; tricks → for every entry of `state.ann` of that seat, `"belot.ann." .. t` when `t ~= "b"` and `state.trickNo <= 2`, and `"belot.ann.b"` when `t == "b"` and its card `i` is in `state.trick`, or in `state.last.cards` while `state.trick` is empty.
  - `contract` = `state.contract` (nil in the auction before a bid); `dealer` = `E.dealer(state)` in phases `"bid"`, `"play"`, `"score"`, else nil; `score = {us = state.score[team], them = state.score[3 − team], hang = state.hang}`.
  - `summary` (phase `"deal"` or `"match"` with `state.res`, else nil) = `{passed = res.contract == nil, contract = res.contract, us = res.pts[team], them = res.pts[3 − team], hang = res.hang, valat = res.valat, inside, hanging, anns}` with `inside` = a contract whose declarer's team has the smaller `res.raw`, `hanging` = a contract with equal `res.raw`, `anns = {{seat, t, v, on}, …}` copied from `res.ann` in its order.
  - `text = {key, …}`: `E.over(state)` (not a `phase == "match"` comparison of its own) → `{"belot.left", name}` when `state.left`; else seated → `{state.winner == team and "belot.match.us" or "belot.match.them"}`; a watcher → `{"belot.match.names", name of seat winner, name of seat winner + 2}`. Phase `"deal"` with a passed-out `res` → `{"belot.passed"}`. Auction → `{"belot.yourBid"}` when `mine`, else `{"belot.waitFor", name on turn}`. Tricks → `{"belot.yourTurn"}` or `{"belot.waitFor", name}`. Otherwise nil.

- [ ] **Step 1: Write the failing tests.** File scope: `guildWow()` as in the other UI tests; `M, E = w.ns.BelotModel, w.ns.Engines.belot`; `sess(state, seat)` = `{ game = "belot", status = "live", mySeat = seat, seats = { A, B, C, D }, state = state }` (`seat` nil = a watcher, `state` then `E.view(st, 0)`); `at(st, q)` = `M.build(sess(E.view(st, q), q))`; `started`, `plays`, `ann`, `idx`, `deckOf`, `DECK_A` copied from the engine test; `faces(v)` as in Task 3, sorted.

```lua
it("the auction: my five cards sorted, only the legal bids, what each seat said", function()
  local st = E.new {}; ok(E.apply(st, 0, { k = "deal", deck = DECK_A })); local m = at(st, 1)
  local ids = {}; for k, c in ipairs(m.hand) do ids[k] = c.i; eq(c.mode, "plain") end; eq(ids, { 13, 1, 5, 9, 17 })       -- 8C | AH KH 7H | JS
  eq(m.bids, { P = true, C = true, D = true, H = true, S = true, N = true, A = true }); eq(m.text, { "belot.yourBid" })
  eq({ m.me, m.team, m.mine, m.dealer, m.pos, m.bubbles, m.score }, { 1, 1, true, 4, { 0, 1, 2, 3 }, {}, { us = 0, them = 0, hang = 0 } })
  ok(E.apply(st, 1, { k = "bid", b = "H" })); eq(at(st, 2).bids, { P = true, S = true, N = true, A = true, X = true })
  ok(E.apply(st, 2, { k = "bid", b = "P" })); m = at(st, 3)
  eq(m.bids, { P = true, S = true, N = true, A = true }); eq(m.pos, { 2, 3, 0, 1 }); eq(m.bubbles, { [1] = { "belot.bid.H" }, [2] = { "belot.bid.P" } })
  eq(at(st, 1).bids, {}); eq(at(st, 1).text, { "belot.waitFor", C })
  local x = started(DECK_A, "H X"); eq(at(x, 3).bids, { P = true, S = true, N = true, A = true, R = true })
end)
it("the tricks: trumps sorted as trumps, unplayable cards dimmed, the trick by seat, the last trick on request", function()
  local st = started(DECK_A, "S P P P"); local m = at(st, 1)
  local ids = {}; for k, c in ipairs(m.hand) do ids[k] = c.i; eq(c.mode, "plain") end; eq(ids, { 13, 29, 25, 1, 5, 9, 17, 21 })   -- 8C | 8D 7D | AH KH 7H | JS 9S
  eq({ m.contract, m.announce, m.canPeek, m.text }, { { seat = 1, b = "S", x = 1 }, nil, false, { "belot.yourTurn" } })
  plays(st, "AH"); m = at(st, 2); local modes = {}; ids = {}
  for k, c in ipairs(m.hand) do ids[k], modes[k] = c.i, c.mode end
  eq(ids, { 14, 26, 30, 2, 6, 10, 22, 18 }); eq(modes, { "dim", "dim", "dim", "raised", "raised", "raised", "dim", "dim" })   -- 7C | AD TD | TH QH 9H | KS QS
  plays(st, "9H 8H"); ok(ann(st, "s4:AC")); plays(st, "TS AC 8C"); m = at(st, 1)
  eq(m.trick, { { seat = 4, i = 4, face = "AC" }, { seat = 1, i = 13, face = "8C" } }); eq({ m.canPeek, m.peeking }, { true, nil })
  m = M.build(sess(E.view(st, 1), 1), true); eq(m.peeking, true)
  eq(m.trick, { { seat = 1, i = 1, face = "AH" }, { seat = 2, i = 10, face = "9H" }, { seat = 3, i = 7, face = "8H" }, { seat = 4, i = 24, face = "TS" } })
end)
it("bubbles are the engine's record: bids, announces of the first two tricks, a belote on the table", function()
  local st = started(DECK_A, "S P P P"); plays(st, "AH 9H 8H")
  local m = at(st, 4); eq(m.announce, { k = "ann", a = { { t = "s4", i = 4 } } }); eq(m.bubbles, {})        -- offered, not said yet
  ok(ann(st, "s4:AC")); eq(at(st, 4).announce, nil)
  for q = 0, 4 do eq(M.build(sess(E.view(st, q), q > 0 and q or nil)).bubbles, { [4] = { "belot.ann.s4" } }) end
  plays(st, "TS AC 8C"); eq(at(st, 2).bubbles, { [4] = { "belot.ann.s4" } })                                  -- trick 2: still shown
  plays(st, "7C 9C KC 9S"); eq(at(st, 2).bubbles, {})
  ok(E.apply(st, 2, { k = "play", i = 18, c = "QS", b = true })); eq(at(st, 1).bubbles, { [2] = { "belot.ann.b" } })
end)
it("the model holds no face outside my hand and the cards on the table", function()
  local st = started(DECK_A, "S P P P"); plays(st, "AH 9H 8H"); ok(ann(st, "s4:AC")); plays(st, "TS AC 8C")
  eq(faces(M.build(sess(E.view(st, 0), nil))), { "8C", "AC" }); eq(faces(M.build(sess(E.view(st, 0), nil), true)), { "8H", "9H", "AH", "TS" })
  eq(faces(at(st, 2)), { "7C", "8C", "AC", "AD", "KS", "QH", "QS", "TD", "TH" })                                 -- its seven cards and the trick
  for _, c in ipairs(M.build(sess(E.view(st, 0), nil)).hand) do eq(c.face, nil) end
end)
it("the summary says who is вътре, the doubling and each side's points", function()
  local st = E.view(started(DECK_A, "S P P P"), 1); st.phase, st.score, st.hang = "deal", { 32, 0 }, 0
  st.res = { round = 1, contract = { seat = 2, b = "H", x = 2 }, raw = { 102, 60 }, pts = { 32, 0 }, hang = 0, valat = false,
    ann = { { s = 1, t = "s3", i = 9, v = 20, on = true }, { s = 2, t = "s3", i = 10, v = 20, on = false }, { s = 4, t = "b", i = 20, v = 20, on = true } } }
  local m = M.build(sess(st, 1)); local sum = m.summary
  eq({ sum.passed, sum.contract, sum.us, sum.them, sum.hang, sum.valat, sum.inside, sum.hanging }, { false, { seat = 2, b = "H", x = 2 }, 32, 0, 0, false, true, false })
  eq(M.build(sess(st, 2)).summary.us, 0); eq(M.build(sess(st, 2)).summary.them, 32); eq(m.score, { us = 32, them = 0, hang = 0 }); eq(m.text, nil)
  st.res.raw, st.res.pts, st.res.hang = { 81, 81 }, { 8, 0 }, 11; sum = M.build(sess(st, 1)).summary; eq({ sum.inside, sum.hanging, sum.hang }, { false, true, 11 })
  st.res = { round = 1, raw = { 0, 0 }, pts = { 0, 0 }, hang = 0, valat = false, ann = {} }
  eq(M.build(sess(st, 1)).summary.passed, true); eq(M.build(sess(st, 1)).text, { "belot.passed" })
end)
it("the summary names an announce that lost as not counted", function()
  --[[ with the first res of the test above: summary.anns == { {seat=1, t="s3", v=20, on=true}, {seat=2, t="s3", v=20, on=false}, {seat=4, t="b", v=20, on=true} } ]]
end)
it("the end of the match: us, them, the names for a watcher, the one who left", function()
  --[[ st.phase, st.winner = "match", 2: at seat 1 text == {"belot.match.them"}, at seat 4 {"belot.match.us"}, a watcher {"belot.match.names", B, D};
  st.left = 3 with sess.seats[3] = false and names = { A, B, C, D }: text == {"belot.left", C}; summary still there when st.res is set ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/belot_model_test.lua`.** Expected: FAIL (`BelotModel` is nil).
- [ ] **Step 3: Implement**; TOC line `ui/games/BelotModel.lua` after `ui/games/SantaseView.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `7 passed, 0 failed`; all pass.
- [ ] **Step 5: Commit.** `git add ui/games/BelotModel.lua TavernGames.toc tests/ui/belot_model_test.lua` — `feat(ui): the Белот table as a pure model`

### Task 8: The Belot view

**Files:**
- Create: `ui/games/BelotView.lua`; Modify: `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`; Test: `tests/ui/belot_test.lua`

**Interfaces:**
- Consumes: `ns.BelotModel.build`, `ns.Cards`, `HallLayout.ring` positions (through `model.pos`), `client:act`, `TableFrame.registerView`, `W.Button`, `W.edges`, `W.Label`, `W.colored`.
- Produces: `TableFrame.registerView("belot", View)` with `View.ring = true`, `View.build(parent)`, `View.update(f, s)`, `View.seatNote(s, seat)` = `M.build(s).dealer == seat and L("belot.dealer") or ""` (the dealer rule lives only in the model). The built frame (as large as `parent`) exposes `myFan`, `trick[0..3]` (card widgets by position), `bidButtons[b]` for `b` in `P C D H S N A X R`, `announceButton`, `peekButton`, `bubbles[0..3]` (frames with `.text`), `contract`, `score`, `summary`, `text`.
- `View.update` stores `f.session = s` and, as SantaseView does (ledger B11), keeps `f.names` / `f.namesTid`: refreshed from `s.seats` while `not E.over(state)` (reset when the table id changes); it calls `M.build(s, f.peek, f.names)`, so the end-of-match line can name a leaver whose seat is already `false`. Every click acts on `f.session` through `ns.client:act(a)` and then redraws. `f.peek` (the last trick is showing) is set by `peekButton` and ends with any table event (the key `tid/epoch/seq`, as „Обяви“ in Сантасе). A match that is over is read through the model (`E.over`), not through `phase == "match"` comparisons of its own.
- Drawing, offsets from the frame's `TOPLEFT` (frame 532 × 328):
  - `trick[2]` at `(246, −56)`, `trick[0]` at `(246, −122)`, `trick[3]` at `(200, −89)`, `trick[1]` at `(292, −89)`; each shows the card of the seat at that position, hidden when that seat has not played. While peeking the four cards are the last trick, in the `"dim"` look.
  - Bid buttons 24 high, shown only for `model.bids[b]`: `C D H S` 40 wide at `x = 180, 224, 268, 312`, `y = −60`, each showing its suit from the `suits` texture (16 px, `Cards.COORD`, hearts and diamonds in `red`, the others in `ink`); `N` and `A` 84 wide at `(180, −88)` and `(268, −88)`; `P` 84 wide at `(180, −116)`; `X` and `R` 84 wide at `(268, −116)` (never both legal). A click sends `{k="bid", b}`.
  - `summary`: one wrapped text 170 wide (x 181–351, clear of the side plates at x 10–175 and 357–522), font 11, its top centre at `(266, −64)`, shown when `model.summary` is set (the trick is empty then). Lines, in this order, joined by newlines: `L("belot.passed")` alone for a passed-out deal; else `L("belot.contract", <game>)` with `<game>` = `L("belot.bid." .. b)`, wrapped in `L("belot.x2", …)` / `L("belot.x4", …)` when doubled, then `L("belot.by", <declarer's name>)` on the same line after two spaces; `L("belot.sum.points", us, them)`; `L("belot.sum.inside.us")` or `.them` when `inside` (us = the declarer is on my team); `L("belot.sum.hanging", hang)` when `hanging`; `L("belot.sum.valat")` when `valat`; one line per announce: `L("belot.sum.ann", name, L("belot.ann." .. t), v)` when `on`, else `L("belot.sum.off", name, L("belot.ann." .. t))` in `inkDim`.
  - `text`: heading 15, centred on `(266, −192)`; gold in phases `"deal"` and `"match"`; a name in it is class-coloured (`W.colored`).
  - `myFan`: `Cards.fan`, its bottom centre 60 px above the frame's bottom edge. A click on a card that is not dimmed sends its `play` action, the variant with `b = true` when `E.legal` offers one (a belote is never left unsaid).
  - `announceButton` 124 × 24 at `(392, −172)`, shown when `model.announce`; text `L("belot.announce", <the kinds, joined by ", ">)`; a click sends `model.announce`. `peekButton` 124 × 24 at `(16, −172)`, text `L("belot.peek")`, shown when `model.canPeek`, gold-edged while peeking.
  - `contract`: two lines (dim, 11) at `(10, −12)`: the game as in the summary, and `L("belot.by", name)`; hidden without a contract. `score`: two right-aligned lines ending at `(522, −12)`: `L("belot.score.us", us, them)` (a watcher: `L("belot.score.watch", us, them)`), and `L("belot.target")`, followed by `" · " .. L("belot.hang", hang)` when `hang > 0`.
  - `bubbles[k]`: 150 × 18, dark fill with a brass edge, gold text 11, the keys' texts joined by `", "`; at `(191, −38)` for position 2, `(364, −133)` for 1, `(17, −133)` for 3, `(357, −280)` for 0; hidden when the seat at that position has no bubble.
- Locale (bg; en pinned in brackets), a new section `-- Белот` after the Сантасе section in both files: `belot.bid.P` = „Пас“ (`Pass`); `belot.bid.C` = „Спатия“ (`Clubs`); `belot.bid.D` = „Каро“ (`Diamonds`); `belot.bid.H` = „Купа“ (`Hearts`); `belot.bid.S` = „Пика“ (`Spades`); `belot.bid.N` = „Без коз“ (`No trumps`); `belot.bid.A` = „Всичко коз“ (`All trumps`); `belot.bid.X` = „Контра“ (`Double`); `belot.bid.R` = „Реконтра“ (`Redouble`); `belot.ann.s3` = „Терца“ (`Tierce`); `belot.ann.s4` = „Кварта“ (`Quarte`); `belot.ann.s5`, `.s6`, `.s7`, `.s8` = „Квинта“ (`Quint`); `belot.ann.c` = „Каре“ (`Four of a kind`); `belot.ann.c9` = „Каре деветки“ (`Four nines`); `belot.ann.cJ` = „Каре валета“ (`Four jacks`); `belot.ann.b` = „Белот“ (`Belote`); `belot.announce` = „Обяви: %s“ (`Announce: %s`); `belot.peek` = „Последна взятка“ (`Last trick`); `belot.contract` = „Игра: %s“ (`Contract: %s`); `belot.x2` = „%s, контра“ (`%s, doubled`); `belot.x4` = „%s, реконтра“ (`%s, redoubled`); `belot.by` = „каза %s“ (`called by %s`); `belot.score.us` = „Ние %d · Вие %d“ (`Us %d · Them %d`); `belot.score.watch` = „Долу и горе %d · Ляво и дясно %d“ (`Bottom and top %d · Left and right %d`); `belot.target` = „до 151“ (`to 151`); `belot.hang` = „висят %d“ (`%d hanging`); `belot.yourBid` = „Кажи игра или пас“ (`Bid or pass`); `belot.yourTurn` = „Твой ход“ (`Your turn`); `belot.waitFor` = „Изчакай %s…“ (`Waiting for %s…`); `belot.passed` = „Всички казаха пас. Раздава се отново.“; `belot.sum.points` = „Ние +%d · Вие +%d“ (`Us +%d · Them +%d`); `belot.sum.inside.us` = „Вътре сме!“; `belot.sum.inside.them` = „Вътре са!“; `belot.sum.hanging` = „Висяща: %d точки чакат следващата игра.“; `belot.sum.valat` = „Капо!“; `belot.sum.ann` = „%s: %s, %d“; `belot.sum.off` = „%s: %s (не се брои)“ (`%s: %s (does not count)`); `belot.match.us` = „Печелим партията!“; `belot.match.them` = „Те печелят партията.“; `belot.match.names` = „%s и %s печелят партията!“; `belot.left` = „%s стана от масата. Отборът му губи.“; `belot.dealer` = „разд.“ (`deal`). Where no English is pinned it is a faithful translation.

- [ ] **Step 1: Write the failing tests.** File scope: `setup()` = `guildWow()`, a parent frame of 532 × 328 under `UIParent`, `f = View.build(parent)`, `w.ns.client.act` replaced by a stub that records the action in `acts` and returns true; returns `w, View, f, acts`. `sess(state, seat)` as in Task 7 plus `tid = "t#1", epoch = 1, seq = 1, role = seat and "player" or "watcher"`; `draw(f, st, q)` = `View.update(f, sess(E.view(st, q), q))`. `shown(f)` = the sorted list of `b` whose `f.bidButtons[b]` is visible. `DECK_Q = deckOf("AC KC QC JC AS TS KD 9D", "AH KH 7H 8C JS 9S 7D 8D", "TH QH 9H 7C QS KS AD TD", "JH 8H 9C TC 7S 8S JD QD")` (seat 1 holds the кварта: `AC` is deck index 1).

```lua
it("the auction shows only the legal bids; a click bids; the others' bids are bubbles", function()
  local w, View, f, acts = setup(); local st = E.new {}; ok(E.apply(st, 0, { k = "deal", deck = DECK_A })); draw(f, st, 1)
  eq(shown(f), { "A", "C", "D", "H", "N", "P", "S" }); eq(f.text:GetText(), "Кажи игра или пас"); eq(#f.myFan.cards, 5)
  eq(f.bidButtons.C.points[1], { "TOPLEFT", f, "TOPLEFT", 180, -60 }); eq(f.bidButtons.R.points[1], { "TOPLEFT", f, "TOPLEFT", 268, -116 })
  w:click(f.bidButtons.H); eq(acts, { { k = "bid", b = "H" } })
  ok(E.apply(st, 1, { k = "bid", b = "H" })); ok(E.apply(st, 2, { k = "bid", b = "X" })); draw(f, st, 3)
  eq(shown(f), { "A", "N", "P", "R", "S" }); eq(f.bidButtons.P.text:GetText(), "Пас"); eq(f.bidButtons.R.text:GetText(), "Реконтра")
  eq({ f.bubbles[2].text:GetText(), f.bubbles[3].text:GetText() }, { "Купа", "Контра" })       -- seat 1 is my partner on top, seat 2 on my left
  eq({ f.bubbles[0]:IsVisible(), f.bubbles[1]:IsVisible() }, { false, false })
  draw(f, st, 1); eq(shown(f), {}); eq(#w:texts("Изчакай "), 1)
end)
it("„Обяви“ sends the engine's set and shows no bubble until the table recorded it", function()
  local w, View, f, acts = setup(); local st = started(DECK_Q, "S P P P"); draw(f, st, 1)
  ok(f.announceButton:IsVisible()); eq(f.announceButton.text:GetText(), "Обяви: Кварта"); eq(f.bubbles[0]:IsVisible(), false)
  w:click(f.announceButton); eq(acts, { { k = "ann", a = { { t = "s4", i = 1 } } } }); eq(f.bubbles[0]:IsVisible(), false)
  ok(E.apply(st, 1, acts[1])); draw(f, st, 1); eq(f.announceButton:IsVisible(), false); eq(f.bubbles[0].text:GetText(), "Кварта")
  draw(f, st, 3); eq(f.bubbles[2].text:GetText(), "Кварта"); eq(f.announceButton:IsVisible(), false)
end)
it("cards I may not play are dimmed; a click plays, with the belote when it is one", function()
  local w, View, f, acts = setup(); local st = started(DECK_A, "S P P P"); plays(st, "AH"); draw(f, st, 2)
  eq({ f.myFan.cards[1].mode, f.myFan.cards[4].mode, f.myFan.cards[4].face, f.myFan.cards[4].y }, { "dim", "raised", "TH", 8 })
  w:click(f.myFan.cards[1].frame); eq(acts, {}); w:click(f.myFan.cards[4].frame); eq(acts, { { k = "play", i = 2, c = "TH" } })
  plays(st, "9H 8H TS AC 8C 7C 9C KC 9S"); draw(f, st, 2); eq(f.myFan.cards[6].face, "QS")
  w:click(f.myFan.cards[6].frame); eq(acts[2], { k = "play", i = 18, c = "QS", b = true })
end)
it("the trick lies in a cross by seat; „Последна взятка“ shows the last one until the table moves", function()
  local w, View, f = setup(); local st = started(DECK_A, "S P P P"); plays(st, "AH 9H 8H TS AC 8C"); draw(f, st, 1)
  eq({ f.trick[3].face, f.trick[0].face }, { "AC", "8C" }); eq({ f.trick[1].frame:IsVisible(), f.trick[2].frame:IsVisible() }, { false, false })
  eq(f.trick[2].frame.points[1], { "TOPLEFT", f, "TOPLEFT", 246, -56 }); eq(f.trick[1].frame.points[1], { "TOPLEFT", f, "TOPLEFT", 292, -89 })
  w:click(f.peekButton); eq({ f.trick[0].face, f.trick[1].face, f.trick[2].face, f.trick[3].face }, { "AH", "9H", "8H", "TS" }); eq(f.trick[0].mode, "dim")
  local s = sess(E.view(st, 1), 1); s.seq = 2; View.update(f, s); eq(f.trick[3].face, "AC")       -- an event closes the peek
  --[[ in the auction and in trick 1 the peekButton is hidden ]]
end)
it("the score, the contract and the deal's summary: вътре, контра, an announce that did not count", function()
  --[[ the first res of Task 7's summary test, drawn for seat 1 with seats {A, B, C, D}: one visible „Ние 32 · Вие 0“ and „до 151“;
  f.summary:GetText() (colour codes stripped) has the lines „Игра: Купа, контра  каза Мария Стоянова“, „Ние +32 · Вие +0“, „Вътре са!“,
  „Иван Петров: Терца, 20“, „Мария Стоянова: Терца (не се брои)“, „Пешо Тодоров: Белот, 20“ in that order; no trick card is visible.
  With st.hang = 9: „до 151 · висят 9“. Mid-play (started(DECK_A, "S P P P")): f.contract shows „Игра: Пика“ and „каза Иван Петров“,
  f.summary is hidden. View.seatNote(sess, 4) == „разд.“ and "" for seat 1; "" for every seat in phase "match".
  f.summary is 170 wide and its font size is 11. A leaver: draw(f, st, 1) with seats { A, B, C, D } (f.names is filled), then
  st.phase, st.winner, st.left = "match", 2, 3 and sess.seats[3] = false, draw again: f.text:GetText() (colour codes stripped) == „Kiro Barley стана от масата. Отборът му губи.“ ]]
end)
it("a watcher sees backs, no button and the teams by place", function()
  --[[ draw(f, st, nil) on E.view(started(DECK_A, "S P P P"), 0): eight cards in f.myFan, every face nil; shown(f) == {}; announceButton hidden;
  one visible „Долу и горе 0 · Ляво и дясно 0“ ]]
end)
it("solo with three bots from a real deal: my five cards face up, my bid stands, three more cards come", function()
  --[[ withBots(); I open Белот „Само поканени“ and invite the three bots through the „Покани“ picker (w:advance(2) after each); w:advance(2).
  V = TableFrame.built.belot; s = client.session: #s.state.hands[1] == 5; V.myFan.cards[1..5] have faces; the plate of seat 3 is at 183.5, −10.
  w:click(V.bidButtons.S); w:advance(8): s.state.phase == "play", s.state.contract == { seat = 1, b = "S", x = 1 } (bots never outbid spades),
  eight faces in V.myFan, v.fairLine hidden or grey (no verdict yet), TableFrame.view.info.topic == "belot" ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/ui/belot_test.lua`.** Expected: FAIL (no view registered for `belot`).
- [ ] **Step 3: Implement**; TOC line `ui/games/BelotView.lua` after `ui/games/BelotModel.lua`.
- [ ] **Step 4: Run the file, then `bash t.sh`.** Expected: `7 passed, 0 failed`; all pass (the locale key sets of bg and en are identical).
- [ ] **Step 5: Commit.** `git add ui/games/BelotView.lua locale/bg.lua locale/en.lua TavernGames.toc tests/ui/belot_test.lua` — `feat(ui): Белот table view`

### Task 9: Rules-book topic „Белот“

**Files:**
- Modify: `core/Help.lua`, `locale/bg.lua`, `locale/en.lua`; Test: `tests/core/locale_help_test.lua`, `tests/ui/book_test.lua`

**Interfaces:**
- Produces: `ns.Help.topics` ids `{"hall", "ttt", "deathroll", "santase", "belot", "fair", "soon"}`. Topic `belot` (title `game.belot`), blocks in this order: `p1`, `example`, `bids`, `contra`, `cards` (kind `cards`, `JH 9H AH TH KH QH`), `trick`, `announce` (kind `cards`, `9H TH JH`), `belote` (kind `cards`, `KS QS`), `score`, `valat`, `time`, `fair`. The quoted-label test also covers `^help%.belot%.`.
- Locale: the `help.belot.*` keys go in a new section `-- Rules book: Белот` after `-- Rules book: Сантасе` in both locale files. Pinned bg (en = faithful translations in the same simple tone, quoting the English labels of Task 8):
  - `help.belot.p1` = „Белот се играе от четирима, двама срещу двама. Партньорът ти седи срещу теб. Играе се с 32 карти, от седмица до асо. Печели отборът, който пръв мине 151 точки.“
  - `help.belot.example` = „Иван, Мария, Kiro и Пешо сядат на маса. Иван и Kiro са един отбор, Мария и Пешо са другият. Всеки получава пет карти. Иван държи вале и деветка купа и казва „Купа“. Мария казва „Пас“, Kiro и Пешо също. Играта е на купа. Всеки получава още три карти и Иван играе пръв.“
  - `help.belot.bids` = „Игрите по сила са спатия, каро, купа, пика, после „Без коз“ и най-силната „Всичко коз“. Можеш да кажеш само по-силна игра от вече казаната, или „Пас“. Наддаването свършва, когато след казана игра трима подред кажат „Пас“. Ако и четиримата кажат „Пас“, картите се раздават отново.“
  - `help.belot.contra` = „Противникът е казал игра, а ти мислиш, че ще го биеш? Натисни „Контра“ и точките се броят двойно. Неговият отбор може да отвърне с „Реконтра“ и тогава са четворни. При контра всичките точки от раздаването взима отборът, който е събрал повече.“
  - `help.belot.cards` = „Козовете по сила: вале 20 точки, деветка 14, асо 11, десетка 10, поп 4, дама 3. В другите бои най-силно е асото: асо 11, десетка 10, поп 4, дама 3, вале 2. На „Всичко коз“ всяка боя е коз. На „Без коз“ козове няма и точките се броят двойно.“
  - `help.belot.trick` = „Отговаряш на боята, ако имаш от нея. На коз трябва и да качиш, ако можеш. Нямаш от боята? Цакаш с коз, освен ако взятката в момента е на партньора ти. Ако вече е цакано, надцакваш, когато можеш. Картите, които не може да играеш, са потъмнени. С бутона „Последна взятка“ виждаш последните четири карти.“
  - `help.belot.announce` = „Три поредни карти от една боя са терца: 20 точки. Четири са кварта: 50. Пет и повече са квинта: 100. Четири еднакви карти са каре: 100 точки, каре деветки 150, каре валета 200 (седмици и осмици не се броят). Обявяваш на първата си карта: появява се бутон, натискаш го и после играеш. Обявата излиза като балон до името ти. Ако и двата отбора имат поредни карти, броят се само на отбора с по-силните, а при равни не се броят на никого. Същото важи и за каретата. На „Без коз“ обяви няма.“
  - `help.belot.belote` = „Поп и дама от коза в една ръка са белот: 20 точки. Не натискаш нищо. Щом изиграеш едната от двете, аддонът го казва сам.“
  - `help.belot.score` = „Накрая всеки отбор брои картите във взятките си, обявите си и 10 точки за последната взятка. Сборът се дели на десет и се записва. Ако отборът, казал играта, има по-малко от другия, той е вътре: всичко отива при противника. При равни точки играта е висяща: точките на казалия чакат и ги взима отборът, който спечели следващото раздаване.“
  - `help.belot.valat` = „Отбор, който вземе всичките осем взятки, прави капо и получава 90 точки отгоре. С капо обаче партия не се затваря: трябва да минеш 151 в раздаване без капо.“
  - `help.belot.time` = „Ако времето ти изтече при наддаването, аддонът казва „Пас“. Ако изтече при игра, той обявява каквото държиш и играе най-слабата ти позволена карта. Ако някой стане от масата или го няма повече от три минути, партията свършва и неговият отбор губи. Щом някой седне на свободния стол, започва нова партия. След нормален край домакинът натиска „Нова игра“.“ (en the same; the quote count is kept.)
  - `help.belot.fair` = „Под масата пише дали последното раздаване е „проверена“ игра. Раздава всеки път следващият по ред, както на истинска маса.“
  - `help.soon.p` = „Скоро идват Табла и Тексас Холдем, и игра на залог с тефтер на дълговете.“; `help.soon.example` = „Засега в кръчмата се играят Морски шах, Death Roll, Сантасе и Белот. Другите игри стоят бледи в списъка, с надпис „Скоро“. Щом станат готови, правилата им ще се появят тук, в книжката.“

- [ ] **Step 1: Write the failing tests.**

```lua
-- tests/core/locale_help_test.lua: topics are {"hall","ttt","deathroll","santase","belot","fair","soon"}; the belot topic has exactly three
-- cards blocks, {"JH","9H","AH","TH","KH","QH"}, {"9H","TH","JH"} and {"KS","QS"}, every face in ns.Engines.belot.DECK;
-- the quoted-label loop also covers ^help%.belot%. and finds at least 12 labels there in each language;
-- pinned: T.bg["help.belot.contra"], T.bg["help.belot.time"], T.bg["help.soon.p"], T.bg["help.soon.example"] equal the strings above;
-- T.en["belot.bid.X"] == "Double"; T.en["belot.peek"] == "Last trick".
-- tests/ui/book_test.lua
it("the Белот topic draws its cards and is listed between Сантасе and the fair deal", function()
  --[[ the topic list reads hall, ttt, deathroll, santase, "belot=Белот", fair, soon; B.open("belot"): the page holds 11 card widgets, the first
  with rank text "J" in red (JH), the last two "K" and "Q" in the ink colour (KS, QS); HelpBook.current == "belot" ]]
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/locale_help_test.lua tests/ui/book_test.lua`.** Expected: FAIL (the topic is missing; `help.soon.p` still names Белот).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run both files, then `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit.** `git add core/Help.lua locale/bg.lua locale/en.lua tests/core/locale_help_test.lua tests/ui/book_test.lua` — `feat(ui): rules-book topic for Белот`

### Task 10: In-game check list and documentation

**Files:**
- Create: `docs/superpowers/notes/2026-11-stageC-ingame-checks.md`; Modify: `docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md` (`### Shared contracts`: a subsection „Stage C additions“), `docs/superpowers/notes/engine-contract.md` (the committed copy; „Addendum 4 (stage C)“: `E.dealer`, `E.bot`, `E.announce`, Belot's view keeps the played cards, `E.auto` plays the lowest card, and that PC1 amends PB8 for Belot: `E.nextFirst` rotates the deal across matches, the previous loser does not lead)

**Interfaces:** none. The notes file holds the table below with a `Result` column, every row `not yet measured`. Nothing is marked passed on the strength of the unit tests.

- [ ] **Step 1: `bash t.sh`.** Expected: `N passed, 0 failed`.
- [ ] **Step 2: Write the notes file** (`/console scriptErrors 1` throughout; rows 11–17 need four characters at one table, rows 15 and 17 a fifth as a watcher):

| # | Check | What to look for |
|---|---|---|
| 1 | `/tavern bots`, open Белот „Само поканени“, invite the three bots | four plates around the felt, my own at the bottom, the bot opposite me is my partner; five cards face up within about two seconds; „разд.“ on the plate of the seat before the first bidder |
| 2 | `/tavern bots host belot`, sit down | two more bots sit within a few seconds and the deal starts |
| 3 | my turn in the auction | only the legal bids have buttons; after a bot's bid the weaker suits are gone; „Контра“ appears only over an opponent's game |
| 4 | let the auction clock run out | my client says „Пас“; with everybody passing the cards are dealt again by the next seat |
| 5 | win the auction | three more cards arrive; the game and who called it stand top left; the score top right |
| 6 | trick 1 with a терца or better in hand | the „Обяви: …“ button; after the click a bubble at my plate; a bot's announce is a bubble at its plate; bubbles are gone after the second trick |
| 7 | play the king or queen of trumps holding both | a „Белот“ bubble without pressing anything |
| 8 | a trick where I must follow or trump | the cards I may not play are dimmed and do nothing; the four cards of the trick lie towards their players; „Последна взятка“ shows the previous four |
| 9 | the end of a deal | the summary: game, both sides' points, „Вътре сме!“ / „Вътре са!“ when it happens, every announce with its points or „(не се брои)“; under the felt „Последната ръка: проверена“ |
| 10 | play to 151 (about 13 deals) | „Печелим партията!“ or „Те печелят партията.“, one result, „Нова игра“ starts a match with the deal one seat further; ⓘ opens „Белот“ with the card pictures |
| 11 | four characters at one table | everyone gets cards; no trace shows another player's hand; „… раздава…“ names the seat marked „разд.“; all four read „проверена“ |
| 12 | контра and реконтра between real players | the buttons appear for the right team only; the summary shows the doubled points for the side with more |
| 13 | a player who is not the dealer `/reload`s mid-deal | the cards are back within about two seconds; the trick and the score are right; the deal reads „не съм я гледал цялата“ for that player only and is scored without the „resynced“ banner |
| 14 | the dealer `/reload`s mid-deal | „Ръката е анулирана от <name>. Раздава следващият.“ on all four; the next player deals (PB6b); no point moved |
| 15 | a player logs out on its turn | nothing is played or bid for it; back within three minutes: play goes on; after three minutes it is stood up, „… стана от масата. Отборът му губи.“, the banner „Играта е прекъсната.“; a new player on the free chair starts a new match |
| 16 | a player presses „Стани“ mid-deal | the same ending at once; the result names the two winners |
| 17 | a watcher from the start, and one who comes mid-deal | backs only, no buttons, „Долу и горе … · Ляво и дясно …“; its trace has no card that was not played |
| 18 | count the whispers of one deal with `/tavern debug` (four players, no watcher) | the host sends about 140 addon whispers per deal (about 46 events to three members), each other player about 12; during the shuffle about 20 leave the host within a second: no visible ChatThrottleLib delay, no deal that hangs at „Разбъркваме заедно…“ |
| 19 | the table at UI scale 0.65 and 1.0 | nothing overlaps on the 532 × 328 felt: the side plates and the bid buttons, the bubbles and the trick, my fan and my plate, the fairness line |

- [ ] **Step 3: Update the two documents**: the stage 1 plan's Shared contracts gets this plan's three contract items (engine options, the action table, the `"result"` fields) under „Stage C additions“; the engines contract (`docs/superpowers/notes/engine-contract.md`) gets Addendum 4, including the PB8 note for Belot's `E.nextFirst`.
- [ ] **Step 4: Report to the user** which rows need four characters, that bots never double (row 12 cannot be seen solo), and the decisions of the Self-review.
- [ ] **Step 5: Commit.** `git add docs/superpowers/notes/2026-11-stageC-ingame-checks.md docs/superpowers/plans/2026-11-20-stage1-platform-tictactoe.md docs/superpowers/notes/engine-contract.md` — `docs: stage C in-game check list and contract additions`

---

## Self-review (applied)

- **Spec coverage:** 5.3 Белот (four players, two teams, to 151, the rule list) → the engine as merged, unchanged in its rules (Tasks 1–2 add contract functions only; the 60 parity matches stay green); „Обявите се показват като балон над играча“ → Tasks 7–8; valid cards raised, invalid dimmed → Tasks 7–8; 5.3а topic in bg/en with tavern talk and card pictures → Task 9; 6.2 timeout = automatic action, lowest valid card → Task 2 (`E.auto`), Task 3 (the auction clock); 6.3 step 1 „раздаващият се ротира по реда на местата, като в Белот“ → Tasks 1 and 3 (`E.dealer`); steps 2–5 with n = 4 → stage B's code, exercised in Task 3; „dealer leaves mid-hand → annulled“ → Task 4; 6.5 bots and trace → Task 5, check list rows 1–2, 18; roadmap „team seats, team score, team result“ → Tasks 4, 6–8; ruling B4 (bots must bid) → Tasks 2, 5; ruling G1 (flip the flag) → Task 3.
- **Verified before writing:** the stage B code was run in the simulator with a throwaway patch of the engine (fair contract, void, the view rule) and no other change: a four-player match with a watcher ran to 155:81 in 13 deals, every deal „проверена“ on all five clients, no resync; four idle players passed a deal out at 45-second steps and were dealt again; a stand, three minutes offline and the dealer's relog behaved as Task 4 pins them; without the view rule a player who relogged after an announce resynced at the score, with it he did not; the numbers `{252, 0}` → `{25, 0}` and `{0, 252}` → `{0, 50}`, every `E.auto` / `E.bot` vector of Task 2, and „300 bot deals, none passed out“ come from those runs. Not run (they need the code of Tasks 1–3): the dealer sequence `{4, 1, 2, 3}` and everything in `ui/`.
- **Decisions the plan makes beyond the spec (the user may contest):**
  1. **The fair dealer is the Belot dealer.** `E.dealer` lets the engine name the seat (the one before the first bidder); it still rotates strictly by seat and depends on nothing a player can influence, which is what ruling PB2 was about. The deal keeps going round into the next match instead of restarting at seat 2. A void passes the deal on (PB6b), so a dealer cannot re-deal a hand it dislikes by reloading.
  2. **Nobody acts for an offline player, not even a pass.** The table waits up to three minutes, then he is stood up, the match ends and his team loses (spec 5.4's forfeit without money). The host could pass for him in the auction, but his card turn would stall the table anyway, and it would need an edit of `core/Session.lua`, which has one line of room.
  3. A player who stands up ends the match for his team at once; the short table is then „прекъсната“ and that last deal gets no fairness verdict (stage B behaviour for Сантасе, kept). A new fourth player starts a new match without „Нова игра“.
  4. **A timeout plays the lowest legal card** (and first announces everything held) instead of the engine's earlier „first or random“ card.
  5. **One „Обяви“ button declares everything** the engine offers (a four before a sequence through it); not announcing is possible by not pressing, choosing a part is not. The belote is always declared with the card.
  6. Announce bubbles show the kind only, stay through the second trick, and the height of a sequence is never said aloud; which announces counted is shown in the deal's summary.
  7. **Bots bid suits only, never double**, and the fourth to speak always bids; контра and реконтра can be seen only with real players.
  8. A view now keeps every card played in the deal (the table saw them); the UI still shows only the last trick. This is the one change to what a Belot view contains.
  9. A bot host fills its table with idle bots once somebody sat down, so `/tavern bots host belot` and `invite belot` are usable alone.
  10. The table frame keeps its 560 × 420 size; the four plates, the trick, the bid buttons and the fan share a 532 × 328 felt (check list row 19).
- **Step scan:** every task has failing tests with exact values, an expected failure, an implement step with files, signatures and pinned values, both run commands, and a commit with exact paths. Task 4 says openly that three of its five tests pass before its one-function change: they are the regression pins of Review Focus 3 and 5 and of the void.
- **Type and name consistency:** `E.dealer`, `E.nextFirst`, `E.announce`, `E.bot`, `E.BOT_BID`, `E.BOT_LUCK` in Tasks 1, 2, 3, 5, 7, 8 and the contract; `dealerFor(s, p)` only in Task 3; `"result"` fields `left`, `names` and the session field `seatedBefore` in Task 4, the contract and Task 5; `HallLayout.ring(n, w, h, me)` and `view.ring` in Tasks 6 and 8; `ns.BelotModel.build(s, peek, names)` with fields `me, seated, team, pos, mine, hand, bids, announce, trick, peeking, canPeek, bubbles, contract, dealer, score, summary, text` in Tasks 7 and 8; widget names `myFan, trick, bidButtons, announceButton, peekButton, bubbles, contract, score, summary, text` in Task 8 and its tests; locale prefix `belot.` and bid letters `P C D H S N A X R`, announce kinds `s3…s8 c c9 cJ b` throughout; topic id `belot`.
- **Review Focus:** each of the five has named tests in Tasks 2, 3, 4, 7 and 8.
- **Proportion:** the engine and core changes are small and given as signatures with pinned values; the bot heuristic and the model's bubble rule are spelled out because the tests alone do not determine them; the view is positions, labels and tests. C1 (Tasks 1–5) is complete and testable without any UI; C2 adds no protocol or engine rule.
