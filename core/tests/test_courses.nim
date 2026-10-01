import std/[unittest, math, sets, tables]
import kks/[json, courses]
import vectors

include closeutil

proc imagesOf(c: JNode, default: seq[string]): HashSet[string] =
  if c.has("images"):
    for x in c["images"].elems: result.incl x.s
  else:
    for x in default: result.incl x

suite "course format (courses-v1.json)":
  let V = loadVectors("courses-v1.json")

  test "valid":
    for c in V["valid"].elems:
      let counts = checkCourse(c["course"], imagesOf(c, @[]))
      for k, v in counts: check c["counts"][k].i == v

  test "rejects with their codes":
    for r in V["reject"].elems:
      var code = "accepted"
      try: discard checkCourse(r["course"], imagesOf(r, @["photo-1.jxl"]))
      except CourseError as e: code = e.code
      check code == r["code"].s
      if code != r["code"].s: echo "  ", r["why"].s, ": got ", code

  test "frames":
    let figures = V["valid"][0]["course"]["figures"]
    for run in V["frames"].elems:
      let fg = newFigure(figures[run["figure"].s], reduceMotion = run["reduce_motion"].b)
      for n, st in run["steps"].elems:
        let e = st["event"]
        case e[0].s
        of "tick": fg.tick(e[1].num)
        of "slider": fg.setSlider(e[1].num)
        of "toggle": fg.toggle(e[1].s)
        of "mode": fg.setMode(int(e[1].num))
        of "play": fg.play()
        of "pause": fg.pause()
        else: discard
        if not st["state"].isNull:
          let d = close(snapshot(fg), st["state"], run["figure"].s & " step " & $n)
          check d == ""
          if d != "": echo "  ", d

  test "units":
    let U = V["units"]
    for c in U["table"].elems:
      for pr in c["at"].elems:
        check abs(tableAt(c["table"], pr[0].num, c["step"].b) - pr[1].num) < 1e-9
    for c in U["format"].elems:
      let got = fmtNumber(c[0].num, int(c[1].i), c[2].b)
      check got == c[3].s
      if got != c[3].s: echo "  ", c[0].num, " → ", got, " want ", c[3].s
    for c in U["template"].elems:
      var vals: Table[string, float]
      for (k, v) in c[1].fields: vals[k] = v.num
      check fillTemplate(c[0].s, vals) == c[2].s
    for c in U["colour"].elems: check colourAt(c[0], c[1].num) == c[2].s
    for c in U["leader"].elems:
      let (x, y) = leaderEnd(c[0].s, (c[1][0].num, c[1][1].num), (c[2][0].num, c[2][1].num), c[3].s)
      check abs(x - c[4][0].num) < 1e-9 and abs(y - c[4][1].num) < 1e-9
    for c in U["judge"]["cases"].elems: check judge(U["judge"]["item"], c[0].num) == c[1].s
    for c in U["choose"].elems:
      var routes = newArr()
      for w in c["weights"].elems:
        routes.elems.add newObj(@[("path", parseStrict("""[["M",0,0],["L",1,0]]""")), ("weight", w)])
      let fl = newObj(@[("count", newInt(5)), ("routes", routes)])
      let fg = newFigure(parseStrict("""{"title":"x","caption":[],"alt":"x","w":1,"h":1,"period":1,"scene":[]}"""))
      for i in 0 ..< 5:
        for n in 0 ..< 4: check fg.choose(fl, i, n) == int(c["routes"][i][n].i)
    for f in U["flatten"].elems:
      let (pts, segs, L) = flatten(f["path"], proc (r: JNode): float = r.num)
      check abs(L - f["length"].num) < 1e-9
      for i, p in pts:
        check abs(p[0] - f["points"][i][0].num) < 1e-9 and abs(p[1] - f["points"][i][1].num) < 1e-9
      for a in f["at"].elems:
        let (x, y) = pointAt(pts, segs, a[0].num)
        check abs(x - a[1][0].num) < 1e-9 and abs(y - a[1][1].num) < 1e-9

  test "rounding: exact binary value, half away from zero":
    check fmtNumber(2.5, 0, false) == "3"
    check fmtNumber(-2.5, 0, false) == "−3"
    check fmtNumber(0.125, 2, false) == "0.13"
    check fmtNumber(2.675, 2, false) == "2.67"
    check fmtNumber(-0.3, 0, true) == "+0"
    check fmtNumber(5e-324, 6, false) == "0.000000"
    check fmtNumber(999999.9999999, 3, false) == "1000000.000"
