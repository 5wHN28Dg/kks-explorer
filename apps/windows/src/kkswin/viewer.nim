## The drawing viewer (R1; decisions 0015, 0016, 0033): the overview pyramid below its own resolution, vector tiles
## rendered by Direct2D on worker threads above it (kks_d2d.cpp), tag hotspots on top. Drag to pan, wheel to zoom,
## double-click to zoom in, click a tag. The same model as the Android and GNOME viewers. Dark drawings (setDark): tiles
## and overview levels light-on-dark, made on the worker threads (kks_d2d.cpp kks_dark_rgb, a copy of
## apps/common/darkcolor.nim); the "Select tags" mode (`selecting`): a click toggles a tag, a dragged box adds the tags
## it touches (multi.nim).

import std/[tables, math, sets, algorithm]
import w32, ui, darkcolor

{.compile("kks_d2d.cpp", "-std=c++17").}
{.passL: "-ljxl -ljxl_cms -lhwy -lbrotlidec -lbrotlienc -lbrotlicommon -ljxl_threads -lstdc++".}

proc d2dInit(): cint {.importc: "kks_d2d_init", cdecl.}
proc sheetOpen(flat: pointer, n: csize_t): pointer {.importc: "kks_sheet_open", cdecl.}
proc sheetClose(s: pointer) {.importc: "kks_sheet_close", cdecl.}
proc sheetW(s: pointer): cint {.importc: "kks_sheet_width", cdecl.}
proc sheetH(s: pointer): cint {.importc: "kks_sheet_height", cdecl.}
proc tileRequest(key: clonglong, s: pointer, tz, x0, y0: cfloat, size: cint, dark: cint) {.importc: "kks_tile_request", cdecl.}
proc jxlRequest(key: clonglong, data: pointer, n: csize_t, dark: cint) {.importc: "kks_jxl_request", cdecl.}
proc jobsClear() {.importc: "kks_jobs_clear", cdecl.}
proc jobDone(key: ptr clonglong, w, h: ptr cint, px: ptr pointer): cint {.importc: "kks_job_done", cdecl.}
proc cfree(p: pointer) {.importc: "kks_free", cdecl.}
proc viewNew(h: HWND): pointer {.importc: "kks_view_new", cdecl.}
proc viewResize(v: pointer, w, h: cint) {.importc: "kks_view_resize", cdecl.}
proc viewBitmap(v: pointer, bgra: pointer, w, h: cint): cint {.importc: "kks_view_bitmap", cdecl.}
proc viewBitmapFree(v: pointer, h: cint) {.importc: "kks_view_bitmap_free", cdecl.}
proc viewBegin(v: pointer, r, g, b: cfloat): cint {.importc: "kks_view_begin", cdecl.}
proc viewDrawBitmap(v: pointer, h: cint, x0, y0, x1, y1: cfloat, smooth: cint) {.importc: "kks_view_draw_bitmap", cdecl.}
proc viewRect(v: pointer, x0, y0, x1, y1: cfloat, rgb: cuint, alpha: cfloat, fill: cint, width: cfloat, dashed: cint) {.importc: "kks_view_rect", cdecl.}
proc viewEnd(v: pointer): cint {.importc: "kks_view_end", cdecl.}
proc viewCircle(v: pointer, cx, cy, r: cfloat, rgb: cuint, alpha: cfloat, fill: cint, width: cfloat, dashed: cint) {.importc: "kks_view_circle", cdecl.}
{.compile("kks_uia.cpp", "-std=c++17").}
{.passL: "-luiautomationcore -loleaut32".}
proc uiaNew(h: HWND, count, info, invoke: pointer, ud: pointer): pointer {.importc: "kks_uia_new", cdecl.}
proc uiaGetObject(root: pointer, h: HWND, w: WPARAM, l: LPARAM): LRESULT {.importc: "kks_uia_getobject", cdecl.}
proc uiaChanged(root: pointer) {.importc: "kks_uia_changed", cdecl.}
proc jxlDecode*(data: pointer, n: csize_t, w, h: ptr cint): pointer {.importc: "kks_jxl_decode", cdecl.}
proc freeNative*(p: pointer) = cfree(p)

