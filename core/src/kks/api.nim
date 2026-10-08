## The plant API: what the pages and the native UIs ask for, as JSON request → JSON response, on top of the node.
## Same paths and shapes as v1 (app.py + server/changes.py, and the Kotlin LocalApi), so the web UI keeps working.
## Network actions (sync now, joining through a server or an invite) are the platform's; the server adds its
## password accounts on top (it passes the signed-in account as the actor).

import std/[algorithm, base64, math, sets, strutils, tables, unicode]
import json, crypto, util, proto, replay, node, plant, progress, invites, extras, plantdata, diagnostics
from model import photoKind

type
  Actor* = object
    ## Who acts: the person and the device whose log gets the entries (this device's own key in peer mode; the
    ## account's custodial key on the server).
    person*, device*: string
    key*: PrivateKey
    username*, fullName*, role*: string
    position*: JNode

  Response* = object
    status*: int
    json*: JNode
    bytes*: string
    contentType*: string
    headers*: seq[(string, string)]

  ApiError* = object of CatchableError
    status*: int
    extra*: JNode

  Api* = ref object
    n*: Node
    invites*: Invites
    rev*: int64
    mode*: string                     ## "peer" or "server"
    plantName*: string
    maxUpload*: int
    deviceLabel*: string
    photoEncoder*: proc (data: string): string   ## to JPEG XL (nil: keep what was sent)
    photoMsPerMp*: int
    syncPort*: int                    ## 0 = sync off
    syncSnapshot*: proc (): JNode
    addresses*: proc (): seq[string]
    relayChanged*: proc ()
    tagIdx: Table[string, string]     ## full code → tag id (tagIndex), for tagIdxKey
    tagIdxKey: string

const
  Kinds = ["equipment", "review", "link", "photo", "photo_delete", "tag_add", "tag_remove"]
  EqFields = ["area", "floor", "elev", "near", "loc", "notes", "custom"]
  Open = ["pending", "conflict"]
  Entities = ["equipment", "review", "link", "photo", "added_tag"]

proc relayLoopbackWs*(url: string): bool =
  ## ws:// (no TLS) is allowed only to this machine: the relay twin in tests (finding #15). Everything else is wss://,
  ## so presence on the relay (the plant's room, device IDs, who is online) is never sent in clear.
  if not url.startsWith("ws://"): return false
  var host = url[5 .. ^1]
  let slash = host.find('/')
  if slash >= 0: host = host[0 ..< slash]
  if host.startsWith("["): host = host[1 .. max(1, host.find(']')) - 1]
  else:
    let colon = host.rfind(':')
    if colon >= 0: host = host[0 ..< colon]
  host == "127.0.0.1" or host == "localhost" or host == "::1"

proc fail*(status: int, msg: string, extra: JNode = nil) {.noreturn.} =
  let e = newException(ApiError, msg)
  e.status = status
  e.extra = extra
  raise e

proc bad(msg: string) {.noreturn.} = fail(400, msg)

proc ok(v: JNode = nil): Response =
  Response(status: 200, json: (if v == nil: newObj(@[("ok", newBool(true))]) else: v), contentType: "application/json")

proc O(fields: varargs[(string, JNode)]): JNode = newObj(@fields)
proc S(s: string): JNode = newStr(s)
proc I(i: int64): JNode = newInt(i)
proc B(b: bool): JNode = newBool(b)
proc orNull(s: string): JNode = (if s.len == 0: newNull() else: newStr(s))

proc newApi*(n: Node, mode = "peer"): Api =
  result = Api(n: n, invites: newInvites(), mode: mode, plantName: "Walkdown", maxUpload: 15 * 1024 * 1024,
               deviceLabel: "laptop", photoMsPerMp: 8000)
  let a = result
  n.listeners.add proc (why: string) =
    inc a.rev
    if why == "received" or why == "adopted":   # a submission row for every proposal that came by sync
      var known: HashSet[string]
      for r in n.store.subs():
        if not r["entry"].isNull: known.incl r["entry"].s
      if n.run != nil:
        for eid, _ in n.run.proposals:
          if eid notin known and eid in n.entries:
            let e = n.entries[eid]
            discard n.store.putSub(O(("id", newNull()), ("client_id", newNull()), ("entry", S(eid)),
                                     ("person", S(n.run.authors.getOrDefault(eid))), ("kind", e["type"]),
                                     ("created", I(e["hlc"][0].i div 1000)), ("held", newNull()), ("status", newNull()),
                                     ("note", newNull()), ("decided_at", newNull())))

proc isAdmin*(a: Actor): bool = a.role in ["admin", "manager"]

proc actorOf*(n: Node, device: string, key: PrivateKey): (bool, Actor) =
  ## The actor for a certified, unrevoked device of a known person.
  if n.run == nil or device notin n.run.devices or device in n.run.cuts: return
  let pid = n.run.devices[device]["person"].s
  if pid notin n.run.persons: return
  let p = n.run.persons[pid]
  (true, Actor(person: pid, device: device, key: key, username: p["username"].s, fullName: p["full_name"].s,
               position: p["position"], role: n.run.role(pid)))

proc owner*(a: Api): (bool, Actor) = a.n.actorOf(a.n.device, a.n.key)

proc need(me: Actor, role: string) =
  if (role == "admin" and not me.isAdmin) or (role == "manager" and me.role != "manager"): fail(403, role & " only")

proc write(a: Api, me: Actor, typ: string, body: JNode, now: int64): string =
  a.n.p.entryId(a.n.appendAs(me.key, typ, body, now))

# ---------------------------------------------------------------- payloads (Payloads.kt / changes.normalize)

proc defaultOf(field: string): JNode = (if field == "custom": newArr() else: newStr(""))

proc kksOf(v: JNode): string =
  if v != nil and v.kind == jStr and v.s.len in 3..24 and v.s.allCharsInSet({'0'..'9', 'A'..'Z', '/'}): v.s
  else: bad("bad KKS")

proc textOf(v: JNode, n = 4000): string =
  if v == nil or v.kind == jNull: return ""
  if v.kind != jStr or v.s.runeLen > n: bad("bad text field")
  v.s.strip

proc intOf(v: JNode): int64 =
  ## Python's int(): numbers, numeric text, booleans.
  if v == nil: bad("bad step")
  case v.kind
  of jInt: v.i
  of jBool: int64(v.b)
  of jFloat: (if v.f.classify in {fcNormal, fcZero, fcNegZero, fcSubnormal}: int64(trunc(v.f)) else: bad("bad step"))
  of jStr:
    try: parseBiggestInt(v.s.strip) except ValueError: bad("bad step")
  else: bad("bad step")

proc numOf(v: JNode): (bool, float) =
  if v == nil: return
  case v.kind
  of jInt: (true, float(v.i))
  of jFloat: (true, v.f)
  of jStr:
    try: (true, parseFloat(v.s.strip)) except ValueError: (false, 0.0)
  else: (false, 0.0)

proc truthy*(v: JNode): bool =
  if v == nil: return false
  case v.kind
  of jNull: false
  of jBool: v.b
  of jInt: v.i != 0
  of jFloat: v.f != 0
  of jStr: v.s.len > 0
  of jArr, jObj: v.len > 0
  of jBig: true

proc isHex32(s: string): bool = s.len == 32 and s.allCharsInSet({'0'..'9', 'a'..'f'})

proc fields(d: JNode): JNode =
  if d.kind != jObj: bad("unknown equipment field")
  result = newObj()
  for (f, v) in d.fields:
    if f notin EqFields: bad("unknown equipment field")
    if f == "custom":
      if v.kind != jArr or v.len > 100: bad("bad custom fields")
      var a = newArr()
      for x in v.elems:
        if x.kind == jObj: a.elems.add O(("k", S(textOf(x.get("k"), 200))), ("v", S(textOf(x.get("v"), 2000))))
      result[f] = a
    else:
      result[f] = S(textOf(v))

proc newHexId*(a: Api): string = hex(a.n.p.randomBytes(16))

