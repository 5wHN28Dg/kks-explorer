#!/bin/sh
# One download, tried again when it fails: up to DOWNLOAD_TRIES (5) tries, the pause between them doubling from
# DOWNLOAD_BACKOFF_SECS (15 s: 15, 30, 60, 120). Each try gives up on a connection not made in 30 s and on a transfer
# slower than 1 kB/s for 60 s. Written to FILE.part and moved to FILE only when whole; nothing is checked here: the
# caller checks the file's SHA-256 as before.
# Why (2026-10-26): downloads.xiph.org refused TLS (curl: (35) SSL_ERROR_SYSCALL) for one CI run's opus and another's
# SpeexDSP, and one failed try failed the job.
#   tools/download.sh URL FILE
set -eu
[ $# -eq 2 ] || { echo "usage: $0 URL FILE" >&2; exit 2; }
URL=$1; OUT=$2
TRIES=${DOWNLOAD_TRIES:-5}
PAUSE=${DOWNLOAD_BACKOFF_SECS:-15}
n=1
while :; do
  if curl -sSfL --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o "$OUT.part" "$URL"; then
    mv "$OUT.part" "$OUT"
    exit 0
  fi
  rm -f "$OUT.part"
  if [ "$n" -ge "$TRIES" ]; then
    echo "download failed $n time(s): $URL" >&2
    exit 1
  fi
  echo "download failed (try $n of $TRIES): $URL; again in ${PAUSE}s" >&2
  sleep "$PAUSE"
  n=$((n + 1)); PAUSE=$((PAUSE * 2))
done
