## A small layout layer over Win32 controls (decision 0033): a scrollable Page stacks labels, fields, buttons and lists
## vertically, like the GNOME app's preference groups. Standard controls carry UI Automation; a field's name is the
## label created just before it (MSAA/UIA name from the preceding static text). Tab moves through a page
## (WS_EX_CONTROLPARENT + IsDialogMessage in the message loop).

import std/[tables, strutils, os, math]
from syncwords import uxOn
import w32, labels, theme

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

# owner-drawn controls (a list whose rows start with a small picture, a picture named by its text): the page asks the
# control's draw proc (onOwnerDraw) for WM_DRAWITEM
type
  DRAWITEMSTRUCT {.importc, header: HG.} = object
    CtlType, CtlID, itemID, itemAction, itemState: UINT
    hwndItem: HWND
    hDC: HDC
    rcItem: RECT
    itemData: uint
  MEASUREITEMSTRUCT {.importc, header: HG.} = object
    CtlType, CtlID, itemID, itemWidth, itemHeight: UINT
    itemData: uint
  HBRUSH0 = pointer
proc CreateSolidBrush(c: DWORD): HBRUSH0 {.importc, stdcall, header: HG.}
proc DeleteObject(o: pointer): int32 {.importc, stdcall, header: HG, discardable.}
proc FillRect(dc: HDC, r: ptr RECT, b: HBRUSH0): int32 {.importc, stdcall, header: HG, discardable.}
proc FrameRect(dc: HDC, r: ptr RECT, b: HBRUSH0): int32 {.importc, stdcall, header: HG, discardable.}
proc DrawFocusRect(dc: HDC, r: ptr RECT): int32 {.importc, stdcall, header: HG, discardable.}
proc SetTextColor(dc: HDC, c: DWORD): DWORD {.importc, stdcall, header: HG, discardable.}
proc SetBkMode(dc: HDC, m: int32): int32 {.importc, stdcall, header: HG, discardable.}
const
  WM_DRAWITEM = 0x002B'u32
  WM_MEASUREITEM = 0x002C'u32
  ODS_SELECTED = 0x0001'u32
  ODS_FOCUS = 0x0010'u32
  SS_OWNERDRAW = 0x000D'u32
  LBS_OWNERDRAWFIXED = 0x0010'u32
  LBS_HASSTRINGS = 0x0040'u32
  DT_SINGLELINE = 0x20'u32
  DT_VCENTER = 0x4'u32
  DT_END_ELLIPSIS = 0x8000'u32
  COLOR_HIGHLIGHT = 13'i32
  COLOR_HIGHLIGHTTEXT = 14'i32
  COLOR_WINDOWTEXT = 8'i32

type OwnerDraw* = proc (dc: HDC, r: RECT, item: int, selected: bool)
var ownerDraws = initTable[HWND, OwnerDraw]()

proc fillRgb*(dc: HDC, r: RECT, rgb: uint32) =
  var rr = r
  let b = CreateSolidBrush(colorRef(rgb))
  FillRect(dc, addr rr, b)
  DeleteObject(b)

proc frameRgb*(dc: HDC, r: RECT, rgb: uint32) =
  var rr = r
  let b = CreateSolidBrush(colorRef(rgb))
  FrameRect(dc, addr rr, b)
  DeleteObject(b)

var
  hinst*: HINSTANCE
  fontNormal*, fontTitle*, fontSmall*: HFONT
  dpi* = 96
  nextId = 1000
  notifies = initTable[HWND, proc (code: UINT, l: LPARAM): bool]()   ## WM_NOTIFY from a control (tree views)

# A control's handlers are kept by its window handle, which WM_COMMAND carries, never by its control id: the id in
# WM_COMMAND is 16 bits, and a new id is used for every control of every rebuilt page (#162). After 64,535 controls
# a new button's click arrived under the id of a control made at the start: it did nothing, or ran that one's
# handler, a tab's button for instance. (An estimate from the number of controls in the side and the panel: about a
# day of sync rounds with a tag open.)
# The Ctl object is the registration: a rebuilt page's controls have new ones, so a handler queued for a control that
# has gone since (`deferred`) finds another object, or none, and does nothing.
type Ctl = ref object
  click, change, enter: proc ()
  select, activate: proc (i: int)
var ctls = initTable[HWND, Ctl]()

proc ctl(h: HWND): Ctl =
  result = ctls.getOrDefault(h)
  if result == nil:
    result = Ctl()
    ctls[h] = result

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

# ---- text size (#377): Windows' "Text size" (Settings → Accessibility), behind the switch win-text-size (KKS_UX).
# Settings writes TextScaleFactor (100–225, what UISettings.TextScaleFactor reads) and scales the system's fonts (the
# message font: 9 pt, 12 px at 96 dpi, at 100 %); the larger of the two is followed. Off: 1, the app as released.
const TextSizeSwitch* = "win-text-size"

var textScale* = 1.0        ## the app's text, and the heights made for it, times this (tx)

proc RegGetValueTs(key: pointer, sub, value: WideCString, flags: uint32, typ: ptr uint32, data: pointer,
                   size: ptr uint32): int32 {.importc: "RegGetValueW", stdcall, header: HG.}
proc SystemParametersInfoForDpi(a, b: UINT, p: pointer, f, d: UINT): BOOL {.importc, stdcall, header: HG.}

proc systemTextScale*(): float =
  ## Windows' text size now, 1 to 2.25 (KKS_TEST_TEXT_SCALE stands in for it in the tests); 1 with the switch off
  if not uxOn(TextSizeSwitch): return 1.0
  let t = getEnv("KKS_TEST_TEXT_SCALE")
  if t.len > 0:
    try: return clamp(parseFloat(t), 1.0, 2.25) except ValueError: discard
  var v: uint32 = 100
  var n = uint32(sizeof(v))
  let hkcu = cast[pointer](0x80000001'u)       # HKEY_CURRENT_USER
  if RegGetValueTs(hkcu, newWideCString("Software\\Microsoft\\Accessibility"), newWideCString("TextScaleFactor"),
                   0x10'u32, nil, addr v, addr n) != 0: v = 100       # RRF_RT_REG_DWORD; absent: 100 %
  result = float(v) / 100
  var m: NONCLIENTMETRICSW
  m.cbSize = UINT(sizeof(m))
  if SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, UINT(sizeof(m)), addr m, 0, 96) != 0 and m.lfMessageFont.lfHeight < 0:
    result = max(result, float(-m.lfMessageFont.lfHeight) / 12)
  result = clamp(result, 1.0, 2.25)

proc tx*(v: int): int32 =
  ## a size made for text (a field's or button's height, a list's rows): `v` DIPs at this DPI and text size (px at 100 %)
  px(int(round(float(v) * textScale)))

proc txp*(text, fixed: int): int32 =
  ## `text` DIPs that grow with the text size plus `fixed` DIPs that don't, at this DPI (px(text + fixed) at 100 %)
  px(int(round(float(text) * textScale)) + fixed)

type
  WNDENUMPROC = proc (h: HWND, l: LPARAM): BOOL {.stdcall.}
proc EnumThreadWindows(t: DWORD, f: WNDENUMPROC, l: LPARAM): BOOL {.importc, stdcall, header: HG, discardable.}
proc EnumChildWindows(h: HWND, f: WNDENUMPROC, l: LPARAM): BOOL {.importc, stdcall, header: HG, discardable.}
proc GetCurrentThreadId(): DWORD {.importc, stdcall, header: HG.}
var refont: seq[(HFONT, HFONT)]
proc refontOne(h: HWND, l: LPARAM): BOOL {.stdcall.} =
  let f = cast[HFONT](SendMessageW(h, WM_SETFONT + 1, 0, 0))       # WM_GETFONT
  for (a, b) in refont:
    if f == a and a != nil:
      SendMessageW(h, WM_SETFONT, cast[WPARAM](b), 1)
      break
  1
proc refontTop(h: HWND, l: LPARAM): BOOL {.stdcall.} =
  discard refontOne(h, l)
  EnumChildWindows(h, refontOne, l)
  1

var afterFonts*: seq[proc ()]    ## after new fonts (scale or text size changed): pages laid out again, lists' rows

proc makeFonts*(d: int) =
  ## the app's fonts for this DPI and text size; the controls that show the old ones take the new ones (a status line
  ## kept the old scale's font after a scale change while the app ran, #377), and every page is laid out again
  dpi = d
  var m: NONCLIENTMETRICSW
  m.cbSize = UINT(sizeof(m))
  SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, UINT(sizeof(m)), addr m, 0)
  var lf = m.lfMessageFont
  let old = [fontNormal, fontTitle, fontSmall]
  lf.lfHeight = -tx(15)
  fontNormal = CreateFontIndirectW(addr lf)
  lf.lfHeight = -tx(20)
  lf.lfWeight = 600
  fontTitle = CreateFontIndirectW(addr lf)
  lf.lfHeight = -tx(13)
  lf.lfWeight = 400
  fontSmall = CreateFontIndirectW(addr lf)
  if old[0] != nil:
    refont = @[(old[0], fontNormal), (old[1], fontTitle), (old[2], fontSmall)]
    EnumThreadWindows(GetCurrentThreadId(), refontTop, 0)
    refont.setLen(0)
    for f in afterFonts:
      try: f() except CatchableError as e: report(e)
  for f in old:
    if f != nil: DeleteObject(f)

