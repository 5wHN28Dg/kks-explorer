## The sync exchange (PROTOCOL-v2 §15–17) as a sans-I/O state machine. The platform runs TLS (its own stack, pinned to
## device keys) over a byte stream, feeds received bytes in and writes what comes out. The TLS layer reports the
## remote peer ID (the §2 hash of the certificate's key).

import std/[base64, sets, strutils, tables]
import json, util, proto, node, relaykey

const
  MaxFrame* = 64 * 1024 * 1024
  # A responder's limits while it doesn't know the other side (issue #67): any key completes TLS, so until the hello
  # is read, and after it while the other side is no device this one serves, frames stay small and the platform
  # ends the connection after StrangerMs. That bounds what a stranger makes a node hold.
  HelloFrame* = 1024 * 1024           ## before the first message (hello, join, enroll, secrets) is read
  StrangerFrame* = 4 * 1024 * 1024    ## after it, while the other side is not a device this one serves
  StrangerMs* = 60_000
  Alpn* = "kks-sync/2"

# ---------------------------------------------------------------- framing

proc frame*(msg: JNode): string =
  ## 4-byte big-endian length + JSON.
  let body = toText(msg)
  if body.len > MaxFrame: raise newException(ValueError, "message too large")
  result = newString(4)
  let n = uint32(body.len)
  result[0] = char((n shr 24) and 0xFF)
  result[1] = char((n shr 16) and 0xFF)
  result[2] = char((n shr 8) and 0xFF)
  result[3] = char(n and 0xFF)
  result.add body

type
  SyncError* = object of CatchableError

  Deframer* = object
    buf: string
    at: int              ## where the next frame starts in buf (consumed bytes are dropped in `add`, not per frame:
                         ## cutting the buffer after every frame copied the rest each time, quadratic in a big read)

proc add*(d: var Deframer, bytes: string) =
  ## Bytes received; take the messages out with `next`.
  if d.at > 0:
    if d.at >= d.buf.len: d.buf.setLen(0)
    else: d.buf = d.buf[d.at .. ^1]
    d.at = 0
  d.buf.add bytes

proc next*(d: var Deframer, limit = MaxFrame): JNode =
  ## The next complete message (strict JSON, §1), or nil until more bytes arrive. A frame announcing more than `limit`
  ## bytes is refused on its 4-byte header, before its body is held. Raises SyncError on a bad frame.
  let a = d.at
  if d.buf.len - a < 4: return nil
  let n = (int(uint8(d.buf[a])) shl 24) or (int(uint8(d.buf[a + 1])) shl 16) or (int(uint8(d.buf[a + 2])) shl 8) or
          int(uint8(d.buf[a + 3]))
  if n > min(limit, MaxFrame): raise newException(SyncError, "frame too large")
  if d.buf.len - a < 4 + n: return nil
  let body = d.buf[a + 4 ..< a + 4 + n]
  d.at = a + 4 + n
  if d.at == d.buf.len:
    d.buf.setLen(0)
    d.at = 0
  try: result = parseStrict(body)
  except JsonError as e: raise newException(SyncError, "bad message: " & e.msg)
  if result.kind != jObj or result.get("t") == nil or result["t"].kind != jStr:
    raise newException(SyncError, "message without t")

proc feed*(d: var Deframer, bytes: string): seq[JNode] =
  ## Complete messages in the bytes received so far, each up to MaxFrame (an initiator's side, tests).
  d.add bytes
  while true:
    let m = d.next()
    if m == nil: break
    result.add m

# ---------------------------------------------------------------- the exchange

type
  Stage = enum
    sHello, sEntries, sWant, sBlobs, sBye, sDone

  Stats* = object
    sent*, received*, blobsSent*, blobsReceived*: int
    denied*, theyDenied*: bool

  Hooks* = object
    ## Answers for connections that are not a sync (§16 join, §17 secrets), on the responder.
    join*: proc (remote: string, msg: JNode): JNode
    secrets*: proc (remote: string, msg: JNode): JNode
    enroll*: proc (remote: string, msg: JNode): JNode   ## §16 through a server: password + join request → enroll_ack
    wipe*: proc (by: string)           ## called after a verified `revoked` (the platform deletes the plant data);
                                       ## by = who removed the device (full name, may be "")

  Session* = ref object
    n*: Node
    initiator*: bool
    remote*: string            ## the TLS peer's ID
    adoptRoot*: string         ## a node without a plant accepts only this root ("" = none)
    hooks*: Hooks
    wall*: int64               ## the time to use for clocks (ms), set by the platform before feeding
    stage: Stage
    theirVv: JNode
    theirWant: seq[string]
    sentBlobs, gotBlobsEnd: bool
    outbox*: seq[JNode]        ## messages to send; blobs are not put here but made one by one in `take`
    blobQueue: seq[string]     ## the blobs still to send (their hashes), then blobs_end
    blobAt: int
    sendingBlobs: bool
    later: seq[JNode]          ## messages queued while blobs are being sent: they follow blobs_end
    stats*: Stats
    done*: bool
    special*: string           ## "join" / "secrets" / "enroll" when the connection was one of those

