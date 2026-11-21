local _, ns = ...

-- Protocol version, addon-message prefix and every timing constant (seconds).
ns.Const = {
  PROTOCOL = 1,
  PREFIX = "TAVG",
  VERSION = "0.1.0",

  TURN_DEFAULT = 45,
  TURN_CHOICES = { 30, 45, 60, 90 },
  INVITE_SECONDS = 30,
  SNOOZE_SECONDS = 1800,
  INVITE_GRACE = 5, -- the host gives up on an unanswered INV this long after the toast ran out
  OFFLINE_STAND_SECONDS = 180,

  PING_EVERY = 30,
  SILENT_AFTER = 75,
  CLAIM_STAGGER = 15,

  TBL_HEARTBEAT = 60,
  TBL_EXPIRE = 150,
  TBL_MIN_GAP = 2,

  HI_HEARTBEAT = 120,
  HI_MIN_GAP = 2,
  PEER_EXPIRE = 300,

  LIST_MODE_ABOVE = 8,
  MAX_WATCHERS = 8,
  MAX_SEATS = 9, -- the most seats any table has
  SYN_MIN_GAP = 5,
  PENDING_SECONDS = 10, -- an unanswered SIT/WAT is given up ("gone") after this long
  TRACE_LINES = 200,

  ROLL_CLAIM_WAIT = 3,  -- the host waits this long to see a roll a member claims, then takes the claim
  ROLL_VERIFY_WAIT = 5, -- an unconfirmed recorded roll is checked against my sightings after this long
  ROLL_ECHO_WAIT = 3,   -- my server roll that has not shown up in chat by then is reported stuck
  ROLL_LOG = 20,        -- roll sightings kept per table

  GROUP_INVITE_GAP = 30, -- the host invites the same player into its group at most this often
  PARTY_SIZE = 5,        -- members of a party (a raid has room for more)

  FAIR_WAIT = 20,    -- an undealt shuffle round is reopened, an unrevealed hand given up, after this long
  FAIR_ASK_GAP = 5,  -- missing private faces are asked for again this often
  SEED_BYTES = 16,   -- random bytes in one seed
  DICE_WAIT = 10,    -- a throw still without the other player's seed this long after its open is thrown alone
  DICE_KEEP = 600,   -- my dice records of a table that is gone are dropped this long after I was last there
  BOOK_WAIT = 30,    -- a sealed game's keys are published at the latest this long after the game was over
  BOOK_KEYS = 24,    -- published keys a snapshot carries (the newest)
  BOOK_BATCH = 2,    -- hands of the book checked a tick
  AUTO_GRACE = 7,    -- the host plays a public timeout (E.publicAuto) for another seat this long after its deadline

  STAKE_MIN = 100,         -- copper: the smallest stake (1s)
  STAKE_MAX = 99999990000, -- copper: the largest stake (the gold cap, whole silver)
  STAKE_BREAK = 10,        -- a staked table's next game starts at the earliest this long after the last ended
  STAKE_LEFT_WINDOW = 600, -- my client confirms a claim for a game I left myself within this long
  STAKE_OWE_WAIT = 60,     -- a clean loss with no claim this long after is written down by the loser
  STAKE_SEEN_KEEP = 1209600, -- my outcome notes are dropped this long after the game (14 days)

  LEDGER_FUTURE = 3600,      -- an entry's `at` may be this far ahead of my clock
  LEDGER_AUTHOR_MAX = 5000,  -- R entries kept per author
  LEDGER_CLAIMS_OPEN = 20,   -- pending claims per creditor shown or asked about
  LEDGER_ADOPT_WAIT = 30,    -- the adoption window of a new store; my own entries wait this long after login
  LEDGER_DENY_RATE = 8,      -- denials sent per minute
  LEDGER_COALESCE = 2,       -- my entries made within this long go out in one LEV
  LEDGER_BATCH = 6,          -- entries in one whispered LEV
  LEDGER_SEND_GAP = 2,       -- a responder sends one LEV this often
  LEDGER_SEND_GAP_BUSY = 6,  -- ... while I sit at a live table
  LEDGER_JITTER_MIN = 5,     -- an exchange starts this long, plus a derived 0..15 s, after a difference is seen
  LEDGER_JITTER_MAX = 20,
  LEDGER_PEER_GAP = 300,     -- not again with the same peer before this long
  LEDGER_SYNC_TIMEOUT = 30,  -- an exchange is given up this long after the partner's last message
  LEDGER_HI_GAP = 30,        -- at most one GUILD HI after a sync this often
  LEDGER_EXCHANGE_MAX = 300, -- entries one exchange sends and takes
  LEDGER_LID_AUTHORS = 3,    -- authors listed by LID in one exchange

  PAY_WINDOW = 300, -- a trade completes a payment when the payer's PAY came within this long
  NUDGE_GAP = 3600, -- a debtor is reminded at most this often
  MAIL_FEE = 30,    -- copper: the postage of one letter
}
