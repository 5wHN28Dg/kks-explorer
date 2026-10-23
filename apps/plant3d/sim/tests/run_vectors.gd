extends SceneTree
## Replays ref/vectors/plant3d-v1.json and plant3d-v2.json (format 2: permits, isolations, the hold node; the water
## treatment plant's start from cold, `wtp`) through the
## app's engine (apps/plant3d/sim) and compares it with the reference (ref/plant3d.py), headless:
##   godot --headless --script apps/plant3d/sim/tests/run_vectors.gd [-- options]
## Options:
##   --vectors=PATH    the vector file (default ref/vectors/plant3d-v1.json of this checkout)
##   --vectors2=PATH   the format 2 vector file (default ref/vectors/plant3d-v2.json); its runs are named v2/…
##   --data=PATH       the first train's content (default data/plant3d)
##   --digests=PATH    also write the SHA-256 of every value at every step of every run, in chunks of 1000 steps
##                     (tests/test_plant3d_sim.py compares them with the reference's: bit for bit)
##   --dump=RUN:FROM:TO   print every value's bits at steps FROM–TO of one run (steps/N, train, hot or a fork's id)
##   --interpreter=1   step every engine with the interpreter (engine.gd _run), not the straight-line program; the
##                     last lines say how many of the engines made here ran each ("PROGRAM straight-line=N interpreter=M")
##   --only=PARTS      some of: valid,steps,links,procedure,train,v2 (default all; procedure and train run both the
##                     cold start, `train`, and the hot restart, `hot`; v2 runs the format 2 file's valid plant,
##                     steps and train forks)
##
## What is compared with the file: every event exactly (kinds, names, numbers and their int/float type, booleans);
## every snapshot's machines, trips, first-out records, alarms (in the model's order), shelved alarms and fast-forward
## exactly; its values to the file's precision (the generator rounds them to 9 decimals, so to within 6e-10 plus the
## last bit of the number). Bit-exactness of every value is what the digests prove.
## Exit code 0 when every vector passed; each failure prints the first divergence of its vector.

const PlantModel = preload("../plant_model.gd")
const PlantEngine = preload("../engine.gd")
const Procedure = preload("../procedure.gd")
const Links = preload("../links.gd")
const JsonStrict = preload("../json_strict.gd")

const CHUNK := 1000

var repo := ""
var opts := {}
var passed := 0
var failed := 0
var digests := {}
var dump_run := ""
var dump_from := 0
var dump_to := -1
var _programs := [0, 0]
var expected := 0       # results the run must give: a script error that skips one fails the run


