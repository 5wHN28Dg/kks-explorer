## Person secrets and course progress (PROTOCOL-v2 §13, §17): private entries only the person's own devices can read.
## Secrets reach another device only sealed to its box key, after the person paired the two (decision 0062).

import std/[algorithm, strutils, tables]
import json, crypto, util, proto, replay, node, extras

const
  MaxValue = 200_000
  MaxTotal = 600_000
  MaxSecrets* = 32
  SharePurpose* = "kks-person-secret"
  BoxKeyMeta = "box_key"            ## this device's box key: {"scalar": hex, "pub": key string}
  BoxWrittenMeta = "box_key_written" ## the box key string this device has written a box_key entry for
  PairedMeta = "paired"             ## the devices the person paired this one with: {device: their box key then}
  AttemptsMeta = "pair_attempts"    ## pairings under way: {device: {"nonce", "mine", "theirs"?, "their_nonce"?}}
  RotatedMeta = "rotated_for"       ## removed devices this device has made a new secret for: [device ID, …]
  SentMeta = "shares_sent"          ## {device: {"box": key string, "sent": [secret SHA-256 hex, …]}}
  TakenMeta = "shares_taken"        ## secret_share entry IDs already taken in: [entry ID, …]

type SecretRec* = tuple[k: seq[byte], made: int64]

proc secretsKey(person: string): string = "person_secrets:" & person

proc metaJson(n: Node, key: string, empty: JNode): JNode =
  let raw = n.store.getMeta(key)
  if raw.len == 0: return empty
  try: parseStrict(raw) except JsonError: empty

proc secretRecs*(n: Node, person: string): seq[SecretRec] =
  ## This person's secrets known here, the one to write with first (§17: the newest `made`; equal: the lowest
  ## SHA-256 hex). Stored before 2026-10-22 as bare strings: those count as made 0.
  var withSha: seq[(int64, string, seq[byte])]
  for x in n.metaJson(secretsKey(person), newArr()).elems:
    try:
      var k: seq[byte]
      var made = 0'i64
      if x.kind == jStr: k = unb64u(x.s)
      elif x.kind == jObj and x.get("k") != nil and x["k"].isStr and x.get("made") != nil and x["made"].kind == jInt:
        k = unb64u(x["k"].s)
        made = x["made"].i
      else: continue
      if k.len == 32: withSha.add((made, hex(n.p.sha256(k)), k))
    except ValueError: discard
  withSha.sort(proc (a, b: (int64, string, seq[byte])): int =
    result = cmp(b[0], a[0])
    if result == 0: result = cmp(a[1], b[1]))
  for (m, _, k) in withSha: result.add (k, m)

proc secretsOf*(n: Node, person: string): seq[seq[byte]] =
  ## This person's secrets known here; the one to write with first.
  for r in n.secretRecs(person): result.add r.k

proc addSecrets*(n: Node, person: string, secrets: seq[SecretRec]): int =
  ## Keep the secrets not held yet. -> how many were new
  var have = n.secretRecs(person)
  for s in secrets:
    if s.k.len != 32 or s.made < 0: continue
    var known = false
    for h in have:
      if h.k == s.k: known = true
    if not known:
      have.add s
      inc result
  if result > 0:
    var a = newArr()
    for s in have: a.elems.add newObj(@[("k", newStr(b64u(s.k))), ("made", newInt(s.made))])
    n.store.setMeta(secretsKey(person), toText(a))