proc fail(msg: string) {.noreturn.} = raise newException(SyncError, msg)

proc send(s: Session, m: JNode) =
  if s.sendingBlobs: s.later.add m else: s.outbox.add m

proc hello(s: Session): JNode =
  newObj(@[("t", newStr("hello")), ("v", newInt(2)),
           ("root", if s.n.root.len == 0: newNull() else: newStr(s.n.root)), ("vv", s.n.vv())])

proc offer(s: Session): JNode =
  if not s.n.mayRead(s.remote):
    s.stats.denied = true
    result = newObj(@[("t", newStr("entries")), ("entries", newArr()), ("denied", newBool(true))])
    let why = s.n.revocationOf(s.remote)
    if why != nil: result["revoked"] = why
    return
  let outs = s.n.entriesFor(s.theirVv)
  s.stats.sent = outs.len
  result = newObj(@[("t", newStr("entries")), ("entries", newArr(outs))])
  let rk = s.n.memberKeyOut   # the relay room key, to a device this one serves (decision 0050)
  if rk != nil: result["relay_member"] = rk

proc wantMsg(s: Session): JNode =
  var a = newArr()
  for sha in s.n.blobWants(): a.elems.add newStr(sha)
  newObj(@[("t", newStr("want")), ("blobs", a)])

proc sendBlobs(s: Session) =
  ## The blobs the other side wants, then blobs_end. They are read and encoded in `take`, a few at a time as the
  ## platform sends them: putting every wanted blob in the outbox at once held a whole plant's drawings and photos
  ## several times over (raw, base64, framed, encrypted) for each device that needed them, and the server's memory
  ## grew to gigabytes (2026-10-09).
  if s.n.mayRead(s.remote): s.blobQueue = s.theirWant[0 ..< min(10000, s.theirWant.len)]
  s.blobAt = 0
  s.sendingBlobs = true
  s.sentBlobs = true

proc sending*(s: Session): bool =
  ## messages wait to be made (`take` again before waiting for the other side)
  s.outbox.len > 0 or s.sendingBlobs

proc take*(s: Session, budget = 1024 * 1024): seq[JNode] =
  ## The messages to send now: the outbox, then blobs until about `budget` bytes of them (at least one), blobs_end
  ## after the last. Call again while `sending`.
  result = move s.outbox
  s.outbox = @[]
  var bytes = 0
  while s.sendingBlobs and (bytes == 0 or bytes < budget):
    if s.blobAt < s.blobQueue.len:
      let sha = s.blobQueue[s.blobAt]
      inc s.blobAt
      if s.n.store.blobHas(sha):
        let data = s.n.store.blobGet(sha)
        bytes += max(1, data.len)
        result.add newObj(@[("t", newStr("blob")), ("sha", newStr(sha)), ("data", newStr(encode(data)))])
        inc s.stats.blobsSent
    else:
      result.add newObj(@[("t", newStr("blobs_end"))])
      s.sendingBlobs = false
      s.blobQueue = @[]
      result.add move(s.later)
      s.later = @[]

proc trusted*(s: Session): bool =
  ## The initiator chose its peer (TLS pinned it). The responder trusts the other side once its hello is read and it
  ## is a device this node serves (§15 mayRead).
  s.initiator or (s.stage != sHello and s.n.mayRead(s.remote))

proc frameLimit*(s: Session): int =
  ## the largest frame to accept next (issue #67)
  if s.initiator: MaxFrame
  elif s.stage == sHello: HelloFrame
  elif s.n.mayRead(s.remote): MaxFrame
  else: StrangerFrame

proc newSession*(n: Node, initiator: bool, remote: string, adoptRoot = "", hooks = Hooks()): Session =
  result = Session(n: n, initiator: initiator, remote: remote, adoptRoot: adoptRoot, hooks: hooks)
  if initiator: result.send result.hello()

