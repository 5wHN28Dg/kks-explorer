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

**Measured 2026-10-01/02 (baselines):** the signed release APK (27 MB; it still carries the x86_64 libraries
too: an ABI split would shrink the phone download), joined to the measurement server on this laptop (the LP sheet,
204 tags, 2,000 approved edits: about 2,020 log entries).

| Metric | Note 9 (Android 10) | Honor 600 (Android 16) |
|---|---|---|
| Installed size (the system's app size after install) | 27.41 MB | 27.39 MB |
| Cold start, `am start -W` TotalTime (median of 5) | 649 ms | 380 ms |
| Core open + replay (app log) | 256 ms | 121 ms |
| First sheet drawn after process start (app log) | 739 ms | 417 ms |
| Steady memory, total PSS | ~214 MB | ~176 MB |
| JPEG XL encode, d1.9 effort 9 | 4,587 ms/MP | 2,505 ms/MP |
| Battery, 1 h in the background, screen off, on Wi-Fi with the server | 0.143 mAh charged to the app (0.334 mAh with its share of system use) of 4,000 mAh: under 0.01 % per hour | ~0 (1 ms CPU): **the worker never ran** (see below) |

Battery on the Note 9 (2026-10-02 11:57–12:58): USB connected with `dumpsys battery unplug`, so the figure is
Android's power-profile estimate, not a measured drain. The worker ran 3 times (Doze held the first run 25 min, then
every 15 min), 3.2 s CPU, 35 KB over Wi-Fi. Two earlier runs were void: the phones were reconnected (stats reset), and
the app had been force-stopped, which puts it in the stopped state where its scheduled work never runs. "Closed"
means sent to the background with Home.

Battery on the Honor 600 (2026-10-02 12:30–13:30, truly unplugged, on Wi-Fi, app sent to the background after the
QR join): the phone slept 55 of the 60 minutes and **the background sync job never ran**. Android had the app in the
`rare` standby bucket (40), which allows background jobs only a few times a day. Every other job constraint was met,
including Honor's own `HN_USER_EXPERIENCE`; it waited only on timing. It ran at 13:49:07, seconds after the phone was
plugged back in. So on this phone, background sync happens while charging or with the app open, not every 15 minutes.
A second hour (14:15–15:15, app forced to `active` with `am set-standby-bucket`): again no run. The usage log shows
why: 34 s after the forced change, and at 12:30:23 seconds after Home, the bucket went back to `rare` with reason `f`
(forced by the system). Something with system rights on MagicOS (its power manager) puts the app in `rare` as soon
as it leaves the screen; stock Android doesn't. Third hour with the app "Unrestricted" (battery-optimization
exemption): bucket `exempted`, still no run, the job held only by Honor's `HN_USER_EXPERIENCE` constraint. Fourth hour
with MagicOS "App launch" set to manual: bucket `active`, still no run; the job had lost its system registration
(WorkManager: Job Id null) and the system log shows "job is prohibit by iaware" for many apps. On this phone,
background sync happens when the app is open or charging; the app now says so (Manage → Account) when it detects it.

All within the rules: the first sheet is well under 3 s on the Note 9, replay well under 2 s, memory under 300 MB.
A 12 MP photo takes about 55 s to encode at effort 9 on the Note 9: the progress bar is needed there.

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
