## Tags from the PDF's text layer: drawings whose tags are real text (CAD exports with fonts), not loose strokes.
## No glyph reading: the characters come from MuPDF's structured text, and the KKS grammar decides what is a tag.
##
## How the text runs are put together (importer/README "Tags from the text layer"):
## - a line of text is split at gaps wider than 0.6 × the font size (a label and the letter or size printed beside it on
##   the same baseline); ordinary spaces stay inside a run;
## - a run that is a system code (`DDLLLDD`, or `LLLDD` when the drawing leaves the unit number out) pairs with the run
##   just under it, in its own reading direction, that is a component code (`LLDDD` and an optional suffix): the gap
##   between them less than one line, and most of the component's width under the system code. Pairs are made
##   nearest first, each run used once;
## - instrument letters (1–6 capitals) just above the system code make the tag an instrument, only when the component
##   is a measurement (`C…`): other words above a valve (normally open/closed marks, signal names) are not letters;
## - a run that is a whole code on its own is a tag too;
## - a code without its unit number goes to the review queue, or gets the number given with `--unit NN`.

import std/[algorithm, tables, unicode, strutils]
import mupdf, fontlib, extract, textlines

const
  MaxChars* = 2_000_000     ## characters on one page; a real P&ID page has a few thousand (a crafted file is refused)
  MaxCodeRuns* = 20_000     ## code-like runs on one page; pairing is quadratic in them (real pages: about 150)
  GapSplit = 0.6            ## a line splits where the gap between characters is wider than this × the font size

type
  TextLimitError* = object of CatchableError
  RawChar {.bycopy.} = object
    c: cint
    line: cint
    x0, y0, x1, y1: cfloat
    size: cfloat
    dx, dy: cfloat
  Run* = object
    text*: string
    box*: array[4, float]   ## page points
    dir*: (int, int)        ## the baseline's direction: (1, 0) left to right, (0, -1) bottom to top, …
    size*: float
    a0*, a1*, p0*, p1*: float  ## the box in the run's own frame: along the baseline, and down from it

proc kks_text_chars(d: Doc, maxChars: cint, n: ptr cint): ptr UncheckedArray[RawChar] {.importc, cdecl.}
proc kks_error(): cstring {.importc, cdecl.}
proc kks_free(p: pointer) {.importc, cdecl.}

proc frame(r: var Run) =
  ## the box in the run's frame: `a` along the baseline, `p` across it, growing downwards from the text's top
  let (dx, dy) = (float(r.dir[0]), float(r.dir[1]))
  let (ex, ey) = (-dy, dx)
  var a, p: seq[float]
  for (x, y) in [(r.box[0], r.box[1]), (r.box[2], r.box[1]), (r.box[0], r.box[3]), (r.box[2], r.box[3])]:
    a.add x * dx + y * dy
    p.add x * ex + y * ey
  r.a0 = min(a); r.a1 = max(a); r.p0 = min(p); r.p1 = max(p)

proc axis(x, y: float): (int, int) =
  ## the baseline's direction rounded to an axis, or (0, 0) for slanted text (never a tag here)
  let sx = if x > 0: 1 else: -1
  let sy = if y > 0: 1 else: -1
  if abs(abs(x) - 1) < 0.02 and abs(y) < 0.02: return (sx, 0)
  if abs(abs(y) - 1) < 0.02 and abs(x) < 0.02: return (0, sy)
  (0, 0)

proc runs*(doc: Doc): seq[Run] =
  ## page 0's text as runs (see the module's notes), in MuPDF's order
  var n: cint
  let p = kks_text_chars(doc, MaxChars, addr n)
  if p == nil:
    if n < 0: raise newException(TextLimitError, "The drawing's text layer has more than " & $MaxChars &
                                 " characters on the page: refused (a real P&ID has a few thousand).")
    raise newException(MupdfError, $kks_error())
  var i = 0
  while i < int(n):
    var j = i
    while j < int(n) and p[j].line == p[i].line: inc j
    let dir = axis(float(p[i].dx), float(p[i].dy))
    if dir != (0, 0):
      var cur: Run
      var lastA1 = 0.0
      var pendingSpace = false
      template flush() =
        cur.text = cur.text.strip
        if cur.text.len > 0:
          cur.frame
          result.add cur
        cur = Run()
        pendingSpace = false
      for k in i ..< j:
        let ch = p[k]
        if Rune(ch.c).isWhiteSpace or ch.c == 0:
          pendingSpace = cur.text.len > 0
          continue
        var b = [float(ch.x0), float(ch.y0), float(ch.x1), float(ch.y1)]
        var one = Run(box: b, dir: dir)
        one.frame
        if cur.text.len > 0 and one.a0 - lastA1 > GapSplit * max(cur.size, float(ch.size)): flush()
        if cur.text.len == 0:
          cur = Run(box: b, dir: dir, size: float(ch.size))
        else:
          if pendingSpace: cur.text.add ' '
          cur.box = [min(cur.box[0], b[0]), min(cur.box[1], b[1]), max(cur.box[2], b[2]), max(cur.box[3], b[3])]
          cur.size = max(cur.size, float(ch.size))
        pendingSpace = false
        cur.text.add toUTF8(Rune(ch.c))
        lastA1 = one.a1
      flush()
    i = j
  kks_free(p)

