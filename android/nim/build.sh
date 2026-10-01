#!/bin/sh
# Build the core library for the Android app (decision 0032): arm64-v8a (phones) and x86_64 (the emulator), with the
# NDK's clang at API 29, SQLite compiled in. Output: android/app/src/main/jniLibs/<abi>/libkks.so
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
NDK="${ANDROID_NDK:-$HOME/Android/Sdk/ndk/27.2.12479018}"
BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
SQLITE="$DEV/src/sqlite-amalgamation-3530400"
[ -f "$SQLITE/sqlite3.c" ] || sh "$HERE/fetch_sqlite.sh"
NIM="${NIM:-$HOME/.nimble/bin/nim}"
for pair in arm64-v8a:arm64:aarch64 x86_64:amd64:x86_64; do
  abi=${pair%%:*}; rest=${pair#*:}; cpu=${rest%%:*}; triple=${rest#*:}
  out="$HERE/../app2/src/main/jniLibs/$abi"
  mkdir -p "$out"
  "$NIM" c --app:lib --os:android --cpu:$cpu --cc:clang \
    --clang.exe="$BIN/$triple-linux-android29-clang" --clang.linkerexe="$BIN/$triple-linux-android29-clang" \
    -d:release -d:kksBundledSqlite -d:sqliteDir="$SQLITE" --passL:"-llog -lz -Wl,-z,max-page-size=16384" \
    --nimcache:"$DEV/nimcache-android-$abi" -o:"$out/libkks.so" "$HERE/kks_jni.nim"
  echo "$abi: $(du -h "$out/libkks.so" | cut -f1)"
done
