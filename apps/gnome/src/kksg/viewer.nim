## The drawing viewer (R1, R2; decisions 0016, 0031):
## - the overview pyramid (JPEG XL levels, decoded on a worker thread), a placeholder until the vector tiles are ready;
## - vector tiles at every zoom, drawn from the .kkp by Cairo on worker threads and cached as GPU textures;
## - tag hotspots on top, as GSK nodes.
## Input: drag to pan, wheel or pinch to zoom, click a tag, keyboard (arrows, +/−, 0 to fit).
##
## Sharpness (2026-10-14: soft at every zoom on a scale-2 screen): tiles are drawn at the exact zoom in device pixels
## (the surface's scale, fractional ones included) and placed on whole device pixels, so each tile pixel is one screen
## pixel, unfiltered. Tiles drawn for a power of two above the zoom and shrunk by 0.5–1 with a mipmapped filter, at
## fractional positions, were blurred to a fifth of the sharp picture's edge energy. While the zoom changes, the tiles
## at hand are scaled; once it has stayed put for `SettleMs`, the tiles of the new zoom are drawn.
## Smoothness: nothing is drawn by Cairo on the main thread any more (the tiles were, for up to a frame's budget at a
## time, and two window-sized Cairo layers were rasterised every frame), so panning only moves textures.

import std/[math, tables, sets, algorithm, times, typedthreads, atomics]
import kks/json
import kksi/jxl
import gtk, kkprender, darkcolor

{.compile: "kks_view.c".}
proc kks_view_new(snap: pointer, user: pointer): W {.importc, cdecl.}

const
  TileSize = 512                 ## device px
  MaxTiles = 96                  ## cached tiles (1 MiB each), at least twice what a view needs (`tileCap`)
  TileWorkers = 2
  MaxInflight = 2 * TileWorkers  ## tiles queued to the workers at once: a moving view's old wishes don't pile up
  SettleMs = 120                 ## a zoom that has stayed put this long gets its own tiles

type
  TileKey = tuple[zb: uint64, ix, iy: int]   ## the tile zoom's bits (device px per point), the tile's column, row
  Tile = object
    tex: W
    used: int                    ## the frame it was last drawn in (the least recently used goes first)
  TileJob = object
    gen: int
    sheet: pointer               ## ptr SheetObj, kept alive by a GC_ref on the main thread until the job comes back
    dark: bool
    key: TileKey
  TileDone = object
    gen: int
    sheet: pointer
    key: TileKey
    surf: Surface                ## nil: skipped (an older generation) or failed

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
    tiles: Table[TileKey, Tile]
    want: seq[TileKey]           ## tiles the view needs, the most wanted last
    queued: HashSet[TileKey]     ## with the workers
    inflight: int                ## jobs with the workers, of any generation
    ticking: bool                ## a frame-clock callback collects finished tiles
    frame: int
    tileZ: float                 ## the zoom (device px per point) tiles are drawn at; follows the view's once it settles
    lastDz: float                ## the view's zoom at the last frame
    settle: cuint                ## the timer that adopts a new zoom (0 none)
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
    selecting*: bool             ## "Select tags" mode: a click toggles a tag, a dragged box adds the tags it touches
    chosen*: HashSet[string]     ## the selected tags (a distinct outline)
    symbolBox*: seq[float]       ## the open panel's valve symbol (x0, y0, x1, y1 in points), outlined; empty = none
    onBox*: proc (x0, y0, x1, y1: float)   ## a box dragged in the select mode (points)

var
  startedAt*: float             ## set by the app at launch (KKS_TIMING: the first drawn sheet is reported)
  timingReported = false
  jobs: Channel[DecodeJob]
  results: Channel[DecodeDone]
  worker: Thread[void]
  workerStarted = false
  liveGen: Atomic[int]          ## the viewer's current gen: the workers skip jobs queued for an older one
  tileJobs: Channel[TileJob]
  tileResults: Channel[TileDone]
  tileThreads: array[TileWorkers, Thread[void]]
  tileStarted = false

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

proc tileZoom(k: TileKey): float = cast[float](k.zb)

