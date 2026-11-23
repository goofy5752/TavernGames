# Stage F4: „Класация“, „История“, ledger retention — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The tabs „Класация“ and „История“, both derived from the guild ledger under a stated trust rule; a retention rule that bounds the ledger without ever touching a balance or the sync's convergence; the last polishing.

**Architecture:** Two pure derivations over `core/LedgerView.lua` (`core/LedgerStats.lua`, `core/LedgerHistory.lua`), two tabs on a shared virtual list (`ui/BookList.lua`, `ui/BoardTab.lua`, `ui/HistoryTab.lua`). Retention turns an old `R`/`S` body into a **stub** (`"<n>.<h>"`, saved) that my vector, digest and `LID` lists keep counting as held, exactly as a remembered refusal does today (`core/LedgerRefused.lua` is the model), so pruning is invisible to every partner that holds the entry in either form. No wire change of any kind.

**Tech Stack:** Lua 5.1, the WoW Forever client, the repo's own test runner (`bash t.sh [files]`; baseline at `ca7581f`: 1889 passed).

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (5.6, 6.4, 9); `docs/superpowers/plans/2026-11-23-stakes-roadmap.md` (F4, "The one rule"); `docs/superpowers/notes/engine-contract.md` Addenda 8–10; `docs/superpowers/notes/2026-11-21-rulings.md` (F1–F3).

## Global Constraints

- Protocol stays `v=1`, prefix `TAVG`, GUILD + WHISPER only. **F4 adds no message, no field, no entry kind.** Fun tables stay byte-identical; an F1–F3 client must see nothing new.
- Retention never stubs a `D`, `C`, `N`, `P` or `X`. Every balance (`View.net`, `View.gross`, `View.rows`, `View.totals`) is identical before and after a prune.
- A stub counts as held in `x`, in `n` (`Store:reach`), in the digest and in a `LID` list. A prune changes no `x`, no digest, sends no `HI`.
- Bulgarian strings in „…“ quotes; every new locale key in both `locale/bg.lua` and `locale/en.lua` (the parity test of `tests/core/locale_help_test.lua` must stay green).
- File caps live in `tests/toc_test.lua` (`the big files keep their limits`); measure with `wc -l` before and after every task. Current: `LedgerHash.lua` 150 (< 160), `LedgerStore.lua` 231 (< 260), `LedgerSync.lua` 285 (< 300), `LedgerSyncVector.lua` 115 (< 160), `LedgerSyncPage.lua` 98 (< 200), `LedgerNet.lua` 216 (< 240), `LedgerView.lua` 205 (< 260). New files get a cap in the task that creates them, and a line in `TavernGames.toc` (the test `lists every source file` fails otherwise).
- Every task ends with `bash t.sh` whole and green, then one commit. No push, no merge.
- Tests use the runner's globals `describe`, `it`, `eq`, `ok`; store-level tests follow `tests/core/ledger_view_test.lua` (`Ledger.new({}, me, function() return NOW end)`), sync tests follow `tests/core/ledger_sync_test.lua` (`require("sim")`, its helpers `world`, `give`, `hello`, `whispers`, `entries`, `digests`), UI tests follow `tests/ui/ledger_tab_test.lua` (`Wow.new{ ui = true }`, `readyWow`, `entry`).

## Decisions (the user was not available; each with its cost)

- **Decision T (the trust rule: which `R`/`S` count).** An `R` or `S` is its author's claim. It counts **per player**, never as a whole:
  1. Denied (`X`) and uncounted (`un`) entries count for nobody (the view already drops them). They stay visible in „История“ as „отречено“.
  2. **For fun** (`R` without `sk`): counts for the players it names only when its author is one of them (a seated host). An outsider's `R` counts for nobody.
  3. **Staked** (`R` with `sk`, losers named): a loser's loss counts only on that loser's own word (a **confirmed** debt of that `gid` with it as `f`, or it wrote the `R` itself); a winner's win counts only on a debtor's word (a confirmed debt of that `gid` with it as `t`). A seat in neither list counts a draw once any debt of the `gid` is confirmed. Pending and contested debts back nothing.
  4. **Холдем** (`S`): the sitting counts for `f` when a confirmed debt of that `gid` names `f`, or `f` wrote the `S`; won or lost is the sign of `f`'s confirmed copper at that `gid`, never the `S`'s `w`/`l`.
  5. A name counts **once per `gid`**; `R`s of one `gid` with the same `g`, `n`, `w`, `l` are one game.
  6. **Gold net is read from confirmed debts only**, never from `R`/`S`. „Кралят/Кралицата на механата“ is the highest positive gold net of the period; only when nobody has one, the most wins among players with at least 5 games.
  - Cost: a modified client that hosts can still write fun results that never happened (wins for itself, losses for whoever it names); they carry its name („по думите на …“ in „История“) and can take the crown only in a period where no gold moved. The cure not taken: every player's client writing its own witness `R` and counting only agreeing pairs. That triples the `R` traffic of fun tables (which must stay byte-identical) and touches `core/Stakes.lua` (335 of 340 lines).
