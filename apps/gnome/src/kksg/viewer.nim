## The drawing viewer (R1, R2; decisions 0016, 0031):
## - the overview pyramid (JPEG XL levels, decoded on a worker thread), shown until the vector tiles are ready;
## - vector tiles at every zoom, drawn from the .kkp by Cairo and cached as GPU textures;
## - tag hotspots on top.
## Input: drag to pan, wheel or pinch to zoom, click a tag, keyboard (arrows, +/−, 0 to fit).

import std/[math, tables, sets, algorithm, strutils, times, typedthreads]
import kks/json
import kksi/jxl
import gtk, kkprender

{.compile: "kks_view.c".}
proc kks_view_new(snap: pointer, user: pointer): W {.importc, cdecl.}

const
  TileSize = 512                 ## device px
  MaxTiles = 240
  FrameBudgetMs = 18.0

type
  TagBox* = object
    id*: string
    x0*, y0*, x1*, y1*: float    ## points
    status*: string              ## auto · verified · review · pending (a proposed mark)
    photos*: string              ## both · equipment · plate · none (core model.photoCover)
    label*: string               ## for the accessible list and tooltips

  DecodeJob = object
    gen, level: int
    data: string
  DecodeDone = object
    gen, level, w, h: int
    pixels: string

  Viewer* = ref object
    coverage*: bool              ## colour the tags by their photos instead of by how they were read
    widget*: W
    sheet*: Sheet
    name*: string
    scale0: float                ## level 0's px per point
    levels: seq[W]               ## textures, nil until decoded
    levelData: seq[string]
    asked: seq[bool]
    gen: int                     ## bumps when the sheet changes (late decodes are dropped)
    z*, ox*, oy*: float          ## logical px per point; the point at the widget's top-left
    fitted: bool
    tiles: Table[(int, int, int), W]
    lru: seq[(int, int, int)]
    want: seq[(int, int, int)]
    rendering: bool
    tags*: seq[TagBox]
    selected*: string
    hits*: HashSet[string]       ## search results to highlight
    linked*: HashSet[string]     ## tags linked to the open procedure (R7)
    floorOn*: bool               ## floor filter: other floors dimmed (R5)
    floorIds*: HashSet[string]
    onSelect*: proc (id: string)
    onView*: proc ()             ## zoom/position changed (status line)
    px, py: float                ## pointer position (for wheel zoom)
    dragOx, dragOy: float
    pinchZ: float
    marking*: bool               ## drawing a box for a missed tag (R6)
    markStart: (float, float)
    mark*: (float, float, float, float)
    onMark*: proc (x0, y0, x1, y1: float)

var
  startedAt*: float             ## set by the app at launch (KKS_TIMING: the first drawn sheet is reported)
  timingReported = false
  jobs: Channel[DecodeJob]
  results: Channel[DecodeDone]
  worker: Thread[void]
  workerStarted = false

proc decodeWorker() {.thread.} =
  while true:
    let j = jobs.recv()
    var d = DecodeDone(gen: j.gen, level: j.level)
    try:
      let (w, h, _, px) = decodeRgba(j.data)
      d.w = w
      d.h = h
      d.pixels = newString(w * h * 3)
      for i in 0 ..< w * h:         # RGBA → RGB (the pyramid has no alpha)
        d.pixels[i * 3] = char(px[i * 4])
        d.pixels[i * 3 + 1] = char(px[i * 4 + 1])
        d.pixels[i * 3 + 2] = char(px[i * 4 + 2])
    except CatchableError: discard
    results.send(d)

proc ensureWorker() =
  if not workerStarted:
    jobs.open()
    results.open()
    createThread(worker, decodeWorker)
    workerStarted = true

proc sf(v: Viewer): float = float(max(1, gtk_widget_get_scale_factor(v.widget)))

proc fit*(v: Viewer) =
  if v.sheet == nil: return
  let w = float(gtk_widget_get_width(v.widget))
  let h = float(gtk_widget_get_height(v.widget))
  if w < 2 or h < 2: return
  v.z = min(w / v.sheet.widthPt, h / v.sheet.heightPt) * 0.98
  v.ox = -(w / v.z - v.sheet.widthPt) / 2
  v.oy = -(h / v.z - v.sheet.heightPt) / 2
  v.fitted = true
  gtk_widget_queue_draw(v.widget)
  if v.onView != nil: v.onView()

