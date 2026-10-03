## Sync connections on Linux: async TCP, TLS through buffers (tls.nim), the core's session state machine. One thread
## owns the node (decision 0030); everything here runs on the asyncdispatch loop.

import std/[asyncdispatch, asyncnet, net, nativesockets, times]
import kks/[json, crypto, node, sync]
when defined(windows): import kksw/tls   # Schannel (decision 0033), same API
else: import tls

const Timeout* = 20_000   # ms without progress before a connection is dropped

type NetError* = object of CatchableError

proc nowMs*(): int64 = int64(epochTime() * 1000)

type Stream* = ref object
  ## A byte stream a sync session runs over: TCP on the same network, or a relay pipe (PROTOCOL-v2 §18).
  write*: proc (data: string): Future[void] {.closure, gcsafe.}
  read*: proc (): Future[string] {.closure, gcsafe.}   ## some bytes; "" = closed
  close*: proc () {.closure, gcsafe.}

proc tcpStream*(sock: AsyncSocket): Stream =
  Stream(write: proc (data: string): Future[void] = sock.send(data),
         read: proc (): Future[string] = sock.recv(16384),
         close: proc () = sock.close())

proc recvSome(st: Stream): Future[string] {.async.} =
  let fut = st.read()
  if not await withTimeout(fut, Timeout): raise newException(NetError, "timed out")
  result = fut.read
  if result.len == 0: raise newException(NetError, "connection closed")

proc flush(st: Stream, c: TlsConn) {.async.} =
  let o = c.takeOut()
  if o.len > 0: await st.write(o)

proc handshake*(sock: Stream, c: TlsConn) {.async.} =
  discard c.handshake()
  await sock.flush(c)
  while not c.handshake():
    await sock.flush(c)
    c.feed(await sock.recvSome())
  await sock.flush(c)

proc drive(sock: Stream, c: TlsConn, s: Session) {.async.} =
  ## Run the exchange to the end. On a protocol error, tell the other side and re-raise.
  var d: Deframer
  try:
    while true:
      for m in s.outbox: c.send(frame(m))
      s.outbox.setLen(0)
      await sock.flush(c)
      if s.done: break
      let plain = c.recv()
      if plain.len == 0:
        if c.closed: raise newException(NetError, "the other side closed the connection")
        c.feed(await sock.recvSome())
        continue
      for m in d.feed(plain):
        s.wall = nowMs()
        s.receive(m)
  except SyncError as e:
    try:
      c.send(frame(errorMsg(e.msg)))
      await sock.flush(c)
    except CatchableError: discard
    raise

proc connectTcp*(host: string, port: int): Future[AsyncSocket] {.async.} =
  ## TCP to an IPv4 or IPv6 address (or a name: each address it resolves to in turn), within Timeout
  let fut = asyncnet.dial(host, Port(port), buffered = false)
  if not await withTimeout(fut, Timeout):
    fut.addCallback(proc () =
      if not fut.failed: fut.read.close())
    raise newException(NetError, "could not connect to " & host)
  try: result = fut.read
  except OSError as e: raise newException(NetError, "could not connect to " & host & ": " & e.msg)

proc syncOver*(n: Node, id: Identity, sock: Stream, expectPeer: string, adoptRoot = "",
               hooks = Hooks()): Future[Stats] {.async.} =
  ## Sync as the initiator over an open stream (TCP or a relay pipe), then close it.
  let c = newTlsConn(n.p, id, client = true, expectPeer = expectPeer)
  try:
    await sock.handshake(c)
    let s = newSession(n, true, c.remotePeer, adoptRoot, hooks)
    s.wall = nowMs()
    await sock.drive(c, s)
    result = s.stats
  finally:
    c.close()
    sock.close()

proc serveOver*(n: Node, id: Identity, sock: Stream, hooks = Hooks()): Future[(string, Stats)] {.async.} =
  ## Answer one sync over an open stream (the listener, or a relay pipe), then close it. -> (remote peer, stats)
  let c = newTlsConn(n.p, id, client = false)
  try:
    await sock.handshake(c)
    let s = newSession(n, false, c.remotePeer, hooks = hooks)
    s.wall = nowMs()
    await sock.drive(c, s)
    result = (c.remotePeer, s.stats)
  finally:
    c.close()
    sock.close()

