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
    let all = c.photoCovers
    for k in ["11LAB70AA501", "11LAB70AA502", "11LAB70AA504", "11LAB70AA503"]:
      check all.getOrDefault(k, "none") == c.photoCover(k)
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

suite "links between sheets":
  proc linked(): Model =
    result = Model()
    result.sheets = parseSheets(j("""[
      {"id":"lp","name":"LP","w":2000,"h":1000,"scale":2.0,"levels":3,"rot":0,"notes":[],
       "links":[{"label":"C16","bbox":[100,200,142,242],"conf":1.0},{"label":"D2","bbox":[300,200,342,242],"conf":0.6},
                {"label":"S3","bbox":[500,200,542,242],"conf":1.0},{"label":"C47","bbox":[700,200,742,242],"conf":1.0},
                {"label":"C47","bbox":[900,200,942,242],"conf":1.0}]},
      {"id":"old","name":"Old sheet","w":1000,"h":500,"scale":1.0,"levels":2,"rot":0,"notes":[]},
      {"id":"cbd","name":"Drains","w":1000,"h":500,"scale":1.0,"levels":2,"rot":0,"notes":[],
       "links":[{"label":"C16","bbox":[10,20,31,41],"conf":1.0},{"label":"C47","bbox":[50,20,71,41],"conf":0.9},
                {"label":"bad"},{"label":"X1","bbox":[1,2,3]},7]},
      {"id":"fw","name":"FW","w":1000,"h":500,"scale":0.5,"levels":2,"rot":0,"notes":[],
       "links":[{"label":"D2","bbox":[100,100,110,110]}]}]"""))
    result.merge()
  let m = linked()
  test "parsed; a sheet without the field and broken entries are fine":
    check m.sheets[0].links.len == 5
    check m.sheets[1].links.len == 0
    check m.sheets[2].links.len == 2
    check m.sheets[3].links[0].conf == 1.0       # no conf: taken as read
    check sheetsView(m)[0]["links"].i == 5 and sheetsView(m)[1]["links"].i == 0
    check linksView(m, "old").elems.len == 0
    check linksView(m, "nope").elems.len == 0
  test "each connector with its targets on the other sheets, boxes in points":
    let v = linksView(m, "lp")
    check v.elems.len == 5
    check v[0]["label"].s == "C16" and v[0]["x0"].num == 50 and v[0]["y1"].num == 121
    check v[0]["targets"].elems.len == 1
    let t = v[0]["targets"][0]
    check t["sheet"].s == "cbd" and t["sheet_name"].s == "Drains" and not t["same_sheet"].b
    check t["x0"].num == 10 and t["y0"].num == 20 and t["x1"].num == 31 and t["y1"].num == 41
    check v[1]["label"].s == "D2" and v[1]["conf"].num == 0.6
    check v[1]["targets"][0]["sheet"].s == "fw" and v[1]["targets"][0]["x1"].num == 220    # fw: 0.5 px per point
    check v[2]["label"].s == "S3" and v[2]["targets"].elems.len == 0                      # the other end isn't here
  test "the same label twice on a sheet: the other sheet first, then the other circle on this one":
    let v = linksView(m, "lp")
    check v[3]["targets"].elems.len == 2
    check v[3]["targets"][0]["sheet"].s == "cbd"
    check v[3]["targets"][1]["sheet"].s == "lp" and v[3]["targets"][1]["same_sheet"].b and v[3]["targets"][1]["x0"].num == 450
    check v[4]["targets"][1]["x0"].num == 350
    let c = linksView(m, "cbd")
    check c[1]["targets"].elems.len == 2 and c[1]["targets"][0]["sheet"].s == "lp" and c[1]["targets"][1]["sheet"].s == "lp"
