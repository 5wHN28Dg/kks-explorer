# 0020 Encryption at rest

Date 2026-09-30 · Scope: N1a (decided requirement), R14, N5 · Status: **accepted by the user 2026-09-30**

**Requirement (N1a):**
- Plant data on a device (history, drawings, photos, backups) is encrypted.
- Only the app, on a device the plant accepted, decrypts it, and only while it runs.
- The limits are stated honestly.

**What the platforms provide:**

| | Disk encryption guaranteed | Key store to protect our key |
|---|---|---|
| Windows | ❌ BitLocker device encryption only on qualifying hardware [D] | DPAPI, per user [D]; TPM keys through CNG's Platform Crypto Provider [K] |
| GNOME | ❌ LUKS optional [K] | Secret Service (libsecret + GNOME Keyring, unlocked at login) [V] |
| Android | ✅ file-based encryption, required from Android 10 [D] | Android Keystore, hardware-backed AES keys (API 23) [K] |
| Browser | ✅ iOS data protection; desktop: depends on the OS | non-extractable WebCrypto AES key in IndexedDB [K] |
| Headless server (Linux) | ❌ | `systemd-creds` sealed to the TPM2 (systemd 259 here, TPM2 present [V]) |

**Proposed design:**
1. **A storage key per device:**
   - Each device creates a random 256-bit storage key when it joins a plant.
   - The key never leaves the device and is protected by the platform (next point).
   - Plant data only arrives after the plant accepted the device (R13), so "only accepted devices can decrypt" follows
     from the join rules. No extra plant-wide key is needed on devices.
2. **The storage key is wrapped by the platform key store:**
   - Android: a Keystore AES-GCM key, hardware-backed where available, wraps it.
   - Windows: DPAPI protects it (tied to the Windows account). A TPM-backed key is an option, measured later.
   - GNOME: stored in the Secret Service (login keyring).
   - Browser: a non-extractable WebCrypto key wraps it.
   - Server: sealed with `systemd-creds` to the TPM2.
3. **App-level encryption with AES-256-GCM (0017):**
   - encrypted: entry bodies in the database, photos and plant-data files on disk, local backups;
   - left in the clear, because sync needs them: entry IDs, device IDs, sequence numbers.
   - This keeps the **platform's own SQLite** (no SQLCipher, which is a library). Searching works from the in-memory
     state built at startup, as today.
4. **Backups made by the server or the manager** are encrypted to a backup key, and only the manager can restore them.
   It is kept apart from device keys. It belongs with the root key backup (R14); the detail goes with the protocol
   decision.
5. **Key loss** (reinstall, reset, lost keyring): that device's local copy becomes unreadable. It is discarded and
   synced again from the other devices. No plant data is lost as long as another device or a backup has it.

**The limits, to state in the app and the docs:**
- Anyone using the unlocked device through the app sees the data.
- On Windows and GNOME, the key store belongs to the user account, not our app: another program running as the same
  user could ask for the key. Android's Keystore is per app, so it is stronger.
- A removed device keeps what it already had. It gets nothing new and wipes itself if it reconnects.
- Performance: AES-GCM runs in hardware on the laptop (AES-NI) and on the phone (ARMv8 crypto extensions) [K].
  Decrypting 50k entries at startup should take milliseconds; measure it when building.

**Revisit:**
- if Windows/GNOME gain per-app key isolation;
- if the database must be searchable without loading it into memory (then an encrypted-database library is
  reconsidered).

Sources: docs/m6/CAPABILITIES.md §4 · https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata ·
https://source.android.com/docs/security/features/encryption/file-based · `systemd-analyze has-tpm2` on this laptop · docs/decisions/0017
