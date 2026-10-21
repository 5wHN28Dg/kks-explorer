## A desktop device's node and its network side, shared by the GNOME app (decision 0031) and the Windows app (0033):
## the sealed store, the core's node and local API, joining a plant, and the sync service (listener, mDNS, the
## automatic rounds), all on one thread through asyncdispatch (one thread owns the node, decision 0030). The platform
## parts: crypto provider, TLS, mDNS, the storage key's home, where the device key lives, local addresses.

import std/[asyncdispatch, httpclient, os, strutils, tables, times, uri, sets, sequtils, nativesockets, selectors]
import kks/[json, util, crypto, proto, node, api, plant, sync, extras, bundle, plantdata, invites, diagnostics, model]
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
    firstModel*: Model                    ## the model built while the window was made (takeModel), nil once taken
    firstModelOf: (int, int64)            ## (entries, API revision) it was built from
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

const AppVersion* = staticRead("../../VERSION").strip   ## the program's version (VERSION at build time)

proc platformName*(): string =
  ## for diagnostics reports (§13a): the OS, nothing personal
  when defined(windows): "Windows"
  else:
    try:
      for line in readFile("/etc/os-release").splitLines:
        if line.startsWith("PRETTY_NAME="): return line[12 .. ^1].strip(chars = {'"'})
    except IOError: discard
    "Linux"

proc diag*(a: App, kind, text: string) =
  ## keep an event for the manager's diagnostics reports (decision 0040); never raises
  try: a.n.record(kind, text, int64(epochTime() * 1000))
  except CatchableError: discard

proc reportDiagnostics*(a: App, force = false): bool =
  ## a report, if the manager has them on and something new happened (at most every 6 h unless `force`)
  try: a.n.maybeReport(when defined(windows): "windows" else: "gnome", AppVersion, platformName(), "",
                       int64(epochTime() * 1000), force)
  except CatchableError: false

proc expectedFailure*(msg: string): bool =
  ## a device that is simply off or out of reach: normal, not worth a report
  let m = msg.toLowerAscii
  for s in ["could not connect", "timed out", "refused", "unreachable", "no route", "not on the relay",
            "connection closed", "is not on the relay", "no answer"]:
    if s in m: return true
  false

proc changed*(a: App, why: string) =
  for f in a.onChange: f(why)

proc dataDir*(): string =
  let x = getEnv("KKS_DATA_DIR")
  if x.len > 0: x
  elif defined(windows): getEnv("LOCALAPPDATA", getHomeDir() / "AppData" / "Local") / "Walkdown"
  else: getEnv("XDG_DATA_HOME", getHomeDir() / ".local" / "share") / "walkdown"

proc label*(): string =
  let h = getHostname()
  if h.len > 0: h[0 ..< min(80, h.len)] else: "laptop"

when defined(windows):
  proc deviceKeyName(dir: string): string =
    ## one key-store key per data folder (tests run several devices on one account)
    "kks-device-" & hex(newCngProvider().sha256(toBytes(absolutePath(dir).toLowerAscii)))[0 ..< 16]

var crashFile = ""   ## where a crash's message and stack go (the release builds keep Nim's stack traces on)

proc writeCrash(msg: string) {.nimcall, gcsafe, raises: [], tags: [WriteIOEffect].} =
  ## Nim's last words on an unhandled exception or a signal (SIGSEGV): to stderr as before, and to crash.txt, which the
  ## next start turns into a diagnostics event (decision 0040), like Android's crash.txt. Until 2026-10-05 a desktop
  ## crash left only "SIGSEGV: Illegal storage access" in the journal.
  {.cast(gcsafe).}:
    try:
      stderr.write(msg)
      if crashFile.len > 0:
        let f = open(crashFile, fmAppend)
        f.write(msg)
        f.close()
    except CatchableError: discard

let launchedAt* = epochTime()   ## (this module's start: the program's first instructions, before its window)

proc timing*(what: string) =
  ## KKS_TIMING (docs/m6/MEASUREMENTS.md): how long after launch a step of the start ended, as one line "timing:
  ## <step> <ms> ms after launch" on stderr (GNOME) or in <data dir>/timing.log (Windows: no console)
  if getEnv("KKS_TIMING").len == 0: return
  let line = "timing: " & what & " " & $int((epochTime() - launchedAt) * 1000) & " ms after launch"
  when defined(windows):
    try:
      let f = open(dataDir() / "timing.log", fmAppend)
      f.writeLine(line)
      f.close()
    except IOError: discard
  else:
    stderr.writeLine line

