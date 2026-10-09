## The always-on server (decision 0026): the core's node and API behind HTTP for browser clients, password accounts
## (Argon2id), the sync listener. Same routes, cookie and headers as v1's app.py in server mode, so the web pages work
## unchanged. One thread owns the node (decision 0030).

import std/[asyncdispatch, asyncnet, base64, nativesockets, os, osproc, posix, strutils, tables, times, uri, sets, algorithm, sequtils]
import kks/[json, util, crypto, proto, replay, node, sync, plant, api, plantdata, bundle, extras, invites, courses, diagnostics, relaykey]
import kks/provider_gnutls
import dbstore, tls, net, argon2, mdns, internet, httpserver, throttle

const
  Cookie = "kks_session"
  MinPassword = 10
  Shell = {"/": "index.html", "/index.html": "index.html", "/admin.html": "admin.html", "/common.js": "common.js", "/tiles.js": "tiles.js", "/dark.js": "dark.js", "/systems.js": "systems.js",
           "/course-bridge.js": "course-bridge.js", "/learning.html": "learning.html",
           "/course.html": "course.html", "/course.js": "course.js", "/course-figure.js": "course-figure.js",
           "/index.js": "index.js", "/admin.js": "admin.js", "/learning.js": "learning.js",
           "/course.css": "course.css", "/kks-wasm.js": "kks-wasm.js", "/kks-wasm-worker.js": "kks-wasm-worker.js",
           "/sw.js": "sw.js", "/manifest.webmanifest": "manifest.webmanifest", "/icon.svg": "icon.svg",
           "/icon-192.png": "icon-192.png", "/icon-512.png": "icon-512.png"}.toTable

type
  Config* = object
    address*: string           ## HTTP listen address (127.0.0.1 behind a tunnel)
    port*: int
    syncPort*: int             ## 0 = off
    publicUrl*: string
    secureCookies*: bool       ## also on whenever publicUrl is https
    trustedProxy*: bool        ## the HTTPS proxy in front appends the browser's address to X-Forwarded-For
    plantName*: string
    sessionDays*: int
    offlineDays*: int
    maxUploadMb*: int
    webDir*: string            ## the web UI (index.html, …)
    dataDir*: string           ## the program's own data/ (kks.json, courses)
    storePath*: string
    plantDir*: string          ## the manager's plant-data working copy (Drawings writes here, then publishes)
    backupDir*: string         ## sheet backups before each import/removal, uploaded PDFs
    importer*: string          ## the kks-import program (decision 0026)
    glyphs*: string            ## its glyph library, when not next to it
    maxPdfMb*: int
    importTimeoutS*: int       ## an import is stopped after this long (issue #34)
    importMemoryMb*: int       ## the importer's address-space limit (RLIMIT_AS; a large sheet peaks near 1.8 GB RSS)

  Server* = ref object
    cfg*: Config
    p*: Provider
    store*: DbStore
    n*: Node
    api*: Api
    id*: Identity
    fails: Throttle               ## failed password and token checks (issue #39)
    listener*: Listener
    mdns*: Mdns
    internet*: Internet           ## presence on the plant's relay (§18), answers syncs through it
    internetPrev*: Internet       ## presence in the previous room for a week after a rotation (decision 0050)
    announced: string
    job*: JNode                ## the drawing import running or last run (one at a time)
    courseCache: (string, JNode)   ## (what the list was built from, the list)

  HttpErr = object of CatchableError
    code: int

proc isLoopback*(address: string): bool =
  ## the web listener's address must be this machine's own (finding #26: no plain-HTTP sign-in on the network)
  ## (IPv4 only: the listener is an IPv4 socket, so "::1" could not be bound anyway)
  let a = address.strip.toLowerAscii
  let parts = a.split('.')
  a == "localhost" or (parts.len == 4 and parts[0] == "127" and
    parts.allIt(it.len in 1..3 and it.allCharsInSet(Digits) and (it.len == 1 or it[0] != '0') and parseInt(it) <= 255))

proc defaultConfig*(): Config =
  Config(address: "127.0.0.1", port: 8420, syncPort: 8421, plantName: "Walkdown", sessionDays: 30,
         offlineDays: 3, maxUploadMb: 15, plantDir: "plant-data", backupDir: "backups", maxPdfMb: 50,
         importer: getAppDir() / "kks-import", importTimeoutS: 1800, importMemoryMb: 6144)

proc loadConfig*(path: string): Config =
  result = defaultConfig()
  if path.len == 0 or not fileExists(path): return
  let j = parseStrict(readFile(path))
  proc s(k: string, d: string): string = (if j.get(k) != nil and j[k].isStr: j[k].s else: d)
  proc i(k: string, d: int): int = (if j.get(k) != nil and j[k].kind == jInt: int(j[k].i) else: d)
  proc b(k: string, d: bool): bool = (if j.get(k) != nil and j[k].kind == jBool: j[k].b else: d)
  result.address = s("address", result.address).strip.toLowerAscii   # what is checked is what is bound
  if not isLoopback(result.address):
    raise newException(ValueError, "\"address\": \"" & result.address & "\" would serve the web pages and their " &
      "sign-in over plain HTTP to the network (finding #26). The web listener stays on this machine: use 127.0.0.1, " &
      "and reach it from elsewhere only through an HTTPS reverse proxy or tunnel to it, with \"public_url\" set to " &
      "its https:// address (and \"trusted_proxy\": true if the proxy appends the browser's address to " &
      "X-Forwarded-For). Devices sync over TLS on the sync port, which listens on every interface.")
  result.port = i("port", result.port)
  result.syncPort = i("sync_port", result.syncPort)
  result.publicUrl = s("public_url", "").strip
  if result.publicUrl.len > 0:
    if not result.publicUrl.toLowerAscii.startsWith("https://"):
      raise newException(ValueError, "\"public_url\": \"" & result.publicUrl & "\" must be an https:// address: " &
        "browsers reach the web pages only through an HTTPS proxy or tunnel (finding #26).")
    # one spelling, as browsers send it in Host and Origin: lower-case scheme and host, no default port
    let pu = parseUri(result.publicUrl)
    result.publicUrl = "https://" & pu.hostname.toLowerAscii & (if pu.port.len > 0 and pu.port != "443": ":" & pu.port else: "") &
      pu.path & (if pu.query.len > 0: "?" & pu.query else: "")
  result.secureCookies = b("secure_cookies", false)
  result.trustedProxy = b("trusted_proxy", false)
  result.plantName = s("plant_name", result.plantName)
  result.sessionDays = i("session_days", result.sessionDays)
  result.offlineDays = i("offline_days", result.offlineDays)
  result.maxUploadMb = i("max_upload_mb", result.maxUploadMb)
  result.webDir = s("web_dir", "")
  result.dataDir = s("data_dir", "")
  result.storePath = s("store", "")
  result.plantDir = s("plant_dir", result.plantDir)
  result.backupDir = s("backup_dir", result.backupDir)
  result.importer = s("importer", result.importer)
  result.glyphs = s("glyphs", "")
  result.maxPdfMb = i("max_pdf_mb", result.maxPdfMb)
  result.importTimeoutS = i("import_timeout_s", result.importTimeoutS)
  result.importMemoryMb = i("import_memory_mb", result.importMemoryMb)
  if result.importTimeoutS < 1: raise newException(ValueError, "import_timeout_s must be 1 or more")
  if result.importMemoryMb < 256: raise newException(ValueError, "import_memory_mb must be 256 or more")

proc herr(code: int, msg: string) {.noreturn.} =
  let e = newException(HttpErr, msg)
  e.code = code
  raise e

proc nowMs(): int64 = int64(epochTime() * 1000)
proc nowS(): int64 = int64(epochTime())

type Ifaddrs {.importc: "struct ifaddrs", header: "<ifaddrs.h>", bycopy.} = object
  ifa_next: ptr Ifaddrs
  ifa_name: cstring
  ifa_flags: cuint
  ifa_addr: ptr SockAddr
proc getifaddrs(ifap: ptr ptr Ifaddrs): cint {.importc, header: "<ifaddrs.h>".}
proc freeifaddrs(ifa: ptr Ifaddrs) {.importc, header: "<ifaddrs.h>".}

proc localAddrs(port: int): seq[string] =
  ## this machine's IPv4 addresses other devices could reach (not loopback), as "ip:port": invites carry them (§16)
  var ifs: ptr Ifaddrs
  if getifaddrs(addr ifs) != 0: return
  var p = ifs
  while p != nil:
    if p.ifa_addr != nil and p.ifa_addr.sa_family == TSa_Family(AF_INET):
      let ip = $inet_ntoa(cast[ptr Sockaddr_in](p.ifa_addr).sin_addr)
      if not ip.startsWith("127."): result.add ip & ":" & $port
    p = p.ifa_next
  freeifaddrs(ifs)
proc O(fields: varargs[(string, JNode)]): JNode = newObj(@fields)
proc S(s: string): JNode = newStr(s)

# ---------------------------------------------------------------- keys kept in the store

proc keyJson(k: PrivateKey): JNode = O(("scalar", S(hex(k.scalar))), ("pub", S(b64u(k.pub))))
proc keyOf*(j: JNode): PrivateKey = PrivateKey(scalar: unhex(j["scalar"].s), pub: unb64u(j["pub"].s))

