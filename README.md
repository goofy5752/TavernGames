<div align="center">

# Tavern Games: a World of Warcraft guild games addon

**Play Belot, Santase, Backgammon, Texas Hold'em, Chess, Tic-tac-toe and Death Roll with your guild inside WoW. Play just for fun or for gold, with a shared debt ledger and payment by trade or mail.**

[![WoW Forever](https://img.shields.io/badge/WoW-Forever%201.60.1-b0813f)](#installation)
[![Interface](https://img.shields.io/badge/Interface-16001-7a1f24)](TavernGames.toc)
[![Lua](https://img.shields.io/badge/Lua-5.1-2c2d72?logo=lua)](#development)
[![Tests](https://github.com/goofy5752/TavernGames/actions/workflows/tests.yml/badge.svg)](https://github.com/goofy5752/TavernGames/actions/workflows/tests.yml)
[![Languages](https://img.shields.io/badge/UI-English%20%7C%20Български-e9c98a)](#languages)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-join%20the%20tavern-5865F2?logo=discord&logoColor=white)](https://discord.gg/uuZg5TRmZz)
[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/goofy5752)

[Features](#features) · [Games](#games) · [Screenshots](#screenshots) · [How it works](#how-it-works) · [Installation](#installation) · [Commands](#slash-commands) · [FAQ](#faq) · [Community](#community-and-support) · [На български](#на-български)

<img src="docs/screenshots/hall.png" alt="The tavern hall: seven tables of different games, some with bots playing, the guild sign, the debts owed to you and who is in the tavern now" width="900">

</div>

---

**Tavern Games** is a free, open-source **World of Warcraft addon** that turns your guild into a tavern. Guild members open tables, invite each other and play **real-time multiplayer card and board games** without leaving the game: **Bulgarian Belot**, **Santase (Sixty-six)**, **Backgammon (Tabla)**, **Texas Hold'em poker**, **Chess**, **Tic-tac-toe** and the classic **WoW Death Roll**.

Every table is either **just for fun** or **staked in gold and silver**. The addon never moves gold by itself. It keeps a **guild-wide debt ledger**, fills in the amount for a **trade** or a **mail**, and you press the button. The addon runs on GUILD and WHISPER addon messages only, so it needs no server, website or external service.

> **Version 1.0.3** ([changelog](CHANGELOG.md)), the first public release with a few additions. All seven games, stakes, the ledger, the leaderboard and the history are built, tested in game on WoW Forever and covered by more than 2500 automated tests. Please [open an issue](../../issues) or tell us on [Discord](https://discord.gg/uuZg5TRmZz) if something misbehaves.

## Table of contents

- [Features](#features)
- [Games](#games)
- [Screenshots](#screenshots)
- [How it works](#how-it-works)
  - [Fair dealing and anti-cheat](#fair-dealing-and-anti-cheat)
  - [Gold stakes, the ledger and payments](#gold-stakes-the-ledger-and-payments)
  - [Texas Hold'em cash tables](#texas-holdem-cash-tables)
  - [Leaderboard and history](#leaderboard-and-history)
- [Installation](#installation)
- [Getting started](#getting-started)
- [Slash commands](#slash-commands)
- [Languages](#languages)
- [FAQ](#faq)
- [Known limitations](#known-limitations)
- [Development](#development)
- [Project structure](#project-structure)
- [Community and support](#community-and-support)
- [Contributing](#contributing)
- [License and credits](#license-and-credits)
- [На български](#на-български)

## Features

- 🃏 **Seven multiplayer games**: Belot, Santase, Backgammon, Texas Hold'em, Chess, Tic-tac-toe and Death Roll, all with full rules played turn by turn in real time.
- 🍺 **The tavern hall**: see every open table in your guild, who sits where and who is watching. Invite guildmates, sit down, stand up, or spectate.
- 🪙 **Optional gold stakes**: each table is *Just for fun* or *With a stake*, in gold and silver, with no house and no rake.
- 📒 **A shared debt ledger**: everyone in the guild sees the same record of who owes whom. A debt counts only after the debtor's own client confirms it.
- 💸 **Pay by trade or mail**: the addon opens the trade or fills in the mail with the right amount, and you click to send. Several debts to the same person are merged into one payment.
- ♠️ **Texas Hold'em cash games**: buy in for 40–100 big blinds, choose a rebuy mode, cash out when you like. Each pair of players is settled directly.
- 🛡️ **Fair dealing**: commit-reveal deck shuffling with input from every player, a rotating dealer, hidden cards sent only to their owner, and every client checking every move.
- 🏆 **Leaderboard**: week, month and all-time rankings per game, winning and losing streaks, and the title *King/Queen of the tavern*.
- 📜 **History**: a timeline of games and payments, and a head-to-head view of any two players.
- 🔄 **Survives disconnects**: reconnect snapshots, automatic stand-up when a player goes offline, and a new host is chosen when the host leaves.
- 🌍 **English and Bulgarian** interface, an in-game rules book and a first-run intro.
- 🎨 **Your faction's tavern**: an *Alliance* look (lapis and gold) or a *Horde* look (blood and iron), with its own frames, felt, crests and sounds. The cards come in faction and race decks, with the faction's leaders as kings.
- 🤖 **Practice bots**: add bots to a table *for fun* with one click to learn a game or try it alone. Bots never join a table with a stake.
- 🗂️ **Hand history**: look back at every trick of Santase and every Hold'em hand while you play. Belot shows only the last trick, since remembering the cards is part of the game. Hold'em shows your current hand as it changes (*Pair of Kings*, *Full House*), and all-in hands are turned face up before the board runs out.
- ↘️ **Resizable windows**: drag the corner or the frame of the main window or a game table. Everything inside, from text to cards to boards, scales with it, and the size is remembered. Right-click the corner for the normal size.

## Games

| Game | Players | Type | Notes |
|---|---|---|---|
| **Belot** (Белот) | 4, two teams | Trick-taking card game | Bulgarian rules: bidding, all-trumps / no-trumps, declarations, belote, valat, hanging points, game to 151 |
| **Santase** (Сантасе, Sixty-six) | 2 | Trick-taking card game | 24-card deck, closing, marriages (20 / 40), trump nine exchange, match to 11 game points |
| **Backgammon** (Табла) | 2 | Board game with dice | Bulgarian Tabla; the dice are rolled by commit-reveal between both players, so neither can choose them |
| **Texas Hold'em** | 2–6 | Poker | Chip tables for fun, plus cash tables with real gold buy-ins |
| **Chess** (Шах) | 2 | Board game | FIDE move rules with automatic draws (castling, en passant, promotion, mate, stalemate, threefold repetition, 50 moves), a clock of 5 to 30 minutes with +5 s a move, offering a draw and resigning, a practice bot in the tester bot mode, and staked games where a draw owes nothing |
| **Tic-tac-toe** (Морски шах) | 2 | Board game | First to 3 wins, quick games between raids |
| **Death Roll** | 2–5, in a group | Dice | The classic `/roll` duel: each roll sets the new maximum, and whoever rolls 1 loses |

## Screenshots

In these shots practice bots fill the seats, and the leaderboard and the ledger show made-up guild members. The addon dresses itself in your faction's colours: click a look to open it.

<details open>
<summary><b>🦁 Alliance look</b>: lapis and gold</summary>

<table>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/hall.png" alt="The tavern hall: tables of different games, the guild sign, the debts owed to you and who is in the tavern (Alliance look)"><br><sub>The hall</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/belot.png" alt="Belot mid-hand: four players, a trick on the table, the face cards with the race leaders (Alliance look)"><br><sub>Belot</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/santase.png" alt="Santase: the trump card under the stock, the last trick and the player's hand (Alliance look)"><br><sub>Santase</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/tabla.png" alt="Backgammon mid-game with the dice thrown by both players (Alliance look)"><br><sub>Backgammon</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/holdem.png" alt="Texas Hold'em with the board out, the live hand label and the hand history beside the table (Alliance look)"><br><sub>Texas Hold'em and the hand history</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/chess.png" alt="Chess mid-game with the move list and both clocks (Alliance look)"><br><sub>Chess</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/deathroll.png" alt="Death Roll: the ladder of rolls, each one setting the new maximum (Alliance look)"><br><sub>Death Roll</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/ttt.png" alt="Tic-tac-toe: a finished winning line (Alliance look)"><br><sub>Tic-tac-toe</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/leaderboard.png" alt="The leaderboard: games, wins, gold net, favourite game and streaks (Alliance look)"><br><sub>Leaderboard</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/ledger.png" alt="The guild ledger: open and settled debts (Alliance look)"><br><sub>Ledger</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/settings.png" alt="Settings: language, the Alliance or Horde look, the decks of the races with their leaders, and the links (Alliance look)"><br><sub>Settings and decks</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/book.png" alt="The rules book open on Belot (Alliance look)"><br><sub>Rules book</sub></td>
</tr>
</table>

</details>

<details>
<summary><b>🐺 Horde look</b>: blood and iron</summary>

<table>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/hall_horde.png" alt="The tavern hall: tables of different games, the guild sign, the debts owed to you and who is in the tavern (Horde look)"><br><sub>The hall</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/belot_horde.png" alt="Belot mid-hand: four players, a trick on the table, the face cards with the race leaders (Horde look)"><br><sub>Belot</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/santase_horde.png" alt="Santase: the trump card under the stock, the last trick and the player's hand (Horde look)"><br><sub>Santase</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/tabla_horde.png" alt="Backgammon mid-game with the dice thrown by both players (Horde look)"><br><sub>Backgammon</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/holdem_horde.png" alt="Texas Hold'em with the board out, the live hand label and the hand history beside the table (Horde look)"><br><sub>Texas Hold'em and the hand history</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/chess_horde.png" alt="Chess mid-game with the move list and both clocks (Horde look)"><br><sub>Chess</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/deathroll_horde.png" alt="Death Roll: the ladder of rolls, each one setting the new maximum (Horde look)"><br><sub>Death Roll</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/ttt_horde.png" alt="Tic-tac-toe: a finished winning line (Horde look)"><br><sub>Tic-tac-toe</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/leaderboard_horde.png" alt="The leaderboard: games, wins, gold net, favourite game and streaks (Horde look)"><br><sub>Leaderboard</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/ledger_horde.png" alt="The guild ledger: open and settled debts (Horde look)"><br><sub>Ledger</sub></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/screenshots/settings_horde.png" alt="Settings: language, the Alliance or Horde look, the decks of the races with their leaders, and the links (Horde look)"><br><sub>Settings and decks</sub></td>
<td width="50%" align="center"><img src="docs/screenshots/book_horde.png" alt="The rules book open on Belot (Horde look)"><br><sub>Rules book</sub></td>
</tr>
</table>

</details>

## How it works

### Fair dealing and anti-cheat

Card games need hidden information, so a deck that every client can compute is not an option. Tavern Games uses a **dealer client that every other client checks**:

1. **Every player helps shuffle.** Before each hand every player commits to a secret, and the deck order comes from all of them together (commit-reveal with SHA-256). No single client can arrange the deck.
2. **Hidden cards stay hidden.** The dealer's client sends each player only their own cards, by whisper.
3. **The dealer rotates every hand**, and the whole deck is revealed and checked after the hand.
4. **Every client runs the rules.** An illegal move, a forged deal or a changed record is caught by the other clients, and the hand is disputed, not paid.

Games with no hidden information (Backgammon, Tic-tac-toe, Death Roll, Chess) are checked fully by every client. Death Roll uses the server's own `/roll`, which everyone in the group sees, and Backgammon dice are rolled by commit-reveal between both players.

### Gold stakes, the ledger and payments

- A stake is agreed when the table is created, and every player sees it before sitting down.
- When a staked game ends, the result becomes a **debt in the guild ledger**. It counts only after the **debtor's own client** confirms it. A client confirms by itself only a game it saw completely and cleanly. If it detected cheating it disputes the debt, and if it missed part of the game it asks the player.
- The ledger is **synced between guild members** with compact, hashed pages, so everyone converges on the same record.
- Paying: click **Pay**, and the addon starts a **trade** with the amount filled in, or fills in a **mail** with the money attached. You make the final click, as Blizzard's rules require. The addon then spots the payment and marks the debt as paid.
- The addon never sends gold without your click, never accepts a trade for you and never posts anything in public chat.

### Texas Hold'em cash tables

- **Buy-in** of 40–100 big blinds in real gold, and the blinds are fixed when the table is created.
- **Rebuy modes** for players who go broke or run short.
- **Pairwise settlement**: when you leave, the addon works out what you owe each other player, and what they owe you, from the hands themselves. No money passes through a host.
- *Table account* and *Stand up now* buttons, plus a late table key, so a player who joins mid-session can still check the earlier hands.

### Leaderboard and history

- **Leaderboard**: rankings for the past week, the past month and all time, for all games or for one game. It shows games, wins, win %, gold net, favourite game and streaks, and crowns the **King or Queen of the tavern**.
- **Trust rule**: results backed by a confirmed debt rank above fun results. A result nobody else confirmed is shown as *according to …*.
- **History**: a timeline of games and payments, and a head-to-head view of any two guildmates.
- **Retention**: old results shrink to small hashed stubs, so the ledger stays light without breaking its sync.

## Installation

Tavern Games is built for **WoW Forever** (the `_forever_` client, game version 1.60.1, `## Interface: 16001`).

**From a release (recommended).** Download the `TavernGames-<version>.zip` of the [latest release](../../releases/latest) and unpack it into
`World of Warcraft\_forever_\Interface\AddOns\`, so that you get `AddOns\TavernGames\TavernGames.toc`. Then restart the game
and make sure **Tavern Games** is enabled in the AddOns list.

**From the source.**
1. Download the repository (**Code → Download ZIP**) and unpack it, or clone it.
2. Copy these folders and files into
   `World of Warcraft\_forever_\Interface\AddOns\TavernGames\`:
   `Libs`, `core`, `engines`, `locale`, `wow`, `ui`, `media`, `TavernGames.toc`, `LICENSE-THIRD-PARTY.md`
3. Restart the game and make sure **Tavern Games** is enabled in the AddOns list.

> The folder must be named exactly `TavernGames` (GitHub's zip unpacks as `TavernGames-master`, so rename it). The `docs`, `tests` and `tools` folders are for development and are not needed in game. After an update that adds new sound files, restart the game; `/reload` does not load new files.

## Getting started

1. Type **`/tavern`**, or click the minimap icon, to open the tavern.
2. In the **Hall**, create a new table: pick a game and choose *Just for fun* or *With a stake*.
3. Invite guildmates. They get an invite toast and can sit down or watch.
4. After a staked game, open the **Ledger** to see debts and click **Pay** to settle by trade or mail.
5. Check the **Leaderboard** and **History** tabs to see who rules the tavern.

All players need the addon, and they need to be in the same guild. Play in the open world or in cities, because addon messages may be blocked inside instances.

## Slash commands

| Command | What it does |
|---|---|
| `/tavern` | Opens or closes the Tavern Games window |
| `/tavern intro` | Replays the first-run intro |
| `/tavern ledger` | Prints a local summary of the ledger: authors, records, stubs and the digest |
| `/tavern probe` | Checks your client: name resolution and addon messaging |
| `/tavern probe roll` | Checks that server `/roll` messages are read correctly |
| `/tavern probe trade` | Checks trade detection; open a trade window first |
| `/tavern probe mail` | Checks mail detection; open the mailbox first |
| `/tavern probe art` | Lists which game icons and portraits your client has |
| `/tavern bots fill` | Fills the empty seats of your fun table with bots (the same as **Add bots**) |
| `/tavern bots clear` | Stands your bots up from your table |
| `/tavern bots close` | Closes the tables where only bots sit |
| `/tavern bots host <game>` | A bot opens a fun table of that game for you to join |
| `/tavern debug` | Turns debug logging on or off |
| `/tavern reset` | Resets the language choice and the intro |

## Languages

The whole interface, the rules book and the intro are available in **English** and **Bulgarian (Български)**. The language can be changed in **Settings**.

## FAQ

<details>
<summary><b>Is gambling with gold allowed by Blizzard?</b></summary>

Tavern Games follows the Blizzard UI Add-On Policy. It is free, its code is not obfuscated, it does not spam, it never automates a trade or a mail, and it never advertises anything in public chat. Stakes stay inside your guild and every payment is a manual click. The guild and its players are responsible for how they play.
</details>

<details>
<summary><b>Can a modified client see my cards or cheat?</b></summary>

Every player helps shuffle, so no one can arrange the deck. Every client checks every move, and the full deck is checked after each hand. Hidden cards are whispered only to their owner. One limit remains: the dealer's own client knows the deck of the hand it deals. The dealer rotates every hand, and the addon warns about this before you sit at a staked card table. See [Known limitations](#known-limitations).
</details>

<details>
<summary><b>What if someone disconnects in the middle of a game?</b></summary>

A player who goes offline is stood up automatically after a grace period, and a host who leaves is replaced. Reconnecting clients get a snapshot of the game. A staked hand that cannot be checked completely is voided, not paid.
</details>

<details>
<summary><b>Does it need a website, a server or a Discord bot?</b></summary>

No. Everything runs inside the game over GUILD and WHISPER addon messages, and it is saved in your SavedVariables.
</details>

<details>
<summary><b>Does it work on Retail, Classic or other clients?</b></summary>

It currently targets WoW Forever (Interface 16001). Other clients may need a different TOC interface number and API checks. Contributions are welcome.
</details>

<details>
<summary><b>Can I play against bots?</b></summary>

Yes, for practice. At a table *for fun*, click **Add bots** and bots fill the empty seats; **Remove bots** stands them up again. Bots never join a table with a stake, and only you see them: they live in your own client, so they are not real opponents for gold. They play simply, which is enough to learn a game.
</details>

## Known limitations

- **The dealer sees its own deck.** In Belot, Santase and Hold'em the dealer's client knows the deck of the hand it deals. This cannot be detected, so it is reduced by dealer rotation and shown as a warning.
- **Hold'em key contest.** A host who holds back the key of one live Hold'em hand is not always disputed automatically. Sometimes the affected player is asked to decide.
- **A dealer who goes silent at showdown** voids that Hold'em hand, and the all-in is returned.
- **Ledger entry delay.** A new record can take up to 24 hours to reach every client, or until its holder logs in again.
- Addon messages may not work inside dungeons and raids.

## Development

The addon is written in **Lua 5.1** and has a headless test suite of **more than 2400 tests** that runs outside the game with stubbed WoW APIs.

```bash
# needs Lua 5.1 or LuaJIT on PATH (or tools/lua/lua5.1.exe)
bash t.sh                    # all tests
bash t.sh tests/engines      # one folder
bash t.sh tests/core/ledger_final_test.lua
```

Every pull request runs the suite in [GitHub Actions](https://github.com/goofy5752/TavernGames/actions/workflows/tests.yml).

[`tools/sim`](tools/sim) holds large simulations that play thousands of games of each game through the real engines and check every result against a reference written from the official rules, plus whole multi-client tables with disconnects. For example, `luajit tools/sim/belot_soak.lua 2000 1` or `luajit tools/sim/e2e_soak.lua 300 21`. The latest audit is in [`docs/audit`](docs/audit).

The design spec, the per-stage implementation plans, the rulings log and the in-game check lists are in [`docs/superpowers`](docs/superpowers). The visual mockups are in [`docs/mockups`](docs/mockups).

## Project structure

```text
TavernGames/
├── TavernGames.toc   # addon manifest (load order)
├── core/             # protocol, sessions, fairness, stakes, ledger, sync, payments
├── engines/          # pure game rules: belot, santase, tabla, holdem, chess, tictactoe, deathroll
├── ui/               # windows, hall, table views, ledger, leaderboard, history
├── wow/              # the WoW API adapter: trade, mail, rolls, slash commands
├── locale/           # English and Bulgarian strings
├── media/            # textures and fonts
├── Libs/             # vendored Ace3, LibDeflate, LibDataBroker, LibDBIcon
├── tests/            # the headless Lua test suite
├── tools/            # texture generators and the game simulations (tools/sim)
└── docs/             # design spec, plans, notes, mockups
```

## Community and support

- **Discord:** join the [Tavern Games server](https://discord.gg/uuZg5TRmZz) to find players, ask for help, report bugs, suggest ideas and hear about new versions first.
- **GitHub:** bugs and rule corrections are also welcome as [issues](../../issues).
- **Support the project:** Tavern Games is free and always will be. If it made your guild nights more fun, you can [buy me a coffee](https://buymeacoffee.com/goofy5752). ☕

## Contributing

Bug reports, rule corrections (especially for regional Belot and Santase variants) and translations are welcome. Please open an issue first for larger changes. Run `bash t.sh` before sending a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md), and report security problems privately ([SECURITY.md](SECURITY.md)).

## License and credits

- Tavern Games is released under the [MIT License](LICENSE).
- The bundled libraries (Ace3, LibDeflate, LibDataBroker-1.1, LibDBIcon-1.0), the Alegreya SC and PT Sans fonts, and the game icons from [game-icons.net](https://game-icons.net) (CC BY 3.0, by Lorc, Delapouite, Aussiesim and Skoll) keep their own licenses; see [LICENSE-THIRD-PARTY.md](LICENSE-THIRD-PARTY.md).
- World of Warcraft® is a trademark of Blizzard Entertainment, Inc. This project is not affiliated with or endorsed by Blizzard Entertainment.

---

## На български

**Tavern Games** е безплатен аддон за **World of Warcraft (WoW Forever)**, с който гилдията играе заедно направо в играта: **Белот**, **Сантасе**, **Табла**, **Тексас Холдем покер**, **Шах**, **Морски шах** и **Death Roll**.

- **Залог по желание:** всяка маса е „Само за удоволствие“ или „Със залог“ в голд и силвер.
- **Общ тефтер на дълговете:** всички в гилдията виждат кой на кого дължи. Дълг се записва само след потвърждение от клиента на длъжника.
- **Плащане с трейд или поща:** аддонът попълва сумата, а бутона натискаш ти. Аддонът никога не мести голд сам.
- **Честно раздаване:** всички участват в разбъркването на тестето (commit-reveal), раздаващият се сменя всяка ръка и всеки клиент проверява всеки ход.
- **Шах:** FIDE правила за ходовете с автоматично реми (рокада, мимоходно вземане, превръщане на пешка), часовник от 5 до 30 минути, реми по съгласие, предаване, тренировъчен бот в тестовия режим с ботове и игра със залог, при която реми не дължи нищо.
- **Холдем със злато:** вход от 40 до 100 големи блайнда, докупуване и сметка между всеки двама играчи.
- **Класация и история:** седмица, месец и всичко, титлата „Кралят/Кралицата на механата“, хронология на игрите и сравнение между двама играчи.
- **Механата на твоята фракция:** облик на Алианса (лапис и злато) или на Ордата (кръв и желязо), с тестета на градовете и расите.
- **Ботове за тренировка:** бутон „Добави ботове“ на маса за удоволствие. На маса със залог ботове не сядат.
- **История на ръцете:** всяка взятка в Сантасе и всяка ръка в Холдема. Белот показва само последната взятка, защото помненето на картите е част от играта. В Холдема виждаш какво имаш в момента, а при all-in картите се обръщат преди борда.
- **Разтегаеми прозорци:** хващаш ъгъла на прозореца или на масата и го правиш колкото искаш голям. Всичко вътре се уголемява заедно с него.
- **Интерфейс на български и английски**, книга с правилата и въведение при първо пускане.

Как изглежда: виж [снимките](#screenshots) по-горе.

**Инсталиране:** копирай папките `Libs`, `core`, `engines`, `locale`, `wow`, `ui`, `media` и файловете `TavernGames.toc` и `LICENSE-THIRD-PARTY.md` в `World of Warcraft\_forever_\Interface\AddOns\TavernGames\`. После напиши `/tavern` в играта.

**Общност:** [Discord сървърът](https://discord.gg/uuZg5TRmZz) е мястото за търсене на съиграчи, въпроси, бъгове и идеи. Ако искаш да подкрепиш проекта, можеш да ми [купиш кафе](https://buymeacoffee.com/goofy5752). ☕

<sub>Keywords: WoW addon, World of Warcraft addon, guild games, Belot addon, Santase addon, Backgammon addon, Tabla, Texas Hold'em poker addon, WoW poker, Chess addon, WoW chess, Death Roll addon, gold betting, guild bank, debt ledger, Lua addon, WoW Forever, аддон за WoW, Белот, Сантасе, Табла, покер, Шах.</sub>
