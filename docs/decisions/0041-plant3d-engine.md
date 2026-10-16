# 0041 The 3D plant: which engine

Date 2026-10-03 · Scope: https://github.com/5wHN28Dg/kks-explorer/wiki/3D-plant (R8 devices, R9 photo-realistic and scaling) · Status:
**decided: Godot 4** (2026-10-16), with the Note 9 tier at the `lean+vis` preset. The user decided on 2026-10-15:
Godot 4 if the Note 9 meets the frame rule. On 2026-10-16 the user settled how the rule is read: count the frames
the 60 Hz screen shows, and a frame held for two refreshes is 30 fps. Read so, the Note 9 meets the rule on battery
with `lean+vis` (Conclusion below).

**Question:** which engine (or none) renders a generic, photo-realistic, walkable combined-cycle plant on laptops
(Windows, Linux) and phones, with the Samsung Galaxy Note 9 (Exynos 9810, Mali-G72 MP18, Android 10, Vulkan 1.1) as
the minimum, scaling smoothly to the top tier from one asset set?

## What the platforms give

None of the targets has a 3D scene engine of its own; they give graphics APIs: Vulkan (Android 7+, Linux), Direct3D
11/12 (Windows; Vulkan through drivers), OpenGL ES 3.2 (Android). Scene management, materials, lighting, LOD,
streaming, audio spatialization and physics for walking are all ours or an engine's.

## Candidates (desk research)

