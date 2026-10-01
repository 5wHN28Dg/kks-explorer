## The equipment panel (R3, R4, R5, R6; index.html select()): what the drawing says, the location list, the person's
## own data (read-only until Edit), where else the code appears, procedures, photos, and the review of uncertain
## readings.

import std/[strutils, math, sets, tables, unicode, sequtils]
import kks/json
import kks/model
import gtk, ui, appstate, win, photos

proc section(title: string, rows: seq[W], description = ""): W =
  result = group(title, description)
  for r in rows: adw_preferences_group_add(result, r)

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc normKks(s: string): string =
  for c in s.toUpperAscii:
    if c notin Whitespace: result.add c

proc reviewSection(w: Win, t: Tag): W =
  let sug = t.suggestion
  let sugNote = s(sug, "note")
  result = group("Check this tag", "The reader saw " & t.read[0] & " / " & t.read[1] & ", confidence " &
                 $int(round(t.conf * 100)) & " %." & (if t.note.len > 0: " " & t.note else: "") &
                 (if sugNote.len > 0: " " & sugNote else: ""))
  let sugK = s(sug, "kks")
  let sugI = s(sug, "isa")
  let k = entryRow("KKS (with suffix)", if sugK.len > 0: sugK else: t.full)
  let isa = entryRow("Function letters (instruments)", if sugI.len > 0: sugI else: t.isa)
  adw_preferences_group_add(result, k)
  adw_preferences_group_add(result, isa)
  let btns = hbox(8)
  gtk_widget_set_margin_top(btns, 8)
  let id = t.id
  let base = if w.m.state != nil and w.m.state.get("reviews") != nil and w.m.state["reviews"].get(id) != nil:
               w.m.state["reviews"][id] else: newNull()
  btns.add button("Confirm", "suggested-action", proc () =
    let code = normKks(text(k))
    if not (code.len >= 12 and code[0 .. 1].allCharsInSet(Digits) and code[2 .. 4].allCharsInSet(UppercaseLetters) and
            code[5 .. 6].allCharsInSet(Digits) and code[7 .. 8].allCharsInSet(UppercaseLetters) and
            code[9 .. 11].allCharsInSet(Digits) and code[12 .. ^1].allCharsInSet(UppercaseLetters + Digits)):
      w.toast("That is not a valid KKS (e.g. 11LAB70AA501)")
      return
    let isaV = text(isa).strip.toUpperAscii
    let data = newObj(@[("status", newStr("confirmed")), ("kks", newStr(code[0 ..< 12])), ("suffix", newStr(code[12 .. ^1])),
                        ("isa", if isaV.len > 0: newStr(isaV) else: newNull())])
    discard w.submit("review", newObj(@[("tag_id", newStr(id)), ("data", data), ("base", base)]), code))
  btns.add button("Not a tag", "", proc () =
    discard w.submit("review", newObj(@[("tag_id", newStr(id)), ("data", newObj(@[("status", newStr("rejected"))])),
                                       ("base", base)]), "not a tag"))
  adw_preferences_group_add(result, btns)

const Fields = [("area", "Building / area"), ("floor", "Floor"), ("elev", "Elevation"), ("near", "Near / landmark"),
                ("loc", "How to find it"), ("notes", "Notes")]

