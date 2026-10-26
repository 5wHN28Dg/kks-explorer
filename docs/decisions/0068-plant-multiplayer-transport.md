# 0068 Walkdown Plant multiplayer: invite-code keys, our own packets over LAN UDP, direct UDP and a new free-plan relay

Date 2026-10-26 · Scope: docs/plant3d/MULTIPLAYER.md §1, §2, §9, §10; the app's session layer; a new `relay-plant/`
(Worker, twin, tests); the packages' permissions · Status: **proposed**, written before any code under the user's
decisions of 2026-10-26 (serverless like Walkdown; a new Cloudflare Worker relay on the free plan only, separate from
Walkdown's, its URL never in tracked files; direct UDP when the network allows; the network only while a session is
open; LAN for local play) · Extends 0012, 0050, 0054 (§8 changes: the app gains network permissions); no new
dependency

**Question:** how do players find and join a session, how are its messages protected end to end (the relay
included), and which paths carry them, on Android, Linux and Windows, from GDScript, at no cost?

## Findings per target

Godot 4.7 is the same on the three targets for everything in the first rows; the platform rows differ.

| | Finding | Source |
|---|---|---|
| Sockets | `PacketPeerUDP` (broadcast with `set_broadcast_enabled`), `UDPServer`, `StreamPeerTCP`, `WebSocketPeer` (wss through mbedTLS) | [S] 4.7 doc/classes |
| Crypto in GDScript | `Crypto`: random bytes, HMAC, RSA key generation, sign/verify with RSA or an EC key loaded from PEM, RSA encrypt; `HMACContext` (SHA-1, SHA-256); `HashingContext`; `AESContext` **ECB and CBC only**; no ECDH, no Ed25519/X25519, no AEAD; `PacketPeerDTLS`/`StreamPeerTLS` with certificates only (no PSK) | [S] 4.7 Crypto.xml, CryptoKey.xml, AESContext.xml, HMACContext.xml, PacketPeerDTLS.xml |
| A standard AEAD from those | RFC 7518 §5.2.3 AEAD_AES_128_CBC_HMAC_SHA_256: AES-128-CBC + HMAC-SHA-256 truncated to 16 bytes, encrypt-then-MAC, test vector in Appendix B.1 | RFC 7518 |
| Key derivation | HKDF (RFC 5869) needs only HMAC-SHA-256; test cases in its Appendix A | RFC 5869 |
| Walkdown's identity | device keys, root-signed certificates, the log, TLS with pinned peer IDs (PROTOCOL-v2 §2, §15, §16) and the relay room key (0050): all in the Nim core, which the plant app doesn't link (0054 §2) | PROTOCOL-v2, 0050, 0054 |
| Walkdown's relay | a Worker with one Durable Object per room, hibernating WebSockets, auto-answered pings, a Python twin with the same protocol | relay/src/index.js, relay/twin.py, 0012 |
| Free plan | Durable Objects: 100,000 requests and 13,000 GB-s a day, SQLite storage 5 GB; incoming WebSocket messages 20 to a request, outgoing and protocol pings free; auto-responses not billed; past a limit operations fail until 00:00 UTC | [D] developers.cloudflare.com/durable-objects/platform/pricing |
| Rate limiting binding | periods of 10 or 60 s, per Cloudflare location, approximate; the page doesn't say whether the free plan has it | [D] developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit |
| Hole punching | Walkdown's direct path: STUN (stun.cloudflare.com, stun.l.google.com), candidates through the relay, punching; per-destination carrier NATs can't be punched, so phones on mobile data often use the pipe | PROTOCOL-v2 §18, kksl/udp.nim, CLAUDE.md lessons |
| QR | Godot has no QR class; a phone's camera app opens a `walkdown-plant://` link, which the app already handles (0056) | [S] 4.7 doc/classes; 0056 |
| Android | `INTERNET` and `CHANGE_WIFI_MULTICAST_STATE` are normal permissions granted at install; broadcasts may be filtered without a `MulticastLock`; Android 17's `ACCESS_LOCAL_NETWORK` binds apps targeting SDK 37, while Godot 4.7's template targets 36 (implicit grant with `INTERNET`) | [D] developer.android.com local-network-permission, WifiManager.MulticastLock; [S] 4.7 platform/android/java/app/config.gradle |
| Linux (Flatpak) | `--share=network` is a static permission | [D] Flatpak sandbox permissions |
| Windows (MSIX) | `internetClient`, `privateNetworkClientServer` capabilities; a full-trust desktop app listening may get the firewall prompt (to check in the VM) | [D] learn.microsoft.com app capability declarations |