proc maxZoom(v: Viewer): float = 16.0 * max(1.0, v.scale0) / v.sf   ## R1: 16× the overview's scale

proc zoomAt*(v: Viewer, factor, x, y: float) =
  ## zoom by `factor` keeping the point under (x, y) still
  if v.sheet == nil: return
  let w = float(gtk_widget_get_width(v.widget))
  let minZ = min(w / v.sheet.widthPt, float(gtk_widget_get_height(v.widget)) / v.sheet.heightPt) * 0.25
  let nz = max(minZ, min(v.maxZoom, v.z * factor))
  let px = v.ox + x / v.z
  let py = v.oy + y / v.z
  v.z = nz
  v.ox = px - x / v.z
  v.oy = py - y / v.z
  gtk_widget_queue_draw(v.widget)
  if v.onView != nil: v.onView()

proc zoomBy*(v: Viewer, factor: float) =
  ## zoom about the middle of the view (the header's buttons)
  v.zoomAt(factor, float(gtk_widget_get_width(v.widget)) / 2, float(gtk_widget_get_height(v.widget)) / 2)

proc centerOn*(v: Viewer, x0, y0, x1, y1: float, zoom = 0.0) =
  ## show the box (points) in the middle, at `zoom` (logical px per point) or at least 2× the fit
  let w = float(gtk_widget_get_width(v.widget))
  let h = float(gtk_widget_get_height(v.widget))
  if zoom > 0: v.z = zoom
  else: v.z = max(v.z, min(w / max(1.0, (x1 - x0) * 6), h / max(1.0, (y1 - y0) * 6)))
  v.z = min(v.z, v.maxZoom)
  v.ox = (x0 + x1) / 2 - w / v.z / 2
  v.oy = (y0 + y1) / 2 - h / v.z / 2
  gtk_widget_queue_draw(v.widget)
  if v.onView != nil: v.onView()

proc dropTiles(v: Viewer) =
  for _, t in v.tiles: g_object_unref(t)
  v.tiles.clear()
  v.lru.setLen(0)
  v.want.setLen(0)

proc setSheet*(v: Viewer, name: string, kkp: string, info: JNode, levels: seq[string]) =
  ## kkp: the path store; info: the sheets.json entry; levels: the pyramid files' bytes, level 0 first
  inc v.gen
  v.dropTiles()
  for t in v.levels:
    if t != nil: g_object_unref(t)
  v.name = name
  v.sheet = if kkp.len > 0: newSheet(kkp) else: nil
  v.scale0 = if info.get("scale") != nil and info["scale"].isNum: info["scale"].num else: 2.0
  v.levelData = levels
  v.levels = newSeq[W](levels.len)
  v.asked = newSeq[bool](levels.len)
  v.selected = ""
  v.hits.clear()
  v.fitted = false
  ensureWorker()
  if levels.len > 0:                      # the smallest level now, so something shows at once
    v.asked[^1] = true
    jobs.send(DecodeJob(gen: v.gen, level: levels.len - 1, data: levels[^1]))
  setAccessibleLabel(v.widget, "Drawing " & name)
  gtk_widget_queue_draw(v.widget)

proc pollDecodes*(v: Viewer) =
  ## called from a GLib timer: take finished overview levels
  while true:
    let (ok, d) = results.tryRecv()
    if not ok: break
    if d.gen != v.gen or d.w == 0: continue
    v.levels[d.level] = textureFromRgb(d.pixels.toOpenArrayByte(0, d.pixels.len - 1), d.w, d.h)
    v.levelData[d.level] = ""            # the bytes are no longer needed
    gtk_widget_queue_draw(v.widget)

proc levelScale(v: Viewer, k: int): float = v.scale0 / float(1 shl k)

proc renderSome(v: Viewer) =
  ## render wanted tiles for one frame's budget, then redraw
  if v.sheet == nil: return
  let t0 = epochTime()
  while v.want.len > 0 and (epochTime() - t0) * 1000 < FrameBudgetMs:
    let key = v.want.pop()
    if key in v.tiles: continue
    let (e, ix, iy) = key
    let tz = pow(2.0, float(e))
    let span = float(TileSize) / tz
    let surf = v.sheet.renderTile(tz, float(ix) * span, float(iy) * span, TileSize, TileSize)
    v.tiles[key] = textureOf(surf)
    cairo_surface_destroy(surf)
    v.lru.add key
    while v.lru.len > MaxTiles:
      let old = v.lru[0]
      v.lru.delete(0)
      if old in v.tiles:
        g_object_unref(v.tiles[old])
        v.tiles.del(old)
  gtk_widget_queue_draw(v.widget)
  if v.want.len == 0: v.rendering = false
  else: idle(proc () = v.renderSome())


