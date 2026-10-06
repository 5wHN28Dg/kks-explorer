import std/[unittest, asyncdispatch, asyncnet, net, tables, os]
import kks/[json, util, crypto, proto, node, sync, plant, progress]
import plat
import kksl/[net, dbstore, tls]

let P = testProvider()

suite "sync over real TCP":
  let rootKey = P.p256Generate()
  let kServer = P.p256Generate()
  let dir = getTempDir() / "kks-net-test"
  removeDir(dir)
  var server = newNode(P, openDbStore(P, dir / "server.db", P.randomBytes(32)), kServer)
  let me = P.newPersonId()
  discard server.append("genesis", P.genesisBody(rootKey, "Test plant", server.device, me, "boss", "The Manager"), nowMs())
  server.adopt(keyString(rootKey.pub))
  let lst = listen(server, newIdentity(kServer), 0, "127.0.0.1",
                   Hooks(secrets: proc (r: string, m: JNode): JNode = server.secretsAnswer(r, m)))

  test "a certified laptop joins, syncs, and a change travels back":
    let kLaptop = P.p256Generate()
    discard server.append("device_cert", deviceCertBody(P.peerId(kLaptop), me, "laptop"), nowMs())
    var laptop = newNode(P, newMemStore(), kLaptop)
    let st = waitFor laptop.syncWith(newIdentity(kLaptop), "127.0.0.1", lst.port, server.device, adoptRoot = server.root)
    check st.received == 2 and laptop.run.manager == me
    discard laptop.append("setting", newObj(@[("key", newStr("relay")), ("value", newNull())]), nowMs())
    let st2 = waitFor laptop.syncWith(newIdentity(kLaptop), "127.0.0.1", lst.port, server.device)
    check st2.sent == 1
    check server.entries.len == 3
    let ans = waitFor laptop.ask(newIdentity(kLaptop), "127.0.0.1", lst.port, server.device, laptop.secretsRequest())
    check ans["t"].s == "secrets"

  test "the wrong device answering is refused":
    let k = P.p256Generate()
    var other = newNode(P, newMemStore(), k)
    expect TlsError:
      discard waitFor other.syncWith(newIdentity(k), "127.0.0.1", lst.port, P.peerId(P.p256Generate()), adoptRoot = server.root)

  test "a stranger completes TLS but receives nothing":
    let k = P.p256Generate()
    var other = newNode(P, newMemStore(), k)
    other.adopt(server.root)
    let st = waitFor other.syncWith(newIdentity(k), "127.0.0.1", lst.port, server.device)
    check st.theyDenied and other.entries.len == 0

  test "the default listener takes IPv6 and IPv4 (one dual-stack socket)":
    let both = listen(server, newIdentity(kServer), 0)
    let k = P.p256Generate()
    discard server.append("device_cert", deviceCertBody(P.peerId(k), me, "laptop 2"), nowMs())
    var laptop = newNode(P, newMemStore(), k)
    check (waitFor laptop.syncWith(newIdentity(k), "::1", both.port, server.device, adoptRoot = server.root)).received > 0
    discard waitFor laptop.syncWith(newIdentity(k), "127.0.0.1", both.port, server.device)
    check laptop.entries.len == server.entries.len

  # issue #67: what a peer that isn't a device of the plant can make a listener hold
  proc strangerTls(port: int, address = "127.0.0.1"): (Stream, TlsConn) =
    let k = P.p256Generate()
    let sock = tcpStream(waitFor connectTcp(address, port))
    let c = newTlsConn(P, newIdentity(k), client = true, expectPeer = server.device)
    waitFor sock.handshake(c)
    (sock, c)

  proc closedWithin(sock: Stream, c: TlsConn, ms: int): bool =
    ## true when the server ends the connection within ms (an error frame first is fine)
    let t0 = nowMs()
    while nowMs() - t0 < ms:
      let fut = sock.read()
      if not waitFor withTimeout(fut, ms): return false
      if fut.read.len == 0: return true
      c.feed(fut.read)
      discard c.recv()
      if c.closed: return true
    false

  proc bigHeader(n: int): string =
    result = newString(4)
    result[0] = char((n shr 24) and 0xFF); result[1] = char((n shr 16) and 0xFF)
    result[2] = char((n shr 8) and 0xFF); result[3] = char(n and 0xFF)

  test "a stranger's large first frame is refused on its header":
    let (sock, c) = strangerTls(lst.port)
    c.send(bigHeader(HelloFrame + 1) & "{")
    waitFor sock.write(c.takeOut())
    check closedWithin(sock, c, 5000)
    sock.close()

  test "after the hello, a stranger gets StrangerFrame, not MaxFrame":
    let (sock, c) = strangerTls(lst.port)
    c.send(frame(newObj(@[("t", newStr("hello")), ("v", newInt(2)), ("root", newStr(server.root)), ("vv", newObj())])))
    c.send(bigHeader(StrangerFrame + 1) & "{")
    waitFor sock.write(c.takeOut())
    check closedWithin(sock, c, 5000)
    sock.close()

  test "a stranger is let go after strangerMs, even while it trickles":
    let short = listen(server, newIdentity(kServer), 0, "127.0.0.1")
    short.strangerMs = 1500
    let (sock, c) = strangerTls(short.port)
    c.send(frame(newObj(@[("t", newStr("hello")), ("v", newInt(2)), ("root", newStr(server.root)), ("vv", newObj())])))
    c.send(bigHeader(1000))
    waitFor sock.write(c.takeOut())
    let t0 = nowMs()
    var closed = false
    while nowMs() - t0 < 6000 and not closed:
      c.send("x")                                   # one byte of the entries frame every 300 ms
      try: waitFor sock.write(c.takeOut())
      except CatchableError: closed = true
      if not closed: closed = closedWithin(sock, c, 300)
    check closed
    check nowMs() - t0 < 4000
    sock.close()
    # a certified device still syncs through it
    let kL = P.p256Generate()
    discard server.append("device_cert", deviceCertBody(P.peerId(kL), me, "laptop 3"), nowMs())
    var l3 = newNode(P, newMemStore(), kL)
    check (waitFor l3.syncWith(newIdentity(kL), "127.0.0.1", short.port, server.device, adoptRoot = server.root)).received > 0

  test "connections are capped in all and per address":
    let capped = listen(server, newIdentity(kServer), 0, "")
    capped.maxOpen = 3
    capped.maxPerAddress = 2
    var socks: seq[AsyncSocket]
    for a in ["127.0.0.1", "127.0.0.1", "127.0.0.1", "127.0.0.2", "127.0.0.3"]:
      let s = newAsyncSocket(buffered = false)
      s.bindAddr(Port(0), a)                        # the source address
      waitFor s.connect("127.0.0.1", Port(capped.port))
      socks.add s
    waitFor sleepAsync(300)
    var closed: seq[bool]
    for s in socks:
      let fut = s.recv(1)
      closed.add(waitFor(withTimeout(fut, 300)) and fut.read.len == 0)
    check closed == @[false, false, true, false, true]   # the 3rd from one address, then the 4th overall
    check capped.open == 3
    for s in socks: s.close()
    waitFor sleepAsync(300)
    check capped.open == 0
