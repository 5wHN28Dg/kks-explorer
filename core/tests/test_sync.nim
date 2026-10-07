import std/[unittest, tables, strutils, times]
import kks/[json, util, crypto, proto, replay, node, sync, plant]
import testprovider

let P = testProvider()
var wall = 1_790_000_000_000'i64
proc tick(): int64 =
  wall += 1000
  wall

proc pump(a, b: Session) =
  ## Carry messages both ways through real framing until both are done (or one fails).
  var da, db: Deframer
  var guard = 0
  while not (a.done and b.done):
    inc guard
    if guard > 10000: raise newException(SyncError, "no progress")
    var moved = false
    while a.outbox.len > 0:
      let m = a.outbox[0]
      a.outbox.delete(0)
      for x in db.feed(frame(m)): b.receive(x)
      moved = true
    while b.outbox.len > 0:
      let m = b.outbox[0]
      b.outbox.delete(0)
      for x in da.feed(frame(m)): a.receive(x)
      moved = true
    if not moved: break

proc sync(a, b: Node, adopt = ""): (Stats, Stats) =
  let s1 = newSession(a, true, b.device, adopt)
  let s2 = newSession(b, false, a.device)
  s1.wall = tick()
  s2.wall = s1.wall
  pump(s1, s2)
  check s1.done and s2.done
  (s1.stats, s2.stats)