- **Decision R (retention).** Only `R` and `S` bodies are ever dropped, and never erased: a dropped body leaves a **stub** `store.st[author]["<n>.<h>"] = true` that counts as held everywhere the sync looks. Rules, run once per session `LEDGER_PRUNE_WAIT` after login:
  1. Age: an `R`/`S` of another author with `at < now - LEDGER_KEEP` (365 days) becomes a stub.
  2. Cap: an author (me included) holding more than `LEDGER_AUTHOR_MAX - LEDGER_AUTHOR_ROOM` (4500) `R`+`S` bodies has its oldest (by `at`, then number) stubbed down to that count, whatever their age. Stubs do not count against the cap.
  3. My own entries are stubbed only by rule 2: the author stays the place an old entry can still be fetched from.
  4. Never stubbed: an id with twins, an `un` body, any other kind.
  - Why stubs and not deletion: two clients with different retention states have the same `x`, `n` and digest, so nothing is exchanged and an old (F1–F3) client that keeps everything is equal to a pruned one. A deleted entry would make `x` differ from every unpruned holder forever.
  - Cost 1: a stub is about a fifth of a body, not zero; the store still grows, by about 40 bytes per game older than a year. „Всичко“ in „Класация“ counts games of the last 365 days (gold net is all-time, it rests on debts).
  - Cost 2 (the one case that does not converge): a client that never got an entry which every online holder has already stubbed (a reinstall or a newcomer after the entry's author left, or a forger's `R` dated a year back) cannot fetch it from them. Its `x` for that author stays different. **Bounded, not cured:** a stub holder remembers per peer the highest number it sent of such an author (`Sync:tail`, this session) and sends only what is newer, so nothing is resent; what remains is the vector exchange on a digest difference, which `Sync:fixed` already limits (Addendum 8, residual 22). The cure needs a wire message that carries stubs: not taken (no protocol change).
  - Cost 3: five versions of one id of which one is stubbed: a pruned client refuses the fifth (the stub counts toward the 4), an unpruned one may evict the stubbed body instead; the two then differ on that author (`Sync:fixed`). Only a deliberate forgery reaches it.
- **Decision M5 (`L.il`).** The kept sorted list of an author whose newest entry is older than `LEDGER_IL_IDLE` (30 days) is dropped once its `x` is hashed. Cost: the next change of such an author sorts its list again, in slices (the F2 mechanism).
- **Decision P (periods).** „Седмица“ = the last 7 × 86400 s, „Месец“ = the last 30 × 86400 s, by my clock against the entry's `at`. Cost: rolling windows, not calendar ones.
- **Decision K (the title).** The label reads „Кралят/Кралицата на механата“ as the spec writes it: no client knows another character's sex without a new `HI` field.
- **Decision G (the game filter)** is one button that cycles „Всички игри“ → each game of `ns.Games.list`; no dropdown widget is built.
- **Left open (not built):** Addendum 8 residual 21 (first names in the bill), residual 20 (payment questions lost on `/reload`); every check-list row that reads "not yet measured".

## Review Focus

1. A saved `st` table that is not what I wrote (not a table, a row `"x.y"`, a 15-hex hash, a stub whose body the store also holds): the load drops the row, raises nothing. → Task 1.
2. An `R` whose `n` holds `false` (an empty chair) or whose `w`/`l` name a seat with no name or above `#n`: skipped seat, no error, no row for `false`. → Task 3.
3. No guild (`client.ledger == nil`) and an empty ledger: both tabs show their empty line. → Tasks 5, 6.
4. An entry dated up to an hour ahead of my clock (`LEDGER_FUTURE`): it is inside every period. → Task 3.
5. 3000 history lines: one sort, at most `ROWS` row widgets. → Task 6.

## File Structure

| File | Role |
|---|---|
| `core/LedgerStub.lua` (new) | stubs: load, `Store:stub`, `Store:prune`, `Net:prune` |
| `core/LedgerStats.lua` (new) | the trust rule; the counted games; the board; head-to-head |
| `core/LedgerHistory.lua` (new) | the chronology of games, payments and denied entries |
| `ui/BookList.lua` (new) | the virtual row list both new tabs share |
| `ui/BoardTab.lua`, `ui/HistoryTab.lua` (new) | the tabs |
| `core/LedgerStore.lua`, `LedgerHash.lua`, `LedgerSyncPage.lua`, `LedgerSyncVector.lua`, `LedgerSync.lua`, `LedgerNet.lua`, `LedgerView.lua`, `Const.lua` | the hooks named in each task |

TOC order: `core/LedgerStub.lua` after `core/LedgerRefused.lua`; `core/LedgerStats.lua`, `core/LedgerHistory.lua` after `core/LedgerView.lua`; `ui/BookList.lua` after `ui/Widgets.lua`; `ui/BoardTab.lua`, `ui/HistoryTab.lua` after `ui/LedgerTab.lua` (the tab order becomes Зала, Тефтер, Класация, История, Настройки).

---

### Task 1: Stubs in the store

**Files:**
- Create: `core/LedgerStub.lua`, `tests/core/ledger_keep_test.lua`
- Modify: `core/Const.lua`, `core/LedgerStore.lua` (`Ledger.new`, `Store:add`), `core/LedgerHash.lua` (`Store:items`, `Store:reach`, `Store:vector`, the end of a job in `Store:work`), `TavernGames.toc`, `tests/toc_test.lua` (cap `core/LedgerStub.lua` < 160)

