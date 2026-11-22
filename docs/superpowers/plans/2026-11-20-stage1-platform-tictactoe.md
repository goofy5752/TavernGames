# Tavern Games Stage 1 (Platform + Морски шах) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A WoW Forever addon in which guild members see a shared tavern hall, open/join/watch tables, invite each other and play Морски шах (match to 3 wins) in real time, with a rules book, first-run intro, bg/en strings, bot mode and debug trace.

**Architecture:** Game engines are pure Lua (`engines/`). All lobby/presence/session logic (`core/`) is written against an injected `env` (send, clock, timers, player status), so several simulated clients run in one Lua process over an in-memory bus and are unit-tested outside WoW. One thin adapter (`wow/`) binds `env` to AceComm/C_Timer/game events; `ui/` only renders core state and calls core methods. The same in-memory bus powers bot mode in game.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), Ace3 subset (LibStub, CallbackHandler-1.0, AceAddon-3.0, AceComm-3.0 + ChatThrottleLib, AceSerializer-3.0, AceDB-3.0), LibDeflate, LibDataBroker-1.1, LibDBIcon-1.0, Python 3.14 + Pillow (texture generation), self-written Lua test runner (busted-style `describe/it`; meets the intent of spec 6.5, since busted cannot be installed on Windows without luarocks; the user approved this plan).

**Spec:** `docs/superpowers/specs/2026-11-20-tavern-games-design.md` (sections 5.1, 5.2, 5.3 Морски шах, 5.3а, 6.1, 6.2, 6.5, 6.6, 7 stage 1, 10). Mockups: `docs/mockups/01-visual-direction.html` (option A), `02-hub.html` (option A), `03-games.html` (`.ttt` panel).

## Global Constraints

- Addon folder and TOC name `TavernGames`; title `Tavern Games`; `## Interface: 16001`; `## SavedVariables: TavernGamesDB`; version `0.1.0`.
- Lua 5.1 syntax only (no `goto`, no LuaJIT-only features, even if tests run on LuaJIT). No `math.randomseed` (absent in the client).
- One addon-message prefix `TAVG`. Only `GUILD` and `WHISPER` channels. Every message is a table with `v` (protocol version, `1`) and `t` (type).
- Player identity is the full name `"Име Фамилия"` exactly as the server delivers it, **no realm**; compared byte-for-byte (never `string.lower`, it breaks Cyrillic). Whispers target that full name. The sender name always comes from the transport, never from the payload.
- `engines/` and `core/` use no WoW API and no globals; every file starts with `local _, ns = ...` and attaches to `ns`. Core calls `env.send`, `env.after`, `env.now` through the `env` table on every call (never cached in an upvalue) so bot mode can wrap them.
- Only `wow/` and `ui/` touch WoW API. The only globals created: `TavernGamesDB`, `SLASH_TAVERNGAMES1`, `SlashCmdList.TAVERNGAMES`.
- Slash command `/tavern` (subcommands `bots`, `debug`, `probe`, `intro`, `reset`).
- Every user-visible string comes from `locale/bg.lua` and `locale/en.lua` through `ns.L(key, ...)`; both tables have identical key sets.
- Colors (spec 5.1): wood `#4a2c1a`/`#2e190e`, felt `#7a1f24`→`#2c090b`, brass `#b0813f`, light brass `#e9c98a`, ink `#f3e2c0`, gold `#f2c94c`, card cream `#fbf3e2`, red paint `#a3161c`; O-mark `#e2735a` (mockup 03). Fonts: Alegreya SC (headings), Alegreya Sans (UI), Alegreya Italic. Player names in class color.
- Timing: turn timer default 45 s (dialog offers 30/45/60/90); invite toast 30 s; snooze 30 min; offline auto-stand after 3 minutes. On turn timeout an automatic move is made, never an automatic loss.
- Stage 1 has no wagers: the new-table dialog offers only „Само за удоволствие“; table records keep a `stake` field that is always `nil`. No ledger code.
- OneForAll is GPL-3: ideas only, no code, no art. Ace3/LibDeflate/LDB/LibDBIcon are vendored unmodified under `Libs/`. Alegreya ships with its `OFL.txt`.
- No spam: at most one `TBL` announce per table per 2 s; no public-chat output of any kind.
- Downloads and installs (Lua interpreter, Pillow, libraries, fonts) need the user's OK first. Never commit or push without the user's explicit instruction.

## Review Focus

1. **Duplicated, reordered or lost table events** (whispers arrive twice, out of order, or not at all): a client must apply each event exactly once, in order, and recover by itself. Pinned by Task 5 (`applies each event once`, `gap triggers SYN and snapshot heals`).
2. **Two clients claim host of the same table** after the host goes silent (or the old host comes back still believing it is host): everybody must converge on one host and one board. Pinned by Task 6 (`split brain converges`, `returning old host demotes`).
3. **Names with a space, Cyrillic and a stray realm suffix** (`"Иван Петров"`, `"Knikin Granitfaust-CAMWOWEU4Realm5PvE"`): the same person must never appear as two players and whispers must reach them. Pinned by Task 3 (`normalizes names`) and Task 9 (`Wire` round trip).
4. **Messages above 255 bytes** (snapshot with long Cyrillic names and 8 watchers): must arrive intact. Pinned by Task 9 (`snapshot above 255 bytes survives pack/unpack`) and the in-game 600-byte echo in Task 10.
5. **Host leaves in the middle of a match while a turn timer runs**: play continues, the timer restarts under the new host, no move is lost or played twice. Pinned by Task 6 (`host stands mid-turn`, `host vanishes mid-turn`).

Also pinned though not in the top five: two players clicking the same chair (Task 4), a stale invite accepted after the table filled or closed (Task 7).

---

## File Structure

```
TavernGames.toc            load order: Libs, core, engines, locale, wow, ui
.pkgmeta  .gitignore  t.sh  LICENSE-THIRD-PARTY.md
Libs/                      vendored libraries (unmodified)
engines/tictactoe.lua      pure rules of Морски шах
core/Const.lua             protocol version, prefix, every timing constant
core/Util.lua              deepcopy, deep equality, money formatting
core/Names.lua             name normalization
core/Emitter.lua           tiny on/emit
core/Bus.lua               in-memory message bus (tests + bots)
core/Trace.lua             ring buffer of protocol lines
core/Presence.lua          who is online with the addon, where they sit
core/Lobby.lua             directory of announced tables
core/Session.lua           one table: seats, ordered events, timers, host duties
core/Succession.lua        host silence detection, claim, handoff, split-brain rule
core/Invites.lua           invite send/receive, auto-decline, snooze
core/Client.lua            composes the above; the only API ui/ and wow/ call
core/Bots.lua              local fake players on a Bus
core/Locale.lua            ns.L, language switch
core/Help.lua              rules-book topics and intro steps (data)
core/HallLayout.lua        floor-plan geometry, floor/list mode, table ordering
core/Wire.lua              table <-> string (serializer + deflate injected)
locale/bg.lua  locale/en.lua
wow/Adapter.lua            AceAddon, AceComm, AceDB, env, events, own-name discovery
wow/Slash.lua              /tavern
ui/Theme.lua  ui/Widgets.lua  ui/MainWindow.lua  ui/Hall.lua  ui/NewTableDialog.lua
ui/InviteToast.lua  ui/TableFrame.lua  ui/games/TicTacToeView.lua
ui/HelpBook.lua  ui/Intro.lua  ui/Settings.lua  ui/Minimap.lua
media/*.tga  media/fonts/*.ttf + OFL.txt
tools/gen_textures.py      Pillow -> media/*.tga
tests/run.lua  tests/helpers/{loader,sim,fake_engine}.lua  tests/**/*_test.lua
```

Stage 1 presentation of stage 2 features: the tabs **Класация / Тефтер / История are not created** (only Зала and Настройки), the **„Сметки“ column is not created** (the right column shows only „В кръчмата сега“), and the left list shows all six games with the five unbuilt ones dimmed and labelled „Скоро“.

### Shared contracts (every task relies on these)

**`env`** (injected into `Client.new`):

| field | type | meaning |
|---|---|---|
| `me` | string | own full name |
| `guid` | string | own GUID (opaque) |
| `cls` | string | own class token, e.g. `"MAGE"` |
| `send(channel, target, msg)` | fn | `channel` `"GUILD"` (target nil) or `"WHISPER"` |
| `now()` | fn → number | monotonic seconds |
| `epoch()` | fn → integer | wall-clock seconds |
| `after(seconds, fn)` | fn → `{cancel=fn}` | one-shot timer |
| `status()` | fn → `{combat=bool, instance=bool, busy=bool}` | |
| `inGroup(guid)` | fn → bool | is that player in my party/raid |
| `db` | table | `{lang, introDone, busy, snoozeUntil, debug, minimap}` (in game a routing proxy over AceDB, Task 10) |
| `log(dir, channel, peer, msg)` | fn | trace hook, `dir` `"in"`/`"out"` |

**Messages** (`v=1` on all; `G` = GUILD, `W` = WHISPER; `→h` = to host):

