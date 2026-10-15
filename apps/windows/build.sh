#!/bin/sh
# Cross-build Walkdown for Windows (decisions 0033, 0053). Needs llvm-mingw and the libraries from
# platform/windows/build-deps.sh in ~/.local/kksdev. Output: $1 or /tmp/kkswin/Walkdown.exe
# KKS_WIN_ARCH=aarch64: Windows on ARM64 (decision 0047; libraries from build-deps.sh with the same variable); the
# default is x86_64
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="${1:-/tmp/kkswin/Walkdown.exe}"
NIM="${NIM:-$HOME/.nimble/bin/nim}"
sh "$HERE/../../platform/windows/fetch-llvm-mingw.sh"   # the pinned toolchain (exits at once when present)
if [ "${KKS_WIN_ARCH:-x86_64}" = aarch64 ]; then CPU=arm64; TRI=aarch64-w64-mingw32; SUF=-arm64
else CPU=amd64; TRI=x86_64-w64-mingw32; SUF=; fi
# the commit and whether the checkout has changed or new files it doesn't hold, as deploy/install-server-user.sh finds
# them: About says them and links that commit's source (platform/linux/src/kksl/buildinfo.nim). Only this
# repository's own checkout; a source tree without git builds as "commit unknown"
REPO=$(cd "$HERE/../.." && pwd)
COMMIT=$( [ -z "$(git -C "$REPO" rev-parse --show-prefix 2>/dev/null || echo no)" ] && git -C "$REPO" rev-parse --verify -q HEAD || true)
DIRTY=false; [ -z "$COMMIT" ] || [ -z "$(git -C "$REPO" status --porcelain -- .)" ] || DIRTY=true
"$NIM" c --os:windows -d:mingw --cpu:$CPU --cc:clang -d:release ${COMMIT:+-d:kksCommit="$COMMIT" -d:kksDirty="$DIRTY"} \
  --nimcache:"${KKS_WIN_CACHE:-/tmp/kkswin/cache-app$SUF}" -o:"$OUT" "$HERE/kks_explorer.nim"
ls -la "$OUT"
# the e2e tests' UI Automation driver (e2e/uiadrive.cpp), next to the app
"${KKS_DEV:-$HOME/.local/kksdev}/llvm-mingw/bin/$TRI-clang++" -O2 -static -municode -D_WIN32_WINNT=0x0A00 \
  -o "$(dirname "$OUT")/uiadrive.exe" "$HERE/e2e/uiadrive.cpp" -luiautomationcore -lole32 -loleaut32 -luuid -lgdi32