type
  TagBox* = object
    id*, status*, code*: string
    photos*: string                ## both · equipment · plate · none (core model.photoCover)
    name*: string                  ## a connector's name for screen readers ("Connector C16, continues on …")
    x0*, y0*, x1*, y1*: float      ## points

  Pixels = object
    w, h: int
    px: seq[byte]

  Viewer* = ref object
    coverage*: bool             ## colour the tags by their photos instead of by how they were read
    dark*: bool                 ## dark drawings (setDark): tiles and overview light-on-dark, markers lightened
    hwnd*: HWND
    v: pointer
    sheet: pointer
    sheetId: string
    gen: int
    scale0*: float              ## the pyramid's level-0 scale, px per point
    levels: seq[Pixels]         ## decoded, kept to re-upload after a lost device
    levelBmp: seq[cint]
    levelAsked: seq[bool]
    stale: seq[cint]            ## the levels shown before a dark-drawings switch, until this mode's arrive (bitmaps)
    levelData*: proc (k: int): string   ## the app gives the JXL bytes of level k
    tiles: Table[string, (Pixels, cint)]
    tileOrder: seq[string]
    pending: HashSet[string]
    z*, ox*, oy*: float         ## px per point, view origin in points
    fitted: bool
    tags*: seq[TagBox]
    selected*: string
    highlight*: HashSet[string]
    dimmed*: HashSet[string]
    dimming*: bool
    onTag*: proc (id: string)
    marking*: bool
    onMark*: proc (x0, y0, x1, y1: float)
    mark: (float, float, float, float)
    markOn: bool
    selecting*: bool            ## "Select tags" mode: a click toggles a tag (onTag), a dragged box adds the tags it touches
    chosen*: HashSet[string]    ## the selected tags (a distinct outline)
    onBox*: proc (x0, y0, x1, y1: float)   ## a box dragged in the select mode (points)
    onEscape*: proc ()          ## Escape in the select mode
    links*: seq[TagBox]         ## off-page connectors (C16, D2 …): id = the label, box in points (links.nim)
    linkSel*: int               ## the connector just arrived at (-1 none), drawn bold
    onLink*: proc (i: int)      ## a connector clicked or invoked: index into links
    dragging: bool
    dragMoved: bool
    lastX, lastY: int
    uia: pointer                ## the UI Automation provider (kks_uia.cpp): tags and connectors on screen as buttons
    onScreen: seq[int]          ## indices into tags (a connector j: -(j + 1)), reading order, at most 200 (what the
                                ## provider exposes)

const
  Tile = 512
  MaxTiles = 160

var viewers = initTable[HWND, Viewer]()

proc invalidate*(v: Viewer) = InvalidateRect(v.hwnd, nil, 0)

proc hasOverview*(v: Viewer): bool =
  ## an overview level is on screen (startup timing)
  for b in v.levelBmp:
    if b > 0: return true
  false

proc size(v: Viewer): (float, float) =
  if v.sheet != nil: return (float(sheetW(v.sheet)) / 64, float(sheetH(v.sheet)) / 64)
  for k, l in v.levels:
    if l.w > 0:
      let s = v.scale0 / float(1 shl k)
      return (float(l.w) / s, float(l.h) / s)
  (1.0, 1.0)

proc client(v: Viewer): (float, float) =
  var r: RECT
  GetClientRect(v.hwnd, addr r)
  (float(r.right), float(r.bottom))

proc fit*(v: Viewer) =
  let (w, h) = v.size
  let (cw, ch) = v.client
  if cw < 2 or ch < 2 or w <= 1: return
  v.z = min(cw / w, ch / h) * 0.98
  v.ox = -(cw / v.z - w) / 2
  v.oy = -(ch / v.z - h) / 2
  v.fitted = true
  v.invalidate()

# Tile jobs carry a serial number (above 10^12, so they never collide with pyramid keys gen·100 + level); a side table
# maps it back to the tile's generation and name.
var tileSerial = 0
var tileNames = initTable[int, (int, string)]()   # serial → (gen, name)

proc newGeneration(v: Viewer) =
  ## a new sheet or colour mode: queued jobs go, and so do the names of tiles of older generations (a dropped job never
  ## reports back, so its entry would stay forever; one still running reports a serial no longer known: ignored)
  inc v.gen
  jobsClear()
  var old: seq[int]
  for serial, (g, _) in tileNames:
    if g != v.gen: old.add serial
  for serial in old: tileNames.del serial

proc clearTiles(v: Viewer) =
  for k, t in v.tiles:
    if t[1] > 0: viewBitmapFree(v.v, t[1])
  v.tiles.clear()
  v.tileOrder.setLen(0)
  v.pending.clear()

proc dropStale(v: Viewer) =
  for b in v.stale:
    if b > 0: viewBitmapFree(v.v, b)
  v.stale = @[]

