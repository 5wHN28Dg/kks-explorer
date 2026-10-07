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

func darkByte(c, mx, mn: int): int {.inline.} =
  DarkLo + ((c + 255 - mx - mn) * (DarkHi - DarkLo) + 127) div 255

func darkRgb*(r, g, b: int): (int, int, int) =
  ## the dark-mode colour of an 8-bit RGB colour
  let mx = max(r, max(g, b))
  let mn = min(r, min(g, b))
  (darkByte(r, mx, mn), darkByte(g, mx, mn), darkByte(b, mx, mn))

func darkRgbF*(r, g, b: float): (float, float, float) =
  ## the same for Cairo's 0..1 colours (rounded through 8 bits, so tiles and the overview agree)
  let (dr, dg, db) = darkRgb(int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5))
  (float(dr) / 255, float(dg) / 255, float(db) / 255)

proc darkenPixels*(px: var openArray[byte], channels: int) =
  ## in place over packed RGB (channels = 3) or RGBA (channels = 4, straight alpha, alpha untouched)
  var i = 0
  while i + 2 < px.len:
    let r = int(px[i])
    let g = int(px[i + 1])
    let b = int(px[i + 2])
    let mx = max(r, max(g, b))
    let mn = min(r, min(g, b))
    px[i] = byte(darkByte(r, mx, mn))
    px[i + 1] = byte(darkByte(g, mx, mn))
    px[i + 2] = byte(darkByte(b, mx, mn))
    i += channels

func lightenForDark*(r, g, b: float, amount = 0.35): (float, float, float) =
  ## a marker colour (tag outlines, selection) raised toward white so it stays readable on the dark background
  (r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount)
