## Dark drawings (a PDF reader's dark mode for the P&IDs): each colour's lightness is inverted while its hue stays, so
## black lines become near-white, the white paper near-black, and red markup stays red. Shared by the desktop apps;
## pure, no platform code.
##
## Inverting every channel (255 - c) turns HSL lightness L into 1 - L but also turns the hue by 180°; turning it back
## (c → max + min - c, which keeps L and S) gives the closed form c' = c + 255 - (max + min): exact in HSL, no
## conversion, cheap enough per pixel. The result is then squeezed into [DarkLo, DarkHi] (the same affine map on all
## three channels keeps the hue): white lands on the dark background, black on a soft white, not a glaring one.

const
  DarkLo* = 18         ## #121212: what white paper becomes (the dark background)
  DarkHi* = 237        ## what black lines become

  RaiseChroma* = 48    ## a colour at least this coloured (max - min) ...
  RaiseLight* = 306    ## ... and no lighter than this (max + min, i.e. HSL lightness 0.6): a line or markup colour
  RaiseY2* = 104_040_000 ## its gamma-2 luminance (2126 r² + 7152 g² + 722 b²) must reach this (0.16 of white:
                         ## gamma 2 overrates mid-tones a little, 0.14 left some at 2.98:1)

func darkByte(c, mx, mn: int): int {.inline.} =
  DarkLo + ((c + 255 - mx - mn) * (DarkHi - DarkLo) + 127) div 255

func darkRgb*(r, g, b: int): (int, int, int) =
  ## the dark-mode colour of an 8-bit RGB colour
  ##
  ## A saturated line colour keeps HSL lightness near 0.5 when inverted, so pure blue would stay dark blue on the dark
  ## background (about 2:1). Such colours (coloured enough, not lighter than 0.6: lines and markup, not light fills or
  ## greys) are mixed toward DarkHi in sixteenths until their luminance reaches 3:1 against #121212. Luminance with
  ## gamma 2 (c²) keeps it exact integer maths in every copy (dark.js, DarkColor.kt); the unit test checks the real
  ## WCAG ratio over a grid of colours.
  let mx = max(r, max(g, b))
  let mn = min(r, min(g, b))
  var dr = darkByte(r, mx, mn)
  var dg = darkByte(g, mx, mn)
  var db = darkByte(b, mx, mn)
  if mx - mn >= RaiseChroma and mx + mn <= RaiseLight:
    var k = 0
    while k < 16 and 2126 * dr * dr + 7152 * dg * dg + 722 * db * db < RaiseY2:
      inc k
      dr = darkByte(r, mx, mn) + (DarkHi - darkByte(r, mx, mn)) * k div 16
      dg = darkByte(g, mx, mn) + (DarkHi - darkByte(g, mx, mn)) * k div 16
      db = darkByte(b, mx, mn) + (DarkHi - darkByte(b, mx, mn)) * k div 16
  (dr, dg, db)

func darkRgbF*(r, g, b: float): (float, float, float) =
  ## the same for Cairo's 0..1 colours (rounded through 8 bits, so tiles and the overview agree)
  let (dr, dg, db) = darkRgb(int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5))
  (float(dr) / 255, float(dg) / 255, float(db) / 255)

proc darkenPixels*(px: var openArray[byte], channels: int) =
  ## in place over packed RGB (channels = 3) or RGBA (channels = 4, straight alpha, alpha untouched)
  var i = 0
  while i + 2 < px.len:
    let (dr, dg, db) = darkRgb(int(px[i]), int(px[i + 1]), int(px[i + 2]))
    px[i] = byte(dr)
    px[i + 1] = byte(dg)
    px[i + 2] = byte(db)
    i += channels

func lightenForDark*(r, g, b: float, amount = 0.35): (float, float, float) =
  ## a marker colour (tag outlines, selection) raised toward white so it stays readable on the dark background
  (r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount)
