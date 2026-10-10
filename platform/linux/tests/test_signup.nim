## Sign-up with the plant's code (the user, 2026-10-10): what needs a clock. The rest (every refusal over HTTP, the
## throttle by address, approving and rejecting) is in e2e/test_server_http.py.
import std/[unittest, os, times, strutils]
import kks/[json, crypto]
import plat
import kksl/[server, throttle]

let P = testProvider()

proc open(name: string): Server =
  let dir = getTempDir() / "kks-signup-test"
  createDir(dir)
  var cfg = defaultConfig()
  cfg.storePath = dir / name
  removeFile(cfg.storePath)
  openServer(cfg, P, P.randomBytes(32))

proc ask(username, code: string): JNode =
  newObj(@[("code", newStr(code)), ("username", newStr(username)), ("full_name", newStr("Some One")),
           ("position", newStr("Operator")), ("password", newStr("a long password"))])

proc refused(s: Server, d: JNode, source: string, now: float): string =
  ## "" = the request was filed; else the refusal's words
  try:
    s.requestAccount(d, [source], now)
    ""
  except CatchableError as e: e.msg

suite "sign-up":
  test "a request nobody decides is dropped after SignupDays":
    let s = open("expiry.db")
    let t0 = epochTime()
    s.setSignupCode("plant-code-1")
    check s.refused(ask("ali", "plant-code-1"), "ip:10.0.0.1", t0) == ""
    check s.signupRequests(int64(t0) + SignupDays * 86400 - 60).len == 1
    check s.signupsOut(int64(t0) + 3600)["requests"].elems.len == 1
    check s.signupRequests(int64(t0) + SignupDays * 86400 + 1).len == 0
    check s.signupRequests(int64(t0)).len == 0          # dropped from the store, not only left out
    check s.signupsOut(int64(t0))["requests"].elems.len == 0

  test "expired requests free their places under the cap":
    let s = open("cap.db")
    let t0 = epochTime()
    s.setSignupCode("plant-code-1")
    for i in 0 ..< SignupMaxPending:
      check s.refused(ask("u" & $i, "plant-code-1"), "ip:10.1.0." & $i, t0) == ""
    let full = s.refused(ask("late", "plant-code-1"), "ip:10.2.0.1", t0 + 1)
    check full.len > 0
    check full == s.refused(ask("late", "a wrong code"), "ip:10.2.0.2", t0 + 2)   # the same words as a wrong code
    check s.signupRequests(int64(t0) + 2).len == SignupMaxPending
    check s.refused(ask("late", "plant-code-1"), "ip:10.2.0.3", t0 + float(SignupDays * 86400 + 5)) == ""
    check s.signupRequests(int64(t0) + SignupDays * 86400 + 5).len == 1

  test "refusals are throttled per source and, under pressure, for everyone; a block ends":
    let s = open("throttle.db")
    let t0 = epochTime()
    s.setSignupCode("plant-code-1")
    var words: seq[string]
    for i in 0 ..< FreeFails: words.add s.refused(ask("xx", "wrong-" & $i), "ip:10.3.0.1", t0)
    check words[0].len > 0 and "Too many" notin words[^1]
    check "Too many" in s.refused(ask("xx", "plant-code-1"), "ip:10.3.0.1", t0 + 1)      # the right code too, for now
    check s.refused(ask("yy", "plant-code-1"), "ip:10.3.0.2", t0 + 1) == ""                # another source is not held up
    check s.refused(ask("xx", "plant-code-1"), "ip:10.3.0.1", t0 + 20) == ""               # 15 s later
    for i in 0 ..< GlobalCap: discard s.refused(ask("xx", "wrong"), "ip:10.4." & $(i div 200) & "." & $(i mod 200), t0 + 30)
    check "Too many" in s.refused(ask("zz", "plant-code-1"), "ip:10.5.0.1", t0 + 31)      # a source never seen before
    check s.refused(ask("zz", "plant-code-1"), "ip:10.5.0.1", t0 + 31 + Window + 1) == ""

  test "the code: 6 to 64 characters, cleared by an empty one, never kept in clear":
    let s = open("code.db")
    expect ValueError: s.setSignupCode("short")
    expect ValueError: s.setSignupCode(repeat('x', 65))
    check not s.signupOn
    s.setSignupCode("  plant-code-1  ")
    check s.signupOn
    check "plant-code-1" notin toText(s.signupsOut())
    check "plant-code-1" notin readFile(getTempDir() / "kks-signup-test" / "code.db")
    check s.refused(ask("ali", " plant-code-1 "), "ip:10.6.0.1", epochTime()) == ""
    s.setSignupCode("")
    check not s.signupOn
    check s.refused(ask("bob", "plant-code-1"), "ip:10.6.0.2", epochTime()).len > 0
    check s.refused(ask("bob", ""), "ip:10.6.0.3", epochTime()).len > 0                   # off: no code is the code