proc tagPayload*(a: Api, p: JNode, keepId = ""): JNode =
  ## A hand-marked tag: sheet, box on the sheet image (px), code if readable.
  let sheet = p.get("sheet")
  if sheet == nil or sheet.kind != jStr or not (sheet.s.len in 1..24 and sheet.s[0] in {'a'..'z', '0'..'9'} and
     sheet.s.allCharsInSet({'a'..'z', '0'..'9', '-'})): bad("bad sheet")
  let raw = p.get("bbox")
  if raw == nil or raw.kind != jArr: bad("bad box")
  var bb: seq[float]
  for v in raw.elems:
    let (ok, x) = numOf(v)
    if not ok: bad("bad box")
    bb.add floor(x * 10 + 0.5) / 10
  if bb.len != 4 or not (0 <= bb[0] and bb[0] < bb[2] and bb[2] <= 20000 and 0 <= bb[1] and bb[1] < bb[3] and
     bb[3] <= 20000) or bb[2] - bb[0] < 4 or bb[3] - bb[1] < 4: bad("bad box")
  var code = ""
  for c in textOf(p.get("kks"), 32):
    if not c.isSpaceAscii: code.add c.toUpperAscii
  let isa = textOf(p.get("isa"), 12).toUpperAscii
  if isa.len > 0 and not (isa.len <= 6 and isa.allCharsInSet({'A'..'Z'})): bad("function letters: 1-6 letters, e.g. PI, TIAC")
  var kks, suffix = ""
  if code.len > 0:
    let okCode = code.len >= 12 and code.len <= 16 and code[0..1].allCharsInSet(Digits) and
      code[2..4].allCharsInSet({'A'..'Z'}) and code[5..6].allCharsInSet(Digits) and code[7..8].allCharsInSet({'A'..'Z'}) and
      code[9..11].allCharsInSet(Digits) and code[12 .. ^1].allCharsInSet({'A'..'Z', '0'..'9'})
    if not okCode: bad("That is not a valid KKS (e.g. 11LAB70AA501, suffix allowed)")
    kks = code[0 .. 11]
    suffix = code[12 .. ^1]
  let id = if keepId.len > 0: keepId elif p.get("id") != nil and p["id"].kind == jStr: p["id"].s else: a.newHexId
  var box = newArr()
  for x in bb: box.elems.add newFloat(x)
  O(("id", S(id)), ("sheet", sheet), ("bbox", box), ("kks", orNull(kks)), ("suffix", S(suffix)), ("isa", orNull(isa)),
    ("kind", S(if isa.len > 0: "instrument" else: "equipment")),
    ("orient", S(if bb[3] - bb[1] > bb[2] - bb[0]: "v" else: "h")), ("note", S(textOf(p.get("note"), 500))))

proc normalize*(a: Api, kind: string, p: JNode): JNode =
  ## Validate a client payload -> the payload to keep (photos: the image goes into the blob store).
  if kind notin Kinds or p == nil or p.kind != jObj: bad("bad submission kind or payload")
  case kind
  of "equipment":
    let k = kksOf(p.get("kks"))
    let changes = fields(if p.get("changes") != nil: p["changes"] else: newObj())
    let base = fields(if p.get("base") != nil: p["base"] else: newObj())
    if changes.len == 0: bad("no changes")
    let fl = changes.get("floor")
    if fl != nil and fl.s.len > 0 and not (fl.s == "10" or (fl.s.len == 1 and fl.s[0] in Digits)):
      bad("Floor: a whole number from 0 to 10 (the height goes in Elevation)")
    var bs = newObj()
    for (f, _) in changes.fields: bs[f] = (if base.has(f): base[f] else: defaultOf(f))
    O(("kks", S(k)), ("changes", changes), ("base", bs))
  of "review":
    let tag = textOf(p.get("tag_id"), 64)
    let d = if p.get("data") != nil and p["data"].kind == jObj: p["data"] else: newObj()
    let st = d.get("status")
    if tag.len == 0 or st == nil or st.kind != jStr or st.s notin ["confirmed", "rejected"]: bad("bad review")
    var data = O(("status", st))
    if st.s == "confirmed":
      data["kks"] = S(kksOf(d.get("kks")))
      data["suffix"] = S(textOf(d.get("suffix"), 8))
      data["isa"] = orNull(textOf(d.get("isa"), 12))
    O(("tag_id", S(tag)), ("data", data), ("base", if p.get("base") != nil and p["base"].kind == jObj: p["base"] else: newNull()))
  of "link":
    let pr = textOf(p.get("proc"), 32)
    let k = kksOf(p.get("kks"))
    let step = intOf(p.get("step"))
    if pr.len == 0: bad("bad procedure")
    O(("proc", S(pr)), ("step", I(step)), ("kks", S(k)), ("on", B(if p.has("on"): truthy(p["on"]) else: true)))
  of "photo":
    let k = kksOf(p.get("kks"))
    let url = if p.get("dataUrl") != nil and p["dataUrl"].kind == jStr: p["dataUrl"].s else: ""
    var ok = false
    for t in ["jpeg", "jpg", "png", "webp", "jxl"]:
      if url.startsWith("data:image/" & t & ";base64,"): ok = true
    if not ok: bad("bad image")
    var raw: string
    try:
      var b64 = url[url.find(',') + 1 .. ^1]
      b64 = b64.multiReplace(("\n", ""), ("\r", ""), (" ", ""))
      raw = decode(b64)
    except ValueError: bad("bad image")
    if raw.len > a.maxUpload: bad("image too large")
    if blobExt(raw) notin ["jpg", "png", "webp", "jxl"]: bad("not an image")
    if a.photoEncoder != nil and blobExt(raw) != "jxl":
      try: raw = a.photoEncoder(raw)
      except CatchableError as e: bad("not a readable image (" & e.msg & ")")
    elif blobExt(raw) != "jxl":
      # photos are stored as JPEG XL only (decision 0018); a device without an encoder takes JXL from its clients
      bad("photos must be sent as JPEG XL")
    let sha = a.n.keepBlob(raw)
    O(("kks", S(k)), ("photo_id", S(a.newHexId)), ("file", S(a.n.blobName(sha))), ("blob", S(sha)), ("size", I(raw.len)),
      ("caption", S(textOf(p.get("caption"), 500))))
  of "tag_add": a.tagPayload(p)
  of "tag_remove":
    let id = textOf(p.get("id"), 64)
    if not isHex32(id): bad("bad tag id")
    O(("id", S(id)))
  else:
    let id = textOf(p.get("photo_id"), 64)
    if not isHex32(id): bad("bad photo id")
    O(("photo_id", S(id)))

proc toBody*(kind: string, p: JNode): JNode =
  case kind
  of "photo": O(("photo", p["photo_id"]), ("kks", p["kks"]), ("blob", p["blob"]), ("caption", p["caption"]))
  of "photo_delete": O(("photo", p["photo_id"]))
  of "tag_add":
    var bb = newArr()
    for x in p["bbox"].elems: bb.elems.add I(int64(floor(x.num * 10 + 0.5)))
    O(("tag", p["id"]), ("sheet", p["sheet"]), ("bbox", bb), ("kks", p["kks"]), ("suffix", p["suffix"]), ("isa", p["isa"]),
      ("note", p["note"]))
  of "tag_remove": O(("tag", p["id"]))
  else: p

proc tagOut*(id: string, t: JNode): JNode =
  var bb: seq[float]
  for x in t["bbox"].elems: bb.add float(x.i) / 10
  var box = newArr()
  for x in bb: box.elems.add newFloat(x)
  O(("id", S(id)), ("sheet", t["sheet"]), ("bbox", box), ("kks", t["kks"]), ("suffix", t["suffix"]), ("isa", t["isa"]),
    ("kind", S(if t["isa"].isNull: "equipment" else: "instrument")),
    ("orient", S(if bb[3] - bb[1] > bb[2] - bb[0]: "v" else: "h")), ("note", t["note"]))

proc toPayload(a: Api, kind: string, b: JNode): JNode =
  case kind
  of "photo": O(("photo_id", b["photo"]), ("kks", b["kks"]), ("file", S(a.n.blobName(b["blob"].s))), ("caption", b["caption"]))
  of "photo_delete": O(("photo_id", b["photo"]))
  of "tag_add": tagOut(b["tag"].s, b)
  of "tag_remove": O(("id", b["tag"]))
  else: b

proc valueOut(a: Api, entity: string, key, v: JNode): JNode =
  ## A replay value in the shape History has always shown.
  if v == nil or v.kind == jNull: return newNull()
  if entity == "photo": return O(("kks", v["kks"]), ("file", S(a.n.blobName(v["blob"].s))), ("caption", v["caption"]))
  if entity == "added_tag":
    result = tagOut(key.s, v)
    result.del("id")
    return
  v

proc target(kind: string, b: JNode): string =
  case kind
  of "equipment": "equipment:" & b["kks"].s
  of "review": "review:" & b["tag_id"].s
  of "link": "link:" & b["proc"].s & "|" & $b["step"].i & "|" & b["kks"].s
  of "photo": "photo:" & b["kks"].s
  of "photo_delete": "photo_delete:" & b["photo"].s
  of "tag_add": "tag_add:" & b["sheet"].s
  else: "tag_remove:" & b["tag"].s

