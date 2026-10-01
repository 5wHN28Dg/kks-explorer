## The grid-indexed path store (.kkp) version 1 (docs/PATHSTORE.md): decoder and encoder. The decoded form is flat
## (one command array, one coordinate array per sheet) so a viewer walks it without per-path allocations.
## Deflate through zlib's C API (decision 0029: system zlib on Linux, the NDK's on Android, linked on Windows).

import std/math

{.passL: "-lz".}

const
  Q* = 64
  Magic = "KKP1"
  Stroke* = 1'u8
  Fill* = 2'u8
  EvenOdd* = 4'u8
  Hairline* = 8'u8
  MaxBytes* = 256 * 1024 * 1024
  OpMove* = 0'u8
  OpLine* = 1'u8
  OpCubic* = 2'u8
  OpClose* = 3'u8
  NPts: array[4, int] = [1, 1, 3, 0]

type
  FormatError* = object of ValueError

  Style* = object
    kind*, cap*, join*: uint8
    width*: uint32
    stroke*, fill*: array[3, uint8]

  Path* = object
    style*: int
    bbox*: array[4, int64]      ## x0, y0, x1, y1
    cmdStart*, cmdCount*: int   ## into Drawing.ops
    ptStart*: int               ## into Drawing.xy (pairs)

  Image* = object
    after*: int
    rect*: array[4, int64]
    data*: string               ## JPEG XL bytes

  Drawing* = object
    width*, height*: uint32
    gx*, gy*: int
    styles*: seq[Style]
    paths*: seq[Path]
    ops*: seq[uint8]            ## all commands, path after path
    xy*: seq[int64]             ## all points as x, y, path after path
    cells*: seq[seq[int32]]     ## path indices per cell, row by row, ascending
    images*: seq[Image]

proc fail(msg: string) {.noreturn.} = raise newException(FormatError, msg)

# ---------------------------------------------------------------- zlib

type
  ZStream {.importc: "z_stream", header: "<zlib.h>".} = object
    next_in {.importc: "next_in".}: ptr uint8
    avail_in {.importc: "avail_in".}: cuint
    next_out {.importc: "next_out".}: ptr uint8
    avail_out {.importc: "avail_out".}: cuint
    total_out {.importc: "total_out".}: culong
    zalloc {.importc: "zalloc".}: pointer
    zfree {.importc: "zfree".}: pointer
    opaque {.importc: "opaque".}: pointer

var
  Z_OK {.importc, header: "<zlib.h>", nodecl.}: cint
  Z_STREAM_END {.importc, header: "<zlib.h>", nodecl.}: cint
  Z_NO_FLUSH {.importc, header: "<zlib.h>", nodecl.}: cint
  Z_BUF_ERROR {.importc, header: "<zlib.h>", nodecl.}: cint

proc inflateInit(s: ptr ZStream): cint {.importc, header: "<zlib.h>".}
proc inflate(s: ptr ZStream, flush: cint): cint {.importc, header: "<zlib.h>".}
proc inflateEnd(s: ptr ZStream): cint {.importc, header: "<zlib.h>".}
proc compressBound(n: culong): culong {.importc, header: "<zlib.h>".}
proc compress2(dst: ptr uint8, dstLen: ptr culong, src: ptr uint8, srcLen: culong, level: cint): cint
  {.importc, header: "<zlib.h>".}

