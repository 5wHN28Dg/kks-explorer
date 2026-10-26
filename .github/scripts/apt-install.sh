#!/bin/bash
# apt-get install for the CI jobs (tests.yml), every phase bounded in time.
#
# Why (2026-10-26): the gnome-e2e job ran into its 40-minute limit three times in one morning, on main and on a PR,
# and python shard 0 into its 30 minutes once, each time inside `apt-get install` (silenced by >/dev/null)
# right after `apt-get update` had finished: the runner's Ubuntu mirror stalled the download. The same installs
# normally take 1 to 3 minutes; a slow mirror took up to 15. apt's own timeout (Acquire::http::Timeout) only ends a
# connection that sends nothing at all, so a trickling one hung the job until it was cancelled.
#
# So: the index update and the package download each run under `timeout` and are tried again (a download that is
# tried again keeps the packages it has and resumes the partial one), and only then are the packages installed from
# the local cache, once, also under a time limit. Every phase's output is shown in a collapsed group, so a stall is
# visible in the log. Nothing is skipped: any phase that fails every attempt fails the step.
#
#   .github/scripts/apt-install.sh PACKAGE...
# The limits can be set for the test (tests/test_apt_install.py): APT_TRIES, APT_UPDATE_SECS, APT_DOWNLOAD_SECS,
# APT_INSTALL_SECS.
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: $0 PACKAGE..." >&2; exit 2; }
TRIES=${APT_TRIES:-3}
UPDATE_SECS=${APT_UPDATE_SECS:-180}
DOWNLOAD_SECS=${APT_DOWNLOAD_SECS:-300}
INSTALL_SECS=${APT_INSTALL_SECS:-600}
APT=(apt-get -q -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Dpkg::Use-Pty=0)

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

phase retry "update the package lists" "$UPDATE_SECS" "${APT[@]}" update
phase retry "download $*" "$DOWNLOAD_SECS" "${APT[@]}" install -y --no-install-recommends --download-only "$@"
phase once "install $*" "$INSTALL_SECS" "${APT[@]}" install -y --no-install-recommends "$@"
