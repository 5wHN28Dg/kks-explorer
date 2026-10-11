import std/[algorithm, unittest, tables, base64, strutils]
from std/times import epochTime
import kks/[json, util, crypto, proto, replay, node, sync, plant, api, extras, invites, plantdata, relaykey]
import testprovider

let P = testProvider()
var clock = 1_790_000_000_000'i64
proc now(): int64 =
  clock += 1000
  clock

proc pump(a, b: Session) =
  while not (a.done and b.done):
    var moved = false
    while a.sending:
      for m in a.take(): b.receive(m); moved = true
    while b.sending:
      for m in b.take(): a.receive(m); moved = true
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
      check x["status"].s == "pending"            # not held as a clash with the note it extends
      for s in userApi.call(ali, "GET", "/api/submissions").json["submissions"].elems:
        if s["id"].i == x["id"].i: seen.add s["payload"]["changes"]["notes"].s
    check seen == @["old leak\ninsulation missing", "insulation missing"]
    # a place over a code's existing value replaces it (the client says so first), it isn't held as a clash
    check mgrApi.call(mgr, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA509","changes":{"floor":"1"}}}""")).status == 200
    sync(userNode, mgrNode)
    let over = mgrApi.call(mgr, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":["11LAB70AA509","11LAB70AA510"],"payload":{"changes":{"floor":"3"}}}"""))
    for x in over.json["results"].elems: check x["status"].s == "approved"
    check userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"tag_add","kks":["11LAB70AA501"],"payload":{}}""")).status == 400
    check userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":[],"payload":{"changes":{"area":"x"}}}""")).status == 400
    check userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":["not a code!"],"payload":{"changes":{"area":"x"}}}""")).status == 400
  test "several codes at once: all checked before any is written; a value changed meanwhile is a clash":
    let (_, ali) = userApi.owner
    let (_, mgr) = mgrApi.owner
    # code B's notes are long: appended, they go over the field's 4000 characters. Nothing is written, not even A's.
    check mgrApi.call(mgr, "POST", "/api/submit", newObj(@[("kind", newStr("equipment")), ("payload", newObj(@[
      ("kks", newStr("11LAB70AA602")), ("changes", newObj(@[("notes", newStr("x".repeat(3990)))]))]))])).status == 200
    sync(userNode, mgrNode)
    let before = userApi.call(ali, "GET", "/api/submissions").json["submissions"].elems.len
    let r = userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":["11LAB70AA601","11LAB70AA602"],"payload":{"append":{"notes":"a longer note that will not fit"}},"client_id":"partial-1"}"""))
    check r.status == 400
    check userApi.call(ali, "GET", "/api/submissions").json["submissions"].elems.len == before
    # a refused note keeps no photo
    let data = "\xff\x0aa photo for a refused note"
    let sha = hex(userNode.p.sha256(data.toBytes))
    let ph = userApi.call(ali, "POST", "/api/submit-many", newObj(@[("kind", newStr("photo")),
      ("kks", newArr(@[newStr("11LAB70AA601")])), ("note", newStr("n".repeat(501))),
      ("payload", newObj(@[("dataUrl", newStr("data:image/jxl;base64," & encode(data)))]))]))
    check ph.status == 400 and not userNode.store.blobHas(sha)
    # the person was shown "area: (none)" for 11LAB70AA603; meanwhile the manager set it: sent with that base, a clash
    check mgrApi.call(mgr, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA603","changes":{"area":"boiler house"}}}""")).status == 200
    let st = mgrApi.call(mgr, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":["11LAB70AA603","11LAB70AA604"],"payload":{"changes":{"area":"pump house"},"bases":{"11LAB70AA603":{"area":""},"11LAB70AA604":{"area":""}}}}"""))
    check st.status == 200
    check st.json["results"][0]["status"].s == "conflict"       # the manager's newer value isn't overwritten silently
    check st.json["results"][1]["status"].s != "conflict"
    # a field both set and appended to: refused (the append used to replace the change silently)
    check userApi.call(ali, "POST", "/api/submit-many", j("""{"kind":"equipment","kks":["11LAB70AA605"],"payload":{"changes":{"notes":"new"},"append":{"notes":"more"}}}""")).status == 400
  test "one photo for several codes with a floor: the single photo's rule, for each code by itself":
    let (_, ali) = userApi.owner
    let (_, mgr) = mgrApi.owner
    const NoFloor = "11LAB80AA701"
    const NoFloor2 = "11LAB80AA702"
    const HasFloor = "11LAB80AA703"
    const MineOpen = "11LAB80AA704"
    proc floorEntries(n: Node, kks: string): seq[string] =
      for _, e in n.entries:
        if e["type"].s == "equipment" and e["body"]["kks"].s == kks and e["body"]["changes"].get("floor") != nil:
          result.add e["body"]["changes"]["floor"].s
    proc many(codes: openArray[string], floor: string, cid = "", data = "shared"): JNode =
      var p = newObj(@[("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0a" & data))), ("caption", newStr(""))])
      if floor.len > 0: p["floor"] = newStr(floor)
      var ks = newArr()
      for c in codes: ks.elems.add newStr(c)
      result = newObj(@[("kind", newStr("photo")), ("kks", ks), ("payload", p)])
      if cid.len > 0: result["client_id"] = newStr(cid)
    check mgrApi.call(mgr, "POST", "/api/submit", newObj(@[("kind", newStr("equipment")), ("payload", newObj(@[
      ("kks", newStr(HasFloor)), ("changes", newObj(@[("floor", newStr("5"))]))]))])).status == 200
    sync(userNode, mgrNode)
    check userApi.call(ali, "POST", "/api/submit", newObj(@[("kind", newStr("equipment")), ("payload", newObj(@[
      ("kks", newStr(MineOpen)), ("changes", newObj(@[("floor", newStr("4"))]))]))])).json["status"].s == "pending"
    # a floor that isn't one refuses the set before anything is written (as a single photo's does)
    let before = userNode.entries.len
    check userApi.call(ali, "POST", "/api/submit-many", many([NoFloor, HasFloor], "14 m")).status == 400
    check userNode.entries.len == before
    # mixed: no floor / has a floor / my own open proposal. No photo is refused; each code's result says what
    # happened to its floor
    let body = many([NoFloor, HasFloor, MineOpen, NoFloor2], "2", cid = "many-floor-1")
    let r = userApi.call(ali, "POST", "/api/submit-many", body)
    if r.status != 200: echo "  ", r.json
    check r.status == 200
    let res = r.json["results"]
    check res.elems.len == 4
    for x in res.elems: check x["status"].s == "pending" and x.get("duplicate") == nil
    check res[0]["floor"]["status"].s == "pending" and res[0]["floor"]["id"].i != res[0]["id"].i
    check res[1]["floor"]["status"].s == "unchanged" and res[1]["floor"]["floor"].s == "5"
    check res[2]["floor"]["status"].s == "unchanged" and res[2]["floor"]["floor"].s == "4"
    check res[3]["floor"]["status"].s == "pending"
    check floorEntries(userNode, NoFloor) == @["2"] and floorEntries(userNode, NoFloor2) == @["2"]
    check floorEntries(userNode, HasFloor) == @["5"] and floorEntries(userNode, MineOpen) == @["4"]
    # the proposals are ordinary ones: this person's, open, for the floor field
    var mine: seq[string]
    for s in userApi.call(ali, "GET", "/api/submissions", q = {"status": "open", "kind": "equipment", "field": "floor",
                                                              "mine": "1"}.toTable).json["submissions"].elems:
      if s["payload"]["kks"].s in [NoFloor, NoFloor2]: mine.add s["payload"]["kks"].s & "=" & s["payload"]["changes"]["floor"].s
    mine.sort()
    check mine == @[NoFloor & "=2", NoFloor2 & "=2"]
    # a retry writes nothing, floors neither
    let n1 = userNode.entries.len
    let again = userApi.call(ali, "POST", "/api/submit-many", body)
    for x in again.json["results"].elems: check x["duplicate"].b and x.get("floor") == nil   # a duplicate says nothing of a floor
    check userNode.entries.len == n1
    # the next photo for the same codes, another floor typed: the open proposals stand, nothing competes with them
    let next = userApi.call(ali, "POST", "/api/submit-many", many([NoFloor, NoFloor2], "7", data = "second"))
    check next.status == 200
    for x in next.json["results"].elems:
      check x["status"].s == "pending" and x["floor"]["status"].s == "unchanged" and x["floor"]["floor"].s == "2"
    check floorEntries(userNode, NoFloor) == @["2"] and floorEntries(userNode, NoFloor2) == @["2"]
    # without a floor nothing is said about one
    let plain = userApi.call(ali, "POST", "/api/submit-many", many([NoFloor, HasFloor], "", data = "third"))
    for x in plain.json["results"].elems: check x.get("floor") == nil
    # the manager's: set at once where there is none, kept where there is one
    const M1 = "11LAB80AA711"
    let m = mgrApi.call(mgr, "POST", "/api/submit-many", many([M1, HasFloor], "3", cid = "many-floor-mgr"))
    check m.status == 200
    check m.json["results"][0]["status"].s == "approved" and m.json["results"][0]["floor"]["status"].s == "approved"
    check m.json["results"][1]["floor"]["status"].s == "unchanged" and m.json["results"][1]["floor"]["floor"].s == "5"
    check mgrNode.run.equipment[M1]["floor"].s == "3" and mgrNode.run.equipment[HasFloor]["floor"].s == "5"

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
    # decision 0050: each save makes a new relay room key, held here, its public key the setting
    let k1 = mgrNode.relayMemberSetting
    check k1.len == 87 and mgrNode.memberKey[0] and keyString(mgrNode.memberKey[1].pub) == k1
    check mgrApi.call(mgr, "POST", "/api/settings/relay", j("""{"url":"wss://relay.example.dev/"}""")).status == 200
    let k2 = mgrNode.relayMemberSetting
    check k2 != k1 and mgrNode.memberKey[0]
    # the manager removing a device rotates it too
    var victim = ""
    for d, _ in mgrNode.run.devices:
      if d != mgr.device and d notin mgrNode.run.cuts: victim = d
    check victim.len > 0
    check mgrApi.call(mgr, "POST", "/api/devices/revoke", newObj(@[("device", newStr(victim))])).status == 200
    check mgrNode.relayMemberSetting != k2 and mgrNode.memberKey[0]
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

  test "a later photo's floor never competes with the person's own open floor proposal":
    # (a photo queued offline with floor 3, then the Floor field set to 4 by hand, then the photo sent: one proposal)
    let (_, ali) = userApi.owner
    const C = "11LAB70AA509"
    let first = userApi.call(ali, "POST", "/api/submit", photoReq(C, "", "first", floor = "2"))
    check first.json["floor"]["status"].s == "pending"
    let later = userApi.call(ali, "POST", "/api/submit", photoReq(C, "", "later", floor = "4"))
    check later.json["floor"]["status"].s == "unchanged" and later.json["floor"]["floor"].s == "2"
    var floors = 0
    for _, e in userNode.entries:
      if e["type"].s == "equipment" and e["body"]["kks"].s == C: inc floors
    check floors == 1

  test "the leaderboard lists only people who contributed (it isn't a member list)":
    let n0 = mgrApi.call(mgr, "GET", "/api/leaderboard").json["people"].len
    check mgrApi.call(mgr, "POST", "/api/devices/import-request",
                      newObj(@[("request", P.joinRequest(P.p256Generate(), "quiet", "Quiet Member", newStr("Operator"), "phone", now() div 1000))])).status == 200
    var member = false   # a member now
    for _, v in mgrNode.run.persons:
      if v["full_name"].isStr and v["full_name"].s == "Quiet Member": member = true
    check member
    let b = mgrApi.call(mgr, "GET", "/api/leaderboard").json
    check b["people"].len == n0
    for x in b["people"].elems: check x["name"].s != "Quiet Member"

  test "a client_id is its sender's: another member sending under it doesn't make the owner's send a repeat (#136)":
    # two members on one node, as two people signed in to the server's web app are
    proc member(user, full: string): Actor =
      let sk = P.p256Generate()
      check mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request",
        P.joinRequest(sk, user, full, newStr("Technician"), "server", now() div 1000))])).status == 200
      let (ok, a) = mgrNode.actorOf(P.peerId(sk), sk)
      check ok and not a.isAdmin
      a
    let omar = member("omar", "Omar Owner")
    let bea = member("bea", "Bea Other")
    proc photosOf(who: Actor, kks: string): int =
      for eid, e in mgrNode.entries:
        if e["type"].s == "photo" and e["body"]["kks"].s == kks and mgrNode.run.authors.getOrDefault(eid) == who.person:
          inc result
    proc many(codes: openArray[string], cid, data: string, floor = ""): JNode =
      var p = newObj(@[("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0a" & data))), ("caption", newStr(""))])
      if floor.len > 0: p["floor"] = newStr(floor)
      var ks = newArr()
      for c in codes: ks.elems.add newStr(c)
      newObj(@[("kind", newStr("photo")), ("kks", ks), ("payload", p), ("client_id", newStr(cid))])
    const A = "11LAB90AA601"
    const B = "11LAB90AA602"
    const C = "11LAB90AA603"
    # a single photo: Omar's is open, so Bea can read its client_id
    let first = mgrApi.call(omar, "POST", "/api/submit", photoReq(A, "", "omar one", cid = "omar-photo-1"))
    check first.json["status"].s == "pending"
    var seen = ""
    for s in mgrApi.call(bea, "GET", "/api/submissions").json["submissions"].elems:
      if s["id"].i == first.json["id"].i and s["client_id"].isStr: seen = s["client_id"].s
    check seen == "omar-photo-1"
    # Bea's own send under it is hers: written, not answered with Omar's submission
    let hers = mgrApi.call(bea, "POST", "/api/submit", photoReq(A, "", "bea one", cid = "omar-photo-1"))
    check hers.json.get("duplicate") == nil and hers.json["id"].i != first.json["id"].i
    check photosOf(bea, A) == 1
    # and each one's resend is still a repeat of their own
    let againO = mgrApi.call(omar, "POST", "/api/submit", photoReq(A, "", "omar one", cid = "omar-photo-1"))
    check againO.json["duplicate"].b and againO.json["id"].i == first.json["id"].i
    let againB = mgrApi.call(bea, "POST", "/api/submit", photoReq(A, "", "bea one", cid = "omar-photo-1"))
    check againB.json["duplicate"].b and againB.json["id"].i == hers.json["id"].i
    check photosOf(omar, A) == 1 and photosOf(bea, A) == 1
    # a set of codes: Bea sends single photos under two of the set's ids before Omar's set arrives
    check mgrApi.call(bea, "POST", "/api/submit", photoReq(B, "", "bea two", cid = "omar-set-01-1")).json["status"].s == "pending"
    check mgrApi.call(bea, "POST", "/api/submit", photoReq(C, "", "bea three", floor = "3", cid = "omar-set-01-2")).json["floor"]["status"].s == "pending"
    let r = mgrApi.call(omar, "POST", "/api/submit-many", many([A, B, C], "omar-set-01", "omar set", floor = "2"))
    check r.status == 200
    var ids: seq[int64]
    for x in r.json["results"].elems:
      check x.get("duplicate") == nil and x["status"].s == "pending"
      check x["floor"]["status"].s == "pending" and x["floor"].get("duplicate") == nil
      ids.add x["id"].i
    check photosOf(omar, A) == 2 and photosOf(omar, B) == 1 and photosOf(omar, C) == 1
    # Omar's retry of the set repeats his own, each one
    let entries = mgrNode.entries.len
    let r2 = mgrApi.call(omar, "POST", "/api/submit-many", many([A, B, C], "omar-set-01", "omar set", floor = "2"))
    for i, x in r2.json["results"].elems: check x["duplicate"].b and x["id"].i == ids[i]
    check mgrNode.entries.len == entries
    # the server's submit-file (written as whoever is the manager now): what another admin sent under the id is
    # there, as after a change of manager; what a member sent under it is not
    proc filed(who: Actor, kks, cid: string): JNode =
      mgrApi.submit(who, "equipment", j("""{"kks":"""" & kks & """","changes":{"near":"from the file"}}"""), newStr(cid),
                    nil, now(), fromFile = true)
    let ak = P.p256Generate()
    let aid = mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request",
      P.joinRequest(ak, "adm", "Ada Admin", newStr("Shift engineer"), "server", now() div 1000))])).json["person"].s
    check mgrApi.call(mgr, "POST", "/api/persons/" & aid, j("""{"role":"admin"}""")).status == 200
    let (_, ada) = mgrNode.actorOf(P.peerId(ak), ak)
    check mgrApi.call(bea, "POST", "/api/submit", photoReq(B, "", "bea claims", cid = "imp-file-01")).json["status"].s == "pending"
    let f1 = filed(ada, B, "imp-file-01")
    check f1.get("duplicate") == nil and f1["status"].s == "approved"
    let f2 = filed(mgr, B, "imp-file-01")
    check f2["duplicate"].b and f2["id"].i == f1["id"].i
    # an ordinary request never looks past its own sender
    let own = mgrApi.call(mgr, "POST", "/api/submit", newObj(@[("kind", newStr("equipment")), ("client_id", newStr("imp-file-01")),
      ("payload", j("""{"kks":"11LAB90AA603","changes":{"near":"the manager's own"}}"""))]))
    check own.json.get("duplicate") == nil

  test "submit-file's re-run finds its own earlier rows, whoever sent them and whatever they are now (#151)":
    proc person(user, full: string, admin = false): (Actor, string) =
      let sk = P.p256Generate()
      let pid = mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request",
        P.joinRequest(sk, user, full, newStr("Technician"), "server", now() div 1000))])).json["person"].s
      if admin: check mgrApi.call(mgr, "POST", "/api/persons/" & pid, j("""{"role":"admin"}""")).status == 200
      let (ok, a) = mgrNode.actorOf(P.peerId(sk), sk)
      check ok and a.isAdmin == admin
      (a, pid)
    proc setRole(pid, role: string): bool =
      mgrApi.call(mgr, "POST", "/api/persons/" & pid, j("""{"role":"""" & role & """"}""")).status == 200
    proc fieldItem(kks, near: string): JNode = j("""{"kks":"""" & kks & """","changes":{"near":"""" & near & """"}}""")
    proc filed(who: Actor, kks, cid: string, near = "from the file"): JNode =
      mgrApi.submit(who, "equipment", fieldItem(kks, near), newStr(cid), nil, now(), fromFile = true)
    proc isDup(r: JNode): bool = r.get("duplicate") != nil and r["duplicate"].b    # (a nil node in `check` segfaults)
    proc nearOf(kks: string): string =
      let e = mgrNode.run.equipment.getOrDefault(kks)
      if e != nil and e.get("near") != nil and e["near"].isStr: e["near"].s else: ""
    # 1. the manager the file was first run as is a plain user now: the file run again still adds nothing
    let (old, oldId) = person("old151", "Old Manager", admin = true)
    let first = filed(old, "11LAB90AA611", "imp-151-demoted")
    check not isDup(first)
    check first["status"].s == "approved"
    check setRole(oldId, "user")
    let entries = mgrNode.entries.len
    let again = filed(mgr, "11LAB90AA611", "imp-151-demoted")
    check isDup(again)
    check again["id"].i == first["id"].i
    check mgrNode.entries.len == entries
    # 2. a member sends under a file's id (they can be computed), it stays pending, the member is made an admin:
    #    the manager's file item is written all the same
    let (mem, memId) = person("mem151", "Mem Ber")
    let claim = mgrApi.call(mem, "POST", "/api/submit", newObj(@[("kind", newStr("equipment")),
      ("client_id", newStr("imp-151-claimed")), ("payload", fieldItem("11LAB90AA612", "not the file's"))]))
    check claim.json["status"].s == "pending"
    check setRole(memId, "admin")
    let item = filed(mgr, "11LAB90AA612", "imp-151-claimed")
    check not isDup(item)
    check item["status"].s == "approved"
    check item["id"].i != claim.json["id"].i
    check nearOf("11LAB90AA612") == "from the file"
    # the rows a run writes keep their id where no request's can be; the answer for one says what the row is
    proc cidOf(id: int64): string =
      for r in mgrNode.store.subs():
        if r["id"].i == id and r["client_id"].isStr: return r["client_id"].s
    check cidOf(first["id"].i) == "file.imp-151-demoted"
    check cidOf(claim.json["id"].i) == "imp-151-claimed"
    check again["same"].b
    check again["kind"].s == "equipment" and again["target"].s == "equipment:11LAB90AA611" and again["status"].s == "approved"
    # an id used again for something else is answered by the earlier row, and says it is not this item
    let other = filed(mgr, "11LAB90AA613", "imp-151-demoted")
    check isDup(other)
    check not other["same"].b and not other["same_target"].b
    # as is another change to the same code
    let changed = filed(mgr, "11LAB90AA611", "imp-151-demoted", near = "another text")
    check isDup(changed)
    check changed["same_target"].b and not changed["same"].b
    check nearOf("11LAB90AA611") == "from the file"
    # the order of the keys in the file is not a difference; what a review says is
    proc filedAny(kind, payload, cid: string): JNode = mgrApi.submit(mgr, kind, j(payload), newStr(cid), nil, now(), fromFile = true)
    check filedAny("equipment", """{"kks":"11LAB90AA617","changes":{"near":"n","notes":"t"}}""", "imp-151-order")["status"].s == "approved"
    let swapped = filedAny("equipment", """{"kks":"11LAB90AA617","changes":{"notes":"t","near":"n"}}""", "imp-151-order")
    check isDup(swapped)
    check swapped["same"].b
    check filedAny("review", """{"tag_id":"t151","data":{"status":"confirmed","kks":"11LAB90AA618","suffix":"","isa":null}}""",
                   "imp-151-review")["status"].s == "approved"
    let rev = filedAny("review", """{"tag_id":"t151","data":{"status":"confirmed","kks":"11LAB90AA618","suffix":"","isa":null}}""",
                       "imp-151-review")
    check isDup(rev)
    check rev["same"].b
    let rev2 = filedAny("review", """{"tag_id":"t151","data":{"status":"rejected"}}""", "imp-151-review")
    check isDup(rev2)
    check rev2["same_target"].b and not rev2["same"].b
    # a marked tag without an id of its own gets a new one each time it is read: still the same item
    const Mark = """{"sheet":"lp","bbox":[310,310,360,330],"kks":"11LAB90AA619","isa":"","note":"from the file"}"""
    check filedAny("tag_add", Mark, "imp-151-mark")["status"].s == "approved"
    let mark2 = filedAny("tag_add", Mark, "imp-151-mark")
    check isDup(mark2)
    check mark2["same"].b
    let mark3 = filedAny("tag_add", Mark.replace("11LAB90AA619", "11LAB90AA620"), "imp-151-mark")
    check isDup(mark3)
    check not mark3["same"].b
    # a link switched off, a photo's caption changed: not the same change
    check filedAny("link", """{"proc":"EP-151","step":1,"kks":"11LAB90AA619","on":true}""", "imp-151-link")["status"].s == "approved"
    check filedAny("link", """{"proc":"EP-151","step":1,"kks":"11LAB90AA619","on":true}""", "imp-151-link")["same"].b
    let off = filedAny("link", """{"proc":"EP-151","step":1,"kks":"11LAB90AA619","on":false}""", "imp-151-link")
    check off["same_target"].b and not off["same"].b
    check other["target"].s == "equipment:11LAB90AA611"
    check nearOf("11LAB90AA613") == ""
    # no request can send such an id, alone or as a set's prefix (the same set under an id without "." is taken)
    for bad in ["file.imp-151-demoted", "floor.file.imp-151-x", "floor.imp-151-xx"]:
      check mgrApi.call(mgr, "POST", "/api/submit", newObj(@[("kind", newStr("equipment")), ("client_id", newStr(bad)),
        ("payload", fieldItem("11LAB90AA613", "a request"))])).status == 400
      check mgrApi.call(mgr, "POST", "/api/submit-many", newObj(@[("kind", newStr("equipment")), ("client_id", newStr(bad)),
        ("kks", j("""["11LAB90AA613"]""")), ("payload", j("""{"changes":{"near":"a request"}}"""))])).status == 400
    check nearOf("11LAB90AA613") == ""
    check mgrApi.call(mgr, "POST", "/api/submit-many", newObj(@[("kind", newStr("equipment")), ("client_id", newStr("req-151-set")),
      ("kks", j("""["11LAB90AA613"]""")), ("payload", j("""{"changes":{"near":"a request"}}"""))])).status == 200
    check nearOf("11LAB90AA613") == "a request"
    # and the manager's own request under the file's bare id is a request's: written, and no repeat of the file's
    let req = mgrApi.call(mgr, "POST", "/api/submit", newObj(@[("kind", newStr("equipment")),
      ("client_id", newStr("imp-151-demoted")), ("payload", fieldItem("11LAB90AA611", "by hand"))]))
    check not isDup(req.json)
    check cidOf(req.json["id"].i) == "imp-151-demoted"
    # a photo with a floor: both rows are the file's, and a run as someone else finds both
    proc filedPhoto(who: Actor, kks, cid: string): JNode =
      mgrApi.submit(who, "photo", photoReq(kks, "", "file photo " & cid, floor = "4")["payload"], newStr(cid), nil, now(),
                    fromFile = true)
    let (two, _) = person("two151", "Second Manager", admin = true)
    let ph = filedPhoto(two, "11LAB90AA614", "imp-151-photo")
    check not isDup(ph)
    check ph["status"].s == "approved" and ph["floor"]["status"].s == "approved"
    check cidOf(ph["id"].i) == "file.imp-151-photo"
    check cidOf(ph["floor"]["id"].i) == "floor.file.imp-151-photo"
    let rows = mgrNode.store.subs().len
    let ph2 = filedPhoto(mgr, "11LAB90AA614", "imp-151-photo")
    check isDup(ph2)
    check ph2["same"].b and ph2["id"].i == ph["id"].i
    check mgrNode.store.subs().len == rows
    # the floor's row alone (the run stopped between the two): the floor proposal is not written a second time
    let fl2 = mgrApi.submitBody(mgr, "equipment", j("""{"kks":"11LAB90AA614","changes":{"floor":"4"},"base":{"floor":""}}"""),
                                newStr("floor.file.imp-151-photo"), "", now(), fileBare = "floor.imp-151-photo")
    check isDup(fl2)
    check fl2["id"].i == ph["floor"]["id"].i and fl2["same"].b
    # a photo whose floor's id is taken by something else: the photo is written, and its floor's answer says so
    check filed(mgr, "11LAB90AA615", "imp-151-photo-2")["status"].s == "approved"
    discard mgrApi.submitBody(mgr, "equipment", j("""{"kks":"11LAB90AA615","changes":{"near":"x"},"base":{"near":"from the file"}}"""),
                              newStr("floor.file.imp-151-photo-3"), "", now(), fileBare = "floor.imp-151-photo-3")
    let ph3 = filedPhoto(mgr, "11LAB90AA616", "imp-151-photo-3")
    check not isDup(ph3)
    check isDup(ph3["floor"])
    check not ph3["floor"]["same"].b

  test "submit-file: rows from before its ids had a prefix (the legacy path, #151)":
    proc person(user, full: string, admin = false): (Actor, string) =
      let sk = P.p256Generate()
      let pid = mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request",
        P.joinRequest(sk, user, full, newStr("Technician"), "server", now() div 1000))])).json["person"].s
      if admin: check mgrApi.call(mgr, "POST", "/api/persons/" & pid, j("""{"role":"admin"}""")).status == 200
      let (ok, a) = mgrNode.actorOf(P.peerId(sk), sk)
      check ok and a.isAdmin == admin
      (a, pid)
    proc fieldItem(kks, near: string): JNode = j("""{"kks":"""" & kks & """","changes":{"near":"""" & near & """"}}""")
    proc sent(who: Actor, kks, cid: string, near = "from the file"): JNode =
      # as the program before the prefix wrote a file's item: a row with the bare id (and as any request still does)
      mgrApi.call(who, "POST", "/api/submit", newObj(@[("kind", newStr("equipment")), ("client_id", newStr(cid)),
        ("payload", fieldItem(kks, near))])).json
    proc filed(kks, cid: string): JNode =
      mgrApi.submit(mgr, "equipment", fieldItem(kks, "from the file"), newStr(cid), nil, now(), fromFile = true)
    proc isDup(r: JNode): bool = r.get("duplicate") != nil and r["duplicate"].b
    # a store from before the prefix: no mark yet
    mgrNode.store.setMeta("file_ids_after", "")
    let (adm, _) = person("leg151a", "Legacy Admin", admin = true)
    let (mem, memId) = person("leg151m", "Legacy Member")
    let oldRun = sent(adm, "11LAB90AA621", "imp-151-legacy-1")           # an earlier run, as the manager of then
    check oldRun["status"].s == "approved"
    let claim = sent(mem, "11LAB90AA622", "imp-151-legacy-2", "not the file's")     # a member under a file's id
    check claim["status"].s == "pending"
    let elsewhere = sent(adm, "11LAB90AA629", "imp-151-legacy-3")       # an admin's, about another code
    check elsewhere["status"].s == "approved"
    # the program with the prefix starts: everything so far is old
    let mark = mgrApi.fileIdsAfter
    check mark == elsewhere["id"].i
    check mgrNode.store.getMeta("file_ids_after") == $mark
    # the earlier run's item is there
    let entries = mgrNode.entries.len
    let again = filed("11LAB90AA621", "imp-151-legacy-1")
    check isDup(again)
    check again["id"].i == oldRun["id"].i and again["same"].b
    check mgrNode.entries.len == entries
    # the member's row never was a file's, also once the member is an admin: the item is written
    check mgrApi.call(mgr, "POST", "/api/persons/" & memId, j("""{"role":"admin"}""")).status == 200
    let item = filed("11LAB90AA622", "imp-151-legacy-2")
    check not isDup(item)
    check item["status"].s == "approved"
    # nor is an admin's row about something else
    let item3 = filed("11LAB90AA623", "imp-151-legacy-3")
    check not isDup(item3)
    check item3["status"].s == "approved"
    # nor anything written since, whoever sends it: the mark stays where it was
    let late = sent(adm, "11LAB90AA624", "imp-151-legacy-4")
    check late["status"].s == "approved"
    check mgrApi.fileIdsAfter == mark
    let item4 = filed("11LAB90AA624", "imp-151-legacy-4")
    check not isDup(item4)
    # and each of these is the file's from now on
    for (k, c, r) in [("11LAB90AA622", "imp-151-legacy-2", item), ("11LAB90AA623", "imp-151-legacy-3", item3),
                      ("11LAB90AA624", "imp-151-legacy-4", item4)]:
      let rr = filed(k, c)
      check isDup(rr)
      check rr["id"].i == r["id"].i

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

