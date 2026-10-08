## Valve types from the drawing's symbols (backlog 3). The P&IDs draw a valve as an "X" between two sides (a bowtie),
## or inside a box (a control valve), with marks around it: a full centre line (gate), a stem ending in a square
## (motor actuator) or in a bar (T handle: the legend's JAM VALVE), an inner bar near one end (check; with a stem:
## min-flow), and hatching (drawn closed). This module finds those symbols in the sheet's vector paths, names them
## by the HRSG legend, and links each valve tag (component AA) to its symbol.
##
## Only sheets that carry the HRSG legend table get types: the legend is recognised on the sheet itself (a row of
## GATE, GLOBE, ELECTRIC GATE, ELECTRIC GLOBE, ELECTRIC CONTROL, … CHECK symbols). Other drawing families draw
## the same shapes with other meanings (a plain bowtie is a globe valve here, a shut-off valve in DIN/Siemens), so
## without the legend nothing is named.
##
## All geometry is in "units" of half a point (2 per pt), the frame the rules were tuned in; bboxes are converted
## to the sheet's level-0 px at the end. Pure: no I/O, no MuPDF (tests/test_valves.nim builds drawings by hand).

import std/[math, tables, algorithm, sets, sequtils]
import kks/[pathstore, json]

const
  U = 2.0              ## units per point
  LinkMax = 25.0       ## a tag links to its symbol when the gap (box to box) is at most this …
  LinkMargin = 15.0    ## … and the next symbol is at least this much further away
  HatchMin = 6         ## strokes inside the body from which it counts as hatched (drawn closed)

type
  Seg = object
    x0, y0, x1, y1: float

  SegGrid = object
    cell: float
    g: Table[(int, int), seq[int32]]
    stamp: seq[int32]
    gen: int32

  Symbol* = object
    cx*, cy*, w*, h*: float      ## centre and size of the X (units)
    horiz*: bool                 ## the flow runs left-right
    body*: string                ## "box" · "bowtie" · "X-open" (one side missing) · "X" (no side: not a valve)
    gate*, actuator*, tHandle*: bool
    stemLo*, stemHi*: float      ## the centre line's extent across the flow, in half-sizes of the body
    inbar*: seq[float]           ## across-flow bars inside the body (check valve marker), along-flow position
    hatch*: int                  ## short strokes inside the body
    kind*: string                ## the legend's name, e.g. "globe valve"
    legend*: bool                ## part of the legend table, never linked

  ValveTag* = object
    id*: string
    bbox*: array[4, float]       ## level-0 px

  Link* = object
    tag*: string
    sym*: int                    ## index into the symbols; -1 = not linked
    gap*, next*: float           ## units; next = the nearest other symbol not paired with another tag (Inf: none)
    conf*: float

  SheetValves* = object
    hasLegend*: bool
    symbols*: seq[Symbol]
    links*: seq[Link]            ## one per valve tag, in the order given

# ---------------------------------------------------------------- segments and their grid

proc segments*(d: Drawing, k: float): seq[Seg] =
  ## every straight piece of every stroked path, the coordinates times k (curves skipped, closes included)
  for p in d.paths:
    if (d.styles[p.style].kind and Stroke) == 0: continue
    var pt = p.ptStart
    var cx, cy, sx, sy = 0.0
    for i in p.cmdStart ..< p.cmdStart + p.cmdCount:
      case d.ops[i]
      of OpMove:
        cx = float(d.xy[2 * pt]) * k
        cy = float(d.xy[2 * pt + 1]) * k
        sx = cx
        sy = cy
        inc pt
      of OpLine:
        let nx = float(d.xy[2 * pt]) * k
        let ny = float(d.xy[2 * pt + 1]) * k
        result.add Seg(x0: cx, y0: cy, x1: nx, y1: ny)
        cx = nx
        cy = ny
        inc pt
      of OpCubic:
        cx = float(d.xy[2 * (pt + 2)]) * k
        cy = float(d.xy[2 * (pt + 2) + 1]) * k
        pt += 3
      else:
        if cx != sx or cy != sy: result.add Seg(x0: cx, y0: cy, x1: sx, y1: sy)
        cx = sx
        cy = sy

