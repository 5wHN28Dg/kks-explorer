## The Android core library (decision 0032): the Nim core behind a small JNI surface (jni_shim.c). All calls come from
## one Kotlin thread, so the core needs no locking. Responses are UTF-8 JSON.

import std/[tables, os, strutils, base64, times]
import std/sets
import kks/[json, crypto, proto, node, api, sync, bundle, extras, util, invites, plantdata, model, views, pathstore, courses, diagnostics, rudp]
import kksl/dbstore
import kksa/[provider_jni, figops]

{.compile: "src/kksa/jni_shim.c".}
proc kks_jc_changed(why: cstring) {.importc, cdecl.}
proc malloc(n: csize_t): pointer {.importc, header: "<stdlib.h>".}
proc free(p: pointer) {.importc, header: "<stdlib.h>".}

type
  Inst = ref object
    p: JniProvider
    store: DbStore
    n: Node
    api: Api
    key: PrivateKey
    tables: JNode          ## the program's KKS tables (kks.json, from the app's assets)
    m: Model               ## rebuilt after a change
    net: JNode             ## what the Kotlin sync service reports: {port, addrs, snapshot} (/native/net)
    programCourses: seq[(string, string)]   ## the app's own data/courses JSON (assets), (name, text)
    programImages: HashSet[string]
  Sync = ref object
    inst: int64
    s: Session
    d: Deframer
    error: string

var
  insts: seq[Inst]
  syncs: Table[int64, Sync]
  nextSync = 1'i64
  rudps: Table[int64, Rudp]     ## reliable UDP streams (§18 direct path); the socket is Kotlin's (sync/Direct.kt)

proc cbytes(s: string, outlen: ptr cint): ptr UncheckedArray[byte] =
  ## a malloc'd copy for the C side (it frees with kks_free)
  let p = cast[ptr UncheckedArray[byte]](malloc(csize_t(max(1, s.len))))
  if s.len > 0: copyMem(p, unsafeAddr s[0], s.len)
  outlen[] = cint(s.len)
  p

proc kks_free(p: pointer) {.exportc, cdecl.} = free(p)

proc nowMs(): int64 = int64(epochTime() * 1000)

proc kks_open(dir: cstring, key: ptr UncheckedArray[byte], keylen: cint, handle: cstring, pub: ptr UncheckedArray[byte],
              publen: cint, label: cstring, err: ptr cstring): int64 {.exportc, cdecl.} =
  try:
    let p = JniProvider()
    var skey = newSeq[byte](int(keylen))
    if keylen > 0: copyMem(addr skey[0], key, int(keylen))
    createDir($dir)
    let st = openDbStore(p, $dir / "kks.db", skey)
    var pubB = newSeq[byte](int(publen))
    if publen > 0: copyMem(addr pubB[0], pub, int(publen))
    let pk = PrivateKey(pub: pubB, handle: $handle)
    let n = newNode(p, st, pk)
    let a = newApi(n, mode = "peer")
    a.deviceLabel = $label
    let inst = Inst(p: p, store: st, n: n, api: a, key: pk, tables: newObj())
    n.listeners.add proc (why: string) =
      inst.m = nil
      kks_jc_changed(why.cstring)
    insts.add inst
    int64(insts.len)
  except CatchableError as e:
    let m = e.msg
    var outl: cint
    err[] = cast[cstring](cbytes(m & "\0", addr outl))
    0

proc inst(h: int64): Inst =
  if h < 1 or h > insts.len: raise newException(ValueError, "no such core")
  insts[h - 1]

proc O(fields: varargs[(string, JNode)]): JNode = newObj(@fields)

