import std/[unittest, os, strutils, tables]
import kks/[json, util, crypto, proto, node, plant]
import plat
import kksl/[dbstore, sqlite]

let P = testProvider()

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
