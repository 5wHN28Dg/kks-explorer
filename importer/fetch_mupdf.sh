#!/bin/sh
# Fetch and build MuPDF 1.28.2 (the version PyMuPDF 1.28.2 bundles: same rendering = same glyph images, decision 0026)
# into $KKS_DEV (default ~/.local/kksdev). Pinned by SHA-256 from https://mupdf.com/releases (checked 2026-10-01).
set -eu
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
VER=1.28.2
SHA=44075a84e329db55b9bef5f342a70fd26d69e48ad1d33cb89d9664581c641156
mkdir -p "$DEV/src" && cd "$DEV/src"
[ -f mupdf-$VER-source.tar.gz ] || curl -sSLO "https://mupdf.com/downloads/archive/mupdf-$VER-source.tar.gz"
echo "$SHA  mupdf-$VER-source.tar.gz" | sha256sum -c -
[ -d mupdf-$VER-source ] || tar xzf mupdf-$VER-source.tar.gz
cd mupdf-$VER-source
make HAVE_X11=no HAVE_GLUT=no HAVE_CURL=no HAVE_LIBCRYPTO=no build=release libs -j"$(nproc)"
echo "MuPDF $VER built in $DEV/src/mupdf-$VER-source/build/release"
