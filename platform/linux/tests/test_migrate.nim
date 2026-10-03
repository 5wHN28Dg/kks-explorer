## Moving a v1 device without an admin (PROTOCOL-v2 §21a, decision 0042), end to end on this machine: a v1 plant made
## by the v1 Python code (tools/m6/v1_test_plant.py), the migration tool, the server's import + succession, then a new
## device that asks for the statement, sends the v1 phone's proof, syncs, and writes the phone's open changes.
## Needs .venv's python (cryptography) or python3 with it.
import std/[unittest, asyncdispatch, os, osproc, strutils, tables, nativesockets, net, base64, sets]
import kks/[json, util, crypto, proto, node, sync, provider_gnutls]
import plat
import kksl/[net as knet, server, dbstore, internet]

let P = testProvider()
let repo = currentSourcePath().parentDir / ".." / ".." / ".."
let py = if fileExists(repo / ".venv/bin/python"): repo / ".venv/bin/python" else: "python3"

proc run(args: varargs[string]): string =
  let (o, code) = execCmdEx(quoteShellCommand(@[py] & @args), workingDir = repo)
  doAssert code == 0, o
  o

proc freePort(): int =
  let s = newSocket()
  s.bindAddr(Port(0), "127.0.0.1")
  result = int(s.getLocalAddr()[1])
  s.close()

proc waitFor2[T](f: Future[T]): T =
  ## waitFor that keeps the server's loop running
  while not f.finished: poll(20)
  f.read

