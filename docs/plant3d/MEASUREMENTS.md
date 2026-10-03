# The 3D plant: measurement rules

Written 2026-10-03, **before any measurement** (evidence-first policy). Status: **confirmed by the user
2026-10-03**.

## Devices and tiers

| Tier | Device | Renderer path (if Godot) |
|---|---|---|
| Minimum | Samsung Galaxy Note 9 (Exynos 9810, Mali-G72 MP18, Android 10), release build, no dev tools | Mobile (Vulkan) |
| Phone, current | Honor 600 (Android 16) | Mobile (Vulkan) |
| Laptop | this laptop (Linux) and a Windows laptop when available | Forward+ |

## Metrics and rules (proposed)

| Metric | How | Rule |
|---|---|---|
| Frame rate, sustained | the fixed walking path for 10 minutes, frame times logged; device at room temperature, screen at 50 % brightness | Note 9: ≥ 30 fps for 95 % of frames over the whole 10 min (no thermal drop below that); laptops: ≥ 60 fps at the highest preset meant for them |
| Frame-time spikes | same log | no frame over 100 ms after the first 5 s (no visible hitch when content streams in) |
| Memory | peak and steady (PSS on Android) | Note 9: ≤ 1.5 GB peak (it has 6 GB; the OS and other apps need the rest) |
| Load time | start to first walkable frame | Note 9: ≤ 15 s; laptop ≤ 5 s |
| Install / download size | APK/AAB and installed size; per-area content separately | written down per tier; growth over 25 % needs a reason |
| Battery (phones) | 30 min walking, battery stats + battery level | written down; informs the default quality on battery |
| Look | the same 10 viewpoints captured on each tier | a person compares them for learning: on every tier a trainee recognizes the same equipment, labels, states (valve positions, running/stopped, alarms) and routes; differences that don't affect that are fine (R9a) |

A regression rule for later builds: worse than 1.2× the baseline frame time on any tier needs a written reason.