proc tileWorker() {.thread.} =
  ## draws tiles: the job's sheet is only read here (kkprender's thread rules)
  while true:
    let j = tileJobs.recv()
    var d = TileDone(gen: j.gen, sheet: j.sheet, key: j.key)
    if j.gen == liveGen.load:
      let z = tileZoom(j.key)
      let span = float(TileSize) / z
      d.surf = renderTile(cast[ptr SheetObj](j.sheet), j.dark, z, float(j.key.ix) * span, float(j.key.iy) * span,
                          TileSize, TileSize)
    tileResults.send(d)

proc ensureTileWorkers() =
  if not tileStarted:
    tileJobs.open()
    tileResults.open()
    for t in tileThreads.mitems: createThread(t, tileWorker)
    tileStarted = true

proc gtk_widget_get_native(w: W): W {.importc, header: "<gtk/gtk.h>".}
proc gtk_native_get_surface(w: W): W {.importc, header: "<gtk/gtk.h>".}
proc gdk_surface_get_scale(s: W): cdouble {.importc, header: "<gtk/gtk.h>".}

type GPoint {.importc: "graphene_point_t", header: "<gtk/gtk.h>", bycopy.} = object
  x, y: cfloat
proc gtk_widget_compute_point(w, target: W, p, res: ptr GPoint): bool {.importc, header: "<gtk/gtk.h>".}
proc gtk_native_get_surface_transform(n: W, x, y: ptr cdouble) {.importc, header: "<gtk/gtk.h>".}

proc originOnSurface*(v: Viewer): (float, float) =
  ## the widget's top-left on its surface, logical px (its device pixel is this × the scale: a fraction of a device
  ## pixel at scales like 1.25, which the tiles' placement makes up for)
  let n = gtk_widget_get_native(v.widget)
  if n == nil: return (0.0, 0.0)
  var p0 = GPoint(x: 0, y: 0)
  var p: GPoint
  if not gtk_widget_compute_point(v.widget, n, addr p0, addr p): return (0.0, 0.0)
  var tx, ty: cdouble
  gtk_native_get_surface_transform(n, addr tx, addr ty)
  (float(p.x) + float(tx), float(p.y) + float(ty))

proc sf(v: Viewer): float =
  ## device px per logical px: the surface's scale, fractional ones included (1.25, 1.5 …); the widget's integer scale
  ## factor before it is on screen
  let n = gtk_widget_get_native(v.widget)
  let surf = if n != nil: gtk_native_get_surface(n) else: nil
  if surf != nil:
    let s = float(gdk_surface_get_scale(surf))
    if s > 0: return s
  float(max(1, gtk_widget_get_scale_factor(v.widget)))

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
  ## every cached tile goes; tiles still with the workers are of an older generation now and are dropped on arrival
  for _, t in v.tiles: g_object_unref(t.tex)
  v.tiles.clear()
  v.want.setLen(0)
  v.queued.clear()
  v.tileZ = 0                   # the next frame's zoom is taken at once
  if v.settle != 0:
    g_source_remove(v.settle)
    v.settle = 0

proc setSheet*(v: Viewer, name: string, kkp: string, info: JNode, levels: seq[string]) =
  ## kkp: the path store; info: the sheets.json entry; levels: the pyramid files' bytes, level 0 first
  inc v.gen
  v.dropTiles()
  liveGen.store(v.gen)
  for t in v.levels & v.stale:
    if t != nil: g_object_unref(t)
  v.stale = @[]
  v.name = name
  if v.sheet != nil: v.sheet.release()
  v.sheet = if kkp.len > 0: newSheet(kkp) else: nil
  if v.sheet != nil: v.sheet.setDark(v.dark)
  v.scale0 = if info.get("scale") != nil and info["scale"].isNum: info["scale"].num else: 2.0
  v.levelData = levels
  v.levels = newSeq[W](levels.len)
  v.asked = newSeq[bool](levels.len)
  v.selected = ""
  v.symbolBox = @[]
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

proc tilesAtViewZoom*(v: Viewer): bool =
  ## the tiles are wanted at the zoom on screen (not still waiting for a zoom change to settle)
  v.tileZ > 0 and v.tileZ == v.lastDz

proc tilesPending*(v: Viewer): int =
  ## tiles the view still waits for (wanted, with the workers, or a zoom about to be adopted); tests wait for 0
  v.want.len + v.queued.len + (if v.settle != 0: 1 else: 0)

