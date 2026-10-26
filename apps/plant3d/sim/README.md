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

**Step time** (`bench_step.gd`, the whole first train, before the water treatment plant and before the generated
program below): about 0.28 ms a step on the laptop, 0.46 ms on CI's runner, 1.4 ms on the Note 9 (fast-forward at
60× needs 600 steps a second: 0.85 of one of its cores).

**With the water treatment plant (W2, 2026-10-23):** the joined model grew from 1,112 to about 1,700 values. Laptop,
the same load for both: 0.57 → 0.80 ms a step over the cold start (1.4×). Note 9, the app's debug export walking with
fast-forward (apps/plant3d/phone/frames.sh, `speed=fast`, 130 s), main against W2: 1.78 → 3.16 ms a step (1.8×), so
the app's fast-forward cap there falls from about 14× to about 8×; the release build's 1.4 ms becomes about 2.5 ms
(estimated by that ratio, not measured).

**Faster, the same bits (2026-10-23).** Step 2 now runs as straight-line GDScript that `_gen_fast` writes from the
compiled program once per model (one statement or a few per node, every slot and argument a number in the code: no
dispatch on the node's kind, no reads of the program's arrays), compiled at the engine's start (about 50 ms on the
laptop) and shared by every engine of that model. The interpreter `_run` stays: step 0, faults' `when` nodes, and
every step if the generated script ever fails to compile (an error, then the same results more slowly). The loops
of steps 3–7 read packed arrays per trip and alarm and skip what can't change anything (no trainer's fault pressed,
no repair asked, an alarm that reads false and is normal), and `fast_forward()`, which the app's clock asks after
every step at fast-forward, looks at normal alarms first (24 → 10 µs). The arithmetic is the same operations on the
same doubles in the same order, so the vectors' digests are unchanged; `tests/test_plant3d_sim.py` runs every
vector through the generated program, the unit and edge runs through the interpreter alone, and gates the step's
cost on the runner at 0.75 ms (`bench_step.gd --max-us`; losing the generated program fails on its own, by the
`PROGRAM` line). Lists past 16 refs and tables past 16 rows run as a loop and a call in the generated script (Godot's
parser recurses into a long expression or `elif` chain).

| | before | after |
|---|---|---|
| laptop, `bench_step.gd` (whole plant with the WTP, cold start / base load) | 0.51 / 0.49 ms | 0.12 / 0.12 ms |
| Note 9, release export, the app walking at fast-forward (`frames.sh`, `speed=fast`, 130 s, two runs each, alternated; the clock's `step_ms`: the step and what follows it in the app) | 1.9 and 2.7 ms | 0.77 and 0.81 ms |
| Note 9, the clock's fast-forward cap (a quarter of a core) | 13× and 9× | 33× and 31× |

(The release APKs for this were exported without the lightmap's bake, which changes nothing the model does.)

**A frame's model work (2026-10-26).** The app's clock (`ui/sim_clock.gd`) runs at most `FRAME_MS` (8 ms) of steps in
a frame, counted from each step's measured cost with the staff's step 9 and what follows it in the app, however long
the frame before was (a frame held for 0.25 s used to give the next a quarter of 0.25 s: 62 ms); in fast-forward it
also stops at 8 ms of real time within the frame, should the steps cost more than their average, and what that leaves
out is not owed. On the Note 9 the model and staff then took at most 7.5 ms in a frame of fast-forward (32 and 13 ms
before). The staff step on the laptop (`bench_step.gd` `staff_step9`): 67 → 50 µs on average, the same bits.
