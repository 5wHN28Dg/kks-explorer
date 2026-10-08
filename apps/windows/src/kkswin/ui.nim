## A small layout layer over Win32 controls (decision 0033): a scrollable Page stacks labels, fields, buttons and lists
## vertically, like the GNOME app's preference groups. Standard controls carry UI Automation; a field's name is the
## label created just before it (MSAA/UIA name from the preceding static text). Tab moves through a page
## (WS_EX_CONTROLPARENT + IsDialogMessage in the message loop).

import std/[tables, strutils, os]
import w32

const HG = "<windows.h>"
type SIZE {.importc, header: HG.} = object
  cx, cy: int32
proc GetDC(h: HWND): HDC {.importc, stdcall, header: HG.}
proc ReleaseDC(h: HWND, dc: HDC): int32 {.importc, stdcall, header: HG, discardable.}
proc SelectObject(dc: HDC, o: HGDIOBJ): HGDIOBJ {.importc, stdcall, header: HG, discardable.}
proc DrawTextW(dc: HDC, s: WideCString, n: int32, r: ptr RECT, f: UINT): int32 {.importc, stdcall, header: HG.}
const DT_CALCRECT = 0x400'u32
const DT_WORDBREAK = 0x10'u32
const DT_NOPREFIX = 0x800'u32

var
  hinst*: HINSTANCE
  fontNormal*, fontTitle*, fontSmall*: HFONT
  dpi* = 96
  nextId = 1000
  clicks = initTable[int, proc ()]()
  changes = initTable[int, proc ()]()
  selects = initTable[int, proc (i: int)]()
  activates = initTable[int, proc (i: int)]()
  notifies = initTable[HWND, proc (code: UINT, l: LPARAM): bool]()   ## WM_NOTIFY from a control (tree views)
  enters = initTable[HWND, proc ()]()                               ## Enter on a focused control that isn't a list

proc px*(v: int): int32 = int32(v * dpi div 96)

var errorLog* = ""          ## file for errors caught at the Win32 boundary (set by the app: <data dir>/crash.log)
var onError*: proc (msg: string)
var errorHook*: proc (text: string)   ## the app's diagnostics (decision 0040): every caught error, with its trace

proc report*(e: ref Exception) =
  ## an exception must never unwind through a Win32 callback (the GNOME app's lesson): log it and carry on
  let msg = $e.name & ": " & e.msg & "\n" & e.getStackTrace()
  if errorLog.len > 0:
    try:
      let f = open(errorLog, fmAppend)
      f.writeLine("---- " & msg)
      f.close()
    except IOError: discard
  if onError != nil:
    try: onError(e.msg) except CatchableError: discard
  if errorHook != nil:
    try: errorHook(msg) except CatchableError: discard

proc trace*(msg: string) =
  ## breadcrumbs for crashes outside Nim (KKS_TRACE=1): appended to <data dir>/trace.log
  if errorLog.len > 0 and getEnv("KKS_TRACE").len > 0:
    try:
      let f = open(errorLog.parentDir / "trace.log", fmAppend)
      f.writeLine(msg)
      f.close()
    except IOError: discard

template guard*(body: untyped) =
  try: body
  except CatchableError as e: report(e)

proc makeFonts*(d: int) =
  dpi = d
  var m: NONCLIENTMETRICSW
  m.cbSize = UINT(sizeof(m))
  SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, UINT(sizeof(m)), addr m, 0)
  var lf = m.lfMessageFont
  lf.lfHeight = -px(15)
  for f in [fontNormal, fontTitle, fontSmall]:
    if f != nil: DeleteObject(f)
  fontNormal = CreateFontIndirectW(addr lf)
  lf.lfHeight = -px(20)
  lf.lfWeight = 600
  fontTitle = CreateFontIndirectW(addr lf)
  lf.lfHeight = -px(13)
  lf.lfWeight = 400
  fontSmall = CreateFontIndirectW(addr lf)

proc newId(): int =
  inc nextId
  nextId

