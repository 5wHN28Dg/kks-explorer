import std/[os, strutils]
switch("path", thisDir() & "/src")
switch("hints", "off")
switch("warning", "UnusedImport:off")

task test, "build and run every tests/test_*.nim (release mode, needs GnuTLS and zlib headers)":
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      exec "nim c -r -d:release --outdir:" & getTempDir() & "kkscore " & f

# Windows builds cross-compiled with mingw-w64 (decision 0033): the toolchain unpacked into ~/.local/kksdev/mingw
# (or KKS_MINGW_BIN), zlib and other Windows libraries in ~/.local/kksdev/win64 (or KKS_WIN64), linked statically.
when defined(mingw):
  let kdev = getEnv("KKS_DEV", getEnv("HOME") & "/.local/kksdev")   # getHomeDir() follows the target OS here
  switch("amd64.windows.gcc.path", getEnv("KKS_MINGW_BIN", kdev & "/mingw/usr/bin"))
  let w64 = getEnv("KKS_WIN64", kdev & "/win64")
  switch("passC", "-I" & w64 & "/include")
  switch("passL", "-L" & w64 & "/lib -static")

task wintests, "cross-build every tests/test_*.nim for Windows (mingw-w64) into $KKS_WIN_OUT or /tmp/kkswin":
  let outd = getEnv("KKS_WIN_OUT", "/tmp/kkswin")
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      let n = f.extractFilename.changeFileExt("")
      exec "nim c -d:mingw -d:release --cpu:amd64 --nimcache:" & outd & "/cache-" & n & " -o:" & outd & "/" & n & ".exe " & f
