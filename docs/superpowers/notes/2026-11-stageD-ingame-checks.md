# Stage D: in-game checks (Табла)

Run these in the game client on Forever with `/console scriptErrors 1` on throughout.
Nothing here is marked passed on the strength of the unit tests: every row stays `not yet measured` until the result is written in by hand.
Rows 1-9, 19, 20 and 25 need one character (solo with bots; bots play the first legal move, a weak opponent, enough to see every rule; row 26 and 27 can be looked at solo too, but a Гюлбара remainder is best seen with two players). Rows 10-14, 16-18, 21-24, 26 and 27 need two characters in different zones and not in a group; rows 15 and 18 add a third as a watcher.

Scope of this stage: Табла (`Games.PLAYABLE = {ttt, deathroll, santase, belot, tabla}`), an open game (no `E.view`), dice by commit-reveal between the two players (no `/roll`), the staged move with „Върни“/„Готово“. Холдем stays shown but not openable.
Board 404 x 232 px in a 512 x 260 view frame; points 28 x 96, checkers 26 x 26 (stacked 17 apart, five drawn at most), table frame 560 x 420.

| # | Check | What to look for | Result |
|---|---|---|---|
| 1 | `/tavern bots`, open Табла „Само поканени“, invite a bot | the board with my home bottom right; „Хвърляме по един зар за първи ход…“, then who starts; the plates read „бели · 0“ and „черни · 0“; under the felt „Зарове: хвърлени от двамата играчи“ in green | not yet measured |
| 2 | my move | my movable checkers carry a faint ring; a click lights the legal points in yellow; a click on a lit point moves the checker; the used die fades; „Остават: N“ counts down | not yet measured |
| 3 | „Върни“ and „Готово“ | „Върни“ takes back one step at a time; „Готово“ is dull until the whole move is staged; the bot sees nothing before „Готово“ | not yet measured |
| 4 | a double | four steps; „Остават: 4“ at the start | not yet measured |
| 5 | a roll with no legal move | „Нямаш ход. Натисни „Готово“.“; „Готово“ is lit at once | not yet measured |
| 6 | let the clock run out with half a move staged | the first legal move is played for me; my staged steps are gone; no loss | not yet measured |
| 7 | play Обикновена to bearing off | a hit checker lies on the bar and must enter first; in the home board a click on a checker lights the tray; the tray counts | not yet measured |
| 8 | the second game, Тапа | 15 on one point with the number „15“; a pinned checker lies under its pinner and cannot be picked; a mother pin ends the game with „Затисната майка!“ | not yet measured |
| 9 | the third game, Гюлбара, a double after the third throw | „Гюлбара: играеш чифт N“, each number its own „Готово“; a remainder the bot cannot play comes to me as „Доиграваш …“; play to 5 points: one result, „Нова игра“ starts with the opening throw; ⓘ opens „Табла“ with the dice pictures | not yet measured |
| 10 | two characters in different zones, no group | the table fills; every throw lands in under about a second; no `/roll` line in chat; both read the same dice | not yet measured |
| 11 | `/tavern debug` on both during one throw | the lines `open`, `commit`, the guest's `seed` and `seeds`, in that order; no line with dice values; the host's seed appears only in `seeds` | not yet measured |
| 12 | the guest `/reload`s while a throw is running | at most ten seconds later the dice are there; „… хвърли сам: … не се включи навреме“ in amber; the next throw is green again; no script error | not yet measured |
| 13 | the guest `/reload`s on its own move | the board, the dice and the clock are back within about two seconds; it can still stage and send its move | not yet measured |
| 14 | the host logs out mid-game | after about 75 s the guest hosts the table, a new throw is made, play goes on; back within three minutes the old host continues as guest; after three minutes it is stood up and loses | not yet measured |
| 15 | a watcher from the start, and one who comes mid-game | the same board and dice as the players, seat 1's side, no buttons, no rings | not yet measured |
| 16 | the guest enters a loading screen (hearthstone) on the host's throw | the host throws alone after ten seconds; play is not held up; the guest returns to the right board | not yet measured |
| 17 | a player presses „Стани“ mid-game | „… стана от масата.“; the other wins the match; the banner „Играта е прекъсната.“ | not yet measured |
| 18 | count the whispers of one turn with `/tavern debug` (two players and a watcher) | the host sends about 8 addon whispers a turn (four events to two members), the guest 3; no visible ChatThrottleLib delay over a whole game | not yet measured |
| 19 | the table at UI scale 0.65 and 1.0 | 26 px checkers and 28 px points are clickable; the numbers on a stack are readable; the right column, the dice line and the plates do not overlap | not yet measured |
| 20 | a long double in Тапа or Гюлбара with many checkers out | no hitch when a checker is clicked (`E.stage` on a double: watch the frame rate) | not yet measured |
| 21 | two characters in different zones (no group) play a full match through all three variants: Обикновена, Тапа, Гюлбара, to 5 points, then „Нова игра“ | no `/roll` line anywhere; both boards agree after every move; the dice line stays green; the game index and the variant name agree on both sides; the second match starts again with Обикновена and the opening throw | not yet measured |
| 22 | the guest `/reload`s mid-throw, after its seed went out and before the seeds event | its seed is kept (`env.db.fairKeep`): the throw closes green, not „unseen“; no second throw is opened for it. If the keep is lost (kill the client instead of reloading) the line may read „unseen“, never red | not yet measured |
| 23 | the host `/reload`s mid-throw, once after the guest's seed arrived and once before | the host has no kept seed: within 75 s the guest hosts and opens a new number (accepted F9: one re-roll per hosting); before the guest's seed arrived nothing is lost; no script error; the old host comes back as guest on the right board | not yet measured |
| 24 | a 10 s silence: the guest sends nothing for one throw (a loading screen) | after 10 s the host throws alone; the line is amber „… хвърли сам: … не се включи навреме“; the dice are the same on both boards after the guest returns; a hidden alone throw (the guest never saw it) is free once per match, a second one makes the line red | not yet measured |
| 25 | 26 px checker legibility: a stack of five and of more than five | the dark rim of a checker stays visible on the felt (field `#2a140b`); a dark checker on a dark point and a light one on a light point can still be told apart; the number on the fifth is readable | not yet measured |
| 26 | the staged move with „Върни“ and „Готово“, including the case where the move is done but can continue (5-1 where 4/0 already ends where 4/3 3/0 ends) | „Готово“ lights as soon as the staged steps are a whole legal move even when more steps may follow; the lit points still show the possible continuation; „Върни“ takes back one step at a time; „Готово“ pressed early ends the turn with what is staged; the opponent sees nothing before „Готово“ | not yet measured |
| 27 | a Гюлбара cascade with a remainder passed to the opponent (a double from a seat's fourth throw on, one number that cannot be played in full) | each cascade number is its own „Готово“ with a full clock; the unplayed steps of that number and of the higher numbers go to the other player as „Доиграваш …“ (a turn of its own, full clock); what the opponent cannot play is lost; then the opponent rolls for its own turn | not yet measured |

Accepted risks with no row (see Addendum 6 of `engine-contract.md`): F8 (a modified host can move for the guest in an open game), F9 (a host reload after it has seen the guest's number re-rolls one throw), the post-/reload alone proof (a just-logged-in client takes a valid alone proof as it is), and a hidden alone throw free once per match (unheard, red from the second).
