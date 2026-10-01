# 0030 Linux platform layer and the server's process model

Date 2026-10-01 · Scope: phase 3 (server, GNOME app), N1a, N6 · Status: **decided by Claude under the user's
instruction "don't stop unless it needs my decision" (2026-10-01). Each choice follows an earlier decision; the user can
revisit any of them.**

**Question.** The Nim core (0029) is sans-I/O. What carries it on Linux? The parts are storage, TLS, sockets, mDNS,
HTTP for the web UI, and Argon2id. And how does the server avoid sharing the node between threads?

**Findings** ([V] = checked on this machine 2026-10-01, Ubuntu with GNOME; [D] = vendor documentation):

| Need | Linux provides | Choice |
|---|---|---|
| Storage | SQLite 3.46 [V] (0020: platform SQLite) | the SQLite C API, hand-written bindings with the `header` pragma (about 15 functions) |
| Encryption at rest (0020) | libsecret 0.21 on GNOME [V]; `systemd-creds` on the server [D] | the AES-GCM layer in the store, with bodies and blobs sealed by a per-device storage key; the key is unwrapped by the key-store adapter (libsecret / systemd-creds), and a key file in tests |
| TLS (0017) | GnuTLS 3.8.12 [V] | GnuTLS with **custom pull/push functions**: TLS is driven from buffers. The same code then runs over TCP, our reliable UDP or the relay pipe, and can be tested in memory. Self-signed X.509 certificates from the device key (`gnutls_x509_crt_sign2`); our verify function pins the peer ID. |
| Sockets, timers | POSIX through Nim's `std/asyncdispatch` | async, single-threaded (below) |
| HTTP for browser clients | — | Nim's `std/asynchttpserver` (in the compiler's own repository, released with it). HTTP/1.1 only: it sits on the LAN or behind Cloudflare Tunnel (docs/REMOTE_ACCESS.md), never directly on the internet. |
| Argon2id (0023) | OpenSSL ≥ 3.2 `EVP_KDF` "ARGON2ID" [V: 3.5.5] | libcrypto, server only; run on a worker thread (about 0.3–1 s per hash) |
| mDNS (0002: the OS service) | avahi-daemon running [V]; `libavahi-client.so.3` installed, its headers not [V] | Avahi's **D-Bus API** through GIO's GDBus (GIO 2.88 [V]; GNOME has it anyway, and headless servers usually do). No new library. |

**Process model.** One thread owns the node, and everything else talks to it on that thread:
- a single-threaded `asyncdispatch` loop for HTTP, sync connections, timers and mDNS;
- CPU-heavy work goes to worker threads that receive and return copies (strings), never shared references:
  - Argon2id;
  - JPEG XL encoding;
  - the importer runs as a separate process anyway.

Nim's ORC reference counting isn't atomic, so sharing the node between threads would mean a lock on every access. v1
had exactly that, and deadlocks came from it on Android (CLAUDE.md, field test fixes). A single owner removes that
class of bug.

**The cost:**
- A big ingest (thousands of entries: about 0.1 ms of ECDSA each, 0029) blocks the loop for a fraction of a second.
  For a team of 100 and 200 devices that is acceptable.
- If it shows in measurements, verification moves to the worker pool (entries are plain JSON text, so they are easy
  to hand over).

**Development headers.** This machine has the runtime libraries but not the `-dev` packages:
- gtk4, libadwaita, libjxl, zxing, avahi-client, mupdf;
- no root here, so for local builds `apt-get download` + `dpkg-deb -x` unpacks them into `~/.local/kksdev`;
- CI installs them normally.

**Revisit:**
- if HTTP/2 or HTTPS termination on the server itself becomes necessary;
- if async + GnuTLS through buffers costs measurably more than blocking sockets.

Sources: `pkg-config` and `/usr/lib/x86_64-linux-gnu` on this machine (2026-10-01) · https://gnutls.org/manual/html_node/Setting-up-the-transport-layer.html ·
https://nim-lang.org/docs/asynchttpserver.html · https://docs.openssl.org/3.2/man7/EVP_KDF-ARGON2/ ·
https://github.com/avahi/avahi/tree/master/avahi-daemon (org.freedesktop.Avahi D-Bus API) · docs/decisions/0002, 0017, 0020, 0023, 0026, 0029
