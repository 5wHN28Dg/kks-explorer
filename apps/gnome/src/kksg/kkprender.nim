## Drawing a region of a .kkp path store with Cairo (docs/PATHSTORE.md "Drawing a view", decision 0016): tiles are
## rendered on the CPU into image surfaces, on the viewer's worker threads; the viewer hands them to GSK as textures.
## Thread safety: the drawing is read only once decoded; the embedded images are decoded on first use under a lock,
## once per mode (light, dark), and handed out with a reference of their own. Workers take a `ptr SheetObj` (no
## reference counting off the main thread); the viewer keeps the Sheet alive while a tile of it is being drawn.

import std/[math, algorithm, locks]
import kks/pathstore
import kksi/jxl
import gtk, darkcolor

type
  SheetObj* = object
    d*: Drawing
    images: array[bool, seq[Surface]]    ## per mode (dark = true), index = image index; nil = not yet / failed
    decoded: array[bool, seq[bool]]
    lock: Lock                           ## guards images and decoded
    dark*: bool                          ## the mode renderTile draws in; set through setDark
  Sheet* = ref SheetObj

proc newSheet*(data: string): Sheet =
  result = Sheet(d: decode(data))
  initLock(result.lock)
  for m in [false, true]:
    result.images[m] = newSeq[Surface](result.d.images.len)
    result.decoded[m] = newSeq[bool](result.d.images.len)

proc setDark*(s: Sheet, on: bool) =
  ## switch dark drawings; the embedded images are decoded again in the new mode (those of the old mode are freed;
  ## a tile being drawn holds its own reference to the one it uses)
  if s.dark == on: return
  s.dark = on
  withLock s.lock:
    let old = not on
    for i in 0 ..< s.images[old].len:
      if s.images[old][i] != nil: cairo_surface_destroy(s.images[old][i])
      s.images[old][i] = nil
      s.decoded[old][i] = false

proc widthPt*(s: Sheet): float = float(s.d.width) / float(Q)
proc heightPt*(s: Sheet): float = float(s.d.height) / float(Q)

proc cairo_surface_reference(s: Surface): Surface {.importc, header: "<cairo.h>", discardable.}

proc imageSurface(s: ptr SheetObj, dark: bool, i: int): Surface =
  ## image i in this mode, with a reference for the caller (nil if it can't be decoded); any thread
  withLock s.lock:
    if s.decoded[dark][i]:
      return (if s.images[dark][i] == nil: nil else: cairo_surface_reference(s.images[dark][i]))
  var sf: Surface = nil
  try:
    var (w, h, _, px) = decodeRgba(s.d.images[i].data)
    if dark: darkenPixels(px, 4)
    sf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, cint(w), cint(h))
    let dst = cairo_image_surface_get_data(sf)
    let stride = int(cairo_image_surface_get_stride(sf))
    for y in 0 ..< h:
      for x in 0 ..< w:
        let o = (y * w + x) * 4
        let a = int(px[o + 3])
        # ARGB32: premultiplied, native-endian 32-bit words (B, G, R, A in memory on little-endian)
        let p = y * stride + x * 4
        dst[p + 0] = byte(int(px[o + 2]) * a div 255)
        dst[p + 1] = byte(int(px[o + 1]) * a div 255)
        dst[p + 2] = byte(int(px[o + 0]) * a div 255)
        dst[p + 3] = byte(a)
    cairo_surface_mark_dirty(sf)
  except CatchableError:
    if sf != nil: cairo_surface_destroy(sf)
    sf = nil
  withLock s.lock:
    if s.decoded[dark][i]:                 # another thread decoded it meanwhile: keep theirs
      if sf != nil: cairo_surface_destroy(sf)
    else:
      s.decoded[dark][i] = true
      s.images[dark][i] = sf
    result = if s.images[dark][i] == nil: nil else: cairo_surface_reference(s.images[dark][i])

proc setColor(dark: bool, c: Cairo, rgb: openArray[uint8]) {.inline.} =
  if dark:
    let (r, g, b) = darkRgb(int(rgb[0]), int(rgb[1]), int(rgb[2]))
    cairo_set_source_rgb(c, float(r) / 255, float(g) / 255, float(b) / 255)
  else:
    cairo_set_source_rgb(c, float(rgb[0]) / 255, float(rgb[1]) / 255, float(rgb[2]) / 255)

