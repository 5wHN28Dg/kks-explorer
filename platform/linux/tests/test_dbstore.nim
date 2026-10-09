import std/[unittest, os, osproc, strutils, strtabs, tables, base64]
import kks/[json, util, crypto, proto, node, plant, api]
import plat
import kksl/[dbstore, sqlite]

let P = testProvider()

proc keyJson(k: PrivateKey): JNode = newObj(@[("scalar", newStr(hex(k.scalar))), ("pub", newStr(b64u(k.pub)))])
proc keyOf(j: JNode): PrivateKey = PrivateKey(scalar: unhex(j["scalar"].s), pub: unb64u(j["pub"].s))
when defined(windows):
  proc c_exit(code: cint) {.importc: "_exit", header: "<stdlib.h>".}
else:
  proc c_exit(code: cint) {.importc: "_exit", header: "<unistd.h>".}

type DyingStore = ref object of Store
  ## a DbStore that kills its process (no cleanup, no commit) at the n-th putSub
  inner: DbStore
  dieAt: int
method loadEntries(s: DyingStore): seq[StoredEntry] = s.inner.loadEntries
method putEntry(s: DyingStore, id: string, e: JNode) = s.inner.putEntry(id, e)
method loadEvidence(s: DyingStore): seq[StoredEntry] = s.inner.loadEvidence
method putEvidence(s: DyingStore, id: string, e: JNode) = s.inner.putEvidence(id, e)
method blobHas(s: DyingStore, sha: string): bool = s.inner.blobHas(sha)
method blobGet(s: DyingStore, sha: string): string = s.inner.blobGet(sha)
method blobPut(s: DyingStore, sha, data: string) = s.inner.blobPut(sha, data)
method getMeta(s: DyingStore, key: string): string = s.inner.getMeta(key)
method setMeta(s: DyingStore, key, value: string) = s.inner.setMeta(key, value)
method subs(s: DyingStore): seq[JNode] = s.inner.subs
method notes(s: DyingStore): seq[(string, string)] = s.inner.notes
method putNote(s: DyingStore, eid, note: string) = s.inner.putNote(eid, note)
method begin(s: DyingStore) = s.inner.begin
method commit(s: DyingStore) = s.inner.commit
method rollback(s: DyingStore) = s.inner.rollback
method putSub(s: DyingStore, row: JNode): int64 =
  dec s.dieAt
  if s.dieAt == 0: c_exit(9)
  s.inner.putSub(row)

proc photo(kks, cid: string): JNode =
  newObj(@[("kind", newStr("photo")), ("client_id", newStr(cid)), ("note", newStr("by the pump")),
           ("payload", newObj(@[("kks", newStr(kks)), ("dataUrl", newStr("data:image/jxl;base64," & encode("\xff\x0a" & cid)))]))])

proc countType(n: Node, typ: string): int =
  for _, e in n.entries:
    if e["type"].s == typ: inc result

let dying = getEnv("KKS_TEST_DIE")   # the child: submit, and die at the given putSub
if dying.len > 0:
  let parts = dying.split('|')       # db path | storage key hex | device key | body | putSub to die at
  let inner = openDbStore(P, parts[0], unhex(parts[1]))
  let n = newNode(P, DyingStore(inner: inner, dieAt: parseInt(parts[4])), keyOf(parseStrict(parts[2])))
  let a = newApi(n)
  let r = a.handle(a.owner[1], "POST", if parts[3].contains("\"kks\":[") : "/api/submit-many" else: "/api/submit",
                   initTable[string, string](), parseStrict(parts[3]), 1_790_000_100_000)
  echo "not killed: ", r.status
  quit 3

