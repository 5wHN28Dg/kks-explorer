## The always-on server (decision 0026): the core's node and API behind HTTP for browser clients, password accounts
## (Argon2id), the sync listener. Same routes, cookie and headers as v1's app.py in server mode, so the web pages work
## unchanged. One thread owns the node (decision 0030).

import std/[asyncdispatch, asynchttpserver, asyncnet, base64, nativesockets, os, osproc, posix, strutils, tables, times, uri, sets, algorithm]
import kks/[json, util, crypto, proto, replay, node, sync, plant, api, plantdata, bundle, extras, invites, courses, diagnostics]
import kks/provider_gnutls
import dbstore, tls, net, argon2, mdns, internet

const
  Cookie = "kks_session"
  MinPassword = 10
  Shell = {"/": "index.html", "/index.html": "index.html", "/admin.html": "admin.html", "/common.js": "common.js", "/tiles.js": "tiles.js",
           "/course-bridge.js": "course-bridge.js", "/learning.html": "learning.html",
           "/course.html": "course.html", "/course.js": "course.js", "/course-figure.js": "course-figure.js",
           "/course.css": "course.css", "/kks-wasm.js": "kks-wasm.js", "/kks-wasm-worker.js": "kks-wasm-worker.js",
           "/sw.js": "sw.js", "/manifest.webmanifest": "manifest.webmanifest", "/icon.svg": "icon.svg",
           "/icon-192.png": "icon-192.png", "/icon-512.png": "icon-512.png"}.toTable

type
  Config* = object
    address*: string           ## HTTP listen address (127.0.0.1 behind a tunnel)
    port*: int
    syncPort*: int             ## 0 = off
    publicUrl*: string
    secureCookies*: bool
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

  Server* = ref object
    cfg*: Config
    p*: Provider
    store*: DbStore
    n*: Node
    api*: Api
    id*: Identity
    fails: Table[string, (int, float)]
    listener*: Listener
    mdns*: Mdns
    internet*: Internet           ## presence on the plant's relay (§18), answers syncs through it
    internetV1*: Internet         ## presence in the v1 plant's room while v1 devices may still move (§21a)
    announced: string
    job*: JNode                ## the drawing import running or last run (one at a time)
    courseCache: (string, JNode)   ## (what the list was built from, the list)

  HttpErr = object of CatchableError
    code: int

proc defaultConfig*(): Config =
  Config(address: "0.0.0.0", port: 8420, syncPort: 8421, plantName: "Walkdown", sessionDays: 30,
         offlineDays: 3, maxUploadMb: 15, plantDir: "plant-data", backupDir: "backups", maxPdfMb: 50,
         importer: getAppDir() / "kks-import")

proc loadConfig*(path: string): Config =
  result = defaultConfig()
  if path.len == 0 or not fileExists(path): return
  let j = parseStrict(readFile(path))
  proc s(k: string, d: string): string = (if j.get(k) != nil and j[k].isStr: j[k].s else: d)
  proc i(k: string, d: int): int = (if j.get(k) != nil and j[k].kind == jInt: int(j[k].i) else: d)
  proc b(k: string, d: bool): bool = (if j.get(k) != nil and j[k].kind == jBool: j[k].b else: d)
  result.address = s("address", result.address)
  result.port = i("port", result.port)
  result.syncPort = i("sync_port", result.syncPort)
  result.publicUrl = s("public_url", "")
  result.secureCookies = b("secure_cookies", false)
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

proc throttled(s: Server, keys: varargs[string]): bool =
  let now = epochTime()
  for k in keys:
    if k in s.fails and s.fails[k][1] > now: return true

proc record(s: Server, ok: bool, keys: varargs[string]) =
  for k in keys:
    if ok: s.fails.del k
    else:
      let n = s.fails.getOrDefault(k, (0, 0.0))[0] + 1
      s.fails[k] = (n, epochTime() + (if n >= 5: float(min(900, 15 * (1 shl min(n - 5, 10)))) else: 0.0))

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

proc login(s: Server, username, password, ip: string): JNode =
  let keys = ["u:" & username.toLowerAscii, "ip:" & ip]
  if s.throttled(keys): herr(429, "Too many failed attempts. Wait a few minutes.")
  let u = s.userByName(username)
  let ok = u != nil and checkPassword(password, if u["pw"].isStr: u["pw"].s else: "") and u["active"].b
  if u == nil: discard checkPassword("x", "")
  s.record(ok, keys)
  if not ok: herr(401, "Wrong username or password.")
  if isLegacy(u["pw"].s):   # a v1 scrypt hash: replace it with Argon2id now that we have the password
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