proc refreshTextScale*(): bool =
  ## Windows' text size changed (WM_SETTINGCHANGE, or read once a second): the fonts and pages follow. -> it changed
  let s = systemTextScale()
  if abs(s - textScale) < 0.001: return false
  textScale = s
  makeFonts(dpi)
  true

proc newId(): int =
  ## a control id: what GetDlgCtrlID and UI Automation's AutomationId say, 16 bits like the id in WM_COMMAND. Nothing
  ## here looks a control up by it, so the ids may repeat once they have gone round
  nextId = if nextId >= 0xFFFF: 1001 else: nextId + 1
  nextId

var groupEnds = false
  ## set by `radios`: the next control made starts a group of its own (WS_GROUP). Without it the radios' group runs on
  ## through the controls after them, and an arrow key on one of those moves to a radio and chooses it

proc control*(parent: HWND, cls, text: string, style: uint32, ex = 0'u32, font: HFONT = nil): (HWND, int) =
  let id = newId()
  let style = if groupEnds and (style and WS_GROUP) == 0: style or WS_GROUP else: style
  groupEnds = false
  let shown = if cls == "BUTTON": buttonLabel(text) else: text      # a button's "&" is the character (labels.nim)
  let h = CreateWindowExW(ex, newWideCString(cls), newWideCString(shown), WS_CHILD or WS_VISIBLE or style, 0, 0, 10, 10,
                          parent, cast[HMENU](id), hinst, nil)
  SendMessageW(h, WM_SETFONT, cast[WPARAM](if font != nil: font else: fontNormal), 1)
  themeContainer(parent)      # (the switch win-dark-ui: the parent paints its controls in the theme's colours)
  themeControl(h)
  ctls.del h      # (a window handle used again for a new control never brings an old control's handlers with it)
  (h, id)

proc onClick*(h: HWND, f: proc ()) = ctl(h).click = f
proc onSelectList*(h: HWND, f: proc (i: int)) = ctl(h).select = f
proc onActivateList*(h: HWND, f: proc (i: int)) = ctl(h).activate = f
proc onNotify*(h: HWND, f: proc (code: UINT, l: LPARAM): bool) =
  ## WM_NOTIFY from this control reaches f (in the notification: queue real work with `later`); true = handled
  notifies[h] = f
proc onEnter*(h: HWND, f: proc ()) =
  ## Enter while this control has the focus runs f (after the key's message, like a list's activation)
  ctl(h).enter = f

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

var beforeHandler*: proc ()
  ## tests only (the app's KKS_TEST_STALE_CLICK): runs when a button's click arrives, before its handler is queued, so
  ## that what it queues with `later` comes between the click and the handler

proc deferred(h: HWND, c: Ctl, run: proc (c: Ctl)) =
  ## `run` after the control's notification has returned (see above), and only if the control is still there by then.
  ## Something else can run in between and rebuild its page: a handler queued before it (two presses that arrived as
  ## sent messages, as UI Automation's Invoke does, are both queued before the first runs; multi.nim met this), or a
  ## message posted earlier (a tag invoked by a screen reader). The handler would then act for a page that has gone:
  ## its fields read as empty, so an edit form's Save sent every field as cleared (#162). It does nothing instead;
  ## the page now on screen has its own controls and handlers.
  later(proc () =
    if ctls.getOrDefault(h) == c and IsWindow(h) != 0: run(c))

proc dispatchCommand0(w: WPARAM, l: LPARAM): bool =
  let h = cast[HWND](l)
  if h == nil: return false           # a menu or accelerator id, not a control
  let c = ctls.getOrDefault(h)
  if c == nil: return false
  let code = uint32(hiword(int(w)))
  if code == BN_CLICKED and c.click != nil:
    if beforeHandler != nil: beforeHandler()
    deferred(h, c, proc (c: Ctl) = c.click())
    return true
  if code == EN_CHANGE and c.change != nil:
    c.change()
    return true
  if code == LBN_SELCHANGE and c.select != nil:
    let i = int(SendMessageW(h, LB_GETCURSEL, 0, 0))
    if i >= 0: deferred(h, c, proc (c: Ctl) = c.select(i))
    return true
  if code == LBN_DBLCLK and c.activate != nil:
    let i = int(SendMessageW(h, LB_GETCURSEL, 0, 0))
    if i >= 0: deferred(h, c, proc (c: Ctl) = c.activate(i))
    return true
  false

# ---------------------------------------------------------------- a page

type
  ItemKind = enum ikLabel, ikTitle, ikDim, ikField, ikMulti, ikButtons, ikList, ikCheck, ikSpace, ikCustom, ikRich, ikTall, ikAspect, ikFill
  Item = object
    kind: ItemKind
    hwnds: seq[HWND]
    height: int          ## for lists, multi-line fields, custom
    natW, natH: int      ## ikAspect: natural size (DIPs)
    right: bool          ## ikButtons: at the right (a dialog's)
    text: string         ## for labels (height is measured)
  Typed = object                ## a field a person can type into
    h: HWND
    name: string                ## its label (what the person reads)
    key: string                 ## what it holds: its label, or a key of its own (a custom field's name)
    was: string                 ## the text it was made with
    secret: bool                ## a password: never kept across a rebuild, never shown
  Page* = ref object
    hwnd*: HWND
    items: seq[Item]
    typed: seq[Typed]
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
  EM_SETTYPOGRAPHYOPTIONS {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_GETLANGOPTIONS {.importc, header: "<richedit.h>", nodecl.}: UINT
  EM_SETLANGOPTIONS {.importc, header: "<richedit.h>", nodecl.}: UINT
  TO_ADVANCEDTYPOGRAPHY {.importc, header: "<richedit.h>", nodecl.}: WPARAM
  IMF_AUTOFONT {.importc, header: "<richedit.h>", nodecl.}: int
  ENM_REQUESTRESIZE {.importc, header: "<richedit.h>", nodecl.}: uint32
  ENM_LINK {.importc, header: "<richedit.h>", nodecl.}: uint32
  EN_REQUESTRESIZE {.importc, header: "<richedit.h>", nodecl.}: UINT
  EN_LINK {.importc, header: "<richedit.h>", nodecl.}: UINT
  CFM_LINK {.importc, header: "<richedit.h>", nodecl.}: DWORD
  CFE_LINK {.importc, header: "<richedit.h>", nodecl.}: DWORD
  SCF_SELECTION {.importc, header: "<richedit.h>", nodecl.}: WPARAM
  FR_DOWN {.importc, header: "<commdlg.h>", nodecl.}: WPARAM
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

var listRows = initTable[HWND, seq[string]]()     ## each list's rows as last put in (updateRows compares)

proc forgetControl*(h: HWND) =
  ## the control is going (its page is rebuilt or closed, its window destroyed): nothing queued for it runs any more
  ctls.del h
  notifies.del h
  listRows.del h
  ownerDraws.del h
  tracks.del h
  richH.del h
  richLinks.del h

proc measure(p: Page, text: string, font: HFONT, width: int): int =
  let dc = GetDC(p.hwnd)
  SelectObject(dc, font)
  var r = RECT(left: 0, top: 0, right: int32(width), bottom: 0)
  discard DrawTextW(dc, newWideCString(if text.len == 0: " " else: text), -1, addr r, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX)
  ReleaseDC(p.hwnd, dc)
  int(r.bottom - r.top)

proc textHeight*(h: HWND, text: string, width: int): int =
  ## how tall `text` is in the normal font, wrapped at `width` px (the main window's status line, #371)
  let dc = GetDC(h)
  SelectObject(dc, fontNormal)
  var r = RECT(left: 0, top: 0, right: int32(max(10, width)), bottom: 0)
  discard DrawTextW(dc, newWideCString(if text.len == 0: " " else: text), -1, addr r, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX)
  ReleaseDC(h, dc)
  int(r.bottom - r.top)

proc textWidth(p: Page, text: string, font: HFONT): int =
  let dc = GetDC(p.hwnd)
  SelectObject(dc, font)
  var r = RECT(left: 0, top: 0, right: 0, bottom: 0)
  discard DrawTextW(dc, newWideCString(if text.len == 0: " " else: text), -1, addr r, DT_CALCRECT or DT_NOPREFIX)
  ReleaseDC(p.hwnd, dc)
  int(r.right - r.left)

proc fieldLabel(p: Page, lab: HWND, w: int): int =
  ## a field's label: one line's height, or as tall as its text wrapped at the page's width when the text is larger
  ## than at 100 % (a long label takes two lines at 150 %, #377); at 100 % as before
  if textScale == 1.0: return int(px(20))
  max(int(tx(20)), p.measure(lab.text, fontNormal, w) + int(px(2)))

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
      let lh = p.fieldLabel(it.hwnds[0], w)
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), int32(lh), 1)
      MoveWindow(it.hwnds[1], x, int32(y + lh), int32(w), tx(28), 1)
      y += lh - int(tx(20)) + txp(48, 8)
    of ikMulti:
      let lh = p.fieldLabel(it.hwnds[0], w)
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), int32(lh), 1)
      MoveWindow(it.hwnds[1], x, int32(y + lh), int32(w), tx(it.height), 1)
      y += lh - int(tx(20)) + tx(it.height) + txp(20, 8)
    of ikButtons:
      var bx = int(x)
      if it.right:       # (one row at the right when they fit; else from the left, as any)
        var total = 0
        for b in it.hwnds: total += max(int(px(90)), p.textWidth(b.text.replace("&&", "&"), fontNormal) + int(px(28))) + int(px(8))
        if total - int(px(8)) <= w: bx = int(x) + w - (total - int(px(8)))
      for b in it.hwnds:
        let bw = max(int(px(90)), p.textWidth(b.text.replace("&&", "&"), fontNormal) + int(px(28)))
        if bx > int(x) and bx + bw > int(x) + w:        # wrap to the next line
          bx = int(x)
          y += txp(30, 8)
        MoveWindow(b, int32(bx), int32(y), int32(min(bw, w)), tx(30), 1)
        bx += bw + int(px(8))
      y += txp(30, 10)
    of ikCheck:
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), tx(26), 1)
      y += txp(26, 6)
    of ikList:      # (its height is made for a number of rows: it grows with them)
      MoveWindow(it.hwnds[0], x, int32(y), int32(w), tx(it.height), 1)
      y += tx(it.height) + px(10)
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
        let th = p.measure(b.text.replace("&&", "&"), fontNormal, w - int(px(28))) + int(px(16))
        MoveWindow(b, int32(bx), int32(y), int32(w), int32(max(int(tx(32)), th)), 1)
        y += max(int(tx(32)), th) + px(6)
  p.contentH = y + p.scroll + px(12)
  var si = SCROLLINFO(cbSize: UINT(sizeof(SCROLLINFO)), fMask: SIF_ALL, nMin: 0, nMax: int32(p.contentH),
                      nPage: UINT(r.bottom), nPos: int32(p.scroll))
  SetScrollInfo(p.hwnd, SB_VERT, addr si, 1)