proc coverColor*(photos: string): (float, float, float) =
  ## the photo coverage colours, the same on every client: both green, the equipment only amber, the tag plate only
  ## blue, none red
  case photos
  of "both": (0.18, 0.63, 0.26)
  of "equipment": (0.9, 0.59, 0.0)
  of "plate": (0.12, 0.47, 0.9)
  else: (0.86, 0.16, 0.16)

proc tagColor(status: string): (float, float, float) =
  case status
  of "verified": (0.15, 0.6, 0.25)
  of "review": (0.95, 0.55, 0.0)
  of "pending": (0.55, 0.2, 0.75)
  else: (0.1, 0.4, 0.9)

proc snapshot(v: Viewer, s: W, w, h: int) =
  var r: GraphRect
  graphene_rect_init(addr r, 0, 0, cfloat(w), cfloat(h))
  let bg = gtk_snapshot_append_cairo(s, addr r)
  cairo_set_source_rgb(bg, 0.82, 0.83, 0.85)
  cairo_paint(bg)
  cairo_destroy(bg)
  if v.sheet == nil and v.levels.len == 0: return
  if not v.fitted: v.fit()
  if v.z <= 0: return
  let wpt = if v.sheet != nil: v.sheet.widthPt else: 1.0
  let hpt = if v.sheet != nil: v.sheet.heightPt else: 1.0
  let dz = v.z * v.sf                     # device px per point
  # 1. the overview: the smallest level sharp enough for this zoom (asked for once), drawn when decoded; until then
  #    the sharpest level already decoded
  var want = 0
  for k in countdown(v.levels.len - 1, 0):
    if v.levelScale(k) >= dz * 0.9:
      want = k
      break
  if v.levels.len > 0 and not v.asked[want]:
    v.asked[want] = true
    jobs.send(DecodeJob(gen: v.gen, level: want, data: v.levelData[want]))
  var best = -1
  if v.levels.len > 0 and v.levels[want] != nil: best = want
  else:
    for k in 0 ..< v.levels.len:
      if v.levels[k] != nil:
        best = k
        break
  graphene_rect_init(addr r, cfloat(-v.ox * v.z), cfloat(-v.oy * v.z), cfloat(wpt * v.z), cfloat(hpt * v.z))
  if best >= 0:
    gtk_snapshot_append_scaled_texture(s, v.levels[best], GSK_SCALING_FILTER_TRILINEAR, addr r)
    if not timingReported and startedAt > 0:
      timingReported = true
      stderr.writeLine "timing: first sheet drawn " & $int((epochTime() - startedAt) * 1000) & " ms after launch"
  else:
    let c = gtk_snapshot_append_cairo(s, addr r)
    cairo_set_source_rgb(c, 1, 1, 1)
    cairo_paint(c)
    cairo_destroy(c)
  # 2. vector tiles at every zoom, over the overview (which shows until they are rendered): the overview shrunk to fit
  #    made the lines soft (the user, 2026-10-07). Clipped to the sheet: at low zoom one tile reaches past its edge.
  if v.sheet != nil:
    graphene_rect_init(addr r, cfloat(-v.ox * v.z), cfloat(-v.oy * v.z), cfloat(wpt * v.z), cfloat(hpt * v.z))
    gtk_snapshot_push_clip(s, addr r)
    let e = int(ceil(log2(dz)))
    let tz = pow(2.0, float(e))
    let span = float(TileSize) / tz         # points per tile
    let x0 = max(0.0, v.ox)
    let y0 = max(0.0, v.oy)
    let x1 = min(wpt, v.ox + float(w) / v.z)
    let y1 = min(hpt, v.oy + float(h) / v.z)
    var missing: seq[(int, int, int)]
    for iy in int(floor(y0 / span)) .. int(floor(y1 / span)):
      for ix in int(floor(x0 / span)) .. int(floor(x1 / span)):
        let key = (e, ix, iy)
        if key in v.tiles:
          graphene_rect_init(addr r, cfloat((float(ix) * span - v.ox) * v.z), cfloat((float(iy) * span - v.oy) * v.z),
                             cfloat(span * v.z), cfloat(span * v.z))
          gtk_snapshot_append_scaled_texture(s, v.tiles[key], GSK_SCALING_FILTER_LINEAR, addr r)
        else: missing.add key
    gtk_snapshot_pop(s)
    if missing.len > 0:
      # nearest the centre last, so it is popped (rendered) first
      let cx = (x0 + x1) / 2 / span
      let cy = (y0 + y1) / 2 / span
      missing.sort(proc (a, b: (int, int, int)): int =
        cmp(abs(float(b[1]) + 0.5 - cx) + abs(float(b[2]) + 0.5 - cy), abs(float(a[1]) + 0.5 - cx) + abs(float(a[2]) + 0.5 - cy)))
      v.want = missing
      if not v.rendering:
        v.rendering = true
        idle(proc () = v.renderSome())
  # 3. hotspots
  graphene_rect_init(addr r, 0, 0, cfloat(w), cfloat(h))
  let c = gtk_snapshot_append_cairo(s, addr r)
  for t in v.tags:
    let x = (t.x0 - v.ox) * v.z
    let y = (t.y0 - v.oy) * v.z
    let tw = (t.x1 - t.x0) * v.z
    let th = (t.y1 - t.y0) * v.z
    if x + tw < 0 or y + th < 0 or x > float(w) or y > float(h): continue
    var (cr, cg, cb) = if v.coverage and t.status != "pending": coverColor(t.photos) else: tagColor(t.status)
    let sel = t.id == v.selected
    let hit = t.id in v.hits
    let dim = v.floorOn and t.id notin v.floorIds
    if t.id in v.linked:
      (cr, cg, cb) = (0.1, 0.65, 0.3)
      cairo_set_source_rgba(c, cr, cg, cb, 0.3)
      cairo_rectangle(c, x, y, tw, th)
      cairo_fill(c)
    if dim:
      cairo_set_source_rgba(c, cr, cg, cb, 0.18)
      cairo_set_line_width(c, 1)
      cairo_rectangle(c, x, y, tw, th)
      cairo_stroke(c)
      continue
    if v.coverage and t.status != "pending" and not (sel or hit):
      cairo_set_source_rgba(c, cr, cg, cb, 0.28)
      cairo_rectangle(c, x, y, tw, th)
      cairo_fill(c)
    if sel or hit:
      cairo_set_source_rgba(c, if hit and not sel: 1.0 else: cr, if hit and not sel: 0.85 else: cg, if hit and not sel: 0.0 else: cb, 0.28)
      cairo_rectangle(c, x, y, tw, th)
      cairo_fill(c)
    cairo_set_source_rgba(c, cr, cg, cb, if sel: 1.0 else: 0.75)
    cairo_set_line_width(c, if sel: 3.0 else: 1.5)
    if t.status == "pending":
      var dash = [4.0, 3.0]
      cairo_set_dash(c, addr dash[0], 2, 0)
    cairo_rectangle(c, x, y, tw, th)
    cairo_stroke(c)
    cairo_set_dash(c, nil, 0, 0)
  if v.marking and v.mark[2] != v.mark[0]:
    cairo_set_source_rgba(c, 0.85, 0.1, 0.1, 0.9)
    cairo_set_line_width(c, 2)
    cairo_rectangle(c, (v.mark[0] - v.ox) * v.z, (v.mark[1] - v.oy) * v.z, (v.mark[2] - v.mark[0]) * v.z, (v.mark[3] - v.mark[1]) * v.z)
    cairo_stroke(c)
  cairo_destroy(c)

