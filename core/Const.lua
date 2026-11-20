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
  TRACE_LINES = 200,
}
