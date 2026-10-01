# The Nim core

The sans-I/O core of M6 (docs/decisions/0027, 0029), shared by the Windows, GNOME and Android apps and the server.
It holds:
- protocol v2: canonical and strict JSON, keys, entries, chains, clock, order, replay, join, relay, ECIES, backups;
- the `.kkp` path store;
- the course format: validator and figure evaluator.

It has no sockets, files, threads or key stores. Crypto comes through the provider interface in `crypto.nim`; each
platform supplies one.

| module | what | spec | vectors |
|---|---|---|---|
| `json.nim` | strict reader, canonical writer | PROTOCOL-v2 §1 | v2-json, v2-core (canonical) |
| `crypto.nim` | provider interface; low-S, HKDF, DER ↔ r‖s | §2, 0029 | — |
| `provider_gnutls.nim` | the GNOME/Linux provider (GnuTLS ≥ 3.8.2) | 0029 | all of the below |
| `proto.nim` | keys, peer IDs, entries, chains, HLC, order | §2–7 | v2-core |
| `replay.nim` | replay, state bytes, private entries | §8–14, §21 | v2-replay, v2-malformed |
| `extras.nim` | join codes and requests, relay, ECIES, passphrase backup | §16, §18, §20 | v2-crypto |
| `pathstore.nim` | `.kkp` decode and encode, grid rules | docs/PATHSTORE.md | pathstore-v1 |
| `courses.nim` | course validator, figure evaluator | docs/COURSES.md | courses-v1 |
| `util.nim` | hex, base64url | | |

**Run the tests:**
- Needs Nim ≥ 2.2 and the GnuTLS and zlib headers (`libgnutls28-dev`, `zlib1g-dev` on Debian/Ubuntu).
- Command: `cd core && nim test`.
- The tests read the shared vector files in `ref/vectors/` with the core's own reader.

**Measured 2026-09-30** (this desktop, release build):
- **Replay** of 2019 entries: 282 ms.
  - 222 ms of that is ECDSA verification in GnuTLS, at 0.11 ms per signature.
  - A node verifies each entry once, when it arrives, and replays its own store as trusted.
- **Path store:** decode of the 11 plant sheets takes 14–55 ms each. Re-encoding reproduces the Python reference's
  bytes exactly (a local check against /tmp files; plant data never enters the repository).
- **Figures:** 8–79 µs per frame for the 16 course figures. All 16 match the Python evaluator frame by frame (local
  check with tools/m6/course_figures.py).
