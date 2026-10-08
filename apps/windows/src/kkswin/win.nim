## The window's shared state and the actions every screen uses (the GNOME app's win.nim, for Win32).

import std/[strutils, tables, sets]
import kks/[json, api]
import kks/model
import appstate
import w32, ui, viewer

type Follower* = ref object
  area*: HWND                ## the control a rebuild replaces the contents of (a tree)
  rebuild*: proc ()
  stale*: bool

type Win* = ref object
  a*: App
  hwnd*: HWND
  m*: Model
  v*: Viewer
  side*: Page               ## the left column: search, sheets, procedures, review, manage
  panel*: Page              ## the right column: the selected tag
  status*: HWND             ## the status line (last message, sync state)
  tab*: string              ## "drawings" | "procedures" | "review" | "manage"
  tabButtons*: seq[HWND]
  sheet*: string
  selected*: string
  linkProc*: string         ## link mode (R7): clicks on tags link them to this procedure step
  linkStep*: int
  activeProc*: string
  floor*: string
  showSheet*: proc (id: string)
  selectTag*: proc (id: string, center: bool)
  rebuildPanel*: proc ()
  rebuildSide*: proc ()
  relayout*: proc ()
  lastMsg*: string
  followers*: seq[Follower]  ## open windows that follow the plant's data (follow)

proc focusInside(area: HWND): bool =
  let f = GetFocus()
  f != nil and (f == area or IsChild(area, f) != 0)

proc follow*(w: Win, area: HWND, rebuild: proc ()): Follower =
  ## `area` shows data that syncs and approvals change (refreshFollowers rebuilds it), but never under the keyboard
  ## or screen reader's focus: while the focus is in it, it is only marked stale, and rebuilt when the focus has left
  ## (catchUpFollowers, every second) or by the window itself (a search sets `stale` false)
  result = Follower(area: area, rebuild: rebuild)
  w.followers.add result

proc refreshFollowers*(w: Win) =
  var keep: seq[Follower]
  for f in w.followers:
    if IsWindow(f.area) == 0: continue          # its window was closed
    keep.add f
    if focusInside(f.area): f.stale = true
    else:
      f.stale = false
      f.rebuild()
  w.followers = keep

proc catchUpFollowers*(w: Win) =
  for f in w.followers:
    if f.stale and IsWindow(f.area) != 0 and not focusInside(f.area):
      f.stale = false
      f.rebuild()

proc toast*(w: Win, msg: string) =
  w.lastMsg = msg
  w.status.setText(msg)

proc fileOr*(w: Win, path: string, dflt: string): string =
  let (ok, data) = w.a.file(path)
  if ok: data else: dflt

const BuiltInTables = staticRead("../../../../data/kks.json")
  ## the KKS decode tables ship inside the program (public data): no file next to the exe is needed

proc loadModel*(w: Win) =
  let m = Model()
  m.sheets = parseSheets(parseStrict(w.fileOr("sheets.json", "[]"), 4096))
  m.baseTags = parseTags(parseStrict(w.fileOr("tags.json", "[]"), 4096))
  m.procs = parseStrict(w.fileOr("procedures.json", "[]"), 4096)
  m.locations = buildLocations(parseStrict(w.fileOr("locations.json", "{}"), 4096))
  m.kksTables = parseStrict(w.fileOr("kks.json", BuiltInTables), 4096)
  try: m.state = w.a.call("GET", "/api/state")
  except ApiError: m.state = newObj()
  m.merge()
  w.m = m

proc isAdmin*(w: Win): bool =
  let (ok, me) = w.a.me
  ok and me.isAdmin

proc submit*(w: Win, kind: string, payload: JNode, what: string, note = ""): string =
  ## Propose a change (members) or make it (admins). -> "approved", "pending", "conflict" or "" on error.
  var body = newObj(@[("kind", newStr(kind)), ("payload", payload)])
  if note.strip.len > 0: body["note"] = newStr(note.strip)
  try:
    let r = w.a.call("POST", "/api/submit", body)
    result = if r.get("status") != nil and r["status"].isStr: r["status"].s else: "pending"
    case result
    of "approved": w.toast("Saved: " & what)
    of "conflict": w.toast("Held: it clashes with a pending change (see Approvals)")
    else: w.toast("Sent for approval: " & what)
  except ApiError as e:
    w.toast(e.msg)
    result = ""

proc myOpen*(w: Win): seq[JNode] =
  try:
    let r = w.a.call("GET", "/api/submissions", nil, {"status": "open"}.toTable)
    for s in r["submissions"].elems:
      if s.get("mine") != nil and s["mine"].kind == jBool and s["mine"].b: result.add s
  except ApiError: discard

proc tagBoxes*(w: Win, sheet: string): seq[TagBox] =
  let (ok, si) = w.m.sheetById(sheet)
  let s = if ok and si.scale > 0: si.scale else: 2.0
  let covers = w.m.photoCovers          # one pass over the photos for all tags
  for t in w.m.tagsOf(sheet):
    result.add TagBox(id: t.id, x0: t.bbox[0] / s, y0: t.bbox[1] / s, x1: t.bbox[2] / s, y1: t.bbox[3] / s,
                      status: (if t.status == "confirmed": "verified" else: t.status), code: t.full,
                      photos: covers.getOrDefault(t.full, "none"))
  for sub in w.myOpen():         # my pending marks (R6), dashed
    if sub["kind"].s == "tag_add" and sub.get("payload") != nil:
      let p = sub["payload"]
      if p.get("sheet") != nil and p["sheet"].s == sheet and p.get("bbox") != nil:
        let b = p["bbox"]
        result.add TagBox(id: "pending:" & $sub["id"].i, x0: b[0].num / s, y0: b[1].num / s, x1: b[2].num / s,
                          y1: b[3].num / s, status: "pending")

proc applyHighlights*(w: Win) =
  ## the active procedure's linked equipment (R7) and the floor filter (R5)
  var codes: HashSet[string]
  if w.activeProc.len > 0 and w.m.state != nil and w.m.state.get("links") != nil:
    for l in w.m.state["links"].elems:
      if l["proc"].s == w.activeProc: codes.incl l["kks"].s
  w.v.highlight.clear()
  for t in w.v.tags:
    if t.code.len > 0 and t.code in codes: w.v.highlight.incl t.id
  w.v.dimming = w.floor.len > 0
  w.v.dimmed.clear()
  if w.floor.len > 0:
    for t in w.v.tags:
      if t.code.len > 0 and w.m.equipment(t.code).get("floor") != nil and w.m.equipment(t.code)["floor"].isStr and
         w.m.equipment(t.code)["floor"].s.strip == w.floor: w.v.dimmed.incl t.id
  w.v.invalidate()

proc statusText*(w: Win): string =
  let snap = w.a.snapshot
  var parts: seq[string]
  if w.a.syncing: parts.add "Syncing…"
  elif snap["last_ok"].kind == jInt:
    parts.add "Last sync " & ($snap["last_ok"].i)   # replaced by a time below
  parts.join(" · ")
