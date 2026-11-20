local _, ns = ...

-- English. The key set must match locale/bg.lua exactly.
local T = ns.Locale.tables.en

-- Rules book: the hall
T["help.hall.title"] = "The hall"
T["help.hall.p1"] = "The hall is the guild's tavern. Every round table is one game. The chairs around the table are the players' places."
T["help.hall.open"] = "Want to play? Under “Open a table” click “Tic-tac-toe”. Choose who may sit and how many seconds each turn has. Click “Open” and your table is in the hall."
T["help.hall.access"] = "You decide who sits with you. “Anyone in the guild”: whoever comes first sits. “Invited only”: only the people you invite sit. “My group”: only the people in your group sit."
T["help.hall.example"] = "You see a table with an empty dashed chair. You click the chair and you are seated. If the table is full, click it to watch."
T["help.hall.invite"] = "Seated and waiting? Click Maria under “In the tavern now” and press “Invite”. Maria sees an invitation with three buttons. “Accept” puts her at the table. “Not now” says no just this once. “Do not disturb for 30 min” stops invitations for half an hour. If Maria is in combat or in a dungeon, the addon says no for her."
T["help.hall.stand"] = "Had enough for today? Press “Stand up”. The table stays with the other player. They wait for a new opponent."
T["help.hall.offline"] = "Lost your connection? Your chair waits 3 minutes. While you are away, your turns are played for you. Log back in and you sit in the same place and the game goes on. After 3 minutes the addon stands you up and the game stops."

-- Rules book: Tic-tac-toe
T["help.ttt.title"] = "Tic-tac-toe"
T["help.ttt.p1"] = "The board is 3 by 3 squares. One player is X, the other is O. You take turns and put down one mark each. Three of the same mark in a row win: across, down or on a diagonal. After every game the other player starts."
T["help.ttt.example"] = "Ivan is X, Maria is O. They take turns. Ivan lines up three X in a row and wins the game. Whoever wins 3 games first wins the match."
T["help.ttt.board"] = "Here is Ivan's winning row. The three squares light up in gold."
T["help.ttt.time"] = "Every turn has a clock. If your time runs out, the addon puts your mark in the first free square. You do not lose because of it. The game simply goes on."
T["help.ttt.draw"] = "The board is full and there is no three in a row? That is a draw. Nobody gets a point."
T["help.ttt.rematch"] = "The match is over and you want more? You both press “Rematch” and a new match starts at 0 : 0."

-- Rules book: coming soon
T["help.soon.title"] = "Coming soon"
T["help.soon.p"] = "Coming soon: Death Roll, Belot, Santase, Backgammon and Texas Hold'em, and playing for a stake with a ledger of debts."
T["help.soon.example"] = "For now the tavern plays Tic-tac-toe. The other games sit dimmed in the list, marked “Soon”. As soon as they are ready, their rules will appear here, in the book."

-- First-run intro
T["intro.hall.title"] = "The hall"
T["intro.hall.text"] = "This is the guild's tavern. Every round table is a game. On the right you see who is here now."
T["intro.sit.title"] = "Sitting down"
T["intro.sit.text"] = "See an empty dashed chair? Click it and you are playing. At a table that is already playing, you can watch."
T["intro.invite.title"] = "Invites"
T["intro.invite.text"] = "Open your own table and click a name on the right. Press “Invite”. Ivan sees the invitation and sits with you in one click."
T["intro.book.title"] = "The rules book"
T["intro.book.text"] = "See an ⓘ? Click it. The rules book opens, with simple examples. This intro is in there too, if you want to see it again."

-- WoW adapter and /tavern
T["addon.title"] = "Tavern Games"
T["hall.noguild"] = "You are not in a guild. The tavern is for guild members, but you can try it with bots: /tavern bots"
T["slash.help"] = "Commands: /tavern (the hall), /tavern bots [host | invite], /tavern debug, /tavern intro, /tavern reset, /tavern probe"
T["bots.on"] = "The bots came into the tavern."
T["bots.off"] = "The bots left."
T["bots.wait"] = "Still finding out your name. Try again in a few seconds."
T["bots.none"] = "All bots are busy."
T["debug.on"] = "The protocol is shown in chat (only to you)."
T["debug.off"] = "The protocol is no longer shown."
T["reset.done"] = "Language and intro are cleared. The next opening starts from the beginning."
T["probe.name"] = "My name: %s (UnitName: %s)"
T["probe.unresolved"] = "not known yet"
T["probe.sender"] = "Last sender, as delivered: %s"
T["probe.instance"] = "IsInInstance: %s, %s"
T["probe.api"] = "%s: %s"
T["probe.random"] = "math.random(1, 1000000): %s"
T["probe.randomseed"] = "math.randomseed: %s"
T["probe.echo.sent"] = "Sent myself a %d-byte whisper, waiting %d s..."
T["probe.echo.ok"] = "echo OK: %d bytes, IsInInstance at send: %s, sender: %s"
T["probe.echo.lost"] = "echo LOST: %d bytes, IsInInstance at send: %s"
