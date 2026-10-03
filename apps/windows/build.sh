#!/bin/sh
# Cross-build KKS Explorer for Windows (decision 0033). Needs the mingw-w64 toolchain and the libraries from
# platform/windows/build-deps.sh in ~/.local/kksdev. Output: $1 or /tmp/kkswin/Walkdown.exe
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="${1:-/tmp/kkswin/Walkdown.exe}"
NIM="${NIM:-$HOME/.nimble/bin/nim}"
"$NIM" c --os:windows -d:mingw --cpu:amd64 -d:release --nimcache:"${KKS_WIN_CACHE:-/tmp/kkswin/cache-app}" -o:"$OUT" "$HERE/kks_explorer.nim"
ls -la "$OUT"
# the e2e tests' UI Automation driver (e2e/uiadrive.cpp), next to the app
MINGW="${KKS_MINGW_BIN:-$HOME/.local/kksdev/mingw/usr/bin}"
"$MINGW/x86_64-w64-mingw32-g++-posix" -O2 -static -municode -o "$(dirname "$OUT")/uiadrive.exe" "$HERE/e2e/uiadrive.cpp" \
  -luiautomationcore -lole32 -loleaut32 -luuid