proc drawPath(s: ptr SheetObj, dark: bool, c: Cairo, i: int, px1: float) =
  ## px1 = one device pixel in quanta
  template p: untyped = s.d.paths[i]
  template st: untyped = s.d.styles[p.style]
  cairo_new_path(c)
  var k = p.ptStart * 2
  var mx, my = 0.0
  for j in 0 ..< p.cmdCount:
    case s.d.ops[p.cmdStart + j]
    of OpMove:
      mx = float(s.d.xy[k]); my = float(s.d.xy[k + 1])
      cairo_move_to(c, mx, my)
      k += 2
    of OpLine:
      cairo_line_to(c, float(s.d.xy[k]), float(s.d.xy[k + 1]))
      k += 2
    of OpCubic:
      cairo_curve_to(c, float(s.d.xy[k]), float(s.d.xy[k + 1]), float(s.d.xy[k + 2]), float(s.d.xy[k + 3]),
                     float(s.d.xy[k + 4]), float(s.d.xy[k + 5]))
      k += 6
    else:
      cairo_close_path(c)
      cairo_move_to(c, mx, my)      # a line after close continues from the move point (PDF)
  let fill = (st.kind and Fill) != 0
  let stroke = (st.kind and Stroke) != 0
  if fill:
    cairo_set_fill_rule(c, if (st.kind and EvenOdd) != 0: CAIRO_FILL_RULE_EVEN_ODD else: CAIRO_FILL_RULE_WINDING)
    setColor(dark, c, st.fill)
    if stroke: cairo_fill_preserve(c) else: cairo_fill(c)
  if stroke:
    let w = if (st.kind and Hairline) != 0: px1 else: max(float(st.width), px1)
    cairo_set_line_width(c, w)
    cairo_set_line_cap(c, cint(st.cap))
    cairo_set_line_join(c, cint(st.join))
    cairo_set_miter_limit(c, 10)
    setColor(dark, c, st.stroke)
    cairo_stroke(c)

proc drawImage(s: ptr SheetObj, dark: bool, c: Cairo, i: int) =
  template im: untyped = s.d.images[i]
  let sf = s.imageSurface(dark, i)
  if sf == nil: return
  let iw = float(cairo_image_surface_get_width(sf))
  let ih = float(cairo_image_surface_get_height(sf))
  cairo_save(c)
  cairo_translate(c, float(im.rect[0]), float(im.rect[1]))
  cairo_scale(c, float(im.rect[2] - im.rect[0]) / iw, float(im.rect[3] - im.rect[1]) / ih)
  cairo_set_source_surface(c, sf, 0, 0)
  cairo_paint(c)
  cairo_restore(c)
  cairo_surface_destroy(sf)

proc renderTile*(s: ptr SheetObj, dark: bool, zoom: float, x0, y0: float, w, h: int): Surface =
  ## The region whose top-left is (x0, y0) in points, w × h device pixels at `zoom` px per point, on white (on the
  ## dark background in dark mode). Any thread.
  result = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, cint(w), cint(h))
  let c = cairo_create(result)
  if dark: cairo_set_source_rgb(c, DarkLo / 255, DarkLo / 255, DarkLo / 255)
  else: cairo_set_source_rgb(c, 1, 1, 1)
  cairo_paint(c)
  let k = zoom / float(Q)                    # device px per quantum
  cairo_scale(c, k, k)
  cairo_translate(c, -x0 * float(Q), -y0 * float(Q))
  let qx0 = int64(floor(x0 * float(Q)))
  let qy0 = int64(floor(y0 * float(Q)))
  let qx1 = int64(ceil((x0 + float(w) / zoom) * float(Q)))
  let qy1 = int64(ceil((y0 + float(h) / zoom) * float(Q)))
  # the thinnest line: one device pixel (PATHSTORE.md), half of one when zoomed out below a pixel per point, where
  # full-pixel lines made dense text a dark block at fit (2026-10-07)
  let px1 = (if zoom < 1.0: 0.5 else: 1.0) / k
  var imgs: seq[int]
  for i in 0 ..< s.d.images.len:
    template im: untyped = s.d.images[i]
    if im.rect[2] >= qx0 and im.rect[0] <= qx1 and im.rect[3] >= qy0 and im.rect[1] <= qy1: imgs.add i
  imgs.sort(proc (a, b: int): int = cmp(s.d.images[a].after, s.d.images[b].after))
  var ii = 0
  for pi in s.d.visible(qx0, qy0, qx1, qy1):
    let i = int(pi)
    while ii < imgs.len and s.d.images[imgs[ii]].after <= i:
      s.drawImage(dark, c, imgs[ii])
      inc ii
    let b = s.d.paths[i].bbox
    if b[2] < qx0 or b[0] > qx1 or b[3] < qy0 or b[1] > qy1: continue
    s.drawPath(dark, c, i, px1)
  while ii < imgs.len:
    s.drawImage(dark, c, imgs[ii])
    inc ii
  cairo_destroy(c)
  cairo_surface_flush(result)

proc renderTile*(s: Sheet, zoom: float, x0, y0: float, w, h: int): Surface =
  ## the same in the sheet's mode, on the main thread
  renderTile(addr s[], s.dark, zoom, x0, y0, w, h)

proc g_bytes_new_with_free_func(data: pointer, size: csize_t, free: pointer, user: pointer): W {.importc, header: "<glib.h>".}
proc freeSurface(p: pointer) {.cdecl.} = cairo_surface_destroy(cast[Surface](p))

proc textureTaking*(sf: Surface): W =
  ## a GdkMemoryTexture over the surface's pixels (Cairo ARGB32 = premultiplied BGRA in memory), without a copy: the
  ## texture takes the surface and frees it with its last reference
  cairo_surface_flush(sf)
  let w = cairo_image_surface_get_width(sf)
  let h = cairo_image_surface_get_height(sf)
  let stride = cairo_image_surface_get_stride(sf)
  let b = g_bytes_new_with_free_func(cairo_image_surface_get_data(sf), csize_t(stride * h), cast[pointer](freeSurface), sf)
  result = gdk_memory_texture_new(w, h, GDK_MEMORY_B8G8R8A8_PREMULTIPLIED, b, csize_t(stride))
  g_bytes_unref(b)