| | Godot 4 | Unreal Engine 5 | Unity 6 | Bevy | Our own renderer |
|---|---|---|---|---|---|
| Licence | MIT | proprietary EULA: free below $1 M revenue, then 5 % royalty; non-game commercial use: seat fee above $1 M company revenue | proprietary; Personal free below $200 k revenue | MIT/Apache-2.0 | ours |
| Latest | 4.7.2 (2026-08-18); minor versions supported until the next has its first patch | 5.6+ | Unity 6 | 0.19.x | — |
| Note 9 (Mali-G72, Vulkan) | Mobile renderer needs Vulkan 1.0 (Mali-G71 named) [D]; Compatibility renderer (GLES 3) as fallback | Mali-G72 listed; mobile renderer (Vulkan 1.1 / GLES 3.2) [D] | supported (Vulkan/GLES) [K] | Android not a focus of recent releases [D] | Vulkan 1.1, all ours |
| Top tier | Forward+ renderer: SDFGI, VoxelGI, SSR, SSAO, volumetric fog (desktop only) [D] | Nanite + Lumen: the best photo-realism, **desktop only** (Nanite needs SM6, not on Android) [D] | HDRP (desktop) / URP (mobile): two pipelines | raytraced lighting (desktop) | years of work |
| One asset set across tiers | lightmaps work in all three renderers; automatic mesh LOD at import, visibility ranges (HLOD), baked occlusion culling [D] | yes, but the mobile path drops Nanite/Lumen: a different lighting look per tier | URP vs HDRP need different materials | — | — |
| Security response | SECURITY.md + security@ address; **a 2026 issue reports three security reports unanswered for months, closed without reply** (#123608) | Epic security team [K] | Unity security [K] | small team | ours |
| Maintainers | large community + paid core team (Godot Foundation) [K] | Epic | Unity | community | one person |
| Fits the rest of KKS Explorer | GDExtension C API: the Nim core can be bound (KKS data, courses links) [K] | C++ plugin | C# | Rust | Nim |

Sources: https://docs.godotengine.org/en/stable/about/system_requirements.html ·
https://docs.godotengine.org/en/stable/about/release_policy.html · https://endoflife.date/godot ·
https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html ·
https://github.com/godotengine/.github/blob/master/SECURITY.md · https://github.com/godotengine/godot/issues/123608 ·
https://dev.epicgames.com/documentation/en-us/unreal-engine/android-development-requirements-for-unreal-engine?application_version=5.6
· https://www.unrealengine.com/en-US/blog/we-are-updating-unreal-engine-twinmotion-and-realitycapture-pricing-in-late-april
· https://www.cgchannel.com/2024/09/unity-scraps-controversial-runtime-fee-but-raises-prices/ ·
https://bevy.org/news/bevy-0-17/ ([D] = vendor docs, [K] = known, to confirm).

## Early reading (not a decision)

- **Our own renderer** is out for photo-realism: the lighting, LOD and streaming work alone is years for one person.
- **Bevy:** Android is not where it is going; out unless that changes.
- **Unity:** two render pipelines means two material sets (against R9's "one asset set"), and a proprietary licence
  with a revenue cap for a project meant to be public and free.
- **Unreal:** the best top tier, but its photo-realistic path (Nanite, Lumen) does not exist on the Note 9, so the
  phone tier looks like a different product; very large installs; proprietary EULA for a public project.
- **Godot 4** fits the constraints best on paper: MIT, one engine with three renderers sharing assets and baked
  lighting, mesh LOD/HLOD/occlusion built in, Android down to Vulkan 1.0. Its weak points: the top tier is below
  Unreal's, and the security response gap above (relevant mainly if the app ever loads content we don't make).

## The deciding measurements (to run, rules first)

Rules in https://github.com/5wHN28Dg/kks-explorer/wiki/3D-plant, written before measuring. One test scene, built the same way in each engine
measured: a pipe rack and pump bay of about 2 M triangles at full detail, 40 PBR materials with 2k textures, baked
lighting plus one dynamic light, a walking camera on a fixed path. Measure on the Note 9 (frame time, sustained 10 min
with thermal state, memory, install size) and a laptop (frame time at the highest preset). Godot first; Unreal only if
Godot misses the Note 9 targets or the top tier is judged not good enough for learning.

## Measurements so far (Godot 4.7.2, 2026-10-03)

Bench: `tools/plant3d/bench` (scene built by script from parametric parts: 1.46 M triangles at full detail, 6,274
parts, 40 PBR materials from 5 CC0 sets, one sun with shadows; a 60 s walking loop; frame times plus Godot's
measured CPU/GPU render time and draw calls). Note 9 runs plugged in (charging adds heat: the final run is to be
repeated unplugged). Variants: `nodes` (one MeshInstance per part), `merged` (everything per material in one mesh),
`cells` (instanced MultiMesh per part, material and 12 m cell). Presets: `full`; `scaled` (70 % resolution, FSR);
`lean` (60 % + FSR, 2048 shadow atlas, 40 m shadow distance, mesh LOD threshold 4); `lean_noshadow`.

| Device | Variant / preset | Median | p95 | > 33 ms | GPU median / p95 | CPU median | Draw calls p95 |
|---|---|---|---|---|---|---|---|
| Laptop (Iris Xe, 1600×900, Forward+) | nodes / full | 21–30 ms | 28–34 ms | 0–6 % | 25 / 35 ms | 5 ms | 482 |
| Laptop | merged / full | 28.8 ms | 43 ms | 42 % | — | — | — |
| Note 9 (Mali-G72, 2220×1080, Mobile) | nodes / full, 10 min | 31.9 ms | 66.7 ms | 40 % | 35 / 69 ms | 7 ms | 6,689 |
| Note 9 | nodes / scaled | 27.7 ms | 51.2 ms | 32 % | | | |
| Note 9 | nodes / lean | 25.0 ms | 43.1 ms | 26 % | | | |
| Note 9 | nodes / lean_noshadow | 21–23 ms | 36 ms | 10–14 % | 20 / 36 ms | 3 ms | 4,317 |
| Note 9 | **cells / lean** (90 s) | 24.0 ms | **34.0 ms** | 8 % | 21 / 33 ms | 1.7 ms | **457** |
| Note 9 | **cells / lean, 10 min** | 22.9 ms | 34.7 ms (28.8 fps) | 8.2 % | 19 / 34 ms | 1.6 ms | 486 |
| Note 9 | cells / lean + 2 shadow cascades, 10 min (started warm) | 22.6 ms | 34.1 ms (29.3 fps) | 7.2 % | 19 / 33 ms | 1.2 ms | 515 |

Findings:
- Both devices are **GPU-bound**; the CPU is not the limit even with thousands of parts.
- **Merging everything is wrong** (it defeats culling and LOD): the plant stays made of parts.
- **Instancing per cell** cuts the phone's draw calls by 93 % and is what brings the lean preset to the target edge
  with shadows kept: the plant's kit must be instanced by area.
- Resolution scaling alone helps less than expected; the GPU time goes to geometry passes (main + shadow) and
  material shading, so the phone tier's levers are shadow cost, LOD distance and texture size, not only pixels.
- After 10 minutes with the lean preset and instanced cells the Note 9 is **about 1 fps short** of the ≥ 30 fps
  (95 %) rule; no thermal throttling (battery 28 → 36 °C, thermal status 0); one 116 ms frame in the 2-cascade run.
  Fewer shadow cascades barely helped: the remaining GPU time is in the heaviest views (looking down the rack with
  everything in sight). Next levers: visibility ranges by part size (bolts, fins and small fittings not drawn beyond
  a distance at which they carry no information: R9a), texture resolution per tier, LOD bias.
- First frame: 20–28 s on the Note 9, 10–14 s on the laptop, almost all of it building the scene by GDScript at
  startup (generating LODs, creating nodes) and compiling shaders; a shipped plant would be pre-built and its
  shaders pre-compiled. To be measured with a pre-built scene before judging the load-time rule.
- The built bench plant saved as a Godot scene is **327 KB** (instanced parts are stored once plus their transforms);
  building it takes 0.9 s on the laptop. Size is in the textures (the APK is 81 MB, nearly all texture data for
  desktop and mobile compression), not the geometry.
- Not measured yet: the Honor 600, battery, the "look" comparison, a Windows laptop.

## Measurements, round 2 (2026-10-15/16): the remaining levers

**Version:** Godot 4.7.2 is still the newest stable release (GitHub releases, checked 2026-10-15; 4.7.2 came out
2026-08-18, no 4.7.3 or 4.8 since), so the bench stays on it. `tools/plant3d/bench/fetch_godot.sh` pins the editor
and export templates by SHA-512 (from the release's SHA512-SUMS.txt).

**What changed in the bench** (`tools/plant3d/bench`, built from nothing by `build.sh`; `run_phone.sh`, `note9.sh`,
`honor.sh` run it on the phones):
- Every lever is a switch on its own: `preset=BASE+LEVER+…` (bases `full`, `scaled`, `lean`, `lean2`,
  `lean_noshadow` as before; levers `vis`, `tex1k`, `lod`, `texraw`, `half`).
- `vis`: bolts and motor fins (parts whose information the flange or motor body carries already) are not drawn beyond
  the distance where their smallest feature is under 1 px on the Note 9's screen (bolt 0.024 m: 18.5 m; fins 0.04 m:
  30.8 m), plus the half diagonal of their instancing cell (Godot measures a range to the centre of the instance's
  box), with a fade. Handwheels and bonnets show a valve's type and state: R9a keeps them on every tier, so they get
  no range (LOD only). `tests/test_plant3d_bench.py` checks the rule.
- `tex1k`: the same texture files imported at 1024 px (17 MB of ETC2 instead of 69 MB). `lod`: LOD bias 0.5.
- **Texture import fixed.** The materials are made by script, so Godot's "used in 3D" detection never ran and the
  earlier bench's textures were imported **lossless, without mipmaps** (`texraw`, kept to compare). They are now
  VRAM-compressed (BPTC/S3TC on desktops, ETC2 on phones) with mipmaps, as any shipped 3D texture is.
- A **pre-built plant** (`built/plant.scn`, 651 KB, instanced cells) with its 40 materials saved as resources, and the
  export's **shader baker** on (Mobile shaders in the APK, Forward+ in the Linux build). Two things that are easy to
  get wrong: the baker and the saved scene need a rendering device (with `--headless` the export silently bakes
  nothing, and a scene saved there loads empty), and the baker compiles for the renderer the editor runs, so the
  Android export runs the editor with `--rendering-method mobile`.
- The earlier 20–28 s first frame on the Note 9 (10–14 s on the laptop) was mostly the bench itself: it counted
  triangles by reading every part's mesh back from the GPU (8 s on the laptop). Counted once per mesh, building the
  whole plant by script takes 50–70 ms on the laptop.
- `look=1` captures 10 fixed viewpoints (valves at 2 m, motor fins at 2 m, flange bolts at 2 m, handwheels at 10 m,
  the rack from 15 m, along the pump row, along the rack, the platform, the bay from above, the whole plant).
- On this laptop the bench runs on a private headless compositor with Xwayland (`offscreen.sh`), not on the
  desktop: under the headless Wayland session Godot got only a few frames a second (no frame callbacks); on Xwayland
  it runs unthrottled with vsync off.

| Device | Variant / preset | Run | Median | p95 (fps) | > 33 ms | > 100 ms | GPU median / p95 | Draw calls p95 | Peak RSS |
|---|---|---|---|---|---|---|---|---|---|
| Laptop (Iris Xe, Forward+, 1600×900) | cells / **full** (pre-built) | **10 min** | 8.3 ms | **12.2 ms (82)** | 0 % | 0 | 5.7 / 18.8 ms | 839 | 277 MB |
| Laptop 1600×900 | cells / full | 60 s | 8.0 ms | 12.5 ms (80) | 0 % | 0 | 5.6 / 17.4 ms | 862 | 276 MB |
| Laptop 1600×900 | cells / full+texraw (the old import) | 60 s | 11.1 ms | 22.7 ms (44) | 0.2 % | 0 | 9.6 / 20.6 ms | 779 | 305 MB |
| Laptop 1600×900 | nodes / full (built by script) | 60 s | 9.0 ms | 12.5 ms (80) | 0 % | 0 | 5.9 / 19.4 ms | 469 | 314 MB |
| Laptop at its panel's 2880×1800 | cells / full | 60 s | 21.7 ms | 34.7 ms (29) | 6.7 % | 0 | 18.3 / 35.5 ms | 878 | 276 MB |
| Laptop 2880×1800 | cells / scaled (70 % + FSR) | 60 s | 24.2 ms | 31.5 ms (32) | 0.8 % | 0 | 26.9 / 33.5 ms | 854 | 276 MB |
| Laptop 2880×1800 | cells / full+half (1440×900 drawn) | 60 s | 15.2 ms | 19.4 ms (51) | 0 % | 0 | 6.5 / 22.7 ms | 836 | 276 MB |
| Honor 600 | full 10 min, load, look | — | **to do: the user connects it later** (`honor.sh`) | | | | | | |

The 10-minute laptop run held steady (mean frame time per minute 8.9–9.1 ms).

**Note 9, first pass (overstated: read the next table).** The numbers in this table are Godot's frame `delta`.
Android does not honour the bench's "vsync off" (every run logs vsync mode 1: frames wait for the 60 Hz display),
and Godot smooths `delta` when vsync is on. So the p95 below hides the frames that stayed up for two refreshes. These
rows still compare the levers with each other (GPU time, memory, load), but not against the frame rule.

**Note 9** (SM-N960F, Android 10, Mali-G72, 2220×1080, Mobile renderer, release build, pre-built plant, 50 %
brightness (backlight setting 128 of 255, auto-brightness off), room temperature; 2026-10-16). The bench draws with
vsync off, as on the laptop; one 10-minute run with vsync on (as a shipped app draws) gave the same numbers. Peak memory is the app's PSS from `dumpsys meminfo`, sampled every 20 s (the app's own reading of /proc is
refused on Android), so a short peak between samples can be missed; the start's peak is measured separately below.

