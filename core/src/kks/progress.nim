## Person secrets and course progress (PROTOCOL-v2 §13, §17): private entries only the person's own devices can read.
## Secrets reach another device only sealed to its box key, after the person paired the two (decision 0062).

import std/[algorithm, strutils, tables]
import json, crypto, util, proto, replay, node, extras

const
  MaxValue = 200_000
  MaxTotal = 600_000
  MaxSecrets* = 16
  SharePurpose* = "kks-person-secret"
  BoxKeyMeta = "box_key"            ## this device's box key: {"scalar": hex, "pub": key string}
  BoxWrittenMeta = "box_key_written" ## the box key string this device has written a box_key entry for
  PairedMeta = "paired"             ## the devices the person paired this one with: [device ID, …]
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
  result = n.p.randomBytes(32)
  discard n.addSecrets(person, @[(result, max(wall, 0'i64))])

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

proc pairCode*(p: Provider, devA, boxA, devB, boxB: string): string =
  ## §17: the 6 digits both devices show; the two IDs sorted, each followed by its box key.
  let (x, kx, y, ky) = if devA < devB: (devA, boxA, devB, boxB) else: (devB, boxB, devA, boxA)
  let d = p.sha256(toBytes("kks-pair-code-v1\n" & x & "\n" & kx & "\n" & y & "\n" & ky))
  let v = (uint32(d[0]) shl 24) or (uint32(d[1]) shl 16) or (uint32(d[2]) shl 8) or uint32(d[3])
  align($(v mod 1_000_000), 6, '0')

proc pairedSet*(n: Node): seq[string] =
  for x in n.metaJson(PairedMeta, newArr()).elems:
    if x.kind == jStr: result.add x.s

proc setPaired(n: Node, devs: seq[string]) =
  var a = newArr()
  for d in devs: a.elems.add newStr(d)
  n.store.setMeta(PairedMeta, toText(a))

proc live(n: Node, d: string): bool = n.run != nil and d in n.run.devices and d notin n.run.cuts

proc ownDevice(n: Node, d: string): bool =
  n.live(d) and d != n.device and n.owner.len > 0 and n.run.devices[d]["person"].s == n.owner

proc myBoxPublished(n: Node): string =
  ## this device's box key as the log has it ("" until its box_key entry is in the replay)
  let (has, key) = n.heldBoxKey
  if n.run == nil or not has: return ""
  let k = keyString(key.pub)
  if n.run.boxKeys.getOrDefault(n.device) == k: k else: ""

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

proc progressTick*(n: Node, wall: int64): int =
  ## The §17 upkeep an app runs after each sync round and around pairing (never a server: it is nobody's own device):
  ## publish the box key, take in shares from paired devices, move to a new secret when a paired device was removed,
  ## and share what a paired device lacks. -> entries written
  let me = n.owner
  if me.len == 0 or n.root.len == 0 or not n.live(n.device): return 0
  let box = n.boxKey
  let boxStr = keyString(box.pub)
  if n.run.boxKeys.getOrDefault(n.device) != boxStr and n.store.getMeta(BoxWrittenMeta) != boxStr:
    discard n.append("box_key", newObj(@[("key", newStr(boxStr))]), wall)
    n.store.setMeta(BoxWrittenMeta, boxStr)
    inc result
  # a paired device removed: drop it, and write with a new secret from now on (it never sees that one)
  var paired = n.pairedSet
  var kept: seq[string]
  for d in paired:
    if n.live(d) and n.run.devices[d]["person"].s == me: kept.add d
  if kept.len != paired.len:
    n.setPaired(kept)
    if n.secretRecs(me).len > 0: discard n.newSecret(me, wall)
    paired = kept
  # shares to this device from devices it paired with
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
  # share to each paired device what it has not been sent, sealed to its current box key
  let recs = n.secretRecs(me)
  if recs.len == 0: return
  var shas: seq[string]
  for i, r in recs:
    if i < MaxSecrets: shas.add hex(n.p.sha256(r.k))
  var sent = n.metaJson(SentMeta, newObj())
  if sent.kind != jObj: sent = newObj()
  for d in paired:
    let theirBox = n.run.boxKeys.getOrDefault(d)
    if theirBox.len == 0: continue
    let prev = sent.get(d)
    var need = prev == nil or prev.kind != jObj or prev.get("box") == nil or prev["box"].s != theirBox
    if not need:
      var had: seq[string]
      for x in prev["sent"].elems: had.add x.s
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
  ## devices with a box key: {device, label, code, paired (by this device), paired_back (a share from it came)}.
  result = newObj(@[("ready", newBool(false)), ("devices", newArr())])
  let me = n.owner
  if me.len == 0: return
  let mine = n.myBoxPublished
  result["ready"] = newBool(mine.len > 0)
  if mine.len == 0: return
  let paired = n.pairedSet
  var back: seq[string]
  for id in n.run.shares.getOrDefault(n.device):
    let e = n.entries.getOrDefault(id)
    if e != nil: back.add e["peer"].s
  for d, info in n.run.devices:
    if not n.ownDevice(d) or d notin n.run.boxKeys: continue
    result["devices"].elems.add newObj(@[("device", newStr(d)), ("label", info["label"]),
      ("code", newStr(n.p.pairCode(n.device, mine, d, n.run.boxKeys[d]))), ("paired", newBool(d in paired)),
      ("paired_back", newBool(d in back))])

proc pair*(n: Node, device: string, wall: int64) =
  ## The person checked that both screens show the same code: trust `device` with this person's secrets.
  if n.myBoxPublished.len == 0: raise newException(ValueError, "This device is not ready to pair yet: sync first.")
  if not n.ownDevice(device) or device notin n.run.boxKeys:
    raise newException(ValueError, "That is not one of your devices that can pair.")
  var p = n.pairedSet
  if device notin p:
    p.add device
    n.setPaired(p)
  discard n.ensureSecret(n.owner, wall)
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
