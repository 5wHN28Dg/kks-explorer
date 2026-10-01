## Drawing a region of a .kkp path store with Cairo (docs/PATHSTORE.md "Drawing a view", decision 0016): tiles are
## rendered on the CPU into image surfaces; the viewer hands them to GSK as textures.

import std/[math, algorithm]
import kks/pathstore
import kksi/jxl
import gtk

type
  Sheet* = ref object
    d*: Drawing
    images: seq[Surface]          ## decoded on first use, index = image index (nil = not yet / failed)
    decoded: seq[bool]

proc newSheet*(data: string): Sheet =
  result = Sheet(d: decode(data))
  result.images = newSeq[Surface](result.d.images.len)
  result.decoded = newSeq[bool](result.d.images.len)

proc widthPt*(s: Sheet): float = float(s.d.width) / float(Q)
proc heightPt*(s: Sheet): float = float(s.d.height) / float(Q)

proc imageSurface(s: Sheet, i: int): Surface =
  if not s.decoded[i]:
    s.decoded[i] = true
    try:
      let (w, h, _, px) = decodeRgba(s.d.images[i].data)
      let sf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, cint(w), cint(h))
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
      s.images[i] = sf
    except CatchableError:
      s.images[i] = nil
  s.images[i]

proc drawPath(s: Sheet, c: Cairo, i: int, px1: float) =
  ## px1 = one device pixel in quanta
  let p = s.d.paths[i]
  let st = s.d.styles[p.style]
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
    cairo_set_source_rgb(c, float(st.fill[0]) / 255, float(st.fill[1]) / 255, float(st.fill[2]) / 255)
    if stroke: cairo_fill_preserve(c) else: cairo_fill(c)
  if stroke:
    let w = if (st.kind and Hairline) != 0: px1 else: max(float(st.width), px1)
    cairo_set_line_width(c, w)
    cairo_set_line_cap(c, cint(st.cap))
    cairo_set_line_join(c, cint(st.join))
    cairo_set_miter_limit(c, 10)
    cairo_set_source_rgb(c, float(st.stroke[0]) / 255, float(st.stroke[1]) / 255, float(st.stroke[2]) / 255)
    cairo_stroke(c)

proc drawImage(s: Sheet, c: Cairo, i: int) =
  let im = s.d.images[i]
  let sf = s.imageSurface(i)
  if sf == nil: return
  let iw = float(cairo_image_surface_get_width(sf))
  let ih = float(cairo_image_surface_get_height(sf))
  cairo_save(c)
  cairo_translate(c, float(im.rect[0]), float(im.rect[1]))
  cairo_scale(c, float(im.rect[2] - im.rect[0]) / iw, float(im.rect[3] - im.rect[1]) / ih)
  cairo_set_source_surface(c, sf, 0, 0)
  cairo_paint(c)
  cairo_restore(c)

proc renderTile*(s: Sheet, zoom: float, x0, y0: float, w, h: int): Surface =
  ## The region whose top-left is (x0, y0) in points, w × h device pixels at `zoom` px per point, on white.
  result = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, cint(w), cint(h))
  let c = cairo_create(result)
  cairo_set_source_rgb(c, 1, 1, 1)
  cairo_paint(c)
  let k = zoom / float(Q)                    # device px per quantum
  cairo_scale(c, k, k)
  cairo_translate(c, -x0 * float(Q), -y0 * float(Q))
  let qx0 = int64(floor(x0 * float(Q)))
  let qy0 = int64(floor(y0 * float(Q)))
  let qx1 = int64(ceil((x0 + float(w) / zoom) * float(Q)))
  let qy1 = int64(ceil((y0 + float(h) / zoom) * float(Q)))
  let px1 = 1.0 / k
  var imgs: seq[int]
  for i, im in s.d.images:
    if im.rect[2] >= qx0 and im.rect[0] <= qx1 and im.rect[3] >= qy0 and im.rect[1] <= qy1: imgs.add i
  imgs.sort(proc (a, b: int): int = cmp(s.d.images[a].after, s.d.images[b].after))
  var ii = 0
  for pi in s.d.visible(qx0, qy0, qx1, qy1):
    let i = int(pi)
    while ii < imgs.len and s.d.images[imgs[ii]].after <= i:
      s.drawImage(c, imgs[ii])
      inc ii
    let b = s.d.paths[i].bbox
    if b[2] < qx0 or b[0] > qx1 or b[3] < qy0 or b[1] > qy1: continue
    s.drawPath(c, i, px1)
  while ii < imgs.len:
    s.drawImage(c, imgs[ii])
    inc ii
  cairo_destroy(c)
  cairo_surface_flush(result)

proc textureOf*(sf: Surface): W =
  ## a GdkMemoryTexture with a copy of the surface's pixels (Cairo ARGB32 = premultiplied BGRA in memory)
  let w = cairo_image_surface_get_width(sf)
  let h = cairo_image_surface_get_height(sf)
  let stride = cairo_image_surface_get_stride(sf)
  let b = g_bytes_new(cairo_image_surface_get_data(sf), csize_t(stride * h))
  result = gdk_memory_texture_new(w, h, GDK_MEMORY_B8G8R8A8_PREMULTIPLIED, b, csize_t(stride))
  g_bytes_unref(b)
