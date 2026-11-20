# belot-parity

Generates the parity fixtures for `engines/belot.lua`: whole Belot matches played on the
**unmodified C# engine** [NikolayIT/BelotGameEngine](https://github.com/NikolayIT/BelotGameEngine)
(MIT), written out as Lua tables in `tests/fixtures/belot/`. `tests/engines/belot_test.lua`
replays every fixture through the Lua engine and compares every legal-bid set, legal-card set,
belote option, offered announce, trick winner, scoring announce and score.

The tool implements no rule of the game. Everything in a fixture is what the C# engine reported.

## Rebuild the fixtures

Needs the .NET SDK (8 or newer) and the engine's sources. The fixtures in the repository were
generated from commit `a4a6e4d9d27ce5cec42ee5648b252452d07f1aac` (package version 2.0.0).

```sh
# from the repository root
git clone https://github.com/NikolayIT/BelotGameEngine tools/belot-parity/BelotGameEngine
git -C tools/belot-parity/BelotGameEngine checkout a4a6e4d9d27ce5cec42ee5648b252452d07f1aac

dotnet run --project tools/belot-parity -c Release -- tests/fixtures/belot
bash t.sh tests/engines/belot_test.lua
```

`tools/belot-parity/BelotGameEngine/`, `bin/` and `obj/` are git-ignored. To use a checkout
somewhere else: `dotnet run --project tools/belot-parity -c Release -p:BelotEngineDir=<path> -- tests/fixtures/belot`.
The build restores the one NuGet package the engine's own project declares (StyleCop.Analyzers).

Arguments: `<output directory> [candidate matches = 3000] [fixtures = 60]`. The output directory's
`*.lua` files are replaced. The run is deterministic: the same engine commit gives the same files.

## How it works

- **Engine**: referenced as a project (`src/Belot.Engine/Belot.Engine.csproj`), driven only through
  its public step-by-step API: `BelotMatch.Start/ToMove/Decision/GetView/Act/GetRecord`.
- **Fixed decks**: the engine has no "use this deck" switch, but `BelotMatchOptions.Random` is the
  source of its shuffle (`k = random.Next(0, n--); swap(array[n], array[k])`, in place, starting from
  the previous deal's order). `DeckFeed` is a `Random` that mirrors that array and returns the `k`
  that puts the wanted card at each position, so the deck comes out in exactly the order asked. The
  tool checks the engine's own record of the deal against the injected deck.
- **Players**: scripted from a small fixed LCG (not `System.Random`, so nothing depends on the .NET
  version): random bids with per-match pass and double rates, random legal cards, a belote claimed
  85% of the time, combinations declared in full, not at all, reversed or as a random subset.
- **Hand-made first deals** (`Scenarios` in `Program.cs`) cover what random deals practically never
  produce: eight in a row, fours against fours, a four against the sequence through it, tied sequences.
- **Selection**: the hand-made matches, then of 3000 random matches the ones that add situations
  not covered yet (the `tags` of a fixture), then more in seed order up to 60.

## Fixture format

`index.lua` lists the fixtures. Each `mNNN.lua` returns one match (seats 1..4 = South, East, North,
West; teams 1 = seats 1+3, 2 = seats 2+4; cards are rank `789TJQKA` + suit `CDHS`):

```lua
{
  name = "m004", source = "seed 17" or "scenario: ...", first = 1,   -- first to bid in deal 1
  rounds = {
    {
      first = 1,
      deck = "JC9C7C...",                       -- the 32 cards in dealing order
      bids = { "1A/PCDHSNA", "2P/PX", ... },    -- <seat><bid>/<the bids legal at that moment>
                                                -- P pass, C D H S N A, X double, R redouble
      contract = { seat = 1, b = "A", x = 1 },  -- absent when the deal was passed out
      plays = { "1JH/JCQCKC.../QCKC", "3KD+/8DQDKDAD/QDKD", ... },
          -- <seat><card>[+ if a belote was declared]/<legal cards>/<cards a belote may be declared with>
      anns = { [1] = "cJ:JS,s3:AC,s4:AC/cJ:JS,s3:AC" },
          -- by play number in the first trick: <offered>/<declared and accepted>, kind:top card
          -- s3..s8 sequences, c four of a kind, c9 four nines, cJ four jacks
      wins = "11122122",                        -- the seat that took each trick
      scored = { "1 cJ JS 1", "2 c9 9S 0", "3 b KD 1" },  -- <seat> <kind> <card> <1 = it scored>
      raw = { 372, 126 },                       -- the teams' totals in the deal
      pts = { 37, 13 }, hang = 0, valat = false,
      total = { 37, 13 },                       -- the match score after the deal
    },
  },
  winner = 1, score = { 152, 97 }, hang = 0,
  tags = { ... },                               -- the situations the match went through
}
```
