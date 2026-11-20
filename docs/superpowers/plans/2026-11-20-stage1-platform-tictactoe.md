# Tavern Games Stage 1 (Platform + Морски шах) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A WoW Forever addon in which guild members see a shared tavern hall, open/join/watch tables, invite each other and play Морски шах (match to 3 wins) in real time, with a rules book, first-run intro, bg/en strings, bot mode and debug trace.

**Architecture:** Game engines are pure Lua (`engines/`). All lobby/presence/session logic (`core/`) is written against an injected `env` (send, clock, timers, player status), so several simulated clients run in one Lua process over an in-memory bus and are unit-tested outside WoW. One thin adapter (`wow/`) binds `env` to AceComm/C_Timer/game events; `ui/` only renders core state and calls core methods. The same in-memory bus powers bot mode in game.

**Tech Stack:** Lua 5.1, WoW Forever client (`## Interface: 16001`), Ace3 subset (LibStub, CallbackHandler-1.0, AceAddon-3.0, AceComm-3.0 + ChatThrottleLib, AceSerializer-3.0, AceDB-3.0), LibDeflate, LibDataBroker-1.1, LibDBIcon-1.0, Python 3.14 + Pillow (texture generation), self-written Lua test runner.

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
| `db` | table | `{lang, introDone, busy, snoozeUntil, debug, minimap}` |
| `log(dir, channel, peer, msg)` | fn | trace hook, `dir` `"in"`/`"out"` |

**Messages** (`v=1` on all; `G` = GUILD, `W` = WHISPER; `→h` = to host):

| `t` | chan | fields | meaning |
|---|---|---|---|
| `HI` | G, W | `ver, cls, id, at, re` | presence; `id` GUID, `at` tid or nil, `re=true` asks peers to answer by whisper |
| `BYE` | G | | leaving |
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
| `SNP` | W | `tid, e, q, tbl, st, left` | snapshot: `tbl` = TBL record, `st` = `Engine.snapshot` |
| `PNG` | W→h | `tid` | member heartbeat |
| `TCK` | W | `tid, e, q` | host heartbeat |
| `HND` | W | `tid, e, to` | graceful handoff; followed by `SNP` at epoch `e` |

Frozen across protocol versions: the fields `v`, `t`, and `SNO.why="version"`. Table/system events (`seat=0`): `{k="sit",seat,name}`, `{k="stand",seat,why}` (`why` `"left"/"offline"`), `{k="start"}`, `{k="abort"}`, plus engine system actions.

**Test commands:** `bash t.sh` runs everything; `bash t.sh <file-or-dir>` runs a subset. Success ends with `N passed, 0 failed` and exit code 0. Test names below written with a `--[[ ... ]]` body state their assertions in words; the implementer writes them out as real assertions with exactly those values before implementing.

---

### Task 1: Tooling, test runner, TOC skeleton

**Files:**
- Create: `t.sh`, `.gitignore`, `TavernGames.toc`, `tests/run.lua`, `tests/helpers/loader.lua`, `tests/runner_test.lua`, `tests/toc_test.lua`, `tests/fixtures/failing.lua`

