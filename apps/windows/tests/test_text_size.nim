## Text size in the Windows app (#377): the fonts follow a scale change while the app runs (the status line kept the
## old scale's font, found on a real laptop 2026-11-18), and Windows' text size (switch win-text-size; KKS_TEST_TEXT_SCALE
## stands in for it) makes the fonts and the heights made for text larger, so nothing is cut off: every label, field,
## button, check box and list's text fits its control, and no two controls overlap, at 150 % and 200 % text and at
## 100 % and 200 % scaling. Switched off, the text size is 1. Real windows and fonts, so it runs on Windows (CI's
## windows-test):
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_text_size.exe apps/windows/tests/test_text_size.nim
import std/[unittest, os, strutils]
import kkswin/[w32, ui]

const H = "<windows.h>"
proc GetDC(h: HWND): HDC {.importc, stdcall, header: H.}
proc ReleaseDC(h: HWND, dc: HDC): int32 {.importc, stdcall, header: H, discardable.}
proc SelectObject(dc: HDC, o: HGDIOBJ): HGDIOBJ {.importc, stdcall, header: H, discardable.}
proc DrawTextW(dc: HDC, s: WideCString, n: int32, r: ptr RECT, f: UINT): int32 {.importc, stdcall, header: H.}
type TEXTMETRICW {.importc, header: H.} = object
  tmHeight: int32
proc GetTextMetricsW(dc: HDC, tm: ptr TEXTMETRICW): BOOL {.importc, stdcall, header: H.}

proc GetWindowLongPtrW(h: HWND, i: int32): int {.importc, stdcall, header: H.}
type
  CHARRANGE {.importc, header: "<richedit.h>".} = object
    cpMin, cpMax: int32
  CHARFORMAT2W {.importc, header: "<richedit.h>".} = object
    cbSize: UINT
    dwMask: DWORD
    dwEffects: DWORD

var main: HWND

proc mainProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  if m == WM_COMMAND and dispatchCommand(wp, lp): return 0
  DefWindowProcW(h, m, wp, lp)

proc pump() =
  var msg: MSG
  while PeekMessageW(addr msg, nil, 0, 0, 1) != 0:
    TranslateMessage(addr msg)
    DispatchMessageW(addr msg)

proc fontOf(h: HWND): HFONT = cast[HFONT](SendMessageW(h, WM_SETFONT + 1, 0, 0))   # WM_GETFONT

proc cls(h: HWND): string =
  var b = newWideCString("", 64)
  discard GetClassNameW(h, b, 64)
  ($b).toLowerAscii

proc lineH(h: HWND): int =
  let dc = GetDC(h)
  SelectObject(dc, fontOf(h))
  var tm: TEXTMETRICW
  discard GetTextMetricsW(dc, addr tm)
  ReleaseDC(h, dc)
  int(tm.tmHeight)

proc needed(h: HWND, width: int, wrap: bool): (int, int) =
  ## the size the control's text needs in its own font (wrapped at `width`)
  let dc = GetDC(h)
  SelectObject(dc, fontOf(h))
  var r = RECT(left: 0, top: 0, right: int32(width), bottom: 0)
  discard DrawTextW(dc, newWideCString(h.text), -1, addr r, 0x400'u32 or (if wrap: 0x10'u32 else: 0x20'u32))  # DT_CALCRECT, WORDBREAK / SINGLELINE
  ReleaseDC(h, dc)
  (int(r.right), int(r.bottom))

proc client(h: HWND): RECT =
  doAssert GetClientRect(h, addr result) != 0

proc inParent(c: HWND): RECT =
  var r: RECT
  doAssert GetWindowRect(c, addr r) != 0
  var a = POINT(x: r.left, y: r.top)
  var b = POINT(x: r.right, y: r.bottom)
  let p = GetParent(c)
  ScreenToClient(p, addr a)
  ScreenToClient(p, addr b)
  RECT(left: a.x, top: a.y, right: b.x, bottom: b.y)

hinst = GetModuleHandleW(nil)
makeFonts(96)
block:
  let c = newWideCString("KKSTestTextSize")
  var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: mainProc, hInstance: hinst,
                       hbrBackground: GetSysColorBrush(COLOR_WINDOW), lpszClassName: c)
  discard RegisterClassExW(addr wc)
  main = CreateWindowExW(WS_EX_CONTROLPARENT, c, newWideCString("text size test"), WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN,
                         0, 0, 900, 900, nil, nil, hinst, nil)
  doAssert main != nil
  ShowWindow(main, SW_SHOW)
  ShowWindow(main, SW_SHOW)

