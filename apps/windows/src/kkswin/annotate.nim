## The photo annotation editor (R6; v1's K.annotate, the GNOME and Android editors): arrow, box or circle in four
## colours, undo, a caption and a note for the approver; the marks are burned into the picture before it is encoded.

import std/[tables, math]
import w32, ui

proc viewNew(h: HWND): pointer {.importc: "kks_view_new", cdecl.}
proc viewFree(v: pointer) {.importc: "kks_view_free", cdecl.}
proc viewResize(v: pointer, w, h: cint) {.importc: "kks_view_resize", cdecl.}
proc viewBitmap(v: pointer, bgra: pointer, w, h: cint): cint {.importc: "kks_view_bitmap", cdecl.}
proc viewBegin(v: pointer, r, g, b: cfloat): cint {.importc: "kks_view_begin", cdecl.}
proc viewDrawBitmap(v: pointer, h: cint, x0, y0, x1, y1: cfloat, smooth: cint) {.importc: "kks_view_draw_bitmap", cdecl.}
proc viewRect(v: pointer, x0, y0, x1, y1: cfloat, rgb: cuint, alpha: cfloat, fill: cint, width: cfloat, dashed: cint) {.importc: "kks_view_rect", cdecl.}
proc viewLine(v: pointer, x0, y0, x1, y1: cfloat, rgb: cuint, width: cfloat) {.importc: "kks_view_line", cdecl.}
proc viewEllipse(v: pointer, x0, y0, x1, y1: cfloat, rgb: cuint, width: cfloat) {.importc: "kks_view_ellipse", cdecl.}
proc viewEnd(v: pointer): cint {.importc: "kks_view_end", cdecl.}

type
  Mark* {.bycopy.} = object      ## kks_d2d.cpp's struct Mark
    kind*: cint                  ## 0 arrow, 1 box, 2 circle
    rgb*: cuint
    x0*, y0*, x1*, y1*: cfloat   ## image px
  Editor = ref object
    hwnd, canvas: HWND
    v: pointer
    w, h: int
    rgba: seq[byte]
    bgra: seq[byte]              ## premultiplied, for the screen
    bmp: cint
    marks: seq[Mark]
    drawing: bool
    cur: Mark
    kind: cint
    color: cuint
    page: Page

proc burnMarks(rgba: pointer, w, h: cint, marks: ptr Mark, n: cint): cint {.importc: "kks_burn_marks", cdecl.}

const Colors = [(0xE53935'u32, "Red"), (0xFDD835'u32, "Yellow"), (0x1E88E5'u32, "Blue"), (0xFFFFFF'u32, "White")]

var editors = initTable[HWND, Editor]()

proc fitOf(e: Editor): (float, float, float) =
  var r: RECT
  GetClientRect(e.canvas, addr r)
  let s = min(float(r.right) / float(e.w), float(r.bottom) / float(e.h))
  (s, (float(r.right) - float(e.w) * s) / 2, (float(r.bottom) - float(e.h) * s) / 2)

proc paintMark(e: Editor, m: Mark) =
  let (s, ox, oy) = e.fitOf
  let a = (cfloat(ox + float(m.x0) * s), cfloat(oy + float(m.y0) * s))
  let b = (cfloat(ox + float(m.x1) * s), cfloat(oy + float(m.y1) * s))
  let sw = cfloat(max(3.0, float(e.w) / 200 * s))
  case m.kind
  of 1: viewRect(e.v, min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]), m.rgb, 1, 0, sw, 0)
  of 2: viewEllipse(e.v, a[0], a[1], b[0], b[1], m.rgb, sw)
  else:
    viewLine(e.v, a[0], a[1], b[0], b[1], m.rgb, sw)
    let ang = arctan2(float(b[1] - a[1]), float(b[0] - a[0]))
    let head = float(sw) * 5
    for d in [-0.5, 0.5]:
      viewLine(e.v, b[0], b[1], cfloat(float(b[0]) - head * cos(ang + d)), cfloat(float(b[1]) - head * sin(ang + d)), m.rgb, sw)

