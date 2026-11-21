# 0077 Walkdown Plant: IRIS as the photosensitivity analyser for flash evidence (development only)

Date 2026-11-21 · Scope: evidence for the UI and UX policy's "no seizures" rule (A10) on Walkdown Plant's scenes
(issue #443, PR #467) · Status: decided (the task given for #443: "a real flash analysis (IRIS or PEAT)")

**Question:** A10 asks that game scenes with flashing pass a Harding-style photosensitivity analysis. Our own
`tools/plant3d/flash_analysis.py` is a model of WCAG 2.3.1, not an analyser. Which analyser can run here, on Linux,
without anything installed system-wide?

## Findings

| | Fact | Source |
|---|---|---|
| IRIS (Electronic Arts) | C++ library and console app; detects luminance flashes, red saturation flashes and spatial patterns; fails > 3 flashes in any second, and 2 to 3 a second over any 5 s ("extended"); a CSV or JSON per frame. "Not intended to guarantee, certify or otherwise validate" compliance | [D] https://github.com/electronicarts/IRIS README |
| IRIS's licence and upkeep | BSD-3-Clause; last commit d96978ac (2025-01-14); one company's repository, few releases | [D] GitHub API for electronicarts/IRIS |
| IRIS's build | CMake + Ninja + vcpkg; depends on OpenCV (with FFmpeg), spdlog, nlohmann-json, giflib, gtest; the code includes only OpenCV's core, imgproc, videoio and highgui (not the contrib modules its manifest asks for) | [V] the source at d96978ac |
| PEAT (Trace Center) | Windows only (XP to 10); free "for developers to identify seizure risks in their web content and software"; assessing material produced for gaming is prohibited (Harding FPA is named for that); version 1.6, 2017 | [D] https://trace.umd.edu/peat/ |
| Harding FPA (Cambridge Research Systems) | the broadcast standard's analyser; commercial | [D] same page |
| This machine | Linux, no OpenCV or FFmpeg development packages; cmake, ninja, g++ present | [V] pkg-config, `which` |

## Choice

- **IRIS**, at commit d96978ac, built in user space under `~/kks-work/tools/` (not in the repository, not in any
  product's dependencies): vcpkg cloned there at the baseline IRIS names (0affe871), its manifest without OpenCV's
  `contrib` feature (unused by the code) and as `opencv4` without its default features (they pull in GTK, unused),
  a release-only triplet, one compile at a time (a `ninja` wrapper that drops `-j`: harfbuzz's -O3 compiles were
  OOM-killed at 3 GiB with several), `CMAKE_POLICY_VERSION_MINIMUM=3.5` and `-Wno-error` (CMake 4 and GCC 15 against
  2024 ports). FFmpeg's port needs `nasm`: Debian's own package, fetched with `apt download` (apt's signed index
  checks it) and unpacked with `dpkg -x` under `~/kks-work/tools/`, not installed. Nothing is installed system-wide;
  if it needed that, we would stop and ask. Verified 2026-11-21: it builds and runs here (`tools/plant3d/flash_iris.sh`),
  and it fails the lightning as it was on main (60x: up to 8 luminance transitions a second) and passes it after #443.
- Its default `config/appsettings.json`, unchanged. Input: Godot's Movie Maker (`--write-movie`, `--fixed-fps`), so
  each frame is one fixed step of real time and the video's time is the game's real time.
- PEAT is ruled out by its own terms (no gaming material) and its platform; Harding FPA costs money (a choice for the
  owner if a certified result is ever needed).
- IRIS's result is evidence for A10, not a certification; the PR says so.

## When to revisit

- If a certified analysis is required (a store, a customer): Harding FPA, the owner's decision.
- If IRIS's repository is archived or its thresholds diverge from WCAG 2.3.1 / ITU-R BT.1702.
- If PEAT's announced fully open-source version appears with terms that allow games.
