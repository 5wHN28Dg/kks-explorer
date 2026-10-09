## The valve type from the drawing's symbol (tags.json "symbol", importer/README): parsed when present, shown on the
## panel as unchecked, confirmed or corrected through the normal equipment proposal (a custom field). Synthetic data.
import std/[unittest, tables]
import kks/[json, util, crypto, proto, replay, node, plant, api, model, views]
import testprovider

let P = testProvider()
var clock = 1_790_000_000_000'i64
proc now(): int64 =
  clock += 1000
  clock

proc j(s: string): JNode = parseStrict(s)

proc plant(): Model =
  result = Model()
  result.sheets = parseSheets(j("""[{"id":"a","name":"Sheet A","w":2000,"h":1000,"scale":2.0,"levels":3,"rot":0}]"""))
  result.baseTags = parseTags(j("""[
    {"id":"a:1","sheet":"a","kks":"11LAB70AA501","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":1,
     "bbox":[200,100,240,120],"read":["11LAB70","AA501"],
     "symbol":{"type":"gate valve","actuator":"motor","nc":false,"conf":0.93,"bbox":[200,60,240,96]}},
    {"id":"a:2","sheet":"a","kks":"11LAB70AA502","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":1,
     "bbox":[300,100,340,120],"read":["11LAB70","AA502"]},
    {"id":"a:3","sheet":"a","kks":"11LAB70AA503","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":1,
     "bbox":[400,100,440,120],"read":["11LAB70","AA503"],"symbol":{"type":"globe valve","actuator":"none","nc":true,"conf":0.8}},
    {"id":"a:4","sheet":"a","kks":"11LAB70AA504","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":1,
     "bbox":[500,100,540,120],"read":["11LAB70","AA504"],"symbol":"not an object"}]"""))
  result.state = j("""{"equipment":{}}""")
  result.merge()

suite "valve type: the panel":
  let m = plant()
  test "from the drawing, unchecked, with its symbol's box in points":
    let v = tagView(m, "a:1")["valve_type"]
    check v["status"].s == "drawing"
    check v["text"].s == "gate valve, motor-operated"
    check v["line"].s == "Valve type: gate valve, motor-operated (from the drawing, unchecked)"
    check v["conf"].num == 0.93
    check v["box"][0].num == 100.0 and v["box"][3].num == 48.0
    let c = v["confirm"]
    check c["kind"].s == "equipment"
    check c["payload"]["changes"]["custom"][0]["k"].s == ValveTypeKey
    check c["payload"]["changes"]["custom"][0]["v"].s == "gate valve, motor-operated"
    check c["payload"]["base"]["custom"].len == 0
  test "hatched (nc) = normally closed, also in the confirm proposal; no box when the importer gave none":
    let v = tagView(m, "a:3")["valve_type"]
    check v["text"].s == "globe valve, normally closed"
    check v["line"].s == "Valve type: globe valve, normally closed (from the drawing, unchecked)"
    check v["confirm"]["payload"]["changes"]["custom"][0]["v"].s == "globe valve, normally closed"
    check v.get("box") == nil
  test "old plant data (no symbol field) and a malformed one: no valve type":
    check tagView(m, "a:2")["valve_type"].isNull
    check tagView(m, "a:4")["valve_type"].isNull
    check m.tagById("a:4")[1].symbol == nil

suite "valve type: confirmed and corrected through the proposal flow":
  let rootKey = P.p256Generate()
  var n = newNode(P, newMemStore(), P.p256Generate())
  discard n.append("genesis", P.genesisBody(rootKey, "Test plant", n.device, P.newPersonId(), "boss", "The Manager"), now())
  n.adopt(keyString(rootKey.pub))
  let a = newApi(n)
  let (_, mgr) = a.owner
  let m = plant()
  proc submit(c: JNode): int =
    a.handle(mgr, "POST", "/api/submit", initTable[string, string](), c, now()).status
  proc refresh() =
    m.state = a.handle(mgr, "GET", "/api/state", initTable[string, string](), nil, now()).json
    m.merge()
  test "confirming the drawing's reading as it is":
    let c = tagView(m, "a:1")["valve_type"]["confirm"]
    check submit(c) == 200
    refresh()
    let v = tagView(m, "a:1")["valve_type"]
    check v["status"].s == "confirmed"
    check v["text"].s == "gate valve, motor-operated"
    check v["line"].s == "Valve type: gate valve, motor-operated (confirmed)"
    check not v["drawn_differs"].b
    check v.get("confirm") == nil
  test "a correction: the person's value wins, the drawing's reading stays visible":
    let c = tagView(m, "a:3")["valve_type"]["confirm"].copy
    c["payload"]["changes"]["custom"][0]["v"] = newStr("check valve")
    check submit(c) == 200
    refresh()
    let v = tagView(m, "a:3")["valve_type"]
    check v["status"].s == "confirmed" and v["text"].s == "check valve"
    check v["drawn"].s == "globe valve, normally closed" and v["drawn_differs"].b
  test "a type set by hand on equipment without a symbol shows too":
    check submit(j("""{"kind":"equipment","payload":{"kks":"11LAB70AA502","changes":{"custom":[{"k":"Valve type","v":"butterfly valve"}]}}}""")) == 200
    refresh()
    check tagView(m, "a:2")["valve_type"]["text"].s == "butterfly valve"

suite "valve type: the proposal's edge cases":
  test "an empty Valve type entry is replaced, not doubled; a full custom list offers no confirm":
    let m = plant()
    m.state = j("""{"equipment":{"11LAB70AA501":{"custom":[{"k":"Size","v":"DN50"},{"k":"Valve type","v":""}]}}}""")
    m.merge()
    let v = tagView(m, "a:1")["valve_type"]
    check v["status"].s == "drawing"
    let c = v["confirm"]["payload"]["changes"]["custom"]
    check c.len == 2 and c[0]["k"].s == "Size" and c[1]["k"].s == ValveTypeKey and c[1]["v"].s == "gate valve, motor-operated"
    var full = newArr()
    for i in 0 ..< 100: full.elems.add newObj(@[("k", newStr("f" & $i)), ("v", newStr("x"))])
    m.state = newObj(@[("equipment", newObj(@[("11LAB70AA501", newObj(@[("custom", full)]))]))])
    m.merge()
    let w = tagView(m, "a:1")["valve_type"]
    check w["status"].s == "drawing" and w["confirm"].isNull
