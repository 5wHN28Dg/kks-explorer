# 0045 The server's CLI commands that change the plant run inside the running server

Date 2026-10-04 · Scope: `kks-server` (platform/linux) · Status: **done** (found in the field; the fix follows the
existing architecture, 0030)

**Question:** `kks-server publish-data` ran in a second process next to the running server. How should commands that
change the plant reach the server?

## What happened

- After two new sheets were published with `publish-data`, no phone and no browser got them until the server was
  restarted. The admin page's Drawings list showed them, because it reads the files directly.
- The CLI process wrote the new entry into the store, but the running server keeps the log in memory (`Node.entries`,
  `Run`; the store is read once in `newNode`) and never saw it.
- Worse, the manager's custodial key signs in both processes. A manager action in the server between the CLI's write
  and a restart would have signed a second entry with the same seq: a forked chain. A read-only check of the live store
  (2026-10-04) found no duplicate (device, seq), no fork evidence and no ignored entry.

## Findings

| | Fact | Source |
|---|---|---|
| SQLite | several processes may write one database (WAL); that is not the problem: the in-memory node is | code: `core/src/kks/node.nim` `newNode` |
| Unix sockets | `AF_UNIX` stream sockets on Linux; the file's permissions decide who may connect | [D] https://man7.org/linux/man-pages/man7/unix.7.html |
| Nim | `asyncnet.bindUnix`, `net.connectUnix` in the standard library | [D] https://nim-lang.org/docs/asyncnet.html, https://nim-lang.org/docs/net.html |
| Nim `fileExists` | true only for regular files, not for a socket | [V] this machine (the first version never forwarded) |

## Choice

- While serving, the server listens on `kks-server.sock` next to its store, created with mode 0600 (umask), so only
  its own user can talk to it. It answers one JSON line `{cmd, args}` with `{ok, out}`.
- `publish-data` and the new `set-plant-name` (the plant's name, written as the manager; also `/api/settings/plant`
  and a field in the admin page) try that socket first and run in the server; with no server running they work
  directly, as before.
- Test: `platform/linux/e2e/test_server_http.py` `Cli` (publishes through the running server; the new version is
  served at once; the socket is 0600; the plant's name from the CLI and the admin page).

**Not changed:** read-only commands (`users`, `v1-status`, `export-root-key`, `backup`) still open the store
themselves. `reset-password` and `reset-manager` are listed in the CLI's help but were never written.

**When to revisit:** when another command needs to change the plant: it goes through `Server.control`.