proc addSecrets*(n: Node, person: string, secrets: seq[seq[byte]]): int =
  ## bare secrets (made 0): tests, and secrets from before 2026-10-22
  var recs: seq[SecretRec]
  for s in secrets: recs.add (s, 0'i64)
  n.addSecrets(person, recs)

proc newSecret(n: Node, person: string, wall: int64): seq[byte] =
  ## a new secret that is the newest held (§17: a clock behind another device's must not keep an old one writing)
  var made = max(wall, 0'i64)
  for r in n.secretRecs(person): made = max(made, r.made + 1)
  result = n.p.randomBytes(32)
  discard n.addSecrets(person, @[(result, made)])

proc ensureSecret*(n: Node, person: string, wall = 0'i64): seq[byte] =
  ## The secret to write with, made now when this device holds none.
  let got = n.secretsOf(person)
  if got.len > 0: got[0] else: n.newSecret(person, wall)

proc owner*(n: Node): string =
  ## The person this device belongs to ("" if not certified).
  if n.run != nil and n.device in n.run.devices: n.run.devices[n.device]["person"].s else: ""

# ---------------------------------------------------------------- §17 box key, pairing, shares

proc heldBoxKey(n: Node): (bool, PrivateKey) =
  let j = n.metaJson(BoxKeyMeta, newNull())
  if j.kind == jObj and j.get("scalar") != nil and j.get("pub") != nil and j["scalar"].isStr and j["pub"].isStr:
    try: return (true, PrivateKey(scalar: unhex(j["scalar"].s), pub: unb64u(j["pub"].s)))
    except ValueError: discard

proc boxKey*(n: Node): PrivateKey =
  ## This device's key for receiving person secrets, made on first use and kept in the sealed store (never sent).
  let (has, k) = n.heldBoxKey
  if has: return k
  result = n.p.p256Generate()
  n.store.setMeta(BoxKeyMeta, toText(newObj(@[("scalar", newStr(hex(result.scalar))),
                                               ("pub", newStr(keyString(result.pub)))])))

proc pairCode*(p: Provider, devA, boxA, nonceA, devB, boxB, nonceB: string): string =
  ## §17: the 6 digits both devices show; the two IDs sorted, each followed by its box key and its revealed nonce
  let (x, kx, nx, y, ky, ny) = if devA < devB: (devA, boxA, nonceA, devB, boxB, nonceB)
                               else: (devB, boxB, nonceB, devA, boxA, nonceA)
  let d = p.sha256(toBytes("kks-pair-code-v2\n" & x & "\n" & kx & "\n" & nx & "\n" & y & "\n" & ky & "\n" & ny))
  let v = (uint32(d[0]) shl 24) or (uint32(d[1]) shl 16) or (uint32(d[2]) shl 8) or uint32(d[3])
  align($(v mod 1_000_000), 6, '0')

proc pairCommit*(p: Provider, dev, to, box, nonce: string): string =
  ## §17: what a pair_commit carries: the hash of the nonce it will reveal, bound to both devices and its box key
  hex(p.sha256(toBytes("kks-pair-commit-v1\n" & dev & "\n" & to & "\n" & box & "\n" & nonce)))

proc pairedMap*(n: Node): OrderedTable[string, string] =
  ## device → the box key the person confirmed with it
  let j = n.metaJson(PairedMeta, newObj())
  if j.kind == jObj:
    for (k, v) in j.fields:
      if v.isStr: result[k] = v.s

proc setPaired(n: Node, m: OrderedTable[string, string]) =
  var o = newObj()
  for k, v in m: o[k] = newStr(v)
  n.store.setMeta(PairedMeta, toText(o))

proc pairedSet*(n: Node): seq[string] =
  for k in n.pairedMap.keys: result.add k

proc live(n: Node, d: string): bool = n.run != nil and d in n.run.devices and d notin n.run.cuts

proc ownDevice(n: Node, d: string): bool =
  n.live(d) and d != n.device and n.owner.len > 0 and n.run.devices[d]["person"].s == n.owner

proc myBoxPublished(n: Node): string =
  ## this device's box key as the log has it ("" until its box_key entry is in the replay)
  let (has, key) = n.heldBoxKey
  if n.run == nil or not has: return ""
  let k = keyString(key.pub)
  if n.run.boxKeys.getOrDefault(n.device) == k: k else: ""

proc stepsFrom(n: Node, d, typ: string): seq[JNode] =
  ## the bodies of `typ` entries from device `d` to this device, in replay order
  for id in n.run.pairSteps.getOrDefault(n.device):
    let e = n.entries.getOrDefault(id)
    if e != nil and e["peer"].s == d and e["type"].s == typ: result.add e["body"]

proc attempts(n: Node): JNode =
  result = n.metaJson(AttemptsMeta, newObj())
  if result.kind != jObj: result = newObj()

proc takeShare*(p: Provider, box: PrivateKey, sealed: JNode, author, me, person: string): (bool, seq[SecretRec]) =
  ## §17 "Taking a share in": the secrets a share gives (false = it gives nothing). The caller checks that the entry
  ## is valid in replay and that its author is in this device's paired set.
  try:
    if sealed.kind != jObj or sealed.get("purpose") == nil or not sealed["purpose"].isStr or
       sealed["purpose"].s != SharePurpose: return
    let o = parseStrict(p.eciesOpen(box, sealed).toStr)
    if o.kind != jObj or o.fields.len != 4: return
    for k in ["person", "from", "to", "secrets"]:
      if o.get(k) == nil: return
    if not (o["person"].isStr and o["person"].s == person and o["from"].isStr and o["from"].s == author and
            o["to"].isStr and o["to"].s == me and o["secrets"].kind == jArr): return
    var got: seq[SecretRec]
    for i, s in o["secrets"].elems:
      if i >= MaxSecrets: break
      if s.kind != jObj or s.fields.len != 2 or s.get("k") == nil or s.get("made") == nil: return
      if not s["k"].isStr or s["made"].kind != jInt or s["made"].i < 0: return
      let k = unb64u(s["k"].s)
      if k.len != 32: return
      got.add (k, s["made"].i)
    (true, got)
  except CatchableError:
    (false, @[])

proc sharePlain*(person, sender, to: string, secrets: seq[SecretRec]): JNode =
  ## the share's plaintext: the secrets in write order (newest first), at most 16
  var a = newArr()
  for i, s in secrets:
    if i >= MaxSecrets: break
    a.elems.add newObj(@[("k", newStr(b64u(s.k))), ("made", newInt(s.made))])
  newObj(@[("person", newStr(person)), ("from", newStr(sender)), ("to", newStr(to)), ("secrets", a)])

proc saveProgress*(n: Node, course: string, data: OrderedTable[string, string], wall: int64): JNode
proc loadProgress*(n: Node, person: string): OrderedTable[string, OrderedTable[string, string]]

proc pairSteps(n: Node, wall: int64): int =
  ## §17 pairing, the steps that need no person: reveal this device's nonce once the other device's commitment is in
  ## the log (never before: a commitment made after seeing it could be chosen to make the codes match), then take
  ## its reveal when it matches the commitment revealed against.
  let mine = n.myBoxPublished
  var at = n.attempts
  var changed = false
  for (d, st) in at.fields:
    if not n.ownDevice(d) or d notin n.run.boxKeys: continue
    let theirBox = n.run.boxKeys[d]
    let commits = n.stepsFrom(d, "pair_commit")
    if st.get("theirs") == nil:
      if commits.len == 0: continue
      st["theirs"] = commits[^1]["commit"]          # the commitment this device reveals against, kept
      discard n.append("pair_reveal", newObj(@[("to", newStr(d)), ("nonce", st["nonce"])]), wall)
      inc result
      changed = true
    elif st.get("their_nonce") == nil:
      for r in n.stepsFrom(d, "pair_reveal"):
        if r["nonce"].isStr and n.p.pairCommit(d, n.device, theirBox, r["nonce"].s) == st["theirs"].s:
          st["their_nonce"] = r["nonce"]
          st["box"] = newStr(theirBox)
          st["code"] = newStr(n.p.pairCode(n.device, mine, st["nonce"].s, d, theirBox, r["nonce"].s))
          changed = true
          break
  if changed: n.store.setMeta(AttemptsMeta, toText(at))

proc progressTick*(n: Node, wall: int64): int =
  ## The §17 upkeep an app runs after each sync round and around pairing (never a server: it is nobody's own device):
  ## publish the box key, the pairing steps, take in shares from paired devices, move to a new secret when a device
  ## of the person that held the secrets was removed, and share what a paired device lacks. -> entries written
  let me = n.owner
  if me.len == 0 or n.root.len == 0 or not n.live(n.device): return 0
  let box = n.boxKey
  let boxStr = keyString(box.pub)
  if n.run.boxKeys.getOrDefault(n.device) != boxStr and n.store.getMeta(BoxWrittenMeta) != boxStr:
    discard n.append("box_key", newObj(@[("key", newStr(boxStr))]), wall)
    n.store.setMeta(BoxWrittenMeta, boxStr)
    inc result
  if n.myBoxPublished.len > 0: result += n.pairSteps(wall)
  # a removed device of this person that had been sent secrets (by anyone): drop it, and write with a new secret
  # from now on (it is denied every sync, so it never sees that one); progress is saved again under it
  var paired = n.pairedMap
  var drop: seq[string]
  for d in paired.keys:
    if not n.live(d) or n.run.devices[d]["person"].s != me: drop.add d
  for d in drop: paired.del d
  if drop.len > 0: n.setPaired(paired)
  var rotated = n.metaJson(RotatedMeta, newArr())
  var rotatedIds: seq[string]
  for x in rotated.elems: rotatedIds.add x.s
  var gone: seq[string]
  for d in n.run.shares.keys:
    if d != n.device and d in n.run.cuts and d notin rotatedIds and d in n.run.devices and
       n.run.devices[d]["person"].s == me: gone.add d
  if gone.len > 0:
    for d in gone: rotated.elems.add newStr(d)
    n.store.setMeta(RotatedMeta, toText(rotated))
    if n.secretRecs(me).len > 0:
      let all = n.loadProgress(me)
      discard n.newSecret(me, wall)
      for course, data in all:
        if data.len > 0:
          try:
            discard n.saveProgress(course, data, wall)
            inc result
          except ValueError: discard
  # shares to this device from devices it paired with (only to the box key the person confirmed)
  var taken = n.metaJson(TakenMeta, newArr())
  var takenIds: seq[string]
  for x in taken.elems: takenIds.add x.s
  var tookAny = false
  for id in n.run.shares.getOrDefault(n.device):
    if id in takenIds: continue
    let e = n.entries.getOrDefault(id)
    if e == nil or e["peer"].s notin paired: continue
    let (ok, got) = n.p.takeShare(box, e["body"]["sealed"], e["peer"].s, n.device, me)
    if ok: discard n.addSecrets(me, got)
    taken.elems.add newStr(id)
    tookAny = true
  if tookAny: n.store.setMeta(TakenMeta, toText(taken))
  # share to each paired device what it has not been sent, sealed to the box key the person confirmed
  let recs = n.secretRecs(me)
  if recs.len == 0: return
  var shas: seq[string]
  for i, r in recs:
    if i < MaxSecrets: shas.add hex(n.p.sha256(r.k))
  var sent = n.metaJson(SentMeta, newObj())
  if sent.kind != jObj: sent = newObj()
  for d, theirBox in paired:
    if n.run.boxKeys.getOrDefault(d) != theirBox: continue    # a box key the person did not compare codes with
    let prev = sent.get(d)
    var need = prev == nil or prev.kind != jObj or prev.get("box") == nil or not prev["box"].isStr or
               prev["box"].s != theirBox or prev.get("sent") == nil or prev["sent"].kind != jArr
    if not need:
      var had: seq[string]
      for x in prev["sent"].elems:
        if x.isStr: had.add x.s
      for s in shas:
        if s notin had: need = true
    if not need: continue
    let sealed = n.p.eciesSeal(theirBox, SharePurpose, canonical(sharePlain(me, n.device, d, recs)).toBytes)
    discard n.append("secret_share", newObj(@[("to", newStr(d)), ("sealed", sealed)]), wall)
    var a = newArr()
    for s in shas: a.elems.add newStr(s)
    sent[d] = newObj(@[("box", newStr(theirBox)), ("sent", a)])
    n.store.setMeta(SentMeta, toText(sent))
    inc result

proc pairingList*(n: Node): JNode =
  ## What the pairing screen shows: whether this device is ready (its box key is in the log), and the person's other
  ## devices with a box key: {device, label, state, code}. state: "paired"; "compare" (code set: the person checks
  ## both screens show it); "waiting" (this device started, the other has not answered yet); "asked" (the other
  ## device started); "none".
  result = newObj(@[("ready", newBool(false)), ("devices", newArr())])
  let me = n.owner
  if me.len == 0: return
  result["ready"] = newBool(n.myBoxPublished.len > 0)
  if not result["ready"].b: return
  let paired = n.pairedMap
  let at = n.attempts
  for d, info in n.run.devices:
    if not n.ownDevice(d) or d notin n.run.boxKeys: continue
    let st = at.get(d)
    var state = "none"
    var code = ""
    if d in paired and paired[d] == n.run.boxKeys[d]: state = "paired"
    elif st != nil and st.get("code") != nil and st.get("box") != nil and st["box"].s == n.run.boxKeys[d]:
      state = "compare"
      code = st["code"].s
    elif st != nil: state = "waiting"
    elif n.stepsFrom(d, "pair_commit").len > 0: state = "asked"
    result["devices"].elems.add newObj(@[("device", newStr(d)), ("label", info["label"]), ("state", newStr(state)),
                                         ("code", newStr(code))])

proc ownPairable(n: Node, device: string): bool =
  n.myBoxPublished.len > 0 and n.ownDevice(device) and device in n.run.boxKeys

proc startPairing*(n: Node, device: string, wall: int64) =
  ## The person pressed Pair: a fresh nonce, and its commitment in the log. Pressing again starts over.
  if n.myBoxPublished.len == 0: raise newException(ValueError, "This device is not ready to pair yet: sync first.")
  if not n.ownPairable(device): raise newException(ValueError, "That is not one of your devices that can pair.")
  let nonce = b64u(n.p.randomBytes(16))
  let mine = n.p.pairCommit(n.device, device, n.myBoxPublished, nonce)
  var at = n.attempts
  at[device] = newObj(@[("nonce", newStr(nonce)), ("mine", newStr(mine))])
  n.store.setMeta(AttemptsMeta, toText(at))
  var p = n.pairedMap
  if device in p:
    p.del device
    n.setPaired(p)
  discard n.append("pair_commit", newObj(@[("to", newStr(device)), ("commit", newStr(mine))]), wall)
  discard n.progressTick(wall)

proc confirmPairing*(n: Node, device, code: string, wall: int64) =
  ## The person checked that both screens show `code`: trust `device`, with the box key the code was made with.
  let at = n.attempts
  let st = at.get(device)
  if st == nil or st.get("code") == nil or st["code"].s != code or st.get("box") == nil or
     n.run.boxKeys.getOrDefault(device) != st["box"].s:
    raise newException(ValueError, "There is no code to confirm with that device now: press Pair again.")
  var p = n.pairedMap
  p[device] = st["box"].s
  n.setPaired(p)
  var left = newObj()
  for (k, v) in at.fields:
    if k != device: left[k] = v
  n.store.setMeta(AttemptsMeta, toText(left))
  discard n.progressTick(wall)

# ---------------------------------------------------------------- course progress

proc validCourse(c: string): bool = c.len in 1..16 and c.allCharsInSet({'a'..'z'})
proc validKey(k: string): bool = k.len in 1..64 and k.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-'})

proc progressBody*(course: string, data: OrderedTable[string, string]): JNode =
  if not validCourse(course): raise newException(ValueError, "bad course")
  if data.len == 0: raise newException(ValueError, "nothing to save")
  var keys: seq[string]
  var total = 0
  for k, v in data:
    if not validKey(k) or v.len > MaxValue: raise newException(ValueError, "bad progress value")
    total += v.len
    keys.add k
  if total > MaxTotal: raise newException(ValueError, "too much at once")
  keys.sort(system.cmp)
  var items = newArr()
  for k in keys: items.elems.add newArr(@[newStr(k), newStr(data[k])])
  newObj(@[("course", newStr(course)), ("items", items)])

proc saveProgress*(n: Node, course: string, data: OrderedTable[string, string], wall: int64): JNode =
  ## Append one private course_progress entry for this device's owner.
  let me = n.owner
  if me.len == 0: raise newException(ValueError, "this device has no person")
  let body = progressBody(course, data)
  n.append("private", n.p.privateBody(n.ensureSecret(me, wall), me, "course_progress", body), wall)

proc mergeValue*(key: string, old, new: string): string =
  ## Two localStorage strings of one key: objects → union (later wins), "…Best" numbers → larger, else the later.
  if old.len == 0: return new
  var a, b: JNode
  try:
    a = parseStrict(old)
    b = parseStrict(new)
  except JsonError:
    return new
  if a.kind == jObj and b.kind == jObj:
    var m = copy(a)
    for (k, v) in b.fields: m[k] = v
    return toText(m)
  if key.endsWith("Best") and a.isNum and b.isNum:
    return (if a.num > b.num: old else: new)
  new

proc loadProgress*(n: Node, person: string): OrderedTable[string, OrderedTable[string, string]] =
  ## {course: {key: localStorage string}} from the person's private entries this device can open.
  if n.run == nil or person notin n.run.private: return
  let keys = n.secretsOf(person)
  for id in n.run.private[person]:
    let e = n.entries.getOrDefault(id)
    if e == nil: continue
    var opened: JNode
    for k in keys:
      try:
        opened = n.p.privateOpen(k, e["body"])
        break
      except CatchableError: discard
    if opened == nil or opened.get("type") == nil or not opened["type"].isStr or opened["type"].s != "course_progress":
      continue
    let b = opened.get("body")
    if b == nil or b.kind != jObj or b.get("course") == nil or not b["course"].isStr or b.get("items") == nil or
       b["items"].kind != jArr: continue
    var data: OrderedTable[string, string]
    var ok = true
    for it in b["items"].elems:
      if it.kind != jArr or it.len != 2 or not it[0].isStr or not it[1].isStr: ok = false
      else: data[it[0].s] = it[1].s
    if not ok: continue
    try: discard progressBody(b["course"].s, data)
    except ValueError: continue
    let course = b["course"].s
    if course notin result: result[course] = initOrderedTable[string, string]()
    for k, v in data: result[course][k] = mergeValue(k, result[course].getOrDefault(k), v)