proc equipmentSection(w: Win, t: Tag): W =
  ## read-only rows; Edit turns them into entries (no accidental edits), Save sends only what changed, each field
  ## with the live value the person saw (the server merges edits to different fields and flags real clashes)
  let k = t.full
  let live = w.m.equipment(k)
  let rl = w.m.refLoc(t.bodyOf)
  result = group("Location and notes")
  let g = result
  var shown: seq[W]
  for (f, title) in Fields:
    var v = s(live, f)
    if f == "elev" and v.len == 0 and rl.elev.len > 0: v = rl.elev & " (location list)"
    let r = row(title, if v.len > 0: v else: "—", selectable = true)
    adw_preferences_group_add(g, r)
    shown.add r
  var customRows: seq[W]
  if live.get("custom") != nil:
    for c in live["custom"].elems:
      let r = row(s(c, "k"), s(c, "v"), selectable = true)
      adw_preferences_group_add(g, r)
      customRows.add r
  let edit = button("Edit", "flat")
  adw_preferences_group_set_header_suffix(g, edit)
  edit.onClick(proc () =
    gtk_widget_set_visible(edit, 0)
    for r in shown & customRows: gtk_widget_set_visible(r, 0)
    var entries: seq[(string, W)]
    for (f, title) in Fields:
      let e = entryRow(title, s(live, f))
      if f == "floor": gtk_widget_set_tooltip_text(e, "A whole number from 0 to 10")
      adw_preferences_group_add(g, e)
      entries.add((f, e))
    var custom: seq[(W, W)]
    let customBox = vbox(4)
    proc addCustom(key, val: string) =
      let line = hbox(4)
      let ek = gtk_entry_new()
      gtk_entry_set_placeholder_text(ek, "Field")
      gtk_editable_set_text(ek, key.cstring)
      setAccessibleLabel(ek, "Custom field name")
      let ev = gtk_entry_new()
      gtk_entry_set_placeholder_text(ev, "Value")
      gtk_editable_set_text(ev, val.cstring)
      setAccessibleLabel(ev, "Custom field value")
      gtk_widget_set_hexpand(ev, 1)
      line.add ek, ev
      customBox.add line
      custom.add((ek, ev))
    if live.get("custom") != nil:
      for c in live["custom"].elems: addCustom(s(c, "k"), s(c, "v"))
    adw_preferences_group_add(g, customBox)
    adw_preferences_group_add(g, button("+ Custom field", "flat", proc () = addCustom("", "")))
    let note = entryRow("Note for the approver (optional)", "")
    if not w.isAdmin: adw_preferences_group_add(g, note)
    let btns = hbox(8)
    gtk_widget_set_margin_top(btns, 8)
    btns.add button("Save", "suggested-action", proc () =
      var changes, base = newObj()
      for (f, e) in entries:
        let nv = text(e).strip
        if nv != s(live, f):
          if f == "floor" and nv.len > 0 and not (nv == "10" or (nv.len == 1 and nv[0] in Digits)):
            w.toast("Floor: a whole number from 0 to 10 (the height goes in Elevation)")
            return
          changes[f] = newStr(nv)
          base[f] = newStr(s(live, f))
      var cs = newArr()
      for (ek, ev) in custom:
        let kk = text(ek).strip
        let vv = text(ev).strip
        if kk.len > 0 or vv.len > 0: cs.elems.add newObj(@[("k", newStr(kk)), ("v", newStr(vv))])
      let oldC = if live.get("custom") != nil: live["custom"] else: newArr()
      if toText(cs) != toText(oldC):
        changes["custom"] = cs
        base["custom"] = oldC
      if changes.len == 0:
        w.toast("Nothing changed")
        return
      if w.submit("equipment", newObj(@[("kks", newStr(k)), ("changes", changes), ("base", base)]), k, text(note)).len > 0:
        w.rebuildPanel())
    btns.add button("Cancel", "", proc () = w.rebuildPanel())
    adw_preferences_group_add(g, btns))

