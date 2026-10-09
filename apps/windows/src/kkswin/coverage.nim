## Coverage: how complete the plant's record is (core views.coverageView; the GNOME app's coverage.nim), in a window of
## its own: totals, then per sheet and per system, each with a bar of the photo coverage colours (named by its numbers
## for screen readers; a list row's text says them too). A sheet row opens that sheet coloured by photos; a system row
## opens Equipment by system filtered to that system. A sync or an approval puts the new numbers into the same controls
## (a list whose rows changed gets its new texts, its selection kept); when sheets or systems came or went, the window
## is rebuilt, never under the focus (win.follow).

import std/[strutils, tables]
import kks/json
import kks/views
import kks/model
import w32, ui, win, systems

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc n(node: JNode, k: string): int =
  if node != nil and node.get(k) != nil and node[k].isInt: int(node[k].i) else: 0

proc pct(a, b: int): string =
  if b == 0: "–" else: $coveragePct(a, b) & " %"   # 100 % only when all, 0 % only when none

proc plural(k: int, one, many: string): string = $k & " " & (if k == 1: one else: many)

const photoKinds = ["both", "equipment", "plate", "none"]

proc coverRgb(i: int): uint32 =
  ## the photo coverage colours, the same on every client (viewer.coverColor): both green, the equipment only amber,
  ## the tag plate only blue, none red
  case i
  of 0: 0x2EA043'u32
  of 1: 0xE69600'u32
  of 2: 0x1E78E6'u32
  else: 0xDC2828'u32

proc photoWords*(p: JNode): string =
  ## the bar's text equivalent: "photos: 2 equipment and tag plate, 1 equipment only, 0 tag plate only, 3 none"
  "photos: " & $n(p, "both") & " equipment and tag plate, " & $n(p, "equipment") & " equipment only, " &
    $n(p, "plate") & " tag plate only, " & $n(p, "none") & " none"

type Counts = array[4, int]

proc counts(p: JNode): Counts =
  for i, k in photoKinds: result[i] = n(p, k)

