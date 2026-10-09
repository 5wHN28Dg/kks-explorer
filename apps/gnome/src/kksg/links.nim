## Links between drawings: the off-page connectors (C16, D2 …) on a sheet, each a hotspot on the drawing and a row in
## "Connectors on this sheet" (named for screen readers: "Connector C16, continues on Sheet X"). Activating one opens
## where its line continues: one target goes there, several ask which, none says so. Targets: core linksView.

import std/[strutils, sequtils]
import kks/[json, views]
import kks/model
import gtk, ui, win, viewer

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc f(n: JNode, k: string): float =
  if n != nil and n.get(k) != nil and n[k].isNum: n[k].num else: 0.0

proc targetName(t: JNode): string =
  if t.get("same_sheet") != nil and t["same_sheet"].kind == jBool and t["same_sheet"].b: "elsewhere on this sheet"
  else: s(t, "sheet_name")

proc whereText*(l: JNode): string =
  var names: seq[string]
  for t in l["targets"].elems:
    let n = targetName(t)
    if n notin names: names.add n
  if names.len == 0: "the other end isn't on any drawing in the app" else: "continues on " & names.join(", ")

proc linkName*(l: JNode): string = "Connector " & s(l, "label") & ", " & whereText(l)

proc setLinks*(w: Win) =
  ## the open sheet's connectors into the viewer (after setSheet or a data reload)
  var boxes: seq[TagBox]
  for l in linksView(w.m, w.sheet).elems:
    boxes.add TagBox(id: s(l, "label"), x0: f(l, "x0"), y0: f(l, "y0"), x1: f(l, "x1"), y1: f(l, "y1"), label: linkName(l))
  w.v.links = boxes
  w.v.linkSel = -1         # an index into the old list: a reload can reorder it (goTo sets it after this)
  gtk_widget_queue_draw(w.v.widget)

proc goTo(w: Win, label: string, t: JNode) =
  let sheet = s(t, "sheet")
  if not w.m.sheetById(sheet)[0]:     # a dialog left open while a new publish removed the sheet
    w.toast("Connector " & label & ": that drawing is no longer in the app")
    return
  if sheet != w.sheet: w.showSheet(sheet)
  else: adw_navigation_split_view_set_show_content(w.split, 1)
  let (x0, y0, x1, y1) = (f(t, "x0"), f(t, "y0"), f(t, "x1"), f(t, "y1"))
  w.v.linkSel = -1
  for i, b in w.v.links:
    if abs(b.x0 - x0) < 0.01 and abs(b.y0 - y0) < 0.01: w.v.linkSel = i
  w.v.centerOn(x0, y0, x1, y1)
  w.toast("Connector " & label & " on " & (if s(t, "sheet_name").len > 0: s(t, "sheet_name") else: sheet))

proc responseLabels*(ts: seq[JNode]): seq[string] =
  ## the choice dialog's buttons, one per target: the sheet's name, numbered when one sheet has the code more than
  ## once (else two identical buttons), with "_" doubled (a response label underlines the letter after a "_")
  var names: seq[string]
  for t in ts: names.add targetName(t)
  for i, n in names:
    var l = n
    if names.count(n) > 1:
      var k = 0
      for j in 0 .. i:
        if names[j] == n: inc k
      l.add " (" & $k & " of " & $names.count(n) & ")"
    result.add l.replace("_", "__")

proc followLink*(w: Win, sheet, label: string, x0, y0: float) =
  ## the connector `label` at (x0, y0) of `sheet`. The viewer's circles and the sidebar's rows keep the connector they
  ## show, not an index: a reload in between (a new publish) can reorder them. The sidebar passes the sheet it was
  ## built for: following a link opens another sheet under it, and its rows must still mean the first sheet's.
  let ls = linksView(w.m, sheet)
  let i = findLink(ls, label, x0, y0)
  if i < 0:
    w.toast("Connector " & label & " is no longer on this drawing")
    return
  let l = ls.elems[i]
  let ts = l["targets"].elems
  if ts.len == 0:
    w.toast("Connector " & label & ": the other end isn't on any drawing in the app")
  elif ts.len == 1:
    w.goTo(label, ts[0])
  else:
    let d = adw_alert_dialog_new(("Where does " & label & " continue?").cstring,
                                 "This connector's code appears in more than one place.")
    for j, r in responseLabels(ts):
      adw_alert_dialog_add_response(d, ("t" & $j).cstring, r.cstring)
    adw_alert_dialog_add_response(d, "cancel", "Cancel")
    adw_alert_dialog_set_default_response(d, "t0")
    adw_alert_dialog_set_close_response(d, "cancel")
    d.onResponse(proc (id: string) =
      if id.startsWith("t"):
        let j = parseInt(id[1 .. ^1])
        if j < ts.len: w.goTo(label, ts[j]))
    present(d, w.window)

proc connectorsPage*(w: Win): W =
  let box = vbox(8)
  margins(box, 12)
  let here = w.sheet
  let ls = linksView(w.m, here)
  if ls.len == 0:
    box.add label("No connectors to other drawings on this sheet.", "dim-label")
    return scrolled(box)
  box.add label("Where this sheet's lines continue (the circled codes on the drawing).", "dim-label")
  let list = gtk_list_box_new()
  gtk_widget_add_css_class(list, "boxed-list")
  gtk_list_box_set_selection_mode(list, GTK_SELECTION_NONE)
  for i in 0 ..< ls.len:
    closureScope:
      let l = ls.elems[i]
      let (lab, x0, y0) = (s(l, "label"), f(l, "x0"), f(l, "y0"))
      gtk_list_box_append(list, navRow("Connector " & lab, whereText(l), linkName(l), proc () = w.followLink(here, lab, x0, y0)))
  box.add list
  scrolled(box)
