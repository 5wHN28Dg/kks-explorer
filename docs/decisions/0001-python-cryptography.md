# 0001 `cryptography` (Python)

Date 2026-09-30 · Scope: server, desktop peer, tests · Status: keep

**Needed for:**
- Ed25519 signatures (the signed log, PROTOCOL.md);
- X25519 + ChaCha20-Poly1305 (Noise sync, private entries);
- key serialization.

**Platform:**
- The Python standard library has hashlib (incl. scrypt, via OpenSSL) and hmac, but no Ed25519, X25519 or AEAD.
- Windows (CNG) and Linux (OpenSSL) have the primitives, but only through native APIs. Using them from Python means
  our own ctypes bindings, which is security-sensitive implementation work.

**Dependency check:** passes every criterion.

| Criterion | Evidence |
|---|---|
| Releases | 50.0.2 on 2026-09-30; first release 2014 |
| Maintainers | 53 contributors active in the last 12 months (GitHub pyca/cryptography) |
| Security history | published security policy and a CVE record at cryptography.io |
| License | Apache-2.0 OR BSD-3-Clause |
| Major versions survived | 20 |

**Decision:** keep. It replaces what would otherwise be our own crypto bindings.

**Revisit:** if the standard library gains Ed25519/X25519/AEAD, or in M6 (then the platform or language decides).

Sources: https://pypi.org/pypi/cryptography/json · https://github.com/pyca/cryptography · https://cryptography.io/en/latest/security/
