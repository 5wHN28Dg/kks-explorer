import std/[unittest, strutils]
import kks/[json, util]
import vectors

proc typed(n: JNode): JNode =
  ## The vectors' typed form (ref/sjson.typed).
  case n.kind
  of jNull: newObj(@[("t", newStr("null"))])
  of jBool: newObj(@[("t", newStr("bool")), ("v", newBool(n.b))])
  of jInt: newObj(@[("t", newStr("int")), ("v", newStr($n.i))])
  of jBig: newObj(@[("t", newStr("big")), ("v", newStr(n.big))])
  of jFloat: newObj(@[("t", newStr("float")), ("v", newFloat(n.f))])
  of jStr: newObj(@[("t", newStr("str")), ("v", newStr(n.s))])
  of jArr:
    var a = newArr()
    for e in n.elems: a.elems.add typed(e)
    newObj(@[("t", newStr("arr")), ("v", a)])
  of jObj:
    var a = newArr()
    for (k, v) in n.fields: a.elems.add newArr(@[newStr(k), typed(v)])
    newObj(@[("t", newStr("obj")), ("v", a)])

proc sameTyped(got, want: JNode): bool =
  ## Floats: the vector gives the shortest decimal; compare the doubles. Objects: order matters here.
  if got["t"].s != want["t"].s: return false
  case got["t"].s
  of "null": true
  of "float": got["v"].f == parseFloat(want["v"].s)
  of "arr":
    if got["v"].len != want["v"].len: return false
    for i in 0 ..< got["v"].len:
      if not sameTyped(got["v"][i], want["v"][i]): return false
    true
  of "obj":
    if got["v"].len != want["v"].len: return false
    for i in 0 ..< got["v"].len:
      if got["v"][i][0].s != want["v"][i][0].s or not sameTyped(got["v"][i][1], want["v"][i][1]): return false
    true
  else: got["v"] == want["v"]

suite "strict JSON (v2-json.json)":
  let V = loadVectors("v2-json.json")
  test "accept":
    for c in V["accept"].elems:
      let n = parseStrict(unhex(c["hex"].s).toStr)
      check sameTyped(typed(n), c["value"])
      if not sameTyped(typed(n), c["value"]): echo "  ", c["why"].s
  test "reject":
    for c in V["reject"].elems:
      var refused = false
      try: discard parseStrict(unhex(c["hex"].s).toStr)
      except JsonError: refused = true
      check refused
      if not refused: echo "  accepted: ", c["why"].s

suite "canonical encoding (v2-core.json)":
  let V = loadVectors("v2-core.json")
  test "canonical":
    for c in V["canonical"].elems:
      check hex(canonical(c["input"])) == c["canonical_utf8_hex"].s
  test "canonical_reject":
    for c in V["canonical_reject"].elems:
      let n = parseStrict(c["input_json"].s)
      check not checkCanonical(n)

suite "base64url":
  test "round trip":
    for n in 0 .. 40:
      var b: seq[byte]
      for i in 0 ..< n: b.add byte((i * 37 + 11) mod 256)
      check unb64u(b64u(b)) == b
  test "strict":
    expect ValueError: discard unb64u("A")
    expect ValueError: discard unb64u("AB=")
    expect ValueError: discard unb64u("AB")   # unused bits set
