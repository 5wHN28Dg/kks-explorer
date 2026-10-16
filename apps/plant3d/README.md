# Walkdown Plant

The walkable 3D plant (decision `docs/decisions/0054-walkdown-plant-app.md`; engine: `0041`; content format:
`docs/PLANT3D.md`). A Godot 4.7.2 project, pinned by `tools/plant3d/bench/fetch_godot.sh` (SHA-512).

Equipment and pipes are made by the parts kit (`kit/`, its README: frames, node names, moving parts, budgets,
materials). Platforms, floors, stairs, ladders, doors, buildings, pits, slabs, fences and the pipe rack are solid
geometry at their described positions, made by the builder.

## Layout

| Folder | What |
|---|---|
| `kit/` | the parts kit: every equipment part of `data/plant3d/kit.json` made from its parameters, the materials and their CC0 textures (fetched by `kit/fetch_textures.sh`) |
| `builder/` | the content build: `data/plant3d` to `built/` (a scene per area, the ground, the materials, `plant.json`). It runs at build time, never at app start. (Not `build/`: the repository ignores every `build/` folder.) |
| `app/` | the app: start and tiers (`main.gd`, `quality.gd`), loading (`plant.gd`), the walker (`player.gd`), doors, the overview map, the touch controls and settings (`hud.gd`), scripted routes (`autopilot.gd`, `routes.gd`) |
| `sim/` | the behaviour engine (the model's evaluator). It has its own owner; the project hosts it (`walkdown_plant/sim/path` in `project.godot`) |
| `tests/` | the app's tests: `run_tests.gd` runs every `test_*.gd` |
| `phone/frames.sh` | one frame-time run on a phone |
| `flatpak/` | the Flatpak (`io.github._5wHN28Dg.WalkdownPlant`, on `org.godotengine.godot.BaseApp//4.7`) |

## Build

```
apps/plant3d/build.sh                       # content check (ref/plant3d.py), content build, tests
apps/plant3d/build.sh export                # and the exports, headless, unbaked, unsigned, into export/check/ (CI)
tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release   # release exports, shaders baked
apps/plant3d/flatpak/build.sh BUILD_DIR     # the Flatpak from the release's .pck; installs nothing
```

`release` needs a rendering device. The shader baker and the export run under a private display
(`offscreen.sh`), never with `--headless` (decision 0041). It makes:

- `export/walkdown-plant.apk`: arm64-v8a, signed with the plant's own key;
- `export/walkdown-plant-debug.apk`;
- `export/linux/walkdown-plant.x86_64` and `.pck`;
- `export/windows/WalkdownPlant.exe`: the `.pck` is embedded, the exe is not signed. MSIX comes with the first
  release.

The Android key is `~/.config/kks-explorer/signing/walkdown-plant.jks`, with its passwords in
`walkdown-plant.properties` next to it. It is not Walkdown's key (0054). Godot needs the store and key passwords to
be the same.

The content build refuses what it can't draw and names the file, the item and the rule:

- a door in a wall with no door opening;
- a pipe through a wall with no opening;
- a pipe through a stair's walking space;
- a stair or ladder whose ends meet nothing walkable once stairwells and hatches are cut;
- a structure part it has no geometry for.

The build cuts a stairwell into a platform or floor that a stair passes through, and a hatch where a ladder passes.
It adds handrails along edges where nothing walkable continues.

## Run

The app on this laptop: `godot --path apps/plant3d` after `build.sh`. Options go after `--`:

| Option | What it does |
|---|---|
| `--quality=full` or `--quality=lean+vis` | uses that tier |
| `--walk=frames --seconds=600` | the scripted frame-time walk |
| `--walk=climb` | the test's route |
| `--shot=NAME@x,y,z,yaw,pitch;…` | saves PNG views and quits |
| `--map=1` | starts on the overview map |

Controls (R7):

- **Keyboard and mouse:** W A S D to walk, Shift to run. Click the view to capture the mouse, then the mouse looks
  around. F flies (Space and C for up and down), M opens the map, E opens a door, Esc shows the settings.
- **Gamepad:** the sticks walk and look. Y flies, Back opens the map, A opens a door, Start shows the settings.
- **Touch:** two sticks, Godot's own `VirtualJoystick`, driving the same actions as a gamepad's sticks: move on the
  left, look on the right. There are buttons for Fly, Map, Use, Settings, and Up and Down while flying.
- **Ladders:** walk into a ladder facing it to climb it. To go down, step backwards over the edge at its top.
- **Map:** drag to pan, use the wheel or pinch to zoom, and right-drag or turn two fingers to rotate. Tap a floor to
  go there.

## Quality tiers (R9)

The tiers are the bench's measured presets (0041):

- `full` is for laptops (Forward+).
- `lean+vis` is for phones (Mobile renderer). It draws at 60 % resolution with FSR, with a 2048 px shadow atlas and
  shadows to 40 m. Its LOD threshold is 4 px, and `detail` pieces are cut at 3 px.

The Compatibility fallback gets `lean+vis` too, but it has not been measured.

Choosing a tier:

- A choice in the settings wins.
- Phones take `lean+vis`.
- A desktop measures its GPU once per graphics adapter at first start: the `full` tier on the heaviest view, 120
  frames. A median GPU time over 12 ms gives `lean+vis`. The result is kept in `user://settings.cfg`.

## Tests

```
godot --headless --fixed-fps 60 --path apps/plant3d --script res://tests/run_tests.gd [-- --only=test_walk]
```

- `test_walk`: up the 30 m stair tower of HRSG 1, across the roof, up the stack's ladder to +40, and back down to the
  ground. It fails if the walker is stuck for 5 s or falls below the floor it walks on.
- `test_frames_route`: the phone's walk, once.
- `test_builder`: geometry, stair layout, the build's refusals and cuts.
- `test_quality`: picking the tier.
- `test_kit`: every part of `kit.json` is made, with valid meshes at every LOD within its triangle budget, its moving
  nodes and plate points.

Physics runs with the headless renderer.

Frame times on the Note 9: `flock ~/kks-work/build/vm.lock sh -c 'apps/plant3d/phone/frames.sh 285d2a7c153f7ece 600;
adb kill-server'`. Only `io.github.walkdown.plant` is ever installed. The script refuses a locked phone.