type Kind = enum other, sysCode, sysNoUnit, comp, fullCode, fullNoUnit, letters

proc kindOf(t: string): Kind =
  var kks, suffix: string
  if t.full("DDLLLDD"): sysCode
  elif t.full("LLLDD"): sysNoUnit
  elif t.fits("LLDDD") and matchFull("00AAA00" & t, kks, suffix): comp
  elif matchFull(t, kks, suffix): fullCode
  elif t.fits("LLLDDLLDDD") and matchFull("00" & t, kks, suffix): fullNoUnit
  elif t.len in 1 .. 6 and t.allCharsInSet({'A' .. 'Z'}): letters
  else: other

proc textInterp*(isa, code: string): Interp =
  ## a code read from text (no reading errors to correct, unlike fontlib.interpret): instrument letters + a full
  ## code = instrument; `DDLLLDD` + `LLDDD[L]` = equipment; a full code with a longer suffix = instrument without
  ## letters (as a full code alone in a bubble is to the glyph reader)
  var kks, suffix: string
  let ok = matchFull(code, kks, suffix)
  let c = if code.len > 7: code[7 .. ^1] else: ""
  if isa.len > 0 and ok: Interp(kind: "instrument", kks: kks, hasKks: true, suffix: suffix, isa: isa, hasIsa: true)
  elif code.len >= 7 and code[0 ..< 7].full("DDLLLDD") and (c.full("LLDDD") or c.full("LLDDDL")):
    Interp(kind: "equipment", kks: code, hasKks: true)
  elif ok: Interp(kind: "instrument", kks: kks, hasKks: true, suffix: suffix, hasIsa: true, isaNull: true)
  else: Interp(kind: "other")

proc under(upper, lower: Run): (bool, float) =
  ## `lower` is the next line under `upper` in their reading direction: (fits, the gap between them)
  if upper.dir != lower.dir: return (false, 0.0)
  let h = upper.p1 - upper.p0
  let gap = lower.p0 - upper.p1
  if gap <= -0.5 * h or gap >= 1.0 * h: return (false, gap)
  (true, gap)

proc overlap(a, b: Run): float = min(a.a1, b.a1) - max(a.a0, b.a0)

proc similarSize(a, b: Run): bool = a.size > 0 and b.size > 0 and b.size / a.size in 0.7 .. 1.43

