# 0060 Walkdown Plant: a first start the phone's pipeline compiler can keep up with

Date 2026-10-20 · Scope: `apps/plant3d` (app/main.gd, kit/materials.gd, kit/weathered.gdshaderinc, ui/bindings.gd,
builder/plant_builder.gd, app/plant.gd, app/quality.gd, project.godot, phone/launch.sh, tests/test_launch.gd and the shot scripts) · Status: **decided** under the task's go-ahead (the
Note 9's load-time rule, wiki 3D-plant "Metrics and rules": start to the first walkable frame ≤ 15 s) · Extends 0054,
0057; no new dependency

**Question:** the Note 9's first start after an install measured 14.8–15.8 s, with starts near 20 s now and then
(0057). Where do the 15 s go, what makes the 20 s ones, and how does the start get under 15 s with a margin (every run
≤ 13.5 s) without changing the rule, the look or the frame, spike and memory rules?

## Findings

[V] measured here (2026-10-20) on the Note 9 (release build, `lean+vis`, plugged in, data cleared before each first
start), with `phone/launch.sh` (logcat's clock, the app's `LAUNCH` lines), a per-thread sampler of
`/proc/PID/task/*/stat` every 0.2 s, and a staged start that drew a frame after each step; [S] Godot 4.7.2 source.

| | Finding | Source |
|---|---|---|
| Where the 15 s went | process and engine 0.45 s; the rendering server's start 1.6 s (0.5 s on a second start: Godot's own shader cache); the main scene's scripts 1.1 s; loading the plant 1.0 s; the map, the HUD and the UI 0.9 s; then **9.6 s waiting for the first frame**, the same on a second start | [V] |
| What the first frame waits for | pipeline compilation: Godot queues every surface's pipelines on its worker threads (drawn or not) and the first draw waits for its ubershaders. The Mali driver compiles them **one at a time**: for 10 s one worker thread at 100 % on one big core, the others idle. A lit surface's ubershader took 0.6–0.9 s at 1.8–2.3 GHz; unshaded and depth ones a fraction of that | [V] sampler; [S] `pipeline_hash_map_rd.h`, `render_forward_mobile.cpp` |
| The ~20 s starts | the same serial compiles with the big cores at 1.47 GHz instead of 1.8–2.7 (the start before took 20.8 s, every compile ~1.6× longer). Not the temperature (29–35 °C, thermal status 0), not the I/O (iowait 0) nor memory (3 GB available); the clock is the phone's governor's. That trace was not kept, and main's build could not be remade to catch another (its lightmap bake crashed in a fresh worktree, twice): `launch.sh` now records the big cores' median clock per run, and of the 46 first starts `launch.sh` timed during and after the change, the one with a lower big-core clock (1,586 MHz median) was the slowest of its ten, at 9.66 s; none came near 20 s | [V] sampler, `scaling_cur_freq` (one run) |
| What compiled | besides the weathered shader (one lit ubershader per pass and vertex format): Godot's standard material for the lamps (the halls' lamp lenses and the kit's lamps, lightmapped and not), primitive meshes for the doors (no vertex colours: a vertex format of its own) and the UI's markers and lamps on the parts (a standard material lit and unlit, primitive meshes). The UI's two cost 2.4 s, the lightmap's variants 2.3 s, the canvas (HUD) about 0.8 s | [V] staged start: 30 surface + 10 specialization pipelines |
| The material's own code | a weathered shader cut down to its colour compiles the start 0.6 s faster: Godot's lighting code is most of each ubershader | [V] |
| The order | the compiles start only when a frame is drawn, and the HUD's canvas pipelines are compiled in the draw itself, behind the queue. A frame drawn with the plant hidden queues the plant's pipelines without waiting for them (hidden surfaces are compiled too) | [V], [S] `_update_dirty_geometry_pipelines` |
| A second start | Godot saves the pipeline cache when 3 MB of new pipelines have built up, or on a clean exit; a start makes less, and Android ends the app without one: the second start compiled everything again (12.7–13.1 s before, 7.0 s after the changes below) | [V], [S] `RenderingDevice::update_pipeline_cache` |
| What does not apply | a loading screen as the first frame (the rule is the first *walkable* frame); turning ubershaders off (no setting; a driver workaround for one Adreno only); a pipeline cache shipped in the APK (driver- and device-bound, read before any script runs) | [S] `rendering_device_driver_vulkan.cpp` |

