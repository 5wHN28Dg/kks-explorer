## The direct path of PROTOCOL-v2 §18 for the server and the desktop apps (Linux and Windows): one UDP socket per
## connection attempt, its public address from STUN (RFC 5389), hole punching to the other side's candidates, then a
## reliable stream (core/src/kks/rudp.nim) that the sync's TLS runs over like TCP (net.Stream). Twin of peer/rudp.py +
## peer/internet.py. One receive loop per socket hands each datagram to the current stage: asyncdispatch timeouts don't
## cancel a pending receive, so a receive per stage would swallow packets.

import std/[asyncdispatch, asyncnet, nativesockets, strutils, sysrand, times]
import kks/rudp
import net as kksnet

type
  Udp* = ref object
    sock: AsyncSocket
    port*: int
    closed: bool
    onPacket: proc (data, host: string, port: int)

const Stun* = [("stun.cloudflare.com", 3478), ("stun.l.google.com", 19302)]

proc monoNow(): float = epochTime()

proc recvLoop(u: Udp) {.async.} =
  while not u.closed:
    try:
      let (data, host, port) = await u.sock.recvFrom(2048)
      if u.onPacket != nil: u.onPacket(data, host, int(port))
    except CatchableError:
      if u.closed: break
      await sleepAsync(20)

proc newUdp*(): Udp =
  ## a UDP socket on any free port (IPv4: STUN and the candidates are IPv4), receiving at once
  let s = newAsyncSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered = false)
  s.bindAddr(Port(0))
  result = Udp(sock: s, port: int(s.getLocalAddr()[1]))
  asyncCheck result.recvLoop()

proc send*(u: Udp, host: string, port: int, data: string) {.async.} =
  try: await u.sock.sendTo(host, Port(port), data)
  except CatchableError: discard          # unreachable candidates are normal while punching

proc close*(u: Udp) =
  if not u.closed:
    u.closed = true
    u.sock.close()