proc tileCap(v: Viewer): int =
  ## the cache's size: MaxTiles, or twice a view's tiles on a very large screen (so a view never evicts its own)
  let d = v.sf
  let across = int(ceil(float(gtk_widget_get_width(v.widget)) * d / float(TileSize))) + 3
  let down = int(ceil(float(gtk_widget_get_height(v.widget)) * d / float(TileSize))) + 3
  max(MaxTiles, 2 * across * down)

proc evict(v: Viewer) =
  ## down to the cap: tiles of other zooms first, then the least recently drawn (a tile of the view's own zoom never
  ## gives way to a stand-in, or the view would draw the same tile again and again)
  let cap = v.tileCap
  if v.tiles.len <= cap: return
  let zb = cast[uint64](v.tileZ)
  var order: seq[(int, int, TileKey)]
  for k, t in v.tiles: order.add ((if k.zb == zb: 1 else: 0), t.used, k)
  order.sort(proc (a, b: (int, int, TileKey)): int = cmp((a[0], a[1]), (b[0], b[1])))
  for n in 0 ..< v.tiles.len - cap:
    let k = order[n][2]
    g_object_unref(v.tiles[k].tex)
    v.tiles.del k

proc pump(v: Viewer)

proc collect(v: Viewer): bool =
  ## take the tiles the workers finished (main thread); true if one of them belongs to the view
  while true:
    let (ok, d) = tileResults.tryRecv()
    if not ok: break
    dec v.inflight
    GC_unref(cast[Sheet](d.sheet))
    if d.gen == v.gen and d.surf != nil:
      v.queued.excl d.key
      if d.key in v.tiles: g_object_unref(v.tiles[d.key].tex)
      v.tiles[d.key] = Tile(tex: textureTaking(d.surf), used: v.frame)
      result = true
    elif d.surf != nil: cairo_surface_destroy(d.surf)
    elif d.gen == v.gen: v.queued.excl d.key
  if result: v.evict()

proc pump(v: Viewer) =
  ## hand the most wanted tiles to the workers, a few at a time; collect finished ones on every frame until none is
  ## out (a frame-clock callback: tiles arrive in step with drawing)
  if v.sheet == nil: return
  ensureTileWorkers()
  while v.inflight < MaxInflight and v.want.len > 0:
    let k = v.want.pop()
    if k in v.tiles or k in v.queued: continue
    v.queued.incl k
    inc v.inflight
    GC_ref(v.sheet)
    tileJobs.send(TileJob(gen: v.gen, sheet: cast[pointer](v.sheet), dark: v.dark, key: k))
  if v.inflight > 0 and not v.ticking:
    v.ticking = true
    onTick(v.widget, proc (us: int64): bool =
      if v.collect(): gtk_widget_queue_draw(v.widget)
      v.pump()
      v.ticking = v.inflight > 0
      v.ticking)

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

type
  GdkRGBA {.importc, header: "<gtk/gtk.h>", bycopy.} = object
    red, green, blue, alpha: cfloat
  GskRoundedRect {.importc, header: "<gtk/gtk.h>", bycopy.} = object
proc gtk_snapshot_append_color(s: W, c: ptr GdkRGBA, r: ptr GraphRect) {.importc, header: "<gtk/gtk.h>".}
proc gsk_rounded_rect_init_from_rect(rr: ptr GskRoundedRect, r: ptr GraphRect, radius: cfloat): ptr GskRoundedRect
  {.importc, header: "<gtk/gtk.h>", discardable.}
proc gtk_snapshot_append_border(s: W, rr: ptr GskRoundedRect, widths: ptr array[4, cfloat],
                                colors: ptr array[4, GdkRGBA]) {.importc, header: "<gtk/gtk.h>".}

proc gtk_snapshot_save(s: W) {.importc, header: "<gtk/gtk.h>".}
proc gtk_snapshot_restore(s: W) {.importc, header: "<gtk/gtk.h>".}
proc gtk_snapshot_scale(s: W, x, y: cfloat) {.importc, header: "<gtk/gtk.h>".}

