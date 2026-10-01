## Person secrets and course progress (PROTOCOL-v2 §13, §17): private entries only the person's own devices can read.
## A port of v1's server/progress.py.

import std/[algorithm, strutils, tables]
import json, crypto, util, replay, node

const
  MaxValue = 200_000
  MaxTotal = 600_000
  MaxSwap* = 16

proc secretsKey(person: string): string = "person_secrets:" & person

proc secretsOf*(n: Node, person: string): seq[seq[byte]] =
  ## This person's secrets known here; the one to write with (lowest SHA-256 hex) first.
  let raw = n.store.getMeta(secretsKey(person))
  if raw.len == 0: return
  var withSha: seq[(string, seq[byte])]
  for x in parseStrict(raw).elems:
    let s = unb64u(x.s)
    withSha.add((hex(n.p.sha256(s)), s))
  withSha.sort(proc (a, b: (string, seq[byte])): int = cmp(a[0], b[0]))
  for (_, s) in withSha: result.add s

proc addSecrets*(n: Node, person: string, secrets: seq[seq[byte]]): int =
  var have = n.secretsOf(person)
  for s in secrets:
    if s.len == 32 and s notin have:
      have.add s
      inc result
  if result > 0:
    var a = newArr()
    for s in have: a.elems.add newStr(b64u(s))
    n.store.setMeta(secretsKey(person), toText(a))

proc ensureSecret*(n: Node, person: string): seq[byte] =
  var got = n.secretsOf(person)
  if got.len == 0:
    discard n.addSecrets(person, @[n.p.randomBytes(32)])
    got = n.secretsOf(person)
  got[0]

proc owner*(n: Node): string =
  ## The person this device belongs to ("" if not certified).
  if n.run != nil and n.device in n.run.devices: n.run.devices[n.device]["person"].s else: ""

proc secretsAnswer*(n: Node, remote: string, msg: JNode): JNode =
  ## §17, the responder: swap only between two devices of this device's own person.
  result = newObj(@[("t", newStr("secrets")), ("secrets", newArr())])
  let me = n.owner
  if me.len == 0 or n.run == nil or remote notin n.run.devices or remote in n.run.cuts: return
  if n.run.devices[remote]["person"].s != me: return
  let person = msg.get("person")
  if person == nil or person.kind != jStr or person.s != me: return
  var theirs: seq[seq[byte]]
  let lst = msg.get("secrets")
  if lst != nil and lst.kind == jArr:
    for i, x in lst.elems:
      if i >= MaxSwap: break
      if x.kind == jStr:
        try:
          let b = unb64u(x.s)
          if b.len == 32: theirs.add b
        except ValueError: discard
  discard n.addSecrets(me, theirs)
  for i, s in n.secretsOf(me):
    if i >= MaxSwap: break
    result["secrets"].elems.add newStr(b64u(s))

proc secretsRequest*(n: Node): JNode =
  ## §17, the initiator's message (after a sync with another device of the same person).
  let me = n.owner
  var a = newArr()
  for i, s in n.secretsOf(me):
    if i >= MaxSwap: break
    a.elems.add newStr(b64u(s))
  newObj(@[("t", newStr("secrets")), ("person", newStr(me)), ("secrets", a)])

proc takeSecretsAnswer*(n: Node, msg: JNode): int =
  var got: seq[seq[byte]]
  let lst = msg.get("secrets")
  if lst != nil and lst.kind == jArr:
    for i, x in lst.elems:
      if i >= MaxSwap: break
      if x.kind == jStr:
        try:
          let b = unb64u(x.s)
          if b.len == 32: got.add b
        except ValueError: discard
  n.addSecrets(n.owner, got)

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
  n.append("private", n.p.privateBody(n.ensureSecret(me), me, "course_progress", body), wall)

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
