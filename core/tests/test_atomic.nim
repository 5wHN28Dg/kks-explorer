## A submission's entry, its comment and its row (the one with the client_id) are one store transaction
## (Node.atomic): a store that fails between them leaves nothing behind, memory never holds what the disk doesn't, and
## a resend (same client_id) writes everything once, in the same process or after a restart.

import std/[unittest, tables, base64, sets]
import kks/[json, util, crypto, proto, node, sync, plant, api, extras]
import testprovider

let P = testProvider()
var clock = 1_790_000_000_000'i64
proc now(): int64 =
  clock += 1000
  clock

type FailStore = ref object of MemStore
  ## fails the n-th next write of a kind (0 = never): a disk error, or the moment a process is killed
  subFail, entryFail, noteFail: int

proc tick(n: var int) =
  if n > 0:
    dec n
    if n == 0: raise newException(IOError, "the disk went away")

method putSub*(s: FailStore, row: JNode): int64 =
  tick(s.subFail)
  procCall putSub(MemStore(s), row)
method putEntry*(s: FailStore, id: string, e: JNode) =
  tick(s.entryFail)
  procCall putEntry(MemStore(s), id, e)
method putNote*(s: FailStore, eid, note: string) =
  tick(s.noteFail)
  procCall putNote(MemStore(s), eid, note)

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

proc j(s: string): JNode = parseStrict(s)

proc call(api: Api, me: Actor, meth, path: string, body: JNode = nil): Response =
  api.handle(me, meth, path, initTable[string, string](), body, now())

proc count(n: Node, typ: string): int =
  for _, e in n.entries:
    if e["type"].s == typ: inc result

proc consistent(n: Node, s: MemStore): bool =
  ## memory holds exactly what the store holds, and a node started from the store sees the same chains
  var disk, mem: HashSet[string]
  for (id, _) in s.loadEntries: disk.incl id
  for id, _ in n.entries: mem.incl id
  disk == mem and toText(newNode(P, s, n.key).vv) == toText(n.vv)

proc photo(kks, cid: string, note = ""): JNode =
  result = newObj(@[("kind", newStr("photo")),
                    ("payload", newObj(@[("kks", newStr(kks)), ("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0a" & cid))),
                                         ("caption", newStr("north side"))]))])
  if cid.len > 0: result["client_id"] = newStr(cid)
  if note.len > 0: result["note"] = newStr(note)

