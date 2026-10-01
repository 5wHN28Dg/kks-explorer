# 0029 Nim core: crypto provider, JSON, zlib, bindings, tests

Date 2026-09-30 · Scope: phase 2 (the sans-I/O core of 0027), all native targets · Status: **accepted by the user 2026-09-30**

**Question.** The core (0027) needs:
- the 0017 primitives: SHA-256, HMAC, HKDF, PBKDF2, ECDSA P-256, ECDH P-256, AES-256-GCM and randomness;
- a JSON reader and writer;
- deflate (the path store, 0015);
- C bindings for all of the above;
- a test runner.

Which provides each, per target?

**Findings** ([V] = checked on this machine 2026-09-30, [D] = vendor documentation or repository):

| Need | Windows | GNOME / Linux | Android | Choice |
|---|---|---|---|---|
| Crypto primitives | CNG (bcrypt.h) [D] | **GnuTLS ≥ 3.8.2**: raw ECC keys, sign/verify, `gnutls_privkey_derive_secret` (ECDH, added in 3.8.2), HKDF, PBKDF2, AEAD, `gnutls_rnd` [V: headers of 3.8.12]. Nettle has the same primitives one level lower. | Java through JNI: `Signature`, `KeyAgreement`, `Cipher`, Keystore [D] | A **provider interface**: the core calls it, and each platform implements it with its own library. |
| TLS (for later) | Schannel | GnuTLS (GIO's backend) | Conscrypt | unchanged (0017) |
| JSON | — | — | — | **Our own strict reader and writer** in the core (see below) |
| Deflate | none in the Win32 API → link zlib (0015) | system zlib [V: 1.3.1] | NDK `libz` (a stable NDK API) [D] | the core links **zlib**'s C API directly |
| Bindings | | | | hand-written `importc` with the `header` pragma for small surfaces (GnuTLS subset about 30 functions, zlib 4) |
| Tests | | | | Nim's `std/unittest`, run by `nim` with a `config.nims`; no Nimble packages |

**Why GnuTLS on GNOME, not Nettle:**
- The GNOME app needs GnuTLS for TLS anyway (GIO's TLS backend).
- Using it for the primitives means one crypto library, not two.
- Maintenance (GitLab, 2026-09-30): releases 3.8.9 (2025-02), 3.8.10 (2025-07), 3.8.11 (2025-11), 3.8.12 (2026-02)
  and 3.8.13 (2026-04). Commits in the last 12 months: Daiki Ueno 57, Alexander Sosedkin 14, David Dudas 14, Tim
  Rühsen 10, and others. Security advisories are published per release (5 CVEs fixed in 3.8.13). LGPL-2.1+,
  compatible with AGPL-3.0. ✅ on every criterion.
- Nettle, by contrast, has mostly one maintainer.

**Why our own JSON reader.** Nim's `std/json` is too lax for signed data [V, test 2026-09-30]:
- duplicate keys: the last one silently wins;
- `[1,]` and `01` are accepted;
- raw control characters are accepted inside strings;
- integers above 64 bits turn into strings.

If one implementation takes the first of two duplicate keys and another the last, the same bytes are one entry on one
device and a different entry on another. PROTOCOL-v2 §1 lets readers use "the platform's JSON parser", and no vector
tests wire bytes, so today the spec allows that divergence.

**Proposed:**
- **PROTOCOL-v2 §1 gets a strict-reading rule.** Readers reject:
  - duplicate keys;
  - trailing commas;
  - leading zeros;
  - raw control characters;
  - unpaired surrogates;
  - bytes after the value;
  - numbers the protocol can't carry (§1 already).
- A new vector file, `ref/vectors/v2-json.json`, holds byte strings to accept (with their value) or reject. The Kotlin
  port's own parser (M3) already rejects most of these.
- The reader is about 300 lines in the core.

**Why a provider interface for crypto, not linking one library everywhere:**
- 0017's point is that each platform supplies the primitives, and on Android and Windows the device key lives in the
  hardware key store. The core must therefore call out for signing anyway.
- Verification and hashing go through the same interface, so there is one seam, tested with the vectors on every
  platform.
- **Cost on Android:** replay verifies each entry through JNI. That is microseconds per call against about 0.1 ms per
  P-256 verification; 20 000 entries add about 0.1 s. Not measured yet; it will be measured on the Note 9 in M3's
  successor.

**What stays in the core:**
- **Low-S normalization:** s ← n − s is a 256-bit subtraction.
- **Canonical encoding.**
- **Signature bytes:** DER ↔ r‖s conversion, for providers whose platform returns DER (Java, GnuTLS).

**Bindings:** 0027 names futhark for generating bindings. For surfaces this small, hand-written declarations with the
`header` pragma are simpler and still checked: the generated C includes the real header, so a wrong signature fails
the C compile. Futhark stays the plan for GTK and Win32.

**Revisit:**
- if GnuTLS drops the raw-key APIs;
- if the JNI round trip is measurably slow on the Note 9;
- if Nim's `std/json` gains a strict mode.

Sources: https://gitlab.com/gnutls/gnutls (tags, NEWS, commits, queried 2026-09-30) · /usr/include/gnutls/*.h (3.8.12) ·
https://developer.android.com/ndk/guides/stable_apis (zlib) · https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/ ·
docs/decisions/0015, 0017, 0027