template inDevicePixels(s: W, sf: float, body: untyped) =
  ## textures are placed in device pixels: GTK 4.22 draws a scaled texture (a texture-scale node) through a picture as
  ## large as its rectangle in the node's own units, so under the window's scale 2 every tile and the overview was
  ## sampled at half the screen's resolution and stretched back (all renderers: Vulkan, GL and Cairo; measured
  ## 2026-10-14, e2e/viewer_sharp.nim). With one unit per device pixel the picture is the screen's resolution.
  gtk_snapshot_save(s)
  gtk_snapshot_scale(s, cfloat(1 / sf), cfloat(1 / sf))
  body
  gtk_snapshot_restore(s)

proc rgba(r, g, b: float, a = 1.0): GdkRGBA = GdkRGBA(red: cfloat(r), green: cfloat(g), blue: cfloat(b), alpha: cfloat(a))

proc fillRect(s: W, c: GdkRGBA, x, y, w, h: float) =
  var r: GraphRect
  var c = c
  graphene_rect_init(addr r, cfloat(x), cfloat(y), cfloat(w), cfloat(h))
  gtk_snapshot_append_color(s, addr c, addr r)

proc strokeRect(s: W, c: GdkRGBA, x, y, w, h, lw: float) =
  ## a rectangle's outline `lw` wide, centred on its edges as Cairo strokes it
  var r: GraphRect
  var rr: GskRoundedRect
  graphene_rect_init(addr r, cfloat(x - lw / 2), cfloat(y - lw / 2), cfloat(w + lw), cfloat(h + lw))
  gsk_rounded_rect_init_from_rect(addr rr, addr r, 0)
  var widths = [cfloat(lw), cfloat(lw), cfloat(lw), cfloat(lw)]
  var colors = [c, c, c, c]
  gtk_snapshot_append_border(s, addr rr, addr widths, addr colors)

template cairoIn(s: W, x, y, w, h: float, c, body: untyped) =
  ## a small Cairo node over just this box (widget coordinates inside), for the few dashed or round marks
  block:
    var r: GraphRect
    graphene_rect_init(addr r, cfloat(floor(x)), cfloat(floor(y)), cfloat(ceil(w) + 1), cfloat(ceil(h) + 1))
    let c = gtk_snapshot_append_cairo(s, addr r)
    body
    cairo_destroy(c)

proc adoptZoom(v: Viewer, dz, before: float) =
  ## the zoom tiles are drawn at: the view's at once when nothing is drawn yet, else once it has stayed put for
  ## SettleMs (a pinch or a run of wheel steps doesn't start tiles for every zoom on the way). `before` is the last
  ## frame's zoom: only a change of zoom starts the wait again, not every frame (a drag right after a zoom drew no
  ## tiles of the new zoom for as long as it lasted)
  if v.tileZ == 0:
    v.tileZ = dz
    return
  if dz == v.tileZ:
    if v.settle != 0:
      g_source_remove(v.settle)
      v.settle = 0
    return
  if v.settle != 0:
    if dz == before: return
    g_source_remove(v.settle)
  v.settle = after(SettleMs, proc () =
    v.settle = 0
    v.tileZ = v.lastDz
    gtk_widget_queue_draw(v.widget))

