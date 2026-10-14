## The drawing viewer on a scaled screen: sharp at every zoom, and smooth to pan and zoom (2026-10-14: on a scale-2
## laptop panel the GNOME app's drawings were soft at every zoom and panning stuttered, while the web was crisp).
## It opens a window, so it is not in `nim test`; run it under a headless mutter whose monitor has scale 2:
##   cd apps/gnome && nim c -d:release -o:/tmp/kksgnome/viewer_sharp e2e/viewer_sharp.nim
##   KKS_HEADLESS_SIZE=2560x1600 KKS_HEADLESS_SCALE=2 e2e/headless.sh /tmp/kksgnome/viewer_sharp
## A synthetic sheet (A1, dense thin "text" and hairlines, as the P&IDs are) is shown at several zooms. Each view is
## captured at device pixels through GTK's own renderer and compared with the same area drawn directly by Cairo at
## that device resolution: the ratio of their gradient energy is 1 for an equally sharp picture and well below 1 for a
## resampled one. Then a pan and a zoom run one step per frame, and the time between frames is measured.
## KKS_SHARP_OUT=folder keeps the pictures; KKS_SHARP_ASSERT=0 only measures (the default asserts).
import std/[os, math, random, strutils, algorithm, times, sequtils]
import kks/[pathstore, json]
import kksg/[gtk, viewer, kkprender]

const HA = "<gtk/gtk.h>"
proc gtk_widget_paintable_new(w: W): W {.importc, header: HA.}
proc gtk_snapshot_new(): W {.importc, header: HA.}
proc gtk_snapshot_scale(s: W, x, y: cfloat) {.importc, header: HA.}
proc gdk_paintable_snapshot(p, s: W, w, h: cdouble) {.importc, header: HA.}
proc gtk_snapshot_free_to_node(s: W): W {.importc, header: HA.}
proc gtk_widget_get_native(w: W): W {.importc, header: HA.}
proc gtk_native_get_renderer(w: W): W {.importc, header: HA.}
proc gtk_native_get_surface(w: W): W {.importc, header: HA.}
proc gdk_surface_get_scale(s: W): cdouble {.importc, header: HA.}
proc gsk_renderer_render_texture(r, node: W, viewport: ptr GraphRect): W {.importc, header: HA.}
proc gsk_render_node_unref(n: W) {.importc, header: HA.}
proc gdk_texture_download(t: W, data: pointer, stride: csize_t) {.importc, header: HA.}
proc gdk_texture_save_to_png(t: W, path: cstring): cint {.importc, header: HA.}
proc cairo_surface_write_to_png(s: Surface, path: cstring): cint {.importc, header: "<cairo.h>".}
proc gtk_window_set_child(w, c: W) {.importc, header: HA.}
proc gtk_window_new(): W {.importc, header: HA.}
proc gtk_application_add_window(a, w: W) {.importc, header: HA.}

let outDir = getEnv("KKS_SHARP_OUT")
let strict = getEnv("KKS_SHARP_ASSERT", "1") != "0"
var failures: seq[string]

proc check(ok: bool, what: string) =
  echo (if ok: "ok   " else: "FAIL ") & what
  if not ok: failures.add what

