## Several tags at once, the "Select tags" mode (the GNOME app's multi.nim, for Win32): pick tags on the drawing (a
## click toggles one, a dragged box adds every tag it touches; from the keyboard or a screen reader, a tag button of the
## drawing or a search result toggles its tag), then one photo, place or note for all their codes, sent as one
## /api/submit-many (core api.submitMany: an ordinary submission per code; a photo's image is kept once).
## While the mode is on, the right-hand panel shows the selection and the "… for all" actions.

import std/[strutils, sets, os, random, times]
import kks/[json, api]
import kks/model
import appstate
import w32, ui, viewer, win, photos

const PlaceFields = [("area", "Building / area", "a building / area"), ("floor", "Floor", "a floor"),
                     ("elev", "Elevation", "an elevation"), ("near", "Near / landmark", "a landmark"),
                     ("loc", "How to find it", "directions")]

## codes in one selection: the server takes up to 200 per submit-many (core api.submitMany). Tests: KKS_MAX_PICK lowers it.
let MaxPick = (try: max(1, min(200, parseInt(getEnv("KKS_MAX_PICK", "200")))) except ValueError: 200)

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc countText*(n: int): string = $n & " selected"

proc syncChosen*(w: Win) =
  ## the drawing's outline follows the selected codes (every tag that shows one of them)
  if w.v == nil: return
  w.v.chosen.clear()
  if w.picking and w.picked.len > 0:
    let codes = toHashSet(w.picked)
    for t in w.v.tags:
      if t.status != "pending" and t.code in codes: w.v.chosen.incl t.id
  w.v.invalidate()

proc updatePick(w: Win) =
  w.syncChosen()
  w.rebuildPanel()          # the panel shows the count and the actions while the mode is on

proc unreadOnce(w: Win) =
  if not w.pickSaidUnread:
    w.pickSaidUnread = true
    w.toast("Tags without a code can't be selected: review them first")

proc togglePick*(w: Win, id: string) =
  let (ok, t) = w.m.tagById(id)
  if not ok: return
  let k = t.full
  if k.len == 0:
    w.unreadOnce()
    return
  let i = w.picked.find(k)
  if i < 0 and w.picked.len >= MaxPick:
    w.toast("At most " & $MaxPick & " tags at once: send these first")
    return
  if i >= 0: w.picked.delete(i) else: w.picked.add k
  w.toast(k & (if i >= 0: " removed, " else: " selected, ") & countText(w.picked.len))
  w.updatePick()

proc addBox*(w: Win, x0, y0, x1, y1: float) =
  ## a dragged box (points): adds every tag it touches (never removes)
  var added = 0
  var unread, full = false
  for id in w.v.tagsIn(x0, y0, x1, y1):
    let (ok, t) = w.m.tagById(id)
    if not ok: continue
    if t.full.len == 0:
      unread = true
    elif t.full notin w.picked:
      if w.picked.len >= MaxPick:
        full = true
        break
      w.picked.add t.full
      inc added
  if full: w.toast("At most " & $MaxPick & " tags at once: send these first")
  elif unread and not w.pickSaidUnread: w.unreadOnce()
  else: w.toast((if added == 1: "1 code added, " else: $added & " codes added, ") & countText(w.picked.len))
  w.updatePick()

proc stopPicking*(w: Win) =
  if not w.picking: return
  w.picking = false
  w.picked.setLen(0)
  w.v.selecting = false
  w.syncChosen()
  w.relayout()
  w.rebuildPanel()
  w.rebuildSide()           # the toggle, and what a search result does

proc startPicking*(w: Win) =
  if w.picking: return
  w.v.marking = false
  w.picking = true
  w.pickSaidUnread = false
  w.picked.setLen(0)
  w.v.selecting = true
  w.toast("Select tags: click tags, or drag a box around several; from the keyboard, search and pick a result")
  w.syncChosen()
  w.relayout()
  w.rebuildPanel()
  w.rebuildSide()