proc snapCb(user: pointer, s: W, w, h: cint) {.cdecl.} =
  try: cast[Viewer](user).snapshot(s, int(w), int(h))
  except CatchableError as e: stderr.writeLine "viewer: " & e.msg

proc hitTag*(v: Viewer, x, y: float): string =
  ## the smallest tag box under (x, y) in widget px
  let px = v.ox + x / v.z
  let py = v.oy + y / v.z
  var area = Inf
  for t in v.tags:
    let pad = 3.0 / v.z
    if px >= t.x0 - pad and px <= t.x1 + pad and py >= t.y0 - pad and py <= t.y1 + pad:
      let a = (t.x1 - t.x0) * (t.y1 - t.y0)
      if a < area:
        area = a
        result = t.id

proc newViewer*(): Viewer =
  let v = Viewer(z: 1)
  GC_ref(v)
  v.widget = kks_view_new(cast[pointer](snapCb), cast[pointer](v))
  gtk_widget_set_cursor_from_name(v.widget, "grab")
  # pan
  let drag = gtk_gesture_drag_new()
  drag.onXY("drag-begin", proc (x, y: float) =
    v.dragOx = v.ox
    v.dragOy = v.oy
    if v.marking:
      v.markStart = (v.ox + x / v.z, v.oy + y / v.z)
      v.mark = (v.markStart[0], v.markStart[1], v.markStart[0], v.markStart[1]))
  drag.onXY("drag-update", proc (dx, dy: float) =
    if v.marking:
      let (sx, sy) = v.markStart
      let ex = sx + dx / v.z
      let ey = sy + dy / v.z
      v.mark = (min(sx, ex), min(sy, ey), max(sx, ex), max(sy, ey))
    else:
      v.ox = v.dragOx - dx / v.z
      v.oy = v.dragOy - dy / v.z
    gtk_widget_queue_draw(v.widget))
  drag.onXY("drag-end", proc (dx, dy: float) =
    if v.marking and abs(dx) + abs(dy) > 6:
      if v.onMark != nil: v.onMark(v.mark[0], v.mark[1], v.mark[2], v.mark[3])
    elif v.onView != nil: v.onView())
  gtk_widget_add_controller(v.widget, drag)
  # wheel zoom around the pointer
  let motion = gtk_event_controller_motion_new()
  motion.onXY("motion", proc (x, y: float) =
    v.px = x
    v.py = y)
  gtk_widget_add_controller(v.widget, motion)
  let scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)
  scroll.onScroll(proc (dx, dy: float) =
    if dy != 0: v.zoomAt(pow(1.0015, -dy * (if gtk_event_controller_scroll_get_unit(scroll) == GDK_SCROLL_UNIT_WHEEL: 80 else: 2)), v.px, v.py))
  gtk_widget_add_controller(v.widget, scroll)
  # pinch
  let pinch = gtk_gesture_zoom_new()
  # "begin" passes the event sequence (NULL for a touchpad pinch): connected with on(), the trampoline took it for its
  # own data and read through nil (the crash on a two-finger trackpad zoom, 2026-10-07)
  pinch.onPtr("begin", proc (sequence: W) = v.pinchZ = v.z)
  pinch.onScale(proc (scale: float) =
    var cx, cy: cdouble
    discard gtk_gesture_get_bounding_box_center(pinch, addr cx, addr cy)
    v.zoomAt(v.pinchZ * scale / v.z, float(cx), float(cy)))
  gtk_widget_add_controller(v.widget, pinch)
  # click a tag
  let click = gtk_gesture_click_new()
  click.onPressed("released", proc (n: int, x, y: float) =
    discard gtk_widget_grab_focus(v.widget)
    if v.marking: return
    let id = v.hitTag(x, y)
    if id.len > 0:
      v.selected = id
      gtk_widget_queue_draw(v.widget)
      if v.onSelect != nil: v.onSelect(id))
  gtk_widget_add_controller(v.widget, click)
  # keyboard
  let keys = gtk_event_controller_key_new()
  keys.onKey(proc (keyval, state: cuint): bool =
    let w = float(gtk_widget_get_width(v.widget))
    let h = float(gtk_widget_get_height(v.widget))
    case keyval
    of 0xff51: v.ox -= w * 0.15 / v.z            # Left
    of 0xff53: v.ox += w * 0.15 / v.z            # Right
    of 0xff52: v.oy -= h * 0.15 / v.z            # Up
    of 0xff54: v.oy += h * 0.15 / v.z            # Down
    of 0x2b, 0x3d, 0xffab: v.zoomAt(1.25, w / 2, h / 2)       # + = keypad+
    of 0x2d, 0xffad: v.zoomAt(0.8, w / 2, h / 2)              # - keypad-
    of 0x30, 0xffb0: v.fit()                                  # 0
    of 0xff1b:                                                 # Escape
      if v.marking:
        v.marking = false
        v.mark = (0.0, 0.0, 0.0, 0.0)
      else: return false
    else: return false
    gtk_widget_queue_draw(v.widget)
    if v.onView != nil: v.onView()
    true)
  gtk_widget_add_controller(v.widget, keys)
  timeout(50, proc (): bool =
    v.pollDecodes()
    true)
  v
