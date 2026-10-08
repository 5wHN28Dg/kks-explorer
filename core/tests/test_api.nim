import std/[unittest, tables, base64, strutils]
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
    let req = P.joinRequest(userNode.key, "ali", "Ali User", newStr("Technician"), "phone", now() div 1000)
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
               ("payload", newObj(@[("kks", newStr("11LAB70AA501")), ("dataUrl", newStr(url)), ("caption", newStr("one")),
                                    ("floor", newStr("3"))]))]))
    # the floor came with the first photo as its own proposal; the second photo counts on that open proposal
    check r1.json["floor"]["status"].s == "pending"
    let r2 = userApi.call(ali, "POST", "/api/submit", newObj(@[("kind", newStr("photo")),
               ("payload", newObj(@[("kks", newStr("11LAB70AA501")), ("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0aother jxl"))), ("caption", newStr("two"))]))]))
    # without an encoder this device takes JPEG XL only (decision 0018)
    let png = userApi.call(ali, "POST", "/api/submit", newObj(@[("kind", newStr("photo")),
               ("payload", newObj(@[("kks", newStr("11LAB70AA501")), ("dataUrl", newStr("data:image/png;base64," & encode("\x89PNG\r\n\x1a\nx")))]))]))
    check png.status == 400
    if r1.status != 200: echo "  ", r1.json
    check r1.json["status"].s == "pending" and r2.json["status"].s == "pending"
    # a tag plate photo is not a competing choice for an equipment photo
    let r3 = userApi.call(ali, "POST", "/api/submit", newObj(@[("kind", newStr("photo")),
               ("payload", newObj(@[("kks", newStr("11LAB70AA501")), ("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0aplate jxl"))), ("caption", newStr("Tag plate · north"))]))]))
    check r3.json["status"].s == "pending"
    check userApi.call(ali, "POST", "/api/submissions/" & $r1.json["id"].i & "/vote").status == 200
    sync(userNode, mgrNode)
    let subs = mgrApi.call(mgr, "GET", "/api/submissions").json["submissions"]
    var first = 0'i64
    for s in subs.elems:
      if s["kind"].s == "photo" and s["payload"]["caption"].s == "one": first = s["id"].i
    let pick = mgrApi.call(mgr, "POST", "/api/submissions/" & $first & "/pick")
    check pick.json["rejected"].i == 1     # "two" only: the tag plate photo stays open
    var plateOpen = false
    for s in mgrApi.call(mgr, "GET", "/api/submissions").json["submissions"].elems:
      if s["kind"].s == "photo" and s["photo_kind"].s == "plate": plateOpen = s["status"].s == "pending"
    check plateOpen
    let st = mgrApi.call(mgr, "GET", "/api/state").json
    check st["photos"].len == 1 and st["photos"][0]["file"].s.endsWith(".jxl")
    check st["photos"][0]["by_name"].s == "Ali User" and st["photos"][0]["kind"].s == "equipment"

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
    let req = P.joinRequest(k, "dana", "Dana New", newStr("Operator"), "tablet", now() div 1000)
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

proc photoReq(kks, caption, data: string, floor = ""): JNode =
  var p = newObj(@[("kks", newStr(kks)), ("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0a" & data))),
                   ("caption", newStr(caption))])
  if floor.len > 0: p["floor"] = newStr(floor)
  newObj(@[("kind", newStr("photo")), ("payload", p)])

