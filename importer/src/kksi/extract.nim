## extractor/extract_sheet.extract + reader3.read_sheet (decision 0026): every tag on one (already rotated) sheet.

import std/[tables, strutils]
import mupdf, imgops, fontlib, reader, textlines

type Tag* = object
  id*: string
  orient*: char
  bbox*: array[4, float]          ## PDF points, rounded to 0.1
  top*, bottom*: string
  conf*: float                    ## rounded to 0.01
  interp*: Interp
  status*: string
  flag*: string
  openBalloon*: bool

proc r1(x: float): float = pyRoundTo(x, 1)

proc readSheet*(r: var Reader, sh: Sheet): seq[Tag] =
  let k = sh.k
  let pairs = pairCells(sh.cells)
  var used = newSeq[bool](sh.cells.len)
  for p in pairs:
    used[p.a] = true
    used[p.b] = true
  for n, p in pairs:
    let a = sh.cells[p.a]
    let b = sh.cells[p.b]
    let (ia0, ma0) = sh.cellImage(a, p.o)
    var (t, ct) = r.read(ia0, ma0)
    let (ib0, mb0) = sh.cellImage(b, p.o)
    var (u, cu) = r.read(ib0, mb0)
    if p.o == 'v' and interpret(t, u).kind notin ["equipment", "instrument"]:
      let (ib, mb) = sh.cellImage(b, p.o, true)
      let (t2, ct2) = r.read(ib, mb)
      let (ia, ma) = sh.cellImage(a, p.o, true)
      let (u2, cu2) = r.read(ia, ma)
      if interpret(t2, u2).kind in ["equipment", "instrument"]:
        t = t2; ct = ct2; u = u2; cu = cu2
    let bb = [float(min(a.x, b.x)) / k, float(min(a.y, b.y)) / k, float(max(a.x + a.w, b.x + b.w)) / k,
              float(max(a.y + a.h, b.y + b.h)) / k]
    result.add Tag(id: $n, orient: p.o, bbox: [bb[0].r1, bb[1].r1, bb[2].r1, bb[3].r1], top: t, bottom: u,
                   conf: pyRoundTo(min(ct, cu), 2), interp: interpret(t, u))
  var n = 0
  for i, c in sh.cells:
    if used[i]: continue
    let (ok, s) = r.readSingle(sh, c)
    let id = "s" & $n
    inc n
    if not ok: continue
    let it = interpret(s.t, s.u)
    if it.kind notin ["equipment", "instrument"]: continue
    let bb = [float(c.x) / k, float(c.y) / k, float(c.x + c.w) / k, float(c.y + c.h) / k]
    result.add Tag(id: id, orient: s.o, bbox: [bb[0].r1, bb[1].r1, bb[2].r1, bb[3].r1], top: s.t, bottom: s.u,
                   conf: pyRoundTo(s.conf, 2), interp: it)

proc crop(doc: Doc, r: array[4, float], orient: char): (imgops.Gray, imgops.Gray) =
  let g = doc.renderGray(DpiRead / 72.0, (r[0], r[1], r[2], r[3]), hasClip = true)
  var im = imgops.Gray(w: g.w, h: g.h, d: g.data)
  if orient == 'v': im = rotateCw(im)
  im = border(im, 30, 30, 30, 30, 255)
  (im, newGray(im.w, im.h, 255))

proc near(b, e: array[4, float], pad = 12.0): bool =
  let cx = (b[0] + b[2]) / 2
  let cy = (b[1] + b[3]) / 2
  e[0] - pad < cx and cx < e[2] + pad and e[1] - pad < cy and cy < e[3] + pad

proc instrumentCode(s: string): bool =
  ## ^\d{2}[A-Z]{3}\d{2}[A-Z]{2}\d{3}[A-Z0-9]*$
  if not s.fits("DDLLLDDLLDDD"): return false
  for c in s[12 .. ^1]:
    if c notin {'A' .. 'Z', '0' .. '9'}: return false
  true

proc containsCode(s: string): bool =
  ## re.search(r'[A-Z]{3}\d{2}[A-Z]{2}\d', s)
  for i in 0 .. s.len - 8:
    if s.fits("LLLDDLLD", i): return true
  false

proc extract*(r: var Reader, doc: Doc, paths: seq[VPath]): seq[Tag] =
  let sh = detect(doc)
  let tags = r.readSheet(sh)
  let lines = process(paths)
  var extra: seq[Tag]
  for li, L in lines:
    if L.chars < 11 or L.chars > 18 or not (4 < L.h and L.h < 9): continue
    let b = L.bbox
    var skip = false
    for t in tags:
      if near(b, t.bbox): skip = true
    for e in extra:
      if near(b, e.bbox, 4): skip = true
    if skip: continue
    let o = L.axis
    let (im, mask) = crop(doc, [b[0] - 2, b[1] - 2, b[2] + 2, b[3] + 2], o)
    let (u, cu) = r.read(im, mask)
    if not u.fits("DDLLLDD") and cu < 0.3 and not containsCode(u): continue
    var best: array[4, float]
    var hasBest = false
    for mi, M in lines:
      if mi == li or M.axis != o: continue
      let m = M.bbox
      if o == 'v' and 3 < b[0] - m[2] and b[0] - m[2] < 14 and abs((m[1] + m[3]) / 2 - (b[1] + b[3]) / 2) < 12:
        best = m; hasBest = true
      if o == 'h' and 3 < b[1] - m[3] and b[1] - m[3] < 14 and abs((m[0] + m[2]) / 2 - (b[0] + b[2]) / 2) < 12:
        best = m; hasBest = true
    var tt = ""
    var ct = 1.0
    if hasBest:
      let (im2, mask2) = crop(doc, [best[0] - 2, best[1] - 2, best[2] + 2, best[3] + 2], o)
      (tt, ct) = r.read(im2, mask2)
    var bb = b
    if hasBest:
      bb = [min(b[0], best[0]), min(b[1], best[1]), max(b[2], best[2]), max(b[3], best[3])]
    extra.add Tag(id: "ob" & $li, orient: o, bbox: [bb[0].r1, bb[1].r1, bb[2].r1, bb[3].r1], top: tt, bottom: u,
                  conf: pyRoundTo(min(cu, ct), 2), interp: interpret(tt, u), openBalloon: true)
  result = tags & extra
  for t in result.mitems:
    if t.interp.kind == "other" and instrumentCode(t.bottom):
      t.interp = Interp(kind: "instrument", kks: t.bottom[0 ..< 12], hasKks: true, suffix: t.bottom[12 .. ^1],
                        hasIsa: true, isaNull: true)
      t.conf = min(t.conf, 0.25)
    if t.interp.kind == "instrument" and t.interp.hasIsa and not t.interp.isaNull and t.interp.isa.len > 0 and
       not (t.interp.isa.len in 1 .. 6 and t.interp.isa.allCharsInSet({'A' .. 'Z'})):
      t.interp.isaNull = true
      t.interp.isa = ""
      t.conf = min(t.conf, 0.25)
    let tagKind = t.interp.kind in ["equipment", "instrument"]
    t.status = if tagKind and t.conf >= 0.3: "auto"
               elif t.interp.kind != "other" or t.top.len > 0 or t.bottom.len > 0: "review"
               else: "ignore"
  var counts = initCountTable[string]()
  for t in result:
    if t.status == "auto": counts.inc(t.interp.kks & t.interp.suffix)
  for t in result.mitems:
    if t.status == "auto" and counts[t.interp.kks & t.interp.suffix] > 1: t.flag = "duplicate KKS on this sheet"
