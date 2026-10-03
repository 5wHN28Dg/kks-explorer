# 0041 The 3D plant: which engine (investigation)

Date 2026-10-03 · Scope: docs/plant3d/REQUIREMENTS.md (R8 devices, R9 photo-realistic and scaling) · Status:
**investigating**: desk research done, the deciding measurements not yet (plan below).

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

Rules in docs/plant3d/MEASUREMENTS.md, written before measuring. One test scene, built the same way in each engine
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

**When to revisit:** after the measurements; if Godot's security response does not improve and the app starts to
load content from others.