suite "a submission is written all at once":
  let rootKey = P.p256Generate()
  let mgrStore = FailStore()
  var mgrNode = newNode(P, mgrStore, P.p256Generate())
  let mgrId = P.newPersonId()
  discard mgrNode.append("genesis", P.genesisBody(rootKey, "Test plant", mgrNode.device, mgrId, "boss", "The Manager"), now())
  mgrNode.adopt(keyString(rootKey.pub))
  var mgrApi = newApi(mgrNode)
  var mgr = mgrApi.owner[1]
  let userKey = P.p256Generate()
  let userStore = FailStore()
  var userNode = newNode(P, userStore, userKey)
  var userApi = newApi(userNode)
  block:
    let req = P.joinRequest(userNode.key, "ali", "Ali User", newStr("Technician"), "phone", now() div 1000)
    doAssert mgrApi.call(mgr, "POST", "/api/devices/import-request", newObj(@[("request", req)])).status == 200
    sync(userNode, mgrNode, adopt = mgrNode.root)
  var ali = userApi.owner[1]

  proc restartUser() =
    ## the process died: a new node and API from what the store kept
    userNode = newNode(P, userStore, userKey)
    userApi = newApi(userNode)
    ali = userApi.owner[1]

  test "the row with the client_id fails: nothing is kept; the resend writes the photo and its note once":
    let before = userNode.entries.len
    let rev = userApi.rev
    userStore.subFail = 1
    expect IOError: discard userApi.call(ali, "POST", "/api/submit", photo("11LAB70AA501", "photo-cid-1", "by the pump"))
    check userNode.entries.len == before and userStore.entries.len == before   # neither memory nor the disk
    check userApi.rev == rev                                                  # pages are not told of a change
    check consistent(userNode, userStore)
    let r = userApi.call(ali, "POST", "/api/submit", photo("11LAB70AA501", "photo-cid-1", "by the pump"))
    check r.status == 200 and r.json["status"].s == "pending" and r.json.get("duplicate") == nil
    let again = userApi.call(ali, "POST", "/api/submit", photo("11LAB70AA501", "photo-cid-1", "by the pump"))
    check again.json["duplicate"].b
    check userNode.count("photo") == 1 and userNode.count("comment") == 1
    check consistent(userNode, userStore)

  test "the comment fails after the entry: neither is kept, and the chain continues from the same head":
    let head = userNode.vv[userNode.device]
    userStore.entryFail = 2
    expect IOError: discard userApi.call(ali, "POST", "/api/submit", photo("11LAB70AA502", "photo-cid-2", "rusty"))
    check toText(userNode.vv[userNode.device]) == toText(head)
    check consistent(userNode, userStore)
    check userApi.call(ali, "POST", "/api/submit", photo("11LAB70AA502", "photo-cid-2", "rusty")).status == 200
    let e = userNode.entries[userNode.vv[userNode.device][1].s]   # the comment, right after the photo
    check e["type"].s == "comment" and e["seq"].i == head[0].i + 2
    check userNode.count("photo") == 2 and userNode.count("comment") == 2
    check consistent(userNode, userStore)

  test "the process dies before the row: after a restart the resend writes the photo once":
    userStore.subFail = 1
    expect IOError: discard userApi.call(ali, "POST", "/api/submit", photo("11LAB70AA503", "photo-cid-3"))
    restartUser()
    check userApi.call(ali, "POST", "/api/submit", photo("11LAB70AA503", "photo-cid-3")).status == 200
    check userApi.call(ali, "POST", "/api/submit", photo("11LAB70AA503", "photo-cid-3")).json["duplicate"].b
    check userNode.count("photo") == 3
    check consistent(userNode, userStore)

  test "several codes: the second code's row fails; the resend keeps the first and writes the rest once":
    let body = newObj(@[("kind", newStr("equipment")), ("client_id", newStr("many-cid-1")),
                        ("kks", newArr(@[newStr("11LAB70AA601"), newStr("11LAB70AA602"), newStr("11LAB70AA603")])),
                        ("payload", j("""{"changes":{"notes":"insulation missing"}}""")), ("note", newStr("walkdown"))])
    userStore.subFail = 2
    expect IOError: discard userApi.call(ali, "POST", "/api/submit-many", body)
    check userNode.count("equipment") == 1 and userNode.count("comment") == 3   # the first code, whole
    check consistent(userNode, userStore)
    restartUser()
    let r = userApi.call(ali, "POST", "/api/submit-many", body)
    check r.status == 200
    let res = r.json["results"]
    check res[0]["duplicate"].b and res[1].get("duplicate") == nil and res[2].get("duplicate") == nil
    check userNode.count("equipment") == 3 and userNode.count("comment") == 5
    check consistent(userNode, userStore)

  test "approving a held change: its row fails; approving again writes the change once":
    sync(userNode, mgrNode)
    let r = mgrApi.call(mgr, "POST", "/api/submit", j("""{"kind":"equipment","payload":{"kks":"11LAB70AA701","changes":{"notes":"new"},"base":{"notes":"stale"}}}"""))
    check r.json["status"].s == "conflict"
    let sid = $r.json["id"].i
    let before = mgrNode.count("equipment")
    mgrStore.subFail = 1
    expect IOError: discard mgrApi.call(mgr, "POST", "/api/submissions/" & sid & "/approve", j("""{"force":true}"""))
    check mgrNode.count("equipment") == before
    check consistent(mgrNode, mgrStore)
    check mgrApi.call(mgr, "POST", "/api/submissions/" & sid & "/approve", j("""{"force":true}""")).status == 200
    check mgrApi.call(mgr, "POST", "/api/submissions/" & sid & "/approve", j("""{"force":true}""")).status == 409
    check mgrNode.count("equipment") == before + 1
    check consistent(mgrNode, mgrStore)

  test "a revert's note fails: none of its entries is kept":
    let h = mgrApi.call(mgr, "GET", "/api/revisions").json["revisions"]
    var hid = ""
    for row in h.elems:
      if row["entity"].s == "equipment" and row["key"].s == "11LAB70AA701": hid = row["hid"].s
    check hid.len > 0
    let before = mgrNode.entries.len
    mgrStore.noteFail = 1
    expect IOError: discard mgrApi.call(mgr, "POST", "/api/revisions/" & hid & "/revert")
    check mgrNode.entries.len == before
    check consistent(mgrNode, mgrStore)
    check mgrApi.call(mgr, "POST", "/api/revisions/" & hid & "/revert").json["changed"].i == 1
    check consistent(mgrNode, mgrStore)

  test "transactions don't nest; a failed one leaves the store usable":
    expect ValueError:
      mgrNode.atomic(proc () = mgrNode.atomic(proc () = discard))
    let before = mgrNode.entries.len
    mgrNode.atomic(proc () = discard mgrNode.append("comment", newObj(@[("entry", newStr(mgrNode.vv[mgrNode.device][1].s)),
                                                                    ("text", newStr("ok"))]), now()))
    check mgrNode.entries.len == before + 1
    check consistent(mgrNode, mgrStore)
