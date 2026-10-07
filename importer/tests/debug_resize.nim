# TEMP (CI diagnosis, to be removed): where resizeArea differs from cv2's vector on this CPU
import std/[os, base64, strutils]
import kks/[json, gz]
import kksi/imgops
proc mxcsr(): uint32 =
  var v: uint32
  {.emit: "__asm__ volatile(\"stmxcsr %0\" : \"=m\"(`v`));".}
  v
echo "mxcsr ", toHex(mxcsr())
proc fmaf(a, b, c: cfloat): cfloat {.importc, header: "<math.h>".}
block:
  # the textbook cases: is a float32 multiply-add rounded the same here?
  let a = 0.1'f32
  let b = 0.7'f32
  let c = 0.3'f32
  var x = a * b
  x = x + c
  echo "mul+add ", toHex(cast[uint32](x)), " fma ", toHex(cast[uint32](fmaf(a, b, c))), " div ", toHex(cast[uint32](1'f32 / 3'f32))
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
for c in cases.elems:
  if c["op"].s == "resize" and c["w"].i == 4 and c["h"].i == 44:
    let src = FImg(w: 4, h: 44, d: floats(decode(c["src"].s)))
    var line = "src"
    for v in src.d[0 ..< 24]: line.add " " & toHex(cast[uint32](v))
    echo line
    let got = resizeArea(src, 3, 32).d
    line = "out"
    for v in got[0 ..< 24]: line.add " " & toHex(cast[uint32](v))
    echo line
