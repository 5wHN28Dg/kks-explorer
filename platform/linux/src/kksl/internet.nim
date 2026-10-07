## Sync across the internet (PROTOCOL-v2 §18) for the server and the desktop apps: presence in the plant's room on
## the relay (a WebSocket signed in with the device key), and syncs directly when hole punching works (udp.nim: STUN,
## punching, reliable UDP), else through a relay pipe. Either way the stream carries the same TLS session as a LAN
## sync, so the relay sees only ciphertext. A device that sends no candidates (§18: `cand: []`) gets the pipe at once.
## Shared by Linux and Windows; runs on the node's async loop.

import std/[asyncdispatch, sets, strutils, tables, times, sysrand]
import kks/[json, crypto, util, node, sync, extras]
import net, ws, udp
when defined(windows): import kksw/tls
else: import tls

type
  Internet* = ref object
    n: Node
    id: Identity
    hooks: Hooks
    relayOf: proc (): string          ## the plant's relay setting ("" = off)
    online*: HashSet[string]          ## devices of the plant on the relay now
    state*: string                    ## "off", "connecting", "online", or an error
    ws: Ws
    room: string
    waiting: Table[string, Future[JNode]]
    running: bool
    onSynced*: proc (remote: string, stats: Stats, initiator: bool)   ## after each sync through the relay
    onChange*: proc ()                ## presence changed (the status line)
    direct*: bool                     ## try hole punching first (tests turn it off to force the pipe)
    stunServers*: seq[(string, int)]  ## empty = no public candidate (only this machine's own addresses)
    lastHow*: string                  ## "direct" or "relay": how the last sync went (for the status)
    noDirectUntil*: Table[string, float]   ## devices the direct path failed with: the pipe until then (epoch s)
    testStall*: bool                  ## tests: the direct path punches through, then fails, like stalled paths in the field
    testNoPath*: bool                 ## tests: the punch hears nothing, like two NATs that can't be punched
    serving*: int                     ## syncs answered through the relay now (at most MaxServed, issue #67)

proc relaySetting*(n: Node): string =
  if n.run == nil: return ""
  let v = n.run.settings.getOrDefault("relay")
  if v != nil and v.kind == jStr: v.s else: ""

proc newInternet*(n: Node, id: Identity, hooks = Hooks(), relayOf: proc (): string = nil): Internet =
  result = Internet(n: n, id: id, hooks: hooks, state: "off", direct: true, stunServers: @Stun)
  let nn = n
  result.relayOf = if relayOf != nil: relayOf else: (proc (): string = relaySetting(nn))

proc newId(): string =
  var b: array[16, byte]
  if not urandom(b): raise newException(CatchableError, "no randomness")
  hex(b)

proc pipeStream(w: Ws): Stream =
  ## a relay pipe as a byte stream: each binary message is a piece of the TLS stream
  Stream(write: proc (data: string): Future[void] = w.sendBinary(data),
         read: proc (): Future[string] {.async.} =
           try:
             while true:
               let m = await w.recv()
               if m.binary: return m.data
           except WsError: return "",
         close: proc () = w.close())

proc openPipe(i: Internet, relay, id, side: string): Future[Stream] {.async.} =
  let w = await wsConnect(relay & "/v1/pipe/" & i.room & "/" & id & "/" & side)
  pipeStream(w)

proc candidates(i: Internet, tryDirect = true): Future[(Udp, seq[string])] {.async.} =
  ## a UDP socket and its candidates: the public address from STUN, then this machine's own (at most 8)
  if not i.direct or not tryDirect: return (nil, newSeq[string]())
  let u = newUdp()
  var cand: seq[string]
  let pub = if i.stunServers.len > 0: await u.stun(i.stunServers) else: ""
  if pub.len > 0: cand.add pub
  for ip in localIPv4s():
    if cand.len < 8: cand.add ip & ":" & $u.port
  return (u, cand)

proc candArr(c: seq[string]): JNode =
  result = newArr()
  for x in c: result.elems.add newStr(x)

proc theirCands(m: JNode): seq[string] =
  let c = m.get("cand")
  if c != nil and c.kind == jArr:
    for x in c.elems:
      if x.kind == jStr and x.s.len <= 64 and result.len < 8: result.add x.s

type DirectStalled = object of NetError   ## the test switch: a direct path that punched, then stalled

