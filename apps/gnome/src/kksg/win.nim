## The window's shared state and the actions every screen uses (decision 0031).

import std/[strutils, tables, sets, base64]
import kks/[json, api]
import kks/model
import gtk, ui, appstate, viewer

type Follower* = ref object
  area*: W                     ## the part a rebuild replaces (a ref is held)
  rebuild*: proc ()
  update*: proc (): bool       ## optional: new values into the same widgets; false = the structure changed
  stale*: bool

type Win* = ref object
  a*: App
  window*, toasts*, root*: W
  m*: Model
  v*: Viewer
  split*, sheetList*, searchEntry*, resultList*, sheetTitle*, panelSplit*, panelBox*, markBtn*, status*: W
  sideNav*, banner*: W
  coverBtn*: W                 ## the drawing's "Colour tags by photos" toggle
  queueBar*, queueLabel*: W    ## the photo queue's status (photos.nim), under the drawing
  picking*: bool               ## "Select tags" mode: one photo, place or note for several codes (multi.nim)
  picked*: seq[string]         ## the selected codes, in the order they were picked
  pickBar*, pickCount*, pickBtn*: W
  pickSaidUnread*: bool        ## the "no code" toast was shown in this round of the mode
  pickChanged*: proc ()        ## the selection changed (the bar's count, the drawing)
  linkProc*: string            ## link mode (R7): clicks on tags link them to this procedure step
  linkStep*: int
  activeProc*: string
  floor*: string               ## floor filter ("" = all)
  bannerAction*: proc ()
  sheet*: string
  selected*: string
  panelEditing*: bool          ## the panel has an open form (Edit, a valve type's Correct): a sync doesn't rebuild it
  reloadQueued*: bool
  showSheet*: proc (id: string)
  selectTag*: proc (id: string, center: bool)
  rebuildPanel*: proc ()
  closePanel*: proc ()
  openProc*: proc (id: string)
  followers*: seq[Follower]    ## open sidebar pages that follow the plant's data (follow)
  livePage*: W                 ## the open Manage page that rebuilds when the data changes (a ref is held)
  liveBuild*: proc (box: W)

proc toast*(w: Win, msg: string) = toast(w.toasts, msg)

proc fileOr*(w: Win, path: string, dflt: string): string =
  let (ok, data) = w.a.file(path)
  if ok: data else: dflt

proc loadModel*(w: Win) =
  let m = Model()
  m.sheets = parseSheets(parseStrict(w.fileOr("sheets.json", "[]"), 4096))
  m.baseTags = parseTags(parseStrict(w.fileOr("tags.json", "[]"), 4096))
  m.procs = parseStrict(w.fileOr("procedures.json", "[]"), 4096)
  m.locations = buildLocations(parseStrict(w.fileOr("locations.json", "{}"), 4096))
  m.descriptions = loadDescriptions(w.fileOr("descriptions.json", ""), proc (msg: string) = stderr.writeLine msg)
  m.kksTables = parseStrict(w.fileOr("kks.json", "{}"), 4096)
  try: m.state = w.a.call("GET", "/api/state")
  except ApiError: m.state = newObj()
  m.merge()
  w.m = m

proc isAdmin*(w: Win): bool =
  let (ok, me) = w.a.me
  ok and me.isAdmin

proc trySubmit*(w: Win, kind: string, payload: JNode, what: string, note = "", clientId = ""): string =
  ## as submit, but an error is raised (ApiError), not shown. `clientId`: the core keeps a change sent twice with the
  ## same one once (the photo queue resends after a crash).
  var body = newObj(@[("kind", newStr(kind)), ("payload", payload)])
  if note.strip.len > 0: body["note"] = newStr(note.strip)
  if clientId.len > 0: body["client_id"] = newStr(clientId)
  let r = w.a.call("POST", "/api/submit", body)
  result = if r.get("status") != nil and r["status"].isStr: r["status"].s else: "pending"
  case result
  of "approved": w.toast("Saved: " & what)
  of "conflict": w.toast("Held: it clashes with a pending change (see Approvals)")
  else: w.toast("Sent for approval: " & what)

proc submit*(w: Win, kind: string, payload: JNode, what: string, note = ""): string =
  ## Propose a change (members) or make it (admins). Returns "approved", "pending", "conflict" or "" on error,
  ## and says what happened.
  try: w.trySubmit(kind, payload, what, note)
  except ApiError as e:
    w.toast(e.msg)
    ""

proc myOpen*(w: Win): seq[JNode] =
  ## my own open proposals (pending or held)
  try:
    let r = w.a.call("GET", "/api/submissions", nil, {"status": "open"}.toTable)
    let (_, me) = w.a.me
    for s in r["submissions"].elems:
      if s.get("person") != nil and s["person"].isStr and s["person"].s == me.person: result.add s
  except ApiError: discard

