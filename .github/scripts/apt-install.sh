#!/bin/bash
# apt-get install for the CI jobs (every workflow), every phase bounded in time.
#
# Why (2026-10-26): the gnome-e2e job ran into its 40-minute limit three times in one morning, on main and on a PR,
# each time silent inside `apt-get install ... >/dev/null` right after `apt-get update` had finished; in python
# shard 0 the same silent install of ffmpeg took 21 minutes and the job then ran out of its 30. The same installs
# normally take 1 to 3 minutes, and a slow one took 15. The output was hidden, so where it hung is not proven; the
# varying times point to the runner's Ubuntu mirror stalling the download. apt's own timeout
# (Acquire::http::Timeout) only ends a connection that sends nothing at all, so a trickling one held the job.
#
# So: the index update and the package download each run under `timeout` and are tried again (a download that is
# tried again keeps the packages it has and resumes the partial one), and only then are the packages installed from
# the local cache, once, also under a time limit. Every phase's output is shown in a collapsed group, so a stall is
# visible in the log. Nothing is skipped: any phase that fails every attempt fails the step.
#
#   .github/scripts/apt-install.sh PACKAGE...
# The limits can be set for the test (tests/test_apt_install.py): APT_TRIES, APT_UPDATE_SECS, APT_DOWNLOAD_SECS,
# APT_INSTALL_SECS. APT_SKIP_UPDATE=1 skips the index update, for a call right after another that made it
# (playwright-deps.sh). The defaults add up to at most 26 minutes (20 without the update); where that is more than a
# job's own limit (server-http, 20; web, which calls this twice), the job's limit ends it first: still bounded.
# Playwright's browser packages come through here too (playwright-deps.sh), not `playwright install --with-deps`.
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: $0 PACKAGE..." >&2; exit 2; }
TRIES=${APT_TRIES:-3}
UPDATE_SECS=${APT_UPDATE_SECS:-120}
DOWNLOAD_SECS=${APT_DOWNLOAD_SECS:-240}
INSTALL_SECS=${APT_INSTALL_SECS:-480}
APT=(apt-get -q -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Dpkg::Use-Pty=0
     -o DPkg::Lock::Timeout=60)

# run "$@" as root under a time limit; TRIES attempts when $1 is "retry", one when it is "once"
phase() {
  local mode=$1 what=$2 secs=$3 tries=1 i t0; shift 3
  [ "$mode" = retry ] && tries=$TRIES
  for ((i = 1; i <= tries; i++)); do
    t0=$SECONDS
    echo "::group::apt: $what (attempt $i of $tries, at most ${secs}s)"
    if sudo timeout -k 15 "$secs" env DEBIAN_FRONTEND=noninteractive "$@"; then
      echo "::endgroup::"; echo "apt: $what took $((SECONDS - t0))s"; return 0
    fi
    echo "::endgroup::"
    echo "::warning::apt: $what failed or ran over ${secs}s (attempt $i of $tries, $((SECONDS - t0))s)"
  done
  echo "::error::apt: $what failed $tries time(s)"
  return 1
}

[ "${APT_SKIP_UPDATE:-}" = 1 ] || phase retry "update the package lists" "$UPDATE_SECS" "${APT[@]}" update
phase retry "download $*" "$DOWNLOAD_SECS" "${APT[@]}" install -y --no-install-recommends --download-only "$@"
phase once "install $*" "$INSTALL_SECS" "${APT[@]}" install -y --no-install-recommends "$@"
