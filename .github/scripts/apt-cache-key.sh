#!/bin/bash
# Before the apt archive cache is saved (.github/actions/apt-cache, mode save): keeps in DIR only the archives that
# apt-install.sh checked and used in this job (named in DIR/.used: copied in from the cache or stored after a
# download, each matching the SHA-256 the package lists give), deletes everything else, and prints the key suffix
# for what is left: the SHA-256 of its list of names and hashes, so that a cache is saved again only when its
# contents change. Prints nothing when nothing is left (nothing to save).
#   .github/scripts/apt-cache-key.sh DIR
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 DIR" >&2; exit 2; }
DIR=$1
[ -d "$DIR" ] || exit 0
declare -A used=()
if [ -f "$DIR/.used" ]; then
  while IFS= read -r f; do [ -n "$f" ] && used[$f]=1; done < "$DIR/.used"
fi
chmod -R u+w "$DIR" 2>/dev/null || true
shopt -s nullglob dotglob
for p in "$DIR"/*; do
  f=${p##*/}
  [ "$f" = .used ] && continue
  if [ ! -f "$p" ] || [ -z "${used[$f]:-}" ]; then rm -rf "$p"; fi
done
rm -f "$DIR/.used"
files=("$DIR"/*.deb)
[ ${#files[@]} -gt 0 ] || exit 0
(cd "$DIR" && sha256sum -- *.deb) | LC_ALL=C sort -k2 | sha256sum | cut -c1-32
