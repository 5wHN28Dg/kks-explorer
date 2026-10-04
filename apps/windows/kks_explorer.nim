## Walkdown for Windows (M6 phase 7; decisions 0014, 0027, 0033): Win32 controls + a Direct2D drawing view on the
## Nim core. One thread owns the node: asyncdispatch is pumped from the window's timer.

import std/[asyncdispatch, os, osproc, strutils, tables, sets, times, math]
import kks/[json, api, pathstore, views]
import kks/model
import appstate
import kksl/dbstore
import kkswin/[w32, ui, viewer, win, panel, side, manage, setup, learn]

const
  TimerPump = 1'u
  TimerRefresh = 2'u
  TabH = 44
  SideW = 380
  PanelW = 420
  StatusH = 28

var
  w: Win
  setupP: Page
  changed = false
  needsRestart = false
  t0 = epochTime()
  firstSheetShown = false

proc showMain()

proc layoutMain() =
  var r: RECT
  GetClientRect(w.hwnd, addr r)
  let W = int(r.right)
  let H = int(r.bottom)
  if setupP != nil:
    MoveWindow(setupP.hwnd, 0, 0, int32(W), int32(H), 1)
    return
  let side = int(px(SideW))
  let panelW = if w.selected.len > 0: int(px(PanelW)) else: 0
  let st = int(px(StatusH))
  var x = 0
  for b in w.tabButtons:
    let bw = int(px(92))
    MoveWindow(b, int32(x + int(px(4))), px(6), int32(bw - int(px(4))), px(32), 1)
    x += bw
  MoveWindow(w.side.hwnd, 0, px(TabH), int32(side), int32(H - int(px(TabH)) - st), 1)
  MoveWindow(w.v.hwnd, int32(side), 0, int32(max(10, W - side - panelW)), int32(H - st), 1)
  MoveWindow(w.panel.hwnd, int32(W - panelW), 0, int32(panelW), int32(H - st), 1)
  ShowWindow(w.panel.hwnd, if panelW > 0: SW_SHOW else: SW_HIDE)
  MoveWindow(w.status, px(8), int32(H - st + int(px(4))), int32(W - int(px(16))), int32(st - int(px(6))), 1)

proc doShowSheet(id: string) =
  let (ok, si) = w.m.sheetById(id)
  if not ok: return
  w.sheet = id
  var flatBytes = ""
  let (okK, kkp) = w.a.file("sheets/" & id & ".kkp")
  if okK:
    try: flatBytes = flat(pathstore.decode(kkp))
    except CatchableError as e: w.toast("This sheet's drawing can't be read: " & e.msg)
  w.v.levelData = proc (k: int): string =
    let (okL, d) = w.a.file("sheets/" & id & ".o" & $k & ".jxl")
    if okL: d else: ""
  w.v.setSheet(id, flatBytes, si.scale, si.levels)
  w.v.tags = w.tagBoxes(id)
  w.applyHighlights()
  SetWindowTextW(w.hwnd, newWideCString(si.name & " — Walkdown"))

proc doSelectTag(id: string, center: bool) =
  w.selected = id
  w.v.selected = id
  if id.len == 0:
    layoutMain()
    w.v.invalidate()
    return
  let (ok, t) = w.m.tagById(id)
  if not ok: return
  if t.sheet != w.sheet: doShowSheet(t.sheet)
  w.v.selected = id
  layoutMain()
  if center:
    let (okS, si) = w.m.sheetById(t.sheet)
    let s = if okS and si.scale > 0: si.scale else: 2.0
    w.v.centerOn(t.bbox[0] / s, t.bbox[1] / s, t.bbox[2] / s, t.bbox[3] / s)
  w.buildPanel(t)
  w.v.invalidate()

proc syncLine(): string =
  let snap = w.a.snapshot
  if w.a.syncing: return "Syncing…"
  result = if snap["last_ok"].kind == jInt: "Last sync " & fromUnix(snap["last_ok"].i).local.format("HH:mm") else: "Not synced yet"
  if snap["relay"].s == "online":
    let n = snap["relay_online"].i
    result.add " · internet: " & (if n == 1: "1 device" else: $n & " devices") & " online"
    case snap["relay_how"].s
    of "direct": result.add ", last sync direct"
    of "relay": result.add ", last sync through the relay"
    else: discard

