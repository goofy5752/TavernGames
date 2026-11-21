# Stage C: in-game checks (Белот)

Run these in the game client on Forever with `/console scriptErrors 1` on throughout.
Nothing here is marked passed on the strength of the unit tests: every row stays `not yet measured` until the result is written in by hand.
Rows 1-10 need one character (solo with bots). Rows 11-17, 20-26 and 27-30 need four characters at one table (rows 24-25 can be looked at solo with bots); rows 15, 17 and 23 add a fifth as a watcher. Row 12 (контра/реконтра) cannot be seen solo: bots never double.

Scope of this stage: Белот (`Games.PLAYABLE = {ttt, deathroll, santase, belot}`) on the stage B fair deal with four seeds; Табла and Holdem stay shown but not openable.
Felt 532 x 328 px; cards 40x58 px, fan step 28 px, raised 8 px, dimmed to 0.55.

| # | Check | What to look for | Result |
|---|---|---|---|
| 1 | `/tavern bots`, open Белот „Само поканени“, invite the three bots | four plates around the felt, my own at the bottom, the bot opposite me is my partner; five cards face up within about two seconds; „разд.“ on the plate of the seat before the first bidder | not yet measured |
| 2 | `/tavern bots host belot`, sit down | two more bots sit within a few seconds and the deal starts | not yet measured |
| 3 | my turn in the auction | only the legal bids have buttons; after a bot's bid the weaker suits are gone; „Контра“ appears only over an opponent's game | not yet measured |
| 4 | let the auction clock run out | my client says „Пас“; with everybody passing the cards are dealt again by the next seat | not yet measured |
| 5 | win the auction | three more cards arrive; the game and who called it stand top left; the score top right | not yet measured |
| 6 | trick 1 with a терца or better in hand | the „Обяви: …“ button; after the click a bubble at my plate; a bot's announce is a bubble at its plate; bubbles are gone after the second trick | not yet measured |
| 7 | play the king or queen of trumps holding both | a „Белот“ bubble without pressing anything | not yet measured |
| 8 | a trick where I must follow or trump | the cards I may not play are dimmed and do nothing; the four cards of the trick lie towards their players; „Последна взятка“ shows the previous four | not yet measured |
| 9 | the end of a deal | the summary: game, both sides' points, „Вътре сме!“ / „Вътре са!“ when it happens, every announce with its points or „(не се брои)“; under the felt „Последната ръка: проверена“ | not yet measured |
| 10 | play to 151 (about 13 deals) | „Печелим партията!“ or „Те печелят партията.“, one result, „Нова игра“ starts a match with the deal one seat further; ⓘ opens „Белот“ with the card pictures | not yet measured |
| 11 | four characters at one table | everyone gets cards; no trace shows another player's hand; „… раздава…“ names the seat marked „разд.“; all four read „проверена“ | not yet measured |
| 12 | контра and реконтра between real players | the buttons appear for the right team only; the summary shows the doubled points for the side with more | not yet measured |
| 13 | a player who is not the dealer `/reload`s mid-deal | the cards are back within about two seconds; the trick and the score are right; the deal reads „не съм я гледал цялата“ for that player only and is scored without the „resynced“ banner | not yet measured |
| 14 | the dealer `/reload`s mid-trick (the seat marked „разд.“, after it played a card) | no void: within a few seconds everybody still holds the same cards, the trick and the score stand, play goes on; at the end the other three read „Последната ръка: проверена“, the dealer „не съм я гледал цялата“; nothing about the deck in `/tavern debug` | not yet measured |
| 15 | a player logs out on its turn | nothing is played or bid for it; back within three minutes: play goes on; after three minutes it is stood up, „… стана от масата. Отборът му губи.“, the banner „Играта е прекъсната.“; a new player on the free chair starts a new match | not yet measured |
| 16 | a player presses „Стани“ mid-deal | the same ending at once; the result names the two winners | not yet measured |
| 17 | a watcher from the start, and one who comes mid-deal | backs only, no buttons, „Долу и горе … · Ляво и дясно …“; its trace has no card that was not played | not yet measured |
| 18 | count the whispers of one deal with `/tavern debug` (four players, no watcher) | the host sends about 140 addon whispers per deal (about 46 events to three members), each other player about 12; during the shuffle about 20 leave the host within a second: no visible ChatThrottleLib delay, no deal that hangs at „Разбъркваме заедно…“ | not yet measured |
| 19 | the table at UI scale 0.65 and 1.0 | nothing overlaps on the 532 × 328 felt: the side plates and the bid buttons, the bubbles and the trick, my fan and my plate, the fairness line | not yet measured |
| 20 | four real players play a full match, with контра and реконтра and every announce kind (терца, кварта, квинта, каре, каре деветки, каре валета, белот) | every announce shows as a bubble at its player's plate by kind only (never the height of a sequence) and is scored in the summary; the doubled points are right; both sides' totals agree on all four clients at 151; all four read „проверена“ for every deal | not yet measured |
| 21 | one player alt-tabs or disconnects mid-deal and stays away three minutes | nothing is bid or played for him; after three minutes he is stood up and his team loses (no points moved, no money); the other three see „Играта е прекъсната.“; alt-tab alone (client still connected) does not stand him up | not yet measured |
| 22 | the dealer loses its saved round mid-deal, four real players (kill the game client from the task manager so nothing is saved, then log in again) | „Ръката е анулирана от <name>. Раздава следващият.“ on all four, no point moves, the next seat deals (PB6b); the same dealer doing it again in the match turns the line red with the count | not yet measured |
| 23 | a watcher joins mid-deal on a four-player table | backs only, no buttons, no hidden card in its trace; it reads „не съм я гледал цялата“ for that deal and „проверена“ for the next | not yet measured |
| 24 | four-plate ring and bubble readability | the four plates (165 wide at the bottom, right, top, left positions) read clearly with class-coloured names; a bubble stays legible over a plate and does not hide the trick or a neighbouring plate; „разд.“ and the turn mark are visible | not yet measured |
| 25 | ♣/♠ bid icons | the black suit icons on the bid buttons (woodDark) are legible against the button, distinct from ♦/♥ in red | not yet measured |
| 26 | message volume per deal (about 140 whispers from the host), with ChatThrottleLib | over several deals in a row: no disconnect, no delayed or lost whisper, no deal that stalls; note the peak whispers per second seen in `/tavern debug` | not yet measured |
| 27 | the dealer `/reload`s twice in one deal, once in the auction and once in trick 7 with a contract going wrong for its team | both times the same deal goes on; it is scored as played; no „анулирана“ line | not yet measured |
| 28 | a false announce (needs a client patched to send `ACT {k="ann"}` for cards it does not hold, e.g. a каре валета on one card) | the bubble shows during the first trick; in the summary that announce reads „(не се брои)“ with 0 points and the other team's announces still score; under the felt in red „Последната ръка: нередовна. <name> обяви карти, които не държи.“ on every client; the tooltip says the announce does not count | not yet measured |
| 29 | „Стани“ in a running Белот match | a small panel above the button: „Отборът ви губи мача, ако станеш сега. Партньорът ти губи заедно с теб.“ with „Стани“ and „Остани“; „Остани“ closes it and nothing changes; „Стани“ there ends the match as in row 16; a watcher's „Към залата“, an open table and a finished match ask nothing | not yet measured |
| 30 | a player's clock runs out while it is in a loading screen or lagging (cards not there yet, or the move lost) | once it is back its automatic move is made within about five seconds; the table does not hang at its turn | not yet measured |
