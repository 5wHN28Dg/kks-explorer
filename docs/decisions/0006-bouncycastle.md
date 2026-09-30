# 0006 BouncyCastle (Android and Kotlin core)

Date 2026-09-30 · Scope: `android/core` Crypto.kt · Status: keep, **update**, and move ChaCha20-Poly1305 to the platform

**Needed for:** Ed25519, X25519 and ChaCha20-Poly1305; HMAC already comes from `javax.crypto`.

**What Android provides (API reference):**

| Algorithm | Available from | Our minimum (API 29, Android 10) |
|---|---|---|
| ChaCha20-Poly1305 (`Cipher` `ChaCha20/Poly1305/NoPadding`) | API 28 | available everywhere |
| Ed25519 (`Signature`) | API 33 | missing on API 29–32 |
| X25519 (`KeyAgreement` / `KeyPairGenerator` `XDH`) | API 33 | missing on API 29–32 |

The core is a plain JVM library so its tests run without an emulator. The JDK (11+) has ChaCha20-Poly1305 and
(15+) Ed25519/X25519 under different names, which needs a small wrapper.

**Dependency check:** passes, but we are behind.

| Criterion | Evidence |
|---|---|
| Releases | latest 1.86, Maven 2026-09-11; **we pin 1.79** |
| Maintainers | 15 active in the last 12 months |
| Security | SECURITY.md present |
| License | MIT |

**Decision:** keep BouncyCastle for Ed25519/X25519 while the minimum is API 29.

Actions:
1. **Update to 1.86.** Seven releases behind in a crypto library. Rerun all vector tests.
2. Take ChaCha20-Poly1305 from the platform `Cipher` (Android API 28+ / JDK 11+). That is one fewer use of
   BouncyCastle, checked by the frozen vectors. Optional; low risk.

**Security check (2026-09-30):** the advisories fixed after 1.79 are:
- FrodoKEM timing, CVE-2026-5598;
- LDAP injection, CVE-2026-0636;
- CMS AuthenticatedData, CVE-2026-59642;
- GOSTCTR, CVE-2025-14813 (the fixed version was not checked; seen only in a search result).

None of them touches what we use (Ed25519, X25519, ChaCha20-Poly1305 through the lightweight API). CVE-2025-8916 was
already fixed in 1.79. So the update is housekeeping, not a security fix. BouncyCastle is removed in v2 (0017).

**Revisit:** when the minimum reaches API 33 (Android 13); then BouncyCastle can go entirely.

Sources: https://developer.android.com/reference/javax/crypto/Cipher · https://developer.android.com/reference/java/security/Signature · https://developer.android.com/reference/javax/crypto/KeyAgreement · https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/maven-metadata.xml · https://github.com/bcgit/bc-java
