## A desktop device's node and its network side, shared by the GNOME app (decision 0031) and the Windows app (0033):
## the sealed store, the core's node and local API, joining a plant, and the sync service (listener, mDNS, the
## automatic rounds), all on one thread through asyncdispatch (one thread owns the node, decision 0030). The platform
## parts: crypto provider, TLS, mDNS, the storage key's home, where the device key lives, local addresses.

import std/[asyncdispatch, httpclient, os, strutils, tables, times, uri, sets, sequtils, nativesockets, selectors]
import kks/[json, util, crypto, proto, node, api, plant, sync, extras, bundle, plantdata, invites]
import kksl/[dbstore, net, internet]
when defined(windows):
  import kks/provider_cng
  import kksw/[tls, mdns, keystore]
else:
  import std/posix
  import kks/provider_gnutls
  import kksl/[tls, mdns]
  import kksg/keystore

const
  SyncPortDefault* = 8421
  Interval = 120_000        ## ms between automatic rounds
  AfterChange = 5_000       ## ms after a local change

type
  PeerSeen* = object
    host*: string
    port*: int
    lastOk*: int64
    lastError*: string
    viaMdns*: bool

  App* = ref object
    dir*: string
    p*: Provider
    store*: DbStore
    n*: Node
    api*: Api
    key*: PrivateKey
    id*: Identity
    listener*: Listener
    mdns*: Mdns
    internet*: Internet                   ## presence on the plant's relay (§18)
    peers*: Table[string, PeerSeen]       ## device → where it was seen
    lastRound*: int64
    syncing*: bool
    nextRound: int64
    onChange*: seq[proc (why: string)]    ## the UI refreshes on these
    announced: string

proc nowMs*(): int64 = int64(epochTime() * 1000)

when defined(windows):
  proc localAddrs*(port: int): seq[string] =
    ## this machine's IPv4 addresses other devices could reach (its host name resolved by Winsock; not loopback or
    ## link-local), as "ip:port"
    try:
      var ai = getAddrInfo(getHostname(), Port(0), AF_INET, SOCK_STREAM, IPPROTO_TCP)
      var p = ai
      while p != nil:
        if p.ai_addr != nil:
          let sin = cast[ptr Sockaddr_in](p.ai_addr)
          let ip = $inet_ntoa(sin.sin_addr)
          let s = ip & ":" & $port
          if not ip.startsWith("127.") and not ip.startsWith("169.254.") and s notin result: result.add s
        p = p.ai_next
      freeAddrInfo(ai)
    except OSError: discard
else:
  type Ifaddrs {.importc: "struct ifaddrs", header: "<ifaddrs.h>", bycopy.} = object
    ifa_next: ptr Ifaddrs
    ifa_name: cstring
    ifa_flags: cuint
    ifa_addr: ptr SockAddr
  proc getifaddrs(ifap: ptr ptr Ifaddrs): cint {.importc, header: "<ifaddrs.h>".}
  proc freeifaddrs(ifa: ptr Ifaddrs) {.importc, header: "<ifaddrs.h>".}

  proc localAddrs*(port: int): seq[string] =
    ## this machine's IPv4 addresses other devices could reach (not loopback), as "ip:port"
    var ifs: ptr Ifaddrs
    if getifaddrs(addr ifs) != 0: return
    var p = ifs
    while p != nil:
      if p.ifa_addr != nil and p.ifa_addr.sa_family == TSa_Family(AF_INET):
        let sin = cast[ptr Sockaddr_in](p.ifa_addr)
        let ip = $inet_ntoa(sin.sin_addr)
        if not ip.startsWith("127."): result.add ip & ":" & $port
      p = p.ifa_next
    freeifaddrs(ifs)

proc keyJson(k: PrivateKey): JNode = newObj(@[("scalar", newStr(hex(k.scalar))), ("pub", newStr(b64u(k.pub)))])
proc keyOf(j: JNode): PrivateKey = PrivateKey(scalar: unhex(j["scalar"].s), pub: unb64u(j["pub"].s))

proc changed*(a: App, why: string) =
  for f in a.onChange: f(why)

