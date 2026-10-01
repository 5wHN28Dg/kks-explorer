## Sync connections on Linux: async TCP, TLS through buffers (tls.nim), the core's session state machine. One thread
## owns the node (decision 0030); everything here runs on the asyncdispatch loop.

import std/[asyncdispatch, asyncnet, net, times]
import kks/[json, crypto, node, sync]
when defined(windows): import kksw/tls   # Schannel (decision 0033), same API
else: import tls

const Timeout* = 20_000   # ms without progress before a connection is dropped

type NetError* = object of CatchableError

proc nowMs*(): int64 = int64(epochTime() * 1000)

proc recvSome(sock: AsyncSocket): Future[string] {.async.} =
  let fut = sock.recv(16384)
  if not await withTimeout(fut, Timeout): raise newException(NetError, "timed out")
  result = fut.read
  if result.len == 0: raise newException(NetError, "connection closed")

proc flush(sock: AsyncSocket, c: TlsConn) {.async.} =
  let o = c.takeOut()
  if o.len > 0: await sock.send(o)

proc handshake(sock: AsyncSocket, c: TlsConn) {.async.} =
  discard c.handshake()
  await sock.flush(c)
  while not c.handshake():
    await sock.flush(c)
    c.feed(await sock.recvSome())
  await sock.flush(c)

proc drive(sock: AsyncSocket, c: TlsConn, s: Session) {.async.} =
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

proc syncWith*(n: Node, id: Identity, host: string, port: int, expectPeer: string, adoptRoot = "",
               hooks = Hooks()): Future[Stats] {.async.} =
  ## Connect, sync as the initiator, close. expectPeer: the device we mean to reach (mDNS, invite, remembered).
  let sock = newAsyncSocket(buffered = false)
  let fut = sock.connect(host, Port(port))
  if not await withTimeout(fut, Timeout):
    sock.close()
    raise newException(NetError, "could not connect to " & host)
  fut.read
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

proc ask*(n: Node, id: Identity, host: string, port: int, expectPeer: string, msg: JNode): Future[JNode] {.async.} =
  ## One question instead of a sync (§16 join, §17 secrets): send `msg`, return the single answer.
  let sock = newAsyncSocket(buffered = false)
  let fut = sock.connect(host, Port(port))
  if not await withTimeout(fut, Timeout):
    sock.close()
    raise newException(NetError, "could not connect to " & host)
  fut.read
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

type Listener* = ref object
  sock*: AsyncSocket
  port*: int
  sessions*: int
  lastError*: string
  onDone*: proc (remote: string, stats: Stats)

proc serveOne(l: Listener, n: Node, id: Identity, client: AsyncSocket, hooks: Hooks) {.async.} =
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

proc listen*(n: Node, id: Identity, port: int, address = "0.0.0.0", hooks = Hooks()): Listener =
  ## Accept sync connections until the loop stops. port 0 = any free port (see `port`).
  let l = Listener(sock: newAsyncSocket(buffered = false))
  l.sock.setSockOpt(OptReuseAddr, true)
  l.sock.bindAddr(Port(port), address)
  l.sock.listen()
  l.port = int(l.sock.getLocalAddr()[1])
  proc loop() {.async.} =
    while true:
      let client = await l.sock.accept()
      asyncCheck l.serveOne(n, id, client, hooks)
  asyncCheck loop()
  l
