#!/bin/sh
# Everything decision 0041 measures on the Samsung Galaxy Note 9 (the minimum tier), in one command, plugged in by USB:
# the levers and the preset ladder (3 minutes each), the chosen preset for 10 minutes, the load time (first and second
# start), the look viewpoints (chosen preset and full), and last the final 10-minute walk on battery: the script says
# when to pull the cable and waits for it to be put back. About 75 minutes. --no-unplugged leaves out the last step.
# Room temperature; the script sets 50 % brightness and puts the old setting back.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=285d2a7c153f7ece
"$HERE/run_phone.sh" $S ladder
P=$(cat "$HERE/results/$S/chosen.txt")
"$HERE/run_phone.sh" $S load "$P"
"$HERE/run_phone.sh" $S look "$P"
[ "$P" = full ] || "$HERE/run_phone.sh" $S look full
[ "${1:-}" = --no-unplugged ] || "$HERE/run_phone.sh" $S unplugged "$P" 600
"$HERE/run_phone.sh" $S remove
echo "results: $HERE/results/$S/summary.tsv"