proc initGrid(s: seq[Seg], cell = 20.0): SegGrid =
  result.cell = cell
  result.stamp = newSeq[int32](s.len)
  for k, q in s:
    for gx in int(floor(min(q.x0, q.x1) / cell)) .. int(floor(max(q.x0, q.x1) / cell)):
      for gy in int(floor(min(q.y0, q.y1) / cell)) .. int(floor(max(q.y0, q.y1) / cell)):
        result.g.mgetOrPut((gx, gy), @[]).add int32(k)

proc query(g: var SegGrid, x0, y0, x1, y1: float): seq[int32] =
  inc g.gen
  for gx in int(floor(x0 / g.cell)) .. int(floor(x1 / g.cell)):
    for gy in int(floor(y0 / g.cell)) .. int(floor(y1 / g.cell)):
      for k in g.g.getOrDefault((gx, gy)):
        if g.stamp[k] != g.gen:
          g.stamp[k] = g.gen
          result.add k
  result.sort()

# ---------------------------------------------------------------- the X finder

proc findX(s: seq[Seg], g: var SegGrid, rmin = 7.0, rmax = 70.0): seq[Symbol] =
  ## points where diagonal ink reaches out symmetrically in all four diagonal directions
  let n = s.len
  var dx, dy, ln, ang = newSeq[float](n)
  var isDiag = newSeq[bool](n)
  for k, q in s:
    dx[k] = q.x1 - q.x0
    dy[k] = q.y1 - q.y0
    ln[k] = hypot(dx[k], dy[k])
    var a = radToDeg(arctan2(dy[k], dx[k]))
    a = a - 180.0 * floor(a / 180.0)
    ang[k] = a
    isDiag[k] = ln[k] > 4 and ((a > 15 and a < 75) or (a > 105 and a < 165))
  var cands: HashSet[(int, int)]
  for k in 0 ..< n:
    if not isDiag[k]: continue
    if ln[k] > 2 * rmin: cands.incl (int(round((s[k].x0 + s[k].x1) / 2)), int(round((s[k].y0 + s[k].y1) / 2)))
    if ln[k] > rmin:
      cands.incl (int(round(s[k].x0)), int(round(s[k].y0)))
      cands.incl (int(round(s[k].x1)), int(round(s[k].y1)))
  var cl: seq[(int, int)]
  for c in cands: cl.add c
  cl.sort()
  type Found = object
    cx, cy, r, a: float
  var found: seq[Found]
  for (ix, iy) in cl:
    let cx = float(ix)
    let cy = float(iy)
    var reach: array[4, float]
    var angs: array[4, float]
    for k in g.query(cx - 2, cy - 2, cx + 2, cy + 2):
      if not isDiag[k]: continue
      let ux = dx[k] / ln[k]
      let uy = dy[k] / ln[k]
      let t = (cx - s[k].x0) * ux + (cy - s[k].y0) * uy
      if t < -1.5 or t > ln[k] + 1.5: continue
      if abs((cx - s[k].x0) * uy - (cy - s[k].y0) * ux) > 1.2: continue
      for (r, sx, sy) in [(ln[k] - t, ux, uy), (t, -ux, -uy)]:
        if r < 1.5: continue
        let q = (if sx > 0: 2 else: 0) + (if sy > 0: 1 else: 0)
        if r > reach[q]:
          reach[q] = r
          angs[q] = radToDeg(arctan2(abs(sy), abs(sx)))
    if min(reach) <= 0: continue
    if min(reach) < rmin or max(reach) > rmax or max(reach) / min(reach) > 1.35: continue
    if max(angs) - min(angs) > 8: continue
    found.add Found(cx: cx, cy: cy, r: sum(reach) / 4, a: sum(angs) / 4)
  # the biggest X wins; smaller ones whose centre lies inside it are its own pieces
  found.sort(proc (p, q: Found): int = cmp((-p.r, p.cx, p.cy), (-q.r, q.cx, q.cy)))
  var kept: seq[Found]
  for f in found:
    var inside = false
    for o in kept:
      if hypot(f.cx - o.cx, f.cy - o.cy) < 0.5 * o.r:
        inside = true
        break
    if not inside: kept.add f
  for f in kept:
    let a = degToRad(f.a)
    result.add Symbol(cx: f.cx, cy: f.cy, w: 2 * f.r * cos(a), h: 2 * f.r * sin(a))

