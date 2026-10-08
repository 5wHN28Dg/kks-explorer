## Off-page connectors (connectors.nim) on a synthetic page: circles with codes drawn in strokes, horizontal and
## turned both ways, plus circles that aren't connectors. No plant data.
##
## The characters are the Hershey Sans 1-stroke (Hershey Simplex) glyphs, condensed like the drawings' SHX font.
## The Hershey Fonts were originally created by Dr. A. V. Hershey while working at the U. S. National Bureau of
## Standards. The format of the Font data in this distribution was originally created by James Hurt, Cognition, Inc.
## (glyph data via Inkscape's svg_fonts/HersheySans1.svg, Windell H. Oskay; the Hershey Fonts' use restriction asks
## for this acknowledgement.)
import std/[os, strutils, unittest, math, algorithm]
import kksi/[mupdf, fontlib, connectors]

const Glyphs = currentSourcePath().parentDir.parentDir / "fontlib.kgl"

const Hershey = [
  ('A', 567, "M 378 662 L 126 0 M 378 662 L 630 0 M 220 220 L 536 220"),
  ('C', 662, "M 662 504 L 630 567 L 567 630 L 504 662 L 378 662 L 315 630 L 252 567 L 220 504 L 189 410 L 189 252 L 220 158 L 252 94.5 L 315 31.5 L 378 0 L 504 0 L 567 31.5 L 630 94.5 L 662 158"),
  ('D', 662, "M 220 662 L 220 0 M 220 662 L 441 662 L 536 630 L 598 567 L 630 504 L 662 410 L 662 252 L 630 158 L 598 94.5 L 536 31.5 L 441 0 L 220 0"),
  ('1', 630, "M 284 536 L 346 567 L 441 662 L 441 0"),
  ('2', 630, "M 220 504 L 220 536 L 252 598 L 284 630 L 346 662 L 472 662 L 536 630 L 567 598 L 598 536 L 598 472 L 567 410 L 504 315 L 189 0 L 630 0"),
  ('3', 630, "M 252 662 L 598 662 L 410 410 L 504 410 L 567 378 L 598 346 L 630 252 L 630 189 L 598 94.5 L 536 31.5 L 441 0 L 346 0 L 252 31.5 L 220 63 L 189 126"),
  ('6', 630, "M 598 567 L 567 630 L 472 662 L 410 662 L 315 630 L 252 536 L 220 378 L 220 220 L 252 94.5 L 315 31.5 L 410 0 L 441 0 L 536 31.5 L 598 94.5 L 630 189 L 630 220 L 598 315 L 536 378 L 441 410 L 410 410 L 315 378 L 252 315 L 220 220"),
  ('8', 630, "M 346 662 L 252 630 L 220 567 L 220 504 L 252 441 L 315 410 L 441 378 L 536 346 L 598 284 L 630 220 L 630 126 L 598 63 L 567 31.5 L 472 0 L 346 0 L 252 31.5 L 220 63 L 189 126 L 189 220 L 220 284 L 284 346 L 378 378 L 504 410 L 567 441 L 598 504 L 598 567 L 567 630 L 472 662 L 346 662"),
  ('9', 630, "M 598 441 L 567 346 L 504 284 L 410 252 L 378 252 L 284 284 L 220 346 L 189 441 L 189 472 L 220 567 L 284 630 L 378 662 L 410 662 L 504 630 L 567 567 L 598 441 L 598 284 L 567 126 L 504 31.5 L 410 0 L 346 0 L 252 31.5 L 220 94.5"),
  ('0', 630, "M 378 662 L 284 630 L 220 536 L 189 378 L 189 284 L 220 126 L 284 31.5 L 378 0 L 441 0 L 536 31.5 L 598 126 L 630 284 L 630 378 L 598 536 L 536 630 L 441 662 L 378 662")]

const
  Cap = 6.5            ## cap height, pt (the drawings' connector labels)
  Squeeze = 0.62       ## the SHX font is narrower than Hershey's

type Turn = enum up, left, right   ## text upright, or turned (reading bottom-to-top / top-to-bottom)

proc text(s: string, cx, cy: float, turn: Turn, track = 0.0): string =
  ## PDF content: each character one stroked path, centred on (cx, cy); PDF y points up
  let k = Cap / 662.0
  var adv = 0.0
  for c in s:
    for g in Hershey:
      if g[0] == c: adv += float(g[1]) * k * Squeeze
  var x = -adv / 2
  for c in s:
    for g in Hershey:
      if g[0] != c: continue
      let toks = g[2].splitWhitespace
      var i = 0
      while i < toks.len:
        let op = toks[i]
        let gx = x + (parseFloat(toks[i + 1]) - 160) * k * Squeeze
        let gy = parseFloat(toks[i + 2]) * k - Cap / 2
        let (px, py) = case turn
          of up: (cx + gx, cy + gy)
          of left: (cx - gy, cy + gx)     # baseline running up the page
          of right: (cx + gy, cy - gx)    # baseline running down the page
        result.add formatFloat(px, ffDecimal, 3) & " " & formatFloat(py, ffDecimal, 3) & (if op == "M": " m\n" else: " l\n")
        i += 3
      result.add "S\n"
      x += float(g[1]) * k * Squeeze + track

