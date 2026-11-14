## Tags from the PDF's text layer (textlayer.nim) on synthetic pages written here: codes as real text in Helvetica,
## across and up the page, with instrument letters, marks that are not letters, a code missing its unit number,
## and text that is not a tag. Also the path store of such a page (its text as glyph outlines, a dashed line cut into
## pieces) and the limits for crafted files. No plant data.
import std/[os, strutils, unittest, sequtils]
import kks/pathstore
import kksi/[mupdf, fontlib, extract, textlayer, kkp]

proc writePdf(path, content: string, w = 600, h = 400, rotate = 0) =
  var objs = @["<< /Type /Catalog /Pages 2 0 R >>",
               "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " & $w & " " & $h & "] /Rotate " & $rotate &
                 " /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
               "<< /Length " & $content.len & " >>\nstream\n" & content & "endstream",
               "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
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

proc txt(s: string, x, y: float, size = 6.0, m = "1 0 0 1"): string =
  ## one text object at (x, y) (PDF coordinates, y up); m: the text matrix's rotation part
  "BT /F1 " & $size & " Tf " & m & " " & $x & " " & $y & " Tm (" & s & ") Tj ET\n"

const Up = "0 1 -1 0"      ## text reading up the page

let dir = getTempDir() / "kksimp"
createDir(dir)

proc page(): string =
  result.add txt("10LAB70", 50, 350) & txt("AA101", 50, 343) & txt("c", 75, 343)   # equipment, a class letter beside
  result.add txt("PI", 155, 300) & txt("10LAB70", 150, 293) & txt("CP501", 151, 286)  # instrument letters above
  result.add txt("NO", 255, 250) & txt("10LAB70", 250, 243) & txt("AA201", 250, 236)  # "normally open" over a valve
  result.add txt("10LAB71", 400, 100, m = Up) & txt("AA102", 407, 100, m = Up)      # up the page, the next line right
  result.add txt("10LAB72AA301", 50, 200)                                           # a whole code alone
  result.add txt("Sheet 2, Field 3/B, 10LAB73AA401", 50, 150)                       # a code inside a sentence
  result.add txt("TIRAZ", 300, 150) & txt("MAD11", 300, 143) & txt("CT031A", 300, 136)  # no unit number
  result.add txt("10LAB70", 450, 350) & txt("AA101", 450, 343)                      # the same code again
  result.add txt("10LAB75", 450, 250, m = "0.7071 0.7071 -0.7071 0.7071") &        # slanted: not read
             txt("AA501", 455, 245, m = "0.7071 0.7071 -0.7071 0.7071")
  result.add txt("10LAB76", 50, 100) & txt("AA601", 50, 80)                         # too far apart to pair
  result.add "[3 2] 0 d 0.5 w 50 50 m 200 50 l S\n"                                 # a dashed line

proc tagsOf(path: string, unit = ""): seq[Tag] =
  let d = rotatedCopy(path, 0)
  result = textTags(d, unit)
  d.close()

proc find(ts: seq[Tag], code: string): seq[Tag] = ts.filterIt(it.interp.kks & it.interp.suffix == code)

suite "tags from the text layer":
  init()
  writePdf(dir / "text.pdf", page())

  test "pairs, letters, whole codes, and what is not a tag":
    let ts = tagsOf(dir / "text.pdf")
    let eq = ts.find("10LAB70AA101")
    check eq.len == 2
    for t in eq:
      check t.interp.kind == "equipment" and t.status == "auto" and t.conf == 1.0 and t.orient == 'h'
      check t.top == "10LAB70" and t.bottom == "AA101"
      check t.flag == "duplicate KKS on this sheet"
    let pi = ts.find("10LAB70CP501")
    check pi.len == 1 and pi[0].interp.kind == "instrument" and pi[0].interp.isa == "PI" and not pi[0].interp.isaNull
    check pi[0].top == "PI" and pi[0].bottom == "10LAB70CP501"
    check pi[0].flag == ""
    let v = ts.find("10LAB70AA201")         # "NO" above a valve is not instrument letters
    check v.len == 1 and v[0].interp.kind == "equipment" and v[0].interp.isa == ""
    let up = ts.find("10LAB71AA102")
    check up.len == 1 and up[0].orient == 'v' and up[0].status == "auto"
    let whole = ts.find("10LAB72AA301")
    check whole.len == 1 and whole[0].interp.kind == "equipment"
    check ts.find("10LAB73AA401").len == 0  # inside a sentence
    check ts.find("10LAB75AA501").len == 0  # slanted
    check ts.find("10LAB76AA601").len == 0  # 20 pt apart: not one tag
    # the box covers the letters and both codes, in page points (y down), 1 pt around the text
    let b = pi[0].bbox
    check b[0] < 151 and b[2] > 170 and b[1] < 400 - 300 - 4 and b[3] > 400 - 286
    # ids follow the page, top to bottom
    var last = -1.0
    for i, t in ts:
      check t.id == "t" & $i
      check t.bbox[1] >= last
      last = t.bbox[1]

  test "a code without its unit number: the review queue, or --unit":
    let r = tagsOf(dir / "text.pdf").filterIt(it.bottom.endsWith("CT031A"))
    check r.len == 1 and r[0].status == "review" and r[0].interp.kind == "suspect" and not r[0].interp.hasKks
    check "unit number" in r[0].interp.note
    let u = tagsOf(dir / "text.pdf", "10").find("10MAD11CT031A")
    check u.len == 1 and u[0].status == "auto" and u[0].interp.kind == "instrument" and u[0].interp.isa == "TIRAZ"
    check u[0].interp.kks == "10MAD11CT031" and u[0].interp.suffix == "A" and "10" in u[0].interp.note

  test "the grammar of a code read from text":
    check textInterp("", "10LAB70AA101").kind == "equipment"
    check textInterp("", "10LAB70AA101A").kind == "equipment"
    check textInterp("TI", "10LAB70CT101").isa == "TI"
    let n = textInterp("", "10LAB70CT101XB31")
    check n.kind == "instrument" and n.isaNull and n.suffix == "XB31"
    check textInterp("", "10LAB70").kind == "other"
    # no reading corrections: a G in the letters or the code stays a G
    let g = textInterp("PGI", "10LAB70GP101")
    check g.isa == "PGI" and g.kks == "10LAB70GP101"

  test "orientation: the most text reading left to right":
    var best = low(int)
    var bestAt = -1
    for extra in [0, 90, 180, 270]:
      let d = rotatedCopy(dir / "text.pdf", extra)
      let n = uprightScore(d)
      d.close()
      if n > best: (best, bestAt) = (n, extra)
    check bestAt == 0

  test "orientation: a sparse sheet with more labels up the page than across it":
    var c = txt("TITLE OF THE SHEET", 400, 30, 8)                  # 18 characters across
    for i in 0 .. 5: c.add txt("10LAB7" & $i & " AA10" & $i, 100 + float(i) * 30, 100, m = Up)   # 72 up the page
    writePdf(dir / "sparse.pdf", c)
    var best = low(int)
    var bestAt = -1
    for extra in [0, 90, 180, 270]:
      let d = rotatedCopy(dir / "sparse.pdf", extra)
      let n = uprightScore(d)
      d.close()
      if n > best: (best, bestAt) = (n, extra)
    check bestAt == 0
    removeFile(dir / "sparse.pdf")

  test "a page turned by /Rotate: the same tags once turned back":
    writePdf(dir / "turned.pdf", page(), rotate = 90)
    var at = -1
    var best = low(int)
    for extra in [0, 90, 180, 270]:
      let d = rotatedCopy(dir / "turned.pdf", extra)
      let n = uprightScore(d)
      d.close()
      if n > best: (best, at) = (n, extra)
    let d = rotatedCopy(dir / "turned.pdf", at)
    let ts = textTags(d)
    d.close()
    check ts.find("10LAB70CP501").len == 1 and ts.find("10LAB71AA102").len == 1
    check ts.find("10LAB70AA101")[0].orient == 'h'

  test "a page without text has no text tags (the glyph reader's path)":
    writePdf(dir / "strokes.pdf", "0.5 w 50 50 m 200 50 l S\n")
    check tagsOf(dir / "strokes.pdf").len == 0

  test "the path store keeps the text as outlines and cuts dashes into pieces":
    let doc = mupdf.open(dir / "text.pdf")
    let withText = fromPdfPage(doc, 0, images = true, text = true)
    let without = fromPdfPage(doc, 0, images = true)
    doc.close()
    var fills = 0
    for p in withText.paths:
      if (withText.styles[p.style].kind and Fill) != 0: inc fills
    check fills >= 100                              # one filled outline per visible glyph
    check without.paths.len < withText.paths.len    # a glyph-read drawing's store: as before, no text
    for p in without.paths: check (without.styles[p.style].kind and Fill) == 0
    # the dashed line: 150 pt with a 3-on 2-off pattern = 30 dashes, in one path of separate pieces
    var dashed = 0
    for p in without.paths:
      var moves = 0
      for k in p.cmdStart ..< p.cmdStart + p.cmdCount:
        if without.ops[k] == OpMove: inc moves
      dashed = max(dashed, moves)
    check dashed == 30

  test "limits for crafted files":
    var many = ""
    for i in 0 .. MaxCodeRuns:
      many.add txt("10LAB" & align($(i mod 100), 2, '0'), float(i mod 100) * 20, float(i div 100 mod 80) * 5, 1.0)
    writePdf(dir / "many.pdf", many, 2000, 400)
    expect TextLimitError:
      discard tagsOf(dir / "many.pdf")

  test "limits: characters on the page, invisible text":
    writePdf(dir / "chars.pdf", txt("10LAB70", 50, 350) & txt("AA101", 50, 343))
    let d = rotatedCopy(dir / "chars.pdf", 0)
    check runs(d, 12).len == 2
    expect TextLimitError:
      discard runs(d, 11)
    d.close()
    # render mode 3 (invisible, an OCR layer): not a tag
    writePdf(dir / "chars.pdf", "BT 3 Tr /F1 6 Tf 50 350 Td (10LAB70) Tj 0 -7 Td (AA101) Tj ET\n")
    check tagsOf(dir / "chars.pdf").len == 0
    removeFile(dir / "chars.pdf")

  test "dash patterns: odd length, phase, zero and negative entries":
    proc dashes(pattern: string): int =
      writePdf(dir / "dash.pdf", pattern & " 0.5 w 50 50 m 200 50 l S\n")
      let doc = mupdf.open(dir / "dash.pdf")
      let d = fromPdfPage(doc, 0, images = true)
      doc.close()
      for p in d.paths:
        for k in p.cmdStart ..< p.cmdStart + p.cmdCount:
          if d.ops[k] == OpMove: inc result
    check dashes("[3] 0 d") == 25          # 3 on, 3 off
    check dashes("[3 2] 1 d") == 31        # the first dash 2 long, then every 5 pt: the last one cut short at 150
    check dashes("[3 2] 0 d") == 30
    check dashes("[0 0] 0 d") == 1         # nothing to cut: the line whole
    check dashes("[3 -2] 0 d") >= 1        # a negative gap counts as 0: no piece runs backwards
    removeFile(dir / "dash.pdf")

  test "a Type 3 font in a text-layer drawing's path store is refused":
    var objs = @["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                 "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 400] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"]
    let content = "BT /F1 6 Tf 50 350 Td (A) Tj ET\n"
    let glyph = "1000 0 0 0 750 750 d1 0 0 750 750 re f\n"
    objs.add "<< /Length " & $content.len & " >>\nstream\n" & content & "endstream"
    objs.add "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 750 750] /FontMatrix [0.001 0 0 0.001 0 0] " &
             "/CharProcs << /a 6 0 R >> /Encoding << /Type /Encoding /Differences [65 /a] >> /FirstChar 65 /LastChar 65 /Widths [1000] >>"
    objs.add "<< /Length " & $glyph.len & " >>\nstream\n" & glyph & "endstream"
    var s = "%PDF-1.4\n"
    var offs: seq[int]
    for i, o in objs:
      offs.add s.len
      s.add $(i + 1) & " 0 obj\n" & o & "\nendobj\n"
    let xref = s.len
    s.add "xref\n0 " & $(objs.len + 1) & "\n0000000000 65535 f \n"
    for o in offs: s.add align($o, 10, '0') & " 00000 n \n"
    s.add "trailer\n<< /Size " & $(objs.len + 1) & " /Root 1 0 R >>\nstartxref\n" & $xref & "\n%%EOF\n"
    writeFile(dir / "t3.pdf", s)
    let doc = mupdf.open(dir / "t3.pdf")
    discard fromPdfPage(doc, 0, images = true)      # a glyph-read drawing: text left out as before
    expect MupdfError:
      discard fromPdfPage(doc, 0, images = true, text = true)
    doc.close()
    removeFile(dir / "t3.pdf")

  removeFile(dir / "text.pdf")
  removeFile(dir / "turned.pdf")
  removeFile(dir / "strokes.pdf")
  removeFile(dir / "many.pdf")
