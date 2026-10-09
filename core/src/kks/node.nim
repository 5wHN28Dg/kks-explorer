## A device's node (PROTOCOL-v2 §15 node rules): its own log, everything it holds of other devices, the replayed state,
## blobs and fork evidence. Storage comes in through `Store` (SQLite on the platforms, `MemStore` in tests); time comes
## in as arguments. The same rules as v1's server/engine.py node methods.

import std/[algorithm, sets, tables]
import json, crypto, util, proto, replay

type
  Store* = ref object of RootObj
    ## Persistence. Every method is called under the node's own lock by the platform layer.

  StoredEntry* = tuple[id: string, e: JNode]

method loadEntries*(s: Store): seq[StoredEntry] {.base.} = @[]
method putEntry*(s: Store, id: string, e: JNode) {.base.} = discard
method loadEvidence*(s: Store): seq[StoredEntry] {.base.} = @[]
method putEvidence*(s: Store, id: string, e: JNode) {.base.} = discard
method blobHas*(s: Store, sha: string): bool {.base.} = false
method blobGet*(s: Store, sha: string): string {.base.} = ""
method blobPut*(s: Store, sha, data: string) {.base.} = discard
method getMeta*(s: Store, key: string): string {.base.} = ""     ## "" = absent
method setMeta*(s: Store, key, value: string) {.base.} = discard
method subs*(s: Store): seq[JNode] {.base.} = @[]                  ## submission rows, newest first
method putSub*(s: Store, row: JNode): int64 {.base.} = 0           ## insert when row.id is null, else replace; -> id
method notes*(s: Store): seq[(string, string)] {.base.} = @[]      ## History notes: entry id → note
method putNote*(s: Store, eid, note: string) {.base.} = discard
# One transaction (Node.atomic): the writes between begin and commit reach the disk all together or not at all. A
# store refuses a begin while one is open (nesting would let an outer rollback undo writes the node already took in).
# Every store must have them: this base refuses, so a store (or a wrapper) that forgets them fails loudly instead of
# losing the all-or-nothing.
method begin*(s: Store) {.base.} = raise newException(ValueError, "this store has no transactions")
method commit*(s: Store) {.base.} = raise newException(ValueError, "this store has no transactions")
method rollback*(s: Store) {.base.} = discard   ## undoes everything since begin; no-op when nothing is open

proc blobExt*(data: string): string =
  ## A blob's file extension from its first bytes.
  if data.len >= 3 and data[0 .. 2] == "\xff\xd8\xff": "jpg"
  elif data.len >= 4 and data[0 .. 3] == "\x89PNG": "png"
  elif data.len >= 4 and data[0 .. 3] == "RIFF": "webp"
  elif data.len >= 2 and data[0 .. 1] == "\xff\x0a": "jxl"
  elif data.len >= 7 and data[0 .. 6] == "\x00\x00\x00\x0cJXL": "jxl"
  else: "bin"

type MemStore* = ref object of Store
  subRows*: seq[JNode]
  noteRows*: seq[(string, string)]
  entries*: seq[StoredEntry]
  evidence*: seq[StoredEntry]
  blobs*: Table[string, string]
  meta*: Table[string, string]
  saved: MemStore                       ## the state at begin (a shallow copy: rows are replaced, never changed)

proc newMemStore*(): MemStore = MemStore()
method loadEntries*(s: MemStore): seq[StoredEntry] = s.entries
method putEntry*(s: MemStore, id: string, e: JNode) = s.entries.add((id, e))
method loadEvidence*(s: MemStore): seq[StoredEntry] = s.evidence
method putEvidence*(s: MemStore, id: string, e: JNode) = s.evidence.add((id, e))
method blobHas*(s: MemStore, sha: string): bool = sha in s.blobs
method blobGet*(s: MemStore, sha: string): string = s.blobs.getOrDefault(sha)
method blobPut*(s: MemStore, sha, data: string) = s.blobs[sha] = data
method getMeta*(s: MemStore, key: string): string = s.meta.getOrDefault(key)
method setMeta*(s: MemStore, key, value: string) = s.meta[key] = value
method subs*(s: MemStore): seq[JNode] =
  for i in countdown(s.subRows.high, 0): result.add s.subRows[i]
