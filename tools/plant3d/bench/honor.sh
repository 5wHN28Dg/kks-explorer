#!/bin/sh
# Decision 0041 on the Honor 600 (a current phone; the user's own: only the bench, kks.plant3d.bench, is installed,
# no setting is changed, and the bench is removed at the end, also when a step fails). The load time first (first and
# second start), so the walks after it start with the shaders compiled as the Note 9's did; then the full preset for
# 10 minutes, the Note 9's chosen preset (results/285d2a7c153f7ece/chosen.txt, if measured) for 3, the look
# viewpoints. About 25 minutes.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=AFAM026711005741
export BENCH_KEEP=1
trap '"$HERE/run_phone.sh" $S remove' EXIT
"$HERE/run_phone.sh" $S load full
"$HERE/run_phone.sh" $S walk full 600
C="$HERE/results/285d2a7c153f7ece/chosen.txt"
[ -f "$C" ] && [ "$(cat "$C")" != full ] && "$HERE/run_phone.sh" $S walk "$(cat "$C")" 180
"$HERE/run_phone.sh" $S look full
echo "results: $HERE/results/$S/summary.tsv"