| Preset | Run | Median | p95 (fps) | > 33 ms | > 100 ms | Max | GPU median / p95 | CPU median | Draw calls p95 | Peak PSS | Battery temp |
|---|---|---|---|---|---|---|---|---|---|---|---|
| lean | 3 min | 21.2 ms | 28.3 ms (35.4) | 0.2 % | 0 | 57 ms | 14.0 / 18.4 ms | 1.8 ms | 526 | 501 MB | 30.6 → 31.7 °C |
| lean+texraw (the round-1 import; bolts and fins now in 6 m cells) | 3 min | 22.9 ms | 34.7 ms (28.8) | 8.2 % | 1 | 103 ms | 18.9 / 33.7 ms | 1.6 ms | 515 | 768 MB | 31.9 → 32.8 °C |
| lean+vis | 3 min | 19.7 ms | 26.9 ms (37.2) | 0.2 % | 0 | 48 ms | 13.4 / 18.1 ms | 1.7 ms | 462 | 500 MB | 33.0 → 33.4 °C |
| lean+tex1k | 3 min | 21.4 ms | 27.9 ms (35.9) | 0.2 % | 0 | 50 ms | 13.8 / 18.2 ms | 1.7 ms | 527 | 373 MB | 33.8 → 34.2 °C |
| lean+lod | 3 min | 21.2 ms | 28.1 ms (35.6) | 0.1 % | 0 | 49 ms | 13.7 / 18.4 ms | 1.7 ms | 526 | 502 MB | 34.3 → 34.7 °C |
| **full** (first rung of the ladder) | 3 min | 22.2 ms | 28.3 ms (35.3) | 0.2 % | 0 | 61 ms | 17.6 / 21.9 ms | 1.9 ms | 606 | 499 MB | 34.7 → 35.5 °C |
| **full**, plugged in | **10 min** | 22.2 ms | **27.7 ms (36.1)** | 0.2 % | **0** | 51 ms | 17.7 / 22.2 ms | 1.9 ms | 606 | 498 MB | 35.2 → 38.2 °C, thermal status 0 → 1 |
| **full**, on battery (the app started the walk 30 s after Android reported discharging; on battery throughout, checked every 5 s) | **10 min** | 22.2 ms | **28.4 ms (35.2)** | 0.3 % | **0** | 67 ms | 17.8 / 22.2 ms | 1.9 ms | 603 | not sampled (no adb on battery) | 31.3 °C at start; battery 95 → 88 % |
| **full**, plugged in, **vsync on** (as a shipped app) | **10 min** | 22.2 ms | **28.3 ms (35.3)** | 0.4 % | **0** | 84 ms | 17.7 / 22.2 ms | 1.9 ms | 606 | 503 MB | 28.8 → 32.6 °C, thermal status 0 |
| full, on battery except the first ~14 s of the walk (about 9 s of it measured; supporting only) | 10 min | 22.2 ms | 28.4 ms (35.2) | 0.3 % | 0 | 80 ms | 17.8 / 22.2 ms | 1.9 ms | 606 | — | 33.0 °C at start |

