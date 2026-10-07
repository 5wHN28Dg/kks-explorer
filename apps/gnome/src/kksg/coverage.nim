## Coverage: how complete the plant's record is (core views.coverageView): totals, then per sheet and per system,
## each with a bar of the photo coverage colours. A sheet row opens that sheet coloured by photos; a system row opens
## Equipment by system filtered to that system.

import std/[strutils, math, tables]
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

type
  Bar = ref object
    w: W
    counts: array[4, int]
  Page = ref object
    ## the widgets a sync updates in place (refreshFollowers): rows by key ("t:checked", "sheet:<id>", "sys:<code>" …)
    totals: W
    rows: Table[string, W]
    bars: Table[string, Bar]
    shape: string            ## the sheets and systems shown: when it changes, the page is rebuilt instead

proc setBar(b: Bar, p: JNode) =
  let words = photoWords(p)
  setAccessibleLabel(b.w, words)
  gtk_widget_set_tooltip_text(b.w, words.cstring)
  for i, k in photoKinds: b.counts[i] = n(p, k)
  gtk_widget_queue_draw(b.w)

proc photoBar(p: JNode, width = 44): Bar =
  ## a stacked bar of the four photo coverage colours, exposed as an image named by its numbers
  let b = Bar(w: imageArea())
  gtk_drawing_area_set_content_width(b.w, cint(width))
  gtk_drawing_area_set_content_height(b.w, 10)
  gtk_widget_set_valign(b.w, GTK_ALIGN_CENTER)
  b.setBar(p)
  b.w.onDraw(proc (c: Cairo, w, h: int) =
    cairo_set_source_rgb(c, 0.6, 0.6, 0.6)
    cairo_rectangle(c, 0, 0, float(w), float(h))
    cairo_stroke(c)
    var total = 0
    for x in b.counts: total += x
    if total == 0: return
    var x = 0.0
    for i, k in photoKinds:
      let part = float(w) * float(b.counts[i]) / float(total)
      if part <= 0: continue
      let (r, g, bl) = coverColor(k)
      cairo_set_source_rgb(c, r, g, bl)
      cairo_rectangle(c, x, 0, part, float(h))
      cairo_fill(c)
      x += part)
  b

proc totalsText(t: JNode): string =
  plural(n(t, "codes"), "code", "codes") & " on the drawings, in " & plural(n(t, "tags"), "tag", "tags")

proc totalsRows(t: JNode): seq[(string, string, string)] =
  ## (key, title, value)
  let codes = n(t, "codes")
  let tags = n(t, "tags")
  let p = t["photos"]
  @[("t:checked", "Checked by a person", $n(t, "verified") & " of " & plural(tags, "tag", "tags") & " (" &
       pct(n(t, "verified"), tags) & ")"),
    ("t:place", "Known place", $n(t, "located") & " of " & plural(codes, "code", "codes") & " (" & pct(n(t, "located"), codes) & ")"),
    ("t:photos", "Photos", "both " & $n(p, "both") & " · equipment only " & $n(p, "equipment") & " · tag plate only " &
       $n(p, "plate") & " · none " & $n(p, "none")),
    ("t:review", "Readings to review", $n(t, "review")),
    ("t:marked", "Missed tags marked", $n(t, "marked"))]

proc sheetSub(sh: JNode): string =
  result = plural(n(sh, "codes"), "code", "codes") & " · " & pct(n(sh, "verified"), n(sh, "tags")) & " checked · " &
           pct(n(sh, "located"), n(sh, "codes")) & " placed"
  if n(sh, "review") > 0: result.add " · " & $n(sh, "review") & " to review"
  if n(sh, "marked") > 0: result.add " · " & $n(sh, "marked") & " marked"

proc sysTitle(sy: JNode): string =
  let code = s(sy, "sys")
  let sn = s(sy, "sys_name")
  if code.len == 0: "Codes that don't decode" else: code & (if sn.len > 0: " · " & sn else: "")

proc sysSub(sy: JNode): string =
  plural(n(sy, "codes"), "code", "codes") & " · " & pct(n(sy, "verified"), n(sy, "codes")) & " checked · " &
    pct(n(sy, "located"), n(sy, "codes")) & " placed"

