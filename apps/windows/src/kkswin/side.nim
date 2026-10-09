## The left column (R2, R5, R7; the GNOME app's sidebar + sidepages.nim): search, the sheet list, floors, sheet notes,
## marking a missed tag; procedures with their steps and link mode; the review queue.

import std/[strutils, tables, sets, sequtils, math, algorithm]
import kks/json
import kks/model
import appstate
import kksl/dbstore
import w32, ui, win, viewer, systems, multi

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc links(w: Win): seq[JNode] =
  if w.m.state != nil and w.m.state.get("links") != nil: w.m.state["links"].elems else: @[]

proc tagsWithCode(w: Win, code: string): seq[Tag] =
  for t in w.m.tags:
    if t.full == code: result.add t

# ---------------------------------------------------------------- drawings

proc drawingsTab(w: Win, p: Page) =
  var results: seq[Tag]
  var resList: HWND
  proc fill(q: string) =
    results = if q.strip.len >= 2: w.m.search(q.strip) else: @[]
    var rows: seq[string]
    for t in results:
      let (ok, si) = w.m.sheetById(t.sheet)
      rows.add (if t.full.len > 0: t.full else: "(unread)") & "   " & w.m.kindName(t) & " · " & (if ok: si.name else: t.sheet)
    resList.setRows(if q.strip.len >= 2 and rows.len == 0: @["Nothing found"] else: rows)
  var search: HWND
  search = p.field("Search equipment by KKS code or description", "", onChange = proc () = fill(search.text))
  sendText(search, EM_SETCUEBANNER, 1, "e.g. LAB70AA501 or feed water")
  # the select mode: a result toggles its tag (the keyboard's way to select several)
  resList = p.list(@[], 180, onActivate = (proc (i: int) =
    if i >= results.len: return
    if w.picking:
      let t = results[i]
      if t.sheet != w.sheet: w.showSheet(t.sheet)
      let (okS, si) = w.m.sheetById(t.sheet)
      let sc = if okS and si.scale > 0: si.scale else: 2.0
      w.v.centerOn(t.bbox[0] / sc, t.bbox[1] / sc, t.bbox[2] / sc, t.bbox[3] / sc)
      w.togglePick(t.id)
    else: w.selectTag(results[i].id, true)), openLabel = (if w.picking: "Select or unselect" else: "Show on the drawing"))
  p.dim(if w.picking: "Select tags: Enter or double-click a result to select or unselect its code."
        else: "Enter or double-click a result to show it on its drawing.")
  p.buttons(("Equipment by system…", proc () = w.openSystems()))   # every code, block → system → kind
  p.title("Sheets")
  var rows: seq[string]
  for si in w.m.sheets:
    var n, review = 0
    for t in w.m.tagsOf(si.id):
      inc n
      if t.status == "review": inc review
    rows.add si.name & "  (" & $n & " tags" & (if review > 0: ", " & $review & " to review" else: "") & ")"
  if rows.len == 0: p.dim("Waiting for the drawings. They arrive with the next sync from a device that has them.")
  let sheets = w.m.sheets
  let sl = p.list(rows, 26 * min(10, max(1, rows.len)) + 6, onSelect = proc (i: int) =
    if i < sheets.len: w.showSheet(sheets[i].id))
  for i, si in sheets:
    if si.id == w.sheet: SendMessageW(sl, LB_SETCURSEL, WPARAM(i), 0)
  # floors in use (R5)
  var floors: seq[string]
  for t in w.m.tags:
    let f = s(w.m.equipment(t.full), "floor").strip
    if f.len > 0 and f notin floors: floors.add f
  floors.sort(proc (a, b: string): int = cmp(try: parseInt(a) except ValueError: 99, try: parseInt(b) except ValueError: 99))
  if floors.len > 0:
    p.title("Floor")
    let fl = p.list(@["All floors"] & floors.mapIt("Floor " & it), 26 * min(6, floors.len + 1) + 6, onSelect = proc (i: int) =
      w.floor = if i == 0: "" else: floors[i - 1]
      w.applyHighlights()
      w.toast(if w.floor.len == 0: "All floors" else: "Showing floor " & w.floor & ": other tags are dimmed"))
    SendMessageW(fl, LB_SETCURSEL, WPARAM(if w.floor.len == 0: 0 else: floors.find(w.floor) + 1), 0)
  let (ok, si) = w.m.sheetById(w.sheet)
  if ok and si.notes.len > 0:
    p.title("Notes on this sheet")
    for n in si.notes: p.label(n)
  if ok:
    p.space()
    p.check("Colour tags by photos", w.v.coverage, proc (on: bool) =
      w.v.coverage = on
      InvalidateRect(w.v.hwnd, nil, 0)
      w.toast(if on: "Tags by photos: green both · amber equipment only · blue tag plate only · red none" else: "Tags by how they were read"))
    # dark drawings: a PDF reader's dark mode for the sheets (lightness inverted, hue kept; photos never change),
    # remembered on this device (its store, like sync_peers)
    p.check("Dark drawings", w.v.dark, proc (on: bool) =
      w.v.setDark(on)
      w.a.store.setMeta("dark_drawings", if on: "1" else: ""))
    # the select mode: one photo, place or note for several tags (multi.nim); a check box, so its state is exposed
    p.check("Select tags", w.picking, proc (on: bool) =
      if on != w.picking:
        if on: w.startPicking() else: w.stopPicking())
    p.buttons(("Fit the sheet (0)", proc () = w.v.fit()),      # the whole sheet again, centred (as GNOME and the web)
              ((if w.v.marking: "Stop marking" else: "Mark a missing tag"), proc () =
      if w.picking: w.stopPicking()
      w.v.marking = not w.v.marking
      w.toast(if w.v.marking: "Drag a box around the tag the app missed" else: "")
      w.rebuildSide()))