proc snapshot(v: Viewer, s: W, w, h: int) =
  inc v.frame
  if v.dark: fillRect(s, rgba(0.24, 0.24, 0.26), 0, 0, float(w), float(h))   # around the sheet: lighter than the paper
  else: fillRect(s, rgba(0.82, 0.83, 0.85), 0, 0, float(w), float(h))
  if v.sheet == nil and v.levels.len == 0: return
  if not v.fitted: v.fit()
  if v.z <= 0: return
  let wpt = if v.sheet != nil: v.sheet.widthPt else: 1.0
  let hpt = if v.sheet != nil: v.sheet.heightPt else: 1.0
  let sf = v.sf
  var dz = v.z * sf                       # device px per point
  # a zoom a rounding error away from the tiles' (a pinch's arithmetic) is theirs: the same picture, not a new set
  if v.tileZ > 0 and abs(dz - v.tileZ) <= 1e-9 * v.tileZ: dz = v.tileZ
  let before = v.lastDz
  v.lastDz = dz
  # the vector tiles: which are at hand, and which the view still needs
  var exact: seq[(TileKey, float, float)]   # tiles at this very zoom, with their place in device px
  var standIns: seq[TileKey]
  var holes: seq[(float, float, float, float)]   # the missing tiles' areas (points): where stand-ins show
  var covered = false                        # the view is all exact tiles: no overview under them
  var hox = v.ox                             # where the hotspots are drawn from: the tiles' rounded place, so a
  var hoy = v.oy                             # tag's box sits on its drawn symbol to the device pixel
  let x0 = max(0.0, v.ox)
  let y0 = max(0.0, v.oy)
  let x1 = min(wpt, v.ox + float(w) / v.z)
  let y1 = min(hpt, v.oy + float(h) / v.z)
  if v.sheet != nil and (x1 <= x0 or y1 <= y0): v.want.setLen(0)   # nothing of the sheet in view
  if v.sheet != nil and x1 > x0 and y1 > y0:
    v.adoptZoom(dz, before)
    if v.tileZ == dz:
      let span = float(TileSize) / dz         # points per tile
      let zb = cast[uint64](dz)
      # where the sheet's device pixel 0 is, relative to the widget: rounded so that every tile lands on whole device
      # pixels of the surface (the widget's own origin may sit on a fraction of one at scales like 1.25)
      let (wx, wy) = v.originOnSurface
      let fx = wx * sf - floor(wx * sf)
      let fy = wy * sf - floor(wy * sf)
      let bx = round(v.ox * dz - fx) + fx
      let by = round(v.oy * dz - fy) + fy
      hox = bx / dz
      hoy = by / dz
      let c0 = int(floor(x0 / span))
      let c1 = int(floor(min(x1, wpt - 1e-9) / span))
      let r0 = int(floor(y0 / span))
      let r1 = int(floor(min(y1, hpt - 1e-9) / span))
      var missing: seq[TileKey]
      covered = true
      for iy in r0 .. r1:
        for ix in c0 .. c1:
          let key = (zb, ix, iy)
          if key in v.tiles: exact.add (key, float(ix * TileSize) - bx, float(iy * TileSize) - by)
          else:
            missing.add key
            holes.add (float(ix) * span, float(iy) * span, float(ix + 1) * span, float(iy + 1) * span)
            covered = false
      # the most wanted last: the middle of the view first, then a ring around it (ready when the pan gets there)
      let cx = (x0 + x1) / 2 / span
      let cy = (y0 + y1) / 2 / span
      proc far(k: TileKey): float = abs(float(k.ix) + 0.5 - cx) + abs(float(k.iy) + 0.5 - cy)
      missing.sort(proc (a, b: TileKey): int = cmp(far(b), far(a)))
      var ring: seq[TileKey]
      let cmax = int(ceil(wpt / span)) - 1
      let rmax = int(ceil(hpt / span)) - 1
      for iy in max(0, r0 - 1) .. min(rmax, r1 + 1):
        for ix in max(0, c0 - 1) .. min(cmax, c1 + 1):
          if (ix < c0 or ix > c1 or iy < r0 or iy > r1) and (zb, ix, iy) notin v.tiles: ring.add (zb, ix, iy)
      ring.sort(proc (a, b: TileKey): int = cmp(far(b), far(a)))
      v.want = ring & missing
    else: v.want.setLen(0)                    # the zoom is changing: the tiles at hand stand in, scaled
    if not covered:
      for k, t in v.tiles:
        if k.zb == cast[uint64](dz): continue
        let span = float(TileSize) / tileZoom(k)
        let (a0, b0, a1, b1) = (float(k.ix) * span, float(k.iy) * span, float(k.ix + 1) * span, float(k.iy + 1) * span)
        if a1 < x0 or a0 > x1 or b1 < y0 or b0 > y1: continue
        if v.tileZ == dz:             # settled: only where a tile of this zoom is still missing
          var needed = false
          for (h0, k0, h1, k1) in holes:
            if a1 > h0 and a0 < h1 and b1 > k0 and b0 < k1:
              needed = true
              break
          if not needed: continue
        standIns.add k
      # the furthest from this zoom first, so the nearest end up on top
      standIns.sort(proc (a, b: TileKey): int = cmp(abs(log2(tileZoom(b) / dz)), abs(log2(tileZoom(a) / dz))))
  var r: GraphRect
  if not covered:
    # the overview: the smallest level sharp enough for this zoom (asked for once), drawn when decoded; until then
    # the sharpest level already decoded
    var want = 0
    let odz = if v.fitZ > 0: min(dz, v.fitZ * sf) else: dz   # vector tiles cover the zooms beyond fit
    for k in countdown(v.levels.len - 1, 0):
      if v.levelScale(k) >= odz * 0.9:
        want = k
        break
    if v.levels.len > 0 and not v.asked[want]:
      v.asked[want] = true
      jobs.send(DecodeJob(gen: v.gen, level: want, dark: v.dark, data: v.levelData[want]))
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
    v.dropSharperStale(want, tex)
    if tex != nil:
      inDevicePixels(s, sf):
        graphene_rect_init(addr r, cfloat(-v.ox * dz), cfloat(-v.oy * dz), cfloat(wpt * dz), cfloat(hpt * dz))
        # shrunk by more than half (a sharper level not decoded yet): mipmapped, else a plain texture node
        if wpt * dz < 0.5 * float(gdk_texture_get_width(tex)):
          gtk_snapshot_append_scaled_texture(s, tex, GSK_SCALING_FILTER_TRILINEAR, addr r)
        else: gtk_snapshot_append_texture(s, tex, addr r)
      if not timingReported and startedAt > 0:
        timingReported = true
        stderr.writeLine "timing: first sheet drawn " & $int((epochTime() - startedAt) * 1000) & " ms after launch"
    elif v.dark: fillRect(s, rgba(DarkLo / 255, DarkLo / 255, DarkLo / 255), -v.ox * v.z, -v.oy * v.z, wpt * v.z, hpt * v.z)
    else: fillRect(s, rgba(1, 1, 1), -v.ox * v.z, -v.oy * v.z, wpt * v.z, hpt * v.z)
  if v.sheet != nil:
    inDevicePixels(s, sf):
      # clipped to the sheet: at low zoom a tile reaches past its edge
      graphene_rect_init(addr r, cfloat(-v.ox * dz), cfloat(-v.oy * dz), cfloat(wpt * dz), cfloat(hpt * dz))
      gtk_snapshot_push_clip(s, addr r)
      for k in standIns:
        let tz = tileZoom(k)
        let span = float(TileSize) / tz
        v.tiles[k].used = v.frame
        graphene_rect_init(addr r, cfloat((float(k.ix) * span - v.ox) * dz), cfloat((float(k.iy) * span - v.oy) * dz),
                           cfloat(span * dz), cfloat(span * dz))
        # a plain texture node: GSK filters it as it draws (a scaled-texture node goes through a picture of its own
        # every frame); mipmapped only when shrunk by more than half, for the moment a zoom out takes to settle
        if dz / tz < 0.5: gtk_snapshot_append_scaled_texture(s, v.tiles[k].tex, GSK_SCALING_FILTER_TRILINEAR, addr r)
        else: gtk_snapshot_append_texture(s, v.tiles[k].tex, addr r)
      for (k, dx, dy) in exact:
        v.tiles[k].used = v.frame
        # one tile pixel per device pixel, on whole device pixels: nothing to filter
        graphene_rect_init(addr r, cfloat(dx), cfloat(dy), cfloat(TileSize), cfloat(TileSize))
        gtk_snapshot_append_texture(s, v.tiles[k].tex, addr r)
      gtk_snapshot_pop(s)
    v.pump()
  # hotspots: colour and border nodes (GSK draws them on the GPU), small Cairo nodes for the few dashed or round ones
  for t in v.tags:
    let x = (t.x0 - hox) * v.z
    let y = (t.y0 - hoy) * v.z
    let tw = (t.x1 - t.x0) * v.z
    let th = (t.y1 - t.y0) * v.z
    if x + tw < -8 or y + th < -8 or x > float(w) + 8 or y > float(h) + 8: continue
    var (cr, cg, cb) = markerColor(t.status, t.photos, v.coverage, v.dark)
    let sel = t.id == v.selected
    let hit = t.id in v.hits
    let dim = v.floorOn and t.id notin v.floorIds
    if t.id in v.linked:
      (cr, cg, cb) = if v.dark: lightenForDark(0.1, 0.65, 0.3) else: (0.1, 0.65, 0.3)
      fillRect(s, rgba(cr, cg, cb, 0.3), x, y, tw, th)
    if dim:
      strokeRect(s, rgba(cr, cg, cb, 0.18), x, y, tw, th, 1)
      continue
    if v.coverage and t.status != "pending" and not (sel or hit):
      fillRect(s, rgba(cr, cg, cb, 0.28), x, y, tw, th)
    if sel or hit:
      if hit and not sel: fillRect(s, rgba(1.0, 0.85, 0.0, 0.28), x, y, tw, th)
      else: fillRect(s, rgba(cr, cg, cb, 0.28), x, y, tw, th)
    let lw = if sel: 3.0 else: 1.5
    let a = if sel or v.dark: 1.0 else: 0.75
    if t.status == "pending":
      cairoIn(s, x - lw, y - lw, tw + 2 * lw, th + 2 * lw, c):
        var dash = [4.0, 3.0]
        cairo_set_dash(c, addr dash[0], 2, 0)
        cairo_set_source_rgba(c, cr, cg, cb, a)
        cairo_set_line_width(c, lw)
        cairo_rectangle(c, x, y, tw, th)
        cairo_stroke(c)
    else: strokeRect(s, rgba(cr, cg, cb, a), x, y, tw, th, lw)
    if t.id in v.chosen:
      # selected for "… for all": a black and yellow ring outside the box, whatever colouring is on
      strokeRect(s, rgba(0, 0, 0, 0.9), x - 4, y - 4, tw + 8, th + 8, 4)
      strokeRect(s, rgba(1, 0.85, 0, 1), x - 4, y - 4, tw + 8, th + 8, 2)
  if v.symbolBox.len == 4:
    # the valve symbol the open panel's type was read from: dashed magenta, apart from every tag colour
    let b = v.symbolBox
    let (mr, mg, mb) = if v.dark: lightenForDark(0.69, 0.09, 0.62) else: (0.69, 0.09, 0.62)
    let bx = (b[0] - hox) * v.z - 3
    let by = (b[1] - hoy) * v.z - 3
    let bw = (b[2] - b[0]) * v.z + 6
    let bh = (b[3] - b[1]) * v.z + 6
    fillRect(s, rgba(mr, mg, mb, 0.16), bx, by, bw, bh)
    cairoIn(s, bx - 3, by - 3, bw + 6, bh + 6, c):
      var dash = [5.0, 3.0]
      cairo_set_dash(c, addr dash[0], 2, 0)
      cairo_set_source_rgba(c, mr, mg, mb, 1.0)
      cairo_set_line_width(c, 2.5)
      cairo_rectangle(c, bx, by, bw, bh)
      cairo_stroke(c)
  # off-page connectors: violet dashed circles, unlike the tags' rectangles
  for i, l in v.links:
    let cx = ((l.x0 + l.x1) / 2 - hox) * v.z
    let cy = ((l.y0 + l.y1) / 2 - hoy) * v.z
    let rad = max(6.0, max(l.x1 - l.x0, l.y1 - l.y0) / 2 * v.z + 3)
    if cx + rad < 0 or cy + rad < 0 or cx - rad > float(w) or cy - rad > float(h): continue
    let sel = i == v.linkSel
    let (lr, lg, lb) = linkColor(v.dark)
    cairoIn(s, cx - rad - 3, cy - rad - 3, 2 * rad + 6, 2 * rad + 6, c):
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
  if (v.selecting or v.marking) and v.mark[2] != v.mark[0]:
    let mx = (v.mark[0] - hox) * v.z
    let my = (v.mark[1] - hoy) * v.z
    let mw = (v.mark[2] - v.mark[0]) * v.z
    let mh = (v.mark[3] - v.mark[1]) * v.z
    if v.selecting:
      cairoIn(s, mx - 2, my - 2, mw + 4, mh + 4, c):
        var dash = [6.0, 4.0]
        cairo_set_dash(c, addr dash[0], 2, 0)
        cairo_set_source_rgba(c, 0.1, 0.35, 0.85, 0.9)
        cairo_set_line_width(c, 2)
        cairo_rectangle(c, mx, my, mw, mh)
        cairo_stroke(c)
    if v.marking: strokeRect(s, rgba(0.85, 0.1, 0.1, 0.9), mx, my, mw, mh, 2)

