## The .kkp writer against ref/pathstore.from_pdf_page on a synthetic drawing (tests/make_kkp_vectors.py): a page
## with /Rotate and a crop box, every path kind and style, an RGBA image and a turned grey one. No plant data; the
## same comparison on the 11 real sheets is tests/diff_kkp.nim (local only).
import std/[os, base64, unittest]
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