proc inflateAll(src: string, start: int): string =
  ## One complete zlib stream filling src[start..^1] exactly, at most MaxBytes out.
  var s: ZStream
  if inflateInit(addr s) != Z_OK: fail("zlib init")
  defer: discard inflateEnd(addr s)
  let inLen = src.len - start
  s.next_in = if inLen > 0: cast[ptr uint8](unsafeAddr src[start]) else: nil
  s.avail_in = cuint(inLen)
  result = newString(min(max(4 * inLen, 4096), MaxBytes + 1))
  while true:
    let have = int(s.total_out)
    if have >= result.len:
      if result.len > MaxBytes: fail("zlib stream: too large")
      result.setLen(min(result.len * 2, MaxBytes + 1))
    s.next_out = cast[ptr uint8](addr result[have])
    s.avail_out = cuint(result.len - have)
    let r = inflate(addr s, Z_NO_FLUSH)
    if r == Z_STREAM_END: break
    if r == Z_BUF_ERROR and s.avail_in == 0: fail("zlib stream truncated")
    if r != Z_OK and r != Z_BUF_ERROR: fail("bad zlib stream")
  if int(s.total_out) > MaxBytes: fail("zlib stream: too large")
  if s.avail_in != 0: fail("zlib stream followed by other bytes")
  result.setLen(int(s.total_out))

proc deflateAll*(src: string, level = 9): string =
  var n = compressBound(culong(src.len))
  result = newString(int(n))
  let p = if src.len > 0: cast[ptr uint8](unsafeAddr src[0]) else: nil
  if compress2(cast[ptr uint8](addr result[0]), addr n, p, culong(src.len), cint(level)) != Z_OK: fail("zlib compress")
  result.setLen(int(n))

# ---------------------------------------------------------------- reading

type Reader = object
  b: string
  p: int

proc take(r: var Reader, n: int): int =
  if n < 0 or r.p + n > r.b.len: fail("truncated")
  result = r.p
  r.p += n

proc u8(r: var Reader): uint8 = uint8(r.b[r.take(1)])
proc u16(r: var Reader): int =
  let i = r.take(2)
  int(uint8(r.b[i])) or (int(uint8(r.b[i + 1])) shl 8)
proc u32(r: var Reader): uint32 =
  let i = r.take(4)
  for k in 0 .. 3: result = result or (uint32(uint8(r.b[i + k])) shl (8 * k))

