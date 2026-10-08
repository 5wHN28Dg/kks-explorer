# 0049 Android: photos are encoded and sent by a WorkManager queue

Date 2026-10-08 · Scope: `android/app2` · Status: proposed

**Question:** the user, 2026-10-08: "Compression currently fails/stops when the info window is closed (on android). It
should keep going whether or not the info popover is open. Image compression should use a queue, so I can take photos
one after another for several tags and have them all processed in order." Where should the JPEG XL encoding and the
submission run, so that they outlive the panel and, if feasible, the process?

## Findings

| | Fact | Source |
|---|---|---|
| Before | the encode ran in the panel's `rememberCoroutineScope`; closing the panel leaves the composition and cancels that scope, so the photo was lost | [V] `PhotoStrip` before this change · [D] https://developer.android.com/develop/ui/compose/side-effects#remembercoroutinescope |
| Cost | libjxl at effort 9 takes several seconds per megapixel on a phone (the app's own estimate starts at 8 s/MP; a 1600 px photo is ~1.9 MP) | [K] `Jxl.msPerMp`, not measured on the Note 9 / Honor for this change |
| Process death | Android kills a background app's process to reclaim memory; work held only in memory (an app-level coroutine scope or executor) is lost with it | [D] https://developer.android.com/guide/components/activities/process-lifecycle |
| WorkManager | "the recommended solution for persistent work": work stays scheduled through app restarts and reboots; unique work with `APPEND_OR_REPLACE` runs requests one after another in the order enqueued, and starts a new chain if the old one failed | [D] https://developer.android.com/develop/background-work/background-tasks/persistent · https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/manage-work |
| Limits | a worker may run up to 10 minutes; expedited work on Android 11 and older runs as a foreground service and needs `getForegroundInfo` (a notification) | [D] https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work |
| Foreground service | the alternative for long user-started work: a notification and, from Android 14, a declared service type and its permission | [D] https://developer.android.com/develop/background-work/services/fgs/service-types |
| Already here | `androidx.work:work-runtime-ktx` 2.11.2 is a dependency (the background sync, `SyncWorker`) | [V] `android/app2/build.gradle.kts` |

## Choice

- **WorkManager, one unique chain** (`kks-photos`, `APPEND_OR_REPLACE`), one `PhotoWorker` per photo: what the platform
  provides for work that must survive the app closing and the process dying, already a dependency, no new permission.
- **Send** writes the annotated pixels (raw RGBA, lossless) and a small JSON (code, caption, note, floor) to
  `files/photo-queue/` on the queue's own thread, then enqueues. The worker encodes, submits through the core with the
  job's ID as `client_id` (a rerun after a kill can't add the photo twice), and deletes the files.
- **Order and failures:** a worker always returns success, so one bad photo never stops the ones after it; what went
  wrong is kept (shared preferences) and shown in a card on every screen until dismissed. At start the app requeues
  job files whose work was lost (written just before the process died).
- **Not expedited:** the work runs as soon as WorkManager starts it (at once while the app is in use). Expedited work
  would need a notification on Android 10 and 11 (minSdk 29) for little gain while the app is open.
- **Status:** "N photos being prepared" under the header on every screen, and per tag in the panel.
- **Removal:** a phone removed from the plant cancels the chain and deletes the queued files with the rest.

**When to revisit:** if photos sit in the queue for long on the Honor (MagicOS defers background work, see the
background sync notice) while the app is closed: then an expedited request with a notification, or a short foreground
service.
