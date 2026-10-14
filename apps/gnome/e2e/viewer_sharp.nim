## The drawing viewer on a scaled screen: sharp at every zoom, and smooth to pan and zoom (2026-10-14: on a scale-2
## laptop panel the GNOME app's drawings were soft at every zoom and panning stuttered, while the web was crisp).
## It opens a window, so it is not in `nim test`; run it under a headless mutter whose monitor has scale 2:
##   cd apps/gnome && nim c -d:release -o:/tmp/kksgnome/viewer_sharp e2e/viewer_sharp.nim
##   KKS_HEADLESS_SIZE=2560x1600 KKS_HEADLESS_SCALE=2 e2e/headless.sh /tmp/kksgnome/viewer_sharp
## and with KKS_HEADLESS_SCALE=1.25 (a fractional scale).
## A synthetic sheet (A1, dense thin "text" and hairlines, as the P&IDs are) is shown at several zooms. Each view is
## captured at device pixels through GTK's own renderer and compared with the same area drawn directly by Cairo at
## that device resolution: the ratio of their gradient energy is 1 for an equally sharp picture and well below 1 for a
## resampled one. A settled view with tags is checked for what makes frames slow: no Cairo layer the size of the view
## (rasterised on the CPU at every frame) and no scaled-texture nodes (GTK draws those through a picture at logical
## size). Then a pan and a zoom run one step per frame, with 300 tags on the sheet, and the time between frames is
## measured (KKS_SHARP_TIMING=0 skips those limits: a CI runner draws on the CPU). Last, the monitor's scale changes
## to 1 and the view must be as sharp at the new scale.
## KKS_SHARP_OUT=folder keeps the pictures; KKS_SHARP_ASSERT=0 only measures (the default asserts).
import std/[os, osproc, math, random, strutils, algorithm, times, sequtils, sets]
import kks/[pathstore, json]
import kksg/[gtk, viewer, kkprender]

const HA = "<gtk/gtk.h>"
proc gtk_snapshot_new(): W {.importc, header: HA.}
proc gtk_snapshot_scale(s: W, x, y: cfloat) {.importc, header: HA.}
proc gsk_render_node_get_node_type(n: W): cint {.importc, header: HA.}
proc gsk_render_node_get_bounds(n: W, r: ptr GraphRect) {.importc, header: HA.}
proc gsk_container_node_get_n_children(n: W): cuint {.importc, header: HA.}
proc gsk_container_node_get_child(n: W, i: cuint): W {.importc, header: HA.}
proc gsk_transform_node_get_child(n: W): W {.importc, header: HA.}
proc gsk_clip_node_get_child(n: W): W {.importc, header: HA.}
proc graphene_rect_get_width(r: ptr GraphRect): cfloat {.importc, header: HA.}
proc graphene_rect_get_height(r: ptr GraphRect): cfloat {.importc, header: HA.}
var
  GSK_CONTAINER_NODE {.importc, header: HA, nodecl.}: cint
  GSK_TRANSFORM_NODE {.importc, header: HA, nodecl.}: cint
  GSK_CLIP_NODE {.importc, header: HA, nodecl.}: cint
  GSK_CAIRO_NODE {.importc, header: HA, nodecl.}: cint
  GSK_TEXTURE_NODE {.importc, header: HA, nodecl.}: cint
  GSK_TEXTURE_SCALE_NODE {.importc, header: HA, nodecl.}: cint
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
let timing = getEnv("KKS_SHARP_TIMING", "1") != "0"
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

proc synthTags(): (seq[TagBox], seq[TagBox]) =
  ## 300 tags and 20 off-page connectors spread over the sheet, every kind of mark among them
  var r = initRand(7)
  for i in 0 ..< 300:
    let x = 30 + r.rand(2300.0)
    let y = 30 + r.rand(1600.0)
    let st = ["auto", "verified", "review", "pending"][i mod 4]
    result[0].add TagBox(id: "t" & $i, x0: x, y0: y, x1: x + 26, y1: y + 9, status: st, photos: "none", label: "t" & $i)
  for i in 0 ..< 20:
    let x = 30 + r.rand(2300.0)
    let y = 30 + r.rand(1600.0)
    result[1].add TagBox(id: "c" & $i, x0: x, y0: y, x1: x + 8, y1: y + 8, label: "C" & $i)

# ---------------------------------------------------------------- pictures and the sharpness measure
type GPoint {.importc: "graphene_point_t", header: HA, bycopy.} = object
  x, y: cfloat
proc gtk_snapshot_translate(s: W, p: ptr GPoint) {.importc, header: HA.}

proc nodeOf(v: Viewer, sf: float): W =
  ## the widget's own drawing under the window's scale, where it sits on its surface, as GTK draws it on screen (a
  ## GtkWidgetPaintable would hand over its last picture at logical size, scaled up)
  let (wx, wy) = v.originOnSurface
  var p = GPoint(x: cfloat(wx), y: cfloat(wy))
  let s = gtk_snapshot_new()
  gtk_snapshot_scale(s, cfloat(sf), cfloat(sf))
  gtk_snapshot_translate(s, addr p)
  v.drawInto(s)
  gtk_snapshot_free_to_node(s)

