# Windows platform layer (decision 0033): always cross-built with mingw-w64 from ~/.local/kksdev
import std/os
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../linux/src")
switch("path", thisDir() & "/../../core/src")
switch("hints", "off")
switch("warning", "UnusedImport:off")
when defined(mingw):
  let kdev = getEnv("KKS_DEV", getEnv("HOME") & "/.local/kksdev")
  # KKS_WIN_ARCH=aarch64 (with --cpu:arm64 --cc:clang): Windows on ARM64 with llvm-mingw (decision 0047)
  let arm = getEnv("KKS_WIN_ARCH", "x86_64") == "aarch64"
  if arm:
    let bin = kdev & "/llvm-mingw/bin"
    # Windows 10 APIs (BCryptHash …): mingw-w64's gcc assumes them, llvm-mingw's clang does not
    switch("passC", "-D_WIN32_WINNT=0x0A00 -Wno-error=incompatible-function-pointer-types -Wno-error=int-conversion -Wno-error=incompatible-pointer-types")
    switch("arm64.windows.clang.path", bin)
    switch("arm64.windows.clang.exe", "aarch64-w64-mingw32-clang")
    switch("arm64.windows.clang.linkerexe", "aarch64-w64-mingw32-clang++")
  else:
    switch("amd64.windows.gcc.path", getEnv("KKS_MINGW_BIN", kdev & "/mingw/usr/bin"))
  let w64 = getEnv("KKS_WIN64", kdev & (if arm: "/winarm64" else: "/win64"))
  switch("passC", "-I" & w64 & "/include")
  switch("passL", "-L" & w64 & "/lib -static")
  switch("define", "kksBundledSqlite")
  switch("define", "sqliteDir=" & kdev & "/src/sqlite-amalgamation-3530400")
