## Sync through a relay pipe (PROTOCOL-v2 §18) against the Python relay twin (relay/twin.py):
## presence, connect with no candidates, the pipe, TLS + §15 inside it. Needs python3 with cryptography, or
## KKS_RELAY_URL (e.g. the Worker under `wrangler dev`).
import std/[unittest, asyncdispatch, os, osproc, strutils, sets, tables]
import kks/[json, util, crypto, proto, node, sync, plant]
import plat
import kksl/[net, internet, udp, ws, dbstore]
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
  let kC = P.p256Generate()
  discard a.append("device_cert", deviceCertBody(P.peerId(kC), me, "phone on mobile data"), nowMs())
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
    # C syncs on the LAN once (gets the first key), then is reachable only through the relay
    var c = newNode(P, newMemStore(), kC)
    c.adopt(a.root)
    let lstC = listen(a, newIdentity(kA), 0, "127.0.0.1")
    discard waitFor c.syncWith(newIdentity(kC), "127.0.0.1", lstC.port, a.device)
    check c.memberKey[0]
    let mk2 = P.p256Generate()
    a.keepMemberKey(mk2, nowMs())
    discard a.append("setting", newObj(@[("key", newStr("relay_member")), ("value", newStr(keyString(mk2.pub)))]), nowMs())
    discard waitFor ia.syncPeer(b.device)
    check b.memberKey[0] and keyString(b.memberKey[1].pub) == keyString(mk2.pub)
    let room2 = relayRoom(P, keyString(mk2.pub))
    check waitUntil(proc (): bool = ia.room == room2 and ib.room == room2 and ia.state == "online" and
                                    ib.state == "online" and a.device in ib.online and b.device in ia.online, 30_000)
    check (waitFor ib.syncPeer(a.device)).theyDenied == false
    # C still has only the old key: A (like the server) stays in the previous room for the grace period, so C can
    # sync there once, learn the new key and move
    check a.prevMemberKey(nowMs())[0] and not a.prevMemberKey(nowMs() + GraceMs + 1)[0]
    let iaPrev = newInternet(a, newIdentity(kA))
    iaPrev.keyOf = proc (): (bool, PrivateKey) = a.prevMemberKey(nowMs())
    iaPrev.stunServers = @[]
    iaPrev.start()
    let ic = newInternet(c, newIdentity(kC), relayOf = proc (): string = url)
    ic.stunServers = @[]
    ic.start()
    let room1 = relayRoom(P, keyString(mk.pub))
    check waitUntil(proc (): bool = ic.state == "online" and ic.room == room1 and a.device in ic.online, 20_000)
    discard waitFor ic.syncPeer(a.device)
    check c.memberKey[0] and keyString(c.memberKey[1].pub) == keyString(mk2.pub)
    check waitUntil(proc (): bool = ic.room == room2 and ic.state == "online" and a.device in ic.online, 30_000)
    ic.stop()
    iaPrev.stop()

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

  test "a read waiting on a direct stream ends when the stream stops (2026-10-09)":
    # the reader waits for a packet, an error or the stream stopping, with no timer per wait: once the stream has
    # stopped and its socket closed, a read gives "" (closed) instead of waiting for packets that can't come
    let a = newUdp()
    let b = newUdp()
    let session = "\x21\x22\x23\x24\x25\x26\x27\x28"
    let sa = a.rudpStream("127.0.0.1", b.port, session)
    let sb = b.rudpStream("127.0.0.1", a.port, session)
    waitFor sa.write("hello")
    check waitFor(sb.read()) == "hello"
    let pending = sb.read()
    a.close()                             # the other side is gone: sb's FIN is never acknowledged
    sb.close()                            # finishes after its FIN wait (3 s), then closes its socket
    check waitFor(withTimeout(pending, 10_000))
    if pending.finished and not pending.failed: check pending.read == ""
    check waitFor(withTimeout(sb.read(), 1000))   # and a read after that returns at once
    sa.close()                            # its socket is closed already: sending its FIN must not crash
    waitFor sleepAsync(4000)

  type DirectRun = object
    ok: bool
    live, heap: int            ## growth of the Nim heap's live bytes (after a full collection) and of the heap itself
    seconds: int

  proc directSync(nBlobs: int): DirectRun =
    ## a server sends a device `nBlobs` blobs of 1 MB over the direct stream; both keep them in SQLite (malloc), so
    ## what the Nim heap holds afterwards is what the sync left behind
    let rootKey = P.p256Generate()
    let kS = P.p256Generate()
    let dir = getTempDir() / "kks-direct-memory"
    removeDir(dir)
    createDir(dir)
    var srv = newNode(P, openDbStore(P, dir / "server.db", P.randomBytes(32)), kS)
    let boss = P.newPersonId()
    discard srv.append("genesis", P.genesisBody(rootKey, "Test plant", srv.device, boss, "boss", "The Manager"), nowMs())
    srv.adopt(keyString(rootKey.pub))
    var listed = newArr(@[newArr(@[newStr("sheets.json"), newStr(srv.keepBlob("[]")), newInt(2)])])
    for i in 0 ..< nBlobs:
      listed.elems.add newArr(@[newStr("sheets/s" & $i & ".jxl"), newStr(srv.keepBlob(P.randomBytes(1024 * 1024).toStr)),
                                newInt(1024 * 1024)])
    discard srv.append("setting", newObj(@[("key", newStr("plant_data")),
                                           ("value", newObj(@[("version", newInt(1)), ("files", listed)]))]), nowMs())
    let kD = P.p256Generate()
    discard srv.append("device_cert", deviceCertBody(P.peerId(kD), boss, "phone"), nowMs())
    var dev = newNode(P, openDbStore(P, dir / "device.db", P.randomBytes(32)), kD)
    GC_fullCollect()
    let heap0 = getTotalMem()
    let live0 = getOccupiedMem()
    let a = newUdp()
    let b = newUdp()
    let session = "\x11\x12\x13\x14\x15\x16\x17\x18"
    let served = serveOver(srv, newIdentity(kS), a.rudpStream("127.0.0.1", b.port, session))
    let t0 = epochTime()
    let synced = syncOver(dev, newIdentity(kD), b.rudpStream("127.0.0.1", a.port, session), srv.device,
                          adoptRoot = srv.root)
    check waitFor(withTimeout(synced, 120_000))     # before 2026-10-09: still copying after 9 minutes (24 MB)
    if synced.finished and not synced.failed:
      discard waitFor served
      check synced.read.blobsReceived == nBlobs + 1
      result.ok = synced.read.blobsReceived == nBlobs + 1    # the checks here are outside a test: the test checks `ok`
      result.seconds = int(epochTime() - t0)
    # both streams finish (FIN acknowledged, sockets closed) a few seconds after the sync, holding their buffers until
    # then: let them, so both runs are measured in the same state
    let t1 = epochTime()
    while epochTime() - t1 < 6.0:
      if hasPendingOperations(): poll(100) else: sleep(100)
    GC_fullCollect()
    result.live = getOccupiedMem() - live0
    result.heap = getTotalMem() - heap0
    DbStore(srv.store).close()           # Windows can't delete the folder of an open database (the next run's removeDir)
    DbStore(dev.store).close()
    echo "  ", nBlobs, " MB of blobs directly in ", result.seconds, " s: the Nim heap grew by ",
         result.heap div (1024 * 1024), " MB, its live bytes by ", result.live div 1024, " kB"

  test "a sync of many MB of blobs goes through the direct stream, in bounded memory (2026-10-09)":
    # The stream cut its queue after every packet and TLS its input after every record: copying the rest each time
    # stalled the loop on a few MB until the other side gave up ("the other device stopped answering").
    # What a sync leaves behind must not grow with the data: every read armed a 20 s timer (withTimeout) that stayed
    # in the dispatcher after the read, and the direct stream gives about a packet per read, so the live heap grew
    # by about a tenth of the bytes moved (7-9 MB more for 96 MB of blobs than for 16; 2026-10-09).
    let heap0 = getTotalMem()
    let small = directSync(16)
    let large = directSync(96)
    check small.ok and large.ok
    let more = (large.live - small.live) div 1024
    let heap = (getTotalMem() - heap0) div (1024 * 1024)
    echo "  the large sync left ", more, " kB more live than the small one; the heap grew by ", heap, " MB in all"
    # nothing that scales with the bytes: 80 MB more of blobs, under 2 MB more held (about 0.2 MB here: the device's
    # log lists 80 more files)
    check more < 2048
    # the peak, whatever the order of the runs: the stream's 4 MB back-pressure and both ends' buffers, 36-42 MB on
    # Linux; everything held at once was about ten times the bytes
    check heap < 64
