## A course figure on Windows (decision 0036): the core's evaluator, drawn by apps/common/figdraw.nim through the
## Direct2D/DirectWrite backend in kks_fig.cpp, in a child window named after the figure. A 16 ms timer is the clock;
## a figure scrolled out of its page is frozen (§9.6). The controls are ordinary page items built by the caller.

import std/[math, os, tables, times]
import kks/[json, courses]
import w32, ui, figdraw

{.compile("kks_fig.cpp", "-std=c++17").}
{.passL: "-ldwrite".}
proc figNew(h: HWND): pointer {.importc: "kks_fig_new", cdecl.}
proc figFree(p: pointer) {.importc: "kks_fig_free", cdecl.}
proc figResize(p: pointer, w, h: cint) {.importc: "kks_fig_resize", cdecl.}
proc figBegin(p: pointer, r, g, b, scale, ox: cfloat): cint {.importc: "kks_fig_begin", cdecl.}
proc figEnd(p: pointer): cint {.importc: "kks_fig_end", cdecl.}
proc figFonts(data: ptr pointer, sizes: ptr csize_t, n: cint): cint {.importc: "kks_fig_fonts", cdecl.}
proc fSave(p: pointer) {.importc: "kks_fig_save", cdecl.}
proc fRestore(p: pointer) {.importc: "kks_fig_restore", cdecl.}
proc fTranslate(p: pointer, x, y: cfloat) {.importc: "kks_fig_translate", cdecl.}
proc fRotate(p: pointer, a: cfloat) {.importc: "kks_fig_rotate", cdecl.}
proc fScale(p: pointer, x, y: cfloat) {.importc: "kks_fig_scale", cdecl.}
proc fPushOpacity(p: pointer, a: cfloat) {.importc: "kks_fig_push_opacity", cdecl.}
proc fPopOpacity(p: pointer) {.importc: "kks_fig_pop_opacity", cdecl.}
proc fClip(p: pointer, x, y, w, h, rx: cfloat) {.importc: "kks_fig_clip_round_rect", cdecl.}
proc fBegin(p: pointer) {.importc: "kks_fig_begin_path", cdecl.}
proc fMove(p: pointer, x, y: cfloat) {.importc: "kks_fig_move_to", cdecl.}
proc fLine(p: pointer, x, y: cfloat) {.importc: "kks_fig_line_to", cdecl.}
proc fCurve(p: pointer, x1, y1, x2, y2, x, y: cfloat) {.importc: "kks_fig_curve_to", cdecl.}
proc fClose(p: pointer) {.importc: "kks_fig_close", cdecl.}
proc fRoundRect(p: pointer, x, y, w, h, rx: cfloat) {.importc: "kks_fig_round_rect", cdecl.}
proc fEllipse(p: pointer, cx, cy, rx, ry: cfloat) {.importc: "kks_fig_ellipse", cdecl.}
proc fFill(p: pointer, r, g, b, a: cfloat) {.importc: "kks_fig_fill", cdecl.}
proc fFillRadial(p: pointer, cx, cy, rad: cfloat, stops: ptr cfloat, n: cint) {.importc: "kks_fig_fill_radial", cdecl.}
proc fStroke(p: pointer, r, g, b, a, w: cfloat, cap, join: cint, dash: ptr cfloat, n: cint) {.importc: "kks_fig_stroke", cdecl.}
proc fText(p: pointer, s: cstring, x, y: cfloat, anchor, role: cint, size: cfloat, weight: cint, r, g, b, a: cfloat) {.importc: "kks_fig_text", cdecl.}

var fontsTried = false
proc loadCourseFonts*() =
  ## the course faces (vendored WOFF2, decision 0011) next to the program: vendor/fonts
  if fontsTried: return
  fontsTried = true
  for base in [getAppDir() / "vendor" / "fonts", currentSourcePath().parentDir.parentDir.parentDir.parentDir.parentDir / "vendor" / "fonts"]:
    if dirExists(base):
      var blobs: seq[string]
      for f in walkFiles(base / "*.woff2"): blobs.add readFile(f)
      if blobs.len == 0: return
      var ptrs: seq[pointer]
      var sizes: seq[csize_t]
      for b in blobs:
        ptrs.add cast[pointer](unsafeAddr b[0])
        sizes.add csize_t(b.len)
      trace("course faces: " & $figFonts(addr ptrs[0], addr sizes[0], cint(ptrs.len)))
      return