Mean frame time per minute over the 10-minute plugged run: 21.9, 21.8, 21.7, 21.7, 22.1, 21.6, 21.9, 22.1, 22.0,
21.9 ms; on battery 21.9, 22.0, 22.0, 22.0, 21.9, 21.9, 21.7, 21.9, 21.8, 22.1 ms (no thermal drop in either). A first
battery run that started the walk before the cable was out was discarded. **Note 9, frame times by the clock (the measurement that counts).** Since 2026-10-16 11:40 the bench times each
frame with the wall clock (`Time.get_ticks_usec` between frames, Godot's delta smoothing off). It reports how many
frames stayed on the 60 Hz screen for one refresh (≤ 17.5 ms, 60 fps), two (≤ 34.2 ms, 30 fps) or more, and it
logs every frame over 100 ms with where the camera was. The walk now also takes in the heaviest views: up over the
pump bay at 12 m, along it with everything in sight, and down from the far corner looking over the whole plant.
That makes a 90 s loop.

| Preset | Run | Median | p95 (fps) | Frames 1 / 2 / ≥ 3 refreshes | > 100 ms | Max | GPU median / p95 | Draw calls p95 | Peak PSS | Battery |
|---|---|---|---|---|---|---|---|---|---|---|
| full, plugged in | 3 min | 17.0 ms | 33.9 ms (29.5) | 62.4 / 35.5 / **2.1 %** | 0 | 90 ms | 17.4 / 22.3 ms | 664 | 599 MB | 28.9 → 29.9 °C |
| **full, on battery** (walk started 30 s after Android reported discharging; on battery throughout) | **10 min** | 17.1 ms | **33.8 ms (29.5)** | 61.9 / 36.4 / **1.7 %** | **1** | **122 ms** | 17.3 / 22.1 ms | 664 | not sampled | 98 → 93 %, 30.0 → 33.1 °C |
| full, plugged in | 10 min | 17.1 ms | 33.8 ms (29.6) | 61.8 / 36.6 / 1.6 % | **2** (121.6 ms at 230.1 s, 119.4 ms at 410.1 s) | 122 ms | 17.4 / 22.1 ms | 664 | 511 MB | 32.9 → 35.3 °C |
| **lean+vis, on battery** (walk started 30 s after Android reported discharging; on battery throughout) | **10 min** | 17.1 ms | 33.8 ms (29.6) | 63.2 / 34.9 / **1.9 %** | **0** | **79 ms** | 14.5 / 18.7 ms | 479 | not sampled (505–630 MB plugged) | 100 → 97 %, 31.7 → 32.4 °C |
| **lean+vis**, plugged in | 10 min | 17.0 ms | 33.8 ms (29.6) | 64.4 / 33.7 / **1.9 %** | **0** | **52 ms** | 14.4 / 18.7 ms | 479 | 504 MB | 35.3 → 35.3 °C |

What this shows:
- **The phone draws at 60 or 30 fps, nothing in between.** The GPU needs 14–22 ms per frame. That is more than one
  refresh (16.7 ms) and far less than two, so about 62 % of frames are shown for one refresh and 36 % for two. A
  frame held for two refreshes is exactly 30 fps on the screen, but by the clock it measures 33.1–34 ms. So the
  95th-percentile frame is 33.8 ms (29.6 fps) in every run, whatever the preset. The share of frames slower than
  30 fps on the screen (three refreshes or more) is 1.6–2.1 %, against the 5 % the rule allows.
- **`full` has a repeatable hitch of about 120 ms.** It came at exactly the same place twice, 180 s apart: the corner
  at (−5, 1.7, 4), where the walk turns to climb over the bay. The battery run had the same one. `lean+vis` never
  showed it (worst frame 52 ms). Its cause is not known yet: a shadow or LOD update when the whole plant comes into
  view is the first suspect.
- **The lighter presets do not buy margin against vsync.** `lean+vis` saves 3 ms of GPU time per frame but still
  needs more than one refresh, so its p95 stays at 33.8 ms. Real headroom would need either frames under 16.7 ms
  (about 25 % less GPU time than `lean+vis`), or a steady 30 fps cap: every frame held for two refreshes, by design.

**Load time** (`full`, pre-built plant, baked shaders), from the launch in the phone's log until the first frame
has been drawn: first start after clearing the app's data 5.8 s (2.1 s of it the first frame's pipeline compiles;
peak PSS 597 MB, sampled every second), second start 1.35 s (500 MB), the plant built by script instead 1.4 s.
Rule ≤ 15 s: met. (A first measurement stopped the clock when the first frame was processed rather than drawn: 3.3 s
and 1.3 s.) **APK** of the bench: 182 MB, of which the engine is 71 MB
and the three texture tiers 69 MB (2048 px ETC2), 17 MB (1024 px) and 55 MB (the lossless comparison set); a
shipped app carries one or two tiers (sizes uncompressed; the APK compresses the engine).

