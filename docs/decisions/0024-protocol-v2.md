# 0024 Protocol v2: what changes, what stays

Date 2026-09-30 · Scope: docs/PROTOCOL.md (all sections); R10–R17, R21, R22 · Status: **accepted by the user 2026-09-30**

The protocol is open (docs/m6/README.md). The question is whether today's model (signed per-device append-only logs,
deterministic replay and merge, roles and approvals as log entries) is still the right answer from scratch, and what
the decisions 0015–0023 force to change.

**Is the model still right?**
- Requirements R10–R15 ask for:
  - changes attributable to a person and a device, tamper-evident;
  - full offline work;
  - deterministic merging with no central server;
  - roles, approvals and revocation.
- No platform provides a replicated, signed, authorization-aware store.
- General merge libraries (CRDT libraries such as Automerge or Yjs) are not platform-provided, and have no signatures
  or authority rules. We would still write the authority layer ourselves.
- So the model stays. It is the product's own logic, and it is platform-independent code (the policy's "pure
  business logic").

**Section by section:**

| PROTOCOL.md | v2 | Why |
|---|---|---|
| §1 Canonical encoding (JCS subset, integers only, ASCII keys) | **keep** | Every target parses JSON with a platform parser: Windows.Data.Json, json-glib, org.json, `JSON.parse` [K]. Only the canonical writer is ours, and it is small. |
| §2 Keys and peer IDs | **change:** ECDSA P-256 (0017). Refined when the spec was written (2026-09-30): peer ID = base64url of the first 24 bytes of SHA-256 of the **uncompressed** key (the form every platform API accepts), 32 characters; the key itself is carried in each device's **seq-1 entry**, so chains stay self-verifying. See docs/PROTOCOL-v2.md §2, §3. | Platform crypto and hardware key stores (0017) |
| §3 Entries | **change:** `v: 2`; signed bytes prefix `kks-log-v2\n`; signature = ECDSA P-256/SHA-256, IEEE P1363 (r‖s), low-S; **entry ID = SHA-256 of the canonical entry *without* `sig`** | ECDSA signatures are randomized and malleable, so the ID must not depend on them |
| §4 Chains, forks | **keep** | A fork is still two different *contents* at the same seq. A re-signed identical content is no longer a fork. |
| §5 Hybrid logical clock, §6 total order, §7 error codes | **keep** | |
| §8 Root statements | **keep**, P-256 root key; **add** the `migrated` checkpoint (below) and a `backup_key` statement (0020: backups encrypted to the manager's backup key) | |
| §9–§12 Bodies, authority, replay, merge | **keep** as they are; they encode R10–R12. Plant-data bodies reference the new file kinds (§19). | |
| §13 Private entries | **change** the cipher to AES-256-GCM (0017) | Safari has no ChaCha |
| §14 Replay output | **keep** | |
| §15 Sync between devices | **change the channel:** TLS 1.3 (1.2 on Windows 10) with mutual authentication; each side presents a self-signed certificate for its device key, accepted only if that key is a certified, unrevoked device of the same plant. **The message layer stays:** hello, version vectors, entries, want/blobs, bye. | 0017: platform TLS replaces our Noise |
| §16 Join by invite | **keep** the flow; the invite is signed with P-256. The joining device's first contact uses TLS with the invite's one-time token instead of a pinned key. | |
| §17 Person secrets | **keep**, over TLS | |
| §18 Internet sync (relay, hole punching, reliable UDP) | **keep**; TLS runs over the relay pipe or over our reliable UDP. The relay still sees only encrypted bytes. | No platform QUIC on GNOME; Windows' MsQuic isn't a public OS API; Android's needs Play services (0013) |
| §19 Plant data | **change the file kinds:** per sheet a **grid-indexed path store** (0015, with a specification and test vectors) and an **overview image pyramid** (0016), lossless JPEG XL (0018). The original PDF stays in the set as the source of record; tags, locations and procedures stay JSON. | |

**Migration (one time, done by the manager):**
1. A migration tool reads each existing v1 log, verifies it completely (Ed25519, chains, replay), and refuses to go on
   if anything fails.
2. It creates the new P-256 root key.
3. It writes one root-signed `migrated` statement containing:
   - the hash of the complete v1 history;
   - the list of v1 device IDs mapped to their new P-256 device keys;
   - the replayed state.
4. v2 devices start from that statement. The old v1 logs are kept, read-only, in an archive for audit, with the
   Ed25519 verifier kept only in the migration tool.
5. Every device re-joins once with its new key: through its person's password on the server, or by QR, as in R13.

**Test vectors:**
- New v2 vector files (encoding, entries, replay, sync, path store). v1–v4 stay frozen as the record of v1.
- Every implementation (desktop language, Kotlin on Android, the server, the browser client's parts) must pass them
  byte for byte, as the Kotlin port does today.

**Costs:**
- Every device re-joins once.
- A new specification for the path store.
- TLS profile work on four platforms (0017).

**Revisit:** if a replicated-store library with signatures and authorization rules appears, and passes the
maintenance test.

Sources: docs/PROTOCOL.md; docs/decisions/0013, 0015–0020; https://noiseprotocol.org/noise.html §12
