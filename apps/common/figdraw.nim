## Drawing a course figure's resolved scene (docs/COURSES.md §9.3–9.5; core `courses.scene`) through a small backend,
## so the GNOME (Cairo + Pango) and Windows (Direct2D + DirectWrite) apps share every drawing rule: paint resolution,
## defaults, arrowheads, labels, groups, flows. A port of course-figure.js's `draw`. Decision 0036.

import std/[math, strutils]
import kks/json

type
  Rgba* = object
    r*, g*, b*, a*: float
  Paint* = object
    radial*: bool
    c*: Rgba                                 ## solid
    cx*, cy*, rad*: float                    ## radial: centre, radius
    stops*: seq[(float, Rgba)]
  Backend* = object
    save*, restore*: proc ()
    translate*: proc (x, y: float)
    rotate*: proc (radians: float)
    scale*: proc (x, y: float)
    pushOpacity*: proc (alpha: float)        ## draw what follows into a layer, composited at `alpha` by popOpacity
    popOpacity*: proc ()
    clipRoundRect*: proc (x, y, w, h, rx: float)
    # one path at a time
    begin*: proc ()
    moveTo*, lineTo*: proc (x, y: float)
    curveTo*: proc (x1, y1, x2, y2, x, y: float)
    close*: proc ()
    roundRect*: proc (x, y, w, h, rx: float)
    ellipse*: proc (cx, cy, rx, ry: float)
    fill*: proc (p: Paint)
    stroke*: proc (c: Rgba, width: float, cap, join: string, dash: seq[float])
    text*: proc (s: string, x, y: float, anchor, font: string, size: float, weight: int, c: Rgba)

const
  Light* = [("ground", "#E9EDEF"), ("surface", "#F8FAFA"), ("sunk", "#DDE3E6"), ("ink", "#16222B"), ("muted", "#56646E"),
            ("rule", "#C6CFD4"), ("accent", "#1F5F8B"), ("ok", "#2E7A4E"), ("alarm", "#9A6412"), ("alarm_fill", "#E8B04A"),
            ("act", "#B3261E")]
  Dark* = [("ground", "#11171B"), ("surface", "#182026"), ("sunk", "#0D1215"), ("ink", "#E2E8EB"), ("muted", "#95A4AD"),
           ("rule", "#2B363D"), ("accent", "#6DAFDC"), ("ok", "#62C08A"), ("alarm", "#E4AE45"), ("alarm_fill", "#B9832A"),
           ("act", "#F0776B")]

proc hexRgba*(h: string, alpha = 1.0): Rgba =
  Rgba(r: float(parseHexInt(h[1 .. 2])) / 255, g: float(parseHexInt(h[3 .. 4])) / 255,
       b: float(parseHexInt(h[5 .. 6])) / 255, a: alpha)

proc token*(name: string, dark: bool): string =
  for (k, v) in (if dark: Dark else: Light):
    if k == name: return v
  "#000000"

proc colour(p: JNode, dark: bool): (bool, Rgba) =
  ## a solid paint → (false when none)
  if p == nil or p.kind != jStr or p.s == "none": return (false, Rgba())
  if p.s.startsWith("#"): return (true, hexRgba(p.s))
  (true, hexRgba(token(p.s, dark)))

proc n(x: JNode): float = x.num
proc nums(a: JNode): seq[float] =
  for x in a.elems: result.add x.num

proc bbox(e: JNode): (float, float, float, float) =
  if e.get("rect") != nil:
    let r = nums(e["rect"])
    return (r[0], r[1], r[2], r[3])
  if e.get("circle") != nil:
    let c = nums(e["circle"])
    return (c[0] - c[2], c[1] - c[2], 2 * c[2], 2 * c[2])
  if e.get("ellipse") != nil:
    let c = nums(e["ellipse"])
    return (c[0] - c[2], c[1] - c[3], 2 * c[2], 2 * c[3])
  var xs, ys: seq[float]
  if e.get("poly") != nil:
    for p in e["poly"].elems:
      xs.add p[0].num
      ys.add p[1].num
  elif e.get("path") != nil:
    for c in e["path"].elems:
      var i = 1
      while i + 1 < c.len:
        xs.add c[i].num
        ys.add c[i + 1].num
        i += 2
  if xs.len == 0: return (0.0, 0.0, 0.0, 0.0)
  (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))

