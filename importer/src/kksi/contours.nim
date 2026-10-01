## The holes cv2.findContours(RETR_CCOMP, CHAIN_APPROX_NONE) reports on a binary image (foreground 8-connected): each
## 4-connected background region not connected to the outside, with its border = the pixels of the enclosing
## foreground component that touch the region (4-adjacent), in cv2's order (see `order` below).
## Checked against cv2 on all 11 sheets (tests/diff_holes.nim).

import std/algorithm

type
  Hole* = object
    pts*: seq[(int32, int32)]   ## (x, y), sorted by (y, x), unique
    x*, y*, w*, h*: int         ## cv2.boundingRect

proc findHoles*(fg: openArray[bool], w, h: int, fourAdj = true): seq[Hole] =
  let n = w * h
  # background regions, 4-connected; label 1 = outside (touches the frame)
  var bg = newSeq[int32](n)
  var stack: seq[int32]
  var nb = 1'i32
  template flood(start: int, lab: int32) =
    stack.setLen(0)
    stack.add int32(start)
    bg[start] = lab
    while stack.len > 0:
      let p = int(stack.pop())
      let x = p mod w
      let y = p div w
      template visit(q: int) =
        if not fg[q] and bg[q] == 0:
          bg[q] = lab
          stack.add int32(q)
      if x > 0: visit(p - 1)
      if x < w - 1: visit(p + 1)
      if y > 0: visit(p - w)
      if y < h - 1: visit(p + w)
  for x in 0 ..< w:
    if not fg[x] and bg[x] == 0: flood(x, 1)
    let b = (h - 1) * w + x
    if not fg[b] and bg[b] == 0: flood(b, 1)
  for y in 0 ..< h:
    if not fg[y * w] and bg[y * w] == 0: flood(y * w, 1)
    let r = y * w + w - 1
    if not fg[r] and bg[r] == 0: flood(r, 1)
  var first: seq[int]                  # first pixel (raster) of each hole region, index = label - 2
  for p in 0 ..< n:
    if not fg[p] and bg[p] == 0:
      inc nb
      first.add p
      flood(p, nb)
  let nh = int(nb) - 1
  # foreground components, 8-connected
  var fgl = newSeq[int32](n)
  var nf = 0'i32
  var compFirst = @[0]                 # first pixel (raster) of each foreground component, index = label
  for p in 0 ..< n:
    if fg[p] and fgl[p] == 0:
      inc nf
      compFirst.add p
      stack.setLen(0)
      stack.add int32(p)
      fgl[p] = nf
      while stack.len > 0:
        let q = int(stack.pop())
        let x = q mod w
        let y = q div w
        for dy in -1 .. 1:
          for dx in -1 .. 1:
            let xx = x + dx
            let yy = y + dy
            if xx >= 0 and xx < w and yy >= 0 and yy < h:
              let r = yy * w + xx
              if fg[r] and fgl[r] == 0:
                fgl[r] = nf
                stack.add int32(r)
  var enclosing = newSeq[int32](nh)
  var order = newSeq[(int, int)](nh)
  for i in 0 ..< nh:
    enclosing[i] = fgl[first[i] - w]   # the pixel above the region's first pixel
    # cv2 lists components in reverse order of their outer border's start (the component's first pixel), each
    # followed by its holes in reverse order of their border's start (the pixel left of the region's first pixel)
    order[i] = (compFirst[enclosing[i]], first[i] - 1)
  var holes = newSeq[Hole](nh)
  for p in 0 ..< n:
    if not fg[p]: continue
    let x = p mod w
    let y = p div w
    var seen: array[8, int32]
    var ns = 0
    template check(q: int) =
      let lab = bg[q]
      if not fg[q] and lab >= 2 and enclosing[lab - 2] == fgl[p]:
        var dup = false
        for k in 0 ..< ns:
          if seen[k] == lab: dup = true
        if not dup:
          seen[ns] = lab
          inc ns
          holes[lab - 2].pts.add((int32(x), int32(y)))
    if x > 0: check(p - 1)
    if x < w - 1: check(p + 1)
    if y > 0: check(p - w)
    if y < h - 1: check(p + w)
    if not fourAdj:
      if x > 0 and y > 0: check(p - w - 1)
      if x < w - 1 and y > 0: check(p - w + 1)
      if x > 0 and y < h - 1: check(p + w - 1)
      if x < w - 1 and y < h - 1: check(p + w + 1)
  # cv2 order and bounding rects
  var idx = newSeq[int](nh)
  for i in 0 ..< nh: idx[i] = i
  idx.sort(proc (a, b: int): int = cmp(order[b], order[a]))
  for i in idx:
    var hl = holes[i]
    var x0, y0 = high(int)
    var x1, y1 = -1
    for (px, py) in hl.pts:
      x0 = min(x0, int(px)); x1 = max(x1, int(px))
      y0 = min(y0, int(py)); y1 = max(y1, int(py))
    hl.x = x0
    hl.y = y0
    hl.w = x1 - x0 + 1
    hl.h = y1 - y0 + 1
    result.add hl