# ---------------------------------------------------------------- reading the marks around an X

proc classify(s: seq[Seg], g: var SegGrid, x: var Symbol) =
  ## the body and its marks, in a frame where u runs along the flow and v across it, both in half-sizes of the X
  x.horiz = x.w >= x.h
  let a = (if x.horiz: x.w else: x.h) / 2
  let b = (if x.horiz: x.h else: x.w) / 2
  let rr = 3.2 * max(a, b)
  type L = tuple[u0, v0, u1, v1: float]
  var ls: seq[L]
  for k in g.query(x.cx - rr, x.cy - rr, x.cx + rr, x.cy + rr):
    let q = s[k]
    if x.horiz: ls.add ((q.x0 - x.cx) / a, (q.y0 - x.cy) / b, (q.x1 - x.cx) / a, (q.y1 - x.cy) / b)
    else: ls.add ((q.y0 - x.cy) / a, (q.x0 - x.cx) / b, (q.y1 - x.cy) / a, (q.x1 - x.cx) / b)
  proc isv(q: L): bool = abs(q.u0 - q.u1) * a < 1.2     # across the flow
  proc ish(q: L): bool = abs(q.v0 - q.v1) * b < 1.2     # along the flow
  proc cover(lo, hi, p, q: float): bool = min(p, q) <= lo and max(p, q) >= hi
  var sides: array[2, bool]
  var rect: array[2, bool]
  for i, sg in [1.0, -1.0]:
    for q in ls:
      if q.isv and abs(q.u0 - sg) < 0.08 and cover(-0.8, 0.8, q.v0, q.v1): sides[i] = true
      if q.ish and abs(q.v0 - sg) < 0.12 and cover(-0.8, 0.8, q.u0, q.u1): rect[i] = true
  x.body = if rect[0] and rect[1] and sides[0] and sides[1]: "box"
           elif sides[0] and sides[1]: "bowtie"
           elif sides[0] or sides[1]: "X-open"
           else: "X"
  # the centre line: across-flow pieces at u = 0, joined outwards from the centre
  var iv: seq[(float, float)]
  for q in ls:
    if q.isv and abs(q.u0) < 0.06 and min(abs(q.v0), abs(q.v1)) < 3.5: iv.add (min(q.v0, q.v1), max(q.v0, q.v1))
  iv.sort()
  var lo, hi = 0.0
  var changed = true
  while changed:
    changed = false
    for (p, q) in iv:
      if p <= hi + 0.08 and q >= lo - 0.08 and (p < lo or q > hi):
        lo = min(lo, p)
        hi = max(hi, q)
        changed = true
  x.gate = lo < -0.6 and hi > 0.6
  x.stemLo = lo
  x.stemHi = hi
  # an actuator box: two along-flow edges near u = 0 on the same side, outside the body, 8–45 units apart
  var lev = initOrderedTable[int, seq[(float, float)]]()
  for q in ls:
    if q.ish and 0.9 < abs(q.v0) and abs(q.v0) * b < b + 60 and max(abs(q.u0), abs(q.u1)) < 0.9:
      lev.mgetOrPut(int(round(q.v0 * b)), @[]).add (min(q.u0, q.u1), max(q.u0, q.u1))
  var good: seq[int]
  for k, ivs0 in lev:
    var ivs = ivs0
    ivs.sort()
    var (lo2, hi2) = ivs[0]
    for (p, q) in ivs[1 .. ^1]:
      if p <= hi2 + 0.05: hi2 = max(hi2, q)
    if lo2 <= -0.12 and hi2 >= 0.12 and 8 < (hi2 - lo2) * a and (hi2 - lo2) * a < 45: good.add k
  x.actuator = false
  for sg in [-1, 1]:
    var lv: seq[int]
    for v in good:
      if v * sg > 0: lv.add v * sg
    lv.sort()
    # the stem runs from the body to the box's near edge (text beside a valve has upright strokes too)
    let stemEnd = (if sg > 0: hi else: -lo) * b
    if lv.len >= 2 and float(lv[0]) < b + 45 and 8 < lv[^1] - lv[0] and lv[^1] - lv[0] < 45 and
       abs(stemEnd - float(lv[0])) <= 3:
      x.actuator = true
      break
  # a T handle: one along-flow bar at the end of the centre line
  x.tHandle = false
  if not x.actuator:
    for e in [lo, hi]:
      if abs(e) > 1.1:
        for q in ls:
          if q.ish and abs(q.v0 - e) < 0.1 and cover(-0.3, 0.3, q.u0, q.u1):
            x.tHandle = true
  # inner bars: across the flow, inside the body, away from the centre
  var bars: seq[float]
  for q in ls:
    if q.isv and 0.3 < abs(q.u0) and abs(q.u0) < 0.92 and cover(-0.3, 0.3, q.v0, q.v1) and
       max(abs(q.v0), abs(q.v1)) < 1.1:
      let r = round(q.u0 * 10) / 10
      if r notin bars: bars.add r
  bars.sort()
  x.inbar = bars
  # hatching: short slanted strokes inside the body
  x.hatch = 0
  for q in ls:
    if max(abs(q.u0), abs(q.u1)) < 1.0 and max(abs(q.v0), abs(q.v1)) < 1.0 and not q.isv and not q.ish and
       hypot((q.u0 - q.u1) * a, (q.v0 - q.v1) * b) < 1.8 * b:
      inc x.hatch
  x.kind =
    if x.body == "box": "control valve"
    elif x.inbar.len > 0: (if lo < -0.5 or hi > 0.5: "min-flow valve" else: "check valve")
    elif x.actuator: (if x.gate: "gate valve" else: "globe valve")
    elif x.tHandle: "jam valve"
    elif x.gate: "gate valve"
    else: "globe valve"

