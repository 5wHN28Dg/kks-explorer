# KKS Explorer for Windows (decision 0033): always cross-built with mingw-w64 (nim c -d:mingw ...)
import std/os
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../common")
switch("path", thisDir() & "/../../core/src")
switch("path", thisDir() & "/../../platform/linux/src")
switch("path", thisDir() & "/../../platform/windows/src")
switch("hints", "off")
switch("warning", "UnusedImport:off")
# the target must come from the command line (build.sh: --os:windows -d:mingw --cpu:amd64): nim.cfg is read
# before this file, and with Linux as the target it adds -ldl
switch("app", "gui")
let kdev = getEnv("KKS_DEV", getEnv("HOME") & "/.local/kksdev")
# KKS_WIN_ARCH=aarch64: Windows on ARM64 with llvm-mingw's clang (decision 0047; build.sh passes --cpu:arm64 --cc:clang)
let arm = getEnv("KKS_WIN_ARCH", "x86_64") == "aarch64"
let bin = if arm: kdev & "/llvm-mingw/bin" else: getEnv("KKS_MINGW_BIN", kdev & "/mingw/usr/bin")
let tri = if arm: "aarch64-w64-mingw32" else: "x86_64-w64-mingw32"
if arm:
  # clang makes these errors by default; gcc 13 (the x86_64 build) warns. They are Nim's types for the same Windows
  # types (a stdcall proc for WNDPROC, an int for MAKEINTRESOURCE, uint32 for DWORD): the same size and ABI.
  switch("passC", "-Wno-error=incompatible-function-pointer-types -Wno-error=int-conversion -Wno-error=incompatible-pointer-types")
  switch("arm64.windows.clang.path", bin)
  switch("arm64.windows.clang.exe", tri & "-clang")
  switch("arm64.windows.clang.linkerexe", tri & "-clang++")
  switch("arm64.windows.clang.cpp.exe", tri & "-clang++")
  switch("arm64.windows.clang.cpp.linkerexe", tri & "-clang++")
else:
  switch("amd64.windows.gcc.path", bin)
  switch("amd64.windows.gcc.exe", tri & "-gcc")
  switch("amd64.windows.gcc.linkerexe", tri & "-g++")      # C++ parts (Direct2D, libjxl, zxing-cpp)
  switch("amd64.windows.gcc.cpp.exe", tri & "-g++")
  switch("amd64.windows.gcc.cpp.linkerexe", tri & "-g++")
let w64 = getEnv("KKS_WIN64", kdev & (if arm: "/winarm64" else: "/win64"))
switch("passC", "-I" & w64 & "/include -DJXL_STATIC_DEFINE -DJXL_THREADS_STATIC_DEFINE -DJXL_CMS_STATIC_DEFINE")
switch("passL", "-L" & w64 & "/lib -static")
switch("define", "kksBundledSqlite")
switch("define", "sqliteDir=" & kdev & "/src/sqlite-amalgamation-3530400")
# the manifest (common controls v6, per-monitor DPI, UTF-8) as a resource object
let res = getEnv("KKS_WIN_RES", "/tmp/kks-win-res-" & tri & ".o")   # getTempDir() follows the target OS here
exec bin & "/" & tri & "-windres " & thisDir() & "/res/kks.rc -O coff -o " & res & " --include-dir " & thisDir() & "/res"
switch("passL", res)
