#!/bin/sh
# The Godot the bench is measured with, pinned by version and SHA-512 (from the release's SHA512-SUMS.txt on
# https://github.com/godotengine/godot/releases/tag/4.7.2-stable, checked 2026-10-15: 4.7.2 is the newest stable).
# Puts the editor in $GODOT_DIR (default ~/.local/kksdev/godot) and the export templates where the editor looks for
# them. Prints the editor's path. GODOT_TEMPLATES="android_release.apk …" unpacks only those templates (CI's cache). Downloads go to their own empty folder and are checked before anything is unpacked.
set -eu
VERSION=4.7.2
EDITOR_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
TEMPLATES_SHA512=ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079
DIR="${GODOT_DIR:-$HOME/.local/kksdev/godot}"
TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION.stable"
URL="https://github.com/godotengine/godot/releases/download/$VERSION-stable"
EDITOR="$DIR/Godot_v$VERSION-stable_linux.x86_64"
DL="$(mktemp -d "${TMPDIR:-/tmp}/godot-dl.XXXXXX")"
trap 'rm -rf "$DL"' EXIT
mkdir -p "$DIR"
get() {  # file sha512
  curl -sSLf -o "$DL/$1" "$URL/$1"
  echo "$2  $DL/$1" | sha512sum -c - >/dev/null || { echo "checksum mismatch: $1" >&2; exit 1; }
}
if [ ! -x "$EDITOR" ]; then
  get "Godot_v$VERSION-stable_linux.x86_64.zip" "$EDITOR_SHA512"
  unzip -oq "$DL/Godot_v$VERSION-stable_linux.x86_64.zip" -d "$DIR"
fi
WANT="${GODOT_TEMPLATES:-android_release.apk linux_release.x86_64}"
missing=""
for t in $WANT; do [ -f "$TPL/$t" ] || missing=1; done
if [ -n "$missing" ]; then
  get "Godot_v$VERSION-stable_export_templates.tpz" "$TEMPLATES_SHA512"
  mkdir -p "$TPL"
  if [ -n "${GODOT_TEMPLATES:-}" ]; then
    # shellcheck disable=SC2046
    unzip -oqj "$DL/Godot_v$VERSION-stable_export_templates.tpz" $(for t in $GODOT_TEMPLATES version.txt; do echo "templates/$t"; done) -d "$TPL"
  else
    unzip -oqj "$DL/Godot_v$VERSION-stable_export_templates.tpz" -d "$TPL"
  fi
fi
"$EDITOR" --version | grep -q "^$VERSION.stable" || { echo "unexpected editor version: $("$EDITOR" --version)" >&2; exit 1; }
echo "$EDITOR"