## Choice

- **One lit shader, one vertex format.** The lamps are the weathered shader with its new `emission` (their light as
  the standard material's emission at energy 2, also in the bake); the UI's markers and lamps on the parts are a clean
  weathered material (`Materials.plain`), lit or not; doors and markers are ArrayMeshes with white vertex colours
  (`Materials.plant_mesh`). Every lit surface now shares the plant's pipelines (`tests/test_launch.gd` checks the built
  plant and the UI's markers).
- **A sky frame first.** With a tier already known (phones always; a desktop after its probe, or with a tier chosen in the settings or on the command line) the start draws the sky
  alone, loads the plant hidden, draws again (the plant's pipelines start compiling), makes the map, the HUD and the UI
  meanwhile, and only then shows the plant. The tier's settings for the plant's pieces and materials are applied once, after the load (before it, the materials would be loaded and freed for nothing). The trainee sees the sky for a few seconds instead of a black screen; the
  log's "first frame" is still the first walkable one. Without a display (the tests) the start runs in one go.
- **The pipeline cache saved every 0.25 MB** of new pipelines (`rendering/rendering_device/pipeline_cache/save_chunk_size_mb`),
  so a second start finds it.
- **Before adding a shader or a vertex format**, count it: `pipelines compiled` in the app's log, and
  `phone/launch.sh` on the Note 9 (each lit one is most of a second there, one after another).

## Measured (2026-10-20)

Note 9, release builds signed as published, first start after `install -r` and the data cleared, **plugged in** (fine
for a launch time; the walk too), 30 s between runs, the phone at 33–39 °C; start = Android's `START`, end = the app's
`first frame drawn` (`phone/launch.sh`). "After" is the final build (a4ad5a3).

**What "first frame" means here.** The rule is "start to the first walkable frame". The sky frame drawn while the plant
loads does not count: the time is taken at the first frame drawn after the plant is shown, the HUD with the touch
sticks and the UI made (`started` is sent then). Godot draws a visible surface only once its pipeline is compiled
(`get_pipeline(…, wait)` on the last ubershader try, [S] `render_forward_mobile.cpp`), so that frame has the whole
plant. Checked on screen too (`screenrecord` from before the start, four first starts over the builds): the sky shows
first, the plant with the HUD and the sticks at 9.23, 9.03, 9.08 and (final build) **8.47 s** after the launch
animation began, as the log says; a swipe on the look stick 1.3 s after that frame turned the view (the controls work
from it).

| | Rule | Main (24c0dd1: main bf979ee with the stage log) | After (final build) |
|---|---|---|---|
| First start, each run | ≤ 15 s | 14.86, 15.06, 14.72, 15.50, 15.46, 15.93 s; in 0057 also 19.66 and 19.76 s | 8.69, 9.52, 8.66, 8.77, 9.66, 8.62, 8.84, 8.60, 8.79, 8.85 s; the walk's start 8.40 s |
| Second start (data kept) | | 12.70, 13.11 s | 6.78 (the start before ended 2 s after its first frame: cache not yet saved), 3.12, 3.07 s |
| Pipelines for the first frame (surface + specialization) | | 30 + 10 | 13 + 7 |
| Frames shown at ≥ 30 fps, 10-minute walk (SurfaceFlinger) | ≥ 95 % | 99.08–99.65 % (0057) | 99.64 % |
| Frames over 100 ms after the first 5 s | none | none | none (app's worst 70.1 ms; SurfaceFlinger: the start's three holds before the first walkable frame, a 150 ms frame right after it and a 100 ms one 1.2 s after it, then nothing over 67 ms) |
| Peak PSS | ≤ 1.5 GB | 1,011–1,052 MB | 658 MB |
| GPU time median / p95 | | 18.8 / 25.3 ms | 18.8 / 25.2 ms |

Earlier builds of this change, for the record: before the reviews (the tier's materials lost on the early start: the
phone drew the full tier's wear) 9.42, 9.50, 9.39, 9.10, 9.28, 9.32, 9.26, 8.98, 9.23, 8.97 s, walk 99.62 %, 916 MB;
with the materials applied twice (loaded and freed once before the plant) 9.75, 9.13, 9.46, 9.37, 9.47, 9.44, 9.33,
9.46, 9.10, 9.15 s. The slowest final run (9.66 s) is the only one whose big cores ran at a lower median clock
(1,586 MHz instead of 1,794): the same effect as the ~20 s starts, now on far fewer serial compiles.

Where the start goes now (median of the ten, from `START`): the process and the engine 0.42 s; the main scene ready
3.16 s (the rendering server's start and the scripts); the tier and the sky frame 3.34 s; the plant loaded 4.06 s; its
lightmap and the tier's materials 4.26 s; the hidden frame (the plant's pipelines start compiling) 5.07 s; the map, the
HUD and the UI 5.88 s; the first walkable frame 8.78 s: 2.9 s for what is left of the pipelines.

No hitch where areas first come into view: Godot queued every surface's pipelines before the first frame (hidden ones
too), and the walk's 50 ms frames (3 refreshes; 0.36 %) are spread over the ten minutes, 0 to 8 in every 30 s, not
bunched in the first lap.

**The two early frames** (150 and 100 ms within 1.2 s of the first walkable frame, inside the rule's first 5 s), told
apart on 2026-10-20 with the app's `EARLY` lines (every frame over 40 ms in the first 5 s, with the pipelines compiled
in it) on four first starts, two with the cache's saves off (`pipeline_save_mb=1024` in `walk.txt`, which `frames.sh` pushes after clearing the app's data; the app now logs the value it took):

- **Not the pipeline cache's saves:** the same frames with them off (166-256 ms and 113-118 ms, against 217-256 and
  115-118 ms with them).
