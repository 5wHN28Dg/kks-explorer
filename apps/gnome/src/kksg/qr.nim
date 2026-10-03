## QR codes (R13, decision 0019): drawing an invite, reading one from a picture.
import gtk
{.compile: "kks_zxing.cpp".}
when defined(flatpak): {.passL: "-L/app/lib -lstdc++ -lZXing".}   # the zxing-cpp the manifest builds (3.1.1: libZXing.so.4)
else: {.passL: "-lstdc++ -l:libZXing.so.3".}            # the system's (no -dev symlink on the build machine)
proc kks_qr_encode(text: cstring, size: ptr cint): ptr UncheckedArray[byte] {.importc, cdecl.}
proc kks_qr_decode(gray: pointer, w, h: cint): cstring {.importc, cdecl.}
proc free(p: pointer) {.importc, header: "<stdlib.h>".}

proc qrTexture*(text: string, scale = 8, quiet = 4): W =
  ## the code as a crisp texture: `scale` px per module, a `quiet`-module white border
  var n: cint
  let m = kks_qr_encode(text.cstring, addr n)
  if m == nil: return nil
  let side = (int(n) + 2 * quiet) * scale
  var px = newSeq[byte](side * side * 3)
  for i in 0 ..< px.len: px[i] = 255
  for y in 0 ..< int(n):
    for x in 0 ..< int(n):
      if m[y * int(n) + x] == 1:
        for dy in 0 ..< scale:
          for dx in 0 ..< scale:
            let o = (((y + quiet) * scale + dy) * side + (x + quiet) * scale + dx) * 3
            px[o] = 0; px[o + 1] = 0; px[o + 2] = 0
  free(m)
  textureFromRgb(px, side, side)

proc qrFromGray*(gray: ptr UncheckedArray[byte], w, h: int): string =
  ## the text of a QR code in an 8-bit grey picture; "" when none
  let p = kks_qr_decode(gray, cint(w), cint(h))
  if p == nil: return ""
  result = $p
  free(p)

proc qrFromPicture*(path: string): string =
  ## the text of a QR code in a picture file; "" when none
  let (w, h, rgba) = loadImage(path)
  if w == 0: return ""
  var g = newSeq[byte](w * h)
  for i in 0 ..< w * h:
    g[i] = byte((int(rgba[i * 4]) * 299 + int(rgba[i * 4 + 1]) * 587 + int(rgba[i * 4 + 2]) * 114) div 1000)
  let p = kks_qr_decode(addr g[0], cint(w), cint(h))
  if p == nil: return ""
  result = $p
  free(p)
