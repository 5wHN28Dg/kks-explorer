import std/[os, strutils]
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../core/src")
switch("hints", "off")
let dev = getEnv("KKS_DEV", getHomeDir() & ".local/kksdev")
let mu = dev & "/src/mupdf-1.28.5-source"
switch("passC", "-I" & mu & "/include")
# Never let the C compiler fuse a multiply and an add on its own: the reader matches OpenCV and numpy bit for bit,
# and fuses exactly where they do, with explicit fmaf (imgops.gaussian3, kks_dot.c). Left to the compiler, the same
# gcc fused resizeArea's sums on GitHub's runner and not on the maintainer's laptop (1 ulp, 101 of 120 test cases).
switch("passC", "-ffp-contract=off")
switch("passL", mu & "/build/release/libmupdf.a " & mu & "/build/release/libmupdf-third.a -lm -lpthread")

task test, "build and run every tests/test_*.nim":
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      exec "nim c -r -d:release --outdir:" & getTempDir() & "kksimp " & f
