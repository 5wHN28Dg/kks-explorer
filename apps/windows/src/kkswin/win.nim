## The window's shared state and the actions every screen uses (the GNOME app's win.nim, for Win32).

import std/[strutils, tables, sets]
import kks/[json, api]
import kks/model
import appstate
import w32, ui, viewer

type Follower* = ref object
  area*: HWND                ## the control a rebuild replaces the contents of (a tree)
  rebuild*: proc ()
  update*: proc (): bool     ## new numbers into the same controls (allowed under the focus); false: rebuild instead
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
  picking*: bool            ## "Select tags" mode: one photo, place or note for several codes (multi.nim)
  picked*: seq[string]      ## the selected codes, in the order they were picked
  pickSaidUnread*: bool     ## the "no code" message was shown in this round of the mode
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
  queueLabel*: HWND         ## the photo queue's line beside the status (photos.nim), hidden while it is empty
  failedButton*: HWND       ## "Photos not sent (n)…": photos that failed, kept until sent or discarded (photos.nim)
  followers*: seq[Follower]  ## open windows that follow the plant's data (follow)
  panelStale*: bool         ## the panel was left as it is under the keyboard or typed text (panelChanged)
  sideStale*: bool          ## the sidebar was left as it is under the keyboard (sideChanged)
  sideUpdate*: proc (): bool  ## the sidebar's page on screen: new data into its controls as they are (allowed under
                              ## the keyboard); false when its controls themselves would change. nil: it can't

proc focusInside(area: HWND): bool =
  let f = GetFocus()
  f != nil and (f == area or IsChild(area, f) != 0)

proc follow*(w: Win, area: HWND, rebuild: proc (), update: proc (): bool = nil): Follower =
  ## `area` shows data that syncs and approvals change (refreshFollowers rebuilds it), but never under the keyboard
  ## or screen reader's focus: while the focus is in it, it is only marked stale, and rebuilt when the focus has left
  ## (catchUpFollowers, every second) or by the window itself (a search sets `stale` false)
  ## (with `update`: tried first, even under the focus, since it replaces nothing; it says false when the shape changed)
  result = Follower(area: area, rebuild: rebuild, update: update)
  w.followers.add result

proc refreshFollowers*(w: Win) =
  var keep: seq[Follower]
  for f in w.followers:
    if IsWindow(f.area) == 0: continue          # its window was closed
    keep.add f
    if f.update != nil and f.update():
      f.stale = false
    elif focusInside(f.area): f.stale = true
    else:
      f.stale = false
      f.rebuild()
  w.followers = keep

proc catchUpFollowers*(w: Win) =
  for f in w.followers:
    if f.stale and IsWindow(f.area) != 0 and not focusInside(f.area):
      f.stale = false
      f.rebuild()

proc isEdit(h: HWND): bool =
  var buf = newWideCString("", 32)
  let n = GetClassNameW(h, buf, 32)
  n > 0 and ($buf).toLowerAscii == "edit"

proc panelHeld*(w: Win, anyFocus = true): bool =
  ## the panel is not rebuilt now: something typed into one of its fields is still there (an edit form, a reading
  ## being corrected: a rebuild makes the fields again from the data and what was typed is lost, wherever the
  ## keyboard is by then, in another window too), or the keyboard is in it (`anyFocus`; else only in a text field)
  if w.panel.edited: return true
  let f = GetFocus()
  if f == nil or GetParent(f) != w.panel.hwnd: return false
  anyFocus or isEdit(f)

proc panelChanged*(w: Win, anyFocus = true) =
  ## what the panel shows changed underneath (a sync, the photo queue): rebuilt now, or, while it is held, once it no
  ## longer is (panelCatchUp, every second; the form's own Save and Cancel rebuild it too)
  if not w.picking and w.selected.len == 0:
    w.panelStale = false
    return
  if w.panelHeld(anyFocus): w.panelStale = true
  else: w.rebuildPanel()

proc panelCatchUp*(w: Win) =
  if w.panelStale and not w.panelHeld(): w.panelChanged()

