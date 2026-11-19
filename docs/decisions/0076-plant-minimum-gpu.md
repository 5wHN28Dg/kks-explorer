# 0076 Walkdown Plant: a stated minimum GPU (Vulkan or Direct3D 12), no lower graphics tier

Date 2026-11-19 · Scope: `apps/plant3d` on Windows and Linux · Status: decided (the user, 2026-11-19: "State a minimum
GPU")

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
| AMD | GCN (from January 2012, "used in several Radeon HD 7000 series graphics cards") supports Vulkan; Godot's own GCN 1.0 example is the HD 7750; GCN 1 and 2 have had no new Windows driver since 22.6.1 (mid-2022) | [D] https://en.wikipedia.org/wiki/Graphics_Core_Next |
| What a lower tier would take | the draw (773 calls) is the cost, not the resolution or effects: merged meshes, a shorter view distance and no lightmap for Compatibility, a second set of tuned content and measurements to keep, for GPUs that the engine's own documentation puts below its 3D renderers' minimum | [V] #432 (720p without shadow and fog still 55 ms) |

## Choice

- **Desktop Walkdown Plant needs a GPU whose driver supports Vulkan 1.0 or Direct3D 12 (feature level 12_0)**, the
  minimum of Godot's Forward+ renderer. Examples, from the sources above: Intel HD Graphics 510 or newer (6th
  generation Core, Skylake, 2015); AMD GCN (Radeon HD 7700 or newer, as Godot's own example HD 7750; Radeon R5/R7 APUs from Kaveri; the low-end HD 7000 models are older TeraScale chips) with a current
  driver; NVIDIA Kepler or newer (GeForce GTX 600 and 700 series, except the Fermi-based low-end models). Below that
  Plant still starts, on the Compatibility renderer, but is not supported: no tier is tuned for it.
- **Android stays as it is:** Android 10 or newer with Vulkan (the Mobile renderer; the Samsung Note 9, Mali-G72, is
  the minimum and its frame rule is decision 0041's).
- **No lower graphics tier** (option B of #432): not built.
- **The app says so:** when a desktop start finds itself on the Compatibility renderer, a message before the plant
  loads says what the computer lacks, that it will run slowly (about 12 frames a second on the laptop above), and
  offers Continue anyway or Quit, with "Don't show this again" kept in the settings (`app/min_gpu.gd`). Never on a
  phone, never for a measurement started from the command line.
- No new dependency.

## When to revisit

- If the plant's users turn out to have such computers (a site's desktops, the training room's PCs): then measure what
  a Compatibility tier would need (option B of #432).
- When Godot changes its renderers' minimum (its system requirements page), or drops the Compatibility fallback.
