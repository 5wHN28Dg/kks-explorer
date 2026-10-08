## The Windows app's JPEG XL decoding (kks_d2d.cpp) refuses pictures bigger than 100 MP before allocating (#37): a
## header that claims 100000 x 100000 px (40 GB of pixels) is refused; a real picture still decodes.
## Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it); runs on Windows:
##   nim c --os:windows -d:mingw --cpu:amd64 -d:release --app:console -o:test_jxl_limit.exe apps/windows/tests/test_jxl_limit.nim
import std/[unittest, strutils]

{.compile("../src/kkswin/kks_d2d.cpp", "-std=c++17").}
{.passL: "-ljxl -ljxl_cms -lhwy -lbrotlidec -lbrotlienc -lbrotlicommon -ljxl_threads -lstdc++ -ld2d1 -lwindowscodecs -lole32 -luuid".}

proc jxlDecode(data: pointer, n: csize_t, w, h: ptr cint): pointer {.importc: "kks_jxl_decode", cdecl.}
proc cfree(p: pointer) {.importc: "kks_free", cdecl.}

const
  # a JPEG XL codestream header: SizeHeader 100000 x 100000, default image metadata, then nothing
  Huge = "\xff\x0a\xfc\x34\x0c\x7e\x1a\x16" & repeat('\0', 16)
  Picture = staticRead("../../../data/courses/ppt-07.jxl")   # a course picture

proc decode(s: string): (pointer, int, int) =
  var w, h: cint
  let p = jxlDecode(unsafeAddr s[0], csize_t(s.len), addr w, addr h)
  (p, int(w), int(h))

suite "JPEG XL decoding on Windows":
  test "a picture over 100 MP is refused before anything is allocated":
    let (p, _, _) = decode(Huge)
    check p == nil

  test "a real picture decodes":
    let (p, w, h) = decode(Picture)
    check p != nil
    check w > 0 and h > 0 and w * h <= 100_000_000
    cfree(p)
