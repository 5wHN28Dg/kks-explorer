## Writes tests/web/dark-vectors.json: apps/common/darkcolor.nim's darkRgb on every grey and a 0..255 grid of colours
## (step 37), the expected values for dark.js (tests/web/test_dark.py).
##   nim r --hints:off tests/web/make_dark_vectors.nim > tests/web/dark-vectors.json
import std/strutils
import ../../apps/common/darkcolor

var lines: seq[string]
proc add(r, g, b: int) =
  let (dr, dg, db) = darkRgb(r, g, b)
  lines.add "[" & $r & "," & $g & "," & $b & "," & $dr & "," & $dg & "," & $db & "]"
for v in 0 .. 255: add(v, v, v)
for r in countup(0, 255, 37):
  for g in countup(0, 255, 37):
    for b in countup(0, 255, 37):
      if not (r == g and g == b): add(r, g, b)
for c in [(255, 0, 0), (0, 0, 255), (0, 0, 128), (10, 200, 30), (255, 128, 0), (0, 160, 0), (255, 7, 255), (1, 2, 254)]: add(c[0], c[1], c[2])
echo "{\"lo\": ", DarkLo, ", \"hi\": ", DarkHi, ", \"rgb\": [\n", lines.join(",\n"), "\n]}"