proc buildPanel*(w: Win, t: Tag) =
  w.panelBox.clear()
  let m = w.m
  let k = t.full
  let head = vbox(2)
  head.add label(if k.len > 0: k else: "Unread tag", "title-2", selectable = true)
  head.add label((if t.isa.len > 0: t.isa & " · " else: "") & m.kindName(t), "dim-label")
  w.panelBox.add head
  # my own open proposals for this tag/code
  var mine: seq[string]
  for sub in w.myOpen():
    let p = sub.get("payload")
    if p == nil: continue
    if (sub["kind"].s in ["equipment", "photo", "link"] and s(p, "kks") == k and k.len > 0) or
       (sub["kind"].s == "review" and s(p, "tag_id") == t.id):
      mine.add sub["kind"].s & (if sub["status"].s == "conflict": " (held: clashes)" else: " (waiting for approval)")
  if mine.len > 0: w.panelBox.add label("Your pending changes: " & mine.join(", "), "dim-label")
  if w.linkProc.len > 0 and k.len > 0:   # link mode (R7), reachable without a pointer
    let lp = w.linkProc
    let ls = w.linkStep
    w.panelBox.add button("Link " & k & " to step " & $ls & " of " & lp, "suggested-action", proc () =
      discard w.submit("link", newObj(@[("proc", newStr(lp)), ("step", newInt(ls)), ("kks", newStr(k)),
                       ("on", newBool(true))]), k & " → step " & $ls)
      w.loadModel()
      w.applyHighlights())
  if t.status == "review": w.panelBox.add w.reviewSection(t)
  let (ok, d) = m.decode(t)
  if ok:
    var rows = @[row("Plant unit", d.blk & "  " & m.blockName(d.blk)),
                 row("System", d.sys & "  " & (if m.systemName(d.sys).len > 0: m.systemName(d.sys) else: "not in the legend")),
                 row("Subsystem no.", d.fn), row("Component", d.comp & "  " & m.componentName(d.comp)), row("Number", d.num)]
    if d.isa.len > 0: rows.add row("Instrument", d.isa)
    rows.add row("Reading", case t.status
      of "confirmed": "confirmed by a person"
      of "verified": "checked by eye against the drawing"
      else: "automatic, " & $int(round(t.conf * 100)) & " % confidence")
    if t.flag.len > 0: rows.add row("Flag", t.flag)
    w.panelBox.add section("From the drawing", rows)
  let rl = m.refLoc(t.bodyOf)
  if rl.rows.len > 0:
    var rows: seq[W]
    for r in rl.rows:
      var parts: seq[string]
      for key in ["level", "cabinet", "direction"]:
        let v = s(r, key)
        if v.len > 0: parts.add v
      rows.add row(if s(r, "desc").len > 0: s(r, "desc") else: "Location list", parts.join(" · "))
    w.panelBox.add section("Location list", rows)
  if t.added.len > 0:
    let g = group("Added by hand", "The reader missed this tag; someone marked it on the drawing." &
                  (if t.note.len > 0: " Note: " & t.note else: ""))
    let addedId = t.added
    adw_preferences_group_add(g, button("Remove this tag", "destructive-action", proc () =
      confirm(w.window, "Remove this tag?", "The mark goes away on every device once approved.", "Remove", true, proc () =
        discard w.submit("tag_remove", newObj(@[("id", newStr(addedId))]), if k.len > 0: k else: "the mark"))))
    w.panelBox.add g
  if k.len == 0: return
  var where: seq[W]
  var seen: HashSet[string]
  let items1 = toSeq(m.tags)
  for i1 in 0 ..< items1.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let x = items1[i1]
      if x.full == k and x.sheet notin seen:
        seen.incl x.sheet
        let (okS, si) = m.sheetById(x.sheet)
        let id = x.id
        let sheet = x.sheet
        where.add button(if okS: si.name else: x.sheet, "pill", proc () =
          if sheet != w.sheet: w.showSheet(sheet)
          w.selectTag(id, true))
  if where.len > 1:
    let g = group("Appears on")
    let box = adw_wrap_box_new()
    adw_wrap_box_set_child_spacing(box, 6)
    adw_wrap_box_set_line_spacing(box, 6)
    for b in where: adw_wrap_box_append(box, b)
    adw_preferences_group_add(g, box)
    w.panelBox.add g
  let procs = m.procsOf(k)
  if procs.len > 0:
    var rows: seq[W]
    let items2 = toSeq(procs)
    for i2 in 0 ..< items2.len:
      closureScope:   # each pass gets its own copies of the captured variables
        let p = items2[i2]
        let pr = m.procById(p)
        let pid = p
        rows.add navRow(p, if pr != nil: s(pr, "title") else: "", "Open procedure " & p, proc () = w.openProc(pid))
    w.panelBox.add section("Used in procedures", rows)
  w.panelBox.add w.equipmentSection(t)
  w.panelBox.add w.photoSection(k)
