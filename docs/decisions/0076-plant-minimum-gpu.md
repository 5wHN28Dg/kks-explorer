# 0076 Walkdown Plant: a stated minimum GPU (Vulkan or Direct3D 12), no lower graphics tier

Date 2026-11-19 · Scope: `apps/plant3d` on Windows and Linux · Status: decided (the user, 2026-11-19: "State a minimum
GPU", given in the coordinating agent session that handed this work out; quoted on #432); the speed class added by
the user's verdict on #455 (2026-11-19: "Add a speed class")

**Question:** on the user's Windows 10 test laptop (Intel HD Graphics 4400, 2013) Godot finds neither Direct3D 12 nor
Vulkan, falls back to its Compatibility renderer, and Plant walks at about 12 frames a second (#432). Is such a GPU a
target, with a lower tier of its own, or is it below a stated minimum?

## Findings

| | Fact | Source |
|---|---|---|
| The laptop | Intel HD Graphics 4400, driver 10.18.15.4248, Windows 10: "Cannot find a compatible Vulkan installable client driver", "Your video card drivers seem not to support Direct3D 12 or Vulkan, switching to OpenGL 3", then ANGLE on Direct3D 11 (Compatibility renderer, tier `lean+vis`). The 300 s frame walk: median 85.5 ms (first start) and 79.8 ms (later start), p95 121–131 ms, **0 % of frames at 30 fps or better**; at 1280 × 720 without shadow and fog still 54.7 ms median. The draw takes ~70 of the 80 ms (773 draw calls). First frame 56.6 s on the very first start. About 1 GB private memory of 4 GB. One of four starts ended by itself | [V] #432, apps/windows/README.md "Results on a real laptop" |
| Godot 4.7's minimum for Forward+ and Mobile (desktop) | "Integrated graphics with full Vulkan 1.0 support", "Direct3D 12 (12_0 feature level) support (Windows)"; examples "Intel HD Graphics 510 (Skylake), AMD Radeon R5 Graphics (Kaveri)" | [D] https://docs.godotengine.org/en/stable/about/system_requirements.html |
| Godot 4.7's minimum for Compatibility (desktop) | OpenGL 3.3, or Direct3D 11 on Windows; examples "Intel HD Graphics 2500 (Ivy Bridge)". The HD 4400 meets this, which is why Godot falls back instead of failing | [D] same page |
| Godot 4.7 on Android | Forward+/Mobile need full Vulkan 1.0 (Android 9.0+); Compatibility OpenGL ES 3.0 | [D] same page |
| NVIDIA | Vulkan 1.0 from the 2016 drivers on Kepler and Maxwell (GeForce 600/700 Kepler, 900), Vulkan 1.2 back to Kepler from driver 441.99. Some low-end GeForce 600 models (GT 610–630) are Fermi, not Kepler | [D] https://en.wikipedia.org/wiki/GeForce_600_series · https://wccftech.com/nvidia-geforce-vulkan-drivers-launch/ |
| AMD | GCN (from January 2012, "used in several Radeon HD 7000 series graphics cards") supports Vulkan (Godot's page names the HD 7750, GCN 1.0, among its Compatibility examples, not its Forward+ ones); GCN 1 and 2 have had no new Windows driver since 22.6.1 (mid-2022) | [D] https://en.wikipedia.org/wiki/Graphics_Core_Next |
| The speed class on Linux | Measured for #445 (2026-11-19) on the owner's Iris Xe laptop (Linux, Vulkan): a release-style export (lightmap baked, shaders compiled at load), `full` tier, a 1600 × 900 window at 60 Hz, the 10-minute frames walk: median 16.7 ms, p95 18.3 ms, p99 21.1 ms, longest 44.2 ms, none over 100 ms, 100.0 % of frames at 30 fps or better (85.5 % at 60), GPU time p95 10.9 ms (one other app used the GPU, about 1 %) | [V] the walk's result.txt (kept with the PR's evidence) |
| What a lower tier would take | the draw (773 calls) is the cost, not the resolution or effects: merged meshes, a shorter view distance and no lightmap for Compatibility, a second set of tuned content and measurements to keep, for GPUs that the engine's own documentation puts below its 3D renderers' minimum | [V] #432 (720p without shadow and fog still 55 ms) |

## Choice

- **Desktop Walkdown Plant needs a GPU whose driver supports Vulkan 1.0 or Direct3D 12 (feature level 12_0)**, the
  minimum of Godot's Forward+ renderer. Examples, from the sources above: Intel HD Graphics 510 or newer (6th
  generation Core, Skylake, 2015); AMD GCN (Radeon HD 7700 or newer; Radeon R5/R7 APUs from Kaveri; the low-end HD 7000 models are older TeraScale chips) with a current
  driver; NVIDIA Kepler or newer (GeForce GTX 600 and 700 series, except the Fermi-based low-end models). Below that
  Plant still starts, on the Compatibility renderer, but is not supported: no tier is tuned for it. The examples
  are for Windows drivers: on Linux, Mesa's Vulkan driver also covers Intel Broadwell and, incompletely, Haswell;
  AMD's later TeraScale rebrands (e.g. Radeon R5 230) have no Vulkan.
- **A speed class for smooth play** (the user, 2026-11-19, #455: "Add a speed class"): the feature minimum says which
  computers get Godot's normal renderer, not which ones reach the frame rules. Smooth play (the project's desktop
  frame rules at the `full` tier) needs roughly **Intel Iris Xe or a GPU at least as fast**. Iris Xe is measured for #445 (2026-11-19) on the owner's Iris Xe laptop (Linux, Vulkan): a release-style export (lightmap baked, shaders compiled at load), `full` tier, a 1600 × 900 window at 60 Hz, the 10-minute frames walk: median 16.7 ms, p95 18.3 ms, p99 21.1 ms, longest 44.2 ms, none over 100 ms, 100.0 % of frames at 30 fps or better (85.5 % at 60), GPU time p95 10.9 ms (one other app used the GPU, about 1 %). At the laptop's native 2880 × 1800 the `full` tier misses the rules (decision 0041's bench: p95 34.7 ms), so smooth means a window of about 1600 × 900 on such graphics.
  A GPU at least as fast: for example a GeForce GTX 1050 or Radeon RX 460 (Godot's recommended GPUs, its system
  requirements page above; the RX 560 is the same chip) is **an estimate here** (not measured). A dedicated GPU is not enough by itself: the user's
  laptop's Radeon R7 M265 (GCN 1.0, about 0.6 TFLOPS against about 2 for Iris Xe) is well below the class.
  HD Graphics 510's 12 execution units are fewer than the HD 4400's 20) run, but slowly: the tier probe gives them the lighter `lean+vis` tier at first start (app/quality.gd),
  whose speed there is unmeasured, an estimate from the HD 4400's about 12 fps on Compatibility (#432, the evidence for
  "below"). In the UX profile the speed class is therefore the oldest device for the frame rules, and the band between
  the feature minimum and it "runs, not supported for frame rate": a narrowing, approved by the owner's verdict on #455.
