## Several tags at once, the "Select tags" mode: pick tags on the drawing (a click toggles one, a dragged box adds every
## tag it touches), a search result in the sidebar (it toggles its tag's code, whichever drawing it is on: the open
## drawing stays), or codes typed into the List dialog; then one photo, place or note for all their codes, sent as one
## /api/submit-many (core api.submitMany: an ordinary submission per code). The selection is by code and survives a
## change of drawing, so codes that are in one place but on different P&IDs go together.

import std/[strutils, sets, os, random, times]
import kks/[json, api]
import kks/model
import gtk, ui, appstate, viewer, win, photos

const PlaceFields = [("area", "Building / area", "a building / area"), ("floor", "Floor", "a floor"),
                     ("elev", "Elevation", "an elevation"), ("near", "Near / landmark", "a landmark"),
                     ("loc", "How to find it", "directions")]

var testBoxDone = false

## codes in one selection: the server takes up to 200 per submit-many (core api.submitMany). Tests: KKS_MAX_PICK lowers it.
let MaxPick = (try: max(1, min(200, parseInt(getEnv("KKS_MAX_PICK", "200")))) except ValueError: 200)

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc announce(w: Win, msg: string) =
  ## said by a screen reader without moving the focus (GTK_ACCESSIBLE_ANNOUNCEMENT_PRIORITY_MEDIUM)
  if w.pickCount != nil: gtk_accessible_announce(w.pickCount, msg.cstring, 1)

proc countText(n: int): string = $n & " selected"

proc syncChosen*(w: Win) =
  ## the drawing's outline follows the selected codes (every tag that shows one of them)
  if w.v == nil: return
  w.v.chosen.clear()
  if w.picking and w.picked.len > 0:
    let codes = toHashSet(w.picked)
    for t in w.v.tags:
      if t.status != "pending" and t.label in codes: w.v.chosen.incl t.id
  gtk_widget_queue_draw(w.v.widget)

proc updatePick(w: Win) =
  if w.pickCount != nil: gtk_label_set_text(w.pickCount, countText(w.picked.len).cstring)
  w.syncChosen()
  if w.pickChanged != nil: w.pickChanged()

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
  w.updatePick()
  w.announce(k & (if i >= 0: " removed, " else: " selected, ") & countText(w.picked.len))

proc sheetsOf(w: Win, k: string): seq[string] =
  ## the drawings a code is on (their names)
  for t in w.m.tags:
    if t.full == k:
      let (okS, si) = w.m.sheetById(t.sheet)
      let n = if okS: si.name else: t.sheet
      if n notin result: result.add n

proc pickResult*(w: Win, id: string) =
  ## a search result activated in the mode: its code joins (or leaves) the selection. The open drawing stays: a code
  ## of another drawing is selected from here, and said (nothing on this drawing shows it)
  let (ok, t) = w.m.tagById(id)
  if not ok: return
  if t.sheet == w.sheet:
    let (okS, si) = w.m.sheetById(t.sheet)
    let sc = if okS and si.scale > 0: si.scale else: 2.0
    w.v.centerOn(t.bbox[0] / sc, t.bbox[1] / sc, t.bbox[2] / sc, t.bbox[3] / sc)
  let before = w.picked.len
  w.togglePick(id)
  if t.sheet != w.sheet and w.picked.len != before:
    w.toast(t.full & (if w.picked.len > before: " selected" else: " removed") & " (on " & w.sheetsOf(t.full).join(", ") &
            ") · " & countText(w.picked.len))

proc addCodes*(w: Win, text: string): tuple[added, unknown, over: seq[string]] =
  ## codes typed or pasted (spaces, commas, semicolons or new lines between them): each one that is on a drawing joins
  ## the selection, up to the cap. `unknown`: on no drawing; `over`: left out by the cap
  var known = initHashSet[string]()
  for t in w.m.tags:
    if t.full.len > 0: known.incl t.full
  var seen = initHashSet[string]()
  for raw in text.toUpperAscii.split({' ', ',', ';', '\n', '\r', '\t'}):
    let k = raw.strip
    if k.len == 0 or k in seen: continue
    seen.incl k
    if k notin known: result.unknown.add k
    elif k in w.picked: continue
    elif w.picked.len >= MaxPick: result.over.add k
    else:
      w.picked.add k
      result.added.add k
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
  if unread: w.unreadOnce()
  if full: w.toast("At most " & $MaxPick & " tags at once: send these first")
  w.updatePick()
  w.announce((if added == 1: "1 code added, " else: $added & " codes added, ") & countText(w.picked.len))

proc stopPicking*(w: Win) =
  w.picking = false
  w.picked.setLen(0)
  w.v.selecting = false
  w.v.mark = (0.0, 0.0, 0.0, 0.0)
  if w.pickBar != nil: gtk_action_bar_set_revealed(w.pickBar, 0)
  if w.pickBtn != nil and gtk_toggle_button_get_active(w.pickBtn) != 0: gtk_toggle_button_set_active(w.pickBtn, 0)
  gtk_widget_set_cursor_from_name(w.v.widget, "grab")
  w.updatePick()

