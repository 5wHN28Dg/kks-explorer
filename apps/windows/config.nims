# KKS Explorer for Windows (decisions 0033, 0053): always cross-built with llvm-mingw (nim c -d:mingw ...)
import std/os
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../common")
switch("path", thisDir() & "/../../core/src")
switch("path", thisDir() & "/../../platform/linux/src")
switch("path", thisDir() & "/../../platform/windows/src")
switch("hints", "off")
# stack traces in release builds too: a crash in the field names its line (appstate crash.txt → diagnostics); they
# cost nothing measurable in tile rendering (b1ms 4.02 s vs 4.05 s, 2026-10-05), the binary grows 4 → 6.7 MB
switch("stackTrace", "on")
switch("lineTrace", "on")
switch("warning", "UnusedImport:off")
# the target must come from the command line (build.sh: --os:windows -d:mingw --cpu:amd64 --cc:clang): nim.cfg is read
# before this file, and with Linux as the target it adds -ldl
switch("app", "gui")
include "../../platform/windows/toolchain.nims"   # llvm-mingw for x86_64 and ARM64 (decisions 0047, 0053)
switch("passC", "-DJXL_STATIC_DEFINE -DJXL_THREADS_STATIC_DEFINE -DJXL_CMS_STATIC_DEFINE")
switch("define", "kksBundledSqlite")
switch("define", "sqliteDir=" & winDev & "/src/sqlite-amalgamation-3530400")
# the manifest (common controls v6, per-monitor DPI, UTF-8) as a resource object
let res = getEnv("KKS_WIN_RES", "/tmp/kks-win-res-" & winTri & ".o")   # getTempDir() follows the target OS here
exec winDev & "/llvm-mingw/bin/" & winTri & "-windres " & thisDir() & "/res/kks.rc -O coff -o " & res & " --include-dir " & thisDir() & "/res"
switch("passL", res)
