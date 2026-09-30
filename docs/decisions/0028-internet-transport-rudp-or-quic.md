# 0028 Internet transport: our reliable UDP, or a QUIC library

Date 2026-09-30 · Scope: R17 (sync across the internet), PROTOCOL §18 · Status: **accepted by the user 2026-09-30 (option A, with the field test before cutover)**

**Where it's used:** only on the internet path, when devices are not on the same Wi-Fi.
- On the LAN, sync is TCP + TLS.
- On the internet, devices first try a direct UDP path through NAT hole punching. If that fails, they use the
  relay's WebSocket pipe (TCP).
- The UDP path needs reliability and ordering on top of UDP. Today that's our reliable UDP: about 290 lines each in
  Python and Kotlin, with SACK, RFC 6298 timeouts, a window halved on loss and fast retransmit. Tests cover 3 MB
  transfers at 2–20 % loss. **Real NATs and mobile data are untested.**
- Hole punching itself is ours either way; QUIC doesn't do it.

**What the platforms provide:**

| | QUIC for our own protocol |
|---|---|
| Windows | ❌ Windows 11 has MsQuic only as a kernel driver (`msquic.sys`) for HTTP and SMB. Apps must ship `msquic.dll` themselves; Microsoft: "there is no plan to ship msquic.dll in Windows" [D] |
| GNOME / Linux | 🟡 OpenSSL 3.5 has a QUIC client and server (3.5.5 installed here [V]); not in GLib/GIO |
| Android | ❌ no general QUIC API; Cronet needs Play services (optional) [K] |
| Browser | 🟡 WebTransport is client-to-server only (not device to device) [D] |

**Libraries** (GitHub, 2026-09-30):

| Library | State | Notes |
|---|---|---|
| MsQuic (Microsoft) | v2.6.1 2026-08-28, 16 authors, MIT | C API, cross-platform. TLS through Schannel (Windows 11 only, since it needs TLS 1.3) or OpenSSL, which would be bundled on Windows 10 and Android |
| OpenSSL QUIC | OpenSSL 4.0.3 2026-09-29, 30 authors, Apache-2.0 | system library on Linux only; bundled elsewhere |
| ngtcp2 | v1.25.0, **essentially one maintainer** (98 of 100 recent commits) | needs a TLS backend |
| quiche (Cloudflare) | 0.30.0, 22 authors | Rust + BoringSSL |
| lsquic, picoquic | active, small teams | BoringSSL / picotls |

**Options:**
- **A. Keep our reliable UDP,** ported once to Nim (one implementation instead of two, 0027), with the platform's TLS
  on top (0017).
  - Small, and already tested under loss.
  - Device keys stay in the hardware key stores through the platform TLS.
  - Risk: our own loss recovery and congestion control are less proven than QUIC's, and real NATs are untested.
- **B. MsQuic on every native target** (bundled; Schannel on Windows 11, bundled OpenSSL on Windows 10 and Android,
  system OpenSSL on Linux).
  - Proven transport: congestion control, connection migration when a phone changes networks, streams.
  - Costs:
    - a large bundled dependency plus OpenSSL on two targets;
    - QUIC carries its own TLS, so **the Android Keystore and Windows TPM device keys would need custom signing hooks**
      inside that TLS (an OpenSSL provider on Android; Schannel only on Windows 11). This works against 0017.
- **C. OpenSSL QUIC:** as B but OpenSSL everywhere; platform-provided only on Linux, and the same key-store problem.

**Recommendation: A**, with a measured trigger to switch:
- The internet path is the fallback path, and its traffic is small: entries, occasional photos, plant data once.
- A keeps the hardware-backed keys that 0017 was chosen for.
- **Test it in the field before cutover:** sync between the Note 9 on mobile data and a laptop behind the plant or
  home NAT. Measure success rate, time for a day's changes, and a 10 MB plant-data transfer.
- If the direct path fails or is slow where the relay pipe isn't, switch to B (MsQuic) and accept its key-store
  costs.

**Revisit:**
- after the field test;
- if Android or Windows ship a QUIC API for apps.

Sources: https://github.com/microsoft/msquic/blob/main/docs/FAQ.md · https://microsoft.github.io/msquic/msquicdocs/docs/Platforms.html ·
https://github.com/openssl/openssl/blob/master/README-QUIC.md · https://www.phoronix.com/news/OpenSSL-3.5-Released ·
GitHub repositories microsoft/msquic, ngtcp2/ngtcp2, cloudflare/quiche, litespeedtech/lsquic, private-octopus/picoquic,
openssl/openssl (queried 2026-09-30); docs/decisions/0013, 0017, 0027; PROTOCOL.md §18
