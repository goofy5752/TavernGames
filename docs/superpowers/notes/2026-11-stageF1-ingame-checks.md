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