proc setSheet*(v: Viewer, id: string, flat: string, scale: float, nLevels: int) =
  v.newGeneration()
  v.clearTiles()
  for b in v.levelBmp:
    if b > 0: viewBitmapFree(v.v, b)
  v.dropStale()
  if v.sheet != nil: sheetClose(v.sheet)
  v.sheet = if flat.len > 0: sheetOpen(unsafeAddr flat[0], csize_t(flat.len)) else: nil
  v.sheetId = id
  v.scale0 = scale
  v.levels = newSeq[Pixels](nLevels)
  v.levelBmp = newSeq[cint](nLevels)
  v.levelAsked = newSeq[bool](nLevels)
  v.fitted = false
  v.selected = ""
  v.links = @[]
  v.linkSel = -1
  if nLevels > 0:
    v.levelAsked[nLevels - 1] = true
    let d = v.levelData(nLevels - 1)
    if d.len > 0: jxlRequest(clonglong(v.gen * 100 + nLevels - 1), unsafeAddr d[0], csize_t(d.len), cint(ord(v.dark)))
  v.invalidate()

proc askLevel(v: Viewer, k: int) =
  if k < 0 or k >= v.levels.len or v.levelAsked[k]: return
  v.levelAsked[k] = true
  let d = v.levelData(k)
  if d.len > 0: jxlRequest(clonglong(v.gen * 100 + k), unsafeAddr d[0], csize_t(d.len), cint(ord(v.dark)))

proc upload(v: Viewer, p: Pixels): cint =
  if p.w == 0: return 0
  viewBitmap(v.v, unsafeAddr p.px[0], cint(p.w), cint(p.h))


proc requestTile(v: Viewer, name: string, tz, x0, y0: float) =
  inc tileSerial
  tileNames[tileSerial] = (v.gen, name)
  tileRequest(clonglong(1_000_000_000_000 + tileSerial), v.sheet, cfloat(tz), cfloat(x0), cfloat(y0), Tile, cint(ord(v.dark)))

proc poll*(v: Viewer) =
  ## take finished tiles and pyramid decodes (call from a timer); redraw if anything arrived
  var key: clonglong
  var w, h: cint
  var px: pointer
  var any = false
  while jobDone(addr key, addr w, addr h, addr px) == 1:
    var p = Pixels(w: int(w), h: int(h))
    if px != nil:
      p.px = newSeq[byte](int(w) * int(h) * 4)
      copyMem(addr p.px[0], px, p.px.len)
      cfree(px)
    let k = int64(key)
    if k >= 1_000_000_000_000:
      let serial = int(k - 1_000_000_000_000)
      let (g, name) = tileNames.getOrDefault(serial, (-1, ""))
      tileNames.del serial
      if g == v.gen:
        v.pending.excl name
        if p.w > 0:
          v.tiles[name] = (p, v.upload(p))
          v.tileOrder.add name
          while v.tileOrder.len > MaxTiles:
            let old = v.tileOrder[0]
            v.tileOrder.delete(0)
            if old in v.tiles:
              if v.tiles[old][1] > 0: viewBitmapFree(v.v, v.tiles[old][1])
              v.tiles.del old
          any = true
    else:
      let g = int(k div 100)
      let lvl = int(k mod 100)
      if g == v.gen and lvl < v.levels.len and p.w == 0:
        for k in lvl ..< v.stale.len:     # this mode's level failed: the old mode's stay no longer than it would
          if v.stale[k] > 0:
            viewBitmapFree(v.v, v.stale[k])
            v.stale[k] = 0
        any = true
      if g == v.gen and lvl < v.levels.len and p.w > 0:
        v.levels[lvl] = p
        if v.levelBmp[lvl] > 0: viewBitmapFree(v.v, v.levelBmp[lvl])
        v.levelBmp[lvl] = v.upload(p)
        for k in lvl ..< v.stale.len:     # the old mode's levels no sharper than this one go
          if v.stale[k] > 0:
            viewBitmapFree(v.v, v.stale[k])
            v.stale[k] = 0
        if not v.fitted: v.fit()
        any = true
  if any: v.invalidate()

