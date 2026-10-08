## Failed-attempt throttling (kksl/throttle.nim, issue #39): spraying and lockout.
import std/unittest
import kksl/throttle

proc attempt(t: var Throttle, account, source: string, now: float): bool =
  ## one wrong password, as the server's login counts it -> was it let through to the password check?
  let keys = [source, "u:" & account & "@" & source]
  if t.blocked(keys, now, ["u:" & account]): return false
  t.record(false, keys, now, ["u:" & account])
  true

suite "throttle":
  test "one source is slowed after a few failures, and a success clears it":
    var t: Throttle
    for i in 0 ..< FreeFails: check t.attempt("ali", "ip:10.0.0.9", 100.0)
    check not t.attempt("ali", "ip:10.0.0.9", 100.0)
    check not t.attempt("bob", "ip:10.0.0.9", 100.0)       # the source, whatever the account
    check t.attempt("ali", "ip:10.0.0.9", 100.0 + 16)      # after the first back-off
    t.record(true, ["ip:10.0.0.9", "u:ali@ip:10.0.0.9"], 200.0, ["u:ali"])
    check not t.blocked(["ip:10.0.0.9"], 200.0)

  test "an attacker can't lock an account's owner out from elsewhere":
    var t: Throttle
    for i in 0 ..< 20: discard t.attempt("ali", "ip:10.0.0.66", 100.0 + float(i))
    check not t.blocked(["ip:10.0.0.7", "u:ali@ip:10.0.0.7"], 130.0, ["u:ali"])

  test "spraying over many accounts and rotating sources is capped (TLS peer IDs are free)":
    var t: Throttle
    var through = 0
    for i in 0 ..< 1000:                                   # a new peer ID for every guess, a new account each time
      if t.attempt("user" & $(i mod 200), "tls:peer" & $i, 100.0 + float(i) * 0.1): inc through
    check through <= GlobalCap + 200                     # without the cap: all 1000
    check t.underPressure(200.0)
    check not t.underPressure(200.0 + Window + 1)          # it drains

  test "the address is the source for TLS: rotating peer IDs from one address doesn't help":
    var t: Throttle
    var through = 0
    for i in 0 ..< 100:
      let keys = [sourceKey("192.168.1.50"), "tls:peer" & $i]
      if not t.blocked(keys, 100.0):
        t.record(false, keys, 100.0)
        inc through
    check through == FreeFails

  test "source keys: IPv6 by /64, IPv4-mapped as IPv4":
    check sourceKey("2001:db8:1:2:aaaa::1") == sourceKey("2001:db8:1:2:bbbb::2")
    check sourceKey("2001:db8:1:2::1") != sourceKey("2001:db8:1:3::1")
    check sourceKey("::ffff:192.168.1.5") == sourceKey("192.168.1.5")
    check sourceKey("192.168.1.5") == "ip:192.168.1.5"
