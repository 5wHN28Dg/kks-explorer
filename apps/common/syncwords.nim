## The offline state and the changes waiting to be sent (#372; PROTOCOL-v2 §15c), the same words on every client:
## the desktop apps use these; Android (ui/Status.kt) and the tests (tests/test_sync_words.py) hold the same sentences.

import std/[os, strutils]
import kks/json

const
  OfflineAfter* = 300          ## s without a successful sync with any device before a device says it is offline
  UxOn*: seq[string] = @[]     ## switched changes a release has turned on (the UI and UX policy's 8.5)
  OfflineWord* = "Offline"
  OfflineHelp* = "Changes are kept on this device and sent when it reaches another device of the plant."
  WaitingShownAfter* = 15_000  ## ms a change waits while online before it is shown (each edit is sent within seconds)

proc uxOn*(name: string): bool =
  ## a change waiting for the owner's check: off unless a release turned it on, or KKS_UX=name[,name…] is set
  name in UxOn or name in getEnv("KKS_UX").split(',')

proc grouped*(n: int64): string =
  ## 1834 → "1,834" (the UI is English)
  let s = $n
  for i, c in s:
    if i > 0 and (s.len - i) mod 3 == 0: result.add ','
    result.add c

proc waitingWords*(n: int64): string =
  ## "" when nothing waits
  if n <= 0: "" elif n == 1: "1 change waiting to be sent" else: grouped(n) & " changes waiting to be sent"

proc isOffline*(snap: JNode, nowS: int64): bool =
  ## the last finished round reached no device, and no device synced with this one in the last OfflineAfter seconds
  ## (before the first round the device is still looking; after a pause or a suspend it waits for a round that fails)
  let rounds = snap.get("rounds")
  if rounds == nil or rounds.kind != jBool or not rounds.b: return false
  let ok = snap.get("last_round_ok")
  if ok != nil and ok.kind == jBool and ok.b: return false
  let last = snap.get("last_ok")
  let after = try: parseInt(getEnv("KKS_OFFLINE_AFTER", $OfflineAfter)) except ValueError: OfflineAfter   # (tests)
  last == nil or last.kind != jInt or nowS - last.i >= after

proc shownWaiting*(snap: JNode, offline: bool, since: var int64, nowMs: int64): int64 =
  ## the changes to show: all of them offline; online only once they have waited WaitingShownAfter (so an edit sent
  ## within seconds neither shows nor is read out). `since` keeps when they began to wait (0 = nothing waits).
  let w = snap.get("waiting")
  let n = if w != nil and w.kind == jInt: w.i else: 0
  if n <= 0: since = 0
  elif since == 0: since = nowMs
  if offline or (n > 0 and nowMs - since >= WaitingShownAfter): n else: 0

proc waitingOf*(snap: JNode): int64 =
  let w = snap.get("waiting")
  if w != nil and w.kind == jInt: w.i else: 0