**Interfaces:**
- Produces (all on `ns.Ledger.Store`):
  - `Store:stubLoad()` — called in `Ledger.new` **after** the bodies are filed. Keeps `store.st[a][it]` only when `a` is a name (as `named` in `LedgerRefused.lua`), `it` matches `^([1-9]%d*)%.(%x+)$` with at most 9 digits and a 16-hex `h`, the value is `true`, and no body `(a, n, h)` is held. Builds `L.sn[a][n] = count`, raises `L.top[a]`, sets `L.dirty[a] = true`.
  - `Store:stubbed(a, n, h) -> boolean`; `Store:stubs(a) -> {{n, h}}` (no order); `Store:stubTop(a) -> number` (0 without one); `Store:stubCount() -> number` (all authors).
  - `Store:stub(b) -> boolean` — body `b` becomes a stub: only `k` `R`/`S`, not `b.un`, its id holds exactly one body and no stub. It calls `self:index(a, n, b, -1)`, clears `store.ev[a][n]`, writes `store.st`, `L.sn`, `L.rev = L.rev + 1`. It does **not** call `Store:stale` (the item `"<id>:<h>"` stays in `x` and in `L.il`) and leaves `L.run[a]` as it is.
  - `Store:prune(now, max) -> count, more` — Decision R rules 1–4, at most `max` stubs a call; `more` is true when candidates are left.
- Constants (`core/Const.lua`): `LEDGER_KEEP = 31536000`, `LEDGER_AUTHOR_ROOM = 500`, `LEDGER_PRUNE_WAIT = 60`, `LEDGER_PRUNE_STEP = 500`, `LEDGER_IL_IDLE = 2592000`.

- [ ] **Step 1: Write the failing tests** in `tests/core/ledger_keep_test.lua` (a `book()` as in `ledger_view_test.lua`, plus `b.result(author, n, at)` = an `R` `{gid = "Иван Петров#1/" .. n, g = "ttt", n = {I, M}, w = {1}, l = {2}}`; `OLD = NOW - C.LEDGER_KEEP - 10`):

```lua
it("a prune changes no x, no n, no digest and no balance", function()
  local b = book()
  local h = {}
  for n = 1, 6 do h[n] = b.result(M, n, OLD).h end
  local d = b.debt(M, I, M, 50000, G1, 7, OLD); b.confirm(I, d); b.pay(M, I, 20000)
  local v0, dg, cell = b.view(), b.l:digest(), b.l:vector()[M]
  local net, open = View.net(v0, I, M), View.totals(v0).open
  local n, more = b.l:prune(NOW, 100)
  eq(n, 6); eq(more, false)
  eq(b.l:digest(), dg); eq(b.l:vector()[M].n, cell.n); eq(b.l:vector()[M].x, cell.x)
  eq(View.net(b.view(), I, M), net); eq(View.totals(b.view()).open, open)
  ok(b.l:get(d.i))
  for n = 1, 6 do eq(b.l:get(Ledger.id(M, n)), nil); ok(b.l:stubbed(M, n, h[n])) end
end)
```

  Further cases, one `it` each:
  - `only R and S are ever stubbed`: a year-old `D`, `C`, `N`, `P`, `X` each survive `prune`; `Store:stub` on each returns `false`.
  - `a stubbed entry offered again is a dup and files no body`: `b.l:add(sameEntry, "Някой")` → `"dup"`; `b.l:get(id) == nil`; `rev` unchanged.
  - `my own entries stay until the cap`: 3 own year-old `R` (made with `b.l:make`) survive; with `C.LEDGER_AUTHOR_MAX` lowered to 10 and `LEDGER_AUTHOR_ROOM` to 4 for the test (restore after), 10 fresh own `R` → `prune` stubs the 4 oldest, `L.rc[me] == 6`, and an 11th `make("R", …)` succeeds.
  - `the cap rule frees another author too, oldest first`.
  - `an id with twins and an un body are never stubbed`.
  - `a twin that comes to a stubbed id counts the stub toward the four`: after 3 more versions the next is refused `"twins"`.
  - `stubs survive a save and a load`: `Ledger.new(b.l.store, me, clock)` → same digest, same vector, `stubbed` true, `seen(M) == 6`, `rc[M] == 0`.
  - `an author of stubs only keeps its cell`: all of `M` stubbed, reloaded → `vector()[M].n == 6`.
  - **Review Focus 1** `a tampered st is dropped row by row`: `store.st = 5`; `store.st = { [M] = { ["x.y"] = true, ["3." .. ("a"):rep(15)] = true, ["2." .. h2] = 1 } }`; a stub for a body that is held → after `Ledger.new` no error, `stubCount() == 0`, the digest equals an untouched twin store's.
  - `max bounds one call`: 6 candidates, `prune(NOW, 4)` → `4, true`; again → `2, false`.
  - `an idle author's kept list is dropped once hashed, an active one's is kept` (Decision M5): after `L:work()` `L.il[M] == nil` for an author whose newest `at` is `NOW - C.LEDGER_IL_IDLE - 1`, a table for one at `NOW`; a later body of the idle author still gives the `x` a fresh store computes.

- [ ] **Step 2: Run** `bash t.sh tests/core/ledger_keep_test.lua` — Expected: FAIL (`attempt to call method 'prune'`).