proc model(c: Inst): Model =
  if c.m != nil: return c.m
  proc file(path, dflt: string): JNode =
    let (ok, data) = c.n.file(path)
    try: parseStrict(if ok: data else: dflt, 4096) except JsonError: parseStrict(dflt)
  let m = Model()
  m.sheets = parseSheets(file("sheets.json", "[]"))
  m.baseTags = parseTags(file("tags.json", "[]"))
  m.procs = file("procedures.json", "[]")
  m.locations = buildLocations(file("locations.json", "{}"))
  let (okD, desc) = c.n.file("descriptions.json")
  m.descriptions = loadDescriptions(if okD: desc else: "", nil)    # a malformed file is skipped
  m.kksTables = c.tables
  let (ok, me) = c.api.owner
  m.state = if ok: c.api.handle(me, "GET", "/api/state", initTable[string, string](), newObj(), nowMs()).json else: newObj()
  m.merge()
  c.m = m
  m

proc native(c: Inst, meth, path: string, body: JNode, q: JNode): JNode =
  proc arg(k: string): string = (if q.get(k) != nil and q[k].isStr: q[k].s else: "")
  template view(x: untyped): untyped = O(("status", newInt(200)), ("json", x))
  ## what the phone needs before (or besides) being a member: config, its join request, bundles, sync targets
  case path
  of "/native/config":
    var cfg = c.api.configOut()
    cfg["device"] = newStr(c.n.device)
    cfg["key"] = newStr(keyString(c.key.pub))
    cfg["root"] = newStr(c.n.root)
    # the mDNS TXT this phone announces (PROTOCOL-v2 §16; the same keys as the GNOME app)
    let (ok, me) = c.api.owner
    let plantN = if c.n.run != nil and c.n.run.settings.getOrDefault("plant") != nil: c.n.run.settings["plant"].s else: ""
    cfg["txt"] = O(("peer", newStr(c.n.device)), ("root", newStr(if c.n.root.len > 0: c.p.peerIdOfKey(c.n.root)[0 ..< 16] else: "")),
                   ("plant", newStr(plantN)), ("label", newStr(c.api.deviceLabel)),
                   ("adm", newStr(if ok and me.isAdmin: "1" else: "0")), ("v", newStr("2")))
    let rv = if c.n.run != nil: c.n.run.settings.getOrDefault("relay") else: nil
    cfg["relay_url"] = newStr(if rv != nil and rv.isStr: rv.s else: "")
    cfg["admin"] = newBool(ok and me.isAdmin)
    cfg["role"] = newStr(if ok: me.role else: "")
    O(("status", newInt(200)), ("json", cfg))
  of "/native/diag-record":
    # decision 0040: an event for the manager's diagnostics reports (crash, error, sync)
    c.n.record(body["kind"].s, body["text"].s, nowMs())
    return view(O(("ok", newBool(true))))
  of "/native/diag-report":
    let wrote = c.n.maybeReport("android", body["version"].s, body["platform"].s, body["model"].s, nowMs(),
                                body.get("force") != nil and body["force"].kind == jBool and body["force"].b)
    return view(O(("wrote", newBool(wrote))))
  of "/native/relay":
    # §18: the plant's relay (the manager's setting), the room, and a hello signed now by the device key
    let v = if c.n.run != nil: c.n.run.settings.getOrDefault("relay") else: nil
    let relay = if v != nil and v.isStr: v.s else: ""
    if relay.len == 0 or c.n.root.len == 0: return view(O(("relay", newStr(""))))
    let room = relayRoom(c.p, c.n.root)
    view(O(("relay", newStr(relay)), ("room", newStr(room)), ("hello", relayHello(c.p, c.key, room, nowMs() div 1000))))
  of "/native/join-request":
    let req = c.p.joinRequest(c.key, body["username"].s, body["full_name"].s,
                              if body.get("position") != nil: body["position"] else: newNull(), c.api.deviceLabel, nowMs() div 1000)
    O(("status", newInt(200)), ("json", req))
  of "/native/bundle":
    let r = c.n.importBundle(base64.decode(body["data"].s), nowMs())
    O(("status", newInt(200)), ("json", r))
  of "/native/join-code":
    O(("status", newInt(200)), ("json", O(("code", newStr(c.p.joinCode(c.n.device, body["admin"].s))))))
  of "/native/net":
    # the sync service's listener port and addresses (invites carry them) and its status for /api/devices
    c.net = body
    let port = if body.get("port") != nil and body["port"].kind == jInt: int(body["port"].i) else: 0
    var addrs: seq[string]
    if body.get("addrs") != nil and body["addrs"].kind == jArr:
      for x in body["addrs"].elems:
        if x.isStr: addrs.add x.s
    c.api.syncPort = port
    c.api.addresses = proc (): seq[string] = addrs
    c.api.syncSnapshot = proc (): JNode =
      if c.net != nil and c.net.get("snapshot") != nil: c.net["snapshot"] else: newObj()
    view(O(("ok", newBool(true))))
  of "/native/course-files":
    # the app's own courses (docs/COURSES.md), used when the plant has published none
    c.programCourses.setLen(0)
    c.programImages.clear()
    for f in body["files"].elems: c.programCourses.add((f[0].s, f[1].s))
    for i in body["images"].elems: c.programImages.incl i.s
    return view(O(("ok", newBool(true))))
  of "/native/courses", "/native/course":
    var files: seq[(string, string)]
    var images: HashSet[string]
    var fromPlant = false
    let (ok, m) = c.n.active
    if ok:
      for path, (sha, _) in m.files:
        if path.startsWith("courses/"):
          let name = path[8 .. ^1]
          if name.endsWith(".json"): files.add((name, c.store.blobGet(sha)))
          elif name.endsWith(".jxl"): images.incl name
    if files.len > 0: fromPlant = true
    else:
      files = c.programCourses
      images = c.programImages
    let (docs, _) = pickCourses(files, images)
    if path == "/native/courses":
      var lst = newArr()
      for d in docs: lst.elems.add summary(d)
      return view(O(("courses", lst), ("plant", newBool(fromPlant))))
    for d in docs:
      if d["id"].s == arg("id"): return view(O(("course", d), ("plant", newBool(fromPlant))))
    return O(("status", newInt(404)), ("json", O(("error", newStr("no such course")))))
  of "/native/fig-new":
    let (ok2, m2) = c.n.active
    var files: seq[(string, string)]
    var images: HashSet[string]
    if ok2:
      for path, (sha, _) in m2.files:
        if path.startsWith("courses/") and path.endsWith(".json"): files.add((path[8 .. ^1], c.store.blobGet(sha)))
        elif path.startsWith("courses/"): images.incl path[8 .. ^1]
    if files.len == 0:
      files = c.programCourses
      images = c.programImages
    for d in pickCourses(files, images)[0]:
      if d["id"].s == body["course"].s and d["figures"].get(body["figure"].s) != nil:
        return view(O(("fig", newInt(figNew(d["figures"][body["figure"].s], body.get("reduce") != nil and body["reduce"].b)))))
    return O(("status", newInt(404)), ("json", O(("error", newStr("no such figure")))))
  of "/native/fig-free":
    figFree(int(body["fig"].num))
    return view(O(("ok", newBool(true))))
  of "/native/kks-tables": return view(c.tables)
  of "/native/tables":
    c.tables = body
    c.m = nil
    view(O(("ok", newBool(true))))
  of "/native/sheets": view(O(("sheets", sheetsView(c.model))))
  of "/native/tags": view(O(("tags", tagsView(c.model, arg("sheet")))))
  of "/native/search": view(O(("results", searchView(c.model, arg("q")))))
  of "/native/tag": view(tagView(c.model, arg("id")))
  of "/native/review": view(O(("tags", reviewView(c.model))))
  of "/native/procs": view(O(("procs", procsView(c.model))))
  of "/native/proc": view(procView(c.model, arg("id")))
  of "/native/floors": view(floorsView(c.model))
  of "/native/systems": view(systemsView(c.model, arg("q")))
  else: O(("status", newInt(404)), ("json", O(("error", newStr("not found")))))

