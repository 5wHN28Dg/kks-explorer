## Off-page connectors on the HRSG package sheets: a small circle (about 21 pt across) holding a code such as "C16"
## (C = drain to the trench, A = pressure discharge, D = process line between sheets, S = sampling, V = vent). The
## same code on another sheet is where the pipe continues (mostly the drain sheet). Found from the drawing's vectors,
## read with the KKS glyph library (the same clean / split / classify as the tags).
##
## A circle: one path with Bézier curves (4 or more items), or a polyline of 12 or more segments, roughly square,
## 10–36 pt. Its label: the small stroke-only paths inside it, grouped into blobs by touching boxes (one blob per
## character). Kept only when the reading is a letter followed by 1–2 digits and has as many characters as the circle
## holds blobs: the Block 1 sheets' numbered circles ("5"), the "90" / "R" marks and line junk drop out here.
## Each circle is read upright, then turned clockwise, counter-clockwise (the drain sheet's are vertical), and last
## upside down; the first reading that passes wins.

import std/[tables, math, algorithm]
import mupdf, imgops, fontlib, reader, textlines

type
  Candidate* = object
    circle*: array[4, float]     ## the circle's box, points (the rotated sheet)
    inner*: array[4, float]      ## its label's box
    n*: int                      ## the label's blobs (characters)
    chars*: seq[array[4, float]] ## their boxes
  Connector* = object
    label*: string
    bbox*: array[4, float]       ## the circle's box, points
    conf*: float                 ## the lowest glyph confidence, rounded to 0.01
    turn*: int                   ## how the label was read: 0 upright, 1 turned clockwise, 2 counter-clockwise, 3 upside down

const
  CircleMin = 10.0
  CircleMax = 36.0
  SmallMax = 14.0                ## a character's paths are at most this long
  Touch = 0.35                   ## boxes this close belong to one character

proc isCircle*(p: Path): bool =
  let w = float(p.rect[2] - p.rect[0])
  let h = float(p.rect[3] - p.rect[1])
  if not (w >= CircleMin and w <= CircleMax and h >= CircleMin and h <= CircleMax): return false
  var curves = false
  for it in p.items:
    if it.cmd == 'c': curves = true
  (curves and p.items.len >= 4) or (p.items.len >= 12 and w / max(h, 1e-3) >= 0.8 and w / max(h, 1e-3) <= 1.25)

proc find(p: var seq[int], a: int): int =
  var a = a
  while p[a] != a:
    p[a] = p[p[a]]
    a = p[a]
  a

proc blobs*(paths: seq[Path]): seq[array[4, float]] =
  ## the small unfilled paths, merged while their boxes touch (within Touch): one box per character
  var r: seq[array[4, float]]
  for p in paths:
    if p.hasFill: continue
    let b = [float(p.rect[0]), float(p.rect[1]), float(p.rect[2]), float(p.rect[3])]
    if max(b[2] - b[0], b[3] - b[1]) > SmallMax: continue
    r.add b
  var parent = newSeq[int](r.len)
  for i in 0 ..< r.len: parent[i] = i
  const Cell = 20.0
  var grid = initTable[(int, int), seq[int]]()
  for i, b in r:
    for gx in int(floor((b[0] - Touch) / Cell)) .. int(floor((b[2] + Touch) / Cell)):
      for gy in int(floor((b[1] - Touch) / Cell)) .. int(floor((b[3] + Touch) / Cell)):
        grid.mgetOrPut((gx, gy), @[]).add i
  for v in grid.values:
    for x in 0 ..< v.len:
      for y in x + 1 ..< v.len:
        let a = r[v[x]]
        let b = r[v[y]]
        if a[0] - Touch <= b[2] and b[0] - Touch <= a[2] and a[1] - Touch <= b[3] and b[1] - Touch <= a[3]:
          let ra = find(parent, v[x])
          let rb = find(parent, v[y])
          if ra != rb: parent[ra] = rb
  var byRoot = initOrderedTable[int, array[4, float]]()
  for i, b in r:
    let k = find(parent, i)
    if k in byRoot:
      var u = byRoot[k]
      u = [min(u[0], b[0]), min(u[1], b[1]), max(u[2], b[2]), max(u[3], b[3])]
      byRoot[k] = u
    else: byRoot[k] = b
  for b in byRoot.values: result.add b

proc candidates*(paths: seq[Path]): seq[Candidate] =
  ## circles with 1–3 character blobs inside, one per label box (a circle drawn twice counts once)
  let bl = blobs(paths)
  var seen: seq[array[4, int]]
  for p in paths:
    if not p.isCircle: continue
    let r = [float(p.rect[0]), float(p.rect[1]), float(p.rect[2]), float(p.rect[3])]
    let m = min(r[2] - r[0], r[3] - r[1])
    var inner = [Inf, Inf, -Inf, -Inf]
    var chars: seq[array[4, float]]
    for b in bl:
      if b[0] >= r[0] + 1 and b[2] <= r[2] - 1 and b[1] >= r[1] + 1 and b[3] <= r[3] - 1 and
         max(b[3] - b[1], b[2] - b[0]) > 0.15 * m:
        chars.add b
        inner = [min(inner[0], b[0]), min(inner[1], b[1]), max(inner[2], b[2]), max(inner[3], b[3])]
    let n = chars.len
    if n notin 1 .. 3: continue
    let key = [int(round(inner[0])), int(round(inner[1])), int(round(inner[2])), int(round(inner[3]))]
    if key in seen: continue
    seen.add key
    result.add Candidate(circle: r, inner: inner, n: n, chars: chars)

