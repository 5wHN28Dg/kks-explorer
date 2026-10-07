## Coverage: how complete the plant's record is (core views.coverageView): totals, then per sheet and per system,
## each with a bar of the photo coverage colours. A sheet row opens that sheet coloured by photos; a system row opens
## Equipment by system filtered to that system.

import std/[strutils, math]
import kks/json
import kks/views
import gtk, ui, viewer, win, sidepages, systems

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc n(node: JNode, k: string): int =
  if node != nil and node.get(k) != nil and node[k].isInt: int(node[k].i) else: 0

proc pct(a, b: int): string =
  if b == 0: "–" else: $int(round(100 * a / b)) & " %"

proc plural(k: int, one, many: string): string = $k & " " & (if k == 1: one else: many)

const photoKinds = ["both", "equipment", "plate", "none"]

proc photoWords*(p: JNode): string =
  ## the bar's text equivalent: "photos: 2 equipment and tag plate, 1 equipment only, 0 tag plate only, 3 none"
  "photos: " & $n(p, "both") & " equipment and tag plate, " & $n(p, "equipment") & " equipment only, " &
    $n(p, "plate") & " tag plate only, " & $n(p, "none") & " none"

proc photoBar(p: JNode, width = 44): W =
  ## a stacked bar of the four photo coverage colours, exposed as an image named by its numbers
  result = imageArea()
  gtk_drawing_area_set_content_width(result, cint(width))
  gtk_drawing_area_set_content_height(result, 10)
  gtk_widget_set_valign(result, GTK_ALIGN_CENTER)
  let words = photoWords(p)
  setAccessibleLabel(result, words)
  gtk_widget_set_tooltip_text(result, words.cstring)
  var counts: array[4, int]
  var total = 0
  for i, k in photoKinds:
    counts[i] = n(p, k)
    total += counts[i]
  result.onDraw(proc (c: Cairo, w, h: int) =
    cairo_set_source_rgb(c, 0.6, 0.6, 0.6)
    cairo_rectangle(c, 0, 0, float(w), float(h))
    cairo_stroke(c)
    if total == 0: return
    var x = 0.0
    for i, k in photoKinds:
      let part = float(w) * float(counts[i]) / float(total)
      if part <= 0: continue
      let (r, g, b) = coverColor(k)
      cairo_set_source_rgb(c, r, g, b)
      cairo_rectangle(c, x, 0, part, float(h))
      cairo_fill(c)
      x += part)

proc totalsGroup(t: JNode): W =
  let codes = n(t, "codes")
  let tags = n(t, "tags")
  let p = t["photos"]
  result = group("Totals", plural(codes, "code", "codes") & " on the drawings, in " & plural(tags, "tag", "tags"))
  adw_preferences_group_add(result, row("Checked by a person", $n(t, "verified") & " of " & plural(tags, "tag", "tags") &
                                        " (" & pct(n(t, "verified"), tags) & ")"))
  adw_preferences_group_add(result, row("Known place", $n(t, "located") & " of " & plural(codes, "code", "codes") &
                                        " (" & pct(n(t, "located"), codes) & ")"))
  let ph = row("Photos", "both " & $n(p, "both") & " · equipment only " & $n(p, "equipment") & " · tag plate only " &
                          $n(p, "plate") & " · none " & $n(p, "none"))
  adw_action_row_add_suffix(ph, photoBar(p, 64))
  adw_preferences_group_add(result, ph)
  adw_preferences_group_add(result, row("Readings to review", $n(t, "review")))
  adw_preferences_group_add(result, row("Missed tags marked", $n(t, "marked")))

proc coveragePage*(w: Win): W =
  let list = vbox(12)
  margins(list, 8)
  let v = coverageView(w.m)
  list.add totalsGroup(v["total"])
  list.add label("Photo colours: green both · amber equipment only · blue tag plate only · red none", "dim-label")
  let sg = group("By sheet", "Open a sheet to see its tags coloured by photos")
  list.add sg
  let sheets = v["sheets"].elems
  for i in 0 ..< sheets.len:
    closureScope:
      let sh = sheets[i]
      let id = s(sh, "id")
      let name = s(sh, "name")
      var sub = plural(n(sh, "codes"), "code", "codes") & " · " & pct(n(sh, "verified"), n(sh, "tags")) & " checked · " &
                pct(n(sh, "located"), n(sh, "codes")) & " placed"
      if n(sh, "review") > 0: sub.add " · " & $n(sh, "review") & " to review"
      if n(sh, "marked") > 0: sub.add " · " & $n(sh, "marked") & " marked"
      let r = navRow(name, sub, "Open " & name & " coloured by photos", proc () =
        w.showSheet(id)
        # the toggle's handler colours the tags and says how
        if w.coverBtn != nil: gtk_toggle_button_set_active(w.coverBtn, 1))
      adw_action_row_add_prefix(r, photoBar(sh["photos"]))
      adw_preferences_group_add(sg, r)
  let yg = group("By system", "Open a system in Equipment by system")
  list.add yg
  let systems = v["systems"].elems
  for i in 0 ..< systems.len:
    closureScope:
      let sy = systems[i]
      let code = s(sy, "sys")
      let sn = s(sy, "sys_name")
      let title = if code.len == 0: "Codes that don't decode" else: code & (if sn.len > 0: " · " & sn else: "")
      let sub = plural(n(sy, "codes"), "code", "codes") & " · " & pct(n(sy, "verified"), n(sy, "codes")) & " checked · " &
                pct(n(sy, "located"), n(sy, "codes")) & " placed"
      let r = navRow(title, sub, "Show " & (if code.len == 0: "the codes that don't decode" else: "system " & code) &
                     " in Equipment by system", proc () =
        w.pushPage(w.systemsPage(if code.len == 0: OtherCodes else: code), "Equipment by system", "systems"))
      adw_action_row_add_prefix(r, photoBar(sy["photos"]))
      adw_preferences_group_add(yg, r)
  scrolled(list)