proc custodial(s: Server, device: string): PrivateKey =
  let j = s.store.getRow("custodial", device)
  if j == nil: herr(500, "no key for this account's device")
  keyOf(j)

proc newCustodial(s: Server): (string, PrivateKey) =
  let k = s.p.p256Generate()
  let d = s.p.peerId(k)
  s.store.putRow("custodial", d, keyJson(k))
  (d, k)

proc rootKey(s: Server): PrivateKey =
  let j = s.store.getRow("keys", "root")
  if j == nil: herr(409, "This server does not hold the plant's root key.")
  keyOf(j)

# ---------------------------------------------------------------- accounts

proc users(s: Server): seq[JNode] =
  for (_, v) in s.store.allRows("users"): result.add v

proc userById(s: Server, id: int64): JNode = s.store.getRow("users", align($id, 12, '0'))
proc putUser(s: Server, u: JNode) = s.store.putRow("users", align($u["id"].i, 12, '0'), u)

proc userByName(s: Server, name: string): JNode =
  for u in s.users:
    if u["username"].s == name: return u

proc managerUser(s: Server): JNode =
  for u in s.users:
    if s.n.run != nil and s.n.run.manager == u["person"].s and u["active"].b: return u

proc newUserId(s: Server): int64 =
  for u in s.users: result = max(result, u["id"].i)
  inc result



proc publicUser(s: Server, u: JNode): JNode =
  let role = if s.n.run != nil: s.n.run.role(u["person"].s) else: "user"
  O(("id", u["id"]), ("username", u["username"]), ("role", S(if role.len > 0: role else: "user")), ("active", u["active"]),
    ("has_password", newBool(u["pw"].isStr and u["pw"].s.len > 0)), ("created", u["created"]),
    ("full_name", u["full_name"]), ("position", if u["position"].isNull: S("") else: u["position"]), ("person", u["person"]))

proc throttled(s: Server, keys: varargs[string]): bool = s.fails.blocked(keys, epochTime())

proc record(s: Server, ok: bool, keys: varargs[string]) = s.fails.record(ok, keys, epochTime())

proc newSession(s: Server, userId: int64): string =
  let raw = b64u(s.p.randomBytes(32))
  for (k, v) in s.store.allRows("sessions"):
    if v["expires"].i < nowS(): s.store.delRow("sessions", k)
  s.store.putRow("sessions", hex(s.p.sha256(raw.toBytes)), O(("user_id", newInt(userId)), ("created", newInt(nowS())),
                                                             ("expires", newInt(nowS() + s.cfg.sessionDays * 86400))))
  raw

proc endSessions(s: Server, userId: int64) =
  for (k, v) in s.store.allRows("sessions"):
    if v["user_id"].i == userId: s.store.delRow("sessions", k)

proc makeToken(s: Server, kind: string, userId: int64, ttl: int64): string =
  let raw = b64u(s.p.randomBytes(24))
  for (k, v) in s.store.allRows("tokens"):
    if v["kind"].s == kind and (kind == "setup" or v["user_id"].i == userId): s.store.delRow("tokens", k)
  s.store.putRow("tokens", hex(s.p.sha256(raw.toBytes)), O(("kind", S(kind)), ("user_id", newInt(userId)),
                                                           ("expires", newInt(nowS() + ttl))))
  raw

proc peekToken(s: Server, kind, raw: string): JNode =
  let t = s.store.getRow("tokens", hex(s.p.sha256(raw.toBytes)))
  if t != nil and t["kind"].s == kind and t["expires"].i > nowS(): t else: nil

proc consumeToken(s: Server, raw: string) = s.store.delRow("tokens", hex(s.p.sha256(raw.toBytes)))

proc hashPw(s: Server, pw: string): string = hashPassword(pw, s.p.randomBytes(16).toStr)

proc login(s: Server, username, password: string, sources: openArray[string]): JNode =
  ## `sources`: where the attempt comes from ("ip:…" from `sourceKey`, "tls:<peer>"), the first one the most specific
  ## that can't be changed for free. The account is counted per source, and as a whole only under pressure (#39).
  let acct = "u:" & username[0 ..< min(64, username.len)].toLowerAscii   # usernames are ≤ 40: no key grows with the body
  let keys = @sources & (acct & "@" & sources[0])
  let now = epochTime()
  if s.fails.blocked(keys, now, [acct]): herr(429, "Too many failed attempts. Wait a few minutes.")
  let u = s.userByName(username)
  let ok = u != nil and checkPassword(password, if u["pw"].isStr: u["pw"].s else: "") and u["active"].b
  if u == nil: discard checkPassword("x", "")
  s.fails.record(ok, keys, epochTime(), [acct])
  if not ok: herr(401, "Wrong username or password.")
  if needsRehash(u["pw"].s):   # v1 scrypt, or Argon2id below today's parameters (#40): replace it now
    u["pw"] = S(s.hashPw(password))
    s.putUser(u)
  u

proc passwordProblem(pw: JNode): string =
  if pw == nil or not pw.isStr or pw.s.len < MinPassword: "Password must be at least " & $MinPassword & " characters." else: ""


proc actorFor(s: Server, u: JNode): Actor =
  let (ok, a) = s.n.actorOf(u["device"].s, s.custodial(u["device"].s))
  if not ok: herr(401, "login required")
  a

# ---------------------------------------------------------------- the plant

proc ensureNodeKey(store: DbStore, p: Provider): PrivateKey =
  let j = store.getRow("keys", "node")
  if j != nil: return keyOf(j)
  result = p.p256Generate()
  store.putRow("keys", "node", keyJson(result))

proc openServer*(cfg: Config, p: Provider, storageKey: seq[byte]): Server =
  let st = openDbStore(p, cfg.storePath, storageKey)
  let key = ensureNodeKey(st, p)
  result = Server(cfg: cfg, p: p, store: st)
  result.n = newNode(p, st, key)
  result.api = newApi(result.n, mode = "server")
  result.api.plantName = cfg.plantName
  result.api.maxUpload = cfg.maxUploadMb * 1024 * 1024
  result.api.syncPort = cfg.syncPort
  result.id = newIdentity(key)

proc setupLinkPath*(cfg: Config): string =
  ## where `serve` keeps the one-time setup link while there is no manager (0600; issue #69)
  absolutePath(cfg.storePath).parentDir / "setup-link.txt"

proc setupLink*(s: Server): string =
  ## A one-time link to create the manager, while there is none.
  if s.managerUser() != nil: return ""
  let raw = s.makeToken("setup", 0, 7 * 86400)
  (if s.cfg.publicUrl.len > 0: s.cfg.publicUrl.strip(chars = {'/'}, leading = false) else: "http://localhost:" & $s.cfg.port) &
    "/#setup=" & raw

proc link(s: Server, path: string): string =
  (if s.cfg.publicUrl.len > 0: s.cfg.publicUrl.strip(chars = {'/'}, leading = false) else: "http://localhost:" & $s.cfg.port) & path

proc createPlant(s: Server, username, fullName: string, position: JNode, pw: string): JNode =
  ## Setup: a new root key, the manager with a custodial device, the genesis, this server's device certified.
  let rk = s.p.p256Generate()
  s.store.putRow("keys", "root", keyJson(rk))
  let pid = hex(s.p.randomBytes(16))
  let (dev, ck) = s.newCustodial()
  let plantName = s.cfg.plantName
  discard s.n.appendAs(ck, "genesis", s.p.genesisBody(rk, plantName, dev, pid, username, fullName, position), nowMs())
  s.n.adopt(keyString(rk.pub))
  discard s.n.appendAs(ck, "device_cert", deviceCertBody(s.n.device, pid, "server"), nowMs())
  result = O(("id", newInt(s.newUserId)), ("username", S(username)), ("pw", S(s.hashPw(pw))), ("active", newBool(true)),
             ("created", newInt(nowS())), ("full_name", S(fullName)), ("position", position), ("person", S(pid)),
             ("device", S(dev)))
  s.putUser(result)

proc createAccount(s: Server, me: Actor, username, fullName: string, position: JNode, role: string): JNode =
  let pid = hex(s.p.randomBytes(16))
  discard s.n.appendAs(me.key, "person", personBody(pid, username, fullName, role, position), nowMs())
  let (dev, _) = s.newCustodial()
  discard s.n.appendAs(me.key, "device_cert", deviceCertBody(dev, pid, "server"), nowMs())
  result = O(("id", newInt(s.newUserId)), ("username", S(username)), ("pw", newNull()), ("active", newBool(true)),
             ("created", newInt(nowS())), ("full_name", S(fullName)), ("position", position), ("person", S(pid)),
             ("device", S(dev)))
  s.putUser(result)

proc handOverManager*(s: Server, to: JNode) =
  ## A root `manager` statement (needs the root key), written by the new manager's own device.
  let rk = s.rootKey()
  let stmt = O(("kind", S("manager")), ("person", to["person"]))
  discard s.n.appendAs(s.custodial(to["device"].s), "root", s.p.rootBody(rk, stmt), nowMs())

# ---------------------------------------------------------------- HTTP

