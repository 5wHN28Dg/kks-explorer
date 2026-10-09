#!/bin/sh
# llvm-mingw (decisions 0047, 0053): clang + mingw-w64 + libc++ for Windows on x86_64 (x86_64-w64-mingw32) and ARM64
# (aarch64-w64-mingw32), run on this x86_64 Linux machine; UCRT, everything linked statically. Pinned release; the
# SHA-256 is the one GitHub publishes for the asset. Unpacked into ~/.local/kksdev/llvm-mingw.
set -eu
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
VER=20260922
NAME=llvm-mingw-$VER-ucrt-ubuntu-22.04-x86_64
SHA=bb7bb7654b33d5aa8712acb837c963b2e0c56352560c76105270a3268c665c21
[ -x "$DEV/llvm-mingw/bin/aarch64-w64-mingw32-clang" ] && [ -x "$DEV/llvm-mingw/bin/x86_64-w64-mingw32-clang" ] && grep -qx "$VER" "$DEV/llvm-mingw/VERSION.kks" 2>/dev/null && exit 0
mkdir -p "$DEV/src/dl"
f="$DEV/src/dl/$NAME.tar.xz"
[ -f "$f" ] || curl -sSfL -o "$f" "https://github.com/mstorsjo/llvm-mingw/releases/download/$VER/$NAME.tar.xz"
echo "$SHA  $f" | sha256sum -c --quiet || { rm -f "$f"; exit 1; }   # a broken download is fetched again next time
rm -rf "$DEV/llvm-mingw"; mkdir -p "$DEV/llvm-mingw"
tar xJf "$f" -C "$DEV/llvm-mingw" --strip-components=1
echo "$VER" > "$DEV/llvm-mingw/VERSION.kks"
echo "llvm-mingw $VER in $DEV/llvm-mingw"