**Look on the Note 9:** the 10 viewpoints captured on the phone (`full`, Mobile renderer, 2220×1080) and looked at
side by side with the laptop tier (Forward+, `full`). Everything a trainee needs is the same on both: the valves with
their red handwheels and bonnets at 2 m and 10 m, the pumps' motors with their fins (near and on the next pumps),
the pipes on the rack by colour, the rack's structure, the platforms, the whole plant from afar. The phone lacks the
laptop's ambient occlusion (the Mobile renderer has none) and its shadow edges are blockier; neither hides a part,
a label or a state.

**Load time (laptop, exported release build, pre-built plant, baked shaders):** from engine start until the first
frame has been drawn: first start with no shader cache 2.66 s (the plant loads in 9 ms; the first frame's pipeline
compiles take 1.26 s; peak RSS 642 MB), second start 0.77 s (236 MB). Rule ≤ 5 s: met. (A first measurement stopped
the clock when the first frame was processed rather than drawn: 1.26 and 0.72 s.)

**Look of the lower presets (drawn on the laptop):** the 10 viewpoints compared side by side between the laptop
tier (Forward+, full, 1600×900) and the phone presets drawn with the Mobile renderer at the Note 9's 2220×1080 on
this laptop (`lean`,
`lean+vis+tex1k+lod`). On every viewpoint the same equipment is there and recognisable: the valves with their red
handwheels and bonnets at 2 m and 10 m, the motors' fins at 2 m and on the next pumps, the pipes on the rack by
colour, the platforms, the rack's structure. What differs is sharpness (60 % resolution with FSR: textures and far
edges softer) and the absence of SSAO in the Mobile renderer; no part a trainee needs is missing, so these presets
stay usable should a heavier plant need them.

