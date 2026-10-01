## The glyph reader of extractor/fontlib.py + segment.norm + feats (decision 0026): the glyph library (docs/GLYPHLIB.md),
## character splitting, glyph normalisation, kNN classification with the family rules, and the KKS grammar.
## Arithmetic follows the Python code's types: doubles where Python computes, float32 where numpy/cv2 do.

import std/[algorithm, math, strutils]
import kks/gz
import imgops

{.compile: "kks_dot.c".}
proc kks_gemv(rows: ptr float32, nrows: csize_t, x: ptr float32, n: csize_t, outp: ptr float32) {.importc, cdecl.}
proc kks_sdot(v: ptr float32, n: csize_t): float32 {.importc, cdecl.}
proc sqrtf(x: cfloat): cfloat {.importc, header: "<math.h>".}

const
  GW* = 20
  GH* = 32
  Dim* = GW * GH

type
  GlyphLib* = object
    n*: int
    x*: seq[float32]       ## n × Dim, row-major
    y*: seq[string]
  GlyphLibError* = object of CatchableError

proc loadGlyphLib*(path: string): GlyphLib =
  let data = gunzip(readFile(path), 64 shl 20)
  if data.len < 20 or data[0 ..< 8] != "KKSGLYPH":
    raise newException(GlyphLibError, path & ": not a glyph library")
  proc u32(p: int): int = int(uint32(data[p].uint8) or (uint32(data[p+1].uint8) shl 8) or
                              (uint32(data[p+2].uint8) shl 16) or (uint32(data[p+3].uint8) shl 24))
  proc u16(p: int): int = int(data[p].uint8) or (int(data[p+1].uint8) shl 8)
  if u32(8) != 1: raise newException(GlyphLibError, path & ": unknown version")
  result.n = u32(12)
  if u16(16) != GW or u16(18) != GH: raise newException(GlyphLibError, path & ": unexpected glyph size")
  var p = 20
  let nb = result.n * Dim * 4
  if data.len < p + nb: raise newException(GlyphLibError, path & ": truncated")
  result.x = newSeq[float32](result.n * Dim)
  copyMem(addr result.x[0], unsafeAddr data[p], nb)    # little-endian hosts only (x86-64, arm64)
  p += nb
  for i in 0 ..< result.n:
    if p >= data.len: raise newException(GlyphLibError, path & ": truncated labels")
    let l = int(data[p].uint8)
    result.y.add data[p + 1 .. p + l]
    p += 1 + l
  if p != data.len: raise newException(GlyphLibError, path & ": trailing bytes")

# ---- a binary image: rows of bools ----

type Bits* = object
  w*, h*: int
  d*: seq[bool]

proc sub*(b: Bits, x0, y0, x1, y1: int): Bits =
  ## b[y0:y1, x0:x1]
  result = Bits(w: x1 - x0, h: y1 - y0)
  result.d = newSeq[bool](result.w * result.h)
  for y in 0 ..< result.h:
    for x in 0 ..< result.w:
      result.d[y * result.w + x] = b.d[(y + y0) * b.w + x + x0]

proc count*(b: Bits): int =
  for v in b.d:
    if v: inc result

proc pyRound*(x: float): float =
  ## Python round(x) for the cases used here (ties to even).
  let f = floor(x)
  let d = x - f
  if d > 0.5: f + 1 elif d < 0.5: f elif f mod 2 == 0: f else: f + 1

proc median(xs: seq[int]): float =
  var s = xs
  s.sort()
  let n = s.len
  if n mod 2 == 1: float(s[n div 2]) else: (float(s[n div 2 - 1]) + float(s[n div 2])) / 2

# ---- split_chars (fontlib.py) ----

type Piece* = object
  a*, b*: int
  sub*: Bits

proc splitChars*(bw: Bits): (seq[Piece], int, int) =
  ## Returns (pieces, y0, y1); no pieces → y0 = -1.
  var y0 = -1
  var y1 = -1
  for y in 0 ..< bw.h:
    for x in 0 ..< bw.w:
      if bw.d[y * bw.w + x]:
        if y0 < 0: y0 = y
        y1 = y
        break
  if y0 < 0: return (@[], -1, -1)
  let hc = y1 - y0 + 1
  var col = newSeq[int](bw.w)
  for y in y0 .. y1:
    for x in 0 ..< bw.w:
      if bw.d[y * bw.w + x]: inc col[x]
  var runs: seq[(int, int)]
  var inrun = false
  var s = 0
  for x in 0 .. bw.w:
    let v = if x < bw.w: col[x] else: 0
    if v > 0 and not inrun:
      s = x
      inrun = true
    elif v == 0 and inrun:
      var ink = 0
      for xx in s ..< x: ink += col[xx]
      if ink >= 15: runs.add((s, x))
      inrun = false
  if runs.len == 0: return (@[], -1, -1)
  var widths: seq[int]
  for (a, b) in runs: widths.add b - a
  let typical = max(median(widths), 0.42 * float(hc))
  var outp: seq[Piece]
  for (a, b) in runs:
    let w = b - a
    let n = int(pyRound(float(w) / typical))
    if float(w) > 1.45 * typical and n >= 2:
      var cuts = @[a]
      for k in 1 ..< n:
        let c = a + int(float(k * w) / float(n))
        let lo = max(a + 2, c - int(0.25 * typical))
        let hi = min(b - 2, c + int(0.25 * typical))
        if hi > lo:
          var best = lo
          for xx in lo ..< hi:
            if col[xx] < col[best]: best = xx
          cuts.add best
        else:
          cuts.add c
      cuts.add b
      for i in 0 ..< cuts.len - 1:
        let p = cuts[i]
        let q = cuts[i + 1]
        if q - p > 2: outp.add Piece(a: p, b: q, sub: bw.sub(p, y0, q, y1 + 1))
    else:
      outp.add Piece(a: a, b: b, sub: bw.sub(a, y0, b, y1 + 1))
  (outp, y0, y1)