- **Android stays as it is:** Android 10 or newer with Vulkan (the Mobile renderer; the Samsung Note 9, Mali-G72, is
  the minimum and its frame rule is decision 0041's).
- **No lower graphics tier** (option B of #432): not built.
- **The app says so:** when a desktop start finds itself on the Compatibility renderer, a message before the plant
  loads says what the computer lacks, that it will run slowly (about 12 frames a second on the laptop above), and
  offers Continue anyway or Quit, with "Don't show this again" kept in the settings (`app/min_gpu.gd`). Never on a
  phone, never for a measurement started from the command line. Under the UI and UX policy (adopted the same day) it
  is a tier-2 change: merged switched off (`walkdown/min_gpu_message`), on after the owner's check.
- The UX profile (docs/ux-profile/plant.md) states the minimum; the HD 4400 laptop leaves it (a narrowing by this
  decision).
- **Not caught:** Linux with only a software Vulkan (lavapipe), or Mesa's incomplete Vulkan on Haswell (hasvk):
  Forward+, no message, unmeasured. An Android device without Vulkan 1.0 would fall back the same way, silently: Android's minimum is
  unchanged (the export asks for Vulkan) and the message is for desktops only.
- No new dependency.

## When to revisit

- If the plant's users turn out to have such computers (a site's desktops, the training room's PCs): then measure what
  a Compatibility tier would need (option B of #432).
- The speed class: when a Windows device at it can be measured (none is reachable), when the plant's content grows
  by a milestone (re-measure the `full` tier on the Iris Xe laptop), or when the tier is chosen again on a window's
  resize (#456).
- When Godot changes its renderers' minimum (its system requirements page), or drops the Compatibility fallback.
