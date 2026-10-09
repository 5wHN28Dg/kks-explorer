## A reliable byte stream over UDP datagrams (PROTOCOL-v2 §18, the v1 wire format: peer/rudp.py, Rudp.kt), sans I/O:
## datagrams and the time go in, datagrams to send and received bytes come out. The platform layer owns the socket.
## Encryption is not done here: the sync's TLS (§15) runs over this stream exactly as over TCP.
##
## Datagram = type u8 + session (8 bytes) + body, big-endian:
##   PUNCH 1, PUNCH_ACK 2: empty;  DATA 3: seq u32 + payload (≤ MSS);  ACK 4: next u32 + mask u32 (bit i: next+1+i
##   arrived too);  FIN 5: seq u32;  PING 6: empty.
## Sender: window from 8 up to 256 packets, halved on loss once per round; RFC 6298 RTO from measured round trips,
## 200 ms – 4 s, doubled per timeout (capped at 4 s); fast retransmit when 3 later packets are acknowledged past a
## hole; no progress for `dead` seconds = failure.

import std/[algorithm, sequtils, tables]

const
  Punch* = 1'u8
  PunchAck* = 2'u8
  Data* = 3'u8
  Ack* = 4'u8
  Fin* = 5'u8
  Ping* = 6'u8
  Mss* = 1150            ## payload per datagram: 1 + 8 + 4 + 1150 < 1200, under any path MTU
  HeadLen* = 9
  RecvWindow* = 512'u32  ## out-of-order packets kept at most this far past the next expected one (issue #36): a sender
                         ## never has more than 256 packets plus its FIN in flight, so a well-behaved peer never
                         ## reaches it; anything further is dropped (unacknowledged), bounding the buffer to ~590 kB

type
  Sent = object
    payload: string
    at: float            ## when last sent (-1 = never: any time, 0 included, can be a real send time)
    retries: int
    sacked: bool
  Rudp* = ref object
    session*: string     ## 8 bytes
    dead: float
    nextSeq, base: uint32
    unacked: Table[uint32, Sent]
    queue: string        ## bytes written, packetized up to qAt (cut in `write`, not per packet: cutting per packet
    qAt: int             ## copied the rest each time, quadratic, and a sync of a few MB stalled the server's loop)
    cwnd: float
    ssthresh: int
    srtt, rttvar, rto: float
    haveRtt: bool
    finSeq: int64        ## -1 = not closing
    recover: uint32
    progress: float
    rnext: uint32
    rbuf: Table[uint32, string]
    inbox: string
    peerFin: int64       ## -1 = the other side hasn't finished
    lastRx, lastTx: float
    outbox: seq[string]
    error*: string

proc be32(x: uint32): string =
  result = newString(4)
  result[0] = char(x shr 24); result[1] = char((x shr 16) and 0xff); result[2] = char((x shr 8) and 0xff); result[3] = char(x and 0xff)

proc rd32(s: string, o: int): uint32 =
  (uint32(uint8(s[o])) shl 24) or (uint32(uint8(s[o + 1])) shl 16) or (uint32(uint8(s[o + 2])) shl 8) or uint32(uint8(s[o + 3]))

proc packet*(typ: uint8, session: string, body = ""): string = char(typ) & session & body

proc newRudp*(session: string, now: float, dead = 15.0): Rudp =
  assert session.len == 8
  Rudp(session: session, dead: dead, cwnd: 8.0, ssthresh: 256, rto: 0.5, finSeq: -1, peerFin: -1, progress: now,
       lastRx: now, lastTx: now)

proc raw(r: Rudp, typ: uint8, now: float, body = "") =
  r.outbox.add packet(typ, r.session, body)
  r.lastTx = now

proc sendData(r: Rudp, seq: uint32, now: float) =
  r.unacked[seq].at = now
  if int64(seq) == r.finSeq: r.raw(Fin, now, be32(seq))
  else: r.raw(Data, now, be32(seq) & r.unacked[seq].payload)

proc pump(r: Rudp, now: float) =
  ## packetize queued bytes while the window allows
  while r.queue.len > r.qAt and float(r.nextSeq - r.base) < float(int(r.cwnd)):
    let n = min(Mss, r.queue.len - r.qAt)
    r.unacked[r.nextSeq] = Sent(payload: r.queue[r.qAt ..< r.qAt + n], at: -1.0)
    r.qAt += n
    if r.qAt == r.queue.len:
      r.queue.setLen(0)
      r.qAt = 0
    r.sendData(r.nextSeq, now)
    inc r.nextSeq

proc sample(r: Rudp, x: float) =
  if not r.haveRtt:
    r.srtt = x; r.rttvar = x / 2; r.haveRtt = true
  else:
    r.rttvar = 0.75 * r.rttvar + 0.25 * abs(r.srtt - x)
    r.srtt = 0.875 * r.srtt + 0.125 * x
  r.rto = min(4.0, max(0.2, r.srtt + 4 * r.rttvar))

proc lost(r: Rudp, seq: uint32) =
  ## a loss halves the window, once per round of packets
  if seq >= r.recover:
    r.ssthresh = max(2, int(r.cwnd / 2))
    r.cwnd = float(r.ssthresh)
    r.recover = r.nextSeq

