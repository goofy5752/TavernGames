# Stage 1 probe results (spec section 10)

Early signal for stage 2, from `/tavern probe` and `/tavern debug` on WoW Forever
(Task 10, steps 3 and 4). Every entry below is **not yet measured** until it
carries a date and the characters used.

| Check | How | Result |
|---|---|---|
| Own name format | `/tavern probe`, line "Името ми" (resolved name vs `UnitName`) | not yet measured |
| Name lookup path | roster GUID match, or the `WHO` echo after 5 s | not yet measured |
| Addon-message sender format | probe line "Последен подател" and the echo sender (realm suffix? two words?) | not yet measured |
| 600-byte self-whisper outside an instance | `echo OK` / `echo LOST` | not yet measured |
| 600-byte self-whisper inside a dungeon | `echo OK` / `echo LOST`, `IsInInstance` at send | not yet measured |
| GUILD `HI` reaches the other client while one is in a dungeon | `/tavern debug` on both | not yet measured |
| Whispered `HI` reply between two guild characters | `/tavern debug` on both | not yet measured |
| `math.random(1, 1000000)` without `math.randomseed` | five samples per session, two sessions (do they repeat?) | not yet measured |
| `math.randomseed` present | probe line | not yet measured |
| `InitiateTrade` | probe line (presence only, never called) | not yet measured |
| `C_TradeInfo.SetTradeMoney` | probe line (presence only, never called) | not yet measured |
| `SetSendMailMoney` | probe line (presence only, never called) | not yet measured |
| `SendMail` | probe line (presence only, never called) | not yet measured |
| `issecretvalue` | probe line | not yet measured |
| `IsGUIDInGroup` (used by the "Групата ми" access) | probe line | not yet measured |

## Notes

(Findings, surprises and their consequences for stage 2 go here.)