proc control*(parent: HWND, cls, text: string, style: uint32, ex = 0'u32, font: HFONT = nil): (HWND, int) =
  let id = newId()
  let h = CreateWindowExW(ex, newWideCString(cls), newWideCString(text), WS_CHILD or WS_VISIBLE or style, 0, 0, 10, 10,
                          parent, cast[HMENU](id), hinst, nil)
  SendMessageW(h, WM_SETFONT, cast[WPARAM](if font != nil: font else: fontNormal), 1)
  (h, id)

proc onClick*(id: int, f: proc ()) = clicks[id] = f
proc onSelectList*(id: int, f: proc (i: int)) = selects[id] = f
proc onActivateList*(id: int, f: proc (i: int)) = activates[id] = f
proc onNotify*(h: HWND, f: proc (code: UINT, l: LPARAM): bool) =
  ## WM_NOTIFY from this control reaches f (in the notification: queue real work with `later`); true = handled
  notifies[h] = f
proc onEnter*(h: HWND, f: proc ()) =
  ## Enter while this control has the focus runs f (after the key's message, like a list's activation)
  enters[h] = f

proc dispatchCommand0(w: WPARAM, l: LPARAM): bool

# Handlers run after the control's notification has returned: a handler may destroy the page holding the control
# (Join → the main screen), and comctl32 keeps using the button after it notified us (an access violation, found on
# Windows 10). The same lesson as the GNOME app's idle handlers.
const WM_KKS_LATER* = WM_APP + 1
var laterWindow*: HWND          ## the main window, which runs the queue on WM_KKS_LATER
var laterQueue: seq[proc ()]

var timers = initTable[uint, proc ()]()

proc timerProc(h: HWND, m: UINT, id: uint, t: DWORD) {.stdcall.} =
  KillTimer(nil, id)
  if id in timers:
    let f = timers[id]
    timers.del id
    try: f()
    except CatchableError as e: report(e)

proc afterMs*(ms: int, f: proc ()): uint =
  ## run f once, ms from now, on the UI thread (a thread timer); -> its id for cancel
  result = SetTimer(nil, 0, UINT(ms), cast[pointer](timerProc))
  if result != 0: timers[result] = f

proc cancel*(id: uint) =
  if id != 0 and id in timers:
    KillTimer(nil, id)
    timers.del id

proc later*(f: proc ()) =
  laterQueue.add f
  PostMessageW(laterWindow, WM_KKS_LATER, 0, 0)

proc runLater*() =
  ## (on WM_KKS_LATER) run what was queued, each guarded
  let q = laterQueue
  laterQueue.setLen(0)
  for f in q:
    try: f()
    except CatchableError as e: report(e)

proc dispatchCommand*(w: WPARAM, l: LPARAM): bool =
  ## WM_COMMAND from any control: run its handler (errors are reported, never thrown). -> true if handled
  try:
    return dispatchCommand0(w, l)
  except CatchableError as e:
    report(e)
    return true

proc dispatchCommand0(w: WPARAM, l: LPARAM): bool =
  let id = loword(int(w))
  let code = uint32(hiword(int(w)))
  if code == BN_CLICKED and id in clicks:
    later(clicks[id])
    return true
  if code == EN_CHANGE and id in changes:
    changes[id]()
    return true
  if code == LBN_SELCHANGE and id in selects:
    let i = int(SendMessageW(cast[HWND](l), LB_GETCURSEL, 0, 0))
    let f = selects[id]
    if i >= 0: later(proc () = f(i))
    return true
  if code == LBN_DBLCLK and id in activates:
    let i = int(SendMessageW(cast[HWND](l), LB_GETCURSEL, 0, 0))
    let f = activates[id]
    if i >= 0: later(proc () = f(i))
    return true
  false

proc forget*(ids: seq[int]) =
  for id in ids:
    clicks.del id
    changes.del id
    selects.del id
    activates.del id

# ---------------------------------------------------------------- a page

type
  ItemKind = enum ikLabel, ikTitle, ikDim, ikField, ikMulti, ikButtons, ikList, ikCheck, ikSpace, ikCustom, ikRich, ikTall, ikAspect, ikFill
  Item = object
    kind: ItemKind
    hwnds: seq[HWND]
    height: int          ## for lists, multi-line fields, custom
    natW, natH: int      ## ikAspect: natural size (DIPs)
    text: string         ## for labels (height is measured)
  Page* = ref object
    hwnd*: HWND
    items: seq[Item]
    ids: seq[int]
    scroll: int
    contentH: int

var pages = initTable[HWND, Page]()

# ---------------------------------------------------------------- rich text (courses, decision 0036)
# A read-only RichEdit 4.1 per run of text: RTF in, its height from EN_REQUESTRESIZE, links (CFE_LINK on ranges we
# found ourselves) reported through EN_LINK to the page's link handler.
type
  CHARRANGE {.importc, header: "<richedit.h>".} = object
    cpMin, cpMax: int32
  FINDTEXTEXW {.importc, header: "<richedit.h>".} = object
    chrg: CHARRANGE
    lpstrText: WideCString
    chrgText: CHARRANGE
  CHARFORMAT2W {.importc, header: "<richedit.h>".} = object
    cbSize: UINT
    dwMask: DWORD
    dwEffects: DWORD
  SETTEXTEX {.importc, header: "<richedit.h>".} = object
    flags: DWORD
    codepage: UINT
  NMHDR {.importc, header: HG.} = object
    hwndFrom: HWND
    idFrom: uint
    code: UINT
  ReqResizeMsg {.importc: "REQRESIZE", header: "<richedit.h>".} = object
    nmhdr: NMHDR
    rc: RECT
  EnLinkMsg {.importc: "ENLINK", header: "<richedit.h>".} = object
    nmhdr: NMHDR
    msg: UINT
    wParam: WPARAM
    lParam: LPARAM
    chrg: CHARRANGE
proc LoadLibraryW(name: WideCString): pointer {.importc, stdcall, header: HG.}
var
  EM_SETEVENTMASK {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_REQUESTRESIZE {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_SETTEXTEX {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_FINDTEXTEXW {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_EXSETSEL {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_SETCHARFORMAT {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_SETBKGNDCOLOR {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_AUTOURLDETECT {.importc, header: "<richedit.h>", nodecl.}: UINT
  ENM_REQUESTRESIZE {.importc, header: "<richedit.h>", nodecl.}: uint32
  ENM_LINK {.importc, header: "<richedit.h>", nodecl.}: uint32
  EN_REQUESTRESIZE {.importc, header: "<richedit.h>", nodecl.}: UINT
  EN_LINK {.importc, header: "<richedit.h>", nodecl.}: UINT
  CFM_LINK {.importc, header: "<richedit.h>", nodecl.}: DWORD
  CFE_LINK {.importc, header: "<richedit.h>", nodecl.}: DWORD
  SCF_SELECTION {.importc, header: "<richedit.h>", nodecl.}: WPARAM
  FR_DOWN {.importc, header: "<richedit.h>", nodecl.}: WPARAM
  BS_MULTILINE {.importc, header: HG, nodecl.}: uint32
  BS_LEFT {.importc, header: HG, nodecl.}: uint32
  WM_LBUTTONUP {.importc, header: HG, nodecl.}: UINT
  colorWindowIdx {.importc: "COLOR_WINDOW", header: HG, nodecl.}: cint
proc GetSysColor(i: cint): DWORD {.importc, stdcall, header: HG.}
var
  TBM_GETPOS* {.importc, header: "<commctrl.h>", nodecl.}: UINT
  TBM_SETPOS* {.importc, header: "<commctrl.h>", nodecl.}: UINT
  TBM_SETRANGEMAX {.importc, header: "<commctrl.h>", nodecl.}: UINT
  TBS_HORZ {.importc, header: "<commctrl.h>", nodecl.}: uint32
  BS_AUTORADIOBUTTON* {.importc, header: HG, nodecl.}: uint32
  tracks = initTable[HWND, proc (v: float)]()
var
  richH = initTable[HWND, int]()                       ## measured content height (px) per RichEdit
  richLinks = initTable[HWND, seq[(int32, int32, string)]]()
  relayoutWanted = false
  onLink*: proc (target: string)                       ## set by the screen that shows rich text

proc measure(p: Page, text: string, font: HFONT, width: int): int =
  let dc = GetDC(p.hwnd)
  SelectObject(dc, font)
  var r = RECT(left: 0, top: 0, right: int32(width), bottom: 0)
  discard DrawTextW(dc, newWideCString(if text.len == 0: " " else: text), -1, addr r, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX)
  ReleaseDC(p.hwnd, dc)
  int(r.bottom - r.top)

proc textWidth(p: Page, text: string, font: HFONT): int =
  let dc = GetDC(p.hwnd)
  SelectObject(dc, font)
  var r = RECT(left: 0, top: 0, right: 0, bottom: 0)
  discard DrawTextW(dc, newWideCString(if text.len == 0: " " else: text), -1, addr r, DT_CALCRECT or DT_NOPREFIX)
  ReleaseDC(p.hwnd, dc)
  int(r.right - r.left)

proc layout*(p: Page) =
  var r: RECT
  GetClientRect(p.hwnd, addr r)
  let w = int(r.right) - 2 * px(16)
  var y = px(12) - p.scroll
  let x = px(16)
  for it in p.items:
    case it.kind
    of ikLabel, ikTitle, ikDim:
      let f = (if it.kind == ikTitle: fontTitle elif it.kind == ikDim: fontSmall else: fontNormal)
      let h = p.measure(it.text, f, w)
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), int32(h), 1)
      y += h + px(if it.kind == ikTitle: 8 else: 6)
    of ikField:
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), px(20), 1)
      MoveWindow(it.hwnds[1], x, int32(y + px(20)), int32(w), px(28), 1)
      y += px(56)
    of ikMulti:
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), px(20), 1)
      MoveWindow(it.hwnds[1], x, int32(y + px(20)), int32(w), px(it.height), 1)
      y += px(it.height) + px(28)
    of ikButtons:
      var bx = int(x)
      for b in it.hwnds:
        let bw = max(int(px(90)), p.textWidth(b.text, fontNormal) + int(px(28)))
        if bx > int(x) and bx + bw > int(x) + w:        # wrap to the next line
          bx = int(x)
          y += px(38)
        MoveWindow(b, int32(bx), int32(y), int32(min(bw, w)), px(30), 1)
        bx += bw + int(px(8))
      y += px(40)
    of ikCheck:
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), px(26), 1)
      y += px(32)
    of ikList:
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), px(it.height), 1)
      y += px(it.height) + px(10)
    of ikSpace:
      y += px(it.height)
    of ikFill:
      let h = max(int(px(it.height)), int(r.bottom) - y - int(px(24)))   # the page's margins: no scroll bar
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), int32(h), 1)
      y += h
    of ikCustom:
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), px(it.height), 1)
      y += px(it.height) + px(10)
    of ikAspect:
      let aw = min(w, int(px(it.natW)))
      MoveWindow(it.hwnds[0], x + int32((w - aw) div 2), int32(y), int32(aw), int32(aw * it.natH div it.natW), 1)
      y += aw * it.natH div it.natW + px(6)
    of ikRich:
      let h0 = richH.getOrDefault(it.hwnds[0], px(20))
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), int32(h0), 1)
      SendMessageW(it.hwnds[0], EM_REQUESTRESIZE, 0, 0)    # EN_REQUESTRESIZE may change richH (another pass follows)
      y += richH.getOrDefault(it.hwnds[0], h0) + px(6)
    of ikTall:
      var bx = int(x)
      for b in it.hwnds:
        let th = p.measure(b.text, fontNormal, w - int(px(28))) + int(px(16))
        MoveWindow(b, int32(bx), int32(y), int32(w), int32(max(int(px(32)), th)), 1)
        y += max(int(px(32)), th) + px(6)
  p.contentH = y + p.scroll + px(12)
  var si = SCROLLINFO(cbSize: UINT(sizeof(SCROLLINFO)), fMask: SIF_ALL, nMin: 0, nMax: int32(p.contentH),
                      nPage: UINT(r.bottom), nPos: int32(p.scroll))
  SetScrollInfo(p.hwnd, SB_VERT, addr si, 1)

