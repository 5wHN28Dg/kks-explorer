# 0074 Photos are stored at up to 2560 px, JPEG XL effort 7, and Android scales them with Lanczos

Date 2026-11-17 · Scope: every client that adds photos (web, GNOME, Windows, Android) · Status: decided (the user,
2026-11-17)

**Question:** photos taken in Walkdown look worse than the camera app's (the user's Honor 600). How much of that is
the app's own pipeline (the 1600 px limit, the codec setting, the scaling filter), and what should it store instead?

## Findings

| | Fact | Source |
|---|---|---|
| Before | every client scaled a photo to at most 1600 px on the longer side (~1.9 MP of a 12–50 MP frame) and stored it as JPEG XL at distance 1.9; the native apps at effort 9, browsers at effort 7 (0037) | [V] `ui/Photos.kt`, `kksg/photos.nim`, `kkswin/photos.nim`, `index.js` before this change |
| Loss | 9 real 12–20 MP phone photos (cjxl/djxl 0.11.1, laptop), luma SSIM of the stored photo enlarged back against the camera's file: 1600 px d1.9 **0.882** (201 KB mean); 2048 px 0.911 (306 KB); **2560 px 0.928 (435 KB, max 810 KB)**; 3200 px 0.944 (614 KB). About 70 % of today's loss is the size limit, 30 % the codec setting | [V] study on PR #401, 2026-11-17 |
| Effort | effort 9 against 7 at d1.9: 7–9 % smaller files for 10× (1600 px) to 22× (3200 px) the encoding time on one laptop core (1600 px: 0.4 s against 4.1 s). The Note 9 encodes effort 9 at 4.6 s per megapixel | [V] same study · [V] `docs/m6/MEASUREMENTS.md` |
| Filter | Lanczos instead of Android's power-of-two decode plus bilinear scale: +0.010 SSIM at the same size, no extra bytes. Android's `Bitmap.createScaledBitmap(…, true)` is bilinear and has no higher-quality filter; `ImageDecoder`/`BitmapFactory` scale only by powers of two with a documented filter | [V] same study · [D] https://developer.android.com/reference/android/graphics/Bitmap#createScaledBitmap(android.graphics.Bitmap,%20int,%20int,%20boolean) |
| Plate text | synthetic plate text in a 12 MP frame, scored by OCR: letters of 0.5–0.75 % of the frame's height lose some low-contrast readings at 1600 and 2048 px and mostly keep them from 2560 px up (a rough, noisy signal) | [V] same study |
| Limits downstream | none near: the core takes uploads up to `max_upload_mb` (15 MB); sync frames up to 64 MiB; relay pipe pieces of 64 KiB, WebSocket messages up to 16 MiB; the photo queues (Android files, desktop sealed rows, the browser's IndexedDB) have no size limit of their own; the protocol states no pixel limit | [V] `core/src/kks/api.nim`, `sync.nim`, `platform/linux/src/kksl/internet.nim`, `ws.nim`, `apps/common/photoqueue.nim` |

## Choice

- **At most 2560 px on the longer side, JPEG XL distance 1.9, effort 7, on every client** (the user's choice of the
  options in the study). Smaller pictures are not enlarged. Photos stored before stay valid: readers take any size
  (PROTOCOL-v2 §9 now says so).
- **Effort 7 on the native apps too** (0018 had fixed effort 9; 0037 kept it for the native apps): a 2560 px photo at
  effort 7 encodes faster than a 1600 px one at effort 9 did, and effort 9 at 2560 px would take about half a minute on
  the Note 9.
- **Android scales with a separable Lanczos-3 filter** of its own (`Resample.kt`, a few dozen lines of Kotlin, no
  dependency): the bitmap is decoded at the largest power-of-two reduction that keeps it at least 2560 px, then
  resampled. The desktops already scale with an area-averaging filter (Cairo's GOOD filter, WIC's Fant); browsers
  use the canvas's own scaling.
- **Thumbnails on Android** are decoded and kept at a small size; the full photo is decoded when it is opened.

**Costs:** about 2.2× the storage and sync per photo (435 KB mean against 201 KB; the largest seen 810 KB), so also
about 2.2× for a browser's offline copy of the photos (its storage quota on iPhones). 2.5× the pixels in each client's
queue while a photo waits (a 2560 × 1920 photo is 19.7 MB of RGBA). Decoding a photo for display takes about 2.5× the
time and memory; browsers without JPEG XL keep each shown photo decoded as a BMP (14.7 MB, was 5.8 MB) for as long as
the page is open. Android decodes thumbnails two at a time and keeps only the small copy.

**Supersedes in part:** 0018 and 0037 (effort 9 on the native apps), 0049's first estimate of 8 s per megapixel.

**When to revisit:** if the plant's photo storage or the phones' sync time becomes a problem (then 2048 px), or if the
in-app camera (0075) shows that the camera's processing, not the size, still limits the plate text (then 3200 px).