proc syncWith*(n: Node, id: Identity, host: string, port: int, expectPeer: string, adoptRoot = "",
               hooks = Hooks()): Future[Stats] {.async.} =
  ## Connect, sync as the initiator, close. expectPeer: the device we mean to reach (mDNS, invite, remembered).
  let raw = await connectTcp(host, port)
  let sock = tcpStream(raw)
  let c = newTlsConn(n.p, id, client = true, expectPeer = expectPeer)
  try:
    await sock.handshake(c)
    let s = newSession(n, true, c.remotePeer, adoptRoot, hooks)
    s.wall = nowMs()
    await sock.drive(c, s)
    result = s.stats
  finally:
    c.close()
    sock.close()

proc askOver*(n: Node, id: Identity, sock: Stream, expectPeer: string, msg: JNode): Future[JNode] {.async.} =
  ## One question instead of a sync (§16 join, §17 secrets, §21a) over an open stream: send `msg`, return the answer.
  let c = newTlsConn(n.p, id, client = true, expectPeer = expectPeer)
  try:
    await sock.handshake(c)
    c.send(frame(msg))
    await sock.flush(c)
    var d: Deframer
    while true:
      let plain = c.recv()
      if plain.len > 0:
        let got = d.feed(plain)
        if got.len > 0: return got[0]
      elif c.closed: raise newException(NetError, "no answer")
      else: c.feed(await sock.recvSome())
  finally:
    c.close()
    sock.close()

proc ask*(n: Node, id: Identity, host: string, port: int, expectPeer: string, msg: JNode): Future[JNode] {.async.} =
  ## One question instead of a sync over TCP.
  let raw = await connectTcp(host, port)
  result = await askOver(n, id, tcpStream(raw), expectPeer, msg)

type Listener* = ref object
  sock*: AsyncSocket
  port*: int
  sessions*: int
  lastError*: string
  onDone*: proc (remote: string, stats: Stats)

proc serveOne(l: Listener, n: Node, id: Identity, raw: AsyncSocket, hooks: Hooks) {.async.} =
  let client = tcpStream(raw)
  let c = newTlsConn(n.p, id, client = false)
  try:
    await client.handshake(c)
    let s = newSession(n, false, c.remotePeer, hooks = hooks)
    s.wall = nowMs()
    await client.drive(c, s)
    inc l.sessions
    if l.onDone != nil and s.special.len == 0: l.onDone(c.remotePeer, s.stats)
  except CatchableError as e:
    l.lastError = e.msg
  finally:
    c.close()
    client.close()

when defined(windows):
  var IPV6_V6ONLY {.importc, header: "<ws2ipdef.h>".}: cint
  var IPPROTO_IPV6_C {.importc: "IPPROTO_IPV6", header: "<winsock2.h>".}: cint
else:
  var IPV6_V6ONLY {.importc, header: "<netinet/in.h>".}: cint
  var IPPROTO_IPV6_C {.importc: "IPPROTO_IPV6", header: "<netinet/in.h>".}: cint

proc listen*(n: Node, id: Identity, port: int, address = "", hooks = Hooks()): Listener =
  ## Accept sync connections until the loop stops. port 0 = any free port (see `port`). address "" = every interface,
  ## IPv6 and IPv4 on one dual-stack socket (mDNS announces both kinds of address; an IPv4-only listener refused the
  ## IPv6 ones, found on the Note 9 2026-10-02), else IPv4 only where the system has no IPv6.
  var l: Listener
  if address.len == 0:
    try:
      l = Listener(sock: newAsyncSocket(AF_INET6, buffered = false))
      setSockOptInt(l.sock.getFd, IPPROTO_IPV6_C, IPV6_V6ONLY, 0)   # Windows defaults to v6-only
      l.sock.setSockOpt(OptReuseAddr, true)
      l.sock.bindAddr(Port(port), "::")
    except OSError:
      if l != nil: l.sock.close()
      l = nil
  if l == nil:
    l = Listener(sock: newAsyncSocket(buffered = false))
    l.sock.setSockOpt(OptReuseAddr, true)
    l.sock.bindAddr(Port(port), if address.len == 0: "0.0.0.0" else: address)
  l.sock.listen()
  l.port = int(l.sock.getLocalAddr()[1])
  proc loop() {.async.} =
    while true:
      let client = await l.sock.accept()
      asyncCheck l.serveOne(n, id, client, hooks)
  asyncCheck loop()
  l
