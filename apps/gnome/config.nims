import std/[os, strutils]
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../common")   # appstate.nim, shared with the Windows app
switch("path", thisDir() & "/../../core/src")
switch("path", thisDir() & "/../../platform/linux/src")
switch("path", thisDir() & "/../../importer/src")
switch("hints", "off")
let dev = getEnv("KKS_DEV", getHomeDir() & ".local/kksdev")
putEnv("PKG_CONFIG_PATH", dev & "/root/usr/lib/x86_64-linux-gnu/pkgconfig:" & dev & "/root/usr/share/pkgconfig:" &
       getEnv("PKG_CONFIG_PATH"))
switch("passC", staticExec("pkg-config --cflags libadwaita-1 libsecret-1"))
switch("passL", staticExec("pkg-config --libs libadwaita-1 libsecret-1"))

task test, "build and run every tests/test_*.nim":
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      exec "nim c -r -d:release --outdir:" & getTempDir() & "kksgnome " & f
