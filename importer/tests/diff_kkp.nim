## kkp.fromPdfPage against ref/pathstore.from_pdf_page (tests/dump_kkp.py) on every sheet: identical .kkp bytes.
##   diff_kkp REFDIR [SHEET...]
import std/[os, times, strutils]
import kks/[json, pathstore]
import kksi/[mupdf, kkp, jxl]

init()
let dir = paramStr(1)
let only = commandLineParams()[1 .. ^1]
var allOk = true
for s in parseStrict(readFile(dir / "manifest.json")).elems:
  let sid = s["id"].s
  if only.len > 0 and sid notin only: continue
  let t0 = epochTime()
  let doc = mupdf.open(s["src"].s)
  let d = fromPdfPage(doc, int(s["rot"].i))
  var vec = d
  vec.images = @[]
  let mine = encode(vec)
  let secs = epochTime() - t0
  let want = readFile(dir / (sid & ".kkp"))
  var note = ""
  if mine != want:
    allOk = false
    let a = decode(mine)
    let b = decode(want)
    note = " paths " & $a.paths.len & "/" & $b.paths.len & " styles " & $a.styles.len & "/" & $b.styles.len &
           " size " & $a.width & "x" & $a.height & " vs " & $b.width & "x" & $b.height
    if a.styles != b.styles: note.add "  styles differ"
    var first = -1
    for i in 0 ..< min(a.paths.len, b.paths.len):
      if a.paths[i].style != b.paths[i].style or a.paths[i].bbox != b.paths[i].bbox or
         a.paths[i].cmdCount != b.paths[i].cmdCount:
        first = i
        break
    if first >= 0: note.add "  first path diff " & $first & ": " & $a.paths[first] & " vs " & $b.paths[first]
  # images: placement exact, pixels compared after decoding our JPEG XL
  let meta = parseStrict(readFile(dir / (sid & ".images.json")))
  let blob = readFile(dir / (sid & ".images.bin"))
  var off = 0
  var imgNote = ""
  if meta.len != d.images.len:
    imgNote = " images " & $d.images.len & " vs " & $meta.len
    allOk = false
  for i in 0 ..< min(meta.len, d.images.len):
    let r = meta[i]
    let rw = int(r["w"].i)
    let rh = int(r["h"].i)
    let want = blob[off ..< off + rw * rh * 4]
    off += rw * rh * 4
    let im = d.images[i]
    var placeOk = int64(r["after"].i) == int64(im.after)
    for k in 0 .. 3:
      if int64(r["rect"][k].i) != im.rect[k]: placeOk = false
    let (w, h, _, px) = decodeRgba(im.data)
    var maxd = 0
    var ndiff = 0
    if w == rw and h == rh:
      for j in 0 ..< w * h:
        var pd = 0
        for k in 0 .. 3: pd = max(pd, abs(int(px[j * 4 + k]) - int(want[j * 4 + k].uint8)))
        if pd > 0: inc ndiff
        maxd = max(maxd, pd)
    imgNote.add "\n    image " & $i & " " & $w & "×" & $h & ": placement " & (if placeOk: "same" else: "DIFFERENT") &
                (if w != rw or h != rh: ", size " & $rw & "×" & $rh & " in the reference" else: "") &
                ", pixels " & (if ndiff == 0: "identical" else: $ndiff & " differ (max " & $maxd & ")") &
                ", " & $im.data.len & " B JXL"
    if not placeOk or w != rw or h != rh: allOk = false
  echo sid.alignLeft(7), " ", (if mine == want: "IDENTICAL" else: "DIFFERENT"), " ", mine.len, " bytes, ",
       d.paths.len, " paths, ", formatFloat(secs, ffDecimal, 2), " s", note, imgNote
  doc.close()
quit(if allOk: 0 else: 1)