# ---------------------------------------------------------------- procedures

proc procedureDetail(w: Win, p: Page, id: string) =
  let pr = w.m.procById(id)
  if pr == nil: return
  p.buttons(("‹ All procedures", proc () =
    w.activeProc = ""
    w.linkProc = ""
    w.applyHighlights()
    w.rebuildSide()))
  p.title(s(pr, "id") & "  " & s(pr, "title"))
  var path: seq[string]
  if pr.get("path") != nil:
    for x in pr["path"].elems: path.add x.s
  # `source`: a procedure from another document (tools/procedure_import.py); else the operation manual's page
  let src = if s(pr, "source").len > 0: s(pr, "source") else: "manual page " & (if pr.get("page") != nil: $pr["page"].i else: "?")
  p.dim(path.join(" › ") & " · " & src)
  let ls = w.links.filterIt(it["proc"].s == id)
  if ls.len == 0:
    p.dim("No equipment linked yet. The manual names equipment by description, not KKS: choose “Link equipment” on a " &
          "step, then click the matching tags on the drawing (or use Link in a tag's panel).")
  if s(pr, "intro").len > 0: p.label(s(pr, "intro"))
  if w.linkProc == id:
    p.buttons(("Done linking step " & $w.linkStep, proc () =
      w.linkProc = ""
      w.toast("")
      w.rebuildSide()
      w.rebuildPanel()))
  let lp1 = toSeq(pr["steps"].elems)
  for lp1i in 0 ..< lp1.len:
    closureScope:
      let st = lp1[lp1i]
      let n = int(st["n"].i)
      p.label($n & ")  " & s(st, "text"))
      var specs: seq[(string, proc ())]
      let lp2 = toSeq(ls.filterIt(int(it["step"].i) == n))
      for lp2i in 0 ..< lp2.len:
        closureScope:
          let l = lp2[lp2i]
          let k = l["kks"].s
          let ts = w.tagsWithCode(k)
          specs.add (k, proc () =
            if ts.len > 0:
              w.selectTag(ts[0].id, true)     # it shows the sheet (after asking whether to drop a selection)
            else: w.toast(k & " is not on any sheet"))
          specs.add ("Unlink " & k, proc () =
            discard w.submit("link", newObj(@[("proc", newStr(id)), ("step", newInt(n)), ("kks", newStr(k)), ("on", newBool(false))]),
                             "unlink " & k)
            w.loadModel()
            w.applyHighlights()
            w.rebuildSide())
      specs.add ("+ Link equipment", proc () =
        w.linkProc = id
        w.linkStep = n
        w.toast("Click tags on the drawing (or Link in a tag's panel) to link them to step " & $n & " of " & id)
        w.rebuildSide()
        w.rebuildPanel())
      p.buttons(specs)

proc proceduresTab(w: Win, p: Page) =
  if w.activeProc.len > 0:
    w.procedureDetail(p, w.activeProc)
    return
  if w.m.procs == nil or w.m.procs.elems.len == 0:
    p.dim("No procedures yet: they come with the plant data.")
    return
  var shown: seq[JNode]
  var lst: HWND
  proc hayOf(pr: JNode): string =
    result = (s(pr, "id") & " " & s(pr, "title")).toLowerAscii
    for x in pr["path"].elems: result.add " " & x.s.toLowerAscii
    for st in pr["steps"].elems: result.add " " & s(st, "text").toLowerAscii
  proc fill(q: string) =
    let query = q.strip.toLowerAscii
    shown = w.m.procs.elems.filterIt(query.len == 0 or query in hayOf(it))
    var counts = initCountTable[string]()
    for l in w.links: counts.inc l["proc"].s
    lst.setRows(shown.mapIt(s(it, "id") & "  " & s(it, "title") & "   (" & $it["steps"].elems.len & " steps" &
                            (if counts[s(it, "id")] > 0: ", " & $counts[s(it, "id")] & " linked" else: "") & ")"))
  var q: HWND
  q = p.field("Search procedures", "", onChange = proc () = fill(q.text))
  lst = p.list(@[], 480, onActivate = (proc (i: int) =
    if i < shown.len:
      w.activeProc = s(shown[i], "id")
      w.applyHighlights()
      w.rebuildSide()), openLabel = "Open the procedure")
  p.dim("Enter or double-click a procedure to open it.")
  fill("")

# ---------------------------------------------------------------- the review queue

proc reviewTab(w: Win, p: Page) =
  let reviews = if w.m.state != nil: w.m.state.get("reviews") else: nil
  var todo: seq[Tag]
  for t in w.m.tags:
    if t.status == "review" and (reviews == nil or reviews.get(t.id) == nil): todo.add t
  p.title("Readings to check")
  if todo.len == 0:
    p.dim("Nothing to check: every reading was confirmed or rejected.")
    return
  var rows: seq[string]
  for t in todo:
    let (ok, si) = w.m.sheetById(t.sheet)
    rows.add (if s(t.suggestion, "kks").len > 0: s(t.suggestion, "kks") else: t.read[0] & " / " & t.read[1]) &
             "   " & (if ok: si.name else: t.sheet) & " · " & $int(round(t.conf * 100)) & " %"
  p.list(rows, 480, onActivate = (proc (i: int) =
    if i < todo.len: w.selectTag(todo[i].id, true)), openLabel = "Check it on the drawing")
  p.dim("Enter or double-click a reading to check it on the drawing.")

proc buildSide*(w: Win, manage: proc (p: Page)) =
  let p = w.side
  p.clear()
  case w.tab
  of "procedures": w.proceduresTab(p)
  of "review": w.reviewTab(p)
  of "manage": manage(p)
  else: w.drawingsTab(p)
  p.layout()
