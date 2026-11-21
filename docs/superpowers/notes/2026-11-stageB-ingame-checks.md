# Stage B: in-game checks

Run these in the game client on Forever, one character unless stated, with `/console scriptErrors 1` on throughout.
Nothing here is marked passed on the strength of the unit tests: every row stays `not yet measured` until the result is written in by hand.
Rows 8-14 need a second account, row 13 a third character. Row 12 is the known price of hidden hands: nobody can see an absent player's cards, so nothing is played for him.

Scope of this stage: the fair deal (commit, seed, private deal, reveal, audit) and Сантасе (`Games.PLAYABLE = {ttt, deathroll, santase}`); Belot, Табла and Holdem stay shown but not openable.
Card art: 40x58 px cards, fan step 28 px, raised 8 px, dimmed to 0.55; textures `card`, `card_back`, `suits` from `tools/gen_textures.py`.

| # | Check | What to look for | Result |
|---|---|---|---|
| 1 | `/tavern bots`, open Сантасе „Само поканени“, invite a bot | six cards face up for me, six backs for the bot, the trump half under the stock, within about a second; no hitch when the hand is dealt (pure-Lua SHA-256) | not yet measured |
| 2 | `/tavern debug` through one hand | my outgoing lines to the bot carry only the cards I play; `SED` goes only to the dealer, `PRV` comes only from it; no GUILD line has a card, a seed or a commit | not yet measured |
| 3 | finish a hand | under the felt „Последната ръка: проверена“; hovering explains it; clicking opens „Защо раздаването е честно“ | not yet measured |
| 4 | the three buttons | „Обяви 20/40“ only on my lead with king and queen in hand (armed: only those two raised); „Смени деветката“ only with the trump nine, a trick taken and more than two stock cards; „Затвори“ only on my lead with more than two stock cards | not yet measured |
| 5 | after closing, or with the stock empty | cards I may not play are dimmed and do nothing when clicked | not yet measured |
| 6 | let my turn run out | my lowest allowed card is played; I do not lose the hand by the clock | not yet measured |
| 7 | play to 11 | „… печели партията!“, one result, „Нова игра“ starts a match led by the loser; ⓘ opens „Сантасе“ with the card pictures | not yet measured |
| 8 | two characters: A opens, B sits | both get cards; neither trace shows the other's hand; both read „проверена“ after the hand; the dealer alternates (the line „… раздава…“ if it ever lingers) | not yet measured |
| 9 | B (not the dealer) `/reload`s mid-hand | B's cards are back within about two seconds; play goes on; B reads „не съм я гледал цялата“ for that hand, „проверена“ for the next | not yet measured |
| 10 | the dealer `/reload`s mid-hand | „Ръката е анулирана. Раздава се отново.“ on both; the same player deals; no game point moved | not yet measured |
| 11 | B logs out during the shuffle (stand up from the keyboard right after sitting) | A reads „Чакаме B за разбъркването…“; when B is back within 3 minutes a hand is dealt within 20 s; otherwise B is stood up and the table reads „Играта е прекъсната.“ | not yet measured |
| 12 | B logs out on its own turn mid-hand | nothing is played for B (nobody can see its cards); B back: its clock plays or B plays; B away 3 minutes: stood up, A wins the match | not yet measured |
| 13 | a third character watches from the start, and another joins mid-hand | backs for both hands; its trace has no hidden card; „проверена“ for the first, „не съм я гледал цялата“ for the latecomer | not yet measured |
| 14 | the host stands mid-hand | Сантасе ends the match for the leaver (rule 16); the other player's frame names the winner | not yet measured |
| 15 | card art at UI scale 0.65 and 1.0 | ranks and suits readable, red and black distinct, the raised edge and the dimming visible on the felt | not yet measured |
| 16 | count the whispers of one deal with `/tavern debug` | about ten addon whispers per hand per player; no ChatThrottleLib delay visible | not yet measured |
| 17 | card texture and fan readability at 40x58, and the variant-1 look | rank and suit legible at 40x58 with the 28 px fan overlap (the visible strip of an overlapped card still shows rank and suit); the gilt inner line on the face and the medallion on the back are visible and not muddy | not yet measured |
| 18 | the Сантасе view layout against the mockup (the WoW-style card/table mockup variants in `docs/`) | stock, trump half, trick area, score, the three buttons, both hands and the fairness line sit where the mockup puts them; nothing overlaps or clips at the default scale | not yet measured |
| 19 | the rules book topic list: long topic titles („Защо раздаването е честно“, „Сантасе“) | titles wrap or truncate cleanly, no text over the neighbouring row or the text pane, in bg and en | not yet measured |
| 20 | message volume per hand with two real clients | with `/tavern debug` on both: no ChatThrottleLib delay or drop, no disconnect, no missing `PRV`/`SED` over several hands in a row; count lines per hand (row 16) on both sides | not yet measured |
| 21 | SHA-256 cost felt in game | no frame hitch or stutter at the moment of the deal on either client, including the audit after the hand (every client re-hashes the commits); note the slower machine | not yet measured |