proc meet(i: Internet, u: Udp, ours, theirs: seq[string], relay, id, side, peer: string): Future[(Stream, string)] {.async.} =
  ## §18: hole punching when both sides offered candidates, else (or when it fails) the relay pipe. -> the stream and
  ## how it goes ("direct" or "relay"): each sync's own, for its fallback (lastHow is only the status line's: a sync
  ## answered meanwhile could overwrite it)
  if u != nil and ours.len > 0 and theirs.len > 0:
    var session = ""
    for k in 0 ..< 8: session.add char(parseHexInt(id[k * 2 .. k * 2 + 1]))
    let pr = if i.testNoPath: (u.close(); PunchResult()) else: await u.punch(session, theirs)
    stderr.writeLine "direct: ours " & $ours & ", theirs " & $theirs & " → heard " & $pr.heard &
                     (if pr.host.len > 0: ", using " & pr.host & ":" & $pr.port & (if pr.confirmed: " (answered)" else: " (heard only)")
                      else: ", no path") & " in " & $pr.ms & " ms"
    stderr.flushFile()
    if pr.host.len > 0:
      i.lastHow = "direct"
      if i.testStall:
        u.close()
        raise newException(DirectStalled, "the other device stopped answering (test: stalled direct path)")
      return (u.rudpStream(pr.host, pr.port, session), "direct")
    # nothing came through: two NATs that can't be punched (2026-10-04: a carrier NAT with a new port per destination
    # against a home router that only lets in the exact address it sent to). Don't spend the 4 s on this device for
    # an hour.
    if peer.len > 0: i.noDirectUntil[peer] = epochTime() + 3600
  if u != nil: u.close()
  i.lastHow = "relay"
  return (await i.openPipe(relay, id, side), "relay")

proc changed(i: Internet) =
  if i.onChange != nil:
    try: i.onChange()
    except CatchableError: discard

const MaxServed* = 8   ## syncs answered through the relay at once: anyone with a key can ask (issue #67, #30)

proc serveConnect(i: Internet, relay, frm, id: string, theirs: seq[string]) {.async.} =
  ## another device asked for a sync: accept with our candidates, meet it (directly or in the pipe), answer as the
  ## TLS server
  if i.serving >= MaxServed:
    try: await i.ws.sendText(toText(newObj(@[("t", newStr("refuse")), ("to", newStr(frm)), ("id", newStr(id))])))
    except CatchableError: discard
    return
  inc i.serving
  try:
    let (u, ours) = await i.candidates(epochTime() >= i.noDirectUntil.getOrDefault(frm, 0.0))   # [] = the pipe at once
    await i.ws.sendText(toText(newObj(@[("t", newStr("accept")), ("to", newStr(frm)), ("id", newStr(id)),
                                        ("cand", candArr(ours))])))
    let (st, _) = await i.meet(u, ours, theirs, relay, id, "b", frm)
    let (remote, stats) = await serveOver(i.n, i.id, st, i.hooks)
    if i.onSynced != nil: i.onSynced(remote, stats, false)
  except CatchableError as e:
    stderr.writeLine "relay: answering " & frm & " failed: " & e.msg
  finally:
    dec i.serving

proc handle(i: Internet, relay: string, m: JNode) =
  let t = if m.get("t") != nil and m["t"].kind == jStr: m["t"].s else: ""
  case t
  of "welcome":
    i.online.clear()
    for p in m["peers"].elems: i.online.incl p.s
    i.state = "online"
    i.changed()
  of "joined":
    i.online.incl m["peer"].s
    i.changed()
  of "left":
    i.online.excl m["peer"].s
    i.changed()
  of "connect":
    if m.get("from") != nil and m.get("id") != nil:
      asyncCheck i.serveConnect(relay, m["from"].s, m["id"].s, theirCands(m))
  of "accept", "refuse", "gone":
    let id = if m.get("id") != nil: m["id"].s else: ""
    if id in i.waiting:
      let f = i.waiting[id]
      i.waiting.del id
      if not f.finished: f.complete(m)
  of "error":
    i.state = "relay error: " & (if m.get("why") != nil: m["why"].s else: "?")
    i.changed()
  else: discard

