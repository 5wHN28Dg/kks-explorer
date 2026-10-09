## Valve symbols (kksi/valves.nim) on synthetic drawings: each HRSG legend shape, the legend row, linking a tag to
## its symbol, and the tags.json annotation (--keep-tags). No plant data.
import std/[os, strutils, unittest]
import kks/[json, pathstore]
import kksi/[mupdf, kkp, valves]

type Pen = object
  d: Drawing

proc initPen(w = 600.0, h = 400.0): Pen =
  result.d.width = uint32(w * 64)
  result.d.height = uint32(h * 64)
  result.d.styles = @[Style(kind: Stroke, width: 46)]

proc poly(p: var Pen, pts: openArray[(float, float)], close = false) =
  ## a stroked polyline, points in pt
  var path = pathstore.Path(style: 0, cmdStart: p.d.ops.len, ptStart: p.d.xy.len div 2)
  var bb = [high(int64), high(int64), low(int64), low(int64)]
  for i, (x, y) in pts:
    p.d.ops.add (if i == 0: OpMove else: OpLine)
    let (qx, qy) = (int64(x * 64), int64(y * 64))
    p.d.xy.add qx
    p.d.xy.add qy
    bb = [min(bb[0], qx), min(bb[1], qy), max(bb[2], qx), max(bb[3], qy)]
  if close: p.d.ops.add OpClose
  path.cmdCount = p.d.ops.len - path.cmdStart
  path.bbox = bb
  p.d.paths.add path

proc line(p: var Pen, x0, y0, x1, y1: float) = p.poly([(x0, y0), (x1, y1)])

type Mark = enum mGate, mMotor, mBox, mCheck, mStem, mT, mHatch, mSplit

proc valve(p: var Pen, cx, cy: float, marks: set[Mark] = {}, vertical = false, w = 18.0, h = 11.0) =
  ## a valve in the HRSG legend's drawing: a bowtie (one Z polyline, closed) and its marks; sizes in pt
  let a = w / 2
  let b = h / 2
  # (u along the flow, v across it) → page
  proc P(u, v: float): (float, float) = (if vertical: (cx + v, cy + u) else: (cx + u, cy + v))
  if mSplit in marks:
    # the X drawn as loose pieces (AutoCAD plots split strokes): each diagonal halved at the centre, the sides on
    # their own
    for (u0, v0, u1, v1) in [(-a, -b, a, b), (-a, b, a, -b)]:
      for i in 0 .. 1:
        let f0 = float(i) / 2
        let f1 = float(i + 1) / 2
        let p0 = P(u0 + (u1 - u0) * f0, v0 + (v1 - v0) * f0)
        let p1 = P(u0 + (u1 - u0) * f1, v0 + (v1 - v0) * f1)
        p.line(p0[0], p0[1], p1[0], p1[1])
    p.line(P(a, -b)[0], P(a, -b)[1], P(a, b)[0], P(a, b)[1])
    p.line(P(-a, -b)[0], P(-a, -b)[1], P(-a, b)[0], P(-a, b)[1])
  else:
    p.poly([P(-a, -b), P(a, b), P(a, -b), P(-a, b)], close = true)
  if mBox in marks:
    p.line(P(-a, -b)[0], P(-a, -b)[1], P(a, -b)[0], P(a, -b)[1])
    p.line(P(-a, b)[0], P(-a, b)[1], P(a, b)[0], P(a, b)[1])
  if mGate in marks: p.poly([P(0, -b), P(0, b)])
  if mCheck in marks: p.poly([P(0.6 * a, -0.55 * b), P(0.6 * a, 0.55 * b)])
  if mMotor in marks:
    p.poly([P(0, 0), P(0, -b - 6)])
    p.poly([P(-3, -b - 6), P(3, -b - 6), P(3, -b - 12), P(-3, -b - 12)], close = true)
  if mStem in marks: p.poly([P(0, 0), P(0, -b - 7)])
  if mT in marks:
    p.poly([P(0, 0), P(0, -b - 7)])
    p.poly([P(-3, -b - 7), P(3, -b - 7)])
  if mHatch in marks:
    for i in 0 .. 7:
      let u = -0.9 * a + float(i) * 0.1 * a
      p.poly([P(u, -0.1 * b), P(u + 0.12 * a, 0.1 * b)])

proc legendRow(p: var Pen, x, y: float) =
  ## GATE, GLOBE, ELECTRIC GATE, ELECTRIC GLOBE, ELECTRIC CONTROL, MIN FLOW, CHECK
  for i, m in [{mGate}, {}, {mGate, mMotor}, {mMotor}, {mBox, mMotor}, {mCheck, mStem}, {mCheck}]:
    p.valve(x + float(i) * 40, y, m)

proc tagAt(id: string, x0, y0, x1, y1: float): ValveTag =
  ## a tag box given in pt, on a sheet at 2 px per pt
  ValveTag(id: id, bbox: [x0 * 2, y0 * 2, x1 * 2, y1 * 2])