- [ ] **Step 3: Implement.**
  - `core/LedgerStub.lua` as the Interfaces block says. `prune` walks `store.ev` with `pairs` (no sort) once, collects candidates `{a, n, b}`, sorts them by `at`, then author bytes, then `n`, and applies rule 2 per author from `L.rc`.
  - `core/LedgerStore.lua`: `L:stubLoad()` after the load loop (before the `L.fresh` bump); in `Store:add`, right after `b.h = Ledger.hash(b)`: `if self:stubbed(a, n, b.h) then return "dup", b end`; the cap test becomes `#held + (self.sn[a] and self.sn[a][n] or 0) >= BODIES_MAX` (the loser is still chosen among bodies only). Add `sn = {}` to the fields of `Ledger.new`.
  - `core/LedgerHash.lua`: `Store:items` appends `a .. ":" .. s.n .. ":" .. s.h` for `self:stubs(a)`; `Store:reach` runs through a stub number unconditionally (`ev[k + 1] or sn[k + 1] or (rn and k < top and rn[k + 1])`); `Store:vector` lists an author of `store.st` it has not listed, with `n = self:reach(a)`; at the end of a job `self.il[job.a]` is `job.il` only when `(self.act[job.a] or 0) >= self.epoch() - C.LEDGER_IL_IDLE`, else `nil`.

- [ ] **Step 4: Run** `bash t.sh` — Expected: all pass (1889 + the new ones). If a test of `ledger_final_test.lua` that asserts a kept list uses entries older than 30 days, give those entries `at = NOW`; do not weaken the rule.

- [ ] **Step 5: Commit** `feat(ledger): stubs — an old R or S leaves its id and hash behind, and my vector keeps counting it`.

---

### Task 2: Retention in the sync, and the prune itself

**Files:**
- Create: `tests/core/ledger_keep_sync_test.lua`
- Modify: `core/LedgerSyncPage.lua` (`Sync:lid`), `core/LedgerSyncVector.lua` (new `Sync:tail`, two call sites in `Sync:vector`), `core/LedgerSync.lua` (`Sync.new`: `high = {}`; `Sync:pump`: note what left), `core/LedgerStub.lua` (`Net:prune`), `core/LedgerNet.lua` (`Net:start`, `Net:stop`)

**Interfaces:**
- Consumes: Task 1's `Store:stubs`, `Store:stubTop`, `Store:prune`.
- Produces:
  - `Sync:lid` lists my stubs of `au` after the refusals, under the same scope test (`all or s.n > n or at[s.n]`, not already in `set`).
  - `self.high[peer][author]` = the highest number of that author among the bodies a `LEV` of mine carried to that peer in an exchange (set in `Sync:pump` for every entry of the batch that leaves; memory only).
  - `Sync:tail(x, a, n) -> bodies` = `self.L:above(a, from)` where `from = n`, or `math.max(n, self.high[x.peer] and self.high[x.peer][a] or 0)` when `self.L:stubTop(a) > n`. `Sync:vector` calls it in place of both `L:above(a, t and t.n or 0)` and `L:above(a, t.n)`.
  - `Net:prune()` — re-arms itself in 5 s while `self.waiting`, `self.L:hashing()` or `self.client.ledgerSync:busy()`; else `local n, more = self.L:prune(self.L.epoch(), C.LEDGER_PRUNE_STEP)`; `n > 0` → `self:changed()`; `more` → re-arm in 5 s. Timer field `pruneTimer`, armed in `Net:start` with `C.LEDGER_PRUNE_WAIT`, cleared in `Net:stop`.

