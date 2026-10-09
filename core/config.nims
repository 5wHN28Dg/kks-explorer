import std/[os, strutils]
switch("path", thisDir() & "/src")
switch("hints", "off")
switch("warning", "UnusedImport:off")

task test, "build and run every tests/test_*.nim (release mode, needs GnuTLS and zlib headers)":
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      exec "nim c -r -d:release --outdir:" & getTempDir() & "kkscore " & f

# Windows builds cross-compiled with llvm-mingw (decisions 0033, 0053; the toolchain and its libraries: see there)
include "../platform/windows/toolchain.nims"

task wintests, "cross-build every tests/test_*.nim for Windows (llvm-mingw, x86_64) into $KKS_WIN_OUT or /tmp/kkswin":
  let outd = getEnv("KKS_WIN_OUT", "/tmp/kkswin")
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      let n = f.extractFilename.changeFileExt("")
      exec "nim c --os:windows -d:mingw -d:release --cpu:amd64 --cc:clang --nimcache:" & outd & "/cache-" & n & " -o:" & outd & "/" & n & ".exe " & f
