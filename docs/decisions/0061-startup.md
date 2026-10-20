# 0061 Walkdown opens in under half a second: the store opens while the window is made, and a saved replayed state

Date 2026-10-21 · Scope: the Nim core (node, replay), the GNOME, Windows and Android apps · Status: **accepted** (the
user's go-ahead for the startup work, 2026-10-21) · Measurements: docs/m6/MEASUREMENTS.md "Startup, 2026-10-21"

**Question:** a start did everything in a row: GTK or Win32 made ready, the sealed store opened, every entry of the log
decrypted and parsed, the whole log replayed (twice: the revocation rounds, then the final pass), the plant model
built, the window made, every overview level of the first sheet read from the store, the sync service and discovery
started, and only then the first frame. Which of that can go off the path to the first drawn sheet, and what may be
kept from one start to the next without ever showing something the log doesn't say?

## Findings

[V] measured here (docs/m6/MEASUREMENTS.md); [S] source read.

- **Where the time went (GNOME, a joined device holding 4,120 log entries and 17 sheets, 369 ms to the first sheet)**
  [V]: GTK's start inside `g_application_register` ~100 ms; the store and the log ~140 ms (decrypting and parsing the
  entries ~55 ms, the replay ~75 ms); the model ~30 ms; the main screen ~10 ms; GTK's first frame and the overview
  ~80 ms. Nothing of the store or the log needs GTK, and nothing of GTK's start needs the store.
- **The replay ran its last pass twice** [S, V]: `computeCuts` replays until the revocation cuts settle, then the final
  pass replays once more with the accepted revokes. The two differ only where the settled round recorded a revoke it
  did not accept (`overridden`); with the same cuts and every recorded revoke accepted, the final pass repeats the
  round step for step. Reusing the round's run: 36 → 25 ms for 4,120 entries [V], the same result field for field on
  every scenario of the shared vectors [V, `core/tests/test_replay_settled.nim`].
- **A saved copy of the replay** [V]: the replay's whole result in a compact binary form is 1.6 MB for that log; reading
  it back (decrypt, check, decode) takes ~10 ms instead of the 25 ms replay, and with the store's own row seal and a
  digest of exactly what was replayed it can't be another log's or another version's (PROTOCOL-v2 §15b).
- **Threads in Nim 2 (ORC)** [S: lib/system/orc.nim, alloc.nim, threadimpl.nim]: memory a thread allocated stays valid
  after it ends (its region goes back to a pool; frees from other threads are queued to it), so a whole object graph
  can be handed over. ORC keeps possible cycle roots per thread; a root left in the ending thread's list would later be
  unlinked from the wrong list, so the thread runs its cycle collector (`GC_runOrc`) before it hands the graph over,
  which empties its list and leaves what is reachable alone.
- **Android** [S]: `App.onCreate` waited on the core thread for the open (`Core.open`), and the first composition asked
  the core whether the phone had joined: the first frame came after the whole open.

## Choice

- **The store, the log and the first model on a thread of their own while the window is made** (GNOME: while GTK
  starts; Windows: while the window class, the window and its fonts are made; `appstate.openAppInBackground`,
  `openedApp`). The main thread waits for it only when it needs the app. The thread does nothing only the running
  instance may do: the last run's crash report and the change listener come after (`startApp`). GNOME starts it only
  when Walkdown isn't running already (its application ID unowned on the session bus): a start that hands its links
  over still ends without touching the store (decision 0058). A first start (no store yet: the storage key is made)
  goes the plain way.
- **Android:** the core opens on its thread without anyone waiting (`Core.openInBackground`); every later call queues
  behind it. The first frame is the empty themed screen; the main screen or the setup comes when the core has
  answered (`Root`), on a background dispatcher.
- **The saved replayed state** (PROTOCOL-v2 §15b): made right after each replay from the replay's own result (so what
  is saved never includes anything changed in memory since), written to the store's sealed meta row when the app
  chooses (GNOME and Windows every 30 s while changed and at exit, Android after each sync round and when it goes to
  the background, every app at a start that had to replay); read at start only when it matches. The server keeps
  none (`newNode(…, keepState = false)`): it starts rarely and would pay the encoding on every request.
- **The replay's last pass** is the settled round's run when the round recorded no revoke it did not accept.
- **Only what the first frame needs, first:** the overview levels are read from the store when the viewer first wants
  each (GNOME; Windows and Android already did), the sync listener, the relay and discovery start after the window is
  up (GNOME: an idle callback after the window; Windows: the first timer tick, after the first paint; Android: after
  the core answered), and a decoded level reaches the GNOME viewer at once instead of at the next 50 ms poll.
- Not done: decoding the first overview level on the loading thread (GNOME's first frame, ~55 ms, then dominates and
  would carry it; ~25 ms more), and loading the entries themselves lazily (the sync, the API and the photos all read
  them; a saved copy of the entries would need the same proofs as §15b for the log itself).

## When to revisit

When a log grows past ~50,000 entries (the entries' decryption and parsing, still done at every start, then dominate:
keep a saved copy of the parsed entries too); when the replay's code changes often enough that every update's first
start replays noticeably (the code id changes with it); when GTK or Win32 can draw before their own start finishes.