# ---------------------------------------------------------------- conflicts, status (LocalNode.kt)

proc managerOwned(a: Api, entity, key: string, field = ""): bool =
  case entity
  of "equipment": a.n.run.eqBy.getOrDefault(key & "\0" & field, (false, "")).manager
  of "review": a.n.run.reviewBy.getOrDefault(key, (false, "")).manager
  else: false

proc plan(a: Api, kind: string, b: JNode): (seq[(string, JNode)], seq[JNode]) =
  ## (targets, conflicts) of a change against the live state.
  let r = a.n.run
  case kind
  of "equipment":
    let k = b["kks"].s
    let cur = r.equipment.getOrDefault(k)
    var cs: seq[JNode]
    for (f, v) in b["changes"].fields:
      let live = if cur != nil and cur.has(f): cur[f] else: defaultOf(f)
      let bs = if b["base"].has(f): b["base"][f] else: defaultOf(f)
      if not pyEq(live, v) and not pyEq(live, bs):
        cs.add O(("field", S(f)), ("base", bs), ("live", live), ("proposed", v), ("manager", B(a.managerOwned("equipment", k, f))))
    (@[("equipment", S(k))], cs)
  of "review":
    let k = b["tag_id"].s
    let live = r.reviews.getOrDefault(k)
    if pyEq(live, b["base"]) or pyEq(live, b["data"]): (@[("review", S(k))], @[])
    else: (@[("review", S(k))], @[O(("field", S("review")), ("base", b["base"]), ("live", if live == nil: newNull() else: live),
                                     ("proposed", b["data"]), ("manager", B(a.managerOwned("review", k))))])
  of "link": (@[("link", newArr(@[b["proc"], b["step"], b["kks"]]))], @[])
  of "photo", "photo_delete": (@[("photo", b["photo"])], @[])
  else: (@[("added_tag", b["tag"])], @[])

proc conflictsOut(cs: seq[JNode]): JNode =
  result = newArr()
  for c in cs:
    var o = newObj()
    for k in ["field", "base", "live", "proposed"]:
      if c.has(k): o[k] = c[k]
    result.elems.add o

proc ts(a: Api, eid: string): JNode =
  if eid in a.n.entries: I(a.n.entries[eid]["hlc"][0].i div 1000) else: newNull()

proc statusOf(a: Api, eid: string): (string, string, string) =
  ## (status, decision entry, note) of an entry written for a submission.
  if eid in a.n.ignored: return ("rejected", "", "not counted: " & a.n.ignored[eid])
  if eid in a.n.run.proposals:
    let d = a.n.run.decisions.getOrDefault(eid)
    return (a.n.run.proposals[eid], (if d == nil: "" else: d["by"].s), (if d == nil: "" else: d["note"].s))
  ("approved", "", "applied directly")

proc personOf(a: Api, dev: string): string =
  if dev in a.n.run.devices: a.n.run.devices[dev]["person"].s else: ""

proc notesTable(a: Api): Table[string, string] =
  for (k, v) in a.n.store.notes(): result[k] = v

proc kindBody(a: Api, r: JNode): (string, JNode) =
  if r["entry"].isNull:
    let h = parseStrict(r["held"].s)
    return (h["kind"].s, h["body"])
  let e = a.n.entries[r["entry"].s]
  (e["type"].s, e["body"])

type SubStatus = object
  status, note, decider: string
  decidedAt: JNode
  conflicts: seq[JNode]

proc subStatus(a: Api, r: JNode): SubStatus =
  let (kind, body) = a.kindBody(r)
  if r["entry"].isNull:
    let open = r["status"].isStr and r["status"].s in Open
    let c = if open: a.plan(kind, body)[1] else: @[]
    return SubStatus(status: (if open: (if c.len > 0: "conflict" else: "pending") else: r["status"].s),
                     note: (if r["note"].isStr: r["note"].s else: ""), decidedAt: r["decided_at"], conflicts: c)
  let eid = r["entry"].s
  var (status, dec, note) = a.statusOf(eid)
  var c: seq[JNode]
  if status == "pending":
    c = a.plan(kind, body)[1]
    if c.len > 0: status = "conflict"
  let decider = if dec.len > 0: a.personOf(a.n.entries[dec]["peer"].s) else: ""
  if note.len == 0 and dec.len > 0: note = a.notesTable.getOrDefault(dec)
  SubStatus(status: status, note: note, decider: decider, conflicts: c,
            decidedAt: (if dec.len > 0: a.ts(dec) elif status == "approved": a.ts(eid) else: newNull()))

proc names(a: Api, person: string): (string, string) =
  if person in a.n.run.persons: (a.n.run.persons[person]["username"].s, a.n.run.persons[person]["full_name"].s)
  else: ("", "")

proc displayName(a: Api, person: string): string =
  ## the full name, else the username ("" = unknown)
  let (u, f) = a.names(person)
  if f.len > 0: f else: u

proc tagIndex*(a: Api): Table[string, string] =
  ## full code (KKS + suffix) → the tag to open on the P&ID: tags.json with the reviews applied (a rejected reading
  ## shows nothing), then the marked tags ("u:<id>", as model.merge). The first tag per code wins. Cached per
  ## plant-data version and log state.
  let (okA, m) = a.n.active
  let sha = if okA and "tags.json" in m.files: m.files["tags.json"][0] else: ""
  let key = sha & "|" & $(if a.n.run != nil: a.n.run.history.len else: 0) & "|" & $a.n.entries.len
  if key == a.tagIdxKey: return a.tagIdx
  var idx: Table[string, string]
  if sha.len > 0:
    let data = a.n.store.blobGet(sha)
    var tags: JNode
    try: tags = parseStrict(data, 4096)
    except JsonError: tags = newArr()
    if tags.kind == jArr:
      for t in tags.elems:
        if t.kind != jObj or t.get("id") == nil or not t["id"].isStr: continue
        let id = t["id"].s
        var code = (if t.get("kks") != nil and t["kks"].isStr: t["kks"].s else: "") &
                   (if t.get("suffix") != nil and t["suffix"].isStr: t["suffix"].s else: "")
        let rv = if a.n.run != nil: a.n.run.reviews.getOrDefault(id) else: nil
        if rv != nil and rv.kind == jObj and rv.get("status") != nil and rv["status"].isStr:
          if rv["status"].s == "rejected": continue
          code = (if rv.get("kks") != nil and rv["kks"].isStr: rv["kks"].s else: "") &
                 (if rv.get("suffix") != nil and rv["suffix"].isStr: rv["suffix"].s else: "")
        if code.len > 0 and code notin idx: idx[code] = id
  if a.n.run != nil:
    for id, t in a.n.run.tags:
      if t["kks"].isStr:
        let code = t["kks"].s & (if t["suffix"].isStr: t["suffix"].s else: "")
        if code notin idx: idx[code] = "u:" & id
  a.tagIdx = idx
  a.tagIdxKey = key
  idx

proc codeOf(a: Api, kind: string, body: JNode): string =
  ## the equipment code a change is about ("" = none: a review, or a marked tag without a code)
  case kind
  of "equipment", "photo", "link": body["kks"].s
  of "tag_add": (if body["kks"].isStr: body["kks"].s & body["suffix"].s else: "")
  of "photo_delete":
    let ph = a.n.run.photos.getOrDefault(body["photo"].s)
    if ph != nil: ph["kks"].s else: ""
  else: ""

proc tagOfChange(a: Api, kind: string, body: JNode, code: string): string =
  case kind
  of "review": body["tag_id"].s
  of "tag_add": "u:" & body["tag"].s
  of "tag_remove": "u:" & body["tag"].s
  else: (if code.len > 0: a.tagIndex.getOrDefault(code) else: "")

proc groupKind*(kind: string, body: JNode): string =
  ## the kind proposals compete within: a photo is an equipment photo or a tag plate photo (caption "Tag plate…",
  ## PROTOCOL-v2 §9), never both
  if kind == "photo": photoKind(body["caption"].s) & "_photo" else: kind

