## model.nim + views.nim: what the screens show, on synthetic plant data (no plant data in the repository).
import std/[unittest, tables, strutils]
import kks/[json, model, views, pathstore]

proc j(s: string): JNode = parseStrict(s)

proc sample(): Model =
  result = Model()
  result.sheets = parseSheets(j("""[{"id":"a","name":"Sheet A","w":2000,"h":1000,"scale":2.0,"levels":3,"rot":0,"notes":["markup"]}]"""))
  result.baseTags = parseTags(j("""[
    {"id":"a:1","sheet":"a","kks":"11LAB70","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":0.9,"bbox":[100,100,140,120],"read":["11LAB70","AA501"]},
    {"id":"a:2","sheet":"a","kks":"11LAB70AA501","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":0.9,"bbox":[200,100,240,120],"read":["11LAB70","AA501"]},
    {"id":"a:3","sheet":"a","kks":"11HAD70CT101","suffix":"R","isa":"TIAC","kind":"instrument","status":"auto","conf":1,"bbox":[300,100,330,160],"read":["TIAC","11HAD70CT101R"]},
    {"id":"a:4","sheet":"a","kks":null,"suffix":"","isa":null,"kind":"other","status":"review","conf":0.1,"bbox":[400,100,430,120],"read":["??","LAB7"]},
    {"id":"a:5","sheet":"a","kks":"11LAB70AA502","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":0.9,"bbox":[500,100,540,120],"read":["",""]}]"""))
  result.kksTables = j("""{"systems":{"LAB":"Feed water piping system","HAD":"HP drum"},"components":{"AA":"Valve","CT":"Temperature measurement"},
    "isa_first":{"T":"Temperature"},"isa_next":{"I":"Indicate","A":"Alarm","C":"Control"},"blocks":{"11":"Block 1"}}""")
  result.locations = buildLocations(j("""{"entries":[{"kks":"LAB70AA501","level":"14.50m","cabinet":"C1","desc":"feed valve"},
                                                    {"kks":"LAB70AA501","level":"14.5 m","cabinet":"C1"}]}"""))
  result.procs = j("""[{"id":"1.1","title":"Start","path":["1 Intro"],"page":3,"steps":[{"n":1,"text":"Open the feed valve"}]}]""")
  result.state = j("""{"equipment":{"11LAB70AA501":{"floor":"3","notes":"leaks"}},
    "reviews":{"a:4":{"status":"confirmed","kks":"11LAB70AA503","suffix":"","isa":null},"a:5":{"status":"rejected"}},
    "photos":[{"id":"p1","kks":"11LAB70AA501","file":"x.jxl","caption":"c"}],
    "links":[{"proc":"1.1","step":1,"kks":"11LAB70AA501"}],
    "added_tags":[{"id":"00112233445566778899aabbccddeeff","sheet":"a","bbox":[600,100,640,120],"kks":"11LAB70AA504","suffix":"","isa":null,"kind":"equipment","note":""}]}""")
  result.merge()

suite "model":
  let m = sample()
  test "reviews override the reader; rejected tags go; added tags join":
    check m.tagById("a:4")[1].full == "11LAB70AA503"
    check m.tagById("a:4")[1].status == "confirmed"
    check not m.tagById("a:5")[0]
    check m.tagById("u:00112233445566778899aabbccddeeff")[1].status == "verified"
  test "decoding":
    let (ok, d) = m.decode(m.tagById("a:3")[1])
    check ok and d.sys == "HAD" and d.comp == "CT" and d.isa == "Temperature — Indicate, Alarm, Control"
    check not m.decode(m.tagById("a:1")[1])[0]
  test "photo coverage: equipment, tag plate, both, none (a caption starting Tag plate)":
    let c = sample()
    c.state["photos"].elems.add j("""{"id":"p2","kks":"11LAB70AA501","file":"y.jxl","caption":"Tag plate · north"}""")
    c.state["photos"].elems.add j("""{"id":"p3","kks":"11LAB70AA502","file":"z.jxl","caption":"Tag plate"}""")
    c.state["photos"].elems.add j("""{"id":"p4","kks":"11LAB70AA504","file":"w.jxl","caption":"the valve"}""")
    check c.photoCover("11LAB70AA501") == "both"
    check c.photoCover("11LAB70AA502") == "plate"
    check c.photoCover("11LAB70AA504") == "equipment"
    check c.photoCover("11HAD70CT101R") == "none"
    check c.photoCover("") == "none"
    var seen: Table[string, string]
    for t in tagsView(c, "a").elems: seen[t["code"].s] = t["photos"].s
    check seen["11LAB70AA501"] == "both" and seen["11HAD70CT101R"] == "none"
  test "the location list: one elevation when the rows agree":
    check m.refLoc("LAB70AA501").elev == "14.5 m"
    check m.refLoc("LAB70AA501").cabinet == "C1"
  test "search: exact codes first, without the unit, partial, by description":
    check m.search("11LAB70AA501")[0].id == "a:2"
    check m.search("LAB70AA501")[0].id == "a:2"
    check m.search("HAD70CT101R")[0].id == "a:3"
    check m.search("feed valve").len >= 1

