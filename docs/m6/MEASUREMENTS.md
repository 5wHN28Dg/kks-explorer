# M6 measurements: baselines and regression rules (N3, N4)

The policy requires a baseline and a regression rule for each metric, with the rule written **before** measuring. Each
section below records the rule first, then the measurement. "Verified" means measured on the target as stated.

## GNOME app (phase 5)

**Target and conditions:**
- the development laptop: i7-12700H, 32 GB RAM, Ubuntu 26.04.1, GNOME 50 on Wayland, GTK 4.22.4;
- a release build (`nim c -d:release`), not yet the Flatpak (unbuilt, see apps/gnome/README.md);
- a joined device holding the LP sheet (5 pyramid levels, 39k paths) and its 225 tags;
- warm file cache, 5 runs, median reported.

**Rules, written 2026-10-01 before the first measurement:**

| Metric | How | Regression rule |
|---|---|---|
| Startup | process start → first sheet drawn (`KKS_TIMING=1` prints it) | worse than 1.5× the baseline, or over 2 s, needs a written reason |
| Steady memory | VmRSS 10 s after the first sheet is drawn, sheet at fit | worse than 1.3× the baseline, or over 400 MB |
| Installed size | the app binary + its program data (system libraries excluded: they come with the GNOME runtime) | growth over 25 % needs a written reason |

**Measured 2026-10-01 (baseline):**
- **Startup:** median 315 ms over 5 runs (285–334 ms). This includes opening the sealed store, replaying the log,
  loading the plant model and drawing the first overview level.
- **Steady memory:** 248 MB VmRSS (248.2–248.7 MB). Not yet broken down. The decoded overview level, the GL
  textures, the path store and the GTK/GL stack each contribute.
- **Installed size:** binary 2.8 MB, plus `data/kks.json` 4 KB.
- **Not measured yet:**
  - panning frame times (no automated input on Wayland here);
  - the Flatpak's size;
  - a mid-range laptop.

## Android app v2 (phase 6)

**Targets:**
- Samsung Galaxy Note 9 on Android 10: the minimum API (29) and the slowest chip we support;
- Honor 600 on Android 16: the newest platform rules, and an aggressive background killer.

Both are clean installs of a **release** build (R8), with USB debugging the only developer setting. Each holds the
LP sheet and its tags, plus 2,000 or more log entries. The user connects the phones; the emulator does not count for any
metric below.

**Rules, written 2026-10-01 before the first measurement:**

| Metric | How | Regression rule |
|---|---|---|
| Installed size | Settings → Apps → storage: "App size" right after install, before joining | growth over 25 % needs a written reason |
| Cold start | `am start -W` TotalTime to the first frame, plus app log time to the first sheet drawn; app force-stopped, 5 runs, median | worse than 1.5× the baseline, or over 3 s to the first sheet on the Note 9, needs a written reason |
| Replay | core open + replay of the log (timed in the app log) | worse than 1.5× the baseline; over 2 s on the Note 9 reopens decision 0032 (JNI crypto) |
| Steady memory | `dumpsys meminfo` total PSS 30 s after the first sheet, sheet at fit | worse than 1.3× the baseline, or over 300 MB |
| Battery | 1 hour with the app closed, joined, on Wi-Fi with one server (the worker every 15 min): battery stats for the app | over 1 % of the battery per hour needs a written reason |
| Photo encode | ms per megapixel for JPEG XL at d1.9, effort 9 (`Jxl.msPerMp`) | informational: drives the progress estimate |

**Measured:** nothing yet; it needs the phones.

For orientation only (not a baseline): the debug APK is 44 MB and unshrunk, with x86_64 and arm64 libraries:
- `libkks.so` (the core with SQLite) is 2.5 MB per ABI;
- libjxl and zxing-cpp make up the rest of the native code.

## Windows app (phase 7)

**Targets:**
- Windows 10 22H2 (build 19045) and Windows 11 26H2 (build 26300) as QEMU/KVM VMs on the development laptop (i7-12700H);
  4 vCPUs, 6 GB (10) and 8 GB (11);
- no GPU: Direct2D runs on WARP, its software renderer;
- a release build (mingw-w64, static), joined, holding the LP sheet and its 226 tags;
- 5 runs, median.

VMs give valid numbers for installed size and comparable numbers for startup and memory. They give no GPU timings and
no battery figures (docs/decisions/0033). A real Windows laptop is still needed before the cutover.

**Rules, written 2026-10-01 before the first measurement:**

| Metric | How | Regression rule |
|---|---|---|
| Installed size | the program folder (one static exe, no other files) | growth over 25 % needs a written reason |
| Startup | process start → first overview level drawn (`KKS_TIMING=1` writes `timing.log` in the data folder); app joined, data warm | worse than 1.5× the baseline, or over 3 s in the VM, needs a written reason |
| Steady memory | private bytes (`Get-Process … PrivateMemorySize64`) 15 s after start, sheet at fit | worse than 1.3× the baseline, or over 400 MB |

**Measured 2026-10-01 (baseline, VMs):**

| | Windows 10 22H2 | Windows 11 26H2 |
|---|---|---|
| Installed size | 13.64 MB (one static exe) | same file |
| Startup to the first overview drawn | median 390 ms (343–1,031) | median 268 ms (246–309) |
| Private bytes after 15 s | 45.3 MB (45.2–45.5); working set 64.6 MB | 45.7 MB (45.5–45.8); working set 71.4 MB |

- **Startup** includes:
  - opening the DPAPI-sealed store;
  - the key store (CNG);
  - replaying the log;
  - loading the model;
  - decoding the smallest pyramid level with libjxl.

  The 1,031 ms run on Windows 10 was the first after a fresh join: the file cache was cold.
- **Memory** is far below the GNOME app's 248 MB. Two reasons:
  - Direct2D on WARP keeps bitmaps in our process, but only the overview is decoded at fit;
  - no GTK/GL stack is loaded.

  Not yet compared: zoomed-in tile caches on a real GPU.
- **Not measured yet:** a real laptop's GPU, panning frame times, the MSIX package's size.