proc fieldsOf(kind: string, body: JNode): seq[string] =
  ## the fields an equipment change sets; custom fields as "custom:<name>" for each name added, changed or removed
  ## against the change's base ("custom" when none can be named)
  if kind != "equipment": return
  for (f, v) in body["changes"].fields:
    if f != "custom":
      result.add f
      continue
    var old: Table[string, string]
    let b = body["base"].get("custom")
    if b != nil and b.kind == jArr:
      for x in b.elems: old[x["k"].s] = x["v"].s
    var named: seq[string]
    var seen: HashSet[string]
    for x in v.elems:
      let k = x["k"].s
      seen.incl k
      if (k notin old or old[k] != x["v"].s) and ("custom:" & k) notin named: named.add "custom:" & k
    for k, _ in old:
      if k notin seen and ("custom:" & k) notin named: named.add "custom:" & k
    if named.len == 0: result.add "custom" else: result.add named

proc subOut(a: Api, r: JNode, me: Actor, live: bool): JNode =
  let (kind, body) = a.kindBody(r)
  let s = a.subStatus(r)
  let (user, full) = a.names(if r["person"].isStr: r["person"].s else: "")
  result = O(("id", r["id"]), ("client_id", r["client_id"]), ("kind", S(kind)), ("target", S(target(kind, body))),
             ("status", S(s.status)), ("created", r["created"]), ("decided_at", s.decidedAt), ("note", S(s.note)),
             ("payload", a.toPayload(kind, body)), ("by", S(if user.len > 0: user else: "?")),
             ("mine", B(r["person"].isStr and r["person"].s == me.person)))
  result["by_name"] = S(if full.len > 0: full else: result["by"].s)
  let code = a.codeOf(kind, body)
  result["code"] = S(code)
  result["tag"] = S(a.tagOfChange(kind, body, code))
  result["group_kind"] = S(groupKind(kind, body))
  if kind == "photo": result["photo_kind"] = S(photoKind(body["caption"].s))
  if kind == "equipment":
    var fs = newArr()
    for f in fieldsOf(kind, body): fs.elems.add S(f)
    result["fields"] = fs
  var requestNote = ""
  if not r["entry"].isNull:
    let eid = r["entry"].s
    let author = a.personOf(a.n.entries[eid]["peer"].s)
    for c in a.n.run.comments.getOrDefault(eid):
      if c["person"].s == author:
        requestNote = c["text"].s
        break
  result["request_note"] = S(requestNote)
  if kind == "photo":
    let voters = if r["entry"].isNull: initHashSet[string]() else: a.n.run.votes.getOrDefault(r["entry"].s)
    result["votes"] = I(voters.len)
    result["voted"] = B(me.person in voters)
  if live and s.status in Open and me.isAdmin:
    result["conflicts"] = conflictsOut(s.conflicts)
    var lv = newArr()
    for (entity, key) in a.plan(kind, body)[0]:
      let k = if entity == "link": S(toText(key)) else: key
      lv.elems.add O(("entity", S(entity)), ("key", k), ("value", a.valueOut(entity, key, a.n.run.getEntity(entity, key))))
    result["live"] = lv

type SubFilter* = object
  ## /api/submissions filters (all optional): kinds (submission kinds or group kinds: equipment_photo, plate_photo),
  ## fields (an equipment change setting any of them: floor, notes, custom, custom:<name>), only my own
  kinds*, fields*: seq[string]
  mine*: bool

const Statuses = ["open", "decided", "all", "pending", "conflict", "approved", "rejected", "withdrawn"]

proc listSubs(a: Api, me: Actor, filter: string, limit: int, f = SubFilter()): seq[JNode] =
  for r in a.n.store.subs():
    let st = a.subStatus(r).status
    if filter == "open" and st notin Open: continue
    if filter == "decided" and st in Open: continue
    if filter notin ["open", "decided", "all"] and st != filter: continue
    if not me.isAdmin and not (r["person"].isStr and r["person"].s == me.person) and not (r["kind"].s == "photo" and st in Open):
      continue
    if f.mine and not (r["person"].isStr and r["person"].s == me.person): continue
    if f.kinds.len > 0 or f.fields.len > 0:
      let (kind, body) = a.kindBody(r)
      if f.kinds.len > 0 and kind notin f.kinds and groupKind(kind, body) notin f.kinds: continue
      if f.fields.len > 0:
        var hit = false
        for x in fieldsOf(kind, body):
          if x in f.fields or (x.startsWith("custom") and "custom" in f.fields): hit = true
        if not hit: continue
    result.add a.subOut(r, me, live = true)
    if result.len >= limit: break

const GroupLabels = [("equipment_photo", "Equipment photo"), ("plate_photo", "Tag plate photo"),
                     ("equipment", "Location and notes"), ("link", "Procedure link"), ("review", "Tag reading"),
                     ("tag_add", "Marked tag"), ("tag_remove", "Remove a marked tag"), ("photo_delete", "Remove a photo")]

proc groupSubs*(subs: seq[JNode]): JNode =
  ## open proposals per code (or per tag when there is no code), then per kind. Proposals of one kind for one code
  ## compete ("several": the clients show Pick and votes only then); an equipment photo and a tag plate photo don't.
  var order: seq[string]
  var groups: Table[string, (string, string, OrderedTable[string, seq[JNode]])]
  for x in subs:
    let code = x["code"].s
    let key = if code.len > 0: "code:" & code else: "tag:" & x["tag"].s
    if key notin groups:
      order.add key
      groups[key] = (code, x["tag"].s, initOrderedTable[string, seq[JNode]]())
    groups[key][2].mgetOrPut(x["group_kind"].s, @[]).add x
  result = newArr()
  for key in order:
    let (code, tag, kinds) = groups[key]
    var ks = newArr()
    var several = false
    for (gk, label) in GroupLabels:
      if gk in kinds:
        let items = kinds[gk]
        several = several or items.len > 1
        ks.elems.add O(("kind", S(gk)), ("label", S(label)), ("several", B(items.len > 1)),
                       ("pick", B(items.len > 1 and gk.endsWith("_photo"))), ("items", newArr(items)))
    result.elems.add O(("code", S(code)), ("tag", S(tag)), ("several", B(several)), ("kinds", ks))

proc subRow(a: Api, id: int64): JNode =
  for r in a.n.store.subs():
    if r["id"].i == id: return r

proc newSubRow(me: Actor, kind: string, clientId: JNode, now: int64): JNode =
  O(("id", newNull()), ("client_id", clientId), ("entry", newNull()), ("person", S(me.person)), ("kind", S(kind)),
    ("created", I(now div 1000)), ("held", newNull()), ("status", newNull()), ("note", newNull()), ("decided_at", newNull()))

proc submitBody*(a: Api, me: Actor, kind: string, body, cid: JNode, requestNote: string, now: int64): JNode =
  ## a change already in its §9 body form: the web/API submissions above and the server's submit-file (a repeated
  ## client_id returns the first submission, so each is written once)
  if cid.isStr:
    for old in a.n.store.subs():
      if old["client_id"].isStr and old["client_id"].s == cid.s:
        let s = a.subStatus(old)
        return O(("id", old["id"]), ("status", S(s.status)), ("note", S(s.note)), ("duplicate", B(true)))
  try: checkData(kind, body)
  except Ignore, KeyError: bad("invalid change")
  let conflicts = a.plan(kind, body)[1]
  var row = newSubRow(me, kind, cid, now)
  if me.isAdmin and conflicts.len > 0:
    row["held"] = S(toText(O(("kind", S(kind)), ("body", body))))
    row["status"] = S("conflict")
    row["note"] = S(toText(conflictsOut(conflicts)))
    let sid = a.n.store.putSub(row)
    return O(("id", I(sid)), ("status", S("conflict")), ("conflicts", conflictsOut(conflicts)))
  let eid = a.write(me, kind, body, now)
  if requestNote.len > 0: discard a.write(me, "comment", O(("entry", S(eid)), ("text", S(requestNote))), now)
  row["entry"] = S(eid)
  let sid = a.n.store.putSub(row)
  if me.isAdmin: O(("id", I(sid)), ("status", S("approved")))
  elif conflicts.len > 0: O(("id", I(sid)), ("status", S("conflict")), ("conflicts", conflictsOut(conflicts)))
  else: O(("id", I(sid)), ("status", S("pending")))

proc submit*(a: Api, me: Actor, kind: string, payload, clientId, noteIn: JNode, now: int64): JNode =
  if noteIn != nil and not noteIn.isNull and (noteIn.kind != jStr or noteIn.s.runeLen > 500): bad("note: up to 500 characters")
  let requestNote = if noteIn != nil and noteIn.isStr: noteIn.s.strip else: ""
  let cid = if clientId == nil: newNull() else: clientId
  if not cid.isNull and not (cid.kind == jStr and cid.s.len in 8..64 and
                             cid.s.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '_', '-'})): bad("bad client_id")
  if cid.isStr:
    for old in a.n.store.subs():
      if old["client_id"].isStr and old["client_id"].s == cid.s:
        let s = a.subStatus(old)
        return O(("id", old["id"]), ("status", S(s.status)), ("note", S(s.note)), ("duplicate", B(true)))
  let p = a.normalize(kind, payload)
  a.submitBody(me, kind, toBody(kind, p), cid, requestNote, now)