proc relayoutIfWanted(p: Page) =
  if relayoutWanted:
    relayoutWanted = false
    p.layout()
    relayoutWanted = false

proc scrollTo*(p: Page, pos: int) =
  var r: RECT
  GetClientRect(p.hwnd, addr r)
  let np = max(0, min(pos, p.contentH - int(r.bottom)))
  if np != p.scroll:
    p.scroll = np
    p.layout()
    InvalidateRect(p.hwnd, nil, 1)

proc pageProc(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT {.stdcall.} =
  let p = pages.getOrDefault(h)
  case m
  of WM_COMMAND:
    if dispatchCommand(w, l): return 0
    return SendMessageW(GetParent(h), m, w, l)     # unknown: to the parent
  of WM_SIZE:
    if p != nil:
      p.layout()
      p.relayoutIfWanted()
    return 0
  of WM_NOTIFY:
    let hdr = cast[ptr NMHDR](l)
    if hdr.code == EN_REQUESTRESIZE:
      let rr = cast[ptr ReqResizeMsg](l)
      let hh = int(rr.rc.bottom - rr.rc.top)
      if richH.getOrDefault(hdr.hwndFrom, -1) != hh:
        richH[hdr.hwndFrom] = hh
        relayoutWanted = true
        if p != nil: later(proc () = p.relayoutIfWanted())
      return 0
    if hdr.hwndFrom in notifies:
      try:
        if notifies[hdr.hwndFrom](hdr.code, l): return 0
      except CatchableError as e: report(e)
    if hdr.code == EN_LINK:
      let el = cast[ptr EnLinkMsg](l)
      if el.msg == WM_LBUTTONUP or (el.msg == WM_KEYDOWN and el.wParam == 0x0D):
        for (a, b, t) in richLinks.getOrDefault(hdr.hwndFrom):
          if el.chrg.cpMin >= a and el.chrg.cpMin < b:
            let target = t
            if onLink != nil: later(proc () = onLink(target))
            return 1
      return 0
  of WM_HSCROLL:
    if l != 0 and cast[HWND](l) in tracks:
      let tb = cast[HWND](l)
      tracks[tb](float(SendMessageW(tb, TBM_GETPOS, 0, 0)) / 1000)
      return 0
  of WM_VSCROLL:
    if p != nil:
      var si = SCROLLINFO(cbSize: UINT(sizeof(SCROLLINFO)), fMask: SIF_ALL)
      GetScrollInfo(h, SB_VERT, addr si)
      case loword(int(w))
      of SB_LINEUP: p.scrollTo(p.scroll - px(30))
      of SB_LINEDOWN: p.scrollTo(p.scroll + px(30))
      of SB_PAGEUP: p.scrollTo(p.scroll - int(si.nPage))
      of SB_PAGEDOWN: p.scrollTo(p.scroll + int(si.nPage))
      of SB_THUMBTRACK, SB_THUMBPOSITION: p.scrollTo(int(si.nTrackPos))
      else: discard
    return 0
  of WM_MOUSEWHEEL:
    if p != nil: p.scrollTo(p.scroll - int(shiword(int(w))) * px(60) div 120)
    return 0
  of WM_KEYDOWN:
    if p != nil:
      var r: RECT
      GetClientRect(h, addr r)
      case int(w)
      of 0x22: p.scrollTo(p.scroll + int(r.bottom) - int(px(40)))     # Page Down
      of 0x21: p.scrollTo(p.scroll - int(r.bottom) + int(px(40)))     # Page Up
      of 0x28: p.scrollTo(p.scroll + int(px(40)))                     # Down
      of 0x26: p.scrollTo(p.scroll - int(px(40)))                     # Up
      of 0x24: p.scrollTo(0)                                         # Home
      of 0x23: p.scrollTo(p.contentH)                                # End
      else: discard
    return 0
  of WM_CTLCOLORSTATIC:
    return cast[LRESULT](GetSysColorBrush(COLOR_WINDOW))
  of WM_DESTROY:
    if p != nil:
      forget(p.ids)
      for it in p.items:
        if it.kind == ikRich:
          richH.del it.hwnds[0]
          richLinks.del it.hwnds[0]
        for c in it.hwnds:
          notifies.del c
          enters.del c
      pages.del h
  else: discard
  DefWindowProcW(h, m, w, l)

var pageClassDone = false

proc newPage*(parent: HWND): Page =
  if not pageClassDone:
    let clsName = newWideCString("KKSPage")   # must outlive RegisterClassExW
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: pageProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_ARROW), hbrBackground: GetSysColorBrush(COLOR_WINDOW),
                         lpszClassName: clsName)
    discard RegisterClassExW(addr wc)
    pageClassDone = true
  result = Page()
  result.hwnd = CreateWindowExW(WS_EX_CONTROLPARENT, newWideCString("KKSPage"), newWideCString(""),
                                WS_CHILD or WS_VISIBLE or WS_VSCROLL or WS_CLIPCHILDREN, 0, 0, 10, 10, parent, nil, hinst, nil)
  pages[result.hwnd] = result