# ---- norm (segment.py) ----

proc norm*(sub: Bits, hcap: int): seq[float32] =
  let s = float(GH) / float(max(hcap, 1))
  var src = FImg(w: sub.w, h: sub.h, d: newSeq[float32](sub.d.len))
  for i, v in sub.d: src.d[i] = (if v: 1'f32 else: 0'f32)
  let im = resizeArea(src, max(1, int(pyRound(float(sub.w) * s))), GH)
  var canvas = FImg(w: GW, h: GH, d: newSeq[float32](Dim))
  let ww = min(GW, im.w)
  let off = (GW - ww) div 2
  for y in 0 ..< GH:
    for x in 0 ..< ww:
      canvas.d[y * GW + off + x] = im.d[y * im.w + x]
  let blurred = gaussian3(canvas, 0.8)
  result = blurred.d
  let n = sqrtf(kks_sdot(addr result[0], csize_t(Dim)))
  if n != 0:
    for i in 0 ..< Dim: result[i] = result[i] / n

# ---- feats.py ----

proc meanRegion(g: Bits, y0, y1, x0, x1: int): float =
  ## g[y0:y1, x0:x1].mean() with numpy slice clamping; NaN when empty
  let ya = max(0, min(y0, g.h))
  let yb = max(ya, min(y1, g.h))
  let xa = max(0, min(x0, g.w))
  let xb = max(xa, min(x1, g.w))
  let n = (yb - ya) * (xb - xa)
  if n == 0: return NaN
  var c = 0
  for y in ya ..< yb:
    for x in xa ..< xb:
      if g.d[y * g.w + x]: inc c
  float(c) / float(n)

proc lowerRight(g: Bits): float =
  meanRegion(g, int(float(g.h) * 0.55), int(float(g.h) * 0.85), int(float(g.w) * 0.7), g.w)

proc leftStraight(g: Bits): float =
  var ls: seq[int]
  for r in int(float(g.h) * 0.12) ..< int(float(g.h) * 0.88):
    for x in 0 ..< g.w:
      if g.d[r * g.w + x]:
        ls.add x
        break
  if ls.len == 0: return NaN
  let lim = max(1.0, float(g.w) * 0.08)
  var c = 0
  for v in ls:
    if float(v) <= lim: inc c
  float(c) / float(ls.len)

proc bottomRightTail(g: Bits): float =
  let y0 = int(float(g.h) * 0.75)
  var br, bl = 0
  for y in y0 ..< g.h:
    for x in 0 ..< g.w:
      if g.d[y * g.w + x]:
        if x >= g.w div 2: inc br else: inc bl
  float(br - bl) / (float(br + bl) + 1e-6)

# ---- classify ----

type Glyph* = object
  label*: string
  conf*: float
  top*: seq[int]
  sim*: seq[float32]

proc classify*(lib: GlyphLib, sub: Bits, hc: int, scores: var seq[float32]): Glyph =
  let v = norm(sub, hc)
  if scores.len != lib.n: scores.setLen(lib.n)
  kks_gemv(unsafeAddr lib.x[0], csize_t(lib.n), unsafeAddr v[0], csize_t(Dim), addr scores[0])
  # argsort(-s)[:5]: exact ties are duplicate library vectors with the same label, so their order doesn't matter
  var top: seq[int]
  for i in 0 ..< lib.n:
    let s = scores[i]
    var pos = top.len
    while pos > 0 and scores[top[pos - 1]] < s: dec pos
    if pos < 5:
      top.insert(i, pos)
      if top.len > 5: top.setLen(5)
  let best = lib.y[top[0]]
  let sim = float(scores[top[0]])
  var agreeN = 0
  for t in top:
    if lib.y[t] == best: inc agreeN
  let agree = float(agreeN) / float(top.len)
  var lab = best
  # the glyph cropped to its ink
  var x0 = sub.w
  var y0 = sub.h
  var x1 = -1
  var y1 = -1
  for y in 0 ..< sub.h:
    for x in 0 ..< sub.w:
      if sub.d[y * sub.w + x]:
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
  let g = sub.sub(x0, y0, x1 + 1, y1 + 1)
  if lab in ["C", "G"]:
    lab = if lowerRight(g) > 0.45: "G" else: "C"
  elif lab in ["B", "8"]:
    lab = if leftStraight(g) < 0.9: "8" else: "B"
  elif lab in ["0", "D", "Q"]:
    let t = bottomRightTail(g)
    let st = leftStraight(g)
    lab = if t > 0.12: "Q" elif t < -0.08 and st > 0.95: "D" else: "0"
  let conf = min(1.0, max(0.0, (sim - 0.80) / 0.12)) * agree
  result = Glyph(label: lab, conf: conf, top: top)
  for t in top: result.sim.add scores[t]