proc census(n: W, cairoMax: var float, textures, scaled: var int) =
  ## the largest Cairo node's area (logical px²), the texture and scaled-texture nodes
  if n == nil: return
  let t = gsk_render_node_get_node_type(n)
  if t == GSK_CONTAINER_NODE:
    for i in 0'u32 ..< gsk_container_node_get_n_children(n): census(gsk_container_node_get_child(n, cuint(i)), cairoMax, textures, scaled)
  elif t == GSK_TRANSFORM_NODE: census(gsk_transform_node_get_child(n), cairoMax, textures, scaled)
  elif t == GSK_CLIP_NODE: census(gsk_clip_node_get_child(n), cairoMax, textures, scaled)
  elif t == GSK_CAIRO_NODE:
    var b: GraphRect
    gsk_render_node_get_bounds(n, addr b)
    cairoMax = max(cairoMax, float(graphene_rect_get_width(addr b)) * float(graphene_rect_get_height(addr b)))
  elif t == GSK_TEXTURE_NODE: inc textures
  elif t == GSK_TEXTURE_SCALE_NODE: inc scaled

proc capture(v: Viewer, sf: float): (int, int, seq[byte]) =
  ## the viewer as GTK draws it at `sf` device px per logical px: (w, h, B G R A rows)
  let w = float(gtk_widget_get_width(v.widget))
  let h = float(gtk_widget_get_height(v.widget))
  let node = v.nodeOf(sf)
  # the surface's device pixels the widget covers, from the whole pixel its top-left is in
  let (wx, wy) = v.originOnSurface
  var vp: GraphRect
  graphene_rect_init(addr vp, cfloat(floor(wx * sf)), cfloat(floor(wy * sf)), cfloat(round(w * sf)), cfloat(round(h * sf)))
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
  # on the device pixel grid the viewer places its tiles on (a fraction of a pixel's shift changes how Cairo
  # anti-aliases a hairline, not how sharp the drawing is)
  let (wx, wy) = v.originOnSurface
  let fx = wx * sf - floor(wx * sf)
  let fy = wy * sf - floor(wy * sf)
  let x0p = round(v.ox * dz - fx) / dz
  let y0p = round(v.oy * dz - fy) / dz
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

proc gtk_widget_get_frame_clock(w: W): W {.importc, header: HA.}

type Motion = object
  intervals: seq[float]          ## between frames (ms): what the eye sees, but also the compositor's and GPU's share
  busy: seq[float]               ## the main thread's work for each frame, from the frame clock's update to its
                                 ## after-paint (ms): snapshot, layout, rasterising Cairo nodes, handing over to GSK
  stall: float                   ## the longest the main loop went without running a 2 ms timer (ms): work outside
                                 ## the frames, as tiles drawn in idle callbacks were

proc motion(v: Viewer, name: string, n: int, step: proc (i: int)): Motion =
  ## one `step` per frame for `n` frames
  var last = 0.0
  var i = 0
  var intervals, busy: seq[float]
  var began = 0.0
  var stall = 0.0
  var lastTimer = epochTime() * 1000
  let clock = gtk_widget_get_frame_clock(v.widget)
  let h1 = clock.on("update", proc () = began = epochTime() * 1000)
  let h2 = clock.on("after-paint", proc () =
    if began > 0 and i < n: busy.add epochTime() * 1000 - began
    began = 0)
  let t = timeout(2, proc (): bool =
    let now = epochTime() * 1000
    if i > 0: stall = max(stall, now - lastTimer)
    lastTimer = now
    i < n)
  discard t
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
  g_signal_handler_disconnect(clock, h1)
  g_signal_handler_disconnect(clock, h2)
  let over = intervals.countIt(it > 25.0)
  let f = proc (x: float): string = formatFloat(x, ffDecimal, 1)
  echo name & ": " & $intervals.len & " frames, between frames median " & f(percentile(intervals, 0.5)) & " ms, p95 " &
    f(percentile(intervals, 0.95)) & " ms, max " & f(max(intervals)) & " ms, " & $over & " over 25 ms; main thread per frame median " &
    f(percentile(busy, 0.5)) & " ms, p95 " & f(percentile(busy, 0.95)) & " ms, max " & f(max(busy)) &
    " ms; longest main-loop stall " & f(stall) & " ms"
  Motion(intervals: intervals, busy: busy, stall: stall)

# ---------------------------------------------------------------- the run
if not getEnv("WAYLAND_DISPLAY").startsWith("kks-headless-"):
  echo "run it under e2e/headless.sh (a private compositor), never on the desktop"
  quit 2
