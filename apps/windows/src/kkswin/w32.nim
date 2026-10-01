## Hand-written Win32 bindings for the Windows app (decisions 0027, 0033): only what the app uses. The `header` pragma
## lets the C compiler check them against mingw-w64's headers.

{.passC: "-DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN -D_WIN32_WINNT=0x0A00".}
{.passL: "-luser32 -lgdi32 -lcomctl32 -lcomdlg32 -lshell32 -lole32 -luuid -ld2d1 -lwindowscodecs -luxtheme -ldwmapi".}

const H = "<windows.h>"

type
  HWND* = pointer
  HMENU* = pointer
  HINSTANCE* = pointer
  HFONT* = pointer
  HDC* = pointer
  HBRUSH* = pointer
  HICON* = pointer
  HCURSOR* = pointer
  HGDIOBJ* = pointer
  WPARAM* = uint
  LPARAM* = int
  LRESULT* = int
  UINT* = uint32
  DWORD* = uint32
  BOOL* = int32
  ATOM* = uint16
  WNDPROC* = proc (h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT {.stdcall.}

  POINT* {.importc, header: H.} = object
    x*, y*: int32
  RECT* {.importc, header: H.} = object
    left*, top*, right*, bottom*: int32
  MSG* {.importc, header: H.} = object
    hwnd*: HWND
    message*: UINT
    wParam*: WPARAM
    lParam*: LPARAM
    time*: DWORD
    pt*: POINT
  WNDCLASSEXW* {.importc, header: H.} = object
    cbSize*: UINT
    style*: UINT
    lpfnWndProc*: WNDPROC
    cbClsExtra*, cbWndExtra*: int32
    hInstance*: HINSTANCE
    hIcon*: HICON
    hCursor*: HCURSOR
    hbrBackground*: HBRUSH
    lpszMenuName*: WideCString
    lpszClassName*: WideCString
    hIconSm*: HICON
  SCROLLINFO* {.importc, header: H.} = object
    cbSize*, fMask*: UINT
    nMin*, nMax*: int32
    nPage*: UINT
    nPos*, nTrackPos*: int32
  LOGFONTW* {.importc, header: H.} = object
    lfHeight*: int32
    lfWeight*: int32
  NONCLIENTMETRICSW* {.importc, header: H.} = object
    cbSize*: UINT
    lfMessageFont*: LOGFONTW
  PAINTSTRUCT* {.importc, header: H.} = object
    hdc*: HDC
  OPENFILENAMEW* {.importc, header: "<commdlg.h>".} = object
    lStructSize*: DWORD
    hwndOwner*: HWND
    lpstrFilter*: WideCString
    lpstrFile*: WideCString
    nMaxFile*: DWORD
    lpstrTitle*: WideCString
    Flags*: DWORD
    lpstrDefExt*: WideCString

const
  WS_OVERLAPPEDWINDOW* = 0x00CF0000'u32
  WS_CHILD* = 0x40000000'u32
  WS_VISIBLE* = 0x10000000'u32
  WS_TABSTOP* = 0x00010000'u32
  WS_GROUP* = 0x00020000'u32
  WS_BORDER* = 0x00800000'u32
  WS_VSCROLL* = 0x00200000'u32
  WS_HSCROLL* = 0x00100000'u32
  WS_CLIPCHILDREN* = 0x02000000'u32
  WS_CLIPSIBLINGS* = 0x04000000'u32
  WS_EX_CLIENTEDGE* = 0x00000200'u32
  WS_EX_CONTROLPARENT* = 0x00010000'u32
  ES_AUTOHSCROLL* = 0x0080'u32
  ES_AUTOVSCROLL* = 0x0040'u32
  ES_MULTILINE* = 0x0004'u32
  ES_PASSWORD* = 0x0020'u32
  ES_READONLY* = 0x0800'u32
  ES_WANTRETURN* = 0x1000'u32
  BS_PUSHBUTTON* = 0x0'u32
  BS_DEFPUSHBUTTON* = 0x1'u32
  BS_AUTOCHECKBOX* = 0x3'u32
  SS_LEFT* = 0x0'u32
  SS_NOPREFIX* = 0x80'u32
  SS_EDITCONTROL* = 0x2000'u32
  LBS_NOTIFY* = 0x0001'u32
  LBS_NOINTEGRALHEIGHT* = 0x0100'u32
  CW_USEDEFAULT* = low(int32)
  SW_SHOW* = 5'i32
  SW_HIDE* = 0'i32
  WM_CREATE* = 0x0001'u32
  WM_DESTROY* = 0x0002'u32
  WM_SIZE* = 0x0005'u32
  WM_SETFOCUS* = 0x0007'u32
  WM_PAINT* = 0x000F'u32
  WM_CLOSE* = 0x0010'u32
  WM_ERASEBKGND* = 0x0014'u32
  WM_SETFONT* = 0x0030'u32
  WM_GETOBJECT* = 0x003D'u32
  WM_NOTIFY* = 0x004E'u32
  WM_KEYDOWN* = 0x0100'u32
  WM_CHAR* = 0x0102'u32
  WM_COMMAND* = 0x0111'u32
  WM_TIMER* = 0x0113'u32
  WM_HSCROLL* = 0x0114'u32
  WM_VSCROLL* = 0x0115'u32
  WM_CTLCOLORSTATIC* = 0x0138'u32
  WM_MOUSEMOVE* = 0x0200'u32
  WM_LBUTTONDOWN* = 0x0201'u32
  WM_LBUTTONUP* = 0x0202'u32
  WM_LBUTTONDBLCLK* = 0x0203'u32
  WM_MOUSEWHEEL* = 0x020A'u32
  WM_MOUSELEAVE* = 0x02A3'u32
  WM_DPICHANGED* = 0x02E0'u32
  WM_APP* = 0x8000'u32
  EM_SETCUEBANNER* = 0x1501'u32
  EM_SETSEL* = 0x00B1'u32
  LB_ADDSTRING* = 0x0180'u32
  LB_RESETCONTENT* = 0x0184'u32
  LB_GETCURSEL* = 0x0188'u32
  LB_SETCURSEL* = 0x0186'u32
  LB_GETCOUNT* = 0x018B'u32
  LBN_SELCHANGE* = 1'u32
  LBN_DBLCLK* = 2'u32
  EN_CHANGE* = 0x0300'u32
  BN_CLICKED* = 0'u32
  BM_GETCHECK* = 0x00F0'u32
  BM_SETCHECK* = 0x00F1'u32
  SB_VERT* = 1'i32
  SIF_ALL* = 0x17'u32
  SB_LINEUP* = 0
  SB_LINEDOWN* = 1
  SB_PAGEUP* = 2
  SB_PAGEDOWN* = 3
  SB_THUMBTRACK* = 5
  SB_THUMBPOSITION* = 4
  CS_HREDRAW* = 0x2'u32
  CS_VREDRAW* = 0x1'u32
  CS_DBLCLKS* = 0x8'u32
  IDC_ARROW* = 32512
  IDC_CROSS* = 32515
  COLOR_WINDOW* = 5
  MB_OK* = 0x0'u32
  MB_OKCANCEL* = 0x1'u32
  MB_ICONWARNING* = 0x30'u32
  MB_ICONQUESTION* = 0x20'u32
  IDOK* = 1'i32
  SPI_GETNONCLIENTMETRICS* = 0x0029'u32
  OFN_FILEMUSTEXIST* = 0x00001000'u32
  OFN_OVERWRITEPROMPT* = 0x00000002'u32
  OFN_EXPLORER* = 0x00080000'u32
  TME_LEAVE* = 0x2'u32
  VK_RETURN* = 0x0D
  VK_ESCAPE* = 0x1B
  VK_TAB* = 0x09
  MK_LBUTTON* = 0x1

proc GetModuleHandleW*(name: WideCString): HINSTANCE {.importc, stdcall, header: H.}
proc RegisterClassExW*(c: ptr WNDCLASSEXW): ATOM {.importc, stdcall, header: H.}
proc CreateWindowExW*(ex: DWORD, cls, title: WideCString, style: DWORD, x, y, w, h: int32, parent: HWND, menu: HMENU,
                      inst: HINSTANCE, param: pointer): HWND {.importc, stdcall, header: H.}
proc DestroyWindow*(h: HWND): BOOL {.importc, stdcall, header: H, discardable.}
proc DefWindowProcW*(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT {.importc, stdcall, header: H.}
proc ShowWindow*(h: HWND, cmd: int32): BOOL {.importc, stdcall, header: H, discardable.}
proc UpdateWindow*(h: HWND): BOOL {.importc, stdcall, header: H, discardable.}
proc GetMessageW*(m: ptr MSG, h: HWND, a, b: UINT): BOOL {.importc, stdcall, header: H.}
proc PeekMessageW*(m: ptr MSG, h: HWND, a, b, remove: UINT): BOOL {.importc, stdcall, header: H.}
proc TranslateMessage*(m: ptr MSG): BOOL {.importc, stdcall, header: H, discardable.}
proc DispatchMessageW*(m: ptr MSG): LRESULT {.importc, stdcall, header: H, discardable.}
proc IsDialogMessageW*(h: HWND, m: ptr MSG): BOOL {.importc, stdcall, header: H.}
proc PostQuitMessage*(code: int32) {.importc, stdcall, header: H.}
proc PostMessageW*(h: HWND, m: UINT, w: WPARAM, l: LPARAM): BOOL {.importc, stdcall, header: H, discardable.}
proc SendMessageW*(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT {.importc, stdcall, header: H, discardable.}
proc SetWindowTextW*(h: HWND, s: WideCString): BOOL {.importc, stdcall, header: H, discardable.}
proc GetWindowTextW*(h: HWND, s: WideCString, n: int32): int32 {.importc, stdcall, header: H.}
proc GetWindowTextLengthW*(h: HWND): int32 {.importc, stdcall, header: H.}
proc MoveWindow*(h: HWND, x, y, w, hh: int32, repaint: BOOL): BOOL {.importc, stdcall, header: H, discardable.}
proc GetClientRect*(h: HWND, r: ptr RECT): BOOL {.importc, stdcall, header: H, discardable.}
proc InvalidateRect*(h: HWND, r: ptr RECT, erase: BOOL): BOOL {.importc, stdcall, header: H, discardable.}
proc SetTimer*(h: HWND, id: uint, ms: UINT, f: pointer): uint {.importc, stdcall, header: H, discardable.}
proc KillTimer*(h: HWND, id: uint): BOOL {.importc, stdcall, header: H, discardable.}
proc LoadCursorW*(inst: HINSTANCE, name: int): HCURSOR {.importc: "LoadCursorW", stdcall, header: H.}
proc SetCursor*(c: HCURSOR): HCURSOR {.importc, stdcall, header: H, discardable.}
proc GetSysColorBrush*(i: int32): HBRUSH {.importc, stdcall, header: H.}
proc SetFocus*(h: HWND): HWND {.importc, stdcall, header: H, discardable.}
proc GetFocus*(): HWND {.importc, stdcall, header: H.}
proc EnableWindow*(h: HWND, on: BOOL): BOOL {.importc, stdcall, header: H, discardable.}
proc IsWindowVisible*(h: HWND): BOOL {.importc, stdcall, header: H.}
proc SetScrollInfo*(h: HWND, bar: int32, si: ptr SCROLLINFO, redraw: BOOL): int32 {.importc, stdcall, header: H, discardable.}
proc GetScrollInfo*(h: HWND, bar: int32, si: ptr SCROLLINFO): BOOL {.importc, stdcall, header: H, discardable.}
proc ScrollWindowEx*(h: HWND, dx, dy: int32, a, b: ptr RECT, rgn: pointer, upd: ptr RECT, flags: UINT): int32
  {.importc, stdcall, header: H, discardable.}
proc BeginPaint*(h: HWND, ps: ptr PAINTSTRUCT): HDC {.importc, stdcall, header: H.}
proc EndPaint*(h: HWND, ps: ptr PAINTSTRUCT): BOOL {.importc, stdcall, header: H, discardable.}
proc MessageBoxW*(h: HWND, text, title: WideCString, kind: UINT): int32 {.importc, stdcall, header: H.}
proc SystemParametersInfoW*(a: UINT, b: UINT, p: pointer, f: UINT): BOOL {.importc, stdcall, header: H, discardable.}
proc CreateFontIndirectW*(lf: ptr LOGFONTW): HFONT {.importc, stdcall, header: H.}
proc DeleteObject*(o: HGDIOBJ): BOOL {.importc, stdcall, header: H, discardable.}
proc GetDpiForWindow*(h: HWND): UINT {.importc, stdcall, header: H.}
proc SetProcessDpiAwarenessContext*(ctx: int): BOOL {.importc, stdcall, header: H, discardable.}
proc SetCapture*(h: HWND): HWND {.importc, stdcall, header: H, discardable.}
proc ReleaseCapture*(): BOOL {.importc, stdcall, header: H, discardable.}
proc ScreenToClient*(h: HWND, p: ptr POINT): BOOL {.importc, stdcall, header: H, discardable.}
proc GetParent*(h: HWND): HWND {.importc, stdcall, header: H.}
proc GetAncestor*(h: HWND, flags: UINT): HWND {.importc, stdcall, header: H.}
proc SetWindowLongPtrW*(h: HWND, i: int32, v: int): int {.importc, stdcall, header: H, discardable.}
proc GetWindowLongPtrW*(h: HWND, i: int32): int {.importc, stdcall, header: H.}
proc GetKeyState*(vk: int32): int16 {.importc, stdcall, header: H.}
proc GetOpenFileNameW*(o: ptr OPENFILENAMEW): BOOL {.importc, stdcall, header: "<commdlg.h>".}
proc GetSaveFileNameW*(o: ptr OPENFILENAMEW): BOOL {.importc, stdcall, header: "<commdlg.h>".}
proc OpenClipboard*(h: HWND): BOOL {.importc, stdcall, header: H.}
proc CloseClipboard*(): BOOL {.importc, stdcall, header: H, discardable.}
proc EmptyClipboard*(): BOOL {.importc, stdcall, header: H, discardable.}

type CommonControlsInit* {.importc: "INITCOMMONCONTROLSEX", header: "<commctrl.h>".} = object
  dwSize*, dwICC*: DWORD
proc InitCommonControlsEx*(i: ptr CommonControlsInit): BOOL {.importc, stdcall, header: "<commctrl.h>", discardable.}

const GWLP_USERDATA* = -21'i32

proc loword*(x: int): int = x and 0xFFFF
proc hiword*(x: int): int = (x shr 16) and 0xFFFF
proc sloword*(x: int): int32 = int32(cast[int16](uint16(x and 0xFFFF)))
proc shiword*(x: int): int32 = int32(cast[int16](uint16((x shr 16) and 0xFFFF)))

proc text*(h: HWND): string =
  let n = GetWindowTextLengthW(h)
  if n <= 0: return ""
  var buf = newWideCString("", n + 1)
  discard GetWindowTextW(h, buf, n + 1)
  $buf

proc setText*(h: HWND, s: string) = SetWindowTextW(h, newWideCString(s))

template sendText*(h: HWND, msg: UINT, w: WPARAM, s: string): LRESULT =
  ## a message whose LPARAM is a string: Nim 2's newWideCString is an object (length + pointer), so the pointer is
  ## taken explicitly and the string lives until the call returns (casting the object passed its length: a crash in
  ## comctl32, found on Windows 10)
  block:
    let ws = newWideCString(s)
    SendMessageW(h, msg, w, cast[LPARAM](toWideCString(ws)))
# courses (decision 0036)
proc SetForegroundWindow*(h: HWND): BOOL {.importc, stdcall, header: H, discardable.}
proc GetForegroundWindow*(): HWND {.importc, stdcall, header: H.}
proc GetWindowRect*(h: HWND, r: ptr RECT): BOOL {.importc, stdcall, header: H.}
proc ShellExecuteW*(h: HWND, op, file, params, dir: WideCString, show: int32): pointer {.importc, stdcall, header: "<shellapi.h>", discardable.}
