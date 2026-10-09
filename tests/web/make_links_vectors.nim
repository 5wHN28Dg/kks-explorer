## tests/web/links-vectors.json: generated sheets.json entries with off-page connectors (seeded: labels shared across
## and within sheets, malformed entries, boxes the core refuses, odd scales, long names) and core views.linksView's
## answer for every sheet, plus findLink cases, so tests/web/test_links.py can check systems.js KSys.linksView and
## KSys.findLink against the Nim core itself.
##   cd core && nim c -r --hints:off --path:src ../tests/web/make_links_vectors.nim > ../tests/web/links-vectors.json
import std/[random, strutils]
import kks/[json, model, views]

var r = initRand(20261010)
let labels = ["C16", "C47", "D2", "S3", "A1", "B12", "Ä1", "C" & "9".repeat(15), "C" & "9".repeat(16), ""]
var sheets = newArr()
for k in 0 ..< 8:
  let scale = [2.0, 1.0, 0.5, 2.0, 3.0, 2.0, 1e-300, 2.0][k]
  var ls = newArr()
  for i in 0 ..< r.rand(14):
    let x = float(r.rand(2000))
    let y = float(r.rand(1000))
    let side = float(5 + r.rand(30))
    var l = newObj(@[("label", newStr(r.sample(labels)))])
    case r.rand(11)
    of 0: l["bbox"] = newArr(@[newFloat(x), newFloat(y), newFloat(x + side)])              # 3 numbers
    of 1: l["bbox"] = newArr(@[newFloat(x + side), newFloat(y), newFloat(x), newFloat(y + side)])   # reversed
    of 2: l["bbox"] = newArr(@[newFloat(x), newFloat(y), newFloat(x + 500), newFloat(y + 500)])     # too big
    of 3: l["bbox"] = newArr(@[newFloat(x), newStr("1"), newFloat(x + side), newFloat(y + side)])
    of 4: l["label"] = newInt(7); l["bbox"] = newArr(@[newFloat(x), newFloat(y), newFloat(x + side), newFloat(y + side)])
    else: l["bbox"] = newArr(@[newFloat(x), newFloat(y), newFloat(x + side), newFloat(y + side)])
    case r.rand(3)
    of 0: discard                                   # no conf: taken as read
    of 1: l["conf"] = newStr("0.5")
    else: l["conf"] = newFloat(float(r.rand(100)) / 100)
    ls.elems.add l
  if k == 2: ls.elems.add newInt(7)
  if k == 1:      # the limits, exactly (scale 1: px = points)
    proc edge(label: string, b: array[4, float], conf: JNode = nil): JNode =
      result = newObj(@[("label", newStr(label)), ("bbox", newArr(@[newFloat(b[0]), newFloat(b[1]), newFloat(b[2]), newFloat(b[3])]))])
      if conf != nil: result["conf"] = conf
    ls.elems.add edge("C" & "9".repeat(15), [10.0, 10, 20, 20])                  # 16 bytes: kept
    ls.elems.add edge("C" & "9".repeat(16), [30.0, 10, 40, 20])                  # 17: dropped
    ls.elems.add edge("Ä" & "9".repeat(14), [50.0, 10, 60, 20], newFloat(0.25))  # 16 bytes, 15 characters: kept
    ls.elems.add edge("Ä" & "9".repeat(15), [70.0, 10, 80, 20])                  # 17 bytes, 16 characters: dropped
    ls.elems.add edge("D2", [100.0, 100, 200, 200])                              # 100 pt across: kept
    ls.elems.add edge("D2", [300.0, 100, 400.5, 200])                            # 100.5: dropped
    ls.elems.add edge("D2", [500.0, 100, 500, 120])                              # no width: dropped
    ls.elems.add edge("S3", [600.0, 100, 610, 110], newInt(1))
    ls.elems.add newObj(@[("label", newStr("S3")), ("bbox", newArr(@[newFloat(1), newFloat(2), newFloat(3), newFloat(4), newFloat(5)]))])
    ls.elems.add newObj(@[("bbox", newArr(@[newFloat(1), newFloat(2), newFloat(3), newFloat(4)]))])   # no label
    ls.elems.add newObj(@[("label", newStr("S3")), ("bbox", newStr("1,2,3,4"))])
  var s = newObj(@[("id", newStr("s" & $k)), ("name", newStr(if k == 5: "Ä".repeat(150) else: "Sheet " & $k)),
                   ("w", newFloat(2000)), ("h", newFloat(1000)), ("levels", newInt(2)), ("rot", newInt(0)),
                   ("notes", newArr())])
  if k != 3: s["scale"] = newFloat(scale)            # s3: no scale (2 px per point)
  if k == 4: s["links"] = newStr("not a list")
  elif k != 6: s["links"] = ls                       # s6: none at all (older plant data)
  sheets.elems.add s
# a label repeated more often than a connector lists targets, on two sheets
var many = newArr()
for i in 0 ..< 30:
  many.elems.add newObj(@[("label", newStr("Z9")), ("bbox", newArr(@[newFloat(float(i * 20)), newFloat(0),
                                                                     newFloat(float(i * 20 + 10)), newFloat(10)]))])
for k in 0 .. 1:
  sheets.elems.add newObj(@[("id", newStr("m" & $k)), ("name", newStr("Many " & $k)), ("scale", newFloat(1)),
                            ("links", many)])
let m = Model()
m.sheets = parseSheets(sheets)
var expected = newObj()
for x in sheets.elems: expected[x["id"].s] = linksView(m, x["id"].s)
expected["nope"] = linksView(m, "nope")
var finds = newArr()
let v = linksView(m, "s0")
for i, l in v.elems:
  finds.elems.add newObj(@[("label", l["label"]), ("x0", l["x0"]), ("y0", l["y0"]), ("want", newInt(findLink(v, l["label"].s, l["x0"].num, l["y0"].num)))])
  finds.elems.add newObj(@[("label", l["label"]), ("x0", newFloat(l["x0"].num + 0.5)), ("y0", l["y0"]), ("want", newInt(findLink(v, l["label"].s, l["x0"].num + 0.5, l["y0"].num)))])
echo toText(newObj(@[("sheets", sheets), ("expected", expected), ("find_in", newStr("s0")), ("finds", finds)]))
