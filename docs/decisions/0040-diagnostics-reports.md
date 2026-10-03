# 0040 Diagnostics reports to the manager

Date 2026-10-03 · Scope: field testing on teammates' devices; PROTOCOL-v2 §13a · Status: **accepted by the user
2026-10-02** ("let's do it the way you described"); details by Claude.

**Question:** when the apps go onto teammates' phones and laptops, how does the manager learn about crashes and
silent failures (syncs that keep failing, a background sync that never runs) without asking each person, and
without plant data or anyone's data leaving the plant's own devices?

## Findings

| | What exists | Crash hook |
|---|---|---|
| Android | `logcat`, readable only over USB debugging | `Thread.setDefaultUncaughtExceptionHandler`: runs before the process dies; a file written there survives [D] |
| GNOME | stderr | exceptions are caught in the GLib trampolines (`guard`, 0031): the app keeps running |
| Windows | `crash.log` in the app's folder | the same catching in the window procedures; `crash.log` for what escapes |
| Server | its console | HTTP handler errors are caught (500) |

Third-party crash services (Sentry, Firebase Crashlytics) send data to an outside company and need SDKs on every
platform: ruled out by the plant's data rules and decision 0012's reasoning for the relay.
Sources: https://developer.android.com/reference/java/lang/Thread.UncaughtExceptionHandler · PROTOCOL-v2 §13, §17, §20.

## Choice

- **Transport = the plant's own log.** A `report` entry, ECIES-sealed (§20) to a report key; the report key's private
  half is a private entry (§13) of the manager, so only the manager's own devices open reports (servers hold no
  person secret). No new crypto, no new connection, works over the relay too.
- **Contents:** device, app, version, platform, model, and events `{at, kind (crash|error|sync), text, n}`; no plant
  data, no passwords. Repeats fold into a count; at most one report per device per 6 h, ≤ 32 KB.
- **Logic in the core** (`core/src/kks/diagnostics.nim`, routes `/api/diagnostics`); platform code only records
  events and asks for a report after each sync round.
- **Switch:** manager only, from the manager's own device (`POST /api/diagnostics`); every device shows whether it is
  on, so teammates know.
- **Vectors:** `ref/vectors/v2-reports.json` (new file; the older files unchanged). The Python reference and the Nim
  core agree on it.

**When to revisit:** if reports grow the log noticeably (count `reports` in the state), or the plant wants them
deleted after reading (the log is append-only; a compaction rule would be a protocol change).
