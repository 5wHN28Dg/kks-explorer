## Equipment by system: every code on the drawings, grouped block → system → subsystem → component kind (core
## views.systemsView), with a search field. A row opens its tag like a search result.

import std/[strutils, sets]
import kks/json
import kks/views
import gtk, ui, viewer, win

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc n(node: JNode, k: string): int =
  if node != nil and node.get(k) != nil and node[k].isInt: int(node[k].i) else: 0

proc coverWords*(photos: string): string =
  case photos
  of "both": "equipment and tag plate photos"
  of "equipment": "equipment photo only"
  of "plate": "tag plate photo only"
  else: "no photos"

proc photoMark*(photos: string, named = true): W =
  ## the photo mark beside a code (search results, equipment by system): the coverage colour of the drawings and a
  ## shape of its own per state, so it reads without colour: none = an empty ring, equipment only = a half-filled
  ## disc, tag plate only = a filled square, both = a filled disc. A thin line in the text colour around it keeps the
  ## shape at 3:1 on any theme (amber alone does not reach it on a light background). A small image with its meaning
  ## as its name and tooltip; `named = false` beside a label that says it (the legend).
  result = imageArea()
  gtk_drawing_area_set_content_width(result, 14)
  gtk_drawing_area_set_content_height(result, 14)
  gtk_widget_set_valign(result, GTK_ALIGN_CENTER)
  if named:
    setAccessibleLabel(result, coverWords(photos))
    gtk_widget_set_tooltip_text(result, coverWords(photos).cstring)
  let (r, g, b) = coverColor(photos)
  let me = result
  result.onDraw(proc (c: Cairo, w, h: int) =
    let cx = w / 2
    let cy = h / 2
    let rad = min(w, h) / 2 - 2.0        # the coloured shape; the outline runs just outside it
    var fg: GdkRGBA
    gtk_widget_get_color(me, addr fg)
    proc shape(grow: float) =
      cairo_new_path(c)
      if photos == "plate": cairo_rectangle(c, cx - rad - grow, cy - rad - grow, 2 * (rad + grow), 2 * (rad + grow))
      else: cairo_arc(c, cx, cy, rad + grow, 0, 6.2832)
    cairo_set_source_rgb(c, r, g, b)
    case photos
    of "both", "plate":
      shape(0)
      cairo_fill(c)
    of "equipment":                      # the left half filled, the ring whole
      cairo_new_path(c)
      cairo_arc(c, cx, cy, rad, 1.5708, 4.7124)
      cairo_close_path(c)
      cairo_fill(c)
      shape(-1)
      cairo_set_line_width(c, 2)
      cairo_stroke(c)
    else:
      shape(-1)
      cairo_set_line_width(c, 2)
      cairo_stroke(c)
    cairo_set_source_rgba(c, fg.red, fg.green, fg.blue, 1)
    shape(0.5)
    cairo_set_line_width(c, 1)
    cairo_stroke(c))

proc photoLegend*(): W =
  ## what the photo marks mean, in two lines (under the search results)
  result = vbox(2)
  let kinds = ["none", "equipment", "plate", "both"]
  for line in 0 .. 1:
    let hb = hbox(6)
    if line == 0: hb.add label("Photos:", "dim-label caption", wrap = false)
    for k in kinds[2 * line .. 2 * line + 1]:
      hb.add photoMark(k, named = false), label(coverWords(k), "dim-label caption", wrap = false)
    result.add hb
  discard margins(result, 6)

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
    w.goToTag(sheet, tag))
  adw_action_row_add_prefix(result, photoMark(s(it, "photos")))

proc expander(title, subtitle: string, fill: proc (r: W), open: bool, key = "", opened: ref HashSet[string] = nil): W =
  ## an expander row whose children are built the first time it opens (thousands of codes otherwise); `opened`
  ## remembers the open rows by `key`, so a rebuild after a sync opens them again
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
    let on = adw_expander_row_get_expanded(r) != 0
    if on: build()
    if opened != nil and key.len > 0:
      if on: opened[].incl key else: opened[].excl key)
  if open or (opened != nil and key in opened[]):
    build()
    adw_expander_row_set_expanded(r, 1)
  r