| `t` | chan | fields | meaning |
|---|---|---|---|
| `HI` | G, W | `ver, cls, id, at, re` | presence; `id` GUID, `at` tid or nil, `re=true` asks peers to answer by whisper |
| `BYE` | G | | leaving (logout or `/reload`); stands nobody up: a seated player keeps the seat for the 3-minute offline window and a host's players claim after the silence; only a host alone at its table sends `END` first |
| `TBL` | G, W | `tid, g, h, e, ac, tn, st, s, w` | table record: game, host, epoch, access `"guild"/"invite"/"group"`, turn seconds, state `"open"/"live"`, seats array (`name` or `false`), watcher count |
| `END` | G | `tid, e` | table closed |
| `SIT` | W→h | `tid, seat` | |
| `SNO` | W | `tid, why` | sit/watch refused: `"taken" "full" "access" "version" "busy" "gone"` |
| `STD` | W→h | `tid` | stand up / stop watching |
| `WAT` | W→h | `tid` | watch |
| `INV` | W | `tid, g, h, s` | invitation |
| `INR` | W→h | `tid, a, why` | answer `"yes"/"no"/"auto"`; `why` `"combat" "instance" "busy" "snooze" "timeout"` |
| `ACT` | W→h | `tid, a` | player action |
| `EV` | W | `tid, e, q, seat, a, auto, left` | ordered event `q`; `seat` 0 = table/system; `left` = seconds on the next turn |
| `SYN` | W→h | `tid, have` | I am at seq `have`, send a snapshot |
| `SNP` | W | `tid, e, q, tbl, st, left, inv` | snapshot: `tbl` = TBL record, `st` = `Engine.snapshot`; `inv` = invited names of an `"invite"` table (byte order, omitted when empty), so a member that becomes host keeps letting them in |
| `PNG` | W→h | `tid` | member heartbeat |
| `TCK` | W | `tid, e, q` | host heartbeat |
| `HND` | W | `tid, e, to, inv` | graceful handoff, whispered by the old host to every member; the successor `to` (not the old host) then whispers `SNP` at epoch `e`; `inv` as on `SNP` (invitations sent after the members' snapshots) |
| `INA` | W | `tid, e, n` | host → every seated player of an `"invite"` table: name `n` was invited at epoch `e`; taken only from my current host at my epoch |
| `WHO` | G | `id` | adapter only (never reaches the Client): own-name lookup when the roster has no entry with my GUID; the echo whose `id` is my GUID names me |
| `PRB` | W | `id, pad` | adapter only: `/tavern probe` whisper to myself (packed above 255 bytes); the echo with the same `id` and `pad` proves split whispers arrive |

Guild gate (adapter): a message reaches the Client only from a sender listed in the latest guild-roster scan, or from myself; anything else is dropped and a roster refresh is asked for (at most once per 10 s), so a member who just joined passes from the next scan on. `WHO` and `PRB` bypass the gate (they verify themselves as my own echo).

Lobby rule: a `TBL` at a higher epoch than the known record replaces it only when its sender sits in the known record's seats (as `Succession.authority` on the session side); `END` only from the known host.

Frozen across protocol versions: the fields `v`, `t`, `tid` (on `SIT`, `WAT`, `SNO`), and `SNO.why="version"`. Table/system events (`seat=0`): `{k="sit",seat,name}`, `{k="stand",seat,why}` (`why` `"left"/"offline"`), `{k="start"}`, `{k="abort"}`, plus engine system actions.

#### Stage A additions

**Engine contract, optional additions** (an engine without them behaves as in stage 1):

| field | meaning |
|---|---|
| `E.start` | `"host"`: the game starts only on `client:startGame()`; absent: starts when every seat is filled |
| `E.options` | array of `{id, choices = {...}, default}`; the chosen values travel as `TBL.o` and reach `E.new` as `opts.opt` |
| `E.new(opts)` | `opts.first` (seat), `opts.seats` (array of booleans, `true` = occupied at start), `opts.opt` (resolved options) |
| `E.auto(state, seat, random)` | third argument `random(lo, hi) -> integer` (the session passes `env.random`) |
| `E.leave(state, seat)` | called on a `stand` event while live; must not fail |
| `E.result(state)` | `nil`, or `{winners = {seat,...}, losers = {seat,...}}` once a game has ended with an outcome |
| `E.over(state)` | `true` when the game has ended and a new one may start; absent: over = `E.result(state) ~= nil` (read through `Session:gameOver()`; `Session:canStart()` decides the start button; both in `core/Lifecycle.lua`) |
| `E.nextFirst(prevState, occupied)` | seat that starts the next game (host only; default: lowest occupied seat) |
| `E.needsGroup` | `true`: players must share a group (extension `party`) |
| `E.ext` | array of names in `ns.Ext` |

Death Roll has 2-5 seats (one party, never a raid). `Games.PLAYABLE = {ttt, deathroll}` gates the games: the Holdem, Santase, Belot and Tabla engines exist but are only shown, not openable, until they are enabled stage by stage.

**`ns.Ext[name]`** = a table of optional hooks:

| hook | meaning |
|---|---|
| `act(s, seat, a) -> a2 or nil` | host only, on a member's `ACT` before it is played; `nil` drops or holds it |
| `applied(s, seat, a)` | host and members, after every applied event (table events have `seat == 0`) |
| `auto(s) -> true or nil` | any seated client, "make my automatic move"; `true` = handled |
| `adopted(s, prevState)` | after a snapshot replaced my state |
| `hostChanged(s)` | my table changed host |

**`env` additions** (all optional; a bot's env has only `random`):

| field | meaning |
|---|---|
| `random(lo, hi)` | integer in `lo..hi` (`math.random` in game) |
| `roll(lo, hi)` | make a server roll (`RandomRoll`); absent when the client has no such function |
| `group()` | `{grouped, leader, raid, size}` of my own group |
| `groupInvite(name)` | invite the full name into my group |

**Protocol additions** (`v=1`, no new `t`):

| where | addition | meaning |
|---|---|---|
| `TBL` (and `SNP.tbl`) | `o` | table options `{id = value}`; omitted when the engine has none |
| `EV` seat 0 | `{k="start", first}` | `first` = seat that begins; absent or not occupied: lowest occupied seat |
| `ACT`, Death Roll | `{k="roll", n, max}` | "I rolled `n` in `1..max`" (the roller's claim) |
| `ACT`, Death Roll | `{k="roll", max, src="ask"}` | "roll for me" (a bot, or a client without `RandomRoll`) |
| `EV`, Death Roll | `{k="roll", n, max, src}` | `src` `"seen"` (host saw the server roll), `"claim"` (host could not see it), `"ask"`, `"timeout"` |

An invited player who asks for a taken seat is seated at the lowest free seat.

**Client events added:** `"result"({tid, game, opt, seats, winners, losers, at})` (`seats` = names by seat at that moment, `at` = `env.epoch()`), `"rollSeen"(shown, n, lo, hi)`.

**Test commands:** `bash t.sh` runs everything; `bash t.sh <file-or-dir>` runs a subset. Success ends with `N passed, 0 failed` and exit code 0. Test names below written with a `--[[ ... ]]` body state their assertions in words; the implementer writes them out as real assertions with exactly those values before implementing. The runner fails any test that makes zero assertions (Task 1), so no test body may be left empty.

#### Stage B additions

**Randomness (ruling X1), all engines.** `E.system(state)` returns an action carrying `need` when the table must supply randomness: `need = "deck"` (payload `deck`, always on the action `{k="deal"}`) or `need = "dice"` (payload `d = {a, b}`, on `{k="dice"}`). The session never applies such an action: after its delay it calls the extensions' `need(s, action)`. Whoever supplies the payload applies the same action without `need`. `E.apply` refuses an action that still has `need` with `"need"`.

**Engines that list the extension `fair`** (card games; Сантасе is the first, `Games.PLAYABLE = {ttt, deathroll, santase}`) also provide:

| item | meaning |
|---|---|
| `E.DECK`, `E.view`, `E.hidden`, `{k="show"}` | as in `.superpowers/sdd/engines-parallel/contract.md` |
| view ⊕ deck | `E.view` changes nothing but `deck` and sets `full = false`; a copy of any view with the whole deck and `full = true` behaves as the full state (`Fair.full`) |
| `{k="deal"}` on a view | accepts no deck or any subset; on a state with `full == true` only a complete permutation of `E.DECK` |
| `{k="void"}` at seat 0 | while a hand runs: annul it, nothing scores, back to the phase in which `E.system` asks for the deal; otherwise `"phase"` |
| `E.auto`/`E.legal` | return nothing for a hand whose faces are unknown |
| `E.again` | `true`: once the match is over the host may start a new one with `client:startGame()` |

**`ns.Ext` hooks added:** `need(s, action)` (host), `table(s, a) -> true|nil` (everyone: a seat-0 event the extension owns; `true` = applied, the engine is not asked), `snap(s) -> table|nil` (host: goes out as `SNP.fr`). `adopted` gets the snapshot message as a third argument. Every hook, `act` included, runs under `pcall`: an error goes to `env.log("error", "ext", "<ext>.<hook>", message)` and counts as `nil` (an `act` that raises drops the action); with `env.strictHooks` set (tests only, never by the WoW adapter) the error is re-raised.

**Protocol additions** (`v=1`; new types `SED`, `PRV`, `PRQ`, all WHISPER-only and point-to-point):

| where | shape | meaning |
|---|---|---|
| `EV` seat 0 | `{k="fair", op="open", h, d, p}` | the host opens shuffle round `h` (its `seq + 1`), dealer seat `d`, participants `p`: exactly the occupied seats in strictly ascending order (an `open` that differs is refused; `Fair.audit` refuses a non-ascending `p`) |
| `ACT` → `EV` seat 0 | `{k="fair", op="commit", h, c}` → `{…, seat, c}` | a participant's commit |
| `SED` (player → dealer) | `{tid, h, s}` | my seed, once every commit is in |
| `ACT` (dealer) → `EV` seat 0 | `{k="fair", op="deal", h, deck={[i]=face}}` → `{k="deal", deck={[i]=face}}` | dealt; `deck` holds only the faces a watcher sees |
| `PRV` (dealer → player) | `{tid, h, cards={[i]=face}}` | faces only that seat sees: its deal, its draws, the answer to `PRQ` |
| `PRQ` (player → dealer) | `{tid, h}` | send me all my faces again |
| `ACT` (dealer) → `EV` seat 0 | `{k="fair", op="show", h, cards}` → `{k="show", cards}` | faces that became public outside a play |
| `ACT` (dealer) → `EV` seat 0 | `{k="fair", op="reveal", h, s={seed,…}}` → the same as an event | the seeds in `p` order, after the hand |
| `ACT` (dealer) → `EV` seat 0 | `{k="fair", op="void", h}` → `{k="void"}` | the dealer lost the deck |
| `EV` seat 0 (host only) | `{k="fair", op="noreveal", h}` | accepted only for my own round `h`, stage `"dealt"`, hand over: closes it `bad`/`noreveal` (after the last hand of a match, which opens no next round) |
| `SNP` | `fr = {h, d, p, c, st, n}` | always sent for a card game: the round (commits `c` by seat, stage `st`, hands dealt `n`), or just `{n}` when no round is open |

**Client event added:** `"fair"({tid, game, h, verdict, why, dealer, at})`, once per closed hand on every client at the table. Verdicts: `"ok"`, `"bad"`, `"unseen"` (I did not see the whole hand), `"void"` (annulled, dealt again). Reasons of `"bad"`, in check order: `seeds`, `commit`, `deal`, `dealt`, `play`, plus `noreveal`. Timing: `FAIR_WAIT = 20`, `FAIR_ASK_GAP = 5`. Seeds, decks and private faces live in memory only.


#### Stage C additions

**Engine, optional** (Belot is the first; an engine without them behaves as in stage B):

| item | meaning |
|---|---|
| `E.dealer(state) -> seat` | who deals the next round, from public data only (Belot: `(first + 2) % 4 + 1`, the seat before the first bidder). Without it the stage B count formula applies. `dealerFor(s, p, n)` in `core/Deal.lua` takes it when it is one of `p`; `n` is optional and is used by `fits` (the check of a snapshot's round) |
| `E.bot(state, seat, random) -> action or nil` | a bot's move for the seat on turn, from its view; `nil` = use `E.auto` (Belot: suit bids only, `BOT_BID = 34`, `BOT_LUCK = 6`) |
| `E.announce(state, seat) -> {k="ann", a} or nil` | everything the seat on turn may still announce, as one action |
| `E.nextFirst` | Belot: `prev.first % 4 + 1`: the deal keeps rotating across matches (PC1 amends PB8) |

**Belot shapes inside `ACT`/`EV`** (no new message type, no new field; protocol `v=1`):

| where | shape | meaning |
|---|---|---|
| `ACT` -> `EV` seat 1-4 | `{k="bid", b}` | `b` = `P C D H S N A X R` |
| `ACT` -> `EV` seat 1-4 | `{k="ann", a={{t, i}, ...}}` | `t` = `s3`...`s8`, `c`, `c9`, `cJ`; `i` = deck index of the top card |
| `ACT` -> `EV` seat 1-4 | `{k="play", i, c, b}` | `b = true`: with a belote |
| `EV` seat 0 | `{k="score"}`, `{k="void"}` | the host after the eighth trick; a deal annulled |

**Client event `"result"`** also carries `left` (the seat whose leaving ended the game, or nil) and `names` (seat -> name or `false`, as seated before the event that ended it). Belot: `winners = {w, w + 2}`, `losers = {3 - w, 5 - w}` (seats 1+3 against 2+4), `losers[k]` paired with `winners[k]`.


#### Stage D additions

**Engine, optional:** `E.stage(state, seat, steps) -> {pts, pin, bar, off, left, next, done} | nil` (Табла: the position after a partial move, the dice still open, every single step that may follow, and whether the steps are a whole legal move; `next` is computed even when `done`). An engine without `E.view` is an open game: whole snapshots, no forged-move check, the host's clock moves for either seat, no automatic-move retry. `E.again` without `E.nextFirst`: a new match starts again with the opening throw. Details: Addendum 6 of `docs/superpowers/notes/engine-contract.md`.

**Extension `dice`** (`engine.ext = {"dice"}`): answers the engine's `{k="dice", need="dice"}` with a throw (`core/Dice.lua`, `core/DiceMember.lua`, `core/DiceCheck.lua`) and applies a seat-0 `{k="dice", d = {x, y}}` on every client itself; no message carries a dice value.

**Protocol additions:** none (still `v=1`). The shapes inside `ACT`/`EV`/`SNP`:

| where | shape | meaning |
|---|---|---|
| `EV` seat 0 | `{k="throw", op="open", h, c}` | the host opens throw `h` (= the event's `q`); `c` = the commit of its own seed |
| `ACT` -> `EV` seat 0 | `{k="throw", op="commit", h, c}` -> `{..., seat, c}` | the other seat's commit |
| `ACT` | `{k="throw", op="seed", h, s}` | the other seat's seed, to the host only |
| `EV` seat 0 | `{k="throw", op="seeds", h, s = {[seat] = seed}}` | both seeds, or the opener's alone after `DICE_WAIT = 10` |
| `ACT` -> `EV` seat 0 | `{k="throw", op="protest", h, why}` -> `{..., seat, why}` | a member found throw `h` forged; a claim only, passed on once per seat and throw, never restarting the turn clock |
| `SNP.fr` | `{h, d, c, p = {h, c, s, r, t}}` or absent | the running throw and the proof of the last closed one |
| `ACT` -> `EV` seat 1-2 | `{k="move", steps = {{from, to}, ...}}` | a whole turn; `from = 25` the bar, `to = 0` off |
| `EV` seat 0 | `{k="next"}` | the next game, 3 s after one ended |

**Session fields (dice games):** `s.throw = {h, d, r, commits, seed, own, asked, sent, rep, done, alone, fresh, reload, late, foul, replaced}`; `s.diceMine`, `s.diceLast = {h, verdict, why, by, silent, n}`, `s.diceProof`, `s.diceOwn`, `s.diceHost`, `s.diceNew`; `s.diceHeard`; per match `s.diceSeen`, `s.diceCry`, `s.diceBad`, `s.diceAlone[name]`, `s.diceUnheard`, `s.diceAway`, `s.diceCried` (host). `client.dice[tid]` keeps them across `END` and re-adoption (dropped `DICE_KEEP = 600` s after the table is gone); `env.db.fairKeep = {dice = true, ...}` keeps the guest's seed across a `/reload`.

**Env additions (final review of stage D, all optional for an env):** `env.loading` (true while the client shows a loading screen), `env.loadedAt` (`env.now()` when the last one ended), `env.entropy() -> string` (cheap entropy for the seed pool of `core/Fair.lua`), `env.db.lastAt` (the table I am at, kept per character; `core/Presence.lua`). `Fair.seed(env, purpose)` replaces `Fair.seed(random)`. New extension hook `still(s, seat, a) -> true` (host: the event leaves the running turn's clock alone).

**Client event:** `"fair"` is also emitted for every closed throw: `{tid, game, h, verdict = "ok" | "alone" | "bad" | "unseen", why, at}`.


#### Stage E additions

**Engine, optional:** `E.players(state) -> {seat, ...}` ascending (who shuffles: the hand's seats that are still seated and not away); `E.dealer(state)` for Hold'em is the button, or the next participant when the button's seat has left; `E.inHand(state) -> bool` (the fair layer's "hand over" is its negation); `E.sealed` (no reveal a hand; the book); `E.publicAuto` (the automatic move needs no hidden card: the host may play it for any seat after `AUTO_GRACE`); `E.watchers` (a cap below `MAX_WATCHERS`; Hold'em 1) and `E.maxSeats = 6`; `E.botFill` (a bot host invites idle bots up to this many seats); a system action `{k, need = "faces"}` (the dealer supplies it; a dealer step is accepted only when it carries every face the trial state needs). Engine state carries `state.g` (the game's identity, the seq of its `start` event). Details: Addendum 7 of `docs/superpowers/notes/engine-contract.md`.

**Extension `cash`** (`engine.ext = {"fair", "cash"}`, in that order: `fair`'s hooks run first; `core/Cash.lua`, with `core/Book.lua`, `core/BookKeys.lua` and `core/BookCheck.lua` for the book). New hooks, under `pcall` like the others: `lapsed(s)` (host: a shuffle was not dealt in `FAIR_WAIT`, called before it is opened again), `leaving(s)` (my client is about to stand up); `hostChanged` also arms the step wait of the new host. `BookKeys` wraps `Session.onStand` (no line of `core/Session.lua`).

**Protocol additions.** One field: `SNP.fr.k`. The shapes inside `ACT`/`EV`:

| where | shape | meaning |
|---|---|---|
| `EV` seat 0 | `{k="fair", op="commits", h, c = {[seat] = commit}}` | every commit of a sealed round, in one event (instead of one `commit` a seat) |
| `ACT` | `{k="book", op="step", h, a = {k = "street" \| "showdown", cards = {[i] = face}}}` | the dealer supplies the step the engine waits for; the host plays `a` at seat 0 only when it carries every face |
| `ACT` | `{k="book", op="missing", h, seats}` | the dealer names the seats whose seed it lacks (a seed lapse) |
| `ACT` | `{k="book", op="key", m, g}` | my table key, 32 hex, for game `g`: before I stand up, and when the game is closed; a key of another game is refused without a foul |
| `EV` seat 0 | `{k="book", op="keys", m = {[seat] = key}, g, f}` | published keys: a leaver's at once, everybody's at the close (may be empty); only the `f = true` final publish ends the book |
| `EV` seat 0 | `{k="close"}`, `{k="away", seat}`, `{k="void"}` | the host ends the game after this hand; a silent seat sits out; the hand is annulled (every chip back, the button moves on) |
| `ACT` -> `EV` seat n | `{k="back"}` | my seat is dealt in again |
| `ACT` -> `EV` seat n | `{k="fold"}`, `{k="check"}`, `{k="call"}`, `{k="bet", to}`, `{k="raise", to}`, `{k="allin"}` | a move; `to` = my whole bet on this street |
| `SNP.fr.k` | `{{seat, q, key}, ...}` or absent | the keys published in the running book, oldest first, at most `BOOK_KEYS = 24` |

**Session fields (sealed games):** `s.book = {key, g, rec = {[h] = {p, c, f, who}}, open = {h, ...}, keys = {{seat, q, m}, ...}, seen = {ok, bad, open}, n, given, tried = {[h] = #keys}, lack = {[h] = seats}, did = {[h] = true}, wait, sent, out, resent, synced, published, overAt, closed, final, dirty, missing, forged, ran, held, done}` (`g` = the seq of the game's `start` event; `overAt` = my clock when the game was over, the start of `BOOK_WAIT`; `ran`, `held`, `done`: rule 6a of Addendum 7); `client.bookHot = {tid, g, n}` (the hand I committed to and have not seen end by an event; on the client, not the session); `s.turnAt` (my own `env.now()` when I applied the event that put my seat on turn); `s.handSeen`, `s.handNames`; `s.lapseOut` (host: seats named at a seed lapse and held out one hand), `s.backAsked`, `s.fairLapses[dealer]` (the amber lapse count, apart from `s.fairVoids`); `fair.pend` (host: commits not yet published), `fair.who`; timers `s.stepTimer`, `s.keysTimer`, `s.bookTimer`. `env.db.bookKeep = {tid, me, key, g, h}` (`h` = `bookHot.n`) and `env.db.bookSpent` (keys I have sent: they never deal again) beside `fairKeep`.

**Client events:** `"hand"`: `{tid, game, opt, n, last, chips = {[seat] = chips after the hand}, names, at}` once a hand on every client that saw it end (`last` = a copy of `state.last`: `hand, contrib, won, pots = {{amount, eligible, winners}}, shown, cat, left`, or `void = true`). `"book"`: `{tid, game, hands, ok, bad, open, missing = {name, ...}, at}` when my book closes (and again when a late key goes into a further keys event). `"fair"` also carries `verdict = "sealed"` for every hand put into the book and `"bad"`, `why = "deal"` for a hand that fails the check; a seed lapse shows as `fair.lapse` (amber, with its own count, never an alarm).

**Message budget (measured, Task 5; supersedes the pre-flight figures of the stage E plan's Volume).** An ordinary hand is 143 whispers (138 EV, 5 PRV) and 22.0-22.5 KB; a full ring of six seats and one watcher is 203 whispers (192 EV, 5 PRV, 6 TCK) and 30.3-31.1 KB (pinned: 203, at most 32 500 B); without the watcher about 25.9 KB; one watcher adds about 4.6 KB; six commits are about 370 bytes packed. Nine seats wait for a later message-budget stage.

**Table geometry as built (Task 9, fix round 1; supersedes the plan's table).** Frame 760 x 532, felt 732 x 440. The note is at TOPLEFT (12, -366), 270 wide, left-justified, in the close button's place; row 3 (y -388, 26 high): fold 56 wide at x 476, call 86 at x 536, raise 100 at x 626; a label wider than its button minus 6 px steps its font down from 13 to 10.

#### Stage F1 additions

Copied from the stage F1 plan (`docs/superpowers/plans/2026-11-23-stageF1-ledger-payments.md`, Global Constraints) and brought up to what was built: where the two differ, this section and Addendum 8 of `docs/superpowers/notes/engine-contract.md` win (the amendment lines of `.superpowers/sdd/2026-11-23-stageF1-ledger-payments/global-constraints.md` and the rulings log, section "Stage F1").

**Engine, optional:** `E.stakes` (the engine takes a gold stake: Морски шах and Death Roll only); `E.idle` (no automatic move at a staked table; the host stands a seat on turn 180 s without an action, `why = "idle"`; its moves are judged by `Rolls.audit`, not by the forged-move check); `E.new(opts)` gets `opts.staked = true` at a staked table (Death Roll: `state.staked`, only `src = "seen"`, no `auto`).

**Extension `stakes`** (`core/Stakes.lua`), called last by `Session:hook` / `Session:filterAct` at a staked table only. New hooks: `gone(s)` (before an `SNO "gone"` ends my seated session) and `ended(s, by) -> true` (my host's `END`, or its snapshot at another stake, while I sit in the running game). `forged` gains a fourth argument `auto`, `adopted` a fourth `how` (`asked`, `fresh`, `sit`). `Session:canStart` gains `"group"` and `"break"`; `Client:sit` refuses `"roll"` (no `env.roll` at a staked Death Roll) and `"stake"` (no ledger, or not the table's stake).

**Protocol additions** (`v=1`, prefix `TAVG`, GUILD and WHISPER only; the complete list):

| where | addition | meaning |
|---|---|---|
| `TBL`, `SNP.tbl` | `sk` | stake in copper (a multiple of 100, `STAKE_MIN = 100` .. `STAKE_MAX = 99999990000`); absent = for fun |
| `SIT` | `sk` | the stake the sitter accepted; absent at a fun table |
| `INV` | `sk` | the stake of the table the invitation is for |
| `SNO.why` | `"stake"` | the `sk` of the `SIT` is not the table's |
| `HI` | `ld` | 8 hex: the digest of my ledger (SHA-256 over the sorted `"<author>:<x>"`); absent on a client without a guild ledger (a bot). `HI` grows by at most 20 packed bytes (measured +13..+18) |
| `EV` seat 0 | `{k="stand", seat, why="idle"}` | staked Death Roll: 180 s on turn without a roll. At a staked table the host also whispers a seat-0 stand (any `why` but `"left"`) to the player it stood up, with the same fields |
| new `LEV` | G: `ev` (1-4 entries, at most 760 packed bytes, **all authored by the sender**); W: `ev` (0-`LEDGER_BATCH` = 6 entries, none only with `f`, at most 1 140 packed bytes, any author, but an entry of another author than the sender is taken only inside an open exchange with the sender), `f = true` on a side's last batch | ledger entries |
| new `LVC` | W: `a = {[author] = {n, x}}` (`n`: the highest k with 1..k all held; `x`: 12 hex, SHA-256 over the byte-sorted `"<id>:<h>"` of the author's bodies), `r = true` when it answers one, `m = true` when more pages follow, `p = true` on an asking vector that is only a part of mine (it would not fit `LEDGER_EX_PAGES = 10` pages: the responder must not take an author it does not list for one I lack). A body I refused and still remember counts as held in `n` and `x` | my per-author vector, in pages of at most 1 500 packed bytes and `LEDGER_PAGE_ITEMS = 120` authors, at most 10 pages |
| new `LID` | W: `au`, `l = {"<n>.<h>", ...}` (`h` the full 16 hex), `r`, `m` | the bodies I hold of one author above the common `n`, at the ids I hold twins for and at the ids the other list names; when the lists are equal and `x` still differs, my whole list once; paged as `LVC` |
| new `PAY` | W: `c` (copper), `how` = `"trade"`, `"mail"` or `"nudge"` | payer -> creditor: "I am paying you `c` now"; creditor -> debtor with `"nudge"`: a reminder (at most one per `NUDGE_GAP = 3600` s) |

`LEV`, `LVC`, `LID` and `PAY` carry no `tid`; `core/Session.lua` ignores them (it returns on a message without a string `tid`). A peer at another protocol version gets the handling of before: listed as incompatible, nothing of the ledger or the payment is sent to it or taken from it, and its `HI.ld` is never read; an `ld` that is not 8 lowercase hex starts no exchange.

**Ledger entry** (`core/Ledger.lua`; the wire form is the stored form minus the local fields `h`, `rl`, `dr`, `un`; a stored `X` keeps its target's hash as `rh` and gives it back as `h`). `i = "<author>:<n>"`, `n` an integer from 1 (at most 9 digits); the author is the text before the last colon. `at` = `env.epoch()` of the author, at most `LEDGER_FUTURE = 3600` s ahead of my clock. A name is at most 64 bytes without `|` or `,`; a canonical entry at most 600 bytes. Anything else is dropped without an error.

| `k` | fields | who may author it |
|---|---|---|
| `R` result | `gid, g, n` (names by seat, `false` = empty), `w`, `l` (seat lists), `sk` (absent = fun), `why` (absent, or `"left"`, `"offline"`, `"idle"`) | the table's host (fun tables too: the one entry of a fun game) |
| `D` debt | `gid, g, f` (debtor), `t` (creditor), `c` (a valid stake), `why` = `"lost"`, `"left"`, `"offline"` or `"idle"` | `f` or `t`; `f ~= t` |
| `C` confirm | `r` (id of a `D`), `dh` (16 hex: the `h` of that exact `D` body) | counts only when the author is that `D`'s `f` and exactly one non-denied body under `r` has `h == dh` |
| `N` contest | `r`, `dh` as `C`; `why` = `"forged"`, `"roll"`, `"stand"`, `"amount"` or `"no"` | as `C` |
| `P` paid | `f` (debtor), `c` (any whole copper from 1 to 99 999 999 999), `how` = `"trade"`, `"mail"` or `"hand"` | the creditor (the author **is** the creditor) |
| `X` deny | `r` (an id), `h` (16 hex, the hash of the denied body) | the author named in `r` |

`gid = "<tid>/<q>"`, `q` the number of the table event that ended the game or stood the leaver up. `Ledger.canon(e)` = the fields in the order `i, k, at, gid, g, f, t, c, why, r, h, how, sk, n, w, l, dh` joined by `|` (absent = empty, `false` = `-`, a list joined by `,`); `Ledger.hash(e)` = the first 16 hex of SHA-256 of it. Up to 4 bodies per id are kept (over 4: a body denied by its author goes first, then the highest `h`). A logical debt is `gid|f|t`; only confirmed debts enter a balance; `net(a, b) = gross(a, b) - gross(b, a)`, `gross(f, t) = max(0, confirmed f->t - the c of t's P with that f)`.

**`env` additions** (all optional; a client without `guild` runs no ledger and sends no `HI.ld`):

| field | meaning |
|---|---|
| `guild` | the key of the ledger store, `guild .. "-" .. GetRealmName()` (local only, never sent); read when the client is created |
| `db.ledger` | `{[guild] = store}`, account-wide (AceDB `global`); a store holds `ev`, `tw` (twins), `me[name] = {seq, born}`, `pending` (the login queue, each row naming its owner character) and `rf` (the entries I refused, `[author]["<n>.<h>"]` = when forgotten) |
| `db.stakeSeen`, `db.stakeLeft` | my outcome notes and my „Стани“ notes, per character (`STAKE_SEEN_KEEP` = 14 days) |
| `db.stakeSat` | `{tid, sk}`: the stake of the table I sit at, per character; my staked seat exists only through it |
| `db.stakeLog` | `{tid, no, log, st}`: what I sent at that table and the game state it was saved at, per character, dropped with `stakeSat` |
| `db.paySent` | `{[creditor] = {at, c, paid, how}}`: gold that left me and no `P` has answered yet, per character (`PAY_GUARD` = 24 h); the payer's guard against paying twice |
| `member(name)` | true when the name is a guild member (the adapter's roster); absent = every name (the sim) |
| `after(0, fn)` | the next frame: the client hashes `LEDGER_HASH_ITEMS = 300` items of a stale author `x` per call (the sim runs it within the same instant) |
| `groupedWith(name)` | my own roster says that full name is in my party or raid (the staked Death Roll grouping checks) |
| `date(t)` | `{d, m, day}` of epoch `t` in my zone (`day` = a local day number); the sim and the fallback use UTC (`Pay.utc`); core never calls `os.date` |
| `noLedger(tid)` | true for a table `Bots:tableKind` calls a bot table; installed by `Bots.enable` |
| `send(..., done)` | `done` is called when the message has left (AceComm's callback); the sim calls it at once |
| `money()` | copper in my bags, or nil when the client cannot say (then Pay skips the "short" check) |
| `trade.state(name)` | `"ok"` (a unit of that player is in trade range; `"ok"` in combat, where range cannot be asked), `"far"`, `"none"` (no unit: not targeted, not grouped), `"off"` (no trade API) |
| `trade.open(name, copper)` | start a trade with that player (from a click) and fill the amount at its first `TRADE_SHOW` within 30 s -> `true` or nil |
| `mail.state()` | `"open"`, `"closed"` or `"off"` |
| `mail.fill(name, subject, body, copper)` | fill the send-mail frame (money, never COD; the player presses Send) -> `true` or nil |
| `mail.fee()` | copper the post takes for one letter (`MAIL_FEE = 30` when the client cannot say) |

The addon never calls `AcceptTrade`, `SendMail`, `TakeInboxMoney`, `AutoLootMailItem` or any COD function (`tests/wow` fails if it does).

**Client events added:** `"ledger"()` (the log changed, once a moment), `"forfeit"({tid, game, q, seat, name, to, why, sk, at})`, `"stakeAsk"(tid, sk)` (my seat at that staked table is asked), `"payAsk"()`, `"debtAsk"()` and `"mineAsk"()` (the lists `client.pay:asks()`, `client.stakes:asks()` and `client.ledgerNet:asks()` changed), `"nudge"(name, copper)`; `"refused"` gains `"stake"` and `"roll"`. `"result"` gains `q` (the event number that ended the game) and `sk`.

**Message budget (measured; the caps of the stage F1 plan hold).** A finished two-player staked game costs 2 GUILD `LEV` in the guild (the host's `R` + `D`, the loser's `C`), each one 255-byte part (`R` + `D` 186-196 packed bytes, `C` 123-127); its payment by trade one more (`P`, 123-125) and one `PAY` whisper; a fun game costs 1 (`R`). A five-player Death Roll's loser sends its four `C` in one `LEV` (under 600 packed bytes). The whole road of `tests/core/stakes_flow_test.lua` (a staked Морски шах, the payment, a member's catch-up after login) is 3 GUILD `LEV` (cap 5, at most 3 a sender), a catch-up of one exchange in 4 whispers (`LVC`, its answer, a `LEV` of four entries at 260-266 bytes, the closing `LEV`), and at most 2 778-2 856 packed bytes from any one client in any 10 s (cap 8 000; pinned at 3 400) in 1 GUILD part. Sync pages (Task 6): a vector of 45 authors with 25-byte names is one page (1 246-1 419 bytes), of 60 two; a `LID` of 50 / 60 / 70 / 300 items of 16-hex `h` is 830 / 959 / 1 113 / 4 414 bytes (about 95 items a page). AceSerializer writes keys in `pairs` order, which LuaJIT seeds per process, so a packed size moves by up to about 20 bytes between runs: every byte pin sits away from its cut. A fun-only guild's message log is the one of `82b0140` but for `HI.ld` and the host's one `LEV` of each result (pinned).

#### Stage F2 additions

Copied from the stage F2 plan (`docs/superpowers/plans/2026-11-24-stageF2-card-dice-stakes.md`, Global Constraints) and brought up to what was built. Where the two differ, this section and Addendum 9 of `docs/superpowers/notes/engine-contract.md` win, together with the rulings log, section "Stage F2".

**Engine, optional:** `E.stakes = true` now also for Сантасе, Белот and Табла (Холдем: F3). `E.partner(seat) -> seat` (Белот: `(seat + 1) % 4 + 1`) is the player who owes nothing and is owed nothing when its partner leaves. With `E.teams`, the i-th loser by seat owes the i-th winner (`Stakes.matched`), and `Stake.worst` is `stake × 2`. With `E.again`, the next match of a staked table waits `STAKE_BREAK_MATCH` (`Stakes.gap`).

**Extension `stakes`:** the new hook `hold(s) -> true` (host; `Session:startIfFull` asks it at a staked table: the start of a refilled `again` table waits for the break and for a silent seat). The `"fair"` client event and the session's dice counts feed the fouls `deal` and `dice` (`core/StakesFair.lua`).

**Protocol additions:** none: no new message and no new field (`v=1`, prefix `TAVG`, GUILD and WHISPER only). The complete list of what changes on the wire:

| where | change | meaning |
|---|---|---|
| `TBL.sk`, `SNP.tbl.sk`, `SIT.sk`, `INV.sk` | now accepted for `santase`, `belot` and `tabla` (`engine.stakes == true`) | as in F1 |
| ledger `N.why` | two more values: `"deal"` and `"dice"` | my client contests because a hand, or a throw, was not clean on it. A client of the F1 version refuses such an `N` (`"shape"`), remembers it, never relays it, and keeps the debt „чака потвърждение“ |
| `EV` timing at a staked table of a game with `E.again` | the host's start after a match, and after a leave and a refilled seat, waits until `STAKE_BREAK_MATCH` (30 s) after the last match ended, and while a seated player has been silent for `SILENT_AFTER` | a member takes a start as clean only when the break has passed by its own clock, less `AUTO_GRACE`; an earlier one is `forged` against the new match |

**Session fields** (local, never sent):

| field | meaning |
|---|---|
| `s.holdTimer` | host: the held start (`hold`), tried again when it fires; one of `Session`'s `TIMERS` |
| `s.stakeHoldFrom` | host: `env.now()` when it took up, by a snapshot or by becoming host, a table whose game was over and whose end its clock never dated (`stakeEndedAt == nil`); the break runs from then |
| `s.stakeRec = {gid, h, open, late}` | the match that just ended by play while its last hand `h` was still open: open until that hand's verdict; `late` = the foul it brought. It dies with the session |
| `s.diceRobbed` | per match, beside `s.diceUnheard`: the throws my host made alone after my commit or seed for them, or that a host change or a same-host snapshot dropped after my seed (foul `dice`) |

**Saved:** `db.stakeSat` is now `{tid, sk, tn}`: `tn` is the turn length of the table I accepted, and a snapshot with another `tn` is `forged`. `db.stakeLog` keeps no state (`st = nil`) and no card (`c`) for an engine with `view`. There is no new db key and no new `env` field.

**Constants:**

| constant | value | meaning |
|---|---|---|
| `STAKE_BREAK_MATCH` | 30 | s: the break before the next match of Сантасе, Белот and Табла (Морски шах and Death Roll keep `STAKE_BREAK = 10`) |
| `STAKE_FAIR_WAIT` | 40 | s: a match's note waits this long for its last hand's verdict (`FAIR_WAIT` + `AUTO_GRACE` + 13); a hand still open then reads `unseen` |
| `PAY_GUARD_MAIL` | 2 592 000 | s (30 days): the payer's guard set by a letter; `PAY_GUARD` (24 h) stays for a trade |
| `LEDGER_HASH_ITEMS` | 150 | was 300: items of a stale author's `x` hashed (and, at its first build, sorted or merged) per frame |
| `Net.SLACK` | 48 | was 24: a sync page is cut at 1 500 − 48 packed bytes, and the receiver accepts up to `PAGE + SLACK` |
| `HOLD_RECHECK` | 5 | s (local to `core/StakesStart.lua`): a held start waits this long for a silent seat, again and again |

**Client events:** none new. `"fair"` events (cards and dice) now also feed the stake's fouls at a staked table.

**Message budget (measured, Task 10, `tests/core/stakes_f2_flow_test.lua`):** GUILD `LEV`s of one finished staked match in the whole guild: Белот 4 (cap 7: `R`, two `D`, two `C`, two spare; at most 3 a client, measured 1), Сантасе 2 and Табла 2 (cap 4). A fun-only evening of the three games sends exactly the message log of `88a48e7` (pinned chunk by chunk).

#### Stage F3 additions

Brought up to what was built from the stage F3 plan (`docs/superpowers/plans/2026-11-25-stageF3-holdem-cash.md`, Global Constraints). Where the two differ, this section and Addendum 10 of `docs/superpowers/notes/engine-contract.md` win, together with the rulings log, section "Stage F3".

**Engine, optional (`engines/holdem.lua`, staked tables only):** `E.stakes = true`. `E.cashGame` (a staked Холдем keeps a matrix), `E.stakeOf(opt) -> opt.blinds × 100` (copper), `E.buyRange(state, seat) -> lo, hi` (chips, or nil with a reason). The option field `at = "fun" | "stake"` (`Games.resolve`; `stack` is a fun option, `rebuy` a staked one). New actions `{k="buy", n}` and `{k="cashout"}`; `join` carries the name as `who`.

**Extension `stakes` at a cash table** (`core/StakesCash.lua`): no forfeit, `s.cashNames`, the snapshot checks, the book's verdict for a note, the debtor's own `D` (`why = "cash"`), one `S` per out record.

**Session and client fields** (local, never sent): `s.cashNames`, `s.stepAsks = {k, n}`, `s.hostHeard`, `client.cashGoing = {tid, at}`, `Client:wantBuy`, `db.stakeSat.o` (the options I sat down to). **Client events:** `"cashout"` (my seat was settled) and `"cashGoing"` (my „Стани“ waits for it; `nil` ends the wait); `buyLow` (a floor above my pick).

**Protocol additions:**

| where | change | meaning |
|---|---|---|
| `TBL.sk`, `SNP.tbl.sk`, `SIT.sk`, `INV.sk` | accepted for `holdem`: the big blind in copper | as in F1 |
| `TBL.o`, `SNP.tbl.o` | `rebuy` present, `stack` absent at a staked table | the rebuy mode |
| `ACT.a`, `EV.a` | `{k="buy", n}`, `{k="cashout"}` | my buy-in; my seat is settled |
| `SNP.st` of a staked game | `cash`, the seats' `who`, `bought`, `cleared`, `back`; `last.took`; `pots[i].from` | the matrix and buy-ins |
| `EV` order at a lapse | `void` before every `away` of a lapsed shuffle | no blind is lost |
| ledger | kind `S`; `D.why = "cash"` | a claim for История; the debtor's own word. A client of the F1 or F2 version refuses both and keeps the debt pending |

**Constants:** `CASH_BOOK_WAIT = 86400` (s: a cash note waits at most this long for the book), `CASH_OUT_WAIT = 30` (s: my `cashout`, not applied this long with no hand holding me, I stand without it). A buy-in is `MIN_BB = 40` to `MAX_BB = 100` big blinds and `CHIP = 100` copper (`ns.HoldemCash`).

**Message budget (measured, Task 12):** an ordinary staked hand at six seats +0 to 1 % over a fun one; the six-seat close 19 GUILD messages in 22 parts. A fun-only Холдем evening sends exactly the log of `e62ddc6`.

---

### Task 1: Tooling, test runner, TOC skeleton

**Files:**
- Create: `t.sh`, `.gitignore`, `TavernGames.toc`, `tests/run.lua`, `tests/helpers/loader.lua`, `tests/runner_test.lua`, `tests/toc_test.lua`, `tests/fixtures/failing.lua`

**Interfaces:**
- Produces (globals inside test files): `describe(name, fn)`, `it(name, fn)`, `eq(actual, expected, msg)` (deep equality), `ok(value, msg)`, `raises(fn, pattern)`, and `Loader`. Each `eq`/`ok`/`raises` call counts as an assertion; an `it` that finishes with zero assertions fails with `no assertions`. A test file that errors while loading counts as one failure.
- Produces: `Loader.ns() -> ns` — reads `TavernGames.toc` and, for every line starting with `core/`, `engines/` or `locale/`, in TOC order, runs `loadfile(path)("TavernGames", ns)`. `Loader.lib(path)` runs a `Libs/` file in the global environment (used by Task 9 only).
- Produces: `t.sh` — picks the interpreter in this order: `tools/lua/lua5.1.exe`, `luajit`, `lua5.1`, `lua` on PATH; writes `tests/.files.txt` (`find engines core locale wow ui -name '*.lua' | sort`, missing directories ignored); runs `tests/run.lua` with the given files (directories expanded to `*_test.lua`) or all `tests/**/*_test.lua`.

- [ ] **Step 1: Get a Lua 5.1 interpreter.** Check `lua -v` and `luajit -v`. If neither exists, ask the user which they prefer and wait for their OK before downloading: (a) LuaBinaries 5.1.5 Win64 executables zip from the LuaBinaries SourceForge page, unpacked to `tools/lua/` (gitignored, nothing installed system-wide; recommended), or (b) LuaJIT through winget (confirm the package id with `winget search luajit` first). Verify: the interpreter prints a version starting `Lua 5.1` or `LuaJIT 2`.
- [ ] **Step 2: Write `tests/runner_test.lua` and `tests/fixtures/failing.lua`.**

```lua
describe("runner", function()
  it("deep-compares tables", function() eq({a={1,2}}, {a={1,2}}) end)
  it("catches errors", function() raises(function() error("boom") end, "boom") end)
end)
-- tests/fixtures/failing.lua
describe("x", function()
  it("fails", function() eq(1, 2) end)
  it("asserts nothing", function() end)   -- must fail: zero assertions
end)
```

- [ ] **Step 3: Run `bash t.sh tests/runner_test.lua`.** Expected: fails, `tests/run.lua` missing.
- [ ] **Step 4: Implement `tests/run.lua`, `tests/helpers/loader.lua`, `t.sh`.** `run.lua` takes file paths as arguments, adds `tests/helpers/?.lua` to `package.path`, prints `FAIL <describe> / <it>: <message>` per failure (`no assertions` for a test that asserted nothing), a last line `N passed, M failed`, and calls `os.exit(M > 0 and 1 or 0)`.
- [ ] **Step 5: Verify.** `bash t.sh tests/runner_test.lua` → `2 passed, 0 failed`. `bash t.sh tests/fixtures/failing.lua; echo $?` → `FAIL x / asserts nothing: no assertions`, `0 passed, 2 failed`, then `1`.
- [ ] **Step 6: Create `TavernGames.toc`** with the header fields from Global Constraints and the section comments `# Libs`, `# Core`, `# Engines`, `# Locale`, `# WoW`, `# UI` (forward-slash paths; each later task appends its files under the right comment). Create `.gitignore`: `tools/lua/`, `tests/.files.txt`, `__pycache__/`, `*.zip`.
- [ ] **Step 7: Write `tests/toc_test.lua`** with three cases: every `.lua` path in the TOC exists; every path in `tests/.files.txt` is in the TOC; every listed non-`Libs/` file compiles (`loadfile` returns a function). This is the syntax gate for `ui/` and `wow/`. Run `bash t.sh` → `5 passed, 0 failed`.
- [ ] **Step 8: Commit (only if the user has authorized commits in this session).** `chore: test runner, loader and TOC skeleton`

### Task 2: Морски шах engine

**Files:**
- Create: `engines/tictactoe.lua`; Test: `tests/engines/tictactoe_test.lua`; Modify: `TavernGames.toc`

**Interfaces:**
- Produces `ns.Engines.ttt` (the engine contract every later game follows):
  - `E.id = "ttt"`, `E.minSeats = 2`, `E.maxSeats = 2`, `E.WINS = 3`
  - `E.new(opts) -> state` — `opts.first` (1 or 2, default 1)
  - state: `board` (9 cells: 0 empty, 1 X, 2 O; seat 1 is always X), `turn` (seat or nil), `score = {0,0}`, `round`, `first`, `phase` (`"play"`, `"round"`, `"match"`), `line` (`{a,b,c}` or nil), `winner` (seat or nil), `draw` (bool), `rematch = {false,false}`
  - `E.apply(state, seat, action) -> true | nil, code` — codes `"seat" "phase" "turn" "cell" "action"`; a rejected action leaves `state` untouched
  - `E.legal(state, seat) -> {action, ...}`; `E.auto(state, seat) -> action|nil` (lowest-numbered empty cell; nil when it is not that seat's turn)
  - `E.system(state) -> action|nil, delaySeconds` — in phase `"round"` returns `{k="next"}, 3`
  - `E.snapshot(state) -> table`, `E.restore(table) -> state` (plain data, deep-copied both ways)
- Actions: `{k="mark", c=1..9}` (seat 1/2, phase `"play"`), `{k="next"}` (seat 0, phase `"round"`), `{k="rematch"}` (seat 1/2, phase `"match"`).
- Rules: lines are checked in the order `{1,2,3},{4,5,6},{7,8,9},{1,4,7},{2,5,8},{3,6,9},{1,5,9},{3,5,7}`. A won round adds 1 to the winner's score and sets `line`; at score 3 the phase becomes `"match"` with `winner`, otherwise `"round"`. A full board without a line is `"round"` with `draw=true` and no score. `next` clears the board, flips `first`, sets `turn = first`, increments `round`. When both `rematch` flags are set: score `{0,0}`, `round=1`, `first` = the seat that did not start the previous match, phase `"play"`.

- [ ] **Step 1: Write the failing tests.**

```lua
local E = Loader.ns().Engines.ttt
local function play(s, seq) for i = 1, #seq, 2 do ok(E.apply(s, seq[i], {k="mark", c=seq[i+1]})) end end
describe("tictactoe", function()
  it("X wins a round on the top row", function()
    local s = E.new{}; play(s, {1,1, 2,4, 1,2, 2,5, 1,3})
    eq(s.phase, "round"); eq(s.line, {1,2,3}); eq(s.score, {1,0}); eq(s.turn, nil)
  end)
  it("rejects wrong turn, taken cell, bad cell", function()
    local s = E.new{}
    eq({E.apply(s, 2, {k="mark", c=1})}, {nil, "turn"})
    play(s, {1,5}); eq({E.apply(s, 2, {k="mark", c=5})}, {nil, "cell"})
    eq({E.apply(s, 2, {k="mark", c=10})}, {nil, "cell"}); eq(s.board[5], 1); eq(s.turn, 2)
  end)
  it("draw gives no point and the next round starts with the other seat", function()
    local s = E.new{}; play(s, {1,1, 2,2, 1,3, 2,5, 1,4, 2,6, 1,8, 2,7, 1,9})
    eq(s.draw, true); eq(s.score, {0,0}); eq({E.system(s)}, {{k="next"}, 3})
    ok(E.apply(s, 0, {k="next"})); eq(s.turn, 2); eq(s.round, 2)
  end)
  it("match ends at 3 wins and rematch needs both seats", function() --[[ three X wins with "next" between:
    phase "match", winner 1, score {3,0}; rematch by seat 1 -> phase still "match";
    rematch by seat 2 -> phase "play", score {0,0}, round 1, turn 2 ]] end)
  it("legal lists 9 marks for the seat on turn and none for the other", function()
    local s = E.new{}; local l = E.legal(s, 1)
    eq(#l, 9); eq(l[1], {k="mark", c=1}); eq(l[9], {k="mark", c=9}); eq(E.legal(s, 2), {})
  end)
  it("auto picks the lowest empty cell", function()
    local s = E.new{}; play(s, {1,1, 2,2}); eq(E.auto(s, 1), {k="mark", c=3}); eq(E.auto(s, 2), nil)
  end)
  it("snapshot round-trips and is a copy", function()
    local s = E.new{}; play(s, {1,5}); local t = E.snapshot(s); t.board[1] = 9
    eq(s.board[1], 0); eq(E.snapshot(E.restore(E.snapshot(s))), E.snapshot(s))
  end)
end)
```

- [ ] **Step 2: Run `bash t.sh tests/engines/tictactoe_test.lua`.** Expected: FAIL, `Engines` is nil.
- [ ] **Step 3: Implement `engines/tictactoe.lua`** and add it to the TOC.
- [ ] **Step 4: Run again.** Expected: `7 passed, 0 failed`.
- [ ] **Step 5: Commit (only if the user has authorized commits in this session).** `feat: tic-tac-toe engine`

### Task 3: Core foundations, bus, simulator, presence

**Files:**
- Create: `core/Const.lua`, `core/Util.lua`, `core/Names.lua`, `core/Emitter.lua`, `core/Bus.lua`, `core/Trace.lua`, `core/Presence.lua`, `core/Client.lua`, `tests/helpers/sim.lua`
- Test: `tests/core/foundations_test.lua`, `tests/core/presence_test.lua`; Modify: `TavernGames.toc`

**Interfaces:**
- `ns.Const`: `PROTOCOL=1`, `PREFIX="TAVG"`, `VERSION="0.1.0"`, `TURN_DEFAULT=45`, `TURN_CHOICES={30,45,60,90}`, `INVITE_SECONDS=30`, `SNOOZE_SECONDS=1800`, `OFFLINE_STAND_SECONDS=180`, `PING_EVERY=30`, `SILENT_AFTER=75`, `CLAIM_STAGGER=15`, `TBL_HEARTBEAT=60`, `TBL_EXPIRE=150`, `TBL_MIN_GAP=2`, `HI_HEARTBEAT=120`, `HI_MIN_GAP=2`, `PEER_EXPIRE=300`, `LIST_MODE_ABOVE=8`, `MAX_WATCHERS=8`, `SYN_MIN_GAP=5`, `TRACE_LINES=200`.
- `ns.Util.copy(t) -> t` (deep), `ns.Util.same(a, b) -> bool` (deep), `ns.Util.money(copper) -> string` (`123456 → "12g 34s 56c"`, `500000 → "50g"`, `0 → "0c"`; zero parts omitted).
- `ns.Names.normalize(raw) -> string|nil` — trim; strip one trailing `-Realm` where Realm contains no space and no hyphen; nil for empty or non-string.
- `ns.Emitter.new() -> e`; `e:on(event, fn)`; `e:emit(event, ...)`.
- `ns.Bus.new() -> bus`; `bus:join(name, receive)` with `receive(channel, sender, msg)`; `bus:leave(name)`; `bus:send(from, channel, target, msg)` queues a deep copy (GUILD → every joined name except `from`; WHISPER → `target` only, dropped if not joined); `bus:flush()` delivers FIFO until the queue is empty; `bus.filter = fn(from, to, channel, msg) -> list of msgs` (default `{msg}`; tests use it to drop or duplicate).
- `ns.Trace.new(limit) -> tr`; `tr:add(dir, channel, peer, msg)`; `tr:lines() -> {string}`; `tr.print` (fn or nil, called with each new line).
- `ns.Client.new(env) -> client`; `client:start()` (GUILD `HI` with `re=true`, starts heartbeats); `client:stop()` (stands if seated, GUILD `BYE`, cancels every timer); `client:receive(channel, sender, msg)`; `client:on(event, fn)`; `client:peerOffline(name)`. `receive` drops non-table messages, messages without `v`/`t`, and messages from its own name; for `v ~= 1` it only records the peer as `incompatible` and, when `v > 1`, emits `"update"` once per client lifetime. The one exception: a `v ~= 1` message with `t` `SIT` or `WAT` and a string `tid` is additionally handed to the session for the version refusal (Task 4); Presence still drops every other `v ~= 1` message.
- `client.presence:list() -> { {name, cls, guid, at, incompatible}, ... }` sorted by name bytes; `client.presence:get(name)`. Emits `"peers"` on change. A `HI` with `re=true` is answered by a WHISPER `HI` (`re=false`). `HI` repeats on GUILD every 120 s with `re=false`. Whenever the client's own `at` changes (from Task 4 on: sit, watch, stand, session end) it sends a GUILD `HI` with `re=false`, coalesced to at most one per 2 s, so peers always know where it sits. A peer silent for 300 s, or reported by `peerOffline`/`BYE`, is removed.
- `Sim.new() -> sim`; `sim:add(name, opts) -> client, env` (`opts`: `cls`, `status`, `group` = list of names, `db`; builds an `env` on a fake clock, joins the bus, calls `start`); `sim.makeEnv(name, cls) -> env`; `sim.bus` (the shared `Bus`; tests set `sim.bus.filter`); `sim:now()`; `sim:run(seconds)` (advances the clock, both `now` and `epoch`, in 1 s steps, firing due timers, then flushing the bus); `sim:offline(name)` / `sim:online(name)` (the bus drops everything to and from the name); `sim:relog(name) -> client` (fresh Client with the same name); `sim.sent` = array of `{at, from, channel, target, msg}` (`at` = `sim:now()` at the send); `sim:count(pred) -> n`.

- [ ] **Step 1: Write the failing tests.**

```lua
it("normalizes names", function()
  eq(N.normalize("Иван Петров"), "Иван Петров")
  eq(N.normalize("Knikin Granitfaust-CAMWOWEU4Realm5PvE"), "Knikin Granitfaust")
  eq(N.normalize("  Мария Стоянова "), "Мария Стоянова"); eq(N.normalize(""), nil); eq(N.normalize(nil), nil)
end)
it("bus copies, orders, filters", function() --[[ mutating msg after send does not change what is delivered;
  two sends arrive in order; filter returning {m, m} delivers twice; whisper to an unknown name is dropped ]] end)
it("money formats", function() eq(U.money(123456), "12g 34s 56c"); eq(U.money(500000), "50g"); eq(U.money(0), "0c") end)
it("trace keeps the last 200 lines", function() --[[ tr = Trace.new(200); tr.print counts calls; 201 tr:add("out", "WHISPER", "P"..i, {v=1, t="HI"})
  for i = 1..201: #tr:lines() == 200; lines()[1] contains "P2", lines()[200] contains "P201"; print called 201 times ]] end)
it("newcomer learns everyone by whisper, not by a guild burst", function()
  local sim = Sim.new(); sim:add("Иван Петров", {cls="MAGE"}); sim:add("Мария Стоянова", {cls="PRIEST"}); sim:run(1)
  local n0 = sim:count(function(m) return m.channel == "GUILD" end)
  local c = sim:add("Kiro Barley", {cls="ROGUE"}); sim:run(1)
  eq(#c.presence:list(), 2); eq(c.presence:get("Иван Петров").cls, "MAGE")
  eq(sim:count(function(m) return m.channel == "GUILD" end) - n0, 1)
end)
it("drops a peer on BYE, on peerOffline and after 300 s of silence", function() --[[ sim with a, b, c, d; sim:run(1): a knows B, C, D;
  sim:offline(D); sim:run(301) -> a.presence:get(D) == nil, B and C still listed; b:stop(); sim:run(1) -> get(B) == nil;
  a:peerOffline(C) -> get(C) == nil at once; #a.presence:list() == 0 ]] end)
it("flags a newer protocol once and lists the peer as incompatible", function()
  local seen = 0; a:on("update", function() seen = seen + 1 end)
  a:receive("GUILD", "Нов Клиент", {v=2, t="HI"}); a:receive("GUILD", "Нов Клиент", {v=2, t="ZZZ"})
  eq(seen, 1); eq(a.presence:get("Нов Клиент").incompatible, true)
end)
it("ignores garbage: a string, a table without t, its own name", function()
  -- a = sim:add(A) in a fresh sim, as in the test above
  a:receive("GUILD", "Гошо Тестов", "hello"); a:receive("GUILD", "Гошо Тестов", {v=1})
  a:receive("GUILD", A, {v=1, t="HI", cls="MAGE"})
  eq(a.presence:get("Гошо Тестов"), nil); eq(a.presence:get(A), nil); eq(#a.presence:list(), 0)
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core`.** Expected: FAIL, modules missing.
- [ ] **Step 3: Implement the files in the order listed and add them to the TOC under `# Core` in that order.**
- [ ] **Step 4: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit (only if the user has authorized commits in this session).** `feat: core foundations, in-memory bus, presence`

### Task 4: Lobby and seating

**Files:**
- Create: `core/Lobby.lua`, `core/Session.lua`; Modify: `core/Client.lua`, `TavernGames.toc`; Test: `tests/core/lobby_test.lua`

**Interfaces:**
- Consumes: `Client`, `Presence`, `Sim`, `Const`.
- Produces:
  - `client:openTable{game="ttt", access="guild", turn=45} -> tid | nil, code` — `tid = env.me .. "#" .. env.epoch()`; codes `"busy"` (already at a table), `"game"`, `"access"`, `"turn"`. The creator takes seat 1 and is host at epoch 1.
  - `client:sit(tid, seat)`, `client:watch(tid)`, `client:stand()` (also stops watching). Refusals arrive as the event `"refused"(tid, why)`.
  - `client.lobby:tables() -> {record, ...}`; `client.lobby:get(tid)`; record = `{tid, game, host, epoch, access, turn, state, seats, watchers, stake=nil}`. Emits `"tables"`.
  - `client.session` — nil, or `{tid, role ("host"|"player"|"watcher"), mySeat, host, epoch, seq, seats, state, status, deadline}`; `session:record() -> TBL fields`. Emits `"session"` on any change (argument: the session or nil).
- Rules:
  - A player is at one table at most (seated or watching). The host checks a request in this order: table exists (`"gone"`), requester known to Presence and compatible (`"version"`), requester not at another table per Presence `at` (`"busy"`), access (`"access"`: `guild` = any Presence peer; `invite` = in the table's invited set; `group` = `env.inGroup(peer.guid)`), seat free (`"taken"`), watcher limit 8 (`"full"`). Watching is subject to the same access rule as sitting.
  - Version refusal (spec 6.2): a `v ~= 1` `SIT` or `WAT` whose string `tid` is a table I host is answered with a whispered `SNO{v=1, tid, why="version"}`; nothing else changes.
  - Every sit, watch, stand or session end changes the client's own `at`, which triggers the coalesced GUILD `HI` from Task 3.
  - Seating changes are ordered events (`EV` seat 0 `sit`/`stand`); the newcomer additionally gets an `SNP`.
  - The host announces `TBL` on GUILD on every record change, coalesced to one per 2 s per table, and every 60 s; a newcomer's `HI re=true` is answered with a whispered `TBL`. Others drop a table after 150 s without `TBL`, or on `END`.
  - A `TBL` is accepted when the sender equals its `h` field and (`e` is greater than the known epoch, or equal with the same host). Equal epoch from a different host: the claimant with the lower seat index in `s` wins.
  - When the last seated player stands, the host sends `END` and the session ends for watchers. Standing by a non-host frees the seat. (Host leaving with others seated: Task 6.)

- [ ] **Step 1: Write the failing tests** (`A`, `B`, `C` = `"Иван Петров"`, `"Мария Стоянова"`, `"Kiro Barley"`; `a`, `b`, `c` their clients):

```lua
it("open -> everyone sees the table; sit fills the dashed chair", function()
  local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
  eq(b.lobby:get(tid).seats, {A, false}); b:sit(tid, 2); sim:run(3)
  eq(c.lobby:get(tid).seats, {A, B}); eq(b.session.mySeat, 2); eq(b.session.role, "player")
  eq(c.presence:get(B).at, tid)
end)
it("two players click the same chair: one sits, the other is refused 'taken'", function() --[[ b:sit and c:sit before sim:run ]] end)
it("invite-only refuses strangers; group table asks env.inGroup", function() --[[ why == "access"; group member is seated ]] end)
it("cannot sit at two tables", function() --[[ why == "busy" ]] end)
it("ten quick changes produce at most one TBL per 2 s", function() --[[ GUILD TBL count for tid within sim:run(2) <= 1 ]] end)
it("table disappears on END and after 150 s of silence", function() --[[ a:stand() -> gone; host offline -> gone after sim:run(151) ]] end)
it("late joiner gets the table by whisper", function() --[[ sim:add after open; lobby:get(tid) ~= nil after sim:run(1) ]] end)
it("ignores TBL whose sender is not its host field", function() --[[ b:receive("GUILD", C, {v=1,t="TBL",tid=tid,h=A,e=9,...})
  (C is not b's own name, so the sender ~= h check is what drops it); b.lobby:get(tid).epoch == 1 and .host == A ]] end)
it("refuses a newer client's SIT with 'version'", function() --[[ a:receive("WHISPER", "Нов Клиент", {v=2,t="SIT",tid=tid,seat=2}); sim:run(1):
  exactly one entry in sim.sent from A, WHISPER to "Нов Клиент", msg.t == "SNO", msg.tid == tid, msg.why == "version"; a.session.seats == {A, false} ]] end)
it("watcher is counted and limited to 8", function() --[[ record.watchers == 8; the ninth WAT -> "full" ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/lobby_test.lua`.** Expected: FAIL, `openTable` is nil.
- [ ] **Step 3: Implement `core/Lobby.lua` (directory, expiry, acceptance rule) and the seating half of `core/Session.lua` (host and member roles, `SIT/SNO/STD/WAT`, seat events, `SNP` to newcomers, coalesced announce).**
- [ ] **Step 4: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit (only if the user has authorized commits in this session).** `feat: lobby directory and seating`

### Task 5: Table session — ordered play

**Files:**
- Modify: `core/Session.lua`, `core/Client.lua`; Test: `tests/core/session_test.lua`

**Interfaces:**
- Consumes: `ns.Engines[game]` contract (Task 2), Task 4 session.
- Produces: `client:act(action) -> true | nil, code` (local pre-check with `Engine.apply` on a copy; then `ACT` to the host, or applied directly when host). `session.status`: `"open"` (waiting for players), `"live"`, `"aborted"` (kept until the next `start`). `session.deadline` = `env.now()`-based end of the current turn, or nil. Event `"desync"(tid)`.
- Rules:
  - When all seats are filled the host emits `{k="start"}` (engine `new` with `first=1`); status `"live"`, record state `"live"`.
  - Host: validates each `ACT` (the sender must hold a seat; the action goes through `Engine.apply` on the real state), assigns `q = seq + 1`, whispers `EV` to every other seated player and watcher. An invalid `ACT` is dropped silently.
  - Members: `q == seq + 1` → apply; `q <= seq` → ignore; `q > seq + 1` → discard and send `SYN` (at most one per 5 s). `EV`/`SNP`/`TCK` are accepted only from the current host and with `e >= epoch` (Task 6 adds higher-epoch adoption from seated senders; an `EV` from a non-host is never applied). If an `EV` from the host fails `Engine.apply`, emit `"desync"` and send `SYN`.
  - `TCK` every 30 s carries `q`; a member behind it sends `SYN`. Members send `PNG` every 30 s.
  - Turn timer: after every event that leaves `state.turn` set, the host arms `turn` seconds; on expiry it emits `Engine.auto(state, seat)` as that seat's event with `auto=true`. `left` in the `EV` gives members the countdown.
  - When `Engine.system(state)` returns an action, the host emits it (seat 0) after the returned delay.
  - A seated player standing while `"live"` → `stand` event. If the seated players then number fewer than `Engine.minSeats`, an `abort` event follows: status `"aborted"`, record state `"open"`. Otherwise the match continues and the emptied seat's turns are played by the turn timer. For ttt (2 of 2) any stand aborts. No winner is recorded (stage 1 has no stakes).

- [ ] **Step 1: Write the failing tests.**

```lua
it("plays a full round on three clients (host, guest, watcher) with identical boards", function()
  -- a hosts, b sits seat 2, c watches; moves 1:1 2:4 1:2 2:5 1:3, sim:run(1) after each
  eq(a.session.state.line, {1,2,3}); eq(b.session.state.board, a.session.state.board)
  eq(c.session.state.score, {1,0}); sim:run(3); eq(b.session.state.round, 2)   -- system "next" after 3 s
end)
it("applies each event once when every whisper is duplicated", function()
  sim.bus.filter = function(_, _, _, m) return {m, m} end   -- then a:act{k="mark", c=1}; sim:run(1)
  eq(b.session.seq, a.session.seq); eq(b.session.state.board[1], 1); eq(b.session.state.turn, 2)
end)
it("gap triggers SYN and snapshot heals", function() --[[ filter drops the first EV to b; the next EV arrives:
  exactly one SYN from b in sim.sent; after sim:run(1) b's board and seq equal a's ]] end)
it("out-of-turn and taken-cell actions never become events", function() --[[ b:act out of turn returns nil,"turn"; forged ACT leaves host seq unchanged ]] end)
it("ACT from a watcher or a stranger is ignored", function() --[[ a:receive("WHISPER", C, {v=1,t="ACT",...}); seq unchanged ]] end)
it("EV from a non-host is ignored", function() --[[ b:receive("WHISPER", C, forged EV); board unchanged ]] end)
it("turn timeout plays the first empty cell, flagged auto, no loss", function()
  sim:run(46); eq(a.session.state.board[1], 1); eq(a.session.status, "live"); eq(b.session.state.turn, 2)
end)
it("no auto action while waiting for rematch", function() --[[ phase "match"; sim:run(120); phase still "match" ]] end)
it("rematch by both restarts 0:0 with the other seat first", function() --[[ X wins three rounds (sim:run(4) after each round);
  a:act{k="rematch"}; sim:run(1) -> phase still "match" on a, b, c; b:act{k="rematch"}; sim:run(1) -> on a, b and c:
  phase "play", score {0,0}, round 1, turn 2 ]] end)
it("standing mid-match aborts without a winner and reopens the chair", function() --[[ a.session.status "aborted"; c.lobby:get(tid).state "open"; seats {A, false} ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/session_test.lua`.** Expected: FAIL.
- [ ] **Step 3: Implement the play half of `core/Session.lua`.**
- [ ] **Step 4: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit (only if the user has authorized commits in this session).** `feat: host-ordered table session with turn timer`

### Task 6: Disconnects, reconnect, host succession

**Files:**
- Create: `core/Succession.lua`, `tests/helpers/fake_engine.lua`; Modify: `core/Session.lua`, `TavernGames.toc`; Test: `tests/core/succession_test.lua`

**Interfaces:**
- Consumes: Task 5 session; `Const.SILENT_AFTER`, `CLAIM_STAGGER`, `OFFLINE_STAND_SECONDS`.
- Produces: `ns.Succession.candidates(seats, oldHost) -> {name, ...}` (seated players in ascending seat index, old host excluded); `ns.Succession.wins(seats, hostA, hostB) -> hostA|hostB` (the one with the lower seat index). `session.hostSilent` (bool, for the UI banner).
- Rules:
  - **Offline seat:** the host tracks `lastHeard` per seated player (any message from them). `peerOffline`/`BYE` does not shorten the wait. When `now − lastHeard ≥ 180` the host emits `stand` with `why="offline"` (then `abort` if live and fewer than `minSeats` remain seated, Task 5). Until then their turns are played by the turn timer. A watcher silent for 75 s is dropped.
  - **Reconnect:** when the host receives `HI` from a name seated at its table, it whispers `SNP`; a client receiving an `SNP` for a table where its own name holds a seat adopts the session.
  - **Graceful host leave** (`stand`/`stop` with another seated player): the host emits its own `stand` event, then whispers `HND{e=epoch+1, to=first candidate}` to every member (seated players and watchers), then leaves. Each member sets `host = HND.to`, `epoch = HND.e`. The successor becomes host and itself whispers an `SNP` at the new epoch to all members, re-arms a full turn timer, announces `TBL`. A member that gets the successor's `SNP` before the `HND` accepts it when `SNP.tbl.h == sender` and the sender is seated. When fewer than `minSeats` remain seated (ttt) the match aborts, but the table lives on under the new host; otherwise (fake engine, 2 of 3) play continues.
  - **Host silence:** a member that hears nothing from the host for 75 s sets `hostSilent`. The candidate at rank `k` (0-based) claims after `75 + 15·k` s of silence: epoch + 1, whispers an `SNP` built from its own state to all members, announces `TBL`, re-arms a full turn timer. The old host keeps its seat and falls under the offline-seat rule (`lastHeard` = its last message).
  - **Convergence:** a higher epoch than mine is adopted only from a sender who holds a seat in my current `seats`, and only via `TBL`, `SNP`, `HND` or `TCK` (never via `EV`; an `EV` from a non-host is never applied). Adopting makes me a member of that sender (a host demotes itself and sends `SYN`); a higher epoch from anyone else is ignored. The same epoch from two hosts → `Succession.wins`; the loser demotes and sends `SYN`. Messages with a lower epoch are ignored.
  - Watchers never become host. If no seated candidate is left, the table expires from the lobby after 150 s and watchers' sessions end.

- [ ] **Step 1: Write the failing tests.** `fake_engine.lua` registers `ns.Engines.fake` in tests only: `minSeats=2`, `maxSeats=3`, action `{k="inc"}` increments `state.n`, turn rotates 1→2→3, `auto` returns `{k="inc"}`, never ends.

```lua
it("offline player's turns are auto-played, then he is stood up at 180 s", function()
  -- ttt, a hosts, b seat 2, live; the 180 s count starts at B's last message, not at sim:offline
  local last = 0; for _, s in ipairs(sim.sent) do if s.from == B then last = s.at end end
  sim:offline(B); sim:run(179 - (sim:now() - last)); eq(a.session.seats[2], B); sim:run(2)
  eq(a.session.seats[2], false); eq(a.session.status, "aborted")
end)
it("relog within 3 minutes restores seat, board and score", function()
  sim:offline(B); sim:run(60); local b2 = sim:relog(B); sim:run(2)
  eq(b2.session.mySeat, 2); eq(b2.session.state.board, a.session.state.board); eq(b2.session.state.score, a.session.state.score)
end)
it("host stands mid-turn: next player becomes host, timer restarts, no move lost or doubled", function()
  -- fake engine, a b c seated, d watches; three incs; a:stand(); sim:run(2)
  eq(b.session.role, "host"); eq(b.session.epoch, 2); eq(d.session.host, B); eq(d.lobby:get(tid).host, B)
  eq(c.session.state.n, 3); eq(c.session.status, "live")   -- 2 of 3 still seated >= minSeats: no abort
  sim:run(46); eq(c.session.state.n, 4)   -- one auto move after a full fresh turn
end)
it("a higher epoch from a non-seated sender is ignored", function() --[[ fake engine, a b c seated, d watches;
  b:receive("WHISPER", D, {v=1,t="SNP",tid=tid,e=9,q=99,tbl={...,h=D,e=9},st=...}) and the same as TBL on GUILD;
  b.session.host == A, b.session.epoch == 1, b.session.seq unchanged ]] end)
it("host vanishes mid-turn: guest claims after 75 s and play continues", function()
  -- ttt, a hosts, b seat 2, c watches; a:act mark 1; then
  sim:offline(A); sim:run(76); eq(b.session.role, "host"); eq(b.session.hostSilent, false)
  ok(b:act{k="mark", c=9}); sim:run(1); eq(c.session.state.board[9], 2); eq(c.session.state.board[1], 1)
end)
it("split brain converges", function() --[[ fake engine, a b c seated; A offline; filter blocks B<->C whispers so both claim epoch 2;
  remove the filter, sim:run(35): b and c both report host == B, equal seq, equal state.n ]] end)
it("returning old host demotes", function() --[[ after B claimed: sim:online(A); sim:run(35); a.session.role == "player"; a.session.host == B; a.session.epoch == 2 ]] end)
it("candidates skip the old host and keep seat order", function()
  eq(S.candidates({"a","b",false,"d"}, "a"), {"b","d"}); eq(S.wins({"a","b","c"}, "c", "b"), "b")
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/succession_test.lua`.** Expected: FAIL.
- [ ] **Step 3: Implement `core/Succession.lua` and wire it into `Session`.**
- [ ] **Step 4: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit (only if the user has authorized commits in this session).** `feat: offline auto-stand, reconnect snapshot, host succession`

### Task 7: Invites

**Files:**
- Create: `core/Invites.lua`; Modify: `core/Client.lua`, `TavernGames.toc`; Test: `tests/core/invites_test.lua`

**Interfaces:**
- Produces: `client:invite(name) -> true | nil, code` (host of a table with a free seat only; codes `"nothost" "unknown" "seated" "pending"`); adds `name` to the table's invited set. `client:answerInvite(tid, answer)` with `"yes"`, `"no"`, `"snooze"`. `ns.Invites.autoReason(status, snoozeUntil, epochNow, atTable) -> why|nil`, checked in the order `combat`, `instance`, `busy` (`status.busy` or `atTable`), `snooze` (`epochNow < snoozeUntil`).
- Events: `"invite"({tid, game, host, seats, expires})` on the invitee (`expires` on the `env.now()` clock); `"inviteGone"(tid)`; `"inviteAnswer"(name, a, why)` on the host.
- Rules: an auto-declined invite never emits `"invite"`; it answers `INR a="auto"` with `why`. No answer within 30 s → `INR a="auto", why="timeout"` and `"inviteGone"`. `"snooze"` answers `"no"` and sets `env.db.snoozeUntil = env.epoch() + 1800`. `"yes"` sends `SIT` for the lowest free seat in the current lobby record (no record → `"refused"(tid, "gone")` locally). One pending invite per invitee (a second is auto-answered `"busy"`). `"inviteGone"` also fires when the table ends or fills. Only the host invites in stage 1.

- [ ] **Step 1: Write the failing tests.**

```lua
it("invite -> yes seats the guest at an invite-only table", function()
  local tid = a:openTable{game="ttt", access="invite", turn=45}; sim:run(3); ok(a:invite(B)); sim:run(1)
  eq(got.tid, tid); eq(got.host, A); b:answerInvite(tid, "yes"); sim:run(3); eq(a.session.seats, {A, B})
end)
it("auto-decline reasons, in order", function()
  eq(I.autoReason({combat=true, instance=true}, 0, 100, false), "combat")
  eq(I.autoReason({instance=true}, 0, 100, false), "instance"); eq(I.autoReason({}, 0, 100, true), "busy")
  eq(I.autoReason({}, 200, 100, false), "snooze"); eq(I.autoReason({}, 200, 200, false), nil)
end)
it("invitee in combat: no toast event, host hears ('auto','combat')", function() --[[ b added with status {combat=true};
  a opens an invite table, ok(a:invite(B)); sim:run(1): b's "invite" handler called 0 times; a's "inviteAnswer" got (B, "auto", "combat") ]] end)
it("unanswered invite times out at 30 s", function() --[[ host sees ("auto","timeout"); invitee sees inviteGone ]] end)
it("snooze lasts 30 minutes", function() --[[ second invite within 1800 s -> why "snooze", no "invite"; after sim:run(1801) a new invite shows ]] end)
it("stale yes after the chair was taken is refused 'taken'", function() --[[ a opens a guild table, invites B; sim:run(1);
  c:sit(tid, 2); sim:run(1); b:answerInvite(tid, "yes"); sim:run(1): b's "refused" got (tid, "taken"); b.session == nil;
  a.session.seats == {A, C}; b saw "inviteGone"(tid) ]] end)
it("yes after the table closed is refused 'gone'", function() --[[ a opens an invite table, invites B; sim:run(1); a:stand(); sim:run(1);
  b:answerInvite(tid, "yes"); sim:run(1): b's "refused" got (tid, "gone"); b.session == nil; b saw "inviteGone"(tid) ]] end)
```

- [ ] **Step 2: Run `bash t.sh tests/core/invites_test.lua`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit (only if the user has authorized commits in this session).** `feat: invites with auto-decline and snooze`

### Task 8: Bots, locale, rules-book data, hall layout

**Files:**
- Create: `core/Bots.lua`, `core/Locale.lua`, `core/Help.lua`, `core/HallLayout.lua`, `locale/bg.lua`, `locale/en.lua`; Modify: `TavernGames.toc`
- Test: `tests/core/bots_test.lua`, `tests/core/locale_help_test.lua`, `tests/core/hall_layout_test.lua`

**Interfaces:**
- `ns.Bots.enable(client, env, makeEnv) -> bots`; `ns.Bots.disable(bots)`; `bots:hostTable()` (an idle bot opens a guild table and waits; when all bots are busy a new one named `"Бот Номер" .. n` is spawned, up to 12 bots in total); `bots:inviteMe()` (an idle bot opens an invite-only table and invites `env.me`); `bots.list` = clients. `makeEnv(name, cls) -> env` is supplied by the caller (Sim in tests, the adapter in game). Starting bots: `"Бот Иванов"` PRIEST, `"Bot Barleybrew"` WARRIOR, `"Бот Петрова"` MAGE.
  - Routing (over a private `Bus`): `enable` wraps `env.send` — a WHISPER to a bot goes only to the bus; GUILD goes to the real send **and** the bus, except that a GUILD message whose `tid` belongs to a table with a bot as host, in its seats or in its invited set goes to the bus only, and a `HI` whose `at` is a bot-hosted table goes to the real send with `at` cleared (a copy) and to the bus unchanged; no bot name or bot table ever reaches the real guild channel. Everything else is unchanged. Bot sends: WHISPER to `env.me` → `client:receive`; to another bot → bus; elsewhere → dropped. Bot GUILD → `client:receive` and the other bots only, **never the real guild channel**. Delivery happens through `env.after(0, flush)`.
  - Behaviour: accept an invite after 1 s; on its turn act `Engine.auto` after 1.5 s; in phase `"match"` send `rematch` after 2 s.
- `ns.Locale.set(lang)` (`"bg"`/`"en"`), `ns.Locale.lang()`, `ns.Locale.tables` (`{bg=..., en=...}`), `ns.L(key, ...) -> string` (`string.format` when extra arguments are given; a missing key returns the key).
- `ns.Help.topics` = ordered list of `{id, title, blocks}`; stage 1 ids `"hall"`, `"ttt"`, `"soon"`. A block is `{kind="p"|"example"|"board", key=<locale key>, board=<9 cells, kind "board">, line=<{a,b,c}>}`. `ns.Help.get(id)`. `ns.Help.intro` = 4 steps of `{title, text}` locale keys: hall → sitting → invites → the ⓘ book.
- `ns.HallLayout.mode(n) -> "floor"|"list"` (`"list"` when `n > 8`); `ns.HallLayout.slots(n, w, h) -> {{x,y},...}` (cell centres of a grid whose column count is `n` for n ≤ 3, 2 for 4, 3 for 5–6, 4 for 7–8); `ns.HallLayout.chairs(seats, r) -> {{x,y},...}` (seat `i` at angle `90° − (i−1)·360/seats`, y up); `ns.HallLayout.order(records, me) -> records` (the table I am at first, then `"open"` before `"live"`, then `tid` ascending).
- Copy rules (spec 5.3а): short sentences, tavern talk, an example in every topic, no legal language. Pinned bg strings (the en ones are faithful translations):
  - `help.ttt.example` = „Иван е Х, Мария е О. Редуват се. Иван нарежда три Х в редица и печели играта. Който пръв спечели 3 игри, печели мача.“
  - `help.hall.example` = „Виждаш маса с празен стол с пунктир. Кликаш на стола и вече седиш. Ако масата е пълна, кликни на нея, за да гледаш.“
  - `help.soon.p` = „Скоро идват Death Roll, Белот, Сантасе, Табла и Тексас Холдем, и игра на залог с тефтер на дълговете.“
  - `help.ttt` also covers: time runs out → the addon plays the first free cell for you and you do not lose; a draw gives nobody a point; „Реванш“. It has one `board` block showing a won line. `help.hall` also covers: opening a table, who may sit (three options), inviting, the three toast buttons, standing up, and what happens when you disconnect (3 minutes).
  - UI keys needed by Tasks 10–13 are added to both files by those tasks.

- [ ] **Step 1: Write the failing tests.**

```lua
it("one human plays a whole match against a bot without touching the guild channel", function()
  local a, envA = sim:add(A, {cls="MAGE"}); local bots = Bots.enable(a, envA, sim.makeEnv)
  sim:run(1)   -- let the bots' HI reach a's Presence before inviting
  local tid = a:openTable{game="ttt", access="invite", turn=45}; ok(a:invite("Бот Иванов")); sim:run(5)
  eq(a.session.seats[2], "Бот Иванов")
  -- loop up to 400 s: when it is seat 1's turn, a:act(E.auto(state, 1)); sim:run(1)
  eq(a.session.state.phase, "match")
  eq(sim:count(function(m) return m.channel == "GUILD" and m.from ~= A end), 0)
  eq(sim:count(function(m) return m.channel == "GUILD" and m.msg.tid == tid
    and m.msg.s and (m.msg.s[1] == "Бот Иванов" or m.msg.s[2] == "Бот Иванов") end), 0)   -- bot table stays on the bot bus
end)
it("a bot can host and invite me", function() --[[ bots:inviteMe(); sim:run(2); "invite" event whose host is a bot name ]] end)
it("hostTable spawns extra bots up to 12", function() --[[ nine calls -> #a.lobby:tables() == 9 after sim:run(3) ]] end)
it("disable restores env.send and removes the bots from presence", function() --[[ keep orig = envA.send before enable; after enable
  and sim:run(1): envA.send ~= orig, a.presence:get("Бот Иванов") ~= nil; Bots.disable(bots); sim:run(1): envA.send == orig;
  a.presence:get(n) == nil for "Бот Иванов", "Bot Barleybrew", "Бот Петрова" ]] end)
it("bg and en have the same keys and the same number of % placeholders per key", function() --[[ T = ns.Locale.tables;
  next(T.bg) ~= nil; ok(T.en[k], k) for every k in T.bg and ok(T.bg[k], k) for every k in T.en; per key, the count of
  "%" placeholders (after removing "%%") is eq in bg and en ]] end)
it("every help block and intro key exists in both languages; topics are hall, ttt, soon", function() --[[ ids of ns.Help.topics ==
  {"hall","ttt","soon"}; #ns.Help.intro == 4; every block key, topic title and intro title/text key is a string in T.bg and T.en;
  "ttt" has exactly one "board" block with 9 cells and a 3-cell line ]] end)
it("L formats and falls back to the key", function() eq(ns.L("no.such.key"), "no.such.key") end)
it("hall switches to list above 8 tables", function() eq(H.mode(8), "floor"); eq(H.mode(9), "list") end)
it("8 slots are distinct and inside the floor", function() --[[ slots(8, 560, 420): 8 unique points, 0 < x < 560, 0 < y < 420 ]] end)
it("seat 1 is at the top", function() --[[ chairs(2, 40): [1] == (0, 40), [2] == (0, -40), tolerance 1e-6 ]] end)
it("my table comes first, then open, then live", function()
  local r = function(tid, st, s) return {tid=tid, state=st, seats=s} end
  local out = H.order({r("b#2","live",{A,false}), r("c#3","open",{"X",false}), r("a#1","live",{"X","Y"}), r("d#4","open",{"Z",false})}, A)
  eq({out[1].tid, out[2].tid, out[3].tid, out[4].tid}, {"b#2", "c#3", "d#4", "a#1"})
end)
```

- [ ] **Step 2: Run `bash t.sh tests/core`.** Expected: the three new files FAIL.
- [ ] **Step 3: Implement the modules and write the bg/en topic texts and intro steps.**
- [ ] **Step 4: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 5: Commit (only if the user has authorized commits in this session).** `feat: bot mode, locale tables, rules-book content, hall layout`

### Task 9: Libraries, fonts, textures, wire format

**Files:**
- Create: `Libs/**`, `media/fonts/*`, `media/*.tga`, `tools/gen_textures.py`, `.pkgmeta`, `LICENSE-THIRD-PARTY.md`, `core/Wire.lua`; Modify: `TavernGames.toc`; Test: `tests/core/wire_test.lua`

**Interfaces:**
- `ns.Wire.new(serializer, deflate) -> wire`; `wire:pack(msg) -> string` (`serializer:Serialize` → `deflate:CompressDeflate` → `deflate:EncodeForWoWAddonChannel`); `wire:unpack(str) -> msg | nil` (nil on any decode/decompress/deserialize failure or a non-table result; never raises).
- Textures (32-bit uncompressed TGA, power-of-two sizes): `wood` 256×256 tiling, `felt` 256×256 tiling, `frame` 64×64 brass nine-slice border, `ring` 128×128 brass ring, `tabletop` 128×128 round table, `chair` 64×64 white disc (tinted with the class color in game), `chair_empty` 64×64 dashed ring, `button` 128×32, `button_hi` 128×32, `glow` 128×128 soft gold, `info` 32×32 ⓘ, `icon` 64×64 mug (minimap and TOC icon). Colors from Global Constraints.

- [ ] **Step 1: Ask the user for an OK to download, then fetch from official sources only:** Ace3 (the six listed libraries and ChatThrottleLib, from the official Ace3 release on WowAce/CurseForge or the WoWUIDev/Ace3 GitHub), LibDeflate (SafeteeWoW/LibDeflate release), LibDataBroker-1.1 (tekkub/libdatabroker-1-1), LibDBIcon-1.0 (WowAce); Alegreya SC Bold, Alegreya Sans Regular and Bold, Alegreya Italic as **static TTF** (Huerta Tipográfica GitHub repositories, not the variable fonts) with `OFL.txt`; Pillow (`python -m pip install pillow`). Record name, version, source URL and license per item in `LICENSE-THIRD-PARTY.md`. Verify with Pillow that each font has glyphs for „Жълтата дюля“ (non-empty bounding box per character).
- [ ] **Step 2: Write `.pkgmeta`** with the same libraries as `externals`, `package-as: TavernGames`, and `ignore:` `docs`, `tests`, `tools`, `t.sh`. Add the library files to the TOC under `# Libs` in dependency order (LibStub, CallbackHandler-1.0, then the rest) and `core/Wire.lua` under `# Core`.
- [ ] **Step 3: Write the failing test `tests/core/wire_test.lua`** (loads LibStub, AceSerializer-3.0 and LibDeflate with `Loader.lib`; if a library needs a WoW global at load time, stub exactly that global at the top of this test file):

```lua
local m = {v=1, t="TBL", tid="Иван Петров#1763650000", s={"Иван Петров", false}, e=1}   -- file scope: used by tests 1 and 3
it("round-trips Cyrillic names and nested tables", function()
  eq(wire:unpack(wire:pack(m)), m)
end)
it("snapshot above 255 bytes survives pack/unpack", function()
  -- snap = SNP with 2 seats, 8 distinct Cyrillic watcher names in tbl and a field of about 400 bytes of
  -- non-repeating Cyrillic prose written inline, so the packed size stays above 255 after deflate
  ok(#wire:pack(snap) > 255); eq(wire:unpack(wire:pack(snap)), snap)
end)
it("packed text has no NUL byte", function() ok(not wire:pack(m):find("%z")) end)
it("garbage returns nil instead of raising", function() eq(wire:unpack("not a message"), nil); eq(wire:unpack(""), nil) end)
```

- [ ] **Step 4: Run `bash t.sh tests/core/wire_test.lua`** → FAIL; implement `core/Wire.lua`; run again → `4 passed, 0 failed`.
- [ ] **Step 5: Write `tools/gen_textures.py`** (procedural: wood grain from stretched noise between the two wood colors, felt from fine noise over the felt gradient, brass with a light top edge and dark bottom edge; fixed random seed so reruns are identical) and run `python tools/gen_textures.py`. Expected: 12 lines `media/<name>.tga WxH`, exit 0; the script ends with a self-check asserting every size is a power of two and the mode is RGBA.
- [ ] **Step 6: Run `bash t.sh`.** Expected: all pass (the TOC test now also checks that the `Libs/` paths exist).
- [ ] **Step 7: Commit (only if the user has authorized commits in this session).** `chore: vendor libraries, fonts, generated textures; wire format`

### Task 10: WoW adapter, slash commands, early risk probes

**Files:**
- Create: `wow/Adapter.lua`, `wow/Slash.lua`, `docs/superpowers/notes/2026-11-stage1-probe-results.md`; Modify: `TavernGames.toc`, `locale/*.lua`

**Interfaces:**
- Consumes: `Client.new(env)`, `Wire.new`, `Bots.enable`, `Trace`, `Locale`.
- Produces (for `ui/`): `ns.addon` (AceAddon object), `ns.client` (nil until the own name is known), `ns.db` (a routing proxy over AceDB on `TavernGamesDB`, the same object passed as `env.db`: reads and writes of `snoozeUntil`, `busy`, `debug` go to AceDB `char`, and of `lang`, `introDone`, `minimap={hide=false}` to AceDB `global`; both persist across reloads), `ns.ready(fn)` (runs `fn(client)` once the client exists), `ns.classColor(cls) -> r, g, b`, `ns.bots` (nil or the bots object).
- Behaviour:
  - Comm: `RegisterComm("TAVG")`; accept only the distributions `GUILD` and `WHISPER`; sender through `Names.normalize`; `wire:unpack` returning nil → drop. Send through `SendCommMessage` (AceComm splits above 255 bytes), priority `ALERT` for `EV`/`ACT`/`SNP`, `NORMAL` otherwise.
  - `env.now = GetTime`, `env.epoch = GetServerTime`, `env.after` over `C_Timer.NewTimer`, `status` from `InCombatLockdown()`, `IsInInstance()`, `db.busy or UnitIsDND("player")`, `inGroup(guid)` over `IsGUIDInGroup`, `log` into a `Trace` whose `print` is set while `db.debug` is on.
  - **Own full name** (`UnitName` gives only the first name on Forever): request the guild roster and find the entry whose GUID equals `UnitGUID("player")`; if not found within 5 s, send `{v=1, t="WHO", id=<guid>}` on GUILD and take the sender of the echo whose `id` matches. Only then create the Client and call `start()`. Not in a guild → no Client; the UI shows `L("hall.noguild")`; bot mode still works with `UnitName("player")` as the name.
  - A guild member going offline (roster update or the "has gone offline" system line) → `client:peerOffline(name)`. `PLAYER_LOGOUT` → `client:stop()`.
  - Suppress the system "player not found" line for names the addon whispered in the last 5 s (chat message event filter; use whichever filter API the client provides).
  - `/tavern` toggles the main window; `/tavern bots` toggles three bots; `/tavern bots host`; `/tavern bots invite`; `/tavern debug` toggles `db.debug` (lines such as `TAVG > WHISPER Име Фамилия: EV q=7` in the default chat frame, visible only to the player); `/tavern intro`; `/tavern reset` (clears `lang` and `introDone`); `/tavern probe` prints: the resolved own name, `IsInInstance()`, whether `InitiateTrade`, `C_TradeInfo.SetTradeMoney`, `SetSendMailMoney`, `SendMail` and `issecretvalue` exist, five `math.random(1, 1000000)` samples, and sends one packed 600-byte test whisper to itself, reporting `echo OK` or `echo LOST` after 5 s together with the `IsInInstance()` value at send time (the instance-messaging result).

- [ ] **Step 1: Ask the user for the Forever `Interface\AddOns` path and their OK, then link the repo into it:** `cmd /c mklink /J "<AddOns>\TavernGames" D:\Programming\TavernGames`.
- [ ] **Step 2: Implement `wow/Adapter.lua` and `wow/Slash.lua`; add them to the TOC with their locale keys.** Run `bash t.sh` → all pass (compile gate, locale parity).
- [ ] **Step 3: In-game checks, one character.** With `/console scriptErrors 1`, `/reload` shows no error. `/tavern probe` prints the own name as two words without a realm and `echo OK`. `/tavern debug` then `/tavern bots`: the trace shows `HI` from three bots, and no outgoing GUILD line carries a bot's name; invite „Бот Иванов“ to an invite-only table and check again: no outgoing GUILD `TBL`/`END` for that table.
- [ ] **Step 4: In-game checks, two guild characters with the addon.** With `/tavern debug` on both: each trace shows the other's `HI` under the full two-word name, and each receives the other's whispered `HI` reply. Enter a dungeon on one and run `/tavern probe` (does the echo arrive, does the other client still see its GUILD `HI`). Write the findings — name format, instance behaviour, `math.random` samples, trade/mail API presence (`InitiateTrade`, `C_TradeInfo.SetTradeMoney`, `SetSendMailMoney`, `SendMail`), the in-instance echo result — into the notes file (spec §10), as an early signal for stage 2.
- [ ] **Step 5: Commit (only if the user has authorized commits in this session).** `feat: WoW adapter, slash commands, risk probes`

### Task 11: Theme, widgets, main window, hall

**Files:**
- Create: `ui/Theme.lua`, `ui/Widgets.lua`, `ui/MainWindow.lua`, `ui/Hall.lua`, `ui/NewTableDialog.lua`, `ui/Minimap.lua`; Modify: `TavernGames.toc`, `locale/*.lua`

**Interfaces:**
- Consumes: client events `"peers"`, `"tables"`, `"session"`, `"refused"`, `"update"`; `HallLayout`; `Util.money`; `ns.classColor`; `ns.ready`.
- Produces: `ns.Theme` (`color.<token> = {r,g,b}`, `font.heading/ui/italic` paths, `tex.<name>` paths); `ns.W.Panel(parent)`, `ns.W.Button(parent, text, onClick)`, `ns.W.Label(parent, style, text)` (`style` `"heading"|"ui"|"dim"|"italic"`), `ns.W.Info(parent, topicId)` (ⓘ button → `ns.HelpBook.open(topicId)`), `ns.W.Scroll(parent)`, `ns.W.Close(parent)`; `ns.MainWindow.toggle()`, `ns.MainWindow.show(tabId)`, `ns.MainWindow.addTab(id, titleKey, buildFn)`.
- Layout (mockup 02 option A): 1100×620 movable frame, closable with Escape, wood background; title bar with „Tavern Games“ in Alegreya SC, the tabs **Зала** and **Настройки** only, gold in bags (`Util.money(GetMoney())`, refreshed on `PLAYER_MONEY`), ⓘ (topic `"hall"`), close. Body: left 190 px „Отвори маса“ — six games, Морски шах active, the other five dimmed with „Скоро“; centre floor; right 250 px „В кръчмата сега“ — names in class color with „на маса при <Име>“ / „гледа“ / „в залата“; while I host a table with a free seat, clicking a name shows „Покани“ → `client:invite(name)`.
- Floor: `HallLayout.order` then `slots`; each table = `tabletop` + game name + chairs from `HallLayout.chairs`; an occupied chair is tinted with the class color and labelled with the first word of the name; an empty chair = `chair_empty`, clickable → `client:sit(tid, seat)`; my table has the `glow` texture pulsing; a live table shows „тече“ and clicking it → `client:watch(tid)`. More than 8 tables → a scroll list with rows (game, host, seats `1/2`, state, „Седни“ / „Гледай“). Empty hall: `L("hall.empty")` = „Няма отворени маси. Отвори първата!“
- New-table dialog: game (Морски шах); stake shown as the single preselected option „Само за удоволствие“; who may sit (Всеки от гилдията / Само поканени / Групата ми); turn time (30/45/60/90, default 45); „Отвори“ → `client:openTable`.
- Refusals appear as a line in the hall footer for 5 s: `refused.taken`, `.full`, `.access`, `.version` („Трябва ти по-нова версия на Tavern Games.“), `.busy`, `.gone`. The `"update"` event shows once: „Има по-нова версия на Tavern Games.“
- Minimap: LDB launcher `TavernGames` with `media/icon`; left click toggles the window; hidden when `db.minimap.hide`.

- [ ] **Step 1: Implement the six files and their locale keys (bg + en); add to the TOC.**
- [ ] **Step 2: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 3: In-game checks.** `/tavern` opens the window with wood and brass visuals and Cyrillic text in Alegreya (no missing-glyph boxes). `/tavern bots host` → a table appears with one chair in the bot's class color and one dashed chair; clicking the dashed chair seats you and your table glows. `/tavern bots` → three bots listed under „В кръчмата сега“. Run `/tavern bots host` nine times → the centre switches from the floor plan to the list at the ninth table. The gold figure matches the bag total. The minimap button toggles the window. A second character (if available) sees a real table within 3 s.
- [ ] **Step 4: Commit (only if the user has authorized commits in this session).** `feat: tavern theme, main window, hall floor plan`

### Task 12: Table frame, Морски шах view, invite toast

**Files:**
- Create: `ui/TableFrame.lua`, `ui/games/TicTacToeView.lua`, `ui/InviteToast.lua`; Modify: `TavernGames.toc`, `locale/*.lua`

**Interfaces:**
- Consumes: events `"session"`, `"invite"`, `"inviteGone"`, `"inviteAnswer"`, `"desync"`; `client:act`, `client:stand`, `client:invite`, `client:answerInvite`; engine state fields from Task 2.
- Produces: `ns.TableFrame.registerView(gameId, view)` where `view.build(parent) -> frame` and `view.update(frame, session)`; `ns.InviteToast`.
- Table frame (shown whenever `client.session` is non-nil, hidden when nil): felt in a wood frame; nameplates with class-colored names and a brass `ring` around the player on turn; turn countdown from `session.deadline`; ⓘ (topic = game id); „Стани“ (watchers: „Към залата“); „Покани“ for the host while a seat is free; watcher count. Banners: `table.waiting` („Чакаме втори играч…“), `table.aborted` („Играта е прекъсната.“), `table.hostSilent` („Връзката с домакина се губи…“), `table.resynced` for 3 s after `"desync"`.
- Морски шах view (mockup 03 `.ttt`): 3×3 cells of 62 px with 6 px gaps; X in light brass `#e9c98a`, O in `#e2735a`, Alegreya SC 44; on my turn an empty cell shows a faint ghost of my mark on hover and a click → `client:act{k="mark", c=i}`; when it is not my turn, or I am a watcher, the cells are dimmed and not clickable; the cells in `state.line` get the gold background and border; score as `2 : 1` under „до 3 победи“; in phase `"match"` a banner with the winner and the button „Реванш“ → `client:act{k="rematch"}` (after pressing: „Чакаме <Име>…“; hidden for watchers).
- Invite toast: top-centre frame; text `L("invite.text", host, gameName)` = „%s те кани на %s“; buttons „Приемам“ / „Не сега“ / „Не ме безпокой 30 мин“; a bar counting down 30 s to `invite.expires`; a soft sound on show; hides on `"inviteGone"`. Host side, `"inviteAnswer"` shows one line: accepted / declined / `invite.auto.combat` („%s е в бой.“) / `.instance` / `.busy` / `.snooze` / `.timeout`.

- [ ] **Step 1: Implement the three files and their locale keys; add to the TOC.**
- [ ] **Step 2: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 3: In-game checks with bots.** Open an invite-only table and invite „Бот Иванов“ → he sits within about 1 s and the match starts. Your marks appear at once, the bot answers in about 1.5 s, the ring moves to the player on turn. Win a round → three cells glow gold for 3 s, the score becomes `1 : 0`, the next round starts with the other player. Let your turn run out → the first empty cell is filled for you and the game goes on. Finish the match → „Реванш“ appears; press it → a new match at `0 : 0`. `/tavern bots invite` → the toast shows with a 30 s bar; try each button; after „Не ме безпокой 30 мин“ a second `/tavern bots invite` shows no toast. Enter combat and repeat → no toast.
- [ ] **Step 4: Commit (only if the user has authorized commits in this session).** `feat: table frame, tic-tac-toe board, invite toast`

### Task 13: Rules book, first-run intro, language, settings

**Files:**
- Create: `ui/HelpBook.lua`, `ui/Intro.lua`, `ui/Settings.lua`; Modify: `TavernGames.toc`, `locale/*.lua`, `wow/Adapter.lua` (first-run hook)

**Interfaces:**
- Consumes: `ns.Help.topics/get/intro`, `ns.Locale.set`, `ns.db`, `ns.MainWindow.addTab`.
- Produces: `ns.HelpBook.open(topicId)` (nil or unknown id opens `"hall"`); `ns.Intro.start(force)`.
- Rules book: 640×480 cream-paper frame titled „Книжка с правила“; topic list on the left (three topics); body on the right rendering blocks: `p` as text, `example` as an indented italic block with a brass left rule, `board` as a 3×3 mini board (26 px cells) with the `line` cells gold. Footer link „Покажи въведението пак“ → `Intro.start(true)`.
- First run (the first time the main window would open while `db.lang == nil`): a dialog titled „Език / Language“ with the buttons „Български“ and „English“ → `db.lang`, `Locale.set`, then the intro. Intro: 4 cards (hall → sitting → invites → ⓘ) with „Напред“, „Назад“, „Пропусни“ and a `1/4` counter; finishing or skipping sets `db.introDone = true`; then the main window opens. Not shown again unless `Intro.start(true)`.
- Settings tab: language (bg/en — saving asks to reload the UI with one confirm button), „Зает съм (не приемам покани)“ → `db.busy`, minimap button on/off, „Покажи въведението“, addon version and protocol version.

- [ ] **Step 1: Implement the three files and their locale keys; add to the TOC.**
- [ ] **Step 2: Run `bash t.sh`.** Expected: all pass.
- [ ] **Step 3: In-game checks.** `/tavern reset`, `/reload`, `/tavern` → the language dialog; pick English → the intro in English, 4 steps, „Skip“ works; `/tavern` now opens the hall in English. Settings → Български → after the reload everything is Bulgarian. ⓘ in the title bar opens the book on „Залата“; ⓘ on a table opens „Морски шах“ with the example board showing a gold line. „Покажи въведението пак“ reopens the intro. With „Зает съм“ on, `/tavern bots invite` shows no toast.
- [ ] **Step 4: Commit (only if the user has authorized commits in this session).** `feat: rules book, first-run intro, language and settings`

### Task 14: Stage 1 acceptance with two real clients

**Files:**
- Create: `docs/superpowers/notes/2026-11-stage1-acceptance.md` (results of the checks below)

**Interfaces:** none (verification only). Needs two guild characters on two accounts, both with the addon and `/tavern debug` on. If no second account is available, say so to the user and record steps 2–6 as not run; do not mark them passed on the strength of bot mode.

- [ ] **Step 1: `bash t.sh`.** Expected: `N passed, 0 failed`.
- [ ] **Step 2: Hall and seating.** A opens a guild table → B sees it within 3 s with A's chair in A's class color; B clicks the dashed chair → both table frames open; after the match starts the table shows „тече“ in the hall of anyone not seated. Both names display as „Име Фамилия“.
- [ ] **Step 3: Invites.** A opens „Само поканени“ and invites B → toast on B; accept → seated. Repeat with B in combat → A sees „<Име> е в бой.“
- [ ] **Step 4: Play.** A full match to 3 wins; the boards are identical on both clients after every move; „Реванш“ works; the trace shows no `SYN` during normal play.
- [ ] **Step 5: Disconnects.** B kills the game client mid-match: A sees B's turns auto-played and B stood up 3 minutes after the last contact, with the banner „Играта е прекъсната.“ Repeat, with B logging back in after 1 minute → B's table reopens with the same board and score.
- [ ] **Step 6: Host leaves.** A (host) presses „Стани“ with B seated: the table stays in the hall with B as host. Then, in a new match, A kills the client as host: within about 75–90 s B takes over and can move.
- [ ] **Step 7: Limits.** A's trace during 10 idle minutes with one open table: outgoing GUILD lines are at most one `TBL` per 60 s and one `HI` per 120 s. No addon output appears in any public chat channel.
- [ ] **Step 8: Record the results and every deviation in the notes file and report them to the user.**
- [ ] **Step 9: Commit (only if the user has authorized commits in this session).** `docs: stage 1 acceptance results`

---

## Self-review (applied)

- **Spec coverage:** 5.1 visuals → Tasks 9, 11; 5.2 hall, list mode above 8, invite toast, gold display → Tasks 7, 8, 11, 12; 5.3 Морски шах → Tasks 2, 12; 5.3а book, ⓘ on the title bar and on every table, first-run intro → Tasks 8, 13; 6.1 layers → File Structure; 6.2 comm, protocol version with a polite refusal, host authority, snapshot on reconnect, automatic action on timeout → Tasks 3–6, 9, 10; 6.5 bots and debug → Tasks 8, 10; 6.6 language choice → Task 13; §10 early risks → Task 10 `/tavern probe`. Deliberately absent (later stages): ledger, stakes, Сметки, Класация/Тефтер/История, commit-reveal, `/roll`.
- **Gaps fixed during review:** added the bag-gold display (spec 5.2) to Task 11; added the GUID (`id`) to `HI` so „Групата ми“ is checked by GUID instead of unreliable unit names; added the `TBL` coalescing test for the anti-spam anti-goal; added the "player not found" whisper-error filter; added a 3-seat fake engine (`minSeats=2`, so a host standing does not abort) because tic-tac-toe has a single successor candidate and cannot exercise split brain; made `bots:hostTable()` spawn extra bots so list mode (9 tables) can be checked by one person; intro step 3 is „покани“ because payment does not exist in stage 1.
- **Type consistency:** the refusal event is `"refused"(tid, why)` everywhere; engine methods are `new/apply/legal/auto/system/snapshot/restore`; session fields are `role/mySeat/host/epoch/seq/seats/state/status/deadline/hostSilent`; `env.inGroup` takes a GUID in Tasks 3, 4, 10; `Succession.wins(seats, hostA, hostB)` matches its test.
- **Proportion:** function bodies are left to the implementer; prose is spent only on rules the tests do not determine (order of the sit checks, claim timing, bot message routing, own-name discovery).