proc contentType(name: string): string =
  let ext = name.splitFile.ext.toLowerAscii
  case ext
  of ".html": "text/html; charset=utf-8"
  of ".js": "text/javascript; charset=utf-8"
  of ".css": "text/css; charset=utf-8"
  of ".json": "application/json"
  of ".webmanifest": "application/manifest+json"
  of ".svg": "image/svg+xml"
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".webp": "image/webp"
  of ".jxl": "image/jxl"
  of ".woff2": "font/woff2"
  of ".wasm": "application/wasm"
  of ".kkp": "application/octet-stream"
  of ".gz": "application/gzip"
  else: "application/octet-stream"

const
  # Stored content (photos, plant-data files) is never a document of this site: if a browser ever renders one as a
  # page, it runs sandboxed (a unique origin, no scripts) and loads nothing. As a subresource (<img>, fetch) the
  # header has no effect.
  ContentSandbox = ("Content-Security-Policy", "default-src 'none'; sandbox")
  # The app's own pages, their scripts and workers (#8): scripts only from this site, no inline script or handler
  # (the pages have none), WebAssembly for our libjxl/zxing build (decision 0037); pictures may be data: or blob:
  # URLs (photo previews, JPEG XL decoded to BMP). Inline styles stay allowed: views set style attributes.
  AppPolicy* = ("Content-Security-Policy", "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; " &
    "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; object-src 'none'; base-uri 'none'; " &
    "frame-ancestors 'none'; form-action 'self'")
  # plant-data files the pages fetch; anything else goes out as a download
  DataTypes = [".json", ".jxl", ".kkp", ".png", ".jpg", ".jpeg", ".webp", ".pdf", ".gz", ".woff2"]

proc photoType*(data: string): (string, bool) =
  ## A stored photo's Content-Type from its own bytes, never from the URL: the name in /photos/<sha>.<ext> is only a
  ## hint, and any member's device can make a blob (2026-10-06: a blob starting with a JPEG XL signature followed by
  ## HTML, requested as <sha>.html, was served as text/html: stored XSS). -> (type, is an image)
  case blobExt(data)
  of "jxl": ("image/jxl", true)
  of "jpg": ("image/jpeg", true)
  of "png": ("image/png", true)
  of "webp": ("image/webp", true)
  else: ("application/octet-stream", false)

proc dataType*(rel: string): (string, seq[(string, string)]) =
  ## a /data/ file's Content-Type and extra headers: the types the pages fetch go out sandboxed; anything else, and
  ## PDFs (a browser's PDF viewer won't run in a sandboxed document), as a sandboxed download
  let ext = rel.splitFile.ext.toLowerAscii
  if ext in DataTypes and ext != ".pdf": (contentType(rel), @[ContentSandbox])
  else: ((if ext == ".pdf": "application/pdf" else: "application/octet-stream"),
         @[ContentSandbox, ("Content-Disposition", "attachment")])

proc baseHeaders(s: Server, ctype: string, cache = "no-store"): HttpHeaders =
  result = newHttpHeaders({"Content-Type": ctype, "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
                           "X-Frame-Options": "DENY", "Cache-Control": cache})
  if s.cfg.publicUrl.startsWith("https://"): result["Strict-Transport-Security"] = "max-age=31536000"

proc sendJson(s: Server, req: Request, code: int, j: JNode, extra: seq[(string, string)] = @[]) {.async.} =
  let hdr = s.baseHeaders("application/json")
  for (k, v) in extra: hdr.add(k, v)
  await req.respond(HttpCode(code), toText(j), hdr)

proc sendBytes(s: Server, req: Request, data, ctype, cache: string, extra: seq[(string, string)] = @[]) {.async.} =
  let hdr = s.baseHeaders(ctype, cache)
  for (k, v) in extra: hdr.add(k, v)
  await req.respond(Http200, data, hdr)

proc localPage(s: Server, req: Request): bool =
  ## the request comes from a page opened over plain http on this machine (Origin http://127.0.0.1 or localhost)
  let o = parseUri(req.headers.getOrDefault("Origin"))
  o.scheme == "http" and o.hostname.toLowerAscii in ["127.0.0.1", "localhost", s.cfg.address]

proc cookieHeader(s: Server, req: Request, raw: string, maxAge: int): (string, string) =
  ## Secure under an https public_url, except for a page on this machine's own http address: WebKit drops a Secure
  ## cookie set over http://127.0.0.1 (Chromium and Firefox keep it), and nothing crosses the network there.
  let secure = s.cfg.secureCookies or (s.cfg.publicUrl.startsWith("https://") and not s.localPage(req))
  ("Set-Cookie", Cookie & "=" & raw & "; Path=/; HttpOnly; SameSite=Strict; Max-Age=" & $maxAge &
                 (if secure: "; Secure" else: ""))

proc sessionRaw(req: Request): string =
  for part in req.headers.getOrDefault("Cookie").split(';'):
    let kv = part.strip.split('=', 1)
    if kv.len == 2 and kv[0] == Cookie: return kv[1]

proc clientIp(s: Server, req: Request): string =
  ## the address login throttling counts. X-Forwarded-For only when the operator says the proxy in front appends to
  ## it (`trusted_proxy`): its last entry is then the browser's address as the proxy saw it. Anyone can send the header, so it is never read
  ## otherwise (every browser behind a proxy that doesn't append is then one address).
  ## HttpHeaders splits "a, b" into values and getOrDefault gives the first: every value is read, the last kept.
  let peer = req.hostname
  let fwd = seq[string](req.headers.getOrDefault("X-Forwarded-For")).join(",").split(',')[^1].strip
  if s.cfg.trustedProxy and fwd.len > 0 and peer in ["127.0.0.1", "::1", "::ffff:127.0.0.1"]: fwd
  else: peer

proc hostAllowed(s: Server, req: Request): bool =
  ## Host must name this server: 127.0.0.1 or localhost with its port, or public_url's host. Another name pointed
  ## at 127.0.0.1 (DNS rebinding, a page open in a browser on this machine) is refused.
  let hs = seq[string](req.headers.getOrDefault("Host"))
  if hs.len != 1: return false                          # two Host lines, or a comma list
  let h = hs[0].strip.toLowerAscii
  var allowed = @["127.0.0.1:" & $s.cfg.port, "localhost:" & $s.cfg.port, s.cfg.address & ":" & $s.cfg.port]
  if s.cfg.publicUrl.len > 0:
    let pu = parseUri(s.cfg.publicUrl)
    allowed.add pu.hostname.toLowerAscii & (if pu.port.len > 0: ":" & pu.port else: "")
  h in allowed

proc currentUser(s: Server, req: Request): JNode =
  let raw = req.sessionRaw
  if raw.len == 0: herr(401, "login required")
  let ses = s.store.getRow("sessions", hex(s.p.sha256(raw.toBytes)))
  if ses == nil or ses["expires"].i < nowS(): herr(401, "login required")
  let u = s.userById(ses["user_id"].i)
  if u == nil or not u["active"].b or not (u["pw"].isStr and u["pw"].s.len > 0): herr(401, "login required")
  if s.n.run == nil or u["device"].s in s.n.run.cuts: herr(401, "login required")
  u

proc queryOf(u: Uri): Table[string, string] =
  for k, v in decodeQuery(u.query): result[k] = v

proc courseList(s: Server): JNode =
  ## The courses (docs/COURSES.md) of the active plant data version, or the program's own data/courses when the plant
  ## has published none; files that are not valid courses are skipped (v1's courses.json among them) and logged.
  var files: seq[(string, string)]   # (name, bytes)
  var images: HashSet[string]
  var key = ""
  let (ok, a) = s.n.active
  if ok:
    for path, (sha, _) in a.files:
      if path.startsWith("courses/"):
        let name = path[8 .. ^1]
        if name.endsWith(".json"):
          files.add((name, s.n.store.blobGet(sha)))
          key.add sha
        elif name.endsWith(".jxl"): images.incl name
  let dir = s.cfg.dataDir / "courses"
  if files.len == 0 and s.cfg.dataDir.len > 0 and dirExists(dir):
    for f in walkDir(dir):
      if f.kind != pcFile: continue
      let name = f.path.extractFilename
      if name.endsWith(".jxl"): images.incl name
      elif name.endsWith(".json"):
        files.add((name, readFile(f.path)))
        key.add name & ":" & $getLastModificationTime(f.path).toUnix & ";"
  if s.courseCache[1] != nil and s.courseCache[0] == key: return s.courseCache[1]
  let (docs, bad) = pickCourses(files, images)
  for b in bad: stderr.writeLine "course refused: " & b
  var found: seq[JNode]
  for d in docs: found.add summary(d)
  result = O(("courses", newArr(found)))
  s.courseCache = (key, result)

proc staticFile(s: Server, req: Request, dir, rel, cache: string, ctype = "", extra: seq[(string, string)] = @[]) {.async.} =
  let root = absolutePath(dir)
  let full = absolutePath(root / rel)
  if not full.startsWith(root & DirSep) or not fileExists(full): herr(404, "not found")
  await s.sendBytes(req, readFile(full), if ctype.len > 0: ctype else: contentType(full), cache, extra)

proc personOf(d: JNode): (string, JNode) = personFields(d)

