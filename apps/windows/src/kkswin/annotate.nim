## The photo annotation editor (R6; v1's K.annotate, the GNOME and Android editors): arrow, box or circle in four
## colours, three line sizes, undo, a caption and a note for the approver; the marks are burned into the picture before
## it is encoded. Zoom: −/+/Fit, the wheel (at the pointer), two fingers (pinch, pan); the right button pans. Touch comes
## as WM_POINTER (Windows 8+): one finger draws and shows a loupe above it, the area under the finger magnified; pen
## and mouse draw without it.

import std/[tables, math, strutils]
from std/unicode import runeLen, toRunes, `$`   # strutils' strip: the core's own
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
proc viewClip(v: pointer, x0, y0, x1, y1: cfloat) {.importc: "kks_view_clip", cdecl.}
proc viewUnclip(v: pointer) {.importc: "kks_view_unclip", cdecl.}

type
  Mark* {.bycopy.} = object      ## kks_d2d.cpp's struct Mark
    kind*: cint                  ## 0 arrow, 1 box, 2 circle
    rgb*: cuint
    x0*, y0*, x1*, y1*: cfloat   ## image px
    size*: cfloat                ## × the base line width
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
    size: cfloat
    page: Page
    zoom, cx, cy: float          ## the image point at the canvas centre; canvas px per image px = fit · zoom
    touches: Table[uint32, (float, float)]   ## touch contacts down (canvas px)
    drawId: uint32               ## the contact (or 0 for the mouse) drawing now
    touching: bool               ## a finger draws: the loupe at (fx, fy)
    fx, fy: float
    pinchD, pinchZ: float        ## two fingers: the distance and zoom when they started
    pinchM: (float, float)
    panning: bool                ## the right button moves the view
    panAt: (float, float)

proc burnMarks(rgba: pointer, w, h: cint, marks: ptr Mark, n: cint): cint {.importc: "kks_burn_marks", cdecl.}

const Colors = [(0xE53935'u32, "Red"), (0xFDD835'u32, "Yellow"), (0x1E88E5'u32, "Blue"), (0xFFFFFF'u32, "White")]

var editors = initTable[HWND, Editor]()

proc canvasSize(e: Editor): (float, float) =
  var r: RECT
  GetClientRect(e.canvas, addr r)
  (float(r.right), float(r.bottom))

proc scaleOf(e: Editor): float =
  let (cw, ch) = e.canvasSize
  min(cw / float(e.w), ch / float(e.h)) * e.zoom

proc clampView(e: Editor) =
  let (cw, ch) = e.canvasSize
  let s = e.scaleOf
  let hw = cw / 2 / s
  let hh = ch / 2 / s
  e.cx = (if hw * 2 >= float(e.w): float(e.w) / 2 else: clamp(e.cx, hw, float(e.w) - hw))
  e.cy = (if hh * 2 >= float(e.h): float(e.h) / 2 else: clamp(e.cy, hh, float(e.h) - hh))

proc toImg(e: Editor, x, y: float): (float, float) =
  let (cw, ch) = e.canvasSize
  let s = e.scaleOf
  (e.cx + (x - cw / 2) / s, e.cy + (y - ch / 2) / s)

proc zoomAt(e: Editor, x, y, z: float) =
  let (ix, iy) = e.toImg(x, y)
  let (cw, ch) = e.canvasSize
  e.zoom = clamp(z, 1.0, 8.0)
  let s = e.scaleOf
  e.cx = ix - (x - cw / 2) / s
  e.cy = iy - (y - ch / 2) / s
  e.clampView()
  InvalidateRect(e.canvas, nil, 0)

proc paintMark(e: Editor, m: Mark, s, ox, oy: float) =
  ## a mark through the view: canvas px = (ox + x · s, oy + y · s)
  let a = (cfloat(ox + float(m.x0) * s), cfloat(oy + float(m.y0) * s))
  let b = (cfloat(ox + float(m.x1) * s), cfloat(oy + float(m.y1) * s))
  let sw = cfloat(max(3.0, float(e.w) / 200) * s * float(m.size))
  case m.kind
  of 1: viewRect(e.v, min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]), m.rgb, 1, 0, sw, 0)
  of 2: viewEllipse(e.v, a[0], a[1], b[0], b[1], m.rgb, sw)
  else:
    viewLine(e.v, a[0], a[1], b[0], b[1], m.rgb, sw)
    let ang = arctan2(float(b[1] - a[1]), float(b[0] - a[0]))
    let head = float(sw) * 5
    for d in [-0.5, 0.5]:
      viewLine(e.v, b[0], b[1], cfloat(float(b[0]) - head * cos(ang + d)), cfloat(float(b[1]) - head * sin(ang + d)), m.rgb, sw)

proc scene(e: Editor, s, ox, oy: float) =
  viewDrawBitmap(e.v, e.bmp, cfloat(ox), cfloat(oy), cfloat(ox + float(e.w) * s), cfloat(oy + float(e.h) * s), 1)
  for mk in e.marks: e.paintMark(mk, s, ox, oy)
  if e.drawing: e.paintMark(e.cur, s, ox, oy)