suite "sync state machine":
  let rootKey = P.p256Generate()
  let rootStr = keyString(rootKey.pub)
  var mgrPhone = newNode(P, newMemStore(), P.p256Generate())
  let mgr = P.newPersonId()
  discard mgrPhone.append("genesis", P.genesisBody(rootKey, "Test plant", mgrPhone.device, mgr, "boss", "The Manager"), tick())
  mgrPhone.adopt(rootStr)

  test "genesis replays":
    check mgrPhone.run.manager == mgr
    check mgrPhone.mayRead(mgrPhone.device)

  var server = newNode(P, newMemStore(), P.p256Generate())
  test "a new device adopts the expected root and receives everything":
    discard mgrPhone.append("device_cert", deviceCertBody(server.device, mgr, "server"), tick())
    let (a, b) = sync(server, mgrPhone, adopt = rootStr)
    check server.root == rootStr
    check a.received == 2
    check stateBytes(server.run.state) == stateBytes(mgrPhone.run.state)

  test "a stranger gets nothing":
    var stranger = newNode(P, newMemStore(), P.p256Generate())
    stranger.adopt(rootStr)
    let (a, b) = sync(stranger, mgrPhone)
    check a.theyDenied and b.denied
    check stranger.entries.len == 0

  test "a different plant stops":
    var other = newNode(P, newMemStore(), P.p256Generate())
    other.adopt(keyString(P.p256Generate().pub))
    let s1 = newSession(other, true, mgrPhone.device)
    let s2 = newSession(mgrPhone, false, other.device)
    expect SyncError: pump(s1, s2)

  test "relay: entries travel through a third device, and a photo blob follows":
    let ali = P.newPersonId()
    var aliPhone = newNode(P, newMemStore(), P.p256Generate())
    discard mgrPhone.append("person", personBody(ali, "ali", "Ali Admin", "admin"), tick())
    discard mgrPhone.append("device_cert", deviceCertBody(aliPhone.device, ali, "phone"), tick())
    discard sync(mgrPhone, server)               # server holds the certs
    discard sync(aliPhone, server, adopt = rootStr)
    check aliPhone.mayRead(aliPhone.device)
    let photo = "\xff\x0afake jxl bytes"
    let sha = aliPhone.keepBlob(photo)
    discard aliPhone.append("photo", newObj(@[("photo", newStr(P.newPersonId())), ("kks", newStr("11LAB70AA501")),
                                              ("blob", newStr(sha)), ("caption", newStr("pump"))]), tick())
    let (a, b) = sync(aliPhone, server)
    check b.blobsReceived == 1
    let (c, d) = sync(mgrPhone, server)
    check c.received == 1 and c.blobsReceived == 1
    check mgrPhone.run.photos.len == 1
    check mgrPhone.store.blobGet(sha) == photo
    check stateBytes(mgrPhone.run.state) == stateBytes(aliPhone.run.state)

  test "a blob nobody references is refused":
    check not server.blobOffer(hex(P.sha256(toBytes("junk"))), "junk")

  test "a removed device is shown the revoke and wipes itself":
    let bob = P.newPersonId()
    var bobPhone = newNode(P, newMemStore(), P.p256Generate())
    discard mgrPhone.append("person", personBody(bob, "bob", "Bob User", "user"), tick())
    discard mgrPhone.append("device_cert", deviceCertBody(bobPhone.device, bob, "phone"), tick())
    discard sync(bobPhone, mgrPhone, adopt = rootStr)
    discard mgrPhone.append("revoke", revokeBody(bobPhone.device, int64(bobPhone.chainsLen)), tick())
    var wiped = false
    var who = ""
    let s1 = newSession(bobPhone, true, mgrPhone.device, hooks = Hooks(wipe: proc (by: string) =
      wiped = true
      who = by))
    let s2 = newSession(mgrPhone, false, bobPhone.device)
    expect SyncError: pump(s1, s2)
    check wiped
    check who.len > 0

  test "a forged revoke from a stranger is not believed":
    var stranger = P.p256Generate()
    let fake = P.makeEntry(stranger, 1, "", (tick(), 0'i64), "revoke", revokeBody(server.device, 0))
    check not server.acceptRevocation(fake)

  test "an admin's revoke is believed for a user's device, not for the manager's (#31)":
    let carol = P.newPersonId()
    let carolKey = P.p256Generate()
    var carolPhone = newNode(P, newMemStore(), carolKey)
    discard mgrPhone.append("person", personBody(carol, "carol", "Carol Admin", "admin"), tick())
    discard mgrPhone.append("device_cert", deviceCertBody(carolPhone.device, carol, "phone"), tick())
    var dave = P.newPersonId()
    var davePhone = newNode(P, newMemStore(), P.p256Generate())
    discard mgrPhone.append("person", personBody(dave, "dave", "Dave User", "user"), tick())
    discard mgrPhone.append("device_cert", deviceCertBody(davePhone.device, dave, "phone"), tick())
    discard sync(carolPhone, mgrPhone, adopt = rootStr)
    discard sync(davePhone, mgrPhone, adopt = rootStr)
    let againstMgr = P.makeEntry(carolKey, int64(carolPhone.chainsLen + 1), "", (tick(), 0'i64), "revoke",
                                 revokeBody(mgrPhone.device, int64(mgrPhone.chainsLen)))
    check not mgrPhone.acceptRevocation(againstMgr)
    let againstUser = P.makeEntry(carolKey, int64(carolPhone.chainsLen + 1), "", (tick(), 0'i64), "revoke",
                                  revokeBody(davePhone.device, int64(davePhone.chainsLen)))
    check davePhone.acceptRevocation(againstUser)

  test "fork evidence: two different entries for one (device, seq)":
    let cloneKey = P.p256Generate()
    var a1 = newNode(P, newMemStore(), cloneKey)
    var a2 = newNode(P, newMemStore(), cloneKey)    # the same key copied to a second device
    discard mgrPhone.append("device_cert", deviceCertBody(a1.device, mgr, "clone"), tick())
    discard sync(a1, mgrPhone, adopt = rootStr)
    discard sync(a2, mgrPhone, adopt = rootStr)
    discard a1.append("setting", newObj(@[("key", newStr("x")), ("value", newInt(1))]), tick())
    discard a2.append("setting", newObj(@[("key", newStr("x")), ("value", newInt(2))]), tick())
    discard sync(a1, mgrPhone)
    discard sync(a2, mgrPhone)
    check mgrPhone.evidence.len == 1
    discard sync(server, mgrPhone)
    check server.evidence.len == 1

  test "join and secrets connections reach their hooks":
    var asked = ""
    let hooks = Hooks(join: proc (remote: string, m: JNode): JNode =
                        asked = remote
                        newObj(@[("t", newStr("join_ack")), ("state", newStr("waiting"))]))
    let s = newSession(mgrPhone, false, "joinerpeer", hooks = hooks)
    s.receive(newObj(@[("t", newStr("join")), ("token", newNull()), ("request", newObj())]))
    check s.done and asked == "joinerpeer" and s.outbox[0]["state"].s == "waiting"
    let s2 = newSession(mgrPhone, false, "x")
    s2.receive(newObj(@[("t", newStr("secrets")), ("person", newStr("p")), ("secrets", newArr())]))
    check s2.outbox[0]["secrets"].len == 0

  test "framing refuses oversize and bad JSON":
    var d: Deframer
    expect SyncError: discard d.feed("\x7f\xff\xff\xff")
    var d2: Deframer
    expect SyncError: discard d2.feed("\x00\x00\x00\x02{]")
    var d3: Deframer
    check d3.feed("\x00\x00\x00\x09{\"t\":\"x").len == 0
    check d3.feed("\"}").len == 1

  test "a responder's frame limit follows trust (issue #67)":
    var d: Deframer
    d.add("\x00\x10\x00\x01")                       # 1 MiB + 1 announced
    expect SyncError: discard d.next(HelloFrame)
    var d2: Deframer
    d2.add("\x00\x10\x00\x01")
    check d2.next(MaxFrame) == nil                   # waits for the body under a larger limit
    # the stages: before the hello, after it as a stranger, after it as a device of the plant
    var stranger = newNode(P, newMemStore(), P.p256Generate())
    stranger.adopt(rootStr)
    let s = newSession(mgrPhone, false, stranger.device)
    check s.frameLimit == HelloFrame and not s.trusted
    s.receive(newObj(@[("t", newStr("hello")), ("v", newInt(2)), ("root", newStr(rootStr)), ("vv", newObj())]))
    check s.frameLimit == StrangerFrame and not s.trusted
    let s2 = newSession(mgrPhone, false, server.device)
    check s2.frameLimit == HelloFrame
    s2.receive(newObj(@[("t", newStr("hello")), ("v", newInt(2)), ("root", newStr(rootStr)), ("vv", newObj())]))
    check s2.frameLimit == MaxFrame and s2.trusted
    check newSession(stranger, true, mgrPhone.device).frameLimit == MaxFrame   # the initiator chose its peer

  test "a large batch from a stranger is handled in linear time (issue #67)":
    var junk: seq[JNode]
    for i in 0 ..< 20000: junk.add newObj(@[("peer", newStr("x" & $i)), ("seq", newInt(2))])
    let t0 = epochTime()
    check mgrPhone.ingest(junk, tick()) == 0
    check epochTime() - t0 < 2.0                    # the search per entry took about 14 s here
