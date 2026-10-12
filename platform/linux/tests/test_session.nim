## A web sign-in renews while it is used (the user, 2026-10-10): what needs a clock. The answers over HTTP (the
## cookie sent again, what ends a session) are in e2e/test_server_http.py (SessionRenewal).
import std/[unittest, os, times]
import kks/[crypto, json]
import plat
import kksl/[server, dbstore]

let P = testProvider()

proc open(name: string): Server =
  let dir = getTempDir() / "kks-session-test"
  createDir(dir)
  var cfg = defaultConfig()
  cfg.storePath = dir / name
  removeFile(cfg.storePath)
  openServer(cfg, P, P.randomBytes(32))

const Day = 86400'i64

suite "session renewal":
  test "used at least every session_days, a session never ends; unused, it ends and stays ended":
    let s = open("renew.db")
    let t0 = int64(epochTime())
    let raw = s.newSession(7)
    let life = int64(s.cfg.sessionDays) * Day
    check s.sessionEnds(raw) in t0 + life - 5 .. t0 + life + 5
    # within the first day: not rewritten
    check not s.renewSession(raw, t0 + Day - 60)
    check s.sessionEnds(raw) in t0 + life - 5 .. t0 + life + 5
    # a day on: session_days from now; and not again the same day
    check s.renewSession(raw, t0 + Day + 60)
    check s.sessionEnds(raw) == t0 + Day + 60 + life
    check not s.renewSession(raw, t0 + Day + 3600)
    check s.sessionEnds(raw) == t0 + Day + 60 + life
    # used once every 29 days for a year: still there
    var t = t0 + Day + 60
    for i in 1 .. 12:
      t += 29 * Day
      check s.renewSession(raw, t)
      check s.sessionEnds(raw) == t + life
    # then not used for longer than session_days: over, and using the cookie afterwards brings nothing back
    let ended = s.sessionEnds(raw)
    check not s.renewSession(raw, ended + 1)
    check s.sessionEnds(raw) == ended
    check not s.renewSession(raw, ended + 40 * Day)
    check s.sessionEnds(raw) == ended

  test "a session that was ended, and a cookie nobody issued, renew nothing":
    let s = open("ended.db")
    let t0 = int64(epochTime())
    let a = s.newSession(7)
    let b = s.newSession(8)
    s.endSessions(7)
    check s.sessionEnds(a) == 0
    check not s.renewSession(a, t0 + 2 * Day)
    check s.sessionEnds(a) == 0                      # not made again
    check s.renewSession(b, t0 + 2 * Day)            # another account's is untouched
    check not s.renewSession("", t0 + 2 * Day)
    check not s.renewSession("not-a-session", t0 + 2 * Day)
    check s.sessionEnds("not-a-session") == 0

suite "sign out everywhere":
  test "every sign-in of the account ends, the others' stay, and none comes back by its cookie":
    let s = open("everywhere.db")
    let t0 = int64(epochTime())
    let a1 = s.newSession(7)
    let a2 = s.newSession(7)
    let a3 = s.newSession(7)
    let b = s.newSession(8)
    check s.openSessions(7) == 3
    check s.openSessions(8) == 1
    check s.endSessions(7) == 3
    check s.openSessions(7) == 0
    for raw in [a1, a2, a3]:
      check s.sessionEnds(raw) == 0
      check not s.renewSession(raw, t0 + 2 * Day)     # the renewal of a sign-in in use does not bring it back
      check s.sessionEnds(raw) == 0
    check s.endSessions(7) == 0                       # nothing left to end
    check s.openSessions(8) == 1
    check s.renewSession(b, t0 + 2 * Day)

  test "the other sessions: all but the one that asks, which carries on and renews":
    let s = open("others.db")
    let t0 = int64(epochTime())
    let here = s.newSession(7)
    let phone = s.newSession(7)
    let shared = s.newSession(7)
    let other = s.newSession(8)
    check s.endSessions(7, keep = here) == 2
    check s.openSessions(7) == 1
    check s.sessionEnds(here) > 0
    check s.sessionEnds(phone) == 0
    check s.sessionEnds(shared) == 0
    check s.renewSession(here, t0 + 2 * Day)
    check not s.renewSession(phone, t0 + 2 * Day)
    check s.endSessions(7, keep = here) == 0          # none: said as none
    check s.sessionEnds(here) > 0
    # a cookie of another account, or one nobody issued, keeps nothing of this account
    check s.endSessions(7, keep = other) == 1
    check s.openSessions(7) == 0
    check s.sessionEnds(other) > 0
    let again = s.newSession(7)
    check s.endSessions(7, keep = "not-a-session") == 1
    check s.sessionEnds(again) == 0

  test "a sign-in that had expired anyway is removed and not counted":
    let s = open("expired.db")
    let here = s.newSession(7)
    discard s.newSession(7)
    s.store.putRow("sessions", "an-old-one", newObj(@[("user_id", newInt(7)), ("created", newInt(1)), ("expires", newInt(2))]))
    check s.openSessions(7) == 2
    check s.endSessions(7, keep = here) == 1
    check s.store.getRow("sessions", "an-old-one") == nil
    check s.openSessions(7) == 1