proc loadApp(dir: string): App =
  ## The store, the device key, the replayed log and the local API: no change anyone else sees (a first start writes
  ## the device key and the store's probe row). May run on a thread of its own (openAppInBackground).
  createDir(dir)
  crashFile = dir / "crash.txt"
  errorMessageWriter = writeCrash
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
  timing("store opened")
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
      # (in one transaction: two starts at once on a new folder keep the same key, the one the store holds)
      st.transaction(proc () =
        let again = st.getRow("keys", "node")
        if again != nil: k = keyOf(again)
        else:
          k = p.p256Generate()
          st.putRow("keys", "node", keyJson(k)))
  result = App(dir: dir, p: p, store: st, key: k)
  timing("device key")
  result.n = newNode(p, st, k)
  timing("log ready (" & $result.n.entries.len & " entries, " &
         (if result.n.stateFromSaved: "saved state read" else: "replayed") & ")")
  result.api = newApi(result.n, mode = "peer")
  result.api.deviceLabel = label()
  result.id = newIdentity(k)

proc startApp(a: App) =
  ## what only the instance that runs does, once its store is open: the last run's crash reported, changes followed
  if fileExists(crashFile):            # the last run crashed: report it (§13a), once
    try:
      let t = readFile(crashFile)
      removeFile(crashFile)
      a.diag("crash", t[max(0, t.len - 6000) .. ^1])
    except CatchableError: discard
  a.n.listeners.add proc (why: string) =
    a.nextRound = nowMs() + AfterChange
    a.changed(why)

proc openApp*(dir = dataDir()): App =
  result = loadApp(dir)
  result.startApp()


proc me*(a: App): (bool, Actor) = a.api.owner

proc saveState*(a: App) =
  ## the replayed state kept for the next start, when it changed (PROTOCOL-v2 §15b); never raises
  a.n.saveState()

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
  @[getAppDir() / "data", getAppDir() / ".." / "share" / "walkdown" / "data",
    currentSourcePath().parentDir.parentDir.parentDir / "data"]

proc file*(a: App, path: string): (bool, string) =
  ## a plant-data file of the version this device shows (§19), else the program's own data/
  result = a.n.file(path)
  if not result[0]:
    for base in programDataDirs():      # next to the program, installed, or the repo (apps/common → ../../data)
      if fileExists(base / path): return (true, readFile(base / path))

proc buildModel*(a: App, kksTables: string): Model =
  ## The plant model the screens show (the plant data files of the active version, merged with the replayed state).
  ## `kksTables`: the program's own KKS tables, used when the plant data has none.
  proc fileOr(path, dflt: string): string =
    let (ok, data) = a.file(path)
    if ok: data else: dflt
  result = Model()
  result.sheets = parseSheets(parseStrict(fileOr("sheets.json", "[]"), 4096))
  result.baseTags = parseTags(parseStrict(fileOr("tags.json", "[]"), 4096))
  result.procs = parseStrict(fileOr("procedures.json", "[]"), 4096)
  result.locations = buildLocations(parseStrict(fileOr("locations.json", "{}"), 4096))
  result.descriptions = loadDescriptions(fileOr("descriptions.json", ""), proc (msg: string) = stderr.writeLine msg)
  result.kksTables = parseStrict(fileOr("kks.json", kksTables), 4096)
  try: result.state = a.call("GET", "/api/state")
  except ApiError: result.state = newObj()
  result.merge()

proc takeModel*(a: App, kksTables: string): Model =
  ## the model built while the window was made, the first time (nothing has changed since: sync starts after the
  ## window); built now after that
  let first = move a.firstModel
  if first != nil and a.firstModelOf == (a.n.entries.len, a.api.rev): return first
  a.buildModel(kksTables)

# ---------------------------------------------------------------- opening while the window is made

type OpenError* = object of CatchableError   ## the background open failed (its message and stack trace)

var
  loader: Thread[string]
  loaderStarted = false
  loaded: App              ## the loader's result, read by the main thread only after joining it
  loadFailed: string

var loadTables: string     ## the KKS tables for the model the loader builds (openAppInBackground)

proc loadWorker(dir: string) {.thread.} =
  {.cast(gcsafe).}:
    try:
      loaded = loadApp(dir)
      if loaded.api.owner[0]:            # (joined)
        try:
          loaded.firstModelOf = (loaded.n.entries.len, loaded.api.rev)
          loaded.firstModel = loaded.buildModel(loadTables)
        except CatchableError: discard          # (built again on the main thread, which then says what is wrong)
        timing("model built")
    except CatchableError as e:
      loadFailed = $e.name & ": " & e.msg & "\n" & e.getStackTrace()
    # The App is handed to the main thread whole: this thread must leave no reference to it behind. ORC keeps
    # possible cycle roots per thread, and one left in this thread's list would be unlinked later from the main
    # thread's list (a wrong index there): collecting here empties the list (what is reachable from `loaded` stays).
    GC_runOrc()

