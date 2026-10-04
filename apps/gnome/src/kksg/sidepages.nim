## The sidebar's pages (R5, R7): procedures with step ↔ equipment links, the review queue, the sheet's markup notes,
## the floor filter.

import std/[strutils, tables, sets, algorithm, sequtils]
import kks/json
import kks/model
import gtk, ui, appstate, viewer, win

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc links(w: Win): seq[JNode] =
  if w.m.state != nil and w.m.state.get("links") != nil: w.m.state["links"].elems else: @[]

proc pushPage*(w: Win, child: W, title, tag: string) =
  ## a sidebar page with its own header (the header shows the Back button)
  let tv = toolbarView(headerBar(adw_window_title_new(title.cstring, "")), child)
  adw_navigation_view_push(w.sideNav, adw_navigation_page_new_with_tag(tv, title.cstring, tag.cstring))

proc procedurePage*(w: Win, id: string): W

proc tagsWithCode(w: Win, k: string): seq[Tag] =
  for t in w.m.tags:
    if t.full == k: result.add t

proc procedureDetail(w: Win, id: string, box: W) =
  box.clear()
  let p = w.m.procById(id)
  if p == nil: return
  var path: seq[string]
  if p.get("path") != nil:
    for x in p["path"].elems: path.add x.s
  box.add label(s(p, "id") & "  " & s(p, "title"), "title-4", selectable = true)
  # `source`: a procedure from another document (tools/procedure_import.py); else the operation manual's page
  let src = if p.get("source") != nil and p["source"].kind == jStr and p["source"].s.len > 0: p["source"].s
            else: "manual page " & (if p.get("page") != nil: $p["page"].i else: "?")
  box.add label(path.join(" › ") & " · " & src, "dim-label")
  let ls = w.links.filterIt(it["proc"].s == id)
  var counts = initOrderedTable[string, int]()
  for l in ls:
    for t in w.tagsWithCode(l["kks"].s): counts.mgetOrPut(t.sheet, 0).inc
  if counts.len > 0:
    let g = group("Linked equipment on")
    let wb = adw_wrap_box_new()
    adw_wrap_box_set_child_spacing(wb, 6)
    let items1 = toSeq(counts.pairs)
    for i1 in 0 ..< items1.len:
      closureScope:   # each pass gets its own copies of the captured variables
        let (sh, n) = items1[i1]
        let (ok, si) = w.m.sheetById(sh)
        let shid = sh
        adw_wrap_box_append(wb, button((if ok: si.name else: sh) & " (" & $n & ")", "pill", proc () = w.showSheet(shid)))
    adw_preferences_group_add(g, wb)
    box.add g
  else:
    box.add label("No equipment linked yet. The manual names equipment by description, not KKS: choose “Link equipment” " &
                  "on a step, then click the matching tags on the drawing. Once per step.", "dim-label")
  if p.get("intro") != nil and s(p, "intro").len > 0: box.add label(s(p, "intro"))
  let items2 = toSeq(p["steps"].elems)
  for i2 in 0 ..< items2.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let st = items2[i2]
      let n = int(st["n"].i)
      let g = group($n & ")")
      adw_preferences_group_add(g, label(s(st, "text"), selectable = true))
      let wb = adw_wrap_box_new()
      adw_wrap_box_set_child_spacing(wb, 6)
      adw_wrap_box_set_line_spacing(wb, 6)
      let items3 = toSeq(ls.filterIt(int(it["step"].i) == n))
      for i3 in 0 ..< items3.len:
        closureScope:   # each pass gets its own copies of the captured variables
          let l = items3[i3]
          let k = l["kks"].s
          let ts = w.tagsWithCode(k)
          let chip = hbox(0)
          gtk_widget_add_css_class(chip, "linked")
          chip.add button(k, "", proc () =
            if ts.len > 0:
              if ts[0].sheet != w.sheet: w.showSheet(ts[0].sheet)
              w.selectTag(ts[0].id, true)
            else: w.toast(k & " is not on any sheet"))
          chip.add iconButton("window-close-symbolic", "Unlink " & k & " from step " & $n, proc () =
            discard w.submit("link", newObj(@[("proc", newStr(id)), ("step", newInt(n)), ("kks", newStr(k)), ("on", newBool(false))]),
                             "unlink " & k)
            w.loadModel()
            w.applyHighlights()
            w.procedureDetail(id, box))
          adw_wrap_box_append(wb, chip)
      adw_wrap_box_append(wb, button("+ Link equipment", "flat", proc () =
        w.linkProc = id
        w.linkStep = n
        w.setBanner("Click tags on the drawing (or Link in a tag's panel) to link them to step " & $n & " of " & id, "Done", proc () =
          w.linkProc = ""
          w.setBanner("", "", nil)
          w.procedureDetail(id, box)
          w.rebuildPanel())
        w.rebuildPanel()))
      adw_preferences_group_add(g, wb)
      box.add g

