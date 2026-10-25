# 0064 Walkdown Plant's people on screen: skinned near, posed meshes far, no crowd simulation, a fixed share per tier

Date 2026-10-22 · Scope: docs/PLANT3D.md §18.1, §18.3–§18.4; `apps/plant3d` (people's presentation, builder) ·
Status: **decided** (milestone A1 as built, below); the counts are targets that milestone A1 measures on the Note 9 (MILESTONES.md)
· Extends 0041, 0054, 0059, 0060

**Question:** how are up to 200 people (logical, 0062) drawn and animated within the frame rules on the Note 9
(`lean+vis`: GPU median 18.8 ms, p95 25.2 ms of the 33.3 ms frame; first start 8.8 s of 15; peak PSS 658 MB, 0060)
and on laptops, without a per-frame cost that grows with the population?

## Findings

| | Finding | Source |
|---|---|---|
| Skinning | Godot's RD renderers (Forward+, Mobile) skin in a compute shader (`servers/rendering/renderer_rd/shaders/skeleton.glsl`) | [S] 4.7 |
| Godot's own advice | "Animation and vertex animation such as skinning and morphing can be very expensive on some platforms. You may need to lower the polycount considerably for animated models, or limit the number of them on screen … reduce the animation rate for distant or occluded meshes, or pause the animation entirely" | [D] tutorials/performance/optimizing_3d_performance |
| Animation rate | `AnimationMixer.callback_mode_process` MANUAL: the app advances each tree itself | [D] class_animationmixer |
| Many copies | MultiMesh has no skinning; per-instance animation only in a vertex shader (vertex animation textures) | [D] class_multimesh, "Animating thousands of fish" |
| Impostors | none built in; the only Godot impostor addon found (wojtekpil/Godot-Octahedral-Impostors, MIT) is a Godot 3 project last changed in 2021 | [K] GitHub |
| Avoidance | NavigationAgent3D RVO: its own space, no knowledge of the mesh or collisions; cost falls with fewer neighbours; the docs suggest staggering path queries | [D] class_navigationagent3d, navigation optimisation |
| Paths at run time | a search costs 0.44–1.1 ms on the laptop, ~3.3× that on the Note 9 (0059) | [V] 0059 |
| Pipelines | each new lit pipeline is 0.6–0.9 s of the Note 9's first start; count before adding a shader or vertex format | [V] 0060 |

## Choice

- **Three bands by distance:** skinned avatars near (Note 9 ≤ 6 within 25 m; laptop ≤ 24 within 40 m; two mesh LODs);
  posed static meshes beyond (to 80 m on the phone, 150 m on laptops): each body in 6 poses (stand, walk A, walk B,
  sit, work, carry) made by the build from the same assets, one MultiMesh per pose and body with the outfit's colours
  as per-instance data (8 bodies: at most 48 draw calls, budget 50), the pose switched 4 times a second for walkers;
  nothing beyond. No impostors (no maintained Godot 4 implementation; posed meshes give the same far look for less
  work).
- **Animation advanced by the app:** 30 Hz within 10 m, 15 Hz further, paused out of view; one AnimationTree per
  skinned avatar, created from a pool of the band's size (never per person).
- **No run-time path search and no avoidance for people:** each way's path is baked as a polyline with the navigation
  mesh (0059) and avatars are placed along it by time; lanes and a sidestep near the trainee (PLANT3D.md §18.1).
- **Pipelines:** avatars use the plant's one lit shader (0060); the skinned meshes' and props' pipelines are compiled
  in the hidden frame; the added first-start time is counted (≤ 1.5 s).
- **The share** (PLANT3D.md §18.4): ≤ 2.5 ms GPU median, ≤ 2 ms CPU a frame, ≤ 100 MB PSS on the Note 9; measured
  in A1 by the frames walk among 6, 12 and 24 people. The counts are set from that measurement, inside the frame
  rules; fewer than 4 skinned on the phone is a question for the user (MILESTONES.md).

**When to revisit:** A1's measurement; a Godot release with built-in impostors or GPU-instanced skinning; if people
in the posed band read as statues to trainees (then a vertex-animation walk cycle in the posed band's shader, counted
as a new pipeline).

## As built (milestone A1, 2026-10-25)

- **Bands as chosen**, with: an AnimationPlayer per pooled avatar (manual process, crossfades by speed: still,
  walk, run, stairs, ladder) instead of an AnimationTree; the outfits' colours baked into each look's vertices (eight
  looks, each with a road variant: the hat carried, a phone in hand) instead of per-instance colours, so the posed
  band is one MultiMesh per look and pose (≤ 48 draw calls). Slots: the nearest within the range, people the trainee
  works with first, kept against someone less than 2 m nearer; LOD0 and new slots taken 2 m inside their edges.
- **Pipelines:** the people are the plant's one shader and vertex format (bones and weights only for the skinning
  compute), made in the plant before its hidden frame; the start's pipeline count and first walkable frame
  unchanged within the spread (below).
- **Measured** on the Note 9 (release build, `lean+vis`, the 10-minute `frames` walk with N skinned people round the
  walker, every run started at ≤ 30 °C, counts interleaved; full quality: shadows, LODs and clip rates as above):

| People | Runs | Frames ≥ 30 fps, median (range) | GPU median, added | Frames > 100 ms | First walkable frame | People CPU (mean) |
|---|---|---|---|---|---|---|
| 0 | 3 | 99.39 % (98.69–99.43) | 20.6 ms | 0 | 11.33–11.86 s | — |
| 6 | 2 | 99.39 % (99.35–99.42) | +0.15 ms | 0 | 10.83–11.08 s | 0.70 ms |
| 12 | 2 | 99.40 % (99.35–99.45) | +0.3 ms | 0 | 10.97–11.03 s | 0.91 ms |
| 24 | 2 | 98.85 % (98.59–99.10) | +0.7 ms | one of 112 ms | 11.35–11.51 s | 1.33 ms |

  Peak PSS 1,102–1,158 MB in every run. Third runs for 6 and 12 were not possible (the shared phone stayed above
  30 °C for four hours). Warm runs (34–36 °C) spread more than people cost: an earlier series on a warm phone ranged
  94.98–97.81 % with no order by count.
- **The counts:** the phone 12 skinned (6 and 12 meet every rule and the share; 24 had one frame over 100 ms);
  the laptop 24, as the spec (not measured on a laptop here). The Honor was not attached and is not measured.