proc kks_api(h: int64, meth, path: cstring, query: ptr UncheckedArray[byte], qlen: cint, body: ptr UncheckedArray[byte],
             blen: cint, outlen: ptr cint): ptr UncheckedArray[byte] {.exportc, cdecl.} =
  var res: JNode
  try:
    let c = inst(h)
    var qs = newString(int(qlen))
    if qlen > 0: copyMem(addr qs[0], query, int(qlen))
    var bs = newString(int(blen))
    if blen > 0: copyMem(addr bs[0], body, int(blen))
    let q = if qs.len > 0: parseStrict(qs) else: newObj()
    let d = if bs.len > 0: parseStrict(bs, 4096) else: newObj()
    if ($path).startsWith("/native/"):
      res = c.native($meth, $path, d, q)
    else:
      let (ok, me) = c.api.owner
      if not ok:
        res = O(("status", newInt(401)), ("json", O(("error", newStr("this phone has not joined a plant")))))
      else:
        var qt = initTable[string, string]()
        for (k, v) in q.fields: qt[k] = (if v.isStr: v.s else: toText(v))
        let r = c.api.handle(me, $meth, $path, qt, d, nowMs())
        res = O(("status", newInt(r.status)), ("json", if r.json == nil: newNull() else: r.json))
        if r.bytes.len > 0:
          res["bytes"] = newStr(base64.encode(r.bytes))
          res["content_type"] = newStr(r.contentType)
  except ApiError as e:
    res = O(("status", newInt(e.status)), ("json", O(("error", newStr(e.msg)))))
  except CatchableError as e:
    res = O(("status", newInt(500)), ("json", O(("error", newStr(e.msg)))))
  cbytes(toText(res), outlen)

