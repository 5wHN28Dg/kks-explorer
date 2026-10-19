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
  phone skips the wear's sample and the ruts' two (its ground has the patches but no broken ruts or wandering track);
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

**When to revisit:** when Godot binds LightmapGI baking to scripts (bake headless, on CI); if a phone in the
measurement set has ASTC HDR; when the plant outgrows one lightmap texture (4096 px slices); if a trainee needs light
inside a dark corner the bake misses.
