# 0007 QR scanning on Android: zxing core + zxing-android-embedded

Date 2026-09-30 · Scope: "Join with a QR code" in the Android app · Status: **replace the embedded library**

**Needed for:** scanning the invite QR with the camera.

**Platform:**
- The Android framework has no barcode decoder.
- Google's code scanner (ML Kit through Google Play services) is an optional component. The native policy says Play
  services is not a guaranteed part of Android, and whether the team's phones all have it is *unverified*.
- CameraX (Jetpack) is the platform's supported camera model. It gives preview and frames, but no decoding.

**Dependency check:**

| Library | Evidence | Result |
|---|---|---|
| zxing core 3.5.4 | Maven 2025-11-11, 8 active contributors, Apache-2.0, no security policy; the project says it is in maintenance mode | weak but alive |
| zxing-android-embedded 4.3.0 | **last release 2021-10-25**, last push 2024-08-04, **0 active contributors** in 12 months, Apache-2.0 | **fails** releases and maintainers |

The embedded library also pulls the camera into its own old `CaptureActivity`. We already had to override that
activity's orientation in the manifest.

**Decision:**
- Replace zxing-android-embedded with a small CameraX preview screen (platform model) that hands frames to zxing core
  for decoding.
- Keep zxing core. Nothing in the platform decodes QR codes, and it is small.
- ML Kit could be added later as an optional fast path, if all phones have Play services.

Test on a real phone (the emulator's camera could not be aimed at a QR; CLAUDE.md M3).

**Revisit:** if zxing core stops releasing, or the framework gains a barcode API.

Sources: https://repo1.maven.org/maven2/com/journeyapps/zxing-android-embedded/maven-metadata.xml · https://github.com/journeyapps/zxing-android-embedded · https://github.com/zxing/zxing · https://developer.android.com/media/camera/camerax · https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner
