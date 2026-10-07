# TEMP (CI diagnosis, to be removed): where resizeArea differs from cv2's vector on this CPU
import std/[os, base64, strutils]
import kks/[json, gz]
import kksi/imgops
const Dir = currentSourcePath().parentDir
proc floats(s: string): seq[float32] =
  result = newSeq[float32](s.len div 4)
  if s.len > 0: copyMem(addr result[0], unsafeAddr s[0], s.len)
let cases = parseStrict(gunzip(readFile(Dir / "vectors" / "cv2-ops.json.gz"), 64 shl 20), 4096)
var n, bad = 0
for c in cases.elems:
  if c["op"].s != "resize": continue
  inc n
  let src = FImg(w: int(c["w"].i), h: int(c["h"].i), d: floats(decode(c["src"].s)))
  let got = resizeArea(src, int(c["dw"].i), 32).d
  let want = floats(decode(c["out"].s))
  var first = -1
  var cnt = 0
  for i in 0 ..< min(got.len, want.len):
    if cast[uint32](got[i]) != cast[uint32](want[i]):
      inc cnt
      if first < 0: first = i
  if cnt > 0 or got.len != want.len:
    inc bad
    if bad <= 6:
      echo "case ", n, " w=", src.w, " h=", src.h, " dw=", c["dw"].i, " lens ", got.len, "/", want.len, " diffs ", cnt,
        " first ", first, (if first >= 0: " got " & toHex(cast[uint32](got[first])) & " want " & toHex(cast[uint32](want[first])) else: "")
echo "resize cases ", n, " bad ", bad