method putSub*(s: MemStore, row: JNode): int64 =
  if row["id"].isNull:
    result = int64(s.subRows.len + 1)
    row["id"] = newInt(result)
    s.subRows.add row
  else:
    result = row["id"].i
    s.subRows[result - 1] = row
method notes*(s: MemStore): seq[(string, string)] = s.noteRows
method putNote*(s: MemStore, eid, note: string) =
  for x in s.noteRows.mitems:
    if x[0] == eid:
      x[1] = note
      return
  s.noteRows.add((eid, note))
method begin*(s: MemStore) =
  if s.saved != nil: raise newException(ValueError, "a store transaction is already open")
  s.saved = MemStore(subRows: s.subRows, noteRows: s.noteRows, entries: s.entries, evidence: s.evidence,
                     blobs: s.blobs, meta: s.meta)
method commit*(s: MemStore) =
  if s.saved == nil: raise newException(ValueError, "no store transaction is open")
  s.saved = nil
method rollback*(s: MemStore) =
  let b = s.saved
  if b == nil: return
  s.subRows = b.subRows; s.noteRows = b.noteRows; s.entries = b.entries; s.evidence = b.evidence
  s.blobs = b.blobs; s.meta = b.meta
  s.saved = nil

type Node* = ref object
  p*: Provider
  store*: Store
  key*: PrivateKey                      ## this device's key
  device*: string                       ## its peer ID
  root*: string                         ## trust anchor; "" = no plant yet
  entries*: OrderedTable[string, JNode] ## id → entry (trusted: verified when it arrived)
  chains: Table[string, seq[string]]    ## device → ids by seq (index = seq − 1)
  evidence*: seq[StoredEntry]
  clock*: Hlc
  run*: Run                             ## the replayed state
  ignored*: OrderedTable[string, string]
  listeners*: seq[proc (why: string)]   ## told after every change: "local", "received", "adopted"
  staging: bool                         ## inside `atomic`: new entries wait in `staged` until the store commits
  staged: seq[StoredEntry]

proc rebuild*(n: Node) =
  ## Replay everything held, as trusted (each entry was verified when it arrived).
  if n.root.len == 0:
    n.run = nil
    return
  var trusted: seq[(string, JNode)]
  for id, e in n.entries: trusted.add((id, e))
  for (id, e) in n.evidence: trusted.add((id, e))   # a device that signed two entries for one seq is cut (§4, #35)
  let rr = n.p.replayRun(@[], n.root, trusted, useTrusted = true)
  n.run = rr.run
  n.ignored = rr.chainIgnored
  for k, v in rr.run.ignored: n.ignored[k] = v

proc changed*(n: Node, why: string) =
  for f in n.listeners: f(why)

proc addStored(n: Node, id: string, e: JNode) =
  n.entries[id] = e
  let peer = e["peer"].s
  n.chains.mgetOrPut(peer, @[]).add id

proc newNode*(p: Provider, store: Store, key: PrivateKey): Node =
  result = Node(p: p, store: store, key: key)
  result.device = p.peerId(key)
  result.root = store.getMeta("root")
  var all = store.loadEntries()
  all.sort(proc (a, b: StoredEntry): int =
    result = cmp(a.e["peer"].s, b.e["peer"].s)
    if result == 0: result = cmp(a.e["seq"].i, b.e["seq"].i))
  for (id, e) in all:
    result.addStored(id, e)
    discard result.clock.recv((e["hlc"][0].i, e["hlc"][1].i), 0)
  result.evidence = store.loadEvidence()
  result.rebuild()

