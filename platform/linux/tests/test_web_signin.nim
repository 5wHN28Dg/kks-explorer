## A web sign-in for someone who joined with the app (their own devices, no account on the server): the account is
## made for the SAME person, by an admin's "Web sign-in" or by approving their sign-up request "as the same person".
## Here with real second nodes (an app's device that syncs with the server); the routes, the CLI and the refusals over
## HTTP are in e2e/test_server_http.py (WebSignIn).
import std/[unittest, os, tables, strutils, times]
import kks/[json, crypto, node, sync, api, extras, replay]
import plat
import kksl/server

let P = testProvider()
var clock = int64(epochTime() * 1000)   # the server writes with the real time: a device far behind it would not follow its clock (§5)
proc now(): int64 =
  clock += 1000
  clock

proc open(name: string): Server =
  let dir = getTempDir() / "kks-web-signin-test"
  createDir(dir)
  var cfg = defaultConfig()
  cfg.storePath = dir / name
  removeFile(cfg.storePath)
  openServer(cfg, P, P.randomBytes(32))

proc pump(a, b: Session) =
  while not (a.done and b.done):
    var moved = false
    while a.sending:
      for m in a.take(): b.receive(m); moved = true
    while b.sending:
      for m in b.take(): a.receive(m); moved = true
    if not moved: break

proc sync(a, b: Node, adopt = "") =
  let s1 = newSession(a, true, b.device, adopt)
  let s2 = newSession(b, false, a.device)
  s1.wall = now(); s2.wall = s1.wall
  pump(s1, s2)

proc S(x: string): JNode = newStr(x)
proc O(fields: varargs[(string, JNode)]): JNode = newObj(@fields)
let NoQuery = initTable[string, string]()

proc refusal(body: proc ()): int =
  ## the HTTP status the server refuses with; 0 = it went through
  try:
    body()
    0
  except HttpErr as e: e.code

type App = object
  n: Node
  a: Api
  person: string

proc join(s: Server, by: Actor, username, fullName: string): App =
  ## someone joins with the app: a device of their own, certified from its join request, synced with the server
  result.n = newNode(P, newMemStore(), P.p256Generate())
  result.a = newApi(result.n)
  let req = P.joinRequest(result.n.key, username, fullName, S("Technician"), "phone", now() div 1000)
  let r = s.api.handle(by, "POST", "/api/devices/import-request", NoQuery, O(("request", req)), now())
  doAssert r.status == 200, $r.status
  result.person = r.json["person"].s
  sync(result.n, s.n, adopt = s.n.root)
  doAssert result.a.owner[0]

proc row(s: Server, username: string): JNode =
  for u in s.usersOut(showHidden = true).elems:
    if u["username"].s == username:
      doAssert result == nil, "two rows for " & username
      result = u

proc mineOf(a: Api, me: Actor): seq[JNode] =
  var q = NoQuery
  q["mine"] = "1"
  q["status"] = "all"
  for x in a.handle(me, "GET", "/api/submissions", q, nil, now()).json["submissions"].elems:
    if x["mine"].b: result.add x

proc devicesOf(r: Run, pid: string): seq[string] =
  for d, v in r.devices:
    if v["person"].s == pid and d notin r.cuts: result.add d

