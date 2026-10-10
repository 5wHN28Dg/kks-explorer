## A web sign-in renews while it is used (the user, 2026-10-10): what needs a clock. The answers over HTTP (the
## cookie sent again, what ends a session) are in e2e/test_server_http.py (SessionRenewal).
import std/[unittest, os, times]
import kks/crypto
import plat
import kksl/server

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
