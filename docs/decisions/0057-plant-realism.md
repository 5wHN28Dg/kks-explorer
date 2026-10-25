# 0057 Walkdown Plant: realism by a baked lightmap, a photographed sky and weathered materials, one asset set

Date 2026-10-16 · Scope: `apps/plant3d` (builder, kit materials, app lighting), wiki 3D-plant R9 and R9a · Status:
**decided** under the task's go-ahead (the realism pass the user asked for: R9 is a hard requirement) · Extends 0041,
0054

**Question:** the first train looked like a clean engineering walkthrough: flat light, no bounce or ambient occlusion,
uniform materials, a plain sky, a bare gravel plane to the horizon. What makes it look like a plant in service, on the
laptop (`full`, Forward+) and on the Note 9 (`lean+vis`, Mobile renderer), with one asset set, within the frame,
memory, load and size rules (wiki: 3D-plant, measurement rules), and with nothing a trainee needs given up (R9a)?

## Findings

[D] Godot 4.7 documentation and source at `4.7-stable`; [V] verified or measured here (2026-10-16).

| | Finding | Source |
|---|---|---|
| Baked light in every renderer | LightmapGI works in Forward+, Mobile and Compatibility; SDFGI, VoxelGI, SSAO, SSIL and volumetric fog are Forward+ only | [D] tutorials/3d/global_illumination |
| Baking from a script | `LightmapGI::bake` is not bound to scripts; only the editor's "Bake Lightmaps" button runs it, and the lightmapper needs a RenderingDevice (no `--headless`). The editor, started on a private display with a plugin that opens the bake scene, selects its LightmapGI and presses the button, bakes the whole first train in 72–150 s on the Iris Xe | [S] `scene/3d/lightmap_gi.cpp`, `editor/scene/3d/lightmap_gi_editor_plugin.cpp`; [V] `builder/bake/` |
| What gets baked | MeshInstance3Ds with UV2 and GI mode static; not MultiMeshes. Lights with bake mode `dynamic` add their bounce only; `static` lights their direct light too. The users' paths are relative to the LightmapGI node, so a LightmapGI beside the areas under the app's plant node finds the meshes the bake scene had | [S] the same file |
| UV2 at build time | `ArrayMesh.lightmap_unwrap` (xatlas) runs headless, keeps vertex colours and tangents: 178 merged meshes of the HRSG in 0.7 s | [V] |
| HDR lightmaps on the Note 9 | the lightmap imports as ASTC HDR for mobile; the Mali-G72 has no ASTC HDR, so Godot converted it to RGBA half floats at load ("ASTC_4x4_HDR not supported by hardware, converting to RGBAHalf"). With `hdr_compression` disabled the importer keeps RGBE9995 (4 bytes a texel, sampled on every Vulkan GPU) | [V] logcat; [S] `editor/import/resource_importer_layered_texture.cpp` |
| The lightmap's bicubic filter on Adreno (added 2026-10-23) | On the Honor 600 (Adreno 722, Vulkan driver 0800.74, Mobile renderer) Godot's default bicubic lightmap filter drew the bake as dark and pale blocks a texel or two wide on every outdoor surface, on both tiers. Switching only the filter to bilinear (`RenderingServer.lightmaps_set_bicubic_filter`) drew it clean; uploading the lightmap again as RGBA half floats (instead of RGBE9995), or the shadowmask as uncompressed RGBA8 (instead of ETC2 R11), did not. The Note 9's Mali-G72 draws the bicubic filter right; its screenshots of the same walk with bilinear show no difference to see at the phone's size (bilinear can show a texel's step at a baked shadow's edge). Phones and any Adreno now read the bake bilinear (`app/lighting.gd` `lightmap_bicubic`); Adreno outside phones (Windows on Snapdragon) is included as a precaution, not measured | [V] on-device bisection, screenshots; [S] `scene_forward_mobile.glsl` `textureArray_bicubic` |
| What the phone's first start waits for | pipeline compilation: the kit's main compiled 33 pipelines for its first frame; the first realism build 75 (19–23 s from launch to the first frame on a first start, 10–14 s before). A two-sided shader variant with the structures' own vertex format cost 20, a see-through (discarding) grating variant 7, Godot's standard shader for the plain pieces 13 more; one weathered shader for every lit surface, walls' back faces as geometry and one vertex format bring it to 35 | [V] `RenderingServer.get_rendering_info(PIPELINE_COMPILATIONS_*)`, first frame with an empty shader cache |
| Light probes for instanced parts | Godot gives a MultiMesh one probe sample for its whole box (a 12 m cell): pumps' motors, valve actuators and handwheels in shade or in a hall came out almost black, their colours lost. With GI mode disabled they take the sky's ambient light and keep their colours | [V] captures |
| Cost of each laptop effect (full tier, 40 s of the frames walk, GPU p95) | SSIL about +6 ms, volumetric fog about +4 ms, glow (default levels) about +10 ms, SSAO (low quality, half size) about +7 ms, SDFGI +16 ms and +360 MB of video memory; the lightmap, the weathered shader and the site cost under 1 ms | [V] `--fx_off`/`--fx_on` runs, a busy desktop sharing the GPU |
| The sky's light in the bake | (both figures at the sky energy π below) LightmapGI reads the sky through `RenderingServer.sky_bake_panorama`, which returns black for a sky no viewport has drawn (its radiance never processed): a sky handed to the LightmapGI alone baked almost no sky light, the shade on open ground was 0.035 of the sunlit ground on screen (linear output), against 0.23 once the sky stands in a WorldEnvironment the editor draws and the bake takes the scene's environment | [V] `builder/bake/bake_plugin.gd` (its guard reads 0.000 the first way and tenths the second); [S] `lightmap_gi.cpp` |
| Light units | Godot's lights shine π times what a sky of the same irradiance gives as ambient: with the sky scaled to a sun of 1, its energy must be π to keep the photograph's ratio (shade 0.35 of sun on open ground on screen, the photograph says 0.31) | [V] linear captures |
| The sky | a CC0 photographed sky (Poly Haven, "Kloofendal 48d Partly Cloudy (Pure Sky)", 2K Radiance HDR, 5.4 MB) has its sun unclipped; left in, it would light everything twice. Taking it out (pixels over 12 × the sky's mean within 0.2 rad of the brightest point) gives the sun's direction (47.9° up) and its light, and the sky's own light on the ground is 0.46 of the sun's | [V] `builder/sky.gd`; polyhaven.com/license |

## Choice

- **Light:** every static mesh gets lightmap UV2 at build time (0.33 m texel, 0.5 m on the ground), the bake runs
  after the content build on a GPU (`build.sh bake`, and `release` before it exports): the sky, the sun's bounce
  (`dynamic`), the halls' lamps (`static`) and the sun's shadow beyond its real-time distance (shadowmask). The sun's
  direct light and sharp shadows stay real-time on both tiers. Instanced and moving pieces take the sky's ambient light.
  The bake takes the sky from a WorldEnvironment the editor draws, and fails when the sky reads black. The halls'
  lamps reach the floor and pits have lamps of their own. The lightmap is RGBE9995: 6.3 M texels, 25 MB. CI does not bake (no GPU): its exports light by the sky and sun alone.
- **Sky and exposure:** the photographed sky without its sun, the sun as the DirectionalLight3D at the photograph's own
  ratio (its energy π in Godot's units), AgX tonemapping (contrast 1.25, exposure 0.85), a thin distance haze on both tiers.
- **Materials:** one weathered shader for every lit surface: the CC0 sets plus grime, run-off streaks, dust on top
  faces, rust, paint wear where hands go (vertex alpha by colour), wet ground round the cooling tower, jointed yards,
  the road's centre line, drawn bar gratings; the plain pieces (plates, dials, bands) the same shader kept clean. The
  phone skips the wear's sample and the ruts' two (its ground has the patches but no broken ruts or wandering track;
  since the polish pass, below, the ruts and the track take no samples and are the same on every tier);
  it draws the streaks, which read no texture of their own. A second, smaller program for the phone (compiled with
  the wear and the ruts left out, swapped onto the materials at start) made its first start slower, not faster (16.6
  and 16.8 s against 14.9 and 15.0 s), and was taken out.
- **The site:** concrete yards in the areas' bounds, gravel between, a ring road with kerbs and a drain, a boundary
  wall, the country to the far plane with low hills.
- **Per tier:** both tiers get the bake and the haze. SSAO (low, half size) was the laptops' at first; the second
  realism pass took it out: it cost the full tier about 6 ms of GPU time at the 95th percentile and with it the 60 fps
  rule (measured below), and the bake carries the shade under equipment and in corners. SSIL, volumetric fog, glow and
  SDFGI are left out: measured above, none shows a trainee anything the bake doesn't (R9a).
- **Halls (second realism pass):** each high-bay lamp is a downlight (a spot, inverse-square, its cone sized to the
  lamps' spacing) plus a wide dim cone for what its reflector lets out sideways; the floor is grey-green epoxy paint.
  Pools under the lamps, darker corners. An omni light per lamp (the first pass) washed the floor out evenly; an omni
  "spill" lit the ceiling close to each lamp, and the bake turned those hot spots into blotches over every floor and
  wall (too few of its bounce rays meet them), so no lamp's light reaches the ceiling. A lamp's energy is set from its
  height over the floor under it (a deck's where there is one, the deck's too for a lamp over its edge), and a deck
  of a hall has lamps under it for the floor below. Walls' streaks hang from the top of the face above them: the wall's,
  or an opening's head.
- **Tag plates:** every valve on a pipe and every child part with a plate point carries its tag plate (content).

## Measured (2026-10-16)

The release build (baked shaders, signed), `lean+vis` chosen by the app on the Note 9, a first start (data cleared),
10 minutes plugged in; the laptop `full` at 1600×900 for 10 minutes, back to back with main (bc5f820, which has the
interaction layer) and no emulator running, but with the user's desktop busy on the same GPU.

| | Rule | Main before this change | After |
|---|---|---|---|
| Note 9, frames shown at ≥ 30 fps (SurfaceFlinger) | ≥ 95 % | 99.79 % (the parts kit, before the interaction layer) | 98.76 % |
| Note 9, frames over 100 ms after the start | none | none (worst 54.8 ms) | none (worst 73.2 ms) |
| Note 9, peak PSS | ≤ 1.5 GB | 683 MB | 1,012 MB |
| Note 9, launch to first frame, first start | ≤ 15 s | 10.2–14.4 s | 14.8 s |
| Note 9, GPU time median / p95 | | 17.5 ms / — | 18.6 / 26.3 ms |
| Laptop, frames ≤ 17.5 ms / frame p95 / GPU p95 | 95 % / ≤ 16.7 ms | 76.1 % / 22.3 ms / 20.6 ms | 70.6 % / 24.4 ms / 21.7 ms |
| APK (`walkdown-plant.apk`) | ≤ 150 MB | 71 MB (before the Gradle export) | 117 MB |

The Note 9 meets every rule, the load time by 0.2 s: the first frame waits for the pipelines Godot compiles (35 with
the realism build alone, 33 before; the interaction layer adds its own), so a new shader or vertex format must be
counted (`pipelines compiled` in result.txt) before it is added. Its memory grew by a third (lightmap and sky 33 MB,
the rest not yet broken down). The laptop missed the 60 fps rule before this change too under the same load (0041's
82 fps was measured on a quiet machine); this change costs about 2 ms at the 95th percentile, mostly SSAO's. A quiet
laptop run is still to be made; if the laptop then misses, SSAO is the first lever.

## Measured, second realism pass (2026-10-20)

Same rules, on the merged code (main c80e71d against this pass on top of it). The laptop: `full` at 1600×900 for 10
minutes, main and the branch back to back, then again in the other order. Not a quiet machine: other agents' Godot
test and screenshot runs came and went (4 to 10 other Godot processes, load average 2.4 to 3.1); main on a quiet
machine (2026-10-17, older main) is in the first column. The Note 9: release builds, first start each (app data
cleared), plugged in, `frames.sh` (SurfaceFlinger), the phone let cool to about 33 °C between runs.

| | Rule | Main, quiet (older) | Main, now | Second pass |
|---|---|---|---|---|
| Laptop, frames ≤ 17.5 ms | 95 % | 85.5 % | 65.7 / 73.5 % | 97.1 / 93.1 % |
| Laptop, frame p95 / median | ≤ 16.7 ms | 23.2 / 9.1 ms | 34.9 / 12.0, 26.7 / 10.8 ms | 11.0 / 8.3, 24.0 / 8.7 ms |
| Laptop, GPU p95 / median | | 21.4 / 8.5 ms | 30.9 / 11.1, 24.5 / 9.9 ms | 8.5 / 7.1, 8.8 / 7.3 ms |
| Laptop, pipelines for the first frame (surface + specialization) | | 27 + 16 | 27 + 16 | 20 + 12 |
| Mobile renderer (lean+vis on the laptop), pipelines | | 30 + 10 | 30 + 10 | 30 + 10 |
| Note 9, frames shown at ≥ 30 fps (SurfaceFlinger), 10 minutes | ≥ 95 % | | 99.08 % | 99.65 % |
| Note 9, frames over 100 ms after 5 s | none | | none (worst 91.9 ms) | none (worst 56.6 ms) |
| Note 9, peak PSS | ≤ 1.5 GB | | 1,029 MB | 1,052 MB |
| Note 9, GPU time median / p95 | | | 19.5 / 27.9 ms | 18.8 / 25.3 ms |
| Note 9, launch to first frame, first start (each run) | ≤ 15 s | | 14.95, 14.85, 14.76, 19.66 s | 15.75, 14.99, 19.76 s |
| Note 9, pipelines for the first frame | | | 30 + 10 | 30 + 10 |

The full tier's GPU time at the 95th percentile fell from 25 to 31 ms to under 9 ms, and the branch's frame p95 met
the rule in one run (11.0 ms). In the other (24.0 ms) its GPU p95 was the same 8.8 ms: the long frames there waited on
something other than this app's GPU work (the other agents' screenshot runs shared the GPU; a frame's render CPU time
was under 2 ms). A quiet run is still to be made before the laptop's 60 fps is called met.

The Note 9 meets its frame, memory and spike rules. The launch rule is not met reliably by either build: both sit at
the 15 s line and both had a start near 20 s (the phone at 29 to 30 °C, plugged in); this pass compiles the same 40
pipelines and its starts are within that spread of main's. The first start waits for those pipelines; what else takes
the rest of the 15 s is not yet broken down, and is the next lever (the launch rule has no margin left).

What each part of the sun's shadow and SSAO cost (150 s walks, loaded, GPU p95, before the merge): everything
16.6 ms; SSAO off 10.7; shadow off 11.5; two cascades 14.7; shadow to 40 m 16.6. SSAO was the lever; the shadow stays
as it was.

## Measured again, after 0060 (2026-10-20)

Of the two rules this record left open, the Note 9's launch is now met; the laptop's 60 fps is not, on a quiet machine
as well, with main and with 0060's change alike (numbers and method in 0060):

| | Rule | Now |
|---|---|---|
| Note 9, launch to the first walkable frame, first start (ten runs) | ≤ 15 s | 8.60–9.66 s (none near 20 s in 46 timed first starts) |
| Note 9, frames shown at ≥ 30 fps / over 100 ms after 5 s / peak PSS | ≥ 95 % / none / ≤ 1.5 GB | 99.64 % / none (worst 70.1 ms) / 658 MB |
| Laptop, `full` at 1600×900, 10 minutes (thought quiet; an editor was using the GPU, below): frame p95 / ≤ 17.5 ms | ≤ 16.7 ms / 95 % | 21.8 ms / 85.3 % (GPU p95 7.8 ms); main 21.6 ms in 300 s runs: another app's GPU work. With the GPU free: 9.6 ms / 100 % (below) |
| Laptop, first frame on a first start | ≤ 5 s | 3.36 s |

## The laptop's long frames: another app on the GPU (2026-10-20)

[V] measured here; [S] Godot 4.7.2 source.

| | Finding | Source |
|---|---|---|
| Where a frame's time went (`probe=1`: `frames.csv`, 600 s, full tier) | the scripts, physics and everything outside the draw: p95 3.6 ms, p99 4.4 ms; the render thread's CPU work p95 2.4 ms; GPU p95 7.6 ms. Frames are two kinds: 7.5 ms (median) and 20.6 ms, about 23 long ones a second, and every long one is long in the draw (18.2 ms against 5.1) | [V] `app/frame_probe.gd` |
| What the draw waits for | the main thread sits 13-15 ms in `DRM_IOCTL_SYNCOBJ_WAIT` (a GPU fence). Not physics (the share of long frames is the same with 0 or 1 physics steps), not vsync or the display (the same with `--disable-vsync`, at 60, 120 and 240 Hz), not this app: a Godot scene of 200 spheres shows the same, an 18.5 ms frame every ~45 ms | [V] strace; [V] |
| Whose GPU work | the user's code editor, left open and idle, kept the render engine busy 420-470 ms of every second, in batches of 12-25 ms about 22 times a second (DRM fdinfo); every long draw ended 1.1 ms (median, p90 2.1 ms) after one of its batches ended, the short ones 12 ms | [V] `tools/plant3d/bench/gpu_clients.py`, timestamps |
| Deeper frame queue | `frame_queue_size` 3: the same p95 (22.0 ms) | [V] |

So the laptop's 60 fps rule was missed for the GPU time another app took, not for this app's work: the app's own CPU
work per frame (everything but the wait in the draw, the render thread included) is 5.4 ms at the 95th percentile and its GPU work 7.6 ms. Main (d61378f)
and the change that found this (the frame probe, the bake's cache below, the walking directions' warm-up: 0060) back
to back, release builds, baked, a first start each, 600 s, the editor still open (280 ms of render engine a second
during both): main p95 21.8 ms, median 8.1 ms, 75.4 % of frames ≤ 17.5 ms, GPU p95 7.7 ms; the change p95 21.6 ms,
median 8.0 ms, 75.6 %, GPU p95 7.6 ms. The
editor then stopped using the GPU (`gpu_clients.py`: nothing over 1 ms/s), and the same two builds, back to back
again, met the rule with a margin: this change p95 **9.6 ms**, median 7.8 ms, p99 10.1 ms, 100 % of frames ≤ 17.5 ms,
GPU p95 7.7 ms (128 frames a second); main p95 **11.0 ms**, median 8.0 ms, 100 %, GPU p95 8.1 ms (a browser and the
desktop drew 15 and 11 ms of GPU a second during main's run). The laptop's 60 fps rule is met; measure it with
nothing else on the GPU.

**The bake on a fresh checkout** (`build.sh release`/`bake`): the editor crashed (signal 11) on opening the bake scene,
in 6 of 7 bakes from a fresh checkout's state. Without a script documentation cache (a new `.godot/`) the editor
regenerates the scripts' documentation on a thread of its own that loads every script of the project
([S] `editor/doc/editor_help.cpp`, `regenerate_script_doc_cache`), just as the plugin opens the scene; with an empty
cache it only reads that (3 of 3 bakes). `build.sh` writes one before the bake (`builder/bake/script_doc_cache.gd`);
three `build.sh release` runs, each in a fresh worktree, then baked and exported.

**When to revisit:** when Godot binds LightmapGI baking to scripts (bake headless, on CI); if a phone in the
measurement set has ASTC HDR; when the plant outgrows one lightmap texture (4096 px slices); if a trainee needs light
inside a dark corner the bake misses.

## Polish pass toward plant-v0.2.0 (2026-10-21)

What a trainee noticed in the first train, fixed in the same approaches (no new shader, vertex format or pipeline):

- **Hall ceilings** were black: the inside of the dark outer sheet, lit by nothing but what a dark floor bounced. Every
  building now has a light liner under its roof (the inner skin of composite cladding) and a metal-clad hall's walls
  are lined inside too; the roof steel (rafters every 6 m, purlins every 1.8 m) hangs under it. The lamps hang as high
  as before, evenly spaced, each on a short rod from a purlin midway between two rafters (hung below the rafters, one
  sat in the boiler house's steam pipe: review). A hall's upper floor seen from below is profiled decking on beams (it
  was the floor's dark epoxy), the beams and the lamps under it clear of the turbine's exhaust trunk.
- **The CW pump house** read as a dim box: buildings draw the louvres and windows their openings name (the content
  format had them, the build ignored them), metal cladding has a concrete plinth and flashings, a concrete wall a
  coping; the cladding is a lighter grey. Windows seen from inside are the daylight beyond (a little light of their
  own, which the bake spreads into the hall).
- **The transformer yard's fence** is a steel palisade (posts, rails, pointed pales a hand apart) one sees through; the
  galvanised sheet read as a blotchy wall on the phone. It still shimmers a little 40 m and more away.
- **Streaks** have broad 0.75 m columns besides the fine ones, longer on taller faces; cladding's are stronger. **The
  ruts** break and **the track** wanders by arithmetic noise, the same on every tier (the phone's took two texture
  samples it skipped). **A safety sign's board** is retroreflective white with a little light of its own (it read light
  grey in a wall's shade: 118 of 255 on screen there, now 192; 186 → 212 in the sun).

Measured (release builds, baked; before = main 75fd006, after = this change):

| | Rule | Before | After |
|---|---|---|---|
| Note 9, frames shown at ≥ 30 fps (SurfaceFlinger), 10 minutes, first start | ≥ 95 % | 99.24 % | 99.55 % |
| Note 9, frames over 100 ms after 5 s | none | none (worst 72.7 ms) | none (worst 55.2 ms) |
| Note 9, peak PSS (sampled) | ≤ 1.5 GB | 669 MB | 920 MB |
| Note 9, launch to the first walkable frame, three first starts | ≤ 15 s | 8.52, 8.74, 8.47 s | 10.21, 8.89, 8.58 s |
| Note 9, pipelines for the first frame (mesh/surface/draw/specialization) | | 0/13/0/7 | 0/13/0/7 |
| Laptop `full` 1600×900, 600 s: frame p95 / GPU p95 | ≤ 16.7 ms (GPU free) | 24.9 / 9.7 ms | 24.8 / 9.6 ms |
| Lightmap texels / APK | ≤ 150 MB | 6.3 M / 115 MB | 8.4 M / 118 MB |

The phone and laptop numbers were measured before the review fixes, which moved the baked lamps (place and spacing),
gave the fence's streaks their top and cut beams at the turbine: nothing drawn at run time changed (the lamps are
dropped once baked; the same meshes, materials and lightmap size).

The laptop's runs had the user's code editor on the GPU (400–470 ms of render engine a second, `gpu_clients.py`), so
its frame p95 says nothing about the 60 fps rule; the app's own GPU time is unchanged. The peak PSS grew by about a
quarter of a gigabyte, within the rule but not yet explained (the lightmap grew by 8 MB): to break down before the next
change adds memory.

## Photo pass (2026-10-21)

The user photographed halls and yards of a combined-cycle plant in service (private reference, not in the
repository). The user's choice (2026-10-21): the details such plants share, in neutral colours, not that plant's own
colour scheme. What the comparison showed and what changed, with the same one shader and vertex format (0060):

- **Floors by finish** (content: a building's `floor`, a deck's `finish`): the gas turbine hall and the steam
  turbine's operating floor glazed light tiles (0.8 m, the grout and each tile's tone drawn by the shader, a sheen of
  the floor's own colour at a grazing view, lit as the floor is), the ground floor under the deck and the pump houses bare concrete with
  hairline cracks, scuffs and tyre marks; dark bar gratings over trenches beside the gas turbine.
- **Halls:** wide spans (18 m and more) carried by trusses (chords, posts, diagonals) instead of solid rafters, in the
  frame's dark steel; columns at every bay (beside an opening, not in it) and girts in bands up the walls, broken at openings; round high-bay lamps;
  more high windows; an overhead travelling crane in safety yellow on its runway in both turbine halls (content
  `crane`: the rail height; only in a rectangular metal-clad hall, the build refusing one whose trolley would reach
  into the roof steel).
- **Outside:** the transformers' concrete firewalls (a new structure, `wall`); open yards (no building) gravelled;
  the ring road concrete in 5 m bays; its kerbs painted in black and yellow stripes; the cladding a light silver grey.
- **Pipes and valves:** the medium's name stencilled in black on both sides of each level run, between the colour bands (plant.json
  `media.name`; the safety signs' label settings, so no pipeline of its own; drawn within 30 m); jacketing brighter;
  valve bodies, bonnets and yokes black, electric actuators silver grey, bolts rusty.
- **The electrical room** over the control room: two rows of switchgear facing each other across an aisle.

Tried and left out: **a reflection probe** over each tiled floor (box-projected, captured once, the full tier only):
the floor mirrored the hall well, but the laptop's GPU p95 went from 10.0 to 23.7 ms in the release build's 600 s
walk (9.8 to 28.6 ms in a 120 s walk of the project with and without them), its video memory from 384 to
948 MB (its reflection atlas, by the size; not broken down), and the first capture held one frame for 2.96 s. **SSR** on the full tier showed nothing
on these floors.

Measured (release builds, baked; "main" = 75fd006 before the polish pass, "before" = the polish and behaviour passes
together (#226 and #227), "after" = this change on the merged main; Note 9 `lean+vis`, first start, plugged in,
10-minute walk; laptop `full` 1600×900, 600 s, with the user's code editor on the GPU, 300–530 ms of render engine a
second, `gpu_clients.py`):

| | Rule | Main | Before | After |
|---|---|---|---|---|
| Note 9, frames shown at ≥ 30 fps (SurfaceFlinger) | ≥ 95 % | 99.73 % | 97.72 % | 99.63 % (99.56 % before the review's last fixes) |
| Note 9, frames over 100 ms after 5 s | none | none (worst 57.2 ms) | none (worst 66.2 ms) | none (worst 67.7 ms; 87.4 ms before the review's last fixes); 1 (104 ms) in a cooled run of an earlier build of this change, below |
| Note 9, GPU time median / p95 | | 18.8 / 25.1 ms | 24.0 / 33.4 ms | 21.0 / 25.5 ms |
| Note 9, peak PSS (sampled) / of it the driver's GPU memory (GL mtrack) / Godot's video memory | ≤ 1.5 GB | 649 / 297 / 220 MB | 945 / 558 / 230 MB | 938 / 560 / 243 MB |
| Note 9, launch to the first walkable frame, three first starts (big cores' median clock) | ≤ 15 s | 9.80, 10.31, 10.34 s (1,586 / 1,469 / 1,469 MHz) | 9.13, 9.05, 10.78 s (1,794 / 1,794 / 1,469) | 9.09, 8.99, 9.36 s (1,794 / 1,794 / 1,794) |
| Note 9, pipelines for the first frame | | 0/13/0/7 | 0/13/0/7 | 0/13/0/7 |
| Laptop, frame p95 / GPU p95 / video memory | ≤ 16.7 ms (GPU free) | | 28.0 / 10.0 ms / 384 MB | 27.4 / 10.8 ms / 386 MB (the build before the review's last fixes) |
| Laptop, first frame / pipelines (surface + specialization) | ≤ 5 s | | 2.04 s / 15 + 9 | not measured on a quiet machine (4.83 s in a busy one: below) / 15 + 9 |
| Lightmap texels / APK | ≤ 150 MB | 6.3 M / 115 MB | 8.4 M / 118 MB | 10.5 M / 124 MB (the frame, trusses and crane: 2 M texels, about 8 MB on the phone) |

The phone's runs are first starts after the phone cooled (battery under 31 °C; main's run began at 29.7 °C, the
"before" run at 33.8 °C right after another). Warm, the same builds showed frames over 100 ms: this change's build
measured 94.90 % at 30 fps and 62 frames over 100 ms in one run begun at 32.6 °C, then, cooled, 99.01 % with one
frame of 104 ms, and two more cooled runs (the pipes' names hidden by `fx_off=stencils` and shown) 99.44 % and
99.66 %, worst 75.0 and 57.8 ms: the names cost nothing measurable, the warm runs were the phone's clock. On the final build the Note 9's rules hold
(cooled); an earlier build of this change, the same drawing but for the review's fixes, had one cooled run with a
104 ms frame, and the warm runs break the rule for every build measured warm here: the margin is narrower than before
the polish pass (main's 99.73 %), so measure it cool and more than once.

The laptop's numbers are from a busy machine (the user's editor on the GPU throughout, and late on a virtual machine
of another task, load average 5.6): its first frame, 3.94 s in an earlier run of this change and 4.83 s in the last,
was 6.3 to 12.3 s for the build before and 6.6 to 8.6 s for this one with an empty Godot data folder each, alternated:
no difference between them, and the 5 s rule to be measured again on a quiet machine.

**The polish pass's quarter gigabyte, broken down** (`frames.sh` now keeps the peak's `dumpsys meminfo`): it is the
GPU driver's own memory (GL mtrack, 297 → 558 MB), not what Godot allocates (its video memory 220 → 230 MB: textures,
meshes, the lightmap); the native heap grew 42 MB (242 → 284 MB). This change adds 2 MB of driver memory (558 → 560 MB). What the driver holds the more for is
not yet found: pipelines are the same 20, the textures and meshes Godot counts barely grew. The next lever is a
build with the polish pass's pieces taken out one at a time (louvres, liners, roof steel, palisade) on the Note 9.

The laptop's 60 fps rule could not be measured with the GPU free (the user's editor drew on it through every run);
the app's own GPU time is about the same (10.8 ms in the final build's run, 9.6 ms in an earlier build's,
against 10.0 ms before, at the 95th percentile).

## Occluders and far views (#249, 2026-10-24)

What is drawn changed for the frame rules, not the look: every building's walls and roof are an occluder (occlusion
culling on); the first train's areas, the WTP and its intake have a merged far view beyond 200 m (simplified within
0.2 m, detail pieces, doors and what stands wholly inside buildings left out); what stands wholly inside a building is drawn only within 30 m plus the building's diagonal.
The far meshes are not in the bake: lit by the sky and the sun without the bake's shadows. Laptop views from 200 to
500 m on the final build (the plant gate's road east, the WTP's west, the train and the turbine hall's roller door from
the WTP), with the far views and without them (`fx_off=farview`): no visible difference. The Note 9's walks on the merged code are in 0066 ("Frame spikes and the far
views").

## Photo pass 3 (2026-10-25)

The user's third batch of reference photos (the admin zone, its lobby, the camp's road, the plant's roads, a row of
pressure vessels and a tank farm; private, not in the repository) against the site, the camp and the WTP as C1 and W1
built them. What changed is in SITE.md ("As built (photo pass 3)") and WATER-TREATMENT.md (§8a, photo pass 3): kerbs
yellow and white, block-paved walkways and a footpath along the ring road, hydrants and bollards, shade sails, skips,
a telecom mast, air conditioners under the windows, the camp's ambulance, the admin lobby, the WTP's gravel yard, its
tank rails and mixed beds. Same one shader and vertex format (0060): the block paving is the tiled floor's code with
three new uniforms (bond, tone, gloss) whose defaults leave every other tiled floor exactly as it was; every new part
draws with materials already in use; the air conditioners and the hydrants each draw in one material (136 units and
25 hydrants: a material each would be a draw call per cell), the hydrants and bollards as `detail` pieces with their
own range. Left out: the photos' auxiliary cooler (the train's closed cooling water is cooled by the circulating water)
and that plant's colours.

Laptop views (`full`, 1280×720, unbaked, the same 22 views on main and on this change): draw calls up by 0 to 67 a
view (the camp's block 1 front 406 → 473, its air conditioners; the admin block 429–507 → 482–560; the ring road
839 → 857; the WTP 1,101–1,317 → 1,110–1,336), triangles by 1–9 %. Unbaked release APKs: 114.59 MB (main) →
114.90 MB; main's baked APK was 139.4 MB (0066), so this change's stays about 140 MB (budget 150).

Note 9 (`lean+vis`, plugged in, a first start each, `camp` walk 300 s with `probe=1`, the two builds one after the
other at 34–36 °C; unbaked release exports of this change and of main at its base, signed with the test key; the
camp walk passes the plant gate, the road west, the camp's blocks with their air conditioners, the ambulance and the
hydrants, block 1 and the mess hall):

| | Main (1d1eb58) | This change |
|---|---|---|
| Frames shown at ≥ 30 fps (SurfaceFlinger) | 99.73 % (99.59 % in an earlier run) | 99.82 % |
| Frames over 100 ms after the first 5 s (app / SurfaceFlinger) | 0 / 0 | 0 / 0 |
| Worst frame (app) | 65.4 ms (71.4) | 64.0 ms |
| GPU median / p95 | 19.1 / 23.8 ms (19.3 / 25.9) | 18.9 / 23.8 ms |
| Peak PSS | 1,063 MB (1,061) | 1,059 MB |
| Pipelines compiled after the first 5 s | 0 | 0 |

No difference beyond run-to-run noise. Not measured on the phone: the `frames` and `wtp` walks (the phone was shared
with two other tasks; the WTP's change is its yard's material, rails and two vessels' platforms), the baked build and
its first start, the Honor.

## The frame rule counts the frames the app causes (the user, 2026-10-25)

The Note 9's last frames over 100 ms came while the phone's kernel reclaimed memory, not from what the app drew (0066,
"The last frame spikes"). So the rule "no frame over 100 ms after the first 5 s" now counts only the frames the app
causes. A frame inside a traced burst of the kernel's memory reclaim is excluded, with its evidence kept. Every other
rule here is unchanged (≥ 95 % at ≥ 30 fps, peak PSS, first start, the 1.2× rule).

- **Inside reclaim** means this: a sample of `phone/frames.sh SAMPLE=1` (every 0.2–0.3 s) that overlaps the frame
  shows kswapd or direct reclaim scanning at least one page, or a direct-reclaim stall, since the sample before
  (`/proc/vmstat`; samples at most 1 s apart).
- **The threshold is any reclaim.** With no scanning, 0.027 % of frames had a GPU time over 45 ms. At 1–200 pages a
  second it was 1.6 %, and 2–15 % above that (0066 gives the walks).
- **The evidence** is the walk's `rule.txt` (each excluded frame with the sample lines that show its reclaim), beside
  its `samp.txt` and `logcat.txt`. `tools/plant3d/bench/reclaim_frames.py --rule` writes it, and `frames.sh` runs it
  after every `SAMPLE=1` walk.
- **Not judged:** a walk without `SAMPLE=1` cannot exclude any frame. A walk that would pass only by excluding frames
  is not judged, and is walked again, when it is a `STRESS=1` walk, when it had reclaim in more than 1 % of its
  sample pairs, or when its log has more `SPIKE` lines than its `over100`. A frame the log lost counts as the app's.
