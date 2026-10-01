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
let bin = getEnv("KKS_MINGW_BIN", kdev & "/mingw/usr/bin")
switch("amd64.windows.gcc.path", bin)
switch("amd64.windows.gcc.exe", "x86_64-w64-mingw32-gcc")
switch("amd64.windows.gcc.linkerexe", "x86_64-w64-mingw32-g++")      # C++ parts (Direct2D, libjxl, zxing-cpp)
switch("amd64.windows.gcc.cpp.exe", "x86_64-w64-mingw32-g++")
switch("amd64.windows.gcc.cpp.linkerexe", "x86_64-w64-mingw32-g++")
let w64 = getEnv("KKS_WIN64", kdev & "/win64")
switch("passC", "-I" & w64 & "/include -DJXL_STATIC_DEFINE -DJXL_THREADS_STATIC_DEFINE -DJXL_CMS_STATIC_DEFINE")
switch("passL", "-L" & w64 & "/lib -static")
switch("define", "kksBundledSqlite")
switch("define", "sqliteDir=" & kdev & "/src/sqlite-amalgamation-3530400")
# the manifest (common controls v6, per-monitor DPI, UTF-8) as a resource object
let res = getEnv("KKS_WIN_RES", "/tmp/kks-win-res.o")   # getTempDir() follows the target OS here
exec bin & "/x86_64-w64-mingw32-windres " & thisDir() & "/res/kks.rc -O coff -o " & res & " --include-dir " & thisDir() & "/res"
switch("passL", res)
