#!/bin/sh
# Cross-build KKS Explorer for Windows (decision 0033). Needs the mingw-w64 toolchain and the libraries from
# platform/windows/build-deps.sh in ~/.local/kksdev. Output: $1 or /tmp/kkswin/KKSExplorer.exe
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="${1:-/tmp/kkswin/KKSExplorer.exe}"
NIM="${NIM:-$HOME/.nimble/bin/nim}"
"$NIM" c --os:windows -d:mingw --cpu:amd64 -d:release --nimcache:"${KKS_WIN_CACHE:-/tmp/kkswin/cache-app}" -o:"$OUT" "$HERE/kks_explorer.nim"
ls -la "$OUT"
