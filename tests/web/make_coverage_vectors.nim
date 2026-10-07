## tests/web/coverage-vectors.json: a generated plant (seeded) with reviews, hand-added tags, places typed by people and
## photos, and core views.coverageView's answer, so tests/web/test_coverage.py can check systems.js (KSys.coverageView)
## against the Nim core itself, not hand-copied values.
##   cd core && nim c -r --hints:off --path:src ../tests/web/make_coverage_vectors.nim > ../tests/web/coverage-vectors.json
import std/[random, strutils, os]
import kks/[json, model, views]

var r = initRand(20261007)
let kksTables = parseStrict(readFile(currentSourcePath().parentDir.parentDir.parentDir / "data" / "kks.json"))
var systems, comps: seq[string]
for (k, _) in kksTables["systems"].fields: systems.add k
for (k, _) in kksTables["components"].fields: comps.add k
systems = systems[0 ..< 12]          # few systems, so codes share them
systems.add "QQX"                    # a system the tables don't name
let blocks = ["11", "12"]
var tags = newArr()
var codes: seq[string]
var reviews = newObj()
for i in 0 ..< 500:
  let sheet = ["a", "b", "c", "d"][i mod 4]          # "d" is not in sheets.json: it comes after the others
  var kks: JNode
  var suffix = ""
  var isa: JNode = newNull()
  var kind = "equipment"
  var status = "auto"
  let roll = r.rand(99)
  if roll < 6: kks = newNull(); kind = "other"; status = "review"                  # unreadable
  elif roll < 10: kks = newStr(r.sample(blocks) & r.sample(systems) & $(10 + r.rand(80)))   # doesn't decode
  elif roll < 30 and codes.len > 0: kks = newStr(r.sample(codes))                  # the same code again (other sheet too)
  else:
    let k = r.sample(blocks) & r.sample(systems) & align($(10 + r.rand(89)), 2, '0') & r.sample(comps) & align($r.rand(999), 3, '0')
    kks = newStr(k)
    codes.add k
    if roll mod 4 == 0:
      kind = "instrument"; isa = newStr("TIA")
      if roll mod 8 == 0: suffix = "R"
  if status != "review":
    status = (if roll mod 5 == 0: "verified" elif roll mod 7 == 0: "review" else: "auto")
  let id = sheet & ":" & $i
  tags.elems.add newObj(@[("id", newStr(id)), ("sheet", newStr(sheet)), ("kks", kks), ("suffix", newStr(suffix)),
    ("isa", isa), ("kind", newStr(kind)), ("status", newStr(status)), ("conf", newFloat(0.9)),
    ("bbox", newArr(@[newInt(1), newInt(1), newInt(2), newInt(2)])), ("read", newArr(@[newStr(""), newStr("")]))])
  # people's decisions: some confirmed (perhaps as another code), some rejected
  let d = r.rand(99)
  if d < 4: reviews[id] = newObj(@[("status", newStr("rejected"))])
  elif d < 10: reviews[id] = newObj(@[("status", newStr("confirmed")), ("kks", newStr(if codes.len > 0: r.sample(codes) else: "11LAB70AA501")),
                                      ("suffix", newStr("")), ("isa", newNull())])
var added = newArr()
for i in 0 ..< 25:
  let k = if i mod 5 == 0: "" else: r.sample(codes)
  added.elems.add newObj(@[("id", newStr(toHex(i, 32).toLowerAscii)), ("sheet", newStr(["a", "b", "c"][i mod 3])),
    ("bbox", newArr(@[newInt(5), newInt(5), newInt(9), newInt(9)])), ("kks", newStr(k)), ("suffix", newStr("")),
    ("isa", newNull()), ("kind", newStr("equipment")), ("note", newStr(""))])
var photos = newArr()
for i in 0 ..< 180:
  photos.elems.add newObj(@[("id", newStr("p" & $i)), ("kks", newStr(r.sample(codes))), ("file", newStr("x.jxl")),
    ("caption", newStr(if r.rand(2) == 0: "Tag plate · " & $i else: "view " & $i))])
var locs = newArr()
for i in 0 ..< 70:
  let k = r.sample(codes)
  locs.elems.add newObj(@[("kks", newStr(k[2 .. ^1])), ("level", newStr($r.rand(40) & " m")), ("desc", newStr("x"))])
# places typed by people: real values, blanks (ASCII whitespace only: not a place), and fields that don't count
var equipment = newObj()
let values = [newStr("pump house"), newStr("3"), newStr("  "), newStr("\t\n"), newStr(""), newStr("\u00a0"), newInt(4)]
for i in 0 ..< 90:
  let k = r.sample(codes) & (if r.rand(9) == 0: "R" else: "")
  let f = r.sample(["area", "floor", "elev", "near", "loc", "notes", "custom_x"])
  equipment[k] = newObj(@[(f, r.sample(values))])
let sheets = parseStrict("""[{"id":"a","name":"Sheet A","w":100,"h":100,"scale":1,"levels":1,"rot":0,"notes":[]},
  {"id":"b","name":"Sheet B","w":100,"h":100,"scale":1,"levels":1,"rot":0,"notes":[]},
  {"id":"c","name":"Sheet C","w":100,"h":100,"scale":1,"levels":1,"rot":0,"notes":[]},
  {"id":"e","name":"Empty sheet","w":100,"h":100,"scale":1,"levels":1,"rot":0,"notes":[]}]""")
let state = newObj(@[("photos", photos), ("equipment", equipment), ("reviews", reviews), ("added_tags", added),
                     ("links", newArr())])
var m = Model()
m.sheets = parseSheets(sheets)
m.baseTags = parseTags(tags)
m.kksTables = kksTables
m.locations = buildLocations(newObj(@[("entries", locs)]))
m.state = state
m.merge()
echo toText(newObj(@[("sheets", sheets), ("tags", tags), ("kks", kksTables), ("locations", locs), ("state", state),
                     ("expected", coverageView(m))]))
