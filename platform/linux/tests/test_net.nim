import std/[unittest, asyncdispatch, tables, os]
import kks/[json, util, crypto, proto, node, sync, plant, progress]
import plat
import kksl/[net, dbstore]

let P = testProvider()

suite "sync over real TCP":
  let rootKey = P.p256Generate()
  let kServer = P.p256Generate()
  let dir = getTempDir() / "kks-net-test"
  removeDir(dir)
  var server = newNode(P, openDbStore(P, dir / "server.db", P.randomBytes(32)), kServer)
  let me = P.newPersonId()
  discard server.append("genesis", P.genesisBody(rootKey, "Test plant", server.device, me, "boss", "The Manager"), nowMs())
  server.adopt(keyString(rootKey.pub))
  let lst = listen(server, newIdentity(kServer), 0, "127.0.0.1",
                   Hooks(secrets: proc (r: string, m: JNode): JNode = server.secretsAnswer(r, m)))

  test "a certified laptop joins, syncs, and a change travels back":
    let kLaptop = P.p256Generate()
    discard server.append("device_cert", deviceCertBody(P.peerId(kLaptop), me, "laptop"), nowMs())
    var laptop = newNode(P, newMemStore(), kLaptop)
    let st = waitFor laptop.syncWith(newIdentity(kLaptop), "127.0.0.1", lst.port, server.device, adoptRoot = server.root)
    check st.received == 2 and laptop.run.manager == me
    discard laptop.append("setting", newObj(@[("key", newStr("relay")), ("value", newNull())]), nowMs())
    let st2 = waitFor laptop.syncWith(newIdentity(kLaptop), "127.0.0.1", lst.port, server.device)
    check st2.sent == 1
    check server.entries.len == 3
    let ans = waitFor laptop.ask(newIdentity(kLaptop), "127.0.0.1", lst.port, server.device, laptop.secretsRequest())
    check ans["t"].s == "secrets"

  test "the wrong device answering is refused":
    let k = P.p256Generate()
    var other = newNode(P, newMemStore(), k)
    expect TlsError:
      discard waitFor other.syncWith(newIdentity(k), "127.0.0.1", lst.port, P.peerId(P.p256Generate()), adoptRoot = server.root)

  test "a stranger completes TLS but receives nothing":
    let k = P.p256Generate()
    var other = newNode(P, newMemStore(), k)
    other.adopt(server.root)
    let st = waitFor other.syncWith(newIdentity(k), "127.0.0.1", lst.port, server.device)
    check st.theyDenied and other.entries.len == 0

  test "the default listener takes IPv6 and IPv4 (one dual-stack socket)":
    let both = listen(server, newIdentity(kServer), 0)
    let k = P.p256Generate()
    discard server.append("device_cert", deviceCertBody(P.peerId(k), me, "laptop 2"), nowMs())
    var laptop = newNode(P, newMemStore(), k)
    check (waitFor laptop.syncWith(newIdentity(k), "::1", both.port, server.device, adoptRoot = server.root)).received > 0
    discard waitFor laptop.syncWith(newIdentity(k), "127.0.0.1", both.port, server.device)
    check laptop.entries.len == server.entries.len
