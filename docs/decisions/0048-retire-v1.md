# 0048 Retiring the v1 move path

Date 2026-10-05 · Scope: the server, the Android app, the relay, `tools/release.py`, PROTOCOL-v2 §21a · Status:
**decided by the user** ("we are done with v1, I have told everyone to migrate, don't care if some did not migrate
yet, nuke every remaining v1 thing in the project ... that we only kept so everyone migrates first")

**Question:** 0042 kept several pieces alive so that phones on the old app (0.8.0, package `kks.explorer`) could move
to Walkdown by themselves. Its "When to revisit" said to remove them once every v1 device had moved. The user has now
told everyone to move and doesn't wait for the rest. What goes, and what stays?

## Findings

| | Fact | Source |
|---|---|---|
| Who still needs the move path | Only phones still on 0.8.0 or its bridge. The user accepts that any of them now joins like a new device (ask an admin) | the user, 2026-10-05 |
| What a v1 password hash needs | Accounts imported from v1 keep their scrypt hash until that person logs in once; the server then replaces it with Argon2id (0023). Removing the scrypt check would lock those people out | `platform/linux/src/kksl/argon2.nim`, `server.nim` login |
| The v1 import in the protocol | §21's one-time import is part of the plant's genesis: every device replays it, and the frozen vectors (`v2-replay.json`) cover it | PROTOCOL-v2 §21, `ref/vectors` |
| The v1 server's import commands | `import-v1` and `import-succession` were already removed after the cutover (2026-10-03) | `server.nim` (git history) |

## Choice

Removed from the repository:
- **Server:** the `succession` and `migrate` answers (`successionOverTls`, `migrateOverTls`), the v1 device table's
  readers (`v1Root`, `v1Room`, `v1Waiting`), presence in the v1 relay room (`internetV1`), the mDNS TXT `prev`,
  `/api/devices` → `sync.v1_waiting`, and the CLI command `kks-server v1-status`.
- **Core:** the `succession`/`migrate` hooks in the sync session (they are now unknown first messages, as for any
  other); `provider_gnutls.ed25519Verify`.
- **Linux layer:** `Internet.roomOf` (only the v1 room used it).
- **Android:** `sync/Migrate.kt`, the "Moving from KKS Explorer" card on the setup screen, the hand-over permission
  and the `<queries>` entry for `kks.explorer`, the TXT `prev` in `Discovery.Found`, the JNI routes
  `/native/relay-hello` and `/native/v1-entry`; the e2e tests no longer uninstall `kks.explorer`.
- **admin.html:** the "Moving from the old app" card.
- **Relay (source only; the deployed Worker is unchanged until the next deploy):** v1 Ed25519 hellos in
  `relay/src/index.js` and `relay/twin.py`.
- **`tools/release.py`:** the bridge APK attachment, `kks-explorer.apk`, the v1 desktop packages, and the Ed25519
  `release.json.sig`. Releases carry `release.json` + `release.json.p256` only (0044); `--new-key` makes a P-256 key.
- **`docs/PROTOCOL.md`** (the frozen v1 spec; it stays in git history). PROTOCOL-v2 §21a is marked retired.

Kept:
- the scrypt check of v1 password hashes (see above);
- PROTOCOL-v2 §21 and the import genesis in replay (part of the live plant's log and of the frozen vectors);
- `/api/devices/enroll` (the GNOME and Android apps still use it);
- the protocol strings CLAUDE.md lists as unchanged on purpose (`kks-…` domains, `_kks._tcp`, the relay's `/v1/…`
  URL paths, release.json's `"app": "kks-explorer"`).

Left on the live machine, not touched by this change (the user's call): the v1 rows in the server's store (`v1`,
`v1_devices`, `v1_moved`; nothing reads them now), `~/kks-server/v1`, `~/kks-server/archive` (with the bridge APK),
and the Ed25519 release key in the signing folder. The deployed relay still accepts v1 hellos until it is redeployed.

**When to revisit:** never for the move itself. A phone still on 0.8.0 installs Walkdown by hand and joins as a new
device.
