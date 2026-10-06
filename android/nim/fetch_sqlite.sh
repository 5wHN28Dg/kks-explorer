#!/bin/sh
# The SQLite amalgamation the Android core compiles in (decision 0032), pinned by SHA3-256 from sqlite.org/download.html
# (checked 2026-10-01). The amalgamation is listed in pinned-sources.cdx.json (DEP-8): change it there too when a pin changes.
set -eu
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
VER=3530400
SHA3=628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e
mkdir -p "$DEV/src" && cd "$DEV/src"
[ -f sqlite-amalgamation-$VER.zip ] || curl -sSLO "https://sqlite.org/2026/sqlite-amalgamation-$VER.zip"
python3 -c "import hashlib,sys; d=open('sqlite-amalgamation-$VER.zip','rb').read(); sys.exit(hashlib.sha3_256(d).hexdigest()!='$SHA3')"
[ -d sqlite-amalgamation-$VER ] || unzip -q sqlite-amalgamation-$VER.zip
echo "SQLite in $DEV/src/sqlite-amalgamation-$VER"
