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
| `builder/` | the content build: `data/plant3d` to `built/` (a scene per area, the ground and the site round the areas, the materials, the sky, the bake scene, `plant.json`, the walking directions' navigation mesh `nav.res` from `nav_bake.gd`). It runs at build time, never at app start. (Not `build/`: the repository ignores every `build/` folder.) `builder/bake/` is the editor plugin that bakes the lightmap |
| `app/` | the app: start and tiers (`main.gd`, `quality.gd`), loading (`plant.gd`), the walker (`player.gd`), doors, the overview map, the touch controls and settings (`hud.gd`), scripted routes (`autopilot.gd`, `routes.gd`), walking directions (`walk_route.gd`) |
| `ui/` | the interaction layer: the engine run at 0.1 s steps (`sim_clock.gd`), equipment cards (`card.gd`), alarms (`alarm_panel.gd`), procedures and tours (`procedure_panel.gd`, `procedure_tracker.gd`), the instructor's faults, bindings on the parts (`bindings.gd`), sounds (`sound_player.gd`), links (`links_in.gd`), the saved run (`autosave.gd`, `run_save.gd`); `plant_ui.gd` ties them together |
| `addons/walkdown_plant_android/` | editor-only: the export plugin that adds the `walkdown-plant://` intent filter to the Android manifest (decision 0056) |
| `msix/` | the MSIX manifest (identity, alias, the `walkdown-plant` protocol); the packaging comes with the first release |
| `sim/` | the behaviour engine (the model's evaluator). It has its own owner; the project hosts it (`walkdown_plant/sim/path` in `project.godot`) |
| `tests/` | the app's tests: `run_tests.gd` runs every `test_*.gd` |
| `phone/frames.sh` | one frame-time run on a phone |
| `flatpak/` | the Flatpak (`io.github._5wHN28Dg.WalkdownPlant`, on `org.godotengine.godot.BaseApp//4.7`) |

## Build

```
apps/plant3d/build.sh                       # content check (ref/plant3d.py), content build, tests
apps/plant3d/build.sh export                # and the exports, headless, unbaked, unsigned, into export/check/ (CI)
tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh bake      # and the lightmap's bake (a GPU, Godot's editor)
tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release   # release exports, shaders baked
apps/plant3d/flatpak/build.sh BUILD_DIR     # the Flatpak from the release's .pck; installs nothing
```

`release` and `bake` need a rendering device; `release` bakes the lightmap before it exports. The shader baker and the export run under a private display
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
| `--scenario=ID` | the scenario the plant starts in (default `cold_iron`) |
| `--procedure=ID` | follows that procedure or tour from the start |
| `--panels=alarms,procedure,card:CODE` | opens these panels |
| `--speed=fast` | starts the plant in fast-forward |
| `walkdown-plant://kks/CODE`, `walkdown-plant://procedure/ID[/STEP]` | a link (docs/PLANT3D.md §6), anywhere on the command line |
| `--fx_off=ssao,fog`, `--fx_on=sdfgi,ssil,volfog,glow` | effects off or on, to measure what each costs |

Controls (R7):

- **Keyboard and mouse:** W A S D to walk, Shift to run. Click the view to capture the mouse, then the mouse looks
  around. F flies (Space and C for up and down), M opens the map, E opens a door, Esc shows the settings.
- **Gamepad:** the sticks walk and look. Y flies, Back opens the map, A opens a door, Start shows the settings, X goes
  back to the control room.
- **Touch:** two sticks, Godot's own `VirtualJoystick`, driving the same actions as a gamepad's sticks: move on the
  left, look on the right. There are buttons for Fly, Map, Use, Settings, and Up and Down while flying.
- **The plant (ui/):** E (gamepad A) or a click or tap on a part opens its card; L (D-pad up) the alarms, P (D-pad
  left) procedures and tours, K (D-pad down) pause and run, the full stop (D-pad right) fast-forward, H (X) back to
  the control room, Esc (B) closes the top panel. The bar under the buttons does the same by touch.
- **Ladders:** walk into a ladder facing it to climb it. To go down, step backwards over the edge at its top.
- **Map:** drag to pan, use the wheel or pinch to zoom, and right-drag or turn two fingers to rotate. Tap a floor to
  go there.

## Operating the plant (ui/)

The plant runs as soon as the app starts, in the `cold_iron` scenario, at 1×. The engine (`sim/`, unchanged)
steps every 0.1 s of plant time whatever the frame rate. Fast-forward is offered while the engine allows it (no
unacknowledged alarm, no active priority 1 alarm, no machine in a step to watch) and stops by itself when that
changes, or when a procedure step is done. It is capped so that the model takes at most a quarter of one core,
from the measured cost of a step: 60× on a laptop, about 18× on the Note 9 (1.4 ms a step).

- **Cards:** the code with its meaning from the plant's key table, where it is (and "Go there"), its state and
  values, its alarms and its operations. An operation is offered where the content's `where` says: within 6 m of the
  equipment for `local`, in the control room for `screen`. Permissives that fail are listed in the content's words;
  a refused operation says why (a failed permissive, the sequence's state, a trip whose cause is still there, a
  value out of range). A 0–1 command is typed in per cent.
- **Alarms:** active ones (unacknowledged first, flashing), shelved ones (10 min, 30 min or 1 h of plant time),
  those suppressed by design, and the latched trips with each group's first out. The horn follows the highest
  unacknowledged priority.
- **Procedures and tours:** the current step's text with its links, the operations it expects (ticked when done),
  why, the equipment pointed at in the plant (a frame and an arrow, and an arrow at the screen's edge with its
  distance); a step ends by itself when its `done` value turns true. "Pause when a step is done" stops the plant
  there. A tour's Next and Back fly to each stop, or the trainee walks with the arrow. A step with `"go": "walk"`
  (every tour stop, most procedure steps) shows the way on foot to what it points at: chevrons on the floors, up and
  down stairs and ladders, from wherever the trainee stands, and the arrow's distance is then the walk's.
- **Instructor mode** (settings): the scenario to restart in and the scenario's trainer faults.
- **Bindings:** the kit's moving pieces are children of the equipment's node named by their channel (`shaft`,
  `blades`, `handwheel` turn about their own Y axis; `stem`, `contacts` move along it by the `travel` meta; `disc`
  turns by the `angle` meta; `needle` from `angle0` to `angle1` about its own Z; `level` scales Y); lamps are
  `lamp_<kind>`. Until the kit has them, small markers stand in. Local displays show their value within 8 m.
- **Sounds:** played from `built/sounds` (tools/plant3d/sounds) when it is there; silent otherwise.
- **Links out:** a course link in a procedure opens Walkdown's course (`walkdown://course/…`); Walkdown takes
  `kks` and `course` links on Android, GNOME and Windows (decision 0058; `ui/links_in.gd` `WALKDOWN_TAKES`). Without
  Walkdown installed, the plant says so.

## Saved runs

A run continues after Android has killed the app or the app was closed (the user, 2026-10-19: a cold start takes 10
minutes and more). `ui/autosave.gd` saves the whole run to `user://run.save`:

- **When:** every 5 s of real time while the run changes (the plant's step, an input, the speed, the procedure's
  progress, the trainee's place or view), and at once when the app goes to the background, loses the focus, is
  closed or Back is pressed (Android: `NOTIFICATION_APPLICATION_PAUSED`; the desktops: focus out, the window
  closed). The periodic save copies the state on the main thread and encodes and writes it on a worker thread; the
  save on going to the background is made at once, on the main thread.
- **What:** the engine's whole state (every script variable of `sim/engine.gd` except those built from the model and
  the scenario: `m`, `sc`, `names`, `ix`, `n`, `timing`, `step_us` and every name beginning with `_`, which is how
  the engine names its compiled program; so the values, the stateful nodes' memory, machines, latched trips and
  first-outs, alarm states with their delay counts, acknowledgements and shelves with their end steps, the faults
  applied, the inputs queued for the next step, every input made and the event log the debrief reads); the
  scenario; the clock's speed, the fast-forward asked for and "pause when a step is done"; the procedure or tour
  (its id) and the tracker's whole state (every script variable but `proc` and `steps`); the last procedure
  followed, kept for the debrief after it was closed (`run`: its id, whether it is the current one, its tracker); the operations' results
  on the cards and those sent and not yet answered; the trainee's position, heading, pitch and whether flying.
  The alarm list's times are rebuilt from the event log. New state in the engine or the tracker is saved with no
  change to the save (`tests/test_run_save.gd`).
- **At start**, a saved run is offered: Continue (the plant, the procedure, the trainee where they were; the run
  then goes on bit for bit as it would have) or New run (a new run in the default scenario, which replaces the save).
  The plant waits, paused, behind the offer (nothing can be walked or worked) and nothing is saved until the trainee
  chooses. A save that can't be continued says why and offers only a new run. A start the command line asks for
  (`walk`, `shot`, `scenario`, `procedure`, `speed`) offers nothing and saves to `user://run-options.save`, never
  over a trainee's run. New run keeps the run it replaces as `run.save.prev` (one step back, by hand).
- **A second window** (a link opened on a desktop while the app runs starts one): `run.save.lock` holds the pid of
  the window that saves to `run.save`, renewed every 5 s; while that window runs, another one offers nothing and saves
  to `run-second.save`. Each process writes its own `.tmp` (`run.save.tmp.<pid>`). Not on Android (one instance).

**The file** (`ui/run_save.gd`), little-endian:

| Bytes | What |
|---|---|
| 8 | `WDPSAVE\n` |
| 4 | the save format, 1 |
| 8 | the payload's length |
| 32 | SHA-256 of the payload |
| … | the payload: one Dictionary in Godot's binary Variant encoding (`var_to_bytes`, no objects), so doubles keep every bit |

The payload's parts, each required, no others: `app` (the app's version: `application/config/version`, `+`, the first 16 hex digits of `built/code.sha256`,
which `build.sh` makes from `sim/*.gd` and the scripts whose state is saved or read back: `ui/run_save.gd`,
`ui/autosave.gd`, `ui/procedure_tracker.gd`, `ui/plant_ui.gd`, `ui/sim_clock.gd`, `app/player.gd`; an export keeps
scripts only compiled, so the app can't hash its code itself. A new build therefore refuses the saves of the one
before), `content`
(SHA-256 over every file of `built/content`, by sorted path, with its length), `scenario`, `saved_unix`, `engine`
(field → value), `clock` (`speed` 0 paused, 1 1×, 2 fast-forward; `ff_want`; `pause_on_hold`), `procedure` (an id,
or `""`), `tracker` (field → value, `{}` without a procedure), `run` (`{}`, or `procedure`, `same`, `tracker`:
`{}` when `same`), `ui` (`results`, `pending`), `player` (`pos` a
Vector3 in Godot's axes, `yaw`, `pitch`, `fly`).

**Written atomically:** the bytes go to `run.save.tmp.<pid>`, which is then renamed over `run.save`: a reader finds the
previous save or the new one, never half of one, whenever the app is stopped. Where a rename can't replace a file
in one step (Windows), a complete `.tmp` beside `run.save` is read too: the newest complete one (by `saved_unix`)
is taken. There is no
fsync (Godot has none): after a power cut right after a save, a file system may hold neither file whole; the app
then says so and starts a new run.

**Loaded strictly:** a file over 64 MiB, a wrong magic, a length that is not the file's, a hash that does not match,
a payload that is not a Dictionary of exactly those parts of those types is refused as damaged; another save format,
another app version or other content is refused as such; so is engine or tracker state whose fields are not this
version's, of other types (where the field is typed: an untyped field takes any value but an object), or (an array the fresh engine holds non-empty, sized by the model) of another length, a
procedure or scenario the plant doesn't have, a step index outside the procedure, a clock, panel record or place
that is not of its kind or not finite; and contents the app indexes with (a machine state or alarm state that
doesn't exist, malformed inputs, events, operations' records or procedure log, a tracker position past the logs)
even under a matching hash. Nothing of a refused save is applied. A save over 64 MiB is not written.

**Cost:** measured by `tests/bench_save.gd` at the end of the cold start (76 events, 37 KB): on this laptop the
copy on the main thread takes 0.11–0.15 ms, encoding 0.5 ms and writing 0.15–0.23 ms. The Note 9 runs the model
5 times slower (1.4 ms a step against 0.28 ms), so about 0.75 ms on its main thread and 4.5 ms in all: the encoding
and the write are kept off the frame.

## Android: a Gradle export

The Android presets are Gradle builds, so that the export plugin can add the intent filter for links (decision 0056).
`build.sh` installs Godot's template into `android/` (ignored by git) from the export templates, pins its Gradle by
SHA-256 and runs it on a JDK 17 (`tools/plant3d/fetch_jdk.sh`; Gradle 8.11 doesn't run on JDK 25). The release is
exported unsigned and signed afterwards with `apksigner` (Android SDK build-tools 35 or later, for `zipalign -P`), so
the key never reaches Gradle; every APK is checked for the intent filter (`aapt2`). Every build dependency Gradle
resolves is checked against `android-gradle-verification.xml` (0056). On the desktops a link opens a second
instance when the app already runs.
`phone/links.sh` checks links on the Note 9 (a cold start and a running app).
## Light, sky and materials (R9, decision 0057)

- **The lightmap** (`builder/lightmap.gd`, `builder/bake/`): every static mesh gets lightmap UV2 at build time
  (Godot's unwrapper, a texel of 0.33 m, 0.5 m on the ground); the bake (Godot bakes only in its editor, on a GPU)
  lights them with the sky, the light the sun bounces, the halls' lamps and the sun's shadow beyond the real-time
  distance (shadowmask). The sun's direct light and sharp shadow stay real-time. Instanced and moving pieces take
  the sky's ambient light, not the bake's probes (one probe per 12 m cell left a blue motor or a red
  handwheel almost black in shade: a trainee must see their colours). Kept as RGBE9995 (no ASTC HDR on the Note 9). A build without the bake (CI)
  lights the plant by the sky and the sun alone.
- **The sky** (`builder/sky.gd`): a CC0 photographed sky (Poly Haven) with its sun taken out; the sun becomes the
  DirectionalLight3D at the photograph's own sky-to-sun ratio. AgX tonemapping, a thin haze.
- **The materials** (`kit/weathered.gdshaderinc`): the CC0 sets with grime, run-off streaks, dust on top faces, rust,
  paint wear where hands go, wet ground round the cooling tower, jointed yards, the road's centre line, drawn bar
  gratings; from one build-made noise in world space.
- **The site** (`builder/site.gd`): concrete yards in the areas' bounds, gravel between, a ring road with kerbs and a
  drain, a boundary wall, the country to the far plane with low hills.
- **Per tier:** laptops add SSAO (low, half size); SSIL, volumetric fog, glow and SDFGI were measured and left out
  (0057). Phones get the bake and the haze.
- `apps/plant3d/about.json` (from `tools/about.py --plant`) lists the CC0 assets; the build packs it.

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
  ground; the condenser pit's stair; every stair and ladder both ways; and the walking directions: from the control
  room the path finder reaches every tour stop and the equipment of every procedure step with `"go": "walk"`, and the
  walker follows those routes, procedure by procedure, stop after stop, and the path finder's ways up and down every
  stair and ladder (about 6.7 km, run; 1.5 minutes). It fails if the walker is stuck for 5 s, falls below the floor
  it walks on, or ends out of reach of the equipment.
- `test_ui_walk_route`: the walking directions in the app (shown, redrawn, found again off the way, hidden in flight
  and by other steps) and the gamepad's X for the control room.
- `test_frames_route`: the phone's walk, once.
- `test_builder`: geometry, stair layout, the build's refusals and cuts.
- `test_quality`: picking the tier.
- `test_kit`: every part of `kit.json` is made, with valid meshes at every LOD within its triangle budget, its moving
  nodes and plate points.
- `test_ui_cold_start`: the cold start driven through the UI only (the procedure panel, cards, the time bar) to base
  load; the engine's inputs, events, step ends and final state must be the reference's (`ref/vectors/plant3d-v1.json`
  `train`).
- `test_run_save`: saved runs: a run saved and put back into a fresh engine continues bit for bit (also with state
  the engine doesn't have yet), damaged and foreign files refused, the atomic write, Continue and New run at start.
  `tests/bench_save.gd` measures a save's cost.
- `test_ui_operate`, `test_ui_alarms`, `test_ui_links`, `test_ui_clock`, `test_ui_parts`: operations offered and
  refused, alarms acknowledged and shelved, links, the clock and its cap, moving parts and sounds.

A test stopped by a script error counts as failed (the runner counts script errors). `tests/ui_shots.gd` saves
screenshots of the UI in use: `tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script
res://tests/ui_shots.gd -- --out=DIR`.
- `test_kit_build`: the built plant's nodes, cells and plates (every valve, inline ones too, carries its tag plate).
- `test_realism`: lightmap UV2 and the bake scene, back faces of walls, the sky's sun, the weathered materials, the
  site, each tier's effects.

Physics runs with the headless renderer.

Frame times on the Note 9: `flock ~/kks-work/build/vm.lock sh -c 'apps/plant3d/phone/frames.sh 285d2a7c153f7ece 600;
adb kill-server'`. Only `io.github.walkdown.plant` is ever installed. The script refuses a locked phone.
