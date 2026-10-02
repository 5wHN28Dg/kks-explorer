# 0038 v2 internet sync: the relay pipe first, on every native target

Date 2026-10-02 · Scope: R17 (sync across the internet), PROTOCOL-v2 §18; decisions 0012, 0017, 0028 · Status:
**decided by Claude under the user's standing instruction to continue**; deploying the Worker was approved by the user
2026-10-02.

**Question:** the v2 apps had no internet sync. The user asked to test the Honor 600 on mobile data. What does each
target provide for a WebSocket to the relay over TLS with normal web trust (a CA chain plus the host name), and how
does our sync TLS (P-256 device keys, peer ID pinning, 0017) run inside a relay pipe?

## Findings

| Need | Linux / GNOME (GnuTLS 3.8) | Windows 10/11 (Schannel) | Android 10+ (Conscrypt) |
|---|---|---|---|
| WebSocket client | none in GLib's C API that runs on our asyncdispatch loop | WinHTTP has WebSockets but runs on its own threads and callbacks | none in the SDK (OkHttp is a dependency) |
| Web trust (wss://) | `gnutls_certificate_set_x509_system_trust` + `gnutls_session_set_verify_cert(host)` + SNI [D, V: refuses expired.badssl.com and wrong.host.badssl.com] | `SCH_CRED_AUTO_CRED_VALIDATION` with the host as the target name [D, V: the same two refusals on 10 and 11] | `SSLSocketFactory.getDefault()` + `endpointIdentificationAlgorithm = "HTTPS"`: a layered SSLSocket checks **no host name** by itself [D] |
| Sync TLS inside the pipe | the buffer-driven `kksl/tls` already runs over any byte stream | the buffer-driven `kksw/tls` the same | an `SSLEngine` from the sync's SSLContext; a layered SSLSocket wants a real socket's file descriptor underneath [D] |
| Revocation checks | not by default | not with auto validation unless asked | platform default |

Sources: GnuTLS manual, "Verifying a certificate in the context of TLS session" (https://www.gnutls.org/manual/html_node/Certificate-verification.html)
· SCH_CREDENTIALS (https://learn.microsoft.com/windows/win32/api/schannel/ns-schannel-sch_credentials) ·
SSLParameters.setEndpointIdentificationAlgorithm (https://developer.android.com/reference/javax/net/ssl/SSLParameters)
· SSLEngine (https://developer.android.com/reference/javax/net/ssl/SSLEngine). [V] = ran here or in the VMs.

## Choice

- **Our own small WebSocket client on each target** (`platform/linux/src/kksl/ws.nim`, shared by Linux and Windows;
  Kotlin `WsClient` from the v1 app): RFC 6455 text/binary/ping/close, about 200 lines each. No new dependency (0013
  already lists our WebSocket clients).
- **TLS through the platform** in web mode (table above). No dependency, the platform's CA store and updates.
- **The pipe carries the same TLS session as a LAN sync** (`syncOver`/`serveOver` in `net.nim`; Kotlin
  `Net.overPipe` on an SSLEngine): the relay sees only ciphertext. Device keys stay in their key stores (0017).
- **Pipe only for now:** this side offers no candidates (`cand: []`), and PROTOCOL-v2 §18 now says an empty list on
  either side means both go straight to the pipe. Hole punching + reliable UDP (0028, option A) come later; 0028's
  field test still stands.
- **The Worker accepts v2 hellos** (P-256 ECDSA, raw r‖s, peer ID = 24 bytes of SHA-256 of the key) next to v1's
  Ed25519 ones; the v1 Python tests pass against it under `wrangler dev`.

## Results 2026-10-02

- Nim `platform/linux/tests/test_internet.nim` (presence, both directions through the pipe, an absent device, leaving):
  passes against the Python twin, the Worker under `wrangler dev`, and the deployed Worker over wss, on Linux,
  Windows 10 (TLS 1.2) and Windows 11 (TLS 1.3).
- Android: the Note 9 synced with the server through a local relay with the server's LAN port closed; the Honor 600 on
  **mobile data only** (Wi-Fi off, carrier NAT) synced both ways with the server through the deployed Worker (a
  server change arrived; the phone's edit was on the server 7.2 s after Save).
- Bugs found and fixed:
  - GnuTLS returns "again" after a TLS 1.3 session ticket while more records wait; the 101 answer sat unread.
  - The WebSocket connect loop sent the handshake's output only after the next read: TLS 1.2 (Windows 10) hung.
  - The Worker never said `left`: workerd still lists the closing socket during `webSocketClose`.
- Not done: the GNOME/Windows/Android UIs have no field for the relay address (the manager sets it in the server's
  web page, Manage → Devices); a phone on mobile data still tries remembered LAN addresses first (15 s each when they
  time out instead of being refused).

**When to revisit:** with 0028's field test (direct UDP path); if Android ships a WebSocket API; if a platform stops
providing web trust this way.