suite "SQLite store, sealed at rest":
  let dir = getTempDir() / "kks-dbstore-test"
  removeDir(dir)
  let key = P.randomBytes(32)
  let devKey = P.p256Generate()
  let rootKey = P.p256Generate()

  test "a node survives a restart on the same store":
    var st = openDbStore(P, dir / "node.db", key)
    var n = newNode(P, st, devKey)
    let me = P.newPersonId()
    discard n.append("genesis", P.genesisBody(rootKey, "Test plant", n.device, me, "boss", "The Manager"), 1_790_000_000_000)
    n.adopt(keyString(rootKey.pub))
    let sha = n.keepBlob("photo bytes")
    st.setMeta("hello", "wörld")
    st.close()
    var st2 = openDbStore(P, dir / "node.db", key)
    var n2 = newNode(P, st2, devKey)
    check n2.root == n.root and n2.entries.len == 1 and n2.run.manager == me
    check st2.blobGet(sha) == "photo bytes"
    check st2.getMeta("hello") == "wörld"
    st2.close()

  test "nothing readable on disk, and a wrong key fails at open":
    let raw = readFile(dir / "node.db")
    check "Test plant" notin raw and "photo bytes" notin raw and "boss" notin raw
    expect CryptoError: discard openDbStore(P, dir / "node.db", P.randomBytes(32))

  test "a row moved to another key doesn't open":
    var st = openDbStore(P, dir / "node.db", key)
    st.setMeta("a", "secret a")
    st.db.exec("UPDATE meta SET v=(SELECT v FROM meta WHERE k='a') WHERE k='hello'")
    expect CryptoError: discard st.getMeta("hello")
    st.close()

  test "wipe leaves only the note":
    var st = openDbStore(P, dir / "node.db", key)
    st.wipe("removed by The Manager")
    check st.loadEntries().len == 0 and st.getMeta("removed") == "removed by The Manager"
    st.close()

  test "a process killed between a submission's writes leaves nothing; the resend writes it once":
    let path = dir / "die.db"
    removeFile(path)
    var st = openDbStore(P, path, key)
    var n = newNode(P, st, devKey)
    discard n.append("genesis", P.genesisBody(rootKey, "Test plant", n.device, P.newPersonId(), "boss", "The Manager"), 1_790_000_000_000)
    n.adopt(keyString(rootKey.pub))
    st.close()
    proc killedAt(body: JNode, at: int) =
      let env = path & "|" & hex(key) & "|" & toText(keyJson(devKey)) & "|" & toText(body) & "|" & $at
      let p = startProcess(getAppFilename(), env = (block:
        var e = newStringTable(modeCaseSensitive)
        for k, v in envPairs(): e[k] = v
        e["KKS_TEST_DIE"] = env
        e), options = {poParentStreams})
      check p.waitForExit() == 9
      p.close()
    # the photo, its comment, then the row with the client_id: killed at the row
    killedAt(photo("11LAB70AA501", "die-photo-1"), 1)
    st = openDbStore(P, path, key)
    n = newNode(P, st, devKey)
    check n.entries.len == 1 and st.subs.len == 0 and st.notes.len == 0
    var a = newApi(n)
    check a.handle(a.owner[1], "POST", "/api/submit", initTable[string, string](), photo("11LAB70AA501", "die-photo-1"), 1_790_000_200_000).status == 200
    check a.handle(a.owner[1], "POST", "/api/submit", initTable[string, string](), photo("11LAB70AA501", "die-photo-1"), 1_790_000_300_000).json["duplicate"].b
    check n.countType("photo") == 1 and n.countType("comment") == 1
    st.close()
    # several codes: killed at the second code's row; the first one is whole, the second absent
    let many = parseStrict("""{"kind":"equipment","kks":["11LAB70AA601","11LAB70AA602"],"client_id":"die-many-1","note":"walkdown",
                               "payload":{"changes":{"notes":"insulation missing"}}}""")
    killedAt(many, 2)
    st = openDbStore(P, path, key)
    n = newNode(P, st, devKey)
    check n.countType("equipment") == 1 and n.countType("comment") == 2 and st.subs.len == 2
    a = newApi(n)
    let r = a.handle(a.owner[1], "POST", "/api/submit-many", initTable[string, string](), many, 1_790_000_400_000)
    check r.status == 200 and r.json["results"][0]["duplicate"].b and r.json["results"][1].get("duplicate") == nil
    check n.countType("equipment") == 2 and n.countType("comment") == 3
    st.close()

  test "a store transaction: all or nothing, not nested, readers on another connection see only what is committed":
    var st = openDbStore(P, dir / "tx.db", key)
    var other = openDbStore(P, dir / "tx.db", key)
    expect IOError:
      st.transaction(proc () =
        st.setMeta("a", "1")
        check st.getMeta("a") == "1" and other.getMeta("a") == ""
        raise newException(IOError, "fails half-way"))
    check st.getMeta("a") == "" and not st.db.inTransaction
    expect ValueError:
      st.transaction(proc () = st.transaction(proc () = discard))
    check not st.db.inTransaction
    st.transaction(proc () = st.setMeta("a", "2"))
    check other.getMeta("a") == "2"
    other.close()
    st.close()
