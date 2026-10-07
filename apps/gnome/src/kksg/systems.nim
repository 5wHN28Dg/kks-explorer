## Equipment by system: every code on the drawings, grouped block → system → subsystem → component kind (core
## views.systemsView), with a search field. A row opens its tag like a search result.

import std/strutils
import kks/json
import kks/views
import gtk, ui, viewer, win

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc n(node: JNode, k: string): int =
  if node != nil and node.get(k) != nil and node[k].isInt: int(node[k].i) else: 0

proc coverWords(photos: string): string =
  case photos
  of "both": "equipment and tag plate photos"
  of "equipment": "equipment photo only"
  of "plate": "tag plate photo only"
  else: "no photos"

proc coverDot(photos: string): W =
  ## the photo coverage colour of the drawings' coverage view, as a small image with its meaning as its name
  result = imageArea()
  gtk_drawing_area_set_content_width(result, 12)
  gtk_drawing_area_set_content_height(result, 12)
  gtk_widget_set_valign(result, GTK_ALIGN_CENTER)
  setAccessibleLabel(result, coverWords(photos))
  gtk_widget_set_tooltip_text(result, coverWords(photos).cstring)
  let (r, g, b) = coverColor(photos)
  result.onDraw(proc (c: Cairo, w, h: int) =
    cairo_set_source_rgb(c, r, g, b)
    cairo_arc(c, w / 2, h / 2, min(w, h) / 2 - 1, 0, 6.2832)
    cairo_fill(c))

proc itemRow(w: Win, it: JNode): W =
  let code = s(it, "code")
  let desc = s(it, "desc")
  let sheetName = s(it, "sheet_name")
  let count = n(it, "count")
  var sub: seq[string]
  if desc.len > 0: sub.add desc
  sub.add sheetName
  if count > 1: sub.add "×" & $count
  let tag = s(it, "tag")
  let sheet = s(it, "sheet")
  result = navRow(code, sub.join(" · "), "Show " & code & (if desc.len > 0: ", " & desc else: "") & ", on " & sheetName &
                  (if count > 1: ", appears " & $count & " times" else: ""), proc () =
    if sheet != w.sheet: w.showSheet(sheet)
    w.selectTag(tag, true))
  adw_action_row_add_prefix(result, coverDot(s(it, "photos")))

proc expander(title, subtitle: string, fill: proc (r: W), open: bool): W =
  ## an expander row whose children are built the first time it opens (thousands of codes otherwise)
  let r = adw_expander_row_new()
  adw_preferences_row_set_use_markup(r, 0)
  adw_preferences_row_set_title(r, title.cstring)
  adw_expander_row_set_subtitle(r, subtitle.cstring)
  var built = false
  proc build() =
    if not built:
      built = true
      fill(r)
  r.onPtr("notify::expanded", proc (p: W) =
    if adw_expander_row_get_expanded(r) != 0: build())
  if open:
    build()
    adw_expander_row_set_expanded(r, 1)
  r

proc codes(k: int): string = (if k == 1: "1 code" else: $k & " codes")

proc systemsPage*(w: Win): W =
  let outer = vbox(0)
  let q = gtk_search_entry_new()
  gtk_search_entry_set_placeholder_text(q, "Search codes, systems, descriptions")
  setAccessibleLabel(q, "Search equipment by system")
  margins(q, 8)
  let list = vbox(12)
  margins(list, 8)
  proc fill() =
    list.clear()
    let query = text(q).strip
    let v = systemsView(w.m, query)
    let total = n(v, "total")
    # while searching every level opens, unless that would build too many rows at once
    let open = query.len > 0 and total <= 300
    list.add label(if query.len == 0: codes(total) & " on the drawings"
                   elif total == 0: "Nothing found"
                   else: codes(total) & " found" & (if open: "" else: " (open a system to see them)"), "dim-label")
    for b in v["blocks"].elems:
      let blk = s(b, "blk")
      let bn = s(b, "blk_name")
      let g = group(if bn.len > 0: blk & " · " & bn else: "Block " & blk)
      list.add g
      let sys = b["systems"].elems
      for i in 0 ..< sys.len:
        closureScope:
          let sy1 = sys[i]
          let sn = s(sy1, "sys_name")
          let title = s(sy1, "sys") & (if sn.len > 0: " · " & sn else: "")
          adw_preferences_group_add(g, expander(title, codes(n(sy1, "count")), proc (r: W) =
            let subs = sy1["subsystems"].elems
            for j in 0 ..< subs.len:
              closureScope:
                let sub1 = subs[j]
                adw_expander_row_add_row(r, expander(s(sub1, "code"), codes(n(sub1, "count")), proc (r2: W) =
                  let kinds = sub1["kinds"].elems
                  for x in 0 ..< kinds.len:
                    closureScope:
                      let k1 = kinds[x]
                      let cn = s(k1, "comp_name")
                      adw_expander_row_add_row(r2, expander(s(k1, "comp") & (if cn.len > 0: " · " & cn else: ""),
                                                            codes(n(k1, "count")), proc (r3: W) =
                        for it in k1["items"].elems: adw_expander_row_add_row(r3, w.itemRow(it)), open)), open)), open))
    let other = v["other"].elems
    if other.len > 0:
      let g = group("Other", "Codes that don't decode as KKS")
      list.add g
      let others = other
      adw_preferences_group_add(g, expander("Other codes", codes(others.len), proc (r: W) =
        for it in others: adw_expander_row_add_row(r, w.itemRow(it)), open))
  q.on("search-changed", fill)
  fill()
  outer.add q, scrolled(list)
  outer