proc kks_file(h: int64, path: cstring, outlen: ptr cint): ptr UncheckedArray[byte] {.exportc, cdecl.} =
  ## a plant-data file, or "photos/<sha256>.<ext>": a photo's blob (nil while this phone doesn't hold it yet)
  try:
    let p = $path
    if p.startsWith("photos/"):
      let sha = p["photos/".len .. ^1].split('.')[0]
      let st = inst(h).n.store
      if st.blobHas(sha): return cbytes(st.blobGet(sha), outlen)
      return nil
    let (ok, data) = inst(h).n.file(p)
    if ok: return cbytes(data, outlen)
  except CatchableError: discard
  nil

proc kks_sync_start(h: int64, initiator: cint, remote, adoptRoot: cstring): int64 {.exportc, cdecl.} =
  try:
    let c = inst(h)
    let hooks = Hooks(join: proc (r: string, m: JNode): JNode =
      result = c.api.invites.offer(c.p, r, m, nowMs() div 1000)
      if result["state"].s == "accepted":
        result["root"] = newStr(c.n.root)
        result["plant"] = c.n.run.settings.getOrDefault("plant"),
      wipe: proc (by: string) =
        # §15: removed by an admin. The store is emptied here; the app then deletes its keys and starts over.
        let note = if by.len > 0: "This phone was removed from the plant by " & by & "." else: "This phone was removed from the plant."
        c.store.wipe(note)
        c.m = nil
        kks_jc_changed(cstring("wiped:" & note)))
    let s = newSession(c.n, initiator != 0, $remote, $adoptRoot, hooks)
    s.wall = nowMs()
    let id = nextSync
    inc nextSync
    syncs[id] = Sync(inst: h, s: s)
    id
  except CatchableError: 0

proc kks_sync_feed(sid: int64, data: ptr UncheckedArray[byte], n: cint, outlen: ptr cint): ptr UncheckedArray[byte] {.exportc, cdecl.} =
  ## TLS plaintext in → TLS plaintext out (framed §15 messages)
  var outp = ""
  if sid in syncs:
    let x = syncs[sid]
    var bs = newString(int(n))
    if n > 0: copyMem(addr bs[0], data, int(n))
    try:
      x.d.add bs
      while true:
        let m = x.d.next(x.s.frameLimit)   # small frames until the other side is trusted (issue #67)
        if m == nil: break
        x.s.wall = nowMs()
        x.s.receive(m)
    except CatchableError as e:
      x.error = e.msg
      x.s.outbox.add errorMsg(e.msg)
    for m in x.s.outbox: outp.add frame(m)
    x.s.outbox.setLen(0)
  cbytes(outp, outlen)

