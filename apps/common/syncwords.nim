## The offline state and the changes waiting to be sent (#372; PROTOCOL-v2 §15c), the same words on every client:
## the desktop apps use these; Android (ui/Status.kt) and the tests (tests/test_sync_words.py) hold the same sentences.

import std/[os, strutils]
import kks/json

const
  OfflineAfter* = 300          ## s without a successful sync with any device before a device says it is offline
  UxOn*: seq[string] = @[]     ## switched changes a release has turned on (the UI and UX policy's 8.5)
  OfflineWord* = "Offline"
  OfflineHelp* = "Changes are kept on this device and sent when it reaches another device of the plant."

proc uxOn*(name: string): bool =
  ## a change waiting for the owner's check: off unless a release turned it on, or KKS_UX=name[,name…] is set
  name in UxOn or name in getEnv("KKS_UX").split(',')

proc waitingWords*(n: int64): string =
  ## "" when nothing waits
  if n <= 0: "" elif n == 1: "1 change waiting to be sent" else: $n & " changes waiting to be sent"

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

proc waitingOf*(snap: JNode): int64 =
  let w = snap.get("waiting")
  if w != nil and w.kind == jInt: w.i else: 0
