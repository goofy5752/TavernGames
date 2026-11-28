# Changelog

## 1.0.4 (2026-11-28)

- **Stakes:** right after login the game sometimes doesn't know your guild's name yet. Tavern Games then started without the guild ledger, and every staked chair said "The table's stake is a different one". The ledger now opens as soon as the guild's name is known, with no `/reload`. If it still isn't loaded, the message says that instead.

## 1.0.3 (2026-11-26)

- **Belot:** the table no longer has a hand history. Remembering what has been played is part of the game, so only „Last trick“ is left, as before. Santase, Hold'em and Chess keep their history.

## 1.0.2 (2026-11-26)

- **Settings:** the Discord server's address now sits under the source code's, in the same box you can copy from.
- **Settings, Deck:** point at a deck and its whole face side opens beside it: the jack, queen, king and ace of every suit, and the back.
- **Decks:** every king now has his own face, never the jack's. Gnomes get an old gnome with a white moustache, trolls a red-mohawked troll, and the blood elves' king is now Kael'thas (the client has no Lor'themar portrait).

## 1.0.1 (2026-11-25)

- **Sounds for every game.** Belot and Santase have the deal, my turn, a card played, a trick taken, the declarations, closing the stock and the nine swap. Backgammon has the dice, a checker moved, hit and borne off. Chess has a move, a capture, check, castling, promotion and the low-time tick. Tic-tac-toe marks its X, its O and the winning line, and Death Roll its rolls and the 1. A win, loss or draw jingle plays at the end of every game.
- **„New table“:** the game is a drop-down. Pick another game without closing the dialog; who may sit and the turn time stay as chosen. The stake boxes end in the gold and silver coin icons.
- **Santase:** „Declare“, the nine swap and „Close“ now stand beside your hand, no longer over the last trick.

## 1.0.0 (2026-11-25)

This is the first public release, for WoW Forever (game version 1.60.1).

### Games
- **Belot** for four players in two teams: Bulgarian rules with bidding, all-trumps and no-trumps, declarations, belote, valat, hanging points and a game to 151.
- **Santase (Sixty-six)**: closing the stock, marriages (20 / 40), swapping the trump nine, and a match to 11.
- **Backgammon (Tabla)**: the dice are rolled by commit-reveal, so neither player can pick them.
- **Texas Hold'em** for 2–6 players:
  - chip tables for fun, and cash tables with gold buy-ins;
  - poker-room sounds for every action, my turn and the last ten seconds.
- **Chess**: FIDE move rules, automatic draws, a clock with an increment, draw offers and resigning.
- **Tic-tac-toe** and the classic **Death Roll**.

### The tavern
- **Hall:** every open table in the guild, with chairs to sit at and spectating.
- **Games list:** each game has an ⓘ that opens its rules.
- **Stakes:** a table can be for fun or for gold. Debts go in a guild-wide ledger and are paid by trade or mail with one click.
- **Fair dealing:** every player helps shuffle the deck (commit-reveal), and every client checks every move.
- **Leaderboard and history:** rankings, streaks, the timeline and head-to-head.
- **Hand history at the table:**
  - Belot and Santase tricks as rows of mini cards;
  - Hold'em streets;
  - chess moves as piece icons with "from → to".
- **Names:** short names everywhere space is tight, with the full name on hover; bots are marked with a cog.
- **Look:** an Alliance and a Horde look, with faction and race decks.
- **Windows:**
  - every window can be resized and stays readable at any size;
  - nothing is ever cut off;
  - windows stay on the screen and move from the first pixel.
- **Languages:** English and Bulgarian, with an in-game rules book and a first-run intro.