func _init() -> void:
	quit(1)         # stays the exit code if a script error stops this function
	repo = ProjectSettings.globalize_path(get_script().resource_path).get_base_dir().path_join("../../../..").simplify_path()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	PlantEngine._interpret_only = opts.get("interpreter", "") == "1"
	if opts.has("dump"):
		var d: PackedStringArray = opts["dump"].rsplit(":", true, 2)
		dump_run = d[0]
		dump_from = d[1].to_int()
		dump_to = d[2].to_int()
	var t0 := Time.get_ticks_msec()
	var path: String = opts.get("vectors", repo.path_join("ref/vectors/plant3d-v1.json"))
	var r := JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000)
	if not r.ok:
		_result("read", "%s: %s" % [path, r.error])
		_finish(t0)
		return
	var V: Dictionary = r.value
	var parts: PackedStringArray = opts.get("only", "valid,steps,links,procedure,train,v2").split(",")
	var V2 := {}
	if parts.has("v2"):
		var path2: String = opts.get("vectors2", repo.path_join("ref/vectors/plant3d-v2.json"))
		var r2 := JsonStrict.parse(FileAccess.get_file_as_bytes(path2), 1000)
		if not r2.ok:
			_result("read", "%s: %s" % [path2, r2.error])
			_finish(t0)
			return
		V2 = r2.value
		expected += 1 + V2["steps"].size()
		if V2.has("train"):
			expected += V2["train"]["forks"].size()
		if V2.has("staff"):
			expected += 1 + V2["staff"]["runs"].size()
		if V2.has("day"):
			expected += 1 + V2["day"]["forks"].size()
		if V2.has("wtp"):          # the water treatment plant's start from cold (W2): its procedure, run and forks
			expected += 2 + V2["wtp"]["forks"].size()
	var valid_files: Dictionary = V["valid"][0]["files"]
	# the starts run by their procedures: the cold start (`train`) and the hot restart (`hot`, where the file has it)
	var starts := ["train", "hot"].filter(func(k): return V.has(k))
	for part in parts:
		for st in starts:
			expected += {"procedure": 1, "train": 1 + V[st]["forks"].size()}.get(part, 0)
		expected += {"valid": 1, "steps": V["steps"].size(), "links": V["links"].size()}.get(part, 0)
	if parts.has("valid"):
		_valid(V["valid"][0])
	if parts.has("steps"):
		for k in V["steps"].size():
			_steps(k, V["steps"][k], valid_files)
	if parts.has("links"):
		_links(V["links"], valid_files)
	var train_model = null
	if parts.has("v2"):
		_valid(V2["valid"][0])
		for k in V2["steps"].size():
			_steps(k, V2["steps"][k], V2["valid"][0]["files"], "v2/")
		if V2.has("staff"):
			_staff(V2["staff"])
	if parts.has("procedure") or parts.has("train") or V2.has("train") or V2.has("wtp"):
		train_model = PlantModel.from_dir(opts.get("data", repo.path_join("data/plant3d")))
		if train_model.error != "":
			_result("train model", train_model.error)
			_finish(t0)
			return
	for st in starts:
		if parts.has("procedure"):
			_procedure(V[st], train_model)
		if parts.has("train"):
			_train(V[st], train_model, st)
	if V2.has("train"):
		_train(V2["train"], train_model, "v2/train")
	if V2.has("wtp"):
		_procedure(V2["wtp"], train_model)
		_train(V2["wtp"], train_model, "v2/wtp")
	if V2.has("day"):
		_day(V2["day"], train_model)
	if opts.has("digests"):
		var f := FileAccess.open(opts["digests"], FileAccess.WRITE)
		f.store_string(JSON.stringify(digests, " ", false))
		f.close()
	_finish(t0)


func _finish(t0: int) -> void:
	print("PROGRAM straight-line=%d interpreter=%d" % [_programs[0], _programs[1]])   # how the engines made here stepped
	if passed + failed != expected:
		failed += 1
		print("FAIL the run: %d results, %d expected (a script error above stopped a vector)" % [passed + failed - 1,
				expected])
	print("VECTORS passed=%d failed=%d seconds=%.1f" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0 if failed == 0 and passed > 0 else 1)


func _result(what: String, diff: String) -> void:
	if diff == "":
		passed += 1
		print("PASS ", what)
	else:
		failed += 1
		print("FAIL ", what, ": ", diff)


# ---------------------------------------------------------------- comparing

static func _fmt(x) -> String:
	if typeof(x) == TYPE_FLOAT:
		return "%s (float)" % var_to_str(x)
	if typeof(x) == TYPE_INT:
		return "%d (int)" % x
	return JSON.stringify(x)


## "" when got equals want, else the first difference with its path. Numbers under a "values" key compare to the
## file's precision; every other number exactly, int and float apart (as Python's JSON writer keeps them apart).
static func diff(got, want, path: String, approx: bool = false) -> String:
	var tg := typeof(got)
	var tw := typeof(want)
	if approx and (tg == TYPE_FLOAT or tg == TYPE_INT) and (tw == TYPE_FLOAT or tw == TYPE_INT):
		var g := float(got)
		var w := float(want)
		if absf(g - w) <= 6e-10 + 4.5e-16 * absf(w):
			return ""
		return "%s: %s, the reference %s" % [path, _fmt(got), _fmt(want)]
	if tg != tw:
		return "%s: %s, the reference %s" % [path, _fmt(got), _fmt(want)]
	if tg == TYPE_DICTIONARY:
		var gk: Array = got.keys()
		var wk: Array = want.keys()
		for i in mini(gk.size(), wk.size()):
			if gk[i] != wk[i]:
				return "%s: key %d is %s, the reference's %s (keys %s / %s)" % [path, i, gk[i], wk[i], str(gk), str(wk)]
		if gk.size() != wk.size():
			return "%s: keys %s, the reference's %s" % [path, str(gk), str(wk)]
		for k in gk:
			var d := diff(got[k], want[k], "%s.%s" % [path, k], approx or k == "values")
			if d != "":
				return d
		return ""
	if tg == TYPE_ARRAY:
		for i in mini(got.size(), want.size()):
			var d := diff(got[i], want[i], "%s[%d]" % [path, i], approx)
			if d != "":
				return d
		if got.size() != want.size():
			var extra = got[want.size()] if got.size() > want.size() else want[got.size()]
			return "%s: %d items, the reference %d (first unmatched: %s)" % [path, got.size(), want.size(),
					JSON.stringify(extra)]
		return ""
	if got != want:
		return "%s: %s, the reference %s" % [path, _fmt(got), _fmt(want)]
	return ""