proc uv(r: var Reader): int64 =
  var shift = 0
  for i in 0 ..< 5:
    let b = r.u8()
    result = result or (int64(b and 0x7F) shl shift)
    if (b and 0x80) == 0:
      if result >= (1'i64 shl 32): fail("varint too large")
      return
    shift += 7
  fail("varint longer than 5 bytes")

proc sv(r: var Reader): int64 =
  let z = r.uv()
  (z shr 1) xor -(z and 1)

proc decode*(data: string): Drawing =
  ## Raises FormatError on any violation of docs/PATHSTORE.md.
  if data.len > MaxBytes: fail("file too large")
  if data.len < 8 or data[0 .. 3] != Magic: fail("not a KKP1 file")
  let version = int(uint8(data[4])) or (int(uint8(data[5])) shl 8)
  let flags = int(uint8(data[6])) or (int(uint8(data[7])) shl 8)
  if version != 1 or (flags and not 1) != 0: fail("unsupported version or flags")
  var r = Reader(b: (if (flags and 1) != 0: inflateAll(data, 8) else: data[8 .. ^1]), p: 0)
  var d: Drawing
  d.width = r.u32()
  d.height = r.u32()
  d.gx = r.u16()
  d.gy = r.u16()
  if d.gx notin 1..1024 or d.gy notin 1..1024: fail("bad grid")
  let ns = r.uv()
  let np = r.uv()
  let ni = r.uv()
  if ns > r.b.len or np > r.b.len or ni > r.b.len: fail("truncated")   # each needs at least one byte
  for _ in 0 ..< ns:
    var s: Style
    s.kind = r.u8()
    s.cap = r.u8()
    s.join = r.u8()
    if (s.kind and not 15'u8) != 0 or (s.kind and (Stroke or Fill)) == 0 or s.cap > 2 or s.join > 2:
      fail("bad style")
    s.width = uint32(r.uv())
    for k in 0 .. 2: s.stroke[k] = r.u8()
    for k in 0 .. 2: s.fill[k] = r.u8()
    d.styles.add s
  d.paths = newSeqOfCap[Path](int(np))
  for _ in 0 ..< np:
    var p: Path
    let st = r.uv()
    if st >= ns: fail("style index")
    p.style = int(st)
    for k in 0 .. 3: p.bbox[k] = r.uv()
    if p.bbox[0] > p.bbox[2] or p.bbox[1] > p.bbox[3]: fail("bbox")
    let n = int(r.uv())
    if n < 1: fail("empty path")
    let packed = r.take((n + 3) div 4)
    p.cmdStart = d.ops.len
    p.cmdCount = n
    p.ptStart = d.xy.len div 2
    for i in 0 ..< n:
      d.ops.add (uint8(r.b[packed + i div 4]) shr (2 * (i mod 4))) and 3
    if n mod 4 != 0 and (uint8(r.b[packed + (n - 1) div 4]) shr (2 * (n mod 4))) != 0:
      fail("unused command bits set")
    if d.ops[p.cmdStart] != OpMove: fail("a path starts with a move")
    var px = p.bbox[0]
    var py = p.bbox[1]
    for i in 0 ..< n:
      for _ in 0 ..< NPts[d.ops[p.cmdStart + i]]:
        px += r.sv()
        py += r.sv()
        d.xy.add px
        d.xy.add py
    d.paths.add p
  d.cells = newSeq[seq[int32]](d.gx * d.gy)
  for c in 0 ..< d.gx * d.gy:
    let cnt = r.uv()
    if cnt > r.b.len: fail("truncated")
    var cell = newSeqOfCap[int32](int(cnt))
    var last = 0'i64
    for k in 0 ..< cnt:
      let v = r.uv()
      if k > 0 and v == 0: fail("grid indices must ascend")
      last = if k == 0: v else: last + v
      if last >= np: fail("grid index")
      cell.add int32(last)
    d.cells[c] = cell
  for _ in 0 ..< ni:
    var im: Image
    let after = r.uv()
    if after > np: fail("image position")
    im.after = int(after)
    for k in 0 .. 3: im.rect[k] = r.uv()
    let len = int(r.uv())
    let at = r.take(len)
    im.data = r.b[at ..< at + len]
    d.images.add im
  if r.p != r.b.len: fail("trailing bytes")
  d

# ---------------------------------------------------------------- grid rules

proc cellRange*(v0, v1, size: int64, n: int): Slice[int] =
  ## Cells (0..n-1) an interval [v0, v1] touches; cell i = [i*size div n, (i+1)*size div n).
  proc cell(v: int64): int =
    let x = if size > 0: min(max(v, 0), size - 1) else: 0
    var lo = 0
    var hi = n - 1
    while lo < hi:
      let mid = (lo + hi + 1) div 2
      if int64(mid) * size div int64(n) <= x: lo = mid
      else: hi = mid - 1
    lo
  cell(v0) .. cell(v1)

proc roundHalfEven(x: float): int =
  let f = floor(x)
  let d = x - f
  if d > 0.5: int(f) + 1
  elif d < 0.5: int(f)
  elif int(f) mod 2 == 0: int(f)
  else: int(f) + 1

proc chooseGrid*(width, height: int64, cellPt = 100): (int, int) =
  ## Cells of about 100 pt, 8..64 on the longer side (the reference rounds half to even, as Python's round).
  let long = max(width, height)
  let g = max(8, min(64, int(ceil(float(long) / float(cellPt * Q)))))
  (max(1, roundHalfEven(float(g) * float(width) / float(long))),
   max(1, roundHalfEven(float(g) * float(height) / float(long))))

proc visible*(d: Drawing, x0, y0, x1, y1: int64): seq[int32] =
  ## Paths whose cells touch [x0, x1] × [y0, y1], in paint order, each once (docs/PATHSTORE.md "Drawing a view").
  var seen = newSeq[bool](d.paths.len)
  for cy in cellRange(y0, y1, int64(d.height), d.gy):
    for cx in cellRange(x0, x1, int64(d.width), d.gx):
      for i in d.cells[cy * d.gx + cx]:
        if not seen[i]:
          seen[i] = true
  for i in 0 ..< d.paths.len:
    if seen[i]:
      let b = d.paths[i].bbox
      if b[2] >= x0 and b[0] <= x1 and b[3] >= y0 and b[1] <= y1: result.add int32(i)

# ---------------------------------------------------------------- writing

proc putUv(o: var string, n: int64) =
  if n < 0 or n >= (1'i64 shl 32): fail("varint out of range: " & $n)
  var v = n
  while true:
    let b = uint8(v and 0x7F)
    v = v shr 7
    if v != 0: o.add char(b or 0x80)
    else:
      o.add char(b)
      return

proc putSv(o: var string, n: int64) =
  if n < -(1'i64 shl 31) or n >= (1'i64 shl 31): fail("svarint out of range: " & $n)
  o.putUv(((n shl 1) xor (n shr 31)) and 0xFFFFFFFF'i64)

proc putU(o: var string, v: uint64, bytes: int) =
  for k in 0 ..< bytes: o.add char((v shr (8 * k)) and 0xFF)

proc buildGrid*(d: Drawing, gx, gy: int): seq[seq[int32]] =
  result = newSeq[seq[int32]](gx * gy)
  for i, p in d.paths:
    for cy in cellRange(p.bbox[1], p.bbox[3], int64(d.height), gy):
      for cx in cellRange(p.bbox[0], p.bbox[2], int64(d.width), gx):
        result[cy * gx + cx].add int32(i)

proc encode*(d: Drawing, gx = 0, gy = 0, compress = true): string =
  ## Canonical encoding of d's width, height, styles, paths and images; the grid is built here
  ## (chooseGrid unless gx, gy are given).
  var (x, y) = (gx, gy)
  if x == 0: (x, y) = chooseGrid(int64(d.width), int64(d.height))
  var o = ""
  o.putU(d.width, 4)
  o.putU(d.height, 4)
  o.putU(uint64(x), 2)
  o.putU(uint64(y), 2)
  o.putUv(d.styles.len)
  o.putUv(d.paths.len)
  o.putUv(d.images.len)
  for s in d.styles:
    if (s.kind and not 15'u8) != 0 or (s.kind and (Stroke or Fill)) == 0 or s.cap > 2 or s.join > 2: fail("bad style")
    o.add char(s.kind)
    o.add char(s.cap)
    o.add char(s.join)
    o.putUv(int64(s.width))
    for k in 0 .. 2: o.add char(s.stroke[k])
    for k in 0 .. 2: o.add char(s.fill[k])
  for p in d.paths:
    o.putUv(p.style)
    for v in p.bbox: o.putUv(v)
    if p.cmdCount < 1 or d.ops[p.cmdStart] != OpMove: fail("a path starts with a move")
    o.putUv(p.cmdCount)
    var packed = newString((p.cmdCount + 3) div 4)
    for i in 0 ..< p.cmdCount:
      packed[i div 4] = char(uint8(packed[i div 4]) or (d.ops[p.cmdStart + i] shl (2 * (i mod 4))))
    o.add packed
    var px = p.bbox[0]
    var py = p.bbox[1]
    var q = p.ptStart
    for i in 0 ..< p.cmdCount:
      for _ in 0 ..< NPts[d.ops[p.cmdStart + i]]:
        o.putSv(d.xy[2 * q] - px)
        o.putSv(d.xy[2 * q + 1] - py)
        px = d.xy[2 * q]
        py = d.xy[2 * q + 1]
        inc q
  for cell in d.buildGrid(x, y):
    o.putUv(cell.len)
    var prev = -1
    for i in cell:
      o.putUv(if prev < 0: int64(i) else: int64(i - prev))
      prev = i
  for im in d.images:
    o.putUv(im.after)
    for v in im.rect: o.putUv(v)
    o.putUv(im.data.len)
    o.add im.data
  result = Magic
  result.putU(1, 2)
  result.putU(if compress: 1 else: 0, 2)
  result.add(if compress: deflateAll(o) else: o)