proc drawInto*(v: Viewer, s: W) =
  ## the view as the widget draws it, into a snapshot of the caller's (tests: a picture at device pixels)
  v.snapshot(s, int(gtk_widget_get_width(v.widget)), int(gtk_widget_get_height(v.widget)))

proc tagsIn*(v: Viewer, x0, y0, x1, y1: float): seq[string] =
  ## the tags whose box intersects the box (points)
  for t in v.tags:
    if t.status != "pending" and t.x0 <= x1 and t.x1 >= x0 and t.y0 <= y1 and t.y1 >= y0: result.add t.id

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

# What the viewer's gestures and keys do, as procs of their own: the tests (KKS_TEST_VIEWER) drive them, the headless
# test session having no pointer or keyboard.
proc dragBegin*(v: Viewer, x, y: float) =
  v.dragOx = v.ox
  v.dragOy = v.oy
  if v.marking or v.selecting:
    v.markStart = (v.ox + x / v.z, v.oy + y / v.z)
    v.mark = (v.markStart[0], v.markStart[1], v.markStart[0], v.markStart[1])

proc dragUpdate*(v: Viewer, dx, dy: float) =
  if v.marking or v.selecting:
    let (sx, sy) = v.markStart
    let ex = sx + dx / v.z
    let ey = sy + dy / v.z
    v.mark = (min(sx, ex), min(sy, ey), max(sx, ex), max(sy, ey))
  else:
    v.ox = v.dragOx - dx / v.z
    v.oy = v.dragOy - dy / v.z
  gtk_widget_queue_draw(v.widget)