# ---------------------------------------------------------------- digests

var _ctx: HashingContext
var _run := ""
var _chunk_start := 0
var _last := 0


func _hash_begin(run: String, from_step: int) -> void:
	_run = run
	digests[run] = {"from": from_step, "chunks": []}
	_chunk_start = from_step
	_ctx = HashingContext.new()
	_ctx.start(HashingContext.HASH_SHA256)


func _hash(e) -> void:
	var vals: PackedFloat64Array = e.value_array()
	if _run == dump_run and e.step_no >= dump_from and e.step_no <= dump_to:
		print("DUMP %d %s" % [e.step_no, vals.to_byte_array().hex_encode()])
	_ctx.update(vals.to_byte_array())
	_last = e.step_no
	if e.step_no - _chunk_start + 1 == CHUNK:
		_hash_cut()


func _hash_cut() -> void:
	digests[_run]["chunks"].append(_ctx.finish().hex_encode())
	_chunk_start = _last + 1
	_ctx = HashingContext.new()
	_ctx.start(HashingContext.HASH_SHA256)


func _hash_end() -> void:
	if _last >= _chunk_start:
		_hash_cut()
	digests[_run]["to"] = _last


# ---------------------------------------------------------------- the vectors

func _valid(v: Dictionary) -> void:
	var m = PlantModel.from_files(v["files"])
	if m.error != "":
		_result("valid: the synthetic plant loads", m.error)
		return
	var c: Dictionary = v["counts"]
	var got := {"areas": m.areas.size(), "codes": m.codes.size(), "values": m.values.size(), "ops": m.ops.size(),
			"interlocks": m.interlocks.size(), "machines": m.machines.size(), "alarms": m.alarms.size(),
			"trips": m.trips.size(), "bindings": m.bind.size(), "scenarios": m.scenarios.size()}
	if c.has("isolations"):
		got["isolations"] = m.isolations.size()
		got["works"] = m.works.size()
	var want := {}
	for k in got:
		want[k] = c[k]
	var pro := 0
	var tours := 0
	for pid in m.procedures:
		if m.procedures[pid]["kind"] == "tour":
			tours += 1
		else:
			pro += 1
	got["procedures"] = pro
	got["tours"] = tours
	want["procedures"] = c["procedures"]
	want["tours"] = c["tours"]
	_result("valid: the synthetic plant loads with the reference's counts", diff(got, want, "counts"))


## Inputs in step order, those of one step in file order (a stable sort, as the reference's sorted()).
static func by_step(items: Array) -> Array:
	var keyed := []
	for k in items.size():
		keyed.append([items[k][0], k])
	keyed.sort()
	var out := []
	for x in keyed:
		out.append(items[x[1]])
	return out


func _apply_due(e, inputs: Array, i: int) -> int:
	while i < inputs.size() and inputs[i][0] == e.step_no + 1:
		e.apply_input(inputs[i])
		i += 1
	return i


## Asks each of `effects` ([step, work, point, answer], §15.6) that falls at the run's step, after that step's inputs
## are made and before it is stepped; appends [step, work, point, the engine's answer] to `got`.
func _ask(e, effects: Array, got: Array) -> void:
	for q in effects:
		if int(q[0]) == e.step_no:
			got.append([q[0], q[1], q[2], e.lock_effects(q[1], int(q[2]))])