proc cookieHeader(s: Server, raw: string, maxAge: int): (string, string) =
  ("Set-Cookie", Cookie & "=" & raw & "; Path=/; HttpOnly; SameSite=Strict; Max-Age=" & $maxAge &
                 (if s.cfg.secureCookies: "; Secure" else: ""))

proc sessionRaw(req: Request): string =
  for part in req.headers.getOrDefault("Cookie").split(';'):
    let kv = part.strip.split('=', 1)
    if kv.len == 2 and kv[0] == Cookie: return kv[1]

proc clientIp(req: Request): string =
  let peer = req.hostname
  let fwd = req.headers.getOrDefault("X-Forwarded-For")
  if fwd.len > 0 and peer in ["127.0.0.1", "::1"]: fwd.split(',')[^1].strip else: peer

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

proc staticFile(s: Server, req: Request, dir, rel, cache: string) {.async.} =
  let root = absolutePath(dir)
  let full = absolutePath(root / rel)
  if not full.startsWith(root & DirSep) or not fileExists(full): herr(404, "not found")
  await s.sendBytes(req, readFile(full), contentType(full), cache)

proc personOf(d: JNode): (string, JNode) = personFields(d)

proc usersOut(s: Server): JNode =
  result = newArr()
  var have: HashSet[string]
  var rows = s.users
  rows.sort(proc (a, b: JNode): int = cmp(a["username"].s.toLowerAscii, b["username"].s.toLowerAscii))
  for u in rows:
    result.elems.add s.publicUser(u)
    have.incl u["person"].s
  var pids: seq[string]
  for pid, _ in s.n.run.persons: pids.add pid
  pids.sort(proc (a, b: string): int = cmp(s.n.run.persons[a]["username"].s.toLowerAscii, s.n.run.persons[b]["username"].s.toLowerAscii))
  for pid in pids:
    if pid in have: continue
    let pr = s.n.run.persons[pid]
    var devs, active = 0
    for d, v in s.n.run.devices:
      if v["person"].s == pid:
        inc devs
        if d notin s.n.run.cuts: inc active
    result.elems.add O(("id", newNull()), ("person", S(pid)), ("username", pr["username"]), ("full_name", pr["full_name"]),
      ("position", if pr["position"].isNull: S("") else: pr["position"]), ("no_account", newBool(true)),
      ("has_password", newBool(false)), ("role", S(s.n.run.role(pid))), ("created", newNull()),
      ("active", newBool(active > 0)), ("devices", newInt(devs)))

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

proc enrollDevice(s: Server, username, password, dev, label0, ip: string) =
  ## Raises HttpErr (403/409/429/401) like the HTTP route; certifies `dev` for the account's person.
  if s.throttled("ip:" & ip): herr(429, "Too many attempts.")
  let usr = s.login(username, password, ip)
  let lab = label0[0 ..< min(80, label0.len)]
  let have = s.n.run.devices.getOrDefault(dev)
  if have != nil and have["person"].s != usr["person"].s: herr(409, "That device belongs to someone else.")
  if dev in s.n.run.cuts: herr(403, "That device was removed; reset the app on it to make a new one.")
  if have == nil:
    discard s.n.appendAs(s.custodial(usr["device"].s), "device_cert", deviceCertBody(dev, usr["person"].s, lab), nowMs())

proc enrollOverTls(s: Server, remote: string, m: JNode): JNode =
  ## the §16 enroll message on the sync port
  proc ack(state, why: string): JNode = O(("t", S("enroll_ack")), ("state", S(state)), ("why", S(why)))
  let req = m.get("request")
  if req == nil or not s.p.checkJoinRequest(req) or req["device"].s != remote:
    return ack("bad", "the join request is not valid, or not from this device")
  try:
    s.enrollDevice(if m.get("username") != nil and m["username"].isStr: m["username"].s else: "",
                   if m.get("password") != nil and m["password"].isStr: m["password"].s else: "", remote,
                   if req.get("label") != nil and req["label"].isStr: req["label"].s else: "device", "tls:" & remote)
  except HttpErr as e:
    return ack("refused", e.msg)
  O(("t", S("enroll_ack")), ("state", S("accepted")), ("root", S(s.n.root)), ("plant", s.n.run.settings.getOrDefault("plant")),
    ("server", S(s.n.device)))

# ---- moving v1 devices (PROTOCOL-v2 §21a, decision 0042) ----
# The one-time import (import-v1, import-succession) ran on 2026-10-03 and was removed with v1's code; what stays
# answers the phones still moving: the statement, the proofs, the v1 relay room. Remove it once v1-status says none.