proc canvasProc0(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT =
  let e = editors.getOrDefault(h)
  if e == nil: return DefWindowProcW(h, m, wp, lp)
  case m
  of WM_PAINT:
    var ps: PAINTSTRUCT
    discard BeginPaint(h, addr ps)
    if viewBegin(e.v, 0.15, 0.15, 0.17) != 0:
      if e.bmp == 0: e.bmp = viewBitmap(e.v, addr e.bgra[0], cint(e.w), cint(e.h))
      let (s, ox, oy) = e.fitOf
      viewDrawBitmap(e.v, e.bmp, cfloat(ox), cfloat(oy), cfloat(ox + float(e.w) * s), cfloat(oy + float(e.h) * s), 1)
      for mk in e.marks: e.paintMark(mk)
      if e.drawing: e.paintMark(e.cur)
      if viewEnd(e.v) == 0: e.bmp = 0
    EndPaint(h, addr ps)
    return 0
  of WM_ERASEBKGND: return 1
  of WM_SIZE:
    viewResize(e.v, cint(loword(lp)), cint(hiword(lp)))
    InvalidateRect(h, nil, 0)
    return 0
  of WM_LBUTTONDOWN, WM_MOUSEMOVE, WM_LBUTTONUP:
    let (s, ox, oy) = e.fitOf
    let x = cfloat((float(sloword(lp)) - ox) / s)
    let y = cfloat((float(shiword(lp)) - oy) / s)
    if m == WM_LBUTTONDOWN:
      SetCapture(h)
      e.drawing = true
      e.cur = Mark(kind: e.kind, rgb: e.color, x0: x, y0: y, x1: x, y1: y)
    elif e.drawing:
      e.cur.x1 = x
      e.cur.y1 = y
      if m == WM_LBUTTONUP:
        ReleaseCapture()
        e.drawing = false
        if abs(e.cur.x1 - e.cur.x0) + abs(e.cur.y1 - e.cur.y0) > 3: e.marks.add e.cur
    InvalidateRect(h, nil, 0)
    return 0
  else: discard
  DefWindowProcW(h, m, wp, lp)

proc canvasProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  try: canvasProc0(h, m, wp, lp)
  except CatchableError as ex:
    report(ex)
    0

var classDone = false

proc annotate*(owner: HWND, rgba: seq[byte], w, h: int, done: proc (rgba: seq[byte], caption, note: string), askNote: bool) =
  ## opens the editor; `done` gets the picture with the marks burned in
  if not classDone:
    let cls = newWideCString("KKSAnnotateCanvas")
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: canvasProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_CROSS), lpszClassName: cls)
    discard RegisterClassExW(addr wc)
    classDone = true
  let e = Editor(w: w, h: h, rgba: rgba, kind: 0, color: Colors[0][0])
  e.bgra = newSeq[byte](rgba.len)
  for i in countup(0, rgba.len - 4, 4):
    let a = int(rgba[i + 3])
    e.bgra[i] = byte(int(rgba[i + 2]) * a div 255)
    e.bgra[i + 1] = byte(int(rgba[i + 1]) * a div 255)
    e.bgra[i + 2] = byte(int(rgba[i]) * a div 255)
    e.bgra[i + 3] = byte(a)
  var hw: HWND
  let (pw, page) = popup(owner, "Mark up the photo", 1000, 860, proc () =
    if e.canvas != nil:
      editors.del e.canvas)
  hw = pw
  e.hwnd = hw
  e.page = page
  e.canvas = CreateWindowExW(0, newWideCString("KKSAnnotateCanvas"), newWideCString("Photo to mark up"),
                             WS_CHILD or WS_VISIBLE, 0, 0, 10, 10, page.hwnd, nil, hinst, nil)
  e.v = viewNew(e.canvas)
  editors[e.canvas] = e
  page.custom(e.canvas, 520)
  page.dim("Drag on the photo to draw. Tool and colour below.")
  page.buttons(("Arrow", proc () = e.kind = 0), ("Box", proc () = e.kind = 1), ("Circle", proc () = e.kind = 2),
               ("Undo", proc () =
                 if e.marks.len > 0: e.marks.setLen(e.marks.len - 1)
                 InvalidateRect(e.canvas, nil, 0)))
  var specs: seq[(string, proc ())]
  for ci in 0 ..< Colors.len:
    closureScope:
      let c = Colors[ci][0]
      specs.add (Colors[ci][1], proc () = e.color = c)
  page.buttons(specs)
  let cap = page.field("Caption (optional)", "")
  let note = if askNote: page.field("Note for the approver (optional)", "") else: nil
  page.buttons(("Send", proc () =
    var marked = e.rgba
    if e.marks.len > 0:
      discard burnMarks(addr marked[0], cint(e.w), cint(e.h), addr e.marks[0], cint(e.marks.len))
    let c = cap.text
    let n = if note != nil: note.text else: ""
    DestroyWindow(hw)
    done(marked, c, n)), ("Cancel", proc () = DestroyWindow(hw)))
  page.layout()
  ShowWindow(hw, SW_SHOW)