proc presence(i: Internet) {.async.} =
  ## stay in the plant's room while running; reconnect with a growing pause after failures
  var pause = 5_000
  while i.running:
    let relay = i.relayOf()
    if relay.len == 0 or i.n.root.len == 0:
      if i.state != "off":
        i.state = "off"
        i.online.clear()
        i.changed()
      await sleepAsync(10_000)
      continue
    i.room = relayRoom(i.n.p, i.n.root)
    i.state = "connecting"
    try:
      i.ws = await wsConnect(relay & "/v1/room/" & i.room)
      await i.ws.sendText(toText(relayHello(i.n.p, i.n.key, i.room, int64(epochTime()))))
      pause = 5_000
      var lastIn = epochTime()
      proc ping() {.async.} =
        let w = i.ws
        while i.running and not w.closed:
          await sleepAsync(25_000)
          if not w.closed and epochTime() - lastIn > 20:
            try: await w.sendText("""{"t":"ping"}""")
            except CatchableError: break
      asyncCheck ping()
      while i.running and i.relayOf() == relay:
        let msg = await i.ws.recv()
        lastIn = epochTime()
        if not msg.binary:
          try: i.handle(relay, parseStrict(msg.data))
          except CatchableError: discard
      i.ws.close()
    except CatchableError as e:
      i.state = "relay unreachable: " & e.msg
      i.online.clear()
      i.changed()
      if i.ws != nil: i.ws.close()
      await sleepAsync(pause)
      pause = min(pause * 2, 60_000)

proc start*(i: Internet) =
  if not i.running:
    i.running = true
    asyncCheck i.presence()

proc restart*(i: Internet) =
  ## the relay setting changed: leave the room now; the presence loop comes back with the new address
  if i.ws != nil: i.ws.close()

proc stop*(i: Internet) =
  i.running = false
  if i.ws != nil: i.ws.close()

proc openTo(i: Internet, peer: string, tryDirect = true): Future[(Stream, string)] {.async.} =
  ## a stream to a device in the room: connect with our candidates, then direct or the pipe (side a)
  let relay = i.relayOf()
  i.lastHow = ""
  if i.state != "online" or relay.len == 0: raise newException(NetError, "not on the relay")
  let id = newId()
  let f = newFuture[JNode]("relay answer")
  i.waiting[id] = f
  let (u, ours) = await i.candidates(tryDirect)
  await i.ws.sendText(toText(newObj(@[("t", newStr("connect")), ("to", newStr(peer)), ("id", newStr(id)),
                                      ("cand", candArr(ours))])))
  if not await withTimeout(f, 15_000):
    i.waiting.del id
    if u != nil: u.close()
    raise newException(NetError, "no answer through the relay")
  let a = f.read
  if a["t"].s != "accept":
    if u != nil: u.close()
    raise newException(NetError, "the device " & (if a["t"].s == "gone": "is not on the relay" else: "refused"))
  return await i.meet(u, ours, theirCands(a), relay, id, "a", peer)

proc syncPeer*(i: Internet, peer: string): Future[Stats] {.async.} =
  ## sync with a device of the plant that is on the relay. A direct path can punch through and then stall (found
  ## 2026-10-03 with two phones on mobile data), so a failed direct sync runs again at once through the pipe, and that
  ## device gets the pipe for an hour (PROTOCOL-v2 §18: "on failure, the pipe").
  let tryDirect = epochTime() >= i.noDirectUntil.getOrDefault(peer, 0.0)
  var failed = ""
  var how = ""
  try:
    let (st, h) = await i.openTo(peer, tryDirect)
    how = h
    result = await syncOver(i.n, i.id, st, peer, hooks = i.hooks)
  except CatchableError as e:
    if how != "direct" and not (e of DirectStalled): raise
    failed = e.msg
  if failed.len > 0:
    i.noDirectUntil[peer] = epochTime() + 3600
    stderr.writeLine "direct sync with " & peer[0 ..< min(8, peer.len)] & " failed (" & failed & "): the relay pipe for this device for an hour"
    let (st, _) = await i.openTo(peer, false)
    result = await syncOver(i.n, i.id, st, peer, hooks = i.hooks)
  if i.onSynced != nil: i.onSynced(peer, result, true)

proc askPeer*(i: Internet, peer: string, msg: JNode, expectPeer = ""): Future[JNode] {.async.} =
  ## one question instead of a sync (§16) to a device in the room
  let (st, _) = await i.openTo(peer)
  result = await askOver(i.n, i.id, st, expectPeer, msg)