proc destroy*(p: Page) =
  if p != nil and p.hwnd != nil:
    DestroyWindow(p.hwnd)
    p.hwnd = nil

proc clear*(p: Page) =
  ## remove every control (the page is rebuilt)
  for it in p.items:
    for h in it.hwnds:
      notifies.del h
      enters.del h
      DestroyWindow(h)
  forget(p.ids)
  p.items.setLen(0)
  p.ids.setLen(0)
  p.scroll = 0

proc keep(p: Page, r: (HWND, int)): HWND =
  p.ids.add r[1]
  r[0]

proc label*(p: Page, text: string): HWND {.discardable.} =
  result = p.keep(control(p.hwnd, "STATIC", text, SS_LEFT or SS_NOPREFIX or SS_EDITCONTROL))
  p.items.add Item(kind: ikLabel, hwnds: @[result], text: text)

proc title*(p: Page, text: string): HWND {.discardable.} =
  result = p.keep(control(p.hwnd, "STATIC", text, SS_LEFT or SS_NOPREFIX, font = fontTitle))
  p.items.add Item(kind: ikTitle, hwnds: @[result], text: text)

proc dim*(p: Page, text: string): HWND {.discardable.} =
  result = p.keep(control(p.hwnd, "STATIC", text, SS_LEFT or SS_NOPREFIX or SS_EDITCONTROL, font = fontSmall))
  p.items.add Item(kind: ikDim, hwnds: @[result], text: text)