proc startMark(e: Editor, id: uint32, x, y: float) =
  let (ix, iy) = e.toImg(x, y)
  e.drawId = id
  e.drawing = true
  e.cur = Mark(kind: e.kind, rgb: e.color, x0: cfloat(ix), y0: cfloat(iy), x1: cfloat(ix), y1: cfloat(iy), size: e.size)

proc moveMark(e: Editor, x, y: float) =
  let (ix, iy) = e.toImg(x, y)
  e.cur.x1 = cfloat(ix)
  e.cur.y1 = cfloat(iy)

proc endMark(e: Editor) =
  if e.drawing and (abs(e.cur.x1 - e.cur.x0) + abs(e.cur.y1 - e.cur.y0)) * e.scaleOf > 6: e.marks.add e.cur
  e.drawing = false
  e.touching = false

proc canvasProc0(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT =
  let e = editors.getOrDefault(h)
  if e == nil: return DefWindowProcW(h, m, wp, lp)
  case m
  of WM_PAINT:
    var ps: PAINTSTRUCT
    discard BeginPaint(h, addr ps)
    if viewBegin(e.v, 0.15, 0.15, 0.17) != 0:
      if e.bmp == 0: e.bmp = viewBitmap(e.v, addr e.bgra[0], cint(e.w), cint(e.h))
      e.clampView()
      let (cw, ch) = e.canvasSize
      let s = e.scaleOf
      e.scene(s, cw / 2 - e.cx * s, ch / 2 - e.cy * s)
      if e.touching and e.drawing:     # the loupe: 2.5× the view around the finger, a square above it
        let r = 90.0
        let k = 2.5
        let lx = clamp(e.fx, r, cw - r)
        let ly = if e.fy - 40 - 2 * r >= 0: e.fy - 40 - r else: e.fy + 40 + r
        let (ix, iy) = e.toImg(e.fx, e.fy)
        viewClip(e.v, cfloat(lx - r), cfloat(ly - r), cfloat(lx + r), cfloat(ly + r))
        viewRect(e.v, cfloat(lx - r), cfloat(ly - r), cfloat(lx + r), cfloat(ly + r), 0, 1, 1, 0, 0)
        e.scene(s * k, lx - ix * s * k, ly - iy * s * k)
        viewLine(e.v, cfloat(lx - 10), cfloat(ly), cfloat(lx + 10), cfloat(ly), 0xFF7A1A, 1.5)
        viewLine(e.v, cfloat(lx), cfloat(ly - 10), cfloat(lx), cfloat(ly + 10), 0xFF7A1A, 1.5)
        viewUnclip(e.v)
        viewRect(e.v, cfloat(lx - r), cfloat(ly - r), cfloat(lx + r), cfloat(ly + r), 0xFF7A1A, 1, 0, 3, 0)
      if viewEnd(e.v) == 0: e.bmp = 0
    EndPaint(h, addr ps)
    return 0
  of WM_ERASEBKGND: return 1
  of WM_SIZE:
    viewResize(e.v, cint(loword(lp)), cint(hiword(lp)))
    InvalidateRect(h, nil, 0)
    return 0
  of WM_POINTERDOWN, WM_POINTERUPDATE, WM_POINTERUP:
    # touch and pen; handled here, Windows makes no mouse messages or system gestures of them
    let id = uint32(loword(int(wp)))
    var t: uint32
    if GetPointerType(id, addr t) == 0 or t notin [PT_TOUCH, PT_PEN]: return DefWindowProcW(h, m, wp, lp)
    var pt = POINT(x: sloword(lp), y: shiword(lp))
    ScreenToClient(h, addr pt)
    let (x, y) = (float(pt.x), float(pt.y))
    if m == WM_POINTERDOWN:
      e.touches[id] = (x, y)
      if e.touches.len == 2:          # a second finger: no mark, zoom and pan
        e.drawing = false
        e.touching = false
        var ps: seq[(float, float)]
        for p in e.touches.values: ps.add p
        e.pinchD = max(1.0, hypot(ps[0][0] - ps[1][0], ps[0][1] - ps[1][1]))
        e.pinchZ = e.zoom
        e.pinchM = ((ps[0][0] + ps[1][0]) / 2, (ps[0][1] + ps[1][1]) / 2)
      elif e.touches.len == 1:
        e.startMark(id, x, y)
        e.touching = t == PT_TOUCH
        e.fx = x
        e.fy = y
    elif m == WM_POINTERUPDATE:
      if id in e.touches:
        e.touches[id] = (x, y)
        if e.touches.len == 2:
          var ps: seq[(float, float)]
          for p in e.touches.values: ps.add p
          let mid = ((ps[0][0] + ps[1][0]) / 2, (ps[0][1] + ps[1][1]) / 2)
          e.zoomAt(mid[0], mid[1], e.pinchZ * hypot(ps[0][0] - ps[1][0], ps[0][1] - ps[1][1]) / e.pinchD)
          let s = e.scaleOf
          e.cx -= (mid[0] - e.pinchM[0]) / s
          e.cy -= (mid[1] - e.pinchM[1]) / s
          e.pinchM = mid
          e.clampView()
        elif e.drawing and id == e.drawId:
          e.moveMark(x, y)
          e.fx = x
          e.fy = y
    else:
      if id in e.touches: e.touches.del id
      if e.drawing and id == e.drawId:
        e.moveMark(x, y)
        e.endMark()
      if e.touches.len == 0: e.touching = false
    InvalidateRect(h, nil, 0)
    return 0
  of WM_LBUTTONDOWN, WM_MOUSEMOVE, WM_LBUTTONUP, WM_RBUTTONDOWN, WM_RBUTTONUP:
    let (x, y) = (float(sloword(lp)), float(shiword(lp)))
    case m
    of WM_LBUTTONDOWN:
      SetCapture(h)
      e.startMark(0, x, y)
    of WM_RBUTTONDOWN:
      SetCapture(h)
      e.panning = true
      e.panAt = (x, y)
    of WM_RBUTTONUP:
      ReleaseCapture()
      e.panning = false
    of WM_MOUSEMOVE:
      if e.panning:
        let s = e.scaleOf
        e.cx -= (x - e.panAt[0]) / s
        e.cy -= (y - e.panAt[1]) / s
        e.panAt = (x, y)
        e.clampView()
      elif e.drawing and e.drawId == 0: e.moveMark(x, y)
    else:
      if e.drawing and e.drawId == 0:
        ReleaseCapture()
        e.moveMark(x, y)
        e.endMark()
    InvalidateRect(h, nil, 0)
    return 0
  of WM_MOUSEWHEEL:
    var pt = POINT(x: sloword(lp), y: shiword(lp))      # screen px
    ScreenToClient(h, addr pt)
    e.zoomAt(float(pt.x), float(pt.y), e.zoom * exp(float(shiword(int(wp))) / 120 * 0.25))
    return 0
  else: discard
  DefWindowProcW(h, m, wp, lp)

proc canvasProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  try: canvasProc0(h, m, wp, lp)
  except CatchableError as ex:
    report(ex)
    0

var classDone = false

const
  MaxCaption* = 500   ## the core refuses a photo's caption over 500 characters (core/src/kks/api.nim, "caption")
  MaxNote* = 500      ## and a note for the approver over 500 (api.nim submitPrep): such a photo could never be sent
  EM_LIMITTEXT = 0x00C5'u32

proc capText*(s: string, n: int): string =
  ## at most n characters (code points, as the core counts them)
  if s.runeLen <= n: s else: $s.toRunes[0 ..< n]

proc annotate*(owner: HWND, rgba: seq[byte], w, h: int, done: proc (rgba: seq[byte], caption, note: string), askNote: bool,
               captionMax = MaxCaption) =
  ## opens the editor; `done` gets the picture with the marks burned in. The caption and the note are capped as they
  ## are typed (EM_LIMITTEXT counts UTF-16 units: never more characters than the core takes) and cut again when sent
  ## (a value set from outside, e.g. UI Automation, isn't capped by the field)
  if not classDone:
    let cls = newWideCString("KKSAnnotateCanvas")
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: canvasProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_CROSS), lpszClassName: cls)
    discard RegisterClassExW(addr wc)
    classDone = true
  let e = Editor(w: w, h: h, rgba: rgba, kind: 0, color: Colors[0][0], size: 1, zoom: 1, cx: float(w) / 2, cy: float(h) / 2)
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
  page.dim("Drag on the photo to draw (tool, colour and line size below). The wheel or two fingers zoom; the right button or two fingers move.")
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
  page.buttons(("Thin lines", proc () = e.size = 0.6), ("Medium lines", proc () = e.size = 1), ("Thick lines", proc () = e.size = 1.8),
               ("Zoom out", proc () =
                 let (cw, ch) = e.canvasSize
                 e.zoomAt(cw / 2, ch / 2, e.zoom / 1.5)),
               ("Zoom in", proc () =
                 let (cw, ch) = e.canvasSize
                 e.zoomAt(cw / 2, ch / 2, e.zoom * 1.5)),
               ("Fit", proc () =
                 e.zoom = 1
                 e.clampView()
                 InvalidateRect(e.canvas, nil, 0)))
  let cap = page.field("Caption (optional)", "")
  let note = if askNote: page.field("Note for the approver (optional)", "") else: nil
  SendMessageW(cap, EM_LIMITTEXT, WPARAM(captionMax), 0)
  if note != nil: SendMessageW(note, EM_LIMITTEXT, WPARAM(MaxNote), 0)
  page.buttons(("Send", proc () =
    var marked = e.rgba
    if e.marks.len > 0:
      discard burnMarks(addr marked[0], cint(e.w), cint(e.h), addr e.marks[0], cint(e.marks.len))
    let c = capText(cap.text.strip, captionMax)
    let n = capText((if note != nil: note.text else: "").strip, MaxNote)
    DestroyWindow(hw)
    done(marked, c, n)), ("Cancel", proc () = DestroyWindow(hw)))
  page.layout()
  ShowWindow(hw, SW_SHOW)
