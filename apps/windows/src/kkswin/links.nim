## Links between drawings (the GNOME app's links.nim): the off-page connectors (C16, D2 …) on a sheet, each a hotspot
## on the drawing (a UI Automation button named "Connector C16, continues on Sheet X") and a row in "Connectors on
## this sheet". Activating one opens where its line continues: one target goes there, several ask which, none says
## so. Targets: core linksView.

import std/[strutils, sequtils]
import kks/[json, views]
import kks/model
import w32, ui, win, viewer

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
    boxes.add TagBox(id: s(l, "label"), x0: f(l, "x0"), y0: f(l, "y0"), x1: f(l, "x1"), y1: f(l, "y1"), name: linkName(l))
  # the connector just arrived at stays bold across a reload (a sync): found again by its label and place
  let old = w.v.linkSel
  var sel = -1
  if old >= 0 and old < w.v.links.len:
    let o = w.v.links[old]
    for i, b in boxes:
      if b.id == o.id and abs(b.x0 - o.x0) < 0.01 and abs(b.y0 - o.y0) < 0.01: sel = i
  w.v.links = boxes
  w.v.linkSel = sel
  w.v.updateOnScreen()     # UI Automation must never see indices into the old list
  w.v.invalidate()

proc goTo(w: Win, label: string, t: JNode) =
  let sheet = s(t, "sheet")
  if not w.m.sheetById(sheet)[0]:     # a window left open while a new publish removed the sheet
    w.toast("Connector " & label & ": that drawing is no longer in the app")
    return
  if sheet != w.sheet: w.showSheet(sheet)
  let (x0, y0, x1, y1) = (f(t, "x0"), f(t, "y0"), f(t, "x1"), f(t, "y1"))
  w.v.linkSel = -1
  for i, b in w.v.links:
    if abs(b.x0 - x0) < 0.01 and abs(b.y0 - y0) < 0.01: w.v.linkSel = i
  w.v.centerOn(x0, y0, x1, y1)
  w.toast("Connector " & label & " on " & (if s(t, "sheet_name").len > 0: s(t, "sheet_name") else: sheet))

proc choiceLabels*(ts: seq[JNode]): seq[string] =
  ## the choice window's buttons, one per target: the sheet's name, numbered when one sheet has the code more than
  ## once (else two identical buttons), with "&" doubled (a button's "&" underlines the letter after it)
  var names: seq[string]
  for t in ts: names.add targetName(t)
  for i, n in names:
    var l = n
    if names.count(n) > 1:
      var k = 0
      for j in 0 .. i:
        if names[j] == n: inc k
      l.add " (" & $k & " of " & $names.count(n) & ")"
    result.add l.replace("&", "&&")

proc followLink*(w: Win, sheet, label: string, x0, y0: float) =
  ## the connector `label` at (x0, y0) of `sheet`. The drawing's circles and the list's rows keep the connector they
  ## show, not an index: a reload in between (a new publish) can reorder them. The list passes the sheet it was built
  ## for: following a link opens another sheet under it, and its rows must still mean the first sheet's.
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
    let (hw, p) = popup(w.hwnd, "Where does " & label & " continue?", 460, 160 + 44 * ts.len, escape = true)
    p.title("Where does " & label & " continue?")
    p.dim("This connector's code appears in more than one place.")
    let names = choiceLabels(ts)
    for j in 0 ..< ts.len:
      closureScope:
        let t = ts[j]
        p.buttons((names[j], proc () =
          DestroyWindow(hw)
          w.goTo(label, t)))
    p.buttons(("Cancel", proc () = DestroyWindow(hw)))
    p.layout()
    ShowWindow(hw, SW_SHOW)

proc onDrawingLink*(w: Win, i: int) =
  ## a connector clicked or invoked on the drawing
  if i < 0 or i >= w.v.links.len: return
  let b = w.v.links[i]
  w.followLink(w.sheet, b.id, b.x0, b.y0)

var connWindow: HWND        ## the open Connectors window (one at a time)

proc openConnectors*(w: Win) =
  ## "Connectors on this sheet": a window for the open sheet, each row named with where it continues
  if connWindow != nil and IsWindow(connWindow) != 0: DestroyWindow(connWindow)   # a new one for the sheet shown now
  let here = w.sheet
  let (ok, si) = w.m.sheetById(here)
  let (hw, p) = popup(w.hwnd, "Connectors on this sheet", 520, 520, proc () = connWindow = nil, escape = true)
  connWindow = hw
  let ls = linksView(w.m, here)
  p.title("Connectors on " & (if ok: si.name else: "this sheet"))
  if ls.len == 0:
    p.dim("No connectors to other drawings on this sheet.")
  else:
    p.dim("Where this sheet's lines continue (the circled codes on the drawing). Enter or double-click a connector " &
          "to go where it continues; Esc closes this window.")
    var keys: seq[(string, float, float)]
    var rows: seq[string]
    for l in ls.elems:
      keys.add (s(l, "label"), f(l, "x0"), f(l, "y0"))
      rows.add linkName(l)
    p.list(rows, 26 * min(12, rows.len) + 6, onActivate = (proc (i: int) =
      if i < keys.len: w.followLink(here, keys[i][0], keys[i][1], keys[i][2])), openLabel = "Go where the selected connector continues")
  p.buttons(("Close", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)
