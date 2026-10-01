## Differential check against dump_ref.py output (local; plant data): rotated copy + renders + drawings, exact.
import std/[os, strutils, times]
import kks/json
import kksi/mupdf

let dir = paramStr(1)
init()
let man = parseStrict(readFile(dir / "manifest.json"))
var allOk = true
for s in man.elems:
  let sid = s["id"].s
  let t0 = epochTime()
  let doc = rotatedCopy(s["src"].s, int(s["rot"].i))
  let (w, h) = doc.pageSize
  var notes: seq[string]
  if abs(float(w) - s["page"][0].num) > 1e-3 or abs(float(h) - s["page"][1].num) > 1e-3: notes.add "page size " & $w & "x" & $h
  let det = doc.renderGray(200.0 / 72.0, minLineWidth = 0.5)
  let want = readFile(dir / (sid & ".det.gray"))
  if det.w != int(s["det"][0].i) or det.h != int(s["det"][1].i): notes.add "det size " & $det.w & "x" & $det.h
  else:
    var diff = 0
    for i in 0 ..< want.len:
      if det.data[i] != byte(want[i]): inc diff
    if diff > 0: notes.add "det pixels differ: " & $diff
  for k, c in s["clips"].elems:
    let r = c["rect"]
    let g = doc.renderGray(600.0 / 72.0, (r[0].num, r[1].num, r[2].num, r[3].num), hasClip = true)
    let wantc = readFile(dir / (sid & ".clip" & $k & ".gray"))
    if g.w != int(c["w"].i) or g.h != int(c["h"].i) or g.x != int(c["x"].i) or g.y != int(c["y"].i):
      notes.add "clip" & $k & " box " & $g.w & "x" & $g.h & "@" & $g.x & "," & $g.y
    else:
      var diff = 0
      for i in 0 ..< wantc.len:
        if g.data[i] != byte(wantc[i]): inc diff
      if diff > 0: notes.add "clip" & $k & " differs: " & $diff
  # drawings, filtered like extractor/glyphs.load_paths
  var mine: seq[(int, array[4, float32], seq[array[4, float32]])]
  for p in doc.drawings:
    if p.hasFill: continue
    let rw = p.rect[2] - p.rect[0]
    let rh = p.rect[3] - p.rect[1]
    if max(rw, rh) > 14: continue
    var segs: seq[array[4, float32]]
    var ok = true
    for it in p.items:
      if it.cmd == 'l': segs.add [float32(it.p[0]), float32(it.p[1]), float32(it.p[2]), float32(it.p[3])]
      else: ok = false
    if ok and segs.len > 0: mine.add((p.seqno, p.rect, segs))
  let ref0 = parseStrict(readFile(dir / (sid & ".paths.json")))
  if mine.len != ref0.len: notes.add "paths " & $mine.len & " vs " & $ref0.len
  else:
    var bad = 0
    for i, (sq, r, segs) in mine:
      let rp = ref0[i]
      if rp[0].i != sq: inc bad
      elif segs.len != rp[2].len: inc bad
      else:
        for k in 0 .. 3:
          if float(r[k]) != rp[1][k].num: inc bad
        for j, sg in segs:
          for k in 0 .. 3:
            if float(sg[k]) != rp[2][j][k].num: inc bad
    if bad > 0: notes.add "paths differ: " & $bad
  doc.close()
  echo sid.alignLeft(7), (if notes.len == 0: "identical" else: notes.join("; ")), "  (", int((epochTime() - t0) * 1000), " ms)"
  if notes.len > 0: allOk = false
quit(if allOk: 0 else: 1)
