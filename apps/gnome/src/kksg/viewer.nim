## The drawing viewer (R1, R2; decisions 0016, 0031):
## - the overview pyramid (JPEG XL levels, decoded on a worker thread), shown until the vector tiles are ready;
## - vector tiles at every zoom, drawn from the .kkp by Cairo and cached as GPU textures;
## - tag hotspots on top.
## Input: drag to pan, wheel or pinch to zoom, click a tag, keyboard (arrows, +/−, 0 to fit).

import std/[math, tables, sets, algorithm, strutils, times, typedthreads, atomics]
import kks/json
import kksi/jxl
import gtk, kkprender, darkcolor

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
    dark: bool                   ## dark drawings: the level's pixels are transformed here, on the worker
    data: string
  DecodeDone = object
    gen, level, w, h: int
    pixels: string

  Viewer* = ref object
    coverage*: bool              ## colour the tags by their photos instead of by how they were read
    dark*: bool                  ## dark drawings (setDark): tiles and overview light-on-dark, markers lightened
    widget*: W
    sheet*: Sheet
    name*: string
    scale0: float                ## level 0's px per point
    levels: seq[W]               ## textures, nil until decoded
    stale: seq[W]                ## the levels shown before a dark-drawings switch, until this mode's arrive
    levelData: seq[string]       ## kept: switching dark drawings decodes the levels again (a few MB per sheet)
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
    links*: seq[TagBox]          ## off-page connectors (C16, D2 …): label, box in points
    linkSel*: int                ## the connector just arrived at (-1 none), drawn bold
    onLink*: proc (i: int)       ## a connector clicked: index into links
    onView*: proc ()             ## zoom/position changed (status line)
    px, py: float                ## pointer position (for wheel zoom)
    dragOx, dragOy: float
    pinchZ: float
    fitZ: float                  ## the zoom that fits the sheet: the overview is a placeholder, none finer is decoded
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
  liveGen: Atomic[int]          ## the viewer's current gen: the worker skips jobs queued for an older one

proc decodeWorker() {.thread.} =
  while true:
    let j = jobs.recv()
    if j.gen != liveGen.load: continue   # superseded (another sheet, a dark-drawings switch): don't decode it
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
      if j.dark and d.pixels.len > 0:
        darkenPixels(d.pixels.toOpenArrayByte(0, d.pixels.len - 1), 3)
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
  v.fitZ = v.z
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
  if not v.fitted: v.fit()      # a sheet just set: fit first, or the first frame's fit would undo this
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
  liveGen.store(v.gen)
  for t in v.levels & v.stale:
    if t != nil: g_object_unref(t)
  v.stale = @[]
  v.name = name
  v.sheet = if kkp.len > 0: newSheet(kkp) else: nil
  if v.sheet != nil: v.sheet.setDark(v.dark)
  v.scale0 = if info.get("scale") != nil and info["scale"].isNum: info["scale"].num else: 2.0
  v.levelData = levels
  v.levels = newSeq[W](levels.len)
  v.asked = newSeq[bool](levels.len)
  v.selected = ""
  v.hits.clear()
  v.links = @[]
  v.linkSel = -1
  v.fitted = false
  ensureWorker()
  if levels.len > 0:                      # the smallest level now, so something shows at once
    v.asked[^1] = true
    jobs.send(DecodeJob(gen: v.gen, level: levels.len - 1, dark: v.dark, data: levels[^1]))
  setAccessibleLabel(v.widget, "Drawing " & name)
  gtk_widget_queue_draw(v.widget)

proc dropSharperStale(v: Viewer, want: int, shown: W) =
  ## the other mode's levels sharper than the zoom wants aren't shown again: they go now, not when this mode's level of
  ## that size arrives (a level 0 is up to 123 MB; zoomed out it might never be asked). `shown` (on screen) stays.
  for k in 0 ..< min(want, v.stale.len):
    if v.stale[k] != nil and v.stale[k] != shown:
      g_object_unref(v.stale[k])
      v.stale[k] = nil

proc pollDecodes*(v: Viewer) =
  ## called from a GLib timer: take finished overview levels
  while true:
    let (ok, d) = results.tryRecv()
    if not ok: break
    if d.gen != v.gen or d.w == 0: continue
    if v.levels[d.level] != nil: g_object_unref(v.levels[d.level])
    v.levels[d.level] = textureFromRgb(d.pixels.toOpenArrayByte(0, d.pixels.len - 1), d.w, d.h)
    for k in d.level ..< v.stale.len:     # the old mode's levels no sharper than this one go
      if v.stale[k] != nil:
        g_object_unref(v.stale[k])
        v.stale[k] = nil
    gtk_widget_queue_draw(v.widget)

