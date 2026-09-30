# 0017 Crypto primitives and the secure channel

Date 2026-09-30 · Scope: R11, R13, R15–R17, N1, N1a (signed history, device keys, sync encryption, encryption at
rest) · Status: **accepted by the user 2026-09-30 (option B)**

**Today:**
- Ed25519 signatures;
- X25519 + ChaCha20-Poly1305 inside our own Noise_XX implementation;
- a BouncyCastle fallback on Android;
- the Python `cryptography` package on desktops.

The protocol is open (docs/m6/README.md), so the algorithms are a choice, not a given.

**What each target provides (docs/m6/CAPABILITIES.md §4, plus this session's checks):**

| Primitive | Windows 10/11 | GNOME | Android 10+ | Safari 17+ |
|---|---|---|---|---|
| Ed25519 | ❌ | ✅ Nettle | ❌ below API 33 | ✅ |
| **ECDSA P-256** | ✅ CNG [K] | ✅ Nettle/GnuTLS [K] | ✅, **in the hardware Keystore from API 23** [D] | ✅ WebCrypto [K] |
| X25519 | ✅ CNG | ✅ | ❌ below API 33 | ✅ |
| **ECDH P-256** | ✅ CNG [K] | ✅ | ✅ in software; inside the Keystore only from API 31 [D] | ✅ |
| ChaCha20-Poly1305 | ✅ | ✅ | ✅ | ❌ |
| **AES-256-GCM** | ✅ | ✅ | ✅ (Keystore too) | ✅ |
| SHA-256, HMAC, HKDF | ✅ (CNG HKDF [K]) | ✅ | ✅ (HKDF is a few lines over HMAC) | ✅ |
| **TLS stack** | ✅ Schannel: TLS 1.2 on Windows 10, **TLS 1.3 from Windows 11** [D] | ✅ GnuTLS / GIO `GTlsConnection` [K] | ✅ Conscrypt `SSLEngine` [K] | ✅ (to the server, HTTPS) |
| Noise protocol | ❌ | ❌ | ❌ | ❌ |

Noise itself defines only the 25519 and 448 curves [D], so leaving 25519 means leaving Noise.

## Options

**A. Keep today's set (Ed25519 / X25519 / ChaCha20-Poly1305 + our Noise):**
- Two targets need a crypto library (Windows, Android 10–12).
- Safari can't do ChaCha.
- Device keys can't live in the hardware key stores: Android Keystore and Windows TPM hold P-256, not Ed25519.
- We keep maintaining our own Noise.

**B. P-256 set on the platform's own TLS (proposed):**
- **Signatures:** ECDSA P-256 with SHA-256.
  - Entry IDs are computed over the *unsigned* content, so ECDSA's signature malleability can't change an ID.
  - Signatures are normalized to low-S.
- **Key agreement and encryption:**
  - ECDH P-256 + HKDF-SHA256 + AES-256-GCM, for encrypting to a device (plant key for encryption at rest,
    private entries);
  - AES-256-GCM for data at rest.
- **Device keys in hardware where the platform offers it:**
  - Android Keystore (TEE or StrongBox);
  - Windows TPM through the Platform Crypto Provider [K];
  - on GNOME a software key sealed by libsecret (no hardware key store in the platform);
  - in the browser a non-extractable WebCrypto key.
  - A stolen phone's key then cannot be copied off it at all, which strengthens N1 and the revocation story (R13).
- **Channel:** the platform's TLS (1.3 where available, 1.2 with ECDHE-ECDSA-AES-GCM on Windows 10).
  - Mutual authentication: each device presents a self-signed certificate for its device key.
  - Each side accepts the peer only if that key is a certified, unrevoked device of the same plant in the signed
    history (key pinning, not certificate authorities).
  - TLS runs over TCP on the LAN, and over the relay pipe or our reliable UDP on the internet path. All three TLS
    stacks can run over a custom byte stream.
- **Result:** every primitive and the channel are platform-provided on all four targets at our minimum versions. No
  crypto library, no own handshake code.

**Costs of B:**
- **ECDSA needs a good random source.** The platform RNGs provide it.
- **Two protocols to learn:** TLS certificate plumbing differs per platform (a thin adapter each), and TLS carries
  more options than Noise, so we pin a narrow profile.
- **Migration:** existing entries are signed with Ed25519.
  - A one-time migration tool verifies the old history with Ed25519.
  - The root then signs a checkpoint (the hash of the migrated history) with the new P-256 root key.
  - After that, only P-256 is needed on devices. The old signatures stay archived for audit.
- **The frozen vectors (v1–v4) and the Kotlin port are replaced** by a new vector set for B.

**Recommendation:** B. It is exactly the policy's case: the platforms provide the whole stack, including hardware
key protection that option A cannot use.

**Revisit:**
- if Windows 10 support is dropped (then TLS 1.3 everywhere);
- if Ed25519 reaches every platform's hardware key store.

Sources: https://noiseprotocol.org/noise.html §12 · https://developer.android.com/reference/android/security/keystore/KeyProperties ·
https://learn.microsoft.com/en-us/windows/win32/secauthn/protocols-in-tls-ssl--schannel-ssp- · docs/m6/CAPABILITIES.md §4
