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
| `app/` | the app: start and tiers (`main.gd`, `quality.gd`), loading (`plant.gd`), the walker (`player.gd`), doors, the overview map, the touch controls and settings (`hud.gd`), About (`about.gd`), scripted routes (`autopilot.gd`, `routes.gd`), walking directions (`walk_route.gd`) |
| `ui/` | the interaction layer: the engine run at 0.1 s steps (`sim_clock.gd`), equipment cards (`card.gd`), alarms (`alarm_panel.gd`), procedures and tours (`procedure_panel.gd`, `procedure_tracker.gd`), the instructor's faults, bindings on the parts (`bindings.gd`), sounds (`sound_player.gd`), links (`links_in.gd`), the saved run (`autosave.gd`, `run_save.gd`); `plant_ui.gd` ties them together |
| `addons/walkdown_plant_android/` | editor-only: the export plugin that adds the `walkdown-plant://` intent filter to the Android manifest (decision 0056) |
| `msix/` | the MSIX: its manifest (identity, alias, the `walkdown-plant` protocol), `make-msix.sh` (the package, as Walkdown's), `logos.gd` (the logos from `icon.svg`) |
| `sim/` | the behaviour engine (the model's evaluator). It has its own owner; the project hosts it (`walkdown_plant/sim/path` in `project.godot`) |
| `tests/` | the app's tests: `run_tests.gd` runs every `test_*.gd` |
| `phone/frames.sh` | one frame-time run on a phone |
| `flatpak/` | the Flatpak (`io.github._5wHN28Dg.WalkdownPlant`, on `org.godotengine.godot.BaseApp//4.7`); `build.sh` makes its AppStream release entry from the version |

## Build

```
apps/plant3d/build.sh                       # content check (ref/plant3d.py), content build, tests
apps/plant3d/build.sh export                # and the exports, headless, unbaked, unsigned, into export/check/ (CI)
tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh bake      # and the lightmap's bake (a GPU, Godot's editor)
tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release   # release exports, shaders baked
apps/plant3d/flatpak/build.sh BUILD_DIR     # the Flatpak from the release's .pck; installs nothing
apps/plant3d/msix/make-msix.sh VM_IP CERT.pfx OUT.msix   # the MSIX from the release's exe (a Windows VM packs it)
```

`release` and `bake` need a rendering device; `release` bakes the lightmap before it exports. The shader baker and the export run under a private display
(`offscreen.sh`), never with `--headless` (decision 0041). Before the bake it gives the editor an empty script
documentation cache (`builder/bake/script_doc_cache.gd`): on a fresh checkout the editor otherwise loads every script
on a thread of its own while the bake opens its scene, and crashed (6 of 7 bakes, 2026-10-20). It makes:

- `export/walkdown-plant.apk`: arm64-v8a, signed with the plant's own key;
- `export/walkdown-plant-debug.apk`;
- `export/linux/walkdown-plant.x86_64` and `.pck`;
- `export/windows/WalkdownPlant.exe` and `export/windows-arm64/WalkdownPlant.exe`: the `.pck` is embedded, the exe
  is not signed; the MSIX packages carry them.

Every build writes `built/build_info.json`: the commit it was made of and whether the checkout had changes. About
shows it, and the release tool finds it inside the APK and the exe.

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
| `--walk=screens` | the control room's screens, each in turn for 10 s: their frame cost (`MIMIC` line) |
| `--shot=NAME@x,y,z,yaw,pitch;…` | saves PNG views and quits |
| `--map=1` | starts on the overview map |
| `--scenario=ID` | the scenario the plant starts in (default `cold_iron`) |
| `--procedure=ID` | follows that procedure or tour from the start |
| `--panels=alarms,procedure,card:CODE` | opens these panels |
| `--speed=fast` | starts the plant in fast-forward |
| `walkdown-plant://kks/CODE`, `walkdown-plant://procedure/ID[/STEP]` | a link (docs/PLANT3D.md §6), anywhere on the command line; a start with a link takes none of the options above (a crafted link could add its own) |
| `--fx_off=fog,lightmap,shadow`, `--fx_on=ssao,sdfgi,ssil,volfog,glow` | effects off or on, to measure what each costs |
| `--probe=1` | (with a walk) `frames.csv` beside `result.txt`: per frame the physics steps, the scripts, the draw (the render thread and any wait for the GPU) and the GPU time (`app/frame_probe.gd`) |
| `--pipeline_save_mb=N` | saves the pipeline cache every N MB of new pipelines (the project: 0.25) |

Controls (R7):

- **Keyboard and mouse:** W A S D to walk, Shift to run. Click the view to capture the mouse, then the mouse looks
  around. F flies (Space and C for up and down), M opens the map, E opens a door, Esc shows the settings.
- **Gamepad:** the sticks walk and look. The left stick is analogue: pushed a little it steps slowly, about three
  quarters of the way it walks, all the way it jogs; clicking it runs. Y flies, Back opens the map, A opens a door, Start shows the settings, X goes
  back to the control room.
- **Touch:** two sticks, Godot's own `VirtualJoystick`, driving the same actions as a gamepad's sticks: move on the
  left (analogue, as the gamepad's), look on the right. There are buttons for Fly, Map, Use, Settings, and Up and Down while flying.
- **The plant (ui/):** E (gamepad A) or a click or tap on a part opens its card; L (D-pad up) the alarms, P (D-pad
  left) procedures and tours, T the permits to work (gamepad: a card's permit button or the procedures panel), K
  (D-pad down) pause and run, the full stop (D-pad right) fast-forward, H (X) to the control room and its screens,
  Esc (B) closes the top panel. The bar under the buttons does the same by touch.
- **The control room screens:** the arrows (D-pad) move between items, Enter (A) opens one, Page Up and Down (LB
  and RB) change screen, + and − zoom; by touch, drag to pan, pinch to zoom, tap to open.
- **Walking and running** (`app/player.gd`): a slow step 0.5 m/s, a walk 1.4 m/s (the settings' "Walking pace":
  slow 1.1, normal 1.4, brisk 1.7), a jog 3 m/s (a stick all the way), a run 4 m/s (Shift or the stick's click). Keys
  walk at the pace. "Run key toggles" in the settings makes Shift and the stick's click switch running on and off
  (for players who can't hold a key); a toggled run ends when the walker stops. The walker speeds up at 4 m/s² and
  slows down or turns at 10 m/s². On a stair it goes at most 0.8 m/s in plan walking and 1.4 running; a ladder is
  climbed at 0.8 m/s whatever the gait. Footsteps follow the speed: longer strides the faster (about 2 a second at a
  walk, 3 running), softer slow steps and louder running ones. The eye dips and sways at the footsteps' rate while
  walking, unless "Reduced motion" is on. Touch has no run button: its stick goes up to a jog. There is no crouching.
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
- **Control room screens** (`ui/mimic.gd`, `ui/screens_model.gd`, `ui/trends.gd`; docs/PLANT3D.md §7.11): the
  Control room button (H, gamepad X) and the operator desks open them, in the control room only. An overview of the
  train (key values with their trends, a tile per screen with its drives and alarms) and a screen per system, made
  from the model and `screens.json`: drives, valves, breakers and sequences with their state, values with their
  units, what the next operation needs, alarms by priority (on the item, the tab and the banner), trends. Grey,
  with colour only for the abnormal (ISA-101). A tap on an item opens its card beside the screen: the same
  operations, permissives and refusals. Redrawn 4 times a second, not every frame; a trend keeps 20 minutes of plant
  time, a sample every 5 s.
- **Alarms:** active ones (unacknowledged first, flashing), shelved ones (10 min, 30 min or 1 h of plant time),
  those suppressed by design, and the latched trips with each group's first out. The horn follows the highest
  unacknowledged priority.
- **Procedures and tours:** the current step's text with its links, the operations it expects (ticked when done),
  why, the equipment pointed at in the plant (a frame and an arrow, and an arrow at the screen's edge with its
  distance); a step ends by itself when its `done` value turns true. "Pause when a step is done" stops the plant
  there. A tour's Next and Back fly to each stop, or the trainee walks with the arrow. A step with `"go": "walk"`
  (every tour stop, most procedure steps) shows the way on foot to what it points at: chevrons on the floors, up and
  down stairs and ladders, from wherever the trainee stands, and the arrow's distance is then the walk's.
- **Instructor mode** (settings): the scenario to restart in (`cold_iron`, `hot_restart`) and the scenario's trainer
  faults: Apply, then Repair (a repaired fault can be applied again). The trainee repairs a fault at its equipment
  too: the card there offers it within reach while the fault is applied. The debrief lists every repair.
- **Permits to work** (`ui/permit_panel.gd`, `ui/permits.gd`; docs/PLANT3D.md §15): the plant's works and their
  permits. A work's form shows its number (PTW-0001), state, steps, its isolation's points with how each is made safe
  and which are locked, the next actions and the history. In free mode the trainee plays each role in turn (the
  button says whose step it is: the maintenance supervisor requests, the shift supervisor approves, issues and closes,
  the technician accepts, finishes and hands back). Each point is locked and tagged at its equipment (within reach,
  as a local operation; Go there flies there); the permit is isolated when the last lock is on and de-isolated when
  the last is off. A locked code refuses its operations (the card says why), skips every automatic write (a standby
  pump's auto-start) and suppresses its alarms; an isolated transmitter holds its reading and votes tripped. The
  screens and cards show a padlock and the permit's number; the debrief has a Permits tab.
- **Handwheels:** a CW pump's discharge valve whose actuator has lost its supply is worked at the valve: Open or Close
  by handwheel, Stop turning (five minutes over the full travel).
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
- **Per tier:** both get the bake and the haze. SSAO, SSIL, volumetric fog, glow and SDFGI were measured on the
  laptop and left out (0057; SSAO cost the full tier its 60 fps).
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
  stair and ladder (about 6.7 km, run; 2.5 minutes). It fails if the walker is stuck for 5 s, falls below the floor
  it walks on, or ends out of reach of the equipment.
- `test_gait`: walking and running: a stick's push to a speed, keys at the pace, Shift and the stick's click (held and
  toggled), a touch stick, gradual speeding up and slowing down, the settings' pace, a stair's and a ladder's limits
  running and walking, the footsteps' stride and level, the head bob and reduced motion. `test_walk` walks every
  stair and ladder walking, running and at the slow pace; `test_gait` climbs a flight at the slowest step (0.5 m/s).
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
- `test_ui_screens`: the control room screens: every code of the model on exactly one screen or left out with its
  reason, a value added to the model landing on its screen, reached only in the control room (button, desks, Esc),
  redrawn at a few hertz, states and alarms that follow the plant, and operating from a screen through the card
  (a refused start, then the same start done); legible: every code whole, every name in two lines, a readable zoom
  at opening (the overview at its key values on a phone), no word over the screens just opened; `walk=screens`.
  `test_ui_screens_cold_start`: `test_ui_cold_start` with every
  operation the screens offer made by a click on its screen.
- `test_run_save`: saved runs: a run saved and put back into a fresh engine continues bit for bit (also with state
  the engine doesn't have yet), damaged and foreign files refused, the atomic write, Continue and New run at start.
  `tests/bench_save.gd` measures a save's cost.
- `test_ui_operate`, `test_ui_alarms`, `test_ui_links`, `test_ui_clock`, `test_ui_parts`: operations offered and
  refused, alarms acknowledged and shelved, links, the clock and its cap, moving parts and sounds.
- `test_ui_repair`: a fault applied and repaired from the instructor's panel and applied again, repaired by the
  trainee at its equipment (within reach only), a CW valve without its supply opened by its handwheel and stopped,
  the debrief's repairs, a run saved with a repair waiting.

A test stopped by a script error counts as failed (the runner counts script errors). `tests/ui_shots.gd` saves
screenshots of the UI in use: `tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script
res://tests/ui_shots.gd -- --out=DIR`; `tests/mimic_shots.gd` (same arguments, `--phone` at
`--resolution 2960x1440` for the phone's scale) saves every control room screen and prints what drawing them costs.
On the Note 9 (2026-10-19, debug build, `WALK_EXTRA="walk=screens\n" phone/frames.sh`, 100 s): frames median
16.7 ms, 99.95 % at 30 fps or more; the screens' pieces drew in 0.38 ms a frame on average, 71 of 5,969 frames over
2 ms, 13 ms at most (a screen's first drawing when it is shown). That counts the pieces only: the tabs, the alarm
banner and the flow lines are drawn besides, so the frame times above are the measure.
- `test_about`: About from the settings (gamepad A), what it shows (version, commit, the assets with their licence,
  Godot's notices), scrolling by D-pad, stick, Page Down and Home, and back by Esc, B and Back.
- `test_kit_build`: the built plant's nodes, cells and plates (every valve, inline ones too, carries its tag plate).
- `test_look`: the polish pass (0057): ceilings (liner, roof steel, lamps hung from purlins between rafters, decking
  and beams under decks, clear of machines through them), plinths and flashings, louvres and windows, the palisade
  seen through and its streaks' top, the shader's streaks and its ruts on every tier, the retroreflective sign board.
- `test_photo`: the photo pass (0057): floors by finish (tiles, bare concrete, gratings over the gas turbine's
  trenches), the tiles' sheen, roof trusses, the halls' frame and overhead cranes clear of the trusses, the
  transformers' firewalls, gravelled yards, striped kerbs, the pipes' stencilled
  names drawn as a sign's text, black valves and grey actuators.
- `test_realism`: lightmap UV2 and the bake scene, back faces of walls, the sky's sun, the weathered materials, the
  site, each tier's effects.
- `test_bake_prep`: what `build.sh` does before the bake (CI cannot bake): the editor's script documentation cache.
- `test_frame_probe`: `probe=1`'s frames.csv and `pipeline_save_mb`.

Physics runs with the headless renderer.

Frame times on the laptop: `tools/plant3d/bench/offscreen.sh apps/plant3d/export/linux/walkdown-plant.x86_64 --resolution
1600x900 -- --quality=full --walk=frames --seconds=600 --out=DIR` (add `--probe=1` for where the time goes), with
nothing else on the GPU: `python3 tools/plant3d/bench/gpu_clients.py 10` before and during the run lists what else
uses it (an idle editor's GPU work cost the full tier its 60 fps, decision 0057).

Frame times on the Note 9: `flock ~/kks-work/build/vm.lock sh -c 'apps/plant3d/phone/frames.sh 285d2a7c153f7ece 600;
adb kill-server'`. Only `io.github.walkdown.plant` is ever installed. The script refuses a locked phone.

## About

Settings → About (gamepad: A on the focused button) shows the version (`application/config/version` in
`project.godot`), the commit of the build and whether it had local changes, the licence and source, the CC0 assets
of `about.json` (from `tools/about.py --plant`; the build copies it to `built/about.json`) with the CC0 text, and the
Godot Engine's licence, copyright notices and third-party licences (`Engine.get_license_text()`,
`get_copyright_info()`, `get_license_info()`). It scrolls by touch, the wheel, arrows or W/S, Page Up/Down, Home and
End, the D-pad and either stick; Esc, B, Start or Back returns to the settings.

## Releasing

A plant release is a GitHub release of this repository tagged `plant-vX.Y.Z`, published **not as latest**:
GitHub's latest release is what Walkdown's updater reads, so it must stay Walkdown's (decision 0054 §8). The whole
procedure, with the keys, is on the wiki's Releasing page. In short, from a clean checkout of the release commit:

1. `python3 tools/plant_release.py bump X.Y.Z` (project.godot and the Android version name and code), commit, push,
   merge; wait for CI.
2. `tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release`: the signed APK, the Linux `.pck`, both Windows
   exes, baked.
3. `apps/plant3d/msix/make-msix.sh VM_IP ~/.config/kks-explorer/signing/windows-msix.pfx WalkdownPlant.msix`
   (`KKS_MSIX_PASS` from `windows-msix.password`), and with `KKS_WIN_ARCH=aarch64` `WalkdownPlant-arm64.msix`; copy
   `windows-msix.cer` next to them. Tests use `make-msix.sh --test-cert DIR` only.
4. `apps/plant3d/flatpak/build.sh --bundle walkdown-plant.flatpak BUILD_DIR --disable-rofiles-fuse` (the option where FUSE is not available to flatpak-builder, as for Walkdown).
5. `python3 tools/plant_release.py X.Y.Z DIR --notes notes.md`: a dry run that checks everything; then the same with
   `--publish`. It refuses unless the version is the app's, the checkout is clean and on origin/main (and `plant-vX.Y.Z` on
   origin, if there, names it), the APK and both MSIX packages carry the commit without local changes (the MSIX signed as `CN=Walkdown`, for the architecture its name says), every CI run
   on the commit has passed, and GitHub's latest release is a Walkdown `vX.Y.Z`; it creates the release with
   `--latest=false` and checks afterwards that the latest release is still Walkdown's (and makes it latest again if
   not). `tools/release.py` makes Walkdown's own releases latest explicitly, behind the same checks.
   The release commit must have had the Walkdown Plant app workflow run on it (it runs only when plant files change):
   release the merge that bumped the version, or start the workflow on a branch whose head is that commit
   (`gh workflow run plant3d-app.yml --ref BRANCH`). The tools also check the APK's signer (`CN=Walkdown Plant`,
   with the Android SDK's apksigner), the MSIX packages' publisher, architecture, version and signature, and
   `windows-msix.cer`; the bundle refuses a `.pck` not built from the checkout's commit without changes.