proc usersOut(s: Server, showHidden = false): JNode =
  ## accounts, then the people without one; a removed person an admin hid (POST /api/hidden) only with show_hidden
  result = newArr()
  var have: HashSet[string]
  var rows = s.users
  rows.sort(proc (a, b: JNode): int = cmp(a["username"].s.toLowerAscii, b["username"].s.toLowerAscii))
  let hidden = s.api.hiddenIds
  for u in rows:
    have.incl u["person"].s
    let gone = u["person"].s in hidden and not s.n.run.personActive(u["person"].s)
    if gone and not showHidden: continue
    var o = s.publicUser(u)
    o["hidden"] = newBool(gone)
    result.elems.add o
  var pids: seq[string]
  for pid, _ in s.n.run.persons: pids.add pid
  pids.sort(proc (a, b: string): int = cmp(s.n.run.persons[a]["username"].s.toLowerAscii, s.n.run.persons[b]["username"].s.toLowerAscii))
  for pid in pids:
    if pid in have: continue
    let gone = pid in hidden and not s.n.run.personActive(pid)
    if gone and not showHidden: continue
    let pr = s.n.run.persons[pid]
    var devs, active = 0
    for d, v in s.n.run.devices:
      if v["person"].s == pid:
        inc devs
        if d notin s.n.run.cuts: inc active
    result.elems.add O(("id", newNull()), ("person", S(pid)), ("username", pr["username"]), ("full_name", pr["full_name"]),
      ("position", if pr["position"].isNull: S("") else: pr["position"]), ("no_account", newBool(true)),
      ("has_password", newBool(false)), ("role", S(s.n.run.role(pid))), ("created", newNull()),
      ("active", newBool(active > 0)), ("devices", newInt(devs)), ("hidden", newBool(gone)))