func _steps(k: int, s: Dictionary, valid_files: Dictionary, prefix: String = "") -> void:
	var files := valid_files.duplicate()
	files["model/a1.json"] = s["model"]
	files["scenarios/s1.json"] = s["scenario"]
	files.erase("procedures/p1.json")
	files.erase("screens.json")
	var name := "%ssteps/%d (%s)" % [prefix, k, s["why"]]
	var m = PlantModel.from_files(files)
	if m.error != "":
		_result(name, m.error)
		return
	var e = PlantEngine.new(m, "s1")
	_programs[0 if e._fast != null else 1] += 1
	var run := "%ssteps/%d" % [prefix, k]
	_hash_begin(run, 0)
	_hash(e)
	var states: Array = s["states"]
	var d := diff(e.snapshot(), states[0], "step 0")
	var i := 0
	var asked := []
	while d == "" and e.step_no < states.size() - 1:
		i = _apply_due(e, s["inputs"], i)
		_ask(e, s.get("effects", []), asked)
		e.step()
		_hash(e)
		d = diff(e.snapshot(), states[e.step_no], "step %d" % e.step_no)
	_hash_end()
	if d == "" and i != s["inputs"].size():
		d = "inputs after the last step"
	if d == "":
		d = diff(e.events, s["events"], "events")
	if d == "":
		d = diff(asked, s.get("effects", []), "what a lock would do")
	_result(name, d)


## Format 2's staff (§16–§17): the synthetic plant with staff loads with the reference's counts, and each run replays
## from its inputs: every event (a read's value to the file's precision, everything else exactly) and a snapshot
## every `every` steps.
func _staff(st: Dictionary) -> void:
	var m = PlantModel.from_files(st["files"])
	if m.error != "" or m.staff == null:
		_result("v2/staff: the plant with staff loads", m.error if m.error != "" else "no staff")
		return
	var c: Dictionary = st["counts"]
	var sm = m.staff
	var got := {"people": sm.people.size(), "roles": sm.roles.size(), "places": sm.places.size(),
			"points": sm.points.size(), "ways": sm.ways.size(), "tasks": sm.tasks.size(),
			"reactions": sm.reactions.size()}
	var want := {}
	for k in got:
		want[k] = c[k]
	_result("v2/staff: the plant with staff loads with the reference's counts", diff(got, want, "counts"))
	for k in st["runs"].size():
		_staff_run(k, st["runs"][k], st["files"])


func _staff_run(k: int, r: Dictionary, base: Dictionary) -> void:
	var files := base.duplicate()
	files["scenarios/s1.json"] = r["scenario"]
	if r["staff"] != null:
		files["staff.json"] = r["staff"]
	var name := "v2/staff/%d (%s)" % [k, r["why"].left(80)]
	var m = PlantModel.from_files(files)
	if m.error != "":
		_result(name, m.error)
		return
	var e = PlantEngine.new(m, "s1")
	var run := "v2/staff/%d" % k
	_hash_begin(run, 0)
	_hash(e)
	var states: Array = r["states"]
	var every: int = r["every"]
	var until: int = r["until"]
	var d := diff(e.snapshot(), states[0], "step 0")
	var inputs := by_step(r["inputs"])
	var i := 0
	var si := 1
	while d == "" and e.step_no < until:
		i = _apply_due(e, inputs, i)
		e.step()
		_hash(e)
		if e.step_no % every == 0 or e.step_no == until:
			d = diff(e.snapshot(), states[si], "step %d" % e.step_no)
			si += 1
	_hash_end()
	if d == "" and i != inputs.size():
		d = "inputs after the last step"
	if d == "":
		d = diff(_reads_as(e.events, r["events"]), r["events"], "events")
	_result(name, d)


## The first train's day with its staff (§19 `day`): the run from the scenario's start (every event, a snapshot every
## clock hour) and each run with a trainee or a fault (every event).
func _day(d: Dictionary, m) -> void:
	var e = PlantEngine.new(m, d["scenario"])
	_hash_begin("v2/day", 0)
	_hash(e)
	var states: Array = d["states"]
	var df := diff(e.snapshot(false), states[0], "day step 0")
	var si := 1
	while df == "" and e.step_no < d["until"]:
		e.step()
		_hash(e)
		if e.step_no % int(d["every"]) == 0:
			df = diff(e.snapshot(false), states[si], "day step %d" % e.step_no)
			si += 1
	_hash_end()
	if df == "":
		df = diff(_reads_as(e.events, d["events"]), d["events"], "day events")
	_result("v2/day (%d steps)" % d["until"], df)
	for f in d["forks"]:
		var x = PlantEngine.new(m, d["scenario"])
		var inputs := by_step(f["inputs"])
		var i := 0
		_hash_begin("v2/day/" + f["id"], 0)
		_hash(x)
		while x.step_no < f["until"]:
			i = _apply_due(x, inputs, i)
			x.step()
			_hash(x)
		_hash_end()
		var fd := diff(_reads_as(x.events, f["events"]), f["events"], "events")
		if fd == "":
			fd = diff(x.snapshot(false), f["end"], "end")
		_result("v2/day/" + f["id"], fd)