proc rebase(a: Api, kind: string, b: JNode): JNode =
  case kind
  of "equipment":
    result = copy(b)
    let cur = a.n.run.equipment.getOrDefault(b["kks"].s)
    var bs = newObj()
    for (f, _) in b["changes"].fields: bs[f] = (if cur != nil and cur.has(f): cur[f] else: defaultOf(f))
    result["base"] = bs
  of "review":
    result = copy(b)
    let cur = a.n.run.reviews.getOrDefault(b["tag_id"].s)
    result["base"] = (if cur == nil: newNull() else: cur)
  else: result = b

proc rejectSub(a: Api, me: Actor, r: JNode, note: string, now: int64) =
  if not r["entry"].isNull: discard a.write(me, "reject", O(("entry", r["entry"]), ("note", S(note))), now)
  else:
    var x = copy(r)
    x["status"] = S("rejected")
    x["note"] = S(note)
    x["decided_at"] = I(now div 1000)
    discard a.n.store.putSub(x)

proc act*(a: Api, me: Actor, sid: int64, action: string, d: JNode, now: int64): JNode =
  let r = a.subRow(sid)
  if r == nil: fail(404, "no such submission")
  var (kind, body) = a.kindBody(r)
  let status = a.subStatus(r).status
  let open = status in Open
  let eid = if r["entry"].isNull: "" else: r["entry"].s
  case action
  of "vote":
    if kind != "photo" or not open or eid.len == 0: bad("only open photo proposals take votes")
    discard a.write(me, "vote", O(("entry", S(eid)), ("on", B(me.person notin a.n.run.votes.getOrDefault(eid)))), now)
    return O(("ok", B(true)))
  of "withdraw":
    if not (r["person"].isStr and r["person"].s == me.person) or not open: fail(403, "can only withdraw your own open submission")
    if eid.len > 0: discard a.write(me, "withdraw", O(("entry", S(eid))), now)
    else:
      var x = copy(r)
      x["status"] = S("withdrawn")
      x["decided_at"] = I(now div 1000)
      discard a.n.store.putSub(x)
    return O(("ok", B(true)))
  else: discard
  need(me, "admin")
  if not open: fail(409, "already " & status)
  if action == "reject":
    let note = if d.get("note") != nil and d["note"].isStr: d["note"].s else: ""
    a.rejectSub(me, r, (if note.runeLen > 500: $note.toRunes[0 ..< 500] else: note), now)
    return O(("ok", B(true)))
  var edit: JNode = newNull()
  if kind == "tag_add" and d.get("edit") != nil and d["edit"].kind == jObj:   # the admin corrects the code while approving
    var p = a.toPayload(kind, body)
    p["kks"] = (if d["edit"].get("kks") != nil: d["edit"]["kks"] else: newNull())
    p["isa"] = (if d["edit"].get("isa") != nil: d["edit"]["isa"] else: newNull())
    let fixed = a.tagPayload(p, body["tag"].s)
    edit = O(("kks", fixed["kks"]), ("suffix", fixed["suffix"]), ("isa", fixed["isa"]))
    body = copy(body)
    for (k, v) in edit.fields: body[k] = v
  let conflicts = a.plan(kind, body)[1]
  if me.role != "manager":
    for c in conflicts:
      if c["manager"].b: fail(403, "The value there was set or approved by the manager; only the manager can overwrite it.")
  if conflicts.len > 0 and not truthy(d.get("force")):
    fail(409, "conflict", O(("conflicts", conflictsOut(conflicts))))
  var note = if conflicts.len > 0: "forced over conflicting change" else: ""
  var written: string
  if eid.len > 0:
    written = a.write(me, "approve", O(("entry", S(eid)), ("edit", edit)), now)
  else:
    written = a.write(me, kind, a.rebase(kind, body), now)
    var x = copy(r)
    x["entry"] = S(written)
    x["held"] = newNull()
    x["status"] = newNull()
    discard a.n.store.putSub(x)
    if not (r["person"].isStr and r["person"].s == me.person):
      let (u, _) = a.names(r["person"].s)
      note = (if note.len > 0: note & "; " else: "") & "proposed by " & (if u.len > 0: u else: "?")
  if note.len > 0: a.n.store.putNote(written, note)
  var rejected = 0
  if action == "pick" and kind == "photo":
    # choose this photo, discard the other open ones of the same kind for the same code: an equipment photo never
    # competes with a tag plate photo (caption "Tag plate…", PROTOCOL-v2 §9)
    let mine = photoKind(body["caption"].s)
    for o in a.n.store.subs():
      if o["id"].i == sid or o["kind"].s != "photo": continue
      let ob = a.kindBody(o)[1]
      if ob["kks"].s == body["kks"].s and photoKind(ob["caption"].s) == mine and a.subStatus(o).status in Open:
        a.rejectSub(me, o, "another photo was chosen (#" & $sid & ")", now)
        inc rejected
  O(("ok", B(true)), ("rejected", I(rejected)))

# ---------------------------------------------------------------- History, revert, restore

type Item = object
  hid: string
  ts: int64
  person, entity: string
  key, before, after: JNode
  sub: JNode
  note: string

proc history*(a: Api): seq[(int64, Item)] =
  let notes = a.notesTable
  var subs: Table[string, int64]
  for r in a.n.store.subs():
    if not r["entry"].isNull: subs[r["entry"].s] = r["id"].i
  var per: Table[string, int]
  var items: seq[(int64, int, Item)]
  for i, h in a.n.run.history:
    let at = h["at"].s
    let k = per.getOrDefault(at, -1) + 1
    per[at] = k
    let e = a.n.entries[at]
    let src = h["source"].s
    items.add((e["hlc"][0].i div 1000, i, Item(hid: at[0 ..< 24] & "-" & $k, ts: e["hlc"][0].i div 1000,
               person: a.personOf(e["peer"].s), entity: h["entity"].s, key: h["key"], before: h["before"],
               after: h["after"], sub: (if src in subs: I(subs[src]) else: newNull()),
               note: (if at in notes: notes[at] else: notes.getOrDefault(src)))))
  items.sort(proc (x, y: (int64, int, Item)): int =
    result = cmp(x[0], y[0])
    if result == 0: result = cmp(x[1], y[1]))
  for n, t in items: result.add((int64(n + 1), t[2]))

proc textOrNull(v: JNode): JNode = (if v.isNull: newNull() else: newStr(toText(v)))

proc historyOut(a: Api, rows: seq[(int64, Item)], meDevicePerson: string): JNode =
  result = newArr()
  for (rev, it) in rows:
    let who = a.n.run.persons.getOrDefault(it.person)
    result.elems.add O(("rev", I(rev)), ("hid", S(it.hid)), ("ts", I(it.ts)),
      ("actor", if it.person == meDevicePerson: I(1) else: newNull()),
      ("username", if who == nil: newNull() else: who["username"]), ("full_name", if who == nil: newNull() else: who["full_name"]),
      ("entity", S(it.entity)), ("key", if it.entity == "link": S(toText(it.key)) else: it.key),
      ("before", textOrNull(a.valueOut(it.entity, it.key, it.before))),
      ("after", textOrNull(a.valueOut(it.entity, it.key, it.after))),
      ("submission_id", it.sub), ("note", S(it.note)))

proc findRow(rows: seq[(int64, Item)], ref0: JNode): int =
  for i, (rev, it) in rows:
    if (ref0.kind == jStr and it.hid == ref0.s) or (ref0.kind == jInt and rev == ref0.i): return i
  bad("no such revision")