proc procedurePage*(w: Win, id: string): W =
  let box = vbox(12)
  margins(box, 12)
  w.activeProc = id
  w.applyHighlights()
  w.procedureDetail(id, box)
  scrolled(box)

proc proceduresPage*(w: Win): W =
  let outer = vbox(0)
  let q = gtk_search_entry_new()
  gtk_search_entry_set_placeholder_text(q, "Search procedures")
  setAccessibleLabel(q, "Search procedures")
  margins(q, 8)
  let list = vbox(12)
  margins(list, 8)
  proc fill() =
    list.clear()
    let query = text(q).strip.toLowerAscii
    var last = ""
    var g: W = nil
    if w.m.procs == nil: return
    proc hayOf(p: JNode): string =
      result = (s(p, "id") & " " & s(p, "title")).toLowerAscii
      for x in p["path"].elems: result.add " " & x.s.toLowerAscii
      for st in p["steps"].elems: result.add " " & s(st, "text").toLowerAscii
    let shown = w.m.procs.elems.filterIt(query.len == 0 or query in hayOf(it))
    for pi in 0 ..< shown.len:
      let chapter = if shown[pi]["path"].elems.len > 0: shown[pi]["path"][0].s else: s(shown[pi], "title")
      if chapter != last or g == nil:
        g = group(chapter)
        list.add g
        last = chapter
      closureScope:   # each pass gets its own copies of the captured variables
        let p = shown[pi]
        let id = s(p, "id")
        var linked = 0
        for l in w.links:
          if l["proc"].s == id: inc linked
        adw_preferences_group_add(g, navRow(id & "  " & s(p, "title"), $p["steps"].elems.len & " steps" &
          (if linked > 0: " · " & $linked & " linked" else: ""), "Open procedure " & id, proc () =
            w.pushPage(w.procedurePage(id), id, "proc")))
  q.on("search-changed", fill)
  fill()
  outer.add q, scrolled(list)
  outer

proc reviewPage*(w: Win): W =
  ## tags the reader wasn't sure of and no one has decided yet; the open sheet's first
  let box = vbox(12)
  margins(box, 8)
  var pend: seq[Tag]
  let reviews = if w.m.state != nil: w.m.state.get("reviews") else: nil
  for t in w.m.tags:
    if t.status == "review" and (reviews == nil or reviews.get(t.id) == nil): pend.add t
  let here = w.sheet
  pend.sort(proc (a, b: Tag): int =
    let ka = ((if a.sheet == here: 0 else: 1), a.sheet, (if a.suggestion == nil: 1 else: 0))
    let kb = ((if b.sheet == here: 0 else: 1), b.sheet, (if b.suggestion == nil: 1 else: 0))
    cmp(ka, kb))
  if pend.len == 0: box.add label("Nothing left to review.", "dim-label")
  var last = ""
  var g: W = nil
  let items4 = toSeq(pend[0 ..< min(250, pend.len)])
  for i4 in 0 ..< items4.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let t = items4[i4]
      if t.sheet != last:
        let (ok, si) = w.m.sheetById(t.sheet)
        var n = 0
        for x in pend:
          if x.sheet == t.sheet: inc n
        g = group((if ok: si.name else: t.sheet) & " (" & $n & ")")
        box.add g
        last = t.sheet
      let sug = if t.suggestion != nil and t.suggestion.get("kks") != nil: " → " & t.suggestion["kks"].s else: ""
      let id = t.id
      let sheet = t.sheet
      adw_preferences_group_add(g, navRow(t.read[0] & " / " & t.read[1] & sug, "confidence " & $int(t.conf * 100) & " %",
        "Check the tag read as " & t.read[1], proc () =
          if sheet != w.sheet: w.showSheet(sheet)
          w.selectTag(id, true)))
  scrolled(box)

proc notesPage*(w: Win): W =
  let box = vbox(8)
  margins(box, 12)
  let (ok, si) = w.m.sheetById(w.sheet)
  if not ok or si.notes.len == 0:
    box.add label("No markups on this sheet.", "dim-label")
  else:
    box.add label("Text added to this PDF by markup (not part of the CAD drawing).", "dim-label")
    for n in si.notes: box.add label(n, "card", selectable = true).margins(4)
  scrolled(box)

proc floors*(w: Win): seq[string] =
  var seen: HashSet[string]
  let eq = if w.m.state != nil: w.m.state.get("equipment") else: nil
  if eq != nil:
    for (_, e) in eq.fields:
      if e.get("floor") != nil and e["floor"].isStr:
        let f = e["floor"].s.strip
        if f.len > 0 and f notin seen:
          seen.incl f
          result.add f
  result.sort(proc (a, b: string): int =
    let na = try: parseFloat(a) except ValueError: 1e9
    let nb = try: parseFloat(b) except ValueError: 1e9
    if na != nb: cmp(na, nb) else: cmp(a, b))