- **The first frame after the first walkable one** (166-256 ms, the one SurfaceFlinger counts with the start's last
  hold): no pipeline compiled in it, the scripts no slower than on the laptop; the display's composer logged the
  frame before as not retired for 200 ms (`waitPreviousFrameDone`): GPU work, the first frame drawing the whole
  plant. Left as it is: within the start's 5 s, and no cheap lever found.
- **The 100 ms frame 1.3-1.5 s after it** (113-121 ms in the app): the walking directions' warm-up (`app/walk_route.gd`)
  drew one chevron with alpha 0 to compile its pipeline, and a drawn surface waits for its pipeline. It now queues
  the pipeline with a hidden chevron, which Godot compiles on its worker threads: that frame is 16-17 ms (three
  first starts), the pipeline still compiled before the directions are first shown.

After this change (release build, plugged in, data cleared before each first start): first walkable frame 8.67, 8.72,
8.73 s with the big cores at their usual 1,794 MHz median and 10.30, 10.37 s in two starts at 1,469 MHz (the
governor's slower clock, as above); the 10-minute walk 99.65 % of frames at ≥ 30 fps, nothing over 100 ms after the
first 5 s (worst 57.8 ms in the app; SurfaceFlinger: after the start's holds no frame held 4 refreshes or more, where
the build before had the warm-up's 100 ms at +1.3 s), peak PSS 651 MB, first walkable frame 8.59 s.

Look: the full tier from the laptop (lightmap off on both: main's could not be baked here), six views from the control
room to outdoors, main against the final branch: identical but for the HUD clock's seconds.

The laptop, `full` at 1600×900, release build of the final code, a first start (empty Godot data folder), the 10-minute
`frames` walk on a quiet machine (no other agent, build, test, emulator or VM; load average up to 1.1; the user's editor
now and then): frame **p95 21.8 ms** (rule ≤ 16.7 ms: **not met**), median 7.7 ms, 85.3 % of frames ≤ 17.5 ms, worst
45.9 ms; GPU p95 7.8 ms; first frame 3.36 s after the engine started (rule ≤ 5 s), 15 + 9 pipelines. The long frames
are not this app's GPU work (7.8 ms at p95). Main against this branch on the same machine, unbaked exports, 300 s each,
alternating: main p95 21.6 and 21.6 ms (GPU p95 7.5), the branch 20.8 and 21.2 ms (GPU p95 7.1 and 7.3): this change
does not make the laptop worse. An earlier pass of this change measured 15.6 ms, but with the tier's materials lost on
the early start (1024 px textures in the full tier instead of 2048): not a valid result. The laptop's 60 fps rule stays
open, as in 0057.

**When to revisit:** when Godot can turn ubershaders off per project, or ships pipeline caches; if a phone in the
measurement set compiles in parallel (the sky frame then matters less); before adding a shader, a material kind or a
vertex format (count its pipelines on the Note 9).
