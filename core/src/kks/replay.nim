## Protocol v2 replay (docs/PROTOCOL-v2.md §8–14, §21): identity, authority, revocation, approvals, merge, private
## entries and the v1 import. A check-for-check port of ref/replay2.py; ref/vectors/v2-replay.json and
## v2-malformed.json decide. Deterministic: the same entries in any order and the same trust anchor give the same
## state bytes.

import std/[algorithm, sets, strutils, tables, unicode]
import json, crypto, util, proto

const
  StmtDomain* = "kks-root-v2\n"
  PrivateDomain* = "kks-private-v2\n"
  MaxRounds = 8

type
  Ignore* = object of CatchableError   ## a valid entry that changes nothing; msg = the reason code (§11)

  Decision = object
    verdict: string
    manager: bool
    edit: JNode        ## nil = None
    note: string
    person: string
    eid: string

  Revoke = object
    rank: int
    hlc0, hlc1: int64
    peer: string
    seq: int64
    eid: string
    device: string
    last: int64

  Owner* = tuple[manager: bool, by: string]   ## by "" = None

  Run* = ref object
    root*: string
    cuts*: Table[string, int64]
    accepted: HashSet[string]
    hasAccepted: bool
    ids: Table[pointer, string]
    manager*: string                ## "" = None
    backupKey*: string              ## "" = None
    imported*: string               ## "" = None
    persons*: OrderedTable[string, JNode]    ## {username, full_name, position, role}
    devices*: OrderedTable[string, JNode]    ## {person, label}
    settings*: OrderedTable[string, JNode]
    equipment*: OrderedTable[string, JNode]  ## kks -> {field: value}
    eqBy*: Table[string, Owner]              ## kks & "\0" & field
    reviews*: OrderedTable[string, JNode]
    reviewBy*: Table[string, Owner]
    links*: HashSet[(string, int64, string)]
    photos*: OrderedTable[string, JNode]
    tags*: OrderedTable[string, JNode]
    proposals*: OrderedTable[string, string]
    pending: Table[string, JNode]
    waiting: Table[string, seq[Decision]]
    votes*: OrderedTable[string, HashSet[string]]
    authors*: Table[string, string]
    conflicts*: seq[JNode]
    private*: OrderedTable[string, seq[string]]
    reports*: OrderedTable[string, seq[string]]   ## device → report entry IDs (§13a)
    ignored*: OrderedTable[string, string]
    revokes: seq[Revoke]
    decisions*: OrderedTable[string, JNode]
    history*: seq[JNode]
    comments*: OrderedTable[string, seq[JNode]]
    at: string

proc ign(code: string) {.noreturn.} = raise newException(Ignore, code)
proc need(c: bool, code = "bad_body") =
  if not c: ign(code)

# ---------------------------------------------------------------- value rules

proc allIn(s: string, cs: set[char]): bool =
  for c in s:
    if c notin cs: return false
  true

