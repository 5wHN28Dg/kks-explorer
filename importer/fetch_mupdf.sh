#!/bin/sh
# Fetch and build MuPDF 1.28.5 into $KKS_DEV (default ~/.local/kksdev). Pinned by SHA-256 from
# https://mupdf.com/releases (checked 2026-10-08). 1.28.2 was the version PyMuPDF 1.28.2 bundles (decision 0026);
# 1.28.3-1.28.5 fix memory-safety bugs found by fuzzing (#51) and read the same tags on every sheet (importer/README.md).
# KKS_JOBS: parallel make jobs (default: all cores).
set -eu
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
VER=1.28.5
SHA=98a5c10cda20c3992cdf76ff6b2a1149c32bd79cc796d3f703230b1185b7e934
mkdir -p "$DEV/src" && cd "$DEV/src"
[ -f mupdf-$VER-source.tar.gz ] || curl -sSLO "https://mupdf.com/downloads/archive/mupdf-$VER-source.tar.gz"
echo "$SHA  mupdf-$VER-source.tar.gz" | sha256sum -c -
[ -d mupdf-$VER-source ] || tar xzf mupdf-$VER-source.tar.gz
cd mupdf-$VER-source
make HAVE_X11=no HAVE_GLUT=no HAVE_CURL=no HAVE_LIBCRYPTO=no build=release libs -j"${KKS_JOBS:-$(nproc)}"
echo "MuPDF $VER built in $DEV/src/mupdf-$VER-source/build/release"
