## The equipment panel (R3–R6; the GNOME app's panel.nim): what the drawing says, the location list, the person's
## own data (read-only until Edit), where else the code appears, procedures, photos, and the review of uncertain
## readings.

import std/[strutils, math, sets, tables, sequtils]
import kks/json
import kks/model
import appstate
import w32, ui, win, photos

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc normKks(s: string): string =
  for c in s.toUpperAscii:
    if c notin Whitespace: result.add c

proc validKks(code: string): bool =
  code.len >= 12 and code[0 .. 1].allCharsInSet(Digits) and code[2 .. 4].allCharsInSet(UppercaseLetters) and
    code[5 .. 6].allCharsInSet(Digits) and code[7 .. 8].allCharsInSet(UppercaseLetters) and
    code[9 .. 11].allCharsInSet(Digits) and code[12 .. ^1].allCharsInSet(UppercaseLetters + Digits)

const Fields = [("area", "Building / area"), ("floor", "Floor"), ("elev", "Elevation"), ("near", "Near / landmark"),
                ("loc", "How to find it"), ("notes", "Notes")]

var editing = ""      ## the tag whose fields are open for editing

proc reviewSection(w: Win, p: Page, t: Tag) =
  let sug = t.suggestion
  p.title("Check this tag")
  p.dim("The reader saw " & t.read[0] & " / " & t.read[1] & ", confidence " & $int(round(t.conf * 100)) & " %." &
        (if t.note.len > 0: " " & t.note else: "") & (if s(sug, "note").len > 0: " " & s(sug, "note") else: ""))
  let k = p.field("KKS (with suffix)", if s(sug, "kks").len > 0: s(sug, "kks") else: t.full)
  let isa = p.field("Function letters (instruments)", if s(sug, "isa").len > 0: s(sug, "isa") else: t.isa)
  let id = t.id
  let base = if w.m.state != nil and w.m.state.get("reviews") != nil and w.m.state["reviews"].get(id) != nil:
               w.m.state["reviews"][id] else: newNull()
  p.buttons(("Confirm", proc () =
    let code = normKks(k.text)
    if not validKks(code):
      w.toast("That is not a valid KKS (e.g. 11LAB70AA501)")
      return
    let isaV = isa.text.strip.toUpperAscii
    let data = newObj(@[("status", newStr("confirmed")), ("kks", newStr(code[0 ..< 12])), ("suffix", newStr(code[12 .. ^1])),
                        ("isa", if isaV.len > 0: newStr(isaV) else: newNull())])
    discard w.submit("review", newObj(@[("tag_id", newStr(id)), ("data", data), ("base", base)]), code)),
    ("Not a tag", proc () =
      discard w.submit("review", newObj(@[("tag_id", newStr(id)), ("data", newObj(@[("status", newStr("rejected"))])),
                                         ("base", base)]), "not a tag")))

proc equipmentSection(w: Win, p: Page, t: Tag) =
  let k = t.full
  let live = w.m.equipment(k)
  let rl = w.m.refLoc(t.bodyOf)
  p.title("Location and notes")
  if editing != t.id:
    for (f, title) in Fields:
      var v = s(live, f)
      if f == "elev" and v.len == 0 and rl.elev.len > 0: v = rl.elev & " (location list)"
      p.field(title, if v.len > 0: v else: "—", readonly = true)
    if live.get("custom") != nil:
      for c in live["custom"].elems: p.field(s(c, "k"), s(c, "v"), readonly = true)
    let id = t.id
    p.buttons(("Edit", proc () =
      editing = id
      w.rebuildPanel()))
    return
  var entries: seq[(string, HWND)]
  for (f, title) in Fields:
    entries.add (f, (if f == "notes": p.multiField(title, s(live, f), 80) else: p.field(title & (if f == "floor": " (0–10)" else: ""), s(live, f))))
  var custom: seq[(HWND, HWND)]
  if live.get("custom") != nil:
    for c in live["custom"].elems:
      custom.add (p.field("Custom field name", s(c, "k")), p.field("Custom field value", s(c, "v")))
  custom.add (p.field("New custom field name (optional)", ""), p.field("New custom field value", ""))
  let note = if not w.isAdmin: p.field("Note for the approver (optional)", "") else: nil
  p.buttons(("Save", proc () =
    var changes, base = newObj()
    for (f, e) in entries:
      let nv = e.text.replace("\r\n", "\n").strip
      if nv != s(live, f):
        if f == "floor" and nv.len > 0 and not (nv == "10" or (nv.len == 1 and nv[0] in Digits)):
          w.toast("Floor: a whole number from 0 to 10 (the height goes in Elevation)")
          return
        changes[f] = newStr(nv)
        base[f] = newStr(s(live, f))
    var cs = newArr()
    for (ek, ev) in custom:
      let kk = ek.text.strip
      let vv = ev.text.strip
      if kk.len > 0 or vv.len > 0: cs.elems.add newObj(@[("k", newStr(kk)), ("v", newStr(vv))])
    let oldC = if live.get("custom") != nil: live["custom"] else: newArr()
    if toText(cs) != toText(oldC):
      changes["custom"] = cs
      base["custom"] = oldC
    if changes.len == 0:
      w.toast("Nothing changed")
      return
    if w.submit("equipment", newObj(@[("kks", newStr(k)), ("changes", changes), ("base", base)]), k,
                if note != nil: note.text else: "").len > 0:
      editing = ""
      w.rebuildPanel()),
    ("Cancel", proc () =
      editing = ""
      w.rebuildPanel()))

