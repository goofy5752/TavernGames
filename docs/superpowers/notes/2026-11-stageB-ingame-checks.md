# Stage B: in-game checks

Run these in the game client on Forever, one character unless stated, with `/console scriptErrors 1` on throughout.
Nothing here is marked passed on the strength of the unit tests: every row stays `not yet measured` until the result is written in by hand.
Rows 8-14 and 22-27 need a second account, rows 13 and 28 a third character. Row 12 is the known price of hidden hands: nobody can see an absent player's cards, so nothing is played for him.

Scope of this stage: the fair deal (commit, seed, private deal, reveal, audit) and Сантасе (`Games.PLAYABLE = {ttt, deathroll, santase}`); Belot, Табла and Holdem stay shown but not openable.
Card art: 40x58 px cards, fan step 28 px, raised 8 px, dimmed to 0.55; textures `card`, `card_back`, `suits` from `tools/gen_textures.py`.

| # | Check | What to look for | Result |
|---|---|---|---|
| 1 | `/tavern bots`, open Сантасе „Само поканени“, invite a bot | six cards face up for me, six backs for the bot, the trump half under the stock, within about a second; no hitch when the hand is dealt (pure-Lua SHA-256) | not yet measured |
| 2 | `/tavern debug` through one hand | my outgoing lines to the bot carry only the cards I play; `SED` goes only to the dealer, `PRV` comes only from it; a `PRV` line shows `cards="<N>"` and a `SED` line `s="<32>"`, never a face or a seed; no GUILD line has a card, a seed or a commit | not yet measured |
| 3 | finish a hand | under the felt „Последната ръка: проверена“; hovering explains it; clicking opens „Защо раздаването е честно“ | not yet measured |
| 4 | the three buttons | „Обяви 20/40“ only on my lead with king and queen in hand (armed: only those two raised); „Смени деветката“ only with the trump nine, a trick taken and more than two stock cards; „Затвори“ only on my lead with more than two stock cards | not yet measured |
| 5 | after closing, or with the stock empty | cards I may not play are dimmed and do nothing when clicked | not yet measured |
| 6 | let my turn run out | my lowest allowed card is played; I do not lose the hand by the clock | not yet measured |
| 7 | play to 11 | „… печели партията!“, one result, „Нова игра“ starts a match led by the loser; ⓘ opens „Сантасе“ with the card pictures | not yet measured |
| 8 | two characters: A opens, B sits | both get cards; neither trace shows the other's hand; both read „проверена“ after the hand; the dealer alternates (the line „… раздава…“ if it ever lingers) | not yet measured |
| 9 | B (not the dealer) `/reload`s mid-hand | B's cards are back within about two seconds; play goes on; B reads „не съм я гледал цялата“ for that hand, „проверена“ for the next | not yet measured |
| 10 | the dealer `/reload`s mid-hand | „Ръката е анулирана от <раздаващия>. Раздава следващият.“ on both; the OTHER player deals the hand again; no game point moved; the tooltip counts the dealer's annulled hands | not yet measured |
| 11 | B logs out during the shuffle (stand up from the keyboard right after sitting) | A reads „Чакаме B за разбъркването…“; when B is back within 3 minutes a hand is dealt within 20 s; otherwise B is stood up and the table reads „Играта е прекъсната.“ | not yet measured |
| 12 | B logs out on its own turn mid-hand | nothing is played for B (nobody can see its cards); B back: its clock plays or B plays; B away 3 minutes: stood up, A wins the match | not yet measured |
| 13 | a third character watches from the start, and another joins mid-hand | backs for both hands; its trace has no hidden card; „проверена“ for the first, „не съм я гледал цялата“ for the latecomer | not yet measured |
| 14 | the host stands mid-hand | Сантасе ends the match for the leaver (rule 16); the other player's frame names the winner | not yet measured |
| 15 | card art at UI scale 0.65 and 1.0 | ranks and suits readable, red and black distinct, the raised edge and the dimming visible on the felt | not yet measured |
| 16 | count the whispers of one deal with `/tavern debug` | about ten addon whispers per hand per player; no ChatThrottleLib delay visible | not yet measured |
| 17 | card texture and fan readability at 40x58, and the variant-1 look | rank and suit legible at 40x58 with the 28 px fan overlap (the visible strip of an overlapped card still shows rank and suit); the gilt inner line on the face and the medallion on the back are visible and not muddy | not yet measured |
| 18 | the Сантасе view layout against the mockup (`docs/mockups/03-games.html`, the Сантасе table; card and table look: `docs/mockups/07-wow-authentic.html`) | stock, trump half, trick area, score, the three buttons, both hands and the fairness line sit where the mockup puts them; nothing overlaps or clips at the default scale | not yet measured |
| 19 | the rules book topic list: long topic titles („Защо раздаването е честно“, „Сантасе“) | titles wrap or truncate cleanly, no text over the neighbouring row or the text pane, in bg and en | not yet measured |
| 20 | message volume per hand with two real clients | with `/tavern debug` on both: no ChatThrottleLib delay or drop, no disconnect, no missing `PRV`/`SED` over several hands in a row; count lines per hand (row 16) on both sides | not yet measured |
| 21 | SHA-256 cost felt in game | no frame hitch or stutter at the moment of the deal on either client, including the audit after the hand (every client re-hashes the commits); note the slower machine | not yet measured |
| 22 | the host `/reload`s mid-hand while the OTHER player deals | the table freezes for about 75 s (the silence before a takeover), then the other player hosts and the same hand goes on; the old host is back in its seat with its cards, reads „не съм я гледал цялата“ for that hand and „проверена“ for the next; note whether 75 s is bearable in a card game | not yet measured |
| 23 | the host `/reload`s mid-hand while it deals itself | after about 75 s the other player hosts; „Ръката е анулирана от <стария домакин>. Раздава следващият.“; the new host deals the hand again; no game point moved | not yet measured |
| 24 | `/tavern debug` on the DEALER's client through one deal (two accounts) | the dealer's outgoing `PRV` lines show `cards="<6>"` (later `"<1>"` per draw) and the incoming `SED` shows `s="<32>"`; no line on the dealer's side shows a card of the other player's hand or the other player's seed before the hand is over (the reveal after the hand does show the seeds) | not yet measured |
| 25 | the same dealer `/reload`s mid-hand twice in one match | the first time the line is grey and names him; the second time it reads „<име> анулира 2 ръце в тази игра. Раздава следващият.“ in red and stays red for the match; each void passes the deal to the other player; „Нова игра“ clears it | not yet measured |
| 26 | the dealer `/reload`s during the shuffle (right after the previous hand ends, before the cards appear) | „<име> раздава…“ lingers up to 20 s, then a hand is dealt by the same dealer; the other player and a watcher read „Последната ръка: нередовна“ with „раздаващият получи разбъркването, но не раздаде навреме“ in the tooltip and the dealer counted on its second line; note how often this happens by accident | not yet measured |
| 27 | a whole evening of honest play, two accounts, several matches, marriages, swaps and closes | never „нередовна“, never „<име>: ръката е нередовна“, and „не съм я гледал цялата“ only after a `/reload`, a relog or a visible disconnect of that client; write down every other occurrence with what happened just before | not yet measured |
| 28 | a third character sits down at a three-seat card table mid-shuffle (not possible in Сантасе; measure when Белот is playable) | the newcomer gets the running round without a resync note and is dealt in from the next hand | not yet measured |
