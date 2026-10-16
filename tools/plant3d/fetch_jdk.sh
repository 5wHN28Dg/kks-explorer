#!/bin/sh
# The JDK Walkdown Plant's Android export builds with (decision 0056): Godot 4.7's Gradle template (Gradle 8.11.1,
# Android Gradle plugin 8.6.1) runs on JDK 17, and Gradle 8.11 doesn't run on the JDK 25 that Walkdown's own build
# uses. Eclipse Temurin 17, pinned by version and SHA-256 (from the Adoptium API's `checksum`, checked 2026-10-16).
# Puts it in $JDK_DIR (default ~/.local/kksdev/jdk-17) and prints its JAVA_HOME. Nothing system-wide.
set -eu
RELEASE=jdk-17.0.20.1+1
FILE=OpenJDK17U-jdk_x64_linux_hotspot_17.0.20.1_1.tar.gz
SHA256=3808d1d15e3ec6bd5b84057fb5d84c33d8a1536a258146bcea2e603fc726e08e
URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/$FILE"
DIR="${JDK_DIR:-$HOME/.local/kksdev/jdk-17}"
if [ ! -x "$DIR/bin/java" ] || [ "$(cat "$DIR/.release" 2>/dev/null)" != "$RELEASE" ]; then
  DL="$(mktemp -d "${TMPDIR:-/tmp}/jdk-dl.XXXXXX")"
  trap 'rm -rf "$DL"' EXIT
  curl -sSLf -o "$DL/$FILE" "$URL"
  echo "$SHA256  $DL/$FILE" | sha256sum -c - >/dev/null || { echo "checksum mismatch: $FILE" >&2; exit 1; }
  rm -rf "$DIR"
  mkdir -p "$DIR"
  tar -xzf "$DL/$FILE" -C "$DIR" --strip-components=1
  echo "$RELEASE" > "$DIR/.release"
fi
"$DIR/bin/java" -version 2>&1 | grep -q '"17\.' || { echo "unexpected JDK: $("$DIR/bin/java" -version 2>&1 | head -1)" >&2; exit 1; }
echo "$DIR"