suite "views":
  let m = sample()
  test "the panel":
    let v = tagView(m, "a:2")
    check v["decoded"]["sys_name"].s == "Feed water piping system"
    check v["equipment"]["floor"].s == "3"
    check v["photos"].elems.len == 1
    check v["procedures"][0]["title"].s == "Start"
    check v["list_elev"].s == "14.5 m"
    check v["box"][0].num == 100.0
  test "sheets, tags in points, review queue, procedures, floors":
    check sheetsView(m)[0]["tags"].i == 5
    check tagsView(m, "a")[0]["x0"].num == 50.0
    check reviewView(m).elems.len == 0
    check procView(m, "1.1")["links"][0]["tag"].s == "a:2"
    check floorsView(m)["3"].elems.len == 1
  test "systems: block, system, subsystem, kind; each code once; search; undecoded codes apart":
    let v = systemsView(m)
    # a:2 11LAB70AA501, a:3 11HAD70CT101R, a:4 → 11LAB70AA503, added 11LAB70AA504; a:1 11LAB70 doesn't decode; a:5 rejected
    check v["total"].i == 5
    check v["blocks"].elems.len == 1 and v["blocks"][0]["blk"].s == "11" and v["blocks"][0]["blk_name"].s == "Block 1"
    let systems = v["blocks"][0]["systems"]
    check systems.elems.len == 2 and systems[0]["sys"].s == "HAD" and systems[1]["sys"].s == "LAB"
    let lab = systems[1]
    check lab["sys_name"].s == "Feed water piping system" and lab["count"].i == 3
    check lab["subsystems"][0]["code"].s == "LAB70"
    let valves = lab["subsystems"][0]["kinds"][0]
    check valves["comp"].s == "AA" and valves["comp_name"].s == "Valve"
    var codes: seq[string]
    for it in valves["items"].elems: codes.add it["code"].s
    check codes == @["11LAB70AA501", "11LAB70AA503", "11LAB70AA504"]
    check valves["items"][0]["desc"].s == "feed valve" and valves["items"][0]["photos"].s == "equipment"
    check v["other"].elems.len == 1 and v["other"][0]["code"].s == "11LAB70"
    check systemsView(m, "temperature")["total"].i == 1
    check systemsView(m, "feed lab70 valve")["total"].i == 3
    check systemsView(m, "had")["blocks"][0]["systems"].elems.len == 1
    check systemsView(m, "nothing like this")["total"].i == 0
  test "systems: a code on two sheets is listed once, with its count":
    let c = sample()
    c.baseTags.add parseTags(j("""[{"id":"b:1","sheet":"a","kks":"11LAB70AA501","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":0.9,"bbox":[10,10,20,20],"read":["",""]}]"""))
    c.merge()
    let lab = systemsView(c)["blocks"][0]["systems"][1]
    check lab["subsystems"][0]["kinds"][0]["items"][0]["count"].i == 2
  test "coverage: per sheet, per system, totals":
    let v = coverageView(m)
    # tags left: a:1 11LAB70 (auto), a:2 AA501 (auto), a:3 CT101R (auto), a:4 → AA503 (confirmed), added AA504 (verified)
    let t = v["total"]
    check t["tags"].i == 5 and t["verified"].i == 2 and t["review"].i == 0 and t["marked"].i == 1
    check t["codes"].i == 5
    # photos: AA501 has an equipment photo (p1); the rest none
    check t["photos"]["equipment"].i == 1 and t["photos"]["none"].i == 4 and t["photos"]["both"].i == 0
    # places: AA501 from the location list and its floor; nothing else
    check t["located"].i == 1
    check v["sheets"].elems.len == 1 and v["sheets"][0]["name"].s == "Sheet A" and v["sheets"][0]["codes"].i == 5
    var names: seq[string]
    for s in v["systems"].elems: names.add s["sys"].s
    check names == @["", "HAD", "LAB"]      # "" = codes that don't decode (11LAB70)
    let lab = v["systems"][2]
    check lab["codes"].i == 3 and lab["verified"].i == 2 and lab["located"].i == 1 and lab.get("tags") == nil
  test "coverage: a place typed by a person counts":
    let c = sample()
    c.state["equipment"]["11LAB70AA504"] = j("""{"area":"pump house"}""")
    c.merge()
    check coverageView(c)["total"]["located"].i == 2
  test "the flat path store":
    var d = Drawing(width: 640, height: 320, gx: 1, gy: 1)
    d.styles.add Style(kind: Stroke, width: 64)
    d.paths.add pathstore.Path(style: 0, bbox: [0'i64, 0, 64, 64], cmdStart: 0, cmdCount: 2, ptStart: 0)
    d.ops = @[OpMove, OpLine]
    d.xy = @[0'i64, 0, 64, 64]
    d.cells = @[@[0'i32]]
    let f = flat(d)
    check f[0 ..< 4] == "KKF1"
    check f.len == 4 + 9 * 4 + 16 + 32 + 4 + 16 + 8 + 4