## Alternatives

- **Keys:** (a) Walkdown's identity, through a GDExtension of the Nim core: 0054 §2's four native builds for a
  feature with no lasting identity; (b) libsodium in a GDExtension (X25519, Ed25519, XChaCha20-Poly1305): a new
  dependency, and nothing in a one-hour session of classmates needs asymmetric identity; (c) **keys derived from the
  invite code**, a standard AEAD built from Godot's own primitives, a per-player key for the player-to-host path.
- **Transport:** (a) Godot's ENet or WebRTC peers: ENet has no relay path and no end-to-end encryption through one;
  WebRTC is an extension with its own native builds and needs a signalling server anyway; (b) **our own packets** over
  `PacketPeerUDP` (LAN and direct) and `WebSocketPeer` (relay), one format on every path.
- **Relay:** (a) reuse Walkdown's deployed relay: the user wants it separate, and its rooms admit only plant devices
  (0050); (b) **a new Worker** built the same way.

## Choice

- **Keys (c):** a 16-character code (75 random bits and a check), HKDF-SHA-256 to `room`, `admit` and K; P per player
  sent in `hello`; RFC 7518's AES-128-CBC-HMAC-SHA-256 on every packet with the header as AAD; replay windows. What it
  does not protect against (one member forging the host on a LAN path) is detected by the digests and accepted
  (MULTIPLAYER.md §1.3, §10). Removal moves the session to new keys.
- **Transport (b):** LAN UDP with beacons on port 47820 (the code finds its session), direct UDP between each player
  and the host after STUN and punching as Walkdown does, the relay otherwise; reliability by acks and RFC 6298
  retransmission over every path, so a player moves between paths without losing a message.
- **Relay (b):** `relay-plant/`, a Worker with one Durable Object per room, hibernating WebSockets, rooms created with
  SHA-256(admit), relay IDs on every message, the limits of §9.1 (9 sockets, 64 KiB, 60 msg/s, 24 h, empty rooms
  deleted after 10 min); `relay-plant/twin.py` as its twin; deployed only on a free-plan account, checked by the
  deploy step; its URL in `CLAUDE.local.md` and an ignored build file. Estimated 8–14 hours of 8-player relay play a
  day within the free plan (§9.1), measured in MP4.
- **Permissions:** Android `INTERNET`, `CHANGE_WIFI_MULTICAST_STATE`; Flatpak `--share=network`; MSIX `internetClient`,
  `privateNetworkClientServer`. None can be granted only during a session; the app opens no socket outside one, and a
  test checks it. 0054 §8 is amended accordingly.

## When to revisit

- if trainees outside one class use it (strangers in a session): then per-player identity (libsodium or the core);
- if the free plan's allowance is reached in practice (MP4's counts) or Cloudflare changes it;
- if the app moves to target SDK 37 (the local network permission at run time);
- if the rate limiting binding turns out to be unavailable and rooms are abused.

Sources: https://www.rfc-editor.org/rfc/rfc7518#section-5.2.3 · https://www.rfc-editor.org/rfc/rfc5869 ·
https://developers.cloudflare.com/durable-objects/platform/pricing/ ·
https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/ ·
https://developer.android.com/privacy-and-security/local-network-permission ·
https://developer.android.com/reference/android/net/wifi/WifiManager.MulticastLock ·
https://docs.flatpak.org/en/latest/sandbox-permissions.html ·
https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations ·
https://github.com/godotengine/godot/tree/4.7-stable/doc/classes · relay/src/index.js, relay/twin.py,
docs/PROTOCOL-v2.md §18, platform/linux/src/kksl/udp.nim.
