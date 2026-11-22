# Stage F1: in-game checks

Run these in the game client on Forever with `/console scriptErrors 1` on throughout.
Nothing here is marked passed on the strength of the unit tests: every row stays `not yet measured` until the result is written in by hand.
Rows 2-3 need a second character; row 4 needs a letter with money from a guild character; rows 5-6 need a second account.

Scope of this stage: the gold ledger, its sync, and payments by trade and mail; stakes for Морски шах and Death Roll.
The probes only read and print: they never press Trade or Send, and the addon never calls `AcceptTrade`, `SendMail`, `TakeInboxMoney`, `AutoLootMailItem` or a COD function.
Later tasks of the stage append their rows below.

| # | Check | What to look for | Result |
|---|---|---|---|
| 1 | `/tavern probe` | which of `SetTradeMoney` / `C_TradeInfo.SetTradeMoney`, `GetPlayerTradeMoney` / `C_TradeInfo.GetTradeMoney`, `GetInboxHeaderInfo` / `C_Mail.GetInboxHeaderInfo`, `MoneyInputFrame_SetCopper`, `GetSendMailPrice`, `hooksecurefunc` are `function`; `GetGuildInfo` | not yet measured |
| 2 | `/tavern probe trade`, then trade 1s to a second character | the order of the events; whether `UI_INFO_MESSAGE` carries `ERR_TRADE_COMPLETE`; whether both money values are still readable at `TRADE_ACCEPT_UPDATE(1,1)` and at `TRADE_CLOSED`; the form of `UnitName("NPC")` (first name, full name, realm) and whether `UnitGUID("NPC")` is a roster GUID | not yet measured |
| 3 | the same, cancelled by the other side | which event tells a cancel from a completion | not yet measured |
| 4 | `/tavern probe mail` at a mailbox with a letter with money from a guild character | the sender's form in the inbox row; the price line; whether a money value is a plain number (`issecretvalue`) | not yet measured |
| 5 | send 1s by mail between two accounts | the delivery delay (one hour between accounts?); the fee actually taken | not yet measured |
| 6 | several small trades and letters in a row | does an economy hold appear; its message text | not yet measured |
| 7 | two characters, one with 30 entries more: `/tavern debug` on both | one `LVC`, `LEV` batches two seconds apart, no error, no disconnect; `/tavern` stays usable meanwhile | not yet measured |
| 8 | the same while playing Холдем on the sending client | the table does not stall (the `LEV` batches come six seconds apart) | not yet measured |
| 9 | staked Death Roll, three characters in one party | every roll shows without „?“, also a `/roll <max>` typed by hand (the `RandomRoll` hook sees it: no red „!“ on my own line); a player outside the party cannot be started with („Започни“ says why) | not yet measured |
| 10 | a third guild character with the first name of a seated player types `/roll <max>` on that player's turn | what the table does, and that the seated player's line turns red | not yet measured |
| 11 | leave a staked Death Roll turn untouched for three minutes | stood up, the bill names the idle player | not yet measured |
| 11a | staked Death Roll in one party: `/run print(UnitInParty("Име-Realm"), UnitInRaid("Име-Realm"))` with a party member's full „Име-Realm“ (and with „Име Фамилия“) | whether `UnitInParty` / `UnitInRaid` accept the full name on Forever; the „Хвърли“ warning „не си в група с домакина“ stays off while grouped with the host | not yet measured |
| 12 | two characters, staked Морски шах | both see the same bill; a third character sees the debt in „Тефтер“ within a few seconds | not yet measured |
| 13 | the loser alt-F4s on the last move | the debt waits, and is confirmed without a question when it logs in | not yet measured |
| 14 | the loser goes offline mid-game for three minutes, then logs in | the question appears once, with the game and the amount | not yet measured |
| 15 | „Плати“ → „Трейд“ next to the creditor | the trade opens with the amount filled in; no "action blocked"; in and out of combat (when the amount stays empty, the dialog's line tells the amount to type) | not yet measured |
| 16 | after the trade | both clients show the debt struck through within seconds | not yet measured |
| 17 | at a mailbox: „Плати“ → „Поща“, once with `/console taintLog 1` | the letter is filled, the money box shows the amount (sent as money, not COD), „Send“ is the game's own button; the taint log names no blocked action of the game's Send or Trade buttons | not yet measured |
| 18 | the receiver takes the money | the debt is struck through on both | not yet measured |
| 19 | a trade for an item with the same player | a question appears, nothing is recorded | not yet measured |
| 20 | the recipient form the mail frame accepts for „Име Фамилия“ (full name, with a realm, first name only), and which body box (`SendMailBodyEditBox` / `MailEditBox`) is filled | which form reaches the right player; that the body text shows in the letter | not yet measured |
| 21 | the new-table dialog with „Със залог“ | nothing clipped at the default and at a low UI scale; Tab moves between the two boxes | not yet measured |
| 22 | the acceptance question for Death Roll | reads naturally with 2 and with 5 seats | not yet measured |
| 23 | the bill at the end of a staked Морски шах and Death Roll | the bill does not cover the winning line or the last rolls | not yet measured |
| 24 | the hall's right column with six accounts and two questions | nothing overlaps „В кръчмата сега“; the column scrolls; long names and the question texts wrap inside it | not yet measured |
| 25 | „Плащане“ next to the creditor, far from it, at a mailbox, away from one | the right lines and buttons: „Трейд“ only next to the creditor, „Поща“ only at an open mailbox, the fee and the hold warning always; after „Трейд“ the amount to type stays shown | not yet measured |
| 26 | kill the client process after a payment and relog | the question „Тези записи на твое име не са запазени на този компютър. Твои ли са?“ appears among the questions of „Сметки“, and „Мои са“ clears the debt | not yet measured |
| 27 | „Тефтер“ with real entries from two characters | both show the same rows and the same head; a paid debt is struck through; the names stay readable on the paper; the list scrolls with the mouse wheel | not yet measured |
| 28 | the rules book in Bulgarian and in English: the topics „Залози“ and „Тефтер“, the ⓘ on „Сметки“, „Плащане“ and „Тефтер“, and `/tavern intro` | the eleven topic titles fit the list above „Покажи въведението пак“; both pages scroll to their last block; each of the three ⓘ opens „Тефтер“; the intro's third card is „Сметки и плащане“ | not yet measured |
