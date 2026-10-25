#!/bin/sh
# Checks the committed KayKit files (people/kaykit/, decision 0063) against their source: KayKit - Character
# Animations 1.1 by Kay Lousberg (CC0 1.0: its License.txt, committed beside them), the archive pinned by SHA-256.
# itch.io gives no stable download link: this script asks the page for the free download as a browser does (no
# account), checks the archive's SHA-256 before anything is unpacked, and compares every committed file with the
# archive's copy byte for byte. The build never runs it (the files are committed: CI never depends on itch.io);
# run it after changing the pins in kaykit/SOURCE.json, or to show where the files come from.
#   apps/plant3d/people/fetch_kaykit.sh            fetch (into $KAYKIT_CACHE) and compare
#   apps/plant3d/people/fetch_kaykit.sh ZIP        compare with an archive already downloaded
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/kaykit/SOURCE.json"
val() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$SRC" "$1"; }
PAGE=$(val page); SHA=$(val archive_sha256); NAME=$(val archive); PREFIX=$(val prefix)
CACHE="${KAYKIT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/walkdown-plant/kaykit}"
mkdir -p "$CACHE"
Z="${1:-$CACHE/$NAME}"
if [ ! -f "$Z" ] || ! echo "$SHA  $Z" | sha256sum -c - >/dev/null 2>&1; then
  [ $# -eq 0 ] || { echo "$Z: not the pinned archive (SHA-256 $SHA)" >&2; exit 1; }
  d=$(mktemp -d "$CACHE/dl.XXXXXX")
  trap 'rm -rf "$d"' EXIT
  A="Mozilla/5.0"; J="$d/cookies"
  csrf() { grep -o 'name="csrf_token" value="[^"]*"' "$1" | head -1 | sed 's/.*value="//;s/"$//'; }
  curl -sSLf -c "$J" -b "$J" -A "$A" -o "$d/page.html" "$PAGE"
  U=$(curl -sSLf -c "$J" -b "$J" -A "$A" -X POST --data-urlencode "csrf_token=$(csrf "$d/page.html")" "$PAGE/download_url" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["url"])')
  curl -sSLf -c "$J" -b "$J" -A "$A" -o "$d/download.html" "$U"
  UP=$(val upload_id)
  F=$(curl -sSLf -c "$J" -b "$J" -A "$A" -X POST --data-urlencode "csrf_token=$(csrf "$d/download.html")" \
      "$PAGE/file/$UP?source=game_download&after_download_lightbox=1&as_props=1" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["url"])')
  curl -sSLf -A "$A" -o "$d/$NAME" "$F"
  echo "$SHA  $d/$NAME" | sha256sum -c - >/dev/null || { echo "checksum mismatch: $NAME (not KayKit 1.1 as pinned)" >&2; exit 1; }
  mv "$d/$NAME" "$CACHE/$NAME"
  Z="$CACHE/$NAME"
fi
python3 -I - "$SRC" "$Z" "$HERE/kaykit" <<'PY'
import hashlib, json, os, sys, zipfile
src, z, d = sys.argv[1:4]
s = json.load(open(src))
bad = 0
with zipfile.ZipFile(z) as zf:
    for f in s['files']:
        a = zf.read(s['prefix'] + f['member'])
        c = open(os.path.join(d, f['file']), 'rb').read()
        ok = a == c and hashlib.sha256(c).hexdigest() == f['sha256']
        print(('same ' if ok else 'DIFFERS ') + f['file'])
        bad += not ok
sys.exit(1 if bad else 0)
PY
echo "kaykit: every committed file is the pinned archive's"
