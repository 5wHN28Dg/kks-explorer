## Walkdown for Windows (M6 phase 7; decisions 0014, 0027, 0033): Win32 controls + a Direct2D drawing view on the
## Nim core. One thread owns the node: asyncdispatch is pumped from the window's timer.

import std/[asyncdispatch, os, osproc, strutils, tables, sets, times, math, sequtils]
import kks/[json, api, pathstore, views, applink]
import kks/model
import appstate
import kksl/dbstore
import kkswin/[w32, ui, viewer, win, panel, side, manage, setup, learn, multi, photos, links, about]

const
  TimerPump = 1'u
  TimerRefresh = 2'u
  IdmAbout = 0x1010         ## "About Walkdown…" in the window's system menu (below 0xF000, low four bits 0)
  VkF1 = 0x70
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
  syncStarted = false
  refreshTicks = 0

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
  let panelW = if w.selected.len > 0 or w.picking: int(px(PanelW)) else: 0
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
  # the bottom row: the status line, then the photo queue's line and "Photos not sent (n)…" while there are any
  var right = W - int(px(8))
  if w.failedButton != nil:
    let n = failedCount()
    ShowWindow(w.failedButton, if n > 0: SW_SHOW else: SW_HIDE)
    if n > 0:
      let bw = int(px(170))
      right -= bw
      MoveWindow(w.failedButton, int32(right), int32(H - st + int(px(1))), int32(bw), int32(st - int(px(2))), 1)
      right -= int(px(8))
  if w.queueLabel != nil:
    let q = queuedCount() > 0
    ShowWindow(w.queueLabel, if q: SW_SHOW else: SW_HIDE)
    if q:
      let qw = min(int(px(520)), (right - int(px(8))) div 2)
      right -= qw
      MoveWindow(w.queueLabel, int32(right), int32(H - st + int(px(4))), int32(qw), int32(st - int(px(6))), 1)
      right -= int(px(8))
  MoveWindow(w.status, px(8), int32(H - st + int(px(4))), int32(max(10, right - int(px(8)))), int32(st - int(px(6))), 1)

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
  w.setLinks()
  w.syncChosen()
  w.applyHighlights()
  SetWindowTextW(w.hwnd, newWideCString(si.name & " — Walkdown"))

proc doSelectTag(id: string, center: bool) =
  # the tag whose panel is open, opened again (on the drawing, by a screen reader): made again only if nothing typed
  # into it would be lost (win.panelChanged; else it catches up later, as after a sync)
  let again = id.len > 0 and id == w.selected and not w.picking
  if w.picking and id.len > 0:
    # a tag opened from elsewhere (Equipment by system, the review list, a procedure step, Learning) ends the mode;
    # a selection is never dropped without asking (nothing has been sent for it)
    if w.picked.len > 0:
      let owner = if GetActiveWindow() != nil: GetActiveWindow() else: w.hwnd
      let before = w.picked
      let n = before.len
      if not ask(owner, "Leave Select tags?", "Opening this tag ends Select tags: the " &
                 (if n == 1: "selected code is" else: $n & " selected codes are") & " dropped, nothing is sent for them."):
        return
      # the main window stays usable under the question: a selection changed meanwhile wasn't the one asked about
      if w.picking and w.picked != before:
        w.toast("The selection changed: open the tag again to leave Select tags")
        return
    w.stopPicking()
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
  if again: w.panelChanged() else: w.buildPanel(t)
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
    w.setLinks()
    w.syncChosen()
    w.applyHighlights()
  elif w.m.sheets.len > 0: doShowSheet(w.m.sheets[0].id)
  if w.tab != "manage" or liveManage(): w.sideChanged()   # never under the keyboard; typed searches stay (#168)
  w.panelChanged()            # never under the keyboard, or over what was typed into a form (win.panelHeld)
  w.status.setText((if w.lastMsg.len > 0: w.lastMsg & "   ·   " else: "") & syncLine())
  w.refreshFollowers()        # open windows that show the plant's data (Equipment by system), never under the focus

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

proc GetSystemMenu(h: HWND, revert: BOOL): pointer {.importc, stdcall, header: "<windows.h>".}
proc AppendMenuW(m: pointer, flags: UINT, id: uint, text: WideCString): BOOL {.importc, stdcall, header: "<windows.h>", discardable.}

const LinkMagic = 0x4B4B534C'u       ## WM_COPYDATA's dwData for a link ("KKSL")

proc isLinkArg(a: string): bool = a.len <= MaxLinkLen and a.toLowerAscii.startsWith(LinkScheme & ":")

