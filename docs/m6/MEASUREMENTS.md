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

## Startup, 2026-10-21 (decision 0061)

The rules above stay (GNOME and Windows: worse than 1.5× the baseline or over 2 s / 3 s needs a reason; Android: over
3 s to the first sheet on the Note 9). This records the start before and after decision 0061, measured the same way
on both builds, in turns where the tool allows it.

**The plant:** `tools/m6/startup_data.py` (no plant data of ours): 17 copies of the sample sheet, 2,600 marked tags and
1,500 approved equipment edits, 4,120 log entries in all, about twice the phone baseline's log. Each app is joined
to it through the server: `apps/gnome/e2e/startup_join.nim`, `apps/windows/e2e/startup_join.nim`, or the Android
setup screen.

**How:**
- **GNOME:** `tools/m6/startup_gnome.py` under `apps/gnome/e2e/headless.sh`. The builds take turns, one warm-up start
  each, then 9 starts; `KKS_TIMING=1` prints every step from launch.
- **Windows:** `tools/m6/startup_windows.py`, running `apps/windows/e2e/startup.ps1` in the Windows 11 VM. It does
  one warm-up, then 7 starts in turns; the steps come from `timing.log`.
- **Android:** `tools/m6/startup_android.py` on the emulator (Pixel 9 Pro XL image, `-gpu guest`): 7 cold starts per
  APK after a warm-up. It records `am start -W` TotalTime (the first frame) and the app's own `KKSTime` lines. These
  are the emulator's numbers, not the phones': they compare the builds, not the targets.

| Median (min–max) | Before (main 75fd006) | After |
|---|---|---|
| GNOME, laptop otherwise quiet: first sheet drawn after launch | 369 ms (351–376) | 215 ms (211–219) |
| GNOME, the same run with other agents' jobs running: first sheet | 430 ms (422–467) | 261 ms (240–283) |
| Windows 11 VM: first overview drawn after start | 297 ms (268–429) | 245 ms (223–338) |
| Android emulator: first frame (`am start -W` TotalTime) | 1,193 ms (1,187–1,272) | 478 ms (469–488) |
| Android emulator: first sheet drawn after process start | 1,282 ms (1,276–1,352) | 1,152 ms (1,136–1,154) |

**Where the time goes after the change** (medians):
- **GNOME** (quiet run):
  - the loading thread reads the saved state and has the log ready at 83–105 ms;
  - GTK's own start ends at 100–120 ms;
  - the main screen is built at 135–169 ms;
  - GTK's first frame takes ~55 ms;
  - the overview is drawn in the frame after that.

  Before the saved state, with the thread already in place, the log was ready at 141–159 ms (`t2` in the run's
  notes). So on this log the saved state cut the thread's work by about 55 ms.
- **Windows:**
  - the window is made at 3 ms;
  - the log is ready at 106 ms and the model at 142 ms (the loading thread is the critical path: Win32 is ready long
    before);
  - the main screen is shown at 207 ms;
  - the first overview is drawn at 245 ms.
- **Android** (one emulator session, the three APKs in turn, 5 cold starts each; a second turn was cut short when the
  emulator reached its 8 GiB cap after 9 installs):
  - the first frame no longer waits for the core;
  - the core's open ends ~560 ms after process start. It takes 450 ms on its thread with the saved state, against
    475 ms with a build that always replays (`-d:kksNoSavedState`: first frame 486 ms, first sheet 1,198 ms) and
    318 ms before. It now runs while the main thread starts Compose, and the emulator's CPUs are shared between the
    two;
  - most of the first sheet's time on the emulator is after the open: the main screen's composition, the native
    views and the overview (~600 ms), which this change does not touch.
  - Sessions differ: an earlier one gave 1,464 → 525 ms (first frame) and 1,533 → 1,247 ms (first sheet); another,
    with other jobs on the laptop, 1,429 ms before and 618 / ~720 ms first frame for the replaying / saved-state
    builds. Only APKs measured in turn in the same session are compared above.

**Not measured:** the real phones (Note 9, Honor 600) and the Windows 10 VM.