proc dataDir*(): string =
  let x = getEnv("KKS_DATA_DIR")
  if x.len > 0: x
  elif defined(windows): getEnv("LOCALAPPDATA", getHomeDir() / "AppData" / "Local") / "KKS Explorer"
  else: getEnv("XDG_DATA_HOME", getHomeDir() / ".local" / "share") / "kks-explorer"

proc label*(): string =
  let h = getHostname()
  if h.len > 0: h[0 ..< min(80, h.len)] else: "laptop"

when defined(windows):
  proc deviceKeyName(dir: string): string =
    ## one key-store key per data folder (tests run several devices on one account)
    "kks-device-" & hex(newCngProvider().sha256(toBytes(absolutePath(dir).toLowerAscii)))[0 ..< 16]

proc openApp*(dir = dataDir()): App =
  createDir(dir)
  when defined(windows):
    let p = newCngProvider()
  else:
    let p = newGnuTlsProvider()
  let skey = storageKey(dir, proc (): seq[byte] = p.randomBytes(32))
  # a previous instance may still be closing the same file (the restart after a wipe): on Windows its WAL clean-up
  # made our open fail with "disk I/O error" (2026-10-01), so a failed open is retried for a moment
  var st: DbStore
  for attempt in 0 .. 10:
    try:
      st = openDbStore(p, dir / "kks.db", skey)
      break
    except CatchableError:
      if attempt == 10: raise
      sleep(300)
  var k: PrivateKey
  when defined(windows):
    # the device key stays in the CNG key store (non-exportable, decisions 0020, 0033); a wiped store makes a new one
    if st.getRow("keys", "node") == nil:
      discard p.deleteStoreKey("ncrypt:sw:" & deviceKeyName(dir))
    k = p.storeKey(false, deviceKeyName(dir))
    if st.getRow("keys", "node") == nil: st.putRow("keys", "node", newObj(@[("handle", newStr(k.handle)), ("pub", newStr(b64u(k.pub)))]))
  else:
    let j = st.getRow("keys", "node")
    if j != nil: k = keyOf(j)
    else:
      k = p.p256Generate()
      st.putRow("keys", "node", keyJson(k))
  result = App(dir: dir, p: p, store: st, key: k)
  result.n = newNode(p, st, k)
  result.api = newApi(result.n, mode = "peer")
  result.api.deviceLabel = label()
  result.id = newIdentity(k)
  let app = result
  result.n.listeners.add proc (why: string) =
    app.nextRound = nowMs() + AfterChange
    app.changed(why)

proc me*(a: App): (bool, Actor) = a.api.owner

proc removedNote*(a: App): string = a.store.getMeta("removed")
  ## set when an admin removed this device and it wiped its plant data (§15); the setup screen says so

proc hooks*(a: App): Hooks =
  ## the answers this device gives on a sync connection: §16 join (as an admin's device) and the §15 wipe
  Hooks(
    join: proc (remote: string, m: JNode): JNode =
      result = a.api.invites.offer(a.p, remote, m, nowMs() div 1000)
      if result["state"].s == "accepted":
        result["root"] = newStr(a.n.root)
        result["plant"] = a.n.run.settings.getOrDefault("plant"),
    wipe: proc (by: string) =
      a.store.wipe(if by.len > 0: "This device was removed from the plant by " & by & "." else: "This device was removed from the plant.")
      a.changed("wiped"))

proc joined*(a: App): bool = a.me[0]

proc plantName*(a: App): string =
  if a.n.run != nil and a.n.run.settings.getOrDefault("plant") != nil: a.n.run.settings["plant"].s else: ""

proc call*(a: App, meth, path: string, body: JNode = nil, q = initTable[string, string]()): JNode =
  ## The core's local API as the screens use it (same routes and JSON as the web pages). Raises ApiError.
  let (ok, me) = a.me
  if not ok: raise newException(ApiError, "this device has not joined a plant")
  let r = a.api.handle(me, meth, path, q, if body == nil: newObj() else: body, nowMs())
  if r.status >= 400:
    let e = newException(ApiError, if r.json != nil and r.json.get("error") != nil: r.json["error"].s else: "error " & $r.status)
    e.status = r.status
    raise e
  r.json

proc programDataDirs(): seq[string] =
  @[getAppDir() / "data", getAppDir() / ".." / "share" / "kks-explorer" / "data",
    currentSourcePath().parentDir.parentDir.parentDir / "data"]