proc takeHello(s: Session, m: JNode) =
  if m.get("v") == nil or m["v"].kind != jInt or m["v"].i != 2: fail("protocol version mismatch")
  let theirs = if m.get("root") != nil and m["root"].kind == jStr: m["root"].s else: ""
  if s.n.root.len == 0:
    if theirs.len == 0 or theirs != s.adoptRoot:
      fail("this device has no plant yet and the other side's plant was not the expected one")
    s.n.adopt(theirs)
  elif theirs.len > 0 and theirs != s.n.root:
    fail("the other device belongs to a different plant")
  s.theirVv = if m.get("vv") != nil and m["vv"].kind == jObj: m["vv"] else: newObj()

proc takeEntries(s: Session, m: JNode) =
  let es = if m.get("entries") != nil and m["entries"].kind == jArr: m["entries"].elems else: @[]
  s.stats.received = s.n.ingest(es, s.wall)
  discard s.n.takeMemberKey(m.get("relay_member"), s.wall)   # kept only if it is the log's current room key (0050)
  s.stats.theyDenied = m.get("denied") != nil and m["denied"].kind == jBool and m["denied"].b
  let r = m.get("revoked")
  if r != nil and s.n.acceptRevocation(r):
    if s.hooks.wipe != nil: s.hooks.wipe(s.n.revokerName(r))
    fail("this device was removed from the plant; its plant data has been deleted here")

proc takeBlob(s: Session, m: JNode) =
  let sha = m.get("sha")
  let data = m.get("data")
  if sha == nil or sha.kind != jStr or data == nil or data.kind != jStr: fail("bad blob")
  var bytes: string
  try: bytes = decode(data.s)
  except ValueError: fail("bad blob")
  if s.n.blobOffer(sha.s, bytes): inc s.stats.blobsReceived

proc receive*(s: Session, m: JNode) =
  ## One message from the other side; replies land in `outbox`. Raises SyncError (send `error` and close).
  let t = m["t"].s
  if t == "error": fail("the other side stopped: " & (if m.get("why") != nil and m["why"].kind == jStr: m["why"].s else: ""))
  if s.done: fail("message after bye")
  if not s.initiator and s.stage == sHello and t in ["join", "secrets", "enroll"]:
    s.special = t
    let h = case t
            of "join": s.hooks.join
            of "enroll": s.hooks.enroll
            else: s.hooks.secrets
    s.send(if h != nil: h(s.remote, m)
           elif t == "join": newObj(@[("t", newStr("join_ack")), ("state", newStr("unknown"))])
           elif t == "enroll": newObj(@[("t", newStr("enroll_ack")), ("state", newStr("refused")), ("why", newStr("this device does not take enrolments"))])
           else: newObj(@[("t", newStr("secrets")), ("secrets", newArr())]))
    s.done = true
    return
  case s.stage
  of sHello:
    if t != "hello": fail("expected hello, got " & t)
    s.takeHello(m)
    if not s.initiator: s.send s.hello()
    else: s.send s.offer()
    s.stage = sEntries
  of sEntries:
    if t != "entries": fail("expected entries, got " & t)
    s.takeEntries(m)
    if not s.initiator: s.send s.offer()
    else: s.send s.wantMsg()
    s.stage = sWant
  of sWant:
    if t != "want": fail("expected want, got " & t)
    for x in (if m.get("blobs") != nil and m["blobs"].kind == jArr: m["blobs"].elems else: @[]):
      if x.kind == jStr: s.theirWant.add x.s
    if not s.initiator: s.send s.wantMsg()
    if s.initiator: s.sendBlobs()
    s.stage = sBlobs
  of sBlobs:
    if t == "blob": s.takeBlob(m)
    elif t == "blobs_end":
      s.gotBlobsEnd = true
      if not s.initiator: s.sendBlobs()
      else: s.send newObj(@[("t", newStr("bye"))])
      s.stage = sBye
    else: fail("expected blob, got " & t)
  of sBye:
    if t != "bye": fail("expected bye, got " & t)
    if not s.initiator: s.send newObj(@[("t", newStr("bye"))])
    s.done = true
    s.stage = sDone
  of sDone: fail("message after bye")

proc errorMsg*(why: string): JNode = newObj(@[("t", newStr("error")), ("why", newStr(why))])