proc one(marks: set[Mark], vertical = false, w = 18.0, h = 11.0): JNode =
  ## one valve at (100, 200) with its tag touching it, on a sheet with the legend: its "symbol" field
  var p = initPen()
  p.legendRow(300, 50)
  p.valve(100, 200, marks, vertical, w, h)
  let t = if vertical: tagAt("t", 106, 190, 140, 210) else: tagAt("t", 85, 207, 115, 225)
  let sv = analyse(p.d, 2.0, @[t])
  check sv.hasLegend
  check sv.links.len == 1
  symbolJson(sv, sv.links[0], 2.0)

suite "valve symbols":
  test "each legend shape, horizontal and vertical":
    for vertical in [false, true]:
      for (marks, kind, act) in [({}, "globe valve", "none"), ({mGate}, "gate valve", "none"),
                                 ({mMotor}, "globe valve", "motor"), ({mGate, mMotor}, "gate valve", "motor"),
                                 ({mBox, mMotor}, "control valve", "motor"), ({mCheck}, "check valve", "none"),
                                 ({mCheck, mStem}, "min-flow valve", "none"), ({mT}, "jam valve", "none")]:
        checkpoint $marks & " vertical=" & $vertical
        let s = one(marks, vertical)
        check s != nil
        if s == nil: continue
        check s["type"].s == kind
        check s["actuator"].s == act
        check s["nc"].b == false
        check s["conf"].num > 0.8
  test "hatched = normally closed (nc)":
    let s = one({mHatch})
    check s != nil and s["type"].s == "globe valve" and s["nc"].b
  test "an X drawn in loose pieces is not hatching (not normally closed)":
    for vertical in [false, true]:
      let s = one({mSplit}, vertical)
      check s != nil and s["type"].s == "globe valve" and not s["nc"].b
      let h = one({mSplit, mHatch}, vertical)
      check h != nil and h["nc"].b
    # a square body: the half-diagonals are short enough to pass the length test; their corners still keep them out
    let q = one({mSplit}, false, 12, 12)
    check q != nil and not q["nc"].b
  test "the symbol's box is in level-0 px":
    let s = one({})
    check s != nil
    if s != nil:
      check abs(s["bbox"][0].num - 182) < 1 and abs(s["bbox"][2].num - 218) < 1
      check abs(s["bbox"][1].num - 389) < 1 and abs(s["bbox"][3].num - 411) < 1
  test "a box without a stem to it is not an actuator (text beside a valve)":
    var p = initPen()
    p.legendRow(300, 50)
    p.valve(100, 200)
    p.poly([(94.0, 187.0), (106.0, 187.0), (106.0, 181.0), (94.0, 181.0)], close = true)   # no stem
    let sv = analyse(p.d, 2.0, @[tagAt("t", 85, 207, 115, 225)])
    let s = symbolJson(sv, sv.links[0], 2.0)
    check s != nil and s["actuator"].s == "none"

suite "the legend":
  test "found on a sheet that carries it, its symbols never linked":
    var p = initPen()
    p.legendRow(300, 50)
    let sv = analyse(p.d, 2.0, @[tagAt("t", 285, 57, 315, 75)])   # a valve tag touching the legend's GATE
    check sv.hasLegend
    var n = 0
    for x in sv.symbols:
      if x.legend: inc n
    check n == 7
    check sv.links[0].sym == -1
  test "no legend: no type, even for a clear link":
    var p = initPen()
    p.valve(100, 200)
    let sv = analyse(p.d, 2.0, @[tagAt("t", 85, 207, 115, 225)])
    check not sv.hasLegend
    check sv.links[0].sym >= 0
    check symbolJson(sv, sv.links[0], 2.0) == nil
  test "--legend hrsg / none override the search":
    var p = initPen()
    p.valve(100, 200)
    check analyse(p.d, 2.0, @[], "hrsg").hasLegend
    var q = initPen()
    q.legendRow(300, 50)
    check not analyse(q.d, 2.0, @[], "none").hasLegend
  test "a partial row (no control valve) is not the legend":
    var p = initPen()
    for i, m in [{mGate}, {}, {mGate, mMotor}, {mMotor}, {mCheck}]:
      p.valve(300 + float(i) * 40, 50, m)
    check not analyse(p.d, 2.0, @[]).hasLegend