- [ ] **Step 1: Write the failing tests** (`ZH` writes, is never online; `rs(author, from, to, at)` builds `R` entries as Task 1's `b.result`; "prune" = `sim:run(C.LEDGER_PRUNE_WAIT + 1)` or a direct `c.ledger:prune`):

```lua
it("a pruned client and one that keeps everything are equal: no exchange, no entry", function()
  local sim, c = world(ANA, BOR)
  give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[BOR], rs(ZH, 1, 40, OLD))
  eq(select(1, c[ANA].ledger:prune(sim:epoch(), 100)), 40)
  eq(digests(c[ANA], c[BOR])[1], digests(c[ANA], c[BOR])[2])
  local mark = #sim.sent
  hello(sim, ANA, BOR); sim:run(400)
  eq(#whispers(sim, ANA, "LVC", mark), 0); eq(#whispers(sim, BOR, "LEV", mark), 0)
end)

it("a newcomer gets a stub holder's bodies once and never again", function()
  local sim, c = world(ANA, BOR)                       -- Ана holds 1..40 (old) and 41..60 (fresh), pruned; Борис nothing
  give(c[ANA], rs(ZH, 1, 40, OLD)); give(c[ANA], rs(ZH, 41, 60, EPOCH0))
  c[ANA].ledger:prune(sim:epoch(), 100)
  hello(sim, ANA, BOR); sim:run(400)
  eq(holds(c[BOR], Ledger.id(ZH, 41)), 1); eq(holds(c[BOR], Ledger.id(ZH, 60)), 1); eq(holds(c[BOR], Ledger.id(ZH, 1)), 0)
  local sent = c[ANA].ledgerSync.stats.sent
  give(c[ANA], rs(ZH, 61, 61, EPOCH0)); give(c[BOR], { pay(BOR, 1) })   -- both cells and both digests move
  hello(sim, ANA, BOR); sim:run(400)
  eq(c[ANA].ledgerSync.stats.sent - sent, 1)           -- the new entry only, not 41..60 again
  eq(holds(c[BOR], Ledger.id(ZH, 61)), 1)
end)
```

  Further cases:
  - `the same newcomer over six more differences is sent nothing it holds`: loop 6 × (a fresh `P` of `BOR` on `BOR`, `hello`, `sim:run(400)`): `stats.sent` of `ANA` unchanged.
  - `a LID round does not bring a stubbed body back`: `ANA` (pruned) and `BOR` (unpruned) hold the same `ZH` 1..10 and each one extra twin at number 10 (so `n` is equal and the `x` differ) → after the exchange `ANA` still holds no body at 1..9 (`holds == 0`), both digests equal.
  - `three clients, three retention states, converge`: `ANA` pruned, `BOR` unpruned, `VERA` empty; `hello` all, `sim:run(1500)` → `VERA` and `BOR` equal digests and `VERA` holds `ZH:1`; then `VERA`'s own prune → all three digests equal.
  - `the prune runs once after login, off the hash and off an exchange`: a client with 5 old `R` of `ZH` → `stubCount() == 0` at `LEDGER_PRUNE_WAIT - 1`, `5` at `+ 6`; `presence.sentLd` unchanged across it (no `HI`).
  - `a prune of 1200 candidates goes in steps`: `stubCount()` reaches 1200 within `LEDGER_PRUNE_WAIT + 20` s, never more than `LEDGER_PRUNE_STEP` in one moment.

- [ ] **Step 2: Run** `bash t.sh tests/core/ledger_keep_sync_test.lua` — Expected: FAIL (the second test resends 20 entries; the prune test finds no stub).

- [ ] **Step 3: Implement** the Interfaces block. `Sync:pump`'s note is two lines inside the loop that builds the batch; `core/LedgerSync.lua` must stay under 300 lines.

- [ ] **Step 4: Run** `bash t.sh` — Expected: all pass; `tests/core/ledger_sync_test.lua` and `ledger_final_test.lua` untouched and green (no store there holds a stub, so `Sync:tail` is `L:above`).

- [ ] **Step 5: Commit** `feat(ledger): retention — a stub holder and a keeper agree, a newcomer is sent each body once`.

---

### Task 3: The trust rule and the board (`core/LedgerStats.lua`)

**Files:**
- Create: `core/LedgerStats.lua`, `tests/core/ledger_stats_test.lua`
- Modify: `core/LedgerView.lua` (`build`: `v.stands`, `v.pays`), `TavernGames.toc`, `tests/toc_test.lua` (cap < 260)

**Interfaces:**
- `core/LedgerView.lua`: `v.stands` = the list of non-denied, counted `S` with string `gid` and `f`; `v.pays` = the list of non-denied `P` the view counted; both in `L:each` order.
- Produces `ns.LedgerStats`:
  - `Stats.games(L) -> { rec, ... }` oldest first (`at`, then `gid` bytes, then author bytes), cached per store until `L.rev` changes. `rec = { gid, g, at, by = {authors}, names = {…}, win = {name = true}, lose = {name = true}, sk, why, cash = true|nil, state, counts = { [name] = "win"|"loss"|"draw" } }`. `state`: `"fun"`, `"confirmed"`, `"pending"`, `"contested"` (any debt of the `gid` contested), `"claim"` (an outsider's `R`, or a staked draw). `counts` is Decision T, rules 2–5; `names` holds strings only.
  - `Stats.board(L, opts) -> { rows, king, top }`, `opts = { period = "week"|"month"|"all", game = id|nil, now = epoch }`. `rows[i] = { name, games, wins, pct, net, fav, honour }`: `pct = floor(wins * 100 / games + 0.5)` (nil at 0 games); `net` signed copper from confirmed debts with `d.at >= now - PERIOD` (and `d.g == game`); `fav` the game id with the most counted games (ties: byte order; nil under a game filter); `honour = { kind = "wins"|"losses", n }` for the longest run of at least 3 in the period (a win run first; a draw breaks both). Rows: every name with `games > 0` or `net ~= 0`, ordered by `net` desc, `wins` desc, `games` desc, name bytes. `top` = the largest `|net|`. `king` (Decision T rule 6) is always computed **without** the game filter.
  - `Stats.versus(L, name, opts) -> { { name, won, lost, net }, ... }` (same `opts`): per opponent, the counted games where `name` and it stand on opposite sides, and the confirmed copper between the two; ordered by `|net|` desc, `won + lost` desc, name bytes.
  - `Stats.PERIOD = { week = 604800, month = 2592000 }`, `Stats.KING_GAMES = 5`, `Stats.RUN = 3`.

- [ ] **Step 1: Write the failing tests** (a `book()` with `b.result(author, fields, n, at)` and `ledger_view_test.lua`'s `debt`, `confirm`, `contest`, `deny`):

```lua
it("a fun result counts on a seated host's word, an outsider's for nobody", function()
  local b = book()
  b.add(I, "R", { gid = G1, g = "ttt", n = { I, M }, w = { 1 }, l = { 2 } })
  b.add(P, "R", { gid = G2, g = "ttt", n = { I, M }, w = { 2 }, l = { 1 } })
  local g = Stats.games(b.l)
  eq(g[1].counts, { [I] = "win", [M] = "loss" }); eq(g[1].state, "fun")
  eq(g[2].counts, {}); eq(g[2].state, "claim")
end)

it("a staked loss counts only on the loser's word, a win only on a debtor's", function()
  local b = book()
  b.add(I, "R", { gid = G1, g = "ttt", n = { I, M }, w = { 1 }, l = { 2 }, sk = 50000 })
  local d = b.debt(I, M, I, 50000, G1)
  eq(Stats.games(b.l)[1].counts, {}); eq(Stats.games(b.l)[1].state, "pending")
  b.confirm(M, d)
  eq(Stats.games(b.l)[1].counts, { [I] = "win", [M] = "loss" }); eq(Stats.games(b.l)[1].state, "confirmed")
  local row = Stats.board(b.l, { period = "all", now = NOW }).rows
  eq(row[1].name, I); eq(row[1].net, 50000); eq(row[2].net, -50000)
end)
```

  Further cases:
  - `a contested debt backs nothing and marks the game`; `a denied R counts for nobody`.
  - `a loser who wrote the R itself has lost` (author == loser, no debt).
  - `Belot: two confirmed pairs, four names, the leaver's partner draws` (forfeit `R`: `w = {2, 4}`, `l = {1}`, seat 3 in neither).
  - `a name counts once per gid` (two `R`s of one `gid` with different `n`); `two Rs of one game with the same content are one game` (`#by == 2`).
  - `Холдем: an S counts by confirmed copper at its gid` (won, lost, and uncounted without a confirmed debt unless `f` wrote it).
  - **Review Focus 2** `an empty chair and a seat out of range are skipped`: `n = { I, false, M }`, `w = { 1, 5 }`, `l = { 2, 3 }` → `counts == { [I] = "win", [M] = "loss" }`, no row keyed `false`.
  - **Review Focus 4** `an entry an hour ahead is inside the week`; `an entry of 8 days ago is in the month, not the week`.
  - `the game filter narrows games and net, and fav is nil under it`; `fav breaks a tie by byte order`.
  - `honours: eight wins in a row; five losses in a row; a draw breaks a run; two is none`.
  - `the king is the highest positive net; without gold, the most wins among players with five games; else nil`; `the king ignores the game filter`.
  - `versus: per opponent won, lost and confirmed copper`.
  - `the games are computed once per rev` (two calls return the same table; a new entry a new one).

- [ ] **Step 2: Run** `bash t.sh tests/core/ledger_stats_test.lua` — Expected: FAIL (`ns.LedgerStats` is nil).
- [ ] **Step 3: Implement.** One pass over `View.of(L)`: index the debts by `gid` first (`status`, `f`, `t`, `c`), then the `R`s of `v.results` and the `S`s of `v.stands`.
- [ ] **Step 4: Run** `bash t.sh` — Expected: all pass.
- [ ] **Step 5: Commit** `feat(ledger): the trust rule — a result counts for a player as far as a word other than the claimant's backs it`.

---

### Task 4: The chronology (`core/LedgerHistory.lua`)

**Files:**
- Create: `core/LedgerHistory.lua`, `tests/core/ledger_history_test.lua`
- Modify: `TavernGames.toc`, `tests/toc_test.lua` (cap < 140)

**Interfaces:**
- Consumes: `Stats.games(L)`, `View.of(L)` (`v.pays`, `View.denied(v)`).
- Produces `ns.LedgerHistory.lines(L, name) -> { line, ... }`, newest first (`at` desc, then kind `game` < `pay` < `denied`, then id bytes), cached per `L.rev` and `name`:
  - `{ kind = "game", at, rec }` for every record of `Stats.games` (counted or not);
  - `{ kind = "pay", at, f, t, c, how, rl }` for every `P` of `v.pays` (`t` its author);
  - `{ kind = "denied", at, entry }` for every denied `R`, `S` or `P`.
  - With `name`: only lines that name it (`rec.names`, `f`, `t`, a denied entry's author, `f` or `n`).

- [ ] **Step 1: Write the failing tests:** `games and payments interleave, newest first`; `a pending and a contested staked game are listed with their state`; `a denied result stays, as denied, and is in no game line`; `the name filter keeps a player's games, payments and denied entries only`; `a stubbed result is gone from the lines and its payments stay` (`L:prune` then `lines`); `the lines are built once per rev and name`.
- [ ] **Step 2: Run** `bash t.sh tests/core/ledger_history_test.lua` — Expected: FAIL.
- [ ] **Step 3: Implement** `History.lines`.
- [ ] **Step 4: Run** `bash t.sh` — Expected: all pass.
- [ ] **Step 5: Commit** `feat(ledger): the chronology of games and payments, from the ledger`.

---

### Task 5: The tab „Класация“

**Files:**
- Create: `ui/BookList.lua`, `ui/BoardTab.lua`, `tests/ui/board_tab_test.lua`
- Modify: `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`, `tests/toc_test.lua` (caps: `ui/BookList.lua` < 140, `ui/BoardTab.lua` < 300)

**Interfaces:**
- `ns.BookList.new(parent, opts) -> list`, `opts = { width, rowH, rows, make = fn(row), fill = fn(row, line, i) }`: `ui/LedgerTab.lua`'s virtual list lifted out (a `W.Scroll`, row widgets made only for the rows on screen, refilled on mouse wheel). `list:set(lines)`, `list:fill()`, `list.scroll`, `list.rows`. `ui/LedgerTab.lua` is **not** changed to use it.
- `ns.BoardTab.lines(client, period, game) -> { king = text|nil, rows = { { name, who, games, wins, pct, net, bar, fav, honour } } }`: texts ready to draw; `who` painted as `LedgerTab` paints names; `pct` `"62%"` or `"–"`; `net` `"+5g"`, `"−3g 20s"` or `"0"` (`ns.Util.money`); `bar` = `net / top` in −1..1; `fav` = `W.gameName(id)` or `""`; `honour` text or nil. `{ rows = {} }` without a ledger.
- `ns.BoardTab.state = { period = "week", game = nil }`; `BoardTab.setPeriod(p)`, `BoardTab.nextGame()` (Decision G), `BoardTab.render()`, `BoardTab.refresh()` (next frame, only while shown, on `"ledger"`), `BoardTab.build(page)`; registered by `ns.MainWindow.addTab("board", "tab.board", BoardTab.build)`. A click on a row calls `ns.HistoryTab.open(name)` when `ns.HistoryTab` exists (Task 6).
- Layout: the panel and paper of `LedgerTab.build`; under the title three period buttons and the game button (`W.Button`, small); a head line with the king; a column header; 14 rows of 26 px: place, name, „Игри“, „Победи“, „%“, a bar (green right of its middle for a positive net, red left for a negative, at most 60 px a side) with the amount, „Любима игра“, the honour.
- Locale keys (bg / en):

| Key | bg | en |
|---|---|---|
| `tab.board` | Класация | Leaderboard |
| `board.week` / `board.month` / `board.all` | Седмица / Месец / Всичко | Week / Month / All time |
| `board.games.all` | Всички игри | All games |
| `board.col.games` / `.wins` / `.pct` / `.net` / `.fav` | Игри / Победи / % / Злато нето / Любима игра | Games / Wins / % / Gold net / Favourite game |
| `board.king` | Кралят/Кралицата на механата: %s | King/Queen of the tavern: %s |
| `board.king.none` | Тронът е празен. | The throne is empty. |
| `board.honour.wins` | %d поредни | %d in a row |
| `board.honour.losses` | %d загуби подред | %d losses in a row |
| `board.empty` | Още никой не е играл. | Nobody has played yet. |
| `board.row.tip` | Натисни, за да видиш историята на %s. | Click to see the history of %s. |

- [ ] **Step 1: Write the failing tests** (`readyWow`, `entry` and `plain` as in `tests/ui/ledger_tab_test.lua`):
  - `the rows read games, wins, percent, net and favourite`: `ME` beats `B` twice for fun at `ttt` (host `ME`) and holds a confirmed 5g debt of `B` → `lines(client, "all", nil).rows[1]` has `name == ME`, `games == "2"`, `wins == "2"`, `pct == "100%"`, `plain(net) == "+5g"`, `bar == 1`; row 2 `plain(net) == "−5g"`, `bar == -1`.
  - `the king line names the highest net; an empty period says the throne is empty`.
  - `the period buttons and the game button redraw the rows` (press, `w:advance(0)`, read `BoardTab.view.list.rows[1]`).
  - `an honour of three wins is written`.
  - `a new ledger entry redraws the shown tab on the next frame, a hidden tab not at all`.
  - **Review Focus 3** `no guild: the tab shows its empty line`; `an empty ledger too`.
  - `BookList: 500 lines make at most rows + 1 widgets and a wheel refills them`.
- [ ] **Step 2: Run** `bash t.sh tests/ui/board_tab_test.lua` — Expected: FAIL.
- [ ] **Step 3: Implement** `ui/BookList.lua`, then `ui/BoardTab.lua`, then the keys.
- [ ] **Step 4: Run** `bash t.sh` — Expected: all pass (locale parity included).
- [ ] **Step 5: Commit** `feat(ui): the tab „Класация“`.

---

### Task 6: The tab „История“

**Files:**
- Create: `ui/HistoryTab.lua`, `tests/ui/history_tab_test.lua`
- Modify: `locale/bg.lua`, `locale/en.lua`, `TavernGames.toc`, `tests/toc_test.lua` (cap < 300)

**Interfaces:**
- Consumes: `ns.LedgerHistory.lines`, `ns.LedgerStats.versus`, `ns.BookList.new`.
- Produces: `ns.HistoryTab.lines(client, name) -> { { kind, text, mark, amount, age, tip, at } }` (text built when a line first comes on screen, as `LedgerTab` does); `HistoryTab.head(client, name) -> { text, ... }` (at most 5 opponents, only with `name`); `HistoryTab.open(name)` (sets the filter, `ns.MainWindow.show("history")`); `HistoryTab.clear()`; `HistoryTab.render()`, `refresh()`, `build(page)`; `ns.MainWindow.addTab("history", "tab.history", HistoryTab.build)`.
- Layout: the panel and paper of `LedgerTab.build`; the head shows „История“ or „История на %s“ with a small button „Всички“ that clears the filter, then the head-to-head lines, then 16 rows of 26 px: the text, its mark, the amount, the age (`LedgerTab.age`).
- A game line: winners and losers by name (`W.colored`), joined with „ и “; the mark from `rec.state`; the amount is `rec.sk` when staked; the tooltip names the author(s) („по думите на %s“), the game, the day, and `why`.
- Locale keys (bg / en):

| Key | bg | en |
|---|---|---|
| `tab.history` | История | History |
| `history.of` | История на %s | History of %s |
| `history.all` | Всички | Everyone |
| `history.won` | %s: %s победи %s | %s: %s beat %s |
| `history.draw` | %s: %s, равен | %s: %s, a draw |
| `history.left` | %s: %s напусна | %s: %s left |
| `history.sat` | %s: %s стана от масата | %s: %s left the table |
| `history.paid` | %s плати на %s | %s paid %s |
| `history.mark.fun` | за удоволствие | for fun |
| `history.mark.claim` | само твърдение | a claim only |
| `history.by` | по думите на %s | by the word of %s |
| `history.versus` | срещу %s: %d победи, %d загуби, %s | against %s: %d won, %d lost, %s |
| `history.empty` | Още няма история. | No history yet. |

  The marks „чака потвърждение“, „оспорен“ and „отречено“ reuse `ledger.pending`, `ledger.contested`, `ledger.denied`; a payment's mark reuses `pay.trade`, `pay.mail`, `accounts.settle`.

- [ ] **Step 1: Write the failing tests:**
  - `a fun game, a staked game and a payment read as lines, newest first` (exact `plain(text)` for each, e.g. `"Морски шах: Иван Петров победи Мария Стоянова"`).
  - `a pending game is marked „чака потвърждение“, a contested one „оспорен“, a denied one „отречено“`.
  - `the tooltip names the host whose word a fun result is`.
  - `open(name) shows that player's lines and the head-to-head; „Всички“ clears it`.
  - `a click on a row of „Класация“ opens the history of that player` (`w.ns.MainWindow.current == "history"`).
  - **Review Focus 5** `3000 lines: at most 17 row widgets, and only the rows on screen have text`.
  - **Review Focus 3** `no guild and an empty ledger show the empty line`.
- [ ] **Step 2: Run** `bash t.sh tests/ui/history_tab_test.lua` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bash t.sh` — Expected: all pass.
- [ ] **Step 5: Commit** `feat(ui): the tab „История“, and a player's history from „Класация“`.

---

### Task 7: Polishing and the documents

**Files:**
- Modify: `core/Help.lua`, `locale/bg.lua`, `locale/en.lua`, `ui/BoardTab.lua`, `ui/HistoryTab.lua` (the ⓘ topic on show and hide, as `LedgerTab` sets `"ledger"`), `wow/Slash.lua`, `tests/core/locale_help_test.lua`, `docs/superpowers/notes/engine-contract.md`, `docs/superpowers/notes/2026-11-21-rulings.md`, `docs/superpowers/plans/2026-11-23-stakes-roadmap.md`
- Create: `docs/superpowers/notes/2026-11-stageF4-ingame-checks.md`

**Interfaces:**
- Help topics `{ id = "board", title = "tab.board" }` (blocks `help.board.p1`, `help.board.trust`, `help.board.king`, `help.board.example`) and `{ id = "history", title = "tab.history" }` (`help.history.p1`, `help.history.marks`); the topic `ledger` gains `help.ledger.keep`. The texts must say, in plain tavern Bulgarian: a staked game counts once the loser has confirmed the debt; a game for fun counts on the host's word; the crown goes to the most gold won, and to the most wins only when no gold moved; results older than a year leave the board while debts never do; a player's row opens its history.
- `/tavern ledger` prints one local line: authors, bodies, stubs (`Store:stubCount`), my digest (`ledger.stats`, bg „Тефтер: %d автори, %d записа, %d стари (само следа), отпечатък %s“ / en "Ledger: %d authors, %d entries, %d old (trace only), digest %s").

- [ ] **Step 1: Write the failing tests:** in `tests/core/locale_help_test.lua`: `the board topic says whose word a result needs` (the bg text of `help.board.trust` contains „потвърди“ and „домакин“), `the ledger topic says old results leave and debts stay`, `the book lists the board and the history topics`; in `tests/ui/board_tab_test.lua` and `history_tab_test.lua`: `the ⓘ opens the tab's own topic while it is shown and the hall's after`; in the slash tests' file (find it with `grep -rl "Slash" tests`): `/tavern ledger prints authors, entries, stubs and the digest`.
- [ ] **Step 2: Run** those files — Expected: FAIL.
- [ ] **Step 3: Implement** the texts, the topics, the slash line.
- [ ] **Step 4: Write the documents.**
  - `engine-contract.md`, **Addendum 11 (stage F4)**: the stub (`store.st`, what counts it, what never is one), `Store:prune`'s rules and constants, `Sync:tail` and `high`, Decision M5, the trust rule 1–6 as built, the functions of `LedgerStats` and `LedgerHistory`, and the residuals: Decision T's cost, Decision R's costs 1–3, each with the name of the test that pins it.
  - `2026-11-21-rulings.md`: a section "Stage F4" with every Decision of this plan and its cost, and whatever the reviews of Tasks 1–7 ruled; "Open after F4": the in-game check list and the items under "Left open".
  - `2026-11-23-stakes-roadmap.md`: F4's bullets rewritten as built, with the trust rule and the retention rule in one line each.
  - `2026-11-stageF4-ingame-checks.md`, rows all "not yet measured": five tab buttons and the gold fit the title bar; „Класация“ after a fun game and after a staked game (before and after the loser's confirmation); the period and game buttons; a click on a row; „История“ with 200 lines scrolls smoothly; `/tavern ledger` before and after `LEDGER_PRUNE_WAIT`; two characters with different retention states (one store edited to hold year-old `R`s) show equal digests and exchange nothing; memory of the addon after login with a large ledger.
- [ ] **Step 5: Run** `bash t.sh` — Expected: all pass. Run `wc -l` on every file with a cap and compare with `tests/toc_test.lua`.
- [ ] **Step 6: Commit** `docs+polish: F4 — the rules book, /tavern ledger, Addendum 11, the rulings and the check list`.

---

## Self-review notes

- Spec 5.6: period × game, columns, bar, favourite game, honours, the crown (Tasks 3, 5); a click on a player shows its history and whom it beats and loses to (Tasks 3 `versus`, 6); „История“ of games and payments (Tasks 4, 6). Spec 6.4 "computed entirely from the log": no new saved state but `store.st`. Spec 9: the retention policy (Tasks 1, 2). Roadmap F4: the trust rule (Task 3), retention (Tasks 1, 2), polishing (Task 7).
- Tasks 1–2 and Tasks 3–6 are independent tracks; Task 4 needs Task 1 only for its one stub test, Task 7 needs all.