proc setDark*(v: Viewer, on: bool) =
  ## dark drawings on or off, at once: cached tiles are dropped (re-rendered in the new colours) and the overview
  ## levels decoded again (the smallest first). Decodes queued for the old mode are skipped by the worker (`liveGen`),
  ## and the levels shown so far stay until this mode's arrive (never the smallest level, never blank)
  if v.dark == on: return
  v.dark = on
  inc v.gen
  liveGen.store(v.gen)
  v.dropTiles()
  if v.sheet != nil: v.sheet.setDark(on)
  if v.stale.len != v.levels.len: v.stale = newSeq[W](v.levels.len)
  for k in 0 ..< v.levels.len:
    if v.levels[k] != nil:          # this mode's level replaces an older stale one; else the older one stays
      if v.stale[k] != nil: g_object_unref(v.stale[k])
      v.stale[k] = v.levels[k]
    v.levels[k] = nil
    v.asked[k] = false
  if v.levels.len > 0:
    ensureWorker()
    v.asked[^1] = true
    jobs.send(DecodeJob(gen: v.gen, level: v.levels.len - 1, dark: on, data: v.levelData[^1]))
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

proc linkColor*(dark: bool): (float, float, float) =
  ## an off-page connector's violet; on dark drawings raised toward white like the tags' colours
  if dark: lightenForDark(0.55, 0.2, 0.85) else: (0.55, 0.2, 0.85)

proc markerColor*(status, photos: string, coverage, dark: bool): (float, float, float) =
  ## a tag's outline colour: by its photos (coverage view) or by how it was read; the same hues on dark drawings,
  ## raised toward white so each keeps 3:1 against the dark sheet (tests/test_darkcolor.nim)
  let (r, g, b) = if coverage and status != "pending": coverColor(photos) else: tagColor(status)
  if dark: lightenForDark(r, g, b) else: (r, g, b)