proc restoreBody(a: Api, entity: string, key, value: JNode): (bool, string, JNode) =
  ## (type, body) that sets entity `key` to `value` (replay form; null = absent), or false if it already is.
  let cur = a.n.run.getEntity(entity, key)
  if pyEq(cur, value): return
  case entity
  of "equipment":
    let c = if cur == nil: newObj() else: cur
    let v = if value == nil or value.isNull: newObj() else: value
    var ks: seq[string]
    for (k, _) in c.fields: ks.add k
    for (k, _) in v.fields:
      if k notin ks: ks.add k
    ks.sort(system.cmp)
    var changes, base = newObj()
    for f in ks:
      let nv = if v.has(f): v[f] else: defaultOf(f)
      let cv = if c.has(f): c[f] else: defaultOf(f)
      if not pyEq(nv, cv):
        changes[f] = nv
        base[f] = cv
    (true, "equipment", O(("kks", key), ("changes", changes), ("base", base)))
  of "review": (true, "review", O(("tag_id", key), ("data", if value == nil: newNull() else: value), ("base", if cur == nil: newNull() else: cur)))
  of "link": (true, "link", O(("proc", key[0]), ("step", key[1]), ("kks", key[2]), ("on", B(value != nil and not value.isNull))))
  of "photo":
    if value == nil or value.isNull: (true, "photo_delete", O(("photo", key)))
    else:
      var b = O(("photo", key))
      for (k, v) in value.fields: b[k] = v
      (true, "photo", b)
  else:
    if value == nil or value.isNull: (true, "tag_remove", O(("tag", key)))
    else:
      var b = O(("tag", key))
      for (k, v) in value.fields: b[k] = v
      (true, "tag_add", b)

proc putBack(a: Api, me: Actor, targets: seq[(string, JNode, JNode)], note: string, now: int64): int =
  var todo: seq[(string, JNode)]
  for (entity, key, value) in targets:
    let (ok, kind, body) = a.restoreBody(entity, key, value)
    if not ok: continue
    if me.role != "manager":
      var owned = false
      if kind == "equipment":
        for (f, _) in body["changes"].fields:
          if a.managerOwned("equipment", key.s, f): owned = true
      elif kind == "review" and a.managerOwned("review", key.s): owned = true
      if owned: fail(403, toText(key) & ": set or approved by the manager; only the manager can change it back.")
    todo.add((kind, body))
  for (kind, body) in todo: a.n.store.putNote(a.write(me, kind, body, now), note)
  todo.len

proc revert*(a: Api, me: Actor, ref0: JNode, force: bool, now: int64): int =
  let rows = a.history
  let (rev, it) = rows[findRow(rows, ref0)]
  if it.entity notin Entities: bad("only data changes can be reverted")
  let live = a.n.run.getEntity(it.entity, it.key)
  if not pyEq(live, it.after) and not force:
    fail(409, "conflict", O(("conflicts", newArr(@[O(("field", S(it.entity)), ("live", a.valueOut(it.entity, it.key, live)),
         ("proposed", a.valueOut(it.entity, it.key, it.before)), ("note", S("changed again after this revision")))]))))
  a.putBack(me, @[(it.entity, it.key, it.before)], "revert of rev " & $rev, now)

proc restoreTo*(a: Api, me: Actor, ref0: JNode, now: int64): int =
  let rows = a.history
  let start = if ref0.kind == jInt and ref0.i == 0: 0 else: findRow(rows, ref0) + 1
  let rev = if start > 0: rows[start - 1][0] else: 0
  var first: OrderedTable[string, (string, JNode, JNode)]
  for i in start ..< rows.len:
    let it = rows[i][1]
    if it.entity in Entities:
      let k = it.entity & "\0" & toText(it.key)
      if k notin first: first[k] = (it.entity, it.key, it.before)
  var targets: seq[(string, JNode, JNode)]
  for _, t in first: targets.add t
  a.putBack(me, targets, "restore to rev " & $rev, now)

# ---------------------------------------------------------------- people and devices

proc personFields*(d: JNode): (string, JNode) =
  proc clean(v: JNode): string =
    if v == nil or v.kind != jStr: return ""
    var words: seq[string]
    var cur = ""
    for r in v.s.runes:
      if r.isWhiteSpace:
        if cur.len > 0: words.add cur
        cur = ""
      else: cur.add $r
    if cur.len > 0: words.add cur
    words.join(" ")
  let name = clean(d.get("full_name"))
  let pos = clean(d.get("position"))
  if name.runeLen < 2: bad("Enter the full name (so everyone knows whose account this is).")
  if name.runeLen > 80 or pos.runeLen > 80: bad("Full name and position: up to 80 characters each.")
  (name, if pos.len == 0: newNull() else: S(pos))

proc roleOf(a: Api, pid: string): string = a.n.run.role(pid)

proc personBody(a: Api, pid: string, fullName = "", position: JNode = nil, role = "", keepPosition = true): JNode =
  let cur = a.n.run.persons[pid]
  O(("person", S(pid)), ("username", cur["username"]), ("full_name", if fullName.len > 0: S(fullName) else: cur["full_name"]),
    ("position", if keepPosition: cur["position"] else: (if position == nil: newNull() else: position)),
    ("role", if role.len > 0: S(role) else: cur["role"]))

proc lastSeq(a: Api, dev: string): int64 =
  let v = a.n.vv.get(dev)
  if v == nil: 0 else: v[0].i

proc existingPerson(a: Api, username: string): JNode =
  for pid, p in a.n.run.persons:
    if p["username"].s.toLowerAscii == username.toLowerAscii:
      return O(("username", p["username"]), ("full_name", p["full_name"]), ("role", S(a.roleOf(pid))))
  newNull()

proc validUsername*(s: string): bool = s.len in 2..40 and s.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '@', '-'})

proc certify*(a: Api, me: Actor, req: JNode, existingOk: bool, now: int64): JNode =
  ## A checked join request -> device_cert (+ a new person).
  let name = if req.get("username") != nil and req["username"].isStr: req["username"].s else: ""
  if not validUsername(name): bad("the request has an invalid username")
  let (fn, pos) = personFields(req)
  let dev = req["device"].s
  let have = a.n.run.devices.getOrDefault(dev)
  var pid = ""
  for id, p in a.n.run.persons:
    if p["username"].s.toLowerAscii == name.toLowerAscii: pid = id
  if have != nil and have["person"].s != pid: fail(409, "That device is already certified for someone else.")
  if pid.len > 0 and not existingOk:
    fail(409, "existing person", O(("existing", a.existingPerson(name))))
  if pid.len > 0:
    if not (me.role == "manager" or pid == me.person or a.roleOf(pid) == "user"): fail(403, "Only the manager can add devices for admins.")
  else:
    pid = a.newHexId
    discard a.write(me, "person", personBody(pid, name, fn, "user", pos), now)
  if have == nil:
    let label = if req.get("label") != nil and req["label"].isStr: req["label"].s else: ""
    discard a.write(me, "device_cert", deviceCertBody(dev, pid, (if label.runeLen > 80: $label.toRunes[0 ..< 80] else: label)), now)
  O(("ok", B(true)), ("username", S(name)), ("person", S(pid)))

proc usernameOf(r: Run, pid: string): JNode =
  let p = r.persons.getOrDefault(pid)
  if p == nil: newNull() else: p["username"]

proc devicesOut(a: Api, me: Actor): JNode =
  let r = a.n.run
  proc dev(d: string, v: JNode): JNode =
    O(("device", S(d)), ("label", v["label"]), ("person", v["person"]),
      ("username", usernameOf(r, v["person"].s)),
      ("revoked", B(d in r.cuts)), ("this_computer", B(d == a.n.device)))
  var mine, all = newArr()
  var names = newObj()
  for d, v in r.devices:
    let p = r.persons.getOrDefault(v["person"].s)
    names[d] = S((if p == nil: "?" else: p["username"].s) & " · " & (if v["label"].s.len > 0: v["label"].s else: "device"))
    if v["person"].s == me.person: mine.elems.add dev(d, v)
    all.elems.add dev(d, v)
  O(("mine", mine), ("all", if me.isAdmin: all else: newNull()), ("node", S(a.n.device)), ("mode", S(a.mode)),
    ("sync", if a.syncSnapshot != nil: a.syncSnapshot() else: newObj()), ("names", names),
    ("sync_port", if a.syncPort > 0: I(a.syncPort) else: newNull()))

proc usersOut(a: Api, me: Actor): JNode =
  result = newArr(@[O(("id", I(1)), ("username", S(me.username)), ("role", S(me.role)), ("active", B(true)),
                      ("has_password", B(true)), ("created", newNull()), ("full_name", S(me.fullName)),
                      ("position", if me.position.isNull: S("") else: me.position), ("person", S(me.person)))])
  var pids: seq[string]
  for pid, _ in a.n.run.persons: pids.add pid
  pids.sort(proc (x, y: string): int = cmp(a.n.run.persons[x]["username"].s.toLowerAscii, a.n.run.persons[y]["username"].s.toLowerAscii))
  for pid in pids:
    if pid == me.person: continue
    let p = a.n.run.persons[pid]
    var devs, active = 0
    for d, v in a.n.run.devices:
      if v["person"].s == pid:
        inc devs
        if d notin a.n.run.cuts: inc active
    result.elems.add O(("id", newNull()), ("person", S(pid)), ("username", p["username"]), ("full_name", p["full_name"]),
      ("position", if p["position"].isNull: S("") else: p["position"]), ("no_account", B(true)), ("has_password", B(false)),
      ("role", S(a.roleOf(pid))), ("created", newNull()), ("active", B(active > 0)), ("devices", I(devs)))

