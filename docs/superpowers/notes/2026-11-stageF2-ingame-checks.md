# Stage F2: in-game checks

Run these in the game client on Forever with `/console scriptErrors 1` on throughout.
Nothing here is marked passed on the strength of the unit tests: every row stays `not yet measured` until the result is written in by hand.
Rows 1, 5–9, 13 and 25 need two characters; rows 2–4, 14, 20, 23 and 26 need four (row 2 a fifth); rows 10–12 and 24 need a second account or a second machine, so that one side's connection can be cut.

Scope of this stage: stakes for Сантасе, Белот and Табла (who owes whom, the leave, the next match, the hand and dice verdicts that feed the confirmation), and F1's residuals 24–27 (a far own id is asked, the sliced sort, the mail guard).
Rows 2–5 and 29–32 of the F1 list (`docs/superpowers/notes/2026-11-stageF1-ingame-checks.md`) should be measured before this list: they decide how trade and mail behave on Forever.
Rows 11 and 12 come first: they measure the price of D2 and D3 on a real connection. If an honest evening produces contested debts (rows 11, 12, 20, 22), `DICE_WAIT` at a staked table is the number to revisit, and `STAKE_FAIR_WAIT` for the cards.
Before the three games are announced, the user confirms residual S1 (the dealer's client knows the deck of the hand it deals; Addendum 9 of `docs/superpowers/notes/engine-contract.md`).

| # | Check | What to look for | Result |
|---|---|---|---|
| 1 | two characters, staked Сантасе, a whole match | both see the same bill within about 20 s of the last card (the reveal); the loser's row turns from „чака потвърждение“ to plain without a question | not yet measured |
| 2 | four characters, staked Белот, a whole match | two rows in the bill, the same on all four; a fifth character sees two debts in „Тефтер“ | not yet measured |
| 3 | staked Белот, one player presses „Стани“ mid-deal | the warning names both opponents and the total; the bill names the leaver and two rows; the partner sees no bill and owes nothing | not yet measured |
| 4 | staked Белот, one player alt-F4s for more than three minutes | stood up; two debts „чака потвърждение“; at its login one question per debt | not yet measured |
| 5 | the acceptance question for Сантасе, Белот, Табла at the default and a low UI scale | nothing clipped; the card warning reads naturally; the question grows with its text (Task 9 review I2): the Белот text of four lines plus the card warning ends above „Отказ“ / „Приемам и сядам“ | not yet measured |
| 6 | the bill at the end of a staked match of each of the three games | what it covers: the last trick, the Белот summary, the Табла bar and dice; whether the end line under it is missed; a reason line that wraps onto two rows (Task 9 concern 3: real `GetStringWidth`); the „Стани“ panel, which now grows with its text, also on a fun table (`table.standWarn`) | not yet measured |
| 7 | staked Сантасе, the dealer `/reload`s mid-hand | the hand goes on; at the end the dealer is asked about its debt, the other is not | not yet measured |
| 8 | staked Сантасе, the dealer alt-F4s mid-hand and logs in again | „Ръката е анулирана от …“; at the end the other player, if it lost, gets a question | not yet measured |
| 9 | staked Табла, a whole match | no question, the debt confirmed; the dice line stays green | not yet measured |
| 10 | staked Табла, the guest enters and leaves a loading screen (a hearthstone, an instance portal) during a throw | the dice line is amber; at the end the guest is asked, not contested | not yet measured |
| 11 | staked Табла, the guest's connection is cut for 15 s at a throw (pull the cable) | the host throws alone; the guest's row reads „оспорен“ if it loses; how often this happens on a normal evening | not yet measured |
| 12 | staked Табла, the host `/reload`s right after the guest's dice animation starts | the guest hosts after about 75 s; if the guest loses, „оспорен“ | not yet measured |
| 13 | the host presses „Нова игра“ at once after a staked match | the button is dim, says why, and lights up after 30 s; the guests' bill counts down | not yet measured |
| 14 | after a leave at a staked Белот table a fifth player sits within 10 s | „Новата игра започва след N сек.“; the match starts by itself at 30 s | not yet measured |
| 15 | a staked Табла turn left untouched | the host plays the timeout 7 s after the clock; the idle player's row is not „оспорен“ | not yet measured |
| 16 | a letter sent with the game's „Send“ after changing the amount by hand | the row says the amount actually sent; `/console taintLog 1` names no blocked action; a COD letter sets no guard; that `SendMailSendMoneyButton` and `MoneyInputFrame_GetCopper(SendMailMoney)` exist on Forever (the click reads the money box first; Task 8 review M2), and which order the client runs (a money confirmation first, or the money set in the button's own script) | not yet measured |
| 17 | a letter left in the box for more than a day | „Плати“ stays off; the tooltip says 30 days | not yet measured |
| 18 | log in with a ledger of one author with thousands of entries (F1 row 31 again) | no hitch above a frame or two at login and when a game ends (`LEDGER_HASH_ITEMS` is now 150: the first build takes about a second) | not yet measured |
| 19 | the rules book in both languages: „Залози“ | the four new blocks fit; the example reads right; the page scrolls to its last block | not yet measured |
| 20 | over a normal evening of staked card games, count the no-deals, voids and contested matches | S9–S11: how often an honest dealer's disconnect, a fourth player's silence in a Белот shuffle, or a loser's trip to the hall before the last reveal costs a contest or a question | not yet measured |
| 21 | (F1 row 32, still open) a staked Белот debt naming a guild member who is offline, with "show offline" off in the guild roster | the debt is taken by a fifth character's ledger (`env.member`); if it is not, F1's residual 23 applies to card debts too | not yet measured |
| 22 | staked Сантасе, the guest's connection is cut for 60–90 s mid-match (residual S12) | whether the guest comes back as host and the host's moves meanwhile are rolled back; at the end the honest host is asked, never charged automatically | not yet measured |
| 23 | staked Белот, the **host** presses „Стани“ mid-deal (final review I1) | another player takes the table over; both opponents' rows turn plain within a few seconds, without a question to the leaver, also when the leaver logs off right after; the partner sees no bill | not yet measured |
| 24 | staked Сантасе, the guest's connection is cut for 10–20 s over the last card of a match (pull the cable), and the host presses „Нова игра“ as soon as its button lights up (final review C2) | the guest catches up by a snapshot and its bill counts 30 s from then; the match the host starts before that is a question for the guest if it loses it („Потвърждавам“ / „Оспорвам“), never „оспорен“ and never confirmed by itself | not yet measured |
| 25 | staked Сантасе, the guest sits on a loading screen (a hearthstone, an instance portal) for more than 7 s over the last card, and the host presses „Нова игра“ at 30 s (final review M2, re-accepted) | whether the guest's row of the next match reads „оспорен“ when it loses it (its break began when the screen closed); how often on a normal evening | not yet measured |
| 26 | staked Белот, the dealer alt-F4s mid-hand and logs in again, and its team loses the match (final review C1) | „Ръката е анулирана от …“; the dealer's partner gets a question about its debt instead of a silent confirmation; how often an evening | not yet measured |