**Interfaces:**
- Produces (globals inside test files): `describe(name, fn)`, `it(name, fn)`, `eq(actual, expected, msg)` (deep equality), `ok(value, msg)`, `raises(fn, pattern)`, and `Loader`.
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
describe("x", function() it("fails", function() eq(1, 2) end) end)
```

- [ ] **Step 3: Run `bash t.sh tests/runner_test.lua`.** Expected: fails, `tests/run.lua` missing.
- [ ] **Step 4: Implement `tests/run.lua`, `tests/helpers/loader.lua`, `t.sh`.** `run.lua` takes file paths as arguments, adds `tests/helpers/?.lua` to `package.path`, prints `FAIL <describe> / <it>: <message>` per failure, a last line `N passed, M failed`, and calls `os.exit(M > 0 and 1 or 0)`.
- [ ] **Step 5: Verify.** `bash t.sh tests/runner_test.lua` → `2 passed, 0 failed`. `bash t.sh tests/fixtures/failing.lua; echo $?` → `0 passed, 1 failed` then `1`.
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
  it("legal lists 9 marks for the seat on turn and none for the other", function() end)
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
- `ns.Const`: `PROTOCOL=1`, `PREFIX="TAVG"`, `VERSION="0.1.0"`, `TURN_DEFAULT=45`, `TURN_CHOICES={30,45,60,90}`, `INVITE_SECONDS=30`, `SNOOZE_SECONDS=1800`, `OFFLINE_STAND_SECONDS=180`, `PING_EVERY=30`, `SILENT_AFTER=75`, `CLAIM_STAGGER=15`, `TBL_HEARTBEAT=60`, `TBL_EXPIRE=150`, `TBL_MIN_GAP=2`, `HI_HEARTBEAT=120`, `PEER_EXPIRE=300`, `LIST_MODE_ABOVE=8`, `MAX_WATCHERS=8`, `SYN_MIN_GAP=5`, `TRACE_LINES=200`.
- `ns.Util.copy(t) -> t` (deep), `ns.Util.same(a, b) -> bool` (deep), `ns.Util.money(copper) -> string` (`123456 → "12g 34s 56c"`, `500000 → "50g"`, `0 → "0c"`; zero parts omitted).
- `ns.Names.normalize(raw) -> string|nil` — trim; strip one trailing `-Realm` where Realm contains no space and no hyphen; nil for empty or non-string.
- `ns.Emitter.new() -> e`; `e:on(event, fn)`; `e:emit(event, ...)`.
- `ns.Bus.new() -> bus`; `bus:join(name, receive)` with `receive(channel, sender, msg)`; `bus:leave(name)`; `bus:send(from, channel, target, msg)` queues a deep copy (GUILD → every joined name except `from`; WHISPER → `target` only, dropped if not joined); `bus:flush()` delivers FIFO until the queue is empty; `bus.filter = fn(from, to, channel, msg) -> list of msgs` (default `{msg}`; tests use it to drop or duplicate).
- `ns.Trace.new(limit) -> tr`; `tr:add(dir, channel, peer, msg)`; `tr:lines() -> {string}`; `tr.print` (fn or nil, called with each new line).
- `ns.Client.new(env) -> client`; `client:start()` (GUILD `HI` with `re=true`, starts heartbeats); `client:stop()` (stands if seated, GUILD `BYE`, cancels every timer); `client:receive(channel, sender, msg)`; `client:on(event, fn)`; `client:peerOffline(name)`. `receive` drops non-table messages, messages without `v`/`t`, and messages from its own name; for `v ~= 1` it only records the peer as `incompatible` and, when `v > 1`, emits `"update"` once per client lifetime.
- `client.presence:list() -> { {name, cls, guid, at, incompatible}, ... }` sorted by name bytes; `client.presence:get(name)`. Emits `"peers"` on change. A `HI` with `re=true` is answered by a WHISPER `HI` (`re=false`). `HI` repeats on GUILD every 120 s; a peer silent for 300 s, or reported by `peerOffline`/`BYE`, is removed.
- `Sim.new() -> sim`; `sim:add(name, opts) -> client, env` (`opts`: `cls`, `status`, `group` = list of names, `db`; builds an `env` on a fake clock, joins the bus, calls `start`); `sim.makeEnv(name, cls) -> env`; `sim:run(seconds)` (advances the clock in 1 s steps, firing due timers, then flushing the bus); `sim:offline(name)` / `sim:online(name)` (the bus drops everything to and from the name); `sim:relog(name) -> client` (fresh Client with the same name); `sim.sent` = array of `{from, channel, target, msg}`; `sim:count(pred) -> n`.

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
it("trace keeps the last 200 lines", function() end)
it("newcomer learns everyone by whisper, not by a guild burst", function()
  local sim = Sim.new(); sim:add("Иван Петров", {cls="MAGE"}); sim:add("Мария Стоянова", {cls="PRIEST"}); sim:run(1)
  local n0 = sim:count(function(m) return m.channel == "GUILD" end)
  local c = sim:add("Kiro Barley", {cls="ROGUE"}); sim:run(1)
  eq(#c.presence:list(), 2); eq(c.presence:get("Иван Петров").cls, "MAGE")
  eq(sim:count(function(m) return m.channel == "GUILD" end) - n0, 1)
end)
it("drops a peer on BYE, on peerOffline and after 300 s of silence", function() end)
it("flags a newer protocol once and lists the peer as incompatible", function()
  local seen = 0; a:on("update", function() seen = seen + 1 end)
  a:receive("GUILD", "Нов Клиент", {v=2, t="HI"}); a:receive("GUILD", "Нов Клиент", {v=2, t="ZZZ"})
  eq(seen, 1); eq(a.presence:get("Нов Клиент").incompatible, true)
end)
it("ignores garbage: a string, a table without t, its own name", function() end)
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
it("ignores TBL whose sender is not its host field", function() --[[ c:receive("GUILD", C, {v=1,t="TBL",tid=tid,h=A,e=9,...}); epoch stays 1 ]] end)
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
  - Members: `q == seq + 1` → apply; `q <= seq` → ignore; `q > seq + 1` → discard and send `SYN` (at most one per 5 s). `EV`/`SNP`/`TCK` are accepted only from the current host and with `e >= epoch`. If an `EV` from the host fails `Engine.apply`, emit `"desync"` and send `SYN`.
  - `TCK` every 30 s carries `q`; a member behind it sends `SYN`. Members send `PNG` every 30 s.
  - Turn timer: after every event that leaves `state.turn` set, the host arms `turn` seconds; on expiry it emits `Engine.auto(state, seat)` as that seat's event with `auto=true`. `left` in the `EV` gives members the countdown.
  - When `Engine.system(state)` returns an action, the host emits it (seat 0) after the returned delay.
  - A seated player standing while `"live"` → `stand` then `abort` events, status `"aborted"`, record state `"open"`. No winner is recorded (stage 1 has no stakes).

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
it("rematch by both restarts 0:0 with the other seat first", function() end)
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
  - **Offline seat:** the host tracks `lastHeard` per seated player (any message from them). `peerOffline`/`BYE` does not shorten the wait. When `now − lastHeard ≥ 180` the host emits `stand` with `why="offline"` (then `abort` if live). Until then their turns are played by the turn timer. A watcher silent for 75 s is dropped.
  - **Reconnect:** when the host receives `HI` from a name seated at its table, it whispers `SNP`; a client receiving an `SNP` for a table where its own name holds a seat adopts the session.
  - **Graceful host leave** (`stand`/`stop` with another seated player): the host emits its own `stand` event, then whispers `HND{e=epoch+1, to=first candidate}` and an `SNP` at the new epoch to all members, then leaves. The successor becomes host, re-arms a full turn timer, announces `TBL`. For a 2-seat game this aborts the match (a seat emptied) but the table lives on under the new host.
  - **Host silence:** a member that hears nothing from the host for 75 s sets `hostSilent`. The candidate at rank `k` (0-based) claims after `75 + 15·k` s of silence: epoch + 1, whispers an `SNP` built from its own state to all members, announces `TBL`, re-arms a full turn timer. The old host keeps its seat and falls under the offline-seat rule (`lastHeard` = its last message).
  - **Convergence:** any table message with a higher epoch than mine makes me a member of that sender (a host demotes itself and sends `SYN`). The same epoch from two hosts → `Succession.wins`; the loser demotes and sends `SYN`. Messages with a lower epoch are ignored.
  - Watchers never become host. If no seated candidate is left, the table expires from the lobby after 150 s and watchers' sessions end.

- [ ] **Step 1: Write the failing tests.** `fake_engine.lua` registers `ns.Engines.fake` in tests only: 4 seats, action `{k="inc"}` increments `state.n`, turn rotates 1→2→3→4, `auto` returns `{k="inc"}`, never ends.

```lua
it("offline player's turns are auto-played, then he is stood up at 180 s", function()
  sim:offline(B); sim:run(179); eq(a.session.seats[2], B); sim:run(2)
  eq(a.session.seats[2], false); eq(a.session.status, "aborted")
end)
it("relog within 3 minutes restores seat, board and score", function()
  sim:offline(B); sim:run(60); local b2 = sim:relog(B); sim:run(2)
  eq(b2.session.mySeat, 2); eq(b2.session.state.board, a.session.state.board); eq(b2.session.state.score, a.session.state.score)
end)
it("host stands mid-turn: next player becomes host, timer restarts, no move lost or doubled", function()
  -- fake engine, a b c seated, d watches; three incs; a:stand(); sim:run(2)
  eq(b.session.role, "host"); eq(b.session.epoch, 2); eq(d.session.host, B); eq(d.lobby:get(tid).host, B)
  eq(c.session.state.n, 3); sim:run(46); eq(c.session.state.n, 4)   -- one auto move after a full fresh turn
end)
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
it("invitee in combat: no toast event, host hears ('auto','combat')", function() end)
it("unanswered invite times out at 30 s", function() --[[ host sees ("auto","timeout"); invitee sees inviteGone ]] end)
it("snooze lasts 30 minutes", function() --[[ second invite within 1800 s -> why "snooze", no "invite"; after sim:run(1801) a new invite shows ]] end)
it("stale yes after the chair was taken is refused 'taken'", function() end)
it("yes after the table closed is refused 'gone'", function() end)
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
  - Routing (over a private `Bus`): `enable` wraps `env.send` — a WHISPER to a bot goes only to the bus; GUILD goes to the real send **and** the bus; everything else is unchanged. Bot sends: WHISPER to `env.me` → `client:receive`; to another bot → bus; elsewhere → dropped. Bot GUILD → `client:receive` and the other bots only, **never the real guild channel**. Delivery happens through `env.after(0, flush)`.
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
  local tid = a:openTable{game="ttt", access="invite", turn=45}; a:invite("Бот Иванов"); sim:run(5)
  eq(a.session.seats[2], "Бот Иванов")
  -- loop up to 400 s: when it is seat 1's turn, a:act(E.auto(state, 1)); sim:run(1)
  eq(a.session.state.phase, "match")
  eq(sim:count(function(m) return m.channel == "GUILD" and m.from ~= A end), 0)
