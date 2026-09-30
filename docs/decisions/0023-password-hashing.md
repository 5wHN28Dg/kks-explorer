# 0023 Password hashing and passphrase keys

Date 2026-09-30 · Scope: R10, R14, R19, N1 · Status: **accepted by the user 2026-09-30**

**Where passwords are used:**
1. Signing in to the always-on server from a browser (R19).
2. "Join via server": a new device proves the person's password to the server (R13).
3. The manager's passphrase that encrypts the root key backup (R14).

**Guidance (OWASP Password Storage Cheat Sheet):** in order of preference:
1. Argon2id (minimum m = 19 MiB, t = 2, p = 1);
2. scrypt (N = 2^17, r = 8, p = 1);
3. PBKDF2-HMAC-SHA256 at 600,000 iterations.

**Today:** scrypt with N = 2^14 for passwords (8× below OWASP) and N = 2^15 for the root key backup.

**What the platforms provide:**

| | Argon2id | scrypt | PBKDF2-SHA256 |
|---|---|---|---|
| Linux server / GNOME | ✅ OpenSSL 3.2+ (3.5.5 here; `openssl kdf … ARGON2ID` ran [V]) | ✅ OpenSSL [V] | ✅ Nettle, OpenSSL |
| Windows | ❌ | ❌ | ✅ CNG `BCryptDeriveKeyPBKDF2` [K] |
| Android | ❌ | ❌ | ✅ `PBKDF2WithHmacSHA256` [K] |
| Browser | ❌ | ❌ | ✅ WebCrypto [K] |

**Proposed:**
- **Password hashes (uses 1 and 2) live only on the server,** which runs Linux. Use **Argon2id** through the system
  OpenSSL (≥ 3.2), starting at m = 64 MiB, t = 3, p = 1, above the OWASP minimum. Measure a login on the server and
  keep it under about 0.5 s.
  - Browsers and devices send the password over the TLS channel (0017). They never hash it themselves.
  - Existing scrypt hashes are upgraded on the person's next successful sign-in (verify the old one, store the new
    one).
- **The root key backup passphrase (use 3) must open on any desktop the manager may use,** so it uses what every
  target has: **PBKDF2-HMAC-SHA256, 600,000 iterations or more.** PBKDF2 is weaker than Argon2id against GPU guessing,
  so the strength has to come from the passphrase:
  - the app **generates** a passphrase of at least 6 random words from a large word list (about 77 bits);
  - the manager may choose their own only if an entropy check says it is at least as strong.
  - Brute force is then out of reach whatever the KDF, and the backup restores on Windows, GNOME, Android or a browser.
- The login throttling from today stays: the server limits attempts per account and address.

**Costs:**
- Argon2id needs OpenSSL 3.2 or newer on the server. That is a stated minimum for the server's Linux distribution
  (Ubuntu 24.04 ships 3.0 [K, not re-checked], so it needs 26.04 or a backport; check when choosing the server's distribution).
- Generated passphrases have to be written down or stored by the manager. This is already part of the root key
  backup routine.

**Revisit:**
- if Windows or Android gain Argon2 (then the backup moves to Argon2id);
- if the server has to run on an OpenSSL older than 3.2.

Sources: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html · `openssl version` / `openssl kdf ARGON2ID` on
this laptop (OpenSSL 3.5.5) · docs/m6/CAPABILITIES.md §4