proc listWindow(w: Win) =
  ## the selected codes, each with a check box: turn a mistake off (on again puts it back)
  let codes = w.picked
  var hw: HWND
  let (h, p) = popup(w.hwnd, "Selected codes", 440, 480, escape = true)
  hw = h
  if codes.len == 0: p.dim("Nothing selected. Click tags on the drawing.")
  else: p.dim("Turn a code off to leave it out")
  for i in 0 ..< codes.len:
    closureScope:
      let k = codes[i]
      var where = ""
      for t in w.m.tags:
        if t.full == k:
          let (okS, si) = w.m.sheetById(t.sheet)
          where = w.m.kindName(t) & " · " & (if okS: si.name else: t.sheet)
          break
      p.check(k & (if where.len > 0: "  (" & where & ")" else: ""), true, proc (on: bool) =
        if not w.picking: return
        let j = w.picked.find(k)
        if on and j < 0:
          if w.picked.len >= MaxPick:
            w.toast("At most " & $MaxPick & " tags at once: send these first")
            return
          w.picked.add k
        elif not on and j >= 0: w.picked.delete(j)
        w.updatePick())
  p.buttons(("Close the list", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)

proc clientPrefix(): string =
  ## submit-many's client_id prefix: code i goes as "<prefix>-<i>", so a retry duplicates nothing
  randomize()
  result = "wm" & $(getTime().toUnix) & "x"
  for _ in 0 ..< 10: result.add "0123456789abcdef"[rand(15)]

proc sendMany(w: Win, kind: string, payload: JNode, note: string): bool =
  ## one submit-many for the selected codes; says how it went and leaves the mode
  let codes = w.picked
  if codes.len == 0:
    w.toast("Nothing selected")
    return false
  var arr = newArr()
  for k in codes: arr.elems.add newStr(k)
  if kind == "equipment":
    # the values this device shows for the fields it changes: a value someone changed meanwhile is then a clash
    # (core submitMany `bases`), not overwritten silently
    var bases = newObj()
    for k in codes:
      let e = w.m.equipment(k)
      var b = newObj()
      if payload.get("changes") != nil:          # replaced fields only: an appended note can't lose anything
        for (f, _) in payload["changes"].fields:
          b[f] = (if e.get(f) != nil: e[f] else: newStr(""))
      bases[k] = b
    payload["bases"] = bases
  var body = newObj(@[("kind", newStr(kind)), ("kks", arr), ("payload", payload), ("client_id", newStr(clientPrefix()))])
  if note.strip.len > 0: body["note"] = newStr(note.strip)
  var r: JNode
  try: r = w.a.call("POST", "/api/submit-many", body)
  except ApiError as e:
    w.toast(e.msg)
    return false
  var pending, held = 0
  if r.get("results") != nil:
    for x in r["results"].elems:
      case s(x, "status")
      of "approved": discard
      of "conflict": inc held
      else: inc pending
  let n = codes.len
  var msg = "Sent for " & (if n == 1: "1 code" else: $n & " codes")
  if pending > 0: msg.add " · " & $pending & " await approval"
  if held > 0: msg.add " · " & $held & " held (they clash with pending changes)"
  if pending == 0 and held == 0: msg.add " · saved"
  w.loadModel()
  if w.sheet.len > 0: w.v.tags = w.tagBoxes(w.sheet)
  w.stopPicking()
  w.toast(msg)
  true

proc photoForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  w.takePhoto(proc (dataUrl, caption, note: string) =
    discard w.sendMany("photo", newObj(@[("dataUrl", newStr(dataUrl)), ("caption", newStr(caption))]), note))

proc placeForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  var hw: HWND
  let (h, p) = popup(w.hwnd, "Place for all", 460, 520, escape = true)
  hw = h
  p.title(countText(w.picked.len))
  p.dim("Only the fields you fill are sent; the others stay as they are for each code.")
  var entries: seq[(string, string, HWND)]
  for (f, title, noun) in PlaceFields:
    entries.add((f, noun, p.field(title & (if f == "floor": " (0–10)" else: ""), "")))
  let note = if not w.isAdmin: p.field("Note for the approver (optional)", "") else: nil
  p.buttons(("Send", proc () =
    var changes = newObj()
    var lines: seq[string]
    let codes = w.picked
    for (f, noun, e) in entries:
      let v = e.text.strip
      if v.len == 0: continue
      if f == "floor" and not (v == "10" or (v.len == 1 and v[0] in Digits)):
        w.toast("Floor: a whole number from 0 to 10 (the height goes in Elevation)")
        return
      changes[f] = newStr(v)
      var have = 0
      for k in codes:
        let cur = s(w.m.equipment(k), f).strip
        if cur.len > 0 and cur != v: inc have
      if have > 0:
        lines.add $have & " of " & $codes.len & " already have " & noun & "; it will be replaced."
    if changes.len == 0:
      w.toast("Fill at least one field")
      return
    if lines.len > 0 and not ask(hw, "Replace values?", lines.join("\n")): return
    if w.sendMany("equipment", newObj(@[("changes", changes)]), if note != nil: note.text else: ""): DestroyWindow(hw)),
    ("Cancel", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)

proc noteForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  var hw: HWND
  let (h, p) = popup(w.hwnd, "Note for all", 460, 360, escape = true)
  hw = h
  p.title(countText(w.picked.len))
  p.dim("Added under each code's own notes; nothing already there is removed.")
  let e = p.field("Note", "")
  let note = if not w.isAdmin: p.field("Note for the approver (optional)", "") else: nil
  p.buttons(("Send", proc () =
    let v = e.text.strip
    if v.len == 0:
      w.toast("Write the note first")
      return
    if w.sendMany("equipment", newObj(@[("append", newObj(@[("notes", newStr(v))]))]), if note != nil: note.text else: ""):
      DestroyWindow(hw)),
    ("Cancel", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)

proc pickPanel*(w: Win, p: Page) =
  ## the right-hand panel while the mode is on: the count and the actions
  p.clear()
  p.title("Select tags")
  p.label(countText(w.picked.len))
  p.dim("Click tags or drag a box · or search and pick results. Escape on the drawing ends the mode.")
  p.buttons(("List", proc () = w.listWindow()))
  p.buttons(("Photo for all…", proc () = w.photoForAll()))
  p.buttons(("Place for all…", proc () = w.placeForAll()))
  p.buttons(("Note for all…", proc () = w.noteForAll()))
  p.buttons(("Done", proc () = w.stopPicking()))
  if w.picked.len > 0:
    p.title("Selected codes")
    for k in w.picked: p.label(k)
  p.layout()
