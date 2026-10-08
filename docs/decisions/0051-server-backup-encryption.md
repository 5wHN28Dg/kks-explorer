# 0051 The server's backups are encrypted with a key from the root key backup's passphrase

Date 2026-10-08 · Scope: `kks-server backup`, `export-root-key`, new `open-backup`; `platform/linux/src/kksl/
serverbackup.nim` · Status: **decided by the user** (2026-10-08, issue #28: "encrypt the server's own backup files
with a key derived from the root-key backup passphrase (restore needs it); join-by-file bundles stay as they are")

**Question:** `kks-server backup` writes the whole plant (log and photos) as a plain bundle (#28). Decision 0020 asks
for backups encrypted so that only the manager can restore them. Nothing in the plant has a backup key yet: the §8
`backup_key` statement exists, but no device makes or holds one. What should the server encrypt to?

## Findings

| | Fact | Source |
|---|---|---|
| Who restores | The manager, from the root key backup routine: a file and its generated passphrase (80 bits, 0023/#29), kept offline | `kks_server.nim export-root-key`, decision 0023 |
| Unattended backups | A backup run (cron, a timer) can't ask for a passphrase. A key derived once and kept sealed in the server's store needs no passphrase at backup time | `dbstore` sealed rows (0020) |
| Join-by-file bundles | `/api/bundle` and the apps' "Export" make bundles a new device imports. A joining device doesn't know the passphrase, so these stay plain | `core/src/kks/bundle.nim`, the user's decision |
| Sheet backups and uploads in `backups/` | The server reads them itself to undo a failed import. Encrypting them with a passphrase key would stop that | `server.nim restoreSheets` |
| What PBKDF2 gives | 0023's KDF, on every platform's provider; with an 80-bit generated passphrase, brute force is out of reach | decision 0023 |

## Choice

- **The key:** `export-root-key` generates the passphrase as before. It now also derives the **server backup key**
  K = PBKDF2-HMAC-SHA256(passphrase, a new 16-byte salt, 600 000 iterations, 32 bytes) and keeps K, with the salt and
  the iteration count, in the server's sealed store (`keys/backup`). A new export replaces it.
- **`kks-server backup --out FILE`** writes `{"kks_server_backup": 2, "root", "created", "kdf": "pbkdf2-sha256",
  "iter", "salt", "nonce", "ct"}` (0600):
  - `ct` = AES-256-GCM(K, a random 12-byte nonce, the gzip bundle, associated data ASCII `kks-server-backup-v2\n`
    + root + `\n` + created + `\n` + salt + `\n` + iter, so the header can't be changed);
  - `open-backup` refuses `iter` above 6 000 000, so a crafted file can't make it run for hours;
  - it refuses to run until `export-root-key` has made K, so there is never a plain backup.
- **`kks-server open-backup --in FILE --out BUNDLE --passphrase-file PASS`** derives K from the passphrase and the
  file's salt, and writes the plain bundle (0600). The manager imports it like any bundle (Manage → Import). It works
  on any machine with the server binary, without the server's store.
- **Unchanged:** join-by-file bundles (`/api/bundle`, the apps' export), the server's own sheet backups and uploads
  under `backups/` (the server process only, umask 077 under systemd), the plant-data working copy.

**Costs:**
- a backup opens only with the passphrase of the root key export that was current when it was made. Every new export
  makes a new key, so the manager keeps each passphrase as long as backups made under it are kept;
- K sits in the server's store, so whoever controls the server can read new backups. That is the server itself, which
  holds the whole plant anyway (#70, accepted).

## When to revisit

- when a device makes the §8 `backup_key` (then encrypt to that public key with §20 ECIES, and the server needs no
  secret at all);
- if the sheet backups or the working copy leave the server (copied elsewhere).

Sources: `platform/linux/kks_server.nim`, `platform/linux/src/kksl/server.nim`, `core/src/kks/bundle.nim`,
`core/src/kks/extras.nim` (`passphraseSeal`), decisions 0020, 0023.