suite "linking a tag to its symbol":
  proc links(p: Pen, tags: seq[ValveTag]): seq[int] =
    var q = p
    q.legendRow(300, 50)
    for l in analyse(q.d, 2.0, tags).links: result.add l.sym
  test "touching: linked; far: not":
    var p = initPen()
    p.valve(100, 200)
    check links(p, @[tagAt("t", 85, 207, 115, 225)])[0] >= 0
    check links(p, @[tagAt("t", 85, 225, 115, 245)])[0] == -1       # 14.5 pt = 29 units: too far
  test "two symbols at nearly the same gap and no other tag: not linked":
    var p = initPen()
    p.valve(100, 200)
    p.valve(100, 236)
    check links(p, @[tagAt("t", 85, 207, 115, 225)])[0] == -1        # 1.5 pt from one, 5.5 pt from the other
  test "a stack: each tag touches its own valve, the neighbour a few units further":
    var p = initPen()
    p.valve(100, 200, vertical = true)
    p.valve(100, 222, vertical = true)
    let l = links(p, @[tagAt("a", 106, 192, 140, 208), tagAt("b", 106, 214, 140, 230)])
    check l[0] >= 0 and l[1] >= 0 and l[0] != l[1]

suite "tags.json (--keep-tags)":
  test "adds or refreshes the symbol field, and changes nothing else":
    init()
    # the same drawing as a PDF, through the path store writer (the importer's own path)
    var content = ""
    proc ln(x0, y0, x1, y1: float) = content.add $x0 & " " & $(400 - y0) & " m " & $x1 & " " & $(400 - y1) & " l S\n"
    proc bow(cx, cy: float, gate = false) =
      content.add $(cx - 9) & " " & $(400 - cy + 5.5) & " m " & $(cx + 9) & " " & $(400 - cy - 5.5) & " l " &
                  $(cx + 9) & " " & $(400 - cy + 5.5) & " l " & $(cx - 9) & " " & $(400 - cy - 5.5) & " l h S\n"
      if gate: ln(cx, cy - 5.5, cx, cy + 5.5)
    proc motor(cx, cy: float) =
      ln(cx, cy, cx, cy - 11.5)
      content.add $(cx - 3) & " " & $(400 - cy + 11.5) & " 6 6 re S\n"
    for i in 0 .. 6:
      let x = 300.0 + float(i) * 40
      bow(x, 50, i in [0, 2])
      if i in [2, 3, 4]: motor(x, 50)
      if i == 4:
        ln(x - 9, 44.5, x + 9, 44.5)
        ln(x - 9, 55.5, x + 9, 55.5)
      if i in [5, 6]: ln(x + 5.4, 50 - 3, x + 5.4, 50 + 3)
      if i == 5: ln(x, 50, x, 50 - 12.5)
    bow(100, 200, gate = true)
    let dir = getTempDir() / "kksimp"
    createDir(dir)
    var objs = @["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                 "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 400] /Contents 4 0 R >>",
                 "<< /Length " & $content.len & " >>\nstream\n" & content & "endstream"]
    var s = "%PDF-1.4\n"
    var offs: seq[int]
    for i, o in objs:
      offs.add s.len
      s.add $(i + 1) & " 0 obj\n" & o & "\nendobj\n"
    let xref = s.len
    s.add "xref\n0 " & $(objs.len + 1) & "\n0000000000 65535 f \n"
    for o in offs: s.add align($o, 10, '0') & " 00000 n \n"
    s.add "trailer\n<< /Size " & $(objs.len + 1) & " /Root 1 0 R >>\nstartxref\n" & $xref & "\n%%EOF\n"
    writeFile(dir / "valves.pdf", s)
    let doc = mupdf.open(dir / "valves.pdf")
    let d = fromPdfPage(doc, 0, images = false)
    doc.close()
    let tags = parseStrict("""[
      {"id": "s:0", "sheet": "s", "kks": "11LAB70AA001", "status": "verified", "bbox": [170, 414, 230, 450],
       "note": "kept", "symbol": {"type": "check valve"}},
      {"id": "s:1", "sheet": "s", "kks": "11LAB70CP001", "isa": "PI", "status": "auto", "bbox": [10, 10, 60, 40]},
      {"id": "s:2", "sheet": "s", "kks": "11LAB70AA002", "status": "auto", "bbox": [1000, 700, 1060, 740],
       "symbol": {"type": "stale"}},
      {"id": "o:0", "sheet": "other", "kks": "11LAB70AA003", "bbox": [170, 414, 230, 450], "symbol": {"type": "x"}}]""")
    let before = parseStrict(toText(tags))
    let r = annotate(tags, "s", d, 2.0)
    check r.hasLegend and r.valves == 2 and r.typed == 1
    let t0 = tags[0]
    check t0["symbol"]["type"].s == "gate valve"
    check t0["symbol"]["actuator"].s == "none"
    for i in 0 ..< 4:   # every other field as it was
      var a = tags[i].copy
      var b = before[i].copy
      if i < 3:
        a.del("symbol")
        b.del("symbol")
      check a == b
    check tags[1].get("symbol") == nil
    check tags[2].get("symbol") == nil        # the stale field is gone: no symbol beside it now
    check tags[3]["symbol"]["type"].s == "x"  # another sheet's tags untouched
    removeFile(dir / "valves.pdf")
