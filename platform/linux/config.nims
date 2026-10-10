import std/[os, strutils]
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../../core/src")
switch("hints", "off")
switch("warning", "UnusedImport:off")

task test, "build and run every tests/test_*.nim":
  for f in listFiles(thisDir() & "/tests"):
    if f.extractFilename.startsWith("test_") and f.endsWith(".nim"):
      exec "nim c -r -d:release --outdir:" & getTempDir() & "kkslinux " & f

# Windows builds (decisions 0033, 0053): llvm-mingw from ~/.local/kksdev, SQLite compiled in, the Windows layer on the path
include "../windows/toolchain.nims"
when defined(mingw):
  switch("path", thisDir() & "/../windows/src")
  switch("define", "kksBundledSqlite")
  switch("define", "sqliteDir=" & winDev & "/src/sqlite-amalgamation-3530400")

task wintests, "cross-build the tests that apply to Windows into $KKS_WIN_OUT or /tmp/kkswin":
  let outd = getEnv("KKS_WIN_OUT", "/tmp/kkswin")
  for n in ["test_dbstore", "test_tls", "test_net", "test_internet"]:
    exec "nim c --os:windows -d:mingw -d:release --cpu:amd64 --cc:clang --nimcache:" & outd & "/cache-" & n & " -o:" & outd & "/" & n & ".exe " & thisDir() & "/tests/" & n & ".nim"
  exec "nim c --os:windows -d:mingw -d:release --cpu:amd64 --cc:clang --nimcache:" & outd & "/cache-winplat -o:" & outd & "/test_winplat.exe " & thisDir() & "/../windows/tests/test_winplat.nim"
