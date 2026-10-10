## Dark drawings on Windows: kks_d2d.cpp's kks_dark_rgb (the worker threads turn tiles and overview levels with it) is
## a copy of apps/common/darkcolor.nim darkRgb; it must give the same colour for every 8-bit RGB colour.
## Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it); runs on Windows:
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_dark.exe apps/windows/tests/test_dark.nim
import std/unittest
import ../../common/darkcolor

{.compile("../src/kkswin/kks_d2d.cpp", "-std=c++17").}
{.passL: "-ljxl -ljxl_cms -lhwy -lbrotlidec -lbrotlienc -lbrotlicommon -ljxl_threads -lstdc++ -ld2d1 -lwindowscodecs -lole32 -luuid".}

proc cDark(r, g, b: cint, outR, outG, outB: ptr cint) {.importc: "kks_dark_rgb", cdecl.}

suite "dark drawings on Windows":
  test "the C++ copy equals darkcolor.darkRgb on every colour":
    var bad = 0
    var first = ""
    for r in 0 .. 255:
      for g in 0 .. 255:
        for b in 0 .. 255:
          var cr, cg, cb: cint
          cDark(cint(r), cint(g), cint(b), addr cr, addr cg, addr cb)
          let (dr, dg, db) = darkRgb(r, g, b)
          if (int(cr), int(cg), int(cb)) != (dr, dg, db):
            if bad == 0: first = $(r, g, b) & ": " & $(cr, cg, cb) & " vs " & $(dr, dg, db)
            inc bad
    check bad == 0
    if bad > 0: echo "first difference ", first

  test "paper, ink and red markup":
    var r, g, b: cint
    cDark(255, 255, 255, addr r, addr g, addr b)
    check (r, g, b) == (cint(DarkLo), cint(DarkLo), cint(DarkLo))
    cDark(0, 0, 0, addr r, addr g, addr b)
    check (r, g, b) == (cint(DarkHi), cint(DarkHi), cint(DarkHi))
    cDark(255, 0, 0, addr r, addr g, addr b)
    check r > g and r > b
