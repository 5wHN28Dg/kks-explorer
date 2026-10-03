## Sync through a relay pipe (PROTOCOL-v2 §18) against the Python relay twin (peer/relay_server.py):
## presence, connect with no candidates, the pipe, TLS + §15 inside it. Needs python3 with cryptography, or
## KKS_RELAY_URL (e.g. the Worker under `wrangler dev`).
import std/[unittest, asyncdispatch, os, osproc, strutils, sets, tables]
import kks/[json, util, crypto, proto, node, sync, plant]
import plat
import kksl/[net, internet]

let P = testProvider()
let repo = currentSourcePath().parentDir / ".." / ".." / ".."

proc waitUntil(cond: proc (): bool, ms = 10_000): bool =
  var t = 0
  while t < ms:
    if cond(): return true
    poll(50)
    t += 50
  cond()

suite "internet sync through the relay":
  # KKS_RELAY_URL=ws://127.0.0.1:8787 runs it against the real Worker under `wrangler dev` instead of the twin
  let external = getEnv("KKS_RELAY_URL")
  let py = if fileExists(repo / ".venv/bin/python"): repo / ".venv/bin/python" else: "python3"
  let port = 18000 + (getCurrentProcessId() mod 1000)
  let relayProc = if external.len > 0: nil
                  else: startProcess(py, repo, ["-m", "peer.relay_server", $port], options = {poStdErrToStdOut})
  if relayProc != nil: sleep(800)
  let url = if external.len > 0: external else: "ws://127.0.0.1:" & $port

  let rootKey = P.p256Generate()
  let kA = P.p256Generate()
  let kB = P.p256Generate()
  var a = newNode(P, newMemStore(), kA)
  let me = P.newPersonId()
  discard a.append("genesis", P.genesisBody(rootKey, "Test plant", a.device, me, "boss", "The Manager"), nowMs())
  a.adopt(keyString(rootKey.pub))
  discard a.append("device_cert", deviceCertBody(P.peerId(kB), me, "phone"), nowMs())
  discard a.append("setting", newObj(@[("key", newStr("relay")), ("value", newStr(url))]), nowMs())
  var b = newNode(P, newMemStore(), kB)
  b.adopt(a.root)
  let ia = newInternet(a, newIdentity(kA))
  let ib = newInternet(b, newIdentity(kB), relayOf = proc (): string = url)
  ia.stunServers = @[]     # tests: this machine's own addresses only (no public STUN server)
  ib.stunServers = @[]

  test "both appear in the room and B pulls A's log through the pipe":
    ia.start()
    ib.start()
    check waitUntil(proc (): bool = ia.state == "online" and ib.state == "online" and a.device in ib.online)
    checkpoint "presence: " & ia.state & " / " & ib.state
    let st = waitFor ib.syncPeer(a.device)
    check st.received == a.entries.len
    check relaySetting(b) == url

  test "a change travels the other way":
    discard b.append("setting", newObj(@[("key", newStr("note")), ("value", newStr("from b"))]), nowMs())
    let st = waitFor ia.syncPeer(b.device)
    check st.received == 1
    check a.entries.len == b.entries.len

  test "both offer candidates: the sync goes direct (hole punching + reliable UDP)":
    discard b.append("setting", newObj(@[("key", newStr("note2")), ("value", newStr("direct"))]), nowMs())
    let st = waitFor ia.syncPeer(b.device)
    check st.received == 1
    check ia.lastHow == "direct" and ib.lastHow == "direct"

  test "one side without direct connections: both use the relay pipe":
    ib.direct = false
    discard b.append("setting", newObj(@[("key", newStr("note3")), ("value", newStr("pipe"))]), nowMs())
    let st = waitFor ia.syncPeer(b.device)
    check st.received == 1
    check ia.lastHow == "relay" and ib.lastHow == "relay"
    ib.direct = true

  test "an absent device is reported":
    expect NetError:
      discard waitFor ia.syncPeer(P.peerId(P.p256Generate()))

  test "leaving is seen":
    ib.stop()
    check waitUntil(proc (): bool = b.device notin ia.online)
    ia.stop()

  if relayProc != nil:
    relayProc.terminate()
    discard relayProc.waitForExit()
    relayProc.close()
