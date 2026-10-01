## extractor/glyphs.load_paths + extractor/textlines (decision 0026): the drawing's short stroke-only paths, chained
## into text lines by drawing order. All arithmetic in doubles, like the Python code.

import std/[algorithm, math]
import mupdf

type
  Seg* = array[4, float]
  VPath* = object
    seq*: int
    segs*: seq[Seg]
    r*: array[4, float]
  Line* = object
    paths*: seq[int]          ## indices into the path list
    axis*: char
  TextLine* = object
    axis*: char
    h*: float                 ## round(H, 2)
    chars*: int
    bbox*: array[4, float]

proc loadPaths*(doc: Doc): seq[VPath] =
  for p in doc.drawings:
    if p.hasFill: continue
    let r = [float(p.rect[0]), float(p.rect[1]), float(p.rect[2]), float(p.rect[3])]
    if max(r[2] - r[0], r[3] - r[1]) > 14: continue
    var segs: seq[Seg]
    var ok = true
    for it in p.items:
      if it.cmd == 'l': segs.add [float(it.p[0]), float(it.p[1]), float(it.p[2]), float(it.p[3])]
      else: ok = false
    if not ok or segs.len == 0: continue
    result.add VPath(seq: p.seqno, segs: segs, r: r)
  result.sort(proc (a, b: VPath): int = cmp(a.seq, b.seq))   # stable, like list.sort

proc buildLines*(paths: seq[VPath]): seq[Line] =
  var i = 0
  let n = paths.len
  while i < n:
    var line = @[i]
    var j = i + 1
    var axis = '\0'
    while j < n and paths[j].seq == paths[line[^1]].seq + 1:
      let a = paths[line[^1]].r
      let b = paths[j].r
      var hh = b[3] - b[1]
      var ww = b[2] - b[0]
      var hq = -Inf
      var wq = -Inf
      for q in line:
        hq = max(hq, paths[q].r[3] - paths[q].r[1])
        wq = max(wq, paths[q].r[2] - paths[q].r[0])
      hh = max(hq, hh)
      ww = max(wq, ww)
      let hc = (b[0] > a[0] - 0.6 * hh and b[0] < a[2] + 0.9 * hh) and (b[1] < a[3] + 0.2 * hh and b[3] > a[1] - 0.2 * hh)
      let vc = (b[1] < a[3] + 0.9 * ww and b[3] > a[1] - 0.9 * ww) and (b[0] < a[2] + 0.2 * ww and b[2] > a[0] - 0.2 * ww)
      if axis == '\0':
        let dx = b[0] - a[0]
        let dy = b[3] - a[3]
        if hc and abs(dy) < 0.35 * hh and dx > -0.2: axis = 'h'
        elif vc and abs(b[0] - a[0]) < 0.35 * ww and dy < 0.2: axis = 'v'
        elif hc: axis = 'h'
        else: break
      if axis == 'h' and hc:
        line.add j; inc j; continue
      if axis == 'v' and vc:
        line.add j; inc j; continue
      break
    result.add Line(paths: line, axis: if axis == '\0': 'h' else: axis)
    i = j

proc pyRoundTo*(x: float, nd: int): float =
  ## Python round(x, nd): the exact binary value rounded to nd decimals (ties to even), via C's printf.
  var buf: array[64, char]
  proc snprintf(s: ptr char, n: csize_t, f: cstring): cint {.importc, header: "<stdio.h>", varargs.}
  discard snprintf(addr buf[0], 64, "%.*f", cint(nd), x)
  var s = ""
  for c in buf:
    if c == '\0': break
    s.add c
  proc strtod(s: cstring, e: pointer): cdouble {.importc, header: "<stdlib.h>".}
  strtod(s.cstring, nil)

proc process*(paths: seq[VPath]): seq[TextLine] =
  for L in buildLines(paths):
    # to_local: vertical lines turned into the horizontal frame
    var lp: seq[(seq[Seg], array[4, float])]
    for q in L.paths:
      var segs: seq[Seg]
      if L.axis == 'h':
        segs = paths[q].segs
      else:
        for s in paths[q].segs: segs.add [-s[1], s[0], -s[3], s[2]]
      var x0 = Inf
      var y0 = Inf
      var x1 = -Inf
      var y1 = -Inf
      for s in segs:
        x0 = min(x0, min(s[0], s[2])); x1 = max(x1, max(s[0], s[2]))
        y0 = min(y0, min(s[1], s[3])); y1 = max(y1, max(s[1], s[3]))
      lp.add((segs, [x0, y0, x1, y1]))
    var hh = -Inf
    for (_, r) in lp: hh = max(hh, r[3] - r[1])
    if hh < 2.5: continue
    # split_chars: only the count is used
    var chars: seq[array[4, float]]
    for (_, r) in lp:
      let (x0, y0, x1, y1) = (r[0], r[1], r[2], r[3])
      if chars.len > 0:
        let c = chars[^1]
        let (cx0, cx1) = (c[0], c[2])
        let ov = min(x1, cx1) - max(x0, cx0)
        let w = max(min(x1 - x0, cx1 - cx0), 0.05)
        let contained = (x0 >= cx0 - 0.25 and x1 <= cx1 + 0.25) or (cx0 >= x0 - 0.25 and cx1 <= x1 + 0.25)
        if (ov >= 0.5 * w - 0.05 and ov > 0.15) or contained:
          chars[^1] = [min(x0, cx0), min(y0, c[1]), max(x1, cx1), max(y1, c[3])]
          continue
      chars.add r
    var bb = [Inf, Inf, -Inf, -Inf]
    for q in L.paths:
      let r = paths[q].r
      bb[0] = min(bb[0], r[0]); bb[1] = min(bb[1], r[1]); bb[2] = max(bb[2], r[2]); bb[3] = max(bb[3], r[3])
    result.add TextLine(axis: L.axis, h: pyRoundTo(hh, 2), chars: chars.len, bbox: bb)

proc score*(paths: seq[VPath]): (int, int) =
  ## orient.score: lines of 6+ paths, horizontal and vertical
  for L in buildLines(paths):
    if L.paths.len >= 6:
      if L.axis == 'h': inc result[0] else: inc result[1]