proc longer(t: string, long: bool): string =
  ## the text 40 % longer (L3: another language, a longer name), still in words
  if not long: return t
  result = t
  while result.len < t.len * 14 div 10: result.add " and more"

proc page(long = false): (Page, seq[HWND]) =
  ## a page like the app's: every kind of control with text, at the sidebar's width (380 DIPs); `long`: every text
  ## 40 % longer
  let p = newPage(main)
  MoveWindow(p.hwnd, 0, 0, px(380), 3000, 1)
  var hs: seq[HWND]
  hs.add p.title(longer("Sheets and procedures", long))
  hs.add p.label(longer("A label long enough to wrap onto a second line in the sidebar of the app at any size", long))
  hs.add p.dim(longer("Secondary text: Enter or double-click a result to show it on its drawing.", long))
  hs.add p.field(longer("Search equipment by KKS code or description", long), "11LAB70AA500")
  hs.add p.multiField("Note", "A note\r\non two lines", 60)
  hs.add p.buttons((longer("Equipment by system…", long), proc () = discard), (longer("Coverage…", long), proc () = discard))
  hs.add p.check(longer("Colour tags by photos", long), false, proc (on: bool) = discard)
  hs.add p.radios(@["Follow theme", "Always dark"], 0, proc (i: int) = discard)
  hs.add p.list(@["Sample sheet  (1 tags)", "Another sheet  (12 tags)"], 26 * 2 + 6)
  let answer: proc () = proc () = discard
  hs.add p.tallButtons(@[(longer("A long answer that wraps onto more lines than one in the sidebar", long), answer)])
  p.layout()
  pump()
  (p, hs)

proc FindWindowExW(parent, after: HWND, cls, title: WideCString): HWND {.importc, stdcall, header: H.}

