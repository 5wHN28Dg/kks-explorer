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
                          r,
                        @[s["plaintext"]["holders"][0].s], @[s["plaintext"]["removed"][0]],
                        @[s["plaintext"]["retired"][0].s])
    check hex(canonical(pt).toBytes) == s["plaintext_bytes_hex"].s
    let eph2 = PrivateKey(scalar: unhex(s["eph_private_scalar_hex"].s), pub: P.publicKey(s["sealed"]["epk"].s))
    check P.eciesSeal(s["box_key"].s, SharePurpose, canonical(pt).toBytes, eph2, unhex(s["nonce_hex"].s)) == s["sealed"]
    let (ok, got) = P.takeShare(box, s["sealed"], s["plaintext"]["from"].s, s["plaintext"]["to"].s,
                                s["plaintext"]["person"].s)
    check ok and got.secrets.len == 2 and got.secrets[0].made == 7000
    check got.holders == @[s["plaintext"]["holders"][0].s] and got.removedProofs == @[s["plaintext"]["removed"][0]]

  test "taking shares in: only a well-formed share for this person and device gives anything":
    let box = privateKeyFromHex(V["share"]["box_private_scalar_hex"].s, V["share"]["box_key"].s)
    for t in V["take"].elems:
      let (ok, got) = P.takeShare(box, t["sealed"], t["author"].s, t["me"].s, t["person"].s)
      if t["secrets"].kind == jNull:
        check not ok
        if ok: echo "  took from: ", t["why"].s
      else:
        check ok and got.secrets.len == t["secrets"].len
        for i, x in t["secrets"].elems:
          check hex(got.secrets[i].k) == x["k_hex"].s and got.secrets[i].made == x["made"].i
        check got.holders.len == t["holders"].len and got.removedProofs.len == t["removed"].len and
              got.retired.len == t["retired"].len

  test "pairing codes and commitments":
    for c in V["pair_codes"].elems:
      check P.pairCode(c["a"].s, c["box_a"].s, c["nonce_a"].s, c["b"].s, c["box_b"].s, c["nonce_b"].s) == c["code"].s
      check P.pairCode(c["b"].s, c["box_b"].s, c["nonce_b"].s, c["a"].s, c["box_a"].s, c["nonce_a"].s) == c["code"].s
      check P.pairCommit(c["a"].s, c["b"].s, c["box_a"].s, c["nonce_a"].s) == c["commit_a"].s

  test "which secret writes":
    for w in V["write_secret"].elems:
      let n = newNode(P, newMemStore(), P.p256Generate())
      var recs: seq[SecretRec]
      for x in w["secrets"].elems: recs.add (unhex(x["k_hex"].s), x["made"].i)
      discard n.addSecrets("p", recs)
      n.store.setMeta("retired_secrets", toText(w["retired"]))
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