const MigrateDomain = "kks-migrate-v1\n"

proc v1Root*(s: Server): string =
  let r = s.store.getRow("v1", "root")
  if r != nil and r.isStr: r.s else: ""

proc v1Room*(s: Server): string =
  ## the v1 plant's relay room (v1 §18), where v1 devices look for the server once they move
  let r = s.v1Root
  if r.len == 0 or s.store.getRow("v1", "succession") == nil: return ""
  hex(s.p.sha256(toBytes("kks-relay-room-v1\n" & r)))[0 ..< 32]

proc successionOverTls(s: Server, remote: string, m: JNode): JNode =
  let f = s.store.getRow("v1", "succession")
  if f == nil: return O(("t", S("succession")), ("stmt", newNull()))
  O(("t", S("succession")), ("stmt", f["stmt"]), ("sig", f["sig"]))

proc migrateOverTls*(s: Server, remote: string, m: JNode): JNode =
  ## §21a: a v1 device's proof → a device_cert for the same person
  proc ack(state, why: string): JNode = O(("t", S("migrate_ack")), ("state", S(state)), ("why", S(why)))
  let pr = m.get("proof")
  if pr == nil or pr.kind != jObj: return ack("bad", "no proof")
  for k in ["v1_root", "v1_device", "v2_root", "device", "key", "label", "sig"]:
    if pr.get(k) == nil or not pr[k].isStr: return ack("bad", "the proof lacks " & k)
  if pr.get("kks_migrate") == nil or pr["kks_migrate"].kind != jInt or pr["kks_migrate"].i != 1 or
     pr.get("created") == nil or pr["created"].kind != jInt or pr.fields.len != 9:
    return ack("bad", "not a migration proof")
  let dev = pr["device"].s
  if dev != remote: return ack("bad", "the proof is not for this connection's device")
  try:
    if not s.p.p256Valid(unb64u(pr["key"].s)) or s.p.peerIdOfKey(pr["key"].s) != dev: return ack("bad", "the key is not the device's")
  except CatchableError: return ack("bad", "the key is not the device's")
  if s.v1Root.len == 0 or s.store.getRow("v1", "succession") == nil: return ack("refused", "this server does not move v1 devices")
  if pr["v1_root"].s != s.v1Root or pr["v2_root"].s != s.n.root: return ack("refused", "the proof is for another plant")
  let v1dev = pr["v1_device"].s
  let info = s.store.getRow("v1_devices", v1dev)
  if info == nil: return ack("refused", "this v1 device is not in the plant's v1 log")
  if info["revoked"].kind == jBool and info["revoked"].b: return ack("refused", "this v1 device was removed")
  var rest = newObj()
  for (k, v) in pr.fields:
    if k != "sig": rest[k] = v
  var sig, pub: seq[byte]
  try: (sig, pub) = (unb64u(pr["sig"].s), unb64u(v1dev))
  except ValueError: return ack("bad", "bad signature encoding")
  if not ed25519Verify(pub, sig, toBytes(MigrateDomain & canonical(rest))): return ack("bad", "the v1 device did not sign this")
  let moved = s.store.getRow("v1_moved", v1dev)
  if moved != nil and moved.s != dev:
    return ack("refused", "this v1 device has already moved to another device; join normally (ask an admin)")
  let person = info["person"].s
  if person notin s.n.run.persons: return ack("refused", "the person of this v1 device is not in the plant")
  let have = s.n.run.devices.getOrDefault(dev)
  if have != nil and have["person"].s != person: return ack("refused", "that device belongs to someone else")
  if dev in s.n.run.cuts: return ack("refused", "that device was removed")
  if have == nil:
    var signer = ""
    for u in s.users():
      if u["person"].s == person and u["active"].kind == jBool and u["active"].b: signer = u["device"].s
    if signer.len == 0: signer = s.managerUser()["device"].s
    let lab = pr["label"].s
    discard s.n.appendAs(s.custodial(signer), "device_cert", deviceCertBody(dev, person, lab[0 ..< min(80, lab.len)]), nowMs())
  s.store.putRow("v1_moved", v1dev, S(dev))
  O(("t", S("migrate_ack")), ("state", S("accepted")), ("root", S(s.n.root)), ("plant", s.n.run.settings.getOrDefault("plant")),
    ("server", S(s.n.device)))