proc fillPaint(e: JNode, dark: bool): (bool, Paint) =
  let p = e.get("fill")
  if p != nil and p.kind == jObj and p.get("radial") != nil:
    let (x, y, w, h) = bbox(e)
    var pt = Paint(radial: true, cx: x + w / 2, cy: y + h / 2, rad: max(w / 2, 1e-6))
    for s in p["radial"].elems:
      let (ok, c) = colour(s[1], dark)
      var cc = if ok: c else: Rgba()
      cc.a = clamp(s[2].num, 0.0, 1.0)
      pt.stops.add (s[0].num, cc)
    return (true, pt)
  let (ok, c) = colour(p, dark)
  (ok, Paint(c: c))

proc draw*(b: Backend, scene: JNode, dark: bool) =
  let ink = hexRgba(token("ink", dark))
  let muted = hexRgba(token("muted", dark))

  proc shape(e: JNode) =
    let (fok, fp) = fillPaint(e, dark)
    if fok: b.fill(fp)
    let (sok, sc) = colour(e.get("stroke"), dark)
    if sok:
      var dash: seq[float]
      if e.get("dash") != nil: dash = nums(e["dash"])
      b.stroke(sc, if e.get("stroke_width") != nil: n(e["stroke_width"]) else: 1.0,
               if e.get("cap") != nil: e["cap"].s else: "butt", if e.get("join") != nil: e["join"].s else: "miter", dash)

  proc el(e: JNode) =
    let op = if e.get("opacity") != nil: n(e["opacity"]) else: 1.0
    if op <= 0: return
    b.save()
    let layered = op < 1
    if layered: b.pushOpacity(op)
    if e.get("transform") != nil:
      for st in e["transform"].elems:
        if st.get("translate") != nil: b.translate(st["translate"][0].num, st["translate"][1].num)
        elif st.get("rotate") != nil:
          let r = nums(st["rotate"])
          b.translate(r[1], r[2])
          b.rotate(r[0] * PI / 180)
          b.translate(-r[1], -r[2])
        elif st.get("scale") != nil: b.scale(st["scale"][0].num, st["scale"][1].num)
    if e.get("group") != nil:
      if e.get("clip") != nil:
        let r = nums(e["clip"]["rect"])
        b.clipRoundRect(r[0], r[1], r[2], r[3], n(e["clip"]["rx"]))
      for c in e["group"].elems: el(c)
    elif e.get("rect") != nil:
      let r = nums(e["rect"])
      b.begin()
      b.roundRect(r[0], r[1], max(0.0, r[2]), max(0.0, r[3]), if e.get("rx") != nil: n(e["rx"]) else: 0.0)
      shape(e)
    elif e.get("circle") != nil:
      let c = nums(e["circle"])
      b.begin()
      b.ellipse(c[0], c[1], max(0.0, c[2]), max(0.0, c[2]))
      shape(e)
    elif e.get("ellipse") != nil:
      let c = nums(e["ellipse"])
      b.begin()
      b.ellipse(c[0], c[1], max(0.0, c[2]), max(0.0, c[3]))
      shape(e)
    elif e.get("line") != nil:
      let l = nums(e["line"])
      b.begin()
      b.moveTo(l[0], l[1])
      b.lineTo(l[2], l[3])
      let (sok, sc) = colour(e.get("stroke"), dark)
      if sok:
        let w = if e.get("stroke_width") != nil: n(e["stroke_width"]) else: 1.0
        var dash: seq[float]
        if e.get("dash") != nil: dash = nums(e["dash"])
        b.stroke(sc, w, if e.get("cap") != nil: e["cap"].s else: "butt", if e.get("join") != nil: e["join"].s else: "miter", dash)
        if e.get("arrow") != nil and e["arrow"].kind == jBool and e["arrow"].b:
          # §9.4: tip at the end + 1.2 w along the line, base 6 w behind the tip, half-width 3 w
          let L = max(hypot(l[2] - l[0], l[3] - l[1]), 1e-9)
          let ux = (l[2] - l[0]) / L
          let uy = (l[3] - l[1]) / L
          let tx = l[2] + 1.2 * w * ux
          let ty = l[3] + 1.2 * w * uy
          let bx = tx - 6 * w * ux
          let by = ty - 6 * w * uy
          b.begin()
          b.moveTo(tx, ty)
          b.lineTo(bx - 3 * w * uy, by + 3 * w * ux)
          b.lineTo(bx + 3 * w * uy, by - 3 * w * ux)
          b.close()
          b.fill(Paint(c: sc))
    elif e.get("poly") != nil:
      b.begin()
      var first = true
      for p in e["poly"].elems:
        if first: b.moveTo(p[0].num, p[1].num) else: b.lineTo(p[0].num, p[1].num)
        first = false
      if e.get("closed") != nil and e["closed"].kind == jBool and e["closed"].b: b.close()
      shape(e)
    elif e.get("path") != nil:
      b.begin()
      for c in e["path"].elems:
        case c[0].s
        of "M": b.moveTo(c[1].num, c[2].num)
        of "L": b.lineTo(c[1].num, c[2].num)
        of "C": b.curveTo(c[1].num, c[2].num, c[3].num, c[4].num, c[5].num, c[6].num)
        else: b.close()
      shape(e)
    elif e.get("text") != nil:
      let at = nums(e["at"])
      let (ok, c) = if e.get("fill") != nil: colour(e["fill"], dark) else: (true, ink)
      if ok:
        b.text(e["text"].s, at[0], at[1], if e.get("anchor") != nil: e["anchor"].s else: "start",
               if e.get("font") != nil: e["font"].s else: "body", if e.get("size") != nil: n(e["size"]) else: 12.0,
               if e.get("weight") != nil: int(n(e["weight"])) else: 400, c)
    elif e.get("label") != nil:
      let at = nums(e["at"])
      let to = nums(e["to"])
      let en = nums(e["end"])
      b.begin()
      b.ellipse(at[0], at[1], 2.5, 2.5)
      b.fill(Paint(c: muted))
      b.begin()
      b.moveTo(at[0], at[1])
      b.lineTo(en[0], en[1])
      b.stroke(muted, 1, "butt", "miter", @[])
      b.text(e["label"].s, to[0], to[1], if e.get("anchor") != nil: e["anchor"].s else: "start", "body", 12.5, 400, ink)
    elif e.get("flow") != nil:
      let fl = e["flow"]
      let (sok, sc) = colour(fl.get("stroke"), dark)
      let sw = if fl.get("stroke_width") != nil: n(fl["stroke_width"]) else: 1.0
      let burst = fl.get("glyph") != nil and fl["glyph"].s == "burst"
      for p in fl["particles"].elems:
        let (x, y, r, pop) = (p[0].num, p[1].num, p[2].num, p[3].num)
        if pop <= 0: continue
        if pop < 1: b.pushOpacity(pop)
        if burst:
          if sok:
            let d = 5 * r / 7
            b.begin()
            b.moveTo(x - r, y)
            b.lineTo(x + r, y)
            b.moveTo(x, y - r)
            b.lineTo(x, y + r)
            b.moveTo(x - d, y - d)
            b.lineTo(x + d, y + d)
            b.stroke(sc, sw, "butt", "miter", @[])
        else:
          b.begin()
          b.ellipse(x, y, max(0.0, r), max(0.0, r))
          let (fok, fc) = colour(p[4], dark)
          if fok: b.fill(Paint(c: fc))
          if sok: b.stroke(sc, sw, "butt", "miter", @[])
        if pop < 1: b.popOpacity()
    if layered: b.popOpacity()
    b.restore()

  for e in scene.elems: el(e)