proc rowOf(n: Node, other: string): JNode =
  for d in n.pairingList["devices"].elems:
    if d["device"].s == other: return d

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
    ## every device syncs with the hub and runs its upkeep, three times (what one device writes reaches the others)
    for _ in 0 ..< 3:
      for n in devs:
        share(hub, n)
        discard n.progressTick(tick())
        share(n, hub)
  proc pairBoth(x, y: Node) =
    ## the person presses Pair on both, the devices sync, both show the same code, the person confirms on both
    x.startPairing(y.device, tick())
    round()
    check x.rowOf(y.device)["state"].s == "waiting" and y.rowOf(x.device)["state"].s in ["asked", "paired"]
    y.startPairing(x.device, tick())
    round()
    let cx = x.rowOf(y.device)
    let cy = y.rowOf(x.device)
    check cx["state"].s == "compare" and cy["state"].s == "compare"
    check cx["code"].s.len == 6 and cx["code"].s == cy["code"].s
    x.confirmPairing(y.device, cx["code"].s, tick())
    y.confirmPairing(x.device, cy["code"].s, tick())
    round()
    check x.rowOf(y.device)["state"].s == "paired" and y.rowOf(x.device)["state"].s == "paired"

  test "before pairing: each device keeps its own progress; nobody else opens it":
    round()
    phone.save("solved", """{"q1_r":true}""")
    round()
    check phone.progressOf(bob)["solved"] == """{"q1_r":true}"""
    check tablet.progressOf(bob).len == 0 and minted.progressOf(bob).len == 0
    check phone.pairingList["ready"].b and phone.rowOf(tablet.device)["state"].s == "none"
    check phone.rowOf(hub.device) == nil      # it wrote no box key: never offered

  test "a device reveals its nonce only after the other's commitment, and takes only the reveal committed to":
    # the server's own device for bob, impersonating the tablet: whatever it reveals afterwards, the phone's code is
    # the one its commitment fixed before the phone's nonce was known (no grinding for a chosen code)
    let before = phone.entries.len
    phone.startPairing(minted.device, tick())
    share(phone, hub)
    share(hub, minted)
    var revealed = false
    for e in phone.entries.values:
      if e["type"].s == "pair_reveal" and e["peer"].s == phone.device: revealed = true
    check not revealed and phone.entries.len == before + 1     # the commitment only
    let nonce = b64u(P.randomBytes(16))
    discard minted.append("pair_commit", newObj(@[("to", newStr(phone.device)),
      ("commit", newStr(P.pairCommit(minted.device, phone.device, minted.run.boxKeys[minted.device], nonce)))]), tick())
    share(minted, hub)
    share(hub, phone)
    discard phone.progressTick(tick())
    share(phone, hub)
    share(hub, minted)
    # the phone's nonce is out; the minted device tries other nonces to steer the code, then the committed one
    for i in 0 ..< 50:
      discard minted.append("pair_reveal", newObj(@[("to", newStr(phone.device)), ("nonce", newStr(b64u(P.randomBytes(16))))]), tick())
    discard minted.append("pair_reveal", newObj(@[("to", newStr(phone.device)), ("nonce", newStr(nonce))]), tick())
    share(minted, hub)
    share(hub, phone)
    discard phone.progressTick(tick())
    let row = phone.rowOf(minted.device)
    var phoneNonce = ""
    for e in phone.entries.values:
      if e["type"].s == "pair_reveal" and e["peer"].s == phone.device: phoneNonce = e["body"]["nonce"].s
    check row["state"].s == "compare"
    check row["code"].s == P.pairCode(phone.device, phone.run.boxKeys[phone.device], phoneNonce, minted.device,
                                      minted.run.boxKeys[minted.device], nonce)
    # the person sees a code no device of theirs shows, and does not confirm: nothing is shared
    round()
    check minted.device notin minted.run.shares

  test "pairing on both: progress follows; a code that does not match is refused":
    expect ValueError: phone.confirmPairing(tablet.device, "000000", tick())
    pairBoth(phone, tablet)
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
    let before = phone.secretsOf(bob)
    let planted = P.randomBytes(32)
    discard minted.addSecrets(bob, @[(planted, tick() + 10_000_000)])
    let sealed = P.eciesSeal(minted.run.boxKeys[phone.device], SharePurpose,
                             canonical(sharePlain(bob, minted.device, phone.device, minted.secretRecs(bob), @[], @[])).toBytes)
    discard minted.append("secret_share", newObj(@[("to", newStr(phone.device)), ("sealed", sealed)]), tick())
    round()
    check phone.secretsOf(bob) == before
    check minted.progressOf(bob).len == 0
    check minted.device notin minted.run.shares
    expect ValueError: phone.startPairing(hub.device, tick())

  test "secrets travel along pairings: a laptop paired with the tablet only reads the phone's progress":
    pairBoth(laptop, tablet)
    check parseStrict(laptop.progressOf(bob)["solved"]) == parseStrict("""{"q1_r":true,"q2_f":true,"q3_p":true}""")
    laptop.save("last", "\"p9\"")
    round()
    check phone.progressOf(bob)["last"] == "\"p9\""

  test "removing a device moves every other device to a new secret, even one never paired with it":
    # the laptop's clock ran a year ahead when it made a secret: the new one must still be the newest
    discard laptop.addSecrets(bob, @[(P.randomBytes(32), tick() + 365 * 86_400_000)])
    laptop.save("finalBest", "11")
    round()
    let old = phone.secretsOf(bob)[0]
    check old == laptop.secretsOf(bob)[0]
    # the phone removes the laptop; the phone never paired with it, the tablet did
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
    # the order-free progress (solved, the bests) was saved again under the new secret: a device holding only it reads
    # it; "last" and "skip" are not (a re-save would stamp an old value over a newer one written offline elsewhere)
    let fresh = newNode(P, newMemStore(), P.p256Generate())
    discard fresh.addSecrets(bob, @[(now, 0'i64)])
    share(hub, fresh)
    fresh.adopt(hub.root)
    share(hub, fresh)
    let p = fresh.progressOf(bob)
    check p["finalBest"] == "11" and "q3_p" in p["solved"] and "last" notin p

  test "the same two devices pair again (after Start again): the codes match again":
    # the tablet's commitment from the last pairing is spent (its nonce is out): the phone waits for a new one
    phone.startPairing(tablet.device, tick())
    check phone.rowOf(tablet.device)["state"].s == "waiting"
    pairBoth(phone, tablet)
    check phone.secretsOf(bob)[0] == tablet.secretsOf(bob)[0]

  test "devices the server certified alone can't make the person's devices rotate":
    let r2 = newNode(P, newMemStore(), P.p256Generate())
    discard hub.append("device_cert", deviceCertBody(r2.device, bob, "tablet"), tick())
    r2.adopt(hub.root)
    share(hub, r2)
    discard r2.progressTick(tick())
    share(r2, hub)
    share(hub, minted)
    discard minted.progressTick(tick())
    let sealed = P.eciesSeal(r2.run.boxKeys[r2.device], SharePurpose,
                             canonical(sharePlain(bob, minted.device, r2.device, @[(P.randomBytes(32), 1'i64)], @[], @[])).toBytes)
    discard minted.append("secret_share", newObj(@[("to", newStr(r2.device)), ("sealed", sealed)]), tick())
    discard minted.append("revoke", newObj(@[("device", newStr(r2.device)), ("last_seq", newInt(r2.vv[r2.device][0].i))]), tick())
    share(minted, hub)
    let before = phone.secretRecs(bob).len
    round()
    check phone.secretRecs(bob).len == before and tablet.secretRecs(bob).len == before

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

suite "removals the server would hide, and a secret from the far future":
  # v is removed by x; y sees that and moves to a new secret; the server holds x's revoke back from z (it can: z gets
  # x's chain only up to before the revoke) but passes y's share on. v had been paired with x and with z.
  let rootKey = P.p256Generate()
  let hub = newNode(P, newMemStore(), P.p256Generate())
  let mgr = P.newPersonId()
  discard hub.append("genesis", P.genesisBody(rootKey, "Test plant", hub.device, mgr, "boss", "The Manager"), tick())
  hub.adopt(keyString(rootKey.pub))
  let bob = P.newPersonId()
  discard hub.append("person", personBody(bob, "bob", "Bob User", "user"), tick())
  var v, x, y, z: Node
  for (n, label) in [(addr v, "v"), (addr x, "x"), (addr y, "y"), (addr z, "z")]:
    n[] = newNode(P, newMemStore(), P.p256Generate())
    discard hub.append("device_cert", deviceCertBody(n[].device, bob, label), tick())
    n[].adopt(hub.root)
  var devs = @[v, x, y, z]
  proc round() =
    for _ in 0 ..< 3:
      for n in devs:
        share(hub, n)
        discard n.progressTick(tick())
        share(n, hub)
  proc pairBoth(a, b: Node) =
    a.startPairing(b.device, tick())
    round()
    b.startPairing(a.device, tick())
    round()
    let code = a.rowOf(b.device)["code"].s
    check code.len == 6 and b.rowOf(a.device)["code"].s == code
    a.confirmPairing(b.device, code, tick())
    b.confirmPairing(a.device, code, tick())
    round()

  test "a far-future made from a device later removed can't keep its secret writing":
    round()
    pairBoth(x, y)
    pairBoth(y, z)
    pairBoth(v, x)
    pairBoth(v, z)
    v.save("solved", """{"a_r":true}""")
    round()
    # v (to be stolen) shares a secret made at the largest allowed time to z alone
    let evil = P.randomBytes(32)
    let sealed = P.eciesSeal(v.run.boxKeys[z.device], SharePurpose, canonical(sharePlain(bob, v.device, z.device,
                             @[(evil, MaxInt53)] & v.secretRecs(bob), @[], @[])).toBytes)
    discard v.append("secret_share", newObj(@[("to", newStr(z.device)), ("sealed", sealed)]), tick())
    share(v, hub)
    share(hub, z)
    discard z.progressTick(tick())
    check z.secretsOf(bob)[0] == evil
    check evil notin x.secretsOf(bob) and evil notin y.secretsOf(bob)
    # x removes v; the server holds that revoke back from z
    discard x.append("revoke", newObj(@[("device", newStr(v.device)), ("last_seq", newInt(v.vv[v.device][0].i))]), tick())
    let cutAt = x.vv[x.device][0].i
    devs = @[x, y]
    round()            # (z does not sync meanwhile: it has not passed the evil secret on)
    check x.secretsOf(bob)[0] != evil and y.secretsOf(bob)[0] != evil
    var batch: seq[JNode]
    for e in hub.entriesFor(z.vv):
      if e["peer"].s != x.device or e["seq"].i < cutAt: batch.add e
    discard z.ingest(batch, tick())
    check v.device notin z.run.cuts
    let before = z.entries.len
    discard z.progressTick(tick())
    check z.secretsOf(bob)[0] == y.secretsOf(bob)[0]            # y's share told it, and brought the new secret
    check v.device notin z.pairedSet
    var sharedToV = false
    var i = 0
    for id, e in z.entries:
      inc i
      if i > before and e["type"].s == "secret_share" and e["body"]["to"].s == v.device: sharedToV = true
    check not sharedToV
    check evil notin @[x.secretsOf(bob)[0], y.secretsOf(bob)[0], z.secretsOf(bob)[0]]

  test "a share naming a removal without a revoke entry that checks out changes nothing":
    # y (still trusted) tells z that x was removed, with a forged revoke (x is live): z ignores it
    devs = @[x, y, z]
    round()
    pairBoth(x, z)
    var forged = copy(y.revocationOf(v.device))
    forged["body"]["device"] = newStr(x.device)        # the signature no longer matches
    let sealed = P.eciesSeal(y.run.boxKeys[z.device], SharePurpose, canonical(sharePlain(bob, y.device, z.device,
                             y.secretRecs(bob), @[], @[forged, newObj(@[("type", newStr("revoke"))])])).toBytes)
    discard y.append("secret_share", newObj(@[("to", newStr(z.device)), ("sealed", sealed)]), tick())
    round()
    check x.device in z.pairedSet and x.device notin z.listMeta("removed_holders")

  test "a removed device's secret carried in late by a device that had not heard of the removal never writes":
    let w = newNode(P, newMemStore(), P.p256Generate())
    discard hub.append("device_cert", deviceCertBody(w.device, bob, "w"), tick())
    w.adopt(hub.root)
    devs = @[w, x, y, z]
    round()
    pairBoth(w, x)
    round()
    # w (to be stolen) shares a far-future secret to x alone, then y removes w
    let late = P.randomBytes(32)
    let sealed = P.eciesSeal(w.run.boxKeys[x.device], SharePurpose, canonical(sharePlain(bob, w.device, x.device,
                             @[(late, MaxInt53)] & w.secretRecs(bob), @[], @[x.revocationOf(v.device)])).toBytes)   # (it knew of v)
    discard w.append("secret_share", newObj(@[("to", newStr(x.device)), ("sealed", sealed)]), tick())
    share(w, hub)
    discard y.ingest(hub.entriesFor(y.vv), tick())
    discard y.append("revoke", newObj(@[("device", newStr(w.device)), ("last_seq", newInt(w.vv[w.device][0].i))]), tick())
    discard y.progressTick(tick())
    share(y, z)
    discard z.progressTick(tick())
    let now = z.secretsOf(bob)[0]
    check now == y.secretsOf(bob)[0] and now notin x.secretsOf(bob)      # y moved to a new secret
    # x had not heard: it takes w's secret, writes with it, and shares it to z
    share(w, x)
    discard x.progressTick(tick())
    check x.secretsOf(bob)[0] == late
    share(x, z)
    discard z.progressTick(tick())
    check late in z.secretsOf(bob)                 # held, readable
    check z.secretsOf(bob)[0] == now               # but never written with

  test "a new holder reaches the other paired devices even when no secret is new":
    let q = newNode(P, newMemStore(), P.p256Generate())
    discard hub.append("device_cert", deviceCertBody(q.device, bob, "q"), tick())
    q.adopt(hub.root)
    devs = @[q, x, y, z]
    round()
    check q.secretsOf(bob).len == 0                 # it has saved nothing: it brings no secret
    pairBoth(q, x)
    round()
    check q.device in y.listMeta("holders") and q.device in z.listMeta("holders")