proc file*(a: App, path: string): (bool, string) =
  ## a plant-data file of the version this device shows (§19), else the program's own data/
  result = a.n.file(path)
  if not result[0]:
    for base in programDataDirs():      # next to the program, installed, or the repo (apps/common → ../../data)
      if fileExists(base / path): return (true, readFile(base / path))

proc courseFiles*(a: App): (seq[(string, string)], HashSet[string]) =
  ## The course files (docs/COURSES.md) this device shows: the active plant data version's `courses/`, else the
  ## program's own data/courses (the plant has published none). → ((name, bytes), image names)
  let (ok, m) = a.n.active
  if ok:
    for path, (sha, _) in m.files:
      if path.startsWith("courses/"):
        let name = path[8 .. ^1]
        if name.endsWith(".json"): result[0].add((name, a.store.blobGet(sha)))
        elif name.endsWith(".jxl"): result[1].incl name
  if result[0].len > 0: return
  for base in programDataDirs():
    if dirExists(base / "courses"):
      for f in walkDir(base / "courses"):
        let name = f.path.extractFilename
        if f.kind != pcFile: continue
        if name.endsWith(".json"): result[0].add((name, readFile(f.path)))
        elif name.endsWith(".jxl"): result[1].incl name
      return

proc courseImage*(a: App, name: string): (bool, string) =
  ## a course picture (`courses/<name>`, JPEG XL) from the same place as the courses
  a.file("courses/" & name)

# ---------------------------------------------------------------- creating or joining a plant

proc createPlant*(a: App, plant, username, fullName: string, position: JNode) =
  ## A new plant with this laptop as the manager's device; the root key stays here (back it up: Account).
  if a.n.root.len > 0: raise newException(ValueError, "this device already belongs to a plant")
  let rk = a.p.p256Generate()
  a.store.putRow("keys", "root", keyJson(rk))
  let pid = newPersonId(a.p)
  discard a.n.append("genesis", a.p.genesisBody(rk, plant, a.n.device, pid, username, fullName, position), nowMs())
  a.changed("joined")

proc syncOne*(a: App, host: string, port: int, expectPeer: string, adoptRoot = ""): Future[Stats] {.async.} =
  ## expectPeer is checked by TLS (the certificate's key must be that device's)
  let st = await syncWith(a.n, a.id, host, port, expectPeer, adoptRoot, a.hooks)
  var p = a.peers.getOrDefault(expectPeer)
  p.host = host
  p.port = port
  p.lastOk = nowMs()
  p.lastError = ""
  a.peers[expectPeer] = p
  result = st

proc serverAddress*(text: string): (string, int) =
  ## "host", "host:port" (the sync port) or a web address (its host, the default sync port)
  let t = text.strip
  if "://" in t:
    let u = parseUri(t)
    return (u.hostname, SyncPortDefault)
  let i = t.rfind(':')
  if i > 0 and t[i + 1 .. ^1].allCharsInSet(Digits) and t[i + 1 .. ^1].len > 0: (t[0 ..< i], parseInt(t[i + 1 .. ^1]))
  else: (t, SyncPortDefault)

proc joinServer*(a: App, address, username, password: string): Future[string] {.async.} =
  ## "" when joined, else what went wrong. PROTOCOL-v2 §16 "through a server": the password goes over TLS to the
  ## server's sync port (never in clear text), then the first sync adopts the plant's root.
  if a.joined: return "this device already belongs to a plant"
  let (host, port) = serverAddress(address)
  if host.len == 0: return "enter the server's address, e.g. 192.168.1.20"
  let req = a.p.joinRequest(a.key, username, username, newNull(), label(), nowMs() div 1000)
  var ack: JNode
  try:
    ack = await ask(a.n, a.id, host, port, "", newObj(@[("t", newStr("enroll")), ("username", newStr(username)),
                                                     ("password", newStr(password)), ("request", req)]))
  except CatchableError as e:
    return "cannot reach " & host & ":" & $port & ": " & e.msg
  if ack.get("state") == nil or ack["state"].s != "accepted":
    return (if ack.get("why") != nil and ack["why"].isStr and ack["why"].s.len > 0: ack["why"].s else: "the server refused")
  try:
    discard await a.syncOne(host, port, ack["server"].s, adoptRoot = if a.n.root.len > 0: "" else: ack["root"].s)
  except CatchableError as e:
    return "the server certified this device, but syncing failed: " & e.msg & ". Try Sync now later."
  if not a.joined: return "synced, but this device is not certified in what came back"
  a.store.setMeta("sync_peers", toText(newArr(@[newStr(host & ":" & $port & "@" & ack["server"].s)])))
  a.changed("joined")
  ""

