import std/[os, strutils]
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../core/src")
switch("hints", "off")
let dev = getEnv("KKS_DEV", getHomeDir() & ".local/kksdev")
let mu = dev & "/src/mupdf-1.28.2-source"
switch("passC", "-I" & mu & "/include")
switch("passL", mu & "/build/release/libmupdf.a " & mu & "/build/release/libmupdf-third.a -lm -lpthread")

task test, "build and run every tests/test_*.nim":
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      exec "nim c -r -d:release --outdir:" & getTempDir() & "kksimp " & f
