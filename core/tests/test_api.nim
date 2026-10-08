import std/[unittest, tables, base64, strutils]
from std/times import epochTime
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

proc photoReq(kks, caption, data: string, floor = "", cid = ""): JNode =
  var p = newObj(@[("kks", newStr(kks)), ("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0a" & data))),
                   ("caption", newStr(caption))])
  if floor.len > 0: p["floor"] = newStr(floor)
  result = newObj(@[("kind", newStr("photo")), ("payload", p)])
  if cid.len > 0: result["client_id"] = newStr(cid)

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

  test "a floor sent with a photo: written once, before it":
    let (_, ali) = userApi.owner
    check userApi.call(ali, "POST", "/api/submit", photoReq(K, "", "bad floor", floor = "14 m")).status == 400
    let ok1 = userApi.call(ali, "POST", "/api/submit", photoReq(K, "", "valve one", floor = "2"))
    check ok1.status == 200 and ok1.json["status"].s == "pending" and ok1.json["floor"]["status"].s == "pending"
    # the same floor with the next photo, while the first proposal is open: not proposed twice
    let ok2 = userApi.call(ali, "POST", "/api/submit", photoReq(K, "", "valve two", floor = "2"))
    check ok2.json["status"].s == "pending" and ok2.json["floor"]["status"].s == "unchanged"
    var floors = 0
    for _, e in userNode.entries:
      if e["type"].s == "equipment" and e["body"]["kks"].s == K: inc floors
    check floors == 1
    # without a floor: accepted (the clients ask for the floor first; the core never refuses the photo)
    check userApi.call(ali, "POST", "/api/submit", photoReq(K, "Tag plate", "plate one")).json["status"].s == "pending"
    # an image this device can't take: refused before the floor sent with it is written
    var bad = photoReq("11LAB70AA503", "", "x", floor = "4")
    bad["payload"]["dataUrl"] = newStr("data:image/png;base64," & encode("\x89PNG\r\n\x1a\nx"))
    check userApi.call(ali, "POST", "/api/submit", bad).status == 400
    check "11LAB70AA503" notin userNode.run.equipment
    for _, e in userNode.entries: check not (e["type"].s == "equipment" and e["body"]["kks"].s == "11LAB70AA503")

  test "approvals grouped per code and kind, with the submitter's full name and the tag to open":
    sync(userNode, mgrNode)
    let calls = mgrApi.tagIndexCalls
    let res = mgrApi.call(mgr, "GET", "/api/submissions", q = {"group": "code"}.toTable).json
    check mgrApi.tagIndexCalls == calls + 1     # once per listing, not once per submission
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
    check top["name"].s == "Ali User" and top["rank"].i == 1 and top["key"].s.len == 16
    for f in ["person", "username", "full_name", "position", "role", "active"]: check top.get(f) == nil
    check top["approved"].i == 3 and top["rejected"].i == 1 and top["pending"].i == 1 and top["total"].i == 5
    check top["ratio"].num == 3.0 and top["approval_rate"].num == 0.75
    check top["kinds"]["photos"]["approved"].i == 1 and top["kinds"]["photos"]["rejected"].i == 1
    check top["kinds"]["plates"]["approved"].i == 1 and top["kinds"]["places"]["approved"].i == 1
    check top["kinds"]["links"]["pending"].i == 1
    check top["last"].kind == jInt
    let boss = b["people"][1]
    # approve floor, approve (pick) one photo, approve the plate; the other photo Pick rejected by itself doesn't count
    check boss["name"].s == "The Manager" and boss["direct"].i == 1 and boss["decided"].i == 3 and boss["ratio"].isNull

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
    # the leaderboard leaves a hidden person out too; the log is untouched
    check mgrApi.call(mgr, "GET", "/api/leaderboard").json["people"].len == 1
    let back = mgrApi.call(mgr, "POST", "/api/hidden", newObj(@[("ids", newArr(@[newStr(ali.person)])), ("hide", newBool(false))])).json
    check back["changed"].i == 1
    check mgrApi.call(mgr, "GET", "/api/users").json["users"].len == 2
    check mgrApi.call(mgr, "GET", "/api/leaderboard").json["people"].len == 2

  test "Clear removed keeps a person who was never removed (no device yet)":
    # a person registered before any of their devices joined: not removed, so neither Clear removed nor Hide takes them
    let pid = mgrApi.newHexId
    discard mgrNode.append("person", personBody(pid, "pre", "Pre Registered", "user", newStr("Technician")),
                           int64(epochTime() * 1000))
    check pid in mgrNode.run.persons
    discard mgrApi.call(mgr, "POST", "/api/hidden", j("""{"clear_removed":true}"""))
    var names: seq[string]
    for u in mgrApi.call(mgr, "GET", "/api/users").json["users"].elems: names.add u["username"].s
    check "pre" in names
    check mgrApi.call(mgr, "POST", "/api/hidden", newObj(@[("ids", newArr(@[newStr(pid)]))])).status == 400

  test "photos without a floor are taken; a floor with a photo only fills an empty one; its client_id is its own":
    let r1 = mgrApi.call(mgr, "POST", "/api/submit", photoReq("11LAB70AA502", "", "no floor"))
    check r1.status == 200 and r1.json["status"].s == "approved" and r1.json.get("floor") == nil
    let r2 = mgrApi.call(mgr, "POST", "/api/submit", photoReq("11LAB70AA502", "", "with floor", floor = "1", cid = "abcdefgh77"))
    check r2.json["floor"]["status"].s == "approved"
    check mgrNode.run.equipment["11LAB70AA502"]["floor"].s == "1"
    # a photo whose own client_id looks like a derived one is a new photo, not a duplicate; its floor 7 doesn't
    # overwrite the floor that is set (that is a normal edit)
    let r3 = mgrApi.call(mgr, "POST", "/api/submit", photoReq("11LAB70AA502", "", "third", floor = "7", cid = "f-abcdefgh77"))
    check r3.json.get("duplicate") == nil and r3.json["status"].s == "approved" and r3.json["floor"]["status"].s == "unchanged"
    check mgrNode.run.equipment["11LAB70AA502"]["floor"].s == "1"

  test "credit: a held change goes to who proposed it; a revert gives the value back to who set it":
    # a second admin on this server (as a custodial key of the server would be)
    let sk = P.p256Generate()
    let sreq = P.joinRequest(sk, "sara", "Sara Admin", newStr("Shift engineer"), "server", now() div 1000)
    let sid = mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request", sreq)])).json["person"].s
    check mgrApi.call(mgr, "POST", "/api/persons/" & sid, j("""{"role":"admin"}""")).status == 200
    let (okS, sara) = mgrNode.actorOf(P.peerId(sk), sk)
    check okS and sara.role == "admin"
    # Sara's stale change is held (her own submission row); the manager forces it through: it is written by the
    # manager's key, but it is Sara's contribution
    let held = mgrApi.call(sara, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA501","changes":{"near":"north side"},"base":{"near":"old"}}}"""))
    check held.json["status"].s == "conflict"
    proc row(name: string): JNode =
      for p in mgrApi.call(mgr, "GET", "/api/leaderboard").json["people"].elems:
        if p["name"].s == name: return p
    let bossBefore = row("The Manager")
    check mgrApi.call(mgr, "POST", "/api/submissions/" & $held.json["id"].i & "/approve", j("""{"force":true}""")).status == 200
    var st = mgrApi.call(mgr, "GET", "/api/state").json
    check st["equipment"][K]["near"].s == "north side"
    check st["equipment_by"][K]["near"]["by_name"].s == "Sara Admin"
    check row("Sara Admin")["approved"].i == 1 and row("Sara Admin")["direct"].i == 0
    check row("The Manager")["total"].i == bossBefore["total"].i and row("The Manager")["direct"].i == bossBefore["direct"].i
    # the manager changes Ali's floor, then reverts it: the floor is Ali's again, and the revert counts for nobody
    check st["equipment_by"][K]["floor"]["by_name"].s == "Ali User"
    check mgrApi.call(mgr, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA501","changes":{"floor":"3"},"base":{"floor":"2"}}}""")).json["status"].s == "approved"
    let bossTotal = row("The Manager")["total"].i
    var hid = ""
    for row in mgrApi.call(mgr, "GET", "/api/revisions").json["revisions"].elems:
      if hid.len == 0 and row["entity"].s == "equipment" and row["after"].s.contains("\"floor\":\"3\""): hid = row["hid"].s
    check mgrApi.call(mgr, "POST", "/api/revisions/" & hid & "/revert").status == 200
    st = mgrApi.call(mgr, "GET", "/api/state").json
    check st["equipment"][K]["floor"].s == "2"
    check st["equipment_by"][K]["floor"]["by_name"].s == "Ali User"
    check row("The Manager")["total"].i == bossTotal
    # a field cleared to "" is nobody's: no author shown
    check mgrApi.call(mgr, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA501","changes":{"custom":[{"k":"Description","v":""}]},"base":{"custom":[{"k":"Description","v":"Feed water stop valve"}]}}}""")).status == 200
    check mgrApi.call(mgr, "GET", "/api/state").json["equipment_by"][K].get("custom:Description") == nil

  test "a 2,000-entry log: the leaderboard and the who-and-when walk are computed once per change":
    let rk = P.p256Generate()
    let key = P.p256Generate()
    let st = newMemStore()
    let dev = P.peerId(key)
    var hlc: Hlc
    var prev = ""
    proc put(sq: int64, typ: string, body: JNode) =
      let e = P.makeEntry(key, sq, prev, hlc.now(now()), typ, body)
      prev = P.entryId(e)
      st.putEntry(prev, e)
    put(1, "genesis", P.genesisBody(rk, "Big plant", dev, P.newPersonId(), "boss", "The Manager"))
    for i in 1 .. 2000:
      let code = "11LAB" & align($(i mod 90 + 10), 2, '0') & "AA" & align($(i mod 900 + 100), 3, '0')
      put(int64(i + 1), "equipment", newObj(@[("kks", newStr(code)), ("changes", newObj(@[("notes", newStr("n" & $i))])),
                                              ("base", newObj())]))
    st.setMeta("root", keyString(rk.pub))
    let n = newNode(P, st, key)
    check n.entries.len == 2001
    let a = newApi(n)
    let (_, me) = a.owner
    var t0 = epochTime()
    let b1 = a.call(me, "GET", "/api/leaderboard").json
    let s1 = a.call(me, "GET", "/api/state").json
    let first = epochTime() - t0
    let walks = a.walks
    t0 = epochTime()
    for _ in 1 .. 5:
      discard a.call(me, "GET", "/api/leaderboard")
      discard a.call(me, "GET", "/api/state")
    let again = (epochTime() - t0) / 5
    check a.walks == walks and walks == 2       # nothing new in the log: no new walk
    check b1["people"][0]["direct"].i == 2000 and s1["equipment_by"].len > 0
    echo "  2,001 entries: leaderboard + state ", int(first * 1000), " ms first, ", int(again * 1000), " ms cached"
    discard a.n.append("equipment", j("""{"kks":"11LAB70AA501","changes":{"notes":"new"},"base":{}}"""), now())
    discard a.call(me, "GET", "/api/leaderboard")
    check a.walks == walks + 1

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
