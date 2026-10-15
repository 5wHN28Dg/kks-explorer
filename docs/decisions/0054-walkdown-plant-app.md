# 0054 Walkdown Plant: the app's structure, content pipeline, packaging and tests

Date 2026-10-15 · Scope: the 3D plant (https://github.com/5wHN28Dg/kks-explorer/wiki/3D-plant, R1–R10), the
user's decisions of 2026-10-15 (Godot 4, its own app "Walkdown Plant", first goal one train) · Engine measurements:
0041 · Content format: docs/PLANT3D.md · First train: docs/plant3d/FIRST-TRAIN.md · Status: **proposed**, written
before any app code; the signing key and the update path are questions for the user (end of this record).

**Question:** how is Walkdown Plant built: where does it live, how does it get KKS decoding and links to and from
Walkdown, how does the plant description become a scene, where do its assets and sounds come from, how big is it and
how is it shipped, signed, built on CI and tested, on Android, Linux and Windows?

## Findings per target

Godot facts are from the 4.7 documentation (docs.godotengine.org/en/stable, which is 4.7 today) and the engine source
at the `4.7-stable` tag; [D] = vendor documentation, [S] = source read, [V] = verified here, [M] = measured in 0041.

| | Android (Note 9 minimum, Honor 600) | Linux (GNOME) | Windows 10/11 |
|---|---|---|---|
| Renderer | Mobile (Vulkan); the export sets minimum SDK 29 when Vulkan is used, the Note 9's Android 10 is API 29; Mali-G72 is named in the Mobile renderer's requirements [D][S] | Forward+, Vulkan [D] | Forward+, Direct3D 12 (default for new projects since 4.6) or Vulkan, each falling back to the other; exported apps need Windows 10 [D] |
| Shaders at load | ubershaders + pipeline precompilation (4.4); the **shader baker** (4.5) bakes Vulkan shaders at export from a Linux editor, but **not with `--headless`** (it needs a GPU) [D] | same, Vulkan | baked for D3D12 only from a Windows editor; a Linux editor bakes Vulkan [D] |
| Texture compression | ETC2 (guaranteed with OpenGL ES 3.0) or ASTC 4×4 ("high quality"); the project imports them only with `import_etc2_astc` [D]; ASTC on > 80 %, ETC2 on > 95 % of Play devices [D] | S3TC/BC1–3, BPTC/BC7 [D] | same as Linux [D] |
| Size | sideloaded APK: no store limit (Google Play would allow 500 MB base, 100 MB for a plain APK; we don't publish there) [D]; the bench's APK 81 MB with 2K textures [M] | Flatpak: `org.godotengine.godot.BaseApp` branch 4.7, the game as `/app/bin/godot-runner.pck` [D] | exe + `.pck` (or embedded up to ~3.9 GB) [D]; MSIX made by our own `packaging/windows` tools (0043) |
| On-demand content | `ProjectSettings.load_resource_pack()` loads extra `.pck` files; packs exported with `--export-pack`, patches (4.4) [D] | same | same |
| Deep links in | an intent filter for `walkdown-plant://` in a Gradle-built export, and a small Android plugin (v2, Godot 4.2+) that hands the Intent's URI to the app: **Godot has no API for the launching Intent** and its plugin hooks have no `onNewIntent` [D][S] | the `.desktop` file's `MimeType=x-scheme-handler/walkdown-plant`, `Exec=… %u`: the URI arrives as a command-line argument (`OS.get_cmdline_args()`) [D] | the MSIX `uap:Protocol` extension (Windows 10 1511+) [D]; the URI arrives on the command line |
| Opening Walkdown's links out | `OS.shell_open("walkdown://…")` (an Intent VIEW) [D] | `OS.shell_open` → the OpenURI portal inside Flatpak [D] | `OS.shell_open` → ShellExecute [D] |
| Input | touch (InputEventScreenTouch/Drag); a built-in `VirtualJoystick` control since 4.7; gamepads through Android's own input [D] | keyboard, mouse, gamepads through SDL3 (4.5) [D] | same as Linux [D] |
| Audio | AudioStreamPlayer3D (attenuation, Doppler), Ogg Vorbis/WAV/MP3; AudioStreamGenerator is for C# or native code, script only at low mix rates [D] | same | same |
| Native code binding | GDExtension libraries per ABI, or inside a v2 plugin AAR [D] | GDExtension `.so` [D] | GDExtension `.dll` [D]; extensions built for 4.x are meant to load in later 4.y, not guaranteed [D] |
| Signing | the export runs `apksigner` with `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`; store and key password must be equal; without apksigner the APK stays unsigned with a warning [D][S] | Flatpak bundle signed like Walkdown's | osslsigncode on the host (0043) |
| CI export | `godot --headless --export-release "<preset>" <path>` with the export templates (4.7.2: 1.28 GB `.tpz`, SHA-512 in `SHA512-SUMS.txt`) [D] | same | same |
| Licence notices | `Engine.get_license_info()`, `get_copyright_info()`; ship Godot's MIT text and third-party notices [D] | same | same |
| JSON | `JSON.parse_string()`: all numbers become floats, duplicate keys not refused [D] | same | same |

Sources: https://docs.godotengine.org/en/stable/about/system_requirements.html ·
…/tutorials/export/exporting_for_android.html · …/tutorials/platform/android/android_plugin.html ·
…/tutorials/editor/command_line_tutorial.html · …/tutorials/performance/pipeline_compilations.html ·
…/tutorials/assets_pipeline/importing_images.html · …/tutorials/export/exporting_pcks.html ·
…/tutorials/3d/visibility_ranges.html · …/tutorials/assets_pipeline/importing_audio_samples.html ·
…/tutorials/export/exporting_for_windows.html · …/tutorials/platform/linux/wayland_x11.html ·
…/about/complying_with_licenses.html · …/about/release_policy.html · https://godotengine.org/releases/4.7/ ·
https://github.com/godotengine/godot/tree/4.7-stable (platform/android/export/export_plugin.cpp, GodotPlugin.java,
GodotActivity.kt) · https://github.com/flathub/org.godotengine.godot.BaseApp ·
https://developer.android.com/guide/playcore/asset-delivery/texture-compression ·
https://support.google.com/googleplay/android-developer/answer/9859372 ·
https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-uap-protocol ·
https://specifications.freedesktop.org/desktop-entry-spec/latest/ ·
https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.OpenURI.html

**One finding about this repository:** Walkdown's Android updater reads GitHub's `releases/latest` and refuses a
release without Walkdown's signed manifest (`sync/Updates.kt`). A Walkdown Plant release published as "latest" in the
same repository would stop every phone's Walkdown updates. [V] the code.

## Choices

1. **Where it lives.** A Godot project in `apps/plant3d/` (project.godot, the app's scripts, the parts kit in
   `apps/plant3d/kit/`, the build script); content in `data/plant3d/` beside `data/courses/` (format:
   docs/PLANT3D.md); the reference validator and model evaluator in `ref/plant3d.py` with vectors
   `ref/vectors/plant3d-v1.json`, like the courses (0025). The bench (`tools/plant3d/bench`) stays a measurement
   tool. Godot pinned to one 4.7.x release; minor upgrades are a decision with a fresh 0041 measurement.
2. **KKS decoding without the core.** The plant's own decoder tables live in its `plant.json`, written from the public
   KKS key (R1; Walkdown's `data/kks.json` comes from a real plant's drawings and is not used). Decoding is a split
   by the fixed grammar and three table lookups: GDScript does it. The tables hold only the codes the plant uses, with
   meanings in our own words: VGB sells the key and licenses its use in electronic systems, the key tables included
   (https://www.vgbe.energy/wp-content/uploads/2023/04/KKS-Licensing-2023-01-01-EXT.pdf). **No GDExtension binding to the Nim core** now:
   the plant app has no sync, no log, no keys and no network, so the core would add four native builds per release
   for a lookup. Revisit when the plant app needs something only the core has (progress through the plant's log,
   §"revisit").
3. **Links by URI scheme.** `walkdown-plant://kks/<code>`, `…/procedure/<id>[/<step>]` into the plant app, and
   `walkdown://course/<course>[/<page>]` back into Walkdown (PLANT3D.md §6). Walkdown registers its scheme on its
   four platforms (the web client: an https URL instead); Walkdown's tag panel gets "Show in Walkdown Plant", which
   opens the plant's equipment of the same kind when the code is not in the invented plant. A link whose app is not installed gives a
   message, not a silent failure. Courses link in with a
   new `plant` target, which needs course format version 2 (COURSES.md is frozen at 1). Both are follow-up work in
   Walkdown, each with its own tests.
4. **Description → pre-built scenes.** The content passes `ref/plant3d.py` (strict JSON), then a headless Godot
   script (`godot --headless --script apps/plant3d/build/build.gd`) makes one scene per area from the kit (instanced
   per part, LOD, material and 12 m cell: 0041) and the compiled model, saved as binary resources that the export
   packs. The app does no geometry generation at startup (0041: building by script took 20–28 s of the Note 9's
   first frame; the pre-built bench plant is 327 KB). Shaders: the shader baker at export (Vulkan from Linux, D3D12
   only from a Windows editor: the Windows build ships Vulkan-baked and D3D12 compiled at load, measured before
   choosing its default driver), plus ubershaders.
5. **Assets.** Geometry is all ours, from the kit (R5). Materials are CC0 PBR sets (ambientCG, as the bench),
   fetched by a pinned script with SHA-256 checksums, never committed; the build makes three sizes (2048, 1024,
   512 px) and the tier picks one (PLANT3D.md §10). Compression: ETC2 by default on Android (ASTC 4×4 measured on the
   Note 9 against it before choosing), BC/BPTC on the desktops. The Android export must carry only the mobile
   formats: to verify on the first export (the docs don't say; the bench's 81 MB carried both).
6. **Size and on-demand content.** The first train ships as **one APK / one package**, budget ≤ 150 MB (measured and
   written down per tier, the wiki's growth rule applies). Areas are already separate scenes in packs (`pack` in
   PLANT3D.md §3), so when the whole plant outgrows the budget, later areas become `.pck` files loaded with
   `load_resource_pack()`, downloaded like Walkdown's plant data and checked by SHA-256, without a format change.
   Google Play's limits don't bind (GitHub releases, 0022).
7. **Audio.** Recorded clips only under **CC0-1.0** (Freesound with the CC0 filter, Kenney, OpenGameArt CC0, our own
   recordings released CC0), trimmed and looped by a script; machinery tones and broadband noise synthesised by our
   tools at build time into loops (PLANT3D.md §11). No CC-BY-NC/ND, no "royalty-free" packs whose licence forbids
   redistributing the files (they would sit in a public repository). Clips are committed (small, Ogg Vorbis, budget
   10 MB; Freesound downloads need a login, so a fetch script can't pin them); each has its licence, source URL,
   uploader and download date in its sound entry (a "CC0" upload's provenance is the uploader's word), and our own
   recordings are preferred for machinery, and `tools/about` lists them in the app's about data like `data/about.json`, with Godot's own
   notices from `Engine.get_license_info()`.
8. **Identity and packaging.** Android `io.github.walkdown.plant`, a Gradle-built export (needed for the deep-link
   plugin), arm64-v8a only (0046), `permissions/internet=false`: no network at all in format 1. Flatpak
   `io.github._5wHN28Dg.walkdown.plant` (or a sibling ID: question below) on `org.godotengine.godot.BaseApp//4.7`. MSIX identity `WalkdownPlant`, exe
   `WalkdownPlant.exe`, alias `walkdown-plant.exe`, publisher `CN=Walkdown` (the certificate IT already trusts,
   0043). Releases: tags `plant-vX.Y.Z` in this repository, published **not as latest**
   (`gh release create --latest=false`), so Walkdown's updater keeps finding Walkdown's release. Not left to memory: with
   the first plant release, `tools/release.py` passes `--latest` explicitly for Walkdown and the plant's release tool
   `--latest=false`, and both refuse when the current latest release is not a Walkdown `v*` tag; `policy.yml`'s tag
   filter (`v*`) is extended to `plant-v*` so plant releases get the same checks.
9. **CI** (when the code lands; `tests.yml` jobs): `plant3d` on Linux x86-64: `ref/plant3d.py` on the content and
   the vectors; the Godot build of every area; the model vectors through the app's evaluator (headless); the walking
   test (below); an Android and a Linux export with `--headless` (not baked, not signed) to catch export errors.
   Godot and its export templates downloaded by URL and SHA-512, cached. Release builds (baked shaders, signed) are
   made on the laptop, where the keys are, from a clean checkout.
10. **Tests.**
    - **Description:** `ref/plant3d.py` valid/reject vectors; the build's own refusals (unsupported spans, stairs
      that don't land, bends that don't fit).
    - **Behaviour model:** step vectors (operations, 0.1 s steps, fast-forward; values, alarms, trips, machine states
      compared to 1e-6) passed by both the Python reference and the GDScript evaluator; each first-train procedure
      run end to end in the model alone (no rendering) must reach its last step with no trip.
    - **Walking:** a headless run (physics works with the dummy renderer, [S]) walks a character along every tour's
      path and every stair and ladder; it fails if the walker is stuck for 5 s or falls off a walkable surface.
    - **Frames:** the scripted walking path of the measurement rules writes a frame log on the devices (as the
      bench); measured by hand on the Note 9, the Honor 600 and the laptop per release, against the wiki's rules
      and the 1.2× regression rule. Not on CI (no GPU).
    - **Model cost:** the time of one 0.1 s model step with the whole first train's model, on the Note 9 (fast-forward
      at 60× runs 600 steps a second); the fast-forward cap is set from it.
    - Test runner: a small SceneTree script of our own that runs test functions and exits non-zero (no GUT or
      gdUnit4 dependency for now).

## Questions for the user

- **Flatpak ID.** The ID asked for, `io.github._5wHN28Dg.walkdown.plant`, lies under Walkdown's own ID: Flatpak lets
  an app own D-Bus names and export files that start with its ID, so Walkdown (`io.github._5wHN28Dg.walkdown`) could
  claim names that belong to the plant app. A sibling ID (`io.github._5wHN28Dg.WalkdownPlant`) avoids it.
  Recommended: the sibling ID; the Android and MSIX IDs are not affected (Android package names don't nest that way,
  MSIX identities are separate names).

- **Android signing key.** (a) the existing `kks-release.jks` (one key to keep safe; the two apps could later share
  signature-level permissions), or (b) a **new key** for Walkdown Plant. Recommended: **(b)**. The Godot export reads
  the key's password from environment variables and needs store and key passwords equal; Walkdown's key holds a
  real plant's account, and a separate key means a mistake in the new, game-engine build path can never sign an
  update of Walkdown. The two apps need nothing from sharing a key (they talk by links only). Losing either key has
  the same cost (reinstall by hand), so it is kept and backed up as the other (wiki: Releasing). Windows keeps
  `CN=Walkdown` either way, so IT trusts one certificate.
- **Updates.** (a) by hand from the GitHub release (the plant app has no network permission); (b) later, Walkdown's
  updater offers Walkdown Plant too (listed in Walkdown's signed `release.json`). Recommended: (a) for the first
  train, (b) when trainees use it on their phones.

**When to revisit:** if the Note 9 misses the frame rule with this content (0041; the question goes back to the
user); when the plant app needs the core (progress kept in the plant's log, signed content): then a GDExtension
binding to `libkks` against the network-free decision above; when the package passes 150 MB; when Godot's security
response (0041) changes or the app is to load content we don't make; when Godot's shader baker works headless.