proc updatePerson(a: Api, me: Actor, pid: string, d: JNode, now: int64): Response =
  need(me, "admin")
  if pid notin a.n.run.persons: fail(404, "no such person")
  let p = a.n.run.persons[pid]
  let tgt = a.roleOf(pid)
  if tgt == "manager" or (tgt == "admin" and me.role != "manager"): fail(403, "not allowed for this person")
  var role = ""
  if d.has("role") and not pyEq(d["role"], p["role"]):
    if me.role != "manager" or not (d["role"].isStr and d["role"].s in ["user", "admin"]):
      fail(403, "only the manager can promote or demote admins")
    role = d["role"].s
  var fn = ""
  var pos: JNode = nil
  var details = false
  if d.has("full_name") or d.has("position"):
    (fn, pos) = personFields(O(("full_name", if d.has("full_name"): d["full_name"] else: p["full_name"]),
                               ("position", if d.has("position"): d["position"] else: p["position"])))
    details = true
  if role.len > 0 or details: discard a.write(me, "person", a.personBody(pid, fn, pos, role, keepPosition = not details), now)
  let act = d.get("active")
  if act != nil and act.kind == jBool and not act.b:
    var devs: seq[string]
    for dev, v in a.n.run.devices:
      if v["person"].s == pid and dev notin a.n.run.cuts: devs.add dev
    for dev in devs: discard a.write(me, "revoke", revokeBody(dev, a.lastSeq(dev)), now)
  elif act != nil and act.kind == jBool and act.b: bad("To come back they join again with a new join request.")
  ok()

proc revokeDevice(a: Api, me: Actor, dev: JNode, now: int64): Response =
  if dev == nil or not dev.isStr or dev.s notin a.n.run.devices: fail(404, "no such device")
  let v = a.n.run.devices[dev.s]
  let tgt = a.roleOf(v["person"].s)
  if not (me.role == "manager" or v["person"].s == me.person or (me.role == "admin" and tgt == "user")):
    fail(403, "not allowed for that device")
  if dev.s == me.device: bad("This is the device you are using; remove it from another one.")
  if dev.s notin a.n.run.cuts: discard a.write(me, "revoke", revokeBody(dev.s, a.lastSeq(dev.s)), now)
  ok()

# ---------------------------------------------------------------- outputs

proc noteOf(removed: string): JNode =
  ## the wipe note (§15): JSON from the Python peer, plain text from DbStore.wipe
  try: parseStrict(removed) except JsonError: S(removed)

proc configOut*(a: Api): JNode =
  let plantN = if a.n.run != nil and a.n.run.settings.getOrDefault("plant") != nil: a.n.run.settings["plant"] else: newNull()
  let (joined, _) = a.owner
  let removed = a.n.store.getMeta("removed")
  O(("plant_name", if plantN.isNull: S(a.plantName) else: plantN), ("offline_days", I(3650)), ("mode", S(a.mode)),
    ("setup_needed", B(false)), ("diagnostics", B(a.n.diagnosticsKey.len > 0)),
    ("photo_upload", if a.photoEncoder != nil: O(("type", S("image/png")), ("ms_per_mp", I(a.photoMsPerMp)))
                     else: O(("type", S("image/jxl")), ("distance", newFloat(1.9)), ("effort", I(7)))),
    ("node", O(("joined", B(joined)), ("device", S(a.n.device)), ("has_plant", B(a.n.root.len > 0)), ("plant", plantN),
               ("can_create", B(true)),
               ("removed", if not joined and removed.len > 0: noteOf(removed) else: newNull()))))

proc stateOut(a: Api, me: Actor): JNode =
  let r = a.n.run
  var created: Table[string, int64]
  for h in r.history:
    if h["entity"].s == "photo" and h["before"].isNull and not h["after"].isNull:
      created[h["key"].s] = a.n.entries[h["at"].s]["hlc"][0].i div 1000
  var photos: seq[JNode]
  for k, v in r.photos:
    photos.add O(("id", S(k)), ("kks", v["kks"]), ("file", S(a.n.blobName(v["blob"].s))), ("caption", v["caption"]),
                 ("created", if k in created: I(created[k]) else: newNull()))
  photos.sort(proc (x, y: JNode): int =
    result = cmp(if x["created"].isNull: 0'i64 else: x["created"].i, if y["created"].isNull: 0'i64 else: y["created"].i)
    if result == 0: result = cmp(x["id"].s, y["id"].s))
  var eq, rv, tags, links = newObj()
  for k, v in r.equipment: eq[k] = v
  for k, v in r.reviews: rv[k] = v
  links = newArr()
  for l in r.state()["links"].elems: links.elems.add O(("proc", l[0]), ("step", l[1]), ("kks", l[2]))
  tags = newArr()
  for k, v in r.tags: tags.elems.add tagOut(k, v)
  let opn = a.listSubs(me, "open", 1_000_000)
  var mine = newArr()
  for s in opn:
    if s["mine"].b: mine.elems.add s
  result = O(("equipment", eq), ("reviews", rv), ("photos", newArr(photos)), ("links", links), ("added_tags", tags),
             ("rev", I(r.history.len)), ("mine", mine))
  if me.isAdmin: result["queue"] = I(opn.len)

proc publicUser*(me: Actor): JNode =
  O(("id", I(1)), ("username", S(me.username)), ("role", S(me.role)), ("active", B(true)), ("has_password", B(true)),
    ("created", newNull()), ("full_name", S(me.fullName)), ("position", if me.position.isNull: S("") else: me.position),
    ("person", S(me.person)))

# ---------------------------------------------------------------- routes

proc qint(q: Table[string, string], k: string, default: int): int =
  try: (if k in q: parseInt(q[k]) else: default) except ValueError: default