var pendingLink = ""       ## a walkdown:// link that came while a form held typed text, or a dialog was up

proc linkHeld(): bool =
  ## a link waits while the panel holds something typed (win.panelHeld: it would rebuild the panel for another tag
  ## and lose it) or a modal dialog has the main window disabled (a question being asked)
  w.panelHeld(anyFocus = false) or IsWindowEnabled(w.hwnd) == 0

proc takeLink() =
  ## the waiting link, once nothing holds it (from linkArrived, and every second: TimerRefresh)
  if pendingLink.len == 0: return
  if setupP != nil or w.v == nil:
    pendingLink = ""
    return
  if linkHeld(): return
  let link = pendingLink
  pendingLink = ""
  w.openAppLink(link, true)

proc linkArrived(link: string) =
  ## a link from another app (the command line, or handed over): on a device that has joined, opened now or once the
  ## form or dialog that holds it is done (never over what was typed)
  if setupP != nil or w.v == nil: return
  pendingLink = link
  if linkHeld():
    w.toast("A link from another app opens once the form is saved or cancelled")
    if IsIconic(w.hwnd) != 0: ShowWindow(w.hwnd, SW_RESTORE)
    discard SetForegroundWindow(w.hwnd)
  else: later(takeLink)

proc handOver(link: string, running: bool): bool =
  ## Walkdown already runs (`running`: its named mutex was there): the link goes to its main window, and this start
  ## ends (true). MSIX starts a new process for every link; two of them on one store and one sync port would not
  ## work. The window comes a moment after the store and sync have opened (and answers once it is set up), so a
  ## start right after another waits for it, up to 15 s. Not running: false, and this start goes on with the link.
  if not running: return false
  for _ in 0 ..< 60:
    let hw = FindWindowW(newWideCString("KKSMain"), nil)
    if hw != nil:
      var pid: DWORD
      GetWindowThreadProcessId(hw, addr pid)
      AllowSetForegroundWindow(pid)   # (this process was started by the person's click: the window may come forward)
      var data = link
      var cd = COPYDATASTRUCT(dwData: LinkMagic, cbData: DWORD(data.len), lpData: addr data[0])
      var res: uint
      if SendMessageTimeoutW(hw, WM_COPYDATA, 0, cast[LPARAM](addr cd), SMTO_ABORTIFHUNG, 5000, addr res) != 0 and res == 1:
        return true
    sleep(250)
  true        # a Walkdown runs but never took the link: this start ends all the same (not a second one on its store)