proc codes(k: int): string = (if k == 1: "1 code" else: $k & " codes")

const OtherCodes* = "-"   ## systemsPage(only = OtherCodes): just the codes that don't decode

proc systemsPage*(w: Win, only = ""): W =
  ## `only`: show just this system (a code like "LAB", or OtherCodes), opened, until the search is used
  let outer = vbox(0)
  var only = only
  let q = gtk_search_entry_new()
  gtk_search_entry_set_placeholder_text(q, "Search codes, systems, descriptions")
  setAccessibleLabel(q, "Search equipment by system")
  margins(q, 8)
  let list = vbox(12)
  margins(list, 8)
  let opened = new HashSet[string]
  var follower: Follower
  proc fill() =
    if follower != nil: follower.stale = false
    list.clear()
    let query = text(q).strip
    let v = systemsView(w.m, query)
    var total = n(v, "total")
    var blocks = v["blocks"].elems
    if only.len > 0:
      # one system: keep its rows in every block (the other codes for OtherCodes)
      total = 0
      var kept: seq[JNode]
      for b in blocks:
        var sys: seq[JNode]
        for sy in b["systems"].elems:
          if s(sy, "sys") == only:
            sys.add sy
            total += n(sy, "count")
        if sys.len > 0:
          var b2 = newObj(@[("blk", newStr(s(b, "blk"))), ("blk_name", newStr(s(b, "blk_name"))), ("systems", newArr())])
          b2["systems"].elems = sys
          kept.add b2
      blocks = kept
      if only == OtherCodes: total = v["other"].elems.len
    # while searching every level opens, unless that would build too many rows at once
    let open = (query.len > 0 or only.len > 0) and total <= 300
    if only.len > 0:
      let head = hbox(6)
      let what = if only == OtherCodes: "that don't decode" else: "in system " & only
      let l = label(codes(total) & " " & what, "dim-label")
      gtk_widget_set_hexpand(l, 1)
      head.add l, button("Show all systems", "flat", proc () =
        only = ""
        fill()
        discard gtk_widget_grab_focus(q))     # the button is gone: the focus goes to the search field
      list.add head
    else:
      list.add label(if query.len == 0: codes(total) & " on the drawings"
                     elif total == 0: "Nothing found"
                     else: codes(total) & " found" & (if open: "" else: " (open a system to see them)"), "dim-label")
    for b in blocks:
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
          let sk = s(sy1, "sys") & "|" & blk
          adw_preferences_group_add(g, expander(title, codes(n(sy1, "count")), proc (r: W) =
            let subs = sy1["subsystems"].elems
            for j in 0 ..< subs.len:
              closureScope:
                let sub1 = subs[j]
                let subk = sk & "|" & s(sub1, "code")
                adw_expander_row_add_row(r, expander(s(sub1, "code"), codes(n(sub1, "count")), proc (r2: W) =
                  let kinds = sub1["kinds"].elems
                  for x in 0 ..< kinds.len:
                    closureScope:
                      let k1 = kinds[x]
                      let cn = s(k1, "comp_name")
                      adw_expander_row_add_row(r2, expander(s(k1, "comp") & (if cn.len > 0: " · " & cn else: ""),
                                                            codes(n(k1, "count")), proc (r3: W) =
                        for it in k1["items"].elems: adw_expander_row_add_row(r3, w.itemRow(it)), open,
                        subk & "|" & s(k1, "comp"), opened)), open, subk, opened)), open, sk, opened))
    let other = if only.len == 0 or only == OtherCodes: v["other"].elems else: @[]
    if other.len > 0:
      let g = group("Other", "Codes that don't decode as KKS")
      list.add g
      let others = other
      adw_preferences_group_add(g, expander("Other codes", codes(others.len), proc (r: W) =
        for it in others: adw_expander_row_add_row(r, w.itemRow(it)), open, "other", opened))
  q.on("search-changed", proc () =
    only = ""                 # a search covers every system again
    opened[].clear()          # a search opens what it finds; what was open before doesn't stay open
    fill())
  fill()
  # a sync or an approval rebuilds the tree (new codes, photo colours), never under the focus (win.follow)
  follower = w.follow(list, fill)
  outer.add q, scrolled(list)
  outer