proc startPicking*(w: Win) =
  if w.picking: return
  w.v.marking = false
  w.setBanner("", "", nil)
  w.picking = true
  w.pickSaidUnread = false
  w.picked.setLen(0)
  w.v.selecting = true
  if w.pickBar != nil: gtk_action_bar_set_revealed(w.pickBar, 1)
  if w.pickBtn != nil and gtk_toggle_button_get_active(w.pickBtn) == 0: gtk_toggle_button_set_active(w.pickBtn, 1)
  gtk_widget_set_cursor_from_name(w.v.widget, "crosshair")
  w.updatePick()
  w.announce("Select tags: click tags, or drag a box around several; from the keyboard, search and pick a result")
  # tests: KKS_SELECT_BOX = "x0,y0,x1,y1" in the sheet's tag units stands in for a box dragged with the pointer (the
  # headless test session has no pointer to drag with); the first time the mode starts only
  let box = getEnv("KKS_SELECT_BOX")
  if box.len > 0 and not testBoxDone:
    testBoxDone = true
    timeout(500, proc (): bool =
      let p = box.split(',')
      let (ok, si) = w.m.sheetById(w.sheet)
      let sc = if ok and si.scale > 0: si.scale else: 2.0
      if p.len == 4 and w.picking:
        w.addBox(parseFloat(p[0]) / sc, parseFloat(p[1]) / sc, parseFloat(p[2]) / sc, parseFloat(p[3]) / sc)
      false)

proc listDialog*(w: Win) =
  ## the selected codes, each with a switch (turn a mistake off; on again puts it back) and the drawings it is on;
  ## below, codes typed or pasted join the selection
  let d = adw_dialog_new()
  adw_dialog_set_title(d, "Selected codes")
  adw_dialog_set_content_width(d, 420)
  let listBox = vbox(8)
  proc fill() =
    listBox.clear()
    let g = group("", "Turn a code off to leave it out")
    let codes = w.picked
    if codes.len == 0: adw_preferences_group_add(g, row("Nothing selected", "Click tags on the drawing, pick search results, or add codes below"))
    for i in 0 ..< codes.len:
      closureScope:
        let k = codes[i]
        var where = ""
        for t in w.m.tags:
          if t.full == k:
            where = w.m.kindName(t) & " · " & w.sheetsOf(k).join(", ")
            break
        let r = row(k, where)
        # a switch, not a check button: GTK 4 gives a check button no accessibility action (AT-SPI can't toggle it);
        # a switch has one ("Toggles the switch"), and Orca reads its state
        let cb = gtk_switch_new()
        gtk_switch_set_active(cb, 1)
        gtk_widget_set_valign(cb, GTK_ALIGN_CENTER)
        adw_action_row_add_suffix(r, cb)
        adw_action_row_set_activatable_widget(r, cb)
        cb.onPtr("notify::active", proc (p: W) =
          let on = gtk_switch_get_active(cb) != 0
          let j = w.picked.find(k)
          if on and j < 0:
            if w.picked.len >= MaxPick:
              w.toast("At most " & $MaxPick & " tags at once: send these first")
              idle(proc () = gtk_switch_set_active(cb, 0))
              return
            w.picked.add k
          elif not on and j >= 0: w.picked.delete(j)
          w.updatePick())
        adw_preferences_group_add(g, r)
    listBox.add g
  fill()
  let addG = group("Add codes", "From any drawing: type or paste KKS codes, separated by spaces or commas")
  let e = entryRow("KKS codes", "")
  adw_preferences_group_add(addG, e)
  let said = label("", "dim-label")
  gtk_widget_set_visible(said, 0)
  proc addNow() =
    let typed = text(e)
    if typed.strip.len == 0:
      w.toast("Type the codes first")
      return
    let r = w.addCodes(typed)
    proc some(xs: seq[string]): string =
      xs[0 ..< min(20, xs.len)].join(", ") & (if xs.len > 20: " and " & $(xs.len - 20) & " more" else: "")
    var lines: seq[string]
    if r.added.len > 0: lines.add "Added " & (if r.added.len == 1: "1 code" else: $r.added.len & " codes") & "."
    if r.unknown.len > 0: lines.add "Not on any drawing, not added: " & some(r.unknown) & "."
    if r.over.len > 0: lines.add "At most " & $MaxPick & " at once, not added: " & some(r.over) & "."
    if lines.len == 0: lines.add "Already selected."
    gtk_label_set_text(said, lines.join(" ").cstring)
    gtk_widget_set_visible(said, 1)
    w.announce(lines.join(" "))
    gtk_editable_set_text(e, (r.unknown & r.over).join(" ").cstring)    # what was not added stays, to be corrected
    # not inside the click (an AT-SPI action: rows built there have no accessibility contents)
    idle(proc () = fill())
  let addBtn = button("Add codes", "", addNow)
  gtk_widget_set_halign(addBtn, GTK_ALIGN_END)
  let body = vbox(8)
  margins(body, 12)
  body.add listBox
  body.add addG
  body.add said
  body.add addBtn
  adw_dialog_set_child(d, toolbarView(headerBar(adw_window_title_new("Selected codes", "")), scrolled(body)))
  adw_dialog_set_content_height(d, 520)
  present(d, w.window)