proc mainProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  case m
  of 0x0112'u32:              # WM_SYSCOMMAND: the system menu's own item
    if (int(wp) and 0xFFF0) == IdmAbout:
      guard: openAbout(h)
      return 0
  of WM_SIZE:
    if w != nil and w.v != nil or setupP != nil: layoutMain()
    return 0
  of WM_COMMAND:
    if dispatchCommand(wp, lp): return 0
  of WM_TIMER:
    if wp == TimerPump:
      if not syncStarted and w != nil:
        # the listener, the relay and discovery once the window is up (WM_TIMER comes after WM_PAINT)
        syncStarted = true
        guard:
          let port = try: parseInt(getEnv("KKS_SYNC_PORT", $SyncPortDefault)) except ValueError: SyncPortDefault
          w.a.startSync(port, discovery = getEnv("KKS_NO_MDNS").len == 0)
          timing("sync started")
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
      inc refreshTicks
      if refreshTicks mod 30 == 0 and w != nil and not needsRestart:
        guard: w.a.saveState()   # the replayed state, for the next start (when it changed; PROTOCOL-v2 §15b)
      if needsRestart:
        # start over as a fresh process (new device key, the setup screen with the note). Close the store first and
        # leave at once, so the new process never opens a file this one is still closing.
        try: w.a.store.close() except CatchableError: discard
        discard startProcess(getAppFilename(), args = commandLineParams().filterIt(not isLinkArg(it)), options = {poParentStreams})
        quit(0)
      elif changed and setupP == nil and w.v != nil:
        changed = false
        guard: refresh()
      elif w.v != nil and setupP == nil:
        w.status.setText((if w.lastMsg.len > 0: w.lastMsg & "   ·   " else: "") & syncLine())
      if w.v != nil and setupP == nil:
        guard: w.catchUpFollowers()     # a window marked stale under the focus, once the focus has left it
        guard: w.panelCatchUp()         # the panel too, left alone under the keyboard or typed text
        guard: w.sideCatchUp()          # the sidebar, left alone under the keyboard
        guard: takeLink()               # a link that waited for a form or a dialog
    return 0
  of WM_KKS_LATER:
    runLater()
    return 0
  of WM_COPYDATA:
    # a walkdown:// link handed over by a second start (handOver): only its text, at most MaxLinkLen bytes, read by
    # the core like any other (decision 0058)
    let cd = cast[ptr COPYDATASTRUCT](lp)
    if w != nil and cd != nil and cd.dwData == LinkMagic and int(cd.cbData) in 1 .. MaxLinkLen and cd.lpData != nil:
      var link = newString(int(cd.cbData))
      copyMem(addr link[0], cd.lpData, link.len)
      later(proc () = linkArrived(link))
      return 1
    return 0
  of WM_DPICHANGED:
    makeFonts(hiword(int(wp)))
    let r = cast[ptr RECT](lp)
    MoveWindow(h, r.left, r.top, r.right - r.left, r.bottom - r.top, 1)
    return 0
  of WM_CLOSE:
    # photos still waiting are kept on this computer (photos.nim) and sent when Walkdown next starts: say so, and
    # offer to wait for them
    let n = (if w != nil: queuedCount() else: 0)
    let f = (if w != nil: failedCount() else: 0)
    if n + f > 0:
      var what: seq[string]
      if n > 0: what.add(if n == 1: "1 photo is still being prepared" else: $n & " photos are still being prepared")
      if f > 0: what.add(if f == 1: "1 photo was not sent" else: $f & " photos were not sent")
      if not ask(h, "Close Walkdown?", what.join(", and ") & ". " & (if n + f == 1: "It is" else: "They are") &
                 " kept on this computer and sent when Walkdown next starts. Cancel to keep Walkdown open" &
                 (if n > 0: " (the ones being prepared are sent in a moment)" else: "") & ", or OK to close now."):
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
      let (b, _) = control(w.hwnd, "BUTTON", t, WS_TABSTOP or BS_PUSHBUTTON)
      onClick(b, proc () = setTab(tid))
      w.tabButtons.add b
  trace("tabs")
  w.side = newPage(w.hwnd)
  w.v = newViewer(w.hwnd, hinst)
  trace("viewer")
  w.panel = newPage(w.hwnd)
  w.queueLabel = control(w.hwnd, "STATIC", "", SS_LEFT or SS_NOPREFIX)[0]
  let (fb, _) = control(w.hwnd, "BUTTON", "Photos not sent (0)…", WS_TABSTOP or BS_PUSHBUTTON)
  w.failedButton = fb
  onClick(fb, proc () = w.failedWindow())
  w.v.onTag = proc (id: string) =
    if w.picking: w.togglePick(id)       # the select mode (multi.nim)
    elif w.linkProc.len > 0:
      let (ok, t) = w.m.tagById(id)
      if ok and t.full.len > 0:
        discard w.submit("link", newObj(@[("proc", newStr(w.linkProc)), ("step", newInt(w.linkStep)), ("kks", newStr(t.full)),
                         ("on", newBool(true))]), t.full & " → step " & $w.linkStep)
        refresh()
      else: w.toast("This tag has no code yet: check it first")
    else: doSelectTag(id, false)
  w.v.onLink = proc (i: int) = w.onDrawingLink(i)
  w.v.onMark = markDialog
  w.v.onBox = proc (x0, y0, x1, y1: float) = w.addBox(x0, y0, x1, y1)
  w.v.onEscape = proc () = w.stopPicking()
  w.v.setDark(w.a.store.getMeta("dark_drawings") == "1")    # per device (this device's store), like sync_peers
  w.loadModel()
  trace("model: " & $w.m.sheets.len & " sheets, " & $w.m.tags.len & " tags")
  w.rebuildSide()
  trace("side built")
  layoutMain()
  trace("laid out")
  if w.m.sheets.len > 0: doShowSheet(w.m.sheets[0].id)
  trace("sheet shown")
  w.resumePhotos()          # the photos left from before (a crash, a kill, a logout) go first, in their order

