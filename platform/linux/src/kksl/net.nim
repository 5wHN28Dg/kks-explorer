## Sync connections on Linux: async TCP, TLS through buffers (tls.nim), the core's session state machine. One thread
## owns the node (decision 0030); everything here runs on the asyncdispatch loop.

import std/[asyncdispatch, asyncnet, monotimes, net, nativesockets, tables, times]
import kks/[json, crypto, node, sync]
when defined(windows): import kksw/tls   # Schannel (decision 0033), same API
else: import tls

const
  Timeout* = 20_000   # ms without progress before a connection is dropped
  # Incoming sync connections a listener holds at once, in all and from one address (issue #67). A plant's devices
  # sync one at a time with each other, in about a second; these leave room for many.
  MaxIncoming* = 32
  MaxIncomingPerAddress* = 4

type NetError* = object of CatchableError

proc nowMs*(): int64 = int64(epochTime() * 1000)

type
  Alarm = ref object
    ## One per stream, firing when `deadline` passes during a read. withTimeout made a timer per read that stayed
    ## in the dispatcher for Timeout (20 s) after the read: the direct stream gives a packet per read, so a sync over
    ## it held some 20 s of reads' timers, about a tenth of the data it moved (2026-10-09).
    deadline: MonoTime    ## monotonic: a clock change neither ends a healthy read nor stretches a stalled one
    fired: Future[void]   ## a fresh one for each read; completed only while that read waits
    waiting: bool         ## a read waits
    watching: bool        ## the watcher runs (it stops at its first look with no read waiting)

  Stream* = ref object
    ## A byte stream a sync session runs over: TCP on the same network, or a relay pipe (PROTOCOL-v2 §18).
    write*: proc (data: string): Future[void] {.closure, gcsafe.}
    read*: proc (): Future[string] {.closure, gcsafe.}   ## some bytes; "" = closed
    close*: proc () {.closure, gcsafe.}
    alarm: Alarm

const AlarmStep = 250   ## ms between the watcher's looks: how late a timeout may fire

proc tcpStream*(sock: AsyncSocket): Stream =
  Stream(write: proc (data: string): Future[void] = sock.send(data),
         read: proc (): Future[string] = sock.recv(16384),
         close: proc () = sock.close())

proc watch(a: Alarm) {.async.} =
  ## one timer at a time per stream, whatever the number of reads
  while a.waiting:
    await sleepAsync(AlarmStep)
    if a.waiting and getMonoTime() >= a.deadline and not a.fired.finished: a.fired.complete()
  a.watching = false

proc recvSome(st: Stream, deadline = 0'i64): Future[string] {.async.} =
  ## some bytes within Timeout, and before `deadline` (ms, 0 = none)
  if deadline > 0 and nowMs() >= deadline: raise newException(NetError, "the other side is not a device of this plant")
  let wait = if deadline > 0: min(int64(Timeout), max(1'i64, deadline - nowMs())) else: int64(Timeout)
  let fut = st.read()
  if not fut.finished:
    if st.alarm == nil: st.alarm = Alarm()
    let a = st.alarm
    a.deadline = getMonoTime() + initDuration(milliseconds = wait)
    a.fired = newFuture[void]("kks.net.alarm")
    a.waiting = true
    if not a.watching:
      a.watching = true
      asyncCheck a.watch()
    try:
      await (fut or a.fired)
    finally:
      a.waiting = false
    if not fut.finished:
      raise newException(NetError, if deadline > 0 and nowMs() >= deadline: "the other side is not a device of this plant" else: "timed out")
  result = fut.read
  if result.len == 0: raise newException(NetError, "connection closed")

proc flush(st: Stream, c: TlsConn) {.async.} =
  let o = c.takeOut()
  if o.len > 0: await st.write(o)

proc handshake*(sock: Stream, c: TlsConn, deadline = 0'i64) {.async.} =
  discard c.handshake()
  await sock.flush(c)
  while not c.handshake():
    await sock.flush(c)
    c.feed(await sock.recvSome(deadline))
  await sock.flush(c)

proc drive(sock: Stream, c: TlsConn, s: Session, deadline = 0'i64) {.async.} =
  ## Run the exchange to the end. On a protocol error, tell the other side and re-raise. `deadline` (ms) ends a
  ## responder's connection while the other side is not trusted yet (issue #67).
  var d: Deframer
  try:
    while true:
      # a budget of blobs at a time, each sent before the next is read from the store: the whole want at once held
      # a plant's drawings and photos several times over per device (2026-10-09)
      for m in s.take(): c.send(frame(m))
      await sock.flush(c)
      if s.sending: continue
      if s.done: break
      let plain = c.recv()
      if plain.len == 0:
        if c.closed: raise newException(NetError, "the other side closed the connection")
        c.feed(await sock.recvSome(if s.trusted: 0'i64 else: deadline))
        continue
      d.add plain
      while true:
        let m = d.next(s.frameLimit)
        if m == nil: break
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
  let deadline = nowMs() + StrangerMs
  try:
    await sock.handshake(c, deadline)
    let s = newSession(n, false, c.remotePeer, hooks = hooks)
    s.wall = nowMs()
    await sock.drive(c, s, deadline)
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
  ## One question instead of a sync (§16 join, §17 secrets) over an open stream: send `msg`, return the answer.
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
  open*: int                    ## incoming connections held now
  perAddress: Table[string, int]
  maxOpen*, maxPerAddress*: int ## MaxIncoming, MaxIncomingPerAddress (tests lower them)
  strangerMs*: int64            ## StrangerMs (tests lower it)
  enrollFrom*: proc (remote, address: string, m: JNode): JNode
    ## when set, answers §16 enroll instead of the hooks' `enroll`, told the TCP peer's address (password throttling
    ## counts the address: a peer ID costs nothing to change, issue #39)

proc serveOne(l: Listener, n: Node, id: Identity, raw: AsyncSocket, address: string, hooks: Hooks) {.async.} =
  let client = tcpStream(raw)
  var c: TlsConn
  let deadline = nowMs() + l.strangerMs
  try:
    c = newTlsConn(n.p, id, client = false)   # inside the try: the slot is given back whatever fails
    await client.handshake(c, deadline)
    var h = hooks
    if l.enrollFrom != nil:
      let f = l.enrollFrom
      let a = address
      h.enroll = proc (remote: string, m: JNode): JNode = f(remote, a, m)
    let s = newSession(n, false, c.remotePeer, hooks = h)
    s.wall = nowMs()
    await client.drive(c, s, deadline)
    inc l.sessions
    if l.onDone != nil and s.special.len == 0: l.onDone(c.remotePeer, s.stats)
  except CatchableError as e:
    l.lastError = e.msg
  finally:
    if c != nil: c.close()
    client.close()
    dec l.open
    l.perAddress[address] = l.perAddress.getOrDefault(address) - 1
    if l.perAddress[address] <= 0: l.perAddress.del address

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
  l.maxOpen = MaxIncoming
  l.maxPerAddress = MaxIncomingPerAddress
  l.strangerMs = StrangerMs
  proc loop() {.async.} =
    while true:
      let (address, client) = await l.sock.acceptAddr()
      if l.open >= l.maxOpen or l.perAddress.getOrDefault(address) >= l.maxPerAddress:
        client.close()   # issue #67: a full listener takes no more
        continue
      inc l.open
      l.perAddress.mgetOrPut(address, 0) += 1
      asyncCheck l.serveOne(n, id, client, address, hooks)
  asyncCheck loop()
  l
