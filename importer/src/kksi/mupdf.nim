## Nim side of kks_mupdf.c (decision 0026): MuPDF 1.28.2, exactly as PyMuPDF used it.

{.compile: "kks_mupdf.c".}

type
  Doc* = distinct pointer
  Item* {.bycopy.} = object
    cmd*: char
    p*: array[8, cfloat]
    orientation*: cint
  RawPath {.bycopy.} = object
    typ: array[3, char]
    hasFill: cint
    seqno: csize_t
    rect: array[4, cfloat]
    nItems: cint
    items: ptr UncheckedArray[Item]
    closePath: cint
    evenOdd: cint
    hasFillColor: cint
    fill: array[3, cfloat]
    fillOpacity: cfloat
    hasStroke: cint
    hasColor: cint
    color: array[3, cfloat]
    strokeOpacity: cfloat
    width: cfloat
    cap: array[3, cint]
    join: cint
    dashLen: cint
  Path* = object
    kind*: string            ## "f", "s", "fs"
    hasFill*: bool
    seqno*: int
    rect*: array[4, float32]
    items*: seq[Item]
    closePath*: int          ## -1 = not set, 0, 1 (PyMuPDF: None, False, True)
    evenOdd*: bool
    fill*: seq[float32]      ## RGB, empty when the colour space is missing
    hasStroke*: bool         ## the keys below are set (stroke or merged fill+stroke)
    color*: seq[float32]
    width*: float32
    cap*: array[3, int]
    join*: int
    dashLen*: int
  Pixmap* = object
    w*, h*, x*, y*: int
    data*: seq[byte]
  MupdfError* = object of CatchableError

proc kks_init(): cint {.importc, cdecl.}
proc kks_error(): cstring {.importc, cdecl.}
proc kks_open(path: cstring): Doc {.importc, cdecl.}
proc kks_close(d: Doc) {.importc, cdecl.}
proc kks_rotated_copy(src: cstring, extra: cint): Doc {.importc, cdecl.}
proc kks_page_size(d: Doc, w, h: ptr cfloat): cint {.importc, cdecl.}
proc kks_render_gray(d: Doc, zoom: cdouble, hasClip: cint, x0, y0, x1, y1: cdouble, minLw: cfloat,
                     w, h, x, y: ptr cint): ptr UncheckedArray[byte] {.importc, cdecl.}
proc kks_render(d: Doc, zoom: cdouble, hasClip: cint, x0, y0, x1, y1: cdouble, minLw: cfloat, ncomp: cint,
                w, h, x, y: ptr cint): ptr UncheckedArray[byte] {.importc, cdecl.}
proc kks_free(p: pointer) {.importc, cdecl.}
proc kks_drawings(d: Doc, out0: ptr ptr UncheckedArray[RawPath], unrotate: cint): cint {.importc, cdecl.}
type
  RawImage {.bycopy.} = object
    logidx: csize_t
    ctm: array[6, cfloat]
    w, h, n: cint
    pixels: ptr UncheckedArray[byte]
  PageImage* = object
    logidx*: int              ## index of the draw call in PyMuPDF's get_bboxlog()
    ctm*: array[6, float32]
    w*, h*, n*: int           ## n = 3 (RGB) or 4 (RGBA, straight alpha)
    pixels*: seq[byte]
proc kks_drawings_images(d: Doc, out0: ptr ptr UncheckedArray[RawPath], unrotate: cint,
                         imgs: ptr ptr UncheckedArray[RawImage], nimg: ptr cint): cint {.importc, cdecl.}
proc kks_free_images(p: ptr UncheckedArray[RawImage], n: cint) {.importc, cdecl.}
proc kks_display_geom(d: Doc, extra: cint, m, r: ptr cdouble): cint {.importc, cdecl.}
proc kks_page_rotation(d: Doc): cint {.importc, cdecl.}
proc kks_free_paths(p: ptr UncheckedArray[RawPath], n: cint) {.importc, cdecl.}

proc fail() = raise newException(MupdfError, $kks_error())

proc init*() =
  if kks_init() == 0: raise newException(MupdfError, "MuPDF context")

proc isNil*(d: Doc): bool = pointer(d) == nil

proc open*(path: string): Doc =
  result = kks_open(path)
  if result.isNil: fail()

proc close*(d: Doc) = kks_close(d)

proc rotatedCopy*(src: string, extra: int): Doc =
  ## extractor/orient.py rotated_copy(src, dst, extra), kept in memory.
  result = kks_rotated_copy(src, cint(extra))
  if result.isNil: fail()

proc pageSize*(d: Doc): (float32, float32) =
  var w, h: cfloat
  if kks_page_size(d, addr w, addr h) == 0: fail()
  (float32(w), float32(h))