proc circle(cx, cy, r: float): string =
  let c = 0.5523 * r
  proc p(x, y: float): string = formatFloat(x, ffDecimal, 3) & " " & formatFloat(y, ffDecimal, 3)
  p(cx + r, cy) & " m\n" &
    p(cx + r, cy + c) & " " & p(cx + c, cy + r) & " " & p(cx, cy + r) & " c\n" &
    p(cx - c, cy + r) & " " & p(cx - r, cy + c) & " " & p(cx - r, cy) & " c\n" &
    p(cx - r, cy - c) & " " & p(cx - c, cy - r) & " " & p(cx, cy - r) & " c\n" &
    p(cx + c, cy - r) & " " & p(cx + r, cy - c) & " " & p(cx + r, cy) & " c\nS\n"

proc writePdf(path, content: string, w = 400, h = 200) =
  var objs = @["<< /Type /Catalog /Pages 2 0 R >>",
               "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " & $w & " " & $h & "] /Contents 4 0 R >>",
               "<< /Length " & $content.len & " >>\nstream\n" & content & "endstream"]
  var s = "%PDF-1.4\n"
  var offs: seq[int]
  for i, o in objs:
    offs.add s.len
    s.add $(i + 1) & " 0 obj\n" & o & "\nendobj\n"
  let xref = s.len
  s.add "xref\n0 " & $(objs.len + 1) & "\n0000000000 65535 f \n"
  for o in offs: s.add align($o, 10, '0') & " 00000 n \n"
  s.add "trailer\n<< /Size " & $(objs.len + 1) & " /Root 1 0 R >>\nstartxref\n" & $xref & "\n%%EOF\n"
  writeFile(path, s)

suite "connector labels":
  test "a letter and 1-2 digits, one blob per character":
    check connectorLabel("C16", 3) == (true, "C16")
    check connectorLabel("D2", 2) == (true, "D2")
    check connectorLabel("CI6", 3) == (true, "C16")
    check connectorLabel("AO", 2) == (true, "A0")
    check connectorLabel("C16", 4)[0] == false     # a fourth blob: not just a code
    check connectorLabel("90", 2)[0] == false
    check connectorLabel("R", 1)[0] == false
    check connectorLabel("C1A", 3)[0] == false
    check connectorLabel("C123", 4)[0] == false
    check connectorLabel("", 0)[0] == false

suite "connectors on a page":
  init()
  let dir = getTempDir() / "kksimp"
  createDir(dir)
  let pdf = dir / "connectors.pdf"
  var c = "0.35 w 1 J 1 j\n"
  # connectors (PDF y up; the page is 200 pt high)
  c.add circle(50, 150, 10.5) & text("C16", 50, 150, up)
  c.add circle(110, 150, 10.5) & text("D2", 110, 150, up)
  c.add circle(170, 150, 10.5) & text("A3", 170, 150, left)
  c.add circle(230, 150, 10.5) & text("C29", 230, 150, right)
  c.add circle(290, 150, 10.5) & text("C16", 290, 150, up)          # the same code twice on a sheet: both kept
  c.add circle(290, 150, 10.5)                                       # a circle drawn twice: counted once
  c.add "0.8 w\n" & circle(350, 150, 10.5) & text("A28", 350, 150, up, -0.2) & "0.35 w\n"   # bold, the 2 and 8 touch
  # not connectors
  c.add circle(50, 60, 10.5) & text("90", 50, 60, up)               # digits only
  c.add circle(110, 60, 10.5) & text("6", 110, 60, up)              # Block 1's numbered circles
  c.add circle(170, 60, 10.5)                                        # empty
  c.add circle(230, 60, 4) & text("C1", 230, 75, up)                # too small to be a connector, label outside
  c.add circle(290, 60, 50)                                          # too big
  c.add "270 20 40 20 re S\n" & text("D3", 290, 30, up)              # a box, not a circle
  writePdf(pdf, c)
  let lib = loadGlyphLib(Glyphs)
  let doc = rotatedCopy(pdf, 0)
  let found = findConnectors(doc, lib)
  doc.close()

  test "every connector, read, in its circle's box":
    var got: seq[(string, int, int)]
    for f in found: got.add((f.label, int(round((f.bbox[0] + f.bbox[2]) / 2)), f.turn))
    got.sort()
    check got == @[("A28", 350, 0), ("A3", 170, 1), ("C16", 50, 0), ("C16", 290, 0), ("C29", 230, 2), ("D2", 110, 0)]
    for f in found:
      check abs((f.bbox[1] + f.bbox[3]) / 2 - 50) < 0.5          # y down: 200 - 150
      check abs(f.bbox[2] - f.bbox[0] - 21) < 0.5
      check f.conf >= 0.3

  test "the page turned (rotatedCopy 90): every label still read, the A3 upside down":
    let d2 = rotatedCopy(pdf, 90)
    let f2 = findConnectors(d2, lib)
    d2.close()
    var got: seq[(string, int)]
    for f in f2: got.add((f.label, f.turn))
    got.sort()
    check got == @[("A28", 1), ("A3", 3), ("C16", 1), ("C16", 1), ("C29", 0), ("D2", 1)]
