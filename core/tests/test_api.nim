import std/[algorithm, unittest, tables, base64, strutils]
import kks/[json, util, crypto, proto, replay, node, sync, plant, api, extras, invites, plantdata]
import testprovider

let P = testProvider()
var clock = 1_790_000_000_000'i64
proc now(): int64 =
  clock += 1000
  clock

proc pump(a, b: Session) =
  while not (a.done and b.done):
    var moved = false
    while a.outbox.len > 0:
      let m = a.outbox[0]; a.outbox.delete(0); b.receive(m); moved = true
    while b.outbox.len > 0:
      let m = b.outbox[0]; b.outbox.delete(0); a.receive(m); moved = true
    if not moved: break

proc sync(a, b: Node, adopt = "") =
  let s1 = newSession(a, true, b.device, adopt)
  let s2 = newSession(b, false, a.device)
  s1.wall = now(); s2.wall = s1.wall
  pump(s1, s2)

proc call(api: Api, me: Actor, meth, path: string, body: JNode = nil, q = initTable[string, string]()): Response =
  api.handle(me, meth, path, q, body, now())

proc j(s: string): JNode = parseStrict(s)

suite "plant API":
  let rootKey = P.p256Generate()
  var mgrNode = newNode(P, newMemStore(), P.p256Generate())
  let mgrId = P.newPersonId()
  discard mgrNode.append("genesis", P.genesisBody(rootKey, "Test plant", mgrNode.device, mgrId, "boss", "The Manager"), now())
  mgrNode.adopt(keyString(rootKey.pub))
  let mgrApi = newApi(mgrNode)
  let (_, mgr) = mgrApi.owner
  var userNode = newNode(P, newMemStore(), P.p256Generate())
  let userApi = newApi(userNode)

  test "certify a join request, the user syncs in":
    let req = P.joinRequest(userNode.key, "ali", "Ali User", newNull(), "phone", now() div 1000)
    let r = mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request", req)]))
    check r.status == 200 and r.json["username"].s == "ali"
    sync(userNode, mgrNode, adopt = mgrNode.root)
    let (ok, _) = userApi.owner
    check ok

  test "a user's proposal waits; the admin approves; the state shows it":
    let (_, ali) = userApi.owner
    let r = userApi.call(ali, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA501","changes":{"notes":"leaks"}},"client_id":"abcdefgh1","note":"seen today"}"""))
    check r.status == 200 and r.json["status"].s == "pending"
    let again = userApi.call(ali, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA501","changes":{"notes":"leaks"}},"client_id":"abcdefgh1"}"""))
    check again.json["duplicate"].b
    sync(userNode, mgrNode)
    let subs = mgrApi.call(mgr, "GET", "/api/submissions").json["submissions"]
    check subs.len == 1 and subs[0]["request_note"].s == "seen today" and subs[0]["by_name"].s == "Ali User"
    let a = mgrApi.call(mgr, "POST", "/api/submissions/" & $subs[0]["id"].i & "/approve")
    check a.status == 200
    check mgrApi.call(mgr, "GET", "/api/state").json["equipment"]["11LAB70AA501"]["notes"].s == "leaks"

  test "conflict: a stale base needs force; a manager value stops an admin":
    let r = mgrApi.call(mgr, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA501","changes":{"notes":"fixed"},"base":{"notes":"old"}}}"""))
    check r.json["status"].s == "conflict"
    let sid = r.json["id"].i
    let x = mgrApi.call(mgr, "POST", "/api/submissions/" & $sid & "/approve")
    check x.status == 409 and x.json["error"].s == "conflict"
    let y = mgrApi.call(mgr, "POST", "/api/submissions/" & $sid & "/approve", j("""{"force":true}"""))
    check y.status == 200
    check mgrApi.call(mgr, "GET", "/api/state").json["equipment"]["11LAB70AA501"]["notes"].s == "fixed"

  test "photos: the image is kept as a blob, votes, pick":
    let (_, ali) = userApi.owner
    let url = "data:image/jxl;base64," & encode("\xff\x0afake jxl codestream")
    let r1 = userApi.call(ali, "POST", "/api/submit", newObj(@[("kind", newStr("photo")),
               ("payload", newObj(@[("kks", newStr("11LAB70AA501")), ("dataUrl", newStr(url)), ("caption", newStr("one"))]))]))
    let r2 = userApi.call(ali, "POST", "/api/submit", newObj(@[("kind", newStr("photo")),
               ("payload", newObj(@[("kks", newStr("11LAB70AA501")), ("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0aother jxl"))), ("caption", newStr("two"))]))]))
    # without an encoder this device takes JPEG XL only (decision 0018)
    let png = userApi.call(ali, "POST", "/api/submit", newObj(@[("kind", newStr("photo")),
               ("payload", newObj(@[("kks", newStr("11LAB70AA501")), ("dataUrl", newStr("data:image/png;base64," & encode("\x89PNG\r\n\x1a\nx")))]))]))
    check png.status == 400
    if r1.status != 200: echo "  ", r1.json
    check r1.json["status"].s == "pending" and r2.json["status"].s == "pending"
    check userApi.call(ali, "POST", "/api/submissions/" & $r1.json["id"].i & "/vote").status == 200
    sync(userNode, mgrNode)
    let subs = mgrApi.call(mgr, "GET", "/api/submissions").json["submissions"]
    var first = 0'i64
    for s in subs.elems:
      if s["kind"].s == "photo" and s["payload"]["caption"].s == "one": first = s["id"].i
    let pick = mgrApi.call(mgr, "POST", "/api/submissions/" & $first & "/pick")
    check pick.json["rejected"].i == 1
    let st = mgrApi.call(mgr, "GET", "/api/state").json
    check st["photos"].len == 1 and st["photos"][0]["file"].s.endsWith(".jxl")

  test "several codes at once: one photo, one place; retries change nothing":
    let (_, ali) = userApi.owner
    let url = "data:image/jxl;base64," & encode("\xff\x0ashared jxl")
    let body = newObj(@[("kind", newStr("photo")), ("client_id", newStr("multi-photo-1")),
                        ("kks", newArr(@[newStr("11LAB70AA501"), newStr("11LAB70AA502"), newStr("11LAB70AA503"), newStr("11LAB70AA501")])),
                        ("payload", newObj(@[("dataUrl", newStr(url)), ("caption", newStr("the three drains"))]))])
    let r = userApi.call(ali, "POST", "/api/submit-many", body)
    if r.status != 200: echo "  ", r.json
    check r.status == 200
    let res = r.json["results"]
    check res.elems.len == 3                                    # the repeated code counts once
    var ids: seq[int64]
    for x in res.elems:
      check x["status"].s == "pending" and x.get("duplicate") == nil
      ids.add x["id"].i
    let again = userApi.call(ali, "POST", "/api/submit-many", body)
    for x in again.json["results"].elems: check x["duplicate"].b
    var codes, photoIds, blobs: seq[string]
    for s in userApi.call(ali, "GET", "/api/submissions").json["submissions"].elems:
      if s["id"].i in ids:
        codes.add s["payload"]["kks"].s
        photoIds.add s["payload"]["photo_id"].s
        blobs.add s["payload"]["file"].s
    codes.sort()
    check codes == @["11LAB70AA501", "11LAB70AA502", "11LAB70AA503"]
    check photoIds[0] != photoIds[1] and photoIds[1] != photoIds[2] and photoIds[0] != photoIds[2]
    check blobs[0] == blobs[1] and blobs[1] == blobs[2]       # one image, kept once
    let place = userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":["11LAB70AA501","11LAB70AA502"],"payload":{"changes":{"area":"pump house","floor":"0"}},"note":"walked today"}"""))
    check place.status == 200 and place.json["results"].elems.len == 2
    # a shared note goes under each code's own note; it doesn't replace it
    let (_, mgr) = mgrApi.owner
    check mgrApi.call(mgr, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA507","changes":{"notes":"old leak"}}}""")).status == 200
    sync(userNode, mgrNode)
    let note = userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":["11LAB70AA507","11LAB70AA508"],"payload":{"append":{"notes":"insulation missing"}}}"""))
    check note.status == 200
    var seen: seq[string]
    for x in note.json["results"].elems:
      for s in userApi.call(ali, "GET", "/api/submissions").json["submissions"].elems:
        if s["id"].i == x["id"].i: seen.add s["payload"]["changes"]["notes"].s
    check seen == @["old leak\ninsulation missing", "insulation missing"]
    check userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"tag_add","kks":["11LAB70AA501"],"payload":{}}""")).status == 400
    check userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":[],"payload":{"changes":{"area":"x"}}}""")).status == 400
    check userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":["not a code!"],"payload":{"changes":{"area":"x"}}}""")).status == 400
  test "a marked tag, corrected while approving":
    let (_, ali) = userApi.owner
    let r = userApi.call(ali, "POST", "/api/submit", j("""{"kind":"tag_add","payload":{"sheet":"lp","bbox":[10,10,60.04,30],"kks":"11lab70aa501","isa":"","note":""}}"""))
    check r.json["status"].s == "pending"
    sync(userNode, mgrNode)
    var sid = 0'i64
    for s in mgrApi.call(mgr, "GET", "/api/submissions").json["submissions"].elems:
      if s["kind"].s == "tag_add": sid = s["id"].i
    check mgrApi.call(mgr, "POST", "/api/submissions/" & $sid & "/approve", j("""{"edit":{"kks":"11LAB70AA501K","isa":"te"}}""")).status == 200
    let t = mgrApi.call(mgr, "GET", "/api/state").json["added_tags"][0]
    check t["suffix"].s == "K" and t["isa"].s == "TE" and t["bbox"][2].num == 60.0

  test "History, revert and restore":
    let h = mgrApi.call(mgr, "GET", "/api/revisions").json["revisions"]
    check h.len >= 3
    var noteRow: JNode
    for row in h.elems:
      if row["entity"].s == "equipment" and row["after"].s.contains("fixed"): noteRow = row
    let rv = mgrApi.call(mgr, "POST", "/api/revisions/" & noteRow["hid"].s & "/revert")
    check rv.status == 200 and rv.json["changed"].i == 1
    check mgrApi.call(mgr, "GET", "/api/state").json["equipment"]["11LAB70AA501"]["notes"].s == "leaks"
    let rs = mgrApi.call(mgr, "POST", "/api/restore", j("""{"rev":0}"""))
    check rs.status == 200
    let st = mgrApi.call(mgr, "GET", "/api/state").json
    check st["equipment"].len == 0 and st["photos"].len == 0 and st["added_tags"].len == 0

  test "people: roles, profile, deactivation":
    let (_, ali) = userApi.owner
    let pid = ali.person
    check userApi.call(ali, "POST", "/api/persons/" & pid, j("""{"role":"admin"}""")).status == 403
    check mgrApi.call(mgr, "POST", "/api/persons/" & pid, j("""{"role":"admin"}""")).status == 200
    check mgrApi.call(mgr, "POST", "/api/profile", j("""{"full_name":"  The   Big Manager ","position":"Head"}""")).status == 200
    check mgrNode.run.persons[mgrId]["full_name"].s == "The Big Manager"
    check mgrApi.call(mgr, "POST", "/api/persons/" & pid, j("""{"active":false}""")).status == 200
    check userNode.device in mgrNode.run.cuts

  test "invite: create, a device asks, the admin accepts":
    mgrApi.syncPort = 8421
    mgrApi.addresses = proc (): seq[string] = @["10.0.0.5:8421"]
    let inv = mgrApi.call(mgr, "POST", "/api/invites").json["invite"]
    let k = P.p256Generate()
    let req = P.joinRequest(k, "dana", "Dana New", newNull(), "tablet", now() div 1000)
    let ack = mgrApi.invites.offer(P, P.peerId(k), newObj(@[("token", inv["token"]), ("request", req)]), now() div 1000)
    check ack["state"].s == "waiting"
    check mgrApi.call(mgr, "POST", "/api/invites/" & inv["token"].s, j("""{"action":"accept"}""")).status == 200
    check P.peerId(k) in mgrNode.run.devices

  test "settings and course progress":
    check mgrApi.call(mgr, "POST", "/api/settings/relay", j("""{"url":"wss://relay.example.dev/"}""")).status == 200
    check mgrNode.run.settings["relay"].s == "wss://relay.example.dev"
    check mgrApi.call(mgr, "POST", "/api/settings/relay", j("""{"url":"http://x"}""")).status == 400
    # #15: ws:// (presence in clear) only to this machine, for tests
    check mgrApi.call(mgr, "POST", "/api/settings/relay", j("""{"url":"ws://relay.example.dev"}""")).status == 400
    check mgrApi.call(mgr, "POST", "/api/settings/relay", j("""{"url":"ws://10.0.0.5:8787"}""")).status == 400
    check mgrApi.call(mgr, "POST", "/api/settings/relay", j("""{"url":"ws://127.0.0.1.evil.dev:80"}""")).status == 400
    check mgrApi.call(mgr, "POST", "/api/settings/relay", j("""{"url":"ws://127.0.0.1:8787"}""")).status == 200
    check mgrApi.call(mgr, "POST", "/api/settings/relay", j("""{"url":"wss://relay.example.dev/"}""")).status == 200
    check mgrApi.call(mgr, "POST", "/api/progress", j("""{"course":"hrsg","data":{"finalBest":"9"}}""")).status == 200
    check mgrApi.call(mgr, "GET", "/api/progress", q = {"course": "hrsg"}.toTable).json["data"]["finalBest"].s == "9"

import kks/bundle
suite "bundles":
  test "a new device joins from a file, with the plant data":
    let rootKey = P.p256Generate()
    var a = newNode(P, newMemStore(), P.p256Generate())
    let me = P.newPersonId()
    discard a.append("genesis", P.genesisBody(rootKey, "Test plant", a.device, me, "boss", "The Manager"), now())
    a.adopt(keyString(rootKey.pub))
    discard a.publish(@[("sheets.json", "[]"), ("sheets/lp.kkp", "KKP1 bytes")], now())
    let file = a.bundle(photos = true, now = now())
    var b = newNode(P, newMemStore(), P.p256Generate())
    let r = b.importBundle(file, now())
    check r["adopted"].b and r["entries"].i == 2 and r["photos"].i == 2
    check b.file("sheets/lp.kkp")[1] == "KKP1 bytes"
    expect ValueError: discard b.importBundle("not gzip", now())
