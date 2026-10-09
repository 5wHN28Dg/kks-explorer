## A WebSocket client (RFC 6455) for the relay (PROTOCOL-v2 §18): `ws://` over TCP, `wss://` over web TLS (the
## system's CAs and the host name, tls.newWebTlsConn). Async, on the node's loop. Small on purpose: text and binary
## messages, ping/pong, close; fragmented messages are joined. Shared by Linux and Windows (decision 0033).

import std/[asyncdispatch, asyncnet, base64, net, strutils, uri, sysrand]
when defined(windows): import kksw/tls
else: import tls

type
  WsError* = object of CatchableError
  WsMsg* = object
    binary*: bool
    data*: string
  Ws* = ref object
    sock: AsyncSocket
    tls: TlsConn           ## nil for ws://
    inbuf: string          ## received bytes (plaintext), not yet framed
    closed*: bool

# ---------------------------------------------------------------- SHA-1 (only for Sec-WebSocket-Accept)

proc sha1(s: string): string =
  var h = [0x67452301'u32, 0xEFCDAB89'u32, 0x98BADCFE'u32, 0x10325476'u32, 0xC3D2E1F0'u32]
  var m = s
  let bits = uint64(s.len) * 8
  m.add '\x80'
  while m.len mod 64 != 56: m.add '\0'
  for i in countdown(7, 0): m.add char((bits shr (8 * i)) and 0xff)
  template rol(x: uint32, n: int): uint32 = (x shl n) or (x shr (32 - n))
  for chunk in 0 ..< m.len div 64:
    var w: array[80, uint32]
    for i in 0 ..< 16:
      let o = chunk * 64 + i * 4
      w[i] = (uint32(m[o].uint8) shl 24) or (uint32(m[o + 1].uint8) shl 16) or (uint32(m[o + 2].uint8) shl 8) or uint32(m[o + 3].uint8)
    for i in 16 ..< 80: w[i] = rol(w[i - 3] xor w[i - 8] xor w[i - 14] xor w[i - 16], 1)
    var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
    for i in 0 ..< 80:
      var f, k: uint32
      if i < 20: (f, k) = ((b and c) or ((not b) and d), 0x5A827999'u32)
      elif i < 40: (f, k) = (b xor c xor d, 0x6ED9EBA1'u32)
      elif i < 60: (f, k) = ((b and c) or (b and d) or (c and d), 0x8F1BBCDC'u32)
      else: (f, k) = (b xor c xor d, 0xCA62C1D6'u32)
      let t = rol(a, 5) + f + e + k + w[i]
      e = d; d = c; c = rol(b, 30); b = a; a = t
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e
  for x in h:
    for i in countdown(3, 0): result.add char((x shr (8 * i)) and 0xff)

# ---------------------------------------------------------------- transport (plain or TLS)

proc rawRecv(w: Ws): Future[string] {.async.} =
  ## some plaintext bytes; "" when the connection closed
  while true:
    if w.tls != nil:
      let plain = w.tls.recv()
      if plain.len > 0: return plain
      if w.tls.closed: return ""
    let got = await w.sock.recv(16384)
    if got.len == 0: return ""
    if w.tls == nil: return got
    w.tls.feed(got)

proc rawSend(w: Ws, data: string) {.async.} =
  if w.tls == nil:
    await w.sock.send(data)
    return
  w.tls.send(data)
  let o = w.tls.takeOut()
  if o.len > 0: await w.sock.send(o)

proc need(w: Ws, n: int) {.async.} =
  while w.inbuf.len < n:
    let got = await w.rawRecv()
    if got.len == 0:
      w.closed = true
      raise newException(WsError, "connection closed")
    w.inbuf.add got

# ---------------------------------------------------------------- frames

proc sendFrame(w: Ws, opcode: int, payload: string) {.async.} =
  var f = newStringOfCap(payload.len + 14)
  f.add char(0x80 or opcode)
  let n = payload.len
  if n < 126: f.add char(0x80 or n)
  elif n < 65536:
    f.add char(0x80 or 126)
    f.add char(n shr 8); f.add char(n and 0xff)
  else:
    f.add char(0x80 or 127)
    for i in countdown(7, 0): f.add char((uint64(n) shr (8 * i)) and 0xff)
  var mask: array[4, byte]
  if not urandom(mask): raise newException(WsError, "no randomness")
  for b in mask: f.add char(b)
  let start = f.len
  f.setLen(start + n)
  for i in 0 ..< n: f[start + i] = char(uint8(payload[i]) xor mask[i mod 4])
  await w.rawSend(f)

proc sendText*(w: Ws, s: string): Future[void] = w.sendFrame(1, s)
proc sendBinary*(w: Ws, s: string): Future[void] = w.sendFrame(2, s)

proc recv*(w: Ws): Future[WsMsg] {.async.} =
  ## the next text or binary message (pings are answered here). Raises WsError when the connection ends.
  var msg = ""
  var binary = false
  while true:
    await w.need(2)
    let b0 = uint8(w.inbuf[0])
    let b1 = uint8(w.inbuf[1])
    var n = int(b1 and 0x7f)
    var hdr = 2
    if n == 126:
      await w.need(4)
      n = (int(uint8(w.inbuf[2])) shl 8) or int(uint8(w.inbuf[3]))
      hdr = 4
    elif n == 127:
      await w.need(10)
      n = 0
      for i in 2 .. 9: n = (n shl 8) or int(uint8(w.inbuf[i]))
      hdr = 10
    if (b1 and 0x80) != 0: raise newException(WsError, "a masked frame from the server")
    if n > 16 shl 20: raise newException(WsError, "message too large")
    await w.need(hdr + n)
    let payload = w.inbuf[hdr ..< hdr + n]
    w.inbuf = w.inbuf[hdr + n .. ^1]
    let opcode = int(b0 and 0x0f)
    case opcode
    of 0, 1, 2:
      if opcode == 2: binary = true
      msg.add payload
      if (b0 and 0x80) != 0: return WsMsg(binary: binary, data: msg)
    of 8:
      w.closed = true
      try: await w.sendFrame(8, payload[0 ..< min(2, payload.len)])
      except CatchableError: discard
      raise newException(WsError, "closed by the server")
    of 9: await w.sendFrame(10, payload)
    else: discard   # pong, unknown

proc close*(w: Ws) =
  if not w.closed:
    w.closed = true
    asyncCheck (proc () {.async.} =
      try: await w.sendFrame(8, "\x03\xe8")
      except CatchableError: discard
      if w.tls != nil: w.tls.close()
      w.sock.close())()

# ---------------------------------------------------------------- connecting

proc connectInner(url: string, timeout: int): Future[Ws] {.async.}

proc wsConnect*(url: string, timeout = 15_000): Future[Ws] {.async.} =
  ## `ws://host[:port]/path` or `wss://…`; the HTTP upgrade is checked (101 and Sec-WebSocket-Accept). The whole
  ## connect (TCP, TLS, upgrade) is bounded by `timeout`: a relay that stops answering halfway must not hang us.
  let f = connectInner(url, timeout)
  if not await withTimeout(f, timeout):
    f.addCallback(proc () =
      if not f.failed: f.read.close())     # finished after all: don't leak the connection
    raise newException(WsError, "the relay did not answer in time")
  result = f.read

proc connectInner(url: string, timeout: int): Future[Ws] {.async.} =
  let u = parseUri(url)
  let secure = u.scheme == "wss"
  if u.scheme notin ["ws", "wss"] or u.hostname.len == 0: raise newException(WsError, "not a WebSocket address: " & url)
  # ws:// only to this machine (tests' relay twin); the relay's presence traffic is never sent in clear (#15)
  if not secure and u.hostname notin ["127.0.0.1", "localhost", "::1"]:
    raise newException(WsError, "the relay must be a wss:// address (ws:// only to this machine)")
  var port = if secure: 443 else: 80
  if u.port.len > 0:
    # a bad port is the setting's fault, not a crash: Port(99999) raised a RangeDefect nothing caught
    port = try: parseInt(u.port) except ValueError: 0
    if port < 1 or port > 65535: raise newException(WsError, "not a valid port in the relay address: " & url)
  let w = Ws(sock: await asyncnet.dial(u.hostname, Port(port), buffered = false))   # IPv4 or IPv6; wsConnect bounds the time
  if secure:
    w.tls = newWebTlsConn(u.hostname)
    while true:
      # send what each step produced before waiting: in TLS 1.2 the client's second flight must go out before the
      # server answers (sending only at the top of the loop hung on Windows 10, 2026-10-02)
      let done = w.tls.handshake()
      let o = w.tls.takeOut()
      if o.len > 0: await w.sock.send(o)
      if done: break
      let got = await w.sock.recv(16384)
      if got.len == 0: raise newException(WsError, "TLS: the server closed the connection")
      w.tls.feed(got)
  var keyBytes: array[16, byte]
  if not urandom(keyBytes): raise newException(WsError, "no randomness")
  var kraw = ""
  for b in keyBytes: kraw.add char(b)
  let key = encode(kraw)
  let path = (if u.path.len > 0: u.path else: "/") & (if u.query.len > 0: "?" & u.query else: "")
  let host = u.hostname & (if u.port.len > 0: ":" & u.port else: "")
  await w.rawSend("GET " & path & " HTTP/1.1\r\nHost: " & host & "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" &
                  "Sec-WebSocket-Key: " & key & "\r\nSec-WebSocket-Version: 13\r\n\r\n")
  while "\r\n\r\n" notin w.inbuf:
    let got = await w.rawRecv()
    if got.len == 0: raise newException(WsError, "no answer to the upgrade")
    w.inbuf.add got
    if w.inbuf.len > 16384: raise newException(WsError, "answer too long")
  let endAt = w.inbuf.find("\r\n\r\n")
  let head = w.inbuf[0 ..< endAt]
  w.inbuf = w.inbuf[endAt + 4 .. ^1]
  let lines = head.split("\r\n")
  if lines.len == 0 or not lines[0].startsWith("HTTP/1.1 101"):
    raise newException(WsError, "the relay refused: " & (if lines.len > 0: lines[0] else: "?"))
  let want = encode(sha1(key & "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
  var ok = false
  for l in lines[1 .. ^1]:
    let c = l.find(':')
    if c > 0 and l[0 ..< c].strip.toLowerAscii == "sec-websocket-accept" and l[c + 1 .. ^1].strip == want: ok = true
  if not ok: raise newException(WsError, "bad Sec-WebSocket-Accept")
  w
