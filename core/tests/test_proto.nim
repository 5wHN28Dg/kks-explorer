import std/[unittest, algorithm]
import kks/[json, util, crypto, proto]
import testprovider
import vectors

let P = testProvider()

proc codeOf(body: proc ()): string =
  try:
    body()
    "ok"
  except ProtocolError as e:
    e.code

suite "protocol v2 core (v2-core.json)":
  let V = loadVectors("v2-core.json")

  test "keys: peer IDs, validity, sign and verify":
    for k in V["keys"].elems:
      check P.peerIdOfKey(k["key"].s) == k["peer"].s
      check P.publicKey(k["key"].s).len == 65
      let key = privateKeyFromHex(k["private_scalar_hex"].s, k["key"].s)
      let sig = P.sign(key, "hello")
      check P.verify(k["key"].s, "hello", sig)
      check not P.verify(k["key"].s, "hellO", sig)

  test "keys_reject":
    for k in V["keys_reject"].elems:
      expect ValueError: discard P.publicKey(k["key"].s)

  test "entries: signed bytes, IDs, signatures":
    for c in V["entries"].elems:
      let e = c["entry"]
      check hex(signedBytes(e)) == c["signed_bytes_hex"].s
      check P.entryId(e) == c["entry_id"].s
    # later entries verify against their device's seq-1 key
    var keys: seq[(string, string)]
    for c in V["entries"].elems:
      if c["entry"]["seq"].i == 1: keys.add((c["entry"]["peer"].s, c["entry"]["key"].s))
    for c in V["entries"].elems:
      var k = ""
      for (peer, key) in keys:
        if peer == c["entry"]["peer"].s: k = key
      check codeOf(proc () = P.verifyEntry(c["entry"], k)) == "ok"

  test "entry_reject":
    for c in V["entry_reject"].elems:
      let e = if c.has("entry"): c["entry"] else: parseStrict(c["entry_json"].s)
      let ck = if c["chain_key"].isNull: "" else: c["chain_key"].s
      let got = codeOf(proc () = P.verifyEntry(e, ck))
      check got == c["code"].s
      if got != c["code"].s: echo "  ", c["why"].s, ": ", got

  test "entry ID ignores the signature":
    let c = V["entry_id_ignores_sig"]
    check P.entryId(c["entry"]) == c["entry_id"].s
    check P.entryId(c["resigned_high_s"]) == c["entry_id"].s

  test "chains":
    for c in V["chains"].elems:
      var order: seq[int64]
      let got = codeOf(proc () =
        for e in P.verifyChain(c["entries"].elems): order.add e["seq"].i)
      check got == c["result"].s
      if c.has("order"):
        var want: seq[int64]
        for x in c["order"].elems: want.add x.i
        check order == want

  test "hybrid logical clock":
    var h = Hlc()
    for c in V["hlc"].elems:
      let st = if c["op"].s == "now": h.now(c["wall"].i)
               else: h.recv((c["remote"][0].i, c["remote"][1].i), c["wall"].i)
      check st == (c["state"][0].i, c["state"][1].i)

  test "total order":
    let o = V["order"]
    var es = o["entries"].elems
    es.sort(orderCmp)
    var ids: seq[string]
    for e in es: ids.add P.entryId(e)
    var want: seq[string]
    for x in o["sorted_entry_ids"].elems: want.add x.s
    check ids == want

  test "low-S and high-S":
    let k = V["keys"][0]
    let key = privateKeyFromHex(k["private_scalar_hex"].s, k["key"].s)
    for i in 0 ..< 20:
      let raw = unb64u(P.sign(key, "m" & $i))
      var s: array[64, byte]
      for j in 0 ..< 64: s[j] = raw[j]
      check sigInRange(s)
      check not P.verify(k["key"].s, "m" & $i, b64u(highS(s)))
      check P.p256Verify(unb64u(k["key"].s), toBytes("m" & $i), highS(s))   # valid ECDSA, refused by §2

  test "generated keys":
    let key = P.p256Generate()
    check key.pub.len == 65 and key.scalar.len == 32
    check P.p256Valid(key.pub)
    let e = P.makeEntry(key, 1, "", (1790000000000'i64, 0'i64), "note", newObj(@[("text", newStr("hi"))]))
    check codeOf(proc () = P.verifyEntry(e)) == "ok"