proc stun*(u: Udp, servers = @Stun, timeout = 1500): Future[string] {.async.} =
  ## the public "ip:port" this socket's packets come from, or "" (no STUN answer: no public candidate)
  for (host, port) in servers:
    var tid = newString(12)
    discard urandom(toOpenArrayByte(tid, 0, 11))
    let req = "\x00\x01\x00\x00\x21\x12\xa4\x42" & tid
    var got = ""
    let done = newFuture[void]("stun")
    u.onPacket = proc (d, h: string, p: int) =
      if d.len < 20 or d[8 ..< 20] != tid or done.finished: return
      let n = (int(uint8(d[2])) shl 8) or int(uint8(d[3]))
      var i = 20
      while i + 4 <= min(d.len, 20 + n):
        let at = (int(uint8(d[i])) shl 8) or int(uint8(d[i + 1]))
        let al = (int(uint8(d[i + 2])) shl 8) or int(uint8(d[i + 3]))
        if at == 0x0020 and al >= 8 and i + 12 <= d.len and uint8(d[i + 5]) == 1:   # XOR-MAPPED-ADDRESS, IPv4
          let xp = ((int(uint8(d[i + 6])) shl 8) or int(uint8(d[i + 7]))) xor 0x2112
          let m = [0x21'u8, 0x12, 0xa4, 0x42]
          var ip: seq[string]
          for k in 0 .. 3: ip.add $(uint8(d[i + 8 + k]) xor m[k])
          got = ip.join(".") & ":" & $xp
          done.complete()
          return
        i += 4 + al + ((4 - al mod 4) mod 4)
    await u.send(host, port, req)
    discard await withTimeout(done, timeout)
    u.onPacket = nil
    if got.len > 0: return got
  ""

proc parseCand*(c: string): (string, int) =
  let i = c.rfind(':')
  if i <= 0: return ("", 0)
  try: (c[0 ..< i], parseInt(c[i + 1 .. ^1])) except ValueError: ("", 0)

type PunchResult* = object
  host*: string                 ## the address to use ("" = no direct path)
  port*: int
  confirmed*: bool              ## the other side heard us (PUNCH_ACK, or it already started the stream)
  heard*: seq[string]           ## the addresses we heard it from, in order ("ip:port"): for the log
  ms*: int

proc punch*(u: Udp, session: string, cands: seq[string], timeout = 4000, interval = 100): Future[PunchResult] {.async.} =
  ## Hole punching: PUNCH to every candidate until the other side is heard and has heard us.
  var r: PunchResult
  u.onPacket = proc (d, h: string, p: int) =
    if d.len < HeadLen or d[1 ..< HeadLen] != session: return
    let a = h & ":" & $p
    if a notin r.heard and r.heard.len < 8: r.heard.add a
    let typ = uint8(d[0])
    if typ == Punch:
      if r.host.len == 0: (r.host, r.port) = (h, p)
      asyncCheck u.send(h, p, packet(PunchAck, session))
    elif typ == PunchAck:
      # an answer to our PUNCH: the address our packets reach it at, and it ours: prefer it to an unanswered one
      (r.host, r.port) = (h, p)
      r.confirmed = true
    elif typ in [Data, Ack, Fin, Ping] and r.host.len > 0:
      r.confirmed = true                  # the other side already started: it heard us
  let t0 = monoNow()
  while (monoNow() - t0) * 1000 < float(timeout) and not r.confirmed:
    if r.host.len > 0: await u.send(r.host, r.port, packet(Punch, session))
    else:
      for c in cands:
        let (h, p) = parseCand(c)
        if h.len > 0: await u.send(h, p, packet(Punch, session))
    await sleepAsync(interval)
  u.onPacket = nil
  r.ms = int((monoNow() - t0) * 1000)
  if r.host.len == 0: r.port = 0       # heard nothing: no direct path
  return r

proc rudpStream*(u: Udp, host: string, port: int, session: string, dead = 15.0): kksnet.Stream =
  ## the reliable stream to the punched address, as a net.Stream for syncOver/serveOver
  # The other side's address can change after punching: NATs that map each destination to its own port, or that
  # rebind. Packets from another address with our session move the stream there (the session is the connect id's,
  # TLS on top authenticates the peer), and the change is logged: before 2026-10-04 they were dropped, and the
  # stream stalled with "the other device stopped answering".
  var host = host
  var port = port
  var moved = 0
  let r = newRudp(session, monoNow(), dead)
  var wake = newFuture[void]("rudp")
  var stopped = false
  proc flush() =
    for d in r.takeOut(): asyncCheck u.send(host, port, d)
  proc poke() =
    if not wake.finished: wake.complete()
  u.onPacket = proc (d, h: string, p: int) =
    if d.len < HeadLen or d[1 ..< HeadLen] != session: return
    if h != host or p != port:
      if moved < 4: stderr.writeLine "direct: the other side's address changed from " & host & ":" & $port & " to " & h & ":" & $p
      inc moved
      host = h
      port = p
    r.feed(d, monoNow())
    flush()
    poke()
  proc timers() {.async.} =
    while not stopped and not u.closed:
      await sleepAsync(20)
      r.tick(monoNow())
      flush()
      if r.error.len > 0: poke()
  asyncCheck timers()
  var told = false
  proc fail(): ref kksnet.NetError =
    # the state when a direct stream gives up, for studying stalls in the field (once per stream)
    if not told:
      told = true
      stderr.writeLine "direct: " & r.error & " with " & host & ":" & $port & ": " & r.debugState
      stderr.flushFile()
    newException(kksnet.NetError, r.error)
  proc readOne(): Future[string] {.async.} =
    while true:
      let got = r.read()
      if got.len > 0: return got
      if r.error.len > 0: raise fail()
      if r.ended: return ""
      wake = newFuture[void]("rudp")
      discard await withTimeout(wake, 200)
  proc writeAll(data: string): Future[void] {.async.} =
    r.write(data, monoNow())
    flush()
    while r.queued > 4 * 1024 * 1024 and r.error.len == 0: await sleepAsync(20)   # back-pressure
    if r.error.len > 0: raise fail()
  proc closeIt() =
    proc finishUp() {.async.} =
      let t0 = monoNow()
      while r.queued > 0 and r.error.len == 0 and monoNow() - t0 < 30: await sleepAsync(50)
      r.finish(monoNow())
      flush()
      let limit = min(dead, max(3.0, 5 * r.rto))
      let t1 = monoNow()
      while not r.finished and r.error.len == 0 and monoNow() - t1 < limit: await sleepAsync(50)
      stopped = true
      u.close()
    asyncCheck finishUp()
  kksnet.Stream(write: writeAll, read: readOne, close: closeIt)

when defined(windows):
  proc localIPv4s*(): seq[string] =
    ## this machine's IPv4 addresses other devices could reach (its host name resolved by Winsock; not loopback or
    ## link-local)
    try:
      var ai = getAddrInfo(getHostname(), Port(0), AF_INET, SOCK_STREAM, IPPROTO_TCP)
      var p = ai
      while p != nil:
        if p.ai_addr != nil:
          let ip = $inet_ntoa(cast[ptr Sockaddr_in](p.ai_addr).sin_addr)
          if not ip.startsWith("127.") and not ip.startsWith("169.254.") and ip notin result: result.add ip
        p = p.ai_next
      freeAddrInfo(ai)
    except OSError: discard
else:
  import std/posix
  type Ifaddrs {.importc: "struct ifaddrs", header: "<ifaddrs.h>", bycopy.} = object
    ifa_next: ptr Ifaddrs
    ifa_name: cstring
    ifa_flags: cuint
    ifa_addr: ptr SockAddr
  proc getifaddrs(ifap: ptr ptr Ifaddrs): cint {.importc, header: "<ifaddrs.h>".}
  proc freeifaddrs(ifa: ptr Ifaddrs) {.importc, header: "<ifaddrs.h>".}
  proc localIPv4s*(): seq[string] =
    ## this machine's IPv4 addresses other devices could reach (not loopback, not link-local)
    var ifs: ptr Ifaddrs
    if getifaddrs(addr ifs) != 0: return
    var p = ifs
    while p != nil:
      if p.ifa_addr != nil and p.ifa_addr.sa_family == TSa_Family(posix.AF_INET):
        let ip = $inet_ntoa(cast[ptr Sockaddr_in](p.ifa_addr).sin_addr)
        if not ip.startsWith("127.") and not ip.startsWith("169.254.") and ip notin result: result.add ip
      p = p.ifa_next
    freeifaddrs(ifs)
