## extractor/reader2.detect + pair and extractor/reader3 (decision 0026): find the tag containers on the 200 dpi
## render, pair stacked halves, crop each half at 600 dpi under its convex-hull mask, clean, split and classify.

import std/[algorithm, math]
import mupdf, contours, imgops, fontlib

const
  DpiDet* = 200.0
  DpiRead* = 600.0
  Shrink = 2

type
  Cell* = object
    x*, y*, w*, h*: int
    poly*: seq[(float32, float32)]   ## the hole's border points / k, as float32 (numpy: int32 → float32 / k)
  Pair* = object
    o*: char                          ## 'h' or 'v'
    a*, b*: int                       ## indices into cells
  Tracer* = object
    onGlyph*: proc (sub: Bits, hc: int, g: Glyph)
    onRead*: proc (im, mask: imgops.Gray, s: string, c: float)
  Reader* = object
    lib*: GlyphLib
    scores: seq[float32]
    trace*: Tracer
  Sheet* = object
    doc*: Doc
    k*: float
    cells*: seq[Cell]
    size*: (float, float)

proc detect*(doc: Doc): Sheet =
  let k = DpiDet / 72.0
  let img = doc.renderGray(k, minLineWidth = 0.5)
  var fg = newSeq[bool](img.w * img.h)
  for i in 0 ..< fg.len: fg[i] = img.data[i] < 215
  let kf = float32(k)
  result = Sheet(doc: doc, k: k)
  let (pw, ph) = doc.pageSize
  result.size = (float(pw), float(ph))
  for hole in findHoles(fg, img.w, img.h):
    let wd = float(hole.w) / k
    let ht = float(hole.h) / k
    if not ((4 < ht and ht < 24 and 15 < wd and wd < 110) or (4 < wd and wd < 24 and 15 < ht and ht < 110)): continue
    var pts: seq[Pt]
    for (x, y) in hole.pts: pts.add((x, y))
    if contourArea(convexHull(pts)) < 0.75 * float(hole.w * hole.h): continue
    var c = Cell(x: hole.x, y: hole.y, w: hole.w, h: hole.h)
    for (x, y) in hole.pts: c.poly.add((float32(x) / kf, float32(y) / kf))
    result.cells.add c

proc fitsOv(p, pw, q, qw: int): bool =
  let ov = min(p + pw, q + qw) - max(p, q)
  float(ov) >= 0.85 * float(min(pw, qw)) and float(min(pw, qw)) >= 0.7 * float(max(pw, qw))

proc pairCells*(cells: seq[Cell]): seq[Pair] =
  ## reader2.pair: cells sorted by (x, y) (stable), first fitting partner wins.
  var s: seq[(int, int, int)]   # (x, y, index): the order of Python's stable sort on (x, y)
  for i, c in cells: s.add((c.x, c.y, i))
  s.sort()
  var used = newSeq[bool](s.len)
  for i in 0 ..< s.len:
    if used[i]: continue
    let a = cells[s[i][2]]
    for j in 0 ..< s.len:
      if i == j or used[j]: continue
      let b = cells[s[j][2]]
      let gy = b.y - (a.y + a.h)
      if -3 <= gy and gy < 8 and fitsOv(a.x, a.w, b.x, b.w):
        result.add Pair(o: 'h', a: s[i][2], b: s[j][2])
        used[i] = true; used[j] = true
        break
      let gx = b.x - (a.x + a.w)
      if -3 <= gx and gx < 8 and fitsOv(a.y, a.h, b.y, b.h):
        result.add Pair(o: 'v', a: s[i][2], b: s[j][2])
        used[i] = true; used[j] = true
        break

proc toGray(g: Pixmap): imgops.Gray = imgops.Gray(w: g.w, h: g.h, d: g.data)

proc cellImage*(sh: Sheet, c: Cell, orient: char, ccw = false): (imgops.Gray, imgops.Gray) =
  let k = sh.k
  let r = (float(c.x + Shrink) / k, float(c.y + Shrink) / k, float(c.x + c.w - Shrink) / k, float(c.y + c.h - Shrink) / k)
  var im = sh.doc.renderGray(DpiRead / 72.0, r, hasClip = true).toGray
  let s = DpiRead / 72.0
  var pts: seq[Pt]
  for (px, py) in c.poly:
    pts.add((int32(trunc((float(px) - r[0]) * s)), int32(trunc((float(py) - r[1]) * s))))
  var mask = newGray(im.w, im.h)
  mask.fillPoly(convexHull(pts), 255)
  mask = erode(mask, 3)
  if orient == 'v':
    if ccw:
      im = rotateCcw(im); mask = rotateCcw(mask)
    else:
      im = rotateCw(im); mask = rotateCw(mask)
  (border(im, 30, 30, 30, 30, 255), border(mask, 30, 30, 30, 30, 0))