proc clientPrefix(): string =
  ## submit-many's client_id prefix: code i goes as "<prefix>-<i>", so a retry duplicates nothing
  randomize()
  result = "gm" & $(getTime().toUnix) & "x"
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
  w.toast(msg)
  w.stopPicking()
  w.loadModel()
  if w.sheet.len > 0: w.v.tags = w.tagBoxes(w.sheet)
  gtk_widget_queue_draw(w.v.widget)
  w.rebuildPanel()
  true

proc photoForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  # the user's rule, as for one photo: the floor first when a code has none, sent with the photo (core submitMany
  # writes it for the codes without one only; nobody has to wait for an approval before the photo)
  let codes = w.picked
  let missing = w.floorsMissing(codes)
  proc go(floor: string) =
    w.photoForCodes(codes, floor, proc () =
      w.toast("Photo queued for " & $codes.len & " codes: it is sent once compressed")
      w.stopPicking()
      w.rebuildPanel())
  if missing.len == 0: go("")
  else: w.askFloorFor(missing, codes.len, go)

proc approverNote(w: Win, g: W): W =
  result = entryRow("Note for the approver (optional)", "")
  if not w.isAdmin: adw_preferences_group_add(g, result)

proc formDialog(w: Win, title: string, g: W, send: proc (d: W)) =
  let d = adw_dialog_new()
  adw_dialog_set_title(d, title.cstring)
  adw_dialog_set_content_width(d, 460)
  let body = vbox(8)
  margins(body, 12)
  body.add g
  let header = headerBar(adw_window_title_new(title.cstring, countText(w.picked.len).cstring))
  adw_header_bar_pack_end(header, button("Send", "suggested-action", proc () = send(d)))
  adw_dialog_set_child(d, toolbarView(header, body))
  present(d, w.window)

proc placeForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  let g = group("", "Only the fields you fill are sent; the others stay as they are for each code.")
  var entries: seq[(string, string, W)]
  for (f, title, noun) in PlaceFields:
    let e = entryRow(title, "")
    if f == "floor": gtk_widget_set_tooltip_text(e, "A whole number from 0 to 10")
    adw_preferences_group_add(g, e)
    entries.add((f, noun, e))
  let note = w.approverNote(g)
  w.formDialog("Place for all", g, proc (d: W) =
    var changes = newObj()
    var lines: seq[string]
    let codes = w.picked
    for (f, noun, e) in entries:
      let v = text(e).strip
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
    let nt = text(note)
    proc go() =
      if w.sendMany("equipment", newObj(@[("changes", changes)]), nt): adw_dialog_close(d)
    if lines.len > 0: confirm(w.window, "Replace values?", lines.join("\n"), "Send", false, go)
    else: go())

proc noteForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  let g = group("", "Added under each code's own notes; nothing already there is removed.")
  let e = entryRow("Note", "")
  adw_preferences_group_add(g, e)
  let note = w.approverNote(g)
  w.formDialog("Note for all", g, proc (d: W) =
    let v = text(e).strip
    if v.len == 0:
      w.toast("Write the note first")
      return
    if w.sendMany("equipment", newObj(@[("append", newObj(@[("notes", newStr(v))]))]), text(note)):
      adw_dialog_close(d))

proc pickBar*(w: Win): W =
  ## the bar under the drawing while the mode is on
  let bar = gtk_action_bar_new()
  setAccessibleLabel(bar, "Selected tags")
  w.pickCount = label(countText(0), "heading", wrap = false)
  gtk_action_bar_pack_start(bar, w.pickCount)
  gtk_action_bar_pack_start(bar, button("List", "flat", proc () = w.listDialog()))
  let hint = label("Click tags or drag a box · or search and pick results (any drawing)", "dim-label", wrap = false)
  gtk_label_set_ellipsize(hint, 3)
  gtk_action_bar_pack_start(bar, hint)
  gtk_action_bar_pack_end(bar, button("Done", "", proc () = w.stopPicking()))
  gtk_action_bar_pack_end(bar, button("Note for all…", "", proc () = w.noteForAll()))
  gtk_action_bar_pack_end(bar, button("Place for all…", "", proc () = w.placeForAll()))
  gtk_action_bar_pack_end(bar, button("Photo for all…", "", proc () = w.photoForAll()))
  gtk_action_bar_set_revealed(bar, 0)
  w.pickBar = bar
  bar