proc adopt*(n: Node, root: string) =
  if n.root.len > 0: raise newException(ValueError, "this node already belongs to a plant")
  n.root = root
  n.store.setMeta("root", root)
  n.rebuild()
  n.changed("adopted")

proc lastOf(n: Node, device: string): (int64, string) =
  for i in countdown(n.staged.high, 0):   # an entry written earlier in the open transaction is the chain's head
    if n.staged[i].e["peer"].s == device: return (n.staged[i].e["seq"].i, n.staged[i].id)
  let c = n.chains.getOrDefault(device)
  if c.len == 0: (0'i64, "") else: (int64(c.len), c[^1])

proc appendAs*(n: Node, key: PrivateKey, typ: string, body: JNode, wall: int64): JNode =
  ## A new entry in the log of the device `key` belongs to (this device's own, or a custodial one on the server).
  let dev = n.p.peerId(key)
  let (seq, prev) = n.lastOf(dev)
  let e = n.p.makeEntry(key, seq + 1, prev, n.clock.now(wall), typ, body)
  let id = n.p.entryId(e)
  n.store.putEntry(id, e)
  if n.staging:
    n.staged.add((id, e))   # memory follows once the transaction is on disk (atomic)
    return e
  n.addStored(id, e)
  n.rebuild()
  n.changed("local")
  e

proc atomic*(n: Node, body: proc ()) =
  ## Runs `body` as one store transaction: its entries and rows (a submission's entry, its comment and the row with
  ## its client_id) are on disk all together or not at all, so a crash between them can't leave an entry whose resend
  ## isn't recognised. The entries `body` appends reach memory (the chains, the replay, the listeners) only after the
  ## commit: an error rolls the store back and leaves memory as it was, so memory never holds what the disk doesn't
  ## (a retry then continues the chain from the same head: no fork, nothing twice). Within `body` the new entries are
  ## not replayed yet (`n.run` and `n.entries` are as before it; the next append continues after them). Not nested.
  if n.staging: raise newException(ValueError, "atomic: already inside a transaction")
  n.store.begin()
  n.staging = true
  try:
    body()
    n.store.commit()
  except:
    n.staging = false
    n.staged.setLen(0)
    n.store.rollback()
    raise
  n.staging = false
  let done = move n.staged
  n.staged = @[]
  for (id, e) in done: n.addStored(id, e)
  if done.len > 0:
    n.rebuild()
    n.changed("local")

proc append*(n: Node, typ: string, body: JNode, wall: int64): JNode =
  ## A new entry in this device's own log.
  n.appendAs(n.key, typ, body, wall)

proc vv*(n: Node): JNode =
  ## {device: [last seq, ID of that entry]}.
  result = newObj()
  var devs: seq[string]
  for d, _ in n.chains: devs.add d
  devs.sort(system.cmp)
  for d in devs:
    let (seq, id) = n.lastOf(d)
    result.fields.add((d, newArr(@[newInt(seq), newStr(id)])))

proc mayRead*(n: Node, peer: string): bool =
  ## Only a certified, unrevoked device of a known person receives plant data.
  if n.run == nil or peer notin n.run.devices or peer in n.run.cuts: return false
  n.run.devices[peer]["person"].s in n.run.persons

proc entriesFor*(n: Node, theirVv: JNode): seq[JNode] =
  ## What the other side lacks: entries above its vv; a device's whole chain when its entry at their last seq differs
  ## from ours; all fork evidence.
  for d, ids in n.chains:
    var seq = 0'i64
    var head = ""
    let have = if theirVv != nil and theirVv.kind == jObj: theirVv.get(d) else: nil
    var valid = false
    if have != nil and have.kind == jArr and have.len == 2 and have[0].kind == jInt:
      seq = have[0].i
      head = if have[1].kind == jStr: have[1].s else: ""
      valid = true
    let mismatch = valid and seq >= 1 and seq <= int64(ids.len) and ids[seq - 1] != head
    for i, id in ids:
      if not valid or int64(i + 1) > seq or mismatch: result.add n.entries[id]
  for (_, e) in n.evidence: result.add e

proc revocationOf*(n: Node, device: string): JNode =
  ## The revoke entry that cut `device`, shown to it so it can wipe itself (§15). nil if none. Revokes replay ignored
  ## are skipped: a later one the log rejected (an admin's, for an admin's device) would be shown instead of the one
  ## that cut it, and the device would refuse it and keep its data.
  if n.run == nil or device notin n.run.cuts: return nil
  for id, e in n.entries:
    if id notin n.ignored and e["type"].s == "revoke" and e["body"].kind == jObj and e["body"].get("device") != nil and
       e["body"]["device"].kind == jStr and e["body"]["device"].s == device:
      if result == nil or (e["hlc"][0].i, e["hlc"][1].i) > (result["hlc"][0].i, result["hlc"][1].i): result = e

proc acceptRevocation*(n: Node, e: JNode): bool =
  ## Another device says this one was removed and shows the revoke entry. True if it checks out against our own log;
  ## the platform then wipes the plant data (§15).
  if n.run == nil or e == nil or e.kind != jObj: return false
  try: n.p.verifyEntry(e, (block:
    let peer = if e.get("peer") != nil and e["peer"].kind == jStr: e["peer"].s else: ""
    let c = n.chains.getOrDefault(peer)
    if c.len > 0 and n.entries[c[0]].has("key"): n.entries[c[0]]["key"].s else: ""))
  except ProtocolError: return false
  if e["type"].s != "revoke" or e["body"].get("device") == nil or e["body"]["device"].kind != jStr or
     e["body"]["device"].s != n.device: return false
  let author = e["peer"].s
  if author notin n.run.devices or author in n.run.cuts: return false
  let person = n.run.devices[author]["person"].s
  let role = n.run.role(person)
  let mine = if n.device in n.run.devices: n.run.devices[n.device]["person"].s else: ""
  # the same rule replay applies to a revoke (replay.tRevoke): the manager, the device's own person, or an admin for a
  # user's device. Before 2026-10-06 any admin's revoke was believed here, so an admin could make the manager's
  # devices wipe themselves although the log rejects that revoke (#31).
  # Roles are this device's view: a removed device gets no more entries, so a role changed after its last sync is
  # not seen (replay judges the revoke at its place in the log).
  role == "manager" or (mine.len > 0 and person == mine) or
    (role == "admin" and mine.len > 0 and n.run.role(mine) == "user")

proc revokerName*(n: Node, e: JNode): string =
  ## who removed this device (an accepted revoke entry): the person's full name, else the username
  let author = e["peer"].s
  if n.run == nil or author notin n.run.devices: return ""
  let pr = n.run.persons.getOrDefault(n.run.devices[author]["person"].s)
  if pr == nil: return ""
  for k in ["full_name", "username"]:
    if pr.get(k) != nil and pr[k].kind == jStr and pr[k].s.len > 0: return pr[k].s

proc ingest*(n: Node, batch: seq[JNode], wall: int64): int =
  ## Store entries from another device: verified; only entries of devices certified once the batch is counted; each
  ## device's chain continued in order (a gap waits for the next sync); a second different entry for a (device, seq)
  ## we hold is fork evidence. -> number of new entries (and evidence) kept.
  var good: OrderedTable[string, seq[(int64, string, JNode)]]
  # a device's seq-1 entry (its key) may be in the same batch: indexed once (a search per entry was quadratic, and a
  # stranger's one frame could hold the core for an hour, issue #67)
  var batchKeys: Table[string, string]
  for other in batch:
    if other != nil and other.kind == jObj and other.get("peer") != nil and other["peer"].kind == jStr and
       other.get("seq") != nil and other["seq"].kind == jInt and other["seq"].i == 1 and
       other.get("key") != nil and other["key"].kind == jStr:
      batchKeys[other["peer"].s] = other["key"].s   # the last one wins, as the search before did
  for e in batch:
    if e == nil or e.kind != jObj: continue
    let peer = if e.get("peer") != nil and e["peer"].kind == jStr: e["peer"].s else: ""
    var key = ""
    let c = n.chains.getOrDefault(peer)
    if c.len > 0: key = n.entries[c[0]]["key"].s
    else: key = batchKeys.getOrDefault(peer)
    try:
      n.p.verifyEntry(e, key)
    except ProtocolError:
      continue
    let id = n.p.entryId(e)
    good.mgetOrPut(peer, @[]).add((e["seq"].i, id, e))
  if good.len == 0 or n.root.len == 0: return 0
  var trusted: seq[(string, JNode)]
  for id, e in n.entries: trusted.add((id, e))
  for _, lst in good:
    for (_, id, e) in lst: trusted.add((id, e))
  let trial = n.p.replayRun(@[], n.root, trusted, useTrusted = true).run
  var added = 0
  for peer, lst0 in good:
    if peer notin trial.devices: continue
    var lst = lst0
    lst.sort(proc (a, b: (int64, string, JNode)): int = cmp(a[0], b[0]))
    var (lastSeq, lastId) = n.lastOf(peer)
    for (seq, id, e) in lst:
      if id in n.entries: continue
      if seq <= lastSeq:
        var known = false
        for (eid, _) in n.evidence:
          if eid == id: known = true
        if not known:
          n.evidence.add((id, e))
          n.store.putEvidence(id, e)
          inc added
      elif seq == lastSeq + 1 and (e["prev"].isNull and lastId.len == 0 or e["prev"].isStr and e["prev"].s == lastId):
        n.store.putEntry(id, e)
        n.addStored(id, e)
        discard n.clock.recv((e["hlc"][0].i, e["hlc"][1].i), wall)
        lastSeq = seq
        lastId = id
        inc added
  if added > 0:
    n.rebuild()
    n.changed("received")
  added

# ---------------------------------------------------------------- blobs

proc referencedBlobs*(n: Node): HashSet[string] =
  ## Photos in the state and in pending photo proposals; the files of the latest plant data version (§19).
  if n.run == nil: return
  for _, ph in n.run.photos: result.incl ph["blob"].s
  for id, st in n.run.proposals:
    if st == "pending":
      let e = n.entries[id]
      if e["type"].s == "photo": result.incl e["body"]["blob"].s
  let pd = n.run.settings.getOrDefault("plant_data")
  if pd != nil and pd.kind == jObj and pd.get("files") != nil and pd["files"].kind == jArr:
    for f in pd["files"].elems:
      if f.kind == jArr and f.len == 3 and f[1].kind == jStr: result.incl f[1].s

proc blobWants*(n: Node): seq[string] =
  for sha in n.referencedBlobs:
    if not n.store.blobHas(sha): result.add sha
  result.sort(system.cmp)

proc blobOffer*(n: Node, sha, data: string): bool =
  ## Accept a blob only if the log references it and the bytes hash to it.
  if sha notin n.referencedBlobs or n.store.blobHas(sha): return false
  if hex(n.p.sha256(data.toBytes)) != sha: return false
  n.store.blobPut(sha, data)
  true

proc blobName*(n: Node, sha: string): string =
  ## The file name pages use for a blob (/photos/<name>): its hash and the extension its bytes say.
  if not n.store.blobHas(sha): return ""
  sha & "." & blobExt(n.store.blobGet(sha))

proc keepBlob*(n: Node, data: string): string =
  ## Store a blob this device made itself (a photo, a plant data file). -> its SHA-256 hex.
  result = hex(n.p.sha256(data.toBytes))
  n.store.blobPut(result, data)

proc chainsLen*(n: Node): int =
  ## How many entries this device has written itself.
  n.chains.getOrDefault(n.device).len