let app = adw_application_new("org.kks.SharpTest", 32)
var done = false
app.on("activate", proc () =
  after(240_000, proc () =
    echo "FAIL the test did not finish in 4 minutes"
    quit 3)
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
  let wantScale = parseFloat(getEnv("KKS_HEADLESS_SCALE", "2"))
  if strict: check(sf > 1.0 and abs(sf - wantScale) < 0.01, "the screen is scaled as asked (KKS_HEADLESS_SCALE): scale " & $sf)
  echo "the widget's top-left on its surface: ", v.originOnSurface, " logical px"
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
  # with tags on: what each frame is made of, in a settled view
  (v.tags, v.links) = synthTags()
  v.selected = "t1"
  for i in countup(0, 299, 37): v.hits.incl "t" & $i
  v.centerOn(300, 800, 301, 801, 1.5)
  doAssert v.complete()
  block:
    let node = v.nodeOf(sf)
    var cairoMax = 0.0
    var textures, scaled = 0
    census(node, cairoMax, textures, scaled)
    gsk_render_node_unref(node)
    let area = float(gtk_widget_get_width(v.widget) * gtk_widget_get_height(v.widget))
    check(cairoMax <= area / 50, "no Cairo layer near the view's size (largest " & $int(cairoMax) & " of " & $int(area) & " px²)")
    check(scaled == 0 and textures > 0, "a settled view is tiles at device pixels: " & $textures & " texture nodes, " &
      $scaled & " scaled-texture nodes")
    if outDir.len > 0:
      discard v.capture(sf)
      moveFile(outDir / "last-capture.png", outDir / "tags-viewer.png")
  # a pan across new parts of the sheet, one step per frame (a brisk drag: 30 logical px a frame)
  # back and forth, always over the sheet
  var dir = 1.0
  let pan = v.motion("pan", 150, proc (i: int) =
    let wide = float(gtk_widget_get_width(v.widget)) / v.z
    if v.ox + wide + 30 / v.z > v.sheet.widthPt: dir = -1.0
    elif v.ox - 30 / v.z < 0: dir = 1.0
    v.ox += dir * 30 / v.z)
  # a zoom from fit, 3 % a frame
  v.fit()
  doAssert v.complete()
  let w = float(gtk_widget_get_width(v.widget))
  let h = float(gtk_widget_get_height(v.widget))
  let zoom = v.motion("zoom", 90, proc (i: int) = v.zoomAt(1.03, w / 2, h / 2))
  # a zoom, then a drag at once: the tiles of the new zoom are drawn while the drag goes on (the zoom has settled,
  # though frames keep coming)
  v.centerOn(1100, 800, 1101, 801, 1.5)
  doAssert v.complete()
  v.zoomAt(1.2, w / 2, h / 2)
  discard v.motion("drag after a zoom", 40, proc (i: int) = v.ox += 2 / v.z)
  check(v.tilesAtViewZoom, "tiles of the new zoom are wanted during a drag that follows it at once")
  if timing:
    # the main thread's share, which this code decides (the time between frames also holds the compositor and the
    # GPU, which other work on the machine slows down: reported above, not checked)
    for (name, m) in [("pan", pan), ("zoom", zoom)]:
      check(percentile(m.busy, 0.95) <= 8.0, name & ": the main thread's work for 95 % of frames within 8 ms (" &
        formatFloat(percentile(m.busy, 0.95), ffDecimal, 1) & ")")
      check(m.stall <= 40.0, name & ": the main loop never held up more than 40 ms (" & formatFloat(m.stall, ffDecimal, 1) & ")")
  # the monitor's scale changes (another screen): the tiles follow, as sharp at the new scale
  if getEnv("KKS_HEADLESS_SCALE").len > 0:
    v.tags = @[]
    v.links = @[]
    let dc = "gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig "
    let st = execProcess(dc & "--method org.gnome.Mutter.DisplayConfig.GetCurrentState", options = {poEvalCommand})
    let serial = st[st.find("uint32 ") + 7 ..< st.find(",")]
    let size = getEnv("KKS_HEADLESS_SIZE", "1280x900")
    doAssert execCmd(dc & "--method org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig " & serial & " 1 \"[(0, 0, 1.0, 0, true, [('Meta-0', '" &
      size & "@60.000', @a{sv} {})])]\" \"@a{sv} {}\" >/dev/null") == 0
    let surface = gtk_native_get_surface(gtk_widget_get_native(v.widget))
    check(waitUntil(proc (): bool = gdk_surface_get_scale(surface) == 1.0, 20), "the window's scale is 1 now")
    v.centerOn(1100, 800, 1101, 801, v.z)   # the same zoom: only the device pixels per point change
    v.frames(3)
    doAssert v.complete()
    let s1 = v.sharpness(1.0, "scale1")
    check(s1 >= 0.85, "sharp after the scale changed to 1 at the same zoom (" & formatFloat(v.z, ffDecimal, 2) & " device px/pt): gradient energy " &
      formatFloat(s1, ffDecimal, 3))
  done = true
  gtk_window_destroy(win)
  g_application_quit(app))
discard g_application_run(app, 0, nil)
doAssert done, "the test ran"
if failures.len > 0 and strict:
  echo $failures.len & " failed"
  quit 1