proc setDark*(v: Viewer, on: bool) =
  ## dark drawings on or off, at once: cached tiles are dropped (rendered again in the new colours) and the overview
  ## levels decoded again (the smallest first). Jobs queued for the old mode are dropped; the levels shown so far stay
  ## until this mode's arrive (never blank)
  if v.dark == on: return
  v.dark = on
  v.newGeneration()
  v.clearTiles()
  if v.stale.len != v.levels.len: v.stale = newSeq[cint](v.levels.len)
  for k in 0 ..< v.levels.len:
    if v.levelBmp[k] > 0:           # this mode's level replaces an older stale one; else the older one stays
      if v.stale[k] > 0: viewBitmapFree(v.v, v.stale[k])
      v.stale[k] = v.levelBmp[k]
    v.levelBmp[k] = 0
    v.levels[k] = Pixels()
    v.levelAsked[k] = false
  if v.levels.len > 0:
    v.levelAsked[^1] = true
    let d = v.levelData(v.levels.len - 1)
    if d.len > 0: jxlRequest(clonglong(v.gen * 100 + v.levels.len - 1), unsafeAddr d[0], csize_t(d.len), cint(ord(on)))
  v.invalidate()

proc reupload(v: Viewer) =
  ## after a lost device (D2DERR_RECREATE_TARGET) every bitmap is gone (the old mode's levels too: their handles would
  ## name new bitmaps now)
  for k in 0 ..< v.stale.len: v.stale[k] = 0
  for k in 0 ..< v.levels.len: v.levelBmp[k] = v.upload(v.levels[k])
  for name, t in v.tiles.mpairs: t[1] = v.upload(t[0])

proc screenRect(v: Viewer, t: TagBox): RECT =
  RECT(left: int32((t.x0 - v.ox) * v.z), top: int32((t.y0 - v.oy) * v.z), right: int32((t.x1 - v.ox) * v.z), bottom: int32((t.y1 - v.oy) * v.z))

proc boxOf(v: Viewer, i: int): TagBox =
  ## an onScreen entry's box: a tag, or a connector (negative)
  if i >= 0: v.tags[i] else: v.links[-i - 1]

proc updateOnScreen*(v: Viewer) =
  ## the tags and connectors inside the view in reading order (rows of about a tag's height, each left to right); the
  ## provider is told when the set changes. The select mode picks tags only: its connectors aren't buttons then
  let (cw, ch) = v.client
  var idx: seq[int]
  for i, t in v.tags:
    if t.status == "pending": continue
    let r = v.screenRect(t)
    if r.right > 0 and r.bottom > 0 and float(r.left) < cw and float(r.top) < ch: idx.add i
  if not v.selecting:
    for j, l in v.links:
      let r = v.screenRect(l)
      if r.right > 0 and r.bottom > 0 and float(r.left) < cw and float(r.top) < ch: idx.add(-j - 1)
  idx.sort(proc (a, b: int): int =
    let ba = v.boxOf(a)
    let bb = v.boxOf(b)
    let ra = int(ba.y0 / 12)
    let rb = int(bb.y0 / 12)
    if ra != rb: cmp(ra, rb) else: cmp(ba.x0, bb.x0))
  if idx.len > 200: idx.setLen(200)
  if idx != v.onScreen:
    v.onScreen = idx
    if v.uia != nil: uiaChanged(v.uia)

proc coverWords(photos: string): string =
  case photos
  of "both": "equipment and tag plate photos"
  of "equipment": "equipment photo only"
  of "plate": "tag plate photo only"
  else: "no photos"

proc statusWords(s: string): string =
  case s
  of "review": "needs checking"
  of "verified": "verified"
  else: "read automatically"

proc a11yCount(ud: pointer): cint {.cdecl.} = cint(cast[Viewer](ud).onScreen.len)

proc a11yInfo(ud: pointer, i: cint, name: ptr UncheckedArray[Utf16Char], cap: cint, r: ptr RECT): cint {.cdecl.} =
  let v = cast[Viewer](ud)
  if i < 0 or int(i) >= v.onScreen.len: return 0
  let ki = v.onScreen[int(i)]
  # the lists may have changed since the last paint (a sheet switch, a reload): an index gone stale names nothing
  if (ki >= 0 and ki >= v.tags.len) or (ki < 0 and -ki - 1 >= v.links.len): return 0
  let t = v.boxOf(ki)
  let text = if ki < 0: t.name
             else: (if t.code.len > 0: t.code else: "Unread tag") & ", " & (if v.coverage: coverWords(t.photos) else: statusWords(t.status)) &
                   (if t.id == v.selected: ", selected" else: "") & (if t.id in v.chosen: ", in the selection" else: "")
  let ws = newWideCString(text)
  var k = 0
  while k < int(cap) - 1 and k < ws.len:
    name[k] = ws[k]
    inc k
  name[k] = Utf16Char(0)
  var rr = v.screenRect(t)
  var c: RECT
  GetClientRect(v.hwnd, addr c)
  rr.left = max(rr.left, 0); rr.top = max(rr.top, 0); rr.right = min(rr.right, c.right); rr.bottom = min(rr.bottom, c.bottom)
  r[] = rr
  1

