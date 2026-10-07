## The OpenCV operations the reader uses (decision 0026), ported from OpenCV 5.0.0 (Apache-2.0) where the exact
## pixels matter: convexHull (Sklansky), fillPoly (CollectPolyEdges + FillEdgeCollection, LINE_8, shift 0),
## erode (rectangular kernel, default border = ignored), rotate, copyMakeBorder, connectedComponentsWithStats
## (8-connected; labels in raster order of each component's first pixel), resize INTER_AREA and a 3×3 Gaussian on
## float32. The float operations follow OpenCV's scalar code; cv2's SIMD/IPP paths may differ in the last bit, which
## tests/diff_trace.nim measures on the real glyphs.

import std/[algorithm, math]
when defined(traceResize): import std/strutils

proc fmaf(a, b, c: cfloat): cfloat {.importc, header: "<math.h>".}

type
  Gray* = object
    w*, h*: int
    d*: seq[uint8]
  Pt* = tuple[x, y: int32]

proc newGray*(w, h: int, fill = 0'u8): Gray =
  result = Gray(w: w, h: h, d: newSeq[uint8](w * h))
  if fill != 0:
    for i in 0 ..< result.d.len: result.d[i] = fill

template at*(g: Gray, x, y: int): uint8 = g.d[y * g.w + x]

# ---- convexHull (modules/geometry/src/convhull.cpp, integer points, clockwise=false, returnPoints) ----

proc sklansky(arr: seq[Pt], start, endIn: int, stack: var seq[int], base: int, nsign, sign2: int): int =
  var `end` = endIn
  let incr = if `end` > start: 1 else: -1
  var pprev = start
  var pcur = pprev + incr
  var pnext = pcur + incr
  var stacksize = 3
  if start == `end` or (arr[start].x == arr[`end`].x and arr[start].y == arr[`end`].y):
    stack[base] = start
    return 1
  stack[base] = pprev
  stack[base + 1] = pcur
  stack[base + 2] = pnext
  `end` += incr
  while pnext != `end`:
    let cury = int64(arr[pcur].y)
    let nexty = int64(arr[pnext].y)
    let by = nexty - cury
    if sgn(by) != nsign:
      let a0 = int64(arr[pcur].x) - int64(arr[pprev].x)
      let a1 = cury - int64(arr[pprev].y)
      let b0 = int64(arr[pnext].x) - int64(arr[pcur].x)
      let b1 = by
      let convexity = a1 * b0 - a0 * b1
      if sgn(convexity) == sign2 and (a0 != 0 or a1 != 0):
        pprev = pcur
        pcur = pnext
        pnext += incr
        stack[base + stacksize] = pnext
        inc stacksize
      else:
        if pprev == start:
          pcur = pnext
          stack[base + 1] = pcur
          pnext += incr
          stack[base + 2] = pnext
        else:
          stack[base + stacksize - 2] = pnext
          pcur = pprev
          pprev = stack[base + stacksize - 4]
          dec stacksize
    else:
      pnext += incr
      stack[base + stacksize - 1] = pnext
  dec stacksize
  stacksize

proc convexHull*(pts: openArray[Pt]): seq[Pt] =
  let total = pts.len
  if total == 0: return
  var p = @pts
  p.sort(proc (a, b: Pt): int =
    if a.x != b.x: cmp(a.x, b.x) else: cmp(a.y, b.y))
  var miny = 0
  var maxy = 0
  for i in 1 ..< total:
    if p[miny].y > p[i].y: miny = i
    if p[maxy].y < p[i].y: maxy = i
  if p[0] == p[total - 1]:
    return @[p[0]]
  var stack = newSeq[int](total + 2)
  var hull: seq[int]
  # upper half
  var tlBase = 0
  var tlCount = sklansky(p, 0, maxy, stack, tlBase, -1, 1)
  var trBase = tlCount
  var trCount = sklansky(p, total - 1, maxy, stack, trBase, -1, -1)
  # clockwise = false: swap
  swap(tlBase, trBase)
  swap(tlCount, trCount)
  for i in 0 ..< tlCount - 1: hull.add stack[tlBase + i]
  for i in countdown(trCount - 1, 1): hull.add stack[trBase + i]
  let stopIdx = if trCount > 2: stack[trBase + 1] elif tlCount > 2: stack[tlBase + tlCount - 2] else: -1
  # lower half (stack is reused from the start, like OpenCV)
  var blBase = 0
  var blCount = sklansky(p, 0, miny, stack, blBase, 1, -1)
  var brBase = blCount
  var brCount = sklansky(p, total - 1, miny, stack, brBase, 1, 1)
  if stopIdx >= 0:
    let checkIdx = if blCount > 2: stack[blBase + 1]
                   elif blCount + brCount > 2: stack[brBase + 2 - blCount]
                   else: -1
    if checkIdx == stopIdx or (checkIdx >= 0 and p[checkIdx] == p[stopIdx]):
      blCount = min(blCount, 2)
      brCount = min(brCount, 2)
  for i in 0 ..< blCount - 1: hull.add stack[blBase + i]
  for i in countdown(brCount - 1, 1): hull.add stack[brBase + i]
  for i in hull: result.add p[i]

proc contourArea*(poly: openArray[Pt]): float =
  ## cv2.contourArea(poly) (not oriented).
  if poly.len == 0: return 0
  var a = 0.0
  var prev = poly[^1]
  for q in poly:
    a += float(prev.x) * float(q.y) - float(prev.y) * float(q.x)
    prev = q
  abs(a * 0.5)

# ---- fillPoly (modules/imgproc/src/drawing.cpp, LINE_8, shift 0, one contour) ----

const
  XyShift = 16
  XyOne = 1'i64 shl XyShift

proc clipLine(w, h: int64, x1, y1, x2, y2: var int64): bool =
  let right = w - 1
  let bottom = h - 1
  if w <= 0 or h <= 0: return false
  var c1 = int(x1 < 0) + int(x1 > right) * 2 + int(y1 < 0) * 4 + int(y1 > bottom) * 8
  var c2 = int(x2 < 0) + int(x2 > right) * 2 + int(y2 < 0) * 4 + int(y2 > bottom) * 8
  if (c1 and c2) == 0 and (c1 or c2) != 0:
    var a: int64
    if (c1 and 12) != 0:
      a = if c1 < 8: 0 else: bottom
      x1 += int64(float(a - y1) * float(x2 - x1) / float(y2 - y1))
      y1 = a
      c1 = int(x1 < 0) + int(x1 > right) * 2
    if (c2 and 12) != 0:
      a = if c2 < 8: 0 else: bottom
      x2 += int64(float(a - y2) * float(x2 - x1) / float(y2 - y1))
      y2 = a
      c2 = int(x2 < 0) + int(x2 > right) * 2
    if (c1 and c2) == 0 and (c1 or c2) != 0:
      if c1 != 0:
        a = if c1 == 1: 0 else: right
        y1 += int64(float(a - x1) * float(y2 - y1) / float(x2 - x1))
        x1 = a
        c1 = 0
      if c2 != 0:
        a = if c2 == 1: 0 else: right
        y2 += int64(float(a - x2) * float(y2 - y1) / float(x2 - x1))
        x2 = a
        c2 = 0
  (c1 or c2) == 0

proc line8(img: var Gray, p1x, p1y, p2x, p2y: int, color: uint8) =
  ## Line() with LineIterator(connectivity 8, leftToRight).
  var x1 = int64(p1x)
  var y1 = int64(p1y)
  var x2 = int64(p2x)
  var y2 = int64(p2y)
  if x1 < 0 or x1 >= img.w or x2 < 0 or x2 >= img.w or y1 < 0 or y1 >= img.h or y2 < 0 or y2 >= img.h:
    # clipLine(Size, Point&, Point&): int Points, through the int64 version
    if not clipLine(img.w, img.h, x1, y1, x2, y2): return
    x1 = int64(int32(x1)); y1 = int64(int32(y1)); x2 = int64(int32(x2)); y2 = int64(int32(y2))
  var px = int(x1)
  var py = int(y1)
  var dx = int(x2 - x1)
  var dy = int(y2 - y1)
  var deltaX = 1
  var deltaY = 1
  if dx < 0:
    dx = -dx
    dy = -dy
    px = int(x2)
    py = int(y2)
  if dy < 0:
    dy = -dy
    deltaY = -1
  let vert = dy > dx
  if vert:
    swap(dx, dy)
    swap(deltaX, deltaY)
  var err = dx - (dy + dy)
  let plusDelta = dx + dx
  let minusDelta = -(dy + dy)
  # (x, y) moves: minus always, plus when err < 0
  var minusX, minusY, plusX, plusY: int
  if not vert:
    minusX = deltaX; minusY = 0; plusX = 0; plusY = deltaY
  else:
    minusX = 0; minusY = deltaX; plusX = deltaY; plusY = 0
  let count = dx + 1
  for i in 0 ..< count:
    img.d[py * img.w + px] = color
    let neg = err < 0
    err += minusDelta + (if neg: plusDelta else: 0)
    px += minusX + (if neg: plusX else: 0)
    py += minusY + (if neg: plusY else: 0)

type PolyEdge = object
  y0, y1: int
  x, dx: int64
  next: int    # index into edges, -1 = none

proc fillPoly*(img: var Gray, v: openArray[Pt], color: uint8) =
  let count = v.len
  if count == 0: return
  var edges: seq[PolyEdge]
  var pt0x = int64(v[count - 1].x) shl XyShift
  var pt0y = int64(v[count - 1].y)
  for i in 0 ..< count:
    let pt1x = int64(v[i].x) shl XyShift
    let pt1y = int64(v[i].y)
    var c0x = pt0x
    var c0y = pt0y
    var c1x = pt1x
    var c1y = pt1y
    var t0x = (pt0x + (XyOne shr 1)) shr XyShift
    var t0y = pt0y
    var t1x = (pt1x + (XyOne shr 1)) shr XyShift
    var t1y = pt1y
    line8(img, int(t0x), int(t0y), int(t1x), int(t1y), color)
    if t0x < 0 or t0x >= img.w or t1x < 0 or t1x >= img.w or t0y < 0 or t0y >= img.h or t1y < 0 or t1y >= img.h:
      discard clipLine(img.w, img.h, t0x, t0y, t1x, t1y)
      if t0y != t1y:
        c0y = t0y
        c1y = t1y
    c0x = t0x shl XyShift
    c1x = t1x shl XyShift
    if pt0y != pt1y:
      var e = PolyEdge(next: -1)
      e.dx = (c1x - c0x) div (c1y - c0y)
      if pt0y < pt1y:
        e.y0 = int(pt0y); e.y1 = int(pt1y)
        e.x = c0x + (pt0y - c0y) * e.dx
      else:
        e.y0 = int(pt1y); e.y1 = int(pt0y)
        e.x = c1x + (pt1y - c1y) * e.dx
      edges.add e
    pt0x = pt1x
    pt0y = pt1y
  # FillEdgeCollection
  let total = edges.len
  if total < 2: return
  var yMax = low(int)
  var yMin = high(int)
  var xMax = low(int64)
  var xMin = high(int64)
  for e in edges:
    let x1 = e.x + int64(e.y1 - e.y0) * e.dx
    yMin = min(yMin, e.y0); yMax = max(yMax, e.y1)
    xMin = min(xMin, e.x); xMax = max(xMax, e.x)
    xMin = min(xMin, x1); xMax = max(xMax, x1)
  if yMax < 0 or yMin >= img.h or xMax < 0 or xMin >= (int64(img.w) shl XyShift): return
  edges.sort(proc (a, b: PolyEdge): int =
    if a.y0 != b.y0: cmp(a.y0, b.y0) elif a.x != b.x: cmp(a.x, b.x) else: cmp(a.dx, b.dx))
  edges.add PolyEdge(y0: high(int), next: -1)       # sentinel
  let tmp = edges.len                               # index of the list head ("tmp" in OpenCV)
  edges.add PolyEdge(next: -1)
  var i = 0
  var e = 0
  yMax = min(yMax, img.h)
  let delta = XyOne - 1
  var y = edges[e].y0
  while y < yMax:
    var draw = false
    let clipline = y < 0
    var prelast = tmp
    var last = edges[tmp].next
    while last >= 0 or edges[e].y0 == y:
      if last >= 0 and edges[last].y1 == y:
        edges[prelast].next = edges[last].next
        last = edges[last].next
        continue
      let keepPrelast = prelast
      if last >= 0 and (edges[e].y0 > y or edges[last].x < edges[e].x):
        prelast = last
        last = edges[last].next
      elif i < total:
        edges[prelast].next = e
        edges[e].next = last
        prelast = e
        inc i
        e = i
      else:
        break
      if draw:
        if not clipline:
          var x1, x2: int
          if edges[keepPrelast].x > edges[prelast].x:
            x1 = int((edges[prelast].x + delta) shr XyShift)
            x2 = int(edges[keepPrelast].x shr XyShift)
          else:
            x1 = int((edges[keepPrelast].x + delta) shr XyShift)
            x2 = int(edges[prelast].x shr XyShift)
          if x1 < img.w and x2 >= 0:
            if x1 < 0: x1 = 0
            if x2 >= img.w: x2 = img.w - 1
            for x in x1 .. x2: img.d[y * img.w + x] = color
        edges[keepPrelast].x += edges[keepPrelast].dx
        edges[prelast].x += edges[prelast].dx
      draw = not draw
    # bubble sort of the active list by x
    var keepPrelast = -1
    while true:
      prelast = tmp
      last = edges[tmp].next
      var lastExchange = -1
      while last != keepPrelast and last >= 0 and edges[last].next >= 0:
        let te = edges[last].next
        if edges[last].x > edges[te].x:
          edges[prelast].next = te
          edges[last].next = edges[te].next
          edges[te].next = last
          prelast = te
          lastExchange = prelast
        else:
          prelast = last
          last = te
      if lastExchange < 0: break
      keepPrelast = lastExchange
      if keepPrelast == edges[tmp].next or keepPrelast == tmp: break
    inc y

# ---- morphology, geometry ----

proc erode*(src: Gray, r: int): Gray =
  ## cv2.erode with a (2r+1)² rectangle (3×3 with iterations=r gives the same), default border (ignored).
  let w = src.w
  let h = src.h
  var tmp = newGray(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      var m = 255'u8
      for xx in max(0, x - r) .. min(w - 1, x + r):
        m = min(m, src.d[y * w + xx])
      tmp.d[y * w + x] = m
  result = newGray(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      var m = 255'u8
      for yy in max(0, y - r) .. min(h - 1, y + r):
        m = min(m, tmp.d[yy * w + x])
      result.d[y * w + x] = m

proc rotateCw*(src: Gray): Gray =
  ## cv2.ROTATE_90_CLOCKWISE: dst(x', y') with x' = h-1-y, y' = x.
  result = newGray(src.h, src.w)
  for y in 0 ..< src.h:
    for x in 0 ..< src.w:
      result.d[x * result.w + (src.h - 1 - y)] = src.d[y * src.w + x]

proc rotateCcw*(src: Gray): Gray =
  result = newGray(src.h, src.w)
  for y in 0 ..< src.h:
    for x in 0 ..< src.w:
      result.d[(src.w - 1 - x) * result.w + y] = src.d[y * src.w + x]

proc border*(src: Gray, top, bottom, left, right: int, value: uint8): Gray =
  result = newGray(src.w + left + right, src.h + top + bottom, value)
  for y in 0 ..< src.h:
    for x in 0 ..< src.w:
      result.d[(y + top) * result.w + x + left] = src.d[y * src.w + x]

proc rows*(src: Gray, y0, y1: int): Gray =
  ## src[y0:y1] (rows y0 ..< y1).
  result = newGray(src.w, y1 - y0)
  for i in 0 ..< result.d.len: result.d[i] = src.d[y0 * src.w + i]

# ---- connected components ----

type
  Stat* = object
    x*, y*, w*, h*, area*: int
  Components* = object
    n*: int                 ## labels incl. background 0
    labels*: seq[int32]
    stats*: seq[Stat]       ## index = label; [0] unused

proc components*(bw: openArray[bool], w, h: int): Components =
  ## connectedComponentsWithStats(bw, 8). OpenCV's labeller (Spaghetti) works on 2×2 blocks, so its labels follow
  ## the raster order of each component's first block (pixels of one block are always one component).
  var labels = newSeq[int32](w * h)
  var stats = @[Stat()]
  var firstBlock = @[(0, 0)]
  var stack: seq[int32]
  var n = 0'i32
  for p in 0 ..< w * h:
    if bw[p] and labels[p] == 0:
      inc n
      var s = Stat(x: high(int), y: high(int))
      var x1 = -1
      var y1 = -1
      var fb = (high(int), high(int))
      stack.setLen(0)
      stack.add int32(p)
      labels[p] = n
      while stack.len > 0:
        let q = int(stack.pop())
        let x = q mod w
        let y = q div w
        fb = min(fb, (y div 2, x div 2))
        inc s.area
        s.x = min(s.x, x); s.y = min(s.y, y); x1 = max(x1, x); y1 = max(y1, y)
        for dy in -1 .. 1:
          let yy = y + dy
          if yy < 0 or yy >= h: continue
          for dx in -1 .. 1:
            let xx = x + dx
            if xx < 0 or xx >= w: continue
            let r = yy * w + xx
            if bw[r] and labels[r] == 0:
              labels[r] = n
              stack.add int32(r)
      s.w = x1 - s.x + 1
      s.h = y1 - s.y + 1
      stats.add s
      firstBlock.add fb
  var order = newSeq[int](int(n))
  for i in 0 ..< int(n): order[i] = i + 1
  order.sort(proc (a, b: int): int = cmp(firstBlock[a], firstBlock[b]))
  var newLabel = newSeq[int32](int(n) + 1)
  result.stats = @[Stat()]
  for i, old in order:
    newLabel[old] = int32(i + 1)
    result.stats.add stats[old]
  result.labels = newSeq[int32](w * h)
  for p in 0 ..< w * h: result.labels[p] = newLabel[labels[p]]
  result.n = int(n) + 1

# ---- float32 resize (INTER_AREA) and Gaussian blur ----

type FImg* = object
  w*, h*: int
  d*: seq[float32]

proc areaTab(ssize, dsize: int, scale: float): seq[(int, int, float32)] =
  ## computeResizeAreaTab: (di, si, alpha)
  for dx in 0 ..< dsize:
    let fsx1 = float(dx) * scale
    let fsx2 = fsx1 + scale
    let cellWidth = min(scale, float(ssize) - fsx1)
    var sx1 = int(ceil(fsx1))
    var sx2 = int(floor(fsx2))
    sx2 = min(sx2, ssize - 1)
    sx1 = min(sx1, sx2)
    if float(sx1) - fsx1 > 1e-3:
      result.add((dx, sx1 - 1, float32((float(sx1) - fsx1) / cellWidth)))
    for sx in sx1 ..< sx2:
      result.add((dx, sx, float32(1.0 / cellWidth)))
    if fsx2 - float(sx2) > 1e-3:
      result.add((dx, sx2, float32(min(min(fsx2 - float(sx2), 1.0), cellWidth) / cellWidth)))

proc linearTab(ssize, dsize: int, scale, invScale: float): seq[(int, float32)] =
  ## The INTER_AREA emulation for upscaling (resize.cpp, area_mode): per dst index, source index + fraction.
  for dx in 0 ..< dsize:
    var sx = int(floor(float(dx) * scale))
    var fx = float32(float(dx + 1) - float(sx + 1) * invScale)
    fx = if fx <= 0: 0'f32 else: fx - float32(floor(fx))
    if sx < 0:
      fx = 0; sx = 0
    if sx + 1 >= ssize:
      if sx >= ssize - 1:
        fx = 0; sx = ssize - 1
    result.add((sx, fx))

proc resizeArea*(src: FImg, dw, dh: int): FImg =
  result = FImg(w: dw, h: dh, d: newSeq[float32](dw * dh))
  if dw == src.w and dh == src.h:
    result.d = src.d
    return
  let invX = float(dw) / float(src.w)
  let invY = float(dh) / float(src.h)
  let scaleX = 1.0 / invX
  let scaleY = 1.0 / invY
  if scaleX >= 1 and scaleY >= 1:
    let ix = int(round(scaleX))
    let iy = int(round(scaleY))
    if abs(scaleX - float(ix)) < 2.220446049250313e-16 and abs(scaleY - float(iy)) < 2.220446049250313e-16:
      # resizeAreaFast_: mean of each ix × iy block
      let area = float32(ix * iy)
      let sc = 1'f32 / area
      for dy in 0 ..< dh:
        for dx in 0 ..< dw:
          var s = 0'f32
          for sy in 0 ..< iy:
            for sx in 0 ..< ix:
              s += src.d[(dy * iy + sy) * src.w + dx * ix + sx]
          result.d[dy * dw + dx] = s * sc
      return
    let xt = areaTab(src.w, dw, scaleX)
    let yt = areaTab(src.h, dh, scaleY)
    when defined(traceResize):
      echo "scale ", scaleX, " ", scaleY
      for t in xt: echo "xt ", t[0], " ", t[1], " ", cast[uint32](t[2])
      for t in yt[0 .. min(8, yt.high)]: echo "yt ", t[0], " ", t[1], " ", cast[uint32](t[2])
    var buf = newSeq[float32](dw)
    var sum = newSeq[float32](dw)
    var prevDy = yt[0][0]
    for (dy, sy, beta) in yt:
      for k in 0 ..< dw: buf[k] = 0
      for (dxn, sxn, alpha) in xt:
        buf[dxn] += src.d[sy * src.w + sxn] * alpha
        when defined(traceResize):
          if src.w == 4 and src.h == 44 and dxn == 2 and dy == 6: echo "buf ", sy, " ", sxn, " ", toHex(cast[uint32](src.d[sy * src.w + sxn])), " ", toHex(cast[uint32](buf[dxn]))
      if dy != prevDy:
        for k in 0 ..< dw: result.d[prevDy * dw + k] = sum[k]
        for k in 0 ..< dw: sum[k] = beta * buf[k]
        prevDy = dy
        when defined(traceResize):
          if src.w == 4 and src.h == 44 and dy == 6: echo "sum0 ", sy, " ", toHex(cast[uint32](sum[2]))
      else:
        for k in 0 ..< dw: sum[k] += beta * buf[k]
        when defined(traceResize):
          if src.w == 4 and src.h == 44 and dy == 6: echo "sum ", sy, " ", toHex(cast[uint32](sum[2]))
    for k in 0 ..< dw: result.d[prevDy * dw + k] = sum[k]
    return
  # bilinear with area coefficients (resizeGeneric_ HResizeLinear + VResizeLinear, float)
  let xt = linearTab(src.w, dw, scaleX, invX)
  let yt = linearTab(src.h, dh, scaleY, invY)
  var rowsH = newSeq[seq[float32]](src.h)
  proc hrow(sy: int): seq[float32] =
    result = newSeq[float32](dw)
    for dx in 0 ..< dw:
      let (sx, fx) = xt[dx]
      let a0 = 1'f32 - fx
      let s1 = min(sx + 1, src.w - 1)
      result[dx] = src.d[sy * src.w + sx] * a0 + src.d[sy * src.w + s1] * fx
  for dy in 0 ..< dh:
    let (sy, fy) = yt[dy]
    let sy1 = min(sy + 1, src.h - 1)
    if rowsH[sy].len == 0: rowsH[sy] = hrow(sy)
    if rowsH[sy1].len == 0: rowsH[sy1] = hrow(sy1)
    let b0 = 1'f32 - fy
    for dx in 0 ..< dw:
      result.d[dy * dw + dx] = rowsH[sy][dx] * b0 + rowsH[sy1][dx] * fy

proc gaussian3*(src: FImg, sigma: float): FImg =
  ## GaussianBlur(ksize 3×3, sigma) on float32, BORDER_REFLECT_101: sepFilter2D's symmetric 3-tap row and column
  ## filters as cv2's AVX2 build computes them, with fused multiply-adds (also in the scalar tail: the compiler
  ## contracts it). Matched bit for bit in tests/diff_ops.nim.
  var k: array[3, float]
  let s2 = -0.5 / (sigma * sigma)
  var total = 0.0
  for i in 0 .. 2:
    let x = float(i - 1)
    k[i] = exp(s2 * x * x)
    total += k[i]
  var kf: array[3, float32]
  for i in 0 .. 2: kf[i] = float32(k[i] / total)
  let w = src.w
  let h = src.h
  proc refl(i, n: int): int =
    if n == 1: 0 elif i < 0: -i elif i >= n: 2 * n - 2 - i else: i
  var tmp = newSeq[float32](w * h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      let a = src.d[y * w + refl(x - 1, w)]
      let b = src.d[y * w + x]
      let c = src.d[y * w + refl(x + 1, w)]
      tmp[y * w + x] = fmaf(b, kf[1], (a + c) * kf[0])
  result = FImg(w: w, h: h, d: newSeq[float32](w * h))
  for y in 0 ..< h:
    for x in 0 ..< w:
      let a = tmp[refl(y - 1, h) * w + x]
      let b = tmp[y * w + x]
      let c = tmp[refl(y + 1, h) * w + x]
      result.d[y * w + x] = fmaf(a + c, kf[0], b * kf[1])