proc drawBar(dc: HDC, r: RECT, c: Counts) =
  ## a stacked bar of the four colours inside `r`, with a grey frame
  var total = 0
  for x in c: total += x
  let inner = RECT(left: r.left + 1, top: r.top + 1, right: r.right - 1, bottom: r.bottom - 1)
  fillRgb(dc, inner, 0xFFFFFF'u32)     # nothing to count: empty (and no colours left from before)
  if total > 0:
    var x = float(inner.left)
    let wdt = float(inner.right - inner.left)
    for i in 0 ..< 4:
      if c[i] <= 0: continue
      let x1 = x + wdt * float(c[i]) / float(total)
      fillRgb(dc, RECT(left: int32(x), top: inner.top, right: int32(x1 + 0.5), bottom: inner.bottom), coverRgb(i))
      x = x1
  frameRgb(dc, r, 0x999999'u32)

proc totalsText(t: JNode): string =
  plural(n(t, "codes"), "code", "codes") & " on the drawings, in " & plural(n(t, "tags"), "tag", "tags")

proc totalsRows(t: JNode): seq[string] =
  let codes = n(t, "codes")
  let tags = n(t, "tags")
  let p = t["photos"]
  @["Checked by a person: " & $n(t, "verified") & " of " & plural(tags, "tag", "tags") & " (" & pct(n(t, "verified"), tags) & ")",
    "Known place: " & $n(t, "located") & " of " & plural(codes, "code", "codes") & " (" & pct(n(t, "located"), codes) & ")",
    "Photos: both " & $n(p, "both") & " · equipment only " & $n(p, "equipment") & " · tag plate only " & $n(p, "plate") &
      " · none " & $n(p, "none"),
    "Readings to review: " & $n(t, "review"),
    "Missed tags marked: " & $n(t, "marked")]

proc sheetRow(sh: JNode): string =
  result = s(sh, "name") & " · " & plural(n(sh, "codes"), "code", "codes") & " · " & pct(n(sh, "verified"), n(sh, "tags")) &
           " of tags checked · " & pct(n(sh, "located"), n(sh, "codes")) & " placed"
  if n(sh, "review") > 0: result.add " · " & $n(sh, "review") & " to review"
  if n(sh, "marked") > 0: result.add " · " & $n(sh, "marked") & " marked"
  result.add " · " & photoWords(sh["photos"])

proc sysTitle(sy: JNode): string =
  let code = s(sy, "sys")
  let sn = s(sy, "sys_name")
  if code.len == 0: "Codes that don't decode" else: code & (if sn.len > 0: " · " & sn else: "")

proc sysRow(sy: JNode): string =
  sysTitle(sy) & " · " & plural(n(sy, "codes"), "code", "codes") & " · " & pct(n(sy, "verified"), n(sy, "codes")) &
    " of codes checked · " & pct(n(sy, "located"), n(sy, "codes")) & " placed · " & photoWords(sy["photos"])

proc shapeOf(v: JNode): string =
  for sh in v["sheets"].elems: result.add "s\0" & s(sh, "id") & "\0" & s(sh, "name") & "\0"
  for sy in v["systems"].elems: result.add "y\0" & sysTitle(sy) & "\0"

type CovPage = ref object
  ## the controls a sync updates in place
  shape: string
  totals: HWND
  rows: seq[HWND]
  bar: HWND
  barCounts: Counts
  sheetList, sysList: HWND
  sheetRows, sysRows: seq[string]
  sheetCounts, sysCounts: seq[Counts]

var covWindow: HWND          ## the open window (one at a time)

proc openSheetCovered*(w: Win, id: string) =
  ## a sheet row: that sheet, its tags coloured by photos. A hand-marked tag can outlive its sheet: its row is
  ## counted, but there is nothing to open
  if not w.m.sheetById(id)[0]:
    w.toast("That sheet is no longer in the plant data")
    return
  if id != w.sheet: w.showSheet(id)
  w.v.coverage = true
  InvalidateRect(w.v.hwnd, nil, 0)
  w.rebuildSide()              # the sidebar's "Colour tags by photos" shows it on
  w.toast("Tags by photos: green both · amber equipment only · blue tag plate only · red none")

proc rowBar(dc: HDC, r: RECT, c: Counts) =
  let top = r.top + (r.bottom - r.top - px(10)) div 2
  drawBar(dc, RECT(left: r.left + px(6), top: top, right: r.left + px(50), bottom: top + px(10)), c)

proc fillCoverage(w: Win, pg: CovPage, p: Page) =
  p.clear()
  let v = coverageView(w.m)
  pg.shape = shapeOf(v)
  let t = v["total"]
  p.title("Totals")
  pg.totals = p.dim(totalsText(t))
  pg.rows = @[]
  for r in totalsRows(t): pg.rows.add p.label(r)
  pg.barCounts = counts(t["photos"])
  pg.bar = p.picture(photoWords(t["photos"]), 14, proc (dc: HDC, r: RECT, item: int, selected: bool) =
    drawBar(dc, RECT(left: r.left, top: r.top + 1, right: min(r.right, r.left + px(160)), bottom: r.bottom - 1), pg.barCounts))
  p.dim("Photo colours: green both · amber equipment only · blue tag plate only · red none")
  var ids: seq[string]
  pg.sheetCounts = @[]
  pg.sheetRows = @[]
  for sh in v["sheets"].elems:
    ids.add s(sh, "id")
    pg.sheetCounts.add counts(sh["photos"])
    pg.sheetRows.add sheetRow(sh)
  p.title("By sheet")
  p.dim("Open a sheet to see its tags coloured by photos.")
  pg.sheetList = p.pictureList(pg.sheetRows, proc (dc: HDC, r: RECT, item: int, selected: bool) =
    if item < 0 or item >= pg.sheetRows.len: return
    drawRow(dc, r, pg.sheetRows[item], selected, px(58))
    rowBar(dc, r, pg.sheetCounts[item]),
    26 * min(8, max(1, ids.len)) + 6, onActivate = proc (i: int) =
      if i < ids.len: w.openSheetCovered(ids[i]),
    openLabel = "Open the selected sheet coloured by photos")
  var codes: seq[string]
  pg.sysCounts = @[]
  pg.sysRows = @[]
  for sy in v["systems"].elems:
    codes.add s(sy, "sys")
    pg.sysCounts.add counts(sy["photos"])
    pg.sysRows.add sysRow(sy)
  p.title("By system")
  p.dim("Open a system in Equipment by system.")
  pg.sysList = p.pictureList(pg.sysRows, proc (dc: HDC, r: RECT, item: int, selected: bool) =
    if item < 0 or item >= pg.sysRows.len: return
    drawRow(dc, r, pg.sysRows[item], selected, px(58))
    rowBar(dc, r, pg.sysCounts[item]),
    26 * min(12, max(1, codes.len)) + 6, onActivate = proc (i: int) =
      if i < codes.len: w.openSystems(if codes[i].len == 0: OtherCodes else: codes[i]),
    openLabel = "Show the selected system in Equipment by system")
  p.layout()

proc updateCoverage(w: Win, pg: CovPage): bool =
  ## new numbers into the same controls (nothing is replaced under the focus); false if sheets or systems came or went
  let v = coverageView(w.m)
  if shapeOf(v) != pg.shape: return false
  let t = v["total"]
  if pg.totals.text != totalsText(t): pg.totals.setText(totalsText(t))
  for i, r in totalsRows(t):
    if pg.rows[i].text != r: pg.rows[i].setText(r)
  pg.barCounts = counts(t["photos"])
  if pg.bar.text != photoWords(t["photos"]):
    pg.bar.setText(photoWords(t["photos"]))
    InvalidateRect(pg.bar, nil, 1)
  var sheetRows, sysRows: seq[string]
  pg.sheetCounts = @[]
  for sh in v["sheets"].elems:
    sheetRows.add sheetRow(sh)
    pg.sheetCounts.add counts(sh["photos"])
  pg.sysCounts = @[]
  for sy in v["systems"].elems:
    sysRows.add sysRow(sy)
    pg.sysCounts.add counts(sy["photos"])
  # a list whose texts didn't change isn't touched (a screen reader isn't interrupted by every sync); a row's text
  # names its photo numbers, so equal texts mean equal bars
  if sheetRows != pg.sheetRows:
    pg.sheetRows = sheetRows
    updateRows(pg.sheetList, sheetRows)
  if sysRows != pg.sysRows:
    pg.sysRows = sysRows
    updateRows(pg.sysList, sysRows)
  true

proc openCoverage*(w: Win) =
  if covWindow != nil and IsWindow(covWindow) != 0:
    SetForegroundWindow(covWindow)
    return
  let (hw, p) = popup(w.hwnd, "Coverage", 680, 760, proc () = covWindow = nil, escape = true)
  covWindow = hw
  let pg = CovPage()
  w.fillCoverage(pg, p)
  # a sync or an approval: new numbers in place; a rebuild when sheets or systems changed, never under the focus
  discard w.follow(hw, proc () = w.fillCoverage(pg, p), proc (): bool = w.updateCoverage(pg))
  ShowWindow(hw, SW_SHOW)
