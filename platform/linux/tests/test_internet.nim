## Sync through a relay pipe (PROTOCOL-v2 §18) against the Python relay twin (relay/twin.py):
## presence, connect with no candidates, the pipe, TLS + §15 inside it. Needs python3 with cryptography, or
## KKS_RELAY_URL (e.g. the Worker under `wrangler dev`).
import std/[unittest, asyncdispatch, os, osproc, strutils, sets, tables]
import kks/[json, util, crypto, proto, node, sync, plant]
import plat
import kksl/[net, internet, udp, ws]
import kks/[extras, relaykey]
import std/times

let P = testProvider()
let repo = currentSourcePath().parentDir / ".." / ".." / ".."

proc waitUntil(cond: proc (): bool, ms = 10_000): bool =
  var t = 0
  while t < ms:
    if cond(): return true
    poll(50)
    t += 50
  cond()

suite "internet sync through the relay":
  # KKS_RELAY_URL=ws://127.0.0.1:8787 runs it against the real Worker under `wrangler dev` instead of the twin
  let external = getEnv("KKS_RELAY_URL")
  let py = if fileExists(repo / ".venv/bin/python"): repo / ".venv/bin/python" else: "python3"
  let port = 18000 + (getCurrentProcessId() mod 1000)
  let relayProc = if external.len > 0: nil
                  else: startProcess(py, repo, ["relay/twin.py", $port], options = {poStdErrToStdOut})
  if relayProc != nil: sleep(800)
  let url = if external.len > 0: external else: "ws://127.0.0.1:" & $port

  let rootKey = P.p256Generate()
  let kA = P.p256Generate()
  let kB = P.p256Generate()
  var a = newNode(P, newMemStore(), kA)
  let me = P.newPersonId()
  discard a.append("genesis", P.genesisBody(rootKey, "Test plant", a.device, me, "boss", "The Manager"), nowMs())
  a.adopt(keyString(rootKey.pub))
  discard a.append("device_cert", deviceCertBody(P.peerId(kB), me, "phone"), nowMs())
  discard a.append("setting", newObj(@[("key", newStr("relay")), ("value", newStr(url))]), nowMs())
  # the plant's relay room key (decision 0050), as /api/settings/relay makes it on the manager's device
  let mk = P.p256Generate()
  a.keepMemberKey(mk)
  discard a.append("setting", newObj(@[("key", newStr("relay_member")), ("value", newStr(keyString(mk.pub)))]), nowMs())
  var b = newNode(P, newMemStore(), kB)
  b.adopt(a.root)
  let ia = newInternet(a, newIdentity(kA))
  let ib = newInternet(b, newIdentity(kB), relayOf = proc (): string = url)
  ia.stunServers = @[]     # tests: this machine's own addresses only (no public STUN server)
  ib.stunServers = @[]

  test "without the plant's room key a device stays off the relay, and the relay refuses an old hello (0050)":
    ib.start()
    check waitUntil(proc (): bool = ib.state.startsWith("waiting for the plant's relay key"), 3000)
    let room = relayRoom(P, keyString(mk.pub))
    let w = waitFor wsConnect(url & "/v1/room/" & room)
    var old = relayHello(P, kB, mk, room, int64(epochTime()))
    old.fields = old.fields[0 ..< 5]                        # t, peer, key, ts, sig: a device before 0050
    waitFor w.sendText(toText(old))
    let f = w.recv()
    check waitFor(withTimeout(f, 5000))
    let m = parseStrict(f.read().data)
    check m["t"].s == "error" and "relay key" in m["why"].s
    w.close()
    let stranger = P.p256Generate()                          # its own key as the room key: another room's
    let w2 = waitFor wsConnect(url & "/v1/room/" & room)
    waitFor w2.sendText(toText(relayHello(P, stranger, stranger, room, int64(epochTime()))))
    let f2 = w2.recv()
    check waitFor(withTimeout(f2, 5000))
    check parseStrict(f2.read().data)["t"].s == "error"
    w2.close()

  test "the room key comes with a LAN sync, then both appear in the room and B pulls through the pipe":
    let lst = listen(a, newIdentity(kA), 0, "127.0.0.1")
    let first = waitFor b.syncWith(newIdentity(kB), "127.0.0.1", lst.port, a.device)
    check first.received == a.entries.len
    check b.memberKey[0] and keyString(b.memberKey[1].pub) == keyString(mk.pub)
    ia.start()
    check waitUntil(proc (): bool = ia.state == "online" and ib.state == "online" and a.device in ib.online, 20_000)
    checkpoint "presence: " & ia.state & " / " & ib.state
    discard a.append("setting", newObj(@[("key", newStr("note0")), ("value", newStr("through the relay"))]), nowMs())
    let st = waitFor ib.syncPeer(a.device)
    check st.received == 1
    check relaySetting(b) == url

  test "a change travels the other way":
    discard b.append("setting", newObj(@[("key", newStr("note")), ("value", newStr("from b"))]), nowMs())
    let st = waitFor ia.syncPeer(b.device)
    check st.received == 1
    check a.entries.len == b.entries.len

  test "both offer candidates: the sync goes direct (hole punching + reliable UDP)":
    discard b.append("setting", newObj(@[("key", newStr("note2")), ("value", newStr("direct"))]), nowMs())
    let st = waitFor ia.syncPeer(b.device)
    check st.received == 1
    check ia.lastHow == "direct" and ib.lastHow == "direct"

  test "one side without direct connections: both use the relay pipe":
    ib.direct = false
    discard b.append("setting", newObj(@[("key", newStr("note3")), ("value", newStr("pipe"))]), nowMs())
    let st = waitFor ia.syncPeer(b.device)
    check st.received == 1
    check ia.lastHow == "relay" and ib.lastHow == "relay"
    ib.direct = true

  test "a direct path that stalls after punching: the same sync falls back to the pipe, and the pipe is kept":
    ia.testStall = true
    discard b.append("setting", newObj(@[("key", newStr("note4")), ("value", newStr("stalled"))]), nowMs())
    let st = waitFor ia.syncPeer(b.device)
    check st.received == 1
    check ia.lastHow == "relay"
    check b.device in ia.noDirectUntil
    ia.testStall = false
    discard b.append("setting", newObj(@[("key", newStr("note5")), ("value", newStr("still pipe"))]), nowMs())
    check (waitFor ia.syncPeer(b.device)).received == 1
    check ia.lastHow == "relay"           # within the hour: no new direct attempt
    ia.noDirectUntil.clear()

  test "a punch that hears nothing: the pipe at once, and no punching with that device for an hour":
    ia.testNoPath = true
    discard b.append("setting", newObj(@[("key", newStr("note6")), ("value", newStr("no path"))]), nowMs())
    check (waitFor ia.syncPeer(b.device)).received == 1
    check ia.lastHow == "relay"
    check b.device in ia.noDirectUntil
    ia.testNoPath = false
    discard b.append("setting", newObj(@[("key", newStr("note7")), ("value", newStr("skip"))]), nowMs())
    check (waitFor ia.syncPeer(b.device)).received == 1
    check ia.lastHow == "relay" and ib.lastHow == "relay"   # neither side offered candidates: no 4 s punch
    ia.noDirectUntil.clear()
    ib.noDirectUntil.clear()

  test "a device answering MaxServed syncs through the relay refuses more (issue #67)":
    ib.serving = MaxServed
    try:
      expect NetError:
        discard waitFor ia.syncPeer(b.device)
    finally: ib.serving = 0
    check (waitFor ia.syncPeer(b.device)).theyDenied == false   # and answers again once one ends

  test "an absent device is reported":
    expect NetError:
      discard waitFor ia.syncPeer(P.peerId(P.p256Generate()))

  test "a replayed hello doesn't knock the device off the relay (issue #44)":
    let kX = P.p256Generate()
    let room = relayRoom(P, keyString(mk.pub))
    let now = int64(epochTime())
    proc first(w: Ws): JNode =
      let f = w.recv()
      check waitFor(withTimeout(f, 5000))
      parseStrict(f.read().data)
    let h = toText(relayHello(P, kX, mk, room, now))
    let w1 = waitFor wsConnect(url & "/v1/room/" & room)
    waitFor w1.sendText(h)
    check w1.first()["t"].s == "welcome"
    # the same signature with s -> n - s (still valid) and spelled with a different last base64 character's spare bits
    let hj = parseStrict(h)
    var sig = unb64u(hj["sig"].s)
    const n = [0xff'u8, 0xff, 0xff, 0xff, 0, 0, 0, 0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
               0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51]
    var borrow = 0
    for i in countdown(31, 0):
      var d = int(n[i]) - int(sig[32 + i]) - borrow
      borrow = (if d < 0: 1 else: 0)
      sig[32 + i] = byte((d + 256) mod 256)
    let flipped = hj.copy
    flipped["sig"] = newStr(b64u(sig))
    for replay in [h, toText(flipped), toText(relayHello(P, kX, mk, room, now - 10))]:   # again; malleated; older
      let w2 = waitFor wsConnect(url & "/v1/room/" & room)
      waitFor w2.sendText(replay)
      let m = w2.first()
      check m["t"].s == "error" and m["why"].s == "replayed hello"
      w2.close()
    waitFor w1.sendText("""{"t":"ping"}""")
    check w1.first()["t"].s == "pong"                          # still there
    let w3 = waitFor wsConnect(url & "/v1/room/" & room)         # a fresh hello replaces it, as before
    waitFor w3.sendText(toText(relayHello(P, kX, mk, room, now)))
    check w3.first()["t"].s == "welcome"
    w1.close()
    w3.close()

  test "a rotated room key reaches B with a sync, and both move to the new room (0050)":
    let mk2 = P.p256Generate()
    a.keepMemberKey(mk2)
    discard a.append("setting", newObj(@[("key", newStr("relay_member")), ("value", newStr(keyString(mk2.pub)))]), nowMs())
    discard waitFor ia.syncPeer(b.device)
    check b.memberKey[0] and keyString(b.memberKey[1].pub) == keyString(mk2.pub)
    let room2 = relayRoom(P, keyString(mk2.pub))
    check waitUntil(proc (): bool = ia.room == room2 and ib.room == room2 and ia.state == "online" and
                                    ib.state == "online" and a.device in ib.online and b.device in ia.online, 30_000)
    check (waitFor ib.syncPeer(a.device)).theyDenied == false

  test "leaving is seen":
    ib.stop()
    check waitUntil(proc (): bool = b.device notin ia.online)
    ia.stop()

  if relayProc != nil:
    relayProc.terminate()
    discard relayProc.waitForExit()
    relayProc.close()

suite "the direct stream":
  test "follows the other side when its address changes after punching":
    # B's NAT gives the stream another port than the one A punched (a mapping per destination, a rebinding): A's
    # stream must move to where B's packets come from, or nothing B sends is answered
    let a = newUdp()
    let b = newUdp()
    let dead = newUdp()                 # the address A punched: nothing there answers
    let session = "\x01\x02\x03\x04\x05\x06\x07\x08"
    let sa = a.rudpStream("127.0.0.1", dead.port, session)
    let sb = b.rudpStream("127.0.0.1", a.port, session)
    waitFor sb.write("hello from b")
    check waitFor(sa.read()) == "hello from b"
    waitFor sa.write("hello back")
    var got = ""
    let f = sb.read()
    check waitFor(withTimeout(f, 5000))
    if f.finished: got = f.read()
    check got == "hello back"
    sa.close()
    sb.close()
    dead.close()