proc findLegend(xs: var seq[Symbol]): bool =
  ## The HRSG legend's valve row: same-size symbols side by side (centres within 0.6 of a body's height: the
  ## motorised ones sit lower in their cells) that include a gate, a globe, a motorised gate, a motorised globe, a
  ## control and a check valve. Marks them; true when found.
  for i, x in xs:
    if x.body == "X" or not x.horiz: continue
    var row: seq[int]
    var have: HashSet[string]
    for j, y in xs:
      if y.body != "X" and y.horiz and abs(y.cy - x.cy) <= 0.6 * x.h and abs(y.w - x.w) <= 0.15 * x.w and
         abs(y.cx - x.cx) <= 12 * x.w:
        row.add j
        have.incl (if y.actuator: "M " else: "") & y.kind
    if ["gate valve", "globe valve", "M gate valve", "M globe valve", "check valve"].allIt(it in have) and
       ("control valve" in have or "M control valve" in have):
      for j in row: xs[j].legend = true
      result = true

# ---------------------------------------------------------------- tags to symbols

proc bbox*(x: Symbol): array[4, float] = [x.cx - x.w / 2, x.cy - x.h / 2, x.cx + x.w / 2, x.cy + x.h / 2]

proc gap(p, q: array[4, float]): float =
  let dx = max(max(p[0] - q[2], 0.0), q[0] - p[2])
  let dy = max(max(p[1] - q[3], 0.0), q[1] - p[3])
  hypot(dx, dy)

proc isValve*(kks: string): bool =
  ## a valve tag: a full equipment code with component AA
  kks.len == 12 and kks[7 .. 8] == "AA"

proc confidence(x: Symbol, l: Link): float =
  ## a heuristic for sorting what to check first, not a probability: the body's completeness, a clear hatch
  ## reading, and how close and unambiguous the link is
  var c = if x.body in ["box", "bowtie"]: 1.0 else: 0.75
  if x.hatch in 3 .. HatchMin - 1: c *= 0.85
  if x.inbar.len > 0 and x.gate: c *= 0.85        # two markers that the legend never combines
  if l.gap > 6: c *= 1.0 - 0.01 * (l.gap - 6)
  if l.next - l.gap < 2 * LinkMargin: c *= 0.95
  round(c * 100) / 100

