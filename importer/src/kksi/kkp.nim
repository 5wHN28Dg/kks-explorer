## A sheet's vector drawing as a .kkp path store (docs/PATHSTORE.md): the port of ref/pathstore.from_pdf_page
## (vector paths; the images are added by `addImages`). Coordinates go through PyMuPDF's arithmetic: MuPDF float
## point transforms, Python double rounding to 1/64 pt.

import std/[algorithm, math, tables]
import kks/pathstore
import mupdf, jxl

type ImportError* = object of CatchableError

proc q(v: float): int64 =
  ## _q: int(round(v * 64)), ties to even
  let x = v * float(Q)
  let f = floor(x)
  let d = x - f
  int64(if d > 0.5: f + 1 elif d < 0.5: f elif f mod 2 == 0: f else: f + 1)

proc tf(m: array[6, float], x, y: float32): (int64, int64) =
  ## util_transform_point: MuPDF's fz_transform_point, in float
  let a = float32(m[0])
  let b = float32(m[1])
  let c = float32(m[2])
  let d = float32(m[3])
  let e = float32(m[4])
  let f = float32(m[5])
  let px = x * a + y * c + e
  let py = x * b + y * d + f
  (q(float(px)), q(float(py)))

proc rgb(c: seq[float32]): array[3, uint8] =
  if c.len == 0: return [0'u8, 0, 0]
  for i in 0 .. 2:
    let v = max(0.0, min(1.0, float(c[i]))) * 255
    let f = floor(v)
    let d = v - f
    result[i] = uint8(if d > 0.5: f + 1 elif d < 0.5: f elif f mod 2 == 0: f else: f + 1)

proc concatF(one, two: array[6, float32]): array[6, float32] =
  ## fz_concat, in float
  result[0] = one[0] * two[0] + one[1] * two[2]
  result[1] = one[0] * two[1] + one[1] * two[3]
  result[2] = one[2] * two[0] + one[3] * two[2]
  result[3] = one[2] * two[1] + one[3] * two[3]
  result[4] = one[4] * two[0] + one[5] * two[2] + two[4]
  result[5] = one[4] * two[1] + one[5] * two[3] + two[5]

type Px = object
  w, h, n: int
  d: seq[byte]

proc flipLR(p: Px): Px =
  result = Px(w: p.w, h: p.h, n: p.n, d: newSeq[byte](p.d.len))
  for y in 0 ..< p.h:
    for x in 0 ..< p.w:
      for k in 0 ..< p.n: result.d[(y * p.w + x) * p.n + k] = p.d[(y * p.w + p.w - 1 - x) * p.n + k]

proc flipTB(p: Px): Px =
  result = Px(w: p.w, h: p.h, n: p.n, d: newSeq[byte](p.d.len))
  for y in 0 ..< p.h:
    for x in 0 ..< p.w:
      for k in 0 ..< p.n: result.d[(y * p.w + x) * p.n + k] = p.d[((p.h - 1 - y) * p.w + x) * p.n + k]

proc transpose(p: Px): Px =
  result = Px(w: p.h, h: p.w, n: p.n, d: newSeq[byte](p.d.len))
  for y in 0 ..< p.h:
    for x in 0 ..< p.w:
      for k in 0 ..< p.n: result.d[(x * result.w + y) * p.n + k] = p.d[(y * p.w + x) * p.n + k]

proc addImages(d: var Drawing, m: array[6, float], images: seq[PageImage], seqnos: seq[int], effort: int) =
  ## ref/pathstore._images: images in paint order, upright, positioned by their transform; `after` = the paths
  ## painted before it (as the reference computes it: path seqnos below the image's index in the bbox log).
  var mf: array[6, float32]
  for i in 0 .. 5: mf[i] = float32(m[i])
  for im in images:
    let t = concatF(im.ctm, mf)
    let eps = 1e-6 * max(max(max(abs(float(t[0])), abs(float(t[1]))), max(abs(float(t[2])), abs(float(t[3])))), 1.0)
    var px = Px(w: im.w, h: im.h, n: im.n, d: im.pixels)
    if abs(float(t[1])) <= eps and abs(float(t[2])) <= eps:
      if t[0] < 0: px = flipLR(px)
      if t[3] < 0: px = flipTB(px)
    elif abs(float(t[0])) <= eps and abs(float(t[3])) <= eps:
      px = transpose(px)
      if t[2] < 0: px = flipLR(px)
      if t[1] < 0: px = flipTB(px)
    else:
      raise newException(ImportError, "image drawn at an angle other than a quarter turn: not supported")
    var xs, ys: seq[int64]
    for (cx, cy) in [(0'f32, 0'f32), (1'f32, 0'f32), (0'f32, 1'f32), (1'f32, 1'f32)]:
      let (qx, qy) = tf([float(t[0]), float(t[1]), float(t[2]), float(t[3]), float(t[4]), float(t[5])], cx, cy)
      xs.add qx
      ys.add qy
    let after = lowerBound(seqnos, im.logidx)
    d.images.add pathstore.Image(after: after, rect: [min(xs), min(ys), max(xs), max(ys)],
                                 data: encodeLossless(px.d, px.w, px.h, px.n, effort))

proc fromPdfPage*(doc: Doc, extra: int, images = true, effort = 9): Drawing =
  let (m, r) = doc.displayGeom(extra)
  result.width = uint32(q(max(0.0, r[2] - r[0])))
  result.height = uint32(q(max(0.0, r[3] - r[1])))
  let scale = sqrt(abs(m[0] * m[3] - m[1] * m[2]))
  var styleIds = initTable[(uint8, uint8, uint8, uint32, array[3, uint8], array[3, uint8]), int]()
  var paths: seq[mupdf.Path]
  var pageImages: seq[PageImage]
  if images: (paths, pageImages) = doc.drawingsAndImages()
  else: paths = doc.drawings(unrotate = true)
  var seqnos: seq[int]
  # sorted(…, key=seqno): stable
  var idx = newSeq[int](paths.len)
  for i in 0 ..< idx.len: idx[i] = i
  for i in 1 ..< idx.len:   # already in seqno order in practice; keep a stable insertion sort for safety
    var j = i
    let v = idx[i]
    while j > 0 and paths[idx[j - 1]].seqno > paths[v].seqno:
      idx[j] = idx[j - 1]
      dec j
    idx[j] = v
  for pi in idx:
    let d = paths[pi]
    let stroke = 's' in d.kind
    let fill = 'f' in d.kind
    var kind = (if stroke: Stroke else: 0'u8) or (if fill: Fill else: 0'u8)
    if fill and d.evenOdd: kind = kind or EvenOdd
    let w = if d.hasStroke: float(d.width) else: 0.0
    if stroke and w == 0: kind = kind or Hairline
    if d.hasStroke and d.dashLen > 0:
      raise newException(ImportError, "dash pattern not supported (seqno " & $d.seqno & ")")
    let cap = if stroke: d.cap[0] else: 0
    let join = if stroke: d.join else: 0
    let wq = if stroke and w != 0: q(w * scale) else: 0'i64
    let st = (kind, uint8(cap), uint8(join), uint32(wq), (if stroke: rgb(d.color) else: [0'u8, 0, 0]),
              (if fill: rgb(d.fill) else: [0'u8, 0, 0]))
    if st notin styleIds:
      styleIds[st] = result.styles.len
      result.styles.add Style(kind: st[0], cap: st[1], join: st[2], width: st[3], stroke: st[4], fill: st[5])
    var ops: seq[uint8]
    var xy: seq[int64]
    var cur = (low(int64), low(int64))
    var hasCur = false
    template add(op: uint8, pts: varargs[(int64, int64)]) =
      ops.add op
      for p in pts:
        xy.add p[0]
        xy.add p[1]
    for it in d.items:
      case it.cmd
      of 'l', 'c':
        let a = tf(m, it.p[0], it.p[1])
        if not hasCur or a != cur:
          add(OpMove, a)
        if it.cmd == 'l':
          cur = tf(m, it.p[2], it.p[3])
          add(OpLine, cur)
        else:
          let c1 = tf(m, it.p[2], it.p[3])
          let c2 = tf(m, it.p[4], it.p[5])
          cur = tf(m, it.p[6], it.p[7])
          add(OpCubic, c1, c2, cur)
        hasCur = true
      of 'r', 'q':
        var corners: array[4, (float32, float32)]
        if it.cmd == 'r':
          let x0 = min(it.p[0], it.p[2])
          let x1 = max(it.p[0], it.p[2])
          let y0 = min(it.p[1], it.p[3])
          let y1 = max(it.p[1], it.p[3])
          corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        else:   # ul, ur, ll, lr stored; drawn ul, ur, lr, ll
          corners = [(it.p[0], it.p[1]), (it.p[2], it.p[3]), (it.p[6], it.p[7]), (it.p[4], it.p[5])]
        let p0 = tf(m, corners[0][0], corners[0][1])
        add(OpMove, p0)
        for k in 1 .. 3: add(OpLine, tf(m, corners[k][0], corners[k][1]))
        add(OpClose)
        cur = p0
        hasCur = true
      else:
        raise newException(ImportError, "unknown drawing item " & it.cmd)
    if d.closePath == 1: add(OpClose)
    if ops.len == 0: continue
    var x0, y0 = high(int64)
    var x1, y1 = low(int64)
    for i in countup(0, xy.len - 1, 2):
      x0 = min(x0, xy[i]); x1 = max(x1, xy[i])
      y0 = min(y0, xy[i + 1]); y1 = max(y1, xy[i + 1])
    let pad = (wq + 1) div 2 + (if (kind and Hairline) != 0: int64(Q) else: 0)
    result.paths.add pathstore.Path(style: styleIds[st], bbox: [max(0, x0 - pad), max(0, y0 - pad), x1 + pad, y1 + pad],
                                    cmdStart: result.ops.len, cmdCount: ops.len, ptStart: result.xy.len div 2)
    result.ops.add ops
    result.xy.add xy
    seqnos.add d.seqno
  seqnos.sort()
  if images: result.addImages(m, pageImages, seqnos, effort)
