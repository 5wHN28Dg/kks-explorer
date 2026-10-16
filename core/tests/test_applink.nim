## Links from other apps (docs/PLANT3D.md §6, decision 0057): the two forms Walkdown opens, and everything else,
## hostile input included, reading as nothing. Synthetic data.
import std/[unittest, strutils]
import kks/[json, model, applink]

proc j(s: string): JNode = parseStrict(s)

proc none(s: string): bool = parseAppLink(s).kind == ""

suite "walkdown:// links":
  test "a code":
    let l = parseAppLink("walkdown://kks/11LAB70AA501")
    check l.kind == "kks" and l.code == "11LAB70AA501" and l.course == "" and l.page == ""
    check parseAppLink("walkdown://kks/11HAD70CL503XB31").code == "11HAD70CL503XB31"
    check parseAppLink("walkdown://kks/ABCD").code == "ABCD"                       # 4 characters, the shortest
    check parseAppLink("walkdown://kks/" & "1".repeat(24)).kind == "kks"            # 24, the longest
    check parseAppLink("WALKDOWN://kks/11LAB70AA501").kind == "kks"                 # the scheme in any case (RFC 3986)
    check parseAppLink("WalkDown://kks/11LAB70AA501").kind == "kks"

  test "a course, and a course page":
    let c = parseAppLink("walkdown://course/ppt")
    check c.kind == "course" and c.course == "ppt" and c.page == ""
    let p = parseAppLink("walkdown://course/ppt/m1_intro")
    check p.kind == "course" and p.course == "ppt" and p.page == "m1_intro"
    check parseAppLink("walkdown://course/_x/_").kind == "course"
    check parseAppLink("walkdown://course/" & "a".repeat(32) & "/" & "b".repeat(32)).kind == "course"

  test "malformed codes":
    for s in ["walkdown://kks/", "walkdown://kks/ABC", "walkdown://kks/" & "1".repeat(25), "walkdown://kks/11lab70aa501",
              "walkdown://kks/11LAB70 AA501", "walkdown://kks/11LAB70-AA501", "walkdown://kks/11LCC70/A403",
              "walkdown://kks/11LAB70AA501/", "walkdown://kks//11LAB70AA501", "walkdown://kks/11LAB70AA501?x=1",
              "walkdown://kks/11LAB70AA501#x", "walkdown://kks/11LAB70%41A501", "walkdown://kks/11LAB70AA50\0",
              "walkdown://kks/11LAB70AA501\n", " walkdown://kks/11LAB70AA501", "walkdown://kks/11LAB70AA501 ",
              "walkdown://kks/11LAB70ÄA501", "walkdown://KKS/11LAB70AA501", "walkdown://kks/../11LAB70AA501",
              "walkdown://kks/11LAB70AA501/extra"]:
      check none(s)

  test "malformed courses":
    for s in ["walkdown://course", "walkdown://course/", "walkdown://course//p", "walkdown://course/ppt/",
              "walkdown://course/ppt/p/q", "walkdown://course/PPT", "walkdown://course/1ppt", "walkdown://course/ppt/1",
              "walkdown://course/" & "a".repeat(33), "walkdown://course/ppt/" & "b".repeat(33),
              "walkdown://course/../../etc/passwd", "walkdown://course/ppt.json", "walkdown://course/ppt%2Fx",
              "walkdown://course/ppt?page=x", "walkdown://course/ppt#x", "walkdown://course/p-t"]:
      check none(s)

  test "other schemes, kinds and actions read as nothing":
    for s in ["", "walkdown:", "walkdown://", "walkdown:///", "walkdown:kks/11LAB70AA501", "walkdown:/kks/11LAB70AA501",
              "walkdown-plant://kks/11LAB70AA501", "walkdownx://kks/11LAB70AA501", "xwalkdown://kks/11LAB70AA501",
              "https://kks/11LAB70AA501", "file:///etc/passwd", "walkdown://user@kks/11LAB70AA501",
              "walkdown://kks:80/11LAB70AA501", "walkdown://procedure/cold_start", "walkdown://procedure/cold_start/2",
              "walkdown://join/abc", "walkdown://sign-in/x", "walkdown://import/https://example.org/a.pdf",
              "walkdown://delete/11LAB70AA501", "walkdown://url/https://example.org", "walkdown://kks",
              "walkdown://course?x", "javascript:alert(1)"]:
      check none(s)

  test "length: nothing over 128 characters is read":
    check parseAppLink("walkdown://course/" & "a".repeat(32) & "/" & "b".repeat(32)).kind == "course"   # 83
    check none("walkdown://kks/11LAB70AA501" & "/".repeat(200))
    check none("walkdown://kks/" & "A".repeat(100_000))

  test "every byte value in a code, or a page, makes it nothing unless it is one the grammar allows":
    for b in 0 .. 255:
      let c = char(b)
      let k = parseAppLink("walkdown://kks/11LAB" & c & "0AA501").kind
      check (k == "kks") == (c in {'0'..'9', 'A'..'Z'})
      let p = parseAppLink("walkdown://course/ppt/m" & c).kind
      check (p == "course") == (c in {'a'..'z', '0'..'9', '_'})

suite "the tag a code link opens":
  var m = Model()
  m.sheets = parseSheets(j("""[{"id":"a","name":"A","w":100,"h":100,"scale":2.0,"levels":1,"rot":0},
                               {"id":"b","name":"B","w":100,"h":100,"scale":2.0,"levels":1,"rot":0}]"""))
  m.baseTags = parseTags(j("""[
    {"id":"a:1","sheet":"a","kks":"11HAD70CT101","suffix":"R","isa":"TI","kind":"instrument","status":"auto","conf":1,
     "bbox":[1,1,2,2],"read":["",""]},
    {"id":"a:2","sheet":"a","kks":"","suffix":"","isa":null,"kind":"equipment","status":"review","conf":0,
     "bbox":[3,3,4,4],"read":["",""]},
    {"id":"b:1","sheet":"b","kks":"11LAB70AA501","suffix":"","isa":null,"kind":"equipment","status":"auto","conf":1,
     "bbox":[1,1,2,2],"read":["",""]},
    {"id":"b:2","sheet":"b","kks":"11HAD70CT101","suffix":"","isa":"TI","kind":"instrument","status":"auto","conf":1,
     "bbox":[3,3,4,4],"read":["",""]},
    {"id":"b:3","sheet":"b","kks":"11HAD70CT101","suffix":"R","isa":"TI","kind":"instrument","status":"auto","conf":1,
     "bbox":[5,5,6,6],"read":["",""]}]"""))
  m.state = j("""{"equipment":{}}""")
  m.merge()

  test "the full code first, in the drawings' order":
    check m.findCode("11HAD70CT101R") == (true, m.tagById("a:1")[1])
    check m.findCode("11LAB70AA501")[1].id == "b:1"

  test "a code without its suffix finds a tag whose full code it is, else the suffixed one":
    check m.findCode("11HAD70CT101")[1].id == "b:2"
    m.baseTags.delete(3)
    m.merge()
    check m.findCode("11HAD70CT101")[1].id == "a:1"

  test "codes on no drawing, and unread tags, find nothing":
    check not m.findCode("11LAB70AA502")[0]
    check not m.findCode("")[0]
    check not m.findCode("11HAD70")[0]       # a beginning is not the code