proc field*(p: Page, name, value: string, password = false, readonly = false, onChange: proc () = nil): HWND {.discardable.} =
  let lab = p.keep(control(p.hwnd, "STATIC", name, SS_LEFT or SS_NOPREFIX))
  let (e, id) = control(p.hwnd, "EDIT", value, WS_TABSTOP or ES_AUTOHSCROLL or (if password: ES_PASSWORD else: 0) or
                        (if readonly: ES_READONLY else: 0), WS_EX_CLIENTEDGE)
  p.ids.add id
  if onChange != nil: changes[id] = onChange
  p.items.add Item(kind: ikField, hwnds: @[lab, e])
  e

proc multiField*(p: Page, name, value: string, height = 90, readonly = false): HWND {.discardable.} =
  let lab = p.keep(control(p.hwnd, "STATIC", name, SS_LEFT or SS_NOPREFIX))
  result = p.keep(control(p.hwnd, "EDIT", value.replace("\n", "\r\n"), WS_TABSTOP or WS_VSCROLL or ES_MULTILINE or
                          ES_AUTOVSCROLL or ES_WANTRETURN or (if readonly: ES_READONLY else: 0), WS_EX_CLIENTEDGE))
  p.items.add Item(kind: ikMulti, hwnds: @[lab, result], height: height)