proc shapeOf(v: JNode): string =
  for sh in v["sheets"].elems: result.add "s\0" & s(sh, "id") & "\0" & s(sh, "name") & "\0"
  for sy in v["systems"].elems: result.add "y\0" & sysTitle(sy) & "\0"

proc fillCoverage(w: Win, pg: Page, list: W) =
  list.clear()
  pg.rows.clear()
  pg.bars.clear()
  let v = coverageView(w.m)
  pg.shape = shapeOf(v)
  let t = v["total"]
  pg.totals = group("Totals", totalsText(t))
  for (key, title, value) in totalsRows(t):
    let r = row(title, value)
    pg.rows[key] = r
    if key == "t:photos":
      let b = photoBar(t["photos"], 64)
      pg.bars[key] = b
      adw_action_row_add_suffix(r, b.w)
    adw_preferences_group_add(pg.totals, r)
  list.add pg.totals
  list.add label("Photo colours: green both · amber equipment only · blue tag plate only · red none", "dim-label")
  let sg = group("By sheet", "Open a sheet to see its tags coloured by photos")
  list.add sg
  let sheets = v["sheets"].elems
  for i in 0 ..< sheets.len:
    closureScope:
      let sh = sheets[i]
      let id = s(sh, "id")
      let name = s(sh, "name")
      let r = navRow(name, sheetSub(sh), "Open " & name & " coloured by photos", proc () =
        w.showSheet(id)
        # the toggle's handler colours the tags and says how
        if w.coverBtn != nil: gtk_toggle_button_set_active(w.coverBtn, 1))
      let b = photoBar(sh["photos"])
      adw_action_row_add_prefix(r, b.w)
      pg.rows["sheet:" & id] = r
      pg.bars["sheet:" & id] = b
      adw_preferences_group_add(sg, r)
  let yg = group("By system", "Open a system in Equipment by system")
  list.add yg
  let systems = v["systems"].elems
  for i in 0 ..< systems.len:
    closureScope:
      let sy = systems[i]
      let code = s(sy, "sys")
      let r = navRow(sysTitle(sy), sysSub(sy), "Show " & (if code.len == 0: "the codes that don't decode" else: "system " & code) &
                     " in Equipment by system", proc () =
        w.pushPage(w.systemsPage(if code.len == 0: OtherCodes else: code), "Equipment by system", "systems"))
      let b = photoBar(sy["photos"])
      adw_action_row_add_prefix(r, b.w)
      pg.rows["sys:" & code] = r
      pg.bars["sys:" & code] = b
      adw_preferences_group_add(yg, r)

proc updateCoverage(w: Win, pg: Page): bool =
  ## new numbers into the same rows and bars (nothing is replaced under the focus); false if sheets or systems came or
  ## went (then the page is rebuilt)
  let v = coverageView(w.m)
  if shapeOf(v) != pg.shape: return false
  let t = v["total"]
  adw_preferences_group_set_description(pg.totals, totalsText(t).cstring)
  for (key, _, value) in totalsRows(t): adw_action_row_set_subtitle(pg.rows[key], value.cstring)
  pg.bars["t:photos"].setBar(t["photos"])
  for sh in v["sheets"].elems:
    let key = "sheet:" & s(sh, "id")
    adw_action_row_set_subtitle(pg.rows[key], sheetSub(sh).cstring)
    pg.bars[key].setBar(sh["photos"])
  for sy in v["systems"].elems:
    let key = "sys:" & s(sy, "sys")
    adw_action_row_set_subtitle(pg.rows[key], sysSub(sy).cstring)
    pg.bars[key].setBar(sy["photos"])
  true

proc coveragePage*(w: Win): W =
  let list = vbox(12)
  margins(list, 8)
  let pg = Page()
  w.fillCoverage(pg, list)
  # a sync or an approval: new numbers in place; a rebuild when sheets or systems changed, never under the focus
  # (win.follow)
  discard w.follow(list, proc () = w.fillCoverage(pg, list), proc (): bool = w.updateCoverage(pg))
  scrolled(list)
