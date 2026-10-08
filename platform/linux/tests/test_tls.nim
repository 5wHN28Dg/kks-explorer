import std/[unittest, strutils, tables]
import kks/[json, util, crypto, proto, node, sync, plant]
import plat


let P = testProvider()

proc wire(a, b: TlsConn) =
  ## Move ciphertext both ways until nothing moves.
  for _ in 0 ..< 100:
    let x = a.takeOut()
    let y = b.takeOut()
    if x.len == 0 and y.len == 0: break
    b.feed(x)
    a.feed(y)
    discard a.handshake()
    discard b.handshake()

suite "TLS through buffers, pinned device keys":
  let ka = P.p256Generate()
  let kb = P.p256Generate()
  let ida = newIdentity(ka)
  let idb = newIdentity(kb)

  test "mutual handshake reports both peer IDs; data both ways":
    let c = newTlsConn(P, ida, client = true, expectPeer = P.peerId(kb))
    let s = newTlsConn(P, idb, client = false)
    discard c.handshake()
    wire(c, s)
    check c.handshaken and s.handshaken
    check c.remotePeer == P.peerId(kb)
    check s.remotePeer == P.peerId(ka)
    when defined(windows): echo "    negotiated TLS ", c.version     # 1.2 on Windows 10, 1.3 on 11 (decision 0033)
    c.send(frame(newObj(@[("t", newStr("hello"))])))
    s.feed(c.takeOut())
    var d: Deframer
    let got = d.feed(s.recv())
    check got.len == 1 and got[0]["t"].s == "hello"
    let big = "x".repeat(200_000)
    s.send(big)
    c.feed(s.takeOut())
    check c.recv() == big
    c.close()
    s.close()

  test "a client expecting another device refuses":
    let c = newTlsConn(P, ida, client = true, expectPeer = P.peerId(P.p256Generate()))
    let s = newTlsConn(P, idb, client = false)
    discard c.handshake()
    expect TlsError: wire(c, s)

  when defined(windows):
    test "TLS 1.2 (Windows 10) negotiates AEAD with ECDHE; a peer offering only AES-CBC is refused (#41)":
      tlsTestMode(1)
      let ka2 = P.p256Generate()
      let kb2 = P.p256Generate()
      let ia = newIdentity(ka2)
      let ib = newIdentity(kb2)
      let c = newTlsConn(P, ia, client = true, expectPeer = P.peerId(kb2))
      let s = newTlsConn(P, ib, client = false)
      discard c.handshake()
      wire(c, s)
      check c.handshaken and s.handshaken
      check c.version == "1.2"
      echo "    TLS 1.2 cipher suite: ", c.cipher
      check c.cipher.startsWith("TLS_ECDHE_")
      check "_GCM_" in c.cipher
      check s.cipher == c.cipher
      c.close()
      s.close()
      tlsTestMode(2)                   # the client offers AES-CBC suites alone; our server has none of them
      let ic = newIdentity(P.p256Generate())
      tlsTestMode(0)
      let c2 = newTlsConn(P, ic, client = true, expectPeer = P.peerId(kb2))
      let s2 = newTlsConn(P, ib, client = false)
      expect TlsError:
        discard c2.handshake()
        wire(c2, s2)
      check not s2.handshaken
      ia.free(); ib.free(); ic.free()

  test "a whole sync runs over it":
    let rootKey = P.p256Generate()
    var a = newNode(P, newMemStore(), ka)
    let me = P.newPersonId()
    discard a.append("genesis", P.genesisBody(rootKey, "Test plant", a.device, me, "boss", "The Manager"), 1_790_000_000_000)
    a.adopt(keyString(rootKey.pub))
    discard a.append("device_cert", deviceCertBody(P.peerId(kb), me, "laptop"), 1_790_000_001_000)
    var b = newNode(P, newMemStore(), kb)
    let c = newTlsConn(P, ida, client = false)           # a answers
    let t = newTlsConn(P, idb, client = true, expectPeer = a.device)
    discard t.handshake()
    wire(t, c)
    let si = newSession(b, true, t.remotePeer, adoptRoot = a.root)
    let sr = newSession(a, false, c.remotePeer)
    var di, dr: Deframer
    for _ in 0 ..< 50:
      for m in si.outbox: t.send(frame(m))
      si.outbox.setLen(0)
      c.feed(t.takeOut())
      for m in dr.feed(c.recv()): sr.receive(m)
      for m in sr.outbox: c.send(frame(m))
      sr.outbox.setLen(0)
      t.feed(c.takeOut())
      for m in di.feed(t.recv()): si.receive(m)
      if si.done and sr.done: break
    check si.done and sr.done
    check b.entries.len == 2 and b.run.manager == me