suite "web sign-in for a person who joined with the app":
  let s = open("link.db")
  let boss = s.createPlant("boss", "The Manager", S("Plant manager"), "a long password")
  let mgr = s.actorFor(boss)
  let ali = s.join(mgr, "ali", "Ali User")
  # what ali did on the phone before having a web sign-in
  let sub = ali.a.handle(ali.a.owner[1], "POST", "/api/submit", NoQuery, parseStrict(
    """{"kind":"equipment","payload":{"kks":"11LAB70AA501","changes":{"notes":"leaks"}},"client_id":"phone-0001"}"""), now())
  doAssert sub.status == 200
  sync(ali.n, s.n)

  test "the admin's Web sign-in: an account for the same person, a password link, and only once":
    check s.row("ali")["no_account"].b
    let persons = s.n.run.persons.len
    let r = s.webSignIn(mgr, ali.person)
    check r["username"].s == "ali" and "/#reset=" in r["link"].s and r["expires_days"].i == 3
    check s.n.run.persons.len == persons                          # no second person
    let u = s.userByName("ali")
    check u["person"].s == ali.person and u["full_name"].s == "Ali User" and u["position"].s == "Technician"
    check u["pw"].isNull                                           # nobody can sign in before the link is used
    check s.n.run.devices[u["device"].s]["person"].s == ali.person and s.n.run.devices[u["device"].s]["label"].s == "server"
    let shown = s.row("ali")                                        # one row, a normal account's
    check shown.get("no_account") == nil and shown["id"].i == u["id"].i and shown["active"].b and shown["role"].s == "user"
    # two admins clicking at once: the second is told, and nothing is made twice
    let devs = s.n.run.devices.len
    check refusal(proc () = discard s.webSignIn(mgr, ali.person)) == 409
    check s.n.run.devices.len == devs
    var n = 0
    for x in s.usersOut(showHidden = true).elems:
      if x["person"].s == ali.person: inc n
    check n == 1

  test "on the web they are that person: what the phone sent is theirs, and the phone agrees":
    let web = s.actorFor(s.userByName("ali"))
    check web.person == ali.person and web.role == "user"
    let mine = s.api.mineOf(web)
    check mine.len == 1 and mine[0]["kind"].s == "equipment" and mine[0]["payload"]["kks"].s == "11LAB70AA501"
    let r = s.api.handle(web, "POST", "/api/submit", NoQuery, parseStrict(
      """{"kind":"equipment","payload":{"kks":"11LAB70AA502","changes":{"notes":"from the web"}},"client_id":"web-00001"}"""), now())
    check r.status == 200
    sync(ali.n, s.n)
    let (ok, me) = ali.a.owner
    check ok                                                        # the phone is still certified
    check ali.a.mineOf(me).len == 2                                 # and sees the web's change as its person's own
    # the server's key for them is a second device of theirs on the phone, not a stranger's
    let d = ali.a.handle(me, "GET", "/api/devices", NoQuery, nil, now()).json["mine"]
    check d.len == 2
    var labels: seq[string]
    for x in d.elems:
      check not x["revoked"].b
      labels.add x["label"].s
    check "server" in labels and "phone" in labels
    for _, why in ali.n.run.ignored: check why != "not_certified"

  test "who may: an admin only for users, the manager for admins, nobody for the manager":
    let dana = s.join(mgr, "dana", "Dana Admin")
    check s.api.handle(mgr, "POST", "/api/persons/" & dana.person, NoQuery, O(("role", S("admin"))), now()).status == 200
    let omar = s.join(mgr, "omar", "Omar User")
    let adm = s.actorFor(s.createAccount(mgr, "adm", "An Admin", S("Engineer"), "admin"))
    let usr = s.actorFor(s.userByName("ali"))
    check refusal(proc () = discard s.webSignIn(usr, omar.person)) == 403          # not an admin
    check refusal(proc () = discard s.webSignIn(adm, dana.person)) == 403          # an admin's web sign-in: the manager's to give
    check refusal(proc () = discard s.webSignIn(adm, boss["person"].s)) == 403     # never the manager's person
    check refusal(proc () = discard s.webSignIn(mgr, boss["person"].s)) == 403
    check refusal(proc () = discard s.webSignIn(mgr, "0".repeat(32))) == 404
    check s.userByName("dana") == nil and s.userByName("omar") == nil
    check refusal(proc () = discard s.webSignIn(adm, omar.person)) == 0             # an admin, for a user
    check s.n.run.devices[s.userByName("omar")["device"].s]["person"].s == omar.person
    check refusal(proc () = discard s.webSignIn(mgr, dana.person)) == 0             # the manager, for an admin
    check s.row("dana")["role"].s == "admin" and s.actorFor(s.userByName("dana")).role == "admin"
    sync(omar.n, s.n)
    check omar.a.owner[0]                                           # certified by an admin's key: the app accepts it

  test "Remove devices and Deactivate do the same to someone with both; Activate brings the web sign-in back":
    var u = s.userByName("ali")
    u["pw"] = S("x")                                                # (a password, so a session can exist)
    discard s.updateUser(mgr, u["id"].i, O(("full_name", S("Ali User"))), false)
    let raw = s.newSession(u["id"].i)
    # Remove devices (what an admin's app does, or POST /api/persons/<id>): the phone and the server's key
    check s.n.run.devicesOf(ali.person).len == 2
    check s.api.handle(mgr, "POST", "/api/persons/" & ali.person, NoQuery, O(("active", newBool(false))), now()).status == 200
    check s.n.run.devicesOf(ali.person).len == 0
    u = s.userByName("ali")
    check not s.live(u) and not s.row("ali")["active"].b            # shown as deactivated
    check s.sessionUser(raw) == nil                                 # and the web session is over
    # Activate: a new key on the server; the phone stays removed until it joins again
    check s.updateUser(mgr, u["id"].i, O(("active", newBool(true))), false)["ok"].b
    u = s.userByName("ali")
    check s.live(u) and s.row("ali")["active"].b and s.n.run.devicesOf(ali.person) == @[u["device"].s]
    # Deactivate, for someone with a phone and a web sign-in: every device of theirs, as Remove devices
    let eva = s.join(mgr, "eva", "Eva User")
    discard s.webSignIn(mgr, eva.person)
    check s.n.run.devicesOf(eva.person).len == 2
    check s.updateUser(mgr, s.userByName("eva")["id"].i, O(("active", newBool(false))), false)["ok"].b
    check s.n.run.devicesOf(eva.person).len == 0 and eva.n.device in s.n.run.cuts
    check not s.live(s.userByName("eva")) and not s.row("eva")["active"].b

  test "someone whose devices were all removed can be given a web sign-in":
    let sam = s.join(mgr, "sam", "Sam User")
    check s.api.handle(mgr, "POST", "/api/persons/" & sam.person, NoQuery, O(("active", newBool(false))), now()).status == 200
    check not s.row("sam")["active"].b and s.row("sam")["no_account"].b
    discard s.webSignIn(mgr, sam.person)
    check s.row("sam")["active"].b and s.n.run.devicesOf(sam.person) == @[s.userByName("sam")["device"].s]
    check sam.n.device in s.n.run.cuts                              # the phone stays removed

  test "a sign-up request under their username: told who that is, linked only on the admin's word":
    let kim = s.join(mgr, "Kim", "Kim Field")
    let lee = s.join(mgr, "lee", "Lee Admin")
    check s.api.handle(mgr, "POST", "/api/persons/" & lee.person, NoQuery, O(("role", S("admin"))), now()).status == 200
    s.setSignupCode("plant-code-1")
    proc ask(username: string, source: string) =
      s.requestAccount(O(("code", S("plant-code-1")), ("username", S(username)), ("full_name", S("K. Field")),
                         ("position", S("Operator")), ("password", S("the password kim chose"))), [source])
    ask("kim", "ip:10.0.0.1")           # another spelling of Kim: usernames are one ignoring case
    ask("lee", "ip:10.0.0.2")
    ask("ali", "ip:10.0.0.3")           # ali has an account by now
    ask("nobody", "ip:10.0.0.4")
    var reqs: Table[string, JNode]
    for r in s.signupsOut()["requests"].elems: reqs[r["username"].s] = r
    let p = reqs["kim"]["person"]
    check reqs["kim"]["taken"].b and p["person"].s == kim.person and p["username"].s == "Kim" and
          p["full_name"].s == "Kim Field" and p["position"].s == "Technician" and p["role"].s == "user" and
          p["devices"].i == 1 and p["removed"].i == 0
    check reqs["lee"]["person"]["role"].s == "admin"
    check reqs["ali"]["taken"].b and reqs["ali"]["person"].isNull     # an account has the name: nothing to link
    check not reqs["nobody"]["taken"].b and reqs["nobody"]["person"].isNull
    check "pw" notin toText(s.signupsOut()) and "the password" notin toText(s.signupsOut())
    let adm = s.actorFor(s.userByName("adm"))
    let kimReq = reqs["kim"]["id"].s
    # never by itself: plain approval is refused as before, and no account appears
    check refusal(proc () = discard s.decideSignup(adm, kimReq, "approve", newObj())) == 409
    check s.userByName("Kim") == nil and s.userByName("kim") == nil
    # the person must be the one the request names
    check refusal(proc () = discard s.decideSignup(adm, kimReq, "approve", O(("person", S(lee.person))))) == 409
    check refusal(proc () = discard s.decideSignup(adm, kimReq, "approve", O(("person", S(ali.person))))) == 409
    check refusal(proc () = discard s.decideSignup(adm, kimReq, "approve", O(("person", S(kim.person)), ("username", S("kim2"))))) == 400
    check refusal(proc () = discard s.decideSignup(adm, reqs["ali"]["id"].s, "approve", O(("person", S(ali.person))))) == 409
    check refusal(proc () = discard s.decideSignup(adm, reqs["nobody"]["id"].s, "approve", O(("person", S(kim.person))))) == 409
    # an admin's identity: only the manager hands it out
    check refusal(proc () = discard s.decideSignup(adm, reqs["lee"]["id"].s, "approve", O(("person", S(lee.person))))) == 403
    check s.signupRequests().len == 4 and s.userByName("lee") == nil
    # approved as the same person: their account, their spelling of the name, the password the request chose
    let persons = s.n.run.persons.len
    let r = s.decideSignup(adm, kimReq, "approve", O(("person", S(kim.person))))
    check r["username"].s == "Kim" and s.n.run.persons.len == persons and s.signupRequests().len == 3
    let u = s.login("Kim", "the password kim chose", ["ip:10.0.0.1"])
    check u["person"].s == kim.person and s.actorFor(u).person == kim.person
    check s.row("Kim").get("no_account") == nil and s.row("Kim")["full_name"].s == "Kim Field"   # the person's name, not the request's
    check refusal(proc () = discard s.decideSignup(mgr, reqs["lee"]["id"].s, "approve", O(("person", S(lee.person))))) == 0
    check s.actorFor(s.login("lee", "the password kim chose", ["ip:10.0.0.2"])).role == "admin"
    sync(kim.n, s.n)
    check kim.a.owner[0]
