# 0046 Android: release APKs for arm64-v8a only, libraries uncompressed

Date 2026-10-04 · Scope: `android/app2` · Status: **accepted by the user** (2026-10-04)

**Question:** which CPU architectures does the release APK carry, and should its native libraries be compressed?

## Findings

| | Fact | Source |
|---|---|---|
| The APK | 27.6 MB at 0.9.2: native code for arm64-v8a 10.6 MB and x86_64 9.0 MB (the emulator only), stored uncompressed | [V] `unzip -l` of the published APK |
| ABIs | phones since 2019 are arm64-v8a; a 32-bit-only phone (Galaxy A02s, Android 12, `armeabi-v7a`) refused it with `INSTALL_FAILED_NO_MATCHING_ABIS` | [D] https://developer.android.com/ndk/guides/abis · [V] the colleague's phone, 2026-10-04 |
| 32-bit build | worked after one constant fix (join, search, edit, approval, wipe passed on the A02s), +6 MB per APK; the user chose not to support 32-bit phones | [V] 2026-10-04, not kept |
| Compression | compressed libraries are extracted by the installer to the file system, and the APK keeps its copy: smaller download, more space on the phone. Uncompressed ones load straight from the APK | [D] https://developer.android.com/guide/topics/manifest/application-element#extractNativeLibs |

## Choice

- **Release:** arm64-v8a only (`ndk.abiFilters` per build type): 18 MB.
- **Debug and rehearsal:** arm64-v8a + x86_64, so the e2e tests keep running on the emulator.
- **Libraries:** stay uncompressed (the default). The user's rule: compress only if the installed size does not grow;
  per the documentation above it grows.
- **32-bit phones:** not supported. Walkdown needs a 64-bit Android phone.

**When to revisit:** if a teammate's phone is 32-bit only after all, or if Play-style per-ABI splits become useful
(several APKs from one release).