proc main() =
  # a walkdown:// link on the command line (MSIX's protocol activation, decision 0058): the first one is taken
  var link = ""
  for p in commandLineParams():
    if isLinkArg(p):
      link = p
      break
  # every start holds the named mutex while it runs: a start with a link finds out from it that Walkdown is starting or
  # running, also before its window is there (the handle is closed when this process ends)
  discard CreateMutexW(nil, 0, newWideCString("Local\\Walkdown-running"))
  let running = GetLastError() == ErrorAlreadyExists
  if link.len > 0 and handOver(link, running): quit(0)
  SetProcessDpiAwarenessContext(-4)        # per-monitor v2
  var icc = CommonControlsInit(dwSize: DWORD(sizeof(CommonControlsInit)), dwICC: 0xFFFF)
  InitCommonControlsEx(addr icc)
  hinst = GetModuleHandleW(nil)
  makeFonts(96)
  createDir(dataDir())
  errorLog = dataDir() / "crash.log"
  timing("main")
  # the store opens and the log replays on a thread of its own while the window is made (decision 0061)
  discard openAppInBackground(kksTables = BuiltInTables)
  let clsName = newWideCString("KKSMain")   # must outlive RegisterClassExW
  var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: mainProc, hInstance: hinst,
                       hCursor: LoadCursorW(nil, IDC_ARROW), hbrBackground: GetSysColorBrush(COLOR_WINDOW),
                       lpszClassName: clsName)
  discard RegisterClassExW(addr wc)
  let hw = CreateWindowExW(WS_EX_CONTROLPARENT, newWideCString("KKSMain"), newWideCString("Walkdown"),
                           WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, 1280, 820, nil, nil, hinst, nil)
  makeFonts(int(GetDpiForWindow(hw)))
  laterWindow = hw
  let sysMenu = GetSystemMenu(hw, 0)          # About in the window's system menu (Alt+Space, the icon's menu)
  if sysMenu != nil:
    AppendMenuW(sysMenu, 0x0800, 0, nil)      # MF_SEPARATOR
    AppendMenuW(sysMenu, 0, uint(IdmAbout), newWideCString("About Walkdown…"))
  timing("window made")
  let a = openedApp()
  timing("app open")
  errorHook = proc (text: string) = a.diag("error", text)
  a.onChange.add proc (why: string) =
    if why == "wiped":
      photosWiped(a.store)      # the wipe deleted the queued photos: nothing more is written or sent
      needsRestart = true
    elif why != "relay": changed = true   # presence only: the status line catches up on its timer
  w = Win(a: a, hwnd: hw, tab: "drawings")
  w.status = control(hw, "STATIC", "", SS_LEFT or SS_NOPREFIX)[0]
  onError = proc (msg: string) = w.toast("Something went wrong: " & msg)
  w.showSheet = doShowSheet
  w.selectTag = doSelectTag
  w.rebuildSide = proc () =
    w.sideStale = false
    w.sideUpdate = nil          # the page that is made sets its own
    w.sidePicked = nil
    w.sideRepick = nil
    if w.tab == "learning":
      w.side.clear()
      w.learningTab(w.side)
      w.side.layout()
    else: w.buildSide(proc (p: Page) = w.manageTab(p))
  w.rebuildPanel = proc () =
    w.panelStale = false
    if w.picking: w.pickPanel(w.panel)
    else:
      let (ok, t) = w.m.tagById(w.selected)
      if ok: w.buildPanel(t)
  w.relayout = layoutMain
  # tests only (#162): while the file named by KKS_TEST_STALE_CLICK exists, the panel is rebuilt between a button's
  # click and its handler. Without the variable nothing changes.
  let staleFile = getEnv("KKS_TEST_STALE_CLICK")
  if staleFile.len > 0:
    beforeHandler = proc () =
      if w.v != nil and setupP == nil and fileExists(staleFile): later(proc () = w.rebuildPanel())
  if a.joined:
    showMain()
    if link.len > 0: later(proc () = linkArrived(link))
  else:
    setupP = newPage(hw)
    w.buildSetup(setupP, proc () =
      setupPage = ""
      showMain())
  layoutMain()
  ShowWindow(hw, SW_SHOW)
  UpdateWindow(hw)
  timing("window shown")
  SetTimer(hw, TimerPump, 30, nil)        # (its first tick starts the sync service: after the first paint)
  SetTimer(hw, TimerRefresh, 1000, nil)
  var msg: MSG
  var lastFocus: HWND
  while GetMessageW(addr msg, nil, 0, 0) > 0:
    if msg.message == WM_KEYDOWN and int(msg.wParam) == VK_RETURN and activateFocused(): continue
    if msg.message == WM_KEYDOWN and int(msg.wParam) == VkF1:     # F1 anywhere in the app: About (help's usual key)
      guard: openAbout(w.hwnd)
      continue
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
  if not needsRestart: w.a.saveState()

main()
