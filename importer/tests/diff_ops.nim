## imgops.nim against cv2 on the synthetic cases of tests/make_op_vectors.py.
import std/[os, base64, strutils, algorithm, sets]
import kks/json
import kksi/imgops

proc bytesOf(n: JNode): string = decode(n.s)
proc floats(s: string): seq[float32] =
  result = newSeq[float32](s.len div 4)
  if s.len > 0: copyMem(addr result[0], unsafeAddr s[0], s.len)
proc ints(s: string): seq[int32] =
  result = newSeq[int32](s.len div 4)
  if s.len > 0: copyMem(addr result[0], unsafeAddr s[0], s.len)

let cases = parseStrict(readFile(paramStr(1)), 4096)
var stats: seq[(string, int, int)]   # op, cases, bad
var maxDiff = [0.0, 0.0]
var exact = [0, 0]
proc tally(op: string, ok: bool) =
  for s in stats.mitems:
    if s[0] == op:
      inc s[1]
      if not ok: inc s[2]
      return
  stats.add((op, 1, int(not ok)))
for c in cases.elems:
  let op = c["op"].s
  case op
  of "hullfill":
    var pts: seq[Pt]
    for p in c["pts"].elems: pts.add((int32(p[0].i), int32(p[1].i)))
    let hull = convexHull(pts)
    var hs, rs: HashSet[Pt]
    for p in hull: hs.incl p
    for p in c["hull"].elems: rs.incl((int32(p[0].i), int32(p[1].i)))
    var g = newGray(int(c["w"].i), int(c["h"].i))
    g.fillPoly(hull, 255)
    let ok = hs == rs and hull.len == c["hull"].elems.len and cast[string](g.d) == bytesOf(c["mask"]) and
             abs(contourArea(hull) - c["area"].f) < 1e-9
    if not ok and stats.len < 99: echo "hullfill diff: hull ", hs == rs, " fill ", cast[string](g.d) == bytesOf(c["mask"])
    tally(op, ok)
  of "erode":
    let src = bytesOf(c["src"])
    var g = Gray(w: int(c["w"].i), h: int(c["h"].i), d: cast[seq[uint8]](src))
    tally(op, cast[string](erode(g, 3).d) == bytesOf(c["out"]))
  of "cc":
    let src = bytesOf(c["src"])
    var bw = newSeq[bool](src.len)
    for i in 0 ..< src.len: bw[i] = src[i] != '\0'
    let r = components(bw, int(c["w"].i), int(c["h"].i))
    var ok = r.n == int(c["n"].i) and r.labels == ints(bytesOf(c["labels"]))
    for i, s in c["stats"].elems:
      let m = r.stats[i + 1]
      if m.x != int(s[0].i) or m.y != int(s[1].i) or m.w != int(s[2].i) or m.h != int(s[3].i) or m.area != int(s[4].i): ok = false
    tally(op, ok)
  of "resize", "gauss":
    var src: FImg
    var outp: FImg
    let k = if op == "resize": 0 else: 1
    if op == "resize":
      src = FImg(w: int(c["w"].i), h: int(c["h"].i), d: floats(bytesOf(c["src"])))
      outp = resizeArea(src, int(c["dw"].i), 32)
    else:
      src = FImg(w: 20, h: 32, d: floats(bytesOf(c["src"])))
      outp = gaussian3(src, 0.8)
    let want = floats(bytesOf(c["out"]))
    var d = 0.0
    for i in 0 ..< want.len: d = max(d, abs(float(want[i]) - float(outp.d[i])))
    maxDiff[k] = max(maxDiff[k], d)
    if outp.d == want: inc exact[k]
    tally(op, d < 1e-5)
for s in stats: echo s[0].alignLeft(9), s[1], " cases, ", s[2], " differ"
echo "resize: ", exact[0], " bit-exact, max diff ", maxDiff[0]
echo "gauss: ", exact[1], " bit-exact, max diff ", maxDiff[1]
