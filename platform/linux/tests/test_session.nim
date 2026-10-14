## A web sign-in renews while it is used (the user, 2026-10-10): what needs a clock. The answers over HTTP (the
## cookie sent again, what ends a session) are in e2e/test_server_http.py (SessionRenewal).
import std/[unittest, os, times, strutils, tables]
import kks/[crypto, json, api, proto, plant, node, extras, invites]
import plat
import kksl/[server, dbstore, argon2]

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

suite "who may sign whom out, and the server's own command":
  let s = open("who.db")
  proc S(x: string): JNode = newStr(x)
  let boss = s.createPlant("boss", "The Manager", S("Plant manager"), "a long password")
  let mgr = s.actorFor(boss)
  var id: array[4, int64]
  for i, (name, role) in [("sara", "admin"), ("omar", "admin"), ("ali", "user"), ("tom", "user")]:
    id[i] = s.createAccount(mgr, name, name & " person", S("Operator"), role, S("a long password"))["id"].i
  let (sara, omar, ali, tom) = (id[0], id[1], id[2], id[3])
  proc actor(name: string): Actor = s.actorFor(s.userByName(name))
  proc refusal(by: Actor, uid: int64): int =
    ## the HTTP status the server refuses with; 0 = it went through
    try:
      discard s.signOutUser(by, uid)
      0
    except HttpErr as e: e.code
  proc signIn(): seq[string] =
    for uid in [boss["id"].i, sara, omar, ali, tom]: result.add s.newSession(uid)
  proc stillOpen(raws: seq[string]): seq[bool] =
    for raw in raws: result.add s.sessionEnds(raw) > 0

  test "a member nobody's; an admin a user's; the manager an admin's; nobody the manager's here":
    let raws = signIn()
    for target in [boss["id"].i, sara, ali, tom]: check refusal(actor("ali"), target) == 403     # their own neither
    for target in [boss["id"].i, sara, omar]: check refusal(actor("sara"), target) == 403        # their own neither
    check refusal(mgr, boss["id"].i) == 403                 # (the manager's own: "my other sessions", which keeps one)
    check refusal(mgr, 99999) == 404
    check stillOpen(raws) == @[true, true, true, true, true]     # nobody was signed out by a refusal
    check s.signOutUser(actor("sara"), ali)["ended"].i == 1
    check stillOpen(raws) == @[true, true, true, false, true]
    check s.signOutUser(actor("sara"), ali)["ended"].i == 0
    check s.signOutUser(mgr, omar)["ended"].i == 1
    check s.signOutUser(mgr, tom)["ended"].i == 1
    check stillOpen(raws) == @[true, true, false, false, false]
    # the account is as it was: the password row and the key are untouched
    let u = s.userByName("ali")
    check u["active"].b and u["pw"].isStr and u["pw"].s.len > 0 and s.live(u)

  test "kks-server sign-out --user NAME: any account, the manager's too":
    for uid in [boss["id"].i, sara, omar, ali, tom]: s.endSessions(uid)     # (whatever the test above left)
    let raws = signIn()
    discard s.newSession(tom)
    expect ValueError: discard s.control("sign-out", @[])
    expect ValueError: discard s.control("sign-out", @["nobody-here"])
    check s.control("sign-out", @["TOM"]).startsWith("Ended 2 web sign-ins of tom.")
    check s.control("sign-out", @["tom"]).startsWith("tom was not signed in on the web.")
    check s.control("sign-out", @["boss"]).startsWith("Ended 1 web sign-in of boss.")
    check stillOpen(raws) == @[false, true, true, true, false]
    check s.sessionUser(raws[1]) != nil and s.sessionUser(raws[0]) == nil

  test "my other sessions: only with the account's password, checked and counted as Change password does":
    for uid in [boss["id"].i, sara, omar, ali, tom]: s.endSessions(uid)     # (whatever the tests above left)
    let u = s.userByName("tom")
    let salt = repeat("ab", 8)
    u["pw"] = S(hashPassword("a long password", salt))     # (the accounts above have no real hash)
    s.putUser(u)
    let here = s.newSession(tom)
    let phone = s.newSession(tom)
    let thief = s.newSession(tom)
    let others = signIn()
    proc ask(password: JNode, keep: string, source: string): int =
      ## the HTTP status the server refuses with; 0 = it went through
      try:
        discard s.signOutOthers(u, password, keep, [source])
        0
      except HttpErr as e: e.code
    # no password, one that is no string, a wrong one, another account's: refused, and nobody is signed out
    check ask(nil, thief, "ip:192.0.2.1") == 401
    check ask(newInt(1), thief, "ip:192.0.2.1") == 401
    check ask(S(""), thief, "ip:192.0.2.1") == 401
    check ask(S("not the password"), thief, "ip:192.0.2.1") == 401
    check s.openSessions(tom) == 4
    check stillOpen(@[here, phone, thief]) == @[true, true, true]
    # each of those counted as a failed sign-in from there: after the fifth, also the right password waits
    check ask(S("still not the password"), thief, "ip:192.0.2.1") == 401
    check ask(S("a long password"), thief, "ip:192.0.2.1") == 429
    check s.openSessions(tom) == 4
    # ... and a sign-in with the right password from there waits too (one count, the one `login` keeps)
    try:
      discard s.login("tom", "a long password", ["ip:192.0.2.1"])
      check false
    except HttpErr as e: check e.code == 429
    # from where nothing failed, with the password: the others end, the one that asks stays, nobody else's ends
    check s.signOutOthers(u, S("a long password"), here, ["ip:192.0.2.2"]) == 3
    check stillOpen(@[here, phone, thief]) == @[true, false, false]
    check stillOpen(others) == @[true, true, true, true, false]
    check s.signOutOthers(u, S("a long password"), here, ["ip:192.0.2.2"]) == 0      # none: said as none
    # with no other session there the check is the same: refused and counted
    for i in 1 .. 5: check ask(S("not the password"), here, "ip:192.0.2.3") == 401
    check ask(S("a long password"), here, "ip:192.0.2.3") == 429
    check s.sessionEnds(here) > 0

  test "a device of one's own is removed from a web sign-in only with the password; somebody else's by the role rules":
    for uid in [boss["id"].i, sara, omar, ali, tom]: s.endSessions(uid)
    let u = s.userByName("tom")           # (has a real hash since the test above)
    proc phone(owner: JNode): string =
      result = P.peerId(P.p256Generate())
      discard s.n.appendAs(mgr.key, "device_cert", deviceCertBody(result, owner["person"].s, "phone"), int64(epochTime() * 1000))
    let mine = phone(u)
    let alis = phone(s.userByName("ali"))
    proc ask(usr: JNode, dev: string, password: JNode, source: string): int =
      ## the HTTP status the check refuses with; 0 = it lets the request on to the core's rules
      var d = newObj(@[("device", newStr(dev))])
      if password != nil: d = newObj(@[("device", newStr(dev)), ("password", password)])
      try:
        s.ownDevicePassword(usr, s.actorFor(usr), d, [source])
        0
      except HttpErr as e: e.code
    check mine in s.n.run.devices and alis in s.n.run.devices
    # one's own: no password, not a string, empty, wrong
    check ask(u, mine, nil, "ip:192.0.2.11") == 401
    check ask(u, mine, newInt(1), "ip:192.0.2.11") == 401
    check ask(u, mine, S(""), "ip:192.0.2.11") == 401
    check ask(u, mine, S("not the password"), "ip:192.0.2.11") == 401
    # counted as failed sign-ins from there: after the fifth the right password waits
    check ask(u, mine, S("still not the password"), "ip:192.0.2.11") == 401
    check ask(u, mine, S("a long password"), "ip:192.0.2.11") == 429
    check ask(u, mine, S("a long password"), "ip:192.0.2.12") == 0
    # somebody else's device, one nobody has, no device named: no password is asked for (the core's rules decide)
    check ask(u, alis, nil, "ip:192.0.2.11") == 0
    check ask(boss, alis, nil, "ip:192.0.2.11") == 0
    check ask(boss, mine, nil, "ip:192.0.2.11") == 0
    check ask(u, "no-such-device", nil, "ip:192.0.2.11") == 0
    check (try: (s.ownDevicePassword(u, actor("tom"), newObj(), ["ip:192.0.2.11"]); true) except HttpErr: false)
    check (try: (s.ownDevicePassword(u, actor("tom"), newObj(@[("device", newInt(7))]), ["ip:192.0.2.11"]); true) except HttpErr: false)

  test "a device for one's own person is added from a web sign-in only with the password; somebody else's by the role rules":
    for uid in [boss["id"].i, sara, omar, ali, tom]: s.endSessions(uid)
    let su = s.userByName("sara")         # an admin: may certify devices (the core's rule)
    su["pw"] = S(hashPassword("sara's long password", repeat("cd", 8)))
    s.putUser(su)
    proc request(username: string): (string, JNode) =
      let k = P.p256Generate()
      (P.peerId(k), P.joinRequest(k, username, username & " person", S("Operator"), "laptop", int64(epochTime())))
    proc ask(usr: JNode, path: string, d: JNode, source: string): int =
      ## the HTTP status the check refuses with; 0 = it lets the request on to the core's rules
      try:
        s.ownCertifyPassword(usr, s.actorFor(usr), path, d, [source])
        0
      except HttpErr as e: e.code
    proc O(f: varargs[(string, JNode)]): JNode = newObj(@f)
    let now = int64(epochTime())
    # "Add a computer from a join request" naming the person asking (in any case of the username), with existing_ok
    # or without: no password, not a string, empty, wrong, another account's
    let (_, own) = request("SARA")
    for (i, pw) in [nil, newInt(1), S(""), S("not the password"), S("a long password")].pairs:
      var d = O(("request", own), ("existing_ok", newBool(i mod 2 == 0)))
      if pw != nil: d["password"] = pw
      check ask(su, "/api/devices/import-request", d, "ip:192.0.2.21") == 401
    # counted as failed sign-ins from there: after the fifth the right password waits; from elsewhere it goes on
    let right = O(("request", own), ("existing_ok", newBool(true)), ("password", S("sara's long password")))
    check ask(su, "/api/devices/import-request", right, "ip:192.0.2.21") == 429
    check ask(su, "/api/devices/import-request", right, "ip:192.0.2.22") == 0
    # a QR invite and a device waiting on the Wi-Fi: "accept" for one's own person asks for it too; refusing does not
    let inv = s.api.invites.create(P, actor("sara").person, s.n.root, "plant", s.n.device, @["127.0.0.1:1"], now)
    let (dev, viaInvite) = request("sara")
    check s.api.invites.offer(P, dev, O(("token", inv["token"]), ("request", viaInvite)), now)["state"].s == "waiting"
    let (ldev, inLobby) = request("sara")
    check s.api.invites.offer(P, ldev, O(("request", inLobby)), now)["state"].s == "waiting"
    for path in ["/api/invites/" & inv["token"].s, "/api/join-requests/" & ldev]:
      check ask(su, path, O(("action", S("accept")), ("existing_ok", newBool(true))), "ip:192.0.2.23") == 401
      check ask(su, path, O(("action", S("accept")), ("password", S("wrong"))), "ip:192.0.2.24") == 401
      check ask(su, path, O(("action", S("accept")), ("password", S("sara's long password"))), "ip:192.0.2.25") == 0
      check ask(su, path, O(("action", S("refuse"))), "ip:192.0.2.26") == 0
      check ask(su, path, O(("action", S("cancel"))), "ip:192.0.2.26") == 0
      check ask(su, path, newObj(), "ip:192.0.2.26") == 0
    # nothing waiting under that token or device: nothing asked (the core says it is not waiting)
    check ask(su, "/api/invites/no-such-token", O(("action", S("accept"))), "ip:192.0.2.26") == 0
    check ask(su, "/api/join-requests/no-such-device", O(("action", S("accept"))), "ip:192.0.2.26") == 0
    # somebody else's: a member's by an admin, an admin's by the manager, the manager's by an admin: no password
    # asked (the core's role rules decide); nor for a request with no username or no request
    check ask(su, "/api/devices/import-request", O(("request", request("ali")[1])), "ip:192.0.2.26") == 0
    check ask(boss, "/api/devices/import-request", O(("request", request("sara")[1])), "ip:192.0.2.26") == 0
    check ask(su, "/api/devices/import-request", O(("request", request("boss")[1])), "ip:192.0.2.26") == 0
    check ask(boss, "/api/invites/" & inv["token"].s, O(("action", S("accept"))), "ip:192.0.2.26") == 0
    check ask(su, "/api/devices/import-request", O(("request", O(("username", newInt(3))))), "ip:192.0.2.26") == 0
    check ask(su, "/api/devices/import-request", O(("request", S("sara"))), "ip:192.0.2.26") == 0
    check ask(su, "/api/devices/import-request", newObj(), "ip:192.0.2.26") == 0
    # the manager's own: the same
    check ask(boss, "/api/devices/import-request", O(("request", request("boss")[1])), "ip:192.0.2.27") == 401
    check ask(boss, "/api/devices/import-request", O(("request", request("boss")[1]), ("password", S("a long password"))), "ip:192.0.2.27") == 0
    # other routes: nothing asked
    check ask(su, "/api/devices/revoke", O(("request", own)), "ip:192.0.2.26") == 0
    check ask(su, "/api/invites", O(("request", own)), "ip:192.0.2.26") == 0