proc onAck(r: Rudp, nxt, mask: uint32, now: float) =
  var newly = 0
  var gone: seq[uint32]
  for s in r.unacked.keys:
    if s < nxt: gone.add s
  for s in gone:
    let rec = r.unacked[s]
    r.unacked.del s
    inc newly
    if rec.retries == 0 and rec.at >= 0: r.sample(now - rec.at)   # Karn: only packets sent once
  for i in 0 ..< 32:
    if ((mask shr uint32(i)) and 1) == 1:
      let s = nxt + 1 + uint32(i)
      if s in r.unacked and not r.unacked[s].sacked:
        r.unacked[s].sacked = true
        if r.unacked[s].retries == 0 and r.unacked[s].at >= 0: r.sample(now - r.unacked[s].at)
  if nxt > r.base:
    r.base = nxt
    r.progress = now
  if newly > 0:
    r.cwnd = min(r.cwnd + (if r.cwnd < float(r.ssthresh): 1.0 else: 1.0 / r.cwnd) * float(newly), 256.0)
  # holes with 3+ later packets acknowledged are lost: send them again now, at most once a round trip each
  var keys = toSeq(r.unacked.keys)
  keys.sort(system.cmp, Descending)
  var later = 0
  for s in keys:
    if r.unacked[s].sacked: inc later
    elif later >= 3 and r.unacked[s].at >= 0 and now - r.unacked[s].at > (if r.haveRtt: r.srtt else: 0.1):
      r.lost(s)
      inc r.unacked[s].retries
      r.sendData(s, now)
  r.pump(now)

proc onData(r: Rudp, seq: uint32, payload: string, fin: bool, now: float) =
  if seq >= r.rnext and seq - r.rnext >= RecvWindow: return   # beyond the window: dropped, not acknowledged
  if fin: r.peerFin = int64(seq)
  if seq >= r.rnext and seq notin r.rbuf:
    r.rbuf[seq] = payload
    while r.rnext in r.rbuf:
      r.inbox.add r.rbuf[r.rnext]
      r.rbuf.del r.rnext
      inc r.rnext
  var mask = 0'u32
  for i in 0 ..< 32:
    if r.rnext + 1 + uint32(i) in r.rbuf: mask = mask or (1'u32 shl uint32(i))
  r.raw(Ack, now, be32(r.rnext) & be32(mask))

proc feed*(r: Rudp, d: string, now: float) =
  ## one datagram from the other side's address (the caller checks the address)
  if d.len < HeadLen or d[1 ..< HeadLen] != r.session: return
  r.lastRx = now
  let typ = uint8(d[0])
  let body = d[HeadLen .. ^1]
  if typ == Data and body.len >= 4: r.onData(rd32(body, 0), body[4 .. ^1], false, now)
  elif typ == Fin and body.len >= 4: r.onData(rd32(body, 0), "", true, now)
  elif typ == Ack and body.len >= 8: r.onAck(rd32(body, 0), rd32(body, 4), now)
  elif typ == Punch or typ == PunchAck: r.raw(PunchAck, now)

proc tick*(r: Rudp, now: float, closed = false) =
  ## timers: retransmissions, failure detection, keep-alive (call every few tens of ms)
  var keys = toSeq(r.unacked.keys)
  keys.sort()
  for i, s in keys:
    if i > int(r.cwnd): break
    let rec = r.unacked[s]
    if not rec.sacked and rec.at >= 0 and now - rec.at > min(4.0, r.rto * float(1 shl min(rec.retries, 4))):
      r.lost(s)
      inc r.unacked[s].retries
      r.sendData(s, now)
  if r.unacked.len > 0 and now - r.progress > r.dead: r.error = "the other device stopped answering"
  if now - r.lastRx > r.dead and not closed and r.error.len == 0: r.error = "the other device stopped answering"
  if now - r.lastTx > 2.0 and not closed: r.raw(Ping, now)
  r.pump(now)

proc write*(r: Rudp, data: string, now: float) =
  if r.finSeq >= 0: raise newException(IOError, "stream closed")
  if r.qAt > 0:
    r.queue = r.queue[r.qAt .. ^1]
    r.qAt = 0
  r.queue.add data
  r.pump(now)

proc buffered*(r: Rudp): int = r.rbuf.len   ## packets received out of order, waiting for a hole to fill

proc queued*(r: Rudp): int = r.queue.len - r.qAt   ## bytes not yet packetized (back-pressure)

proc read*(r: Rudp): string =
  ## everything received in order so far
  result = move r.inbox
  r.inbox = ""

proc ended*(r: Rudp): bool = r.peerFin >= 0 and int64(r.rnext) > r.peerFin   ## the other side closed and all arrived

proc finish*(r: Rudp, now: float) =
  ## after the queue: FIN (acknowledged like data)
  if r.finSeq < 0 and r.queued == 0:
    r.finSeq = int64(r.nextSeq)
    r.unacked[r.nextSeq] = Sent(at: -1.0)
    r.sendData(r.nextSeq, now)
    inc r.nextSeq

proc finished*(r: Rudp): bool = r.finSeq >= 0 and r.unacked.len == 0   ## our FIN and everything before it acknowledged
proc rto*(r: Rudp): float = r.rto

proc takeOut*(r: Rudp): seq[string] =
  result = move r.outbox
  r.outbox = @[]

proc debugState*(r: Rudp): string =
  var ks = toSeq(r.unacked.keys)
  ks.sort()
  var head = ""
  for s in ks[0 ..< min(4, ks.len)]:
    head.add $s & "(at " & $r.unacked[s].at & " r" & $r.unacked[s].retries & (if r.unacked[s].sacked: " sacked" else: "") & ") "
  "base=" & $r.base & " next=" & $r.nextSeq & " cwnd=" & $r.cwnd & " rto=" & $r.rto & " unacked=" & $r.unacked.len & " " & head