Findings:
- **The texture import was the biggest cost**, not geometry. The round-1 bench imported its textures lossless and
  without mipmaps (script-made materials skip Godot's 3D detection). With VRAM-compressed, mipmapped textures the
  same scene goes from 44 to 80 fps (p95) on the laptop and from 28.8 to 35.4 fps on the Note 9 (`lean`), with
  a third less memory on the phone (768 → 502 MB) and no 100 ms frame.
- **With that fixed, the Note 9 is at the edge of the rule**, not above it as the first pass said (see the
  clock-timed table). 98 % of frames are shown at 30 fps or better on its 60 Hz screen, but by the clock the 95th
  percentile is 33.8 ms (29.6 fps). `full` has a repeatable 120 ms hitch; `lean+vis` does not. There is no thermal
  drop and memory is about 0.5 GB.
- **Load time is no longer an issue**: 5.8 s on the Note 9 on a first start, 1.35 s after, with the pre-built plant
  and baked shaders (the round-1 20–28 s were mostly the bench reading every mesh back from the GPU).
- **The laptop tier meets its rule at 1600×900** (82 fps for 95 % of frames over 10 minutes). At this laptop's native
  2880×1800 the full preset is 29 fps (GPU-bound); drawing at the panel's logical 1440×900 gives 51 fps on the private
  display, where presenting a 2880×1800 frame through Xwayland costs about 9 ms more than the GPU's 6.5 ms. The laptop
  preset for a full-screen HiDPI window needs one run on the real display (and a Windows laptop when there is one).

## Conclusion

**Decided: Godot 4.** The Note 9 tier uses the `lean+vis` preset.

**The rule, as the user reads it (2026-10-16):** at least 95 % of frames are shown at 30 fps or better on the Note 9's
60 Hz screen, and a frame held for two refreshes counts as 30 fps. By the clock such a frame measures 33.1–34 ms, so
the 95th-percentile frame time alone (33.8 ms) is not the test. The test is the share of frames held for three
refreshes or more, which must stay at or under 5 %.

**The confirming run** (`lean+vis`, 10 minutes on battery; the walk includes the heaviest views):
- frames shown at 30 fps or better: 98.1 % (63.2 % for one refresh, 34.9 % for two), so 1.9 % slower, against the
  5 % allowed;
- spikes: no frame over 100 ms after the first 5 s; the worst was 79 ms;
- heat: no thermal drop (per-minute means 20.7–21.4 ms); battery 100 → 97 %;
- memory: 505–630 MB sampled plugged in, against 1.5 GB;
- load: 7.6 s to the first drawn frame right after a fresh install, 1.4 s after that, against 15 s.
- Unrelated to the engine: the battery run's own start took 50 s, because the phone's screen was off when the app was
  launched. Its log shows the window stopped right away and shown 43 s later.

**What `lean+vis` gives up next to `full`:**
- the screen is drawn at 60 % of its resolution with FSR, so textures and far edges are softer;
- shadows reach 40 m instead of 80 m;
- bolts and motor fins are not drawn beyond the distance where they are under a pixel, with a fade.

None of that is what R9a protects. The look viewpoints drawn with that preset show the same equipment, handwheels,
bonnets and pipe colours as `full`. On the phone, `full` differs from the laptop tier only by the missing ambient
occlusion and blockier shadow edges; neither hides a part, a label or a state.

**`full` is not for the Note 9:** it has a repeatable hitch of about 120 ms at one corner of the walk, every 180 s, on
battery and plugged in. Its cause is not known yet; find it before `full` is used on any phone.

**Margin:** small. Any heavier content shows first as more frames held for three refreshes. The real plant must be
measured the same way as it grows (R9; the regression rule).

Still to measure, none of it bearing on the decision:
- the Honor 600 (`honor.sh`; to do, the user connects it later);
- the laptop's full-screen preset at its native 2880×1800, on the real display;
- a Windows laptop;
- battery drain over 30 minutes (a 10-minute walk took 3–7 %).

**When to revisit:** after the measurements; if Godot's security response does not improve and the app starts to
load content from others.