proc tagBoxes*(w: Win, sheet: string): seq[TagBox] =
  let (ok, si) = w.m.sheetById(sheet)
  let s = if ok and si.scale > 0: si.scale else: 2.0
  for t in w.m.tagsOf(sheet):
    result.add TagBox(id: t.id, x0: t.bbox[0] / s, y0: t.bbox[1] / s, x1: t.bbox[2] / s, y1: t.bbox[3] / s,
                      status: (if t.status == "confirmed": "verified" else: t.status), label: t.full,
                      photos: w.m.photoCover(t.full))
  # my pending marks (R6), dashed
  for sub in w.myOpen():
    if sub["kind"].s == "tag_add" and sub.get("payload") != nil:
      let p = sub["payload"]
      if p.get("sheet") != nil and p["sheet"].s == sheet and p.get("bbox") != nil:
        let b = p["bbox"]
        result.add TagBox(id: "pending:" & $sub["id"].i, x0: b[0].num / s, y0: b[1].num / s, x1: b[2].num / s,
                          y1: b[3].num / s, status: "pending", label: "proposed tag")

proc setBanner*(w: Win, text, button: string, action: proc ()) =
  if text.len == 0:
    adw_banner_set_revealed(w.banner, 0)
    w.bannerAction = nil
    return
  adw_banner_set_title(w.banner, text.cstring)
  adw_banner_set_button_label(w.banner, button.cstring)
  w.bannerAction = action
  adw_banner_set_revealed(w.banner, 1)

proc linkedTags*(w: Win): HashSet[string] =
  ## tags whose code is linked to the open procedure
  if w.activeProc.len == 0 or w.m.state == nil or w.m.state.get("links") == nil: return
  var codes: HashSet[string]
  for l in w.m.state["links"].elems:
    if l["proc"].s == w.activeProc: codes.incl l["kks"].s
  for t in w.m.tags:
    if t.full in codes: result.incl t.id

proc applyHighlights*(w: Win) =
  w.v.linked = w.linkedTags()
  w.v.floorOn = w.floor.len > 0
  w.v.floorIds.clear()
  if w.floor.len > 0:
    for t in w.m.tags:
      let e = w.m.equipment(t.full)
      if e.get("floor") != nil and e["floor"].isStr and e["floor"].s.strip.toLowerAscii == w.floor.toLowerAscii:
        w.v.floorIds.incl t.id
  gtk_widget_queue_draw(w.v.widget)

proc setLive*(w: Win, box: W, build: proc (box: W)) =
  ## this page shows data that syncs can change (Approvals, Devices…): rebuild it on changes while it is shown
  if w.livePage != nil: g_object_unref(w.livePage)
  w.livePage = if box != nil: g_object_ref(box) else: nil
  w.liveBuild = build

proc refreshLive*(w: Win) =
  if w.livePage == nil: return
  if gtk_widget_get_root(w.livePage) == nil:      # its page was closed
    w.setLive(nil, nil)
  elif gtk_widget_get_mapped(w.livePage) != 0:
    w.livePage.clear()
    w.liveBuild(w.livePage)

proc focusInside(area: W): bool =
  let root = gtk_widget_get_root(area)
  if root == nil: return false
  let f = gtk_root_get_focus(root)
  f != nil and (f == area or gtk_widget_is_ancestor(f, area) != 0)

proc follow*(w: Win, area: W, rebuild: proc (), update: proc (): bool = nil): Follower =
  ## `area` shows data that syncs and approvals change (refreshFollowers rebuilds it), but never under the keyboard
  ## or screen reader's focus: while the focus is inside it, it is only marked stale and rebuilt when the focus
  ## leaves (or by the page itself, e.g. on a search: it sets `stale` false). A page hidden under another one is
  ## rebuilt when it shows again. `update`, if given, is tried first: it puts new values into the same widgets (safe
  ## under the focus) and says false when only a rebuild will do.
  let f = Follower(area: g_object_ref(area), rebuild: rebuild, update: update)
  w.followers.add f
  proc catchUp() =
    if f.stale and gtk_widget_get_mapped(f.area) != 0:
      if f.update != nil and f.update():      # in place: safe even under the focus
        f.stale = false
      elif not focusInside(f.area):
        f.stale = false
        f.rebuild()
  let fc = gtk_event_controller_focus_new()
  fc.on("leave", proc () = idle(catchUp))       # after the focus has moved on
  gtk_widget_add_controller(area, fc)
  area.on("map", catchUp)
  f

proc refreshFollowers*(w: Win) =
  var keep: seq[Follower]
  for f in w.followers:
    if gtk_widget_get_root(f.area) == nil:      # its page was closed
      g_object_unref(f.area)
      continue
    keep.add f
    if gtk_widget_get_mapped(f.area) == 0: f.stale = true     # hidden: no work now, brought up to date when shown
    elif f.update != nil and f.update():        # changed in place: nothing under the focus is replaced
      f.stale = false
    elif focusInside(f.area): f.stale = true
    else:
      f.stale = false
      f.rebuild()
  w.followers = keep