proc renderGray*(d: Doc, zoom: float, clip: (float, float, float, float) = (0.0, 0.0, 0.0, 0.0), hasClip = false,
                 minLineWidth = 0.0): Pixmap =
  ## page.get_pixmap(matrix/dpi, clip, colorspace=csGRAY) with TOOLS.set_graphics_min_line_width(minLineWidth).
  var w, h, x, y: cint
  let p = kks_render_gray(d, zoom, cint(hasClip), clip[0], clip[1], clip[2], clip[3], cfloat(minLineWidth),
                          addr w, addr h, addr x, addr y)
  if p == nil: fail()
  result = Pixmap(w: int(w), h: int(h), x: int(x), y: int(y), data: newSeq[byte](int(w) * int(h)))
  if result.data.len > 0: copyMem(addr result.data[0], p, result.data.len)
  kks_free(p)

proc convert(raw: ptr UncheckedArray[RawPath], n: cint): seq[Path]

proc drawings*(d: Doc, unrotate = false): seq[Path] =
  ## Page.get_drawings() (unrotate: in the unrotated page, as PyMuPDF does for a page with /Rotate).
  var raw: ptr UncheckedArray[RawPath]
  let n = kks_drawings(d, addr raw, cint(unrotate))
  if n < 0: fail()
  result = convert(raw, n)
  kks_free_paths(raw, n)

proc drawingsAndImages*(d: Doc): (seq[Path], seq[PageImage]) =
  ## The unrotated page's paths and its images as MuPDF draws them (decoded, masks as alpha, sRGB).
  var raw: ptr UncheckedArray[RawPath]
  var imgs: ptr UncheckedArray[RawImage]
  var ni: cint
  let n = kks_drawings_images(d, addr raw, 1, addr imgs, addr ni)
  if n < 0: fail()
  result[0] = convert(raw, n)
  kks_free_paths(raw, n)
  for i in 0 ..< int(ni):
    let r = imgs[i]
    var im = PageImage(logidx: int(r.logidx), w: int(r.w), h: int(r.h), n: int(r.n))
    for k in 0 .. 5: im.ctm[k] = float32(r.ctm[k])
    im.pixels = newSeq[byte](im.w * im.h * im.n)
    if im.pixels.len > 0: copyMem(addr im.pixels[0], r.pixels, im.pixels.len)
    result[1].add im
  kks_free_images(imgs, ni)

proc convert(raw: ptr UncheckedArray[RawPath], n: cint): seq[Path] =
  for i in 0 ..< int(n):
    let r = raw[i]
    var p = Path(hasFill: r.hasFill != 0, seqno: int(r.seqno))
    for c in r.typ:
      if c == '\0': break
      p.kind.add c
    for k in 0 .. 3: p.rect[k] = float32(r.rect[k])
    for k in 0 ..< int(r.nItems): p.items.add r.items[k]
    p.closePath = int(r.closePath)
    p.evenOdd = r.evenOdd != 0
    if r.hasFillColor != 0: p.fill = @[float32(r.fill[0]), float32(r.fill[1]), float32(r.fill[2])]
    p.hasStroke = r.hasStroke != 0
    if r.hasColor != 0: p.color = @[float32(r.color[0]), float32(r.color[1]), float32(r.color[2])]
    p.width = float32(r.width)
    for k in 0 .. 2: p.cap[k] = int(r.cap[k])
    p.join = int(r.join)
    p.dashLen = int(r.dashLen)
    result.add p

proc displayGeom*(d: Doc, extra: int): (array[6, float], array[4, float]) =
  ## (page.rotation_matrix * Matrix(extra) * shift, page.rect * Matrix(extra)), as ref/pathstore.from_pdf_page.
  var m: array[6, cdouble]
  var r: array[4, cdouble]
  if kks_display_geom(d, cint(extra), addr m[0], addr r[0]) == 0: fail()
  for i in 0 .. 5: result[0][i] = float(m[i])
  for i in 0 .. 3: result[1][i] = float(r[i])

proc pageRotation*(d: Doc): int =
  ## the first page's own /Rotate (0, 90, 180 or 270)
  result = int(kks_page_rotation(d))
  if result < 0: fail()

proc renderRgb*(d: Doc, zoom: float): Pixmap =
  ## The whole page as RGB at `zoom` (Page.get_pixmap(matrix=Matrix(zoom, zoom))); data = w*h*3 bytes.
  var w, h, x, y: cint
  let p = kks_render(d, zoom, 0, 0, 0, 0, 0, 0, 3, addr w, addr h, addr x, addr y)
  if p == nil: fail()
  result = Pixmap(w: int(w), h: int(h), x: int(x), y: int(y), data: newSeq[byte](int(w) * int(h) * 3))
  if result.data.len > 0: copyMem(addr result.data[0], p, result.data.len)
  kks_free(p)

proc kks_annot_notes(d: Doc, len: ptr csize_t): ptr UncheckedArray[char] {.importc, cdecl.}

proc annotNotes*(d: Doc): seq[string] =
  ## /Contents of page 0's annotations (not links, popups, widgets), in page order.
  var n: csize_t
  let p = kks_annot_notes(d, addr n)
  if p == nil: fail()
  var cur = ""
  for i in 0 ..< int(n):
    if p[i] == '\0':
      result.add cur
      cur = ""
    else: cur.add p[i]
  kks_free(p)
