# UI audit 2026-11, pass 1: Walkdown Plant on Android (helper "vm")

## 1. What was run

- Emulator AVD Pixel_9_Pro_XL (Android 16, `ro.product.cpu.abilist` = `x86_64` only, no ARM translation), under
  `vm.lock`. `adb install -t ~/kks-work/build/plant-w2-debug.apk` (a test-key debug build; its only native library is
  `lib/arm64-v8a/libgodot_android.so`) failed: `INSTALL_FAILED_NO_MATCHING_ABIS: Failed to extract native libraries,
  res=-113`. The arm64 build can't run on this emulator.
- Note 9: not used. The phone window was closed when checked, and the
  emulator and Windows work ended at 13:27, before the window opened. The Honor was not touched.
- So nothing of Plant on Android was run. Plant's phone layout on the desktop (`tests/mimic_shots.gd --phone`) is the
  stand-in the policy names (§4 limits); that is the desktop helper's part, not repeated here.

## 2. Results

Every rule for Plant on Android: **Not checked: the arm64 build does not run on the emulator** (an accepted limit,
policy §4: "Plant on Android, if its arm64 build does not run on the x86-64 emulator: the phone layout on the desktop
stands in until a phone window"), and the Note 9's window was not open during this run.

| Rule | Plant Android |
|---|---|
| T1, T2, T4, T5 | Not checked (arm64 build does not run on the emulator; no phone window) |
| T3 | N/A (desktop rule) |
| R1, R2, R3, R4 | Not checked (same reason) |
| C1, C2, C3 | Not checked (same reason) |
| B1, B2, B3 | Not checked (same reason) |
| K1, K2, K3, K4, K5, K6, K7 | Not checked (same reason) |
| S1, S2, S3 | Not checked (same reason) |
| F1, F2, F3, F5, F6 | Not checked (same reason) |
| F4 | N/A (Plant on Android exempt) |
| D1, D2, D3, D4 | Not checked (same reason) |
| X1, X2, X3 | Not checked (same reason) |
| A1, A2, A3, A4 | Not checked (same reason) |
| A5 | N/A (Plant on Android exempt) |
| L1, L2, L3, L4, L5 | Not checked (same reason) |
| P1 | Not checked (needs the Note 9's frame walk; window closed, accepted limit) |
| P2 | N/A (Walkdown rule) |
| P3, P3a, P4 | Not checked (same reason) |
| Z1, Z2, Z3 | N/A (nothing captured) |
| G1, G2, G4 | Not checked (same reason) |
| G3 | N/A (Plant is landscape only by design) |

## 3. Findings

None (nothing ran).