suite "moving v1 devices (§21a)":
  let tmp = getTempDir() / "kks-migrate-" & $getCurrentProcessId()
  removeDir(tmp)
  createDir(tmp)
  discard run(repo / "tools/m6/v1_test_plant.py", "make", tmp)
  discard run(repo / "tools/m6/migrate_v1.py", "export", "--db", tmp / "v1/plant.db", "--photos", tmp / "v1/photos",
              "--out", tmp / "pkg.json")
  let phone = parseStrict(readFile(tmp / "phone.json"))
  var cfg = defaultConfig()
  cfg.address = "127.0.0.1"
  cfg.port = freePort()
  cfg.syncPort = freePort()
  cfg.storePath = tmp / "server.db"
  cfg.webDir = repo
  cfg.dataDir = repo / "data"
  cfg.plantDir = tmp / "plant-data"
  cfg.backupDir = tmp / "backups"
  let s = openServer(cfg, P, P.randomBytes(32))
  discard s.importV1(parseStrict(readFile(tmp / "pkg.json"), maxDepth = 512))
  let v1root = phone["v1_root"].s

  test "the succession statement: only one the v1 root signed for this server is kept":
    discard run(repo / "tools/m6/migrate_v1.py", "succession", "--db", tmp / "v1/plant.db", "--root-key", tmp / "v1/root.key",
                "--v2-root", s.n.root, "--server", s.n.device, "--out", tmp / "succ.json")
    var bad = parseStrict(readFile(tmp / "succ.json"))
    bad["stmt"]["server"] = newStr("x" & s.n.device[1 .. ^1])
    expect ValueError: discard s.importSuccession(bad)
    check s.importSuccession(parseStrict(readFile(tmp / "succ.json"))).startsWith("succession statement kept")
    check s.v1Room.len == 32

  asyncCheck s.serve()
  for _ in 0 ..< 10: poll(20)

  let kNew = P.p256Generate()
  var b = newNode(P, newMemStore(), kNew)
  let idB = newIdentity(kNew)

  proc proof(dev, key: string): JNode =
    parseStrict(run(repo / "tools/m6/v1_test_plant.py", "proof", "--seed", phone["seed"].s, "--v1-root", v1root,
                    "--v2-root", s.n.root, "--device", dev, "--key", key, "--label", "Tom’s phone — ü\\n").strip)

  test "a new device gets the statement and can check it with the v1 root":
    let a = waitFor2 ask(b, idB, "127.0.0.1", cfg.syncPort, "", newObj(@[("t", newStr("succession"))]))
    check a["stmt"]["server"].s == s.n.device
    check a["stmt"]["v2_root"].s == s.n.root
    check ed25519Verify(unb64u(v1root), unb64u(a["sig"].s), toBytes("kks-succession-v1\n" & canonical(a["stmt"])))
    var archived = initTable[string, int64]()
    for x in a["stmt"]["archived"].elems: archived[x[0].s] = x[1].i
    check archived[phone["v1_device"].s] == 1

  test "a tampered proof is refused":
    var pr = proof(b.device, keyString(kNew.pub))
    pr["label"] = newStr("Someone else")
    let a = waitFor2 ask(b, idB, "127.0.0.1", cfg.syncPort, s.n.device, newObj(@[("t", newStr("migrate")), ("proof", pr)]))
    check a["state"].s == "bad"

  test "a proof for another device than the connection's is refused":
    let other = P.p256Generate()
    let a = waitFor2 ask(b, idB, "127.0.0.1", cfg.syncPort, s.n.device,
                         newObj(@[("t", newStr("migrate")), ("proof", proof(P.peerId(other), keyString(other.pub)))]))
    check a["state"].s == "bad"

  test "the phone's proof moves it: same person, the plant syncs, its open photo reaches the server":
    let a = waitFor2 ask(b, idB, "127.0.0.1", cfg.syncPort, s.n.device,
                         newObj(@[("t", newStr("migrate")), ("proof", proof(b.device, keyString(kNew.pub)))]))
    check a["state"].s == "accepted"
    discard waitFor2 syncWith(b, idB, "127.0.0.1", cfg.syncPort, s.n.device, adoptRoot = a["root"].s)
    check b.root == s.n.root
    check b.run.devices[b.device]["person"].s == phone["person"].s
    check b.run.equipment["11LAB70AA501"]["notes"].s == "checked"
    # the bridge's hand-over, written as this device's own entries
    for (sha, data) in phone["blobs"].fields: b.store.blobPut(sha, base64.decode(data.s))
    let h = phone["handover"][0]
    let eid = P.entryId(b.append(h["type"].s, h["body"], nowMs()))
    discard b.append("comment", newObj(@[("entry", newStr(eid)), ("text", h["note"])]), nowMs())
    discard waitFor2 syncWith(b, idB, "127.0.0.1", cfg.syncPort, s.n.device)
    check s.n.run.proposals.getOrDefault(eid) == "pending"
    check s.n.store.blobGet(h["body"]["blob"].s).len > 0
    check s.n.run.persons[phone["person"].s]["full_name"].s == "Tom Teammate"

  test "the same proof again is fine; a second new device for the same v1 phone is refused":
    let again = waitFor2 ask(b, idB, "127.0.0.1", cfg.syncPort, s.n.device,
                             newObj(@[("t", newStr("migrate")), ("proof", proof(b.device, keyString(kNew.pub)))]))
    check again["state"].s == "accepted"
    let k2 = P.p256Generate()
    var c = newNode(P, newMemStore(), k2)
    let a = waitFor2 ask(c, newIdentity(k2), "127.0.0.1", cfg.syncPort, s.n.device,
                         newObj(@[("t", newStr("migrate")), ("proof", proof(c.device, keyString(k2.pub)))]))
    check a["state"].s == "refused"
    check "already moved" in a["why"].s

  test "a device that knows only the v1 root finds the server in the v1 relay room":
    let port = 19000 + (getCurrentProcessId() mod 1000)
    let relayProc = startProcess(py, repo, ["-m", "peer.relay_server", $port], options = {poStdErrToStdOut})
    defer: relayProc.terminate(); discard relayProc.waitForExit(); relayProc.close()
    sleep(800)
    let url = "ws://127.0.0.1:" & $port
    let mgr = s.n.run.manager
    var mdev = ""
    for (_, u) in s.store.allRows("users"):
      if u["person"].s == mgr: mdev = u["device"].s
    discard s.n.appendAs(keyOf(s.store.getRow("custodial", mdev)), "setting",
                         newObj(@[("key", newStr("relay")), ("value", newStr(url))]), nowMs())
    s.internet.restart()
    s.internetV1.restart()
    let k3 = P.p256Generate()
    var c = newNode(P, newMemStore(), k3)
    let ic = newInternet(c, newIdentity(k3), relayOf = proc (): string = url)
    ic.stunServers = @[]
    let room = s.v1Room
    ic.roomOf = proc (): string = room
    ic.start()
    var t = 0
    while t < 20_000 and not (ic.state == "online" and s.n.device in ic.online):
      poll(50); t += 50
    check s.n.device in ic.online
    let a = waitFor2 ic.askPeer(s.n.device, newObj(@[("t", newStr("succession"))]))
    check a["stmt"]["server"].s == s.n.device
    ic.stop()

  test "a removed v1 device cannot move":
    check s.store.getRow("v1_devices", phone["lost"].s)["revoked"].b
    check s.v1Waiting().elems.len == 0        # the v1 server's own keys never move; tom's phone moved, ann's was removed

  s.store.close()
  removeDir(tmp)