proc textTags*(doc: Doc, unit = ""): seq[Tag] =
  ## every tag in page 0's text layer, as extract.extract gives the glyph reader's (bbox in page points)
  let rs = runs(doc)
  var kinds = newSeq[Kind](rs.len)
  var nCode = 0
  for i, r in rs:
    kinds[i] = kindOf(r.text)
    if kinds[i] != other: inc nCode
  if nCode > MaxCodeRuns:
    raise newException(TextLimitError, "The drawing's text layer has more than " & $MaxCodeRuns &
                       " code-like words on the page: refused (a real P&ID has a few hundred).")
  # system code over component code, nearest first
  type Cand = tuple[gap, off: float, s, c: int]
  var cands: seq[Cand]
  for i, s in rs:
    if kinds[i] notin {sysCode, sysNoUnit}: continue
    for j, c in rs:
      if kinds[j] != comp or not similarSize(s, c): continue
      let (ok, gap) = under(s, c)
      if ok and overlap(s, c) > 0.5 * (c.a1 - c.a0):
        cands.add (gap, abs((s.a0 + s.a1) - (c.a0 + c.a1)) / 2, i, j)
  cands.sort(proc (x, y: Cand): int = cmp((x.gap, x.off, x.s, x.c), (y.gap, y.off, y.s, y.c)))
  var used = newSeq[bool](rs.len)
  type Found = tuple[top, code: int, low: int]    ## the system (or whole) code's run, the component's (-1: none)
  var found: seq[Found]
  for c in cands:
    if used[c.s] or used[c.c]: continue
    used[c.s] = true
    used[c.c] = true
    found.add (c.s, c.s, c.c)
  for i in 0 ..< rs.len:
    if kinds[i] in {fullCode, fullNoUnit} and not used[i]:
      used[i] = true
      found.add (i, i, -1)
  # instrument letters just above a measurement's code, nearest first
  var letterOf = newSeq[int](found.len)
  var lc: seq[Cand]
  for fi, f in found:
    letterOf[fi] = -1
    let codeText = rs[f.code].text & (if f.low >= 0: rs[f.low].text else: "")
    let compAt = if kinds[f.code] in {sysNoUnit, fullNoUnit}: 5 else: 7
    if codeText.len <= compAt or codeText[compAt] != 'C': continue
    for j, u in rs:
      if kinds[j] != letters or used[j] or not similarSize(rs[f.code], u): continue
      let (ok, gap) = under(u, rs[f.code])
      if ok and overlap(u, rs[f.code]) >= 0.8 * (u.a1 - u.a0):
        lc.add (gap, abs((u.a0 + u.a1) - (rs[f.code].a0 + rs[f.code].a1)) / 2, fi, j)
  lc.sort(proc (x, y: Cand): int = cmp((x.gap, x.off, x.s, x.c), (y.gap, y.off, y.s, y.c)))
  var letterUsed = newSeq[bool](rs.len)
  for c in lc:
    if letterOf[c.s] >= 0 or letterUsed[c.c]: continue
    letterOf[c.s] = c.c
    letterUsed[c.c] = true
  # the tags, in page order (top to bottom, then left to right) so their ids follow the drawing, not MuPDF's order
  for fi, f in found:
    let isa = if letterOf[fi] >= 0: rs[letterOf[fi]].text else: ""
    var sys = rs[f.code].text
    var low = if f.low >= 0: rs[f.low].text else: ""
    if f.low < 0:                      # a whole code: split where the component starts
      let at = if kinds[f.code] == fullNoUnit: 5 else: 7
      low = sys[at .. ^1]
      sys = sys[0 ..< at]
    var t = Tag(orient: if rs[f.code].dir[0] != 0: 'h' else: 'v', conf: 1.0)
    var b = rs[f.code].box
    for k in [f.low, letterOf[fi]]:
      if k >= 0:
        let o = rs[k].box
        b = [min(b[0], o[0]), min(b[1], o[1]), max(b[2], o[2]), max(b[3], o[3])]
    t.bbox = [pyRoundTo(b[0] - 1, 1), pyRoundTo(b[1] - 1, 1), pyRoundTo(b[2] + 1, 1), pyRoundTo(b[3] + 1, 1)]
    let noUnit = kinds[f.code] in {sysNoUnit, fullNoUnit}
    if noUnit and unit.len > 0: sys = unit & sys
    t.top = if isa.len > 0: isa else: sys
    t.bottom = if isa.len > 0: sys & low else: low
    if noUnit and unit.len == 0:
      t.interp = Interp(kind: "suspect", note: "the drawing leaves out the unit number (import with --unit NN)")
      t.status = "review"
    else:
      t.interp = textInterp(isa, sys & low)
      if noUnit: t.interp.note = "unit number " & unit & " added on import (the drawing leaves it out)"
      t.status = if t.interp.kind in ["equipment", "instrument"]: "auto" else: "review"
    result.add t
  result.sort(proc (x, y: Tag): int = cmp((x.bbox[1], x.bbox[0], x.bottom), (y.bbox[1], y.bbox[0], y.bottom)))
  for i in 0 ..< result.len: result[i].id = "t" & $i
  var counts = initCountTable[string]()
  for t in result:
    if t.status == "auto": counts.inc(t.interp.kks & t.interp.suffix)
  for t in result.mitems:
    if t.status == "auto" and counts[t.interp.kks & t.interp.suffix] > 1: t.flag = "duplicate KKS on this sheet"

proc leftToRight*(doc: Doc): int =
  ## how many characters read left to right: the text reader's orientation score (all the text, title block and
  ## notes included: tags may be written up the page while the sheet's own lettering reads across it)
  for r in runs(doc):
    if r.dir == (1, 0): result += r.text.runeLen
