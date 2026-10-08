## tests/web/systems-vectors.json: a generated plant (seeded) and core views.systemsView's answers for a set of
## searches, so tests/web/test_systems.py can check systems.js against the Nim core itself, not hand-copied values.
##   cd core && nim c -r --hints:off --path:src ../tests/web/make_systems_vectors.nim > ../tests/web/systems-vectors.json
import std/[random, strutils, os]
import kks/[json, model, views]

var r = initRand(20261007)
let kksTables = parseStrict(readFile(currentSourcePath().parentDir.parentDir.parentDir / "data" / "kks.json"))
var systems, comps: seq[string]
for (k, _) in kksTables["systems"].fields: systems.add k
for (k, _) in kksTables["components"].fields: comps.add k
let blocks = ["11", "12", "21"]
let isas = ["TI", "TIAC", "PI", "PDIA", "LIASC", "FIAC"]
var tags = newArr()
var codes: seq[string]
for i in 0 ..< 400:
  let sheet = ["a", "b", "c"][i mod 3]
  var kks: JNode
  var suffix = ""
  var isa: JNode = newNull()
  var kind = "equipment"
  let roll = r.rand(99)
  if roll < 5: kks = newNull(); kind = "other"                                     # unreadable
  elif roll < 9: kks = newStr(r.sample(blocks) & r.sample(systems) & $(10 + r.rand(80)))   # doesn't decode
  elif roll < 20 and codes.len > 0: kks = newStr(r.sample(codes))                  # the same code again
  else:
    let k = r.sample(blocks) & r.sample(systems) & align($(10 + r.rand(89)), 2, '0') & r.sample(comps) & align($r.rand(999), 3, '0')
    kks = newStr(k)
    codes.add k
    if roll mod 4 == 0:
      kind = "instrument"; isa = newStr(r.sample(isas))
      if roll mod 8 == 0: suffix = "R"
  tags.elems.add newObj(@[("id", newStr(sheet & ":" & $i)), ("sheet", newStr(sheet)), ("kks", kks), ("suffix", newStr(suffix)),
    ("isa", isa), ("kind", newStr(kind)), ("status", newStr(if roll mod 5 == 0: "verified" else: "auto")), ("conf", newFloat(0.9)),
    ("bbox", newArr(@[newInt(1), newInt(1), newInt(2), newInt(2)])), ("read", newArr(@[newStr(""), newStr("")]))])
var photos = newArr()
for i in 0 ..< 150:
  photos.elems.add newObj(@[("id", newStr("p" & $i)), ("kks", newStr(r.sample(codes))), ("file", newStr("x.jxl")),
    ("caption", newStr(if r.rand(2) == 0: "Tag plate · " & $i else: "view " & $i))])
var locs = newArr()
for i in 0 ..< 60:
  let k = r.sample(codes)
  locs.elems.add newObj(@[("kks", newStr(k[2 .. ^1])), ("level", newStr($r.rand(40) & " m")),
    ("desc", newStr(r.sample(["drain valve", "vent", "feed pump suction", "", "condenser vent", "sampling cooler"])))])
let sheets = parseStrict("""[{"id":"a","name":"Sheet A","w":100,"h":100,"scale":1,"levels":1,"rot":0,"notes":[]},
  {"id":"b","name":"Sheet B","w":100,"h":100,"scale":1,"levels":1,"rot":0,"notes":[]},
  {"id":"c","name":"Sheet C","w":100,"h":100,"scale":1,"levels":1,"rot":0,"notes":[]}]""")
var m = Model()
m.sheets = parseSheets(sheets)
m.baseTags = parseTags(tags)
m.kksTables = kksTables
m.locations = buildLocations(newObj(@[("entries", locs)]))
m.state = newObj(@[("photos", photos), ("equipment", newObj()), ("reviews", newObj()), ("added_tags", newArr()), ("links", newArr())])
m.merge()
let queries = ["", "lab", "valve", "pump", "11", "12 lab", "vent", "condenser vent", "temperature", "aa5", "control",
               "nothing at all", "LBA10", "drain"]
var expected = newObj()
for q in queries: expected[q] = systemsView(m, q)
echo toText(newObj(@[("sheets", sheets), ("tags", tags), ("kks", kksTables), ("locations", locs), ("photos", photos),
                     ("expected", expected)]))