proc checkFits(p: Page, made: seq[HWND], what: string) =
  # every control of the page, the fields' labels too
  var hs: seq[HWND]
  var c = FindWindowExW(p.hwnd, nil, nil, nil)
  while c != nil:
    hs.add c
    c = FindWindowExW(p.hwnd, c, nil, nil)
  check hs.len > made.len
  for i, h in hs:
    let r = client(h)
    let c = cls(h)
    let style = uint32(GetWindowLongPtrW(h, -16))
    checkpoint(what & ": " & c & " \"" & h.text & "\" " & $r)
    case c
    of "static":
      let (_, nh) = needed(h, int(r.right), wrap = true)
      check nh <= int(r.bottom)                                    # every line of it shown
    of "edit":
      check lineH(h) <= int(r.bottom)                              # a whole line of text in the field
    of "button":
      if (style and 0xF) in [3'u32, 9'u32]:                        # check box, radio button: the box and the text
        if (style and 0x2000) != 0:                                # (its lines wrapped beside the box)
          let (_, nh) = needed(h, int(r.right) - int(px(24)), wrap = true)
          check nh <= int(r.bottom)
        else:
          let (nw, nh) = needed(h, 0, wrap = false)
          check nh <= int(r.bottom)
          check nw + px(20) <= int(r.right)
      elif (style and 0x2000) != 0:                                # BS_MULTILINE
        let (_, nh) = needed(h, int(r.right) - int(px(28)), wrap = true)
        check nh <= int(r.bottom)
      else:
        let (nw, nh) = needed(h, 0, wrap = false)
        check nh <= int(r.bottom)
        check nw <= int(r.right)
    of "listbox":
      check int(SendMessageW(h, 0x01A1'u32, 0, 0)) >= lineH(h)      # LB_GETITEMHEIGHT: a row holds a line
      check int(r.bottom) >= 2 * lineH(h)                          # both rows in view
    else: discard
    # no two controls overlap
    let a = inParent(h)
    for j in 0 ..< i:
      let b = inParent(hs[j])
      check a.top >= b.bottom or b.top >= a.bottom or a.left >= b.right or b.left >= a.right


suite "fonts after a scale change":
  test "every control takes the new fonts, the main window's status line too":
    let status = control(main, "STATIC", "Last sync 10:23", SS_LEFT or SS_NOPREFIX)[0]
    let (p, hs) = page()
    makeFonts(144)              # (as WM_DPICHANGED does: 150 % scaling while the app runs)
    check fontOf(status) == fontNormal
    check fontOf(hs[1]) == fontNormal
    check fontOf(hs[0]) == fontTitle
    check fontOf(hs[2]) == fontSmall
    check lineH(status) > 20    # (the 150 % font, not the 100 % one)
    p.destroy()
    DestroyWindow(status)
    makeFonts(96)

suite "Windows' text size":
  test "switched off, the text size is 1 (as released)":
    putEnv("KKS_TEST_TEXT_SCALE", "1.5")
    check systemTextScale() == 1.0
    check not refreshTextScale()
    check textScale == 1.0

  test "at 100 % text the heights are as before":
    check tx(28) == px(28)
    check txp(48, 8) == px(56)

  test "nothing cut off or overlapping at 150 % and 200 % text, 100 % and 200 % scaling":
    putEnv("KKS_UX", TextSizeSwitch)
    let normal100 = block:
      let (p, hs) = page()
      let h = lineH(hs[1])
      p.destroy()
      h
    for d in [96, 192]:
      for s in ["1.5", "2"]:
        putEnv("KKS_TEST_TEXT_SCALE", s)
        textScale = 1.0
        makeFonts(d)
        check refreshTextScale()
        check textScale == parseFloat(s)
        let (p, hs) = page()
        check lineH(hs[1]) >= int(float(normal100) * parseFloat(s) * float(d) / 96 * 0.9)   # the text is larger
        checkFits(p, hs, s & " text at " & $d & " dpi")
        p.destroy()

  test "40 % longer text at 200 % text and 200 % scaling: still nothing cut off (L3)":
    putEnv("KKS_TEST_TEXT_SCALE", "2")
    textScale = 1.0
    makeFonts(192)
    check refreshTextScale()
    let (p, hs) = page(long = true)
    checkFits(p, hs, "longer text at 200 %")
    p.destroy()
    makeFonts(96)

  test "rich text keeps its own fonts through a scale change (bold, sizes, Consolas: only zoomed)":
    putEnv("KKS_TEST_TEXT_SCALE", "1")
    textScale = 1.0
    makeFonts(96)
    let p = newPage(main)
    MoveWindow(p.hwnd, 0, 0, px(380), 600, 1)
    let r = p.rich("{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Segoe UI;}{\\f1 Consolas;}}\\f0\\fs22 plain {\\b bold} {\\f1 mono}}")
    p.layout()
    pump()
    proc boldAt(pos: int): bool =
      var sel = CHARRANGE(cpMin: int32(pos), cpMax: int32(pos + 1))
      SendMessageW(r, 0x0437'u32, 0, cast[LPARAM](addr sel))          # EM_EXSETSEL
      var cf = CHARFORMAT2W(cbSize: UINT(sizeof(CHARFORMAT2W)))
      SendMessageW(r, 0x043A'u32, 1, cast[LPARAM](addr cf))            # EM_GETCHARFORMAT, SCF_SELECTION
      (cf.dwEffects and 1) != 0                                        # CFE_BOLD
    check boldAt(7)            # "bold"
    check not boldAt(1)
    makeFonts(144)             # (a scale change while the app runs)
    pump()
    check boldAt(7)
    check not boldAt(1)
    p.destroy()
    makeFonts(96)

  test "a text size change while the app runs: the page's controls follow":
    putEnv("KKS_TEST_TEXT_SCALE", "1")
    textScale = 1.0
    makeFonts(96)
    let (p, hs) = page()
    let before = lineH(hs[1])
    putEnv("KKS_TEST_TEXT_SCALE", "1.5")
    check refreshTextScale()
    pump()
    check fontOf(hs[1]) == fontNormal
    check lineH(hs[1]) > before
    checkFits(p, hs, "after the change")
    p.destroy()
