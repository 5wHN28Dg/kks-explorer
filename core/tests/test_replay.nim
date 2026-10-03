import std/[unittest, times, strutils]
import kks/[json, util, crypto, proto, replay, extras]
import testprovider
import vectors

let P = testProvider()

proc firstDiff(a, b: string): string =
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]:
      return "at byte " & $i & ":\n  ours: " & a[max(0, i - 120) .. min(a.len - 1, i + 120)] &
             "\n  want: " & b[max(0, i - 120) .. min(b.len - 1, i + 120)]
  "lengths " & $a.len & " vs " & $b.len

proc checkScenarios(file: string) =
  let V = loadVectors(file)
  for s in V["scenarios"].elems:
    let t0 = epochTime()
    let got = stateBytes(P.replay(s["entries"].elems, s["root"].s))
    let want = stateBytes(s["state"])
    let ms = int((epochTime() - t0) * 1000)
    check got == want
    if got != want: echo "  ", s["why"].s, "\n  ", firstDiff(got, want)
    else: echo "  ok (", s["entries"].len, " entries, ", ms, " ms): ", s["why"].s

suite "replay (v2-replay.json)":
  test "scenarios":
    checkScenarios("v2-replay.json")
  test "any order gives the same state":
    let V = loadVectors("v2-replay.json")
    let s = V["scenarios"][0]
    var es = s["entries"].elems
    for i in 0 ..< es.len div 2: swap(es[i], es[es.len - 1 - i])
    check stateBytes(P.replay(es, s["root"].s)) == stateBytes(s["state"])
  test "root statement":
    let st = loadVectors("v2-replay.json")["statement"]
    let key = privateKeyFromHex(st["root_private_scalar_hex"].s, st["root"].s)
    check P.peerIdOfKey(st["root"].s) == st["root_id"].s
    check P.verify(st["root"].s, unhex(st["signed_bytes_hex"].s).toStr, st["root_sig"].s)
    discard key
  test "private entries":
    let pv = loadVectors("v2-replay.json")["private"]
    let secret = unhex(pv["secret_hex"].s)
    let body = P.privateBody(secret, pv["person"].s, pv["plaintext"]["type"].s, pv["plaintext"]["body"],
                             unhex(pv["nonce_hex"].s))
    check body == pv["body"]
    check P.privateOpen(secret, pv["body"]) == pv["plaintext"]

suite "malformed bodies (v2-malformed.json)":
  test "scenarios":
    checkScenarios("v2-malformed.json")

suite "diagnostics reports (v2-reports.json, §13a)":
  test "scenario":
    checkScenarios("v2-reports.json")
  test "the sealed report opens with the report key":
    let s = loadVectors("v2-reports.json")["seal"]
    let rk = privateKeyFromHex(s["report_key_private_scalar_hex"].s, s["report_key"].s)
    check hex(P.eciesOpen(rk, s["sealed"])) == s["plaintext_bytes_hex"].s
  test "the report_key private entry":
    let v = loadVectors("v2-reports.json")["report_key_private"]
    let got = P.privateOpen(unhex(v["secret_hex"].s), v["body"])
    check canonical(got) == canonical(v["plaintext"])
