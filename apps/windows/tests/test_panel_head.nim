## The tag panel's heading (the code, Copy, Close) stays in view however far the panel is scrolled (the user,
## 2026-11-15: "Close button shouldn't be hidden or move away when I scroll down the sheet"): ui.placeColumn puts the
## heading in a page of its own above the panel's page, which scrolls under it. Before, Close was the panel page's
## third item and scrolled away with the rest.
## Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it); runs on Windows:
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_panel_head.exe apps/windows/tests/test_panel_head.nim
import std/[unittest, sequtils]
import kkswin/[w32, ui]

const H = "<windows.h>"
proc ChildWindowFromPoint(h: HWND, p: POINT): HWND {.importc, stdcall, header: H.}

var main: HWND

proc mainProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  if m == WM_COMMAND and dispatchCommand(wp, lp): return 0
  DefWindowProcW(h, m, wp, lp)

proc pump() =
  var msg: MSG
  while PeekMessageW(addr msg, nil, 0, 0, 1) != 0:
    TranslateMessage(addr msg)
    DispatchMessageW(addr msg)

proc inMain(c: HWND): RECT =
  ## a control's rectangle in the main window's client coordinates
  var r: RECT
  doAssert GetWindowRect(c, addr r) != 0
  var a = POINT(x: r.left, y: r.top)
  var b = POINT(x: r.right, y: r.bottom)
  ScreenToClient(main, addr a)
  ScreenToClient(main, addr b)
  RECT(left: a.x, top: a.y, right: b.x, bottom: b.y)

hinst = GetModuleHandleW(nil)
makeFonts(96)
block:
  let cls = newWideCString("KKSTestPanelHead")
  var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: mainProc, hInstance: hinst,
                       hbrBackground: GetSysColorBrush(COLOR_WINDOW), lpszClassName: cls)
  discard RegisterClassExW(addr wc)
  main = CreateWindowExW(WS_EX_CONTROLPARENT, cls, newWideCString("panel head test"), WS_OVERLAPPEDWINDOW, 0, 0, 900, 600,
                         nil, nil, hinst, nil)
  doAssert main != nil
  ShowWindow(main, SW_SHOW)

suite "the tag panel's heading":
  test "Copy and Close stay at the top while the panel scrolls to its end":
    let head = newPage(main)
    let body = newPage(main)
    head.title("11LAB70AA501")
    head.dim("Gate valve")
    let bs = head.buttons(("Copy", proc () = discard), ("Close", proc () = discard))
    var first: HWND
    for i in 0 ..< 80:
      let l = body.label("Field " & $i & ": a value long enough to take a line")
      if i == 0: first = l
    var r: RECT
    GetClientRect(main, addr r)
    let x = int(r.right) - 400
    let headH = placeColumn(head, body, x, 400, int(r.bottom), headOn = true)
    body.layout()
    pump()
    check headH > 0 and headH < int(r.bottom) div 2
    check IsWindowVisible(head.hwnd) != 0
    let before = bs.mapIt(inMain(it))
    body.scrollTo(1_000_000)
    pump()
    check inMain(first).top < 0                      # the panel did scroll: its first line is above the window
    for i, b in bs:
      let now = inMain(b)
      check now == before[i]                         # the buttons didn't move
      check now.top >= 0 and now.bottom <= headH     # and are inside the heading, at the top of the window
      # the main window's child at the button's middle is the heading's page: nothing of the panel covers it
      check ChildWindowFromPoint(main, POINT(x: (now.left + now.right) div 2, y: (now.top + now.bottom) div 2)) == head.hwnd

  test "without the heading the panel takes the whole column":
    let head = newPage(main)
    let body = newPage(main)
    head.title("11LAB70AA501")
    body.label("a line")
    var r: RECT
    GetClientRect(main, addr r)
    check placeColumn(head, body, 0, 400, int(r.bottom), headOn = false) == 0
    check IsWindowVisible(head.hwnd) == 0
    check inMain(body.hwnd).top == 0
