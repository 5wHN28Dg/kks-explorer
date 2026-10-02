## Sync across the internet (PROTOCOL-v2 §18) for the server and the desktop apps: presence in the plant's room on
## the relay (a WebSocket signed in with the device key), and syncs through a relay pipe. The pipe carries the same
## TLS session as a LAN sync, so the relay sees only ciphertext. No hole punching yet: this side offers no candidates,
## which §18 says means "go straight to the pipe". Shared by Linux and Windows; runs on the node's async loop.

import std/[asyncdispatch, sets, tables, times, sysrand]
import kks/[json, crypto, util, node, sync, extras]
import net, ws
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

proc relaySetting*(n: Node): string =
  if n.run == nil: return ""
  let v = n.run.settings.getOrDefault("relay")
  if v != nil and v.kind == jStr: v.s else: ""

proc newInternet*(n: Node, id: Identity, hooks = Hooks(), relayOf: proc (): string = nil): Internet =
  result = Internet(n: n, id: id, hooks: hooks, state: "off")
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

proc changed(i: Internet) =
  if i.onChange != nil:
    try: i.onChange()
    except CatchableError: discard

proc serveConnect(i: Internet, relay, frm, id: string) {.async.} =
  ## another device asked for a sync: accept with no candidates, meet it in the pipe, answer as the TLS server
  try:
    await i.ws.sendText(toText(newObj(@[("t", newStr("accept")), ("to", newStr(frm)), ("id", newStr(id)),
                                        ("cand", newArr())])))
    let st = await i.openPipe(relay, id, "b")
    let (remote, stats) = await serveOver(i.n, i.id, st, i.hooks)
    if i.onSynced != nil: i.onSynced(remote, stats, false)
  except CatchableError as e:
    stderr.writeLine "relay: answering " & frm & " failed: " & e.msg

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
      asyncCheck i.serveConnect(relay, m["from"].s, m["id"].s)
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

proc syncPeer*(i: Internet, peer: string): Future[Stats] {.async.} =
  ## sync with a device of the plant that is on the relay: connect (no candidates), then the pipe as side a
  let relay = i.relayOf()
  if i.state != "online" or relay.len == 0: raise newException(NetError, "not on the relay")
  let id = newId()
  let f = newFuture[JNode]("relay answer")
  i.waiting[id] = f
  await i.ws.sendText(toText(newObj(@[("t", newStr("connect")), ("to", newStr(peer)), ("id", newStr(id)),
                                      ("cand", newArr())])))
  if not await withTimeout(f, 15_000):
    i.waiting.del id
    raise newException(NetError, "no answer through the relay")
  let a = f.read
  if a["t"].s != "accept": raise newException(NetError, "the device " & (if a["t"].s == "gone": "is not on the relay" else: "refused"))
  let st = await i.openPipe(relay, id, "a")
  result = await syncOver(i.n, i.id, st, peer, hooks = i.hooks)
  if i.onSynced != nil: i.onSynced(peer, result, true)
