# The toolchain for every Windows cross-build (decisions 0047, 0053): llvm-mingw's clang for x86_64 and ARM64, unpacked
# into ~/.local/kksdev/llvm-mingw by platform/windows/fetch-llvm-mingw.sh (build-deps.sh runs it). The libraries from
# build-deps.sh are in ~/.local/kksdev/winx64 or winarm64 (or $KKS_WIN64), linked statically.
# Included by the config.nims of core/, platform/linux/, platform/windows/ and apps/windows/; the target comes from
# the command line (--os:windows -d:mingw --cpu:amd64 or --cpu:arm64).
let winDev = getEnv("KKS_DEV", getEnv("HOME") & "/.local/kksdev")   # getHomeDir() follows the target OS here
let winTri = (when defined(arm64): "aarch64" else: "x86_64") & "-w64-mingw32"
when defined(mingw):
  let winKey = (when defined(arm64): "arm64" else: "amd64") & ".windows.clang."
  switch("cc", "clang")
  switch(winKey & "path", winDev & "/llvm-mingw/bin")
  switch(winKey & "exe", winTri & "-clang")
  switch(winKey & "linkerexe", winTri & "-clang++")      # C++ parts (Direct2D, libjxl, zxing-cpp)
  switch(winKey & "cpp.exe", winTri & "-clang++")
  switch(winKey & "cpp.linkerexe", winTri & "-clang++")
  # Windows 10 APIs (BCryptHash …) stated, not assumed. clang makes three diagnostics errors that gcc only warned
  # about: they are Nim's types for the same Windows types (a stdcall proc for WNDPROC, an int for MAKEINTRESOURCE,
  # uint32 for DWORD), the same size and ABI.
  switch("passC", "-D_WIN32_WINNT=0x0A00 -Wno-error=incompatible-function-pointer-types -Wno-error=int-conversion -Wno-error=incompatible-pointer-types")
  let winLibs = getEnv("KKS_WIN64", winDev & (when defined(arm64): "/winarm64" else: "/winx64"))
  switch("passC", "-I" & winLibs & "/include")
  switch("passL", "-L" & winLibs & "/lib -static")
