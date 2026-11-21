# Stage A: in-game checks

Run these in the game client on Forever, one character unless stated, with `/console scriptErrors 1` on throughout.
Nothing here is marked passed on the strength of the unit tests: every row stays `not yet measured` until the result is written in by hand.
Rows 9-15 and 17-18 need a second account (rows 14 and 17 are better with a third character); row 22 needs two.

Scope of this stage: Death Roll (2-5 seats, one party, never a raid) and Морски шах are playable (`Games.PLAYABLE = {ttt, deathroll}`).
The Holdem, Santase, Belot and Tabla engines already exist in `engines/`; they are shown in the hall and the new-table dialog but cannot be opened, and will be enabled stage by stage.

| # | Check | What to look for | Result |
|---|---|---|---|
| 1 | `/tavern probe` | `RandomRoll`, `C_PartyInfo.InviteUnit`, `AcceptGroup`, `UnitIsGroupLeader`, `StaticPopup_Hide`: `function`; the `/roll` format line ends with `OK` | not yet measured |
| 2 | `/tavern probe roll` | „/roll се вижда…“; which name form the line carries (first name, full name, realm); „това съм аз: yes“ | not yet measured |
| 3 | `/tavern bots`, open Death Roll („Само поканени“, 100), invite two bots, „Започни“ | five plates in two rows (3 + 2); pressing „Хвърли“ prints a real roll line in chat and adds my number in my class colour; no "action blocked" popup, in and out of combat | not yet measured |
| 4 | same game, bots' turns | their numbers arrive after about 1.5 s tagged „· маса“; no bot name in any outgoing line of `/tavern debug`; no group invite is sent | not yet measured |
| 5 | let my turn run out | the table rolls for me (tagged), the game goes on | not yet measured |
| 6 | on my turn type `/roll <max>` by hand; on another turn type `/roll 100` | the first is taken, the second ignored | not yet measured |
| 7 | finish the game, „Нова игра“ | the loser rolls first; ⓘ opens „Death Roll“ with the ladder picture | not yet measured |
| 8 | `/tavern bots host dr`, sit | the bot starts by itself; my rolls show without „?“ | not yet measured |
| 9 | two guild characters, not grouped: A opens Death Roll, B sits | B is in A's group within a second or two and no invite popup stays on B's screen; does `InviteUnit` accept a full name with a space? Record the form of the inviter's name in `PARTY_INVITE_REQUEST` (first name, full name, realm): the auto-accept matches only the host's first name, so a namesake inviter is a known risk (Review Focus 1: "never a wrong seat") | not yet measured |
| 10 | A and B play a whole game | identical ladders, no „?“, no „!“; record how B's name appears in A's roll line | not yet measured |
| 11 | B stands far away and leaves the group, then rolls | A shows B's number after about 3 s with „?“; the game goes on; the group line names B | not yet measured |
| 12 | A is in a party led by somebody else, opens a table, B sits | no invite; the line „Не си водач на групата си…“ | not yet measured |
| 13 | B is already in another group | the game's "already in a group" message appears once per 30 s at most; the group line shows | not yet measured |
| 14 | three characters if available: one stands mid-game; the host stands on its own turn | play continues; the next player hosts and its roll is taken | not yet measured |
| 15 | `/reload` by a guest mid-game | the ladder comes back from the snapshot; no second „… губи!“ line or result | not yet measured |
| 16 | hall with a Death Roll table and nine bot tables (`/tavern bots host` x9) | five chairs drawn without overlap at the Death Roll table; list row shows `1/5`; trace: still one `TBL` per 60 s per table. Note: a finished Death Roll keeps `status = "live"` (phase `"over"`), so between games the table's `st` is `live` and the hall shows „тече“; accepted (changing `st` would make newcomers infer "aborted" on `adopt`) | not yet measured |
| 17 | (a) A and B seated at a Death Roll table; a third, UNSEATED guild character C whose first name equals the first name of seated player B types `/roll` (same group or in range) | does the roll land on B's ladder (wrong seat) or is it ignored? Record the name form the line carries for C and B; nothing may be credited to B | not yet measured |
| 18 | (b) A invites B (table opens, B sits); watch the party-invite popup / `PARTY_INVITE_REQUEST` | how the inviter's name appears (full name with space? first name only? with realm?); whether the auto-accept fires and the popup disappears; record the exact string | not yet measured |
| 19 | (c) open the Death Roll new-table dialog (it is about 429 px wide) | no clipped or overlapping controls, the four start-number choices fit, the dialog sits fully on screen at the default UI scale and at a low one | not yet measured |
| 20 | (d) a Death Roll table with 3 or more seats, players with long names (two long Cyrillic words) | the plate leaves about 73 px for the name: is the name truncated sensibly, and does „от следващата игра“ overlap it? Record which seat counts and names overlap | not yet measured |
| 21 | (e) taint: a click on „Хвърли“, the auto-invite and the auto-accept, in and out of combat | `RandomRoll`, `C_PartyInfo.InviteUnit` and `AcceptGroup` really work from addon code on Forever (no "action blocked", no taint message from `AllowedWhenUntainted`); record which of the three fail | not yet measured |
| 22 | an invited player asks for a taken seat (invite table; B is invited and clicks seat 1, which A holds) | B is seated at the lowest free seat, not refused | not yet measured |

Rows 1-2 decide whether „Хвърли“ and the auto-invite work as built or fall back to the hints; rows 17, 18 and 21 decide whether the first-name match of the auto-accept and the roll attribution are safe enough to keep.
