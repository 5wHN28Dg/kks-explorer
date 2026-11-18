## The main window's tabs stay inside the sidebar at 100, 125 and 150 % scaling (the user, 2026-11-18: "the manage
## button ... most of it is hidden behind the P&ID"; #377: five tabs of 92 px took 472 px in the 380 px sidebar, and
## the drawing beside it, a sibling window that paints its whole area, covered Manage until the mouse came over it).
## ui.placeTabs lays them out by their labels' widths in the font shown, wrapped into rows when they don't fit.
## Real windows and fonts, so it runs on Windows (CI's windows-test; a scale is simulated by the fonts and sizes the
## app makes for that DPI, as after WM_DPICHANGED):
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_tabs.exe apps/windows/tests/test_tabs.nim
import std/[unittest]
import kkswin/[w32, ui]

const H = "<windows.h>"
proc ChildWindowFromPoint(h: HWND, p: POINT): HWND {.importc, stdcall, header: H.}
type SIZE {.importc, header: H.} = object
  cx, cy: int32
proc GetDC(h: HWND): HDC {.importc, stdcall, header: H.}
proc ReleaseDC(h: HWND, dc: HDC): int32 {.importc, stdcall, header: H, discardable.}
proc SelectObject(dc: HDC, o: HGDIOBJ): HGDIOBJ {.importc, stdcall, header: H, discardable.}
proc GetTextExtentPoint32W(dc: HDC, s: WideCString, n: int32, sz: ptr SIZE): BOOL {.importc, stdcall, header: H.}
proc DestroyWindow(h: HWND): BOOL {.importc, stdcall, header: H, discardable.}

const
  SideW = 380      ## the sidebar's width at 100 % (kks_explorer.nim)
  Labels = ["Drawings", "Procedures", "Review", "Learning", "Manage"]

var main: HWND

proc mainProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} = DefWindowProcW(h, m, wp, lp)

proc inMain(c: HWND): RECT =
  var r: RECT
  doAssert GetWindowRect(c, addr r) != 0
  var a = POINT(x: r.left, y: r.top)
  var b = POINT(x: r.right, y: r.bottom)
  ScreenToClient(main, addr a)
  ScreenToClient(main, addr b)
  RECT(left: a.x, top: a.y, right: b.x, bottom: b.y)

proc textW(h: HWND, s: string): int =
  let dc = GetDC(h)
  SelectObject(dc, fontNormal)
  var sz: SIZE
  doAssert GetTextExtentPoint32W(dc, newWideCString(s), int32(newWideCString(s).len), addr sz) != 0
  ReleaseDC(h, dc)
  int(sz.cx)

hinst = GetModuleHandleW(nil)
makeFonts(96)
block:
  let cls = newWideCString("KKSTestTabs")
  var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: mainProc, hInstance: hinst,
                       hbrBackground: GetSysColorBrush(COLOR_WINDOW), lpszClassName: cls)
  discard RegisterClassExW(addr wc)
  main = CreateWindowExW(WS_EX_CONTROLPARENT, cls, newWideCString("tabs test"), WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN,
                         0, 0, 1366, 768, nil, nil, hinst, nil)
  doAssert main != nil
  ShowWindow(main, SW_SHOW)
  ShowWindow(main, SW_SHOW)      # (the first call follows the starting process's show flag: hidden when started over SSH)

proc checkTabs(d: int, labels: openArray[string]): int =
  ## the tabs at this DPI, the "drawing" (a sibling made after them, as in the app) beside the sidebar; -> rows
  makeFonts(d)
  let side = int(px(SideW))
  # (the stand-in drawing first: above the tabs in z-order, so a tab under it is not what the hit test finds)
  let drawing = control(main, "STATIC", "drawing", 0)[0]
  var tabs: seq[HWND]
  for l in labels: tabs.add control(main, "BUTTON", l, WS_TABSTOP or BS_PUSHBUTTON)[0]
  let h = placeTabs(tabs, 0, 0, side)
  MoveWindow(drawing, int32(side), 0, 600, 600, 1)
  var tops: seq[int32]
  for i, b in tabs:
    let r = inMain(b)
    checkpoint(labels[i] & " at " & $d & " dpi: " & $r)
    check r.left >= 0 and r.right <= side             # inside the sidebar: never under the drawing
    check r.top >= 0 and r.bottom <= h                # inside the strip placeTabs said it took
    # the whole label with room around it (one wider than the sidebar: the sidebar's width)
    check r.right - r.left >= min(textW(b, labels[i]) + int(px(8)), side - 2 * int(px(4)))
    for j in 0 ..< i:                                 # no two tabs overlap
      let o = inMain(tabs[j])
      check r.left >= o.right or o.left >= r.right or r.top >= o.bottom or o.top >= r.bottom
    let mid = POINT(x: (r.left + r.right) div 2, y: (r.top + r.bottom) div 2)
    check ChildWindowFromPoint(main, mid) == b         # what a click at its middle reaches, not the drawing
    if r.top notin tops: tops.add r.top
  for b in tabs: DestroyWindow(b)
  DestroyWindow(drawing)
  tops.len

suite "the tabs inside the sidebar":
  test "the five tabs fit in one row at 100, 125 and 150 % scaling":
    for d in [96, 120, 144]:
      check checkTabs(d, Labels) == 1

  test "longer labels wrap into more rows, still inside the sidebar":
    check checkTabs(96, ["Drawings and sheets", "Procedures to follow", "Review queue", "Learning courses",
                         "Manage this device"]) >= 2
    check checkTabs(144, ["A label far wider than the whole sidebar is, so it takes a row of its own", "Manage"]) == 2

  test "rows: in order, each within the width":
    check tabRows(@[100, 100, 100], 400, 4) == @[@[0, 1, 2]]
    check tabRows(@[100, 100, 100], 250, 4) == @[@[0, 1], @[2]]
    check tabRows(@[500, 50], 300, 4) == @[@[0], @[1]]
    check tabRows(@[], 300, 4).len == 0
