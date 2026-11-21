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
}