proc analyse*(d: Drawing, scale: float, tags: seq[ValveTag], legend = "auto"): SheetValves =
  ## `scale`: the sheet's level-0 px per point; tag boxes in level-0 px. legend: "auto" (look for the HRSG legend
  ## on the sheet), "hrsg" (use it regardless) or "none" (no types).
  let s = segments(d, U / float(Q))
  var g = initGrid(s)
  var xs = findX(s, g)
  var keep: seq[Symbol]
  for x0 in xs:
    var x = x0
    if max(x.w, x.h) <= 12: continue
    classify(s, g, x)
    if x.body != "X": keep.add x
  result.hasLegend = findLegend(keep)
  if legend == "hrsg": result.hasLegend = true
  elif legend == "none": result.hasLegend = false
  result.symbols = keep
  let toU = U / scale
  var tb: seq[array[4, float]]
  for t in tags: tb.add [t.bbox[0] * toU, t.bbox[1] * toU, t.bbox[2] * toU, t.bbox[3] * toU]
  # each tag's nearest symbol, and each symbol's nearest valve tag (a link must be mutual)
  var nearestTag = newSeq[int](keep.len)
  var nearestGap = newSeq[float](keep.len)
  for i in 0 ..< keep.len:
    nearestTag[i] = -1
    nearestGap[i] = Inf
  var cands: seq[seq[(float, int)]]
  for ti, b in tb:
    var c: seq[(float, int)]
    for i, x in keep:
      if x.legend: continue
      let gp = gap(b, x.bbox)
      if gp > 200: continue
      c.add (gp, i)
      if gp < nearestGap[i]:
        nearestGap[i] = gp
        nearestTag[i] = ti
    c.sort()
    cands.add c
  # a symbol and a tag that are each other's nearest are a pair; another tag's pair is no competitor (in a stack of
  # valves each box touches its own valve, and the neighbour is only a few units further)
  var pairOf = newSeq[int](keep.len)
  for i in 0 ..< keep.len:
    let ti = nearestTag[i]
    pairOf[i] = if ti >= 0 and cands[ti].len > 0 and cands[ti][0][1] == i: ti else: -1
  for ti, t in tags:
    var l = Link(tag: t.id, sym: -1, gap: Inf, next: Inf)
    let c = cands[ti]
    if c.len > 0:
      l.gap = c[0][0]
      for (gp, i) in c[1 .. ^1]:
        if pairOf[i] < 0 or pairOf[i] == ti:
          l.next = gp
          break
      if l.gap <= LinkMax and l.next - l.gap >= LinkMargin and pairOf[c[0][1]] == ti:
        l.sym = c[0][1]
        l.conf = confidence(keep[l.sym], l)
    result.links.add l

proc symbolJson*(sv: SheetValves, l: Link, scale: float): JNode =
  ## tags.json's optional "symbol" field for a linked valve on a sheet with the legend; nil otherwise
  if l.sym < 0 or not sv.hasLegend: return nil
  let x = sv.symbols[l.sym]
  let k = scale / U
  var bb = newArr()
  for v in x.bbox: bb.elems.add newFloat(round(v * k * 10) / 10)
  newObj(@[("type", newStr(x.kind)), ("actuator", newStr(if x.actuator: "motor" else: "none")),
           ("nc", newBool(x.hatch >= HatchMin)), ("conf", newFloat(l.conf)), ("bbox", bb)])

proc annotate*(tags: JNode, sheet: string, d: Drawing, scale: float, legend = "auto"):
    tuple[hasLegend: bool, valves, typed: int] =
  ## tags.json (all sheets) in place: each of `sheet`'s valve tags gets a fresh "symbol" field, or loses a stale
  ## one; nothing else of any tag changes
  var vtags: seq[ValveTag]
  var nodes: seq[JNode]
  for t in tags.elems:
    if t.kind != jObj or not t.get("sheet").isStr or t["sheet"].s != sheet: continue
    t.del("symbol")
    let k = t.get("kks")
    let bb = t.get("bbox")
    if k.isStr and isValve(k.s) and bb != nil and bb.kind == jArr and bb.elems.len == 4 and bb.elems.allIt(it.isNum):
      vtags.add ValveTag(id: (if t.get("id").isStr: t["id"].s else: ""), bbox: [bb[0].num, bb[1].num, bb[2].num, bb[3].num])
      nodes.add t
  let sv = analyse(d, scale, vtags, legend)
  result.hasLegend = sv.hasLegend
  result.valves = vtags.len
  for i, l in sv.links:
    let sym = symbolJson(sv, l, scale)
    if sym != nil:
      nodes[i]["symbol"] = sym
      inc result.typed