proc toSpec*[F](x: (string, F)): (string, proc ()) =
  ## lambdas that capture nothing are nimcall and a tuple doesn't convert by itself: wrap them as closures.
  ## A lambda that only calls a nested closure proc (`proc () = open()`) must say `{.closure.}`: Nim 2.2.12 types it
  ## nimcall here, makes it a closure later, and this instance then copies its environment without counting the
  ## reference (freed once too often when the buttons go: heap corruption, crashes anywhere later; Windows 11)
  let f = x[1]
  (x[0], proc () = f())

proc buttons*(p: Page, specs: varargs[(string, proc ()), toSpec]): seq[HWND] {.discardable.} =
  for (t, f) in specs:
    let (b, id) = control(p.hwnd, "BUTTON", t, WS_TABSTOP or BS_PUSHBUTTON)
    p.ids.add id
    clicks[id] = f
    result.add b
  p.items.add Item(kind: ikButtons, hwnds: result)

proc check*(p: Page, text: string, on: bool, f: proc (on: bool)): HWND {.discardable.} =
  let (b, id) = control(p.hwnd, "BUTTON", text, WS_TABSTOP or BS_AUTOCHECKBOX)
  p.ids.add id
  SendMessageW(b, BM_SETCHECK, WPARAM(ord(on)), 0)
  clicks[id] = proc () = f(SendMessageW(b, BM_GETCHECK, 0, 0) == 1)
  p.items.add Item(kind: ikCheck, hwnds: @[b])
  b

proc list*(p: Page, rows: seq[string], height = 200, onSelect: proc (i: int) = nil,
           onActivate: proc (i: int) = nil, openLabel = ""): HWND {.discardable.} =
  ## onActivate runs on double-click and Enter; with openLabel, also from a button below the list (a list item has
  ## no Invoke for UI Automation, and a button is reachable the same way for every user)
  let (l, id) = control(p.hwnd, "LISTBOX", "", WS_TABSTOP or WS_VSCROLL or LBS_NOTIFY or LBS_NOINTEGRALHEIGHT, WS_EX_CLIENTEDGE)
  p.ids.add id
  for r in rows: sendText(l, LB_ADDSTRING, 0, r)
  if onSelect != nil: selects[id] = onSelect
  if onActivate != nil: activates[id] = onActivate
  p.items.add Item(kind: ikList, hwnds: @[l], height: height)
  if onActivate != nil and openLabel.len > 0:
    let (b, bid) = control(p.hwnd, "BUTTON", openLabel, WS_TABSTOP or BS_PUSHBUTTON)
    p.ids.add bid
    clicks[bid] = proc () =
      let i = int(SendMessageW(l, LB_GETCURSEL, 0, 0))
      if i >= 0: onActivate(i)
    p.items.add Item(kind: ikButtons, hwnds: @[b])
  l

proc space*(p: Page, h = 12) = p.items.add Item(kind: ikSpace, height: h)

var richLoaded = false
proc rich*(p: Page, rtf: string, links: seq[(string, string)] = @[]): HWND {.discardable.} =
  ## read-only rich text from RTF (ASCII, non-ASCII as \uN?); `links` = (display text, target) in reading order: each
  ## is found after the previous one and marked as a link
  if not richLoaded:
    discard LoadLibraryW(newWideCString("Msftedit.dll"))
    richLoaded = true
  result = p.keep(control(p.hwnd, "RICHEDIT50W", "", WS_TABSTOP or ES_MULTILINE or ES_READONLY))
  SendMessageW(result, EM_SETBKGNDCOLOR, 0, LPARAM(GetSysColor(colorWindowIdx)))
  SendMessageW(result, EM_AUTOURLDETECT, 0, 0)
  var st = SETTEXTEX(flags: 0, codepage: 65001)
  let raw = rtf & "\0"
  SendMessageW(result, EM_SETTEXTEX, cast[WPARAM](addr st), cast[LPARAM](cstring(raw)))
  var found: seq[(int32, int32, string)]
  var from0 = 0'i32
  for (text, target) in links:
    let wt = newWideCString(text)
    var ft = FINDTEXTEXW(chrg: CHARRANGE(cpMin: from0, cpMax: -1), lpstrText: wt)
    if SendMessageW(result, EM_FINDTEXTEXW, FR_DOWN, cast[LPARAM](addr ft)) >= 0:
      var cr = ft.chrgText
      SendMessageW(result, EM_EXSETSEL, 0, cast[LPARAM](addr cr))
      var cf = CHARFORMAT2W(cbSize: UINT(sizeof(CHARFORMAT2W)), dwMask: CFM_LINK, dwEffects: CFE_LINK)
      SendMessageW(result, EM_SETCHARFORMAT, SCF_SELECTION, cast[LPARAM](addr cf))
      found.add (cr.cpMin, cr.cpMax, target)
      from0 = cr.cpMax
  var none = CHARRANGE(cpMin: 0, cpMax: 0)
  SendMessageW(result, EM_EXSETSEL, 0, cast[LPARAM](addr none))
  richLinks[result] = found
  SendMessageW(result, EM_SETEVENTMASK, 0, LPARAM(ENM_REQUESTRESIZE or ENM_LINK))
  p.items.add Item(kind: ikRich, hwnds: @[result])