proc keepTyped*(w: Win, p: Page, rebuild: proc (), drop: openArray[HWND] = []) =
  ## `rebuild` makes page `p` again for what it shows now (one of its own buttons, a mode turned on or off, a sync
  ## while the keyboard is elsewhere): what was typed into its fields goes back into the new ones, except into those in
  ## `drop` (what the button sent, the form it closes) (#168). Text that finds no field again (its part of the page went,
  ## or the value its field shows changed underneath) is shown to the person, so it is never lost unseen
  let kept = p.keptText(drop)
  rebuild()
  let lost = p.restoreText(kept)
  if lost.len > 0:
    var lines: seq[string]
    for k in lost: lines.add k.name & ": " & k.text.replace("\r\n", "\n")
    say(w.hwnd, "Typed text not kept", "This changed underneath while you were typing, so what you typed was not put " &
        "back (copy it from here if you need it):\n\n" & lines.join("\n"))

proc rebuildPanelKeeping*(w: Win, drop: openArray[HWND] = []) =
  ## the panel made again by one of its own buttons, keeping what was typed into its other parts (keepTyped)
  w.keepTyped(w.panel, w.rebuildPanel, drop)

proc rebuildSideKeeping*(w: Win) =
  ## the sidebar made again on the same tab, keeping what was typed into its search field (keepTyped)
  w.keepTyped(w.side, w.rebuildSide)

proc sideHeld*(w: Win): bool =
  ## the sidebar is not rebuilt now: the keyboard is in it (on the Drawings tab anywhere, in its lists too; on the
  ## others in a text field). A rebuild makes every control again: the focus would be lost, and the letters typed
  ## while the field is made again (#168: the Procedures search emptied while typing)
  let f = GetFocus()
  f != nil and GetParent(f) == w.side.hwnd and (w.tab == "drawings" or isEdit(f))

proc sideChanged*(w: Win) =
  ## what the sidebar shows changed underneath (a sync, an approval). Under the keyboard only what can change in place
  ## does (sideUpdate: the search's results, the sheets' counts, the procedures' links); the rest waits until the
  ## keyboard has left (sideCatchUp, every second). Otherwise it is made again, keeping what was typed into its search
  if w.sideHeld():
    if w.sideUpdate == nil or not w.sideUpdate(): w.sideStale = true
  else: w.rebuildSideKeeping()

proc sideCatchUp*(w: Win) =
  if w.sideStale and not w.sideHeld(): w.rebuildSideKeeping()

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
  m.descriptions = loadDescriptions(w.fileOr("descriptions.json", ""), proc (msg: string) = stderr.writeLine msg)
  m.kksTables = parseStrict(w.fileOr("kks.json", BuiltInTables), 4096)
  try: m.state = w.a.call("GET", "/api/state")
  except ApiError: m.state = newObj()
  m.merge()
  w.m = m

proc isAdmin*(w: Win): bool =
  let (ok, me) = w.a.me
  ok and me.isAdmin

proc trySubmit*(w: Win, kind: string, payload: JNode, what: string, note = "", clientId = ""): (string, string) =
  ## Propose a change (members) or make it (admins) and say how it went. -> (status, error): status "approved",
  ## "pending" or "conflict", or "" with the reason. `clientId`: the core returns the first submission for a repeat
  var body = newObj(@[("kind", newStr(kind)), ("payload", payload)])
  if note.strip.len > 0: body["note"] = newStr(note.strip)
  if clientId.len > 0: body["client_id"] = newStr(clientId)
  try:
    let r = w.a.call("POST", "/api/submit", body)
    result[0] = if r.get("status") != nil and r["status"].isStr: r["status"].s else: "pending"
    case result[0]
    of "approved": w.toast("Saved: " & what)
    of "conflict": w.toast("Held: it clashes with a pending change (see Approvals)")
    else: w.toast("Sent for approval: " & what)
  except CatchableError as e:
    w.toast(e.msg)
    result = ("", if e.msg.len > 0: e.msg else: $e.name)

proc submit*(w: Win, kind: string, payload: JNode, what: string, note = ""): string =
  ## Propose a change (members) or make it (admins). -> "approved", "pending", "conflict" or "" on error.
  w.trySubmit(kind, payload, what, note)[0]

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