# ---------------------------------------------------------------- the synthetic sheet
proc synthSheet(): string =
  ## an A1 sheet (2384 × 1684 pt) of what makes a P&ID: lines of small stroked characters (0.25 pt pens), boxes and
  ## pipes drawn as hairlines, a few filled symbols
  var d: Drawing
  d.width = uint32(2384 * Q)
  d.height = uint32(1684 * Q)
  d.styles = @[
    Style(kind: Stroke, cap: 1, join: 1, width: uint32(Q div 4)),            # text pen
    Style(kind: Stroke or Hairline, cap: 0, join: 0, width: 0),              # hairline boxes and pipes
    Style(kind: Stroke, cap: 0, join: 0, width: uint32(Q * 3 div 4)),        # heavy pipes
    Style(kind: Fill, cap: 0, join: 0, width: 0)]                            # filled valve bodies
  var r = initRand(20261014)
  proc add(style: int, pts: seq[(float, float)], closed = false) =
    var x0, y0 = int64.high
    var x1, y1 = int64.low
    let ps = d.ops.len
    let pt = d.xy.len div 2
    for i, (x, y) in pts:
      let qx = int64(round(x * float(Q)))
      let qy = int64(round(y * float(Q)))
      d.ops.add(if i == 0: OpMove else: OpLine)
      d.xy.add qx
      d.xy.add qy
      x0 = min(x0, qx); y0 = min(y0, qy); x1 = max(x1, qx); y1 = max(y1, qy)
    if closed: d.ops.add OpClose
    d.paths.add pathstore.Path(style: style, bbox: [x0, y0, x1, y1], cmdStart: ps, cmdCount: d.ops.len - ps, ptStart: pt)
  # text: rows of 1.4 × 2.2 pt characters, each 2–4 strokes
  var y = 20.0
  while y < 1660:
    var x = 20.0 + r.rand(40.0)
    let rowEnd = min(2360.0, x + 150 + r.rand(500.0))
    while x < rowEnd:
      for _ in 0 ..< 2 + r.rand(2):
        let a = (x + r.rand(1.4), y + r.rand(2.2))
        let b = (x + r.rand(1.4), y + r.rand(2.2))
        add(0, @[a, b])
      x += 1.9
      if r.rand(7) == 0: x += 2.5      # a space
    y += 5.5 + r.rand(9.0)
  # tag boxes and pipes (hairlines), heavy pipes, valves
  for _ in 0 ..< 1500:
    let bx = 30 + r.rand(2300.0)
    let by = 30 + r.rand(1600.0)
    add(1, @[(bx, by), (bx + 26, by), (bx + 26, by + 9), (bx, by + 9)], closed = true)
    add(1, @[(bx, by + 4.5), (bx + 26, by + 4.5)])
  for _ in 0 ..< 300:
    let px = 20 + r.rand(2340.0)
    let py = 20 + r.rand(1640.0)
    if r.rand(1) == 0: add(2, @[(px, py), (min(2370.0, px + 50 + r.rand(400.0)), py)])
    else: add(1, @[(px, py), (px, min(1670.0, py + 50 + r.rand(400.0)))])
  for _ in 0 ..< 400:
    let vx = 30 + r.rand(2320.0)
    let vy = 30 + r.rand(1620.0)
    add(3, @[(vx, vy), (vx + 6, vy + 3), (vx + 6, vy - 3)], closed = true)
  d.styles[3].fill = [0'u8, 0, 0]
  encode(d)

# ---------------------------------------------------------------- pictures and the sharpness measure
proc capture(v: Viewer, sf: float): (int, int, seq[byte]) =
  ## the viewer as GTK draws it at `sf` device px per logical px: (w, h, B G R A rows)
  let w = float(gtk_widget_get_width(v.widget))
  let h = float(gtk_widget_get_height(v.widget))
  let p = gtk_widget_paintable_new(v.widget)
  let s = gtk_snapshot_new()
  gtk_snapshot_scale(s, cfloat(sf), cfloat(sf))
  gdk_paintable_snapshot(p, s, w, h)
  let node = gtk_snapshot_free_to_node(s)
  g_object_unref(p)
  var vp: GraphRect
  graphene_rect_init(addr vp, 0, 0, cfloat(round(w * sf)), cfloat(round(h * sf)))
  let tex = gsk_renderer_render_texture(gtk_native_get_renderer(gtk_widget_get_native(v.widget)), node, addr vp)
  gsk_render_node_unref(node)
  let tw = int(gdk_texture_get_width(tex))
  let th = int(gdk_texture_get_height(tex))
  var buf = newSeq[byte](tw * th * 4)
  gdk_texture_download(tex, addr buf[0], csize_t(tw * 4))
  if outDir.len > 0: discard gdk_texture_save_to_png(tex, (outDir / "last-capture.png").cstring)
  g_object_unref(tex)
  (tw, th, buf)

proc luma(buf: openArray[byte], stride, x, y: int): float =
  let o = y * stride + x * 4
  0.114 * float(buf[o]) + 0.587 * float(buf[o + 1]) + 0.299 * float(buf[o + 2])

proc gradEnergy(buf: openArray[byte], stride, x0, y0, x1, y1: int): float =
  for y in y0 ..< y1:
    for x in x0 ..< x1:
      let c = luma(buf, stride, x, y)
      let dx = luma(buf, stride, x + 1, y) - c
      let dy = luma(buf, stride, x, y + 1) - c
      result += dx * dx + dy * dy

proc sharpness(v: Viewer, sf: float, name: string): float =
  ## the gradient energy of the middle of the view as drawn, over the same area drawn by Cairo at device pixels
  let (w, h, buf) = v.capture(sf)
  let dz = v.z * sf
  let x0p = v.ox
  let y0p = v.oy
  let refSurf = v.sheet.renderTile(dz, x0p, y0p, w, h)
  let rstride = int(cairo_image_surface_get_stride(refSurf))
  let rdata = cairo_image_surface_get_data(refSurf)
  # the middle half of the view, inside the sheet
  let cx0 = max(w div 4, int(ceil(-v.ox * dz)) + 4)
  let cy0 = max(h div 4, int(ceil(-v.oy * dz)) + 4)
  let cx1 = min(w * 3 div 4, int(floor((v.sheet.widthPt - v.ox) * dz)) - 4)
  let cy1 = min(h * 3 div 4, int(floor((v.sheet.heightPt - v.oy) * dz)) - 4)
  doAssert cx1 > cx0 + 50 and cy1 > cy0 + 50, "the measured area is inside the sheet"
  let got = gradEnergy(buf, w * 4, cx0, cy0, cx1, cy1)
  let want = gradEnergy(toOpenArray(cast[ptr UncheckedArray[byte]](rdata), 0, rstride * h - 1), rstride, cx0, cy0, cx1, cy1)
  if outDir.len > 0:
    moveFile(outDir / "last-capture.png", outDir / (name & "-viewer.png"))
    discard cairo_surface_write_to_png(refSurf, (outDir / (name & "-cairo.png")).cstring)
  cairo_surface_destroy(refSurf)
  got / want

# ---------------------------------------------------------------- driving the main loop
proc settle() =
  while g_main_context_iteration(nil, 0) != 0: discard

proc waitUntil(cond: proc (): bool, secs = 30.0): bool =
  let till = epochTime() + secs
  while epochTime() < till:
    if cond(): return true
    discard g_main_context_iteration(nil, 1)
  false

proc frames(v: Viewer, n: int) =
  ## let `n` frames of the widget's frame clock pass
  var seen = 0
  onTick(v.widget, proc (us: int64): bool =
    inc seen
    seen < n)
  discard waitUntil(proc (): bool = seen >= n, 20)

proc complete(v: Viewer): bool =
  ## the view's tiles are all drawn: nothing pending through a few frames
  waitUntil(proc (): bool =
    if v.tilesPending > 0: return false
    v.frames(3)
    v.tilesPending == 0, 60)

proc percentile(xs: seq[float], p: float): float =
  let s = xs.sorted
  s[min(s.len - 1, int(float(s.len - 1) * p + 0.5))]

proc motion(v: Viewer, name: string, n: int, step: proc (i: int)): seq[float] =
  ## one `step` per frame for `n` frames; returns the times between frames (ms)
  var last = 0.0
  var i = 0
  var intervals: seq[float]
  onTick(v.widget, proc (us: int64): bool =
    let now = epochTime() * 1000
    if last > 0: intervals.add now - last
    last = now
    if i < n:
      step(i)
      inc i
      gtk_widget_queue_draw(v.widget)
    i < n)
  discard waitUntil(proc (): bool = i >= n, 120)
  let over = intervals.countIt(it > 25.0)
  echo name & ": " & $intervals.len & " frames, median " & formatFloat(percentile(intervals, 0.5), ffDecimal, 1) &
    " ms, p95 " & formatFloat(percentile(intervals, 0.95), ffDecimal, 1) & " ms, max " &
    formatFloat(max(intervals), ffDecimal, 1) & " ms, " & $over & " over 25 ms"
  intervals

# ---------------------------------------------------------------- the run
let app = adw_application_new("org.kks.SharpTest", 32)
var done = false
app.on("activate", proc () =
  let v = newViewer()
  let win = gtk_window_new()
  gtk_window_set_default_size(win, 1200, 800)
  gtk_window_set_child(win, v.widget)
  gtk_application_add_window(app, win)
  gtk_window_present(win)
  doAssert waitUntil(proc (): bool = gtk_widget_get_width(v.widget) > 100 and gtk_widget_get_native(v.widget) != nil)
  v.frames(5)
  let sf = float(gdk_surface_get_scale(gtk_native_get_surface(gtk_widget_get_native(v.widget))))
  echo "window ", gtk_widget_get_width(v.widget), "×", gtk_widget_get_height(v.widget), " logical px, scale ", sf
  if strict: check(sf >= 2.0, "the screen is scaled (run under KKS_HEADLESS_SCALE=2): scale " & $sf)
  if outDir.len > 0: createDir(outDir)
  let kkp = synthSheet()
  v.setSheet("synthetic", kkp, parseStrict("{\"scale\": 2}"), @[])
  v.fit()
  # sharp at every zoom: fit, and zooms between and on the powers of two
  let fitZ = v.z
  for (name, z) in [("fit", fitZ), ("z0.7", 0.7 / sf * 2), ("z1.37", 1.37), ("z2", 2.0), ("z2.9", 2.9), ("z6.1", 6.1)]:
    v.centerOn(1100, 800, 1101, 801, z)
    doAssert v.complete(), "the tiles at " & name & " are drawn"
    let s = v.sharpness(sf, name)
    check(s >= 0.85, "sharp at " & name & " (" & formatFloat(v.z * sf, ffDecimal, 2) & " device px/pt): gradient energy " &
      formatFloat(s, ffDecimal, 3) & " of Cairo's at device pixels")
  # a pan across new parts of the sheet, one step per frame (a brisk drag: 30 logical px a frame)
  v.centerOn(300, 800, 301, 801, 1.5)
  doAssert v.complete()
  let pan = v.motion("pan", 150, proc (i: int) = v.ox += 30 / v.z)
  # a zoom from fit, 3 % a frame
  v.fit()
  doAssert v.complete()
  let w = float(gtk_widget_get_width(v.widget))
  let h = float(gtk_widget_get_height(v.widget))
  let zoom = v.motion("zoom", 90, proc (i: int) = v.zoomAt(1.03, w / 2, h / 2))
  for (name, xs) in [("pan", pan), ("zoom", zoom)]:
    check(percentile(xs, 0.95) <= 25.0, name & ": 95 % of frames within 25 ms (" &
      formatFloat(percentile(xs, 0.95), ffDecimal, 1) & ")")
    check(max(xs) <= 60.0, name & ": no frame over 60 ms (" & formatFloat(max(xs), ffDecimal, 1) & ")")
  done = true
  gtk_window_destroy(win)
  g_application_quit(app))
discard g_application_run(app, 0, nil)
doAssert done, "the test ran"
if failures.len > 0 and strict:
  echo $failures.len & " failed"
  quit 1