## The events with each read's value replaced by the reference's when it is within the file's precision (the file
## rounds numbers to 9 decimals; the value itself is a model value, which the digests compare bit for bit).
static func _reads_as(got: Array, want: Array) -> Array:
	var out := []
	for k in got.size():
		var g: Array = got[k]
		if k < want.size() and g.size() == 6 and g[1] == "read" and want[k].size() == 6 and want[k][1] == "read" \
				and diff(g[4], want[k][4], "", true) == "":
			g = g.duplicate()
			g[4] = want[k][4]
		out.append(g)
	return out


func _links(links: Array, valid_files: Dictionary) -> void:
	var m = PlantModel.from_files(valid_files)
	for x in links:
		_result("link " + x["link"], diff(Links.read_link(x["link"], m), x["expect"], "opens"))


func _procedure(t: Dictionary, m) -> void:
	var r := Procedure.run(m, t["procedure"])
	var d: String = r.error
	var e = r.engine
	if d == "":
		d = diff(r.log, t["steps"], "procedure steps")
	if d == "":
		d = diff(e.inputs, t["inputs"], "inputs")
	if d == "":
		d = diff(e.events, t["events"], "events")
	if d == "":
		d = diff(e.step_no, t["until"], "last step")
	_result("procedure %s run as a trainee: its inputs, steps and events" % t["procedure"], d)


func _train(t: Dictionary, m, run: String) -> void:
	var e = PlantEngine.new(m, t["scenario"])
	_programs[0 if e._fast != null else 1] += 1
	var forks: Array = t["forks"]
	var bases := {}
	for f in forks:
		bases[int(f["base_step"])] = null
	var snaps: Array = t.get("snapshots", [])
	var whole: bool = t.has("snapshots")     # format 2's train holds the forks only (and the inputs to reach them)
	var si := 0
	var inputs := by_step(t["inputs"])
	var i := 0
	var d := ""
	var until: int = t["until"]
	var every: int = t.get("snapshot_every", 1)
	_hash_begin(run, 0)
	_hash(e)
	while e.step_no < until:
		if bases.has(e.step_no):
			bases[e.step_no] = e.clone()
		i = _apply_due(e, inputs, i)
		e.step()
		_hash(e)
		if whole and d == "" and (e.step_no % every == 0 or e.step_no == until):
			if si >= snaps.size():
				d = "step %d: more snapshots than the reference" % e.step_no
			else:
				d = diff(e.snapshot(), snaps[si], "step %d" % e.step_no)
			si += 1
	_hash_end()
	if bases.has(until):
		bases[until] = e.clone()
	if d == "" and i != inputs.size():
		d = "inputs after the last step"
	if d == "" and si != snaps.size():
		d = "%d snapshots, the reference %d" % [si, snaps.size()]
	if d == "" and whole:
		d = diff(e.events, t["events"], "events")
	if whole:
		_result("%s: %s replayed from its inputs (%d steps, %d snapshots)" % [run, t["procedure"], until,
				snaps.size()], d)
	elif d != "":
		_result("%s: %s replayed from its inputs" % [run, t["procedure"]], d)
	for f in forks:
		var x = bases[int(f["base_step"])].clone()
		var n0: int = x.events.size()
		var fin := by_step(f["inputs"])
		var j := 0
		var asked := []
		_hash_begin(("v2/" if run.begins_with("v2/") else "") + f["id"], x.step_no + 1)
		while x.step_no < int(f["until"]):
			j = _apply_due(x, fin, j)
			_ask(x, f.get("effects", []), asked)
			x.step()
			_hash(x)
		_hash_end()
		var fd := ""
		if j != fin.size():
			fd = "inputs after the end"
		if fd == "":
			fd = diff(x.events.slice(n0), f["events"], "events")
		if fd == "":
			fd = diff(x.snapshot(false), f["end"], "end")
		if fd == "":
			fd = diff(asked, f.get("effects", []), "what a lock would do")
		_result("fork " + f["id"], fd)