proc updateUser(s: Server, me: Actor, uid: int64, d: JNode, reset: bool): JNode =
  if not me.isAdmin: herr(403, "admin only")
  var u = s.userById(uid)
  if u == nil: herr(404, "no such user")
  let role = s.n.run.role(u["person"].s)
  if role == "manager" or (role == "admin" and me.role != "manager"): herr(403, "not allowed for this account")
  if reset:
    return O(("ok", newBool(true)), ("link", S(s.link("/#reset=" & s.makeToken("reset", uid, 3 * 86400)))),
             ("expires_days", newInt(3)))
  var newRole = role
  if d.has("role") and not (d["role"].isStr and d["role"].s == role):
    if me.role != "manager" or not (d["role"].isStr and d["role"].s in ["user", "admin"]):
      herr(403, "only the manager can promote or demote admins")
    newRole = d["role"].s
  var fn = u["full_name"].s
  var pos = u["position"]
  if d.has("full_name") or d.has("position"):
    try:
      (fn, pos) = personOf(O(("full_name", if d.has("full_name"): d["full_name"] else: u["full_name"]),
                             ("position", if d.has("position"): d["position"] else: u["position"])))
    except ApiError as e: herr(400, e.msg)
  if newRole != role or fn != u["full_name"].s or not pyEq(pos, u["position"]):
    discard s.n.appendAs(me.key, "person", personBody(u["person"].s, u["username"].s, fn, newRole, pos), nowMs())
    u["full_name"] = S(fn)
    u["position"] = pos
  if d.has("active") and d["active"].kind == jBool and d["active"].b != u["active"].b:
    if not d["active"].b:   # all their keys stop: this server's and their own devices'
      var devs: seq[string]
      for dev, v in s.n.run.devices:
        if v["person"].s == u["person"].s and dev notin s.n.run.cuts: devs.add dev
      for dev in devs:
        let vvd = s.n.vv.get(dev)
        discard s.n.appendAs(me.key, "revoke", revokeBody(dev, if vvd == nil: 0'i64 else: vvd[0].i), nowMs())
    else:   # a new key; the old one stays cut
      let (dev, _) = s.newCustodial()
      discard s.n.appendAs(me.key, "device_cert", deviceCertBody(dev, u["person"].s, "server"), nowMs())
      u["device"] = S(dev)
    u["active"] = d["active"]
    s.endSessions(uid)
  if newRole != role: s.endSessions(uid)
  s.putUser(u)
  O(("ok", newBool(true)))

# ---- enrolment: a device joining with its owner's password (PROTOCOL-v2 §16 "through a server") ----

proc enrollDevice(s: Server, username, password, dev, label0: string, sources: openArray[string]) =
  ## Raises HttpErr (403/409/429/401) like the HTTP route; certifies `dev` for the account's person.
  if s.throttled(sources): herr(429, "Too many attempts.")
  let usr = s.login(username, password, sources)
  let lab = label0[0 ..< min(80, label0.len)]
  let have = s.n.run.devices.getOrDefault(dev)
  if have != nil and have["person"].s != usr["person"].s: herr(409, "That device belongs to someone else.")
  if dev in s.n.run.cuts: herr(403, "That device was removed; reset the app on it to make a new one.")
  if have == nil:
    discard s.n.appendAs(s.custodial(usr["device"].s), "device_cert", deviceCertBody(dev, usr["person"].s, lab), nowMs())

proc enrollOverTls(s: Server, remote, address: string, m: JNode): JNode =
  ## the §16 enroll message on the sync port (`address`: the TCP peer's; "" through the relay). The peer ID costs
  ## nothing to change, so the address is the source that counts (#39).
  proc ack(state, why: string): JNode = O(("t", S("enroll_ack")), ("state", S(state)), ("why", S(why)))
  let req = m.get("request")
  if req == nil or not s.p.checkJoinRequest(req) or req["device"].s != remote:
    return ack("bad", "the join request is not valid, or not from this device")
  try:
    s.enrollDevice(if m.get("username") != nil and m["username"].isStr: m["username"].s else: "",
                   if m.get("password") != nil and m["password"].isStr: m["password"].s else: "", remote,
                   if req.get("label") != nil and req["label"].isStr: req["label"].s else: "device",
                   (if address.len > 0: @[sourceKey(address), "tls:" & remote] else: @["tls:" & remote]))
  except HttpErr as e:
    return ack("refused", e.msg)
  O(("t", S("enroll_ack")), ("state", S("accepted")), ("root", S(s.n.root)), ("plant", s.n.run.settings.getOrDefault("plant")),
    ("server", S(s.n.device)))

# ---- plant data and drawings (PROTOCOL-v2 §19; server/sheets.py in v1) ----

proc publishDir*(s: Server, dir: string): int =
  ## Publish the plant files in `dir` as a new version signed by the manager's custodial key; 0 = unchanged.
  var files: seq[(string, string)]
  for f in ["sheets.json", "tags.json", "procedures.json", "locations.json", "descriptions.json"]:
    if fileExists(dir / f): files.add((f, readFile(dir / f)))
  for sub in ["sheets", "courses"]:
    if dirExists(dir / sub):
      var names: seq[string]
      for f in walkDir(dir / sub):
        if f.kind == pcFile: names.add f.path.extractFilename
      names.sort()
      for n in names:
        if validPath(sub & "/" & n): files.add((sub & "/" & n, readFile(dir / sub / n)))
  let mgr = s.managerUser()
  if mgr == nil: raise newException(ValueError, "no manager yet")
  let ck = s.store.getRow("custodial", mgr["device"].s)
  result = s.n.publishAs(keyOf(ck), files, nowMs())

proc setPlantName*(s: Server, name: string) =
  ## the plant's name, written by the manager's custodial key ("" = none shown)
  let n = name.strip
  if n.len > 80: raise newException(ValueError, "A plant name of 80 characters or fewer")
  let mgr = s.managerUser()
  if mgr == nil: raise newException(ValueError, "no manager yet")
  discard s.n.appendAs(keyOf(s.store.getRow("custodial", mgr["device"].s)), "setting",
                       O(("key", S("plant")), ("value", S(n))), nowMs())

# ---- control socket: the CLI's commands that change the plant run inside the server process ----
# Found 2026-10-04: `kks-server publish-data` in a second process wrote to the store, but the running server keeps the
# log in memory and never saw it (the new sheets reached no device until a restart), and the two processes' copies of
# the manager's chain could have signed two different entries with one seq. While the server runs, these commands go
# through this socket (owner-only, next to the store) and run here.

proc controlPath*(cfg: Config): string = absolutePath(cfg.storePath).parentDir / "kks-server.sock"

proc control*(s: Server, cmd: string, args: seq[string]): string =
  ## one CLI command that changes the plant; -> what to print. Raises ValueError for the person to read.
  case cmd
  of "publish-data":
    if args.len != 1: raise newException(ValueError, "usage: kks-server publish-data DIR")
    let v = s.publishDir(args[0])
    if v == 0: "Unchanged: the files equal the latest version." else: "Published plant data version " & $v & "."
  of "set-plant-name":
    if args.len != 1: raise newException(ValueError, "usage: kks-server set-plant-name NAME   (\"\" for none)")
    s.setPlantName(args[0])
    if args[0].strip.len == 0: "The plant has no name now." else: "The plant is called " & args[0].strip & " now."
  of "submit-file":
    # a list of ordinary submissions [{kind, payload, client_id?, note?}] made as the manager, through the same checks
    # as /api/submit: plant knowledge from a document (procedure links, photos, equipment fields). A client_id makes a
    # second run add nothing.
    if args.len != 1: raise newException(ValueError, "usage: kks-server submit-file FILE.json")
    let mgr = s.managerUser()
    if mgr == nil: raise newException(ValueError, "no manager yet")
    let me = s.actorFor(mgr)
    var items: JNode
    try: items = parseStrict(readFile(args[0]), 64)
    except CatchableError as e: raise newException(ValueError, args[0] & ": " & e.msg)
    if items.kind != jArr: raise newException(ValueError, args[0] & ": a JSON list of submissions")
    var count = initCountTable[string]()
    for i, it in items.elems:
      if it.kind != jObj or it.get("kind") == nil or not it["kind"].isStr:
        raise newException(ValueError, "item " & $i & ": {kind, payload, client_id?, note?}")
      var r: JNode
      try: r = s.api.submit(me, it["kind"].s, it.get("payload"), it.get("client_id"), it.get("note"), nowMs())
      except CatchableError as e: raise newException(ValueError, "item " & $i & " (" & it["kind"].s & "): " & e.msg &
                                                     (if i > 0: " (the " & $i & " before it were submitted)" else: ""))
      count.inc(if r.get("duplicate") != nil and r["duplicate"].kind == jBool and r["duplicate"].b: "already there"
                elif r.get("status") != nil and r["status"].isStr: r["status"].s else: "done")
    var parts: seq[string]
    for k, v in count: parts.add $v & " " & k
    $items.elems.len & " submissions: " & parts.join(", ") & "."
  of "reset-password":
    # a one-time link to set a new password (as the admin page's Users → Password link), for whoever runs the server
    if args.len != 1: raise newException(ValueError, "usage: kks-server reset-password --user NAME")
    let u = s.userByName(args[0])
    if u == nil or not u["active"].b: raise newException(ValueError, "No active account named " & args[0] & ".")
    "Open this link once within 3 days to set a new password for " & args[0] & ":\n  " &
      s.link("/#reset=" & s.makeToken("reset", u["id"].i, 3 * 86400))
  of "reset-manager":
    # the manager account was lost (forgotten password, the person left): the root key, which the server holds,
    # names another active account manager; the old manager becomes an admin (a root `manager` statement, §21)
    if args.len != 1: raise newException(ValueError, "usage: kks-server reset-manager --user NAME")
    let u = s.userByName(args[0])
    if u == nil or not u["active"].b: raise newException(ValueError, "No active account named " & args[0] & ".")
    if s.n.run != nil and s.n.run.manager == u["person"].s: raise newException(ValueError, args[0] & " is already the manager.")
    s.handOverManager(u)
    s.store.setMeta("transfer", "")                   # an offer waiting from the old manager is void
    args[0] & " is the manager now. If they need a new password, open this link once within 3 days:\n  " &
      s.link("/#reset=" & s.makeToken("reset", u["id"].i, 3 * 86400))
  else: raise newException(ValueError, "not a control command: " & cmd)

proc serveControl(s: Server) {.async.} =
  let path = controlPath(s.cfg)
  try: removeFile(path)                                # a stale socket of a server that stopped (fileExists is
  except OSError: discard                               # false for sockets: not a regular file)
  let sock = newAsyncSocket(nativesockets.AF_UNIX, nativesockets.SOCK_STREAM, nativesockets.IPPROTO_IP)
  let old = umask(0o177)                                # created 0600: only this user can talk to it
  try: sock.bindUnix(path)
  finally: discard umask(old)
  sock.listen()
  while true:
    let c = await sock.accept()
    try:
      let line = await c.recvLine(maxLength = 64 * 1024)
      let req = parseStrict(line)
      var args: seq[string]
      for a in req["args"].elems: args.add a.s
      var res: JNode
      try: res = O(("ok", newBool(true)), ("out", S(s.control(req["cmd"].s, args))))
      except ValueError as e: res = O(("ok", newBool(false)), ("out", S(e.msg)))
      await c.send(toText(res) & "\n")
    except CatchableError as e:
      stderr.writeLine "control: " & e.msg
    c.close()

proc importerStatus(s: Server): JNode =
  if fileExists(s.cfg.importer): O(("available", newBool(true)))
  else: O(("available", newBool(false)), ("error", S("The drawing importer (kks-import) was not found at " & s.cfg.importer & ".")))

proc readJsonFile(path: string): JNode =
  if fileExists(path): parseStrict(readFile(path), 4096) else: newArr()

proc sheetSummary(s: Server): JNode =
  let sheets = readJsonFile(s.cfg.plantDir / "sheets.json")
  var count = initTable[string, Table[string, int]]()
  for t in readJsonFile(s.cfg.plantDir / "tags.json").elems:
    count.mgetOrPut(t["sheet"].s, initTable[string, int]()).mgetOrPut(t["status"].s, 0).inc
  result = newArr()
  for sh in sheets.elems:
    var e = sh.copy
    var c = O(("auto", newInt(0)), ("verified", newInt(0)), ("review", newInt(0)))
    for k, v in count.getOrDefault(sh["id"].s): c[k] = newInt(v)
    e["tags"] = c
    e["has_source"] = newBool(fileExists(s.cfg.plantDir / "sheets" / (sh["id"].s & ".pdf")))
    result.elems.add e

proc sheetFiles(s: Server, sid: string): seq[string] =
  ## this sheet's files in the working copy (sheets/<id>.pdf, .kkp, .o<k>.jxl)
  if not dirExists(s.cfg.plantDir / "sheets"): return
  for f in walkDir(s.cfg.plantDir / "sheets"):
    let n = f.path.extractFilename
    if n == sid & ".pdf" or n == sid & ".kkp" or (n.startsWith(sid & ".o") and n.endsWith(".jxl")): result.add n

proc backupSheets(s: Server, why, sid: string): string =
  result = s.cfg.backupDir / ("sheets-" & now().format("yyyyMMdd-HHmmss") & "-" & why & "-" & sid)
  createDir(result)
  for f in ["sheets.json", "tags.json"]:
    if fileExists(s.cfg.plantDir / f): copyFile(s.cfg.plantDir / f, result / f)
  for n in s.sheetFiles(sid): copyFile(s.cfg.plantDir / "sheets" / n, result / n)

proc restoreSheets(s: Server, backup, sid: string) =
  for n in s.sheetFiles(sid): removeFile(s.cfg.plantDir / "sheets" / n)
  for f in walkDir(backup):
    let n = f.path.extractFilename
    let dst = if n.endsWith(".json"): s.cfg.plantDir / n else: s.cfg.plantDir / "sheets" / n
    copyFile(f.path, dst & ".tmp")
    moveFile(dst & ".tmp", dst)

proc validSheetId(sid: string): bool =
  sid.len in 1 .. 24 and sid[0] in {'a' .. 'z', '0' .. '9'} and sid.allCharsInSet({'a' .. 'z', '0' .. '9', '-'})

proc runImport(s: Server, job: JNode, args: seq[string], replace: bool) {.async.} =
  let backup = s.backupSheets("import", job["sheet"].s)
  var ok = false
  var p: Process
  try:
    # issue #34: MuPDF reads an uploaded file, so the importer runs with an address-space limit and no core dumps
    # (set by sh before it execs the importer: the same process, killed below at the deadline). The arguments are
    # passed through "$@", never through the script text.
    p = startProcess("/bin/sh", args = @["-c", "ulimit -c 0 && ulimit -v " & $(s.cfg.importMemoryMb * 1024) &
                                         " && exec \"$0\" \"$@\"", s.cfg.importer] & args,
                     options = {poStdErrToStdOut})
    let deadline = epochTime() + float(s.cfg.importTimeoutS)
    let fd = p.outputHandle
    discard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) or O_NONBLOCK)
    var pending = ""
    var buf = newString(4096)
    proc takeLines(final: bool) =
      while true:
        let i = pending.find('\n')
        if i < 0 and not (final and pending.len > 0): break
        let line = if i < 0: pending else: pending[0 ..< i]
        pending = if i < 0: "" else: pending[i + 1 .. ^1]
        let l = line.strip(leading = false)
        if l.startsWith("RESULT "):
          try: job["result"] = parseStrict(l[7 .. ^1])
          except JsonError: discard
        elif l.len > 0:
          job["log"].elems.add S(l)
          if job["log"].elems.len > 300: job["log"].elems.delete(0)
    var stopped = false
    proc stop() =
      if not stopped:
        stopped = true
        p.kill()
        job["log"].elems.add S("The importer was stopped after " & $s.cfg.importTimeoutS & " s (import_timeout_s in the config).")
    var reads = 0
    while true:
      if epochTime() > deadline:          # checked on every pass: an importer that never stops printing is stopped too
        stop()
        break
      let n = posix.read(fd, addr buf[0], buf.len)
      if n > 0:
        pending.add buf[0 ..< n]
        if pending.len > 65536 and '\n' notin pending: pending.add '\n'   # one endless line: cut it
        takeLines(false)
        inc reads
        if reads mod 16 == 0: await sleepAsync(0)   # let the server answer others meanwhile
        continue
      if n == 0: break                       # end of output
      if errno != EAGAIN and errno != EWOULDBLOCK: break
      await sleepAsync(200)
    takeLines(true)
    while p.peekExitCode() == -1:          # no blocking wait: a child that closed its output may still hang
      if epochTime() > deadline: stop()
      await sleepAsync(100)
    let code = p.peekExitCode()
    ok = code == 0 and job["result"].kind == jObj
  except CatchableError as e:
    job["log"].elems.add S("Importer crashed: " & e.msg)
  finally:
    if p != nil: p.close()
  if ok:
    try:
      let v = s.publishDir(s.cfg.plantDir)
      job["version"] = newInt(v)
    except CatchableError as e:
      job["log"].elems.add S("Imported, but publishing failed: " & e.msg)
  else:
    s.restoreSheets(backup, job["sheet"].s)
    job["log"].elems.add S("Import failed; the sheet list and tags were left as they were before.")
  job["state"] = S(if ok: "done" else: "failed")
  job["finished"] = newInt(nowS())