# ---- the KKS grammar (fontlib.interpret) ----

proc isD(c: char): bool = c in {'0' .. '9'}
proc isL(c: char): bool = c in {'A' .. 'Z'}

proc fits*(s: string, pat: string, start = 0): bool =
  ## s[start ..] begins with the pattern: D = digit, L = A-Z, I = digit or 'I', A = A-Z or digit
  if s.len - start < pat.len: return false
  for i, p in pat:
    let c = s[start + i]
    case p
    of 'D': (if not c.isD: return false)
    of 'L': (if not c.isL: return false)
    of 'I': (if not (c.isD or c == 'I'): return false)
    of 'A': (if not (c.isD or c.isL): return false)
    else: (if c != p: return false)
  true

proc full*(s, pat: string): bool = s.len == pat.len and s.fits(pat)

proc allIn(s: string, lo, hi: int, ok: proc (c: char): bool): bool =
  if s.len < lo or s.len > hi: return false
  for c in s:
    if not ok(c): return false
  true

proc fixKks(s: string): string =
  result = s
  for pat in ["DDLLLDDLLDDD", "DDLLLDD", "LLDDD"]:
    if result.len >= pat.len:
      for i, c in pat:
        if c == 'D' and result[i] == 'I': result[i] = '1'
        if c == 'D' and result[i] == 'O': result[i] = '0'
      break

proc matchFull(s: string, kks, suffix: var string): bool =
  ## FULL = ^(\d{2}[A-Z]{3}\d{2}[A-Z]{2}\d{3})((?:X[A-Z]{1,2}\d{1,2})|[A-Z]{0,2})$
  if not s.fits("DDLLLDDLLDDD"): return false
  let rest = s[12 .. ^1]
  var ok = rest.allIn(0, 2, isL)
  if not ok and rest.len >= 3 and rest[0] == 'X':
    var i = 1
    while i < rest.len and rest[i].isL: inc i
    let nl = i - 1
    let nd = rest.len - i
    ok = nl in 1 .. 2 and nd in 1 .. 2 and rest[i .. ^1].allIn(1, 2, isD)
  if ok:
    kks = s[0 ..< 12]
    suffix = rest
  ok

type Interp* = object
  kind*: string
  kks*: string
  hasKks*: bool
  suffix*: string
  isa*: string
  hasIsa*: bool        ## isa key present (instrument)
  isaNull*: bool
  note*: string

proc interpret*(top0, bottom0: string): Interp =
  var top = top0
  if top.len == 6 and top[0] == 'U' and top.fits("ULLLDD"): top = "11" & top[1 .. ^1]
  if top.allIn(1, 6, proc (c: char): bool = c.isL or c == '1') and not top.fits("DD"):
    top = top.replace('1', 'I')
  if top.fits("IILLL"): top = fixKks(top)
  let bottom = fixKks(bottom0)
  var kks, suffix: string
  let m = matchFull(bottom, kks, suffix)
  if m and top.strip(chars = Whitespace + {'\x1c', '\x1d', '\x1e', '\x1f', '\x85', '\xa0'}).len == 0:
    return Interp(kind: "instrument", kks: kks, hasKks: true, suffix: suffix, hasIsa: true, isaNull: true)
  if m and top.allIn(1, 6, isL):
    let v = if top.startsWith("PD"): 'P' else: top[0]
    top = top[0] & top[1 .. ^1].replace('G', 'C')
    if kks[7] == 'G' and kks[8] == v: kks = kks[0 ..< 7] & "C" & kks[8 .. ^1]
    return Interp(kind: "instrument", kks: kks, hasKks: true, suffix: suffix, isa: top, hasIsa: true)
  let sys = top.full("DDLLLDD")
  if sys and (bottom.full("LLDDD") or bottom.full("LLDDDL")):
    return Interp(kind: "equipment", kks: top & bottom, hasKks: true, suffix: "")
  if sys and bottom.allIn(3, 6, proc (c: char): bool = c.isL or c.isD):
    return Interp(kind: "suspect", note: "component code \"" & bottom & "\" does not fit KKS format (drawing error?)")
  if bottom.fits("LLLDD") or bottom.fits("DLLLDD") or top.fits("LLLDD") or top.fits("DLLLDD"):
    return Interp(kind: "suspect", note: "partially read tag")
  Interp(kind: "other")
