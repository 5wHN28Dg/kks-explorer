import std/[os, streams, strutils, times]
import kks/json
import std/algorithm
import kksi/contours

let dir = paramStr(1)
let man = parseStrict(readFile(dir / "manifest.json"))
for s in man.elems:
  let sid = s["id"].s
  let w = int(s["det"][0].i)
  let h = int(s["det"][1].i)
  let img = readFile(dir / (sid & ".det.gray"))
  var fg = newSeq[bool](w * h)
  for i in 0 ..< w * h: fg[i] = uint8(img[i]) < 215
  let t0 = epochTime()
  let holes = findHoles(fg, w, h)
  let ms = int((epochTime() - t0) * 1000)
  let f = newFileStream(dir / (sid & ".holes.bin"))
  let n = f.readInt32()
  var notes: seq[string]
  if int(n) != holes.len: notes.add "count " & $holes.len & " vs " & $n
  var refs: seq[Hole]
  for i in 0 ..< int(n):
    let np = f.readInt32()
    var r = Hole(x: int(f.readInt32()), y: int(f.readInt32()), w: int(f.readInt32()), h: int(f.readInt32()))
    for k in 0 ..< int(np):
      let yy = f.readInt32()
      let xx = f.readInt32()
      r.pts.add((xx, yy))
    refs.add r
  proc key(a: Hole): (int, int, int, int, int, int32, int32) = (a.x, a.y, a.w, a.h, a.pts.len, a.pts[0][1], a.pts[0][0])
  let mine = holes   # compared in order: reader2.pair's stable sort keeps cv2's order for equal corners
  var bad = 0
  for i in 0 ..< min(mine.len, refs.len):
    if key(mine[i]) != key(refs[i]) or mine[i].pts != refs[i].pts:
      if bad < 3: echo "  first diff: mine ", (mine[i].x, mine[i].y, mine[i].w, mine[i].h, mine[i].pts.len), " cv2 ", (refs[i].x, refs[i].y, refs[i].w, refs[i].h, refs[i].pts.len)
      inc bad
  var ties = 0
  for i in 1 ..< refs.len:
    if refs[i].x == refs[i-1].x and refs[i].y == refs[i-1].y: inc ties
  f.close()
  echo sid.alignLeft(7), " holes ", holes.len, (if notes.len > 0: " " & notes.join("; ") else: ""),
       "  diff ", bad, "  same (x,y) ", ties, "  (", ms, " ms)"