proc startImport(s: Server, me: JNode, sid0, name0, rotate: string, replace: bool, pdf: string, hasPdf: bool): JNode =
  let sid = sid0.strip
  if not validSheetId(sid): herr(400, "Sheet id: 1-24 lowercase letters, digits, dashes (start with a letter or digit).")
  var name = name0.strip
  var current = initTable[string, JNode]()
  for sh in readJsonFile(s.cfg.plantDir / "sheets.json").elems: current[sh["id"].s] = sh
  if name.len == 0 and replace and sid in current: name = current[sid]["name"].s   # a re-import keeps the name
  if name.len == 0 or name.len > 80: herr(400, "Give the sheet a name (up to 80 characters).")
  if rotate notin ["auto", "0", "90", "180", "270"]: herr(400, "bad rotation")
  if sid in current and not replace: herr(400, "A sheet with id \"" & sid & "\" exists. Pick another id, or choose to replace it.")
  if not s.importerStatus()["available"].b: herr(400, s.importerStatus()["error"].s)
  if s.job != nil and s.job["state"].s == "running": herr(400, "Another import is running. Wait for it to finish.")
  var src = s.cfg.plantDir / "sheets" / (sid & ".pdf")
  if hasPdf:
    if not pdf.startsWith("%PDF-"): herr(400, "That file is not a PDF.")
    createDir(s.cfg.backupDir / "uploads")
    src = s.cfg.backupDir / "uploads" / (sid & ".pdf")
    writeFile(src & ".tmp", pdf)
    moveFile(src & ".tmp", src)
  elif not fileExists(src): herr(400, "No stored PDF for this sheet: upload it again.")
  createDir(s.cfg.plantDir)
  let job = O(("id", newInt(nowMs())), ("sheet", S(sid)), ("name", S(name)), ("rotate", S(rotate)),
              ("by", me["username"]), ("state", S("running")), ("log", newArr()), ("result", newNull()),
              ("started", newInt(nowS())))
  s.job = job
  var args = @["--rotate", rotate, "--data-dir", s.cfg.plantDir]
  if replace: args.add "--replace"
  if s.cfg.glyphs.len > 0: args.add @["--glyphs", s.cfg.glyphs]
  args.add @["--", src, name, sid]   # the name is the manager's text: never read as an option (issue #38)
  asyncCheck s.runImport(job, args, replace)
  job

proc removeSheet(s: Server, sid: string): JNode =
  if s.job != nil and s.job["state"].s == "running": herr(400, "An import is running. Wait for it to finish.")
  let sheets = readJsonFile(s.cfg.plantDir / "sheets.json")
  var found = false
  for sh in sheets.elems:
    if sh["id"].s == sid: found = true
  if not found: herr(400, "No such sheet.")
  if sheets.elems.len == 1: herr(400, "That is the only sheet; add another before removing it.")
  let backup = s.backupSheets("remove", sid)    # the files too: nothing is lost
  for n in s.sheetFiles(sid): removeFile(s.cfg.plantDir / "sheets" / n)
  var keptTags = newArr()
  var n = 0
  for t in readJsonFile(s.cfg.plantDir / "tags.json").elems:
    if t["sheet"].s == sid: inc n else: keptTags.elems.add t
  var keptSheets = newArr()
  for sh in sheets.elems:
    if sh["id"].s != sid: keptSheets.elems.add sh
  for (path, obj) in [(s.cfg.plantDir / "tags.json", keptTags), (s.cfg.plantDir / "sheets.json", keptSheets)]:
    writeFile(path & ".tmp", toText(obj))
    moveFile(path & ".tmp", path)
  let v = s.publishDir(s.cfg.plantDir)
  O(("ok", newBool(true)), ("removed", S(sid)), ("tags", newInt(n)), ("backup", S(backup.extractFilename)), ("version", newInt(v)))