proc importBundleFile*(a: App, raw: string): string =
  try:
    discard a.n.importBundle(raw, nowMs())
  except CatchableError as e:
    return e.msg
  a.changed("bundle")
  ""

proc joinRequestFile*(a: App, username, fullName: string, position: JNode): string =
  ## the signed join request an admin imports (Manage → Devices), as a .kksjoin file's text
  toText(a.p.joinRequest(a.key, username, fullName, position, label(), nowMs() div 1000))

# ---------------------------------------------------------------- the sync service

proc txt(a: App): seq[(string, string)] =
  let rootId = if a.n.root.len > 0: a.p.peerIdOfKey(a.n.root)[0 ..< 16] else: ""
  let (ok, me) = a.me
  @[("peer", a.n.device), ("root", rootId), ("plant", a.plantName), ("label", label()),
    ("adm", if ok and me.isAdmin: "1" else: "0"), ("v", "2")]

proc announce*(a: App) =
  if a.mdns == nil or a.listener == nil: return
  let t = a.txt
  if $t == a.announced: return
  try:
    a.mdns.announce("kks-" & a.n.device[0 ..< 12], a.listener.port, t)
    a.announced = $t
  except MdnsError: discard

proc remembered(a: App): seq[(string, int, string)] =
  let raw = a.store.getMeta("sync_peers")
  if raw.len == 0: return
  for x in parseStrict(raw).elems:
    let s = x.s
    let at = s.rfind('@')
    let colon = s.rfind(':', last = at)
    if at > 0 and colon > 0:
      result.add((s[0 ..< colon], parseInt(s[colon + 1 ..< at]), s[at + 1 .. ^1]))

proc syncAll*(a: App): Future[int] {.async.} =
  ## One round: every same-plant device found by mDNS, then remembered addresses not reached yet.
  if a.syncing or a.n.root.len == 0: return 0
  a.syncing = true
  defer:
    a.syncing = false
    a.lastRound = nowMs()
  var done: HashSet[string]
  var targets: seq[(string, int, string)]
  let rootId = a.p.peerIdOfKey(a.n.root)[0 ..< 16]
  if a.mdns != nil:
    for f in a.mdns.found:
      var peer, root: string
      for (k, v) in f.txt:
        if k == "peer": peer = v
        if k == "root": root = v
      if peer.len > 0 and peer != a.n.device and root == rootId: targets.add((f.address, f.port, peer))
  targets.add a.remembered()
  let started = nowMs()
  for (host, port, peer) in targets:
    if peer in done or peer == a.n.device: continue
    try:
      discard await a.syncOne(host, port, peer)
      done.incl peer
      inc result
    except CatchableError as e:
      var p = a.peers.getOrDefault(peer)
      p.host = host
      p.port = port
      p.lastError = e.msg
      a.peers[peer] = p
  # then the devices on the relay that no LAN sync reached and that did not sync with us since the round started
  if a.internet != nil and a.internet.state == "online":
    for peer in a.internet.online.toSeq:
      if peer in done or a.peers.getOrDefault(peer).lastOk >= started: continue
      try:
        discard await a.internet.syncPeer(peer)
        inc result
      except CatchableError as e:
        var p = a.peers.getOrDefault(peer)
        p.host = "relay"
        p.lastError = e.msg
        a.peers[peer] = p
  a.changed("sync")

