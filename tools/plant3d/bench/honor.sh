#!/bin/sh
# Decision 0041 on the Honor 600 (a current phone; the user's own: only the bench, kks.plant3d.bench, is installed,
# no setting is changed, and the bench is removed at the end, also when a step fails). The load time first (first and
# second start), so the walks after it start with the shaders compiled as the Note 9's did; then the full preset and
# the Note 9's preset (lean+vis) for 10 minutes each, the look viewpoints. About 30 minutes.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=AFAM026711005741
export BENCH_KEEP=1
mkdir -p "$HERE/results"
# removed also on Ctrl-C or a closed terminal (dash runs no EXIT trap on a signal)
# The removal ignores further signals, runs with BENCH_KEEP=0, logs to a file (after a hang-up there is no terminal)
# and says loudly when it fails. A killed laptop (SIGKILL, power loss) still leaves the bench: run
# `run_phone.sh AFAM026711005741 remove` then.
cleanup() {
  trap '' INT TERM HUP
  if ! BENCH_KEEP=0 "$HERE/run_phone.sh" $S remove >>"$HERE/results/honor-remove.log" 2>&1; then
    echo "!!! THE BENCH MAY STILL BE ON THE HONOR: run $HERE/run_phone.sh $S remove (log: results/honor-remove.log)" >&2 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
"$HERE/run_phone.sh" $S load full
"$HERE/run_phone.sh" $S walk full 600
# the Note 9's preset (decision 0041, 2026-10-16)
"$HERE/run_phone.sh" $S walk lean+vis 600
"$HERE/run_phone.sh" $S look full
echo "results: $HERE/results/$S/summary.tsv"
