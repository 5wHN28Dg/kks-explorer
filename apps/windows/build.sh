#!/bin/sh
# Cross-build Walkdown for Windows (decision 0033). Needs the mingw-w64 toolchain and the libraries from
# platform/windows/build-deps.sh in ~/.local/kksdev. Output: $1 or /tmp/kkswin/Walkdown.exe
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="${1:-/tmp/kkswin/Walkdown.exe}"
NIM="${NIM:-$HOME/.nimble/bin/nim}"
# KKS_WIN_ARCH=aarch64: Windows on ARM64 (decision 0047; libraries from platform/windows/build-deps.sh with the same
# variable); the default is x86_64
if [ "${KKS_WIN_ARCH:-x86_64}" = aarch64 ]; then
  sh "$HERE/../../platform/windows/fetch-llvm-mingw.sh"
  "$NIM" c --os:windows -d:mingw --cpu:arm64 --cc:clang -d:release --nimcache:"${KKS_WIN_CACHE:-/tmp/kkswin/cache-app-arm64}" -o:"$OUT" "$HERE/kks_explorer.nim"
  ls -la "$OUT"
  CXX="$HOME/.local/kksdev/llvm-mingw/bin/aarch64-w64-mingw32-clang++"
else
  "$NIM" c --os:windows -d:mingw --cpu:amd64 -d:release --nimcache:"${KKS_WIN_CACHE:-/tmp/kkswin/cache-app}" -o:"$OUT" "$HERE/kks_explorer.nim"
  ls -la "$OUT"
  CXX="${KKS_MINGW_BIN:-$HOME/.local/kksdev/mingw/usr/bin}/x86_64-w64-mingw32-g++-posix"
fi
# the e2e tests' UI Automation driver (e2e/uiadrive.cpp), next to the app
"$CXX" -O2 -static -municode -D_WIN32_WINNT=0x0A00 -o "$(dirname "$OUT")/uiadrive.exe" "$HERE/e2e/uiadrive.cpp" -luiautomationcore -lole32 -loleaut32 -luuid