proc clean*(im, mask: imgops.Gray): Bits =
  let w = im.w
  let h = im.h
  var bw = newSeq[bool](w * h)
  for i in 0 ..< bw.len: bw[i] = im.d[i] < 190
  let cc = components(bw, w, h)
  let inner = h - 60
  var keep = newSeq[bool](w * h)
  for i in 1 ..< cc.n:
    let st = cc.stats[i]
    if float(st.w) > 0.6 * float(w) or float(st.h) > 0.95 * float(inner) + 20: continue
    let edge = st.x <= 34 or st.x + st.w >= w - 34
    if edge and float(st.h) > 0.5 * float(inner):
      var trimmed = newSeq[bool](w * h)
      var n = 0
      var ymin = high(int)
      var ymax = -1
      for y in st.y ..< st.y + st.h:
        for x in st.x ..< st.x + st.w:
          let p = y * w + x
          if cc.labels[p] == int32(i) and mask.d[p] > 0:
            trimmed[p] = true
            inc n
            ymin = min(ymin, y); ymax = max(ymax, y)
      if n > 40 and float(ymax - ymin) > 0.6 * float(inner):
        let c2 = components(trimmed, w, h)
        if c2.n > 1:
          var j = 1
          for q in 2 ..< c2.n:
            if c2.stats[q].area > c2.stats[j].area: j = q
          let sj = c2.stats[j]
          for y in sj.y ..< sj.y + sj.h:
            for x in sj.x ..< sj.x + sj.w:
              if c2.labels[y * w + x] == int32(j): keep[y * w + x] = true
      continue
    for y in st.y ..< st.y + st.h:
      for x in st.x ..< st.x + st.w:
        if cc.labels[y * w + x] == int32(i): keep[y * w + x] = true
  # drop specks far smaller than the text
  let c2 = components(keep, w, h)
  if c2.n > 1:
    var maxh = 0
    for j in 1 ..< c2.n: maxh = max(maxh, c2.stats[j].h)
    for j in 1 ..< c2.n:
      let sj = c2.stats[j]
      if float(sj.h) < 0.3 * float(maxh) and float(sj.w) < 0.3 * float(maxh):
        for y in sj.y ..< sj.y + sj.h:
          for x in sj.x ..< sj.x + sj.w:
            if c2.labels[y * w + x] == int32(j): keep[y * w + x] = false
  Bits(w: w, h: h, d: keep)

proc read*(r: var Reader, im, mask: imgops.Gray): (string, float) =
  let bw = clean(im, mask)
  let (chars, y0, y1) = splitChars(bw)
  var s = ""
  var conf = 0.0
  if chars.len > 0:
    let hc = y1 - y0 + 1
    var cs: seq[float]
    for p in chars:
      let g = r.lib.classify(p.sub, hc, r.scores)
      if r.trace.onGlyph != nil: r.trace.onGlyph(p.sub, hc, g)
      if g.label.len > 0:
        s.add g.label
        cs.add g.conf
    if cs.len > 0: conf = min(cs)
  if r.trace.onRead != nil: r.trace.onRead(im, mask, s, conf)
  (s, conf)

proc isTag(i: Interp): bool = i.kind in ["equipment", "instrument"]

type Single* = object
  o*: char
  t*, u*: string
  conf*: float

proc readSingle1(r: var Reader, sh: Sheet, c: Cell, o: char, ccw: bool): (bool, Single) =
  var (im, mask) = sh.cellImage(c, o, ccw)
  for i in 0 ..< im.d.len:
    if mask.d[i] == 0: im.d[i] = 255
  let cl = clean(im, mask)
  var rows = newSeq[int](cl.h)
  for y in 0 ..< cl.h:
    for x in 0 ..< cl.w:
      if cl.d[y * cl.w + x]: inc rows[y]
  var ys: seq[int]
  for y in 0 ..< cl.h:
    if rows[y] != 0: ys.add y
  if ys.len == 0: return (false, Single())
  var bestRun = 0
  var bestC = -1
  var run = 0
  for i in 0 ..< ys[^1] - ys[0]:
    if rows[ys[0] + i] == 0: inc run else: run = 0
    if run > bestRun:
      bestRun = run
      bestC = ys[0] + i - run div 2
  if bestC < 0 or bestRun < 4:
    let (u, cu) = r.read(im, mask)
    return (true, Single(o: o, t: "", u: u, conf: cu))
  let c0 = bestC
  let (t, ct) = r.read(border(im.rows(0, c0 + 1), 30, 30, 0, 0, 255), border(mask.rows(0, c0 + 1), 30, 30, 0, 0, 0))
  let (u, cu) = r.read(border(im.rows(c0, im.h), 30, 30, 0, 0, 255), border(mask.rows(c0, mask.h), 30, 30, 0, 0, 0))
  (true, Single(o: o, t: t, u: u, conf: min(ct, cu)))

proc readSingle*(r: var Reader, sh: Sheet, c: Cell): (bool, Single) =
  let wd = float(c.w) / sh.k
  let ht = float(c.h) / sh.k
  if min(wd, ht) < 10: return (false, Single())
  let o = if wd >= ht: 'h' else: 'v'
  if o == 'v':
    var rs: seq[Single]
    let (ok1, s1) = r.readSingle1(sh, c, o, false)
    if ok1: rs.add s1
    let (ok2, s2) = r.readSingle1(sh, c, o, true)
    if ok2: rs.add s2
    if rs.len == 0: return (false, Single())
    var best = 0
    for i in 1 ..< rs.len:
      let a = (isTag(interpret(rs[i].t, rs[i].u)), rs[i].conf)
      let b = (isTag(interpret(rs[best].t, rs[best].u)), rs[best].conf)
      if a > b: best = i
    return (true, rs[best])
  r.readSingle1(sh, c, o, false)