proc connectorLabel*(s: string, n: int): (bool, string) =
  ## a letter and 1–2 digits, as many characters as blobs; I/O in a digit place are 1/0 (as in KKS codes)
  if s.len notin 2 .. 3 or s.len != n or s[0] notin {'A' .. 'Z'}: return (false, "")
  var t = s
  for i in 1 ..< t.len:
    if t[i] == 'I': t[i] = '1'
    elif t[i] == 'O': t[i] = '0'
    if t[i] notin {'0' .. '9'}: return (false, "")
  (true, t)

proc byBlobs(bw: Bits, y0, y1: int, cuts: seq[float]): seq[Piece] =
  ## the label cut between its characters' vector boxes, each piece trimmed to its ink columns
  var col = newSeq[int](bw.w)
  for y in y0 .. y1:
    for x in 0 ..< bw.w:
      if bw.d[y * bw.w + x]: inc col[x]
  var edges = @[0]
  for c in cuts: edges.add max(0, min(bw.w, int(round(c))))
  edges.add bw.w
  for i in 0 ..< edges.len - 1:
    var a = edges[i]
    var b = edges[i + 1]
    while a < b and col[a] == 0: inc a
    while b > a and col[b - 1] == 0: dec b
    if b > a: result.add Piece(a: a, b: b, sub: bw.sub(a, y0, b, y1 + 1))

proc readBox(doc: Doc, lib: GlyphLib, scores: var seq[float32], c: Candidate, turn: int): (string, float) =
  ## turn: 0 upright, 1 clockwise, 2 counter-clockwise, 3 upside down. The characters are split as the tags'
  ## are (ink columns); when that doesn't give one piece per character blob (bold digits whose ink touches), the
  ## label is cut between the blobs' vector boxes instead.
  let b = c.inner
  let g = doc.renderGray(DpiRead / 72.0, (b[0] - 1.5, b[1] - 1.5, b[2] + 1.5, b[3] + 1.5), hasClip = true)
  var im = imgops.Gray(w: g.w, h: g.h, d: g.data)
  case turn
  of 1: im = rotateCw(im)
  of 2: im = rotateCcw(im)
  of 3: im = rotateCw(rotateCw(im))
  else: discard
  im = border(im, 30, 30, 30, 30, 255)
  let bw = clean(im, newGray(im.w, im.h, 255))
  var (chars, y0, y1) = splitChars(bw)
  if chars.len > 0 and chars.len != c.n and c.n > 1:
    # each blob's extent along the reading direction, in the turned image's columns
    let s = DpiRead / 72.0
    var spans: seq[(float, float)]
    for q in c.chars:
      let (ox0, ox1) = (q[0] * s - float(g.x), q[2] * s - float(g.x))
      let (oy0, oy1) = (q[1] * s - float(g.y), q[3] * s - float(g.y))
      let span = case turn
        of 1: (float(g.h - 1) - oy1, float(g.h - 1) - oy0)
        of 2: (oy0, oy1)
        of 3: (float(g.w - 1) - ox1, float(g.w - 1) - ox0)
        else: (ox0, ox1)
      spans.add((span[0] + 30, span[1] + 30))
    spans.sort()
    var cuts: seq[float]
    for i in 0 ..< spans.len - 1:
      if spans[i + 1][0] > spans[i][1]: cuts.add (spans[i][1] + spans[i + 1][0]) / 2
    if cuts.len == spans.len - 1:   # side by side in this direction (not stacked: the label read the wrong way)
      chars = byBlobs(bw, y0, y1, cuts)
  var conf = 0.0
  if chars.len > 0:
    let hc = y1 - y0 + 1
    var cs: seq[float]
    for p in chars:
      let gl = lib.classify(p.sub, hc, scores)
      if gl.label.len == 0: continue
      result[0].add gl.label
      cs.add gl.conf
    if cs.len > 0: conf = min(cs)
  result[1] = conf

proc findConnectors*(doc: Doc, lib: GlyphLib, paths: seq[Path]): seq[Connector] =
  var scores: seq[float32]
  for c in candidates(paths):
    for turn in 0 .. 3:
      let (s, conf) = readBox(doc, lib, scores, c, turn)
      let (ok, label) = connectorLabel(s, c.n)
      if ok:
        result.add Connector(label: label, bbox: c.circle, conf: pyRoundTo(conf, 2), turn: turn)
        break

proc findConnectors*(doc: Doc, lib: GlyphLib): seq[Connector] = findConnectors(doc, lib, doc.drawings)