proc dragEnd*(v: Viewer, dx, dy: float) =
  if v.marking and abs(dx) + abs(dy) > 6:
    if v.onMark != nil: v.onMark(v.mark[0], v.mark[1], v.mark[2], v.mark[3])
  elif v.selecting:
    let b = v.mark
    v.mark = (0.0, 0.0, 0.0, 0.0)
    gtk_widget_queue_draw(v.widget)
    if abs(dx) + abs(dy) > 6 and v.onBox != nil: v.onBox(b[0], b[1], b[2], b[3])
  elif v.onView != nil: v.onView()

proc clickAt*(v: Viewer, x, y: float) =
  if v.marking: return
  let li = if v.selecting: -1 else: v.hitLink(x, y)   # the select mode: clicks pick tags only
  if li >= 0:
    if v.onLink != nil: v.onLink(li)
    return
  let id = v.hitTag(x, y)
  if id.len > 0 and v.selecting:      # the select mode: the app toggles it (v.chosen), the panel stays as it is
    if v.onSelect != nil: v.onSelect(id)
  elif id.len > 0:
    v.selected = id
    gtk_widget_queue_draw(v.widget)
    if v.onSelect != nil: v.onSelect(id)

proc keyPress*(v: Viewer, keyval: cuint): bool =
  ## The drawing's own keys: panning and zooming. Escape is not one of them: it goes on to the window, which ends
  ## whatever mode the drawing is in the way that mode's own button does (kks_explorer.nim endMode). Before #183 the
  ## viewer ended Mark a tag here by itself, and the banner and the crosshair stayed.
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
  else: return false
  gtk_widget_queue_draw(v.widget)
  if v.onView != nil: v.onView()
  true

proc newViewer*(): Viewer =
  let v = Viewer(z: 1, linkSel: -1)
  GC_ref(v)
  v.widget = kks_view_new(cast[pointer](snapCb), cast[pointer](v))
  gtk_widget_set_cursor_from_name(v.widget, "grab")
  # pan
  let drag = gtk_gesture_drag_new()
  drag.onXY("drag-begin", proc (x, y: float) = v.dragBegin(x, y))
  drag.onXY("drag-update", proc (dx, dy: float) = v.dragUpdate(dx, dy))
  drag.onXY("drag-end", proc (dx, dy: float) = v.dragEnd(dx, dy))
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
    v.clickAt(x, y))
  gtk_widget_add_controller(v.widget, click)
  # keyboard
  let keys = gtk_event_controller_key_new()
  keys.onKey(proc (keyval, state: cuint): bool = v.keyPress(keyval))
  gtk_widget_add_controller(v.widget, keys)
  timeout(50, proc (): bool =
    v.pollDecodes()
    true)
  v
