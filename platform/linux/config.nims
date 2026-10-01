import std/[os, strutils]
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../../core/src")
switch("hints", "off")
switch("warning", "UnusedImport:off")

task test, "build and run every tests/test_*.nim":
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      exec "nim c -r -d:release --outdir:" & getTempDir() & "kkslinux " & f

# Windows builds (decision 0033): mingw-w64 from ~/.local/kksdev, SQLite compiled in, the Windows layer on the path
when defined(mingw):
  switch("path", thisDir() & "/../windows/src")
  let kdev = getEnv("KKS_DEV", getEnv("HOME") & "/.local/kksdev")
  switch("amd64.windows.gcc.path", getEnv("KKS_MINGW_BIN", kdev & "/mingw/usr/bin"))
  let w64 = getEnv("KKS_WIN64", kdev & "/win64")
  switch("passC", "-I" & w64 & "/include")
  switch("passL", "-L" & w64 & "/lib -static")
  switch("define", "kksBundledSqlite")
  switch("define", "sqliteDir=" & kdev & "/src/sqlite-amalgamation-3530400")

task wintests, "cross-build the tests that apply to Windows into $KKS_WIN_OUT or /tmp/kkswin":
  let outd = getEnv("KKS_WIN_OUT", "/tmp/kkswin")
  for n in ["test_dbstore", "test_tls", "test_net"]:
    exec "nim c -d:mingw -d:release --cpu:amd64 --nimcache:" & outd & "/cache-" & n & " -o:" & outd & "/" & n & ".exe " & thisDir() & "/tests/" & n & ".nim"
  exec "nim c -d:mingw -d:release --cpu:amd64 --nimcache:" & outd & "/cache-winplat -o:" & outd & "/test_winplat.exe " & thisDir() & "/../windows/tests/test_winplat.nim"
