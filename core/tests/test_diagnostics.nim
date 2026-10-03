## Diagnostics reports end to end in the core (PROTOCOL-v2 §13a): the manager switches them on, a user's phone
## records events and reports, the manager's devices open the report, nobody else can.
import std/[unittest, tables]
import kks/[json, util, crypto, proto, node, plant, progress, diagnostics]
import testprovider

let P = testProvider()
var clock = 1_800_000_000_000'i64
proc tick(): int64 =
  clock += 1000
  clock

proc share(src, dst: Node) = discard dst.ingest(src.entriesFor(dst.vv), tick())

suite "diagnostics reports":
  let rootKey = P.p256Generate()
  let laptop = newNode(P, newMemStore(), P.p256Generate())     # the manager's laptop
  let mgr = P.newPersonId()
  discard laptop.append("genesis", P.genesisBody(rootKey, "Test plant", laptop.device, mgr, "boss", "The Manager"), tick())
  laptop.adopt(keyString(rootKey.pub))
  let server = newNode(P, newMemStore(), P.p256Generate())    # certified to the manager, but holds no person secret
  let phone = newNode(P, newMemStore(), P.p256Generate())     # a user's phone
  let bob = P.newPersonId()
  discard laptop.append("device_cert", deviceCertBody(server.device, mgr, "server"), tick())
  discard laptop.append("person", personBody(bob, "bob", "Bob User", "user"), tick())
  discard laptop.append("device_cert", deviceCertBody(phone.device, bob, "phone"), tick())
  for n in [server, phone]: n.adopt(laptop.root)

  test "nothing is reported while reports are off; events wait":
    share(laptop, phone)
    phone.record("sync", "sync with 192.0.2.1:8421: refused", tick())
    phone.record("sync", "sync with 192.0.2.1:8421: refused", tick())
    phone.record("crash", "IndexError at foo", tick())
    check phone.pending.len == 2 and phone.pending[0]["n"].i == 2
    check not phone.maybeReport("android", "0.9.0", "Android 10", "SM-N960F", tick())

  test "only the manager switches them on":
    expect ValueError: phone.enable(tick())
    laptop.enable(tick())
    check laptop.diagnosticsKey.len == 87 and laptop.canRead

  test "the phone reports once, then waits 6 hours":
    share(laptop, phone)
    check phone.diagnosticsKey == laptop.diagnosticsKey
    check phone.maybeReport("android", "0.9.0", "Android 10", "SM-N960F", tick())
    check phone.pending.len == 0
    phone.record("error", "photo encode failed", tick())
    check not phone.maybeReport("android", "0.9.0", "Android 10", "SM-N960F", tick())
    check phone.maybeReport("android", "0.9.0", "Android 10", "SM-N960F", tick() + Interval)

  test "the manager's laptop opens both; the server and the phone open none":
    share(phone, laptop)
    let r = laptop.readReports
    check r.len == 2
    check r[0]["report"]["events"][0]["text"].s == "photo encode failed"
    check r[1]["report"]["events"].len == 2 and r[1]["report"]["model"].s == "SM-N960F"
    check r[1]["label"].s == "phone" and r[1]["username"].s == "bob"
    share(laptop, server)
    check not server.canRead and server.readReports[0]["report"].kind == jNull
    check phone.readReports.len == 2 and phone.readReports[0]["report"].kind == jNull

  test "a second manager device opens them after the person secrets swap (§17)":
    let tablet = newNode(P, newMemStore(), P.p256Generate())
    discard laptop.append("device_cert", deviceCertBody(tablet.device, mgr, "tablet"), tick())
    tablet.adopt(laptop.root)
    share(laptop, tablet)
    check not tablet.canRead
    discard tablet.addSecrets(mgr, laptop.secretsOf(mgr))
    check tablet.canRead and tablet.readReports[0]["report"].kind == jObj

  test "switched off: nothing more is written":
    laptop.disable(tick())
    share(laptop, phone)
    phone.record("error", "later", tick())
    check phone.diagnosticsKey == ""
    check not phone.maybeReport("android", "0.9.0", "Android 10", "SM-N960F", tick() + 2 * Interval)
