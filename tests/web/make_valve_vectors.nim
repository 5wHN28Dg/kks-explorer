## tests/web/valve-vectors.json: generated valve tags (seeded: symbols of every shape the core accepts or drops, review
## corrections, equipment custom fields from none to a full list) and core views.tagView's "valve_type" for each, so
## tests/web/test_systems.py can check systems.js KSys.valveType against the Nim core itself.
##   cd core && nim c -r --hints:off --path:src ../tests/web/make_valve_vectors.nim > ../tests/web/valve-vectors.json
import std/[random, strutils]
import kks/[json, model, views]

var r = initRand(20261009)
let types = ["gate valve", "globe valve", "check valve", "control valve", "butterfly valve", "x"]
var tags = newArr()
var equipment = newObj()
var reviews = newObj()
for i in 0 ..< 160:
  let comp = if r.rand(9) < 8: "AA" else: r.sample(["CP", "AP", "CT"])
  let kks = "11LAB" & align($(10 + r.rand(80)), 2, '0') & comp & align($r.rand(999), 3, '0')
  let suffix = if r.rand(9) == 0: "R" else: ""
  var sym: JNode = nil
  let shape = r.rand(19)
  if shape < 14:
    sym = newObj(@[("type", newStr(r.sample(types)))])
    case r.rand(3)
    of 0: sym["actuator"] = newStr("motor")
    of 1: sym["actuator"] = newStr("none")
    of 2: sym["actuator"] = newInt(1)
    else: discard
    case r.rand(4)
    of 0, 1: sym["nc"] = newBool(r.rand(1) == 0)
    of 2: sym["nc"] = newStr("true")
    else: discard
    case r.rand(3)
    of 0, 1: sym["conf"] = newFloat(float(r.rand(100)) / 100)
    of 2: sym["conf"] = newStr("0.9")
    else: discard
    case r.rand(4)
    of 0, 1, 2:
      let x = float(r.rand(1000))
      sym["bbox"] = newArr(@[newFloat(x), newFloat(40), newFloat(x + 36), newFloat(62)])
    of 3: sym["bbox"] = newArr(@[newFloat(1), newFloat(2), newFloat(3)])
    else: sym["bbox"] = newArr(@[newFloat(1), newStr("2"), newFloat(3), newFloat(4)])
  elif shape == 14: sym = newObj(@[("type", newStr(""))])
  elif shape == 15: sym = newObj(@[("type", newStr('v'.repeat(101)))])
  elif shape == 16: sym = newObj(@[("type", newInt(3))])
  elif shape == 17: sym = newStr("gate valve")
  let id = "a:" & $i
  var t = newObj(@[("id", newStr(id)), ("sheet", newStr("a")), ("kks", newStr(kks)), ("suffix", newStr(suffix)),
    ("isa", newNull()), ("kind", newStr("equipment")), ("status", newStr("auto")), ("conf", newFloat(0.9)),
    ("bbox", newArr(@[newInt(1), newInt(1), newInt(2), newInt(2)])), ("read", newArr(@[newStr(""), newStr("")]))])
  if sym != nil: t["symbol"] = sym
  tags.elems.add t
  # a review: the code corrected to another valve or a non-valve
  case r.rand(11)
  of 0: reviews[id] = newObj(@[("status", newStr("confirmed")), ("kks", newStr(kks[0 .. 6] & "CP" & kks[9 .. 11])),
                               ("suffix", newStr("")), ("isa", newStr(""))])
  of 1: reviews[id] = newObj(@[("status", newStr("confirmed")), ("kks", newStr(kks[0 .. 6] & "AA" & kks[9 .. 11])),
                               ("suffix", newStr("")), ("isa", newStr(""))])
  else: discard
  # what is known of the equipment already
  let k = kks & suffix
  var cs = newArr()
  case r.rand(9)
  of 0: cs.elems.add newObj(@[("k", newStr("Valve type")), ("v", newStr("ball valve"))])
  of 1: cs.elems.add newObj(@[("k", newStr("Size")), ("v", newStr("DN50"))]); cs.elems.add newObj(@[("k", newStr("Valve type")), ("v", newStr(""))])
  of 2:
    cs.elems.add newObj(@[("k", newStr("Valve type")), ("v", newStr(""))])
    cs.elems.add newObj(@[("k", newStr("Size")), ("v", newStr("DN80"))])
    cs.elems.add newObj(@[("k", newStr("Valve type")), ("v", newStr(""))])
  of 3:
    for j in 0 ..< 99 + r.rand(1): cs.elems.add newObj(@[("k", newStr("f" & $j)), ("v", newStr($j))])
  of 4: cs.elems.add newStr("not an object"); cs.elems.add newObj(@[("k", newStr("Size")), ("v", newStr("DN25"))])
  of 5: cs.elems.add newObj(@[("k", newStr("Valve type")), ("v", newInt(5))])
  else: discard
  if cs.elems.len > 0 and equipment.get(k) == nil: equipment[k] = newObj(@[("custom", cs), ("notes", newStr("n"))])
let sheets = parseStrict("""[{"id":"a","name":"Sheet A","w":2000,"h":1000,"scale":2.0,"levels":1,"rot":0,"notes":[]}]""")
var m = Model()
m.sheets = parseSheets(sheets)
m.baseTags = parseTags(tags)
m.state = newObj(@[("photos", newArr()), ("equipment", equipment), ("reviews", reviews), ("added_tags", newArr()),
                   ("links", newArr())])
m.merge()
var expected = newObj()
for t in m.baseTags: expected[t.id] = tagView(m, t.id).get("valve_type")
echo toText(newObj(@[("sheets", sheets), ("tags", tags), ("state", m.state), ("expected", expected)]))
