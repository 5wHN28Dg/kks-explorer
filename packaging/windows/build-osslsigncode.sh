#!/bin/sh
# osslsigncode (signs the MSIX here, so the key never leaves this machine; make-msix.sh), built from the release tag's
# source pinned by SHA-256 (codeload.github.com, tag 2.14 = commit 65a4c40460ea81a10c4df3e609edc4634a52b51f; checked
# 2026-10-08). 2.14 has the APPX parsing fixes that Ubuntu's 2.13 lacks (#53). Needs cmake, a C compiler and the
# OpenSSL 3 and zlib headers (with OpenSSL 3 it needs no curl). Output: ~/.local/kksdev/osslsigncode/bin.
set -eu
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
VER=2.14
SHA=0f033fd6069387d2e489fbd2187e62f624764eb8c2758ee94e3e793e5150b5c5
BIN="$DEV/osslsigncode/bin/osslsigncode"
[ -x "$BIN" ] && "$BIN" --version 2>/dev/null | head -1 | grep -q "^osslsigncode $VER[ ,]" && exit 0
mkdir -p "$DEV/src/dl"
f="$DEV/src/dl/osslsigncode-$VER.tar.gz"
[ -f "$f" ] && echo "$SHA  $f" | sha256sum -c --quiet 2>/dev/null ||
  curl -sSfL -o "$f" "https://codeload.github.com/mtrojnar/osslsigncode/tar.gz/refs/tags/$VER"
echo "$SHA  $f" | sha256sum -c --quiet || { rm -f "$f"; exit 1; }
S="$DEV/src/osslsigncode-$VER"
rm -rf "$S"; mkdir -p "$S"; tar xzf "$f" -C "$S" --strip-components=1
cmake -S "$S" -B "$S/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$S/build" -j2 >/dev/null
install -Dm755 "$S/build/osslsigncode" "$BIN"   # (cmake --install would also write a bash completion under /usr)
"$BIN" --version | head -1
