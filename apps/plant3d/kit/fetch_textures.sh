#!/bin/sh
# The parts kit's textures (decision 0054 §5): CC0 PBR sets from ambientCG (https://ambientcg.com, "all assets are
# CC0"), 2K JPG, pinned by SHA-256, never committed. Each download goes to its own empty folder and is checked before
# anything is unpacked; only the maps the kit uses are taken (kit/materials.gd SETS). Then the three texture tiers:
#   kit/tex/2048/  VRAM-compressed (S3TC on the desktops, ETC2 on phones) with mipmaps: the laptops' tier
#   kit/tex/1024/  the same at most 1024 px: the phones' tier (decision 0041), and what the built materials name
#   kit/tex/512/   the same at most 512 px: kept for a heavier plant (0054)
# The same source files (hard links) are imported three ways: one asset set, three sizes.
# Downloads are kept in $KIT_TEX_CACHE (default ~/.cache/walkdown-plant/textures) and checked again on every run.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
CACHE="${KIT_TEX_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/walkdown-plant/textures}"
mkdir -p "$CACHE" "$HERE/tex/src"
while read -r sha name maps; do
  z="$CACHE/$name.zip"
  if [ ! -f "$z" ] || ! echo "$sha  $z" | sha256sum -c - >/dev/null 2>&1; then
    d=$(mktemp -d "$CACHE/dl.XXXXXX")
    curl -sSLf -o "$d/$name.zip" "https://ambientcg.com/get?file=${name}_2K-JPG.zip"
    echo "$sha  $d/$name.zip" | sha256sum -c - >/dev/null || { rm -rf "$d"; echo "checksum mismatch: $name" >&2; exit 1; }
    mv "$d/$name.zip" "$z"
    rmdir "$d"
  fi
  for m in $maps; do
    f="$HERE/tex/src/${name}_$m.jpg"
    [ -f "$f" ] || unzip -ojq "$z" "${name}_2K-JPG_$m.jpg" -d "$HERE/tex/src"
    [ -f "$f" ] || mv "$HERE/tex/src/${name}_2K-JPG_$m.jpg" "$f"
  done
done <<LIST
2ebc9feab92e00aa026d538b5ad068d573258eb4509245efb67eb29583d574fa PaintedMetal004 NormalGL Roughness
4b8884843c490963d5734be036c35639d064e7a817eb61145322f69c6c19895a Metal032 Color NormalGL Roughness
6f79f53d5073e65707c5765316fa9257f4604e1790093be5a51ed8226761a7f0 Metal009 Color NormalGL Roughness
9bec057d9db923cdf2208c0cc5b41e4df2072237c951ef4a4e22db0830a2a00a CorrugatedSteel005 Color NormalGL Roughness
fafd7cd3aee2b703abbb12b7810ef565ab76ac7ea3b1ea9a73b088e423e670b3 Concrete034 Color NormalGL Roughness
72d7440ebe251e42804022632987c56b3a1fc30614fa506a298524870ae2246a MetalWalkway010 Color NormalGL Roughness
0c7afb58ec80b3d46af307099451e1bc71c643c7b2ba2d45c7d69663d8d3f909 DiamondPlate008C Color NormalGL Roughness
a6dd0aea7bcda95d6373c823734eda0cfa066e34c0eea9e1e07023926021bab5 Gravel023 Color NormalGL Roughness
f2a02ea9ea1fd97d2a6d27f46ebac069a5851e3ae7c73fa991abf563b97786c7 Asphalt031 Color NormalGL Roughness
LIST
# the source maps are not resources of the project (Godot would import a fourth copy): .gdignore
touch "$HERE/tex/src/.gdignore"
for size in 2048 1024 512; do
  mkdir -p "$HERE/tex/$size"
  limit=$size; [ "$size" = 2048 ] && limit=0
  for f in "$HERE/tex/src/"*.jpg; do
    n=$(basename "$f")
    [ -f "$HERE/tex/$size/$n" ] || ln "$f" "$HERE/tex/$size/$n" 2>/dev/null || cp -p "$f" "$HERE/tex/$size/$n"
    normal=0
    case "$n" in *_NormalGL.jpg) normal=1 ;; esac
    want="[remap]

importer=\"texture\"
type=\"CompressedTexture2D\"

[params]

compress/mode=2
compress/high_quality=false
compress/normal_map=$normal
mipmaps/generate=true
process/size_limit=$limit
detect_3d/compress_to=0
"
    # rewritten only when the settings differ, so Godot keeps what it imported before
    grep -q "^process/size_limit=$limit\$" "$HERE/tex/$size/$n.import" 2>/dev/null &&
      grep -q "^compress/normal_map=$normal\$" "$HERE/tex/$size/$n.import" || printf '%s' "$want" > "$HERE/tex/$size/$n.import"
  done
done
echo "textures: $(ls "$HERE/tex/src/"*.jpg | wc -l) maps, 3 tiers"