proc a11yInvoke(ud: pointer, i: cint) {.cdecl.} = discard    # invocations come back as WM_APP + 7 (kks_uia.cpp)

proc coverColor(photos: string): uint32 =
  ## the photo coverage colours, the same on every client: both green, the equipment only amber, the tag plate only
  ## blue, none red
  case photos
  of "both": 0x2EA043'u32
  of "equipment": 0xE69600'u32
  of "plate": 0x1E78E6'u32
  else: 0xDC2828'u32

proc colorOf(status: string): uint32 =
  case status
  of "verified": 0x269940'u32
  of "review": 0xF28C00'u32
  of "pending": 0x8C33BF'u32
  else: 0x1A66E6'u32

proc lighten(c: uint32): uint32 =
  ## a marker colour raised toward white for dark drawings (darkcolor.lightenForDark: each keeps 3:1 on the dark paper)
  let (r, g, b) = lightenForDark(float((c shr 16) and 255) / 255, float((c shr 8) and 255) / 255, float(c and 255) / 255)
  (uint32(round(r * 255)) shl 16) or (uint32(round(g * 255)) shl 8) or uint32(round(b * 255))

proc paint(v: Viewer) =
  # around the sheet: lighter than the dark paper in dark drawings
  if (if v.dark: viewBegin(v.v, 0.24, 0.24, 0.26) else: viewBegin(v.v, 0.82, 0.83, 0.85)) == 0: return
  let (cw, ch) = v.client
  if v.levels.len > 0:
    if not v.fitted: v.fit()
    let (w, h) = v.size
    let dst = (-v.ox * v.z, -v.oy * v.z, (w - v.ox) * v.z, (h - v.oy) * v.z)
    # 1. the overview: the smallest level sharp enough (asked once), else the sharpest one decoded
    var want = 0
    for k in countdown(v.levels.high, 0):
      if v.scale0 / float(1 shl k) >= v.z * 0.9:
        want = k
        break
    v.askLevel(want)
    var bmp: cint = 0
    if v.levelBmp[want] > 0: bmp = v.levelBmp[want]
    elif want < v.stale.len and v.stale[want] > 0: bmp = v.stale[want]   # shown before a dark switch: not blurrier
    else:
      for k in 0 ..< v.levels.len:
        if v.levelBmp[k] > 0:
          bmp = v.levelBmp[k]
          break
      if bmp == 0:
        for k in 0 ..< v.stale.len:
          if v.stale[k] > 0:
            bmp = v.stale[k]
            break
    # the other mode's levels sharper than the zoom wants aren't shown again: they go now (a level 0 is large)
    for k in 0 ..< min(want, v.stale.len):
      if v.stale[k] > 0 and v.stale[k] != bmp:
        viewBitmapFree(v.v, v.stale[k])
        v.stale[k] = 0
    if bmp > 0: viewDrawBitmap(v.v, bmp, cfloat(dst[0]), cfloat(dst[1]), cfloat(dst[2]), cfloat(dst[3]), 1)
    else: viewRect(v.v, cfloat(dst[0]), cfloat(dst[1]), cfloat(dst[2]), cfloat(dst[3]),
                   (if v.dark: uint32(DarkLo) * 0x010101'u32 else: 0xFFFFFF'u32), 1, 1, 0, 0)
    # 2. vector tiles once the overview isn't sharp enough
    if v.sheet != nil and v.z > v.scale0 * 1.05:
      let e = int(ceil(log2(v.z)))
      let tz = pow(2.0, float(e))
      let span = float(Tile) / tz
      let x0 = max(0.0, v.ox)
      let y0 = max(0.0, v.oy)
      let x1 = min(w, v.ox + cw / v.z)
      let y1 = min(h, v.oy + ch / v.z)
      for iy in int(floor(y0 / span)) .. int(floor(y1 / span)):
        for ix in int(floor(x0 / span)) .. int(floor(x1 / span)):
          let name = $e & ":" & $ix & ":" & $iy
          let r = ((float(ix) * span - v.ox) * v.z, (float(iy) * span - v.oy) * v.z,
                   (float(ix + 1) * span - v.ox) * v.z, (float(iy + 1) * span - v.oy) * v.z)
          if name in v.tiles:
            viewDrawBitmap(v.v, v.tiles[name][1], cfloat(r[0]), cfloat(r[1]), cfloat(r[2]), cfloat(r[3]), 1)
          elif name notin v.pending:
            v.pending.incl name
            v.requestTile(name, tz, float(ix) * span, float(iy) * span)
    # 3. hotspots
    let dens = float(GetDpiForWindow(v.hwnd)) / 96
    for t in v.tags:
      let r = ((t.x0 - v.ox) * v.z, (t.y0 - v.oy) * v.z, (t.x1 - v.ox) * v.z, (t.y1 - v.oy) * v.z)
      if r[2] < 0 or r[3] < 0 or r[0] > cw or r[1] > ch: continue
      let col0 = if v.coverage and t.status != "pending": coverColor(t.photos) else: colorOf(t.status)
      let col = if v.dark: lighten(col0) else: col0
      let dim = v.dimming and t.id notin v.dimmed
      if v.coverage and t.status != "pending" and not dim and t.id != v.selected:
        viewRect(v.v, cfloat(r[0]), cfloat(r[1]), cfloat(r[2]), cfloat(r[3]), col, 0.28, 1, 0, 0)
      if t.id in v.highlight: viewRect(v.v, cfloat(r[0]), cfloat(r[1]), cfloat(r[2]), cfloat(r[3]),
                                       (if v.dark: lighten(0x1AA64D) else: 0x1AA64D), 0.3, 1, 0, 0)
      if t.id == v.selected: viewRect(v.v, cfloat(r[0]), cfloat(r[1]), cfloat(r[2]), cfloat(r[3]), col, 0.28, 1, 0, 0)
      viewRect(v.v, cfloat(r[0]), cfloat(r[1]), cfloat(r[2]), cfloat(r[3]), col, (if dim: 0.18 else: 1.0), 0,
               cfloat((if t.id == v.selected: 3.0 else: 1.5) * dens), cint(ord(t.status == "pending")))
      if t.id in v.chosen:
        # selected for "… for all": a black and yellow ring outside the box, whatever colouring is on
        let o = 4 * dens
        viewRect(v.v, cfloat(r[0] - o), cfloat(r[1] - o), cfloat(r[2] + o), cfloat(r[3] + o), 0x000000, 0.9, 0, cfloat(4 * dens), 0)
        viewRect(v.v, cfloat(r[0] - o), cfloat(r[1] - o), cfloat(r[2] + o), cfloat(r[3] + o), 0xFFD900, 1, 0, cfloat(2 * dens), 0)
    # 4. off-page connectors: violet dashed circles, unlike the tags' rectangles (the GNOME viewer's)
    let lc = if v.dark: lighten(0x8C33D9) else: 0x8C33D9'u32
    for i, l in v.links:
      let cx = ((l.x0 + l.x1) / 2 - v.ox) * v.z
      let cy = ((l.y0 + l.y1) / 2 - v.oy) * v.z
      let rad = max(6.0 * dens, max(l.x1 - l.x0, l.y1 - l.y0) / 2 * v.z + 3 * dens)
      if cx + rad < 0 or cy + rad < 0 or cx - rad > cw or cy - rad > ch: continue
      let sel = i == v.linkSel
      viewCircle(v.v, cfloat(cx), cfloat(cy), cfloat(rad), lc, (if sel: 0.3 else: 0.12), 1, 0, 0)
      viewCircle(v.v, cfloat(cx), cfloat(cy), cfloat(rad), lc, 0.9, 0, cfloat((if sel: 3.5 else: 2.0) * dens),
                 cint(ord(not sel)))
    if v.markOn:
      let m = v.mark
      viewRect(v.v, cfloat((m[0] - v.ox) * v.z), cfloat((m[1] - v.oy) * v.z), cfloat((m[2] - v.ox) * v.z),
               cfloat((m[3] - v.oy) * v.z), (if v.selecting: 0x1A59D9'u32 else: 0x8C33BF'u32), 1, 0, cfloat(2 * dens), 1)
  if viewEnd(v.v) == 0: v.reupload()
  v.updateOnScreen()

