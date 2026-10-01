## The 0026 gate, run locally on plant data: the Nim importer against the Python importer's trace
## (tests/dump_cells.py) on every sheet: orientation scores, every glyph and read in call order, and the tags.
##   diff_trace REFDIR GLYPHLIB.kgl [SHEET...]
import std/[os, strutils, times, sequtils]
import kks/json
import kksi/[mupdf, imgops, fontlib, reader, textlines, extract]
import sha256util

proc shapeHash(w, h: int, data: openArray[uint8]): string =
  var s = "(" & $h & ", " & $w & ")"
  for v in data: s.add char(v)
  sha256hex(s)[0 ..< 16]

proc bitsHash(b: Bits): string =
  var d = newSeq[uint8](b.d.len)
  for i, v in b.d: d[i] = uint8(v)
  shapeHash(b.w, b.h, d)

proc tagJson(t: Tag): JNode =
  result = newObj()
  result["id"] = newStr(t.id)
  result["orient"] = newStr($t.orient)
  result["bbox"] = newArr(t.bbox.mapIt(newFloat(it)))
  result["top"] = newStr(t.top)
  result["bottom"] = newStr(t.bottom)
  result["conf"] = newFloat(t.conf)
  result["kind"] = newStr(t.interp.kind)
  result["kks"] = (if t.interp.hasKks: newStr(t.interp.kks) else: newNull())
  result["suffix"] = (if t.interp.hasKks: newStr(t.interp.suffix) else: newNull())
  result["isa"] = (if t.interp.hasIsa and not t.interp.isaNull: newStr(t.interp.isa) else: newNull())
  result["note"] = (if t.interp.note.len > 0: newStr(t.interp.note) else: newNull())
  result["status"] = newStr(t.status)
  result["flag"] = (if t.flag.len > 0: newStr(t.flag) else: newNull())

proc pyTag(t: JNode): JNode =
  ## the Python tag dict in tagJson's shape and key order (missing keys → null, ids as strings)
  result = newObj()
  result["id"] = newStr(if t["id"].kind == jInt: $t["id"].i else: t["id"].s)
  result["orient"] = t["orient"]
  result["bbox"] = newArr(t["bbox"].elems.mapIt(newFloat(it.num)))
  result["top"] = t["top"]
  result["bottom"] = t["bottom"]
  result["conf"] = newFloat(t["conf"].num)
  result["kind"] = t["kind"]
  for k in ["kks", "suffix", "isa", "note", "status", "flag"]:
    result[k] = (if t.has(k) and t[k].kind != jNull: t[k] else: newNull())
  if result["kks"].kind == jNull: result["suffix"] = newNull()

let dir = paramStr(1)
init()
var r = Reader(lib: loadGlyphLib(paramStr(2)))
let only = commandLineParams()[2 .. ^1]
let man = parseStrict(readFile(dir / "manifest.json"))
var allOk = true
for s in man.elems:
  let sid = s["id"].s
  if only.len > 0 and sid notin only: continue
  var want: seq[JNode]
  for l in lines(dir / (sid & ".trace.jsonl")):
    if l.len > 0: want.add parseStrict(l, 4096)
  var got: seq[(string, string, string, float, seq[int], seq[float32])]   # (e, hash/label, hash2, conf, top, sim)
  let t0 = epochTime()
  for rot in [0, 90, 180, 270]:
    let d = rotatedCopy(s["src"].s, rot)
    let (h, v) = score(loadPaths(d))
    got.add(("score", $h, $v, float(rot), @[], @[]))
    d.close()
  r.trace.onGlyph = proc (sub: Bits, hc: int, g: Glyph) =
    got.add(("glyph", g.label, bitsHash(sub) & "/" & $hc, g.conf, g.top, g.sim))
  r.trace.onRead = proc (im, mask: imgops.Gray, s: string, c: float) =
    got.add(("read", s, shapeHash(im.w, im.h, im.d) & "/" & shapeHash(mask.w, mask.h, mask.d), c, @[], @[]))
  let doc = rotatedCopy(s["src"].s, int(s["rot"].i))
  let tags = r.extract(doc, loadPaths(doc))
  let secs = epochTime() - t0
  # compare the event streams
  var firstDiff = ""
  var nGlyph, nRead, badGlyph, badRead, badSim, nScore, badScore = 0
  var maxSimDiff = 0.0
  let wantEv = want.filterIt(it["e"].s != "tags")
  if wantEv.len != got.len: firstDiff = "events " & $got.len & " vs " & $wantEv.len
  for i in 0 ..< min(wantEv.len, got.len):
    let w = wantEv[i]
    let g = got[i]
    if w["e"].s != g[0]:
      if firstDiff.len == 0: firstDiff = "event " & $i & ": " & g[0] & " vs " & w["e"].s
      break
    case g[0]
    of "score":
      inc nScore
      if $w["h"].i != g[1] or $w["v"].i != g[2]:
        inc badScore
        if firstDiff.len == 0: firstDiff = "score rot " & $g[3] & ": " & g[1] & "/" & g[2] & " vs " & $w["h"].i & "/" & $w["v"].i
    of "glyph":
      inc nGlyph
      let wantSub = w["sub"].s & "/" & $w["hc"].i
      var simSame = true
      for j in 0 ..< min(5, g[5].len):
        let d = abs(float(g[5][j]) - w["sim"][j].num)
        maxSimDiff = max(maxSimDiff, d)
        if d != 0:
          simSame = false
          if existsEnv("KKS_SIMDEBUG"): echo "    sim diff at library row ", g[4][j], " (python top ", w["top"][j].i, ")"
      if not simSame: inc badSim
      if g[1] != w["l"].s or g[2] != wantSub or abs(g[3] - w["c"].num) > 1e-12:
        inc badGlyph
        if firstDiff.len == 0:
          firstDiff = "glyph " & $i & ": " & g[1] & " " & g[2] & " " & $g[3] & " vs " & w["l"].s & " " & wantSub & " " & $w["c"].num
    of "read":
      inc nRead
      let wantH = w["im"].s & "/" & w["mask"].s
      if g[1] != w["s"].s or g[2] != wantH or abs(g[3] - w["c"].num) > 1e-12:
        inc badRead
        if firstDiff.len == 0:
          firstDiff = "read " & $i & ": '" & g[1] & "' " & g[2] & " " & $g[3] & " vs '" & w["s"].s & "' " & wantH & " " & $w["c"].num
  # tags
  let wantTags = want.filterIt(it["e"].s == "tags")[0]["tags"]
  var badTags = 0
  if wantTags.len != tags.len: badTags = abs(wantTags.len - tags.len)
  for i in 0 ..< min(wantTags.len, tags.len):
    let a = toText(tagJson(tags[i]))
    let b = toText(pyTag(wantTags[i]))
    if a != b:
      inc badTags
      if badTags <= 3: echo "  tag ", i, ":\n    nim ", a, "\n    py  ", b
  let ok = firstDiff.len == 0 and badTags == 0 and badSim == 0
  if not ok: allOk = false
  echo sid.alignLeft(7), " ", (if ok: "IDENTICAL" else: "DIFFERENT"), "  tags ", tags.len, "/", wantTags.len,
       " (", badTags, " differ)  reads ", nRead, " (", badRead, ")  glyphs ", nGlyph, " (", badGlyph, ", sims ", badSim,
       " max ", maxSimDiff, ")  scores ", nScore - badScore, "/", nScore, "  ", formatFloat(secs, ffDecimal, 1), " s",
       (if firstDiff.len > 0: "\n    first: " & firstDiff else: "")
quit(if allOk: 0 else: 1)