proc openAppInBackground*(dir = dataDir(), kksTables = "{}"): bool =
  ## Starts opening the store, replaying the log and building the plant model (`takeModel`, with `kksTables`) on a
  ## thread of its own while the window is made (decision 0061): `openedApp` then waits for it. Only for a folder that
  ## already has a store (a first start makes the storage key, which two starts at once must not both do: it goes the
  ## plain way, after the app knows it is the one that runs). -> whether it started.
  if loaderStarted or not fileExists(dir / "kks.db"): return false
  loaderStarted = true
  loadTables = kksTables
  createThread(loader, loadWorker, dir)
  true

proc dropBackgroundOpen*() =
  ## a start that is not the one that runs (it handed its links over): waits for the thread, then lets go of what it
  ## opened, so the process never ends with the thread inside the store
  if loaderStarted:
    joinThread(loader)
    loaderStarted = false
    loadFailed = ""
    if loaded != nil:
      try: loaded.store.close() except CatchableError: discard
      loaded = nil

proc openedApp*(dir = dataDir()): App =
  ## The app opened by openAppInBackground (waiting for it), else opened now. Raises OpenError if the background
  ## open failed. Only the main thread calls this, once.
  if loaderStarted:
    joinThread(loader)
    loaderStarted = false
    if loadFailed.len > 0:
      let why = move loadFailed
      raise newException(OpenError, why)
    result = move loaded
    result.startApp()
  else:
    result = openApp(dir)

proc fileSha*(a: App, path: string): string =
  ## the blob (SHA-256 hex) of plant file `path` in the version shown now, "" when it has none
  let (ok, m) = a.n.active
  if ok and path in m.files: m.files[path][0] else: ""

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
  # the plant's root, as the server's setup does: without it the replay ignored the genesis (its root must be the
  # node's), so the new manager had no account here (empty details in Account, no role)
  a.n.adopt(keyString(rk.pub))
  a.changed("joined")

proc syncOne*(a: App, host: string, port: int, expectPeer: string, adoptRoot = ""): Future[Stats] {.async.} =
  ## expectPeer is checked by TLS (the certificate's key must be that device's)
  let st = await syncWith(a.n, a.id, host, port, expectPeer, adoptRoot, a.hooks)
  stderr.writeLine "sync with " & host & ":" & $port & ": sent " & $st.sent & ", received " & $st.received &
    " (photos sent " & $st.blobsSent & ", received " & $st.blobsReceived & ")"
  stderr.flushFile()        # a file when redirected: block-buffered, lost if the process is killed
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
      stderr.writeLine "sync with " & host & ":" & $port & " failed: " & e.msg
      stderr.flushFile()
      if not expectedFailure(e.msg): a.diag("sync", "sync with " & host & ":" & $port & ": " & e.msg)
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
        if not expectedFailure(e.msg): a.diag("sync", "sync through the relay: " & e.msg)
  # gone quiet: no successful sync with anyone for a day although there were devices to try
  var lastOk = 0'i64
  for _, p in a.peers: lastOk = max(lastOk, p.lastOk)
  if targets.len > 0 and lastOk > 0 and nowMs() - lastOk > 24 * 3600 * 1000:
    a.diag("sync", "no successful sync for more than 24 hours")
  discard a.reportDiagnostics()
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
           ("relay_online", newInt(if a.internet != nil: a.internet.online.len else: 0)),
           ("relay_how", newStr(if a.internet != nil: a.internet.lastHow else: "")), ("port", if a.listener != nil: newInt(a.listener.port) else: newNull())])

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
  # tests: KKS_SYNC_EVERY (ms) instead of the 2 minutes, for a page that must follow what the server just changed
  let roundEvery = max(1000, parseInt(getEnv("KKS_SYNC_EVERY", $Interval)))
  proc loop() {.async.} =
    while true:
      await sleepAsync(500)
      # not while a round runs (Sync now): that would skip this one and push the next a whole Interval away, so a
      # change made just before would wait minutes (found by the GNOME e2e test, 2026-10-03)
      if nowMs() >= a.nextRound and a.n.root.len > 0 and not a.syncing:
        a.nextRound = nowMs() + roundEvery
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
