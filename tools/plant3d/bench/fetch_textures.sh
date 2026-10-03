#!/bin/sh
# The bench's textures: CC0 PBR sets from ambientCG (https://ambientcg.com, "all assets are CC0"), 2K JPG, pinned by
# SHA-256. Not committed (about 100 MB); this puts the maps the bench uses into tex/.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DL="${TMPDIR:-/tmp}/kks-bench-textures"
mkdir -p "$DL" "$HERE/tex"
while read -r sha name; do
  z="$DL/$name.zip"
  [ -f "$z" ] || curl -sSLf -o "$z" "https://ambientcg.com/get?file=${name}_2K-JPG.zip"
  echo "$sha  $z" | sha256sum -c - >/dev/null || { echo "checksum mismatch: $name"; exit 1; }
  for m in Color NormalGL Roughness Metalness AmbientOcclusion Opacity; do
    unzip -ojq "$z" "${name}_2K-JPG_$m.jpg" -d "$HERE/tex" 2>/dev/null || true
  done
done <<LIST
2c3f766c7401cee514fd88530cf22cdf846d1491c8fb590000a9345aee75553c PaintedMetal009
4b8884843c490963d5734be036c35639d064e7a817eb61145322f69c6c19895a Metal032
fafd7cd3aee2b703abbb12b7810ef565ab76ac7ea3b1ea9a73b088e423e670b3 Concrete034
18dc289f6212817c51fcbcd74ea55ebf9d76cd89b85ad44978be72b1458d9124 MetalPlates006
ae84d10fa03530c4fbd64e0767bd6ac14c642d2b232d5c40870ddc59d43ec950 Grate001
LIST
ls "$HERE/tex" | wc -l
