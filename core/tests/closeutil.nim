## Shared by the course tests: deep compare with a tolerance, and the evaluator snapshot.

proc close(a, b: JNode, path = "", tol = 1e-6): string =
  ## First difference or "". Numbers compare to tol (int and float alike).
  let an = a == nil or a.kind == jNull
  let bn = b == nil or b.kind == jNull
  if an or bn: return (if an and bn: "" else: path & ": null vs value")
  if a.kind in {jInt, jFloat} and b.kind in {jInt, jFloat}:
    return (if abs(a.num - b.num) <= tol: "" else: path & ": " & $a.num & " != " & $b.num)
  if a.kind != b.kind: return path & ": kind " & $a.kind & " != " & $b.kind
  case a.kind
  of jArr:
    if a.len != b.len: return path & ": length " & $a.len & " != " & $b.len
    for i in 0 ..< a.len:
      let d = close(a[i], b[i], path & "[" & $i & "]", tol)
      if d.len > 0: return d
  of jObj:
    if a.len != b.len: return path & ": key count " & $a.len & " != " & $b.len
    for (k, v) in a.fields:
      if not b.has(k): return path & ": missing " & k
      let d = close(v, b[k], path & "." & k, tol)
      if d.len > 0: return d
  else:
    if a != b: return path & ": " & $a & " != " & $b
  ""

proc snapshot(fg: Figure): JNode =
  var vals = newObj()
  for k, v in fg.vals: vals.fields.add((k, newFloat(v)))
  newObj(@[("t", newFloat(fg.t)), ("v", newFloat(fg.v)), ("playing", newBool(fg.playing)), ("values", vals),
           ("scene", fg.scene()), ("status", fg.status()), ("slider_text", fg.sliderText())])