proc buildPanel*(w: Win, t: Tag) =
  let p = w.panel
  p.clear()
  let m = w.m
  let k = t.full
  p.title((if k.len > 0: k else: "Unread tag"))
  p.dim((if t.isa.len > 0: t.isa & " · " else: "") & m.kindName(t))
  p.buttons(("Close", proc () = w.selectTag("", false)))
  var mine: seq[string]
  for sub in w.myOpen():
    let pl = sub.get("payload")
    if pl == nil: continue
    if (sub["kind"].s in ["equipment", "photo", "link"] and s(pl, "kks") == k and k.len > 0) or
       (sub["kind"].s == "review" and s(pl, "tag_id") == t.id):
      mine.add sub["kind"].s & (if sub["status"].s == "conflict": " (held: clashes)" else: " (waiting for approval)")
  if mine.len > 0: p.dim("Your pending changes: " & mine.join(", "))
  if w.linkProc.len > 0 and k.len > 0:   # link mode (R7), reachable from the keyboard
    let lp = w.linkProc
    let ls = w.linkStep
    p.buttons(("Link " & k & " to step " & $ls & " of " & lp, proc () =
      discard w.submit("link", newObj(@[("proc", newStr(lp)), ("step", newInt(ls)), ("kks", newStr(k)),
                       ("on", newBool(true))]), k & " → step " & $ls)
      w.loadModel()
      w.applyHighlights()))
  if t.status == "review": w.reviewSection(p, t)
  let (ok, d) = m.decode(t)
  if ok:
    p.title("From the drawing")
    p.field("Plant unit", d.blk & "  " & m.blockName(d.blk), readonly = true)
    p.field("System", d.sys & "  " & (if m.systemName(d.sys).len > 0: m.systemName(d.sys) else: "not in the legend"), readonly = true)
    p.field("Subsystem no.", d.fn, readonly = true)
    p.field("Component", d.comp & "  " & m.componentName(d.comp), readonly = true)
    p.field("Number", d.num, readonly = true)
    if d.isa.len > 0: p.field("Instrument", d.isa, readonly = true)
    p.field("Reading", (case t.status
      of "confirmed": "confirmed by a person"
      of "verified": "checked by eye against the drawing"
      else: "automatic, " & $int(round(t.conf * 100)) & " % confidence"), readonly = true)
    if t.flag.len > 0: p.field("Flag", t.flag, readonly = true)
  let rl = m.refLoc(t.bodyOf)
  if rl.rows.len > 0:
    p.title("Location list")
    for r in rl.rows:
      var parts: seq[string]
      for key in ["level", "cabinet", "direction"]:
        if s(r, key).len > 0: parts.add s(r, key)
      p.field((if s(r, "desc").len > 0: s(r, "desc") else: "Location list"), parts.join(" · "), readonly = true)
  if t.added.len > 0:
    p.title("Added by hand")
    p.dim("The reader missed this tag; someone marked it on the drawing." & (if t.note.len > 0: " Note: " & t.note else: ""))
    let addedId = t.added
    p.buttons(("Remove this tag", proc () =
      if ask(w.hwnd, "Remove this tag?", "The mark goes away on every device once approved."):
        discard w.submit("tag_remove", newObj(@[("id", newStr(addedId))]), if k.len > 0: k else: "the mark")))
  if k.len == 0: return
  var seen: HashSet[string]
  var where: seq[(string, string, string)]
  for x in m.tags:
    if x.full == k and x.sheet notin seen:
      seen.incl x.sheet
      let (okS, si) = m.sheetById(x.sheet)
      where.add ((if okS: si.name else: x.sheet), x.sheet, x.id)
  if where.len > 1:
    p.title("Appears on")
    var specs: seq[(string, proc ())]
    let lp1 = toSeq(0 ..< where.len)
    for lp1i in 0 ..< lp1.len:
      closureScope:
        let i = lp1[lp1i]
        let (name, sheet, id) = where[i]
        specs.add (name, proc () =
          if sheet != w.sheet: w.showSheet(sheet)
          w.selectTag(id, true))
    p.buttons(specs)
  let procs = m.procsOf(k)
  if procs.len > 0:
    p.title("Used in procedures")
    var rows: seq[string]
    for pid in procs:
      let pr = m.procById(pid)
      rows.add pid & "  " & (if pr != nil: s(pr, "title") else: "")
    let ps = toSeq(procs)
    p.list(rows, 26 * min(6, rows.len) + 6, onActivate = (proc (i: int) =
      w.activeProc = ps[i]
      w.tab = "procedures"
      w.rebuildSide()
      w.applyHighlights()), openLabel = "Open the procedure")
  w.equipmentSection(p, t)
  w.photoSection(p, k)
  p.layout()
