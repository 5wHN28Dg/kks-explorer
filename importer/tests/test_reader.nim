## The reader's building blocks against OpenCV 5.0.0 / the Python extractor, on synthetic cases
## (tests/make_op_vectors.py → tests/vectors/cv2-ops.json.gz; no plant data). The full gate on the real sheets is
## tests/diff_trace.nim (local only).
import std/[os, base64, unittest]
import kks/[json, gz]
import kksi/[imgops, contours, fontlib, reader]

const Dir = currentSourcePath().parentDir
const Glyphs = Dir.parentDir.parentDir / "extractor" / "fontlib.kgl"

proc bytesOf(n: JNode): string = decode(n.s)
proc floats(s: string): seq[float32] =
  result = newSeq[float32](s.len div 4)
  if s.len > 0: copyMem(addr result[0], unsafeAddr s[0], s.len)
proc ints(s: string): seq[int32] =
  result = newSeq[int32](s.len div 4)
  if s.len > 0: copyMem(addr result[0], unsafeAddr s[0], s.len)
proc gray(w, h: int, s: string): Gray = Gray(w: w, h: h, d: cast[seq[uint8]](s))

let cases = parseStrict(gunzip(readFile(Dir / "vectors" / "cv2-ops.json.gz"), 64 shl 20), 4096)
proc each(op: string): seq[JNode] =
  for c in cases.elems:
    if c["op"].s == op: result.add c

suite "OpenCV operations":
  test "convexHull + contourArea + fillPoly":
    for c in each("hullfill"):
      var pts: seq[Pt]
      for p in c["pts"].elems: pts.add((int32(p[0].i), int32(p[1].i)))
      let hull = convexHull(pts)
      check hull.len == c["hull"].elems.len
      check abs(contourArea(hull) - c["area"].num) < 1e-9
      var g = newGray(int(c["w"].i), int(c["h"].i))
      g.fillPoly(hull, 255)
      check cast[string](g.d) == bytesOf(c["mask"])
  test "erode":
    for c in each("erode"):
      check cast[string](erode(gray(int(c["w"].i), int(c["h"].i), bytesOf(c["src"])), 3).d) == bytesOf(c["out"])
  test "connectedComponentsWithStats":
    for c in each("cc"):
      let src = bytesOf(c["src"])
      var bw = newSeq[bool](src.len)
      for i in 0 ..< src.len: bw[i] = src[i] != '\0'
      let r = components(bw, int(c["w"].i), int(c["h"].i))
      check r.n == int(c["n"].i)
      check r.labels == ints(bytesOf(c["labels"]))
      for i, s in c["stats"].elems:
        let m = r.stats[i + 1]
        check [m.x, m.y, m.w, m.h, m.area] == [int(s[0].i), int(s[1].i), int(s[2].i), int(s[3].i), int(s[4].i)]
  test "resize INTER_AREA (float32), bit for bit":
    for c in each("resize"):
      let src = FImg(w: int(c["w"].i), h: int(c["h"].i), d: floats(bytesOf(c["src"])))
      check resizeArea(src, int(c["dw"].i), 32).d == floats(bytesOf(c["out"]))
  test "GaussianBlur 3×3 σ 0.8 (float32), bit for bit":
    for c in each("gauss"):
      check gaussian3(FImg(w: 20, h: 32, d: floats(bytesOf(c["src"]))), 0.8).d == floats(bytesOf(c["out"]))
  test "findContours holes (RETR_CCOMP), in cv2's order":
    for c in each("holes"):
      let w = int(c["w"].i)
      let h = int(c["h"].i)
      let src = bytesOf(c["src"])
      var fg = newSeq[bool](w * h)
      for i in 0 ..< fg.len: fg[i] = src[i] != '\0'
      let holes = findHoles(fg, w, h)
      check holes.len == c["holes"].elems.len
      for i, want in c["holes"].elems:
        if i >= holes.len: break
        check [holes[i].x, holes[i].y, holes[i].w, holes[i].h] ==
              [int(want["rect"][0].i), int(want["rect"][1].i), int(want["rect"][2].i), int(want["rect"][3].i)]
        var pts: seq[(int32, int32)]
        for p in want["pts"].elems: pts.add((int32(p[0].i), int32(p[1].i)))
        check holes[i].pts == pts

suite "reader steps":
  test "clean + split_chars":
    for c in each("clean"):
      let w = int(c["w"].i)
      let h = int(c["h"].i)
      let keep = clean(gray(w, h, bytesOf(c["im"])), gray(w, h, bytesOf(c["mask"])))
      let want = bytesOf(c["keep"])
      var same = true
      for i in 0 ..< keep.d.len:
        if keep.d[i] != (want[i] != '\0'): same = false
      check same
      let (chars, y0, y1) = splitChars(keep)
      check chars.len == c["chars"].elems.len
      for i, ab in c["chars"].elems:
        if i < chars.len: check [chars[i].a, chars[i].b] == [int(ab[0].i), int(ab[1].i)]
      if c["band"].kind != jNull: check [y0, y1] == [int(c["band"][0].i), int(c["band"][1].i)]
  test "interpret (the KKS grammar)":
    for c in each("interpret"):
      let r = interpret(c["top"].s, c["bottom"].s)
      let o = c["out"]
      check r.kind == o["kind"].s
      check (if r.hasKks: r.kks else: "") == (if o.has("kks") and o["kks"].kind == jStr: o["kks"].s else: "")
      if o.has("suffix"): check r.suffix == o["suffix"].s
      if o.has("isa"): check (if r.isaNull: "" else: r.isa) == (if o["isa"].kind == jStr: o["isa"].s else: "")
      if o.has("note"): check r.note == o["note"].s
  test "classify: glyph library, norm, kNN (OpenBLAS single-thread order)":
    let lib = loadGlyphLib(Glyphs)
    check lib.n == 13794
    var scores: seq[float32]
    for c in each("classify"):
      let w = int(c["w"].i)
      let h = int(c["h"].i)
      let src = bytesOf(c["src"])
      var b = Bits(w: w, h: h, d: newSeq[bool](w * h))
      for i in 0 ..< b.d.len: b.d[i] = src[i] != '\0'
      let g = lib.classify(b, h, scores)
      check g.label == c["label"].s
      check g.conf == c["conf"].num
      for j in 0 ..< 5: check float(g.sim[j]) == c["sims"][j].num
