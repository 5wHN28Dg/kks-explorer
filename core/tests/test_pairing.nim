## Course progress between a person's own devices (PROTOCOL-v2 §17, decision 0062): the vectors (pairing code, the
## sealed share, which secret writes, hostile shares, the merge), then whole devices: pairing by code, a device the
## server certified on its own, offline progress on two devices, a removed device, and what a hub can see.
import std/[unittest, tables, strutils]
import kks/[json, util, crypto, proto, replay, node, plant, progress, extras]
import testprovider
import vectors

let P = testProvider()
var clock = 1_800_000_000_000'i64
proc tick(): int64 =
  clock += 1000
  clock

proc share(src, dst: Node) = discard dst.ingest(src.entriesFor(dst.vv), tick())

suite "pairing vectors (v2-pairing.json)":
  let V = loadVectors("v2-pairing.json")

  test "the sealed share: the same bytes from the same ephemeral key and nonce, and it opens":
    let s = V["share"]
    let box = privateKeyFromHex(s["box_private_scalar_hex"].s, s["box_key"].s)
    let pt = sharePlain(s["plaintext"]["person"].s, s["plaintext"]["from"].s, s["plaintext"]["to"].s,
                        block:
                          var r: seq[SecretRec]
                          for x in s["plaintext"]["secrets"].elems: r.add (unb64u(x["k"].s), x["made"].i)
                          r)
    check hex(canonical(pt).toBytes) == s["plaintext_bytes_hex"].s
    let eph2 = PrivateKey(scalar: unhex(s["eph_private_scalar_hex"].s), pub: P.publicKey(s["sealed"]["epk"].s))
    check P.eciesSeal(s["box_key"].s, SharePurpose, canonical(pt).toBytes, eph2, unhex(s["nonce_hex"].s)) == s["sealed"]
    let (ok, got) = P.takeShare(box, s["sealed"], s["plaintext"]["from"].s, s["plaintext"]["to"].s,
                                s["plaintext"]["person"].s)
    check ok and got.len == 2 and got[0].made == 7000

  test "taking shares in: only a well-formed share for this person and device gives anything":
    let box = privateKeyFromHex(V["share"]["box_private_scalar_hex"].s, V["share"]["box_key"].s)
    for t in V["take"].elems:
      let (ok, got) = P.takeShare(box, t["sealed"], t["author"].s, t["me"].s, t["person"].s)
      if t["secrets"].kind == jNull:
        check not ok
        if ok: echo "  took from: ", t["why"].s
      else:
        check ok and got.len == t["secrets"].len
        for i, x in t["secrets"].elems:
          check hex(got[i].k) == x["k_hex"].s and got[i].made == x["made"].i

  test "pairing codes":
    for c in V["pair_codes"].elems:
      check P.pairCode(c["a"].s, c["box_a"].s, c["b"].s, c["box_b"].s) == c["code"].s
      check P.pairCode(c["b"].s, c["box_b"].s, c["a"].s, c["box_a"].s) == c["code"].s

  test "which secret writes":
    for w in V["write_secret"].elems:
      let n = newNode(P, newMemStore(), P.p256Generate())
      var recs: seq[SecretRec]
      for x in w["secrets"].elems: recs.add (unhex(x["k_hex"].s), x["made"].i)
      discard n.addSecrets("p", recs)
      check hex(n.secretsOf("p")[0]) == w["writes_hex"].s

  test "progress merges: union, the larger best, the later value":
    for m in V["merge"].elems:
      var cur = ""
      for v in m["values"].elems: cur = mergeValue(m["key"].s, cur, v.s)
      if m["merged_is_json"].b: check parseStrict(cur) == m["merged"]
      else: check cur == m["merged"].s
      if (m["merged_is_json"].b and parseStrict(cur) != m["merged"]) or
         (not m["merged_is_json"].b and cur != m["merged"].s): echo "  ", m["why"].s, ": ", cur

  test "secrets stored before 2026-10-22 (bare strings) still open":
    let n = newNode(P, newMemStore(), P.p256Generate())
    let k = P.randomBytes(32)
    n.store.setMeta("person_secrets:p", toText(newArr(@[newStr(b64u(k))])))
    check n.secretsOf("p") == @[k]
    discard n.addSecrets("p", @[(P.randomBytes(32), 5'i64)])
    check n.secretRecs("p").len == 2 and n.secretRecs("p")[1].k == k

proc progressOf(n: Node, person: string): OrderedTable[string, string] =
  let all = n.loadProgress(person)
  if "hrsg" in all: all["hrsg"] else: initOrderedTable[string, string]()

proc save(n: Node, k, v: string) =
  var d: OrderedTable[string, string]
  d[k] = v
  discard n.saveProgress("hrsg", d, tick())

proc codeFor(n: Node, other: string): string =
  for d in n.pairingList["devices"].elems:
    if d["device"].s == other: return d["code"].s

suite "pairing between a person's own devices":
  # the hub stands for the server: it certifies devices (as with a custodial key) and relays everything
  let rootKey = P.p256Generate()
  let hub = newNode(P, newMemStore(), P.p256Generate())
  let mgr = P.newPersonId()
  discard hub.append("genesis", P.genesisBody(rootKey, "Test plant", hub.device, mgr, "boss", "The Manager"), tick())
  hub.adopt(keyString(rootKey.pub))
  let bob = P.newPersonId()
  discard hub.append("person", personBody(bob, "bob", "Bob User", "user"), tick())
  let phone = newNode(P, newMemStore(), P.p256Generate())
  let tablet = newNode(P, newMemStore(), P.p256Generate())
  let laptop = newNode(P, newMemStore(), P.p256Generate())
  let minted = newNode(P, newMemStore(), P.p256Generate())    # a device the server certified for bob on its own
  for (n, label) in [(phone, "phone"), (tablet, "tablet"), (laptop, "laptop"), (minted, "phone")]:
    discard hub.append("device_cert", deviceCertBody(n.device, bob, label), tick())
    n.adopt(hub.root)
  let devs = @[phone, tablet, laptop, minted]
  proc round() =
    ## every device syncs with the hub and runs its upkeep, twice (what one device writes reaches the others)
    for _ in 0 ..< 2:
      for n in devs:
        share(hub, n)
        discard n.progressTick(tick())
        share(n, hub)

  test "before pairing: each device keeps its own progress; nobody else opens it":
    round()
    phone.save("solved", """{"q1_r":true}""")
    round()
    check phone.progressOf(bob)["solved"] == """{"q1_r":true}"""
    check tablet.progressOf(bob).len == 0 and minted.progressOf(bob).len == 0

  test "both devices show the same code for each other; a server-certified device has a different one":
    check phone.pairingList["ready"].b and tablet.pairingList["ready"].b
    check phone.codeFor(tablet.device).len == 6
    check phone.codeFor(tablet.device) == tablet.codeFor(phone.device)
    check phone.codeFor(minted.device) != tablet.codeFor(phone.device)
    check phone.codeFor(hub.device) == ""      # it wrote no box key: never offered

  test "pairing on one side only gives nothing; on both, progress follows":
    phone.pair(tablet.device, tick())
    round()
    check tablet.progressOf(bob).len == 0          # the tablet has not confirmed the phone yet
    tablet.pair(phone.device, tick())
    round()
    check tablet.progressOf(bob)["solved"] == """{"q1_r":true}"""
    tablet.save("finalBest", "7")
    round()
    check phone.progressOf(bob)["finalBest"] == "7"
    check phone.secretsOf(bob)[0] == tablet.secretsOf(bob)[0]

  test "offline on both devices: nothing is lost when they meet":
    phone.save("solved", """{"q1_r":true,"q2_f":true}""")
    phone.save("finalBest", "9")
    tablet.save("solved", """{"q1_r":true,"q3_p":true}""")
    tablet.save("finalBest", "4")
    tablet.save("skip", """{"m1":true}""")
    round()
    for n in [phone, tablet]:
      let p = n.progressOf(bob)
      check parseStrict(p["solved"]) == parseStrict("""{"q1_r":true,"q2_f":true,"q3_p":true}""")
      check p["finalBest"] == "9"
      check parseStrict(p["skip"]) == parseStrict("""{"m1":true}""")

  test "a device the server certified alone gets nothing and can plant nothing":
    # it shares a newer secret of its own to the phone: the phone never paired with it, so it keeps writing as before
    let before = phone.secretsOf(bob)
    let planted = P.randomBytes(32)
    discard minted.addSecrets(bob, @[(planted, tick() + 10_000_000)])
    let sealed = P.eciesSeal(minted.run.boxKeys[phone.device], SharePurpose,
                             canonical(sharePlain(bob, minted.device, phone.device, minted.secretRecs(bob))).toBytes)
    discard minted.append("secret_share", newObj(@[("to", newStr(phone.device)), ("sealed", sealed)]), tick())
    round()
    check phone.secretsOf(bob) == before
    check minted.progressOf(bob).len == 0
    check minted.device notin minted.run.shares     # nobody shared to it
    expect ValueError: phone.pair(hub.device, tick())

  test "secrets travel along pairings: a laptop paired with the tablet only reads the phone's progress":
    laptop.pair(tablet.device, tick())
    tablet.pair(laptop.device, tick())
    round()
    check parseStrict(laptop.progressOf(bob)["solved"]) == parseStrict("""{"q1_r":true,"q2_f":true,"q3_p":true}""")
    laptop.save("last", "\"p9\"")
    round()
    check phone.progressOf(bob)["last"] == "\"p9\""

  test "removing a device moves the others to a new secret it never sees":
    let old = phone.secretsOf(bob)[0]
    discard phone.append("revoke", newObj(@[("device", newStr(laptop.device)),
                                            ("last_seq", newInt(laptop.vv[laptop.device][0].i))]), tick())
    round()
    let now = phone.secretsOf(bob)[0]
    check now != old and tablet.secretsOf(bob)[0] == now
    check now notin laptop.secretsOf(bob)
    phone.save("solved", """{"q9_r":true}""")
    round()
    check "q9_r" in tablet.progressOf(bob)["solved"]
    let last = phone.run.private[bob][^1]
    for k in laptop.secretsOf(bob):
      expect CatchableError: discard P.privateOpen(k, phone.entries[last]["body"])

  test "the hub holds only ciphertext: no secret, no box key, no progress in the clear":
    check hub.secretsOf(bob).len == 0 and hub.loadProgress(bob).len == 0
    check hub.device notin hub.run.boxKeys
    let ms = MemStore(hub.store)
    var everything = ""
    for k, v in ms.meta: everything.add k & v
    for e in hub.entries.values: everything.add toText(e)
    check "q1_r" notin everything and "finalBest" notin everything and "solved" notin everything
    for n in [phone, tablet]:
      for k in n.secretsOf(bob):
        check b64u(k) notin everything and hex(k) notin everything
