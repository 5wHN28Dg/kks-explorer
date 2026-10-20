## The saved replayed state (PROTOCOL-v2 §15b, decision 0059): a node started on a store reads it instead of replaying
## only when it is exactly the replay of what the store holds now, written by this program; anything else (another
## log, another root, fork evidence added, another version's, damaged, cut short, garbage) is ignored and the log
## replayed, so what a start shows is always what a replay would show.
import std/[unittest, tables, sets, algorithm, strutils]
import kks/[json, util, crypto, proto, node, replay, savedstate, binser, plant, api]
import testprovider
import vectors

let P = testProvider()
var clock = 1_790_000_000_000'i64
proc now(): int64 =
  clock += 1000
  clock

proc fields(r: Run): seq[(string, string)] =
  ## everything a replay leaves that other code reads, as text
  result.add(("state", stateBytes(r.state)))
  var h = newArr()
  for x in r.history: h.elems.add x
  result.add(("history", toText(h)))
  var d = newObj()
  for k, v in r.decisions: d.fields.add((k, v))
  result.add(("decisions", toText(d)))
  var c = newObj()
  for k, v in r.comments: c.fields.add((k, newArr(v)))
  result.add(("comments", toText(c)))
  var a: seq[string]
  for k, v in r.authors: a.add k & "=" & v
  a.sort(system.cmp)
  result.add(("authors", $a))
  var o: seq[string]
  for k, v in r.eqBy: o.add k & "=" & $v
  for k, v in r.reviewBy: o.add "review " & k & "=" & $v
  o.sort(system.cmp)
  result.add(("owners", $o))
  var cu: seq[string]
  for k, v in r.cuts: cu.add k & "=" & $v
  cu.sort(system.cmp)
  result.add(("cuts", $cu))

proc same(a, b: Node): bool =
  ## the two nodes hold the same replayed state (and the same ignored entries)
  fields(a.run) == fields(b.run) and a.ignored == b.ignored

proc plantStore(edits = 30): (MemStore, PrivateKey) =
  ## a manager's device with a plant and some approved edits, a person, a tag
  let s = newMemStore()
  let k = P.p256Generate()
  let n = newNode(P, s, k)
  let root = P.p256Generate()
  discard n.append("genesis", P.genesisBody(root, "Test plant", n.device, P.newPersonId(), "boss", "The Manager"), now())
  n.adopt(keyString(root.pub))
  let api = newApi(n)
  let me = api.owner[1]
  for i in 0 ..< edits:
    let r = api.handle(me, "POST", "/api/submit", initTable[string, string](), parseStrict(
      """{"kind":"equipment","payload":{"kks":"11LAB70AA50""" & $(i mod 10) & """","changes":{"notes":"round """ & $i &
      """"},"base":{}}}"""), now())
    doAssert r.status < 400, $r.status
    n.saveState()
  (s, k)

