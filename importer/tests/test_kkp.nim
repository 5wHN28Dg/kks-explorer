## The .kkp writer against ref/pathstore.from_pdf_page on a synthetic drawing (tests/make_kkp_vectors.py): a page
## with /Rotate and a crop box, every path kind and style, an RGBA image and a turned grey one. No plant data; the
## same comparison on the 11 real sheets is tests/diff_kkp.nim (local only).
import std/[os, base64, strutils, unittest]
import kks/[json, pathstore]
import kksi/[mupdf, kkp, jxl]

const Dir = currentSourcePath().parentDir / "vectors"

suite "path store writer":
  init()
  let want = parseStrict(readFile(Dir / "kkp-sample.json"))
  let doc = mupdf.open(Dir / "kkp-sample.pdf")
  let d = fromPdfPage(doc, int(want["rot"].i))
  doc.close()
  test "vector paths: the reference's bytes":
    var vec = d
    vec.images = @[]
    check encode(vec) == base64.decode(want["kkp"].s)
  test "images: placement and pixels (lossless JPEG XL round trip)":
    check d.images.len == want["images"].elems.len
    for i, w in want["images"].elems:
      if i >= d.images.len: break
      let im = d.images[i]
      check im.after == int(w["after"].i)
      check im.rect == [int64(w["rect"][0].i), int64(w["rect"][1].i), int64(w["rect"][2].i), int64(w["rect"][3].i)]
      let (iw, ih, _, px) = decodeRgba(im.data)
      check [iw, ih] == [int(w["w"].i), int(w["h"].i)]
      check cast[string](px) == base64.decode(w["rgba"].s)

proc markedPdf(path: string, rotate: int) =
  ## a 200×100 pt page with its own /Rotate and one filled square near its top-left corner (PDF y up)
  let content = "0 0 0 rg 10 70 20 20 re f\n"
  var objs = @["<< /Type /Catalog /Pages 2 0 R >>",
               "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Rotate " & $rotate & " /Contents 4 0 R >>",
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

suite "the path store in the overview's frame":
  init()
  test "every page /Rotate × every sheet rotation: the mark lands where the overview shows it":
    let dir = getTempDir() / "kksimp"
    createDir(dir)
    for pageRot in [0, 90, 180, 270]:
      let src = dir / ("rot" & $pageRot & ".pdf")
      markedPdf(src, pageRot)
      for rot in [0, 90, 180, 270]:
        # the overview and the tags: rotatedCopy, rendered at 1 px per pt; the mark's centre is its dark pixels'
        let copy = rotatedCopy(src, rot)
        let px = copy.renderGray(1.0)
        copy.close()
        var sx, sy, n = 0
        for y in 0 ..< px.h:
          for x in 0 ..< px.w:
            if px.data[y * px.w + x] < 128: sx += x; sy += y; inc n
        # the path store: its one path's bbox centre, in pt
        let doc = mupdf.open(src)
        let d = fromPdfPage(doc, sheetExtra(rot, doc.pageRotation), images = false)
        doc.close()
        let b = d.paths[0].bbox
        let (kx, ky) = (float(b[0] + b[2]) / 2 / float(Q), float(b[1] + b[3]) / 2 / float(Q))
        checkpoint "page /Rotate " & $pageRot & ", rot " & $rot
        check n > 0
        check [int(d.width) div Q, int(d.height) div Q] == [px.w, px.h]
        check abs(float(sx) / float(n) + 0.5 - kx) < 1.5
        check abs(float(sy) / float(n) + 0.5 - ky) < 1.5
