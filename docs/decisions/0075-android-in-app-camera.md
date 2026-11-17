# 0075 Android: an in-app camera (CameraX with the phone's Extensions), beside the system camera

Date 2026-11-17 · Scope: `android/app2` · Status: decided for a trial (the user, 2026-11-17: "if it fixes this then it
is the way to go, if not then just a hint")

**Question:** photos taken from Walkdown on the Honor 600 look worse than the same scene in the camera app. Walkdown
asks the system camera app for a picture (`ACTION_IMAGE_CAPTURE`); 0074 removed most of the app's own loss (1600 px,
effort 9, bilinear). Can an in-app camera get the picture the camera app would have taken, and at what cost?

## Findings

| | Fact | Source |
|---|---|---|
| The intent | Android promises nothing about the quality of `ACTION_IMAGE_CAPTURE`; since Android 11 it always goes to the preinstalled camera app. Its screen has no mode picker (no night or high-resolution mode) | [D] https://developer.android.com/reference/android/provider/MediaStore#ACTION_IMAGE_CAPTURE · https://developer.android.com/about/versions/11/behavior-changes-11 |
| Huawei | "Photos or videos taken with third-party apps have their image resolution and color information compressed, resulting in lower image quality compared to the native Camera app" (no model or version given, and it does not say whether that means the intent or an app's own camera code). Honor tells WeChat users to take close-range photos in the Camera app and share them. Nothing found from Honor or MagicOS on the intent itself | [D] https://consumer.huawei.com/en/support/content/en-us00445136 · https://www.honor.com/uk/support/content/en-us15807528 |
| Plain Camera2 / CameraX | an app's own camera gets the sensor's normal output (on a 50 MP binned sensor usually ~12.5 MP) and the HAL's single-frame processing, not the maker's multi-frame HDR or night processing | [D] https://developer.android.com/media/camera/camera-extensions · https://developer.android.com/reference/androidx/camera/core/resolutionselector/ResolutionSelector |
| Extensions | the maker's processing reaches other apps only as Extensions (AUTO, HDR, NIGHT, BOKEH, FACE_RETOUCH), still capture and preview only. The phone must ship the vendor library `androidx.camera.extensions.impl` (and `ro.camerax.extensions.enabled=true` on Android 12+). CameraX reaches it on any Android version; Camera2's own Extensions API (`CameraExtensionSession`) needs API 31+ and runs on the same vendor library | [D] https://source.android.com/docs/core/camera/camerax-vendor-extensions · https://developer.android.com/media/camera/camera2/extensions-api |
| Which phones | Google's list (incomplete by its own words): Honor 200/200 Pro/300/400/400 Pro, Magic5–7, Magic V2/V3; Samsung S10 and later, Note10/20, A-series. **Neither the Honor 600 nor the Note 9 is listed**: only the phone can tell | [D] https://developer.android.com/media/camera/supported-devices |
| Version | CameraX 1.6.2 (2026-08-26) is the latest stable release; its AARs need minSdk 23, compileSdk 36, AGP 8.9.1, Kotlin 2.0+ (Walkdown: 29, 36, AGP 9.4.1, Kotlin 2.4.20). From 2026-11-01 some phones drop Extensions for apps on CameraX 1.5 or older. 1.7.0 is a release candidate | [D] https://developer.android.com/jetpack/androidx/releases/camera · https://developer.android.com/media/camera/camerax/extensions-api |
| Licence, advisories | Apache-2.0, plus BSD-3-Clause for the libyuv code in camera-core (both on `license-allowlist.txt`). OSV: no advisories for camera-core, camera-camera2, camera-extensions | [D] https://dl.google.com/android/maven2/androidx/camera/camera-core/1.6.2/camera-core-1.6.2.pom · https://osv.dev |
| Maintenance | Jetpack, Google's own camera library for apps ("platform-provided" under the evidence-first rules: the vendor's named development model); releases every few months since 2019, past one major line change (1.0 → 1.6) | [D] release notes above |
| Size | AARs (compressed, before R8): camera-core 1.21 MB, camera-camera2 1.18 MB, camera-camera2-pipe 1.59 MB (pulled in, with Dagger), camera-extensions 75 KB, camera-lifecycle 55 KB, camera-compose 43 KB. camera-view would also bring appcompat, fragment and camera-video. The installed size after R8 is to be measured (the regression rule: growth over 25 % of the 27 MB APK needs a written reason) | [D] dl.google.com AAR sizes · `docs/m6/MEASUREMENTS.md` |
| QR, 0032 | the invite QR scanner uses Camera2 directly (a preview and grey frames, ~150 lines); that needs no still capture, orientation, JPEG quality or 3A handling, and no Extensions | [V] `ui/ScanQr.kt` · 0032 |

## Choice

- **CameraX 1.6.2** (`camera-core`, `camera-camera2`, `camera-lifecycle`, `camera-extensions`, `camera-compose` for
  the viewfinder), pinned in the lockfile. Camera2 alone (no dependency) is the alternative: it reaches Extensions
  only on Android 12+, not on the Note 9's Android 10, and would mean owning the still-capture code (3A, orientation,
  quirks per device) that CameraX carries. CameraX's own `PreviewView` (camera-view) is left out: Compose's
  `CameraXViewfinder` is lighter.
- **The camera screen:** back camera, `CAPTURE_MODE_MAXIMIZE_QUALITY`, the largest normal output size. Where the phone
  offers Extensions the person picks one (Auto, HDR, Night; Auto first if offered), else "Standard". The shot is
  written at full size, then goes through the same path as any picture (0074: 2560 px, Lanczos, the editor). It keeps
  the equipment / tag plate choice of the add-photo buttons. The QR scanner stays on Camera2.
- **The system camera stays available:** a setting chooses which one "Take a photo" opens (the in-app camera by
  default on a phone that offers an Extension, else the system camera), and the camera screen has a button to the
  system camera instead.
- **Diagnostics:** the app records which Extensions the phone reports per camera, the capture sizes, and the
  manufacturer and model, so a diagnostics report (and the user's trial) tells what the phone offers.
- **The trial:** a test build with its own application ID (`io.github.walkdown.camtest`, "Walkdown camera test",
  never the release key) takes the same scene both ways and keeps the full-size originals and the stored JPEG XL, so
  the two can be compared on the Honor 600 without touching the real install.

**When to revisit:** after the user's trial on the Honor 600. If the in-app camera's picture is not clearly better,
it is removed again (the dependency with it) and the add-photo screen gets a one-line hint to take the photo in the
camera app and add it from the gallery. Also when CameraX 1.7 is stable, or if the installed size grows past the
25 % rule.
