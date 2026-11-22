## The Windows app's own dark colours (#377, decision 0078; theme.nim, kks_theme.cpp), behind the switch win-dark-ui:
## switched off, nothing changes (the system's colours, the task dialog); on, in dark app mode (KKS_TEST_SYSTEM_DARK
## stands in for Windows' setting) a page's background, its labels, fields and lists take the theme's colours, which
## meet the profile's contrast; the mode followed when it changes; ask, askYesNo and say use the app's own dialog,
## whose keyboard starts on the safe answer. Real windows and messages, so it runs on Windows (CI's windows-test):
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_theme.exe apps/windows/tests/test_theme.nim
import std/[unittest, os, math]
import kkswin/[w32, ui, theme]

const H = "<windows.h>"
proc GetDC(h: HWND): HDC {.importc, stdcall, header: H.}
proc ReleaseDC(h: HWND, dc: HDC): int32 {.importc, stdcall, header: H, discardable.}
proc CreateCompatibleDC(dc: HDC): HDC {.importc, stdcall, header: H.}
proc CreateCompatibleBitmap(dc: HDC, w, h: int32): HGDIOBJ {.importc, stdcall, header: H.}
proc SelectObject(dc: HDC, o: HGDIOBJ): HGDIOBJ {.importc, stdcall, header: H, discardable.}
proc DeleteObject(o: HGDIOBJ): int32 {.importc, stdcall, header: H, discardable.}
proc DeleteDC(dc: HDC): int32 {.importc, stdcall, header: H, discardable.}
proc GetPixel(dc: HDC, x, y: int32): DWORD {.importc, stdcall, header: H.}
proc GetTextColor(dc: HDC): DWORD {.importc, stdcall, header: H.}
proc GetSysColor(i: cint): DWORD {.importc, stdcall, header: H.}
type LOGBRUSH {.importc, header: H.} = object
  lbStyle: UINT
  lbColor: DWORD
proc GetObjectW(o: pointer, n: int32, p: pointer): int32 {.importc, stdcall, header: H.}
proc FindWindowExW(parent, after: HWND, cls, title: WideCString): HWND {.importc, stdcall, header: H.}
proc GetWindowTextW(h: HWND, s: WideCString, n: int32): int32 {.importc, stdcall, header: H.}

var main: HWND

proc mainProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  if m == WM_COMMAND and dispatchCommand(wp, lp): return 0
  if m == WM_KKS_LATER:
    runLater()
    return 0
  DefWindowProcW(h, m, wp, lp)

proc pump() =
  var msg: MSG
  while PeekMessageW(addr msg, nil, 0, 0, 1) != 0:
    TranslateMessage(addr msg)
    DispatchMessageW(addr msg)

proc lum(c: DWORD): float =
  ## WCAG relative luminance of a COLORREF
  proc ch(v: DWORD): float =
    let s = float(v and 0xFF) / 255
    if s <= 0.04045: s / 12.92 else: pow((s + 0.055) / 1.055, 2.4)
  0.2126 * ch(c) + 0.7152 * ch(c shr 8) + 0.0722 * ch(c shr 16)

proc contrast(a, b: DWORD): float =
  let (x, y) = (lum(a), lum(b))
  (max(x, y) + 0.05) / (min(x, y) + 0.05)

proc brushColour(b: LRESULT): DWORD =
  var lb: LOGBRUSH
  doAssert GetObjectW(cast[pointer](b), int32(sizeof(LOGBRUSH)), addr lb) > 0
  lb.lbColor

proc ctlColour(page: Page, msg: UINT, c: HWND): (DWORD, DWORD) =
  ## what the page answers a control asking for its colours: (text, background brush)
  let sdc = GetDC(page.hwnd)
  let dc = CreateCompatibleDC(sdc)
  let b = SendMessageW(page.hwnd, msg, cast[WPARAM](dc), cast[LPARAM](c))
  result = (GetTextColor(dc), brushColour(b))
  DeleteDC(dc)
  ReleaseDC(page.hwnd, sdc)

proc erased(h: HWND): DWORD =
  ## the colour a window erases its background with (WM_ERASEBKGND into a bitmap of our own)
  let sdc = GetDC(h)
  let dc = CreateCompatibleDC(sdc)
  let bmp = CreateCompatibleBitmap(sdc, 40, 40)
  let old = SelectObject(dc, bmp)
  discard SendMessageW(h, WM_ERASEBKGND, cast[WPARAM](dc), 0)
  result = GetPixel(dc, 5, 5)
  SelectObject(dc, old)
  DeleteObject(bmp)
  DeleteDC(dc)
  ReleaseDC(h, sdc)

proc textOf(h: HWND): string =
  var buf = newWideCString("", 128)
  discard GetWindowTextW(h, buf, 128)
  $buf

hinst = GetModuleHandleW(nil)
makeFonts(96)
block:
  let cls = newWideCString("KKSTestTheme")
  var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: mainProc, hInstance: hinst,
                       hbrBackground: GetSysColorBrush(COLOR_WINDOW), lpszClassName: cls)
  discard RegisterClassExW(addr wc)
  main = CreateWindowExW(WS_EX_CONTROLPARENT, cls, newWideCString("theme test"), WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN,
                         0, 0, 800, 600, nil, nil, hinst, nil)
  doAssert main != nil
  laterWindow = main
  ShowWindow(main, SW_SHOW)
  ShowWindow(main, SW_SHOW)

proc makePage(): (Page, HWND, HWND, HWND) =
  let p = newPage(main)
  MoveWindow(p.hwnd, 0, 0, 400, 500, 1)
  let lab = p.label("A label")
  let dim = p.dim("A secondary line")
  let f = p.field("A field", "text")
  discard p.list(@["one", "two"], 80)
  p.layout()
  pump()
  (p, lab, dim, f)

putEnv("KKS_TEST_SYSTEM_DARK", "1")

suite "switched off (as released)":
  test "dark app mode leaves the system's colours":
    initTheme()                       # (KKS_UX unset: the switch is off)
    check not themeEnabled()
    check not uiDark
    let (p, lab, _, _) = makePage()
    check erased(p.hwnd) == GetSysColor(5)                          # COLOR_WINDOW
    check ctlColour(p, WM_CTLCOLORSTATIC, lab)[1] == GetSysColor(5)
    check themeColor(rSurface) == GetSysColor(5)
    check themeColor(rText) == GetSysColor(8)
    check not refreshTheme()
    p.destroy()

suite "the dark colours (the switch on)":
  test "the palette meets the profile's contrast":
    let c = DarkColours
    for bg in [rWindow, rSurface]:
      check contrast(colorRef(c[rText]), colorRef(c[bg])) >= 7.0       # main text: 7:1 (A1, raised by the profile)
      check contrast(colorRef(c[rDim]), colorRef(c[bg])) >= 4.5        # secondary text
      check contrast(colorRef(c[rBorder]), colorRef(c[bg])) >= 3.0     # edges of fields and buttons (A2)
      check contrast(colorRef(c[rFocus]), colorRef(c[bg])) >= 3.0      # the focus ring (A2)
      check contrast(colorRef(c[rAccent]), colorRef(c[bg])) >= 3.0     # a ticked box, a chosen radio button (A2)
    for face in [rButton, rHot, rDown]:
      check contrast(colorRef(c[rText]), colorRef(c[face])) >= 7.0     # a button's label in each of its states
      check contrast(colorRef(c[rBorder]), colorRef(c[rWindow])) >= 3.0
    check contrast(colorRef(c[rAccentText]), colorRef(c[rAccent])) >= 4.5   # the tick and the dot

  test "a page and its controls in dark app mode":
    putEnv("KKS_UX", DarkUiSwitch)
    initTheme()
    check themeEnabled()
    check uiDark
    let (p, lab, dim, f) = makePage()
    let c = DarkColours
    check erased(p.hwnd) == colorRef(c[rWindow])
    check erased(main) == colorRef(c[rWindow])                       # the window holding it too
    check ctlColour(p, WM_CTLCOLORSTATIC, lab) == (colorRef(c[rText]), colorRef(c[rWindow]))
    check ctlColour(p, WM_CTLCOLORSTATIC, dim) == (colorRef(c[rDim]), colorRef(c[rWindow]))
    check ctlColour(p, 0x0133'u32, f) == (colorRef(c[rText]), colorRef(c[rSurface]))   # WM_CTLCOLOREDIT
    check themeColor(rSurface) == colorRef(c[rSurface])
    p.destroy()

  test "the app mode followed while the app runs, both ways":
    let (p, lab, _, _) = makePage()
    putEnv("KKS_TEST_SYSTEM_DARK", "0")
    check refreshTheme()
    check not uiDark
    check erased(p.hwnd) == GetSysColor(5)
    check ctlColour(p, WM_CTLCOLORSTATIC, lab)[1] == GetSysColor(5)
    check not refreshTheme()                                         # (nothing changed: nothing done)
    putEnv("KKS_TEST_SYSTEM_DARK", "1")
    check refreshTheme()
    check uiDark
    check erased(p.hwnd) == colorRef(DarkColours[rWindow])
    p.destroy()

  test "a question in the app's own dialog: the keyboard on the safe answer, Escape keeps":
    var seen = ""
    var dialogBg: DWORD = 0
    discard afterMs(400, proc () =
      let d = FindWindowExW(nil, nil, newWideCString("KKSPopup"), newWideCString("Walkdown"))
      doAssert d != nil, "no dialog"
      dialogBg = erased(d)
      seen = textOf(GetFocus())
      PostMessageW(GetFocus(), WM_KEYDOWN, VK_ESCAPE, 0))
    check not ask(main, "Delete this photo?", "It is removed for everyone.", "Delete photo")
    check seen == "Cancel"
    check dialogBg == colorRef(DarkColours[rWindow])
    # the named action, pressed
    discard afterMs(400, proc () =
      let d = FindWindowExW(nil, nil, newWideCString("KKSPopup"), newWideCString("Walkdown"))
      doAssert d != nil, "no dialog"
      var b: HWND = nil
      for page in [FindWindowExW(d, nil, newWideCString("KKSPage"), nil)]:
        var c = FindWindowExW(page, nil, newWideCString("Button"), nil)
        while c != nil:
          if textOf(c) == "Delete photo": b = c
          c = FindWindowExW(page, c, newWideCString("Button"), nil)
      doAssert b != nil, "no Delete photo button"
      SendMessageW(b, 0x00F5'u32, 0, 0))     # BM_CLICK
    check ask(main, "Delete this photo?", "It is removed for everyone.", "Delete photo")
    check IsWindowEnabled(main) != 0          # the owner usable again

  test "menus in dark only on the Windows builds where uxtheme's unnamed exports are known":
    check menusKnown(17762) == 0
    check menusKnown(17763) == 1
    check menusKnown(26300) == 1
    check menusKnown(30000) == 0
