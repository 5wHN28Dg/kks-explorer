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
| The sky's light in the bake | LightmapGI reads the sky through `RenderingServer.sky_bake_panorama`, which returns black for a sky no viewport has drawn (its radiance never processed): a sky handed to the LightmapGI alone baked almost no sky light, the shade on open ground was 0.035 of the sunlit ground on screen (linear output), against 0.23 once the sky stands in a WorldEnvironment the editor draws and the bake takes the scene's environment | [V] `builder/bake/bake_plugin.gd` (its guard reads 0.000 the first way, 0.991 the second); [S] `lightmap_gi.cpp` |
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
  phone skips the streaks' and wear's samples.
- **The site:** concrete yards in the areas' bounds, gravel between, a ring road with kerbs and a drain, a boundary
  wall, the country to the far plane with low hills.
- **Per tier:** laptops add SSAO (low, half size, faded by 120 m: contact shade on valves and fittings the lightmap is
  too coarse for). SSIL, volumetric fog, glow and SDFGI are left out: measured above, none shows a trainee anything
  the bake doesn't (R9a).
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

**When to revisit:** when Godot binds LightmapGI baking to scripts (bake headless, on CI); if a phone in the
measurement set has ASTC HDR; when the plant outgrows one lightmap texture (4096 px slices); if a trainee needs light
inside a dark corner the bake misses.