proc backend(p: pointer): Backend =
  var b: Backend
  b.save = proc () = fSave(p)
  b.restore = proc () = fRestore(p)
  b.translate = proc (x, y: float) = fTranslate(p, x, y)
  b.rotate = proc (a: float) = fRotate(p, a)
  b.scale = proc (x, y: float) = fScale(p, x, y)
  b.pushOpacity = proc (a: float) = fPushOpacity(p, a)
  b.popOpacity = proc () = fPopOpacity(p)
  b.clipRoundRect = proc (x, y, w, h, rx: float) = fClip(p, x, y, w, h, rx)
  b.begin = proc () = fBegin(p)
  b.moveTo = proc (x, y: float) = fMove(p, x, y)
  b.lineTo = proc (x, y: float) = fLine(p, x, y)
  b.curveTo = proc (x1, y1, x2, y2, x, y: float) = fCurve(p, x1, y1, x2, y2, x, y)
  b.close = proc () = fClose(p)
  b.roundRect = proc (x, y, w, h, rx: float) = fRoundRect(p, x, y, w, h, rx)
  b.ellipse = proc (cx, cy, rx, ry: float) = fEllipse(p, cx, cy, rx, ry)
  b.fill = proc (pt: Paint) =
    if pt.radial:
      var st: seq[cfloat]
      for (o, c) in pt.stops: st.add [cfloat(o), c.r, c.g, c.b, c.a]
      fFillRadial(p, pt.cx, pt.cy, pt.rad, addr st[0], cint(pt.stops.len))
    else: fFill(p, pt.c.r, pt.c.g, pt.c.b, pt.c.a)
  b.stroke = proc (c: Rgba, w: float, cap, join: string, dash: seq[float]) =
    var d: seq[cfloat]
    for x in dash: d.add cfloat(x)
    fStroke(p, c.r, c.g, c.b, c.a, w, cint(case cap
      of "round": 1
      of "square": 2
      else: 0), cint(case join
      of "round": 1
      of "bevel": 2
      else: 0), if d.len > 0: addr d[0] else: nil, cint(d.len))
  b.text = proc (s: string, x, y: float, anchor, font: string, size: float, weight: int, c: Rgba) =
    fText(p, s.cstring, x, y, cint(case anchor
      of "middle": 1
      of "end": 2
      else: 0), cint(case font
      of "display": 1
      of "mono": 2
      else: 0), size, cint(weight), c.r, c.g, c.b, c.a)
  b

type FigView* = ref object
  ev*: Figure
  f*: JNode
  hwnd*, page*: HWND
  d2d: pointer
  status*, sliderOut*, slider*, playBtn*: HWND
  last: float
  onTick*: proc ()            ## after each frame (status, slider)

var views = initTable[HWND, FigView]()
var classDone = false

proc dark*(): bool =
  ## Windows' app theme (AppsUseLightTheme = 0)
  false

proc visible(v: FigView): bool =
  var r, pr: RECT
  if GetWindowRect(v.hwnd, addr r) == 0 or GetWindowRect(v.page, addr pr) == 0: return false
  r.bottom > pr.top and r.top < pr.bottom

proc paint(v: FigView) =
  var r: RECT
  GetClientRect(v.hwnd, addr r)
  let s = float(r.right) / v.f["w"].num      # the page sized the window (ui.aspect): never above 1:1 in DIPs
  let bg = hexRgba(token("surface", dark()))
  if figBegin(v.d2d, bg.r, bg.g, bg.b, s, 0) == 0: return
  backend(v.d2d).draw(v.ev.scene(), dark())
  discard figEnd(v.d2d)

proc figProc(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT {.stdcall.} =
  let v = views.getOrDefault(h)
  try:
    case m
    of WM_PAINT:
      var ps: PAINTSTRUCT
      discard BeginPaint(h, addr ps)
      if v != nil: v.paint()
      EndPaint(h, addr ps)
      return 0
    of WM_ERASEBKGND: return 1
    of WM_SIZE:
      if v != nil:
        figResize(v.d2d, cint(loword(l)), cint(hiword(l)))
        InvalidateRect(h, nil, 0)
      return 0
    of WM_TIMER:
      if v != nil:
        let now = epochTime() * 1000
        let el = if v.last == 0: 0.0 else: (now - v.last) / 1000
        v.last = now
        if v.ev.playing and v.visible:
          v.ev.tick(el)
          InvalidateRect(h, nil, 0)
          if v.onTick != nil: v.onTick()
        elif not v.visible: v.last = 0
      return 0
    of WM_DESTROY:
      if v != nil:
        KillTimer(h, 1)
        figFree(v.d2d)
        views.del h
      return 0
    else: discard
  except CatchableError as e: report(e)
  DefWindowProcW(h, m, w, l)

proc reduceMotion(): bool =
  var on: BOOL = 1
  SystemParametersInfoW(0x1042, 0, addr on, 0)     # SPI_GETCLIENTAREAANIMATION
  on == 0

proc figureView*(page: HWND, f: JNode, ev: Figure = nil): FigView =
  ## the drawing (a child of `page`); pass `ev` to keep a figure's state across page rebuilds
  if not classDone:
    let cls = newWideCString("KKSFigure")
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: figProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_ARROW), lpszClassName: cls)
    discard RegisterClassExW(addr wc)
    classDone = true
  loadCourseFonts()
  let v = FigView(f: f, page: page, ev: if ev != nil: ev else: newFigure(f, reduceMotion = reduceMotion()))
  v.hwnd = CreateWindowExW(0, newWideCString("KKSFigure"), newWideCString(f["title"].s & ". " & f["alt"].s),
                           WS_CHILD or WS_VISIBLE, 0, 0, 10, 10, page, nil, hinst, nil)
  v.d2d = figNew(v.hwnd)
  views[v.hwnd] = v
  if not v.ev.isStatic: SetTimer(v.hwnd, 1, 16, nil)
  v
