#!/bin/bash
# apt-get install for the CI jobs (every workflow), every phase bounded in time.
#
# Why (2026-10-26): the gnome-e2e job ran into its 40-minute limit three times in one morning, on main and on a PR,
# each time silent inside `apt-get install ... >/dev/null` right after `apt-get update` had finished; in python
# shard 0 the same silent install of ffmpeg took 21 minutes and the job then ran out of its 30. The same installs
# normally take 1 to 3 minutes, and a slow one took 15. apt's own timeout (Acquire::http::Timeout) only ends a
# connection that sends nothing at all, so a trickling one held the job.
#
# So: the index update and the package download each run under `timeout` and are tried again (a download that is
# tried again keeps the packages it has and resumes the partial one), and only then are the packages installed from
# the local cache, once, also under a time limit. Every phase's output is shown in a collapsed group, so a stall is
# visible in the log. Nothing is skipped: any phase that fails every attempt fails the step.
#
# What the logs then showed (2026-10-26: gnome-e2e, python shard 0, web firefox and chromium): every attempt of the
# download ran its whole 240 s against azure.archive.ubuntu.com at 10 to 60 kB/s, some making no progress at all, so
# three attempts on the same mirror were not enough. Hence, on top:
# - Another mirror after a failed attempt. GitHub's runners read their Ubuntu mirrors from a list
#   (/etc/apt/apt-mirrors.txt, `mirror+file:` in the sources; Azure's mirror first, then archive.ubuntu.com, then
#   security.ubuntu.com). apt goes to the next one in that list only when a mirror answers with an error, never when
#   it is slow; so after a failed attempt the first mirror goes to the end of the list, and the next attempt starts
#   with another (never with one named security.ubuntu.com, which carries only the -security pockets). The package
#   lists stay valid: apt files them under the list's name, not the mirror's. The order that worked is kept for the
#   job's later calls. Without that file (another machine) nothing changes.
# - A pause between attempts that doubles (APT_BACKOFF_SECS, then twice that, ...).
# - A cache of the downloaded archives across runs (APT_DEB_CACHE, a folder the workflow restores and saves with
#   actions/cache through .github/actions/apt-cache). The archives the install needs are asked of apt first
#   (`--print-uris`, with the SHA-256 the signed package lists give each); a cached file is copied in only when its
#   SHA-256 is that one (apt itself takes any file of the right size), and after every download attempt the needed
#   archives that arrived whole and match go into the folder and are named in its `.used`, so even a failed run
#   leaves what it got to the next. A cached archive with another hash is deleted, never used.
#
#   .github/scripts/apt-install.sh PACKAGE...
# The limits can be set for the test (tests/test_apt_install.py): APT_TRIES, APT_UPDATE_SECS, APT_DOWNLOAD_SECS,
# APT_INSTALL_SECS, APT_BACKOFF_SECS; APT_MIRROR_LIST (the mirror list), APT_ARCHIVES (apt's archive folder, else
# asked of apt-config). APT_SKIP_UPDATE=1 skips the index update, for a call right after another that made it
# (playwright-deps.sh). The defaults add up to at most 27 minutes (21 without the update); where that is more than a
# job's own limit (server-http, 20; web, which calls this twice), the job's limit ends it first: still bounded.
# Playwright's browser packages come through here too (playwright-deps.sh), not `playwright install --with-deps`.
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: $0 PACKAGE..." >&2; exit 2; }
TRIES=${APT_TRIES:-3}
UPDATE_SECS=${APT_UPDATE_SECS:-120}
DOWNLOAD_SECS=${APT_DOWNLOAD_SECS:-240}
INSTALL_SECS=${APT_INSTALL_SECS:-480}
BACKOFF_SECS=${APT_BACKOFF_SECS:-10}
MIRRORS=${APT_MIRROR_LIST:-/etc/apt/apt-mirrors.txt}
DEB_CACHE=${APT_DEB_CACHE:-}
APT=(apt-get -q -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Dpkg::Use-Pty=0
     -o DPkg::Lock::Timeout=60)