proc tallButtons*(p: Page, specs: seq[(string, proc ())]): seq[HWND] {.discardable.} =
  ## full-width buttons whose text wraps (answer options)
  for (t, f) in specs:
    let (b, id) = control(p.hwnd, "BUTTON", t, WS_TABSTOP or BS_PUSHBUTTON or BS_MULTILINE or BS_LEFT)
    p.ids.add id
    clicks[id] = f
    result.add b
  p.items.add Item(kind: ikTall, hwnds: result)

proc scroll*(p: Page): int = p.scroll

proc showFocused*() =
  ## keyboard users: Tab to a control below or above the visible part of a page scrolls it into view
  let f = GetFocus()
  if f == nil: return
  let pg = pages.getOrDefault(GetParent(f))
  if pg == nil: return
  var r, pr: RECT
  if GetWindowRect(f, addr r) == 0 or GetWindowRect(pg.hwnd, addr pr) == 0: return
  if r.top < pr.top: pg.scrollTo(pg.scroll - int(pr.top - r.top) - int(px(12)))
  elif r.bottom > pr.bottom: pg.scrollTo(pg.scroll + int(r.bottom - pr.bottom) + int(px(12)))

proc wheelToPage*(h: HWND, w: WPARAM, l: LPARAM): bool =
  ## the wheel over read-only text (RichEdit) scrolls the page it sits in (other children pass it up by themselves)
  if h notin richH: return false
  let pg = pages.getOrDefault(GetParent(h))
  if pg == nil: return false
  SendMessageW(pg.hwnd, WM_MOUSEWHEEL, w, l)
  true

proc aspect*(p: Page, h: HWND, natW, natH: int) =
  ## a child drawn at its natural size (DIPs) when the page is wide enough, else scaled down to the page width
  p.items.add Item(kind: ikAspect, hwnds: @[h], natW: natW, natH: natH)

proc slider*(p: Page, name: string, value: float, f: proc (v: float)): HWND {.discardable.} =
  ## a trackbar 0–1 (steps of 0.001) under its label; its UIA name is the label before it
  discard p.label(name)
  result = p.keep(control(p.hwnd, "msctls_trackbar32", name, WS_TABSTOP or TBS_HORZ))
  SendMessageW(result, TBM_SETRANGEMAX, 1, 1000)
  SendMessageW(result, TBM_SETPOS, 1, LPARAM(int(value * 1000)))
  tracks[result] = f
  p.items.add Item(kind: ikCustom, hwnds: @[result], height: 30)

proc radios*(p: Page, labels: seq[string], selected: int, f: proc (i: int)): seq[HWND] {.discardable.} =
  ## a radio group (one item per row)
  var res: seq[HWND]
  for i in 0 ..< labels.len:
    closureScope:
      let idx = i
      let (b, id) = control(p.hwnd, "BUTTON", labels[i], WS_TABSTOP or BS_AUTORADIOBUTTON or (if i == 0: WS_GROUP else: 0))
      p.ids.add id
      SendMessageW(b, BM_SETCHECK, WPARAM(ord(i == selected)), 0)
      clicks[id] = proc () = f(idx)
      p.items.add Item(kind: ikCheck, hwnds: @[b])
      res.add b
  res

proc custom*(p: Page, h: HWND, height: int) =
  p.items.add Item(kind: ikCustom, hwnds: @[h], height: height)

proc fill*(p: Page, h: HWND, minHeight: int) =
  ## a child that takes the rest of the page's height (at least minHeight DIPs): put it last
  p.items.add Item(kind: ikFill, hwnds: @[h], height: minHeight)