end)
it("a bot can host and invite me", function() --[[ bots:inviteMe(); sim:run(2); "invite" event whose host is a bot name ]] end)
it("hostTable spawns extra bots up to 12", function() --[[ nine calls -> #a.lobby:tables() == 9 after sim:run(3) ]] end)
it("disable restores env.send and removes the bots from presence", function() end)
it("bg and en have the same keys and the same number of % placeholders per key", function() end)
it("every help block and intro key exists in both languages; topics are hall, ttt, soon", function() end)
it("L formats and falls back to the key", function() eq(ns.L("no.such.key"), "no.such.key") end)
it("hall switches to list above 8 tables", function() eq(H.mode(8), "floor"); eq(H.mode(9), "list") end)
it("8 slots are distinct and inside the floor", function() --[[ slots(8, 560, 420): 8 unique points, 0 < x < 560, 0 < y < 420 ]] end)
it("seat 1 is at the top", function() --[[ chairs(2, 40): [1] == (0, 40), [2] == (0, -40), tolerance 1e-6 ]] end)
it("my table comes first, then open, then live", function() end)
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
it("round-trips Cyrillic names and nested tables", function()
  local m = {v=1, t="TBL", tid="Иван Петров#1763650000", s={"Иван Петров", false}, e=1}
  eq(wire:unpack(wire:pack(m)), m)
end)
it("snapshot above 255 bytes survives pack/unpack", function()
  -- snap = SNP with 2 seats and 8 extra names "Александър Константинопольски N" in tbl
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
- Produces (for `ui/`): `ns.addon` (AceAddon object), `ns.client` (nil until the own name is known), `ns.db` (AceDB over `TavernGamesDB`; `global`: `lang`, `introDone`, `busy`, `debug`, `minimap={hide=false}`; `char`: `snoozeUntil`), `ns.ready(fn)` (runs `fn(client)` once the client exists), `ns.classColor(cls) -> r, g, b`, `ns.bots` (nil or the bots object).
- Behaviour:
  - Comm: `RegisterComm("TAVG")`; accept only the distributions `GUILD` and `WHISPER`; sender through `Names.normalize`; `wire:unpack` returning nil → drop. Send through `SendCommMessage` (AceComm splits above 255 bytes), priority `ALERT` for `EV`/`ACT`/`SNP`, `NORMAL` otherwise.
  - `env.now = GetTime`, `env.epoch = GetServerTime`, `env.after` over `C_Timer.NewTimer`, `status` from `InCombatLockdown()`, `IsInInstance()`, `db.busy or UnitIsDND("player")`, `inGroup(guid)` over `IsGUIDInGroup`, `log` into a `Trace` whose `print` is set while `db.debug` is on.
  - **Own full name** (`UnitName` gives only the first name on Forever): request the guild roster and find the entry whose GUID equals `UnitGUID("player")`; if not found within 5 s, send `{v=1, t="WHO", id=<guid>}` on GUILD and take the sender of the echo whose `id` matches. Only then create the Client and call `start()`. Not in a guild → no Client; the UI shows `L("hall.noguild")`; bot mode still works with `UnitName("player")` as the name.
  - A guild member going offline (roster update or the "has gone offline" system line) → `client:peerOffline(name)`. `PLAYER_LOGOUT` → `client:stop()`.
  - Suppress the system "player not found" line for names the addon whispered in the last 5 s (chat message event filter; use whichever filter API the client provides).
  - `/tavern` toggles the main window; `/tavern bots` toggles three bots; `/tavern bots host`; `/tavern bots invite`; `/tavern debug` toggles `db.debug` (lines such as `TAVG > WHISPER Име Фамилия: EV q=7` in the default chat frame, visible only to the player); `/tavern intro`; `/tavern reset` (clears `lang` and `introDone`); `/tavern probe` prints: the resolved own name, `IsInInstance()`, whether `C_TradeInfo.SetTradeMoney`, `SetSendMailMoney` and `issecretvalue` exist, five `math.random(1, 1000000)` samples, and sends one packed 600-byte test whisper to itself, reporting `echo OK` or `echo LOST` after 5 s.

- [ ] **Step 1: Ask the user for the Forever `Interface\AddOns` path and their OK, then link the repo into it:** `cmd /c mklink /J "<AddOns>\TavernGames" D:\Programming\TavernGames`.
- [ ] **Step 2: Implement `wow/Adapter.lua` and `wow/Slash.lua`; add them to the TOC with their locale keys.** Run `bash t.sh` → all pass (compile gate, locale parity).
- [ ] **Step 3: In-game checks, one character.** With `/console scriptErrors 1`, `/reload` shows no error. `/tavern probe` prints the own name as two words without a realm and `echo OK`. `/tavern debug` then `/tavern bots`: the trace shows `HI` from three bots, and no outgoing GUILD line carries a bot's name.
- [ ] **Step 4: In-game checks, two guild characters with the addon.** With `/tavern debug` on both: each trace shows the other's `HI` under the full two-word name, and each receives the other's whispered `HI` reply. Enter a dungeon on one and run `/tavern probe` (does the echo arrive, does the other client still see its GUILD `HI`). Write the findings — name format, instance behaviour, `math.random` samples, trade/mail API presence — into the notes file (spec §10).
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
- **Gaps fixed during review:** added the bag-gold display (spec 5.2) to Task 11; added the GUID (`id`) to `HI` so „Групата ми“ is checked by GUID instead of unreliable unit names; added the `TBL` coalescing test for the anti-spam anti-goal; added the "player not found" whisper-error filter; added a 4-seat fake engine because tic-tac-toe has a single successor candidate and cannot exercise split brain; made `bots:hostTable()` spawn extra bots so list mode (9 tables) can be checked by one person; intro step 3 is „покани“ because payment does not exist in stage 1.
- **Type consistency:** the refusal event is `"refused"(tid, why)` everywhere; engine methods are `new/apply/legal/auto/system/snapshot/restore`; session fields are `role/mySeat/host/epoch/seq/seats/state/status/deadline/hostSilent`; `env.inGroup` takes a GUID in Tasks 3, 4, 10; `Succession.wins(seats, hostA, hostB)` matches its test.
- **Proportion:** function bodies are left to the implementer; prose is spent only on rules the tests do not determine (order of the sit checks, claim timing, bot message routing, own-name discovery).