proc refresh() =
  ## the data changed underneath (a sync, an approval): reload, keep the open sheet and selection (R20)
  w.loadModel()
  if w.sheet.len > 0:
    w.v.tags = w.tagBoxes(w.sheet)
    w.applyHighlights()
  elif w.m.sheets.len > 0: doShowSheet(w.m.sheets[0].id)
  let f = GetFocus()
  let typing = f != nil and GetParent(f) == w.side.hwnd and w.tab == "drawings"
  if not typing and (w.tab != "manage" or liveManage()): w.rebuildSide()
  if w.selected.len > 0:
    let (ok, t) = w.m.tagById(w.selected)
    if ok and GetParent(GetFocus()) != w.panel.hwnd: w.buildPanel(t)
  w.status.setText((if w.lastMsg.len > 0: w.lastMsg & "   ·   " else: "") & syncLine())

proc setTab(t: string) =
  w.tab = t
  managePage = ""
  w.rebuildSide()

proc markDialog(x0, y0, x1, y1: float) =
  let (ok, si) = w.m.sheetById(w.sheet)
  let sc = if ok and si.scale > 0: si.scale else: 2.0
  if (x1 - x0) * sc < 8 or (y1 - y0) * sc < 8:
    w.toast("Box too small: drag across the whole tag")
    return
  let sheet = w.sheet
  var hw: HWND
  let (h, p) = popup(w.hwnd, "Mark a missing tag", 460, 420)
  hw = h
  p.dim("Type the code if you can read it. If not, leave it empty: the mark goes to the review queue.")
  let code = p.field("KKS (with suffix, optional)", "")
  let isa = p.field("Function letters (instruments, optional)", "")
  let note = p.field("Note (optional)", "")
  p.buttons(("Propose", proc () =
    let bb = newArr(@[newFloat(round(x0 * sc * 10) / 10), newFloat(round(y0 * sc * 10) / 10),
                      newFloat(round(x1 * sc * 10) / 10), newFloat(round(y1 * sc * 10) / 10)])
    let k = code.text.strip.toUpperAscii
    if w.submit("tag_add", newObj(@[("sheet", newStr(sheet)), ("bbox", bb), ("kks", newStr(k)),
                ("isa", newStr(isa.text.strip.toUpperAscii)), ("note", newStr(note.text.strip))]),
                if k.len > 0: k else: "an unread tag").len > 0:
      w.v.marking = false
      DestroyWindow(hw)
      refresh()), ("Cancel", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)

proc mainProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  case m
  of WM_SIZE:
    if w != nil and w.v != nil or setupP != nil: layoutMain()
    return 0
  of WM_COMMAND:
    if dispatchCommand(wp, lp): return 0
  of WM_TIMER:
    if wp == TimerPump:
      guard:
        if hasPendingOperations(): poll(0)
      guard:
        if w.v != nil: w.v.poll()
      if w.v != nil and not firstSheetShown and w.v.hasOverview():
        firstSheetShown = true
        if getEnv("KKS_TIMING").len > 0:      # docs/m6/MEASUREMENTS.md: start → first overview drawn
          let f = open(dataDir() / "timing.log", fmAppend)
          f.writeLine("first sheet " & $int((epochTime() - t0) * 1000) & " ms after start")
          f.close()
    elif wp == TimerRefresh:
      if needsRestart:
        # start over as a fresh process (new device key, the setup screen with the note). Close the store first and
        # leave at once, so the new process never opens a file this one is still closing.
        try: w.a.store.close() except CatchableError: discard
        discard startProcess(getAppFilename(), args = commandLineParams(), options = {poParentStreams})
        quit(0)
      elif changed and setupP == nil and w.v != nil:
        changed = false
        guard: refresh()
      elif w.v != nil and setupP == nil:
        w.status.setText((if w.lastMsg.len > 0: w.lastMsg & "   ·   " else: "") & syncLine())
    return 0
  of WM_KKS_LATER:
    runLater()
    return 0
  of WM_DPICHANGED:
    makeFonts(hiword(int(wp)))
    let r = cast[ptr RECT](lp)
    MoveWindow(h, r.left, r.top, r.right - r.left, r.bottom - r.top, 1)
    return 0
  of WM_DESTROY:
    PostQuitMessage(0)
    return 0
  else: discard
  DefWindowProcW(h, m, wp, lp)

proc showMain() =
  trace("showMain")
  if setupP != nil:
    setupP.destroy()
    setupP = nil
  trace("setup destroyed")
  const tabs = [("Drawings", "drawings"), ("Procedures", "procedures"), ("Review", "review"), ("Learning", "learning"),
                ("Manage", "manage")]
  for ti in 0 ..< tabs.len:
    closureScope:
      let t = tabs[ti][0]
      let tid = tabs[ti][1]
      let (b, bid) = control(w.hwnd, "BUTTON", t, WS_TABSTOP or BS_PUSHBUTTON)
      onClick(bid, proc () = setTab(tid))
      w.tabButtons.add b
  trace("tabs")
  w.side = newPage(w.hwnd)
  w.v = newViewer(w.hwnd, hinst)
  trace("viewer")
  w.panel = newPage(w.hwnd)
  w.v.onTag = proc (id: string) =
    if w.linkProc.len > 0:
      let (ok, t) = w.m.tagById(id)
      if ok and t.full.len > 0:
        discard w.submit("link", newObj(@[("proc", newStr(w.linkProc)), ("step", newInt(w.linkStep)), ("kks", newStr(t.full)),
                         ("on", newBool(true))]), t.full & " → step " & $w.linkStep)
        refresh()
      else: w.toast("This tag has no code yet: check it first")
    else: doSelectTag(id, false)
  w.v.onMark = markDialog
  w.loadModel()
  trace("model: " & $w.m.sheets.len & " sheets, " & $w.m.tags.len & " tags")
  w.rebuildSide()
  trace("side built")
  layoutMain()
  trace("laid out")
  if w.m.sheets.len > 0: doShowSheet(w.m.sheets[0].id)
  trace("sheet shown")

proc main() =
  SetProcessDpiAwarenessContext(-4)        # per-monitor v2
  var icc = CommonControlsInit(dwSize: DWORD(sizeof(CommonControlsInit)), dwICC: 0xFFFF)
  InitCommonControlsEx(addr icc)
  hinst = GetModuleHandleW(nil)
  makeFonts(96)
  createDir(dataDir())
  errorLog = dataDir() / "crash.log"
  let a = openApp()
  errorHook = proc (text: string) = a.diag("error", text)
  let port = try: parseInt(getEnv("KKS_SYNC_PORT", $SyncPortDefault)) except ValueError: SyncPortDefault
  a.startSync(port, discovery = getEnv("KKS_NO_MDNS").len == 0)
  a.onChange.add proc (why: string) =
    if why == "wiped": needsRestart = true
    elif why != "relay": changed = true   # presence only: the status line catches up on its timer
  let clsName = newWideCString("KKSMain")   # must outlive RegisterClassExW
  var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: mainProc, hInstance: hinst,
                       hCursor: LoadCursorW(nil, IDC_ARROW), hbrBackground: GetSysColorBrush(COLOR_WINDOW),
                       lpszClassName: clsName)
  discard RegisterClassExW(addr wc)
  let hw = CreateWindowExW(WS_EX_CONTROLPARENT, newWideCString("KKSMain"), newWideCString("Walkdown"),
                           WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, 1280, 820, nil, nil, hinst, nil)
  makeFonts(int(GetDpiForWindow(hw)))
  laterWindow = hw
  w = Win(a: a, hwnd: hw, tab: "drawings")
  w.status = control(hw, "STATIC", "", SS_LEFT or SS_NOPREFIX)[0]
  onError = proc (msg: string) = w.toast("Something went wrong: " & msg)
  w.showSheet = doShowSheet
  w.selectTag = doSelectTag
  w.rebuildSide = proc () =
    if w.tab == "learning":
      w.side.clear()
      w.learningTab(w.side)
      w.side.layout()
    else: w.buildSide(proc (p: Page) = w.manageTab(p))
  w.rebuildPanel = proc () =
    let (ok, t) = w.m.tagById(w.selected)
    if ok: w.buildPanel(t)
  w.relayout = layoutMain
  if a.joined: showMain()
  else:
    setupP = newPage(hw)
    w.buildSetup(setupP, proc () =
      setupPage = ""
      showMain())
  layoutMain()
  ShowWindow(hw, SW_SHOW)
  UpdateWindow(hw)
  SetTimer(hw, TimerPump, 30, nil)
  SetTimer(hw, TimerRefresh, 1000, nil)
  var msg: MSG
  var lastFocus: HWND
  while GetMessageW(addr msg, nil, 0, 0) > 0:
    if msg.message == WM_KEYDOWN and int(msg.wParam) == VK_RETURN and activateFocused(): continue
    if msg.message == WM_MOUSEWHEEL and wheelToPage(msg.hwnd, msg.wParam, msg.lParam): continue
    let root = GetAncestor(msg.hwnd, 2)          # GA_ROOT: the main window or a popup
    if root != nil and IsDialogMessageW(root, addr msg) != 0:
      let f = GetFocus()
      if f != lastFocus:
        lastFocus = f
        showFocused()
      continue
    TranslateMessage(addr msg)
    DispatchMessageW(addr msg)
    let f = GetFocus()
    if f != lastFocus:
      lastFocus = f
      showFocused()

main()
