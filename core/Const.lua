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
  SYN_MIN_GAP = 5,
  PENDING_SECONDS = 10, -- an unanswered SIT/WAT is given up ("gone") after this long
  TRACE_LINES = 200,
}