suite "the saved state is read only when it is the replay of what is held":
  test "a start after a saved state reads it, and it is what a replay gives":
    let (s, k) = plantStore()
    check s.getMeta(SavedStateKey).len > 0
    let a = newNode(P, s, k)
    check a.stateFromSaved
    forceFinalPass = true
    let replayed = newNode(P, newMemStore(), k)          # (a store without a saved state: replays)
    for (id, e) in s.entries: replayed.store.putEntry(id, e)
    replayed.store.setMeta("root", s.getMeta("root"))
    let b = newNode(P, replayed.store, k)
    forceFinalPass = false
    check not b.stateFromSaved
    check same(a, b)
    check a.run.equipment.len == 10

  test "every scenario of the vectors comes back field for field":
    for file in ["v2-replay.json", "v2-malformed.json", "v2-reports.json"]:
      for sc in loadVectors(file)["scenarios"].elems:
        let rr = P.replayRun(sc["entries"].elems, sc["root"].s)
        let bytes = encodeSaved(P, repeat("ab", 32), rr.run, rr.chainIgnored)
        let (run, ign) = decodeSaved(P, bytes, repeat("ab", 32))
        check fields(run) == fields(rr.run)
        check ign == rr.chainIgnored

  test "an entry added to the store after the state was saved: replayed":
    let (s, k) = plantStore()
    let saved = s.getMeta(SavedStateKey)
    # another device's entry, as a sync writes it: the store holds more than the saved state was made from
    let n = newNode(P, s, k)
    let api = newApi(n)
    discard api.handle(api.owner[1], "POST", "/api/submit", initTable[string, string](), parseStrict(
      """{"kind":"equipment","payload":{"kks":"11LAB70AA599","changes":{"notes":"new"},"base":{}}}"""), now())
    s.setMeta(SavedStateKey, saved)                       # (the old saved state, as if the process had died)
    let after = newNode(P, s, k)
    check not after.stateFromSaved
    check "11LAB70AA599" in after.run.equipment

  test "an entry gone from the store: replayed":
    let (s, k) = plantStore()
    s.entries.setLen(s.entries.len - 1)
    let n = newNode(P, s, k)
    check not n.stateFromSaved
    check n.entries.len == s.entries.len

  test "fork evidence added: replayed":
    let (s, k) = plantStore()
    let (id, e) = s.entries[^1]
    var other = copy(e)
    other["hlc"] = newArr(@[newInt(e["hlc"][0].i + 1), newInt(0)])
    s.putEvidence(id & "x", other)
    let n = newNode(P, s, k)
    check not n.stateFromSaved

  test "another root: replayed":
    let (s, k) = plantStore()
    let saved = s.getMeta(SavedStateKey)
    let (s2, k2) = plantStore()                            # another plant's store, given this one's saved state
    s2.setMeta(SavedStateKey, saved)
    let n = newNode(P, s2, k2)
    check not n.stateFromSaved
    check n.run.root == s2.getMeta("root")
    discard k

  test "another program's saved state: replayed":
    let (s, k) = plantStore()
    var saved = s.getMeta(SavedStateKey)
    let at = "kks-saved-state-v1\n".len
    saved[at] = (if saved[at] == '0': '1' else: '0')      # another code id
    s.setMeta(SavedStateKey, saved)
    check not newNode(P, s, k).stateFromSaved

  test "damaged, cut short, empty or garbage: replayed, and the same state":
    let (s, k) = plantStore()
    let good = s.getMeta(SavedStateKey)
    let want = newNode(P, s, k)
    check want.stateFromSaved
    var cases: seq[string]
    for at in [good.len div 3, good.len div 2, good.len - 1, 200, 260]:
      var b = good
      b[at] = char(ord(b[at]) xor 0x20)                   # one bit somewhere in the payload or its checksum
      cases.add b
    cases.add good[0 ..< good.len div 2]
    cases.add good[0 ..< 50]
    cases.add good & "x"
    cases.add "x"
    cases.add repeat('\xff', 5000)
    for b in cases:
      s.setMeta(SavedStateKey, b)
      let n = newNode(P, s, k)
      check not n.stateFromSaved
      check same(n, want)
      let again = newNode(P, s, k)                        # (the replay saved the state again)
      check again.stateFromSaved and same(again, want)

  test "a payload that is not one (checksum right, content wrong) is refused by the reader":
    let (s, k) = plantStore()
    let good = s.getMeta(SavedStateKey)
    let head = "kks-saved-state-v1\n".len + CodeId.len + 64
    for cut in [1, 7, 100]:
      let payload = good[head + 64 .. ^(cut + 1)]           # the payload cut short, with its own right checksum
      let b = good[0 ..< head] & hex(P.sha256(payload.toBytes)) & payload
      expect SavedStateError: discard decodeSaved(P, b, good[head - 64 ..< head])
      s.setMeta(SavedStateKey, b)
      check not newNode(P, s, k).stateFromSaved

  test "saveState writes only when the state changed, never inside a transaction":
    let (s, k) = plantStore(3)
    let n = newNode(P, s, k)
    check not n.stateDirty
    s.setMeta(SavedStateKey, "marker")
    n.saveState()
    check s.getMeta(SavedStateKey) == "marker"            # nothing changed: not written again
    let api = newApi(n)
    discard api.handle(api.owner[1], "POST", "/api/submit", initTable[string, string](), parseStrict(
      """{"kind":"equipment","payload":{"kks":"11LAB70AA598","changes":{"notes":"x"},"base":{}}}"""), now())
    check n.stateDirty
    n.saveState()
    check not n.stateDirty
    check newNode(P, s, k).stateFromSaved

  test "a store whose root is gone (wiped) gets nothing written back":
    let (s, k) = plantStore(3)
    let n = newNode(P, s, k)
    let api = newApi(n)
    discard api.handle(api.owner[1], "POST", "/api/submit", initTable[string, string](), parseStrict(
      """{"kind":"equipment","payload":{"kks":"11LAB70AA597","changes":{"notes":"x"},"base":{}}}"""), now())
    s.meta.clear()                                       # what a wipe leaves (§15)
    n.saveState()
    check s.getMeta(SavedStateKey) == ""

  test "no plant yet: nothing saved, nothing read":
    let s = newMemStore()
    let n = newNode(P, s, P.p256Generate())
    check n.run == nil
    n.saveState()
    check s.getMeta(SavedStateKey) == ""

suite "the binary form":
  test "values come back as they were":
    var w = Writer()
    let j = parseStrict("""{"a":[1,-2,9223372036854775807,-9223372036854775808,1.5,"x",true,false,null,{}],"b":"ü"}""")
    w.put(j)
    w.put(JNode(nil))
    w.put(-1'i64)
    var r = Reader(data: w.buf)
    var j2, n: JNode
    var i: int64
    r.get(j2)
    r.get(n)
    r.get(i)
    r.done()
    check j2 == j and toText(j2) == toText(j)
    check n == nil
    check i == -1

  test "a count larger than what is left is refused, not allocated":
    var w = Writer()
    w.put(1_000_000_000)
    var r = Reader(data: "\x08" & w.buf)
    var j: JNode
    expect SavedStateError: r.get(j)
