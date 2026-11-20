// Parity fixture generator for engines/belot.lua.
//
// Plays whole Belot matches on the unmodified C# engine (NikolayIT/BelotGameEngine, MIT) through
// its public step-by-step API (BelotMatch), with fixed decks and scripted deterministic players,
// and writes what happened as Lua tables: tests/fixtures/belot/*.lua. tests/engines/belot_test.lua
// replays every fixture through the Lua engine and compares every decision and score.
//
// Nothing here implements a rule of the game: every legal-bid set, legal-card set, offered
// announce, trick winner and score in a fixture is what the C# engine reported.
namespace BelotParity
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Linq;
    using System.Text;

    using Belot.Engine.Cards;
    using Belot.Engine.Game;
    using Belot.Engine.GameMechanics;
    using Belot.Engine.Players;

    /// <summary>A small fixed generator, so the fixtures do not depend on the .NET version.</summary>
    internal sealed class Lcg
    {
        private ulong state;

        public Lcg(ulong seed)
        {
            this.state = (seed * 2862933555777941757UL) + 3037000493UL;
            this.Next(2);
        }

        public int Next(int n)
        {
            this.state = (this.state * 6364136223846793005UL) + 1442695040888963407UL;
            return (int)((this.state >> 33) % (ulong)n);
        }
    }

    /// <summary>
    /// The deck injection point. The engine's Deck shuffles in place with
    /// <c>k = random.Next(0, n--); swap(array[n], array[k])</c> for n = 32..2, starting from the
    /// order the previous deal left. This Random mirrors that array and answers each call with the
    /// k that puts the wanted card at position n, so the deck comes out in exactly the order asked.
    /// </summary>
    internal sealed class DeckFeed : Random
    {
        private readonly Card[] order = Card.AllCards.ToArray();

        private readonly Func<Card[]> nextDeck;

        private Card[] target;

        public DeckFeed(Func<Card[]> nextDeck)
        {
            this.nextDeck = nextDeck;
        }

        public List<Card[]> Dealt { get; } = new List<Card[]>();

        public override int Next(int minValue, int maxValue)
        {
            if (minValue != 0 || maxValue < 2 || maxValue > 32)
            {
                throw new InvalidOperationException("Unexpected use of the deck's random source.");
            }

            if (maxValue == 32)
            {
                this.target = this.nextDeck();
                this.Dealt.Add(this.target);
            }

            var k = Array.IndexOf(this.order, this.target[maxValue - 1], 0, maxValue);
            if (k < 0)
            {
                throw new InvalidOperationException("The wanted deck is not a permutation of the 32 cards.");
            }

            (this.order[maxValue - 1], this.order[k]) = (this.order[k], this.order[maxValue - 1]);
            return k;
        }
    }

    /// <summary>A hand-made first deal: the four hands, the bids and how the combinations are declared.</summary>
    internal sealed class Scenario
    {
        public string Name { get; set; }

        public int First { get; set; } = 1;

        /// <summary>Gets or sets the hands of seats 1..4, eight faces each (the first five are dealt first).</summary>
        public string[] Hands { get; set; }

        /// <summary>Gets or sets the bids of the first deal, one letter per decision (then passes).</summary>
        public string Bids { get; set; }

        /// <summary>Gets or sets how the first deal's combinations are declared: "all" or "rev" (the list reversed).</summary>
        public string Announce { get; set; } = "all";
    }

    internal sealed class RoundLog
    {
        public Dictionary<int, BidType> Bids { get; } = new Dictionary<int, BidType>();

        public Dictionary<int, AnnounceLog> Announces { get; } = new Dictionary<int, AnnounceLog>();

        public Dictionary<int, PlayLog> Plays { get; } = new Dictionary<int, PlayLog>();
    }

    internal sealed class AnnounceLog
    {
        public IReadOnlyList<BelotAnnounce> Offered { get; set; }

        public int Requested { get; set; }
    }

    internal sealed class PlayLog
    {
        public IReadOnlyList<Card> Playable { get; set; }

        public IReadOnlyList<Card> Belote { get; set; }
    }

    internal sealed class PlayedMatch
    {
        public string Name { get; set; }

        public string Source { get; set; }

        public int First { get; set; }

        public BelotMatchRecord Record { get; set; }

        public List<RoundLog> Logs { get; set; }

        public SortedSet<string> Tags { get; set; }
    }

    internal static class Program
    {
        private const int MaxRounds = 40;

        private static readonly PlayerPosition[] Seats =
            { PlayerPosition.South, PlayerPosition.East, PlayerPosition.North, PlayerPosition.West };

        private static readonly BidType[] BidOrder =
            {
                BidType.Clubs, BidType.Diamonds, BidType.Hearts, BidType.Spades, BidType.NoTrumps,
                BidType.AllTrumps, BidType.Double, BidType.ReDouble,
            };

        private static readonly Scenario[] Scenarios =
            {
                new Scenario
                {
                    Name = "four eights-long suits: every sequence is tied and none scores", Bids = "A",
                    Hands = new[]
                    {
                        "7C 8C 9C TC JC QC KC AC", "7D 8D 9D TD JD QD KD AD",
                        "7H 8H 9H TH JH QH KH AH", "7S 8S 9S TS JS QS KS AS",
                    },
                },
                new Scenario
                {
                    Name = "a quinte of eight beats the quintes of seven", Bids = "PH", First = 2,
                    Hands = new[]
                    {
                        "7C 8C 9C TC JC QC KC AC", "7D 8D 9D TD JD QD KD 7H",
                        "AD 8S 9S TS JS QS KS AS", "8H 9H TH JH QH KH AH 7S",
                    },
                },
                new Scenario
                {
                    Name = "six in a row beats five to the ace; the partner's quarte rides along", Bids = "S",
                    Hands = new[]
                    {
                        "TC JC QC KC AC 7D 8D 7H", "7S 8S 9S TS JS QS 9D TD",
                        "8H 9H TH 7C 8C JD QD KS", "JH QH KH AH 9C KD AD AS",
                    },
                },
                new Scenario
                {
                    Name = "four jacks beat four nines and four tens", Bids = "A",
                    Hands = new[]
                    {
                        "JC JD JH JS QC KC AC 7D", "9C 9D 9H 9S TC TD TH TS",
                        "7C 8C 8D QD KD AD 7H 8H", "QH KH AH 7S 8S QS KS AS",
                    },
                },
                new Scenario
                {
                    Name = "four nines beat four aces", Bids = "PC", First = 4,
                    Hands = new[]
                    {
                        "AC AD AH AS 7C 8C 7D 8D", "9C 9D 9H 9S 7H 8H 7S 8S",
                        "TC JC QC KC TD JD QD KD", "TH JH QH KH TS JS QS KS",
                    },
                },
                new Scenario
                {
                    Name = "fours of equal value rank in trump order: tens over kings and queens", Bids = "A",
                    Hands = new[]
                    {
                        "KC KD KH KS QC QD QH QS", "TC TD TH TS 7C 8C 9C 7D",
                        "JC AC 8D 9D JD AD 7H 8H", "9H JH AH 7S 8S 9S JS AS",
                    },
                },
                new Scenario
                {
                    Name = "aces over tens, both teams with two fours", Bids = "D",
                    Hands = new[]
                    {
                        "TC TD TH TS QC QD QH QS", "AC AD AH AS KC KD KH KS",
                        "7C 8C 9C JC 7D 8D 9D JD", "7H 8H 9H JH 7S 8S 9S JS",
                    },
                },
                new Scenario
                {
                    Name = "four jacks or the quinte through the jack: the four is declared", Bids = "A",
                    Hands = new[]
                    {
                        "JC JD JH JS 9C TC QC KC", "7C 8C AC 7D 8D 9D TD QD",
                        "KD AD 7H 8H 9H TH QH KH", "AH 7S 8S 9S TS QS KS AS",
                    },
                },
                new Scenario
                {
                    Name = "four jacks or the quinte through the jack: the quinte is declared first", Bids = "A",
                    Announce = "rev",
                    Hands = new[]
                    {
                        "JC JD JH JS 9C TC QC KC", "7C 8C AC 7D 8D 9D TD QD",
                        "KD AD 7H 8H 9H TH QH KH", "AH 7S 8S 9S TS QS KS AS",
                    },
                },
                new Scenario
                {
                    Name = "four nines with two tierces through them, declared first", Bids = "PPPS", Announce = "rev",
                    Hands = new[]
                    {
                        "7C 8C QC KC AC 7D 8D QD", "KD AD 7H 8H QH KH AH 7S",
                        "8S QS KS AS TH JH TS JS", "9C 9D 9H 9S TC JC TD JD",
                    },
                },
                new Scenario
                {
                    Name = "equal tierces in the two teams cancel a lower one too", Bids = "H",
                    Hands = new[]
                    {
                        "9C TC JC 7H 8H KD QS AS", "9S TS JS 7C 8C KC QD AH",
                        "7D 8D 9D QC AC 9H JH KS", "TD JD AD TH QH KH 7S 8S",
                    },
                },
                new Scenario
                {
                    Name = "equal quartes in one team both score", Bids = "PC", First = 1,
                    Hands = new[]
                    {
                        "7C 8C 7D 8D 9D 7H 8H 7S", "9C TC JC QC KD AD KH AH",
                        "KC AC JD 9H JH 8S KS AS", "9S TS JS QS TD QD TH QH",
                    },
                },
                new Scenario
                {
                    Name = "no trumps: nothing is declared, the totals are doubled", Bids = "N",
                    Hands = new[]
                    {
                        "7C 8C 9C TC JC QC KC AC", "7D 8D 9D TD JD QD KD AD",
                        "7H 8H 9H TH JH QH KH AH", "7S 8S 9S TS JS QS KS AS",
                    },
                },
                new Scenario
                {
                    Name = "all trumps redoubled with two belotes in one hand", Bids = "AXR",
                    Hands = new[]
                    {
                        "QC KC QD KD JH 9H AH TS", "7C 8C 9C 7D 8D 9D 7H 8H",
                        "JC TC AC JD TD AD JS 9S", "TH QH KH 7S 8S QS KS AS",
                    },
                },
            };

        public static int Main(string[] args)
        {
            if (args.Length < 1)
            {
                Console.Error.WriteLine("usage: BelotParity <output directory> [candidate matches = 3000] [fixtures = 60]");
                return 2;
            }

            var outDir = args[0];
            var candidates = args.Length > 1 ? int.Parse(args[1]) : 3000;
            var wanted = args.Length > 2 ? int.Parse(args[2]) : 60;

            var crafted = new List<PlayedMatch>();
            for (var i = 0; i < Scenarios.Length; i++)
            {
                var match = Play((ulong)(900001 + i), Scenarios[i]);
                if (match == null)
                {
                    throw new InvalidOperationException($"Scenario {i} did not finish in {MaxRounds} deals.");
                }

                crafted.Add(match);
            }

            var random = new List<PlayedMatch>();
            for (var seed = 1; seed <= candidates; seed++)
            {
                var match = Play((ulong)seed, null);
                if (match != null)
                {
                    random.Add(match);
                }
            }

            // The hand-made deals always go in; then the random matches that add the most
            // situations not covered yet (shorter first); then the rest in seed order.
            var chosen = new List<PlayedMatch>(crafted);
            var covered = new SortedSet<string>(crafted.SelectMany(x => x.Tags));
            var pool = new List<PlayedMatch>(random);
            while (true)
            {
                PlayedMatch best = null;
                var bestGain = 0;
                foreach (var match in pool)
                {
                    var gain = match.Tags.Count(x => !covered.Contains(x));
                    if (gain > bestGain || (gain == bestGain && gain > 0 && match.Record.Rounds.Count < best.Record.Rounds.Count))
                    {
                        best = match;
                        bestGain = gain;
                    }
                }

                if (best == null)
                {
                    break;
                }

                chosen.Add(best);
                pool.Remove(best);
                covered.UnionWith(best.Tags);
            }

            foreach (var match in pool)
            {
                if (chosen.Count >= wanted)
                {
                    break;
                }

                chosen.Add(match);
            }

            Directory.CreateDirectory(outDir);
            foreach (var old in Directory.GetFiles(outDir, "*.lua"))
            {
                File.Delete(old);
            }

            var index = new StringBuilder();
            index.Append("-- Generated by tools/belot-parity. Do not edit.\nreturn {\n");
            var rounds = 0;
            for (var i = 0; i < chosen.Count; i++)
            {
                chosen[i].Name = $"m{i + 1:000}";
                File.WriteAllText(Path.Combine(outDir, chosen[i].Name + ".lua"), ToLua(chosen[i]), new UTF8Encoding(false));
                index.Append($"  \"{chosen[i].Name}\",\n");
                rounds += chosen[i].Record.Rounds.Count;
            }

            index.Append("}\n");
            File.WriteAllText(Path.Combine(outDir, "index.lua"), index.ToString(), new UTF8Encoding(false));

            Console.WriteLine($"{chosen.Count} matches, {rounds} deals written to {outDir}");
            Console.WriteLine("situations covered:");
            foreach (var tag in covered)
            {
                Console.WriteLine($"  {tag}: {chosen.Count(x => x.Tags.Contains(tag))}");
            }

            return 0;
        }

        // Plays one match to the end; null when it takes too many deals.
        private static PlayedMatch Play(ulong seed, Scenario scenario)
        {
            var rnd = new Lcg(seed);
            var passPercent = 45 + rnd.Next(40);
            var doublePercent = 5 + rnd.Next(30);
            var first = scenario?.First ?? (1 + rnd.Next(4));
            var decks = 0;
            var feed = new DeckFeed(() => decks++ == 0 && scenario != null ? DeckOf(scenario.Hands) : Shuffled(rnd));
            var match = new BelotMatch(new BelotMatchOptions { FirstToPlay = Seats[first - 1], Random = feed, RecordHistory = true });
            var logs = new List<RoundLog>();
            var script = new Queue<char>(scenario?.Bids ?? string.Empty);

            match.Start();
            while (!match.IsFinished)
            {
                var seat = match.ToMove;
                var view = match.GetView(seat);
                if (view.RoundNumber > MaxRounds)
                {
                    return null;
                }

                while (logs.Count < view.RoundNumber)
                {
                    logs.Add(new RoundLog());
                }

                var log = logs[view.RoundNumber - 1];
                var scripted = scenario != null && view.RoundNumber == 1;
                BelotAction action;
                switch (match.Decision)
                {
                    case BelotDecision.Bid:
                    {
                        var available = view.AvailableBids;
                        log.Bids[view.Bids.Count] = available;
                        var bid = BidType.Pass;
                        if (scripted)
                        {
                            if (script.Count > 0)
                            {
                                bid = FromLetter(script.Dequeue());
                            }
                        }
                        else if (rnd.Next(100) >= passPercent)
                        {
                            // A double now and then; otherwise a higher contract, the cheaper ones more often.
                            var options = BidOrder.Where(x => available.HasFlag(x)).ToList();
                            var doubling = options.Where(x => x == BidType.Double || x == BidType.ReDouble).ToList();
                            var contracts = options.Except(doubling).ToList();
                            if (doubling.Count > 0 && (contracts.Count == 0 || rnd.Next(100) < doublePercent))
                            {
                                bid = doubling[0];
                            }
                            else if (contracts.Count > 0)
                            {
                                bid = contracts[Math.Min(rnd.Next(contracts.Count), rnd.Next(contracts.Count))];
                            }
                        }

                        action = BelotAction.Bid(bid);
                        break;
                    }

                    case BelotDecision.Announce:
                    {
                        var offered = view.AvailableAnnounces;
                        var declared = offered.ToList();
                        var mode = scripted ? (scenario.Announce == "rev" ? 8 : 0) : rnd.Next(10);
                        if (mode == 7)
                        {
                            declared.Clear();
                        }
                        else if (mode == 8)
                        {
                            declared.Reverse();
                        }
                        else if (mode == 9)
                        {
                            declared = declared.Where(x => rnd.Next(2) == 0).OrderBy(x => rnd.Next(1000)).ToList();
                        }

                        log.Announces[CardsPlayed(view)] = new AnnounceLog { Offered = offered, Requested = declared.Count };
                        action = BelotAction.Declare(declared.Select(x => new Announce(x.Type, x.Card)));
                        break;
                    }

                    default:
                    {
                        var playable = view.PlayableCards;
                        log.Plays[CardsPlayed(view)] = new PlayLog { Playable = playable, Belote = view.BeloteCards };
                        action = BelotAction.PlayCard(playable[rnd.Next(playable.Count)], rnd.Next(100) < 85);
                        break;
                    }
                }

                var result = match.Act(seat, action);
                if (result != BelotActResult.Ok)
                {
                    throw new InvalidOperationException($"The engine refused a scripted action: {result}.");
                }
            }

            var record = match.GetRecord();
            if (record.Rounds.Count > MaxRounds)
            {
                return null;
            }

            for (var i = 0; i < record.Rounds.Count; i++)
            {
                if (!record.Rounds[i].Deal.SequenceEqual(feed.Dealt[i]))
                {
                    throw new InvalidOperationException("The engine did not deal the injected deck.");
                }
            }

            var played = new PlayedMatch
            {
                Source = scenario != null ? "scenario: " + scenario.Name : "seed " + seed,
                First = first,
                Record = record,
                Logs = logs,
            };
            played.Tags = Tags(played);
            return played;
        }

        private static int CardsPlayed(BelotSeatView view) => (view.Tricks.Count * 4) + view.CurrentTrick.Count;

        private static Card[] Shuffled(Lcg rnd)
        {
            var deck = Card.AllCards.ToArray();
            for (var n = deck.Length; n > 1; n--)
            {
                var k = rnd.Next(n);
                (deck[n - 1], deck[k]) = (deck[k], deck[n - 1]);
            }

            return deck;
        }

        // The deck that deals these hands: five cards each one at a time from seat 1, then three each.
        private static Card[] DeckOf(string[] hands)
        {
            var cards = hands.Select(x => x.Split(' ').Select(ParseCard).ToArray()).ToArray();
            var deck = new Card[32];
            for (var j = 0; j < 20; j++)
            {
                deck[j] = cards[j % 4][j / 4];
            }

            for (var j = 20; j < 32; j++)
            {
                deck[j] = cards[j % 4][5 + ((j - 20) / 4)];
            }

            if (deck.Distinct().Count() != 32)
            {
                throw new InvalidOperationException("A scenario's hands are not the 32 cards: " + string.Join(" | ", hands));
            }

            return deck;
        }

        private static Card ParseCard(string face) =>
            Card.GetCard((CardSuit)"CDHS".IndexOf(face[1]), (CardType)"789TJQKA".IndexOf(face[0]));

        private static string Face(Card card) => $"{"789TJQKA"[(int)card.Type]}{"CDHS"[(int)card.Suit]}";

        private static string Faces(IEnumerable<Card> cards) => string.Concat(cards.Select(Face));

        private static int SeatNumber(PlayerPosition seat) => Array.IndexOf(Seats, seat) + 1;

        private static BidType FromLetter(char letter) =>
            letter switch
                {
                    'P' => BidType.Pass,
                    'C' => BidType.Clubs,
                    'D' => BidType.Diamonds,
                    'H' => BidType.Hearts,
                    'S' => BidType.Spades,
                    'N' => BidType.NoTrumps,
                    'A' => BidType.AllTrumps,
                    'X' => BidType.Double,
                    'R' => BidType.ReDouble,
                    _ => throw new ArgumentException("Unknown bid letter " + letter),
                };

        private static char Letter(BidType bid) =>
            bid switch
                {
                    BidType.Pass => 'P',
                    BidType.Clubs => 'C',
                    BidType.Diamonds => 'D',
                    BidType.Hearts => 'H',
                    BidType.Spades => 'S',
                    BidType.NoTrumps => 'N',
                    BidType.AllTrumps => 'A',
                    BidType.Double => 'X',
                    BidType.ReDouble => 'R',
                    _ => throw new ArgumentException("Not a single bid: " + bid),
                };

        private static string Letters(BidType available) =>
            "P" + string.Concat(BidOrder.Where(x => available.HasFlag(x)).Select(Letter));

        private static BidType Base(BidType contract) => contract & ~BidType.Double & ~BidType.ReDouble;

        private static int Multiplier(BidType contract) =>
            contract.HasFlag(BidType.ReDouble) ? 4 : contract.HasFlag(BidType.Double) ? 2 : 1;

        private static string Kind(AnnounceType type) =>
            type switch
                {
                    AnnounceType.Belot => "b",
                    AnnounceType.FourOfAKind => "c",
                    AnnounceType.FourNines => "c9",
                    AnnounceType.FourJacks => "cJ",
                    _ => "s" + (type - AnnounceType.SequenceOf3 + 3),
                };

        private static bool IsTeamOne(PlayerPosition seat) => seat == PlayerPosition.South || seat == PlayerPosition.North;

        // The situations a match went through; used only to choose which matches become fixtures.
        private static SortedSet<string> Tags(PlayedMatch match)
        {
            var tags = new SortedSet<string>(StringComparer.Ordinal);
            int one = 0, two = 0, hanging = 0;
            var rounds = match.Record.Rounds;
            for (var r = 0; r < rounds.Count; r++)
            {
                var round = rounds[r];
                var log = match.Logs[r];
                var result = round.Result;
                var last = r == rounds.Count - 1;

                var doubled = false;
                foreach (var bid in round.Bids)
                {
                    if (bid.Type == BidType.Double || bid.Type == BidType.ReDouble)
                    {
                        doubled = true;
                    }
                    else if (bid.Type != BidType.Pass)
                    {
                        if (doubled)
                        {
                            tags.Add("bid over a doubled contract");
                        }

                        doubled = false;
                    }
                }

                var contract = result.Contract.Type;
                if (contract == BidType.Pass)
                {
                    tags.Add("passed out");
                    if (hanging > 0)
                    {
                        tags.Add("passed out with points hanging");
                    }

                    if (Math.Max(one, two) >= BelotMatch.PointsToWin)
                    {
                        tags.Add("passed out with a team over 151");
                    }

                    continue;
                }

                var suit = Base(contract) != BidType.AllTrumps && Base(contract) != BidType.NoTrumps;
                var kind = suit ? "suit" : Letter(Base(contract)).ToString();
                var multiplier = Multiplier(contract);
                tags.Add("contract " + Letter(Base(contract)));
                tags.Add("contract " + kind + " x" + multiplier);

                int rawOne = result.SouthNorthTotalInRoundPoints, rawTwo = result.EastWestTotalInRoundPoints;
                var declarerOne = IsTeamOne(result.Contract.Player);
                int rawDeclarer = declarerOne ? rawOne : rawTwo, rawOther = declarerOne ? rawTwo : rawOne;
                var outcome = rawDeclarer > rawOther ? "made" : rawDeclarer < rawOther ? "inside" : "hanging";
                tags.Add($"{outcome} x{multiplier}");
                tags.Add($"{outcome} {kind}");
                if (outcome == "made" && multiplier == 1)
                {
                    var edge = Base(contract) == BidType.AllTrumps ? 4 : 6;
                    if (!suit && Base(contract) == BidType.NoTrumps)
                    {
                        tags.Add("rounding N remainder " + (rawOne % 10));
                    }
                    else
                    {
                        if (rawDeclarer % 10 == edge)
                        {
                            tags.Add($"rounding {kind}: winner at the edge");
                        }

                        if (rawOther % 10 == edge)
                        {
                            tags.Add($"rounding {kind}: loser at the edge");
                        }
                    }
                }

                if (outcome == "inside" && multiplier == 1)
                {
                    tags.Add("inside sum remainder " + ((rawOne + rawTwo) % 10));
                }

                if (hanging > 0)
                {
                    tags.Add(result.HangingPoints == 0 ? "hanging points collected" : "hanging points grow");
                    tags.Add($"hanging before, {outcome} x{multiplier}");
                }

                if (result.NoTricksForOneOfTheTeams)
                {
                    tags.Add("valat " + kind);
                    tags.Add("valat x" + multiplier);
                    tags.Add(rawDeclarer > rawOther ? "valat by the declarer" : "valat against the declarer");
                }

                var fours = new HashSet<bool>();
                var sequences = new HashSet<bool>();
                foreach (var announce in round.Announces)
                {
                    var scored = announce.IsScored == true ? "scores" : "does not score";
                    tags.Add($"{Kind(announce.Type)} {scored}");
                    if (announce.Type == AnnounceType.Belot)
                    {
                        tags.Add("belote " + kind);
                    }
                    else if (announce.Type >= AnnounceType.FourOfAKind)
                    {
                        fours.Add(IsTeamOne(announce.Player));
                    }
                    else
                    {
                        sequences.Add(IsTeamOne(announce.Player));
                    }
                }

                if (fours.Count == 2)
                {
                    tags.Add("fours in both teams");
                }

                if (sequences.Count == 2)
                {
                    tags.Add("sequences in both teams");
                    if (round.Announces.Where(x => x.Type != AnnounceType.Belot && x.Type < AnnounceType.FourOfAKind).All(x => x.IsScored != true))
                    {
                        tags.Add("tied sequences cancel");
                    }
                }

                if (round.Announces.Count(x => x.Type == AnnounceType.Belot) > 1)
                {
                    tags.Add("two belotes in a deal");
                }

                foreach (var pair in log.Announces)
                {
                    var seat = round.Tricks[0].Cards[pair.Key].Player;
                    var kept = round.Announces.Count(x => x.Player == seat && x.Type != AnnounceType.Belot);
                    var offered = pair.Value.Offered;
                    if (kept < pair.Value.Requested)
                    {
                        tags.Add("a declaration sharing a card is dropped");
                    }

                    if (pair.Value.Requested == 0)
                    {
                        tags.Add("combinations not declared");
                    }

                    if (offered.Count > 1)
                    {
                        tags.Add("several combinations offered");
                    }

                    if (offered.Any(x => x.Type >= AnnounceType.FourOfAKind) && offered.Any(x => x.Type < AnnounceType.FourOfAKind))
                    {
                        tags.Add("a four and a sequence offered");
                    }
                }

                one += result.SouthNorthPoints;
                two += result.EastWestPoints;
                hanging = result.HangingPoints;
                if (!last)
                {
                    if (one >= BelotMatch.PointsToWin || two >= BelotMatch.PointsToWin)
                    {
                        if (result.NoTricksForOneOfTheTeams)
                        {
                            tags.Add("over 151 on a valat: the match goes on");
                        }
                        else if (one == two)
                        {
                            tags.Add("over 151 and tied: the match goes on");
                        }
                        else if ((one > two ? result.SouthNorthPoints : result.EastWestPoints) == 0)
                        {
                            tags.Add("leader over 151 scored nothing: the match goes on");
                        }
                    }
                }
                else if (Math.Min(one, two) >= BelotMatch.PointsToWin)
                {
                    tags.Add("both teams over 151 at the end");
                }
            }

            tags.Add("first seat " + match.First);
            tags.Add("winner team " + (match.Record.Winner == PlayerPosition.SouthNorthTeam ? 1 : 2));
            return tags;
        }

        private static string ToLua(PlayedMatch match)
        {
            var record = match.Record;
            var lua = new StringBuilder();
            lua.Append("-- Generated by tools/belot-parity from a match played on NikolayIT/BelotGameEngine (MIT). Do not edit.\n");
            lua.Append("-- bids: \"<seat><bid>/<legal bids>\"; plays: \"<seat><card>[+ = belote declared]/<legal cards>/<cards a belote\n");
            lua.Append("-- may be declared with>\"; anns[play number in the first trick] = \"<offered>/<declared>\" as kind:top card;\n");
            lua.Append("-- scored: \"<seat> <kind> <card> <1 = scores>\"; wins: the seat that took each trick.\n");
            lua.Append("return {\n");
            lua.Append($"  name = \"{match.Name}\", source = \"{match.Source}\", first = {match.First},\n");
            lua.Append("  rounds = {\n");
            int one = 0, two = 0;
            for (var r = 0; r < record.Rounds.Count; r++)
            {
                var round = record.Rounds[r];
                var log = match.Logs[r];
                var result = round.Result;
                lua.Append("    {\n");
                lua.Append($"      first = {SeatNumber(round.FirstToPlay)}, deck = \"{Faces(round.Deal)}\",\n");

                lua.Append("      bids = {");
                for (var i = 0; i < round.Bids.Count; i++)
                {
                    var legal = log.Bids.TryGetValue(i, out var available) ? Letters(available) : "P";
                    lua.Append($" \"{SeatNumber(round.Bids[i].Player)}{Letter(round.Bids[i].Type)}/{legal}\",");
                }

                lua.Append(" },\n");

                var contract = result.Contract.Type;
                if (contract != BidType.Pass)
                {
                    lua.Append($"      contract = {{ seat = {SeatNumber(result.Contract.Player)}, b = \"{Letter(Base(contract))}\", x = {Multiplier(contract)} }},\n");
                    lua.Append("      plays = {\n");
                    var n = 0;
                    foreach (var trick in round.Tricks)
                    {
                        lua.Append("       ");
                        foreach (var card in trick.Cards)
                        {
                            var forced = !log.Plays.TryGetValue(n, out var play);
                            var legal = forced ? Face(card.Card) : Faces(play.Playable);
                            var belote = forced ? string.Empty : Faces(play.Belote);
                            lua.Append($" \"{SeatNumber(card.Player)}{Face(card.Card)}{(card.Belote ? "+" : string.Empty)}/{legal}/{belote}\",");
                            n++;
                        }

                        lua.Append('\n');
                    }

                    lua.Append("      },\n");
                    lua.Append("      anns = {");
                    foreach (var pair in log.Announces.OrderBy(x => x.Key))
                    {
                        var seat = round.Tricks[0].Cards[pair.Key].Player;
                        var offered = string.Join(",", pair.Value.Offered.Select(x => $"{Kind(x.Type)}:{Face(x.Card)}"));
                        var declared = string.Join(
                            ",",
                            round.Announces.Where(x => x.Player == seat && x.Type != AnnounceType.Belot).Select(x => $"{Kind(x.Type)}:{Face(x.Card)}"));
                        lua.Append($" [{pair.Key + 1}] = \"{offered}/{declared}\",");
                    }

                    lua.Append(" },\n");
                    lua.Append($"      wins = \"{string.Concat(round.Tricks.Select(x => SeatNumber(x.Winner)))}\",\n");
                    lua.Append("      scored = {");
                    foreach (var announce in round.Announces)
                    {
                        lua.Append($" \"{SeatNumber(announce.Player)} {Kind(announce.Type)} {Face(announce.Card)} {(announce.IsScored == true ? 1 : 0)}\",");
                    }

                    lua.Append(" },\n");
                }

                one += result.SouthNorthPoints;
                two += result.EastWestPoints;
                lua.Append($"      raw = {{ {result.SouthNorthTotalInRoundPoints}, {result.EastWestTotalInRoundPoints} }}, ");
                lua.Append($"pts = {{ {result.SouthNorthPoints}, {result.EastWestPoints} }}, ");
                lua.Append($"hang = {result.HangingPoints}, valat = {(result.NoTricksForOneOfTheTeams ? "true" : "false")}, ");
                lua.Append($"total = {{ {one}, {two} }},\n");
                lua.Append("    },\n");
            }

            if (one != record.SouthNorthPoints || two != record.EastWestPoints)
            {
                throw new InvalidOperationException("The deals do not add up to the match score.");
            }

            lua.Append("  },\n");
            lua.Append($"  winner = {(record.Winner == PlayerPosition.SouthNorthTeam ? 1 : 2)}, ");
            lua.Append($"score = {{ {record.SouthNorthPoints}, {record.EastWestPoints} }}, hang = {record.HangingPoints},\n");
            lua.Append("  tags = {\n");
            foreach (var tag in match.Tags)
            {
                lua.Append($"    \"{tag}\",\n");
            }

            lua.Append("  },\n}\n");
            return lua.ToString();
        }
    }
}