proc v1Waiting*(s: Server): JNode =
  ## the v1 devices that have not moved yet (Manage → Devices; when all have, the bridge can be retired)
  result = newArr()
  for (d, info) in s.store.allRows("v1_devices"):
    let server = info.get("server") != nil and info["server"].kind == jBool and info["server"].b   # v1's own keys never move
    if not server and s.store.getRow("v1_moved", d) == nil and not (info["revoked"].kind == jBool and info["revoked"].b) and
       info["person"].s in s.n.run.persons:
      result.elems.add O(("v1_device", S(d)), ("person", info["person"]), ("name", s.n.run.persons[info["person"].s]["full_name"]))

# ---- plant data and drawings (PROTOCOL-v2 §19; server/sheets.py in v1) ----

proc publishDir*(s: Server, dir: string): int =
  ## Publish the plant files in `dir` as a new version signed by the manager's custodial key; 0 = unchanged.
  var files: seq[(string, string)]
  for f in ["sheets.json", "tags.json", "procedures.json", "locations.json"]:
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
    p = startProcess(s.cfg.importer, args = args, options = {poStdErrToStdOut})
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
    while true:
      let n = posix.read(fd, addr buf[0], buf.len)
      if n > 0:
        pending.add buf[0 ..< n]
        takeLines(false)
        continue
      if n == 0: break                       # end of output
      if errno != EAGAIN and errno != EWOULDBLOCK: break
      await sleepAsync(200)
    takeLines(true)
    let code = p.waitForExit()
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
  var args = @[src, name, sid, "--rotate", rotate, "--data-dir", s.cfg.plantDir]
  if replace: args.add "--replace"
  if s.cfg.glyphs.len > 0: args.add @["--glyphs", s.cfg.glyphs]
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
  if meth == "GET" or meth == "HEAD":
    if path in Shell:
      await s.staticFile(req, s.cfg.webDir, Shell[path], "no-cache")
      return
    if path.startsWith("/vendor/"):
      await s.staticFile(req, s.cfg.webDir / "vendor", path[8 .. ^1], "no-cache")
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
      var allowed = @[$req.headers.getOrDefault("Host"), $req.headers.getOrDefault("X-Forwarded-Host")]
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
  let ip = req.clientIp
  if isPost:
    case path
    of "/api/login":
      let usr = s.login(if d.get("username") != nil and d["username"].isStr: d["username"].s else: "",
                        if d.get("password") != nil and d["password"].isStr: d["password"].s else: "", ip)
      let raw = s.newSession(usr["id"].i)
      await s.sendJson(req, 200, O(("user", s.publicUser(usr))), @[s.cookieHeader(raw, s.cfg.sessionDays * 86400)])
      return
    of "/api/logout":
      let raw = req.sessionRaw
      if raw.len > 0: s.store.delRow("sessions", hex(s.p.sha256(raw.toBytes)))
      await s.sendJson(req, 200, O(("ok", newBool(true))), @[s.cookieHeader("", 0)])
      return
    of "/api/setup":
      if s.throttled("ip:" & ip): herr(429, "Too many attempts.")
      let name = if d.get("username") != nil and d["username"].isStr: d["username"].s.strip else: ""
      if not validUsername(name): herr(400, "Username: 2-40 letters (a-z), digits, . _ - @")
      let prob = passwordProblem(d.get("password"))
      if prob.len > 0: herr(400, prob)
      var fn: string
      var pos: JNode
      try: (fn, pos) = personOf(d)
      except ApiError as e: herr(400, e.msg)
      let tok = if d.get("token") != nil and d["token"].isStr: d["token"].s else: ""
      if s.peekToken("setup", tok) == nil or s.managerUser() != nil or s.n.root.len > 0:
        s.record(false, "ip:" & ip)
        herr(403, "This setup link is invalid or already used.")
      let usr = s.createPlant(name, fn, pos, d["password"].s)
      s.consumeToken(tok)
      let raw = s.newSession(usr["id"].i)
      await s.sendJson(req, 200, O(("ok", newBool(true))), @[s.cookieHeader(raw, s.cfg.sessionDays * 86400)])
      return
    of "/api/password-reset":
      if s.throttled("ip:" & ip): herr(429, "Too many attempts.")
      let prob = passwordProblem(d.get("password"))
      if prob.len > 0: herr(400, prob)
      let tok = if d.get("token") != nil and d["token"].isStr: d["token"].s else: ""
      let t = s.peekToken("reset", tok)
      if t == nil:
        s.record(false, "ip:" & ip)
        herr(403, "This link is invalid or has expired.")
      var usr = s.userById(t["user_id"].i)
      usr["pw"] = S(s.hashPw(d["password"].s))
      s.putUser(usr)
      s.consumeToken(tok)
      s.endSessions(usr["id"].i)
      let raw = s.newSession(usr["id"].i)
      await s.sendJson(req, 200, O(("ok", newBool(true))), @[s.cookieHeader(raw, s.cfg.sessionDays * 86400)])
      return
    of "/api/devices/enroll":   # v1 clients: a device joining with its owner's account (v2 devices enroll over TLS, §16)
      let dev = d.get("device")
      if dev == nil or not dev.isStr or not isPeer(dev.s): herr(400, "bad device ID")
      s.enrollDevice(if d.get("username") != nil and d["username"].isStr: d["username"].s else: "",
                     if d.get("password") != nil and d["password"].isStr: d["password"].s else: "", dev.s,
                     if d.get("label") != nil and d["label"].isStr: d["label"].s else: "laptop", ip)
      await s.sendJson(req, 200, O(("root", S(s.n.root)), ("plant", s.n.run.settings.getOrDefault("plant")),
                                   ("sync_port", newInt(s.cfg.syncPort)), ("server", S(s.n.device))))
      return
    else: discard
  # everything else needs a signed-in account
  var usr = s.currentUser(req)
  let me = s.actorFor(usr)
  if meth == "GET":
    if path.startsWith("/data/"):
      let rel = path[6 .. ^1]
      let (ok, data) = s.n.file(rel)
      if ok:
        await s.sendBytes(req, data, contentType(rel), "private, no-cache")
        return
      let (okGz, gzd) = s.n.file(rel & ".gz")
      if okGz:
        await s.sendBytes(req, gzd, contentType(rel), "private, no-cache", @[("Content-Encoding", "gzip"), ("Vary", "Accept-Encoding")])
        return
      await s.staticFile(req, s.cfg.dataDir, rel, "private, no-cache")
      return
    if path.startsWith("/photos/"):
      let name = path[8 .. ^1]
      let sha = name.split('.')[0]
      if not isHex64(sha) or not s.n.store.blobHas(sha): herr(404, "not found")
      await s.sendBytes(req, s.n.store.blobGet(sha), contentType(name), "private, max-age=31536000, immutable")
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
      await s.sendJson(req, 200, O(("users", s.usersOut)))
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
      discard s.login(usr["username"].s, if d.get("old") != nil and d["old"].isStr: d["old"].s else: "", ip)
      let prob = passwordProblem(d.get("new"))
      if prob.len > 0: herr(400, prob)
      usr["pw"] = S(s.hashPw(d["new"].s))
      s.putUser(usr)
      s.endSessions(usr["id"].i)
      let raw = s.newSession(usr["id"].i)
      await s.sendJson(req, 200, O(("ok", newBool(true))), @[s.cookieHeader(raw, s.cfg.sessionDays * 86400)])
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
      try: (fn, pos) = personOf(d)
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
      let addr0 = if d.get("address") != nil and d["address"].isStr: d["address"].s.strip else: ""
      if addr0.len == 0: herr(400, "give the other device's address (host:port)")
      let host = if ':' in addr0: addr0.rsplit(':', 1)[0] else: addr0
      let port = if ':' in addr0: parseInt(addr0.rsplit(':', 1)[1]) else: 8421
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
        discard s.login(usr["username"].s, if d.get("password") != nil and d["password"].isStr: d["password"].s else: "", ip)
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
  if s.v1Room.len > 0: result.add ("prev", s.v1Root[0 ..< 16])   # §21a: moving v1 devices find the server by it

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
    enroll: proc (remote: string, m: JNode): JNode = s.enrollOverTls(remote, m),
    succession: proc (remote: string, m: JNode): JNode = s.successionOverTls(remote, m),
    migrate: proc (remote: string, m: JNode): JNode = s.migrateOverTls(remote, m))
  if s.cfg.syncPort > 0:
    s.listener = listen(s.n, s.id, s.cfg.syncPort, hooks = hooks)
  # §18: the server sits in the plant's room when the manager set a relay, and answers syncs through it (it starts
  # none: the other devices sync with it on their rounds, as on the LAN)
  s.internet = newInternet(s.n, s.id, hooks)
  s.internet.start()
  # §21a: while v1 devices may still move, also in the v1 plant's room (they know only the v1 root)
  if s.v1Room.len > 0:
    s.internetV1 = newInternet(s.n, s.id, hooks)
    s.internetV1.roomOf = proc (): string = s.v1Room
    s.internetV1.start()
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
    if s.internetV1 != nil: s.internetV1.restart()
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
    if s.v1Room.len > 0: result["v1_waiting"] = s.v1Waiting()   # §21a: old-app phones that haven't moved yet
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
  http.serve(Port(s.cfg.port), cb, s.cfg.address)
