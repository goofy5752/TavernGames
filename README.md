<div align="center">

# Tavern Games: a World of Warcraft guild games addon

**Play Belot, Santase, Backgammon, Texas Hold'em, Tic-tac-toe and Death Roll with your guild inside WoW. Play just for fun or for gold, with a shared debt ledger and payment by trade or mail.**

[![WoW Forever](https://img.shields.io/badge/WoW-Forever%201.60.1-b0813f)](#installation)
[![Interface](https://img.shields.io/badge/Interface-16001-7a1f24)](TavernGames.toc)
[![Lua](https://img.shields.io/badge/Lua-5.1-2c2d72?logo=lua)](#development)
[![Tests](https://img.shields.io/badge/tests-2042%20passing-2e7d32)](#development)
[![Languages](https://img.shields.io/badge/UI-English%20%7C%20Български-e9c98a)](#languages)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[Features](#features) · [Games](#games) · [How it works](#how-it-works) · [Installation](#installation) · [Commands](#slash-commands) · [FAQ](#faq) · [На български](#на-български)

</div>

---

**Tavern Games** is a free, open-source **World of Warcraft addon** that turns your guild into a tavern. Guild members open tables, invite each other and play **real-time multiplayer card and board games** without leaving the game: **Bulgarian Belot**, **Santase (Sixty-six)**, **Backgammon (Tabla)**, **Texas Hold'em poker**, **Tic-tac-toe** and the classic **WoW Death Roll**.

Every table is either **just for fun** or **staked in gold and silver**. The addon never moves gold by itself. It keeps a **guild-wide debt ledger**, fills in the amount for a **trade** or a **mail**, and you press the button. The addon runs on GUILD and WHISPER addon messages only, so it needs no server, website or external service.

> **Status: alpha.** All six games, stakes, the ledger, the leaderboard and the history are built and covered by 2042 automated tests. In-game testing on WoW Forever is in progress. Please [open an issue](../../issues) if something misbehaves.

## Table of contents

- [Features](#features)
- [Games](#games)
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
- [Contributing](#contributing)
- [License and credits](#license-and-credits)
- [На български](#на-български)

## Features

- 🃏 **Six multiplayer games**: Belot, Santase, Backgammon, Texas Hold'em, Tic-tac-toe and Death Roll, all with full rules played turn by turn in real time.
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
- 🎨 **A hand-made tavern look**: a walnut frame, burgundy felt, brass, cream-coloured cards with Alegreya SC headings and clear PT Sans text. It does not look like the default WoW UI templates.
- ↘️ **Resizable windows**: drag the corner of the main window or a game table to make it as large or as small as you like. Everything inside, from text to cards to boards, scales with it, and the size is remembered. Right-click the corner for the normal size.

## Games

| Game | Players | Type | Notes |
|---|---|---|---|
| **Belot** (Белот) | 4, two teams | Trick-taking card game | Bulgarian rules: bidding, all-trumps / no-trumps, declarations, belote, valat, hanging points, game to 151 |
| **Santase** (Сантасе, Sixty-six) | 2 | Trick-taking card game | 24-card deck, closing, marriages (20 / 40), trump nine exchange, match to 11 game points |
| **Backgammon** (Табла) | 2 | Board game with dice | Bulgarian Tabla; the dice are rolled by commit-reveal between both players, so neither can choose them |
| **Texas Hold'em** | 2–6 | Poker | Chip tables for fun, plus cash tables with real gold buy-ins |
| **Tic-tac-toe** (Морски шах) | 2 | Board game | First to 3 wins, quick games between raids |
| **Death Roll** | 2–5, in a group | Dice | The classic `/roll` duel: each roll sets the new maximum, and whoever rolls 1 loses |

## How it works

### Fair dealing and anti-cheat

Card games need hidden information, so a deck that every client can compute is not an option. Tavern Games uses a **dealer client that every other client checks**:

1. **Every player helps shuffle.** Before each hand every player commits to a secret, and the deck order comes from all of them together (commit-reveal with SHA-256). No single client can arrange the deck.
2. **Hidden cards stay hidden.** The dealer's client sends each player only their own cards, by whisper.
3. **The dealer rotates every hand**, and the whole deck is revealed and checked after the hand.
4. **Every client runs the rules.** An illegal move, a forged deal or a changed record is caught by the other clients, and the hand is disputed, not paid.

Games with no hidden information (Backgammon, Tic-tac-toe, Death Roll) are checked fully by every client. Death Roll uses the server's own `/roll`, which everyone in the group sees, and Backgammon dice are rolled by commit-reveal between both players.

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

1. Download the latest release zip, or clone this repository.
2. Copy these folders and files into
   `World of Warcraft\_forever_\Interface\AddOns\TavernGames\`:
   `Libs`, `core`, `engines`, `locale`, `wow`, `ui`, `media`, `TavernGames.toc`, `LICENSE-THIRD-PARTY.md`
3. Restart the game, or type `/reload`, and make sure **Tavern Games** is enabled in the AddOns list.

> The folder must be named exactly `TavernGames`. The `docs`, `tests` and `tools` folders are for development and are not needed in game.

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

There are no AI opponents. A tester-only bot mode exists for development.
</details>

## Known limitations

- **The dealer sees its own deck.** In Belot, Santase and Hold'em the dealer's client knows the deck of the hand it deals. This cannot be detected, so it is reduced by dealer rotation and shown as a warning.
- **Hold'em key contest.** A host who holds back the key of one live Hold'em hand is not always disputed automatically. Sometimes the affected player is asked to decide.
- **A dealer who goes silent at showdown** voids that Hold'em hand, and the all-in is returned.
- **Ledger entry delay.** A new record can take up to 24 hours to reach every client, or until its holder logs in again.
- Addon messages may not work inside dungeons and raids.

## Development

The addon is written in **Lua 5.1** and has a headless test suite of **2042 tests** that runs outside the game with stubbed WoW APIs.

```bash
# needs Lua 5.1 or LuaJIT on PATH (or tools/lua/lua5.1.exe)
bash t.sh                    # all tests
bash t.sh tests/engines      # one folder
bash t.sh tests/core/ledger_final_test.lua
```

The design spec, the per-stage implementation plans, the rulings log and the in-game check lists are in [`docs/superpowers`](docs/superpowers). The visual mockups are in [`docs/mockups`](docs/mockups).

## Project structure

```text
TavernGames/
├── TavernGames.toc   # addon manifest (load order)
├── core/             # protocol, sessions, fairness, stakes, ledger, sync, payments
├── engines/          # pure game rules: belot, santase, tabla, holdem, tictactoe, deathroll
├── ui/               # windows, hall, table views, ledger, leaderboard, history
├── wow/              # the WoW API adapter: trade, mail, rolls, slash commands
├── locale/           # English and Bulgarian strings
├── media/            # textures and fonts
├── Libs/             # vendored Ace3, LibDeflate, LibDataBroker, LibDBIcon
├── tests/            # the headless Lua test suite
└── docs/             # design spec, plans, notes, mockups
```

## Contributing

Bug reports, rule corrections (especially for regional Belot and Santase variants) and translations are welcome. Please open an issue first for larger changes. Run `bash t.sh` before sending a pull request.

## License and credits

- Tavern Games is released under the [MIT License](LICENSE).
- The bundled libraries (Ace3, LibDeflate, LibDataBroker-1.1, LibDBIcon-1.0) and the Alegreya SC and PT Sans fonts keep their own licenses; see [LICENSE-THIRD-PARTY.md](LICENSE-THIRD-PARTY.md).
- World of Warcraft® is a trademark of Blizzard Entertainment, Inc. This project is not affiliated with or endorsed by Blizzard Entertainment.

---

## На български

**Tavern Games** е безплатен аддон за **World of Warcraft (WoW Forever)**, с който гилдията играе заедно направо в играта: **Белот**, **Сантасе**, **Табла**, **Тексас Холдем покер**, **Морски шах** и **Death Roll**.

- **Залог по желание:** всяка маса е „Само за удоволствие“ или „Със залог“ в голд и силвер.
- **Общ тефтер на дълговете:** всички в гилдията виждат кой на кого дължи. Дълг се записва само след потвърждение от клиента на длъжника.
- **Плащане с трейд или поща:** аддонът попълва сумата, а бутона натискаш ти. Аддонът никога не мести голд сам.
- **Честно раздаване:** всички участват в разбъркването на тестето (commit-reveal), раздаващият се сменя всяка ръка и всеки клиент проверява всеки ход.
- **Холдем със злато:** вход от 40 до 100 големи блайнда, докупуване и сметка между всеки двама играчи.
- **Класация и история:** седмица, месец и всичко, титлата „Кралят/Кралицата на механата“, хронология на игрите и сравнение между двама играчи.
- **Разтегаеми прозорци:** хващаш ъгъла на прозореца или на масата и го правиш колкото искаш голям. Всичко вътре се уголемява заедно с него.
- **Интерфейс на български и английски**, книга с правилата и въведение при първо пускане.

**Инсталиране:** копирай папките `Libs`, `core`, `engines`, `locale`, `wow`, `ui`, `media` и файла `TavernGames.toc` в `World of Warcraft\_forever_\Interface\AddOns\TavernGames\`. После напиши `/tavern` в играта.

<sub>Keywords: WoW addon, World of Warcraft addon, guild games, Belot addon, Santase addon, Backgammon addon, Tabla, Texas Hold'em poker addon, WoW poker, Death Roll addon, gold betting, guild bank, debt ledger, Lua addon, WoW Forever, аддон за WoW, Белот, Сантасе, Табла, покер.</sub>