# after a failed attempt: the list's first mirror to the end (and on past any security.ubuntu.com one), the
# priorities numbered again in the new order; nothing when there is no list or only one mirror
next_mirror() {
  [ -f "$MIRRORS" ] || return 0
  local new
  new=$(awk '
    /^[ \t]*(#|$)/ { next }
    { line[n++] = $0 }
    END {
      if (n < 2) exit
      for (s = 1; s < n; s++) if (line[s] !~ /security\.ubuntu\.com/) break
      if (s == n) s = 1
      for (i = 0; i < n; i++) {
        l = line[(s + i) % n]
        sub(/priority:[0-9]+/, "priority:" (i + 1), l)
        print l
      }
    }' "$MIRRORS")
  [ -n "$new" ] || return 0
  if sudo tee "$MIRRORS" >/dev/null <<<"$new"; then
    echo "apt: the next attempt starts with mirror $(head -1 <<<"$new" | cut -f1)"
  else
    echo "::warning::apt: could not reorder $MIRRORS; the next attempt uses the same mirror"
  fi
}

# run "$@" as root under a time limit; TRIES attempts (another mirror and a longer pause before each) when $1 is
# "retry", one when it is "once"; the function named in $AFTER (if any) runs after every attempt
phase() {
  local mode=$1 what=$2 secs=$3 tries=1 i t0 code; shift 3
  [ "$mode" = retry ] && tries=$TRIES
  for ((i = 1; i <= tries; i++)); do
    if [ "$i" -gt 1 ]; then
      next_mirror
      sleep $((BACKOFF_SECS << (i - 2)))
    fi
    t0=$SECONDS
    echo "::group::apt: $what (attempt $i of $tries, at most ${secs}s)"
    code=0; sudo timeout -k 15 "$secs" env DEBIAN_FRONTEND=noninteractive "$@" || code=$?
    echo "::endgroup::"
    # (the cache is a help: its failure is a warning, never the step's failure)
    [ -z "${AFTER:-}" ] || "$AFTER" || echo "::warning::apt cache: storing the archives failed"
    if [ $code -eq 0 ]; then
      echo "apt: $what took $((SECONDS - t0))s"; return 0
    fi
    echo "::warning::apt: $what failed or ran over ${secs}s (attempt $i of $tries, $((SECONDS - t0))s)"
  done
  echo "::error::apt: $what failed $tries time(s)"
  return 1
}

# --- the archive cache (APT_DEB_CACHE) ---
NEED=()    # "file sha256" of each archive this install needs, from the signed package lists
ARCHIVES=
sha_of() { sha256sum "$1" | cut -d' ' -f1; }

# what the install needs; the cached archives among it that match, copied into apt's archive folder
plan_cache() {
  local out line e f h hit=0 bytes=0 re="^'[^']+' ([A-Za-z0-9][A-Za-z0-9.+~%_-]*\.deb) [0-9]+ SHA256:([0-9a-f]{64})$"
  ARCHIVES=${APT_ARCHIVES:-}
  [ -n "$ARCHIVES" ] || eval "$(apt-config shell ARCHIVES Dir::Cache::archives/d)"
  [ -d "$ARCHIVES" ] || { echo "::warning::apt: no archive folder ($ARCHIVES); the cache is not used"; return 0; }
  mkdir -p "$DEB_CACHE"
  if ! out=$(sudo timeout 120 "${APT[@]}" -qq -o Acquire::ForceHash=SHA256 --print-uris install -y \
             --no-install-recommends "$@"); then
    echo "::warning::apt: could not list the archives to install; the cache is not used this time"
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [[ $line =~ $re ]]; then NEED+=("${BASH_REMATCH[1]} ${BASH_REMATCH[2]}")
    else echo "apt cache: not cached (no SHA-256, or a name it does not take): $line"; fi
  done <<<"$out"
  for e in "${NEED[@]}"; do
    f=${e%% *}; h=${e#* }
    [ -f "$DEB_CACHE/$f" ] || continue
    if [ "$(sha_of "$DEB_CACHE/$f")" = "$h" ]; then
      if sudo cp "$DEB_CACHE/$f" "$ARCHIVES/$f"; then
        echo "$f" >> "$DEB_CACHE/.used"
        hit=$((hit + 1)); bytes=$((bytes + $(stat -c %s "$DEB_CACHE/$f")))
      else
        echo "::warning::apt cache: could not copy $f into $ARCHIVES; it is downloaded"
      fi
    else
      echo "::warning::apt cache: $f is not the archive the package lists name (SHA-256): deleted, downloaded again"
      rm -f "$DEB_CACHE/$f"
    fi
  done
  echo "apt cache: ${#NEED[@]} archive(s) needed, $hit from the cache ($((bytes / 1024)) KiB)"
}

# after each download attempt: the needed archives that arrived whole and are the ones the lists name, into the cache
store_cache() {
  local e f h added=0
  for e in "${NEED[@]}"; do
    f=${e%% *}; h=${e#* }
    if [ ! -f "$DEB_CACHE/$f" ] && [ -f "$ARCHIVES/$f" ] && [ "$(sha_of "$ARCHIVES/$f")" = "$h" ]; then
      rm -rf "$DEB_CACHE/$f.part"   # (never written through: a .part could be a link)
      cp "$ARCHIVES/$f" "$DEB_CACHE/$f.part" && mv "$DEB_CACHE/$f.part" "$DEB_CACHE/$f"
      echo "$f" >> "$DEB_CACHE/.used"
      added=$((added + 1))
    fi
  done
  echo "apt cache: $added archive(s) added"
}

AFTER=
[ "${APT_SKIP_UPDATE:-}" = 1 ] || phase retry "update the package lists" "$UPDATE_SECS" "${APT[@]}" update
if [ -n "$DEB_CACHE" ]; then
  plan_cache "$@"
  [ ${#NEED[@]} -eq 0 ] || AFTER=store_cache
fi
phase retry "download $*" "$DOWNLOAD_SECS" "${APT[@]}" install -y --no-install-recommends --download-only "$@"
AFTER=
phase once "install $*" "$INSTALL_SECS" "${APT[@]}" install -y --no-install-recommends "$@"