proc zoomAt*(v: Viewer, f, px, py: float) =
  let (w, h) = v.size
  let (cw, ch) = v.client
  let minZ = min(cw / w, ch / h) * 0.25
  let nz = clamp(v.z * f, minZ, 16 * max(1.0, v.scale0))
  let sx = v.ox + px / v.z
  let sy = v.oy + py / v.z
  v.z = nz
  v.ox = sx - px / v.z
  v.oy = sy - py / v.z
  v.invalidate()

proc centerOn*(v: Viewer, x0, y0, x1, y1: float) =
  let (cw, ch) = v.client
  v.z = min(16 * max(1.0, v.scale0), max(v.z, min(cw / max(1.0, (x1 - x0) * 5), ch / max(1.0, (y1 - y0) * 8))))
  v.ox = (x0 + x1) / 2 - cw / v.z / 2
  v.oy = (y0 + y1) / 2 - ch / v.z / 2
  v.fitted = true
  v.invalidate()

proc endSelecting*(v: Viewer) =
  ## the select mode ends (Escape, Done, a send): a box being dragged goes with it, and the rest of that drag does
  ## nothing (no pan from where the box started)
  v.selecting = false
  if v.markOn or v.dragging:
    v.markOn = false
    v.dragging = false
    v.invalidate()