proc setRows*(l: HWND, rows: seq[string]) =
  SendMessageW(l, LB_RESETCONTENT, 0, 0)
  for r in rows: sendText(l, LB_ADDSTRING, 0, r)

proc ask*(owner: HWND, title, text: string): bool =
  MessageBoxW(owner, newWideCString(text), newWideCString(title), MB_OKCANCEL or MB_ICONQUESTION) == IDOK

proc say*(owner: HWND, title, text: string) =
  discard MessageBoxW(owner, newWideCString(text), newWideCString(title), MB_OK)

proc openFile*(owner: HWND, title, filter: string): string =
  ## filter like "Bundles|*.kksbundle|All files|*.*"
  var buf = newWideCString("", 1024)
  let f = newWideCString(filter.replace('|', '\0') & "\0\0")
  let t = newWideCString(title)        # the strings must outlive the call (temporaries in the struct would dangle)
  var o = OPENFILENAMEW(lStructSize: DWORD(sizeof(OPENFILENAMEW)), hwndOwner: owner, lpstrFilter: f,
                        lpstrFile: buf, nMaxFile: 1024, lpstrTitle: t, Flags: OFN_FILEMUSTEXIST or OFN_EXPLORER)
  if GetOpenFileNameW(addr o) != 0: $buf else: ""

proc saveFile*(owner: HWND, title, filter, suggested, ext: string): string =
  var buf = newWideCString(suggested, 1024)
  let f = newWideCString(filter.replace('|', '\0') & "\0\0")
  let t = newWideCString(title)
  let e = newWideCString(ext)
  var o = OPENFILENAMEW(lStructSize: DWORD(sizeof(OPENFILENAMEW)), hwndOwner: owner, lpstrFilter: f,
                        lpstrFile: buf, nMaxFile: 1024, lpstrTitle: t, Flags: OFN_OVERWRITEPROMPT or OFN_EXPLORER,
                        lpstrDefExt: e)
  if GetSaveFileNameW(addr o) != 0: $buf else: ""

proc GetDlgCtrlID(h: HWND): int32 {.importc, stdcall, header: HG.}

proc activateFocused*(): bool =
  ## Enter on a focused list opens its item (the keyboard equivalent of a double-click)
  let f = GetFocus()
  if f == nil: return false
  if f in enters:
    later(enters[f])
    return true
  let id = int(GetDlgCtrlID(f))
  if id notin activates: return false
  let i = int(SendMessageW(f, LB_GETCURSEL, 0, 0))
  let g = activates[id]
  if i >= 0: later(proc () = g(i))
  true

# ---------------------------------------------------------------- a popup window hosting a page

var popups = initTable[HWND, (Page, proc ())]()
var escCloses: seq[HWND]      ## popups that Escape closes (IsDialogMessage turns it into IDCANCEL)

proc popupProc(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT {.stdcall.} =
  case m
  of WM_SIZE:
    if h in popups: MoveWindow(popups[h][0].hwnd, 0, 0, int32(loword(l)), int32(hiword(l)), 1)
    return 0
  of WM_COMMAND:
    if loword(int(w)) == 2 and l == 0 and h in escCloses:     # IDCANCEL: Escape
      PostMessageW(h, WM_CLOSE, 0, 0)
      return 0
    if dispatchCommand(w, l): return 0
  of WM_DESTROY:
    let i = escCloses.find(h)
    if i >= 0: escCloses.del i
    if h in popups:
      let onClose = popups[h][1]
      popups.del h
      if onClose != nil: onClose()
    return 0
  else: discard
  DefWindowProcW(h, m, w, l)

var popupClassDone = false

proc popup*(owner: HWND, title: string, w, h: int, onClose: proc () = nil, escape = false): (HWND, Page) =
  ## a separate window (an invite, a dialog-like form) with one page; closing it calls onClose; with `escape`,
  ## the Escape key closes it too
  if not popupClassDone:
    let clsName = newWideCString("KKSPopup")   # must outlive RegisterClassExW
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: popupProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_ARROW), hbrBackground: GetSysColorBrush(COLOR_WINDOW),
                         lpszClassName: clsName)
    discard RegisterClassExW(addr wc)
    popupClassDone = true
  let hw = CreateWindowExW(WS_EX_CONTROLPARENT, newWideCString("KKSPopup"), newWideCString(title), WS_OVERLAPPEDWINDOW,
                           CW_USEDEFAULT, CW_USEDEFAULT, px(w), px(h), owner, nil, hinst, nil)
  let p = newPage(hw)
  popups[hw] = (p, onClose)
  if escape: escCloses.add hw
  var r: RECT
  GetClientRect(hw, addr r)
  MoveWindow(p.hwnd, 0, 0, r.right, r.bottom, 1)
  (hw, p)