proc kks_sync_info(sid: int64, outlen: ptr cint): ptr UncheckedArray[byte] {.exportc, cdecl.} =
  var j = O(("known", newBool(false)))
  if sid in syncs:
    let x = syncs[sid]
    let st = x.s.stats
    j = O(("known", newBool(true)), ("done", newBool(x.s.done)), ("error", newStr(x.error)),
          ("sent", newInt(st.sent)), ("received", newInt(st.received)), ("blobs_sent", newInt(st.blobsSent)),
          ("blobs_received", newInt(st.blobsReceived)), ("denied", newBool(st.denied)),
          ("trusted", newBool(x.s.trusted)))
  cbytes(toText(j), outlen)

proc kks_sync_end(sid: int64) {.exportc, cdecl.} = syncs.del sid

proc kks_rudp_new(session: ptr UncheckedArray[byte], dead, now: cdouble): int64 {.exportc, cdecl.} =
  var ss = newString(8)
  copyMem(addr ss[0], session, 8)
  let id = nextSync
  inc nextSync
  rudps[id] = newRudp(ss, now, dead)
  id

proc kks_rudp_step(id: int64, op: cint, data: ptr UncheckedArray[byte], n: cint, now: cdouble,
                   outlen: ptr cint): ptr UncheckedArray[byte] {.exportc, cdecl.} =
  ## One event for a stream: op 1 a datagram from the other side, 2 timers, 3 bytes to send, 4 finish, 5 free.
  ## -> flags u8 (1 error, 2 ended, 4 finished) + queued u32 + error (u32 len + bytes) + received (u32 len + bytes)
  ##    + datagrams to send (u16 count, each u16 len + bytes); big-endian
  var outp = ""
  proc u32(x: int) =
    outp.add char((x shr 24) and 0xff); outp.add char((x shr 16) and 0xff); outp.add char((x shr 8) and 0xff); outp.add char(x and 0xff)
  proc u16(x: int) =
    outp.add char((x shr 8) and 0xff); outp.add char(x and 0xff)
  if id notin rudps: return cbytes("\x01\x00\x00\x00\x00\x00\x00\x00\x04gone\x00\x00\x00\x00\x00\x00", outlen)
  let r = rudps[id]
  var bs = newString(int(n))
  if n > 0: copyMem(addr bs[0], data, int(n))
  try:
    case op
    of 1: r.feed(bs, now)
    of 2: r.tick(now)
    of 3: r.write(bs, now)
    of 4: r.finish(now)
    of 5:
      rudps.del id
      return cbytes("", outlen)
    else: discard
  except CatchableError as e:
    if r.error.len == 0: r.error = e.msg
  let got = r.read()
  let dgs = r.takeOut()
  outp.add char((if r.error.len > 0: 1 else: 0) or (if r.ended: 2 else: 0) or (if r.finished: 4 else: 0))
  u32(r.queued)
  u32(r.error.len); outp.add r.error
  u32(got.len); outp.add got
  u16(dgs.len)
  for d in dgs:
    u16(d.len); outp.add d
  cbytes(outp, outlen)

proc kks_sheet(h: int64, id: cstring, outlen: ptr cint): ptr UncheckedArray[byte] {.exportc, cdecl.} =
  ## a sheet's path store, decoded, in views.flat's layout
  try:
    let (ok, data) = inst(h).n.file("sheets/" & $id & ".kkp")
    if ok: return cbytes(flat(pathstore.decode(data)), outlen)
  except CatchableError: discard
  nil

proc kks_fig(h: int64, id: cint, cmd: cstring, outlen: ptr cint): ptr UncheckedArray[byte] {.exportc, cdecl.} =
  ## one frame of a course figure (kksa/figops): the state JSON and the drawing ops; nil when it doesn't exist
  try:
    let r = figFrame(int(id), parseStrict($cmd))
    if r.len > 0: return cbytes(r, outlen)
  except CatchableError: discard
  nil