const
  Hex = {'0'..'9', 'a'..'f'}
  B64 = {'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}
  Upper = {'A'..'Z'}
  Dig = {'0'..'9'}

proc sOf(n: JNode): (bool, string) = (if n != nil and n.kind == jStr: (true, n.s) else: (false, ""))

proc isId(n: JNode): bool = (let (ok, s) = sOf(n); ok and s.len == 32 and allIn(s, Hex))
proc isHex64n(n: JNode): bool = (let (ok, s) = sOf(n); ok and isHex64(s))
proc isPeerN(n: JNode): bool = (let (ok, s) = sOf(n); ok and isPeer(s))
proc isB64u(n: JNode): bool = (let (ok, s) = sOf(n); ok and allIn(s, B64))
proc isUser(n: JNode): bool =
  let (ok, s) = sOf(n)
  ok and s.len in 2..40 and allIn(s, {'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '@', '-'})
proc isKks(n: JNode): bool = (let (ok, s) = sOf(n); ok and s.len in 3..24 and allIn(s, {'0'..'9', 'A'..'Z', '/'}))
proc isCode(n: JNode): bool =
  let (ok, s) = sOf(n)
  if not ok or s.len != 12: return false
  for i, c in s:
    let want = if i in {0, 1, 5, 6, 9, 10, 11}: Dig else: Upper
    if c notin want: return false
  true
proc isSuffix(n: JNode): bool = (let (ok, s) = sOf(n); ok and s.len <= 4 and allIn(s, {'A'..'Z', '0'..'9'}))
proc isIsa(n: JNode): bool = (let (ok, s) = sOf(n); ok and s.len in 1..6 and allIn(s, Upper))
proc isSheet(n: JNode): bool =
  let (ok, s) = sOf(n)
  ok and s.len in 1..24 and s[0] in {'a'..'z', '0'..'9'} and allIn(s, {'a'..'z', '0'..'9', '-'})
proc isTagId(n: JNode): bool =
  let (ok, s) = sOf(n)
  ok and s.len in 1..64 and allIn(s, {'A'..'Z', 'a'..'z', '0'..'9', ':', '_', '.', '-'})
proc isKeyName(n: JNode): bool = (let (ok, s) = sOf(n); ok and keyOk(s))
proc isText(n: JNode, lo = 0, hi = 4000): bool =
  ## Length in code points, as Python's len().
  let (ok, s) = sOf(n)
  ok and s.runeLen in lo..hi
proc isInt(n: JNode): bool = n != nil and n.kind == jInt
proc isBool(n: JNode): bool = n != nil and n.kind == jBool
proc isObj(n: JNode): bool = n != nil and n.kind == jObj
proc isArr(n: JNode): bool = n != nil and n.kind == jArr

proc keysAre(obj: JNode, keys: openArray[string]) =
  need(isObj(obj) and obj.len == keys.len)
  for k in keys: need(obj.has(k))

proc pyEq*(a, b: JNode): bool =
  ## Python's == on JSON values: True == 1 and False == 0; dicts ignore key order.
  let an = a == nil or a.kind == jNull
  let bn = b == nil or b.kind == jNull
  if an or bn: return an and bn
  if a.kind in {jBool, jInt} and b.kind in {jBool, jInt}:
    let x = if a.kind == jBool: int64(a.b) else: a.i
    let y = if b.kind == jBool: int64(b.b) else: b.i
    return x == y
  if a.kind != b.kind: return false
  case a.kind
  of jStr: a.s == b.s
  of jArr:
    if a.len != b.len: return false
    for i in 0 ..< a.len:
      if not pyEq(a[i], b[i]): return false
    true
  of jObj:
    if a.len != b.len: return false
    for (k, v) in a.fields:
      let w = b.get(k)
      if w == nil or not pyEq(v, w): return false
    true
  else: a == b

# ---------------------------------------------------------------- §8 root statements, §13 private entries

proc stmtKeys(kind: string): seq[string] =
  case kind
  of "manager": @["kind", "person"]
  of "device": @["kind", "device", "person"]
  of "rotate": @["kind", "root"]
  of "revoke": @["kind", "device", "last_seq"]
  of "backup_key": @["kind", "key"]
  of "import": @["kind", "v1", "state"]
  else: @[]

proc signStatement*(p: Provider, rootKey: PrivateKey, stmt: JNode): string =
  p.sign(rootKey, StmtDomain & canon(stmt))

proc checkStatement(p: Provider, rootPub: string, stmt, sig: JNode) =
  let k = if isObj(stmt): stmt.get("kind") else: nil
  need(k != nil and k.kind == jStr and stmtKeys(k.s).len > 0)
  keysAre(stmt, stmtKeys(k.s))
  var data: string
  try: data = StmtDomain & canon(stmt)
  except ProtocolError: ign("bad_body")
  need(sig.isStr and p.verify(rootPub, data, sig.s), "bad_root_sig")

proc privateBody*(p: Provider, secret: openArray[byte], person, typ: string, body: JNode,
                  nonce: seq[byte] = @[]): JNode =
  let n = if nonce.len == 0: p.randomBytes(12) else: nonce
  let pt = canon(newObj(@[("type", newStr(typ)), ("body", body)]))
  let ct = p.aesGcmSeal(secret, n, pt.toBytes, toBytes(PrivateDomain & person))
  newObj(@[("person", newStr(person)), ("nonce", newStr(b64u(n))), ("ct", newStr(b64u(ct)))])

proc privateOpen*(p: Provider, secret: openArray[byte], body: JNode): JNode =
  let pt = p.aesGcmOpen(secret, unb64u(body["nonce"].s), unb64u(body["ct"].s),
                        toBytes(PrivateDomain & body["person"].s))
  parseStrict(pt.toStr)

# ---------------------------------------------------------------- §3–4 chains across devices

type Chains = object
  usable: seq[(string, JNode)]       ## (entry id, entry)
  ignored: OrderedTable[string, string]
  forks: Table[string, int64]

proc chains(p: Provider, entries: seq[JNode], trusted: seq[(string, JNode)], useTrusted: bool): Chains =
  var byPeer: OrderedTable[string, OrderedTable[int64, OrderedTable[string, JNode]]]
  proc put(peer: string, seq: int64, eid: string, e: JNode) =
    discard byPeer.hasKeyOrPut(peer, initOrderedTable[int64, OrderedTable[string, JNode]]())
    discard byPeer[peer].hasKeyOrPut(seq, initOrderedTable[string, JNode]())
    byPeer[peer][seq][eid] = e
  if useTrusted:
    for (eid, e) in trusted: put(e["peer"].s, e["seq"].i, eid, e)
  else:
    var staged: seq[(string, JNode)]
    for e in entries:
      try:
        checkFields(e)
        staged.add((p.entryId(e), e))
      except ProtocolError as err:
        if e != nil and e.kind == jObj:
          try: result.ignored[p.entryId(e)] = err.code
          except ProtocolError: discard      # can't even be hashed: nothing to report it under
    var firsts: OrderedTable[string, OrderedTable[string, JNode]]
    var bad: OrderedTable[string, string]
    for (eid, e) in staged:
      if e["seq"].i == 1:
        try:
          p.verifyEntry(e)
          discard firsts.hasKeyOrPut(e["peer"].s, initOrderedTable[string, JNode]())
          firsts[e["peer"].s][eid] = e
        except ProtocolError as err:
          if eid notin bad: bad[eid] = err.code
    for (eid, e) in staged:
      if e["seq"].i == 1: continue
      let peer = e["peer"].s
      if peer notin firsts or firsts[peer].len == 0:
        if eid notin bad: bad[eid] = "chain_gap"
        continue
      if firsts[peer].len > 1:
        if eid notin bad: bad[eid] = "fork"
        continue
      var key = ""
      for _, f in firsts[peer]: key = f["key"].s
      if not p.verify(key, signedBytes(e), e["sig"].s):
        if eid notin bad: bad[eid] = "bad_sig"
        continue
      put(peer, e["seq"].i, eid, e)
    var valid: HashSet[string]
    for _, seqs in byPeer:
      for _, c in seqs:
        for eid, _ in c: valid.incl eid
    for _, f in firsts:
      for eid, _ in f: valid.incl eid
    for eid, code in bad:
      if eid notin valid: result.ignored[eid] = code
    for peer, f in firsts:
      for eid, e in f: put(peer, 1, eid, e)
  for peer, seqs in byPeer:
    var prev = ""
    var why = ""
    var maxSeq = 0'i64
    for s, _ in seqs: maxSeq = max(maxSeq, s)
    var seq = 1'i64
    while seq <= maxSeq:
      let cands = seqs.getOrDefault(seq)
      if cands.len > 1:
        result.forks[peer] = seq - 1
        why = "fork"
        break
      if cands.len == 0:
        why = "chain_gap"
        break
      var eid: string
      var e: JNode
      for k, v in cands:
        eid = k
        e = v
      let pv = if e["prev"].isNull: "" else: e["prev"].s
      if pv != prev:
        why = "chain_prev"
        break
      result.usable.add((eid, e))
      prev = eid
      inc seq
    if why.len > 0:
      for s, cands in seqs:
        for eid, _ in cands:
          if s >= seq: result.ignored[eid] = why

# ---------------------------------------------------------------- §10–12 one pass in total order

proc newRun(root: string, cuts: Table[string, int64], ids: Table[pointer, string]): Run =
  Run(root: root, cuts: cuts, ids: ids)

proc role*(r: Run, person: string): string =
  if person.len > 0 and person == r.manager: return "manager"
  if person in r.persons: return r.persons[person]["role"].s
  ""

proc rank(role: string): int =
  case role
  of "root": 0
  of "manager": 1
  of "admin": 2
  else: 3

proc checkEqField(f: string, v: JNode) =
  need(f in ["area", "floor", "elev", "near", "loc", "notes", "custom"])
  if f == "custom":
    need(isArr(v) and v.len <= 100)
    for x in v.elems:
      keysAre(x, ["k", "v"])
      need(isText(x["k"], 0, 200) and isText(x["v"], 0, 2000))
  else:
    need(isText(v))

proc checkData*(t: string, b: JNode) =
  ## Body rules for the data types (§9a).
  case t
  of "equipment":
    need(isKks(b["kks"]) and isObj(b["changes"]) and b["changes"].len > 0 and isObj(b["base"]))
    for d in [b["changes"], b["base"]]:
      for (f, v) in d.fields: checkEqField(f, v)
  of "review":
    need(isTagId(b["tag_id"]) and (b["data"].isNull or isObj(b["data"])) and (b["base"].isNull or isObj(b["base"])))
  of "link":
    need(isText(b["proc"], 1, 32) and isInt(b["step"]) and b["step"].i >= 0)
    need(isKks(b["kks"]) and isBool(b["on"]))
  of "photo":
    need(isId(b["photo"]) and isHex64n(b["blob"]))
    need(isKks(b["kks"]) and isText(b["caption"], 0, 500))
  of "photo_delete": need(isId(b["photo"]))
  of "tag_remove": need(isId(b["tag"]))
  of "tag_add":
    need(isId(b["tag"]) and isSheet(b["sheet"]))
    let bb = b["bbox"]
    need(isArr(bb) and bb.len == 4 and isInt(bb[0]) and isInt(bb[1]) and isInt(bb[2]) and isInt(bb[3]))
    need(0 <= bb[0].i and bb[0].i < bb[2].i and bb[2].i <= 200000 and 0 <= bb[1].i and bb[1].i < bb[3].i and
         bb[3].i <= 200000)
    need(b["kks"].isNull or isCode(b["kks"]))
    need(isSuffix(b["suffix"]) and (b["isa"].isNull or isIsa(b["isa"])))
    need(isText(b["note"], 0, 500))
  else: discard

proc personFields(b: JNode) =
  need(isId(b["person"]) and isUser(b["username"]))
  need(isText(b["full_name"], 2, 80) and (b["position"].isNull or isText(b["position"], 0, 80)))

proc pairs(v: JNode): seq[JNode] =
  ## §21 pair form: [key, value] lists, string keys sorted by code point, no key twice.
  need(isArr(v))
  var keys: seq[string]
  for x in v.elems:
    need(isArr(x) and x.len == 2 and x[0].isStr)
    keys.add x[0].s
  for i in 1 ..< keys.len: need(keys[i - 1] < keys[i])
  v.elems

proc linkCmp(a, b: JNode): int =
  result = cmp(a[0].s, b[0].s)
  if result == 0: result = cmp(a[1].i, b[1].i)
  if result == 0: result = cmp(a[2].s, b[2].s)

proc checkImport(st, m: JNode) =
  var names: HashSet[string]
  for pr in pairs(st["persons"]):
    let pid = pr[0]
    let pp = pr[1]
    need(isId(pid))
    keysAre(pp, ["username", "full_name", "position", "role"])
    need(pp["role"].isStr and pp["role"].s in ["user", "admin"])
    if pid.s == m["person"].s: continue    # the genesis values replace the imported ones for the manager
    personFields(newObj(@[("person", pid), ("username", pp["username"]), ("full_name", pp["full_name"]),
                        ("position", pp["position"])]))
    let low = pp["username"].s.toLowerAscii
    need(low notin names and low != m["username"].s.toLowerAscii)
    names.incl low
  for pr in pairs(st["settings"]): need(isKeyName(pr[0]) and pr[0].s != "plant")
  for pr in pairs(st["equipment"]):
    need(isKks(pr[0]) and isObj(pr[1]) and pr[1].len > 0)
    for (f, v) in pr[1].fields:
      checkEqField(f, v)
      need(not pyEq(v, newStr("")) and not pyEq(v, newArr()))
  for pr in pairs(st["reviews"]): need(isTagId(pr[0]) and isObj(pr[1]))
  need(isArr(st["links"]))
  for x in st["links"].elems:
    need(isArr(x) and x.len == 3)
    checkData("link", newObj(@[("proc", x[0]), ("step", x[1]), ("kks", x[2]), ("on", newBool(true))]))
  let links = st["links"].elems
  for i in 1 ..< links.len: need(linkCmp(links[i - 1], links[i]) < 0)   # sorted and no duplicates
  for pr in pairs(st["photos"]):
    keysAre(pr[1], ["kks", "blob", "caption"])
    checkData("photo", newObj(@[("photo", pr[0]), ("kks", pr[1]["kks"]), ("blob", pr[1]["blob"]),
                             ("caption", pr[1]["caption"])]))
  for pr in pairs(st["added_tags"]):
    let t = pr[1]
    keysAre(t, ["sheet", "bbox", "kks", "suffix", "isa", "note"])
    var b = newObj(@[("tag", pr[0])])
    for (k, v) in t.fields: b.fields.add((k, v))
    checkData("tag_add", b)

proc subset(obj: JNode, keys: openArray[string]): JNode =
  result = newObj()
  for k in keys: result.fields.add((k, obj[k]))

proc applyImport(r: Run, st: JNode) =
  for pr in st["persons"].elems: r.persons[pr[0].s] = subset(pr[1], ["username", "full_name", "position", "role"])
  for pr in st["settings"].elems: r.settings[pr[0].s] = pr[1]
  for pr in st["equipment"].elems: r.equipment[pr[0].s] = copy(pr[1])
  for pr in st["reviews"].elems: r.reviews[pr[0].s] = pr[1]
  for x in st["links"].elems: r.links.incl((x[0].s, x[1].i, x[2].s))
  for pr in st["photos"].elems: r.photos[pr[0].s] = subset(pr[1], ["kks", "blob", "caption"])
  for pr in st["added_tags"].elems:
    r.tags[pr[0].s] = subset(pr[1], ["sheet", "bbox", "kks", "suffix", "isa", "note"])

proc doImport(p: Provider, r: Run, imp, m: JNode): JNode =
  ## §21: validate the genesis import; any problem is bad_genesis.
  try:
    keysAre(imp, ["stmt", "root_sig", "state"])
    let stmt = imp["stmt"]
    let st = imp["state"]
    need(isObj(stmt) and stmt.get("kind") != nil and pyEq(stmt.get("kind"), newStr("import")))
    keysAre(stmt, stmtKeys("import"))
    need(isHex64n(stmt["v1"]) and isHex64n(stmt["state"]))
    keysAre(st, ["persons", "settings", "equipment", "reviews", "links", "photos", "added_tags"])
    need(hex(p.sha256(canon(st).toBytes)) == stmt["state"].s)
    checkImport(st, m)
  except Ignore, ProtocolError, KeyError:
    ign("bad_genesis")
  p.checkStatement(r.root, imp["stmt"], imp["root_sig"])
  imp

type Ctx = object
  p: Provider

proc genesis(c: Ctx, r: Run, e: JNode) =
  let b = e["body"]
  need(r.manager.len == 0, "second_genesis")
  keysAre(b, ["plant", "root", "manager", "stmt_manager", "stmt_device", "sig_manager", "sig_device", "import"])
  need(isText(b["plant"], 1, 80))
  need(b["root"].isStr and b["root"].s == r.root, "bad_genesis")
  let m = b["manager"]
  keysAre(m, ["person", "username", "full_name", "position"])
  personFields(m)
  need(pyEq(b["stmt_manager"], newObj(@[("kind", newStr("manager")), ("person", m["person"])])), "bad_genesis")
  need(pyEq(b["stmt_device"], newObj(@[("kind", newStr("device")), ("device", e["peer"]), ("person", m["person"])])),
       "bad_genesis")
  c.p.checkStatement(r.root, b["stmt_manager"], b["sig_manager"])
  c.p.checkStatement(r.root, b["stmt_device"], b["sig_device"])
  if not b["import"].isNull:
    let imp = c.p.doImport(r, b["import"], m)
    r.applyImport(imp["state"])
    r.imported = imp["stmt"]["v1"].s
  r.persons[m["person"].s] = newObj(@[("username", m["username"]), ("full_name", m["full_name"]),
                                    ("position", m["position"]), ("role", newStr("admin"))])
  r.manager = m["person"].s
  r.devices[e["peer"].s] = newObj(@[("person", m["person"]), ("label", newStr(""))])
  r.settings["plant"] = b["plant"]

proc addRevoke(r: Run, rk: int, e: JNode, eid, device: string, last: int64) =
  r.revokes.add Revoke(rank: rk, hlc0: e["hlc"][0].i, hlc1: e["hlc"][1].i, peer: e["peer"].s, seq: e["seq"].i,
                       eid: eid, device: device, last: last)
  if r.hasAccepted and eid notin r.accepted: ign("overridden")

proc validKeyStr(c: Ctx, n: JNode): bool =
  if not n.isStr: return false
  try:
    discard c.p.publicKey(n.s)
    true
  except ValueError:
    false

proc tRoot(c: Ctx, r: Run, e: JNode, eid, author, role: string) =
  let stmt = e["body"]["stmt"]
  need(isObj(stmt) and not pyEq(stmt.get("kind"), newStr("import")))
  c.p.checkStatement(r.root, stmt, e["body"]["root_sig"])
  case stmt["kind"].s
  of "manager":
    need(isId(stmt["person"]) and stmt["person"].s in r.persons)
    r.manager = stmt["person"].s
  of "device":
    need(isPeerN(stmt["device"]) and isId(stmt["person"]) and stmt["person"].s in r.persons)
    let dev = stmt["device"].s
    need(dev notin r.devices or r.devices[dev]["person"].s == stmt["person"].s, "not_allowed")
    if dev notin r.devices: r.devices[dev] = newObj(@[("person", stmt["person"]), ("label", newStr(""))])
  of "rotate":
    need(c.validKeyStr(stmt["root"]))
    r.root = stmt["root"].s
  of "backup_key":
    need(c.validKeyStr(stmt["key"]))
    r.backupKey = stmt["key"].s
  else:   # revoke
    need(isPeerN(stmt["device"]) and isInt(stmt["last_seq"]) and stmt["last_seq"].i >= 0)
    r.addRevoke(rank("root"), e, eid, stmt["device"].s, stmt["last_seq"].i)

proc tPerson(r: Run, e: JNode, author, role: string) =
  let b = e["body"]
  personFields(b)
  need(b["role"].isStr and b["role"].s in ["user", "admin"])
  let pid = b["person"].s
  if pid notin r.persons:
    need(role == "manager" or (role == "admin" and b["role"].s == "user"), "not_allowed")
    for _, pp in r.persons: need(pp["username"].s.toLowerAscii != b["username"].s.toLowerAscii, "username_taken")
    r.persons[pid] = subset(b, ["username", "full_name", "position", "role"])
    return
  let cur = r.persons[pid]
  need(b["username"].s == cur["username"].s)
  if author == pid:
    need(b["role"].s == cur["role"].s, "not_allowed")
  else:
    let target = r.role(pid)
    need(target != "manager", "not_allowed")
    need(role == "manager" or (role == "admin" and target == "user" and b["role"].s == "user"), "not_allowed")
  cur["full_name"] = b["full_name"]
  cur["position"] = b["position"]
  cur["role"] = b["role"]

proc tDeviceCert(r: Run, e: JNode, author, role: string) =
  let b = e["body"]
  need(isPeerN(b["device"]) and isId(b["person"]) and b["person"].s in r.persons and isText(b["label"], 0, 80))
  let dev = b["device"].s
  need(dev notin r.devices or r.devices[dev]["person"].s == b["person"].s, "not_allowed")
  need(role == "manager" or author == b["person"].s or (role == "admin" and r.role(b["person"].s) == "user"),
       "not_allowed")
  r.devices[dev] = newObj(@[("person", b["person"]), ("label", b["label"])])

proc tRevoke(r: Run, e: JNode, eid, author, role: string) =
  let b = e["body"]
  let target = if isPeerN(b["device"]): r.devices.getOrDefault(b["device"].s) else: nil
  need(target != nil and isInt(b["last_seq"]) and b["last_seq"].i >= 0)
  need(role == "manager" or author == target["person"].s or (role == "admin" and r.role(target["person"].s) == "user"),
       "not_allowed")
  r.addRevoke(rank(role), e, eid, b["device"].s, b["last_seq"].i)

# ----- §12 merge and apply

proc merge(r: Run, entity, key: string, field: JNode, live, base, new: JNode, owner: Owner, by: string,
           byManager: bool): bool =
  if pyEq(live, base) or pyEq(live, new): return true
  let ownerBy = if owner.by.len == 0: newNull() else: newStr(owner.by)
  if owner.manager and not byManager:
    r.conflicts.add newObj(@[("entity", newStr(entity)), ("key", newStr(key)), ("field", field), ("kept", live),
                           ("lost", new), ("kept_by", ownerBy), ("lost_by", newStr(by))])
    return false
  r.conflicts.add newObj(@[("entity", newStr(entity)), ("key", newStr(key)), ("field", field), ("kept", new),
                         ("lost", live), ("kept_by", newStr(by)), ("lost_by", ownerBy)])
  true

proc entityKey(t: string, b: JNode): (string, JNode) =
  case t
  of "equipment": ("equipment", b.get("kks"))
  of "review": ("review", b.get("tag_id"))
  of "link": ("link", newArr(@[b.get("proc"), b.get("step"), b.get("kks")]))
  of "photo", "photo_delete": ("photo", b.get("photo"))
  else: ("added_tag", b.get("tag"))

proc getEntity*(r: Run, entity: string, key: JNode): JNode =
  case entity
  of "equipment": (if key.s in r.equipment and r.equipment[key.s].len > 0: copy(r.equipment[key.s]) else: nil)
  of "review": r.reviews.getOrDefault(key.s)
  of "link": (if (key[0].s, key[1].i, key[2].s) in r.links: newBool(true) else: nil)
  of "photo": r.photos.getOrDefault(key.s)
  else: r.tags.getOrDefault(key.s)

proc applyData(r: Run, t: string, b: JNode, by: string, byManager: bool) =
  case t
  of "equipment":
    let k = b["kks"].s
    if k notin r.equipment: r.equipment[k] = newObj()
    let cur = r.equipment[k]
    var fields: seq[string]
    for (f, _) in b["changes"].fields: fields.add f
    fields.sort(system.cmp)
    for f in fields:
      let v = b["changes"][f]
      let empty = if f == "custom": newArr() else: newStr("")
      let live = if cur.has(f): cur[f] else: empty
      let base = if b["base"].has(f): b["base"][f] else: empty
      if r.merge("equipment", k, newStr(f), live, base, v, r.eqBy.getOrDefault(k & "\0" & f, (false, "")), by,
                 byManager):
        if pyEq(v, empty): cur.del(f)
        else: cur[f] = v
        r.eqBy[k & "\0" & f] = (byManager, by)
    if cur.len == 0: r.equipment.del(k)
  of "review":
    let k = b["tag_id"].s
    if r.merge("review", k, newNull(), r.reviews.getOrDefault(k), b["base"], b["data"],
               r.reviewBy.getOrDefault(k, (false, "")), by, byManager):
      if b["data"].isNull: r.reviews.del(k)
      else: r.reviews[k] = b["data"]
      r.reviewBy[k] = (byManager, by)
  of "link":
    let item = (b["proc"].s, b["step"].i, b["kks"].s)
    if b["on"].b: r.links.incl item
    else: r.links.excl item
  of "photo": r.photos[b["photo"].s] = subset(b, ["kks", "blob", "caption"])
  of "photo_delete": r.photos.del(b["photo"].s)
  of "tag_add": r.tags[b["tag"].s] = subset(b, ["sheet", "bbox", "kks", "suffix", "isa", "note"])
  of "tag_remove": r.tags.del(b["tag"].s)
  else: discard

proc apply(r: Run, t: string, b: JNode, by: string, byManager: bool) =
  let (entity, key) = entityKey(t, b)
  let before = r.getEntity(entity, key)
  r.applyData(t, b, by, byManager)
  let after = r.getEntity(entity, key)
  if not pyEq(before, after):
    r.history.add newObj(@[("at", newStr(r.at)), ("source", newStr(by)), ("entity", newStr(entity)), ("key", key),
                         ("before", if before == nil: newNull() else: copy(before)),
                         ("after", if after == nil: newNull() else: copy(after))])

proc decide(r: Run, target: string, d: Decision) =
  let e = r.pending[target]
  r.pending.del(target)
  var body = e["body"]
  var verdict = d.verdict
  if d.edit != nil:
    body = copy(body)
    for (k, v) in d.edit.fields: body[k] = v
    try:
      need(e["type"].s == "tag_add")
      checkData("tag_add", body)
    except Ignore:
      verdict = "rejected"
  r.proposals[target] = verdict
  r.decisions[target] = newObj(@[("status", newStr(verdict)), ("by", newStr(d.eid)), ("note", newStr(d.note))])
  if verdict == "approved": r.apply(e["type"].s, body, target, d.manager)

proc tData(r: Run, e: JNode, eid, author, role: string) =
  checkData(e["type"].s, e["body"])
  if role in ["admin", "manager"]:
    r.apply(e["type"].s, e["body"], eid, role == "manager")
    return
  r.proposals[eid] = "pending"
  r.pending[eid] = e
  r.authors[eid] = author
  var ws: seq[Decision]
  if r.waiting.pop(eid, ws):
    for d in ws:
      try:
        need(r.proposals[eid] == "pending", "already_decided")
        need(d.verdict != "withdrawn" or d.person == author, "not_allowed")
        r.decide(eid, d)
      except Ignore as why:
        r.ignored[d.eid] = why.msg

proc decision(r: Run, e: JNode, eid: string, d0: Decision, role: string) =
  var d = d0
  let target = e["body"]["entry"]
  need(isHex64n(target))
  if d.verdict != "withdrawn": need(role in ["admin", "manager"], "not_allowed")
  d.eid = eid
  let t = target.s
  if t notin r.proposals:
    r.waiting.mgetOrPut(t, @[]).add d
    return
  need(r.proposals[t] == "pending", "already_decided")
  need(d.verdict != "withdrawn" or d.person == r.authors[t], "not_allowed")
  r.decide(t, d)

proc tApprove(r: Run, e: JNode, eid, author, role: string) =
  let edit = e["body"]["edit"]
  if not edit.isNull: keysAre(edit, ["kks", "suffix", "isa"])
  r.decision(e, eid, Decision(verdict: "approved", manager: role == "manager",
                              edit: (if edit.isNull: nil else: edit)), role)

proc tReject(r: Run, e: JNode, eid, author, role: string) =
  need(isText(e["body"]["note"], 0, 500))
  r.decision(e, eid, Decision(verdict: "rejected", manager: role == "manager", note: e["body"]["note"].s), role)

proc tWithdraw(r: Run, e: JNode, eid, author: string) =
  r.decision(e, eid, Decision(verdict: "withdrawn", person: author), "")

proc tVote(r: Run, e: JNode, author: string) =
  need(isHex64n(e["body"]["entry"]) and isBool(e["body"]["on"]))
  let t = e["body"]["entry"].s
  if t notin r.votes: r.votes[t] = initHashSet[string]()
  if e["body"]["on"].b: r.votes[t].incl author
  else: r.votes[t].excl author

proc tComment(r: Run, e: JNode, eid, author: string) =
  need(isHex64n(e["body"]["entry"]) and isText(e["body"]["text"], 1, 500))
  r.comments.mgetOrPut(e["body"]["entry"].s, @[]).add newObj(@[("person", newStr(author)), ("text", e["body"]["text"]),
                                                             ("id", newStr(eid))])

proc tSetting(r: Run, e: JNode, role: string) =
  need(isKeyName(e["body"]["key"]))
  need(role == "manager", "not_allowed")
  r.settings[e["body"]["key"].s] = e["body"]["value"]

proc tPrivate(r: Run, e: JNode, eid, author: string) =
  let b = e["body"]
  need(isB64u(b["nonce"]) and b["nonce"].s.len == 16)
  need(isB64u(b["ct"]) and b["ct"].s.len in 22..1_400_000)
  need(b["person"].isStr and b["person"].s == author, "not_allowed")
  r.private.mgetOrPut(author, @[]).add eid

proc tReport(r: Run, e: JNode, eid: string) =
  ## §13a: a diagnostics report sealed to the manager's report key; any certified device; kept opaquely by device
  let s = e["body"]["sealed"]
  need(s.kind == jObj)
  keysAre(s, ["v", "purpose", "epk", "nonce", "ct"])
  need(s["v"].kind == jInt and s["v"].i == 2 and s["purpose"].isStr and s["purpose"].s == "kks-report")
  need(isB64u(s["epk"]) and s["epk"].s.len == 87)
  need(isB64u(s["nonce"]) and s["nonce"].s.len == 16)
  need(isB64u(s["ct"]) and s["ct"].s.len in 22..65_536)
  r.reports.mgetOrPut(e["peer"].s, @[]).add eid

proc bodyKeys(t: string): seq[string] =
  case t
  of "genesis": @["plant", "root", "manager", "stmt_manager", "stmt_device", "sig_manager", "sig_device", "import"]
  of "root": @["stmt", "root_sig"]
  of "person": @["person", "username", "full_name", "position", "role"]
  of "device_cert": @["device", "person", "label"]
  of "revoke": @["device", "last_seq"]
  of "setting": @["key", "value"]
  of "equipment": @["kks", "changes", "base"]
  of "review": @["tag_id", "data", "base"]
  of "link": @["proc", "step", "kks", "on"]
  of "photo": @["photo", "kks", "blob", "caption"]
  of "photo_delete": @["photo"]
  of "tag_add": @["tag", "sheet", "bbox", "kks", "suffix", "isa", "note"]
  of "tag_remove": @["tag"]
  of "approve": @["entry", "edit"]
  of "reject": @["entry", "note"]
  of "withdraw": @["entry"]
  of "vote": @["entry", "on"]
  of "comment": @["entry", "text"]
  of "private": @["person", "nonce", "ct"]
  of "report": @["sealed"]
  else: @[]

proc run(c: Ctx, r: Run, ordered: seq[(string, JNode)]): Run =
  for (eid, e) in ordered:
    try:
      if e["seq"].i > r.cuts.getOrDefault(e["peer"].s, MaxInt53): ign("revoked")
      let t = e["type"].s
      if t == "genesis":
        c.genesis(r, e)
        continue
      need(e["peer"].s in r.devices, "not_certified")
      let keys = bodyKeys(t)
      need(keys.len > 0, "unknown_type")
      keysAre(e["body"], keys)
      r.at = eid
      let author = r.devices[e["peer"].s]["person"].s
      let role = r.role(author)
      case t
      of "root": c.tRoot(r, e, eid, author, role)
      of "person": r.tPerson(e, author, role)
      of "device_cert": r.tDeviceCert(e, author, role)
      of "revoke": r.tRevoke(e, eid, author, role)
      of "setting": r.tSetting(e, role)
      of "private": r.tPrivate(e, eid, author)
      of "report": r.tReport(e, eid)
      of "approve": r.tApprove(e, eid, author, role)
      of "reject": r.tReject(e, eid, author, role)
      of "withdraw": r.tWithdraw(e, eid, author)
      of "vote": r.tVote(e, author)
      of "comment": r.tComment(e, eid, author)
      else: r.tData(e, eid, author, role)
    except Ignore as why:
      r.ignored[eid] = why.msg
    except KeyError, ProtocolError, ValueError:
      r.ignored[eid] = "bad_body"     # the reference's safety net for bodies no rule anticipated
  r

# ---------------------------------------------------------------- §10 revocation cuts, then the final pass

proc revokeCmp(a, b: Revoke): int =
  result = cmp(a.rank, b.rank)
  if result == 0: result = cmp(a.hlc0, b.hlc0)
  if result == 0: result = cmp(a.hlc1, b.hlc1)
  if result == 0: result = cmp(a.peer, b.peer)
  if result == 0: result = cmp(a.seq, b.seq)
  if result == 0: result = cmp(a.peer, b.peer)
  if result == 0: result = cmp(a.seq, b.seq)
  if result == 0: result = cmp(a.eid, b.eid)
  if result == 0: result = cmp(a.device, b.device)
  if result == 0: result = cmp(a.last, b.last)

proc sameCuts(a, b: Table[string, int64]): bool =
  if a.len != b.len: return false
  for k, v in a:
    if k notin b or b[k] != v: return false
  true

proc computeCuts(c: Ctx, ordered: seq[(string, JNode)], root: string, forks: Table[string, int64]):
    (Table[string, int64], HashSet[string]) =
  var cuts = forks
  var accepted: HashSet[string]
  for _ in 0 ..< MaxRounds:
    let r = c.run(newRun(root, cuts, initTable[pointer, string]()), ordered)
    var nw = forks
    var acc: HashSet[string]
    var revs = r.revokes
    revs.sort(revokeCmp)
    for rv in revs:
      if rv.seq > nw.getOrDefault(rv.peer, MaxInt53): continue
      nw[rv.device] = min(rv.last, nw.getOrDefault(rv.device, rv.last))
      acc.incl rv.eid
    if sameCuts(nw, cuts) and acc == accepted: break
    cuts = nw
    accepted = acc
  (cuts, accepted)

type Replayed* = object
  run*: Run
  chainIgnored*: OrderedTable[string, string]

proc replayRun*(p: Provider, entries: seq[JNode], root: string, trusted: seq[(string, JNode)] = @[],
                useTrusted = false): Replayed =
  ## `trusted` = (entry id, entry) pairs already verified (the node's own store).
  let ch = p.chains(entries, trusted, useTrusted)
  var ordered = ch.usable
  ordered.sort(proc (a, b: (string, JNode)): int = orderCmp(a[1], b[1]))
  let c = Ctx(p: p)
  let (cuts, accepted) = c.computeCuts(ordered, root, ch.forks)
  var r = newRun(root, cuts, initTable[pointer, string]())
  r.accepted = accepted
  r.hasAccepted = true
  result.run = c.run(r, ordered)
  result.chainIgnored = ch.ignored

proc orNull(s: string): JNode = (if s.len == 0: newNull() else: newStr(s))

proc state*(r: Run): JNode =
  var persons = newObj()
  for k, v in r.persons: persons.fields.add((k, v))
  var devices = newObj()
  for d, v in r.devices:
    var x = copy(v)
    x["cut"] = if d in r.cuts: newInt(r.cuts[d]) else: newNull()
    devices.fields.add((d, x))
  var settings = newObj()
  for k, v in r.settings: settings.fields.add((k, v))
  var equipment = newObj()
  for k, v in r.equipment: equipment.fields.add((k, v))
  var reviews = newObj()
  for k, v in r.reviews: reviews.fields.add((k, v))
  var links: seq[(string, int64, string)]
  for x in r.links: links.add x
  links.sort(proc (a, b: (string, int64, string)): int =
    result = cmp(a[0], b[0])
    if result == 0: result = cmp(a[1], b[1])
    if result == 0: result = cmp(a[2], b[2]))
  var la = newArr()
  for (pr, st, kks) in links: la.elems.add newArr(@[newStr(pr), newInt(st), newStr(kks)])
  var photos = newObj()
  for k, v in r.photos: photos.fields.add((k, v))
  var tags = newObj()
  for k, v in r.tags: tags.fields.add((k, v))
  var proposals = newObj()
  for k, v in r.proposals: proposals.fields.add((k, newStr(v)))
  var votes = newObj()
  for k, v in r.votes:
    if v.len > 0 and k in r.proposals:
      var names: seq[string]
      for n in v: names.add n
      names.sort(system.cmp)
      var a = newArr()
      for n in names: a.elems.add newStr(n)
      votes.fields.add((k, a))
  var priv = newObj()
  for k, v in r.private:
    var a = newArr()
    for x in v: a.elems.add newStr(x)
    priv.fields.add((k, a))
  var ignored = newObj()
  for k, v in r.ignored: ignored.fields.add((k, newStr(v)))
  var reports = newObj()
  for k, v in r.reports:
    var a = newArr()
    for x in v: a.elems.add newStr(x)
    reports.fields.add((k, a))
  result = newObj(@[("root", newStr(r.root)), ("manager", orNull(r.manager)), ("settings", settings),
         ("backup_key", orNull(r.backupKey)), ("persons", persons), ("devices", devices), ("equipment", equipment),
         ("reviews", reviews), ("links", la), ("photos", photos), ("added_tags", tags), ("proposals", proposals),
         ("conflicts", newArr(r.conflicts)), ("votes", votes), ("private", priv), ("ignored", ignored),
         ("imported", orNull(r.imported))])
  if r.reports.len > 0: result.fields.add(("reports", reports))   # only when there are any (§14)

proc replay*(p: Provider, entries: seq[JNode], root: string): JNode =
  ## Replay `entries` (any order, any devices) from the trust anchor `root` (root key string, §2). -> state.
  let rr = p.replayRun(entries, root)
  result = rr.run.state()
  var all = rr.chainIgnored
  for k, v in rr.run.ignored: all[k] = v
  var keys: seq[string]
  for k, _ in all: keys.add k
  keys.sort(system.cmp)
  var ig = newObj()
  for k in keys: ig.fields.add((k, newStr(all[k])))
  result["ignored"] = ig

# ---------------------------------------------------------------- §14 state bytes

proc stateInto(res: var string, n: JNode) =
  case n.kind
  of jObj:
    var keys: seq[string]
    for (k, _) in n.fields:
      if k.len < 1 or k.len > 64 or not allIn(k, {'\x20'..'\x7e'}): raise perr("bad_encoding", "state key " & k)
      keys.add k
    keys.sort(system.cmp)
    res.add '{'
    for i, k in keys:
      if i > 0: res.add ','
      res.add canonical(newStr(k))
      res.add ':'
      res.stateInto(n.get(k))
    res.add '}'
  of jArr:
    res.add '['
    for i, e in n.elems:
      if i > 0: res.add ','
      res.stateInto(e)
    res.add ']'
  else: res.add canon(n)

proc stateBytes*(state: JNode): string =
  ## §14: §1 rules, except object keys may be any printable ASCII (1–64 characters).
  result.stateInto(state)