proc zoomRich(h: HWND) =
  ## rich text (courses) at the text size: RichEdit's own zoom (its fonts are in points, from the RTF)
  SendMessageW(h, 0x04E1'u32, WPARAM(int(round(textScale * 100))), 100)     # EM_SETZOOM

proc relayoutAll() =
  ## after new fonts: every page laid out again with them, owner-drawn lists' rows and rich text at the new size
  var ps: seq[Page]
  for h, p in pages:
    if IsWindow(h) != 0: ps.add p
  for p in ps:
    for it in p.items:
      if it.kind == ikList and it.hwnds[0] in ownerDraws:
        SendMessageW(it.hwnds[0], 0x01A0'u32, 0, LPARAM(tx(26)))           # LB_SETITEMHEIGHT
  var rs: seq[HWND]
  for h in richH.keys: rs.add h
  for h in rs:
    if IsWindow(h) != 0: zoomRich(h)
  for p in ps:
    if p.hwnd != nil and IsWindow(p.hwnd) != 0: p.layout()

afterFonts.add relayoutAll

proc isEmpty*(p: Page): bool = p == nil or p.items.len == 0

proc placeColumn*(head, body: Page, x, w, h: int, headOn: bool): int =
  ## a column of two pages at `x`: `head` on top, as tall as what it holds (at most half the column), and `body`
  ## under it, which scrolls on its own: what is in `head` stays in view however far `body` is scrolled (the tag
  ## panel's code, Copy and Close; the user, 2026-11-15). Without `headOn` (or with nothing in it), `head` is hidden
  ## and `body` takes the whole column. -> the height `head` took
  if headOn and not head.isEmpty and w > 0:
    MoveWindow(head.hwnd, int32(x), 0, int32(w), int32(h), 0)
    head.layout()
    # (one pixel more than what it holds: at exactly that height Windows still showed the page's scroll bar)
    result = min(head.contentH + 1, h div 2)
    MoveWindow(head.hwnd, int32(x), 0, int32(w), int32(result), 1)
    head.layout()            # (at its own height: no scroll bar when all of it fits)
  ShowWindow(head.hwnd, if result > 0: SW_SHOW else: SW_HIDE)
  MoveWindow(body.hwnd, int32(x), int32(result), int32(max(w, 0)), int32(h - result), 1)

proc tabRows*(widths: seq[int], avail, gap: int): seq[seq[int]] =
  ## the tabs (their least widths) in rows of at most `avail` px with `gap` between them, in order; a tab wider than
  ## `avail` has a row of its own. -> each row's tab indexes
  var used = 0
  for i, tw in widths:
    if result.len == 0 or used + gap + tw > avail:
      result.add @[i]
      used = tw
    else:
      result[^1].add i
      used += gap + tw

proc placeTabs*(tabs: seq[HWND], x, y, w: int): int =
  ## the tab buttons inside a strip `w` px wide at (x, y) (the sidebar's width): each at least as wide as its label
  ## plus padding, one row when they all fit, wrapped into more rows when not (larger scaling, longer labels), each
  ## row stretched to the strip's width. Never past the strip: the drawing beside it, a sibling window that paints
  ## its whole area, hid what stood over it (the user, 2026-11-18: Manage under the drawing). -> the strip's height
  let m = int(px(4))
  let rowH = int(tx(32))
  var widths: seq[int]
  for b in tabs:
    SendMessageW(b, WM_SETFONT, cast[WPARAM](fontNormal), 0)   # (WM_DPICHANGED made new fonts: measure with the one shown)
    let dc = GetDC(b)
    SelectObject(dc, fontNormal)
    var r = RECT()
    discard DrawTextW(dc, newWideCString(b.text), -1, addr r, DT_CALCRECT or DT_SINGLELINE)  # ("&&" is one "&")
    ReleaseDC(b, dc)
    widths.add int(r.right - r.left) + int(px(12))   # (the least room around a label; a row's spare is shared out)
  let avail = max(1, w - 2 * m)
  let rows = tabRows(widths, avail, m)
  for ri, row in rows:
    var least = 0
    for i in row: least += widths[i]
    let spare = max(0, avail - least - m * (row.len - 1))
    var bx = x + m
    for k, i in row:
      let extra = spare div row.len + (if k < spare mod row.len: 1 else: 0)
      let bw = if row.len == 1: avail else: widths[i] + extra
      MoveWindow(tabs[i], int32(bx), int32(y + int(px(6)) + ri * (rowH + m)), int32(bw), int32(rowH), 1)
      bx += bw + m
  int(px(6)) + rows.len * rowH + (rows.len - 1) * m + int(px(6))

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

var escCloses: seq[HWND]      ## popups that Escape closes (IsDialogMessage turns it into IDCANCEL)

proc pageProc(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT {.stdcall.} =
  let p = pages.getOrDefault(h)
  case m
  of WM_CLOSE:
    # a multi-line edit sends Escape to its parent as WM_CLOSE, and the default destroyed the page under its window
    # (an empty licence window was left): the window it is in closes when Escape closes it, else nothing does
    let root = GetAncestor(h, 2)        # GA_ROOT
    if root != nil and root in escCloses: PostMessageW(root, WM_CLOSE, 0, 0)
    return 0
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
  of WM_MEASUREITEM:
    let mi = cast[ptr MEASUREITEMSTRUCT](l)
    mi.itemHeight = UINT(tx(26))
    return 1
  of WM_DRAWITEM:
    let di = cast[ptr DRAWITEMSTRUCT](l)
    if di.hwndItem in ownerDraws:
      try: ownerDraws[di.hwndItem](di.hDC, di.rcItem, int(cast[int32](di.itemID)), (di.itemState and ODS_SELECTED) != 0)
      except CatchableError as e: report(e)
      if (di.itemState and ODS_FOCUS) != 0:
        var r = di.rcItem
        DrawFocusRect(di.hDC, addr r)
      return 1
  of WM_DESTROY:
    if p != nil:
      for it in p.items:
        for c in it.hwnds: forgetControl(c)
      p.items.setLen(0)
      p.typed.setLen(0)
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
  themeContainer(result.hwnd)

proc destroy*(p: Page) =
  if p != nil and p.hwnd != nil:
    DestroyWindow(p.hwnd)
    p.hwnd = nil

proc clear*(p: Page) =
  ## remove every control (the page is rebuilt)
  for it in p.items:
    for h in it.hwnds:
      forgetControl(h)
      DestroyWindow(h)
  p.items.setLen(0)
  p.typed.setLen(0)
  p.scroll = 0

proc edited*(p: Page): bool =
  ## something was typed into one of the page's fields and is still there: a rebuild now would lose it
  if p == nil or p.hwnd == nil: return false
  for f in p.typed:
    if IsWindow(f.h) != 0 and f.h.text != f.was: return true

type KeptText* = seq[tuple[name, key, was: string, nth: int, text: string]]
  ## what was typed into a page's fields, each by its label, what it holds (field's `key`), the text it was made with and
  ## which of the fields with both it was (so it finds its field again in the page made anew)

proc keptText*(p: Page, drop: openArray[HWND] = []): KeptText =
  ## what was typed into the page's fields and is still there, except in the fields in `drop` (what a button has just
  ## sent, or a form it closes), to be put back with restoreText once the page is made again (#168)
  if p == nil or p.hwnd == nil: return
  for i, f in p.typed:
    var nth = 0
    for j in 0 ..< i:
      if p.typed[j].key == f.key and p.typed[j].was == f.was: inc nth
    if IsWindow(f.h) == 0 or f.h in drop or f.secret: continue
    let t = f.h.text
    if t != f.was: result.add (f.name, f.key, f.was, nth, t)

proc restoreText*(p: Page, kept: KeptText): KeptText =
  ## each kept text back into the page's field with the same label made with the same text (the n-th such field for
  ## the n-th); it still counts as typed (`edited`). -> what found no such field: its part of the page has gone, or the
  ## value the field shows changed underneath (put back, it would be sent as a change of the new value)
  if p == nil or p.hwnd == nil: return kept
  for k in kept:
    var nth = 0
    var found = false
    for f in p.typed:
      if f.key == k.key and f.was == k.was and IsWindow(f.h) != 0:
        if nth == k.nth:
          f.h.setText(k.text)
          found = true
          break
        inc nth
    if not found: result.add k


proc setLabel*(h: HWND, text: string) =
  ## a page's label given new text: its height is measured again (a status line that becomes a sentence or two wraps
  ## instead of being cut after its first line, #371)
  h.setText(text)
  let pg = GetParent(h)
  if pg in pages:
    let p = pages[pg]
    for it in p.items.mitems:
      if it.kind in {ikLabel, ikDim} and h in it.hwnds: it.text = text
    p.layout()

proc label*(p: Page, text: string): HWND {.discardable.} =
  result = control(p.hwnd, "STATIC", text, SS_LEFT or SS_NOPREFIX or SS_EDITCONTROL)[0]
  p.items.add Item(kind: ikLabel, hwnds: @[result], text: text)

proc title*(p: Page, text: string): HWND {.discardable.} =
  result = control(p.hwnd, "STATIC", text, SS_LEFT or SS_NOPREFIX, font = fontTitle)[0]
  p.items.add Item(kind: ikTitle, hwnds: @[result], text: text)

proc dim*(p: Page, text: string): HWND {.discardable.} =
  result = control(p.hwnd, "STATIC", text, SS_LEFT or SS_NOPREFIX or SS_EDITCONTROL, font = fontSmall)[0]
  themeDim(result)
  p.items.add Item(kind: ikDim, hwnds: @[result], text: text)

proc field*(p: Page, name, value: string, password = false, readonly = false, onChange: proc () = nil,
            key = ""): HWND {.discardable.} =
  ## key: what the field holds, where its label doesn't say (a custom field's value: its name), so that what was typed
  ## goes back into the field for the same thing when the page is made again (restoreText)
  let lab = control(p.hwnd, "STATIC", name, SS_LEFT or SS_NOPREFIX)[0]
  let (e, _) = control(p.hwnd, "EDIT", value, WS_TABSTOP or ES_AUTOHSCROLL or (if password: ES_PASSWORD else: 0) or
                       (if readonly: ES_READONLY else: 0), WS_EX_CLIENTEDGE)
  if onChange != nil: ctl(e).change = onChange
  if not readonly: p.typed.add Typed(h: e, name: name, key: (if key.len > 0: key else: name), was: e.text, secret: password)
  p.items.add Item(kind: ikField, hwnds: @[lab, e])
  e

proc multiField*(p: Page, name, value: string, height = 90, readonly = false): HWND {.discardable.} =
  let lab = control(p.hwnd, "STATIC", name, SS_LEFT or SS_NOPREFIX)[0]
  result = control(p.hwnd, "EDIT", value.replace("\n", "\r\n"), WS_TABSTOP or WS_VSCROLL or ES_MULTILINE or
                          ES_AUTOVSCROLL or ES_WANTRETURN or (if readonly: ES_READONLY else: 0), WS_EX_CLIENTEDGE)[0]
  if not readonly: p.typed.add Typed(h: result, name: name, key: name, was: result.text)
  p.items.add Item(kind: ikMulti, hwnds: @[lab, result], height: height)

proc toSpec*[F](x: (string, F)): (string, proc ()) =
  ## lambdas that capture nothing are nimcall and a tuple doesn't convert by itself: wrap them as closures.
  ## A lambda that only calls a nested closure proc (`proc () = open()`) must say `{.closure.}`: Nim 2.2.12 types it
  ## nimcall here, makes it a closure later, and this instance then copies its environment without counting the
  ## reference (freed once too often when the buttons go: heap corruption, crashes anywhere later; Windows 11)
  let f = x[1]
  (x[0], proc () = f())

proc buttons*(p: Page, specs: seq[(string, proc ())], right: bool): seq[HWND] {.discardable.} =
  ## buttons in a row (wrapped when they don't fit); `right`: at the right, as a dialog's
  for (t, f) in specs:
    let (b, _) = control(p.hwnd, "BUTTON", t, WS_TABSTOP or BS_PUSHBUTTON)
    onClick(b, f)
    result.add b
  p.items.add Item(kind: ikButtons, hwnds: result, right: right)

proc buttons*(p: Page, specs: varargs[(string, proc ()), toSpec]): seq[HWND] {.discardable.} =
  p.buttons(@specs, false)

proc check*(p: Page, text: string, on: bool, f: proc (on: bool)): HWND {.discardable.} =
  let (b, _) = control(p.hwnd, "BUTTON", text, WS_TABSTOP or BS_AUTOCHECKBOX)
  SendMessageW(b, BM_SETCHECK, WPARAM(ord(on)), 0)
  onClick(b, proc () = f(SendMessageW(b, BM_GETCHECK, 0, 0) == 1))
  p.items.add Item(kind: ikCheck, hwnds: @[b])
  b

proc list*(p: Page, rows: seq[string], height = 200, onSelect: proc (i: int) = nil,
           onActivate: proc (i: int) = nil, openLabel = ""): HWND {.discardable.} =
  ## onActivate runs on double-click and Enter; with openLabel, also from a button below the list (a list item has
  ## no Invoke for UI Automation, and a button is reachable the same way for every user)
  let (l, _) = control(p.hwnd, "LISTBOX", "", WS_TABSTOP or WS_VSCROLL or LBS_NOTIFY or LBS_NOINTEGRALHEIGHT, WS_EX_CLIENTEDGE)
  for r in rows: sendText(l, LB_ADDSTRING, 0, r)
  listRows[l] = rows
  if onSelect != nil: onSelectList(l, onSelect)
  if onActivate != nil: onActivateList(l, onActivate)
  p.items.add Item(kind: ikList, hwnds: @[l], height: height)
  if onActivate != nil and openLabel.len > 0:
    let (b, _) = control(p.hwnd, "BUTTON", openLabel, WS_TABSTOP or BS_PUSHBUTTON)
    onClick(b, proc () =
      let i = int(SendMessageW(l, LB_GETCURSEL, 0, 0))
      if i >= 0: onActivate(i))
    p.items.add Item(kind: ikButtons, hwnds: @[b])
  l

proc drawRow*(dc: HDC, r: RECT, text: string, selected: bool, indent: int) =
  ## an owner-drawn list row's background and text, the text from `indent` px (a picture goes before it)
  var rr = r
  if selected: FillRect(dc, addr rr, cast[HBRUSH0](GetSysColorBrush(COLOR_HIGHLIGHT)))
  else:
    let b = CreateSolidBrush(themeColor(rSurface))      # (the system's window colour, or the dark theme's)
    FillRect(dc, addr rr, b)
    DeleteObject(b)
  let oldFont = SelectObject(dc, fontNormal)
  SetBkMode(dc, 1)          # TRANSPARENT
  SetTextColor(dc, if selected: GetSysColor(COLOR_HIGHLIGHTTEXT) else: themeColor(rText))
  var tr = RECT(left: r.left + int32(indent), top: r.top, right: r.right - px(4), bottom: r.bottom)
  discard DrawTextW(dc, newWideCString(text), -1, addr tr, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS)
  SelectObject(dc, oldFont)  # the DC goes back as it came (WM_DRAWITEM)

proc CreatePen(style, width: int32, c: DWORD): HGDIOBJ {.importc, stdcall, header: HG.}
proc GetStockObject(i: int32): HGDIOBJ {.importc, stdcall, header: HG.}
proc Ellipse(dc: HDC, l, t, r, b: int32): int32 {.importc, stdcall, header: HG, discardable.}
proc Rectangle(dc: HDC, l, t, r, b: int32): int32 {.importc, stdcall, header: HG, discardable.}
proc Pie(dc: HDC, l, t, r, b, x1, y1, x2, y2: int32): int32 {.importc, stdcall, header: HG, discardable.}

proc photoStateWords*(photos: string): string =
  ## a code's photo coverage in words, the same on every client
  case photos
  of "both": "equipment and tag plate photos"
  of "equipment": "equipment photo only"
  of "plate": "tag plate photo only"
  else: "no photos"

proc photoRgb*(photos: string): uint32 =
  ## the photo coverage colours, the same on every client (viewer.coverColor): both green, the equipment only amber,
  ## the tag plate only blue, none red
  case photos
  of "both": 0x2EA043'u32
  of "equipment": 0xE69600'u32
  of "plate": 0x1E78E6'u32
  else: 0xDC2828'u32

proc markRgb*(photos: string, light: bool): uint32 =
  ## the photo mark's fill: the coverage colour, except on a light background, where the green and the amber are
  ## darker (the drawings' are 3.4:1 and 2.4:1 on white; these 4.4:1 and 4.2:1, UI/UX audit of #401). The same on
  ## every client.
  if light and photos == "both": 0x2B8A3E'u32
  elif light and photos == "equipment": 0xB36B00'u32
  else: photoRgb(photos)

proc lightRgb(c: DWORD): bool =
  ## a COLORREF (0x00BBGGRR) light enough that dark text goes on it
  let r = float(c and 0xFF)
  let g = float((c shr 8) and 0xFF)
  let b = float((c shr 16) and 0xFF)
  0.299 * r + 0.587 * g + 0.114 * b > 128

proc drawPhotoMark*(dc: HDC, r: RECT, photos: string, selected: bool) =
  ## the photo mark at the start of an owner-drawn row `r` (search results): the coverage colour and a shape of its
  ## own per state, so it reads without colour: none = an empty ring, equipment only = a half-filled disc, tag plate
  ## only = a filled square, both = a filled disc. A thin line in the text colour around it keeps the shape at 3:1 on
  ## any theme, the contrast themes included. The row's text says the same in words.
  let d = px(12)
  let l = r.left + px(7)
  let t = r.top + (r.bottom - r.top - d) div 2
  let hue = colorRef(markRgb(photos, lightRgb(if selected: GetSysColor(COLOR_HIGHLIGHT) else: themeColor(rSurface))))
  let line = CreatePen(0, 1, if selected: GetSysColor(COLOR_HIGHLIGHTTEXT) else: themeColor(rText))
  let ring = CreatePen(6, max(2, px(2)), hue)          # PS_INSIDEFRAME: the ring stays inside its box
  let fill = CreateSolidBrush(hue)
  let hollow = GetStockObject(5)                       # NULL_BRUSH
  let oldPen = SelectObject(dc, line)
  let oldBrush = SelectObject(dc, fill)
  case photos
  of "both": Ellipse(dc, l, t, l + d, t + d)
  of "plate": Rectangle(dc, l, t, l + d, t + d)
  else:
    SelectObject(dc, ring)
    SelectObject(dc, hollow)
    Ellipse(dc, l + 1, t + 1, l + d - 1, t + d - 1)
    if photos == "equipment":                          # the left half filled (from the top round to the bottom)
      SelectObject(dc, fill)
      SelectObject(dc, GetStockObject(8))              # NULL_PEN: no line along the diameter (it all but filled the
                                                       # empty half: UI/UX audit of #401)
      Pie(dc, l + 1, t + 1, l + d - 1, t + d - 1, l + d div 2, t, l + d div 2, t + d)
    SelectObject(dc, line)
    SelectObject(dc, hollow)
    Ellipse(dc, l, t, l + d, t + d)
  SelectObject(dc, oldPen)
  SelectObject(dc, oldBrush)
  DeleteObject(line)
  DeleteObject(ring)
  DeleteObject(fill)

proc pictureList*(p: Page, rows: seq[string], draw: OwnerDraw, height = 200, onActivate: proc (i: int) = nil,
                  openLabel = ""): HWND {.discardable.} =
  ## a list whose rows `draw` paints (a small picture, then drawRow); the rows' strings stay its UI Automation names
  let (l, _) = control(p.hwnd, "LISTBOX", "", WS_TABSTOP or WS_VSCROLL or LBS_NOTIFY or LBS_NOINTEGRALHEIGHT or
                       LBS_OWNERDRAWFIXED or LBS_HASSTRINGS, WS_EX_CLIENTEDGE)
  ownerDraws[l] = draw
  for r in rows: sendText(l, LB_ADDSTRING, 0, r)
  listRows[l] = rows
  if onActivate != nil: onActivateList(l, onActivate)
  p.items.add Item(kind: ikList, hwnds: @[l], height: height)
  if onActivate != nil and openLabel.len > 0:
    let (b, _) = control(p.hwnd, "BUTTON", openLabel, WS_TABSTOP or BS_PUSHBUTTON)
    onClick(b, proc () =
      let i = int(SendMessageW(l, LB_GETCURSEL, 0, 0))
      if i >= 0: onActivate(i))
    p.items.add Item(kind: ikButtons, hwnds: @[b])
  l

proc picture*(p: Page, name: string, height: int, draw: OwnerDraw): HWND {.discardable.} =
  ## a small drawn picture whose text (its UI Automation name) says what it shows; `draw` gets item -1
  result = control(p.hwnd, "STATIC", name, SS_OWNERDRAW or SS_NOPREFIX)[0]
  ownerDraws[result] = draw
  p.items.add Item(kind: ikCustom, hwnds: @[result], height: height)

proc updateRows*(l: HWND, rows: seq[string]) =
  ## new texts for a list's rows, keeping the selection and the scroll position (a sync, under the focus). Only the
  ## rows whose text changed are replaced, and nothing when none did: a row replaced is a new row for UI Automation,
  ## so what a screen reader (or the e2e driver) had found of it no longer acts (a sync under the keyboard made every
  ## row anew, and a search result picked just then was not selected)
  if listRows.hasKey(l) and listRows[l] == rows: return
  let sel = SendMessageW(l, LB_GETCURSEL, 0, 0)
  let top = SendMessageW(l, 0x018E'u32, 0, 0)         # LB_GETTOPINDEX
  SendMessageW(l, 0x000B'u32, 0, 0)                   # WM_SETREDRAW off
  let old = listRows.getOrDefault(l)
  if listRows.hasKey(l) and old.len == rows.len:
    for i in 0 ..< rows.len:
      if old[i] != rows[i]:
        SendMessageW(l, 0x0182'u32, WPARAM(i), 0)     # LB_DELETESTRING
        discard sendText(l, 0x0181'u32, WPARAM(i), rows[i])    # LB_INSERTSTRING
  else:
    SendMessageW(l, LB_RESETCONTENT, 0, 0)
    for r in rows: sendText(l, LB_ADDSTRING, 0, r)
  listRows[l] = rows
  if sel >= 0 and sel < rows.len: SendMessageW(l, LB_SETCURSEL, WPARAM(sel), 0)
  if top >= 0: SendMessageW(l, 0x0197'u32, WPARAM(top), 0)    # LB_SETTOPINDEX
  SendMessageW(l, 0x000B'u32, 1, 0)
  InvalidateRect(l, nil, 1)

proc space*(p: Page, h = 12) = p.items.add Item(kind: ikSpace, height: h)

var richLoaded = false
proc rich*(p: Page, rtf: string, links: seq[(string, string)] = @[]): HWND {.discardable.} =
  ## read-only rich text from RTF (ASCII, non-ASCII as \uN?); `links` = (display text, target) in reading order: each
  ## is found after the previous one and marked as a link
  if not richLoaded:
    discard LoadLibraryW(newWideCString("Msftedit.dll"))
    richLoaded = true
  result = control(p.hwnd, "RICHEDIT50W", "", WS_TABSTOP or ES_MULTILINE or ES_READONLY)[0]
  SendMessageW(result, EM_SETBKGNDCOLOR, 0, LPARAM(if uiDark: themeColor(rWindow) else: GetSysColor(colorWindowIdx)))
  SendMessageW(result, EM_AUTOURLDETECT, 0, 0)
  # Advanced typography: line breaking that keeps a no-break space with what stands before it (without it a line
  # ended between a digit and a no-break space, "0.385" / " Ω per °C"), and breaks a word too long for its table
  # cell where the cell is full.
  SendMessageW(result, EM_SETTYPOGRAPHYOPTIONS, TO_ADVANCEDTYPOGRAPHY, cast[LPARAM](TO_ADVANCEDTYPOGRAPHY))
  # No font binding: RichEdit took the minus sign (U+2212), the arrows and √ ≈ ≤ ≥ from Cambria Math whatever font
  # the run has. Its minus is as long as a dash ("supply − I × R" read as "supply — I × R") and half a character
  # wider than Consolas's cell (found 2026-10-13). Every character is now drawn in the face its run asks for; one
  # that face lacks comes from the fonts Windows links to Segoe UI, and Consolas has what the courses' numbers use
  # (tests/test_courserich.nim).
  SendMessageW(result, EM_SETLANGOPTIONS, 0, LPARAM(int(SendMessageW(result, EM_GETLANGOPTIONS, 0, 0)) and not IMF_AUTOFONT))
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
  if textScale != 1.0: zoomRich(result)
  p.items.add Item(kind: ikRich, hwnds: @[result])

proc tallButtons*(p: Page, specs: seq[(string, proc ())]): seq[HWND] {.discardable.} =
  ## full-width buttons whose text wraps (answer options)
  for (t, f) in specs:
    let (b, _) = control(p.hwnd, "BUTTON", t, WS_TABSTOP or BS_PUSHBUTTON or BS_MULTILINE or BS_LEFT)
    onClick(b, f)
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
  result = control(p.hwnd, "msctls_trackbar32", name, WS_TABSTOP or TBS_HORZ)[0]
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
      let (b, _) = control(p.hwnd, "BUTTON", labels[i], WS_TABSTOP or BS_AUTORADIOBUTTON or (if i == 0: WS_GROUP else: 0))
      SendMessageW(b, BM_SETCHECK, WPARAM(ord(i == selected)), 0)
      onClick(b, proc () = f(idx))
      p.items.add Item(kind: ikCheck, hwnds: @[b])
      res.add b
  groupEnds = true
  res

proc chips*(p: Page, labels: seq[string], selected: int, f: proc (i: int)): seq[HWND] {.discardable.} =
  ## one choice of several (a filter): radio buttons laid out in rows like buttons; f runs when one is chosen. UIA:
  ## radio buttons named by their text, the chosen one selected
  var res: seq[HWND]
  for i in 0 ..< labels.len:
    closureScope:
      let idx = i
      let (b, _) = control(p.hwnd, "BUTTON", labels[i], WS_TABSTOP or BS_AUTORADIOBUTTON or (if i == 0: WS_GROUP else: 0))
      SendMessageW(b, BM_SETCHECK, WPARAM(ord(i == selected)), 0)
      onClick(b, proc () = f(idx))
      res.add b
  p.items.add Item(kind: ikButtons, hwnds: res)
  res

proc custom*(p: Page, h: HWND, height: int) =
  p.items.add Item(kind: ikCustom, hwnds: @[h], height: height)

proc fill*(p: Page, h: HWND, minHeight: int) =
  ## a child that takes the rest of the page's height (at least minHeight DIPs): put it last
  p.items.add Item(kind: ikFill, hwnds: @[h], height: minHeight)

proc setRows*(l: HWND, rows: seq[string]) =
  SendMessageW(l, LB_RESETCONTENT, 0, 0)
  for r in rows: sendText(l, LB_ADDSTRING, 0, r)
  listRows[l] = rows

proc popup*(owner: HWND, title: string, w, h: int, onClose: proc () = nil, escape = false): (HWND, Page)
var popupMayClose* = initTable[HWND, proc (): bool]()   ## a popup's close box (and Escape) asks this first: false keeps it

proc LoadIconW(inst: HINSTANCE, name: int): pointer {.importc: "LoadIconW", stdcall, header: HG.}
proc SetWindowPos(h, after: HWND, x, y, cx, cy: int32, flags: UINT): BOOL {.importc, stdcall, header: HG, discardable.}
proc GetWindowLongPtrW(h: HWND, i: int32): int {.importc, stdcall, header: HG.}
proc SetWindowLongPtrW(h: HWND, i: int32, v: int): int {.importc, stdcall, header: HG, discardable.}
proc DrawIconEx(dc: HDC, x, y: int32, icon: pointer, w, h: int32, step: UINT, br: pointer, flags: UINT): BOOL {.importc, stdcall, header: HG, discardable.}

type MONITORINFO {.importc, header: HG.} = object
  cbSize: DWORD
  rcMonitor, rcWork: RECT
  dwFlags: DWORD
proc MonitorFromWindow(h: HWND, flags: DWORD): pointer {.importc, stdcall, header: HG.}
proc GetDoubleClickTime(): UINT {.importc, stdcall, header: HG.}
proc GetMonitorInfoW(m: pointer, mi: ptr MONITORINFO): BOOL {.importc, stdcall, header: HG.}

proc themedQuestion*(owner: HWND, title, text: string, answers: seq[string], focusOn, cancelWith: int,
                     warning = false, danger = -1): int =
  ## The app's own modal dialog for ask, askYesNo and say while its dark colours are on (theme.nim, #377): the task
  ## dialog and the message box are drawn by Windows in light colours whatever the app mode. The same parts and keys:
  ## the question (`title`, also the window's name, which a screen reader says first) and what it means, one button per
  ## answer, named by it, at the bottom right as Windows' dialogs have them; the keyboard starts on `focusOn`; Escape
  ## and the close box give `cancelWith`; Enter presses the button with the keyboard; `danger`: the answer whose action
  ## can't be taken back, in the destructive colour. The keyboard goes back where it was. -> the index of the answer
  var chosen = cancelWith
  var armed = true
  let ownerTop = if owner != nil: GetAncestor(owner, 2) else: nil        # GA_ROOT
  let before = GetFocus()
  let (hw, p) = popup(ownerTop, title, 460, 240, escape = true)
  # a dialog: no maximise, minimise or resizing
  SetWindowLongPtrW(hw, -16, GetWindowLongPtrW(hw, -16) and not 0x00070000)   # GWL_STYLE: WS_THICKFRAME, MIN/MAXBOX
  SetWindowPos(hw, nil, 0, 0, 0, 0, 0x0027'u32)        # SWP_FRAMECHANGED, NOMOVE, NOSIZE, NOZORDER: the new frame
  proc release() =
    # the owner usable again before the question goes, so Windows gives it the activation (not another app's window)
    if ownerTop != nil: EnableWindow(ownerTop, 1)
  popupMayClose[hw] = proc (): bool =        # Escape, the close box, Alt+F4: the cancelling answer
    release()
    true
  if warning:
    let icon = LoadIconW(nil, 32515)                                         # IDI_WARNING (the task dialog's)
    p.picture("Warning", 34, proc (dc: HDC, r: RECT, item: int, selected: bool) =
      let b = CreateSolidBrush(themeColor(rWindow))
      var rr = r
      FillRect(dc, addr rr, b)
      DeleteObject(b)
      DrawIconEx(dc, r.left, r.top, icon, px(32), px(32), 0, nil, 3))     # DI_NORMAL
  p.title(title)
  if text.len > 0: p.label(text)
  var specs: seq[(string, proc ())]
  for i in 0 ..< answers.len:
    closureScope:
      let k = i
      specs.add (answers[k], proc () =
        if not armed: return
        chosen = k
        release()
        DestroyWindow(hw))
  let bs = p.buttons(specs, right = true)
  if danger in 0 ..< bs.len: themeDanger(bs[danger])
  themeDialog(hw, text)          # a dialog to a screen reader, what it means as its description (as a task dialog)
  # the buttons take no press for a double-click's time: a second press of the button that opened the question
  # never answers it (S2), whatever sent it (the mouse, a key, UI Automation's Invoke)
  armed = false
  p.layout()
  # as tall as what it holds (within the screen's work area: the buttons stay on screen), over its owner, a third of
  # the way down
  var wr, cr, orr: RECT
  discard GetWindowRect(hw, addr wr)
  GetClientRect(hw, addr cr)
  var mi = MONITORINFO(cbSize: DWORD(sizeof(MONITORINFO)))
  discard GetMonitorInfoW(MonitorFromWindow(if ownerTop != nil: ownerTop else: hw, 2), addr mi)   # MONITOR_DEFAULTTONEAREST
  let wa = mi.rcWork
  let wW = min(int(wr.right - wr.left), int(wa.right - wa.left))
  let wH = min(int(wr.bottom - wr.top) - int(cr.bottom) + p.contentH + 1, int(wa.bottom - wa.top))  # (+1: no scroll bar)
  var x = int(wr.left)
  var y = int(wr.top)
  if ownerTop != nil and GetWindowRect(ownerTop, addr orr) != 0:
    x = (int(orr.left) + int(orr.right) - wW) div 2
    y = int(orr.top) + (int(orr.bottom) - int(orr.top) - wH) div 3
  x = max(int(wa.left), min(x, int(wa.right) - wW))
  y = max(int(wa.top), min(y, int(wa.bottom) - wH))
  SetWindowPos(hw, nil, int32(x), int32(y), int32(wW), int32(wH), 0x0024'u32)   # SWP_NOZORDER, SWP_FRAMECHANGED
  if ownerTop != nil: EnableWindow(ownerTop, 0)
  ShowWindow(hw, SW_SHOW)
  # (at most 700 ms: a double-click time raised for a tremor would otherwise hold the buttons for seconds)
  let ready = afterMs(min(int(GetDoubleClickTime()), 700), proc () = armed = true)
  if focusOn in 0 ..< bs.len: SetFocus(bs[focusOn])
  var msg: MSG
  while IsWindow(hw) != 0:
    let got = GetMessageW(addr msg, nil, 0, 0)
    if got == 0:
      PostQuitMessage(int32(msg.wParam))       # (the app is closing: the main loop sees it too)
      break
    if got < 0: break
    if msg.message == WM_KEYDOWN and int(msg.wParam) == VK_RETURN and GetAncestor(msg.hwnd, 2) == hw:
      let f = GetFocus()
      if f != nil and f in bs:
        SendMessageW(f, 0x00F5'u32, 0, 0)      # BM_CLICK
        continue
    let root = GetAncestor(msg.hwnd, 2)
    if root != nil and IsDialogMessageW(root, addr msg) != 0: continue
    TranslateMessage(addr msg)
    DispatchMessageW(addr msg)
  cancel(ready)
  release()
  if IsWindow(hw) != 0: DestroyWindow(hw)
  if ownerTop != nil: SetForegroundWindow(ownerTop)
  if before != nil and IsWindow(before) != 0: SetFocus(before)    # the keyboard back where it was
  chosen

proc ask*(owner: HWND, title, text, yes: string, no = "Cancel", destructive = true): bool =
  ## A question before an action (#365, D2 in docs/UI-UX-POLICY.md): a task dialog whose confirming button names the
  ## action (`yes`: "Delete photo", never OK), and whose default is the safe button (`no`), so Enter, Escape and
  ## closing it keep. With `destructive`: the warning icon. `title` is the question, `text` what it means. True: `yes`.
  ## In the app's dark colours: themedQuestion, with the same buttons, default and keys.
  if uiDark: return themedQuestion(owner, title, text, @[yes, no], 1, 1, destructive, if destructive: 0 else: -1) == 0
  let wTitle = newWideCString("Walkdown")
  let wQ = newWideCString(title)
  let wText = newWideCString(text)
  let wYes = newWideCString(yes)
  let wNo = newWideCString(no)
  var buttons = [TaskDialogButton(nButtonID: 100, pszButtonText: wYes), TaskDialogButton(nButtonID: 2, pszButtonText: wNo)]
  var c: TaskDialogConfig
  c.cbSize = UINT(sizeof(TaskDialogConfig))
  c.hwndParent = owner
  c.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION or TDF_POSITION_RELATIVE_TO_WINDOW
  c.pszWindowTitle = wTitle
  if destructive: c.pszMainIcon = cast[WideCString](TD_WARNING_ICON)
  c.pszMainInstruction = wQ
  if text.len > 0: c.pszContent = wText
  c.cButtons = UINT(buttons.len)
  c.pButtons = addr buttons[0]
  c.nDefaultButton = 2        # IDCANCEL: also what Escape and the close box give
  var pressed: int32 = 0
  if TaskDialogIndirect(addr c, addr pressed, nil, nil) == 0:
    return pressed == 100
  # (the task dialog failed to show: out of memory, a bad owner) a message box, its second button (Cancel) the
  # default. Without Common Controls v6 the app would not start at all: TaskDialogIndirect is imported from it.
  MessageBoxW(owner, newWideCString(title & (if text.len > 0: "\n\n" & text else: "")), wTitle,
              MB_OKCANCEL or MB_ICONQUESTION or 0x100'u32) == IDOK    # MB_DEFBUTTON2

proc askYesNo*(owner: HWND, title, text: string): bool =
  ## a question with Yes and No (MB_YESNO; IDYES = 6)
  if uiDark: return themedQuestion(owner, title, text, @["Yes", "No"], 0, 1) == 0     # (as MB_YESNO: Yes first)
  MessageBoxW(owner, newWideCString(text), newWideCString(title), 0x4'u32 or MB_ICONQUESTION) == 6

proc say*(owner: HWND, title, text: string) =
  if uiDark:
    discard themedQuestion(owner, title, text, @["OK"], 0, 0)
    return
  discard MessageBoxW(owner, newWideCString(text), newWideCString(title), MB_OK)

proc GlobalAlloc(flags: UINT, n: csize_t): pointer {.importc, stdcall, header: HG.}
proc GlobalLock(h: pointer): pointer {.importc, stdcall, header: HG.}
proc GlobalUnlock(h: pointer): BOOL {.importc, stdcall, header: HG, discardable.}
proc GlobalFree(h: pointer): pointer {.importc, stdcall, header: HG, discardable.}
proc SetClipboardData(fmt: UINT, h: pointer): pointer {.importc, stdcall, header: HG.}

proc copyToClipboard*(owner: HWND, text: string): bool =
  ## text to the clipboard as CF_UNICODETEXT (the clipboard owns the memory once SetClipboardData took it). -> it is there
  let wide = newWideCString(text)
  let bytes = (wide.len + 1) * 2
  let h = GlobalAlloc(0x0002, csize_t(bytes))      # GMEM_MOVEABLE (first: a failure leaves the clipboard as it was)
  if h == nil: return false
  let mem = GlobalLock(h)
  if mem == nil:
    GlobalFree(h)
    return false
  copyMem(mem, cast[pointer](wide[0].addr), bytes)
  GlobalUnlock(h)
  if OpenClipboard(owner) == 0:
    GlobalFree(h)
    return false
  EmptyClipboard()
  result = SetClipboardData(13, h) != nil          # CF_UNICODETEXT
  if not result: GlobalFree(h)
  CloseClipboard()

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

proc activateFocused*(): bool =
  ## Enter on a focused list opens its item (the keyboard equivalent of a double-click)
  let f = GetFocus()
  if f == nil: return false
  let c = ctls.getOrDefault(f)
  if c == nil: return false
  if c.enter != nil:
    deferred(f, c, proc (c: Ctl) = c.enter())
    return true
  if c.activate == nil: return false
  let i = int(SendMessageW(f, LB_GETCURSEL, 0, 0))
  if i >= 0: deferred(f, c, proc (c: Ctl) = c.activate(i))
  true

# ---------------------------------------------------------------- a popup window hosting a page

var popups = initTable[HWND, (Page, proc ())]()

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
  of WM_CLOSE:
    if h in popupMayClose:
      let ask = popupMayClose[h]      # (a copy: the window may go while it asks, and its entry with it)
      if not ask(): return 0
  of WM_DESTROY:
    popupMayClose.del h
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
  # (larger with the text size, within the screen's work area)
  var wa: RECT
  SystemParametersInfoW(0x0030, 0, addr wa, 0)         # SPI_GETWORKAREA
  let pw = min(int(tx(w)), max(int(px(w)), int(wa.right - wa.left)))
  let ph = min(int(tx(h)), max(int(px(h)), int(wa.bottom - wa.top)))
  let hw = CreateWindowExW(WS_EX_CONTROLPARENT, newWideCString("KKSPopup"), newWideCString(title), WS_OVERLAPPEDWINDOW,
                           CW_USEDEFAULT, CW_USEDEFAULT, int32(pw), int32(ph), owner, nil, hinst, nil)
  let p = newPage(hw)
  popups[hw] = (p, onClose)
  if escape: escCloses.add hw
  var r: RECT
  GetClientRect(hw, addr r)
  MoveWindow(p.hwnd, 0, 0, r.right, r.bottom, 1)
  (hw, p)
