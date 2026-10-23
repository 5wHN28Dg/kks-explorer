# Walkdown Plant: the behaviour engine (GDScript)

The plant's behaviour model (docs/PLANT3D.md §7, and format 2's permits, isolations and `hold` node, §15, and its staff,
§16–§17) as the app runs it, bit for bit with the reference (`ref/plant3d.py`, `ref/plant3d_staff.py`) on
`ref/vectors/plant3d-v1.json` and `plant3d-v2.json` (decision 0054 §10, 0062).

| File | What it is |
|---|---|
| `json_strict.gd` | strict JSON reader (the rules of `ref/sjson.py`), numbers correctly rounded like Python's `float()`: Godot's `JSON` and `String.to_float` are off by a unit in the last place for some 17-digit numbers, one of which is in the first train's model |
| `plant_model.gd` | loads `data/plant3d` (or a `{path: text}` set of files): the joined model, scenarios, procedures and the plant's codes |
| `engine.gd` | the 0.1 s step of §7.10: values, operations and permissives, interlocks, machines, trips with first-out, alarms with suppression and shelving, faults; permits to work, locks and the writes they skip (§15, free mode); snapshots and fast-forward |
| `staff.gd` | staff.json (§16) as the engine runs it, and the staff step (step 9, §17): duties, routines, queues, routes by the `next` table, reservations, reactions, the task steps, the trainee's person, jumps, the per-person random streams. It holds only what is built from the content; the run's staff state is the engine's `st_`/`sp_` variables, so saved runs and clones keep it |
| `procedure.gd` | a procedure run in the model alone, as a trainee who does each step |
| `links.gd` | `walkdown-plant://` links (§6) |

```gdscript
const PlantModel = preload("res://sim/plant_model.gd")
const PlantEngine = preload("res://sim/engine.gd")
var m = PlantModel.from_dir("res://…/plant3d")     # m.error is "" when it loaded
var e = PlantEngine.new(m, "cold_iron")
e.op("30PAC10AP001", "start")                    # takes effect in the next step
e.step()
```

The scripts preload each other by relative path, so they work from the app's project (`res://sim/`) and from the
test runner, which loads them by file path without a project.

## Tests

With the pinned Godot (`tools/plant3d/bench/fetch_godot.sh`; CI: `.github/workflows/plant3d.yml`):

```sh
python3 -m unittest -v tests.test_plant3d_sim        # everything below, against the Python reference
godot --headless --script apps/plant3d/sim/tests/run_vectors.gd     # the vectors alone (about 1.5 minutes here)
godot --headless --script apps/plant3d/sim/tests/bench_step.gd      # the model's step time
```

`run_vectors.gd` compares events exactly and snapshots to the vector file's precision (it rounds to 9 decimals); the
Python test compares a SHA-256 of every value at every step with the reference's, so a single different bit fails
and is reported at its step and value. `tests/` holds a `.gdignore`: the app's editor and exports leave it out.

**Bit-exactness and the platform.** Every operation is an IEEE double operation in the reference's order, except a
lag's factor 1 − e^(−0.1/τ), which calls the C library's `exp` on both sides. Verified: glibc (this laptop, CI) and
the Note 9's bionic (Android 10, 2026-10-16: every value at every step of every vector run gave the laptop's
digests). Windows (its CRT's `exp`) is not run yet; if it ever differs, the build (0054) can store the factors
computed on Linux in the compiled model.

**Where there is no reference result.** The claim covers what the reference can run: content whose values stay finite
(the validator bounds each number below 10⁹, but a product of many can overflow, and the reference then raises in a
`select` or `wrap`), and inputs whose names are text or null and whose values are numbers, booleans or null (the
reference raises on, for example, a list as an alarm name). There the GDScript keeps going without a defined result.

**Step time** (`bench_step.gd`, the whole first train): about 0.28 ms a step on the laptop, 0.46 ms on CI's runner,
1.4 ms on the Note 9 (fast-forward at 60× needs 600 steps a second: 0.85 of one of its cores).
