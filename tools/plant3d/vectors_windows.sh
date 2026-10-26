#!/bin/sh
# The engine's vectors on Windows (docs/plant3d/MULTIPLAYER.md §4 and §12, milestone MP1): apps/plant3d/sim's
# run_vectors.gd with the pinned Godot's Windows build in a Windows VM, and its digests (every value at every step, the
# state digest of every 50th step) compared with this machine's.
#   tools/plant3d/vectors_windows.sh VM_IP GODOT_WIN_ZIP LINUX_DIGESTS
# VM_IP: a running VM with OpenSSH (~/.ssh/kks_vm, user kks: apps/windows/e2e/vm), started and stopped by the caller,
# who holds ~/kks-work/build/vm.lock meanwhile (one VM or emulator machine-wide). GODOT_WIN_ZIP: the editor's
# Godot_v4.7.2-stable_win64.exe.zip, checked against the release's SHA-512 (below). LINUX_DIGESTS: run_vectors.gd's
# --digests output made here from the same checkout. Prints the VM's VECTORS line and "DIGESTS equal" or the runs
# whose digests differ; exit code 0 only when every vector passed there and every digest is equal.
set -eu
VM="$1"; ZIP="$2"; LINUX="$3"
WIN_SHA512=83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
echo "$WIN_SHA512  $ZIP" | sha512sum -c - >/dev/null || { echo "the Windows Godot is not the pinned one" >&2; exit 2; }
SSH="-i $HOME/.ssh/kks_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/vecwin.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
(cd "$ROOT" && tar -cf "$TMP/v.tar" apps/plant3d/sim ref/vectors/plant3d-v1.json ref/vectors/plant3d-v2.json data/plant3d)
# shellcheck disable=SC2086
ssh $SSH "kks@$VM" "powershell -NoProfile -Command \"Remove-Item -Recurse -Force C:/vectors -ErrorAction SilentlyContinue; New-Item -ItemType Directory C:/vectors | Out-Null\""
# shellcheck disable=SC2086
scp -q $SSH "$TMP/v.tar" "$ZIP" "kks@$VM:C:/vectors/"
# shellcheck disable=SC2086
ssh $SSH "kks@$VM" "powershell -NoProfile -Command \"cd C:/vectors; tar -xf v.tar; Expand-Archive -Force $(basename "$ZIP") .; ./Godot_v4.7.2-stable_win64_console.exe --headless --script C:/vectors/apps/plant3d/sim/tests/run_vectors.gd -- --digests=C:/vectors/digests.json 2>&1 | Select-String -Pattern 'VECTORS|FAIL|ERROR|PROGRAM'\"" | tee "$TMP/out.txt"
# shellcheck disable=SC2086
scp -q $SSH "kks@$VM:C:/vectors/digests.json" "$TMP/win.json"
grep -q "VECTORS passed=[0-9]* failed=0" "$TMP/out.txt" || { echo "a vector failed on Windows" >&2; exit 1; }
python3 - "$TMP/win.json" "$LINUX" <<'EOF'
import json, sys
w, l = (json.load(open(p)) for p in sys.argv[1:])
bad = sorted(k for k in set(w) | set(l) if w.get(k) != l.get(k))
n = sum(len(v.get('state', [])) for v in l.values())
print(f'DIGESTS equal: {len(l)} runs, {n} state digests' if not bad else 'DIGESTS differ: ' + ', '.join(bad[:20]))
sys.exit(1 if bad else 0)
EOF
