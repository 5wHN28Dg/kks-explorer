## Dark drawings: the colour transform (apps/common/darkcolor.nim) and the marker colours' contrast on dark.
import std/[unittest, math]
import darkcolor
import kksg/viewer

proc hsl(r, g, b: int): (float, float, float) =
  ## hue in degrees, saturation and lightness in 0..1
  let (rf, gf, bf) = (r / 255, g / 255, b / 255)
  let mx = max(rf, max(gf, bf))
  let mn = min(rf, min(gf, bf))
  let l = (mx + mn) / 2
  let d = mx - mn
  if d == 0: return (0.0, 0.0, l)
  let s = d / (1 - abs(2 * l - 1))
  var h = if mx == rf: (gf - bf) / d mod 6 elif mx == gf: (bf - rf) / d + 2 else: (rf - gf) / d + 4
  h = h * 60
  if h < 0: h += 360
  (h, s, l)

proc lum(r, g, b: float): float =
  proc ch(c: float): float = (if c <= 0.03928: c / 12.92 else: pow((c + 0.055) / 1.055, 2.4))
  0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)

proc contrast(a, b: (float, float, float)): float =
  let la = lum(a[0], a[1], a[2])
  let lb = lum(b[0], b[1], b[2])
  (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

suite "dark drawings colour":
  test "black becomes light, white becomes the dark background":
    check darkRgb(0, 0, 0) == (DarkHi, DarkHi, DarkHi)
    check darkRgb(255, 255, 255) == (DarkLo, DarkLo, DarkLo)
    check DarkHi >= 220 and DarkLo <= 24

  test "greys invert and stay grey, in order":
    var last = 256
    for g in countup(0, 255, 5):
      let (r, gg, b) = darkRgb(g, g, g)
      check r == gg and gg == b
      check r < last
      last = r
    check darkRgb(128, 128, 128)[0] in 125 .. 131      # mid grey stays mid grey

  test "pure colours keep their hue and stay saturated":
    for (c, hue) in [((255, 0, 0), 0.0), ((0, 0, 255), 240.0), ((0, 160, 0), 120.0), ((255, 128, 0), 30.0)]:
      let (r, g, b) = darkRgb(c[0], c[1], c[2])
      let (h0, _, l0) = hsl(c[0], c[1], c[2])
      let (h1, s1, l1) = hsl(r, g, b)
      check abs(h1 - hue) < 2.0
      check abs(h1 - h0) < 2.0
      check s1 > (if c[1] == 0 and (c[0] == 0 or c[2] == 0): 0.8 else: 0.7)
      check abs((l1 - DarkLo / 255) / ((DarkHi - DarkLo) / 255) - (1 - l0)) < 0.01   # lightness inverted
    check darkRgb(255, 0, 0) == (DarkHi, DarkLo, DarkLo)

  test "dark colours become light with the same hue":
    let (r, g, b) = darkRgb(0, 0, 128)                 # navy → light blue
    check b > r and r == g and hsl(r, g, b)[2] > 0.6

  test "the buffer form matches the pure function":
    var px = @[0'u8, 0, 0, 255, 255, 255, 255, 7, 255, 0, 0, 128, 10, 200, 30, 0]
    darkenPixels(px, 4)
    check (int(px[0]), int(px[1]), int(px[2])) == darkRgb(0, 0, 0)
    check px[3] == 255 and px[7] == 7 and px[11] == 128 and px[15] == 0  # alpha untouched
    check (int(px[4]), int(px[5]), int(px[6])) == darkRgb(255, 255, 255)
    check (int(px[12]), int(px[13]), int(px[14])) == darkRgb(10, 200, 30)
    var rgb = @[10'u8, 200, 30, 255, 0, 0]
    darkenPixels(rgb, 3)
    check (int(rgb[3]), int(rgb[4]), int(rgb[5])) == darkRgb(255, 0, 0)

  test "the 0..1 form rounds through 8 bits":
    let (r, g, b) = darkRgbF(1, 0, 0)
    check abs(r - DarkHi / 255) < 1e-9 and abs(g - DarkLo / 255) < 1e-9 and abs(b - DarkLo / 255) < 1e-9

suite "markers on dark":
  test "every tag and coverage colour reaches 3:1 against the dark sheet (WCAG non-text contrast)":
    let bg = (DarkLo / 255, DarkLo / 255, DarkLo / 255)
    for st in ["auto", "verified", "review", "pending"]:
      let c = markerColor(st, "", false, true)
      check contrast(c, bg) >= 3.0
    for ph in ["both", "equipment", "plate", "none"]:
      let c = markerColor("auto", ph, true, true)
      check contrast(c, bg) >= 3.0
    # light mode unchanged
    check markerColor("auto", "", false, false) == (0.1, 0.4, 0.9)