proc route*(a: Api, me: Actor, meth, path: string, q: Table[string, string], d: JNode, now: int64): Response =
  ## One request of a signed-in actor. Raises ApiError.
  if meth == "GET":
    case path
    of "/api/me": return ok(O(("user", publicUser(me)), ("offline_days", I(3650)), ("transfer_offer", B(false)),
                               ("transfer_pending", newNull())))
    of "/api/state": return ok(a.stateOut(me))
    of "/api/submissions":
      # ?status=open|decided|all|pending|conflict|approved|rejected|withdrawn &kind=photo,equipment_photo,…
      # &field=floor,custom:Description &mine=1 &group=code (adds "groups": per code, per kind)
      let status = q.getOrDefault("status", "open")
      if status notin Statuses: bad("bad status")
      proc list(k: string): seq[string] =
        for x in q.getOrDefault(k).split(','):
          if x.strip.len > 0: result.add x.strip
      let f = SubFilter(kinds: list("kind"), fields: list("field"), mine: q.getOrDefault("mine") in ["1", "true"])
      for k in f.kinds:
        if k notin Kinds and k notin ["equipment_photo", "plate_photo"]: bad("bad kind: " & k)
      let subs = a.listSubs(me, status, min(q.qint("limit", 200), 1000), f)
      var res = O(("submissions", newArr(subs)))
      if q.getOrDefault("group") == "code": res["groups"] = groupSubs(subs)
      return ok(res)
    of "/api/revisions":
      need(me, "admin")
      let before = q.qint("before", high(int))
      let limit = min(q.qint("limit", 100), 500)
      var rows: seq[(int64, Item)]
      for x in a.history:
        if x[0] < before: rows.add x
      if rows.len > limit: rows = rows[^limit .. ^1]
      rows.reverse()
      return ok(O(("revisions", a.historyOut(rows, me.person))))
    of "/api/users":
      need(me, "admin")
      return ok(O(("users", a.usersOut(me))))
    of "/api/devices": return ok(a.devicesOut(me))
    of "/api/diagnostics":
      # §13a: everyone sees whether reports are on (the app tells its person); the manager also sees the reports
      var o = O(("on", B(a.n.diagnosticsKey.len > 0)), ("pending", I(a.n.pending.len)))
      if me.role == "manager":
        o["can_switch"] = B(a.mode != "server")
        o["can_read"] = B(a.n.canRead)
        o["reports"] = a.n.readReports
      return ok(o)
    of "/api/progress":
      let got = a.n.loadProgress(me.person)
      proc dataOf(c: OrderedTable[string, string]): JNode =
        result = newObj()
        for k, v in c: result[k] = S(v)
      if "course" in q:
        return ok(O(("data", if q["course"] in got: dataOf(got[q["course"]]) else: newObj())))
      var all = newObj()
      for c, v in got: all[c] = dataOf(v)
      return ok(O(("courses", all)))
    of "/api/join-requests":
      need(me, "admin")
      var lst = newArr()
      for (key, ask) in a.invites.pending(now div 1000):
        if key.startsWith("lobby:"):
          let req = ask.request
          lst.elems.add O(("device", S(ask.device)), ("request", req), ("seen", I(ask.seen)), ("exp", I(ask.exp)),
                          ("code", S(a.n.p.joinCode(ask.device, a.n.device))),
                          ("existing", a.existingPerson(req["username"].s)))
      return ok(O(("requests", lst)))
    else:
      if path.startsWith("/api/invites/"):
        need(me, "admin")
        let tok = path["/api/invites/".len .. ^1]
        if tok notin a.invites.items or a.invites.items[tok].by != me.person: fail(404, "no such invite")
        let v = a.invites.items[tok]
        let state = if v.exp < now div 1000 and v.state in ["open", "asked"]: "expired" else: v.state
        return ok(O(("state", S(state)), ("exp", I(v.exp)), ("request", if v.request == nil: newNull() else: v.request),
                    ("seen", I(v.seen)), ("existing", if v.request == nil: newNull() else: a.existingPerson(v.request["username"].s))))
      fail(404, "not found")
  if meth != "POST": fail(405, "method not allowed")
  let parts = path.split('/')
  # /api/submissions/<id>/<action>
  if parts.len == 5 and parts[2] == "submissions" and parts[4] in ["vote", "withdraw", "approve", "reject", "pick"]:
    let sid = try: parseBiggestInt(parts[3]) except ValueError: fail(404, "not found")
    return ok(a.act(me, sid, parts[4], d, now))
  if parts.len == 5 and parts[2] == "revisions" and parts[4] == "revert":
    need(me, "admin")
    let ref0 = try: I(parseBiggestInt(parts[3])) except ValueError: S(parts[3])
    return ok(O(("ok", B(true)), ("changed", I(a.revert(me, ref0, truthy(d.get("force")), now)))))
  if parts.len == 4 and parts[2] == "persons" and isHex32(parts[3]): return a.updatePerson(me, parts[3], d, now)
  if parts.len == 4 and parts[2] == "invites":
    need(me, "admin")
    let tok = parts[3]
    let action = if d.get("action") != nil and d["action"].isStr: d["action"].s else: ""
    if action == "cancel":
      if tok in a.invites.items and a.invites.items[tok].by == me.person: a.invites.cancel(tok)
      return ok()
    if action notin ["accept", "refuse"]: bad("bad action")
    if tok notin a.invites.items or a.invites.items[tok].by != me.person or a.invites.items[tok].state != "asked" or
       a.invites.items[tok].exp < now div 1000:
      fail(409, "No device is waiting on this invite (it expired, or was decided already).")
    let req = a.invites.items[tok].request
    if action == "refuse":
      discard a.invites.decide(tok, false, now div 1000)
      return ok()
    let res = a.certify(me, req, truthy(d.get("existing_ok")), now)
    discard a.invites.decide(tok, true, now div 1000)
    return ok(res)
  if parts.len == 4 and parts[2] == "join-requests":
    need(me, "admin")
    let dev = parts[3]
    let action = if d.get("action") != nil and d["action"].isStr: d["action"].s else: ""
    if action notin ["accept", "refuse"]: bad("bad action")
    if dev notin a.invites.lobby or a.invites.lobby[dev].state != "asked":
      fail(409, "That device is no longer waiting (it gave up, or was decided already).")
    if action == "refuse":
      discard a.invites.decide("lobby:" & dev, false, now div 1000)
      return ok()
    let res = a.certify(me, a.invites.lobby[dev].request, truthy(d.get("existing_ok")), now)
    discard a.invites.decide("lobby:" & dev, true, now div 1000)
    return ok(res)
  case path
  of "/api/submit":
    let kind = if d.get("kind") != nil and d["kind"].isStr: d["kind"].s else: ""
    return ok(a.submit(me, kind, d.get("payload"), d.get("client_id"), d.get("note"), now))
  of "/api/profile":
    let (fn, pos) = personFields(d)
    if fn != me.fullName or not pyEq(pos, me.position):
      discard a.write(me, "person", a.personBody(me.person, fn, pos, keepPosition = false), now)
    return ok()
  of "/api/restore":
    need(me, "admin")
    let r0 = if d.get("hid") != nil: d["hid"] else: d.get("rev")
    if r0 == nil or not ((r0.kind == jInt and r0.i >= 0) or r0.kind == jStr): bad("hid (a History row) or rev 0 is required")
    return ok(O(("ok", B(true)), ("changed", I(a.restoreTo(me, r0, now)))))
  of "/api/devices/import-request":
    need(me, "admin")
    let req = d.get("request")
    if not a.n.p.checkJoinRequest(req): bad("bad join request")
    return ok(a.certify(me, req, truthy(d.get("existing_ok")), now))
  of "/api/devices/revoke": return a.revokeDevice(me, d.get("device"), now)
  of "/api/settings/relay":
    need(me, "manager")
    var url = if d.get("url") != nil and d["url"].isStr: d["url"].s.strip else: ""
    while url.endsWith("/"): url.setLen(url.len - 1)
    if url.len > 0 and not ((url.startsWith("wss://") or relayLoopbackWs(url)) and
                            url.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '.', '-', ':', '/', '_', '~'})):
      bad("The relay address looks like wss://kks-relay.example.workers.dev (ws:// only to this machine, for tests)")
    discard a.write(me, "setting", O(("key", S("relay")), ("value", orNull(url))), now)
    if a.relayChanged != nil: a.relayChanged()
    return ok()
  of "/api/settings/plant":
    need(me, "manager")
    let name = if d.get("name") != nil and d["name"].isStr: d["name"].s.strip else: ""
    if name.len > 80: bad("A plant name of 80 characters or fewer")
    discard a.write(me, "setting", O(("key", S("plant")), ("value", S(name))), now)    # "" = no name shown
    return ok()
  of "/api/diagnostics":
    need(me, "manager")
    if a.mode == "server":
      bad("Switch diagnostics reports on or off from your own laptop or phone: a server holds no key to read them.")
    let on = truthy(d.get("on"))
    try:
      if on: a.n.enable(now) else: a.n.disable(now)
    except ValueError as e: bad(e.msg)
    return ok(O(("on", B(on))))
  of "/api/progress":
    let course = if d.get("course") != nil and d["course"].isStr: d["course"].s else: ""
    var data: OrderedTable[string, string]
    let dd = d.get("data")
    if dd == nil or dd.kind != jObj: bad("nothing to save")
    for (k, v) in dd.fields:
      if v.kind != jStr: bad("bad progress value")
      data[k] = v.s
    try: discard a.n.saveProgress(course, data, now)
    except ValueError as e: bad(e.msg)
    return ok()
  of "/api/invites":
    need(me, "admin")
    if a.syncPort == 0: fail(409, "Sync is off on this device, so devices cannot join through it.")
    let addrs = if a.addresses != nil: a.addresses() else: @[]
    if addrs.len == 0: fail(409, "This device is not on a network other devices could reach.")
    let plantN = if a.n.run.settings.getOrDefault("plant") != nil: a.n.run.settings["plant"].s else: a.plantName
    let inv = a.invites.create(a.n.p, me.person, a.n.root, plantN, a.n.device, addrs, now div 1000)
    return ok(O(("ok", B(true)), ("invite", inv), ("code", S(toText(inv)))))
  else: fail(404, "not found")

proc handle*(a: Api, me: Actor, meth, path: string, q: Table[string, string], body: JNode, now: int64): Response =
  ## route() with errors turned into responses, and the change counter pages poll.
  let d = if body != nil and body.kind == jObj: body else: newObj()
  try:
    result = a.route(me, meth, path, q, d, now)
  except ApiError as e:
    var j = O(("error", S(e.msg)))
    if e.extra != nil:
      for (k, v) in e.extra.fields: j[k] = v
    result = Response(status: e.status, json: j, contentType: "application/json")
  if meth == "POST" and result.status < 400: inc a.rev
