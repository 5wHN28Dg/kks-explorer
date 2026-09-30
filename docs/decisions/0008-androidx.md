# 0008 AndroidX: Compose, Activity, Core, WorkManager

Date 2026-09-30 · Scope: Android app shell · Status: keep, **update versions**

These are Android's current supported development model. Compose is Google's recommended UI toolkit, and WorkManager
is the Jetpack background scheduler. The native policy treats them as platform-provided even though they ship inside
the APK.

**What we use:**
- Compose (BOM, material3, adaptive navigation suite) for the shell UI;
- activity-compose;
- core-ktx (FileProvider for camera photos);
- WorkManager (periodic sync, M3d);
- NsdManager, Keystore, WebView, SQLite: framework APIs used directly.

**Versions, pinned 2024 → latest (Google Maven, 2026-09-30):**

| Library | Pinned | Latest |
|---|---|---|
| compose-bom | 2024.12.01 | 2026.09.00 |
| activity-compose | 1.9.3 | 1.14.0 (alpha at the latest line) |
| core-ktx | 1.13.1 | 1.19.1 |
| work-runtime-ktx | 2.9.1 | 2.12.0 |

**Decision:** keep. Update to current stable releases in one step, then run the emulator checks again. The Compose
API changes yearly, as the policy says about moving frameworks. AGP and Kotlin versions come along.

**Revisit:** once a year, or when targetSdk moves.

Sources: https://dl.google.com/android/maven2/androidx/compose/compose-bom/maven-metadata.xml · https://developer.android.com/develop/ui/compose · https://developer.android.com/topic/libraries/architecture/workmanager