proc handle(s: Server, req: Request) {.async.} =
  let u = req.url
  let path = decodeUrl(u.path)
  let q = queryOf(u)
  let meth = $req.reqMethod
  if not s.hostAllowed(req): herr(421, "This server does not answer to that host name.")
  if meth == "GET" or meth == "HEAD":
    if path in Shell:
      await s.staticFile(req, s.cfg.webDir, Shell[path], "no-cache", extra = @[AppPolicy])
      return
    if path.startsWith("/vendor/"):
      await s.staticFile(req, s.cfg.webDir / "vendor", path[8 .. ^1], "no-cache", extra = @[AppPolicy])
      return
    if path == "/api/config":
      var c = s.api.configOut()
      c["mode"] = S("server")
      c["offline_days"] = newInt(s.cfg.offlineDays)
      c["setup_needed"] = newBool(s.managerUser() == nil)
      c.del("node")
      # no encoder here: browsers encode JPEG XL themselves (decision 0037); the API refuses anything else
      c["photo_upload"] = O(("type", S("image/jxl")), ("distance", newFloat(1.9)), ("effort", newInt(7)))
      await s.sendJson(req, 200, c)
      return
    if path == "/api/token-info":
      let kind = q.getOrDefault("kind")
      let t = if kind in ["setup", "reset"]: s.peekToken(kind, q.getOrDefault("token")) else: nil
      if t == nil: herr(404, "This link is invalid or has expired.")
      let usr = s.userById(t["user_id"].i)
      await s.sendJson(req, 200, O(("kind", S(kind)), ("username", if usr == nil: newNull() else: usr["username"])))
      return
  let isPost = meth == "POST"
  if isPost:   # JSON only, same origin: a form on another site can't post here with the session cookie
    let origin = req.headers.getOrDefault("Origin")
    if origin.len > 0:
      let host = parseUri(origin).hostname & (if parseUri(origin).port.len > 0: ":" & parseUri(origin).port else: "")
      var allowed = @[$req.headers.getOrDefault("Host")]   # not X-Forwarded-Host: anyone can send it
      if s.cfg.publicUrl.len > 0:
        let pu = parseUri(s.cfg.publicUrl)
        allowed.add pu.hostname & (if pu.port.len > 0: ":" & pu.port else: "")
      if host notin allowed: herr(403, "cross-origin request refused")
    let ctype = req.headers.getOrDefault("Content-Type")
    if path == "/api/bundle/import" and (ctype.startsWith("application/gzip") or ctype.startsWith("application/octet-stream")):
      let me = s.actorFor(s.currentUser(req))
      if not me.isAdmin: herr(403, "admin only")
      var r: JNode
      try: r = s.n.importBundle(req.body, nowMs())
      except ValueError as e: herr(400, e.msg)
      r["ok"] = newBool(true)
      await s.sendJson(req, 200, r)
      return
    if path == "/api/sheets/import" and ctype.startsWith("application/pdf"):   # not a type a cross-site form can send
      let usr = s.currentUser(req)
      if usr == nil or s.actorFor(usr).role != "manager": herr(403, "manager only")
      if req.body.len > s.cfg.maxPdfMb * 1024 * 1024: herr(413, "PDF larger than " & $s.cfg.maxPdfMb & " MB (max_pdf_mb in the config)")
      let job = s.startImport(usr, q.getOrDefault("id"), q.getOrDefault("name"), q.getOrDefault("rotate", "auto"),
                              q.getOrDefault("replace") == "1", req.body, true)
      await s.sendJson(req, 200, O(("ok", newBool(true)), ("job", job)))
      return
    if not ctype.startsWith("application/json"): herr(415, "JSON only")
  var d = newObj()
  if isPost and req.body.len > 0:
    try: d = parseStrict(req.body)
    except JsonError: herr(400, "bad json")
    if d.kind != jObj: herr(400, "bad json")
  let ip = s.clientIp(req)
  let src = [sourceKey(ip)]
  if isPost:
    case path
    of "/api/login":
      let usr = s.login(if d.get("username") != nil and d["username"].isStr: d["username"].s else: "",
                        if d.get("password") != nil and d["password"].isStr: d["password"].s else: "", src)
      let raw = s.newSession(usr["id"].i)
      await s.sendJson(req, 200, O(("user", s.publicUser(usr))), @[s.cookieHeader(req, raw, s.cfg.sessionDays * 86400)])
      return
    of "/api/logout":
      # Clear-Site-Data: the HTTP cache goes too (it may hold photos from before the fix of finding #25, which were
      # served with the URL's type and cached as immutable for a year)
      let raw = req.sessionRaw
      if raw.len > 0: s.store.delRow("sessions", hex(s.p.sha256(raw.toBytes)))
      await s.sendJson(req, 200, O(("ok", newBool(true))), @[s.cookieHeader(req, "", 0), ("Clear-Site-Data", "\"cache\"")])
      return
    of "/api/setup":
      if s.throttled(src): herr(429, "Too many attempts.")
      let name = if d.get("username") != nil and d["username"].isStr: d["username"].s.strip else: ""
      if not validUsername(name): herr(400, "Username: 2-40 letters (a-z), digits, . _ - @")
      let prob = passwordProblem(d.get("password"))
      if prob.len > 0: herr(400, prob)
      var fn: string
      var pos: JNode
      try:
        (fn, pos) = personOf(d)
        requirePosition(pos)    # the manager is a new member too
      except ApiError as e: herr(400, e.msg)
      let tok = if d.get("token") != nil and d["token"].isStr: d["token"].s else: ""
      if s.peekToken("setup", tok) == nil or s.managerUser() != nil or s.n.root.len > 0:
        s.record(false, src)
        herr(403, "This setup link is invalid or already used.")
      let usr = s.createPlant(name, fn, pos, d["password"].s)
      s.consumeToken(tok)
      try: removeFile(setupLinkPath(s.cfg))   # used: the file's link is dead (#69)
      except OSError: discard
      let raw = s.newSession(usr["id"].i)
      await s.sendJson(req, 200, O(("ok", newBool(true))), @[s.cookieHeader(req, raw, s.cfg.sessionDays * 86400)])
      return
    of "/api/password-reset":
      if s.throttled(src): herr(429, "Too many attempts.")
      let prob = passwordProblem(d.get("password"))
      if prob.len > 0: herr(400, prob)
      let tok = if d.get("token") != nil and d["token"].isStr: d["token"].s else: ""
      let t = s.peekToken("reset", tok)
      if t == nil:
        s.record(false, src)
        herr(403, "This link is invalid or has expired.")
      var usr = s.userById(t["user_id"].i)
      usr["pw"] = S(s.hashPw(d["password"].s))
      s.putUser(usr)
      s.consumeToken(tok)
      s.endSessions(usr["id"].i)
      let raw = s.newSession(usr["id"].i)
      await s.sendJson(req, 200, O(("ok", newBool(true))), @[s.cookieHeader(req, raw, s.cfg.sessionDays * 86400)])
      return
    else: discard
  # everything else needs a signed-in account
  var usr = s.currentUser(req)
  let me = s.actorFor(usr)
  if meth == "GET":
    if path.startsWith("/data/"):
      let rel = path[6 .. ^1]
      let (ok, data) = s.n.file(rel)
      # plant-data files: only the types the pages use; anything else (an .html the manager published) downloads
      let (dtype, dextra) = dataType(rel)
      if ok:
        await s.sendBytes(req, data, dtype, "private, no-cache", dextra)
        return
      let (okGz, gzd) = s.n.file(rel & ".gz")
      if okGz:
        await s.sendBytes(req, gzd, dtype, "private, no-cache", dextra & @[("Content-Encoding", "gzip"), ("Vary", "Accept-Encoding")])
        return
      await s.staticFile(req, s.cfg.dataDir, rel, "private, no-cache", dtype, dextra)   # the program's own data/
      return
    if path.startsWith("/photos/"):
      let name = path[8 .. ^1]
      let sha = name.split('.')[0]
      if not isHex64(sha) or not s.n.store.blobHas(sha): herr(404, "not found")
      let blob = s.n.store.blobGet(sha)
      let (ptype, image) = photoType(blob)
      await s.sendBytes(req, blob, ptype, "private, max-age=31536000, immutable",
                        if image: @[ContentSandbox] else: @[ContentSandbox, ("Content-Disposition", "attachment")])
      return
    case path
    of "/api/me":
      let t = s.store.getMeta("transfer")
      let tr = if t.len > 0: parseStrict(t) else: nil
      let live = tr != nil and tr["expires"].i > nowS()
      await s.sendJson(req, 200, O(("user", s.publicUser(usr)), ("offline_days", newInt(s.cfg.offlineDays)),
        ("transfer_offer", newBool(live and tr["to"].i == usr["id"].i)),
        ("transfer_pending", if live and me.role == "manager": tr else: newNull())))
      return
    of "/api/users":
      if not me.isAdmin: herr(403, "admin only")
      await s.sendJson(req, 200, O(("users", s.usersOut(q.getOrDefault("show_hidden") in ["1", "true"]))))
      return
    of "/api/sync/status":
      await s.sendJson(req, 200, O(("rev", newInt(s.api.rev)), ("mode", S("server")), ("internet", newNull()),
                                   ("plant_data", s.n.status)))
      return
    of "/api/progress": herr(404, "Course progress stays in this browser on a server.")
    of "/api/courses":
      await s.sendJson(req, 200, s.courseList)
      return
    of "/api/bundle":
      if not me.isAdmin: herr(403, "admin only")
      let data = s.n.bundle(photos = q.getOrDefault("photos") == "1", now = nowMs())
      var name = ""
      for c in (if s.n.run.settings.getOrDefault("plant") != nil: s.n.run.settings["plant"].s else: "plant"):
        name.add(if c.isAlphaNumeric or c in {'.', '-', '_'}: c else: '-')
      await s.sendBytes(req, data, "application/gzip", "no-store",
        @[("Content-Disposition", "attachment; filename=\"" & name[0 ..< min(40, name.len)] & "-" &
           now().format("yyyyMMdd-HHmm") & ".kksbundle\"")])
      return
    of "/api/sheets":
      if me.role != "manager": herr(403, "manager only")
      await s.sendJson(req, 200, O(("sheets", s.sheetSummary()), ("job", if s.job == nil: newNull() else: s.job),
                                   ("plant_data", s.n.status), ("importer", s.importerStatus())))
      return
    of "/api/sheets/job":
      if me.role != "manager": herr(403, "manager only")
      await s.sendJson(req, 200, O(("job", if s.job == nil: newNull() else: s.job)))
      return
    of "/api/update":
      await s.sendJson(req, 200, O(("available", newBool(false)), ("can_install", newBool(false)),
        ("note", S("This server is updated by its administrator (package manager)."))))
      return
    else: discard
  if isPost:
    let parts = path.split('/')
    if parts.len == 5 and parts[1] == "api" and parts[2] == "sheets" and parts[4] == "remove":
      if me.role != "manager": herr(403, "manager only")
      await s.sendJson(req, 200, s.removeSheet(parts[3]))
      return
    case path
    of "/api/password":
      discard s.login(usr["username"].s, if d.get("old") != nil and d["old"].isStr: d["old"].s else: "", src)
      let prob = passwordProblem(d.get("new"))
      if prob.len > 0: herr(400, prob)
      usr["pw"] = S(s.hashPw(d["new"].s))
      s.putUser(usr)
      s.endSessions(usr["id"].i)
      let raw = s.newSession(usr["id"].i)
      await s.sendJson(req, 200, O(("ok", newBool(true))), @[s.cookieHeader(req, raw, s.cfg.sessionDays * 86400)])
      return
    of "/api/sheets/reimport":   # the stored PDF again, e.g. with another rotation
      if me.role != "manager": herr(403, "manager only")
      let str = proc (k: string, dflt = ""): string = (if d.get(k) != nil and d[k].isStr: d[k].s elif d.get(k) != nil and d[k].kind == jInt: $d[k].i else: dflt)
      let job = s.startImport(usr, str("id"), str("name"), str("rotate", "auto"), true, "", false)
      await s.sendJson(req, 200, O(("ok", newBool(true)), ("job", job)))
      return
    of "/api/users":
      if not me.isAdmin: herr(403, "admin only")
      let name = if d.get("username") != nil and d["username"].isStr: d["username"].s.strip else: ""
      let role = if d.get("role") != nil and d["role"].isStr: d["role"].s else: "user"
      if not validUsername(name): herr(400, "Username: 2-40 letters (a-z), digits, . _ - @")
      if role notin ["user", "admin"]: herr(400, "role must be user or admin")
      if role == "admin" and me.role != "manager": herr(403, "only the manager can create admins")
      var fn: string
      var pos: JNode
      try:
        (fn, pos) = personOf(d)
        requirePosition(pos)    # every new member needs one (existing ones keep what they have)
      except ApiError as e: herr(400, e.msg)
      if s.userByName(name) != nil: herr(409, "That username exists.")
      for _, pr in s.n.run.persons:
        if pr["username"].s.toLowerAscii == name.toLowerAscii: herr(409, "That username exists.")
      let nu = s.createAccount(me, name, fn, pos, role)
      await s.sendJson(req, 200, O(("ok", newBool(true)), ("id", nu["id"]),
        ("link", S(s.link("/#reset=" & s.makeToken("reset", nu["id"].i, 7 * 86400)))), ("expires_days", newInt(7))))
      return
    of "/api/profile":
      let r = s.api.handle(me, "POST", path, q, d, nowMs())
      if r.status == 200:
        let (fn, pos) = personOf(d)
        usr["full_name"] = S(fn)
        usr["position"] = pos
        s.putUser(usr)
      await s.sendJson(req, r.status, r.json)
      return
    of "/api/progress": herr(404, "Course progress stays in this browser on a server.")
    of "/api/sync/now":
      # admins only (#32): it makes the server open a connection to an address of the caller's choice
      if not me.isAdmin: herr(403, "admin only")
      let addr0 = if d.get("address") != nil and d["address"].isStr: d["address"].s.strip else: ""
      if addr0.len == 0: herr(400, "give the other device's address (host:port)")
      let host = if ':' in addr0: addr0.rsplit(':', 1)[0] else: addr0
      let port = if ':' in addr0: (try: parseInt(addr0.rsplit(':', 1)[1]) except ValueError: -1) else: 8421
      if port < 1 or port > 65535 or host.len == 0: herr(400, "give the other device's address (host:port)")
      try:
        let st = await s.n.syncWith(s.id, host, port, "")
        await s.sendJson(req, 200, O(("ok", newBool(true)), ("result", O(("sent", newInt(st.sent)),
          ("received", newInt(st.received)), ("blobs_sent", newInt(st.blobsSent)), ("blobs_received", newInt(st.blobsReceived)),
          ("denied", newBool(st.denied)), ("they_denied", newBool(st.theyDenied))))))
      except CatchableError as e: herr(502, "sync with " & addr0 & " failed: " & e.msg)
      return
    else: discard
    if parts.len >= 4 and parts[2] == "users":
      let uid = try: parseBiggestInt(parts[3]) except ValueError: herr(404, "not found")
      await s.sendJson(req, 200, s.updateUser(me, uid, d, parts.len == 5 and parts[4] == "reset"))
      return
    if parts.len == 4 and parts[2] == "manager":
      let t0 = s.store.getMeta("transfer")
      let t = if t0.len > 0: parseStrict(t0) else: nil
      case parts[3]
      of "transfer":
        if me.role != "manager": herr(403, "manager only")
        discard s.login(usr["username"].s, if d.get("password") != nil and d["password"].isStr: d["password"].s else: "", src)
        let to = s.userByName(if d.get("username") != nil and d["username"].isStr: d["username"].s else: "")
        if to == nil or s.n.run.role(to["person"].s) != "admin" or not to["active"].b:
          herr(400, "The new manager must be an active admin.")
        discard s.rootKey()   # the handover is signed with the root key: fail now, not at "accept"
        s.store.setMeta("transfer", toText(O(("from", usr["id"]), ("to", to["id"]), ("to_name", to["username"]),
                                             ("expires", newInt(nowS() + 7 * 86400)))))
      of "cancel":
        if me.role != "manager": herr(403, "manager only")
        s.store.setMeta("transfer", "")
      of "accept", "decline":
        if t == nil or t["to"].i != usr["id"].i or t["expires"].i < nowS(): herr(400, "No manager transfer is waiting for you.")
        s.store.setMeta("transfer", "")
        if parts[3] == "accept":
          let old = s.userById(t["from"].i)
          if old == nil or s.n.run.role(old["person"].s) != "manager" or me.role != "admin": herr(409, "The offer is no longer valid.")
          s.handOverManager(usr)
      else: herr(404, "not found")
      await s.sendJson(req, 200, O(("ok", newBool(true))))
      return
  let r = s.api.handle(me, meth, path, q, d, nowMs())
  if r.bytes.len > 0: await s.sendBytes(req, r.bytes, r.contentType, "no-store", r.headers)
  else: await s.sendJson(req, r.status, r.json)