proc snapshot*(a: App): JNode =
  ## /api/sync/status's sync part: reachable devices, last successful sync
  var devs = newObj()
  var lastOk = 0'i64
  for d, p in a.peers:
    lastOk = max(lastOk, p.lastOk)
    devs[d] = newObj(@[("host", newStr(p.host)), ("last_ok", newInt(p.lastOk div 1000)),
                       ("error", if p.lastError.len > 0: newStr(p.lastError) else: newNull())])
  newObj(@[("devices", devs), ("last_ok", if lastOk > 0: newInt(lastOk div 1000) else: newNull()),
           ("syncing", newBool(a.syncing)),
           ("relay", newStr(if a.internet != nil: a.internet.state else: "off")),
           ("relay_online", newInt(if a.internet != nil: a.internet.online.len else: 0)), ("port", if a.listener != nil: newInt(a.listener.port) else: newNull())])

proc startSync*(a: App, port = SyncPortDefault, discovery = true) =
  ## Listener (the next free port from `port`), mDNS announce + browse, and the automatic rounds.
  var p = port
  for i in 0 .. 20:
    try:
      a.listener = listen(a.n, a.id, p, hooks = a.hooks)
      break
    except CatchableError:
      inc p
  a.api.syncPort = if a.listener != nil: a.listener.port else: 0
  a.api.syncSnapshot = proc (): JNode = a.snapshot
  a.api.addresses = proc (): seq[string] = localAddrs(a.api.syncPort)
  if a.listener != nil:
    a.listener.onDone = proc (remote: string, st: Stats) =
      var pr = a.peers.getOrDefault(remote)
      pr.lastOk = nowMs()
      a.peers[remote] = pr
      a.changed("sync")
  a.internet = newInternet(a.n, a.id, a.hooks)
  a.internet.onSynced = proc (remote: string, st: Stats, initiator: bool) =
    var pr = a.peers.getOrDefault(remote)
    pr.host = "relay"
    pr.port = 0
    pr.lastOk = nowMs()
    pr.lastError = ""
    a.peers[remote] = pr
    a.changed("sync")
  var seen = 0
  a.internet.onChange = proc () =
    if a.internet.online.len > seen: a.nextRound = min(a.nextRound, nowMs() + 1000)   # a device came online
    seen = a.internet.online.len
    a.changed("relay")
  a.internet.start()
  a.api.relayChanged = proc () = a.internet.restart()
  if discovery:
    try:
      a.mdns = newMdns()
      a.mdns.browse()
      a.announce()
      a.mdns.onFound = proc (f: Found) = a.nextRound = min(a.nextRound, nowMs() + 1000)
      a.onChange.add proc (why: string) = a.announce()
    except MdnsError: a.mdns = nil
  a.nextRound = nowMs() + 2000
  proc loop() {.async.} =
    while true:
      await sleepAsync(500)
      if nowMs() >= a.nextRound and a.n.root.len > 0:
        a.nextRound = nowMs() + Interval
        discard await a.syncAll()
  asyncCheck loop()

proc pumpAsync*() =
  ## Run whatever asyncdispatch has ready, without blocking (called from GLib).
  if hasPendingOperations(): poll(0)

when not defined(windows):
  proc asyncFd*(): int = int(getGlobalDispatcher().getIoHandler().getFd())

# ---------------------------------------------------------------- joining by invite or through an admin nearby (§16)

proc joinCode*(a: App, admin: string): string = a.p.joinCode(a.n.device, admin)

proc askJoin*(a: App, host: string, port: int, peer: string, token: JNode, request: JNode): Future[JNode] {.async.} =
  ## one §16 question: {"t":"join", token, request} → the join_ack
  result = await ask(a.n, a.id, host, port, peer, newObj(@[("t", newStr("join")), ("token", token), ("request", request)]))

proc parseInvite*(text: string): (bool, JNode) =
  try:
    let j = parseStrict(text.strip)
    if j.kind == jObj and j.get("kks_invite") != nil and j.get("peer") != nil and j.get("addrs") != nil and
       j.get("token") != nil and j.get("root") != nil: return (true, j)
  except JsonError: discard
  (false, nil)

proc adminsNearby*(a: App): seq[Found] =
  ## devices on this Wi-Fi that announce an admin (adm=1); empty without mDNS
  if a.mdns == nil: return
  for f in a.mdns.found:
    var adm, peer = ""
    for (k, v) in f.txt:
      if k == "adm": adm = v
      if k == "peer": peer = v
    if adm == "1" and peer.len > 0 and peer != a.n.device: result.add f