proc tagsIn*(v: Viewer, x0, y0, x1, y1: float): seq[string] =
  ## the tags whose box intersects the box (points)
  for t in v.tags:
    if t.status != "pending" and t.x0 <= x1 and t.x1 >= x0 and t.y0 <= y1 and t.y1 >= y0: result.add t.id

proc hit(v: Viewer, x, y: int): string =
  let px = v.ox + float(x) / v.z
  let py = v.oy + float(y) / v.z
  let pad = 6 / v.z
  var best = -1.0
  for t in v.tags:
    if t.status != "pending" and px >= t.x0 - pad and px <= t.x1 + pad and py >= t.y0 - pad and py <= t.y1 + pad:
      let a = (t.x1 - t.x0) * (t.y1 - t.y0)
      if best < 0 or a < best:
        best = a
        result = t.id

proc hitLink(v: Viewer, x, y: int): int =
  ## the connector under (x, y) in window px, -1 none (a little slack: they are small)
  result = -1
  let px = v.ox + float(x) / v.z
  let py = v.oy + float(y) / v.z
  let pad = 6 / v.z
  for i, l in v.links:
    if px >= l.x0 - pad and px <= l.x1 + pad and py >= l.y0 - pad and py <= l.y1 + pad: return i

proc viewProc0(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT

proc viewProc(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT {.stdcall.} =
  try: viewProc0(h, m, w, l)
  except CatchableError as e:
    report(e)
    0

proc viewProc0(h: HWND, m: UINT, w: WPARAM, l: LPARAM): LRESULT =
  let v = viewers.getOrDefault(h)
  if v == nil: return DefWindowProcW(h, m, w, l)
  case m
  of WM_GETOBJECT:
    if v.uia != nil:
      let r = uiaGetObject(v.uia, h, w, l)
      if r != 0: return r
  of WM_APP + 7:      # a screen reader invoked a tag (kks_uia.cpp)
    let i = int(w)
    if i < v.onScreen.len:
      let k = v.onScreen[i]
      if k >= v.tags.len: return 0             # stale (the tags changed since the last paint)
      if k < 0:                                # a connector: where its line continues (links.nim)
        if v.onLink != nil and -k - 1 < v.links.len: v.onLink(-k - 1)
        return 0
      let id = v.tags[k].id
      if not v.selecting: v.selected = id     # the select mode: the app toggles it (chosen), the panel stays
      v.invalidate()
      if v.onTag != nil: v.onTag(id)
    return 0
  of WM_PAINT:
    var ps: PAINTSTRUCT
    discard BeginPaint(h, addr ps)
    v.paint()
    EndPaint(h, addr ps)
    return 0
  of WM_ERASEBKGND: return 1
  of 0x0087:          # WM_GETDLGCODE: Escape reaches the drawing in the select mode (the dialog manager keeps it otherwise)
    if v.selecting and l != 0:
      let msg = cast[ptr MSG](l)
      if msg.message == WM_KEYDOWN and int(msg.wParam) == 0x1B: return 0x0004     # DLGC_WANTMESSAGE
  of WM_SIZE:
    viewResize(v.v, cint(loword(l)), cint(hiword(l)))
    if not v.fitted: v.fit()
    v.invalidate()
    return 0
  of WM_LBUTTONDOWN:
    SetFocus(h)
    SetCapture(h)
    v.dragging = true
    v.dragMoved = false
    v.lastX = sloword(l)
    v.lastY = shiword(l)
    if v.marking or v.selecting:
      let px = v.ox + float(v.lastX) / v.z
      let py = v.oy + float(v.lastY) / v.z
      v.mark = (px, py, px, py)
      v.markOn = v.marking
    return 0
  of WM_MOUSEMOVE:
    if v.dragging:
      let x = sloword(l)
      let y = shiword(l)
      if abs(x - v.lastX) + abs(y - v.lastY) > 3: v.dragMoved = true
      if v.selecting and v.dragMoved: v.markOn = true     # a box, not a click
      if v.marking or v.selecting:
        let px = v.ox + float(x) / v.z
        let py = v.oy + float(y) / v.z
        let ax = v.ox + float(v.lastX) / v.z      # where the drag started
        let ay = v.oy + float(v.lastY) / v.z
        v.mark = (min(ax, px), min(ay, py), max(ax, px), max(ay, py))
      else:
        v.ox -= float(x - v.lastX) / v.z
        v.oy -= float(y - v.lastY) / v.z
        v.lastX = x
        v.lastY = y
      v.invalidate()
    return 0
  of WM_LBUTTONUP:
    ReleaseCapture()
    let was = v.dragging
    v.dragging = false
    if v.markOn and not (was and v.marking):    # whatever ended the drag, no box stays drawn
      v.markOn = false
      v.invalidate()
    if was and v.marking:
      v.markOn = false
      if v.onMark != nil and v.mark[2] > v.mark[0]: v.onMark(v.mark[0], v.mark[1], v.mark[2], v.mark[3])
      v.invalidate()
    elif was and v.selecting and v.dragMoved:
      v.markOn = false
      v.invalidate()
      if v.onBox != nil: v.onBox(v.mark[0], v.mark[1], v.mark[2], v.mark[3])
    elif was and v.selecting:
      v.markOn = false
      let id = v.hit(sloword(l), shiword(l))
      if id.len > 0 and v.onTag != nil: v.onTag(id)
    elif was and not v.dragMoved and (let li = v.hitLink(sloword(l), shiword(l)); li >= 0):
      if v.onLink != nil: v.onLink(li)          # a connector before the tags under it (as GNOME)
    elif was and not v.dragMoved:
      let id = v.hit(sloword(l), shiword(l))
      if id.len > 0:
        v.selected = id
        v.invalidate()
        if v.onTag != nil: v.onTag(id)
    return 0
  of WM_LBUTTONDBLCLK:
    v.zoomAt(2, float(sloword(l)), float(shiword(l)))
    return 0
  of WM_MOUSEWHEEL:
    var p = POINT(x: sloword(l), y: shiword(l))
    ScreenToClient(h, addr p)
    v.zoomAt(pow(1.25, float(shiword(int(w))) / 120), float(p.x), float(p.y))
    return 0
  of WM_KEYDOWN:
    case int(w)
    of 0x6B, 0xBB: v.zoomAt(1.25, v.client[0] / 2, v.client[1] / 2)      # + keys
    of 0x6D, 0xBD: v.zoomAt(0.8, v.client[0] / 2, v.client[1] / 2)       # - keys
    of 0x25: (v.ox -= 60 / v.z; v.invalidate())
    of 0x27: (v.ox += 60 / v.z; v.invalidate())
    of 0x26: (v.oy -= 60 / v.z; v.invalidate())
    of 0x28: (v.oy += 60 / v.z; v.invalidate())
    of 0x30: v.fit()
    of 0x1B:                          # Escape ends the select mode
      if v.selecting and v.onEscape != nil: v.onEscape()
    else: discard
    return 0
  else: discard
  DefWindowProcW(h, m, w, l)

var viewClassDone = false

proc newViewer*(parent: HWND, hinst: HINSTANCE): Viewer =
  if d2dInit() != 0: raise newException(OSError, "Direct2D could not start")
  if not viewClassDone:
    let clsName = newWideCString("KKSDrawing")   # must outlive RegisterClassExW
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), style: CS_DBLCLKS, lpfnWndProc: viewProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_ARROW), lpszClassName: clsName)
    discard RegisterClassExW(addr wc)
    viewClassDone = true
  result = Viewer(z: 1, linkSel: -1)
  result.hwnd = CreateWindowExW(0, newWideCString("KKSDrawing"), newWideCString("Drawing"),
                                WS_CHILD or WS_VISIBLE or WS_TABSTOP, 0, 0, 10, 10, parent, nil, hinst, nil)
  result.v = viewNew(result.hwnd)
  viewers[result.hwnd] = result
  result.uia = uiaNew(result.hwnd, cast[pointer](a11yCount), cast[pointer](a11yInfo), cast[pointer](a11yInvoke),
                      cast[pointer](result))      # the viewer lives as long as the window (kept in `viewers`)