proc txtRecord(s: Server): seq[(string, string)] =
  ## PROTOCOL-v2 §16: peer, root (first 16 of the root ID), plant, label, adm, v.
  let rootId = if s.n.root.len > 0: s.p.peerIdOfKey(s.n.root)[0 ..< 16] else: ""
  let plant = if s.n.run != nil and s.n.run.settings.getOrDefault("plant") != nil: s.n.run.settings["plant"].s else: ""
  result = @[("peer", s.n.device), ("root", rootId), ("plant", plant), ("label", "server"), ("adm", "1"), ("v", "2")]

proc announce(s: Server) =
  if s.mdns == nil or s.cfg.syncPort == 0: return
  let txt = s.txtRecord
  let key = $txt
  if key == s.announced: return
  try:
    s.mdns.announce("kks-" & s.n.device[0 ..< 12], s.cfg.syncPort, txt)
    s.announced = key
  except MdnsError as e:
    stderr.writeLine "mDNS: " & e.msg

proc serve*(s: Server): Future[void] =
  ## HTTP, sync and mDNS until the process stops.
  asyncCheck s.serveControl()
  if s.cfg.syncPort > 0:
    try:
      s.mdns = newMdns()
      s.announce()
      s.n.listeners.add proc (why: string) = s.announce()
      proc pumpLoop() {.async.} =
        while true:
          s.mdns.pump()
          await sleepAsync(250)
      asyncCheck pumpLoop()
    except MdnsError as e:
      stderr.writeLine "mDNS off: " & e.msg
  let hooks = Hooks(
    join: proc (remote: string, m: JNode): JNode =
      result = s.api.invites.offer(s.p, remote, m, nowS())
      if result["state"].s == "accepted":
        result["root"] = S(s.n.root)
        result["plant"] = s.n.run.settings.getOrDefault("plant"),
    secrets: proc (remote: string, m: JNode): JNode = O(("t", S("secrets")), ("secrets", newArr())),   # §17: a server holds none
    enroll: proc (remote: string, m: JNode): JNode = s.enrollOverTls(remote, "", m))   # through the relay
  if s.cfg.syncPort > 0:
    s.listener = listen(s.n, s.id, s.cfg.syncPort, hooks = hooks)
    s.listener.enrollFrom = proc (remote, address: string, m: JNode): JNode = s.enrollOverTls(remote, address, m)
  # §18: the server sits in the plant's room when the manager set a relay, and answers syncs through it (it starts
  # none: the other devices sync with it on their rounds, as on the LAN)
  s.internet = newInternet(s.n, s.id, hooks)
  s.internet.start()
  # 0050: after a rotation the server stays in the previous room for a while, so a device that reaches the plant only
  # through the relay (a phone on mobile data) can sync there once and learn the new key
  s.internetPrev = newInternet(s.n, s.id, hooks)
  s.internetPrev.keyOf = proc (): (bool, PrivateKey) = s.n.prevMemberKey(nowMs())
  s.internetPrev.start()
  # diagnostics reports (§13a): the server's own errors, at most every 6 hours, while the manager has them on
  proc reportLoop() {.async.} =
    const version = staticRead("../../../../VERSION").strip
    var os = "Linux"
    try:
      for line in readFile("/etc/os-release").splitLines:
        if line.startsWith("PRETTY_NAME="): os = line[12 .. ^1].strip(chars = {'"'})
    except IOError: discard
    while true:
      await sleepAsync(3_600_000)
      try: discard s.n.maybeReport("server", version, os, "", nowS() * 1000)
      except CatchableError: discard
  asyncCheck reportLoop()
  s.api.relayChanged = proc () =
    s.internet.restart()
    s.internetPrev.restart()
  # the status admin.html's Devices page shows (the v1 shape: syncs by device, found on the Wi-Fi, internet)
  var syncs = newObj()
  proc record(remote, address: string, st: Stats) =
    syncs[remote] = O(("peer", S(remote)), ("address", S(address)), ("at", newInt(nowS())), ("ok", newBool(true)),
                      ("result", O(("sent", newInt(st.sent)), ("received", newInt(st.received)),
                                   ("denied", newBool(st.denied)), ("they_denied", newBool(st.theyDenied)))))
  if s.listener != nil:
    s.listener.onDone = proc (remote: string, st: Stats) = record(remote, "", st)
  s.internet.onSynced = proc (remote: string, st: Stats, initiator: bool) = record(remote, "relay", st)
  s.api.syncPort = s.cfg.syncPort
  s.api.addresses = proc (): seq[string] =
    if s.cfg.syncPort == 0: @[] else: localAddrs(s.cfg.syncPort)   # the listener binds every interface
  s.api.syncSnapshot = proc (): JNode =
    var found = newArr()
    if s.mdns != nil:
      for f in s.mdns.found: found.elems.add O(("name", S(f.name)), ("host", S(f.address)))
    var online = newArr()
    for p in s.internet.online: online.elems.add S(p)
    let relay = relaySetting(s.n)
    result = O(("discovery", S(if s.mdns != nil: "on" else: "off")), ("syncs", syncs), ("found", found),
      ("internet", O(("relay", if relay.len > 0: S(relay) else: newNull()), ("state", S(s.internet.state)), ("online", online))))
  let http = newAsyncHttpServer(maxBody = s.cfg.maxUploadMb * 1024 * 1024 * 2 + 65536)
  proc cb(req: Request) {.async, gcsafe.} =
    {.cast(gcsafe).}:
      try:
        await s.handle(req)
      except HttpErr as e:
        await s.sendJson(req, e.code, O(("error", S(e.msg))))
      except CatchableError as e:
        stderr.writeLine "error: " & e.msg & "\n" & e.getStackTrace()
        try: s.n.record("error", req.url.path & ": " & $e.name & ": " & e.msg & "\n" & e.getStackTrace(), nowS() * 1000)
        except CatchableError: discard
        await s.sendJson(req, 500, O(("error", S("internal error (see the server log)"))))
  http.serve(Port(s.cfg.port), cb, s.cfg.address, assumedDescriptorsPerRequest = 5)   # stop accepting near the descriptor limit instead of crashing