proc snapshot(v: Viewer, s: W, w, h: int) =
  var r: GraphRect
  graphene_rect_init(addr r, 0, 0, cfloat(w), cfloat(h))
  let bg = gtk_snapshot_append_cairo(s, addr r)
  if v.dark: cairo_set_source_rgb(bg, 0.24, 0.24, 0.26)     # around the sheet: lighter than the dark paper
  else: cairo_set_source_rgb(bg, 0.82, 0.83, 0.85)
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
  let odz = if v.fitZ > 0: min(dz, v.fitZ * v.sf) else: dz   # vector tiles cover the zooms beyond fit
  for k in countdown(v.levels.len - 1, 0):
    if v.levelScale(k) >= odz * 0.9:
      want = k
      break
  if v.levels.len > 0 and not v.asked[want]:
    v.asked[want] = true
    jobs.send(DecodeJob(gen: v.gen, level: want, dark: v.dark, data: v.levelData[want]))
  var best = -1
  var tex: W = nil
  if v.levels.len > 0 and v.levels[want] != nil: tex = v.levels[want]
  elif want < v.stale.len and v.stale[want] != nil: tex = v.stale[want]   # shown before a dark switch: not blurrier
  else:
    for k in 0 ..< v.levels.len:
      if v.levels[k] != nil:
        tex = v.levels[k]
        break
    if tex == nil:
      for k in 0 ..< v.stale.len:
        if v.stale[k] != nil:
          tex = v.stale[k]
          break
  if tex != nil: best = 0
  v.dropSharperStale(want, tex)
  graphene_rect_init(addr r, cfloat(-v.ox * v.z), cfloat(-v.oy * v.z), cfloat(wpt * v.z), cfloat(hpt * v.z))
  if best >= 0:
    gtk_snapshot_append_scaled_texture(s, tex, GSK_SCALING_FILTER_TRILINEAR, addr r)
    if not timingReported and startedAt > 0:
      timingReported = true
      stderr.writeLine "timing: first sheet drawn " & $int((epochTime() - startedAt) * 1000) & " ms after launch"
  else:
    let c = gtk_snapshot_append_cairo(s, addr r)
    if v.dark: cairo_set_source_rgb(c, DarkLo / 255, DarkLo / 255, DarkLo / 255)
    else: cairo_set_source_rgb(c, 1, 1, 1)
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
    # while this level's tiles render, the neighbouring levels' cached tiles stand in (sharper than the overview)
    for e2 in [e + 1, e - 1]:
      let span2 = float(TileSize) / pow(2.0, float(e2))
      for iy in int(floor(y0 / span2)) .. int(floor(y1 / span2)):
        for ix in int(floor(x0 / span2)) .. int(floor(x1 / span2)):
          if (e2, ix, iy) in v.tiles and (e, int(floor(float(ix) * span2 / span)), int(floor(float(iy) * span2 / span))) notin v.tiles:
            graphene_rect_init(addr r, cfloat((float(ix) * span2 - v.ox) * v.z), cfloat((float(iy) * span2 - v.oy) * v.z),
                               cfloat(span2 * v.z), cfloat(span2 * v.z))
            gtk_snapshot_append_scaled_texture(s, v.tiles[(e2, ix, iy)], GSK_SCALING_FILTER_TRILINEAR, addr r)
    var missing: seq[(int, int, int)]
    for iy in int(floor(y0 / span)) .. int(floor(y1 / span)):
      for ix in int(floor(x0 / span)) .. int(floor(x1 / span)):
        let key = (e, ix, iy)
        if key in v.tiles:
          graphene_rect_init(addr r, cfloat((float(ix) * span - v.ox) * v.z), cfloat((float(iy) * span - v.oy) * v.z),
                             cfloat(span * v.z), cfloat(span * v.z))
          gtk_snapshot_append_scaled_texture(s, v.tiles[key], GSK_SCALING_FILTER_TRILINEAR, addr r)   # drawn at 0.5-1x
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
    var (cr, cg, cb) = markerColor(t.status, t.photos, v.coverage, v.dark)
    let sel = t.id == v.selected
    let hit = t.id in v.hits
    let dim = v.floorOn and t.id notin v.floorIds
    if t.id in v.linked:
      (cr, cg, cb) = if v.dark: lightenForDark(0.1, 0.65, 0.3) else: (0.1, 0.65, 0.3)
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
    cairo_set_source_rgba(c, cr, cg, cb, if sel or v.dark: 1.0 else: 0.75)
    cairo_set_line_width(c, if sel: 3.0 else: 1.5)
    if t.status == "pending":
      var dash = [4.0, 3.0]
      cairo_set_dash(c, addr dash[0], 2, 0)
    cairo_rectangle(c, x, y, tw, th)
    cairo_stroke(c)
    cairo_set_dash(c, nil, 0, 0)
  # off-page connectors: violet dashed circles, unlike the tags' rectangles
  for i, l in v.links:
    let cx = ((l.x0 + l.x1) / 2 - v.ox) * v.z
    let cy = ((l.y0 + l.y1) / 2 - v.oy) * v.z
    let rad = max(6.0, max(l.x1 - l.x0, l.y1 - l.y0) / 2 * v.z + 3)
    if cx + rad < 0 or cy + rad < 0 or cx - rad > float(w) or cy - rad > float(h): continue
    let sel = i == v.linkSel
    let (lr, lg, lb) = linkColor(v.dark)
    cairo_new_sub_path(c)
    cairo_arc(c, cx, cy, rad, 0, 2 * PI)
    cairo_set_source_rgba(c, lr, lg, lb, if sel: 0.3 else: 0.12)
    cairo_fill_preserve(c)
    cairo_set_source_rgba(c, lr, lg, lb, 0.9)
    cairo_set_line_width(c, if sel: 3.5 else: 2.0)
    if not sel:
      var dash = [5.0, 3.0]
      cairo_set_dash(c, addr dash[0], 2, 0)
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

proc hitLink*(v: Viewer, x, y: float): int =
  ## the connector under (x, y) in widget px, -1 none (a little slack: they are small)
  result = -1
  let px = v.ox + x / v.z
  let py = v.oy + y / v.z
  let pad = 6.0 / v.z
  for i, l in v.links:
    if px >= l.x0 - pad and px <= l.x1 + pad and py >= l.y0 - pad and py <= l.y1 + pad: return i

proc newViewer*(): Viewer =
  let v = Viewer(z: 1, linkSel: -1)
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
    let li = v.hitLink(x, y)
    if li >= 0:
      if v.onLink != nil: v.onLink(li)
      return
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
