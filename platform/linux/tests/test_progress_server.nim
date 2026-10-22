## The server only stores and relays course progress (PROTOCOL-v2 §17, decision 0062): two devices of the manager
## pair and save progress through the real server's store; then every sealed row of its database is opened with its
## storage key, and nothing in it is a person secret, a box key's private half, or progress in the clear. The server's
## own device is certified for that same person, the worst case: it still holds nothing and offers no pairing.
import std/[unittest, os, tables, strutils]
import kks/[json, util, crypto, proto, node, plant, progress, api]
import plat
import kksl/[server, sqlite, dbstore]

let P = testProvider()
var clock = 1_800_000_000_000'i64
proc tick(): int64 =
  clock += 1000
  clock

proc share(src, dst: Node) = discard dst.ingest(src.entriesFor(dst.vv), tick())

proc openRow(key: seq[byte], where, sealed: string): string =
  P.aesGcmOpen(key, sealed[0 ..< 12].toBytes, sealed[12 .. ^1].toBytes, toBytes("kks-store-v2\n" & where)).toStr

suite "the server holds only ciphertext of course progress":
  let dir = getTempDir() / "kks-progress-server-test"
  removeDir(dir)
  createDir(dir)
  var cfg = defaultConfig()
  cfg.storePath = dir / "server.db"
  let storageKey = P.randomBytes(32)
  let s = openServer(cfg, P, storageKey)
  let u = s.createPlant("boss", "The Manager", newNull(), "a long password 1")
  let mgr = u["person"].s
  let custodial = keyOf(s.store.getRow("custodial", u["device"].s))
  let phone = newNode(P, newMemStore(), P.p256Generate())
  let tablet = newNode(P, newMemStore(), P.p256Generate())
  for (n, label) in [(phone, "phone"), (tablet, "tablet")]:
    discard s.n.appendAs(custodial, "device_cert", deviceCertBody(n.device, mgr, label), tick())
    n.adopt(s.n.root)
  proc round() =
    for _ in 0 ..< 3:
      for n in [phone, tablet]:
        share(s.n, n)
        discard n.progressTick(tick())
        share(n, s.n)

  test "two devices pair through the server and read each other's progress":
    round()
    check phone.pairingList["devices"].len == 1     # the tablet; not the server's device, nor the custodial one
    phone.startPairing(tablet.device, tick())
    round()
    tablet.startPairing(phone.device, tick())
    round()
    let code = phone.pairingList["devices"][0]["code"].s
    check code.len == 6 and tablet.pairingList["devices"][0]["code"].s == code
    phone.confirmPairing(tablet.device, code, tick())
    tablet.confirmPairing(phone.device, code, tick())
    round()
    var d: OrderedTable[string, string]
    d["solved"] = """{"q1_r":true,"q2_f":true}"""
    d["finalBest"] = "8"
    discard phone.saveProgress("hrsg", d, tick())
    round()
    check tablet.loadProgress(mgr)["hrsg"]["finalBest"] == "8"

  test "every row of the server's store, opened with its key, holds no secret and no progress":
    check s.n.secretsOf(mgr).len == 0 and s.n.loadProgress(mgr).len == 0
    check s.n.device notin s.n.run.boxKeys and not s.n.pairingList["ready"].b
    check s.n.run.shares.len == 2 and s.n.run.private[mgr].len >= 1 and s.n.run.pairSteps.len == 2   # it relays them
    var plain = ""
    var n = 0
    for (tbl, keyCol, valCol) in [("entries", "id", "data"), ("evidence", "id", "data"), ("blobs", "sha", "data"),
                                  ("meta", "k", "v")]:
      for r in s.store.db.rows("SELECT " & keyCol & ", " & valCol & " FROM " & tbl):
        plain.add openRow(storageKey, tbl & "/" & r.colText(0), r.colText(1))
        inc n
    for r in s.store.db.rows("SELECT tbl, k, v FROM rows"):
      plain.add openRow(storageKey, "rows/" & r.colText(0) & "/" & r.colText(1), r.colText(2))
      inc n
    check n > 10
    check "q1_r" notin plain and "finalBest" notin plain and "solved" notin plain
    for r in s.store.db.rows("SELECT k FROM meta"):
      check r.colText(0) notin ["box_key", "paired", "shares_sent", "shares_taken", "pair_attempts", "rotated_for"] and
            not r.colText(0).startsWith("person_secrets")
    for dev in [phone, tablet]:
      for k in dev.secretsOf(mgr):
        check b64u(k) notin plain and hex(k) notin plain
      check hex(dev.boxKey.scalar) notin plain
    let raw = readFile(cfg.storePath)
    check "q1_r" notin raw and "solved" notin raw

  test "the server's API refuses progress and pairing":
    let me = s.actorFor(u)
    for (meth, path) in [("GET", "/api/progress"), ("GET", "/api/pairing"), ("POST", "/api/pairing"),
                         ("POST", "/api/progress")]:
      var status = 0
      try: discard s.api.route(me, meth, path, initTable[string, string](), newObj(@[("course", newStr("hrsg")),
                               ("data", newObj(@[("last", newStr("\"p1\""))])), ("device", newStr(phone.device))]), tick())
      except ApiError as e: status = e.status
      check status == 404
    check s.n.secretsOf(mgr).len == 0