suite "screens' requests (who, leaderboard, approvals, position, hiding, floor)":
  let rootKey = P.p256Generate()
  var mgrNode = newNode(P, newMemStore(), P.p256Generate())
  let mgrId = P.newPersonId()
  discard mgrNode.append("genesis", P.genesisBody(rootKey, "Test plant", mgrNode.device, mgrId, "boss", "The Manager"), now())
  mgrNode.adopt(keyString(rootKey.pub))
  discard mgrNode.publish(@[("sheets.json", "[]"), ("tags.json",
    """[{"id":"a:2","sheet":"a","kks":"11LAB70AA501","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":0.9,"bbox":[1,1,9,9]}]""")], now())
  let mgrApi = newApi(mgrNode)
  let (_, mgr) = mgrApi.owner
  var userNode = newNode(P, newMemStore(), P.p256Generate())
  let userApi = newApi(userNode)
  const K = "11LAB70AA501"

  test "a new member needs a position; an existing one adding a device doesn't":
    let none = P.joinRequest(userNode.key, "ali", "Ali User", newNull(), "phone", now() div 1000)
    let r0 = mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request", none)]))
    check r0.status == 400 and "position" in r0.json["error"].s
    let blank = P.joinRequest(userNode.key, "ali", "Ali User", newStr("   "), "phone", now() div 1000)
    check mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request", blank)])).status == 400
    let req = P.joinRequest(userNode.key, "ali", "Ali User", newStr("I&C technician"), "phone", now() div 1000)
    check mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request", req)])).status == 200
    sync(userNode, mgrNode, adopt = mgrNode.root)
    check userApi.owner[0]
    let k2 = P.p256Generate()
    let second = P.joinRequest(k2, "ali", "Ali User", newNull(), "tablet", now() div 1000)
    check mgrApi.call(mgr, "POST", "/api/devices/import-request",
                      newObj(@[("request", second), ("existing_ok", newBool(true))])).status == 200

  test "a photo needs the floor first, or with it":
    let (_, ali) = userApi.owner
    let r = userApi.call(ali, "POST", "/api/submit", photoReq(K, "", "no floor"))
    check r.status == 400 and r.json["need"].s == "floor"
    check userApi.call(ali, "POST", "/api/submit", photoReq(K, "", "bad floor", floor = "14 m")).status == 400
    let ok1 = userApi.call(ali, "POST", "/api/submit", photoReq(K, "", "valve one", floor = "2"))
    check ok1.status == 200 and ok1.json["status"].s == "pending" and ok1.json["floor"]["status"].s == "pending"
    # the open floor proposal is enough for the next photo (equipment or tag plate)
    check userApi.call(ali, "POST", "/api/submit", photoReq(K, "", "valve two")).json["status"].s == "pending"
    check userApi.call(ali, "POST", "/api/submit", photoReq(K, "Tag plate", "plate one")).json["status"].s == "pending"
    # another code: still refused, also for an admin
    check mgrApi.call(mgr, "POST", "/api/submit", photoReq("11LAB70AA502", "", "x")).status == 400

  test "approvals grouped per code and kind, with the submitter's full name and the tag to open":
    sync(userNode, mgrNode)
    let res = mgrApi.call(mgr, "GET", "/api/submissions", q = {"group": "code"}.toTable).json
    check res["groups"].len == 1
    let g = res["groups"][0]
    check g["code"].s == K and g["tag"].s == "a:2" and g["several"].b
    var kinds: Table[string, JNode]
    for k in g["kinds"].elems: kinds[k["kind"].s] = k
    check kinds["equipment_photo"]["several"].b and kinds["equipment_photo"]["pick"].b
    check kinds["equipment_photo"]["items"].len == 2
    check not kinds["plate_photo"]["several"].b and not kinds["plate_photo"]["pick"].b
    check kinds["equipment"]["items"][0]["fields"][0].s == "floor"
    check kinds["equipment_photo"]["items"][0]["by_name"].s == "Ali User"
    check kinds["equipment_photo"]["items"][0]["tag"].s == "a:2"

  test "pick rejects only the same kind of photo; then who took it shows on the state":
    var floorSid, pickSid, plateSid = 0'i64
    for s in mgrApi.call(mgr, "GET", "/api/submissions").json["submissions"].elems:
      if s["kind"].s == "equipment": floorSid = s["id"].i
      elif s["kind"].s == "photo" and s["payload"]["caption"].s == "": pickSid = s["id"].i
      elif s["kind"].s == "photo": plateSid = s["id"].i
    check mgrApi.call(mgr, "POST", "/api/submissions/" & $floorSid & "/approve").status == 200
    check mgrApi.call(mgr, "POST", "/api/submissions/" & $pickSid & "/pick").json["rejected"].i == 1
    check mgrApi.call(mgr, "POST", "/api/submissions/" & $plateSid & "/approve").status == 200
    # the manager's own direct change, and a confirmed description (a custom field)
    check mgrApi.call(mgr, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA501","changes":{"notes":"by the door","custom":[{"k":"Description","v":"Feed water stop valve"}]}}}""")).json["status"].s == "approved"
    let st = mgrApi.call(mgr, "GET", "/api/state").json
    check st["photos"].len == 2
    for p in st["photos"].elems:
      check p["by_name"].s == "Ali User" and p["by"].s == "ali" and p["submitted"].kind == jInt
    let by = st["equipment_by"][K]
    check by["floor"]["by_name"].s == "Ali User"
    check by["notes"]["by_name"].s == "The Manager"
    check by["custom:Description"]["by_name"].s == "The Manager"
    check by["floor"]["at"].i >= by["floor"]["submitted"].i

  test "my proposals: filter by status, kind and field":
    let (_, ali) = userApi.owner
    sync(userNode, mgrNode)
    proc list(qs: openArray[(string, string)]): seq[JNode] =
      userApi.call(ali, "GET", "/api/submissions", q = qs.toTable).json["submissions"].elems
    let rej = list({"status": "rejected", "kind": "photo"})
    check rej.len == 1 and rej[0]["status"].s == "rejected" and rej[0]["kind"].s == "photo"
    let floors = list({"status": "approved", "kind": "equipment", "field": "floor"})
    check floors.len == 1 and floors[0]["fields"][0].s == "floor"
    check list({"status": "approved", "kind": "plate_photo"}).len == 1
    check list({"status": "approved", "kind": "equipment_photo"}).len == 1
    check list({"status": "all", "field": "notes"}).len == 0
    check userApi.call(ali, "GET", "/api/submissions", q = {"status": "maybe"}.toTable).status == 400
    check userApi.call(ali, "GET", "/api/submissions", q = {"kind": "nope"}.toTable).status == 400

  test "leaderboard: per person, per kind, approved/rejected/pending, ratio; every member sees it":
    let (_, ali) = userApi.owner
    check userApi.call(ali, "POST", "/api/submit", j("""{"kind":"link","payload":{"proc":"1.1","step":1,"kks":"11LAB70AA501"}}""")).json["status"].s == "pending"
    sync(userNode, mgrNode)
    let b = userApi.call(ali, "GET", "/api/leaderboard").json
    check b["people"].len == 2
    let top = b["people"][0]
    check top["name"].s == "Ali User" and top["rank"].i == 1
    check top["approved"].i == 3 and top["rejected"].i == 1 and top["pending"].i == 1 and top["total"].i == 5
    check top["ratio"].num == 3.0 and top["approval_rate"].num == 0.75
    check top["kinds"]["photos"]["approved"].i == 1 and top["kinds"]["photos"]["rejected"].i == 1
    check top["kinds"]["plates"]["approved"].i == 1 and top["kinds"]["places"]["approved"].i == 1
    check top["kinds"]["links"]["pending"].i == 1
    check top["last"].kind == jInt
    let boss = b["people"][1]
    check boss["name"].s == "The Manager" and boss["direct"].i == 1 and boss["decided"].i >= 4 and boss["ratio"].isNull

  test "removed devices and people can be hidden from the lists (display only)":
    let (_, ali) = userApi.owner
    check mgrApi.call(mgr, "POST", "/api/hidden", newObj(@[("ids", newArr(@[newStr(userNode.device)]))])).status == 400
    check userApi.call(ali, "POST", "/api/hidden", j("""{"clear_removed":true}""")).status == 403
    check mgrApi.call(mgr, "POST", "/api/persons/" & ali.person, j("""{"active":false}""")).status == 200
    let before = mgrApi.call(mgr, "GET", "/api/devices").json
    check before["all"].len == 3 and before["hidden"].i == 0
    let h = mgrApi.call(mgr, "POST", "/api/hidden", j("""{"clear_removed":true}""")).json
    check h["hidden"].i == 3      # two devices and the person
    let after = mgrApi.call(mgr, "GET", "/api/devices").json
    check after["all"].len == 1 and after["hidden"].i == 2
    check mgrApi.call(mgr, "GET", "/api/devices", q = {"show_hidden": "1"}.toTable).json["all"].len == 3
    var names: seq[string]
    for u in mgrApi.call(mgr, "GET", "/api/users").json["users"].elems: names.add u["username"].s
    check names == @["boss"]
    # the log is untouched: the History and the leaderboard still have them
    check mgrApi.call(mgr, "GET", "/api/leaderboard").json["people"].len == 2
    let back = mgrApi.call(mgr, "POST", "/api/hidden", newObj(@[("ids", newArr(@[newStr(ali.person)])), ("hide", newBool(false))])).json
    check back["changed"].i == 1
    check mgrApi.call(mgr, "GET", "/api/users").json["users"].len == 2

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
