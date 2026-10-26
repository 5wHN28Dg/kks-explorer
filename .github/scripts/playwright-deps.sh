#!/bin/bash
# The Ubuntu packages one Playwright browser needs, installed through apt-install.sh (bounded in time, retried, output
# shown) instead of `playwright install --with-deps`, which runs `apt-get update` and `apt-get install` itself with no
# time limit (GitHub's mirror stalls had held jobs for their whole 40 minutes; see apt-install.sh).
#
#   .github/scripts/playwright-deps.sh ENGINE        (chromium, firefox or webkit; then `playwright install ENGINE`)
#
# The list comes from Playwright itself: `playwright install-deps --dry-run ENGINE` simulates the same
# `apt-get install --no-install-recommends` that --with-deps runs, on the package lists apt-install.sh has brought up
# to date (the job runs it for its own packages first), and prints every package that would be installed
# (Playwright's list and what they pull in) or says that all are installed. Any other answer, or a list whose length
# is not the count it states, fails the step. After installing, the same check must say that all are installed.
# $PLAYWRIGHT is the playwright command (the test sets a fake one).
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 ENGINE" >&2; exit 2; }
PLAYWRIGHT=${PLAYWRIGHT:-.venv/bin/playwright}
HERE=$(dirname "$0")

# prints the missing packages one per line (nothing when all are installed); fails on any other answer
missing() {
  local out code=0
  out=$("$PLAYWRIGHT" install-deps --dry-run "$1" 2>&1) || code=$?
  if [ $code -eq 0 ] && grep -qx 'All system dependencies are installed\.' <<<"$out"; then
    return 0
  fi
  local n list
  n=$(sed -n 's/^Missing system dependencies (\([0-9]\+\)):$/\1/p' <<<"$out")
  if [ $code -ne 0 ] && [ -n "$n" ]; then
    list=$(sed -n '/^Missing system dependencies (/,$p' <<<"$out" | sed -n 's/^  \([a-z0-9][a-z0-9.+:-]*\)$/\1/p')
    if [ "$n" -gt 0 ] && [ "$(grep -c . <<<"$list")" -eq "$n" ]; then
      echo "$list"
      return 0
    fi
  fi
  echo "::error::playwright install-deps --dry-run $1 gave an answer this script does not know (exit $code):" >&2
  echo "$out" >&2
  return 1
}

pkgs=$(missing "$1")
if [ -n "$pkgs" ]; then
  mapfile -t list <<<"$pkgs"
  echo "Playwright's $1 needs: ${list[*]}"
  "$HERE/apt-install.sh" "${list[@]}"
else
  echo "Playwright's $1: all system dependencies are installed already"
fi
left=$(missing "$1")
if [ -n "$left" ]; then
  echo "::error::still missing for Playwright's $1 after installing: $(tr '\n' ' ' <<<"$left")"
  exit 1
fi
